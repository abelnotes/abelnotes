import 'dart:math';
import 'package:flutter/material.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Overlay widget that shows move/resize/rotate/delete handles around a selected element.
class ImageHandleOverlay extends StatefulWidget {
  final Rect bounds;
  final double rotation;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Rect> onResize;
  final ValueChanged<double> onRotate;
  final VoidCallback onDelete;
  final VoidCallback onDeselect;
  final VoidCallback? onDragStart;
  /// Called once when any drag/rotate/resize gesture ends or is cancelled.
  /// Lets the host commit a locally-tracked transform back to Riverpod
  /// in a single state update instead of one per pointer-move event.
  final VoidCallback? onDragEnd;
  final VoidCallback? onCrop;
  final VoidCallback? onBringToFront;
  final VoidCallback? onSendToBack;
  final VoidCallback? onToggleLock;
  final VoidCallback? onEditComment;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onFlipHorizontal;
  /// Text only: decrease / increase the font size. Non-null marks the element
  /// as text, which shows the A−/A+ buttons in the action bar. Resizing the
  /// box never changes the font, so these are the only way to scale glyphs.
  final VoidCallback? onFontSmaller;
  final VoidCallback? onFontLarger;
  final bool isLocked;
  final bool hasComment;
  final bool isFlipped;
  /// Whether to show the top/bottom (height) edge handles. True everywhere now
  /// — text is a reflow frame whose height the user can extend past the content
  /// (the host clamps so a drag never clips the text).
  final bool showEdgeHeightHandles;

  const ImageHandleOverlay({
    super.key,
    required this.bounds,
    required this.rotation,
    required this.onMove,
    required this.onResize,
    required this.onRotate,
    required this.onDelete,
    required this.onDeselect,
    this.onDragStart,
    this.onDragEnd,
    this.onCrop,
    this.onBringToFront,
    this.onSendToBack,
    this.onToggleLock,
    this.onEditComment,
    this.onCopy,
    this.onCut,
    this.onFlipHorizontal,
    this.onFontSmaller,
    this.onFontLarger,
    this.isLocked = false,
    this.hasComment = false,
    this.isFlipped = false,
    this.showEdgeHeightHandles = true,
  });

  @override
  State<ImageHandleOverlay> createState() => _ImageHandleOverlayState();
}

class _ImageHandleOverlayState extends State<ImageHandleOverlay> {
  Offset _dragStart = Offset.zero;
  Offset _rotationCenter = Offset.zero;
  double _lastRotationAngle = 0;
  // Bounds captured at corner-resize gesture START. We use this as the
  // stable divisor in the projection math because widget.bounds is
  // LIVE — it's recomputed by the parent on every notifier tick. If the
  // parent rebuild lagged behind the gesture (one frame ≈ 16 ms but
  // pan events fire faster), per-tick math against widget.bounds would
  // see stale bounds and produce a frozen newBounds, never advancing
  // beyond the first tick. Using the immutable origBounds + the
  // CUMULATIVE pointer travel solves this regardless of rebuild rate.
  Rect? _resizeOrigBounds;
  Offset _resizeGestureOrigin = Offset.zero;

  static const _handleSize = 12.0;
  static const _rotateHandleDistance = 30.0;

  @override
  Widget build(BuildContext context) {
    final bounds = widget.bounds;
    if (bounds.width < 1 || bounds.height < 1) return const SizedBox.shrink();

    final p = HwThemeScope.of(context);

    return LayoutBuilder(builder: (context, constraints) {
      Widget handleStack = _buildHandleStack(bounds, p, constraints);

      // Apply rotation around the element center if rotated
      if (widget.rotation != 0) {
        handleStack = Transform.rotate(
          angle: widget.rotation,
          alignment: Alignment.topLeft,
          origin: bounds.center,
          child: handleStack,
        );
      }

      // Wrap in a non-rotated widget so _outerKey gives us global coords
      // unaffected by the internal Transform.rotate.
      return handleStack;
    });
  }

