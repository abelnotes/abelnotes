import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas/notebook_save.dart';
import 'package:abelnotes/core/providers/canvas/pdf_sources.dart';
import 'package:abelnotes/core/providers/canvas/sync_pull.dart';
import 'package:abelnotes/core/providers/canvas/sync_session.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/core/providers/offline_providers.dart'
    show fileServiceProvider;
import 'package:abelnotes/core/providers/notebook_provider.dart'
    show notebookListProvider, syncServiceProvider;
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/remote_store.dart'
    show RemoteStorageFullException, RemoteStoreException;
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/core/sync/stroke_ops.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Pushing the open notebook to the server: the upload of what a save
/// changed, its outcome, and the retries that follow a failure.
class SyncPush {
  SyncPush(
    this._core,
    this._sync, {
    required NotebookSave save,
    required PdfSources pdfSources,
    required this.remoteSaveInFlight,
    required this.keptLocal,
    required Future<bool> Function(String id) isLocalOnly,
    required void Function(String id) markLocalOnly,
    required Future<void> Function(String id) persistUnpushedBase,
    required Future<void> Function(String id) clearUnpushedBase,
    required Future<void> Function(String id) persistPendingDeletes,
    required Future<void> Function(String id, Uint8List? bytes)
        persistPendingMetaCommit,
    required Future<void> Function(String id) persistRemoteMetaEtag,
    required Future<void> Function(String id) persistLastPageEtags,
    required void Function(bool full) reportStorageFull,
    required void Function(bool reachable) reportReachable,
    required void Function() recomputeSyncStatus,
    required Future<void> Function() pullRemoteChanges,
    required Future<void> Function(String id) forgetBaseline,
  })  : _save = save,
        _pdfSources = pdfSources,
        _isLocalOnly = isLocalOnly,
        _markLocalOnly = markLocalOnly,
        _persistUnpushedBase = persistUnpushedBase,
        _clearUnpushedBase = clearUnpushedBase,
        _persistPendingDeletes = persistPendingDeletes,
        _persistPendingMetaCommit = persistPendingMetaCommit,
        _persistRemoteMetaEtag = persistRemoteMetaEtag,
        _persistLastPageEtags = persistLastPageEtags,
        _reportStorageFull = reportStorageFull,
        _reportReachable = reportReachable,
        _recomputeSyncStatus = recomputeSyncStatus,
        _pullRemoteChanges = pullRemoteChanges,
        _forgetBaseline = forgetBaseline;

  final CanvasCore _core;
  final SyncSession _sync;
  final NotebookSave _save;
  final PdfSources _pdfSources;
  final Future<bool> Function(String id) _isLocalOnly;
  final void Function(String id) _markLocalOnly;
  final Future<void> Function(String id) _persistUnpushedBase;
  final Future<void> Function(String id) _clearUnpushedBase;
  final Future<void> Function(String id) _persistPendingDeletes;
  final Future<void> Function(String id, Uint8List? bytes)
      _persistPendingMetaCommit;
  final Future<void> Function(String id) _persistRemoteMetaEtag;
  final Future<void> Function(String id) _persistLastPageEtags;
  final void Function(bool full) _reportStorageFull;
  final void Function(bool reachable) _reportReachable;
  final void Function() _recomputeSyncStatus;
  final Future<void> Function() _pullRemoteChanges;
  final Future<void> Function(String id) _forgetBaseline;

  /// An upload is running: isDirty is cleared before it starts, so without
  /// this the pill read "synced" for the whole upload.
  final ValueNotifier<bool> remoteSaveInFlight;

  /// The open notebook never syncs: kept on this device, or no server.
  final ValueNotifier<bool> keptLocal;

  CanvasState? get state => _core.state;
  set state(CanvasState? value) => _core.state = value;

  /// Anything this session holds that the server doesn't.
  bool _hasUnpushed() {
    final st = state;
    if (st == null) return false;
    if (_sync.dirtyAssetKeys.isNotEmpty ||
        _sync.pendingPageDeletes.isNotEmpty ||
        _sync.pendingAssetDeletes.isNotEmpty) {
      return true;
    }
    for (final e in st.pages.entries) {
      if (!identical(e.value, _sync.lastSyncedPages[e.key])) return true;
    }
    return false;
  }

