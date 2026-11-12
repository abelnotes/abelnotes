// Runtime for the circuit symbol detector (a fused YOLO11).
//
// The model file carries a flat op list written by ml/circuits/export_detector.py;
// this file executes it. Convolutions run as im2col + the SIMD matmul in ops.dart,
// depthwise convolutions as a direct loop. Where packages/circuit_engine is built
// the same op list runs there instead.

import 'dart:math' as math;
import 'dart:typed_data';

import '../ink_recognizer/model_file.dart';
import '../ink_recognizer/ops.dart';
import 'native_engine.dart';

/// One detected symbol, in input-image pixels.
class Detection {
  Detection(this.cls, this.score, this.x0, this.y0, this.x1, this.y1);
  final String cls;
  final double score;
  final double x0, y0, x1, y1;

  double get width => x1 - x0;
  double get height => y1 - y0;

  @override
  String toString() =>
      '$cls ${score.toStringAsFixed(2)} [${x0.round()},${y0.round()},${x1.round()},${y1.round()}]';
}

class _T {
  _T(this.c, this.h, this.w, this.d);
  final int c, h, w;
  final Float32List d;
}

class _Conv {
  _Conv(this.w, this.b, this.cin, this.cout, this.k, this.s, this.p, this.g, this.act, this.kPad);
  final Float32List w; // [cout, kPad] for dense, [cout, k*k] for depthwise
  final Float32List b;
  final int cin, cout, k, s, p, g, kPad;
  final bool act;
}

class CircuitDetector {
  CircuitDetector._(this.names, this._ops, this._convs, this._heads, this._strides, this._regMax);

  factory CircuitDetector.fromModelFile(ModelFile f) {
    if (f.kind != 'circuit-detector') {
      throw ModelFileException('not a circuit detector: ${f.kind}');
    }
    final h = f.header;
    final ops = (h['ops'] as List).cast<Map<String, dynamic>>();
    final convs = <int, _Conv>{};
    for (var i = 0; i < ops.length; i++) {
      final o = ops[i];
      if (o['op'] != 'conv') continue;
      final cin = o['cin'] as int, cout = o['cout'] as int, k = o['k'] as int, g = o['g'] as int;
      final raw = f[o['w'] as String].floats;
      final bias = f[o['b'] as String].floats;
      if (g == 1) {
        final kk = cin * k * k;
        final kPad = (kk + 3) & ~3;
        final w = Float32List(cout * kPad);
        for (var co = 0; co < cout; co++) {
          w.setRange(co * kPad, co * kPad + kk, raw, co * kk);
        }
        convs[i] = _Conv(w, bias, cin, cout, k, o['s'] as int, o['p'] as int, g, o['act'] as bool, kPad);
      } else {
        if (g != cin || g != cout) throw ModelFileException('only depthwise grouped convs are supported');
        convs[i] = _Conv(raw, bias, cin, cout, k, o['s'] as int, o['p'] as int, g, o['act'] as bool, k * k);
      }
    }
    return CircuitDetector._(
      (h['names'] as List).cast<String>(),
      ops,
      convs,
      (h['heads'] as List).map((e) => [(e as Map)['box'] as int, e['cls'] as int]).toList(),
      (h['strides'] as List).cast<int>(),
      h['reg_max'] as int,
    );
  }

  final List<String> names;
  final List<Map<String, dynamic>> _ops;
  final Map<int, _Conv> _convs;
  final List<List<int>> _heads;
  final List<int> _strides;
  final int _regMax;

  /// Largest stride: input sides must be a multiple of it.
  int get stride => _strides.reduce(math.max);

  /// Raw decoded output, [4 + nc, anchors]: cx, cy, w, h, then class scores.
  /// [image] is one grayscale plane, 0 = ink, 1 = paper, [h] x [w].
  /// Milliseconds per op kind, accumulated when non-null (benchmarks only).
  Map<String, int>? profile;

  NativeEngine? _native;
  var _nativeTried = false;

