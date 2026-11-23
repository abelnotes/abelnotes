// The movable tool dock of the editor: drag and fly-to-edge state, snap
// geometry and the placement of the dock and its tool popup.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/features/canvas/presentation/editor/near_point_layout.dart';
import 'package:abelnotes/ui/editor/hw_editor_chrome.dart';
import 'package:abelnotes/ui/theme/hw_motion.dart';

class DockController {
  DockController({
    required this.vsync,
    required this.context,
    required this.ref,
    required this.stackKey,
    required this.isMounted,
    required this.cancelLongPress,
    required this.closePopup,
  }) {
    drag.addListener(_syncDragging);
  }

  final TickerProvider vsync;
  final BuildContext context;
  final WidgetRef ref;
  /// Key of the editor body stack, the dock's coordinate space.
  final GlobalKey stackKey;
  final bool Function() isMounted;
  final void Function() cancelLongPress;
  /// Closes the tool panel.
  final void Function() closePopup;

  // ── Placement geometry ──
  // The insets keep the docked toolbar clear of the 52px top bar and the
  // 84px bottom page strip.
  static const double topInset = 64;
  static const double bottomInset = 110;
  static const double sideInset = 16;
  static const double popupGap = 12;
  /// Editor top bar height; a dock dropped on it docks inside it.
  static const double topBarHeight = 52;
  /// Narrower than this the top bar has no room for the tools.
  static const double barMinWidth = 720;

  // While the grip is dragged, [drag] holds the dock's top-left in stack
  // coordinates. A notifier, not state: a drag frame moves only the dock,
  // never rebuilds the whole editor.
  final drag = ValueNotifier<Offset?>(null);
  Offset? get dragOffset => drag.value;
  /// Flips only when a drag starts or ends, not on every frame of it.
  final dragging = ValueNotifier<bool>(false);
  void _syncDragging() {
    final d = drag.value != null;
    if (dragging.value != d) dragging.value = d;
  }
  Size dragSize = Size.zero;
  /// The live editor area, cached by the layout for snap zones and clamping.
  Size area = Size.zero;
  final GlobalKey key = GlobalKey();

  /// Unresisted drag position; the shown one rubber-bands past the edges.
  Offset _rawOffset = Offset.zero;

  // Released dock glides to its edge on these, carrying the throw velocity.
  // Created on the first fling: making them in dispose() looks up the tree
  // of a widget being torn down.
  AnimationController? _flyX, _flyY;
  AnimationController get _dockFlyX =>
      _flyX ??= AnimationController.unbounded(vsync: vsync)..addListener(_onFly);
  AnimationController get _dockFlyY =>
      _flyY ??= AnimationController.unbounded(vsync: vsync)..addListener(_onFly);
  /// Bumped when a new drag grabs the dock, so a cancelled flight's late
  /// completion can't drop the dock back to its edge mid-drag.
  int _flyGen = 0;

  void dispose() {
    _flyX?.dispose();
    _flyY?.dispose();
    drag.removeListener(_syncDragging);
    drag.dispose();
    dragging.dispose();
  }

  static DockPosition edgePosition(String edge) {
    switch (edge) {
      case 'left':
        return DockPosition.left;
      case 'right':
        return DockPosition.right;
      case 'top':
        return DockPosition.top;
      default:
        return DockPosition.bottom;
    }
  }

  /// Map a 0..1 along-edge fraction to Flutter's -1..1 [Alignment] axis.
  static double alignToAxis(double align) => (align.clamp(0.0, 1.0) * 2) - 1;

  void onDragStart(DragStartDetails _) {
    final dockCtx = key.currentContext;
    final stackCtx = stackKey.currentContext;
    if (dockCtx == null || stackCtx == null) return;
    final dockBox = dockCtx.findRenderObject() as RenderBox?;
    final stackBox = stackCtx.findRenderObject() as RenderBox?;
    if (dockBox == null || stackBox == null) return;
    final flying = _dockFlyX.isAnimating || _dockFlyY.isAnimating;
    _flyGen++;
    _dockFlyX.stop();
    _dockFlyY.stop();
    final topLeft = flying && dragOffset != null
        ? dragOffset!
        : stackBox.globalToLocal(dockBox.localToGlobal(Offset.zero));
    // Grabbing the dock cancels any pending canvas long-press so the
    // context menu can't fire mid-drag (e.g. a resting finger started the
    // 600ms timer just before the other hand grabbed the grip).
    cancelLongPress();
    dragSize = dockBox.size;
    drag.value = topLeft;
    _rawOffset = topLeft;
    // A panel that floats around mid-drag is more distracting than useful:
    // close it; the user reopens it after parking the dock.
    closePopup();
    HapticFeedback.selectionClick();
  }

