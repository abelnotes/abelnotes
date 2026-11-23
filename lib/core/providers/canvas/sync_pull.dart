import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/canvas/asset_cache.dart';
import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas/pdf_sources.dart';
import 'package:abelnotes/core/providers/canvas/sync_session.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart' show syncServiceProvider;
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/core/services/remote_store.dart'
    show RemoteStoreException;
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/core/services/sync_thrift.dart';
import 'package:abelnotes/core/sync/page_merge.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Pulling the open notebook from the server: the cheap change probe, the
/// download of what changed and the merge of it into the editor's state.
class SyncPull {
  SyncPull(
    this._core,
    this._sync, {
    required this.isPullingFromRemote,
    required this.pullProgress,
    required PdfSources pdfSources,
    required AssetCache assets,
    required bool Function() isPreview,
    required Future<bool> Function(String id) isLocalOnly,
    required Future<int?> Function() acquireSyncLock,
    required void Function(int token) releaseSyncLock,
    required Future<void> Function(String id) persistLastPageEtags,
    required Future<void> Function(String id) persistRemoteMetaEtag,
    required Future<void> Function(NotebookMetadata, DocumentStructure,
            Map<String, PageData>, Map<String, Uint8List>)
        savePulledChangesLocally,
    required void Function() onRemoteReachable,
    required Future<bool> Function(SyncService sync) remoteNotebookGone,
    required Future<void> Function() onRemoteNotebookGone,
    required void Function(bool reachable) reportReachable,
    required void Function() recomputeSyncStatus,
    required Future<void> Function() save,
    required void Function() acceptRemoteChanges,
    required int Function(String fileName) filenameNum,
    required Map<String, String> Function(NotebookMetadata) chapterByPageId,
  })  : _pdfSources = pdfSources,
        _assets = assets,
        _isPreview = isPreview,
        _isLocalOnly = isLocalOnly,
        _acquireSyncLock = acquireSyncLock,
        _releaseSyncLock = releaseSyncLock,
        _persistLastPageEtags = persistLastPageEtags,
        _persistRemoteMetaEtag = persistRemoteMetaEtag,
        _savePulledChangesLocally = savePulledChangesLocally,
        _onRemoteReachable = onRemoteReachable,
        _remoteNotebookGone = remoteNotebookGone,
        _onRemoteNotebookGone = onRemoteNotebookGone,
        _reportReachable = reportReachable,
        _recomputeSyncStatus = recomputeSyncStatus,
        _save = save,
        _acceptRemoteChanges = acceptRemoteChanges,
        _filenameNum = filenameNum,
        _chapterByPageId = chapterByPageId;

  final CanvasCore _core;
  final SyncSession _sync;

  /// The editor state; a pull that finds the notifier gone stops here.
  CanvasState? get _state {
    if (_core.isDisposed) throw const _PullAborted();
    return _core.state;
  }

  set _state(CanvasState? value) => _core.state = value;

  /// Stops the pull when the notifier was disposed during the last await.
  void _alive() {
    if (_core.isDisposed) throw const _PullAborted();
  }
  final PdfSources _pdfSources;
  final AssetCache _assets;
  final bool Function() _isPreview;
  final Future<bool> Function(String id) _isLocalOnly;
  final Future<int?> Function() _acquireSyncLock;
  final void Function(int token) _releaseSyncLock;
  final Future<void> Function(String id) _persistLastPageEtags;
  final Future<void> Function(String id) _persistRemoteMetaEtag;
  final Future<void> Function(NotebookMetadata, DocumentStructure,
      Map<String, PageData>, Map<String, Uint8List>) _savePulledChangesLocally;
  final void Function() _onRemoteReachable;
  final Future<bool> Function(SyncService sync) _remoteNotebookGone;
  final Future<void> Function() _onRemoteNotebookGone;
  final void Function(bool reachable) _reportReachable;
  final void Function() _recomputeSyncStatus;
  final Future<void> Function() _save;
  final void Function() _acceptRemoteChanges;
  final int Function(String fileName) _filenameNum;
  final Map<String, String> Function(NotebookMetadata) _chapterByPageId;

  /// True while a background pull is downloading for the open notebook.
  final ValueNotifier<bool> isPullingFromRemote;

  /// Progress of the current pull: (done, total); total 0 is indeterminate.
  final ValueNotifier<({int done, int total})> pullProgress;

  static const int _ghostPruneThreshold = 3;
  static const int _maxInconsistentPulls = 6;
  static const Duration _inconsistentWindow = Duration(seconds: 60);
  static const int idlePullThreshold = 3;
  static const Duration _idlePullMaxInterval = Duration(seconds: 30);
  static const int deepIdleThreshold = 30;
  static const Duration _deepIdleMaxInterval = Duration(seconds: 60);
  static const Duration _deepIdleThriftyInterval = Duration(minutes: 5);
  static const int propfindSafetyNetEvery = 8;
  static const Duration _propfindSafetyNetMaxAge = Duration(minutes: 5);
  static const Duration _absentAssetRetry = Duration(minutes: 10);
  static const int _failedPullsBackoff = 3;
  static const int failedPullsShown = 5;
  static const Duration _failedPullMaxInterval = Duration(minutes: 5);

  /// Checks if the remote metadata.json ETag has changed, then pulls
  /// only the pages that differ. Falls back to checking the .ncnote ZIP
  /// for devices that don't use delta sync. Merges into the live canvas.
  ///
  /// Now mutex-protected: waits for any in-flight save() to finish first,
  /// and if local pages are dirty, creates per-page conflicts instead of
  /// silently overwriting.
  Future<void> pullRemoteChanges() async {
    if (_isPreview()) return;
    if (_sync.isPulling || _state == null || _core.bulkOperationInProgress) return;
    // Don't pull while user is resolving conflicts or reviewing pending
    // remote changes — avoids overwriting with a fresh pull.
    if (_state!.pendingConflicts.isNotEmpty) return;
    if (_state!.pendingRemoteChanges != null) return;
    _sync.isPulling = true;
    _sync.pullHadFailures = false;
    // NOTE: isPullingFromRemote is NOT flipped here. The pill should only
    // appear when we're actually *downloading* new remote content — not
    // during every 4-second PROPFIND poll, which is silent and quick.
    // We set it true below only if the metadata ETag indicates real
    // changes to fetch.

    try {
      final target = await _probeRemote();
      if (target == null) return;
      await _pullUnderLock(target.sync, target.notebookId);
    } on _PullAborted {
      // The notifier is gone: nothing left to report or reset.
    } catch (e) {
      print('[Canvas] Pull failed: $e');
    } finally {
      _sync.isPulling = false;
      if (!_core.isDisposed) isPullingFromRemote.value = false;
    }
  }

