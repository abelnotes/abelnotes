import 'package:flutter/material.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/l10n/app_localizations.dart';

/// Shared state between the running import and its progress dialog: the
/// importers push [ImportProgress] updates in, the user's Annulla button
/// flips [cancelled], which the importers poll between files/chunks.
class ImportRunController {
  final ValueNotifier<ImportProgress> progress = ValueNotifier(
      const ImportProgress(phase: ImportPhase.scanning));
  bool _cancelled = false;

  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
  void update(ImportProgress p) => progress.value = p;
  void dispose() => progress.dispose();
}

/// Modal progress dialog. Not awaited by the caller — dismissed via
/// Navigator.pop when the import finishes or fails.
void showImportProgressDialog(
    BuildContext context, ImportRunController controller) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ImportProgressDialog(controller: controller),
  );
}

class _ImportProgressDialog extends StatelessWidget {
  final ImportRunController controller;

  const _ImportProgressDialog({required this.controller});

  String _phaseLabel(AppLocalizations l10n, ImportProgress p) {
    switch (p.phase) {
      case ImportPhase.scanning:
        return l10n.importPhaseScanning;
      case ImportPhase.parsing:
        return l10n.importPhaseParsing(p.current + 1, p.total);
      case ImportPhase.paginating:
        return l10n.importPhasePaginating(p.current + 1, p.total);
      case ImportPhase.packaging:
      case ImportPhase.done:
        return l10n.importPhasePackaging;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ValueListenableBuilder<ImportProgress>(
            valueListenable: controller.progress,
            builder: (context, p, _) {
              final determinate =
                  p.total > 0 && p.phase != ImportPhase.packaging;
              return ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 280, maxWidth: 340),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_phaseLabel(l10n, p),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (p.detail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        p.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: determinate ? p.current / p.total : null,
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: controller.cancel,
                        child: Text(l10n.importCancel),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