  static double _band(double v, double maxV) {
    if (v < 0) return -hwRubberband(-v, 160);
    if (v > maxV) return maxV + hwRubberband(v - maxV, 160);
    return v;
  }

  void onDragUpdate(DragUpdateDetails d) {
    if (dragOffset == null) return;
    _rawOffset += d.delta;
    var next = _rawOffset;
    if (area.width > 0 && area.height > 0) {
      next = Offset(
        _band(next.dx, max(0.0, area.width - dragSize.width)),
        _band(next.dy, max(0.0, area.height - dragSize.height)),
      );
    }
    drag.value = next;
  }

  void _onFly() {
    if (!isMounted()) return;
    drag.value = Offset(_dockFlyX.value, _dockFlyY.value);
  }

  /// Where the docked layout puts a dock of the given orientation; mirrors
  /// [dockedPositioned] and the dock's own size maths.
  static Offset dockedTopLeft(String edge, double align, Size area) {
    final vert = edge == 'left' || edge == 'right';
    final availMain = vert
        ? area.height - topInset - bottomInset
        : area.width - sideInset * 2;
    final m = HwFloatingDock.metricsFor(availMain);
    final main = min(m.extent, availMain);
    final cross = m.thickness;
    if (vert) {
      final x = edge == 'left' ? sideInset : area.width - sideInset - cross;
      return Offset(x, topInset + (availMain - main) * align);
    }
    final y = edge == 'top' ? topInset : area.height - bottomInset - cross;
    return Offset(sideInset + (availMain - main) * align, y);
  }

  void onDragEnd(DragEndDetails d) {
    final off = dragOffset;
    if (off == null || area.width <= 0 || area.height <= 0) {
      drag.value = null;
      return;
    }
    // Choose the edge from where the throw is heading, not where it let go.
    final v = d.velocity.pixelsPerSecond;
    final projected = off + Offset(hwProject(v.dx), hwProject(v.dy));
    final center = Offset(
      projected.dx.clamp(0.0, area.width - dragSize.width),
      projected.dy.clamp(0.0, area.height - dragSize.height),
    ) + Offset(dragSize.width / 2, dragSize.height / 2);
    // Dropped on the top bar: dock inside it, if the window is wide enough.
    if (center.dy < topBarHeight + 16 &&
        MediaQuery.sizeOf(context).width >= barMinWidth) {
      ref.read(appSettingsProvider.notifier).setToolDock('bar', 0.5);
      drag.value = null;
      HapticFeedback.lightImpact();
      return;
    }
    // Snap to whichever of the four edges the dock's centre is nearest.
    final dLeft = center.dx;
    final dRight = area.width - center.dx;
    final dTop = center.dy;
    final dBottom = area.height - center.dy;
    final nearest = [dLeft, dRight, dTop, dBottom].reduce(min);

    final String edge;
    final double align;
    if (nearest == dTop) {
      edge = 'top';
      align = _spanFraction(center.dx, sideInset, area.width - sideInset);
    } else if (nearest == dBottom) {
      edge = 'bottom';
      align = _spanFraction(center.dx, sideInset, area.width - sideInset);
    } else if (nearest == dLeft) {
      edge = 'left';
      align = _spanFraction(center.dy, topInset, area.height - bottomInset);
    } else {
      edge = 'right';
      align = _spanFraction(center.dy, topInset, area.height - bottomInset);
    }

    ref.read(appSettingsProvider.notifier).setToolDock(edge, align);
    final target = dockedTopLeft(edge, align, area);
    final instant = hwReduceMotion(context);
    final spring = v.distance > 600 ? HwSprings.fling : hwSpring(response: 0.4);
    _dockFlyX.value = off.dx;
    _dockFlyY.value = off.dy;
    var done = 0;
    final gen = ++_flyGen;
    void land() {
      if (++done == 2 && isMounted() && gen == _flyGen) {
        drag.value = null;
      }
    }
    _dockFlyX
        .springTo(target.dx, spring: spring, velocity: v.dx, instant: instant)
        .whenCompleteOrCancel(land);
    _dockFlyY
        .springTo(target.dy, spring: spring, velocity: v.dy, instant: instant)
        .whenCompleteOrCancel(land);
    HapticFeedback.lightImpact();
  }

