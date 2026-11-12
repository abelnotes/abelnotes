// Parts with more than two terminals or a polarity the redraw must keep:
// transistors (n/p read from the drawn arrow), op-amps, switches, batteries.
// Geometry from CircuiTikZ (GPL-3.0), as in circuit_graph.dart.
part of 'circuit_graph.dart';

/// Where a transistor's arrow sits and which way it points, read from the ink
/// in its box: (on the upper lead, pointing away from the gate). Null when no
/// head stands out, i.e. the part was drawn without one.
///
/// Heads are drawn as a chevron or a quick hook: either way a tangle of short
/// strokes off the lead line, much more ink than a rounded corner leaves.
(bool, bool)? _leadArrow(List<List<Pt>> runs, _Box b, bool gateWest, {bool slanted = false}) {
  final w = b.x1 - b.x0, h = b.y1 - b.y0;
  Pt m(Pt p) => Pt(gateWest ? p.x - b.x0 : b.x1 - p.x, p.y); // x from the gate edge
  final short = <Pt>[];
  final arms = <(Pt, Pt)>[];
  double? ch;
  for (final run in runs) {
    final simp = _simplify([for (final p in run) m(p)], math.max(1.5, 0.06 * h));
    for (var k = 0; k + 1 < simp.length; k++) {
      final a = simp[k], c = simp[k + 1], d = c - a;
      if (d.len <= 0.22 * h) {
        // Head wings slant; an upright piece is a lead leaving its corner.
        if (d.y.abs() <= 2.5 * d.x.abs()) short.addAll(_densify([a, c], 1).skip(1));
      } else if (d.y.abs() > 2 * d.x.abs()) {
        // Plates and the channel cross the middle; lead lines do not.
        if (d.len > 0.45 * h && math.min(a.y, c.y) < b.cy && math.max(a.y, c.y) > b.cy && (a.x + c.x) / 2 < 0.8 * w) {
          ch = math.max(ch ?? 0, (a.x + c.x) / 2);
        }
      } else if (slanted || d.y.abs() < 0.4 * d.x.abs()) {
        arms.add(a.x <= c.x ? (a, c) : (c, a));
      } else {
        short.addAll(_densify([a, c], 1).skip(1));
      }
    }
  }
  final channel = ch ?? 0.45 * w;

  // (ink off the lead, points away from the gate) for one half. The head's
  // tip sits on the lead line, its wings off it: tip beyond wings is the way
  // it points, for a chevron and a hook alike.
  (int, bool)? read(bool upper) {
    final mine = arms.where((s) => ((s.$1.y + s.$2.y) / 2 < b.cy) == upper && s.$2.x > channel + 2).toList();
    if (mine.isEmpty) return null;
    final arm = mine.reduce((p, q) => (p.$2 - p.$1).len >= (q.$2 - q.$1).len ? p : q);
    final dir = (arm.$2 - arm.$1) * (1 / (arm.$2 - arm.$1).len);
    final nrm = Pt(-dir.y, dir.x);
    final lo = mine.map((s) => s.$1.x).reduce(math.min), hi = mine.map((s) => s.$2.x).reduce(math.max);
    final head = <(Pt, double)>[
      for (final p in short)
        if ((p.y < b.cy) == upper && p.x > channel - 0.08 * h && p.x > lo - 0.15 * h && p.x < hi + 0.2 * h)
          if ((p - arm.$1).dot(nrm) case final d when d.abs() > 1.0 && d.abs() < 0.25 * h) (p, d)
    ];
    final above = head.where((e) => e.$2 > 0).length, below = head.length - above;
    // A rounded corner leaves ink on one side only.
    if (math.min(above, below) < 2) return null;
    // Compare the two ends of the head: the tip end hugs the lead line.
    final xs = head.map((e) => e.$1.x);
    final x0 = xs.reduce(math.min), x1 = xs.reduce(math.max), span = x1 - x0;
    if (span < 1) return null;
    double spread(bool far) {
      final d = [
        for (final e in head)
          if (far ? e.$1.x > x1 - 0.35 * span : e.$1.x < x0 + 0.35 * span) e.$2.abs()
      ];
      return d.isEmpty ? 0 : d.reduce((a, v) => a + v) / d.length;
    }
    return (head.length, spread(true) < spread(false));
  }

  final up = read(true), down = read(false);
  final su = up?.$1 ?? 0, sd = down?.$1 ?? 0;
  final best = su >= sd ? up : down;
  if (best == null || best.$1 < math.max(5.0, 0.2 * h) || best.$1 < 1.8 * math.min(su, sd)) return null;
  return (su >= sd, best.$2);
}

