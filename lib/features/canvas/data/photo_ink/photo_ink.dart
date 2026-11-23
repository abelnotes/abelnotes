// Photo of handwritten notes -> centre-line strokes. Steps, choices and
// bench numbers: README.md in this folder.

import 'dart:math' as math;
import 'dart:typed_data';

/// One traced line: flat [x0, y0, x1, y1, ...] in output pixels, the ink's
/// width there, its colour against the paper (ARGB) and whether it is
/// highlighter rather than pen.
class PhotoStroke {
  PhotoStroke(this.points, this.width, this.color, {this.highlighter = false});
  final Float64List points;
  final double width;
  final int color;
  final bool highlighter;
}

/// The strokes of a photo in an output space of [width] x [height] pixels:
/// the straightened sheet when one was found ([rectified]), else the photo.
/// [toSource] (3x3, row-major) maps output pixels back to photo pixels.
class PhotoInk {
  PhotoInk(this.strokes, this.width, this.height, this.toSource, {required this.rectified});
  final List<PhotoStroke> strokes;
  final double width, height;
  final Float64List toSource;
  final bool rectified;
}

/// Tunables, defaults from the bench (README.md).
class PhotoInkOptions {
  const PhotoInkOptions({
    this.penPx = 6,
    this.lo = 0.30,
    this.hi = 0.55,
    this.core = 0.55,
    this.sigma = 1.5,
    this.maxSide = 3600,
    this.page = true,
    this.rule = true,
    this.carve = 1.5,
    this.splice = 6,
  });

  /// Working scale: the pen comes out about this many pixels wide.
  final double penPx;

  /// Hysteresis thresholds, as fractions of the page's ink darkness.
  final double lo, hi;

  /// A pixel is ink only within this fraction of the darkest ink near it.
  final double core;

  /// Centre-line smoothing (working pixels).
  final double sigma;
  final int maxSide;
  final bool page, rule;

  /// Loops the photo filled are reopened where the ink is deeper than this
  /// many half pen widths.
  final double carve;

  /// Paths up to this many pen widths long join a longer one they touch.
  final double splice;
}

/// Longest side the photo is read at; bigger ones are averaged down first.
const int _kSourceSide = 3200;

/// Milliseconds since start at the end of each step, when set (benches).
Map<String, int>? photoInkLaps;

/// Traces the handwriting in an RGBA photo ([w] x [h], row-major).
PhotoInk photoToInk(Uint8List rgba, int w, int h, [PhotoInkOptions o = const PhotoInkOptions()]) {
  final watch = Stopwatch()..start();
  void lap(String s) => photoInkLaps?[s] = watch.elapsedMilliseconds;
  var src = _Rgb.fromRgba(rgba, w, h);
  var toSrc = _identity();
  if (math.max(w, h) > _kSourceSide) {
    final f = _kSourceSide / math.max(w, h);
    src = src.resize((w * f).round(), (h * f).round());
    toSrc = _scale(w / src.w, h / src.h);
  }
  var work = src;
  var rectified = false;
  if (o.page) {
    final quad = _findPage(src);
    if (quad != null) {
      final (img, m) = _rectify(src, quad);
      work = img;
      toSrc = _mul(toSrc, _invert(m));
      rectified = true;
    }
  }

  lap('page');
  // Pen width at a reference scale, then the working scale from it.
  final yw = work.luma();
  final s0 = 1600 / math.max(work.w, work.h);
  final bw = math.max(1, (work.w * s0).round()), bh = math.max(1, (work.h * s0).round());
  final yb = _resizePlane(yw, work.w, work.h, bw, bh);
  final k0 = math.max(15, math.max(bw, bh) ~/ 60) | 1;
  final d0 = _lumaDarkness(yb, _paperLevel(yb, bw, bh, k0), bw, bh);
  final lvl0 = _inkLevel(d0);
  final m0 = Uint8List(d0.length);
  for (var i = 0; i < d0.length; i++) {
    if (d0[i] >= 0.55 * lvl0) m0[i] = 1;
  }
  // Twice the distance to paper along the ink's ridge, less the centre pixel.
  final dt0 = _chamfer(m0, bw, bh);
  final wv = <double>[];
  for (var y = 1; y < bh - 1; y++) {
    for (var x = 1; x < bw - 1; x++) {
      final i = y * bw + x, v = dt0[i];
      if (v == 0) continue;
      if (v >= dt0[i - 1] && v >= dt0[i + 1] && v >= dt0[i - bw] && v >= dt0[i + bw]) wv.add(v);
    }
  }
  wv.sort();
  final width0 = wv.length > 50 ? 2 * wv[wv.length ~/ 2] - 1 : 3.0;
  var s = s0 * math.max(0.5, o.penPx / math.max(width0, 1.0));
  s = math.min(s, o.maxSide / math.max(work.w, work.h));
  final int W = math.max(1, (work.w * s).round()), H = math.max(1, (work.h * s).round());
  final n = W * H;
  final k = math.max(15, (6 * o.penPx).toInt()) | 1;
  lap('scale');

  // Paper colour on a copy f times smaller (it is smooth); darkness of the
  // grey at full working size against it.
  final int f = math.max(1, k ~/ 8);
  final int sw = math.max(1, (W / f).round()), sh = math.max(1, (H / f).round());
  final ks = math.max(3, (k / f).round() | 1);
  final small = work.resize(sw, sh);
  final pr = _paperLevel(small.r, sw, sh, ks), pg = _paperLevel(small.g, sw, sh, ks);
  final pb = _paperLevel(small.b, sw, sh, ks);
  final py = Float32List(sw * sh);
  for (var i = 0; i < py.length; i++) {
    py[i] = 0.299 * pr[i] + 0.587 * pg[i] + 0.114 * pb[i];
  }
  final yi = _resizePlane(yw, work.w, work.h, W, H, cubic: true);
  final d = _lumaDarkness(yi, _resizePlane(py, sw, sh, W, H), W, H);
  lap('flatten');

  // Highlighter: light and strongly coloured. Out of the ink, traced apart.
  // Its bands are wider than the pen: paper measured over a wider window.
  final kw = 3 * ks;
  final qr = _paperLevel(small.r, sw, sh, kw), qg = _paperLevel(small.g, sw, sh, kw);
  final qb = _paperLevel(small.b, sw, sh, kw);
  final ref = _percentile(Float32List.fromList([for (final v in py) v / 255]), 0.9);
  final hlSmall = Uint8List(sw * sh);
  for (var i = 0; i < hlSmall.length; i++) {
    // Only on the sheet: warm wood and dark cloth look tinted against themselves.
    if (py[i] / 255 < 0.7 * ref) continue;
    final r = math.min(1.0, small.r[i] / math.max(qr[i], 1)), g = math.min(1.0, small.g[i] / math.max(qg[i], 1));
    final b = math.min(1.0, small.b[i] / math.max(qb[i], 1));
    final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
    if (mx - mn > 0.2 && 1 - (0.299 * r + 0.587 * g + 0.114 * b) < 0.45 && mx > 0.7) hlSmall[i] = 1;
  }
  // Not paper: the background far darker than the sheet (desk, clothes).
  var notPaper = Uint8List(sw * sh);
  for (var i = 0; i < py.length; i++) {
    if (py[i] / 255 < 0.45 * ref) notPaper[i] = 1;
  }
  notPaper = _open(notPaper, sw, sh, ks, ks);
  final hlGrown = _dilate(hlSmall, sw, sh, 3, 3);
  for (var y = 0; y < H; y++) {
    final int ys = math.min(sh - 1, y * sh ~/ H) * sw;
    for (var x = 0; x < W; x++) {
      final int j = ys + math.min(sw - 1, x * sw ~/ W);
      if (notPaper[j] == 1 || hlGrown[j] == 1 && d[y * W + x] < 0.45) d[y * W + x] = 0;
    }
  }
  if (rectified) {
    // The sheet's own edge, a pixel or two off the found corners.
    final m = math.max(3, (0.01 * math.max(W, H)).round());
    for (var y = 0; y < H; y++) {
      for (var x = 0; x < W; x++) {
        if (x < m || y < m || x >= W - m || y >= H - m) d[y * W + x] = 0;
      }
    }
  }
  final lvl = _inkLevel(d);

  var ink = _hysteresis(d, W, H, o.lo * lvl, o.hi * lvl);
  // Gaps between close strokes and small loops are lighter than the ink
  // beside them: they stay open.
  final kk = (2 * o.penPx).toInt() | 1;
  final peak = _maxFilterF(d, W, H, kk, kk);
  for (var i = 0; i < n; i++) {
    if (ink[i] == 1 && d[i] < o.core * peak[i]) ink[i] = 0;
  }

  lap('threshold');
  if (o.rule) {
    final faint = Uint8List(n);
    for (var i = 0; i < n; i++) {
      if (d[i] >= 0.08) faint[i] = 1;
    }
    final lines = _rulingMask(d, W, H, _skew(faint, W, H), math.max(12, (0.015 * math.max(W, H)).toInt()), lvl);
    if (lines.contains(1)) {
      final dd = Float32List(n);
      for (var i = 0; i < n; i++) {
        if (ink[i] == 1 && lines[i] == 0) dd[i] = d[i];
      }
      ink = _hysteresis(dd, W, H, o.lo * lvl, o.hi * lvl);
    }
  }

  lap('ruling');
  ink = _majority(ink, W, H);
  _fillHoles(ink, W, H, math.max(2, (0.6 * o.penPx * o.penPx).toInt()));
  _dropSmall(ink, W, H, math.max(4, (0.5 * o.penPx * o.penPx).toInt()));
  final dist = _chamfer(ink, W, H);
  if (o.carve > 0) _carveLoops(ink, dist, W, H, o.carve);
  final sk = _thin(ink, W, H);
  _unstair(sk, W, H);
  // Also after straightening: a sliver of desk along the sheet's edge.
  _dropTouching(ink, sk, dist, W, H, o.penPx);
  _clearFrame(sk, W, H, math.max(2, (0.5 * o.penPx).round()));
  lap('thin');
  final paths = traceSkeleton(sk, W, H, math.max(2, (0.8 * o.penPx).toInt()));

  lap('trace');
  final out = <PhotoStroke>[];
  // Output: working pixels back to the straightened sheet (or the photo).
  final ox = work.w / W, oy = work.h / H;
  // Ink colour against the paper: the photo's pixel over the paper level.
  (double, double, double) colourAt(int p) {
    final x = p % W, y = p ~/ W;
    final wx = math.min(work.w - 1, (x * ox).floor()), wy = math.min(work.h - 1, (y * oy).floor());
    final int j = math.min(sh - 1, y * sh ~/ H) * sw + math.min(sw - 1, x * sw ~/ W);
    final i = wy * work.w + wx;
    return (
      math.min(1.0, work.r[i] / math.max(pr[j], 1)),
      math.min(1.0, work.g[i] / math.max(pg[j], 1)),
      math.min(1.0, work.b[i] / math.max(pb[j], 1)),
    );
  }

  final kept = [for (final p in paths) if (p.length >= 2) p];
  final smooth = <List<(double, double)>>[];
  final widths = <double>[], argb = <int>[];
  for (final path in kept) {
    final closed = path.length > 8 && path.first == path.last;
    smooth.add(_smooth([for (final p in path) (p % W + 0.5, p ~/ W + 0.5)], o.sigma, closed));
    final ws = [for (final p in path) dist[p]]..sort();
    final dk = [for (final p in path) d[p]]..sort();
    final cut = dk[dk.length ~/ 2];
    final rs = <double>[], gs = <double>[], bs = <double>[];
    for (final p in path) {
      if (d[p] < cut) continue;
      final (r, g, b) = colourAt(p);
      rs.add(r);
      gs.add(g);
      bs.add(b);
    }
    widths.add(2 * ws[ws.length ~/ 2] * ox);
    argb.add(_argb(_median(rs), _median(gs), _median(bs)));
  }
  final half = math.max(1.0, _halfWidth(dist, W, H));
  for (final (i, pts) in _splice(kept, smooth, argb, W, H, o.splice * 2 * half, half + 1.5)) {
    final dp = _douglasPeucker(pts, 0.4);
    out.add(PhotoStroke(Float64List.fromList([for (final (x, y) in dp) ...[x * ox, y * oy]]), widths[i], argb[i]));
  }

  // Highlighter strokes, on the small copy: wide, along each band's middle.
  final hp = math.max(1, (2 * o.penPx / f).round()) | 1;
  final hm = _open(hlSmall, sw, sh, hp, hp);
  _dropSmall(hm, sw, sh, (30 * o.penPx * o.penPx / (f * f)).ceil());
  if (hm.contains(1)) {
    final hd = _chamfer(hm, sw, sh);
    final hs = _thin(hm, sw, sh);
    _unstair(hs, sw, sh);
    _clearFrame(hs, sw, sh, 2);
    final hx = work.w / sw, hy = work.h / sh;
    for (final path in traceSkeleton(hs, sw, sh, math.max(2, (4 * o.penPx / f).round()))) {
      if (path.length < 2) continue;
      var pts = [for (final p in path) (p % sw + 0.5, p ~/ sw + 0.5)];
      pts = _douglasPeucker(_smooth(pts, 3 * o.sigma / f, false), 1.0 / f);
      final ws = [for (final p in path) hd[p]]..sort();
      double ch(Float32List c, Float32List pc) =>
          _median([for (final p in path) math.min(1.0, c[p] / math.max(pc[p], 1))]);
      out.add(PhotoStroke(
        Float64List.fromList([for (final (x, y) in pts) ...[x * hx, y * hy]]),
        2 * ws[ws.length ~/ 2] * hx,
        _argb(ch(small.r, qr), ch(small.g, qg), ch(small.b, qb)),
        highlighter: true,
      ));
    }
  }
  lap('emit');
  return PhotoInk(out, work.w.toDouble(), work.h.toDouble(), toSrc, rectified: rectified);
}

