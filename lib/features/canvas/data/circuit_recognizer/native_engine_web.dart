// The circuit engine (packages/circuit_engine) on the web: the same C built
// to WebAssembly by tool/build_circuit_wasm.sh, served as web/circuit_engine.wasm.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'engine_graph.dart';
import 'engine_worker_web.dart';

@JS('WebAssembly.instantiate')
external JSPromise<JSObject> _instantiate(JSArrayBuffer bytes, JSObject imports);

/// The module's exports, called by name.
class _Ce {
  _Ce(this._x);
  final JSObject _x;

  num _call(String name, List<Object> args) {
    final r = _x.callMethodVarArgs<JSNumber?>(name.toJS, [for (final a in args) (a as num).toJS]);
    return r?.toDartDouble ?? 0;
  }

  int _int(String name, List<Object> args) => _call(name, args).toInt();

  JSArrayBuffer get buffer => (_x['memory'] as JSObject)['buffer'] as JSArrayBuffer;

  int malloc(int bytes) => _int('ce_malloc', [bytes]);
  void free(int ptr) => _call('ce_free', [ptr]);
  int create(int threads) => _int('ce_create', [threads]);
  int conv(int h, int input, int output, int cin, int cout, int k, int s, int p, int g, int act, int w, int wStride,
          int b) =>
      _int('ce_conv', [h, input, output, cin, cout, k, s, p, g, act, w, wStride, b]);
  int add(int h, int a, int b, int output) => _int('ce_add', [h, a, b, output]);
  int concat(int h, int ins, int count, int output) => _int('ce_concat', [h, ins, count, output]);
  int split(int h, int input, int outs, int sizes, int count) => _int('ce_split', [h, input, outs, sizes, count]);
  int maxpool(int h, int input, int output, int k, int p) => _int('ce_maxpool', [h, input, output, k, p]);
  int upsample(int h, int input, int output, int scale) => _int('ce_upsample', [h, input, output, scale]);
  int attn(int h, int input, int outX, int outV, int heads, int kd, int hd, double scale) =>
      _int('ce_attn', [h, input, outX, outV, heads, kd, hd, scale]);
  int run(int h, int gray, int height, int width, int want, int nWant, int out, int outLen) =>
      _int('ce_run', [h, gray, height, width, want, nWant, out, outLen]);
  void destroy(int h) => _call('ce_destroy', [h]);
  int tracePrep(int rgba, int w, int h, int cw, int ch, int rgb, int gray, int ink, int skel, int dist, int tinted) =>
      _int('ce_trace_prep', [rgba, w, h, cw, ch, rgb, gray, ink, skel, dist, tinted]);
  int leftover(int rgba, int w, int h, int cutPts, int cutLens, int cutWidths, int nCuts, int alpha, int box) =>
      _int('ce_leftover', [rgba, w, h, cutPts, cutLens, cutWidths, nCuts, alpha, box]);
  int trace(int rgba, int w, int h, int cw, int ch, double s) => _int('ce_trace', [rgba, w, h, cw, ch, s]);
  int traceCount(int r) => _int('ce_trace_count', [r]);
  int traceStroke(int r, int i, int pts, int width, int color) => _int('ce_trace_stroke', [r, i, pts, width, color]);
  int traceInk(int r) => _int('ce_trace_ink', [r]);
  void traceFree(int r) => _call('ce_trace_free', [r]);
  void rasterizeInk(int ink, int w, int h, double inkScale, double originX, double originY, double scale, int rw,
          int rh, int out) =>
      _call('ce_rasterize_ink', [ink, w, h, inkScale, originX, originY, scale, rw, rh, out]);
}

_Ce? _module;
Future<bool>? _loading;

/// Fetches and instantiates the engine once; false where it can't run.
Future<bool> loadNativeEngine() => _loading ??= _load();

Future<bool> _load() async {
  try {
    final res = await web.window.fetch('circuit_engine.wasm'.toJS).toDart;
    if (!res.ok) return false;
    final bytes = await res.arrayBuffer().toDart;
    final source = await _instantiate(bytes, JSObject()).toDart;
    final exports = (source['instance'] as JSObject)['exports'] as JSObject;
    // A WASI reactor runs its constructors here before any other call.
    if (exports.has('_initialize')) exports.callMethod('_initialize'.toJS);
    _module = _Ce(exports);
    return true;
  } catch (_) {
    return false;
  }
}

/// The module's memory as bytes; taken again after every call that may grow it.
ByteBuffer _heap(_Ce ce) => ce.buffer.toDart;

/// Buffers in the module's memory, freed together.
class _Arena {
  _Arena(this.ce);
  final _Ce ce;
  final _ptrs = <int>[];

