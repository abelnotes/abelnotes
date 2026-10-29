import 'dart:math';
import 'dart:ui';

import 'package:abelnotes/shared/models/ncnote_format.dart';

// Freehand-to-figure recognition. The stroke is resampled, then every closed
// candidate is FITTED (3/4-gon by edge line fits, oval by least squares) and
// the one whose edges/outline the stroke follows best wins. Nothing here
// depends on where the pen started, which way it went, or point density.

/// Samples per resampled stroke (uniform in arc length).
const _resampleN = 96;

/// ~9 deg: a tilt this small reads as "meant to be upright" and is snapped.
const _tiltSnap = 0.157;

/// Largest start-to-end gap, as a share of the stroke length, still read as a
/// closed figure (a 315-degree arc of a circle is the limit).
const _maxGapOfLength = 0.15;

/// A polygon fit is only believed if the stroke encloses about its area: a
/// "D" or other bulging figure fits straight edges but encloses much less.
bool _roundish(_PolyFit f) => f.area > 0.9 && f.area < 1.1;

/// Axis ratio (minor/major) from which an oval is snapped to a true circle.
const _circleRatio = 0.85;

/// Fill of a closed shape: a ~19% tint of its ink. Recolouring reuses it.
int shapeFillTint(int ink) => (ink & 0x00FFFFFF) | (0x30 << 24);

ShapeData? recognizeShape(
  List<StrokePoint> points, {
  required int color,
  required double strokeWidth,
  bool isHighlighter = false,
  bool fill = false,
}) {
  if (points.length < 5) return null;
  final pts = _dedupe(points);
  if (pts.length < 5) return null;

  var minX = double.infinity, maxX = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  for (final p in pts) {
    minX = min(minX, p.dx);
    maxX = max(maxX, p.dx);
    minY = min(minY, p.dy);
    maxY = max(maxY, p.dy);
  }
  final size = max(maxX - minX, maxY - minY);
  if (size < 10) return null;

  ShapeData make(String type, double x1, double y1, double x2, double y2,
          {double rotation = 0, List<double> vertices = const []}) =>
      ShapeData(
        shapeType: type,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        rotation: rotation,
        vertices: vertices,
        strokeColor: color,
        strokeWidth: strokeWidth,
        isHighlighter: isHighlighter,
        fillColor: fill && type != 'line' ? shapeFillTint(color) : null,
      );

  final len = _pathLen(pts);
  final line = _asLine(pts, len, maxX - minX, maxY - minY);
  if (line != null) {
    return make('line', line[0], line[1], line[2], line[3]);
  }

  if ((pts.last - pts.first).distance > _maxGapOfLength * len) return null;

  final q = _resample(_trimOverlap(pts, size, len), _resampleN);
  final sets = _vertexSets(q);
  final tol = 0.03 * size + 0.3; // edge straightness tolerance, px

  _PolyFit? tri, quad;
  if (sets[3] != null) {
    final f = _fitPolygon(q, sets[3]!);
    if (f.err <= tol && _roundish(f) && _validTriangle(f.v, size)) tri = f;
  }
  if (sets[4] != null) {
    final f = _fitPolygon(q, sets[4]!);
    if (f.err <= tol && _roundish(f) && _validQuad(f.v, size)) quad = f;
  }
  final poly = (tri != null && (quad == null || tri.err <= 1.2 * quad.err))
      ? tri
      : quad;

  var oval = _fitEllipse(q, size);
  if (oval != null && (oval.err > 0.035 * size + 0.3 || oval.b / oval.a < 0.55)) {
    oval = null;
  }

  // A figure whose edges are straight is a polygon even if an oval also fits
  // roughly; the oval only wins when it is clearly the better description.
  if (poly != null && (oval == null || poly.err < 0.7 * oval.err)) {
    final end = pts.last;
    if (poly == tri) return _triangle(poly.v, size, make);
    return _quad(poly.v, end, make);
  }
  if (oval != null) return _oval(oval, make);
  return null;
}

typedef _Make = ShapeData Function(
    String type, double x1, double y1, double x2, double y2,
    {double rotation, List<double> vertices});