int _argb(double r, double g, double b) {
  int c(double v) => (255 * v).round().clamp(0, 255);
  return 0xFF000000 | (c(r) << 16) | (c(g) << 8) | c(b);
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  v.sort();
  return v[v.length ~/ 2];
}

// ---------------------------------------------------------------- images

/// RGB planes, 0..255.
class _Rgb {
  _Rgb(this.w, this.h, this.r, this.g, this.b);
  final int w, h;
  final Float32List r, g, b;

  factory _Rgb.fromRgba(Uint8List rgba, int w, int h) {
    final n = w * h;
    final r = Float32List(n), g = Float32List(n), b = Float32List(n);
    for (var i = 0; i < n; i++) {
      final a = rgba[4 * i + 3] / 255;
      r[i] = rgba[4 * i] * a + 255 * (1 - a);
      g[i] = rgba[4 * i + 1] * a + 255 * (1 - a);
      b[i] = rgba[4 * i + 2] * a + 255 * (1 - a);
    }
    return _Rgb(w, h, r, g, b);
  }

  Float32List luma() {
    final y = Float32List(w * h);
    for (var i = 0; i < y.length; i++) {
      y[i] = 0.299 * r[i] + 0.587 * g[i] + 0.114 * b[i];
    }
    return y;
  }

  /// Area average when shrinking, bilinear when growing.
  _Rgb resize(int nw, int nh) {
    if (nw == w && nh == h) return this;
    return _Rgb(nw, nh, _resizePlane(r, w, h, nw, nh), _resizePlane(g, w, h, nw, nh), _resizePlane(b, w, h, nw, nh));
  }
}

Float32List _resizePlane(Float32List src, int w, int h, int nw, int nh, {bool cubic = false}) {
  if (nw == w && nh == h) return src;
  final tmp = Float32List(nw * h);
  final cols = _resampleWeights(w, nw, cubic);
  for (var y = 0; y < h; y++) {
    final row = y * w, orow = y * nw;
    for (var x = 0; x < nw; x++) {
      final (idx, wt) = cols[x];
      var sum = 0.0;
      for (var j = 0; j < idx.length; j++) {
        sum += src[row + idx[j]] * wt[j];
      }
      tmp[orow + x] = sum;
    }
  }
  final out = Float32List(nw * nh);
  final rows = _resampleWeights(h, nh, cubic);
  for (var y = 0; y < nh; y++) {
    final (idx, wt) = rows[y];
    final orow = y * nw;
    for (var j = 0; j < idx.length; j++) {
      final srow = idx[j] * nw, f = wt[j];
      for (var x = 0; x < nw; x++) {
        out[orow + x] += tmp[srow + x] * f;
      }
    }
  }
  return out;
}

/// Per output index along one axis: source indices and weights. Area
/// average when shrinking, linear when growing.
List<(Int32List, Float64List)> _resampleWeights(int n, int nn, bool cubic) {
  final s = n / nn;
  final out = <(Int32List, Float64List)>[];
  for (var i = 0; i < nn; i++) {
    if (s > 1) {
      final f0 = i * s, f1 = (i + 1) * s;
      final idx = <int>[], wt = <double>[];
      for (var k = f0.floor(); k < f1.ceil() && k < n; k++) {
        final c = math.min(f1, k + 1.0) - math.max(f0, k.toDouble());
        if (c <= 0) continue;
        idx.add(k);
        wt.add(c / s);
      }
      out.add((Int32List.fromList(idx), Float64List.fromList(wt)));
    } else if (!cubic) {
      final f = ((i + 0.5) * s - 0.5).clamp(0.0, n - 1.0);
      final k0 = f.floor(), k1 = math.min(k0 + 1, n - 1), t = f - k0;
      out.add((Int32List.fromList([k0, k1]), Float64List.fromList([1 - t, t])));
    } else {
      // Catmull-Rom: thin gaps between strokes stay lighter than linear keeps them.
      final f = ((i + 0.5) * s - 0.5).clamp(0.0, n - 1.0);
      final k0 = f.floor(), t = f - k0, t2 = t * t, t3 = t2 * t;
      out.add((
        Int32List.fromList([for (var j = -1; j <= 2; j++) (k0 + j).clamp(0, n - 1)]),
        Float64List.fromList([
          0.5 * (-t3 + 2 * t2 - t),
          0.5 * (3 * t3 - 5 * t2 + 2),
          0.5 * (-3 * t3 + 4 * t2 + t),
          0.5 * (t3 - t2),
        ]),
      ));
    }
  }
  return out;
}

