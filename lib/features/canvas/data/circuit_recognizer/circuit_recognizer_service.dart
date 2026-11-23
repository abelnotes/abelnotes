// Runs circuit recognition (detector + wire tracing) on a long-lived isolate.
//
// The model is loaded once; requests carry flat stroke arrays, replies carry new
// polylines in page coordinates plus which input strokes they replace.

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:abelnotes/core/platform/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:abelnotes/features/modules/bundled_model.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import '../ink_recognizer/model_file.dart';
import 'circuit_graph.dart';
import 'detector.dart';
import 'native_engine.dart';
import 'raster.dart';

const String kCircuitModelFileName = 'circuit_detector.ablm';
const String kBundledCircuitModelAsset = 'assets/models/$kCircuitModelFileName';

/// sha256 of the bundled model; test/circuit_model_asset_test.dart pins it.
const String kBundledCircuitModelSha256 =
    'c8b7b40843559e48c8875d30a9094d3ab03348f27048cfa840c436430c2ea4f4';

/// The longer side of a drawing, in model pixels, the detector reads: outside
/// [kMinSidePx]..[kMaxSidePx] a miss is retried at [kRetrySidePx].
const double kMinSidePx = 160;
const double kMaxSidePx = 800;
const double kRetrySidePx = 320;

/// Auto-disposed: a module switched off in Settings frees its isolate.
final circuitRecognizerProvider = FutureProvider.autoDispose<CircuitRecognizer?>((ref) async {
  if (kIsWeb) return CircuitRecognizer.loadInline();
  final dir = await getApplicationSupportDirectory();
  final path = '${dir.path}${Platform.pathSeparator}models${Platform.pathSeparator}$kCircuitModelFileName';
  await installBundledModel(
      path, kBundledCircuitModelSha256, () => rootBundle.load(kBundledCircuitModelAsset));
  final r = await CircuitRecognizer.load(path);
  ref.onDispose(() => r?.dispose());
  return r;
});

/// How an added polyline is drawn: the user's ink kept as drawn, or a clean
/// line: thin (wires, leads), twice as thick (part outlines), or filled.
enum CircuitInk { drawn, wire, body, fill }

class CircuitResult {
  CircuitResult(this.removed, this.added, this.sources, this.components, this.milliseconds, this.error,
      {this.kinds = const [], this.rlen = 0});

  /// Indices into the request's strokes that the new drawing replaces.
  final Set<int> removed;

  /// New polylines in page coordinates, flat [x0, y0, x1, y1, ...].
  final List<Float64List> added;

  /// For each added polyline, the request stroke whose style it takes, or -1.
  final List<int> sources;

  /// For each added polyline, how it is drawn.
  final List<CircuitInk> kinds;

  /// CircuiTikZ's basic length the symbols were drawn at, in page units.
  final double rlen;
  final int components;
  final int milliseconds;
  final String? error;

  bool get ok => error == null && components > 0;

  /// Parts were found and some ink gives way to them.
  bool get replaced => ok && removed.isNotEmpty;
}

class CircuitRecognizer {
  CircuitRecognizer._(Isolate this._isolate, SendPort this._toIsolate, Stream<dynamic> this._responses)
      : _inline = null,
        worker = null;
  CircuitRecognizer._inline(CircuitDetector this._inline, this.worker)
      : _isolate = null,
        _toIsolate = null,
        _responses = null;

  final Isolate? _isolate;
  final SendPort? _toIsolate;
  final Stream<dynamic>? _responses;

  /// Web has no isolates: the detector runs on the UI thread, on the
  /// engine's WebAssembly build (the Dart forward pass would take seconds).
  final CircuitDetector? _inline;

  /// With [_inline], the engine in a Web Worker: the heavy passes run there
  /// and the UI thread only does the light Dart steps around them. Null
  /// elsewhere, or where a worker can't start (the UI thread then runs all).
  final CircuitWorker? worker;
  var _nextId = 0;
  var _disposed = false;

