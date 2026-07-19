import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'dart:io';

import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/import_service.dart';
import 'package:abelnotes/features/import/data/notion_importer.dart';
import 'package:abelnotes/features/import/data/obsidian_importer.dart';
import 'package:abelnotes/features/import/data/onenote_importer.dart';
import 'package:abelnotes/features/import/presentation/import_progress_dialog.dart';
import 'package:abelnotes/features/import/presentation/import_report_dialog.dart';
import 'package:abelnotes/features/import/presentation/import_source_sheet.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/screens/settings_screen.dart';
import 'package:abelnotes/ui/services/notebook_opener.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';
import 'package:abelnotes/ui/primitives/hw_button.dart';
import 'package:abelnotes/ui/primitives/sync_badge.dart';
import 'package:uuid/uuid.dart';

/// HandWriter library screen, "warm paper" redesign.
class LibraryScreenV2 extends ConsumerStatefulWidget {
  const LibraryScreenV2({super.key});

  @override
  ConsumerState<LibraryScreenV2> createState() => _LibraryScreenV2State();
}

class _LibraryScreenV2State extends ConsumerState<LibraryScreenV2> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _gridView = true;
  Timer? _bgSyncTimer;
  String? _selectedFolderId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      ref.read(notebookListProvider.notifier).refresh();
      // Best-effort retry of pending uploads on cold boot.
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      try {
        await ref.read(notebookListProvider.notifier).retryPendingUploads();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _bgSyncTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final settings = ref.watch(appSettingsProvider);
    final asyncList = ref.watch(notebookListProvider);

    final entries = asyncList.valueOrNull ?? const <NotebookEntry>[];
    final filtered =
        _filterAndSort(entries, settings, _query, _selectedFolderId);
    // Free-sketch notebooks (infinite canvas) live in their own home
    // section; keep them out of the A4 "taccuini" grid.
    final sketches = filtered
        .where((n) => n.metadata.paperType == AppConfig.infinitePaperType)
        .toList();
    final notebooks = filtered
        .where((n) => n.metadata.paperType != AppConfig.infinitePaperType)
        .toList();

    final notebookNotifier = ref.read(notebookListProvider.notifier);
    return Scaffold(
      backgroundColor: p.paper1,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              searchController: _searchCtrl,
              onSearchChanged: (v) => setState(() => _query = v),
              gridView: _gridView,
              onViewToggle: (v) => setState(() => _gridView = v),
              onSortTap: _showSortSheet,
              onSettingsTap: _openSettings,
              onImportTap: _importFlow,
              sortLabel: settings.sortMode.labelOf(AppLocalizations.of(context)),
            ),
            _FolderChipRow(
                folders: settings.folders,
                selectedFolderId: _selectedFolderId,
                onSelect: (id) => setState(() => _selectedFolderId = id),
                onCreate: () async {
                  final name = await _newFolderDialog(context);
                  if (name != null && name.isNotEmpty) {
                    ref.read(appSettingsProvider.notifier).createFolder(name);
                  }
                },
                onRename: (folder) async {
                  final name = await _newFolderDialog(context, initial: folder.name);
                  if (name != null && name.isNotEmpty) {
                    ref.read(appSettingsProvider.notifier).renameFolder(folder.id, name);
                  }
                },
                onDelete: (folder) async {
                  final l10n = AppLocalizations.of(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      title: Text(l10n.libDeleteFolderTitle(folder.name)),
                      content: Text(l10n.libDeleteFolderBody),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(dCtx, false),
                            child: Text(l10n.libCancel)),
                        FilledButton(
                            onPressed: () => Navigator.pop(dCtx, true),
                            child: Text(l10n.libDelete)),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    if (_selectedFolderId == folder.id) {
                      setState(() => _selectedFolderId = null);
                    }
                    ref.read(appSettingsProvider.notifier).deleteFolder(folder.id);
                  }
                },
              ),
            // Sync-in-progress banner — visible during any background
            // refresh, including the cold-start fetch on a fresh device
            // (where `entries` is empty and the body just shows the
            // "Nuovo taccuino" tile). Without this, a new-device user
            // saw the empty body and had no clue notebooks were
            // streaming in. The earlier banner-fix landed on the legacy
            // LibraryScreen (lib/features/library/library_screen.dart)
            // which main.dart no longer renders — this is the
            // production screen.
            _SyncBanner(notifier: notebookNotifier),
            Expanded(
              child: asyncList.when(
                data: (_) => _Body(
                  entries: notebooks,
                  sketches: sketches,
                  gridView: _gridView,
                  favoriteIds: settings.favoriteNotebookIds,
                  onOpen: _openNotebook,
                  onCreate: _createNotebook,
                  onCreateSketch: _createSketch,
                  onLongPress: _showNotebookMenu,
                  onToggleFavorite: _toggleFavorite,
                ),
                loading: () => _LoadingState(notifier: notebookNotifier),
                error: (e, _) => Center(
                    child: Text(
                        AppLocalizations.of(context)
                            .libErrorGeneric(e.toString()),
                        style: TextStyle(color: p.ink2))),
              ),
            ),
            _FooterBar(),
          ],
        ),
      ),
    );
  }

  List<NotebookEntry> _filterAndSort(
      List<NotebookEntry> all, AppSettings s, String query, String? folderId) {
    var list = query.isEmpty
        ? List<NotebookEntry>.from(all)
        : all
            .where((n) =>
                n.metadata.title.toLowerCase().contains(query.toLowerCase()))
            .toList();
    if (folderId != null) {
      list = list
          .where((n) => s.notebookFolderId[n.metadata.id] == folderId)
          .toList();
    }

    int compare(NotebookEntry a, NotebookEntry b) {
      switch (s.sortMode) {
        case LibrarySortMode.modifiedDesc:
          return b.metadata.modifiedAt.compareTo(a.metadata.modifiedAt);
        case LibrarySortMode.modifiedAsc:
          return a.metadata.modifiedAt.compareTo(b.metadata.modifiedAt);
        case LibrarySortMode.titleAsc:
          return a.metadata.title.compareTo(b.metadata.title);
        case LibrarySortMode.titleDesc:
          return b.metadata.title.compareTo(a.metadata.title);
        case LibrarySortMode.createdDesc:
          return b.metadata.createdAt.compareTo(a.metadata.createdAt);
        case LibrarySortMode.createdAsc:
          return a.metadata.createdAt.compareTo(b.metadata.createdAt);
        case LibrarySortMode.colorGroup:
          return a.metadata.coverColor.compareTo(b.metadata.coverColor);
      }
    }

    list.sort((a, b) {
      if (s.favoritesFirst) {
        final fa = s.favoriteNotebookIds.contains(a.metadata.id);
        final fb = s.favoriteNotebookIds.contains(b.metadata.id);
        if (fa != fb) return fa ? -1 : 1;
      }
      return compare(a, b);
    });
    return list;
  }

  Future<void> _openNotebook(NotebookEntry entry) async {
    ref.read(appSettingsProvider.notifier).markOpened(entry.metadata.id);
    try {
      await openNotebookAndNavigate(context, ref, entry);
      if (!mounted) return;
      ref.read(notebookListProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context).libErrorOpen(e.toString()))),
      );
    }
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const SettingsScreenV2(),
    ));
  }

  /// Entry point of the import flow: source chooser first, then the
  /// format-specific pipeline (.ncnote archive, Obsidian vault, Notion zip).
  Future<void> _importFlow() async {
    final type = await showImportSourceSheet(context);
    if (type == null || !mounted) return;
    switch (type) {
      case ImportSourceType.ncnote:
        await _importNcnote();
      case ImportSourceType.obsidianVault:
      case ImportSourceType.notionExport:
        await _importForeign(type);
      case ImportSourceType.onenote:
        await _importOneNote();
      case ImportSourceType.goodnotes:
        break; // not reachable from the sheet yet
    }
  }

  /// OneNote import (desktop-only, via the Rust FFI bridge). Freeform pages
  /// become infinite-canvas pages, sections become chapters.
  Future<void> _importOneNote() async {
    final l10n = AppLocalizations.of(context);
    final fileService = ref.read(fileServiceProvider);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['one', 'onetoc2'],
    );
    final path = result?.files.firstOrNull?.path;
    if (path == null) return;
    if (!mounted) return;

    final controller = ImportRunController();
    showImportProgressDialog(context, controller);
    final ctx = context;
    try {
      final parsed = await OneNoteImporter().parse(
        path,
        onProgress: controller.update,
        isCancelled: () => controller.cancelled,
      );
      if (controller.cancelled) {
        if (!mounted) return;
        // ignore: use_build_context_synchronously
        Navigator.of(ctx).pop();
        _toast(l10n.importCancelled);
        return;
      }

      final existingTitles =
          (ref.read(notebookListProvider).valueOrNull ?? const [])
              .map((e) => e.metadata.title.toLowerCase())
              .toSet();
      var title = parsed.title;
      if (existingTitles.contains(title.toLowerCase())) {
        title = l10n.libImportedTitleSuffix(title);
      }

      final report = await ImportService(fileService).importOneNote(
        parsed,
        resolvedTitle: title,
        onProgress: controller.update,
        isCancelled: () => controller.cancelled,
      );

      if (!mounted) return;
      // ignore: use_build_context_synchronously
      Navigator.of(ctx).pop();
      if (report == null) {
        _toast(l10n.importCancelled);
        return;
      }
      ref.read(notebookListProvider.notifier).refresh();
      _toast(l10n.libImportSuccess(report.notebookTitle, report.pageCount));
      if (report.issues.isNotEmpty && mounted) {
        // ignore: use_build_context_synchronously
        await showImportReportDialog(ctx, report);
      }
    } catch (e) {
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      Navigator.of(ctx).pop();
      _toast(l10n.libErrorImport(e.toString()));
    } finally {
      controller.dispose();
    }
  }

  /// Foreign-format import (Obsidian / Notion): pick the source, parse it to
  /// a draft, paginate and register. Cancellable at every stage; leaves no
  /// residue when cancelled before packaging.
  Future<void> _importForeign(ImportSourceType type) async {
    final l10n = AppLocalizations.of(context);
    final fileService = ref.read(fileServiceProvider);

    String? vaultPath;
    Uint8List? zipBytes;
    String zipName = '';
    if (type == ImportSourceType.obsidianVault) {
      vaultPath = await FilePicker.platform.getDirectoryPath();
      if (vaultPath == null) return;
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
      );
      final file = result?.files.firstOrNull;
      if (file == null) return;
      zipBytes = file.bytes ??
          (file.path != null
              ? await File(file.path!).readAsBytes()
              : null);
      if (zipBytes == null) {
        _toast(l10n.libImportCannotReadFile);
        return;
      }
      zipName = file.name;
    }
    if (!mounted) return;

    final controller = ImportRunController();
    showImportProgressDialog(context, controller);
    final ctx = context;
    try {
      final draft = type == ImportSourceType.obsidianVault
          ? await ObsidianImporter().parse(
              vaultPath!,
              onProgress: controller.update,
              isCancelled: () => controller.cancelled,
            )
          : await NotionImporter().parse(
              zipBytes!,
              exportName: zipName,
              onProgress: controller.update,
              isCancelled: () => controller.cancelled,
            );

      if (controller.cancelled) {
        if (!mounted) return;
        // ignore: use_build_context_synchronously
        Navigator.of(ctx).pop();
        _toast(l10n.importCancelled);
        return;
      }

      // Same title-collision policy as the .ncnote import.
      final existingTitles =
          (ref.read(notebookListProvider).valueOrNull ?? const [])
              .map((e) => e.metadata.title.toLowerCase())
              .toSet();
      var title = draft.title;
      if (existingTitles.contains(title.toLowerCase())) {
        title = l10n.libImportedTitleSuffix(title);
      }

      final report = await ImportService(fileService).importDraft(
        draft,
        resolvedTitle: title,
        onProgress: controller.update,
        isCancelled: () => controller.cancelled,
      );

      if (!mounted) return;
      // ignore: use_build_context_synchronously
      Navigator.of(ctx).pop(); // dismiss progress
      if (report == null) {
        _toast(l10n.importCancelled);
        return;
      }
      ref.read(notebookListProvider.notifier).refresh();
      _toast(l10n.libImportSuccess(report.notebookTitle, report.pageCount));
      if (report.issues.isNotEmpty && mounted) {
        // ignore: use_build_context_synchronously
        await showImportReportDialog(ctx, report);
      }
    } catch (e) {
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      Navigator.of(ctx).pop();
      _toast(l10n.libErrorImport(e.toString()));
    } finally {
      controller.dispose();
    }
  }

  /// Import a .ncnote archive from disk: validates, optionally renames on
  /// title collision, registers a new notebook and refreshes the library.
  Future<void> _importNcnote() async {
    final l10n = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ncnote', 'zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _toast(l10n.libImportCannotReadFile);
      return;
    }
    if (!mounted) return;

    // Show progress
    final ctx = context;
    showDialog(
      // ignore: use_build_context_synchronously
      context: ctx,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(l10n.libImportInProgress),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Validate ZIP integrity first
      SyncService.validateNcnoteArchive(bytes,
          context: 'import ${file.name}');

      final syncService = ref.read(syncServiceProvider);
      final fileService = ref.read(fileServiceProvider);
      if (syncService == null) {
        throw Exception(l10n.libServiceUnavailable);
      }

      // Parse to read metadata, document, pages, assets, symbols.
      // Contents come from a single ZIP walk (was 3 separate decodes).
      final parsed = syncService.parseNcnoteMetadata(bytes);
      final contents = syncService.extractNotebookContents(bytes);
      final pages = contents.pages;
      final assets = contents.assets;
      final symbols = contents.symbolLibraries;

      // Always assign a fresh ID so two devices/users importing the same
      // .ncnote don't end up sharing/colliding the notebook id (and so
      // the importer can keep their original alongside).
      final newId = const Uuid().v4();
      final originalTitle = parsed.metadata.title;
      // If a notebook with the same title already exists locally, mark
      // the import with a "(importato)" suffix so they're distinguishable
      // in the library list.
      final existingTitles = (ref.read(notebookListProvider).valueOrNull ?? const [])
          .map((e) => e.metadata.title.toLowerCase())
          .toSet();
      String newTitle = originalTitle;
      if (existingTitles.contains(originalTitle.toLowerCase())) {
        newTitle = l10n.libImportedTitleSuffix(originalTitle);
      }

      final newMeta = parsed.metadata.copyWith(
        id: newId,
        title: newTitle,
        modifiedAt: DateTime.now(),
      );

      // Re-pack with the new id/title and register via the shared importer
      // back-end (zip encode runs in an isolate; same path the foreign-format
      // importers use).
      await ImportService(fileService).registerNotebook(
        metadata: newMeta,
        document: parsed.document,
        pages: pages,
        assets: assets,
        symbolLibraries: symbols,
      );

      if (!mounted) return;
      // ignore: use_build_context_synchronously
      Navigator.of(ctx).pop(); // dismiss spinner
      ref.read(notebookListProvider.notifier).refresh();
      _toast(l10n.libImportSuccess(newTitle, pages.length));
    } catch (e) {
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      Navigator.of(ctx).pop();
      _toast(l10n.libErrorImport(e.toString()));
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _createNotebook() async {
    final res = await showDialog<_NewNotebookResult>(
      context: context,
      builder: (_) => const _NewNotebookDialog(),
    );
    if (res == null) return;
    try {
      final argb = (res.coverColor.a * 255).round() << 24 |
          (res.coverColor.r * 255).round() << 16 |
          (res.coverColor.g * 255).round() << 8 |
          (res.coverColor.b * 255).round();
      final entry =
          await ref.read(notebookListProvider.notifier).createNotebook(
                title: res.title,
                paperType: res.paperType,
                coverColor: argb,
                chapterTitle: AppLocalizations.of(context).nbDefaultChapterTitle,
              );
      if (mounted) _openNotebook(entry);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context).libErrorCreate(e.toString()))),
      );
    }
  }

  /// Create a free-sketch (infinite canvas) notebook and open it straight
  /// away — a quick-sketch flow with no dialog friction. Background/texture
  /// is picked later from the editor toolbar.
  Future<void> _createSketch() async {
    try {
      final entry =
          await ref.read(notebookListProvider.notifier).createNotebook(
                title: AppLocalizations.of(context).libSketchDefaultTitle,
                infinite: true,
                backgroundType: 'dotted',
                coverColor: HwTheme.cover4.toARGB32(),
                chapterTitle: AppLocalizations.of(context).nbDefaultChapterTitle,
              );
      if (mounted) _openNotebook(entry);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .libErrorCreateSketch(e.toString()))),
      );
    }
  }

  /// One-click favorite toggle from the cover star overlay. Avoids the
  /// long-press → bottom-sheet → tap → close round-trip for what is
  /// almost always the single most frequent library action.
  void _toggleFavorite(NotebookEntry entry) {
    HapticFeedback.selectionClick();
    ref.read(appSettingsProvider.notifier).toggleFavorite(entry.metadata.id);
  }

  Future<void> _showNotebookMenu(NotebookEntry entry) async {
    // Long-press is a hidden affordance; the bottom sheet feels more
    // intentional with a confirmatory haptic.
    HapticFeedback.lightImpact();
    final l10n = AppLocalizations.of(context);
    final settings = ref.read(appSettingsProvider);
    final isFav = settings.favoriteNotebookIds.contains(entry.metadata.id);

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final p = HwThemeScope.of(ctx);
        return Container(
          decoration: BoxDecoration(
            color: p.paper0,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.paper3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(entry.metadata.title,
                  style: TextStyle(
                      color: p.ink0,
                      fontWeight: FontWeight.w600,
                      fontSize: 16)),
              const SizedBox(height: 16),
              _menuItem(
                  ctx,
                  'star',
                  isFav
                      ? l10n.libRemoveFromFavorites
                      : l10n.libAddToFavorites,
                  'fav'),
              _menuItem(ctx, 'pen', l10n.libRename, 'rename'),
              _menuItem(ctx, 'palette', l10n.libChangeCover, 'cover'),
              _menuItem(ctx, 'folder', l10n.libMoveToFolder, 'move'),
              _menuItem(ctx, 'trash', l10n.libDelete, 'delete', danger: true),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    try {
      switch (action) {
        case 'fav':
          ref
              .read(appSettingsProvider.notifier)
              .toggleFavorite(entry.metadata.id);
          break;
        case 'rename':
          final t = await _renameDialog(entry.metadata.title);
          if (t != null && t.isNotEmpty) {
            await ref
                .read(notebookListProvider.notifier)
                .renameNotebook(entry, t);
          }
          break;
        case 'move':
          await _showMoveToFolderSheet(entry);
          break;
        case 'cover':
          final newColor = await _pickCoverColor(
              initial: Color(entry.metadata.coverColor));
          if (newColor != null) {
            final argb = (newColor.a * 255).round() << 24 |
                (newColor.r * 255).round() << 16 |
                (newColor.g * 255).round() << 8 |
                (newColor.b * 255).round();
            await ref
                .read(notebookListProvider.notifier)
                .updateNotebookCover(entry, argb);
          }
          break;
        case 'delete':
          final confirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(l10n.libDeleteNotebookTitle),
              content: Text(l10n.libDeleteNotebookBody),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l10n.libCancel)),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(l10n.libDelete)),
              ],
            ),
          );
          if (confirm == true) {
            await ref.read(notebookListProvider.notifier).deleteNotebook(entry);
          }
          break;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.libErrorGeneric(e.toString()))),
      );
    }
  }

  /// Folder membership is local-only (see [NotebookFolder]) — this just
  /// reassigns [AppSettings.notebookFolderId], no notebook file I/O.
  Future<void> _showMoveToFolderSheet(NotebookEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final settingsNotifier = ref.read(appSettingsProvider.notifier);
    final currentFolderId =
        ref.read(appSettingsProvider).notebookFolderId[entry.metadata.id];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          final folders = ref.watch(appSettingsProvider).folders;
          final p = HwThemeScope.of(ctx);
          return Container(
            decoration: BoxDecoration(
              color: p.paper0,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.paper3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(l10n.libMoveToFolder,
                    style: TextStyle(
                        color: p.ink0, fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () {
                    settingsNotifier.setNotebookFolder(entry.metadata.id, null);
                    Navigator.of(ctx).pop();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    child: Row(
                      children: [
                        HwIcon('folder', size: 18, color: p.ink1),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(l10n.libNoFolder,
                                style: TextStyle(color: p.ink0, fontSize: 14))),
                        if (currentFolderId == null)
                          HwIcon('check', size: 16, color: p.accent),
                      ],
                    ),
                  ),
                ),
                for (final folder in folders)
                  InkWell(
                    onTap: () {
                      settingsNotifier.setNotebookFolder(
                          entry.metadata.id, folder.id);
                      Navigator.of(ctx).pop();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                      child: Row(
                        children: [
                          HwIcon('folder', size: 18, color: p.ink1),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(folder.name,
                                  style:
                                      TextStyle(color: p.ink0, fontSize: 14))),
                          if (currentFolderId == folder.id)
                            HwIcon('check', size: 16, color: p.accent),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () async {
                    final name = await _newFolderDialog(ctx);
                    if (name != null && name.isNotEmpty) {
                      settingsNotifier.createFolder(name);
                      setSheetState(() {});
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    child: Row(
                      children: [
                        HwIcon('plus', size: 18, color: p.ink1),
                        const SizedBox(width: 12),
                        Text(l10n.libNewFolder,
                            style: TextStyle(color: p.ink0, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<String?> _newFolderDialog(BuildContext ctx, {String? initial}) async {
    final l10n = AppLocalizations.of(ctx);
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(initial == null ? l10n.libNewFolder : l10n.libRenameFolder),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.libFolderNameHint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, null),
              child: Text(l10n.libCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()),
              child: Text(
                  initial == null ? l10n.libCreate : l10n.libSave)),
        ],
      ),
    );
  }

  Widget _menuItem(BuildContext ctx, String icon, String label, String action,
      {bool danger = false}) {
    final p = HwThemeScope.of(ctx);
    return InkWell(
      onTap: () => Navigator.of(ctx).pop(action),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: [
            HwIcon(icon,
                size: 18, color: danger ? HwTheme.syncConflict : p.ink1),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: danger ? HwTheme.syncConflict : p.ink0,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet to pick one of the 8 preset cover colours.
  Future<Color?> _pickCoverColor({Color? initial}) async {
    return showModalBottomSheet<Color>(
      context: context,
      backgroundColor: HwThemeScope.of(context).paper0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context).libChangeCover,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in HwTheme.covers)
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(c),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(8),
                          border: initial?.toARGB32() == c.toARGB32()
                              ? Border.all(
                                  color:
                                      HwThemeScope.of(context).ink0,
                                  width: 2)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _renameDialog(String old) async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: old);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.libRenameNotebookTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.libCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: Text(l10n.libSave)),
        ],
      ),
    );
  }

  Future<void> _showSortSheet() async {
    final l10n = AppLocalizations.of(context);
    final current = ref.read(appSettingsProvider).sortMode;
    final p = HwThemeScope.of(context);
    try {
      final picked = await showModalBottomSheet<LibrarySortMode>(
        context: context,
        backgroundColor: p.paper0,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Text(l10n.libSortTitle,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.ink0)),
                const SizedBox(height: 8),
                for (final m in LibrarySortMode.values)
                  ListTile(
                    leading: Icon(m.icon, size: 18, color: p.ink2),
                    title: Text(m.labelOf(l10n),
                        style: TextStyle(color: p.ink0, fontSize: 14)),
                    trailing: m == current
                        ? HwIcon('check', size: 16, color: p.accent)
                        : null,
                    onTap: () => Navigator.of(ctx).pop(m),
                  ),
              ],
            ),
          );
        },
      );
      if (!mounted) return;
      if (picked != null) {
        ref.read(appSettingsProvider.notifier).setSortMode(picked);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.libErrorGeneric(e.toString()))),
      );
    }
  }
}