  /// Re-runs the save for what a failed upload left behind. A failed save
  /// clears isDirty, so nothing else would retry until the next edit.
  void retryUnpushed() {
    _sync.remoteRetryTimer?.cancel();
    _sync.remoteRetryTimer = null;
    final st = state;
    if (_core.isDisposed || st == null || st.isDirty || !_hasUnpushed()) return;
    state = st.copyWith(isDirty: true); // the editor autosaves on this edge
  }

  void scheduleRemoteRetry() {
    if (_core.isDisposed) return;
    _sync.remoteRetryTimer?.cancel();
    final secs = (15 * (1 << (_sync.consecutiveSyncFailures - 1).clamp(0, 5)))
        .clamp(15, 300);
    _sync.remoteRetryTimer = Timer(Duration(seconds: secs), retryUnpushed);
  }

  /// The server answered: the offline state is over, push what is waiting.
  void onRemoteReachable() {
    _reportReachable(true);
    final wasFailing =
        _sync.consecutiveSyncFailures > 0 || _sync.pullUnreachable;
    _sync.pullUnreachable = false;
    if (_sync.consecutiveSyncFailures > 0) {
      _sync.consecutiveSyncFailures = 0;
      retryUnpushed();
    }
    if (wasFailing) _recomputeSyncStatus();
  }

  static const _metaRetryBaseMs = 60 * 1000;
  static const _metaRetryMaxMs = 30 * 60 * 1000;

  /// Schedule the next retry of the pending metadata.json commit with
  /// exponential backoff. Idempotent: a scheduled timer is left in
  /// place. Cancelled on success or notebook close. Skips firing the
  /// immediate microtask retry that previously hammered the network
  /// the moment a failure landed (it's the worst time to retry — the
  /// link is presumably still bad).
  void scheduleMetaCommitRetry() {
    if (_sync.pendingMetaCommitTimer != null || _core.isDisposed) return;
    final delayMs =
        (_metaRetryBaseMs * (1 << _sync.metaRetryAttempts.clamp(0, 8)))
            .clamp(_metaRetryBaseMs, _metaRetryMaxMs);
    _sync.pendingMetaCommitTimer = Timer(
      Duration(milliseconds: delayMs),
      () {
        _sync.pendingMetaCommitTimer = null;
        _retryPendingMetaCommit();
      },
    );
  }

  Future<void> _retryPendingMetaCommit() async {
    final bytes = _sync.pendingMetaCommitBytes;
    if (bytes == null) {
      _sync.pendingMetaCommitTimer?.cancel();
      _sync.pendingMetaCommitTimer = null;
      _sync.metaRetryAttempts = 0;
      return;
    }
    if (state == null || _core.isDisposed) return;
    final notebookId = state!.metadata.id;
    final syncService = _core.ref.read(syncServiceProvider);
    if (syncService == null) {
      _sync.metaRetryAttempts++;
      scheduleMetaCommitRetry();
      return;
    }
    try {
      final etag = await syncService.replayMetadataCommit(
        notebookId: notebookId,
        metadataBytes: bytes,
      );
      // Success — clear the pending state and the backoff.
      _sync.pendingMetaCommitBytes = null;
      _sync.pendingMetaCommitTimer?.cancel();
      _sync.pendingMetaCommitTimer = null;
      _sync.metaRetryAttempts = 0;
      await _persistPendingMetaCommit(notebookId, null);
      if (etag != null && etag.isNotEmpty) {
        _sync.remoteMetaEtag = etag;
        await _persistRemoteMetaEtag(notebookId);
      }
      _recomputeSyncStatus();
      print('[Canvas] Pending metadata commit replayed successfully '
          '(etag=$etag) — server is consistent again');
    } catch (e) {
      // Bump attempt count, schedule next with exponential delay.
      _sync.metaRetryAttempts++;
      debugPrint(
          '[Canvas] Pending metadata commit retry #${_sync.metaRetryAttempts} '
          'failed: $e — next try in '
          '${(_metaRetryBaseMs * (1 << _sync.metaRetryAttempts.clamp(0, 8))).clamp(_metaRetryBaseMs, _metaRetryMaxMs) ~/ 1000}s');
      scheduleMetaCommitRetry();
    }
  }

