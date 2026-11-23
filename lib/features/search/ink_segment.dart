import 'dart:math' as math;

import 'package:abelnotes/features/search/ink_text.dart' show InkSegment;
import 'package:abelnotes/shared/models/ncnote_format.dart';

// Line segmentation (rationale in lib/features/search/README.md).

const _glueEps = 1.0; // pt: end points this close continue the same pen line
const _glueFar = 2.5; // pt: farther ends glue only when pointing at each other
const _markH = 0.4; // units lower than this x the typical height are marks
const _joinOv = 0.5; // vertical overlap / smaller height to join a line
const _maxRatio = 4.0; // height ratio past which a unit does not join a band
const _kLocal = 6; // units used for a local band
const _spanMax = 4.6; // a line spans at most this many core bands

typedef _Box = ({double x0, double y0, double x1, double y1});

class _Uf {
  final List<int> p;
  _Uf(int n) : p = List<int>.generate(n, (i) => i);
  int find(int a) {
    while (p[a] != a) {
      p[a] = p[p[a]];
      a = p[a];
    }
    return a;
  }

  void union(int a, int b) {
    a = find(a);
    b = find(b);
    if (a != b) p[math.max(a, b)] = math.min(a, b);
  }
}

class _Line {
  final List<int> units;
  final List<int> marks = [];
  double x1 = 0, t = 0, b = 0, lh = 6;
  _Line(int k) : units = [k];
}

double _med(Iterable<double> v) {
  final s = v.toList()..sort();
  return s[s.length ~/ 2];
}

/// Stable sort by [key] (Python's sorted), ties keep list order.
List<int> _sortedBy(List<int> v, double Function(int) key) {
  final idx = List<int>.generate(v.length, (i) => i)
    ..sort((a, b) {
      final d = key(v[a]).compareTo(key(v[b]));
      return d != 0 ? d : a.compareTo(b);
    });
  return [for (final i in idx) v[i]];
}

/// (x, y, outward unit direction) at both ends of a stroke.
List<(double, double, double, double)> _ends(List<StrokePoint> p) {
  final out = <(double, double, double, double)>[];
  for (final (e, step) in [(0, 1), (p.length - 1, -1)]) {
    final x = p[e].x, y = p[e].y;
    var j = e;
    var dx = 0.0, dy = 0.0;
    while (j + step >= 0 && j + step < p.length && dx * dx + dy * dy < 4.0) {
      j += step;
      dx = x - p[j].x;
      dy = y - p[j].y;
    }
    final d = math.sqrt(dx * dx + dy * dy);
    out.add((x, y, d > 0 ? dx / d : 0.0, d > 0 ? dy / d : 0.0));
  }
  return out;
}

/// Units = strokes that continue each other (touching ends, or close ends
/// pointing at each other: a pen line cut with a small gap).
List<List<int>> _glue(List<StrokeData> strokes) {
  final uf = _Uf(strokes.length);
  final grid = <(int, int), List<(int, double, double, double, double)>>{};
  for (var i = 0; i < strokes.length; i++) {
    for (final (x, y, ux, uy) in _ends(strokes[i].points)) {
      final gx = (x / _glueFar).floor(), gy = (y / _glueFar).floor();
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          for (final (j, jx, jy, vx, vy) in grid[(gx + dx, gy + dy)] ??
              const <(int, double, double, double, double)>[]) {
            if (j == i) continue;
            final d2 = (jx - x) * (jx - x) + (jy - y) * (jy - y);
            if (d2 <= _glueEps * _glueEps) {
              uf.union(i, j);
            } else if (d2 <= _glueFar * _glueFar && ux * vx + uy * vy < -0.7) {
              if (((jx - x) * ux + (jy - y) * uy) / math.sqrt(d2) > 0.7) {
                uf.union(i, j);
              }
            }
          }
        }
      }
      (grid[(gx, gy)] ??= []).add((i, x, y, ux, uy));
    }
  }
  final units = <int, List<int>>{};
  for (var i = 0; i < strokes.length; i++) {
    (units[uf.find(i)] ??= []).add(i);
  }
  return units.values.toList()..sort((a, b) => a.first.compareTo(b.first));
}