// ── output builders ──────────────────────────────────────────────

ShapeData _oval(_OvalFit o, _Make make) {
  if (o.b / o.a >= _circleRatio) {
    final r = (o.a + o.b) / 2;
    return make('circle', o.c.dx - r, o.c.dy - r, o.c.dx + r, o.c.dy + r);
  }
  var rho = _wrapHalfPi(o.phi);
  var w = o.a, h = o.b;
  if (rho > pi / 4) {
    rho -= pi / 2;
    w = o.b;
    h = o.a;
  } else if (rho <= -pi / 4) {
    rho += pi / 2;
    w = o.b;
    h = o.a;
  }
  if (rho.abs() < _tiltSnap) rho = 0;
  return make('circle', o.c.dx - w, o.c.dy - h, o.c.dx + w, o.c.dy + h,
      rotation: rho);
}

ShapeData _quad(List<Offset> v, Offset end, _Make make) {
  final c = (v[0] + v[1] + v[2] + v[3]) / 4;
  final d1 = v[2] - v[0], d2 = v[3] - v[1];
  final l1 = d1.distance, l2 = d2.distance;
  // Rectangle: equal diagonals. Rhombus: perpendicular diagonals. Square: both.
  final rs = (l1 - l2).abs() / max(l1, l2);
  final cosd = (d1.dx * d2.dx + d1.dy * d2.dy).abs() / (l1 * l2);
  final isSquare = rs <= 0.15 && cosd <= 0.2;
  final isRect = isSquare || rs < cosd;

  if (isRect) {
    final sa = (v[1] - v[0]) - (v[3] - v[2]);
    final sb = (v[2] - v[1]) - (v[0] - v[3]);
    // Side direction: mean of both opposite-side pairs, modulo 90 deg.
    final aa = atan2(sa.dy, sa.dx), ab = atan2(sb.dy, sb.dx);
    var th = _wrapQuarter(0.25 *
        atan2(sin(4 * aa) + sin(4 * ab), cos(4 * aa) + cos(4 * ab)));
    if (th.abs() < _tiltSnap) th = 0;
    if (isSquare && (th.abs() > pi / 4 - _tiltSnap)) {
      // A square standing on its corner is a diamond: snap it upright.
      final d = (l1 + l2) / 2;
      return make('rhombus', c.dx - d / 2, c.dy - d / 2, c.dx + d / 2,
          c.dy + d / 2);
    }
    final e1 = Offset(cos(th), sin(th)), e2 = Offset(-sin(th), cos(th));
    double lo1 = double.infinity, hi1 = -double.infinity;
    double lo2 = double.infinity, hi2 = -double.infinity;
    for (final p in v) {
      final a = (p - c).dx * e1.dx + (p - c).dy * e1.dy;
      final b = (p - c).dx * e2.dx + (p - c).dy * e2.dy;
      lo1 = min(lo1, a);
      hi1 = max(hi1, a);
      lo2 = min(lo2, b);
      hi2 = max(hi2, b);
    }
    final cx = c.dx + e1.dx * (lo1 + hi1) / 2 + e2.dx * (lo2 + hi2) / 2;
    final cy = c.dy + e1.dy * (lo1 + hi1) / 2 + e2.dy * (lo2 + hi2) / 2;
    final hw = (hi1 - lo1) / 2, hh = (hi2 - lo2) / 2;
    // The pen-end corner becomes (x2,y2): hold-to-resize drags that corner.
    final rel = end - Offset(cx, cy);
    final ex = rel.dx * e1.dx + rel.dy * e1.dy;
    final ey = rel.dx * e2.dx + rel.dy * e2.dy;
    final sx = ex >= 0 ? 1.0 : -1.0, sy = ey >= 0 ? 1.0 : -1.0;
    return make('rectangle', cx - sx * hw, cy - sy * hh, cx + sx * hw,
        cy + sy * hh,
        rotation: th);
  }

  // Rhombus: bbox is the two diagonals, rotated to the long diagonal.
  final a1 = atan2(d1.dy, d1.dx), a2 = atan2(d2.dy, d2.dx);
  var rho = _wrapHalfPi(0.5 *
      atan2(sin(2 * a1) + sin(2 * (a2 - pi / 2)),
          cos(2 * a1) + cos(2 * (a2 - pi / 2))));
  final d1AlongE1 = cos(2 * (a1 - rho)) > 0;
  var w = d1AlongE1 ? l1 : l2, h = d1AlongE1 ? l2 : l1;
  if (rho > pi / 4) {
    rho -= pi / 2;
    final t = w;
    w = h;
    h = t;
  } else if (rho <= -pi / 4) {
    rho += pi / 2;
    final t = w;
    w = h;
    h = t;
  }
  if (rho.abs() < _tiltSnap) rho = 0;
  return make('rhombus', c.dx - w / 2, c.dy - h / 2, c.dx + w / 2,
      c.dy + h / 2,
      rotation: rho);
}