/// A transistor redrawn upright in its box: gate (or base) on the side its
/// wire comes from, the two leads on the line of the wires above and below.
/// Returns terminals and strokes, the symbol in CircuiTikZ's proportions for
/// basic length [rl] (nmos/npn). The arrow comes from [_leadArrow]; without a
/// readable one, none is drawn. [placed]: terminals of parts laid out so far.
(List<Pt>, List<OutStroke>) _transistor(_Box b, List<Pt> ends, List<List<Pt>> ink, double rl,
    {double? stacked, bool bipolar = false, double? gateLine, List<Pt> placed = const []}) {
  final w = b.x1 - b.x0, h = b.y1 - b.y0;
  final sideways = ends.where((p) => (p.y - b.cy).abs() < 0.3 * h && (b.side(p) == 'W' || b.side(p) == 'E')).toList();
  final leads = ends.where((p) => !sideways.contains(p)).toList();
  // Wires on both flanks: the gate is the one opposite the leads, the other
  // the body.
  final leadsEast = leads.isEmpty
      ? _inkLeansEast(ink, b)
      : leads.map((p) => p.x).reduce((a, v) => a + v) / leads.length >= b.cx;
  final bool gateWest;
  if (sideways.isNotEmpty) {
    final west = sideways.where((p) => p.x < b.cx).length, east = sideways.length - west;
    gateWest = west == east ? leadsEast : west > east;
  } else {
    gateWest = leadsEast;
  }
  double mx(double x) => gateWest ? x : b.x0 + b.x1 - x; // mirror for an east gate
  final outs = leads.where((p) => gateWest ? p.x > b.cx - 0.1 * w : p.x < b.cx + 0.1 * w).toList();
  // Both leads share one line; take it from the wire above (or a part
  // stacked there), so only the other lead may need a jog.
  final top = outs.where((p) => p.y < b.cy).toList();
  final pick = top.isNotEmpty ? top : outs;
  var xo = stacked != null
      ? mx(stacked)
      : pick.isEmpty
          ? b.x0 + 0.85 * w
          : pick.map((p) => mx(p.x)).reduce((a, v) => a + v) / pick.length;
  xo = xo.clamp(b.x0 + 0.5 * w, b.x1);
  // The channel (or base bar) sits a fixed step from the lead line, so the
  // lead stays where the wires are.
  final xc = xo - (bipolar ? 0.3 : 0.35) * rl;
  final xg = xo - 0.434 * rl;
  final gates = sideways.where((p) => (p.x < b.cx) == gateWest).toList();
  final body = !bipolar && sideways.length > gates.length;
  final gy = gates.isEmpty ? b.cy : gateLine ?? gates.map((p) => p.y).reduce((a, v) => a + v) / gates.length;
  Pt at(double x, double y) => Pt(mx(x), y);
  // Terminals at least where CircuiTikZ puts them, further out to meet the
  // wires.
  final gate = at(math.min(b.x0, xo - (bipolar ? 0.6 : 0.7) * rl), gy);
  final bodyEnd = at(math.max(b.x1, xo + 0.15 * rl), b.cy);
  var yTop = math.min(b.y0, b.cy - 0.55 * rl), yBot = math.max(b.y1, b.cy + 0.55 * rl);
  // A part drawn touching it on the lead line: the lead stops at that part's
  // terminal instead of running into its body.
  for (final t in placed) {
    if ((mx(t.x) - xo).abs() > _tol) continue;
    if (t.y > yTop && t.y < b.cy - 0.2 * rl) yTop = t.y;
    if (t.y < yBot && t.y > b.cy + 0.2 * rl) yBot = t.y;
  }
  final arrow = _leadArrow(ink, b, gateWest, slanted: bipolar);
  final out = <OutStroke>[];
  final terminals = [at(xo, yTop), at(xo, yBot), gate, if (body) bodyEnd];

  if (bipolar) {
    final barTop = b.cy - 0.22 * rl, barBot = b.cy + 0.22 * rl;
    out
      ..add(OutStroke.line([gate, at(xc, gy)]))
      ..add(OutStroke.line([at(xc, math.min(barTop, gy - 0.05 * rl)), at(xc, math.max(barBot, gy + 0.05 * rl))],
          body: true));
    for (final upper in [true, false]) {
      final sgn = upper ? -1.0 : 1.0;
      final a = at(xc, b.cy + sgn * 0.0825 * rl), z = at(xo, b.cy + sgn * 0.22 * rl);
      out.add(OutStroke.line([a, z, at(xo, upper ? yTop : yBot)]));
      if (arrow != null && arrow.$1 == upper) {
        final d = (z - a) * (1 / (z - a).len);
        out.add(_arrowHead((a + z) * 0.5, arrow.$2 ? d : d * -1, rl));
      }
    }
    return (terminals, out);
  }

  final yd = b.cy - 0.1925 * rl, ys = b.cy + 0.1925 * rl;
  final chTop = b.cy - 0.275 * rl, chBot = b.cy + 0.275 * rl;
  out
    ..add(OutStroke.line([gate, at(xg, gy)]))
    ..add(OutStroke.line([at(xg, math.min(yd, gy - 0.05 * rl)), at(xg, math.max(ys, gy + 0.05 * rl))], body: true))
    ..add(OutStroke.line([at(xc, chTop), at(xc, chBot)], body: true))
    ..add(OutStroke.line([at(xc, yd), at(xo, yd), at(xo, yTop)]))
    ..add(OutStroke.line([at(xc, ys), at(xo, ys), at(xo, yBot)]));
  if (body) out.add(OutStroke.line([at(xc, b.cy), bodyEnd]));
  if (arrow != null) {
    // n-channel: the arrow leaves the channel; p-channel: it enters it.
    final y = arrow.$1 ? yd : ys;
    final outward = (at(xo, y) - at(xc, y)) * (1 / (xo - xc));
    out.add(_arrowHead(at(xo - 0.174 * rl, y), arrow.$2 ? outward : outward * -1, rl));
  }
  return (terminals, out);
}

