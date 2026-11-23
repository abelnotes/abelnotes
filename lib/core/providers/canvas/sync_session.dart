import 'dart:async';
import 'dart:typed_data';

import 'package:abelnotes/shared/models/ncnote_format.dart';

/// What the open notebook's sync knows about the server and about what is
/// still to be pushed or pulled: baselines, ETags, queues, retry and pull
/// counters, timers. Plain state; the notifier drives it.
class SyncSession {
  SyncSession({required bool Function() isDisposed}) : _isDisposed = isDisposed;

  final bool Function() _isDisposed;

  /// Mutex: serializes save() and _pullRemoteChanges() so they never
  /// race each other. Only one can modify state at a time.
  Completer<void>? lock;

  /// Generation token bumped on every acquire AND every force-release.
  /// `releaseSyncLock` takes the caller's token and only nulls
  /// `lock` if the token matches the current generation. Without
  /// this, a slow holder timed out by force-release would later call
  /// `_releaseSyncLock` and erase the NEW holder's lock, letting a third
  /// caller race the new one — exactly the cross-stomp three audits
  /// flagged.
  int lockGeneration = 0;

  /// Tracks the in-flight remote save (launched fire-and-forget by save())
  /// so [closeNotebook] can await it — otherwise we may null out state while
  /// syncDelta is still mid-upload, abandoning the upload (PUT on the page
  /// file happened, but metadata.json never lands → server has half a
  /// commit which the next pull will try to reconcile).
  Future<void>? pendingRemoteSave;

  /// Tracks the latest in-flight local save of pulled-from-remote changes.
  /// Needed so [closeNotebook] can await it — otherwise the user can exit
  /// fast enough after a pull that the merged state never hits disk, and
  /// the next open reads a stale .ncnote (the "sync adds pages, exit,
  /// re-enter, everything gone, re-sync" bug).
  Future<void>? pendingPulledLocalSave;

  /// Upload attempts in a row refused because the server moved.
  int serverMovedStreak = 0;

  /// Asset keys modified since last sync (e.g. "images/foo.png").
  final Set<String> dirtyAssetKeys = {};

  /// Asset keys that were successfully uploaded at least once during this
  /// session (or seeded from a remote pull). Used by `pruneOrphanAssets`
  /// to decide whether an orphan should generate a server-side DELETE:
  /// a local-only asset (created and orphaned without ever syncing) MUST
  /// NOT produce a DELETE — the server has nothing to delete and a 404
  /// loop or worse, a cross-device collision (another device created an
  /// asset with the same id), would result. Persisted? No — re-seeded
  /// each notebook open from the remote asset listing during the first
  /// successful pull (every key in pulled `state.assetBytes` is by
  /// definition server-confirmed at that moment).
  final Set<String> uploadedAssetKeys = <String>{};

  /// Snapshot of page map references from the last sync.
  /// Used for identity-based dirty detection: if `pages[fileName]` is a
  /// different object than `_lastSyncedPages[fileName]`, it was edited.
  Map<String, PageData> lastSyncedPages = {};

  /// Last-synced common ancestor for the document structure (page order +
  /// chapter assignments) and notebook metadata (title/chapters/paper/cover).
  /// These are the "base" side of a 3-way merge on pull: comparing the live
  /// local value against this baseline tells us whether the LOCAL device
  /// changed order/chapters/metadata since the last sync, so a remote change
  /// to a DIFFERENT field doesn't clobber the local edit (and vice-versa).
  /// Null until the first successful sync/open; merge falls back to
  /// remote-wins while null.
  DocumentStructure? lastSyncedDocument;

  NotebookMetadata? lastSyncedMetadata;

  /// Strike counter for "ghost" document entries — pages listed in
  /// document.json that have NO data locally AND are absent from the server's
  /// page listing, so they can never be hydrated. Left in place they pin the
  /// pull in a hot retry loop forever (the consistency gate `pages < doc` can
  /// never be satisfied → meta-ETag never advances → ~50% CPU on a large
  /// notebook). We prune such an entry only after `ghostPruneThreshold`
  /// consecutive confirmations so a single flaky/partial PROPFIND can't wrongly
  /// drop a page that is really on the server. Keyed by fileName.
  final Map<String, int> ghostEntryStrikes = {};

  /// In-flight watchdog for the "Pull done but state still inconsistent" loop.
  /// If we burn through more than `maxInconsistentPulls` consecutive
  /// inconsistent pulls inside `inconsistentWindow`, the slow-path's
  /// `_idlePullCount = 0` reset is suppressed so adaptive backoff can engage
  /// even while the document hasn't converged — defense-in-depth on top of
  /// the ghost-prune (which itself converges in ~3 pulls). Reset on real
  /// progress (state becomes consistent or a ghost ripens for pruning).
  int consecutiveInconsistentPulls = 0;

  DateTime? consecutiveInconsistentSince;

