// Handwriting line segmentation and the recognised-line format.

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/search/ink_text.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

StrokeData _stroke(List<num> flat) => StrokeData(points: [
      for (var i = 0; i + 1 < flat.length; i += 2)
        StrokePoint(x: flat[i].toDouble(), y: flat[i + 1].toDouble()),
    ]);

void main() {
  test('segmentation keeps a written line and drops a lone mark', () {
    // Three "letters" on one line, a dot far away.
    final strokes = [
      _stroke([10, 10, 14, 30, 18, 10]),
      _stroke([22, 12, 26, 30, 30, 12]),
      _stroke([34, 10, 38, 30, 42, 12]),
      _stroke([300, 300, 301, 301]),
    ];
    final segs = segmentInk(strokes);
    expect(segs, hasLength(1));
    expect(segs.single.strokes, hasLength(3));
  });

  test('tails, t-bars and dots stay with their line', () {
    // Letters on a 10..30 band, a p tail below, an i dot and a t-bar above.
    final strokes = [
      _stroke([10, 10, 14, 30, 18, 10]),
      _stroke([22, 12, 26, 30, 30, 12]),
      _stroke([34, 10, 38, 30, 42, 12]),
      _stroke([46, 10, 50, 30, 54, 12]),
      _stroke([58, 10, 62, 30, 66, 12]),
      _stroke([11, 20, 11, 50]), // tail
      _stroke([26, 3, 26.5, 3.5]), // dot
      _stroke([31, 6, 45, 6]), // t-bar
      _stroke([300, 300, 301, 301]), // far away: still dropped
    ];
    final segs = segmentInk(strokes);
    expect(segs, hasLength(1));
    expect(segs.single.strokes, hasLength(8));
  });

  test('a line cut into short pieces with small gaps stays one line', () {
    // Five zigzag letters on a 10..30 band, each cut in three with 1 pt gaps
    // (as traced photo ink comes), plus an i dot.
    final strokes = <StrokeData>[];
    for (var k = 0; k < 5; k++) {
      final x = 10.0 + 14 * k;
      strokes
        ..add(_stroke([x, 10, x + 2, 19.5]))
        ..add(_stroke([x + 2.2, 20.5, x + 4, 30, x + 5.8, 20.5]))
        ..add(_stroke([x + 6, 19.5, x + 8, 10]));
    }
    strokes.add(_stroke([40, 3, 40.5, 3.5]));
    final segs = segmentInk(strokes);
    expect(segs, hasLength(1));
    expect(segs.single.strokes, hasLength(16));
  });

  test('a descender after capitals stays on their line', () {
    // "4 Cam" with tall glyphs, then a p whose tail hangs below their band
    // and more letters: one line, not two.
    final strokes = [
      _stroke([24, 60, 26, 84, 29, 70]),
      _stroke([59, 60, 49, 70, 59, 79]),
      _stroke([58, 69, 66, 81, 75, 70]),
      _stroke([77, 72, 79, 94, 81, 75]),
      _stroke([85, 72, 86, 81]),
      _stroke([110, 56, 96, 94, 122, 70]),
      _stroke([127, 58, 130, 81]),
      _stroke([134, 70, 142, 81, 150, 70]),
    ];
    final segs = segmentInk(strokes);
    expect(segs, hasLength(1));
    expect(segs.single.strokes, hasLength(8));
  });

  test('two rows (a fraction) are not read as one line', () {
    final strokes = [
      for (var k = 0; k < 4; k++)
        _stroke([10.0 + 12 * k, 0, 14.0 + 12 * k, 12, 18.0 + 12 * k, 0]),
      _stroke([8, 16, 60, 16]), // bar
      for (var k = 0; k < 4; k++)
        _stroke([10.0 + 12 * k, 20, 14.0 + 12 * k, 32, 18.0 + 12 * k, 20]),
    ];
    for (final s in segmentInk(strokes)) {
      expect(s.y1 - s.y0, lessThan(20), reason: 'a segment spans both rows');
    }
  });

  test('InkLine survives its JSON round trip', () {
    const l = InkLine('Laplace', 1, 2, 30, 12, [3, 6, 9]);
    final back = InkLine.decodeAll(InkLine.encodeAll([l])).single;
    expect(back.text, 'Laplace');
    expect(back.xs, [3, 6, 9]);
    expect(back.alt, isFalse);
    const plain = InkLine('Lapiace', 1, 2, 30, 12, [3], alt: true);
    expect(InkLine.decodeAll(InkLine.encodeAll([plain])).single.alt, isTrue);
    expect(InkLine.decodeAll('not json'), isEmpty);
  });
}
