// Strokes + detected symbols -> wires, nets, and a cleaned-up drawing.
//
// Everything here works in detector pixels (page width = 1024 px). Port of
// ml/circuits/wires.py, where the rules were tuned on handwritten notes; the
// README next to that script explains each rule.
//
// Symbol geometry is ported from CircuiTikZ, used under GPL-3.0 (copyright
// R. Giannetti, S. Lindner, S. Erhardt, M. Redaelli; see
// assets/licenses/circuitikz_NOTICE.txt).

import 'dart:math' as math;

import 'detector.dart';

part 'circuit_devices.dart';

class Pt {
  const Pt(this.x, this.y);
  final double x, y;
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator *(double s) => Pt(x * s, y * s);
  double get len => math.sqrt(x * x + y * y);
  double dot(Pt o) => x * o.x + y * o.y;
}

/// A new polyline; [source] is the original stroke whose style it inherits.
/// [wire] marks a straightened wire. Wires and symbols are [clean] lines,
/// thin like a wire unless [body] (a part's outline, drawn twice as thick,
/// as CircuiTikZ does); [fill] shapes are closed and solid. Anything else is
/// the user's ink, kept as drawn.
class OutStroke {
  OutStroke(this.points, this.source, [this.wire = false])
      : clean = wire,
        body = false,
        fill = false;
  OutStroke.line(this.points, {this.body = false})
      : source = -1,
        wire = false,
        clean = true,
        fill = false;
  OutStroke.reshaped(OutStroke o, this.points)
      : source = o.source,
        wire = o.wire,
        clean = o.clean,
        body = o.body,
        fill = o.fill;
  OutStroke.fill(this.points)
      : source = -1,
        wire = false,
        clean = true,
        body = false,
        fill = true;
  final List<Pt> points;
  final int source;
  final bool wire, clean, body, fill;
}

class CircuitRewrite {
  CircuitRewrite(this.removed, this.added, this.components, this.nets, this.rlen);

  /// Indices of input strokes to delete.
  final Set<int> removed;
  final List<OutStroke> added;
  final List<Detection> components;
  final int nets;

  /// CircuiTikZ's basic length the symbols were drawn at, in detector px.
  final double rlen;
}

const _nonComponent = {'text', 'junction', 'crossover', 'terminal', 'arrow'};
const _keepAsDrawn = {
  'ic', 'transformer', 'crossover', 'vss', 'capacitor.polarized',
};
const _sources = {'voltage.dc', 'voltage.ac', 'current_source'};
const _transistors = {'transistor.fet', 'transistor.bjt'};

// Tolerances in detector px (wires.py values x 1024/1240).
const double _tol = 7.5;
const double _nodeMax = 13;
const double _gapMax = 29;
const double _dirLen = 50;
const double _reachMax = 45;

// Symbols follow CircuiTikZ's proportions, in multiples of its basic length
// (`bipoles/length`, R below): R per drawing unit.
const double _rlenPerUnit = 1.05;

class _Box {
  _Box(this.x0, this.y0, this.x1, this.y1);
  factory _Box.of(Detection d) => _Box(d.x0, d.y0, d.x1, d.y1);
  final double x0, y0, x1, y1;
  double get cx => (x0 + x1) / 2;
  double get cy => (y0 + y1) / 2;
  double dist(Pt p) => math.sqrt(math.pow(math.max(0.0, math.max(x0 - p.x, p.x - x1)), 2) +
      math.pow(math.max(0.0, math.max(y0 - p.y, p.y - y1)), 2));
  bool has(Pt p, [double pad = 0]) =>
      p.x >= x0 - pad && p.x <= x1 + pad && p.y >= y0 - pad && p.y <= y1 + pad;
  String side(Pt p) {
    final dx = (p.x - cx) / math.max(1, x1 - x0), dy = (p.y - cy) / math.max(1, y1 - y0);
    return dx.abs() > dy.abs() ? (dx > 0 ? 'E' : 'W') : (dy > 0 ? 'S' : 'N');
  }
}

class _Dsu {
  _Dsu(int n) : p = List<int>.generate(n, (i) => i);
  final List<int> p;
  int find(int a) {
    while (p[a] != a) {
      p[a] = p[p[a]];
      a = p[a];
    }
    return a;
  }

  void union(int a, int b) => p[find(a)] = find(b);
}

/// Polylines bucketed by the grid cells their bounding boxes cover, so a
/// neighbour query only looks at what is nearby (a photo of a page can
/// trace into thousands of pieces).
class _Grid {
  _Grid(List<List<Pt>?> polys) {
    for (var id = 0; id < polys.length; id++) {
      final pts = polys[id];
      if (pts == null || pts.isEmpty) continue;
      var x0 = pts.first.x, y0 = pts.first.y, x1 = x0, y1 = y0;
      for (final p in pts) {
        x0 = math.min(x0, p.x);
        y0 = math.min(y0, p.y);
        x1 = math.max(x1, p.x);
        y1 = math.max(y1, p.y);
      }
      for (var cx = _c(x0); cx <= _c(x1); cx++) {
        for (var cy = _c(y0); cy <= _c(y1); cy++) {
          (_cells[_key(cx, cy)] ??= []).add(id);
        }
      }
    }
  }

  static const double cell = 40;
  final _cells = <int, List<int>>{};
  int _c(double v) => (v / cell).floor();
  static int _key(int cx, int cy) => (cx + 1048576) * 2097152 + (cy + 1048576);

  Set<int> near(Pt p, double r) => box(p.x - r, p.y - r, p.x + r, p.y + r);

  Set<int> box(double x0, double y0, double x1, double y1) {
    final out = <int>{};
    for (var cx = _c(x0); cx <= _c(x1); cx++) {
      for (var cy = _c(y0); cy <= _c(y1); cy++) {
        final ids = _cells[_key(cx, cy)];
        if (ids != null) out.addAll(ids);
      }
    }
    return out;
  }
}

class _Piece {
  _Piece(this.pts, this.source, [List<_Piece>? parts]) : parts = parts ?? [];
  List<Pt> pts;
  final int source;

  /// The pieces chained into this one, as they were drawn; empty if none.
  final List<_Piece> parts;
  Iterable<_Piece> get drawn => parts.isEmpty ? [this] : parts;
  Pt get a => pts.first;
  Pt get b => pts.last;
}

double _segDist(Pt p, Pt a, Pt b) {
  final ab = b - a;
  final l2 = ab.dot(ab);
  final t = l2 == 0 ? 0.0 : ((p - a).dot(ab) / l2).clamp(0.0, 1.0);
  return (a + ab * t - p).len;
}

double _polyDist(Pt p, List<Pt> pts) {
  var d = double.infinity;
  for (var i = 0; i + 1 < pts.length; i++) {
    d = math.min(d, _segDist(p, pts[i], pts[i + 1]));
  }
  return pts.length == 1 ? (pts[0] - p).len : d;
}

Pt _along(List<Pt> pts, double dist) {
  var acc = 0.0;
  for (var i = 1; i < pts.length; i++) {
    acc += (pts[i] - pts[i - 1]).len;
    if (acc >= dist) return pts[i];
  }
  return pts.last;
}

Pt _project(Pt p, List<Pt> pts) {
  var best = pts.first;
  var bd = double.infinity;
  for (var i = 0; i + 1 < pts.length; i++) {
    final a = pts[i], ab = pts[i + 1] - a;
    final l2 = ab.dot(ab);
    final t = l2 == 0 ? 0.0 : ((p - a).dot(ab) / l2).clamp(0.0, 1.0);
    final q = a + ab * t;
    final d = (q - p).len;
    if (d < bd) {
      bd = d;
      best = q;
    }
  }
  return best;
}

List<Pt> _simplify(List<Pt> pts, double eps) {
  if (pts.length < 3) return List.of(pts);
  var dmax = 0.0, idx = 0;
  for (var i = 1; i < pts.length - 1; i++) {
    final d = _segDist(pts[i], pts.first, pts.last);
    if (d > dmax) {
      dmax = d;
      idx = i;
    }
  }
  if (dmax <= eps) return [pts.first, pts.last];
  final l = _simplify(pts.sublist(0, idx + 1), eps);
  final r = _simplify(pts.sublist(idx), eps);
  return [...l.sublist(0, l.length - 1), ...r];
}

/// Rebuilds [pts] as horizontal/vertical runs from [s] to [e], keeping the
/// original's turn points.
List<Pt> _manhattan(List<Pt> pts, Pt s, Pt e) {
  final simp = _simplify(pts, 6);
  final dirs = <bool>[]; // true = horizontal
  final turns = <Pt>[];
  for (var i = 0; i + 1 < simp.length; i++) {
    final d = simp[i + 1] - simp[i];
    if (d.len < 3) continue;
    final h = d.x.abs() >= d.y.abs();
    if (dirs.isNotEmpty && dirs.last == h) {
      turns[turns.length - 1] = simp[i + 1];
    } else {
      dirs.add(h);
      turns.add(simp[i + 1]);
    }
  }
  if (dirs.isEmpty) return [s, e];
  final out = <Pt>[s];
  var cur = s;
  for (var i = 0; i < dirs.length; i++) {
    final h = dirs[i];
    final last = i == dirs.length - 1, second = i == dirs.length - 2;
    final target = last || second ? e : turns[i];
    final next = h ? Pt(target.x, cur.y) : Pt(cur.x, target.y);
    out.add(next);
    cur = next;
  }
  if ((cur - e).len > 0.5) out.add(e);
  return out;
}

List<Pt> _circle(Pt c, double r, [int n = 28]) =>
    [for (var i = 0; i <= n; i++) Pt(c.x + r * math.cos(2 * math.pi * i / n), c.y + r * math.sin(2 * math.pi * i / n))];