  /// Stage 1: the cheap probe, without the lock: has the server changed, and
  /// is there anything to fetch. Null when there is nothing to pull.
  Future<({SyncService sync, String notebookId})?> _probeRemote() async {
    // ── Fast path: cheap HEAD on metadata.json only — NO LOCK ──
    //
    // The common case on every 4-second poll (and most notebook opens)
    // is "nothing changed". Running the HEAD inside `_sync.lock` blocked
    // any concurrent save() for 100-200ms on every idle poll; with the
    // HEAD outside the lock, idle polling has zero contention with user
    // saves. Only the slow path (getRemoteChangeState + page downloads)
    // needs the lock, and save() doesn't touch `_sync.remoteMetaEtag`, so
    // reading it without the lock is safe.
    final syncService = _core.ref.read(syncServiceProvider);
    // syncServiceProvider always returns a non-null instance now (see its
    // doc comment) — local-only mode is signaled by isOffline, not null.
    if (syncService == null || syncService.isOffline) return null;
    final pullNotebookId = _state!.metadata.id;
    // Nothing to pull for a notebook that was never meant to leave.
    if (await _isLocalOnly(pullNotebookId)) return null;
    _alive();
    // closeNotebook may have nulled state (or switched notebooks) during the await.
    if (_state == null || _state!.metadata.id != pullNotebookId) return null;
    final s0 = _state!;
    unawaited(CrashLogger.append(
      '[Pull] start nb=${pullNotebookId.substring(0, 8)} '
      'state.pages=${s0.pages.length}/doc=${s0.document.pages.length} '
      'cachedMetaEtag=${_sync.remoteMetaEtag ?? "null"} '
      'lastPageEtags=${_sync.lastPageEtags.length}',
    ));
    // ── Cheap idle path: meta-ETag HEAD only ──
    //
    // Fetching meta-ETag AND a full pages/ PROPFIND every 2 s burnt a
    // whole CPU core idle on a 215-page notebook (XML payload ~50 KB +
    // parse + Map diff). Almost every poll is a noop, so we now do
    // ONLY the meta-ETag HEAD (a few-byte response) on most ticks and
    // fall through to the full PROPFIND only when meta-ETag actually
    // moved, or every [_propfindSafetyNetEvery] cycles as a safety
    // net catching the rare ordered-commit race (another device wrote
    // pages + document.json but crashed before committing
    // metadata.json — meta-ETag unchanged but pages/ folder has new
    // files invisible from a HEAD).
    String? fastMetaEtag;
    var fullStateFetched = false;
    ({String? metaEtag, Map<String, String> pageEtags})? remoteState;
    // Safety-net: by tick count OR by wall-clock age (whichever fires
    // first). Pre-fix, deep-idle stretched the cap to 5 min per tick,
    // and the tick-only safety-net `>= 8` could push a full PROPFIND
    // out to ~40 min. The wall-clock anchor caps the worst case at
    // [_propfindSafetyNetMaxAge].
    final now = DateTime.now();
    final mustDoSafetyNet =
        ++_sync.pagePropfindCounter >= propfindSafetyNetEvery ||
        now.difference(_sync.lastFullPropfindAt) >= _propfindSafetyNetMaxAge;
    try {
      fastMetaEtag =
          await syncService.getDeltaMetaEtag(pullNotebookId);
    } catch (e) {
      unawaited(CrashLogger.append('[Pull] meta-HEAD failed: $e'));
      return null;
    }
    _alive();
    // getDeltaMetaEtag folds errors into null; null for a notebook we
    // already know is on the server means the server isn't answering.
    if (fastMetaEtag != null) {
      _onRemoteReachable();
    } else if (_sync.remoteMetaEtag != null && !_sync.pullUnreachable) {
      if (await _remoteNotebookGone(syncService)) {
        await _onRemoteNotebookGone();
        return null;
      }
      _alive();
      _sync.pullUnreachable = true;
      _reportReachable(false);
      _recomputeSyncStatus();
    }
    // Delta folder never seen from here (the first save creates it): the
    // full fetch below would only repeat the same 404s. The safety net looks.
    if (fastMetaEtag == null &&
        _sync.remoteMetaEtag == null &&
        _sync.lastPageEtags.isEmpty &&
        !mustDoSafetyNet) {
      _sync.idlePullCount++;
      return null;
    }
    final metaMoved = fastMetaEtag != null &&
        (_sync.remoteMetaEtag == null || fastMetaEtag != _sync.remoteMetaEtag);
    if (fastMetaEtag != null) {
      unawaited(_pdfSources.syncQuietly(syncService, pullNotebookId,
          upToDate: !metaMoved && _sync.remoteMetaEtag != null));
    }
    if (metaMoved || mustDoSafetyNet || _sync.remoteMetaEtag == null) {
      try {
        remoteState =
            await syncService.getRemoteChangeState(pullNotebookId);
      } on RemoteStoreException catch (e) { // WebDAV and Drive alike
        if (e.statusCode == 404) {
          if (await _remoteNotebookGone(syncService)) {
            await _onRemoteNotebookGone();
            return null;
          }
          // Remote .sync/<id>/ doesn't exist yet — a freshly created
          // notebook that has never been pushed. Nothing to pull; the
          // first save() will create the folder. Count as an idle tick
          // so adaptive backoff engages instead of re-hitting the 404
          // at full cadence (which also spammed "Pull failed" forever).
          _alive();
          _sync.idlePullCount++;
          // The listing ran and answered: the safety net is satisfied too,
          // or it would rerun this same 404 fetch on every tick.
          _sync.pagePropfindCounter = 0;
          _sync.lastFullPropfindAt = now;
          unawaited(CrashLogger.append(
            '[Pull] skip: remote delta folder missing (404) — '
            'notebook not pushed yet',
          ));
          return null;
        }
        rethrow;
      }
      _alive();
      fastMetaEtag = remoteState.metaEtag;
      fullStateFetched = true;
      _sync.pagePropfindCounter = 0;
      _sync.lastFullPropfindAt = now;
    }
    if (_state == null || _state!.metadata.id != pullNotebookId) {
      print('[Canvas] Pull aborted — notebook switched during HEAD '
          '(expected $pullNotebookId, got ${_state?.metadata.id})');
      unawaited(CrashLogger.append('[Pull] abort: nb switched during HEAD'));
      return null;
    }
    // Detect server-side metadata/pages inconsistency. Three cases:
    //   1. pages/ folder has MORE files than our local document (another
    //      device added pages + page files but failed to commit metadata)
    //   2. pages/ contains fileNames we've never seen locally (same as
    //      #1 but count might match due to concurrent add+remove)
    //   3. An EXISTING page's ETag has moved but our cache still has the
    //      old one (another device saved a stroke and rewrote that page,
    //      but crashed before writing metadata.json) — THIS is the case
    //      the previous detector missed, causing iPad edits to existing
    //      pages to be invisible on PC forever when the iPad's save hit
    //      the ordered-commit race.
    // Skipped on the cheap path (no full PROPFIND) since meta-ETag is
    // matching our cache → the safety-net cycle every
    // [_propfindSafetyNetEvery] ticks will catch any rare divergence.
    final int remotePageCount = fullStateFetched
        ? remoteState!.pageEtags.length
        : _sync.lastPageEtags.length;
    final serverInconsistent = fullStateFetched &&
        (remoteState!.pageEtags.length > s0.document.pages.length ||
            (_sync.lastPageEtags.isNotEmpty &&
                remoteState.pageEtags.keys.any((k) => !_sync.lastPageEtags.containsKey(k))) ||
            (_sync.lastPageEtags.isNotEmpty &&
                remoteState.pageEtags.entries.any(
                    (e) => _sync.lastPageEtags[e.key] != null &&
                           _sync.lastPageEtags[e.key] != e.value)));
    if (fastMetaEtag != null &&
        _sync.remoteMetaEtag != null &&
        fastMetaEtag == _sync.remoteMetaEtag &&
        !serverInconsistent) {
      // Server unchanged since last known etag AND no sign of a half-
      // committed upload from another device. Safe to skip the pull if
      // local state is also self-consistent. If `document.pages > pages`,
      // a previous partial pull left us with missing data and we need
      // to fetch regardless of what the server says.
      if (s0.pages.length >= s0.document.pages.length) {
        // ── Ghost-page detection (P1) ──
        //
        // The pull is about to skip because state is "self-consistent"
        // (pages == doc) and meta ETag is unchanged. But if the document
        // references pages whose ETag the server has NEVER acknowledged
        // (count(_sync.lastPageEtags) < count(document.pages)), those pages
        // exist locally without ever having been uploaded — typically
        // because a previous save() failed mid-upload and reopen rebuilt
        // _sync.lastSyncedPages from the local zip, hiding the ghost pages
        // from future dirty-page detection. Result: every subsequent
        // pull skips here, every save() considers the ghost pages
        // already-synced, and the notebook is permanently wedged with
        // local pages > remote pages.
        //
        // Repair: rebuild _sync.lastSyncedPages without those ghost entries
        // (so the next save() detects them as "new pages" via the
        // !_sync.lastSyncedPages.containsKey(key) branch in _saveInner) and
        // mark the notebook dirty so the next save cycle actually fires.
        if (_sync.lastPageEtags.isNotEmpty &&
            _sync.lastPageEtags.length < s0.document.pages.length) {
          final ghostFns = s0.document.pages
              .map((p) => p.fileName)
              .where((fn) => !_sync.lastPageEtags.containsKey(fn))
              .toList();
          if (ghostFns.isNotEmpty) {
            for (final fn in ghostFns) {
              _sync.lastSyncedPages.remove(fn);
            }
            if (_state != null && _state!.metadata.id == pullNotebookId) {
              _state = _state!.copyWith(isDirty: true);
            }
            unawaited(CrashLogger.append(
              '[Pull] ghost pages detected: ${ghostFns.length} doc entries '
              'without server ETag (sample: '
              '${ghostFns.take(3).join(",")}'
              '${ghostFns.length > 3 ? "..." : ""}) — '
              'marked dirty so next save() uploads them',
            ));
            return null;
          }
        }
        unawaited(CrashLogger.append(
          '[Pull] skip: meta ETag unchanged (fast=$fastMetaEtag) '
          'and state is consistent (pages=${s0.pages.length}=doc=${s0.document.pages.length}, '
          'remote pages=$remotePageCount, fullPropfind=$fullStateFetched)',
        ));
        _sync.idlePullCount++;
        return null;
      }
      unawaited(CrashLogger.append(
        '[Pull] force slow-path despite matching ETag: state inconsistent '
        '(pages=${s0.pages.length} < doc=${s0.document.pages.length}) — '
        're-fetching to hydrate missing pages',
      ));
    } else if (serverInconsistent) {
      unawaited(CrashLogger.append(
        '[Pull] SERVER inconsistency detected: metaEtag unchanged but '
        'pages/ folder has $remotePageCount files vs '
        'local document.pages=${s0.document.pages.length}. '
        'Forcing slow path to hydrate orphan pages (broken commit from '
        'another device).',
      ));
    }
    unawaited(CrashLogger.append(
      '[Pull] proceed: fastEtag=${fastMetaEtag ?? "null"} '
      'cached=${_sync.remoteMetaEtag ?? "null"} → acquire lock + full fetch',
    ));
    return (sync: syncService, notebookId: pullNotebookId);
  }


  /// Stage 2: under the sync lock, fetch the change state, pull what moved and
  /// advance the cached ETag when that left the notebook whole.
  Future<void> _pullUnderLock(
      SyncService syncService, String pullNotebookId) async {
    // ── Slow path: remote changed (or safety-net cycle), acquire lock ──
    //
    // We deliberately do NOT reset _sync.idlePullCount here. The slow path
    // is entered both for genuine changes AND for the periodic safety
    // net (every [_propfindSafetyNetEvery] ticks). Resetting on
    // safety-net cycles defeated the adaptive backoff: every 8th tick
    // dropped us back to the 2 s cadence, then 8 more ticks of 2 s,
    // then safety-net again, forever — the whole point of the backoff
    // (idle should converge to 30 s) never materialised, and a
    // 215-page notebook kept paying a full pages/ PROPFIND every 16 s
    // for nothing. The reset now happens deeper in the function, only
    // when [changeState.metaEtag != _sync.remoteMetaEtag] (true work to
    // do).
    final pullLockToken = await _acquireSyncLock();
    if (pullLockToken == null) return;
    try {
      _alive();
      if (_state == null || _state!.metadata.id != pullNotebookId) return;
      final s = _state!;

      // Fetch metadata ETag + page ETags in parallel (only on change path)
      final changeState = await syncService.getRemoteChangeState(pullNotebookId);
      _alive();

      // Guard: did the user switch notebooks while we were awaiting the
      // network? If so this pull belongs to the OLD notebook — dropping
      // its data into the new one would swap the user's current notebook
      // out from under them (the "Automotive turned into AICD" bug).
      if (_state == null || _state!.metadata.id != pullNotebookId) {
        print('[Canvas] Pull aborted — notebook switched during PROPFIND '
            '(expected $pullNotebookId, got ${_state?.metadata.id})');
        return;
      }

      unawaited(CrashLogger.append(
        '[Pull] changeState: metaEtag=${changeState.metaEtag ?? "null"} '
        'remotePages=${changeState.pageEtags.length}',
      ));
      // Re-evaluate server inconsistency here against the inside-lock
      // change state. We enter the download path if ANY of:
      //   - meta ETag moved
      //   - pages/ folder has more files than local document
      //   - server has page fileNames we don't know about
      //   - an EXISTING page's ETag moved (ordered-commit race: page
      //     uploaded but metadata.json never committed, so meta ETag
      //     looks unchanged). Without this check, strokes written on
      //     another device and uploaded into an existing page are
      //     invisible here until the meta ETag eventually moves.
      // Also: a page the document lists and the server has, but whose data
      // this device lacks (e.g. pulled into memory but never persisted).
      final localDataMissing = s.document.pages.any((e) =>
          !s.pages.containsKey(e.fileName) &&
          changeState.pageEtags.containsKey(e.fileName));
      final innerInconsistent = localDataMissing ||
          changeState.pageEtags.length > s.document.pages.length ||
          (_sync.lastPageEtags.isNotEmpty &&
              changeState.pageEtags.keys.any((k) => !_sync.lastPageEtags.containsKey(k))) ||
          (_sync.lastPageEtags.isNotEmpty &&
              changeState.pageEtags.entries.any(
                  (e) => _sync.lastPageEtags[e.key] != null &&
                         _sync.lastPageEtags[e.key] != e.value));
      if (changeState.metaEtag != null &&
          (changeState.metaEtag != _sync.remoteMetaEtag || innerInconsistent)) {
        // Real work detected → reset idle counter so the next ticks
        // happen at the snappy 2 s cadence until things stabilise.
        // Watchdog: if we've been in the "inconsistent" loop too long
        // without progress (>= _maxInconsistentPulls in the window), do NOT
        // reset to the fast cadence — let adaptive backoff stretch the next
        // tick out. Defense-in-depth on top of the ghost-prune (which
        // normally converges in ~3 strikes); guards against any future
        // regression where state can't converge for unknown reasons.
        if (_sync.consecutiveInconsistentPulls < _maxInconsistentPulls) {
          _sync.idlePullCount = 0;
        } else {
          print('[Canvas] Pull watchdog: ${_sync.consecutiveInconsistentPulls} '
              'consecutive inconsistent pulls — suppressing fast-cadence '
              'reset, letting adaptive backoff engage');
        }
        if (changeState.metaEtag == _sync.remoteMetaEtag && innerInconsistent) {
          print('[Canvas] Meta ETag unchanged but pages/ folder grew '
              '(${changeState.pageEtags.length} remote vs '
              '${s.document.pages.length} local document). '
              'Hydrating orphan pages from server.');
          unawaited(CrashLogger.append(
            '[Pull] hydrating orphan pages despite matching meta ETag '
            '(remote pages=${changeState.pageEtags.length}, '
            'local doc=${s.document.pages.length})',
          ));
        } else {
          print('[Canvas] Delta metadata changed, pulling delta...');
        }
        // The pill is NOT flipped here — metadata ETag changes even when
        // nothing of substance was downloaded (e.g. same content re-uploaded
        // from this device, weak/strong ETag reformatting by the server).
        // Showing it every 4s during normal polling is distracting.
        // _pullFromDelta flips it only when real pages/assets will
        // actually be fetched.
        await _pullFromDelta(
          s, syncService, changeState.pageEtags,
        );
        await _advanceMetaEtag(changeState.metaEtag, pullNotebookId);
      }
    } finally {
      // Hand the lock to a background task that awaits any local-save
      // spawned by acceptRemoteChanges() before releasing. Without this
      // the next save() / pull can race the pulled ZIP rewrite on disk:
      //   • save() would overwrite the on-disk file before the pulled
      //     pages are persisted → pulled edits lost on next open
      //   • the _pageJsonCache would be re-populated out of order
      final pendingSave = _sync.pendingPulledLocalSave;
      if (pendingSave == null) {
        _releaseSyncLock(pullLockToken);
      } else {
        () async {
          try {
            await pendingSave;
          } catch (e) {
            print('[Canvas] Pending pulled-save failed: $e');
          } finally {
            // Clear only if still the same future (a later pull may have
            // replaced it).
            if (identical(_sync.pendingPulledLocalSave, pendingSave)) {
              _sync.pendingPulledLocalSave = null;
            }
            _releaseSyncLock(pullLockToken);
          }
        }();
      }
    }
  }


