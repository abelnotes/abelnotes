import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/core/providers/cross_notebook_clipboard_provider.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/core/services/webdav_service.dart' show WebDavException;
import 'package:abelnotes/features/canvas/data/render_engine.dart' show CanvasRenderEngine;
import 'package:abelnotes/features/canvas/data/math_rasterizer.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/shared/utils/rich_paste.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:abelnotes/core/providers/canvas_state.dart';
// Re-export so all existing import canvas_provider.dart files keep getting
// CanvasState, CanvasTool, PaperType, etc. without any change.
export 'package:abelnotes/core/providers/canvas_state.dart';

// ═══════════════════════════════════════════════════════════════
//  CANVAS PROVIDER
// ═══════════════════════════════════════════════════════════════

/// Thrown by [CanvasNotifier.openNotebook] when the notebook was written by
/// a newer app version than this build supports. Carries the two versions so
/// the UI layer (notebook_opener) can render a localized message at the
/// point of display — the provider has no BuildContext.
class FormatTooNewException implements Exception {
  final int fileVersion;
  final int supportedVersion;
  const FormatTooNewException(this.fileVersion, this.supportedVersion);

  @override
  String toString() =>
      'FormatTooNewException: notebook format v$fileVersion > supported v$supportedVersion';
}

final canvasProvider =
    StateNotifierProvider<CanvasNotifier, CanvasState?>((ref) {
  return CanvasNotifier(ref);
});

/// Per-StrokeData bounding-box cache used by the eraser hit-test.
/// Computed lazily on the first hit, persists for the lifetime of the
/// underlying StrokeData reference (Expando = weak-keyed). Skipping
/// even one stroke's 80-point loop per pointer event is the difference
/// between a 200-element walk dominating the main thread and not.
final Expando<Rect> _strokeBboxCache = Expando<Rect>();

class CanvasNotifier extends StateNotifier<CanvasState?> {
  final Ref _ref;
  // Track whether we've pushed undo for the current eraser/drag gesture
  bool _eraserUndoPushed = false;
  // Same idea for a selection-width slider drag: one undo entry per
  // gesture, not one per onChanged tick.
  bool _selectionWidthUndoPushed = false;
  Size? _viewportSize;

  // ── Eraser throttling state ──
  // Erasing fired `state.copyWith(pages: Map.from(...))` per pointer
  // event (60-120 Hz), each one cloning the 215-PageData map and
  // invalidating the Picture cache (pageData reference changes). On a
  // dense ink page that turned every eraser drag into 60 full Picture
  // rebuilds per second.
  //
  // Now: _eraseAt computes the new page content into [_pendingErasePage]
  // and only commits to `state` at most every 33 ms, or immediately on
  // pointer-up via [_flushPendingErase]. Visual feedback at 30 Hz still
  // feels responsive while the heavy state cascade fires ~3× less.
  PageData? _pendingErasePage;
  String? _pendingEraseFileName;
  Timer? _eraseFlushTimer;
  DateTime _lastEraseFlushAt =
      DateTime.fromMillisecondsSinceEpoch(0);
  // 16 ms = 60 Hz commit cap — one flush per vsync. Below 60 Hz the
  // visual updates feel choppy regardless of the per-flush work
  // (user perceives 20 fps eraser feedback even on a 1-stroke page
  // because the canvas doesn't tick on every vsync). Each flush
  // remains cheap thanks to the stroke-path Expando cache and the
  // Picture cache walking only the current page's elements.
  static const Duration _eraseFlushInterval = Duration(milliseconds: 16);

  /// Last position where [_eraseAt] actually walked the content list.
  /// Pointer events whose movement since this position is below
  /// [_eraseRadiusFraction] × eraserRadius are skipped — at 120 Hz pen
  /// on iPad the pointer reports many sub-millimetre samples that
  /// cannot intersect any element a previous, denser sample didn't
  /// already cover. Walking 200 elements × 80 points per skipped
  /// sample dominated CPU on dense ink pages.
  Offset _lastEraseAtPos = const Offset(-1e9, -1e9);

  /// Wall-clock start of the current eraser gesture. Used by [_eraseAt]
  /// to grow the effective radius after the user has been holding the
  /// gesture for a while — same affordance as macOS Notes / Apple
  /// Pencil's "press harder to erase faster", without needing pressure
  /// data which finger/mouse don't have.
  DateTime? _eraseGestureStart;
  // 0.1 (was 0.3): the previous threshold was tuned for iPad 120 Hz
  // dense sub-mm samples but blocked legitimate slow erase drags on
  // graphics tablets (200-300 Hz) where each sample moves <1 page-unit.
  // The eraser felt like it "stutters" at slow speeds because erase work
  // only fired when the user accumulated ~30% of the eraser radius.
  // 0.1 still skips obvious noise; the real per-event compute cost is
  // bounded by the bbox-culled stroke walk and amortised by the 60 Hz
  // _eraseFlushTimer batching state mutations.
  static const double _eraseRadiusFraction = 0.1;

  /// Mutex: serializes save() and _pullRemoteChanges() so they never
  /// race each other. Only one can modify state at a time.
  Completer<void>? _syncLock;
  /// Generation token bumped on every acquire AND every force-release.
  /// [_releaseSyncLock] takes the caller's token and only nulls
  /// `_syncLock` if the token matches the current generation. Without
  /// this, a slow holder timed out by force-release would later call
  /// `_releaseSyncLock` and erase the NEW holder's lock, letting a third
  /// caller race the new one — exactly the cross-stomp three audits
  /// flagged.
  int _syncLockGeneration = 0;
  bool _disposed = false;

  /// Incremented every time [openNotebook] runs. A deferred [closeNotebook]
  /// compares its starting generation against this — if the user re-opens
  /// a notebook before the previous close's teardown lands, the newer open
  /// would otherwise see its freshly-set state immediately nulled out,
  /// producing a stuck "Nessun notebook aperto" canvas.
  int _openGeneration = 0;

   /// Tracks the in-flight remote save (launched fire-and-forget by save())
  /// so [closeNotebook] can await it — otherwise we may null out state while
  /// syncDelta is still mid-upload, abandoning the upload (PUT on the page
  /// file happened, but metadata.json never lands → server has half a
  /// commit which the next pull will try to reconcile).
  Future<void>? _pendingRemoteSave;

  /// Tracks the latest in-flight local save of pulled-from-remote changes.
  /// Needed so [closeNotebook] can await it — otherwise the user can exit
  /// fast enough after a pull that the merged state never hits disk, and
  /// the next open reads a stale .ncnote (the "sync adds pages, exit,
  /// re-enter, everything gone, re-sync" bug).
  Future<void>? _pendingPulledLocalSave;

  /// Tracks the in-flight local ZIP rebuild from save(). Runs in background
  /// so save() returns quickly; closeNotebook awaits this so the ZIP lands
  /// on disk before the notebook is torn down.
  Future<bool>? _pendingLocalSave;

  /// Acquire exclusive sync lock. Returns when lock available.
  /// Returns false if notifier was disposed while waiting.
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
  /// healthy pull, letting a concurrent save() mutate _lastSyncedPages /
  /// _lastPageEtags in parallel and corrupt dirty-tracking. Every WebDAV
  /// call inside a holder carries its own ≤600 s timeout and all holders
  /// release in `finally`, so a wedged lock self-clears before this
  /// last-resort force-release fires.
  /// Acquire returns a generation TOKEN that must be passed back to
  /// [_releaseSyncLock]. A token is only valid until either (a) the
  /// matching release call, or (b) a force-release that bumps the
  /// generation. Use the boolean-style helpers below for compatibility
  /// with existing callers — internally they thread the token.
  Future<int?> _acquireSyncLock({
    Duration timeout = const Duration(minutes: 11),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (_syncLock != null && !_disposed) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        print('[Canvas] _acquireSyncLock TIMEOUT after ${timeout.inSeconds}s '
            '— force-releasing stuck lock to avoid UI deadlock');
        _forceReleaseSyncLock();
        break;
      }
      try {
        await _syncLock!.future.timeout(remaining);
      } on TimeoutException {
        // Loop: next iteration re-checks the deadline and force-releases.
        continue;
      } catch (_) {
        break;
      }
    }
    if (_disposed) return null;
    _syncLock = Completer<void>();
    _syncLockGeneration++;
    return _syncLockGeneration;
  }

  /// Release sync lock. Only releases when the caller's token matches
  /// the current generation — a stale token (the prior holder timed out
  /// and force-release bumped the gen) becomes a no-op so the new
  /// holder's lock isn't erased.
  void _releaseSyncLock(int token) {
    if (token != _syncLockGeneration) return;
    final lock = _syncLock;
    _syncLock = null;
    if (lock != null && !lock.isCompleted) lock.complete();
  }

  /// Force-release lock and bump generation, invalidating any in-flight
  /// holder's release call. Used on close/dispose and on acquire timeout.
  void _forceReleaseSyncLock() {
    final lock = _syncLock;
    _syncLock = null;
    _syncLockGeneration++;
    if (lock != null && !lock.isCompleted) lock.complete();
  }

  /// Asset keys modified since last sync (e.g. "images/foo.png").
  final Set<String> _dirtyAssetKeys = {};

  /// Asset keys that were successfully uploaded at least once during this
  /// session (or seeded from a remote pull). Used by [_pruneOrphanAssets]
  /// to decide whether an orphan should generate a server-side DELETE:
  /// a local-only asset (created and orphaned without ever syncing) MUST
  /// NOT produce a DELETE — the server has nothing to delete and a 404
  /// loop or worse, a cross-device collision (another device created an
  /// asset with the same id), would result. Persisted? No — re-seeded
  /// each notebook open from the remote asset listing during the first
  /// successful pull (every key in pulled `state.assetBytes` is by
  /// definition server-confirmed at that moment).
  final Set<String> _uploadedAssetKeys = <String>{};

  /// Snapshot of page map references from the last sync.
  /// Used for identity-based dirty detection: if `pages[fileName]` is a
  /// different object than `_lastSyncedPages[fileName]`, it was edited.
  Map<String, PageData> _lastSyncedPages = {};

  /// Last-synced common ancestor for the document structure (page order +
  /// chapter assignments) and notebook metadata (title/chapters/paper/cover).
  /// These are the "base" side of a 3-way merge on pull: comparing the live
  /// local value against this baseline tells us whether the LOCAL device
  /// changed order/chapters/metadata since the last sync, so a remote change
  /// to a DIFFERENT field doesn't clobber the local edit (and vice-versa).
  /// Null until the first successful sync/open; merge falls back to
  /// remote-wins while null.
  DocumentStructure? _lastSyncedDocument;
  NotebookMetadata? _lastSyncedMetadata;

  /// Strike counter for "ghost" document entries — pages listed in
  /// document.json that have NO data locally AND are absent from the server's
  /// page listing, so they can never be hydrated. Left in place they pin the
  /// pull in a hot retry loop forever (the consistency gate `pages < doc` can
  /// never be satisfied → meta-ETag never advances → ~50% CPU on a large
  /// notebook). We prune such an entry only after [_ghostPruneThreshold]
  /// consecutive confirmations so a single flaky/partial PROPFIND can't wrongly
  /// drop a page that is really on the server. Keyed by fileName.
  final Map<String, int> _ghostEntryStrikes = {};
  static const int _ghostPruneThreshold = 3;

  /// Asset ids whose decode failed AND whose server copy was confirmed to be
  /// the same poisoned bytes (the 1024-aligned truncation incident). Persisted
  /// across sessions so a notebook with permanently-truncated server assets
  /// doesn't waste ~N GETs on every app launch re-attempting to heal them.
  /// Cleared when a successful decode for the same id arrives (e.g. the
  /// ZIP-aware recovery tool replaced the bytes), so genuine recoveries pick
  /// up automatically. Kept in sync with [_healAttempted] (pre-seeds it on
  /// open) so the proactive sweep AND the lazy decode path both skip.
  final Set<String> _knownIncurableAssets = <String>{};

  /// In-flight watchdog for the "Pull done but state still inconsistent" loop.
  /// If we burn through more than [_maxInconsistentPulls] consecutive
  /// inconsistent pulls inside [_inconsistentWindow], the slow-path's
  /// `_idlePullCount = 0` reset is suppressed so adaptive backoff can engage
  /// even while the document hasn't converged — defense-in-depth on top of
  /// the ghost-prune (which itself converges in ~3 pulls). Reset on real
  /// progress (state becomes consistent or a ghost ripens for pruning).
  int _consecutiveInconsistentPulls = 0;
  DateTime? _consecutiveInconsistentSince;
  static const int _maxInconsistentPulls = 6;
  static const Duration _inconsistentWindow = Duration(seconds: 60);

  /// PRE-SAVE GUARD #2 abort rate-limit. Each abort triggers a pull; on
  /// pathologically broken state that pull can't restore consistency,
  /// re-firing forever. After [_maxPreSaveGuardAborts] aborts in
  /// [_preSaveGuardWindow] we stop kicking pulls and let the next user
  /// action retry instead — eliminating any chance of a save→abort→pull
  /// CPU loop even if the upstream fixes regress.
  int _preSaveGuardAborts = 0;
  DateTime? _preSaveGuardSince;
  static const int _maxPreSaveGuardAborts = 3;
  static const Duration _preSaveGuardWindow = Duration(seconds: 10);

  /// Cache of encoded page JSON bytes per fileName. Reused when the current
  /// [PageData] instance is identical to the one that produced the cached
  /// bytes — i.e. the page wasn't mutated since the last save. For big
  /// notebooks where only one page changes per save, this avoids re-encoding
  /// every other page on every write.
  final Map<String, _CachedPageJson> _pageJsonCache = {};

  /// ETag of the remote metadata.json — used to detect remote changes.
  String? _remoteMetaEtag;

  /// Per-page WebDAV ETags from the last pull — used to detect which pages changed.
  Map<String, String> _lastPageEtags = {};

  /// Which notebook the ETag caches above belong to. Guards against cross-
  /// contamination when the user switches notebooks: notebook-A's ETag set
  /// must never be used to diff notebook-B's remote state, or the first
  /// pull on B either misses real changes or fakes false positives.
  String? _etagNotebookId;

  /// Set to true by [_pullFromDeltaDownload] when any page/asset download
  /// failed in the current pull cycle. [_pullRemoteChanges] checks this flag
  /// before advancing [_remoteMetaEtag] — advancing the meta ETag on a
  /// partial pull would lie to the next sync ("already in sync") and those
  /// missing pages would never be retried until the remote file changed
  /// again.
  bool _pullHadFailures = false;

  /// Per-page consecutive failure count. Reset to 0 whenever a download
  /// succeeds. Used by the cooldown logic in [_pullFromDeltaDownload] to
  /// stop hammering the server with the same dead-end pages every 2 s.
  final Map<String, int> _pageFailureCount = {};

  /// Cooldown deadline per page. While `now() < deadline` the page is
  /// excluded from `pagesToPull` so we don't spin the same 8 broken
  /// downloads forever (~ every 5-10 s) burning battery and bandwidth.
  /// Cleared once the deadline passes (one more attempt is allowed).
  final Map<String, DateTime> _pageFailureCooldownUntil = {};

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
  final Map<String, String> _knownCorruptEtags = {};


  /// True while a multi-step bulk operation (e.g. PDF import) is in
  /// progress. Pull cycles are suppressed so an intervening network
  /// round-trip cannot re-order document.pages mid-insert and corrupt
  /// chapter assignments or currentPageIndex.
  bool _bulkOperationInProgress = false;

  /// Pause automatic remote pulls. Call [endBulkOperation] when done.
  void beginBulkOperation() => _bulkOperationInProgress = true;

  /// Resume automatic remote pulls after a bulk operation.
  void endBulkOperation() => _bulkOperationInProgress = false;

  // ── Page filename helpers ────────────────────────────────────────────────

  /// Returns a safe, non-colliding fileName for a **new** page.
  ///
  /// Uses `max(existing numeric suffix) + 1` rather than
  /// `document.pages.length + 1`.  The two values diverge whenever pages
  /// are reordered, deleted, or merged from multiple sessions — which is
  /// exactly when the simple `length + 1` scheme re-uses an already-taken
  /// number and causes the "chapter mixing / duplicate page" bug.
  String _nextPageFileName(CanvasState s) {
    int maxNum = s.document.pages.length; // safe lower bound
    for (final p in s.document.pages) {
      final m = RegExp(r'page_(\d+)\.json').firstMatch(p.fileName);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > maxNum) maxNum = n;
      }
    }
    return 'page_${(maxNum + 1).toString().padLeft(3, '0')}.json';
  }

  /// Scans [doc].pages for duplicate fileNames and renames every second-or-
  /// later occurrence to a fresh, unique name.  The corresponding [PageData]
  /// is copied to the new key so content is preserved.
  ///
  /// Called at notebook-open and after every remote-pull merge so that
  /// collisions introduced by concurrent sessions are healed before the user
  /// ever navigates to the affected pages.
  static ({DocumentStructure document, Map<String, PageData> pages})
      _repairDuplicateFileNames(
          DocumentStructure doc, Map<String, PageData> pages) {
    // Compute the current max numeric suffix so we can mint fresh names.
    int maxNum = 0;
    for (final p in doc.pages) {
      final m = RegExp(r'page_(\d+)\.json').firstMatch(p.fileName);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > maxNum) maxNum = n;
      }
    }

    final seen = <String>{};
    final repairedEntries = <PageEntry>[];
    final repairedPages = Map<String, PageData>.from(pages);
    bool anyFixed = false;

    for (final entry in doc.pages) {
      if (seen.contains(entry.fileName)) {
        // Duplicate: assign a new non-colliding fileName.
        maxNum++;
        final newFileName =
            'page_${maxNum.toString().padLeft(3, '0')}.json';
        // Copy the PageData under the new key so the content is not lost.
        final originalData = repairedPages[entry.fileName];
        if (originalData != null) {
          repairedPages[newFileName] = originalData;
        }
        repairedEntries.add(entry.copyWith(fileName: newFileName));
        anyFixed = true;
        print('[Canvas] _repairDuplicateFileNames: '
            '${entry.fileName} → $newFileName (pageId ${entry.pageId})');
      } else {
        seen.add(entry.fileName);
        repairedEntries.add(entry);
      }
    }

    if (!anyFixed) return (document: doc, pages: pages);

    return (
      document: doc.copyWith(pages: repairedEntries),
      pages: repairedPages,
    );
  }

  static bool _listEqStr(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Records a strike for each ghost [candidates] fileName this pull and
  /// returns those confirmed dead for [_ghostPruneThreshold] consecutive pulls
  /// (i.e. safe to prune from the document). Candidates absent this cycle have
  /// their strike count reset, so a page that reappears on the server before
  /// ripening is never pruned.
  Set<String> _updateGhostStrikes(Set<String> candidates) {
    _ghostEntryStrikes.removeWhere((fn, _) => !candidates.contains(fn));
    final ripe = <String>{};
    for (final fn in candidates) {
      final n = (_ghostEntryStrikes[fn] ?? 0) + 1;
      _ghostEntryStrikes[fn] = n;
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
  Set<String> _survivingFileNames({
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
        _lastPageEtags.remove(fn);
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

  /// True if two documents differ in page ORDER, the SET of pages, or any
  /// per-page chapter assignment. Ignores pageNumber (a pure renumber is not
  /// a meaningful change). Used to decide whether a merge produced something
  /// the server doesn't have yet (→ needs an upload to converge).
  static bool _documentStructurallyDiffers(
      DocumentStructure a, DocumentStructure b) {
    if (a.pages.length != b.pages.length) return true;
    for (var i = 0; i < a.pages.length; i++) {
      if (a.pages[i].fileName != b.pages[i].fileName) return true;
      if (a.pages[i].chapterId != b.pages[i].chapterId) return true;
    }
    return false;
  }

  /// True if two metadata objects differ in any user-meaningful field
  /// (title/cover/paper/tags/author/description/chapter list). Ignores
  /// modifiedAt, pageCount, createdAt — those are derived/bookkeeping.
  static bool _metadataStructurallyDiffers(
      NotebookMetadata a, NotebookMetadata b) {
    if (a.title != b.title ||
        a.coverStyle != b.coverStyle ||
        a.coverColor != b.coverColor ||
        a.paperType != b.paperType ||
        a.paperColor != b.paperColor ||
        a.author != b.author ||
        a.description != b.description) {
      return true;
    }
    if (!_listEqStr(a.tags, b.tags)) return true;
    if (a.chapters.length != b.chapters.length) return true;
    for (var i = 0; i < a.chapters.length; i++) {
      if (a.chapters[i].id != b.chapters[i].id) return true;
      if (a.chapters[i].title != b.chapters[i].title) return true;
    }
    return false;
  }

  /// 3-way merge of notebook metadata + document structure on pull.
  ///
  /// `base` is the last-synced common ancestor (what we last knew the server
  /// had); `local` is the LIVE local state at apply time (may include edits
  /// the user made DURING the pull download window); `remote` is what the
  /// server has now. Returns the merged metadata + document.
  ///
  /// Core principle that eliminates the cross-device clobber class: a change
  /// made on ONE side to something the OTHER side left untouched is ALWAYS
  /// kept. Only when both sides changed the SAME thing do we tie-break —
  /// low-stakes structural fields (page order, per-page chapter, chapter
  /// order) resolve to LOCAL (the device the user is holding, so their most
  /// recent action sticks); scalar metadata tie-breaks by `modifiedAt`.
  ///
  /// `survivingFileNames` is the authoritative set of pages that have data in
  /// the merged page map; the returned document lists exactly those, once.
  ///
  /// When `baseDoc`/`baseMeta` are null (first sync, no ancestor) we fall
  /// back to remote-wins for ordering/scalars — matching legacy behaviour.
  static ({NotebookMetadata metadata, DocumentStructure document}) _merge3Way({
    required NotebookMetadata? baseMeta,
    required NotebookMetadata localMeta,
    required NotebookMetadata remoteMeta,
    required DocumentStructure? baseDoc,
    required DocumentStructure localDoc,
    required DocumentStructure remoteDoc,
    required Set<String> survivingFileNames,
  }) {
    final baseByFn = {
      for (final e in (baseDoc?.pages ?? const <PageEntry>[])) e.fileName: e
    };
    final localByFn = {for (final e in localDoc.pages) e.fileName: e};
    final remoteByFn = {for (final e in remoteDoc.pages) e.fileName: e};

    List<String> fnOrder(List<PageEntry> p) =>
        p.map((e) => e.fileName).toList();

    // Did `side` reorder the pages it shares with the baseline? Compares the
    // RELATIVE order of common pages, so pure adds/deletes don't read as a
    // reorder.
    bool reordered(List<PageEntry> side) {
      if (baseDoc == null) return false;
      final baseOrder = fnOrder(baseDoc.pages);
      final sideOrder = fnOrder(side);
      final sideSet = sideOrder.toSet();
      final baseSet = baseOrder.toSet();
      final a = baseOrder.where(sideSet.contains).toList();
      final b = sideOrder.where(baseSet.contains).toList();
      return !_listEqStr(a, b);
    }

    final localReordered = reordered(localDoc.pages);
    final remoteReordered = reordered(remoteDoc.pages);
    final List<String> spine;
    if (localReordered && !remoteReordered) {
      spine = fnOrder(localDoc.pages);
    } else if (remoteReordered && !localReordered) {
      spine = fnOrder(remoteDoc.pages);
    } else if (localReordered && remoteReordered) {
      spine = fnOrder(localDoc.pages); // both moved → device wins
    } else {
      spine = fnOrder(remoteDoc.pages); // neither → canonical/remote
    }

    // Final ordered fileName list: spine first, then any surviving fileName
    // not in the spine (remote order, then local order, then bare orphans).
    final seen = <String>{};
    final orderedFns = <String>[];
    void take(Iterable<String> fns) {
      for (final fn in fns) {
        if (survivingFileNames.contains(fn) && seen.add(fn)) orderedFns.add(fn);
      }
    }

    take(spine);
    take(fnOrder(remoteDoc.pages));
    take(fnOrder(localDoc.pages));
    take(survivingFileNames);

    // Per-page chapterId 3-way.
    String? mergeChapterId(String fn) {
      final b = baseByFn[fn]?.chapterId;
      final l = localByFn[fn]?.chapterId;
      final r = remoteByFn[fn]?.chapterId;
      if (baseDoc == null) return r ?? l;
      final lChanged = l != b;
      final rChanged = r != b;
      if (lChanged && !rChanged) return l;
      if (rChanged && !lChanged) return r;
      if (lChanged && rChanged) return l; // both → device wins
      return r ?? l;
    }

    final mergedEntries = <PageEntry>[];
    for (var i = 0; i < orderedFns.length; i++) {
      final fn = orderedFns[i];
      final src = remoteByFn[fn] ?? localByFn[fn];
      final chapterId = mergeChapterId(fn);
      if (src != null) {
        mergedEntries.add(
            src.copyWith(pageNumber: i + 1, fileName: fn, chapterId: chapterId));
      } else {
        // Pure orphan (page data exists but no entry on either side). Heal
        // reconciles pageId from the page bytes; fileName is a safe stand-in.
        mergedEntries.add(PageEntry(
          pageId: fn,
          pageNumber: i + 1,
          fileName: fn,
          chapterId: chapterId,
        ));
      }
    }

    final mergedDoc = DocumentStructure(
      notebookId: remoteDoc.notebookId,
      formatVersion: remoteDoc.formatVersion,
      pages: mergedEntries,
    );

    // ── Metadata scalar fields (per-field 3-way) ──
    final lMod = localMeta.modifiedAt;
    final rMod = remoteMeta.modifiedAt;
    T pick<T>(T? base, T local, T remote) {
      if (baseMeta == null) return remote;
      final lChanged = local != base;
      final rChanged = remote != base;
      if (lChanged && !rChanged) return local;
      if (rChanged && !lChanged) return remote;
      if (lChanged && rChanged) return rMod.isAfter(lMod) ? remote : local;
      return remote;
    }

    // ── Chapters merged by id (union of adds, honour deletes, title 3-way) ──
    final baseCh = {for (final c in (baseMeta?.chapters ?? const <Chapter>[])) c.id: c};
    final localCh = {for (final c in localMeta.chapters) c.id: c};
    final remoteCh = {for (final c in remoteMeta.chapters) c.id: c};

    final survivingChIds = <String>{};
    for (final id in {...localCh.keys, ...remoteCh.keys, ...baseCh.keys}) {
      final b = baseCh[id];
      final l = localCh[id];
      final r = remoteCh[id];
      if (b == null) {
        if (l != null || r != null) survivingChIds.add(id); // new on a side
      } else if (l != null && r != null) {
        survivingChIds.add(id);
      } else if (l != null && r == null) {
        if (l != b) survivingChIds.add(id); // remote deleted, local edited → keep
      } else if (l == null && r != null) {
        if (r != b) survivingChIds.add(id); // local deleted, remote edited → keep
      }
      // else: deleted on both (or unchanged-deleted) → drop
    }

    // Chapter order: same spine logic as pages.
    bool chReordered(List<Chapter> side) {
      if (baseMeta == null) return false;
      final baseOrder = baseMeta.chapters.map((c) => c.id).toList();
      final sideOrder = side.map((c) => c.id).toList();
      final ss = sideOrder.toSet();
      final bs = baseOrder.toSet();
      final a = baseOrder.where(ss.contains).toList();
      final b = sideOrder.where(bs.contains).toList();
      return !_listEqStr(a, b);
    }

    final List<String> chSpine;
    final lChRe = chReordered(localMeta.chapters);
    final rChRe = chReordered(remoteMeta.chapters);
    if (lChRe && !rChRe) {
      chSpine = localMeta.chapters.map((c) => c.id).toList();
    } else if (rChRe && !lChRe) {
      chSpine = remoteMeta.chapters.map((c) => c.id).toList();
    } else if (lChRe && rChRe) {
      chSpine = localMeta.chapters.map((c) => c.id).toList();
    } else {
      chSpine = remoteMeta.chapters.map((c) => c.id).toList();
    }

    Chapter mergeChapterObj(String id) {
      final b = baseCh[id];
      final l = localCh[id];
      final r = remoteCh[id];
      final fallback = (r ?? l ?? b)!;
      final title = pick<String>(b?.title, l?.title ?? fallback.title,
          r?.title ?? fallback.title);
      return Chapter(id: id, title: title, pageIds: const []);
    }

    final chSeen = <String>{};
    final mergedChapters = <Chapter>[];
    void takeCh(Iterable<String> ids) {
      for (final id in ids) {
        if (survivingChIds.contains(id) && chSeen.add(id)) {
          mergedChapters.add(mergeChapterObj(id));
        }
      }
    }

    takeCh(chSpine);
    takeCh(remoteMeta.chapters.map((c) => c.id));
    takeCh(localMeta.chapters.map((c) => c.id));

    // Recompute each chapter's pageIds from the merged document so the backup
    // membership list (used by the orphan-heal path) stays consistent with
    // the authoritative PageEntry.chapterId.
    final pageIdsByChapter = <String, List<String>>{};
    for (final e in mergedDoc.pages) {
      final cid = e.chapterId;
      if (cid != null) (pageIdsByChapter[cid] ??= []).add(e.pageId);
    }
    final finalChapters = mergedChapters
        .map((c) => c.copyWith(pageIds: pageIdsByChapter[c.id] ?? const []))
        .toList();

    final mergedMeta = remoteMeta.copyWith(
      title: pick(baseMeta?.title, localMeta.title, remoteMeta.title),
      coverStyle:
          pick(baseMeta?.coverStyle, localMeta.coverStyle, remoteMeta.coverStyle),
      coverColor:
          pick(baseMeta?.coverColor, localMeta.coverColor, remoteMeta.coverColor),
      paperType:
          pick(baseMeta?.paperType, localMeta.paperType, remoteMeta.paperType),
      paperColor:
          pick(baseMeta?.paperColor, localMeta.paperColor, remoteMeta.paperColor),
      tags: pick(baseMeta?.tags, localMeta.tags, remoteMeta.tags),
      author: pick(baseMeta?.author, localMeta.author, remoteMeta.author),
      description:
          pick(baseMeta?.description, localMeta.description, remoteMeta.description),
      chapters: finalChapters,
      pageCount: mergedDoc.pages.length,
      modifiedAt: rMod.isAfter(lMod) ? rMod : lMod,
    );

    return (metadata: mergedMeta, document: mergedDoc);
  }

  /// Attempts a 3-way element-level merge of ONE page so that two devices
  /// editing DIFFERENT parts of the same page converge automatically instead
  /// of being forced into a manual conflict. Elements (strokes/text/images/
  /// shapes) carry stable ids, so we diff by id against the [base] (last-
  /// synced) version:
  ///   • added on one side only            → keep it
  ///   • modified on one side only          → take that side
  ///   • deleted on one side, untouched other → honour the deletion
  ///   • identical on both                  → keep
  ///   • SAME element changed on BOTH sides differently, OR edited on one
  ///     side and deleted on the other      → real conflict ⇒ return null
  ///     (caller falls back to the page-level conflict UI; nothing is lost).
  /// The render engine paints by zIndex, so unioning the element lists is
  /// visually correct regardless of list order.
  static PageData? _mergePageElements({
    required PageData base,
    required PageData local,
    required PageData remote,
  }) {
    String idOf(ContentElement e) => e.map(
        stroke: (s) => s.id,
        text: (t) => t.id,
        image: (i) => i.id,
        shape: (s) => s.id,
        math: (m) => m.id);
    int zOf(ContentElement e) => e.map(
        stroke: (s) => s.zIndex,
        text: (t) => t.zIndex,
        image: (i) => i.zIndex,
        shape: (s) => s.zIndex,
        math: (m) => m.zIndex);

    final baseById = {for (final e in base.layers.content) idOf(e): e};
    final localById = {for (final e in local.layers.content) idOf(e): e};
    final remoteById = {for (final e in remote.layers.content) idOf(e): e};

    final merged = <ContentElement>[];
    for (final id in {...baseById.keys, ...localById.keys, ...remoteById.keys}) {
      final b = baseById[id];
      final l = localById[id];
      final r = remoteById[id];
      final inL = l != null, inR = r != null, inB = b != null;
      if (inL && inR) {
        if (l == r) {
          merged.add(l);
        } else if (inB && l == b) {
          merged.add(r); // only remote changed
        } else if (inB && r == b) {
          merged.add(l); // only local changed
        } else {
          return null; // both changed the same element → conflict
        }
      } else if (inL && !inR) {
        if (!inB) {
          merged.add(l); // local-added
        } else if (l == b) {
          // remote deleted it, local untouched → honour deletion (drop)
        } else {
          return null; // remote deleted, local edited → conflict
        }
      } else if (!inL && inR) {
        if (!inB) {
          merged.add(r); // remote-added
        } else if (r == b) {
          // local deleted it, remote untouched → honour deletion (drop)
        } else {
          return null; // local deleted, remote edited → conflict
        }
      }
      // else: absent on both live sides → dropped
    }

    // Background: same one-sided-change rule; both-changed-differently = conflict.
    final bb = base.layers.background;
    final lb = local.layers.background;
    final rb = remote.layers.background;
    final BackgroundLayer bg;
    if (lb == rb) {
      bg = lb;
    } else if (lb == bb) {
      bg = rb;
    } else if (rb == bb) {
      bg = lb;
    } else {
      return null; // both changed background differently → conflict
    }

    merged.sort((a, b) => zOf(a).compareTo(zOf(b)));
    final lMod = local.modifiedAt;
    final rMod = remote.modifiedAt;
    return remote.copyWith(
      layers: RenderingLayers(background: bg, content: merged),
      modifiedAt: (rMod != null && lMod != null && rMod.isAfter(lMod))
          ? rMod
          : (lMod ?? rMod),
    );
  }

  /// Timer for pulling remote changes from other devices.
  Timer? _pullTimer;

  /// True while a background pull from the server is fetching data for
  /// the currently-open notebook. The UI watches this to show a subtle
  /// "Sincronizzazione…" banner so the user knows why the notebook might
  /// be about to change.
  final ValueNotifier<bool> isPullingFromRemote = ValueNotifier<bool>(false);

  /// Live progress of the current pull: `(done, total)`. `total == 0` means
  /// "indeterminate" (no count yet).  Wired to the sync pill so the user
  /// sees actual progress during a long first-time hydration instead of a
  /// generic spinner that looks like the app has hung.
  final ValueNotifier<({int done, int total})> pullProgress =
      ValueNotifier<({int done, int total})>((done: 0, total: 0));

  /// Bumped whenever [CanvasState.imageCache] changes (decode lands,
  /// asset eviction, pull merge). The painter listens to this notifier
  /// for repaint instead of `ref.watch(canvasProvider.select(s.imageCache))`
  /// — bypassing the Riverpod cascade lets a 78-page PDF import avoid
  /// 78 full state.copyWith→consumer-walk rebuild cycles. The map ref
  /// itself still travels through state.copyWith for back-compat with
  /// the rest of the codebase; the painter just stops watching it
  /// through Riverpod.
  final ValueNotifier<int> imageCacheVersion = ValueNotifier<int>(0);

  // ── Typeset-math raster cache ──
  /// LaTeX equations rasterized to ui.Images, keyed by [mathCacheKey].
  /// Derived/ephemeral (NOT in CanvasState, never synced) — math elements
  /// persist only their LaTeX source + style; pixels are re-creatable. Lives
  /// on the notifier so it survives state.copyWith churn, mirroring how the
  /// image decode pipeline bumps a version notifier instead of riding the
  /// Riverpod cascade.
  final Map<String, MathRaster> mathCache = {};

  /// Bumped when [mathCache]/[failedMathKeys] changes so the painter
  /// repaints and the freshly-rasterized equation appears. Merged into the
  /// canvas repaint listenable next to [imageCacheVersion].
  final ValueNotifier<int> mathCacheVersion = ValueNotifier<int>(0);

  /// Cache keys whose rasterize permanently failed (no implicit view /
  /// pipeline error). Drawn as a source fallback, never retried, and
  /// treated as "ready" by the static picture cache.
  final Set<String> failedMathKeys = {};
  final Set<String> _mathInFlight = {};

  /// Soft cap on cached math rasters (each is a GPU texture). Oldest is
  /// disposed + evicted past this; far above any realistic page's count.
  static const int _mathCacheMax = 256;

  /// Request an async rasterize for a math element after a paint cache
  /// MISS (wired as CanvasRenderEngine.onMathCacheMiss). De-dupes against
  /// in-flight + cached + failed keys. On completion stores the raster (or
  /// records a permanent failure) and bumps [mathCacheVersion] so the
  /// canvas repaints with the equation. Mirrors the async image-decode path.
  void requestMathRaster(
    String latex,
    int colorArgb,
    double fontSize,
    bool displayMode,
    double pixelRatio,
  ) {
    final pr = pixelRatio.clamp(1.0, 4.0);
    final key = mathCacheKey(latex, colorArgb, fontSize, displayMode, pr);
    if (mathCache.containsKey(key) ||
        failedMathKeys.contains(key) ||
        !_mathInFlight.add(key)) {
      return;
    }
    () async {
      final r = await MathRasterizer.rasterize(
        latex: latex,
        color: Color(colorArgb),
        fontSize: fontSize,
        displayMode: displayMode,
        pixelRatio: pr,
      );
      _mathInFlight.remove(key);
      if (_disposed) {
        r?.image.dispose();
        return;
      }
      if (r == null) {
        failedMathKeys.add(key);
      } else if (mathCache.containsKey(key)) {
        // measureMath stored this key while we were rasterizing — keep the
        // existing raster; overwriting would leak the prior ui.Image's
        // GPU texture (nothing else holds a reference to dispose it).
        r.image.dispose();
      } else {
        if (mathCache.length >= _mathCacheMax) {
          final oldest = mathCache.keys.first;
          mathCache.remove(oldest)?.image.dispose();
        }
        mathCache[key] = r;
      }
      mathCacheVersion.value++;
    }();
  }

  /// Rasterize a math element to its INTRINSIC logical size (used at create
  /// time so the element box matches the typeset shape). Returns null on
  /// failure (caller falls back to an estimate). Also warms [mathCache].
  Future<Size?> measureMath(
    String latex, {
    required int colorArgb,
    required double fontSize,
    required bool displayMode,
    double pixelRatio = 3.0,
  }) async {
    final pr = pixelRatio.clamp(1.0, 4.0);
    final r = await MathRasterizer.rasterize(
      latex: latex,
      color: Color(colorArgb),
      fontSize: fontSize,
      displayMode: displayMode,
      pixelRatio: pr,
    );
    if (r == null) return null;
    if (_disposed) {
      r.image.dispose();
      return null;
    }
    final key = mathCacheKey(latex, colorArgb, fontSize, displayMode, pr);
    if (!mathCache.containsKey(key)) {
      // Same cap as requestMathRaster — without it long sessions with many
      // unique formulas grow GPU textures unbounded.
      if (mathCache.length >= _mathCacheMax) {
        final oldest = mathCache.keys.first;
        mathCache.remove(oldest)?.image.dispose();
      }
      mathCache[key] = r;
      mathCacheVersion.value++;
    } else {
      r.image.dispose();
    }
    return mathCache[key]!.size;
  }

  /// Last eraser sub-mode the user explicitly picked. Tapping the
  /// toolbar's eraser button restores THIS instead of always falling
  /// back to eraserStroke — fixes the bug where eraser-area → pen →
  /// eraser would reset back to eraser-stroke.
  CanvasTool _lastEraserMode = CanvasTool.eraserStroke;
  CanvasTool get lastEraserMode => _lastEraserMode;

  /// Per-tool memory of (strokeWidth, color, opacity, eraserSize).
  /// Restored when the user re-enters a tool, so changing tools no
  /// longer resets the pen width back to the global default. Highlighter
  /// has its own hardcoded defaults (12 px, 35% opacity, yellow) on
  /// FIRST entry only — subsequent visits restore whatever the user
  /// last set inside highlighter mode.
  final Map<CanvasTool, ToolSettings> _toolPrefs = {};
  ToolSettings? toolPrefFor(CanvasTool tool) => _toolPrefs[tool];

  CanvasNotifier(this._ref) : super(null) {
    // Restore per-tool preferences from SharedPreferences ASAP so the
    // very first tool the user touches already shows the previous
    // session's width/color/eraser size.
    unawaited(_loadToolPrefs());
  }

  void setViewportSize(Size size) {
    final wasNull = _viewportSize == null;
    _viewportSize = size;
    if (wasNull && state != null) {
      // Scratch: an infinite canvas has no fit-scaling, so centre the big
      // page's middle on the viewport. Ordinary pages: only re-centre when
      // zoom != 1.0 (the A4 fit already centres at zoom 1).
      final needsCenter = state!.isScratch || state!.zoom != 1.0;
      if (needsCenter) {
        // Defer state update to avoid modifying state during build phase
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (state != null) {
            state = state!.copyWith(
              panOffset: state!.isScratch
                  ? _scratchCenterPan(state!.zoom)
                  : _centeredPanOffset(state!.zoom),
            );
          }
        });
      }
    }
  }

  /// Compute the panOffset that horizontally centres the page at given zoom.
  Offset _centeredPanOffset(double zoom) {
    final vp = _viewportSize;
    if (vp == null) return Offset.zero;
    return Offset(vp.width * (1 - zoom) / 2, 0);
  }

  /// Pan that puts the centre of the big scratch page at the viewport centre.
  /// Scratch mode uses a fixed 1:1 render scale (no fit-to-page), so
  /// `screen = page * zoom + pan` — solving for the page centre gives this.
  Offset _scratchCenterPan(double zoom) {
    final vp = _viewportSize;
    if (vp == null) return Offset.zero;
    const s = AppConfig.scratchPageSize;
    return Offset(vp.width / 2 - s * zoom / 2, vp.height / 2 - s * zoom / 2);
  }

  Future<void> openNotebook({
    required NotebookMetadata metadata,
    required DocumentStructure document,
    required Map<String, PageData> pages,
    required String remotePath,
    Map<String, Uint8List>? assets,
    List<SymbolLibrary>? symbolLibraries,
  }) async {
    // Refuse notebooks written by a NEWER format than this build supports.
    // Freezed fromJson silently defaults unknown fields, so opening (and
    // then saving) a newer-format notebook would strip data the newer app
    // wrote — with WebDAV multi-device sync, mixed app versions are normal
    // operation, not an edge case. Better a clear error than silent loss.
    if (metadata.formatVersion > AppConfig.formatVersion) {
      throw FormatTooNewException(
          metadata.formatVersion, AppConfig.formatVersion);
    }
    // Bump the generation so any deferred teardown from a previous close
    // bails out instead of nulling the state we're about to populate.
    _openGeneration++;
    // Await so that state is set before the caller pushes CanvasScreen.
    // Without this, CanvasScreen briefly shows "Nessun notebook aperto"
    // (the null-state fallback) while SharedPreferences loads.
    await _restoreLastPosition(metadata, document, pages, remotePath, assets, symbolLibraries);
  }

  Future<void> _restoreLastPosition(
    NotebookMetadata metadata,
    DocumentStructure document,
    Map<String, PageData> pages,
    String remotePath,
    Map<String, Uint8List>? assets,
    List<SymbolLibrary>? symbolLibraries,
  ) async {
    String? restoredChapterId;
    int startPageIndex = 0;

    try {
      final prefs = await SharedPreferences.getInstance();
      final nbId = metadata.id;
      final savedChapter = prefs.getString('last_chapter_$nbId');
      final savedPage = prefs.getInt('last_page_$nbId') ?? 0;

      // Validate saved chapter still exists AND has at least one page that
      // matches its id in document.pages. If metadata.chapters[].pageIds is
      // stale (references a pageId no longer present in any page_*.json),
      // restoring activeChapterId to that chapter would leave the user
      // stuck on "— / 0" with all other pages hidden by the chapter filter.
      final hasPagesIn =
          (String cid) => document.pages.any((p) => p.chapterId == cid);
      if (savedChapter != null &&
          metadata.chapters.any((c) => c.id == savedChapter) &&
          hasPagesIn(savedChapter)) {
        restoredChapterId = savedChapter;
        // Validate saved page index is within range AND belongs to this chapter.
        // After a pull/merge the document may be reordered, so savedPage might
        // now point to a page in a different chapter → shows "—/N" in the nav.
        if (savedPage >= 0 &&
            savedPage < document.pages.length &&
            document.pages[savedPage].chapterId == savedChapter) {
          startPageIndex = savedPage;
        } else {
          // Page out of range or in wrong chapter: find first page of the chapter
          final idx = document.pages.indexWhere((p) => p.chapterId == savedChapter);
          if (idx >= 0) startPageIndex = idx;
        }
      } else {
        // No valid saved chapter — default to the first chapter that
        // actually has pages, or to null (all-pages view) if none qualifies.
        final firstWithPages = metadata.chapters
            .map((c) => c.id)
            .firstWhere(hasPagesIn, orElse: () => '');
        if (firstWithPages.isNotEmpty) {
          restoredChapterId = firstWithPages;
          final idx = document.pages
              .indexWhere((p) => p.chapterId == restoredChapterId);
          if (idx >= 0) startPageIndex = idx;
        }
      }
    } catch (_) {
      // SharedPreferences failed — fall back to first chapter with pages
      final firstWithPages = metadata.chapters
          .map((c) => c.id)
          .firstWhere((cid) => document.pages.any((p) => p.chapterId == cid),
              orElse: () => '');
      if (firstWithPages.isNotEmpty) {
        restoredChapterId = firstWithPages;
        final idx = document.pages
            .indexWhere((p) => p.chapterId == restoredChapterId);
        if (idx >= 0) startPageIndex = idx;
      }
    }

    // Scratch (infinite canvas) opens at 1:1 with the big page centred;
    // ordinary A4 notebooks open at the default 2.0 zoom, horizontally
    // centred.
    final isScratch = metadata.paperType == AppConfig.infinitePaperType;
    final initialZoom = isScratch ? 1.0 : 2.0;

    // Pick an initial panOffset that centers the page if the viewport
    // size is already known. Previously we relied on setViewportSize to
    // do this — but that only fires on FIRST layout; re-opening a
    // notebook with a known viewport left panOffset at (0,0) which
    // made the page render off-center (user saw it "shifted left").
    final initialPan = _viewportSize != null
        ? (isScratch
            ? _scratchCenterPan(initialZoom)
            : _centeredPanOffset(2.0)) // 2.0 = default zoom in CanvasState
        : Offset.zero;

    // ── Self-healing: repair duplicate fileNames before first render ──
    // Two sessions running simultaneously can independently generate the
    // same sequential fileName (e.g. page_068.json) for different pages.
    // Detect and rename any such duplicates so every PageEntry has a
    // unique key into the pages map.
    final repaired = CanvasNotifier._repairDuplicateFileNames(document, pages);

    state = CanvasState(
      metadata: metadata,
      document: repaired.document,
      pages: Map.of(repaired.pages),
      remotePath: remotePath,
      assetBytes: assets != null ? Map.of(assets) : const {},
      symbolLibraries: symbolLibraries ?? const [],
      activeChapterId: restoredChapterId,
      currentPageIndex: startPageIndex,
      zoom: initialZoom,
      panOffset: initialPan,
    );

    // Initialize delta sync tracking
    _disposed = false;
    _consecutiveSyncFailures = 0;
    hasSyncFailure.value = false;
    // Hold the same ref — _lastSyncedPages is a dirty-detection sidetable
    // (we only ever read identity via `identical(s.pages[k], _lastSyncedPages[k])`),
    // and `pages` itself is treated as immutable: every edit replaces it
    // with a fresh map. So Map.of(...) was a defensive copy with no benefit.
    _lastSyncedPages = repaired.pages;
    // Seed the 3-way-merge baselines from the just-loaded on-disk state.
    _lastSyncedDocument = repaired.document;
    _lastSyncedMetadata = metadata;
    _ghostEntryStrikes.clear();
    _consecutiveInconsistentPulls = 0;
    _consecutiveInconsistentSince = null;
    _preSaveGuardAborts = 0;
    _preSaveGuardSince = null;
    _knownIncurableAssets.clear();
    _healAttempted.clear();
    unawaited(_loadIncurableAssets(metadata.id));
    _assetsByLength.clear();
    _assetIndexBuilt = false;
    _pageJsonCache.clear();
    _dirtyAssetKeys.clear();
    // If the cached ETags belong to a different notebook, flush them so
    // notebook-A's diff never bleeds into notebook-B's first pull.
    if (_etagNotebookId != metadata.id) {
      _remoteMetaEtag = null;
      _lastPageEtags = {};
      _pageFailureCount.clear();
      _pageFailureCooldownUntil.clear();
      _knownCorruptEtags.clear();
      _etagNotebookId = metadata.id;
    }

    // ── Heal local document if it has fewer entries than pages map ──
    //
    // Triggered when a previous sync cycle cemented a corrupted
    // `state.document` with N fewer entries than `state.pages` has actual
    // page data (the "server document.json has 1 entry but pages/ has
    // 109" scenario where the pull-save-pull cycle self-perpetuates the
    // corruption).  Must run SYNCHRONOUSLY before the pull timer so the
    // open renders with the full page list, not just the corrupt subset.
    _healOrphanedPagesInState();

    // Pre-populate page ETags so the first pull doesn't see every page as
    // "changed" (empty cache vs all remote ETags → false positives).
    _initPageEtags(metadata.id);
    _loadPendingDeletes(metadata.id);
    _startPullTimer();

    // If there's a cross-notebook clipboard pending, apply it to this canvas
    // so the user can paste immediately after switching notebooks.
    final crossClip = _ref.read(crossNotebookClipboardProvider);
    if (crossClip != null) {
      state = state?.copyWith(
        clipboard: crossClip,
        pendingPaste: true,
      );
      // Consume — don't carry over to a third notebook accidentally
      _ref.read(crossNotebookClipboardProvider.notifier).state = null;
    }

    // Decode asset images into the render cache.
    //
    // IMPORTANT: do NOT launch all decodes concurrently.  On iPad, firing
    // ui.instantiateImageCodec() for every image in one microtask burst can
    // cause the process to be OOM-killed before a single frame is drawn.
    //
    // Strategy (all platforms — desktop included since the 400-page
    // memory fix): decode only assets referenced by a **window** around
    // the current page (current ± _assetWindow; wider on desktop). The
    // rest are decoded lazily when the user navigates near them (see
    // [_ensureAssetsForCurrentWindow]) and far-away textures are
    // LRU-evicted past the platform cache cap.
    if (assets != null && assets.isNotEmpty) {
      final initialRefs = _assetRefsForPage(startPageIndex, repaired.document, repaired.pages);
      // Phase 1: kick off decodes for the initial page. Missing-bytes
      // assets get routed through ensureAssetDecodedForThumbnail which
      // triggers a lazy fetch — so an incomplete .ncnote heals itself
      // on open without the user having to navigate away and back.
      for (final assetId in initialRefs) {
        final bytes = assets[assetId];
        if (bytes != null) {
          unawaited(_decodeAndCacheImage(assetId, bytes));
        } else {
          ensureAssetDecodedForThumbnail(assetId);
        }
      }
      // Phase 2: decode only the ±_assetWindow page window — on EVERY
      // platform. Desktop used to decode everything here, which on a
      // 400-page scan-heavy notebook meant minutes of background decode
      // churn and gigabytes of pinned textures. Distant pages now decode
      // on navigation via _ensureAssetsForCurrentWindow (same path
      // mobile has exercised since the iPad OOM fixes).
      final windowRefs = _assetRefsForWindow(
        startPageIndex, _assetWindow, repaired.document, repaired.pages,
      )..removeAll(initialRefs);
      final windowAssets = <String, Uint8List>{};
      for (final r in windowRefs) {
        final b = assets[r];
        if (b != null) windowAssets[r] = b;
      }
      unawaited(_decodeAssetsThrottled(windowAssets, skip: const {}));
    }
    _logMemoryStats('openNotebook');

    // Background self-heal: re-pull any locally-truncated assets from the
    // server (where the clean copy lives in the notebook itself). Deferred so
    // it doesn't compete with the initial open/pull, and a no-op for healthy
    // notebooks. Recovers corrupt assets on pages the user never opens, which
    // the view-driven lazy heal would otherwise miss.
    final healGen = _openGeneration;
    Future.delayed(const Duration(seconds: 4), () {
      if (_disposed || _openGeneration != healGen) return;
      _recoverTruncatedAssetsFromServer();
    });
  }

  /// Pages ahead/behind current to keep decoded in the imageCache on mobile.
  /// A 70-page notebook with full-page PDF backgrounds can easily consume
  /// 300 MB of texture memory if decoded in full. The window keeps a tight
  /// working set so iOS jetsam doesn't kill the process.
  static const int _mobileAssetWindow = 2;

  /// Max imageCache entries on mobile before LRU eviction kicks in. Each
  /// ui.Image holds native/GPU memory; unbounded growth is the #1 iPad OOM
  /// cause in this app.
  static const int _mobileImageCacheMax = 12;

  /// Desktop counterparts. Desktop used to decode EVERY asset at open
  /// with no eviction at all — a 400-page notebook of full-page scans
  /// pinned gigabytes of texture memory for the whole session. A wider
  /// window than mobile (more RAM, faster decode) keeps navigation
  /// seamless while bounding the working set.
  static const int _desktopAssetWindow = 6;
  static const int _desktopImageCacheMax = 48;

  static bool get _isMobilePlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
  static int get _assetWindow =>
      _isMobilePlatform ? _mobileAssetWindow : _desktopAssetWindow;
  static int get _imageCacheMax =>
      _isMobilePlatform ? _mobileImageCacheMax : _desktopImageCacheMax;

  /// Access-time map for LRU tracking. Key: assetId, value: monotonic
  /// counter bumped on every render access.
  final Map<String, int> _imageAccessTime = {};
  int _imageAccessCounter = 0;

  /// Compute the union of asset refs across pages in [center ± radius].
  Set<String> _assetRefsForWindow(
      int center, int radius, DocumentStructure doc, Map<String, PageData> pages) {
    final lo = (center - radius).clamp(0, doc.pages.length - 1);
    final hi = (center + radius).clamp(0, doc.pages.length - 1);
    final refs = <String>{};
    for (var i = lo; i <= hi; i++) {
      refs.addAll(_assetRefsForPage(i, doc, pages));
    }
    return refs;
  }

  /// Ensure assets needed by pages in the current window are decoded, and
  /// evict far-away ones (mobile only). Called after page navigation.
  ///
  /// Also triggers `ensureAssetDecodedForThumbnail` for any image element
  /// on the CURRENT page whose bytes are missing — that routes through
  /// the lazy-fetch path so the user doesn't have to navigate away and
  /// back to make a missing image appear after sync completes.
  void _ensureAssetsForCurrentWindow() {
    final s = state;
    if (s == null) return;
    // Lazy-fetch missing assets on the current page (all platforms).
    // ensureAssetDecodedForThumbnail is idempotent + race-free: if the
    // asset is already loading/cached/corrupt it returns immediately.
    final page = s.currentPage;
    if (page != null) {
      for (final el in page.layers.content) {
        if (el is ImageElement) {
          ensureAssetDecodedForThumbnail(el.data.assetPath);
        }
      }
    }
    // Windowed ensure + eviction on every platform (desktop included —
    // it now shares the bounded-cache policy instead of holding every
    // decoded texture for the whole session).
    final needed = _assetRefsForWindow(
        s.currentPageIndex, _assetWindow, s.document, s.pages);
    // Decode missing ones that we already have bytes for.
    for (final ref in needed) {
      if (s.imageCache.containsKey(ref)) continue;
      final bytes = s.assetBytes[ref];
      if (bytes != null) {
        unawaited(_decodeAndCacheImage(ref, bytes));
      }
    }
    _evictDistantImages();
  }

  /// LRU-evict from imageCache when it grows beyond the platform cap.
  /// Prefers to drop assets NOT referenced by pages in the current window.
  void _evictDistantImages() {
    final s = state;
    if (s == null) return;
    if (s.imageCache.length <= _imageCacheMax) return;
    final protect = _assetRefsForWindow(
        s.currentPageIndex, _assetWindow, s.document, s.pages);
    // Candidates: everything not in the window. Sort oldest first.
    final candidates = s.imageCache.keys
        .where((k) => !protect.contains(k))
        .toList()
      ..sort((a, b) =>
          (_imageAccessTime[a] ?? 0).compareTo(_imageAccessTime[b] ?? 0));
    final toEvict = s.imageCache.length - _imageCacheMax;
    if (toEvict <= 0 || candidates.isEmpty) return;
    final newCache = Map<String, ui.Image>.from(s.imageCache);
    var evicted = 0;
    for (final key in candidates) {
      if (evicted >= toEvict) break;
      final img = newCache.remove(key);
      img?.dispose();
      _imageAccessTime.remove(key);
      evicted++;
    }
    if (evicted > 0) {
      state = s.copyWith(imageCache: newCache);
      imageCacheVersion.value++;
      _logMemoryStats('evict($evicted)');
    }
  }

  /// Record an access to an asset for LRU. Called by render paths.
  void touchImageAsset(String assetId) {
    _imageAccessTime[assetId] = ++_imageAccessCounter;
  }

  /// Log a one-line memory snapshot on mobile so we can tell, from the
  /// crash log after a jetsam kill, roughly how big the caches had grown.
  void _logMemoryStats(String context) {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final s = state;
    if (s == null) return;
    // Approximate GPU texture bytes: 4 * w * h per cached ui.Image.
    var gpuBytes = 0;
    for (final img in s.imageCache.values) {
      gpuBytes += img.width * img.height * 4;
    }
    final rawAssetBytes = s.assetBytes.values
        .fold<int>(0, (sum, b) => sum + b.length);
    unawaited(CrashLogger.append(
      '[Mem] $context: imageCache=${s.imageCache.length} '
      '(~${(gpuBytes / (1024 * 1024)).toStringAsFixed(1)} MB GPU), '
      'assetBytes=${s.assetBytes.length} '
      '(~${(rawAssetBytes / (1024 * 1024)).toStringAsFixed(1)} MB raw), '
      'pages=${s.pages.length}',
    ));
  }

  /// Returns the set of asset keys referenced by a single page.
  Set<String> _assetRefsForPage(
      int pageIdx, DocumentStructure doc, Map<String, PageData> pages) {
    if (pageIdx < 0 || pageIdx >= doc.pages.length) return {};
    final entry = doc.pages[pageIdx];
    final page = pages[entry.fileName];
    if (page == null) return {};
    final refs = <String>{...page.assetReferences};
    for (final el in page.layers.content) {
      el.map(
        stroke: (_) {},
        text:   (_) {},
        shape:  (_) {},
        math:   (_) {},
        image:  (img) {
          if (img.data.assetPath.isNotEmpty) refs.add(img.data.assetPath);
        },
      );
    }
    return refs;
  }

  /// Returns the set of asset keys referenced by ANY page in the document.
  /// Used to detect orphan entries in `assetBytes`/`imageCache` left behind
  /// after the pages that referenced them were deleted (e.g. when the user
  /// re-imports a PDF after dropping the prior pages — the new pages get
  /// fresh asset IDs and the old bytes would otherwise sit in storage and
  /// keep showing up in corrupt-asset logs forever).
  Set<String> _allReferencedAssetIds(
      DocumentStructure doc, Map<String, PageData> pages) {
    final refs = <String>{};
    for (final entry in doc.pages) {
      final page = pages[entry.fileName];
      if (page == null) continue;
      refs.addAll(page.assetReferences);
      for (final el in page.layers.content) {
        if (el is ImageElement) {
          final p = el.data.assetPath;
          if (p.isNotEmpty) refs.add(p);
        }
      }
    }
    return refs;
  }

  /// Removes asset entries no longer referenced by any page from
  /// `state.assetBytes`, `state.imageCache`, and the local corrupt-id set.
  /// Stages orphan IDs into [_pendingAssetDeletes] so the next save —
  /// even if this one's remote upload throws — will retry the server-side
  /// delete. Symbol assets (assetPath prefixed with `symbol_`) are kept as
  /// they live in `imageCache` only and are never stored in `assetBytes`
  /// to begin with — the difference here naturally excludes them.
  void _pruneOrphanAssets() {
    final s = state;
    if (s == null) return;
    final referenced = _allReferencedAssetIds(s.document, s.pages);
    final orphans = <String>[];
    for (final key in s.assetBytes.keys) {
      if (!referenced.contains(key)) orphans.add(key);
    }
    // Also catch imageCache entries with no assetBytes backing AND no page
    // reference — these come from symbol elements that get deleted; we
    // don't return them as server deletes (no server-side asset file
    // exists for symbols), just dispose locally.
    final cacheOnlyOrphans = <String>[];
    for (final key in s.imageCache.keys) {
      if (!referenced.contains(key) && !s.assetBytes.containsKey(key)) {
        cacheOnlyOrphans.add(key);
      }
    }
    if (orphans.isEmpty && cacheOnlyOrphans.isEmpty) return;

    final newAssets = Map<String, Uint8List>.from(s.assetBytes);
    final newCache = Map<String, ui.Image>.from(s.imageCache);
    for (final id in orphans) {
      newAssets.remove(id);
      newCache.remove(id)?.dispose();
      _corruptAssetIds.remove(id);
      _dirtyAssetKeys.remove(id);
      _onDemandDecodeQueued.remove(id);
    }
    for (final id in cacheOnlyOrphans) {
      newCache.remove(id)?.dispose();
      _corruptAssetIds.remove(id);
    }
    state = s.copyWith(
      assetBytes: newAssets,
      imageCache: newCache,
    );
    imageCacheVersion.value++;
    // Stage server-side deletes for orphans we're CONFIDENT exist on the
    // server (we successfully uploaded them at least once in this session
    // or pulled them from remote). Local-only orphans (created but never
    // synced) skip the queue — issuing a DELETE for an asset the server
    // never had can race a concurrent upload from another device that
    // happens to use the same id, or just spin in a 404 retry.
    final serverConfirmed =
        orphans.where(_uploadedAssetKeys.contains).toList();
    _pendingAssetDeletes.addAll(serverConfirmed);
    // Drop the no-longer-tracked orphan ids from the uploaded set so it
    // doesn't grow unbounded over a long session.
    for (final id in orphans) {
      _uploadedAssetKeys.remove(id);
    }
    print('[Canvas] Pruned ${orphans.length} orphan assets '
        '(${serverConfirmed.length} queued for server delete, '
        '${cacheOnlyOrphans.length} cache-only) — freeing storage');
  }

  /// Sequentially decodes [assets] that are NOT in [skip], waiting for each
  /// to finish and yielding a ~16 ms frame gap between them so the UI stays
  /// responsive and memory pressure stays bounded.
  Future<void> _decodeAssetsThrottled(
      Map<String, Uint8List> assets, {required Set<String> skip}) async {
    for (final entry in assets.entries) {
      if (_disposed) return;
      if (skip.contains(entry.key)) continue;
      await _decodeAndCacheImage(entry.key, entry.value);
      // Yield one frame between images so we don't spike memory or block
      // the raster thread for longer than a single vsync interval.
      await Future.delayed(const Duration(milliseconds: 16));
    }
  }

  /// Wrap each asset's bytes in [TransferableTypedData] so the
  /// `compute()` boundary is a zero-second-copy hand-off. Without
  /// wrapping, SendPort memcpys the entire asset map into the worker
  /// isolate (~150 MB peak for a PDF-heavy notebook → 2× peak resident
  /// memory).
  ///
  /// Async + yields between assets: `TransferableTypedData.fromList`
  /// itself copies the bytes (the transfer happens later at SendPort
  /// time). With 78 PDF rasters (~3-5 MB each) that's 200-400 MB of
  /// sync memcpy on the UI isolate — long enough to freeze the pen
  /// stroke when an auto-save fires mid-drawing. Yielding to the
  /// event loop every 4 assets keeps frame budget intact.
  /// Set by the canvas screen: returns true while a pen stroke is
  /// mid-flight (the screen-local ActiveStrokeNotifier, which bypasses
  /// Riverpod, is the only component that knows). Save's heavy prep
  /// (page JSON encode, asset wrapping) polls this via
  /// [_waitForQuietPointer] so its main-thread chunks never land while
  /// the user has the pen on the page — that was the "scatto" that
  /// dropped pointer samples and kinked the stroke being written.
  bool Function()? strokeActiveProbe;

  /// Suspend until no pen stroke / eraser drag is in flight, polling at
  /// 50 ms. Hard cap so lifecycle-driven saves (close, background) can
  /// never deadlock behind a stuck probe.
  Future<void> _waitForQuietPointer() async {
    var waitedMs = 0;
    const capMs = 3000;
    while (waitedMs < capMs &&
        ((strokeActiveProbe?.call() ?? false) ||
            state?.eraserCursorPos != null)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      waitedMs += 50;
    }
  }

  Future<Map<String, TransferableTypedData>?> _wrapAssetsForIsolate(
      Map<String, Uint8List> assetBytes) async {
    if (assetBytes.isEmpty) return null;
    final wrapped = <String, TransferableTypedData>{};
    var bytesSinceYield = 0;
    for (final entry in assetBytes.entries) {
      // Never copy bytes while the pen is down — fromList on a multi-MB
      // scan blocks the UI isolate long enough to coalesce away pointer
      // samples at the start of the next stroke.
      await _waitForQuietPointer();
      wrapped[entry.key] = TransferableTypedData.fromList([entry.value]);
      bytesSinceYield += entry.value.length;
      // Yield to the event loop every ~1 MB copied (was: every 4 assets,
      // which with full-page scans meant 20+ MB between yields) so
      // pointer events dispatch promptly during the wrap.
      if (bytesSinceYield >= (1 << 20)) {
        bytesSinceYield = 0;
        await Future<void>.delayed(Duration.zero);
      }
    }
    return wrapped;
  }

  /// Apply a point transform to each vertex pair in [v] (length 6 = 3
  /// vertices). Returns the input unchanged when empty. Used to keep
  /// oblique-triangle vertices coherent under translate / scale / rotate
  /// / flip operations on a shape — without this, transforms updated the
  /// bbox + rotation field but the absolute-coord vertices stayed frozen
  /// and the triangle rendered at the OLD position/orientation.
  static List<double> _transformVertices(
      List<double> v, Offset Function(Offset) fn) {
    if (v.length != 6) return v;
    final out = List<double>.filled(6, 0);
    for (var i = 0; i < 6; i += 2) {
      final p = fn(Offset(v[i], v[i + 1]));
      out[i] = p.dx;
      out[i + 1] = p.dy;
    }
    return out;
  }

  /// Tracks which on-demand thumbnail decodes are already queued so the
  /// page manager doesn't fire the same decode N times when multiple
  /// thumbnails share the same asset (or a thumbnail re-builds before
  /// its decode lands).
  final Set<String> _onDemandDecodeQueued = <String>{};

  /// Decode every image asset referenced by the current page, fire-
  /// and-forget. Called by the canvas screen at the end of a bulk
  /// import (PDF) so the page the user lands on actually shows its
  /// imagery — during the bulk import itself decoding is skipped to
  /// keep GPU pressure bounded (every decoded `ui.Image` is ~3-5 MB
  /// of GPU memory, which pegged the host at ~40-page mark on long
  /// PDF imports).
  void ensureCurrentPageImagesDecoded() {
    if (state == null) return;
    final page = state!.currentPage;
    if (page == null) return;
    for (final el in page.layers.content) {
      if (el is ImageElement) {
        ensureAssetDecodedForThumbnail(el.data.assetPath);
      }
    }
  }

  /// Public hook for the page manager / library: ensure the asset
  /// behind a thumbnail is decoded, fire-and-forget. Cheap when the
  /// asset is already cached; otherwise queues a single decode that
  /// will land in `state.imageCache` on the next frame.
  ///
  /// On a 200-page notebook eagerly decoding every asset on open would
  /// cost seconds of CPU and ~hundred-MB peak memory; this lets the
  /// grid pull only the visible thumbnails' assets and progressively
  /// fill in the rest as the user scrolls.
  void ensureAssetDecodedForThumbnail(String assetId) {
    if (state == null) return;
    final s = state!;
    if (s.imageCache.containsKey(assetId)) return;
    if (_onDemandDecodeQueued.contains(assetId)) return;
    final bytes = s.assetBytes[assetId];
    if (bytes == null) {
      // The asset is referenced by a page but its bytes aren't in
      // memory. This commonly happens when the .ncnote ZIP cache was
      // built from an incomplete state (a delta pull whose asset GETs
      // were truncated by Tailscale and silently dropped) but the
      // server actually has the bytes. Try a one-shot fetch from the
      // delta folder before giving up — with the post-GET 1024-aligned
      // verification in webdav_service.dart the fetched bytes are
      // trustworthy. Only mark corrupt when the fetch genuinely fails
      // (404 / network gone).
      //
      // Three exit gates in order:
      //   1. Already in _loadingAssetIds: fetch is in flight — return
      //      so a re-paint during the fetch doesn't race and prematurely
      //      mark the asset corrupt (the original bug).
      //   2. Already in _corruptAssetIds OR _healAttempted: an earlier
      //      attempt landed (success → already decoded path; failure →
      //      stay corrupt). Don't retry every paint frame.
      //   3. Otherwise: kick off a new fetch.
      if (_loadingAssetIds.contains(assetId)) return;
      if (_corruptAssetIds.contains(assetId)) return;
      if (_healAttempted.contains(assetId)) return;
      _healAttempted.add(assetId);
      _loadingAssetIds.add(assetId);
      // Bump version so the UI repaints — the page render now sees
      // loadingAssetIds.contains(assetId) and shows a "loading"
      // placeholder instead of nothing.
      imageCacheVersion.value++;
      unawaited(_lazyFetchMissingAsset(assetId, s.metadata.id));
      return;
    }
    _onDemandDecodeQueued.add(assetId);
    () async {
      try {
        await _decodeAndCacheImage(assetId, bytes);
      } finally {
        _onDemandDecodeQueued.remove(assetId);
      }
    }();
  }

  /// SharedPreferences key for a notebook's last-observed delta metadata
  /// ETag.  Persisting this across app launches lets the first pull on
  /// re-open short-circuit when nothing changed server-side, eliminating
  /// the redundant "download all ETags + diff them" round-trip that made
  /// re-opening feel like a fresh sync ("chiudo riapro e la sync
  /// ricomincia").
  static String _deltaMetaEtagPrefsKey(String notebookId) =>
      'delta_meta_etag_$notebookId';

  /// Extract the numeric suffix from a `page_NNN.json` filename so we can
  /// sort pages by creation order — much more reliable than the
  /// `pageNumber` field stored inside each PageData JSON, which past bugs
  /// have been observed to leave duplicated or out-of-range.
  static int _filenameNum(String fn) {
    final m = RegExp(r'page_(\d+)\.json').firstMatch(fn);
    return m != null ? (int.tryParse(m.group(1)!) ?? 99999) : 99999;
  }

  /// Build a `pageId → chapterId` map from the canonical chapter list in
  /// metadata.  This is what lets the heal pass restore the user's
  /// chapter assignments instead of dropping every orphan into "no
  /// chapter" (the bug that caused the navigator to show "- / -" on
  /// 100+ pages after a botched repair).
  static Map<String, String> _chapterByPageId(NotebookMetadata meta) {
    final out = <String, String>{};
    for (final ch in meta.chapters) {
      for (final pid in ch.pageIds) {
        out[pid] = ch.id;
      }
    }
    return out;
  }

  /// Repair the current `state.document` when it references fewer pages
  /// than `state.pages` holds data for.  This is the in-memory mirror of
  /// the server-side heal in `_pullFromDeltaDownload`: it catches the case
  /// where a previous buggy session wrote a stale 1-entry document.json
  /// locally, so on open the user would see only that one entry in the
  /// navigator even though dozens of page files are sitting in the local
  /// ZIP, unreachable.
  ///
  /// Reconstructs the missing PageEntries:
  ///   • chapterId is recovered from `metadata.chapters[i].pageIds` so
  ///     orphan pages keep their chapter membership instead of being
  ///     dropped into "no chapter" — that bug is what corrupted every
  ///     notebook on the server during the previous heal cycle.
  ///   • Sort key is the numeric suffix of the filename (page_001 …
  ///     page_NNN), not the `pageNumber` field, which has been observed
  ///     duplicated/corrupt and produced random navigation order.
  ///   • Marks dirty so `save()` pushes the repaired document back to
  ///     the server, breaking the corruption cycle permanently.
  void _healOrphanedPagesInState() {
    final s = state;
    if (s == null) return;
    final docFileNames = s.document.pages.map((p) => p.fileName).toSet();
    final pageIdToChapter = _chapterByPageId(s.metadata);

    final orphans = <PageEntry>[];
    int recoveredChapter = 0;
    int unmappedChapter = 0;
    for (final entry in s.pages.entries) {
      if (docFileNames.contains(entry.key)) continue;
      final pid = entry.value.pageId;
      final ch = pageIdToChapter[pid];
      if (ch != null) {
        recoveredChapter++;
      } else {
        unmappedChapter++;
      }
      orphans.add(PageEntry(
        pageId: pid,
        pageNumber: entry.value.pageNumber,
        fileName: entry.key,
        lastModified: entry.value.modifiedAt,
        chapterId: ch,
      ));
    }
    if (orphans.isEmpty) return;

    print('[Canvas] HEAL (in-state): document has ${s.document.pages.length} '
        'entries, pages map has ${s.pages.length} — synthesising '
        '${orphans.length} PageEntries '
        '(chapter recovered: $recoveredChapter, unmapped: $unmappedChapter). '
        'Notebook marked dirty so save() pushes the repaired document.');

    // Append orphans AFTER the existing document order: the user's
    // page-manager reorder lives in `s.document.pages` and must survive
    // the heal. Sorting the whole combined list by filename was wiping a
    // local reorder every time the heal fired on open or pre-save. Sort
    // only orphans among themselves so their relative order is
    // deterministic across devices when a heal actually recovers files.
    orphans.sort((a, b) =>
        _filenameNum(a.fileName).compareTo(_filenameNum(b.fileName)));
    final combined = [...s.document.pages, ...orphans];
    for (var i = 0; i < combined.length; i++) {
      combined[i] = combined[i].copyWith(pageNumber: i + 1);
    }
    final repairedDoc = DocumentStructure(
      notebookId: s.document.notebookId,
      formatVersion: s.document.formatVersion,
      pages: combined,
    );
    state = s.copyWith(
      document: repairedDoc,
      metadata: s.metadata.copyWith(pageCount: combined.length),
      isDirty: true,
    );
  }

  /// SharedPreferences key for the per-page ETag map of a notebook.
  static String _pageEtagsPrefsKey(String notebookId) =>
      'page_etags_$notebookId';

  /// Restore [_lastPageEtags] from disk. This MUST reflect the ETags of the
  /// page content we actually have locally — i.e. only ETags that were
  /// successfully downloaded or uploaded. Never pre-populate from live
  /// server state on open: the server may have moved while we were closed,
  /// and pre-filling with current server ETags would silently make the
  /// first pull think 'nothing changed' even though our local .ncnote is
  /// stale (the 'iPad wrote page_164 while PC was offline → PC opens but
  /// pull is no-op → local stays stale forever' bug).
  ///
  /// Also primes [_remoteMetaEtag] from SharedPreferences.
  Future<void> _initPageEtags(String notebookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load last-saved meta ETag so first-pull can skip cheaply when
      // server state hasn't moved. Only use it if we don't already have
      // one in memory (e.g. same notebook re-opened without notebook-switch).
      if (_remoteMetaEtag == null) {
        final persisted = prefs.getString(_deltaMetaEtagPrefsKey(notebookId));
        if (persisted != null && persisted.isNotEmpty) {
          _remoteMetaEtag = persisted;
        }
      }

      // Load the persisted per-page ETag cache written by previous save/
      // pull cycles. Empty map on fresh install: the first pull will then
      // treat every page as potentially changed and download it.
      final persistedPageEtags = prefs.getString(_pageEtagsPrefsKey(notebookId));
      if (persistedPageEtags != null && persistedPageEtags.isNotEmpty) {
        try {
          final decoded = jsonDecode(persistedPageEtags) as Map<String, dynamic>;
          _lastPageEtags = decoded.map((k, v) => MapEntry(k, v as String));
          debugPrint('[Canvas] Loaded ${_lastPageEtags.length} page ETags from disk');
        } catch (_) {
          _lastPageEtags = {};
        }
      } else {
        _lastPageEtags = {};
      }

      // NOTE: we intentionally do NOT seed _lastPageEtags from the server's
      // current state when prefs is empty. Seeding from live server state
      // is UNSAFE: if another device (iPad) has uploaded new page content
      // but the ordered commit didn't finish (metadata.json still stale),
      // the server's page ETags are newer than what our local .ncnote
      // reflects — caching them as-is lies to the pull diff ('cached ==
      // server, nothing to download') and the iPad edits stay invisible
      // forever. Silent data loss.
      //
      // Acceptable cost: first post-upgrade open re-downloads every page
      // once. After that, the persisted cache kicks in and cross-device
      // sync works with 2 s latency. Correctness > bandwidth.

      debugPrint('[Canvas] Initialized ${_lastPageEtags.length} page ETags '
          '(persisted meta etag: ${_remoteMetaEtag != null})');
    } catch (e) {
      debugPrint('[Canvas] Could not init page ETags: $e');
    }
  }

  /// Server-side deletes that the last sync attempt failed to commit
  /// (e.g. Tailscale connection drop). Replayed on every subsequent save
  /// until the server returns 404 or the delete succeeds, so an orphan
  /// can never be "lost in transit" and stay on the server forever.
  final Set<String> _pendingPageDeletes = <String>{};
  final Set<String> _pendingAssetDeletes = <String>{};

  /// Captured metadata.json bytes when [SyncService.syncDelta] reported
  /// a half-commit ([MetadataCommitFailedException] — pages + document
  /// landed on the server but the metadata commit-marker upload failed).
  /// Replayed by [_retryPendingMetaCommit] on a periodic timer until
  /// the upload succeeds. Without this, other devices would fast-path-
  /// skip on the unchanged meta-ETag and never see the new content.
  /// Persisted base64 in SharedPreferences so a process restart doesn't
  /// drop the obligation.
  Uint8List? _pendingMetaCommitBytes;
  Timer? _pendingMetaCommitTimer;

  /// True when the most recent remote sync attempt(s) have failed
  /// OR there's a pending metadata-commit retry. Surfaced to the UI
  /// so the top-bar pill can show OFFLINE instead of the misleading
  /// "isDirty ? pending : ok" binary that hid 20-minute Tailscale
  /// flaps under a green cloud icon. The UI combines this with
  /// state.isDirty and state.pendingConflicts to pick the final
  /// HwSyncState (conflict > offline > pending > ok).
  final ValueNotifier<bool> hasSyncFailure = ValueNotifier<bool>(false);
  int _consecutiveSyncFailures = 0;

  static String _pendingPageDeletesPrefsKey(String notebookId) =>
      'pending_page_deletes_$notebookId';
  static String _pendingAssetDeletesPrefsKey(String notebookId) =>
      'pending_asset_deletes_$notebookId';
  static String _pendingMetaCommitPrefsKey(String notebookId) =>
      'pending_meta_commit_$notebookId';

  Future<void> _loadPendingDeletes(String notebookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = prefs.getStringList(_pendingPageDeletesPrefsKey(notebookId));
      final a = prefs.getStringList(_pendingAssetDeletesPrefsKey(notebookId));
      _pendingPageDeletes
        ..clear()
        ..addAll(p ?? const []);
      _pendingAssetDeletes
        ..clear()
        ..addAll(a ?? const []);
      if (_pendingPageDeletes.isNotEmpty || _pendingAssetDeletes.isNotEmpty) {
        debugPrint('[Canvas] Loaded pending deletes: '
            '${_pendingPageDeletes.length} pages, '
            '${_pendingAssetDeletes.length} assets');
      }
      // Pending metadata commit: a previous run may have left the server
      // half-committed (pages + document landed but metadata.json
      // upload failed). Pick up where we left off — retry every minute
      // until it lands. Other devices' meta-ETag won't advance until
      // this commits, so cross-device sync is stuck without it.
      final metaB64 = prefs.getString(_pendingMetaCommitPrefsKey(notebookId));
      if (metaB64 != null && metaB64.isNotEmpty) {
        try {
          _pendingMetaCommitBytes = base64Decode(metaB64);
          debugPrint('[Canvas] Loaded pending metadata commit: '
              '${_pendingMetaCommitBytes!.length} bytes');
          _scheduleMetaCommitRetry();
        } catch (_) {
          await prefs.remove(_pendingMetaCommitPrefsKey(notebookId));
        }
      }
    } catch (_) {}
  }

  Future<void> _persistPendingDeletes(String notebookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _pendingPageDeletesPrefsKey(notebookId),
          _pendingPageDeletes.toList());
      await prefs.setStringList(
          _pendingAssetDeletesPrefsKey(notebookId),
          _pendingAssetDeletes.toList());
    } catch (_) {}
  }

  Future<void> _persistPendingMetaCommit(
      String notebookId, Uint8List? bytes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (bytes == null) {
        await prefs.remove(_pendingMetaCommitPrefsKey(notebookId));
      } else {
        await prefs.setString(
            _pendingMetaCommitPrefsKey(notebookId), base64Encode(bytes));
      }
    } catch (_) {}
  }

  void _recomputeSyncStatus() {
    final next = _consecutiveSyncFailures > 0 ||
        _pendingMetaCommitBytes != null;
    if (hasSyncFailure.value != next) hasSyncFailure.value = next;
  }

  /// Backoff state for the metadata-commit retry. Exponential: 60s →
  /// 120s → 240s → 480s → cap 1800s (30 min). Reset on success.
  int _metaRetryAttempts = 0;
  static const _metaRetryBaseMs = 60 * 1000;
  static const _metaRetryMaxMs = 30 * 60 * 1000;

  /// Schedule the next retry of the pending metadata.json commit with
  /// exponential backoff. Idempotent: a scheduled timer is left in
  /// place. Cancelled on success or notebook close. Skips firing the
  /// immediate microtask retry that previously hammered the network
  /// the moment a failure landed (it's the worst time to retry — the
  /// link is presumably still bad).
  void _scheduleMetaCommitRetry() {
    if (_pendingMetaCommitTimer != null) return;
    final delayMs = (_metaRetryBaseMs * (1 << _metaRetryAttempts.clamp(0, 8)))
        .clamp(_metaRetryBaseMs, _metaRetryMaxMs);
    _pendingMetaCommitTimer = Timer(
      Duration(milliseconds: delayMs),
      () {
        _pendingMetaCommitTimer = null;
        _retryPendingMetaCommit();
      },
    );
  }

  Future<void> _retryPendingMetaCommit() async {
    final bytes = _pendingMetaCommitBytes;
    if (bytes == null) {
      _pendingMetaCommitTimer?.cancel();
      _pendingMetaCommitTimer = null;
      _metaRetryAttempts = 0;
      return;
    }
    if (state == null || _disposed) return;
    final notebookId = state!.metadata.id;
    final syncService = _ref.read(syncServiceProvider);
    if (syncService == null) {
      _metaRetryAttempts++;
      _scheduleMetaCommitRetry();
      return;
    }
    try {
      final etag = await syncService.replayMetadataCommit(
        notebookId: notebookId,
        metadataBytes: bytes,
      );
      // Success — clear the pending state and the backoff.
      _pendingMetaCommitBytes = null;
      _pendingMetaCommitTimer?.cancel();
      _pendingMetaCommitTimer = null;
      _metaRetryAttempts = 0;
      await _persistPendingMetaCommit(notebookId, null);
      if (etag != null && etag.isNotEmpty) {
        _remoteMetaEtag = etag;
        await _persistRemoteMetaEtag(notebookId);
      }
      _recomputeSyncStatus();
      print('[Canvas] Pending metadata commit replayed successfully '
          '(etag=$etag) — server is consistent again');
    } catch (e) {
      // Bump attempt count, schedule next with exponential delay.
      _metaRetryAttempts++;
      debugPrint('[Canvas] Pending metadata commit retry #$_metaRetryAttempts '
          'failed: $e — next try in '
          '${(_metaRetryBaseMs * (1 << _metaRetryAttempts.clamp(0, 8))).clamp(_metaRetryBaseMs, _metaRetryMaxMs) ~/ 1000}s');
      _scheduleMetaCommitRetry();
    }
  }

  /// Persist [_lastPageEtags] to disk. Called after every pull/save cycle
  /// that updates the map so a cold restart resumes with the ETag state
  /// that matches our local .ncnote content.
  Future<void> _persistLastPageEtags(String notebookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _pageEtagsPrefsKey(notebookId), jsonEncode(_lastPageEtags));
    } catch (_) {}
  }

  /// Persist the current [_remoteMetaEtag] so next app launch can skip the
  /// redundant first pull when nothing changed on the server.
  ///
  /// Also mirrors the ETag into the SQLite notebooks row. Without that, the
  /// library's background sync (which reads the etag from the DB) sees a
  /// stale value for any notebook that was pulled WITHOUT a save() cycle —
  /// and then re-downloads every page of every notebook on the next BgSync
  /// tick, burning Tailscale bandwidth and delaying the real sync of the
  /// notebook the user currently has open ("0 new, 109 refresh" x every
  /// notebook in the library).
  Future<void> _persistRemoteMetaEtag(String notebookId) async {
    final etag = _remoteMetaEtag;
    if (etag == null || etag.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deltaMetaEtagPrefsKey(notebookId), etag);
    } catch (_) {}
    // Mirror into the DB so BgSync's ETag comparison sees the current value.
    try {
      final fileService = _ref.read(fileServiceProvider);
      await fileService.markNotebookSynced(notebookId, etag);
    } catch (e) {
      debugPrint('[Canvas] Could not mirror meta ETag to DB: $e');
    }
  }

  static String _incurableAssetsPrefsKey(String nbId) =>
      'incurable_assets_$nbId';

  Future<void> _loadIncurableAssets(String notebookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_incurableAssetsPrefsKey(notebookId));
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<String>();
      _knownIncurableAssets
        ..clear()
        ..addAll(list);
      // Pre-seed _healAttempted so the lazy decode path AND the proactive
      // sweep both skip these on this session.
      _healAttempted.addAll(list);
      debugPrint('[Canvas] Loaded ${list.length} known-incurable assets '
          'from disk (skipping heal re-fetch this session)');
    } catch (_) {}
  }

  Future<void> _persistIncurableAssets(String notebookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_knownIncurableAssets.isEmpty) {
        await prefs.remove(_incurableAssetsPrefsKey(notebookId));
      } else {
        await prefs.setString(_incurableAssetsPrefsKey(notebookId),
            jsonEncode(_knownIncurableAssets.toList()));
      }
    } catch (_) {}
  }

  /// Drain every in-flight pull / pulled-save / remote-save so the .ncnote +
  /// SQLite metadata are up to date on disk.  Keeps `state` alive so the UI
  /// doesn't flash the "Nessun notebook aperto" fallback while the caller is
  /// still animating a pop.
  ///
  /// **Call this BEFORE `Navigator.pop()`** if the caller relies on reloading
  /// library metadata after the pop — otherwise the library's `.then()` fires
  /// as soon as the pop begins and reads a stale SQLite row (the bug where a
  /// notebook syncs 31 pages on open but the library card stays at "1 pagina"
  /// after exit because the pulled-save hadn't reached SQLite yet).
  Future<void> flushPendingWork() async {
    _pullTimer?.cancel();
    _pullTimer = null;
    _saveLastPosition();

    final pendingPull = _pendingPullFuture;
    if (pendingPull != null) {
      try { await pendingPull; } catch (_) {}
    }
    _pendingPullFuture = null;

    final pendingSave = _pendingPulledLocalSave;
    if (pendingSave != null) {
      try { await pendingSave; } catch (_) {}
    }
    _pendingPulledLocalSave = null;

    // Await any in-flight remote sync (launched fire-and-forget by save())
    // — without this, exiting during an upload can leave a half-committed
    // delta folder on the server (pages written, metadata.json stale),
    // which another device will then see as a conflict.
    final pendingRemoteSave = _pendingRemoteSave;
    if (pendingRemoteSave != null) {
      try { await pendingRemoteSave; } catch (_) {}
    }
    _pendingRemoteSave = null;

    // Await in-flight local ZIP rebuild (from save()'s background task).
    // Otherwise exit-after-stroke can leave the .ncnote without the very
    // last stroke, and a cold reopen would show pre-stroke content until
    // the next pull brings it back from the server.
    final pendingLocalSave = _pendingLocalSave;
    if (pendingLocalSave != null) {
      try { await pendingLocalSave; } catch (_) {}
    }
    _pendingLocalSave = null;
  }

  Future<void> closeNotebook() async {
    // Snapshot the generation: if another openNotebook() fires while we're
    // draining, the new open bumps [_openGeneration], and the teardown
    // below is skipped — otherwise we'd null out the freshly-populated
    // state and the canvas would be stuck on "Nessun notebook aperto".
    final myGen = _openGeneration;

    // Drain first so pulled pages + metadata actually land on disk before
    // the notifier tears down (the "ci rientro ed è scomparso tutto" bug).
    await flushPendingWork();

    if (_openGeneration != myGen) {
      // A newer open superseded us — the new generation owns `state` now.
      // Do not touch disposal flags or null the state.
      return;
    }

    // Only now tear down — everything that needed state has finished.
    // Dispose GPU textures BEFORE nulling state; otherwise the ui.Image
    // references get dropped without image.dispose() being called, which
    // on Linux leaks GPU handles until the renderer shuts down and
    // segfaults at exit.
    releaseImageCache();
    // Drop the static picture cache so the closed notebook's PageData
    // refs + ~5-10 MB of Skia picture buffers don't linger as zombie
    // memory across notebook switches.
    CanvasRenderEngine.disposeStaticCache();
    _disposed = true;
    _isPulling = false;
    isPullingFromRemote.value = false;
    _pendingMetaCommitTimer?.cancel();
    _pendingMetaCommitTimer = null;
    _forceReleaseSyncLock();
    _dirtyAssetKeys.clear();
    _lastSyncedPages = {};
    _lastSyncedDocument = null;
    _lastSyncedMetadata = null;
    _ghostEntryStrikes.clear();
    _consecutiveInconsistentPulls = 0;
    _consecutiveInconsistentSince = null;
    _preSaveGuardAborts = 0;
    _preSaveGuardSince = null;
    _knownIncurableAssets.clear();
    _healAttempted.clear();
    _assetsByLength.clear();
    _assetIndexBuilt = false;
    _pageJsonCache.clear();
    // Reset the corrupt-asset blocklist: once the user closes the notebook,
    // any "this asset failed to decode" state from this session is stale.
    // After a settings "Ricarica" replaces the local .ncnote with fresh
    // bytes from the server, re-entering the notebook must re-try decode
    // — otherwise the orange broken-image badge stays on forever even
    // though the underlying bytes are now valid.
    _corruptAssetIds.clear();
    _onDemandDecodeQueued.clear();
    // Keep _remoteMetaEtag, _lastPageEtags across
    // close/open to avoid re-pulling all pages on re-enter.
    state = null;
  }

  Future<void> _saveLastPosition() async {
    if (state == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final nbId = state!.metadata.id;
      await prefs.setInt('last_page_$nbId', state!.currentPageIndex);
      if (state!.activeChapterId != null) {
        await prefs.setString('last_chapter_$nbId', state!.activeChapterId!);
      } else {
        await prefs.remove('last_chapter_$nbId');
      }
    } catch (_) {
      // Non-critical — silently ignore
    }
  }

  // ── Tool management ──

  void setTool(CanvasTool tool) {
    if (state == null) return;

    // Bake any pending lasso transformations before switching tools
    if (tool != CanvasTool.lasso && state!.lassoSelection != null) {
      applySelectionTransform();
    }

    final s = state!;
    final fromTool = s.currentTool;

    // Persist the OUTGOING tool's settings so the next visit restores
    // them. Lasso/text/image/pan/laser don't have user-tunable settings,
    // so we skip recording for those.
    if (_toolHasSettings(fromTool)) {
      _toolPrefs[fromTool] = s.toolSettings;
    }

    // Remember the eraser sub-mode the user just picked so the dock
    // button restores it next time. Updated when the target is one of
    // the eraser variants OR when leaving eraser (in which case the
    // current value is already correct — no update needed).
    if (tool == CanvasTool.eraserStandard || tool == CanvasTool.eraserStroke) {
      _lastEraserMode = tool;
    }

    // Resolve the INCOMING tool's settings:
    //   1) per-tool memory if we have one
    //   2) tool-specific first-visit defaults (highlighter yellow/12 px/35 %)
    //   3) fall back to whatever the current toolSettings hold (rare —
    //      happens only for lasso/text/etc. that don't track settings).
    ToolSettings updatedSettings = s.toolSettings;
    final remembered = _toolPrefs[tool];
    if (remembered != null) {
      updatedSettings = remembered;
    } else if (tool == CanvasTool.highlighter) {
      updatedSettings = s.toolSettings.copyWith(
        color: 0xFFFFEB3B,
        strokeWidth: 12.0,
        opacity: 0.35,
      );
    } else if (_toolHasSettings(tool)) {
      // First visit to a pen-class tool — start with the global default
      // width and full opacity, keeping whatever colour the user had on
      // a previous pen-class tool (so pen → ballpoint stays the same
      // colour when ballpoint has never been touched before).
      updatedSettings = s.toolSettings.copyWith(
        strokeWidth: AppConfig.defaultStrokeWidth,
        opacity: 1.0,
        color: s.toolSettings.color == 0xFFFFEB3B
            ? 0xFF000000  // coming from highlighter default — neutralise
            : s.toolSettings.color,
      );
    }

    state = s.copyWith(
      currentTool: tool,
      toolSettings: updatedSettings,
      clearLasso: tool != CanvasTool.lasso,
      lassoPath: tool != CanvasTool.lasso ? const [] : s.lassoPath,
      showToolOptions: false,
      activeStroke: [],
      clearShapeStart: true,
      clearShapeEnd: true,
      clearEraserCursor: true,
      clearRecognizedShape: true,
      isAdjustingRecognized: false,
    );
    _persistToolPrefs();
  }

  /// Tools that have user-tunable settings worth remembering across
  /// switches. Lasso/text/image/pan/laser/shape don't carry width/colour
  /// state so they're omitted.
  bool _toolHasSettings(CanvasTool t) {
    return t == CanvasTool.pen ||
        t == CanvasTool.ballpoint ||
        t == CanvasTool.brush ||
        t == CanvasTool.calligraphy ||
        t == CanvasTool.highlighter ||
        t == CanvasTool.eraserStandard ||
        t == CanvasTool.eraserStroke;
  }

  Timer? _toolPrefsPersistDebounce;
  /// Debounced persist of _toolPrefs to SharedPreferences. We don't need
  /// to flush on every keystroke of the width slider — once the gesture
  /// settles, write the JSON blob once.
  void _persistToolPrefs() {
    _toolPrefsPersistDebounce?.cancel();
    _toolPrefsPersistDebounce =
        Timer(const Duration(milliseconds: 600), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final blob = <String, dynamic>{
          'lastEraserMode': _lastEraserMode.name,
          'tools': {
            for (final e in _toolPrefs.entries)
              e.key.name: {
                'color': e.value.color,
                'strokeWidth': e.value.strokeWidth,
                'opacity': e.value.opacity,
                'eraserSize': e.value.eraserSize.name,
              },
          },
        };
        await prefs.setString('canvas_tool_prefs_v1', jsonEncode(blob));
      } catch (_) {/* non-critical */}
    });
  }

  Future<void> _loadToolPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('canvas_tool_prefs_v1');
      if (raw == null || raw.isEmpty) return;
      final blob = jsonDecode(raw) as Map<String, dynamic>;
      final lastEr = blob['lastEraserMode'] as String?;
      if (lastEr != null) {
        _lastEraserMode = CanvasTool.values.firstWhere(
          (t) => t.name == lastEr,
          orElse: () => CanvasTool.eraserStroke,
        );
      }
      final tools = blob['tools'] as Map<String, dynamic>?;
      if (tools != null) {
        tools.forEach((toolName, settings) {
          final tool = CanvasTool.values.firstWhere(
            (t) => t.name == toolName,
            orElse: () => CanvasTool.pen,
          );
          final s = settings as Map<String, dynamic>;
          _toolPrefs[tool] = ToolSettings(
            color: s['color'] as int? ?? 0xFF000000,
            strokeWidth:
                (s['strokeWidth'] as num?)?.toDouble() ?? AppConfig.defaultStrokeWidth,
            opacity: (s['opacity'] as num?)?.toDouble() ?? 1.0,
            eraserSize: EraserSize.values.firstWhere(
              (e) => e.name == (s['eraserSize'] as String?),
              orElse: () => EraserSize.medium,
            ),
          );
        });
      }
    } catch (_) {/* non-critical */}
  }

  void toggleToolOptions() {
    if (state == null) return;
    state = state!.copyWith(showToolOptions: !state!.showToolOptions);
  }

  void setToolSettings(ToolSettings settings) {
    if (state == null) return;
    state = state!.copyWith(toolSettings: settings);
    _rememberToolPref();
  }

  /// Apply a saved pen preset: injects the preset's (color, strokeWidth,
  /// opacity) into the currently active tool. Used by the 3-slot preset
  /// rail in the tool popup so the user can flip between favorite
  /// configurations with one tap. Presets live on a per-tool rail (see
  /// AppSettings.presetsFor) — the user is already on the tool this
  /// preset belongs to, so no tool switch is needed here.
  void applyPenPreset(PenPreset preset) {
    if (state == null) return;
    setToolSettings(state!.toolSettings.copyWith(
      color: preset.color,
      strokeWidth: preset.strokeWidth,
      opacity: preset.opacity,
    ));
  }

  void setColor(int color) {
    if (state == null) return;
    if (state!.toolSettings.color == color) return;
    state = state!.copyWith(
      toolSettings: state!.toolSettings.copyWith(color: color),
    );
    _rememberToolPref();
  }

  /// Snapshot the current toolSettings into the per-tool memory and
  /// schedule a persist. Called whenever the user tweaks width / color /
  /// opacity / eraser size for the active tool so the next tool switch
  /// (and the next app launch) can restore those exact values.
  void _rememberToolPref() {
    final s = state;
    if (s == null) return;
    if (!_toolHasSettings(s.currentTool)) return;
    _toolPrefs[s.currentTool] = s.toolSettings;
    _persistToolPrefs();
  }

  /// Cancel the current stroke without committing (e.g. when pinch-to-zoom starts)
  void cancelStroke() {
    if (state == null) return;
    _eraserUndoPushed = false;
    _eraseGestureStart = null;
    state = state!.copyWith(
      activeStroke: [],
      clearShapeStart: true,
      clearShapeEnd: true,
      clearEraserCursor: true,
    );
  }

  void setStrokeWidth(double width) {
    if (state == null) return;
    if (state!.toolSettings.strokeWidth == width) return;
    state = state!.copyWith(
      toolSettings: state!.toolSettings.copyWith(strokeWidth: width),
    );
    _rememberToolPref();
  }

  void setEraserSize(EraserSize size) {
    if (state == null) return;
    if (state!.toolSettings.eraserSize == size) return;
    state = state!.copyWith(
      toolSettings: state!.toolSettings.copyWith(eraserSize: size),
    );
    _rememberToolPref();
  }

  void toggleShapeRecognition() {
    if (state == null) return;
    state = state!.copyWith(
      toolSettings: state!.toolSettings.copyWith(
        shapeRecognition: !state!.toolSettings.shapeRecognition,
      ),
    );
  }

  // ── Paper type ──

  void setPaperType(PaperType type) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;

    final fileName = s.currentPageFileName;
    final bgType = paperTypeToString(type);
    final lineSpacing = paperTypeLineSpacing(type);

    final undoStack = _pushUndo(s, fileName, page);

    final updatedPage = PageData(
      pageId: page.pageId,
      pageNumber: page.pageNumber,
      width: page.width,
      height: page.height,
      layers: RenderingLayers(
        background: BackgroundLayer(
          type: bgType,
          color: page.layers.background.color,
          lineSpacing: lineSpacing,
          lineColor: page.layers.background.lineColor,
        ),
        content: page.layers.content,
      ),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt,
      modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    // metadata.paperType only drives the Library cover's texture swatch and
    // the default for newly added pages — keep it in sync with page 1 so
    // the cover doesn't keep showing a stale paper type after the user
    // changes it.
    final metadata = page.pageNumber == 1
        ? s.metadata.copyWith(paperType: bgType, modifiedAt: DateTime.now())
        : s.metadata;

    state = s.copyWith(
      pages: updatedPages,
      metadata: metadata,
      undoStack: undoStack,
      redoStack: [],
      isDirty: true,
    );
  }

  // ── Drawing ──

  void startStroke(Offset position, double pressure) {
    if (state == null) return;
    final tool = state!.currentTool;

    if (tool == CanvasTool.pan || tool == CanvasTool.text || tool == CanvasTool.image) return;

    if (tool == CanvasTool.lasso) {
      _startLasso(position);
      return;
    }

    if (tool == CanvasTool.eraserStandard || tool == CanvasTool.eraserStroke) {
      _eraserUndoPushed = false; // Reset at start of each eraser gesture
      _lastEraseAtPos = const Offset(-1e9, -1e9); // unfreeze dist-throttle
      _eraseGestureStart = DateTime.now(); // for progressive growth
      state = state!.copyWith(eraserCursorPos: position);
      _eraseAt(position);
      return;
    }

    if (tool == CanvasTool.shape) {
      state = state!.copyWith(shapeStartPos: position, shapeEndPos: position);
      return;
    }

    state = state!.copyWith(
      activeStroke: [
        StrokePoint(x: position.dx, y: position.dy, pressure: pressure, timestamp: 0),
      ],
    );
  }

  void continueStroke(Offset position, double pressure) {
    if (state == null) return;
    final tool = state!.currentTool;

    if (tool == CanvasTool.lasso) {
      _continueLasso(position);
      return;
    }

    if (tool == CanvasTool.eraserStandard || tool == CanvasTool.eraserStroke) {
      // Note: do NOT call state.copyWith for eraserCursorPos here.
      // continueStroke fires at 60-120 Hz on Apple Pencil / mouse and
      // every state mutation triggers Riverpod fan-out to all
      // listeners (~7 selectors run their compute even if they don't
      // re-fire). _eraseAt below updates the cursor position itself
      // alongside its own distance throttle so the cursor moves
      // visibly only when erase work happens.
      _eraseAt(position);
      return;
    }

    if (tool == CanvasTool.shape) {
      state = state!.copyWith(shapeEndPos: position);
      return;
    }

    // Pen/brush/highlighter: fast notifier handles visual rendering,
    // no need to update Riverpod state on every point (avoids O(n) list copy).
    // Points are committed via commitAndEndStroke on pointer up.
  }

  /// Commit fast-notifier points and finalize the stroke in a single state update,
  /// avoiding the intermediate frame that causes visible line stretching.
  void commitAndEndStroke(List<StrokePoint> points) {
    if (state == null) return;
    if (points.isEmpty) {
      state = state!.copyWith(activeStroke: []);
      return;
    }
    // Single-point taps are valid 'dot' strokes — Apple Pencil quick taps
    // were previously discarded because the jitter-rejection filter trims
    // every nearby sample, leaving only the first point. Now we keep them
    // and the renderer draws a proportional dot for length-1 strokes.
    state = state!.copyWith(activeStroke: List.of(points));
    _addStrokeElement(state!);
  }

  void endStroke() {
    if (state == null) return;
    final tool = state!.currentTool;

    if (tool == CanvasTool.lasso) { _endLasso(); return; }
    if (tool == CanvasTool.eraserStandard || tool == CanvasTool.eraserStroke) {
      // Force-commit any throttled erasures so the pointer-up state
      // matches what the user saw on screen during the drag.
      if (_pendingErasePage != null) {
        _flushPendingErase();
      }
      _eraseGestureStart = null; // reset progressive-growth timer
      state = state!.copyWith(clearEraserCursor: true);
      return;
    }
    if (tool == CanvasTool.shape) { _finalizeShape(); return; }

    if (state!.activeStroke.isEmpty) {
      state = state!.copyWith(activeStroke: []);
      return;
    }

    final s = state!;
    final page = s.currentPage;
    if (page == null) return;

    // Try shape recognition at commit time if enabled
    if (s.toolSettings.shapeRecognition && s.activeStroke.length >= 5) {
      final recognized = _recognizeShape(s.activeStroke);
      if (recognized != null) {
        _commitRecognizedShape(s, recognized);
        return;
      }
    }

    _addStrokeElement(s);
  }

  /// Called from the hold-to-recognize timer: tries shape recognition on the
  /// active stroke while the user is still pressing (GoodNotes-style).
  void recognizeHeldStroke(List<StrokePoint> points) {
    if (state == null) return;
    if (!state!.toolSettings.shapeRecognition) return;
    if (points.length < 5) return;

    final recognized = _recognizeShape(points);
    if (recognized != null) {
      state = state!.copyWith(
        activeStroke: [],
        recognizedShape: recognized,
      );
    }
  }

  /// Called when user starts adjusting a recognized shape (pointer down while adjusting).
  void startAdjustRecognized(Offset position) {
    // Nothing to do here — we just mark the gesture started
  }

  /// Called when user drags while adjusting a recognized shape to change its endpoint.
  void adjustRecognizedShape(Offset position) {
    if (state == null || state!.recognizedShape == null) return;
    final shape = state!.recognizedShape!;
    // The user drags to adjust the endpoint / size
    ShapeData updated;
    switch (shape.shapeType) {
      case 'line':
      case 'arrow':
        final snapped = _snapLineEnd(shape.x1, shape.y1, position.dx, position.dy);
        // copyWith preserves isHighlighter (and any other untouched field)
        // — a from-scratch rebuild silently reset it to opaque on every
        // drag, which is why a highlighter-drawn recognized line turned
        // solid the moment the user adjusted it.
        updated = shape.copyWith(x2: snapped[0], y2: snapped[1]);
        break;
      case 'circle':
        final cx = (shape.x1 + shape.x2) / 2;
        final cy = (shape.y1 + shape.y2) / 2;
        final radius = sqrt(pow(position.dx - cx, 2) + pow(position.dy - cy, 2));
        updated = shape.copyWith(
          x1: cx - radius, y1: cy - radius,
          x2: cx + radius, y2: cy + radius,
        );
        break;
      case 'triangle':
      case 'rectangle':
      default:
        // Drag adjusts the bottom-right corner
        updated = shape.copyWith(x2: position.dx, y2: position.dy);
        break;
    }
    state = state!.copyWith(recognizedShape: updated);
  }

  /// For line shapes: keep x1,y1 fixed and move x2,y2 to [position].
  /// This lets the user adjust angle and length after hold-to-recognize.
  void setRecognizedLineEndpoint(Offset position) {
    if (state == null || state!.recognizedShape == null) return;
    final s = state!.recognizedShape!;
    final snapped = _snapLineEnd(s.x1, s.y1, position.dx, position.dy);
    state = state!.copyWith(
      recognizedShape: s.copyWith(x2: snapped[0], y2: snapped[1]),
    );
  }

  /// Fix top-left corner (x1,y1), resize by dragging bottom-right to [position].
  /// For circles: keep center fixed, change radius based on cursor distance.
  void resizeRecognizedShape(Offset position) {
    if (state == null || state!.recognizedShape == null) return;
    final s = state!.recognizedShape!;

    if (s.shapeType == 'circle' || s.shapeType == 'triangle') {
      // Keep center fixed, compute new size from cursor distance to center
      final cx = (s.x1 + s.x2) / 2;
      final cy = (s.y1 + s.y2) / 2;
      final dx = (position.dx - cx).abs();
      final dy = (position.dy - cy).abs();
      final halfW = max(dx, 5.0);
      final halfH = max(dy, 5.0);
      state = state!.copyWith(
        recognizedShape: s.copyWith(
          x1: cx - halfW, y1: cy - halfH,
          x2: cx + halfW, y2: cy + halfH,
        ),
      );
      return;
    }

    // x1,y1 is the anchor (opposite corner from pen at recognition time).
    // x2,y2 follows the cursor freely — rendering uses Rect.fromPoints
    // so any ordering is handled correctly.
    state = state!.copyWith(
      recognizedShape: s.copyWith(x2: position.dx, y2: position.dy),
    );
  }

  /// Called when user releases while adjusting a recognized shape — commit it.
  void commitRecognizedShape() {
    if (state == null || state!.recognizedShape == null) return;
    _addShapeElement(state!.recognizedShape!);
    state = state!.copyWith(clearRecognizedShape: true, isAdjustingRecognized: false);
  }

  /// Called to dismiss the recognized shape without committing.
  void dismissRecognizedShape() {
    if (state == null) return;
    state = state!.copyWith(clearRecognizedShape: true, isAdjustingRecognized: false);
  }

  /// Immediately commit a recognized shape (used at endStroke for instant recognition).
  void _commitRecognizedShape(CanvasState s, ShapeData shape) {
    _addShapeElement(shape);
    state = state!.copyWith(activeStroke: []);
  }

  void _addStrokeElement(CanvasState s) {
    final page = s.currentPage!;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);

    String toolType;
    bool isHighlighter = false;
    double opacity = s.toolSettings.opacity;

    switch (s.currentTool) {
      case CanvasTool.pen: toolType = 'pen'; break;
      case CanvasTool.ballpoint: toolType = 'ballpoint'; break;
      case CanvasTool.brush: toolType = 'brush'; break;
      case CanvasTool.calligraphy: toolType = 'calligraphy'; break;
      case CanvasTool.highlighter:
        toolType = 'highlighter'; isHighlighter = true; opacity = 0.35; break;
      default: toolType = 'pen';
    }

    // No commit-time smoothing pass: the ActiveStrokeNotifier already
    // smoothed each point inline (3- or 5-tap FIR depending on input
    // device). Re-applying a 1-2-1 here shifted the committed shape
    // 1-3 px on cusps relative to what was painted live, producing
    // the visible "snap" the user saw when lifting the pen. Keeping
    // the live preview's geometry consistent with the committed
    // stroke also unifies the 80-point threshold edge case where
    // long strokes silently switched smoothing modes.
    final smoothedPoints = s.activeStroke;

    final newElement = ContentElement.stroke(
      id: const Uuid().v4(),
      zIndex: _nextZIndex(page),
      data: StrokeData(
        points: smoothedPoints,
        toolType: toolType,
        color: s.toolSettings.color,
        baseWidth: s.toolSettings.strokeWidth,
        isHighlighter: isHighlighter,
        opacity: opacity,
        timestamp: DateTime.now(),
      ),
    );

    final updatedPage = _pageWithNewElement(page, newElement);
    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    state = s.copyWith(
      pages: updatedPages,
      activeStroke: [],
      undoStack: undoStack,
      redoStack: [],
      isDirty: true,
    );
  }


  // ── Shape recognition (improved) ──

  ShapeData? _recognizeShape(List<StrokePoint> points) {
    if (points.length < 5) return null;

    final xs = points.map((p) => p.x).toList();
    final ys = points.map((p) => p.y).toList();
    final minX = xs.reduce(min);
    final maxX = xs.reduce(max);
    final minY = ys.reduce(min);
    final maxY = ys.reduce(max);
    final width = maxX - minX;
    final height = maxY - minY;
    final maxDim = max(width, height);

    if (maxDim < 10) return null;

    // Total path length vs straight line distance
    double pathLen = 0;
    for (int i = 1; i < points.length; i++) {
      pathLen += sqrt(pow(points[i].x - points[i - 1].x, 2) + pow(points[i].y - points[i - 1].y, 2));
    }
    final startEndDist = sqrt(pow(points.last.x - points.first.x, 2) + pow(points.last.y - points.first.y, 2));
    
    // A recognized shape is a clean geometric figure that REPLACES the
    // freehand gesture, so it should carry the tool's nominal width — exactly
    // like a shape drawn with the manual shape tool (see _finalizeShape, which
    // uses toolSettings.strokeWidth directly). Earlier attempts scaled this by
    // average pressure (a linear 0.15..1.0× map, then a sqrt 0.35..1.50× one),
    // but a flat-width shape painted at the average pressure still read as
    // thinner than the default line — pressure modulation belongs to live
    // strokes, not to the snapped result. Use the full stroke width.
    final visualWidth = state!.toolSettings.strokeWidth;
    final color = state!.toolSettings.color;
    // A shape recognized while the highlighter is active must keep the
    // highlighter's translucent multiply look — otherwise it commits as
    // an opaque mark that covers whatever ink is underneath it.
    final isHighlighter = state!.currentTool == CanvasTool.highlighter;

    // ── LINE DETECTION ──
    // If the path length is barely longer than the distance between
    // start and end, treat as a straight line. Arrow auto-recognition
    // was removed because tiny natural wobbles at the end of a line
    // were being misclassified as an arrow head — the user almost
    // always wanted just a line. Arrows can still be drawn manually
    // via the shape tool.
    if (pathLen > 20 && (pathLen / startEndDist) < 1.25) {
      return ShapeData(
        shapeType: 'line',
        x1: points.first.x, y1: points.first.y,
        x2: _snapLineEnd(points.first.x, points.first.y, points.last.x, points.last.y)[0],
        y2: _snapLineEnd(points.first.x, points.first.y, points.last.x, points.last.y)[1],
        strokeColor: color, strokeWidth: visualWidth, isHighlighter: isHighlighter,
      );
    }

    // ── CLOSURE CHECK ──
    // Allow a generous overlap gap for messy hand drawing
    final isClosed = startEndDist < maxDim * 0.35;
    if (!isClosed) return null;

    // Auto-fill closed shapes with a transparent version of the stroke color.
    const fillAlpha = 0x30; // ~19% opacity
    final autoFill = (color & 0x00FFFFFF) | (fillAlpha << 24);

    // ── POLYGON DETECTION (Douglas-Peucker) — run early to inform circle vs rect ──
    final offsets = points.map((p) => Offset(p.x, p.y)).toList();
    
    // Lowered epsilon to 0.06 to avoid over-smoothing rounded corners
    final simplified = _douglasPeucker(offsets, maxDim * 0.06);
    
    // Remove the last point if it overlaps the first to get the true corner count
    List<Offset> corners = List.from(simplified);
    if (corners.length > 1 && (corners.first - corners.last).distance < maxDim * 0.25) {
      corners.removeLast();
    }

    // ── CIRCLE DETECTION (Radial Variance) ──
    // A circle has many Douglas-Peucker segments (7+), while
    // rectangles have 4-6 and triangles have 3. Use corner count
    // to disambiguate: only accept circle if NOT in polygon range (4-6).
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    double sumR = 0, sumR2 = 0;
    
    for (final p in points) {
      final r = sqrt(pow(p.x - cx, 2) + pow(p.y - cy, 2));
      sumR += r;
      sumR2 += r * r;
    }
    
    final avgR = sumR / points.length;
    final radialVariance = (sumR2 / points.length) - (avgR * avgR);
    final radialCV = avgR > 0 ? sqrt(radialVariance) / avgR : 0.0;
    final aspectRatio = min(width, height) / max(width, height);

    // Accept circle on radial fit + aspect alone. The previous corner-
    // count gate (`notPolygonRange = corners.length < 4 || > 6`)
    // silently rejected circles drawn from 12 o'clock or 6 o'clock:
    // Douglas-Peucker on a closure-deduped circle starting from the top
    // commonly produces 4-6 corners (cardinal-quartet collapse), failing
    // the gate; the shape then fell through to the rhombus check and
    // was recognized as a rhombus, looking visually smaller than the
    // user's stroke. radialCV<0.20 covers natural hand jitter at slow
    // start/end points (a typical hand-drawn circle has CV in the
    // 0.10-0.18 range; 0.15 was rejecting top-started ones whose start
    // density spiked CV slightly). aspectRatio>0.60 is enough to
    // exclude genuine ovals; further refinement (rectangle disambig)
    // is handled by the polygon branches that follow when this gate
    // fails.
    // ── EDGE-BULGE GATE (circle vs square/rectangle) ──
    // radialCV + aspect alone can't separate a circle from a SQUARE: a square
    // has aspect ≈ 1 and a fairly low radial CV, so it used to be recognized
    // as a circle. The true difference is edge shape — a square's corner-to-
    // corner edges are STRAIGHT, a circle's are ARCS that bulge away from the
    // chord. Measure the mean per-edge bulge (max perpendicular deviation of
    // the stroke from each corner chord, normalised by maxDim):
    //   • many corners (≥7) ⇒ clearly round, accept regardless;
    //   • few corners but bulging edges ⇒ a circle drawn from 12/6 o'clock
    //     (Douglas-Peucker collapses it to 4–6 corners) — still accept;
    //   • few corners AND straight edges ⇒ a real square/rectangle — REJECT,
    //     let the polygon branches below classify it.
    double meanEdgeBulge = 1.0; // default high ⇒ don't reject if mapping fails
    if (corners.length >= 3) {
      // Map each corner to its index in `offsets` (DP returns a subsequence).
      final cornerIdx = <int>[];
      int searchFrom = 0;
      for (final c in corners) {
        for (int j = searchFrom; j < offsets.length; j++) {
          if (offsets[j] == c) {
            cornerIdx.add(j);
            searchFrom = j + 1;
            break;
          }
        }
      }
      if (cornerIdx.length == corners.length) {
        double bulgeSum = 0;
        int bulgeEdges = 0;
        for (int k = 0; k < corners.length; k++) {
          final a = corners[k];
          final b = corners[(k + 1) % corners.length];
          final chord = b - a;
          final chordLen = chord.distance;
          if (chordLen < 1e-3) continue;
          final ai = cornerIdx[k];
          final bi = (k + 1 < corners.length)
              ? cornerIdx[k + 1]
              : offsets.length - 1; // closing edge wraps to the path end
          double maxPerp = 0;
          for (int j = ai; j <= bi && j < offsets.length; j++) {
            final v = offsets[j] - a;
            final perp = (v.dx * chord.dy - v.dy * chord.dx).abs() / chordLen;
            if (perp > maxPerp) maxPerp = perp;
          }
          bulgeSum += maxPerp;
          bulgeEdges++;
        }
        if (bulgeEdges > 0) meanEdgeBulge = (bulgeSum / bulgeEdges) / maxDim;
      }
    }

    // 0.04·maxDim of bulge cleanly separates hand-jitter on straight square
    // edges (~0.01–0.03) from a circle's arc edges (~0.07–0.15).
    final hasCurvyEdges = corners.length >= 7 || meanEdgeBulge > 0.04;
    final isCircleCandidate =
        radialCV < 0.20 && aspectRatio > 0.60 && hasCurvyEdges;

    if (isCircleCandidate) {
      // Radius is the LARGER of two estimates: half the bigger bbox
      // dimension, OR the mean point-to-centre distance. When a user
      // starts from 12/6 o'clock and ergonomically curves back early
      // before reaching the full bottom/top extent, the bbox shrinks
      // (undershoots the intended circle) but the mean radius still
      // reflects the user's curvature — most points sit at the
      // intended radius even if the bbox doesn't capture the full
      // diameter. Taking the max of the two estimates absorbs this
      // asymmetry: perfect circle → both equal, no change; under-
      // shoot from top/bottom → avgR > bbox/2, use avgR (the user's
      // curvature wins); slightly-oval drawn fully → bbox/2 ≥ avgR,
      // bbox/2 wins. Either way the recognized circle never shrinks
      // below what the user's stroke physically traces.
      final r = max(max(width, height) / 2, avgR);
      return ShapeData(
        shapeType: 'circle',
        x1: cx - r, y1: cy - r,
        x2: cx + r, y2: cy + r,
        strokeColor: color, strokeWidth: visualWidth, isHighlighter: isHighlighter,
        fillColor: autoFill,
      );
    }

    // ── TRIANGLE ──
    // Preserve the user's apex orientation. The renderer draws an
    // "apex up" triangle inside the bbox and applies `rotation` around
    // the bbox centre, so we encode the actual apex direction as a
    // rotation angle. Without this, every triangle was canonicalised
    // to apex-up regardless of how the user drew it (op-amps drawn
    // pointing right became pointing up, etc).
    if (corners.length == 3) {
      final centroid = Offset(
        (corners[0].dx + corners[1].dx + corners[2].dx) / 3,
        (corners[0].dy + corners[1].dy + corners[2].dy) / 3,
      );
      // Apex = the vertex between the two most-equal-length edges (the tip of
      // an isosceles triangle). This is orientation- AND aspect-independent.
      // The old "farthest corner from the centroid" heuristic was wrong for
      // WIDE/flat triangles: a base corner can sit farther from the centroid
      // than the apex (e.g. a short, wide "roof"), so the detected apex — and
      // thus the pointing direction — flipped to a base corner. Comparing each
      // vertex's two adjacent edges instead finds the symmetric tip regardless
      // of which way (up/down/left/right/oblique) the triangle points.
      int apexIdx = 0;
      double bestBalance = double.infinity;
      for (int i = 0; i < 3; i++) {
        final e1 = (corners[i] - corners[(i + 2) % 3]).distance;
        final e2 = (corners[i] - corners[(i + 1) % 3]).distance;
        final sum = e1 + e2;
        final balance = sum > 0 ? (e1 - e2).abs() / sum : 1.0;
        if (balance < bestBalance) {
          bestBalance = balance;
          apexIdx = i;
        }
      }
      final apex = corners[apexIdx];
      // Canvas y is flipped (down=positive). Apex-up corresponds to
      // angle = -π/2 from centroid. Required rotation to produce the
      // user's apex direction = (drawn angle) − (canonical −π/2).
      final drawnAngle =
          atan2(apex.dy - centroid.dy, apex.dx - centroid.dx);
      double rotation = drawnAngle + pi / 2;
      // Normalize to [0, 2π) so the modular snap below is symmetric.
      while (rotation < 0) { rotation += 2 * pi; }
      while (rotation >= 2 * pi) { rotation -= 2 * pi; }
      // Snap aggressively (within ~25°) to the nearest cardinal direction
      // (0, π/2, π, 3π/2). Hand-drawn triangles vary much more than 11°
      // (the previous threshold), and a slight tilt almost always means
      // "the user wanted apex-up but drew at 18°", not "the user
      // intended a 18° tilt". Cardinal results render cleanly inside
      // the bbox without rotation transform (see _paintShape).
      const cardinalSnap = 0.44;  // ~25°
      final nearestQuarter = (rotation / (pi / 2)).round() * (pi / 2);
      final isCardinal = (rotation - nearestQuarter).abs() < cardinalSnap;
      if (isCardinal) {
        rotation = nearestQuarter % (2 * pi);
      }
      // For oblique (non-cardinal) triangles the canonical apex-up +
      // canvas.rotate path was geometrically wrong: the canonical apex
      // sat at distance H/2 from bbox center, but the user's actual
      // apex sat at (corner_to_centroid) distance, generally not H/2.
      // The rendered apex landed inside or outside the bbox at the
      // wrong place. Fix: store the user's three actual vertices and
      // render them directly. On resize, an affine bbox→bbox remap
      // preserves geometry exactly.
      final base1 = corners[(apexIdx + 1) % 3];
      final base2 = corners[(apexIdx + 2) % 3];
      final vertices = isCardinal
          ? const <double>[]
          : <double>[apex.dx, apex.dy, base1.dx, base1.dy, base2.dx, base2.dy];
      return ShapeData(
        shapeType: 'triangle',
        x1: minX, y1: minY, x2: maxX, y2: maxY,
        rotation: rotation,
        vertices: vertices,
        strokeColor: color, strokeWidth: visualWidth, isHighlighter: isHighlighter,
        fillColor: autoFill,
      );
    }

    // ── RHOMBUS (4 corners with roughly equal edge lengths, diamond shape) ──
    if (corners.length == 4) {
      // Check if all edge lengths are roughly equal (within 30%)
      final edgeLengths = <double>[];
      for (int i = 0; i < 4; i++) {
        edgeLengths.add((corners[i] - corners[(i + 1) % 4]).distance);
      }
      final avgEdge = edgeLengths.reduce((a, b) => a + b) / 4;
      final edgeVariation = edgeLengths.map((e) => (e - avgEdge).abs() / avgEdge).reduce(max);

      if (edgeVariation < 0.30) {
        // Check it's more diamond-like than rectangular:
        // diagonals should be perpendicular (or close to it)
        final d1 = corners[2] - corners[0]; // diagonal 1
        final d2 = corners[3] - corners[1]; // diagonal 2
        final dotProduct = (d1.dx * d2.dx + d1.dy * d2.dy).abs();
        final d1Len = d1.distance;
        final d2Len = d2.distance;
        final cosAngle = (d1Len > 0 && d2Len > 0) ? dotProduct / (d1Len * d2Len) : 1.0;

        // Also check the shape area vs bounding box area ratio
        // A rhombus fills ~50% of its bounding box, a rectangle fills ~100%
        double shapeArea = 0;
        for (int i = 0; i < 4; i++) {
          final p1 = corners[i];
          final p2 = corners[(i + 1) % 4];
          shapeArea += (p1.dx * p2.dy) - (p2.dx * p1.dy);
        }
        shapeArea = shapeArea.abs() / 2;
        final bboxArea = width * height;
        final fillRatio = bboxArea > 0 ? shapeArea / bboxArea : 1.0;

        // Rhombus: near-perpendicular diagonals OR diamond-like fill ratio (<75%)
        if (cosAngle < 0.3 || fillRatio < 0.75) {
          return ShapeData(
            shapeType: 'rhombus',
            x1: minX, y1: minY,
            x2: maxX, y2: maxY,
            strokeColor: color, strokeWidth: visualWidth, isHighlighter: isHighlighter,
            fillColor: autoFill,
          );
        }
      }
    }

    // ── RECTANGLE (With slant/rotation support) ──
    if (corners.length >= 4 && corners.length <= 6) {
      double maxEdgeLen = 0;
      double angle = 0;
      for (int i = 0; i < corners.length; i++) {
        final p1 = corners[i];
        final p2 = corners[(i + 1) % corners.length];
        final dist = (p1 - p2).distance;
        if (dist > maxEdgeLen) {
          maxEdgeLen = dist;
          angle = atan2(p2.dy - p1.dy, p2.dx - p1.dx);
        }
      }

      // Snap-to-cardinal threshold: was 0.2 rad (≈11.5°) which
      // flattened any rectangle drawn with a small intentional tilt
      // back to axis-aligned. 0.157 rad ≈ 9°: enough margin for
      // "tried to draw straight but was a bit off" while preserving
      // anything visibly tilted as the user intended.
      final snappedAngle = (angle / (pi / 2)).round() * (pi / 2);
      if ((angle - snappedAngle).abs() < 0.157) angle = snappedAngle;

      // For axis-aligned rectangles (angle is multiple of π/2), use the
      // simple bounding box directly. The OBB rotation is only needed for
      // truly tilted rectangles — using it for axis-aligned ones produces
      // distorted coordinates that break resize and rendering.
      final isAxisAligned = (angle % (pi / 2)).abs() < 0.01 || ((angle % (pi / 2)).abs() - pi / 2).abs() < 0.01;

      double rMinX, rMaxX, rMinY, rMaxY;
      double finalAngle;

      if (isAxisAligned) {
        // Use raw bounding box — no rotation needed
        rMinX = minX;
        rMaxX = maxX;
        rMinY = minY;
        rMaxY = maxY;
        finalAngle = 0;
      } else {
        // Tilted rectangle: compute OBB
        final cosA = cos(-angle);
        final sinA = sin(-angle);
        rMinX = double.infinity;
        rMaxX = double.negativeInfinity;
        rMinY = double.infinity;
        rMaxY = double.negativeInfinity;

        for (final p in offsets) {
          final dx = p.dx - cx;
          final dy = p.dy - cy;
          final rx = dx * cosA - dy * sinA;
          final ry = dx * sinA + dy * cosA;
          if (rx < rMinX) rMinX = rx;
          if (rx > rMaxX) rMaxX = rx;
          if (ry < rMinY) rMinY = ry;
          if (ry > rMaxY) rMaxY = ry;
        }
        // Convert back to page-space
        rMinX += cx;
        rMaxX += cx;
        rMinY += cy;
        rMaxY += cy;
        finalAngle = angle;
      }

      final obbW = rMaxX - (isAxisAligned ? rMinX : rMinX);
      final obbH = rMaxY - (isAxisAligned ? rMinY : rMinY);
      final obbArea = obbW * obbH;

      double shapeArea = 0;
      for (int i = 0; i < corners.length; i++) {
        final p1 = corners[i];
        final p2 = corners[(i + 1) % corners.length];
        shapeArea += (p1.dx * p2.dy) - (p2.dx * p1.dy);
      }
      shapeArea = (shapeArea.abs() / 2);

      if (obbArea > 0 && (shapeArea / obbArea) > 0.70) {
        // Find which corner the pen ended near
        final endPoint = Offset(points.last.x, points.last.y);
        final rectCorners = [
          Offset(rMinX, rMinY), // Top-Left
          Offset(rMaxX, rMinY), // Top-Right
          Offset(rMaxX, rMaxY), // Bottom-Right
          Offset(rMinX, rMaxY), // Bottom-Left
        ];
        int closestIdx = 0;
        double closestDist = double.infinity;
        for (int i = 0; i < 4; i++) {
          final d = (rectCorners[i] - endPoint).distance;
          if (d < closestDist) {
            closestDist = d;
            closestIdx = i;
          }
        }
        return ShapeData(
          shapeType: 'rectangle',
          x1: rectCorners[(closestIdx + 2) % 4].dx,
          y1: rectCorners[(closestIdx + 2) % 4].dy,
          x2: rectCorners[closestIdx].dx,
          y2: rectCorners[closestIdx].dy,
          rotation: finalAngle,
          strokeColor: color, strokeWidth: visualWidth, isHighlighter: isHighlighter,
          fillColor: autoFill,
        );
      }
    }

    return null;
  }

  // ── MATHEMATICAL HELPERS ──

  /// Snap line end to nearest common angle if within threshold.
  /// Snaps to multiples of 15° (0°, 15°, 30°, 45°, 60°, 75°, 90°, …).
  /// Returns [snappedX2, snappedY2].
  List<double> _snapLineEnd(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final lineLen = sqrt(dx * dx + dy * dy);
    if (lineLen < 5) return [x2, y2];

    final angle = atan2(dy, dx); // radians
    // Snap to multiples of 15° (π/12)
    const snapStep = pi / 12; // 15 degrees
    const snapThreshold = 0.065; // ~3.7 degrees in radians

    final nearest = (angle / snapStep).round() * snapStep;
    if ((angle - nearest).abs() < snapThreshold) {
      return [x1 + lineLen * cos(nearest), y1 + lineLen * sin(nearest)];
    }
    return [x2, y2];
  }

  /// Douglas-Peucker algorithm to reduce complex paths into core geometric vertices
  List<Offset> _douglasPeucker(List<Offset> points, double epsilon) {
    if (points.length <= 2) return points;

    double maxDist = 0.0;
    int index = 0;
    final end = points.length - 1;

    for (int i = 1; i < end; i++) {
      final dist = _perpendicularDistance(points[i], points[0], points[end]);
      if (dist > maxDist) {
        maxDist = dist;
        index = i;
      }
    }

    if (maxDist > epsilon) {
      final left = _douglasPeucker(points.sublist(0, index + 1), epsilon);
      final right = _douglasPeucker(points.sublist(index, end + 1), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [points[0], points[end]];
    }
  }

  /// Calculates the shortest distance from a point to a line segment
  double _perpendicularDistance(Offset pt, Offset lineStart, Offset lineEnd) {
    final dx = lineEnd.dx - lineStart.dx;
    final dy = lineEnd.dy - lineStart.dy;
    final mag = sqrt(dx * dx + dy * dy);
    
    if (mag > 0.0) {
      return ((pt.dx - lineStart.dx) * dy - (pt.dy - lineStart.dy) * dx).abs() / mag;
    }
    return (pt - lineStart).distance;
  }


  void _addShapeElement(ShapeData shapeData) {
    final s = state!;
    final page = s.currentPage!;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);

    final newElement = ContentElement.shape(
      id: const Uuid().v4(),
      zIndex: _nextZIndex(page),
      data: shapeData,
    );

    final updatedPage = _pageWithNewElement(page, newElement);
    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    state = s.copyWith(
      pages: updatedPages,
      activeStroke: [],
      undoStack: undoStack,
      redoStack: [],
      isDirty: true,
    );
  }

  void _finalizeShape() {
    if (state == null) return;
    final s = state!;
    if (s.shapeStartPos == null || s.shapeEndPos == null) {
      state = s.copyWith(clearShapeStart: true, clearShapeEnd: true);
      return;
    }

    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);

    final newElement = ContentElement.shape(
      id: const Uuid().v4(),
      zIndex: _nextZIndex(page),
      data: ShapeData(
        shapeType: s.toolSettings.shapeType,
        x1: s.shapeStartPos!.dx, y1: s.shapeStartPos!.dy,
        x2: s.shapeEndPos!.dx, y2: s.shapeEndPos!.dy,
        strokeColor: s.toolSettings.color,
        strokeWidth: s.toolSettings.strokeWidth,
      ),
    );

    final updatedPage = _pageWithNewElement(page, newElement);
    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    state = s.copyWith(
      pages: updatedPages,
      undoStack: undoStack,
      redoStack: [],
      isDirty: true,
      clearShapeStart: true,
      clearShapeEnd: true,
    );
  }

  // ── Eraser ──

  /// Distance from point [p] to the line segment [a]-[b].
  static double _distToSegment(Offset p, Offset a, Offset b) {
    final l2 = (b - a).distanceSquared;
    if (l2 == 0) return (p - a).distance;
    var t = ((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2;
    t = t.clamp(0.0, 1.0);
    return (p - Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy))).distance;
  }

  /// Minimum distance from point [p] to the four edges of [rect].
  static double _distToRectEdges(Offset p, Rect rect) {
    final tl = rect.topLeft, tr = rect.topRight, bl = rect.bottomLeft, br = rect.bottomRight;
    return [
      _distToSegment(p, tl, tr),
      _distToSegment(p, tr, br),
      _distToSegment(p, br, bl),
      _distToSegment(p, bl, tl),
    ].reduce(min);
  }

  /// Convert a shape outline into sampled edge segments (list of point lists).
  /// Each edge is densely sampled so point-by-point erasure works.
  /// Points are in final (rotated) coordinates.
  static List<List<StrokePoint>> _shapeToSampledEdges(ShapeData sh, double stepSize) {
    final rawEdges = <List<Offset>>[];

    switch (sh.shapeType) {
      case 'line':
      case 'arrow':
        rawEdges.add([Offset(sh.x1, sh.y1), Offset(sh.x2, sh.y2)]);
        break;
      case 'rectangle':
        final l = min(sh.x1, sh.x2), r = max(sh.x1, sh.x2);
        final t = min(sh.y1, sh.y2), b = max(sh.y1, sh.y2);
        rawEdges.addAll([
          [Offset(l, t), Offset(r, t)],
          [Offset(r, t), Offset(r, b)],
          [Offset(r, b), Offset(l, b)],
          [Offset(l, b), Offset(l, t)],
        ]);
        break;
      case 'triangle':
        final tLeft = min(sh.x1, sh.x2), tRight = max(sh.x1, sh.x2);
        final top = min(sh.y1, sh.y2), bottom = max(sh.y1, sh.y2);
        final apex = Offset((tLeft + tRight) / 2, top);
        final bl = Offset(tLeft, bottom), br = Offset(tRight, bottom);
        rawEdges.addAll([[apex, bl], [bl, br], [br, apex]]);
        break;
      case 'rhombus':
        final rl = min(sh.x1, sh.x2), rr = max(sh.x1, sh.x2);
        final rt = min(sh.y1, sh.y2), rb = max(sh.y1, sh.y2);
        final mx = (rl + rr) / 2, my = (rt + rb) / 2;
        final top = Offset(mx, rt), right = Offset(rr, my);
        final bottom = Offset(mx, rb), left = Offset(rl, my);
        rawEdges.addAll([
          [top, right],
          [right, bottom],
          [bottom, left],
          [left, top],
        ]);
        break;
      case 'circle':
        final cx = (sh.x1 + sh.x2) / 2;
        final cy = (sh.y1 + sh.y2) / 2;
        final radius = Offset(sh.x2 - sh.x1, sh.y2 - sh.y1).distance / 2;
        final n = max(36, (2 * pi * radius / stepSize).ceil());
        // Circle as one continuous edge of n+1 points
        final pts = <Offset>[];
        for (int i = 0; i <= n; i++) {
          final a = 2 * pi * i / n;
          pts.add(Offset(cx + radius * cos(a), cy + radius * sin(a)));
        }
        rawEdges.add(pts);
        break;
      default:
        final l = min(sh.x1, sh.x2), r = max(sh.x1, sh.x2);
        final t = min(sh.y1, sh.y2), b = max(sh.y1, sh.y2);
        rawEdges.addAll([
          [Offset(l, t), Offset(r, t)],
          [Offset(r, t), Offset(r, b)],
          [Offset(r, b), Offset(l, b)],
          [Offset(l, b), Offset(l, t)],
        ]);
        break;
    }

    // Rotation transform
    final cx = (sh.x1 + sh.x2) / 2;
    final cy = (sh.y1 + sh.y2) / 2;
    final hasRotation = sh.rotation != 0;
    final cosA = hasRotation ? cos(sh.rotation) : 1.0;
    final sinA = hasRotation ? sin(sh.rotation) : 0.0;

    Offset rotatePoint(Offset p) {
      if (!hasRotation) return p;
      final dx = p.dx - cx;
      final dy = p.dy - cy;
      return Offset(cx + dx * cosA - dy * sinA, cy + dx * sinA + dy * cosA);
    }

    // Sample each edge and apply rotation
    final result = <List<StrokePoint>>[];
    for (final edge in rawEdges) {
      final sampled = <StrokePoint>[];
      // For multi-point edges (circles), sample between consecutive pairs
      for (int i = 0; i < edge.length - 1; i++) {
        final p1 = edge[i];
        final p2 = edge[i + 1];
        final dist = (p2 - p1).distance;
        final count = max(2, (dist / stepSize).ceil() + 1);
        // Don't duplicate the start point for interior segments
        final startIdx = (i == 0) ? 0 : 1;
        for (int j = startIdx; j < count; j++) {
          final t = j / (count - 1);
          final raw = Offset(p1.dx + (p2.dx - p1.dx) * t, p1.dy + (p2.dy - p1.dy) * t);
          final rotated = rotatePoint(raw);
          sampled.add(StrokePoint(x: rotated.dx, y: rotated.dy, pressure: 1.0));
        }
      }
      if (sampled.length >= 2) result.add(sampled);
    }
    return result;
  }

  void _eraseAt(Offset position) {
    if (state == null) return;
    final s = state!;
    // Base radius from the user's eraser-size pref, scaled up after a
    // sustained gesture. Curve: starts at 1.0, ramps to ~2.5 over 5 s
    // of continuous drawing, then caps. The user keeps moving →
    // effective radius keeps growing, so "wipe everything in this
    // region" works without flipping size from the popup.
    final base = eraserSizeToRadius(s.toolSettings.eraserSize);
    final startedAt = _eraseGestureStart;
    double growth = 1.0;
    if (startedAt != null) {
      final secs = DateTime.now().difference(startedAt).inMilliseconds / 1000;
      // Linear up to 5 s, capped at 2.5×. Gesture under ~0.8 s leaves
      // growth ≈ 1.05 — imperceptible, doesn't surprise the user on
      // quick taps.
      growth = (1.0 + secs * 0.30).clamp(1.0, 2.5);
    }
    final eraseRadius = base * growth;
    // Sub-radius movement check: any element a closer-spaced previous
    // sample might erase is also reachable from this near-identical
    // position, so skip the O(elements × points) scan entirely.
    final dx = position.dx - _lastEraseAtPos.dx;
    final dy = position.dy - _lastEraseAtPos.dy;
    final movedSq = dx * dx + dy * dy;
    final thresholdSq = (eraseRadius * _eraseRadiusFraction) *
        (eraseRadius * _eraseRadiusFraction);
    if (movedSq < thresholdSq) return;
    _lastEraseAtPos = position;

    // Now that we know we're going to do real erase work, push the
    // cursor visualisation to state. Throttling this with the same
    // dist-check as the erase compute means the cursor visibly moves
    // ~30 Hz instead of 120 Hz, but only saves Riverpod fan-out work
    // — at radius * 0.3 movement thresholds the cursor still tracks
    // the pointer smoothly to the eye.
    state = s.copyWith(eraserCursorPos: position);
    final s2 = state!;

    final fileName = s2.currentPageFileName;
    // Use the in-progress pending page as base if we have one — otherwise
    // each event would re-erase from the original (pre-gesture) page and
    // wipe out earlier erasures within the throttle window.
    final page =
        (_pendingErasePage != null && _pendingEraseFileName == fileName)
            ? _pendingErasePage!
            : s.currentPage;
    if (page == null) return;

    final isStrokeEraser = s.currentTool == CanvasTool.eraserStroke;

    final newContent = <ContentElement>[];
    bool changed = false;

    // Avoid `element.map(stroke:_, text:_, image:_, shape:_)` per
    // element — that's 4 closure allocations per call, twice per
    // element below = 8 closures × 200 elements × ~30 Hz ≈ 48 k
    // closure allocs/sec of pure GC pressure during a drag. Replace
    // with `is` checks on the runtime subtype which is zero-alloc.
    for (final element in page.layers.content) {
      bool shouldRemoveWhole = false;

      // Check non-stroke elements (text, symbols, shapes).
      // Per-tratto eraser: remove whole element if within bounding box.
      // Standard eraser: only remove if the eraser touches the actual outline/edge.
      if (element is TextElement) {
        final t = element.data;
        final rect = Rect.fromLTWH(t.x, t.y, t.width, t.height);
        if (isStrokeEraser) {
          if (rect.inflate(eraseRadius).contains(position)) shouldRemoveWhole = true;
        } else {
          if (_distToRectEdges(position, rect) < eraseRadius) shouldRemoveWhole = true;
        }
      } else if (element is ImageElement) {
        final img = element.data;
        if (img.assetPath.startsWith('symbol_')) {
          final rect = Rect.fromLTWH(img.x, img.y, img.width, img.height);
          if (isStrokeEraser) {
            if (rect.inflate(eraseRadius).contains(position)) shouldRemoveWhole = true;
          } else {
            if (_distToRectEdges(position, rect) < eraseRadius) shouldRemoveWhole = true;
          }
        }
      } else if (element is ShapeElement && isStrokeEraser) {
        final sh = element.data;
        final rect = Rect.fromPoints(
          Offset(sh.x1, sh.y1),
          Offset(sh.x2, sh.y2),
        );
        // Bbox is only a cheap reject: a diagonal line's bbox is mostly
        // empty space, so a bbox-contains test erased lines the cursor
        // was nowhere near. Confirm the hit against the sampled outline.
        // Rotated shapes skip the bbox gate — their outline can extend
        // outside the axis-aligned x1..x2/y1..y2 rect.
        if (sh.rotation != 0 ||
            rect.inflate(eraseRadius).contains(position)) {
          final r2 = eraseRadius * eraseRadius;
          outer:
          for (final edge in _shapeToSampledEdges(sh, eraseRadius * 0.5)) {
            for (final p in edge) {
              final dx = p.x - position.dx;
              final dy = p.y - position.dy;
              if (dx * dx + dy * dy < r2) {
                shouldRemoveWhole = true;
                break outer;
              }
            }
          }
        }
      } else if (element is MathElement) {
        // Typeset math is an atomic object (like text): delete the whole
        // equation on hit; never pixel-erase into it.
        final m = element.data;
        final rect = Rect.fromLTWH(m.x, m.y, m.width, m.height);
        if (isStrokeEraser) {
          if (rect.inflate(eraseRadius).contains(position)) shouldRemoveWhole = true;
        } else {
          if (_distToRectEdges(position, rect) < eraseRadius) shouldRemoveWhole = true;
        }
      }

      if (shouldRemoveWhole) {
        changed = true;
        continue;
      }

      // For strokes: stroke eraser removes entire stroke, standard eraser
      // splits it into segments by erasing only the touched points.
      // For shapes (standard eraser only): decompose outline into sampled
      // points and apply the same splitting logic, so only the touched
      // portion is erased.
      bool handled = false;
      // Same closure-free pattern: replace `element.map(stroke:_, ...)`
      // with a typed dispatch.
      if (element is StrokeElement) {
        final stroke = element;
        handled = true;

        // BBOX FAST PATH — most strokes on a dense page are nowhere
        // near the eraser cursor, so walking all 80 points just to
        // discover that is wasted work. Cache the stroke's bbox via
        // Expando the first time we see it.
        var bbox = _strokeBboxCache[stroke.data];
        if (bbox == null) {
          double minX = double.infinity, minY = double.infinity;
          double maxX = -double.infinity, maxY = -double.infinity;
          for (final p in stroke.data.points) {
            if (p.x < minX) minX = p.x;
            if (p.x > maxX) maxX = p.x;
            if (p.y < minY) minY = p.y;
            if (p.y > maxY) maxY = p.y;
          }
          if (minX == double.infinity) {
            newContent.add(element);
            continue;
          }
          bbox = Rect.fromLTRB(minX, minY, maxX, maxY);
          _strokeBboxCache[stroke.data] = bbox;
        }
        if (!bbox.inflate(eraseRadius).contains(position)) {
          newContent.add(element);
          continue;
        }

        final r2 = eraseRadius * eraseRadius;
        if (isStrokeEraser) {
          bool hit = false;
          for (final point in stroke.data.points) {
            final dx = point.x - position.dx;
            final dy = point.y - position.dy;
            if (dx * dx + dy * dy < r2) {
              hit = true;
              break;
            }
          }
          if (hit) {
            changed = true;
          } else {
            newContent.add(element);
          }
        } else {
          bool anyTouched = false;
          for (final point in stroke.data.points) {
            final dx = point.x - position.dx;
            final dy = point.y - position.dy;
            if (dx * dx + dy * dy < r2) {
              anyTouched = true;
              break;
            }
          }
          if (!anyTouched) {
            newContent.add(element);
            continue;
          }
          final segments = <List<StrokePoint>>[];
          var currentSegment = <StrokePoint>[];
          for (final point in stroke.data.points) {
            final dx = point.x - position.dx;
            final dy = point.y - position.dy;
            if (dx * dx + dy * dy < r2) {
              if (currentSegment.length >= 2) {
                segments.add(currentSegment);
              }
              currentSegment = [];
              changed = true;
            } else {
              currentSegment.add(point);
            }
          }
          if (currentSegment.length >= 2) {
            segments.add(currentSegment);
          }
          if (segments.isEmpty) {
            changed = true;
            continue;
          }
          if (segments.length == 1 &&
              segments[0].length == stroke.data.points.length) {
            newContent.add(element);
            continue;
          }
          for (final seg in segments) {
            newContent.add(ContentElement.stroke(
              id: const Uuid().v4(),
              zIndex: stroke.zIndex,
              data: StrokeData(
                points: seg,
                toolType: stroke.data.toolType,
                color: stroke.data.color,
                baseWidth: stroke.data.baseWidth,
                isHighlighter: stroke.data.isHighlighter,
                opacity: stroke.data.opacity,
                timestamp: stroke.data.timestamp,
              ),
            ));
          }
        }
      } else if (element is ShapeElement && !isStrokeEraser) {
        final sh = element;
        handled = true;
        final sampledEdges = _shapeToSampledEdges(sh.data, eraseRadius * 0.5);
        bool anyErased = false;
        final survivingStrokes = <ContentElement>[];

        for (final edgePoints in sampledEdges) {
          final segments = <List<StrokePoint>>[];
          var currentSeg = <StrokePoint>[];

          for (final point in edgePoints) {
            final dx = point.x - position.dx;
            final dy = point.y - position.dy;
            if (dx * dx + dy * dy < eraseRadius * eraseRadius) {
              if (currentSeg.length >= 2) segments.add(currentSeg);
              currentSeg = [];
              anyErased = true;
            } else {
              currentSeg.add(point);
            }
          }
          if (currentSeg.length >= 2) segments.add(currentSeg);

          for (final seg in segments) {
            survivingStrokes.add(ContentElement.stroke(
              id: const Uuid().v4(),
              zIndex: sh.zIndex,
              data: StrokeData(
                points: seg,
                toolType: 'ballpoint',
                color: sh.data.strokeColor,
                baseWidth: sh.data.strokeWidth,
                isHighlighter: false,
                opacity: 1.0,
              ),
            ));
          }
        }

        if (anyErased) {
          changed = true;
          newContent.addAll(survivingStrokes);
        } else {
          newContent.add(element);
        }
      }

      if (!handled) {
        newContent.add(element);
      }
    }

    if (!changed) return;

    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: newContent),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );

    // Stash the latest computed page locally; commit to `state` at most
    // every [_eraseFlushInterval] (or immediately on pointer-up via
    // [_flushPendingErase]). This drops the ~60-120 Hz state cascade
    // (Picture rebuild + chrome notify + Map<String,PageData>.from
    // copy of 215 entries) down to ~30 Hz while keeping erase visually
    // smooth.
    _pendingErasePage = updatedPage;
    _pendingEraseFileName = fileName;
    final elapsed = DateTime.now().difference(_lastEraseFlushAt);
    if (elapsed >= _eraseFlushInterval) {
      _flushPendingErase();
    } else {
      _eraseFlushTimer?.cancel();
      _eraseFlushTimer =
          Timer(_eraseFlushInterval - elapsed, _flushPendingErase);
    }
  }

  /// Apply the buffered eraser changes to `state`. Called from either
  /// the throttle Timer in [_eraseAt] or directly on pointer-up by
  /// [endStroke] so the final erase state always lands.
  void _flushPendingErase() {
    _eraseFlushTimer?.cancel();
    _eraseFlushTimer = null;
    final pending = _pendingErasePage;
    final fn = _pendingEraseFileName;
    if (pending == null || fn == null || state == null) {
      _pendingErasePage = null;
      _pendingEraseFileName = null;
      return;
    }
    final s = state!;
    if (s.currentPageFileName != fn) {
      // User flipped pages mid-erase; drop the buffer.
      _pendingErasePage = null;
      _pendingEraseFileName = null;
      return;
    }

    // Push undo only once per eraser gesture (first flush of the burst).
    List<UndoEntry> undoStack;
    if (!_eraserUndoPushed) {
      // Use the original pre-gesture page from `s.pages[fn]`, NOT the
      // pending page (which has erasures already applied).
      final originalPage = s.pages[fn];
      undoStack = originalPage == null
          ? s.undoStack
          : _pushUndo(s, fn, originalPage);
      _eraserUndoPushed = true;
    } else {
      undoStack = s.undoStack;
    }

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fn] = pending;

    state = s.copyWith(
      pages: updatedPages, undoStack: undoStack, redoStack: [], isDirty: true,
    );

    _pendingErasePage = null;
    _pendingEraseFileName = null;
    _lastEraseFlushAt = DateTime.now();
  }

  // ── Lasso ──

  void _startLasso(Offset position) {
    if (state!.lassoSelection != null) {
      final sel = state!.lassoSelection!;
      final dragBounds = sel.bounds.translate(sel.dragOffset.dx, sel.dragOffset.dy);
      // Wait, is it clicking inside the lasso to drag?
      if (dragBounds.contains(position)) return;
      applySelectionTransform(); // Bake if clicking outside
      state = state!.copyWith(clearLasso: true, lassoPath: []);
    }
    state = state!.copyWith(lassoPath: [position]);
  }

  void clearLassoPath() {
    if (state == null) return;
    if (state!.lassoSelection != null) applySelectionTransform();
    state = state!.copyWith(clearLasso: true, lassoPath: []);
  }

  /// Accept a locally-collected lasso path (from _LassoPathNotifier in the UI)
  /// and run selection — bypasses per-point Riverpod updates entirely.
  void commitLassoPath(List<Offset> path) {
    if (state == null) return;
    final s = state!;
    if (path.length < 3) {
      state = s.copyWith(lassoPath: [], clearLasso: true);
      return;
    }
    // Reuse _endLasso logic by temporarily setting the path
    state = s.copyWith(lassoPath: path);
    _endLasso();
  }

  void _continueLasso(Offset position) {
    if (state!.lassoPath.isEmpty) return;
    state = state!.copyWith(lassoPath: [...state!.lassoPath, position]);
  }

  void _endLasso() {
    if (state == null) return;
    final s = state!;
    if (s.lassoPath.length < 3) {
      state = s.copyWith(lassoPath: [], clearLasso: true);
      return;
    }

    final page = s.currentPage;
    if (page == null) return;

    // Build the lasso polygon for point-in-polygon testing
    final lassoPolygon = s.lassoPath;

    final selectedIds = <String>[];
    Rect? selectionBounds;

    for (final element in page.layers.content) {
      // Skip PDF images from lasso selection — they are only selectable via double-tap
      final isPdfImage = element.mapOrNull(
        image: (img) => img.data.assetPath.contains('.pdf_p'),
      ) ?? false;
      if (isPdfImage) continue;

      final elementBounds = _getElementBounds(element);
      if (elementBounds == null) continue;

      bool isSelected = false;

      // Strokes and shapes are tested against their ACTUAL geometry, not
      // the bounding box: a diagonal line's (or C-shaped stroke's) bbox
      // center/corners are mostly empty space, so the old center+corner
      // heuristic selected elements the lasso was nowhere near.
      if (element is StrokeElement) {
        for (final p in element.data.points) {
          if (_pointInPolygon(Offset(p.x, p.y), lassoPolygon)) {
            isSelected = true;
            break;
          }
        }
      } else if (element is ShapeElement) {
        outer:
        for (final edge in _shapeToSampledEdges(element.data, 8.0)) {
          for (final p in edge) {
            if (_pointInPolygon(Offset(p.x, p.y), lassoPolygon)) {
              isSelected = true;
              break outer;
            }
          }
        }
      } else {
        // Solid rectangular elements (text, image, math): center or any
        // corner inside the lasso counts.
        if (_pointInPolygon(elementBounds.center, lassoPolygon)) {
          isSelected = true;
        }
        if (!isSelected) {
          final corners = [elementBounds.topLeft, elementBounds.topRight, elementBounds.bottomLeft, elementBounds.bottomRight];
          for (final corner in corners) {
            if (_pointInPolygon(corner, lassoPolygon)) {
              isSelected = true;
              break;
            }
          }
        }
      }

      if (isSelected) {
        final id = element.map(
          stroke: (e) => e.id, text: (e) => e.id,
          image: (e) => e.id, shape: (e) => e.id,
          math: (e) => e.id,
        );
        selectedIds.add(id);
        selectionBounds = selectionBounds == null
            ? elementBounds
            : selectionBounds.expandToInclude(elementBounds);
      }
    }

    if (selectedIds.isEmpty || selectionBounds == null) {
      state = s.copyWith(lassoPath: [], clearLasso: true);
      return;
    }

    state = s.copyWith(
      lassoPath: [],
      lassoSelection: LassoSelection(selectedIds: selectedIds, bounds: selectionBounds),
    );
  }

  /// Ray casting point-in-polygon test
  bool _pointInPolygon(Offset point, List<Offset> polygon) {
    bool inside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].dy > point.dy) != (polygon[j].dy > point.dy) &&
          point.dx < (polygon[j].dx - polygon[i].dx) * (point.dy - polygon[i].dy) / (polygon[j].dy - polygon[i].dy) + polygon[i].dx) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  Rect? _getElementBounds(ContentElement element) {
    Rect getRotatedBounds(Rect rect, double rotation) {
      if (rotation == 0.0) return rect;
      final c = rect.center;
      final cosA = cos(rotation);
      final sinA = sin(rotation);
      Offset r(Offset p) {
        final dx = p.dx - c.dx;
        final dy = p.dy - c.dy;
        return Offset(c.dx + dx * cosA - dy * sinA, c.dy + dx * sinA + dy * cosA);
      }
      final pts = [r(rect.topLeft), r(rect.topRight), r(rect.bottomLeft), r(rect.bottomRight)];
      final xs = pts.map((p) => p.dx);
      final ys = pts.map((p) => p.dy);
      return Rect.fromLTRB(xs.reduce(min), ys.reduce(min), xs.reduce(max), ys.reduce(max));
    }

    return element.map(
      stroke: (e) {
        if (e.data.points.isEmpty) return null;
        final xs = e.data.points.map((p) => p.x);
        final ys = e.data.points.map((p) => p.y);
        final halfW = e.data.baseWidth / 2.0;
        return Rect.fromLTRB(xs.reduce(min) - halfW, ys.reduce(min) - halfW, xs.reduce(max) + halfW, ys.reduce(max) + halfW);
      },
      text: (e) => Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
      image: (e) {
        final rect = Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height);
        return getRotatedBounds(rect, e.data.rotation);
      },
      shape: (e) {
        final halfW = e.data.strokeWidth / 2.0;
        final baseRect = Rect.fromPoints(Offset(e.data.x1, e.data.y1), Offset(e.data.x2, e.data.y2)).inflate(halfW);
        return getRotatedBounds(baseRect, e.data.rotation);
      },
      math: (e) => Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
    );
  }

  void moveSelection(Offset delta) {
    if (state == null || state!.lassoSelection == null) return;
    state = state!.copyWith(
      lassoSelection: state!.lassoSelection!.copyWith(
        dragOffset: state!.lassoSelection!.dragOffset + delta,
      ),
    );
  }

  void resizeSelection(double scaleFactor) {
    if (state == null || state!.lassoSelection == null) return;
    final s = state!;
    final sel = s.lassoSelection!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);
    final center = sel.bounds.center;

    final updatedContent = page.layers.content.map((element) {
      final id = element.map(
        stroke: (e) => e.id, text: (e) => e.id,
        image: (e) => e.id, shape: (e) => e.id,
        math: (e) => e.id,
      );
      if (!sel.selectedIds.contains(id)) return element;
      return _scaleElement(element, center, scaleFactor);
    }).toList();

    final newBounds = Rect.fromCenter(
      center: center,
      width: sel.bounds.width * scaleFactor,
      height: sel.bounds.height * scaleFactor,
    );

    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: updatedContent),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    state = s.copyWith(
      pages: updatedPages, undoStack: undoStack, redoStack: [], isDirty: true,
      lassoSelection: LassoSelection(selectedIds: sel.selectedIds, bounds: newBounds),
    );
  }

  void rotateSelection(double angle) {
    if (state == null || state!.lassoSelection == null) return;
    state = state!.copyWith(
      lassoSelection: state!.lassoSelection!.copyWith(
        rotation: state!.lassoSelection!.rotation + angle,
      ),
    );
  }

  void scaleSelectionPreview(double scale) {
    if (state == null || state!.lassoSelection == null) return;
    state = state!.copyWith(
      lassoSelection: state!.lassoSelection!.copyWith(scale: scale),
    );
  }

  /// Apply the full transform (drag/rotation/scale) atomically. Used by
  /// the UI when committing a locally-tracked LassoTransformNotifier on
  /// pointer-up, so Riverpod fires a single state update per gesture
  /// instead of one per pointer-move.
  void commitSelectionTransform({
    required Offset dragOffset,
    required double rotation,
    required double scale,
  }) {
    if (state == null || state!.lassoSelection == null) return;
    // No-op tap on the bounds: avoid the state churn (a fresh
    // LassoSelection + CanvasState allocation that would tickle every
    // chrome consumer for nothing).
    if (dragOffset == Offset.zero && rotation == 0.0 && scale == 1.0) {
      return;
    }
    state = state!.copyWith(
      lassoSelection: state!.lassoSelection!.copyWith(
        dragOffset: dragOffset,
        rotation: rotation,
        scale: scale,
      ),
    );
  }

  void applySelectionTransform() {
    if (state == null || state!.lassoSelection == null) return;
    final s = state!;
    final sel = s.lassoSelection!;
    if (sel.rotation == 0.0 && sel.dragOffset == Offset.zero && sel.scale == 1.0) return;

    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);
    final center = sel.bounds.center;

    final updatedContent = page.layers.content.map((element) {
      final id = element.map(
        stroke: (e) => e.id, text: (e) => e.id,
        image: (e) => e.id, shape: (e) => e.id,
        math: (e) => e.id,
      );
      if (!sel.selectedIds.contains(id)) return element;
      var updated = element;
      if (sel.scale != 1.0) {
        updated = _scaleElement(updated, center, sel.scale);
      }
      if (sel.rotation != 0.0) {
        updated = _rotateElementAroundCenter(updated, center, sel.rotation);
      }
      if (sel.dragOffset != Offset.zero) {
        updated = _translateElement(updated, sel.dragOffset);
      }
      return updated;
    }).toList();

    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: updatedContent),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    // Recalculate bounds from actual transformed element positions
    Rect? newBounds;
    for (final element in updatedContent) {
      final id = element.map(
        stroke: (e) => e.id, text: (e) => e.id,
        image: (e) => e.id, shape: (e) => e.id,
        math: (e) => e.id,
      );
      if (!sel.selectedIds.contains(id)) continue;
      final eb = _getElementBounds(element);
      if (eb == null) continue;
      newBounds = newBounds == null ? eb : newBounds.expandToInclude(eb);
    }

    state = s.copyWith(
      pages: updatedPages, undoStack: undoStack, redoStack: [], isDirty: true,
      lassoSelection: LassoSelection(
        selectedIds: sel.selectedIds,
        bounds: newBounds ?? sel.bounds.translate(sel.dragOffset.dx, sel.dragOffset.dy),
      ),
    );
  }

  /// Mirror the current selection around its horizontal center axis (flip X).
  void flipSelectionHorizontal() => _flipSelection(horizontal: true);

  /// Mirror the current selection around its vertical center axis (flip Y).
  void flipSelectionVertical() => _flipSelection(horizontal: false);

  void _flipSelection({required bool horizontal}) {
    if (state == null || state!.lassoSelection == null) return;
    final s = state!;
    final sel = s.lassoSelection!;
    final page = s.currentPage;
    if (page == null || sel.selectedIds.isEmpty) return;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);

    // Bake any pending translate/scale/rotate first so the flip axis is the
    // *visual* center the user sees, not the original bounds center.
    if (sel.rotation != 0.0 || sel.dragOffset != Offset.zero || sel.scale != 1.0) {
      applySelectionTransform();
    }
    final postState = state!;
    final postSel = postState.lassoSelection!;
    final postPage = postState.currentPage!;
    final center = postSel.bounds.center;

    double reflectX(double x) => horizontal ? 2 * center.dx - x : x;
    double reflectY(double y) => horizontal ? y : 2 * center.dy - y;

    final updatedContent = postPage.layers.content.map((element) {
      final id = element.map(
        stroke: (e) => e.id, text: (e) => e.id,
        image: (e) => e.id, shape: (e) => e.id,
        math: (e) => e.id,
      );
      if (!postSel.selectedIds.contains(id)) return element;
      return element.map(
        stroke: (e) => ContentElement.stroke(
          id: e.id, zIndex: e.zIndex,
          data: StrokeData(
            points: e.data.points
                .map((p) => StrokePoint(
                      x: reflectX(p.x),
                      y: reflectY(p.y),
                      pressure: p.pressure,
                      tilt: p.tilt,
                      timestamp: p.timestamp,
                    ))
                .toList(),
            toolType: e.data.toolType, color: e.data.color,
            baseWidth: e.data.baseWidth, isHighlighter: e.data.isHighlighter,
            opacity: e.data.opacity, timestamp: e.data.timestamp,
          ),
        ),
        text: (e) => ContentElement.text(
          id: e.id, zIndex: e.zIndex,
          // copyWith preserves spans/fontFamily and every other field —
          // mirror only moves the box (reflect top-left by element size).
          data: e.data.copyWith(
            x: horizontal ? 2 * center.dx - e.data.x - e.data.width : e.data.x,
            y: horizontal ? e.data.y : 2 * center.dy - e.data.y - e.data.height,
          ),
        ),
        image: (e) => ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          // copyWith preserves flipHorizontal (and any future field) —
          // a from-scratch ImageData silently dropped it on every mirror.
          data: e.data.copyWith(
            x: horizontal ? 2 * center.dx - e.data.x - e.data.width : e.data.x,
            y: horizontal ? e.data.y : 2 * center.dy - e.data.y - e.data.height,
            // Mirror rotation so the image visually stays aligned.
            rotation: -e.data.rotation,
          ),
        ),
        // copyWith preserves isHighlighter (and any other untouched
        // field) — a from-scratch rebuild silently reset it to opaque.
        shape: (e) => ContentElement.shape(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(
            x1: reflectX(e.data.x1), y1: reflectY(e.data.y1),
            x2: reflectX(e.data.x2), y2: reflectY(e.data.y2),
            rotation: -e.data.rotation,
            vertices: _transformVertices(e.data.vertices,
                (p) => Offset(reflectX(p.dx), reflectY(p.dy))),
          ),
        ),
        math: (e) => ContentElement.math(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(
            x: horizontal ? 2 * center.dx - e.data.x - e.data.width : e.data.x,
            y: horizontal ? e.data.y : 2 * center.dy - e.data.y - e.data.height,
          ),
        ),
      );
    }).toList();

    final updatedPage = PageData(
      pageId: postPage.pageId, pageNumber: postPage.pageNumber,
      width: postPage.width, height: postPage.height,
      layers: RenderingLayers(background: postPage.layers.background, content: updatedContent),
      assetReferences: postPage.assetReferences,
      createdAt: postPage.createdAt, modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(postState.pages);
    updatedPages[fileName] = updatedPage;

    // Recompute selection bounds from mirrored elements.
    Rect? newBounds;
    for (final element in updatedContent) {
      final id = element.map(
        stroke: (e) => e.id, text: (e) => e.id,
        image: (e) => e.id, shape: (e) => e.id,
        math: (e) => e.id,
      );
      if (!postSel.selectedIds.contains(id)) continue;
      final eb = _getElementBounds(element);
      if (eb == null) continue;
      newBounds = newBounds == null ? eb : newBounds.expandToInclude(eb);
    }

    state = postState.copyWith(
      pages: updatedPages,
      undoStack: undoStack,
      redoStack: [],
      isDirty: true,
      lassoSelection: LassoSelection(
        selectedIds: postSel.selectedIds,
        bounds: newBounds ?? postSel.bounds,
      ),
    );
  }

  ContentElement _rotateElementAroundCenter(ContentElement element, Offset center, double angle) {
    Offset rotatePoint(double x, double y) {
      final cosA = cos(angle);
      final sinA = sin(angle);
      final dx = x - center.dx;
      final dy = y - center.dy;
      return Offset(center.dx + dx * cosA - dy * sinA, center.dy + dx * sinA + dy * cosA);
    }

    return element.map(
      stroke: (e) => ContentElement.stroke(
        id: e.id, zIndex: e.zIndex,
        data: StrokeData(
          points: e.data.points.map((p) {
            final rp = rotatePoint(p.x, p.y);
            return StrokePoint(x: rp.dx, y: rp.dy, pressure: p.pressure, tilt: p.tilt, timestamp: p.timestamp);
          }).toList(),
          toolType: e.data.toolType, color: e.data.color,
          baseWidth: e.data.baseWidth, isHighlighter: e.data.isHighlighter,
          opacity: e.data.opacity, timestamp: e.data.timestamp,
        ),
      ),
      text: (e) {
        final rp = rotatePoint(e.data.x, e.data.y);
        return ContentElement.text(
          id: e.id, zIndex: e.zIndex,
          // copyWith preserves spans/fontFamily; rotation only moves the box.
          data: e.data.copyWith(x: rp.dx, y: rp.dy),
        );
      },
      image: (e) {
        // Rotate only the element center around the selection center,
        // then translate the bounding box by the center offset.
        // The internal rotation is incremented to match the visual preview.
        final oldCx = e.data.x + e.data.width / 2;
        final oldCy = e.data.y + e.data.height / 2;
        final rCenter = rotatePoint(oldCx, oldCy);
        final dx = rCenter.dx - oldCx;
        final dy = rCenter.dy - oldCy;
        return ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          // copyWith preserves flipHorizontal (and any future field).
          data: e.data.copyWith(
            x: e.data.x + dx, y: e.data.y + dy,
            rotation: e.data.rotation + angle,
          ),
        );
      },
      shape: (e) {
        // Rotate only the element center around the selection center,
        // then translate the bounding box by the center offset.
        final oldCx = (e.data.x1 + e.data.x2) / 2;
        final oldCy = (e.data.y1 + e.data.y2) / 2;
        final rCenter = rotatePoint(oldCx, oldCy);
        final dx = rCenter.dx - oldCx;
        final dy = rCenter.dy - oldCy;
        // For vertex triangles, rotate each vertex around the new bbox
        // centre too — the bbox translation alone wouldn't carry the
        // shape's orientation through.
        final cosA = cos(angle);
        final sinA = sin(angle);
        final newCx = oldCx + dx;
        final newCy = oldCy + dy;
        final newVertices = _transformVertices(e.data.vertices, (p) {
          final ddx = p.dx + dx - newCx;
          final ddy = p.dy + dy - newCy;
          return Offset(newCx + ddx * cosA - ddy * sinA,
                        newCy + ddx * sinA + ddy * cosA);
        });
        return ContentElement.shape(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(
            x1: e.data.x1 + dx, y1: e.data.y1 + dy,
            x2: e.data.x2 + dx, y2: e.data.y2 + dy,
            rotation: e.data.rotation + angle,
            vertices: newVertices,
          ),
        );
      },
      math: (e) {
        final rp = rotatePoint(e.data.x, e.data.y);
        return ContentElement.math(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(x: rp.dx, y: rp.dy),
        );
      },
    );
  }

  void deleteSelection() {
    if (state == null || state!.lassoSelection == null) return;
    final s = state!;
    final sel = s.lassoSelection!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);

    final filteredContent = page.layers.content.where((element) {
      final id = element.map(
        stroke: (e) => e.id, text: (e) => e.id,
        image: (e) => e.id, shape: (e) => e.id,
        math: (e) => e.id,
      );
      return !sel.selectedIds.contains(id);
    }).toList();

    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: filteredContent),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    state = s.copyWith(
      pages: updatedPages, undoStack: undoStack, redoStack: [], isDirty: true,
      clearLasso: true, lassoPath: [],
    );
  }

  void clearSelection() {
    if (state == null) return;
    if (state!.lassoSelection != null) applySelectionTransform();
    state = state!.copyWith(clearLasso: true, lassoPath: [], selectedElementId: null, clearSelectedElement: true);
  }

  /// Change the color of all selected strokes/shapes/text.
  void changeSelectionColor(int newColor) {
    if (state == null || state!.lassoSelection == null) return;
    final s = state!;
    final sel = s.lassoSelection!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);

    final updatedContent = page.layers.content.map((element) {
      final id = element.map(
        stroke: (e) => e.id, text: (e) => e.id,
        image: (e) => e.id, shape: (e) => e.id,
        math: (e) => e.id,
      );
      if (!sel.selectedIds.contains(id)) return element;
      return element.map(
        stroke: (e) => e.copyWith(data: e.data.copyWith(color: newColor)),
        text: (e) => e.copyWith(data: e.data.copyWith(color: newColor)),
        image: (e) => e, // images don't have a stroke color
        shape: (e) => e.copyWith(data: e.data.copyWith(strokeColor: newColor)),
        math: (e) => e.copyWith(data: e.data.copyWith(color: newColor)),
      );
    }).toList();

    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: updatedContent),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    state = s.copyWith(
      pages: updatedPages, undoStack: undoStack, redoStack: [], isDirty: true,
    );
  }

  /// Change the stroke/shape width of everything in the current
  /// selection to an absolute value. Mirrors [changeSelectionColor], but
  /// a width control is a slider — it fires many times per drag — so
  /// only the first call of a gesture pushes an undo entry. The UI calls
  /// [endSelectionWidthEdit] on release so the next drag starts fresh.
  void changeSelectionStrokeWidth(double newWidth) {
    if (state == null || state!.lassoSelection == null) return;
    final s = state!;
    final sel = s.lassoSelection!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    var undoStack = s.undoStack;
    if (!_selectionWidthUndoPushed) {
      undoStack = _pushUndo(s, fileName, page);
      _selectionWidthUndoPushed = true;
    }

    final updatedContent = page.layers.content.map((element) {
      final id = element.map(
        stroke: (e) => e.id, text: (e) => e.id,
        image: (e) => e.id, shape: (e) => e.id,
        math: (e) => e.id,
      );
      if (!sel.selectedIds.contains(id)) return element;
      return element.map(
        stroke: (e) => e.copyWith(data: e.data.copyWith(baseWidth: newWidth)),
        text: (e) => e, // text has no stroke width
        image: (e) => e, // images don't have a stroke width
        shape: (e) => e.copyWith(data: e.data.copyWith(strokeWidth: newWidth)),
        math: (e) => e, // math has no stroke width
      );
    }).toList();

    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: updatedContent),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    state = s.copyWith(
      pages: updatedPages, undoStack: undoStack, redoStack: [], isDirty: true,
    );
  }

  /// Ends the current width-adjustment gesture so the next slider drag
  /// starts its own undo entry instead of continuing the previous one.
  void endSelectionWidthEdit() {
    _selectionWidthUndoPushed = false;
  }

  // ── Undo / Redo ──

  void undo() {
    if (state == null || state!.undoStack.isEmpty) return;
    final s = state!;
    final entry = s.undoStack.last;
    // Entry for a page no longer in the document (removed by a path that
    // didn't purge the stacks): drop it instead of restoring an orphan
    // PageData that has no document entry.
    if (!s.document.pages.any((p) => p.fileName == entry.pageFileName)) {
      state = s.copyWith(
          undoStack: List<UndoEntry>.from(s.undoStack)..removeLast());
      return;
    }
    final currentPage = s.pages[entry.pageFileName];

    final newUndo = List<UndoEntry>.from(s.undoStack)..removeLast();
    final newRedo = [...s.redoStack, if (currentPage != null) UndoEntry(entry.pageFileName, currentPage)];

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[entry.pageFileName] = entry.pageData;

    state = s.copyWith(pages: updatedPages, undoStack: newUndo, redoStack: newRedo, isDirty: true);
  }

  void redo() {
    if (state == null || state!.redoStack.isEmpty) return;
    final s = state!;
    final entry = s.redoStack.last;
    // Same orphan guard as undo().
    if (!s.document.pages.any((p) => p.fileName == entry.pageFileName)) {
      state = s.copyWith(
          redoStack: List<UndoEntry>.from(s.redoStack)..removeLast());
      return;
    }
    final currentPage = s.pages[entry.pageFileName];

    final newRedo = List<UndoEntry>.from(s.redoStack)..removeLast();
    final newUndo = [...s.undoStack, if (currentPage != null) UndoEntry(entry.pageFileName, currentPage)];

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[entry.pageFileName] = entry.pageData;

    state = s.copyWith(pages: updatedPages, undoStack: newUndo, redoStack: newRedo, isDirty: true);
  }

  bool get canUndo => state != null && state!.undoStack.isNotEmpty;
  bool get canRedo => state != null && state!.redoStack.isNotEmpty;

  // ── Page management ──

  void setActiveChapter(String? chapterId) {
    if (state == null) return;
    final s = state!;
    if (chapterId == null) {
      state = s.copyWith(clearActiveChapter: true);
      return;
    }
    // True orphan only: chapterId not present in metadata.chapters at all
    // (legacy pageId leak from a pre-cleanup migration). Selecting a ghost
    // chip would leave a phantom selection. Fall back to all-pages.
    //
    // An EMPTY chapter (exists in metadata, 0 pages) is a legitimate user
    // state — reachable by deleting all pages of a chapter via the page
    // manager's multi-select. Previously this branch also caught that case
    // and silently deselected the chip; the user couldn't enter their own
    // empty chapter to add fresh pages to it.
    final chapterExists = s.metadata.chapters.any((c) => c.id == chapterId);
    if (!chapterExists) {
      state = s.copyWith(clearActiveChapter: true, clearLasso: true, lassoPath: []);
      return;
    }
    final firstIdx = s.document.pages.indexWhere((p) => p.chapterId == chapterId);
    state = s.copyWith(
      activeChapterId: chapterId,
      // If the chapter has no pages, leave currentPageIndex alone — the page
      // strip will show "0/0" and the user can add pages from the menu.
      currentPageIndex: firstIdx >= 0 ? firstIdx : s.currentPageIndex,
      clearLasso: true,
      lassoPath: [],
    );
  }

  /// Navigate to [index]. By default the user's zoom/pan is preserved so
  /// arrow-button and grid taps don't rip the viewport out from under them.
  /// Pass [resetViewport]=true for gestures where a fresh view is wanted
  /// (e.g. swipe-to-turn-page).
  void goToPage(int index, {bool resetViewport = false}) {
    if (state == null || index < 0 || index >= state!.pageCount) return;
    final s = state!;
    // Record the index we're leaving so the page nav bar can offer a
    // one-tap jump back. Only update if the user is actually changing
    // pages — re-navigating to the current page (e.g. through "Vai a
    // pagina N") shouldn't trash the prior memory.
    final prev = (s.currentPageIndex != index) ? s.currentPageIndex : s.previousPageIndex;
    if (resetViewport) {
      state = s.copyWith(
        currentPageIndex: index,
        previousPageIndex: prev,
        activeStroke: [],
        clearLasso: true,
        lassoPath: [],
        clearSelectedElement: true,
        zoom: 2.0,
        panOffset: _centeredPanOffset(2.0),
      );
    } else {
      state = s.copyWith(
        currentPageIndex: index,
        previousPageIndex: prev,
        activeStroke: [],
        clearLasso: true,
        lassoPath: [],
        clearSelectedElement: true,
      );
    }
    _ensureAssetsForCurrentWindow();
  }

  void nextPage({bool resetViewport = false}) {
    if (state == null) return;
    final s = state!;
    final filtered = s.filteredPageIndices;
    final pos = filtered.indexOf(s.currentPageIndex);
    if (pos >= 0 && pos + 1 < filtered.length) {
      goToPage(filtered[pos + 1], resetViewport: resetViewport);
    }
  }

  void prevPage({bool resetViewport = false}) {
    if (state == null) return;
    final s = state!;
    final filtered = s.filteredPageIndices;
    final pos = filtered.indexOf(s.currentPageIndex);
    if (pos > 0) {
      goToPage(filtered[pos - 1], resetViewport: resetViewport);
    }
  }

  void addPage() {
    if (state == null) return;
    final s = state!;
    const uuid = Uuid();
    final pageId = uuid.v4();
    final now = DateTime.now();
    final pageNum = s.pageCount + 1;
    final fileName = _nextPageFileName(s);

    final currentBg = s.currentPage?.layers.background;
    final bgType = currentBg?.type ?? 'blank';
    final lineSpacing = currentBg?.lineSpacing ?? 30.0;
    // Inherit the current page's size so scratch (infinite) notebooks get
    // another big sheet instead of a stray A4 page.
    final pageW = s.currentPage?.width ?? AppConfig.defaultPageWidth;
    final pageH = s.currentPage?.height ?? AppConfig.defaultPageHeight;

    final newPage = PageData(
      pageId: pageId, pageNumber: pageNum,
      width: pageW, height: pageH,
      layers: RenderingLayers(
        background: BackgroundLayer(type: bgType, lineSpacing: lineSpacing),
        content: const [],
      ),
      createdAt: now, modifiedAt: now,
    );

    // Auto-assign chapter if one is active
    final newEntry = PageEntry(
      pageId: pageId, pageNumber: pageNum, fileName: fileName,
      width: pageW, height: pageH,
      lastModified: now, chapterId: s.activeChapterId,
    );

    // Insert after current page position (not always at end)
    final insertIndex = s.currentPageIndex + 1;
    final pageList = List<PageEntry>.from(s.document.pages)..insert(insertIndex, newEntry);
    // Renumber: inserting mid-document would otherwise leave pageNumber
    // out of sync with position (search results sort on it).
    for (int i = 0; i < pageList.length; i++) {
      pageList[i] = pageList[i].copyWith(pageNumber: i + 1);
    }

    final updatedDoc = DocumentStructure(
      notebookId: s.document.notebookId,
      formatVersion: s.document.formatVersion,
      pages: pageList,
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = newPage;

    state = s.copyWith(
      metadata: s.metadata.copyWith(pageCount: pageNum, modifiedAt: now),
      document: updatedDoc,
      pages: updatedPages,
      currentPageIndex: insertIndex,
      zoom: 2.0,
      panOffset: _centeredPanOffset(2.0),
      isDirty: true,
    );
  }

  /// Insert a new blank page at a specific position (0-based index).
  void insertPageAt(int index) {
    if (state == null) return;
    final s = state!;
    const uuid = Uuid();
    final pageId = uuid.v4();
    final now = DateTime.now();
    final pageNum = s.pageCount + 1;
    final fileName = _nextPageFileName(s);

    final currentBg = s.currentPage?.layers.background;
    final bgType = currentBg?.type ?? 'blank';
    final lineSpacing = currentBg?.lineSpacing ?? 30.0;

    final newPage = PageData(
      pageId: pageId, pageNumber: pageNum,
      width: AppConfig.defaultPageWidth, height: AppConfig.defaultPageHeight,
      layers: RenderingLayers(
        background: BackgroundLayer(type: bgType, lineSpacing: lineSpacing),
        content: const [],
      ),
      createdAt: now, modifiedAt: now,
    );

    final insertIdx = index.clamp(0, s.document.pages.length);

    // Inherit chapter from the page before the insert position
    String? chapterId;
    if (insertIdx > 0) {
      chapterId = s.document.pages[insertIdx - 1].chapterId;
    } else if (s.document.pages.isNotEmpty) {
      chapterId = s.document.pages[0].chapterId;
    }

    final newEntry = PageEntry(
      pageId: pageId, pageNumber: pageNum, fileName: fileName,
      lastModified: now, chapterId: chapterId,
    );

    final pageList = List<PageEntry>.from(s.document.pages)..insert(insertIdx, newEntry);
    // Same renumber as addPage: keep pageNumber == position + 1.
    for (int i = 0; i < pageList.length; i++) {
      pageList[i] = pageList[i].copyWith(pageNumber: i + 1);
    }
    final updatedDoc = s.document.copyWith(pages: pageList);
    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = newPage;

    state = s.copyWith(
      metadata: s.metadata.copyWith(pageCount: pageNum, modifiedAt: now),
      document: updatedDoc,
      pages: updatedPages,
      currentPageIndex: insertIdx,
      zoom: 2.0,
      panOffset: _centeredPanOffset(2.0),
      isDirty: true,
    );
  }

  /// Paste pages from [PageClipboard] into this notebook at [insertDocIndex].
  ///
  /// Each page gets a fresh [pageId] and [fileName] so it doesn't collide with
  /// any existing page.  The [chapterId] from the clipboard entry is preserved
  /// unless the target notebook has no chapters, in which case it is cleared.
  void pastePages({
    required List<PageData> pages,
    required List<PageEntry> entries,
    Map<String, Uint8List> assets = const {},
    int? insertDocIndex, // null → append at end
  }) {
    if (state == null) return;
    final s = state!;
    if (pages.isEmpty) return;

    // Materialize clipboard-carried assets this notebook doesn't have
    // (cross-notebook paste). Without the bytes, the pasted pages'
    // image/PDF elements would reference asset ids that exist only in
    // the SOURCE notebook — a permanently broken reference.
    var newAssetBytes = s.assetBytes;
    if (assets.isNotEmpty) {
      final merged = Map<String, Uint8List>.from(s.assetBytes);
      var changed = false;
      for (final entry in assets.entries) {
        if (!merged.containsKey(entry.key)) {
          merged[entry.key] = entry.value;
          (_assetsByLength[entry.value.length] ??= []).add(entry.key);
          _markAssetDirty(entry.key);
          changed = true;
        }
      }
      if (changed) newAssetBytes = merged;
    }

    const uuid = Uuid();
    final now = DateTime.now();
    final existingChapterIds = s.metadata.chapters.map((c) => c.id).toSet();

    final insertIdx = (insertDocIndex ?? s.document.pages.length)
        .clamp(0, s.document.pages.length);

    final newEntries = <PageEntry>[];
    final newPagesMap = Map<String, PageData>.from(s.pages);

    for (int i = 0; i < pages.length; i++) {
      final pageId = uuid.v4();
      final fileName = _nextPageFileName(
        s.copyWith(
          document: s.document.copyWith(
            pages: [
              ...s.document.pages,
              ...newEntries,
            ],
          ),
        ),
      );
      // Only keep chapter id if the chapter still exists in this notebook
      final chapterId = existingChapterIds.contains(entries[i].chapterId)
          ? entries[i].chapterId
          : null;
      final newEntry = PageEntry(
        pageId: pageId,
        pageNumber: 0, // renumbered below
        fileName: fileName,
        lastModified: now,
        chapterId: chapterId,
      );
      newEntries.add(newEntry);
      newPagesMap[fileName] = pages[i].copyWith(pageId: pageId, modifiedAt: now);
    }

    final allEntries = List<PageEntry>.from(s.document.pages)
      ..insertAll(insertIdx, newEntries);
    // Renumber
    for (int i = 0; i < allEntries.length; i++) {
      allEntries[i] = allEntries[i].copyWith(pageNumber: i + 1);
    }

    final updatedDoc = s.document.copyWith(pages: allEntries);

    state = s.copyWith(
      document: updatedDoc,
      pages: newPagesMap,
      assetBytes: newAssetBytes,
      currentPageIndex: insertIdx,
      metadata: s.metadata.copyWith(
        pageCount: allEntries.length,
        modifiedAt: now,
      ),
      isDirty: true,
    );
  }

  /// Move a page to a different chapter.
  void movePageToChapter(int pageIndex, String? chapterId) {
    assignPageToChapter(pageIndex, chapterId);
  }

  void addChapter(String title) {
    if (state == null) return;
    final s = state!;
    final now = DateTime.now();
    final chapterId = const Uuid().v4();
    const uuid = Uuid();

    // Create a new blank page for the chapter instead of reassigning the current page
    final pageId = uuid.v4();
    final pageNum = s.pageCount + 1;
    final fileName = _nextPageFileName(s);

    final currentBg = s.currentPage?.layers.background;
    final bgType = currentBg?.type ?? 'blank';
    final lineSpacing = currentBg?.lineSpacing ?? 30.0;
    // Inherit the current page's size (scratch chapters get big sheets).
    final pageW = s.currentPage?.width ?? AppConfig.defaultPageWidth;
    final pageH = s.currentPage?.height ?? AppConfig.defaultPageHeight;

    final newPage = PageData(
      pageId: pageId, pageNumber: pageNum,
      width: pageW, height: pageH,
      layers: RenderingLayers(
        background: BackgroundLayer(type: bgType, lineSpacing: lineSpacing),
        content: const [],
      ),
      createdAt: now, modifiedAt: now,
    );

    final newEntry = PageEntry(
      pageId: pageId, pageNumber: pageNum, fileName: fileName,
      width: pageW, height: pageH,
      lastModified: now, chapterId: chapterId,
    );

    final chapter = Chapter(id: chapterId, title: title, pageIds: [pageId]);

    // Insert the new page after current position
    final insertIndex = s.currentPageIndex + 1;
    final pageList = List<PageEntry>.from(s.document.pages)..insert(insertIndex, newEntry);
    final updatedDoc = s.document.copyWith(pages: pageList);

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = newPage;

    state = s.copyWith(
      metadata: s.metadata.copyWith(
        chapters: [...s.metadata.chapters, chapter],
        pageCount: pageNum,
        modifiedAt: now,
      ),
      document: updatedDoc,
      pages: updatedPages,
      currentPageIndex: insertIndex,
      activeChapterId: chapterId,
      zoom: 2.0,
      panOffset: _centeredPanOffset(2.0),
      isDirty: true,
    );
  }

  void renameChapter(String chapterId, String title) {
    if (state == null) return;
    final s = state!;
    final chapters = s.metadata.chapters.map((c) => c.id == chapterId ? c.copyWith(title: title) : c).toList();
    state = s.copyWith(
      metadata: s.metadata.copyWith(chapters: chapters, modifiedAt: DateTime.now()),
      isDirty: true,
    );
  }

  void reorderChapters(int oldIndex, int newIndex) {
    if (state == null) return;
    final s = state!;
    final chapters = List<Chapter>.from(s.metadata.chapters);
    if (oldIndex < 0 || oldIndex >= chapters.length) return;
    if (newIndex < 0 || newIndex >= chapters.length) return;
    final item = chapters.removeAt(oldIndex);
    chapters.insert(newIndex, item);
    state = s.copyWith(
      metadata: s.metadata.copyWith(chapters: chapters, modifiedAt: DateTime.now()),
      isDirty: true,
    );
  }

  void deleteChapter(String chapterId) {
    if (state == null) return;
    final s = state!;
    final chapters = s.metadata.chapters.where((c) => c.id != chapterId).toList();
    // Pages remain, but chapterId is cleared.
    final pages = s.document.pages.map((p) => p.chapterId == chapterId ? p.copyWith(chapterId: null) : p).toList();
    final document = s.document.copyWith(pages: pages);
    // If deleted chapter was the active filter, clear the filter
    final clearActiveChapter = s.activeChapterId == chapterId;
    state = s.copyWith(
      metadata: s.metadata.copyWith(chapters: chapters, modifiedAt: DateTime.now()),
      document: document,
      isDirty: true,
      clearActiveChapter: clearActiveChapter,
    );
  }

  void assignPageToChapter(int pageIndex, String? chapterId) {
    if (state == null) return;
    final s = state!;
    if (pageIndex < 0 || pageIndex >= s.document.pages.length) return;
    final pages = List<PageEntry>.from(s.document.pages);
    pages[pageIndex] = pages[pageIndex].copyWith(chapterId: chapterId);
    final document = s.document.copyWith(pages: pages);
    state = s.copyWith(document: document, isDirty: true);
  }

  // ── Zoom & Pan ──

  /// Mark "user is currently dragging/zooming". The pull tick consults
  /// [_isInteractingRecent] and skips its network round-trip until the
  /// user stops moving — keeps response-handling microtasks out of the
  /// pan event loop.
  void _bumpInteract() {
    _lastInteractAt = DateTime.now();
  }

  void setZoom(double zoom) {
    if (state == null) return;
    _bumpInteract();
    state = state!.copyWith(zoom: zoom.clamp(0.25, 5.0));
  }

  void setPanOffset(Offset offset) {
    if (state == null) return;
    _bumpInteract();
    state = state!.copyWith(panOffset: offset);
  }

  /// Set zoom and pan in a single state update to avoid intermediate render frames.
  void setZoomAndPan(double zoom, Offset pan) {
    if (state == null) return;
    _bumpInteract();
    state = state!.copyWith(zoom: zoom.clamp(0.25, 5.0), panOffset: pan);
  }

  /// Last laid-out canvas viewport size (see [setViewportSize]) — needed by
  /// the UI to reason about what's on screen (back-to-content pill).
  Size? get viewportSize => _viewportSize;

  // Memo for [currentPageContentBounds]: the pill visibility check runs on
  // every pan frame, and a big imported page can carry thousands of strokes
  // (tens of thousands of points) — recomputing the union each frame would
  // dwarf the paint cost. PageData is immutable, so identity is a safe key.
  PageData? _contentBoundsPage;
  Rect? _contentBoundsCache;

  /// Bounding box (page units) of everything on the current page, or null
  /// when the page is empty. Drives the scratch "torna al contenuto" pill.
  Rect? currentPageContentBounds() {
    final page = state?.currentPage;
    if (page == null || page.layers.content.isEmpty) return null;
    if (identical(page, _contentBoundsPage)) return _contentBoundsCache;
    Rect? acc;
    for (final el in page.layers.content) {
      final b = _elementBounds(el);
      if (b == Rect.zero) continue;
      acc = acc == null ? b : acc.expandToInclude(b);
    }
    _contentBoundsPage = page;
    _contentBoundsCache = acc;
    return acc;
  }

  /// Re-frame the viewport on the page content (scratch mode): zoom to fit
  /// the content bounding box with a margin, centred. Empty page → back to
  /// the sheet centre at 1:1. No-op before the first layout.
  void fitToContent({double marginPx = 60}) {
    final s = state;
    final vp = _viewportSize;
    if (s == null || vp == null || !s.isScratch) return;
    final bbox = currentPageContentBounds();
    if (bbox == null) {
      _bumpInteract();
      state = s.copyWith(zoom: 1.0, panOffset: _scratchCenterPan(1.0));
      return;
    }
    // Scratch transform: screen = panOffset + P × zoom (base scale 1).
    final zoomX = (vp.width - marginPx * 2) / max(bbox.width, 1.0);
    final zoomY = (vp.height - marginPx * 2) / max(bbox.height, 1.0);
    // Cap at 1.25× so a tiny doodle doesn't blow up to poster size.
    final zoom = min(zoomX, zoomY).clamp(0.25, 1.25).toDouble();
    final pan = Offset(
      vp.width / 2 - bbox.center.dx * zoom,
      vp.height / 2 - bbox.center.dy * zoom,
    );
    _bumpInteract();
    state = s.copyWith(zoom: zoom, panOffset: pan);
  }

  // ── Text ──

  /// Measure the laid-out height of a text block so new/edited elements
  /// fit their content instead of clipping at the legacy fixed 50 px.
  static double _measureTextHeight(
    String content,
    List<TextSpanData> spans,
    double baseFontSize,
    double width,
  ) {
    final children = <TextSpan>[];
    if (spans.isEmpty) {
      children.add(TextSpan(
          text: content, style: TextStyle(fontSize: baseFontSize)));
    } else {
      for (final sp in spans) {
        children.add(TextSpan(
          text: sp.text,
          style: TextStyle(
            fontSize: sp.fontSize ?? baseFontSize,
            fontFamily: sp.fontFamily,
            fontWeight: sp.bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: sp.italic ? FontStyle.italic : FontStyle.normal,
          ),
        ));
      }
    }
    final tp = TextPainter(
      text: TextSpan(children: children),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: width);
    final h = tp.height + 8; // breathing room for descenders
    tp.dispose();
    return h.clamp(30.0, 2000.0);
  }

  void addTextElement(
    Offset position,
    String content, {
    double fontSize = 16,
    List<TextSpanData> spans = const [],
    int? color,
    String alignment = 'left',
    double width = 300,
  }) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);

    final newElement = ContentElement.text(
      id: const Uuid().v4(),
      zIndex: _nextZIndex(page),
      data: TextData(
        x: position.dx, y: position.dy,
        width: width,
        height: _measureTextHeight(content, spans, fontSize, width),
        content: content,
        spans: spans,
        fontSize: fontSize,
        color: color ?? s.toolSettings.color,
        alignment: alignment,
      ),
    );

    final updatedPage = _pageWithNewElement(page, newElement);
    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    state = s.copyWith(pages: updatedPages, undoStack: undoStack, redoStack: [], isDirty: true);
  }

  /// Paste a parsed Markdown/LaTeX document ([parsePastedRich] output) as a
  /// vertical stack of elements — styled text runs + typeset-math blocks —
  /// in a SINGLE undo step, anchored at [anchor] (viewport centre) and
  /// clamped within the page. Math blocks are pre-rasterized (async) to get
  /// their intrinsic typeset size. The inserted element(s) are selected so
  /// the user can immediately move them.
  Future<void> pasteRichBlocks(
    List<PastedBlock> blocks,
    Offset anchor, {
    int? color,
    double maxWidth = 360,
    double pixelRatio = 3.0,
  }) async {
    if (state == null || blocks.isEmpty) return;
    var s = state!;
    var page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final baseColor = color ?? 0xFF000000;
    final colWidth = maxWidth.clamp(40.0, max(40.0, page.width - 24)).toDouble();
    const gap = 10.0;

    // Pre-measure (math raster is async) so the y-cursor is exact.
    final built = <ContentElement>[];
    final x = anchor.dx;
    var y = anchor.dy;
    var z = _nextZIndex(page);
    for (final b in blocks) {
      if (b is PastedTextBlock) {
        if (b.content.trim().isEmpty) continue;
        final h = _measureTextHeight(b.content, b.spans, b.fontSize, colWidth);
        built.add(ContentElement.text(
          id: const Uuid().v4(),
          zIndex: z++,
          data: TextData(
            x: x, y: y, width: colWidth, height: h,
            content: b.content, spans: b.spans,
            fontSize: b.fontSize, color: baseColor, alignment: b.alignment,
          ),
        ));
        y += h + gap;
      } else if (b is PastedMathBlock) {
        if (b.latex.trim().isEmpty) continue;
        final fontSize = b.display ? 26.0 : 20.0;
        final size = await measureMath(b.latex,
            colorArgb: baseColor, fontSize: fontSize, displayMode: b.display,
            pixelRatio: pixelRatio);
        final w = (size?.width ??
                (b.latex.length * fontSize * 0.5).clamp(20.0, colWidth))
            .toDouble();
        final h = (size?.height ?? fontSize * 1.6).toDouble();
        built.add(ContentElement.math(
          id: const Uuid().v4(),
          zIndex: z++,
          data: MathData(
            x: x, y: y, width: w, height: h, latex: b.latex,
            displayMode: b.display, color: baseColor, fontSize: fontSize,
          ),
        ));
        y += h + gap;
      }
    }
    if (built.isEmpty) return;

    // measureMath awaited — re-read state and bail if it changed underfoot.
    if (_disposed) return;
    s = state!;
    // Re-read the ORIGINAL page by its fileName, not currentPage: if the
    // user switched page during the (slow) math rasterization, committing
    // currentPage's data under the old key would clobber the old page.
    page = s.pages[fileName];
    if (page == null) return;

    // If the column overflows the page bottom, shift the whole stack up to
    // fit (best-effort; very tall stacks just start near the top margin).
    final totalH = y - anchor.dy;
    var dy = 0.0;
    if (anchor.dy + totalH > page.height - 12) {
      dy = page.height - 12 - totalH - anchor.dy;
      if (anchor.dy + dy < 12) dy = 12 - anchor.dy;
    }
    final placed = dy == 0
        ? built
        : built.map((e) => _translateElement(e, Offset(0, dy))).toList();

    final undoStack = _pushUndo(s, fileName, page);
    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(
          background: page.layers.background,
          content: [...page.layers.content, ...placed]),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );
    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    final ids = placed
        .map((e) => e.map(
            stroke: (x) => x.id, text: (x) => x.id, image: (x) => x.id,
            shape: (x) => x.id, math: (x) => x.id))
        .toList();

    if (ids.length == 1) {
      state = s.copyWith(
        pages: updatedPages, undoStack: undoStack, redoStack: [], isDirty: true,
        selectedElementId: ids.first, clearLasso: true, lassoPath: [],
      );
    } else {
      var bounds = _elementBounds(placed.first);
      for (final e in placed.skip(1)) {
        bounds = bounds.expandToInclude(_elementBounds(e));
      }
      state = s.copyWith(
        pages: updatedPages, undoStack: undoStack, redoStack: [], isDirty: true,
        lassoSelection: LassoSelection(selectedIds: ids, bounds: bounds),
        clearSelectedElement: true, lassoPath: [],
      );
    }
  }

  /// Replace content/style of an existing TextElement (rich editor's
  /// "Modifica testo"). Keeps position and width; height re-measured to
  /// fit the new content. No-op when the id isn't on the current page.
  void updateTextElement(
    String elementId, {
    required String content,
    required List<TextSpanData> spans,
    required double fontSize,
    required int color,
    required String alignment,
  }) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final idx = page.layers.content.indexWhere(
        (e) => e is TextElement && e.id == elementId);
    if (idx < 0) return;
    final old = page.layers.content[idx] as TextElement;

    final undoStack = _pushUndo(s, fileName, page);
    final newData = old.data.copyWith(
      content: content,
      spans: spans,
      fontSize: fontSize,
      color: color,
      alignment: alignment,
      // Element-level bold/italic are legacy whole-block flags; the
      // editor baked them into spans on load, so clear them here.
      bold: false,
      italic: false,
      // Auto-fit the box to the new content, but keep a height the user had
      // previously extended past the content (a fixed/taller frame) so editing
      // text doesn't collapse it back to hugging the text.
      height: () {
        final measured =
            _measureTextHeight(content, spans, fontSize, old.data.width);
        final oldMeasured = _measureTextHeight(
            old.data.content, old.data.spans, old.data.fontSize, old.data.width);
        final wasExtended = old.data.height > oldMeasured + 1.0;
        return wasExtended ? max(old.data.height, measured) : measured;
      }(),
    );
    final newContent = List<ContentElement>.from(page.layers.content);
    newContent[idx] = old.copyWith(data: newData);

    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(
          background: page.layers.background, content: newContent),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );
    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    state = s.copyWith(
        pages: updatedPages, undoStack: undoStack, redoStack: [], isDirty: true);
  }

  // ── Helpers ──

  /// Push an undo entry. Cap depth at 30 (was 50) — for a typical
  /// 200-stroke page that drops the upper-bound resident memory of
  /// the undo stack from ~25 MB to ~15 MB without practically reducing
  /// reachable history (very few people use undo more than ~20 steps
  /// back on a single page). Combined with the chrome's switch from
  /// undoStack/redoStack refs to canUndo/canRedo booleans (perf_state
  /// 2.8) the per-stroke chrome rebuild churn is also gone.
  static const int _undoStackCap = 30;
  List<UndoEntry> _pushUndo(CanvasState s, String fileName, PageData page) {
    final source = s.undoStack;
    // Build the new list at the right capacity: drop the oldest if we'd
    // exceed the cap, otherwise just append. Using sublist + add avoids
    // the O(N) removeAt(0) the previous code paid on every push past
    // 50 entries.
    final List<UndoEntry> stack;
    if (source.length >= _undoStackCap) {
      stack = source.sublist(source.length - _undoStackCap + 1)
        ..add(UndoEntry(fileName, page));
    } else {
      stack = [...source, UndoEntry(fileName, page)];
    }
    return stack;
  }

  int _nextZIndex(PageData page) {
    int maxZ = -1;
    for (final e in page.layers.content) {
      final z = e.map(stroke: (s) => s.zIndex, text: (t) => t.zIndex, image: (i) => i.zIndex, shape: (s) => s.zIndex, math: (m) => m.zIndex);
      if (z > maxZ) maxZ = z;
    }
    return maxZ + 1;
  }

  PageData _pageWithNewElement(PageData page, ContentElement element) {
    return PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(
        background: page.layers.background,
        content: [...page.layers.content, element],
      ),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );
  }

  ContentElement _translateElement(ContentElement element, Offset offset) {
    return element.map(
      stroke: (e) => ContentElement.stroke(
        id: e.id, zIndex: e.zIndex,
        data: StrokeData(
          points: e.data.points.map((p) => StrokePoint(
            x: p.x + offset.dx, y: p.y + offset.dy,
            pressure: p.pressure, tilt: p.tilt, timestamp: p.timestamp,
          )).toList(),
          toolType: e.data.toolType, color: e.data.color,
          baseWidth: e.data.baseWidth, isHighlighter: e.data.isHighlighter,
          opacity: e.data.opacity, timestamp: e.data.timestamp,
        ),
      ),
      // copyWith preserves spans/fontFamily/flipHorizontal — a from-scratch
      // rebuild dropped them on every move (and powers paste/duplicate).
      text: (e) => ContentElement.text(
        id: e.id, zIndex: e.zIndex,
        data: e.data.copyWith(
          x: e.data.x + offset.dx, y: e.data.y + offset.dy,
        ),
      ),
      image: (e) => ContentElement.image(
        id: e.id, zIndex: e.zIndex,
        data: e.data.copyWith(
          x: e.data.x + offset.dx, y: e.data.y + offset.dy,
        ),
      ),
      // copyWith preserves isHighlighter (and any other untouched field)
      // — a from-scratch rebuild silently reset it to opaque on every move.
      shape: (e) => ContentElement.shape(
        id: e.id, zIndex: e.zIndex,
        data: e.data.copyWith(
          x1: e.data.x1 + offset.dx, y1: e.data.y1 + offset.dy,
          x2: e.data.x2 + offset.dx, y2: e.data.y2 + offset.dy,
          vertices: _transformVertices(
              e.data.vertices, (p) => p + offset),
        ),
      ),
      math: (e) => ContentElement.math(
        id: e.id, zIndex: e.zIndex,
        data: e.data.copyWith(
          x: e.data.x + offset.dx, y: e.data.y + offset.dy,
        ),
      ),
    );
  }

  Rect _elementBounds(ContentElement element) {
    return element.map(
      stroke: (e) {
        if (e.data.points.isEmpty) return Rect.zero;
        double mnX = e.data.points.first.x, mxX = mnX, mnY = e.data.points.first.y, mxY = mnY;
        for (final p in e.data.points) {
          if (p.x < mnX) mnX = p.x; if (p.x > mxX) mxX = p.x;
          if (p.y < mnY) mnY = p.y; if (p.y > mxY) mxY = p.y;
        }
        return Rect.fromLTRB(mnX, mnY, mxX, mxY);
      },
      text: (e) => Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
      image: (e) => Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
      shape: (e) => Rect.fromPoints(Offset(e.data.x1, e.data.y1), Offset(e.data.x2, e.data.y2)),
      math: (e) => Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
    );
  }

  ContentElement _scaleElement(ContentElement element, Offset center, double scale) {
    return element.map(
      stroke: (e) => ContentElement.stroke(
        id: e.id, zIndex: e.zIndex,
        data: StrokeData(
          points: e.data.points.map((p) => StrokePoint(
            x: center.dx + (p.x - center.dx) * scale,
            y: center.dy + (p.y - center.dy) * scale,
            pressure: p.pressure, tilt: p.tilt, timestamp: p.timestamp,
          )).toList(),
          toolType: e.data.toolType, color: e.data.color,
          baseWidth: e.data.baseWidth * scale, isHighlighter: e.data.isHighlighter,
          opacity: e.data.opacity, timestamp: e.data.timestamp,
        ),
      ),
      // copyWith preserves spans/fontFamily; scale also multiplies the
      // element fontSize AND every per-span fontSize override so multi-size
      // rich text scales uniformly instead of collapsing overridden runs.
      text: (e) => ContentElement.text(
        id: e.id, zIndex: e.zIndex,
        data: e.data.copyWith(
          x: center.dx + (e.data.x - center.dx) * scale,
          y: center.dy + (e.data.y - center.dy) * scale,
          width: e.data.width * scale, height: e.data.height * scale,
          fontSize: e.data.fontSize * scale,
          spans: e.data.spans
              .map((sp) => sp.fontSize == null
                  ? sp
                  : sp.copyWith(fontSize: sp.fontSize! * scale))
              .toList(),
        ),
      ),
      image: (e) => ContentElement.image(
        id: e.id, zIndex: e.zIndex,
        data: e.data.copyWith(
          x: center.dx + (e.data.x - center.dx) * scale,
          y: center.dy + (e.data.y - center.dy) * scale,
          width: e.data.width * scale, height: e.data.height * scale,
        ),
      ),
      shape: (e) => ContentElement.shape(
        id: e.id, zIndex: e.zIndex,
        data: e.data.copyWith(
          x1: center.dx + (e.data.x1 - center.dx) * scale,
          y1: center.dy + (e.data.y1 - center.dy) * scale,
          x2: center.dx + (e.data.x2 - center.dx) * scale,
          y2: center.dy + (e.data.y2 - center.dy) * scale,
          strokeWidth: e.data.strokeWidth * scale,
          vertices: _transformVertices(e.data.vertices,
              (p) => Offset(
                  center.dx + (p.dx - center.dx) * scale,
                  center.dy + (p.dy - center.dy) * scale)),
        ),
      ),
      math: (e) => ContentElement.math(
        id: e.id, zIndex: e.zIndex,
        data: e.data.copyWith(
          x: center.dx + (e.data.x - center.dx) * scale,
          y: center.dy + (e.data.y - center.dy) * scale,
          width: e.data.width * scale, height: e.data.height * scale,
          fontSize: e.data.fontSize * scale,
        ),
      ),
    );
  }

  // ── Element selection & transform ──

  void selectElement(String elementId) {
    if (state == null) return;
    if (state!.lassoSelection != null) applySelectionTransform();
    state = state!.copyWith(selectedElementId: elementId, clearLasso: true, lassoPath: []);
  }

  void deselectElement() {
    if (state == null) return;
    state = state!.copyWith(clearSelectedElement: true);
  }

  void moveElement(String elementId, Offset delta) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    // Push undo only on the first move (when not yet dirty from a drag)
    // This avoids filling the undo stack with per-frame entries
    final undoStack = s.undoStack;

    final updatedContent = page.layers.content.map((element) {
      final id = element.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      if (id != elementId) return element;
      return _translateElement(element, delta);
    }).toList();

    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: updatedContent),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;
    state = s.copyWith(pages: updatedPages, undoStack: undoStack, isDirty: true);
  }

  /// Call this before starting a drag to push undo state once
  void startDragElement(String elementId) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);
    state = s.copyWith(undoStack: undoStack, redoStack: []);
  }

  /// Smart resize for a TEXT element (GoodNotes/Keynote semantics).
  ///
  /// - Side handles → pass [width] only: re-wrap to the new width and
  ///   auto-fit height. fontSize untouched.
  /// - Corner handles → pass [fontScale] (uniform drag factor) AND the
  ///   proportionally-scaled [width]: multiply the element fontSize and every
  ///   per-span fontSize override by [fontScale], then auto-fit height.
  ///
  /// [topLeft] repositions the box (a left/top-edge drag moves the corner).
  /// PRESERVES spans, fontFamily, color, bold, italic, alignment, content —
  /// mutates via copyWith, never rebuilding TextData. No undo push here: the
  /// gesture already pushed one on drag-start (matches resizeElement).
  void resizeTextElement(
    String elementId, {
    double? width,
    double? height,
    double? fontScale,
    Offset? topLeft,
  }) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final idx = page.layers.content
        .indexWhere((e) => e is TextElement && e.id == elementId);
    if (idx < 0) return;
    final old = page.layers.content[idx] as TextElement;
    final d = old.data;

    final newWidth = (width ?? d.width).clamp(20.0, 100000.0).toDouble();

    var newFontSize = d.fontSize;
    var newSpans = d.spans;
    if (fontScale != null && fontScale > 0 && (fontScale - 1.0).abs() > 1e-6) {
      newFontSize = (d.fontSize * fontScale).clamp(6.0, 200.0).toDouble();
      if (d.spans.isNotEmpty) {
        newSpans = d.spans
            .map((sp) => sp.fontSize == null
                ? sp
                : sp.copyWith(
                    fontSize: (sp.fontSize! * fontScale).clamp(6.0, 200.0)))
            .toList();
      }
    }

    // The text box is a frame (see [_measureTextHeight] for the content-fit
    // measurement). `measured` is the height the content actually needs at the
    // new width/font; the box may be TALLER (the user dragged a height handle)
    // but never shorter — that would clip text.
    final measured =
        _measureTextHeight(d.content, newSpans, newFontSize, newWidth);
    final double newHeight;
    if (height != null) {
      // Explicit frame height from a height/corner handle drag.
      newHeight = max(height, measured);
    } else {
      // Width or font change with no explicit height: keep a box the user had
      // previously extended past its content, otherwise auto-fit to content.
      final oldMeasured =
          _measureTextHeight(d.content, d.spans, d.fontSize, d.width);
      final wasExtended = d.height > oldMeasured + 1.0;
      newHeight = wasExtended ? max(d.height, measured) : measured;
    }

    final newData = d.copyWith(
      x: topLeft?.dx ?? d.x,
      y: topLeft?.dy ?? d.y,
      width: newWidth,
      height: newHeight,
      fontSize: newFontSize,
      spans: newSpans,
    );

    final newContent = List<ContentElement>.from(page.layers.content);
    newContent[idx] = old.copyWith(data: newData);

    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(
          background: page.layers.background, content: newContent),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );
    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;
    state = s.copyWith(pages: updatedPages, isDirty: true);
  }

  void resizeElement(String elementId, Rect newBounds) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final updatedContent = page.layers.content.map((element) {
      final id = element.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      if (id != elementId) return element;
      return element.map(
        stroke: (e) => e as ContentElement, // can't resize strokes this way
        // Text resize from the smart-resize flow goes through
        // resizeTextElement; this arm is the generic fallback. copyWith
        // preserves spans/fontFamily, and height is re-fit to the new
        // width rather than free-stretched (auto-fit owns height).
        text: (e) => ContentElement.text(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(
            x: newBounds.left, y: newBounds.top,
            width: newBounds.width,
            height: _measureTextHeight(
                e.data.content, e.data.spans, e.data.fontSize, newBounds.width),
          ),
        ),
        image: (e) => ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(
            x: newBounds.left, y: newBounds.top,
            width: newBounds.width, height: newBounds.height,
          ),
        ),
        shape: (e) {
          // Triangles with explicit vertices: remap each vertex via the
          // bbox→bbox affine so the shape stretches/translates with the
          // new bbox while preserving relative geometry. Without this,
          // resize would change the bbox but the absolute-coord vertices
          // would stay frozen at the original position, producing a
          // mismatched shape.
          List<double> remappedVertices = e.data.vertices;
          if (e.data.vertices.length == 6) {
            final oldL = min(e.data.x1, e.data.x2);
            final oldT = min(e.data.y1, e.data.y2);
            final oldR = max(e.data.x1, e.data.x2);
            final oldB = max(e.data.y1, e.data.y2);
            final oldW = oldR - oldL;
            final oldH = oldB - oldT;
            final newW = newBounds.width;
            final newH = newBounds.height;
            double mapX(double x) => oldW <= 0
                ? newBounds.left
                : newBounds.left + (x - oldL) / oldW * newW;
            double mapY(double y) => oldH <= 0
                ? newBounds.top
                : newBounds.top + (y - oldT) / oldH * newH;
            final v = e.data.vertices;
            remappedVertices = [
              mapX(v[0]), mapY(v[1]),
              mapX(v[2]), mapY(v[3]),
              mapX(v[4]), mapY(v[5]),
            ];
          }
          return ContentElement.shape(
            id: e.id, zIndex: e.zIndex,
            data: e.data.copyWith(
              x1: newBounds.left, y1: newBounds.top,
              x2: newBounds.right, y2: newBounds.bottom,
              vertices: remappedVertices,
            ),
          );
        },
        math: (e) {
          final s = e.data.width <= 0 ? 1.0 : newBounds.width / e.data.width;
          return ContentElement.math(
            id: e.id, zIndex: e.zIndex,
            data: e.data.copyWith(
              x: newBounds.left, y: newBounds.top,
              width: newBounds.width, height: newBounds.height,
              fontSize: (e.data.fontSize * s).clamp(6.0, 200.0),
            ),
          );
        },
      );
    }).toList();

    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: updatedContent),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;
    state = s.copyWith(pages: updatedPages, isDirty: true);
  }

  void rotateElement(String elementId, double deltaAngle) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final updatedContent = page.layers.content.map((element) {
      final id = element.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      if (id != elementId) return element;
      return element.map(
        stroke: (e) => e as ContentElement,
        text: (e) => e as ContentElement,
        image: (e) => ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(rotation: e.data.rotation + deltaAngle),
        ),
        shape: (e) {
          // Vertex triangles ignore the rotation field (render path uses
          // the absolute vertices). Apply the rotation directly to the
          // vertices around the bbox center so the visible shape rotates.
          final cx = (e.data.x1 + e.data.x2) / 2;
          final cy = (e.data.y1 + e.data.y2) / 2;
          final cosA = cos(deltaAngle);
          final sinA = sin(deltaAngle);
          final newVertices = _transformVertices(e.data.vertices, (p) {
            final dx = p.dx - cx;
            final dy = p.dy - cy;
            return Offset(cx + dx * cosA - dy * sinA,
                          cy + dx * sinA + dy * cosA);
          });
          return ContentElement.shape(
            id: e.id, zIndex: e.zIndex,
            data: e.data.copyWith(
              rotation: e.data.rotation + deltaAngle,
              vertices: newVertices,
            ),
          );
        },
        math: (e) => e as ContentElement,
      );
    }).toList();

    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: updatedContent),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;
    state = s.copyWith(pages: updatedPages, isDirty: true);
  }

  void deleteElement(String elementId) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);

    final filteredContent = page.layers.content.where((element) {
      final id = element.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      return id != elementId;
    }).toList();

    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: filteredContent),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;
    state = s.copyWith(
      pages: updatedPages, undoStack: undoStack, redoStack: [], isDirty: true,
      clearSelectedElement: true,
    );
  }

  void bringToFront(String elementId) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);

    final content = List<ContentElement>.from(page.layers.content);
    final idx = content.indexWhere((e) =>
        e.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id) == elementId);
    if (idx < 0 || idx == content.length - 1) return;
    final element = content.removeAt(idx);
    // Give it a zIndex higher than all others
    final maxZ = content.fold<int>(0, (m, e) =>
        max(m, e.map(stroke: (s) => s.zIndex, text: (t) => t.zIndex, image: (i) => i.zIndex, shape: (s) => s.zIndex, math: (m) => m.zIndex)));
    final updated = element.map(
      stroke: (e) => ContentElement.stroke(id: e.id, zIndex: maxZ + 1, data: e.data),
      text: (e) => ContentElement.text(id: e.id, zIndex: maxZ + 1, data: e.data),
      image: (e) => ContentElement.image(id: e.id, zIndex: maxZ + 1, data: e.data),
      shape: (e) => ContentElement.shape(id: e.id, zIndex: maxZ + 1, data: e.data),
      math: (e) => ContentElement.math(id: e.id, zIndex: maxZ + 1, data: e.data),
    );
    content.add(updated);

    _updatePageContent(s, page, fileName, content, undoStack);
  }

  void sendToBack(String elementId) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);

    final content = List<ContentElement>.from(page.layers.content);
    final idx = content.indexWhere((e) =>
        e.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id) == elementId);
    if (idx <= 0) return;
    final element = content.removeAt(idx);
    // Give it a zIndex lower than all others
    final minZ = content.fold<int>(999999, (m, e) =>
        min(m, e.map(stroke: (s) => s.zIndex, text: (t) => t.zIndex, image: (i) => i.zIndex, shape: (s) => s.zIndex, math: (m) => m.zIndex)));
    final updated = element.map(
      stroke: (e) => ContentElement.stroke(id: e.id, zIndex: minZ - 1, data: e.data),
      text: (e) => ContentElement.text(id: e.id, zIndex: minZ - 1, data: e.data),
      image: (e) => ContentElement.image(id: e.id, zIndex: minZ - 1, data: e.data),
      shape: (e) => ContentElement.shape(id: e.id, zIndex: minZ - 1, data: e.data),
      math: (e) => ContentElement.math(id: e.id, zIndex: minZ - 1, data: e.data),
    );
    content.insert(0, updated);

    _updatePageContent(s, page, fileName, content, undoStack);
  }

  void toggleImageLock(String elementId) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final updatedContent = page.layers.content.map((element) {
      final id = element.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      if (id != elementId) return element;
      return element.map(
        stroke: (e) => e as ContentElement,
        text: (e) => e as ContentElement,
        image: (e) => ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(locked: !e.data.locked),
        ),
        shape: (e) => e as ContentElement,
        math: (e) => e as ContentElement,
      );
    }).toList();

    _updatePageContent(s, page, fileName, updatedContent, s.undoStack);
  }

  /// Toggles horizontal flip on an image element.
  void flipImageElement(String elementId) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final updatedContent = page.layers.content.map((element) {
      final id = element.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      if (id != elementId) return element;
      return element.map(
        stroke: (e) => e as ContentElement,
        text: (e) => e as ContentElement,
        image: (e) => ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(flipHorizontal: !e.data.flipHorizontal),
        ),
        shape: (e) => e as ContentElement,
        math: (e) => e as ContentElement,
      );
    }).toList();

    _updatePageContent(s, page, fileName, updatedContent, s.undoStack);
  }

  void setImageComment(String elementId, String? comment) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final updatedContent = page.layers.content.map((element) {
      final id = element.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      if (id != elementId) return element;
      return element.map(
        stroke: (e) => e as ContentElement,
        text: (e) => e as ContentElement,
        image: (e) => ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(comment: comment),
        ),
        shape: (e) => e as ContentElement,
        math: (e) => e as ContentElement,
      );
    }).toList();

    _updatePageContent(s, page, fileName, updatedContent, s.undoStack);
  }

  bool isImageLocked(String elementId) {
    if (state == null) return false;
    final page = state!.currentPage;
    if (page == null) return false;
    for (final el in page.layers.content) {
      final id = el.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      if (id != elementId) continue;
      return el.map(
        stroke: (_) => false, text: (_) => false,
        image: (e) => e.data.locked,
        shape: (_) => false,
        math: (_) => false,
      );
    }
    return false;
  }

  void _updatePageContent(CanvasState s, PageData page, String fileName, List<ContentElement> content, List<UndoEntry> undoStack) {
    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: content),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );
    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;
    state = s.copyWith(pages: updatedPages, undoStack: undoStack, redoStack: [], isDirty: true);
  }

  // ── Image insertion ──

  /// Returns the asset id the image was stored under (`null` if no current
  /// page). PDF import uses the returned id to tie an extracted text layer
  /// back to its raster (see [setPageTextLayer]).
  String? addImageElement(Offset position, String fileName, Uint8List bytes, double width, double height, {bool locked = false}) {
    if (state == null) return null;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return null;
    final pageFileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, pageFileName, page);

    // Content-dedup: reuse an existing identical-bytes asset instead of
    // minting a fresh UUID. PDF (re-)import and page-duplicate otherwise store
    // the same page render under a new id each time, bloating the notebook
    // (observed: 62 duplicate groups / ~19 MB in one notebook).
    final dupId = _findIdenticalAsset(bytes, s.assetBytes);
    final assetId = dupId ?? '${const Uuid().v4()}_$fileName';

    final newElement = ContentElement.image(
      id: const Uuid().v4(),
      zIndex: _nextZIndex(page),
      data: ImageData(
        x: position.dx, y: position.dy,
        width: width, height: height,
        assetPath: assetId,
        locked: locked,
      ),
    );

    final updatedPage = _pageWithNewElement(page, newElement).copyWith(
      assetReferences: [...page.assetReferences, assetId],
    );
    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[pageFileName] = updatedPage;

    // Store raw bytes for persistence and decode for rendering. When we reused
    // an existing asset (dupId != null) the bytes are already present and
    // already uploaded — only register/mark-dirty genuinely new content.
    final newAssetBytes = Map<String, Uint8List>.from(s.assetBytes);
    if (dupId == null) {
      newAssetBytes[assetId] = bytes;
      (_assetsByLength[bytes.length] ??= []).add(assetId);
    }
    // Skip eager decode during bulk operations (PDF import). Each
    // decoded `ui.Image` lives on the GPU at ~3-5 MB; eagerly
    // decoding 78 PDF pages while importing was the OOM that
    // crashed the host. The thumbnail / current-page render path
    // calls `ensureAssetDecodedForThumbnail` lazily for what's
    // actually visible, so deferring is correct — the user is on
    // ONE page during the import, and only that page's image needs
    // to be decoded.
    if (!_bulkOperationInProgress) {
      _decodeAndCacheImage(assetId, newAssetBytes[assetId] ?? bytes);
    }
    if (dupId == null) _markAssetDirty(assetId);

    state = s.copyWith(
      pages: updatedPages,
      assetBytes: newAssetBytes,
      undoStack: undoStack,
      redoStack: [],
      isDirty: true,
      selectedElementId: newElement.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id),
      currentTool: CanvasTool.lasso,
    );
    return assetId;
  }

  /// Attach an extracted PDF text layer to an EXPLICIT page. Called during
  /// PDF import right after the page's raster image was added, so the layer's
  /// page-logical coordinates line up with that image. The target page is
  /// named, not "the current page": text extraction awaits between the image
  /// insert and this call, and the user can navigate mid-import — attaching
  /// to whatever page happened to be current at completion time clobbered
  /// unrelated pages' layers. The new [PageData] identity makes the page
  /// dirty for the next delta sync / local save.
  void setPageTextLayer(String pageFileName, PdfTextLayer layer) {
    if (state == null) return;
    final s = state!;
    final page = s.pages[pageFileName];
    if (page == null) return;
    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[pageFileName] = page.copyWith(pdfTextLayer: layer);
    state = s.copyWith(pages: updatedPages, isDirty: true);
  }

  /// Asset IDs that have been classified as corrupt (decoding failed,
  /// usually due to the historic 1024-aligned server-side truncation
  /// bug). Used by thumbnails / page render to mark such pages with a
  /// warning indicator instead of a blank placeholder so the user
  /// understands that re-decoding won't help and they need to
  /// re-import the source PDF / image.
  final Set<String> _corruptAssetIds = <String>{};

  /// Public read-only view of [_corruptAssetIds] for UI consumers.
  Set<String> get corruptAssetIds => _corruptAssetIds;

  /// Asset IDs whose bytes are currently being fetched from the server
  /// because they were missing from `state.assetBytes`. While in this
  /// set, callers should render a "loading" placeholder, NOT the
  /// broken-image badge — the asset isn't corrupt, it just hasn't
  /// arrived yet. Distinct from `_healAttempted` because that set
  /// stays populated AFTER the fetch (success or failure) to gate
  /// retries; this set is cleared the moment the fetch lands.
  final Set<String> _loadingAssetIds = <String>{};

  /// Public read-only view of [_loadingAssetIds] for UI consumers.
  Set<String> get loadingAssetIds => _loadingAssetIds;

  /// Tracks per-session asset IDs that have already been the target of
  /// a one-shot fresh-fetch attempt. Without this we'd loop pulling
  /// the same asset every paint frame if the server bytes are STILL
  /// corrupt (the failure path re-fires every paint).
  final Set<String> _healAttempted = <String>{};

  /// One-shot heal: pull fresh bytes for [assetId] from the delta
  /// folder and, if they decode this time, write them into state +
  /// remove the corrupt flag. Called from [_decodeAndCacheImage]'s
  /// failure branch so a user who re-imported the source on another
  /// device gets the fix automatically on the affected device's next
  /// paint instead of having to wait for a sync round-trip.
  /// Sister to [_healCorruptAsset] for the "bytes never landed in
  /// state.assetBytes" case: the asset is referenced by a page but no
  /// payload is in memory. Fetches from the delta folder and, on
  /// success, writes into state + decodes. Used by
  /// [ensureAssetDecodedForThumbnail] so a missing asset doesn't
  /// immediately render as broken when the server actually has it.
  Future<void> _lazyFetchMissingAsset(
      String assetId, String ownerNotebookId) async {
    try {
      final syncService = _ref.read(syncServiceProvider);
      if (syncService == null) {
        _markMissingAsCorrupt(assetId);
        return;
      }
      final fresh = await syncService.downloadDeltaAsset(
          ownerNotebookId, assetId);
      if (_disposed ||
          state == null ||
          state!.metadata.id != ownerNotebookId) {
        return;
      }
      // Server returned bytes — install and decode. Defense-in-depth
      // (the webdav layer already verifies); a 1024-aligned body here
      // means something slipped past, so reject it.
      if (fresh.isEmpty || fresh.length % 1024 == 0) {
        _markMissingAsCorrupt(assetId);
        return;
      }
      final mergedAssets = Map<String, Uint8List>.from(state!.assetBytes);
      mergedAssets[assetId] = fresh;
      state = state!.copyWith(assetBytes: mergedAssets);
      await _decodeAndCacheImage(assetId, fresh);
    } catch (_) {
      // 404 / network failure / etc — only NOW do we declare the asset
      // unrecoverable and surface the broken-image overlay.
      _markMissingAsCorrupt(assetId);
    } finally {
      // Always clear the loading flag — either we landed bytes (UI
      // shows the image) or we marked corrupt (UI shows the broken
      // overlay). Either way the loading placeholder must go.
      if (_loadingAssetIds.remove(assetId)) {
        imageCacheVersion.value++;
      }
    }
  }

  void _markMissingAsCorrupt(String assetId) {
    if (_disposed || state == null) return;
    if (_corruptAssetIds.add(assetId)) {
      // ignore: avoid_print
      print('[Canvas] Asset $assetId has no bytes available — '
          'likely missing on server (404) or never downloaded. '
          'Re-import the source PDF/image to recover.');
      imageCacheVersion.value++;
    }
  }

  Future<void> _healCorruptAsset(String assetId, String ownerNotebookId) async {
    try {
      final syncService = _ref.read(syncServiceProvider);
      if (syncService == null) return;
      final fresh = await syncService.downloadDeltaAsset(
          ownerNotebookId, assetId);
      if (_disposed ||
          state == null ||
          state!.metadata.id != ownerNotebookId) {
        return;
      }
      final existing = state!.assetBytes[assetId];
      if (existing != null &&
          existing.length == fresh.length &&
          _bytesEqual(existing, fresh)) {
        // Same corrupt bytes — server still poisoned. Remember persistently
        // so we don't burn another GET on this asset next app launch (the
        // proactive sweep + lazy heal both consult _healAttempted, which is
        // pre-seeded from this set on open).
        if (_knownIncurableAssets.add(assetId)) {
          unawaited(_persistIncurableAssets(ownerNotebookId));
        }
        return;
      }
      // New bytes — replace and retry decode. _decodeAndCacheImage
      // clears _corruptAssetIds on success.
      final mergedAssets =
          Map<String, Uint8List>.from(state!.assetBytes);
      mergedAssets[assetId] = fresh;
      // Mark the notebook dirty so the next save persists the fresh bytes into
      // the on-disk ZIP — otherwise a fresh app launch hits the stale ZIP
      // cache and re-heals every session. We do NOT add the asset to
      // _dirtyAssetKeys: the server already has these clean bytes (that's
      // where we just fetched them), so the local-only ZIP rewrite is enough
      // and no redundant re-upload is triggered.
      state = state!.copyWith(assetBytes: mergedAssets, isDirty: true);
      await _decodeAndCacheImage(assetId, fresh);
    } catch (_) {
      // Network blip / server-side 404 / etc — keep corrupt flag.
    }
  }

  /// Proactively re-fetch locally-truncated assets from the server. The
  /// rendered PDF/image pages live IN the notebook (server `_delta/.../assets`
  /// + local), independent of the original source PDF — so when a local asset
  /// carries the 1024-aligned truncation fingerprint, the authoritative clean
  /// bytes are almost always still on the server and we just re-pull them.
  ///
  /// The lazy heal in [_decodeAndCacheImage] only fires for assets the user
  /// actually views; this sweep covers assets on pages they never open, so a
  /// notebook fully self-heals in the background. Each fetch is throttled via
  /// [_healAttempted] (once per asset per session) and [_healCorruptAsset]
  /// replaces bytes only when the server copy actually differs — so a clean
  /// asset that happens to be 1024-aligned costs one harmless PROPFIND/GET and
  /// nothing else. Capped so a false-positive-heavy notebook can't trigger a
  /// fetch storm; the rest still heal lazily on view.
  void _recoverTruncatedAssetsFromServer() {
    final s = state;
    if (s == null) return;
    if (_ref.read(syncServiceProvider) == null) return; // offline → skip
    final nb = s.metadata.id;
    const cap = 80;
    var fired = 0;
    for (final entry in s.assetBytes.entries) {
      if (fired >= cap) break;
      final b = entry.value;
      if (b.isEmpty || b.length % 1024 != 0) continue; // not a truncation suspect
      if (!_healAttempted.add(entry.key)) continue; // already tried this session
      fired++;
      unawaited(_healCorruptAsset(entry.key, nb));
    }
    if (fired > 0) {
      print('[Canvas] Proactive asset recovery: re-fetching $fired '
          'truncated-fingerprint asset(s) from server (clean copy lives in '
          'the notebook; no source PDF needed)');
    }
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Content-dedup index: byte-length → assetIds that have that length. Lets
  /// [addImageElement] reuse an existing identical-bytes asset instead of
  /// minting a fresh UUID for the same image. Without this, PDF (re-)import
  /// and page-duplicate store the same page render under a new asset id every
  /// time — observed bloating a real notebook by 62 duplicate groups (~19 MB,
  /// ~10%). Bucketing on length keeps the dedup check to a handful of exact
  /// byte-compares (no hashing, no extra dependency). Built lazily, reset on
  /// notebook open/close.
  final Map<int, List<String>> _assetsByLength = {};
  bool _assetIndexBuilt = false;

  /// Returns the id of an existing asset whose bytes are identical to [bytes],
  /// or null if none. Lazily indexes the current asset set on first use.
  String? _findIdenticalAsset(Uint8List bytes, Map<String, Uint8List> assets) {
    if (!_assetIndexBuilt) {
      _assetsByLength.clear();
      assets.forEach((id, b) => (_assetsByLength[b.length] ??= []).add(id));
      _assetIndexBuilt = true;
    }
    final candidates = _assetsByLength[bytes.length];
    if (candidates == null) return null;
    for (final id in candidates) {
      final b = assets[id];
      if (b != null && _bytesEqual(b, bytes)) return id;
    }
    return null;
  }

  /// AssetIds whose decode is currently in flight. Used to prevent two
  /// parallel decodes from racing — priority loop and background loop can
  /// both fire `_decodeAndCacheImage(assetId, bytes)` for the same id, and
  /// the second decode's writeback would otherwise overwrite the first
  /// without disposing the orphaned ui.Image (silent GPU-memory leak).
  final Set<String> _decodingInFlight = <String>{};

  Future<void> _decodeAndCacheImage(String assetId, Uint8List bytes) async {
    // Remember which notebook this decode belongs to. If the user switches
    // notebooks while we're awaiting the codec, the decoded ui.Image must
    // not leak into the new notebook's imageCache (would show a stale
    // image on a different page, or worse, under a conflicting assetId).
    final ownerNotebookId = state?.metadata.id;
    if (ownerNotebookId == null) return;
    // Coalesce parallel decodes for the same asset. Once the in-flight
    // decode lands the cache will already hold the image, so a subsequent
    // request can re-check via the existing imageCache lookup and skip.
    if (!_decodingInFlight.add(assetId)) return;
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      // Re-check: still the same notebook, still not disposed, assetBytes
      // still references this asset.
      if (_disposed ||
          state == null ||
          state!.metadata.id != ownerNotebookId) {
        image.dispose();
        return;
      }
      final newCache = Map<String, ui.Image>.from(state!.imageCache);
      // Dispose any previously cached image for this assetId to avoid GPU
      // memory leaks on iPad when re-decoding (e.g. after a pull merge or
      // a crop that reuses the same assetId).
      final previous = newCache[assetId];
      if (previous != null && !identical(previous, image)) {
        previous.dispose();
      }
      newCache[assetId] = image;
      // Recovered from a previous corruption attempt — clear the flag
      // so the warning indicator goes away.
      _corruptAssetIds.remove(assetId);
      // If this was on the persisted incurable list (e.g. an earlier session
      // confirmed the server was poisoned), drop it now — the asset clearly
      // decodes, so future sessions should try to heal it again normally.
      if (_knownIncurableAssets.remove(assetId)) {
        unawaited(_persistIncurableAssets(ownerNotebookId));
      }
      state = state!.copyWith(imageCache: newCache);
      imageCacheVersion.value++;
    } catch (e) {
      // Image decoding failed. Most common cause in this codebase is
      // the historic server-side truncation bug — assets uploaded
      // before the post-PUT size verification (commit dd43281) sit on
      // the server and in local mirrors at exactly 1024-aligned byte
      // boundaries with corrupt PNG/JPG payloads. Detect that
      // signature and log a one-shot diagnostic so the user knows
      // why a thumbnail is blank.
      final isLikelyTruncation = bytes.isNotEmpty && bytes.length % 1024 == 0;
      if (_corruptAssetIds.add(assetId)) {
        // ignore: avoid_print
        print('[Canvas] Asset $assetId failed to decode: $e '
            '(${bytes.length} B'
            '${isLikelyTruncation ? ", 1024-aligned → likely truncated server-side" : ""}). '
            'Re-import the source PDF/image to recover this asset.');
        if (state != null && state!.metadata.id == ownerNotebookId) {
          // Bump the version so the painter repaints (corruptAssetIds
          // membership controls the placeholder render path).
          imageCacheVersion.value++;
        }
        // ── Auto-heal ──
        // If another device re-uploaded clean bytes for this asset
        // (after the user manually re-imported the source PDF/image
        // from a different machine), the server now has good bytes
        // but our local copy is the truncated leftover. Try a
        // one-shot fresh fetch from the delta folder; on success
        // replace the cached bytes and retry the decode.
        // Throttled to once per asset per session via _healAttempted
        // so we don't loop on assets the server STILL has corrupt.
        if (_healAttempted.add(assetId)) {
          unawaited(_healCorruptAsset(assetId, ownerNotebookId));
        }
      }
    } finally {
      // Dispose the codec to release native decoder resources.
      // On iPad, leaking codecs quickly exhausts GPU memory and causes the
      // renderer to be jettisoned by the OS.
      codec?.dispose();
      _decodingInFlight.remove(assetId);
    }
  }

  /// Crop an image element using a normalized crop rect (0..1).
  /// Creates a new cropped image from the original bytes.
  Future<void> cropImageElement(String elementId, Rect normalizedCrop) async {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;

    // Find the image element
    ImageData? imgData;
    for (final el in page.layers.content) {
      el.map(
        stroke: (_) {},
        text: (_) {},
        image: (i) { if (i.id == elementId) imgData = i.data; },
        shape: (_) {},
        math: (_) {},
      );
    }
    if (imgData == null) return;

    final cachedImage = s.imageCache[imgData!.assetPath];
    if (cachedImage == null) return;

    // Crop the image using a PictureRecorder
    final srcW = cachedImage.width.toDouble();
    final srcH = cachedImage.height.toDouble();
    final cropSrc = Rect.fromLTRB(
      normalizedCrop.left * srcW,
      normalizedCrop.top * srcH,
      normalizedCrop.right * srcW,
      normalizedCrop.bottom * srcH,
    );
    final cropW = cropSrc.width.toInt();
    final cropH = cropSrc.height.toInt();
    if (cropW < 1 || cropH < 1) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      cachedImage,
      cropSrc,
      Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    ui.Image croppedImage;
    Uint8List croppedBytes;
    try {
      croppedImage = await picture.toImage(cropW, cropH);
      // Encode the cropped image to PNG bytes
      final byteData = await croppedImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        croppedImage.dispose();
        return;
      }
      croppedBytes = Uint8List.fromList(byteData.buffer.asUint8List());
    } finally {
      // Picture holds GPU/CPU display-list memory; release ASAP.
      picture.dispose();
    }

    final newAssetId = '${const Uuid().v4()}_cropped.png';

    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);

    // Update the image element dimensions (scale on page proportionally)
    final scaleX = normalizedCrop.width;
    final scaleY = normalizedCrop.height;
    final newPageW = imgData!.width * scaleX;
    final newPageH = imgData!.height * scaleY;
    final newX = imgData!.x + imgData!.width * normalizedCrop.left;
    final newY = imgData!.y + imgData!.height * normalizedCrop.top;

    final updatedContent = page.layers.content.map((element) {
      final id = element.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      if (id != elementId) return element;
      return element.map(
        stroke: (e) => e as ContentElement,
        text: (e) => e as ContentElement,
        image: (e) => ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          data: ImageData(
            x: newX, y: newY,
            width: newPageW, height: newPageH,
            assetPath: newAssetId,
            rotation: e.data.rotation,
            opacity: e.data.opacity,
            locked: e.data.locked, comment: e.data.comment,
          ),
        ),
        shape: (e) => e as ContentElement,
        math: (e) => e as ContentElement,
      );
    }).toList();

    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: updatedContent),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    // Update caches
    final newCache = Map<String, ui.Image>.from(s.imageCache);
    // Defensive: if a previous image happened to be keyed under the new
    // (unique UUID) assetId — shouldn't happen but we've seen IDs collide
    // after aborted crop+undo sequences — dispose it before replacing.
    final previousAtNewId = newCache[newAssetId];
    if (previousAtNewId != null && !identical(previousAtNewId, croppedImage)) {
      previousAtNewId.dispose();
    }
    newCache[newAssetId] = croppedImage;
    final newAssets = Map<String, Uint8List>.from(s.assetBytes);
    newAssets[newAssetId] = croppedBytes;
    _markAssetDirty(newAssetId);

    state = s.copyWith(
      pages: updatedPages,
      imageCache: newCache,
      assetBytes: newAssets,
      undoStack: undoStack,
      redoStack: [],
      isDirty: true,
    );
    imageCacheVersion.value++;
  }

  // ── Clipboard operations ──

  /// Collect the asset bytes referenced by [elements] from the CURRENT
  /// notebook's asset store, so the clipboard stays pasteable across
  /// notebooks (see [CanvasClipboard.assets]). Best-effort: assets whose
  /// bytes aren't resident in memory are skipped.
  Map<String, Uint8List> _collectClipboardAssets(
      List<ContentElement> elements) {
    final s = state;
    if (s == null) return const {};
    final out = <String, Uint8List>{};
    for (final el in elements) {
      if (el is ImageElement) {
        final p = el.data.assetPath;
        final bytes = s.assetBytes[p];
        if (p.isNotEmpty && bytes != null) out[p] = bytes;
      }
    }
    return out;
  }

  void copySelection() {
    if (state == null || state!.lassoSelection == null) return;
    final sel = state!.lassoSelection!;
    final page = state!.currentPage;
    if (page == null) return;

    final copied = page.layers.content.where((element) {
      final id = element.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      return sel.selectedIds.contains(id);
    }).toList();

    if (copied.isEmpty) return;
    final clip = CanvasClipboard(
      elements: copied,
      bounds: sel.bounds,
      assets: _collectClipboardAssets(copied),
    );
    state = state!.copyWith(clipboard: clip);
    _ref.read(crossNotebookClipboardProvider.notifier).state = clip;
  }

  void cutSelection() {
    copySelection();
    deleteSelection();
  }

  /// Copy a single element (e.g. an image / PDF preview) to the clipboard.
  void copyElement(String elementId) {
    if (state == null) return;
    final page = state!.currentPage;
    if (page == null) return;
    final element = page.layers.content.where((e) {
      final id = e.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      return id == elementId;
    }).firstOrNull;
    if (element == null) return;
    final bounds = _getElementBounds(element);
    if (bounds == null) return;
    final clip = CanvasClipboard(
      elements: [element],
      bounds: bounds,
      assets: _collectClipboardAssets([element]),
    );
    state = state!.copyWith(clipboard: clip);
    _ref.read(crossNotebookClipboardProvider.notifier).state = clip;
  }

  /// Cut a single element: copy to clipboard, then delete.
  void cutElement(String elementId) {
    copyElement(elementId);
    deleteElement(elementId);
  }

  void paste({Offset? at}) {
    if (state == null || state!.clipboard == null) return;
    final s = state!;
    final clip = s.clipboard!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);

    // Offset paste position slightly from original
    final pasteOffset = at != null
        ? Offset(at.dx - clip.bounds.center.dx, at.dy - clip.bounds.center.dy)
        : const Offset(20, 20);

    final baseZ = _nextZIndex(page);
    final newElements = <ContentElement>[];
    final newIds = <String>[];
    for (int idx = 0; idx < clip.elements.length; idx++) {
      final element = clip.elements[idx];
      final newId = const Uuid().v4();
      newIds.add(newId);
      final translated = _translateElement(element, pasteOffset);
      final z = baseZ + idx;
      newElements.add(translated.map(
        stroke: (e) => ContentElement.stroke(id: newId, zIndex: z, data: e.data),
        text: (e) => ContentElement.text(id: newId, zIndex: z, data: e.data),
        image: (e) => ContentElement.image(id: newId, zIndex: z, data: e.data),
        shape: (e) => ContentElement.shape(id: newId, zIndex: z, data: e.data),
        math: (e) => ContentElement.math(id: newId, zIndex: z, data: e.data),
      ));
    }

    // Materialize assets this notebook doesn't have (cross-notebook paste:
    // the clipboard carries the source notebook's bytes) and register the
    // pasted elements' asset ids on the destination page so orphan-asset
    // pruning never mistakes them for garbage.
    final newAssetBytes = Map<String, Uint8List>.from(s.assetBytes);
    final newRefs = <String>[];
    var assetsChanged = false;
    for (final element in clip.elements) {
      if (element is! ImageElement) continue;
      final p = element.data.assetPath;
      if (p.isEmpty) continue;
      if (!page.assetReferences.contains(p) && !newRefs.contains(p)) {
        newRefs.add(p);
      }
      if (!newAssetBytes.containsKey(p)) {
        final carried = clip.assets[p];
        if (carried != null) {
          newAssetBytes[p] = carried;
          (_assetsByLength[carried.length] ??= []).add(p);
          _markAssetDirty(p);
          _decodeAndCacheImage(p, carried);
          assetsChanged = true;
        }
      }
    }

    final updatedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: [...page.layers.content, ...newElements]),
      assetReferences: [...page.assetReferences, ...newRefs],
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    // The cross-notebook clipboard is a one-shot "carry to the next
    // notebook" intent: once the user has pasted ANYWHERE it is consumed.
    // Leaving it set made openNotebook re-arm the "Tocca per posizionare"
    // banner on every subsequent notebook open, even after the paste.
    if (_ref.read(crossNotebookClipboardProvider) != null) {
      _ref.read(crossNotebookClipboardProvider.notifier).state = null;
    }

    // Keep the pasted elements SELECTED (same as duplicateSelection): the
    // paste often lands on top of existing content, and re-selecting it by
    // hand to move it away is fiddly. Switching to lasso makes the handles
    // immediately usable.
    state = s.copyWith(
      pages: updatedPages,
      assetBytes: assetsChanged ? newAssetBytes : s.assetBytes,
      undoStack: undoStack,
      redoStack: [],
      isDirty: true,
      lassoPath: [],
      lassoSelection: LassoSelection(
        selectedIds: newIds,
        bounds: clip.bounds.shift(pasteOffset),
      ),
      currentTool: CanvasTool.lasso,
      pendingPaste: false,
    );
  }

  /// Duplicate the current lasso selection in place, then keep the
  /// new copies selected so the user can drag/scale/rotate them via
  /// the existing lasso handles. Pasting in select mode replaces the
  /// previous "tap somewhere to drop" flow which was disorienting for
  /// large selections (the user couldn't tell where the duplicate
  /// would land before committing).
  void duplicateSelection() {
    if (state == null || state!.lassoSelection == null) return;
    final s = state!;
    final sel = s.lassoSelection!;
    final page = s.currentPage;
    if (page == null) return;

    final fileName = s.currentPageFileName;
    final originals = page.layers.content.where((element) {
      final id = element.map(
        stroke: (e) => e.id,
        text: (e) => e.id,
        image: (e) => e.id,
        shape: (e) => e.id,
        math: (e) => e.id,
      );
      return sel.selectedIds.contains(id);
    }).toList();
    if (originals.isEmpty) return;

    // Update clipboard so a follow-up Ctrl+V works as expected. NOTE: only
    // the in-app clipboard — duplicate places its copy immediately, so
    // arming the cross-notebook clipboard here would re-trigger the
    // "Tocca per posizionare" banner at the next notebook open.
    final clip = CanvasClipboard(
      elements: originals,
      bounds: sel.bounds,
      assets: _collectClipboardAssets(originals),
    );

    final undoStack = _pushUndo(s, fileName, page);

    // Offset the copy by a small constant so it's visible next to the
    // original instead of overlapping it pixel-perfect.
    const offset = Offset(20, 20);

    final baseZ = _nextZIndex(page);
    final newElements = <ContentElement>[];
    final newIds = <String>[];
    for (int idx = 0; idx < originals.length; idx++) {
      final translated = _translateElement(originals[idx], offset);
      final newId = const Uuid().v4();
      newIds.add(newId);
      final z = baseZ + idx;
      newElements.add(translated.map(
        stroke: (e) => ContentElement.stroke(id: newId, zIndex: z, data: e.data),
        text: (e) => ContentElement.text(id: newId, zIndex: z, data: e.data),
        image: (e) => ContentElement.image(id: newId, zIndex: z, data: e.data),
        shape: (e) => ContentElement.shape(id: newId, zIndex: z, data: e.data),
        math: (e) => ContentElement.math(id: newId, zIndex: z, data: e.data),
      ));
    }

    final updatedPage = PageData(
      pageId: page.pageId,
      pageNumber: page.pageNumber,
      width: page.width,
      height: page.height,
      layers: RenderingLayers(
        background: page.layers.background,
        content: [...page.layers.content, ...newElements],
      ),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt,
      modifiedAt: DateTime.now(),
    );
    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = updatedPage;

    final newBounds = sel.bounds.shift(offset);

    state = s.copyWith(
      pages: updatedPages,
      clipboard: clip,
      undoStack: undoStack,
      redoStack: [],
      isDirty: true,
      lassoPath: [],
      lassoSelection:
          LassoSelection(selectedIds: newIds, bounds: newBounds),
    );
  }

  void duplicateElement(String elementId) {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;

    final original = page.layers.content.where((e) {
      final id = e.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      return id == elementId;
    }).firstOrNull;
    if (original == null) return;

    // Copy the element to clipboard and enter placement mode. In-app
    // clipboard only (see duplicateSelection): duplicating is a local
    // action, arming the cross-notebook clipboard re-triggered the
    // placement banner at the next notebook open.
    final bounds = _elementBounds(original);
    final clip = CanvasClipboard(
      elements: [original],
      bounds: bounds,
      assets: _collectClipboardAssets([original]),
    );
    state = s.copyWith(
      clipboard: clip,
      pendingPaste: true,
      clearSelectedElement: true,
    );
  }

  void cancelPendingPaste() {
    if (state == null) return;
    // Dismissing the banner is a "no thanks" for the carried clipboard too:
    // without this, the cross-notebook clipboard re-armed the banner at the
    // next notebook open even though the user explicitly closed it.
    if (_ref.read(crossNotebookClipboardProvider) != null) {
      _ref.read(crossNotebookClipboardProvider.notifier).state = null;
    }
    state = state!.copyWith(pendingPaste: false);
  }

  // ── Reusable Symbols & Libraries ──

  /// Returns the first library, or creates a default one if none exists.
  SymbolLibrary _defaultLibrary() {
    if (state!.symbolLibraries.isEmpty) {
      final lib = SymbolLibrary(id: const Uuid().v4(), name: 'Simboli');
      state = state!.copyWith(symbolLibraries: [lib]);
      return lib;
    }
    return state!.symbolLibraries.first;
  }

  void createSymbolLibrary(String name) {
    if (state == null) return;
    final lib = SymbolLibrary(id: const Uuid().v4(), name: name);
    state = state!.copyWith(symbolLibraries: [...state!.symbolLibraries, lib]);
  }

  void renameSymbolLibrary(String libId, String newName) {
    if (state == null) return;
    state = state!.copyWith(
      symbolLibraries: state!.symbolLibraries.map((l) => l.id == libId ? l.copyWith(name: newName) : l).toList(),
    );
  }

  void deleteSymbolLibrary(String libId) {
    if (state == null) return;
    state = state!.copyWith(
      symbolLibraries: state!.symbolLibraries.where((l) => l.id != libId).toList(),
    );
  }

  void renameSymbol(String libId, String symbolId, String newName) {
    if (state == null) return;
    state = state!.copyWith(
      symbolLibraries: state!.symbolLibraries.map((l) {
        if (l.id != libId) return l;
        return l.copyWith(symbols: l.symbols.map((s) => s.id == symbolId
            ? ReusableSymbol(id: s.id, name: newName, elements: s.elements, bounds: s.bounds, createdAt: s.createdAt)
            : s).toList());
      }).toList(),
    );
  }

  void deleteSymbolFromLibrary(String libId, String symbolId) {
    if (state == null) return;
    state = state!.copyWith(
      symbolLibraries: state!.symbolLibraries.map((l) {
        if (l.id != libId) return l;
        return l.copyWith(symbols: l.symbols.where((s) => s.id != symbolId).toList());
      }).toList(),
    );
  }

  /// Creates a symbol from the current lasso selection and adds it to the
  /// target library (first library if [targetLibId] is null).
  void createSymbolFromSelection(String name, {String? targetLibId}) {
    if (state == null || state!.lassoSelection == null) return;
    final sel = state!.lassoSelection!;
    final page = state!.currentPage;
    if (page == null) return;

    final elements = page.layers.content.where((element) {
      final id = element.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      return sel.selectedIds.contains(id);
    }).toList();

    if (elements.isEmpty) return;

    final symbol = ReusableSymbol(
      id: const Uuid().v4(),
      name: name,
      elements: elements,
      bounds: sel.bounds,
      createdAt: DateTime.now(),
    );

    // Ensure there is at least one library
    _defaultLibrary();

    final targetId = targetLibId ?? state!.symbolLibraries.first.id;
    state = state!.copyWith(
      symbolLibraries: state!.symbolLibraries.map((l) {
        if (l.id != targetId) return l;
        return l.copyWith(symbols: [...l.symbols, symbol]);
      }).toList(),
    );
  }

  void createSymbolFromElement(String elementId, String name) {
    if (state == null) return;
    final page = state!.currentPage;
    if (page == null) return;

    final element = page.layers.content.where((e) {
      final id = e.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      return id == elementId;
    }).firstOrNull;
    if (element == null) return;

    final bounds = _getElementBounds(element);
    if (bounds == null) return;

    final symbol = ReusableSymbol(
      id: const Uuid().v4(),
      name: name,
      elements: [element],
      bounds: bounds,
      createdAt: DateTime.now(),
    );

    _defaultLibrary();
    final targetId = state!.symbolLibraries.first.id;
    state = state!.copyWith(
      symbolLibraries: state!.symbolLibraries.map((l) {
        if (l.id != targetId) return l;
        return l.copyWith(symbols: [...l.symbols, symbol]);
      }).toList(),
    );
  }

  // Legacy: keep for backward compatibility
  void deleteSymbol(String symbolId) {
    if (state == null) return;
    state = state!.copyWith(
      symbolLibraries: state!.symbolLibraries.map((l) =>
          l.copyWith(symbols: l.symbols.where((s) => s.id != symbolId).toList())
      ).toList(),
    );
  }

  void setPendingSymbol(ReusableSymbol symbol) {
    if (state == null) return;
    state = state!.copyWith(pendingSymbol: symbol);
  }

  void clearPendingSymbol() {
    if (state == null) return;
    state = state!.copyWith(clearPendingSymbol: true);
  }

  Future<void> insertSymbol(ReusableSymbol symbol, Offset position) async {
    if (state == null) return;
    // Clear pending symbol immediately to prevent multiple placements
    state = state!.copyWith(clearPendingSymbol: true);

    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);

    final symbolImage = await _rasterizeSymbol(symbol);
    if (symbolImage == null || state == null) return;

    // Re-read current state after async gap (state may have changed)
    final current = state!;
    final currentPage = current.currentPage;
    if (currentPage == null) return;
    final currentFileName = current.currentPageFileName;

    // Compute the same padding used during rasterization
    double maxHalfStroke = 2.0;
    for (final e in symbol.elements) {
      e.mapOrNull(
        stroke: (s) {
          final half = s.data.baseWidth / 2.0;
          if (half > maxHalfStroke) maxHalfStroke = half;
        },
        shape: (s) {
          final half = s.data.strokeWidth / 2.0;
          if (half > maxHalfStroke) maxHalfStroke = half;
        },
      );
    }
    final paddedBounds = symbol.bounds.inflate(maxHalfStroke);
    final symbolW = paddedBounds.width <= 0 ? 1.0 : paddedBounds.width;
    final symbolH = paddedBounds.height <= 0 ? 1.0 : paddedBounds.height;
    final assetId = 'symbol_${const Uuid().v4()}.png';

    final imgElement = ContentElement.image(
      id: const Uuid().v4(),
      zIndex: _nextZIndex(page),
      data: ImageData(
        x: position.dx - symbolW / 2,
        y: position.dy - symbolH / 2,
        width: symbolW,
        height: symbolH,
        assetPath: assetId,
      ),
    );

    final updatedPage = PageData(
      pageId: currentPage.pageId, pageNumber: currentPage.pageNumber,
      width: currentPage.width, height: currentPage.height,
      layers: RenderingLayers(background: currentPage.layers.background, content: [...currentPage.layers.content, imgElement]),
      assetReferences: currentPage.assetReferences,
      createdAt: currentPage.createdAt, modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(current.pages);
    updatedPages[currentFileName] = updatedPage;

    final newAssets = Map<String, Uint8List>.from(current.assetBytes);
    newAssets[assetId] = symbolImage.$1;
    final newCache = Map<String, ui.Image>.from(current.imageCache);
    newCache[assetId] = symbolImage.$2;
    _markAssetDirty(assetId);

    state = current.copyWith(
      pages: updatedPages,
      assetBytes: newAssets,
      imageCache: newCache,
      undoStack: undoStack,
      redoStack: [],
      isDirty: true,
      // Land in selection mode on the just-placed symbol (mirrors
      // addImageElement) instead of deselecting — a symbol is usually
      // dropped in roughly the right spot and then nudged/resized, which
      // needs it selected immediately rather than forcing a manual re-tap.
      selectedElementId: imgElement.map(
          stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id,
          shape: (e) => e.id, math: (e) => e.id),
      clearLasso: true,
      clearPendingSymbol: true,
      currentTool: CanvasTool.lasso,
    );
    imageCacheVersion.value++;
  }

  Future<(Uint8List, ui.Image)?> _rasterizeSymbol(ReusableSymbol symbol) async {
    // Render at 3x resolution for crisp quality
    const double renderScale = 3.0;

    // Compute padding: half of the thickest stroke so edges aren't clipped
    double maxHalfStroke = 2.0; // minimum padding
    for (final e in symbol.elements) {
      e.mapOrNull(
        stroke: (s) {
          final half = s.data.baseWidth / 2.0;
          if (half > maxHalfStroke) maxHalfStroke = half;
        },
        shape: (s) {
          final half = s.data.strokeWidth / 2.0;
          if (half > maxHalfStroke) maxHalfStroke = half;
        },
      );
    }

    final paddedBounds = symbol.bounds.inflate(maxHalfStroke);
    final baseW = paddedBounds.width <= 0 ? 1.0 : paddedBounds.width;
    final baseH = paddedBounds.height <= 0 ? 1.0 : paddedBounds.height;
    final renderW = (baseW * renderScale).ceil();
    final renderH = (baseH * renderScale).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, renderW.toDouble(), renderH.toDouble()));
    canvas.scale(renderScale);
    canvas.translate(-paddedBounds.left, -paddedBounds.top);

    for (final element in symbol.elements) {
      element.map(
        stroke: (e) => _paintStrokeSymbol(canvas, e.data),
        text: (e) => _paintTextSymbol(canvas, e.data),
        image: (e) => _paintImageSymbol(canvas, e.data),
        shape: (e) => _paintShapeSymbol(canvas, e.data),
        math: (_) {},
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(renderW, renderH);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      image.dispose();
      return null;
    }
    return (byteData.buffer.asUint8List(), image);
  }

  void _paintStrokeSymbol(Canvas canvas, StrokeData stroke) {
    if (stroke.points.length < 2) return;
    final color = Color(stroke.color);

    // Highlighter
    if (stroke.isHighlighter) {
      final paint = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.baseWidth
        ..blendMode = BlendMode.multiply
        ..isAntiAlias = true;
      final path = Path()..moveTo(stroke.points[0].x, stroke.points[0].y);
      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].x, stroke.points[i].y);
      }
      canvas.drawPath(path, paint);
      return;
    }

    // Ballpoint
    if (stroke.toolType == 'ballpoint') {
      final paint = Paint()
        ..color = color.withValues(alpha: stroke.opacity)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      final interp = _catmullRomInterpolateSymbol(stroke.points);
      for (int i = 0; i < interp.length - 1; i++) {
        final p0 = interp[i];
        final p1 = interp[i + 1];
        final avgP = (p0.pressure + p1.pressure) / 2;
        paint.strokeWidth = stroke.baseWidth * (0.6 + avgP * 0.4);
        canvas.drawLine(Offset(p0.x, p0.y), Offset(p1.x, p1.y), paint);
      }
      return;
    }

    // Brush
    if (stroke.toolType == 'brush') {
      final interp = _catmullRomInterpolateSymbol(stroke.points);
      for (int layer = 0; layer < 3; layer++) {
        final alpha = (stroke.opacity * (0.3 - layer * 0.08)).clamp(0.05, 1.0);
        final widthMul = 1.0 + layer * 0.6;
        final paint = Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
        for (int i = 0; i < interp.length - 1; i++) {
          final p0 = interp[i];
          final p1 = interp[i + 1];
          final avgP = (p0.pressure + p1.pressure) / 2;
          paint.strokeWidth = stroke.baseWidth * widthMul * (0.2 + avgP * 0.8);
          canvas.drawLine(Offset(p0.x, p0.y), Offset(p1.x, p1.y), paint);
        }
      }
      return;
    }

    // Fountain pen (default). MUST mirror the width formula in
    // render_engine.dart's _paintStroke exactly — this used to be an
    // independently-hand-tuned copy (old pressure/velocity constants),
    // so a symbol's rendered thickness visibly diverged from the same
    // stroke drawn live on the canvas. Keep these two in sync.
    final n = stroke.points.length;

    // Velocity in PAGE-UNITS PER SECOND, normalised across input rates.
    final velocities = List<double>.filled(n, 0.0);
    for (int i = 1; i < n; i++) {
      final dx = stroke.points[i].x - stroke.points[i - 1].x;
      final dy = stroke.points[i].y - stroke.points[i - 1].y;
      final dt = stroke.points[i].timestamp - stroke.points[i - 1].timestamp;
      final dtMs = dt < 1 ? 1 : dt;
      velocities[i] = sqrt(dx * dx + dy * dy) * 1000.0 / dtMs;
    }
    if (n > 1) velocities[0] = velocities[1];

    for (int i = 1; i < n - 1; i++) {
      velocities[i] = (velocities[i - 1] + velocities[i] * 2 + velocities[i + 1]) / 4;
    }

    final rawWidths = List<double>.filled(n, stroke.baseWidth);
    for (int i = 0; i < n; i++) {
      final excessV = (velocities[i] - 800.0).clamp(0.0, 4000.0);
      final velocityFactor = 1.0 - (excessV / 4000.0) * 0.15;
      final pc = sqrt(stroke.points[i].pressure.clamp(0.0, 1.0));
      final pressureFactor = 0.35 + pc * 1.15;
      rawWidths[i] = stroke.baseWidth * pressureFactor * velocityFactor;
    }
    for (int pass = 0; pass < 2; pass++) {
      for (int i = 1; i < n - 1; i++) {
        rawWidths[i] = (rawWidths[i - 1] + rawWidths[i] * 2 + rawWidths[i + 1]) / 4;
      }
    }

    final interp = _catmullRomAdaptiveWithWidthSymbol(stroke.points, rawWidths);
    if (interp.length < 2) return;

    // Render as filled outline polygon for smooth edges.
    final count = interp.length;
    final nxArr = List<double>.filled(count, 0.0);
    final nyArr = List<double>.filled(count, 0.0);
    for (int i = 0; i < count; i++) {
      double dx, dy;
      if (i == 0) {
        dx = interp[1].$1 - interp[0].$1;
        dy = interp[1].$2 - interp[0].$2;
      } else if (i == count - 1) {
        dx = interp[i].$1 - interp[i - 1].$1;
        dy = interp[i].$2 - interp[i - 1].$2;
      } else {
        dx = interp[i + 1].$1 - interp[i - 1].$1;
        dy = interp[i + 1].$2 - interp[i - 1].$2;
      }
      final len = sqrt(dx * dx + dy * dy);
      if (len > 0.0001) {
        nxArr[i] = -dy / len;
        nyArr[i] = dx / len;
      } else if (i > 0) {
        nxArr[i] = nxArr[i - 1];
        nyArr[i] = nyArr[i - 1];
      }
    }

    final path = Path();
    final hw0 = (interp[0].$4 * 0.5).clamp(0.2, 999.0);

    // Right edge (forward)
    path.moveTo(
      interp[0].$1 + nxArr[0] * hw0,
      interp[0].$2 + nyArr[0] * hw0,
    );
    for (int i = 1; i < count; i++) {
      final hw = (interp[i].$4 * 0.5).clamp(0.2, 999.0);
      path.lineTo(
        interp[i].$1 + nxArr[i] * hw,
        interp[i].$2 + nyArr[i] * hw,
      );
    }

    // Left edge (backward) — straight connection at the end
    for (int i = count - 1; i >= 0; i--) {
      final hw = (interp[i].$4 * 0.5).clamp(0.2, 999.0);
      path.lineTo(
        interp[i].$1 - nxArr[i] * hw,
        interp[i].$2 - nyArr[i] * hw,
      );
    }
    path.close();

    final fillPaint = Paint()
      ..color = color.withValues(alpha: stroke.opacity)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(path, fillPaint);

    // Round endpoint circles
    canvas.drawCircle(
      Offset(interp.first.$1, interp.first.$2),
      hw0,
      fillPaint,
    );
    final lastHw = (interp.last.$4 * 0.5).clamp(0.2, 999.0);
    canvas.drawCircle(
      Offset(interp.last.$1, interp.last.$2),
      lastHw,
      fillPaint,
    );
  }

  List<StrokePoint> _catmullRomInterpolateSymbol(List<StrokePoint> points) {
    if (points.length < 4) return points;
    final result = <StrokePoint>[];
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : points[i + 1];
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      final dist = sqrt(dx * dx + dy * dy);
      final segments = dist < 2 ? 2 : dist < 8 ? 4 : dist < 20 ? 6 : 8;
      for (int j = 0; j < segments; j++) {
        final t = j / segments;
        final t2 = t * t;
        final t3 = t2 * t;
        final x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3);
        final y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);
        final pressure = p1.pressure + (p2.pressure - p1.pressure) * t;
        result.add(StrokePoint(x: x, y: y, pressure: pressure));
      }
    }
    result.add(points.last);
    return result;
  }

  /// Adaptive Catmull-Rom with width for symbol rasterization.
  /// Returns list of (x, y, pressure, width) tuples.
  List<(double, double, double, double)> _catmullRomAdaptiveWithWidthSymbol(
      List<StrokePoint> points, List<double> widths) {
    if (points.length < 4) {
      return List.generate(points.length, (i) =>
          (points[i].x, points[i].y, points[i].pressure, widths[i]));
    }
    final result = <(double, double, double, double)>[];
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : points[i + 1];
      final w1 = widths[i];
      final w2 = widths[i + 1];
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      final dist = sqrt(dx * dx + dy * dy);
      final segments = dist < 2 ? 2 : dist < 8 ? 4 : dist < 20 ? 6 : 8;
      for (int j = 0; j < segments; j++) {
        final t = j / segments;
        final t2 = t * t;
        final t3 = t2 * t;
        final x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3);
        final y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);
        final w = w1 + (w2 - w1) * t;
        result.add((x, y, p1.pressure + (p2.pressure - p1.pressure) * t, w));
      }
    }
    result.add((points.last.x, points.last.y, points.last.pressure, widths.last));
    return result;
  }

  void _paintTextSymbol(Canvas canvas, TextData textData) {
    final style = ui.TextStyle(
      color: Color(textData.color),
      fontSize: textData.fontSize,
      fontFamily: textData.fontFamily,
      fontWeight: textData.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: textData.italic ? FontStyle.italic : FontStyle.normal,
    );
    final paragraphStyle = ui.ParagraphStyle(
      textAlign: textData.alignment == 'center'
          ? TextAlign.center
          : textData.alignment == 'right'
              ? TextAlign.right
              : TextAlign.left,
    );
    final builder = ui.ParagraphBuilder(paragraphStyle)..pushStyle(style)..addText(textData.content);
    final paragraph = builder.build()..layout(ui.ParagraphConstraints(width: textData.width));
    canvas.drawParagraph(paragraph, Offset(textData.x, textData.y));
  }

  void _paintImageSymbol(Canvas canvas, ImageData imageData) {
    final cachedImage = state?.imageCache[imageData.assetPath];
    if (cachedImage == null) return;

    canvas.save();
    if (imageData.rotation != 0) {
      final cx = imageData.x + imageData.width / 2;
      final cy = imageData.y + imageData.height / 2;
      canvas.translate(cx, cy);
      canvas.rotate(imageData.rotation);
      canvas.translate(-cx, -cy);
    }

    final srcRect = Rect.fromLTWH(0, 0, cachedImage.width.toDouble(), cachedImage.height.toDouble());
    final dstRect = Rect.fromLTWH(imageData.x, imageData.y, imageData.width, imageData.height);
    final paint = Paint()..color = Colors.white.withValues(alpha: imageData.opacity);
    canvas.drawImageRect(cachedImage, srcRect, dstRect, paint);
    canvas.restore();
  }

  void _paintShapeSymbol(Canvas canvas, ShapeData shape) {
    final strokePaint = Paint()
      ..color = Color(shape.strokeColor)
      ..style = PaintingStyle.stroke
      ..strokeWidth = shape.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    Paint? fillPaint;
    if (shape.fillColor != null) {
      fillPaint = Paint()..color = Color(shape.fillColor!)..style = PaintingStyle.fill;
    }

    canvas.save();
    if (shape.rotation != 0) {
      final cx = (shape.x1 + shape.x2) / 2;
      final cy = (shape.y1 + shape.y2) / 2;
      canvas.translate(cx, cy);
      canvas.rotate(shape.rotation);
      canvas.translate(-cx, -cy);
    }

    switch (shape.shapeType) {
      case 'rectangle':
        final rect = Rect.fromPoints(Offset(shape.x1, shape.y1), Offset(shape.x2, shape.y2));
        if (fillPaint != null) canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, strokePaint);
        break;
      case 'circle':
        final center = Offset((shape.x1 + shape.x2) / 2, (shape.y1 + shape.y2) / 2);
        final radius = Offset(shape.x2 - shape.x1, shape.y2 - shape.y1).distance / 2;
        if (fillPaint != null) canvas.drawCircle(center, radius, fillPaint);
        canvas.drawCircle(center, radius, strokePaint);
        break;
      case 'line':
      case 'arrow':
        canvas.drawLine(Offset(shape.x1, shape.y1), Offset(shape.x2, shape.y2), strokePaint);
        break;
      case 'triangle':
        final tLeft = min(shape.x1, shape.x2);
        final tRight = max(shape.x1, shape.x2);
        final tTop = min(shape.y1, shape.y2);
        final tBottom = max(shape.y1, shape.y2);
        final tPath = Path()
          ..moveTo((tLeft + tRight) / 2, tTop)
          ..lineTo(tLeft, tBottom)
          ..lineTo(tRight, tBottom)
          ..close();
        if (fillPaint != null) canvas.drawPath(tPath, fillPaint);
        canvas.drawPath(tPath, strokePaint);
        break;
      default:
        canvas.drawRect(Rect.fromPoints(Offset(shape.x1, shape.y1), Offset(shape.x2, shape.y2)), strokePaint);
    }
    canvas.restore();
  }

  // ── Page management ──

  /// Replace a PageEntry whose PageData is missing with a fresh blank page.
  ///
  /// Used to recover from server-side corruption: when the delta folder
  /// references page files that were never uploaded (or were deleted), the
  /// notebook is permanently stuck with "Nessuna pagina" on the affected
  /// pages and no amount of re-syncing will restore them.  This method
  /// replaces the missing entry with a blank PageData so the user can at
  /// least continue to use the notebook; subsequent save() re-uploads the
  /// fresh blank page to the server, ending the corruption cycle.
  ///
  /// Caller is expected to trigger save() afterwards (or let auto-save fire).
  bool repairMissingPageData(int docIndex) {
    if (state == null) return false;
    final s = state!;
    if (docIndex < 0 || docIndex >= s.document.pages.length) return false;
    final entry = s.document.pages[docIndex];
    // Only repair if data is genuinely missing — do not clobber real content.
    if (s.pages.containsKey(entry.fileName)) return false;

    final now = DateTime.now();
    // Inherit background from the surrounding page so the visual style of
    // the notebook stays consistent.
    final referencePage = s.pages.isNotEmpty ? s.pages.values.first : null;
    final bgType = referencePage?.layers.background.type ?? 'blank';
    final lineSpacing = referencePage?.layers.background.lineSpacing ?? 30.0;
    final width = referencePage?.width ?? AppConfig.defaultPageWidth;
    final height = referencePage?.height ?? AppConfig.defaultPageHeight;

    final blank = PageData(
      pageId: entry.pageId,
      pageNumber: entry.pageNumber,
      width: width,
      height: height,
      layers: RenderingLayers(
        background: BackgroundLayer(type: bgType, lineSpacing: lineSpacing),
        content: const [],
      ),
      createdAt: now,
      modifiedAt: now,
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    // `blank` is a brand-new object, so _saveInner's identity diff against
    // _lastSyncedPages already flags it — the next save() pushes the blank
    // page and clears the server-side gap.
    updatedPages[entry.fileName] = blank;

    state = s.copyWith(pages: updatedPages, isDirty: true);
    print('[Canvas] repairMissingPageData: restored ${entry.fileName} '
        'as blank at index $docIndex');
    return true;
  }

  /// Count how many PageEntries in the current document reference a
  /// fileName whose PageData is missing from [state.pages].
  int missingPageCount() {
    final s = state;
    if (s == null) return 0;
    var count = 0;
    for (final entry in s.document.pages) {
      if (!s.pages.containsKey(entry.fileName)) count++;
    }
    return count;
  }

  /// Heal every page whose data is missing. Returns the number of pages
  /// that were replaced with a blank.
  int repairAllMissingPages() {
    final s = state;
    if (s == null) return 0;
    var repaired = 0;
    for (int i = 0; i < s.document.pages.length; i++) {
      if (!state!.pages.containsKey(s.document.pages[i].fileName)) {
        if (repairMissingPageData(i)) repaired++;
      }
    }
    return repaired;
  }

  void deletePage(int index) {
    if (state == null || state!.pageCount <= 1) return;
    final s = state!;
    if (index < 0 || index >= s.document.pages.length) return;
    final entry = s.document.pages[index];
    final fileName = entry.fileName;
    final deletedPageId = entry.pageId;

    final newPages = List<PageEntry>.from(s.document.pages)..removeAt(index);
    // Renumber pages (preserve all fields including chapterId)
    for (int i = 0; i < newPages.length; i++) {
      newPages[i] = newPages[i].copyWith(pageNumber: i + 1);
    }

    final updatedDoc = DocumentStructure(
      notebookId: s.document.notebookId,
      formatVersion: s.document.formatVersion,
      pages: newPages,
    );

    // Purge the deleted page's pageId from every chapter.pageIds list so
    // we don't leave dead references in metadata.chapters. These were
    // never fatal (the document is authoritative for navigation) but
    // accumulated over time as garbage and confused the heal path on
    // other devices.
    final cleanedChapters = s.metadata.chapters
        .map((c) => c.copyWith(
              pageIds: c.pageIds.where((pid) => pid != deletedPageId).toList(),
            ))
        .toList();
    final cleanedMeta = s.metadata.copyWith(
      chapters: cleanedChapters,
      pageCount: newPages.length,
      modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages)..remove(fileName);
    // Keep the user on the page they were viewing (the page manager can
    // delete an arbitrary index, not just the current one): indices after
    // the deleted page shift down by one; if the current page itself was
    // deleted, stay at the same position (now the following page).
    int newIndex = s.currentPageIndex > index
        ? s.currentPageIndex - 1
        : s.currentPageIndex;
    if (newIndex >= newPages.length) newIndex = newPages.length - 1;
    if (newIndex < 0) newIndex = 0;

    // If a chapter filter is active, the naive "stay at same index" rule
    // can land on a page outside the active chapter (the page-indicator
    // then reads "— / N"). Snap to a page that still belongs to the
    // chapter — the previous one within it, or the first one — and only
    // fall back to the global index if the chapter became empty.
    String? newActiveChapterId = s.activeChapterId;
    if (newActiveChapterId != null) {
      final chapterPagesInUnfiltered = <int>[
        for (int i = 0; i < newPages.length; i++)
          if (newPages[i].chapterId == newActiveChapterId) i,
      ];
      if (chapterPagesInUnfiltered.isNotEmpty) {
        // Only re-snap when the adjusted index fell outside the chapter.
        // Prefer the closest earlier page within the chapter; otherwise
        // the first one. Keeps the user near where they were.
        if (!chapterPagesInUnfiltered.contains(newIndex)) {
          final prior = chapterPagesInUnfiltered
              .where((i) => i < newIndex)
              .toList();
          newIndex =
              prior.isNotEmpty ? prior.last : chapterPagesInUnfiltered.first;
        }
      } else {
        // Chapter has no pages left — drop the filter so the nav isn't
        // stuck showing "— / 0".
        newActiveChapterId = null;
      }
    }

    final clearChapter = newActiveChapterId == null && s.activeChapterId != null;
    state = s.copyWith(
      document: updatedDoc,
      pages: updatedPages,
      currentPageIndex: newIndex,
      // Drop undo/redo entries for the deleted page: undo would put its
      // PageData back into the pages map without a document entry — an
      // orphan the heal then resurrects. Deletion is declared
      // non-undoable in the UI, so the stacks must agree.
      undoStack:
          s.undoStack.where((e) => e.pageFileName != fileName).toList(),
      redoStack:
          s.redoStack.where((e) => e.pageFileName != fileName).toList(),
      // Deletion shifts all subsequent indices; the previously-tracked
      // page index would now point to a different page. Drop it so the
      // bottom-strip "↺ previous" badge doesn't mislead the user.
      clearPreviousPage: true,
      activeChapterId: clearChapter ? null : newActiveChapterId,
      clearActiveChapter: clearChapter,
      metadata: cleanedMeta,
      isDirty: true,
    );
  }

  /// Delete multiple pages in a single state update.
  ///
  /// [docIndices] are absolute document indices (not filtered/visible indices).
  /// Must contain at least one index and must not delete ALL pages if only one
  /// page remains.
  void deletePages(List<int> docIndices) {
    if (state == null) return;
    final s = state!;
    if (docIndices.isEmpty) return;
    // Never delete the last page
    final effective = docIndices.where((i) => i >= 0 && i < s.document.pages.length).toList();
    if (effective.isEmpty) return;
    if (s.pageCount - effective.length < 1) {
      // Keep at least one page — remove excess from deletion list
      effective.sort();
      effective.removeLast(); // keep the last one
      if (effective.isEmpty) return;
    }

    final indicesToRemove = effective.toSet();
    final removedFileNames = indicesToRemove.map((i) => s.document.pages[i].fileName).toSet();
    final removedPageIds = indicesToRemove.map((i) => s.document.pages[i].pageId).toSet();

    final newPages = <PageEntry>[];
    for (int i = 0; i < s.document.pages.length; i++) {
      if (!indicesToRemove.contains(i)) {
        newPages.add(s.document.pages[i].copyWith(pageNumber: newPages.length + 1));
      }
    }

    final updatedDoc = DocumentStructure(
      notebookId: s.document.notebookId,
      formatVersion: s.document.formatVersion,
      pages: newPages,
    );
    final updatedPagesMap = Map<String, PageData>.from(s.pages)
      ..removeWhere((k, _) => removedFileNames.contains(k));

    // Keep the user on the page they were viewing: shift by the number of
    // deleted pages that preceded it, then clamp to the shrunken list.
    int newIndex = s.currentPageIndex -
        indicesToRemove.where((i) => i < s.currentPageIndex).length;
    if (newIndex >= newPages.length) newIndex = newPages.length - 1;
    if (newIndex < 0) newIndex = 0;

    String? newActiveChapterId = s.activeChapterId;
    if (newActiveChapterId != null) {
      final chapterPages = [
        for (int i = 0; i < newPages.length; i++)
          if (newPages[i].chapterId == newActiveChapterId) i,
      ];
      if (chapterPages.isEmpty) {
        newActiveChapterId = null;
      } else if (!chapterPages.contains(newIndex)) {
        newIndex = chapterPages.first;
      }
    }

    // Purge dead pageIds from every chapter (same reason as deletePage).
    final cleanedChapters = s.metadata.chapters
        .map((c) => c.copyWith(
              pageIds: c.pageIds.where((pid) => !removedPageIds.contains(pid)).toList(),
            ))
        .toList();

    final clearChapter = newActiveChapterId == null && s.activeChapterId != null;
    state = s.copyWith(
      document: updatedDoc,
      pages: updatedPagesMap,
      currentPageIndex: newIndex,
      // Same as deletePage: purge undo/redo entries for deleted pages or
      // undo restores them as document-less orphans.
      undoStack: s.undoStack
          .where((e) => !removedFileNames.contains(e.pageFileName))
          .toList(),
      redoStack: s.redoStack
          .where((e) => !removedFileNames.contains(e.pageFileName))
          .toList(),
      // Bulk deletion invalidates any prior "previous page" reference.
      clearPreviousPage: true,
      activeChapterId: clearChapter ? null : newActiveChapterId,
      clearActiveChapter: clearChapter,
      metadata: s.metadata.copyWith(
        pageCount: newPages.length,
        modifiedAt: DateTime.now(),
        chapters: cleanedChapters,
      ),
      isDirty: true,
    );
  }

  /// Assign multiple pages to a chapter (or clear their chapter) in a single
  /// state update.
  void assignPagesToChapter(List<int> docIndices, String? chapterId) {
    if (state == null) return;
    final s = state!;
    if (docIndices.isEmpty) return;
    final indicesSet = docIndices.toSet();
    final pages = List<PageEntry>.from(s.document.pages);
    for (final i in indicesSet) {
      if (i >= 0 && i < pages.length) {
        pages[i] = pages[i].copyWith(chapterId: chapterId);
      }
    }
    state = s.copyWith(
      document: s.document.copyWith(pages: pages),
      isDirty: true,
    );
  }

  void duplicatePage(int index) {
    if (state == null) return;
    final s = state!;
    if (index < 0 || index >= s.document.pages.length) return;
    final entry = s.document.pages[index];
    final sourcePage = s.pages[entry.fileName];
    if (sourcePage == null) return;

    const uuid = Uuid();
    final pageId = uuid.v4();
    final now = DateTime.now();
    final pageNum = s.pageCount + 1;
    final fileName = _nextPageFileName(s);

    final newPage = PageData(
      pageId: pageId, pageNumber: pageNum,
      width: sourcePage.width, height: sourcePage.height,
      layers: RenderingLayers(
        background: sourcePage.layers.background,
        content: sourcePage.layers.content.map((e) {
          final newId = uuid.v4();
          return e.map(
            stroke: (e) => ContentElement.stroke(id: newId, zIndex: e.zIndex, data: e.data),
            text: (e) => ContentElement.text(id: newId, zIndex: e.zIndex, data: e.data),
            image: (e) => ContentElement.image(id: newId, zIndex: e.zIndex, data: e.data),
            shape: (e) => ContentElement.shape(id: newId, zIndex: e.zIndex, data: e.data),
            math: (e) => ContentElement.math(id: newId, zIndex: e.zIndex, data: e.data),
          );
        }).toList(),
      ),
      createdAt: now, modifiedAt: now,
    );

    final newEntry = PageEntry(pageId: pageId, pageNumber: pageNum, fileName: fileName, lastModified: now, chapterId: entry.chapterId);

    final updatedDoc = DocumentStructure(
      notebookId: s.document.notebookId,
      formatVersion: s.document.formatVersion,
      pages: [...s.document.pages, newEntry],
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = newPage;

    state = s.copyWith(
      document: updatedDoc,
      pages: updatedPages,
      currentPageIndex: pageNum - 1,
      metadata: s.metadata.copyWith(pageCount: pageNum, modifiedAt: now),
      isDirty: true,
    );
  }

  void reorderPage(int oldIndex, int newIndex) {
    if (state == null) return;
    final s = state!;
    final pages = List<PageEntry>.from(s.document.pages);
    if (oldIndex < 0 || oldIndex >= pages.length) return;
    final entry = pages.removeAt(oldIndex);
    pages.insert(newIndex.clamp(0, pages.length), entry);

    // Renumber
    for (int i = 0; i < pages.length; i++) {
      pages[i] = pages[i].copyWith(pageNumber: i + 1);
    }

    final updatedDoc = DocumentStructure(
      notebookId: s.document.notebookId,
      formatVersion: s.document.formatVersion,
      pages: pages,
    );

    // Adjust current page index to follow the page that was being viewed
    int newCurrentIndex = s.currentPageIndex;
    if (s.currentPageIndex == oldIndex) {
      newCurrentIndex = newIndex;
    } else if (oldIndex < s.currentPageIndex && newIndex >= s.currentPageIndex) {
      newCurrentIndex--;
    } else if (oldIndex > s.currentPageIndex && newIndex <= s.currentPageIndex) {
      newCurrentIndex++;
    }

    state = s.copyWith(document: updatedDoc, currentPageIndex: newCurrentIndex, isDirty: true);
  }

  /// Move a set of pages (possibly non-contiguous) so that the first moved
  /// page lands at final 1-based position [targetPosition]. Complements
  /// drag-and-drop, which is impractical for long-distance moves in big
  /// notebooks.
  void movePagesToPosition(List<int> docIndices, int targetPosition) {
    if (state == null) return;
    final s = state!;
    final validSet = docIndices
        .where((i) => i >= 0 && i < s.document.pages.length)
        .toSet();
    if (validSet.isEmpty) return;
    final valid = validSet.toList()..sort();

    final currentPageId = s.document.pages[s.currentPageIndex].pageId;

    final moved = [for (final i in valid) s.document.pages[i]];
    final remaining = [
      for (int i = 0; i < s.document.pages.length; i++)
        if (!validSet.contains(i)) s.document.pages[i],
    ];
    // "Position N" means: after the move, the first moved page is page N.
    final insertAt = (targetPosition - 1).clamp(0, remaining.length);
    final pages = [...remaining]..insertAll(insertAt, moved);

    for (int i = 0; i < pages.length; i++) {
      pages[i] = pages[i].copyWith(pageNumber: i + 1);
    }

    final newCurrentIndex =
        pages.indexWhere((e) => e.pageId == currentPageId);

    state = s.copyWith(
      document: DocumentStructure(
        notebookId: s.document.notebookId,
        formatVersion: s.document.formatVersion,
        pages: pages,
      ),
      currentPageIndex: newCurrentIndex < 0 ? s.currentPageIndex : newCurrentIndex,
      metadata: s.metadata.copyWith(modifiedAt: DateTime.now()),
      isDirty: true,
    );
  }

  // ── Clear page ──

  void clearPage() {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final undoStack = _pushUndo(s, fileName, page);

    final clearedPage = PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: const []),
      assetReferences: page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = clearedPage;

    state = s.copyWith(pages: updatedPages, undoStack: undoStack, redoStack: [], isDirty: true);
  }

  // ── Select all elements ──

  void selectAll() {
    if (state == null) return;
    final page = state!.currentPage;
    if (page == null || page.layers.content.isEmpty) return;

    final allIds = page.layers.content.map((e) {
      return e.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
    }).toList();

    Rect? bounds;
    for (final element in page.layers.content) {
      final b = _getElementBounds(element);
      if (b != null) bounds = bounds == null ? b : bounds.expandToInclude(b);
    }

    if (bounds == null) return;
    state = state!.copyWith(
      lassoSelection: LassoSelection(selectedIds: allIds, bounds: bounds),
      currentTool: CanvasTool.lasso,
    );
  }

  // ── Reset zoom ──

  void resetZoom() {
    if (state == null) return;
    state = state!.copyWith(zoom: 2.0, panOffset: _centeredPanOffset(2.0));
  }

  /// Fit the current page vertically into the viewport. Computes the zoom
  /// that makes the full page height visible at once + horizontally centers
  /// the page. Bound to the double-tap gesture on the canvas.
  void zoomToFit() {
    final s = state;
    final vp = _viewportSize;
    if (s == null || vp == null) return;
    final page = s.currentPage;
    if (page == null) return;
    // Fit entire page height with a small margin; width fits automatically
    // because pages are narrower than the viewport on desktop/iPad.
    const margin = 24.0;
    final zoomH = (vp.height - margin * 2) / page.height;
    final zoomW = (vp.width - margin * 2) / page.width;
    final target = zoomH < zoomW ? zoomH : zoomW;
    final newZoom = target.clamp(0.3, 5.0);
    // Horizontally center: same rule as _centeredPanOffset but with margin.
    final panX = (vp.width - page.width * newZoom) / 2;
    final panY = (vp.height - page.height * newZoom) / 2;
    state = s.copyWith(
      zoom: newZoom,
      panOffset: Offset(panX, panY),
    );
  }

  Future<void> save() async {
    if (state == null) return;
    // Run even when not dirty if a delete queue is pending: a delete-only
    // save that failed remotely leaves isDirty false, and without this the
    // queued DELETEs would wait for an unrelated edit to be retried.
    final hasPendingDeletes =
        _pendingPageDeletes.isNotEmpty || _pendingAssetDeletes.isNotEmpty;
    if (!state!.isDirty && !hasPendingDeletes) return;
    final token = await _acquireSyncLock();
    if (token == null || state == null) return;
    bool lockTransferred = false;
    try {
      lockTransferred = await _saveInner(token);
    } finally {
      if (!lockTransferred) _releaseSyncLock(token);
    }
  }

  /// Performs local save synchronously, then hands the sync lock to a
  /// background task that uploads to the server.
  ///
  /// Returns `true` if the background task has taken ownership of the
  /// sync lock (caller must NOT release it). Returns `false` if the
  /// caller must release the lock itself (nothing scheduled).
  Future<bool> _saveInner(int lockToken) async {
    if (state == null || !state!.isDirty) return false;

    // ── Pre-flight integrity guard ──
    //
    // If `state.pages` holds page data for a fileName that
    // `state.document` doesn't reference, uploading the document as-is
    // would propagate the inconsistency to the server and cause every
    // other device pulling next to lose those pages from the navigator.
    // Repair in-state FIRST (heal preserves chapterId via
    // metadata.chapters[].pageIds), then save the consistent state.
    //
    // This is the brake that breaks the corruption cycle even when an
    // older client version is still running on another machine — the
    // save path on THIS device refuses to publish a document that is
    // demonstrably less complete than the local pages map.
    {
      final cur = state!;
      final docFns = cur.document.pages.map((p) => p.fileName).toSet();
      final missing = cur.pages.keys.where((fn) => !docFns.contains(fn)).toList();
      if (missing.isNotEmpty) {
        print('[Canvas] PRE-SAVE GUARD: state.pages has ${missing.length} '
            'fileNames not in state.document — running heal before upload');
        _healOrphanedPagesInState();
      }
    }

    // ── Pre-save integrity guard #2 ──
    //
    // Reject the save if the document references pages whose data isn't in
    // memory (state.pages). A previous partial pull can leave us with
    // `document.pages.length > state.pages.length`; if save() ships that
    // state, syncDelta writes a document.json listing pages whose bytes
    // we'd upload with old content (or not at all), silently corrupting
    // every other device's view. Abort and let the next pull re-hydrate
    // instead.
    {
      final cur = state!;
      final missingData = cur.document.pages
          .where((e) => !cur.pages.containsKey(e.fileName))
          .toList();
      if (missingData.isNotEmpty) {
        final sample = missingData.take(3).map((e) => e.fileName).join(', ');
        // Abort rate-limit: each abort kicks a pull, and on pathologically
        // broken state that pull can't fix it, repeating forever. After
        // _maxPreSaveGuardAborts aborts inside _preSaveGuardWindow we STOP
        // kicking pulls — the next user-initiated save / pull-timer tick
        // will retry naturally, with no chance of a save↔abort↔pull loop.
        final now = DateTime.now();
        if (_preSaveGuardSince == null ||
            now.difference(_preSaveGuardSince!) > _preSaveGuardWindow) {
          _preSaveGuardSince = now;
          _preSaveGuardAborts = 0;
        }
        _preSaveGuardAborts++;
        final triggerPull = _preSaveGuardAborts <= _maxPreSaveGuardAborts;
        print('[Canvas] PRE-SAVE GUARD #2: aborting — document has '
            '${missingData.length} entries without page data '
            '($sample${missingData.length > 3 ? "..." : ""})'
            '${triggerPull ? ". Triggering pull to re-hydrate first." : " (rate-limited: $_preSaveGuardAborts in ${_preSaveGuardWindow.inSeconds}s — not kicking another pull)."}');
        unawaited(CrashLogger.append(
          '[Save] aborted: doc=${cur.document.pages.length} > '
          'pages=${cur.pages.length} (missing: $sample) '
          'guard#$_preSaveGuardAborts pull=$triggerPull',
        ));
        if (triggerPull) {
          unawaited(_pullRemoteChanges());
        }
        return false;
      }
    }

    // ── Compact orphan assets only when pages were deleted this save ──
    // Running prune on every save is unsafe: during pull/cross-device
    // races, transient state can mark assets as orphan that another
    // device still uses → mass DELETE + cross-device ping-pong. Gating
    // it to "this save deleted at least one page" matches the actual
    // user intent (re-import / page deletion) without firing spuriously.
    // _pruneOrphanAssets is called below, AFTER deletedPages is computed.

    final s = state!;
    final syncService = _ref.read(syncServiceProvider);
    final fileService = _ref.read(fileServiceProvider);
    if (syncService == null) return false;

    // Always derive pageCount from the live document so the DB is never
    // left with a stale count (e.g. after an auto-accept stamped the
    // server's old count onto metadata).
    final updatedMeta = s.metadata.copyWith(
      modifiedAt: DateTime.now(),
      pageCount: s.document.pages.length,
    );

    // ── Detect which pages actually changed (identity comparison) ──
    final changedPages = <String, PageData>{};

    for (final entry in s.pages.entries) {
      if (!identical(entry.value, _lastSyncedPages[entry.key])) {
        changedPages[entry.key] = entry.value;
      }
    }
    // Also detect new pages (added since last sync)
    for (final key in s.pages.keys) {
      if (!_lastSyncedPages.containsKey(key)) {
        changedPages[key] = s.pages[key]!;
      }
    }

    // Detect changed assets
    final changedAssets = <String, Uint8List>{};
    for (final key in _dirtyAssetKeys) {
      if (s.assetBytes.containsKey(key)) {
        changedAssets[key] = s.assetBytes[key]!;
      }
    }

    // Detect deleted pages (existed in last sync but no longer in current state)
    final deletedPages = <String>[];
    for (final key in _lastSyncedPages.keys) {
      if (!s.pages.containsKey(key)) {
        deletedPages.add(key);
      }
    }
    // Stage into the persistent pending queue so a thrown remote sync
    // doesn't lose the deletion request — _remoteSync merges these and
    // clears them on confirmed success.
    _pendingPageDeletes.addAll(deletedPages);

    // Drop pending DELETEs that conflict with what we're about to PUT.
    // Without this guard, Phase 0 of syncDelta (DELETE) fires in
    // parallel with Phase 1 (PUT) — a stale pending delete for
    // page_010.json could race the new page_010.json PUT and leave the
    // server without the just-uploaded content. _nextPageFileName
    // reuses numeric suffixes after deletion, so this collision is
    // realistic when the user re-imports a PDF after deleting the prior.
    if (changedPages.isNotEmpty) {
      _pendingPageDeletes.removeWhere((fn) => changedPages.containsKey(fn));
    }
    if (changedAssets.isNotEmpty) {
      _pendingAssetDeletes.removeWhere((id) => changedAssets.containsKey(id));
    }

    // Now it's safe to compact orphan assets: we have a stable view of
    // which pages were just deleted, and we only run prune at all when
    // the user actually removed something this save (avoids racing pull).
    if (deletedPages.isNotEmpty) {
      _pruneOrphanAssets();
      // Persist the pending queue EAGERLY, not only in the remote-sync
      // success path: if the upload fails (offline) and the app dies
      // before the next successful save, an unpersisted delete is lost
      // and the page resurrects from the server on the next pull.
      unawaited(_persistPendingDeletes(s.metadata.id));
    }

    debugPrint('[Canvas] Dirty: ${changedPages.length} pages, '
        '${changedAssets.length} assets, ${deletedPages.length} deleted');

    // 1. Update state IMMEDIATELY so the UI unblocks on this microtask.
    //    The remote delta sync and the local ZIP write run in parallel in
    //    the background while we return control to the caller.
    if (state != null) {
      final changedDuringSave = !identical(state!.pages, s.pages);
      state = state!.copyWith(
        metadata: updatedMeta,
        isDirty: changedDuringSave,
      );
    }
    _saveLastPosition();

    // Capture a snapshot of the dirty assets so we can clear them only if
    // the remote commit succeeds. Doing this optimistically lost dirty
    // state when the upload failed halfway through the ordered commit.
    final snapshotDirtyAssetKeys = Set<String>.of(_dirtyAssetKeys);

    // 2b. Encode the dirty pages ONCE, up front. Both consumers reuse
    //     these bytes: syncDelta (which used to re-run compactPageJson
    //     internally) and the local ZIP build (cache hit by identity).
    //     Halves the main-thread JSON encode per save, and the encode
    //     respects the quiet-pointer gate so it can't kink a stroke.
    final preEncodedDirty =
        await _encodePagesWithCache(changedPages, evictMissing: false);

    // 3. Fire remote delta sync RIGHT NOW — it only needs the in-memory
    //    objects (changedPages + document + metadata), does not need the
    //    full .ncnote ZIP. Putting it ahead of the expensive
    //    compute(_buildPackageInIsolate) call is what makes small-stroke
    //    edits actually reach the server in ~seconds on Tailscale instead
    //    of waiting for the ZIP build to finish first.
    final remoteSyncFuture = _remoteSync(
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
    );

    // 4. Persist locally — INCREMENTALLY, into the per-page "loose store"
    //    (see FileService). A one-page edit writes ONE small page file instead
    //    of rebuilding + re-snapshotting the entire notebook ZIP, which on an
    //    asset-heavy notebook was ~232 MB of build + write + snapshot-copy on
    //    EVERY save (the periodic write-time hitch and pointless disk churn).
    //    The remote delta sync above already ships only the dirty pages; this
    //    brings the local copy to the same granularity. Runs in the background;
    //    never blocks the UI.
    final localSaveFuture = (() async {
      try {
        final metaJson =
            Uint8List.fromList(utf8.encode(jsonEncode(updatedMeta.toJson())));
        final docJson =
            Uint8List.fromList(utf8.encode(jsonEncode(s.document.toJson())));
        final hasSymbols = s.symbolLibraries.isNotEmpty;
        final symbolsJson = hasSymbols
            ? Uint8List.fromList(utf8.encode(
                jsonEncode(s.symbolLibraries.map((l) => l.toJson()).toList())))
            : null;

        if (await fileService.hasLooseStore(updatedMeta.id)) {
          // Steady state: patch only what changed.
          await fileService.saveNotebookIncremental(
            updatedMeta.id,
            metadataJson: metaJson,
            documentJson: docJson,
            changedPages: preEncodedDirty,
            changedAssets: changedAssets,
            deletedPages: deletedPages,
            symbolsJson: symbolsJson,
            removeSymbols: !hasSymbols,
          );
          debugPrint('[Canvas] Saved locally (incremental): '
              '${preEncodedDirty.length} pages, ${changedAssets.length} assets, '
              '${deletedPages.length} deleted');
        } else {
          // First save of a notebook with no loose store yet (brand-new, or a
          // legacy notebook on its first edit after this update): seed the
          // store with the FULL current in-memory state ONCE — guaranteed to
          // match what the user sees, no dependence on the legacy file's
          // freshness. Every subsequent save is then incremental.
          final allPages = await _encodePagesWithCache(s.pages);
          await fileService.saveNotebookIncremental(
            updatedMeta.id,
            metadataJson: metaJson,
            documentJson: docJson,
            changedPages: allPages,
            changedAssets: Map<String, Uint8List>.of(s.assetBytes),
            symbolsJson: symbolsJson,
            removeSymbols: !hasSymbols,
          );
          debugPrint('[Canvas] Seeded local store: ${allPages.length} pages, '
              '${s.assetBytes.length} assets');
        }

        // Keep the DB row fresh. Preserve the delta ETag — upsert uses
        // ConflictAlgorithm.replace, so omitting it would erase it and trigger
        // a stale re-download on the next library refresh.
        await fileService.upsertNotebookMeta(
          id: updatedMeta.id,
          title: updatedMeta.title,
          remotePath: s.remotePath,
          etag: _remoteMetaEtag,
          localModifiedAt: updatedMeta.modifiedAt,
          syncStatus: 'modified',
          fileSize: await fileService.looseStoreSize(updatedMeta.id),
          coverColor: updatedMeta.coverColor,
          paperType: updatedMeta.paperType,
          pageCount: updatedMeta.pageCount,
          createdAt: updatedMeta.createdAt,
        );
        return true;
      } catch (e) {
        debugPrint('[Canvas] Local save failed: $e');
        return false;
      }
    })();
    _pendingLocalSave = localSaveFuture;
    unawaited(localSaveFuture.whenComplete(() {
      if (identical(_pendingLocalSave, localSaveFuture)) {
        _pendingLocalSave = null;
      }
    }));

    // Fire-and-forget: refresh thumbnail for the library card. Uses the
    // first page of the document — failures are swallowed (cards fall
    // back to the gradient placeholder).
    () async {
      try {
        // Rendering the cover thumbnail records a full page paint on the
        // UI isolate — never do it while the pen is down.
        await _waitForQuietPointer();
        final thumbs = _ref.read(thumbnailServiceProvider);
        final firstPageEntry = s.document.pages.isNotEmpty
            ? s.document.pages.first
            : null;
        if (firstPageEntry == null) return;
        final firstPage = s.pages[firstPageEntry.fileName];
        if (firstPage == null) return;
        await thumbs.renderAndCache(
          updatedMeta.id,
          firstPage,
          imageCache: s.imageCache,
          // Pass the raw asset bytes too — if the canvas hasn't finished
          // decoding every image yet (e.g. save() fires right after open
          // on a notebook with many images), the thumbnail would render
          // blank rectangles where the images should be without this
          // fallback decode path.
          assetBytes: s.assetBytes,
        );
      } catch (e) {
        debugPrint('[Canvas] Thumbnail cache failed: $e');
      }
    }();

    // Hand the lock to a background task that waits for the remote sync
    // to finish (or fail), then releases the lock.
    //
    // Track the background task so closeNotebook() can await it.
    // Without this, the user can exit mid-upload and the sync ends up
    // half-committed on the server (pages uploaded, metadata.json never
    // rewritten), which the next pull then has to reconcile as a conflict.
    _pendingRemoteSave = () async {
      try {
        await remoteSyncFuture;
        // Remote commit succeeded — clear the failure streak so the
        // pill flips back from offline to pending/ok.
        if (_consecutiveSyncFailures > 0) {
          _consecutiveSyncFailures = 0;
          _recomputeSyncStatus();
        }
        // The full chain (pages + document + metadata) just landed,
        // so any pending metadata-only retry is now stale: the bytes
        // queued by an earlier failed save committed something the
        // server has since superseded. Drop the queue and reset the
        // exponential-backoff state.
        if (_pendingMetaCommitBytes != null) {
          _pendingMetaCommitBytes = null;
          _pendingMetaCommitTimer?.cancel();
          _pendingMetaCommitTimer = null;
          _metaRetryAttempts = 0;
          await _persistPendingMetaCommit(updatedMeta.id, null);
          _recomputeSyncStatus();
        }
        // Remote commit succeeded — NOW it's safe to advance the dirty
        // snapshot. If we do this optimistically (before remote returns),
        // a failed upload leaves _lastSyncedPages matching state.pages,
        // so the NEXT save() considers those pages 'already synced' via
        // identity check and never retries. That's how iPad drew strokes,
        // hit a commit-phase failure, and the strokes stayed invisible
        // to other devices even though iPad's local file had them.
        _lastSyncedPages = s.pages;
        // Advance the structure/metadata baselines to exactly what we just
        // uploaded (the `s` snapshot + the committed metadata), so the next
        // pull's 3-way merge treats THIS as the common ancestor.
        _lastSyncedDocument = s.document;
        _lastSyncedMetadata = updatedMeta;
        for (final k in snapshotDirtyAssetKeys) {
          _dirtyAssetKeys.remove(k);
          // Mark these asset IDs as having a server-side counterpart.
          // _pruneOrphanAssets uses this set to decide whether to queue
          // a server DELETE — a local-only asset (never uploaded) must
          // never produce a DELETE because the server might 404 forever
          // OR delete a totally unrelated file with the same name created
          // by another device.
          _uploadedAssetKeys.add(k);
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
        // metadata. Local _lastSyncedPages is intentionally NOT
        // advanced: the next save will retry the full chain, but the
        // metadata-only retry timer typically wins first.
        debugPrint('[Canvas] Remote sync: pages+document committed but '
            'metadata.json failed — staging for replay: $e');
        _pendingMetaCommitBytes = e.metadataBytes;
        await _persistPendingMetaCommit(updatedMeta.id, e.metadataBytes);
        _scheduleMetaCommitRetry();
        _consecutiveSyncFailures++;
        _recomputeSyncStatus();
        try {
          await fileService.markNotebookDirty(updatedMeta.id);
        } catch (_) {}
      } catch (e) {
        debugPrint('[Canvas] Remote sync deferred (offline?): $e');
        _consecutiveSyncFailures++;
        _recomputeSyncStatus();
        // Leave _lastSyncedPages and _dirtyAssetKeys untouched so the
        // failed pages are detected as dirty again on the next save.
        try {
          await fileService.markNotebookDirty(updatedMeta.id);
        } catch (_) {}
      } finally {
        _releaseSyncLock(lockToken);
      }
    }();
    // Clear the tracking slot when this particular save settles — a later
    // save() may have already replaced it, so only clear if still us.
    final thisRemoteSave = _pendingRemoteSave;
    unawaited(thisRemoteSave!.whenComplete(() {
      if (identical(_pendingRemoteSave, thisRemoteSave)) {
        _pendingRemoteSave = null;
      }
    }));
    return true;
  }

  Future<void> _remoteSync({
    required SyncService syncService,
    required dynamic fileService,
    required NotebookMetadata updatedMeta,
    required DocumentStructure document,
    required Map<String, PageData> dirtyPages,
    Map<String, Uint8List>? preEncodedPages,
    Map<String, Uint8List>? dirtyAssets,
    List<Map<String, dynamic>>? symbolLibraries,
    List<String>? deletedPages,
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
      _pendingPageDeletes.removeWhere((fn) => dirtyPages.containsKey(fn));
    }
    if (dirtyAssets != null && dirtyAssets.isNotEmpty) {
      _pendingAssetDeletes.removeWhere((id) => dirtyAssets.containsKey(id));
    }

    // Pending sets carry every delete request — both this save's and any
    // from prior saves whose DELETE drops on flaky networks (Tailscale).
    // Drain in CAPPED batches so a backlog of hundreds of orphans (can
    // happen after re-importing a PDF and re-deleting it on flaky links)
    // doesn't bloat every save into a multi-minute storm of DELETEs that
    // ties up the connection and starves the metadata commit phase.
    const int deleteBatchPerSave = 30;
    final mergedDeletedPages =
        _pendingPageDeletes.take(deleteBatchPerSave).toList();
    final mergedDeletedAssets =
        _pendingAssetDeletes.take(deleteBatchPerSave).toList();

    debugPrint('[Canvas] Starting delta sync: ${dirtyPages.length} pages '
        '(retrying ${_pendingPageDeletes.length} pending page deletes, '
        '${_pendingAssetDeletes.length} pending asset deletes)');
    final result = await syncService.syncDelta(
      notebookId: updatedMeta.id,
      metadata: updatedMeta,
      document: document,
      dirtyPages: dirtyPages,
      preEncodedPages: preEncodedPages,
      dirtyAssets: dirtyAssets,
      symbolLibraries: symbolLibraries,
      deletedPageFileNames: mergedDeletedPages.isNotEmpty
          ? mergedDeletedPages : null,
      deletedAssetFileNames: mergedDeletedAssets.isNotEmpty
          ? mergedDeletedAssets : null,
    );

    // Anything we asked the server to delete and didn't see a failure for
    // is now confirmed gone (or 404, which we treat as success). Drop those
    // from the pending sets; re-add anything that failed.
    final attemptedPageDeletes = mergedDeletedPages.toSet();
    final attemptedAssetDeletes = mergedDeletedAssets.toSet();
    _pendingPageDeletes
      ..removeAll(attemptedPageDeletes)
      ..addAll(result.failedPageDeletes);
    _pendingAssetDeletes
      ..removeAll(attemptedAssetDeletes)
      ..addAll(result.failedAssetDeletes);
    await _persistPendingDeletes(updatedMeta.id);

    _remoteMetaEtag = result.metaEtag;
    // Clear corrupt-ETag dedup entries for any page we just uploaded:
    // the server now has fresh bytes (with verified size — see
    // WebDavService.uploadFile), so the OLD truncated ETag we cached as
    // "skip the GET" is no longer authoritative. If the post-PUT
    // verification ever lets a bad upload slip through (it shouldn't,
    // but defensively), the next pull will FormatException again and
    // re-populate the dedup with the new ETag.
    for (final fn in result.pageEtags.keys) {
      _knownCorruptEtags.remove(fn);
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
      _lastPageEtags[entry.key] = entry.value;
    }
    // Purge deleted pages so the pull diff doesn't resurrect them.
    if (deletedPages != null) {
      for (final fn in deletedPages) {
        _lastPageEtags.remove(fn);
      }
    }
    await fileService.markNotebookSynced(updatedMeta.id, result.metaEtag);
    // ETag persistence is INTENTIONALLY deferred: the caller chains it
    // to the local-ZIP write completion in the _pendingRemoteSave block.
    // Persisting here would race the local write — a process kill in
    // between leaves us advertising synced state that the on-disk ZIP
    // contradicts, producing silent stale-content on next open.
    print('[Canvas] Delta synced: ${dirtyPages.length} pages → server '
        '(${result.pageEtags.length} etags captured)');
  }

  // ══════════════════════════════════════════════════════════════
  //  PULL TIMER — receive remote changes from other devices
  // ══════════════════════════════════════════════════════════════

  /// Random source for per-device pull-interval jitter.
  final _pullJitterRng = Random();

  void _startPullTimer() {
    _pullTimer?.cancel();
    if (_disposed) return;
    // Immediate pull on notebook open — don't wait first interval.
    // Track the future so closeNotebook can await it.
    // _disposed guard avoids scheduling a pull whose continuation could
    // race a `closeNotebook` issued seconds later on a slow link
    // (downloads keep arriving and try to mutate a torn-down state).
    _pendingPullFuture = _pullRemoteChanges();
    _schedulePullTick();
  }

  /// Restart the pull timer when coming back from a teardown that killed it
  /// (e.g. previous `paused` lifecycle event). No-op if a timer is already
  /// running. Called from the canvas screen on `AppLifecycleState.resumed`.
  void restartPullTimerIfNeeded() {
    if (_disposed) return;
    if (state == null) return;
    if (_pullTimer != null) return;
    debugPrint('[Canvas] Resume: restarting pull timer');
    _startPullTimer();
  }

  /// Dispose every GPU-backed image texture held in state.imageCache.
  /// Must be called before the Flutter engine shuts down, otherwise the
  /// Linux build crashes with 'Segmentation fault (core dumped)' on close
  /// because native ui.Image handles are still alive when the renderer
  /// tears down its texture pool.
  ///
  /// Called from the canvas screen on AppLifecycleState.detached.
  void releaseImageCache() {
    final s = state;
    if (s == null) return;
    if (s.imageCache.isEmpty) return;
    final count = s.imageCache.length;
    for (final img in s.imageCache.values) {
      try { img.dispose(); } catch (_) {}
    }
    _imageAccessTime.clear();
    // Don't touch `state` — we're shutting down; the empty map means any
    // half-rendered frame still in flight just gets a placeholder.
    debugPrint('[Canvas] Released $count image textures on shutdown');
  }

  @override
  void dispose() {
    _pullTimer?.cancel();
    _pullTimer = null;
    _pendingMetaCommitTimer?.cancel();
    _pendingMetaCommitTimer = null;
    _disposed = true;
    // Release ui.Image textures before super.dispose() tears down the
    // Riverpod state (which would otherwise drop references without
    // calling image.dispose()).
    try {
      releaseImageCache();
    } catch (_) {}
    // Release math raster textures too (same GPU-texture lifetime concern).
    try {
      for (final r in mathCache.values) {
        r.image.dispose();
      }
      mathCache.clear();
    } catch (_) {}
    // Dispose the ValueNotifier instances so any still-subscribed listeners
    // (e.g. the sync pill widget) get cleaned up instead of leaking their
    // attached callbacks on hot-restart / provider container teardown.
    try { isPullingFromRemote.dispose(); } catch (_) {}
    try { pullProgress.dispose(); } catch (_) {}
    try { hasSyncFailure.dispose(); } catch (_) {}
    try { imageCacheVersion.dispose(); } catch (_) {}
    try { mathCacheVersion.dispose(); } catch (_) {}
    super.dispose();
  }

  /// Self-rescheduling pull tick. Adds random jitter per cycle so multiple
  /// devices don't hit the server in lockstep, and skips firing while a
  /// save() is still holding the sync lock (save releases the lock only
  /// after its remote upload commits — running a pull against our own
  /// half-committed upload would show the just-saved state as a remote
  /// "conflict").
  ///
  /// Adaptive interval: starts at [AppConfig.deltaPullInterval] (2 s) for
  /// snappy convergence right after a notebook open or a real change.
  /// After [_idlePullThreshold] consecutive noop pulls we exponentially
  /// back off up to [_idlePullMaxInterval] so an idle notebook doesn't
  /// keep PROPFIND'ing the server and parsing a 215-entry XML payload
  /// every 2 s — that was burning 100 % of one CPU core for no benefit.
  /// On any real change ([_idlePullCount] reset by [_pullRemoteChanges])
  /// we drop straight back to the fast cadence.
  void _schedulePullTick() {
    if (_disposed) return;
    final base = _pullIntervalForIdle();
    final jitterMs = _pullJitterRng.nextInt(AppConfig.deltaPullJitter.inMilliseconds + 1);
    final next = base + Duration(milliseconds: jitterMs);
    _pullTimer?.cancel();
    _pullTimer = Timer(next, () {
      if (_disposed) return;
      // Skip while the user is actively dragging / zooming. The pull's
      // network HEAD response-handling microtasks would otherwise
      // schedule on the same event loop as pointer events, and the
      // resulting context switches show up as occasional pan stutter.
      // The next tick (re-armed below) will fire the moment the user
      // stops moving (the 150 ms guard window naturally lapses).
      //
      // ALSO skip while a pen stroke or eraser drag is mid-flight
      // (strokeActiveProbe — _isInteractingRecent is only bumped by
      // pan/zoom, NOT by drawing). The safety-net tick runs a full
      // pages/ PROPFIND whose XML parse takes tens of ms on a
      // 400-page notebook; landing that mid-stroke coalesced pointer
      // samples away and segmented the curve being drawn.
      if (_isInteractingRecent ||
          (strokeActiveProbe?.call() ?? false) ||
          state?.eraserCursorPos != null) {
        _schedulePullTick();
        return;
      }
      // Skip if a pull or save is still in flight. _pullRemoteChanges()
      // early-returns on _isPulling already, but we also want to back off
      // when save() is uploading so a concurrent PROPFIND doesn't see our
      // half-committed delta folder and mis-diagnose it as a remote change.
      if (!_isPulling && _syncLock == null && !_bulkOperationInProgress) {
        _pendingPullFuture = _pullRemoteChanges();
      }
      _schedulePullTick();
    });
  }

  /// Number of consecutive pull cycles that ended in a "nothing changed"
  /// noop. Used to back off the polling interval (see
  /// [_pullIntervalForIdle]). Reset to 0 in [_pullRemoteChanges] whenever
  /// a real change is observed.
  int _idlePullCount = 0;
  static const int _idlePullThreshold = 3;
  static const Duration _idlePullMaxInterval = Duration(seconds: 30);
  /// After this much sustained idle (≥ this many consecutive noop
  /// pulls), extend the backoff cap to 5 minutes. The fast cadence
  /// still resumes immediately on real activity (a save resets
  /// _idlePullCount to 0). This trims background HEAD chatter from
  /// ~3000/h to ~300/h on notebooks the user leaves open but doesn't
  /// touch — meaningful battery saving on mobile + Tailscale.
  static const int _deepIdleThreshold = 30;
  static const Duration _deepIdleMaxInterval = Duration(minutes: 5);

  /// Counter for the ordered-commit safety-net: every Nth pull does the
  /// full pages/ PROPFIND even when meta-ETag is unchanged, to catch
  /// the rare case of pages added on another device that crashed before
  /// updating metadata.json. Cycle reset to 0 each time we run the
  /// full PROPFIND.
  int _pagePropfindCounter = 0;
  static const int _propfindSafetyNetEvery = 8;
  /// Timestamp anchor for the safety-net so deep-idle (5 min ticks) can't
  /// stretch it to 8 * 5 min = 40 min. With this, after
  /// [_propfindSafetyNetMaxAge] of wall-clock time without a full PROPFIND
  /// we force one regardless of tick count. Set when [_pagePropfindCounter]
  /// is reset.
  DateTime _lastFullPropfindAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _propfindSafetyNetMaxAge = Duration(minutes: 5);

  Duration _pullIntervalForIdle() {
    if (_idlePullCount < _idlePullThreshold) {
      return AppConfig.deltaPullInterval;
    }
    // Deep-idle: after ~30 consecutive noop pulls (≈ 10 minutes
    // of sustained inactivity at the 30s cap) extend the cap to 5
    // minutes. Trades immediate cross-device sync latency (still
    // sub-5min vs sub-30s) for ~10× less network chatter on idle
    // open notebooks.
    final maxIntervalMs = _idlePullCount >= _deepIdleThreshold
        ? _deepIdleMaxInterval.inMilliseconds
        : _idlePullMaxInterval.inMilliseconds;
    // Exponential backoff: idle=3 → 4s, 4 → 8s, 5 → 16s, 6+ → 30s,
    // 30+ → 5min (cap).
    final shift = (_idlePullCount - _idlePullThreshold).clamp(0, 8);
    final ms = AppConfig.deltaPullInterval.inMilliseconds * (2 << shift);
    final capped = ms.clamp(
      AppConfig.deltaPullInterval.inMilliseconds,
      maxIntervalMs,
    );
    return Duration(milliseconds: capped);
  }

  bool _isPulling = false;
  /// The in-flight pull Future, if any. Tracked so that [closeNotebook]
  /// can await an in-progress pull before dropping state — otherwise
  /// exiting mid-download drops the pulled pages before they reach disk
  /// and the next open reads the stale local file.
  Future<void>? _pendingPullFuture;

  /// Set to a "pan/zoom is happening RIGHT NOW" timestamp by the canvas
  /// screen on every pointer-move during pan/zoom. While this stamp is
  /// recent, [_schedulePullTick] skips the network call so the HEAD's
  /// response-handling microtask never lands mid-drag and never causes
  /// a frame-time spike. The stamp is bumped from setPanOffset and
  /// setZoom-and-pan paths, and naturally goes stale within ~150 ms of
  /// the last move event so polling resumes seamlessly when the user
  /// stops moving.
  DateTime _lastInteractAt =
      DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _interactGuard = Duration(milliseconds: 150);
  bool get _isInteractingRecent =>
      DateTime.now().difference(_lastInteractAt) < _interactGuard;
  // _isSyncing tracked by _syncLock mutex

  /// Checks if the remote metadata.json ETag has changed, then pulls
  /// only the pages that differ. Falls back to checking the .ncnote ZIP
  /// for devices that don't use delta sync. Merges into the live canvas.
  ///
  /// Now mutex-protected: waits for any in-flight save() to finish first,
  /// and if local pages are dirty, creates per-page conflicts instead of
  /// silently overwriting.
  Future<void> _pullRemoteChanges() async {
    if (_isPulling || state == null || _bulkOperationInProgress) return;
    // Don't pull while user is resolving conflicts or reviewing pending
    // remote changes — avoids overwriting with a fresh pull.
    if (state!.pendingConflicts.isNotEmpty) return;
    if (state!.pendingRemoteChanges != null) return;
    _isPulling = true;
    _pullHadFailures = false;
    // NOTE: isPullingFromRemote is NOT flipped here. The pill should only
    // appear when we're actually *downloading* new remote content — not
    // during every 4-second PROPFIND poll, which is silent and quick.
    // We set it true below only if the metadata ETag indicates real
    // changes to fetch.

    try {
      // ── Fast path: cheap HEAD on metadata.json only — NO LOCK ──
      //
      // The common case on every 4-second poll (and most notebook opens)
      // is "nothing changed". Running the HEAD inside `_syncLock` blocked
      // any concurrent save() for 100-200ms on every idle poll; with the
      // HEAD outside the lock, idle polling has zero contention with user
      // saves. Only the slow path (getRemoteChangeState + page downloads)
      // needs the lock, and save() doesn't touch `_remoteMetaEtag`, so
      // reading it without the lock is safe.
      final syncService = _ref.read(syncServiceProvider);
      // syncServiceProvider always returns a non-null instance now (see its
      // doc comment) — local-only mode is signaled by isOffline, not null.
      if (syncService == null || syncService.isOffline) return;
      final pullNotebookId = state!.metadata.id;
      final s0 = state!;
      unawaited(CrashLogger.append(
        '[Pull] start nb=${pullNotebookId.substring(0, 8)} '
        'state.pages=${s0.pages.length}/doc=${s0.document.pages.length} '
        'cachedMetaEtag=${_remoteMetaEtag ?? "null"} '
        'lastPageEtags=${_lastPageEtags.length}',
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
          ++_pagePropfindCounter >= _propfindSafetyNetEvery ||
          now.difference(_lastFullPropfindAt) >= _propfindSafetyNetMaxAge;
      try {
        fastMetaEtag =
            await syncService.getDeltaMetaEtag(pullNotebookId);
      } catch (e) {
        unawaited(CrashLogger.append('[Pull] meta-HEAD failed: $e'));
        return;
      }
      final metaMoved = fastMetaEtag != null &&
          (_remoteMetaEtag == null || fastMetaEtag != _remoteMetaEtag);
      if (metaMoved || mustDoSafetyNet || _remoteMetaEtag == null) {
        try {
          remoteState =
              await syncService.getRemoteChangeState(pullNotebookId);
        } on WebDavException catch (e) {
          if (e.statusCode == 404) {
            // Remote .sync/<id>/ doesn't exist yet — a freshly created
            // notebook that has never been pushed. Nothing to pull; the
            // first save() will create the folder. Count as an idle tick
            // so adaptive backoff engages instead of re-hitting the 404
            // at full cadence (which also spammed "Pull failed" forever).
            _idlePullCount++;
            unawaited(CrashLogger.append(
              '[Pull] skip: remote delta folder missing (404) — '
              'notebook not pushed yet',
            ));
            return;
          }
          rethrow;
        }
        fastMetaEtag = remoteState.metaEtag;
        fullStateFetched = true;
        _pagePropfindCounter = 0;
        _lastFullPropfindAt = now;
      }
      if (state == null || state!.metadata.id != pullNotebookId) {
        print('[Canvas] Pull aborted — notebook switched during HEAD '
            '(expected $pullNotebookId, got ${state?.metadata.id})');
        unawaited(CrashLogger.append('[Pull] abort: nb switched during HEAD'));
        return;
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
          : _lastPageEtags.length;
      final serverInconsistent = fullStateFetched &&
          (remoteState!.pageEtags.length > s0.document.pages.length ||
              (_lastPageEtags.isNotEmpty &&
                  remoteState.pageEtags.keys.any((k) => !_lastPageEtags.containsKey(k))) ||
              (_lastPageEtags.isNotEmpty &&
                  remoteState.pageEtags.entries.any(
                      (e) => _lastPageEtags[e.key] != null &&
                             _lastPageEtags[e.key] != e.value)));
      if (fastMetaEtag != null &&
          _remoteMetaEtag != null &&
          fastMetaEtag == _remoteMetaEtag &&
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
          // (count(_lastPageEtags) < count(document.pages)), those pages
          // exist locally without ever having been uploaded — typically
          // because a previous save() failed mid-upload and reopen rebuilt
          // _lastSyncedPages from the local zip, hiding the ghost pages
          // from future dirty-page detection. Result: every subsequent
          // pull skips here, every save() considers the ghost pages
          // already-synced, and the notebook is permanently wedged with
          // local pages > remote pages.
          //
          // Repair: rebuild _lastSyncedPages without those ghost entries
          // (so the next save() detects them as "new pages" via the
          // !_lastSyncedPages.containsKey(key) branch in _saveInner) and
          // mark the notebook dirty so the next save cycle actually fires.
          if (_lastPageEtags.isNotEmpty &&
              _lastPageEtags.length < s0.document.pages.length) {
            final ghostFns = s0.document.pages
                .map((p) => p.fileName)
                .where((fn) => !_lastPageEtags.containsKey(fn))
                .toList();
            if (ghostFns.isNotEmpty) {
              for (final fn in ghostFns) {
                _lastSyncedPages.remove(fn);
              }
              if (state != null && state!.metadata.id == pullNotebookId) {
                state = state!.copyWith(isDirty: true);
              }
              unawaited(CrashLogger.append(
                '[Pull] ghost pages detected: ${ghostFns.length} doc entries '
                'without server ETag (sample: '
                '${ghostFns.take(3).join(",")}'
                '${ghostFns.length > 3 ? "..." : ""}) — '
                'marked dirty so next save() uploads them',
              ));
              return;
            }
          }
          unawaited(CrashLogger.append(
            '[Pull] skip: meta ETag unchanged (fast=$fastMetaEtag) '
            'and state is consistent (pages=${s0.pages.length}=doc=${s0.document.pages.length}, '
            'remote pages=$remotePageCount, fullPropfind=$fullStateFetched)',
          ));
          _idlePullCount++;
          return;
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
        'cached=${_remoteMetaEtag ?? "null"} → acquire lock + full fetch',
      ));

      // ── Slow path: remote changed (or safety-net cycle), acquire lock ──
      //
      // We deliberately do NOT reset _idlePullCount here. The slow path
      // is entered both for genuine changes AND for the periodic safety
      // net (every [_propfindSafetyNetEvery] ticks). Resetting on
      // safety-net cycles defeated the adaptive backoff: every 8th tick
      // dropped us back to the 2 s cadence, then 8 more ticks of 2 s,
      // then safety-net again, forever — the whole point of the backoff
      // (idle should converge to 30 s) never materialised, and a
      // 215-page notebook kept paying a full pages/ PROPFIND every 16 s
      // for nothing. The reset now happens deeper in the function, only
      // when [changeState.metaEtag != _remoteMetaEtag] (true work to
      // do).
      final pullLockToken = await _acquireSyncLock();
      if (pullLockToken == null) return;
      try {
        if (state == null || state!.metadata.id != pullNotebookId) return;
        final s = state!;

        // Fetch metadata ETag + page ETags in parallel (only on change path)
        final changeState = await syncService.getRemoteChangeState(pullNotebookId);

        // Guard: did the user switch notebooks while we were awaiting the
        // network? If so this pull belongs to the OLD notebook — dropping
        // its data into the new one would swap the user's current notebook
        // out from under them (the "Automotive turned into AICD" bug).
        if (state == null || state!.metadata.id != pullNotebookId) {
          print('[Canvas] Pull aborted — notebook switched during PROPFIND '
              '(expected $pullNotebookId, got ${state?.metadata.id})');
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
        final innerInconsistent = changeState.pageEtags.length > s.document.pages.length ||
            (_lastPageEtags.isNotEmpty &&
                changeState.pageEtags.keys.any((k) => !_lastPageEtags.containsKey(k))) ||
            (_lastPageEtags.isNotEmpty &&
                changeState.pageEtags.entries.any(
                    (e) => _lastPageEtags[e.key] != null &&
                           _lastPageEtags[e.key] != e.value));
        if (changeState.metaEtag != null &&
            (changeState.metaEtag != _remoteMetaEtag || innerInconsistent)) {
          // Real work detected → reset idle counter so the next ticks
          // happen at the snappy 2 s cadence until things stabilise.
          // Watchdog: if we've been in the "inconsistent" loop too long
          // without progress (>= _maxInconsistentPulls in the window), do NOT
          // reset to the fast cadence — let adaptive backoff stretch the next
          // tick out. Defense-in-depth on top of the ghost-prune (which
          // normally converges in ~3 strikes); guards against any future
          // regression where state can't converge for unknown reasons.
          if (_consecutiveInconsistentPulls < _maxInconsistentPulls) {
            _idlePullCount = 0;
          } else {
            print('[Canvas] Pull watchdog: $_consecutiveInconsistentPulls '
                'consecutive inconsistent pulls — suppressing fast-cadence '
                'reset, letting adaptive backoff engage');
          }
          if (changeState.metaEtag == _remoteMetaEtag && innerInconsistent) {
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
          // _pullFromDeltaInner flips it only when real pages/assets will
          // actually be fetched.
          await _pullFromDeltaFast(
            s, syncService, changeState.pageEtags,
          );
          // Only advance _remoteMetaEtag if the notebook is STILL open and
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
          final stillOpen = state != null && state!.metadata.id == pullNotebookId;
          final sNow = stillOpen ? state! : null;
          // Per-fileName check, not a length comparison: a local-only page
          // can make `pages.length >= document.pages.length` true while a
          // DIFFERENT document entry still has no page data. Advancing the
          // meta ETag in that state makes the gap permanent (next pull
          // fast-path skips). Require that EVERY document entry is backed by
          // page data in memory — exactly what the comment above intends.
          final stateConsistent = sNow == null
              ? false
              : sNow.document.pages.every((e) => sNow.pages.containsKey(e.fileName));
          if (stillOpen && !_pullHadFailures && stateConsistent) {
            // Wait for the pulled-changes local save to land on disk BEFORE
            // persisting the meta ETag. Otherwise a crash/kill in the small
            // window between persist and save completion leaves the
            // _remoteMetaEtag matching the server while the .ncnote zip is
            // still the pre-pull version — next open's fast path skips
            // because ETag matches, and the user is wedged at the old
            // page count until they manually force-sync.
            final pendingSave = _pendingPulledLocalSave;
            if (pendingSave != null) {
              try {
                await pendingSave;
              } catch (e) {
                print('[Canvas] Pre-ETag save wait failed: $e');
              }
            }
            _remoteMetaEtag = changeState.metaEtag;
            // Real progress (ETag advanced) → reset the inconsistent-loop
            // watchdog. The next inconsistent pull starts a fresh window.
            _consecutiveInconsistentPulls = 0;
            _consecutiveInconsistentSince = null;
            // Persist so next cold-start's first pull can skip immediately.
            // Awaited: SharedPreferences.setString is a few ms, and we need
            // it on disk before the caller assumes the ETag survived a crash.
            await _persistRemoteMetaEtag(pullNotebookId);
            unawaited(CrashLogger.append(
              '[Pull] ETag advanced: ${changeState.metaEtag}',
            ));
          } else if (_pullHadFailures) {
            print('[Canvas] Pull had failures — leaving _remoteMetaEtag stale '
                'so next sync retries missing content');
            unawaited(CrashLogger.append(
              '[Pull] ETag not advanced: pull had page failures',
            ));
          } else if (stillOpen && !stateConsistent) {
            // Increment the watchdog inside a rolling window. Once it crosses
            // _maxInconsistentPulls, the slow-path branch above stops
            // resetting _idlePullCount so the next tick is at the slower
            // adaptive cadence (eventually 30 s) instead of 2 s — preventing
            // any silent CPU loop if the ghost-prune ever fails to converge.
            final now = DateTime.now();
            if (_consecutiveInconsistentSince == null ||
                now.difference(_consecutiveInconsistentSince!) >
                    _inconsistentWindow) {
              _consecutiveInconsistentSince = now;
              _consecutiveInconsistentPulls = 0;
            }
            _consecutiveInconsistentPulls++;
            print('[Canvas] Pull done but state still inconsistent '
                '(pages=${sNow!.pages.length} < doc=${sNow.document.pages.length}) '
                '— leaving _remoteMetaEtag stale so next pull retries '
                '[loop $_consecutiveInconsistentPulls/$_maxInconsistentPulls]');
            unawaited(CrashLogger.append(
              '[Pull] ETag not advanced: state still mismatch '
              '(pages=${sNow.pages.length} < doc=${sNow.document.pages.length})',
            ));
          }
        }
      } finally {
        // Hand the lock to a background task that awaits any local-save
        // spawned by acceptRemoteChanges() before releasing. Without this
        // the next save() / pull can race the pulled ZIP rewrite on disk:
        //   • save() would overwrite the on-disk file before the pulled
        //     pages are persisted → pulled edits lost on next open
        //   • the _pageJsonCache would be re-populated out of order
        final pendingSave = _pendingPulledLocalSave;
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
              if (identical(_pendingPulledLocalSave, pendingSave)) {
                _pendingPulledLocalSave = null;
              }
              _releaseSyncLock(pullLockToken);
            }
          }();
        }
      }
    } catch (e) {
      print('[Canvas] Pull failed: $e');
    } finally {
      _isPulling = false;
      isPullingFromRemote.value = false;
    }
  }

  /// Pull changed pages from the exploded _delta/ folder.
  /// Uses per-page WebDAV ETags to detect which pages actually changed.
  /// Returns true if any pages were merged.
  /// [preloadedPageEtags]: already-fetched page ETags (parallel optimization).
  Future<bool> _pullFromDeltaFast(
    CanvasState s,
    SyncService syncService,
    Map<String, String> preloadedPageEtags,
  ) async {
    return _pullFromDeltaInner(s, syncService, preloadedPageEtags);
  }

  Future<bool> _pullFromDeltaInner(
    CanvasState s,
    SyncService syncService,
    Map<String, String> remotePageEtags,
  ) async {
    print('[Canvas] Remote has ${remotePageEtags.length} pages, local cache has ${_lastPageEtags.length} ETags');

    // Find pages whose WebDAV ETag changed since last pull, OR that exist
    // on the server but are missing from the local state.
    //
    // The second condition handles stale local caches: _initPageEtags may
    // have pre-populated _lastPageEtags from the server, so a stale local
    // notebook (e.g. opened with 1 page when server has 100) would have
    // matching ETags for all 100 pages and download nothing. Checking
    // s.pages directly ensures every page the server has is materialised
    // locally, regardless of whether the ETag cache looks up-to-date.
    final pagesToPull = <String>[];
    final preKnownCorrupt = <String>[];
    for (final entry in remotePageEtags.entries) {
      final etagChanged = _lastPageEtags[entry.key] != entry.value;
      final missingLocally = !s.pages.containsKey(entry.key);
      if (etagChanged || missingLocally) {
        // Dedup: if we've already confirmed the server bytes for this exact
        // ETag are corrupt, re-issuing the GET will hit the same bad bytes.
        // Skip the network round-trip and let the heal path handle it
        // directly — the upcoming save() will replace the corrupt server
        // file and produce a fresh ETag, at which point this skip no
        // longer matches and the next pull will re-fetch normally.
        if (_knownCorruptEtags[entry.key] == entry.value) {
          preKnownCorrupt.add(entry.key);
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
    if (_lastPageEtags.isNotEmpty) {
      final cachedCount = _lastPageEtags.length;
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
        _pullHadFailures = true; // force retry next cycle
        return false;
      }
    }

    // Detect pages that were deleted remotely (in our ETag cache but gone
    // from the remote pages/ folder listing).
    final deletedRemotelyByEtag = _lastPageEtags.keys
        .where((k) => !remotePageEtags.containsKey(k))
        .toSet();

    // ── Structure-based deletion detection ──
    // ETag-based deletion detection (_lastPageEtags diff above) already
    // catches remote deletions when we had an ETag for the page; the loop
    // below is the backstop for the "cache was fetched AFTER the delete"
    // path.
    //
    // IMPORTANT: we gate on `_lastPageEtags.containsKey(fn)`, NOT
    // `_lastSyncedPages`. `_lastSyncedPages` is re-populated from the
    // local .ncnote on every open — which means it also contains pages
    // the user added offline and that have NEVER been uploaded. Using
    // that signal would classify brand-new local pages as "deleted
    // remotely" and silently drop them the first time the canvas pulls
    // ("ho aggiunto pagina 2 offline, chiuso e riaperto, è sparita").
    //
    // `_lastPageEtags` only contains pages the server has acknowledged,
    // so it cleanly distinguishes "was on server, now gone" (true remote
    // delete) from "never been on server, still pending upload" (local-
    // only page to preserve and upload on the next save).
    for (final pageEntry in s.document.pages) {
      final fn = pageEntry.fileName;
      if (remotePageEtags.containsKey(fn)) continue; // still exists on remote
      if (deletedRemotelyByEtag.contains(fn)) continue; // already detected
      if (s.pages[fn] == null) continue; // no local data (nothing to delete)
      if (_lastPageEtags.containsKey(fn)) {
        deletedRemotelyByEtag.add(fn);
      } else {
        print('[Canvas] Pull: page $fn exists locally but not on server — '
            'treating as pending upload (never synced), NOT a remote delete');
      }
    }

    // Edge case: every "changed" page on the server was already known to
    // be corrupt at this very ETag. Nothing to network-fetch, but we still
    // need to push the heal save so the server gets fresh bytes — fall
    // through to the download path so the heal scheduling fires.
    if (pagesToPull.isEmpty && deletedRemotelyByEtag.isEmpty && preKnownCorrupt.isEmpty) {
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
            await syncService.downloadDeltaMeta(s.metadata.id);
        if (state != null && state!.metadata.id == s.metadata.id) {
          // 3-way merge against the LIVE state (not the pull-start snapshot)
          // so a reorder / chapter-move / rename the user made during this
          // tick isn't clobbered by the remote metadata. No page data moved on
          // this path (pagesToPull empty), so any doc entry without local data
          // is NOT on the server (else it'd be in pagesToPull) → a ghost. Prune
          // it via the strike policy so a long-broken document.json (more
          // entries than real pages) finally converges instead of pinning the
          // pull in a hot retry loop forever.
          final live = state!;
          final surviving = _survivingFileNames(
            withData: live.pages.keys,
            docPages: live.document.pages,
            serverFileNames: remotePageEtags.keys.toSet(),
            remoteDeleted: const {},
          );
          final merged = CanvasNotifier._merge3Way(
            baseMeta: _lastSyncedMetadata,
            localMeta: live.metadata,
            remoteMeta: remoteMeta.metadata,
            baseDoc: _lastSyncedDocument,
            localDoc: live.document,
            remoteDoc: remoteMeta.document,
            survivingFileNames: surviving,
          );
          final finalDoc = merged.document;
          final finalMeta =
              merged.metadata.copyWith(pageCount: finalDoc.pages.length);
          final changed = CanvasNotifier._documentStructurallyDiffers(
                  finalDoc, live.document) ||
              CanvasNotifier._metadataStructurallyDiffers(
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
                (CanvasNotifier._documentStructurallyDiffers(
                        finalDoc, remoteMeta.document) ||
                    CanvasNotifier._metadataStructurallyDiffers(
                        finalMeta, remoteMeta.metadata));
            state = live.copyWith(
              metadata: finalMeta,
              document: finalDoc,
              isDirty: needsPush || live.isDirty,
            );
            print('[Canvas] Pull noop: merged metadata/structure '
                '(needsPush=$needsPush) — chapters/title/paper/order');
            unawaited(CrashLogger.append(
              '[Pull] noop: 3-way merged metadata/structure '
              '(needsPush=$needsPush)',
            ));
          }
          // Baseline tracks SERVER TRUTH regardless of whether we adopted a
          // change, so the next merge has the correct common ancestor.
          _lastSyncedDocument = remoteMeta.document;
          _lastSyncedMetadata = remoteMeta.metadata;
        }
      } catch (e) {
        // Don't fail the whole pull on a metadata-fetch hiccup; next pull
        // will retry. The ETag advance below means we WON'T retry — but
        // that's fine: any subsequent metadata edit will move the meta
        // ETag again and trigger another slow-path tick.
        print('[Canvas] Pull noop: metadata-content check failed: $e');
      }

      print('[Canvas] Delta pull: no page ETags changed, no deletions');
      unawaited(CrashLogger.append(
        '[Pull] diff: noop (remote=${remotePageEtags.length} '
        'cached=${_lastPageEtags.length} state=${s.pages.length})',
      ));
      _lastPageEtags = Map.of(remotePageEtags);
      // Await the persist — the user can close the notebook during the
      // 'noop' tick of the pull loop, and if the unawaited write hadn't
      // landed yet the next open would reset _lastPageEtags to empty and
      // force a full 183-page re-sync next time.
      await _persistLastPageEtags(s.metadata.id);
      return false;
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
      isPullingFromRemote.value = false;
      pullProgress.value = (done: 0, total: 0);
    }
  }

  Future<bool> _pullFromDeltaDownload(
    CanvasState s,
    SyncService syncService,
    Map<String, String> remotePageEtags,
    List<String> pagesToPull,
    Set<String> deletedRemotelyByEtag,
    List<String> preKnownCorrupt,
  ) async {
    // Download metadata + changed pages in parallel (one round-trip)
    late final ({NotebookMetadata metadata, DocumentStructure document}) remoteMeta;
    final updatedPages = Map<String, PageData>.from(s.pages);
    final updatedAssets = Map<String, Uint8List>.from(s.assetBytes);
    var anyPageChanged = false;

    final metaFuture = syncService.downloadDeltaMeta(s.metadata.id);

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
    // [_knownCorruptEtags] — those were already proven corrupt this
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
      final until = _pageFailureCooldownUntil[fn];
      if (until != null && now.isBefore(until)) {
        cooledDown.add(fn);
        return true;
      }
      return false;
    });
    if (cooledDown.isNotEmpty) {
      _pullHadFailures = true; // keep meta etag stale until they recover
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
          final remotePage = await syncService
              .downloadDeltaPage(s.metadata.id, pageFileName);
          updatedPages[pageFileName] = remotePage;
          anyPageChanged = true;
          completed.add(pageFileName);
          completedCount++;
          pullProgress.value =
              (done: completedCount, total: pagesToPull.length);
          // Success: reset failure tracking for this page.
          _pageFailureCount.remove(pageFileName);
          _pageFailureCooldownUntil.remove(pageFileName);
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
            _pageFailureCount.remove(pageFileName);
            _pageFailureCooldownUntil.remove(pageFileName);
            // Remember the exact server ETag we just confirmed corrupt
            // so subsequent pull cycles before save() lands skip the
            // GET entirely (the bad bytes are stable; re-downloading
            // them just burns bandwidth).
            final corruptEtag = remotePageEtags[pageFileName];
            if (corruptEtag != null) {
              _knownCorruptEtags[pageFileName] = corruptEtag;
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
          if (_disposed || state?.metadata.id != s.metadata.id) return;
        }
      }
      failedPages.add(pageFileName);
      _pullHadFailures = true;
      // Track consecutive failures so we can apply a cooldown next pull.
      final fc = (_pageFailureCount[pageFileName] ?? 0) + 1;
      _pageFailureCount[pageFileName] = fc;
      if (fc >= maxConsecutiveFailures) {
        _pageFailureCooldownUntil[pageFileName] =
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
        if (_disposed || state?.metadata.id != s.metadata.id) return;
        final fn = queue.removeLast();
        await pullOne(fn);
      }
    }
    final workers = List.generate(
        batchSize < queue.length ? batchSize : queue.length,
        (_) => worker());
    await Future.wait(workers);
    // ── Defensive meta-fetch: never let document.json / metadata.json
    //    failure abort the whole pull cycle.
    //
    // metaFuture is downloadDeltaMeta() which throws on truncated /
    // empty / unparseable body (very common during Tailscale flaps:
    // server closes the connection mid-response → 200 OK with 0
    // bytes → jsonDecode('') → FormatException). If we let that
    // propagate, the function aborts BEFORE line 7836 where per-page
    // ETags get persisted. Next pull tick sees _lastPageEtags = 1
    // again and tries the full 102-page re-pull from scratch — the
    // infinite-loop bug.
    //
    // On meta failure: mark _pullHadFailures so the meta ETag stays
    // stale (next tick will retry the whole cycle), but still persist
    // the per-page ETags we DID successfully fetch and return false
    // gracefully.
    try {
      remoteMeta = await metaFuture;
    } catch (e) {
      print('[Canvas] Meta fetch failed mid-pull '
          '(${completed.length} pages still got through): $e');
      _pullHadFailures = true;
      // Persist what we DID download so subsequent ticks don't re-fetch
      // the same pages. remotePageEtags was already restricted at
      // lines 7280-7295 to remove failed/cooled/corrupt pages, so
      // it now contains only the successful ones.
      remotePageEtags = Map.of(remotePageEtags);
      for (final fn in failedPages) { remotePageEtags.remove(fn); }
      for (final fn in cooledDown) { remotePageEtags.remove(fn); }
      for (final fn in corruptedPages) { remotePageEtags.remove(fn); }
      for (final entry in remotePageEtags.entries) {
        _lastPageEtags[entry.key] = entry.value;
      }
      await _persistLastPageEtags(s.metadata.id);
      return false;
    }

    if (anyPageChanged) {
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
    // re-attempts them; we must NOT advance _lastPageEtags for pages we
    // didn't actually receive. Also evict pages we skipped due to the
    // cooldown — they still haven't been received either. And evict
    // corrupt-on-server pages so the next save() (which uploads the
    // local-good copy) is followed by a pull that DOES re-fetch the
    // freshly-correct bytes — leaving the corrupt etag in our cache
    // would make the post-heal pull skip them.
    if (failedPages.isNotEmpty || cooledDown.isNotEmpty || corruptedPages.isNotEmpty) {
      remotePageEtags = Map.of(remotePageEtags);
      for (final fn in failedPages) {
        // Keep the previous ETag we had (if any) so the "changed" comparison
        // still picks this page up next time the ETag actually changes again,
        // but ensure the new remotePageEtags entry for this file does NOT
        // make it into _lastPageEtags below.
        remotePageEtags.remove(fn);
      }
      for (final fn in cooledDown) {
        remotePageEtags.remove(fn);
      }
      for (final fn in corruptedPages) {
        remotePageEtags.remove(fn);
      }
    }


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
        !updatedAssets.containsKey(ref) || _corruptAssetIds.contains(ref);
    for (final page in updatedPages.values) {
      for (final ref in page.assetReferences) {
        if (needsHeal(ref)) missingAssets.add(ref);
      }
      // Also scan image elements directly (assetReferences may be out of date)
      for (final el in page.layers.content) {
        el.map(
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
    // `_remoteMetaEtag` was still null on disk.
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
          _assetRefsForPage(s.currentPageIndex, s.document, updatedPages);
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
            if (attempt == maxAttempts - 1) break;
            await Future.delayed(
                Duration(milliseconds: 200 * (1 << attempt)));
            if (_disposed || state?.metadata.id != notebookId) {
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
        if (_disposed) break;
        final batch = priorityList.skip(i).take(maxAssetConcurrency);
        final batchResults = await Future.wait(batch.map(pullOneAsset));
        for (final (ref, data, err) in batchResults) {
          if (data != null) {
            updatedAssets[ref] = data;
            priorityDownloaded[ref] = data;
            anyPageChanged = true;
          } else if (err != null) {
            print('[Canvas] Failed to pull priority asset $ref: $err '
                '(will retry next pull)');
          }
        }
      }
      if (priorityDownloaded.isNotEmpty) {
        for (final entry in priorityDownloaded.entries) {
          unawaited(_decodeAndCacheImage(entry.key, entry.value));
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
            if (_disposed || state?.metadata.id != notebookId) break;
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
                unawaited(_decodeAndCacheImage(ref, data));
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
          if (!_disposed &&
              bgDownloaded.isNotEmpty &&
              state != null &&
              state!.metadata.id == notebookId) {
            final merged = Map<String, Uint8List>.from(state!.assetBytes)
              ..addAll(bgDownloaded);
            state = state!.copyWith(assetBytes: merged);
            // Anything we just pulled from the server is by definition
            // server-confirmed. Mark these as eligible for future
            // server-side DELETE (used by _pruneOrphanAssets).
            _uploadedAssetKeys.addAll(bgDownloaded.keys);
          }
        }());
      }
    }

    // ── Detect remote deletions: pages in local state but gone from
    //    remote pages/ folder ──
    final deletionConflicts = <PageConflict>[];

    if (deletedRemotelyByEtag.isNotEmpty) {
      for (final fileName in deletedRemotelyByEtag) {
        final localPage = s.pages[fileName];
        if (localPage == null) continue;
        // Was this page edited locally since last sync?
        final locallyEdited = _lastSyncedPages[fileName] != null &&
            localPage != _lastSyncedPages[fileName];
        if (locallyEdited) {
          // Conflict: local edit vs remote deletion — let user decide
          final pageIndex = s.document.pages.indexWhere(
              (e) => e.fileName == fileName);
          final pageEntry = pageIndex >= 0
              ? s.document.pages[pageIndex] : null;
          final chapterName = _chapterNameForPage(pageEntry, s.metadata);
          deletionConflicts.add(PageConflict(
            fileName: fileName,
            pageNumber: localPage.pageNumber,
            chapterName: chapterName,
            localPage: localPage,
            remotePage: localPage, // no remote version — show local as both
            localImageCache: Map.of(state!.imageCache),
            remoteImageCache: const {},
            isDeletion: true,
          ));
          print('[Canvas] CONFLICT: $fileName edited locally but deleted remotely');
        } else {
          // Safe deletion — auto-remove
          updatedPages.remove(fileName);
          anyPageChanged = true;
          print('[Canvas] Auto-removing page deleted remotely: $fileName');
        }
      }
    }

    // Notebook-switch guard: if the user opened a different notebook while
    // we were downloading pages/assets, this data belongs to the old one.
    // Writing it to state would corrupt the now-active notebook.
    if (state == null || state!.metadata.id != s.metadata.id) {
      print('[Canvas] Delta merge aborted — notebook switched mid-pull '
          '(expected ${s.metadata.id}, got ${state?.metadata.id})');
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
    if ((anyPageChanged ||
            deletionConflicts.isNotEmpty ||
            corruptedPages.isNotEmpty) &&
        state != null) {
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
        final lastSynced = _lastSyncedPages[fileName];
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
          final autoMerged = CanvasNotifier._mergePageElements(
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
            final chapterName = _chapterNameForPage(pageEntry, remoteMeta.metadata);
            conflicts.add(PageConflict(
              fileName: fileName,
              pageNumber: remotePage.pageNumber,
              chapterName: chapterName,
              localPage: localPage,
              remotePage: remotePage,
              localImageCache: Map.of(state!.imageCache),
              remoteImageCache: Map.of(state!.imageCache),
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
        final chapterName = _chapterNameForPage(pageEntry, remoteMeta.metadata);
        final localCounts = _elementCounts(localPage);
        final remoteCounts = _elementCounts(remotePage);
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

      // Count safe deletions (auto-removed, not conflicting)
      final safeDeleteCount = deletedRemotelyByEtag.length - deletionConflicts.length;

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
      final orphanSynthEntries = <PageEntry>[];
      int orphanChRecovered = 0;
      int orphanChUnmapped = 0;
      for (final entry in updatedPages.entries) {
        if (allLocalFileNames.contains(entry.key)) continue;
        final pid = entry.value.pageId;
        final ch = orphanPageIdToChapter[pid];
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
      final combinedEntries = [
        ...remoteMeta.document.pages,
        ...localOnlyEntries,
        ...orphanSynthEntries,
      ];
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
                remotePageFileNames: remotePageEtags.keys.toSet(),
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
          state = state!.copyWith(
            pendingRemoteChanges: pending,
            clearPendingConflicts: true,
          );
          acceptRemoteChanges();
          // Any healed orphan means the server's document.json/metadata.json
          // is inconsistent (page files exist in pages/ but aren't listed
          // in document). Mark dirty so the next save() pushes the repaired
          // document back to the server — regardless of whether we also
          // received other pending changes in this cycle. Without this, a
          // pull that both 'accepts' real new pages AND heals an orphan
          // left the server broken forever (details.isNotEmpty gated the
          // repair-upload out even though the repair is exactly what's
          // needed to break the cycle).
          if (needsHeal && state != null) {
            state = state!.copyWith(isDirty: true);
          }
          // Corrupt-page heal: acceptRemoteChanges just rebuilt
          // _lastSyncedPages from the merged map (which contains the
          // LOCAL bytes for these pages, since updatedPages was seeded
          // from s.pages and we never overwrote them). To make the next
          // save() actually re-upload, we must evict their entries so
          // _saveInner's `!_lastSyncedPages.containsKey(key)` branch
          // detects them as fresh. Then mark dirty + schedule a save:
          // the local copies overwrite the truncated server bytes, and
          // a subsequent pull picks up the freshly-written ETag without
          // FormatException.
          if (needsCorruptionHeal && state != null) {
            for (final fn in corruptedPages) {
              _lastSyncedPages.remove(fn);
            }
            state = state!.copyWith(isDirty: true);
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
              if (_disposed) return;
              if (state == null || state!.metadata.id != s.metadata.id) return;
              unawaited(save());
            });
          }
        } else {
          state = state!.copyWith(
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
    _lastPageEtags = Map.of(remotePageEtags);
    // Await — if we only 'unawait' this, a notebook close fires right
    // after a successful pull race the SharedPreferences write and the
    // next open wakes up with _lastPageEtags={} → forces a full N-page
    // re-sync even though nothing on the server changed.
    await _persistLastPageEtags(s.metadata.id);
    return anyPageChanged;
  }

  // ══════════════════════════════════════════════════════════════
  //  ACCEPT / DISMISS REMOTE CHANGES
  // ══════════════════════════════════════════════════════════════

  /// User accepted the incoming remote changes — apply them to the canvas.
  void acceptRemoteChanges() {
    final s = state;
    final pending = s?.pendingRemoteChanges;
    if (s == null || pending == null) return;

    // Safety net: never apply remote changes belonging to a different
    // notebook than the one currently open (shouldn't happen with the
    // pull-path guards in place, but cheap to double-check).
    if (s.metadata.id != pending.metadata.id) {
      print('[Canvas] Dropping stale pendingRemoteChanges '
          '(pending=${pending.metadata.id}, open=${s.metadata.id})');
      state = s.copyWith(clearPendingRemoteChanges: true);
      return;
    }

    // ── Self-healing: repair duplicate fileNames introduced by the merge ──
    final repaired = CanvasNotifier._repairDuplicateFileNames(
        pending.document, pending.pages);

    // ── Merge page DATA: preserve strokes drawn during the pull window ──
    // pending.pages was captured at pull-start. If the user kept drawing
    // while the pull was in flight (slow Tailscale: 30-90s), state.pages[k]
    // is now a NEW PageData instance while repaired.pages[k] is the pre-pull
    // snapshot. Identity vs _lastSyncedPages tells us whether the user
    // touched this page since last sync; if yes keep live local, else take
    // remote. Plus: keep truly local-only pages, drop remote-deleted ones.
    final mergedPages = <String, PageData>{};
    final newLastSynced = <String, PageData>{};
    var anyAutoMerged = false;
    for (final entry in repaired.pages.entries) {
      final k = entry.key;
      // Deletion-conflicted page whose delete the user has since accepted
      // in resolveConflicts (purged from pages, document and tracking):
      // the pull snapshot still carries its data, and without this guard a
      // later banner-tap resurrects a page the user explicitly chose to
      // delete — undoing the deletion on every other device at next save.
      if (pending.remoteDeletedFileNames.contains(k) &&
          !s.pages.containsKey(k) &&
          !s.document.pages.any((p) => p.fileName == k)) {
        continue;
      }
      final live = s.pages[k];
      final lastSynced = _lastSyncedPages[k];
      // Element-level auto-merge: both sides edited this page but the pull
      // judged the edits disjoint. Re-run the merge with the LIVE local page
      // (folds in any edits made during the pull window) against the RAW
      // remote (entry.value). On success we adopt the union — no prompt; on
      // failure (a same-element clash introduced by a mid-pull edit) we keep
      // local and leave it dirty so the next pull can re-evaluate.
      if (pending.autoMergeable.contains(k) &&
          lastSynced != null &&
          live != null) {
        final reMerged = CanvasNotifier._mergePageElements(
            base: lastSynced, local: live, remote: entry.value);
        if (reMerged != null) {
          mergedPages[k] = reMerged;
          anyAutoMerged = true; // differs from remote → must re-upload
        } else {
          mergedPages[k] = live;
        }
        // Either way the result isn't the server's version, so DON'T advance
        // the baseline for this page — let save() detect it as dirty.
        continue;
      }
      final userTouchedDuringPull =
          live != null && !identical(live, lastSynced);
      if (userTouchedDuringPull) {
        mergedPages[k] = live;
        if (lastSynced != null) newLastSynced[k] = lastSynced;
      } else {
        mergedPages[k] = entry.value;
        newLastSynced[k] = entry.value;
      }
    }
    for (final entry in s.pages.entries) {
      if (mergedPages.containsKey(entry.key)) continue;
      final wasPreviouslySynced = _lastSyncedPages.containsKey(entry.key);
      if (wasPreviouslySynced) continue; // remote-deleted → drop
      mergedPages[entry.key] = entry.value; // truly local-only → keep
    }

    // ── 3-way merge of STRUCTURE (page order + per-page chapter) and
    //    METADATA (title/chapters/paper/cover) against the LIVE local state ──
    // This is the fix for the structural-race data-loss bug: the old code
    // applied `repaired.document` (the remote snapshot's order) wholesale,
    // silently discarding any reorder / chapter-move / rename the user made
    // DURING the download window. Feeding the LIVE s.document/s.metadata as
    // the "local" side, with _lastSynced* as the common ancestor, preserves
    // one-sided edits on BOTH sides and only tie-breaks true same-field
    // conflicts. survivingFileNames is the authoritative page set.
    // Keep pages with data, plus data-less entries still pending hydration on
    // the server; prune only ghosts confirmed dead for _ghostPruneThreshold
    // pulls. Without keeping pending-hydration entries, a page whose download
    // merely failed this cycle on a flaky link would be wrongly dropped.
    final surviving = _survivingFileNames(
      withData: mergedPages.keys,
      docPages: s.document.pages,
      serverFileNames: pending.remotePageFileNames,
      remoteDeleted: pending.remoteDeletedFileNames,
    );
    final merged = CanvasNotifier._merge3Way(
      baseMeta: _lastSyncedMetadata,
      localMeta: s.metadata,
      remoteMeta: pending.metadata,
      baseDoc: _lastSyncedDocument,
      localDoc: s.document,
      remoteDoc: repaired.document,
      survivingFileNames: surviving,
    );
    final finalDoc = merged.document;
    final finalMeta =
        merged.metadata.copyWith(pageCount: finalDoc.pages.length);

    // ── Keep the user on the same page they were viewing ──
    // Resolve by fileName against the MERGED order so the user doesn't jump.
    int newPageIndex = s.currentPageIndex;
    if (s.document.pages.isNotEmpty &&
        s.currentPageIndex < s.document.pages.length) {
      final currentFileName = s.document.pages[s.currentPageIndex].fileName;
      final found =
          finalDoc.pages.indexWhere((p) => p.fileName == currentFileName);
      if (found >= 0) {
        newPageIndex = found;
      } else {
        newPageIndex = finalDoc.pages.isEmpty
            ? 0
            : s.currentPageIndex.clamp(0, finalDoc.pages.length - 1);
      }
    }
    // Land on an index whose page data actually exists ("Nessuna pagina"
    // guard) — walk forward from the resolved index.
    for (int attempt = 0; attempt < finalDoc.pages.length; attempt++) {
      final idx = (newPageIndex + attempt) % finalDoc.pages.length;
      if (mergedPages.containsKey(finalDoc.pages[idx].fileName)) {
        newPageIndex = idx;
        break;
      }
    }

    // ── Sync activeChapterId with the landed page's actual chapter ──
    String? mergedChapterId = s.activeChapterId;
    if (finalDoc.pages.isNotEmpty) {
      final pageChapterId = finalDoc.pages[newPageIndex].chapterId;
      if (pageChapterId != s.activeChapterId) {
        mergedChapterId = pageChapterId;
      }
    }

    // ── Preserve locally-added assets that haven't been uploaded yet ──
    // pending.assets contains only what the server currently has; merge any
    // local-only assets back so save() can still find their bytes.
    final mergedAssets = Map<String, Uint8List>.from(pending.assets);
    for (final entry in s.assetBytes.entries) {
      mergedAssets.putIfAbsent(entry.key, () => entry.value);
    }
    _uploadedAssetKeys.addAll(pending.assets.keys);

    state = s.copyWith(
      metadata: finalMeta,
      document: finalDoc,
      pages: mergedPages,
      assetBytes: mergedAssets,
      currentPageIndex: newPageIndex,
      activeChapterId: mergedChapterId,
      clearPendingRemoteChanges: true,
    );
    _lastSyncedPages = newLastSynced;
    // Baselines track SERVER TRUTH (what this pull observed), NOT the merged
    // result — the merge isn't on the server until we push it. Setting the
    // baseline to `merged` would let a pull during the push window read
    // local's own unpushed contributions as "remote reverted them" and drop
    // them. save() advances these to the merged doc once the upload commits.
    _lastSyncedDocument = repaired.document;
    _lastSyncedMetadata = pending.metadata;

    // If our local structural / metadata edits made the merged result differ
    // from what the server has, mark dirty so the next save pushes the merge
    // up. This is what makes two devices CONVERGE instead of ping-ponging.
    //
    // BUT only when the merged document is internally consistent (every entry
    // has page data). If data-less entries remain (pages still hydrating, or
    // ghosts not yet ripe for prune), a triggered save would hit PRE-SAVE
    // GUARD #2, abort, and fire another pull — a hot CPU loop. Defer the push
    // until the state converges; the ghost-prune / hydration will get us there
    // and the NEXT consistent pull marks dirty then.
    final docConsistent =
        finalDoc.pages.every((e) => mergedPages.containsKey(e.fileName));
    final needsPush = docConsistent &&
        (anyAutoMerged ||
            CanvasNotifier._documentStructurallyDiffers(finalDoc, repaired.document) ||
            CanvasNotifier._metadataStructurallyDiffers(finalMeta, pending.metadata));
    if (needsPush && state != null) {
      state = state!.copyWith(isDirty: true);
    }
    print('[Canvas] User accepted remote changes (landed on page $newPageIndex, '
        'chapter $mergedChapterId, needsPush=$needsPush, consistent=$docConsistent)');

    // The pull may have placed us on a different page than the pre-pull
    // one (new pages added, landing shifted). The decode priority loop
    // inside _pullFromDeltaDownload runs against the BEFORE-landing
    // current page, so the AFTER-landing page's images can still be
    // blank bytes-only in state.assetBytes with no ui.Image cached.
    // Without this call the user sees blank images/PDFs until they flip
    // to the next page and back (which triggers decode via goToPage).
    _ensureAssetsForCurrentWindow();

    // Persist the merged state locally. Tracked so closeNotebook() can
    // await it — otherwise exiting immediately after an auto-accept loses
    // the pulled pages (they're in memory but the .ncnote wasn't rewritten
    // in time).
    //
    // Validate BEFORE kicking off the save: the merged state already lives
    // in the notifier's state, so if we let _savePulledChangesLocally's own
    // skip conditions trigger later, the in-memory merge survives but disk
    // never catches up → first re-open reverts to pre-merge .ncnote and
    // the pulled pages silently vanish.
    // Validate against the MERGED document + `mergedPages` (what we actually
    // applied to state and are about to persist), NOT the pull-start snapshot.
    // Persisting the snapshot dropped any strokes/structure the user changed
    // DURING the pull window — they survived in memory but the on-disk
    // .ncnote was written from the older snapshot, so a cold reopen lost them.
    final missingCount = finalDoc.pages
        .where((e) => !mergedPages.containsKey(e.fileName))
        .length;
    if (mergedPages.isEmpty && finalDoc.pages.isNotEmpty) {
      print('[Canvas] acceptRemoteChanges: merged pages empty — '
          'skipping .ncnote persist but refreshing DB metadata');
      // Still refresh the library-visible metadata so the card reflects the
      // (partial) pull — otherwise after a failed pull the notebook is stuck
      // showing the install-time pageCount (e.g. "1 pagina") until the user
      // opens it again and a retry succeeds.
      _pendingPulledLocalSave = _persistPulledMetaOnly(finalMeta);
      return;
    }
    if (missingCount > 0) {
      print('[Canvas] acceptRemoteChanges: $missingCount merged page entries '
          'have no data — skipping .ncnote persist but refreshing DB metadata');
      _pendingPulledLocalSave = _persistPulledMetaOnly(finalMeta);
      return;
    }
    // Two callers reach this point:
    //   a) auto-accept from inside _pullFromDeltaDownload (sync lock ALREADY
    //      held by the enclosing _pullRemoteChanges call), and
    //   b) user tap on the "accept" button in the remote-changes banner
    //      (no lock held — pull already released it long ago).
    //
    // Only (b) can race a concurrent save(): the in-memory state has just
    // been replaced with `repaired.pages`, but the rebuilt ZIP hasn't hit
    // disk yet.  If save() fires first it writes the CORRECT state, then
    // _savePulledChangesLocally lands later with an older snapshot and
    // silently truncates the user's latest edits ("accepted, drew, exited,
    // on re-open stroke is gone").
    //
    // The sync lock already serialises save() / pull correctly for case (a),
    // so all we need in (b) is to hold the lock while this pulled-save
    // actually writes.  `_isPulling` tells us which case we're in.
    if (_isPulling) {
      _pendingPulledLocalSave = _savePulledChangesLocally(
        finalMeta, finalDoc, mergedPages, mergedAssets,
      );
    } else {
      _pendingPulledLocalSave = _runPulledSaveLocked(
        finalMeta, finalDoc, mergedPages, mergedAssets,
      );
    }
  }

  /// Refresh just the SQLite metadata row for a notebook whose pulled
  /// content couldn't be fully materialised on disk (partial pull, missing
  /// page data). Keeps the library card in sync with what the user sees
  /// in memory even when the .ncnote rewrite has to be deferred to a
  /// retry, so a notebook doesn't stay pinned at "1 pagina" after a flaky
  /// first-sync.
  Future<void> _persistPulledMetaOnly(NotebookMetadata metadata) async {
    try {
      final fileService = _ref.read(fileServiceProvider);
      final s = state;
      final existingSize = s == null
          ? 0
          : (await fileService.readNotebookFile(metadata.id))?.length ?? 0;
      await fileService.upsertNotebookMeta(
        id: metadata.id,
        title: metadata.title,
        remotePath: s?.remotePath ?? '',
        // Leave syncStatus as 'modified' so the next sync cycle will retry
        // the missing pages (synced would mask the incomplete state).
        etag: _remoteMetaEtag,
        // Use now() — see _savePulledChangesLocally for the rationale:
        // the library's overwrite guard compares local_modified_at against
        // the root .ncnote's server mtime. If we stamp a server timestamp
        // here, the next library refresh sees "server newer" and trample
        // our pulled state.
        localModifiedAt: DateTime.now(),
        syncStatus: 'modified',
        fileSize: existingSize,
        coverColor: metadata.coverColor,
        paperType: metadata.paperType,
        pageCount: metadata.pageCount,
        createdAt: metadata.createdAt,
      );
      print('[Canvas] Refreshed DB meta for partial pull '
          '(pageCount=${metadata.pageCount})');
    } catch (e) {
      print('[Canvas] Could not refresh DB meta after partial pull: $e');
    }
  }

  /// Runs [_savePulledChangesLocally] while holding the sync lock so a
  /// concurrent `save()` can't land a newer ZIP on disk before the pulled
  /// state has been persisted (or vice-versa — either ordering loses data
  /// when they run in parallel).
  Future<void> _runPulledSaveLocked(
    NotebookMetadata metadata,
    DocumentStructure document,
    Map<String, PageData> pages,
    Map<String, Uint8List> assets,
  ) async {
    final pulledSaveToken = await _acquireSyncLock();
    if (pulledSaveToken == null) return;
    try {
      await _savePulledChangesLocally(metadata, document, pages, assets);
    } finally {
      _releaseSyncLock(pulledSaveToken);
    }
  }

  /// User dismissed the incoming remote changes — keep local state.
  /// The changes are discarded; they won't re-appear until the remote
  /// side is modified again (ETags already updated).
  void dismissRemoteChanges() {
    if (state == null) return;
    state = state!.copyWith(clearPendingRemoteChanges: true);
    print('[Canvas] User dismissed remote changes');
  }

  /// User resolved per-page conflicts via visual diff screen.
  /// [resolutions]: fileName → true=keep local, false=accept remote.
  void resolveConflicts(Map<String, bool> resolutions) {
    if (state == null || state!.pendingConflicts.isEmpty) return;
    final s = state!;
    final updatedPages = Map<String, PageData>.from(s.pages);
    // fileNames whose remote DELETION the user accepted — these get purged
    // locally (and from the document) instead of copied back from remote.
    final removedByDeletion = <String>{};
    var anyRemoteAccepted = false;
    var anyLocalKept = false;

    for (final conflict in s.pendingConflicts) {
      final keepLocal = resolutions[conflict.fileName] ?? true;
      if (conflict.isDeletion) {
        // Edit-vs-delete conflict: `remotePage` is a placeholder (== local),
        // so the old code's `updatedPages[fn] = remotePage` was a no-op that
        // resurrected the page on BOTH choices → the delete could never win
        // and the two devices ping-ponged forever.
        if (keepLocal) {
          // Reject the deletion: keep + re-upload so the page comes back on
          // the server for the device that deleted it. The re-upload is
          // forced by dropping the page's baseline entry below.
          anyLocalKept = true;
          print('[Canvas] Deletion conflict → KEEP LOCAL (resurrect): '
              '${conflict.fileName}');
        } else {
          // Honour the deletion: drop locally. The server already removed it,
          // so no upload is needed — just purge local traces so the page is
          // not re-detected as a change on the next pull.
          updatedPages.remove(conflict.fileName);
          removedByDeletion.add(conflict.fileName);
          anyRemoteAccepted = true;
          print('[Canvas] Deletion conflict → ACCEPT REMOTE (delete): '
              '${conflict.fileName}');
        }
      } else if (!keepLocal) {
        updatedPages[conflict.fileName] = conflict.remotePage;
        anyRemoteAccepted = true;
        print('[Canvas] Conflict resolved → REMOTE: ${conflict.fileName}');
      } else {
        anyLocalKept = true;
        // The page must be re-uploaded (the server still holds the rejected
        // remote version) — forced by dropping its baseline entry below.
        print('[Canvas] Conflict resolved → LOCAL: ${conflict.fileName}');
      }
    }

    // Rebuild the document without pages whose remote deletion was accepted,
    // so the document never points at missing page data (the "Nessuna
    // pagina" ghost-entry bug). Renumber to keep pageNumbers sequential.
    DocumentStructure updatedDoc = s.document;
    if (removedByDeletion.isNotEmpty) {
      final kept = s.document.pages
          .where((e) => !removedByDeletion.contains(e.fileName))
          .toList();
      for (var i = 0; i < kept.length; i++) {
        kept[i] = kept[i].copyWith(pageNumber: i + 1);
      }
      updatedDoc = DocumentStructure(
        notebookId: s.document.notebookId,
        formatVersion: s.document.formatVersion,
        pages: kept,
      );
    }

    // For pages whose LOCAL version won the conflict, DROP the baseline
    // entry so _saveInner's identity diff flags the page as changed and the
    // triggered save actually re-uploads it. (Setting baseline to the live
    // object here made keep-local a silent no-op: the diff saw no change,
    // nothing was uploaded, and the server kept the rejected version
    // forever.) For pages where remote won, baseline is the new (remote)
    // content — already on the server, nothing to upload. Pages whose
    // deletion we accepted are purged from every tracking map so they can't
    // be resurrected by a later diff.
    //
    // IMPORTANT: pages NOT involved in the conflict keep their previous
    // _lastSyncedPages entry intact — overwriting with the current in-memory
    // page would hide legitimate local edits on unrelated pages.
    final newBaseline = Map<String, PageData>.from(_lastSyncedPages);
    for (final conflict in s.pendingConflicts) {
      if (removedByDeletion.contains(conflict.fileName)) {
        newBaseline.remove(conflict.fileName);
        _lastPageEtags.remove(conflict.fileName);
      } else if (resolutions[conflict.fileName] ?? true) {
        newBaseline.remove(conflict.fileName);
      } else {
        newBaseline[conflict.fileName] = updatedPages[conflict.fileName]!;
      }
    }
    _lastSyncedPages = newBaseline;

    // A removed page may have left currentPageIndex past the end.
    final newIndex = updatedDoc.pages.isEmpty
        ? 0
        : s.currentPageIndex.clamp(0, updatedDoc.pages.length - 1);

    state = s.copyWith(
      pages: updatedPages,
      document: updatedDoc,
      currentPageIndex: newIndex,
      isDirty: anyRemoteAccepted || anyLocalKept || s.isDirty,
      clearPendingConflicts: true,
    );

    // Save merged result locally + trigger sync whenever the user touched
    // the conflict set, regardless of direction — keep-local still needs an
    // upload so the server reflects the user's chosen version.
    if (anyRemoteAccepted || anyLocalKept) {
      _triggerSaveAfterConflictResolution();
    }
  }

  /// Keep all local versions, discard conflicts.
  void dismissConflicts() {
    if (state == null) return;
    final s = state!;
    // Update the baseline ONLY for the conflicted pages so the next pull
    // doesn't re-detect the same edits. Unrelated pages keep their previous
    // baseline entry — overwriting the whole map with `s.pages` made every
    // unsaved local edit on non-conflicted pages look already-synced,
    // silently excluding it from all future saves.
    final newBaseline = Map<String, PageData>.from(_lastSyncedPages);
    for (final conflict in s.pendingConflicts) {
      final live = s.pages[conflict.fileName];
      if (live != null) newBaseline[conflict.fileName] = live;
    }
    _lastSyncedPages = newBaseline;
    state = s.copyWith(clearPendingConflicts: true);
    print('[Canvas] User dismissed all conflicts (kept local)');
  }

  /// After conflict resolution, save merged state.
  Future<void> _triggerSaveAfterConflictResolution() async {
    if (state == null) return;
    // Mark dirty so save() picks it up
    state = state!.copyWith(isDirty: true);
    await save();
  }

  /// Accept remote changes and navigate to a specific page.
  void acceptAndGoToPage(int pageIndex) {
    acceptRemoteChanges();
    if (state != null && pageIndex >= 0 && pageIndex < state!.document.pages.length) {
      goToPage(pageIndex);
    }
  }

  /// Resolve chapter name for a page entry.
  static String? _chapterNameForPage(PageEntry? pageEntry, NotebookMetadata meta) {
    if (pageEntry == null || pageEntry.chapterId == null) return null;
    final idx = meta.chapters.indexWhere((c) => c.id == pageEntry.chapterId);
    return idx >= 0 ? meta.chapters[idx].title : null;
  }

  /// Count elements by type in a page: (strokes, images, shapes, texts).
  static (int, int, int, int) _elementCounts(PageData? page) {
    if (page == null) return (0, 0, 0, 0);
    var strokes = 0, images = 0, shapes = 0, texts = 0;
    for (final el in page.layers.content) {
      el.map(
        stroke: (_) => strokes++,
        image: (_) => images++,
        shape: (_) => shapes++,
        text: (_) => texts++,
        math: (_) => 0,
      );
    }
    return (strokes, images, shapes, texts);
  }

  /// Track an asset as dirty when added/modified (e.g. image paste/add).
  void _markAssetDirty(String assetKey) {
    _dirtyAssetKeys.add(assetKey);
  }

  /// Build a ZIP from the pulled state and save it locally so changes
  /// survive close/reopen without re-downloading.
  ///
  /// PARTIAL saves are allowed: if the document references pages whose data
  /// hasn't been pulled yet, they're silently dropped from the stored ZIP
  /// AND from the stored document, so the library card stays accurate and
  /// the next pull will re-request them via the "missingLocally" branch of
  /// `_pullFromDeltaInner`.  This replaces the old behaviour that REFUSED
  /// to save on any missing page — that guard was meant to prevent a
  /// "Nessuna pagina" state but in practice it meant that on a 100-page
  /// first-time pull a single transient failure threw away every already-
  /// downloaded page, forcing the whole thing to restart from zero on every
  /// app launch.
  Future<void> _savePulledChangesLocally(
    NotebookMetadata metadata,
    DocumentStructure document,
    Map<String, PageData> pages,
    Map<String, Uint8List> assets,
  ) async {
    // Total abort only when we'd save a wholly empty notebook on top of a
    // non-empty one — that's a sign the call chain is broken, not a
    // recoverable missing-page scenario.
    if (pages.isEmpty && document.pages.isNotEmpty) {
      print('[Canvas] _savePulledChangesLocally: refusing to save — '
          'pages map is empty but document has ${document.pages.length} entries');
      return;
    }

    // Drop document entries whose page data is missing so the saved ZIP is
    // internally consistent (every PageEntry has matching page bytes).  The
    // server's canonical document structure is preserved via the delta
    // folder; the next pull re-discovers the dropped entries as new pages
    // and merges them in.
    DocumentStructure persistedDoc = document;
    NotebookMetadata persistedMeta = metadata;
    final missingEntries = document.pages
        .where((e) => !pages.containsKey(e.fileName))
        .toList();
    if (missingEntries.isNotEmpty) {
      print('[Canvas] _savePulledChangesLocally: saving PARTIAL snapshot — '
          '${missingEntries.length} / ${document.pages.length} entries have '
          'no data yet, deferred to next pull');
      persistedDoc = DocumentStructure(
        notebookId: document.notebookId,
        formatVersion: document.formatVersion,
        pages: document.pages
            .where((e) => pages.containsKey(e.fileName))
            .toList(),
      );
      persistedMeta = metadata.copyWith(
        pageCount: persistedDoc.pages.length,
      );
    }

    try {
      final fileService = _ref.read(fileServiceProvider);
      final symbolLibs = state?.symbolLibraries
          .map((l) => l.toJson())
          .toList();
      // Pulled pages are all new to us, so the cache will miss for each of
      // them and re-encode. This is fine — happens once after a remote pull.
      final encodedPages = await _encodePagesWithCache(pages);
      final wrappedAssets = await _wrapAssetsForIsolate(assets);
      final transferred = await compute(_buildPackageInIsolate, _PackageParams(
        metadata: persistedMeta,
        document: persistedDoc,
        encodedPages: encodedPages,
        assets: wrappedAssets,
        symbolLibraries: symbolLibs,
      ));
      final package = transferred.materialize().asUint8List();
      await fileService.saveNotebookFile(metadata.id, package);
      // Also update DB metadata so the library screen reflects the pulled
      // title, page count, cover colour, etc. without a full re-download.
      // Pass _remoteMetaEtag so the delta ETag is preserved in the DB row —
      // without it upsertNotebookMeta (ConflictAlgorithm.replace) erases the
      // ETag, making _syncWithServer think the notebook changed and re-download
      // the stale server .ncnote on every library refresh.
      //
      // localModifiedAt MUST reflect when WE wrote the local file, not when
      // the server's metadata.json claims the notebook was modified. The
      // library uses localModifiedAt vs server.lastModified to decide
      // whether to overwrite the local .ncnote — if we pass the server's
      // (possibly stale) timestamp, the next library refresh will think
      // the server is newer and trample our freshly-hydrated pages.
      await fileService.upsertNotebookMeta(
        id: metadata.id,
        title: metadata.title,
        remotePath: state?.remotePath ?? '',
        etag: _remoteMetaEtag,  // keep delta ETag across pull-saves
        localModifiedAt: DateTime.now(),
        syncStatus: 'synced',
        fileSize: package.length,
        coverColor: metadata.coverColor,
        paperType: metadata.paperType,
        pageCount: metadata.pageCount,
        createdAt: metadata.createdAt,
      );
      print('[Canvas] Saved pulled changes locally (${package.length} bytes)');
    } catch (e) {
      print('[Canvas] Failed to save pulled changes locally: $e');
    }
  }

  /// Encodes every page in [pages] to JSON bytes, reusing cached encodings for
  /// pages whose [PageData] instance hasn't changed since the last save.
  ///
  /// Returns a fresh Map safe to ship to a background isolate. Stale cache
  /// entries (for pages that were deleted) are evicted.
  ///
  /// Yields to the event loop every [_encodeYieldBatch] pages so first-save
  /// on a large notebook (e.g. 140 pages) doesn't block the UI thread for
  /// hundreds of ms on low-end hardware (Linux laptops, iPads, phones).
  /// Cache hits are free — the yield only fires during actual re-encoding.
  /// [evictMissing] must stay true only when [pages] is the FULL page
  /// map — the eviction pass treats anything not in [pages] as deleted.
  /// The dirty-only pre-encode in [_saveInner] passes false.
  Future<Map<String, Uint8List>> _encodePagesWithCache(
    Map<String, PageData> pages, {
    bool evictMissing = true,
  }) async {
    final result = <String, Uint8List>{};
    final seen = <String>{};
    var encodedSinceYield = 0;
    for (final entry in pages.entries) {
      seen.add(entry.key);
      final cached = _pageJsonCache[entry.key];
      if (cached != null && identical(cached.page, entry.value)) {
        result[entry.key] = cached.bytes;
        continue;
      }
      // Cache miss → a real jsonEncode is coming (10-50 ms for a dense
      // page). Hold it while the pen is down so the encode chunk never
      // steals pointer samples from a stroke in progress.
      await _waitForQuietPointer();
      final bytes = Uint8List.fromList(
          utf8.encode(compactPageJson(entry.value)));
      _pageJsonCache[entry.key] = _CachedPageJson(entry.value, bytes);
      result[entry.key] = bytes;
      encodedSinceYield++;
      if (encodedSinceYield >= _encodeYieldBatch) {
        encodedSinceYield = 0;
        await Future<void>.delayed(Duration.zero);
      }
    }
    // Evict deleted pages from the cache.
    if (evictMissing) {
      _pageJsonCache.removeWhere((k, _) => !seen.contains(k));
    }
    return result;
  }

  static const int _encodeYieldBatch = 3;
}

/// Compact JSON encode for a PageData.
///
/// Two reductions applied:
///
/// (1) Doubles rounded to 3 decimals (sub-1‰ — well below visible
///     pixel precision and finer than the tablet's 10-bit ADC).
///
/// (2) StrokePoint objects emitted as compact arrays
///     `[x, y, pressure?, tilt?, timestamp?]` with trailing defaults
///     omitted. A point with pressure=0.5, tilt=0, timestamp=0
///     becomes `[x, y]` (2 elements) instead of a 5-field object.
///     Decoder counter-part is [_expandStrokePointsInPlace] (applied
///     via [decodePageData]) which restores the map form before
///     handing to the generated PageData.fromJson.
///
/// Combined effect on a typical 100-point stroke: JSON drops from
/// ~8-10 KB to ~1.5-2.5 KB (75-85% smaller). Same wire schema for
/// the surrounding tree, both forms accepted on read so old notebooks
/// continue to load unchanged.
String compactPageJson(PageData page) {
  final raw = page.toJson();
  final rounded = _roundFloatsInPlace(raw);
  _compactStrokePointsInPlace(rounded);
  return jsonEncode(rounded);
}

/// Counterpart to [compactPageJson]. Mutates [json] in-place to
/// expand any compact `[x,y,p,t,ts]` arrays back into full maps so
/// the generated `PageData.fromJson` (which casts each point to
/// `Map<String, dynamic>`) accepts them. Old maps are left untouched.
/// Always run this before `PageData.fromJson` on any deserialized
/// notebook JSON — it's a cheap no-op when no compact points exist.
PageData decodePageData(Map<String, dynamic> json) {
  _expandStrokePointsInPlace(json);
  return PageData.fromJson(json);
}

Object? _roundFloatsInPlace(Object? v) {
  if (v is double) {
    // Arithmetic rounding, NOT double.parse(v.toStringAsFixed(3)): the
    // string round-trip allocates+parses a String per double, and a
    // dense page is ~80k doubles — that was measurable jank on every
    // save since encoding runs on the main thread. The two roundings
    // can differ by 1 ulp on ties, irrelevant at page-coordinate scale.
    return v.isFinite ? (v * 1000).round() / 1000 : v;
  }
  if (v is Map) {
    final out = <String, Object?>{};
    v.forEach((k, val) {
      out[k as String] = _roundFloatsInPlace(val);
    });
    return out;
  }
  if (v is List) {
    return v.map(_roundFloatsInPlace).toList(growable: false);
  }
  return v;
}

/// Walk the page JSON tree and replace `points: [{...}, {...}]` lists
/// inside a `stroke` ContentElement with compact `points: [[x,y,..], ..]`.
/// Operates in place on the tree produced by toJson() — only the
/// `points` list under each stroke element is mutated, the rest of
/// the structure (zIndex, id, data wrapper, type) stays intact.
void _compactStrokePointsInPlace(Object? v) {
  if (v is Map) {
    if (v['type'] == 'stroke') {
      final data = v['data'];
      if (data is Map && data['points'] is List) {
        final pts = data['points'] as List;
        for (var i = 0; i < pts.length; i++) {
          final p = pts[i];
          if (p is Map) pts[i] = _pointMapToArray(p);
        }
      }
    }
    v.forEach((_, val) {
      if (val is Map || val is List) _compactStrokePointsInPlace(val);
    });
  } else if (v is List) {
    for (final item in v) { _compactStrokePointsInPlace(item); }
  }
}

List<num> _pointMapToArray(Map p) {
  final x = p['x'] as num;
  final y = p['y'] as num;
  final pr = (p['pressure'] as num?) ?? 0.5;
  final t = (p['tilt'] as num?) ?? 0.0;
  final ts = (p['timestamp'] as num?) ?? 0;
  // Trim trailing defaults so quick taps / mouse strokes (no real
  // pressure or timestamp) compact to just [x, y].
  if (ts == 0 && t == 0.0 && pr == 0.5) return <num>[x, y];
  if (ts == 0 && t == 0.0) return <num>[x, y, pr];
  if (ts == 0) return <num>[x, y, pr, t];
  return <num>[x, y, pr, t, ts];
}

/// Counterpart of [_compactStrokePointsInPlace]. Walks the JSON
/// produced by [jsonDecode] and expands any array-form points
/// back into the map form the generated fromJson expects. Idempotent
/// when no compact points are present (old notebooks).
void _expandStrokePointsInPlace(Object? v) {
  if (v is Map) {
    if (v['type'] == 'stroke') {
      final data = v['data'];
      if (data is Map && data['points'] is List) {
        final pts = data['points'] as List;
        for (var i = 0; i < pts.length; i++) {
          final p = pts[i];
          if (p is List) pts[i] = _pointArrayToMap(p);
        }
      }
    }
    v.forEach((_, val) {
      if (val is Map || val is List) _expandStrokePointsInPlace(val);
    });
  } else if (v is List) {
    for (final item in v) { _expandStrokePointsInPlace(item); }
  }
}

Map<String, dynamic> _pointArrayToMap(List p) {
  final out = <String, dynamic>{'x': p[0], 'y': p[1]};
  if (p.length > 2) out['pressure'] = p[2];
  if (p.length > 3) out['tilt'] = p[3];
  if (p.length > 4) out['timestamp'] = p[4];
  return out;
}

/// Parameters for the isolate packaging function.
class _PackageParams {
  final NotebookMetadata metadata;
  final DocumentStructure document;
  /// Pre-encoded page JSON bytes keyed by page file name. Encoding is done on
  /// the main thread so unchanged pages can skip re-encoding via a cache in
  /// [CanvasNotifier]. The isolate only ZIPs these bytes.
  final Map<String, Uint8List> encodedPages;
  /// Asset bytes wrapped in [TransferableTypedData] so the isolate
  /// boundary is a zero-second-copy hand-off. SendPort would otherwise
  /// memcpy all 150 MB of asset bytes for a typical PDF-heavy notebook
  /// — the transfer keeps the peak resident memory at 1× instead of 2×,
  /// which is the difference between "save" and "iOS jetsam kills the
  /// app" on iPad. Materialised on the isolate side.
  final Map<String, TransferableTypedData>? assets;
  final List<Map<String, dynamic>>? symbolLibraries;

  _PackageParams({
    required this.metadata,
    required this.document,
    required this.encodedPages,
    this.assets,
    this.symbolLibraries,
  });
}

/// Tiny record tying cached encoded bytes to the exact [PageData] instance
/// they were produced from. Identity check (`identical`) is enough because
/// [PageData] is a freezed/immutable model.
class _CachedPageJson {
  final PageData page;
  final Uint8List bytes;
  const _CachedPageJson(this.page, this.bytes);
}

/// Top-level function run inside [Isolate.run] via [compute].
/// Builds + validates the .ncnote ZIP package off the main thread.
///
/// Returns the bytes wrapped in [TransferableTypedData] so `compute()`'s reply
/// is a zero-copy ownership transfer, NOT a memcpy of the whole ZIP onto the
/// UI isolate's thread when the message is received. On a large full-notebook
/// package (seen here at ~232 MB) that return-copy was a multi-frame stall on
/// the main isolate — the periodic hitch felt while writing, as the 15 s forced
/// autosave landed. Symmetric with the asset hand-off INTO the isolate
/// ([_PackageParams.assets]), which already transfers instead of copying.
TransferableTypedData _buildPackageInIsolate(_PackageParams p) {
  // Create a throwaway SyncService-less package builder (static-ish logic).
  final archive = Archive();

  // IMPORTANT: Use utf8.encode() first, then .length for the byte count.
  // String.length returns UTF-16 code units, which differs from UTF-8 byte
  // length for non-ASCII characters (e.g. accented Italian letters).
  final metaBytes = utf8.encode(jsonEncode(p.metadata.toJson()));
  archive.addFile(ArchiveFile(AppConfig.metadataFile, metaBytes.length, metaBytes));

  final docBytes = utf8.encode(jsonEncode(p.document.toJson()));
  archive.addFile(ArchiveFile(AppConfig.documentFile, docBytes.length, docBytes));

  for (final entry in p.encodedPages.entries) {
    archive.addFile(ArchiveFile(
      '${AppConfig.pagesDir}/${entry.key}',
      entry.value.length,
      entry.value,
    ));
  }

  if (p.assets != null) {
    for (final entry in p.assets!.entries) {
      // Materialise the transferred typed data into a real Uint8List
      // for the archive. After this the source isolate's wrapper is
      // invalidated — but the source already let the wrapper go out
      // of scope by passing it through compute(), so that's fine.
      final bytes = entry.value.materialize().asUint8List();
      // STORE already-compressed assets (PNG/JPEG/PDF/...): re-deflating
      // them was the dominant CPU cost of every autosave's local ZIP
      // rebuild on image-heavy notebooks, for a ~0-3% size gain.
      archive.addFile(ArchiveFile(
        '${AppConfig.assetsDir}/${entry.key}',
        bytes.length,
        bytes,
      )..compress = !SyncService.isPrecompressedAsset(entry.key));
    }
  }

  if (p.symbolLibraries != null && p.symbolLibraries!.isNotEmpty) {
    final symbolsBytes = utf8.encode(jsonEncode(p.symbolLibraries));
    archive.addFile(ArchiveFile('symbols.json', symbolsBytes.length, symbolsBytes));
  }

  final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

  // Validate the produced archive
  SyncService.validateNcnoteArchive(bytes, context: 'isolate-build ${p.metadata.title}');

  // Transfer ownership back to the caller (no copy on the receiving isolate).
  return TransferableTypedData.fromList([bytes]);
}
