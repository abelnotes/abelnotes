// A picture of a circuit as pen strokes, so a pasted schematic goes through
// the same tidy-up as one drawn by hand. Port of the thin-and-trace steps of
// ml/circuits/photos_to_strokes.py; ink is measured against the paper level
// around each pixel, so faint printed wires survive next to dark text.

import 'dart:math' as math;
import 'dart:typed_data';

import 'native_engine.dart';
import 'raster.dart';

/// One traced line in source image pixels: flat [x0, y0, x1, y1, ...], the
/// width of the ink it runs along and its colour (ARGB).
class TracedStroke {
  TracedStroke(this.points, this.width, this.color);
  final Float64List points;
  final double width;
  final int color;
}

/// The image is traced with its long side at this many pixels.
const int kTraceLongSide = 1600;

// 8-neighbourhood as (dy, dx), clockwise from north (Zhang-Suen order).
const _nb = [(-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1)];

/// Traces the ink of an RGBA image ([w] x [h], row-major) into polylines.
List<TracedStroke> traceImageInk(Uint8List rgba, int w, int h) => traceImage(rgba, w, h).strokes;

/// [traceImageInk], with the ink mask the lines were thinned from.
({List<TracedStroke> strokes, InkMask ink}) traceImage(Uint8List rgba, int w, int h) {
  final s = kTraceLongSide / math.max(w, h);
  final cw = math.max(1, (w * s).round()), ch = math.max(1, (h * s).round());
  final native = NativeImage.open();
  if (native != null) {
    final t = native.trace(rgba, w, h, cw, ch, s);
    return (strokes: [for (final (p, wd, c) in t.strokes) TracedStroke(p, wd, c)], ink: InkMask(t.ink, cw, ch, s));
  }
  final n = cw * ch;
  final (:rgb, :gray, :ink, :skel, :dist, :tinted) = _tracePrep(rgba, w, h, cw, ch);
  final out = <TracedStroke>[];
  // A filled head (a transistor's arrow) thins to a dot: it goes in as its
  // outline, which reads like a drawn one.
  final dots = [for (var i = 0; i < n; i++) if (skel[i] == 1 && dist[i] > 0) dist[i]]..sort();
  final half = dots.isEmpty ? 1.0 : dots[dots.length ~/ 2] / 3;
  for (final head in _filledHeads(ink, dist, cw, ch, half)) {
    for (final p in head) {
      skel[p] = 0;
    }
    final r = rgb[3 * head.first], g = rgb[3 * head.first + 1], b = rgb[3 * head.first + 2];
    final chroma = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
    // Nested outlines, peeled a pixel at a time: about the ink of a head
    // filled in by hand.
    final mask = Uint8List(n);
    for (final p in head) {
      mask[p] = 1;
    }
    var left = head.toList();
    while (left.length >= 4) {
      final ring = _douglasPeucker([for (final p in _outline(mask, cw, ch, left.reduce(math.min))) (p % cw + 0.5, p ~/ cw + 0.5)], 0.8);
      if (ring.length >= 3) {
        out.add(TracedStroke(
          Float64List.fromList([for (final (x, y) in [...ring, ring.first]) ...[x / s, y / s]]),
          1 / s,
          chroma < 40 || tinted ? 0xFF000000 : 0xFF000000 | (r << 16) | (g << 8) | b,
        ));
      }
      final edge = [
        for (final p in left)
          if (p % cw == 0 || p % cw == cw - 1 || mask[p - 1] == 0 || mask[p + 1] == 0 || p < cw || p >= n - cw || mask[p - cw] == 0 || mask[p + cw] == 0) p
      ];
      for (final p in edge) {
        mask[p] = 0;
      }
      left = [for (final p in left) if (mask[p] == 1) p];
    }
  }
  for (final path in _trace(skel, cw, ch)) {
    // Twice the distance to paper at the centre line, less the pixel it sits
    // on: the ink's width.
    final widths = [for (final p in path) 2 * dist[p] / 3 - 1]..sort();
    var dark = path.first;
    for (final p in path) {
      if (gray[p] < gray[dark]) dark = p;
    }
    final r = rgb[3 * dark], g = rgb[3 * dark + 1], b = rgb[3 * dark + 2];
    // Print and pencil come out grey, faint where anti-aliased: they turn
    // black. Coloured ink keeps its colour.
    final chroma = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
    // On tinted paper the ink takes the paper's hue: it is black ink.
    final color = chroma < 40 || tinted ? 0xFF000000 : 0xFF000000 | (r << 16) | (g << 8) | b;
    final pts = _douglasPeucker([for (final p in path) (p % cw + 0.5, p ~/ cw + 0.5)], 0.8);
    if (pts.length < 2) continue;
    out.add(TracedStroke(
      Float64List.fromList([for (final (x, y) in pts) ...[x / s, y / s]]),
      math.max(1.0, widths[widths.length ~/ 2]) / s,
      color,
    ));
  }
  return (strokes: out, ink: InkMask(ink, cw, ch, s));
}