/// With no wire to tell, the gate is on the side with less ink: the leads
/// and their corners sit opposite it.
bool _inkLeansEast(List<List<Pt>> ink, _Box b) {
  final pts = [for (final r in ink) ...r];
  if (pts.isEmpty) return true;
  return pts.map((p) => p.x).reduce((a, v) => a + v) / pts.length >= b.cx;
}

/// Mean offset of [ink] from the line [s]-[e], on the side of its left
/// normal: where a switch lever leans.
double _inkSide(List<Pt> ink, Pt s, Pt e) {
  if (ink.isEmpty) return 0;
  final u = (e - s) * (1 / (e - s).len), v = Pt(-u.y, u.x);
  return ink.map((p) => (p - s).dot(v)).reduce((a, x) => a + x) / ink.length;
}

/// Whether the plate nearer [s] is the wider one (a battery's plus).
bool _widerAtStart(List<Pt> ink, Pt s, Pt e) {
  if (ink.length < 4) return true;
  final u = (e - s) * (1 / (e - s).len), v = Pt(-u.y, u.x);
  final mid = (e - s).len / 2;
  double width(bool first) {
    final off = [for (final p in ink) if (((p - s).dot(u) < mid) == first) (p - s).dot(v)];
    return off.isEmpty ? 0 : off.reduce(math.max) - off.reduce(math.min);
  }

  return width(true) >= width(false);
}