  /// Stage 3, push: fires the delta sync for [plan]; false when held back.
  Future<bool> startRemoteSync(
      SavePlan plan, Map<String, Uint8List> preEncodedDirty) {
    final s = plan.s;
    final syncService = plan.syncService;
    final fileService = plan.fileService;
    final updatedMeta = plan.updatedMeta;
    final changedPages = plan.changedPages;
    final changedAssets = plan.changedAssets;
    final deletedPages = plan.deletedPages;
    // Fire remote delta sync RIGHT NOW — it only needs the in-memory
    //    objects (changedPages + document + metadata), does not need the
    //    full .ncnote ZIP. Putting it ahead of the expensive
    //    local write is what makes small-stroke
    //    edits actually reach the server in ~seconds on Tailscale instead
    //    of waiting for the ZIP build to finish first.
    // A pending conflict is the user's to decide: uploading now would push
    // their local side of it (and the document listing it) before they do.
    // Saved locally only; resolving the conflict triggers the upload.
    final conflictHold = s.pendingConflicts.isNotEmpty;
    return conflictHold
        ? Future<bool>.value(false)
        : _remoteSync(
            syncService: syncService,
            fileService: fileService,
            updatedMeta: updatedMeta,
            document: s.document,
            dirtyPages: changedPages,
            preEncodedPages: preEncodedDirty,
            dirtyAssets: changedAssets.isNotEmpty ? changedAssets : null,
            symbolLibraries: s.symbolLibraries.isNotEmpty
                ? s.symbolLibraries.map((l) => l.toJson()).toList()
                : null,
            deletedPages: deletedPages.isNotEmpty ? deletedPages : null,
            compactPages: plan.compactPages,
          );
  }

