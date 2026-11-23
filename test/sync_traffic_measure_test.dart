// Upload traffic of real writing through the real save and push path
// (CanvasNotifier + SyncService + a counting fake store). A measuring tool,
// not a check: skipped unless ABELNOTES_MEASURE is set.
//
//   ABELNOTES_MEASURE=1 flutter test test/sync_traffic_measure_test.dart
//
// Results and the writing model: lib/core/sync/README.md, "Traffic".

@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/providers/remote_store_provider.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/sync/stroke_ops.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/fake_remote_store.dart';

final _measure = Platform.environment['ABELNOTES_MEASURE'] != null;

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

/// Sums uploaded bytes and PUTs by kind of file.
class CountingStore extends FakeRemoteStore {
  final bytes = <String, int>{};
  final puts = <String, int>{};
  int down = 0;

  static String kindOf(String path) {
    if (path.contains('/pages/')) return 'page';
    if (path.contains('/ops/')) return 'ops';
    if (path.contains('/assets/')) return 'asset';
    if (path.endsWith('metadata.json')) return 'metadata';
    if (path.endsWith('document.json')) return 'document';
    return 'other';
  }

  @override
  Future<String?> uploadFile(String remotePath, Uint8List data,
      {int? timeoutSeconds,
      bool criticalVerify = false,
      bool skipVerify = false}) {
    final k = kindOf(remotePath);
    bytes[k] = (bytes[k] ?? 0) + data.length;
    puts[k] = (puts[k] ?? 0) + 1;
    return super.uploadFile(remotePath, data);
  }

  @override
  Future<Uint8List> downloadFile(String remotePath,
      {int? timeoutSeconds, bool criticalVerify = false}) async {
    final d = await super.downloadFile(remotePath);
    down += d.length;
    return d;
  }

  int get total => bytes.values.fold(0, (a, b) => a + b);
  int get totalPuts => puts.values.fold(0, (a, b) => a + b);

  void reset() {
    bytes.clear();
    puts.clear();
    down = 0;
  }
}

/// Handwriting strokes with the shape of real pages (local corpus of 1523
/// pages: points per stroke p50 17, p90 54, mean 26; absolute ms timestamps
/// and pressure on 95% of points; ~1.2 KB of compact JSON per stroke).
class StrokeGen {
  StrokeGen(int seed) : _r = Random(seed);
  final Random _r;
  int _n = 0;
  int _clock = 1781849370321;
  double _x = 60, _y = 80;

  int _pointCount() {
    // Log-normal fitted to the corpus: median 17, p90 54.
    final g = sqrt(-2 * log(1 - _r.nextDouble())) * cos(2 * pi * _r.nextDouble());
    return exp(log(17) + 0.90 * g).round().clamp(2, 400);
  }

  ContentElement next({double pageW = 595, double pageH = 842}) {
    final n = _pointCount();
    final pts = <StrokePoint>[];
    var x = _x, y = _y;
    var a = _r.nextDouble() * 2 * pi;
    var p = 0.4 + _r.nextDouble() * 0.4;
    for (var i = 0; i < n; i++) {
      a += (_r.nextDouble() - 0.5) * 0.9;
      x += cos(a) * (0.6 + _r.nextDouble() * 1.6);
      y += sin(a) * (0.6 + _r.nextDouble() * 1.6);
      p = (p + (_r.nextDouble() - 0.5) * 0.08).clamp(0.05, 1.0);
      _clock += 4 + _r.nextInt(6);
      pts.add(StrokePoint(
          x: (x * 1000).round() / 1000,
          y: (y * 1000).round() / 1000,
          pressure: (p * 100).round() / 100,
          timestamp: _clock));
    }
    // Next stroke a little to the right, wrapping like lines of text.
    _x += 8 + _r.nextDouble() * 10;
    if (_x > pageW - 60) {
      _x = 60;
      _y += 28;
      if (_y > pageH - 60) _y = 80;
    }
    _clock += 150 + _r.nextInt(500);
    return ContentElement.stroke(
      id: 'stroke-${_n++}-${_r.nextInt(1 << 30)}',
      zIndex: _n,
      data: StrokeData(
        points: pts,
        color: 0xFF000000,
        baseWidth: 1.5,
        timestamp: DateTime.fromMillisecondsSinceEpoch(_clock),
      ),
    );
  }

  int lastDurationMs(ContentElement e) {
    final pts = (e as StrokeElement).data.points;
    return pts.last.timestamp - pts.first.timestamp;
  }
}