/// Paper level per pixel (grey closing: ink removed, shadow edges kept), and
/// the image divided by it, 0..1.
/// Paper level of a plane: a grey closing (ink removed, shadow edges kept)
/// over a [k] x [k] window, softened, never below the plane itself.
Float32List _paperLevel(Float32List p, int w, int h, int k) {
  var bg = _minFilterF(_maxFilterF(p, w, h, k, k), w, h, k, k);
  bg = _boxBlur(bg, w, h, (k ~/ 2) | 1);
  for (var i = 0; i < bg.length; i++) {
    if (bg[i] < p[i]) bg[i] = p[i];
  }
  return bg;
}

/// 1 - grey / paper level, 0..1.
Float32List _lumaDarkness(Float32List y, Float32List paper, int w, int h) {
  final d = Float32List(w * h);
  for (var i = 0; i < d.length; i++) {
    final v = 1 - y[i] / math.max(math.max(paper[i], y[i]), 1);
    d[i] = v < 0 ? 0 : v;
  }
  return d;
}

/// How dark the page's ink is: a high percentile of what is clearly not paper.
double _inkLevel(Float32List d) {
  final v = [for (final x in d) if (x > 0.12) x];
  if (v.length < 50) return 0.5;
  v.sort();
  return v[(0.9 * (v.length - 1)).round()];
}

double _percentile(Float32List v, double q) {
  final hist = Int32List(1025);
  for (final x in v) {
    hist[(x.clamp(0.0, 1.0) * 1024).toInt()]++;
  }
  final want = q * v.length;
  var acc = 0;
  for (var i = 0; i < hist.length; i++) {
    acc += hist[i];
    if (acc >= want) return i / 1024;
  }
  return 1;
}

/// Running max/min over a [kx] x [ky] window (van Herk / Gil-Werman: two
/// block scans per axis, the window clipped to the image).
Float32List _extremeF(Float32List src, int w, int h, int kx, int ky, bool max) {
  final pad = max ? double.negativeInfinity : double.infinity;
  var cur = src;
  if (kx > 1) {
    final r = kx ~/ 2, k = 2 * r + 1, n = w + 2 * r;
    final a = Float64List(n), g = Float64List(n), hh = Float64List(n);
    final out = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var i = 0; i < n; i++) {
        final x = i - r;
        a[i] = x < 0 || x >= w ? pad : cur[row + x];
      }
      for (var i = 0; i < n; i++) {
        g[i] = i % k == 0 ? a[i] : (max ? math.max(g[i - 1], a[i]) : math.min(g[i - 1], a[i]));
      }
      for (var i = n - 1; i >= 0; i--) {
        hh[i] = (i + 1) % k == 0 || i == n - 1 ? a[i] : (max ? math.max(hh[i + 1], a[i]) : math.min(hh[i + 1], a[i]));
      }
      for (var x = 0; x < w; x++) {
        // Window [x, x + 2r] in padded indices.
        final lo = hh[x], hi = g[x + 2 * r];
        out[row + x] = max ? math.max(lo, hi) : math.min(lo, hi);
      }
    }
    cur = out;
  }
  if (ky > 1) {
    final r = ky ~/ 2, k = 2 * r + 1, n = h + 2 * r;
    final g = Float32List(n * w), hh = Float32List(n * w);
    double at(int i, int x) {
      final y = i - r;
      return y < 0 || y >= h ? pad : cur[y * w + x];
    }

    for (var i = 0; i < n; i++) {
      final o = i * w;
      if (i % k == 0) {
        for (var x = 0; x < w; x++) {
          g[o + x] = at(i, x);
        }
      } else {
        for (var x = 0; x < w; x++) {
          final v = at(i, x), p = g[o - w + x];
          g[o + x] = max ? (v > p ? v : p) : (v < p ? v : p);
        }
      }
    }
    for (var i = n - 1; i >= 0; i--) {
      final o = i * w;
      if ((i + 1) % k == 0 || i == n - 1) {
        for (var x = 0; x < w; x++) {
          hh[o + x] = at(i, x);
        }
      } else {
        for (var x = 0; x < w; x++) {
          final v = at(i, x), p = hh[o + w + x];
          hh[o + x] = max ? (v > p ? v : p) : (v < p ? v : p);
        }
      }
    }
    final out = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      final lo = y * w, hi = (y + 2 * r) * w, o = y * w;
      for (var x = 0; x < w; x++) {
        final p = hh[lo + x], q = g[hi + x];
        out[o + x] = max ? (p > q ? p : q) : (p < q ? p : q);
      }
    }
    cur = out;
  }
  return identical(cur, src) ? Float32List.fromList(src) : cur;
}

Float32List _maxFilterF(Float32List s, int w, int h, int kx, int ky) => _extremeF(s, w, h, kx, ky, true);
Float32List _minFilterF(Float32List s, int w, int h, int kx, int ky) => _extremeF(s, w, h, kx, ky, false);

/// Binary dilation/erosion by a [kx] x [ky] box, via running counts.
Uint8List _morph(Uint8List m, int w, int h, int kx, int ky, bool dilate) {
  // Count of set pixels in the window: dilate = any, erode = all (clipped).
  final rx = kx ~/ 2, ry = ky ~/ 2;
  final rowSum = Int32List(w * h);
  for (var y = 0; y < h; y++) {
    final o = y * w;
    var sum = 0;
    for (var x = 0; x <= math.min(rx, w - 1); x++) {
      sum += m[o + x];
    }
    for (var x = 0; x < w; x++) {
      rowSum[o + x] = sum;
      final add = x + rx + 1, sub = x - rx;
      if (add < w) sum += m[o + add];
      if (sub >= 0) sum -= m[o + sub];
    }
  }
  final out = Uint8List(w * h);
  final col = Int32List(w);
  for (var y = 0; y <= math.min(ry, h - 1); y++) {
    for (var x = 0; x < w; x++) {
      col[x] += rowSum[y * w + x];
    }
  }
  for (var y = 0; y < h; y++) {
    final o = y * w;
    final y0 = math.max(0, y - ry), y1 = math.min(h - 1, y + ry);
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - rx), x1 = math.min(w - 1, x + rx);
      final full = (x1 - x0 + 1) * (y1 - y0 + 1);
      if (dilate ? col[x] > 0 : col[x] == full) out[o + x] = 1;
    }
    final add = y + ry + 1, sub = y - ry;
    if (add < h) {
      for (var x = 0; x < w; x++) {
        col[x] += rowSum[add * w + x];
      }
    }
    if (sub >= 0) {
      for (var x = 0; x < w; x++) {
        col[x] -= rowSum[sub * w + x];
      }
    }
  }
  return out;
}

Uint8List _dilate(Uint8List m, int w, int h, int kx, int ky) => _morph(m, w, h, kx, ky, true);
Uint8List _erode(Uint8List m, int w, int h, int kx, int ky) => _morph(m, w, h, kx, ky, false);
Uint8List _open(Uint8List m, int w, int h, int kx, int ky) => _dilate(_erode(m, w, h, kx, ky), w, h, kx, ky);

/// Box mean over a [k] x [k] window clipped to the image (running sums).
Float32List _boxBlur(Float32List src, int w, int h, int k) {
  final r = k ~/ 2;
  final tmp = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final o = y * w;
    var sum = 0.0;
    var lo = 0, hi = -1;
    for (var x = 0; x < w; x++) {
      final nlo = math.max(0, x - r), nhi = math.min(w - 1, x + r);
      while (hi < nhi) {
        sum += src[o + ++hi];
      }
      while (lo < nlo) {
        sum -= src[o + lo++];
      }
      tmp[o + x] = sum / (hi - lo + 1);
    }
  }
  final out = Float32List(w * h);
  final col = Float64List(w);
  var lo = 0, hi = -1;
  for (var y = 0; y < h; y++) {
    final nlo = math.max(0, y - r), nhi = math.min(h - 1, y + r);
    while (hi < nhi) {
      hi++;
      for (var x = 0; x < w; x++) {
        col[x] += tmp[hi * w + x];
      }
    }
    while (lo < nlo) {
      for (var x = 0; x < w; x++) {
        col[x] -= tmp[lo * w + x];
      }
      lo++;
    }
    final cnt = hi - lo + 1, o = y * w;
    for (var x = 0; x < w; x++) {
      out[o + x] = col[x] / cnt;
    }
  }
  return out;
}

