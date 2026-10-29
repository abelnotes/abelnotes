import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/app_mode_provider.dart';
import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/providers/remote_store_provider.dart';
import 'package:abelnotes/core/providers/auth_provider.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/file_open_receiver.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/core/services/sync_thrift.dart';
import 'package:abelnotes/core/platform/io.dart';

import 'package:abelnotes/features/auth/login_screen.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/import_service.dart';
import 'package:abelnotes/features/import/data/notion_importer.dart';
import 'package:abelnotes/features/import/data/obsidian_importer.dart';
import 'package:abelnotes/features/import/data/onenote_importer.dart';
import 'package:abelnotes/features/import/presentation/import_messages.dart';
import 'package:abelnotes/features/import/presentation/import_progress_dialog.dart';
import 'package:abelnotes/features/import/presentation/import_report_dialog.dart';
import 'package:abelnotes/features/import/presentation/import_source_sheet.dart';
import 'package:abelnotes/features/sync/sync_notices.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/screens/settings_screen.dart';
import 'package:abelnotes/ui/screens/trash_screen.dart';
import 'package:abelnotes/shared/utils/relative_time.dart';
import 'package:abelnotes/shared/utils/text_fold.dart';
import 'package:abelnotes/ui/services/file_export.dart';
import 'package:abelnotes/ui/services/notebook_opener.dart';
import 'package:abelnotes/ui/primitives/page_size_picker.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/features/pages_tray/application/pages_tray_provider.dart';
import 'package:abelnotes/features/pages_tray/domain/pages_tray.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';
import 'package:abelnotes/ui/primitives/hw_button.dart';
import 'package:abelnotes/ui/primitives/hw_glass.dart';
import 'package:abelnotes/ui/primitives/hw_motion_widgets.dart';
import 'package:abelnotes/ui/primitives/scrollable_sheet.dart';
import 'package:abelnotes/ui/primitives/sync_badge.dart';
import 'package:uuid/uuid.dart';

/// HandWriter library screen, "warm paper" redesign.
class LibraryScreenV2 extends ConsumerStatefulWidget {
  const LibraryScreenV2({super.key});

  @override
  ConsumerState<LibraryScreenV2> createState() => _LibraryScreenV2State();
}

