import 'package:abelnotes/features/canvas/presentation/multi_finger_tap.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<int> taps;
  late MultiFingerTapDetector d;

  setUp(() {
    taps = [];
    d = MultiFingerTapDetector(onTap: taps.add);
  });

  Duration ms(int v) => Duration(milliseconds: v);

  void down(int p, int t,
          {Offset at = Offset.zero,
          PointerDeviceKind kind = PointerDeviceKind.touch}) =>
      d.down(PointerDownEvent(
          pointer: p, timeStamp: ms(t), position: at, kind: kind));
  void move(int p, int t, Offset at) =>
      d.move(PointerMoveEvent(pointer: p, timeStamp: ms(t), position: at));
  void up(int p, int t, {Offset at = Offset.zero}) =>
      d.up(PointerUpEvent(pointer: p, timeStamp: ms(t), position: at));

  test('two fingers tapping count as a two-finger tap', () {
    down(1, 0);
    down(2, 30, at: const Offset(80, 0));
    up(1, 120);
    up(2, 140, at: const Offset(80, 0));
    expect(taps, [2]);
  });

  test('three fingers tapping count as a three-finger tap', () {
    down(1, 0);
    down(2, 20);
    down(3, 40);
    up(2, 150);
    up(1, 160);
    up(3, 170);
    expect(taps, [3]);
  });

  test('one finger is not a tap here', () {
    down(1, 0);
    up(1, 80);
    expect(taps, isEmpty);
  });

  test('a pinch (fingers moving) is not a tap', () {
    down(1, 0);
    down(2, 10, at: const Offset(100, 0));
    move(2, 60, const Offset(160, 0));
    up(1, 150);
    up(2, 160, at: const Offset(160, 0));
    expect(taps, isEmpty);
  });

  test('a small wobble still counts', () {
    down(1, 0);
    down(2, 10);
    move(1, 50, const Offset(6, 4));
    up(1, 120);
    up(2, 130);
    expect(taps, [2]);
  });

  test('fingers held too long are not a tap', () {
    down(1, 0);
    down(2, 10);
    up(1, 500);
    up(2, 510);
    expect(taps, isEmpty);
  });

  test('a second finger landing late is not a tap', () {
    down(1, 0);
    down(2, 300);
    up(1, 320);
    up(2, 330);
    expect(taps, isEmpty);
  });

  test('four fingers are not a tap', () {
    for (var p = 1; p <= 4; p++) {
      down(p, p * 10);
    }
    for (var p = 1; p <= 4; p++) {
      up(p, 100 + p);
    }
    expect(taps, isEmpty);
  });

  test('a pen landing mid-gesture rules it out', () {
    down(1, 0);
    down(2, 10);
    down(9, 40, kind: PointerDeviceKind.stylus);
    up(1, 100);
    up(2, 110);
    expect(taps, isEmpty);
  });

  test('a cancelled finger rules it out', () {
    down(1, 0);
    down(2, 10);
    d.cancel(PointerCancelEvent(pointer: 1, timeStamp: ms(50)));
    up(2, 100);
    expect(taps, isEmpty);
  });

  test('spoil() rules out the gesture in progress only', () {
    down(1, 0);
    down(2, 10);
    d.spoil();
    up(1, 100);
    up(2, 110);
    down(3, 1000);
    down(4, 1010);
    up(3, 1100);
    up(4, 1110);
    expect(taps, [2]);
  });
}
