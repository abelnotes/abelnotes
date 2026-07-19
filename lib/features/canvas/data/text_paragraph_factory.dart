import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Shared builder for the ui.Paragraph that represents a [TextData] element.
///
/// This is the single source of truth for how text elements are shaped:
/// [CanvasRenderEngine] paints exactly this paragraph, and the import
/// paginator measures exactly this paragraph to decide page breaks — so a
/// page break computed at import time can never disagree with what the
/// canvas later draws.
///
/// Matches http(s):// URLs and bare www. links inside text content, so
/// they can be rendered as styled (blue + underlined) link spans. Kept in
/// sync with the Ctrl+click hit-test in canvas_screen.dart.
final RegExp urlInTextPattern = RegExp(
  r'((https?://)|(www\.))[^\s]+',
  caseSensitive: false,
);

/// Resolve the effective ui.TextStyle for one rich span (or the legacy
/// whole-element run when [span] is null). [asLink] layers the blue
/// underline link affordance on top.
ui.TextStyle textStyleFor(TextData t, TextSpanData? span,
    {bool asLink = false}) {
  final bold = (span?.bold ?? false) || t.bold;
  final italic = (span?.italic ?? false) || t.italic;
  final underline = (span?.underline ?? false) || asLink;
  final strike = span?.strikethrough ?? false;
  final color = asLink
      ? const Color(0xFF1565C0)
      : Color(span?.color ?? t.color);
  TextDecoration deco = TextDecoration.none;
  if (underline && strike) {
    deco = TextDecoration.combine(
        [TextDecoration.underline, TextDecoration.lineThrough]);
  } else if (underline) {
    deco = TextDecoration.underline;
  } else if (strike) {
    deco = TextDecoration.lineThrough;
  }
  return ui.TextStyle(
    color: color,
    fontSize: span?.fontSize ?? t.fontSize,
    fontFamily: span?.fontFamily ?? t.fontFamily,
    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    decoration: deco,
    decorationColor: color,
  );
}

/// Build (and lay out) the paragraph for [textData]. [width] overrides the
/// layout width; defaults to the element's own box width.
ui.Paragraph buildTextParagraph(TextData textData, {double? width}) {
  final paragraphStyle = ui.ParagraphStyle(
    textAlign: textData.alignment == 'center'
        ? TextAlign.center
        : textData.alignment == 'right'
            ? TextAlign.right
            : TextAlign.left,
  );
  final builder = ui.ParagraphBuilder(paragraphStyle);

  // Normalise to a list of styled runs: rich spans when present,
  // otherwise one legacy run carrying the element-level style. Inside
  // each run, URL matches get the link affordance layered on top so
  // Ctrl+click targets stay visible in both forms.
  final runs =
      textData.spans.isNotEmpty ? textData.spans : <TextSpanData?>[null];
  var any = false;
  for (final span in runs) {
    final text = span?.text ?? textData.content;
    if (text.isEmpty) continue;
    any = true;
    final base = textStyleFor(textData, span);
    final link = textStyleFor(textData, span, asLink: true);
    var last = 0;
    for (final m in urlInTextPattern.allMatches(text)) {
      if (m.start > last) {
        builder
          ..pushStyle(base)
          ..addText(text.substring(last, m.start))
          ..pop();
      }
      builder
        ..pushStyle(link)
        ..addText(text.substring(m.start, m.end))
        ..pop();
      last = m.end;
    }
    if (last < text.length) {
      builder
        ..pushStyle(base)
        ..addText(text.substring(last))
        ..pop();
    }
  }
  if (!any) {
    builder
      ..pushStyle(textStyleFor(textData, null))
      ..addText('');
  }
  return builder.build()
    ..layout(ui.ParagraphConstraints(width: width ?? textData.width));
}
