import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/native_engine_ffi.dart'
    show circuitEngineLibrary;
import 'package:abelnotes/features/search/ink_decode.dart';
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
  InkRecognizer._(this._m, this._meta, this._lexicon, this._free, this._run, this._raster);

  final Pointer<Void> _m;
  final InkModelMeta _meta;
  final InkLexicon? _lexicon;
  final _Free _free;
  final _Run _run;
  final _Raster _raster;
  bool _disposed = false;

  static InkRecognizer? open(Uint8List model, InkModelMeta meta, {InkLexicon? lexicon}) {
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
        lexicon,
        lib.lookupFunction<_FreeC, _Free>('abnn_free'),
        lib.lookupFunction<_RunC, _Run>('abnn_run'),
        lib.lookupFunction<_RasterC, _Raster>('abnn_raster'),
      );
    } on ArgumentError {
      return null; // an older engine without abnn
    }
  }

  /// As [open]; the web's form, which can only load asynchronously.
  static Future<InkRecognizer?> load(Uint8List model, InkModelMeta meta,
          {InkLexicon? lexicon}) async =>
      open(model, meta, lexicon: lexicon);

  Future<List<InkLine>> recognizeAsync(InkSegment seg) async => recognize(seg);

  Future<({Float32List probs, int frames, int classes, InkRaster geometry})?> debugRunAsync(
      InkSegment seg) async {
    final o = debugRun(seg);
    return o == null
        ? null
        : (probs: o.probs, frames: o.frames, classes: o.classes, geometry: o.geometry);
  }

  Future<Float32List> rasterAsync(InkSegment seg) async => debugRun(seg)?.raster ?? Float32List(0);

  /// Every line of handwriting on [page] that reads as text ([keep] skips
  /// segments that are not text, e.g. formulas).
  List<InkLine> recognizePage(PageData page, {bool Function(InkSegment seg)? keep}) {
    if (_disposed) return const [];
    return [
      for (final seg in segmentInk(inkStrokes(page)))
        if (keep == null || keep(seg)) ...recognize(seg),
    ];
  }

  /// The segment's line (lexicon reading first, then the plain one if it differs).
  List<InkLine> recognize(InkSegment seg) {
    final o = debugRun(seg);
    if (o == null) return const [];
    return decodeLines(o.probs, o.frames, o.classes, seg, o.geometry, _meta, _lexicon);
  }

  /// The model's input and output for [seg], for parity tests.
  ({Float32List raster, Float32List probs, int frames, int classes, InkRaster geometry})?
      debugRun(InkSegment seg) {
    if (_disposed) return null;
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
      final raster = Float32List.fromList(img.asTypedList(3 * h * w));
      if (_run(_m, img, 4, dims, out, outNd, outDims) != 0) return null;
      if (outNd.value != 3) return null;
      final frames = outDims[1], classes = outDims[2];
      final probs = Float32List.fromList(out.value.asTypedList(frames * classes));
      return (raster: raster, probs: probs, frames: frames, classes: classes, geometry: r);
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