/// Builds the cleaned drawing. [strokes] are polylines in detector px.
CircuitRewrite rewriteCircuit(List<List<Pt>> strokes, List<Detection> detected) {
  final dets = _withSupplyArrows(strokes, _withCoils(strokes, detected));
  final (comps, sourceKinds) = _mergeSources(dets.where((d) => !_nonComponent.contains(d.cls)).toList());
  final kindOf = [for (final d in comps) d.cls];
  final cbox = comps.map(_Box.of).toList();
  // Annotation arrows stay as drawn, like text.
  final texts = dets.where((d) => d.cls == 'text' || d.cls == 'arrow').map(_Box.of).toList();
  final nodeBoxes = dets.where((d) => d.cls == 'junction' || d.cls == 'terminal').map(_Box.of).toList();
  // One scale for every redrawn symbol: the typical size of a part in this
  // drawing, so a big ring and a small zigzag come out in proportion.
  final sizes = [
    for (var c = 0; c < comps.length; c++)
      if (!_keepAsDrawn.contains(kindOf[c]) && kindOf[c] != 'gnd' && kindOf[c] != 'opamp')
        math.max(cbox[c].x1 - cbox[c].x0, cbox[c].y1 - cbox[c].y0)
  ]..sort();
  final unit = sizes.isEmpty ? 50.0 : sizes[sizes.length ~/ 2].clamp(30.0, 90.0);
  final rl = _rlenPerUnit * unit;

  final added = <OutStroke>[];
  final keptOf = <int, List<OutStroke>>{}; // component -> its ink, if kept
  final inkOf = <int, List<Pt>>{}; // component -> all ink inside its box
  final sourceInk = <int, List<List<Pt>>>{}; // dc/ac source -> the marks inside its ring
  final compStrokes = <int>{};
  final pieces = <_Piece>[];

  int region(Pt p) {
    for (var i = 0; i < cbox.length; i++) {
      if (cbox[i].has(p)) return i;
    }
    return -1;
  }

  // 1. Split every non-text stroke into wire pieces and component parts.
  // Specks (a tap, or a zero-length leftover of an earlier tidy-up) take no
  // part; they are swept away below if they sit on the circuit.
  final specks = <int>[];
  // The detector's box can also fall short of the drawn symbol (a big ring,
  // a square turned into a diamond): grow it to the closed outline that sits
  // mostly inside, so the outline is not cut into wire pieces.
  for (var c = 0; c < comps.length; c++) {
    if (!_sources.contains(kindOf[c])) continue;
    final b = cbox[c];
    final side = math.min(b.x1 - b.x0, b.y1 - b.y0);
    for (final st in strokes) {
      if (st.length < 5 || (st.first - st.last).len > 0.25 * side) continue;
      if (st.where((p) => b.has(p)).length * 2 < st.length) continue;
      final xs = st.map((p) => p.x), ys = st.map((p) => p.y);
      final x0 = xs.reduce(math.min), x1 = xs.reduce(math.max), y0 = ys.reduce(math.min), y1 = ys.reduce(math.max);
      if (math.max(x1 - x0, y1 - y0) < 0.8 * side || math.max(x1 - x0, y1 - y0) > 1.6 * side) continue;
      cbox[c] = _Box(math.min(b.x0, x0), math.min(b.y0, y0), math.max(b.x1, x1), math.max(b.y1, y1));
      break;
    }
    if (!identical(cbox[c], b)) continue;
    // A ring in several arcs (a traced picture splits it where wires meet
    // it): the circle the arcs lie on is the symbol, wherever the box sat.
    final ring = _ringFromArcs(strokes, b);
    if (ring != null) cbox[c] = ring;
  }

  // A source's box can run past its ring over the label beside it ("v_s",
  // the g of "g_m"). The ring is the widest stroke in the box; a stroke
  // wholly outside it is a label and stays as drawn.
  final labelStrokes = <int>{};
  for (var c = 0; c < comps.length; c++) {
    if (!_sources.contains(kindOf[c])) continue;
    final b = cbox[c];
    final inBox = [
      for (var si = 0; si < strokes.length; si++)
        if (strokes[si].length > 1 && strokes[si].every((p) => b.has(p, _tol))) si
    ];
    double span(List<Pt> st) => math.max(st.map((p) => p.x).reduce(math.max) - st.map((p) => p.x).reduce(math.min),
        st.map((p) => p.y).reduce(math.max) - st.map((p) => p.y).reduce(math.min));
    if (inBox.isEmpty) continue;
    final ring = inBox.reduce((a, b) => span(strokes[a]) >= span(strokes[b]) ? a : b);
    final rs = strokes[ring];
    final xs = rs.map((p) => p.x), ys = rs.map((p) => p.y);
    final rc = Pt((xs.reduce(math.max) + xs.reduce(math.min)) / 2, (ys.reduce(math.max) + ys.reduce(math.min)) / 2);
    final rr = span(rs) / 2;
    // No ring drawn as one stroke (a diamond side by side, a ring in arcs).
    if (rr < 0.3 * math.min(b.x1 - b.x0, b.y1 - b.y0) || (rs.first - rs.last).len > 0.6 * rr) continue;
    for (final si in inBox) {
      if (si != ring && strokes[si].every((p) => (p - rc).len > 1.02 * rr)) labelStrokes.add(si);
    }
  }

  for (var si = 0; si < strokes.length; si++) {
    final st = strokes[si];
    if (st.isEmpty || labelStrokes.contains(si)) continue;
    if (st.every((p) => (p - st.first).len < 1.5)) {
      specks.add(si);
      continue;
    }
    final inText = st.where((p) => texts.any((t) => t.has(p))).length;
    // Signs inside an amplifier or a source ring are part of that symbol even
    // when the detector also reads them as text.
    final marks = cbox.indexed.any((e) =>
        (kindOf[e.$1] == 'opamp' || _sources.contains(kindOf[e.$1])) && st.every((p) => e.$2.has(p)));
    if (inText * 2 > st.length && !marks) continue;
    var run = <Pt>[];
    var reg = region(st.first);
    void flush() {
      if (run.isEmpty) return;
      if (reg < 0) {
        if (run.length >= 2) pieces.add(_Piece(run, si));
      } else {
        compStrokes.add(si);
        inkOf.putIfAbsent(reg, () => []).addAll(_densify(run, 2));
        final cls = comps[reg].cls;
        // Every part keeps its ink at hand: it is put back if the part ends
        // up not redrawn.
        keptOf.putIfAbsent(reg, () => []).add(OutStroke(run, si));
        if (_sources.contains(cls)) {
          final b = cbox[reg];
          final r = 0.5 * math.min(b.x1 - b.x0, b.y1 - b.y0);
          // The sign or arrow inside the ring gives kind and polarity: collect
          // whole pieces whose centre sits well inside, not the ring itself.
          final c = run.fold(const Pt(0, 0), (a, p) => a + p) * (1 / run.length);
          final reach = run.map((p) => (p - Pt(b.cx, b.cy)).len).reduce(math.max);
          if ((c - Pt(b.cx, b.cy)).len < 0.5 * r && reach < 0.85 * r && run.length >= 2) {
            sourceInk.putIfAbsent(reg, () => []).add(run);
          }
        }
      }
      run = <Pt>[];
    }

    Pt? prev;
    for (final p in st) {
      final r = region(p);
      if (r != reg) {
        // Cut exactly on the box border: stored strokes can be sparse on
        // straight runs, and the last point before a box may sit well short
        // of it.
        final edge = prev == null ? null : _crossing(prev, p, cbox[r >= 0 ? r : reg]);
        if (edge != null) run.add(edge);
        flush();
        reg = r;
        if (edge != null) run.add(edge);
      }
      run.add(p);
      prev = p;
    }
    flush();
  }
  pieces.removeWhere((pc) => (pc.b - pc.a).len <= 4 && pc.pts.length <= 6);

  // A ring the detector scored both ways is settled by what is drawn inside.
  final arrowOf = <int, Pt>{};
  for (var c = 0; c < comps.length; c++) {
    if (!_sources.contains(kindOf[c])) continue;
    final b = cbox[c];
    final arrow = _arrowDir(sourceInk[c], Pt(b.cx, b.cy), 0.5 * math.min(b.x1 - b.x0, b.y1 - b.y0));
    final kinds = sourceKinds[c] ?? {kindOf[c]};
    if (arrow != null && kinds.contains('current_source')) {
      kindOf[c] = 'current_source';
    } else if (arrow == null && kindOf[c] == 'current_source' && kinds.length > 1) {
      kindOf[c] = kinds.firstWhere((k) => k != 'current_source');
    }
    if (arrow != null) {
      arrowOf[c] = arrow;
    } else if (kindOf[c] == 'current_source') {
      // Only a head drawn (the wire itself is the shaft): it points to the
      // side of the ring it sits in. Nothing readable: keep the marks.
      final marks = sourceInk[c] ?? const [];
      final all = [for (final m in marks) ...m];
      final r = 0.5 * math.min(b.x1 - b.x0, b.y1 - b.y0);
      final off = all.isEmpty ? const Pt(0, 0) : all.fold(const Pt(0, 0), (a, p) => a + p) * (1 / all.length) - Pt(b.cx, b.cy);
      if (off.len > 0.2 * r) {
        arrowOf[c] = off.x.abs() > off.y.abs() ? Pt(off.x.sign, 0) : Pt(0, off.y.sign);
      } else {
        for (final m in marks) {
          added.add(OutStroke(m, -1));
        }
        arrowOf[c] = const Pt(0, 0);
      }
    }
  }
  _chainPieces(pieces, cbox, unit);
  // Wires run straight along the axes. A curve (a plot, a brace), a slanted
  // line or a zigzag the detector missed is something else: it keeps its
  // shape and connects nothing.
  final wirelike = [for (final pc in pieces) _wirelike(pc.pts, unit)];

  // 2. Nets: joints, facing ends, node dots/terminals, ground symbols.
  final dsu = _Dsu(pieces.length);
  final grid = _Grid([for (final pc in pieces) pc.pts]);
  final tJoin = <(int, bool), int>{}; // (piece, isEnd) -> piece it lands on
  for (var i = 0; i < pieces.length; i++) {
    for (final isEnd in [false, true]) {
      final e = isEnd ? pieces[i].b : pieces[i].a;
      for (final j in grid.near(e, _tol)) {
        if (i == j) continue;
        if (_polyDist(e, pieces[j].pts) <= _tol) {
          dsu.union(i, j);
          final pj = pieces[j];
          if ((e - pj.a).len > _tol && (e - pj.b).len > _tol) tJoin[(i, isEnd)] = j;
        }
      }
    }
  }
  final ends = <(int, bool, Pt, Pt)>[];
  for (var i = 0; i < pieces.length; i++) {
    final p = pieces[i].pts;
    ends.add((i, false, p.first, _along(p, _dirLen)));
    ends.add((i, true, p.last, _along(p.reversed.toList(), _dirLen)));
  }
  final endGrid = _Grid([for (final e in ends) [e.$3]]);
  for (final (i, _, e, ni) in ends) {
    final di = e - ni;
    for (final k in endGrid.near(e, _gapMax)) {
      final (j, _, f, nj) = ends[k];
      if (i == j) continue;
      final g = f - e;
      final gap = g.len;
      if (gap > _gapMax || gap < 1) continue;
      final dj = f - nj;
      if (di.dot(g) > 0.8 * di.len * gap && dj.dot(g * -1) > 0.8 * dj.len * gap) dsu.union(i, j);
    }
  }
  final nodes = <_Box>[...nodeBoxes];
  final dotPieces = <int>{};
  for (var i = 0; i < pieces.length; i++) {
    final xs = pieces[i].pts.map((p) => p.x), ys = pieces[i].pts.map((p) => p.y);
    final w = xs.reduce(math.max) - xs.reduce(math.min), h = ys.reduce(math.max) - ys.reduce(math.min);
    if (math.max(w, h) <= _nodeMax && math.min(w, h) >= 3) {
      dotPieces.add(i);
      nodes.add(_Box(xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max)));
    }
  }
  for (final nb in nodes) {
    final hit = <int>[
      for (final i in grid.box(nb.x0 - _tol - 3, nb.y0 - _tol - 3, nb.x1 + _tol + 3, nb.y1 + _tol + 3))
        if (nb.has(pieces[i].a, _tol + 3) || nb.has(pieces[i].b, _tol + 3) ||
            pieces[i].pts.any((p) => nb.has(p, 1)))
          i
    ];
    for (final i in hit.skip(1)) {
      dsu.union(hit.first, i);
    }
  }

  // 3. Where each wire end lands on a component, and on which side.
  final attach = <(int, bool), int>{};
  for (var i = 0; i < pieces.length; i++) {
    if (dotPieces.contains(i) || !wirelike[i]) continue;
    for (final isEnd in [false, true]) {
      final e = isEnd ? pieces[i].b : pieces[i].a;
      // A wire end on a drawn node (a junction on a rail) belongs to the
      // node, not to a part merely nearby.
      final onNode = nodes.any((n) => n.has(e, 2));
      // Nearest box wins: a short wire between two parts touches both pads.
      var bd = onNode ? 0.0 : _tol + 2;
      for (var c = 0; c < cbox.length; c++) {
        final d = cbox[c].dist(e);
        if (d <= bd) {
          bd = d;
          attach[(i, isEnd)] = c;
        }
      }
    }
  }

  // 4. Lay out each redrawn component on the line of the wires reaching it.
  final terminalsOf = <int, List<Pt>>{};
  List<Pt> wireEnds(int c) => attach.entries.where((e) => e.value == c).map((e) {
        final pc = pieces[e.key.$1];
        return e.key.$2 ? pc.b : pc.a;
      }).toList();
  final axisOf = <int, (bool, double)>{}; // component -> (vertical, line)
  for (var c = 0; c < comps.length; c++) {
    final cls = kindOf[c];
    if (_keepAsDrawn.contains(cls) || cls == 'gnd' || cls == 'opamp' || _transistors.contains(cls)) continue;
    final b = cbox[c];
    final mine = wireEnds(c);
    final sides = mine.map(b.side).toSet();
    final vertical = sides.isEmpty
        ? (b.y1 - b.y0) > (b.x1 - b.x0)
        : (sides.containsAll(['N', 'S']) || (!sides.contains('E') && !sides.contains('W')));
    final along = vertical
        ? mine.where((p) => b.side(p) == 'N' || b.side(p) == 'S').map((p) => p.x)
        : mine.where((p) => b.side(p) == 'E' || b.side(p) == 'W').map((p) => p.y);
    axisOf[c] = (vertical, along.isEmpty ? (vertical ? b.cx : b.cy) : along.reduce((a, v) => a + v) / along.length);
  }
  // A transistor's gate wire joins the alignment as a horizontal line, so a
  // rail running into the gate past other parts stays level.
  for (var c = 0; c < comps.length; c++) {
    if (!_transistors.contains(kindOf[c])) continue;
    final b = cbox[c];
    final side = wireEnds(c)
        .where((p) => (p.y - b.cy).abs() < 0.3 * (b.y1 - b.y0) && (b.side(p) == 'W' || b.side(p) == 'E'))
        .toList();
    if (side.isEmpty || side.map(b.side).toSet().length != 1) continue;
    axisOf[c] = (false, side.map((p) => p.y).reduce((a, v) => a + v) / side.length);
  }
  _alignAxes(axisOf);
  // x of the terminal already laid out at the far end of a wire entering [c]
  // from above, so a vertical run between two parts comes out straight.
  double? fromAbove(int c) {
    for (final e in attach.entries) {
      if (e.value != c) continue;
      final (i, isEnd) = e.key;
      final mineEnd = isEnd ? pieces[i].b : pieces[i].a;
      if (cbox[c].side(mineEnd) != 'N') continue;
      final o = attach[(i, !isEnd)];
      final ts = o == null ? null : terminalsOf[o];
      if (ts == null) continue;
      final far = isEnd ? pieces[i].a : pieces[i].b;
      return ts.reduce((a, v) => (a - far).len <= (v - far).len ? a : v).x;
    }
    return null;
  }

  // A ground hangs straight below the wire that feeds it: the x of the last
  // long upright run of an incoming wire. With several coming in (a stem off
  // a rail next to its corner), only a run close by may move it.
  double? dropX(int c) {
    final ins = attach.keys.where((k) => attach[k] == c).toList();
    double? best;
    for (final (i, isEnd) in ins) {
      var pts = _simplify(pieces[i].pts, 4);
      if (isEnd) pts = pts.reversed.toList();
      for (var k = 0; k + 1 < pts.length; k++) {
        final d = pts[k + 1] - pts[k];
        final upright = d.y.abs() > 2 * d.x.abs();
        if (upright && d.len >= 0.4 * unit) {
          final x = (pts[k].x + pts[k + 1].x) / 2;
          if (best == null || (x - cbox[c].cx).abs() < (best - cbox[c].cx).abs()) best = x;
          break;
        }
        // Only a short hook may come between: a long sideways run means the
        // ground hangs where it was drawn.
        if (!upright && d.len >= 0.8 * unit) break;
      }
    }
    if (best == null) return null;
    return (best - cbox[c].cx).abs() <= (ins.length == 1 ? 2 : 0.6) * unit ? best : null;
  }

  // A supply rail sits on the line of the upright part right below it.
  double? partBelow(int c) {
    final b = cbox[c];
    final mine = wireEnds(c);
    final x = mine.map((p) => p.x).reduce((a, v) => a + v) / mine.length;
    double? best, bestY;
    for (final e in axisOf.entries) {
      final ob = cbox[e.key];
      if (!e.value.$1 || ob.y0 < b.y1 - _tol || (e.value.$2 - x).abs() > 0.6 * unit) continue;
      if (bestY == null || ob.y0 < bestY) (best, bestY) = (e.value.$2, ob.y0);
    }
    return best;
  }

  final order = List<int>.generate(comps.length, (i) => i)..sort((a, b) => cbox[a].y0.compareTo(cbox[b].y0));
  for (final c in order) {
    final cls = kindOf[c];
    final b = cbox[c];
    final mine = wireEnds(c);
    if (_keepAsDrawn.contains(cls)) continue;
    // Wires reaching a part confirm it; without them the detector must be
    // sure (stray shapes in a plot or a note get scored as parts too).
    // Batteries are its weakest class.
    final need = cls == 'voltage.battery' ? 0.5 : (mine.length >= 2 ? 0.0 : (mine.length == 1 ? 0.25 : 0.6));
    if (comps[c].score < need) continue;
    if (_transistors.contains(cls)) {
      // A part stacked right on top of the transistor sets its lead line.
      double? stacked;
      for (final o in axisOf.entries) {
        final ob = cbox[o.key];
        if (!o.value.$1 || o.value.$2 < b.x0 || o.value.$2 > b.x1) continue;
        if ((ob.y1 - b.y0).abs() <= _tol * 1.6 || (b.y1 - ob.y0).abs() <= _tol * 1.6) stacked = o.value.$2;
      }
      final above = fromAbove(c);
      if (above != null && above > b.x0 && above < b.x1) stacked = above;
      final t = _transistor(b, mine, [for (final o in keptOf[c] ?? const <OutStroke>[]) o.points], rl,
          stacked: stacked,
          bipolar: cls == 'transistor.bjt',
          gateLine: axisOf[c]?.$2,
          placed: [for (final ts in terminalsOf.values) ...ts]);
      terminalsOf[c] = t.$1;
      added.addAll(t.$2);
      continue;
    }
    if (cls == 'opamp') {
      final amp = _opamp(b, mine, [for (final o in keptOf[c] ?? const <OutStroke>[]) o.points], rl);
      if (amp != null) {
        terminalsOf[c] = amp.$1;
        added.addAll(amp.$2);
      }
      continue;
    }
    // A bar fed from below only is a supply rail: the detector reads it as a
    // ground, or, unsure, as a capacitor missing its second plate.
    final railLike = mine.isNotEmpty && mine.every((p) => b.side(p) == 'S');
    if (cls == 'gnd' || (cls == 'capacitor' && railLike && comps[c].score < 0.5)) {
      final ink = [for (final o in keptOf[c] ?? const <OutStroke>[]) o.points];
      // Shape tests look along the stem as drawn, not where it is snapped to.
      final drawnX = mine.isEmpty ? b.cx : mine.map((p) => p.x).reduce((a, v) => a + v) / mine.length;
      // A ground or a rail ends its wire: ink running on past the far side
      // (a wire through a label read as a ground) leaves it as drawn.
      bool runsPast(bool up, [double? at]) => strokes.any((st) => st.any((p) =>
          (p.x - (at ?? drawnX)).abs() <= _tol &&
          (up ? b.y0 - p.y : p.y - b.y1) > 2 &&
          (up ? b.y0 - p.y : p.y - b.y1) <= 0.4 * unit &&
          !texts.any((t) => t.has(p))));
      if (runsPast(railLike)) continue;
      // ...and hangs off the circuit: some wire into it leads somewhere (an
      // annotation arrow's shaft beside a wire does not).
      final leads = attach.keys.where((k) => attach[k] == c).any((k) {
        final (i, isEnd) = k;
        if (attach.containsKey((i, !isEnd))) return true;
        final far = isEnd ? pieces[i].a : pieces[i].b;
        return grid
            .box(far.x - _tol, far.y - _tol, far.x + _tol, far.y + _tol)
            .any((j) => j != i && pieces[j].pts.any((p) => (p - far).len <= _tol));
      });
      if (!leads) continue;
      if (railLike) {
        final x = partBelow(c) ?? mine.map((p) => p.x).reduce((a, v) => a + v) / mine.length;
        if (runsPast(true, x)) continue;
        if (cls == 'gnd' && _headBars(ink, drawnX) != null && _pointsAway(ink, drawnX, -1)) {
          // An arrow or triangle up: CircuiTikZ's vcc.
          final apex = Pt(x, ink.expand((r) => r).map((p) => p.y).reduce(math.min));
          added
            ..add(OutStroke.line([Pt(x, b.y1), apex]))
            ..addAll(_supplyArrow(apex, -1, rl));
        } else {
          final w = 0.2 * rl;
          added
            ..add(OutStroke.line([Pt(x - w, b.cy), Pt(x + w, b.cy)], body: true))
            ..add(OutStroke.line([Pt(x, b.cy), Pt(x, b.y1)]));
        }
        terminalsOf[c] = [Pt(x, b.y1)];
        continue;
      }
      // Redraw only a ground fed from above: wires from the top, or a rail
      // passing over it (its halves reach the box high on either side).
      // Anything else stays as drawn.
      bool rail(Pt p) => (b.side(p) == 'W' || b.side(p) == 'E') && p.y < b.y0 + 0.4 * (b.y1 - b.y0);
      if (mine.isEmpty || !mine.every((p) => b.side(p) == 'N' || rail(p))) continue;
      final down = mine.where((p) => b.side(p) == 'N').toList(), across = mine.where(rail).toList();
      final above = fromAbove(c);
      var x = dropX(c) ??
          (above != null && b.has(Pt(above, b.cy), 0.25 * (b.x1 - b.x0))
              ? above
              : down.isEmpty
                  ? b.cx
                  : down.map((p) => p.x).reduce((a, v) => a + v) / down.length);
      // A hair off the terminal it hangs from is a wobble of the pen.
      if (above != null && (x - above).abs() <= _tol) x = above;
      // Where it would be drawn, the wire must end too.
      if (runsPast(false, x)) continue;
      final topY = across.isEmpty ? b.y0 : across.map((p) => p.y).reduce((a, v) => a + v) / across.length;
      if (_headBars(ink, drawnX) != null && _pointsAway(ink, drawnX, 1)) {
        // A head down, open or closed, is a ground drawn as a triangle:
        // CircuiTikZ's sground (an open "v" is a quick one far more often
        // than a VEE arrow).
        final apex = ink.expand((r) => r).map((p) => p.y).reduce(math.max);
        final w = 0.15 * rl, base = math.max(topY + 0.1 * rl, apex - 0.25 * rl);
        added
          ..add(OutStroke.line([Pt(x, topY), Pt(x, base)]))
          ..add(OutStroke.line([Pt(x - w, base), Pt(x + w, base), Pt(x, base + 0.25 * rl), Pt(x - w, base)], body: true));
        terminalsOf[c] = [Pt(x, topY)];
        continue;
      }
      // CircuiTikZ's ground: three bars 0.05 R apart, the top one 0.3 R wide.
      final top = Pt(x, topY), w = 0.15 * rl, step = 0.05 * rl;
      final barY = topY + math.max(0.3 * rl, (b.y1 - topY) * 0.35);
      added
        ..add(OutStroke.line([top, Pt(x, barY)]))
        ..add(OutStroke.line([Pt(x - w, barY), Pt(x + w, barY)], body: true))
        ..add(OutStroke.line([Pt(x - w * 2 / 3, barY + step), Pt(x + w * 2 / 3, barY + step)], body: true))
        ..add(OutStroke.line([Pt(x - w * 5 / 12, barY + 2 * step), Pt(x + w * 5 / 12, barY + 2 * step)], body: true));
      terminalsOf[c] = [top];
      continue;
    }
    final (vertical, axisLine) = axisOf[c]!;
    final boxy = cls == 'resistor' && _looksLikeBox(inkOf[c] ?? const [], b);
    final kind = boxy
        ? 'resistor.box'
        : cls == 'capacitor' && _unevenPlates(inkOf[c] ?? const [], vertical)
            ? 'voltage.battery'
            : cls;
    // Short boxes grow a little along the axis to fit the symbol, but not
    // into their neighbours: past that the body shrinks instead.
    final mid = vertical ? b.cy : b.cx;
    final boxHalf = (vertical ? b.y1 - b.y0 : b.x1 - b.x0) / 2;
    var half = math.max(boxHalf, math.min(_minLength(kind, rl) / 2, boxHalf + 0.15 * unit));
    // A part laid out already right at one end, on this line give or take a
    // wobble: meet its terminal there instead of running past it.
    var line = axisLine;
    for (final ts in terminalsOf.values) {
      for (final t in ts) {
        final across = vertical ? t.x - axisLine : t.y - axisLine, along = ((vertical ? t.y : t.x) - mid).abs();
        if (across.abs() > _tol || along < boxHalf - 2 || along >= half) continue;
        half = along;
        line = vertical ? t.x : t.y;
      }
    }
    axisOf[c] = (vertical, line);
    final s = vertical ? Pt(line, mid - half) : Pt(mid - half, line);
    final e = vertical ? Pt(line, mid + half) : Pt(mid + half, line);
    terminalsOf[c] = [s, e];
    final flip = switch (kind) {
      'voltage.dc' => _plusTowardStart(sourceInk[c], s, e) ?? _outsideSignTowardStart(strokes, b, s, e) ?? true,
      'diode' => _cathodeAtStart(inkOf[c] ?? const [], s, e),
      'switch' => _inkSide(inkOf[c] ?? const [], s, e) > 0,
      'voltage.battery' => _widerAtStart(inkOf[c] ?? const [], s, e),
      _ => false,
    };
    final diamond =
        _sources.contains(kind) && _isDiamond([for (final o in keptOf[c] ?? const <OutStroke>[]) o.points], b);
    added.addAll(_symbol(kind, s, e, rl, flip: flip, arrow: arrowOf[c], diamond: diamond));
  }

  for (final e in keptOf.entries) {
    if (!terminalsOf.containsKey(e.key)) added.addAll(e.value);
  }

  // 5. Straight wires, ending on terminals or on the wire they join.
  final straight = List<List<Pt>?>.filled(pieces.length, null);
  Pt target(int i, bool isEnd) {
    final pc = pieces[i];
    final e = isEnd ? pc.b : pc.a;
    final c = attach[(i, isEnd)];
    if (c == null) return e;
    final ts = terminalsOf[c];
    if (ts == null) {
      // Kept-as-drawn symbol: land on its box edge, wherever the wire meets it.
      final b = cbox[c];
      switch (b.side(e)) {
        case 'N':
          return Pt(e.x, b.y0);
        case 'S':
          return Pt(e.x, b.y1);
        case 'W':
          return Pt(b.x0, e.y);
        default:
          return Pt(b.x1, e.y);
      }
    }
    return ts.reduce((a, v) => (a - e).len <= (v - e).len ? a : v);
  }

  // A straight drop from a rail onto a part: its rail end may slide along the
  // rail, taking the node with it when every other wire there runs across, so
  // the drop lines up with the part instead of jogging.
  final endAt = <(int, bool), Pt>{
    for (var i = 0; i < pieces.length; i++)
      if (!dotPieces.contains(i))
        for (final isEnd in [false, true]) (i, isEnd): target(i, isEnd),
  };
  Pt outward(int i, bool isEnd) {
    final pts = isEnd ? pieces[i].pts.reversed.toList() : pieces[i].pts;
    return pts.first - _along(pts, _dirLen);
  }

  for (var i = 0; i < pieces.length; i++) {
    if (dotPieces.contains(i)) continue;
    final fixedS = terminalsOf.containsKey(attach[(i, false)]), fixedE = terminalsOf.containsKey(attach[(i, true)]);
    if (fixedS == fixedE) continue;
    final pc = pieces[i];
    if (!pc.pts.every((p) => _segDist(p, pc.a, pc.b) <= _tol)) continue;
    final d = pc.b - pc.a;
    final upright = d.x.abs() < 0.3 * d.y.abs();
    if (!upright && d.y.abs() >= 0.3 * d.x.abs()) continue;
    final free = (i, fixedS), anchor = endAt[(i, !fixedS)]!;
    final raw = fixedS ? pc.b : pc.a;
    final partners = <(int, bool)>[];
    var ok = true;
    for (final j in grid.near(raw, _tol * 1.5)) {
      if (!ok) break;
      if (j == i || dotPieces.contains(j)) continue;
      for (final isEnd in [false, true]) {
        if (((isEnd ? pieces[j].b : pieces[j].a) - raw).len > _tol * 1.5) continue;
        final o = outward(j, isEnd);
        // Partners must run across the drop, and be free to stretch.
        if (attach.containsKey((j, isEnd)) || (upright ? o.y.abs() > 0.5 * o.x.abs() : o.x.abs() > 0.5 * o.y.abs())) {
          ok = false;
        } else {
          partners.add((j, isEnd));
        }
      }
    }
    // A dangling end (a port, a stub) has nothing to hold it: it lines up
    // too, unless it shares a drawn node with another wire.
    bool dangling() =>
        attach[free] == null &&
        !nodes.any((n) =>
            n.has(raw, _tol) &&
            grid
                .box(n.x0 - _tol, n.y0 - _tol, n.x1 + _tol, n.y1 + _tol)
                .any((j) => j != i && !dotPieces.contains(j) && (n.has(pieces[j].a, _tol) || n.has(pieces[j].b, _tol))));
    if (!ok || (partners.isEmpty && !tJoin.containsKey(free) && !dangling())) continue;
    Pt slide(Pt p) => upright ? Pt(anchor.x, p.y) : Pt(p.x, anchor.y);
    endAt[free] = slide(endAt[free]!);
    for (final k in partners) {
      endAt[k] = slide(endAt[k]!);
    }
  }
  for (var i = 0; i < pieces.length; i++) {
    if (dotPieces.contains(i)) continue;
    // A zigzag the detector missed is a part, not a wire: leave it as drawn.
    if (!wirelike[i]) continue;
    straight[i] = _manhattan(pieces[i].pts, endAt[(i, false)]!, endAt[(i, true)]!);
  }
  for (final entry in tJoin.entries) {
    final (i, isEnd) = entry.key;
    final host = straight[entry.value], mine = straight[i];
    if (host == null || mine == null || attach.containsKey(entry.key)) continue;
    final q = _project(isEnd ? mine.last : mine.first, host);
    if (isEnd) {
      mine[mine.length - 1] = q;
    } else {
      mine[0] = q;
    }
  }
  // Only nets that reach a component are wires; the rest (labels the detector
  // missed, braces, arrows) stays exactly as drawn.
  final live = {for (final k in attach.keys) dsu.find(k.$1)};
  double runLength(List<Pt> st) {
    var len = 0.0;
    for (var k = 1; k < st.length; k++) {
      len += (st[k] - st[k - 1]).len;
    }
    return len;
  }

  // A free end that stops short of a crossing wire (a rail drawn up to, but
  // not onto, the wire it tees into) runs on until it meets it.
  final wireGrid = _Grid(straight);
  for (var i = 0; i < pieces.length; i++) {
    final mine = straight[i];
    if (mine == null || mine.length < 2 || !live.contains(dsu.find(i)) || runLength(pieces[i].pts) < _tol * 2) continue;
    for (final isEnd in [false, true]) {
      if (attach.containsKey((i, isEnd)) || tJoin.containsKey((i, isEnd))) continue;
      final e = isEnd ? mine.last : mine.first;
      final out = e - (isEnd ? mine[mine.length - 2] : mine[1]);
      if (out.len < 1) continue;
      final dir = out * (1 / out.len);
      if (dir.x.abs() > 0.01 && dir.y.abs() > 0.01) continue;
      var reach = _reachMax;
      Pt? hit;
      var nearEnd = false;
      final far = e + dir * _reachMax;
      for (final j in wireGrid.box(math.min(e.x, far.x) - _tol, math.min(e.y, far.y) - _tol,
          math.max(e.x, far.x) + _tol, math.max(e.y, far.y) + _tol)) {
        final host = straight[j];
        if (j == i || host == null || !live.contains(dsu.find(j))) continue;
        if ((host.first - e).len <= _tol || (host.last - e).len <= _tol) nearEnd = true;
        for (var k = 0; k + 1 < host.length; k++) {
          final a = host[k], b = host[k + 1];
          final double t, lo, hi, across;
          if (dir.x != 0 && (a.x - b.x).abs() < 0.5) {
            t = (a.x - e.x) / dir.x;
            lo = math.min(a.y, b.y);
            hi = math.max(a.y, b.y);
            across = e.y;
          } else if (dir.y != 0 && (a.y - b.y).abs() < 0.5) {
            t = (a.y - e.y) / dir.y;
            lo = math.min(a.x, b.x);
            hi = math.max(a.x, b.x);
            across = e.x;
          } else {
            continue;
          }
          if (t > 0.2 && t < reach && across >= lo - 2 && across <= hi + 2) {
            reach = t;
            hit = e + dir * t;
          }
        }
      }
      // Already at another wire's end (a corner or a tee drawn as separate
      // strokes): close only the hair's gap between them, never run on.
      if (hit == null || (nearEnd && reach > _tol)) continue;
      if (isEnd) {
        mine[mine.length - 1] = hit;
      } else {
        mine[0] = hit;
      }
    }
  }
  final removed = <int>{...compStrokes};
  for (var i = 0; i < pieces.length; i++) {
    if (live.contains(dsu.find(i))) removed.addAll(pieces[i].drawn.map((d) => d.source));
  }

  // Level the wires: runs that continue each other a few pixels apart end up
  // on one line, a part's terminal line winning when one sits on it.
  _snapRuns([for (var i = 0; i < pieces.length; i++) live.contains(dsu.find(i)) ? straight[i] : null],
      [for (final ts in terminalsOf.values) ...ts], math.max(2.5, 0.15 * unit));

  // Node marks, drawn clean on the straightened wires: open rings (port
  // terminals) and filled junction dots. A ring is a small hollow loop, drawn
  // on its own or into the wire's stroke; the wire stops at its rim.
  final ringInk = <int>{};
  final rings = <Pt>[], dots = <Pt>[];
  Pt onWire(Pt c, double reach) {
    var best = c;
    var bd = reach;
    for (final j in wireGrid.near(c, reach)) {
      final st = straight[j];
      if (st == null || !live.contains(dsu.find(j))) continue;
      final q = _project(c, st);
      if ((q - c).len < bd) {
        bd = (q - c).len;
        best = q;
      }
    }
    return best;
  }

  final terminalBoxes = dets.where((d) => d.cls == 'terminal').map(_Box.of).toList();
  for (var i = 0; i < pieces.length; i++) {
    if (!live.contains(dsu.find(i))) continue;
    final pc = pieces[i];
    final inTerminal = terminalBoxes.any((tb) => pc.pts.every((p) => tb.has(p, _tol * 0.5)));
    if (!dotPieces.contains(i) && !inTerminal) continue;
    final xs = pc.pts.map((p) => p.x), ys = pc.pts.map((p) => p.y);
    final c = Pt((xs.reduce(math.max) + xs.reduce(math.min)) / 2, (ys.reduce(math.max) + ys.reduce(math.min)) / 2);
    final size = math.max(xs.reduce(math.max) - xs.reduce(math.min), ys.reduce(math.max) - ys.reduce(math.min));
    // A dot is a blob (scribbled, or closed on itself); a short dash next to
    // a wire (a switch lever, a tick) is neither and stays as drawn.
    var len = 0.0;
    for (var k = 1; k < pc.pts.length; k++) {
      len += (pc.pts[k] - pc.pts[k - 1]).len;
    }
    final blob = (pc.pts.first - pc.pts.last).len < 0.5 * size || len >= 2.2 * size;
    // A port ring is small; a big circle in a "terminal" box is a symbol.
    if (!blob || size > math.max(14.0, 0.3 * unit)) continue;
    (_hollow(pc.pts, size) ? rings : dots).add(onWire(c, size / 2 + _tol));
    ringInk.add(i);
  }
  for (var i = 0; i < pieces.length; i++) {
    if (straight[i] == null || !live.contains(dsu.find(i))) continue;
    for (final (c, size) in _loops(pieces[i].pts, unit)) {
      (size >= 6 ? rings : dots).add(onWire(c, 0.2 * unit + _tol));
    }
  }
  for (final j in ringInk) {
    removed.addAll(pieces[j].drawn.map((d) => d.source));
  }
  final terminalPts = [for (final ts in terminalsOf.values) ...ts];
  final replaced = _Grid([for (var si = 0; si < strokes.length; si++) removed.contains(si) ? strokes[si] : null]);
  for (final si in specks) {
    final p = strokes[si].first;
    // On the drawing being replaced (or its terminals): sweep it away.
    final onOld = replaced.near(p, _tol).any((k) => _polyDist(p, strokes[k]) <= _tol);
    if (onOld || terminalPts.any((t) => (t - p).len <= _tol)) removed.add(si);
  }
  // CircuiTikZ's ocirc/circ, radius 0.04 R.
  final ringR = 0.04 * rl, dotR = 0.04 * rl;
  for (final c in rings) {
    added.add(OutStroke.line(_circle(c, ringR, 20)));
  }
  for (final c in dots) {
    added.add(OutStroke.fill(_circle(c, dotR, 16)));
  }
  // Short stubs hanging off a part with a free end (an arrow head on a wire,
  // a subscript next to it) are not wires: they stay as drawn.
  bool stub(int i) {
    final st = straight[i]!;
    if (runLength(pieces[i].pts) >= _tol * 2) return false;
    for (final isEnd in [false, true]) {
      if (attach.containsKey((i, isEnd))) continue;
      final e = isEnd ? st.last : st.first;
      if (nodes.any((n) => n.has(e, _tol))) continue;
      final touches = [
        for (final j in wireGrid.near(e, _tol))
          if (j != i && straight[j] != null && _polyDist(e, straight[j]!) <= _tol) j
      ];
      if (touches.isEmpty) return true;
    }
    return false;
  }

  // A ring drawn bigger than the detector's box leaves arcs outside it: the
  // redrawn source replaces those too.
  bool ringArc(int i) {
    if (wirelike[i]) return false;
    for (var c = 0; c < comps.length; c++) {
      if (!_sources.contains(kindOf[c]) || !terminalsOf.containsKey(c)) continue;
      final b = cbox[c], mid = Pt(b.cx, b.cy), r = 0.5 * math.min(b.x1 - b.x0, b.y1 - b.y0);
      if (pieces[i].pts.every((p) => (p - mid).len >= 0.7 * r && (p - mid).len <= 1.5 * r)) return true;
    }
    return false;
  }

  // Ends of the wires actually drawn; one collapsed to nothing joins nothing.
  final drawnEnds = <Pt>[];
  for (var i = 0; i < pieces.length; i++) {
    if (ringInk.contains(i) || ringArc(i)) continue;
    final s = straight[i];
    if (live.contains(dsu.find(i)) && s != null) {
      if (!stub(i)) {
        var parts = [_orthogonal(s)];
        for (final c in rings) {
          parts = [for (final pl in parts) ..._cutCircle(pl, c, ringR)];
        }
        for (final pl in parts) {
          // A run collapsed to a point (both ends on one terminal) would
          // render as a stray dot.
          if (runLength(pl) >= 1.5) {
            added.add(OutStroke(pl, pieces[i].source, true));
            drawnEnds.addAll([pl.first, pl.last]);
          }
        }
        continue;
      }
    }
    for (final d in pieces[i].drawn) {
      if (removed.contains(d.source)) added.add(OutStroke(d.pts, d.source));
    }
  }

  // Parts drawn touching, with no wire between: join their facing terminals.
  final straightEnds = drawnEnds;
  final tlist = [for (final e in terminalsOf.entries) for (final t in e.value) (e.key, t)];
  for (var a = 0; a < tlist.length; a++) {
    for (var b = a + 1; b < tlist.length; b++) {
      final (ca, ta) = tlist[a];
      final (cb, tb) = tlist[b];
      if (ca == cb || (ta - tb).len > _tol * 2.5 || (ta - tb).len < 0.5) continue;
      if (straightEnds.any((w) => (w - ta).len <= _tol) && straightEnds.any((w) => (w - tb).len <= _tol)) continue;
      final dx = (ta.x - tb.x).abs(), dy = (ta.y - tb.y).abs();
      final mid = dy >= dx ? Pt(ta.x, (ta.y + tb.y) / 2) : Pt((ta.x + tb.x) / 2, ta.y);
      final mid2 = dy >= dx ? Pt(tb.x, mid.y) : Pt(mid.x, tb.y);
      added.add(OutStroke([ta, mid, mid2, tb], -1, true));
    }
  }

  final nets = {for (var i = 0; i < pieces.length; i++) dsu.find(i)}.length;
  return CircuitRewrite(removed, _joinLines(_dropCovered(_tidyEnds(added))), comps, nets, rl);
}

