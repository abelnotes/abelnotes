import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';
import 'package:abelnotes/ui/primitives/hw_button.dart';

/// Lists trashed notebooks (soft-deleted, see [NotebookListNotifier.deleteNotebook])
/// with restore / delete-forever actions, and an empty-trash action. There is
/// no Riverpod stream for trash — [FileService.listTrash] is a one-shot
/// Future, so this screen re-fetches after every mutation.
class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  List<TrashEntry>? _entries;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await ref.read(notebookListProvider.notifier).listTrash();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _restore(TrashEntry entry) async {
    await ref.read(notebookListProvider.notifier).restoreFromTrash(entry.trashId);
    await _load();
  }

  Future<void> _purge(TrashEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.setTrashPurgeTitle(entry.title)),
        content: Text(l10n.setTrashPurgeBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.setCancel)),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: HwTheme.syncConflict),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.setTrashPurge)),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(notebookListProvider.notifier).purgeTrashEntry(entry.trashId);
    await _load();
  }

  Future<void> _emptyTrash() async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.setTrashEmptyTitle),
        content: Text(l10n.setTrashEmptyBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.setCancel)),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: HwTheme.syncConflict),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.setTrashEmpty)),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(notebookListProvider.notifier).emptyTrash();
    await _load();
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays >= 1) return '${diff.inDays}d';
    if (diff.inHours >= 1) return '${diff.inHours}h';
    return '${diff.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final entries = _entries ?? const <TrashEntry>[];
    return Scaffold(
      backgroundColor: p.paper1,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const HwIcon('chevron-left', size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(l10n.setTrash,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: p.ink0)),
                  ),
                  if (entries.isNotEmpty)
                    TextButton(
                      onPressed: _emptyTrash,
                      child: Text(l10n.setTrashEmpty,
                          style: TextStyle(color: HwTheme.syncConflict)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : entries.isEmpty
                      ? Center(
                          child: Text(l10n.setTrashEmptyState,
                              style: TextStyle(fontSize: 14, color: p.ink2)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          itemCount: entries.length,
                          separatorBuilder: (_, __) =>
                              Divider(color: p.paper2, height: 1),
                          itemBuilder: (_, i) {
                            final entry = entries[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Color(entry.coverColor)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(Icons.description_outlined,
                                        size: 18, color: Color(entry.coverColor)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(entry.title,
                                            style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: p.ink0)),
                                        const SizedBox(height: 2),
                                        Text(
                                            l10n.setTrashDeletedAgo(
                                                _formatDate(entry.deletedAt)),
                                            style: TextStyle(
                                                fontSize: 12, color: p.ink2)),
                                      ],
                                    ),
                                  ),
                                  Text(
                                      _formatSize(
                                          entry.meta?['file_size'] as int?),
                                      style:
                                          TextStyle(fontSize: 12, color: p.ink2)),
                                  const SizedBox(width: 12),
                                  HwButton(
                                      label: l10n.setTrashRestore,
                                      style: HwButtonStyle.solid,
                                      onPressed: () => _restore(entry)),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: HwIcon('trash', size: 16, color: p.ink2),
                                    onPressed: () => _purge(entry),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
