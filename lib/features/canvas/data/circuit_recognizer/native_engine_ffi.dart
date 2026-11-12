import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef _CreateC = Pointer<Void> Function(Int32);
typedef _Create = Pointer<Void> Function(int);
typedef _ConvC = Int32 Function(Pointer<Void>, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32,
    Pointer<Float>, Int32, Pointer<Float>);
typedef _Conv = int Function(Pointer<Void>, int, int, int, int, int, int, int, int, int, Pointer<Float>, int,
    Pointer<Float>);
typedef _AddC = Int32 Function(Pointer<Void>, Int32, Int32, Int32);
typedef _Add = int Function(Pointer<Void>, int, int, int);
typedef _ConcatC = Int32 Function(Pointer<Void>, Pointer<Int32>, Int32, Int32);
typedef _Concat = int Function(Pointer<Void>, Pointer<Int32>, int, int);
typedef _SplitC = Int32 Function(Pointer<Void>, Int32, Pointer<Int32>, Pointer<Int32>, Int32);
typedef _Split = int Function(Pointer<Void>, int, Pointer<Int32>, Pointer<Int32>, int);
typedef _PoolC = Int32 Function(Pointer<Void>, Int32, Int32, Int32, Int32);
typedef _Pool = int Function(Pointer<Void>, int, int, int, int);
typedef _UpC = Int32 Function(Pointer<Void>, Int32, Int32, Int32);
typedef _Up = int Function(Pointer<Void>, int, int, int);
typedef _AttnC = Int32 Function(Pointer<Void>, Int32, Int32, Int32, Int32, Int32, Int32, Float);
typedef _Attn = int Function(Pointer<Void>, int, int, int, int, int, int, double);
typedef _RunC = Long Function(Pointer<Void>, Pointer<Float>, Int32, Int32, Pointer<Int32>, Int32, Pointer<Float>, Long);
typedef _Run = int Function(Pointer<Void>, Pointer<Float>, int, int, Pointer<Int32>, int, Pointer<Float>, int);
typedef _DestroyC = Void Function(Pointer<Void>);
typedef _Destroy = void Function(Pointer<Void>);

/// The detector graph on the native engine: built op by op, then run.
/// ABELNOTES_CIRCUIT_NATIVE=0 keeps the detector in Dart (tests, benches).
class NativeEngine {
  NativeEngine._(this._h, DynamicLibrary lib)
      : _conv = lib.lookupFunction<_ConvC, _Conv>('ce_conv'),
        _add = lib.lookupFunction<_AddC, _Add>('ce_add'),
        _concat = lib.lookupFunction<_ConcatC, _Concat>('ce_concat'),
        _split = lib.lookupFunction<_SplitC, _Split>('ce_split'),
        _maxpool = lib.lookupFunction<_PoolC, _Pool>('ce_maxpool'),
        _upsample = lib.lookupFunction<_UpC, _Up>('ce_upsample'),
        _attn = lib.lookupFunction<_AttnC, _Attn>('ce_attn'),
        _run = lib.lookupFunction<_RunC, _Run>('ce_run'),
        _destroy = lib.lookupFunction<_DestroyC, _Destroy>('ce_destroy');

  final Pointer<Void> _h;
  final _Conv _conv;
  final _Add _add;
  final _Concat _concat;
  final _Split _split;
  final _Pool _maxpool;
  final _Up _upsample;
  final _Attn _attn;
  final _Run _run;
  final _Destroy _destroy;

  /// The circuit_engine plugin's library (packages/circuit_engine, built by
  /// each platform's Flutter build); under `flutter test`, its local CMake build.
  static DynamicLibrary? _lib() {
    try {
      if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.open('circuit_engine.framework/circuit_engine');
      if (Platform.isWindows) return DynamicLibrary.open('circuit_engine.dll');
      return DynamicLibrary.open('libcircuit_engine.so');
    } catch (_) {
      // Not bundled (a test run): try the local build.
    }
    final name = Platform.isWindows ? 'circuit_engine.dll' : 'libcircuit_engine.so';
    for (final path in [
      // Never the working directory in the app: it could be anyone's folder.
      if (Platform.environment.containsKey('FLUTTER_TEST'))
        p.join(Directory.current.path, 'packages', 'circuit_engine', 'src', 'build', name),
      p.join(p.dirname(Platform.resolvedExecutable), 'lib', name),
    ]) {
      if (!File(path).existsSync()) continue;
      try {
        return DynamicLibrary.open(path);
      } catch (_) {
        // Wrong architecture or a broken file.
      }
    }
    return null;
  }

  static NativeEngine? open() {
    if (Platform.environment['ABELNOTES_CIRCUIT_NATIVE'] == '0') return null;
    final lib = _lib();
    if (lib == null) return null;
    final create = lib.lookupFunction<_CreateC, _Create>('ce_create');
    final h = create(math.max(1, Platform.numberOfProcessors));
    return h == nullptr ? null : NativeEngine._(h, lib);
  }