/// Drops end hairs under 3 px and makes ends within 2 px of a crossing line
/// meet it: both show as ticks at nodes.
List<OutStroke> _tidyEnds(List<OutStroke> added) {
  bool thin(OutStroke o) => o.clean && !o.body && !o.fill && o.points.length >= 2;
  bool hook(Pt end, Pt corner, Pt before) {
    final a = end - corner, b = corner - before;
    if (a.len == 0 || a.len > 3 || b.len == 0) return false;
    return ((a.x * b.x + a.y * b.y) / (a.len * b.len)).abs() < 0.5;
  }

  final out = [...added];
  for (var i = 0; i < out.length; i++) {
    final o = out[i];
    if (!thin(o) || o.points.length < 3) continue;
    var p = o.points;
    if (hook(p[0], p[1], p[2])) p = p.sublist(1);
    if (p.length >= 3 && hook(p.last, p[p.length - 2], p[p.length - 3])) p = p.sublist(0, p.length - 1);
    if (p.length != o.points.length) out[i] = OutStroke.reshaped(o, p);
  }
  for (var i = 0; i < out.length; i++) {
    if (!thin(out[i])) continue;
    final p = [...out[i].points];
    var moved = false;
    for (final atEnd in [false, true]) {
      final ei = atEnd ? p.length - 1 : 0, e = p[ei], n = p[atEnd ? p.length - 2 : 1];
      final level = (e.y - n.y).abs() < 0.5 && (e.x - n.x).abs() > 0;
      final upright = (e.x - n.x).abs() < 0.5 && (e.y - n.y).abs() > 0;
      if (!level && !upright) continue;
      for (var j = 0; j < out.length && p[ei] == e; j++) {
        if (j == i || !thin(out[j])) continue;
        final q = out[j].points;
        for (var k = 0; k + 1 < q.length; k++) {
          final a = q[k], b = q[k + 1];
          // The crossing line runs the other way and spans this end.
          final off = level ? a.x - e.x : a.y - e.y;
          final run = level ? (a.x - b.x).abs() < 0.5 : (a.y - b.y).abs() < 0.5;
          final at = level ? e.y : e.x, lo = level ? math.min(a.y, b.y) : math.min(a.x, b.x);
          final hi = level ? math.max(a.y, b.y) : math.max(a.x, b.x);
          final span = level ? (e.x - n.x).abs() : (e.y - n.y).abs();
          if (!run || off == 0 || off.abs() > 2 || off.abs() >= span || at < lo - 0.5 || at > hi + 0.5) continue;
          p[ei] = level ? Pt(a.x, e.y) : Pt(e.x, a.y);
          moved = true;
          break;
        }
      }
    }
    if (moved) out[i] = OutStroke.reshaped(out[i], p);
  }
  return out;
}