  /// PRE-SAVE GUARD #2 abort rate-limit. Each abort triggers a pull; on
  /// pathologically broken state that pull can't restore consistency,
  /// re-firing forever. After `maxPreSaveGuardAborts` aborts in
  /// `preSaveGuardWindow` we stop kicking pulls and let the next user
  /// action retry instead — eliminating any chance of a save→abort→pull
  /// CPU loop even if the upstream fixes regress.
  int preSaveGuardAborts = 0;

  DateTime? preSaveGuardSince;

  /// ETag of the remote metadata.json — used to detect remote changes.
  String? remoteMetaEtag;

  /// Per-page WebDAV ETags from the last pull — used to detect which pages changed.
  Map<String, String> lastPageEtags = {};

  /// Server version of document.json that `lastSyncedDocument` came from;
  /// the push writes the page list only over it. Null = unknown, write as is.
  String? remoteDocVersion;

  /// Version of the document a pull downloaded, adopted on accept.
  String? pendingDocVersion;

  /// Which notebook the ETag caches above belong to. Guards against cross-
  /// contamination when the user switches notebooks: notebook-A's ETag set
  /// must never be used to diff notebook-B's remote state, or the first
  /// pull on B either misses real changes or fakes false positives.
  String? etagNotebookId;

  /// Set to true by `pullFromDeltaDownload` when any page/asset download
  /// failed in the current pull cycle. `pullRemoteChanges` checks this flag
  /// before advancing `remoteMetaEtag` — advancing the meta ETag on a
  /// partial pull would lie to the next sync ("already in sync") and those
  /// missing pages would never be retried until the remote file changed
  /// again.
  bool pullHadFailures = false;

  /// Per-page consecutive failure count. Reset to 0 whenever a download
  /// succeeds. Used by the cooldown logic in `pullFromDeltaDownload` to
  /// stop hammering the server with the same dead-end pages every 2 s.
  final Map<String, int> pageFailureCount = {};

  /// Cooldown deadline per page. While `now() < deadline` the page is
  /// excluded from `pagesToPull` so we don't spin the same 8 broken
  /// downloads forever (~ every 5-10 s) burning battery and bandwidth.
  /// Cleared once the deadline passes (one more attempt is allowed).
  final Map<String, DateTime> pageFailureCooldownUntil = {};

  /// Server ETags that have already been confirmed corrupt (truncated
  /// JSON / invalid UTF-8). Once a download produced FormatException
  /// for a given (fileName, etag) tuple, every subsequent pull cycle
  /// would hit the SAME bad bytes — there's no point re-issuing the GET
  /// until either (a) save() finishes uploading the local-good copy and
  /// the server returns a fresh ETag, or (b) some other device pushes a
  /// different version. This map is the dedup: if the current remote
  /// ETag for a page matches what we know is corrupt, skip the download
  /// attempt and re-flag for heal directly. Entries are cleared after a
  /// successful save() (server now has a new ETag for those pages) or
  /// when the page disappears from the server listing.
  final Map<String, String> knownCorruptEtags = {};

  /// Timer for pulling remote changes from other devices.
  Timer? pullTimer;

  /// Server-side deletes that the last sync attempt failed to commit
  /// (e.g. Tailscale connection drop). Replayed on every subsequent save
  /// until the server returns 404 or the delete succeeds, so an orphan
  /// can never be "lost in transit" and stay on the server forever.
  final Set<String> pendingPageDeletes = <String>{};

  final Set<String> pendingAssetDeletes = <String>{};

  /// Captured metadata.json bytes when [SyncService.syncDelta] reported
  /// a half-commit ([MetadataCommitFailedException] — pages + document
  /// landed on the server but the metadata commit-marker upload failed).
  /// Replayed by `retryPendingMetaCommit` on a periodic timer until
  /// the upload succeeds. Without this, other devices would fast-path-
  /// skip on the unchanged meta-ETag and never see the new content.
  /// Persisted base64 in SharedPreferences so a process restart doesn't
  /// drop the obligation.
  Uint8List? pendingMetaCommitBytes;

  Timer? pendingMetaCommitTimer;

  int consecutiveSyncFailures = 0;

  /// The pull's last probe failed for a notebook known to be on the server.
  bool pullUnreachable = false;

  Timer? remoteRetryTimer;

  /// Backoff state for the metadata-commit retry. Exponential: 60s →
  /// 120s → 240s → 480s → cap 1800s (30 min). Reset on success.
  int metaRetryAttempts = 0;

  /// Pre-push checks that found the server moved, in a row. After
  /// `maxMovedChecks` the push goes ahead so a pull that never settles the
  /// difference cannot starve the upload.
  int movedChecks = 0;

  /// False once [flushPendingWork] or [dispose] stopped polling: a pull that
  /// finishes after that must not re-arm the timer.
  bool pullLoopOn = false;

  /// Number of consecutive pull cycles that ended in a "nothing changed"
  /// noop. Used to back off the polling interval (see
  /// `pullIntervalForIdle`). Reset to 0 in `pullRemoteChanges` whenever
  /// a real change is observed.
  int idlePullCount = 0;

