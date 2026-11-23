import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:abelnotes/shared/models/ncnote_format.dart';

/// A recognised handwritten line: its text and where each character sits.
class InkLine {
  final String text;

  /// Line box in page points: left, top, right, bottom.
  final double x0, y0, x1, y1;

  /// Page x of the middle of each character of [text].
  final List<double> xs;

  const InkLine(this.text, this.x0, this.y0, this.x1, this.y1, this.xs);

  Map<String, Object> toJson() => {
        't': text,
        'b': [x0, y0, x1, y1].map(_r).toList(),
        'x': xs.map(_r).toList(),
      };

  static double _r(double v) => (v * 10).roundToDouble() / 10;

  static InkLine? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = j['t'], b = j['b'], x = j['x'];
    if (t is! String || b is! List || b.length != 4 || x is! List) return null;
    double d(Object? v) => (v as num).toDouble();
    return InkLine(t, d(b[0]), d(b[1]), d(b[2]), d(b[3]), [for (final v in x) d(v)]);
  }

  static String encodeAll(List<InkLine> lines) =>
      lines.isEmpty ? '' : jsonEncode([for (final l in lines) l.toJson()]);

  static List<InkLine> decodeAll(String? s) {
    if (s == null || s.isEmpty) return const [];
    try {
      final v = jsonDecode(s);
      if (v is! List) return const [];
      return [for (final e in v) fromJson(e)].whereType<InkLine>().toList();
    } on FormatException {
      return const [];
    }
  }
}

/// The recognizer's settings, from assets/models/handwriting_text.json.
class InkModelMeta {
  final String version;
  final int height;
  final double pad;
  final double lineWidth;
  final List<String> chars;
  const InkModelMeta(this.version, this.height, this.pad, this.lineWidth, this.chars);

  factory InkModelMeta.fromJson(Map<String, dynamic> j) => InkModelMeta(
        j['version'] as String,
        (j['height'] as num).toInt(),
        (j['pad'] as num).toDouble(),
        (j['line_width'] as num).toDouble(),
        [for (final c in j['chars'] as List) c as String],
      );
}

/// Strokes that are handwriting: no highlighter, no tidied circuit lines.
List<StrokeData> inkStrokes(PageData page) => [
      for (final e in page.layers.content)
        if (e is StrokeElement &&
            !e.data.isHighlighter &&
            e.data.toolType != 'highlighter' &&
            !isTechnicalTool(e.data.toolType) &&
            e.data.points.isNotEmpty)
          e.data,
    ];

typedef _Box = ({double x0, double y0, double x1, double y1});

_Box _boxOf(StrokeData s) {
  var x0 = double.infinity, y0 = double.infinity;
  var x1 = -double.infinity, y1 = -double.infinity;
  for (final p in s.points) {
    x0 = math.min(x0, p.x);
    y0 = math.min(y0, p.y);
    x1 = math.max(x1, p.x);
    y1 = math.max(y1, p.y);
  }
  return (x0: x0, y0: y0, x1: x1, y1: y1);
}

/// A run of strokes that reads as one line of handwriting.
class InkSegment {
  final List<StrokeData> strokes;
  final double x0, y0, x1, y1;
  const InkSegment(this.strokes, this.x0, this.y0, this.x1, this.y1);
}

