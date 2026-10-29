import 'package:flutter/gestures.dart';

/// Whether a pen down/move means the tip touches the surface.
///
/// GTK and browsers report a side-button press made while hovering as a
/// pointer-down, so there only the contact bit tells. Android sends downs
/// and moves only on contact, but Flutter drops the bit while a side button
/// is held.
bool penTipTouches(int buttons, {required bool downMayPrecedeContact}) =>
    !downMayPrecedeContact || (buttons & kPrimaryButton) != 0;