class _LibraryScreenV2State extends ConsumerState<LibraryScreenV2>
    with WidgetsBindingObserver {
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  Timer? _bgSyncTimer;
  String? _selectedFolderId;

  /// How often the library re-syncs while it's the visible route; the slow
  /// one applies on metered data or battery saver.
  static const _bgSyncInterval = Duration(seconds: 60);
  static const _bgSyncThriftyInterval = Duration(minutes: 5);
  bool _bgSyncInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      ref.read(notebookListProvider.notifier).loadDeletedElsewhere();
      ref.read(notebookListProvider.notifier).refresh();
      // A cold start opened via file association already has its request
      // queued; ref.listen only reports later changes.
      _consumePendingFileOpen();
      // Best-effort retry of pending uploads on cold boot.
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      try {
        await ref.read(notebookListProvider.notifier).retryPendingUploads();
      } catch (_) {}
    });
    // Periodic re-sync. `_bgSyncTimer` existed but was never started, so the
    // library only ever synced at cold boot: notebooks another device created
    // stayed invisible, and an upload that failed while the network was down
    // sat pending until the app was restarted.
    _scheduleBackgroundSync();
  }

  void _scheduleBackgroundSync() {
    _bgSyncTimer?.cancel();
    final interval =
        SyncThrift.thrifty ? _bgSyncThriftyInterval : _bgSyncInterval;
    _bgSyncTimer = Timer(interval, () async {
      await SyncThrift.refresh();
      await _backgroundSync();
      if (mounted && _bgSyncTimer != null) _scheduleBackgroundSync();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No polling from the background; catch up the moment the app is back.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _bgSyncTimer?.cancel();
      _bgSyncTimer = null;
    } else if (state == AppLifecycleState.resumed && _bgSyncTimer == null) {
      _scheduleBackgroundSync();
      unawaited(_backgroundSync());
    }
  }

  /// One background sync tick. Skipped while a notebook is open (this screen
  /// stays mounted underneath the canvas route — syncing under the user's
  /// editing session is the canvas pull timer's job, not ours) and while
  /// local-only, where every server probe would just throw.
  Future<void> _backgroundSync() async {
    if (!mounted || _bgSyncInFlight) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (ref.read(remoteStoreProvider) == null) return;
    final notifier = ref.read(notebookListProvider.notifier);
    if (notifier.isSyncing.value) return; // a visible sync is already running
    _bgSyncInFlight = true;
    try {
      await notifier.refresh(showProgress: false);
      if (!mounted) return;
      await notifier.retryPendingUploads();
    } catch (e) {
      debugPrint('[Library] Background sync failed: $e');
    } finally {
      _bgSyncInFlight = false;
    }
  }

  /// Mirrors the cold-start sequence for a server connected mid-session:
  /// pull what's on the server, then push the local-only notebooks up.
  Future<void> _onServerConnected() async {
    final notifier = ref.read(notebookListProvider.notifier);
    await notifier.refresh();
    if (!mounted) return;
    try {
      await notifier.retryPendingUploads();
    } catch (_) {}
    if (!mounted) return;
    // The uploads flip sync_status/etag rows — reload so the cards drop
    // their "local only" badge without waiting for the next refresh.
    await notifier.refresh();
  }

  /// Runs a pending OS open request, if any, and clears it so a rebuild
  /// doesn't import the same notebook twice.
  void _consumePendingFileOpen() {
    if (!mounted) return;
    final pending = ref.read(fileOpenReceiverProvider);
    if (pending == null) return;
    ref.read(fileOpenReceiverProvider.notifier).consume();
    _openNcnotePath(pending.path);
  }

  /// Opens the notebook a tray action asked for (the editor takes it up from
  /// there and shows its Pages). Ignored while the editor is on top: it
  /// answers the request itself.
  Future<void> _consumeTrayNav(TrayNavRequest req) async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final list = ref.read(notebookListProvider).valueOrNull ?? const [];
    final entry =
        list.where((e) => e.metadata.id == req.notebookId).firstOrNull;
    if (entry == null) {
      ref.read(pagesTrayNavProvider.notifier).state = null;
      return;
    }
    if (req.landing.isNotEmpty) {
      ref.read(pagesTrayProvider.notifier).landPages(req.landing);
    }
    await _openNotebook(entry);
    if (mounted && ref.read(pagesTrayNavProvider) == req) {
      ref.read(pagesTrayNavProvider.notifier).state = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bgSyncTimer?.cancel();
    _bgSyncTimer = null;
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<NextcloudCredentials?>(credentialsProvider, (prev, next) {
      if (prev != null || next == null) return;
      unawaited(_onServerConnected());
    });
    final p = HwThemeScope.of(context);
    final settings = ref.watch(appSettingsProvider);
    final asyncList = ref.watch(notebookListProvider);

    // A .ncnote double-click while the app is already running.
    ref.listen<PendingFileOpen?>(fileOpenReceiverProvider, (_, next) {
      if (next != null) _consumePendingFileOpen();
    });

    ref.listen<TrayNavRequest?>(pagesTrayNavProvider, (_, next) {
      if (next != null) _consumeTrayNav(next);
    });
    final tray = ref.watch(pagesTrayProvider.select((s) => s.tray));

    // The selected folder may have been deleted on another device.
    if (_selectedFolderId != null &&
        !settings.folders.any((f) => f.id == _selectedFolderId)) {
      _selectedFolderId = null;
    }
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
    final l10n = AppLocalizations.of(context);
    final folderName = settings.folders
            .where((f) => f.id == _selectedFolderId)
            .map((f) => f.name)
            .firstOrNull ??
        l10n.libAllNotebooks;
    return Scaffold(
      backgroundColor: p.paper1,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          // Wide windows get a sidebar; phones keep the folder chip row.
          final wide = c.maxWidth >= 900;
          final headerSlivers = <Widget>[
            SliverToBoxAdapter(
              child: _LargeTitle(
                title: folderName,
                subtitle: l10n.libItemsCount(notebooks.length),
                scroll: _scroll,
                hPad: wide ? 32 : 16,
              ),
            ),
            if (tray != null)
              SliverToBoxAdapter(
                child: _TrayHint(tray: tray, hPad: wide ? 32 : 16),
              ),
            if (!wide)
              SliverToBoxAdapter(
                child: _FolderChipRow(
                  folders: settings.folders,
                  selectedFolderId: _selectedFolderId,
                  onSelect: (id) => setState(() => _selectedFolderId = id),
                  onCreate: _createFolder,
                  onRename: _renameFolder,
                  onDelete: _deleteFolder,
                ),
              ),
            // Sync and storage notices; each collapses to nothing when idle.
            SliverToBoxAdapter(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _SyncBanner(notifier: notebookNotifier),
                const _LocalOnlyNotice(),
                const DeletedElsewhereNotice(),
                _StorageFullNotice(notifier: notebookNotifier),
                _ServerUnreachableNotice(notifier: notebookNotifier),
                _PendingUploadsNotice(entries: notebooks),
                _PendingRemoteDeletesNotice(notifier: notebookNotifier),
              ]),
            ),
          ];
          final body = asyncList.when(
            data: (_) => _Body(
              controller: _scroll,
              headerSlivers: headerSlivers,
              hPad: wide ? 32 : 16,
              entries: notebooks,
              sketches: sketches,
              gridView: settings.libraryGridView,
              searchQuery: _query.trim(),
              favoriteIds: settings.favoriteNotebookIds,
              onOpen: _openNotebook,
              onCreate: _createNotebook,
              onCreateSketch: _createSketch,
              onLongPress: _showNotebookMenu,
              onToggleFavorite: _toggleFavorite,
              movingFromId: tray != null && tray.isMove ? tray.sourceNotebookId : null,
              movingCount: tray?.count ?? 0,
            ),
            loading: () => Padding(
              padding: const EdgeInsets.only(top: _TopBar.height),
              child: _LoadingState(notifier: notebookNotifier),
            ),
            error: (e, _) => Center(
                child: Text(l10n.libErrorGeneric(e.toString()),
                    style: TextStyle(color: p.ink2))),
          );
          final main = Column(children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(
                  child: RefreshIndicator(
                    edgeOffset: _TopBar.height,
                    onRefresh: () =>
                        notebookNotifier.syncNow(showProgress: false),
                    child: body,
                  ),
                ),
                // Floats over the list so content scrolls under its glass.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _TopBar(
                    scroll: _scroll,
                    title: folderName,
                    wide: wide,
                    searchController: _searchCtrl,
                    onSearchChanged: (v) => setState(() => _query = v),
                    gridView: settings.libraryGridView,
                    onViewToggle: ref
                        .read(appSettingsProvider.notifier)
                        .setLibraryGridView,
                    onSortTap: _showSortSheet,
                    onSettingsTap: _openSettings,
                    onImportTap: _importFlow,
                    sortLabel: settings.sortMode.labelOf(l10n),
                  ),
                ),
              ]),
            ),
            if (!wide) _FooterBar(),
          ]);
          if (!wide) return main;
          return Row(children: [
            _Sidebar(
              folders: settings.folders,
              entries: entries,
              folderOf: settings.notebookFolderId,
              selectedFolderId: _selectedFolderId,
              onSelect: (id) => setState(() => _selectedFolderId = id),
              onCreateFolder: _createFolder,
              onRenameFolder: _renameFolder,
              onDeleteFolder: _deleteFolder,
              onTrash: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TrashScreen())),
              onSettings: _openSettings,
            ),
            Expanded(child: main),
          ]);
        }),
      ),
    );
  }

  Future<void> _createFolder() async {
    final name = await _newFolderDialog(context);
    if (name != null && name.isNotEmpty) {
      ref.read(appSettingsProvider.notifier).createFolder(name);
    }
  }

  Future<void> _renameFolder(NotebookFolder folder) async {
    final name = await _newFolderDialog(context, initial: folder.name);
    if (name != null && name.isNotEmpty) {
      ref.read(appSettingsProvider.notifier).renameFolder(folder.id, name);
    }
  }

  Future<void> _deleteFolder(NotebookFolder folder) async {
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
  }

  List<NotebookEntry> _filterAndSort(
      List<NotebookEntry> all, AppSettings s, String query, String? folderId) {
    final q = foldForSearch(query.trim());
    var list = q.isEmpty
        ? List<NotebookEntry>.from(all)
        : all
            .where((n) => foldForSearch(n.metadata.title).contains(q))
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
          return _compareTitles(a.metadata.title, b.metadata.title);
        case LibrarySortMode.titleDesc:
          return _compareTitles(b.metadata.title, a.metadata.title);
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

  static int _compareTitles(String a, String b) {
    final c = foldForSearch(a).compareTo(foldForSearch(b));
    return c != 0 ? c : a.compareTo(b);
  }

  Future<void> _openNotebook(NotebookEntry entry, {Rect? origin}) async {
    ref.read(appSettingsProvider.notifier).markOpened(entry.metadata.id);
    try {
      await openNotebookAndNavigate(context, ref, entry, origin: origin);
      if (!mounted) return;
      // The 5-minute tick skips while a notebook is open, so a session spent
      // in the editor would otherwise never retry pending uploads.
      final notifier = ref.read(notebookListProvider.notifier);
      unawaited(notifier
          .refresh()
          .then((_) => notifier.retryPendingUploads())
          .catchError((Object _) {}));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context)
                    .libErrorOpen(syncErrorText(AppLocalizations.of(context), e)))),
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
        sectionLabel: l10n.qiOneNoteSection,
        pageLabel: l10n.qiOneNotePage,
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
      debugPrint('[Import] OneNote import failed: $e');
      _toast(_oneNoteErrorMessage(l10n, e));
    } finally {
      controller.dispose();
    }
  }

  /// Bridge failures read like `parse_section: <diagnosis>`: log-only text,
  /// so any bridge FormatException maps to the generic unreadable message.
  String _oneNoteErrorMessage(AppLocalizations l10n, Object error) {
    if (error is ImportException) return importErrorText(l10n, error);
    if (error is FormatException) return l10n.libImportOneNoteUnreadable;
    return importErrorText(l10n, error);
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
      debugPrint('[Import] foreign import failed: $e');
      _toast(importErrorText(l10n, e));
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
      // Legacy spelling stays selectable: exports made before the rename.
      allowedExtensions: ['abelnote', 'ncnote', 'zip'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final single = result.files.length == 1;
    var imported = 0;
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) {
        _toast(l10n.libImportCannotReadFile);
        continue;
      }
      if (!mounted) return;
      if (await _importNcnoteBytes(bytes, file.name, announce: single)) imported++;
    }
    if (!single && imported > 0) _toast(l10n.libImportSuccessMany(imported));
  }

  /// A notebook handed to us by the OS (file association / command line).
  ///
  /// A notebook the user already has is OPENED, not imported: double-clicking
  /// your own file must not silently clone it. Importing stays the explicit
  /// in-app action, which always makes a copy.
  Future<void> _openNcnotePath(String path) async {
    Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (e) {
      if (mounted) {
        _toast(AppLocalizations.of(context).libErrorImport(e.toString()));
      }
      return;
    }
    if (!mounted) return;

    final syncService = ref.read(syncServiceProvider);
    if (syncService != null) {
      try {
        final incoming = syncService.parseNcnoteMetadataOnly(bytes);
        final existing = await _findNotebookById(incoming.id);
        if (!mounted) return;
        if (existing != null) {
          _openNotebook(existing);
          return;
        }
      } catch (_) {
        // Unreadable archive: fall through so the import path reports it with
        // the friendly message instead of duplicating the diagnosis here.
      }
    }
    if (!mounted) return;
    await _importNcnoteBytes(bytes, path.split(RegExp(r'[\\/]')).last);
  }

  /// The library loads asynchronously, so on a cold start the list can still
  /// be empty when the OS request arrives — deciding "do I already have this?"
  /// against it would import a duplicate. Waits for the first real value.
  Future<NotebookEntry?> _findNotebookById(String id) async {
    var list = ref.read(notebookListProvider);
    if (!list.hasValue) {
      final completer = Completer<AsyncValue<List<NotebookEntry>>>();
      final sub = ref.listenManual<AsyncValue<List<NotebookEntry>>>(
        notebookListProvider,
        (_, next) {
          if (next.hasValue && !completer.isCompleted) completer.complete(next);
        },
      );
      try {
        list = await completer.future
            .timeout(const Duration(seconds: 10), onTimeout: () => list);
      } finally {
        sub.close();
      }
    }
    for (final entry in list.valueOrNull ?? const <NotebookEntry>[]) {
      if (entry.metadata.id == id) return entry;
    }
    return null;
  }

  /// Export straight from the library — the same .ncnote package the in-canvas
  /// export produces, read from disk instead of from live canvas state.
  Future<void> _exportNotebook(NotebookEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(SnackBar(content: Text(l10n.csGeneratingNcnote)));
      final bytes =
          await ref.read(fileServiceProvider).readNotebookFile(entry.metadata.id);
      messenger.clearSnackBars();
      if (!mounted) return;
      if (bytes == null) {
        _toast(l10n.libImportCannotReadFile);
        return;
      }
      await saveOrShareFile(
        context,
        fileName:
            '${sanitiseForFilename(entry.metadata.title)}${AppConfig.fileExtension}',
        data: bytes,
        mimeType: 'application/zip',
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text(
              l10n.csNcnoteExported((bytes.length / 1024).toStringAsFixed(1)))));
    } catch (e) {
      messenger.clearSnackBars();
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.csNcnoteExportError(e.toString()))));
    }
  }

  /// Returns whether the notebook was imported. [announce] shows the
  /// per-notebook success toast; a batch shows one summary instead.
  Future<bool> _importNcnoteBytes(Uint8List bytes, String name, {bool announce = true}) async {
    final l10n = AppLocalizations.of(context);

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
      SyncService.validateNcnoteArchive(bytes, context: 'import $name');

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

      if (!mounted) return true;
      // ignore: use_build_context_synchronously
      Navigator.of(ctx).pop(); // dismiss spinner
      ref.read(notebookListProvider.notifier).refresh();
      if (announce) _toast(l10n.libImportSuccess(newTitle, pages.length));
      return true;
    } catch (e) {
      if (!mounted) return false;
      // ignore: use_build_context_synchronously
      Navigator.of(ctx).pop();
      // A corrupt archive is a normal thing for a user to hit — a truncated
      // download, a half-synced file, a double-click on the wrong .ncnote — so
      // it gets a sentence they can act on. The exception text stays in the
      // log for diagnosis.
      debugPrint('[Import] .ncnote import failed: $e');
      final msg = e is CorruptedArchiveException
          ? l10n.libImportCorruptedFile
          : l10n.libErrorImport(e.toString());
      // Named, so in a batch it's clear which file it was.
      _toast('$name — $msg');
      return false;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _createNotebook() async {
    final chapterTitle = AppLocalizations.of(context).quDefaultChapter;
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
                coverStyle: res.coverStyle.key,
                chapterTitle: chapterTitle,
                pageWidth: res.pageSize.width,
                pageHeight: res.pageSize.height,
              );
      if (mounted) _openNotebook(entry);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context)
                    .libErrorCreate(syncErrorText(AppLocalizations.of(context), e)))),
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
                chapterTitle: AppLocalizations.of(context).quDefaultChapter,
              );
      if (mounted) _openNotebook(entry);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .libErrorCreateSketch(syncErrorText(AppLocalizations.of(context), e)))),
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

  /// Takes a notebook off the remote, or puts it back on.
  ///
  /// Turning it off asks first, because of the copy that may already be
  /// uploaded: deleting someone's file is not something to do as a side
  /// effect of a preference, so the checkbox offering it starts unticked and
  /// the default is to leave that copy alone.
  Future<void> _toggleLocalOnly(NotebookEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final files = ref.read(fileServiceProvider);

    if (entry.localOnly) {
      final notifier = ref.read(notebookListProvider.notifier);
      final uploaded = await notifier.resumeSync(entry);
      ref.read(canvasProvider.notifier).forgetLocalOnly(entry.metadata.id);
      await notifier.refresh(showProgress: false);
      messenger.showSnackBar(SnackBar(
          content: Text(uploaded
              ? l10n.qsResumeSyncUploaded
              : notifier.needsOpenToUpload.value.contains(entry.metadata.id)
                  ? l10n.qtResumeSyncNeedsOpen
                  : l10n.qsResumeSyncPending)));
      return;
    }

    var removeRemote = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setLocal) => AlertDialog(
          title: Text(l10n.libKeepOnDeviceTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.libKeepOnDeviceBody),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: removeRemote,
                onChanged: (v) => setLocal(() => removeRemote = v ?? false),
                title: Text(l10n.libKeepOnDeviceRemoveCopy,
                    style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: Text(l10n.libCancel)),
            TextButton(
                onPressed: () => Navigator.pop(dCtx, true),
                child: Text(l10n.libKeepOnDeviceConfirm)),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    await files.setNotebookLocalOnly(entry.metadata.id, true);
    ref.read(canvasProvider.notifier).forgetLocalOnly(entry.metadata.id);
    if (removeRemote) {
      // Best effort: the local setting is what the user asked for and must
      // stick even if the remote is unreachable right now.
      try {
        await ref
            .read(notebookListProvider.notifier)
            .deleteRemoteCopy(entry);
      } catch (_) {}
    }
    await ref.read(notebookListProvider.notifier).refresh(showProgress: false);
    messenger.showSnackBar(SnackBar(content: Text(l10n.libLocalOnlyDone)));
  }

  /// Frees this device's copy of a notebook, or asks for it back.
  ///
  /// The opposite trade from [_toggleLocalOnly]: there the notebook stays
  /// here and leaves the cloud, here it stays in the cloud and leaves the
  /// device. Only offered for notebooks the remote is known to hold, because
  /// the remote copy is the one the user gets back.
  Future<void> _toggleOnDevice(NotebookEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(notebookListProvider.notifier);

    if (entry.notOnDevice) {
      await notifier.keepOnDevice(entry);
      await notifier.refresh(showProgress: true);
      messenger.showSnackBar(SnackBar(content: Text(l10n.libKeepOnThisDeviceDone)));
      return;
    }

    // Evicting the notebook the canvas is holding would pull the files out
    // from under a live editor.
    if (ref.read(canvasProvider)?.metadata.id == entry.metadata.id) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.libFreeSpaceOpenNotebook)));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.libFreeSpaceTitle),
        content: Text(l10n.libFreeSpaceBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: Text(l10n.libCancel)),
          TextButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: Text(l10n.libFreeSpaceConfirm)),
        ],
      ),
    );
    if (confirmed != true) return;

    final int freed;
    try {
      freed = await notifier.evictLocalCopy(entry);
    } on StateError {
      // The guards in FileService: unsynced changes, or a notebook the
      // remote never had. Both mean there is nothing to come back from.
      messenger.showSnackBar(SnackBar(content: Text(l10n.libFreeSpaceNotSynced)));
      return;
    }
    await notifier.refresh(showProgress: false);
    messenger.showSnackBar(
        SnackBar(content: Text(l10n.libFreeSpaceDone(_formatFreedSize(freed)))));
  }

  String _formatFreedSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _showNotebookMenu(NotebookEntry entry) async {
    // Long-press is a hidden affordance; the bottom sheet feels more
    // intentional with a confirmatory haptic.
    HapticFeedback.lightImpact();
    final l10n = AppLocalizations.of(context);
    final settings = ref.read(appSettingsProvider);
    final isFav = settings.favoriteNotebookIds.contains(entry.metadata.id);
    final tray = ref.read(pagesTrayProvider).tray;

    final action = await showScrollableSheet<String>(
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
              if (tray != null && !(tray.isMove && tray.sourceNotebookId == entry.metadata.id))
                _menuItem(
                    ctx,
                    tray.isMove ? 'move' : 'paste',
                    tray.isMove
                        ? l10n.pgtCardMoveHere(tray.count)
                        : l10n.pgtCardPasteHere(tray.count),
                    'trayPaste'),
              _menuItem(
                  ctx,
                  'star',
                  isFav
                      ? l10n.libRemoveFromFavorites
                      : l10n.libAddToFavorites,
                  'fav'),
              _menuItem(ctx, 'pen', l10n.libRename, 'rename'),
              _menuItem(ctx, 'duplicate', l10n.qlDuplicate, 'duplicate'),
              _menuItem(ctx, 'palette', l10n.libChangeCover, 'cover'),
              _menuItem(ctx, 'folder', l10n.libMoveToFolder, 'move'),
              _menuItem(ctx, 'export', l10n.libExport, 'export'),
              // Only offered when there is a remote to withhold it from.
              if (ref.read(remoteStoreProvider) != null)
                _menuItem(
                    ctx,
                    entry.localOnly ? 'cloud' : 'cloud-off',
                    entry.localOnly ? l10n.libResumeSync : l10n.libKeepOnDevice,
                    'localOnly'),
              // The remote copy is what the user gets back, so this is only
              // offered for notebooks it already holds.
              if (ref.read(remoteStoreProvider) != null &&
                  !entry.localOnly &&
                  (entry.notOnDevice || !entry.isLocal))
                _menuItem(
                    ctx,
                    entry.notOnDevice ? 'cloud-download' : 'trash',
                    entry.notOnDevice
                        ? l10n.libKeepOnThisDevice
                        : l10n.libFreeSpace,
                    'onDevice'),
              _menuItem(ctx, 'trash', l10n.libDelete, 'delete', danger: true),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    try {
      switch (action) {
        case 'trayPaste':
          await ref
              .read(pagesTrayProvider.notifier)
              .pasteIntoClosed(entry.metadata.id);
          break;
        case 'fav':
          ref
              .read(appSettingsProvider.notifier)
              .toggleFavorite(entry.metadata.id);
          break;
        case 'localOnly':
          await _toggleLocalOnly(entry);
          break;
        case 'onDevice':
          await _toggleOnDevice(entry);
          break;
        case 'rename':
          final t = await _renameDialog(entry.metadata.title);
          if (t != null && t.isNotEmpty) {
            await ref
                .read(notebookListProvider.notifier)
                .renameNotebook(entry, t);
          }
          break;
        case 'duplicate':
          final copy = await ref
              .read(notebookListProvider.notifier)
              .duplicateNotebook(
                  entry, l10n.qlDuplicateTitle(entry.metadata.title));
          if (copy != null) {
            final folderId = ref
                .read(appSettingsProvider)
                .notebookFolderId[entry.metadata.id];
            if (folderId != null) {
              ref
                  .read(appSettingsProvider.notifier)
                  .setNotebookFolder(copy.metadata.id, folderId);
            }
          }
          _toast(copy == null ? l10n.qlDuplicateNoLocalCopy : l10n.qlDuplicated);
          break;
        case 'move':
          await _showMoveToFolderSheet(entry);
          break;
        case 'export':
          await _exportNotebook(entry);
          break;
        case 'cover':
          final picked = await _pickCover(entry);
          if (picked != null) {
            final c = picked.color;
            final argb = (c.a * 255).round() << 24 |
                (c.r * 255).round() << 16 |
                (c.g * 255).round() << 8 |
                (c.b * 255).round();
            await ref
                .read(notebookListProvider.notifier)
                .updateNotebookCover(entry, argb, picked.style.key);
          }
          break;
        case 'delete':
          // No copy left on this device and nobody to ask for one: there is
          // nothing to put in the trash, so the dialog must not promise it.
          final orphan = ref.read(remoteStoreProvider) == null &&
              !await ref
                  .read(fileServiceProvider)
                  .hasLocalCopy(entry.metadata.id);
          if (!mounted) return;
          final confirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(l10n.libDeleteNotebookTitle),
              content: Text(orphan
                  ? l10n.qlDeleteOrphanBody
                  : l10n.libDeleteNotebookBody),
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
          if (confirm == true && mounted) {
            final messenger = ScaffoldMessenger.of(context);
            final result = await ref
                .read(notebookListProvider.notifier)
                .deleteNotebook(entry);
            if (result.trashId == null) _toast(l10n.qlDeletedNoTrash);
            if (result.remotePending) {
              messenger.showSnackBar(
                  SnackBar(content: Text(l10n.libDeleteRemotePending)));
            }
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

  /// Reassigns [AppSettings.notebookFolderId]; no notebook file I/O, the
  /// change syncs through folders.json.
  Future<void> _showMoveToFolderSheet(NotebookEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final settingsNotifier = ref.read(appSettingsProvider.notifier);
    final currentFolderId =
        ref.read(appSettingsProvider).notebookFolderId[entry.metadata.id];

    await showScrollableSheet<void>(
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

  Future<String?> _newFolderDialog(BuildContext ctx, {String? initial}) {
    final l10n = AppLocalizations.of(ctx);
    return showDialog<String>(
      context: ctx,
      builder: (_) => _NameDialog(
        title: initial == null ? l10n.libNewFolder : l10n.libRenameFolder,
        hint: l10n.libFolderNameHint,
        initial: initial ?? '',
        confirmLabel: initial == null ? l10n.libCreate : l10n.libSave,
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
  Future<({Color color, CoverStyle style})?> _pickCover(
      NotebookEntry entry) async {
    var color = Color(entry.metadata.coverColor);
    var style = CoverStyle.fromKey(entry.metadata.coverStyle);
    final texture = coverTextureFor(entry.metadata.paperType);
    return showModalBottomSheet<({Color color, CoverStyle style})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: HwThemeScope.of(context).paper0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final p = HwThemeScope.of(ctx);
        final l10n = AppLocalizations.of(ctx);
        const sectionStyle =
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.libChangeCover,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Center(
                  child: NotebookCover(
                    color: color,
                    title: entry.metadata.title,
                    texture: texture,
                    style: style,
                    width: 150,
                    height: 195,
                  ),
                ),
                const SizedBox(height: 20),
                Text(l10n.libCoverColor, style: sectionStyle),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in HwTheme.covers)
                      GestureDetector(
                        onTap: () => setSheet(() => color = c),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(8),
                            border: color.toARGB32() == c.toARGB32()
                                ? Border.all(color: p.ink0, width: 2)
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(l10n.libCoverPattern, style: sectionStyle),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final st in CoverStyle.values)
                      Tooltip(
                        message: _coverStyleName(l10n, st),
                        child: Semantics(
                          button: true,
                          selected: st == style,
                          label: _coverStyleName(l10n, st),
                          child: GestureDetector(
                            onTap: () => setSheet(() => style = st),
                            child: _CoverStyleSwatch(
                              color: color,
                              style: st,
                              texture: texture,
                              selected: st == style,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_coverStyleName(l10n, style),
                    style: TextStyle(fontSize: 12, color: p.ink2)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(l10n.libCancel)),
                    const SizedBox(width: 8),
                    FilledButton(
                        onPressed: () => Navigator.of(ctx)
                            .pop((color: color, style: style)),
                        child: Text(l10n.libCoverApply)),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Future<String?> _renameDialog(String old) {
    final l10n = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: l10n.libRenameNotebookTitle,
        initial: old,
        confirmLabel: l10n.libSave,
      ),
    );
  }

  Future<void> _showSortSheet() async {
    final l10n = AppLocalizations.of(context);
    final current = ref.read(appSettingsProvider).sortMode;
    final p = HwThemeScope.of(context);
    try {
      final picked = await showScrollableSheet<LibrarySortMode>(
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
/// Rename/delete actions for a folder (long-press or right click).
Future<void> _showFolderMenu(
  BuildContext context,
  NotebookFolder folder, {
  required ValueChanged<NotebookFolder> onRename,
  required ValueChanged<NotebookFolder> onDelete,
}) async {
  final l10n = AppLocalizations.of(context);
  final p = HwThemeScope.of(context);
  Widget row(String icon, String label, Color color, String value, BuildContext ctx) =>
      InkWell(
        onTap: () => Navigator.of(ctx).pop(value),
        borderRadius: BorderRadius.circular(HwTheme.rMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(children: [
            HwIcon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Text(label, style: HwType.callout.copyWith(color: color, fontSize: 15)),
          ]),
        ),
      );
  final action = await showScrollableSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: p.paper0,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(HwTheme.rXl)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                  color: p.paper3, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 12),
          row('pen', l10n.libRenameFolder, p.ink0, 'rename', ctx),
          row('trash', l10n.libDeleteFolder, HwTheme.syncConflict, 'delete', ctx),
        ],
      ),
    ),
  );
  if (action == 'rename') onRename(folder);
  if (action == 'delete') onDelete(folder);
}

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
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        children: [
          _chip(context,
              label: l10n.libAllNotebooks,
              selected: selectedFolderId == null,
              onTap: () => onSelect(null)),
          for (final folder in folders)
            GestureDetector(
              onLongPress: () => _showFolderMenu(context, folder,
                  onRename: onRename, onDelete: onDelete),
              onSecondaryTap: () => _showFolderMenu(context, folder,
                  onRename: onRename, onDelete: onDelete),
              child: _chip(context,
                  label: folder.name,
                  selected: selectedFolderId == folder.id,
                  onTap: () => onSelect(folder.id)),
            ),
          _addChip(context),
        ],
      ),
    );
  }

  Widget _addChip(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Tooltip(
      message: AppLocalizations.of(context).libNewFolder,
      child: GestureDetector(
        onTap: onCreate,
        child: HwPressable(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: p.paper2, shape: BoxShape.circle),
            child: Center(child: HwIcon('plus', size: 16, color: p.ink1)),
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context,
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    final p = HwThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: HwPressable(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? p.accentSoft : p.paper2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(label,
                style: TextStyle(
                  fontSize: 13.5,
                  color: selected ? p.accentDeep : p.ink1,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                )),
          ),
        ),
      ),
    );
  }
}

/// Wide-window navigation: folders with counts, trash, settings, sync state.
class _Sidebar extends ConsumerWidget {
  final List<NotebookFolder> folders;
  final List<NotebookEntry> entries;
  final Map<String, String> folderOf;
  final String? selectedFolderId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onCreateFolder;
  final ValueChanged<NotebookFolder> onRenameFolder;
  final ValueChanged<NotebookFolder> onDeleteFolder;
  final VoidCallback onTrash;
  final VoidCallback onSettings;

  const _Sidebar({
    required this.folders,
    required this.entries,
    required this.folderOf,
    required this.selectedFolderId,
    required this.onSelect,
    required this.onCreateFolder,
    required this.onRenameFolder,
    required this.onDeleteFolder,
    required this.onTrash,
    required this.onSettings,
  });

  static const width = 248.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final (syncIcon, syncLabel) = _syncFooterInfo(ref, l10n);
    int countIn(String id) =>
        entries.where((e) => folderOf[e.metadata.id] == id).length;
    return Container(
      width: width,
      decoration: BoxDecoration(
        // Heavier material than the content: separates structure from content.
        color: Color.alphaBlend(p.ink0.withValues(alpha: 0.035), p.paper1),
        border: Border(right: BorderSide(color: p.paper3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 18),
            child: Row(children: [
              Image.asset('assets/branding/logo.png', width: 26, height: 26),
              const SizedBox(width: 10),
              Flexible(
                child: Text(l10n.libAppName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HwType.title.copyWith(
                        color: p.ink0, fontSize: 17, letterSpacing: -0.25)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                _SideItem(
                  icon: 'pages',
                  label: l10n.libAllNotebooks,
                  count: entries.length,
                  selected: selectedFolderId == null,
                  onTap: () => onSelect(null),
                ),
                for (final f in folders)
                  _SideItem(
                    icon: 'folder',
                    label: f.name,
                    count: countIn(f.id),
                    selected: selectedFolderId == f.id,
                    onTap: () => onSelect(f.id),
                    onMenu: () => _showFolderMenu(context, f,
                        onRename: onRenameFolder, onDelete: onDeleteFolder),
                  ),
                _SideItem(
                  icon: 'plus',
                  label: l10n.libNewFolder,
                  muted: true,
                  onTap: onCreateFolder,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(children: [
              _SideItem(icon: 'trash', label: l10n.setTrash, onTap: onTrash),
              _SideItem(
                  icon: 'settings',
                  label: l10n.setSettingsTitle,
                  onTap: onSettings),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 14),
            child: Row(children: [
              HwIcon(syncIcon, size: 15, color: p.ink2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(syncLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HwType.footnote.copyWith(color: p.ink2)),
              ),
              const SyncRefreshButton(),
            ]),
          ),
        ],
      ),
    );
  }
}

class _SideItem extends StatefulWidget {
  final String icon;
  final String label;
  final int? count;
  final bool selected;
  final bool muted;
  final VoidCallback onTap;
  final VoidCallback? onMenu;

  const _SideItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
    this.selected = false,
    this.muted = false,
    this.onMenu,
  });

  @override
  State<_SideItem> createState() => _SideItemState();
}

class _SideItemState extends State<_SideItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final sel = widget.selected;
    final fg = sel ? p.accentDeep : (widget.muted ? p.ink2 : p.ink0);
    return Semantics(
      button: true,
      selected: sel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: widget.onMenu,
          onSecondaryTap: widget.onMenu,
          child: Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: sel
                  ? p.accentSoft
                  : _hover
                      ? p.ink0.withValues(alpha: 0.05)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(HwTheme.rSm + 1),
            ),
            child: Row(children: [
              HwIcon(widget.icon,
                  size: 17, color: sel ? p.accent : p.ink2),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                        color: fg)),
              ),
              if (widget.count != null)
                Text('${widget.count}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: sel ? p.accentDeep : p.ink3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Folder name + count; fades as it scrolls under the bar, where the
/// inline title takes over.
class _LargeTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final ScrollController scroll;
  final double hPad;

  const _LargeTitle({
    required this.title,
    required this.subtitle,
    required this.scroll,
    required this.hPad,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return AnimatedBuilder(
      animation: scroll,
      builder: (context, child) {
        final y = scroll.hasClients ? scroll.offset : 0.0;
        return Opacity(
            opacity: (1 - (y - 4) / 28).clamp(0.0, 1.0), child: child);
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(hPad, 2, hPad, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HwType.largeTitle.copyWith(color: p.ink0)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: HwType.footnote.copyWith(color: p.ink2, fontSize: 13.5)),
          ],
        ),
      ),
    );
  }
}

(String, String) _syncFooterInfo(WidgetRef ref, AppLocalizations l10n) {
  final backend = ref.watch(appSettingsProvider.select((s) => s.syncBackend));
  return ref.watch(remoteStoreProvider) == null
      ? ('cloud-off', l10n.libLocalOnlyBadge)
      : backend == SyncBackend.drive
          ? ('cloud-check', l10n.setSyncDriveTitle)
          : ('cloud-check', l10n.libFooterWebdav);
}

// ─── Top bar ─────────────────────────────────────────────────────
/// Floats over the list: clear at rest, glass once content slides under it.
class _TopBar extends StatelessWidget {
  static const double height = 60;

  final ScrollController scroll;
  final String title;
  final bool wide;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool gridView;
  final ValueChanged<bool> onViewToggle;
  final VoidCallback onSortTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onImportTap;
  final String sortLabel;

  const _TopBar({
    required this.scroll,
    required this.title,
    required this.wide,
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
      final isCompact = c.maxWidth < 640;
      final iconOnly = !isCompact && c.maxWidth < 980;
      final hPad = isCompact ? 12.0 : (wide ? 24.0 : 20.0);
      final row = Row(
        children: [
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
          else ...[
            Expanded(
              child: AnimatedBuilder(
                animation: scroll,
                builder: (_, child) {
                  final y = scroll.hasClients ? scroll.offset : 0.0;
                  return Opacity(
                      opacity: ((y - 28) / 18).clamp(0.0, 1.0), child: child);
                },
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HwType.headline.copyWith(color: p.ink0, fontSize: 16)),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: HwTextField(
                controller: searchController,
                hint: l10n.libSearchHintNotebooks,
                leading: const HwIcon('search', size: 16),
                onChanged: onSearchChanged,
                width: double.infinity,
              ),
            ),
            const SizedBox(width: 10),
            _ViewToggle(gridView: gridView, onChanged: onViewToggle),
            const SizedBox(width: 6),
            if (iconOnly)
              HwButton.icon(
                  icon: const HwIcon('sort', size: 16),
                  tooltip: l10n.libSortWithLabel(sortLabel),
                  onPressed: onSortTap)
            else
              HwButton(
                leading: const HwIcon('sort', size: 16),
                label: sortLabel,
                onPressed: onSortTap,
              ),
            if (iconOnly)
              HwButton.icon(
                  icon: const HwIcon('export', size: 16),
                  tooltip: l10n.libImportTooltip,
                  onPressed: onImportTap)
            else
              HwButton(
                leading: const HwIcon('export', size: 16),
                label: l10n.libImport,
                tooltip: l10n.libImportTooltip,
                onPressed: onImportTap,
              ),
            if (!wide)
              HwButton.icon(
                  icon: const HwIcon('settings', size: 16),
                  tooltip: l10n.libSettingsTooltip,
                  onPressed: onSettingsTap),
          ],
          if (isCompact) ...[
            const SizedBox(width: 4),
            HwButton.icon(
              icon: const HwIcon('more', size: 18),
              tooltip: l10n.libMoreTooltip,
              onPressed: () => _compactMenu(ctx),
            ),
          ],
        ],
      );
      return AnimatedBuilder(
        animation: scroll,
        builder: (_, child) {
          final y = scroll.hasClients ? scroll.offset : 0.0;
          final edge = (y / 20).clamp(0.0, 1.0);
          if (edge == 0) return child!;
          // Web: fill only, no blur (see HwGlass).
          if (kIsWeb) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: Color.alphaBlend(p.glass, p.paper1)
                    .withValues(alpha: edge),
                border: Border(
                    bottom: BorderSide(
                        color: p.glassLine
                            .withValues(alpha: p.glassLine.a * edge))),
              ),
              child: child,
            );
          }
          // Materialize: blur and fill grow together with the scroll.
          return ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20 * edge, sigmaY: 20 * edge),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.glass.withValues(alpha: p.glass.a * edge),
                  border: Border(
                      bottom: BorderSide(
                          color: p.glassLine.withValues(
                              alpha: p.glassLine.a * edge))),
                ),
                child: child,
              ),
            ),
          );
        },
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: row,
          ),
        ),
      );
    });
  }

  Future<void> _compactMenu(BuildContext context) async {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await showScrollableSheet<void>(
        context: context,
        backgroundColor: p.paper0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(HwTheme.rXl)),
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

/// Grid/list segmented control; the thumb slides on a spring.
class _ViewToggle extends StatelessWidget {
  final bool gridView;
  final ValueChanged<bool> onChanged;
  const _ViewToggle({required this.gridView, required this.onChanged});

  static const _seg = 34.0;

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    Widget seg(String icon, bool value) => Tooltip(
          message: value
              ? AppLocalizations.of(context).libViewAsGrid
              : AppLocalizations.of(context).libViewAsList,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(value),
              child: SizedBox(
                width: _seg,
                height: 28,
                child: Center(
                  child: HwIcon(icon,
                      size: 16, color: gridView == value ? p.ink0 : p.ink2),
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.paper2,
        borderRadius: BorderRadius.circular(HwTheme.rSm + 2),
      ),
      child: Stack(children: [
        HwSpringOffset(
          offset: Offset(gridView ? 0 : _seg, 0),
          child: Container(
            width: _seg,
            height: 28,
            decoration: BoxDecoration(
              color: p.isDark ? p.paper3 : p.paper0,
              borderRadius: BorderRadius.circular(HwTheme.rSm),
              boxShadow: hwShadow1(p.brightness),
            ),
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          seg('grid', true),
          seg('list', false),
        ]),
      ]),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────
class _Body extends StatelessWidget {
  final ScrollController controller;
  /// Title, folder chips and notices: scroll with the content.
  final List<Widget> headerSlivers;
  final double hPad;
  final List<NotebookEntry> entries;
  final List<NotebookEntry> sketches;
  final bool gridView;
  final String searchQuery;
  final Set<String> favoriteIds;
  final void Function(NotebookEntry entry, {Rect? origin}) onOpen;
  final VoidCallback onCreate;
  final VoidCallback onCreateSketch;
  final ValueChanged<NotebookEntry> onLongPress;
  final ValueChanged<NotebookEntry> onToggleFavorite;

  /// Notebook a pending move comes from, tagged on its cover.
  final String? movingFromId;
  final int movingCount;

  const _Body({
    required this.controller,
    required this.headerSlivers,
    required this.hPad,
    required this.entries,
    required this.sketches,
    required this.gridView,
    required this.searchQuery,
    required this.favoriteIds,
    required this.onOpen,
    required this.onCreate,
    required this.onCreateSketch,
    required this.onLongPress,
    required this.onToggleFavorite,
    required this.movingFromId,
    required this.movingCount,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return CustomScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: _TopBar.height)),
        ...headerSlivers,
        SliverToBoxAdapter(
          child: _SketchSection(
            hPad: hPad,
            sketches: sketches,
            onCreateSketch: onCreateSketch,
            onOpen: onOpen,
            onLongPress: onLongPress,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // Both groups yield on a narrow phone: the heading and its
                // count together are wider than a 412dp row once text scales.
                Flexible(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                            AppLocalizations.of(context).libYourNotebooks,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HwType.title
                                .copyWith(color: p.ink0, fontSize: 17)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Flexible so a narrow phone shortens the button's label
                // rather than pushing the whole header off the screen.
                Flexible(
                  child: HwButton(
                    leading: const HwIcon('plus', size: 16),
                    label: AppLocalizations.of(context).libNewNotebook,
                    style: HwButtonStyle.primary,
                    onPressed: onCreate,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (searchQuery.isNotEmpty && entries.isEmpty && sketches.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
              child: Text(
                  AppLocalizations.of(context).qlSearchNoResults(searchQuery),
                  style: TextStyle(fontSize: 14, color: p.ink2)),
            ),
          ),
        if (gridView)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            sliver: SliverLayoutBuilder(
              builder: (ctx, constraints) {
                // Adapt cover-tile sizing to the available width so the
                // grid doesn't stay locked to tablet proportions on phones
                // or waste space on very wide desktops. mainExtent is
                // derived from maxExtent via the cover's aspect ratio plus
                // the text block below it, so the cover height always
                // tracks its actual width instead of the two drifting
                // apart on narrow screens (which read as the cover being
                // stretched tall and clipping into the row below).
                final width = constraints.crossAxisExtent;
                final double maxExtent;
                if (width < 480) {
                  maxExtent = 160;
                } else if (width > 1100) {
                  maxExtent = 280;
                } else {
                  maxExtent = 232;
                }
                final mainExtent =
                    _CoverTile.coverWidthFor(maxExtent) / _CoverTile.aspectRatio +
                        _CoverTile.textBlockHeightFor(ctx);
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: maxExtent,
                    mainAxisExtent: mainExtent,
                    crossAxisSpacing: width < 480 ? 16 : 28,
                    mainAxisSpacing: width < 480 ? 24 : 36,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      if (i == 0) return _NewTile(onTap: onCreate);
                      final e = entries[i - 1];
                      final tile = _CoverTile(
                        entry: e,
                        favorite: favoriteIds.contains(e.metadata.id),
                        onTap: (r) => onOpen(e, origin: r),
                        onLongPress: () => onLongPress(e),
                        onToggleFavorite: () => onToggleFavorite(e),
                      );
                      if (e.metadata.id != movingFromId) return tile;
                      return Stack(clipBehavior: Clip.none, children: [
                        tile,
                        Positioned(
                          left: -6,
                          bottom: _CoverTile.textBlockHeightFor(ctx) + 56,
                          child: _MovingBadge(count: movingCount),
                        ),
                      ]);
                    },
                    childCount: entries.length + 1,
                  ),
                );
              },
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: hPad - 8),
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
        SliverToBoxAdapter(child: SizedBox(height: movingCount > 0 ? 190 : 80)),
      ],
    );
  }
}

// ─── Sketch (infinite canvas) section ─────────────────────────────
class _SketchSection extends StatefulWidget {
  final double hPad;
  final List<NotebookEntry> sketches;
  final VoidCallback onCreateSketch;
  final void Function(NotebookEntry entry, {Rect? origin}) onOpen;
  final ValueChanged<NotebookEntry> onLongPress;
  const _SketchSection({
    required this.hPad,
    required this.sketches,
    required this.onCreateSketch,
    required this.onOpen,
    required this.onLongPress,
  });

  @override
  State<_SketchSection> createState() => _SketchSectionState();
}

/// Sketches sit on a shelf, App Store style: it stops on whole tiles, the
/// next one peeks in, a mouse can drag or wheel it, arrows appear on hover,
/// and "Show all" lays them out as a grid instead.
class _SketchSectionState extends State<_SketchSection> {
  static const double _tileW = 220;
  static const double _gap = 16;
  static const double _tileH = 128;

  final _ctrl = ScrollController();
  bool _expanded = false;
  bool _hover = false;
  bool _atStart = true;
  bool _atEnd = true;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_syncEnds);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _syncEnds() {
    if (!_ctrl.hasClients) return;
    final pos = _ctrl.position;
    final atStart = pos.pixels <= pos.minScrollExtent + 1;
    final atEnd = pos.pixels >= pos.maxScrollExtent - 1;
    if (atStart != _atStart || atEnd != _atEnd) {
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
  }

  void _page(int dir) {
    if (!_ctrl.hasClients) return;
    final pos = _ctrl.position;
    const stride = _tileW + _gap;
    final perView = (pos.viewportDimension / stride).floor().clamp(1, 99);
    final target = ((pos.pixels / stride).round() + dir * perView) * stride;
    _ctrl.animateTo(target.clamp(pos.minScrollExtent, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic);
  }

  Widget _tile(NotebookEntry e) => _SketchTile(
        entry: e,
        onTap: () => widget.onOpen(e),
        onLongPress: () => widget.onLongPress(e),
      );

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final sketches = widget.sketches;
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.hPad, 14, widget.hPad, 4),
      child: LayoutBuilder(builder: (context, c) {
        final fit = ((c.maxWidth + _gap) / (_tileW + _gap)).floor();
        final overflows = sketches.length > fit;
        // Phone width: title, "Show all" and a plus, like an iOS section.
        final compact = c.maxWidth < 600;
        if (!overflows && _expanded) _expanded = false;
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncEnds());
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(l10n.libSketches,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HwType.title
                                .copyWith(color: p.ink0, fontSize: 17)),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(l10n.libInfiniteSpace,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: p.ink2)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (overflows) ...[
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    style: TextButton.styleFrom(foregroundColor: p.accent),
                    child: Text(_expanded ? l10n.libShowLess : l10n.libShowAll),
                  ),
                  const SizedBox(width: 8),
                ],
                if (compact)
                  HwButton.icon(
                    icon: const HwIcon('plus', size: 16),
                    tooltip: l10n.libNewSketch,
                    style: HwButtonStyle.primary,
                    onPressed: widget.onCreateSketch,
                  )
                else
                  // Flexible so a narrow window shortens the button's label
                  // rather than pushing the whole header off the screen.
                  Flexible(
                    child: HwButton(
                      leading: const HwIcon('plus', size: 16),
                      label: l10n.libNewSketch,
                      style: HwButtonStyle.primary,
                      onPressed: widget.onCreateSketch,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: sketches.isEmpty
                  ? SizedBox(
                      height: _tileH,
                      child: _SketchEmptyTile(onTap: widget.onCreateSketch))
                  : _expanded
                      ? Wrap(
                          spacing: _gap,
                          runSpacing: _gap,
                          children: [
                            for (final e in sketches)
                              SizedBox(height: _tileH, child: _tile(e)),
                          ],
                        )
                      : _shelf(p),
            ),
          ],
        );
      }),
    );
  }

  Widget _shelf(HwPalette p) {
    final list = ScrollConfiguration(
      // A mouse drags the shelf like a finger; the wheel scrolls it sideways.
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      child: Listener(
        onPointerSignal: (signal) {
          if (signal is! PointerScrollEvent || !_ctrl.hasClients) return;
          final d = signal.scrollDelta;
          final delta = d.dy.abs() > d.dx.abs() ? d.dy : d.dx;
          final pos = _ctrl.position;
          _ctrl.jumpTo((pos.pixels + delta)
              .clamp(pos.minScrollExtent, pos.maxScrollExtent));
        },
        child: ListView.separated(
          controller: _ctrl,
          scrollDirection: Axis.horizontal,
          physics: const _TileSnapPhysics(extent: _tileW + _gap),
          itemCount: widget.sketches.length,
          separatorBuilder: (_, __) => const SizedBox(width: _gap),
          itemBuilder: (_, i) =>
              SizedBox(width: _tileW, child: _tile(widget.sketches[i])),
        ),
      ),
    );
    // Fade the edge that has more behind it, so the shelf reads as one.
    final faded = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => LinearGradient(
        colors: [
          _atStart ? Colors.black : Colors.transparent,
          Colors.black,
          Colors.black,
          _atEnd ? Colors.black : Colors.transparent,
        ],
        stops: const [0, 0.04, 0.96, 1],
      ).createShader(r),
      child: list,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: SizedBox(
        height: _tileH,
        child: Stack(children: [
          Positioned.fill(child: faded),
          if (_hover && !_atStart)
            Positioned(
                left: 6,
                top: (_tileH - 34) / 2,
                child: _ShelfArrow(icon: 'chevron-left', onTap: () => _page(-1))),
          if (_hover && !_atEnd)
            Positioned(
                right: 6,
                top: (_tileH - 34) / 2,
                child: _ShelfArrow(icon: 'chevron-right', onTap: () => _page(1))),
        ]),
      ),
    );
  }
}