(double, double) _band(List<int> us, List<_Box> ub) {
  if (us.length < 3) {
    return (
      us.map((k) => ub[k].y0).reduce(math.min),
      us.map((k) => ub[k].y1).reduce(math.max)
    );
  }
  return (_med(us.map((k) => ub[k].y0)), _med(us.map((k) => ub[k].y1)));
}

(double, double) _localBand(_Line l, List<_Box> ub, double cx) {
  var us = l.units;
  if (us.length > _kLocal) {
    us = _sortedBy(us, (k) => ((ub[k].x0 + ub[k].x1) / 2 - cx).abs())
        .sublist(0, _kLocal);
  }
  return _band(us, ub);
}

(double, double) _rightBand(_Line l, List<_Box> ub) {
  var us = l.units;
  if (us.length > _kLocal) {
    us = _sortedBy(us, (k) => -ub[k].x1).sublist(0, _kLocal);
  }
  return _band(us, ub);
}

List<_Line> _groupLines(List<_Box> ub) {
  final n = ub.length;
  final hs = [for (final b in ub) b.y1 - b.y0];
  final tall = [
    for (final h in hs)
      if (h > 1.0) h
  ];
  final typ = math.max(tall.isEmpty ? 6.0 : _med(tall), 2.0);
  final core = [
    for (var k = 0; k < n; k++)
      if (hs[k] >= _markH * typ) k
  ];
  final marks = [
    for (var k = 0; k < n; k++)
      if (hs[k] < _markH * typ) k
  ];
  final lines = <_Line>[];
  final order = List<int>.of(core)
    ..sort((a, b) {
      final d = ub[a].x0.compareTo(ub[b].x0);
      if (d != 0) return d;
      final e = ub[a].y0.compareTo(ub[b].y0);
      return e != 0 ? e : a.compareTo(b);
    });
  for (final k in order) {
    final u = ub[k];
    final h = math.max(u.y1 - u.y0, 1.0);
    _Line? best;
    (double, double)? bk;
    for (final l in lines) {
      final gap = u.x0 - l.x1;
      if (gap > math.max(1.5 * l.lh, 18)) continue;
      final (t, b) = _rightBand(l, ub);
      final bh = math.max(b - t, 1.0);
      if (math.max(h, bh) > _maxRatio * math.min(h, bh)) continue;
      final r = (math.min(u.y1, b) - math.max(u.y0, t)) / math.min(h, bh);
      // A descender (top in the band's upper part, bottom below it) or an
      // ascender (bottom near the band's bottom, top above it) joins too.
      final desc = t - 0.2 * bh <= u.y0 && u.y0 <= t + 0.6 * bh && u.y1 > b;
      final asc = b - 0.6 * bh <= u.y1 && u.y1 <= b + 0.2 * bh && u.y0 < t;
      if (r < _joinOv && !desc && !asc) continue;
      final key = (-math.min(math.max(r, 0.0), 1.0), math.max(gap, 0.0));
      if (bk == null || key.$1 < bk.$1 || (key.$1 == bk.$1 && key.$2 < bk.$2)) {
        best = l;
        bk = key;
      }
    }
    if (best == null) {
      best = _Line(k);
      lines.add(best);
    } else {
      best.units.add(k);
    }
    best.x1 = best.units.length > 1 ? math.max(best.x1, u.x1) : u.x1;
    best.t = best.units.map((j) => ub[j].y0).reduce(math.min);
    best.b = best.units.map((j) => ub[j].y1).reduce(math.max);
    best.lh = math.max(best.b - best.t, 6.0);
  }
  // Marks: the line whose band near them is closest vertically, close in x.
  for (final k in marks) {
    final u = ub[k];
    final cx = (u.x0 + u.x1) / 2;
    _Line? best;
    (double, double)? bk;
    for (var li = 0; li < lines.length; li++) {
      final l = lines[li];
      final (t, b) = _localBand(l, ub, cx);
      final bh = math.max(b - t, 2.0);
      final lx0 = l.units.map((j) => ub[j].x0).reduce(math.min);
      final dx = math.max(0.0, math.max(lx0 - cx, cx - l.x1));
      if (dx > bh) continue;
      final gap = math.max(0.0, math.max(t - u.y1, u.y0 - b));
      if (gap > 0.8 * bh) continue;
      final key = (gap / bh, dx);
      if (bk == null || key.$1 < bk.$1 || (key.$1 == bk.$1 && key.$2 < bk.$2)) {
        best = l;
        bk = key;
      }
    }
    if (best != null) {
      best.marks.add(k);
    } else {
      lines.add(_Line(k)
        ..x1 = u.x1
        ..t = u.y0
        ..b = u.y1
        ..lh = math.max(u.y1 - u.y0, 6.0));
    }
  }
  return lines;
}