// ─── Folder filter chips ─────────────────────────────────────────
/// Horizontal scroller: "Tutti" + one chip per user folder. Long-press a
/// folder chip for rename/delete — "Tutti" has no such affordance since it
/// isn't a real folder.
class _FolderChipRow extends StatelessWidget {
  final List<NotebookFolder> folders;
  final String? selectedFolderId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<NotebookFolder> onRename;
  final ValueChanged<NotebookFolder> onDelete;

  const _FolderChipRow({
    required this.folders,
    required this.selectedFolderId,
    required this.onSelect,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          _chip(context, label: l10n.libAllNotebooks, selected: selectedFolderId == null,
              onTap: () => onSelect(null)),
          for (final folder in folders)
            GestureDetector(
              onLongPress: () => _showFolderChipMenu(context, folder),
              onSecondaryTap: () => _showFolderChipMenu(context, folder),
              child: _chip(context,
                  label: folder.name,
                  selected: selectedFolderId == folder.id,
                  onTap: () => onSelect(folder.id)),
            ),
          _iconChip(context, icon: Icons.add_rounded, onTap: onCreate),
        ],
      ),
    );
  }

  Widget _iconChip(BuildContext context,
      {required IconData icon, required VoidCallback onTap}) {
    final p = HwThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: p.paper0,
            shape: BoxShape.circle,
            border: Border.all(color: p.paper3),
          ),
          child: Icon(icon, size: 18, color: p.ink1),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context,
      {required String label, required bool selected, required VoidCallback onTap}) {
    final p = HwThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? p.accentSoft : p.paper0,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? p.accent : p.paper3),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? p.ink0 : p.ink1,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              )),
        ),
      ),
    );
  }

  Future<void> _showFolderChipMenu(BuildContext context, NotebookFolder folder) async {
    final l10n = AppLocalizations.of(context);
    final p = HwThemeScope.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: p.paper0,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration:
                    BoxDecoration(color: p.paper3, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => Navigator.of(ctx).pop('rename'),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                child: Row(children: [
                  HwIcon('pen', size: 18, color: p.ink1),
                  const SizedBox(width: 12),
                  Text(l10n.libRenameFolder, style: TextStyle(color: p.ink0, fontSize: 14)),
                ]),
              ),
            ),
            InkWell(
              onTap: () => Navigator.of(ctx).pop('delete'),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                child: Row(children: [
                  HwIcon('trash', size: 18, color: HwTheme.syncConflict),
                  const SizedBox(width: 12),
                  Text(l10n.libDeleteFolder,
                      style: TextStyle(color: HwTheme.syncConflict, fontSize: 14)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
    if (action == 'rename') onRename(folder);
    if (action == 'delete') onDelete(folder);
  }
}

// ─── Top bar ─────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool gridView;
  final ValueChanged<bool> onViewToggle;
  final VoidCallback onSortTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onImportTap;
  final String sortLabel;

  const _TopBar({
    required this.searchController,
    required this.onSearchChanged,
    required this.gridView,
    required this.onViewToggle,
    required this.onSortTap,
    required this.onSettingsTap,
    required this.onImportTap,
    required this.sortLabel,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(builder: (ctx, c) {
      final isCompact = c.maxWidth < 720;
      final hPad = isCompact ? 16.0 : 32.0;
      return Container(
        padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 14),
        decoration: BoxDecoration(
          color: p.paper0,
          border: Border(bottom: BorderSide(color: p.paper3)),
        ),
        child: Row(
          children: [
            Text(l10n.libAppName,
                style: TextStyle(
                  fontSize: isCompact ? 18 : 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: p.ink0,
                )),
            const Spacer(),
            // Search field — full width on phone, fixed 240 on wide.
            if (isCompact)
              Expanded(
                child: HwTextField(
                  controller: searchController,
                  hint: l10n.libSearchHintShort,
                  leading: const HwIcon('search', size: 16),
                  onChanged: onSearchChanged,
                  width: double.infinity,
                ),
              )
            else
              HwTextField(
                controller: searchController,
                hint: l10n.libSearchHintNotebooks,
                leading: const HwIcon('search', size: 16),
                onChanged: onSearchChanged,
                width: 240,
              ),
            const SizedBox(width: 8),
            // Wide-only: view toggle, sort label, divider, big "Importa".
            if (!isCompact) ...[
              const HwDivider(),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: p.paper2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  _SegBtn(
                      icon: 'grid',
                      selected: gridView,
                      onTap: () => onViewToggle(true)),
                  _SegBtn(
                      icon: 'list',
                      selected: !gridView,
                      onTap: () => onViewToggle(false)),
                ]),
              ),
              const SizedBox(width: 12),
              HwButton(
                leading: const HwIcon('sort', size: 16),
                label: sortLabel,
                onPressed: onSortTap,
              ),
              const SizedBox(width: 12),
              const HwDivider(),
              const SizedBox(width: 12),
              HwButton(
                leading: const HwIcon('export', size: 16),
                label: l10n.libImport,
                tooltip: l10n.libImportTooltip,
                onPressed: onImportTap,
              ),
              const SizedBox(width: 4),
              HwButton.icon(
                  icon: const HwIcon('settings', size: 16),
                  tooltip: l10n.libSettingsTooltip,
                  onPressed: onSettingsTap),
            ] else ...[
              // Compact: collapse view toggle / sort / import / settings
              // into a single overflow menu. Saves ~360px of bar width.
              HwButton.icon(
                icon: const HwIcon('more', size: 16),
                tooltip: l10n.libMoreTooltip,
                onPressed: () => _compactMenu(ctx),
              ),
            ],
          ],
        ),
      );
    });
  }

  Future<void> _compactMenu(BuildContext context) async {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await showModalBottomSheet<void>(
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
            ListTile(
              leading: HwIcon(gridView ? 'list' : 'grid', size: 18),
              title: Text(gridView ? l10n.libViewAsList : l10n.libViewAsGrid),
              onTap: () {
                Navigator.of(ctx).pop();
                onViewToggle(!gridView);
              },
            ),
            ListTile(
              leading: const HwIcon('sort', size: 18),
              title: Text(l10n.libSortWithLabel(sortLabel)),
              onTap: () {
                Navigator.of(ctx).pop();
                onSortTap();
              },
            ),
            const Divider(),
            ListTile(
              leading: const HwIcon('export', size: 18),
              title: Text(l10n.libImportNcnoteMenu),
              onTap: () {
                Navigator.of(ctx).pop();
                onImportTap();
              },
            ),
            ListTile(
              leading: const HwIcon('settings', size: 18),
              title: Text(l10n.libSettingsTooltip),
              onTap: () {
                Navigator.of(ctx).pop();
                onSettingsTap();
              },
            ),
          ],
        ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.libErrorGeneric(e.toString()))),
      );
    }
  }
}