  Pointer<Float> _floats(Float32List v) {
    final ptr = malloc<Float>(v.length);
    ptr.asTypedList(v.length).setAll(0, v);
    return ptr;
  }

  Pointer<Int32> _ints(List<int> v) {
    final ptr = malloc<Int32>(v.length);
    ptr.asTypedList(v.length).setAll(0, v);
    return ptr;
  }

  bool conv(int input, int output, int cin, int cout, int k, int s, int p, int g, bool act, Float32List w,
      int wStride, Float32List b) {
    final wp = _floats(w), bp = _floats(b);
    try {
      return _conv(_h, input, output, cin, cout, k, s, p, g, act ? 1 : 0, wp, wStride, bp) == 0;
    } finally {
      malloc.free(wp);
      malloc.free(bp);
    }
  }

  bool add(int a, int b, int output) => _add(_h, a, b, output) == 0;

  bool concat(List<int> inputs, int output) {
    final ip = _ints(inputs);
    try {
      return _concat(_h, ip, inputs.length, output) == 0;
    } finally {
      malloc.free(ip);
    }
  }

  bool split(int input, List<int> outputs, List<int> sizes) {
    final op = _ints(outputs), sp = _ints(sizes);
    try {
      return _split(_h, input, op, sp, outputs.length) == 0;
    } finally {
      malloc.free(op);
      malloc.free(sp);
    }
  }

  bool maxpool(int input, int output, int k, int p) => _maxpool(_h, input, output, k, p) == 0;

  bool upsample(int input, int output, int scale) => _upsample(_h, input, output, scale) == 0;

  bool attn(int input, int outX, int outV, int heads, int keyDim, int headDim, double scale) =>
      _attn(_h, input, outX, outV, heads, keyDim, headDim, scale) == 0;

  /// The tensors [want] after running [gray] (h x w), back to back, or null.
  Float32List? run(Float32List gray, int h, int w, List<int> want, int outLen) {
    final gp = _floats(gray), wp = _ints(want), op = malloc<Float>(outLen);
    try {
      final n = _run(_h, gp, h, w, wp, want.length, op, outLen);
      return n == outLen ? Float32List.fromList(op.asTypedList(outLen)) : null;
    } finally {
      malloc.free(gp);
      malloc.free(wp);
      malloc.free(op);
    }
  }

  void dispose() => _destroy(_h);
}

typedef _PrepC = Int32 Function(Pointer<Uint8>, Int32, Int32, Int32, Int32, Pointer<Uint8>, Pointer<Uint8>,
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Int32>, Pointer<Int32>);
typedef _Prep = int Function(
    Pointer<Uint8>, int, int, int, int, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Int32>, Pointer<Int32>);
typedef _LeftC = Int32 Function(
    Pointer<Uint8>, Int32, Int32, Pointer<Double>, Pointer<Int32>, Pointer<Double>, Int32, Pointer<Uint8>, Pointer<Int32>);
typedef _Left = int Function(
    Pointer<Uint8>, int, int, Pointer<Double>, Pointer<Int32>, Pointer<Double>, int, Pointer<Uint8>, Pointer<Int32>);

typedef _TraceC = Pointer<Void> Function(Pointer<Uint8>, Int32, Int32, Int32, Int32, Double);
typedef _Trace = Pointer<Void> Function(Pointer<Uint8>, int, int, int, int, double);
typedef _CountC = Int32 Function(Pointer<Void>);
typedef _Count = int Function(Pointer<Void>);
typedef _StrokeC = Int32 Function(Pointer<Void>, Int32, Pointer<Pointer<Double>>, Pointer<Double>, Pointer<Int32>);
typedef _Stroke = int Function(Pointer<Void>, int, Pointer<Pointer<Double>>, Pointer<Double>, Pointer<Int32>);
typedef _InkC = Pointer<Uint8> Function(Pointer<Void>);
typedef _Ink = Pointer<Uint8> Function(Pointer<Void>);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);
typedef _RasterC = Void Function(Pointer<Uint8>, Int32, Int32, Double, Double, Double, Double, Int32, Int32, Pointer<Float>);
typedef _Raster = void Function(Pointer<Uint8>, int, int, double, double, double, double, int, int, Pointer<Float>);

/// The picture tidy-up's pixel passes in C (native/circuit_engine/src/image_ink.c),
/// bit for bit the Dart ones in image_ink.dart.
class NativeImage {
  NativeImage._(DynamicLibrary lib)
      : _prep = lib.lookupFunction<_PrepC, _Prep>('ce_trace_prep'),
        _left = lib.lookupFunction<_LeftC, _Left>('ce_leftover'),
        _trace = lib.lookupFunction<_TraceC, _Trace>('ce_trace'),
        _count = lib.lookupFunction<_CountC, _Count>('ce_trace_count'),
        _stroke = lib.lookupFunction<_StrokeC, _Stroke>('ce_trace_stroke'),
        _ink = lib.lookupFunction<_InkC, _Ink>('ce_trace_ink'),
        _free = lib.lookupFunction<_FreeC, _Free>('ce_trace_free'),
        _raster = lib.lookupFunction<_RasterC, _Raster>('ce_rasterize_ink');

