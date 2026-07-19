import 'package:flutter/material.dart';
import '../theme/hw_theme.dart';

enum HwButtonStyle { ghost, solid, primary }

/// Compact button matching the design spec.
/// - ghost: transparent, hovers paper2
/// - solid: paper2 background
/// - primary: ink0 background, paper0 text
class HwButton extends StatefulWidget {
  final Widget? leading;
  final Widget? trailing;
  final String? label;
  final VoidCallback? onPressed;
  final HwButtonStyle style;
  final EdgeInsetsGeometry padding;
  final String? tooltip;
  final Color? color; // override foreground color
  final bool dense;

  const HwButton({
    super.key,
    this.leading,
    this.trailing,
    this.label,
    this.onPressed,
    this.style = HwButtonStyle.ghost,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.tooltip,
    this.color,
    this.dense = false,
  });

  /// Icon-only round button.
  factory HwButton.icon({
    Key? key,
    required Widget icon,
    VoidCallback? onPressed,
    String? tooltip,
    HwButtonStyle style = HwButtonStyle.ghost,
    Color? color,
  }) =>
      HwButton(
        key: key,
        leading: icon,
        onPressed: onPressed,
        tooltip: tooltip,
        style: style,
        color: color,
        padding: const EdgeInsets.all(8),
      );

  @override
  State<HwButton> createState() => _HwButtonState();
}

class _HwButtonState extends State<HwButton> {
  bool _hover = false;
  bool _press = false;

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final disabled = widget.onPressed == null;

    Color bg;
    Color fg;
    switch (widget.style) {
      case HwButtonStyle.ghost:
        fg = widget.color ?? p.ink1;
        if (_press) {
          bg = p.paper3;
        } else if (_hover) {
          bg = p.paper2;
          fg = widget.color ?? p.ink0;
        } else {
          bg = Colors.transparent;
        }
        break;
      case HwButtonStyle.solid:
        fg = widget.color ?? p.ink0;
        bg = _hover ? p.paper3 : p.paper2;
        break;
      case HwButtonStyle.primary:
        fg = widget.color ?? p.paper0;
        bg = _hover ? p.accentDeep : p.ink0;
        break;
    }

    final padding = widget.dense
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
        : widget.padding;

    final children = <Widget>[];
    if (widget.leading != null) {
      children.add(IconTheme(
          data: IconThemeData(color: fg, size: 16), child: widget.leading!));
    }
    if (widget.label != null) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 6));
      children.add(Text(widget.label!,
          style: TextStyle(
              color: fg,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: HwTheme.fontSans)));
    }
    if (widget.trailing != null) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 6));
      children.add(IconTheme(
          data: IconThemeData(color: fg, size: 16), child: widget.trailing!));
    }

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(HwTheme.rSm),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );

    final btn = Opacity(
      opacity: disabled ? 0.4 : 1,
      child: MouseRegion(
        cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _press = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _press = true),
          onTapCancel: () => setState(() => _press = false),
          onTapUp: (_) => setState(() => _press = false),
          onTap: disabled ? null : widget.onPressed,
          child: content,
        ),
      ),
    );

    final wrapped = widget.tooltip == null
        ? btn
        : Tooltip(
            message: widget.tooltip!,
            waitDuration: const Duration(milliseconds: 400),
            child: btn);

    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.tooltip ?? widget.label,
      child: wrapped,
    );
  }
}

/// Vertical hairline divider, 18px tall.
class HwDivider extends StatelessWidget {
  final double height;
  final double width;
  const HwDivider({super.key, this.height = 18, this.width = 1});
  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Container(width: width, height: height, color: p.paper3);
  }
}

/// Pill-style label / chip.
class HwPill extends StatelessWidget {
  final String label;
  final Widget? leading;
  final Color? background;
  final Color? foreground;
  const HwPill(
      {super.key,
      required this.label,
      this.leading,
      this.background,
      this.foreground});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? p.paper2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            IconTheme(
                data: IconThemeData(color: foreground ?? p.ink1, size: 12),
                child: leading!),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: foreground ?? p.ink1)),
        ],
      ),
    );
  }
}

/// Search-style text field with leading icon.
class HwTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final Widget? leading;
  final ValueChanged<String>? onChanged;
  final double width;

  const HwTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.leading,
    this.onChanged,
    this.width = 240,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 14, color: p.ink0),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: p.ink3),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          prefixIcon: leading == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 10, right: 6),
                  child: IconTheme(
                      data: IconThemeData(color: p.ink3, size: 16),
                      child: leading!),
                ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 0),
          filled: true,
          fillColor: p.paper2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HwTheme.rMd),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HwTheme.rMd),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HwTheme.rMd),
            borderSide: BorderSide(color: p.paperEdge),
          ),
        ),
      ),
    );
  }
}

/// Switch in the design spec — pill-shaped, accent fill when on.
class HwSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const HwSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36,
          height: 22,
          decoration: BoxDecoration(
            color: value ? p.accent : p.paper3,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 150),
                top: 2,
                left: value ? 16 : 2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 2,
                          offset: Offset(0, 1)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
