// ═══════════════════════════════════════════════════════════════
//  html_text.dart
//
//  Best-effort conversion of clipboard HTML into rich TextSpanData
//  runs, so pasting formatted text from a browser / Word / Docs keeps
//  bold, italic, underline and strikethrough. Everything else (fonts,
//  tables, links-as-anchors, images) is flattened to plain text.
//  Pure Dart — unit-testable without Flutter.
// ═══════════════════════════════════════════════════════════════

import 'package:abelnotes/shared/models/ncnote_format.dart';

class HtmlTextResult {
  final String plain;
  final List<TextSpanData> spans;
  const HtmlTextResult(this.plain, this.spans);
}

final RegExp _tagRe = RegExp(r'<[^>]*>');

/// Convert an HTML fragment to plain text + styled spans. Returns null
/// when the input doesn't look like HTML at all (caller uses the plain
/// clipboard text instead). Never throws — any parse oddity degrades to
/// plainer output.
HtmlTextResult? htmlToSpans(String html) {
  if (!html.contains('<')) return null;

  var bold = 0, italic = 0, underline = 0, strike = 0;
  var skipDepth = 0; // inside <style>/<script>/<head>
  final textBuf = StringBuffer();
  final styles = <TextSpanData>[];

  void emit(String chunk) {
    if (chunk.isEmpty || skipDepth > 0) return;
    final style = TextSpanData(
      text: '',
      bold: bold > 0,
      italic: italic > 0,
      underline: underline > 0,
      strikethrough: strike > 0,
    );
    textBuf.write(chunk);
    for (var i = 0; i < chunk.length; i++) {
      styles.add(style);
    }
  }

  void emitNewline() {
    // Collapse runs: at most one blank line in a row, none at the start.
    final cur = textBuf.toString();
    if (cur.isEmpty || cur.endsWith('\n\n')) return;
    emit('\n');
  }

  var last = 0;
  for (final m in _tagRe.allMatches(html)) {
    if (m.start > last) {
      emit(_decodeEntities(_collapseWs(html.substring(last, m.start))));
    }
    last = m.end;

    final raw = m.group(0)!;
    final isClose = raw.startsWith('</');
    // Tag name: strip < / > and attributes.
    final name = raw
        .replaceAll(RegExp(r'[</>]'), ' ')
        .trim()
        .split(RegExp(r'[\s/]+'))
        .first
        .toLowerCase();

    switch (name) {
      case 'b':
      case 'strong':
        isClose ? bold = (bold - 1).clamp(0, 99) : bold++;
        break;
      case 'i':
      case 'em':
        isClose ? italic = (italic - 1).clamp(0, 99) : italic++;
        break;
      case 'u':
      case 'ins':
        isClose ? underline = (underline - 1).clamp(0, 99) : underline++;
        break;
      case 's':
      case 'strike':
      case 'del':
        isClose ? strike = (strike - 1).clamp(0, 99) : strike++;
        break;
      case 'br':
        emit('\n');
        break;
      case 'p':
      case 'div':
      case 'li':
      case 'tr':
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        if (isClose) emitNewline();
        break;
      case 'style':
      case 'script':
      case 'head':
      case 'title':
        isClose ? skipDepth = (skipDepth - 1).clamp(0, 99) : skipDepth++;
        break;
      default:
        break; // unknown tag: contributes nothing
    }
  }
  if (last < html.length) {
    emit(_decodeEntities(_collapseWs(html.substring(last))));
  }

  // Trim trailing whitespace/newlines (and matching style entries).
  var text = textBuf.toString();
  var end = text.length;
  while (end > 0 && (text[end - 1] == '\n' || text[end - 1] == ' ')) {
    end--;
  }
  var start = 0;
  while (start < end && (text[start] == '\n' || text[start] == ' ')) {
    start++;
  }
  text = text.substring(start, end);
  final trimmedStyles = styles.sublist(start, start + text.length);

  if (text.isEmpty) return null;

  // RLE into spans; all-plain → empty spans (legacy plain rendering).
  final spans = <TextSpanData>[];
  var allPlain = true;
  var runStart = 0;
  bool same(TextSpanData a, TextSpanData b) =>
      a.bold == b.bold &&
      a.italic == b.italic &&
      a.underline == b.underline &&
      a.strikethrough == b.strikethrough;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || !same(trimmedStyles[i], trimmedStyles[runStart])) {
      final st = trimmedStyles[runStart];
      if (st.bold || st.italic || st.underline || st.strikethrough) {
        allPlain = false;
      }
      spans.add(st.copyWith(text: text.substring(runStart, i)));
      runStart = i;
    }
  }
  return HtmlTextResult(text, allPlain ? const [] : spans);
}

/// Collapse HTML whitespace runs (newlines/tabs/spaces in source markup
/// are a single space when rendered).
String _collapseWs(String s) => s.replaceAll(RegExp(r'[ \t\r\n]+'), ' ');

String _decodeEntities(String s) {
  if (!s.contains('&')) return s;
  return s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAllMapped(
          RegExp(r'&#(\d+);'), (m) => _safeCharCode(m.group(1)!, 10))
      .replaceAllMapped(
          RegExp(r'&#x([0-9a-fA-F]+);'), (m) => _safeCharCode(m.group(1)!, 16))
      .replaceAll('&amp;', '&');
}

/// [String.fromCharCode] throws a RangeError above 0x10FFFF (and huge digit
/// runs overflow [int.parse]); malformed entities degrade to U+FFFD instead
/// so `htmlToSpans` keeps its "never throws" contract.
String _safeCharCode(String digits, int radix) {
  final code = int.tryParse(digits, radix: radix);
  if (code == null || code < 0 || code > 0x10FFFF) return '�';
  // Surrogate halves are not valid standalone code points either.
  if (code >= 0xD800 && code <= 0xDFFF) return '�';
  return String.fromCharCode(code);
}