  int alloc(int bytes) {
    final p = ce.malloc(math.max(1, bytes));
    if (p == 0) throw StateError('circuit engine out of memory');
    _ptrs.add(p);
    return p;
  }

  int floats(Float32List v) {
    final p = alloc(4 * v.length);
    _heap(ce).asFloat32List(p, v.length).setAll(0, v);
    return p;
  }

  int doubles(Float64List v) {
    final p = alloc(8 * v.length);
    _heap(ce).asFloat64List(p, v.length).setAll(0, v);
    return p;
  }

  int ints(List<int> v) {
    final p = alloc(4 * v.length);
    _heap(ce).asInt32List(p, v.length).setAll(0, v);
    return p;
  }

  int bytes(Uint8List v) {
    final p = alloc(v.length);
    _heap(ce).asUint8List(p, v.length).setAll(0, v);
    return p;
  }

  void free() {
    for (final p in _ptrs) {
      ce.free(p);
    }
    _ptrs.clear();
  }
}

/// The detector graph on the WebAssembly engine: built op by op, then run.
class NativeEngine implements EngineGraph {
  NativeEngine._(this._ce, this._h);

  final _Ce _ce;
  final int _h;

  /// Null until [loadNativeEngine] has completed.
  static NativeEngine? open() {
    final ce = _module;
    if (ce == null) return null;
    final h = ce.create(1);
    return h == 0 ? null : NativeEngine._(ce, h);
  }

  T _with<T>(T Function(_Arena a) f) {
    final a = _Arena(_ce);
    try {
      return f(a);
    } finally {
      a.free();
    }
  }

  @override
  bool conv(int input, int output, int cin, int cout, int k, int s, int p, int g, bool act, Float32List w,
          int wStride, Float32List b) =>
      _with((a) => _ce.conv(_h, input, output, cin, cout, k, s, p, g, act ? 1 : 0, a.floats(w), wStride, a.floats(b)) == 0);

  @override
  bool add(int a, int b, int output) => _ce.add(_h, a, b, output) == 0;

  @override
  bool concat(List<int> inputs, int output) =>
      _with((a) => _ce.concat(_h, a.ints(inputs), inputs.length, output) == 0);

  @override
  bool split(int input, List<int> outputs, List<int> sizes) =>
      _with((a) => _ce.split(_h, input, a.ints(outputs), a.ints(sizes), outputs.length) == 0);

  @override
  bool maxpool(int input, int output, int k, int p) => _ce.maxpool(_h, input, output, k, p) == 0;

  @override
  bool upsample(int input, int output, int scale) => _ce.upsample(_h, input, output, scale) == 0;

  @override
  bool attn(int input, int outX, int outV, int heads, int keyDim, int headDim, double scale) =>
      _ce.attn(_h, input, outX, outV, heads, keyDim, headDim, scale) == 0;

  /// The tensors [want] after running [gray] (h x w), back to back, or null.
  Float32List? run(Float32List gray, int h, int w, List<int> want, int outLen) => _with((a) {
        final gp = a.floats(gray), wp = a.ints(want), op = a.alloc(4 * outLen);
        final n = _ce.run(_h, gp, h, w, wp, want.length, op, outLen);
        return n == outLen ? Float32List.fromList(_heap(_ce).asFloat32List(op, outLen)) : null;
      });

  void dispose() => _ce.destroy(_h);
}

/// The picture tidy-up's pixel passes in WebAssembly, bit for bit the Dart
/// ones in image_ink.dart.
class NativeImage {
  NativeImage._(this._ce);

  final _Ce _ce;

  /// Tests compare both paths in one process.
  static bool forceDart = false;

  static NativeImage? open() {
    final ce = _module;
    return forceDart || ce == null ? null : NativeImage._(ce);
  }

  T _with<T>(T Function(_Arena a) f) {
    final a = _Arena(_ce);
    try {
      return f(a);
    } finally {
      a.free();
    }
  }

  ({List<(Float64List, double, int)> strokes, Uint8List ink}) trace(
          Uint8List rgba, int w, int h, int cw, int ch, double s) =>
      _with((a) {
        final src = a.bytes(rgba), pts = a.alloc(4), width = a.alloc(8), color = a.alloc(4);
        final r = _ce.trace(src, w, h, cw, ch, s);
        try {
          final out = <(Float64List, double, int)>[];
          for (var i = 0, n = _ce.traceCount(r); i < n; i++) {
            final len = _ce.traceStroke(r, i, pts, width, color);
            final heap = _heap(_ce);
            final at = heap.asUint32List(pts, 1)[0];
            out.add((
              Float64List.fromList(heap.asFloat64List(at, len)),
              heap.asFloat64List(width, 1)[0],
              heap.asUint32List(color, 1)[0],
            ));
          }
          return (strokes: out, ink: Uint8List.fromList(_heap(_ce).asUint8List(_ce.traceInk(r), cw * ch)));
        } finally {
          _ce.traceFree(r);
        }
      });

