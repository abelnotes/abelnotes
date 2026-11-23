import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/platform/io.dart' show File;
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart' show decodePageBytes;
import 'package:abelnotes/features/search/ink_decode.dart';
import 'package:abelnotes/features/search/ink_recognizer.dart';
import 'package:abelnotes/features/search/ink_text.dart';
import 'package:abelnotes/features/search/page_text.dart';
import 'package:abelnotes/features/search/region_router.dart';
import 'package:abelnotes/features/search/search_index.dart';
import 'package:abelnotes/shared/utils/text_fold.dart';

/// How much indexing work is waiting, for the "Indexing notes" line.
class IndexStatus {
  final int pending;
  final bool reconciling;
  const IndexStatus(this.pending, this.reconciling);
  bool get busy => pending > 0 || reconciling;
}

class _Job {
  final Set<String> force = {};
  bool removed = false;
  bool fromEvent = false;
}

typedef _Todo = ({
  String file,
  String path,
  String? pageId,
  int index,
  String? chapterId,
  String stamp,
});

const _chunk = 8;

/// The handwriting model handed to the extraction isolate; [router] keeps
/// lines that are not text (formulas, circuits) away from OCR.
typedef InkModel = ({
  Uint8List bytes,
  String metaJson,
  String version,
  String? lexicon,
  Uint8List? router,
});

/// Handwriting segments worth reading: [router] says they may be text.
bool Function(InkSegment) ocrGate(RegionRouter router) =>
    (seg) => (router.classify(seg.strokes)?.text ?? 1) >= ocrTextThreshold;

/// The text of each page (with recognised handwriting when [ink] is given),
/// null for one that does not parse.
List<PageText?> _extractBatch(
    ({
      List<Uint8List> pages,
      Uint8List? model,
      String? meta,
      String? lexicon,
      Uint8List? router,
    }) job) {
  InkRecognizer? rec;
  RegionRouter? router;
  if (job.model != null && job.meta != null) {
    rec = InkRecognizer.open(job.model!,
        InkModelMeta.fromJson(jsonDecode(job.meta!) as Map<String, dynamic>),
        lexicon: job.lexicon == null ? null : InkLexicon.parse(job.lexicon!));
    if (rec != null && job.router != null) router = RegionRouter.open(job.router!);
  }
  try {
    return [
      for (final b in job.pages)
        () {
          try {
            final text = extractPageTextFromBytes(b);
            if (rec == null) return text;
            return text.withInk(rec.recognizePage(decodePageBytes(b),
                keep: router == null ? null : ocrGate(router)));
          } on FormatException {
            return null;
          } catch (_) {
            // Handwriting failed on this page: keep its typed text.
            try {
              return extractPageTextFromBytes(b);
            } on FormatException {
              return null;
            }
          }
        }(),
    ];
  } finally {
    rec?.dispose();
    router?.dispose();
  }
}

/// Recognizer and router kept open by an indexer that extracts in place (web).
typedef _InkEngines = ({InkRecognizer rec, RegionRouter? router});

/// Keeps the `page_text` table in step with the notebook stores: it follows
/// [FileService.writes] (after a pause) and reconciles once per launch.
class SearchIndexer {
  final FileService files;
  final Duration debounce;
  final bool useIsolate;
  final Future<void> Function() _idle;

  /// Loads the handwriting model, or null where it cannot run.
  final Future<InkModel?> Function()? inkModel;
  Future<InkModel?>? _ink;

  SearchIndexer(
    this.files, {
    this.debounce = const Duration(seconds: 2),
    bool? useIsolate,
    Future<void> Function()? idle,
    this.inkModel,
  })  : useIsolate = useIsolate ?? !kIsWeb,
        _idle = idle ?? _defaultIdle;

  Future<InkModel?> _inkModel() => _ink ??= () async {
        try {
          final m = await inkModel?.call();
          if (m == null || useIsolate) return m;
          // In place (web): opened once; a model that can't run indexes no ink.
          final meta = InkModelMeta.fromJson(jsonDecode(m.metaJson) as Map<String, dynamic>);
          final lexicon = m.lexicon == null ? null : await InkLexicon.parseAsync(m.lexicon!, _idle);
          final rec = await InkRecognizer.load(m.bytes, meta, lexicon: lexicon);
          if (rec == null) return null;
          _engines = (rec: rec, router: m.router == null ? null : await RegionRouter.load(m.router!));
          if (_disposed) _closeEngines();
          return m;
        } catch (e) {
          debugPrint('[SearchIndexer] handwriting model unavailable: $e');
          return null;
        }
      }();
  _InkEngines? _engines;

  void _closeEngines() {
    _engines?.rec.dispose();
    _engines?.router?.dispose();
    _engines = null;
  }

