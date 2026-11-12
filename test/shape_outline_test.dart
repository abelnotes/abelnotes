// Shape outlines as traced for circuit recognition.
import 'dart:math';

import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a circle traces its ring, closed', () {
    final pts = shapeOutline(const ShapeData(shapeType: 'circle', x1: 0, y1: 0, x2: 20, y2: 20))!;
    expect(pts.length, greaterThan(30));
    for (final p in pts) {
      expect((p - const Offset(10, 10)).distance, closeTo(10, 1e-9));
    }
    expect((pts.first - pts.last).distance, lessThan(1e-9));
  });

  test('rotation turns the outline about its centre', () {
    final pts = shapeOutline(const ShapeData(shapeType: 'rectangle', x1: 0, y1: 0, x2: 20, y2: 10, rotation: pi / 2))!;
    // A 20 x 10 box turned a quarter is 10 wide and 20 tall, same centre.
    final xs = pts.map((p) => p.dx), ys = pts.map((p) => p.dy);
    expect(xs.reduce(max) - xs.reduce(min), closeTo(10, 1e-9));
    expect(ys.reduce(max) - ys.reduce(min), closeTo(20, 1e-9));
    expect((xs.reduce(max) + xs.reduce(min)) / 2, closeTo(10, 1e-9));
  });

  test('an oblique triangle uses its stored vertices', () {
    final pts = shapeOutline(const ShapeData(
      shapeType: 'triangle', x1: 0, y1: 0, x2: 10, y2: 10, vertices: [1, 2, 3, 4, 5, 6],
    ))!;
    expect(pts, const [Offset(1, 2), Offset(3, 4), Offset(5, 6), Offset(1, 2)]);
  });

  test('a quarter-turned triangle stays inside its box, as the painter draws it', () {
    // Cardinal rotations point the apex inside the box instead of turning it.
    final pts = shapeOutline(const ShapeData(shapeType: 'triangle', x1: 0, y1: 0, x2: 20, y2: 10, rotation: pi / 2))!;
    expect(pts.first, const Offset(20, 5));
    for (final p in pts) {
      expect(p.dx, inInclusiveRange(0, 20));
      expect(p.dy, inInclusiveRange(0, 10));
    }
  });

  test('arrows have no outline to trace', () {
    expect(shapeOutline(const ShapeData(shapeType: 'arrow', x1: 0, y1: 0, x2: 10, y2: 0)), isNull);
  });
}