/// Groups strokes into lines, then splits lines at wide gaps. Drawings,
/// multi-line blobs and lone marks are left out.
List<InkSegment> segmentInk(List<StrokeData> strokes) {
  final bx = [for (final s in strokes) _boxOf(s)];
  final idx = List<int>.generate(strokes.length, (i) => i)
    ..sort((a, b) => ((bx[a].y0 + bx[a].y1) / 2).compareTo((bx[b].y0 + bx[b].y1) / 2));
  final lines = <_Line>[];
  for (final i in idx) {
    final x = bx[i];
    final h = math.max(x.y1 - x.y0, 2.0);
    final cy = (x.y0 + x.y1) / 2;
    _Line? best;
    for (final l in lines) {
      if (!(l.t <= cy && cy <= l.b)) continue;
      final med = math.max(_median([for (final j in l.ids) bx[j].y1 - bx[j].y0]), 4.0);
      if (math.max(l.b, x.y1) - math.min(l.t, x.y0) > 2.5 * med + 4 && h < 3 * med) {
        if (!(l.t + 0.2 * (l.b - l.t) <= cy && cy <= l.b - 0.2 * (l.b - l.t))) {
          continue;
        }
      }
      best = l;
      break;
    }
    if (best == null) {
      lines.add(_Line([i], x.y0, x.y1));
    } else {
      best.ids.add(i);
      best.t = math.min(best.t, x.y0);
      best.b = math.max(best.b, x.y1);
    }
  }
  final moved = _attachMarks(lines, bx);
  final out = <InkSegment>[];
  for (final l in lines) {
    final lh = l.b - l.t;
    if (lh < 6) continue;
    for (final piece in _splitAtGaps(l.ids, bx, lh)) {
      if (piece.length < 3) continue;
      final seg = _segment(piece, strokes, bx, moved);
      if (seg != null) out.add(seg);
    }
  }
  return out;
}

class _Line {
  final List<int> ids;
  double t, b;
  _Line(this.ids, this.t, this.b);
}

double _median(List<double> v) => (v..sort())[v.length ~/ 2];

/// Splits a line left to right where the gap is wider than ~1.5 line heights.
List<List<int>> _splitAtGaps(List<int> lineIds, List<_Box> bx, double lh) {
  final ids = [...lineIds]..sort((a, b) => bx[a].x0.compareTo(bx[b].x0));
  final pieces = <List<int>>[];
  var cur = <int>[];
  double? right;
  for (final i in ids) {
    if (cur.isNotEmpty && bx[i].x0 - right! > math.max(1.5 * lh, 18)) {
      pieces.add(cur);
      cur = [];
    }
    cur.add(i);
    right = cur.length == 1 ? bx[i].x1 : math.max(right!, bx[i].x1);
  }
  if (cur.isNotEmpty) pieces.add(cur);
  return pieces;
}

/// Tails (p/g/q), t-bars, dots and accents sort outside their line and would
/// be dropped as 1-2 stroke lines: they join the nearest line instead.
Set<int> _attachMarks(List<_Line> lines, List<_Box> bx) {
  final moved = <int>{};
  final big = [
    for (final l in lines)
      if (l.ids.length >= 3)
        (
          line: l,
          bt: _median([for (final j in l.ids) bx[j].y0]),
          bb: _median([for (final j in l.ids) bx[j].y1]),
          x0: l.ids.map((j) => bx[j].x0).reduce(math.min),
          x1: l.ids.map((j) => bx[j].x1).reduce(math.max),
        ),
  ];
  _Line? home(int i, _Line s, bool tailsOnly) {
    final x = bx[i];
    _Line? best;
    double? bestGap, bestOv;
    for (final c in big) {
      if (identical(c.line, s)) continue;
      final bh = math.max(c.bb - c.bt, 2.0);
      if (x.x1 < c.x0 - bh || x.x0 > c.x1 + bh || x.y1 - x.y0 > 4 * bh) continue;
      final gap = math.max(0.0, math.max(c.bt - x.y1, x.y0 - c.bb)) / bh;
      final ov = math.max(0.0, math.min(x.y1, c.bb) - math.max(x.y0, c.bt)) / bh;
      if (tailsOnly) {
        if (ov < 0.5 || (x.y0 + x.y1) / 2 <= (c.bt + c.bb) / 2) continue;
      } else if (gap > 0.8) {
        continue;
      }
      if (best == null || gap < bestGap! || (gap == bestGap && ov > bestOv!)) {
        best = c.line;
        bestGap = gap;
        bestOv = ov;
      }
    }
    return best;
  }

  for (final s in lines) {
    final small = _splitAtGaps(s.ids, bx, math.max(s.b - s.t, 6))
        .every((p) => p.length < 3);
    final homes = {for (final i in s.ids) i: home(i, s, !small)};
    final moving = [for (final e in homes.entries) if (e.value != null) e.key];
    // A row of 3+ strokes moves only when it is mostly tails of one line.
    if (!small && moving.length < 0.7 * s.ids.length) continue;
    for (final i in moving) {
      s.ids.remove(i);
      homes[i]!.ids.add(i);
      moved.add(i);
    }
  }
  // Line order and t/b (used for the gap split) stay as before the move.
  lines.removeWhere((l) => l.ids.isEmpty);
  return moved;
}

