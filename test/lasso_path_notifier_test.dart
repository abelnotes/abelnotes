import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/presentation/canvas_painter_notifiers.dart';

void main() {
  test('samples closer than the step are dropped, the rest kept in order', () {
    final n = LassoPathNotifier()..start(Offset.zero, minStep: 3);
    for (final p in const [Offset(1, 1), Offset(2, 0), Offset(3, 0), Offset(4, 1), Offset(7, 1)]) {
      n.addPoint(p);
    }
    expect(n.points, const [Offset.zero, Offset(3, 0), Offset(7, 1)]);
  });

  test('without a step every sample is kept, and a new lasso forgets the old step', () {
    final n = LassoPathNotifier()..start(Offset.zero, minStep: 3);
    n.start(Offset.zero);
    n.addPoint(const Offset(0.5, 0));
    expect(n.points.length, 2);
  });
}