  /// The graph built on the native engine, once; null where there is none
  /// or it refused an op (the Dart forward pass then runs).
  NativeEngine? _engine() {
    if (_nativeTried) return _native;
    _nativeTried = true;
    final e = NativeEngine.open();
    if (e == null) return null;
    var ok = true;
    for (var i = 0; i < _ops.length && ok; i++) {
      final o = _ops[i];
      List<int> ints(Object? v) => (v as List).cast<int>();
      switch (o['op'] as String) {
        case 'conv':
          final c = _convs[i]!;
          ok = e.conv(o['in'] as int, o['out'] as int, c.cin, c.cout, c.k, c.s, c.p, c.g, c.act, c.w, c.kPad, c.b);
        case 'add':
          ok = e.add(ints(o['in'])[0], ints(o['in'])[1], o['out'] as int);
        case 'concat':
          ok = e.concat(ints(o['in']), o['out'] as int);
        case 'split':
          ok = e.split(o['in'] as int, ints(o['outs']), ints(o['sizes']));
        case 'maxpool':
          ok = e.maxpool(ints(o['in'])[0], o['out'] as int, o['k'] as int, o['p'] as int);
        case 'upsample':
          ok = e.upsample(ints(o['in'])[0], o['out'] as int, o['scale'] as int);
        case 'attn':
          final outs = ints(o['outs']);
          ok = e.attn(o['in'] as int, outs[0], outs[1], o['heads'] as int, o['key_dim'] as int, o['head_dim'] as int,
              (o['scale'] as num).toDouble());
        default:
          ok = false;
      }
    }
    if (!ok) {
      e.dispose();
      return null;
    }
    return _native = e;
  }

  /// (channels, height, width) of every tensor for an h x w input.
  Map<int, (int, int, int)> _shapes(int h, int w) {
    final sh = <int, (int, int, int)>{0: (3, h, w)};
    List<int> ints(Object? v) => (v as List).cast<int>();
    for (var i = 0; i < _ops.length; i++) {
      final o = _ops[i];
      switch (o['op'] as String) {
        case 'conv':
          final c = _convs[i]!;
          final (_, ih, iw) = sh[o['in'] as int]!;
          sh[o['out'] as int] = (c.cout, (ih + 2 * c.p - c.k) ~/ c.s + 1, (iw + 2 * c.p - c.k) ~/ c.s + 1);
        case 'add':
          sh[o['out'] as int] = sh[ints(o['in'])[0]]!;
        case 'concat':
          final ins = ints(o['in']).map((e) => sh[e]!).toList();
          sh[o['out'] as int] = (ins.fold<int>(0, (a, e) => a + e.$1), ins[0].$2, ins[0].$3);
        case 'split':
          final (_, ih, iw) = sh[o['in'] as int]!;
          final outs = ints(o['outs']), sizes = ints(o['sizes']);
          for (var j = 0; j < outs.length; j++) {
            sh[outs[j]] = (sizes[j], ih, iw);
          }
        case 'maxpool':
          sh[o['out'] as int] = sh[ints(o['in'])[0]]!;
        case 'upsample':
          final (c, ih, iw) = sh[ints(o['in'])[0]]!;
          final f = o['scale'] as int;
          sh[o['out'] as int] = (c, ih * f, iw * f);
        case 'attn':
          final (_, ih, iw) = sh[o['in'] as int]!;
          final c = (o['heads'] as int) * (o['head_dim'] as int);
          for (final out in ints(o['outs'])) {
            sh[out] = (c, ih, iw);
          }
      }
    }
    return sh;
  }