ShapeData _triangle(List<Offset> v, double size, _Make make) {
  final centroid = (v[0] + v[1] + v[2]) / 3;
  // Apex = vertex between the two most equal edges (the tip of an isosceles).
  var apexIdx = 0;
  var bestBalance = double.infinity;
  for (var i = 0; i < 3; i++) {
    final e1 = (v[i] - v[(i + 2) % 3]).distance;
    final e2 = (v[i] - v[(i + 1) % 3]).distance;
    final balance = (e1 - e2).abs() / (e1 + e2);
    if (balance < bestBalance) {
      bestBalance = balance;
      apexIdx = i;
    }
  }
  var tri = [v[apexIdx], v[(apexIdx + 1) % 3], v[(apexIdx + 2) % 3]];
  var rotation = _wrapTwoPi(
      atan2(tri[0].dy - centroid.dy, tri[0].dx - centroid.dx) + pi / 2);
  final quarter = (rotation / (pi / 2)).round();
  final snapped = quarter * (pi / 2);
  if ((rotation - snapped).abs() <= _tiltSnap) {
    final da = snapped - rotation;
    tri = [for (final p in tri) _rotAbout(p, centroid, da)];
    rotation = _wrapTwoPi(snapped);
  }

  var minX = double.infinity, maxX = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  for (final p in tri) {
    minX = min(minX, p.dx);
    maxX = max(maxX, p.dx);
    minY = min(minY, p.dy);
    maxY = max(maxY, p.dy);
  }
  // Upright isosceles inside its bbox: store just the bbox + apex direction.
  final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
  final q = ((rotation / (pi / 2)).round()) % 4;
  final canon = switch (q) {
    0 => [Offset(cx, minY), Offset(minX, maxY), Offset(maxX, maxY)],
    1 => [Offset(maxX, cy), Offset(minX, minY), Offset(minX, maxY)],
    2 => [Offset(cx, maxY), Offset(maxX, minY), Offset(minX, minY)],
    _ => [Offset(minX, cy), Offset(maxX, maxY), Offset(maxX, minY)],
  };
  final isCardinal = (rotation - q * (pi / 2)).abs() < 1e-6 ||
      (rotation - 2 * pi).abs() < 1e-6;
  if (isCardinal && _maxMatchDist(tri, canon) <= 0.1 * size) {
    return make('triangle', minX, minY, maxX, maxY, rotation: rotation);
  }
  return make('triangle', minX, minY, maxX, maxY,
      rotation: rotation,
      vertices: [for (final p in tri) ...[p.dx, p.dy]]);
}

double _maxMatchDist(List<Offset> a, List<Offset> b) {
  var best = double.infinity;
  for (final perm in const [
    [0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]
  ]) {
    var m = 0.0;
    for (var i = 0; i < 3; i++) {
      m = max(m, (a[i] - b[perm[i]]).distance);
    }
    best = min(best, m);
  }
  return best;
}

// ── validity ─────────────────────────────────────────────────────

