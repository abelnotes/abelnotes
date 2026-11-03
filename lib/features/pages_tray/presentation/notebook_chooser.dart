import 'dart:convert';
import 'package:abelnotes/core/platform/io.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/features/pages_tray/domain/pages_tray.dart';
import 'package:abelnotes/features/pages_tray/presentation/tray_widgets.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/shared/utils/chapter_title.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// What the chooser returns when the user wants the library instead.
const String kChooserLibrary = '__library__';

/// Notebooks a move can go to: this device's copies, the source left out,
/// the most recently opened first.
List<NotebookEntry> chooserNotebooks(
    List<NotebookEntry> all, String sourceId, Map<String, DateTime> opened) {
  final list = [
    for (final e in all)
      if (e.metadata.id != sourceId && !e.notOnDevice) e,
  ];
  DateTime when(NotebookEntry e) =>
      opened[e.metadata.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
  list.sort((a, b) {
    final c = when(b).compareTo(when(a));
    return c != 0 ? c : b.metadata.modifiedAt.compareTo(a.metadata.modifiedAt);
  });
  return list;
}

Future<int?> _chapterCount(WidgetRef ref, String id) async {
  try {
    final dir = ref.read(fileServiceProvider).notebookStoreDir(id);
    final m = NotebookMetadata.fromJson(jsonDecode(
            await File(p.join(dir, AppConfig.metadataFile)).readAsString())
        as Map<String, dynamic>);
    return m.chapters.length;
  } catch (_) {
    return null;
  }
}

/// "Move N pages to…": recent notebooks, then the library.
Future<String?> showNotebookChooser(
  BuildContext context, {
  required PagesTray tray,
  String? currentNotebookId,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: HwThemeScope.of(context).scrim,
    builder: (ctx) => _Chooser(tray: tray, currentId: currentNotebookId),
  );
}

class _Chooser extends ConsumerWidget {
  final PagesTray tray;
  final String? currentId;
  const _Chooser({required this.tray, required this.currentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = HwThemeScope.of(context);
    final l = AppLocalizations.of(context);
    final all = ref.watch(notebookListProvider).valueOrNull ?? const [];
    final opened = ref.watch(appSettingsProvider.select((s) => s.lastOpenedAt));
    final rows = chooserNotebooks(all, tray.sourceNotebookId, opened);
    return Dialog(
      backgroundColor: p.paper0,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.pgtChooserTitle(tray.count),
                          style: HwType.title.copyWith(color: p.ink0)),
                      const SizedBox(height: 2),
                      Text(trayFromLine(l, tray),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, color: p.ink2)),
                    ],
                  ),
                ),
                TrayRoundButton(
                    icon: 'x',
                    tooltip: l.pmClose,
                    onTap: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 14),
              Text(l.pgtRecent.toUpperCase(),
                  style: HwType.eyebrow.copyWith(color: p.ink2)),
              const SizedBox(height: 6),
              Flexible(
                child: rows.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(l.pgtChooserEmpty,
                            style: TextStyle(color: p.ink2, fontSize: 14)),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final e in rows)
                            _Row(
                                entry: e,
                                isCurrent: e.metadata.id == currentId),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, kChooserLibrary),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                        color: p.paper2,
                        borderRadius: BorderRadius.circular(18)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      HwIcon('book', size: 16, color: p.ink0),
                      const SizedBox(width: 7),
                      Text(l.pgtBrowseLibrary,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: p.ink0)),
                    ]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  final NotebookEntry entry;
  final bool isCurrent;
  const _Row({required this.entry, required this.isCurrent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = HwThemeScope.of(context);
    final l = AppLocalizations.of(context);
    final m = entry.metadata;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.pop(context, m.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(children: [
          Container(
            width: 34,
            height: 46,
            decoration: BoxDecoration(
              color: Color(m.coverColor),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(3),
                bottomLeft: Radius.circular(3),
                topRight: Radius.circular(6),
                bottomRight: Radius.circular(6),
              ),
              boxShadow: [
                BoxShadow(
                    color: p.ink0.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 3)),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chapterDisplayTitle(l, m.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: p.ink0)),
                FutureBuilder<int?>(
                  future: _chapterCount(ref, m.id),
                  builder: (_, snap) {
                    final ch = snap.data;
                    final text = ch == null || ch == 0
                        ? l.pgtNbPages(m.pageCount)
                        : l.pgtNbPagesChapters(
                            l.pgtNbPages(m.pageCount), l.pgtNbChapters(ch));
                    return Text(text,
                        style: TextStyle(fontSize: 12.5, color: p.ink2));
                  },
                ),
              ],
            ),
          ),
          HwIcon(isCurrent ? 'check' : 'chevron-right',
              size: 16, color: isCurrent ? p.accent : p.ink3),
        ]),
      ),
    );
  }
}
