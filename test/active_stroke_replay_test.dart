// iPadOS Safari replays pen samples it already delivered (older timestamps)
// inside later events. Taken as new points they zigzagged the live ink.

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/presentation/canvas_painter_notifiers.dart';

Duration _ms(int ms) => Duration(milliseconds: ms);

void main() {
  test('replayed or out-of-order samples are ignored', () {
    final n = ActiveStrokeNotifier()
      ..start(const Offset(0, 0), 0.5, eventTime: _ms(0));
    // Real sequence from the device log: 783 788 796 800, then 788 796 800
    // again with slightly different positions.
    n.addPoint(const Offset(10, 0), 0.5, eventTime: _ms(783));
    n.addPoint(const Offset(12, 0), 0.5, eventTime: _ms(788));
    n.addPoint(const Offset(14, 0), 0.5, eventTime: _ms(796));
    n.addPoint(const Offset(16, 0), 0.5, eventTime: _ms(800));
    final before = n.points.length;
    n.addPoint(const Offset(13, 1), 0.5, eventTime: _ms(788));
    n.addPoint(const Offset(15, 1), 0.5, eventTime: _ms(796));
    n.addPoint(const Offset(16, 1), 0.5, eventTime: _ms(800));
    expect(n.points.length, before);
    n.addPoint(const Offset(18, 0), 0.5, eventTime: _ms(805));
    expect(n.points.length, before + 1);
    final xs = n.points.map((p) => p.x).toList();
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], greaterThanOrEqualTo(xs[i - 1]));
    }
  });

  test('without event times every sample is taken (native input)', () {
    final n = ActiveStrokeNotifier()..start(const Offset(0, 0), 0.5);
    n.addPoint(const Offset(10, 0), 0.5);
    n.addPoint(const Offset(5, 0), 0.5);
    expect(n.points.length, 3);
  });

  test('a new stroke starts a fresh clock', () {
    final n = ActiveStrokeNotifier()
      ..start(const Offset(0, 0), 0.5, eventTime: _ms(1000));
    n.addPoint(const Offset(10, 0), 0.5, eventTime: _ms(1010));
    n.start(const Offset(50, 0), 0.5, eventTime: _ms(500));
    n.addPoint(const Offset(60, 0), 0.5, eventTime: _ms(510));
    expect(n.points.length, 2);
  });

  test('the live preview is smoothed like the committed stroke', () {
    final n = ActiveStrokeNotifier()
      ..start(const Offset(0, 0), 0.5,
          pageUnitsPerPx: 0.8, integerCoords: true, eventTime: _ms(0));
    // Integer-pixel staircase along a diagonal, as Safari delivers it.
    for (var i = 1; i <= 300; i++) {
      n.addPoint(Offset(i * 2.0, (i * 1.3 + (i % 7 == 0 ? 1 : 0)).roundToDouble()),
          0.5, eventTime: _ms(i * 8));
      n.displayPoints; // a frame after every sample, like the painter
    }
    final live = n.displayPoints;
    final committed = n.snapshotForCommit();
    expect(live.length, committed.length);
    for (var i = 0; i < live.length; i++) {
      expect(live[i].x, closeTo(committed[i].x, 1e-9));
      expect(live[i].y, closeTo(committed[i].y, 1e-9));
    }
    // And a new stroke never shows the previous one's cached preview.
    n.start(const Offset(500, 500), 0.5,
        pageUnitsPerPx: 0.8, integerCoords: true, eventTime: _ms(1000));
    for (var i = 1; i <= 40; i++) {
      n.addPoint(Offset(500 + i * 2.0, 500), 0.5, eventTime: _ms(1000 + i * 8));
    }
    expect(n.displayPoints.first.x, 500);
  });
}
