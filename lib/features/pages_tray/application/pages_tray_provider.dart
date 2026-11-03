import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:abelnotes/core/platform/app_dirs.dart';
import 'package:uuid/uuid.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/core/services/thumbnail_service.dart';
import 'package:abelnotes/features/pages_tray/data/closed_notebook_editor.dart';
import 'package:abelnotes/features/pages_tray/data/tray_store.dart';
import 'package:abelnotes/features/pages_tray/domain/page_transfer.dart';
import 'package:abelnotes/features/pages_tray/domain/pages_tray.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

// Controller of the pages tray; the flows and their invariants are in
// ../README.md.

enum TrayEvent {
  copied,
  moveReady,
  moveCancelled,
  trayCleared,
  pasted,
  moved,
  duplicated,
  undone,
  tooMany,
  nothingToTake,
  trayNotSaved,
  pastePagesGone,
  pasteTrayDamaged,
  pasteDestFailed,
  pasteDestUnavailable,
  moveSourceFailed,
  moveResumed,
  undoFailed,
}

enum TrayWhereKind { start, afterPage, end, chapterEnd }

class TrayWhere {
  final TrayWhereKind kind;
  final int page;
  final String? chapterTitle;
  const TrayWhere(this.kind, {this.page = 0, this.chapterTitle});
}

class TrayToast {
  final int id;
  final TrayEvent event;
  final int count;
  final int skipped;
  final String? notebookTitle;
  final TrayWhere? where;
  final bool canUndo;

  /// Offers "Show" for this notebook (the paste happened out of its Pages).
  final String? showNotebookId;
  final Set<String> landingIds;
  const TrayToast(this.id, this.event,
      {this.count = 0,
      this.skipped = 0,
      this.notebookTitle,
      this.where,
      this.canUndo = false,
      this.showNotebookId,
      this.landingIds = const {}});

  bool get isProblem => const {
        TrayEvent.tooMany,
        TrayEvent.nothingToTake,
        TrayEvent.trayNotSaved,
        TrayEvent.pastePagesGone,
        TrayEvent.pasteTrayDamaged,
        TrayEvent.pasteDestFailed,
        TrayEvent.pasteDestUnavailable,
        TrayEvent.moveSourceFailed,
        TrayEvent.undoFailed,
      }.contains(event);
}

/// Pages that just landed; the grid highlights them for a moment.
class TrayLanding {
  final Set<String> pageIds;
  final int stamp;
  const TrayLanding(this.pageIds, this.stamp);
}

enum PasteStatus {
  ok,
  noTray,
  busy,
  pagesGone,
  trayDamaged,
  destFailed,
  destUnavailable,
  sourceFailed,
}

class PasteOutcome {
  final PasteStatus status;
  final List<String> newPageIds;
  const PasteOutcome(this.status, [this.newPageIds = const []]);
  bool get done =>
      status == PasteStatus.ok || status == PasteStatus.sourceFailed;
}

enum CaptureResult { ok, nothing, tooMany }

enum _UndoKind { pasted, movedAcross, movedWithin }

class _PasteUndo {
  final _UndoKind kind;
  final String destNotebookId;
  final List<String> newPageIds;
  final List<PageEntry> orderBefore;
  final String? sourceNotebookId;
  final ClosedRemoval? removal;
  final Map<String, PageData> removedData;
  const _PasteUndo(this.kind, this.destNotebookId, this.newPageIds,
      {this.orderBefore = const [],
      this.sourceNotebookId,
      this.removal,
      this.removedData = const {}});
}

class PagesTrayState {
  final PagesTray? tray;
  final TrayToast? toast;
  final TrayLanding? landing;
  final bool busy;
  const PagesTrayState(
      {this.tray, this.toast, this.landing, this.busy = false});

  PagesTrayState copyWith({
    PagesTray? tray,
    bool clearTray = false,
    TrayToast? toast,
    bool clearToast = false,
    TrayLanding? landing,
    bool clearLanding = false,
    bool? busy,
  }) =>
      PagesTrayState(
        tray: clearTray ? null : (tray ?? this.tray),
        toast: clearToast ? null : (toast ?? this.toast),
        landing: clearLanding ? null : (landing ?? this.landing),
        busy: busy ?? this.busy,
      );
}

