// Layout delegate that places a panel next to a point inside an area.

import 'dart:math';
import 'package:flutter/material.dart';

/// Puts the tool panel just below [point], or above it when there is no
/// room, kept inside the canvas.
class NearPointLayout extends SingleChildLayoutDelegate {
  const NearPointLayout(this.point, this.area);

  final Offset point;

  /// The canvas, so the panel never covers the top bar.
  final Rect area;

  /// Clear of the Pencil's tip, so the panel doesn't sit under the hand.
  static const double _gap = 24;
  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final room = area.intersect(Offset.zero & constraints.biggest);
    return BoxConstraints.loose(Size(
      max(0, room.width - 2 * _margin),
      max(0, room.height - 2 * _margin),
    ));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final box = area.intersect(Offset.zero & size).deflate(_margin);
    final below = point.dy + _gap;
    final y = below + childSize.height <= box.bottom
        ? below
        : point.dy - _gap - childSize.height;
    final x = point.dx - childSize.width / 2;
    return Offset(
      x.clamp(box.left, max(box.left, box.right - childSize.width)),
      y.clamp(box.top, max(box.top, box.bottom - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(NearPointLayout oldDelegate) =>
      oldDelegate.point != point || oldDelegate.area != area;
}