List<double> _interiorAngles(List<Offset> v) {
  final n = v.length;
  return [
    for (var i = 0; i < n; i++)
      () {
        final a = v[(i + n - 1) % n] - v[i], b = v[(i + 1) % n] - v[i];
        final c = (a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance);
        return acos(c.clamp(-1.0, 1.0));
      }()
  ];
}

bool _isConvex(List<Offset> v) {
  final n = v.length;
  var pos = 0, neg = 0;
  for (var i = 0; i < n; i++) {
    final a = v[(i + 1) % n] - v[i], b = v[(i + 2) % n] - v[(i + 1) % n];
    (a.dx * b.dy - a.dy * b.dx) > 0 ? pos++ : neg++;
  }
  return pos == 0 || neg == 0;
}

double _minSide(List<Offset> v) {
  var m = double.infinity;
  for (var i = 0; i < v.length; i++) {
    m = min(m, (v[i] - v[(i + 1) % v.length]).distance);
  }
  return m;
}

/// Three corners with no sliver angle and no collapsed side.
bool _validTriangle(List<Offset> v, double size) {
  if (!_isConvex(v) || _minSide(v) < 0.12 * size) return false;
  return _interiorAngles(v).every((a) => a > 0.2 && a < 2.8); // 12..160 deg
}

/// Four real corners (a ~180 deg one is a stray vertex on a straight edge)
/// forming roughly a parallelogram; trapezoids and kites stay freehand.
bool _validQuad(List<Offset> v, double size) {
  if (!_isConvex(v) || _minSide(v) < 0.1 * size) return false;
  if (!_interiorAngles(v).every((a) => a > 0.7 && a < 2.45)) return false; // 40..140 deg
  final d1 = v[2] - v[0], d2 = v[3] - v[1];
  final mid = ((v[0] + v[2]) - (v[1] + v[3])).distance / 2;
  if (mid > 0.2 * max(d1.distance, d2.distance)) return false;
  final rs = (d1.distance - d2.distance).abs() / max(d1.distance, d2.distance);
  final cosd = (d1.dx * d2.dx + d1.dy * d2.dy).abs() / (d1.distance * d2.distance);
  return min(rs, cosd) <= 0.35; // neither rectangle- nor rhombus-like: skip
}

// ── fitting ──────────────────────────────────────────────────────

class _PolyFit {
  _PolyFit(this.v, this.err, this.area);
  final List<Offset> v;
  final double err;
  final double area; // area enclosed by the stroke / area of the polygon
}

class _OvalFit {
  _OvalFit(this.c, this.a, this.b, this.phi, this.err);
  final Offset c;
  final double a, b; // semi-axes, a >= b
  final double phi; // direction of the a axis
  final double err;
}

/// Vertex index sets (3..6 vertices) of the closed curve [q]: greedy
/// Douglas-Peucker splitting up to 10 vertices, then drop the least useful
/// one at a time, so a stray vertex at the pen start is shed like any other.
Map<int, List<int>> _vertexSets(List<Offset> q) {
  final n = q.length;
  var far = 0;
  var fd = 0.0;
  for (var i = 1; i < n; i++) {
    final d = (q[i] - q[0]).distance;
    if (d > fd) {
      fd = d;
      far = i;
    }
  }
  if (far == 0) return {};
  final v = <int>[0, far];
  while (v.length < 10) {
    var bestDev = 1e-6, bestI = -1;
    for (var j = 0; j < v.length; j++) {
      final a = v[j], b = v[(j + 1) % v.length];
      for (var i = (a + 1) % n; i != b; i = (i + 1) % n) {
        final d = _segDist(q[i], q[a], q[b]);
        if (d > bestDev) {
          bestDev = d;
          bestI = i;
        }
      }
    }
    if (bestI < 0) break;
    v
      ..add(bestI)
      ..sort();
  }
  final out = <int, List<int>>{};
  var cur = List<int>.of(v);
  while (cur.length >= 3) {
    if (cur.length <= 6) out[cur.length] = List<int>.of(cur);
    if (cur.length == 3) break;
    var bestJ = 0;
    var bestC = double.infinity;
    for (var j = 0; j < cur.length; j++) {
      final cand = [
        for (var i = 0; i < cur.length; i++)
          if (i != j) q[cur[i]]
      ];
      final c = _closedPolySumSq(q, cand);
      if (c < bestC) {
        bestC = c;
        bestJ = j;
      }
    }
    cur.removeAt(bestJ);
  }
  return out;
}