/// Splits a line at wide gaps between its core units; marks follow their piece.
List<(List<int>, List<int>)> _splitCore(_Line l, List<_Box> ub) {
  final us = _sortedBy(l.units, (k) => ub[k].x0);
  final t = us.map((k) => ub[k].y0).reduce(math.min);
  final b = us.map((k) => ub[k].y1).reduce(math.max);
  final lh = math.max(b - t, 6.0);
  final pieces = <List<int>>[];
  var cur = <int>[];
  var right = 0.0;
  for (final k in us) {
    if (cur.isNotEmpty && ub[k].x0 - right > math.max(1.5 * lh, 18)) {
      pieces.add(cur);
      cur = [];
    }
    cur.add(k);
    right = cur.length == 1 ? ub[k].x1 : math.max(right, ub[k].x1);
  }
  if (cur.isNotEmpty) pieces.add(cur);
  final out = [for (final p in pieces) (p, <int>[])];
  final ext = [
    for (final p in pieces)
      (
        p.map((k) => ub[k].x0).reduce(math.min),
        p.map((k) => ub[k].x1).reduce(math.max)
      ),
  ];
  for (final m in l.marks) {
    final cx = (ub[m].x0 + ub[m].x1) / 2;
    var j = 0;
    var bd = double.infinity;
    for (var i = 0; i < ext.length; i++) {
      final d = math.max(0.0, math.max(ext[i].$1 - cx, cx - ext[i].$2));
      if (d < bd) {
        bd = d;
        j = i;
      }
    }
    out[j].$2.add(m);
  }
  return out;
}

/// A line too small to emit, or mostly tails of another line (p/g/q
/// descenders), moves into the nearest big line as marks.
List<_Line> _attachSmall(List<_Line> lines, List<_Box> ub) {
  final big = [
    for (final l in lines)
      if (l.units.length >= 3)
        (
          line: l,
          bt: _med(l.units.map((k) => ub[k].y0)),
          bb: _med(l.units.map((k) => ub[k].y1)),
          x0: l.units.map((k) => ub[k].x0).reduce(math.min),
          x1: l.units.map((k) => ub[k].x1).reduce(math.max),
        ),
  ];
  _Line? home(int k, _Line s, bool tailsOnly) {
    final u = ub[k];
    _Line? best;
    (double, double)? key;
    for (final c in big) {
      if (identical(c.line, s)) continue;
      final bh = math.max(c.bb - c.bt, 2.0);
      if (u.x1 < c.x0 - bh || u.x0 > c.x1 + bh || u.y1 - u.y0 > 4 * bh) {
        continue;
      }
      final gap = math.max(0.0, math.max(c.bt - u.y1, u.y0 - c.bb));
      final ov =
          math.max(0.0, math.min(u.y1, c.bb) - math.max(u.y0, c.bt)) / bh;
      if (tailsOnly) {
        if (ov < 0.5 || (u.y0 + u.y1) / 2 <= (c.bt + c.bb) / 2) continue;
      } else if (gap > 0.8 * bh) {
        continue;
      }
      final kk = (gap / bh, -ov);
      if (key == null ||
          kk.$1 < key.$1 ||
          (kk.$1 == key.$1 && kk.$2 < key.$2)) {
        best = c.line;
        key = kk;
      }
    }
    return best;
  }

  for (final s in lines) {
    final small = _splitCore(s, ub).every((p) => p.$1.length + p.$2.length < 3);
    final all = [...s.units, ...s.marks];
    final homes = {for (final k in all) k: home(k, s, !small)};
    final moving = [
      for (final e in homes.entries)
        if (e.value != null) e.key
    ];
    if (!small && moving.length < 0.7 * all.length) continue;
    for (final k in moving) {
      if (s.units.contains(k)) {
        s.units.remove(k);
      } else {
        s.marks.remove(k);
      }
      homes[k]!.marks.add(k);
    }
  }
  return [
    for (final l in lines)
      if (l.units.isNotEmpty || l.marks.isNotEmpty) l
  ];
}