  /// Stage 3: moves the cached meta ETag on only when the pull fully hydrated
  /// the notebook that is still open.
  Future<void> _advanceMetaEtag(String? metaEtag, String pullNotebookId) async {
    // Only advance _sync.remoteMetaEtag if the notebook is STILL open and
    // still the same one we started the pull for. If the user closed
    // or switched mid-pull, the merge aborted and the pulled pages
    // never reached local disk — advancing the ETag here would tell
    // the next session "you're already in sync" and permanently lose
    // those pages.
    // Advance the cached meta ETag only when the pull fully hydrated
    // us — same notebook still open, no per-page failures, AND the
    // resulting state is internally consistent (every document entry
    // has page data in memory). Persisting an ETag that matches a
    // truncated local state is the wedge we spent this afternoon
    // chasing: next pull would fast-path skip, leaving missing pages
    // unreachable until manual "Forza sync".
    final stillOpen = _state != null && _state!.metadata.id == pullNotebookId;
    final sNow = stillOpen ? _state! : null;
    // Per-fileName check, not a length comparison: a local-only page
    // can make `pages.length >= document.pages.length` true while a
    // DIFFERENT document entry still has no page data. Advancing the
    // meta ETag in that state makes the gap permanent (next pull
    // fast-path skips). Require that EVERY document entry is backed by
    // page data in memory — exactly what the comment above intends.
    final stateConsistent = sNow == null
        ? false
        : sNow.document.pages.every((e) => sNow.pages.containsKey(e.fileName));
    if (stillOpen && !_sync.pullHadFailures && stateConsistent) {
      // Wait for the pulled-changes local save to land on disk BEFORE
      // persisting the meta ETag. Otherwise a crash/kill in the small
      // window between persist and save completion leaves the
      // _sync.remoteMetaEtag matching the server while the .ncnote zip is
      // still the pre-pull version — next open's fast path skips
      // because ETag matches, and the user is wedged at the old
      // page count until they manually force-sync.
      final pendingSave = _sync.pendingPulledLocalSave;
      if (pendingSave != null) {
        try {
          await pendingSave;
        } catch (e) {
          print('[Canvas] Pre-ETag save wait failed: $e');
        }
      }
      _alive();
      _sync.remoteMetaEtag = metaEtag;
      if (_sync.consecutiveFailedPulls > 0) {
        _sync.consecutiveFailedPulls = 0;
        _recomputeSyncStatus();
      }
      // Real progress (ETag advanced) → reset the inconsistent-loop
      // watchdog. The next inconsistent pull starts a fresh window.
      _sync.consecutiveInconsistentPulls = 0;
      _sync.consecutiveInconsistentSince = null;
      // Persist so next cold-start's first pull can skip immediately.
      // Awaited: SharedPreferences.setString is a few ms, and we need
      // it on disk before the caller assumes the ETag survived a crash.
      await _persistRemoteMetaEtag(pullNotebookId);
      unawaited(CrashLogger.append(
        '[Pull] ETag advanced: $metaEtag',
      ));
    } else if (_sync.pullHadFailures) {
      _sync.consecutiveFailedPulls++;
      _recomputeSyncStatus();
      print('[Canvas] Pull had failures — leaving _sync.remoteMetaEtag stale '
          'so next sync retries missing content');
      unawaited(CrashLogger.append(
        '[Pull] ETag not advanced: pull failed '
        '(${_sync.consecutiveFailedPulls} in a row, next in '
        '${pullIntervalForIdle().inSeconds}s)',
      ));
    } else if (stillOpen && !stateConsistent) {
      // Increment the watchdog inside a rolling window. Once it crosses
      // _maxInconsistentPulls, the slow-path branch above stops
      // resetting _sync.idlePullCount so the next tick is at the slower
      // adaptive cadence (eventually 30 s) instead of 2 s — preventing
      // any silent CPU loop if the ghost-prune ever fails to converge.
      final now = DateTime.now();
      if (_sync.consecutiveInconsistentSince == null ||
          now.difference(_sync.consecutiveInconsistentSince!) >
              _inconsistentWindow) {
        _sync.consecutiveInconsistentSince = now;
        _sync.consecutiveInconsistentPulls = 0;
      }
      _sync.consecutiveInconsistentPulls++;
      print('[Canvas] Pull done but state still inconsistent '
          '(pages=${sNow!.pages.length} < doc=${sNow.document.pages.length}) '
          '— leaving _sync.remoteMetaEtag stale so next pull retries '
          '[loop ${_sync.consecutiveInconsistentPulls}/$_maxInconsistentPulls]');
      unawaited(CrashLogger.append(
        '[Pull] ETag not advanced: state still mismatch '
        '(pages=${sNow.pages.length} < doc=${sNow.document.pages.length})',
      ));
    }
  }


  /// Pull changed pages from the exploded _delta/ folder.
  /// Uses per-page WebDAV ETags to detect which pages actually changed.
  /// Returns true if any pages were merged.
  /// The page ETags are the ones the caller already fetched.
  Future<bool> _pullFromDelta(
    CanvasState s,
    SyncService syncService,
    Map<String, String> remotePageEtags,
  ) async {
    print('[Canvas] Remote has ${remotePageEtags.length} pages, local cache has ${_sync.lastPageEtags.length} ETags');
    final plan = _planPull(s, remotePageEtags);
    if (plan == null) return false;
    final (:pagesToPull, :preKnownCorrupt, :deletedRemotelyByEtag) = plan;

    // Edge case: every "changed" page on the server was already known to
    // be corrupt at this very ETag. Nothing to network-fetch, but we still
    // need to push the heal save so the server gets fresh bytes — fall
    // through to the download path so the heal scheduling fires.
    if (pagesToPull.isEmpty && deletedRemotelyByEtag.isEmpty && preKnownCorrupt.isEmpty) {
      return _syncMetadataOnly(s, syncService, remotePageEtags);
    }

    print('[Canvas] Delta pull: ${pagesToPull.length} pages changed, '
        '${deletedRemotelyByEtag.length} pages deleted remotely');
    unawaited(CrashLogger.append(
      '[Pull] diff: pull=${pagesToPull.length} '
      '(${pagesToPull.take(3).join(",")}${pagesToPull.length > 3 ? "..." : ""}) '
      'del=${deletedRemotelyByEtag.length} '
      '(${deletedRemotelyByEtag.take(3).join(",")}${deletedRemotelyByEtag.length > 3 ? "..." : ""})',
    ));

    // Real download starting — show the "Sincronizzazione…" pill. Flipped
    // here (not in the outer PROPFIND-only cycle) so the indicator only
    // appears when we're actually bringing down new content, not during
    // the silent 4-second polling.
    isPullingFromRemote.value = true;
    try {
      return await _pullFromDeltaDownload(
        s, syncService, remotePageEtags, pagesToPull, deletedRemotelyByEtag,
        preKnownCorrupt,
      );
    } finally {
      if (!_core.isDisposed) {
        isPullingFromRemote.value = false;
        pullProgress.value = (done: 0, total: 0);
      }
    }
  }

  /// Stage 1: which pages to fetch, which the server dropped. Null when the
  /// listing looks like a transient failure, not a real mass delete.
  ({
    List<String> pagesToPull,
    List<String> preKnownCorrupt,
    Set<String> deletedRemotelyByEtag
  })? _planPull(CanvasState s, Map<String, String> remotePageEtags) {
    // Find pages whose WebDAV ETag changed since last pull, OR that exist
    // on the server but are missing from the local state.
    //
    // The second condition handles stale local caches: _initPageEtags may
    // have pre-populated _sync.lastPageEtags from the server, so a stale local
    // notebook (e.g. opened with 1 page when server has 100) would have
    // matching ETags for all 100 pages and download nothing. Checking
    // s.pages directly ensures every page the server has is materialised
    // locally, regardless of whether the ETag cache looks up-to-date.
    final pagesToPull = <String>[];
    final preKnownCorrupt = <String>[];
    for (final entry in remotePageEtags.entries) {
      final etagChanged = _sync.lastPageEtags[entry.key] != entry.value;
      final missingLocally = !s.pages.containsKey(entry.key);
      if (etagChanged || missingLocally) {
        // Dedup: if we've already confirmed the server bytes for this exact
        // ETag are corrupt, re-issuing the GET will hit the same bad bytes.
        // Skip the network round-trip and let the heal path handle it
        // directly — the upcoming save() will replace the corrupt server
        // file and produce a fresh ETag, at which point this skip no
        // longer matches and the next pull will re-fetch normally.
        if (_sync.knownCorruptEtags[entry.key] == entry.value) {
          // No copy here to heal it with: nothing to do until it changes.
          if (s.pages.containsKey(entry.key)) preKnownCorrupt.add(entry.key);
          continue;
        }
        pagesToPull.add(entry.key);
      }
    }

    // ── Mass-delete sanity check ──
    //
    // If the server's pages/ listing came back with DRASTICALLY FEWER
    // entries than what we have cached, this is almost certainly a
    // network/PROPFIND issue (partial response, proxy error, server
    // glitch) rather than a user genuinely deleting every page at once.
    // A previous version interpreted the 0-count case as 'all 183 pages
    // deleted' and auto-removed them from local state (then filled the
    // gaps with blank placeholders on the next pull), wiping hours of
    // work. Bail out of the pull completely when this pattern matches.
    //
    // Heuristic: server returned 0 AND we had >=5 cached, OR server
    // returned <50% of what we had cached AND cached was >=20. Either
    // case is implausible as a genuine operation and more plausible
    // as a networking glitch.
    if (_sync.lastPageEtags.isNotEmpty) {
      final cachedCount = _sync.lastPageEtags.length;
      final remoteCount = remotePageEtags.length;
      final suspicious = (remoteCount == 0 && cachedCount >= 5) ||
          (cachedCount >= 20 && remoteCount < cachedCount ~/ 2);
      if (suspicious) {
        print('[Canvas] Pull: ABORTING — server listing returned $remoteCount '
            'pages vs $cachedCount cached; refusing to treat as mass-delete '
            '(likely a transient PROPFIND failure). Next pull will retry.');
        unawaited(CrashLogger.append(
          '[Pull] abort: mass-delete-protection '
          '(remote=$remoteCount, cached=$cachedCount)',
        ));
        _sync.pullHadFailures = true; // force retry next cycle
        return null;
      }
    }

    // Detect pages that were deleted remotely (in our ETag cache but gone
    // from the remote pages/ folder listing).
    final deletedRemotelyByEtag = _sync.lastPageEtags.keys
        .where((k) => !remotePageEtags.containsKey(k))
        .toSet();

    // ── Structure-based deletion detection ──
    // ETag-based deletion detection (_sync.lastPageEtags diff above) already
    // catches remote deletions when we had an ETag for the page; the loop
    // below is the backstop for the "cache was fetched AFTER the delete"
    // path.
    //
    // IMPORTANT: we gate on `_sync.lastPageEtags.containsKey(fn)`, NOT
    // `_sync.lastSyncedPages`. `_sync.lastSyncedPages` is re-populated from the
    // local .ncnote on every open — which means it also contains pages
    // the user added offline and that have NEVER been uploaded. Using
    // that signal would classify brand-new local pages as "deleted
    // remotely" and silently drop them the first time the canvas pulls
    // ("ho aggiunto pagina 2 offline, chiuso e riaperto, è sparita").
    //
    // `_sync.lastPageEtags` only contains pages the server has acknowledged,
    // so it cleanly distinguishes "was on server, now gone" (true remote
    // delete) from "never been on server, still pending upload" (local-
    // only page to preserve and upload on the next save).
    for (final pageEntry in s.document.pages) {
      final fn = pageEntry.fileName;
      if (remotePageEtags.containsKey(fn)) continue; // still exists on remote
      if (deletedRemotelyByEtag.contains(fn)) continue; // already detected
      if (s.pages[fn] == null) continue; // no local data (nothing to delete)
      if (_sync.lastPageEtags.containsKey(fn)) {
        deletedRemotelyByEtag.add(fn);
      } else {
        print('[Canvas] Pull: page $fn exists locally but not on server — '
            'treating as pending upload (never synced), NOT a remote delete');
      }
    }
    return (
      pagesToPull: pagesToPull,
      preKnownCorrupt: preKnownCorrupt,
      deletedRemotelyByEtag: deletedRemotelyByEtag
    );
  }