  final _Prep _prep;
  final _Left _left;
  final _Trace _trace;
  final _Count _count;
  final _Stroke _stroke;
  final _Ink _ink;
  final _Free _free;
  final _Raster _raster;

  /// The whole trace at cw x ch (scale s): strokes as (points, width, colour)
  /// and the ink mask.
  ({List<(Float64List, double, int)> strokes, Uint8List ink}) trace(
      Uint8List rgba, int w, int h, int cw, int ch, double s) {
    final src = malloc<Uint8>(rgba.length);
    final pts = malloc<Pointer<Double>>(), width = malloc<Double>(), color = malloc<Int32>();
    Pointer<Void> r = nullptr;
    try {
      src.asTypedList(rgba.length).setAll(0, rgba);
      r = _trace(src, w, h, cw, ch, s);
      final out = <(Float64List, double, int)>[];
      for (var i = 0, n = _count(r); i < n; i++) {
        final len = _stroke(r, i, pts, width, color);
        out.add((Float64List.fromList(pts.value.asTypedList(len)), width.value, color.value & 0xFFFFFFFF));
      }
      return (strokes: out, ink: Uint8List.fromList(_ink(r).asTypedList(cw * ch)));
    } finally {
      if (r != nullptr) _free(r);
      malloc.free(src);
      malloc.free(pts);
      malloc.free(width);
      malloc.free(color);
    }
  }

  /// rasterizeInk's plane for a raster of rw x rh at the given geometry.
  Float32List rasterizeInk(Uint8List ink, int w, int h, double inkScale, double originX, double originY, double scale,
      int rw, int rh) {
    final src = malloc<Uint8>(ink.length), out = malloc<Float>(rw * rh);
    try {
      src.asTypedList(ink.length).setAll(0, ink);
      _raster(src, w, h, inkScale, originX, originY, scale, rw, rh, out);
      return Float32List.fromList(out.asTypedList(rw * rh));
    } finally {
      malloc.free(src);
      malloc.free(out);
    }
  }

  /// Tests compare both paths in one process.
  static bool forceDart = false;

  static NativeImage? open() {
    if (forceDart || Platform.environment['ABELNOTES_CIRCUIT_NATIVE'] == '0') return null;
    final lib = NativeEngine._lib();
    if (lib == null) return null;
    try {
      return NativeImage._(lib);
    } catch (_) {
      return null; // an older library without these entry points
    }
  }

  ({Uint8List rgb, Uint8List gray, Uint8List ink, Uint8List skel, Int32List dist, bool tinted}) tracePrep(
      Uint8List rgba, int w, int h, int cw, int ch) {
    final n = cw * ch;
    final src = malloc<Uint8>(rgba.length), rgb = malloc<Uint8>(3 * n), gray = malloc<Uint8>(n);
    final ink = malloc<Uint8>(n), skel = malloc<Uint8>(n), dist = malloc<Int32>(n), tinted = malloc<Int32>(1);
    try {
      src.asTypedList(rgba.length).setAll(0, rgba);
      _prep(src, w, h, cw, ch, rgb, gray, ink, skel, dist, tinted);
      return (
        rgb: Uint8List.fromList(rgb.asTypedList(3 * n)),
        gray: Uint8List.fromList(gray.asTypedList(n)),
        ink: Uint8List.fromList(ink.asTypedList(n)),
        skel: Uint8List.fromList(skel.asTypedList(n)),
        dist: Int32List.fromList(dist.asTypedList(n)),
        tinted: tinted.value != 0,
      );
    } finally {
      for (final ptr in [src, rgb, gray, ink, skel, dist, tinted]) {
        malloc.free(ptr);
      }
    }
  }

  ({Uint8List alpha, int x0, int y0, int x1, int y1, int kept}) leftover(
      Uint8List rgba, int w, int h, List<(Float64List, double)> cut) {
    final total = cut.fold<int>(0, (a, c) => a + c.$1.length);
    final src = malloc<Uint8>(rgba.length), pts = malloc<Double>(math.max(1, total));
    final lens = malloc<Int32>(math.max(1, cut.length)), widths = malloc<Double>(math.max(1, cut.length));
    final alpha = malloc<Uint8>(w * h), box = malloc<Int32>(5);
    try {
      src.asTypedList(rgba.length).setAll(0, rgba);
      var off = 0;
      for (var i = 0; i < cut.length; i++) {
        pts.asTypedList(math.max(1, total)).setAll(off, cut[i].$1);
        off += cut[i].$1.length;
        lens[i] = cut[i].$1.length;
        widths[i] = cut[i].$2;
      }
      _left(src, w, h, pts, lens, widths, cut.length, alpha, box);
      return (
        alpha: Uint8List.fromList(alpha.asTypedList(w * h)),
        x0: box[0],
        y0: box[1],
        x1: box[2],
        y1: box[3],
        kept: box[4],
      );
    } finally {
      for (final ptr in [src, pts, lens, widths, alpha, box]) {
        malloc.free(ptr);
      }
    }
  }
}