/// Resampled RGB, grey, ink mask, skeleton and chamfer distance at cw x ch
/// (packages/circuit_engine/src/image_ink.c does the same, faster).
({Uint8List rgb, Uint8List gray, Uint8List ink, Uint8List skel, Int32List dist, bool tinted}) _tracePrep(
    Uint8List rgba, int w, int h, int cw, int ch) {
  final rgb = _resample(rgba, w, h, cw, ch);
  final n = cw * ch;
  final (gray, diff, thr, tinted) = _darkness(rgb, 3, cw, ch);
  final ink = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (diff[i] >= thr) ink[i] = 1;
  }
  _dropFrame(ink, cw, ch);
  _dropSpecks(ink, cw, ch);

  // Width is measured at half the local darkness, so the anti-aliased fringe
  // the low threshold keeps does not fatten the lines.
  final peak = _maxFilter(diff, cw, ch, 9);
  final core = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (ink[i] == 1 && diff[i] * 2 >= peak[i]) core[i] = 1;
  }
  final dist = _distance(core, cw, ch);
  final skel = _thin(ink, cw, ch);
  _unstair(skel, cw, ch);
  return (rgb: rgb, gray: gray, ink: ink, skel: skel, dist: dist, tinted: tinted);
}

/// What is left of the picture once its circuit is redrawn: its ink on a
/// clear background (labels and notes stay exactly as printed), less the
/// pixels along [cut] (traced lines in image pixels with their ink width).
/// Cropped to what remains: (RGBA, left, top, width, height), or null when
/// nothing does.
(Uint8List, int, int, int, int)? inkLeftover(Uint8List rgba, int w, int h, List<(Float64List, double)> cut) {
  final native = NativeImage.open();
  if (native != null) {
    final m = native.leftover(rgba, w, h, cut);
    return m.kept < 30 ? null : _crop(rgba, m.alpha, w, m.x0, m.y0, m.x1, m.y1);
  }
  final n = w * h;
  final rgb = Uint8List(3 * n);
  for (var i = 0; i < n; i++) {
    final a = rgba[4 * i + 3] / 255;
    for (var c = 0; c < 3; c++) {
      rgb[3 * i + c] = (rgba[4 * i + c] * a + 255 * (1 - a)).round();
    }
  }
  final (_, diff, thr, _) = _darkness(rgb, 3, w, h);
  final gone = Uint8List(n);
  for (final (pts, width) in cut) {
    // Past the ink's edge by its anti-aliased fringe.
    final r = width / 2 + 2.5;
    void stamp(double cx, double cy) {
      for (var y = (cy - r).floor(); y <= (cy + r).ceil(); y++) {
        for (var x = (cx - r).floor(); x <= (cx + r).ceil(); x++) {
          if (x < 0 || y < 0 || x >= w || y >= h || (x - cx) * (x - cx) + (y - cy) * (y - cy) > r * r) continue;
          gone[y * w + x] = 1;
        }
      }
    }

    for (var i = 0; i + 3 < pts.length; i += 2) {
      final dx = pts[i + 2] - pts[i], dy = pts[i + 3] - pts[i + 1];
      final steps = math.max(1, math.sqrt(dx * dx + dy * dy).ceil());
      for (var k = 0; k <= steps; k++) {
        stamp(pts[i] + dx * k / steps, pts[i + 1] + dy * k / steps);
      }
    }
    if (pts.length == 2) stamp(pts[0], pts[1]);
  }
  final ink = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (diff[i] >= thr && gone[i] == 0) ink[i] = 1;
  }
  // The frame goes as in tracing; slivers the cut left are dropped.
  _dropFrame(ink, w, h);
  _dropSpecks(ink, w, h, minArea: 15);
  _dropTouchingEdge(ink, w, h);
  var x0 = w, y0 = h, x1 = -1, y1 = -1, kept = 0;
  final alpha = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (ink[i] == 0) continue;
    alpha[i] = math.min(255, diff[i] * 4);
    kept++;
    final x = i % w, y = i ~/ w;
    x0 = math.min(x0, x);
    x1 = math.max(x1, x);
    y0 = math.min(y0, y);
    y1 = math.max(y1, y);
  }
  if (kept < 30) return null;
  return _crop(rgba, alpha, w, x0, y0, x1, y1);
}

