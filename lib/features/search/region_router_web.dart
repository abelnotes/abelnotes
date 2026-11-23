import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/engine_worker_web.dart';
import 'package:abelnotes/features/search/region_route.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// The router on the web: the same C (abnn_route) as WebAssembly, in the
/// engine's worker, so only the async forms answer.
class RegionRouter {
  RegionRouter._(this._w, this._m);

  final EngineWorker _w;
  final int _m;
  bool _disposed = false;

  /// Native only: on the web use [load].
  static RegionRouter? open(Uint8List model) => null;

  static Future<RegionRouter?> load(Uint8List model) async {
    final w = await EngineWorker.shared();
    if (w == null) return null;
    try {
      final m = ((await w.ask('abnnLoad', {'bytes': model.toJS})) as JSNumber).toDartInt;
      return m == 0 ? null : RegionRouter._(w, m);
    } catch (_) {
      return null;
    }
  }

  /// Native only: on the web use [classifyAsync].
  RegionProbs? classify(List<StrokeData> strokes) => null;

  ({Float32List feats, Float32List glob, Float32List local})? inputs(List<StrokeData> strokes) =>
      null;

  /// Class probabilities of [strokes], null when they hold no points.
  Future<RegionProbs?> classifyAsync(List<StrokeData> strokes) async {
    final g = strokeGroup(strokes);
    if (_disposed || g == null) return null;
    final r = await _w.ask('route', {'m': _m.toJS, 'xy': g.xy.toJS, 'starts': g.starts.toJS});
    if (r == null) return null;
    return RegionProbs.fromLogits([for (final v in (r as JSFloat32Array).toDart) v]);
  }

  /// The model's three inputs, for tests.
  Future<({Float32List feats, Float32List glob, Float32List local})?> inputsAsync(
      List<StrokeData> strokes) async {
    final g = strokeGroup(strokes);
    if (g == null) return null;
    final r = await _w.ask('routerInputs', {'xy': g.xy.toJS, 'starts': g.starts.toJS});
    if (r == null) return null;
    final o = r as JSObject;
    Float32List f(String k) => (o[k] as JSFloat32Array).toDart;
    return (feats: f('feats'), glob: f('glob'), local: f('local'));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _w.ask('abnnFree', {'m': _m.toJS}).ignore();
  }
}

/// [strokes] as the engine takes them (empty strokes dropped), null without points.
({Float32List xy, Int32List starts})? strokeGroup(List<StrokeData> strokes) {
  final kept = [for (final s in strokes) if (s.points.isNotEmpty) s];
  if (kept.isEmpty) return null;
  var n = 0;
  for (final s in kept) {
    n += s.points.length;
  }
  final xy = Float32List(2 * n), st = Int32List(kept.length);
  var k = 0;
  for (var i = 0; i < kept.length; i++) {
    st[i] = k;
    for (final p in kept[i].points) {
      xy[2 * k] = p.x;
      xy[2 * k + 1] = p.y;
      k++;
    }
  }
  return (xy: xy, starts: st);
}