  /// Counter for the ordered-commit safety-net: every Nth pull does the
  /// full pages/ PROPFIND even when meta-ETag is unchanged, to catch
  /// the rare case of pages added on another device that crashed before
  /// updating metadata.json. Cycle reset to 0 each time we run the
  /// full PROPFIND.
  int pagePropfindCounter = 0;

  /// Timestamp anchor for the safety-net so deep-idle (5 min ticks) can't
  /// stretch it to 8 * 5 min = 40 min. With this, after
  /// `propfindSafetyNetMaxAge` of wall-clock time without a full PROPFIND
  /// we force one regardless of tick count. Set when `pagePropfindCounter`
  /// is reset.
  DateTime lastFullPropfindAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Pulls in a row that ended with something not received (a page, or
  /// document/metadata that would not verify). Each one used to retry at the
  /// 4-second cadence forever; from `failedPullsBackoff` on the interval
  /// doubles up to `failedPullMaxInterval`, and from `failedPullsShown` the
  /// sync badge says so.
  int consecutiveFailedPulls = 0;

  /// Assets the server answered 404 for, and when. Not asked again for
  /// `absentAssetRetry`: an upload from another device may still be on
  /// its way, a reference to a deleted image never will be.
  final Map<String, DateTime> absentRemoteAssets = {};

  bool isPulling = false;

  /// Pages the next save writes whole, folding their stroke chunks so
  /// releases that read snapshots only see them (set on close).
  final Set<String> compactNext = {};

  /// The in-flight pull Future, if any. Tracked so that [closeNotebook]
  /// can await an in-progress pull before dropping state — otherwise
  /// exiting mid-download drops the pulled pages before they reach disk
  /// and the next open reads the stale local file.
  Future<void>? pendingPullFuture;

  /// Acquire exclusive sync lock. Returns when lock available, or null if
  /// the notifier was disposed while waiting.
  ///
  /// Has a [timeout] to break deadlocks: if something awaited inside the
  /// previous holder's critical section hangs (e.g. `compute()` stuck,
  /// WebDAV socket frozen), we'd otherwise block every future save and
  /// pull forever. On timeout we force-release the stale lock and grab
  /// it ourselves so the notifier recovers instead of wedging the UI.
  ///
  /// The timeout must exceed the longest LEGITIMATE critical section: an
  /// asset-heavy pull over a degraded link runs for minutes (the .ncnote
  /// download alone is allowed webdavLargeDownloadTimeoutSeconds = 600 s).
  /// The old 30 s default force-released the lock out from under such a
  /// healthy pull, letting a concurrent save() mutate lastSyncedPages /
  /// lastPageEtags in parallel and corrupt dirty-tracking. Every WebDAV
  /// call inside a holder carries its own <=600 s timeout and all holders
  /// release in `finally`, so a wedged lock self-clears before this
  /// last-resort force-release fires.
  /// Acquire returns a generation TOKEN that must be passed back to
  /// [releaseLock]. A token is only valid until either (a) the
  /// matching release call, or (b) a force-release that bumps the
  /// generation.
  Future<int?> acquireLock({
    Duration timeout = const Duration(minutes: 11),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (lock != null && !_isDisposed()) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        print(
          '[Canvas] _acquireSyncLock TIMEOUT after ${timeout.inSeconds}s '
          '— force-releasing stuck lock to avoid UI deadlock',
        );
        forceReleaseLock();
        break;
      }
      try {
        await lock!.future.timeout(remaining);
      } on TimeoutException {
        // Loop: next iteration re-checks the deadline and force-releases.
        continue;
      } catch (_) {
        break;
      }
    }
    if (_isDisposed()) return null;
    lock = Completer<void>();
    lockGeneration++;
    return lockGeneration;
  }

  /// [acquireLock] as a lease: whoever holds it releases it, and a save that
  /// hands the upload to the push hands the lease over with it.
  Future<SyncLockLease?> acquireLease() async {
    final token = await acquireLock();
    return token == null ? null : SyncLockLease._(this, token);
  }

  /// Release sync lock. Only releases when the caller's token matches
  /// the current generation — a stale token (the prior holder timed out
  /// and force-release bumped the gen) becomes a no-op so the new
  /// holder's lock isn't erased.
  void releaseLock(int token) {
    if (token != lockGeneration) return;
    final held = lock;
    lock = null;
    if (held != null && !held.isCompleted) held.complete();
  }

  /// Force-release lock and bump generation, invalidating any in-flight
  /// holder's release call. Used on close/dispose and on acquire timeout.
  void forceReleaseLock() {
    final held = lock;
    lock = null;
    lockGeneration++;
    if (held != null && !held.isCompleted) held.complete();
  }

  /// True while any of the pull, retry or commit-retry timers is armed.
  bool get hasTimers =>
      (pullTimer?.isActive ?? false) ||
      (remoteRetryTimer?.isActive ?? false) ||
      (pendingMetaCommitTimer?.isActive ?? false);
}

/// The sync lock as held by one save: release it exactly once, or pass it
/// on to the push that takes over the upload.
class SyncLockLease {
  SyncLockLease._(this._session, this._token);

  final SyncSession _session;
  final int _token;

  void release() => _session.releaseLock(_token);
}
