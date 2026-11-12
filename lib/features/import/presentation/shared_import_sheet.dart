import 'package:flutter/material.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/primitives/scrollable_sheet.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Where a file opened from another app goes: a new notebook, or [notebook].
class SharedImportTarget {
  final NotebookEntry? notebook;
  const SharedImportTarget.newNotebook() : notebook = null;
  const SharedImportTarget.existing(NotebookEntry this.notebook);
}

/// Asks where to import [title] (a file name, or "N files"). Null when
/// dismissed.
Future<SharedImportTarget?> showSharedImportSheet(
  BuildContext context, {
  required String title,
  required List<NotebookEntry> notebooks,
}) {
  final p = HwThemeScope.of(context);
  final l10n = AppLocalizations.of(context);
  return showScrollableSheet<SharedImportTarget>(
    context: context,
    backgroundColor: p.paper0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: HwIcon('plus', size: 20, color: p.accent),
            ),
            title: Text(l10n.libNewNotebook),
            subtitle: Text(l10n.shareImportNewNotebookHint,
                style: const TextStyle(fontSize: 12)),
            onTap: () =>
                Navigator.of(ctx).pop(const SharedImportTarget.newNotebook()),
          ),
          if (notebooks.isNotEmpty) ...[
            Divider(height: 1, color: p.paper2),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                l10n.shareImportAddTo,
                style: TextStyle(fontSize: 12, color: p.ink2),
              ),
            ),
            for (final n in notebooks)
              ListTile(
                leading: Container(
                  width: 28,
                  height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Color(n.metadata.coverColor),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                title: Text(n.metadata.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(l10n.libPagesCount(n.metadata.pageCount),
                    style: const TextStyle(fontSize: 12)),
                onTap: () =>
                    Navigator.of(ctx).pop(SharedImportTarget.existing(n)),
              ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Where inside an existing notebook: the end of [chapterId], a new
/// chapter when [newChapter], else the end of the notebook.
class SharedImportPlace {
  final String? chapterId;
  final bool newChapter;
  const SharedImportPlace.endOf(String this.chapterId) : newChapter = false;
  /// The end of a notebook that has no chapters.
  const SharedImportPlace.end()
      : chapterId = null,
        newChapter = false;
  const SharedImportPlace.newChapter()
      : chapterId = null,
        newChapter = true;
}

/// Second step for an existing notebook: which chapter. Null when dismissed.
Future<SharedImportPlace?> showSharedImportPlaceSheet(
  BuildContext context, {
  required NotebookEntry notebook,
}) {
  final p = HwThemeScope.of(context);
  final l10n = AppLocalizations.of(context);
  return showScrollableSheet<SharedImportPlace>(
    context: context,
    backgroundColor: p.paper0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              l10n.shareImportWhere(notebook.metadata.title),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (notebook.metadata.chapters.isEmpty)
            ListTile(
              leading: HwIcon('chapter', size: 20, color: p.ink1),
              title: Text(l10n.shareImportAtEnd),
              onTap: () => Navigator.of(ctx).pop(const SharedImportPlace.end()),
            ),
          for (final c in notebook.metadata.chapters)
            ListTile(
              leading: HwIcon('chapter', size: 20, color: p.ink1),
              title: Text(l10n.shareImportEndOf(c.title),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () =>
                  Navigator.of(ctx).pop(SharedImportPlace.endOf(c.id)),
            ),
          Divider(height: 1, color: p.paper2),
          ListTile(
            leading: HwIcon('plus', size: 20, color: p.accent),
            title: Text(l10n.pmNewChapter),
            subtitle: Text(l10n.shareImportNewChapterHint,
                style: const TextStyle(fontSize: 12)),
            onTap: () =>
                Navigator.of(ctx).pop(const SharedImportPlace.newChapter()),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