  /// Stage 4, push: hands the sync lock to a background task that waits for
  /// the upload and the local write, records the outcome and releases it.
  void trackRemoteSave(
    SavePlan plan,
    Set<String> snapshotDirtyAssetKeys,
    Future<bool> remoteSyncFuture,
    Future<bool> localSaveFuture,
    SyncLockLease lease,
  ) {
    final s = plan.s;
    final syncService = plan.syncService;
    final fileService = plan.fileService;
    final updatedMeta = plan.updatedMeta;
    final changedPages = plan.changedPages;
    final conflictHold = plan.conflictHold;
    // Hand the lock to a background task that waits for the remote sync
    // to finish (or fail), then releases the lock.
    //
    // Track the background task so closeNotebook() can await it.
    // Without this, the user can exit mid-upload and the sync ends up
    // half-committed on the server (pages uploaded, metadata.json never
    // rewritten), which the next pull then has to reconcile as a conflict.
    remoteSaveInFlight.value = !conflictHold;
    _sync.pendingRemoteSave = () async {
      try {
        final uploaded = await remoteSyncFuture;
        if (conflictHold) return; // nothing went up: baselines stay put
        if (uploaded) _sync.serverMovedStreak = 0;
        // Remote commit succeeded — clear the failure streak so the
        // pill flips back from offline to pending/ok.
        _reportStorageFull(false);
        _reportReachable(true);
        if (_sync.consecutiveSyncFailures > 0 || _sync.pullUnreachable) {
          _sync.consecutiveSyncFailures = 0;
          _sync.pullUnreachable = false;
          _sync.remoteRetryTimer?.cancel();
          _recomputeSyncStatus();
        }
        _sync.movedChecks = 0;
        // The full chain (pages + document + metadata) just landed,
        // so any pending metadata-only retry is now stale: the bytes
        // queued by an earlier failed save committed something the
        // server has since superseded. Drop the queue and reset the
        // exponential-backoff state.
        if (_sync.pendingMetaCommitBytes != null) {
          _sync.pendingMetaCommitBytes = null;
          _sync.pendingMetaCommitTimer?.cancel();
          _sync.pendingMetaCommitTimer = null;
          _sync.metaRetryAttempts = 0;
          await _persistPendingMetaCommit(updatedMeta.id, null);
          _recomputeSyncStatus();
        }
        // Remote commit succeeded — NOW it's safe to advance the dirty
        // snapshot. If we do this optimistically (before remote returns),
        // a failed upload leaves _sync.lastSyncedPages matching state.pages,
        // so the NEXT save() considers those pages 'already synced' via
        // identity check and never retries. That's how iPad drew strokes,
        // hit a commit-phase failure, and the strokes stayed invisible
        // to other devices even though iPad's local file had them.
        _sync.lastSyncedPages = s.pages;
        await _sync.clearAttempted(updatedMeta.id);
        // Advance the structure/metadata baselines to exactly what we just
        // uploaded (the `s` snapshot + the committed metadata), so the next
        // pull's 3-way merge treats THIS as the common ancestor.
        _sync.lastSyncedDocument = s.document;
        _sync.lastSyncedMetadata = updatedMeta;
        for (final k in snapshotDirtyAssetKeys) {
          _sync.dirtyAssetKeys.remove(k);
          // Mark these asset IDs as having a server-side counterpart.
          // _pruneOrphanAssets uses this set to decide whether to queue
          // a server DELETE — a local-only asset (never uploaded) must
          // never produce a DELETE because the server might 404 forever
          // OR delete a totally unrelated file with the same name created
          // by another device.
          _sync.uploadedAssetKeys.add(k);
        }
        if (uploaded) {
          await _remarkUnpushedAfterUpload(
              updatedMeta.id, s.pages, s.document, updatedMeta);
        }
        // Persist the per-page ETag map and meta-ETag ONLY after the
        // local ZIP rebuild has landed on disk. If we persist before the
        // ZIP write completes (the previous behaviour) and the process
        // is killed in-between (iOS jetsam, OOM, force-quit), the cold
        // boot reads "we're synced at these ETags" but the .ncnote on
        // disk is the pre-save bundle — the next pull's "ETag matches,
        // skip" path then leaves the user with stale local content
        // forever, an undetectable form of silent data loss.
        try {
          final localOk = await localSaveFuture;
          if (!localOk) {
            debugPrint('[Canvas] Local save reported failure — '
                'skipping ETag persist to avoid lying about sync state');
          } else {
            await _persistRemoteMetaEtag(updatedMeta.id);
            await _persistLastPageEtags(updatedMeta.id);
          }
        } catch (e) {
          debugPrint('[Canvas] Local save errored, skipping ETag '
              'persist: $e');
        }
      } on MetadataCommitFailedException catch (e) {
        // Pages + document landed on the server, only metadata.json
        // failed. Persist the bytes for periodic retry — without this,
        // OTHER devices see the unchanged meta-ETag, fast-path-skip,
        // and never pull the new pages until something else touches
        // metadata. Local _sync.lastSyncedPages is intentionally NOT
        // advanced: the next save will retry the full chain, but the
        // metadata-only retry timer typically wins first.
        debugPrint('[Canvas] Remote sync: pages+document committed but '
            'metadata.json failed — staging for replay: $e');
        if (e.cause is RemoteStorageFullException) _reportStorageFull(true);
        await _sync.noteAttempted(updatedMeta.id, changedPages);
        _sync.pendingMetaCommitBytes = e.metadataBytes;
        await _persistPendingMetaCommit(updatedMeta.id, e.metadataBytes);
        scheduleMetaCommitRetry();
        _sync.consecutiveSyncFailures++;
        _recomputeSyncStatus();
        try {
          await fileService.markNotebookDirty(updatedMeta.id);
        } catch (_) {}
      } on _ServerMovedException {
        _sync.serverMovedStreak++;
        debugPrint('[Canvas] Server changed since the last pull — merging '
            'before pushing');
        try {
          await fileService.markNotebookDirty(updatedMeta.id);
          await fileService.addDirtyPages(updatedMeta.id, [
            ...changedPages.keys,
            for (final k in snapshotDirtyAssetKeys) 'asset:$k',
            'doc',
          ]);
          await _persistUnpushedBase(updatedMeta.id);
        } catch (_) {}
        _pullThenPush();
      } on _RemoteGoneException {
        await onRemoteNotebookGone();
      } catch (e) {
        final cause = e is MetadataCommitFailedException ? e.cause : e;
        if (cause is RemoteStoreException &&
            (cause.statusCode == 404 || cause.statusCode == 409) &&
            await remoteNotebookGone(syncService)) {
          await onRemoteNotebookGone();
          return;
        }
        debugPrint('[Canvas] Remote sync deferred (offline?): $e');
        await _sync.noteAttempted(updatedMeta.id, changedPages);
        if (e is RemoteStorageFullException) _reportStorageFull(true);
        _sync.consecutiveSyncFailures++;
        _recomputeSyncStatus();
        scheduleRemoteRetry();
        // Leave _sync.lastSyncedPages and _sync.dirtyAssetKeys untouched so the
        // failed pages are detected as dirty again on the next save.
        try {
          await fileService.markNotebookDirty(updatedMeta.id);
          // In-memory state dies with the editor: persist what failed so
          // reopening pushes it instead of treating it as synced.
          if (!syncService.isOffline) {
            // 'doc': every save carries the page list and metadata, so a
            // failed one leaves those (deletions, moves, renames) unpushed
            // even when no page content changed.
            await fileService.addDirtyPages(updatedMeta.id, [
              ...changedPages.keys,
              for (final k in snapshotDirtyAssetKeys) 'asset:$k',
              'doc',
            ]);
            await _persistUnpushedBase(updatedMeta.id);
          }
        } catch (_) {}
      } finally {
        lease.release();
        remoteSaveInFlight.value = false;
      }
    }();
    // Clear the tracking slot when this particular save settles — a later
    // save() may have already replaced it, so only clear if still us.
    final thisRemoteSave = _sync.pendingRemoteSave;
    unawaited(thisRemoteSave!.whenComplete(() {
      if (identical(_sync.pendingRemoteSave, thisRemoteSave)) {
        _sync.pendingRemoteSave = null;
      }
    }));
  }