(Uint8List, int, int, int, int) _crop(Uint8List rgba, Uint8List alpha, int w, int x0, int y0, int x1, int y1) {
  final cw = x1 - x0 + 1, ch = y1 - y0 + 1;
  final out = Uint8List(cw * ch * 4);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final src = (y + y0) * w + x + x0, dst = 4 * (y * cw + x);
      out[dst] = rgba[4 * src];
      out[dst + 1] = rgba[4 * src + 1];
      out[dst + 2] = rgba[4 * src + 2];
      out[dst + 3] = alpha[src];
    }
  }
  return (out, x0, y0, cw, ch);
}

/// How much darker than the paper around it each pixel is, with the ink
/// threshold. Grey is the darkest channel, which keeps light coloured pen,
/// unless the paper itself is coloured (green paper is as dark as its ink
/// there): then luminance. A noisy picture (a photo's grain) is blurred
/// first; a clean one is not, as blur merges a coil's loops.
(Uint8List, Uint8List, int, bool) _darkness(Uint8List rgb, int stride, int w, int h) {
  final n = w * h;
  final rs = <int>[], gs = <int>[], bs = <int>[];
  for (var i = 0; i < n; i += 7) {
    rs.add(rgb[stride * i]);
    gs.add(rgb[stride * i + 1]);
    bs.add(rgb[stride * i + 2]);
  }
  int med(List<int> v) => (v..sort())[v.length ~/ 2];
  final pr = med(rs), pg = med(gs), pb = med(bs);
  final tinted = math.max(pr, math.max(pg, pb)) - math.min(pr, math.min(pg, pb)) > 30;
  final gray = Uint8List(n);
  for (var i = 0; i < n; i++) {
    final r = rgb[stride * i], g = rgb[stride * i + 1], b = rgb[stride * i + 2];
    gray[i] = tinted ? (0.299 * r + 0.587 * g + 0.114 * b).round() : math.min(r, math.min(g, b));
  }
  final k = math.max(15, (math.min(w, h) ~/ 25) | 1);
  (Uint8List, int) measure() {
    final paper = _maxFilter(gray, w, h, k);
    final diff = Uint8List(n);
    final hist = List<int>.filled(256, 0);
    for (var i = 0; i < n; i++) {
      diff[i] = paper[i] - gray[i];
      hist[diff[i]]++;
    }
    var median = 0;
    for (var acc = 0; median < 255 && (acc += hist[median]) < n ~/ 2; median++) {}
    return (diff, median);
  }

  var (diff, median) = measure();
  if (median >= 2) {
    _blur3(gray, w, h);
    (diff, median) = measure();
  }
  return (gray, diff, math.max(8, math.min(6 * median, 2 * median + 12)), tinted);
}

/// In-place 3x3 box blur.
void _blur3(Uint8List img, int w, int h) {
  final src = Uint8List.fromList(img);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var sum = 0, n = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx, yy = y + dy;
          if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
          sum += src[yy * w + xx];
          n++;
        }
      }
      img[y * w + x] = sum ~/ n;
    }
  }
}

