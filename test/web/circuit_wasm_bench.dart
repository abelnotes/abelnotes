// The circuit engine's WebAssembly build against the Dart path, in a browser:
// same detections, same traced lines, and the time each takes on the UI
// thread. Built and run by tool/web_circuit_bench.sh; prints one JSON line
// "CIRCUIT_BENCH {...}" to the console.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_recognizer_service.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/detector.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/image_ink.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/native_engine.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/raster.dart';
import 'package:abelnotes/features/canvas/data/ink_recognizer/model_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:web/web.dart' as web;

Future<String> _get(String url) async => (await (await web.window.fetch(url.toJS).toDart).text().toDart).toDart;

Future<Uint8List> _bytes(String url) async =>
    (await (await web.window.fetch(url.toJS).toDart).arrayBuffer().toDart).toDart.asUint8List();

String _sig(CircuitResult r) =>
    '${r.components} ${(r.removed.toList()..sort()).join(',')} '
    '${r.added.map((a) => a.map((v) => v.toStringAsFixed(3)).join(',')).join(';')} ${r.kinds.join(',')}';

double _worst(Float32List a, Float32List b) {
  if (a.length != b.length) return double.infinity;
  var w = 0.0;
  for (var i = 0; i < a.length; i++) {
    w = math.max(w, (a[i] - b[i]).abs() / math.max(1.0, a[i].abs()));
  }
  return w;
}

