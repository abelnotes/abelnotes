// Selection logic over the PDF text layer: nearest-glyph hit-testing, drag
// range, tap-to-select-line, cross-run joining (space vs newline), and the
// copied-text reconstruction. Pure (page-logical coords) — no widgets.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/features/canvas/presentation/pdf_text_selection.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Build a run with one char box per character, laid out left-to-right at
/// [y] with [charW]-wide cells starting at [x].
PdfTextRun _run(String text, double x, double y,
    {double charW = 10, double h = 12}) {
  final chars = <PdfCharBox>[];
  for (var i = 0; i < text.length; i++) {
    chars.add(PdfCharBox(x: x + i * charW, y: y, width: charW, height: h));
  }
  return PdfTextRun(
      text: text, x: x, y: y, width: text.length * charW, height: h, chars: chars);
}

void main() {
  group('PdfTextSelectionController', () {
    // Two lines: "Hello" at y=0, "World" at y=20.
    PdfTextLayer layer() => PdfTextLayer(
          sourceAssetPath: 'a.png',
          runs: [_run('Hello', 0, 0), _run('World', 0, 20)],
        );

    test('drag across part of a line selects those characters', () {
      final c = PdfTextSelectionController(layer());
      c.begin(const Offset(1, 6)); // 'H'
      c.update(const Offset(28, 6)); // ~'l' (index 2..3)
      expect(c.selectedText(), 'Hel');
      c.end();
      expect(c.selectedText(), 'Hel'); // drag => not promoted to whole line
    });

    test('tap (no drag) promotes to the whole line', () {
      final c = PdfTextSelectionController(layer());
      c.begin(const Offset(22, 6)); // somewhere in "Hello"
      c.end();
      expect(c.selectedText(), 'Hello');
    });

    test('selection spanning two lines joins with a newline', () {
      final c = PdfTextSelectionController(layer());
      c.begin(const Offset(1, 6)); // 'H' on line 1
      c.update(const Offset(48, 26)); // last char of line 2
      expect(c.selectedText(), 'Hello\nWorld');
    });

    test('same-line runs join with a space', () {
      final c = PdfTextSelectionController(PdfTextLayer(
        sourceAssetPath: 'a.png',
        runs: [_run('foo', 0, 0), _run('bar', 60, 0)], // both y=0
      ));
      c.begin(const Offset(1, 6));
      c.update(const Offset(88, 6)); // well inside the final 'r' (x 80..90)
      expect(c.selectedText(), 'foo bar');
    });

    test('clear removes the selection', () {
      final c = PdfTextSelectionController(layer());
      c.begin(const Offset(1, 6));
      c.end();
      expect(c.hasSelection, isTrue);
      c.clear();
      expect(c.hasSelection, isFalse);
      expect(c.selectedText(), '');
    });

    test('selectedPageRects covers the selected glyphs', () {
      final c = PdfTextSelectionController(layer());
      c.begin(const Offset(1, 6));
      c.update(const Offset(18, 6)); // H,e
      final rects = c.selectedPageRects();
      expect(rects.length, 2);
    });

    test('run without char boxes selects at run granularity', () {
      final c = PdfTextSelectionController(PdfTextLayer(
        sourceAssetPath: 'a.png',
        runs: [
          const PdfTextRun(
              text: 'whole line', x: 0, y: 0, width: 100, height: 12),
        ],
      ));
      c.begin(const Offset(50, 6));
      expect(c.selectedText(), 'whole line');
    });
  });
}