  /// Stage 2, nothing to fetch: the meta ETag moved, so adopt a metadata-only
  /// change (title, chapters, order) by a 3-way merge. Always false.
  Future<bool> _syncMetadataOnly(CanvasState s, SyncService syncService,
      Map<String, String> remotePageEtags) async {
    // ── Metadata-only change check ───────────────────────────────────
    // We're here because the meta-ETag moved (slow path was triggered)
    // but no per-page ETag changed. The most common cause is a metadata-
    // only edit on another device: chapter renamed, chapter added with
    // no pages yet, title changed, paper type changed. The old code
    // dropped through to the ETag-advance path without ever downloading
    // metadata.json/document.json — so a chapter rename done on PC was
    // INVISIBLE on iPad until the next page edit happened to bump a
    // page ETag. Now we always pull the metadata pair when the slow
    // path fires, and apply any content changes so they propagate.
    try {
      final remoteMeta =
          await syncService.downloadDeltaMetaVersioned(s.metadata.id);
      if (_state != null && _state!.metadata.id == s.metadata.id) {
        // 3-way merge against the LIVE state (not the pull-start snapshot)
        // so a reorder / chapter-move / rename the user made during this
        // tick isn't clobbered by the remote metadata. No page data moved on
        // this path (pagesToPull empty), so any doc entry without local data
        // is NOT on the server (else it'd be in pagesToPull) → a ghost. Prune
        // it via the strike policy so a long-broken document.json (more
        // entries than real pages) finally converges instead of pinning the
        // pull in a hot retry loop forever.
        final live = _state!;
        final surviving = survivingFileNames(
          withData: live.pages.keys,
          docPages: live.document.pages,
          serverFileNames: remotePageEtags.keys.toSet(),
          remoteDeleted: const {},
        );
        final merged = merge3Way(
          baseMeta: _sync.lastSyncedMetadata,
          localMeta: live.metadata,
          remoteMeta: remoteMeta.metadata,
          baseDoc: _sync.lastSyncedDocument,
          localDoc: live.document,
          remoteDoc: remoteMeta.document,
          survivingFileNames: surviving,
        );
        final finalDoc = merged.document;
        final finalMeta =
            merged.metadata.copyWith(pageCount: finalDoc.pages.length);
        final changed = documentStructurallyDiffers(
                finalDoc, live.document) ||
            metadataStructurallyDiffers(
                finalMeta, live.metadata);
        if (changed) {
          // Mark dirty only when our merge differs from what the server has
          // (local-side edits to push) AND the document is internally
          // consistent — pushing while data-less entries remain would just
          // trip PRE-SAVE GUARD #2 → abort → pull → hot loop. Defer until the
          // ghost-prune / hydration makes it consistent.
          final docConsistent = finalDoc.pages
              .every((e) => live.pages.containsKey(e.fileName));
          final needsPush = docConsistent &&
              (documentStructurallyDiffers(
                      finalDoc, remoteMeta.document) ||
                  metadataStructurallyDiffers(
                      finalMeta, remoteMeta.metadata));
          _state = live.copyWith(
            metadata: finalMeta,
            document: finalDoc,
            isDirty: needsPush || live.isDirty,
          );
          // Adopting the remote order/chapters/title only changed memory:
          // with the meta ETag now marked seen, a reopen loaded the old
          // page list from disk and never pulled it again.
          if (!needsPush) {
            _sync.pendingPulledLocalSave = _savePulledChangesLocally(
                finalMeta, finalDoc, live.pages, live.assetBytes);
          }
          print('[Canvas] Pull noop: merged metadata/structure '
              '(needsPush=$needsPush) — chapters/title/paper/order');
          unawaited(CrashLogger.append(
            '[Pull] noop: 3-way merged metadata/structure '
            '(needsPush=$needsPush)',
          ));
        }
        // Baseline tracks SERVER TRUTH regardless of whether we adopted a
        // change, so the next merge has the correct common ancestor.
        _sync.lastSyncedDocument = remoteMeta.document;
        _sync.remoteDocVersion = remoteMeta.docVersion;
        _sync.lastSyncedMetadata = remoteMeta.metadata;
      }
    } catch (e) {
      // Don't fail the whole pull on a metadata-fetch hiccup; next pull
      // will retry. The ETag advance below means we WON'T retry — but
      // that's fine: any subsequent metadata edit will move the meta
      // ETag again and trigger another slow-path tick.
      print('[Canvas] Pull noop: metadata-content check failed: $e');
    }
    _alive();

    print('[Canvas] Delta pull: no page ETags changed, no deletions');
    unawaited(CrashLogger.append(
      '[Pull] diff: noop (remote=${remotePageEtags.length} '
      'cached=${_sync.lastPageEtags.length} state=${s.pages.length})',
    ));
    _sync.lastPageEtags = Map.of(remotePageEtags);
    // Await the persist — the user can close the notebook during the
    // 'noop' tick of the pull loop, and if the unawaited write hadn't
    // landed yet the next open would reset _sync.lastPageEtags to empty and
    // force a full 183-page re-sync next time.
    await _persistLastPageEtags(s.metadata.id);
    return false;
  }

  Future<bool> _pullFromDeltaDownload(
    CanvasState s,
    SyncService syncService,
    Map<String, String> remotePageEtags,
    List<String> pagesToPull,
    Set<String> deletedRemotelyByEtag,
    List<String> preKnownCorrupt,
  ) async {
    final run = _PullRun(s, syncService, remotePageEtags, pagesToPull,
        deletedRemotelyByEtag, preKnownCorrupt);
    // Download metadata + changed pages in parallel (one round-trip)
    _startMetaDownload(run);
    await _downloadPages(run);
    _alive();
    if (!await _awaitRemoteMeta(run)) return false;
    _alive();
    _dropUnreceivedEtags(run);
    await _downloadAssets(run);
    _alive();
    final deletionConflicts = _detectRemoteDeletions(run);

    // Notebook-switch guard: if the user opened a different notebook while
    // we were downloading pages/assets, this data belongs to the old one.
    // Writing it to state would corrupt the now-active notebook.
    if (_state == null || _state!.metadata.id != s.metadata.id) {
      print('[Canvas] Delta merge aborted — notebook switched mid-pull '
          '(expected ${s.metadata.id}, got ${_state?.metadata.id})');
      return false;
    }

    // Enter the merge/accept block when ANY of the following is true:
    //   - we successfully pulled at least one page (anyPageChanged)
    //   - we detected a remote deletion that needs reconciling
    //   - we detected at least one page that's corrupt on the server
    //     (heal-via-reupload path; needs to land in pendingRemoteChanges
    //     so acceptRemoteChanges + the corruption-heal post-step run and
    //     the auto-save Timer is scheduled). Without this third guard,
    //     a pull where ALL changed pages are corrupt skips the entire
    //     block, never schedules the save, and the loop continues
    //     forever.
    if ((run.anyPageChanged ||
            deletionConflicts.isNotEmpty ||
            run.corruptedPages.isNotEmpty) &&
        _state != null) {
      _mergeIntoState(run, deletionConflicts);
    }
    _sync.lastPageEtags = Map.of(run.remotePageEtags);
    // Await — if we only 'unawait' this, a notebook close fires right
    // after a successful pull race the SharedPreferences write and the
    // next open wakes up with _sync.lastPageEtags={} → forces a full N-page
    // re-sync even though nothing on the server changed.
    await _persistLastPageEtags(s.metadata.id);
    return run.anyPageChanged;
  }

  /// Stage 6: decides what the pulled pages mean for the open notebook.
  void _mergeIntoState(_PullRun run, List<PageConflict> deletionConflicts) {
    final (:conflicts, :safePages, :autoMergeable) =
        _classifyPageChanges(run, deletionConflicts);
    final (:details, :newCount, :modCount) = _describeChanges(run, safePages);
    final (:mergedDocument, :orphanSynthEntries) = _healedDocument(run);
    _applyPulled(run, deletionConflicts, conflicts, details, newCount, modCount,
        autoMergeable, mergedDocument, orphanSynthEntries);
  }

  /// Stage 0: starts the document and metadata download, in parallel with the pages.
  void _startMetaDownload(_PullRun run) {
    final s = run.s;
    run.metaFuture = run.syncService
        .downloadDeltaMetaVersioned(s.metadata.id)
        .then((r) {
      _sync.pendingDocVersion = r.docVersion;
      return (metadata: r.metadata, document: r.document);
    });
  }

