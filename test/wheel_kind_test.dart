import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/presentation/editor/wheel_kind.dart';

PointerScrollEvent _scroll(int ms, Offset delta,
        {PointerDeviceKind kind = PointerDeviceKind.mouse}) =>
    PointerScrollEvent(
        timeStamp: Duration(milliseconds: ms), kind: kind, scrollDelta: delta);

void main() {
  test('engine-tagged trackpad pans everywhere', () {
    for (final web in [true, false]) {
      final c = WheelKindClassifier(web: web);
      expect(
          c.isTrackpad(_scroll(0, const Offset(0, 120),
              kind: PointerDeviceKind.trackpad)),
          isTrue);
    }
  });

  test('native mouse scroll stays a wheel whatever the delta', () {
    final c = WheelKindClassifier(web: false);
    expect(c.isTrackpad(_scroll(0, const Offset(3.5, 2.25))), isFalse);
  });

  test('web: Firefox wheel notches (3 lines of 4 px) are a wheel', () {
    final c = WheelKindClassifier(web: true);
    expect(c.isTrackpad(_scroll(0, const Offset(0, 12))), isFalse);
    expect(c.isTrackpad(_scroll(400, const Offset(0, -36))), isFalse);
    // 125 % scaling: 48 device px arrive as 38.4 logical px.
    expect(
        c.isTrackpad(_scroll(500, const Offset(0, 38.4)),
            devicePixelRatio: 1.25),
        isFalse);
    // Chrome on Windows: 100 px per notch.
    expect(c.isTrackpad(_scroll(1200, const Offset(0, 100))), isFalse);
  });

  test('web: a swipe reported as mouse pans, momentum included', () {
    final c = WheelKindClassifier(web: true);
    expect(c.isTrackpad(_scroll(0, const Offset(0, 3))), isTrue);
    expect(c.isTrackpad(_scroll(16, const Offset(0.5, 12.75))), isTrue);
    // Same gesture: whole, larger deltas keep panning.
    expect(c.isTrackpad(_scroll(32, const Offset(0, 48))), isTrue);
    expect(c.isTrackpad(_scroll(48, const Offset(0, 24))), isTrue);
    // A wheel notch well after the swipe ended zooms again.
    expect(c.isTrackpad(_scroll(1000, const Offset(0, 48))), isFalse);
  });

  test('web: sideways scrolling pans', () {
    final c = WheelKindClassifier(web: true);
    expect(c.isTrackpad(_scroll(0, const Offset(48, 0))), isTrue);
  });
}