  Widget _buildHandleStack(Rect bounds, HwPalette p, BoxConstraints constraints) {
    // Float the action bar above the rotate handle, but clamp so it never
    // runs off the top edge (would be hidden) or off the right edge of the
    // overlay when the image is near a corner.
    final rawBarTop = bounds.top - _rotateHandleDistance - 24 - 38;
    final barTop = max(8.0, rawBarTop);
    final maxLeft = constraints.maxWidth.isFinite
        ? max(8.0, constraints.maxWidth - 8.0)
        : double.infinity;
    final barLeft = bounds.left.clamp(8.0, maxLeft);

    return Stack(
      children: [
        // Selection border (dashed)
        Positioned(
          left: bounds.left - 1,
          top: bounds.top - 1,
          width: bounds.width + 2,
          height: bounds.height + 2,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _DashedBorderPainter(p.accent),
            ),
          ),
        ),

        // Move handle (center) — drag anywhere inside to move
        Positioned(
          left: bounds.left,
          top: bounds.top,
          width: bounds.width,
          height: bounds.height,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: widget.isLocked ? null : (d) {
              _dragStart = d.globalPosition;
              widget.onDragStart?.call();
            },
            onPanUpdate: widget.isLocked ? null : (d) {
              final delta = d.globalPosition - _dragStart;
              _dragStart = d.globalPosition;
              widget.onMove(delta);
            },
            onPanEnd: widget.isLocked ? null : (_) => widget.onDragEnd?.call(),
            onPanCancel: widget.isLocked ? null : () => widget.onDragEnd?.call(),
          ),
        ),

        // Corner/edge/rotate handles (hidden when locked)
        if (!widget.isLocked) ...[
          // Corner resize handles (aspect-ratio preserving)
          _buildCornerHandle(bounds.topLeft, 'tl', p),
          _buildCornerHandle(bounds.topRight, 'tr', p),
          _buildCornerHandle(bounds.bottomLeft, 'bl', p),
          _buildCornerHandle(bounds.bottomRight, 'br', p),

          // Edge midpoint resize handles (free deform). Height handles are
          // hidden for auto-fit-height elements (text) — see [showEdgeHeightHandles].
          if (widget.showEdgeHeightHandles) ...[
            _buildEdgeHandle(Offset(bounds.center.dx, bounds.top), 'tm', p),
            _buildEdgeHandle(Offset(bounds.center.dx, bounds.bottom), 'bm', p),
          ],
          _buildEdgeHandle(Offset(bounds.left, bounds.center.dy), 'ml', p),
          _buildEdgeHandle(Offset(bounds.right, bounds.center.dy), 'mr', p),

          // Rotate handle (above top center)
          _buildRotateHandle(bounds, p),
        ],