/// Bilinear resample to [cw] x [ch], composited over white; RGB out.
Uint8List _resample(Uint8List rgba, int w, int h, int cw, int ch) {
  final out = Uint8List(cw * ch * 3);
  final sx = w / cw, sy = h / ch;
  for (var y = 0; y < ch; y++) {
    final fy = ((y + 0.5) * sy - 0.5).clamp(0.0, h - 1.0);
    final y0 = fy.floor(), y1 = math.min(y0 + 1, h - 1), ty = fy - y0;
    for (var x = 0; x < cw; x++) {
      final fx = ((x + 0.5) * sx - 0.5).clamp(0.0, w - 1.0);
      final x0 = fx.floor(), x1 = math.min(x0 + 1, w - 1), tx = fx - x0;
      for (var c = 0; c < 3; c++) {
        double at(int px, int py) {
          final i = 4 * (py * w + px);
          final a = rgba[i + 3] / 255;
          return rgba[i + c] * a + 255 * (1 - a);
        }

        final top = at(x0, y0) * (1 - tx) + at(x1, y0) * tx;
        final bottom = at(x0, y1) * (1 - tx) + at(x1, y1) * tx;
        out[3 * (y * cw + x) + c] = (top * (1 - ty) + bottom * ty).round().clamp(0, 255);
      }
    }
  }
  return out;
}

/// Max over a [k] x [k] window, as two running-max passes.
Uint8List _maxFilter(Uint8List src, int w, int h, int k) {
  final half = k ~/ 2;
  Uint8List pass(Uint8List a, int len, int lines, int Function(int line, int i) at) {
    final out = Uint8List(a.length);
    final q = Int32List(len);
    for (var l = 0; l < lines; l++) {
      var head = 0, tail = 0;
      var next = 0;
      for (var i = 0; i < len; i++) {
        while (next < len && next <= i + half) {
          final v = a[at(l, next)];
          while (tail > head && a[at(l, q[tail - 1])] <= v) {
            tail--;
          }
          q[tail++] = next++;
        }
        while (q[head] < i - half) {
          head++;
        }
        out[at(l, i)] = a[at(l, q[head])];
      }
    }
    return out;
  }

  final rows = pass(src, w, h, (y, x) => y * w + x);
  return pass(rows, h, w, (x, y) => y * w + x);
}

/// A page's or a screenshot's border: rows and columns nearly all ink.
void _dropFrame(Uint8List ink, int w, int h) {
  for (var y = 0; y < h; y++) {
    var c = 0;
    for (var x = 0; x < w; x++) {
      c += ink[y * w + x];
    }
    if (c <= 0.8 * w) continue;
    for (var yy = math.max(0, y - 4); yy <= math.min(h - 1, y + 4); yy++) {
      ink.fillRange(yy * w, yy * w + w, 0);
    }
  }
  for (var x = 0; x < w; x++) {
    var c = 0;
    for (var y = 0; y < h; y++) {
      c += ink[y * w + x];
    }
    if (c <= 0.8 * h) continue;
    for (var xx = math.max(0, x - 4); xx <= math.min(w - 1, x + 4); xx++) {
      for (var y = 0; y < h; y++) {
        ink[y * w + xx] = 0;
      }
    }
  }
}

/// Specks, and long thin lines near the edge (what is left of a frame).
void _dropSpecks(Uint8List ink, int w, int h, {int minArea = 20}) {
  final seen = Uint8List(ink.length);
  final stack = <int>[];
  final short = math.min(w, h);
  for (var start = 0; start < ink.length; start++) {
    if (ink[start] == 0 || seen[start] == 1) continue;
    final comp = <int>[];
    var x0 = w, y0 = h, x1 = 0, y1 = 0;
    seen[start] = 1;
    stack.add(start);
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      comp.add(p);
      final x = p % w, y = p ~/ w;
      x0 = math.min(x0, x);
      x1 = math.max(x1, x);
      y0 = math.min(y0, y);
      y1 = math.max(y1, y);
      for (final (dy, dx) in _nb) {
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final q = ny * w + nx;
        if (ink[q] == 1 && seen[q] == 0) {
          seen[q] = 1;
          stack.add(q);
        }
      }
    }
    final bw = x1 - x0 + 1, bh = y1 - y0 + 1;
    final margin = math.min(math.min(x0, y0), math.min(w - 1 - x1, h - 1 - y1));
    final line = math.max(bw, bh) > 0.2 * short && math.max(bw, bh) > 15 * math.min(bw, bh);
    // A border broken into pieces leaves short dashes hugging the edge.
    final dash = margin < 0.08 * short && math.min(bw, bh) <= 0.005 * short + 2 && math.max(bw, bh) > 4 * math.min(bw, bh);
    if (comp.length < minArea || (margin < 0.1 * short && line) || dash) {
      for (final p in comp) {
        ink[p] = 0;
      }
    }
  }
}

