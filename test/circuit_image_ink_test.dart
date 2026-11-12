// Picture -> strokes for the circuit tidy-up, on synthetic images.
import 'dart:math';
import 'dart:typed_data';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/image_ink.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/raster.dart';
import 'package:flutter_test/flutter_test.dart';

class _Canvas {
  _Canvas(this.w, this.h) : rgba = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
  final int w, h;
  final Uint8List rgba;

  void dot(int x, int y, (int, int, int) c) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = 4 * (y * w + x);
    rgba[i] = c.$1;
    rgba[i + 1] = c.$2;
    rgba[i + 2] = c.$3;
  }

  void line(int x0, int y0, int x1, int y1, (int, int, int) c) {
    final n = max(1, max((x1 - x0).abs(), (y1 - y0).abs()));
    for (var k = 0; k <= n; k++) {
      dot(x0 + ((x1 - x0) * k / n).round(), y0 + ((y1 - y0) * k / n).round(), c);
    }
  }
}

double _length(TracedStroke s) {
  var len = 0.0;
  for (var i = 2; i + 1 < s.points.length; i += 2) {
    len += sqrt(pow(s.points[i] - s.points[i - 2], 2) + pow(s.points[i + 1] - s.points[i - 1], 2));
  }
  return len;
}

void main() {
  test('a faint one-pixel printed wire is traced, in black', () {
    final c = _Canvas(400, 300);
    const faint = (235, 235, 235);
    c
      ..line(50, 50, 350, 50, faint)
      ..line(350, 50, 350, 250, faint)
      ..line(350, 250, 50, 250, faint)
      ..line(50, 250, 50, 50, faint);
    final out = traceImageInk(c.rgba, c.w, c.h);
    final total = out.fold(0.0, (a, s) => a + _length(s));
    expect(total, closeTo(1000, 60));
    expect(out.map((s) => s.color).toSet(), {0xFF000000});
    final xs = [for (final s in out) for (var i = 0; i < s.points.length; i += 2) s.points[i]];
    expect(xs.reduce(min), closeTo(50, 3));
    expect(xs.reduce(max), closeTo(350, 3));
  });

  test('coloured ink keeps its colour, ink width is measured', () {
    final c = _Canvas(400, 300);
    for (var y = 148; y <= 152; y++) {
      c.line(60, y, 340, y, (20, 40, 220));
    }
    final out = traceImageInk(c.rgba, c.w, c.h);
    expect(out, hasLength(1));
    final col = out.single.color;
    expect(col & 0xFF, greaterThan(150));
    expect((col >> 16) & 0xFF, lessThan(80));
    expect(out.single.width, closeTo(5, 1.5));
  });

  test('a screenshot frame and specks are dropped', () {
    final c = _Canvas(400, 300);
    const grey = (120, 120, 120);
    c
      ..line(0, 0, 399, 0, grey)
      ..line(0, 299, 399, 299, grey)
      ..line(0, 0, 0, 299, grey)
      ..line(399, 0, 399, 299, grey)
      ..line(100, 150, 300, 150, grey)
      ..dot(200, 60, grey)
      ..dot(201, 60, grey);
    final out = traceImageInk(c.rgba, c.w, c.h);
    expect(out, hasLength(1));
    final ys = [for (var i = 1; i < out.single.points.length; i += 2) out.single.points[i]];
    expect(ys.every((y) => (y - 150).abs() < 2), isTrue);
  });

  test('a filled arrowhead goes in as nested outlines, the wire as a line', () {
    final c = _Canvas(400, 300);
    const ink = (30, 30, 30);
    for (var y = 149; y <= 151; y++) {
      c.line(40, y, 360, y, ink);
    }
    // Head pointing right, tip at x 230.
    for (var x = 200; x <= 230; x++) {
      final half = ((230 - x) * 0.5).round();
      c.line(x, 150 - half, x, 150 + half, ink);
    }
    final out = traceImageInk(c.rgba, c.w, c.h);
    bool closed(TracedStroke s) =>
        s.points.length >= 8 &&
        s.points[0] == s.points[s.points.length - 2] &&
        s.points[1] == s.points[s.points.length - 1];
    final rings = out.where(closed).toList();
    expect(rings.length, greaterThanOrEqualTo(2));
    for (final r in rings) {
      for (var i = 0; i < r.points.length; i += 2) {
        expect(r.points[i], inInclusiveRange(195, 235));
      }
    }
  });

  test('the leftover keeps what was not cut, on a clear background', () {
    final c = _Canvas(300, 200);
    const ink = (20, 20, 20);
    for (var y = 49; y <= 51; y++) {
      c.line(20, y, 280, y, ink);
    }
    for (var y = 148; y <= 151; y++) {
      c.line(130, y, 170, y, (200, 20, 20)); // a red pen mark
    }
    final left = inkLeftover(c.rgba, c.w, c.h, [(Float64List.fromList([20, 50, 280, 50]), 3.0)]);
    expect(left, isNotNull);
    final (rgba, x0, y0, w, h) = left!;
    // Only the red mark is left, cropped to it, colour kept.
    expect(x0, closeTo(130, 2));
    expect(y0, closeTo(148, 2));
    expect(w, closeTo(41, 3));
    expect(h, closeTo(4, 2));
    final mid = 4 * ((h ~/ 2) * w + w ~/ 2);
    expect(rgba[mid], 200);
    expect(rgba[mid + 3], greaterThan(200));
  });

  test('a grainy photo keeps a pen line only a few times above the grain', () {
    final c = _Canvas(400, 300);
    var seed = 7;
    for (var y = 0; y < c.h; y++) {
      for (var x = 0; x < c.w; x++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        final v = 255 - (seed >> 8) % 41;
        c.dot(x, y, (v, v, v));
      }
    }
    for (var y = 148; y <= 152; y++) {
      c.line(60, y, 340, y, (170, 170, 170));
    }
    final out = traceImageInk(c.rgba, c.w, c.h);
    final along = out.where((s) => _length(s) > 100).toList();
    expect(along, isNotEmpty);
    expect(along.fold(0.0, (a, s) => a + _length(s)), greaterThan(250));
  });

  test('the detector plane of a picture is its ink, where the strokes lie', () {
    final c = _Canvas(400, 300);
    for (var y = 148; y <= 152; y++) {
      c.line(60, y, 340, y, (20, 20, 20));
    }
    final t = traceImage(c.rgba, c.w, c.h);
    final strokes = [for (final s in t.strokes) s.points];
    final r = rasterizeInk(t.ink, strokes, c.w.toDouble());
    final row = r.toPxY(150).round();
    final mid = r.toPxX(200).round();
    expect(r.data[row * r.width + mid], lessThan(0.2));
    expect(r.data[(row - 12) * r.width + mid], 1.0);
  });

  test('ink on tinted paper comes out black, background off the edge is not kept', () {
    final c = _Canvas(300, 200);
    for (var y = 0; y < 200; y++) {
      c.line(0, y, 299, y, (140, 200, 90)); // green sheet
    }
    for (var y = 0; y < 200; y++) {
      c.line(0, y, 12, y, (90, 60, 40)); // table showing on the left edge
    }
    for (var y = 99; y <= 101; y++) {
      c.line(60, y, 240, y, (40, 70, 30)); // pen on the sheet
    }
    final traced = traceImageInk(c.rgba, c.w, c.h);
    final pen = traced.where((t) => t.points[1] > 90 && t.points[1] < 110 && t.points[0] > 40).toList();
    expect(pen, isNotEmpty);
    expect(pen.map((t) => t.color).toSet(), {0xFF000000});
    for (var y = 140; y <= 143; y++) {
      c.line(100, y, 200, y, (40, 70, 30)); // a label to keep
    }
    final left = inkLeftover(c.rgba, c.w, c.h, const []);
    expect(left, isNotNull);
    final (_, x0, _, _, _) = left!;
    expect(x0, greaterThan(40)); // the table strip went
  });
}
