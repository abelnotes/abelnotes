// Tells a trackpad swipe from a mouse wheel notch on the web, where the engine
// can't always (Firefox reports every wheel event as a mouse).

import 'package:flutter/gestures.dart';

/// True when a scroll event is a trackpad swipe (pan), false for a wheel
/// notch (zoom). [web] enables the delta heuristics; elsewhere the event kind
/// is trusted.
class WheelKindClassifier {
  WheelKindClassifier({required this.web});

  final bool web;
  Duration? _lastAt;
  bool _lastTrackpad = false;

  // Closer events belong to the same gesture, momentum included.
  static const _gesture = Duration(milliseconds: 150);

  bool isTrackpad(PointerScrollEvent e, {double devicePixelRatio = 1}) {
    final gap = _lastAt == null ? null : e.timeStamp - _lastAt!;
    final sameGesture = gap != null && gap >= Duration.zero && gap < _gesture;
    final trackpad = e.kind == PointerDeviceKind.trackpad ||
        (web &&
            ((sameGesture && _lastTrackpad) ||
                looksLikeSwipe(e.scrollDelta, devicePixelRatio)));
    _lastAt = e.timeStamp;
    _lastTrackpad = trackpad;
    return trackpad;
  }

  /// A wheel notch scrolls one axis by whole lines: the engine counts a line
  /// as 4 device px (3 per notch in Firefox, 100 or 120 px in Chrome). A swipe
  /// moves sideways too, or by fractional or odd amounts.
  static bool looksLikeSwipe(Offset logical, double devicePixelRatio) {
    if (logical.dx != 0) return true;
    final v = (logical.dy * devicePixelRatio).abs();
    if (v == 0) return false;
    final whole = v.roundToDouble();
    return (v - whole).abs() > 0.01 || whole % 4 != 0;
  }
}
