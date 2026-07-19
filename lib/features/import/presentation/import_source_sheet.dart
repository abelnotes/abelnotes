import 'package:flutter/material.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/onenote_importer.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// "Importa da…" chooser. Returns the picked source type, or null when
/// dismissed. Styling mirrors the library's compact overflow menu.
Future<ImportSourceType?> showImportSourceSheet(BuildContext context) {
  final p = HwThemeScope.of(context);
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<ImportSourceType>(
    context: context,
    backgroundColor: p.paper0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.importSourceTitle,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          ListTile(
            leading: const HwIcon('export', size: 18),
            title: Text(l10n.importSourceNcnote),
            onTap: () => Navigator.of(ctx).pop(ImportSourceType.ncnote),
          ),
          ListTile(
            leading: const HwIcon('folder', size: 18),
            title: Text(l10n.importSourceObsidian),
            subtitle: Text(l10n.importSourceObsidianHint,
                style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.of(ctx).pop(ImportSourceType.obsidianVault),
          ),
          ListTile(
            leading: const HwIcon('pages', size: 18),
            title: Text(l10n.importSourceNotion),
            subtitle: Text(l10n.importSourceNotionHint,
                style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.of(ctx).pop(ImportSourceType.notionExport),
          ),
          if (OneNoteImporter.isSupported)
            ListTile(
              leading: const HwIcon('text', size: 18),
              title: Text(l10n.importSourceOneNote),
              subtitle: Text(l10n.importSourceOneNoteHint,
                  style: const TextStyle(fontSize: 12)),
              onTap: () => Navigator.of(ctx).pop(ImportSourceType.onenote),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
