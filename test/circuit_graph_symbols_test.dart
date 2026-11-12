// Rewrite rules on synthetic ink: controlled sources drawn side by side,
// supply arrows and triangle grounds the detector misses.
import 'dart:math';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_graph.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// A polyline through [corners], a point every 2 px like a pen sample.
List<Pt> _ink(List<(double, double)> corners) {
  final out = [Pt(corners.first.$1, corners.first.$2)];
  for (var i = 1; i < corners.length; i++) {
    final a = Pt(corners[i - 1].$1, corners[i - 1].$2), b = Pt(corners[i].$1, corners[i].$2);
    final n = ((b - a).len / 2).ceil();
    for (var k = 1; k <= n; k++) {
      out.add(a + (b - a) * (k / n));
    }
  }
  return out;
}

bool _isOutline(List<Pt> p) => p.length == 5 && (p.first - p.last).len < 0.01;

void main() {
  group('controlled source', () {
    List<List<Pt>> source(List<List<Pt>> outline) => [
          ...outline,
          _ink([(125, 110), (125, 140)]),
          _ink([(120, 133), (125, 140), (130, 133)]),
          _ink([(125, 40), (125, 100)]),
          _ink([(125, 150), (125, 210)]),
        ];
    final det = [Detection('current_source', 0.9, 100, 100, 150, 150)];

    test('a diamond drawn one side per stroke stays a diamond', () {
      final out = rewriteCircuit(
          source([
            _ink([(125, 100), (100, 125)]),
            _ink([(125, 100), (150, 125)]),
            _ink([(100, 125), (125, 150)]),
            _ink([(150, 125), (125, 150)]),
          ]),
          det);
      expect(out.added.any((o) => _isOutline(o.points)), isTrue);
    });

    test('a ring stays a ring', () {
      final ring = _ink([
        for (var k = 0; k <= 32; k++) (125 + 25 * cos(k * pi / 16), 125 + 25 * sin(k * pi / 16)),
      ]);
      final out = rewriteCircuit(source([ring]), det);
      expect(out.added.any((o) => _isOutline(o.points)), isFalse);
    });
  });

  group('supply arrow and triangle ground', () {
    final resistor = Detection('resistor', 0.9, 100, 100, 130, 160);
    List<List<Pt>> drawn(List<List<Pt>> head) => [
          _ink([(115, 100), (105, 110), (125, 120), (105, 130), (125, 140), (105, 150), (115, 160)]),
          _ink([(115, 40), (115, 100)]),
          _ink([(115, 160), (115, 230)]),
          ...head,
        ];

    test('a closed triangle down at a free wire end becomes a signal ground', () {
      final out = rewriteCircuit(
          drawn([_ink([(108, 230), (122, 230)]), _ink([(108, 230), (115, 242), (122, 230)])]), [resistor]);
      expect(out.components.map((d) => d.cls), contains('gnd'));
      final triangle = out.added.where((o) => o.points.length == 4 && (o.points.first - o.points.last).len < 0.01);
      expect(triangle, hasLength(1));
      expect(triangle.single.points[2].y, greaterThan(triangle.single.points[0].y));
    });

    test('an open head down at a free wire end is a ground too', () {
      final out = rewriteCircuit(drawn([_ink([(108, 222), (115, 232), (122, 222)])]), [resistor]);
      final triangle = out.added.where((o) => o.points.length == 4 && (o.points.first - o.points.last).len < 0.01);
      expect(triangle, hasLength(1));
    });

    test('a head on a stroke touching nothing (writing) is left alone', () {
      final out = rewriteCircuit([
        ...drawn(const []),
        _ink([(200, 100), (200, 115)]),
        _ink([(194, 104), (200, 98), (206, 104)]),
      ], [resistor]);
      expect(out.components.map((d) => d.cls), isNot(contains('gnd')));
    });

    test('a triangle up on a wire from below becomes a vcc arrow', () {
      final out = rewriteCircuit([
        _ink([(115, 100), (105, 110), (125, 120), (105, 130), (125, 140), (105, 150), (115, 160)]),
        _ink([(115, 40), (115, 100)]),
        _ink([(108, 40), (122, 40)]),
        _ink([(108, 40), (115, 28), (122, 40)]),
        _ink([(115, 160), (115, 230)]),
      ], [resistor]);
      final head = out.added.where((o) =>
          o.points.length == 3 && o.points[1].y < o.points[0].y - 1 && (o.points[0].y - o.points[2].y).abs() < 1);
      expect(head, hasLength(1));
      expect(head.single.points[1].y, closeTo(28, 2));
    });

    test('ground bars are not read as an arrow', () {
      final out = rewriteCircuit(
          drawn([
            _ink([(108, 230), (122, 230)]),
            _ink([(110, 234), (120, 234)]),
            _ink([(113, 238), (117, 238)]),
          ]),
          [resistor]);
      expect(out.components.map((d) => d.cls), isNot(contains('gnd')));
    });
  });
}