  /// [_extractBatch] in place, one handwriting line per idle slot; the
  /// recognizer and router run in the engine's worker.
  Future<List<PageText?>> _extractInPlace(List<Uint8List> pages) async {
    final out = <PageText?>[];
    for (final b in pages) {
      PageText text;
      try {
        text = extractPageTextFromBytes(b);
      } on FormatException {
        out.add(null);
        continue;
      }
      final e = _engines;
      if (e != null) {
        try {
          final lines = <InkLine>[];
          final segs = segmentInk(inkStrokes(decodePageBytes(b)));
          for (final seg in segs) {
            await _idle();
            if (_disposed) return out;
            final p = await e.router?.classifyAsync(seg.strokes);
            if ((p?.text ?? 1) < ocrTextThreshold) continue;
            lines.addAll(await e.rec.recognizeAsync(seg));
          }
          text = text.withInk(lines);
        } catch (err) {
          // Handwriting failed on this page: keep its typed text.
          debugPrint('[SearchIndexer] handwriting failed: $err');
        }
      }
      out.add(text);
    }
    return out;
  }

  /// Opened on first use: the database may not be ready when this is built.
  late final SearchIndex index = SearchIndex(files.database);

  final status = ValueNotifier<IndexStatus>(const IndexStatus(0, false));

  /// Bumped whenever the index changed, so open results can refresh.
  final revision = ValueNotifier<int>(0);

  final _timers = <String, Timer>{};
  final _waiting = <String, _Job>{}; // paused by the debounce
  final _ready = <String, _Job>{};
  StreamSubscription<StoreWrite>? _sub;
  Timer? _reconcileTimer;
  Future<void>? _running;
  bool _reconciling = false;
  bool _disposed = false;

  /// Starts following writes and reconciles once after [reconcileDelay].
  void start({Duration reconcileDelay = const Duration(seconds: 3)}) {
    if (_sub != null || _disposed) return;
    _sub = files.writes.listen(_onWrite);
    _reconcileTimer = Timer(reconcileDelay, () => unawaited(reconcile()));
  }

  void _onWrite(StoreWrite w) {
    final job = _waiting.putIfAbsent(w.notebookId, _Job.new);
    job.fromEvent = true;
    if (w.removed) {
      job.removed = true;
      job.force.clear();
    } else {
      job.removed = false;
      job.force.addAll(w.changed);
    }
    _timers[w.notebookId]?.cancel();
    _timers[w.notebookId] = Timer(debounce, () => _promote(w.notebookId));
    _publish();
  }

  void _promote(String id) {
    _timers.remove(id);
    final job = _waiting.remove(id);
    if (job == null) return;
    final cur = _ready[id];
    if (cur == null) {
      _ready[id] = job;
    } else {
      cur.force.addAll(job.force);
      cur.removed = job.removed;
      cur.fromEvent = cur.fromEvent || job.fromEvent;
    }
    _publish();
    unawaited(_drain());
  }

  void _publish() {
    if (_disposed) return;
    status.value = IndexStatus(_waiting.length + _ready.length, _reconciling);
  }

  /// Queues every library notebook and drops rows of notebooks that are gone.
  Future<void> reconcile() async {
    if (_disposed || _reconciling) return;
    _reconciling = true;
    _publish();
    try {
      final ids = [
        for (final r in await files.getAllNotebookMeta()) r['id'] as String
      ];
      final known = ids.toSet();
      for (final id in await index.notebookIds()) {
        if (!known.contains(id)) {
          (_ready[id] ??= _Job()).removed = true;
        }
      }
      for (final id in ids) {
        _ready.putIfAbsent(id, _Job.new);
      }
    } catch (e) {
      debugPrint('[SearchIndexer] reconcile failed: $e');
    }
    _reconciling = false;
    _publish();
    await _drain();
  }

  /// Runs everything queued now, ignoring the pause. For tests and shutdown.
  Future<void> flush() async {
    await Future<void>.delayed(Duration.zero); // events still in flight
    for (final t in _timers.values) {
      t.cancel();
    }
    for (final id in _timers.keys.toList()) {
      _promote(id);
    }
    await _drain();
  }

  Future<void> _drain() {
    final cur = _running;
    if (cur != null) return cur;
    if (_ready.isEmpty || _disposed) return Future<void>.value();
    return _running = _work();
  }

  Future<void> _work() async {
    try {
      while (_ready.isNotEmpty && !_disposed) {
        final id = _ready.keys.first;
        final job = _ready.remove(id)!;
        try {
          if (job.removed) {
            await index.deleteNotebook(id);
            _bump();
          } else {
            await indexNotebook(id, force: job.force, fromEvent: job.fromEvent);
          }
        } catch (e) {
          debugPrint('[SearchIndexer] $id failed: $e');
        }
        _publish();
        await _idle();
      }
    } finally {
      _running = null;
      _publish();
    }
  }