/// Components of [m] (8- or 4-connected): labels (0 = none, 1..n) and per
/// component [area, x0, y0, x1, y1].
(Int32List, List<Int32List>) _label(Uint8List m, int w, int h, {bool eight = true}) {
  final lab = Int32List(m.length);
  final stats = <Int32List>[Int32List(5)];
  final stack = Int32List(m.length);
  for (var s = 0; s < m.length; s++) {
    if (m[s] == 0 || lab[s] != 0) continue;
    final id = stats.length;
    final st = Int32List.fromList([0, w, h, -1, -1]);
    var top = 0;
    stack[top++] = s;
    lab[s] = id;
    while (top > 0) {
      final p = stack[--top];
      final x = p % w, y = p ~/ w;
      st[0]++;
      if (x < st[1]) st[1] = x;
      if (y < st[2]) st[2] = y;
      if (x > st[3]) st[3] = x;
      if (y > st[4]) st[4] = y;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0 || (!eight && dx != 0 && dy != 0)) continue;
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          final q = yy * w + xx;
          if (m[q] == 1 && lab[q] == 0) {
            lab[q] = id;
            stack[top++] = q;
          }
        }
      }
    }
    stats.add(st);
  }
  return (lab, stats);
}

/// Pixels at least [lo], in components holding a pixel at least [hi].
Uint8List _hysteresis(Float32List d, int w, int h, double lo, double hi) {
  final weak = Uint8List(d.length);
  for (var i = 0; i < d.length; i++) {
    if (d[i] >= lo && d[i] > 0) weak[i] = 1;
  }
  final (lab, stats) = _label(weak, w, h);
  final keep = Uint8List(stats.length);
  for (var i = 0; i < d.length; i++) {
    if (lab[i] != 0 && d[i] >= hi) keep[lab[i]] = 1;
  }
  for (var i = 0; i < d.length; i++) {
    weak[i] = lab[i] != 0 && keep[lab[i]] == 1 ? 1 : 0;
  }
  return weak;
}

/// 3x3 majority vote: ragged edges and single-pixel bumps smoothed.
Uint8List _majority(Uint8List m, int w, int h) {
  final out = Uint8List(m.length);
  for (var y = 0; y < h; y++) {
    final ym = y > 0 ? y - 1 : 0, yp = y < h - 1 ? y + 1 : h - 1;
    for (var x = 0; x < w; x++) {
      final xm = x > 0 ? x - 1 : 0, xp = x < w - 1 ? x + 1 : w - 1;
      final c = m[ym * w + xm] + m[ym * w + x] + m[ym * w + xp] + m[y * w + xm] + m[y * w + x] + m[y * w + xp] +
          m[yp * w + xm] + m[yp * w + x] + m[yp * w + xp];
      if (c >= 5) out[y * w + x] = 1;
    }
  }
  return out;
}

/// Pinholes in thick ink (they would thin to small rings).
void _fillHoles(Uint8List m, int w, int h, int maxArea) {
  final inv = Uint8List(m.length);
  for (var i = 0; i < m.length; i++) {
    inv[i] = 1 - m[i];
  }
  final (lab, stats) = _label(inv, w, h, eight: false);
  for (var i = 0; i < m.length; i++) {
    if (lab[i] != 0 && stats[lab[i]][0] <= maxArea) m[i] = 1;
  }
}

void _dropSmall(Uint8List m, int w, int h, int minArea) {
  final (lab, stats) = _label(m, w, h);
  for (var i = 0; i < m.length; i++) {
    if (lab[i] != 0 && stats[lab[i]][0] < minArea) m[i] = 0;
  }
}

/// Ink running off the picture (desk, notebook edge) goes; writing cut by
/// the frame stays when it is as thin as the pen.
void _dropTouching(Uint8List m, Uint8List sk, Float32List dist, int w, int h, double pen) {
  final (lab, stats) = _label(m, w, h);
  final edge = <int>{};
  for (var x = 0; x < w; x++) {
    edge
      ..add(lab[x])
      ..add(lab[(h - 1) * w + x]);
  }
  for (var y = 0; y < h; y++) {
    edge
      ..add(lab[y * w])
      ..add(lab[y * w + w - 1]);
  }
  edge.remove(0);
  if (edge.isEmpty) return;
  final widths = <int, List<double>>{for (final c in edge) c: []};
  for (var i = 0; i < m.length; i++) {
    if (sk[i] == 1 && edge.contains(lab[i])) widths[lab[i]]!.add(dist[i]);
  }
  final kill = <int>{};
  for (final c in edge) {
    final st = stats[c];
    final big = (st[3] - st[1] + 1) * (st[4] - st[2] + 1) > 0.25 * w * h;
    final v = widths[c]!..sort();
    if (big || v.isEmpty || 2 * v[v.length ~/ 2] > 1.8 * pen) kill.add(c);
  }
  for (var i = 0; i < m.length; i++) {
    if (kill.contains(lab[i])) m[i] = sk[i] = 0;
  }
}

/// Half the pen's width: median distance to paper along the ink's ridges.
double _halfWidth(Float32List dist, int w, int h) {
  final v = <double>[];
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x, d = dist[i];
      if (d == 0) continue;
      if (d >= dist[i - 1] && d >= dist[i + 1] && d >= dist[i - w] && d >= dist[i + w]) v.add(d);
    }
  }
  if (v.length < 50) return 0;
  v.sort();
  return v[v.length ~/ 2];
}

/// Ink far wider than the pen is a loop the photo filled (o, a, e, d): a
/// hole is cut where it is deepest, so it thins to a ring, not a stub.
void _carveLoops(Uint8List ink, Float32List dist, int w, int h, double f) {
  final half = _halfWidth(dist, w, h);
  if (half == 0) return;
  // Dots (i, full stops) stay solid: only ink spanning 3 pen widths.
  final (il, ist) = _label(ink, w, h);
  for (var i = 0; i < ink.length; i++) {
    if (dist[i] <= f * half) continue;
    final st = ist[il[i]];
    if (math.max(st[3] - st[1], st[4] - st[2]) + 1 >= 6 * half) ink[i] = 0;
  }
}

/// Nothing is written along the frame itself (a sheet edge, a grid line
/// there): [sk] cleared within [m] pixels of it.
void _clearFrame(Uint8List sk, int w, int h, int m) {
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (x < m || y < m || x >= w - m || y >= h - m) sk[y * w + x] = 0;
    }
  }
}

/// Distance to the nearest paper pixel, 3x3 chamfer (0.955, 1.3693).
Float32List _chamfer(Uint8List m, int w, int h) {
  const a = 0.955, b = 1.3693, big = 1e9;
  final d = Float32List(m.length);
  for (var i = 0; i < m.length; i++) {
    d[i] = m[i] == 1 ? big : 0;
  }
  double at(int x, int y) => x < 0 || y < 0 || x >= w || y >= h ? 0 : d[y * w + x];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (d[i] == 0) continue;
      d[i] = math.min(d[i],
          math.min(math.min(at(x - 1, y) + a, at(x, y - 1) + a), math.min(at(x - 1, y - 1) + b, at(x + 1, y - 1) + b)));
    }
  }
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final i = y * w + x;
      if (d[i] == 0) continue;
      d[i] = math.min(d[i],
          math.min(math.min(at(x + 1, y) + a, at(x, y + 1) + a), math.min(at(x + 1, y + 1) + b, at(x - 1, y + 1) + b)));
    }
  }
  return d;
}

// 8-neighbourhood as (dy, dx), clockwise from north (Zhang-Suen order).
const _nb = [(-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1)];

int _px(Uint8List img, int w, int h, int x, int y) => x < 0 || y < 0 || x >= w || y >= h ? 0 : img[y * w + x];

/// Zhang-Suen thinning to a one-pixel skeleton.
Uint8List _thin(Uint8List ink, int w, int h) {
  final img = Uint8List.fromList(ink);
  var live = Int32List.fromList([for (var i = 0; i < img.length; i++) if (img[i] == 1) i]);
  final p = List<int>.filled(8, 0);
  var changed = true;
  while (changed) {
    changed = false;
    for (final step in [0, 1]) {
      final kill = <int>[];
      for (final i in live) {
        if (img[i] == 0) continue;
        final x = i % w, y = i ~/ w;
        var b = 0;
        for (var k = 0; k < 8; k++) {
          p[k] = _px(img, w, h, x + _nb[k].$2, y + _nb[k].$1);
          b += p[k];
        }
        if (b < 2 || b > 6) continue;
        var a = 0;
        for (var k = 0; k < 8; k++) {
          if (p[k] == 0 && p[(k + 1) % 8] == 1) a++;
        }
        if (a != 1) continue;
        final c1 = step == 0 ? p[0] * p[2] * p[4] : p[0] * p[2] * p[6];
        final c2 = step == 0 ? p[2] * p[4] * p[6] : p[0] * p[4] * p[6];
        if (c1 == 0 && c2 == 0) kill.add(i);
      }
      for (final i in kill) {
        img[i] = 0;
      }
      if (kill.isNotEmpty) changed = true;
    }
    live = Int32List.fromList([for (final i in live) if (img[i] == 1) i]);
  }
  return img;
}

