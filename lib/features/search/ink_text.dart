import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:abelnotes/features/search/ink_decode.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

export 'package:abelnotes/features/search/ink_segment.dart' show segmentInk;

/// A recognised handwritten line: its text and where each character sits.
class InkLine {
  final String text;

  /// Line box in page points: left, top, right, bottom.
  final double x0, y0, x1, y1;

  /// Page x of the middle of each character of [text].
  final List<double> xs;

  /// The plain (greedy) reading of a line whose dictionary reading differs:
  /// indexed too, so a word the dictionary bent is still found.
  final bool alt;

  const InkLine(this.text, this.x0, this.y0, this.x1, this.y1, this.xs, {this.alt = false});

  Map<String, Object> toJson() => {
        't': text,
        'b': [x0, y0, x1, y1].map(_r).toList(),
        'x': xs.map(_r).toList(),
        if (alt) 'a': 1,
      };

  static double _r(double v) => (v * 10).roundToDouble() / 10;

  static InkLine? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = j['t'], b = j['b'], x = j['x'];
    if (t is! String || b is! List || b.length != 4 || x is! List) return null;
    double d(Object? v) => (v as num).toDouble();
    return InkLine(t, d(b[0]), d(b[1]), d(b[2]), d(b[3]), [for (final v in x) d(v)],
        alt: j['a'] == 1);
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
  final InkDecoderParams decoder;
  const InkModelMeta(this.version, this.height, this.pad, this.lineWidth, this.chars,
      {this.decoder = const InkDecoderParams()});

  factory InkModelMeta.fromJson(Map<String, dynamic> j) => InkModelMeta(
        j['version'] as String,
        (j['height'] as num).toInt(),
        (j['pad'] as num).toDouble(),
        (j['line_width'] as num).toDouble(),
        [for (final c in j['chars'] as List) c as String],
        decoder: j['decoder'] is Map
            ? InkDecoderParams.fromJson((j['decoder'] as Map).cast<String, dynamic>())
            : const InkDecoderParams(),
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

/// A run of strokes that reads as one line of handwriting.
class InkSegment {
  final List<StrokeData> strokes;
  final double x0, y0, x1, y1;
  const InkSegment(this.strokes, this.x0, this.y0, this.x1, this.y1);
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

/// A line from decoded [text] whose characters were emitted at [frames].
InkLine? inkLineFromFrames(String text, List<int> frames, int nFrames, InkSegment seg,
    InkRaster r, InkModelMeta meta, {bool alt = false}) {
  final pxPerFrame = r.width / nFrames;
  final xs = [for (final t in frames) ((t + 0.5) * pxPerFrame) / r.scale + seg.x0 - meta.pad];
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final lead = text.length - text.trimLeft().length;
  return InkLine(trimmed, seg.x0, seg.y0, seg.x1, seg.y1,
      xs.sublist(lead, lead + trimmed.length), alt: alt);
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

/// The line read with the lexicon beam search, plus the greedy reading as an
/// [InkLine.alt] line when it differs (search indexes both). Greedy only
/// without a lexicon.
List<InkLine> decodeLines(Float32List probs, int frames, int classes, InkSegment seg,
    InkRaster r, InkModelMeta meta, InkLexicon? lexicon) {
  final greedy = decodeCtc(probs, frames, classes, seg, r, meta);
  if (lexicon == null) return [if (greedy != null) greedy];
  final b = beamDecode(probs, frames, classes, meta.chars, lexicon, meta.decoder);
  final beam = inkLineFromFrames(b.text, b.frames, frames, seg, r, meta);
  if (beam == null) return [if (greedy != null) greedy];
  if (greedy == null || greedy.text == beam.text) return [beam];
  return [
    beam,
    InkLine(greedy.text, greedy.x0, greedy.y0, greedy.x1, greedy.y1, greedy.xs, alt: true),
  ];
}
