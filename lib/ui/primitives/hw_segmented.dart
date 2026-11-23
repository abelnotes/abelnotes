import 'package:flutter/material.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// One choice of an [HwSegmented]: an icon (with [label] as tooltip) or text.
class HwSegment<T> {
  final T value;
  final String label;
  final IconData? icon;
  const HwSegment(this.value, this.label, {this.icon});
}

/// Compact segmented toggle, the same height as a chip's text line.
class HwSegmented<T> extends StatelessWidget {
  final List<HwSegment<T>> segments;
  final T selected;
  final ValueChanged<T>? onChanged;

  const HwSegmented({
    super.key,
    required this.segments,
    required this.selected,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    Widget segment(HwSegment<T> s) {
      final isSelected = s.value == selected;
      final fg = isSelected ? p.paper0 : p.ink1;
      final body = Container(
        padding: EdgeInsets.symmetric(
            horizontal: s.icon != null ? 8 : 10, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? p.ink0 : null,
          borderRadius: BorderRadius.circular(5),
        ),
        child: s.icon != null
            ? Icon(s.icon, size: 18, color: fg)
            : SizedBox(
                height: 18,
                child: Center(
                  widthFactor: 1,
                  child: Text(s.label,
                      style: TextStyle(fontSize: 13, color: fg)),
                ),
              ),
      );
      final tappable = Semantics(
        button: true,
        selected: isSelected,
        label: s.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isSelected || onChanged == null
              ? null
              : () => onChanged!(s.value),
          child: body,
        ),
      );
      return s.icon != null
          ? Tooltip(message: s.label, child: tappable)
          : tappable;
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: p.paper2,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (final s in segments) segment(s)],
      ),
    );
  }
}
