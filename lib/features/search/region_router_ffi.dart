import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/native_engine_ffi.dart'
    show circuitEngineLibrary;
import 'package:abelnotes/features/search/region_route.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

typedef _LoadC = Pointer<Void> Function(Pointer<Uint8>, Size);
typedef _Load = Pointer<Void> Function(Pointer<Uint8>, int);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);
typedef _RouteC = Int32 Function(Pointer<Void>, Pointer<Float>, Pointer<Int32>, Int32, Int32,
    Pointer<Float>);
typedef _Route = int Function(Pointer<Void>, Pointer<Float>, Pointer<Int32>, int, int,
    Pointer<Float>);
typedef _InputsC = Int32 Function(Pointer<Float>, Pointer<Int32>, Int32, Int32, Pointer<Float>,
    Pointer<Float>, Pointer<Float>);
typedef _Inputs = int Function(Pointer<Float>, Pointer<Int32>, int, int, Pointer<Float>,
    Pointer<Float>, Pointer<Float>);

/// Says what a group of strokes is with the bundled router model
/// ([regionRouterAsset]); features, rasters and model all run in C.
class RegionRouter {
  RegionRouter._(this._m, this._free, this._route, this._inputs);

  final Pointer<Void> _m;
  final _Free _free;
  final _Route _route;
  final _Inputs _inputs;
  bool _disposed = false;

  static RegionRouter? open(Uint8List model) {
    final lib = circuitEngineLibrary();
    if (lib == null) return null;
    try {
      final load = lib.lookupFunction<_LoadC, _Load>('abnn_load');
      final route = lib.lookupFunction<_RouteC, _Route>('abnn_route');
      final inputs = lib.lookupFunction<_InputsC, _Inputs>('abnn_router_inputs');
      final buf = malloc<Uint8>(model.length);
      buf.asTypedList(model.length).setAll(0, model);
      final m = load(buf, model.length);
      malloc.free(buf);
      if (m == nullptr) return null;
      return RegionRouter._(m, lib.lookupFunction<_FreeC, _Free>('abnn_free'), route, inputs);
    } on ArgumentError {
      return null; // an older engine without the router
    }
  }

  /// As [open]; the web's form, which can only load asynchronously.
  static Future<RegionRouter?> load(Uint8List model) async => open(model);

  Future<RegionProbs?> classifyAsync(List<StrokeData> strokes) async => classify(strokes);

  Future<({Float32List feats, Float32List glob, Float32List local})?> inputsAsync(
          List<StrokeData> strokes) async =>
      inputs(strokes);

  /// Class probabilities of [strokes], null when they hold no points.
  RegionProbs? classify(List<StrokeData> strokes) {
    if (_disposed) return null;
    return _withPoints(strokes, (xy, st, ns, np) {
      final lg = malloc<Float>(4);
      try {
        if (_route(_m, xy, st, ns, np, lg) != 0) return null;
        return RegionProbs.fromLogits([for (var i = 0; i < 4; i++) lg[i]]);
      } finally {
        malloc.free(lg);
      }
    });
  }

  /// The model's three inputs (24 features, 64x64 and 32x192 views), for tests.
  ({Float32List feats, Float32List glob, Float32List local})? inputs(List<StrokeData> strokes) {
    if (_disposed) return null;
    return _withPoints(strokes, (xy, st, ns, np) {
      final f = malloc<Float>(24), g = malloc<Float>(64 * 64), l = malloc<Float>(32 * 192);
      try {
        if (_inputs(xy, st, ns, np, f, g, l) != 0) return null;
        return (
          feats: Float32List.fromList(f.asTypedList(24)),
          glob: Float32List.fromList(g.asTypedList(64 * 64)),
          local: Float32List.fromList(l.asTypedList(32 * 192)),
        );
      } finally {
        malloc
          ..free(f)
          ..free(g)
          ..free(l);
      }
    });
  }

  T? _withPoints<T>(List<StrokeData> strokes,
      T? Function(Pointer<Float> xy, Pointer<Int32> st, int ns, int np) run) {
    final kept = [for (final s in strokes) if (s.points.isNotEmpty) s];
    if (kept.isEmpty) return null;
    var n = 0;
    for (final s in kept) {
      n += s.points.length;
    }
    final xy = malloc<Float>(2 * n);
    final st = malloc<Int32>(kept.length);
    try {
      var k = 0;
      for (var i = 0; i < kept.length; i++) {
        st[i] = k;
        for (final p in kept[i].points) {
          xy[2 * k] = p.x;
          xy[2 * k + 1] = p.y;
          k++;
        }
      }
      return run(xy, st, kept.length, n);
    } finally {
      malloc
        ..free(xy)
        ..free(st);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _free(_m);
  }
}
