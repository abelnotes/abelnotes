import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/auth_provider.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart' show canvasProvider;
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/search_service.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/core/services/webdav_service.dart';

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

  const NotebookEntry({
    required this.metadata,
    required this.remotePath,
    this.lastSynced,
    this.isLocal = false,
  });

  NotebookEntry copyWith({
    NotebookMetadata? metadata,
    String? remotePath,
    DateTime? lastSynced,
    bool? isLocal,
  }) =>
      NotebookEntry(
        metadata: metadata ?? this.metadata,
        remotePath: remotePath ?? this.remotePath,
        lastSynced: lastSynced ?? this.lastSynced,
        isLocal: isLocal ?? this.isLocal,
      );
}

/// Provider del SyncService.
final syncServiceProvider = Provider<SyncService?>((ref) {
  // Always non-null: SyncService's pure ZIP / loose-store helpers must work
  // in local-only mode (no server). `webdav` is null then, and any genuine
  // network call throws a clear "modalità solo-locale" error. Nullable type
  // kept for source compatibility with existing `== null` guards.
  final webdav = ref.watch(webdavServiceProvider);
  final fileService = ref.watch(fileServiceProvider);
  final service = SyncService(webdav, fileService);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider della lista notebook nella libreria.
final notebookListProvider =
    StateNotifierProvider<NotebookListNotifier, AsyncValue<List<NotebookEntry>>>(
        (ref) {
  return NotebookListNotifier(ref);
});

class NotebookListNotifier
    extends StateNotifier<AsyncValue<List<NotebookEntry>>> {
  final Ref _ref;

  NotebookListNotifier(this._ref) : super(const AsyncValue.loading());

  /// True while a background sync with the server is running. The library UI
  /// watches this to distinguish "cold install, still fetching" from "really
  /// no notebooks" when the local DB is empty.
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  /// Progress during first sync: "downloaded/total" where 0/0 means PROPFIND
  /// is still in flight. UI shows this beside the spinner so first-install
  /// users can tell work is happening.
  final ValueNotifier<({int done, int total})> syncProgress =
      ValueNotifier<({int done, int total})>((done: 0, total: 0));

  @override
  void dispose() {
    isSyncing.dispose();
    syncProgress.dispose();
    super.dispose();
  }

  /// Carica la lista dei notebook dal server, con fallback locale offline.
  Future<void> refresh() async {
    final fileService = _ref.read(fileServiceProvider);

    // ── Step 1: Show cached notebooks instantly from local DB ──
    await _loadFromLocalDb(fileService);

    // ── Step 2: Sync with server in background ──
    isSyncing.value = true;
    try {
      final syncService = _ref.read(syncServiceProvider);
      final webdav = _ref.read(webdavServiceProvider);
      if (syncService == null || webdav == null) return;

      await _syncWithServer(syncService, webdav, fileService);
    } catch (e) {
      debugPrint('[Library] Remote sync failed: $e');
      // Local data is already shown — no need to show error
    } finally {
      if (mounted) {
        isSyncing.value = false;
        syncProgress.value = (done: 0, total: 0);
      }
    }
  }

  /// Build notebook entries directly from local SQLite metadata (no ZIP parsing).
  Future<void> _loadFromLocalDb(FileService fileService) async {
    final allMeta = await fileService.getAllNotebookMeta();
    if (allMeta.isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }

    final entries = <NotebookEntry>[];
    for (final row in allMeta) {
      entries.add(_notebookEntryFromRow(row));
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
        paperType: row['paper_type'] as String? ?? 'lined',
        pageCount: row['page_count'] as int? ?? 0,
      ),
      remotePath: row['remote_path'] as String? ?? '',
      lastSynced: row['remote_modified_at'] != null
          ? DateTime.tryParse(row['remote_modified_at'] as String)
          : null,
      isLocal: row['sync_status'] != 'synced',
    );
  }

  /// Sync with server: only download notebooks whose ETag has changed.
  /// Detects remote deletions and parallelizes downloads.
  Future<void> _syncWithServer(
    SyncService syncService,
    dynamic webdav,
    FileService fileService,
  ) async {
    await webdav.ensureBaseDirectory();
    final remoteFiles = await syncService.listRemoteNotebooks();
    debugPrint('[Library] PROPFIND returned ${remoteFiles.length} .ncnote files');

    // Build map of locally cached ETags keyed by remote path
    final localRows = await fileService.getAllNotebookMeta();
    final localByPath = <String, Map<String, dynamic>>{};
    for (final row in localRows) {
      final rp = row['remote_path'] as String? ?? '';
      if (rp.isNotEmpty) localByPath[rp] = row;
    }

    // Track which remote paths we've seen (to detect deletions)
    final seenRemotePaths = <String>{};
    var changed = false;
    final skipped = <String>[];

    // ── Identify which notebooks need downloading ──
    final toDownload = <({String remotePath, WebDavItem file})>[];
    for (final file in remoteFiles) {
      final remotePath = '${AppConfig.defaultRemotePath}${file.name}';
      seenRemotePaths.add(remotePath);

      final localRow = localByPath[remotePath];
      final localEtag = localRow?['etag'] as String?;

      // Skip if ETag matches — notebook hasn't changed on the server.
      if (localEtag != null && localEtag == file.etag) continue;

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
                  await fileService.upsertNotebookMeta(
                    id: nbId,
                    title: parsed.metadata.title,
                    remotePath: remotePath,
                    localModifiedAt: parsed.metadata.modifiedAt,
                    syncStatus: localRow['sync_status'] as String? ?? 'synced',
                    fileSize: localBytes.length,
                    coverColor: parsed.metadata.coverColor,
                    paperType: parsed.metadata.paperType,
                    pageCount: parsed.metadata.pageCount,
                    createdAt: parsed.metadata.createdAt,
                    etag: localRow['etag'] as String?,
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
            _downloadAndCache(webdav, syncService, fileService, item.remotePath, item.file));
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
      final localRow = localByPath[remotePath];
      if (localRow == null) continue;
      final localEtag = localRow['etag'] as String?;
      if (localEtag == null || localEtag != file.etag) continue;
      // Only ETag-unchanged notebooks that we didn't already redownload.
      etagUnchanged.add(localRow);
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
          final existingCount = row['page_count'] as int? ?? 0;
          final existingTitle = row['title'] as String? ?? '';
          // Skip the UPDATE when nothing user-visible differs — avoids
          // spurious SQLite writes and library rebuilds.
          if (existingCount == deltaMeta.pageCount &&
              existingTitle == deltaMeta.title) {
            continue;
          }
          await fileService.upsertNotebookMeta(
            id: id,
            title: deltaMeta.title,
            remotePath: row['remote_path'] as String? ?? '',
            etag: row['etag'] as String?,
            localModifiedAt: deltaMeta.modifiedAt,
            remoteModifiedAt: row['remote_modified_at'] != null
                ? DateTime.tryParse(row['remote_modified_at'] as String)
                : null,
            syncStatus: row['sync_status'] as String? ?? 'synced',
            fileSize: row['file_size'] as int?,
            coverColor: deltaMeta.coverColor,
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
      if (seenRemotePaths.contains(rp)) continue;
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
      try {
        deltaAlive = await syncService.deltaFolderExists(id);
      } catch (e) {
        debugPrint('[Library] deltaFolderExists error for $id — assuming alive: $e');
        deltaAlive = true; // explicit: uncertainty ⇒ keep local
      }
      if (deltaAlive) {
        debugPrint('[Library] Root .ncnote missing for $id but delta folder alive — '
            'skipping cleanup (notebook still exists on server)');
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
    WebDavItem file,
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
        final uuidRe = RegExp(
            r'([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.ncnote$');
        final uuidMatch = uuidRe.firstMatch(file.name);

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
        if (!hasLocal) {
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
          etag: file.etag,
          localModifiedAt: libraryModifiedAt,
          remoteModifiedAt: file.lastModified,
          syncStatus: 'synced',
          fileSize: hasLocal ? (await fileService.readNotebookFile(rootMeta.id))?.length ?? fullData.length : fullData.length,
          coverColor: libraryMeta.coverColor,
          paperType: libraryMeta.paperType,
          pageCount: libraryMeta.pageCount,
          createdAt: libraryMeta.createdAt,
        );
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
    List<String> tags = const [],
    // Free-sketch mode: one big infinite canvas instead of A4 pages.
    // When true, `paperType` is forced to the infinite marker and the
    // single page uses [backgroundType] (blank/grid/dotted) for its
    // visible texture over a [AppConfig.scratchPageSize] square sheet.
    bool infinite = false,
    String backgroundType = 'dotted',
    String chapterTitle = 'Chapter 1',
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
    final pageW = infinite ? AppConfig.scratchPageSize : AppConfig.defaultPageWidth;
    final pageH = infinite ? AppConfig.scratchPageSize : AppConfig.defaultPageHeight;
    final bgType = infinite ? backgroundType : paperType;

    final metadata = NotebookMetadata(
      id: notebookId,
      title: title,
      createdAt: now,
      modifiedAt: now,
      paperType: effectivePaperType,
      coverColor: coverColor,
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
        '${AppConfig.defaultRemotePath}${safeName}_$notebookId${AppConfig.fileExtension}';

    // Always save locally first
    bool isLocal = true;
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
        paperType: effectivePaperType,
        pageCount: 1,
        createdAt: now,
      );

      // Try uploading to server
      try {
        await syncService.uploadNotebook(
          remotePath: remotePath,
          metadata: metadata,
          document: document,
          pages: {'page_001.json': pageData},
        );
        await fileService.markNotebookSynced(notebookId, null);
        isLocal = false;
      } catch (e) {
        debugPrint('[Library] Created notebook locally, sync deferred: $e');
      }
    }

    final entry = NotebookEntry(
      metadata: metadata,
      remotePath: remotePath,
      lastSynced: isLocal ? null : DateTime.now(),
      isLocal: isLocal,
    );

    // Aggiungi alla lista
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([entry, ...current]);

    return entry;
  }

  /// Soft-deletes a notebook: moves it to the local trash and removes it from
  /// the remote server (when reachable). Can be undone via [restoreFromTrash].
  Future<String?> deleteNotebook(NotebookEntry entry) async {
    final webdav = _ref.read(webdavServiceProvider);
    final fileService = _ref.read(fileServiceProvider);
    final thumbs = _ref.read(thumbnailServiceProvider);

    // Delete remote (if connected)
    if (webdav != null) {
      try {
        await webdav.delete(entry.remotePath);
      } catch (e) {
        debugPrint('[Library] Remote delete failed: $e');
      }
      // Also remove the exploded delta folder — leaving it alive makes the
      // other devices' cleanup logic keep (and re-upload) the notebook.
      try {
        await _ref
            .read(syncServiceProvider)
            ?.deleteDeltaFolder(entry.metadata.id);
      } catch (e) {
        debugPrint('[Library] Delta folder delete failed: $e');
      }
    }

    // Soft-delete locally: preserve the .ncnote in the trash so it can be restored.
    final trashId = await fileService.moveNotebookToTrash(entry.metadata.id);

    // Best-effort thumbnail cleanup.
    try {
      await thumbs.deleteThumbnail(entry.metadata.id);
    } catch (_) {}

    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(
      current.where((e) => e.metadata.id != entry.metadata.id).toList(),
    );
    return trashId;
  }

  /// Restores a notebook from the trash. Re-uploads it to the remote on the
  /// next sync because it was deleted from the server.
  Future<void> restoreFromTrash(String trashId) async {
    final fileService = _ref.read(fileServiceProvider);
    final meta = await fileService.restoreFromTrash(trashId);
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
  Future<void> updateNotebookTags(NotebookEntry entry, List<String> tags) async {
    final syncService = _ref.read(syncServiceProvider);
    final webdav = _ref.read(webdavServiceProvider);
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
      paperType: updatedMeta.paperType,
      pageCount: updatedMeta.pageCount,
      createdAt: updatedMeta.createdAt,
    );

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
        await fileService.markNotebookSynced(updatedMeta.id, etag);
      }
    } catch (e) {
      debugPrint('[Library] Tags uploaded locally, remote sync deferred: $e');
    }

    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.map((e) {
      if (e.metadata.id == entry.metadata.id) {
        return e.copyWith(metadata: updatedMeta);
      }
      return e;
    }).toList());
  }

  /// Change a notebook's cover colour. Same flow as [renameNotebook]:
  /// rebuild the local .ncnote with the new metadata, persist, mark
  /// dirty, and best-effort push to the server.
  Future<void> updateNotebookCover(
      NotebookEntry entry, int newCoverColor) async {
    final syncService = _ref.read(syncServiceProvider);
    final webdav = _ref.read(webdavServiceProvider);
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
      paperType: updatedMeta.paperType,
      pageCount: updatedMeta.pageCount,
      createdAt: updatedMeta.createdAt,
    );

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
        await fileService.markNotebookSynced(updatedMeta.id, etag);
      }
    } catch (e) {
      debugPrint('[Library] Cover change saved locally, remote sync deferred: $e');
    }

    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.map((e) {
      if (e.metadata.id == entry.metadata.id) {
        return e.copyWith(metadata: updatedMeta);
      }
      return e;
    }).toList());
  }

  /// Rinomina un notebook.
  Future<void> renameNotebook(NotebookEntry entry, String newTitle) async {
    final syncService = _ref.read(syncServiceProvider);
    final webdav = _ref.read(webdavServiceProvider);
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
      paperType: updatedMeta.paperType,
      pageCount: updatedMeta.pageCount,
      createdAt: updatedMeta.createdAt,
    );

    // Try to upload to server (best-effort — succeeds when online)
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
        await fileService.markNotebookSynced(updatedMeta.id, etag);
      }
    } catch (e) {
      debugPrint('[Library] Rename uploaded locally, remote sync deferred: $e');
    }

    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.map((e) {
      if (e.metadata.id == entry.metadata.id) {
        return e.copyWith(metadata: updatedMeta);
      }
      return e;
    }).toList());
  }

  /// Best-effort re-upload of every notebook whose local sync status is still
  /// `modified` — i.e. previous save() couldn't reach the server (offline,
  /// Tailscale drop, Nextcloud restart). Called when connectivity comes back,
  /// and once at library boot after a cold start.
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

    final dirtyRows = await fileService.getDirtyNotebooks();
    if (dirtyRows.isEmpty) return;
    debugPrint('[Library] Retrying ${dirtyRows.length} pending notebook uploads');
    unawaited(CrashLogger.append(
      '[Retry] ${dirtyRows.length} pending notebooks to re-upload',
    ));

    for (final row in dirtyRows) {
      final id = row['id'] as String?;
      final remotePath = row['remote_path'] as String?;
      if (id == null || remotePath == null || remotePath.isEmpty) continue;

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
        final deltaAlive = await syncService.deltaFolderExists(id);
        if (deltaAlive) {
          debugPrint('[Library] Skipping full-notebook retry for $id — '
              'delta folder is alive on server, canvas pull/save handles '
              'per-page reconciliation');
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

      try {
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
        await fileService.markNotebookSynced(id, res.metaEtag);
        debugPrint('[Library] Retried upload OK for $id (bootstrapped delta folder)');
      } catch (e) {
        debugPrint('[Library] Retry upload failed for $id: $e (will retry next cycle)');
      }
    }
  }

}