/// Thin lines lying wholly on another (a wire drawn twice, a stub along the
/// run it joins) go: overlapping anti-aliased lines draw darker.
List<OutStroke> _dropCovered(List<OutStroke> added) {
  bool thin(OutStroke o) => o.clean && !o.body && !o.fill && o.points.length >= 2;
  double length(List<Pt> p) {
    var len = 0.0;
    for (var k = 1; k < p.length; k++) {
      len += (p[k] - p[k - 1]).len;
    }
    return len;
  }

  final grid = _Grid([for (final o in added) thin(o) ? o.points : null]);
  final lens = [for (final o in added) length(o.points)];
  final drop = <int>{};
  for (var i = 0; i < added.length; i++) {
    if (!thin(added[i])) continue;
    final p = added[i].points;
    final probe = [...p, for (var k = 1; k < p.length; k++) (p[k] + p[k - 1]) * 0.5];
    for (final j in grid.near(p.first, 0.5)) {
      if (j == i || drop.contains(j) || lens[j] < lens[i] || (lens[j] == lens[i] && j > i)) continue;
      if (probe.every((q) => _polyDist(q, added[j].points) <= 0.05)) {
        drop.add(i);
        break;
      }
    }
  }
  return [for (var i = 0; i < added.length; i++) if (!drop.contains(i)) added[i]];
}

