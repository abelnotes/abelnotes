import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Paper size chips, a "Custom" chip that asks for width and height in
/// millimetres, and a portrait/landscape pair. Shared by the new-notebook
/// dialog and the editor's paper sheet. [size] is in points.
class PageSizePicker extends StatelessWidget {
  final Size size;
  final ValueChanged<Size> onChanged;

  const PageSizePicker({
    super.key,
    required this.size,
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

  static String _mm(double pt) {
    final mm = pt / ptPerMm;
    return mm.toStringAsFixed(mm == mm.roundToDouble() ? 0 : 1);
  }

  Future<void> _askCustom(BuildContext context) async {
    final picked = await showDialog<Size>(
      context: context,
      builder: (_) => _CustomSizeDialog(initial: size),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preset = pageSizePresetOf(size.width, size.height);
    final landscape = size.width > size.height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in PageSizePreset.values)
              _chip(context, presetLabel(l10n, p), p == preset,
                  () => onChanged(pageSizeFor(p, landscape: landscape))),
            _chip(
              context,
              preset == null
                  ? '${l10n.pageSizeCustom} · '
                      '${l10n.pageSizeCustomMm(_mm(size.width), _mm(size.height))}'
                  : l10n.pageSizeCustom,
              preset == null,
              () => _askCustom(context),
            ),
          ],
        ),
        // A square page reads the same either way round.
        if (size.width != size.height) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              _chip(context, l10n.pageSizePortrait, !landscape, () {
                if (landscape) onChanged(size.flipped);
              }),
              _chip(context, l10n.pageSizeLandscape, landscape, () {
                if (!landscape) onChanged(size.flipped);
              }),
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

/// Width and height in millimetres; pops the size in points.
class _CustomSizeDialog extends StatefulWidget {
  final Size initial;
  const _CustomSizeDialog({required this.initial});

  @override
  State<_CustomSizeDialog> createState() => _CustomSizeDialogState();
}

class _CustomSizeDialogState extends State<_CustomSizeDialog> {
  late final _width =
      TextEditingController(text: PageSizePicker._mm(widget.initial.width));
  late final _height =
      TextEditingController(text: PageSizePicker._mm(widget.initial.height));
  bool _showError = false;

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  double? _read(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    if (v == null || v < minPageSizeMm || v > maxPageSizeMm) return null;
    return v;
  }

  void _submit() {
    final w = _read(_width);
    final h = _read(_height);
    if (w == null || h == null) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(Size(w * ptPerMm, h * ptPerMm));
  }

  Widget _field(TextEditingController c, String label, {bool last = false}) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onChanged: (_) {
        if (_showError) setState(() => _showError = false);
      },
      onSubmitted: last ? (_) => _submit() : null,
      decoration: InputDecoration(
        labelText: label,
        errorText: _showError && _read(c) == null ? l10n.pageSizeRange : null,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: HwThemeScope.of(context).paper0,
      title: Text(l10n.pageSizeCustom),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_width, l10n.pageSizeWidthMm),
            const SizedBox(height: 12),
            _field(_height, l10n.pageSizeHeightMm, last: true),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.libCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.pageSizeApply),
        ),
      ],
    );
  }
}