  Float32List forward(Float32List image, int h, int w) {
    final engine = profile == null ? _engine() : null;
    if (engine != null) {
      final sh = _shapes(h, w);
      final want = [for (final hd in _heads) ...hd];
      final out = engine.run(image, h, w, want, want.fold<int>(0, (a, id) => a + sh[id]!.$1 * sh[id]!.$2 * sh[id]!.$3));
      if (out != null) {
        final t = <int, _T>{};
        var off = 0;
        for (final id in want) {
          final (c, th, tw) = sh[id]!;
          t[id] = _T(c, th, tw, Float32List.sublistView(out, off, off + c * th * tw));
          off += c * th * tw;
        }
        return _decode(t);
      }
    }
    final plane = h * w;
    final x = Float32List(3 * plane);
    for (var c = 0; c < 3; c++) {
      x.setRange(c * plane, (c + 1) * plane, image);
    }
    final t = <int, _T>{0: _T(3, h, w, x)};
    final sw = Stopwatch();
    for (var i = 0; i < _ops.length; i++) {
      final o = _ops[i];
      sw
        ..reset()
        ..start();
      final kind = o['op'] as String;
      final conv = _convs[i];
      switch (kind) {
        case 'conv':
          t[o['out'] as int] = _conv(t[o['in'] as int]!, _convs[i]!);
        case 'add':
          final ins = o['in'] as List;
          final a = t[ins[0] as int]!, b = t[ins[1] as int]!;
          final d = Float32List(a.d.length);
          for (var j = 0; j < d.length; j++) {
            d[j] = a.d[j] + b.d[j];
          }
          t[o['out'] as int] = _T(a.c, a.h, a.w, d);
        case 'concat':
          final ins = (o['in'] as List).map((e) => t[e as int]!).toList();
          final c = ins.fold<int>(0, (s, e) => s + e.c);
          final d = Float32List(c * ins[0].h * ins[0].w);
          var off = 0;
          for (final e in ins) {
            d.setRange(off, off + e.d.length, e.d);
            off += e.d.length;
          }
          t[o['out'] as int] = _T(c, ins[0].h, ins[0].w, d);
        case 'split':
          final a = t[o['in'] as int]!;
          final outs = (o['outs'] as List).cast<int>();
          final sizes = (o['sizes'] as List).cast<int>();
          var c0 = 0;
          for (var j = 0; j < outs.length; j++) {
            final p = a.h * a.w;
            t[outs[j]] = _T(sizes[j], a.h, a.w,
                Float32List.fromList(Float32List.sublistView(a.d, c0 * p, (c0 + sizes[j]) * p)));
            c0 += sizes[j];
          }
        case 'maxpool':
          t[o['out'] as int] = _maxPool(t[(o['in'] as List)[0] as int]!, o['k'] as int, o['p'] as int);
        case 'upsample':
          t[o['out'] as int] = _upsample(t[(o['in'] as List)[0] as int]!, o['scale'] as int);
        case 'attn':
          final outs = (o['outs'] as List).cast<int>();
          final r = _attention(t[o['in'] as int]!, o['heads'] as int, o['key_dim'] as int,
              o['head_dim'] as int, (o['scale'] as num).toDouble());
          t[outs[0]] = r[0];
          t[outs[1]] = r[1];
        default:
          throw ModelFileException('unknown op ${o['op']}');
      }
      final p = profile;
      if (p != null) {
        final key = conv == null ? kind : (conv.g == 1 ? 'conv${conv.k}x${conv.k}' : 'dwconv');
        p[key] = (p[key] ?? 0) + sw.elapsedMicroseconds;
      }
    }
    return _decode(t);
  }

  /// Per-class score floors, tuned on held-out handwritten circuits: current
  /// sources score low but matter most; switches are the usual false alarm.
  static const Map<String, double> classMinScore = {'current_source': 0.2, 'switch': 0.4};

  /// Thresholded, class-wise NMS'd detections.
  List<Detection> detect(Float32List image, int h, int w,
      {double minScore = 0.3, double iou = 0.5}) {
    final out = forward(image, h, w);
    final n = out.length ~/ (4 + names.length);
    final cands = <Detection>[];
    for (var a = 0; a < n; a++) {
      var best = -1, bestS = 0.0;
      for (var c = 0; c < names.length; c++) {
        final s = out[(4 + c) * n + a];
        if (s > bestS) {
          bestS = s;
          best = c;
        }
      }
      if (best < 0 || bestS < (classMinScore[names[best]] ?? minScore)) continue;
      final cx = out[a], cy = out[n + a], bw = out[2 * n + a], bh = out[3 * n + a];
      cands.add(Detection(names[best], bestS, cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2));
    }
    cands.sort((a, b) => b.score.compareTo(a.score));
    final keep = <Detection>[];
    for (final d in cands) {
      if (keep.every((k) => k.cls != d.cls || boxIou(k, d) < iou)) keep.add(d);
    }
    return keep;
  }