/// Thin clean lines meeting end to end, two at a point (a wire running into
/// a lead, a corner), become one polyline: a real join instead of two
/// overlapping anti-aliased ends. Tees, and lines with a slant (a BJT's
/// leads, a ring), stay as they are.
List<OutStroke> _joinLines(List<OutStroke> added) {
  (int, int) key(Pt p) => ((p.x * 1000).round(), (p.y * 1000).round());
  bool square(List<Pt> p) => [
        for (var k = 1; k < p.length; k++) (p[k].x - p[k - 1].x).abs() < 1e-6 || (p[k].y - p[k - 1].y).abs() < 1e-6
      ].every((b) => b);
  bool thin(OutStroke o) => o.clean && !o.body && !o.fill && o.points.length >= 2 && square(o.points);
  final at = <(int, int), List<(int, bool)>>{};
  for (var i = 0; i < added.length; i++) {
    if (!thin(added[i])) continue;
    for (final isEnd in [false, true]) {
      (at[key(isEnd ? added[i].points.last : added[i].points.first)] ??= []).add((i, isEnd));
    }
  }
  final used = <int>{};
  // From end [isEnd] of stroke [i], the strokes beyond it in order, each
  // with the end it is entered by; stops at a tee, a free end or a loop.
  List<(int, bool)> walk(int i, bool isEnd) {
    final out = <(int, bool)>[];
    var cur = (i, isEnd);
    while (true) {
      final ends = at[key(cur.$2 ? added[cur.$1].points.last : added[cur.$1].points.first)]!;
      if (ends.length != 2) return out;
      final n = ends.firstWhere((e) => e != cur);
      if (used.contains(n.$1)) return out;
      used.add(n.$1);
      out.add(n);
      cur = (n.$1, !n.$2);
    }
  }

  List<Pt> leaving((int, bool) e) {
    final p = added[e.$1].points;
    return (e.$2 ? p.reversed : p).skip(1).toList();
  }

  final out = <OutStroke>[];
  for (var i = 0; i < added.length; i++) {
    final o = added[i];
    if (!thin(o)) {
      out.add(o);
      continue;
    }
    if (!used.add(i)) continue;
    final fwd = walk(i, true), back = walk(i, false);
    if (fwd.isEmpty && back.isEmpty) {
      out.add(o);
      continue;
    }
    final behind = [for (final e in back) ...leaving(e)];
    final pts = [...behind.reversed, ...o.points, for (final e in fwd) ...leaving(e)];
    final members = [i, for (final e in [...fwd, ...back]) e.$1];
    final wire = members.map((k) => added[k]).where((m) => m.wire).firstOrNull;
    out.add(wire != null ? OutStroke(pts, wire.source, true) : OutStroke.line(pts));
  }
  return out;
}

/// Clean symbol between terminals [s] and [e] (axis-aligned), drawn as
/// CircuiTikZ draws it for basic length [rl]: the body centred between the
/// terminals, leads filling the rest. [flip]: the dc source's or battery's
/// plus, or the diode's cathode, sits at [s]; for a switch, the lever leans
/// to the left normal. [arrow]: a current source's direction on the page.
/// [diamond]: a controlled source, CircuiTikZ's 0.7 R diamond.
List<OutStroke> _symbol(String cls, Pt s, Pt e, double rl, {bool flip = false, Pt? arrow, bool diamond = false}) {
  final d = e - s;
  final u = d * (1 / d.len);
  final v = Pt(-u.y, u.x);
  final c = (s + e) * 0.5;
  double bodyHalf(double len) => _bodyHalf(cls, len) * (diamond ? 0.35 / 0.3 : 1);
  // Terminals too close for the body: the whole symbol shrinks.
  final full = bodyHalf(rl);
  final r = full > 0 ? rl * math.min(1.0, d.len * 0.42 / full) : rl;
  final half = bodyHalf(r);
  Pt at(double t, double o) => c + u * t + v * o; // t: along the axis from the centre
  final leads = [
    OutStroke.line([s, at(-half, 0)]),
    OutStroke.line([at(half, 0), e]),
  ];
  switch (cls) {
    case 'resistor.box':
      final h = 0.15 * r;
      return [
        ...leads,
        OutStroke.line([at(-half, -h), at(half, -h), at(half, h), at(-half, h), at(-half, -h)], body: true),
      ];
    case 'resistor':
      // Three zigs: six peaks 0.15 R off the axis.
      final amp = 0.15 * r;
      return [
        ...leads,
        OutStroke.line([
          at(-half, 0),
          for (var k = 0; k < 6; k++) at(-half + (k + 0.5) * half / 3, k.isEven ? amp : -amp),
          at(half, 0),
        ], body: true),
      ];
    case 'capacitor':
    case 'voltage.battery':
      // A battery's long plate is its plus.
      final h = 0.3 * r;
      final hs = cls == 'capacitor' ? h : (flip ? h : h * 0.5), he = cls == 'capacitor' ? h : (flip ? h * 0.5 : h);
      return [
        ...leads,
        OutStroke.line([at(-half, -hs), at(-half, hs)], body: true),
        OutStroke.line([at(half, -he), at(half, he)], body: true),
      ];
    case 'diode':
      final hw = 0.25 * r;
      final base = flip ? half : -half, tip = -base;
      return [
        ...leads,
        OutStroke.line([at(base, -hw), at(base, hw), at(tip, 0), at(base, -hw)], body: true),
        OutStroke.line([at(tip, -hw), at(tip, hw)], body: true),
      ];
    case 'switch':
      return [
        ...leads,
        OutStroke.line([at(-half, 0), at(half * 0.9, 0.15 * r * (flip ? 1 : -1))], body: true),
      ];
    case 'inductor':
      // The "cute inductor": five coils, the turns between them looping back
      // under the axis.
      const coils = 5;
      final small = 0.0375 * r, big = (2 * half + (coils - 1) * 2 * small) / coils / 2;
      final pts = [at(-half, 0)];
      var x = -half;
      for (var k = 0; k < coils; k++) {
        for (var j = 1; j <= 12; j++) {
          final a = math.pi - math.pi * j / 12;
          pts.add(at(x + big + big * math.cos(a), -0.15 * r * math.sin(a)));
        }
        x += 2 * big;
        if (k == coils - 1) break;
        for (var j = 1; j <= 8; j++) {
          final a = -math.pi * j / 8;
          pts.add(at(x - small + small * math.cos(a), -0.075 * r * math.sin(a)));
        }
        x -= 2 * small;
      }
      return [...leads, OutStroke.line(pts, body: true)];
    default:
      if (_sources.contains(cls)) {
        final marks = <OutStroke>[];
        if (cls == 'voltage.dc') {
          // Signs sit on the axis, upright on the page whatever the axis.
          final pc = c + u * (0.126 * r * (flip ? -1 : 1));
          final mc = c + u * (0.126 * r * (flip ? 1 : -1));
          final m = 0.08 * r;
          marks
            ..add(OutStroke.line([Pt(pc.x - m, pc.y), Pt(pc.x + m, pc.y)]))
            ..add(OutStroke.line([Pt(pc.x, pc.y - m), Pt(pc.x, pc.y + m)]))
            ..add(OutStroke.line([Pt(mc.x - m, mc.y), Pt(mc.x + m, mc.y)]));
        } else if (cls == 'current_source' && arrow != null && arrow.len > 0) {
          // Shaft across 0.7 of the ring, the head centred halfway out.
          final dir = arrow * (1 / arrow.len);
          final mid = c + dir * (0.5 * half);
          marks
            ..add(OutStroke.line([c - dir * (0.7 * half), mid], body: true))
            ..add(_arrowHead(mid, dir, r));
        } else if (cls == 'voltage.ac') {
          marks.add(OutStroke.line([
            for (var k = 0; k <= 24; k++)
              Pt(c.x - 0.15 * r + 0.3 * r * k / 24, c.y - 0.075 * r * math.sin(2 * math.pi * k / 24)),
          ], body: true));
        }
        final outline = diamond ? [at(-half, 0), at(0, half), at(half, 0), at(0, -half), at(-half, 0)] : _circle(c, half, 48);
        return [...leads, OutStroke.line(outline, body: true), ...marks];
      }
      return [
        OutStroke.line([s, e]),
      ];
  }
}

/// CircuiTikZ's filled current arrow (`currarrow`) centred on [mid], pointing
/// along the unit vector [dir], for basic length [rl].
OutStroke _arrowHead(Pt mid, Pt dir, double rl) {
  final w = rl / 16;
  final side = Pt(-dir.y, dir.x);
  final tip = mid + dir * w, tail = mid - dir * (0.7 * w);
  return OutStroke.fill([tip, tail + side * (0.8 * w), tail - side * (0.8 * w), tip]);
}

/// CircuiTikZ's vcc arrow: an open head with its tip at [apex], pointing up
/// for [dir] -1 (down for 1).
List<OutStroke> _supplyArrow(Pt apex, int dir, double rl) {
  final w = 0.12 * rl, h = 0.15 * rl;
  return [
    OutStroke.line([Pt(apex.x - w, apex.y - dir * h), apex, Pt(apex.x + w, apex.y - dir * h)], body: true)
  ];
}

/// Whether ink capping a stem at [x] narrows to a tip on the stem's line,
/// going [dir] (-1 up, 1 down).
bool _pointsAway(List<List<Pt>> runs, double x, int dir) {
  final all = [for (final r in runs) ...r];
  if (all.length < 3) return false;
  final xs = all.map((p) => p.x), as = all.map((p) => p.y * dir);
  final w = xs.reduce(math.max) - xs.reduce(math.min);
  final a0 = as.reduce(math.min), a1 = as.reduce(math.max), h = a1 - a0;
  if (w < 3 || h < 3) return false;
  final tip = [for (final p in all) if (p.y * dir >= a1 - 0.3 * h) p.x];
  final mid = tip.reduce((a, v) => a + v) / tip.length;
  return tip.reduce(math.max) - tip.reduce(math.min) <= 0.6 * w && (mid - x).abs() <= 0.25 * w;
}

/// Level bars in ink capping a stem at [x] when it is mostly slanted (an
/// arrowhead: 0 open, 1 a triangle's base), else null (bars of a ground).
int? _headBars(List<List<Pt>> runs, double x) {
  if (_slantedShare(runs, x) < 0.3) return null;
  final pts = [for (final r in runs) ...r];
  if (pts.isEmpty) return null;
  final w = pts.map((p) => p.x).reduce(math.max) - pts.map((p) => p.x).reduce(math.min);
  final bars = <double>[];
  for (final raw in runs) {
    final r = _simplify(raw, 1);
    for (var i = 1; i < r.length; i++) {
      final d = r[i] - r[i - 1];
      if (d.x.abs() >= 0.5 * w && d.y.abs() < 0.27 * d.x.abs()) bars.add((r[i].y + r[i - 1].y) / 2);
    }
  }
  bars.sort();
  var levels = bars.isEmpty ? 0 : 1;
  for (var i = 1; i < bars.length; i++) {
    if (bars[i] - bars[i - 1] > 2) levels++;
  }
  return levels <= 1 ? levels : null;
}

/// Share of the ink's length running slanted, off the stem at [x].
double _slantedShare(List<List<Pt>> runs, double x) {
  var slant = 0.0, all = 0.0;
  for (final raw in runs) {
    final r = _simplify(raw, 1);
    for (var i = 1; i < r.length; i++) {
      final a = r[i - 1], b = r[i], d = b - a;
      if (d.len == 0 || ((a.x - x).abs() <= 1.5 && (b.x - x).abs() <= 1.5)) continue;
      all += d.len;
      final deg = math.atan2(d.y.abs(), d.x.abs()) * 180 / math.pi;
      if (deg > 15 && deg < 82) slant += d.len;
    }
  }
  return all == 0 ? 0 : slant / all;
}

/// Supply arrows and triangle grounds the detector missed: a head capping a
/// free upright wire end (rules in ml/circuits/README.md).
List<Detection> _withSupplyArrows(List<List<Pt>> strokes, List<Detection> dets) {
  final sizes = [
    for (final d in dets)
      if (!_nonComponent.contains(d.cls) && !_keepAsDrawn.contains(d.cls) && d.cls != 'gnd' && d.cls != 'opamp')
        math.max(d.x1 - d.x0, d.y1 - d.y0)
  ]..sort();
  final unit = sizes.isEmpty ? 50.0 : sizes[sizes.length ~/ 2].clamp(30.0, 90.0);
  final grid = _Grid(strokes);
  // Parts and annotation arrows; a label may sit right by a supply arrow.
  final taken = [
    for (final d in dets)
      if (d.cls == 'arrow' || !_nonComponent.contains(d.cls)) _Box.of(d)
  ];
  final texts = [
    for (final d in dets)
      if (d.cls == 'text') _Box.of(d)
  ];
  final out = [...dets];
  for (var si = 0; si < strokes.length; si++) {
    final st = strokes[si];
    if (st.length < 2) continue;
    for (final atEnd in [false, true]) {
      final pts = atEnd ? st.reversed.toList() : st;
      final e = pts.first;
      var arc = 0.0, k = 1;
      for (; k < pts.length && arc < 0.2 * unit; k++) {
        arc += (pts[k] - pts[k - 1]).len;
      }
      if (arc < 0.2 * unit) continue;
      final d = e - pts[k - 1];
      if (d.x.abs() > 0.3 * d.y.abs()) continue;
      final dir = d.y.sign;
      double along(Pt p) => (p.y - e.y) * dir;
      final ids = grid.box(e.x - 0.35 * unit, e.y - 0.5 * unit, e.x + 0.35 * unit, e.y + 0.5 * unit);
      final head = [
        for (final j in ids)
          if (j != si &&
              strokes[j].isNotEmpty &&
              strokes[j].every((p) => (p.x - e.x).abs() <= 0.35 * unit && along(p) >= -0.4 * unit && along(p) <= 0.5 * unit))
            strokes[j]
      ];
      if (head.isEmpty) continue;
      final all = [for (final h in head) ...h];
      final xs = all.map((p) => p.x), as = all.map(along);
      final x0 = xs.reduce(math.min), x1 = xs.reduce(math.max), w = x1 - x0;
      final a0 = as.reduce(math.min), a1 = as.reduce(math.max), h = a1 - a0;
      if (w < 0.08 * unit || w > 0.6 * unit || h < 0.08 * unit || a0 > 0.1 * unit) continue;
      if (x0 > e.x - 0.2 * w || x1 < e.x + 0.2 * w) continue;
      if (_headBars(head, e.x) == null || !_pointsAway(head, e.x, dir.round())) continue;
      // Writing is not a head ("1/" of a label), and the stem is a wire: its
      // other end meets the circuit.
      if (head.any((h) => h.where((p) => texts.any((t) => t.has(p))).length * 2 > h.length)) continue;
      final far = pts.last;
      final joined = taken.any((t) => t.has(far, _tol)) ||
          grid.box(far.x - _tol, far.y - _tol, far.x + _tol, far.y + _tol).any(
              (j) => j != si && !head.contains(strokes[j]) && strokes[j].any((p) => (p - far).len <= _tol));
      if (!joined) continue;
      // A supply arrow ends the wire: nothing but a label runs on past its
      // tip (an arrow drawn on a wire, a part's lead, does).
      final past = grid.box(e.x - 0.15 * unit, e.y - unit, e.x + 0.15 * unit, e.y + unit).any((j) =>
          j != si &&
          !head.contains(strokes[j]) &&
          strokes[j].any((p) =>
              (p.x - e.x).abs() <= 0.15 * unit &&
              along(p) > a1 + 1 &&
              along(p) <= a1 + 0.5 * unit &&
              !texts.any((t) => t.has(p))));
      if (past) continue;
      // The box takes in a little of the wire, so the wire enters it.
      final ys = all.map((p) => p.y);
      final stemY = e.y - dir * 0.1 * unit;
      final box = _Box(math.min(x0, e.x - 2), math.min(ys.reduce(math.min), stemY), math.max(x1, e.x + 2),
          math.max(ys.reduce(math.max), stemY));
      bool overlaps(_Box t) => t.x0 < box.x1 && box.x0 < t.x1 && t.y0 < box.y1 && box.y0 < t.y1;
      if (taken.any(overlaps)) continue;
      taken.add(box);
      out.add(Detection('gnd', 0.5, box.x0, box.y0, box.x1, box.y1));
    }
  }
  return out;
}