InkSegment? _segment(
    List<int> ids, List<StrokeData> strokes, List<_Box> bx, Set<int> moved) {
  ({double x0, double y0, double x1, double y1}) extent(Iterable<int> js) => (
        x0: js.map((j) => bx[j].x0).reduce(math.min),
        y0: js.map((j) => bx[j].y0).reduce(math.min),
        x1: js.map((j) => bx[j].x1).reduce(math.max),
        y1: js.map((j) => bx[j].y1).reduce(math.max),
      );
  // Height checks use the line's own strokes, not the attached marks.
  final own = ids.where((j) => !moved.contains(j)).toList();
  final core = own.isEmpty ? ids : own;
  final med = math.max(_median([for (final j in core) bx[j].y1 - bx[j].y0]), 1.0);
  final c = extent(core);
  // Two lines in one, or a drawing: taller than any written line.
  if ((c.y1 - c.y0) / med >= 2.6) return null;
  if ((c.x1 - c.x0) < (c.y1 - c.y0)) return null;
  final e = extent(ids);
  return InkSegment([for (final j in ids) strokes[j]], e.x0, e.y0, e.x1, e.y1);
}

/// Pixel geometry of one segment as the recognizer sees it.
class InkRaster {
  final double scale;
  final int width;
  final Float32List xy;
  final Int32List starts;
  const InkRaster(this.scale, this.width, this.xy, this.starts);
}

InkRaster rasterGeometry(InkSegment seg, InkModelMeta meta) {
  final h = meta.height;
  final sc = h / (seg.y1 - seg.y0 + 2 * meta.pad);
  var w = ((seg.x1 - seg.x0 + 2 * meta.pad) * sc).floor() + 8;
  w = math.max(32, math.min((w + 31) ~/ 32 * 32, 2048));
  var n = 0;
  for (final s in seg.strokes) {
    n += s.points.length;
  }
  final xy = Float32List(2 * n);
  final starts = Int32List(seg.strokes.length);
  var k = 0;
  for (var i = 0; i < seg.strokes.length; i++) {
    starts[i] = k;
    for (final p in seg.strokes[i].points) {
      xy[2 * k] = (p.x - seg.x0 + meta.pad) * sc;
      xy[2 * k + 1] = (p.y - seg.y0 + meta.pad) * sc;
      k++;
    }
  }
  return InkRaster(sc, w, xy, starts);
}

/// Greedy CTC decoding of [probs] (T x C, class 0 = blank) into a line,
/// placing each character at the middle of its first frame.
InkLine? decodeCtc(Float32List probs, int frames, int classes, InkSegment seg,
    InkRaster r, InkModelMeta meta) {
  final sb = StringBuffer();
  final xs = <double>[];
  var prev = 0;
  final pxPerFrame = r.width / frames;
  for (var t = 0; t < frames; t++) {
    var best = 0;
    var bp = -1.0;
    for (var c = 0; c < classes; c++) {
      final v = probs[t * classes + c];
      if (v > bp) {
        bp = v;
        best = c;
      }
    }
    if (best != 0 && best != prev && best - 1 < meta.chars.length) {
      sb.write(meta.chars[best - 1]);
      xs.add(((t + 0.5) * pxPerFrame) / r.scale + seg.x0 - meta.pad);
    }
    prev = best;
  }
  final text = sb.toString().trim();
  if (text.isEmpty) return null;
  // trim() may have dropped edge spaces: keep xs aligned with text.
  final raw = sb.toString();
  final lead = raw.length - raw.trimLeft().length;
  return InkLine(text, seg.x0, seg.y0, seg.x1, seg.y1,
      xs.sublist(lead, lead + text.length));
}