/// Open this notebook's Pages (the editor does it when it appears).
class TrayNavRequest {
  final String notebookId;
  final Set<String> landing;
  const TrayNavRequest(this.notebookId, [this.landing = const {}]);
}

final pagesTrayNavProvider = StateProvider<TrayNavRequest?>((_) => null);

/// True while the page manager is on screen (it draws the tray itself).
final pageManagerOpenProvider = StateProvider<bool>((_) => false);

final pagesTrayProvider =
    StateNotifierProvider<PagesTrayController, PagesTrayState>(
        (ref) => PagesTrayController(ref));

class PagesTrayController extends StateNotifier<PagesTrayState> {
  PagesTrayController(
    this._ref, {
    TrayStore? store,
    Future<List<List<int>>> Function(
            List<TrayPage> pages, Map<String, Uint8List> assets)?
        renderThumbs,
    Future<void> Function()? reloadLibrary,
    Future<void> Function()? pushClosedNotebooks,
  })  : _store = store,
        _renderThumbs = renderThumbs ?? _defaultThumbs(_ref),
        _reloadLibrary = reloadLibrary ?? _defaultReload(_ref),
        _push = pushClosedNotebooks ?? _defaultPush(_ref),
        super(const PagesTrayState());

  final Ref _ref;
  TrayStore? _store;
  final Future<List<List<int>>> Function(
      List<TrayPage> pages, Map<String, Uint8List> assets) _renderThumbs;
  final Future<void> Function() _reloadLibrary;
  final Future<void> Function() _push;
  _PasteUndo? _undo;
  Timer? _toastTimer;
  bool _toastHeld = false;
  Timer? _landingTimer;
  var _toastSeq = 0;

  static Future<List<List<int>>> Function(
      List<TrayPage>, Map<String, Uint8List>) _defaultThumbs(
          Ref ref) =>
      (pages, assets) async {
        final out = <List<int>>[];
        final svc = ref.read(thumbnailServiceProvider);
        for (final tp in pages.take(3)) {
          final png = await svc.renderPng(tp.data,
              assetBytes: {
                for (final a in tp.assetIds)
                  if (assets[a] != null) a: assets[a]!,
              },
              width: 120,
              height: 168);
          if (png != null) out.add(png);
        }
        return out;
      };

  static Future<void> Function() _defaultReload(Ref ref) => () async {
        await ref.read(notebookListProvider.notifier).reloadFromLocal();
      };

  /// Closed notebooks edited here go up now instead of at the library's next tick.
  static Future<void> Function() _defaultPush(Ref ref) => () async {
        await ref.read(notebookListProvider.notifier).retryPendingUploads();
      };

  void _kickSync() {
    unawaited(_push().catchError((Object e) {
      debugPrint('[PagesTray] push after edit deferred: $e');
    }));
  }

  Future<TrayStore> _storeReady() async {
    final s = _store;
    if (s != null) return s;
    final dir = await getApplicationSupportDirectory();
    return _store = TrayStore(p.join(dir.path, 'pages_tray'));
  }

  ClosedNotebookEditor get _editor => ClosedNotebookEditor(
        _ref.read(fileServiceProvider),
        thumbnails: _safeThumbs(),
        isOpenInEditor: (id) => _ref.read(canvasProvider)?.metadata.id == id,
      );

  ThumbnailService? _safeThumbs() {
    try {
      return _ref.read(thumbnailServiceProvider);
    } catch (_) {
      return null;
    }
  }

  CanvasNotifier get _canvas => _ref.read(canvasProvider.notifier);

  @override
  void dispose() {
    _toastTimer?.cancel();
    _landingTimer?.cancel();
    super.dispose();
  }

  // ── startup ──

