import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/native_engine_ffi.dart'
    show circuitEngineLibrary;
import 'package:abelnotes/features/search/ink_text.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

typedef _LoadC = Pointer<Void> Function(Pointer<Uint8>, Size);
typedef _Load = Pointer<Void> Function(Pointer<Uint8>, int);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);
typedef _RunC = Int32 Function(Pointer<Void>, Pointer<Float>, Int32, Pointer<Int64>,
    Pointer<Pointer<Float>>, Pointer<Int32>, Pointer<Int64>);
typedef _Run = int Function(Pointer<Void>, Pointer<Float>, int, Pointer<Int64>,
    Pointer<Pointer<Float>>, Pointer<Int32>, Pointer<Int64>);
typedef _RasterC = Void Function(Pointer<Float>, Pointer<Int32>, Int32, Int32, Float, Int32,
    Int32, Pointer<Float>);
typedef _Raster = void Function(Pointer<Float>, Pointer<Int32>, int, int, double, int, int,
    Pointer<Float>);

/// Reads handwritten lines with the bundled model (assets/models/handwriting_text.*).
class InkRecognizer {
  InkRecognizer._(this._m, this._meta, this._free, this._run, this._raster);

  final Pointer<Void> _m;
  final InkModelMeta _meta;
  final _Free _free;
  final _Run _run;
  final _Raster _raster;
  bool _disposed = false;

  static InkRecognizer? open(Uint8List model, InkModelMeta meta) {
    final lib = circuitEngineLibrary();
    if (lib == null) return null;
    try {
      final load = lib.lookupFunction<_LoadC, _Load>('abnn_load');
      final buf = malloc<Uint8>(model.length);
      buf.asTypedList(model.length).setAll(0, model);
      final m = load(buf, model.length);
      malloc.free(buf);
      if (m == nullptr) return null;
      return InkRecognizer._(
        m,
        meta,
        lib.lookupFunction<_FreeC, _Free>('abnn_free'),
        lib.lookupFunction<_RunC, _Run>('abnn_run'),
        lib.lookupFunction<_RasterC, _Raster>('abnn_raster'),
      );
    } on ArgumentError {
      return null; // an older engine without abnn
    }
  }

  /// Every line of handwriting on [page] that reads as text.
  List<InkLine> recognizePage(PageData page) {
    if (_disposed) return const [];
    return [
      for (final seg in segmentInk(inkStrokes(page))) recognize(seg),
    ].whereType<InkLine>().toList();
  }

  InkLine? recognize(InkSegment seg) {
    final r = rasterGeometry(seg, _meta);
    final h = _meta.height, w = r.width;
    final xy = malloc<Float>(math.max(1, r.xy.length));
    final st = malloc<Int32>(math.max(1, r.starts.length));
    final img = malloc<Float>(3 * h * w);
    final dims = malloc<Int64>(4);
    final out = malloc<Pointer<Float>>();
    final outNd = malloc<Int32>();
    final outDims = malloc<Int64>(6);
    try {
      xy.asTypedList(r.xy.length).setAll(0, r.xy);
      st.asTypedList(r.starts.length).setAll(0, r.starts);
      final lw = math.max(1.0, (_meta.lineWidth * r.scale / 2).roundToDouble());
      _raster(xy, st, r.starts.length, r.xy.length ~/ 2, lw, w, h, img);
      dims.asTypedList(4).setAll(0, [1, 3, h, w]);
      if (_run(_m, img, 4, dims, out, outNd, outDims) != 0) return null;
      if (outNd.value != 3) return null;
      final frames = outDims[1], classes = outDims[2];
      final probs = Float32List.fromList(out.value.asTypedList(frames * classes));
      return decodeCtc(probs, frames, classes, seg, r, _meta);
    } finally {
      malloc
        ..free(xy)
        ..free(st)
        ..free(img)
        ..free(dims)
        ..free(out)
        ..free(outNd)
        ..free(outDims);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _free(_m);
  }
}