/// Connected groups among the set positions of a 3x3 ring.
int _groups(List<int> ring) {
  var n = 0;
  final seen = List<bool>.filled(8, false);
  for (var k = 0; k < 8; k++) {
    if (ring[k] == 0 || seen[k]) continue;
    n++;
    final stack = [k];
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      if (seen[i]) continue;
      seen[i] = true;
      for (var j = 0; j < 8; j++) {
        if (ring[j] == 0 || seen[j]) continue;
        final d = (i - j) % 8;
        if (d == 1 || d == 7 || ((d == 2 || d == 6) && i.isEven && j.isEven)) stack.add(j);
      }
    }
  }
  return n;
}

/// Staircase corners dropped, so plain runs have exactly two neighbours.
void _unstair(Uint8List sk, int w, int h) {
  final ring = List<int>.filled(8, 0);
  var changed = true;
  while (changed) {
    changed = false;
    for (var i = 0; i < sk.length; i++) {
      if (sk[i] == 0) continue;
      final x = i % w, y = i ~/ w;
      var sum = 0;
      for (var k = 0; k < 8; k++) {
        ring[k] = _px(sk, w, h, x + _nb[k].$2, y + _nb[k].$1);
        sum += ring[k];
      }
      if (sum >= 2 && sum <= 4 && _groups(ring) == 1) {
        sk[i] = 0;
        changed = true;
      }
    }
  }
}

// ---------------------------------------------------------------- rulings

/// Skew (degrees) of the page's long lines: the angle whose projection
/// gives the sharpest row profile, over a coarse copy of [m].
double _skew(Uint8List m, int w, int h) {
  final f = math.max(1, math.max(w, h) ~/ 600);
  final xs = <double>[], ys = <double>[];
  for (var y = 0; y < h; y += f) {
    for (var x = 0; x < w; x += f) {
      if (m[y * w + x] == 1) {
        xs.add(x / f);
        ys.add(y / f);
      }
    }
  }
  if (xs.length < 100) return 0;
  final span = (math.max(w, h) / f * 1.5).ceil() + 2;
  final bins = Float64List(2 * span);
  var best = 0.0, bestScore = -1.0;
  for (var a = -8.0; a <= 8.0001; a += 0.25) {
    final t = a * math.pi / 180, c = math.cos(t), s = math.sin(t);
    var score = 0.0;
    for (final horizontal in [true, false]) {
      bins.fillRange(0, bins.length, 0);
      for (var i = 0; i < xs.length; i++) {
        final v = horizontal ? -s * xs[i] + c * ys[i] : c * xs[i] + s * ys[i];
        bins[(v + span).floor().clamp(0, bins.length - 1)]++;
      }
      for (final b in bins) {
        score += b * b;
      }
    }
    if (score > bestScore) (best, bestScore) = (a, score);
  }
  return best;
}

/// Ruling and grid lines in darkness [d], tilted by [deg]: per strip of
/// [strip] px, the row profile's median darkness peaks above the strip's own
/// noise floor; peaks linked across neighbouring strips (a line drifts or
/// bends) into chains reaching [reach] of the page; four chains or more
/// are a ruling. Returns the line pixels lighter than the ink ([lvl]).
Uint8List _rulingMask(Float32List d, int w0, int h0, double deg, int strip, double lvl, {double reach = 0.4}) {
  final out = Uint8List(d.length);
  final t = math.tan(deg * math.pi / 180);
  for (final transposed in [false, true]) {
    final w = transposed ? h0 : w0, h = transposed ? w0 : h0;
    // Row y of the levelled page at column x, in the picture.
    final tt = transposed ? -t : t;
    final cx = w / 2;
    int? at(int x, int y) {
      final yy = (y + (x - cx) * tt).round();
      if (yy < 0 || yy >= h) return null;
      return transposed ? x * w0 + yy : yy * w0 + x;
    }

    final ns = math.max(1, w ~/ strip);
    final prof = Float32List(h * ns);
    final col = Float32List(strip * 2 + 2);
    for (var k = 0; k < ns; k++) {
      final x0 = k * w ~/ ns, x1 = (k + 1) * w ~/ ns;
      for (var y = 0; y < h; y++) {
        var c = 0;
        for (var x = x0; x < x1; x++) {
          final i = at(x, y);
          if (i != null) col[c++] = d[i];
        }
        if (c < (x1 - x0) ~/ 2) continue;
        final v = Float32List.sublistView(col, 0, c)..sort();
        prof[y * ns + k] = v[c ~/ 2];
      }
    }
    // Peaks: above the strip's median by several of its deviations.
    final peak = Uint8List(h * ns);
    final base = Float32List(ns);
    for (var k = 0; k < ns; k++) {
      final v = [for (var y = 0; y < h; y++) prof[y * ns + k]]..sort();
      final med = v[h ~/ 2];
      final dev = [for (final x in v) (x - med).abs()]..sort();
      final floor = med + math.max(0.02, 6 * dev[h ~/ 2]);
      base[k] = med;
      for (var y = 0; y < h; y++) {
        final p = prof[y * ns + k];
        // A line on the frame edge peaks with one neighbour.
        if (p > floor && (y == 0 || p >= prof[(y - 1) * ns + k]) && (y == h - 1 || p >= prof[(y + 1) * ns + k])) {
          peak[y * ns + k] = 1;
        }
      }
    }
    // Chains: a peak links to the next strip's within two rows.
    final grown = _dilate(peak, ns, h, 1, 5);
    final (lab, stats) = _label(grown, ns, h);
    final long = [for (final st in stats) st[0] > 0 && st[3] - st[1] + 1 >= math.max(3, reach * ns)];
    if (long.where((v) => v).length < 4) continue;
    // Each chain's darkness and half thickness, its medians over the strips
    // (writing crossing it darkens a few).
    final lv = <int, List<double>>{}, th = <int, List<int>>{};
    final span = <int, (int, int)>{};
    for (var k = 0; k < ns; k++) {
      for (var y = 0; y < h; y++) {
        final c = lab[y * ns + k];
        if (peak[y * ns + k] == 0 || !long[c]) continue;
        final p = prof[y * ns + k], half = base[k] + 0.5 * (p - base[k]);
        var a = y, b = y;
        while (a > 0 && y - a < 6 && prof[(a - 1) * ns + k] > half) {
          a--;
        }
        while (b < h - 1 && b - y < 6 && prof[(b + 1) * ns + k] > half) {
          b++;
        }
        (lv[c] ??= []).add(p);
        (th[c] ??= []).add(math.max(y - a, b - y));
        span[y * ns + k] = (a, b);
      }
    }
    double med(List<num> v) => (List<num>.of(v)..sort())[v.length ~/ 2].toDouble();
    for (final en in span.entries) {
      final k = en.key % ns, y = en.key ~/ ns, c = lab[en.key];
      final p = med(lv[c]!), r = med(th[c]!).round() + 1;
      final keep = math.max(1.4 * p, p + 0.35 * (lvl - p));
      final x0 = k * w ~/ ns, x1 = (k + 1) * w ~/ ns;
      for (var yy = y - r; yy <= y + r; yy++) {
        for (var x = x0; x < x1; x++) {
          final i = at(x, yy);
          if (i != null && d[i] < keep) out[i] = 1;
        }
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------- the sheet

/// Corners of the sheet in [im] (photo pixels, clockwise from top left), or
/// null when it fills the frame or no clean four-sided shape is found.
List<(double, double)>? _findPage(_Rgb im) {
  final s = 512 / math.max(im.w, im.h);
  final small = im.resize(math.max(1, (im.w * s).round()), math.max(1, (im.h * s).round()));
  final w = small.w, h = small.h, n = w * h;
  final r = _gauss5(small.r, w, h), g = _gauss5(small.g, w, h), b = _gauss5(small.b, w, h);
  // Paper: bright and grey; a shadow keeps it grey.
  final sc = Uint8List(n);
  for (var i = 0; i < n; i++) {
    final v = math.max(r[i], math.max(g[i], b[i])), mn = math.min(r[i], math.min(g[i], b[i]));
    final sat = v > 0 ? (v - mn) / v : 0.0;
    sc[i] = ((v / 255 - 0.8 * sat) * 255).round().clamp(0, 255);
  }
  final t = _otsu(sc);
  var m = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (sc[i] > t) m[i] = 1;
  }
  m = _erode(_dilate(m, w, h, 9, 9), w, h, 9, 9);
  m = _open(m, w, h, 5, 5);
  final (lab, stats) = _label(m, w, h);
  var best = 0;
  for (var c = 1; c < stats.length; c++) {
    if (best == 0 || stats[c][0] > stats[best][0]) best = c;
  }
  if (best == 0 || stats[best][0] < 0.2 * n) return null;
  // The region's outline: each row's and each column's two ends.
  final pts = <(double, double)>[];
  for (var y = 0; y < h; y++) {
    var x0 = -1, x1 = -1;
    for (var x = 0; x < w; x++) {
      if (lab[y * w + x] == best) {
        if (x0 < 0) x0 = x;
        x1 = x;
      }
    }
    if (x0 >= 0) pts.addAll([(x0.toDouble(), y.toDouble()), (x1.toDouble(), y.toDouble())]);
  }
  for (var x = 0; x < w; x++) {
    var y0 = -1, y1 = -1;
    for (var y = 0; y < h; y++) {
      if (lab[y * w + x] == best) {
        if (y0 < 0) y0 = y;
        y1 = y;
      }
    }
    if (y0 >= 0) pts.addAll([(x.toDouble(), y0.toDouble()), (x.toDouble(), y1.toDouble())]);
  }
  final hull = _convexHull(pts);
  if (_area(hull) > 0.97 * (w - 1) * (h - 1)) return null;
  final q = fitQuad(hull, w, h);
  if (q == null) return null;
  final fit = _refineQuad(q, pts) ?? q;
  return [for (final (x, y) in fit) (x / s, y / s)];
}

Float32List _gauss5(Float32List a, int w, int h) {
  const k = [1.0, 4.0, 6.0, 4.0, 1.0];
  Float32List pass(Float32List src, bool rows) {
    final out = Float32List(src.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0.0;
        for (var j = -2; j <= 2; j++) {
          // Mirrored border (OpenCV's default).
          var xx = rows ? x + j : x, yy = rows ? y : y + j;
          if (xx < 0) xx = -xx;
          if (xx >= w) xx = 2 * w - 2 - xx;
          if (yy < 0) yy = -yy;
          if (yy >= h) yy = 2 * h - 2 - yy;
          sum += k[j + 2] * src[yy.clamp(0, h - 1) * w + xx.clamp(0, w - 1)];
        }
        out[y * w + x] = sum / 16;
      }
    }
    return out;
  }

  return pass(pass(a, true), false);
}

int _otsu(Uint8List v) {
  final hist = Float64List(256);
  for (final x in v) {
    hist[x]++;
  }
  final total = v.length.toDouble();
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0, wB = 0.0, best = 0.0;
  var t = 0;
  for (var i = 0; i < 256; i++) {
    wB += hist[i];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += i * hist[i];
    final mB = sumB / wB, mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) (best, t) = (between, i);
  }
  return t;
}

List<(double, double)> _convexHull(List<(double, double)> p) {
  final pts = [...p]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  if (pts.length < 3) return pts;
  double cross((double, double) o, (double, double) a, (double, double) b) =>
      (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);
  final lower = <(double, double)>[], upper = <(double, double)>[];
  for (final q in pts) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, q) <= 0) {
      lower.removeLast();
    }
    lower.add(q);
  }
  for (final q in pts.reversed) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, q) <= 0) {
      upper.removeLast();
    }
    upper.add(q);
  }
  return [...lower.sublist(0, lower.length - 1), ...upper.sublist(0, upper.length - 1)];
}

