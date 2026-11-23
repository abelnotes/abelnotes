import 'dart:ui';

import 'package:abelnotes/features/canvas/data/text_paragraph_factory.dart';
import 'package:abelnotes/features/search/ink_text.dart';
import 'package:abelnotes/features/search/page_text.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/shared/utils/text_fold.dart';

/// What a find match is inside of.
enum FindSource { text, math, pdf, ink }

/// One occurrence of the query in the open notebook (see README, phase 2).
class FindMatch {
  final int pageIndex;
  final FindSource source;

  /// Text or math element id; empty for the PDF text layer; `ink:<line>` for
  /// a recognised handwritten line.
  final String elementId;

  /// Offsets in the element's text (PDF: the layer's runs joined by spaces).
  final int start, end;

  const FindMatch(
      this.pageIndex, this.source, this.elementId, this.start, this.end);

  @override
  bool operator ==(Object other) =>
      other is FindMatch &&
      other.pageIndex == pageIndex &&
      other.source == source &&
      other.elementId == elementId &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(pageIndex, source, elementId, start, end);
}

List<String> _tokens(String query) => [
      for (final t in foldForSearch(query.trim()).split(RegExp(r'\s+')))
        if (t.isNotEmpty) RegExp.escape(t),
    ];

/// Folded whole-query pattern: tokens in order, any whitespace between them.
RegExp? findPattern(String query) {
  final toks = _tokens(query);
  return toks.isEmpty ? null : RegExp(toks.join(r'\s+'));
}

/// Every match of [query] on loaded pages, in page order, then top to bottom.
/// The phrase first; when it is nowhere, each word on its own (library
/// search matches words in any order, and its hits open here).
List<FindMatch> findInNotebook(
    DocumentStructure doc, Map<String, PageData> pages, String query,
    {Map<String, List<InkLine>> ink = const {}}) {
  final pattern = findPattern(query);
  if (pattern == null) return const [];
  final phrase = _findAll(doc, pages, pattern, ink);
  final toks = _tokens(query);
  if (phrase.isNotEmpty || toks.length < 2) return phrase;
  // A one-letter word only on its own, not inside every other word.
  return _findAll(
      doc,
      pages,
      RegExp(
          toks
              .map((t) => t.length == 1
                  ? r'(?<![\p{L}\p{N}])' '$t' r'(?![\p{L}\p{N}])'
                  : t)
              .join('|'),
          unicode: true),
      ink);
}

List<FindMatch> _findAll(DocumentStructure doc, Map<String, PageData> pages,
    RegExp pattern, Map<String, List<InkLine>> ink) {
  final out = <FindMatch>[];
  for (var i = 0; i < doc.pages.length; i++) {
    final page = pages[doc.pages[i].fileName];
    if (page == null) continue;
    final found = <(double, double, FindMatch)>[];
    final lines = ink[doc.pages[i].fileName] ?? const <InkLine>[];
    for (final h in [..._haystacks(page), ..._inkHaystacks(lines)]) {
      for (final m in pattern.allMatches(h.folded)) {
        if (m.end == m.start) continue;
        final at = h.anchor(m.start);
        found.add((at.dy, at.dx, FindMatch(i, h.source, h.id, m.start, m.end)));
      }
    }
    found.sort((a, b) {
      final y = a.$1.compareTo(b.$1);
      if (y != 0) return y;
      final x = a.$2.compareTo(b.$2);
      return x != 0 ? x : a.$3.start.compareTo(b.$3.start);
    });
    out.addAll(found.map((f) => f.$3));
  }
  return out;
}

/// Where [m] is on [page], in page points: one rect per text line. [ink] is
/// the page's recognised handwriting (needed for [FindSource.ink]).
List<Rect> findMatchRects(PageData page, FindMatch m,
    {List<InkLine> ink = const []}) {
  switch (m.source) {
    case FindSource.ink:
      final k = int.tryParse(m.elementId.substring(4)) ?? -1;
      if (k < 0 || k >= ink.length) return const [];
      return [_inkRect(ink[k], m.start, m.end)];
    case FindSource.pdf:
      final layer = page.pdfTextLayer;
      return layer == null ? const [] : _pdfText(layer).rects(m.start, m.end);
    case FindSource.math:
      for (final e in page.layers.content) {
        if (e is MathElement && e.id == m.elementId) {
          final d = e.data;
          return [Rect.fromLTWH(d.x, d.y, d.width, d.height)];
        }
      }
      return const [];
    case FindSource.text:
      for (final e in page.layers.content) {
        if (e is TextElement && e.id == m.elementId) {
          return _textRects(e.data, m);
        }
      }
      return const [];
  }
}

