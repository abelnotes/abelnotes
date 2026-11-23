// Small stateless widgets used by the editor screen: floating action button,
// presentation button, menu row, shortcut group.

import 'package:flutter/material.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Context menu row with icon, label, and optional shortcut
class FloatingActionBtn extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final Color? color;

  const FloatingActionBtn(this.icon, this.label, this.onTap, {this.color, super.key});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final c = color ?? p.ink1;
    final iconWidget = Icon(icon, size: 20, color: c);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              if (label != null)
                Text(label!, style: TextStyle(fontSize: 9, color: c)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small, semi-transparent circular tap target used by presentation mode's
/// corner controls (exit / prev / next) — bounded hit area, unlike a
/// full-screen gesture layer, so it never steals pointer events meant for
/// the laser tool elsewhere on the canvas.
class PresentationIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const PresentationIconButton({required this.icon, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

class MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? shortcut;

  const MenuRow(this.icon, this.label, this.shortcut, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: p.ink2),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        if (shortcut != null)
          Text(shortcut!, style: TextStyle(fontSize: 11, color: p.ink3)),
      ],
    );
  }
}

/// Group of keyboard-shortcut rows shown in the help dialog. Kept const so
/// the list of (combo, description) pairs can be declared inline without
/// per-build allocations.
class ShortcutGroup extends StatelessWidget {
  final String title;
  final List<(String, String)> entries;
  const ShortcutGroup(this.title, this.entries, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: p.ink2,
          ),
        ),
        const SizedBox(height: 6),
        ...entries.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: p.paper2,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: p.paperEdge, width: 0.5),
                    ),
                    child: Text(
                      e.$1,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(e.$2, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