/// Groups strokes into written lines and cuts them at wide gaps. Drawings,
/// two-row blobs and lone marks are left out.
List<InkSegment> segmentInk(List<StrokeData> strokes) {
  final valid = [
    for (final s in strokes)
      if (s.points.isNotEmpty) s
  ];
  if (valid.isEmpty) return const [];
  final bx = <_Box>[
    for (final s in valid)
      (
        x0: s.points.map((p) => p.x).reduce(math.min),
        y0: s.points.map((p) => p.y).reduce(math.min),
        x1: s.points.map((p) => p.x).reduce(math.max),
        y1: s.points.map((p) => p.y).reduce(math.max),
      ),
  ];
  final units = _glue(valid);
  final ub = <_Box>[
    for (final u in units)
      (
        x0: u.map((i) => bx[i].x0).reduce(math.min),
        y0: u.map((i) => bx[i].y0).reduce(math.min),
        x1: u.map((i) => bx[i].x1).reduce(math.max),
        y1: u.map((i) => bx[i].y1).reduce(math.max),
      ),
  ];
  final lines = _attachSmall(_groupLines(ub), ub);
  final out = <InkSegment>[];
  for (final l in lines) {
    if (l.units.isEmpty) continue;
    for (final (core, mk) in _splitCore(l, ub)) {
      if (core.length + mk.length < 3) continue;
      final cy0 = core.map((k) => ub[k].y0).reduce(math.min);
      final cy1 = core.map((k) => ub[k].y1).reduce(math.max);
      final cx0 = core.map((k) => ub[k].x0).reduce(math.min);
      final cx1 = core.map((k) => ub[k].x1).reduce(math.max);
      final bt = _med(core.map((k) => ub[k].y0));
      final bb = _med(core.map((k) => ub[k].y1));
      final bh = math.max(bb - bt, 1.0);
      final off = core.where((k) {
        final u = ub[k];
        return math.min(u.y1, bb) - math.max(u.y0, bt) <
            0.3 * math.min(math.max(u.y1 - u.y0, 1.0), bh);
      }).length;
      // One written line: wider than tall, at most _spanMax core bands
      // (ascenders + descenders), its units on one band (not two rows).
      if (cx1 - cx0 < cy1 - cy0 ||
          (cy1 - cy0) / bh >= _spanMax ||
          off > 0.25 * core.length) {
        continue;
      }
      final ids = [
        for (final k in [...core, ...mk]) ...units[k]
      ]..sort();
      out.add(InkSegment(
        [for (final i in ids) valid[i]],
        ids.map((i) => bx[i].x0).reduce(math.min),
        ids.map((i) => bx[i].y0).reduce(math.min),
        ids.map((i) => bx[i].x1).reduce(math.max),
        ids.map((i) => bx[i].y1).reduce(math.max),
      ));
    }
  }
  return out;
}