List<Rect> _textRects(TextData t, FindMatch m) {
  final box = Rect.fromLTWH(t.x, t.y, t.width, t.height);
  // Rich spans must spell out content, and folding must keep offsets.
  final laidOut = t.spans.isEmpty
      ? t.content.length
      : t.spans.fold<int>(0, (n, s) => n + s.text.length);
  if (laidOut != t.content.length ||
      foldForSearch(t.content).length != t.content.length ||
      m.end > t.content.length) {
    return [box];
  }
  final paragraph = buildTextParagraph(t);
  try {
    final boxes = paragraph.getBoxesForRange(m.start, m.end);
    if (boxes.isEmpty) return [box];
    return [for (final b in boxes) b.toRect().shift(Offset(t.x, t.y))];
  } finally {
    paragraph.dispose();
  }
}

Iterable<_Haystack> _inkHaystacks(List<InkLine> lines) sync* {
  for (var k = 0; k < lines.length; k++) {
    final l = lines[k];
    yield _Haystack(FindSource.ink, 'ink:$k', foldForSearch(l.text),
        (_) => Offset(l.x0, l.y0));
  }
}

/// Box of characters [start, end) of a handwritten line, from their centres.
Rect _inkRect(InkLine l, int start, int end) {
  final xs = l.xs;
  if (xs.isEmpty || start >= xs.length) return Rect.fromLTRB(l.x0, l.y0, l.x1, l.y1);
  final last = (end - 1).clamp(start, xs.length - 1);
  final half = xs.length > 1
      ? (xs.last - xs.first) / (xs.length - 1) / 2
      : (l.y1 - l.y0) / 2;
  final left = start == 0 ? l.x0 : xs[start] - half;
  final right = last == xs.length - 1 ? l.x1 : xs[last] + half;
  return Rect.fromLTRB(left.clamp(l.x0, l.x1), l.y0, right.clamp(l.x0, l.x1), l.y1);
}

class _Haystack {
  final FindSource source;
  final String id;
  final String folded;
  final Offset Function(int at) anchor;
  const _Haystack(this.source, this.id, this.folded, this.anchor);
}

// Pages are immutable, so folded text is cached per page object.
final _haystackCache = Expando<List<_Haystack>>();

List<_Haystack> _haystacks(PageData page) =>
    _haystackCache[page] ??= List.unmodifiable(_buildHaystacks(page));

Iterable<_Haystack> _buildHaystacks(PageData page) sync* {
  for (final e in page.layers.content) {
    if (e is TextElement) {
      final d = e.data;
      if (d.content.isEmpty) continue;
      yield _Haystack(FindSource.text, e.id, foldForSearch(d.content),
          (_) => Offset(d.x, d.y));
    } else if (e is MathElement) {
      final d = e.data;
      final words = latexWords(d.latex);
      if (words.isEmpty) continue;
      yield _Haystack(
          FindSource.math, e.id, foldForSearch(words), (_) => Offset(d.x, d.y));
    }
  }
  final layer = page.pdfTextLayer;
  if (layer != null && layer.runs.isNotEmpty) {
    final pdf = _pdfText(layer);
    yield _Haystack(FindSource.pdf, '', pdf.folded, pdf.anchor);
  }
}

/// A PDF text layer as one string, with a box for every code unit.
class _PdfText {
  final String folded;
  final List<Rect?> boxes;
  _PdfText(this.folded, this.boxes);

  Offset anchor(int at) {
    for (var i = at; i < boxes.length; i++) {
      final b = boxes[i];
      if (b != null) return b.topLeft;
    }
    return Offset.zero;
  }

  /// Boxes of [start, end) merged into one rect per line.
  List<Rect> rects(int start, int end) {
    final out = <Rect>[];
    for (var i = start; i < end && i < boxes.length; i++) {
      final b = boxes[i];
      if (b == null) continue;
      if (out.isNotEmpty) {
        final last = out.last;
        final overlap = (last.bottom < b.bottom ? last.bottom : b.bottom) -
            (last.top > b.top ? last.top : b.top);
        final minH = last.height < b.height ? last.height : b.height;
        if (overlap > minH * 0.5 && b.left >= last.left - 1) {
          out[out.length - 1] = last.expandToInclude(b);
          continue;
        }
      }
      out.add(b);
    }
    return out;
  }
}

final _pdfCache = Expando<_PdfText>();

_PdfText _pdfText(PdfTextLayer layer) => _pdfCache[layer] ??= () {
      final text = StringBuffer();
      final boxes = <Rect?>[];
      for (final r in layer.runs) {
        if (boxes.isNotEmpty) {
          text.write(' ');
          boxes.add(null);
        }
        final whole = Rect.fromLTWH(r.x, r.y, r.width, r.height);
        final perChar = r.chars.length == r.text.length;
        for (var i = 0; i < r.text.length; i++) {
          final c = perChar ? r.chars[i] : null;
          boxes.add(
              c == null ? whole : Rect.fromLTWH(c.x, c.y, c.width, c.height));
        }
        text.write(r.text);
      }
      var folded = foldForSearch(text.toString());
      // Offsets index the boxes, so a length-changing fold is undone.
      if (folded.length != boxes.length) folded = text.toString().toLowerCase();
      if (folded.length != boxes.length) folded = text.toString();
      return _PdfText(folded, boxes);
    }();