/// An op-amp redrawn as CircuiTikZ's triangle: inputs on the side two wires
/// reach, the output on the opposite side, signs where the user wrote them.
/// Null when the wiring does not read as an amplifier (the part then stays as
/// drawn).
(List<Pt>, List<OutStroke>)? _opamp(_Box b, List<Pt> ends, List<List<Pt>> ink, double rl) {
  final w = b.x1 - b.x0, h = b.y1 - b.y0;
  final west = ends.where((p) => b.side(p) == 'W').toList()..sort((p, q) => p.y.compareTo(q.y));
  final east = ends.where((p) => b.side(p) == 'E').toList()..sort((p, q) => p.y.compareTo(q.y));
  final bool inWest;
  if (west.length >= 2 && east.length <= 1) {
    inWest = true;
  } else if (east.length >= 2 && west.length <= 1) {
    inWest = false;
  } else {
    return null;
  }
  final ins = inWest ? west : east;
  // Inputs enter the triangle's base, inside its corners; wires meeting a
  // box at its very corners (axes of a plot) are not inputs.
  if (ins.any((p) => p.y < b.y0 + 0.12 * h || p.y > b.y1 - 0.12 * h)) return null;
  final inX = inWest ? b.x0 : b.x1, outX = inWest ? b.x1 : b.x0;
  final dir = inWest ? 1.0 : -1.0;
  // CircuiTikZ's triangle is 1.4 R tall and 1.19 R deep, inputs halfway to
  // its corners; inputs drawn further apart stretch it, same shape. Leads
  // bridge to wherever the wires reach the box.
  final yA = ins.first.y, yB = ins.last.y;
  final mid = (yA + yB) / 2, halfH = math.max(0.7 * rl, (yB - yA) / 2 + 0.35 * rl);
  final baseX = inX + dir * 0.15 * w;
  final tipX = baseX + dir * 1.19 * rl * halfH / (0.7 * rl);
  final outEnd = (outX - tipX) * dir > 0 ? outX : tipX + dir * 0.25 * rl;
  final yOut = mid;
  final top = mid - halfH, bot = mid + halfH;
  final strokes = <OutStroke>[
    OutStroke.line([Pt(baseX, top), Pt(baseX, bot), Pt(tipX, yOut), Pt(baseX, top)], body: true),
    OutStroke.line([Pt(inX, yA), Pt(baseX, yA)]),
    OutStroke.line([Pt(inX, yB), Pt(baseX, yB)]),
    OutStroke.line([Pt(tipX, yOut), Pt(outEnd, yOut)]),
  ];
  // Signs: the plus has an upright bar, the minus none. Only short strokes
  // count, so the triangle's own sides do not.
  final marks = _shortInk(ink, 0.3 * h);
  double upright(double y) {
    final pts = [
      for (final p in marks)
        if ((p.x - inX) * dir > 0 && (p.x - inX) * dir < 0.5 * w && (p.y - y).abs() < 0.15 * h) p.y
    ];
    return pts.isEmpty ? 0 : pts.reduce(math.max) - pts.reduce(math.min);
  }

  final ua = upright(yA), ub = upright(yB);
  if ((ua - ub).abs() > math.max(2.0, 0.04 * h)) {
    final m = 0.085 * rl, sx = baseX + dir * 0.19 * rl;
    for (final (y, plus) in [(yA, ua > ub), (yB, ub > ua)]) {
      strokes.add(OutStroke.line([Pt(sx - m, y), Pt(sx + m, y)]));
      if (plus) strokes.add(OutStroke.line([Pt(sx, y - m), Pt(sx, y + m)]));
    }
  }
  return ([Pt(inX, yA), Pt(inX, yB), Pt(outEnd, yOut)], strokes);
}

/// Points along the short pieces of [runs] once simplified: marks and signs,
/// without the long sides of the outline they sit in.
List<Pt> _shortInk(List<List<Pt>> runs, double maxLen) => [
      for (final r in runs)
        for (final seg in _segments(_simplify(r, 1.5)))
          if ((seg.$2 - seg.$1).len <= maxLen) ..._densify([seg.$1, seg.$2], 1),
    ];

Iterable<(Pt, Pt)> _segments(List<Pt> pts) sync* {
  for (var k = 0; k + 1 < pts.length; k++) {
    yield (pts[k], pts[k + 1]);
  }
}
