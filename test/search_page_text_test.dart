// Search index text extraction: typed text, LaTeX words and the PDF text
// layer, from a decoded page and from stored bytes (JSON and binary forms).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart'
    show binaryPageBytes, compactPageJson;
import 'package:abelnotes/features/search/page_text.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

PageData _page({
  List<String> texts = const [],
  List<String> maths = const [],
  List<String> pdfRuns = const [],
}) {
  var z = 0;
  return PageData(
    pageId: 'p1',
    pageNumber: 1,
    width: 595,
    height: 842,
    layers: RenderingLayers(content: [
      ContentElement.stroke(
        id: 's',
        zIndex: z++,
        data: const StrokeData(points: [
          StrokePoint(x: 1, y: 2),
          StrokePoint(x: 3.5, y: 4.25, pressure: 0.8),
        ]),
      ),
      for (final t in texts)
        ContentElement.text(
          id: 't${z++}',
          zIndex: z,
          data: TextData(x: 0, y: 0, width: 100, height: 20, content: t),
        ),
      for (final m in maths)
        ContentElement.math(
          id: 'm${z++}',
          zIndex: z,
          data: MathData(x: 0, y: 0, width: 40, height: 20, latex: m),
        ),
    ]),
    pdfTextLayer: pdfRuns.isEmpty
        ? null
        : PdfTextLayer(sourceAssetPath: 'a', runs: [
            for (final r in pdfRuns)
              PdfTextRun(text: r, x: 0, y: 0, width: 10, height: 10),
          ]),
  );
}

void main() {
  test('typed text, math words and pdf runs end up in their lines', () {
    final t = extractPageText(_page(
      texts: ['Hello  World\nsecond line', 'Città Nuova'],
      maths: [r'\omega_0 = \frac{1}{\sqrt{LC}}'],
      pdfRuns: ['Fourier', 'transform of'],
    ));
    expect(t.sources, TextSource.text | TextSource.math | TextSource.pdf);
    expect(t.parts, '2,1,1');
    expect(t.raw.split('\n'), [
      'Hello World second line',
      'Città Nuova',
      r'\omega_0 = \frac{1}{\sqrt{LC}}',
      'Fourier transform of',
    ]);
    expect(t.folded.split('\n'), [
      'hello world second line',
      'citta nuova',
      'omega 0 1 lc',
      'fourier transform of',
    ]);
  });

  test('latexWords keeps names people search for and drops the markup', () {
    expect(latexWords(r'\alpha + \beta^{2}'), 'alpha beta 2');
    expect(latexWords(r'\frac{a}{b}'), 'a b');
    expect(latexWords(r'\int_0^\infty e^{-x}\,dx'), '0 infty e x dx');
    expect(latexWords(r'\sin(\theta) = 3.14'), 'sin theta 3.14');
    expect(latexWords(r'\text{Volt}'), 'Volt');
    expect(latexWords(r'{}^_\\'), '');
  });

  test('a page with no text has no rows of text', () {
    final t = extractPageText(_page());
    expect(t.isEmpty, isTrue);
    expect(t.sources, 0);
    expect(extractPageText(_page(texts: ['   ', '\n'])).isEmpty, isTrue);
  });

  test('stored bytes give the same text in JSON and binary form', () {
    final page = _page(
        texts: ['caffè', 'Ünï'],
        maths: [r'\gamma'],
        pdfRuns: ['alpha', 'beta']);
    final want = extractPageText(page);
    final json = utf8.encode(compactPageJson(page));
    final bin = binaryPageBytes(page)!;
    for (final bytes in [json, bin]) {
      final got = extractPageTextFromBytes(bytes);
      expect(got.raw, want.raw);
      expect(got.folded, want.folded);
      expect(got.sources, want.sources);
      expect(got.parts, want.parts);
    }
  });

  test('unreadable bytes throw FormatException, a newer binary too', () {
    expect(() => extractPageTextFromBytes(utf8.encode('not json')),
        throwsFormatException);
    expect(() => extractPageTextFromBytes(utf8.encode('[1,2]')),
        throwsFormatException);
    expect(() => extractPageTextFromBytes([0x41, 0x42, 0x50, 0x47, 9, 0]),
        throwsFormatException);
  });
}
