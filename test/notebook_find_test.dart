// Find in notebook (search phase 2): matching, order, rectangles, controller.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/search/ink_text.dart';
import 'package:abelnotes/features/search/notebook_find.dart';
import 'package:abelnotes/features/search/notebook_find_bar.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

ContentElement _text(String id, String content,
        {double x = 50, double y = 50, double width = 300}) =>
    ContentElement.text(
      id: id,
      zIndex: 0,
      data: TextData(
          x: x, y: y, width: width, height: 40, content: content, fontSize: 16),
    );

PageData _page(String id,
        {List<ContentElement> content = const [], PdfTextLayer? pdf}) =>
    PageData(
      pageId: id,
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: RenderingLayers(content: content),
      pdfTextLayer: pdf,
    );

({DocumentStructure doc, Map<String, PageData> pages}) _book(
    List<PageData> pages) {
  final doc = DocumentStructure(notebookId: 'nb', pages: [
    for (var i = 0; i < pages.length; i++)
      PageEntry(pageId: pages[i].pageId, pageNumber: i + 1, fileName: 'p$i.json'),
  ]);
  return (
    doc: doc,
    pages: {for (var i = 0; i < pages.length; i++) 'p$i.json': pages[i]},
  );
}

PdfTextLayer _pdf(List<(String, double)> lines) => PdfTextLayer(
      sourceAssetPath: 'a',
      runs: [
        for (final (text, y) in lines)
          PdfTextRun(
            text: text,
            x: 40,
            y: y,
            width: text.length * 6.0,
            height: 10,
            chars: [
              for (var i = 0; i < text.length; i++)
                PdfCharBox(x: 40 + i * 6.0, y: y, width: 6, height: 10),
            ],
          ),
      ],
    );

