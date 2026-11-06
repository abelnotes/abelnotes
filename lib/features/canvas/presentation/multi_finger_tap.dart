import 'package:flutter/gestures.dart';

/// Two- and three-finger taps on the canvas (undo / redo).
///
/// Read from the raw pointer stream the canvas Listener already sees, not
/// through the gesture arena: a tap recognizer there would compete with the
/// pinch-to-zoom ScaleGestureRecognizer for the same fingers. Watching from
/// the side, pinch keeps every gesture, and one that never moved and lifted
/// quickly also counts as a tap.
///
/// A tap is 2 or 3 touch pointers that all land within [maxSpread] of the
/// first, none moving more than [slop], the last lifting within
/// [maxDuration] of the first landing. A pen or mouse contact, a fourth
/// finger, a cancel or [spoil] in between rules the gesture out, and so does
/// any pen activity (touching, moving or hovering) within [penQuiet] before
/// the first finger lands: fingers then are a palm, not a tap.
class MultiFingerTapDetector {
  MultiFingerTapDetector({required this.onTap});

  final void Function(int fingers) onTap;

  static const Duration maxDuration = Duration(milliseconds: 350);
  static const Duration maxSpread = Duration(milliseconds: 150);
  static const double slop = 20;
  static const Duration penQuiet = Duration(milliseconds: 800);

  final Map<int, Offset> _downAt = {};
  Duration? _start;
  int _fingers = 0;
  bool _spoiled = false;
  Duration? _lastPen;

  static bool _isPen(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus ||
      e.kind == PointerDeviceKind.invertedStylus;

  void _pen(PointerEvent e) {
    _lastPen = e.timeStamp;
    spoil();
  }

  void down(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) {
      _isPen(e) ? _pen(e) : spoil();
      return;
    }
    if (_downAt.isEmpty) {
      _start = e.timeStamp;
      _fingers = 0;
      _spoiled = _lastPen != null && e.timeStamp - _lastPen! < penQuiet;
    } else if (e.timeStamp - _start! > maxSpread) {
      _spoiled = true;
    }
    _downAt[e.pointer] = e.position;
    if (++_fingers > 3) _spoiled = true;
  }

  void move(PointerMoveEvent e) {
    if (_isPen(e)) return _pen(e);
    final from = _downAt[e.pointer];
    if (from != null && (e.position - from).distance > slop) _spoiled = true;
  }

  /// A pen in range but not touching (S Pen, Apple Pencil hover) means the
  /// hand resting on the glass is a palm.
  void hover(PointerHoverEvent e) {
    if (_isPen(e)) _pen(e);
  }

  void up(PointerUpEvent e) {
    if (_isPen(e)) return _pen(e);
    if (_downAt.remove(e.pointer) == null || _downAt.isNotEmpty) return;
    final tap = !_spoiled &&
        _fingers >= 2 &&
        e.timeStamp - _start! <= maxDuration;
    _start = null;
    if (tap) onTap(_fingers);
  }

  void cancel(PointerCancelEvent e) {
    if (_downAt.remove(e.pointer) == null) return;
    _spoiled = true;
    if (_downAt.isEmpty) _start = null;
  }

  /// Rules out the gesture in progress, if any (pen on the glass, palm).
  void spoil() {
    if (_start != null) _spoiled = true;
  }
}
