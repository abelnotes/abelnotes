import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/cross_notebook_clipboard_provider.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/providers/remote_store_provider.dart'
    show remoteStoreProvider;
import 'package:abelnotes/core/services/sync_thrift.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart'
    show
        CanvasRenderEngine,
        ballpointWidthFactor,
        penWidthFactor,
        circleDragBox,
        circleResizeBox,
        scaledShapeResizeBox;
import 'package:abelnotes/features/canvas/data/math_rasterizer.dart';
import 'package:abelnotes/features/pages_tray/domain/page_transfer.dart';
import 'package:abelnotes/features/canvas/data/shape_recognizer.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/shared/utils/rich_paste.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas/asset_cache.dart';
import 'package:abelnotes/core/providers/canvas/clipboard_actions.dart';
import 'package:abelnotes/core/providers/canvas/element_editor.dart';
import 'package:abelnotes/core/providers/canvas/eraser_throttle.dart';
import 'package:abelnotes/core/providers/canvas/notebook_save.dart';
import 'package:abelnotes/core/providers/canvas/pages_and_chapters.dart';
import 'package:abelnotes/core/providers/canvas/pdf_sources.dart';
import 'package:abelnotes/core/providers/canvas/selection_actions.dart';
import 'package:abelnotes/core/providers/canvas/sync_pull.dart';
import 'package:abelnotes/core/providers/canvas/sync_push.dart';
import 'package:abelnotes/core/providers/canvas/sync_session.dart';
import 'package:abelnotes/core/providers/canvas/symbols_library.dart';
import 'package:abelnotes/core/providers/canvas/thumbnails.dart';
import 'package:abelnotes/core/providers/canvas/tool_prefs.dart';
import 'package:abelnotes/core/notebook/page_codec.dart';
import 'package:abelnotes/features/canvas/data/element_geometry.dart';
import 'package:abelnotes/features/canvas/data/pdf_text_carry.dart';
import 'package:abelnotes/features/canvas/data/pdf_export.dart' show hasFullPageBackground;
import 'package:abelnotes/core/sync/page_merge.dart' as page_merge;
import 'package:abelnotes/core/sync/stroke_ops.dart' show StrokeOps, splitPageVersion;
import 'package:abelnotes/core/sync/page_merge.dart'
    hide rebaseHistoryOnMerge, placeByLocalOrder;
// Re-export so all existing import canvas_provider.dart files keep getting
// CanvasState, CanvasTool, PaperType, etc. without any change.
export 'package:abelnotes/core/providers/canvas_state.dart';
export 'package:abelnotes/core/notebook/page_codec.dart';
export 'package:abelnotes/features/canvas/data/pdf_text_carry.dart';

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

class CanvasNotifier extends StateNotifier<CanvasState?> implements CanvasCore {
  final Ref _ref;
  @override
  Ref get ref => _ref;
  @override
  bool get isDisposed => _disposed;
  late final ToolPrefs _toolPrefs;
  late final SyncSession _sync = SyncSession(isDisposed: () => _disposed);
  late final SymbolsLibrary _symbolsLib = SymbolsLibrary(this);
  late final AssetCache _assets = AssetCache(this);
  late final PdfSources _pdfSources =
      PdfSources(this, _allReferencedAssetIds);
  late final EraserThrottle _eraser = EraserThrottle(this);
  late final ElementEditor _elements = ElementEditor(this, _assets);
  late final SelectionActions _selection = SelectionActions(this);
  late final ClipboardActions _clip =
      ClipboardActions(this, _assets, _selection.applySelectionTransform);
  late final NotebookSave _save = NotebookSave(
    this,
    writeBlocked: () => _preview || _loadingSnapshotId != null,
    persistUnpushedBase: _persistUnpushedBase,
    encodePages: _encodePagesWithCache,
    chaptersWithMembership: _chaptersWithMembership,
    remoteMetaEtag: () => _sync.remoteMetaEtag,
    persistRemoteMetaEtag: _persistRemoteMetaEtag,
    persistLastPageEtags: _persistLastPageEtags,
  );
  late final PagesAndChapters _pages =
      PagesAndChapters(this, _assets, _nextPageFileName);
  late final Thumbnails _thumbnails = Thumbnails(this, _waitForQuietPointer);
  late final SyncPull _pull = SyncPull(
    this,
    _sync,
    isPullingFromRemote: isPullingFromRemote,
    pullProgress: pullProgress,
    pdfSources: _pdfSources,
    assets: _assets,
    isPreview: () => _preview,
    isLocalOnly: _isLocalOnly,
    acquireSyncLock: _sync.acquireLock,
    releaseSyncLock: _sync.releaseLock,
    persistLastPageEtags: _persistLastPageEtags,
    persistRemoteMetaEtag: _persistRemoteMetaEtag,
    savePulledChangesLocally: _savePulledChangesLocally,
    onRemoteReachable: _push.onRemoteReachable,
    remoteNotebookGone: _push.remoteNotebookGone,
    onRemoteNotebookGone: _push.onRemoteNotebookGone,
    reportReachable: _reportReachable,
    recomputeSyncStatus: _recomputeSyncStatus,
    save: save,
    acceptRemoteChanges: acceptRemoteChanges,
    filenameNum: _filenameNum,
    chapterByPageId: _chapterByPageId,
  );
  late final SyncPush _push = SyncPush(
    this,
    _sync,
    save: _save,
    pdfSources: _pdfSources,
    remoteSaveInFlight: remoteSaveInFlight,
    keptLocal: keptLocal,
    isLocalOnly: _isLocalOnly,
    markLocalOnly: (id) => _localOnlyCache[id] = true,
    persistUnpushedBase: _persistUnpushedBase,
    clearUnpushedBase: _clearUnpushedBase,
    persistPendingDeletes: _persistPendingDeletes,
    persistPendingMetaCommit: _persistPendingMetaCommit,
    persistRemoteMetaEtag: _persistRemoteMetaEtag,
    persistLastPageEtags: _persistLastPageEtags,
    reportStorageFull: _reportStorageFull,
    reportReachable: _reportReachable,
    recomputeSyncStatus: _recomputeSyncStatus,
    pullRemoteChanges: () => _pull.pullRemoteChanges(),
    deltaMetaEtagPrefsKey: _deltaMetaEtagPrefsKey,
    pageEtagsPrefsKey: _pageEtagsPrefsKey,
  );

  // Pen diagnostics (CrashLogger.verboseEnabled): the last committed stroke,
  // so a state write that drops it is logged with the writer's stack.
  String? _diagStrokeId;
  String? _diagStrokePage;

  @override
  set state(CanvasState? value) {
    final id = _diagStrokeId;
    if (id != null && value != null && CrashLogger.verboseEnabled) {
      final page = value.pages[_diagStrokePage];
      if (page != null && !page.layers.content.any((e) => e.id == id)) {
        _diagStrokeId = null;
        CrashLogger.append('[StrokeDbg] STROKE-LOST $id '
            'undo=${value.undoStack.length}\n${StackTrace.current}');
      }
    }
    super.state = value;
  }
  Size? _viewportSize;

  bool _disposed = false;

  /// Incremented every time [openNotebook] runs. A deferred [closeNotebook]
  /// compares its starting generation against this — if the user re-opens
  /// a notebook before the previous close's teardown lands, the newer open
  /// would otherwise see its freshly-set state immediately nulled out,
  /// producing a stuck "Nessun notebook aperto" canvas.
  int _openGeneration = 0;

  static const int _maxPreSaveGuardAborts = 3;
  static const Duration _preSaveGuardWindow = Duration(seconds: 10);

  /// Cache of encoded page JSON bytes per fileName. Reused when the current
  /// [PageData] instance is identical to the one that produced the cached
  /// bytes — i.e. the page wasn't mutated since the last save. For big
  /// notebooks where only one page changes per save, this avoids re-encoding
  /// every other page on every write.
  final Map<String, _CachedPageJson> _pageJsonCache = {};

  /// True while a multi-step bulk operation (e.g. PDF import) is in
  /// progress. Pull cycles are suppressed so an intervening network
  /// round-trip cannot re-order document.pages mid-insert and corrupt
  /// chapter assignments or currentPageIndex.
  bool _bulkOperationInProgress = false;

  /// Pause automatic remote pulls. Call [endBulkOperation] when done.
  void beginBulkOperation() => _bulkOperationInProgress = true;

  /// Resume automatic remote pulls after a bulk operation.
  void endBulkOperation() => _bulkOperationInProgress = false;

  @override
  bool get bulkOperationInProgress => _bulkOperationInProgress;

  // ── Page filename helpers ────────────────────────────────────────────────

