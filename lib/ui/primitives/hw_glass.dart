import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/hw_theme.dart';
import '../theme/hw_motion.dart';

// Saturation 1.6 (Rec. 709 luma), so colors under the blur stay alive.
const _saturate = <double>[
  1.4724, -0.4291, -0.0433, 0, 0, //
  -0.1276, 1.1709, -0.0433, 0, 0, //
  -0.1276, -0.4291, 1.5567, 0, 0, //
  0, 0, 0, 1, 0,
];

/// Translucent chrome: blurred backdrop, tinted fill, light-catching top
/// edge. High-contrast mode swaps it for a solid surface with a real border.
class HwGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final bool shadow;
  /// Heavier fill for surfaces stacked over other glass (popups).
  final bool strong;
  final EdgeInsetsGeometry? padding;

  const HwGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(HwTheme.rLg)),
    this.blur = 22,
    this.shadow = true,
    this.strong = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final solid = MediaQuery.maybeHighContrastOf(context) ?? false;
    // Web gets no backdrop blur (CanvasKit redoes it on every frame), so
    // the fill turns opaque, like iOS with Reduce Transparency.
    final fill = solid
        ? p.paper0
        : kIsWeb
            ? Color.alphaBlend(p.glass, p.paper0)
            : strong
                ? Color.alphaBlend(p.glass, p.paper0).withValues(alpha: 0.9)
                : p.glass;
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: borderRadius,
        border: Border.all(
            color: solid ? p.ink2 : p.glassLine, width: solid ? 1.5 : 1),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    if (!solid) {
      body = Stack(children: [
        body,
        // Bright top edge: light catching the material.
        Positioned(
          top: 0.5,
          left: math.min(borderRadius.topLeft.x, 18) * 0.8,
          right: math.min(borderRadius.topRight.x, 18) * 0.8,
          height: 1,
          child: IgnorePointer(child: ColoredBox(color: p.glassEdge)),
        ),
      ]);
      body = ClipRRect(
        borderRadius: borderRadius,
        child: kIsWeb
            ? body
            : BackdropFilter(
                filter: ui.ImageFilter.compose(
                  outer: const ColorFilter.matrix(_saturate),
                  inner: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                ),
                child: body,
              ),
      );
    }
    if (!shadow) return body;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        // Outer-only so the shadow never muddies the translucent fill.
        boxShadow: [
          for (final s in hwShadow2(p.brightness))
            BoxShadow(
              color: s.color,
              blurRadius: s.blurRadius,
              // Outer blur clears the offset shape, which left a bare strip
              // under the panel; it only looks right centred.
              offset: kIsWeb ? s.offset : Offset.zero,
              // Normal on web: the only style Skia draws analytically.
              blurStyle: kIsWeb ? BlurStyle.normal : BlurStyle.outer,
            ),
        ],
      ),
      child: body,
    );
  }
}

/// Scales its child to 0.97 the instant a pointer lands (no tap-delay),
/// and springs back on release. Purely visual: taps stay with [child].
class HwPressable extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double pressedScale;

  const HwPressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.97,
  });

  @override
  State<HwPressable> createState() => _HwPressableState();
}

class _HwPressableState extends State<HwPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController.unbounded(vsync: this, value: 1);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _to(double v, SpringDescription s) {
    if (!mounted) return;
    _c.springTo(v, spring: s);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || hwReduceMotion(context)) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _to(widget.pressedScale, HwSprings.press),
      onPointerUp: (_) => _to(1, HwSprings.standard),
      onPointerCancel: (_) => _to(1, HwSprings.standard),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.scale(scale: _c.value, child: child),
        child: widget.child,
      ),
    );
  }
}