bool _same<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// [f]'s result, its time, and the longest the UI thread went without a
/// timer tick meanwhile (what a user would feel as a freeze).
Future<({T value, int ms, int gap})> _offThread<T>(Future<T> Function() f) async {
  final watch = Stopwatch()..start();
  var last = 0, gap = 0;
  final tick = Timer.periodic(const Duration(milliseconds: 5), (_) {
    final now = watch.elapsedMilliseconds;
    gap = math.max(gap, now - last);
    last = now;
  });
  final v = await f();
  tick.cancel();
  final end = watch.elapsedMilliseconds;
  return (value: v, ms: end, gap: math.max(gap, end - last));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final report = <String, Object?>{};
  final cases = <Map<String, Object?>>[];
  report['cases'] = cases;
  try {
    report['wasm'] = await loadNativeEngine();
    final data = await rootBundle.load(kBundledCircuitModelAsset);
    final det = CircuitDetector.fromModelFile(
        ModelFile.parse(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
    final index = jsonDecode(await _get('bench/index.json')) as Map<String, dynamic>;
    final watch = Stopwatch();

    det.profile = null;
    watch.start();
    det.forward(Float32List(64 * 64)..fillRange(0, 64 * 64, 1), 64, 64);
    report['graphBuildMs'] = watch.elapsedMilliseconds;

    final worker = await CircuitWorker.start(det.buildGraph);
    report['worker'] = worker != null;

    for (final name in (index['strokes'] as List).cast<String>()) {
      final j = jsonDecode(await _get('bench/$name')) as Map<String, dynamic>;
      final strokes = [
        for (final s in j['strokes'] as List) Float64List.fromList([for (final v in s as List) (v as num).toDouble()])
      ];
      // As drawn, and zoomed out (the retry path).
      for (final scale in [1.0, 3.0]) {
        final pw = (j['pageWidth'] as num).toDouble() * scale;
        final r = rasterize(strokes, pw);
        det.profile = <String, int>{};
        final fd = det.forward(r.data, r.height, r.width);
        watch.reset();
        final rd = CircuitRecognizer.run(det, strokes, pw);
        final tDart = watch.elapsedMilliseconds;
        det.profile = null;
        watch.reset();
        final fw = det.forward(r.data, r.height, r.width);
        final tForward = watch.elapsedMilliseconds;
        watch.reset();
        final rw = CircuitRecognizer.run(det, strokes, pw);
        final tWasm = watch.elapsedMilliseconds;
        final off = worker == null ? null : await _offThread(() => CircuitRecognizer.runOn(worker, det, strokes, pw));
        cases.add({
          'case': '$name x$scale',
          'size': '${r.width}x${r.height}',
          'dartMs': tDart,
          'wasmMs': tWasm,
          'wasmForwardMs': tForward,
          'workerMs': off?.ms,
          'workerUiGapMs': off?.gap,
          'forwardWorstRel': _worst(fd, fw),
          'components': rw.components,
          'sameResult': _sig(rd) == _sig(rw),
          'sameWorker': off == null ? null : _sig(rd) == _sig(off.value),
        });
      }
    }

    for (final name in (index['images'] as List).cast<String>()) {
      final im = img.decodeImage(await _bytes('bench/$name'))!.convert(numChannels: 4);
      final rgba = im.getBytes(order: img.ChannelOrder.rgba);
      final w = im.width, h = im.height;
      NativeImage.forceDart = true;
      det.profile = <String, int>{};
      watch.reset();
      final a = traceImage(rgba, w, h);
      final tTraceDart = watch.elapsedMilliseconds;
      final ra = rasterizeInk(a.ink, [for (final s in a.strokes) s.points], w.toDouble());
      final da = det.detect(ra.data, ra.height, ra.width);
      final tDart = watch.elapsedMilliseconds;
      final cut = [for (final s in a.strokes.take(a.strokes.length ~/ 2)) (s.points, s.width)];
      watch.reset();
      final la = inkLeftover(rgba, w, h, cut);
      final lDart = watch.elapsedMilliseconds;

      NativeImage.forceDart = false;
      det.profile = null;
      watch.reset();
      final b = traceImage(rgba, w, h);
      final tTraceWasm = watch.elapsedMilliseconds;
      final rb = rasterizeInk(b.ink, [for (final s in b.strokes) s.points], w.toDouble());
      final db = det.detect(rb.data, rb.height, rb.width);
      final tWasm = watch.elapsedMilliseconds;
      watch.reset();
      final lb = inkLeftover(rgba, w, h, cut);
      final lWasm = watch.elapsedMilliseconds;

      String dets(List<Detection> d) => d.map((e) => '${e.cls} ${e.x0.round()} ${e.y0.round()}').join(';');
      bool sameTrace(({List<TracedStroke> strokes, InkMask ink}) x, ({List<TracedStroke> strokes, InkMask ink}) y) {
        if (x.strokes.length != y.strokes.length || !_same(x.ink.data, y.ink.data)) return false;
        for (var i = 0; i < x.strokes.length; i++) {
          if (!_same(x.strokes[i].points, y.strokes[i].points) ||
              x.strokes[i].width != y.strokes[i].width ||
              x.strokes[i].color != y.strokes[i].color) {
            return false;
          }
        }
        return true;
      }

      bool sameLeft((Uint8List, int, int, int, int)? x, (Uint8List, int, int, int, int)? y) =>
          (x == null) == (y == null) &&
          (x == null || (x.$2 == y!.$2 && x.$3 == y.$3 && x.$4 == y.$4 && _same(x.$1, y.$1)));

      final row = <String, Object?>{
        'case': name,
        'size': '${w}x$h',
        'traceDartMs': tTraceDart,
        'traceWasmMs': tTraceWasm,
        'dartMs': tDart,
        'wasmMs': tWasm,
        'leftoverDartMs': lDart,
        'leftoverWasmMs': lWasm,
        'traceSame': sameTrace(a, b),
        'rasterSame': _same(ra.data, rb.data),
        'detections': db.length,
        'sameDetections': dets(da) == dets(db),
        'leftoverSame': sameLeft(la, lb),
      };
      if (worker != null) {
        // The picture path as the app runs it on the web.
        final off = await _offThread(() async {
          final t = await traceImageOn(worker, rgba, w, h);
          final res = await CircuitRecognizer.runOn(
              worker, det, [for (final s in t.strokes) s.points], w.toDouble(), null, t.ink);
          final l = await inkLeftoverOn(worker, rgba, w, h, cut);
          return (t, res, l);
        });
        final full = CircuitRecognizer.run(det, [for (final s in a.strokes) s.points], w.toDouble(), null, a.ink);
        row['workerMs'] = off.ms;
        row['workerUiGapMs'] = off.gap;
        row['sameWorker'] =
            sameTrace(a, off.value.$1) && _sig(full) == _sig(off.value.$2) && sameLeft(la, off.value.$3);
      }
      cases.add(row);
    }
  } catch (e, st) {
    report['error'] = '$e\n$st';
  }
  // ignore: avoid_print
  print('CIRCUIT_BENCH ${jsonEncode(report)}');
}
