// Photo to ink on synthetic pictures: handwriting-like lines drawn on plain,
// lined and tinted shaded paper come back as strokes over the same ink.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:abelnotes/features/canvas/data/photo_ink/photo_ink.dart';
import 'package:abelnotes/features/canvas/data/photo_ink/photo_ink_strokes.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A made-up line of handwriting from (x, y): loops, arches and a tall bar
/// per letter, as polylines in image pixels.
List<List<(double, double)>> _word(double x, double y, double size, int letters) {
  final out = <List<(double, double)>>[];
  for (var k = 0; k < letters; k++) {
    final cx = x + k * size * 1.1;
    switch (k % 3) {
      case 0: // an "e"-like loop
        out.add([
          for (var t = 0; t <= 40; t++)
            (cx + size * 0.4 * math.cos(t / 40 * 2 * math.pi * 0.9), y - size * 0.4 + size * 0.4 * math.sin(t / 40 * 2 * math.pi * 0.9))
        ]);
      case 1: // an "n"-like arch
        out.add([
          for (var t = 0; t <= 30; t++) (cx - size * 0.4 + t / 30 * size * 0.8, y - size * 0.8 * math.sin(t / 30 * math.pi))
        ]);
      default: // a "t": bar and cross
        out.add([(cx, y - size * 1.4), (cx, y)]);
        out.add([(cx - size * 0.35, y - size * 0.9), (cx + size * 0.35, y - size * 0.9)]);
    }
  }
  return out;
}

img.Image _paper(int w, int h, img.Color Function(int x, int y) at) {
  final im = img.Image(width: w, height: h, numChannels: 4);
  for (final p in im) {
    final c = at(p.x, p.y);
    p
      ..r = c.r
      ..g = c.g
      ..b = c.b
      ..a = 255;
  }
  return im;
}

/// Ink multiplies the paper under it ([ink] is its transmittance, 0..1).
void _draw(img.Image im, List<List<(double, double)>> lines, double width, List<double> ink) {
  final mask = img.Image(width: im.width, height: im.height, numChannels: 1);
  for (final l in lines) {
    for (var i = 0; i + 1 < l.length; i++) {
      img.drawLine(mask,
          x1: l[i].$1.round(), y1: l[i].$2.round(), x2: l[i + 1].$1.round(), y2: l[i + 1].$2.round(),
          color: img.ColorUint8.rgb(255, 255, 255), thickness: width, antialias: true);
    }
  }
  for (final p in im) {
    final a = mask.getPixel(p.x, p.y).r / 255;
    if (a == 0) continue;
    p
      ..r = p.r * (1 - a + a * ink[0])
      ..g = p.g * (1 - a + a * ink[1])
      ..b = p.b * (1 - a + a * ink[2]);
  }
}

PhotoInk _trace(img.Image im) => photoToInk(im.getBytes(order: img.ChannelOrder.rgba), im.width, im.height);

/// Fraction of the drawn centre lines within [tol] px of a traced line
/// (recall), and of traced points within [tol] of a drawn line (precision).
(double, double) _overlap(List<List<(double, double)>> truth, List<PhotoStroke> got, double tol) {
  // About one sample per pixel along each line.
  List<(double, double)> dense(List<(double, double)> l) => [
        for (var i = 0; i + 1 < l.length; i++)
          for (var j = 0, n = math.max(1, math.sqrt(math.pow(l[i + 1].$1 - l[i].$1, 2) + math.pow(l[i + 1].$2 - l[i].$2, 2)).ceil());
              j < n;
              j++)
            (l[i].$1 + (l[i + 1].$1 - l[i].$1) * j / n, l[i].$2 + (l[i + 1].$2 - l[i].$2) * j / n),
        l.last,
      ];
  final a = [for (final l in truth) ...dense(l)];
  final b = [
    for (final s in got)
      if (!s.highlighter) ...dense([for (var i = 0; i + 1 < s.points.length; i += 2) (s.points[i], s.points[i + 1])])
  ];
  bool near((double, double) p, List<(double, double)> set) =>
      set.any((q) => (p.$1 - q.$1) * (p.$1 - q.$1) + (p.$2 - q.$2) * (p.$2 - q.$2) <= tol * tol);
  if (a.isEmpty || b.isEmpty) return (0, 0);
  return (a.where((p) => near(p, b)).length / a.length, b.where((p) => near(p, a)).length / b.length);
}