  /// Stage 1: the changed pages, with retries, cooldown and corruption handling.
  Future<void> _downloadPages(_PullRun run) async {
    final s = run.s;
    final syncService = run.syncService;
    final pagesToPull = run.pagesToPull;
    final preKnownCorrupt = run.preKnownCorrupt;
    final updatedPages = run.updatedPages;
    // ── Per-page download with retry + live progress counter ──
    //
    // The previous code fired `Future.wait` with a single attempt per
    // page; any transient failure (Tailscale relay flap, Nextcloud
    // hiccup, TLS reset) dropped that page and left the user's notebook
    // incomplete until the NEXT 4-second pull cycle fired.  For a
    // 100-page first-time hydration over a flaky network that could mean
    // minutes of incomplete state without any visible progress.
    //
    // Now each page has its own 3-attempt retry loop with exponential
    // backoff, capped by [AppConfig.webdavDeltaTimeoutSeconds] per attempt.
    // A live counter feeds [pullProgress] so the sync pill can show
    // "Sincronizzazione 23/100" instead of a generic spinner.
    final completed = <String>[];
    final failedPages = <String>[];
    // Pages whose server-side bytes are CORRUPT (e.g. JSON truncated mid-
    // stroke at a 1024-byte boundary, observed when an interrupted PUT
    // from another device left a partial body on Nextcloud). These do
    // NOT count as transient failures: re-downloading will hit the same
    // bad bytes forever, so we must NOT block the meta-ETag advance and
    // MUST NOT apply the per-page cooldown — that combination is exactly
    // what produced the every-2-second pull-loop hammering the server.
    // Instead we hand the page back to save() with the local-good copy
    // re-flagged as dirty, so the next save heals the server.
    //
    // Seeded with pages whose current server ETag matches an entry in
    // [_sync.knownCorruptEtags] — those were already proven corrupt this
    // session, so we skip the redundant GET entirely.
    final corruptedPages = <String>[...preKnownCorrupt];
    if (preKnownCorrupt.isNotEmpty) {
      print('[Canvas] Pull: skipping ${preKnownCorrupt.length} GET(s) for '
          'pages already known corrupt at their current server ETag '
          '(sample: ${preKnownCorrupt.take(3).join(",")}'
          '${preKnownCorrupt.length > 3 ? "..." : ""}) — heal via save '
          'will run');
    }
    var completedCount = 0;

    // ── Per-page failure cooldown (P2) ──
    //
    // Skip pages that have failed [maxConsecutiveFailures] times in a row
    // until [pageCooldown] has elapsed since the last failure. Without this
    // the same 8 broken downloads (e.g. server-side gone, permission glitch,
    // bad bytes) re-fired every 2 s pull cycle forever, draining battery
    // and the IOClient connection pool. After the cooldown a single retry
    // is allowed; if it succeeds counters reset, otherwise the cooldown
    // is reapplied.
    const maxConsecutiveFailures = 5;
    const pageCooldown = Duration(seconds: 60);
    final now = DateTime.now();
    final cooledDown = <String>[];
    pagesToPull.removeWhere((fn) {
      final until = _sync.pageFailureCooldownUntil[fn];
      if (until != null && now.isBefore(until)) {
        cooledDown.add(fn);
        return true;
      }
      return false;
    });
    if (cooledDown.isNotEmpty) {
      _sync.pullHadFailures = true; // keep meta etag stale until they recover
      unawaited(CrashLogger.append(
        '[Pull] cooldown skip: ${cooledDown.length} pages '
        '(sample: ${cooledDown.take(3).join(",")}'
        '${cooledDown.length > 3 ? "..." : ""}) — '
        'will retry after cooldown expires',
      ));
    }
    // Refresh totals after cooldown filter so the progress pill is honest.
    pullProgress.value = (done: 0, total: pagesToPull.length);

    Future<void> pullOne(String pageFileName) async {
      const maxAttempts = 3;
      Object? lastError;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        try {
          final remotePage = await syncService.downloadDeltaPage(
              s.metadata.id, pageFileName,
              version: run.remotePageEtags[pageFileName]);
          updatedPages[pageFileName] = remotePage;
          run.anyPageChanged = true;
          completed.add(pageFileName);
          completedCount++;
          pullProgress.value =
              (done: completedCount, total: pagesToPull.length);
          // Success: reset failure tracking for this page.
          _sync.pageFailureCount.remove(pageFileName);
          _sync.pageFailureCooldownUntil.remove(pageFileName);
          return;
        } catch (e) {
          lastError = e;
          // ── Server-side corruption short-circuit ──
          // FormatException from `jsonDecode(utf8.decode(bytes))` means
          // the bytes the server gave us are not valid JSON — typically
          // truncated mid-stroke at a 1024-byte boundary because an
          // earlier PUT from some device only partially committed.
          // Re-trying the download won't help (the bad bytes are stable
          // on the server), and the FormatException is wrapped as a
          // bare Exception by the http path, so we sniff the message
          // too. We bail out of the retry loop immediately and let the
          // outer code reroute this page through the heal-via-reupload
          // path instead of the network-failure path.
          final isCorruption = e is FormatException ||
              e.toString().contains('FormatException');
          if (isCorruption) {
            corruptedPages.add(pageFileName);
            // Reset any prior cooldown — corruption is a one-shot
            // categorisation, not a flaky-network counter.
            _sync.pageFailureCount.remove(pageFileName);
            _sync.pageFailureCooldownUntil.remove(pageFileName);
            // Remember the exact server ETag we just confirmed corrupt
            // so subsequent pull cycles before save() lands skip the
            // GET entirely (the bad bytes are stable; re-downloading
            // them just burns bandwidth).
            final corruptEtag = run.remotePageEtags[pageFileName];
            if (corruptEtag != null) {
              _sync.knownCorruptEtags[pageFileName] = corruptEtag;
            }
            print('[Canvas] Page $pageFileName: server-side JSON '
                'corruption detected ($e) — scheduling heal via '
                're-upload from local copy');
            return;
          }
          if (attempt == maxAttempts - 1) break;
          // Exponential backoff: 200 ms, 600 ms, 1.8 s.
          await Future.delayed(
              Duration(milliseconds: 200 * (1 << attempt)));
          // Abort all further attempts if the notebook was closed.
          if (_core.isDisposed || _state?.metadata.id != s.metadata.id) return;
        }
      }
      failedPages.add(pageFileName);
      _sync.pullHadFailures = true;
      // Track consecutive failures so we can apply a cooldown next pull.
      final fc = (_sync.pageFailureCount[pageFileName] ?? 0) + 1;
      _sync.pageFailureCount[pageFileName] = fc;
      if (fc >= maxConsecutiveFailures) {
        _sync.pageFailureCooldownUntil[pageFileName] =
            DateTime.now().add(pageCooldown);
        print('[Canvas] Page $pageFileName failed $fc times — '
            'applying ${pageCooldown.inSeconds}s cooldown');
      }
      print('[Canvas] Failed to pull page $pageFileName '
          'after $maxAttempts attempts: $lastError');
    }