  /// Normalise [v] within [lo, hi] to a 0..1 fraction (clamped).
  static double _spanFraction(double v, double lo, double hi) {
    if (hi <= lo) return 0.5;
    return ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
  }

  /// Place the docked toolbar against its edge. Left/right anchor to the
  /// side and centre vertically by [align]; top/bottom anchor to the
  /// top/bottom and centre horizontally by [align].
  static Widget dockedPositioned(DockPosition pos, double align, Widget child) {
    final axis = alignToAxis(align);
    switch (pos) {
      case DockPosition.left:
        return Positioned(
          left: sideInset,
          top: topInset,
          bottom: bottomInset,
          child: Align(alignment: Alignment(0, axis), child: child),
        );
      case DockPosition.right:
        return Positioned(
          right: sideInset,
          top: topInset,
          bottom: bottomInset,
          child: Align(alignment: Alignment(0, axis), child: child),
        );
      case DockPosition.top:
        return Positioned(
          left: sideInset,
          right: sideInset,
          top: topInset,
          child: Align(alignment: Alignment(axis, 0), child: child),
        );
      case DockPosition.bottom:
      case DockPosition.floating:
      case DockPosition.bar:
        return Positioned(
          left: sideInset,
          right: sideInset,
          bottom: bottomInset,
          child: Align(alignment: Alignment(axis, 0), child: child),
        );
    }
  }

  /// The tool panel beside the dock, or next to the Pencil's tip when a
  /// squeeze opened it there ([popupAt]).
  static Widget placePopup(DockPosition pos, double align, Size area,
      ({Offset tip, Rect area})? popupAt, Widget child) {
    if (popupAt == null) return _popupPositioned(pos, align, area, child);
    return Positioned.fill(
      child: CustomSingleChildLayout(
          delegate: NearPointLayout(popupAt.tip, popupAt.area), child: child),
    );
  }

  /// Place the tool popup adjacent to the docked toolbar: above for the
  /// bottom edge, below for the top, and to the inner side for left/right.
  /// For the vertical edges we position by an estimated height so the
  /// ~300px panel can never be clipped against the top/bottom of the band.
  static Widget _popupPositioned(
      DockPosition pos, double align, Size area, Widget child) {
    final axis = alignToAxis(align);
    // The dock shrinks itself to fit narrow screens, so ask it how thick
    // it actually is instead of assuming the full-size bar.
    final isVert = pos == DockPosition.left || pos == DockPosition.right;
    final dockExtent = isVert
        ? area.height - topInset - bottomInset
        : area.width - sideInset * 2;
    final thickness = HwFloatingDock.metricsFor(dockExtent).thickness;
    final offset = sideInset + thickness + popupGap;
    switch (pos) {
      case DockPosition.left:
      case DockPosition.right:
        const popupHeightGuess = 380.0;
        const bandTop = topInset;
        final bandBottom = area.height - bottomInset;
        final top = (bandTop +
                (bandBottom - bandTop - popupHeightGuess) * align)
            .clamp(bandTop, max(bandTop, bandBottom - popupHeightGuess))
            .toDouble();
        return Positioned(
          left: pos == DockPosition.left ? offset : null,
          right: pos == DockPosition.right ? offset : null,
          top: top,
          child: child,
        );
      case DockPosition.top:
        return Positioned(
          left: sideInset,
          right: sideInset,
          top: topInset + thickness + popupGap,
          child: Align(alignment: Alignment(axis, 0), child: child),
        );
      case DockPosition.bar:
        return Positioned(
          left: sideInset,
          right: sideInset,
          top: topBarHeight + popupGap,
          child: Align(child: child),
        );
      case DockPosition.bottom:
      case DockPosition.floating:
        return Positioned(
          left: sideInset,
          right: sideInset,
          bottom: bottomInset + thickness + popupGap,
          child: Align(alignment: Alignment(axis, 0), child: child),
        );
    }
  }
}
