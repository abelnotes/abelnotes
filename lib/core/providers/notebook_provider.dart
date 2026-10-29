import 'dart:async';
import 'dart:convert';
import 'package:abelnotes/core/platform/io.dart' show File, HandshakeException, SocketException;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/folder_sync_provider.dart';
import 'package:abelnotes/core/providers/remote_store_provider.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart' show canvasProvider;
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/pending_remote_deletes.dart';
import 'package:abelnotes/core/services/pending_root_uploads.dart';
import 'package:abelnotes/core/services/search_service.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/core/services/unpushed_guard.dart';
import 'package:abelnotes/features/pages_tray/application/pages_tray_provider.dart';
import 'package:abelnotes/core/services/remote_store.dart';

import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:uuid/uuid.dart';

/// Full-text search across locally-cached notebooks.
final searchServiceProvider = Provider<SearchService?>((ref) {
  final sync = ref.watch(syncServiceProvider);
  if (sync == null) return null;
  return SearchService(ref.watch(fileServiceProvider), sync);
});

/// Un notebook nella libreria (metadata + info remote).
class NotebookEntry {
  final NotebookMetadata metadata;
  final String remotePath;
  final DateTime? lastSynced;
  final bool isLocal; // creato localmente, non ancora sincronizzato

  /// The user asked for this notebook to stay on this device. Different from
  /// [isLocal], which means "not uploaded yet": this one is never going.
  final bool localOnly;

  /// The mirror image of [localOnly]: the notebook lives on the remote and
  /// this device was told not to keep it. The card is a stub — title and page
  /// count only — until the user opens it, which downloads it.
  final bool notOnDevice;

  /// No server is configured at all: nothing is pending, everything is local.
  final bool serverless;

  /// Its root file was never uploaded, so other devices can't see it at all.
  /// The rest of [isLocal] are notebooks already there with edits to send.
  final bool neverUploaded;

  const NotebookEntry({
    required this.metadata,
    required this.remotePath,
    this.lastSynced,
    this.isLocal = false,
    this.localOnly = false,
    this.notOnDevice = false,
    this.serverless = false,
    this.neverUploaded = false,
  });

  NotebookEntry copyWith({
    NotebookMetadata? metadata,
    String? remotePath,
    DateTime? lastSynced,
    bool? isLocal,
    bool? localOnly,
    bool? notOnDevice,
    bool? serverless,
    bool? neverUploaded,
  }) =>
      NotebookEntry(
        metadata: metadata ?? this.metadata,
        remotePath: remotePath ?? this.remotePath,
        lastSynced: lastSynced ?? this.lastSynced,
        isLocal: isLocal ?? this.isLocal,
        localOnly: localOnly ?? this.localOnly,
        notOnDevice: notOnDevice ?? this.notOnDevice,
        serverless: serverless ?? this.serverless,
        neverUploaded: neverUploaded ?? this.neverUploaded,
      );
}