    // Pull pages with explicit concurrency cap (NOT via the IOClient pool).
    // The pool's queueing piles every in-flight GET onto the same N
    // sockets — when those go stale together (typical Tailscale signature:
    // middlebox closes idle keep-alive after ~30 s), dozens of queued
    // requests all surface "Connection closed" before the circuit
    // breaker rebuilds the client. With an explicit worker pool we only
    // ever have [batchSize] requests in flight: a stale-pool burst trips
    // ONE rebuild, the next batchSize requests use the fresh pool, and
    // the cascade stops at batchSize instead of pagesToPull.length.
    const batchSize = 4;
    final queue = List<String>.from(pagesToPull);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (_core.isDisposed || _state?.metadata.id != s.metadata.id) return;
        final fn = queue.removeLast();
        await pullOne(fn);
      }
    }
    final workers = List.generate(
        batchSize < queue.length ? batchSize : queue.length,
        (_) => worker());
    await Future.wait(workers);
    // A corrupt server page this device never had cannot be healed by a
    // re-upload: healing marked the notebook dirty and rewrote its metadata
    // on every pull, forever. Left alone until another device rewrites it.
    final unhealable =
        corruptedPages.where((fn) => !s.pages.containsKey(fn)).toList();
    if (unhealable.isNotEmpty) {
      corruptedPages.removeWhere(unhealable.contains);
      unawaited(CrashLogger.append('[Pull] unreadable on the server and '
          'not on this device, left alone: ${unhealable.join(",")}'));
    }
    run.completed = completed;
    run.failedPages = failedPages;
    run.corruptedPages = corruptedPages;
    run.cooledDown = cooledDown;
  }

  /// Stage 2: waits for the document and metadata; false when they failed.
  Future<bool> _awaitRemoteMeta(_PullRun run) async {
    final completed = run.completed;
    // ── Defensive meta-fetch: never let document.json / metadata.json
    //    failure abort the whole pull cycle.
    //
    // metaFuture is downloadDeltaMeta() which throws on truncated /
    // empty / unparseable body (very common during Tailscale flaps:
    // server closes the connection mid-response → 200 OK with 0
    // bytes → jsonDecode('') → FormatException). If we let that
    // propagate, the function aborts BEFORE line 7836 where per-page
    // ETags get persisted. Next pull tick sees _sync.lastPageEtags = 1
    // again and tries the full 102-page re-pull from scratch — the
    // infinite-loop bug.
    //
    // On meta failure: mark _sync.pullHadFailures so the meta ETag stays
    // stale (next tick will retry the whole cycle) and return false.
    try {
      run.remoteMeta = await run.metaFuture;
    } catch (e) {
      _alive();
      print('[Canvas] Meta fetch failed mid-pull '
          '(${completed.length} pages still got through): $e');
      _sync.pullHadFailures = true;
      // None of the downloaded pages was merged: their ETags stay unrecorded
      // so the next pull fetches and merges them.
      return false;
    }

    return true;
  }

  /// Stage 3: logs the download and keeps the ETags only of what arrived.
  void _dropUnreceivedEtags(_PullRun run) {
    final pagesToPull = run.pagesToPull;
    final completed = run.completed;
    final failedPages = run.failedPages;
    final corruptedPages = run.corruptedPages;
    final cooledDown = run.cooledDown;
    if (run.anyPageChanged) {
      print('[Canvas] Pulled ${completed.length}/${pagesToPull.length} pages '
          '(${failedPages.length} failed, ${corruptedPages.length} corrupt → reupload)');
    }
    unawaited(CrashLogger.append(
      '[Pull] download done: ok=${completed.length}/${pagesToPull.length} '
      'failed=${failedPages.length}'
      '${failedPages.isEmpty ? "" : " (${failedPages.take(3).join(",")})"} '
      'corrupt=${corruptedPages.length}'
      '${corruptedPages.isEmpty ? "" : " (${corruptedPages.take(3).join(",")})"}',
    ));
    // Evict per-page ETags for any download that failed so the next pull
    // re-attempts them; we must NOT advance _sync.lastPageEtags for pages we
    // didn't actually receive. Also evict pages we skipped due to the
    // cooldown — they still haven't been received either. And evict
    // corrupt-on-server pages so the next save() (which uploads the
    // local-good copy) is followed by a pull that DOES re-fetch the
    // freshly-correct bytes — leaving the corrupt etag in our cache
    // would make the post-heal pull skip them.
    if (failedPages.isNotEmpty || cooledDown.isNotEmpty || corruptedPages.isNotEmpty) {
      run.remotePageEtags = Map.of(run.remotePageEtags);
      for (final fn in failedPages) {
        // Keep the previous ETag we had (if any) so the "changed" comparison
        // still picks this page up next time the ETag actually changes again,
        // but ensure the new remotePageEtags entry for this file does NOT
        // make it into _sync.lastPageEtags below.
        run.remotePageEtags.remove(fn);
      }
      for (final fn in cooledDown) {
        run.remotePageEtags.remove(fn);
      }
      for (final fn in corruptedPages) {
        run.remotePageEtags.remove(fn);
      }
    }

  }

  /// Stage 4: the assets the pulled pages need, current page first.
  Future<void> _downloadAssets(_PullRun run) async {
    final s = run.s;
    final syncService = run.syncService;
    final updatedPages = run.updatedPages;
    final updatedAssets = run.updatedAssets;
    // Download new assets in parallel
    // Collect asset references from both assetReferences list AND image elements.
    //
    // An asset is considered "missing" and worth pulling from the server if:
    //   1. It's NOT in the local assetBytes map, OR
    //   2. It IS in the local map but flagged as corrupt — this is the
    //      heal path for the historic 1024-aligned-truncation bug. If
    //      another device re-uploaded clean bytes after we cached the
    //      corrupt copy, the path hasn't changed and the previous
    //      `containsKey` short-circuit kept the broken bytes forever.
    //      Re-fetching forces a fresh decode attempt; on success
    //      `_decodeAndCacheImage` clears the corrupt flag.
    final missingAssets = <String>{};
    bool needsHeal(String ref) =>
        !_knownAbsent(ref) &&
        (!updatedAssets.containsKey(ref) || _assets.corruptAssetIds.contains(ref));
    for (final page in updatedPages.values) {
      // Only what an image element draws: assetReferences is append-only and
      // keeps ids of deleted images, which were fetched (404) on every pull.
      for (final el in page.layers.content) {
        el.map(unknown: (_) {},
          stroke: (_) {},
          text: (_) {},
          shape: (_) {},
          math: (_) {},
          image: (img) {
            final path = img.data.assetPath;
            if (path.isNotEmpty && needsHeal(path)) {
              missingAssets.add(path);
            }
          },
        );
      }
    }
    // Drop the cached bytes for any asset we're about to re-pull so the
    // download path actually writes the fresh bytes back instead of
    // short-circuiting on "already in updatedAssets".
    for (final ref in missingAssets) {
      updatedAssets.remove(ref);
    }
    // ── Asset download: priority (current page) sync, rest in background ─
    //
    // Previously the entire asset download was awaited inline before the
    // function could return. For an asset-heavy notebook (Automotive: 200+
    // assets / 60+ MB) over Tailscale the awaited pull took 2-5 minutes,
    // and the meta-ETag persist (which happens AFTER this function returns)
    // never ran if the user closed the app during that window. Result:
    // every reopen replayed a full 389-page slow-path pull because
    // `_sync.remoteMetaEtag` was still null on disk.
    //
    // Now we only await the current page's assets (so the visible page
    // renders correctly when this function returns); the rest fire as an
    // unawaited background task that updates `state.assetBytes` incremen-
    // tally and marks the notebook dirty so the next save flushes them to
    // the .ncnote zip. The ETag can advance as soon as page commit + local
    // save complete, independent of asset progress.
    if (missingAssets.isNotEmpty) {
      final maxAssetConcurrency = (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android)
          ? 4
          : 6;
      final notebookId = s.metadata.id;
      final curPageRefs =
          _assets.refsForPage(s.currentPageIndex, s.document, updatedPages);
      final priorityList =
          missingAssets.where(curPageRefs.contains).toList();
      final backgroundList =
          missingAssets.where((r) => !curPageRefs.contains(r)).toList();

      Future<(String, Uint8List?, Object?)> pullOneAsset(String ref) async {
        const maxAttempts = 3;
        Object? lastError;
        for (var attempt = 0; attempt < maxAttempts; attempt++) {
          try {
            final data = await syncService.downloadDeltaAsset(notebookId, ref);
            return (ref, data, null);
          } catch (e) {
            lastError = e;
            // Not on the server: retrying (now or next pull) can't help.
            if (e is RemoteStoreException && e.statusCode == 404) {
              _sync.absentRemoteAssets[ref] = DateTime.now();
              unawaited(CrashLogger.append('[Pull] asset missing on the '
                  'server, asked again in 10 min: $ref'));
              break;
            }
            if (attempt == maxAttempts - 1) break;
            await Future.delayed(
                Duration(milliseconds: 200 * (1 << attempt)));
            if (_core.isDisposed || _state?.metadata.id != notebookId) {
              return (ref, null, lastError);
            }
          }
        }
        return (ref, null, lastError);
      }

      // Priority pass: await current-page assets so the visible page renders
      // correctly when the function returns.
      final priorityDownloaded = <String, Uint8List>{};
      for (var i = 0; i < priorityList.length; i += maxAssetConcurrency) {
        if (_core.isDisposed) break;
        final batch = priorityList.skip(i).take(maxAssetConcurrency);
        final batchResults = await Future.wait(batch.map(pullOneAsset));
        for (final (ref, data, err) in batchResults) {
          if (data != null) {
            updatedAssets[ref] = data;
            priorityDownloaded[ref] = data;
            run.anyPageChanged = true;
          } else if (err != null) {
            print('[Canvas] Failed to pull priority asset $ref: $err '
                '(will retry next pull)');
          }
        }
      }
      if (priorityDownloaded.isNotEmpty) {
        for (final entry in priorityDownloaded.entries) {
          unawaited(_assets.decodeAndCache(entry.key, entry.value));
        }
      }

      // Background pass: fire-and-forget. Aborts if the user switches notebooks.
      //
      // Previously this `state = state!.copyWith(assetBytes: merged)` ran
      // PER-BATCH — and `merged` was a fresh `Map<String, Uint8List>.from(50MB)`
      // every iteration, plus every state mutation cascaded into a full
      // rebuild of the canvas widget tree (which `ref.watch(canvasProvider)`s
      // the entire state). On a 60-asset notebook the rebuild storm + Map
      // re-allocations alone burned a CPU core for the whole download
      // window. Now we accumulate every batch into a local map and commit
      // ONCE at the end of the pass — image decoding still streams in
      // (each batch fires `_decodeAndCacheImage` so the canvas can show
      // them as soon as they're decoded).
      //
      // We also no longer flip `isDirty=true`: the assets are reachable
      // from `_pageJsonCache` lookups and will be flushed by the NEXT
      // user-driven save, which is enough — flipping dirty here triggered
      // a full-notebook 50 MB ZIP rebuild + remote sync just because some
      // bytes arrived from the server, which is exactly the work we want
      // to avoid.
      if (backgroundList.isNotEmpty) {
        unawaited(() async {
          final bgDownloaded = <String, Uint8List>{};
          int bgOk = 0;
          int bgFailed = 0;
          for (var i = 0;
              i < backgroundList.length;
              i += maxAssetConcurrency) {
            if (_core.isDisposed || _state?.metadata.id != notebookId) break;
            final batch =
                backgroundList.skip(i).take(maxAssetConcurrency);
            final batchResults = await Future.wait(batch.map(pullOneAsset));
            for (final (ref, data, err) in batchResults) {
              if (data != null) {
                bgDownloaded[ref] = data;
                bgOk++;
                // Decode now so the canvas paints the asset as soon as
                // each batch resolves — _decodeAndCacheImage updates
                // state.imageCache atomically and is independent of the
                // assetBytes commit below.
                unawaited(_assets.decodeAndCache(ref, data));
              } else if (err != null) {
                bgFailed++;
                print('[Canvas] Failed to pull bg asset $ref: $err '
                    '(will retry next pull)');
              }
            }
          }
          print('[Canvas] Background asset pull done: '
              '$bgOk/${backgroundList.length} ok, $bgFailed failed');
          // Single commit at the end. Skip if the notifier was disposed
          // or the notebook closed mid-pass — without the _disposed check
          // a post-dispose `state = ...` would set a value on a notifier
          // Riverpod considers torn-down, surfacing as "tried to use
          // ProviderContainer after it was disposed" if any listener
          // outlives the dispose.
          if (!_core.isDisposed &&
              bgDownloaded.isNotEmpty &&
              _state != null &&
              _state!.metadata.id == notebookId) {
            final merged = Map<String, Uint8List>.from(_state!.assetBytes)
              ..addAll(bgDownloaded);
            _state = _state!.copyWith(assetBytes: merged);
            // Anything we just pulled from the server is by definition
            // server-confirmed. Mark these as eligible for future
            // server-side DELETE (used by _pruneOrphanAssets).
            _sync.uploadedAssetKeys.addAll(bgDownloaded.keys);
          }
        }());
      }
    }
    run.missingAssets = missingAssets;
  }

  /// Stage 5: pages the server dropped; a locally edited one becomes a conflict.
  List<PageConflict> _detectRemoteDeletions(_PullRun run) {
    final s = run.s;
    final deletedRemotelyByEtag = run.deletedRemotelyByEtag;
    final updatedPages = run.updatedPages;
    // ── Detect remote deletions: pages in local state but gone from
    //    remote pages/ folder ──
    final deletionConflicts = <PageConflict>[];

    if (deletedRemotelyByEtag.isNotEmpty) {
      for (final fileName in deletedRemotelyByEtag) {
        final localPage = s.pages[fileName];
        if (localPage == null) continue;
        // Was this page edited locally since last sync?
        final locallyEdited = _sync.lastSyncedPages[fileName] != null &&
            localPage != _sync.lastSyncedPages[fileName];
        if (locallyEdited) {
          // Conflict: local edit vs remote deletion — let user decide
          final pageIndex = s.document.pages.indexWhere(
              (e) => e.fileName == fileName);
          final pageEntry = pageIndex >= 0
              ? s.document.pages[pageIndex] : null;
          final chapterName = chapterNameForPage(pageEntry, s.metadata);
          deletionConflicts.add(PageConflict(
            fileName: fileName,
            pageNumber: localPage.pageNumber,
            chapterName: chapterName,
            localPage: localPage,
            remotePage: localPage, // no remote version — show local as both
            localImageCache: Map.of(_state!.imageCache),
            remoteImageCache: const {},
            isDeletion: true,
          ));
          print('[Canvas] CONFLICT: $fileName edited locally but deleted remotely');
        } else {
          // Safe deletion — auto-remove
          updatedPages.remove(fileName);
          run.anyPageChanged = true;
          print('[Canvas] Auto-removing page deleted remotely: $fileName');
        }
      }
    }
    return deletionConflicts;
  }

  /// Stage 6a: which pulled pages merge silently and which clash with local edits.
  ({List<PageConflict> conflicts, Set<String> safePages, Set<String> autoMergeable}) _classifyPageChanges(_PullRun run, List<PageConflict> deletionConflicts) {
    final s = run.s;
    final pagesToPull = run.pagesToPull;
    final updatedPages = run.updatedPages;
    final remoteMeta = run.remoteMeta;
    // ── Detect conflicts: pages changed both locally AND remotely ──
    final conflicts = <PageConflict>[...deletionConflicts];
    final safePages = <String>{}; // non-conflicting remote pages
    // fileNames where both sides edited but the edits look disjoint
    // (element-level) → auto-merge at apply time instead of prompting.
    final autoMergeable = <String>{};
    for (final fileName in pagesToPull) {
      final remotePage = updatedPages[fileName];
      final localPage = s.pages[fileName];
      if (remotePage == null) continue;

      // Skip pages where local and remote have identical content —
      // no conflict and no change to report.
      // Compare without modifiedAt: a re-upload of identical content sets a
      // new modifiedAt timestamp, but that is NOT a real conflict.
      if (localPage != null &&
          localPage.copyWith(modifiedAt: null) ==
              remotePage.copyWith(modifiedAt: null)) {
        continue;
      }

      // Conflict: local page was edited since last sync AND remote ALSO
      // diverged from that same baseline. Classic 3-way merge: if only one
      // side moved, it's not a conflict.
      //
      // The remoteEdited check matters on flaky networks: when a save's
      // upload reaches the server but the response packet is dropped, the
      // iPad thinks the save failed and leaves lastSynced at the old
      // baseline. Subsequent local edits then look "edited locally", and
      // the next pull sees the server's new ETag (matching what the iPad
      // just uploaded) and pulls it back — without remoteEdited the user
      // gets a false conflict prompt for their own pending work.
      // Compare without modifiedAt so a sync-induced timestamp change on
      // otherwise-identical content doesn't register as edited.
      final lastSynced = _sync.lastSyncedPages[fileName];
      final lastSyncedNorm = lastSynced?.copyWith(modifiedAt: null);
      final locallyEdited = localPage != null &&
          lastSynced != null &&
          localPage.copyWith(modifiedAt: null) != lastSyncedNorm;
      final remoteEdited = lastSynced != null &&
          remotePage.copyWith(modifiedAt: null) != lastSyncedNorm;
      if (locallyEdited && remoteEdited) {
        // Before prompting, try an element-level 3-way merge: if the two
        // sides touched DIFFERENT strokes/images/shapes/text, we can fold
        // them together silently — no dialog, which keeps the experience
        // smooth (most "same page" edits on different devices are actually
        // disjoint). Only a genuine same-element clash surfaces a prompt.
        // acceptRemoteChanges re-runs this with the LIVE local page; here
        // we only DECIDE (against the snapshot) whether a prompt is needed.
        // lastSynced and localPage are both non-null here (locallyEdited
        // implies it), so Dart has already promoted them.
        final autoMerged = mergePageElements(
            base: lastSynced, local: localPage, remote: remotePage);
        if (autoMerged != null) {
          autoMergeable.add(fileName);
          safePages.add(fileName);
          print('[Canvas] Auto-mergeable (disjoint element edits): $fileName');
        } else {
          final pageIndex = remoteMeta.document.pages.indexWhere(
              (e) => e.fileName == fileName);
          final pageEntry = pageIndex >= 0
              ? remoteMeta.document.pages[pageIndex]
              : null;
          final chapterName = chapterNameForPage(pageEntry, remoteMeta.metadata);
          conflicts.add(PageConflict(
            fileName: fileName,
            pageNumber: remotePage.pageNumber,
            chapterName: chapterName,
            localPage: localPage,
            remotePage: remotePage,
            localImageCache: Map.of(_state!.imageCache),
            remoteImageCache: Map.of(_state!.imageCache),
          ));
          print('[Canvas] CONFLICT on $fileName — local + remote edits '
              'touch the same element(s)');
        }
      } else if (locallyEdited && !remoteEdited) {
        // Local has unsynced edits but remote is unchanged from baseline:
        // the server's "new" ETag is just our own pending upload echoing
        // back (or a touched mtime on identical bytes). Keep local content
        // by reverting the merge map; the next save will push local up.
        // Without this, the safePages branch would overwrite the user's
        // in-progress strokes with the older remote bytes — exactly the
        // data-loss bug behind the false-conflict UX on flaky links.
        //
        // `localPage != null` is already implied by `locallyEdited`.
        updatedPages[fileName] = localPage;
        print('[Canvas] Pull: $fileName changed remotely but matches '
            'baseline; preserving local edits');
      } else {
        safePages.add(fileName);
      }
    }

    return (conflicts: conflicts, safePages: safePages, autoMergeable: autoMergeable);
  }

  /// Stage 6b: the per-page change list the user is told about.
  ({List<PageChangeDetail> details, int newCount, int modCount}) _describeChanges(_PullRun run, Set<String> safePages) {
    final s = run.s;
    final updatedPages = run.updatedPages;
    final remoteMeta = run.remoteMeta;
    // ── Build per-page change details for non-conflicting pages ──
    // Skip pages whose content is identical to local (same ETag ≠ same
    // content, but downloading gave us the actual data to compare).
    final details = <PageChangeDetail>[];
    var newCount = 0;
    var modCount = 0;
    for (final fileName in safePages) {
      final remotePage = updatedPages[fileName];
      final localPage = s.pages[fileName];
      if (remotePage == null) continue;
      final isNew = localPage == null;
      // Content-equality check: if the downloaded page has the same
      // data as local, don't report it as modified.
      if (!isNew && localPage == remotePage) {
        // Silently accept the identical page (keeps updatedPages in sync)
        continue;
      }
      if (isNew) {
        newCount++;
      } else {
        modCount++;
      }
      final pageIndex = remoteMeta.document.pages.indexWhere((e) => e.fileName == fileName);
      final pageEntry = pageIndex >= 0 ? remoteMeta.document.pages[pageIndex] : null;
      final chapterName = chapterNameForPage(pageEntry, remoteMeta.metadata);
      final localCounts = elementCounts(localPage);
      final remoteCounts = elementCounts(remotePage);
      details.add(PageChangeDetail(
        fileName: fileName,
        pageNumber: remotePage.pageNumber,
        pageIndex: pageIndex >= 0 ? pageIndex : 0,
        chapterName: chapterName,
        changeType: isNew ? PageChangeType.added : PageChangeType.modified,
        localStrokeCount: localCounts.$1, remoteStrokeCount: remoteCounts.$1,
        localImageCount: localCounts.$2, remoteImageCount: remoteCounts.$2,
        localShapeCount: localCounts.$3, remoteShapeCount: remoteCounts.$3,
        localTextCount: localCounts.$4, remoteTextCount: remoteCounts.$4,
      ));
    }

    return (details: details, newCount: newCount, modCount: modCount);
  }

  /// Stage 6c: the remote page list with local-only pages kept and orphans healed.
  ({DocumentStructure mergedDocument, List<PageEntry> orphanSynthEntries}) _healedDocument(_PullRun run) {
    final s = run.s;
    final deletedRemotelyByEtag = run.deletedRemotelyByEtag;
    final updatedPages = run.updatedPages;
    final remoteMeta = run.remoteMeta;
    // ── Preserve locally-added pages that the server hasn't seen yet ──
    // remoteMeta.document only lists pages the server knows about.
    // Any pages added locally but not yet fully uploaded are absent from
    // that list. If we let auto-accept replace state.document with the
    // remote-only version, those page entries disappear even though their
    // data is still alive in updatedPages — they become unreachable and
    // appear to vanish (chapter mixing / "page loss after PDF import").
    //
    // Fix: append local-only entries after the remote list so they survive
    // the merge. Remote's ordering and chapter assignments win for shared
    // pages; local-only entries keep their original chapterId.
    final remoteFileNames =
        remoteMeta.document.pages.map((p) => p.fileName).toSet();
    // Exclude pages we just auto-deleted (server removed them) from the
    // local-only preservation set. Without this filter, a page deleted
    // on another device would be removed from `updatedPages` but its
    // stale PageEntry would survive in `localOnlyEntries` → document
    // ends up with N entries while pages map has N-1. The canvas then
    // reports 'Nessuna pagina' for the ghost entry and every subsequent
    // pull loops forever at 'pages=N-1 < doc=N, state still mismatch'.
    final localOnlyEntries = s.document.pages
        .where((p) => !remoteFileNames.contains(p.fileName) &&
                       !deletedRemotelyByEtag.contains(p.fileName))
        .toList();

    // ── Self-heal corrupted server document.json ──
    //
    // Observed on a production Nextcloud: every notebook's server-side
    // `_delta/<id>/document.json` contained only **one** PageEntry, while
    // `_delta/<id>/pages/` held dozens or hundreds of actual page files.
    // An earlier buggy client had overwritten the remote document with a
    // stale 1-entry local state.  Because the pull-then-save cycle now
    // propagates that 1-entry document back to disk, the bug was
    // self-perpetuating — every sync re-cemented the broken state.
    //
    // Detect the mismatch and rebuild PageEntries from the actual page
    // data we just downloaded.  chapterId is reconstructed from
    // `metadata.chapters[].pageIds` — the canonical chapter membership
    // list — so orphan pages keep their original chapter instead of
    // landing in "no chapter" (the bug that nuked chapter info on every
    // notebook during the previous heal cycle).  Sort uses the filename
    // numeric suffix (page_001 .. page_NNN) which is stable; the
    // `pageNumber` field inside PageData JSON has been observed
    // duplicated/corrupt so it can't be trusted.
    final allLocalFileNames = {
      ...remoteFileNames,
      ...localOnlyEntries.map((e) => e.fileName),
    };
    final orphanPageIdToChapter = _chapterByPageId(remoteMeta.metadata);
    // A page another device just added is an orphan here until its page
    // list lands, and is in no chapter list yet: without a chapter it fell
    // out of every chapter view. New pages go after the last one.
    final remoteChapters = remoteMeta.metadata.chapters;
    final orphanFallbackChapter = remoteMeta.document.pages.isNotEmpty
        ? remoteMeta.document.pages.last.chapterId
        : (remoteChapters.length == 1 ? remoteChapters.first.id : null);
    final orphanSynthEntries = <PageEntry>[];
    int orphanChRecovered = 0;
    int orphanChUnmapped = 0;
    final localEntryByFile = {
      for (final e in s.document.pages) e.fileName: e,
    };
    for (final entry in updatedPages.entries) {
      if (allLocalFileNames.contains(entry.key)) continue;
      final pid = entry.value.pageId;
      // A page this device still lists (kept against a remote delete)
      // keeps its own entry, chapter included.
      final own = localEntryByFile[entry.key];
      if (own != null) {
        orphanSynthEntries.add(own);
        orphanChRecovered++;
        continue;
      }
      final ch = orphanPageIdToChapter[pid] ?? orphanFallbackChapter;
      if (ch != null) {
        orphanChRecovered++;
      } else {
        orphanChUnmapped++;
      }
      orphanSynthEntries.add(PageEntry(
        pageId: pid,
        pageNumber: entry.value.pageNumber,
        fileName: entry.key,
        lastModified: entry.value.modifiedAt,
        chapterId: ch,
      ));
    }
    if (orphanSynthEntries.isNotEmpty) {
      print('[Canvas] HEAL: remote document.json references '
          '${remoteMeta.document.pages.length} pages but pages/ folder '
          'has ${updatedPages.length} — synthesising '
          '${orphanSynthEntries.length} PageEntries '
          '(chapter recovered: $orphanChRecovered, '
          'unmapped: $orphanChUnmapped). '
          'The next save() will push the repaired document to the server.');
    }

    // Assemble merged document: remote entries first (canonical order from
    // the server — preserves any page-manager reorder), then local-only,
    // then orphaned-and-healed.  Do NOT sort the combined list by filename
    // numeric suffix: filenames are minted sequentially at page-creation
    // time, so sorting by filename destroys a user-defined reorder
    // (page-manager drag) every time a heal or local-only branch fires
    // here. Only sort the orphan-synth set internally so its members
    // appear deterministically across devices when the heal actually
    // recovers something.
    orphanSynthEntries.sort((a, b) =>
        _filenameNum(a.fileName).compareTo(_filenameNum(b.fileName)));
    // Pages only this device lists go back where they were locally,
    // after their local predecessor; appending them moved a page added
    // or kept offline to the end of the notebook.
    final combinedEntries = placeByLocalOrder(
      [...remoteMeta.document.pages],
      [
        ...localOnlyEntries,
        ...orphanSynthEntries
            .where((e) => localEntryByFile.containsKey(e.fileName)),
      ],
      s.document.pages,
    )..addAll(orphanSynthEntries
        .where((e) => !localEntryByFile.containsKey(e.fileName)));
    // Renumber to guarantee sequential, unique pageNumbers after the heal.
    for (var i = 0; i < combinedEntries.length; i++) {
      combinedEntries[i] = combinedEntries[i].copyWith(pageNumber: i + 1);
    }
    final mergedDocument = (localOnlyEntries.isEmpty &&
            orphanSynthEntries.isEmpty)
        ? remoteMeta.document
        : DocumentStructure(
            notebookId: remoteMeta.document.notebookId,
            formatVersion: remoteMeta.document.formatVersion,
            pages: combinedEntries,
          );

    return (mergedDocument: mergedDocument, orphanSynthEntries: orphanSynthEntries);
  }

  /// Stage 7: puts the pulled changes into the state, or raises the prompt.
  void _applyPulled(_PullRun run, List<PageConflict> deletionConflicts, List<PageConflict> conflicts, List<PageChangeDetail> details, int newCount, int modCount, Set<String> autoMergeable, DocumentStructure mergedDocument, List<PageEntry> orphanSynthEntries) {
    final s = run.s;
    final deletedRemotelyByEtag = run.deletedRemotelyByEtag;
    final updatedPages = run.updatedPages;
    final updatedAssets = run.updatedAssets;
    final corruptedPages = run.corruptedPages;
    final missingAssets = run.missingAssets;
    final remoteMeta = run.remoteMeta;
    // Count safe deletions (auto-removed, not conflicting)
    final safeDeleteCount = deletedRemotelyByEtag.length - deletionConflicts.length;

    // Show conflicts if any, plus non-conflicting changes banner.
    // Also trigger the pending/accept flow when the server document was
    // healed from orphan pages — even if no "user-visible" changes were
    // detected, the in-memory state still needs to pick up the repaired
    // document so the subsequent save() uploads it back to the server.
    final needsHeal = orphanSynthEntries.isNotEmpty;
    // ALSO trigger when at least one page was found corrupt on the server —
    // we need to push the local-good copy back up to overwrite the bad
    // bytes, otherwise the next pull will hit the same FormatException.
    final needsCorruptionHeal = corruptedPages.isNotEmpty;
    if (conflicts.isNotEmpty ||
        details.isNotEmpty ||
        safeDeleteCount > 0 ||
        needsHeal ||
        needsCorruptionHeal) {
      final pending = (details.isNotEmpty || safeDeleteCount > 0 || needsHeal || needsCorruptionHeal)
          ? PendingRemoteChanges(
              metadata: remoteMeta.metadata,
              document: mergedDocument,
              pages: updatedPages,
              assets: updatedAssets,
              changedPages: details,
              newPageCount: newCount,
              modifiedPageCount: modCount,
              deletedPageCount: safeDeleteCount,
              newAssetCount: missingAssets.length,
              autoMergeable: autoMergeable,
              // The server's ACTUAL page listing (PROPFIND of pages/), NOT
              // document.json — document.json is exactly what contains the
              // ghost entries we're trying to detect. A doc entry whose
              // fileName isn't in this set and has no local data is a ghost.
              remotePageFileNames: run.remotePageEtags.keys.toSet(),
              remoteDeletedFileNames: deletedRemotelyByEtag.toSet(),
            )
          : null;

      // Auto-accept all non-conflicting changes silently.
      // Only show UI when there are true per-page conflicts
      // (both local and remote edited the same page).
      if (conflicts.isEmpty && pending != null) {
        print('[Canvas] Auto-accepting ${pending.totalChanges} remote '
            'changes ($newCount new, $modCount modified'
            '${needsHeal ? ", ${orphanSynthEntries.length} healed orphans" : ""}'
            '${needsCorruptionHeal ? ", ${corruptedPages.length} corrupt-page reuploads" : ""})');
        _state = _state!.copyWith(
          pendingRemoteChanges: pending,
          clearPendingConflicts: true,
        );
        _acceptRemoteChanges();
        // Any healed orphan means the server's document.json/metadata.json
        // is inconsistent (page files exist in pages/ but aren't listed
        // in document). Mark dirty so the next save() pushes the repaired
        // document back to the server — regardless of whether we also
        // received other pending changes in this cycle. Without this, a
        // pull that both 'accepts' real new pages AND heals an orphan
        // left the server broken forever (details.isNotEmpty gated the
        // repair-upload out even though the repair is exactly what's
        // needed to break the cycle).
        if (needsHeal && _state != null) {
          _state = _state!.copyWith(isDirty: true);
        }
        // Corrupt-page heal: acceptRemoteChanges just rebuilt
        // _sync.lastSyncedPages from the merged map (which contains the
        // LOCAL bytes for these pages, since updatedPages was seeded
        // from s.pages and we never overwrote them). To make the next
        // save() actually re-upload, we must evict their entries so
        // _saveInner's `!_sync.lastSyncedPages.containsKey(key)` branch
        // detects them as fresh. Then mark dirty + schedule a save:
        // the local copies overwrite the truncated server bytes, and
        // a subsequent pull picks up the freshly-written ETag without
        // FormatException.
        if (needsCorruptionHeal && _state != null) {
          for (final fn in corruptedPages) {
            _sync.lastSyncedPages.remove(fn);
          }
          _state = _state!.copyWith(isDirty: true);
          print('[Canvas] HEAL: ${corruptedPages.length} pages corrupt on '
              'server (sample: ${corruptedPages.take(3).join(",")}'
              '${corruptedPages.length > 3 ? "..." : ""}) — will re-upload '
              'from local on the next save (auto-scheduled)');
          // Schedule save just after the current pull releases its sync
          // lock. 500ms gives the in-flight _savePulledChangesLocally
          // time to land; save() acquires the lock cooperatively so a
          // race here just queues behind the local persist instead of
          // being dropped.
          Timer(const Duration(milliseconds: 500), () {
            if (_core.isDisposed) return;
            if (_state == null || _state!.metadata.id != s.metadata.id) return;
            unawaited(_save());
          });
        }
      } else {
        _state = _state!.copyWith(
          pendingRemoteChanges: pending,
          pendingConflicts: conflicts.isNotEmpty ? conflicts : null,
          clearPendingRemoteChanges: pending == null,
          clearPendingConflicts: conflicts.isEmpty,
        );
        print('[Canvas] Pull result: ${conflicts.length} conflicts, '
            '$modCount safe merges, $newCount new pages');
      }
    }
  }

  /// Records a strike for each ghost [candidates] fileName this pull and
  /// returns those confirmed dead for [_ghostPruneThreshold] consecutive pulls
  /// (i.e. safe to prune from the document). Candidates absent this cycle have
  /// their strike count reset, so a page that reappears on the server before
  /// ripening is never pruned.
  Set<String> _updateGhostStrikes(Set<String> candidates) {
    _sync.ghostEntryStrikes.removeWhere((fn, _) => !candidates.contains(fn));
    final ripe = <String>{};
    for (final fn in candidates) {
      final n = (_sync.ghostEntryStrikes[fn] ?? 0) + 1;
      _sync.ghostEntryStrikes[fn] = n;
      if (n >= _ghostPruneThreshold) ripe.add(fn);
    }
    return ripe;
  }

  /// Builds the set of fileNames the merged document should KEEP, applying the
  /// ghost-prune policy. Starts from [withData] (pages that have page bytes)
  /// and walks every current [docPages] entry that lacks data, classifying it:
  ///   • a confirmed remote deletion ([remoteDeleted])  → drop (honour delete)
  ///   • still on the server ([serverFileNames])        → keep (will hydrate)
  ///   • otherwise a ghost → keep until it has accrued [_ghostPruneThreshold]
  ///     strikes, then drop so the state can finally converge.
  /// Ripe (pruned) ghosts are also evicted from the ETag cache so a later pull
  /// doesn't resurrect them.
  Set<String> survivingFileNames({
    required Iterable<String> withData,
    required List<PageEntry> docPages,
    required Set<String> serverFileNames,
    required Set<String> remoteDeleted,
  }) {
    final keep = <String>{...withData};
    final ghostCandidates = <String>{};
    for (final e in docPages) {
      final fn = e.fileName;
      if (keep.contains(fn)) continue;
      if (remoteDeleted.contains(fn)) continue; // honour confirmed deletion
      if (serverFileNames.contains(fn)) {
        keep.add(fn); // pending hydration — the page is on the server
      } else {
        ghostCandidates.add(fn);
      }
    }
    final ripe = _updateGhostStrikes(ghostCandidates);
    keep.addAll(ghostCandidates.where((fn) => !ripe.contains(fn)));
    if (ripe.isNotEmpty) {
      for (final fn in ripe) {
        _sync.lastPageEtags.remove(fn);
      }
      print('[Canvas] Pruning ${ripe.length} ghost document entr'
          '${ripe.length == 1 ? "y" : "ies"} (no data locally or on server '
          'for $_ghostPruneThreshold+ pulls): '
          '${ripe.take(3).join(", ")}${ripe.length > 3 ? "…" : ""}');
      unawaited(CrashLogger.append(
          '[Pull] pruned ${ripe.length} ghost entries → state can converge'));
    }
    return keep;
  }

  bool _knownAbsent(String ref) {
    final at = _sync.absentRemoteAssets[ref];
    if (at == null) return false;
    if (DateTime.now().difference(at) < _absentAssetRetry) return true;
    _sync.absentRemoteAssets.remove(ref);
    return false;
  }

  Duration pullIntervalForIdle() {
    if (_sync.consecutiveFailedPulls >= _failedPullsBackoff) {
      final shift = (_sync.consecutiveFailedPulls - _failedPullsBackoff).clamp(0, 10);
      final ms = AppConfig.deltaPullInterval.inMilliseconds * (2 << shift);
      return Duration(
          milliseconds: ms.clamp(0, _failedPullMaxInterval.inMilliseconds));
    }
    if (_sync.idlePullCount < idlePullThreshold) {
      return AppConfig.deltaPullInterval;
    }
    final maxIntervalMs = _sync.idlePullCount >= deepIdleThreshold
        ? (SyncThrift.thrifty
                ? _deepIdleThriftyInterval
                : _deepIdleMaxInterval)
            .inMilliseconds
        : _idlePullMaxInterval.inMilliseconds;
    // Exponential backoff: idle=3 → 4s, 4 → 8s, 5 → 16s, 6+ → 30s,
    // 30+ → 60s (5 min when thrifty).
    final shift = (_sync.idlePullCount - idlePullThreshold).clamp(0, 8);
    final ms = AppConfig.deltaPullInterval.inMilliseconds * (2 << shift);
    final capped = ms.clamp(
      AppConfig.deltaPullInterval.inMilliseconds,
      maxIntervalMs,
    );
    return Duration(milliseconds: capped);
  }

  /// Resolve chapter name for a page entry.
  static String? chapterNameForPage(PageEntry? pageEntry, NotebookMetadata meta) {
    if (pageEntry == null || pageEntry.chapterId == null) return null;
    final idx = meta.chapters.indexWhere((c) => c.id == pageEntry.chapterId);
    return idx >= 0 ? meta.chapters[idx].title : null;
  }

  /// Count elements by type in a page: (strokes, images, shapes, texts).
  static (int, int, int, int) elementCounts(PageData? page) {
    if (page == null) return (0, 0, 0, 0);
    var strokes = 0, images = 0, shapes = 0, texts = 0;
    for (final el in page.layers.content) {
      el.map(unknown: (_) => 0,
        stroke: (_) => strokes++,
        image: (_) => images++,
        shape: (_) => shapes++,
        text: (_) => texts++,
        math: (_) => 0,
      );
    }
    return (strokes, images, shapes, texts);
  }
}

/// What one pull of the delta folder carries from one stage to the next.
class _PullRun {
  _PullRun(this.s, this.syncService, this.remotePageEtags, this.pagesToPull,
      this.deletedRemotelyByEtag, this.preKnownCorrupt)
      : updatedPages = Map<String, PageData>.from(s.pages),
        updatedAssets = Map<String, Uint8List>.from(s.assetBytes);

  final CanvasState s;
  final SyncService syncService;

  /// The server's page listing; shrinks to what arrived.
  Map<String, String> remotePageEtags;
  final List<String> pagesToPull;
  final Set<String> deletedRemotelyByEtag;
  final List<String> preKnownCorrupt;
  final Map<String, PageData> updatedPages;
  final Map<String, Uint8List> updatedAssets;
  bool anyPageChanged = false;

  late final Future<({NotebookMetadata metadata, DocumentStructure document})>
      metaFuture;
  late final ({NotebookMetadata metadata, DocumentStructure document})
      remoteMeta;
  late final List<String> completed;
  late final List<String> failedPages;
  late final List<String> corruptedPages;
  late final List<String> cooledDown;
  late final Set<String> missingAssets;
}

/// Thrown inside a pull when the notifier went away under it.
class _PullAborted implements Exception {
  const _PullAborted();
}