/// Box of the circle that curved strokes meeting [b] trace together, when
/// about the box's size; strokes off it are dropped worst first.
_Box? _ringFromArcs(List<List<Pt>> strokes, _Box b) {
  final side = math.min(b.x1 - b.x0, b.y1 - b.y0);
  final arcs = <List<Pt>>[];
  for (final st in strokes) {
    if (st.length < 4 || !st.any((p) => b.has(p))) continue;
    final xs = st.map((p) => p.x), ys = st.map((p) => p.y);
    final span = math.max(xs.reduce(math.max) - xs.reduce(math.min), ys.reduce(math.max) - ys.reduce(math.min));
    if (span < 0.4 * side || span > 1.6 * side) continue;
    if (st.every((p) => _segDist(p, st.first, st.last) < 0.1 * span)) continue; // straight
    arcs.add(_densify(st, 2));
  }
  while (arcs.length >= 2) {
    final c = _fitCircle([for (final a in arcs) ...a]);
    if (c == null) return null;
    final (centre, r) = c;
    double dev(Pt p) => ((p - centre).len - r).abs();
    final worst = [for (final a in arcs) a.map(dev).reduce(math.max)];
    final w = worst.indexOf(worst.reduce(math.max));
    if (worst[w] > 0.15 * r) {
      arcs.removeAt(w);
      continue;
    }
    if (r < 0.3 * side || r > 0.9 * side) return null;
    // Together they go most of the way round.
    final sectors = {
      for (final a in arcs)
        for (final p in a) ((math.atan2(p.y - centre.y, p.x - centre.x) + math.pi) / (math.pi / 6)).floor() % 12
    };
    if (sectors.length < 9) return null;
    return _Box(centre.x - r, centre.y - r, centre.x + r, centre.y + r);
  }
  return null;
}

/// Least-squares circle x^2 + y^2 + Dx + Ey + F = 0 through [pts].
(Pt, double)? _fitCircle(List<Pt> pts) {
  var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0, sz = 0.0, sxz = 0.0, syz = 0.0;
  for (final p in pts) {
    final z = p.x * p.x + p.y * p.y;
    sx += p.x;
    sy += p.y;
    sxx += p.x * p.x;
    syy += p.y * p.y;
    sxy += p.x * p.y;
    sz += z;
    sxz += p.x * z;
    syz += p.y * z;
  }
  final m = [
    [sxx, sxy, sx, -sxz],
    [sxy, syy, sy, -syz],
    [sx, sy, pts.length.toDouble(), -sz],
  ];
  for (var i = 0; i < 3; i++) {
    var piv = i;
    for (var r = i + 1; r < 3; r++) {
      if (m[r][i].abs() > m[piv][i].abs()) piv = r;
    }
    if (m[piv][i].abs() < 1e-9) return null;
    final t = m[i];
    m[i] = m[piv];
    m[piv] = t;
    for (var r = 0; r < 3; r++) {
      if (r == i) continue;
      final f = m[r][i] / m[i][i];
      for (var k = i; k < 4; k++) {
        m[r][k] -= f * m[i][k];
      }
    }
  }
  final cx = -m[0][3] / m[0][0] / 2, cy = -m[1][3] / m[1][1] / 2;
  final r2 = cx * cx + cy * cy - m[2][3] / m[2][2];
  return r2 <= 0 ? null : (Pt(cx, cy), math.sqrt(r2));
}

/// Whether a source's outline is a diamond (a controlled source) rather than
/// a ring: it has three or more straight sides, stretches of 0.9 radius
/// bowing under 0.06 radius, where a ring's arcs bow about 0.1. Thin ink (a
/// wire through the ring, the arrow inside) does not count.
bool _isDiamond(List<List<Pt>> runs, _Box b) {
  final r0 = 0.5 * math.min(b.x1 - b.x0, b.y1 - b.y0);
  var sides = 0;
  for (final raw in runs) {
    if (raw.length < 5) continue;
    final xs = raw.map((p) => p.x), ys = raw.map((p) => p.y);
    final w = xs.reduce(math.max) - xs.reduce(math.min), h = ys.reduce(math.max) - ys.reduce(math.min);
    // A wire or the arrow's shaft is thin one way; a side drawn on its own
    // spans about 0.7 radius both ways.
    if (math.sqrt(w * w + h * h) < 0.9 * r0 || math.min(w, h) < 0.35 * r0) continue;
    final p = _densify(raw, 1);
    var i = 0;
    while (i < p.length) {
      var end = -1;
      for (var j = i + 1; j < p.length; j++) {
        final span = (p[j] - p[i]).len;
        if (span > 3 * r0) break;
        if (span >= 0.9 * r0 && p.sublist(i, j + 1).every((q) => _segDist(q, p[i], p[j]) <= 0.06 * r0)) end = j;
      }
      if (end > 0) {
        sides++;
        i = end + 1;
      } else {
        i += 2;
      }
    }
  }
  return sides >= 3;
}

/// A rectangle (IEC resistor, impedance) leaves the middle of its outline
/// empty; a zigzag always crosses it.
bool _looksLikeBox(List<Pt> ink, _Box _) {
  if (ink.length < 8) return false;
  final x0 = ink.map((p) => p.x).reduce(math.min), x1 = ink.map((p) => p.x).reduce(math.max);
  final y0 = ink.map((p) => p.y).reduce(math.min), y1 = ink.map((p) => p.y).reduce(math.max);
  final cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
  final core = ink.where((p) => (p.x - cx).abs() < 0.2 * (x1 - x0) && (p.y - cy).abs() < 0.2 * (y1 - y0)).length;
  return core < 0.03 * ink.length;
}

/// Where segment [a]->[b] crosses the border of [box] (one end inside, one out).
Pt? _crossing(Pt a, Pt b, _Box box) {
  var t0 = 0.0, t1 = 1.0;
  final d = b - a;
  for (final (p, q) in [
    (-d.x, a.x - box.x0),
    (d.x, box.x1 - a.x),
    (-d.y, a.y - box.y0),
    (d.y, box.y1 - a.y),
  ]) {
    if (p == 0) {
      if (q < 0) return null;
      continue;
    }
    final t = q / p;
    if (p < 0) {
      if (t > t0) t0 = t;
    } else if (t < t1) {
      t1 = t;
    }
  }
  if (t0 > t1) return null;
  final t = box.has(a) ? t1 : t0;
  return a + d * t;
}

/// Points every [step] px along [pts], so shape tests see the segments too.
List<Pt> _densify(List<Pt> pts, double step) {
  if (pts.length < 2) return List.of(pts);
  final out = <Pt>[pts.first];
  for (var i = 1; i < pts.length; i++) {
    final d = pts[i] - pts[i - 1];
    final n = (d.len / step).ceil();
    for (var k = 1; k <= n; k++) {
      out.add(pts[i - 1] + d * (k / n));
    }
  }
  return out;
}

/// Half the length of a symbol's body along its axis, for basic length [rl].
double _bodyHalf(String cls, double rl) => switch (cls) {
      'resistor' || 'resistor.box' => 0.4 * rl,
      'capacitor' => 0.1 * rl,
      'voltage.battery' => 0.05 * rl,
      'inductor' => 0.3 * rl,
      'diode' => 0.2 * rl,
      'switch' => 0.175 * rl,
      _ when _sources.contains(cls) => 0.3 * rl,
      _ => 0,
    };

/// Shortest terminal-to-terminal length: the body plus a lead each side.
double _minLength(String cls, double rl) => 2 * _bodyHalf(cls, rl) + 0.38 * rl;

/// Whether the user's "+" sits in the half of the ring nearer [s]: a plus
/// has vertical extent on the page, a minus has none. Null when nothing
/// inside tells: an empty ring, or only the bar of an IEC source running
/// through the centre along the wire.
bool? _plusTowardStart(List<List<Pt>>? marks, Pt s, Pt e) {
  if (marks == null || marks.isEmpty) return null;
  final c = (s + e) * 0.5, u = e - s;
  final ul = u.len;
  var startScore = 0.0, endScore = 0.0;
  var any = false;
  for (final m in marks) {
    final along = m.map((p) => (p - c).dot(u) / ul);
    if (along.reduce(math.min) < -0.08 * ul && along.reduce(math.max) > 0.08 * ul) continue;
    any = true;
    final ys = m.map((p) => p.y);
    final xs = m.map((p) => p.x);
    // On a horizontal axis the plus is told apart by its vertical bar; on a
    // vertical one both signs have a horizontal bar, so the bar decides too.
    final extent = ys.reduce(math.max) - ys.reduce(math.min);
    final mid = Pt((xs.reduce(math.max) + xs.reduce(math.min)) / 2, (ys.reduce(math.max) + ys.reduce(math.min)) / 2);
    if ((mid - c).dot(u) < 0) {
      startScore += extent;
    } else {
      endScore += extent;
    }
  }
  return any ? startScore >= endScore : null;
}

/// A "+" or "-" written just outside the ring, beside a terminal: whether
/// the plus (or, failing one, opposite the minus) is on [s]'s side.
bool? _outsideSignTowardStart(List<List<Pt>> strokes, _Box b, Pt s, Pt e) {
  final c = Pt(b.cx, b.cy), u = e - s, ul = u.len;
  final r = 0.5 * math.max(b.x1 - b.x0, b.y1 - b.y0);
  // Small strokes just outside the ring, merged by proximity: a plus is
  // usually two strokes.
  final marks = <List<double>>[]; // x0, y0, x1, y1
  for (final st in strokes) {
    if (st.length < 2) continue;
    final xs = st.map((p) => p.x), ys = st.map((p) => p.y);
    final m = [xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max)];
    if (math.max(m[2] - m[0], m[3] - m[1]) > 0.8 * r) continue;
    final d = (Pt((m[0] + m[2]) / 2, (m[1] + m[3]) / 2) - c).len;
    if (d < 1.05 * r || d > 2.2 * r) continue;
    final near = marks.where((o) => math.max(o[0], m[0]) - math.min(o[2], m[2]) < 0.1 * r &&
        math.max(o[1], m[1]) - math.min(o[3], m[3]) < 0.1 * r).firstOrNull;
    if (near == null) {
      marks.add(m);
    } else {
      near.setAll(0, [math.min(near[0], m[0]), math.min(near[1], m[1]), math.max(near[2], m[2]), math.max(near[3], m[3])]);
    }
  }
  // The sign sits beside a terminal: past the ring's middle along the axis,
  // not as far as the next part, and close across it. Nearest one wins.
  double? plusAlong, minusAlong;
  var plusD = double.infinity, minusD = double.infinity;
  for (final m in marks) {
    final w = m[2] - m[0], h = m[3] - m[1];
    if (math.max(w, h) < 0.15 * r) continue;
    final mid = Pt((m[0] + m[2]) / 2, (m[1] + m[3]) / 2) - c;
    final along = mid.dot(u) / ul, across = (mid - u * (along / ul)).len;
    if (along.abs() < 0.4 * r || along.abs() > 1.3 * r || across > 1.4 * r) continue;
    final d = mid.len;
    if (math.min(w, h) > 0.45 * math.max(w, h)) {
      if (d < plusD) (plusD, plusAlong) = (d, along);
    } else if (d < minusD) {
      (minusD, minusAlong) = (d, along);
    }
  }
  if (plusAlong != null) return plusAlong < 0;
  if (minusAlong != null) return minusAlong > 0;
  return null;
}

/// Snaps components whose axes nearly line up onto one shared line, so the
/// wire between two stacked parts comes out straight.
void _alignAxes(Map<int, (bool, double)> axisOf) {
  for (final vertical in [true, false]) {
    final ids = axisOf.keys.where((c) => axisOf[c]!.$1 == vertical).toList()
      ..sort((a, b) => axisOf[a]!.$2.compareTo(axisOf[b]!.$2));
    var group = <int>[];
    void close() {
      if (group.length > 1) {
        final mean = group.map((c) => axisOf[c]!.$2).reduce((a, v) => a + v) / group.length;
        for (final c in group) {
          axisOf[c] = (vertical, mean);
        }
      }
      group = <int>[];
    }

    for (final c in ids) {
      if (group.isNotEmpty && axisOf[c]!.$2 - axisOf[group.last]!.$2 > _tol * 1.6) close();
      group.add(c);
    }
    close();
  }
}

