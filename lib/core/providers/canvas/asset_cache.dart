import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:abelnotes/core/platform/device_class.dart';
import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart' show syncServiceProvider;
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/features/canvas/data/math_rasterizer.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Decoded-image window and LRU cache, typeset-math raster cache and the
/// corrupt/heal/loading asset sets. Pixels only: asset bytes live in CanvasState.
class AssetCache {
  AssetCache(this._core);

  final CanvasCore _core;

  CanvasState? get state => _core.state;
  set state(CanvasState? v) => _core.state = v;

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
      if (_core.isDisposed) {
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
    if (_core.isDisposed) {
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

  // Web on a tablet counts as mobile: Safari's per-tab memory ceiling is
  // tighter than the native app's, so it gets the small caches too.
  static bool get _isMobilePlatform =>
      isWebTouchDevice ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
  static int get assetWindow =>
      _isMobilePlatform ? _mobileAssetWindow : _desktopAssetWindow;
  static int get imageCacheMax =>
      _isMobilePlatform ? _mobileImageCacheMax : _desktopImageCacheMax;

  /// Access-time map for LRU tracking. Key: assetId, value: monotonic
  /// counter written when an image is cached or read.
  final Map<String, int> _imageAccessTime = {};
  int _accessClock = 0;

  void _touch(String assetId) => _imageAccessTime[assetId] = ++_accessClock;

  /// Compute the union of asset refs across pages in [center ± radius].
  Set<String> refsForWindow(
      int center, int radius, DocumentStructure doc, Map<String, PageData> pages) {
    final lo = (center - radius).clamp(0, doc.pages.length - 1);
    final hi = (center + radius).clamp(0, doc.pages.length - 1);
    final refs = <String>{};
    for (var i = lo; i <= hi; i++) {
      refs.addAll(refsForPage(i, doc, pages));
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
  void ensureForCurrentWindow() {
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
    final needed = refsForWindow(
        s.currentPageIndex, assetWindow, s.document, s.pages);
    // Decode missing ones that we already have bytes for.
    for (final ref in needed) {
      if (s.imageCache.containsKey(ref)) {
        _touch(ref);
        continue;
      }
      final bytes = s.assetBytes[ref];
      if (bytes != null) {
        unawaited(decodeAndCache(ref, bytes));
      }
    }
    evictDistantImages();
  }

  /// LRU-evict from imageCache when it grows beyond the platform cap.
  /// Prefers to drop assets NOT referenced by pages in the current window.
  void evictDistantImages() {
    final s = state;
    if (s == null) return;
    if (s.imageCache.length <= imageCacheMax) return;
    final protect = refsForWindow(
        s.currentPageIndex, assetWindow, s.document, s.pages);
    // Candidates: everything not in the window. Sort oldest first.
    final candidates = s.imageCache.keys
        .where((k) => !protect.contains(k))
        .toList()
      ..sort((a, b) =>
          (_imageAccessTime[a] ?? 0).compareTo(_imageAccessTime[b] ?? 0));
    final toEvict = s.imageCache.length - imageCacheMax;
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
      logMemoryStats('evict($evicted)');
    }
  }

  /// Log a one-line memory snapshot on mobile so we can tell, from the
  /// crash log after a jetsam kill, roughly how big the caches had grown.
  void logMemoryStats(String context) {
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
  Set<String> refsForPage(
      int pageIdx, DocumentStructure doc, Map<String, PageData> pages) {
    if (pageIdx < 0 || pageIdx >= doc.pages.length) return {};
    final entry = doc.pages[pageIdx];
    final page = pages[entry.fileName];
    if (page == null) return {};
    final refs = <String>{...page.assetReferences};
    for (final el in page.layers.content) {
      el.map(unknown: (_) {},
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

  /// Sequentially decodes [assets] that are NOT in [skip], waiting for each
  /// to finish and yielding a ~16 ms frame gap between them so the UI stays
  /// responsive and memory pressure stays bounded.
  Future<void> decodeThrottled(
      Map<String, Uint8List> assets, {required Set<String> skip}) async {
    for (final entry in assets.entries) {
      if (_core.isDisposed) return;
      if (skip.contains(entry.key)) continue;
      await decodeAndCache(entry.key, entry.value);
      // Yield one frame between images so we don't spike memory or block
      // the raster thread for longer than a single vsync interval.
      await Future.delayed(const Duration(milliseconds: 16));
    }
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
    if (s.imageCache.containsKey(assetId)) {
      _touch(assetId);
      return;
    }
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
        await decodeAndCache(assetId, bytes);
      } finally {
        _onDemandDecodeQueued.remove(assetId);
      }
    }();
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
  /// remove the corrupt flag. Called from [decodeAndCache]'s
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
      final syncService = _core.ref.read(syncServiceProvider);
      if (syncService == null) {
        _markMissingAsCorrupt(assetId);
        return;
      }
      final fresh = await syncService.downloadDeltaAsset(
          ownerNotebookId, assetId);
      if (_core.isDisposed ||
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
      await decodeAndCache(assetId, fresh);
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
    if (_core.isDisposed || state == null) return;
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
      final syncService = _core.ref.read(syncServiceProvider);
      if (syncService == null) return;
      final fresh = await syncService.downloadDeltaAsset(
          ownerNotebookId, assetId);
      if (_core.isDisposed ||
          state == null ||
          state!.metadata.id != ownerNotebookId) {
        return;
      }
      final existing = state!.assetBytes[assetId];
      if (existing != null &&
          existing.length == fresh.length &&
          bytesEqual(existing, fresh)) {
        // Same corrupt bytes — server still poisoned. Remember persistently
        // so we don't burn another GET on this asset next app launch (the
        // proactive sweep + lazy heal both consult _healAttempted, which is
        // pre-seeded from this set on open).
        if (_knownIncurableAssets.add(assetId)) {
          unawaited(_persistIncurable(ownerNotebookId));
        }
        return;
      }
      // New bytes — replace and retry decode. decodeAndCache
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
      await decodeAndCache(assetId, fresh);
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
  /// The lazy heal in [decodeAndCache] only fires for assets the user
  /// actually views; this sweep covers assets on pages they never open, so a
  /// notebook fully self-heals in the background. Each fetch is throttled via
  /// [_healAttempted] (once per asset per session) and [_healCorruptAsset]
  /// replaces bytes only when the server copy actually differs — so a clean
  /// asset that happens to be 1024-aligned costs one harmless PROPFIND/GET and
  /// nothing else. Capped so a false-positive-heavy notebook can't trigger a
  /// fetch storm; the rest still heal lazily on view.
  void recoverTruncatedFromServer() {
    final s = state;
    if (s == null) return;
    if (_core.ref.read(syncServiceProvider) == null) return; // offline → skip
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

  static bool bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// AssetIds whose decode is currently in flight. Used to prevent two
  /// parallel decodes from racing — priority loop and background loop can
  /// both fire `decodeAndCache(assetId, bytes)` for the same id, and
  /// the second decode's writeback would otherwise overwrite the first
  /// without disposing the orphaned ui.Image (silent GPU-memory leak).
  final Set<String> _decodingInFlight = <String>{};

  Future<void> decodeAndCache(String assetId, Uint8List bytes) async {
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
      if (_core.isDisposed ||
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
      _touch(assetId);
      // Recovered from a previous corruption attempt — clear the flag
      // so the warning indicator goes away.
      _corruptAssetIds.remove(assetId);
      // If this was on the persisted incurable list (e.g. an earlier session
      // confirmed the server was poisoned), drop it now — the asset clearly
      // decodes, so future sessions should try to heal it again normally.
      if (_knownIncurableAssets.remove(assetId)) {
        unawaited(_persistIncurable(ownerNotebookId));
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

  /// Asset ids whose decode failed AND whose server copy was confirmed to be
  /// the same poisoned bytes (the 1024-aligned truncation incident). Persisted
  /// across sessions so a notebook with permanently-truncated server assets
  /// doesn't waste ~N GETs on every app launch re-attempting to heal them.
  /// Cleared when a successful decode for the same id arrives (e.g. the
  /// ZIP-aware recovery tool replaced the bytes), so genuine recoveries pick
  /// up automatically. Kept in sync with [_healAttempted] (pre-seeds it on
  /// open) so the proactive sweep AND the lazy decode path both skip.
  final Set<String> _knownIncurableAssets = <String>{};

  static String _incurableAssetsPrefsKey(String nbId) =>
      'incurable_assets_$nbId';

  Future<void> loadIncurable(String notebookId) async {
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

  Future<void> _persistIncurable(String notebookId) async {
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


  /// A notebook opened: forget the last one's heal state, load its incurable ids.
  void resetOnOpen(String notebookId) {
    _knownIncurableAssets.clear();
    _healAttempted.clear();
    unawaited(loadIncurable(notebookId));
  }

  /// A notebook closed. The corrupt-asset blocklist is stale once it is: a
  /// reload that replaces the bytes must retry the decode, not keep the badge.
  void resetOnClose() {
    _knownIncurableAssets.clear();
    _healAttempted.clear();
    _corruptAssetIds.clear();
    _onDemandDecodeQueued.clear();
  }

  /// An orphaned asset left the document: drop its transient flags.
  void forgetOrphan(String id) {
    _imageAccessTime.remove(id);
    _corruptAssetIds.remove(id);
    _onDemandDecodeQueued.remove(id);
  }

  /// Same for an image that only ever lived in the cache (deleted symbol).
  void forgetCacheOnlyOrphan(String id) {
    _imageAccessTime.remove(id);
    _corruptAssetIds.remove(id);
  }

  /// Dispose every GPU-backed image texture held in state.imageCache.
  /// Must run before the engine shuts down, or the Linux build segfaults on
  /// close with native ui.Image handles still alive. Called on `detached`.
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

  /// Frees the textures and notifiers with the notifier.
  void dispose() {
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
    try { imageCacheVersion.dispose(); } catch (_) {}
    try { mathCacheVersion.dispose(); } catch (_) {}
  }
}
