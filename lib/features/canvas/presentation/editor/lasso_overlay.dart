// Handles of a lasso selection: four corner resize handles and the rotate
// handle, following the live transform of a gesture in progress.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/canvas_painter_notifiers.dart';
import 'package:abelnotes/features/canvas/presentation/editor/page_view_transform.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

class LassoOverlay extends ConsumerStatefulWidget {
  const LassoOverlay({
    super.key,
    required this.fallback,
    required this.canvasSize,
    required this.transform,
    required this.canvasStackKey,
    required this.onCommit,
    required this.actionBar,
  });

  /// State to draw from before the provider has one.
  final CanvasState fallback;
  final Size canvasSize;
  final LassoTransformNotifier transform;
  /// Key of the canvas stack, to turn the handles' screen points to global.
  final GlobalKey canvasStackKey;
  /// Ends a gesture: the live transform goes back to the provider once.
  final VoidCallback onCommit;
  /// The floating actions, drawn over the handles while a selection exists.
  final Widget Function(CanvasState state) actionBar;

  @override
  ConsumerState<LassoOverlay> createState() => _LassoOverlayState();
}

class _LassoOverlayState extends ConsumerState<LassoOverlay> {
  // Resize drag tracking.
  Offset _resizeDragStart = Offset.zero;
  double _resizeInitialScale = 1.0;

  @override
  Widget build(BuildContext context) {
    // pages: so a lasso commit (move/scale/rotate) refreshes the state the
    // handles anchor to; zoom and pan re-project them.
    ref.watch(canvasProvider.select((s) => (
          zoom: s?.zoom ?? 1.0,
          panOffset: s?.panOffset ?? Offset.zero,
          pages: s?.pages,
          page: s?.currentPageIndex,
          lassoSelection: s?.lassoSelection,
          selectedElementId: s?.selectedElementId,
          hasClipboard: s?.clipboard != null,
        )));
    final live = ref.read(canvasProvider) ?? widget.fallback;
    return ListenableBuilder(
      listenable: widget.transform,
      builder: (_, __) => Stack(
        children: [
          ..._handles(live, widget.canvasSize),
          if (live.lassoSelection != null) widget.actionBar(live),
        ],
      ),
    );
  }