/// Small filled shapes that are not round (arrowheads, not node dots): ink
/// far thicker than the lines ([half] is their half-width), grown back to
/// its edge. Pixel indices per shape.
List<List<int>> _filledHeads(Uint8List ink, Int32List dist, int w, int h, double half) {
  final thick = 3 * math.max(2.0, 1.7 * half);
  final seen = Uint8List(ink.length);
  final out = <List<int>>[];
  for (var start = 0; start < ink.length; start++) {
    if (dist[start] < thick || seen[start] == 1) continue;
    // The thick core, then the ink around it out to the core's own depth.
    final core = <int>[];
    final stack = [start];
    seen[start] = 1;
    var deepest = 0;
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      core.add(p);
      deepest = math.max(deepest, dist[p]);
      for (final (dy, dx) in _nb) {
        final x = p % w + dx, y = p ~/ w + dy;
        if (x < 0 || y < 0 || x >= w || y >= h) continue;
        final q = y * w + x;
        if (seen[q] == 0 && dist[q] >= thick) {
          seen[q] = 1;
          stack.add(q);
        }
      }
    }
    // Grown down the slope of the distance only: it stops where a wire or a
    // bar it touches levels off.
    final region = <int>{...core};
    var front = core;
    while (front.isNotEmpty) {
      final next = <int>[];
      for (final p in front) {
        for (final (dy, dx) in _nb) {
          final x = p % w + dx, y = p ~/ w + dy;
          if (x < 0 || y < 0 || x >= w || y >= h) continue;
          final q = y * w + x;
          if (ink[q] == 1 && dist[q] < dist[p] && region.add(q)) next.add(q);
        }
      }
      front = next;
    }
    // A head's thick core is many pixels; a crossing in bold writing has a
    // few (measured 22-70 against 1-7). A round dot fills its circle.
    var cx = 0.0, cy = 0.0;
    for (final p in region) {
      cx += p % w;
      cy += p ~/ w;
    }
    cx /= region.length;
    cy /= region.length;
    var r2 = 0.0;
    for (final p in region) {
      r2 = math.max(r2, math.pow(p % w - cx, 2) + math.pow(p ~/ w - cy, 2).toDouble());
    }
    if (core.length >= math.max(10, 1.2 * half * half) &&
        region.length < 0.8 * math.pi * r2 &&
        math.sqrt(r2) < 20 * half) {
      out.add(region.toList());
    }
  }
  return out;
}

/// Boundary of the shape in [mask] containing [start] (its first pixel in
/// raster order), Moore-neighbour traced clockwise.
List<int> _outline(Uint8List mask, int w, int h, int start) {
  const dirs = [(-1, 0), (-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1)];
  final out = [start];
  var cur = start, back = 0; // entered from the west
  for (var guard = 0; guard < 4 * mask.length; guard++) {
    int? next;
    var k = back;
    for (var t = 0; t < 8; t++) {
      k = (back + 1 + t) % 8;
      final x = cur % w + dirs[k].$1, y = cur ~/ w + dirs[k].$2;
      if (x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x] == 1) {
        next = y * w + x;
        break;
      }
    }
    if (next == null || next == start) break;
    // Next search starts from the neighbour before the one found.
    back = (k + 4 + 1) % 8;
    cur = next;
    out.add(cur);
  }
  return out;
}

/// Ink running off the picture's edge: the table and the sheet's border in
/// a photo, never a label.
void _dropTouchingEdge(Uint8List ink, int w, int h) {
  final stack = <int>[];
  void seed(int i) {
    if (ink[i] == 1) {
      ink[i] = 0;
      stack.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    seed(x);
    seed((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    seed(y * w);
    seed(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    for (final (dy, dx) in _nb) {
      final x = p % w + dx, y = p ~/ w + dy;
      if (x >= 0 && y >= 0 && x < w && y < h) seed(y * w + x);
    }
  }
}

/// Chamfer (3-4) distance to the nearest paper pixel; 3 per pixel step.
Int32List _distance(Uint8List ink, int w, int h) {
  const big = 1 << 28;
  final d = Int32List(ink.length);
  for (var i = 0; i < ink.length; i++) {
    d[i] = ink[i] == 1 ? big : 0;
  }
  int at(int x, int y) => x < 0 || y < 0 || x >= w || y >= h ? 0 : d[y * w + x];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (d[i] == 0) continue;
      d[i] = math.min(d[i], math.min(math.min(at(x - 1, y) + 3, at(x, y - 1) + 3), math.min(at(x - 1, y - 1) + 4, at(x + 1, y - 1) + 4)));
    }
  }
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final i = y * w + x;
      if (d[i] == 0) continue;
      d[i] = math.min(d[i], math.min(math.min(at(x + 1, y) + 3, at(x, y + 1) + 3), math.min(at(x + 1, y + 1) + 4, at(x - 1, y + 1) + 4)));
    }
  }
  return d;
}