  static const int _maxMovedChecks = 3;

  /// The upload overwrites whole page files, so it must start from what the
  /// server holds now: when another device pushed since our last pull, throw
  /// [_ServerMovedException] and let the pull's 3-way merge run first.
  Future<void> _ensureServerUnchanged(
      SyncService sync, String id, List<String> dirtyFns) async {
    if (_sync.movedChecks >= _maxMovedChecks) return;
    final known =
        dirtyFns.where((fn) => _sync.lastPageEtags[fn] != null).toList();
    if (known.isEmpty && _sync.remoteMetaEtag == null) {
      // Never pushed from here: if the server held it before, it is gone now.
      if (await remoteNotebookGone(sync)) throw _RemoteGoneException();
      return;
    }
    var moved = false;
    try {
      if (known.isNotEmpty && known.length <= 16) {
        final now = await sync.getPageVersions(id, known);
        if (now.values.every((v) => v == null) &&
            await remoteNotebookGone(sync)) {
          throw _RemoteGoneException();
        }
        moved = now.entries.any((e) => e.value != _sync.lastPageEtags[e.key]);
      }
      if (!moved && _sync.remoteMetaEtag != null) {
        final meta = await sync.getDeltaMetaEtag(id);
        if (meta == null && await remoteNotebookGone(sync)) {
          throw _RemoteGoneException();
        }
        moved = meta != null && meta != _sync.remoteMetaEtag;
      }
    } on _RemoteGoneException {
      rethrow;
    } catch (_) {
      return; // can't tell: the upload itself will fail or succeed
    }
    if (moved) {
      _sync.movedChecks++;
      throw _ServerMovedException();
    }
  }

  /// Merge what the other device pushed, then push the merge.
  void _pullThenPush() {
    // Backs off while the other device keeps winning the race.
    final ms = (300 * (1 << (_sync.serverMovedStreak - 1).clamp(0, 7)))
        .clamp(300, 30000);
    unawaited(() async {
      await Future<void>.delayed(Duration(milliseconds: ms));
      if (_core.isDisposed || state == null) return;
      _sync.pagePropfindCounter =
          SyncPull.propfindSafetyNetEvery; // force a full listing
      await _pullRemoteChanges();
      retryUnpushed();
    }());
  }

  /// This device has seen the notebook on the server: a delta ETag, or the
  /// root file's ETag recorded when it was downloaded or uploaded.
  Future<bool> _wasOnServer(String id) async {
    if (_sync.remoteMetaEtag != null || _sync.lastPageEtags.isNotEmpty)
      return true;
    try {
      final row = await _core.ref.read(fileServiceProvider).getNotebookMeta(id);
      return row?['etag'] != null;
    } catch (_) {
      return false;
    }
  }