  /// Loads the saved tray and finishes or drops what a crash left half done.
  Future<void> start() async {
    final store = await _storeReady();
    await store.purgeDiscarded();
    final t = await store.read();
    if (t == null || !mounted) return;
    state = state.copyWith(tray: t);
    await _reconcile(t);
  }

  Future<void> _reconcile(PagesTray t) async {
    var tray = t;
    final j = t.journal;
    if (j != null) {
      final stored =
          await _editor.storesPages(j.destNotebookId, j.newPageIds.toSet());
      if (stored && t.isMove) {
        try {
          await _editor.removePages(t.sourceNotebookId, t.pageIds);
          await _discard();
          _toast(TrayEvent.moveResumed, count: t.count);
          await _reloadLibrary();
          return;
        } catch (e) {
          debugPrint('[PagesTray] could not finish an interrupted move: $e');
          tray = t.copyWith(mode: TrayMode.copy, clearJournal: true);
        }
      } else {
        tray = t.copyWith(clearJournal: true);
      }
      await _putTray(tray, manifestOnly: true);
    }
    if (tray.isMove && !await _sourceExists(tray.sourceNotebookId)) {
      await _putTray(tray.asCopyOfDeletedSource(), manifestOnly: true);
    }
  }

  Future<bool> _sourceExists(String id) async {
    try {
      return await _ref.read(fileServiceProvider).getNotebookMeta(id) != null;
    } catch (_) {
      return true; // cannot tell: keep it a move, nothing is lost either way
    }
  }

  Future<void> _putTray(PagesTray t, {bool manifestOnly = false}) async {
    if (mounted) state = state.copyWith(tray: t);
    try {
      if (manifestOnly) await (await _storeReady()).updateManifest(t);
    } catch (e) {
      debugPrint('[PagesTray] manifest update failed: $e');
    }
  }

  /// A move whose source is gone is a copy: nothing is left to take them out of.
  Future<PagesTray> _resolveSource(PagesTray t) async {
    if (!t.isMove || await _sourceExists(t.sourceNotebookId)) return t;
    final copy = t.asCopyOfDeletedSource();
    await _putTray(copy, manifestOnly: true);
    return copy;
  }

  /// Called when a notebook is deleted (library, trash).
  Future<void> onNotebookDeleted(String notebookId) async {
    final t = state.tray;
    if (t == null || !t.isMove || t.sourceNotebookId != notebookId) return;
    await _putTray(t.asCopyOfDeletedSource(), manifestOnly: true);
  }

  // ── capture, cancel ──

  /// Puts the pages at [docIndices] of the open notebook in the tray.
  Future<CaptureResult> capture(
      TrayMode mode, CanvasState s, Set<int> docIndices) async {
    final sorted = docIndices
        .where((i) => i >= 0 && i < s.document.pages.length)
        .toList()
      ..sort();
    final taken = <TrayPage>[];
    final assets = <String, Uint8List>{};
    var skipped = 0;
    for (final i in sorted) {
      final entry = s.document.pages[i];
      final page = s.pages[entry.fileName];
      final tp = page == null ? null : TrayPage(entry, page);
      final bytes = <String, Uint8List>{};
      var complete = tp != null;
      if (tp != null) {
        for (final a in tp.assetIds) {
          final b = s.assetBytes[a];
          if (b == null) {
            complete = false;
            break;
          }
          bytes[a] = b;
        }
      }
      if (!complete) {
        skipped++;
        continue;
      }
      taken.add(tp!);
      assets.addAll(bytes);
    }
    if (taken.isEmpty) {
      _toast(TrayEvent.nothingToTake, skipped: skipped);
      return CaptureResult.nothing;
    }
    if (taken.length > kTrayPageCap) {
      _toast(TrayEvent.tooMany, count: kTrayPageCap);
      return CaptureResult.tooMany;
    }
    final info = sourceChapterInfo(
        s.metadata.chapters, [for (final t in taken) t.entry]);
    List<List<int>> thumbs = const [];
    try {
      thumbs = await _renderThumbs(taken, assets);
    } catch (_) {}
    final tray = PagesTray(
      id: const Uuid().v4(),
      mode: mode,
      sourceNotebookId: s.metadata.id,
      sourceTitle: s.metadata.title,
      sourceChapterTitle: info.title,
      mixedChapters: info.mixed,
      pages: taken,
      thumbs: thumbs,
    );
    _undo = null;
    state = state.copyWith(tray: tray);
    // The tray panel already says what was taken; only skipped pages need a word.
    if (skipped > 0) {
      _toast(mode == TrayMode.copy ? TrayEvent.copied : TrayEvent.moveReady,
          count: taken.length, skipped: skipped);
    }
    try {
      await (await _storeReady()).write(tray, assets);
      if (mounted && state.tray?.id == tray.id) {
        state = state.copyWith(tray: tray.copyWith(saved: true));
      }
    } catch (e) {
      debugPrint('[PagesTray] could not save the tray: $e');
      _toast(TrayEvent.trayNotSaved);
    }
    return CaptureResult.ok;
  }