class _ShelfArrow extends StatelessWidget {
  final String icon;
  final VoidCallback onTap;
  const _ShelfArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return HwGlass(
      borderRadius: BorderRadius.circular(17),
      strong: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(child: HwIcon(icon, size: 16, color: p.ink0)),
        ),
      ),
    );
  }
}

/// Lets a fling travel, then settles on a whole tile.
class _TileSnapPhysics extends ScrollPhysics {
  final double extent;
  const _TileSnapPhysics({required this.extent, super.parent});

  @override
  _TileSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _TileSnapPhysics(extent: extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final projected = position.pixels + velocity * 0.25;
    final target = ((projected / extent).roundToDouble() * extent)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity,
        tolerance: tolerance);
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
                // Sketches sync exactly like notebooks, so they need the same
                // badge: without it a sketch kept off the cloud, waiting to
                // upload, or not held on this device looks identical to one
                // that is fully synced.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                          relativeTime(AppLocalizations.of(context),
                              entry.metadata.modifiedAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: p.ink2)),
                    ),
                    SyncBadge(state: _syncStateOf(entry), size: 13),
                  ],
                ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _CoverTile.coverWidthFor(constraints.maxWidth);
        final height = width / _CoverTile.aspectRatio;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              height: height,
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
      },
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
  /// Receives the cover's global rect, for the open transition.
  final ValueChanged<Rect?> onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleFavorite;
  const _CoverTile({
    required this.entry,
    required this.favorite,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFavorite,
  });

  // Design proportions of the cover art itself (width / height). The grid's
  // mainAxisExtent is derived from this so cover height always tracks
  // whatever width the grid actually hands the tile, on any screen size.
  static const double aspectRatio = 200 / 260;
  // The cover never grows past its original design size — on wide
  // desktop columns it just stays 200 wide with room to spare, rather
  // than blowing up to fill the whole cell. On narrow phone columns it
  // shrinks below this, which is the case the aspect ratio above exists
  // to handle cleanly.
  static const double designMaxWidth = 200;
  // Space below the cover reserved for title + meta row, incl. the 12px
  // gap between cover and text. Keep in sync with the text block below.
  static const double textBlockHeight = 56;

  /// [textBlockHeight] assumes the default font scale; a phone set to large
  /// text needs more room or the meta row is clipped out of the grid cell.
  static double textBlockHeightFor(BuildContext context) {
    final t = MediaQuery.textScalerOf(context);
    final scaled = 12 + t.scale(14) * 1.4 + 2 + t.scale(12) * 1.4 + 4;
    return scaled > textBlockHeight ? scaled : textBlockHeight;
  }

  static double coverWidthFor(double cellWidth) =>
      cellWidth < designMaxWidth ? cellWidth : designMaxWidth;

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final coverWidth = coverWidthFor(constraints.maxWidth);
        final coverHeight = coverWidth / aspectRatio;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Star overlay sits ABOVE the cover via Stack so its tap can be
            // intercepted before NotebookCover's onTap fires (the cover-wide
            // InkWell would otherwise swallow it). One-tap favorite was a
            // three-tap action via the long-press sheet pre-fix.
            SizedBox(
              width: coverWidth,
              height: coverHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onLongPress: onLongPress,
                      // Desktop affordance: right click opens the same actions
                      // menu as long-press.
                      onSecondaryTap: onLongPress,
                      behavior: HitTestBehavior.translucent,
                      child: Builder(builder: (coverCtx) => NotebookCover(
                        color: Color(entry.metadata.coverColor),
                        title: entry.metadata.title,
                        style: CoverStyle.fromKey(entry.metadata.coverStyle),
                        // Hide the cover's built-in star — we render our own
                        // tappable one above.
                        favorite: false,
                        texture: coverTextureFor(entry.metadata.paperType),
                        width: coverWidth,
                        height: coverHeight,
                        onTap: () {
                          final box = coverCtx.findRenderObject() as RenderBox?;
                          onTap(box == null || !box.hasSize
                              ? null
                              : box.localToGlobal(Offset.zero) & box.size);
                        },
                      )),
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
              width: coverWidth,
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
                        // Flexible: on a 160px tile the page count, the
                        // separator and the sync badge together leave the
                        // date nothing, and the row spills past the tile.
                        Flexible(
                          child: Text(
                              AppLocalizations.of(context)
                                  .libPagesAbbrev(entry.metadata.pageCount),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: p.ink2)),
                        ),
                        Text(' · ',
                            style: TextStyle(fontSize: 12, color: p.ink3)),
                        Expanded(
                          child: Text(
                            relativeTime(AppLocalizations.of(context),
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
      },
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
                clipBehavior: Clip.antiAlias,
                child: CustomPaint(
                  painter: CoverPatternPainter(
                      CoverStyle.fromKey(entry.metadata.coverStyle)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.metadata.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: Text(
                    relativeTime(AppLocalizations.of(context),
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

class _FooterBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final (footerIcon, footerLabel) = _syncFooterInfo(ref, l10n);
    return LayoutBuilder(builder: (ctx, c) {
      // Both captions at full size overflow a phone's width — more so at a
      // large system font scale — so they share the row and ellipsize.
      final compact = c.maxWidth < 600;
      return Container(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 24, vertical: 10),
        decoration: BoxDecoration(
          color: p.paper1,
          border: Border(top: BorderSide(color: p.paper3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HwIcon(footerIcon, size: 14, color: p.ink2),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(footerLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.ink2)),
                  ),
                  const SizedBox(width: 4),
                  const SyncRefreshButton(),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(AppLocalizations.of(context).libFooterLocalFirst,
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: p.ink2)),
            ),
          ],
        ),
      );
    });
  }
}