void main() {
  final white = img.ColorUint8.rgb(250, 250, 248);
  const black = [0.1, 0.1, 0.12];
  const blue = [0.12, 0.22, 0.6];

  test('written letters come back as strokes over the same ink', () {
    final im = _paper(1200, 700, (x, y) => white);
    final truth = [..._word(150, 250, 60, 9), ..._word(150, 500, 60, 9)];
    _draw(im, truth, 6, black);
    final ink = _trace(im);
    expect(ink.rectified, isFalse);
    final (recall, precision) = _overlap(truth, ink.strokes, 5);
    expect(recall, greaterThan(0.9));
    expect(precision, greaterThan(0.9));
    // Letters stay letter-sized: not shredded, not merged into one.
    expect(ink.strokes.length, inInclusiveRange(truth.length ~/ 2, truth.length * 2));
    expect(penColors(ink.strokes).toSet(), {kPhotoBlack});
  });

  test('lined paper: the ruling is not traced', () {
    final im = _paper(1200, 900, (x, y) => y % 60 < 2 ? img.ColorUint8.rgb(160, 190, 230) : white);
    final truth = [..._word(150, 239, 50, 9), ..._word(150, 479, 50, 9), ..._word(150, 719, 50, 9)];
    _draw(im, truth, 6, black);
    final ink = _trace(im);
    for (final s in ink.strokes) {
      var x0 = double.infinity, x1 = -double.infinity;
      for (var i = 0; i < s.points.length; i += 2) {
        x0 = math.min(x0, s.points[i]);
        x1 = math.max(x1, s.points[i]);
      }
      expect(x1 - x0, lessThan(0.5 * im.width), reason: 'a stroke runs along a ruling line');
    }
    final (recall, precision) = _overlap(truth, ink.strokes, 5);
    expect(recall, greaterThan(0.85));
    expect(precision, greaterThan(0.9));
  });

  test('squared paper with a darker grid: the grid is not traced', () {
    final grid = img.ColorUint8.rgb(150, 170, 205);
    final im = _paper(1200, 900, (x, y) => y % 40 < 3 || x % 40 < 3 ? grid : white);
    final truth = [..._word(150, 239, 50, 9), ..._word(150, 479, 50, 9), ..._word(150, 719, 50, 9)];
    _draw(im, truth, 6, black);
    final ink = _trace(im);
    for (final s in ink.strokes) {
      var x0 = double.infinity, x1 = -double.infinity, y0 = double.infinity, y1 = -double.infinity;
      for (var i = 0; i < s.points.length; i += 2) {
        x0 = math.min(x0, s.points[i]);
        x1 = math.max(x1, s.points[i]);
        y0 = math.min(y0, s.points[i + 1]);
        y1 = math.max(y1, s.points[i + 1]);
      }
      expect(math.max(x1 - x0, y1 - y0), lessThan(0.4 * im.width), reason: 'a stroke runs along the grid');
    }
    final (recall, precision) = _overlap(truth, ink.strokes, 5);
    expect(recall, greaterThan(0.8));
    expect(precision, greaterThan(0.9));
  });

  test('a loop the photo filled in comes back as a ring, not a stub', () {
    final im = _paper(1600, 400, (x, y) => white);
    // "o"s whose hole the photo lost (solid disks), beside bars of the pen.
    final truth = [
      for (var k = 0; k < 5; k++) ...[
        [for (var t = 0; t <= 24; t++) (200.0 + k * 300 + 8 * math.cos(t / 24 * 2 * math.pi), 200.0 + 8 * math.sin(t / 24 * 2 * math.pi))],
        [(230.0 + k * 300, 160.0), (230.0 + k * 300, 240.0)],
      ]
    ];
    _draw(im, truth, 6, black);
    _draw(im, [for (var k = 0; k < 5; k++) [(200.0 + k * 300, 200.0), (200.0 + k * 300, 200.0)]], 20, black);
    final ink = _trace(img.gaussianBlur(im, radius: 1));
    final (recall, _) = _overlap(truth, ink.strokes, 3);
    expect(recall, greaterThan(0.8));
    for (var k = 0; k < 5; k++) {
      // The centre is open: no traced point sits on it.
      for (final s in ink.strokes) {
        for (var i = 0; i < s.points.length; i += 2) {
          expect(math.sqrt(math.pow(s.points[i] - 200 - k * 300, 2) + math.pow(s.points[i + 1] - 200, 2)), greaterThan(3));
        }
      }
    }
  });

  test('an E is one or two strokes, not one per bar', () {
    final im = _paper(500, 300, (x, y) => white);
    List<List<(double, double)>> e(double x) => [
          [(x + 40, 80), (x, 80), (x, 220), (x + 40, 220)],
          [(x, 150), (x + 32, 150)],
        ];
    final truth = [...e(100), ...e(250)];
    _draw(im, truth, 7, black);
    final ink = _trace(im);
    final (recall, precision) = _overlap(truth, ink.strokes, 4);
    expect(recall, greaterThan(0.9));
    expect(precision, greaterThan(0.9));
    expect(ink.strokes.length, inInclusiveRange(2, 4));
  });

  test('tinted paper under uneven light and a hard shadow: only the ink', () {
    final im = _paper(1200, 800, (x, y) {
      final light = 1.0 - 0.4 * x / 1200 - (x + y > 1300 ? 0.3 : 0);
      return img.ColorUint8.rgb((250 * light).round(), (235 * light).round(), (190 * light).round());
    });
    final truth = [..._word(150, 250, 60, 9), ..._word(150, 550, 60, 9)];
    _draw(im, truth, 6, blue);
    // A photo is never pixel sharp: the shadow edge is a pixel or two soft.
    final ink = _trace(img.gaussianBlur(im, radius: 2));
    final (recall, precision) = _overlap(truth, ink.strokes, 5);
    expect(recall, greaterThan(0.85));
    expect(precision, greaterThan(0.9));
    expect(penColors(ink.strokes).toSet(), {kPhotoBlue});
  });

  test('a highlighter band is kept apart from the pen', () {
    final im = _paper(1200, 600, (x, y) => white);
    final truth = _word(150, 300, 60, 9);
    _draw(im, [[(120, 270), (1100, 270)]], 60, [1.0, 0.95, 0.3]);
    _draw(im, truth, 6, black);
    final ink = _trace(im);
    expect(ink.strokes.where((s) => s.highlighter), isNotEmpty);
    final (_, precision) = _overlap(truth, ink.strokes, 5);
    expect(precision, greaterThan(0.9));
  });

  test('a sheet photographed on a desk is straightened', () {
    // A 3:4 sheet turned by 8 degrees, on a dark desk.
    const a = 8 * math.pi / 180;
    (double, double) rot(double x, double y) =>
        (700 + (x - 700) * math.cos(a) - (y - 700) * math.sin(a), 700 + (x - 700) * math.sin(a) + (y - 700) * math.cos(a));
    final im = _paper(1400, 1400, (x, y) {
      // Back into the sheet's own frame: inside the rectangle is paper.
      final u = 700 + (x - 700) * math.cos(a) + (y - 700) * math.sin(a);
      final v = 700 - (x - 700) * math.sin(a) + (y - 700) * math.cos(a);
      return u >= 250 && u <= 1150 && v >= 100 && v <= 1300 ? img.ColorUint8.rgb(245, 245, 240) : img.ColorUint8.rgb(60, 45, 35);
    });
    final truth = [
      for (final l in _word(350, 500, 50, 8)) [for (final (x, y) in l) rot(x, y)]
    ];
    _draw(im, truth, 6, black);
    final ink = _trace(im);
    expect(ink.rectified, isTrue);
    expect(ink.width / ink.height, closeTo(900 / 1200, 0.03));
    // Back in the photo, the strokes lie on the ink.
    final m = ink.toSource;
    final back = [
      for (final s in ink.strokes)
        PhotoStroke(
            Float64List.fromList([
              for (var i = 0; i + 1 < s.points.length; i += 2)
                for (final v in () {
                  final z = m[6] * s.points[i] + m[7] * s.points[i + 1] + m[8];
                  return [
                    (m[0] * s.points[i] + m[1] * s.points[i + 1] + m[2]) / z,
                    (m[3] * s.points[i] + m[4] * s.points[i + 1] + m[5]) / z
                  ];
                }())
                  v
            ]),
            s.width,
            s.color)
    ];
    final (recall, precision) = _overlap(truth, back, 5);
    expect(recall, greaterThan(0.85));
    expect(precision, greaterThan(0.9));
  });

  test('strokes are placed in the picture box, a straightened sheet keeping its shape', () {
    final ink = PhotoInk([
      PhotoStroke(Float64List.fromList([0, 0, 300, 400]), 4, 0xFF101010),
    ], 300, 400, Float64List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1]), rectified: true);
    const d = ImageData(assetPath: 'a.jpg', x: 100, y: 50, width: 600, height: 400);
    final s = placePhotoInk(ink, d).single;
    // 300 x 400 fitted into 600 x 400: scale 1, centred horizontally.
    expect(s.points.first.x, closeTo(250, 0.01));
    expect(s.points.first.y, closeTo(50, 0.01));
    expect(s.points.last.x, closeTo(550, 0.01));
    expect(s.points.last.y, closeTo(450, 0.01));
    expect(s.color, kPhotoBlack);
    expect(s.baseWidth, closeTo(4, 0.01));
    // Pen ink, so the handwriting search reads it (it skips technical lines).
    expect(s.toolType, 'ballpoint');
    expect(isTechnicalTool(s.toolType), isFalse);
  });

  test('ink colours map to pens; one dominant pen colours the page', () {
    expect(inkClass(0xFF1A1A1E), kPhotoBlack);
    expect(inkClass(0xFF2A3C9A), kPhotoBlue);
    expect(inkClass(0xFFB82020), kPhotoRed);
    PhotoStroke s(int c, double len) => PhotoStroke(Float64List.fromList([0, 0, len, 0]), 2, c);
    expect(penColors([s(0xFF2A3C9A, 1000), s(0xFF1A1A1E, 10)]), [kPhotoBlue, kPhotoBlue]);
    expect(penColors([s(0xFF2A3C9A, 500), s(0xFFB82020, 500)]), [kPhotoBlue, kPhotoRed]);
    expect(highlighterColor(0xFFFFF070), 0xFFFFEB3B);
  });
}