double _area(List<(double, double)> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final (x0, y0) = p[i];
    final (x1, y1) = p[(i + 1) % p.length];
    a += x0 * y1 - x1 * y0;
  }
  return a.abs() / 2;
}

/// Four corners from a sheet's hull: the four longest sides of the
/// simplified hull, extended to meet (a shadow or a finger cutting a corner
/// adds a short side). Null when a side runs along the frame (the sheet is
/// cropped) or the shape is no sheet.
List<(double, double)>? fitQuad(List<(double, double)> hull, int w, int h) {
  if (hull.length < 4) return null;
  var peri = 0.0;
  for (var i = 0; i < hull.length; i++) {
    final (x0, y0) = hull[i];
    final (x1, y1) = hull[(i + 1) % hull.length];
    peri += math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
  }
  var poly = hull;
  for (final eps in [0.01, 0.015, 0.02, 0.03]) {
    poly = _closedDouglasPeucker(hull, eps * peri);
    if (poly.length <= 8) break;
  }
  if (poly.length < 4) return null;
  final n = poly.length;
  double len(int i) {
    final (x0, y0) = poly[i];
    final (x1, y1) = poly[(i + 1) % n];
    return math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
  }

  final order = List<int>.generate(n, (i) => i)..sort((a, b) => len(b).compareTo(len(a)));
  final keep = order.sublist(0, 4)..sort();
  final q = <(double, double)>[];
  for (var j = 0; j < 4; j++) {
    final a = keep[(j + 3) % 4], b = keep[j];
    final c = _meet(poly[a], poly[(a + 1) % n], poly[b], poly[(b + 1) % n]);
    if (c == null) return null;
    q.add(c);
  }
  final m = 0.01 * math.max(w, h);
  for (var i = 0; i < 4; i++) {
    final a = q[i], b = q[(i + 1) % 4];
    if ((a.$1.abs() < m && b.$1.abs() < m) ||
        (a.$2.abs() < m && b.$2.abs() < m) ||
        ((a.$1 - (w - 1)).abs() < m && (b.$1 - (w - 1)).abs() < m) ||
        ((a.$2 - (h - 1)).abs() < m && (b.$2 - (h - 1)).abs() < m)) {
      return null;
    }
  }
  for (final (x, y) in q) {
    if (x < -0.03 * w || x > 1.03 * w || y < -0.03 * h || y > 1.03 * h) return null;
  }
  // Convex, corners near right angles.
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final o = q[i], a = q[(i + 3) % 4], b = q[(i + 1) % 4];
    final ux = a.$1 - o.$1, uy = a.$2 - o.$2, vx = b.$1 - o.$1, vy = b.$2 - o.$2;
    final cr = ux * vy - uy * vx;
    final sg = cr > 0 ? 1 : -1;
    if (sign != 0 && sg != sign) return null;
    sign = sg;
    final cos = (ux * vx + uy * vy) / math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
    final ang = math.acos(cos.clamp(-1.0, 1.0)) * 180 / math.pi;
    if (ang < 55 || ang > 125) return null;
  }
  final ha = _area(hull), qa = _area(q);
  if (qa < 0.97 * ha || qa > 1.35 * ha) return null;
  return _orderQuad(q);
}

/// Each side refitted (total least squares) to the outline points lying
/// along it, corners re-intersected: the hull's vertices alone sit a pixel
/// or two off.
List<(double, double)>? _refineQuad(List<(double, double)> q, List<(double, double)> pts) {
  final lines = <((double, double), (double, double))>[];
  for (var i = 0; i < 4; i++) {
    final a = q[i], b = q[(i + 1) % 4];
    final dx = b.$1 - a.$1, dy = b.$2 - a.$2, len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return null;
    final ux = dx / len, uy = dy / len;
    var n = 0, mx = 0.0, my = 0.0;
    final sel = <(double, double)>[];
    for (final p in pts) {
      final t = ((p.$1 - a.$1) * ux + (p.$2 - a.$2) * uy) / len;
      final off = ((p.$1 - a.$1) * uy - (p.$2 - a.$2) * ux).abs();
      if (t > 0.1 && t < 0.9 && off < 2.5) {
        sel.add(p);
        mx += p.$1;
        my += p.$2;
        n++;
      }
    }
    if (n < 10) return null;
    mx /= n;
    my /= n;
    var sxx = 0.0, sxy = 0.0, syy = 0.0;
    for (final p in sel) {
      sxx += (p.$1 - mx) * (p.$1 - mx);
      sxy += (p.$1 - mx) * (p.$2 - my);
      syy += (p.$2 - my) * (p.$2 - my);
    }
    final th = 0.5 * math.atan2(2 * sxy, sxx - syy);
    lines.add(((mx, my), (mx + math.cos(th), my + math.sin(th))));
  }
  final out = <(double, double)>[];
  for (var i = 0; i < 4; i++) {
    final a = lines[(i + 3) % 4], b = lines[i];
    final c = _meet(a.$1, a.$2, b.$1, b.$2);
    if (c == null) return null;
    final (ox, oy) = q[i];
    if ((c.$1 - ox).abs() > 10 || (c.$2 - oy).abs() > 10) return null;
    out.add(c);
  }
  return out;
}

(double, double)? _meet((double, double) a0, (double, double) a1, (double, double) b0, (double, double) b1) {
  final d1x = a1.$1 - a0.$1, d1y = a1.$2 - a0.$2, d2x = b1.$1 - b0.$1, d2y = b1.$2 - b0.$2;
  final den = d1x * d2y - d1y * d2x;
  if (den.abs() < 1e-9) return null;
  final t = ((b0.$1 - a0.$1) * d2y - (b0.$2 - a0.$2) * d2x) / den;
  return (a0.$1 + t * d1x, a0.$2 + t * d1y);
}

/// Clockwise (y down) from the corner nearest the top left.
List<(double, double)> _orderQuad(List<(double, double)> q) {
  final cx = q.fold(0.0, (a, p) => a + p.$1) / 4, cy = q.fold(0.0, (a, p) => a + p.$2) / 4;
  final s = [...q]..sort((a, b) => math.atan2(a.$2 - cy, a.$1 - cx).compareTo(math.atan2(b.$2 - cy, b.$1 - cx)));
  var first = 0;
  for (var i = 1; i < 4; i++) {
    if (s[i].$1 + s[i].$2 < s[first].$1 + s[first].$2) first = i;
  }
  return [for (var i = 0; i < 4; i++) s[(first + i) % 4]];
}