/// Slim progress banner shown while a background sync with the server is
/// running. Returns [SizedBox.shrink] when idle so it costs no layout space.
/// Local-only reminder: no server, no Drive, nothing leaving the device.
///
/// Deliberately quiet and dismissible — the choice was already offered at
/// onboarding and saying "no" there has to keep working. This only makes the
/// state visible, and puts the same Connect action as Settings one tap away.
class _LocalOnlyNotice extends ConsumerWidget {
  const _LocalOnlyNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Credentials outlive the active backend, so check both: a saved server
    // with sync pointed elsewhere is not "local only".
    if (ref.watch(credentialsProvider) != null) return const SizedBox.shrink();
    if (ref.watch(remoteStoreProvider) != null) return const SizedBox.shrink();
    if (ref.watch(localOnlyNoticeDismissedProvider)) {
      return const SizedBox.shrink();
    }

    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(builder: (ctx, c) {
      final compact = c.maxWidth < 600;
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.libLocalOnlyTitle,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: p.ink0)),
          const SizedBox(height: 2),
          Text(kIsWeb ? l10n.libLocalOnlyBodyWeb : l10n.libLocalOnlyBody,
              style: TextStyle(fontSize: 12, color: p.ink2, height: 1.4)),
        ],
      );
      final connect = HwButton(
          label: l10n.setConnect,
          style: HwButtonStyle.primary,
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginScreen())));
      final dismiss = TextButton(
          onPressed: () =>
              ref.read(localOnlyNoticeDismissedProvider.notifier).dismiss(),
          child: Text(l10n.rcbDismiss,
              style: TextStyle(fontSize: 12, color: p.ink2)));
      return Container(
        width: double.infinity,
        color: p.paper2,
        padding:
            EdgeInsets.symmetric(horizontal: compact ? 16 : 32, vertical: 10),
        child: compact
            // Narrow: the buttons cannot share the row with the body text
            // without squeezing both, so they drop below it.
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    HwIcon('cloud-off', size: 14, color: p.ink3),
                    const SizedBox(width: 8),
                    Expanded(child: text),
                  ]),
                  const SizedBox(height: 8),
                  // Wrap, not Row: at 320 px with large text the two
                  // buttons don't fit side by side and a Row overflows.
                  Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 4,
                      runSpacing: 4,
                      children: [connect, dismiss]),
                ],
              )
            : Row(children: [
                HwIcon('cloud-off', size: 14, color: p.ink3),
                const SizedBox(width: 8),
                Expanded(child: text),
                connect,
                const SizedBox(width: 4),
                dismiss,
              ]),
      );
    });
  }
}