/// Provider del SyncService.
final syncServiceProvider = Provider<SyncService?>((ref) {
  // Always non-null: SyncService's pure ZIP / loose-store helpers must work
  // in local-only mode (no server). `webdav` is null then, and any genuine
  // network call throws a clear "modalità solo-locale" error. Nullable type
  // kept for source compatibility with existing `== null` guards.
  final remote = ref.watch(remoteStoreProvider);
  final fileService = ref.watch(fileServiceProvider);
  final service = SyncService(remote, fileService);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider della lista notebook nella libreria.
final notebookListProvider =
    StateNotifierProvider<NotebookListNotifier, AsyncValue<List<NotebookEntry>>>(
        (ref) {
  final notifier = NotebookListNotifier(ref);
  ref.read(folderSyncProvider); // starts the edit-triggered folder sync
  // Connecting, disconnecting or re-authenticating changes what every card
  // should say; the list was only rebuilt on the next refresh.
  ref.listen(remoteStoreProvider, (prev, next) {
    unawaited(notifier.onRemoteChanged(hadRemote: prev != null));
  });
  return notifier;
});

class NotebookListNotifier
    extends StateNotifier<AsyncValue<List<NotebookEntry>>> {
  final Ref _ref;

  NotebookListNotifier(this._ref) : super(const AsyncValue.loading());

  /// True while a background sync with the server is running. The library UI
  /// watches this to distinguish "cold install, still fetching" from "really
  /// no notebooks" when the local DB is empty.
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  /// True once the remote has refused a write for lack of space.
  ///
  /// Worth its own flag rather than a passing error: it does not fix itself
  /// by waiting, the user has to go and free space, and until they do every
  /// upload will fail the same way. The library shows it until a sync
  /// succeeds.
  final ValueNotifier<bool> storageFull = ValueNotifier<bool>(false);

  /// The last library sync failed on the network, not on the server's
  /// answer: shown so a silent offline isn't mistaken for "all synced".
  final ValueNotifier<bool> serverUnreachable = ValueNotifier<bool>(false);

  /// Notebooks another device deleted while this one still held edits: kept
  /// here as local-only, listed until the user dismisses the notice.
  final ValueNotifier<Set<String>> deletedElsewhere =
      ValueNotifier<Set<String>>(const {});

  /// Notebooks whose pending edits touch what another device changed too: the
  /// editor's merge has to run, so they wait until opened.
  final ValueNotifier<Set<String>> needsOpenToUpload =
      ValueNotifier<Set<String>>(const {});
  static const _deletedElsewhereKey = 'qs_deleted_elsewhere_v1';

  /// Deleted on this device, id to remote stem: the server losing them is
  /// our own doing, not another device's.
  final Map<String, String> _deletedHere = {};

  bool isDeletedHere(String id) => _deletedHere.containsKey(id);

  Future<void> loadDeletedElsewhere() async {
    final prefs = await SharedPreferences.getInstance();
    final saved =
        (prefs.getStringList(_deletedElsewhereKey) ?? const <String>[]).toSet();
    // A notebook since trashed here leaves nothing to warn about.
    var kept = saved;
    try {
      final live = {
        for (final r
            in await _ref.read(fileServiceProvider).getAllNotebookMeta())
          r['id'] as String
      };
      kept = saved.where(live.contains).toSet();
    } catch (_) {}
    deletedElsewhere.value = kept;
    if (kept.length != saved.length) {
      await prefs.setStringList(_deletedElsewhereKey, kept.toList());
    }
  }

  Future<void> noteDeletedElsewhere(String id) async {
    if (isDeletedHere(id)) return;
    final next = {...deletedElsewhere.value, id};
    deletedElsewhere.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_deletedElsewhereKey, next.toList());
    if (mounted) await _loadFromLocalDb(_ref.read(fileServiceProvider));
  }

  Future<void> dismissDeletedElsewhere([String? id]) async {
    final next = id == null ? <String>{} : ({...deletedElsewhere.value}..remove(id));
    deletedElsewhere.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_deletedElsewhereKey, next.toList());
  }

  /// The remote client was replaced: connect, disconnect or new credentials.
  Future<void> onRemoteChanged({required bool hadRemote}) async {
    if (!mounted) return;
    await _loadFromLocalDb(_ref.read(fileServiceProvider));
    // A re-login keeps the library on screen with no connect event of its own.
    if (hadRemote && _ref.read(remoteStoreProvider) != null && mounted) {
      await syncNow(showProgress: false);
    }
  }

  /// Pull what the server has, then push what is waiting.
  Future<void> syncNow({bool showProgress = true}) async {
    if (isSyncing.value) return;
    await refresh(showProgress: showProgress);
    if (!mounted) return;
    try {
      await retryPendingUploads();
    } catch (e) {
      debugPrint('[Library] Retry after refresh failed: $e');
    }
  }

  /// Notebooks deleted here whose remote copy is still waiting to go.
  final ValueNotifier<int> pendingRemoteDeletes = ValueNotifier<int>(0);

  /// Progress during first sync: "downloaded/total" where 0/0 means PROPFIND
  /// is still in flight. UI shows this beside the spinner so first-install
  /// users can tell work is happening.
  final ValueNotifier<({int done, int total})> syncProgress =
      ValueNotifier<({int done, int total})>((done: 0, total: 0));

  @override
  void dispose() {
    isSyncing.dispose();
    storageFull.dispose();
    serverUnreachable.dispose();
    deletedElsewhere.dispose();
    needsOpenToUpload.dispose();
    pendingRemoteDeletes.dispose();
    syncProgress.dispose();
    super.dispose();
  }

  /// Carica la lista dei notebook dal server, con fallback locale offline.
  ///
  /// [showProgress] drives the "syncing with server" banner. The periodic
  /// background tick passes false: the user didn't ask for that sync and a
  /// banner blinking on its own every few minutes reads as a glitch.
  Future<void> refresh({bool showProgress = true}) async {
    final fileService = _ref.read(fileServiceProvider);

    // The symbol library rides along with the library refresh — which runs at
    // launch and on pull-to-refresh — instead of owning a timer of its own.
    // Costs one version check when nothing changed, and means the symbols are
    // already there by the time the user opens a notebook. Unawaited: the
    // notebook list must never wait on it.
    unawaited(_ref.read(symbolLibraryServiceProvider).reconcile());

    // ── Step 1: Show cached notebooks instantly from local DB ──
    await _loadFromLocalDb(fileService);

    // ── Step 2: Sync with server in background ──
    if (showProgress) isSyncing.value = true;
    try {
      final syncService = _ref.read(syncServiceProvider);
      final webdav = _ref.read(remoteStoreProvider);
      if (syncService == null || webdav == null) return;

      await _syncWithServer(syncService, webdav, fileService);
      if (mounted) serverUnreachable.value = false;
    } on RemoteStorageFullException catch (e) {
      debugPrint('[Library] Remote is out of space: $e');
      storageFull.value = true;
    } catch (e) {
      debugPrint('[Library] Remote sync failed: $e');
      if (mounted && _isNetworkError(e)) serverUnreachable.value = true;
      // Local data is already shown — no need to show error
    } finally {
      if (mounted) {
        // syncProgress is always reset, banner or not: _syncWithServer sets
        // it while downloading, and a leftover count would flash on the next
        // visible sync before its own PROPFIND lands.
        if (showProgress) isSyncing.value = false;
        syncProgress.value = (done: 0, total: 0);
      }
    }
  }

  static bool _isNetworkError(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException ||
      e is http.ClientException;

  /// Re-reads the cards from the local database, without touching the server.
  Future<void> reloadFromLocal() => _loadFromLocalDb(_ref.read(fileServiceProvider));

  /// Build notebook entries directly from local SQLite metadata (no ZIP parsing).
  Future<void> _loadFromLocalDb(FileService fileService) async {
    final allMeta = await fileService.getAllNotebookMeta();
    if (allMeta.isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }

    // A root file still queued means other devices can't see the notebook,
    // whatever the delta sync says: the card must not read as synced.
    final pendingRoots = await PendingRootUploads.load();
    pendingRemoteDeletes.value = (await PendingRemoteDeletes.load()).length;
    final serverless = _ref.read(syncServiceProvider)?.isOffline ?? true;
    final entries = <NotebookEntry>[];
    for (final row in allMeta) {
      if (isDeletedHere(row['id'] as String)) continue;
      final e = _notebookEntryFromRow(row);
      entries.add(e.copyWith(
        isLocal: e.isLocal || pendingRoots.contains(e.metadata.id),
        neverUploaded: pendingRoots.contains(e.metadata.id),
        serverless: serverless,
      ));
    }
    entries.sort((a, b) => b.metadata.modifiedAt.compareTo(a.metadata.modifiedAt));
    state = AsyncValue.data(entries);
  }

  /// Create a NotebookEntry from a DB row without parsing ZIP.
  NotebookEntry _notebookEntryFromRow(Map<String, dynamic> row) {
    return NotebookEntry(
      metadata: NotebookMetadata(
        id: row['id'] as String,
        title: row['title'] as String? ?? 'Untitled',
        createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
        modifiedAt: DateTime.tryParse(row['local_modified_at'] as String? ?? '') ?? DateTime.now(),
        coverColor: row['cover_color'] as int? ?? 0xFF1565C0,
        coverStyle: row['cover_style'] as String? ?? 'default',
        paperType: row['paper_type'] as String? ?? 'lined',
        pageCount: row['page_count'] as int? ?? 0,
      ),
      remotePath: row['remote_path'] as String? ?? '',
      lastSynced: row['remote_modified_at'] != null
          ? DateTime.tryParse(row['remote_modified_at'] as String)
          : null,
      isLocal: row['sync_status'] != 'synced',
      localOnly: (row['local_only'] as int? ?? 0) == 1,
      notOnDevice: (row['download_skipped'] as int? ?? 0) == 1,
    );
  }

  /// Sync with server: only download notebooks whose ETag has changed.
  /// Detects remote deletions and parallelizes downloads.
  Future<void> _syncWithServer(
    SyncService syncService,
    RemoteStore remote,
    FileService fileService,
  ) async {
    await remote.ensureBaseDirectory();
    final root = await syncService.listRemoteRoot();
    unawaited(_ref.read(folderSyncProvider).sync(root: root));
    final remoteFiles = await _adoptStorageExtension(
        remote, syncService, SyncService.notebooksIn(root));
    debugPrint('[Library] PROPFIND returned ${remoteFiles.length} .ncnote files');

    // Build map of locally cached ETags keyed by remote path, without the
    // extension: a rename half-done by another device must still match.
    final localRows = await fileService.getAllNotebookMeta();
    final localByPath = <String, Map<String, dynamic>>{};
    for (final row in localRows) {
      final rp = row['remote_path'] as String? ?? '';
      if (rp.isNotEmpty) localByPath[AppConfig.notebookStem(rp)] = row;
    }

    // Track which remote paths we've seen (to detect deletions)
    final seenRemotePaths = <String>{};
    var changed = false;
    final skipped = <String>[];

    // ── Identify which notebooks need downloading ──
    final toDownload = <({String remotePath, RemoteItem file})>[];
    // Rows we deliberately don't download but still want an accurate card
    // for: refreshed from the tiny delta metadata further down.
    final metaOnlyRows = <Map<String, dynamic>>[];
    // Deleted here, remote delete still queued: downloading it would bring
    // the notebook straight back.
    final deletingPaths = {
      for (final rp in (await PendingRemoteDeletes.load()).values)
        AppConfig.notebookStem(rp),
      ..._deletedHere.values,
    };
    for (final file in remoteFiles) {
      final remotePath = '${AppConfig.defaultRemotePath}${file.name}';
      final stem = AppConfig.notebookStem(remotePath);
      seenRemotePaths.add(stem);
      if (deletingPaths.contains(stem)) continue;

      final localRow = localByPath[stem];
      final localEtag = localRow?['etag'] as String?;

      // This device was told not to keep this notebook. It stays a stub card
      // until the user opens it; the opener downloads on demand.
      if (localRow != null && (localRow['download_skipped'] as int? ?? 0) == 1) {
        metaOnlyRows.add(localRow);
        continue;
      }

      // Skip if ETag matches — notebook hasn't changed on the server.
      if (localEtag != null && localEtag == file.version) continue;

      // Skip if the currently-open notebook in the canvas owns this row.
      // The canvas has an authoritative in-memory state and just persisted
      // the fresh version locally via _savePulledChangesLocally / save().
      // Overwriting its .ncnote with the server's stale root ZIP while the
      // user is editing would trample pulled pages (the "orphan page_071
      // hydrated then vanished" bug).
      if (localRow != null) {
        final lrId = localRow['id'] as String?;
        final canvasOpenId = _ref.read(canvasProvider)?.metadata.id;
        if (lrId != null && canvasOpenId == lrId) {
          debugPrint('[Library] Skipping .ncnote download for $remotePath '
              '(notebook is open in canvas, which owns the local copy)');
          continue;
        }
      }

      // Skip downloading the server .ncnote if a local row AND a delta
      // folder exist on the server.  Delta sync is authoritative for
      // these notebooks and the root .ncnote is a legacy snapshot that
      // no delta-era writer updates; it's typically stale by minutes to
      // hours. Downloading it would rewrite the local cache with old
      // content and reset the library page count (the bug where AICD's
      // 71st hydrated page was immediately overwritten back to 70 by
      // the following library refresh).
      //
      // Falls back to the normal timestamp-based check when the delta
      // folder check fails (network glitch, or genuinely absent delta
      // folder for a legacy single-device notebook).
      if (localRow != null) {
        final lrId = localRow['id'] as String?;
        if (lrId != null) {
          bool deltaAlive = false;
          try {
            deltaAlive = await syncService.deltaFolderExists(lrId);
          } catch (_) {
            // Network/uncertainty — let the timestamp check below decide.
            deltaAlive = false;
          }
          if (deltaAlive) {
            debugPrint('[Library] Skipping .ncnote download for $remotePath '
                '(delta folder on server is authoritative)');
            // The root changed (rename, cover, tags): pick up the title and
            // cover from the delta metadata, which those edits also patch.
            metaOnlyRows.add(localRow);
            continue;
          }
        }
      }

      // Skip downloading the server .ncnote if local data is NEWER.
      // Notebooks that use delta sync are never re-packaged into the server
      // .ncnote — their local copy is always more up-to-date than the static
      // file on the server.  Re-downloading would corrupt the local cache
      // with stale data and reset the library page-count to an old value.
      // The pull timer inside CanvasNotifier handles actual remote-change
      // detection for delta notebooks.
      if (localRow != null && file.lastModified != null) {
        final localModAt = localRow['local_modified_at'] as String?;
        if (localModAt != null) {
          final localDt = DateTime.tryParse(localModAt);
          if (localDt != null && localDt.isAfter(file.lastModified!)) {
            debugPrint('[Library] Skipping .ncnote download for $remotePath '
                '(local $localDt > server ${file.lastModified})');
            // Even though we skip the download, refresh the DB from the local
            // .ncnote so the library card always shows correct page-count/title.
            // Without this, a notebook that was never opened on this device
            // (so _savePulledChangesLocally never ran) can show stale metadata.
            final nbId = localRow['id'] as String;
            try {
              final localBytes = await fileService.readNotebookFile(nbId);
              if (localBytes != null) {
                final parsed = syncService.parseNcnoteMetadata(localBytes);
                final existingPageCount = localRow['page_count'] as int? ?? 0;
                if (parsed.metadata.pageCount != existingPageCount) {
                  await fileService.refreshNotebookCard(
                    id: nbId,
                    title: parsed.metadata.title,
                    localModifiedAt: parsed.metadata.modifiedAt,
                    coverColor: parsed.metadata.coverColor,
                    coverStyle: parsed.metadata.coverStyle,
                    paperType: parsed.metadata.paperType,
                    pageCount: parsed.metadata.pageCount,
                    createdAt: parsed.metadata.createdAt,
                  );
                  changed = true;
                }
              }
            } catch (e) {
              debugPrint('[Library] Could not refresh DB from local cache for $nbId: $e');
            }
            continue;
          }
        }
      }

      toDownload.add((remotePath: remotePath, file: file));
    }

    // ── Download changed/new notebooks in parallel (max 4 concurrent) ──
    if (toDownload.isNotEmpty) {
      debugPrint('[Library] Downloading ${toDownload.length} changed notebooks');
      syncProgress.value = (done: 0, total: toDownload.length);
      const maxConcurrent = 4;
      var completed = 0;
      for (var i = 0; i < toDownload.length; i += maxConcurrent) {
        if (!mounted) return; // notifier disposed
        final batch = toDownload.skip(i).take(maxConcurrent);
        final futures = batch.map((item) =>
            _downloadAndCache(remote, syncService, fileService, item.remotePath, item.file));
        final results = await Future.wait(futures);
        if (results.any((ok) => ok)) changed = true;
        skipped.addAll(results
            .asMap()
            .entries
            .where((e) => !e.value)
            .map((e) => toDownload[i + e.key].file.name));
        completed += results.length;
        syncProgress.value = (done: completed, total: toDownload.length);
        // Incrementally refresh the library while the batch drains so
        // already-downloaded notebooks appear before the whole sync finishes.
        if (changed && mounted) {
          await _loadFromLocalDb(fileService);
        }
      }
    }

    // ── Lightweight library-meta refresh for ETag-unchanged notebooks ──
    //
    // The root `.ncnote` ETag doesn't move when another device delta-syncs
    // (it writes to `.sync/<id>/*` and never re-packs the root), so the
    // ETag-skip above can leave the library card stuck at an old page
    // count even though the real content moved on.  Fix: for every
    // ETag-unchanged notebook, fetch ONLY `.sync/<id>/metadata.json` (tiny)
    // and upsert its pageCount/title into SQLite.  This is much cheaper
    // than downloading the whole delta tree but keeps the library card
    // accurate between opens.
    final etagUnchanged = <Map<String, dynamic>>[];
    for (final file in remoteFiles) {
      final remotePath = '${AppConfig.defaultRemotePath}${file.name}';
      final localRow = localByPath[AppConfig.notebookStem(remotePath)];
      if (localRow == null) continue;
      final localEtag = localRow['etag'] as String?;
      if (localEtag == null || localEtag != file.version) continue;
      // Only ETag-unchanged notebooks that we didn't already redownload.
      etagUnchanged.add(localRow);
    }
    for (final row in metaOnlyRows) {
      if (!etagUnchanged.any((r) => r['id'] == row['id'])) etagUnchanged.add(row);
    }
    if (etagUnchanged.isNotEmpty && mounted) {
      const metaConcurrency = 6;
      for (var i = 0; i < etagUnchanged.length; i += metaConcurrency) {
        if (!mounted) return;
        final batch = etagUnchanged.skip(i).take(metaConcurrency).toList();
        final metas = await Future.wait(batch.map((row) {
          final id = row['id'] as String;
          return syncService.downloadDeltaMetadataOnly(id);
        }));
        for (var k = 0; k < batch.length; k++) {
          final row = batch[k];
          final deltaMeta = metas[k];
          if (deltaMeta == null) continue;
          final id = row['id'] as String;
          // A rename/cover/tag edit not yet on the server: the remote copy is
          // the stale side, and copying it here would undo the edit.
          if ((await fileService.dirtyPagesOf(id)).contains('meta')) continue;
          await _mirrorMetaLocally(fileService, deltaMeta);
          final existingCount = row['page_count'] as int? ?? 0;
          final existingTitle = row['title'] as String? ?? '';
          final existingModified =
              DateTime.tryParse(row['local_modified_at'] as String? ?? '');
          // Skip the UPDATE when nothing user-visible differs — avoids
          // spurious SQLite writes and library rebuilds. The timestamp has
          // to be part of that: a sketch is always one page with the same
          // title, so on count+title alone its card would never move, and
          // editing it on another device would leave this one showing a
          // stale "modified 3 days ago" forever.
          if (existingCount == deltaMeta.pageCount &&
              existingTitle == deltaMeta.title &&
              existingModified != null &&
              !deltaMeta.modifiedAt.isAfter(existingModified)) {
            continue;
          }
          await fileService.refreshNotebookCard(
            id: id,
            title: deltaMeta.title,
            localModifiedAt: deltaMeta.modifiedAt,
            coverColor: deltaMeta.coverColor,
            coverStyle: deltaMeta.coverStyle,
            paperType: deltaMeta.paperType,
            pageCount: deltaMeta.pageCount,
            createdAt: deltaMeta.createdAt,
          );
          changed = true;
        }
      }
    }

    // ── Detect remote deletions: remove notebooks no longer on server ──
    //
    // The PROPFIND only lists root-level `.ncnote` files. A notebook whose
    // root `.ncnote` is missing may still be alive via its delta folder
    // (another device may have deleted the legacy ZIP by accident, or a
    // pre-delta sync cycle never uploaded one). Before wiping the local
    // cache, verify the delta folder doesn't exist — without that check
    // we were silently destroying notebooks that the user had JUST been
    // editing on another device (the "AICD scompare dalla libreria" bug).
    //
    // Also: never touch a notebook that's currently open in the canvas.
    // Deleting its files out from under the user mid-edit is catastrophic.
    final openIdForRemoval = _ref.read(canvasProvider)?.metadata.id;
    for (final row in localRows) {
      final rp = row['remote_path'] as String? ?? '';
      final syncStatus = row['sync_status'] as String? ?? '';
      final id = row['id'] as String;
      if (rp.isEmpty || syncStatus != 'synced') continue;
      // Kept on this device on purpose: not being on the remote is its
      // normal state, not proof the user deleted it elsewhere.
      if ((row['local_only'] as int? ?? 0) == 1) continue;
      if (seenRemotePaths.contains(AppConfig.notebookStem(rp))) continue;
      if (id == openIdForRemoval) {
        debugPrint('[Library] Skipping remote-delete cleanup for $id — notebook is currently open');
        continue;
      }
      // Root .ncnote missing — check the delta folder. If it's still
      // there, the notebook is alive; just the legacy ZIP is gone.
      //
      // PARANOID default: assume alive on ANY uncertainty. deltaFolderExists
      // silently returns false on network errors, and we must never mistake
      // a Tailscale glitch or transient 5xx for "notebook was deleted" —
      // that mistake permanently wipes the local .ncnote + snapshots + DB
      // row for a notebook the user is still actively using.
      bool deltaAlive = true;
      bool deltaConfirmed = false;
      try {
        deltaAlive = await syncService.deltaFolderExists(id, fresh: true);
        deltaConfirmed = deltaAlive;
      } catch (e) {
        debugPrint('[Library] deltaFolderExists error for $id — assuming alive: $e');
        deltaAlive = true; // explicit: uncertainty ⇒ keep local
      }
      if (deltaAlive) {
        debugPrint('[Library] Root .ncnote missing for $id but delta folder alive — '
            'skipping cleanup (notebook still exists on server)');
        // Other devices discover notebooks only through the root file, so
        // without it this one stays invisible there. Pre-fix notebooks never
        // entered the pending set: heal them here.
        if (deltaConfirmed) {
          await PendingRootUploads.add(id);
          await _uploadPendingRoot(syncService, fileService, id);
        }
        continue;
      }
      debugPrint('[Library] Notebook $id removed from server, cleaning local cache');
      await fileService.deleteNotebook(id);
      changed = true;
    }

    if (skipped.isNotEmpty) {
      debugPrint('[Library] Skipped ${skipped.length} notebooks: $skipped');
    }

    // Reload from DB if anything changed
    if (changed && mounted) {
      await _loadFromLocalDb(fileService);
    }
  }

  /// `${title}_${uuid}` plus either notebook extension.
  static final _rootIdRe = RegExp(
      r'([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.(?:ncnote|abelnote)$');

  /// Legacy-named roots seen without a delta folder this session.
  final Set<String> _legacyWithoutDelta = {};

  /// Server files an older build named `.ncnote` get renamed to
  /// [AppConfig.storageExtension]. When the new name is already there, the old
  /// one is a root an older device re-uploaded under the name it remembered:
  /// stale by design (pages live in the delta folder), so it goes.
  ///
  /// Only notebooks with a delta folder are touched: builds up to 0.37.6 drop
  /// their local copy of a synced notebook whose root vanished unless that
  /// folder is there. The rest keep the old name until someone edits them.
  /// Returns the listing as it now stands; a failed rename keeps the old
  /// entry, which the stem-keyed matching in [_syncWithServer] still pairs.
  Future<List<RemoteItem>> _adoptStorageExtension(RemoteStore remote,
      SyncService syncService, List<RemoteItem> files) async {
    final names = {for (final f in files) f.name};
    final out = <RemoteItem>[];
    for (final f in files) {
      final next = AppConfig.toStorageName(f.name);
      if (next == f.name) {
        out.add(f);
        continue;
      }
      final twin = names.contains(next);
      final id = _rootIdRe.firstMatch(f.name)?.group(1);
      var hasDelta = false;
      if (id != null && !_legacyWithoutDelta.contains(f.name)) {
        try {
          hasDelta = await syncService.deltaFolderExists(id, fresh: true);
        } catch (_) {}
        if (!hasDelta) _legacyWithoutDelta.add(f.name);
      }
      if (!hasDelta) {
        // A twin with no delta folder would make both copies download every
        // pass; the new name stands for it.
        if (!twin) out.add(f);
        continue;
      }
      final from = '${AppConfig.defaultRemotePath}${f.name}';
      final to = '${AppConfig.defaultRemotePath}$next';
      try {
        if (twin) {
          await remote.delete(from);
          unawaited(CrashLogger.append('[Ext] dropped stale twin $from'));
        } else {
          await remote.rename(from, to);
          unawaited(CrashLogger.append('[Ext] renamed $from'));
          out.add(RemoteItem(
            path: to,
            name: next,
            isDirectory: false,
            contentLength: f.contentLength,
            version: f.version,
            lastModified: f.lastModified,
            contentType: f.contentType,
          ));
        }
      } catch (e) {
        debugPrint('[Library] Could not rename $from: $e');
        out.add(f);
      }
    }
    return out;
  }

  /// The card reads the DB row but the editor reads the stored metadata.json:
  /// a rename made elsewhere has to reach both or they disagree.
  Future<void> _mirrorMetaLocally(
      FileService fileService, NotebookMetadata remote) async {
    // The open editor owns its copy and merges the change itself.
    if (_ref.read(canvasProvider)?.metadata.id == remote.id) return;
    try {
      final f = File(
          p.join(fileService.notebookStoreDir(remote.id), AppConfig.metadataFile));
      if (!await f.exists()) return;
      final local = NotebookMetadata.fromJson(
          jsonDecode(utf8.decode(await f.readAsBytes())) as Map<String, dynamic>);
      if (!remote.modifiedAt.isAfter(local.modifiedAt) ||
          (local.title == remote.title &&
              local.coverColor == remote.coverColor &&
              listEquals(local.tags, remote.tags))) {
        return;
      }
      final patched = local.copyWith(
        title: remote.title,
        coverColor: remote.coverColor,
        tags: remote.tags,
        modifiedAt: remote.modifiedAt,
      );
      await fileService.saveNotebookIncremental(remote.id,
          metadataJson: Uint8List.fromList(utf8.encode(jsonEncode(patched.toJson()))));
    } catch (e) {
      debugPrint('[Library] Could not mirror metadata of ${remote.id}: $e');
    }
  }

  /// Download a single notebook's cache + library metadata.
  ///
  /// IMPORTANT: the `<name>.ncnote` file at the server root is NOT updated
  /// by other devices doing delta-sync — they write pages directly to the
  /// `.sync/<id>/` folder and never re-pack the monolithic ZIP.  Downloading
  /// the root `.ncnote` therefore yields a stale snapshot for the page
  /// count (often just "1 pagina" until the user opens the notebook).
  ///
  /// Two-stage strategy to keep the library fast AND show a correct count:
  ///   1. Cache the root `.ncnote` bytes as-is so `_openNotebook` has
  ///      something to open instantly offline.
  ///   2. Fetch ONLY `.sync/<id>/metadata.json` (tiny, ~1 KB) and use
  ///      that metadata to stamp the library card — gives real pageCount
  ///      without downloading all pages.  Pages are fetched on-demand by
  ///      the canvas pull timer when the notebook is opened.
  ///
  /// Previously this did a full `downloadExplodedFull` on every notebook
  /// on first-sync, which issued N+1 HTTP requests per notebook (N pages
  /// + assets + PROPFINDs).  For a library of 10 large notebooks this
  /// turned into 1000+ requests sequentially → "estremamente lento".
  Future<bool> _downloadAndCache(
    dynamic webdav,
    SyncService syncService,
    FileService fileService,
    String remotePath,
    RemoteItem file,
  ) async {
    const maxRetries = 2;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // ── Best-effort UUID extraction from filename ──────────────────
        // The app names new notebooks as `${sanitized_title}_${uuid}.ncnote`.
        // If the pattern matches we can kick off the delta-metadata GET in
        // PARALLEL with the root download, halving the per-notebook latency
        // on the initial sync pass.  If the filename doesn't embed a UUID,
        // fall back to sequential fetch after parsing the root ZIP.
        final uuidMatch = _rootIdRe.firstMatch(file.name);

        // ── Fast path: if we already have a local copy of this notebook AND
        // the delta folder is alive on the server, skip the big root .ncnote
        // download entirely. We only need the tiny `<id>/metadata.json`
        // (~1 KB) to refresh the library card; the canvas pull takes care
        // of pulling page content when the notebook is opened.
        //
        // Saves ~33 MB per library refresh for a heavy notebook whose root
        // .ncnote is stale anyway (nobody rewrites it in the delta era).
        if (uuidMatch != null) {
          final candidateId = uuidMatch.group(1)!;
          final hasLocal = await fileService.hasLocalCopy(candidateId);
          if (hasLocal) {
            try {
              final deltaMeta =
                  await syncService.downloadDeltaMetadataOnly(candidateId);
              if (deltaMeta != null) {
                final existing = await fileService.getNotebookMeta(candidateId);
                await fileService.upsertNotebookMeta(
                  id: candidateId,
                  title: deltaMeta.title,
                  remotePath: remotePath,
                  // Preserve the canvas-maintained etag + localModifiedAt —
                  // the library has no authority over those, they reflect
                  // the live delta state maintained by the canvas pull/save.
                  etag: existing?['etag'] as String?,
                  localModifiedAt: existing?['local_modified_at'] != null
                      ? DateTime.tryParse(
                              existing!['local_modified_at'] as String) ??
                          deltaMeta.modifiedAt
                      : deltaMeta.modifiedAt,
                  remoteModifiedAt: file.lastModified,
                  syncStatus: (existing?['sync_status'] as String?) ?? 'synced',
                  fileSize: existing?['file_size'] as int?,
                  coverColor: deltaMeta.coverColor,
                  coverStyle: deltaMeta.coverStyle,
                  paperType: deltaMeta.paperType,
                  pageCount: deltaMeta.pageCount,
                  createdAt: deltaMeta.createdAt,
                );
                debugPrint('[Library] Fast-path refresh for $candidateId '
                    '(delta-meta only, root .ncnote NOT downloaded, '
                    'pageCount=${deltaMeta.pageCount})');
                return true;
              }
            } catch (e) {
              debugPrint('[Library] Fast-path delta-meta fetch failed for '
                  '$candidateId, falling back to root download: $e');
              // Fall through to the slow path below.
            }
          }
        }

        final Future<NotebookMetadata?> deltaFut = uuidMatch != null
            ? syncService.downloadDeltaMetadataOnly(uuidMatch.group(1)!)
            : Future.value(null);

        // Use the long timeout for the root .ncnote — these can be 60+ MB
        // for heavy notebooks and the default 120 s deadline killed the
        // request mid-stream (Automotive notebook download timing out
        // after 2 minutes on Tailscale).
        final Uint8List fullData = await webdav.downloadFile(
          remotePath,
          timeoutSeconds: AppConfig.webdavLargeDownloadTimeoutSeconds,
        );

        // Validate ZIP integrity before touching anything else
        SyncService.validateNcnoteArchive(
            fullData, context: 'downloadAndCache $remotePath');

        // Parse metadata off the main thread (cheap, single-file decode)
        final rootMeta = await SyncService.parseNcnoteMetadataIsolate(fullData);

        // ── Get authoritative pageCount from delta folder if present ──
        NotebookMetadata libraryMeta = rootMeta;
        DateTime libraryModifiedAt = rootMeta.modifiedAt;
        NotebookMetadata? deltaMeta = await deltaFut;
        // If the filename didn't embed a UUID we couldn't start the delta
        // fetch in parallel — run it now with the real ID from metadata.
        if (deltaMeta == null && uuidMatch == null) {
          deltaMeta =
              await syncService.downloadDeltaMetadataOnly(rootMeta.id);
        }
        // Safety: a UUID-from-filename mismatch (user renamed file?) would
        // make the parallel fetch return the wrong metadata.  Trust the root
        // ZIP's ID — if the two diverge, fall back to a fresh fetch by the
        // real ID.
        if (deltaMeta != null &&
            uuidMatch != null &&
            deltaMeta.id != rootMeta.id) {
          deltaMeta = await syncService.downloadDeltaMetadataOnly(rootMeta.id);
        }
        if (deltaMeta != null) {
          libraryMeta = deltaMeta;
          libraryModifiedAt = deltaMeta.modifiedAt;
          debugPrint('[Library] Refreshed library meta for '
              '"${rootMeta.title}" from delta '
              '(pageCount=${deltaMeta.pageCount})');
        } else {
          // No delta metadata (legacy single-device notebook or transient
          // network failure) — fall back to the root .ncnote's metadata
          // and integrity-check it since it's now our source of truth.
          if (rootMeta.pageCount > 0) {
            final actualPages = syncService.extractAllPages(fullData);
            if (actualPages.length < rootMeta.pageCount) {
              throw CorruptedArchiveException(
                'Page count mismatch for $remotePath: '
                'metadata says ${rootMeta.pageCount} pages, '
                'archive contains ${actualPages.length}',
              );
            }
          }
        }

        // Save file ONLY if a local copy doesn't already exist. An
        // existing local .ncnote is always considered more authoritative
        // than the server's root ZIP: the delta-sync path writes pages
        // directly to .sync/<id>/* without updating the root ZIP, so the
        // root is typically stale by minutes to hours. Overwriting local
        // with the stale server ZIP would silently destroy pages the
        // canvas just pulled (the 'AICD saved 43 MB of strokes, library
        // refresh ran, now file is 33 MB and 10 MB of content is gone'
        // bug). First-time cache of a never-before-seen notebook still
        // works because then there is no local file.
        final hasLocal = await fileService.hasLocalCopy(rootMeta.id);
        // The root of a delta notebook is a stale snapshot: caching it would
        // make the notebook open blank offline. Left as a stub, it is
        // downloaded whole the first time it is opened.
        final stub = !hasLocal && deltaMeta != null;
        if (stub) {
          debugPrint('[Library] ${rootMeta.id} kept as a stub until opened');
        } else if (!hasLocal) {
          await fileService.saveNotebookFile(rootMeta.id, fullData);
          debugPrint('[Library] First-time cache of ${rootMeta.id} '
              '(${fullData.length} bytes from server root .ncnote)');
        } else {
          debugPrint('[Library] NOT overwriting local .ncnote for ${rootMeta.id} '
              '(local is canvas-maintained, server root ZIP is stale)');
        }
        await fileService.upsertNotebookMeta(
          id: rootMeta.id,
          title: libraryMeta.title,
          remotePath: remotePath,
          etag: file.version,
          localModifiedAt: libraryModifiedAt,
          remoteModifiedAt: file.lastModified,
          syncStatus: 'synced',
          fileSize: stub
              ? null
              : hasLocal
                  ? (await fileService.readNotebookFile(rootMeta.id))?.length ??
                      fullData.length
                  : fullData.length,
          coverColor: libraryMeta.coverColor,
          coverStyle: libraryMeta.coverStyle,
          paperType: libraryMeta.paperType,
          pageCount: libraryMeta.pageCount,
          createdAt: libraryMeta.createdAt,
        );
        if (stub) {
          await fileService.setNotebookDownloadSkipped(rootMeta.id, true);
        }
        return true;
      } catch (e) {
        if (e is CorruptedArchiveException) {
          debugPrint('[Library] CORRUPTED notebook ${file.name}: $e');
          return false;
        }
        if (attempt == maxRetries - 1) {
          debugPrint('[Library] FAILED to load ${file.name} after $maxRetries attempts: $e');
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    return false;
  }

  /// Crea un nuovo notebook vuoto. Salva localmente e tenta upload remoto.
  Future<NotebookEntry> createNotebook({
    required String title,
    String paperType = 'lined',
    int coverColor = 0xFF1565C0,
    String coverStyle = 'default',
    List<String> tags = const [],
    // Free-sketch mode: one big infinite canvas instead of A4 pages.
    // When true, `paperType` is forced to the infinite marker and the
    // single page uses [backgroundType] (blank/grid/dotted) for its
    // visible texture over a [AppConfig.scratchPageSize] square sheet.
    bool infinite = false,
    String backgroundType = 'dotted',
    String chapterTitle = 'Chapter 1',
    // Page size in points for paged notebooks; A4 when not given.
    double pageWidth = AppConfig.defaultPageWidth,
    double pageHeight = AppConfig.defaultPageHeight,
  }) async {
    final syncService = _ref.read(syncServiceProvider);
    final fileService = _ref.read(fileServiceProvider);

    const uuid = Uuid();
    final notebookId = uuid.v4();
    final now = DateTime.now();
    final pageId = uuid.v4();
    final chapterId = uuid.v4();

    // Infinite/scratch: the metadata paperType becomes the marker, the
    // single page is a big square, and its visible texture is `backgroundType`.
    final effectivePaperType =
        infinite ? AppConfig.infinitePaperType : paperType;
    final pageW = infinite ? AppConfig.scratchPageSize : pageWidth;
    final pageH = infinite ? AppConfig.scratchPageSize : pageHeight;
    final bgType = infinite ? backgroundType : paperType;

    final metadata = NotebookMetadata(
      id: notebookId,
      title: title,
      createdAt: now,
      modifiedAt: now,
      paperType: effectivePaperType,
      coverColor: coverColor,
      coverStyle: coverStyle,
      pageCount: 1,
      tags: tags,
      chapters: [
        Chapter(id: chapterId, title: chapterTitle, pageIds: [pageId]),
      ],
    );

    final document = DocumentStructure(
      notebookId: notebookId,
      pages: [
        PageEntry(
          pageId: pageId,
          pageNumber: 1,
          fileName: 'page_001.json',
          width: pageW,
          height: pageH,
          lastModified: now,
          chapterId: chapterId,
        ),
      ],
    );

    final pageData = PageData(
      pageId: pageId,
      pageNumber: 1,
      width: pageW,
      height: pageH,
      layers: RenderingLayers(
        background: BackgroundLayer(type: bgType),
        content: const [],
      ),
      createdAt: now,
      modifiedAt: now,
    );

    // Sanitizza il nome file
    final safeName = title
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
    final remotePath =
        '${AppConfig.defaultRemotePath}${safeName}_$notebookId${AppConfig.storageExtension}';

    // Always save locally first
    if (syncService != null) {
      final package = syncService.createNcnotePackage(
        metadata: metadata,
        document: document,
        pages: {'page_001.json': pageData},
      );
      await fileService.saveNotebookFile(notebookId, package);
      await fileService.upsertNotebookMeta(
        id: notebookId,
        title: title,
        remotePath: remotePath,
        localModifiedAt: now,
        syncStatus: 'modified',
        coverColor: coverColor,
        coverStyle: coverStyle,
        paperType: effectivePaperType,
        pageCount: 1,
        createdAt: now,
      );

      // The root is always queued; without a server nothing is attempted
      // (an upload could only fail) and the queue is worked off on connect.
      await PendingRootUploads.add(notebookId);
      if (!syncService.isOffline) {
        // Upload in the BACKGROUND — never on the path to the editor.
        //
        // This used to be awaited, so "new notebook"/"new sketch" sat on a
        // frozen library for as long as the first PUT took: ~2 s on a normal
        // connection, the full socket timeout on a flaky one, for a notebook
        // that is already safely on disk. Offline-first means the local write
        // above is the commit; the remote copy is catch-up work. The row stays
        // `modified` until the upload lands, which is what the pending-upload
        // badge is for, and a failure is just the next sync's job.
        _rootUploadsInFlight.add(notebookId);
        unawaited(() async {
          try {
            await syncService.uploadNotebook(
              remotePath: remotePath,
              metadata: metadata,
              document: document,
              pages: {'page_001.json': pageData},
            );
            await PendingRootUploads.remove(notebookId);
            await fileService.markNotebookSynced(notebookId, null);
            // Flip the card's "local only" badge off without a full refetch.
            final list = mounted ? state.valueOrNull : null;
            if (list != null) {
              state = AsyncValue.data([
                for (final e in list)
                  if (e.metadata.id == notebookId)
                    NotebookEntry(
                      metadata: e.metadata,
                      remotePath: e.remotePath,
                      lastSynced: DateTime.now(),
                      isLocal: false,
                    )
                  else
                    e,
              ]);
            }
          } catch (e) {
            debugPrint('[Library] Created notebook locally, sync deferred: $e');
            unawaited(CrashLogger.append('[Root] create upload $notebookId failed: $e'));
          } finally {
            _rootUploadsInFlight.remove(notebookId);
          }
        }());
      }
    }

    final entry = NotebookEntry(
      metadata: metadata,
      remotePath: remotePath,
      lastSynced: null,
      isLocal: true,
      serverless: syncService?.isOffline ?? true,
    );

    // Aggiungi alla lista
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([entry, ...current]);

    return entry;
  }

  /// Copies a notebook under a fresh id; the copy syncs as a new notebook.
  /// Returns null when this device holds no copy of the source.
  Future<NotebookEntry?> duplicateNotebook(
      NotebookEntry entry, String title) async {
    final syncService = _ref.read(syncServiceProvider);
    final fileService = _ref.read(fileServiceProvider);
    if (syncService == null) return null;
    final localData = await fileService.readNotebookFile(entry.metadata.id);
    if (localData == null) return null;

    final parsed = syncService.parseNcnoteMetadata(localData);
    final contents = syncService.extractNotebookContents(localData);
    const uuid = Uuid();
    final newId = uuid.v4();
    final now = DateTime.now();
    // Fresh page and chapter ids too: the copy must share no id with the
    // original anywhere.
    final pageIds = {for (final e in parsed.document.pages) e.pageId: uuid.v4()};
    final chapterIds = {for (final c in parsed.metadata.chapters) c.id: uuid.v4()};
    final metadata = parsed.metadata.copyWith(
      id: newId,
      title: title,
      createdAt: now,
      modifiedAt: now,
      chapters: [
        for (final c in parsed.metadata.chapters)
          Chapter(
            id: chapterIds[c.id]!,
            title: c.title,
            pageIds: [for (final id in c.pageIds) pageIds[id] ?? id],
          ),
      ],
    );
    final document = parsed.document.copyWith(
      notebookId: newId,
      pages: [
        for (final e in parsed.document.pages)
          e.copyWith(
            pageId: pageIds[e.pageId]!,
            chapterId: chapterIds[e.chapterId] ?? e.chapterId,
          ),
      ],
    );
    final pages = {
      for (final e in contents.pages.entries)
        e.key: e.value.copyWith(pageId: pageIds[e.value.pageId] ?? e.value.pageId),
    };

    final safeName = title
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
    final remotePath =
        '${AppConfig.defaultRemotePath}${safeName}_$newId${AppConfig.storageExtension}';

    final package = syncService.createNcnotePackage(
      metadata: metadata,
      document: document,
      pages: pages,
      assets: contents.assets.isNotEmpty ? contents.assets : null,
      symbolLibraries:
          contents.symbolLibraries.isNotEmpty ? contents.symbolLibraries : null,
    );
    await fileService.saveNotebookFile(newId, package);
    await fileService.upsertNotebookMeta(
      id: newId,
      title: title,
      remotePath: remotePath,
      localModifiedAt: now,
      syncStatus: 'modified',
      coverColor: metadata.coverColor,
      paperType: metadata.paperType,
      pageCount: metadata.pageCount,
      createdAt: now,
    );
    // A copy of a notebook kept off the cloud stays off the cloud.
    if (entry.localOnly) await fileService.setNotebookLocalOnly(newId, true);
    await PendingRootUploads.add(newId);
    if (_ref.read(remoteStoreProvider) != null && !entry.localOnly) {
      unawaited(uploadPendingRootFor(newId));
    }

    final copy = NotebookEntry(
      metadata: metadata,
      remotePath: remotePath,
      isLocal: true,
      localOnly: entry.localOnly,
      serverless: entry.serverless,
    );
    state = AsyncValue.data([copy, ...(state.valueOrNull ?? [])]);
    return copy;
  }

  /// Removes only the remote copy, leaving the notebook here untouched.
  ///
  /// For the user who takes a notebook off sync and asks for the uploaded
  /// copy to go too. Deliberately separate from [deleteNotebook]: this must
  /// never touch the local file or the trash.
  Future<void> deleteRemoteCopy(NotebookEntry entry) async {
    final remote = _ref.read(remoteStoreProvider);
    if (remote == null) return;
    try {
      await _deleteRoot(remote, entry.remotePath);
    } catch (e) {
      debugPrint('[Library] Remote copy delete failed: $e');
    }
    // The exploded folder is the real content; leaving it behind would let
    // another device treat the notebook as alive and re-upload it.
    try {
      await _ref.read(syncServiceProvider)?.deleteDeltaFolder(entry.metadata.id);
    } catch (e) {
      debugPrint('[Library] Delta folder delete failed: $e');
    }
  }

  /// Frees this device's copy, leaving the notebook on the remote.
  ///
  /// Not a deletion: the row stays, the card stays, and opening it downloads
  /// the notebook again. Never touches the remote or the trash. Returns the
  /// bytes freed. Throws [StateError] when the remote isn't known to hold
  /// everything (unsynced changes, or a local-only notebook).
  Future<int> evictLocalCopy(NotebookEntry entry) {
    final id = entry.metadata.id;
    return _ref.read(fileServiceProvider).evictLocalCopy(id);
  }

  /// Puts a notebook back in this device's care, without downloading it yet:
  /// the next library sync (or opening it) brings the content down.
  Future<void> keepOnDevice(NotebookEntry entry) async {
    final id = entry.metadata.id;
    await _ref.read(fileServiceProvider).setNotebookDownloadSkipped(id, false);
  }

  /// Soft-deletes a notebook: moves it to the local trash and removes it from
  /// the remote server. Can be undone via [restoreFromTrash]. `remotePending`
  /// is true when the remote delete failed and was queued for retry.
  Future<({String? trashId, bool remotePending})> deleteNotebook(
      NotebookEntry entry) async {
    final webdav = _ref.read(remoteStoreProvider);
    final fileService = _ref.read(fileServiceProvider);
    final thumbs = _ref.read(thumbnailServiceProvider);
    final id = entry.metadata.id;

    // Card goes now: the remote delete can take seconds, and reopening the
    // notebook meanwhile reads the vanishing server as a delete elsewhere.
    _deletedHere[id] = AppConfig.notebookStem(entry.remotePath);
    state = AsyncValue.data(
      (state.valueOrNull ?? []).where((e) => e.metadata.id != id).toList(),
    );

    var remotePending = false;
    if (webdav != null) {
      try {
        await _deleteRemoteNotebook(id, entry.remotePath);
      } catch (e) {
        debugPrint('[Library] Remote delete failed, queued: $e');
        unawaited(CrashLogger.append('[Delete] $id queued: $e'));
        await PendingRemoteDeletes.add(id, entry.remotePath);
        remotePending = true;
      }
      pendingRemoteDeletes.value = (await PendingRemoteDeletes.load()).length;
    }

    // Soft-delete locally: preserve the .ncnote in the trash so it can be restored.
    final String? trashId;
    try {
      trashId = await fileService.moveNotebookToTrash(entry.metadata.id);
    } catch (_) {
      _deletedHere.remove(id);
      if (mounted) await _loadFromLocalDb(fileService);
      rethrow;
    }

    // Best-effort thumbnail cleanup.
    try {
      await thumbs.deleteThumbnail(entry.metadata.id);
    } catch (_) {}

    if (deletedElsewhere.value.contains(id)) {
      await dismissDeletedElsewhere(id);
    }
    unawaited(
        _ref.read(pagesTrayProvider.notifier).onNotebookDeleted(entry.metadata.id));
    return (trashId: trashId, remotePending: remotePending);
  }

  /// Delta folder first: a root left behind is a stale copy the retry
  /// removes, a delta left behind makes other devices keep and re-upload it.
  Future<void> _deleteRemoteNotebook(String id, String remotePath) async {
    final remote = _ref.read(remoteStoreProvider);
    final syncService = _ref.read(syncServiceProvider);
    if (remote == null || syncService == null) {
      throw StateError('No remote to delete from');
    }
    await syncService.deleteDeltaFolder(id);
    await _deleteRoot(remote, remotePath);
  }

  /// The root under either spelling: another device may have renamed it
  /// since this one last listed the server.
  Future<void> _deleteRoot(RemoteStore remote, String remotePath) async {
    if (remotePath.isEmpty) return;
    final stem = AppConfig.notebookStem(remotePath);
    await remote.delete('$stem${AppConfig.storageExtension}');
    await remote.delete('$stem${AppConfig.legacyStorageExtension}');
  }

  Future<void> _retryPendingRemoteDeletes() async {
    final pending = await PendingRemoteDeletes.load();
    for (final e in pending.entries) {
      try {
        await _deleteRemoteNotebook(e.key, e.value);
        await PendingRemoteDeletes.remove(e.key);
        unawaited(CrashLogger.append('[Delete] ${e.key} remote delete done'));
      } catch (err) {
        unawaited(CrashLogger.append('[Delete] ${e.key} retry failed: $err'));
      }
    }
    if (pending.isNotEmpty && mounted) {
      pendingRemoteDeletes.value = (await PendingRemoteDeletes.load()).length;
    }
  }

  /// Restores a notebook from the trash. Re-uploads it to the remote on the
  /// next sync because it was deleted from the server.
  Future<void> restoreFromTrash(String trashId) async {
    final fileService = _ref.read(fileServiceProvider);
    final meta = await fileService.restoreFromTrash(trashId);
    final id = meta?['id'] as String?;
    if (id != null) {
      // Wanted back: cancel a queued remote delete, and re-upload the root
      // the delete may already have removed.
      _deletedHere.remove(id);
      await PendingRemoteDeletes.remove(id);
      await PendingRootUploads.add(id);
    }
    if (meta != null) await refresh();
  }

  /// Lists notebooks in the trash.
  Future<List<TrashEntry>> listTrash() {
    return _ref.read(fileServiceProvider).listTrash();
  }

  /// Permanently deletes a single trash entry.
  Future<void> purgeTrashEntry(String trashId) {
    return _ref.read(fileServiceProvider).purgeTrashEntry(trashId);
  }

  /// Permanently empties the trash.
  Future<void> emptyTrash() {
    return _ref.read(fileServiceProvider).emptyTrash();
  }

  /// Replaces the tag list on a notebook. Persists locally and re-uploads
  /// (best-effort). The `syncStatus` is flipped to `modified` so the next
  /// background sync picks it up when offline.
  /// Other devices read title, cover and tags from the delta metadata.json,
  /// not the root file the edits below rewrite. Patches only those fields on
  /// the server copy: the local metadata may be behind another device's.
  Future<void> _patchDeltaMetadata(
    SyncService syncService,
    String id,
    NotebookMetadata Function(NotebookMetadata) patch,
  ) async {
    final remote = await syncService.downloadDeltaMetadataOnly(id);
    if (remote == null) return; // no delta folder yet
    await syncService.replayMetadataCommit(
      notebookId: id,
      metadataBytes:
          Uint8List.fromList(utf8.encode(jsonEncode(patch(remote).toJson()))),
    );
  }

  Future<void> updateNotebookTags(NotebookEntry entry, List<String> tags) async {
    final syncService = _ref.read(syncServiceProvider);
    final webdav = _ref.read(remoteStoreProvider);
    final fileService = _ref.read(fileServiceProvider);

    final localData = await fileService.readNotebookFile(entry.metadata.id);
    if (localData == null || syncService == null) return;

    final result = syncService.parseNcnoteMetadata(localData);
    // Single ZIP walk for pages + assets + symbols (was 3 decodes).
    final contents = syncService.extractNotebookContents(localData);
    final allPages = contents.pages;
    final allAssets = contents.assets;
    final symbolLibraries = contents.symbolLibraries;

    // Normalize: trim, drop empties, dedup while preserving order.
    final seen = <String>{};
    final cleanTags = <String>[];
    for (final t in tags.map((e) => e.trim())) {
      if (t.isEmpty) continue;
      if (seen.add(t.toLowerCase())) cleanTags.add(t);
    }

    final updatedMeta = result.metadata.copyWith(
      tags: cleanTags,
      modifiedAt: DateTime.now(),
    );

    final package = syncService.createNcnotePackage(
      metadata: updatedMeta,
      document: result.document,
      pages: allPages,
      assets: allAssets.isNotEmpty ? allAssets : null,
      symbolLibraries: symbolLibraries.isNotEmpty ? symbolLibraries : null,
    );
    await fileService.saveNotebookFile(updatedMeta.id, package);
    await fileService.upsertNotebookMeta(
      id: updatedMeta.id,
      title: updatedMeta.title,
      remotePath: entry.remotePath,
      localModifiedAt: updatedMeta.modifiedAt,
      syncStatus: 'modified',
      coverColor: updatedMeta.coverColor,
      coverStyle: updatedMeta.coverStyle,
      paperType: updatedMeta.paperType,
      pageCount: updatedMeta.pageCount,
      createdAt: updatedMeta.createdAt,
    );

    var remoteDone = false;
    try {
      if (webdav != null) {
        final etag = await syncService.uploadNotebook(
          remotePath: entry.remotePath,
          metadata: updatedMeta,
          document: result.document,
          pages: allPages,
          assets: allAssets.isNotEmpty ? allAssets : null,
          symbolLibraries: symbolLibraries.isNotEmpty ? symbolLibraries : null,
        );
        await _patchDeltaMetadata(syncService, updatedMeta.id,
            (m) => m.copyWith(tags: cleanTags, modifiedAt: updatedMeta.modifiedAt));
        await fileService.markNotebookSynced(updatedMeta.id, etag);
        remoteDone = true;
      }
    } catch (e) {
      debugPrint('[Library] Tags uploaded locally, remote sync deferred: $e');
      // Stays pending until the delta metadata carries it: the library
      // retry patches it once the server answers.
      await fileService.addDirtyPages(updatedMeta.id, const ['meta']);
    }

    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.map((e) {
      if (e.metadata.id == entry.metadata.id) {
        return e.copyWith(metadata: updatedMeta, isLocal: !remoteDone);
      }
      return e;
    }).toList());
  }

  /// Change a notebook's cover colour. Same flow as [renameNotebook]:
  /// rebuild the local .ncnote with the new metadata, persist, mark
  /// dirty, and best-effort push to the server.
  Future<void> updateNotebookCover(
      NotebookEntry entry, int newCoverColor, String newCoverStyle) async {
    final syncService = _ref.read(syncServiceProvider);
    final webdav = _ref.read(remoteStoreProvider);
    final fileService = _ref.read(fileServiceProvider);

    final localData = await fileService.readNotebookFile(entry.metadata.id);
    if (localData == null || syncService == null) return;

    final result = syncService.parseNcnoteMetadata(localData);
    // Single ZIP walk for pages + assets + symbols (was 3 decodes).
    final contents = syncService.extractNotebookContents(localData);
    final allPages = contents.pages;
    final allAssets = contents.assets;
    final symbolLibraries = contents.symbolLibraries;

    final updatedMeta = result.metadata.copyWith(
      coverColor: newCoverColor,
      coverStyle: newCoverStyle,
      modifiedAt: DateTime.now(),
    );

    final package = syncService.createNcnotePackage(
      metadata: updatedMeta,
      document: result.document,
      pages: allPages,
      assets: allAssets.isNotEmpty ? allAssets : null,
      symbolLibraries: symbolLibraries.isNotEmpty ? symbolLibraries : null,
    );
    await fileService.saveNotebookFile(updatedMeta.id, package);
    await fileService.upsertNotebookMeta(
      id: updatedMeta.id,
      title: updatedMeta.title,
      remotePath: entry.remotePath,
      localModifiedAt: updatedMeta.modifiedAt,
      syncStatus: 'modified',
      coverColor: updatedMeta.coverColor,
      coverStyle: updatedMeta.coverStyle,
      paperType: updatedMeta.paperType,
      pageCount: updatedMeta.pageCount,
      createdAt: updatedMeta.createdAt,
    );

    var remoteDone = false;
    try {
      if (webdav != null) {
        final etag = await syncService.uploadNotebook(
          remotePath: entry.remotePath,
          metadata: updatedMeta,
          document: result.document,
          pages: allPages,
          assets: allAssets.isNotEmpty ? allAssets : null,
          symbolLibraries: symbolLibraries.isNotEmpty ? symbolLibraries : null,
        );
        await _patchDeltaMetadata(syncService, updatedMeta.id,
            (m) => m.copyWith(
              coverColor: newCoverColor,
              coverStyle: newCoverStyle,
              modifiedAt: updatedMeta.modifiedAt));
        await fileService.markNotebookSynced(updatedMeta.id, etag);
        remoteDone = true;
      }
    } catch (e) {
      debugPrint('[Library] Cover change saved locally, remote sync deferred: $e');
      // Stays pending until the delta metadata carries it: the library
      // retry patches it once the server answers.
      await fileService.addDirtyPages(updatedMeta.id, const ['meta']);
    }

    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.map((e) {
      if (e.metadata.id == entry.metadata.id) {
        return e.copyWith(metadata: updatedMeta, isLocal: !remoteDone);
      }
      return e;
    }).toList());
  }

  /// Rinomina un notebook.
  Future<void> renameNotebook(NotebookEntry entry, String newTitle) async {
    final syncService = _ref.read(syncServiceProvider);
    final webdav = _ref.read(remoteStoreProvider);
    final fileService = _ref.read(fileServiceProvider);

    // Use the local copy instead of downloading from remote.
    // This works offline and avoids overwriting unsaved local changes.
    final localData = await fileService.readNotebookFile(entry.metadata.id);
    if (localData == null) {
      // No local copy — can't rename
      debugPrint('[Library] Cannot rename: no local file for ${entry.metadata.id}');
      return;
    }

    if (syncService == null) return;

    final result = syncService.parseNcnoteMetadata(localData);
    // Single ZIP walk for pages + assets + symbols (was 3 decodes).
    final contents = syncService.extractNotebookContents(localData);
    final allPages = contents.pages;
    final allAssets = contents.assets;
    final symbolLibraries = contents.symbolLibraries;

    final updatedMeta = result.metadata.copyWith(
      title: newTitle,
      modifiedAt: DateTime.now(),
    );

    // Rebuild and save locally
    final package = syncService.createNcnotePackage(
      metadata: updatedMeta,
      document: result.document,
      pages: allPages,
      assets: allAssets.isNotEmpty ? allAssets : null,
      symbolLibraries: symbolLibraries.isNotEmpty ? symbolLibraries : null,
    );
    await fileService.saveNotebookFile(updatedMeta.id, package);
    await fileService.upsertNotebookMeta(
      id: updatedMeta.id,
      title: newTitle,
      remotePath: entry.remotePath,
      localModifiedAt: updatedMeta.modifiedAt,
      syncStatus: 'modified',
      coverColor: updatedMeta.coverColor,
      coverStyle: updatedMeta.coverStyle,
      paperType: updatedMeta.paperType,
      pageCount: updatedMeta.pageCount,
      createdAt: updatedMeta.createdAt,
    );

    // Try to upload to server (best-effort — succeeds when online)
    var remoteDone = false;
    try {
      if (webdav != null) {
        final etag = await syncService.uploadNotebook(
          remotePath: entry.remotePath,
          metadata: updatedMeta,
          document: result.document,
          pages: allPages,
          assets: allAssets.isNotEmpty ? allAssets : null,
          symbolLibraries: symbolLibraries.isNotEmpty ? symbolLibraries : null,
        );
        await _patchDeltaMetadata(syncService, updatedMeta.id,
            (m) => m.copyWith(title: newTitle, modifiedAt: updatedMeta.modifiedAt));
        await fileService.markNotebookSynced(updatedMeta.id, etag);
        remoteDone = true;
      }
    } catch (e) {
      debugPrint('[Library] Rename uploaded locally, remote sync deferred: $e');
      // Stays pending until the delta metadata carries it: the library
      // retry patches it once the server answers.
      await fileService.addDirtyPages(updatedMeta.id, const ['meta']);
    }

    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.map((e) {
      if (e.metadata.id == entry.metadata.id) {
        return e.copyWith(metadata: updatedMeta, isLocal: !remoteDone);
      }
      return e;
    }).toList());
  }

  /// Uploads the root `.ncnote` of notebooks whose create/import PUT never
  /// landed. A 404 check first: a rename or another retry may have written
  /// it since.
  Future<void> _uploadPendingRoots(
    SyncService syncService,
    FileService fileService,
  ) async {
    final pending = await PendingRootUploads.load();
    if (pending.isNotEmpty) {
      unawaited(CrashLogger.append('[Root] pending: ${pending.join(', ')}'));
    }
    for (final id in pending) {
      await _uploadPendingRoot(syncService, fileService, id);
    }
  }

  /// Root uploads running now, keyed by notebook id. Two writers on one root
  /// race the create-time size check, which deletes a file it sees mismatch.
  final Set<String> _rootUploadsInFlight = {};

  /// Called after a successful canvas delta sync: the network demonstrably
  /// works, while the library-driven retry only runs with the library on
  /// screen.
  Future<void> uploadPendingRootFor(String id) async {
    final syncService = _ref.read(syncServiceProvider);
    if (syncService == null || syncService.isOffline) return;
    if (!(await PendingRootUploads.load()).contains(id)) return;
    await _uploadPendingRoot(syncService, _ref.read(fileServiceProvider), id);
  }

  Future<void> _uploadPendingRoot(
    SyncService syncService,
    FileService fileService,
    String id,
  ) async {
    if (!_rootUploadsInFlight.add(id)) return;
    try {
      final row = await fileService.getNotebookMeta(id);
      final remotePath = row?['remote_path'] as String? ?? '';
      final localOnly = (row?['local_only'] as int? ?? 0) == 1;
      final bytes = row == null || localOnly || remotePath.isEmpty
          ? null
          : await fileService.readNotebookFile(id);
      if (bytes == null) {
        // Deleted, taken off the cloud, or nothing to send: not pending.
        unawaited(CrashLogger.append('[Root] $id dropped: '
            'row=${row != null} localOnly=$localOnly path=$remotePath'));
        await PendingRootUploads.remove(id);
        return;
      }
      // Under the old name it is there already; library sync renames it.
      if (!await syncService.notebookRootExists(remotePath)) {
        SyncService.validateNcnoteArchive(bytes, context: 'root retry $id');
        await syncService.uploadNcnoteZip(remotePath, bytes);
        storageFull.value = false;
        debugPrint('[Library] Uploaded missing root .ncnote for $id');
        unawaited(CrashLogger.append(
            '[Root] $id uploaded (${bytes.length} bytes) to $remotePath'));
      }
      await PendingRootUploads.remove(id);
      // The card reads the pending set: drop its pending badge now.
      if (mounted) await _loadFromLocalDb(fileService);
    } catch (e) {
      if (e is RemoteStorageFullException) storageFull.value = true;
      debugPrint('[Library] Root upload for $id failed: $e (will retry)');
      unawaited(CrashLogger.append('[Root] $id retry failed: $e'));
    } finally {
      _rootUploadsInFlight.remove(id);
    }
  }

  /// Best-effort re-upload of every notebook whose local sync status is still
  /// `modified` — i.e. previous save() couldn't reach the server (offline,
  /// Tailscale drop, Nextcloud restart). Driven by the library screen: once
  /// at cold boot, again the first time a server is connected mid-session,
  /// and on its periodic background-sync tick.
  ///
  /// Uses the local .ncnote as source of truth, pushes it via the delta-sync
  /// exploded folder. Failures are logged but never throw — the notebook stays
  /// marked `modified` so the next retry picks it up again.
  Future<void> retryPendingUploads() async {
    final syncService = _ref.read(syncServiceProvider);
    final fileService = _ref.read(fileServiceProvider);
    // Local-only mode: nothing to upload, and every server probe would just
    // throw. Bail before the loop instead of throwing once per notebook.
    if (syncService == null || syncService.isOffline) return;

    await _retryPendingRemoteDeletes();
    await _uploadPendingRoots(syncService, fileService);

    final dirtyRows = await fileService.getDirtyNotebooks();
    final stillDirty = {for (final r in dirtyRows) r['id'] as String};
    needsOpenToUpload.value =
        needsOpenToUpload.value.where(stillDirty.contains).toSet();
    if (dirtyRows.isEmpty) return;
    // Rows cleared below only reach the pending-uploads banner on a reload.
    try {
      await _retryDirtyRows(syncService, fileService, dirtyRows);
    } finally {
      if (mounted) await _loadFromLocalDb(fileService);
    }
  }

  /// Pushes what a closed notebook failed to upload (dirty_pages), but only
  /// when nobody changed it since this device last synced: the local copy is
  /// then a superset of the server's and needs no merge. Otherwise the
  /// editor does it on open, with its 3-way merge. A pending rename/cover/
  /// tag edit alone ('meta') is patched field by field either way.
  Future<void> _pushUnpushed(
      SyncService syncService, FileService fileService, String id) async {
    final keys = await fileService.dirtyPagesOf(id);
    if (keys.isEmpty) return;
    if (_ref.read(canvasProvider)?.metadata.id == id) return; // editor owns it
    final local = await syncService
        .loadLooseStoreFromDisk(fileService.notebookStoreDir(id));
    if (local == null) return;
    final m = local.metadata;
    if (keys.length == 1 && keys.contains('meta')) {
      await _patchDeltaMetadata(
          syncService,
          id,
          (r) => r.copyWith(
              title: m.title,
              coverColor: m.coverColor,
              coverStyle: m.coverStyle,
              tags: m.tags,
              modifiedAt: m.modifiedAt));
      await fileService.clearDirtyPages(id);
      unawaited(CrashLogger.append('[Unpushed] $id metadata patched'));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final known = prefs.getString('delta_meta_etag_$id');
    final remote = await syncService.getDeltaMetaEtag(id);
    if (known == null || remote == null) {
      unawaited(CrashLogger.append(
          '[Unpushed] $id left for the editor (server state unknown)'));
      return;
    }
    final serverMoved = remote != known;
    if (serverMoved && !await _serverMoveIsDisjoint(
        syncService, prefs, id, keys, local)) {
      needsOpenToUpload.value = {...needsOpenToUpload.value, id};
      unawaited(CrashLogger.append(
          '[Unpushed] $id left for the editor (server moved)'));
      return;
    }
    final pages = {
      for (final k in keys)
        if (local.pages.containsKey(k)) k: local.pages[k]!,
    };
    final assets = <String, Uint8List>{
      for (final k in keys)
        if (k.startsWith('asset:') && local.assets.containsKey(k.substring(6)))
          k.substring(6): local.assets[k.substring(6)]!,
    };
    // Deletions the editor queued but couldn't send (same keys it reads).
    final pageDeletes =
        prefs.getStringList('pending_page_deletes_$id') ?? const <String>[];
    final assetDeletes =
        prefs.getStringList('pending_asset_deletes_$id') ?? const <String>[];
    final res = await syncService.syncDelta(
      notebookId: id,
      metadata: m,
      document: local.document,
      dirtyPages: pages,
      dirtyAssets: assets.isEmpty ? null : assets,
      symbolLibraries:
          local.symbolLibraries.isNotEmpty ? local.symbolLibraries : null,
      deletedPageFileNames: pageDeletes.isEmpty ? null : pageDeletes,
      deletedAssetFileNames: assetDeletes.isEmpty ? null : assetDeletes,
    );
    // Deletes that failed come back; the rest are done.
    await prefs.setStringList(
        'pending_page_deletes_$id', res.failedPageDeletes);
    await prefs.setStringList(
        'pending_asset_deletes_$id', res.failedAssetDeletes);
    await prefs.remove('unpushed_base_doc_$id');
    await prefs.remove('unpushed_base_meta_$id');
    if (serverMoved) {
      // Other devices' changes are still to be pulled: keep the old meta etag
      // so the editor sees them, and only record the pages sent here.
      await _recordPushedPageEtags(prefs, id, res.pageEtags);
    } else {
      // Same key the editor reads, so its first pull knows this is ours.
      final etag = res.metaEtag;
      if (etag != null && etag.isNotEmpty) {
        await prefs.setString('delta_meta_etag_$id', etag);
      }
    }
    await fileService.clearDirtyPages(id);
    if (mounted) {
      needsOpenToUpload.value = ({...needsOpenToUpload.value}..remove(id));
    }
    storageFull.value = false; // the server just took a write
    unawaited(CrashLogger.append(
        '[Unpushed] $id pushed ${pages.length} pages, ${assets.length} assets'));
  }

  Future<bool> _serverMoveIsDisjoint(
      SyncService syncService,
      SharedPreferences prefs,
      String id,
      Set<String> keys,
      LooseStoreContents local) async {
    try {
      final knownRaw = prefs.getString('page_etags_$id');
      final knownPages = knownRaw == null
          ? <String, String>{}
          : (jsonDecode(knownRaw) as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as String));
      final baseDocRaw = prefs.getString('unpushed_base_doc_$id');
      final baseMetaRaw = prefs.getString('unpushed_base_meta_$id');
      final server = await syncService.downloadDeltaMeta(id);
      return serverMoveIsDisjoint(
        dirtyPageKeys: keys,
        knownPageEtags: knownPages,
        serverPageEtags: await syncService.getRemotePageEtags(id),
        baseDocument: baseDocRaw != null
            ? DocumentStructure.fromJson(
                jsonDecode(baseDocRaw) as Map<String, dynamic>)
            : local.document,
        serverDocument: server.document,
        baseMetadata: baseMetaRaw != null
            ? NotebookMetadata.fromJson(
                jsonDecode(baseMetaRaw) as Map<String, dynamic>)
            : local.metadata,
        serverMetadata: server.metadata,
      );
    } catch (e) {
      debugPrint('[Library] Cannot tell whether $id moved elsewhere: $e');
      return false;
    }
  }

  Future<void> _recordPushedPageEtags(SharedPreferences prefs, String id,
      Map<String, String> pushed) async {
    if (pushed.isEmpty) return;
    Map<String, String> known = {};
    try {
      final raw = prefs.getString('page_etags_$id');
      if (raw != null) {
        known = (jsonDecode(raw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as String));
      }
    } catch (_) {}
    await prefs.setString('page_etags_$id', jsonEncode({...known, ...pushed}));
  }

  /// True when the notebook was on the server and its folder and root file
  /// are both gone now. Throws if the server can't say.
  Future<bool> _deletedOnServer(SyncService syncService,
      FileService fileService, String id, Map<String, dynamic> row) async {
    if ((await PendingRootUploads.load()).contains(id)) return false;
    final prefs = await SharedPreferences.getInstance();
    final wasOnServer =
        row['etag'] != null || prefs.getString('delta_meta_etag_$id') != null;
    if (!wasOnServer) return false;
    if (await syncService.deltaFolderExists(id, fresh: true)) return false;
    final root = row['remote_path'] as String? ?? '';
    return root.isEmpty || await syncService.notebookRootAbsent(root);
  }

  Future<void> _keepAfterRemoteDelete(FileService fileService, String id) async {
    await fileService.setNotebookLocalOnly(id, true);
    await fileService.clearDirtyPages(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('delta_meta_etag_$id');
    await prefs.remove('page_etags_$id');
    unawaited(CrashLogger.append(
        '[Sync] $id deleted on the server: kept on this device only'));
    await noteDeletedElsewhere(id);
  }

  /// "Sync this notebook again": lets the notebook sync and makes the server
  /// match it now. A copy still on the server is merged by the editor as
  /// usual; a missing one (deleted elsewhere, or never uploaded) is rebuilt
  /// whole, root file and delta folder together. Returns false when the
  /// server could not be reached or the editor has to merge: the notebook
  /// then waits as pending.
  Future<bool> resumeSync(NotebookEntry entry) async {
    final id = entry.metadata.id;
    final fileService = _ref.read(fileServiceProvider);
    await fileService.setNotebookLocalOnly(id, false);
    await fileService.markNotebookDirty(id);
    await dismissDeletedElsewhere(id);
    final syncService = _ref.read(syncServiceProvider);
    if (syncService == null || syncService.isOffline) return false;
    try {
      await _syncNotebookNow(syncService, fileService, id);
      return (await fileService.dirtyPagesOf(id)).isEmpty;
    } catch (e) {
      debugPrint('[Library] Resume sync of $id deferred: $e');
      return false;
    } finally {
      if (mounted) await _loadFromLocalDb(fileService);
    }
  }

  Future<void> _syncNotebookNow(
      SyncService syncService, FileService fileService, String id) async {
    final alive = await syncService.deltaFolderExists(id, fresh: true);
    if (alive) {
      await _pushUnpushed(syncService, fileService, id);
      if ((await fileService.dirtyPagesOf(id)).isEmpty) {
        final row = await fileService.getNotebookMeta(id);
        await fileService.markNotebookSynced(id, row?['etag'] as String?);
      }
    } else {
      final local = await syncService
          .loadLooseStoreFromDisk(fileService.notebookStoreDir(id));
      if (local == null) throw StateError('No local copy of $id');
      // A stale baseline would read the rebuilt pages as foreign changes.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('delta_meta_etag_$id');
      await prefs.remove('page_etags_$id');
      final res = await syncService.syncDelta(
        notebookId: id,
        metadata: local.metadata,
        document: local.document,
        dirtyPages: local.pages,
        dirtyAssets: local.assets.isEmpty ? null : local.assets,
        symbolLibraries:
            local.symbolLibraries.isEmpty ? null : local.symbolLibraries,
      );
      final etag = res.metaEtag;
      if (etag != null && etag.isNotEmpty) {
        await prefs.setString('delta_meta_etag_$id', etag);
      }
      await fileService.clearDirtyPages(id);
      await fileService.markNotebookSynced(id, etag);
    }
    // Both cases: the root file other devices list must be there too.
    await _uploadPendingRoot(syncService, fileService, id);
  }

  Future<void> _retryDirtyRows(
    SyncService syncService,
    FileService fileService,
    List<Map<String, dynamic>> dirtyRows,
  ) async {
    debugPrint('[Library] Retrying ${dirtyRows.length} pending notebook uploads');
    unawaited(CrashLogger.append(
      '[Retry] ${dirtyRows.length} pending notebooks to re-upload',
    ));

    for (final row in dirtyRows) {
      final id = row['id'] as String?;
      final remotePath = row['remote_path'] as String?;
      if (id == null || remotePath == null || remotePath.isEmpty) continue;
      if (isDeletedHere(id)) continue;

      // ── SAFETY: never retry-upload a notebook whose delta folder is
      // alive on the server. Re-uploading ALL pages as 'dirty' would
      // overwrite whatever another device (e.g. iPad) uploaded while this
      // device was offline — and it usually DID, because the whole point
      // of cross-device sync is that other devices make progress too.
      //
      // The canvas pull/save path handles per-page reconciliation with
      // proper dirty-detection. If this notebook has any local-only
      // changes, those will be uploaded when the user next opens it.
      //
      // This retry path is now only for legacy notebooks that were
      // created offline and never made it to the delta folder at all —
      // i.e. the original 'created local, immediate sync attempt failed'
      // scenario this retry was added for.
      try {
        final deltaAlive = await syncService.deltaFolderExists(id, fresh: true);
        if (deltaAlive) {
          debugPrint('[Library] Skipping full-notebook retry for $id — '
              'delta folder is alive on server, canvas pull/save handles '
              'per-page reconciliation');
          try {
            await _pushUnpushed(syncService, fileService, id);
          } catch (e) {
            if (e is RemoteStorageFullException ||
                (e is MetadataCommitFailedException &&
                    e.cause is RemoteStorageFullException)) {
              storageFull.value = true;
            }
            unawaited(CrashLogger.append('[Unpushed] $id push failed: $e'));
          }
          // Clear the dirty flag since the delta folder IS the committed
          // state; the DB's 'modified' flag was a vestige from an earlier
          // save path that never got cleared.
          try {
            await fileService.markNotebookSynced(id, row['etag'] as String?);
          } catch (_) {}
          continue;
        }
      } catch (_) {
        // If we can't even check the delta folder, we have no business
        // firing a heavy re-upload. Bail until next cycle.
        debugPrint('[Library] Skipping retry for $id — cannot verify server state');
        continue;
      }

      // Delta folder absent. Was it ever here? Then another device deleted
      // the notebook: bootstrapping it again would resurrect it behind their
      // back, so it stays on this device until the user resumes sync.
      try {
        if (await _deletedOnServer(syncService, fileService, id, row)) {
          await _keepAfterRemoteDelete(fileService, id);
          continue;
        }
      } catch (e) {
        debugPrint('[Library] Skipping retry for $id — cannot verify server state: $e');
        continue;
      }

      try {
        final pushedKeys = await fileService.dirtyPagesOf(id);
        final localData = await fileService.readNotebookFile(id);
        if (localData == null) continue;
        final result = syncService.parseNcnoteMetadata(localData);
        // Single ZIP walk for pages + assets + symbols (was 3 decodes).
        final contents = syncService.extractNotebookContents(localData);
        final allPages = contents.pages;
        final allAssets = contents.assets;
        final symbolLibraries = contents.symbolLibraries;

        // Legacy path: no delta folder yet, do a full upload to bootstrap
        // the notebook on the server.
        final res = await syncService.syncDelta(
          notebookId: id,
          metadata: result.metadata,
          document: result.document,
          dirtyPages: allPages,
          dirtyAssets: allAssets.isNotEmpty ? allAssets : null,
          symbolLibraries: symbolLibraries.isNotEmpty ? symbolLibraries : null,
        );
        // Every page and the metadata read above just went up.
        await fileService.clearDirtyPagesOf(id, pushedKeys);
        await fileService.markNotebookSynced(id, res.metaEtag);
        // The root file is what other devices list; without it the folder
        // just written is invisible to them.
        await PendingRootUploads.add(id);
        await _uploadPendingRoot(syncService, fileService, id);
        debugPrint('[Library] Retried upload OK for $id (bootstrapped delta folder)');
      } catch (e) {
        debugPrint('[Library] Retry upload failed for $id: $e (will retry next cycle)');
      }
    }
  }

}
