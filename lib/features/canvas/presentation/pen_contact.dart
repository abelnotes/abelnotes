import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

// Pointer Events uses bit 5 for a pen's eraser end. Flutter Web forwards
// the bit but reports both ends of the pen as PointerDeviceKind.stylus.
const _webPenEraserButton = 0x20;

bool isPenEraser(PointerEvent event, {bool web = kIsWeb}) =>
    event.kind == PointerDeviceKind.invertedStylus ||
    (web &&
        event.kind == PointerDeviceKind.stylus &&
        (event.buttons & _webPenEraserButton) != 0);

/// Whether a pen down/move means the tip touches the surface.
///
/// GTK and browsers report a side-button press made while hovering as a
/// pointer-down. A web eraser makes contact with bit 5 instead of bit 0.
/// Android sends downs and moves only on contact, but Flutter drops the
/// tip bit while a side button is held.
bool penTipTouches(
  int buttons, {
  required bool downMayPrecedeContact,
  bool web = kIsWeb,
}) =>
    !downMayPrecedeContact ||
    (buttons & (kPrimaryButton | (web ? _webPenEraserButton : 0))) != 0;
