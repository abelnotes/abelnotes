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

  test('InkLine survives its JSON round trip', () {
    const l = InkLine('Laplace', 1, 2, 30, 12, [3, 6, 9]);
    final back = InkLine.decodeAll(InkLine.encodeAll([l])).single;
    expect(back.text, 'Laplace');
    expect(back.xs, [3, 6, 9]);
    expect(InkLine.decodeAll('not json'), isEmpty);
  });
}