  static Future<CircuitRecognizer?> load(String path) async {
    if (!File(path).existsSync()) return null;
    final ready = ReceivePort();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(_isolateMain, [ready.sendPort, path], debugName: 'circuit-recognizer');
    } catch (e) {
      ready.close();
      debugPrint('[circuit] isolate spawn failed: $e');
      return null;
    }
    final responses = ready.asBroadcastStream();
    final handshake = await responses.first;
    if (handshake is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      ready.close();
      debugPrint('[circuit] model load failed: $handshake');
      return null;
    }
    return CircuitRecognizer._(isolate, handshake, responses);
  }

  /// The bundled model with the WebAssembly engine; null when either is
  /// missing.
  static Future<CircuitRecognizer?> loadInline() async {
    try {
      if (!await loadNativeEngine()) return null;
      final data = await rootBundle.load(kBundledCircuitModelAsset);
      final det = CircuitDetector.fromModelFile(
          await ModelFile.parseAsync(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
      return CircuitRecognizer._inline(det, await CircuitWorker.start(det.buildGraph));
    } catch (e) {
      debugPrint('[circuit] model load failed: $e');
      return null;
    }
  }

  /// [pageWidth] fixes the scale: the detector expects page width ~1024 px.
  /// [ink], for a traced picture, is what the detector looks at instead of
  /// the strokes redrawn.
  Future<CircuitResult> recognize(List<StrokeData> strokes, double pageWidth, {InkMask? ink}) async {
    if (_disposed || strokes.isEmpty) return CircuitResult({}, [], [], 0, 0, 'nothing to recognize');
    final flat = [
      for (final s in strokes) Float64List.fromList([for (final p in s.points) ...[p.x, p.y]])
    ];
    final inline = _inline;
    if (inline != null) {
      // A frame for the busy indicator before the UI thread is taken.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final watch = Stopwatch()..start();
      try {
        final w = worker;
        if (w != null) return await runOn(w, inline, flat, pageWidth, watch, ink);
        return run(inline, flat, pageWidth, watch, ink);
      } catch (e) {
        return CircuitResult({}, [], [], 0, watch.elapsedMilliseconds, '$e');
      }
    }
    final id = _nextId++;
    _toIsolate!.send(_Request(id, flat, pageWidth, ink));
    final reply = await _responses!.firstWhere((m) => m is _Reply && m.id == id,
        orElse: () => _Reply(id, CircuitResult({}, [], [], 0, 0, 'isolate closed'))) as _Reply;
    return reply.result;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    worker?.dispose();
  }

  static void _isolateMain(List<dynamic> args) {
    final ready = args[0] as SendPort;
    final CircuitDetector det;
    try {
      det = CircuitDetector.fromModelFile(ModelFile.parse(File(args[1] as String).readAsBytesSync()));
    } catch (e) {
      ready.send('$e');
      return;
    }
    final inbox = ReceivePort();
    ready.send(inbox.sendPort);
    inbox.listen((m) {
      if (m is! _Request) return;
      final watch = Stopwatch()..start();
      CircuitResult result;
      try {
        result = run(det, m.strokes, m.pageWidth, watch, m.ink);
      } catch (e) {
        result = CircuitResult({}, [], [], 0, watch.elapsedMilliseconds, '$e');
      }
      ready.send(_Reply(m.id, result));
    });
  }

  /// The whole pipeline, synchronous; public for tests.
  ///
  /// Page width sets the scale only as far as people draw at one size on a
  /// page. Ink drawn zoomed far in or out comes out too small or too large for
  /// the detector, so a miss there is retried with the drawing at a size it
  /// reads well.
  static CircuitResult run(CircuitDetector det, List<Float64List> strokes, double pageWidth,
      [Stopwatch? watch, InkMask? ink]) {
    final first = _runAt(det, strokes, pageWidth, watch, ink);
    if (ink != null || first.replaced) return first;
    final retry = retryPageWidth(strokes, pageWidth);
    if (retry == null) return first;
    final second = _runAt(det, strokes, retry, watch, null);
    return second.replaced ? second : first;
  }

  /// [run] with the detector's forward pass on [worker].
  static Future<CircuitResult> runOn(CircuitWorker worker, CircuitDetector det, List<Float64List> strokes,
      double pageWidth, [Stopwatch? watch, InkMask? ink]) async {
    Future<CircuitResult> at(double pw, InkMask? ink) async {
      final r = _raster(strokes, pw, ink);
      final outs = det.engineOutputs(r.height, r.width);
      final heads = r.data.isEmpty ? null : await worker.run(r.data, r.height, r.width, outs.want, outs.floats);
      final dets = det.detect(r.data, r.height, r.width,
          raw: heads == null ? null : det.decodeEngine(heads, r.height, r.width));
      return _finish(r, strokes, dets, watch);
    }

    final first = await at(pageWidth, ink);
    if (ink != null || first.replaced) return first;
    final retry = retryPageWidth(strokes, pageWidth);
    if (retry == null) return first;
    final second = await at(retry, null);
    return second.replaced ? second : first;
  }

  /// The page width at which [strokes]' longer side takes [kRetrySidePx]
  /// model pixels, or null when it is already at a size the detector reads.
  static double? retryPageWidth(List<Float64List> strokes, double pageWidth) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final s in strokes) {
      for (var i = 0; i + 1 < s.length; i += 2) {
        minX = math.min(minX, s[i]);
        maxX = math.max(maxX, s[i]);
        minY = math.min(minY, s[i + 1]);
        maxY = math.max(maxY, s[i + 1]);
      }
    }
    final side = math.max(maxX - minX, maxY - minY);
    if (!side.isFinite || side <= 0 || pageWidth <= 0) return null;
    final px = side * kModelPageWidthPx / pageWidth;
    if (px >= kMinSidePx && px <= kMaxSidePx) return null;
    return side * kModelPageWidthPx / kRetrySidePx;
  }

  static CircuitResult _runAt(CircuitDetector det, List<Float64List> strokes, double pageWidth,
      [Stopwatch? watch, InkMask? ink]) {
    final r = _raster(strokes, pageWidth, ink);
    return _finish(r, strokes, det.detect(r.data, r.height, r.width), watch);
  }

  static Raster _raster(List<Float64List> strokes, double pageWidth, InkMask? ink) =>
      ink == null ? rasterize(strokes, pageWidth) : rasterizeInk(ink, strokes, pageWidth);

  static CircuitResult _finish(Raster r, List<Float64List> strokes, List<Detection> dets, Stopwatch? watch) {
    final px = [
      for (final s in strokes) [for (var i = 0; i + 1 < s.length; i += 2) Pt(r.toPxX(s[i]), r.toPxY(s[i + 1]))]
    ];
    final out = rewriteCircuit(px, dets);
    return CircuitResult(
      out.removed,
      [for (final o in out.added) Float64List.fromList([for (final p in o.points) ...[r.toPageX(p.x), r.toPageY(p.y)]])],
      [for (final o in out.added) o.source],
      out.components.length,
      watch?.elapsedMilliseconds ?? 0,
      null,
      kinds: [
        for (final o in out.added)
          o.fill
              ? CircuitInk.fill
              : o.body
                  ? CircuitInk.body
                  : (o.clean ? CircuitInk.wire : CircuitInk.drawn)
      ],
      rlen: out.rlen / r.scale,
    );
  }
}

class _Request {
  _Request(this.id, this.strokes, this.pageWidth, this.ink);
  final int id;
  final List<Float64List> strokes;
  final double pageWidth;
  final InkMask? ink;
}

class _Reply {
  _Reply(this.id, this.result);
  final int id;
  final CircuitResult result;
}