/// When the editor's autosave fires for a stream of strokes: 1.2 s after
/// the last edit, or 15 s after the first edit of a burst (canvas_screen).
/// The pace: words of 2-6 strokes, 0.15-0.35 s between strokes of a word,
/// 0.3-0.8 s between words, a 1.5-4 s pause every 5-8 words.
List<int> autosaveBatches(int strokes, Random r, {required void Function(double) onDurationS}) {
  const idle = 1.2, maxDelay = 15.0;
  final times = <double>[];
  var t = 0.0;
  var wordLeft = 2 + r.nextInt(5), wordsLeft = 5 + r.nextInt(4);
  for (var i = 0; i < strokes; i++) {
    t += 0.12 + r.nextDouble() * 0.45; // the stroke itself
    times.add(t);
    if (--wordLeft > 0) {
      t += 0.15 + r.nextDouble() * 0.2;
      continue;
    }
    wordLeft = 2 + r.nextInt(5);
    if (--wordsLeft > 0) {
      t += 0.3 + r.nextDouble() * 0.5;
    } else {
      wordsLeft = 5 + r.nextInt(4);
      t += 1.5 + r.nextDouble() * 2.5;
    }
  }
  onDurationS(t);
  final batches = <int>[];
  var start = 0;
  double? burst;
  for (var i = 0; i < times.length; i++) {
    burst ??= times[i];
    final gap = i + 1 < times.length ? times[i + 1] - times[i] : double.infinity;
    final capHit = i + 1 < times.length && times[i + 1] - burst >= maxDelay;
    if (gap >= idle || capHit) {
      batches.add(i + 1 - start);
      start = i + 1;
      burst = null;
    }
  }
  return batches;
}

PdfTextLayer _textLayer(Random r) => PdfTextLayer(
      sourceAssetPath: 'images/pdfpage.png',
      runs: [
        for (var l = 0; l < 45; l++)
          PdfTextRun(
            text: 'Lorem ipsum dolor sit amet consectetur $l',
            x: 56,
            y: 60 + l * 16.0,
            width: 480,
            height: 12,
            chars: [
              for (var c = 0; c < 40; c++)
                PdfCharBox(x: 56 + c * 11.7 + r.nextDouble(), y: 60 + l * 16.0, width: 10.9, height: 12),
            ],
          ),
      ],
    );

class Scenario {
  Scenario(this.name, this.baseStrokes, {this.pdf = false, this.images = 0});
  final String name;
  final int baseStrokes;
  final bool pdf;
  final int images;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final scenarios = [
    Scenario('light (40 strokes)', 40),
    Scenario('medium (400 strokes, the p90 page)', 400),
    Scenario('dense (2000 strokes)', 2000),
    Scenario('PDF page + 3 images + 300 strokes', 300, pdf: true, images: 3),
  ];
  const writtenStrokes = 120;
  final report = StringBuffer();