  _T _conv(_T x, _Conv c) {
    final ho = (x.h + 2 * c.p - c.k) ~/ c.s + 1;
    final wo = (x.w + 2 * c.p - c.k) ~/ c.s + 1;
    final m = ho * wo;
    final out = Float32List(c.cout * m);
    if (c.g == 1) {
      final cols = Float32List(m * c.kPad);
      final k = c.k;
      for (var oy = 0; oy < ho; oy++) {
        for (var ox = 0; ox < wo; ox++) {
          var r = (oy * wo + ox) * c.kPad;
          for (var ci = 0; ci < c.cin; ci++) {
            final base = ci * x.h * x.w;
            for (var dy = 0; dy < k; dy++) {
              final iy = oy * c.s + dy - c.p;
              for (var dx = 0; dx < k; dx++) {
                final ix = ox * c.s + dx - c.p;
                cols[r++] = (iy < 0 || iy >= x.h || ix < 0 || ix >= x.w) ? 0 : x.d[base + iy * x.w + ix];
              }
            }
          }
        }
      }
      // out[cout, m] = W[cout, kPad] · colsᵀ, already channel-major.
      linear(c.w, cols, null, out, m: c.cout, k: c.kPad, n: m);
    } else {
      final k = c.k;
      for (var ch = 0; ch < c.cout; ch++) {
        final base = ch * x.h * x.w;
        final wb = ch * k * k;
        for (var oy = 0; oy < ho; oy++) {
          for (var ox = 0; ox < wo; ox++) {
            var acc = 0.0;
            for (var dy = 0; dy < k; dy++) {
              final iy = oy * c.s + dy - c.p;
              if (iy < 0 || iy >= x.h) continue;
              for (var dx = 0; dx < k; dx++) {
                final ix = ox * c.s + dx - c.p;
                if (ix < 0 || ix >= x.w) continue;
                acc += c.w[wb + dy * k + dx] * x.d[base + iy * x.w + ix];
              }
            }
            out[ch * m + oy * wo + ox] = acc;
          }
        }
      }
    }
    for (var ch = 0; ch < c.cout; ch++) {
      final b = c.b[ch];
      final o = ch * m;
      if (c.act) {
        for (var j = o; j < o + m; j++) {
          final v = out[j] + b;
          out[j] = v / (1 + math.exp(-v));
        }
      } else {
        for (var j = o; j < o + m; j++) {
          out[j] += b;
        }
      }
    }
    return _T(c.cout, ho, wo, out);
  }

  static _T _maxPool(_T x, int k, int p) {
    final d = Float32List(x.d.length);
    for (var c = 0; c < x.c; c++) {
      final base = c * x.h * x.w;
      for (var y = 0; y < x.h; y++) {
        for (var xx = 0; xx < x.w; xx++) {
          var m = double.negativeInfinity;
          for (var dy = -p; dy <= k - 1 - p; dy++) {
            final iy = y + dy;
            if (iy < 0 || iy >= x.h) continue;
            for (var dx = -p; dx <= k - 1 - p; dx++) {
              final ix = xx + dx;
              if (ix < 0 || ix >= x.w) continue;
              final v = x.d[base + iy * x.w + ix];
              if (v > m) m = v;
            }
          }
          d[base + y * x.w + xx] = m;
        }
      }
    }
    return _T(x.c, x.h, x.w, d);
  }

  static _T _upsample(_T x, int s) {
    final h = x.h * s, w = x.w * s;
    final d = Float32List(x.c * h * w);
    for (var c = 0; c < x.c; c++) {
      for (var y = 0; y < h; y++) {
        final src = c * x.h * x.w + (y ~/ s) * x.w;
        final dst = c * h * w + y * w;
        for (var xx = 0; xx < w; xx++) {
          d[dst + xx] = x.d[src + xx ~/ s];
        }
      }
    }
    return _T(x.c, h, w, d);
  }