double _closedPolySumSq(List<Offset> q, List<Offset> v) {
  var s = 0.0;
  for (final p in q) {
    var best = double.infinity;
    for (var i = 0; i < v.length; i++) {
      best = min(best, _segDist(p, v[i], v[(i + 1) % v.length]));
    }
    s += best * best;
  }
  return s;
}

/// Replaces each DP vertex by the intersection of the two straight lines fitted
/// to the middle 60 % of its adjacent edges (corner rounding does not bias
/// them), and scores the fit on those middle parts only, so the score
/// measures edge STRAIGHTNESS and not how sharp the corners were drawn.
_PolyFit _fitPolygon(List<Offset> q, List<int> idx) {
  final n = q.length, m = idx.length;
  final inner = <List<Offset>>[];
  final lines = <({Offset c, Offset d})?>[];
  for (var j = 0; j < m; j++) {
    final a = idx[j], b = idx[(j + 1) % m];
    final arc = <Offset>[];
    for (var i = a;; i = (i + 1) % n) {
      arc.add(q[i]);
      if (i == b) break;
    }
    final lo = (arc.length * 0.2).floor(), hi = (arc.length * 0.8).ceil();
    final mid = arc.sublist(lo, max(hi, lo + 1));
    inner.add(mid);
    lines.add(mid.length >= 3 ? _tlsLine(mid) : null);
  }
  final v = <Offset>[];
  for (var j = 0; j < m; j++) {
    final l1 = lines[(j + m - 1) % m], l2 = lines[j];
    final orig = q[idx[j]];
    Offset? x;
    if (l1 != null && l2 != null) x = _intersect(l1, l2);
    v.add(x ?? orig);
  }
  final errs = <double>[];
  for (var j = 0; j < m; j++) {
    for (final p in inner[j]) {
      errs.add(_segDist(p, v[j], v[(j + 1) % m]));
    }
  }
  return _PolyFit(v, _trimmedRms(errs), _area(q) / _area(v));
}

double _area(List<Offset> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final b = p[(i + 1) % p.length];
    a += p[i].dx * b.dy - b.dx * p[i].dy;
  }
  return a.abs() / 2;
}

Offset? _intersect(({Offset c, Offset d}) a, ({Offset c, Offset d}) b) {
  final cross = a.d.dx * b.d.dy - a.d.dy * b.d.dx;
  if (cross.abs() < 0.15) return null; // under ~9 deg: ill-conditioned
  final w = b.c - a.c;
  final t = (w.dx * b.d.dy - w.dy * b.d.dx) / cross;
  return a.c + a.d * t;
}

({Offset c, Offset d}) _tlsLine(List<Offset> p) {
  final c = p.reduce((a, b) => a + b) / p.length.toDouble();
  var sxx = 0.0, syy = 0.0, sxy = 0.0;
  for (final o in p) {
    final dx = o.dx - c.dx, dy = o.dy - c.dy;
    sxx += dx * dx;
    syy += dy * dy;
    sxy += dx * dy;
  }
  final a = 0.5 * atan2(2 * sxy, sxx - syy);
  return (c: c, d: Offset(cos(a), sin(a)));
}