class _SegBtn extends StatelessWidget {
  final String icon;
  final bool selected;
  final VoidCallback onTap;
  const _SegBtn(
      {required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? p.paper0 : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: selected ? hwShadow1(p.brightness) : null,
          ),
          child: HwIcon(icon, size: 16, color: selected ? p.ink0 : p.ink2),
        ),
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────
class _Body extends StatelessWidget {
  final List<NotebookEntry> entries;
  final List<NotebookEntry> sketches;
  final bool gridView;
  final Set<String> favoriteIds;
  final ValueChanged<NotebookEntry> onOpen;
  final VoidCallback onCreate;
  final VoidCallback onCreateSketch;
  final ValueChanged<NotebookEntry> onLongPress;
  final ValueChanged<NotebookEntry> onToggleFavorite;

  const _Body({
    required this.entries,
    required this.sketches,
    required this.gridView,
    required this.favoriteIds,
    required this.onOpen,
    required this.onCreate,
    required this.onCreateSketch,
    required this.onLongPress,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _SketchSection(
            sketches: sketches,
            onCreateSketch: onCreateSketch,
            onOpen: onOpen,
            onLongPress: onLongPress,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(AppLocalizations.of(context).libYourNotebooks,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: p.ink0,
                    )),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(context).libItemsCount(entries.length),
                    style: TextStyle(fontSize: 13, color: p.ink2)),
                const Spacer(),
                HwButton(
                  leading: const HwIcon('plus', size: 16),
                  label: AppLocalizations.of(context).libNewNotebook,
                  style: HwButtonStyle.primary,
                  onPressed: onCreate,
                ),
              ],
            ),
          ),
        ),
        if (gridView)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            sliver: SliverLayoutBuilder(
              builder: (ctx, constraints) {
                // Adapt cover-tile sizing to the available width so the
                // grid doesn't stay locked to tablet proportions on phones
                // or waste space on very wide desktops.
                final width = constraints.crossAxisExtent;
                final double maxExtent, mainExtent;
                if (width < 480) {
                  maxExtent = 160;
                  mainExtent = 260;
                } else if (width > 1100) {
                  maxExtent = 280;
                  mainExtent = 340;
                } else {
                  maxExtent = 232;
                  mainExtent = 320;
                }
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: maxExtent,
                    mainAxisExtent: mainExtent,
                    crossAxisSpacing: 32,
                    mainAxisSpacing: 40,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      if (i == 0) return _NewTile(onTap: onCreate);
                      final e = entries[i - 1];
                      return _CoverTile(
                        entry: e,
                        favorite: favoriteIds.contains(e.metadata.id),
                        onTap: () => onOpen(e),
                        onLongPress: () => onLongPress(e),
                        onToggleFavorite: () => onToggleFavorite(e),
                      );
                    },
                    childCount: entries.length + 1,
                  ),
                );
              },
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            sliver: SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (_, i) => _ListRow(
                entry: entries[i],
                favorite: favoriteIds.contains(entries[i].metadata.id),
                onTap: () => onOpen(entries[i]),
                onLongPress: () => onLongPress(entries[i]),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}