/// Shown when the remote refuses writes for lack of space.
///
/// Louder than the pending-uploads line on purpose: that one resolves itself
/// in a few seconds, this one never does until the user goes and deletes
/// something. It also names where the space ran out, because on Drive the
/// quota is shared with Gmail and Photos and people don't expect that.
class _StorageFullNotice extends ConsumerWidget {
  final NotebookListNotifier notifier;
  const _StorageFullNotice({required this.notifier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final onDrive =
        ref.watch(appSettingsProvider.select((s) => s.syncBackend)) ==
            SyncBackend.drive;

    return ValueListenableBuilder<bool>(
      valueListenable: notifier.storageFull,
      builder: (_, full, __) {
        if (!full) return const SizedBox.shrink();
        return LayoutBuilder(builder: (ctx, c) {
          final compact = c.maxWidth < 600;
          return Container(
            width: double.infinity,
            color: HwTheme.syncConflict.withValues(alpha: 0.12),
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 16 : 32, vertical: 12),
            child: Row(
              children: [
                const HwIcon('cloud-off', size: 16,
                    color: HwTheme.syncConflict),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        onDrive
                            ? l10n.libStorageFullDrive
                            : l10n.libStorageFullServer,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p.ink0),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        onDrive
                            ? l10n.libStorageFullBody
                            : l10n.libStorageFullBodyServer,
                        style: TextStyle(
                            fontSize: 12, color: p.ink2, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}

/// Says in words how many notebooks are still queued for upload.
class _PendingUploadsNotice extends ConsumerWidget {
  final List<NotebookEntry> entries;
  const _PendingUploadsNotice({required this.entries});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Kept-here and not-downloaded notebooks are never going up.
    final waiting = entries
        .where((e) => e.isLocal && !e.localOnly && !e.notOnDevice)
        .toList();
    if (waiting.isEmpty) return const SizedBox.shrink();
    final needsOpen = ref
        .read(notebookListProvider.notifier)
        .needsOpenToUpload
        .value;
    final blocked =
        waiting.where((e) => needsOpen.contains(e.metadata.id)).length;
    final unblocked =
        waiting.where((e) => !needsOpen.contains(e.metadata.id));
    final fresh = unblocked.where((e) => e.neverUploaded).toList();
    final edited = unblocked.where((e) => !e.neverUploaded).toList();

    final backend = ref.watch(appSettingsProvider.select((s) => s.syncBackend));
    // Local-only has no destination to name and nothing is queued for one.
    final remote = ref.watch(remoteStoreProvider);
    if (remote == null) return const SizedBox.shrink();

    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(builder: (ctx, c) {
      final compact = c.maxWidth < 600;
      return Container(
        width: double.infinity,
        color: p.paper2,
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 32, vertical: 10),
        child: Row(
          children: [
            const HwIcon('cloud-pending',
                size: 14, color: HwTheme.syncPending),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (fresh.isNotEmpty)
                    Text(
                      backend == SyncBackend.drive
                          ? l10n.libPendingNewDrive(fresh.length, _titles(fresh))
                          : l10n.libPendingNewServer(
                              fresh.length, _titles(fresh)),
                      style: TextStyle(fontSize: 13, color: p.ink1),
                    ),
                  if (edited.isNotEmpty)
                    Text(l10n.libPendingChanges(edited.length, _titles(edited)),
                        style: TextStyle(fontSize: 13, color: p.ink1)),
                  if (fresh.isNotEmpty || edited.isNotEmpty)
                    Text(l10n.libPendingUploadsHint,
                        style: TextStyle(fontSize: 11, color: p.ink3)),
                  if (blocked > 0) ...[
                    Text(l10n.qtNeedsOpenToUpload(blocked),
                        style: TextStyle(fontSize: 13, color: p.ink1)),
                    Text(l10n.qtNeedsOpenToUploadHint,
                        style: TextStyle(fontSize: 11, color: p.ink3)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Up to three titles, then a count of the rest.
String _titles(List<NotebookEntry> entries) {
  final shown = entries.take(3).map((e) => e.metadata.title).join(', ');
  final more = entries.length - 3;
  return more > 0 ? '$shown +$more' : shown;
}

/// A delete that hasn't reached the remote yet: other devices still show it.
class _PendingRemoteDeletesNotice extends StatelessWidget {
  final NotebookListNotifier notifier;
  const _PendingRemoteDeletesNotice({required this.notifier});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: notifier.pendingRemoteDeletes,
      builder: (_, count, __) {
        if (count == 0) return const SizedBox.shrink();
        return LayoutBuilder(builder: (ctx, c) {
          final compact = c.maxWidth < 600;
          return Container(
            width: double.infinity,
            color: p.paper2,
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 16 : 32, vertical: 10),
            child: Row(
              children: [
                const HwIcon('cloud-pending',
                    size: 14, color: HwTheme.syncPending),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.libPendingRemoteDeletes(count),
                          style: TextStyle(fontSize: 13, color: p.ink1)),
                      Text(l10n.libPendingRemoteDeletesHint,
                          style: TextStyle(fontSize: 11, color: p.ink3)),
                    ],
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}

class _ServerUnreachableNotice extends StatelessWidget {
  final NotebookListNotifier notifier;
  const _ServerUnreachableNotice({required this.notifier});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: notifier.serverUnreachable,
      builder: (_, down, __) {
        if (!down) return const SizedBox.shrink();
        return LayoutBuilder(builder: (ctx, c) {
          final compact = c.maxWidth < 600;
          return Container(
            width: double.infinity,
            color: p.paper2,
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 16 : 32, vertical: 10),
            child: Row(
              children: [
                HwIcon('cloud-off', size: 14, color: p.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.libServerUnreachable,
                          style: TextStyle(fontSize: 13, color: p.ink1)),
                      Text(l10n.libServerUnreachableHint,
                          style: TextStyle(fontSize: 11, color: p.ink3)),
                    ],
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}

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
  // Kept here on purpose: not syncing is the desired state, not a failure.
  if (e.localOnly || e.serverless) return HwSyncState.localOnly;
  // On the remote, deliberately not here. Checked before [isLocal] so the
  // stub card never reads as "waiting to upload".
  if (e.notOnDevice) return HwSyncState.notOnDevice;
  if (e.isLocal) return HwSyncState.pending;
  return HwSyncState.ok;
}

String _coverStyleName(AppLocalizations l10n, CoverStyle style) =>
    switch (style) {
      CoverStyle.auto => l10n.libCoverStyleAuto,
      CoverStyle.plain => l10n.libCoverStylePlain,
      CoverStyle.pinstripe => l10n.libCoverStylePinstripe,
      CoverStyle.diagonal => l10n.libCoverStyleDiagonal,
      CoverStyle.polka => l10n.libCoverStylePolka,
      CoverStyle.gingham => l10n.libCoverStyleGingham,
      CoverStyle.waves => l10n.libCoverStyleWaves,
      CoverStyle.label => l10n.libCoverStyleLabel,
      CoverStyle.twoTone => l10n.libCoverStyleTwoTone,
      CoverStyle.sheen => l10n.libCoverStyleSheen,
    };

/// One pattern choice in the cover sheet, drawn in the chosen color.
class _CoverStyleSwatch extends StatelessWidget {
  final Color color;
  final CoverStyle style;
  final BackgroundTexture texture;
  final bool selected;
  const _CoverStyleSwatch({
    required this.color,
    required this.style,
    required this.texture,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: selected ? p.ink0 : Colors.transparent, width: 2),
      ),
      child: NotebookCover(
        color: color,
        title: '',
        texture: texture,
        style: style,
        width: 44,
        height: 58,
      ),
    );
  }
}

// ─── New notebook dialog ──────────────────────────────────────────
class _NewNotebookResult {
  final String title;
  final Color coverColor;
  final CoverStyle coverStyle;
  final String paperType;
  final Size pageSize;
  _NewNotebookResult(this.title, this.coverColor, this.coverStyle,
      this.paperType, this.pageSize);
}

class _NewNotebookDialog extends StatefulWidget {
  const _NewNotebookDialog();
  @override
  State<_NewNotebookDialog> createState() => _NewNotebookDialogState();
}

class _NewNotebookDialogState extends State<_NewNotebookDialog> {
  final _titleCtrl = TextEditingController();
  Color _color = HwTheme.cover1;
  CoverStyle _style = CoverStyle.auto;
  String _paper = 'lined';
  PageSizePreset _pageSize = PageSizePreset.a4;
  bool _landscape = false;
  bool _showError = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _titleCtrl.text.trim();
    if (t.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context)
        .pop(_NewNotebookResult(t, _color, _style, _paper,
            pageSizeFor(_pageSize, landscape: _landscape)));
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleCtrl,
                autofocus: true,
                onChanged: (_) {
                  if (_showError) setState(() => _showError = false);
                },
                onEditingComplete: _submit,
                decoration: InputDecoration(
                  labelText: l10n.libNotebookTitleLabel,
                  errorText: _showError ? l10n.qlNameRequired : null,
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
              Text(l10n.libCoverPattern,
                  style: TextStyle(
                      fontSize: 11,
                      color: p.ink2,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final st in CoverStyle.values)
                    Tooltip(
                      message: _coverStyleName(l10n, st),
                      child: Semantics(
                        button: true,
                        selected: st == _style,
                        label: _coverStyleName(l10n, st),
                        child: GestureDetector(
                          onTap: () => setState(() => _style = st),
                          child: _CoverStyleSwatch(
                            color: _color,
                            style: st,
                            texture: coverTextureFor(_paper),
                            selected: st == _style,
                          ),
                        ),
                      ),
                    ),
                ],
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
              const SizedBox(height: 20),
              Text(l10n.pageSizeLabel,
                  style: TextStyle(
                      fontSize: 11,
                      color: p.ink2,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              PageSizePicker(
                preset: _pageSize,
                landscape: _landscape,
                onChanged: (preset, landscape) => setState(() {
                  _pageSize = preset;
                  _landscape = landscape;
                }),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.libCancel),
        ),
        FilledButton(
          onPressed: _submit,
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

/// Single-line name prompt with inline validation; Enter confirms.
class _NameDialog extends StatefulWidget {
  final String title;
  final String? hint;
  final String initial;
  final String confirmLabel;
  const _NameDialog({
    required this.title,
    this.hint,
    required this.initial,
    required this.confirmLabel,
  });

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);
  bool _showError = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        onChanged: (_) {
          if (_showError) setState(() => _showError = false);
        },
        onEditingComplete: _submit,
        decoration: InputDecoration(
          hintText: widget.hint,
          errorText: _showError ? l10n.qlNameRequired : null,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.libCancel)),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// "Choose a notebook": shown under the title while a tray is waiting.
class _TrayHint extends StatelessWidget {
  final PagesTray tray;
  final double hPad;
  const _TrayHint({required this.tray, required this.hPad});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: HwIcon(tray.isMove ? 'move' : 'paste',
              size: 16, color: p.accentDeep),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              tray.isMove
                  ? l.pgtLibHintMove(tray.count)
                  : l.pgtLibHintPaste(tray.count),
              style: TextStyle(fontSize: 13.5, height: 1.3, color: p.accentDeep)),
        ),
      ]),
    );
  }
}

/// Tag on the cover of the notebook a pending move comes from.
class _MovingBadge extends StatelessWidget {
  final int count;
  const _MovingBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
      decoration: BoxDecoration(
        color: p.paper0,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: p.ink0.withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        HwIcon('move', size: 13, color: p.accent),
        const SizedBox(width: 5),
        Text(AppLocalizations.of(context).pgtBadgeMoving(count),
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: p.ink0)),
      ]),
    );
  }
}