List<(double, double)> _closedDouglasPeucker(List<(double, double)> p, double eps) {
  if (p.length < 4) return p;
  var far = 0;
  var best = -1.0;
  for (var i = 1; i < p.length; i++) {
    final d = (p[i].$1 - p[0].$1) * (p[i].$1 - p[0].$1) + (p[i].$2 - p[0].$2) * (p[i].$2 - p[0].$2);
    if (d > best) (best, far) = (d, i);
  }
  final a = _douglasPeucker(p.sublist(0, far + 1), eps);
  final b = _douglasPeucker([...p.sublist(far), p[0]], eps);
  return [...a, ...b.sublist(1, b.length - 1)];
}

/// The sheet straightened to its own size, and the matrix taking photo
/// pixels to it.
(_Rgb, Float64List) _rectify(_Rgb im, List<(double, double)> quad) {
  final [tl, tr, br, bl] = quad;
  double dist((double, double) a, (double, double) b) => math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));
  final wq = (dist(tl, tr) + dist(bl, br)) / 2, hq = (dist(tl, bl) + dist(tr, br)) / 2;
  final W = math.max(8, wq.round()), H = math.max(8, hq.round());
  final m = _perspective(quad, [(0, 0), (W.toDouble(), 0), (W.toDouble(), H.toDouble()), (0, H.toDouble())]);
  final inv = _invert(m);
  final n = W * H;
  final r = Float32List(n), g = Float32List(n), b = Float32List(n);
  for (var y = 0; y < H; y++) {
    for (var x = 0; x < W; x++) {
      final z = inv[6] * x + inv[7] * y + inv[8];
      final sx = ((inv[0] * x + inv[1] * y + inv[2]) / z).clamp(0.0, im.w - 1.0);
      final sy = ((inv[3] * x + inv[4] * y + inv[5]) / z).clamp(0.0, im.h - 1.0);
      final x0 = sx.floor(), y0 = sy.floor(), x1 = math.min(x0 + 1, im.w - 1), y1 = math.min(y0 + 1, im.h - 1);
      final tx = sx - x0, ty = sy - y0;
      double bil(Float32List p) =>
          (p[y0 * im.w + x0] * (1 - tx) + p[y0 * im.w + x1] * tx) * (1 - ty) +
          (p[y1 * im.w + x0] * (1 - tx) + p[y1 * im.w + x1] * tx) * ty;
      final i = y * W + x;
      r[i] = bil(im.r);
      g[i] = bil(im.g);
      b[i] = bil(im.b);
    }
  }
  return (_Rgb(W, H, r, g, b), m);
}

Float64List _identity() => Float64List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1]);
Float64List _scale(double sx, double sy) => Float64List.fromList([sx, 0, 0, 0, sy, 0, 0, 0, 1]);

Float64List _mul(Float64List a, Float64List b) {
  final o = Float64List(9);
  for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      o[3 * i + j] = a[3 * i] * b[j] + a[3 * i + 1] * b[3 + j] + a[3 * i + 2] * b[6 + j];
    }
  }
  return o;
}

Float64List _invert(Float64List m) {
  final a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8];
  final A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g;
  final det = a * A + b * B + c * C;
  return Float64List.fromList([
    A / det, -(b * i - c * h) / det, (b * f - c * e) / det,
    B / det, (a * i - c * g) / det, -(a * f - c * d) / det,
    C / det, -(a * h - b * g) / det, (a * e - b * d) / det,
  ]);
}

/// Homography taking the four [from] points to [to].
Float64List _perspective(List<(double, double)> from, List<(double, double)> to) {
  final a = List.generate(8, (_) => Float64List(9));
  for (var k = 0; k < 4; k++) {
    final (x, y) = from[k];
    final (u, v) = to[k];
    a[2 * k].setAll(0, [x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
    a[2 * k + 1].setAll(0, [0, 0, 0, x, y, 1, -v * x, -v * y, v]);
  }
  for (var c = 0; c < 8; c++) {
    var p = c;
    for (var r = c + 1; r < 8; r++) {
      if (a[r][c].abs() > a[p][c].abs()) p = r;
    }
    final t = a[c];
    a[c] = a[p];
    a[p] = t;
    for (var r = 0; r < 8; r++) {
      if (r == c) continue;
      final f = a[r][c] / a[c][c];
      for (var k = c; k < 9; k++) {
        a[r][k] -= f * a[c][k];
      }
    }
  }
  return Float64List.fromList([for (var r = 0; r < 8; r++) a[r][8] / a[r][r], 1]);
}

// ---------------------------------------------------------------- skeleton

/// Skeleton -> pixel paths (indices): spurs up to [minSpur] off a junction
/// pruned, paths continued straight through junctions where two branches
/// line up, lone dots kept as two-point paths.
List<List<int>> traceSkeleton(Uint8List sk0, int w, int h, int minSpur) {
  var sk = Uint8List.fromList(sk0);
  List<int> nbrs(int p) {
    final x = p % w, y = p ~/ w;
    return [
      for (final (dy, dx) in _nb)
        if (_px(sk, w, h, x + dx, y + dy) == 1) (y + dy) * w + x + dx
    ];
  }

  Map<int, int> degrees() => {
        for (var i = 0; i < sk.length; i++)
          if (sk[i] == 1) i: nbrs(i).length
      };

  for (var round = 0; round < 2; round++) {
    final deg = degrees();
    var removed = false;
    for (final e in [for (final en in deg.entries) if (en.value == 1) en.key]) {
      final path = [e];
      int? prev;
      var cur = e;
      while (true) {
        final tail = path.length > 3 ? path.sublist(path.length - 3) : path;
        final nb = [for (final q in nbrs(cur)) if (q != prev && !tail.contains(q)) q];
        if (nb.length != 1 || (deg[nb[0]] ?? 0) >= 3 || path.length > minSpur) break;
        prev = cur;
        cur = nb[0];
        path.add(cur);
      }
      final nb = [for (final q in nbrs(cur)) if (q != prev) q];
      if (path.length <= minSpur && (deg[cur] ?? 0) < 3 && [...nb, cur].any((q) => (deg[q] ?? 0) >= 3)) {
        for (final p in path) {
          sk[p] = 0;
        }
        removed = true;
      }
    }
    if (!removed) break;
    sk = _thin(sk, w, h);
    _unstair(sk, w, h);
  }

  final deg = degrees();
  final nodeOf = <int, int>{};
  final nodes = <List<int>>[];
  for (final en in deg.entries) {
    if (en.value < 3 || nodeOf.containsKey(en.key)) continue;
    final id = nodes.length;
    final comp = <int>[];
    final stack = [en.key];
    nodeOf[en.key] = id;
    while (stack.isNotEmpty) {
      final q = stack.removeLast();
      comp.add(q);
      for (final r in nbrs(q)) {
        if ((deg[r] ?? 0) >= 3 && !nodeOf.containsKey(r)) {
          nodeOf[r] = id;
          stack.add(r);
        }
      }
    }
    nodes.add(comp);
  }
  for (final en in deg.entries) {
    if (en.value <= 1 && !nodeOf.containsKey(en.key)) {
      nodeOf[en.key] = nodes.length;
      nodes.add([en.key]);
    }
  }
  final n = sk.length;
  final used = <int>{};
  final edges = <(int, int, List<int>)>[];
  for (var ni = 0; ni < nodes.length; ni++) {
    for (final p in nodes[ni]) {
      for (final q in nbrs(p)) {
        if (nodeOf.containsKey(q) || used.contains(p * n + q)) continue;
        final path = [p, q];
        used
          ..add(p * n + q)
          ..add(q * n + p);
        var prev = p, cur = q;
        while (!nodeOf.containsKey(cur)) {
          final nxt = [for (final r in nbrs(cur)) if (r != prev && !used.contains(cur * n + r)) r];
          if (nxt.isEmpty) break;
          int key(int r) => (nodeOf.containsKey(r) ? 10 : 0) + (r % w - cur % w).abs() + (r ~/ w - cur ~/ w).abs();
          nxt.sort((a, b) => key(a).compareTo(key(b)));
          final r = nxt.first;
          used
            ..add(cur * n + r)
            ..add(r * n + cur);
          prev = cur;
          cur = r;
          path.add(cur);
        }
        edges.add((ni, nodeOf[cur] ?? -1, path));
      }
    }
  }
  // Rings with no junction.
  final seen = <int>{for (final e in edges) ...e.$3};
  for (final en in deg.entries) {
    if (en.value != 2 || seen.contains(en.key)) continue;
    final path = [en.key];
    seen.add(en.key);
    int? prev;
    var cur = en.key;
    while (true) {
      final nxt = [for (final r in nbrs(cur)) if (r != prev && !seen.contains(r)) r];
      if (nxt.isEmpty) break;
      prev = cur;
      cur = nxt.first;
      seen.add(cur);
      path.add(cur);
    }
    if (path.length > 4) edges.add((-1, -1, [...path, en.key]));
  }
  final has = <int>{for (final e in edges) ...[e.$1, e.$2]};
  final dots = [
    for (var i = 0; i < nodes.length; i++)
      if (!has.contains(i)) [nodes[i].first, nodes[i].first]
  ];
  return [..._mergeEdges(edges, nodes, w), ...dots];
}

/// Short paths (bars, hooks, a filled bowl's ring) touching a longer one of
/// the same colour join it as a there-and-back detour: strokes stay letter
/// sized, as a pen draws them, instead of pieces cut at every junction.
/// [pts] are the paths' points (one per pixel of [paths]); returns, per
/// kept path, its points with the detours in.
List<(int, List<(double, double)>)> _splice(List<List<int>> paths, List<List<(double, double)>> pts, List<int> argb, int w,
    int h, double maxLen, double reach) {
  final n = paths.length;
  final len = [for (final p in pts) _length(p)];
  // Owner of each path pixel: the longest path through it.
  final owner = <int, (int, int)>{};
  for (var i = 0; i < n; i++) {
    for (var k = 0; k < paths[i].length; k++) {
      final o = owner[paths[i][k]];
      if (o == null || len[o.$1] < len[i]) owner[paths[i][k]] = (i, k);
    }
  }
  bool near(int a, int b) {
    final ca = argb[a], cb = argb[b];
    for (var s = 0; s <= 16; s += 8) {
      if ((((ca >> s) & 255) - ((cb >> s) & 255)).abs() > 40) return false;
    }
    return true;
  }

  // Where path i attaches: (parent, index there, from its end).
  (int, int, bool)? attach(int i) {
    (int, int, bool)? best;
    var bestLen = len[i];
    for (final end in [false, true]) {
      final e = end ? paths[i].last : paths[i].first;
      final ex = e % w, ey = e ~/ w;
      final r = reach.ceil();
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx * dx + dy * dy > reach * reach) continue;
          final x = ex + dx, y = ey + dy;
          if (x < 0 || y < 0 || x >= w || y >= h) continue;
          final o = owner[y * w + x];
          if (o == null || o.$1 == i || !near(i, o.$1)) continue;
          // Only into a longer path (ties by index): attachments form a tree.
          final l = len[o.$1];
          if (l > bestLen || l == bestLen && o.$1 < i && best == null) {
            best = (o.$1, o.$2, end);
            bestLen = l;
          }
        }
      }
    }
    return best;
  }

  final kids = <int, List<(int, int, bool)>>{};
  final joined = List<bool>.filled(n, false);
  for (var i = 0; i < n; i++) {
    if (len[i] > maxLen || paths[i].length < 2) continue;
    final a = attach(i);
    if (a == null) continue;
    joined[i] = true;
    (kids[a.$1] ??= []).add((i, a.$2, a.$3));
  }
  List<(double, double)> expand(int i) {
    final ks = kids[i];
    if (ks == null) return pts[i];
    ks.sort((a, b) => a.$2.compareTo(b.$2));
    final out = <(double, double)>[];
    var j = 0;
    for (var k = 0; k < pts[i].length; k++) {
      out.add(pts[i][k]);
      for (; j < ks.length && ks[j].$2 == k; j++) {
        final (c, _, fromEnd) = ks[j];
        var sub = expand(c);
        if (fromEnd) sub = sub.reversed.toList();
        final loop = _dist(sub.first, sub.last) < 3;
        out
          ..addAll(sub)
          ..addAll(loop ? const [] : sub.reversed.skip(1))
          ..add(pts[i][k]);
      }
    }
    return out;
  }

  return [for (var i = 0; i < n; i++) if (!joined[i]) (i, expand(i))];
}