  List<Widget> _handles(CanvasState state, Size canvasSize) {
    final originalSel = state.lassoSelection;
    if (originalSel == null) return [];
    final p = HwThemeScope.of(context);
    final view = PageViewTransform.of(state, canvasSize);

    // During drag/rotate/scale the local LassoTransformNotifier holds the
    // live values. Riverpod state stays at the *initial* transform until
    // pointer-up, so reading sel.dragOffset/scale/rotation directly here
    // would freeze the handles in place while the canvas content moved
    // underneath — the visible "lag". Override with the live values.
    final sel = widget.transform.isActive
        ? originalSel.copyWith(
            dragOffset: widget.transform.dragOffset,
            rotation: widget.transform.rotation,
            scale: widget.transform.scale,
          )
        : originalSel;

    final center = sel.bounds.center;
    final scaledBounds = Rect.fromCenter(
      center: center,
      width: sel.bounds.width * sel.scale,
      height: sel.bounds.height * sel.scale,
    ).translate(sel.dragOffset.dx, sel.dragOffset.dy);

    final screenTL = view.toScreen(scaledBounds.topLeft);
    final screenBR = view.toScreen(scaledBounds.bottomRight);
    final screenRect = Rect.fromPoints(screenTL, screenBR);
    final selRotation = sel.rotation;

    Offset rotateScreenPoint(Offset point) {
      if (selRotation == 0.0) return point;
      final dx = point.dx - screenRect.center.dx;
      final dy = point.dy - screenRect.center.dy;
      final cosA = cos(selRotation);
      final sinA = sin(selRotation);
      return Offset(
        screenRect.center.dx + dx * cosA - dy * sinA,
        screenRect.center.dy + dx * sinA + dy * cosA,
      );
    }

    final unrotatedCenterTop = Offset(screenRect.center.dx, screenRect.top - 40);
    final centerTop = rotateScreenPoint(unrotatedCenterTop);

    Widget buildCornerHandle(Offset unrotatedPos, MouseCursor cursor) {
      final screenPos = rotateScreenPoint(unrotatedPos);
      return Positioned(
        left: screenPos.dx - 7,
        top: screenPos.dy - 7,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            onPanStart: (d) {
              _resizeDragStart = d.globalPosition;
              _resizeInitialScale = sel.scale;
              widget.transform.begin(
                dragOffset: sel.dragOffset,
                rotation: sel.rotation,
                scale: sel.scale,
              );
            },
            onPanUpdate: (d) {
              // Convert screenRect.center to global coordinates via the canvas Stack
              final stackBox = widget.canvasStackKey.currentContext?.findRenderObject() as RenderBox?;
              final centerGlobal = stackBox != null
                  ? stackBox.localToGlobal(screenRect.center)
                  : screenRect.center;
              final startDist = (_resizeDragStart - centerGlobal).distance;
              final currentDist = (d.globalPosition - centerGlobal).distance;
              if (startDist > 5) {
                final newScale = _resizeInitialScale * (currentDist / startDist);
                widget.transform.setScale(newScale.clamp(0.1, 10.0));
              }
            },
            onPanEnd: (_) => widget.onCommit(),
            onPanCancel: widget.onCommit,
            child: Container(
              width: 14, height: 14,
              decoration: BoxDecoration(
                color: p.paper0,
                shape: BoxShape.circle,
                border: Border.all(color: p.accent, width: 1.5),
                boxShadow: hwShadow2(p.brightness),
              ),
            ),
          ),
        ),
      );
    }

    return [
      // Corner resize handles
      buildCornerHandle(screenRect.topLeft, SystemMouseCursors.resizeUpLeft),
      buildCornerHandle(screenRect.topRight, SystemMouseCursors.resizeUpRight),
      buildCornerHandle(screenRect.bottomLeft, SystemMouseCursors.resizeDownLeft),
      buildCornerHandle(screenRect.bottomRight, SystemMouseCursors.resizeDownRight),

      // Rotation handle
      Positioned(
        left: centerTop.dx - 14,
        top: centerTop.dy - 14,
        child: Transform.rotate(
          angle: selRotation,
          origin: const Offset(0, -13), // Shift origin from the center of the 54px col (y=27) pointing to circle (y=14)
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onPanStart: (_) {
                  widget.transform.begin(
                    dragOffset: sel.dragOffset,
                    rotation: sel.rotation,
                    scale: sel.scale,
                  );
                },
                onPanUpdate: (d) {
                  // Use the canvas Stack's RenderBox for proper coordinate conversion
                  final stackBox = widget.canvasStackKey.currentContext?.findRenderObject() as RenderBox?;
                  final centerGlobal = stackBox != null
                      ? stackBox.localToGlobal(screenRect.center)
                      : screenRect.center;
                  final prev = d.globalPosition - d.delta;
                  final startAngle = atan2(prev.dy - centerGlobal.dy, prev.dx - centerGlobal.dx);
                  final currentAngle = atan2(d.globalPosition.dy - centerGlobal.dy, d.globalPosition.dx - centerGlobal.dx);
                  var deltaAngle = currentAngle - startAngle;
                  if (deltaAngle > pi) deltaAngle -= 2 * pi;
                  if (deltaAngle < -pi) deltaAngle += 2 * pi;
                  widget.transform.rotateBy(deltaAngle);
                },
                onPanEnd: (_) => widget.onCommit(),
                onPanCancel: widget.onCommit,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: p.paper0, shape: BoxShape.circle,
                    border: Border.all(color: p.accent, width: 2),
                    boxShadow: hwShadow2(p.brightness),
                  ),
                  child: Icon(Icons.rotate_right_rounded, size: 16, color: p.accent),
                ),
              ),
              IgnorePointer(
                child: Container(width: 1.5, height: 26, color: p.accent.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
      ),
    ];
  }
}