/// Least-squares ellipse in the frame of the point cloud's principal axes:
/// A x^2 + B y^2 + C x + D y = 1.
_OvalFit? _fitEllipse(List<Offset> q, double size) {
  final c0 = q.reduce((a, b) => a + b) / q.length.toDouble();
  var sxx = 0.0, syy = 0.0, sxy = 0.0;
  for (final p in q) {
    final dx = p.dx - c0.dx, dy = p.dy - c0.dy;
    sxx += dx * dx;
    syy += dy * dy;
    sxy += dx * dy;
  }
  final phi = 0.5 * atan2(2 * sxy, sxx - syy);
  final cp = cos(phi), sp = sin(phi);
  final u = [
    for (final p in q)
      Offset(((p.dx - c0.dx) * cp + (p.dy - c0.dy) * sp) / size,
          (-(p.dx - c0.dx) * sp + (p.dy - c0.dy) * cp) / size)
  ];
  final m = List.generate(4, (_) => List<double>.filled(5, 0));
  for (final p in u) {
    final r = [p.dx * p.dx, p.dy * p.dy, p.dx, p.dy];
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        m[i][j] += r[i] * r[j];
      }
      m[i][4] += r[i];
    }
  }
  final s = _solve(m);
  if (s == null) return null;
  final aa = s[0], bb = s[1], cc = s[2], dd = s[3];
  if (aa <= 0 || bb <= 0) return null;
  final k = 1 + cc * cc / (4 * aa) + dd * dd / (4 * bb);
  if (k <= 0) return null;
  var a = sqrt(k / aa), b = sqrt(k / bb);
  final ux = -cc / (2 * aa), uy = -dd / (2 * bb);
  final errs = <double>[];
  for (final p in u) {
    final x = p.dx - ux, y = p.dy - uy;
    final f = x * x / (a * a) + y * y / (b * b) - 1;
    final g = 2 * sqrt(x * x / pow(a, 4) + y * y / pow(b, 4));
    errs.add(g == 0 ? 0 : f.abs() / g * size);
  }
  var ang = phi;
  if (b > a) {
    final t = a;
    a = b;
    b = t;
    ang += pi / 2;
  }
  final centre = c0 + Offset(ux * size * cp - uy * size * sp,
      ux * size * sp + uy * size * cp);
  if (![centre.dx, centre.dy, a, b].every((e) => e.isFinite)) return null;
  return _OvalFit(centre, a * size, b * size, ang, _trimmedRms(errs));
}

List<double>? _solve(List<List<double>> m) {
  final n = m.length;
  for (var i = 0; i < n; i++) {
    var p = i;
    for (var r = i + 1; r < n; r++) {
      if (m[r][i].abs() > m[p][i].abs()) p = r;
    }
    if (m[p][i].abs() < 1e-12) return null;
    final t = m[i];
    m[i] = m[p];
    m[p] = t;
    for (var r = 0; r < n; r++) {
      if (r == i) continue;
      final f = m[r][i] / m[i][i];
      for (var c = i; c <= n; c++) {
        m[r][c] -= f * m[i][c];
      }
    }
  }
  return [for (var i = 0; i < n; i++) m[i][n] / m[i][i]];
}

/// RMS of the best 92 % (hooks and pen-lift flicks do not count).
double _trimmedRms(List<double> e) {
  if (e.isEmpty) return double.infinity;
  final s = List<double>.of(e)..sort();
  final keep = max(1, (s.length * 0.92).floor());
  var sum = 0.0;
  for (var i = 0; i < keep; i++) {
    sum += s[i] * s[i];
  }
  return sqrt(sum / keep);
}

// ── stroke preparation ───────────────────────────────────────────

List<Offset> _dedupe(List<StrokePoint> pts) {
  final out = <Offset>[];
  for (final p in pts) {
    if (!p.x.isFinite || !p.y.isFinite) continue;
    final o = Offset(p.x, p.y);
    if (out.isEmpty || (o - out.last).distance > 0.05) out.add(o);
  }
  return out;
}

double _pathLen(List<Offset> p) {
  var l = 0.0;
  for (var i = 1; i < p.length; i++) {
    l += (p[i] - p[i - 1]).distance;
  }
  return l;
}