  /// Cancels a move (nothing was removed) or clears a copy.
  Future<void> cancel() async {
    final t = state.tray;
    if (t == null) return;
    _undo = null;
    await _discard();
    _toast(t.isMove ? TrayEvent.moveCancelled : TrayEvent.trayCleared,
        count: t.count, notebookTitle: t.sourceTitle);
  }

  Future<void> _discard() async {
    if (mounted) state = state.copyWith(clearTray: true);
    try {
      await (await _storeReady()).discard();
    } catch (e) {
      debugPrint('[PagesTray] discard failed: $e');
    }
  }

  // ── paste ──

  /// Pastes into the open notebook at [slot]; a move inside its own notebook
  /// reorders, a move from another notebook transfers (README).
  Future<PasteOutcome> pasteIntoOpen(PasteSlot slot) async {
    final cs = _ref.read(canvasProvider);
    if (cs == null) return const PasteOutcome(PasteStatus.destUnavailable);
    return _run(() async {
      final tray = await _resolveSource(state.tray!);
      if (tray.isMove && tray.sourceNotebookId == cs.metadata.id) {
        return _moveWithin(tray, cs, slot);
      }
      return _transfer(tray, cs.metadata.id, openDest: true, slot: slot);
    });
  }

  /// Pastes into a closed notebook, at the end of its last chapter.
  Future<PasteOutcome> pasteIntoClosed(String notebookId) async {
    return _run(() async {
      final tray = await _resolveSource(state.tray!);
      if (tray.isMove && tray.sourceNotebookId == notebookId) {
        return const PasteOutcome(PasteStatus.destUnavailable);
      }
      return _transfer(tray, notebookId, openDest: false, slot: null);
    });
  }

