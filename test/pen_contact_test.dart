import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/presentation/pen_contact.dart';

/// Raw stylus packets as an embedder sends them, through Flutter's own
/// converter, so the test sees the `buttons` the canvas really gets.
List<PointerEvent> _deliver(
  List<(ui.PointerChange, int)> packets, {
  ui.PointerDeviceKind kind = ui.PointerDeviceKind.stylus,
}) => PointerEventConverter.expand([
  for (final (change, buttons) in packets)
    ui.PointerData(
      change: change,
      kind: kind,
      buttons: buttons,
      physicalX: 100,
      physicalY: 100,
    ),
], (_) => 1.0).toList();

void main() {
  group('Android (#18)', () {
    // AndroidTouchProcessor: buttons = getButtonState() >> 4, so the S Pen
    // button (BUTTON_STYLUS_PRIMARY 0x20) arrives as 0x02 on every contact
    // packet while it is held.
    final events = _deliver([
      (ui.PointerChange.add, 0),
      (ui.PointerChange.hover, kPrimaryStylusButton),
      (ui.PointerChange.down, kPrimaryStylusButton),
      (ui.PointerChange.move, kPrimaryStylusButton),
      (ui.PointerChange.up, 0),
    ]);
    final contact = events.where(
      (e) => e is PointerDownEvent || e is PointerMoveEvent,
    );

    test('Flutter leaves the contact bit out while the button is held', () {
      expect(contact, hasLength(2));
      for (final e in contact) {
        expect(e.buttons, kPrimaryStylusButton);
      }
    });

    test('the contact bit alone reads them as hovering (0.37.9 bug)', () {
      for (final e in contact) {
        expect(penTipTouches(e.buttons, downMayPrecedeContact: true), isFalse);
      }
    });

    test('down and move count as touching', () {
      for (final e in contact) {
        expect(penTipTouches(e.buttons, downMayPrecedeContact: false), isTrue);
      }
    });
  });

  group('GTK / browser', () {
    // A side button pressed while hovering arrives as the pointer-down with
    // only the side bit; the tip landing later sets the contact bit.
    final events = _deliver([
      (ui.PointerChange.add, 0),
      (ui.PointerChange.down, kSecondaryStylusButton),
      (ui.PointerChange.move, kSecondaryStylusButton),
      (ui.PointerChange.move, kSecondaryStylusButton | kPrimaryButton),
      (ui.PointerChange.move, kSecondaryStylusButton),
      (ui.PointerChange.up, 0),
    ]);
    final touches = [
      for (final e in events)
        if (e is PointerDownEvent || e is PointerMoveEvent)
          penTipTouches(e.buttons, downMayPrecedeContact: true),
    ];

    test('only the packet with the contact bit touches', () {
      expect(touches, [false, false, true, false]);
    });
  });

  test('web pen eraser makes contact with button bit 5 alone', () {
    const eraser = 0x20;
    final events = _deliver([
      (ui.PointerChange.add, 0),
      (ui.PointerChange.down, eraser),
      (ui.PointerChange.move, eraser),
      (ui.PointerChange.up, 0),
    ]);
    final gesture = events.where(
      (e) =>
          e is PointerDownEvent || e is PointerMoveEvent || e is PointerUpEvent,
    );
    expect(gesture.map((e) => isPenEraser(e, web: true)), [true, true, false]);
    expect(
      gesture.map(
        (e) => penTipTouches(e.buttons, downMayPrecedeContact: true, web: true),
      ),
      [true, true, false],
    );
    expect(isPenEraser(gesture.first, web: false), isFalse);
    expect(
      isPenEraser(
        const PointerDownEvent(kind: PointerDeviceKind.mouse, buttons: eraser),
        web: true,
      ),
      isFalse,
    );
  });

  test('native inverted stylus still activates the eraser', () {
    final down = _deliver(
      [(ui.PointerChange.add, 0), (ui.PointerChange.down, 0)],
      kind: ui.PointerDeviceKind.invertedStylus,
    ).whereType<PointerDownEvent>().single;
    expect(isPenEraser(down, web: false), isTrue);
  });

  test('plain pen contact touches everywhere', () {
    final down = _deliver([
      (ui.PointerChange.add, 0),
      (ui.PointerChange.down, 0),
    ]).whereType<PointerDownEvent>().single;
    expect(penTipTouches(down.buttons, downMayPrecedeContact: true), isTrue);
    expect(penTipTouches(down.buttons, downMayPrecedeContact: false), isTrue);
  });
}