  /// rasterizeInk's plane for a raster of rw x rh at the given geometry.
  Float32List rasterizeInk(Uint8List ink, int w, int h, double inkScale, double originX, double originY, double scale,
          int rw, int rh) =>
      _with((a) {
        final src = a.bytes(ink), out = a.alloc(4 * rw * rh);
        _ce.rasterizeInk(src, w, h, inkScale, originX, originY, scale, rw, rh, out);
        return Float32List.fromList(_heap(_ce).asFloat32List(out, rw * rh));
      });

  ({Uint8List rgb, Uint8List gray, Uint8List ink, Uint8List skel, Int32List dist, bool tinted}) tracePrep(
          Uint8List rgba, int w, int h, int cw, int ch) =>
      _with((a) {
        final n = cw * ch;
        final src = a.bytes(rgba), rgb = a.alloc(3 * n), gray = a.alloc(n), ink = a.alloc(n), skel = a.alloc(n);
        final dist = a.alloc(4 * n), tinted = a.alloc(4);
        _ce.tracePrep(src, w, h, cw, ch, rgb, gray, ink, skel, dist, tinted);
        final heap = _heap(_ce);
        return (
          rgb: Uint8List.fromList(heap.asUint8List(rgb, 3 * n)),
          gray: Uint8List.fromList(heap.asUint8List(gray, n)),
          ink: Uint8List.fromList(heap.asUint8List(ink, n)),
          skel: Uint8List.fromList(heap.asUint8List(skel, n)),
          dist: Int32List.fromList(heap.asInt32List(dist, n)),
          tinted: heap.asInt32List(tinted, 1)[0] != 0,
        );
      });

  ({Uint8List alpha, int x0, int y0, int x1, int y1, int kept}) leftover(
          Uint8List rgba, int w, int h, List<(Float64List, double)> cut) =>
      _with((a) {
        final flat = Float64List(math.max(1, cut.fold<int>(0, (s, c) => s + c.$1.length)));
        var off = 0;
        for (final c in cut) {
          flat.setAll(off, c.$1);
          off += c.$1.length;
        }
        final src = a.bytes(rgba), pts = a.doubles(flat);
        final lens = a.ints([for (final c in cut) c.$1.length, if (cut.isEmpty) 0]);
        final widths = a.doubles(Float64List.fromList([for (final c in cut) c.$2, if (cut.isEmpty) 0]));
        final alpha = a.alloc(w * h), box = a.alloc(20);
        _ce.leftover(src, w, h, pts, lens, widths, cut.length, alpha, box);
        final heap = _heap(_ce), b = heap.asInt32List(box, 5);
        return (
          alpha: Uint8List.fromList(heap.asUint8List(alpha, w * h)),
          x0: b[0],
          y0: b[1],
          x1: b[2],
          y1: b[3],
          kept: b[4],
        );
      });
}

/// The ink-to-LaTeX dense layers stay in Dart on the web: adopted weights
/// would be views on memory that moves when the module grows it.
class NativeMath {
  NativeMath._();

  static bool forceDart = false;
  static NativeMath? get instance => null;

  Float32List adopt(Float32List v) => v;

  bool linear(Float32List x, Float32List w, Float32List? bias, Float32List out,
          {required int m, required int k, required int n}) =>
      false;
}

/// The engine in a Web Worker (web/circuit_engine_worker.js), so a tidy-up
/// never holds the UI thread: the detector's forward pass and the picture
/// passes, each request answered by its id.
class CircuitWorker {
  CircuitWorker._(this._w);

  final EngineWorker _w;

  /// A worker with the graph [build] makes; null where it can't start.
  static Future<CircuitWorker?> start(bool Function(EngineGraph g) build) async {
    final w = await EngineWorker.start();
    if (w == null) return null;
    try {
      final rec = _Recorder();
      if (!build(rec)) throw StateError('graph refused');
      final ok = await w.ask('graph', {'ops': rec.ops.toJS});
      if ((ok as JSBoolean?)?.toDart != true) throw StateError('graph refused');
      return CircuitWorker._(w);
    } catch (_) {
      w.dispose();
      return null;
    }
  }

  Future<JSAny?> _ask(String type, Map<String, JSAny?> args) => _w.ask(type, args);