/// A single straight stroke: [x1,y1,x2,y2] with the end snapped to 15 deg
/// steps, or null. Straightness = max distance from the best-fit line.
List<double>? _asLine(List<Offset> pts, double len, double w, double h) {
  final chord = (pts.last - pts.first).distance;
  if (chord < 12 || chord < 0.9 * sqrt(w * w + h * h) || len > 1.3 * chord) {
    return null;
  }
  final fit = _tlsLine(pts);
  var dev = 0.0;
  for (final p in pts) {
    final r = p - fit.c;
    dev = max(dev, (r.dx * fit.d.dy - r.dy * fit.d.dx).abs());
  }
  if (dev > 0.08 * chord) return null;
  Offset proj(Offset p) {
    final r = p - fit.c;
    return fit.c + fit.d * (r.dx * fit.d.dx + r.dy * fit.d.dy);
  }

  final a = proj(pts.first), b = proj(pts.last);
  final e = snapLineEnd(a.dx, a.dy, b.dx, b.dy);
  return [a.dx, a.dy, e[0], e[1]];
}

/// Drops the tail that retraces the start (closing overshoot), so the
/// overlap does not read as an extra corner.
List<Offset> _trimOverlap(List<Offset> p, double size, double len) {
  final head = <Offset>[p.first];
  var c = 0.0;
  for (var i = 1; i < p.length && c < 0.3 * len; i++) {
    c += (p[i] - p[i - 1]).distance;
    head.add(p[i]);
  }
  final tol = 0.02 * size + 0.5;
  var end = p.length;
  var cum = len;
  while (end > 8 && cum >= 0.8 * len) {
    var d = double.infinity;
    for (var i = 0; i + 1 < head.length; i++) {
      d = min(d, _segDist(p[end - 1], head[i], head[i + 1]));
    }
    if (d > tol) break;
    cum -= (p[end - 1] - p[end - 2]).distance;
    end--;
  }
  return p.sublist(0, end);
}

List<Offset> _resample(List<Offset> p, int n) {
  final cum = <double>[0];
  for (var i = 1; i < p.length; i++) {
    cum.add(cum.last + (p[i] - p[i - 1]).distance);
  }
  final total = cum.last;
  final out = <Offset>[];
  var j = 0;
  for (var i = 0; i < n; i++) {
    final s = total * i / (n - 1);
    while (j < p.length - 2 && cum[j + 1] < s) {
      j++;
    }
    final seg = cum[j + 1] - cum[j];
    out.add(seg <= 0 ? p[j] : Offset.lerp(p[j], p[j + 1], ((s - cum[j]) / seg).clamp(0.0, 1.0))!);
  }
  return out;
}

// ── small math ───────────────────────────────────────────────────

double _segDist(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (l2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

Offset _rotAbout(Offset p, Offset c, double a) {
  final d = p - c;
  return c + Offset(d.dx * cos(a) - d.dy * sin(a), d.dx * sin(a) + d.dy * cos(a));
}

/// Folds an angle into (-pi/2, pi/2].
double _wrapHalfPi(double a) {
  var r = a % pi;
  if (r > pi / 2) r -= pi;
  if (r <= -pi / 2) r += pi;
  return r;
}

/// Folds an angle into (-pi/4, pi/4] (symmetry of a rectangle).
double _wrapQuarter(double a) {
  var r = a % (pi / 2);
  if (r > pi / 4) r -= pi / 2;
  return r;
}

double _wrapTwoPi(double a) {
  var r = a % (2 * pi);
  if (r < 0) r += 2 * pi;
  return r;
}

// ── MATHEMATICAL HELPERS ──

/// Snap line end to nearest common angle if within threshold.
/// Snaps to multiples of 15° (0°, 15°, 30°, 45°, 60°, 75°, 90°, …).
/// Returns [snappedX2, snappedY2].
List<double> snapLineEnd(double x1, double y1, double x2, double y2) {
  final dx = x2 - x1;
  final dy = y2 - y1;
  final lineLen = sqrt(dx * dx + dy * dy);
  if (lineLen < 5) return [x2, y2];

  final angle = atan2(dy, dx); // radians
  // Snap to multiples of 15° (π/12)
  const snapStep = pi / 12; // 15 degrees
  const snapThreshold = 0.065; // ~3.7 degrees in radians

  final nearest = (angle / snapStep).round() * snapStep;
  if ((angle - nearest).abs() < snapThreshold) {
    return [x1 + lineLen * cos(nearest), y1 + lineLen * sin(nearest)];
  }
  return [x2, y2];
}
