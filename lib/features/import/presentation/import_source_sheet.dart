import 'package:flutter/material.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/onenote_importer.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/primitives/scrollable_sheet.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// "Importa da…" chooser. Returns the picked source type, or null when
/// dismissed. Styling mirrors the library's compact overflow menu.
Future<ImportSourceType?> showImportSourceSheet(BuildContext context) {
  final p = HwThemeScope.of(context);
  final l10n = AppLocalizations.of(context);
  return showScrollableSheet<ImportSourceType>(
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
          _SourceTile(
            // Our own mark — the same one onboarding and Settings → About use.
            logo: 'assets/branding/logo.png',
            icon: 'src-abelnote',
            tint: p.accent,
            title: l10n.importSourceNcnote,
            onTap: () => Navigator.of(ctx).pop(ImportSourceType.ncnote),
          ),
          _SourceTile(
            icon: 'src-obsidian',
            tint: _obsidianTint,
            title: l10n.importSourceObsidian,
            subtitle: l10n.importSourceObsidianHint,
            onTap: () => Navigator.of(ctx).pop(ImportSourceType.obsidianVault),
          ),
          _SourceTile(
            icon: 'src-notion',
            tint: p.ink0,
            title: l10n.importSourceNotion,
            subtitle: l10n.importSourceNotionHint,
            onTap: () => Navigator.of(ctx).pop(ImportSourceType.notionExport),
          ),
          if (OneNoteImporter.isSupported)
            _SourceTile(
              icon: 'src-onenote',
              tint: _oneNoteTint,
              title: l10n.importSourceOneNote,
              subtitle: l10n.importSourceOneNoteHint,
              onTap: () => Navigator.of(ctx).pop(ImportSourceType.onenote),
            ),
          _SourceTile(
            icon: 'src-samsung',
            tint: _samsungNotesTint,
            title: l10n.importSourceSamsung,
            subtitle: l10n.importSourceSamsungHint,
            onTap: () => Navigator.of(ctx).pop(ImportSourceType.samsungNotes),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Empty-library card offering the other apps' importers in one tap.
class ImportInvite extends StatelessWidget {
  final ValueChanged<ImportSourceType> onPick;
  final VoidCallback onDismiss;

  const ImportInvite(
      {super.key, required this.onPick, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    Widget source(String icon, Color tint, String label, ImportSourceType t) =>
        Material(
          color: p.paper0,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onPick(t),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 12, 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  alignment: Alignment.center,
                  child: HwIcon(icon, size: 16, color: tint),
                ),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 13, color: p.ink0)),
              ]),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: p.paper2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(l10n.libImportInviteTitle,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: p.ink0)),
            ),
            TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(foregroundColor: p.ink2),
              child: Text(l10n.libImportInviteLater,
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 12),
            child: Text(l10n.libImportInviteBody,
                style: TextStyle(fontSize: 12, color: p.ink2, height: 1.4)),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (OneNoteImporter.isSupported)
              source('src-onenote', _oneNoteTint, l10n.importSourceOneNote,
                  ImportSourceType.onenote),
            source('src-samsung', _samsungNotesTint, l10n.importSourceSamsung,
                ImportSourceType.samsungNotes),
            source('src-notion', p.ink0, l10n.importSourceNotion,
                ImportSourceType.notionExport),
            source('src-obsidian', _obsidianTint, l10n.importSourceObsidian,
                ImportSourceType.obsidianVault),
          ]),
        ],
      ),
    );
  }
}

/// Hues each source is popularly associated with, used to tint the drawn
/// fallback glyph. A colour is not a trademark on its own; the shapes in
/// hw_icons.dart tinted with it are ours, not the vendors' marks.
///
/// To show a vendor's REAL mark instead, drop the official artwork in
/// `assets/branding/`, declare it in pubspec.yaml next to the Google Drive
/// and Nextcloud marks, add its provenance row to the "Third-party marks"
/// table in ACKNOWLEDGMENTS.md, and pass it as `logo:` below — same terms
/// the two sync marks already ship under. The glyph then stops being drawn.
const _obsidianTint = Color(0xFF7C5CD6);
const _oneNoteTint = Color(0xFF7719AA);
const _samsungNotesTint = Color(0xFFE8603C);

/// One import source: the format's real mark when we ship one, otherwise a
/// tinted glyph, so the rows read as distinct formats instead of four grey
/// outlines. Mirrors `_BackendAvatar` in the settings screen — a bundled
/// mark is drawn untinted at its own colours, never recoloured to match the
/// theme, which is the condition the marks are shipped under.
class _SourceTile extends StatelessWidget {
  /// Asset path of the format's official mark, or null to draw [icon].
  final String? logo;
  final String icon;
  final Color tint;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.tint,
    required this.title,
    required this.onTap,
    this.logo,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: logo != null ? p.paper2 : tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: logo != null
            ? Image.asset(logo!,
                width: 22,
                height: 22,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium)
            : HwIcon(icon, size: 20, color: tint),
      ),
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 12)),
      onTap: onTap,
    );
  }
}