  /// As [NativeEngine.run], off the UI thread.
  Future<Float32List?> run(Float32List gray, int h, int w, List<int> want, int outLen) async {
    final r = await _ask('run', {
      'gray': gray.toJS,
      'h': h.toJS,
      'w': w.toJS,
      'want': [for (final i in want) i.toJS].toJS,
      'outLen': outLen.toJS,
    });
    return r == null ? null : (r as JSFloat32Array).toDart;
  }

  /// As [NativeImage.trace], off the UI thread.
  Future<({List<(Float64List, double, int)> strokes, Uint8List ink})> trace(
      Uint8List rgba, int w, int h, int cw, int ch, double s) async {
    final r = await _ask('trace', {
      'rgba': rgba.toJS,
      'w': w.toJS,
      'h': h.toJS,
      'cw': cw.toJS,
      'ch': ch.toJS,
      's': s.toJS,
    }) as JSObject;
    final strokes = (r['strokes'] as JSArray<JSObject>).toDart;
    return (
      strokes: [
        for (final t in strokes)
          (
            (t['pts'] as JSFloat64Array).toDart,
            (t['width'] as JSNumber).toDartDouble,
            (t['color'] as JSNumber).toDartInt,
          )
      ],
      ink: (r['ink'] as JSUint8Array).toDart,
    );
  }

  /// As [NativeImage.leftover], off the UI thread.
  Future<({Uint8List alpha, int x0, int y0, int x1, int y1, int kept})> leftover(
      Uint8List rgba, int w, int h, List<(Float64List, double)> cut) async {
    final flat = Float64List(cut.fold<int>(0, (s, c) => s + c.$1.length));
    var off = 0;
    for (final c in cut) {
      flat.setAll(off, c.$1);
      off += c.$1.length;
    }
    final r = await _ask('leftover', {
      'rgba': rgba.toJS,
      'w': w.toJS,
      'h': h.toJS,
      'pts': flat.toJS,
      'lens': Int32List.fromList([for (final c in cut) c.$1.length]).toJS,
      'widths': Float64List.fromList([for (final c in cut) c.$2]).toJS,
    }) as JSObject;
    final b = [for (final v in (r['box'] as JSArray<JSNumber>).toDart) v.toDartInt];
    return (alpha: (r['alpha'] as JSUint8Array).toDart, x0: b[0], y0: b[1], x1: b[2], y1: b[3], kept: b[4]);
  }

  void dispose() => _w.dispose();
}

/// The graph's op calls as messages for the worker.
class _Recorder implements EngineGraph {
  final ops = <JSObject>[];

  bool _op(String op, Map<String, JSAny> f) {
    final o = JSObject()..['op'] = op.toJS;
    f.forEach((k, v) => o[k] = v);
    ops.add(o);
    return true;
  }

  JSArray<JSNumber> _ints(List<int> v) => [for (final i in v) i.toJS].toJS;

  @override
  bool conv(int input, int output, int cin, int cout, int k, int s, int p, int g, bool act, Float32List w,
          int wStride, Float32List b) =>
      _op('conv', {
        'in': input.toJS,
        'out': output.toJS,
        'cin': cin.toJS,
        'cout': cout.toJS,
        'k': k.toJS,
        's': s.toJS,
        'p': p.toJS,
        'g': g.toJS,
        'act': (act ? 1 : 0).toJS,
        'w': w.toJS,
        'wStride': wStride.toJS,
        'b': b.toJS,
      });

  @override
  bool add(int a, int b, int output) => _op('add', {'a': a.toJS, 'b': b.toJS, 'out': output.toJS});

  @override
  bool concat(List<int> inputs, int output) => _op('concat', {'ins': _ints(inputs), 'out': output.toJS});

  @override
  bool split(int input, List<int> outputs, List<int> sizes) =>
      _op('split', {'in': input.toJS, 'outs': _ints(outputs), 'sizes': _ints(sizes)});

  @override
  bool maxpool(int input, int output, int k, int p) =>
      _op('maxpool', {'in': input.toJS, 'out': output.toJS, 'k': k.toJS, 'p': p.toJS});

  @override
  bool upsample(int input, int output, int scale) =>
      _op('upsample', {'in': input.toJS, 'out': output.toJS, 'scale': scale.toJS});

  @override
  bool attn(int input, int outX, int outV, int heads, int keyDim, int headDim, double scale) => _op('attn', {
        'in': input.toJS,
        'outX': outX.toJS,
        'outV': outV.toJS,
        'heads': heads.toJS,
        'kd': keyDim.toJS,
        'hd': headDim.toJS,
        'scale': scale.toJS,
      });
}
