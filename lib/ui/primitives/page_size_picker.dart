import 'package:flutter/material.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Paper size chips plus a portrait/landscape pair, shared by the
/// new-notebook dialog and the editor's paper sheet. [preset] is null when
/// the page has a size no preset matches; then no size chip is selected.
class PageSizePicker extends StatelessWidget {
  final PageSizePreset? preset;
  final bool landscape;
  final void Function(PageSizePreset preset, bool landscape) onChanged;

  const PageSizePicker({
    super.key,
    required this.preset,
    required this.landscape,
    required this.onChanged,
  });

  static String presetLabel(AppLocalizations l10n, PageSizePreset preset) {
    switch (preset) {
      case PageSizePreset.a4: return 'A4';
      case PageSizePreset.a5: return 'A5';
      case PageSizePreset.b5: return 'B5';
      case PageSizePreset.letter: return l10n.pageSizeLetter;
      case PageSizePreset.legal: return l10n.pageSizeLegal;
      case PageSizePreset.square: return l10n.pageSizeSquare;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = preset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in PageSizePreset.values)
              _chip(context, presetLabel(l10n, p), p == current,
                  () => onChanged(p, landscape)),
          ],
        ),
        // A square page reads the same either way round.
        if (current != null && current != PageSizePreset.square) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              _chip(context, l10n.pageSizePortrait, !landscape,
                  () => onChanged(current, false)),
              _chip(context, l10n.pageSizeLandscape, landscape,
                  () => onChanged(current, true)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _chip(
      BuildContext context, String label, bool selected, VoidCallback onTap) {
    final p = HwThemeScope.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? p.ink0 : p.paper2,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? p.paper0 : p.ink0, fontSize: 13)),
        ),
      ),
    );
  }
}