  /// The notebook was on the server and its root file and folder
  /// are both gone: another device deleted it. Anything else (network, auth,
  /// a half-written upload) answers false.
  Future<bool> remoteNotebookGone(SyncService sync) async {
    final st = state;
    if (st == null || !await _wasOnServer(st.metadata.id)) return false;
    try {
      if (await sync.deltaFolderExists(st.metadata.id, fresh: true)) {
        return false;
      }
      final root = st.remotePath;
      return root.isEmpty || await sync.notebookRootAbsent(root);
    } catch (_) {
      return false;
    }
  }

  /// Keeps the notebook on this device only, instead of recreating a folder
  /// nobody can find: the user's edits stay, the indicators say so, and
  /// resuming sync from the library uploads it again on purpose.
  Future<void> onRemoteNotebookGone() async {
    final st = state;
    if (st == null) return;
    final id = st.metadata.id;
    // Deleted from this device: the server is empty because of us.
    if (_core.ref.read(notebookListProvider.notifier).isDeletedHere(id)) return;
    final files = _core.ref.read(fileServiceProvider);
    await files.setNotebookLocalOnly(id, true);
    await files.clearDirtyPages(id);
    _markLocalOnly(id);
    keptLocal.value = true;
    _sync.remoteRetryTimer?.cancel();
    _sync.pendingMetaCommitBytes = null;
    _sync.pendingMetaCommitTimer?.cancel();
    _sync.pendingMetaCommitTimer = null;
    _sync.pendingPageDeletes.clear();
    _sync.pendingAssetDeletes.clear();
    _sync.remoteMetaEtag = null;
    _sync.lastPageEtags = {};
    _sync.consecutiveSyncFailures = 0;
    _sync.pullUnreachable = false;
    _recomputeSyncStatus();
    await _persistPendingDeletes(id);
    await _persistPendingMetaCommit(id, null);
    await _clearUnpushedBase(id);
    await _forgetBaseline(id);
    unawaited(CrashLogger.append('[Sync] $id deleted on the server: kept '
        'on this device only'));
    _core.ref.read(notebookListProvider.notifier).noteDeletedElsewhere(id);
  }