  /// Multi-head self-attention over spatial positions; returns the attended
  /// values and v itself (the caller adds a depthwise conv of v).
  static List<_T> _attention(_T qkv, int heads, int kd, int hd, double scale) {
    final n = qkv.h * qkv.w;
    final per = 2 * kd + hd;
    final xa = Float32List(heads * hd * n);
    final v = Float32List(heads * hd * n);
    final row = Float32List(n);
    for (var hh = 0; hh < heads; hh++) {
      final base = hh * per * n;
      for (var dd = 0; dd < hd; dd++) {
        v.setRange((hh * hd + dd) * n, (hh * hd + dd + 1) * n, qkv.d, base + (2 * kd + dd) * n);
      }
      for (var i = 0; i < n; i++) {
        var mx = double.negativeInfinity;
        for (var j = 0; j < n; j++) {
          var s = 0.0;
          for (var dd = 0; dd < kd; dd++) {
            s += qkv.d[base + dd * n + i] * qkv.d[base + (kd + dd) * n + j];
          }
          s *= scale;
          row[j] = s;
          if (s > mx) mx = s;
        }
        var sum = 0.0;
        for (var j = 0; j < n; j++) {
          row[j] = math.exp(row[j] - mx);
          sum += row[j];
        }
        for (var dd = 0; dd < hd; dd++) {
          final vb = base + (2 * kd + dd) * n;
          var acc = 0.0;
          for (var j = 0; j < n; j++) {
            acc += qkv.d[vb + j] * row[j];
          }
          xa[(hh * hd + dd) * n + i] = acc / sum;
        }
      }
    }
    return [_T(heads * hd, qkv.h, qkv.w, xa), _T(heads * hd, qkv.h, qkv.w, v)];
  }

  Float32List _decode(Map<int, _T> t) {
    final nc = names.length;
    var total = 0;
    for (final hd in _heads) {
      total += t[hd[0]]!.h * t[hd[0]]!.w;
    }
    final out = Float32List((4 + nc) * total);
    var a0 = 0;
    final probs = Float32List(_regMax);
    for (var l = 0; l < _heads.length; l++) {
      final box = t[_heads[l][0]]!, cls = t[_heads[l][1]]!;
      final s = _strides[l].toDouble();
      final p = box.h * box.w;
      for (var y = 0; y < box.h; y++) {
        for (var x = 0; x < box.w; x++) {
          final a = y * box.w + x;
          final dist = List<double>.filled(4, 0);
          for (var side = 0; side < 4; side++) {
            var mx = double.negativeInfinity;
            for (var r = 0; r < _regMax; r++) {
              final v = box.d[(side * _regMax + r) * p + a];
              probs[r] = v;
              if (v > mx) mx = v;
            }
            var sum = 0.0, e = 0.0;
            for (var r = 0; r < _regMax; r++) {
              final q = math.exp(probs[r] - mx);
              sum += q;
              e += q * r;
            }
            dist[side] = e / sum;
          }
          final ax = x + 0.5, ay = y + 0.5;
          final x0 = ax - dist[0], y0 = ay - dist[1], x1 = ax + dist[2], y1 = ay + dist[3];
          final idx = a0 + a;
          out[idx] = (x0 + x1) / 2 * s;
          out[total + idx] = (y0 + y1) / 2 * s;
          out[2 * total + idx] = (x1 - x0) * s;
          out[3 * total + idx] = (y1 - y0) * s;
          for (var c = 0; c < nc; c++) {
            out[(4 + c) * total + idx] = 1 / (1 + math.exp(-cls.d[c * p + a]));
          }
        }
      }
      a0 += p;
    }
    return out;
  }
}

double boxIou(Detection a, Detection b) {
  final ix = math.max(0.0, math.min(a.x1, b.x1) - math.max(a.x0, b.x0));
  final iy = math.max(0.0, math.min(a.y1, b.y1) - math.max(a.y0, b.y0));
  final i = ix * iy;
  final u = a.width * a.height + b.width * b.height - i;
  return u <= 0 ? 0 : i / u;
}
