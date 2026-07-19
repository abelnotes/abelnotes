import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Post-import issue list ("image X missing", "attachment skipped", …).
/// Shown only when the report carries issues; a clean import just toasts.
Future<void> showImportReportDialog(
    BuildContext context, ImportReport report) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.importReportTitle(report.issues.length)),
      content: SizedBox(
        width: 480,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: report.issues.length,
            itemBuilder: (_, i) {
              final issue = report.issues[i];
              final color = switch (issue.severity) {
                ImportIssueSeverity.error => HwTheme.syncConflict,
                ImportIssueSeverity.warning => const Color(0xFFB26A00),
                ImportIssueSeverity.info => null,
              };
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(issue.source,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600)),
                    Text(issue.message,
                        style: TextStyle(fontSize: 12, color: color)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            final text = report.issues
                .map((i) => '[${i.severity.name}] ${i.source}: ${i.message}')
                .join('\n');
            Clipboard.setData(ClipboardData(text: text));
          },
          child: Text(l10n.importReportCopy),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.importReportClose),
        ),
      ],
    ),
  );
}
