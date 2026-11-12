// Runs circuit recognition (detector + wire tracing) on a long-lived isolate.
//
// The model is loaded once; requests carry flat stroke arrays, replies carry new
// polylines in page coordinates plus which input strokes they replace.

import 'dart:async';
import 'dart:isolate';

import 'package:abelnotes/core/platform/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:abelnotes/shared/models/ncnote_format.dart';

import '../ink_recognizer/model_file.dart';
import 'circuit_graph.dart';
import 'detector.dart';
import 'raster.dart';

const String kCircuitModelFileName = 'circuit_detector.ablm';
const String kBundledCircuitModelAsset = 'assets/models/$kCircuitModelFileName';

/// sha256 of the bundled model; test/circuit_model_asset_test.dart pins it.
const String kBundledCircuitModelSha256 =
    'c8b7b40843559e48c8875d30a9094d3ab03348f27048cfa840c436430c2ea4f4';

/// Auto-disposed: a module switched off in Settings frees its isolate.
final circuitRecognizerProvider = FutureProvider.autoDispose<CircuitRecognizer?>((ref) async {
  // Not offered on the web: there the detector would freeze the UI for seconds.
  if (kIsWeb) return null;
  final dir = await getApplicationSupportDirectory();
  final path = '${dir.path}${Platform.pathSeparator}models${Platform.pathSeparator}$kCircuitModelFileName';
  await installBundledCircuitModel(
      path, kBundledCircuitModelSha256, () => rootBundle.load(kBundledCircuitModelAsset));
  final r = await CircuitRecognizer.load(path);
  ref.onDispose(() => r?.dispose());
  return r;
});

/// Copies the bundled model to [path] unless the copy there is that very file:
/// a stamp beside it records the installed hash, since two models can have the
/// same length. [load] runs only when a copy is needed.
Future<void> installBundledCircuitModel(String path, String sha256, Future<ByteData> Function() load) async {
  final file = File(path);
  final stamp = File('$path.sha256');
  if (file.existsSync() && stamp.existsSync() && stamp.readAsStringSync().trim() == sha256) return;
  final ByteData data;
  try {
    data = await load();
  } catch (e) {
    debugPrint('[circuit] bundled model missing: $e');
    return;
  }
  await file.parent.create(recursive: true);
  // Stamp last, so a copy cut short is redone at the next start.
  if (stamp.existsSync()) await stamp.delete();
  final tmp = File('$path.tmp');
  await tmp.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
  await tmp.rename(path);
  await stamp.writeAsString(sha256, flush: true);
}

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
}

class CircuitRecognizer {
  CircuitRecognizer._(this._isolate, this._toIsolate, this._responses);

  final Isolate _isolate;
  final SendPort _toIsolate;
  final Stream<dynamic> _responses;
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

  /// [pageWidth] fixes the scale: the detector expects page width ~1024 px.
  /// [ink], for a traced picture, is what the detector looks at instead of
  /// the strokes redrawn.
  Future<CircuitResult> recognize(List<StrokeData> strokes, double pageWidth, {InkMask? ink}) async {
    if (_disposed || strokes.isEmpty) return CircuitResult({}, [], [], 0, 0, 'nothing to recognize');
    final flat = [
      for (final s in strokes) Float64List.fromList([for (final p in s.points) ...[p.x, p.y]])
    ];
    final id = _nextId++;
    _toIsolate.send(_Request(id, flat, pageWidth, ink));
    final reply = await _responses.firstWhere((m) => m is _Reply && m.id == id,
        orElse: () => _Reply(id, CircuitResult({}, [], [], 0, 0, 'isolate closed'))) as _Reply;
    return reply.result;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate.kill(priority: Isolate.beforeNextEvent);
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
  static CircuitResult run(CircuitDetector det, List<Float64List> strokes, double pageWidth,
      [Stopwatch? watch, InkMask? ink]) {
    final r = ink == null ? rasterize(strokes, pageWidth) : rasterizeInk(ink, strokes, pageWidth);
    final dets = det.detect(r.data, r.height, r.width);
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