        // Action buttons bar (above the rotate handle), clamped on-screen.
        Positioned(
          left: barLeft,
          top: barTop,
          child: _buildActionBar(),
        ),
      ],
    );
  }

  Widget _buildCornerHandle(Offset position, String handleId, HwPalette p) {
    return Positioned(
      left: position.dx - _handleSize / 2,
      top: position.dy - _handleSize / 2,
      child: GestureDetector(
        onPanStart: (d) {
          _dragStart = d.globalPosition;
          // Snapshot the bounds at gesture start; the resize math uses
          // the cumulative pointer travel against this snapshot, NOT
          // the live widget.bounds (which lags by one frame and would
          // freeze the scale at the first tick's value).
          _resizeOrigBounds = widget.bounds;
          _resizeGestureOrigin = d.globalPosition;
          widget.onDragStart?.call();
        },
        onPanUpdate: (d) {
          final cumulative = d.globalPosition - _resizeGestureOrigin;
          _handleCornerResize(handleId, cumulative);
        },
        onPanEnd: (_) {
          _resizeOrigBounds = null;
          widget.onDragEnd?.call();
        },
        onPanCancel: () {
          _resizeOrigBounds = null;
          widget.onDragEnd?.call();
        },
        child: Container(
          width: _handleSize,
          height: _handleSize,
          decoration: BoxDecoration(
            color: p.paper0,
            border: Border.all(color: p.accent, width: 2),
            borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: p.ink0.withValues(alpha: 0.15), blurRadius: 2)],
          ),
        ),
      ),
    );
  }

  Widget _buildEdgeHandle(Offset position, String handleId, HwPalette p) {
    final isHorizontal = handleId == 'tm' || handleId == 'bm';
    return Positioned(
      left: position.dx - (isHorizontal ? 10 : 4),
      top: position.dy - (isHorizontal ? 4 : 10),
      child: GestureDetector(
        onPanStart: (d) {
          // Same orig-snapshot pattern as corner resize: edge drags must
          // compute newBounds from cumulative pointer travel against an
          // IMMUTABLE origBounds, not against live widget.bounds.
          // widget.bounds is recomputed each frame from notifier values,
          // and at fast pan rates the parent rebuild lags pointer events
          // — per-tick math against the live rect freezes the dimension
          // at whatever the first tick produced.
          _resizeOrigBounds = widget.bounds;
          _resizeGestureOrigin = d.globalPosition;
          widget.onDragStart?.call();
        },
        onPanUpdate: (d) {
          final cumulative = d.globalPosition - _resizeGestureOrigin;
          _handleEdgeResize(handleId, cumulative);
        },
        onPanEnd: (_) {
          _resizeOrigBounds = null;
          widget.onDragEnd?.call();
        },
        onPanCancel: () {
          _resizeOrigBounds = null;
          widget.onDragEnd?.call();
        },
        child: Container(
          width: isHorizontal ? 20 : 8,
          height: isHorizontal ? 8 : 20,
          decoration: BoxDecoration(
            color: p.paper0,
            border: Border.all(color: p.accent, width: 1.5),
            borderRadius: BorderRadius.circular(3),
            boxShadow: [BoxShadow(color: p.ink0.withValues(alpha: 0.1), blurRadius: 2)],
          ),
        ),
      ),
    );
  }

  Widget _buildRotateHandle(Rect bounds, HwPalette p) {
    final centerTop = Offset(bounds.center.dx, bounds.top - _rotateHandleDistance);
    return Positioned(
      left: centerTop.dx - 12,
      top: centerTop.dy - 12,
      child: Column(
        children: [
          GestureDetector(
            onPanStart: (d) {
              // Compute element center in global coords from the handle position.
              // The handle is above the element center by a known distance
              // (half the element height + the handle gap). After rotation,
              // this vector is rotated, so we undo it to find the center.
              final dist = widget.bounds.height / 2 + _rotateHandleDistance;
              _rotationCenter = d.globalPosition + Offset(
                -dist * sin(widget.rotation),
                dist * cos(widget.rotation),
              );
              _lastRotationAngle = atan2(
                d.globalPosition.dy - _rotationCenter.dy,
                d.globalPosition.dx - _rotationCenter.dx,
              );
              widget.onDragStart?.call();
            },
            onPanUpdate: (d) {
              final currentAngle = atan2(
                d.globalPosition.dy - _rotationCenter.dy,
                d.globalPosition.dx - _rotationCenter.dx,
              );
              // Incremental delta, normalized to handle atan2 wrapping at ±π
              var delta = currentAngle - _lastRotationAngle;
              if (delta > pi) delta -= 2 * pi;
              if (delta < -pi) delta += 2 * pi;
              _lastRotationAngle = currentAngle;
              widget.onRotate(delta);
            },
            onPanEnd: (_) => widget.onDragEnd?.call(),
            onPanCancel: () => widget.onDragEnd?.call(),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: p.paper0,
                shape: BoxShape.circle,
                border: Border.all(color: p.accent, width: 2),
                boxShadow: [BoxShadow(color: p.ink0.withValues(alpha: 0.15), blurRadius: 3)],
              ),
              child: Icon(Icons.rotate_right_rounded, size: 14, color: p.accent),
            ),
          ),
          // Line connecting rotate handle to element
          IgnorePointer(
            child: Container(
              width: 1.5,
              height: _rotateHandleDistance - 12,
              color: p.accent.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Builder(builder: (context) {
      final p = HwThemeScope.of(context);
      final l10n = AppLocalizations.of(context);
      final surface = Theme.of(context).colorScheme.surface;
      final shadow = Theme.of(context).colorScheme.shadow;
      final inactiveIcon = Theme.of(context).colorScheme.onSurfaceVariant;
      return Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: shadow.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Text font-size controls — decoupled from box resize so the box
            // can be extended without deforming the glyphs.
            if (widget.onFontLarger != null && !widget.isLocked) ...[
              _actionBtn(Icons.text_decrease_rounded, p.ink2,
                  widget.onFontSmaller!, l10n.imgFontSmaller),
              _actionBtn(Icons.text_increase_rounded, p.ink2,
                  widget.onFontLarger!, l10n.imgFontLarger),
              _divider(),
            ],
            if (widget.onCrop != null && !widget.isLocked) ...[
              _actionBtn(Icons.crop_rounded, p.ink2, widget.onCrop!, l10n.imgCrop),
              _divider(),
            ],
            // "Copia" is the top-priority frequent action: copying an
            // image to paste into another app is the only way to get
            // the pixels out (Ctrl+C now does the same, but the
            // floating bar is the discoverable path). Was buried in
            // the overflow menu pre-fix.
            if (widget.onCopy != null) ...[
              _actionBtn(Icons.copy_rounded, p.ink2, widget.onCopy!, l10n.imgCopy),
              _divider(),
            ],
            if (widget.onToggleLock != null) ...[
              _actionBtn(
                widget.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                widget.isLocked ? HwTheme.syncPending : inactiveIcon,
                widget.onToggleLock!,
                widget.isLocked ? l10n.imgUnlock : l10n.imgLock,
              ),
              _divider(),
            ],
            if (!widget.isLocked) ...[
              _actionBtn(Icons.delete_outline_rounded, HwTheme.syncConflict, widget.onDelete, l10n.imgDelete),
              _divider(),
            ],
            // Overflow menu for less-used actions: bring-to-front,
            // send-to-back, comment, reflect, cut. Z-order shuffle is
            // rare enough that exposing the two big icons in the main
            // bar wasted space (and crowded the bar above the cropped
            // image — was harder to grab the resize handles).
            if (_hasOverflowActions()) ...[
              _buildOverflowMenu(),
              _divider(),
            ],
            _actionBtn(Icons.close_rounded, inactiveIcon, widget.onDeselect, l10n.imgDeselect),
          ],
        ),
      );
    });
  }

  Widget _divider() => Builder(builder: (context) {
    return Container(width: 1, height: 24, color: Theme.of(context).colorScheme.outlineVariant);
  });

  bool _hasOverflowActions() {
    return widget.onEditComment != null ||
        widget.onBringToFront != null ||
        widget.onSendToBack != null ||
        (widget.onFlipHorizontal != null && !widget.isLocked) ||
        (widget.onCut != null && !widget.isLocked);
  }

  Widget _buildOverflowMenu() {
    return Builder(builder: (context) {
      final p = HwThemeScope.of(context);
      final l10n = AppLocalizations.of(context);
      final inactiveIcon = Theme.of(context).colorScheme.onSurfaceVariant;
      return Tooltip(
        message: l10n.imgMoreActions,
        child: PopupMenuButton<String>(
          tooltip: '',
          padding: EdgeInsets.zero,
          icon: Icon(Icons.more_vert_rounded, size: 18, color: inactiveIcon),
          onSelected: (value) {
            switch (value) {
              case 'front':
                widget.onBringToFront?.call();
                break;
              case 'back':
                widget.onSendToBack?.call();
                break;
              case 'comment':
                widget.onEditComment?.call();
                break;
              case 'flip':
                widget.onFlipHorizontal?.call();
                break;
              case 'cut':
                widget.onCut?.call();
                break;
            }
          },
          itemBuilder: (ctx) => [
            if (widget.onBringToFront != null)
              PopupMenuItem<String>(
                value: 'front',
                child: Row(children: [
                  const Icon(Icons.flip_to_front_rounded, size: 18, color: HwTheme.teal),
                  const SizedBox(width: 10),
                  Text(l10n.imgBringToFront),
                ]),
              ),
            if (widget.onSendToBack != null)
              PopupMenuItem<String>(
                value: 'back',
                child: Row(children: [
                  const Icon(Icons.flip_to_back_rounded, size: 18, color: HwTheme.teal),
                  const SizedBox(width: 10),
                  Text(l10n.imgSendToBack),
                ]),
              ),
            if (widget.onEditComment != null)
              PopupMenuItem<String>(
                value: 'comment',
                child: Row(children: [
                  Icon(
                    widget.hasComment ? Icons.comment_rounded : Icons.comment_outlined,
                    size: 18,
                    color: widget.hasComment ? HwTheme.syncOk : inactiveIcon,
                  ),
                  const SizedBox(width: 10),
                  Text(l10n.imgComment),
                ]),
              ),
            if (widget.onFlipHorizontal != null && !widget.isLocked)
              PopupMenuItem<String>(
                value: 'flip',
                child: Row(children: [
                  Icon(
                    Icons.flip_rounded,
                    size: 18,
                    color: widget.isFlipped ? p.accent : inactiveIcon,
                  ),
                  const SizedBox(width: 10),
                  Text(widget.isFlipped ? l10n.imgFlipHChecked : l10n.imgFlipH),
                ]),
              ),
            if (widget.onCut != null && !widget.isLocked)
              PopupMenuItem<String>(
                value: 'cut',
                child: Row(children: [
                  Icon(Icons.content_cut_rounded, size: 18, color: p.ink2),
                  const SizedBox(width: 10),
                  Text(l10n.imgCut),
                ]),
              ),
          ],
        ),
      );
    });
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  void _handleCornerResize(String handle, Offset cumulativeDelta) {
    // Use the bounds CAPTURED at gesture start, not widget.bounds.
    // widget.bounds is LIVE (recomputed by the parent each frame from
    // notifier values). Computing per-tick newBounds against widget.bounds
    // would freeze growth at the first tick whenever the parent rebuild
    // lagged behind a fast pan stream — the visible bbox stayed small
    // while the user dragged on. Cumulative travel against the immutable
    // origBounds gives a stable, frame-rate-independent computation.
    final b = _resizeOrigBounds ?? widget.bounds;
    if (b.width <= 0 || b.height <= 0) return;

    // Project the (origCorner + cumulativeDelta) point onto the
    // original anchor→corner diagonal direction. scale = projection /
    // diag_length² is the cumulative-vs-original scale factor; smooth
    // and monotonic regardless of pointer wobble or rebuild cadence.
    late Offset anchor;
    late Offset corner;
    switch (handle) {
      case 'tl': anchor = b.bottomRight; corner = b.topLeft;     break;
      case 'tr': anchor = b.bottomLeft;  corner = b.topRight;    break;
      case 'bl': anchor = b.topRight;    corner = b.bottomLeft;  break;
      case 'br': anchor = b.topLeft;     corner = b.bottomRight; break;
      default: return;
    }
    final diag = corner - anchor;
    final diagLenSq = diag.dx * diag.dx + diag.dy * diag.dy;
    if (diagLenSq <= 0) return;

    final newCorner = corner + cumulativeDelta;
    final newVec = newCorner - anchor;
    final scale = (newVec.dx * diag.dx + newVec.dy * diag.dy) / diagLenSq;
    if (scale <= 0) return;

    final newW = b.width * scale;
    final newH = b.height * scale;
    Rect newBounds;
    switch (handle) {
      case 'tl': newBounds = Rect.fromLTWH(anchor.dx - newW, anchor.dy - newH, newW, newH); break;
      case 'tr': newBounds = Rect.fromLTWH(anchor.dx,        anchor.dy - newH, newW, newH); break;
      case 'bl': newBounds = Rect.fromLTWH(anchor.dx - newW, anchor.dy,        newW, newH); break;
      case 'br': newBounds = Rect.fromLTWH(anchor.dx,        anchor.dy,        newW, newH); break;
      default: return;
    }
    if (newBounds.width > 20 && newBounds.height > 20) {
      widget.onResize(newBounds);
    }
  }

  void _handleEdgeResize(String handle, Offset cumulativeDelta) {
    // Cumulative against orig snapshot — see comment on _handleCornerResize
    // for why widget.bounds (live) would freeze the drag at fast pan
    // rates.
    final b = _resizeOrigBounds ?? widget.bounds;
    Rect newBounds;
    switch (handle) {
      case 'tm':
        newBounds = Rect.fromLTRB(b.left, b.top + cumulativeDelta.dy, b.right, b.bottom);
        break;
      case 'bm':
        newBounds = Rect.fromLTRB(b.left, b.top, b.right, b.bottom + cumulativeDelta.dy);
        break;
      case 'ml':
        newBounds = Rect.fromLTRB(b.left + cumulativeDelta.dx, b.top, b.right, b.bottom);
        break;
      case 'mr':
        newBounds = Rect.fromLTRB(b.left, b.top, b.right + cumulativeDelta.dx, b.bottom);
        break;
      default:
        return;
    }
    if (newBounds.width > 20 && newBounds.height > 20) {
      widget.onResize(newBounds);
    }
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;

  _DashedBorderPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const dashWidth = 6.0;
    const dashSpace = 4.0;

    // Top
    _drawDashedLine(canvas, Offset.zero, Offset(size.width, 0), paint, dashWidth, dashSpace);
    // Right
    _drawDashedLine(canvas, Offset(size.width, 0), Offset(size.width, size.height), paint, dashWidth, dashSpace);
    // Bottom
    _drawDashedLine(canvas, Offset(0, size.height), Offset(size.width, size.height), paint, dashWidth, dashSpace);
    // Left
    _drawDashedLine(canvas, Offset.zero, Offset(0, size.height), paint, dashWidth, dashSpace);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint, double dashWidth, double dashSpace) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = sqrt(dx * dx + dy * dy);
    final unitX = dx / len;
    final unitY = dy / len;

    double drawn = 0;
    bool drawing = true;
    while (drawn < len) {
      final segLen = drawing ? dashWidth : dashSpace;
      final nextDrawn = (drawn + segLen).clamp(0.0, len);
      if (drawing) {
        canvas.drawLine(
          Offset(start.dx + unitX * drawn, start.dy + unitY * drawn),
          Offset(start.dx + unitX * nextDrawn, start.dy + unitY * nextDrawn),
          paint,
        );
      }
      drawn = nextDrawn;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