/// Joins pieces that continue each other (a wire lifted at a corner, a hook
/// at its end) into one polyline, so each straightens as a single run. Only
/// free ends with exactly one partner nearby join: a T or a three-way node
/// keeps its pieces apart.
void _chainPieces(List<_Piece> pieces, List<_Box> cbox, double unit) {
  // Outward direction at an end, or null when the piece leaves it at a slant
  // (a switch lever, an arrow head) rather than along an axis.
  Pt? axisDir((int, bool) k) {
    final pts = k.$2 ? pieces[k.$1].pts.reversed.toList() : pieces[k.$1].pts;
    final d = pts.first - _along(pts, _dirLen);
    if (d.len < 3) return null;
    final ax = d.x.abs(), ay = d.y.abs();
    if (math.min(ax, ay) > 0.5 * math.max(ax, ay)) return null;
    return ax >= ay ? Pt(d.x.sign, 0) : Pt(0, d.y.sign);
  }

  // A corner (perpendicular ends) or a lifted pen on a straight run (facing
  // ends on one line); anything else, like a parallel stroke alongside, stays
  // apart.
  double length(_Piece pc) {
    var l = 0.0;
    for (var k = 1; k < pc.pts.length; k++) {
      l += (pc.pts[k] - pc.pts[k - 1]).len;
    }
    return l;
  }

  bool joins((int, bool) x, (int, bool) y, Pt a, Pt b) {
    if ((a - b).len > _tol * 2) return false;
    // Two short dashes are a dashed line, not a wire lifted mid-run.
    if (math.max(length(pieces[x.$1]), length(pieces[y.$1])) < 0.5 * unit) return false;
    final da = axisDir(x), db = axisDir(y);
    if (da == null || db == null) return false;
    if (da.dot(db) == 0) return true;
    final g = b - a;
    final lateral = (da.x != 0 ? g.y : g.x).abs();
    return da.dot(db) < 0 && lateral <= _tol && da.dot(g) >= -_tol;
  }

  // Link every free end to its single partner, all at once, then walk the
  // links into chains; repeat, since a chain's new ends may pair up too.
  while (true) {
    final grid = _Grid([for (final pc in pieces) pc.pts]);
    bool free(Pt e, int self) {
      if (cbox.any((b) => b.has(e, _tol + 2))) return false;
      for (final j in grid.near(e, _tol)) {
        if (j == self) continue;
        final pj = pieces[j];
        // Landing near the other wire's end is a corner, not a T.
        if (_polyDist(e, pj.pts) <= _tol && (e - pj.a).len > 2 * _tol && (e - pj.b).len > 2 * _tol) return false;
      }
      return true;
    }

    Pt at((int, bool) k) => k.$2 ? pieces[k.$1].b : pieces[k.$1].a;
    final ends = <(int, bool)>[
      for (var i = 0; i < pieces.length; i++)
        for (final isEnd in [false, true])
          if (free(isEnd ? pieces[i].b : pieces[i].a, i)) (i, isEnd),
    ];
    final endGrid = _Grid([for (final k in ends) [at(k)]]);
    List<(int, bool)> partners((int, bool) x) => [
          for (final n in endGrid.near(at(x), _tol * 2))
            if (ends[n].$1 != x.$1 && (at(ends[n]) - at(x)).len <= _tol * 2) ends[n]
        ];
    final link = <(int, bool), (int, bool)>{};
    for (final x in ends) {
      if (link.containsKey(x)) continue;
      final px = partners(x);
      if (px.length != 1 || link.containsKey(px.single)) continue;
      final y = px.single;
      if (partners(y).length != 1 || !joins(x, y, at(x), at(y))) continue;
      link[x] = y;
      link[y] = x;
    }
    if (link.isEmpty) return;

    final used = <int>{};
    final out = <_Piece>[];
    void walk(int start) {
      // Enter through the end that has no link (or any, on a closed loop).
      var cur = start, forward = !link.containsKey((start, false));
      final pts = <Pt>[], drawn = <_Piece>[];
      while (used.add(cur)) {
        final pc = pieces[cur];
        pts.addAll(forward ? pc.pts : pc.pts.reversed);
        drawn.addAll(pc.drawn);
        final next = link[(cur, forward)];
        if (next == null) break;
        cur = next.$1;
        forward = !next.$2;
      }
      out.add(drawn.length == 1 ? pieces[start] : _Piece(pts, pieces[start].source, drawn));
    }

    for (var i = 0; i < pieces.length; i++) {
      if (!used.contains(i) && !(link.containsKey((i, false)) && link.containsKey((i, true)))) walk(i);
    }
    for (var i = 0; i < pieces.length; i++) {
      if (!used.contains(i)) walk(i);
    }
    pieces
      ..clear()
      ..addAll(out);
  }
}

/// Collapses overlapping source detections (one ring read as both a dc and a
/// current source) into the best-scored one, remembering every kind it got.
/// Any other part read as two kinds in one place (a transistor scored both
/// fet and bjt) keeps only its best reading.
(List<Detection>, Map<int, Set<String>>) _mergeSources(List<Detection> comps) {
  double iou(Detection a, Detection b) {
    final w = math.min(a.x1, b.x1) - math.max(a.x0, b.x0), h = math.min(a.y1, b.y1) - math.max(a.y0, b.y0);
    if (w <= 0 || h <= 0) return 0;
    return w * h / (a.width * a.height + b.width * b.height - w * h);
  }

  final out = <Detection>[];
  final kinds = <int, Set<String>>{};
  final sorted = [...comps]..sort((a, b) => b.score.compareTo(a.score));
  for (final d in sorted) {
    if (_sources.contains(d.cls)) {
      final k = out.indexWhere((o) => _sources.contains(o.cls) && iou(o, d) > 0.5);
      if (k >= 0) {
        (kinds[k] ??= {out[k].cls}).add(d.cls);
        continue;
      }
    } else if (out.any((o) => !_sources.contains(o.cls) && o.cls != d.cls && iou(o, d) > 0.6)) {
      continue;
    }
    out.add(d);
  }
  return (out, kinds);
}

/// Page direction of an arrow drawn inside a ring of radius [r], or null if
/// the marks are not one: a shaft at least ~0.6 r long with a head at one end
/// (the detector's box can run well past a small ring).
Pt? _arrowDir(List<List<Pt>>? marks, Pt c, double r) {
  if (marks == null || marks.isEmpty) return null;
  var best = 0.0;
  var vertical = true;
  List<Pt>? shaft;
  for (final m in marks) {
    final xs = m.map((p) => p.x), ys = m.map((p) => p.y);
    final w = xs.reduce(math.max) - xs.reduce(math.min), h = ys.reduce(math.max) - ys.reduce(math.min);
    if (math.max(w, h) > best) {
      best = math.max(w, h);
      vertical = h >= w;
      shaft = m;
    }
  }
  if (best < 0.6 * r) return null;
  // A shaft runs through the middle of the symbol; the bar of a "+" sits in
  // one half of it.
  final ends = shaft!.map((p) => vertical ? p.y - c.y : p.x - c.x);
  if (ends.reduce(math.min) > -0.25 * r || ends.reduce(math.max) < 0.25 * r) return null;
  // The head is the end where the ink spreads widest across the shaft.
  final all = [for (final m in marks) ...m];
  double along(Pt p) => vertical ? p.y : p.x;
  double across(Pt p) => vertical ? p.x : p.y;
  final lo = all.map(along).reduce(math.min), hi = all.map(along).reduce(math.max);
  double spread(bool high) {
    final near = all.where((p) => high ? along(p) > hi - 0.3 * (hi - lo) : along(p) < lo + 0.3 * (hi - lo));
    if (near.isEmpty) return 0;
    return near.map(across).reduce(math.max) - near.map(across).reduce(math.min);
  }

  final up = spread(false), down = spread(true);
  if ((up - down).abs() < 0.08 * r) return null;
  final sign = down > up ? 1.0 : -1.0;
  return vertical ? Pt(0, sign) : Pt(sign, 0);
}

/// Whether the diode's bar sits toward [s]: the triangle's wide base half
/// spreads more ink across the axis than the half with its tip.
bool _cathodeAtStart(List<Pt> ink, Pt s, Pt e) {
  if (ink.length < 8) return false;
  final u = (e - s) * (1 / (e - s).len), v = Pt(-u.y, u.x);
  final ts = ink.map((p) => (p - s).dot(u)).toList();
  final lo = ts.reduce(math.min), hi = ts.reduce(math.max), span = hi - lo;
  if (span <= 0) return false;
  double spread(double f0, double f1) {
    var total = 0.0;
    var bins = 0;
    for (var f = f0; f < f1 - 1e-9; f += 0.05) {
      final off = [
        for (var i = 0; i < ink.length; i++)
          if (ts[i] >= lo + f * span && ts[i] < lo + (f + 0.05) * span) (ink[i] - s).dot(v)
      ];
      if (off.isEmpty) continue;
      total += off.reduce(math.max) - off.reduce(math.min);
      bins++;
    }
    return bins == 0 ? 0 : total / bins;
  }

  return spread(0.15, 0.5) < spread(0.5, 0.85);
}

/// [pts] with a corner put in wherever two points are not level or plumb
/// (an end moved onto another wire), keeping the earlier run's direction.
List<Pt> _orthogonal(List<Pt> pts) {
  final out = <Pt>[pts.first];
  for (var k = 1; k < pts.length; k++) {
    final a = out.last, b = pts[k];
    if ((a.x - b.x).abs() > 0.5 && (a.y - b.y).abs() > 0.5) {
      final horizontal = out.length >= 2 ? (out[out.length - 2].y - a.y).abs() < 0.5 : (b.x - a.x).abs() >= (b.y - a.y).abs();
      out.add(horizontal ? Pt(b.x, a.y) : Pt(a.x, b.y));
    }
    out.add(b);
  }
  return out;
}

/// Mostly straight runs along the axes, as wires are drawn, and not a zigzag.
bool _wirelike(List<Pt> pts, double unit) {
  final simp = _simplify(pts, math.max(2.5, 0.06 * unit));
  var total = 0.0, aligned = 0.0;
  for (var k = 0; k + 1 < simp.length; k++) {
    final d = simp[k + 1] - simp[k];
    total += d.len;
    // Within ~20 degrees of horizontal or vertical.
    if (math.min(d.x.abs(), d.y.abs()) <= 0.36 * math.max(d.x.abs(), d.y.abs())) aligned += d.len;
  }
  if (total < 0.4 * unit) return true;
  return aligned >= 0.75 * total && !_wiggly(pts);
}

/// Sharp turns between short legs, alternating left and right: a zigzag (an
/// undetected resistor). A ring drawn into a wire turns one way only.
bool _wiggly(List<Pt> pts) {
  final simp = _simplify(pts, 2);
  var run = 0, best = 0;
  double last = 0;
  for (var k = 1; k + 1 < simp.length; k++) {
    final a = simp[k] - simp[k - 1], b = simp[k + 1] - simp[k];
    if (a.len < 2 || b.len < 2) continue;
    if (math.max(a.len, b.len) > 25 || a.dot(b) >= 0.34 * a.len * b.len) {
      run = 0;
      continue;
    }
    final turn = (a.x * b.y - a.y * b.x).sign;
    run = run > 0 && turn == -last ? run + 1 : 1;
    last = turn;
    best = math.max(best, run);
  }
  return best >= 4;
}

/// A "capacitor" whose plates differ clearly in length is a battery cell.
bool _unevenPlates(List<Pt> ink, bool vertical) {
  if (ink.length < 8) return false;
  // Plates run across the axis: group ink by position along it.
  double along(Pt p) => vertical ? p.y : p.x;
  double across(Pt p) => vertical ? p.x : p.y;
  final lo = ink.map(along).reduce(math.min), hi = ink.map(along).reduce(math.max);
  final mid = (lo + hi) / 2;
  double width(bool first) {
    final a = [for (final p in ink) if ((along(p) < mid) == first) across(p)];
    return a.isEmpty ? 0 : a.reduce(math.max) - a.reduce(math.min);
  }

  final w1 = width(true), w2 = width(false);
  return math.max(w1, w2) > 1.6 * math.min(w1, w2) && math.min(w1, w2) > 2;
}

/// A small closed loop drawn once around (a port ring) rather than scribbled
/// full (a junction dot) or too tiny to be either.
bool _hollow(List<Pt> pts, double size) {
  // A tiny closed stroke of its own is a junction dot: the pen's width fills
  // it. Port rings come larger, or drawn into the wire (see [_loops]).
  // Page-normalized pixels: pen marks keep their size whatever the parts'.
  if (size < 8.5 || pts.length < 4) return false;
  var len = 0.0;
  for (var k = 1; k < pts.length; k++) {
    len += (pts[k] - pts[k - 1]).len;
  }
  return (pts.first - pts.last).len < 0.5 * size && len < 4.5 * size;
}