  Future<PasteOutcome> _run(Future<PasteOutcome> Function() body) async {
    if (state.tray == null) return const PasteOutcome(PasteStatus.noTray);
    if (state.busy) return const PasteOutcome(PasteStatus.busy);
    state = state.copyWith(busy: true);
    try {
      return await body();
    } catch (e, st) {
      debugPrint('[PagesTray] paste failed: $e');
      unawaited(CrashLogger.append('[PagesTray] paste failed: $e\n$st'));
      _toast(TrayEvent.pasteDestFailed);
      return const PasteOutcome(PasteStatus.destFailed);
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  Future<PasteOutcome> _moveWithin(
      PagesTray tray, CanvasState cs, PasteSlot slot) async {
    final here = {for (final e in cs.document.pages) e.pageId};
    final ids = tray.pageIds.intersection(here);
    if (ids.isEmpty) {
      await _discard();
      _toast(TrayEvent.pastePagesGone);
      return const PasteOutcome(PasteStatus.pagesGone);
    }
    final before = cs.document.pages;
    _canvas.movePagesToSlot(ids, slot);
    final after = _ref.read(canvasProvider)!.document;
    final at = after.pages.indexWhere((e) => ids.contains(e.pageId));
    final where = _whereFor(
        after, _ref.read(canvasProvider)!.metadata.chapters, at, slot);
    await _discard();
    _undo = _PasteUndo(_UndoKind.movedWithin, cs.metadata.id, ids.toList(),
        orderBefore: before);
    _land(ids);
    _toast(TrayEvent.moved,
        count: ids.length,
        notebookTitle: cs.metadata.title,
        where: where,
        canUndo: true);
    return PasteOutcome(PasteStatus.ok, ids.toList());
  }

  TrayWhere _whereFor(DocumentStructure doc, List<Chapter> chapters,
      int firstIndex, PasteSlot? slot) {
    if (slot == null) {
      // Closed notebook: end of the last chapter, or of the notebook.
      if (chapters.isEmpty) return const TrayWhere(TrayWhereKind.end);
      return TrayWhere(TrayWhereKind.chapterEnd,
          chapterTitle: chapters.last.title);
    }
    if (firstIndex <= 0) return const TrayWhere(TrayWhereKind.start);
    return TrayWhere(TrayWhereKind.afterPage, page: firstIndex);
  }

  Future<PasteOutcome> _transfer(PagesTray tray, String destId,
      {required bool openDest, required PasteSlot? slot}) async {
    final store = await _storeReady();
    final assets = await store.readAssets(tray.assetIds);
    if (!tray.assetIds.every(assets.containsKey)) {
      _toast(TrayEvent.pasteTrayDamaged);
      return const PasteOutcome(PasteStatus.trayDamaged);
    }
    final editor = _editor;
    final ids = [for (final _ in tray.pages) const Uuid().v4()];
    final cross = tray.isMove;
    var current = tray;
    if (cross) {
      current = tray.copyWith(journal: TrayJournal(destId, ids));
      await _putTray(current, manifestOnly: true);
    }
    Future<void> dropJournal() async {
      if (cross) {
        current = current.copyWith(clearJournal: true);
        await _putTray(current, manifestOnly: true);
      }
    }

    // 1. The destination first.
    var destTitle = '';
    TrayWhere? where;
    try {
      if (openDest) {
        final before = _ref.read(canvasProvider)!;
        destTitle = before.metadata.title;
        _canvas.pastePages(
          pages: [for (final t in tray.pages) t.data],
          entries: [for (final t in tray.pages) t.entry],
          assets: assets,
          slot: slot,
          pageIds: ids,
        );
        final after = _ref.read(canvasProvider)!;
        final at =
            after.document.pages.indexWhere((e) => e.pageId == ids.first);
        where = _whereFor(after.document, after.metadata.chapters, at, slot);
        final saved = await _canvas.saveLocally();
        if (!saved || !await editor.storesPages(destId, ids.toSet())) {
          _canvas.deletePagesById(ids.toSet());
          await dropJournal();
          _toast(TrayEvent.pasteDestFailed);
          return const PasteOutcome(PasteStatus.destFailed);
        }
      } else {
        final cur = await editor.readStructure(destId);
        destTitle = cur.meta.title;
        final s = slot ?? appendSlot(cur.meta.chapters, cur.doc);
        final r = await editor.insertPages(destId, tray.pages, assets, s,
            pageIds: ids);
        where = _whereFor(cur.doc, cur.meta.chapters, r.insertIndex, null);
        if (!await editor.storesPages(destId, ids.toSet())) {
          try {
            await editor.removePages(destId, ids.toSet());
          } catch (_) {}
          await dropJournal();
          _toast(TrayEvent.pasteDestFailed);
          return const PasteOutcome(PasteStatus.destFailed);
        }
      }
    } on NotebookBusyException {
      await dropJournal();
      _toast(TrayEvent.pasteDestUnavailable);
      return const PasteOutcome(PasteStatus.destUnavailable);
    } on NotebookUnavailableException {
      await dropJournal();
      _toast(TrayEvent.pasteDestUnavailable);
      return const PasteOutcome(PasteStatus.destUnavailable);
    } catch (e) {
      debugPrint('[PagesTray] destination write failed: $e');
      await dropJournal();
      _toast(TrayEvent.pasteDestFailed);
      return const PasteOutcome(PasteStatus.destFailed);
    }

    // 2. Only now the source (moves).
    ClosedRemoval? removal;
    var sourceFailed = false;
    if (cross) {
      try {
        removal = await editor.removePages(tray.sourceNotebookId, tray.pageIds);
      } catch (e) {
        debugPrint('[PagesTray] source edit failed: $e');
        unawaited(CrashLogger.append('[PagesTray] source edit failed: $e'));
        sourceFailed = true;
      }
    }

    // 3. Settle the tray.
    if (cross && !sourceFailed) {
      await _discard();
    } else if (cross) {
      await _putTray(current.copyWith(mode: TrayMode.copy, clearJournal: true),
          manifestOnly: true);
    }
    final undoable = !sourceFailed;
    _undo = undoable
        ? _PasteUndo(
            cross ? _UndoKind.movedAcross : _UndoKind.pasted, destId, ids,
            sourceNotebookId: cross ? tray.sourceNotebookId : null,
            removal: removal,
            removedData: {for (final t in tray.pages) t.pageId: t.data})
        : null;
    if (openDest) _land(ids.toSet());
    await _reloadLibrary();
    _kickSync();
    _toast(
        sourceFailed
            ? TrayEvent.moveSourceFailed
            : (cross ? TrayEvent.moved : TrayEvent.pasted),
        count: ids.length,
        notebookTitle: sourceFailed ? tray.sourceTitle : destTitle,
        where: where,
        canUndo: undoable,
        showNotebookId: openDest ? null : destId,
        landingIds: openDest ? const {} : ids.toSet());
    return PasteOutcome(
        sourceFailed ? PasteStatus.sourceFailed : PasteStatus.ok, ids);
  }

  // ── duplicate, delete ──

  /// Duplicates the pages with these ids, each right after its original, and
  /// offers Undo like a paste.
  void duplicatePages(Set<String> pageIds) {
    final s = _ref.read(canvasProvider);
    if (s == null) return;
    final before = {for (final e in s.document.pages) e.pageId};
    final idx = [
      for (var i = 0; i < s.document.pages.length; i++)
        if (pageIds.contains(s.document.pages[i].pageId)) i,
    ];
    for (final i in idx.reversed) {
      _canvas.duplicatePage(i);
    }
    final after = _ref.read(canvasProvider)!;
    final added = [
      for (final e in after.document.pages)
        if (!before.contains(e.pageId)) e.pageId,
    ];
    if (added.isEmpty) return;
    _undo = _PasteUndo(_UndoKind.pasted, after.metadata.id, added);
    _land(added.toSet());
    _toast(TrayEvent.duplicated, count: added.length, canUndo: true);
  }

  /// A move tray must not carry pages the user deleted from its source.
  Future<void> pagesDeleted(String notebookId, Set<String> pageIds) async {
    final t = state.tray;
    if (t == null || !t.isMove || t.sourceNotebookId != notebookId) return;
    final keep = [
      for (final pg in t.pages)
        if (!pageIds.contains(pg.pageId)) pg,
    ];
    if (keep.length == t.pages.length) return;
    if (keep.isEmpty) {
      await _discard();
      return;
    }
    final store = await _storeReady();
    final next = PagesTray(
      id: t.id,
      mode: t.mode,
      sourceNotebookId: t.sourceNotebookId,
      sourceTitle: t.sourceTitle,
      sourceChapterTitle: t.sourceChapterTitle,
      mixedChapters: t.mixedChapters,
      pages: keep,
      thumbs: t.thumbs,
    );
    state = state.copyWith(tray: next);
    try {
      final assets = await store.readAssets(next.assetIds);
      await store.write(next, assets);
      if (mounted && state.tray?.id == next.id) {
        state = state.copyWith(tray: next.copyWith(saved: true));
      }
    } catch (e) {
      debugPrint('[PagesTray] could not rewrite the tray: $e');
    }
  }

  // ── undo ──

  Future<void> undoLast() async {
    final u = _undo;
    if (u == null || state.busy) return;
    _undo = null;
    state = state.copyWith(busy: true, clearToast: true);
    try {
      final ok = await _undoNow(u);
      _toast(ok ? TrayEvent.undone : TrayEvent.undoFailed);
    } catch (e, st) {
      debugPrint('[PagesTray] undo failed: $e');
      unawaited(CrashLogger.append('[PagesTray] undo failed: $e\n$st'));
      _toast(TrayEvent.undoFailed);
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  Future<bool> _undoNow(_PasteUndo u) async {
    final editor = _editor;
    switch (u.kind) {
      case _UndoKind.movedWithin:
        _canvas.restorePageOrder(u.orderBefore);
        return _restoreTray();
      case _UndoKind.pasted:
        await _removeFromDest(editor, u);
        return true;
      case _UndoKind.movedAcross:
        // Source first: if it cannot be restored nothing else changes.
        final removal = u.removal;
        final src = u.sourceNotebookId;
        if (removal != null && src != null) {
          await editor.restoreRemoved(src, removal, u.removedData);
        }
        await _removeFromDest(editor, u);
        await _restoreTray();
        _kickSync();
        return true;
    }
  }

  Future<void> _removeFromDest(
      ClosedNotebookEditor editor, _PasteUndo u) async {
    final open = _ref.read(canvasProvider)?.metadata.id == u.destNotebookId;
    if (open) {
      _canvas.deletePagesById(u.newPageIds.toSet());
      await _canvas.saveLocally();
    } else {
      await editor.removePages(u.destNotebookId, u.newPageIds.toSet());
    }
    await _reloadLibrary();
    _kickSync();
  }

  Future<bool> _restoreTray() async {
    final store = await _storeReady();
    if (!await store.restoreDiscarded()) return false;
    final t = await store.read();
    if (t == null) return false;
    await _putTray(t.copyWith(clearJournal: true), manifestOnly: true);
    return true;
  }

  // ── toast, landing ──

  void _toast(TrayEvent event,
      {int count = 0,
      int skipped = 0,
      String? notebookTitle,
      TrayWhere? where,
      bool canUndo = false,
      String? showNotebookId,
      Set<String> landingIds = const {}}) {
    if (!mounted) return;
    _toastTimer?.cancel();
    final t = TrayToast(++_toastSeq, event,
        count: count,
        skipped: skipped,
        notebookTitle: notebookTitle,
        where: where,
        canUndo: canUndo,
        showNotebookId: showNotebookId,
        landingIds: landingIds);
    state = state.copyWith(toast: t);
    _toastHeld = false;
    _armToastTimer();
  }

  // Undo stays a little longer, and only while it still matches the screen.
  void _armToastTimer() {
    _toastTimer?.cancel();
    final t = state.toast;
    if (t == null || _toastHeld) return;
    _toastTimer = Timer(Duration(seconds: t.canUndo ? 10 : 6), dismissToast);
  }

  /// Pointer over the toast: keep it until the pointer leaves.
  void holdToast(bool hold) {
    _toastHeld = hold;
    hold ? _toastTimer?.cancel() : _armToastTimer();
  }

  /// The user moved on (another screen, a new edit): drop a pending Undo.
  void dismissUndoToast() {
    if (state.toast?.canUndo ?? false) dismissToast();
  }

  void dismissToast() {
    _toastTimer?.cancel();
    if (!mounted) return;
    _undo = null;
    state = state.copyWith(clearToast: true);
    unawaited(_storeReady().then((s) => s.purgeDiscarded()));
  }

  void _land(Set<String> ids) {
    _landingTimer?.cancel();
    state = state.copyWith(
        landing: TrayLanding(ids, DateTime.now().microsecondsSinceEpoch));
    _landingTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) state = state.copyWith(clearLanding: true);
    });
  }

  /// Highlights pages (for "Show" after a paste made outside the Pages).
  void landPages(Set<String> ids) => _land(ids);
}