double _length(List<(double, double)> p) {
  var l = 0.0;
  for (var i = 1; i < p.length; i++) {
    l += _dist(p[i - 1], p[i]);
  }
  return l;
}

double _dist((double, double) a, (double, double) b) =>
    math.sqrt((a.$1 - b.$1) * (a.$1 - b.$1) + (a.$2 - b.$2) * (a.$2 - b.$2));

/// Unit direction out of the node along [path] (from its start or its end).
(double, double)? _dir(List<int> path, bool atStart, int w) {
  final k = math.min(8, path.length);
  if (k < 2) return null;
  final a = atStart ? path[0] : path[path.length - 1];
  final b = atStart ? path[k - 1] : path[path.length - k];
  final vx = (b % w - a % w).toDouble(), vy = (b ~/ w - a ~/ w).toDouble();
  final l = math.sqrt(vx * vx + vy * vy);
  return l == 0 ? null : (vx / l, vy / l);
}

/// Joins pairs of edges meeting at a junction head-on (directions out of
/// it nearly opposite), so a crossing stays two strokes, not four.
List<List<int>> _mergeEdges(List<(int, int, List<int>)> edges, List<List<int>> nodes, int w) {
  final inc = <int, List<(int, bool)>>{};
  for (var ei = 0; ei < edges.length; ei++) {
    final (a, b, p) = edges[ei];
    if (p.length < 2) continue;
    if (a >= 0) (inc[a] ??= []).add((ei, true));
    if (b >= 0) (inc[b] ??= []).add((ei, false));
  }
  final link = <(int, bool), (int, bool)>{};
  for (final lst in inc.values) {
    if (lst.length < 2) continue;
    final cand = <(double, (int, bool), (int, bool))>[];
    for (var i = 0; i < lst.length; i++) {
      for (var j = i + 1; j < lst.length; j++) {
        if (lst[i].$1 == lst[j].$1) continue;
        final da = _dir(edges[lst[i].$1].$3, lst[i].$2, w), db = _dir(edges[lst[j].$1].$3, lst[j].$2, w);
        if (da == null || db == null) continue;
        cand.add((da.$1 * db.$1 + da.$2 * db.$2, lst[i], lst[j]));
      }
    }
    cand.sort((a, b) => a.$1.compareTo(b.$1));
    final taken = <(int, bool)>{};
    for (final (c, x, y) in cand) {
      if (c > -0.75) break;
      if (taken.contains(x) || taken.contains(y)) continue;
      taken
        ..add(x)
        ..add(y);
      link[x] = y;
      link[y] = x;
    }
  }
  final out = <List<int>>[];
  final done = <int>{};
  for (var ei = 0; ei < edges.length; ei++) {
    if (done.contains(ei)) continue;
    var cur = ei;
    var atStart = true;
    for (var guard = 0; link.containsKey((cur, atStart)) && guard < edges.length; guard++) {
      final (nxt, nstart) = link[(cur, atStart)]!;
      if (nxt == ei) break;
      cur = nxt;
      atStart = !nstart;
    }
    final chain = <int>[];
    var e = cur, fromStart = atStart;
    while (!done.contains(e)) {
      done.add(e);
      final p = edges[e].$3;
      final seg = fromStart ? p : p.reversed.toList();
      chain.addAll(chain.isEmpty ? seg : seg.skip(1));
      final end = (e, !fromStart);
      final next = link[end];
      if (next == null) break;
      e = next.$1;
      fromStart = next.$2;
    }
    out.add(chain);
  }
  return out;
}

// ---------------------------------------------------------------- lines

List<(double, double)> _smooth(List<(double, double)> p, double sigma, bool closed) {
  if (p.length < 5 || sigma <= 0) return p;
  final r = (3 * sigma).toInt();
  final k = [for (var i = -r; i <= r; i++) math.exp(-0.5 * (i / sigma) * (i / sigma))];
  final ks = k.fold(0.0, (a, b) => a + b);
  final n = p.length;
  (double, double) at(int i) {
    if (closed) return p[((i % (n - 1)) + (n - 1)) % (n - 1)];
    return p[i.clamp(0, n - 1)];
  }

  final out = [
    for (var i = 0; i < n; i++)
      () {
        var x = 0.0, y = 0.0;
        for (var j = -r; j <= r; j++) {
          final q = at(i + j);
          x += k[j + r] * q.$1;
          y += k[j + r] * q.$2;
        }
        return (x / ks, y / ks);
      }()
  ];
  if (closed) {
    out[n - 1] = out[0];
  } else {
    out[0] = p[0];
    out[n - 1] = p[n - 1];
  }
  return out;
}

/// Douglas-Peucker simplification of an open polyline to within [eps].
List<(double, double)> _douglasPeucker(List<(double, double)> pts, double eps) {
  if (pts.length < 3) return pts;
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = keep[pts.length - 1] = true;
  final stack = [(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    final (ax, ay) = pts[a];
    final (bx, by) = pts[b];
    final dx = bx - ax, dy = by - ay, len = math.sqrt(dx * dx + dy * dy);
    var far = -1;
    var best = eps;
    for (var i = a + 1; i < b; i++) {
      final (px, py) = pts[i];
      final d = len == 0
          ? math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay))
          : ((px - ax) * dy - (py - ay) * dx).abs() / len;
      if (d > best) (far, best) = (i, d);
    }
    if (far < 0) continue;
    keep[far] = true;
    stack
      ..add((a, far))
      ..add((far, b));
  }
  return [for (var i = 0; i < pts.length; i++) if (keep[i]) pts[i]];
}