// ─── Sketch (infinite canvas) section ─────────────────────────────
class _SketchSection extends StatelessWidget {
  final List<NotebookEntry> sketches;
  final VoidCallback onCreateSketch;
  final ValueChanged<NotebookEntry> onOpen;
  final ValueChanged<NotebookEntry> onLongPress;
  const _SketchSection({
    required this.sketches,
    required this.onCreateSketch,
    required this.onOpen,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(AppLocalizations.of(context).libSketches,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: p.ink0,
                  )),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(context).libInfiniteSpace,
                  style: TextStyle(fontSize: 13, color: p.ink2)),
              const Spacer(),
              HwButton(
                leading: const HwIcon('plus', size: 16),
                label: AppLocalizations.of(context).libNewSketch,
                style: HwButtonStyle.primary,
                onPressed: onCreateSketch,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 128,
            child: sketches.isEmpty
                ? _SketchEmptyTile(onTap: onCreateSketch)
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: sketches.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (_, i) => _SketchTile(
                      entry: sketches[i],
                      onTap: () => onOpen(sketches[i]),
                      onLongPress: () => onLongPress(sketches[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SketchTile extends StatelessWidget {
  final NotebookEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _SketchTile({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return SizedBox(
      width: 220,
      child: Material(
        color: p.paper0,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          // Desktop affordance: right click = long-press actions menu.
          onSecondaryTap: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.paper3),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CustomPaint(
                      painter: _SketchDotsPainter(p.paperEdge),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(entry.metadata.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: p.ink0,
                    )),
                const SizedBox(height: 1),
                Text(
                    _relativeTime(AppLocalizations.of(context),
                        entry.metadata.modifiedAt),
                    style: TextStyle(fontSize: 11, color: p.ink2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SketchEmptyTile extends StatelessWidget {
  final VoidCallback onTap;
  const _SketchEmptyTile({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return SizedBox(
      width: 220,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: DottedBorderBox(
            color: p.paperEdge,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HwIcon('plus', size: 22, color: p.ink2),
                  const SizedBox(height: 6),
                  Text(AppLocalizations.of(context).libInfiniteCanvas,
                      style: TextStyle(
                          fontSize: 12,
                          color: p.ink2,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny dot-grid preview painted on a sketch tile — echoes the infinite
/// dotted canvas the tile opens into.
class _SketchDotsPainter extends CustomPainter {
  final Color color;
  _SketchDotsPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0;
    const spacing = 16.0;
    final pts = <Offset>[];
    for (double y = spacing / 2; y < size.height; y += spacing) {
      for (double x = spacing / 2; x < size.width; x += spacing) {
        pts.add(Offset(x, y));
      }
    }
    if (pts.isNotEmpty) {
      canvas.drawPoints(ui.PointMode.points, pts, dot);
    }
  }

  @override
  bool shouldRepaint(_SketchDotsPainter old) => old.color != color;
}

class _NewTile extends StatelessWidget {
  final VoidCallback onTap;
  const _NewTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 200,
          height: 260,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                bottomLeft: Radius.circular(4),
                topRight: Radius.circular(10),
                bottomRight: Radius.circular(10),
              ),
              child: DottedBorderBox(
                color: p.paperEdge,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    HwIcon('plus', size: 28, color: p.ink2),
                    const SizedBox(height: 8),
                    Text(AppLocalizations.of(context).libNew,
                        style: TextStyle(
                            fontSize: 13,
                            color: p.ink2,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DottedBorderBox extends StatelessWidget {
  final Color color;
  final Widget child;
  const DottedBorderBox({super.key, required this.color, required this.child});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DottedBorderPainter(color),
      child: child,
    );
  }
}

class _DottedBorderPainter extends CustomPainter {
  final Color color;
  _DottedBorderPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final r = const BorderRadius.only(
      topLeft: Radius.circular(4),
      bottomLeft: Radius.circular(4),
      topRight: Radius.circular(10),
      bottomRight: Radius.circular(10),
    ).toRRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(r);
    final metric = path.computeMetrics().first;
    const dash = 6.0, gap = 5.0;
    var dist = 0.0;
    while (dist < metric.length) {
      final next = (dist + dash).clamp(0, metric.length).toDouble();
      canvas.drawPath(metric.extractPath(dist, next), paint);
      dist += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DottedBorderPainter old) => old.color != color;
}

class _CoverTile extends StatelessWidget {
  final NotebookEntry entry;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleFavorite;
  const _CoverTile({
    required this.entry,
    required this.favorite,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Star overlay sits ABOVE the cover via Stack so its tap can be
        // intercepted before NotebookCover's onTap fires (the cover-wide
        // InkWell would otherwise swallow it). One-tap favorite was a
        // three-tap action via the long-press sheet pre-fix.
        SizedBox(
          width: 200,
          height: 260,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onLongPress: onLongPress,
                  // Desktop affordance: right click opens the same actions
                  // menu as long-press.
                  onSecondaryTap: onLongPress,
                  behavior: HitTestBehavior.translucent,
                  child: NotebookCover(
                    color: Color(entry.metadata.coverColor),
                    title: entry.metadata.title,
                    // Hide the cover's built-in star — we render our own
                    // tappable one above.
                    favorite: false,
                    texture: _textureFor(entry.metadata.paperType),
                    width: 200,
                    height: 260,
                    onTap: onTap,
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onToggleFavorite,
                    customBorder: const CircleBorder(),
                    child: Tooltip(
                      message: favorite
                          ? AppLocalizations.of(context).libRemoveFromFavorites
                          : AppLocalizations.of(context).libAddToFavorites,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: HwIcon(
                          favorite ? 'star-filled' : 'star',
                          size: 18,
                          color: favorite
                              ? HwTheme.favoriteGold
                              : p.paper0.withValues(alpha: 0.80),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 200,
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.metadata.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: p.ink0,
                    )),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                        AppLocalizations.of(context)
                            .libPagesAbbrev(entry.metadata.pageCount),
                        style: TextStyle(fontSize: 12, color: p.ink2)),
                    Text(' · ',
                        style: TextStyle(fontSize: 12, color: p.ink3)),
                    Expanded(
                      child: Text(
                        _relativeTime(AppLocalizations.of(context),
                            entry.metadata.modifiedAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.ink2),
                      ),
                    ),
                    SyncBadge(state: _syncStateOf(entry)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ListRow extends StatelessWidget {
  final NotebookEntry entry;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _ListRow({
    required this.entry,
    required this.favorite,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        // Desktop affordance: right click = long-press actions menu.
        onSecondaryTap: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 42,
                decoration: BoxDecoration(
                  color: Color(entry.metadata.coverColor),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2),
                    bottomLeft: Radius.circular(2),
                    topRight: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                  boxShadow: hwShadow1(p.brightness),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.metadata.title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: p.ink0)),
                    Text(
                        AppLocalizations.of(context)
                            .libPagesCount(entry.metadata.pageCount),
                        style: TextStyle(fontSize: 12, color: p.ink2)),
                  ],
                ),
              ),
              SizedBox(
                width: 120,
                child: Text(
                    _relativeTime(AppLocalizations.of(context),
                        entry.metadata.modifiedAt),
                    style: TextStyle(fontSize: 12, color: p.ink2)),
              ),
              SyncBadge(state: _syncStateOf(entry)),
              if (favorite) ...[
                const SizedBox(width: 8),
                HwIcon('star-filled', size: 14, color: p.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      decoration: BoxDecoration(
        color: p.paper0,
        border: Border(top: BorderSide(color: p.paper3)),
      ),
      child: Row(
        children: [
          HwIcon('cloud-check', size: 14, color: p.ink2),
          const SizedBox(width: 6),
          Text(AppLocalizations.of(context).libFooterWebdav,
              style: TextStyle(fontSize: 13, color: p.ink2)),
          const Spacer(),
          Text(AppLocalizations.of(context).libFooterLocalFirst,
              style: TextStyle(fontSize: 13, color: p.ink2)),
        ],
      ),
    );
  }
}

/// Slim progress banner shown while a background sync with the server is
/// running. Returns [SizedBox.shrink] when idle so it costs no layout space.
class _SyncBanner extends StatelessWidget {
  final NotebookListNotifier notifier;
  const _SyncBanner({required this.notifier});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: notifier.isSyncing,
      builder: (_, syncing, __) {
        if (!syncing) return const SizedBox.shrink();
        return Material(
          color: p.paper2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
            child: ValueListenableBuilder<({int done, int total})>(
              valueListenable: notifier.syncProgress,
              builder: (_, progress, __) {
                final l10n = AppLocalizations.of(context);
                final label = progress.total == 0
                    ? l10n.libSyncingWithServer
                    : l10n.libDownloadingProgress(
                        progress.done, progress.total);
                return Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: progress.total == 0
                            ? null
                            : progress.done / progress.total,
                        color: p.ink0,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(fontSize: 13, color: p.ink1),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Loading view shown while [notebookListProvider] is still in
/// `AsyncValue.loading` (i.e. before the very first `_loadFromLocalDb`
/// returns). On a fresh install this is the brief window between app boot
/// and the DB-read completing; afterwards the body itself takes over with
/// the [_SyncBanner] above. If sync is already in flight (rare but possible
/// on fast SSDs where DB read races sync kickoff), show progress text so
/// the user sees the work happening immediately.
class _LoadingState extends StatelessWidget {
  final NotebookListNotifier notifier;
  const _LoadingState({required this.notifier});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: notifier.isSyncing,
      builder: (_, syncing, __) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<({int done, int total})>(
                valueListenable: notifier.syncProgress,
                builder: (_, progress, __) {
                  return SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      value: progress.total == 0
                          ? null
                          : progress.done / progress.total,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<({int done, int total})>(
                valueListenable: notifier.syncProgress,
                builder: (_, progress, __) {
                  final l10n = AppLocalizations.of(context);
                  final label = !syncing
                      ? l10n.libLoadingNotebooks
                      : progress.total == 0
                          ? l10n.libLoadingNotebooksFromServer
                          : l10n.libDownloadingProgress(
                              progress.done, progress.total);
                  return Text(label, style: TextStyle(color: p.ink2));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────
HwSyncState _syncStateOf(NotebookEntry e) {
  if (e.isLocal) return HwSyncState.pending;
  return HwSyncState.ok;
}

BackgroundTexture _textureFor(String paperType) {
  switch (paperType) {
    case 'lined':
    case 'lined_narrow':
    case 'lined_wide':
      return BackgroundTexture.lines;
    case 'grid':
      return BackgroundTexture.grid;
    case 'dotted':
      return BackgroundTexture.dots;
    case 'cornell':
      return BackgroundTexture.cornell;
    default:
      return BackgroundTexture.blank;
  }
}

String _relativeTime(AppLocalizations l10n, DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return l10n.libTimeNow;
  if (diff.inHours < 1) return l10n.libTimeMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.libTimeHoursAgo(diff.inHours);
  if (diff.inDays < 7) return l10n.libTimeDaysAgo(diff.inDays);
  if (diff.inDays < 30) return l10n.libTimeWeeksAgo((diff.inDays / 7).floor());
  if (diff.inDays < 365) {
    return l10n.libTimeMonthsAgo((diff.inDays / 30).floor());
  }
  return l10n.libTimeYearsAgo((diff.inDays / 365).floor());
}

// ─── New notebook dialog ──────────────────────────────────────────
class _NewNotebookResult {
  final String title;
  final Color coverColor;
  final String paperType;
  _NewNotebookResult(this.title, this.coverColor, this.paperType);
}

class _NewNotebookDialog extends StatefulWidget {
  const _NewNotebookDialog();
  @override
  State<_NewNotebookDialog> createState() => _NewNotebookDialogState();
}

class _NewNotebookDialogState extends State<_NewNotebookDialog> {
  final _titleCtrl = TextEditingController();
  Color _color = HwTheme.cover1;
  String _paper = 'lined';

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: p.paper0,
      title: Text(l10n.libNewNotebook),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.libNotebookTitleLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text(l10n.libCoverLabel,
                style: TextStyle(
                    fontSize: 11,
                    color: p.ink2,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: HwTheme.covers
                  .map((c) => GestureDetector(
                        onTap: () => setState(() => _color = c),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(6),
                            border: _color == c
                                ? Border.all(color: p.ink0, width: 2)
                                : null,
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            Text(l10n.libPaperLabel,
                style: TextStyle(
                    fontSize: 11,
                    color: p.ink2,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                _paperChip(l10n.libPaperBlank, 'blank'),
                _paperChip(l10n.libPaperLined, 'lined'),
                _paperChip(l10n.libPaperGrid, 'grid'),
                _paperChip(l10n.libPaperDotted, 'dotted'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.libCancel),
        ),
        FilledButton(
          onPressed: () {
            final t = _titleCtrl.text.trim();
            if (t.isEmpty) return;
            Navigator.of(context).pop(_NewNotebookResult(t, _color, _paper));
          },
          child: Text(l10n.libCreate),
        ),
      ],
    );
  }

  Widget _paperChip(String label, String type) {
    final p = HwThemeScope.of(context);
    final selected = _paper == type;
    return GestureDetector(
      onTap: () => setState(() => _paper = type),
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
    );
  }
}