  for (final (ops, sc) in [
    for (final ops in [false, true])
      for (final sc in scenarios) (ops, sc),
  ]) {
    test('${sc.name}${ops ? ', stroke chunks' : ''}', () async {
      StrokeOps.read = ops;
      StrokeOps.write = ops;
      addTearDown(StrokeOps.restoreDefaults);
      SharedPreferences.setMockInitialValues({});
      final tmp = await Directory.systemTemp.createTemp('traffic');
      PathProviderPlatform.instance = _Paths(tmp.path);
      final fs = FileService();
      await fs.init();
      final store = CountingStore();
      final c = ProviderContainer(overrides: [
        fileServiceProvider.overrideWithValue(fs),
        remoteStoreProvider.overrideWithValue(store),
      ]);
      final n = c.read(canvasProvider.notifier);
      final gen = StrokeGen(7);
      final r = Random(11);
      final assets = <String, Uint8List>{
        if (sc.pdf) 'pdfpage.png': Uint8List(900 * 1024),
        for (var i = 0; i < sc.images; i++) 'img$i.jpg': Uint8List(250 * 1024),
      };
      final content = <ContentElement>[
        if (sc.pdf)
          const ContentElement.image(
              id: 'pdf-raster',
              zIndex: 0,
              data: ImageData(
                  x: 0, y: 0, width: 595, height: 842, assetPath: 'images/pdfpage.png',
                  locked: true, pdfWidthPt: 595, pdfHeightPt: 842)),
        for (var i = 0; i < sc.images; i++)
          ContentElement.image(
              id: 'img-$i',
              zIndex: i + 1,
              data: ImageData(
                  x: 40.0 + i * 150, y: 500, width: 140, height: 100,
                  assetPath: 'images/img$i.jpg')),
        for (var i = 0; i < sc.baseStrokes; i++) gen.next(),
      ];
      final id = 'measure-${sc.baseStrokes}-${sc.pdf}-$ops';
      final now = DateTime(2026);
      await n.openNotebook(
        metadata: NotebookMetadata(id: id, title: 'Measure', createdAt: now, modifiedAt: now),
        document: DocumentStructure(notebookId: id, pages: const [
          PageEntry(pageId: 'p1', pageNumber: 1, fileName: 'page_001.json'),
        ]),
        pages: {
          'page_001.json': PageData(
            pageId: 'p1',
            pageNumber: 1,
            width: 595,
            height: 842,
            layers: RenderingLayers(content: content),
            pdfTextLayer: sc.pdf ? _textLayer(r) : null,
          ),
        },
        assets: assets,
        remotePath: '/AbelNotes/$id.abelnote',
      );

      void draw(int k) {
        final s = n.state!;
        final page = s.pages['page_001.json']!;
        n.state = s.copyWith(
          pages: {
            ...s.pages,
            'page_001.json': page.copyWith(
                layers: page.layers.copyWith(content: [
              ...page.layers.content,
              for (var i = 0; i < k; i++) gen.next(),
            ])),
          },
          isDirty: true,
        );
      }

      // First upload of the notebook (not counted).
      n.state = n.state!.copyWith(isDirty: true);
      await n.save();
      await n.flushPendingWork();
      final initial = store.total;
      store.reset();

      var durationS = 0.0;
      final batches = autosaveBatches(writtenStrokes, Random(3), onDurationS: (d) => durationS = d);
      final before = n.state!.pages['page_001.json']!;
      var afterFirst = 0;
      for (final k in batches) {
        draw(k);
        await n.save();
        await n.flushPendingWork();
        if (afterFirst == 0) afterFirst = store.total;
      }
      final steady = (store.total - afterFirst) / (batches.length - 1);
      final after = n.state!.pages['page_001.json']!;
      final added = after.layers.content.skip(before.layers.content.length).toList();
      final editJson = utf8.encode(compactPageJson(before.copyWith(
                  layers: before.layers.copyWith(content: added))))
              .length -
          utf8.encode(compactPageJson(before.copyWith(
                  layers: before.layers.copyWith(content: const []))))
              .length;
      final editBin = binaryPageBytes(before.copyWith(
                  layers: before.layers.copyWith(content: added)))!
              .length -
          binaryPageBytes(before.copyWith(layers: before.layers.copyWith(content: const [])))!.length;
      final pageJson = utf8.encode(compactPageJson(after)).length;
      final pageBin = binaryPageBytes(after)!.length;
      final saves = batches.length;
      final perMin = 60 / durationS;
      String kb(num b) => '${(b / 1024).toStringAsFixed(1)} KB';
      String mb(num b) => '${(b / 1048576).toStringAsFixed(2)} MB';
      final line = '| ${sc.name}${ops ? ' **chunks**' : ''} | ${kb(pageJson)} / ${kb(pageBin)} | '
          '${kb(afterFirst)} | ${kb(steady)} | '
          '${kb(store.total / saves)} (page ${kb((store.bytes['page'] ?? 0) / saves)}) | '
          '${kb(store.total / writtenStrokes)} | '
          '${mb(store.total * perMin)} | ${mb(store.total * perMin * 60)} | '
          '${kb(editJson / writtenStrokes)} / ${kb(editBin / writtenStrokes)} | '
          '${(store.total / editJson).toStringAsFixed(0)}x |';
      report.writeln(line);
      // ignore: avoid_print
      print('[measure] ${sc.name}: initial ${kb(initial)}, '
          'writing ${durationS.toStringAsFixed(0)} s, $saves saves, '
          'up ${kb(store.total)} in ${store.totalPuts} PUTs '
          '${store.bytes.map((k, v) => MapEntry(k, kb(v)))}, '
          'puts ${store.puts}, down ${kb(store.down)}');
      final beforeClose = store.total;
      await n.closeNotebook();
      // ignore: avoid_print
      print('[measure] ${sc.name}${ops ? ' chunks' : ''}: close uploaded '
          '${kb(store.total - beforeClose)}');
      c.dispose();
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }, skip: _measure ? false : 'set ABELNOTES_MEASURE=1 to measure');
  }

  tearDownAll(() {
    if (!_measure) return;
    // ignore: avoid_print
    print('\n$writtenStrokes strokes written on each page.\n'
        '| page | page file after, JSON / binary | first save | later saves | up per save | '
        'up per stroke | up per minute | up per hour | edit per stroke JSON / binary | up / edit |\n'
        '|---|---|---|---|---|---|---|---|---|---|\n$report');
  });
}