/// Coils the detector missed (loops it scores low, or reads as a transistor),
/// found in the ink: three or more small loops in a row along one stroke,
/// each closed by the stroke crossing itself, alike in size and lined up
/// along an axis, with a straight wire running on from the coil. Cursive
/// writing, a port ring or a scribbled dot fail one of these. Each becomes
/// an inductor detection, replacing a part read on top of it and stopping
/// short of a part next to it.
List<Detection> _withCoils(List<List<Pt>> strokes, List<Detection> dets) {
  final sizes = [
    for (final d in dets)
      if (!_nonComponent.contains(d.cls) && !_keepAsDrawn.contains(d.cls) && d.cls != 'gnd' && d.cls != 'opamp')
        math.max(d.x1 - d.x0, d.y1 - d.y0)
  ]..sort();
  final unit = sizes.isEmpty ? 50.0 : sizes[sizes.length ~/ 2].clamp(30.0, 90.0);
  final grid = _Grid(strokes);
  final coils = <_Box>[];
  for (final p in strokes) {
    if (p.length < 8) continue;
    final arc = List<double>.filled(p.length, 0);
    for (var k = 1; k < p.length; k++) {
      arc[k] = arc[k - 1] + (p[k] - p[k - 1]).len;
    }
    // Small loops: (first index, last index, centre, size).
    final loops = <(int, int, Pt, double)>[];
    var i = 0;
    while (i < p.length - 1) {
      var next = i + 1;
      for (var j = i + 2; j < p.length - 1 && arc[j] - arc[i] <= 1.2 * unit; j++) {
        if (!_segmentsCross(p[i], p[i + 1], p[j], p[j + 1])) continue;
        final loop = p.sublist(i + 1, j + 1);
        final xs = loop.map((q) => q.x), ys = loop.map((q) => q.y);
        final w = xs.reduce(math.max) - xs.reduce(math.min), h = ys.reduce(math.max) - ys.reduce(math.min);
        if (math.max(w, h) <= 0.6 * unit && math.min(w, h) >= 0.04 * unit) {
          loops.add((i, j, Pt((xs.reduce(math.max) + xs.reduce(math.min)) / 2, (ys.reduce(math.max) + ys.reduce(math.min)) / 2), math.max(w, h)));
          next = j + 1;
        }
        break;
      }
      i = next;
    }
    var run = <(int, int, Pt, double)>[];
    void flush() {
      final r = run;
      run = [];
      if (r.length < 3) return;
      final cx = r.map((l) => l.$3.x), cy = r.map((l) => l.$3.y);
      final sx = cx.reduce(math.max) - cx.reduce(math.min), sy = cy.reduce(math.max) - cy.reduce(math.min);
      final sz = r.map((l) => l.$4);
      if (math.max(sx, sy) < 0.3 * unit || math.max(sx, sy) < 2 * math.min(sx, sy)) return;
      if (sz.reduce(math.max) > 3 * sz.reduce(math.min)) return;
      // The coil runs half a loop past its first and last crossings.
      final reachArc = 0.5 * (arc[r.last.$2] - arc[r.first.$1]) / r.length;
      var a = r.first.$1, z = r.last.$2;
      while (a > 0 && arc[r.first.$1] - arc[a - 1] <= reachArc) {
        a--;
      }
      while (z < p.length - 1 && arc[z + 1] - arc[r.last.$2] <= reachArc) {
        z++;
      }
      final seg = p.sublist(a, z + 1);
      final xs = seg.map((q) => q.x), ys = seg.map((q) => q.y);
      final box = _Box(xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max));
      final flat = sx >= sy, short = flat ? box.y1 - box.y0 : box.x1 - box.x0;
      // A straight wire runs on from at least one end along the coil's line:
      // ink within one narrow band across, reaching 0.35 unit out.
      bool wireAt(bool far) {
        final edge = flat ? (far ? box.x1 : box.x0) : (far ? box.y1 : box.y0);
        final mid = flat ? box.cy : box.cx;
        final out = far ? 1.0 : -1.0;
        final lo = edge + out * 0.05 * unit, hi = edge + out * 0.7 * unit;
        final ids = flat
            ? grid.box(math.min(lo, hi), mid - short, math.max(lo, hi), mid + short)
            : grid.box(mid - short, math.min(lo, hi), mid + short, math.max(lo, hi));
        final bands = <int, List<double>>{};
        for (final k in ids) {
          for (final q in strokes[k]) {
            final along = ((flat ? q.x : q.y) - edge) * out, across = (flat ? q.y : q.x) - mid;
            if (along < 0.05 * unit || along > 0.7 * unit || across.abs() > 0.6 * short + _tol) continue;
            final band = (across / (0.06 * unit)).floor();
            (bands[band] ??= []).add(along);
            (bands[band + 1] ??= []).add(along);
          }
        }
        return bands.values.any((v) => v.length >= 3 && v.reduce(math.max) - v.reduce(math.min) >= 0.35 * unit);
      }

      if (wireAt(false) || wireAt(true)) coils.add(_Box(box.x0 - 2, box.y0 - 2, box.x1 + 2, box.y1 + 2));
    }

    for (final l in loops) {
      if (run.isNotEmpty && (l.$3 - run.last.$3).len > 0.6 * unit) flush();
      run.add(l);
    }
    flush();
  }
  if (coils.isEmpty) return dets;
  final kept = [...dets];
  for (var c in coils) {
    final flat = c.x1 - c.x0 >= c.y1 - c.y0;
    double overlap(Detection d) {
      final w = math.min(c.x1, d.x1) - math.max(c.x0, d.x0), h = math.min(c.y1, d.y1) - math.max(c.y0, d.y0);
      return w <= 0 || h <= 0 ? 0 : w * h;
    }

    final parts = kept.where((d) => !_nonComponent.contains(d.cls) && overlap(d) > 0).toList();
    // A part read over most of the coil, or across its middle, is the coil
    // misread.
    bool misread(Detection d) {
      final o = overlap(d), area = d.width * d.height, coil = (c.x1 - c.x0) * (c.y1 - c.y0);
      return o / (area + coil - o) > 0.3 || o > 0.6 * area || _Box.of(d).has(Pt(c.cx, c.cy));
    }

    final misreads = parts.where(misread).toList();
    if (misreads.any((d) => d.cls == 'inductor')) continue;
    for (final d in parts.where((d) => !misreads.contains(d)).toList()) {
      final ahead = flat ? (d.x0 + d.x1) / 2 > c.cx : (d.y0 + d.y1) / 2 > c.cy;
      c = flat
          ? (ahead ? _Box(c.x0, c.y0, math.min(c.x1, d.x0), c.y1) : _Box(math.max(c.x0, d.x1), c.y0, c.x1, c.y1))
          : (ahead ? _Box(c.x0, c.y0, c.x1, math.min(c.y1, d.y0)) : _Box(c.x0, math.max(c.y0, d.y1), c.x1, c.y1));
    }
    if (math.max(c.x1 - c.x0, c.y1 - c.y0) < 0.4 * unit) continue;
    kept.removeWhere(misreads.contains);
    kept.add(Detection('inductor', 0.5, c.x0, c.y0, c.x1, c.y1));
  }
  return kept;
}

/// Whether segments [a]-[b] and [c]-[d] cross (touching does not count).
bool _segmentsCross(Pt a, Pt b, Pt c, Pt d) {
  double side(Pt o, Pt p, Pt q) => (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x);
  final d1 = side(c, d, a), d2 = side(c, d, b), d3 = side(a, b, c), d4 = side(a, b, d);
  return (d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0) && d1 != 0 && d2 != 0 && d3 != 0 && d4 != 0;
}

/// Small loops drawn into a wire's stroke (centre, size): stretches where
/// the pen goes around and comes back near where it started.
List<(Pt, double)> _loops(List<Pt> pts, double unit) {
  final out = <(Pt, double)>[];
  const minD = 3.5;
  final maxD = 0.4 * unit;
  var i = 0;
  while (i < pts.length) {
    var len = 0.0;
    var found = -1;
    for (var j = i + 1; j < pts.length; j++) {
      len += (pts[j] - pts[j - 1]).len;
      if (len > 4 * maxD) break;
      if (len < 2.5 * minD || (pts[j] - pts[i]).len > 0.3 * len) continue;
      final seg = pts.sublist(i, j + 1);
      final xs = seg.map((p) => p.x), ys = seg.map((p) => p.y);
      final w = xs.reduce(math.max) - xs.reduce(math.min), h = ys.reduce(math.max) - ys.reduce(math.min);
      if (math.min(w, h) >= minD && math.max(w, h) <= maxD && math.max(w, h) < 2.6 * math.min(w, h) &&
          len < 4.5 * math.max(w, h) && _winding(seg).abs() > 0.8 * math.pi && _portPlace(pts, i, j, unit)) {
        out.add((Pt((xs.reduce(math.max) + xs.reduce(math.min)) / 2, (ys.reduce(math.max) + ys.reduce(math.min)) / 2), math.max(w, h)));
        found = j;
        break;
      }
    }
    i = found > 0 ? found : i + 1;
  }
  return out;
}

/// Where a port ring sits in a stroke: at its end, or on a run that carries
/// straight on past it. A loop where the stroke turns a corner is a hook.
bool _portPlace(List<Pt> pts, int i, int j, double unit) {
  final reach = 0.25 * unit;
  final before = _along(pts.sublist(0, i + 1).reversed.toList(), reach);
  final after = _along(pts.sublist(j), reach);
  final din = pts[i] - before, dout = after - pts[j];
  if (din.len < 0.5 * reach || dout.len < 0.5 * reach) return true;
  return din.dot(dout) > 0.85 * din.len * dout.len;
}

/// Total signed turning along [pts]: about 2 pi for a ring, pi for a hook.
double _winding(List<Pt> pts) {
  var total = 0.0;
  for (var k = 1; k + 1 < pts.length; k++) {
    final a = pts[k] - pts[k - 1], b = pts[k + 1] - pts[k];
    if (a.len < 0.5 || b.len < 0.5) continue;
    total += math.atan2(a.x * b.y - a.y * b.x, a.dot(b));
  }
  return total;
}

/// [pl] without the stretches inside the circle at [c] of radius [r].
List<List<Pt>> _cutCircle(List<Pt> pl, Pt c, double r) {
  bool inside(Pt p) => (p - c).len < r;
  final out = <List<Pt>>[];
  var cur = <Pt>[];
  for (var k = 0; k < pl.length; k++) {
    final p = pl[k];
    if (k > 0) {
      final a = pl[k - 1], d = p - a;
      // Circle crossings along a->p, in order.
      final f = a - c;
      final qa = d.dot(d), qb = 2 * f.dot(d), qc = f.dot(f) - r * r;
      final disc = qb * qb - 4 * qa * qc;
      if (qa > 0 && disc > 0) {
        final sq = math.sqrt(disc);
        for (final t in [(-qb - sq) / (2 * qa), (-qb + sq) / (2 * qa)]) {
          if (t <= 0 || t >= 1) continue;
          final x = a + d * t;
          if (cur.isNotEmpty) {
            cur.add(x);
            if (cur.length >= 2) out.add(cur);
            cur = <Pt>[];
          } else {
            cur = [x];
          }
        }
      }
    }
    if (!inside(p)) cur.add(p);
  }
  if (cur.length >= 2) out.add(cur);
  return out;
}

/// Brings runs that continue each other (or overlap) within [delta] onto one
/// line: horizontal runs to one y, vertical runs to one x. A [fixed] point
/// (a part's terminal) on a run sets the line; otherwise the longer runs
/// weigh more. Ends of other wires resting on a moved point move with it.
void _snapRuns(List<List<Pt>?> wires, List<Pt> fixed, double delta) {
  for (final horizontal in [true, false]) {
    double across(Pt p) => horizontal ? p.y : p.x;
    double along(Pt p) => horizontal ? p.x : p.y;
    final segs = <(int, int)>[]; // (wire, index of the segment's first point)
    for (var w = 0; w < wires.length; w++) {
      final pl = wires[w];
      if (pl == null) continue;
      for (var k = 0; k + 1 < pl.length; k++) {
        final a = pl[k], b = pl[k + 1];
        if ((across(a) - across(b)).abs() < 0.5 && (along(a) - along(b)).abs() >= 0.5) segs.add((w, k));
      }
    }
    if (segs.length < 2) continue;
    double line((int, int) s) => across(wires[s.$1]![s.$2]);
    (double, double) span((int, int) s) {
      final a = along(wires[s.$1]![s.$2]), b = along(wires[s.$1]![s.$2 + 1]);
      return (math.min(a, b), math.max(a, b));
    }

    final order = List<int>.generate(segs.length, (i) => i)..sort((a, b) => line(segs[a]).compareTo(line(segs[b])));
    final dsu = _Dsu(segs.length);
    for (var x = 0; x < order.length; x++) {
      for (var y = x + 1; y < order.length && line(segs[order[y]]) - line(segs[order[x]]) <= delta; y++) {
        final (a0, a1) = span(segs[order[x]]);
        final (b0, b1) = span(segs[order[y]]);
        if (a0 <= b1 + _tol && b0 <= a1 + _tol) dsu.union(order[x], order[y]);
      }
    }
    final groups = <int, List<int>>{};
    for (var i = 0; i < segs.length; i++) {
      (groups[dsu.find(i)] ??= []).add(i);
    }
    final moves = <(Pt, Pt)>[];
    for (final g in groups.values) {
      final values = g.map((i) => line(segs[i])).toList();
      if (values.reduce(math.max) - values.reduce(math.min) < 0.05) continue;
      double? target;
      for (final f in fixed) {
        if (g.any((i) {
          final (s0, s1) = span(segs[i]);
          return (across(f) - line(segs[i])).abs() <= delta && along(f) >= s0 - 1 && along(f) <= s1 + 1;
        })) {
          target = across(f);
          break;
        }
      }
      if (target == null) {
        var sum = 0.0, weight = 0.0;
        for (final i in g) {
          final (s0, s1) = span(segs[i]);
          sum += line(segs[i]) * (s1 - s0 + 1);
          weight += s1 - s0 + 1;
        }
        target = sum / weight;
      }
      for (final i in g) {
        final (w, k) = segs[i];
        final pl = wires[w]!;
        for (final j in [k, k + 1]) {
          final old = pl[j];
          final moved = horizontal ? Pt(old.x, target) : Pt(target, old.y);
          if ((moved - old).len > 0.01) {
            moves.add((old, moved));
            pl[j] = moved;
          }
        }
      }
    }
    if (moves.isEmpty) continue;
    // Wires ending on a moved point follow it.
    for (final pl in wires) {
      if (pl == null) continue;
      for (final j in [0, pl.length - 1]) {
        for (final (old, moved) in moves) {
          if ((pl[j] - old).len <= 1.0) {
            pl[j] = moved;
            break;
          }
        }
      }
    }
  }
}