  /// Returns true when the delta went up, false when nothing was sent
  /// (offline, or the notebook stays on this device).
  Future<bool> _remoteSync({
    required SyncService syncService,
    required dynamic fileService,
    required NotebookMetadata updatedMeta,
    required DocumentStructure document,
    required Map<String, PageData> dirtyPages,
    Map<String, Uint8List>? preEncodedPages,
    Map<String, Uint8List>? dirtyAssets,
    List<Map<String, dynamic>>? symbolLibraries,
    List<String>? deletedPages,
    Set<String> compactPages = const {},
  }) async {
    // Collision guard (queue-lifetime, not just this save): never DELETE a
    // fileName we're also PUTting in THIS syncDelta call. syncDelta runs
    // Phase 0 (DELETE) and Phase 1 (PUT) under one Future.wait with no
    // ordering, so a stale pending delete for page_010 racing the new
    // page_010 PUT could leave the server without the just-uploaded content.
    // _saveInner already drops same-save collisions, but a delete QUEUED IN A
    // PRIOR save (dropped on a flaky link) reaches _remoteSync independently
    // and bypasses that guard — so re-check against the live upload set here.
    // Sequential filename reuse after delete+re-import makes this real.
    if (dirtyPages.isNotEmpty) {
      _sync.pendingPageDeletes.removeWhere((fn) => dirtyPages.containsKey(fn));
    }
    if (dirtyAssets != null && dirtyAssets.isNotEmpty) {
      _sync.pendingAssetDeletes
          .removeWhere((id) => dirtyAssets.containsKey(id));
    }

    // Pending sets carry every delete request — both this save's and any
    // from prior saves whose DELETE drops on flaky networks (Tailscale).
    // Drain in CAPPED batches so a backlog of hundreds of orphans (can
    // happen after re-importing a PDF and re-deleting it on flaky links)
    // doesn't bloat every save into a multi-minute storm of DELETEs that
    // ties up the connection and starves the metadata commit phase.
    const int deleteBatchPerSave = 30;
    final mergedDeletedPages =
        _sync.pendingPageDeletes.take(deleteBatchPerSave).toList();
    final mergedDeletedAssets =
        _sync.pendingAssetDeletes.take(deleteBatchPerSave).toList();

    if (syncService.isOffline || await _isLocalOnly(updatedMeta.id)) {
      debugPrint('[Canvas] Skipping delta sync for ${updatedMeta.id} — '
          'notebook is kept on this device only');
      // Remember what the server never got: reconnecting or resuming sync
      // pushes it, instead of reading the local copy as already uploaded.
      try {
        await fileService.addDirtyPages(updatedMeta.id, [
          ...dirtyPages.keys,
          for (final k in dirtyAssets?.keys ?? const <String>[]) 'asset:$k',
          'doc',
        ]);
        await _persistUnpushedBase(updatedMeta.id);
      } catch (_) {}
      return false;
    }

    await _ensureServerUnchanged(
        syncService, updatedMeta.id, dirtyPages.keys.toList());

    debugPrint('[Canvas] Starting delta sync: ${dirtyPages.length} pages '
        '(retrying ${_sync.pendingPageDeletes.length} pending page deletes, '
        '${_sync.pendingAssetDeletes.length} pending asset deletes)');
    final ({
      String? metaEtag,
      Map<String, String> pageEtags,
      List<String> failedPageDeletes,
      List<String> failedAssetDeletes,
      String? docVersion,
    }) result;
    try {
      result = await syncService.syncDelta(
        notebookId: updatedMeta.id,
        metadata: updatedMeta,
        document: document,
        dirtyPages: dirtyPages,
        preEncodedPages: preEncodedPages,
        dirtyAssets: dirtyAssets,
        symbolLibraries: symbolLibraries,
        deletedPageFileNames:
            mergedDeletedPages.isNotEmpty ? mergedDeletedPages : null,
        deletedAssetFileNames:
            mergedDeletedAssets.isNotEmpty ? mergedDeletedAssets : null,
        // Each page only lands over the server version it was edited from:
        // a blind PUT replaced another device's strokes, and its next pull
        // then read them as deleted here.
        pageBaseVersions: {
          for (final fn in dirtyPages.keys)
            if (_sync.lastPageEtags[fn] != null) fn: _sync.lastPageEtags[fn]!,
        },
        documentBaseVersion: _sync.remoteDocVersion,
        pageBaselines: StrokeOps.writing
            ? {
                for (final fn in dirtyPages.keys)
                  if (_sync.lastSyncedPages[fn] != null)
                    fn: _sync.lastSyncedPages[fn]!,
              }
            : null,
        compactPages: StrokeOps.writing ? compactPages : const {},
      );
    } on RemotePagesChangedException catch (e) {
      // Ours went up for the others; keep their versions so the pull does
      // not fetch them back as foreign changes.
      _sync.lastPageEtags.addAll(e.uploadedEtags);
      // The page list moved: force the next pull to fetch and merge it even
      // if metadata.json (written after it) hasn't moved yet.
      if (e.fileNames.contains(AppConfig.documentFile))
        _sync.remoteMetaEtag = null;
      unawaited(CrashLogger.append('[Sync] ${e.fileNames.length} files '
          'changed on the server under this upload: merging first'));
      throw _ServerMovedException();
    }

    // Anything we asked the server to delete and didn't see a failure for
    // is now confirmed gone (or 404, which we treat as success). Drop those
    // from the pending sets; re-add anything that failed.
    final attemptedPageDeletes = mergedDeletedPages.toSet();
    final attemptedAssetDeletes = mergedDeletedAssets.toSet();
    _sync.pendingPageDeletes
      ..removeAll(attemptedPageDeletes)
      ..addAll(result.failedPageDeletes);
    _sync.pendingAssetDeletes
      ..removeAll(attemptedAssetDeletes)
      ..addAll(result.failedAssetDeletes);
    await _persistPendingDeletes(updatedMeta.id);

    _sync.remoteMetaEtag = result.metaEtag;
    _sync.remoteDocVersion = result.docVersion ?? _sync.remoteDocVersion;
    // Clear corrupt-ETag dedup entries for any page we just uploaded:
    // the server now has fresh bytes (with verified size — see
    // WebDavService.uploadFile), so the OLD truncated ETag we cached as
    // "skip the GET" is no longer authoritative. If the post-PUT
    // verification ever lets a bad upload slip through (it shouldn't,
    // but defensively), the next pull will FormatException again and
    // re-populate the dedup with the new ETag.
    for (final fn in result.pageEtags.keys) {
      _sync.knownCorruptEtags.remove(fn);
    }
    // MERGE (not replace) the per-page ETags we just uploaded into the cache.
    //
    // Using a full PROPFIND here — the old behaviour — is racy: between our
    // syncDelta completing and the PROPFIND returning, another device can
    // upload a different page; its ETag would land in our cache and the next
    // pull would diff its already-up-to-date ETag against itself, concluding
    // "no change" → we'd silently miss that remote edit.
    //
    // Merging only the pages WE wrote leaves all other entries untouched, so
    // the next pull still detects any concurrent uploads from other devices.
    for (final entry in result.pageEtags.entries) {
      _sync.lastPageEtags[entry.key] = entry.value;
    }
    // Purge deleted pages so the pull diff doesn't resurrect them.
    if (deletedPages != null) {
      for (final fn in deletedPages) {
        _sync.lastPageEtags.remove(fn);
      }
    }
    // Dirty marks are reset by the caller once the baselines advanced
    // (_remarkUnpushedAfterUpload): edits written to disk after this
    // snapshot keep theirs.
    await fileService.markNotebookSynced(updatedMeta.id, result.metaEtag);
    if (_pdfSources.dirty) {
      unawaited(_pdfSources.syncQuietly(syncService, updatedMeta.id));
    }
    unawaited(_core.ref
        .read(notebookListProvider.notifier)
        .uploadPendingRootFor(updatedMeta.id));
    // ETag persistence is INTENTIONALLY deferred: the caller chains it
    // to the local-ZIP write completion in the _sync.pendingRemoteSave block.
    // Persisting here would race the local write — a process kill in
    // between leaves us advertising synced state that the on-disk ZIP
    // contradicts, producing silent stale-content on next open.
    print('[Canvas] Delta synced: ${dirtyPages.length} pages → server '
        '(${result.pageEtags.length} etags captured)');
    return true;
  }