  /// Brings the rows of one notebook up to date with its store.
  @visibleForTesting
  Future<void> indexNotebook(String id,
      {Set<String> force = const {}, bool fromEvent = false}) async {
    if (await files.getNotebookMeta(id) == null) {
      await index.deleteNotebook(id);
      _bump();
      return;
    }
    if (!await files.hasLooseStore(id)) {
      // Evicted: keep the rows. A restored legacy file is migrated once.
      if (!fromEvent || !await File(files.localPath(id)).exists()) return;
      if (!await files.ensureLooseStore(id)) return;
    }
    final ink = await _inkModel();
    final dir = files.notebookStoreDir(id);
    final document = jsonDecode(utf8
        .decode(await File(p.join(dir, AppConfig.documentFile)).readAsBytes()));
    final metadata = jsonDecode(utf8
        .decode(await File(p.join(dir, AppConfig.metadataFile)).readAsBytes()));
    final entries = (document['pages'] as List? ?? const []);
    final stored = await index.stored(id);
    final keep = <String>{};
    var changed = false;

    final moved =
        <String, ({int pageIndex, String? chapterId, String? pageId})>{};
    final firstOfChapter = <String, (int, String?)>{};
    var batch = <PageRow>[];
    final todo = <_Todo>[];

    Future<void> flushBatch() async {
      if (batch.isEmpty) return;
      await index.apply(id, upsert: batch);
      batch = [];
      changed = true;
    }

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i] as Map;
      final fileName = e['fileName'] as String?;
      if (fileName == null) continue;
      final pageId = e['pageId'] as String?;
      final chapterId = e['chapterId'] as String?;
      if (chapterId != null) {
        firstOfChapter.putIfAbsent(chapterId, () => (i, pageId));
      }
      final path = p.join(dir, AppConfig.pagesDir, fileName);
      final st = await File(path).stat();
      if (st.size < 0) continue;
      keep.add(fileName);
      // The model version is part of the stamp: a new model re-reads pages.
      final stamp = '${st.size}:${st.modified.millisecondsSinceEpoch}'
          '${ink == null ? '' : ':${ink.version}'}'
          '${ink?.router == null ? '' : '+$regionRouterVersion'}';
      final row = stored[fileName];
      if (row != null && row.stamp == stamp && !force.contains(fileName)) {
        if (row.pageIndex != i || row.chapterId != chapterId) {
          moved[fileName] =
              (pageIndex: i, chapterId: chapterId, pageId: pageId);
        }
        continue;
      }
      todo.add((
        file: fileName,
        path: path,
        pageId: pageId,
        index: i,
        chapterId: chapterId,
        stamp: stamp,
      ));
    }

    // A few pages per isolate hop: spawning one per page costs more than it saves.
    for (var from = 0; from < todo.length; from += _chunk) {
      final part = todo.sublist(from, math.min(from + _chunk, todo.length));
      final read = <({_Todo t, Uint8List bytes})>[];
      for (final t in part) {
        try {
          read.add((t: t, bytes: await File(t.path).readAsBytes()));
        } catch (_) {
          // Unreadable now (mid-swap?): keep the row, a later write retries.
        }
      }
      final job = (
        pages: [for (final r in read) r.bytes],
        model: ink?.bytes,
        meta: ink?.metaJson,
        lexicon: ink?.lexicon,
        router: ink?.router,
      );
      final texts = useIsolate
          ? await compute(_extractBatch, job)
          : await _extractInPlace(job.pages);
      if (_disposed) return;
      for (var k = 0; k < read.length; k++) {
        final t = read[k].t;
        batch.add(PageRow(
            notebookId: id,
            pageFile: t.file,
            pageId: t.pageId,
            pageIndex: t.index,
            chapterId: t.chapterId,
            // A page that does not parse stays empty until it changes.
            text: texts[k] ?? PageText.empty,
            stamp: t.stamp));
      }
      await flushBatch();
      await _idle();
      if (_disposed) return;
    }

    for (final c in (metadata['chapters'] as List? ?? const [])) {
      if (c is! Map) continue;
      final cid = c['id'] as String?;
      final title = (c['title'] as String? ?? '').trim();
      if (cid == null || title.isEmpty) continue;
      final file = '$chapterFilePrefix$cid';
      keep.add(file);
      final first = firstOfChapter[cid];
      final row = stored[file];
      if (row != null &&
          row.stamp == title &&
          row.pageIndex == (first?.$1 ?? 0)) {
        continue;
      }
      batch.add(PageRow(
          notebookId: id,
          pageFile: file,
          pageId: first?.$2,
          pageIndex: first?.$1 ?? 0,
          chapterId: cid,
          text: PageText(
              title, foldForSearch(title), TextSource.chapter, '0,0,0'),
          stamp: title));
    }
    await flushBatch();

    final gone = [
      for (final f in stored.keys)
        if (!keep.contains(f)) f
    ];
    if (gone.isNotEmpty || moved.isNotEmpty) {
      await index.apply(id, delete: gone, moved: moved);
      changed = true;
    }
    if (changed) _bump();
  }

  void _bump() {
    if (!_disposed) revision.value++;
  }

  void dispose() {
    _disposed = true;
    _closeEngines();
    _sub?.cancel();
    _reconcileTimer?.cancel();
    for (final t in _timers.values) {
      t.cancel();
    }
    status.dispose();
    revision.dispose();
  }
}

/// Between two pages: a short pause natively (extraction runs in an isolate);
/// on the web, an idle-priority slot so a frame is never kept waiting.
Future<void> _defaultIdle() {
  if (!kIsWeb) return Future<void>.delayed(const Duration(milliseconds: 1));
  final c = Completer<void>();
  SchedulerBinding.instance.scheduleTask(c.complete, Priority.idle);
  return c.future;
}
