// Measures text blocks (height, hugging width) with the same spans the editor paints.
import 'dart:math';

import 'package:flutter/painting.dart';

import 'package:abelnotes/shared/models/ncnote_format.dart';

/// The styled runs of a text block, shared by the width/height measures
/// so the two can never lay the same content out differently.
TextSpan textSpanFor(
  String content,
  List<TextSpanData> spans,
  double baseFontSize,
) {
  final children = <TextSpan>[];
  if (spans.isEmpty) {
    children
        .add(TextSpan(text: content, style: TextStyle(fontSize: baseFontSize)));
  } else {
    for (final sp in spans) {
      children.add(TextSpan(
        text: sp.text,
        style: TextStyle(
          fontSize: sp.fontSize ?? baseFontSize,
          fontFamily: sp.fontFamily,
          fontWeight: sp.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: sp.italic ? FontStyle.italic : FontStyle.normal,
        ),
      ));
    }
  }
  return TextSpan(children: children);
}

/// Measure the laid-out height of a text block so new/edited elements
/// fit their content instead of clipping at the legacy fixed 50 px.
double measureTextHeight(
  String content,
  List<TextSpanData> spans,
  double baseFontSize,
  double width,
) {
  final tp = TextPainter(
    text: textSpanFor(content, spans, baseFontSize),
    textDirection: TextDirection.ltr,
    maxLines: null,
  )..layout(maxWidth: width);
  final h = tp.height + 8; // breathing room for descenders
  tp.dispose();
  return h.clamp(30.0, 2000.0);
}

/// Width that actually hugs the text: the longest laid-out line, once the
/// content has wrapped at [maxWidth].
///
/// New text boxes used to be born [kTextBoxMaxWidth] wide whatever they
/// held, so a one-word note carried a selection frame half the page across
/// — handles and action bar floating far from the glyphs they belong to.
/// Laying out at [maxWidth] first and taking the longest line keeps the line
/// breaks the wrap width produced (a line that fitted in [maxWidth] still
/// fits in the longest line), so this narrows the frame without ever
/// reflowing the text.
double measureTextWidth(
  String content,
  List<TextSpanData> spans,
  double baseFontSize,
  double maxWidth,
) {
  final tp = TextPainter(
    text: textSpanFor(content, spans, baseFontSize),
    textDirection: TextDirection.ltr,
    maxLines: null,
  )..layout(maxWidth: maxWidth);
  // TextPainter.width reports the CONSTRAINT it laid out against, not the
  // ink — it would hand back maxWidth and fit nothing. The per-line metrics
  // are the real extents.
  final lines = tp.computeLineMetrics();
  final longest =
      lines.isEmpty ? tp.width : lines.map((m) => m.width).reduce(max);
  // Same breathing room the height gets: guards the last glyph, italic
  // overhang, and the sub-pixel rounding of re-laying out at this width.
  final w = longest + 8;
  tp.dispose();
  return w.clamp(40.0, maxWidth);
}