  /// After an upload of [pages]/[document]: clears the dirty marks, then
  /// marks again what the disk holds newer than that upload. Under the
  /// local-write lock, so a write landing meanwhile keeps its mark.
  Future<void> _remarkUnpushedAfterUpload(
    String id,
    Map<String, PageData> pages,
    DocumentStructure document,
    NotebookMetadata metadata,
  ) {
    return _save.withLocalLock(() async {
      try {
        final files = _core.ref.read(fileServiceProvider);
        await files.clearDirtyPages(id);
        await _clearUnpushedBase(id);
        if (state?.metadata.id != id) return;
        final newer = <String>[
          for (final e in _save.storedPages.entries)
            if (!identical(e.value, pages[e.key])) e.key,
          for (final k in _sync.dirtyAssetKeys)
            if (_save.storedAssets.contains(k)) 'asset:$k',
          if ((_save.storedDoc != null &&
                  !identical(_save.storedDoc, document)) ||
              (_save.storedMeta != null &&
                  !identical(_save.storedMeta, metadata)))
            'doc',
        ];
        if (newer.isEmpty) return;
        await files.addDirtyPages(id, newer);
        await _persistUnpushedBase(id);
        await files.markNotebookDirty(id);
      } catch (e) {
        debugPrint('[Canvas] Could not reset dirty marks: $e');
      }
    });
  }
}

/// The server changed under a push; the caller merges first.
class _ServerMovedException implements Exception {}

/// The server no longer holds the notebook.
class _RemoteGoneException implements Exception {}

/// What one save carries, computed by [CanvasNotifier._prepareSave].
class SavePlan {
  SavePlan({
    required this.s,
    required this.syncService,
    required this.fileService,
    required this.updatedMeta,
    required this.changedPages,
    required this.changedAssets,
    required this.deletedPages,
    this.compactPages = const {},
  });

  final CanvasState s;
  final SyncService syncService;
  final FileService fileService;
  final NotebookMetadata updatedMeta;
  final Map<String, PageData> changedPages;
  final Map<String, Uint8List> changedAssets;
  final List<String> deletedPages;

  /// Pages written whole, folding their stroke chunks (on close).
  final Set<String> compactPages;

  /// A pending conflict is the user's to decide: nothing is uploaded.
  bool get conflictHold => s.pendingConflicts.isNotEmpty;
}