void main() {
  test('case and accents fold, pages in order, top to bottom on a page', () {
    final b = _book([
      _page('a', content: [
        _text('low', 'la città di Ohm', y: 400),
        _text('high', 'OHM e citta', y: 80),
      ]),
      _page('b'),
      _page('c', content: [_text('t', 'Legge di ohm')]),
    ]);
    final m = findInNotebook(b.doc, b.pages, 'ohm');
    expect([for (final x in m) (x.pageIndex, x.elementId)],
        [(0, 'high'), (0, 'low'), (2, 't')]);
    expect(findInNotebook(b.doc, b.pages, 'CITTÀ').map((x) => x.elementId),
        ['high', 'low']);
    expect(findInNotebook(b.doc, b.pages, '   '), isEmpty);
  });

  test('a phrase matches across line breaks; missing phrase falls back to words',
      () {
    final b = _book([
      _page('a', content: [_text('t', 'transfer\nfunction of the loop')]),
      _page('b', content: [_text('u', 'loop gain and transfer')]),
    ]);
    final phrase = findInNotebook(b.doc, b.pages, 'transfer function');
    expect(phrase, hasLength(1));
    expect((phrase.single.start, phrase.single.end), (0, 17));

    final words = findInNotebook(b.doc, b.pages, 'loop transfer');
    // No page has "loop transfer" in that order: every word is shown.
    expect(words.map((x) => (x.pageIndex, x.start)).toList(),
        [(0, 0), (0, 25), (1, 0), (1, 14)]);
  });

  test('in the word fallback a one-letter word is matched only on its own', () {
    final b = _book([
      _page('a', content: [_text('t', 'Errore: cancella e riscrivi')]),
    ]);
    final m = findInNotebook(b.doc, b.pages, 'riscrivi e cancella');
    expect(m.map((x) => (x.start, x.end)).toList(), [(8, 16), (17, 18), (19, 27)]);
    // Regex syntax in a fallback query stays literal (unicode mode).
    expect(findInNotebook(b.doc, b.pages, 'x (a+b)* - / e'), hasLength(1));
  });

  test('regex characters in the query are literal', () {
    final b = _book([
      _page('a', content: [_text('t', 'costo (a+b)* 2 e a.b')]),
    ]);
    expect(findInNotebook(b.doc, b.pages, '(a+b)*'), hasLength(1));
    expect(findInNotebook(b.doc, b.pages, 'a.b'), hasLength(1));
  });

  test('math matches its words, highlighted as the whole formula', () {
    final page = _page('a', content: [
      const ContentElement.math(
        id: 'm',
        zIndex: 0,
        data: MathData(
            x: 10, y: 20, width: 80, height: 30, latex: r'\omega_0 = \frac{1}{RC}'),
      ),
    ]);
    final b = _book([page]);
    expect(findInNotebook(b.doc, b.pages, 'frac'), isEmpty);
    final m = findInNotebook(b.doc, b.pages, 'omega').single;
    expect(m.source, FindSource.math);
    expect(findMatchRects(page, m), [const Rect.fromLTWH(10, 20, 80, 30)]);
  });

  test('pdf matches span runs and give one rect per line', () {
    final page = _page('a', pdf: _pdf([('Fourier', 100), ('transform', 120)]));
    final b = _book([page]);
    final m = findInNotebook(b.doc, b.pages, 'fourier transform').single;
    expect(m.source, FindSource.pdf);
    final rects = findMatchRects(page, m);
    expect(rects, hasLength(2));
    expect(rects[0], const Rect.fromLTWH(40, 100, 42, 10));
    expect(rects[1], const Rect.fromLTWH(40, 120, 54, 10));

    final one = findInNotebook(b.doc, b.pages, 'rans').single;
    expect(findMatchRects(page, one), [const Rect.fromLTWH(46, 120, 24, 10)]);
  });

  test('typed text rects come from the laid-out paragraph', () {
    final page = _page('a', content: [_text('t', 'alpha beta gamma', x: 100, y: 200)]);
    final b = _book([page]);
    final m = findInNotebook(b.doc, b.pages, 'beta').single;
    final r = findMatchRects(page, m);
    expect(r, hasLength(1));
    // Inside the box, right of its left edge (not the whole element).
    expect(r.single.left, greaterThan(100));
    expect(r.single.top, greaterThanOrEqualTo(200));
    expect(r.single.right, lessThan(400));
    expect(r.single.width, lessThan(300));
  });

  test('text whose spans disagree with content falls back to the box', () {
    final page = _page('a', content: [
      const ContentElement.text(
        id: 't',
        zIndex: 0,
        data: TextData(
          x: 5,
          y: 6,
          width: 70,
          height: 20,
          content: 'hello world',
          spans: [TextSpanData(text: 'hello')],
        ),
      ),
    ]);
    final b = _book([page]);
    final m = findInNotebook(b.doc, b.pages, 'world').single;
    expect(findMatchRects(page, m), [const Rect.fromLTWH(5, 6, 70, 20)]);
  });

  test('handwriting lines are found and boxed by their character centres', () {
    final b = _book([_page('a'), _page('b')]);
    const line = InkLine('Laplace ok', 100, 50, 200, 70,
        [105, 115, 125, 135, 145, 155, 165, 175, 185, 195]);
    final m = findInNotebook(b.doc, b.pages, 'place', ink: {'p1.json': [line]}).single;
    expect((m.pageIndex, m.source, m.elementId, m.start, m.end), (1, FindSource.ink, 'ink:0', 2, 7));
    final r = findMatchRects(b.pages['p1.json']!, m, ink: [line]).single;
    expect(r, const Rect.fromLTRB(120, 50, 170, 70));
  });

  group('controller', () {
    final b = _book([
      _page('a', content: [_text('t', 'node one')]),
      _page('b', content: [_text('t', 'node two node')]),
      _page('c', content: [_text('t', 'node three')]),
    ]);

    test('starts from the current page and wraps both ways', () {
      final c = NotebookFindController()..open();
      c.setQuery('node', b.doc, b.pages, 1);
      expect(c.matches, hasLength(4));
      expect(c.currentMatch!.pageIndex, 1);
      expect(c.pagesWithMatches, {0, 1, 2});
      c.step(-1);
      expect(c.currentMatch!.pageIndex, 0);
      c.step(-1);
      expect(c.currentMatch!.pageIndex, 2);
      c.step(1);
      expect(c.current, 0);
    });

    test('an edit keeps the current match, a removed one moves on', () {
      final c = NotebookFindController()..open();
      c.setQuery('node', b.doc, b.pages, 2);
      expect(c.currentMatch!.pageIndex, 2);
      final edited = Map.of(b.pages)
        ..['p0.json'] = _page('a', content: [_text('t', 'node one node')]);
      c.sync(b.doc, edited);
      expect(c.matches, hasLength(5));
      expect(c.currentMatch!.pageIndex, 2);

      final gone = Map.of(edited)
        ..['p2.json'] = _page('c', content: [_text('t', 'empty')]);
      c.sync(b.doc, gone);
      expect(c.matches, hasLength(4));
      expect(c.currentMatch!.pageIndex, 1, reason: 'last one before it');
    });

    test('close clears everything', () {
      final c = NotebookFindController()..open();
      c.setQuery('node', b.doc, b.pages, 0);
      c.close();
      expect(c.isOpen, isFalse);
      expect(c.matches, isEmpty);
      expect(c.currentMatch, isNull);
    });
  });

  test('5000 pages are searched fast', () {
    final pages = [
      for (var i = 0; i < 5000; i++)
        _page('p$i', content: [
          _text('t', 'Lecture $i: the Laplace transform of signals and systems '
              'with some more words to make the page realistic ${i % 7}'),
        ]),
    ];
    final b = _book(pages);
    findInNotebook(b.doc, b.pages, 'warm up the fold cache');
    final sw = Stopwatch()..start();
    final m = findInNotebook(b.doc, b.pages, 'laplace');
    sw.stop();
    // ignore: avoid_print
    print('find over 5000 pages: ${sw.elapsedMilliseconds} ms');
    expect(m, hasLength(5000));
    expect(sw.elapsedMilliseconds, lessThan(200));
  });
}