int _px(Uint8List img, int w, int h, int x, int y) => x < 0 || y < 0 || x >= w || y >= h ? 0 : img[y * w + x];

/// Zhang-Suen thinning to a one-pixel skeleton.
Uint8List _thin(Uint8List ink, int w, int h) {
  final img = Uint8List.fromList(ink);
  var live = [for (var i = 0; i < img.length; i++) if (img[i] == 1) i];
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
    live = [for (final i in live) if (img[i] == 1) i];
  }
  return img;
}

/// Connected groups among the set positions of a 3x3 ring (neighbour order).
int _groups(List<int> ring) {
  final on = [for (var k = 0; k < 8; k++) if (ring[k] == 1) k];
  final seen = <int>{};
  var n = 0;
  for (final k in on) {
    if (seen.contains(k)) continue;
    n++;
    final stack = [k];
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      if (!seen.add(i)) continue;
      for (final j in on) {
        final d = (i - j) % 8;
        if (!seen.contains(j) && (d == 1 || d == 7 || ((d == 2 || d == 6) && i.isEven && j.isEven))) stack.add(j);
      }
    }
  }
  return n;
}

/// Drops skeleton pixels whose removal keeps their neighbours connected
/// (staircase corners), so plain runs have exactly two neighbours.
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

/// Skeleton -> pixel paths (indices), split at junctions; short spurs off a
/// junction (thinning artefacts) are dropped.
List<List<int>> _trace(Uint8List sk, int w, int h, {int minSpur = 6}) {
  List<int> nbrs(int p) {
    final x = p % w, y = p ~/ w;
    return [
      for (final (dy, dx) in _nb)
        if (_px(sk, w, h, x + dx, y + dy) == 1) (y + dy) * w + x + dx
    ];
  }

  final deg = <int, int>{};
  for (var i = 0; i < sk.length; i++) {
    if (sk[i] == 1) deg[i] = nbrs(i).length;
  }
  final nodes = {for (final e in deg.entries) if (e.value != 2) e.key};
  final used = <int>{};
  final n = sk.length;
  int edge(int a, int b) => a * n + b;
  final paths = <List<int>>[];
  for (final s in nodes) {
    for (final q in nbrs(s)) {
      if (used.contains(edge(s, q))) continue;
      final path = [s, q];
      used
        ..add(edge(s, q))
        ..add(edge(q, s));
      var prev = s, cur = q;
      while (!nodes.contains(cur)) {
        final next = nbrs(cur).where((r) => r != prev && !used.contains(edge(cur, r))).toList();
        if (next.isEmpty) break;
        used
          ..add(edge(cur, next.first))
          ..add(edge(next.first, cur));
        prev = cur;
        cur = next.first;
        path.add(cur);
      }
      paths.add(path);
    }
  }
  // Closed loops with no junction (a ring drawn on its own).
  final seen = {for (final p in paths) ...p};
  for (final p in deg.keys) {
    if (seen.contains(p) || deg[p] != 2) continue;
    final path = [p];
    int? prev;
    var cur = p;
    while (true) {
      final tail = path.length > 3 ? path.sublist(path.length - 3) : path;
      final next = nbrs(cur).where((r) => r != prev && !tail.contains(r)).toList();
      if (next.isEmpty || seen.contains(next.first)) break;
      prev = cur;
      cur = next.first;
      seen.add(cur);
      path.add(cur);
    }
    seen.add(p);
    if (path.length > 4) paths.add([...path, p]);
  }
  return [
    for (final path in paths)
      if (!(path.length < minSpur && (deg[path.first] == 1 || deg[path.last] == 1))) path
  ];
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
