// PDF import page-range picker dialog and its result type.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

// ═══════════════════════════════════════════════════════════════
//  PDF IMPORT RANGE PICKER
// ═══════════════════════════════════════════════════════════════

/// Page range chosen by the user when importing a PDF. `null` on either
/// side means "no bound on this side" — i.e. start from page 1 or end at
/// the last page. Both null = import every page.
class PdfImportRange {
  final int? start;
  final int? end;
  const PdfImportRange({this.start, this.end});
  const PdfImportRange.all() : start = null, end = null;
}

class PdfRangeDialog extends StatefulWidget {
  final int estimatedPages;
  const PdfRangeDialog({required this.estimatedPages, super.key});

  @override
  State<PdfRangeDialog> createState() => _PdfRangeDialogState();
}

class _PdfRangeDialogState extends State<PdfRangeDialog> {
  /// 'all' or 'range'.
  String _mode = 'all';
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCtrl = TextEditingController(text: '1');
    _endCtrl = TextEditingController(
      text: widget.estimatedPages > 0 ? '${widget.estimatedPages}' : '',
    );
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_mode == 'all') {
      Navigator.of(context).pop(const PdfImportRange.all());
      return;
    }
    final l10n = AppLocalizations.of(context);
    final start = int.tryParse(_startCtrl.text.trim());
    final end = int.tryParse(_endCtrl.text.trim());
    if (start == null || end == null || start < 1 || end < start) {
      setState(() => _error = l10n.csInvalidRangeError);
      return;
    }
    if (widget.estimatedPages > 0 && start > widget.estimatedPages) {
      setState(() => _error =
          l10n.qiPdfStartOutOfRange(widget.estimatedPages));
      return;
    }
    final clampedEnd =
        widget.estimatedPages > 0 ? min(end, widget.estimatedPages) : end;
    Navigator.of(context).pop(PdfImportRange(start: start, end: clampedEnd));
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final est = widget.estimatedPages;
    return AlertDialog(
      title: Text(l10n.csImportPdfTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (est > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                l10n.qiPdfPageCount(est),
                style: TextStyle(color: p.ink2),
              ),
            ),
          RadioListTile<String>(
            value: 'all',
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v ?? 'all'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(est > 0
                ? l10n.csAllPagesWithCount(est)
                : l10n.csAllPages),
          ),
          RadioListTile<String>(
            value: 'range',
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v ?? 'all'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l10n.csCustomRange),
          ),
          if (_mode == 'range') ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.csFromLabel,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _confirm(),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('–'),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _endCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.csToLabel,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _confirm(),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: HwTheme.syncConflict, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.csCancel),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(l10n.csImport),
        ),
      ],
    );
  }
}