  /// Returns a safe, non-colliding fileName for a **new** page.
  ///
  /// Uses `max(existing numeric suffix) + 1` rather than
  /// `document.pages.length + 1`.  The two values diverge whenever pages
  /// are reordered, deleted, or merged from multiple sessions — which is
  /// exactly when the simple `length + 1` scheme re-uses an already-taken
  /// number and causes the "chapter mixing / duplicate page" bug.
  /// `page_NNN.json`, or `page_NNN_xxxx.json` for pages created here: two
  /// devices adding a page before syncing used to mint the same name, and
  /// the merge then fused the two different pages into one.
  static final _pageFileRe = RegExp(r'page_(\d+)(?:_[a-z0-9]+)?\.json');
  static final _rand = Random.secure();
  static String _mintPageFileName(int number) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final tag =
        List.generate(4, (_) => chars[_rand.nextInt(chars.length)]).join();
    return 'page_${number.toString().padLeft(3, '0')}_$tag.json';
  }

  String _nextPageFileName(CanvasState s) {
    int maxNum = s.document.pages.length; // safe lower bound
    for (final p in s.document.pages) {
      final m = _pageFileRe.firstMatch(p.fileName);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > maxNum) maxNum = n;
      }
    }
    return _mintPageFileName(maxNum + 1);
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
      final m = _pageFileRe.firstMatch(p.fileName);
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
        final newFileName = _mintPageFileName(maxNum);
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


  @visibleForTesting
  static PageData unionPageElementsForTest(
          {required PageData local, required PageData remote}) =>
      unionPageElements(local: local, remote: remote);

  static List<UndoEntry> rebaseHistoryOnMerge(List<UndoEntry> stack,
          Map<String, PageData> before, Map<String, PageData> after) =>
      page_merge.rebaseHistoryOnMerge(stack, before, after);

  @visibleForTesting
  static List<PageEntry> placeByLocalOrder(List<PageEntry> base,
          List<PageEntry> extras, List<PageEntry> localOrder) =>
      page_merge.placeByLocalOrder(base, extras, localOrder);

  @visibleForTesting
  static PageData? mergePageElementsForTest(
          {required PageData base,
          required PageData local,
          required PageData remote}) =>
      mergePageElements(base: base, local: local, remote: remote);

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

  /// Bumped whenever [CanvasState.imageCache] changes (decode lands, eviction,
  /// pull merge); the painter repaints on it instead of watching Riverpod.
  ValueNotifier<int> get imageCacheVersion => _assets.imageCacheVersion;

  /// Typeset-math rasters (derived, never in CanvasState), read by the painter.
  Map<String, MathRaster> get mathCache => _assets.mathCache;

  /// Bumped when [mathCache]/[failedMathKeys] changes.
  ValueNotifier<int> get mathCacheVersion => _assets.mathCacheVersion;

  /// Cache keys whose rasterize permanently failed; drawn as a source fallback.
  Set<String> get failedMathKeys => _assets.failedMathKeys;

  void requestMathRaster(String latex, int colorArgb, double fontSize,
          bool displayMode, double pixelRatio) =>
      _assets.requestMathRaster(
          latex, colorArgb, fontSize, displayMode, pixelRatio);

  /// Rasterize a math element to its intrinsic logical size, null on failure.
  Future<Size?> measureMath(
    String latex, {
    required int colorArgb,
    required double fontSize,
    required bool displayMode,
    double pixelRatio = 3.0,
  }) =>
      _assets.measureMath(latex,
          colorArgb: colorArgb,
          fontSize: fontSize,
          displayMode: displayMode,
          pixelRatio: pixelRatio);

  /// Asset ids classified as corrupt (decode failed), for UI placeholders.
  Set<String> get corruptAssetIds => _assets.corruptAssetIds;

  /// Asset ids being fetched from the server right now (loading placeholder).
  Set<String> get loadingAssetIds => _assets.loadingAssetIds;

  /// Decode every image of the current page, fire-and-forget (PDF import end).
  void ensureCurrentPageImagesDecoded() =>
      _assets.ensureCurrentPageImagesDecoded();

  /// Page manager hook: decode the asset behind a thumbnail on demand.
  void ensureAssetDecodedForThumbnail(String assetId) =>
      _assets.ensureAssetDecodedForThumbnail(assetId);

  /// Dispose every GPU-backed image texture (called on `detached`).
  void releaseImageCache() => _assets.releaseImageCache();

  /// Bumped when source PDFs of imported pages arrive from the server.
  ValueNotifier<int> get pdfSourcesVersion => _pdfSources.version;

  /// A PDF import wrote a source PDF: the next sync takes it to the server.
  void notePdfSourcesChanged() => _pdfSources.noteChanged();

  /// Last eraser sub-mode the user explicitly picked. Tapping the
  /// toolbar's eraser button restores THIS instead of always falling
  /// back to eraserStroke — fixes the bug where eraser-area → pen →
  /// eraser would reset back to eraser-stroke.
  CanvasTool get lastEraserMode => _toolPrefs.lastEraserMode;

  CanvasNotifier(this._ref) : super(null) {
    // Restore per-tool preferences from SharedPreferences ASAP so the
    // very first tool the user touches already shows the previous
    // session's width/color/eraser size.
    _toolPrefs = ToolPrefs(this);
    // A new client (re-login after a password change, reconnect) ends the
    // failure streak: push what is waiting instead of sleeping out the backoff.
    _ref.listen(remoteStoreProvider, (prev, next) {
      if (next == null || _disposed || state == null) return;
      _sync.consecutiveSyncFailures = 0;
      _sync.consecutiveFailedPulls = 0;
      _sync.pullUnreachable = false;
      _recomputeSyncStatus();
      _push.retryUnpushed();
    });
  }
  static String _unpushedBaseDocKey(String id) => 'unpushed_base_doc_$id';
  static String _unpushedBaseMetaKey(String id) => 'unpushed_base_meta_$id';

  /// Keeps the last server-confirmed page list and metadata across closing
  /// the notebook. Written once: later failures share the same baseline.
  Future<void> _persistUnpushedBase(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final doc = _sync.lastSyncedDocument;
      final meta = _sync.lastSyncedMetadata;
      if (doc != null && !prefs.containsKey(_unpushedBaseDocKey(id))) {
        await prefs.setString(
            _unpushedBaseDocKey(id), jsonEncode(doc.toJson()));
      }
      if (meta != null && !prefs.containsKey(_unpushedBaseMetaKey(id))) {
        await prefs.setString(
            _unpushedBaseMetaKey(id), jsonEncode(meta.toJson()));
      }
    } catch (_) {}
  }

  Future<void> _clearUnpushedBase(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_unpushedBaseDocKey(id));
      await prefs.remove(_unpushedBaseMetaKey(id));
    } catch (_) {}
  }

  /// Pages and assets a previous session failed to upload: dropped from the
  /// baseline so the next save pushes them, and a save is scheduled.
  Future<void> _restoreUnpushed(
      String notebookId, Map<String, PageData> pages) async {
    final Set<String> keys;
    try {
      keys = await _ref.read(fileServiceProvider).dirtyPagesOf(notebookId);
    } catch (_) {
      return;
    }
    if (keys.isEmpty) return;
    // The page list's 3-way merge needs the server's baseline, not the local
    // copy just loaded: with that as base, a move made offline read as "no
    // change" and the remote order won.
    try {
      final prefs = await SharedPreferences.getInstance();
      final doc = prefs.getString(_unpushedBaseDocKey(notebookId));
      final meta = prefs.getString(_unpushedBaseMetaKey(notebookId));
      if (doc != null) {
        _sync.lastSyncedDocument = DocumentStructure.fromJson(
            jsonDecode(doc) as Map<String, dynamic>);
      }
      if (meta != null) {
        _sync.lastSyncedMetadata = NotebookMetadata.fromJson(
            jsonDecode(meta) as Map<String, dynamic>);
      }
    } catch (_) {}
    final pageKeys = keys.where((k) => !k.startsWith('asset:')).toSet();
    // Baseline for those pages: the page emptied. The server's real
    // baseline is unknown, and an empty one makes a page that another
    // device also edited merge as a union instead of being overwritten.
    _sync.lastSyncedPages = {
      for (final e in pages.entries)
        e.key: pageKeys.contains(e.key)
            ? e.value.copyWith(
                layers: RenderingLayers(
                    background: e.value.layers.background, content: const []))
            : e.value,
    };
    for (final k in keys) {
      if (k.startsWith('asset:')) _sync.dirtyAssetKeys.add(k.substring(6));
    }
    unawaited(CrashLogger.append(
        '[Canvas] $notebookId reopening with ${keys.length} unpushed items'));
    // The editor autosaves on the transition to dirty; state does not exist
    // yet here, so flip it once the notebook is on screen.
    unawaited(Future<void>.delayed(const Duration(seconds: 2), () {
      if (_disposed) return; // closed within the 2 s
      final st = state;
      // Kept on this device or offline: nothing can go up, a save would only
      // rewrite the files and bump the modified time on every open.
      if (keptLocal.value) return;
      if (st != null && st.metadata.id == notebookId && !st.isDirty) {
        state = st.copyWith(isDirty: true);
      }
    }));
  }

  void setViewportSize(Size size) {
    final wasNull = _viewportSize == null;
    final old = _viewportSize;
    _viewportSize = size;
    if (!wasNull && old != size && state != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (state != null && _viewportSize == size) _refitPanToViewport(old!, size);
      });
    }
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
                  : centeredPanOffset(state!.zoom),
            );
          }
        });
      }
    }
  }

  /// Keeps the page where the user left it relative to the viewport centre
  /// after a window resize (a stale pan left the page off-screen).
  void _refitPanToViewport(Size from, Size to) {
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    Offset centered(Size vp) => s.isScratch
        ? Offset(vp.width / 2 - AppConfig.scratchPageSize * s.zoom / 2,
            vp.height / 2 - AppConfig.scratchPageSize * s.zoom / 2)
        : centeredPanIn(vp, s.zoom, Size(page.width, page.height));
    double base(Size vp) => s.isScratch
        ? 1.0
        : min(vp.width / page.width, vp.height / page.height);
    final ratio = base(to) / base(from);
    final delta = s.panOffset - centered(from);
    state = s.copyWith(panOffset: centered(to) + delta * ratio);
  }

  /// Pan for [page] (default: the current one) at [zoom]: centred across,
  /// and down the screen centred when it fits, else top edge at the top.
  @override
  Offset centeredPanOffset(double zoom, [PageData? page]) {
    final vp = _viewportSize;
    if (vp == null) return Offset.zero;
    final p = page ?? state?.currentPage;
    return centeredPanIn(vp, zoom, p == null ? null : Size(p.width, p.height));
  }

  // screen = (page * fit + fitCentre) * zoom + pan; a zero vertical pan
  // scaled the fit's centring too, leaving a band above short pages.
  @visibleForTesting
  static Offset centeredPanIn(Size vp, double zoom, Size? page) {
    final dx = vp.width * (1 - zoom) / 2;
    if (page == null || page.width <= 0 || page.height <= 0) {
      return Offset(dx, 0);
    }
    final fit = min(vp.width / page.width, vp.height / page.height);
    final fitTop = (vp.height - page.height * fit) / 2;
    final top = max(0.0, (vp.height - page.height * fit * zoom) / 2);
    return Offset(dx, top - fitTop * zoom);
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

  /// Notebook whose opening page is on screen while the rest of it loads
  /// (see [showLoadingSnapshot]), or null.
  String? _loadingSnapshotId;

  /// True while the editor shows only the opening page: input waits for the
  /// whole notebook.
  final ValueNotifier<bool> pagesLoading = ValueNotifier<bool>(false);

  bool isLoadingSnapshotOf(String notebookId) =>
      _loadingSnapshotId == notebookId && state?.metadata.id == notebookId;

  /// Shows a notebook's opening page at once, read-only, while the rest of it
  /// loads; [openNotebook] with the whole notebook then takes over as usual.
  /// Nothing is saved, synced or repaired before that: those steps need
  /// every page in memory.
  Future<void> showLoadingSnapshot({
    required NotebookMetadata metadata,
    required DocumentStructure document,
    required Map<String, PageData> pages,
    required Map<String, Uint8List> assets,
    required String? chapterId,
    required int pageIndex,
    required String remotePath,
  }) async {
    if (metadata.formatVersion > AppConfig.formatVersion) {
      throw FormatTooNewException(
          metadata.formatVersion, AppConfig.formatVersion);
    }
    _openGeneration++;
    _preview = false;
    await _toolPrefs.loaded;
    final isScratch = metadata.paperType == AppConfig.infinitePaperType;
    final zoom = isScratch ? 1.0 : 2.0;
    _loadingSnapshotId = metadata.id;
    pagesLoading.value = true;
    _disposed = false;
    state = CanvasState(
      toolSettings: _toolPrefs.startupPen(),
      metadata: metadata,
      document: document,
      pages: Map.of(pages),
      remotePath: remotePath,
      assetBytes: Map.of(assets),
      activeChapterId: chapterId,
      currentPageIndex: pageIndex,
      zoom: zoom,
      panOffset: _viewportSize == null
          ? Offset.zero
          : isScratch
              ? _scratchCenterPan(zoom)
              : centeredPanOffset(zoom, PagesAndChapters.pageAt(document, pages, pageIndex)),
      currentTool: CanvasTool.pen,
    );
    for (final id in _assets.refsForPage(pageIndex, document, pages)) {
      final bytes = assets[id];
      if (bytes != null) unawaited(_assets.decodeAndCache(id, bytes));
    }
  }

  void _endLoadingSnapshot() {
    _loadingSnapshotId = null;
    if (pagesLoading.value) pagesLoading.value = false;
  }

  Future<void> openNotebook({
    required NotebookMetadata metadata,
    required DocumentStructure document,
    required Map<String, PageData> pages,
    required String remotePath,
    Map<String, Uint8List>? assets,
    List<SymbolLibrary>? symbolLibraries,
    bool preview = false,
  }) async {
    _preview = preview;
    // Refuse notebooks written by a NEWER format than this build supports.
    // Freezed fromJson silently defaults unknown fields, so opening (and
    // then saving) a newer-format notebook would strip data the newer app
    // wrote — with WebDAV multi-device sync, mixed app versions are normal
    // operation, not an edge case. Better a clear error than silent loss.
    _pdfSources.resetOnOpen();
    if (metadata.formatVersion > AppConfig.formatVersion) {
      throw FormatTooNewException(
          metadata.formatVersion, AppConfig.formatVersion);
    }
    // Bump the generation so any deferred teardown from a previous close
    // bails out instead of nulling the state we're about to populate.
    _openGeneration++;
    // Safety net: a stuck bulk flag would block remote pulls for the session.
    _bulkOperationInProgress = false;
    // Await so that state is set before the caller pushes CanvasScreen.
    // Without this, CanvasScreen briefly shows "Nessun notebook aperto"
    // (the null-state fallback) while SharedPreferences loads.
    await _restoreLastPosition(metadata, document, pages, remotePath, assets, symbolLibraries);
    _endLoadingSnapshot();
  }

  /// Chapter and page a notebook opens on: the saved position when it still
  /// fits the document, else the first chapter that has pages.
  static ({String? chapterId, int pageIndex}) startPosition(
    NotebookMetadata metadata,
    DocumentStructure document,
    String? savedChapter,
    int savedPage,
  ) {
    // Validate saved chapter still exists AND has at least one page that
    // matches its id in document.pages. If metadata.chapters[].pageIds is
    // stale (references a pageId no longer present in any page_*.json),
    // restoring activeChapterId to that chapter would leave the user
    // stuck on "— / 0" with all other pages hidden by the chapter filter.
    bool hasPagesIn(String cid) => document.pages.any((p) => p.chapterId == cid);
    if (savedChapter != null &&
        metadata.chapters.any((c) => c.id == savedChapter) &&
        hasPagesIn(savedChapter)) {
      // Validate saved page index is within range AND belongs to this chapter.
      // After a pull/merge the document may be reordered, so savedPage might
      // now point to a page in a different chapter → shows "—/N" in the nav.
      if (savedPage >= 0 &&
          savedPage < document.pages.length &&
          document.pages[savedPage].chapterId == savedChapter) {
        return (chapterId: savedChapter, pageIndex: savedPage);
      }
      // Page out of range or in wrong chapter: find first page of the chapter
      final idx = document.pages.indexWhere((p) => p.chapterId == savedChapter);
      return (chapterId: savedChapter, pageIndex: idx >= 0 ? idx : 0);
    }
    // No valid saved chapter — default to the first chapter that
    // actually has pages, or to null (all-pages view) if none qualifies.
    final firstWithPages = metadata.chapters
        .map((c) => c.id)
        .firstWhere(hasPagesIn, orElse: () => '');
    if (firstWithPages.isEmpty) return (chapterId: null, pageIndex: 0);
    final idx = document.pages.indexWhere((p) => p.chapterId == firstWithPages);
    return (chapterId: firstWithPages, pageIndex: idx >= 0 ? idx : 0);
  }

  Future<void> _restoreLastPosition(
    NotebookMetadata metadata,
    DocumentStructure document,
    Map<String, PageData> pages,
    String remotePath,
    Map<String, Uint8List>? assets,
    List<SymbolLibrary>? symbolLibraries,
  ) async {
    String? savedChapter;
    var savedPage = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      savedChapter = prefs.getString('last_chapter_${metadata.id}');
      savedPage = prefs.getInt('last_page_${metadata.id}') ?? 0;
    } catch (_) {
      // SharedPreferences failed — fall back to first chapter with pages
    }
    final start = startPosition(metadata, document, savedChapter, savedPage);
    final restoredChapterId = start.chapterId;
    final startPageIndex = start.pageIndex;

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
    Offset initialPan(DocumentStructure doc, Map<String, PageData> pages) =>
        _viewportSize == null
            ? Offset.zero
            : isScratch
                ? _scratchCenterPan(initialZoom)
                : centeredPanOffset(
                    initialZoom, PagesAndChapters.pageAt(doc, pages, startPageIndex));

    // ── Self-healing: repair duplicate fileNames before first render ──
    // Two sessions running simultaneously can independently generate the
    // same sequential fileName (e.g. page_068.json) for different pages.
    // Detect and rename any such duplicates so every PageEntry has a
    // unique key into the pages map.
    final repaired = CanvasNotifier._repairDuplicateFileNames(document, pages);

    // Fold whatever symbols this notebook carries into the device-wide
    // library. That covers the collection a user had before the library was
    // shared, and a symbol made on another device that arrived inside this
    // notebook. Awaited: the symbol panel must never open on a library that
    // is still loading.
    // A preview stays out of the device-wide library: it shows its own.
    final mergedSymbols = await _symbolsLib.mergeOnOpen(symbolLibraries,
        preview: _preview);
    await _toolPrefs.loaded;

    // Images the opening page already decoded stay, so they do not blink.
    final carriedImages = _loadingSnapshotId == metadata.id &&
            state?.metadata.id == metadata.id
        ? state!.imageCache
        : const <String, ui.Image>{};
    state = CanvasState(
      imageCache: carriedImages,
      // Starting on the const defaults, a switch away from the pen recorded
      // black 1.5 as the pen's memory and wiped the user's last pen.
      toolSettings: _toolPrefs.startupPen(),
      metadata: metadata,
      document: repaired.document,
      pages: Map.of(repaired.pages),
      remotePath: remotePath,
      assetBytes: assets != null ? Map.of(assets) : const {},
      symbolLibraries:
          mergedSymbols?.libraries ?? symbolLibraries ?? const [],
      activeChapterId: restoredChapterId,
      currentPageIndex: startPageIndex,
      zoom: initialZoom,
      panOffset: initialPan(repaired.document, repaired.pages),
      currentTool: _preview ? CanvasTool.pan : CanvasTool.pen,
    );

    // Catch up with the other devices in the background. Deliberately not
    // awaited and deliberately NOT marking the notebook dirty: opening a
    // notebook must neither wait on the network nor schedule a save.
    if (!_preview) _symbolsLib.reconcileInBackground();

    // Initialize delta sync tracking
    _disposed = false;
    _sync.consecutiveSyncFailures = 0;
    _sync.consecutiveFailedPulls = 0;
    _sync.absentRemoteAssets.clear();
    _sync.pullUnreachable = false;
    hasSyncFailure.value = false;
    remoteSaveInFlight.value = false;
    keptLocal.value = _preview ||
        (_ref.read(syncServiceProvider)?.isOffline ?? true) ||
        await _isLocalOnly(metadata.id);
    // Hold the same ref — _sync.lastSyncedPages is a dirty-detection sidetable
    // (we only ever read identity via `identical(s.pages[k], _sync.lastSyncedPages[k])`),
    // and `pages` itself is treated as immutable: every edit replaces it
    // with a fresh map. So Map.of(...) was a defensive copy with no benefit.
    _sync.lastSyncedPages = repaired.pages;
    // The repair may have renamed pages: then the disk copy is behind.
    _save.openedWith(
      pages: Map.of(repaired.pages),
      assets: {...?assets?.keys},
      doc: identical(repaired.document, document) ? repaired.document : null,
      meta: metadata,
      symbols: state?.symbolLibraries,
    );
    _sync.serverMovedStreak = 0;
    // Seed the 3-way-merge baselines from the just-loaded on-disk state.
    _sync.lastSyncedDocument = repaired.document;
    _sync.remoteDocVersion = null;
    _sync.pendingDocVersion = null;
    _sync.lastSyncedMetadata = metadata;
    _sync.ghostEntryStrikes.clear();
    _sync.consecutiveInconsistentPulls = 0;
    _sync.consecutiveInconsistentSince = null;
    _sync.preSaveGuardAborts = 0;
    _sync.preSaveGuardSince = null;
    _assets.resetOnOpen(metadata.id);
    _assetsByLength.clear();
    _assetIndexBuilt = false;
    _pageJsonCache.clear();
    _sync.dirtyAssetKeys.clear();
    if (!_preview) await _restoreUnpushed(metadata.id, repaired.pages);
    // If the cached ETags belong to a different notebook, flush them so
    // notebook-A's diff never bleeds into notebook-B's first pull.
    if (_sync.etagNotebookId != metadata.id) {
      _sync.remoteMetaEtag = null;
      _sync.lastPageEtags = {};
      _sync.pageFailureCount.clear();
      _sync.pageFailureCooldownUntil.clear();
      _sync.knownCorruptEtags.clear();
      _sync.etagNotebookId = metadata.id;
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
    if (!_preview) {
      _initPageEtags(metadata.id);
      _loadPendingDeletes(metadata.id);
      _startPullTimer();
    }

    // If there's a cross-notebook clipboard pending, apply it to this canvas
    // so the user can paste immediately after switching notebooks.
    final crossClip =
        _preview ? null : _ref.read(crossNotebookClipboardProvider);
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
    // the current page (current ± AssetCache.assetWindow; wider on desktop). The
    // rest are decoded lazily when the user navigates near them (see
    // [_ensureAssetsForCurrentWindow]) and far-away textures are
    // LRU-evicted past the platform cache cap.
    if (assets != null && assets.isNotEmpty) {
      final initialRefs = _assets.refsForPage(startPageIndex, repaired.document, repaired.pages);
      // Phase 1: kick off decodes for the initial page. Missing-bytes
      // assets get routed through ensureAssetDecodedForThumbnail which
      // triggers a lazy fetch — so an incomplete .ncnote heals itself
      // on open without the user having to navigate away and back.
      for (final assetId in initialRefs) {
        if (carriedImages.containsKey(assetId)) continue;
        final bytes = assets[assetId];
        if (bytes != null) {
          unawaited(_assets.decodeAndCache(assetId, bytes));
        } else {
          ensureAssetDecodedForThumbnail(assetId);
        }
      }
      // Phase 2: decode only the ±AssetCache.assetWindow page window — on EVERY
      // platform. Desktop used to decode everything here, which on a
      // 400-page scan-heavy notebook meant minutes of background decode
      // churn and gigabytes of pinned textures. Distant pages now decode
      // on navigation via _ensureAssetsForCurrentWindow (same path
      // mobile has exercised since the iPad OOM fixes).
      final windowRefs = _assets.refsForWindow(
        startPageIndex, AssetCache.assetWindow, repaired.document, repaired.pages,
      )..removeAll(initialRefs);
      final windowAssets = <String, Uint8List>{};
      for (final r in windowRefs) {
        final b = assets[r];
        if (b != null) windowAssets[r] = b;
      }
      unawaited(_assets.decodeThrottled(windowAssets, skip: const {}));
    }
    _assets.logMemoryStats('openNotebook');

    // Background self-heal: re-pull any locally-truncated assets from the
    // server (where the clean copy lives in the notebook itself). Deferred so
    // it doesn't compete with the initial open/pull, and a no-op for healthy
    // notebooks. Recovers corrupt assets on pages the user never opens, which
    // the view-driven lazy heal would otherwise miss.
    final healGen = _openGeneration;
    Future.delayed(const Duration(seconds: 4), () {
      if (_disposed || _openGeneration != healGen) return;
      _assets.recoverTruncatedFromServer();
    });
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
  /// Stages orphan IDs into [_sync.pendingAssetDeletes] so the next save —
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
      _assets.forgetOrphan(id);
      _sync.dirtyAssetKeys.remove(id);
    }
    for (final id in cacheOnlyOrphans) {
      newCache.remove(id)?.dispose();
      _assets.forgetCacheOnlyOrphan(id);
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
        orphans.where(_sync.uploadedAssetKeys.contains).toList();
    _sync.pendingAssetDeletes.addAll(serverConfirmed);
    // Drop the no-longer-tracked orphan ids from the uploaded set so it
    // doesn't grow unbounded over a long session.
    for (final id in orphans) {
      _sync.uploadedAssetKeys.remove(id);
    }
    print('[Canvas] Pruned ${orphans.length} orphan assets '
        '(${serverConfirmed.length} queued for server delete, '
        '${cacheOnlyOrphans.length} cache-only) — freeing storage');
  }

  /// Set by the canvas screen: returns true while a pen stroke is
  /// mid-flight (the screen-local ActiveStrokeNotifier, which bypasses
  /// Riverpod, is the only component that knows). Save's heavy prep
  /// (page JSON encode) polls this via [_waitForQuietPointer] so its
  /// main-thread chunks never land while the user has the pen on the
  /// page — that was the "scatto" that dropped pointer samples and kinked
  /// the stroke being written.
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
    final m = _pageFileRe.firstMatch(fn);
    return m != null ? (int.tryParse(m.group(1)!) ?? 99999) : 99999;
  }

  /// Chapter membership lists rebuilt from the authoritative
  /// PageEntry.chapterId (addPage & co. only set the entry, so the lists
  /// written to metadata.json went stale).
  static List<Chapter> _chaptersWithMembership(
      List<Chapter> chapters, DocumentStructure doc) {
    final byChapter = <String, List<String>>{};
    for (final e in doc.pages) {
      final cid = e.chapterId;
      if (cid != null) (byChapter[cid] ??= []).add(e.pageId);
    }
    return [
      for (final c in chapters)
        c.copyWith(pageIds: byChapter[c.id] ?? const <String>[]),
    ];
  }

  @visibleForTesting
  static List<Chapter> chaptersWithMembershipForTest(
          List<Chapter> chapters, DocumentStructure doc) =>
      _chaptersWithMembership(chapters, doc);

  @visibleForTesting
  static ({NotebookMetadata metadata, DocumentStructure document})
      merge3WayForTest({
    required NotebookMetadata? baseMeta,
    required NotebookMetadata localMeta,
    required NotebookMetadata remoteMeta,
    required DocumentStructure? baseDoc,
    required DocumentStructure localDoc,
    required DocumentStructure remoteDoc,
    required Set<String> survivingFileNames,
  }) =>
          merge3Way(
              baseMeta: baseMeta,
              localMeta: localMeta,
              remoteMeta: remoteMeta,
              baseDoc: baseDoc,
              localDoc: localDoc,
              remoteDoc: remoteDoc,
              survivingFileNames: survivingFileNames);

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

  /// Web builds up to 0.38.1 could read WebDAV pages back from the service
  /// worker cache (same-origin proxy): stale content stored under fresh
  /// ETags. Forgetting every pull baseline once makes the next open
  /// download each page again; unpushed local edits go through the merge.
  static Future<void> forgetWebPullBaselinesOnce() async {
    if (!kIsWeb) return;
    const done = 'web_pull_baselines_reset_v1';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(done) ?? false) return;
      for (final k in prefs.getKeys().toList()) {
        if (k.startsWith('page_etags_') || k.startsWith('delta_meta_etag_')) {
          await prefs.remove(k);
        }
      }
      await prefs.setBool(done, true);
      unawaited(CrashLogger.append('[Web] pull baselines reset once'));
    } catch (_) {}
  }

  /// Pull baseline for a notebook just downloaded whole: without it the
  /// editor's first pull fetched every page a second time.
  static Future<void> seedPageEtags(
      String notebookId, Map<String, String> etags) async {
    if (etags.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pageEtagsPrefsKey(notebookId), jsonEncode(etags));
    } catch (_) {}
  }

  /// SharedPreferences key for the per-page ETag map of a notebook.
  static String _pageEtagsPrefsKey(String notebookId) =>
      'page_etags_$notebookId';

  /// Restore [_sync.lastPageEtags] from disk. This MUST reflect the ETags of the
  /// page content we actually have locally — i.e. only ETags that were
  /// successfully downloaded or uploaded. Never pre-populate from live
  /// server state on open: the server may have moved while we were closed,
  /// and pre-filling with current server ETags would silently make the
  /// first pull think 'nothing changed' even though our local .ncnote is
  /// stale (the 'iPad wrote page_164 while PC was offline → PC opens but
  /// pull is no-op → local stays stale forever' bug).
  ///
  /// Also primes [_sync.remoteMetaEtag] from SharedPreferences.
  Future<void> _initPageEtags(String notebookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load last-saved meta ETag so first-pull can skip cheaply when
      // server state hasn't moved. Only use it if we don't already have
      // one in memory (e.g. same notebook re-opened without notebook-switch).
      if (_sync.remoteMetaEtag == null) {
        final persisted = prefs.getString(_deltaMetaEtagPrefsKey(notebookId));
        if (persisted != null && persisted.isNotEmpty) {
          _sync.remoteMetaEtag = persisted;
        }
      }

      // Load the persisted per-page ETag cache written by previous save/
      // pull cycles. Empty map on fresh install: the first pull will then
      // treat every page as potentially changed and download it.
      final persistedPageEtags = prefs.getString(_pageEtagsPrefsKey(notebookId));
      if (persistedPageEtags != null && persistedPageEtags.isNotEmpty) {
        try {
          final decoded = jsonDecode(persistedPageEtags) as Map<String, dynamic>;
          _sync.lastPageEtags = decoded.map((k, v) => MapEntry(k, v as String));
          debugPrint('[Canvas] Loaded ${_sync.lastPageEtags.length} page ETags from disk');
        } catch (_) {
          _sync.lastPageEtags = {};
        }
      } else {
        _sync.lastPageEtags = {};
      }

      // NOTE: we intentionally do NOT seed _sync.lastPageEtags from the server's
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

      debugPrint('[Canvas] Initialized ${_sync.lastPageEtags.length} page ETags '
          '(persisted meta etag: ${_sync.remoteMetaEtag != null})');
    } catch (e) {
      debugPrint('[Canvas] Could not init page ETags: $e');
    }
  }

  /// True when the most recent remote sync attempt(s) have failed
  /// OR there's a pending metadata-commit retry. Surfaced to the UI
  /// so the top-bar pill can show OFFLINE instead of the misleading
  /// "isDirty ? pending : ok" binary that hid 20-minute Tailscale
  /// flaps under a green cloud icon. The UI combines this with
  /// state.isDirty and state.pendingConflicts to pick the final
  /// HwSyncState (conflict > offline > pending > ok).
  final ValueNotifier<bool> hasSyncFailure = ValueNotifier<bool>(false);

  /// An upload is running: isDirty is cleared before it starts, so without
  /// this the pill read "synced" for the whole upload.
  final ValueNotifier<bool> remoteSaveInFlight = ValueNotifier<bool>(false);

  /// The open notebook never syncs: kept on this device, or no server.
  final ValueNotifier<bool> keptLocal = ValueNotifier<bool>(false);

  /// Drives the library's out-of-space notice, which only the library's own
  /// sync used to set and nothing ever cleared.
  void _reportStorageFull(bool full) {
    try {
      final n = _ref.read(notebookListProvider.notifier).storageFull;
      if (n.value != full) n.value = full;
    } catch (_) {}
  }

  /// Keeps the library's "server not reachable" notice in step with what
  /// the editor sees.
  void _reportReachable(bool reachable) {
    try {
      final n = _ref.read(notebookListProvider.notifier).serverUnreachable;
      if (n.value == reachable) n.value = !reachable;
    } catch (_) {}
  }

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
      _sync.pendingPageDeletes
        ..clear()
        ..addAll(p ?? const []);
      _sync.pendingAssetDeletes
        ..clear()
        ..addAll(a ?? const []);
      if (_sync.pendingPageDeletes.isNotEmpty || _sync.pendingAssetDeletes.isNotEmpty) {
        debugPrint('[Canvas] Loaded pending deletes: '
            '${_sync.pendingPageDeletes.length} pages, '
            '${_sync.pendingAssetDeletes.length} assets');
      }
      // Pending metadata commit: a previous run may have left the server
      // half-committed (pages + document landed but metadata.json
      // upload failed). Pick up where we left off — retry every minute
      // until it lands. Other devices' meta-ETag won't advance until
      // this commits, so cross-device sync is stuck without it.
      final metaB64 = prefs.getString(_pendingMetaCommitPrefsKey(notebookId));
      if (metaB64 != null && metaB64.isNotEmpty) {
        try {
          _sync.pendingMetaCommitBytes = base64Decode(metaB64);
          debugPrint('[Canvas] Loaded pending metadata commit: '
              '${_sync.pendingMetaCommitBytes!.length} bytes');
          _push.scheduleMetaCommitRetry();
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
          _sync.pendingPageDeletes.toList());
      await prefs.setStringList(
          _pendingAssetDeletesPrefsKey(notebookId),
          _sync.pendingAssetDeletes.toList());
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
    if (_disposed) return; // a push that finished after the editor closed
    final next = _sync.consecutiveSyncFailures > 0 ||
        _sync.pendingMetaCommitBytes != null ||
        _sync.pullUnreachable ||
        _sync.consecutiveFailedPulls >= SyncPull.failedPullsShown;
    if (hasSyncFailure.value != next) hasSyncFailure.value = next;
  }

  /// Persist [_sync.lastPageEtags] to disk. Called after every pull/save cycle
  /// that updates the map so a cold restart resumes with the ETag state
  /// that matches our local .ncnote content.
  Future<void> _persistLastPageEtags(String notebookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _pageEtagsPrefsKey(notebookId), jsonEncode(_sync.lastPageEtags));
    } catch (_) {}
  }

  /// Persist the current [_sync.remoteMetaEtag] so next app launch can skip the
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
    final etag = _sync.remoteMetaEtag;
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
  /// With [compact], pages with stroke chunks are written whole first, so
  /// releases that read only snapshots see every stroke (closing).
  Future<void> flushPendingWork({bool compact = false}) async {
    _thumbnails.flush();
    _sync.pullLoopOn = false;
    _sync.pullTimer?.cancel();
    _sync.pullTimer = null;
    _saveLastPosition();

    final pendingPull = _sync.pendingPullFuture;
    if (pendingPull != null) {
      try { await pendingPull; } catch (_) {}
    }
    _sync.pendingPullFuture = null;

    final pendingSave = _sync.pendingPulledLocalSave;
    if (pendingSave != null) {
      try { await pendingSave; } catch (_) {}
    }
    _sync.pendingPulledLocalSave = null;

    if (compact && StrokeOps.writing && !_save.discardRequested && state != null) {
      final withChunks = [
        for (final e in _sync.lastPageEtags.entries)
          if (splitPageVersion(e.value).chunks.isNotEmpty) e.key,
      ];
      if (withChunks.isNotEmpty) {
        _sync.compactNext.addAll(withChunks);
        state = state!.copyWith(isDirty: true);
      }
    }

    // Edits since the last autosave go up as well, not only to disk:
    // leaving no longer waits for a "save before leaving?" answer.
    if (!_save.discardRequested && (state?.isDirty ?? false)) {
      try { await save(); } catch (_) {}
    }

    // Await any in-flight remote sync (launched fire-and-forget by save())
    // — without this, exiting during an upload can leave a half-committed
    // delta folder on the server (pages written, metadata.json stale),
    // which another device will then see as a conflict.
    final pendingRemoteSave = _sync.pendingRemoteSave;
    if (pendingRemoteSave != null) {
      try { await pendingRemoteSave; } catch (_) {}
    }
    _sync.pendingRemoteSave = null;

    // Await in-flight local ZIP rebuild (from save()'s background task).
    // Otherwise exit-after-stroke can leave the .ncnote without the very
    // last stroke, and a cold reopen would show pre-stroke content until
    // the next pull brings it back from the server.
    await _save.awaitPendingWrite();

    // Last word to the disk: whatever the state holds and the store lacks,
    // then every queued local write.
    if (!_save.discardRequested && state != null) {
      try { await _save.persistLocal(); } catch (_) {}
    }
    await _save.awaitWriteQueue();
  }

  Future<void> closeNotebook() async {
    // Snapshot the generation: if another openNotebook() fires while we're
    // draining, the new open bumps [_openGeneration], and the teardown
    // below is skipped — otherwise we'd null out the freshly-populated
    // state and the canvas would be stuck on "Nessun notebook aperto".
    final myGen = _openGeneration;

    // Drain first so pulled pages + metadata actually land on disk before
    // the notifier tears down (the "ci rientro ed è scomparso tutto" bug).
    final closingId = state?.metadata.id;
    await flushPendingWork(compact: true);
    // A day of edits gets one restorable copy.
    if (closingId != null && !_save.discardRequested && !_preview) {
      unawaited(_ref
          .read(fileServiceProvider)
          .snapshotIfDue(closingId, every: const Duration(hours: 24)));
    }

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
    _bulkOperationInProgress = false;
    _eraser.discard();
    _sync.isPulling = false;
    isPullingFromRemote.value = false;
    _sync.pendingMetaCommitTimer?.cancel();
    _sync.pendingMetaCommitTimer = null;
    _sync.remoteRetryTimer?.cancel();
    _sync.remoteRetryTimer = null;
    remoteSaveInFlight.value = false;
    _sync.forceReleaseLock();
    _sync.dirtyAssetKeys.clear();
    _sync.lastSyncedPages = {};
    _save.closed();
    _preview = false;
    _endLoadingSnapshot();
    _sync.lastSyncedDocument = null;
    _sync.lastSyncedMetadata = null;
    _sync.ghostEntryStrikes.clear();
    _sync.consecutiveInconsistentPulls = 0;
    _sync.consecutiveInconsistentSince = null;
    _sync.preSaveGuardAborts = 0;
    _sync.preSaveGuardSince = null;
    _assets.resetOnClose();
    _assetsByLength.clear();
    _assetIndexBuilt = false;
    _pageJsonCache.clear();
    // Keep _sync.remoteMetaEtag, _sync.lastPageEtags across
    // close/open to avoid re-pulling all pages on re-enter.
    state = null;
  }

  Future<void> _saveLastPosition() async {
    if (state == null || _preview) return;
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
    // A preview is for reading: no tool that edits.
    if (_preview && tool != CanvasTool.pan) return;

    // Bake any pending lasso transformations before switching tools
    if (tool != CanvasTool.lasso && state!.lassoSelection != null) {
      applySelectionTransform();
    }

    final s = state!;
    final fromTool = s.currentTool;

    // Persist the OUTGOING tool's settings so the next visit restores them.
    _toolPrefs.rememberOutgoing(fromTool, s.toolSettings);

    // Remember the eraser sub-mode so the dock button restores it.
    if (tool == CanvasTool.eraserStandard || tool == CanvasTool.eraserStroke) {
      _toolPrefs.lastEraserMode = tool;
    }

    final updatedSettings = _toolPrefs.settingsFor(tool, s.toolSettings);

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
    _toolPrefs.persist();
  }

  void setToolSettings(ToolSettings settings) {
    if (state == null) return;
    state = state!.copyWith(toolSettings: settings);
    _toolPrefs.rememberCurrent();
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

  /// Cancel the current stroke without committing (e.g. when pinch-to-zoom starts)
  void cancelStroke() {
    if (state == null) return;
    _eraser.cancelGesture();
    state = state!.copyWith(
      activeStroke: [],
      clearShapeStart: true,
      clearShapeEnd: true,
      clearEraserCursor: true,
    );
  }

  void setEraserSize(EraserSize size) {
    if (state == null) return;
    final ts = state!.toolSettings;
    if (ts.eraserSize == size && ts.eraserDiameterPt == null) return;
    state = state!.copyWith(
      toolSettings: ts.copyWith(eraserSize: size, clearEraserDiameter: true),
    );
    _toolPrefs.rememberCurrent();
  }

  void setEraserDiameterPt(double? pt) {
    if (state == null) return;
    final ts = state!.toolSettings;
    if (ts.eraserDiameterPt == pt) return;
    state = state!.copyWith(
      toolSettings: pt == null
          ? ts.copyWith(clearEraserDiameter: true)
          : ts.copyWith(eraserDiameterPt: pt),
    );
    _toolPrefs.rememberCurrent();
  }

  // ── Paper type ──

  /// Paper sheet scope for this session: true applies to every ruled page.
  bool paperAllPages = true;

  /// Undo group ids: an all-pages paper change is one step across pages.
  int _undoGroupSeq = 0;

  static PageData _withPaperType(PageData page, PaperType type) =>
      carryPdfTextLayer(page, PageData(
        pageId: page.pageId,
        pageNumber: page.pageNumber,
        width: page.width,
        height: page.height,
        layers: RenderingLayers(
          background: BackgroundLayer(
            type: paperTypeToString(type),
            color: page.layers.background.color,
            lineSpacing: paperTypeLineSpacing(type),
            lineColor: page.layers.background.lineColor,
          ),
          content: page.layers.content,
        ),
        assetReferences: page.assetReferences,
        createdAt: page.createdAt,
        modifiedAt: DateTime.now(),
      ));

  static PageData _withLineSpacing(PageData page, double spacing) =>
      page.copyWith(
        layers: page.layers.copyWith(
          background: page.layers.background.copyWith(lineSpacing: spacing),
        ),
        modifiedAt: DateTime.now(),
      );

  /// True when [page]'s background is ruled paper, not a PDF or image.
  static bool isRuledPaperPage(PageData page) =>
      page.layers.background.pdfAsset == null && !hasFullPageBackground(page);

  /// Applies [edit] to every ruled page in memory as one undo step.
  /// Pages without local data yet have nothing to edit and are skipped.
  void _editAllRuledPages(PageData? Function(PageData page) edit,
      {CanvasState Function(CanvasState)? alsoState}) {
    final s = state!;
    final updatedPages = Map<String, PageData>.from(s.pages);
    final group = ++_undoGroupSeq;
    var undo = s.undoStack;
    for (final entry in s.document.pages) {
      final page = s.pages[entry.fileName];
      if (page == null || !isRuledPaperPage(page)) continue;
      final after = edit(page);
      if (after == null) continue;
      updatedPages[entry.fileName] = after;
      undo = [...undo, UndoEntry(entry.fileName, page, group: group)];
    }
    if (identical(undo, s.undoStack) && alsoState == null) return;
    final next = s.copyWith(
        pages: updatedPages,
        undoStack: _trimUndo(undo),
        redoStack: [],
        isDirty: true);
    state = alsoState == null ? next : alsoState(next);
  }

  /// Sets the paper type of the current page, or with [allPages] of every
  /// ruled page (PDF and image pages keep theirs).
  void setPaperType(PaperType type, {bool allPages = false}) {
    if (state == null || _preview || _loadingSnapshotId != null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final bgType = paperTypeToString(type);

    if (allPages) {
      // metadata.paperType: Library cover swatch and the default for new pages.
      _editAllRuledPages((p) => _withPaperType(p, type),
          alsoState: (n) => n.copyWith(
              metadata: s.metadata
                  .copyWith(paperType: bgType, modifiedAt: DateTime.now())));
      return;
    }

    final fileName = s.currentPageFileName;
    final updatedPage = _withPaperType(page, type);

    // metadata.paperType only drives the Library cover's texture swatch and
    // the default for newly added pages — keep it in sync with page 1 so
    // the cover doesn't keep showing a stale paper type after the user
    // changes it.
    final metadata = page.pageNumber == 1
        ? s.metadata.copyWith(paperType: bgType, modifiedAt: DateTime.now())
        : s.metadata;

    commitPageEdit(s, fileName, updatedPage,
        undoOf: page, alsoState: (n) => n.copyWith(metadata: metadata));
  }

  /// Gap between lines, grid squares or dots in points, on the current page
  /// or with [allPages] every ruled page. New pages copy the page before.
  void setLineSpacing(double spacing, {bool allPages = false}) {
    if (state == null || _preview || _loadingSnapshotId != null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;

    if (allPages) {
      _editAllRuledPages((p) => p.layers.background.lineSpacing == spacing
          ? null
          : _withLineSpacing(p, spacing));
      return;
    }

    if (page.layers.background.lineSpacing == spacing) return;
    commitPageEdit(s, s.currentPageFileName, _withLineSpacing(page, spacing),
        undoOf: page);
  }

  /// Resizes the current page. What's drawn keeps its place from the top
  /// left corner; what falls past a new edge stays on the page, outside the
  /// paper, and comes back if the page grows again. One undo step.
  void setPageSize(double width, double height) {
    if (state == null || _preview || _loadingSnapshotId != null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    if (page.width == width && page.height == height) return;

    final fileName = s.currentPageFileName;
    final resized = page.copyWith(
      width: width,
      height: height,
      modifiedAt: DateTime.now(),
    );
    commitPageEdit(s, fileName, resized,
        undoOf: page,
        alsoState: (n) =>
            n.copyWith(document: _withEntrySize(s.document, fileName, resized)));
  }

  /// The document's page list also records each page's size: keep it in
  /// step when a resize is made, undone or redone.
  static DocumentStructure _withEntrySize(
      DocumentStructure doc, String fileName, PageData page) {
    if (!doc.pages.any((e) =>
        e.fileName == fileName &&
        (e.width != page.width || e.height != page.height))) {
      return doc;
    }
    return doc.copyWith(pages: [
      for (final e in doc.pages)
        e.fileName == fileName
            ? e.copyWith(width: page.width, height: page.height)
            : e,
    ]);
  }

  // ── Drawing ──

  void startStroke(Offset position, double pressure) {
    if (state == null) return;
    final tool = state!.currentTool;

    if (tool == CanvasTool.pan || tool == CanvasTool.text || tool == CanvasTool.image) return;

    if (tool == CanvasTool.lasso) {
      _selection.startLasso(position);
      return;
    }

    if (tool == CanvasTool.eraserStandard || tool == CanvasTool.eraserStroke) {
      _eraser.beginGesture();
      state = state!.copyWith(eraserCursorPos: position);
      _eraser.eraseAt(position);
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
      _selection.continueLasso(position);
      return;
    }

    if (tool == CanvasTool.eraserStandard || tool == CanvasTool.eraserStroke) {
      // Note: do NOT call state.copyWith for eraserCursorPos here.
      // continueStroke fires at 60-120 Hz on Apple Pencil / mouse and
      // every state mutation triggers Riverpod fan-out to all
      // listeners (~7 selectors run their compute even if they don't
      // re-fire). eraseAt below updates the cursor position itself
      // alongside its own distance throttle so the cursor moves
      // visibly only when erase work happens.
      _eraser.eraseAt(position);
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

    if (tool == CanvasTool.lasso) { _selection.endLasso(); return; }
    if (tool == CanvasTool.eraserStandard || tool == CanvasTool.eraserStroke) {
      // Force-commit any throttled erasures so the pointer-up state
      // matches what the user saw on screen during the drag.
      _eraser.endGesture();
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
      _heldShapeBase = recognized;
      _heldShapeGrip = Offset(points.last.x, points.last.y);
      state = state!.copyWith(
        activeStroke: [],
        recognizedShape: recognized,
      );
    }
  }

  // Shape and pen position at hold-to-recognize time, for resizeRecognizedShape.
  ShapeData? _heldShapeBase;
  Offset? _heldShapeGrip;

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
        final snapped = snapLineEnd(shape.x1, shape.y1, position.dx, position.dy);
        // copyWith preserves isHighlighter (and any other untouched field)
        // — a from-scratch rebuild silently reset it to opaque on every
        // drag, which is why a highlighter-drawn recognized line turned
        // solid the moment the user adjusted it.
        updated = shape.copyWith(x2: snapped[0], y2: snapped[1]);
        break;
      case 'circle' when isRound(shape):
        final box = circleResizeBox(
            Offset((shape.x1 + shape.x2) / 2, (shape.y1 + shape.y2) / 2),
            position);
        updated = shape.copyWith(
          x1: box.left, y1: box.top,
          x2: box.right, y2: box.bottom,
        );
        break;
      case 'rectangle':
        updated = dragRectCorner(shape, position);
        break;
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
    final snapped = snapLineEnd(s.x1, s.y1, position.dx, position.dy);
    state = state!.copyWith(
      recognizedShape: s.copyWith(x2: snapped[0], y2: snapped[1]),
    );
  }

  /// Fix top-left corner (x1,y1), resize by dragging bottom-right to [position].
  /// For circles: keep center fixed, change radius based on cursor distance.
  void resizeRecognizedShape(Offset position) {
    if (state == null || state!.recognizedShape == null) return;
    final s = state!.recognizedShape!;

    if (s.shapeType == 'circle' && isRound(s)) {
      final box = circleResizeBox(
          Offset((s.x1 + s.x2) / 2, (s.y1 + s.y2) / 2), position);
      state = state!.copyWith(
        recognizedShape: s.copyWith(
          x1: box.left, y1: box.top,
          x2: box.right, y2: box.bottom,
        ),
      );
      return;
    }

    if (s.shapeType == 'triangle' ||
        s.shapeType == 'rhombus' ||
        s.shapeType == 'circle') {
      final base = _heldShapeBase ?? s;
      final box = scaledShapeResizeBox(
        Rect.fromPoints(Offset(base.x1, base.y1), Offset(base.x2, base.y2)),
        _heldShapeGrip ?? Offset(s.x2, s.y2),
        position,
      );
      // Oblique triangles draw from absolute vertices: scale them with the box.
      final from = Rect.fromPoints(
          Offset(base.x1, base.y1), Offset(base.x2, base.y2));
      final vertices = transformVertices(
          base.vertices,
          (p) => Offset(
                from.width <= 0
                    ? box.left
                    : box.left + (p.dx - from.left) / from.width * box.width,
                from.height <= 0
                    ? box.top
                    : box.top + (p.dy - from.top) / from.height * box.height,
              ));
      state = state!.copyWith(
        recognizedShape: s.copyWith(
          x1: box.left, y1: box.top,
          x2: box.right, y2: box.bottom,
          vertices: vertices,
        ),
      );
      return;
    }

    // x1,y1 is the anchor (opposite corner from pen at recognition time).
    state = state!.copyWith(
      recognizedShape: s.shapeType == 'rectangle'
          ? dragRectCorner(s, position)
          : s.copyWith(x2: position.dx, y2: position.dy),
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
      zIndex: nextZIndex(page),
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

    commitPageEdit(s, fileName, pageWithNewElement(page, newElement),
        undoOf: page, alsoState: (n) => n.copyWith(activeStroke: []));
    if (CrashLogger.verboseEnabled) {
      _diagStrokeId = newElement.id;
      _diagStrokePage = fileName;
      CrashLogger.append('[StrokeDbg] COMMIT ${newElement.id} '
          'pts=${smoothedPoints.length} page=$fileName '
          'undo=${state!.undoStack.length}');
    }
  }

  /// The width the ink of [points] is drawn at, on average, so a shape made
  /// from them matches the pen: the slider's width times the stroke's own
  /// width factor (a pen with pressure off is drawn ~1.24x the slider).
  double _inkWidth(List<StrokePoint> points) {
    final width = state!.toolSettings.strokeWidth;
    if (points.isEmpty) return width;
    final factor = switch (state!.currentTool) {
      CanvasTool.pen => penWidthFactor,
      CanvasTool.ballpoint => ballpointWidthFactor,
      _ => null, // highlighter, brush, calligraphy: left at the slider's width
    };
    if (factor == null) return width;
    final mean =
        points.fold<double>(0, (t, p) => t + factor(p.pressure)) / points.length;
    return width * mean;
  }

  ShapeData? _recognizeShape(List<StrokePoint> points) => recognizeShape(
        points,
        color: state!.toolSettings.color,
        strokeWidth: _inkWidth(points),
        isHighlighter: state!.currentTool == CanvasTool.highlighter,
        fill: _ref.read(appSettingsProvider).fillRecognizedShapes,
      );

  void _addShapeElement(ShapeData shapeData) {
    final s = state!;
    final page = s.currentPage!;
    final fileName = s.currentPageFileName;

    final newElement = ContentElement.shape(
      id: const Uuid().v4(),
      zIndex: nextZIndex(page),
      data: shapeData,
    );

    commitPageEdit(s, fileName, pageWithNewElement(page, newElement),
        undoOf: page, alsoState: (n) => n.copyWith(activeStroke: []));
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

    // A circle stays a circle whatever the drag looked like: store the
    // squared box so the inscribed ellipse every consumer reads IS a circle.
    // Every other shape keeps the raw drag endpoints — line and arrow read
    // direction off them, so normalising the corners would flip arrowheads.
    var x1 = s.shapeStartPos!.dx, y1 = s.shapeStartPos!.dy;
    var x2 = s.shapeEndPos!.dx, y2 = s.shapeEndPos!.dy;
    if (s.toolSettings.shapeType == 'circle') {
      final box = circleDragBox(s.shapeStartPos!, s.shapeEndPos!);
      x1 = box.left; y1 = box.top;
      x2 = box.right; y2 = box.bottom;
    }

    final newElement = ContentElement.shape(
      id: const Uuid().v4(),
      zIndex: nextZIndex(page),
      data: ShapeData(
        shapeType: s.toolSettings.shapeType,
        x1: x1, y1: y1,
        x2: x2, y2: y2,
        strokeColor: s.toolSettings.color,
        strokeWidth: s.toolSettings.strokeWidth,
      ),
    );

    final updatedPage = pageWithNewElement(page, newElement);
    commitPageEdit(s, fileName, updatedPage,
        undoOf: page,
        alsoState: (n) => n.copyWith(clearShapeStart: true, clearShapeEnd: true));
  }

  // ── Lasso ──

  void clearLassoPath() => _selection.clearLassoPath();

  /// Accept a locally-collected lasso path (from _LassoPathNotifier in the UI)
  /// and run selection, bypassing per-point Riverpod updates.
  void commitLassoPath(List<Offset> path) => _selection.commitLassoPath(path);

  /// Apply the full transform (drag/rotation/scale) atomically: the UI
  /// commits a locally-tracked transform on pointer-up in one state update.
  void commitSelectionTransform({
    required Offset dragOffset,
    required double rotation,
    required double scale,
  }) =>
      _selection.commitSelectionTransform(
          dragOffset: dragOffset, rotation: rotation, scale: scale);

  void applySelectionTransform() => _selection.applySelectionTransform();

  /// Mirror the current selection around its horizontal center axis (flip X).
  void flipSelectionHorizontal() => _selection.flipSelection(horizontal: true);

  /// Mirror the current selection around its vertical center axis (flip Y).
  void flipSelectionVertical() => _selection.flipSelection(horizontal: false);

  void deleteSelection() => _selection.deleteSelection();

  /// Selected ink as (element id, stroke): freehand strokes plus shapes
  /// traced as their outline, as circuits use them.
  List<(String, StrokeData)> selectedInk() => _selection.selectedInk();

  /// Whether [selectedInk] would find anything, without building it.
  bool get selectionHasInk => _selection.selectionHasInk;

  /// Selected ink for formula recognition: pen strokes plus line shapes
  /// (fraction bars, minus signs). Highlighter is left out.
  List<(String, StrokeData)> selectedMathInk() => _selection.selectedMathInk();

  /// Swaps the ink [removedIds] on page [fileName] for a formula typeset from
  /// [latex], fitted to that ink's box and centred on it, in one undo step.
  Future<void> replaceInkWithMath(String fileName, Set<String> removedIds, String latex) async {
    if (latex.trim().isEmpty) return;
    bool replaced(ContentElement e) => (e is StrokeElement || e is ShapeElement) && removedIds.contains(e.id);
    final ink = state?.pages[fileName]?.layers.content.where(replaced).toList() ?? const [];
    if (ink.isEmpty) return;
    var bounds = elementBounds(ink.first);
    for (final e in ink.skip(1)) {
      bounds = bounds.expandToInclude(elementBounds(e));
    }
    // The colour of the ink it replaces, not of the pen held now.
    final first = ink.first;
    final color = first is StrokeElement ? first.data.color : (first as ShapeElement).data.strokeColor;
    const probe = 24.0;
    var fontSize = probe;
    var size = await measureMath(latex, colorArgb: color, fontSize: probe, displayMode: false);
    if (size != null && size.width > 0 && size.height > 0) {
      final scale = min(bounds.height / size.height, bounds.width / size.width);
      fontSize = (probe * scale).clamp(10.0, 96.0).toDouble();
      size = await measureMath(latex, colorArgb: color, fontSize: fontSize, displayMode: false);
    }
    if (_disposed) return;
    final s = state;
    final page = s?.pages[fileName];
    if (s == null || page == null || !page.layers.content.any(replaced)) return;
    final width = size?.width ?? bounds.width;
    final height = size?.height ?? bounds.height;
    final id = const Uuid().v4();
    final updatedPage = pageWithContent(page, [
      ...page.layers.content.where((e) => !replaced(e)),
      ContentElement.math(
        id: id,
        zIndex: nextZIndex(page),
        data: MathData(
          x: bounds.center.dx - width / 2,
          y: bounds.center.dy - height / 2,
          width: width,
          height: height,
          latex: latex,
          displayMode: false,
          color: color,
          fontSize: fontSize,
        ),
      ),
    ]);
    commitPageEdit(s, fileName, updatedPage,
        undoOf: page,
        alsoState: (n) => n.copyWith(
            lassoPath: [], clearLasso: true, selectedElementId: id));
  }

  /// Swaps the elements [removedIds] on page [fileName] for [added], over
  /// [image] (a new picture, PNG) if any, in one undo step. A recogniser runs
  /// for a while: if the page no longer holds any of them, nothing changes.
  void replaceStrokesWithDrawing(String fileName, Set<String> removedIds, List<StrokeData> added,
      {({Uint8List png, ImageData data})? image}) {
    final s = state;
    final page = s?.pages[fileName];
    if (s == null || page == null) return;
    bool replaced(ContentElement e) =>
        (e is StrokeElement || e is ShapeElement || e is ImageElement) && removedIds.contains(e.id);
    if (!page.layers.content.any(replaced)) return;
    var z = nextZIndex(page);
    final dupId = image == null ? null : findIdenticalAsset(image.png, s.assetBytes);
    final assetId = image == null ? null : dupId ?? '${const Uuid().v4()}_circuit_rest.png';
    final updatedPage = pageWithContent(page, [
      ...page.layers.content.where((e) => !replaced(e)),
      if (image != null)
        ContentElement.image(id: const Uuid().v4(), zIndex: z++, data: image.data.copyWith(assetPath: assetId!)),
      for (final data in added) ContentElement.stroke(id: const Uuid().v4(), zIndex: z++, data: data),
    ], assetReferences: [...page.assetReferences, if (assetId != null) assetId]);
    var assetBytes = s.assetBytes;
    if (image != null && dupId == null) {
      assetBytes = {...s.assetBytes, assetId!: image.png};
      (_assetsByLength[image.png.length] ??= []).add(assetId);
      _assets.decodeAndCache(assetId, image.png);
      markAssetDirty(assetId);
    }
    commitPageEdit(s, fileName, updatedPage,
        undoOf: page,
        alsoState: (n) => n.copyWith(
            assetBytes: assetBytes, lassoPath: [], clearLasso: true));
  }

  void clearSelection() => _selection.clearSelection();

  /// Change the color of all selected strokes/shapes/text.
  void changeSelectionColor(int newColor) => _selection.changeSelectionColor(newColor);

  /// Sets the stroke/shape width of the selection; a slider drag pushes one
  /// undo entry, closed by [endSelectionWidthEdit].
  void changeSelectionStrokeWidth(double newWidth) =>
      _selection.changeSelectionStrokeWidth(newWidth);

  /// Ends the width-adjustment gesture so the next drag starts a new undo entry.
  void endSelectionWidthEdit() => _selection.endSelectionWidthEdit();

  // ── Undo / Redo ──

  /// Index of the newest entry of [stack] that belongs to [fileName].
  static int _lastEntryFor(List<UndoEntry> stack, String fileName) {
    for (var i = stack.length - 1; i >= 0; i--) {
      if (stack[i].pageFileName == fileName) return i;
    }
    return -1;
  }

  /// Dismiss the lasso before a history step so its stale ids/bounds can't
  /// outlive the page swap. Returns false when an uncommitted move/resize
  /// is pending and [commitPending] is false (redo must not discard it).
  bool _settleSelectionForHistory({required bool commitPending}) {
    final sel = state!.lassoSelection;
    if (sel == null) return true;
    final pending = sel.rotation != 0.0 ||
        sel.dragOffset != Offset.zero ||
        sel.scale != 1.0;
    if (pending && !commitPending) return false;
    if (pending) applySelectionTransform();
    state = state!.copyWith(clearLasso: true, lassoPath: []);
    return true;
  }

  void undo() {
    _diagStrokeId = null;
    if (state == null || state!.document.pages.isEmpty) return;
    final fileName = state!.currentPageFileName;
    final sel = state!.lassoSelection;
    final hasPending = sel != null &&
        (sel.rotation != 0.0 ||
            sel.dragOffset != Offset.zero ||
            sel.scale != 1.0);
    if (!hasPending && _lastEntryFor(state!.undoStack, fileName) < 0) return;
    _settleSelectionForHistory(commitPending: true);
    final s = state!;
    final idx = _lastEntryFor(s.undoStack, fileName);
    if (idx < 0) return;
    final h = _stepHistory(s, s.undoStack, s.redoStack, idx);
    state = s.copyWith(
        pages: h.pages,
        document: _withEntrySize(s.document, fileName, h.pages[fileName]!),
        undoStack: h.from,
        redoStack: h.to,
        isDirty: true);
  }

  /// Moves the step at [idx] of [from] onto [to]. A grouped step takes every
  /// page whose latest entry is in the group; pages edited since keep theirs.
  static ({Map<String, PageData> pages, List<UndoEntry> from, List<UndoEntry> to})
      _stepHistory(CanvasState s, List<UndoEntry> from, List<UndoEntry> to,
          int idx) {
    final entry = from[idx];
    final picked = <int>[idx];
    final group = entry.group;
    if (group != null) {
      final latest = <String>{entry.pageFileName};
      for (var i = from.length - 1; i >= 0; i--) {
        final e = from[i];
        if (!latest.add(e.pageFileName)) continue;
        if (e.group == group) picked.add(i);
      }
    }
    picked.sort();
    final pages = Map<String, PageData>.from(s.pages);
    final newTo = [...to];
    for (final i in picked) {
      final e = from[i];
      final current = s.pages[e.pageFileName];
      if (current != null) {
        newTo.add(UndoEntry(e.pageFileName, current, group: group));
      }
      pages[e.pageFileName] = e.pageData;
    }
    final pickedSet = picked.toSet();
    final newFrom = [
      for (var i = 0; i < from.length; i++)
        if (!pickedSet.contains(i)) from[i],
    ];
    return (pages: pages, from: newFrom, to: newTo);
  }

  void redo() {
    if (state == null || state!.document.pages.isEmpty) return;
    final fileName = state!.currentPageFileName;
    if (_lastEntryFor(state!.redoStack, fileName) < 0) return;
    if (!_settleSelectionForHistory(commitPending: false)) return;
    final s = state!;
    final idx = _lastEntryFor(s.redoStack, fileName);
    if (idx < 0) return;
    final h = _stepHistory(s, s.redoStack, s.undoStack, idx);
    state = s.copyWith(
        pages: h.pages,
        document: _withEntrySize(s.document, fileName, h.pages[fileName]!),
        undoStack: h.to,
        redoStack: h.from,
        isDirty: true);
  }

  bool get canUndo =>
      state != null &&
      state!.document.pages.isNotEmpty &&
      _lastEntryFor(state!.undoStack, state!.currentPageFileName) >= 0;
  bool get canRedo =>
      state != null &&
      state!.document.pages.isNotEmpty &&
      _lastEntryFor(state!.redoStack, state!.currentPageFileName) >= 0;

  // ── Page management ──

  void setActiveChapter(String? chapterId) => _pages.setActiveChapter(chapterId);

  /// Navigate to [index]. By default the user's zoom/pan is preserved so
  /// arrow-button and grid taps don't rip the viewport out from under them.
  /// Pass [resetViewport]=true for gestures where a fresh view is wanted
  /// (e.g. swipe-to-turn-page).
  void goToPage(int index, {bool resetViewport = false}) =>
      _pages.goToPage(index, resetViewport: resetViewport);

  void nextPage({bool resetViewport = false}) =>
      _pages.nextPage(resetViewport: resetViewport);

  void prevPage({bool resetViewport = false}) =>
      _pages.prevPage(resetViewport: resetViewport);

  void addPage() => _pages.addPage();

  /// Insert a new blank page at a specific position (0-based index).
  void insertPageAt(int index) => _pages.insertPageAt(index);

  /// Pastes [pages] into this notebook at [slot] (default: end of the last
  /// chapter) and returns the new page ids. Fresh ids and file names; the
  /// chapter is the slot's, never invented. [assets] are materialized here so
  /// the pasted pages do not point at ids that exist only in the source.
  List<String> pastePages({
    required List<PageData> pages,
    required List<PageEntry> entries,
    Map<String, Uint8List> assets = const {},
    PasteSlot? slot,
    List<String>? pageIds,
  }) =>
      _pages.pastePages(
          pages: pages,
          entries: entries,
          assets: assets,
          slot: slot,
          pageIds: pageIds);

  /// Deletes the pages with these ids (those not here are ignored).
  void deletePagesById(Set<String> pageIds) => _pages.deletePagesById(pageIds);

  /// Moves pages inside this notebook to [slot] (see [planMoveWithin]); the
  /// editor stays on the page it was showing.
  void movePagesToSlot(Set<String> pageIds, PasteSlot slot) =>
      _pages.movePagesToSlot(pageIds, slot);

  /// Page order and chapters back to [before] (Undo of [movePagesToSlot]).
  void restorePageOrder(List<PageEntry> before) =>
      _pages.restorePageOrder(before);

  void addChapter(String title) => _pages.addChapter(title);

  void renameChapter(String chapterId, String title) =>
      _pages.renameChapter(chapterId, title);

  void reorderChapters(int oldIndex, int newIndex) =>
      _pages.reorderChapters(oldIndex, newIndex);

  void deleteChapter(String chapterId) => _pages.deleteChapter(chapterId);

  void assignPageToChapter(int pageIndex, String? chapterId) =>
      _pages.assignPageToChapter(pageIndex, chapterId);

  // ── Zoom & Pan ──

  /// Mark "user is currently dragging/zooming". The pull tick consults
  /// [_isInteractingRecent] and skips its network round-trip until the
  /// user stops moving — keeps response-handling microtasks out of the
  /// pan event loop.
  void _bumpInteract() {
    _lastInteractAt = DateTime.now();
    _wakePullFromIdle();
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
      final b = elementBounds(el);
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

  /// Adds a text box at [position] (see [ElementEditor.addTextElement]).
  void addTextElement(
    Offset position,
    String content, {
    double fontSize = 16,
    List<TextSpanData> spans = const [],
    int? color,
    String alignment = 'left',
    double width = ElementEditor.textWrapWidth,
  }) =>
      _elements.addTextElement(position, content,
          fontSize: fontSize,
          spans: spans,
          color: color,
          alignment: alignment,
          width: width);

  /// Pastes a parsed Markdown/LaTeX document as a stack of text and math
  /// elements in one undo step, anchored at [anchor] and kept inside the page.
  Future<void> pasteRichBlocks(
    List<PastedBlock> blocks,
    Offset anchor, {
    int? color,
    double maxWidth = 360,
    double pixelRatio = 3.0,
  }) =>
      _clip.pasteRichBlocks(blocks, anchor,
          color: color,
          maxWidth: maxWidth,
          pixelRatio: pixelRatio);

  /// Replaces content and style of a text element, re-fitting its box.
  void updateTextElement(
    String elementId, {
    required String content,
    required List<TextSpanData> spans,
    required double fontSize,
    required int color,
    required String alignment,
  }) =>
      _elements.updateTextElement(elementId,
          content: content,
          spans: spans,
          fontSize: fontSize,
          color: color,
          alignment: alignment);

  // ── Helpers ──

  /// Push an undo entry. Cap depth at 30 (was 50) — for a typical
  /// 200-stroke page that drops the upper-bound resident memory of
  /// the undo stack from ~25 MB to ~15 MB without practically reducing
  /// reachable history (very few people use undo more than ~20 steps
  /// back on a single page). Combined with the chrome's switch from
  /// undoStack/redoStack refs to canUndo/canRedo booleans (perf_state
  /// 2.8) the per-stroke chrome rebuild churn is also gone.
  static const int _undoStackCap = 30;
  @override
  List<UndoEntry> pushUndo(CanvasState s, String fileName, PageData page) {
    final source = s.undoStack;
    // Build the new list at the right capacity: drop the oldest if we'd
    // exceed the cap, otherwise just append. Using sublist + add avoids
    // the O(N) removeAt(0) the previous code paid on every push past
    // 50 entries.
    if (source.length < _undoStackCap) {
      return [...source, UndoEntry(fileName, page)];
    }
    return _trimUndo([...source, UndoEntry(fileName, page)]);
  }

  /// [stack] capped at [_undoStackCap] steps; a grouped step counts once.
  static List<UndoEntry> _trimUndo(List<UndoEntry> stack) {
    var steps = 0;
    final seen = <int>{};
    for (var i = stack.length - 1; i >= 0; i--) {
      final g = stack[i].group;
      if (g == null || seen.add(g)) steps++;
      // stack[i] opens the oldest step past the cap: keep what follows it.
      if (steps > _undoStackCap) return stack.sublist(i + 1);
    }
    return stack;
  }

  @override
  int nextZIndex(PageData page) {
    int maxZ = -1;
    for (final e in page.layers.content) {
      final z = e.zIndex;
      if (z > maxZ) maxZ = z;
    }
    return maxZ + 1;
  }

  @override
  PageData pageWithNewElement(PageData page, ContentElement element) {
    return pageWithContent(page, [...page.layers.content, element]);
  }

  /// [page] with [content] (and optionally [assetReferences]) swapped in,
  /// its PDF text layer carried over.
  @override
  PageData pageWithContent(PageData page, List<ContentElement> content,
      {List<String>? assetReferences}) {
    return carryPdfTextLayer(page, PageData(
      pageId: page.pageId, pageNumber: page.pageNumber,
      width: page.width, height: page.height,
      layers: RenderingLayers(background: page.layers.background, content: content),
      assetReferences: assetReferences ?? page.assetReferences,
      createdAt: page.createdAt, modifiedAt: DateTime.now(),
    ));
  }

  /// The one way to write an edited page back: [after] replaces [fileName]
  /// and the notebook turns dirty. With [history] (default) redo is dropped
  /// and, when [undoOf] is given, that page is pushed as one undo step;
  /// `history: false` leaves undo and redo alone (drag follow-ups).
  /// [alsoState] adds the caller's other fields to the same state write.
  @override
  void commitPageEdit(CanvasState s, String fileName, PageData after,
      {PageData? undoOf,
      bool history = true,
      CanvasState Function(CanvasState)? alsoState}) {
    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = after;
    final next = history
        ? s.copyWith(
            pages: updatedPages,
            undoStack: undoOf == null ? s.undoStack : pushUndo(s, fileName, undoOf),
            redoStack: [],
            isDirty: true)
        : s.copyWith(pages: updatedPages, isDirty: true);
    state = alsoState == null ? next : alsoState(next);
  }

  // ── Element selection & transform ──

  void selectElement(String elementId) => _selection.selectElement(elementId);

  void selectIds(Set<String> ids) => _selection.selectIds(ids);

  void deselectElement() => _selection.deselectElement();

  void moveElement(String elementId, Offset delta) =>
      _elements.moveElement(elementId, delta);

  /// Call this before starting a drag to push undo state once
  void startDragElement(String elementId) => _elements.startDragElement(elementId);

  /// Smart resize of a text element: side handles pass [width], corner
  /// handles [fontScale] and [width]; [topLeft] moves the box.
  void resizeTextElement(
    String elementId, {
    double? width,
    double? height,
    double? fontScale,
    Offset? topLeft,
  }) =>
      _elements.resizeTextElement(elementId,
          width: width, height: height, fontScale: fontScale, topLeft: topLeft);

  void resizeElement(String elementId, Rect newBounds) =>
      _elements.resizeElement(elementId, newBounds);

  void rotateElement(String elementId, double deltaAngle) =>
      _elements.rotateElement(elementId, deltaAngle);

  void deleteElement(String elementId) => _elements.deleteElement(elementId);

  void bringToFront(String elementId) => _elements.bringToFront(elementId);

  void sendToBack(String elementId) => _elements.sendToBack(elementId);

  void toggleImageLock(String elementId) => _elements.toggleImageLock(elementId);

  /// Toggles horizontal flip on an image element.
  void flipImageElement(String elementId) => _elements.flipImageElement(elementId);

  void setImageComment(String elementId, String? comment) =>
      _elements.setImageComment(elementId, comment);

  // ── Image insertion ──

  /// Returns the asset id the image was stored under (`null` if no current
  /// page). PDF import uses it to tie an extracted text layer to its raster.
  String? addImageElement(Offset position, String fileName, Uint8List bytes,
          double width, double height,
          {bool locked = false, ({double w, double h})? pdfSizePt}) =>
      _elements.addImageElement(position, fileName, bytes, width, height,
          locked: locked, pdfSizePt: pdfSizePt);

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
    commitPageEdit(s, pageFileName, page.copyWith(pdfTextLayer: layer), history: false);
  }

  /// Resize a page (and its document entry) and make its paper blank. PDF
  /// import calls it so a page takes the source PDF page's shape instead of
  /// letterboxing it on A4 ruling.
  void setPageGeometry(String pageFileName, double width, double height,
      {bool blankPaper = true}) {
    if (state == null) return;
    final s = state!;
    final page = s.pages[pageFileName];
    if (page == null) return;
    final bg = blankPaper
        ? page.layers.background.copyWith(type: 'blank')
        : page.layers.background;
    final entries = [
      for (final e in s.document.pages)
        e.fileName == pageFileName ? e.copyWith(width: width, height: height) : e,
    ];
    final resized = page.copyWith(
      width: width,
      height: height,
      layers: page.layers.copyWith(background: bg),
    );
    commitPageEdit(s, pageFileName, resized,
        history: false,
        alsoState: (n) => n.copyWith(
              document: DocumentStructure(
                notebookId: s.document.notebookId,
                formatVersion: s.document.formatVersion,
                pages: entries,
              ),
            ));
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
  @override
  Map<int, List<String>> get assetsByLength => _assetsByLength;
  bool _assetIndexBuilt = false;

  /// Returns the id of an existing asset whose bytes are identical to [bytes],
  /// or null if none. Lazily indexes the current asset set on first use.
  @override
  String? findIdenticalAsset(Uint8List bytes, Map<String, Uint8List> assets) {
    if (!_assetIndexBuilt) {
      _assetsByLength.clear();
      assets.forEach((id, b) => (_assetsByLength[b.length] ??= []).add(id));
      _assetIndexBuilt = true;
    }
    final candidates = _assetsByLength[bytes.length];
    if (candidates == null) return null;
    for (final id in candidates) {
      final b = assets[id];
      if (b != null && AssetCache.bytesEqual(b, bytes)) return id;
    }
    return null;
  }

  /// Crops an image element to a normalized rect (0..1), as a new asset.
  Future<void> cropImageElement(String elementId, Rect normalizedCrop) =>
      _elements.cropImageElement(elementId, normalizedCrop);

  // ── Clipboard operations ──

  void copySelection() => _clip.copySelection();

  void cutSelection() {
    copySelection();
    deleteSelection();
  }

  /// Copy a single element (e.g. an image / PDF preview) to the clipboard.
  void copyElement(String elementId) => _clip.copyElement(elementId);

  /// Cut a single element: copy to clipboard, then delete.
  void cutElement(String elementId) {
    copyElement(elementId);
    deleteElement(elementId);
  }

  void paste({Offset? at}) => _clip.paste(at: at);

  /// Duplicate the current lasso selection in place and keep the copies
  /// selected, so the lasso handles can drag/scale/rotate them.
  void duplicateSelection() => _clip.duplicateSelection();

  /// Replaces the LaTeX of a math element, kept centred. One undo entry.
  Future<void> updateMathLatex(String elementId, String latex) =>
      _elements.updateMathLatex(elementId, latex);

  void duplicateElement(String elementId) => _clip.duplicateElement(elementId);

  void cancelPendingPaste() => _clip.cancelPendingPaste();

  // ── Reusable Symbols & Libraries (see SymbolsLibrary) ──

  void createSymbolLibrary(String name) => _symbolsLib.createSymbolLibrary(name);

  void renameSymbolLibrary(String libId, String newName) =>
      _symbolsLib.renameSymbolLibrary(libId, newName);

  void deleteSymbolLibrary(String libId) =>
      _symbolsLib.deleteSymbolLibrary(libId);

  void renameSymbol(String libId, String symbolId, String newName) =>
      _symbolsLib.renameSymbol(libId, symbolId, newName);

  void deleteSymbolFromLibrary(String libId, String symbolId) =>
      _symbolsLib.deleteSymbolFromLibrary(libId, symbolId);

  /// Creates a symbol from the current lasso selection and adds it to the
  /// target library (first library if [targetLibId] is null).
  void createSymbolFromSelection(String name,
          {String? targetLibId, required String defaultLibraryName}) =>
      _symbolsLib.createSymbolFromSelection(name,
          targetLibId: targetLibId, defaultLibraryName: defaultLibraryName);

  void createSymbolFromElement(String elementId, String name,
          {required String defaultLibraryName}) =>
      _symbolsLib.createSymbolFromElement(elementId, name,
          defaultLibraryName: defaultLibraryName);

  void clearPendingSymbol() => _symbolsLib.clearPendingSymbol();

  /// Drops [symbol] on the page centred on [position], as the vector
  /// elements it was saved from (like [paste]), so it stays sharp at any
  /// zoom, resize and export. Left selected for nudging.
  void insertSymbol(ReusableSymbol symbol, Offset position) {
    if (state == null || _preview || _loadingSnapshotId != null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final offset = position - symbol.bounds.center;
    final baseZ = nextZIndex(page);
    final newElements = <ContentElement>[];
    final newRefs = <String>[];
    for (final element in symbol.elements) {
      // A picture inside the symbol only comes along when this notebook has
      // its bytes; otherwise it would be a reference to nothing.
      if (element is ImageElement) {
        final p = element.data.assetPath;
        if (!s.assetBytes.containsKey(p)) continue;
        if (!page.assetReferences.contains(p) && !newRefs.contains(p)) {
          newRefs.add(p);
        }
      }
      final newId = const Uuid().v4();
      final z = baseZ + newElements.length;
      newElements.add(translateElement(element, offset).map(
        unknown: (u) => u.copyWith(id: newId, zIndex: z),
        stroke: (e) => ContentElement.stroke(id: newId, zIndex: z, data: e.data),
        text: (e) => ContentElement.text(id: newId, zIndex: z, data: e.data),
        image: (e) => ContentElement.image(id: newId, zIndex: z, data: e.data),
        shape: (e) => ContentElement.shape(id: newId, zIndex: z, data: e.data),
        math: (e) => ContentElement.math(id: newId, zIndex: z, data: e.data),
      ));
    }
    if (newElements.isEmpty) {
      state = s.copyWith(clearPendingSymbol: true);
      return;
    }

    final updatedPage = pageWithContent(page, [...page.layers.content, ...newElements], assetReferences: [...page.assetReferences, ...newRefs]);
    // Land in lasso mode on the placed symbol: it is usually dropped roughly
    // right and then nudged or resized, which needs it selected at once.
    commitPageEdit(s, fileName, updatedPage,
        undoOf: page,
        alsoState: (n) => n.copyWith(
              lassoPath: [],
              lassoSelection: LassoSelection(
                selectedIds: [for (final e in newElements) e.id],
                bounds: symbol.bounds.shift(offset),
              ),
              clearPendingSymbol: true,
              currentTool: CanvasTool.lasso,
            ));
    // Pictures are drawn from the decoded cache only; paste decodes too.
    for (final e in newElements) {
      if (e is ImageElement) ensureAssetDecodedForThumbnail(e.data.assetPath);
    }
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
  ///
  /// Only pages in [goneFromServer] (from [checkMissingPages]) are repaired:
  /// a blank uploaded over a page the server still has destroys it.
  bool repairMissingPageData(int docIndex, Set<String> goneFromServer) {
    if (state == null) return false;
    final s = state!;
    if (docIndex < 0 || docIndex >= s.document.pages.length) return false;
    final entry = s.document.pages[docIndex];
    // Only repair if data is genuinely missing — do not clobber real content.
    if (s.pages.containsKey(entry.fileName)) return false;
    if (!goneFromServer.contains(entry.fileName)) return false;

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
    // _sync.lastSyncedPages already flags it — the next save() pushes the blank
    // page and clears the server-side gap.
    updatedPages[entry.fileName] = blank;

    state = s.copyWith(pages: updatedPages, isDirty: true);
    print('[Canvas] repairMissingPageData: restored ${entry.fileName} '
        'as blank at index $docIndex');
    return true;
  }

  /// Heal every missing page in [goneFromServer]. Returns the number of
  /// pages that were replaced with a blank.
  int repairAllMissingPages(Set<String> goneFromServer) {
    final s = state;
    if (s == null) return 0;
    var repaired = 0;
    for (int i = 0; i < s.document.pages.length; i++) {
      if (!state!.pages.containsKey(s.document.pages[i].fileName)) {
        if (repairMissingPageData(i, goneFromServer)) repaired++;
      }
    }
    return repaired;
  }

  /// Asks the server about the pages this device has no data for and starts
  /// downloading the ones it still has. [goneFromServer] lists only pages a
  /// complete server listing confirms absent; unreachable means unknown.
  /// [noServer]: the notebook never syncs, so nothing else holds the pages.
  Future<({bool reachable, bool noServer, Set<String> goneFromServer})>
      checkMissingPages() async {
    const unknown =
        (reachable: false, noServer: false, goneFromServer: <String>{});
    final s = state;
    if (s == null) return unknown;
    final missing = {
      for (final e in s.document.pages)
        if (!s.pages.containsKey(e.fileName)) e.fileName,
    };
    final syncService = _ref.read(syncServiceProvider);
    final id = s.metadata.id;
    if (syncService == null ||
        syncService.isOffline ||
        await _isLocalOnly(id)) {
      return (reachable: false, noServer: true, goneFromServer: missing);
    }
    try {
      final remote = await syncService.getRemoteChangeState(id);
      if (remote.metaEtag == null) return unknown;
      // A listing smaller than what this device holds is not trustworthy.
      if (remote.pageEtags.length < s.document.pages.length - missing.length) {
        return unknown;
      }
      final gone = {
        for (final fn in missing)
          if (!remote.pageEtags.containsKey(fn)) fn,
      };
      unawaited(CrashLogger.append(
        '[MissingPages] ${missing.length} without local data, '
        '${gone.length} absent on the server',
      ));
      if (gone.length < missing.length) unawaited(_pull.pullRemoteChanges());
      return (reachable: true, noServer: false, goneFromServer: gone);
    } catch (e) {
      unawaited(CrashLogger.append('[MissingPages] server check failed: $e'));
      return unknown;
    }
  }

  void deletePage(int index) => _pages.deletePage(index);

  /// Delete multiple pages in a single state update.
  ///
  /// [docIndices] are absolute document indices (not filtered/visible indices).
  /// Must contain at least one index and must not delete ALL pages if only one
  /// page remains.
  void deletePages(List<int> docIndices) => _pages.deletePages(docIndices);

  /// Assign multiple pages to a chapter (or clear their chapter) in a single
  /// state update.
  void assignPagesToChapter(List<int> docIndices, String? chapterId) =>
      _pages.assignPagesToChapter(docIndices, chapterId);

  void duplicatePage(int index) => _pages.duplicatePage(index);

  /// Move a set of pages (possibly non-contiguous) so that the first moved
  /// page lands at final 1-based position [targetPosition]. Complements
  /// drag-and-drop, which is impractical for long-distance moves in big
  /// notebooks.
  void movePagesToPosition(List<int> docIndices, int targetPosition) =>
      _pages.movePagesToPosition(docIndices, targetPosition);

  // ── Clear page ──

  void clearPage() {
    if (state == null) return;
    final s = state!;
    final page = s.currentPage;
    if (page == null || page.layers.content.isEmpty) return;
    final fileName = s.currentPageFileName;

    final clearedPage = pageWithContent(page, const []);

    commitPageEdit(s, fileName, clearedPage, undoOf: page);
  }

  // ── Select all elements ──

  void selectAll() => _selection.selectAll();

  /// Zooms by [factor] around the viewport centre (Ctrl + / Ctrl −).
  void zoomBy(double factor) {
    final s = state;
    final vp = _viewportSize;
    if (s == null || vp == null) return;
    final z = (s.zoom * factor).clamp(0.25, 5.0);
    final c = Offset(vp.width / 2, vp.height / 2);
    setZoomAndPan(z, c - (c - s.panOffset) * (z / s.zoom));
  }

  // ── Reset zoom ──

  void resetZoom() {
    if (state == null) return;
    if (state!.isScratch) {
      fitToContent();
      return;
    }
    state = state!.copyWith(zoom: 2.0, panOffset: centeredPanOffset(2.0));
  }

  /// Fit the current page vertically into the viewport. Computes the zoom
  /// that makes the full page height visible at once + horizontally centers
  /// the page. Bound to the double-tap gesture on the canvas.
  void zoomToFit() {
    final s = state;
    final vp = _viewportSize;
    if (s == null || vp == null) return;
    if (s.isScratch) {
      fitToContent();
      return;
    }
    final page = s.currentPage;
    if (page == null) return;
    // zoom is relative to the viewport-fit scale of the page (zoom 1 = page
    // fills the viewport), so the margin-fit zoom is expressed against it.
    const margin = 24.0;
    final fit = min(vp.width / page.width, vp.height / page.height);
    final target = min((vp.width - margin * 2) / page.width,
        (vp.height - margin * 2) / page.height);
    final newZoom = (target / fit).clamp(0.3, 5.0).toDouble();
    _bumpInteract();
    state = s.copyWith(
      zoom: newZoom,
      panOffset: Offset(vp.width, vp.height) * ((1 - newZoom) / 2),
    );
  }

  /// Writes the open notebook to its loose store and returns true once the
  /// store holds it; false if the write failed. The upload runs on its own
  /// afterwards.
  Future<bool> saveLocally() async {
    if (state == null) return false;
    final ok = await _save.persistLocal();
    unawaited(save());
    return ok;
  }

  /// Puts the notebook on disk now, e.g. before the OS may kill the app.
  Future<bool> persistLocalNow() => state == null
      ? Future<bool>.value(false)
      : _save.persistLocal();

  /// The last local write's error, or null once one succeeds.
  ValueNotifier<Object?> get localSaveError => _save.localSaveError;

  bool _preview = false;

  /// A notebook file opened from outside, shown read-only: nothing of it is
  /// written anywhere, synced, or merged into the library.
  bool get isPreview => _preview;

  /// True while a pull, retry or commit-retry timer is armed.
  @visibleForTesting
  bool get hasSyncTimers => _sync.hasTimers;

  /// The user chose to leave without what could not be saved: closing must
  /// neither write nor upload it.
  void discardUnsavedEdits() {
    if (state == null) return;
    _save.discard();
    state = state!.copyWith(isDirty: false);
  }

  Future<void> save() async {
    if (state == null || _preview || _loadingSnapshotId != null) return;
    // Run even when not dirty if a delete queue is pending: a delete-only
    // save that failed remotely leaves isDirty false, and without this the
    // queued DELETEs would wait for an unrelated edit to be retried.
    final hasPendingDeletes =
        _sync.pendingPageDeletes.isNotEmpty || _sync.pendingAssetDeletes.isNotEmpty;
    // Disk first, without the sync lock: an upload or a pull can hold that
    // for minutes, and a crash meanwhile lost every edit made since.
    final local = _save.persistLocal();
    if (_save.discardRequested) return;
    // With no sync the local write is the whole save, and the remote path
    // below (which refreshes the library thumbnail) never runs.
    if (_ref.read(syncServiceProvider) == null) {
      _thumbnails.refresh(state!, state!.metadata.id);
    }
    if (!state!.isDirty && !hasPendingDeletes) {
      await local;
      return;
    }
    _wakePullFromIdle();
    final lease = await _sync.acquireLease();
    if (lease == null || state == null) return;
    bool lockTransferred = false;
    try {
      lockTransferred = await _saveInner(lease);
    } finally {
      if (!lockTransferred) lease.release();
    }
  }

  /// Performs local save synchronously, then hands the sync lock to a
  /// background task that uploads to the server.
  ///
  /// Returns `true` if the background task has taken ownership of the
  /// sync lock (caller must NOT release it). Returns `false` if the
  /// caller must release the lock itself (nothing scheduled).
  Future<bool> _saveInner(SyncLockLease lease) async {
    final plan = _prepareSave();
    if (plan == null) return false;
    final snapshotDirtyAssetKeys = _commitSaveSnapshot(plan);

    // Encode the dirty pages ONCE, up front. Both consumers reuse these
    // bytes: the upload and the local write (cache hit by identity). The
    // encode respects the quiet-pointer gate so it can't kink a stroke.
    final preEncodedDirty =
        await _encodePagesWithCache(plan.changedPages, evictMissing: false);

    // The upload starts before the local write: small edits reach the
    // server in seconds instead of waiting for the disk.
    final remoteSyncFuture = _push.startRemoteSync(plan, preEncodedDirty);
    final localSaveFuture = _writeLocally(plan);
    _push.trackRemoteSave(plan, snapshotDirtyAssetKeys, remoteSyncFuture,
        localSaveFuture, lease);
    return true;
  }

  /// Stage 1: the integrity guards, then which pages, assets and deletions
  /// this save carries. Null when there is nothing to save or push.
  SavePlan? _prepareSave() {
    if (state == null || !state!.isDirty) return null;

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
        if (_sync.preSaveGuardSince == null ||
            now.difference(_sync.preSaveGuardSince!) > _preSaveGuardWindow) {
          _sync.preSaveGuardSince = now;
          _sync.preSaveGuardAborts = 0;
        }
        _sync.preSaveGuardAborts++;
        final triggerPull = _sync.preSaveGuardAborts <= _maxPreSaveGuardAborts;
        print('[Canvas] PRE-SAVE GUARD #2: aborting — document has '
            '${missingData.length} entries without page data '
            '($sample${missingData.length > 3 ? "..." : ""})'
            '${triggerPull ? ". Triggering pull to re-hydrate first." : " (rate-limited: ${_sync.preSaveGuardAborts} in ${_preSaveGuardWindow.inSeconds}s — not kicking another pull)."}');
        unawaited(CrashLogger.append(
          '[Save] aborted: doc=${cur.document.pages.length} > '
          'pages=${cur.pages.length} (missing: $sample) '
          'guard#${_sync.preSaveGuardAborts} pull=$triggerPull',
        ));
        if (triggerPull) {
          unawaited(_pull.pullRemoteChanges());
        }
        return null;
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
    if (syncService == null) return null;

    // Always derive pageCount from the live document so the DB is never
    // left with a stale count (e.g. after an auto-accept stamped the
    // server's old count onto metadata).
    final updatedMeta = s.metadata.copyWith(
      modifiedAt: DateTime.now(),
      pageCount: s.document.pages.length,
      chapters: _chaptersWithMembership(s.metadata.chapters, s.document),
    );

    // ── Detect which pages actually changed (identity comparison) ──
    final changedPages = <String, PageData>{};

    for (final entry in s.pages.entries) {
      if (!identical(entry.value, _sync.lastSyncedPages[entry.key])) {
        changedPages[entry.key] = entry.value;
      }
    }
    // Also detect new pages (added since last sync)
    for (final key in s.pages.keys) {
      if (!_sync.lastSyncedPages.containsKey(key)) {
        changedPages[key] = s.pages[key]!;
      }
    }
    // Pages to write whole on close, folding their stroke chunks.
    final compactPages = {
      for (final fn in _sync.compactNext)
        if (s.pages.containsKey(fn)) fn,
    };
    _sync.compactNext.clear();
    for (final fn in compactPages) {
      changedPages[fn] = s.pages[fn]!;
    }

    // Detect changed assets
    final changedAssets = <String, Uint8List>{};
    for (final key in _sync.dirtyAssetKeys) {
      if (s.assetBytes.containsKey(key)) {
        changedAssets[key] = s.assetBytes[key]!;
      }
    }

    // Detect deleted pages (existed in last sync but no longer in current state)
    final deletedPages = <String>[];
    for (final key in _sync.lastSyncedPages.keys) {
      if (!s.pages.containsKey(key)) {
        deletedPages.add(key);
      }
    }
    // Stage into the persistent pending queue so a thrown remote sync
    // doesn't lose the deletion request — _remoteSync merges these and
    // clears them on confirmed success.
    _sync.pendingPageDeletes.addAll(deletedPages);

    // Drop pending DELETEs that conflict with what we're about to PUT.
    // Without this guard, Phase 0 of syncDelta (DELETE) fires in
    // parallel with Phase 1 (PUT) — a stale pending delete for
    // page_010.json could race the new page_010.json PUT and leave the
    // server without the just-uploaded content. _nextPageFileName
    // reuses numeric suffixes after deletion, so this collision is
    // realistic when the user re-imports a PDF after deleting the prior.
    if (changedPages.isNotEmpty) {
      _sync.pendingPageDeletes.removeWhere((fn) => changedPages.containsKey(fn));
    }
    if (changedAssets.isNotEmpty) {
      _sync.pendingAssetDeletes.removeWhere((id) => changedAssets.containsKey(id));
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

    return SavePlan(
      s: s,
      syncService: syncService,
      fileService: fileService,
      updatedMeta: updatedMeta,
      changedPages: changedPages,
      changedAssets: changedAssets,
      deletedPages: deletedPages,
      compactPages: compactPages,
    );
  }

  /// Stage 2: the state moves on at once so the UI unblocks, and the dirty
  /// asset keys of this save are captured (cleared only if the upload lands).
  Set<String> _commitSaveSnapshot(SavePlan plan) {
    final s = plan.s;
    final updatedMeta = plan.updatedMeta;
    // Update state IMMEDIATELY so the UI unblocks on this microtask.
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
    return Set<String>.of(_sync.dirtyAssetKeys);
  }

  /// Stage 3, local: queues the write of everything the store lacks.
  Future<bool> _writeLocally(SavePlan plan) {
    final s = plan.s;
    final updatedMeta = plan.updatedMeta;
    // Persist locally: everything the store lacks, this snapshot
    //    included. Queued after any earlier local write, not behind the
    //    upload; the ETag persist below waits for it.
    final localSaveFuture = _save.persistLocal();

    _thumbnails.refresh(s, updatedMeta.id);

    return localSaveFuture;
  }

  /// Whether the open notebook is one the user keeps off the remote.
  ///
  /// Cached per notebook: it is read on every save and every pull tick, and
  /// it only changes when the user flips it, which goes through
  /// [forgetLocalOnly].
  final Map<String, bool> _localOnlyCache = {};

  Future<bool> _isLocalOnly(String notebookId) async {
    final cached = _localOnlyCache[notebookId];
    if (cached != null) return cached;
    try {
      final flag =
          await _ref.read(fileServiceProvider).isNotebookLocalOnly(notebookId);
      return _localOnlyCache[notebookId] = flag;
    } catch (_) {
      // Unknown: assume it syncs, which is the pre-existing behaviour. The
      // opposite guess would silently stop syncing a notebook.
      return false;
    }
  }

  /// Drops the cached answer after the user changes the setting.
  void forgetLocalOnly(String notebookId) {
    _localOnlyCache.remove(notebookId);
    final st = state;
    if (st != null && st.metadata.id == notebookId) {
      unawaited(_isLocalOnly(notebookId).then((v) => keptLocal.value =
          v || (_ref.read(syncServiceProvider)?.isOffline ?? true)));
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  PULL TIMER — receive remote changes from other devices
  // ══════════════════════════════════════════════════════════════

  /// Random source for per-device pull-interval jitter.
  final _pullJitterRng = Random();

  void _startPullTimer() {
    _sync.pullTimer?.cancel();
    if (_disposed) return;
    // Immediate pull on notebook open — don't wait first interval.
    // Track the future so closeNotebook can await it.
    // _disposed guard avoids scheduling a pull whose continuation could
    // race a `closeNotebook` issued seconds later on a slow link
    // (downloads keep arriving and try to mutate a torn-down state).
    _sync.pullLoopOn = true;
    _pullThenSchedule();
  }

  /// Runs a pull and arms the next tick only once it has finished, so the
  /// interval reflects how this pull went (the failure backoff counted one
  /// pull late when the next tick was armed at the start).
  void _pullThenSchedule() {
    final f = _pull.pullRemoteChanges();
    _sync.pendingPullFuture = f;
    f.then((_) {}, onError: (_) {}).whenComplete(() {
      if (!_disposed && _sync.pullLoopOn) _schedulePullTick();
    });
  }

  /// Restart the pull timer when coming back from a teardown that killed it
  /// (e.g. previous `paused` lifecycle event). No-op if a timer is already
  /// running. Called from the canvas screen on `AppLifecycleState.resumed`.
  void restartPullTimerIfNeeded() {
    if (_preview) return;
    if (_disposed) return;
    if (state == null) return;
    if (_sync.pullTimer != null) return;
    debugPrint('[Canvas] Resume: restarting pull timer');
    _sync.idlePullCount = 0;
    _startPullTimer();
  }

  @override
  void dispose() {
    _sync.pullLoopOn = false;
    _sync.pullTimer?.cancel();
    _sync.pullTimer = null;
    _sync.pendingMetaCommitTimer?.cancel();
    _sync.pendingMetaCommitTimer = null;
    _sync.remoteRetryTimer?.cancel();
    _sync.remoteRetryTimer = null;
    _eraser.discard();
    _disposed = true;
    _sync.forceReleaseLock(); // a save or pull waiting on it must not hang
    _toolPrefs.dispose();
    _thumbnails.dispose();
    _assets.dispose();
    // Dispose the ValueNotifier instances so any still-subscribed listeners
    // (e.g. the sync pill widget) get cleaned up instead of leaking their
    // attached callbacks on hot-restart / provider container teardown.
    try { isPullingFromRemote.dispose(); } catch (_) {}
    try { pullProgress.dispose(); } catch (_) {}
    try { hasSyncFailure.dispose(); } catch (_) {}
    try { pagesLoading.dispose(); } catch (_) {}
    super.dispose();
  }

  /// Drops a backed-off pull cadence straight back to the fast one: someone
  /// is using this device, so remote edits should show up promptly.
  void _wakePullFromIdle() {
    if (_sync.idlePullCount < SyncPull.idlePullThreshold) return;
    _sync.idlePullCount = 0;
    if (_sync.pullTimer != null) _schedulePullTick();
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
  /// After [SyncPull.idlePullThreshold] consecutive noop pulls we exponentially
  /// back off up to [_idlePullMaxInterval] so an idle notebook doesn't
  /// keep PROPFIND'ing the server and parsing a 215-entry XML payload
  /// every 2 s — that was burning 100 % of one CPU core for no benefit.
  /// On any real change ([_sync.idlePullCount] reset by [_pullRemoteChanges])
  /// we drop straight back to the fast cadence.
  void _schedulePullTick() {
    if (_disposed) return;
    if (_sync.idlePullCount >= SyncPull.deepIdleThreshold) unawaited(SyncThrift.refresh());
    final base = _pull.pullIntervalForIdle();
    final jitterMs = _pullJitterRng.nextInt(AppConfig.deltaPullJitter.inMilliseconds + 1);
    final next = base + Duration(milliseconds: jitterMs);
    _sync.pullTimer?.cancel();
    _sync.pullTimer = Timer(next, () {
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
      // Skip if a pull or save is still in flight. _pull.pullRemoteChanges()
      // early-returns on _sync.isPulling already, but we also want to back off
      // when save() is uploading so a concurrent PROPFIND doesn't see our
      // half-committed delta folder and mis-diagnose it as a remote change.
      if (!_sync.isPulling && _sync.lock == null && !_bulkOperationInProgress) {
        _pullThenSchedule();
        return;
      }
      _schedulePullTick();
    });
  }

  /// After this many consecutive noop pulls the cap stretches to
  /// [_deepIdleMaxInterval], or [_deepIdleThriftyInterval] on metered
  /// data / battery saver. Local activity resets it ([_wakePullFromIdle]).





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
  // _isSyncing tracked by _sync.lock mutex


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
    // snapshot. Identity vs _sync.lastSyncedPages tells us whether the user
    // touched this page since last sync; if yes keep live local, else take
    // remote. Plus: keep truly local-only pages, drop remote-deleted ones.
    final mergedPages = <String, PageData>{};
    final newLastSynced = <String, PageData>{};
    final pulledFileNames = {
      for (final d in pending.changedPages) d.fileName,
    };
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
      final lastSynced = _sync.lastSyncedPages[k];
      // Server page newer than ours while local edits exist (the pull saw
      // disjoint edits, or the user drew during the download): merge,
      // never pick a side. Keeping only live dropped the other device's
      // strokes at the next push, since the pull had already recorded the
      // server's ETag. Pages not pulled this cycle carry local bytes here.
      final userTouchedDuringPull =
          live != null && !identical(live, lastSynced);
      final pulledNow =
          pending.autoMergeable.contains(k) || pulledFileNames.contains(k);
      if (pulledNow &&
          live != null &&
          (pending.autoMergeable.contains(k) || userTouchedDuringPull)) {
        // A same-element clash keeps both sides: an erased stroke may come
        // back, but nothing drawn is lost.
        final reMerged = (lastSynced == null
                ? null
                : mergePageElements(
                    base: lastSynced, local: live, remote: entry.value)) ??
            unionPageElements(local: live, remote: entry.value);
        mergedPages[k] = reMerged;
        // Base = the server page this merge contains. Dropping the base
        // (the old code) made the next pull see "no local edits".
        newLastSynced[k] = entry.value;
        if (reMerged != entry.value) anyAutoMerged = true;
        continue;
      }
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
      final wasPreviouslySynced = _sync.lastSyncedPages.containsKey(entry.key);
      if (wasPreviouslySynced) continue; // remote-deleted → drop
      mergedPages[entry.key] = entry.value; // truly local-only → keep
    }
    // A page deleted here, offline, that another device has since edited
    // came back with this pull: the newer edit wins. Draining the queued
    // DELETE afterwards removed the file under a page list still naming it,
    // losing that edit on the server.
    final revived = _sync.pendingPageDeletes
        .where((fn) => repaired.pages.containsKey(fn))
        .toList();
    if (revived.isNotEmpty) {
      _sync.pendingPageDeletes.removeAll(revived);
      unawaited(_persistPendingDeletes(s.metadata.id));
      print('[Canvas] Dropped queued delete for remotely edited page(s): '
          '${revived.join(", ")}');
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
    final surviving = _pull.survivingFileNames(
      withData: mergedPages.keys,
      docPages: s.document.pages,
      serverFileNames: pending.remotePageFileNames,
      remoteDeleted: pending.remoteDeletedFileNames,
    );
    final merged = merge3Way(
      baseMeta: _sync.lastSyncedMetadata,
      localMeta: s.metadata,
      remoteMeta: pending.metadata,
      baseDoc: _sync.lastSyncedDocument,
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
    // A stale index (outer `if` skipped) must still land inside the merged range.
    newPageIndex = finalDoc.pages.isEmpty
        ? 0
        : newPageIndex.clamp(0, finalDoc.pages.length - 1);
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
    _sync.uploadedAssetKeys.addAll(pending.assets.keys);

    state = s.copyWith(
      undoStack: rebaseHistoryOnMerge(s.undoStack, s.pages, mergedPages),
      redoStack: rebaseHistoryOnMerge(s.redoStack, s.pages, mergedPages),
      metadata: finalMeta,
      document: finalDoc,
      pages: mergedPages,
      assetBytes: mergedAssets,
      currentPageIndex: newPageIndex,
      activeChapterId: mergedChapterId,
      clearPendingRemoteChanges: true,
    );
    _sync.lastSyncedPages = newLastSynced;
    // Baselines track SERVER TRUTH (what this pull observed), NOT the merged
    // result — the merge isn't on the server until we push it. Setting the
    // baseline to `merged` would let a pull during the push window read
    // local's own unpushed contributions as "remote reverted them" and drop
    // them. save() advances these to the merged doc once the upload commits.
    _sync.lastSyncedDocument = repaired.document;
    _sync.remoteDocVersion = _sync.pendingDocVersion;
    _sync.lastSyncedMetadata = pending.metadata;

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
            documentStructurallyDiffers(finalDoc, repaired.document) ||
            metadataStructurallyDiffers(finalMeta, pending.metadata));
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
    _assets.ensureForCurrentWindow();

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
      _sync.pendingPulledLocalSave = _persistPulledMetaOnly(finalMeta);
      return;
    }
    if (missingCount > 0) {
      print('[Canvas] acceptRemoteChanges: $missingCount merged page entries '
          'have no data — skipping .ncnote persist but refreshing DB metadata');
      _sync.pendingPulledLocalSave = _persistPulledMetaOnly(finalMeta);
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
    // actually writes.  `_sync.isPulling` tells us which case we're in.
    if (_sync.isPulling) {
      _sync.pendingPulledLocalSave = _savePulledChangesLocally(
        finalMeta, finalDoc, mergedPages, mergedAssets,
      );
    } else {
      _sync.pendingPulledLocalSave = _runPulledSaveLocked(
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
      final existingSize =
          s == null ? 0 : await fileService.looseStoreSize(metadata.id);
      await fileService.upsertNotebookMeta(
        id: metadata.id,
        title: metadata.title,
        remotePath: s?.remotePath ?? '',
        // Leave syncStatus as 'modified' so the next sync cycle will retry
        // the missing pages (synced would mask the incomplete state).
        etag: _sync.remoteMetaEtag,
        // Use now() — see _savePulledChangesLocally for the rationale:
        // the library's overwrite guard compares local_modified_at against
        // the root .ncnote's server mtime. If we stamp a server timestamp
        // here, the next library refresh sees "server newer" and trample
        // our pulled state.
        localModifiedAt: DateTime.now(),
        syncStatus: 'modified',
        fileSize: existingSize,
        coverColor: metadata.coverColor,
        coverStyle: metadata.coverStyle,
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
    final pulledSaveToken = await _sync.acquireLock();
    if (pulledSaveToken == null) return;
    try {
      await _savePulledChangesLocally(metadata, document, pages, assets);
    } finally {
      _sync.releaseLock(pulledSaveToken);
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
    // _sync.lastSyncedPages entry intact — overwriting with the current in-memory
    // page would hide legitimate local edits on unrelated pages.
    final newBaseline = Map<String, PageData>.from(_sync.lastSyncedPages);
    for (final conflict in s.pendingConflicts) {
      if (removedByDeletion.contains(conflict.fileName)) {
        newBaseline.remove(conflict.fileName);
        _sync.lastPageEtags.remove(conflict.fileName);
      } else if (resolutions[conflict.fileName] ?? true) {
        newBaseline.remove(conflict.fileName);
      } else {
        newBaseline[conflict.fileName] = updatedPages[conflict.fileName]!;
      }
    }
    _sync.lastSyncedPages = newBaseline;

    // A removed page may have left currentPageIndex past the end.
    final newIndex = updatedDoc.pages.isEmpty
        ? 0
        : s.currentPageIndex.clamp(0, updatedDoc.pages.length - 1);

    state = s.copyWith(
      undoStack: rebaseHistoryOnMerge(s.undoStack, s.pages, updatedPages),
      redoStack: rebaseHistoryOnMerge(s.redoStack, s.pages, updatedPages),
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
    // The rest of that pull (pages that didn't conflict, the repaired page
    // list) would have been applied silently without the conflict; leaving
    // it pending re-prompted "changes from another device" right after.
    if (state?.pendingRemoteChanges != null) acceptRemoteChanges();
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
    final newBaseline = Map<String, PageData>.from(_sync.lastSyncedPages);
    for (final conflict in s.pendingConflicts) {
      final live = s.pages[conflict.fileName];
      if (live != null) newBaseline[conflict.fileName] = live;
    }
    _sync.lastSyncedPages = newBaseline;
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


  /// Track an asset as dirty when added/modified (e.g. image paste/add).
  @override
  void markAssetDirty(String assetKey) {
    _sync.dirtyAssetKeys.add(assetKey);
    _save.dirtyAssetKeys.add(assetKey);
  }

  /// Build a ZIP from the pulled state and save it locally so changes
  /// survive close/reopen without re-downloading.
  ///
  /// PARTIAL saves are allowed: if the document references pages whose data
  /// hasn't been pulled yet, they're silently dropped from the stored ZIP
  /// AND from the stored document, so the library card stays accurate and
  /// the next pull will re-request them via the "missingLocally" branch of
  /// `_pullFromDelta`.  This replaces the old behaviour that REFUSED
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

    // Only what the store lacks, like save(): rebuilding and rewriting the
    // whole notebook on every pull cost hundreds of MB of disk writes on a
    // large one. Queued with the editor's own local writes.
    await _save.withLocalLock(() =>
        _savePulledIncremental(persistedMeta, persistedDoc, pages, assets));
    // Edits made after the merge are newer than what was just written.
    _save.persistLocalIfBehind();
  }

  /// Writes only the pulled pages and assets the local store doesn't hold yet,
  /// the same way save() persists edits.
  Future<void> _savePulledIncremental(
    NotebookMetadata metadata,
    DocumentStructure document,
    Map<String, PageData> pages,
    Map<String, Uint8List> assets,
  ) async {
    try {
      final fileService = _ref.read(fileServiceProvider);
      final id = metadata.id;
      final hasStore = await fileService.hasLooseStore(id);
      final toWrite = <String, PageData>{
        for (final e in pages.entries)
          if (!hasStore || !identical(_save.storedPages[e.key], e.value))
            e.key: e.value,
      };
      final newAssets = <String, Uint8List>{
        for (final e in assets.entries)
          if (!hasStore || !_save.storedAssets.contains(e.key)) e.key: e.value,
      };
      final docFiles = document.pages.map((e) => e.fileName).toSet();
      final deleted = [
        for (final fn in _save.storedPages.keys)
          if (!pages.containsKey(fn) && !docFiles.contains(fn)) fn,
      ];
      final symbols = state?.symbolLibraries ?? const <SymbolLibrary>[];
      final encoded = await _encodePagesWithCache(toWrite, evictMissing: false);
      await fileService.saveNotebookIncremental(
        id,
        metadataJson:
            Uint8List.fromList(utf8.encode(jsonEncode(metadata.toJson()))),
        documentJson:
            Uint8List.fromList(utf8.encode(jsonEncode(document.toJson()))),
        changedPages: encoded,
        changedAssets: newAssets,
        deletedPages: deleted,
        symbolsJson: symbols.isNotEmpty
            ? Uint8List.fromList(utf8.encode(
                jsonEncode(symbols.map((l) => l.toJson()).toList())))
            : null,
      );
      if (state?.metadata.id == id) {
        if (!hasStore) {
          _save.storedPages = {};
          _save.storedAssets = {};
        }
        _save.storedPages.addAll(toWrite);
        for (final fn in deleted) {
          _save.storedPages.remove(fn);
        }
        _save.storedAssets.addAll(newAssets.keys);
        _save.storedDoc = document;
        _save.storedMeta = metadata;
        _save.storedSymbols = state?.symbolLibraries;
      }
      await fileService.upsertNotebookMeta(
        id: id,
        title: metadata.title,
        remotePath: state?.remotePath ?? '',
        etag: _sync.remoteMetaEtag,
        localModifiedAt: DateTime.now(),
        syncStatus: 'synced',
        fileSize: await fileService.looseStoreSize(id),
        coverColor: metadata.coverColor,
        coverStyle: metadata.coverStyle,
        paperType: metadata.paperType,
        pageCount: metadata.pageCount,
        createdAt: metadata.createdAt,
      );
      // A sketch edited elsewhere: its library preview shows this device's copy.
      final live = state;
      if (!kIsWeb &&
          live != null &&
          live.metadata.id == id &&
          metadata.paperType == AppConfig.infinitePaperType &&
          document.pages.isNotEmpty &&
          toWrite.containsKey(document.pages.first.fileName)) {
        _thumbnails.refresh(live, id);
      }
      print('[Canvas] Saved pulled changes locally (incremental): '
          '${encoded.length} pages, ${newAssets.length} assets, '
          '${deleted.length} deleted');
    } catch (e) {
      print('[Canvas] Failed to save pulled changes locally: $e');
      unawaited(CrashLogger.append('[Pull] local save of pulled pages FAILED: $e'));
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
      final bytes = encodePageBytes(entry.value);
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

/// Tiny record tying cached encoded bytes to the exact [PageData] instance
/// they were produced from. Identity check (`identical`) is enough because
/// [PageData] is a freezed/immutable model.
class _CachedPageJson {
  final PageData page;
  final Uint8List bytes;
  const _CachedPageJson(this.page, this.bytes);
}
