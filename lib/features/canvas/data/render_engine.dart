import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/data/math_rasterizer.dart';
import 'package:abelnotes/features/canvas/data/text_paragraph_factory.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// High-performance canvas render engine.
/// Handles all rendering including zoom/pan transform internally.
class CanvasRenderEngine extends CustomPainter {
  /// Effective page-units→pixels factor of the current paint pass (zoom ×
  /// fit scale). Set at the top of [paint]/[paintPage]; lets the background
  /// pattern painters skip sub-pixel patterns (thumbnail moiré + cost).
  double _bgPatternScale = 1.0;

  final PageData pageData;
  final List<StrokePoint>? activeStroke;
  /// Optional dynamic provider for the active stroke. When non-null,
  /// paint() calls it on every frame to fetch the CURRENT live points
  /// (typically from a ChangeNotifier) instead of using the snapshot
  /// captured in [activeStroke] at widget build time. This is the
  /// same fix pattern as [liveLassoTransform]: avoids the painter
  /// rendering a stale empty/old buffer when the live notifier has
  /// already moved on to a new stroke and the wrapper widget hasn't
  /// rebuilt yet (the bug where a fresh stroke appeared to start at
  /// the previous stroke's end-point and "stretch" to where the user
  /// actually wrote).
  final List<StrokePoint>? Function()? activeStrokeGetter;
  final String? activeToolType;
  final int? activeColor;
  final double? activeWidth;
  final LassoSelection? lassoSelection;
  /// Optional live override for the lasso transform (drag/rotate/scale).
  /// The callback returns the current values each frame, or `null` when
  /// no gesture is in flight — that way the painter never needs the
  /// widget tree to rebuild between "active" and "inactive" states; it
  /// just re-asks the callback. Used together with a repaintNotifier
  /// that ticks on the same source so the painter is invalidated at
  /// pointer rate.
  final ({Offset dragOffset, double rotation, double scale})? Function()?
      liveLassoTransform;
  /// Optional live override for a single non-lasso element being
  /// dragged / rotated / resized. Same callback contract as
  /// liveLassoTransform — returns null when no gesture is in flight.
  final ({
    String elementId,
    Offset dragOffset,
    double rotationDelta,
    double scaleW,
    double scaleH,
  })? Function()? liveElementTransform;
  final List<Offset>? lassoPath;
  final List<Offset> Function()? lassoPathGetter;
  /// Laser-pointer trail — list of (x, y, t-millis) tuples. The painter
  /// computes per-point opacity from `now − t` so the trail visually
  /// fades. Never written to disk; presentation only.
  final List<({double x, double y, int t, bool start})> Function()? laserTrailGetter;
  final (Offset, Offset, String)? shapePreview;
  final ShapeData? recognizedShapePreview;
  final double zoom;
  final Offset panOffset;
  /// Free-sketch (infinite canvas) mode. Uses a fixed 1:1 base scale (no
  /// fit-to-page shrink) and no fit-centering, and suppresses the A4 page
  /// shadow + border so the big sheet reads as an edgeless whiteboard. MUST
  /// mirror [CanvasScreen]'s `_getRenderScale`/`_getCenterOffset`.
  final bool infiniteCanvas;
  final Map<String, ui.Image> imageCache;
  /// Live-read access to the imageCache for callers that own a long-lived
  /// painter whose enclosing widget does NOT rebuild on cache updates (the
  /// main canvas Consumer intentionally doesn't `ref.watch` `s.imageCache`
  /// for perf — the page-manager grid does). Without this getter, when an
  /// asset finishes decoding the [repaintNotifier] fires `paint()` but the
  /// painter's `imageCache` field is still the snapshot captured at the last
  /// widget build, so the freshly decoded image is invisible until the user
  /// pans/zooms (forcing a widget rebuild). When non-null, `paint()` reads
  /// the live map from this getter on every frame.
  final Map<String, ui.Image> Function()? liveImageCacheGetter;
  /// Asset ids the provider has flagged as corrupt (decode failed or
  /// bytes missing on server). For picture-cache purposes treat these
  /// as "decoded": their placeholder will paint, no live update is
  /// expected, so the cached picture is stable. Without this set the
  /// _allImageAssetsDecoded() check would return false forever for any
  /// page with a single corrupt asset → cache never stored → every
  /// frame rebuilds the static layers (50-100× CPU regression).
  final Set<String> corruptAssetIds;

  // ── Typeset-math raster cache (mirrors the imageCache pair) ──
  /// LaTeX equations rasterized to ui.Images, keyed by [mathCacheKey].
  /// Built-time snapshot; [liveMathCacheGetter] gives the fresh view.
  final Map<String, MathRaster> mathCache;
  /// Live-read access to [mathCache] for the long-lived main painter — same
  /// rationale as [liveImageCacheGetter]: when a rasterize finishes the
  /// repaintNotifier fires but this field is the stale build-time snapshot.
  final Map<String, MathRaster> Function()? liveMathCacheGetter;
  /// Called from paint() on a math cache MISS so the owner can kick off an
  /// async rasterize that, when done, populates the cache and bumps the
  /// repaint notifier. Null for offscreen renders (export/thumbnail), which
  /// pre-rasterize into [mathCache] instead and draw the placeholder on miss.
  final void Function(MathData data)? onMathCacheMiss;
  /// Device-pixels-per-logical-pixel to rasterize math at this frame
  /// (devicePixelRatio × zoom, bucketed). Keeps equations crisp on zoom.
  final double mathPixelRatio;
  /// Cache keys whose rasterize permanently failed (no implicit view /
  /// pipeline error). Treated as "ready" for picture-cache purposes — same
  /// role as [corruptAssetIds] — so one bad equation can't block the static
  /// cache forever (every-frame re-record = sustained-core CPU on idle).
  final Set<String> failedMathKeys;

  /// Live imageCache the painter should use this frame — either the
  /// getter's current view (preferred when provided) or the build-time
  /// snapshot. Cheap: one nullable function call + map ref.
  Map<String, ui.Image> get _liveImageCache =>
      liveImageCacheGetter?.call() ?? imageCache;

  Map<String, MathRaster> get _liveMathCache =>
      liveMathCacheGetter?.call() ?? mathCache;

  CanvasRenderEngine({
    required this.pageData,
    this.activeStroke,
    this.activeStrokeGetter,
    this.activeToolType,
    this.activeColor,
    this.activeWidth,
    this.lassoSelection,
    this.liveLassoTransform,
    this.liveElementTransform,
    this.lassoPath,
    this.lassoPathGetter,
    this.laserTrailGetter,
    this.shapePreview,
    this.recognizedShapePreview,
    this.zoom = 1.0,
    this.panOffset = Offset.zero,
    this.infiniteCanvas = false,
    this.imageCache = const {},
    this.liveImageCacheGetter,
    this.corruptAssetIds = const <String>{},
    this.mathCache = const {},
    this.liveMathCacheGetter,
    this.onMathCacheMiss,
    this.mathPixelRatio = 3.0,
    this.failedMathKeys = const <String>{},
    Listenable? repaintNotifier,
  }) : super(repaint: repaintNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    // Scratch: fixed 1:1 scale, no fit-centering (panOffset positions the
    // big page). A4: fit the page and centre it. Keep this identical to
    // CanvasScreen._getRenderScale / _getCenterOffset.
    final scaleX = size.width / pageData.width;
    final scaleY = size.height / pageData.height;
    final baseScale = infiniteCanvas ? 1.0 : min(scaleX, scaleY);

    // Center the page in the canvas area
    final scaledW = pageData.width * baseScale;
    final scaledH = pageData.height * baseScale;
    final centerOffsetX = infiniteCanvas ? 0.0 : (size.width - scaledW) / 2;
    final centerOffsetY = infiniteCanvas ? 0.0 : (size.height - scaledH) / 2;

    canvas.save();

    // Apply pan + centering + zoom + base scale
    canvas.translate(
      panOffset.dx + centerOffsetX * zoom,
      panOffset.dy + centerOffsetY * zoom,
    );
    canvas.scale(zoom * baseScale);
    _bgPatternScale = zoom * baseScale;

    // Infinite/scratch: fill the WHOLE visible viewport with the paper +
    // texture every frame (uncached, pan-dependent) so there is no page
    // edge to pan into — it reads as a truly boundless whiteboard. Drawn
    // before the cached content picture (which, in infinite mode, carries
    // no background of its own).
    if (infiniteCanvas) {
      _paintInfiniteBackground(canvas, size);
    }

    // ── Static-content Picture cache ──
    //
    // Layers 0-3 (shadow, background, border, content) are *static* per
    // page — they never depend on activeStroke / lassoPath / preview /
    // selection drag, so the same drawing commands run identically on
    // every frame the user is at rest. With 200 strokes × ~80 points ×
    // adaptive Catmull-Rom interpolation (up to 24 segments), that's
    // ~400k drawLine calls per paint. Even a single repaint per second
    // saturates a CPU core.
    //
    // Cache the layered draw commands into a `ui.Picture` keyed on
    // (pageData identity, zoom-bucket, imageCache identity-set,
    // lassoSelection identity) and replay it. PictureRecorder builds
    // an opaque GPU command stream that drawPicture re-issues in
    // microseconds. Cache miss only happens when the page or zoom
    // changes meaningfully (zoom bucketed to 0.1 because the
    // adaptive-interpolation segment count is zoom-dependent —
    // recording at 1× and replaying at 4× would look polygonal).
    final lassoSel = lassoSelection;
    // selectedIdsSet is only consumed by the cache-rebuild / live-
    // transform paths (_paintStaticLayers needs it for selection
    // highlighting + transform target). On cache-hit we skip the
    // O(N) HashSet allocation entirely.
    Set<String>? lazySelectedIds;
    Set<String> selectedIdsSet() {
      if (lassoSel == null) return const <String>{};
      return lazySelectedIds ??= lassoSel.selectedIds.toSet();
    }
    // Resolve live transform override if present — bypasses Riverpod for
    // per-frame drag/rotate/scale updates.
    final liveTr = liveLassoTransform?.call();
    final selDragOffset = liveTr?.dragOffset ?? lassoSel?.dragOffset ?? Offset.zero;
    final selRotation = liveTr?.rotation ?? lassoSel?.rotation ?? 0.0;
    final selScale = liveTr?.scale ?? lassoSel?.scale ?? 1.0;
    final selCenter = lassoSel?.bounds.center ?? Offset.zero;
    final hasTransform = selDragOffset != Offset.zero ||
        selRotation != 0.0 ||
        selScale != 1.0;

    // Live override for a single (non-lasso) element being dragged or
    // rotated. When present, also bypass the picture cache because the
    // element moves every frame.
    final liveEl = liveElementTransform?.call();
    final hasLiveEl = liveEl != null &&
        (liveEl.dragOffset != Offset.zero ||
            liveEl.rotationDelta != 0.0 ||
            liveEl.scaleW != 1.0 ||
            liveEl.scaleH != 1.0);

    // While the lasso is being dragged/rotated/scaled OR a single
    // element is being live-transformed, bypass the cache and draw
    // inline so the moving element follows pointer at vsync.
    if (hasTransform || hasLiveEl) {
      _paintStaticLayers(
        canvas,
        selectedIdsSet(),
        selDragOffset,
        selRotation,
        selScale,
        selCenter,
        hasTransform,
        liveEl: liveEl,
      );
    } else {
      // Idle / non-drag path: cache or rebuild the FULL static layers
      // (strokes + images + shapes + text in zIndex order) into the
      // Picture. Previously we split images out and painted them via
      // _paintImagesOnly AFTER the cached picture — that always put
      // images on top of strokes, ignoring zIndex (so a stroke drawn
      // ON a PDF page rendered UNDER it). Including images in the
      // cache restores correct layering. To avoid baking placeholders
      // when assets are still decoding, we DON'T cache while any
      // referenced image lacks bytes — once decoded, the next frame
      // builds the cache and subsequent frames replay it.
      final allImagesReady = _allImageAssetsDecoded();
      final imageSig = allImagesReady ? _pageImageSignature() : 0;
      final cached = allImagesReady
          ? _staticPictureCache.lookup(
              pageData: pageData,
              zoom: zoom,
              lassoSelection: lassoSel,
              imageSig: imageSig,
            )
          : null;
      if (cached != null) {
        canvas.drawPicture(cached);
      } else {
        final recorder = ui.PictureRecorder();
        final pictureCanvas = Canvas(recorder);
        _paintStaticLayers(
          pictureCanvas,
          selectedIdsSet(),
          selDragOffset,
          selRotation,
          selScale,
          selCenter,
          hasTransform,
        );
        final pic = recorder.endRecording();
        canvas.drawPicture(pic);
        if (allImagesReady) {
          _staticPictureCache.store(
            pageData: pageData,
            zoom: zoom,
            lassoSelection: lassoSel,
            imageSig: imageSig,
            picture: pic,
          );
        } else {
          // Discard immediately — re-record next frame so freshly
          // decoded images appear without waiting for an unrelated
          // pageData identity change.
          pic.dispose();
        }
      }
    }

    // 4. Active stroke being drawn — fetch live from the getter when
    // present so the painter never renders a snapshot the wrapper
    // widget captured at build time (the cause of the phantom-line
    // bug where a fresh stroke appeared to start at the previous
    // stroke's end-point).
    final liveActive = activeStrokeGetter?.call() ?? activeStroke;
    // isNotEmpty (was length >= 2): the first sample of every stroke
    // now previews immediately as a dot via _paintStroke's single-
    // point branch — no more 16-32 ms dead time on PointerDown, and
    // a tap-to-dot is visible during the gesture instead of only
    // appearing at lift.
    if (liveActive != null && liveActive.isNotEmpty) {
      _paintStroke(canvas, StrokeData(
        points: liveActive,
        toolType: activeToolType ?? 'pen',
        color: activeColor ?? 0xFF000000,
        baseWidth: activeWidth ?? AppConfig.defaultStrokeWidth,
      ));
    }

    // 5. Shape preview
    if (shapePreview != null) {
      _paintShapePreview(canvas, shapePreview!);
    }

    // 5b. Recognized shape preview (interactive adjustment)
    if (recognizedShapePreview != null) {
      _paintRecognizedShapePreview(canvas, recognizedShapePreview!);
    }

    // 6. Lasso path — read live from getter if available
    final currentLassoPath = lassoPathGetter?.call() ?? lassoPath;
    if (currentLassoPath != null && currentLassoPath.length >= 2) {
      _paintLassoPathFromPoints(canvas, currentLassoPath);
    }

    // 6b. Laser pointer trail — fades over LaserStrokeNotifier.trailMs.
    final laserPts = laserTrailGetter?.call();
    if (laserPts != null && laserPts.isNotEmpty) {
      _paintLaserTrail(canvas, laserPts);
    }

    // 7. Lasso selection bounds — pass through the resolved live
    // transform so the dashed marquee follows the moving content
    // during drag/rotate/scale instead of staying pinned at start.
    if (lassoSelection != null) {
      _paintSelectionBounds(
        canvas,
        liveDragOffset: selDragOffset,
        liveRotation: selRotation,
        liveScale: selScale,
      );
    }

    canvas.restore();
  }

  /// Layers 0-3 of [paint]: shadow, background, border, content. Recorded
  /// into a `ui.Picture` once per (pageData, zoom-bucket, lassoSelection)
  /// and replayed by subsequent paint calls — see [_staticPictureCache].
  /// Images are baked into the cached picture at their proper zIndex
  /// (no live update path), so the cache lookup is gated on
  /// [_allImageAssetsDecoded] — corrupt assets count as decoded so a
  /// single broken PNG doesn't permanently disable the cache.
  void _paintStaticLayers(
    Canvas canvas,
    Set<String> selectedIdsSet,
    Offset selDragOffset,
    double selRotation,
    double selScale,
    Offset selCenter,
    bool hasTransform, {
    ({
      String elementId,
      Offset dragOffset,
      double rotationDelta,
      double scaleW,
      double scaleH,
    })? liveEl,
  }) {
    // 0. Page shadow — three flat offset rects of decreasing alpha.
    // Replaces a `MaskFilter.blur(sigma:8)` Gaussian which Skia
    // re-rasterises every layer invalidation (60 Hz during eraser =
    // ~525 k pixel × kernel ops/frame). Three flat fills look almost
    // identical at normal zoom but cost ~100× less per frame.
    // Skipped in infinite/scratch mode — an edgeless whiteboard has no
    // sheet to cast a shadow or draw a border around.
    if (!infiniteCanvas) {
      final shadowOuter = Paint()..color = const Color(0x14000000);
      final shadowMid = Paint()..color = const Color(0x1F000000);
      final shadowInner = Paint()..color = const Color(0x29000000);
      final w = pageData.width, h = pageData.height;
      canvas.drawRect(Rect.fromLTWH(5, 5, w, h), shadowOuter);
      canvas.drawRect(Rect.fromLTWH(3.5, 3.5, w, h), shadowMid);
      canvas.drawRect(Rect.fromLTWH(2, 2, w, h), shadowInner);
    }

    // 1. Page background (white rect)
    _paintBackground(canvas, pageData.layers.background);

    // 2. Page border
    if (!infiniteCanvas) _paintPageBorder(canvas);

    // 3. Content elements (cached sort to avoid O(n log n) per frame)
    final sortedContent = _getSortedContent(pageData.layers.content);

    for (final element in sortedContent) {
      // Type-discriminate via `is` (zero-alloc) instead of `.map(...)`
      // — the freezed-generated `map(stroke:..., text:..., image:..., shape:...)`
      // allocates 4 closure objects per call. With 200 elements × 2
      // closure-quartets per iteration that was 1 600 needless
      // allocations per cache-miss frame, all immediately dead.
      final String id;
      if (element is StrokeElement) {
        id = element.id;
      } else if (element is TextElement) {
        id = element.id;
      } else if (element is ImageElement) {
        id = element.id;
      } else if (element is ShapeElement) {
        id = element.id;
      } else {
        id = (element as MathElement).id;
      }
      final isSelected = selectedIdsSet.contains(id);

      final isLiveTarget = liveEl != null && liveEl.elementId == id;

      // If this element is being moved/rotated/scaled via lasso, apply transform
      if (isSelected && hasTransform) {
        canvas.save();
        canvas.translate(selDragOffset.dx, selDragOffset.dy);
        canvas.translate(selCenter.dx, selCenter.dy);
        if (selScale != 1.0) {
          canvas.scale(selScale);
        }
        if (selRotation != 0.0) {
          canvas.rotate(selRotation);
        }
        canvas.translate(-selCenter.dx, -selCenter.dy);
      }
      // Single-element live transform (drag/rotate/resize via image handles).
      if (isLiveTarget) {
        canvas.save();
        canvas.translate(liveEl.dragOffset.dx, liveEl.dragOffset.dy);
        // Anchor: rotation pivots around the element's CENTER, but
        // scale must pivot around its TOP-LEFT to match the resize
        // handle's math (newBounds = orig.tl + (sw*W, sh*H), where the
        // handle keeps top-left fixed and the dragOffset captures any
        // top/left edge displacement). Using center as the scale anchor
        // (the prior behaviour) made the image grow symmetrically from
        // the centre while the handle tracked top-left → image visually
        // drifted off the handle frame as the user dragged. Choose the
        // anchor based on which transform is active; for the typical
        // "drag a corner" gesture this is scale-only, so top-left
        // anchor applies and the image sticks to the handles.
        final hasScale = liveEl.scaleW != 1.0 || liveEl.scaleH != 1.0;
        final hasRotation = liveEl.rotationDelta != 0.0;
        if (hasRotation) {
          final c = _elementCenter(element);
          canvas.translate(c.dx, c.dy);
          canvas.rotate(liveEl.rotationDelta);
          canvas.translate(-c.dx, -c.dy);
        }
        // Text is a reflow FRAME, not a bitmap: a canvas.scale here would
        // stretch the glyphs during the drag and then visibly snap back
        // to normal on release (resizeTextElement reflows at the new
        // width instead of scaling). Skip the geometric scale for text
        // and instead re-lay-out the paragraph at the live width below —
        // dragOffset is already applied above, unconditionally.
        if (hasScale && element is! TextElement) {
          final tl = _elementTopLeft(element);
          canvas.translate(tl.dx, tl.dy);
          canvas.scale(liveEl.scaleW, liveEl.scaleH);
          canvas.translate(-tl.dx, -tl.dy);
        }
      }

      element.map(
        stroke: (e) => _paintStroke(canvas, e.data),
        text: (e) {
          if (isLiveTarget && liveEl.scaleW != 1.0) {
            _paintText(canvas, e.data, widthOverride: e.data.width * liveEl.scaleW);
          } else {
            _paintText(canvas, e.data);
          }
        },
        image: (e) => _paintImage(canvas, e.data),
        shape: (e) => _paintShape(canvas, e.data),
        math: (e) => _paintMath(canvas, e.data),
      );

      if (isLiveTarget) canvas.restore();
      if (isSelected && hasTransform) {
        canvas.restore();
      }
    }
  }

  /// Geometric center of an element on the page (used as the rotation /
  /// scale anchor for the single-element live transform). Hot-path:
  /// called every paint frame during a drag/rotate. Use is-checks
  /// (zero-alloc) instead of `.map(...)` (4 closures per call).
  Offset _elementCenter(ContentElement element) {
    if (element is StrokeElement) {
      final pts = element.data.points;
      if (pts.isEmpty) return Offset.zero;
      double minX = pts.first.x, maxX = minX;
      double minY = pts.first.y, maxY = minY;
      for (final p in pts) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
      return Offset((minX + maxX) / 2, (minY + maxY) / 2);
    } else if (element is TextElement) {
      final t = element.data;
      return Offset(t.x + t.width / 2, t.y + t.height / 2);
    } else if (element is ImageElement) {
      final i = element.data;
      return Offset(i.x + i.width / 2, i.y + i.height / 2);
    } else if (element is MathElement) {
      final m = element.data;
      return Offset(m.x + m.width / 2, m.y + m.height / 2);
    } else {
      final s = (element as ShapeElement).data;
      return Offset((s.x1 + s.x2) / 2, (s.y1 + s.y2) / 2);
    }
  }

  /// Top-left corner of an element on the page. Used as the scale anchor
  /// for live resize so the rendered shape keeps its top-left at
  /// element.tl + dragOffset (matching the resize handle's bbox math).
  Offset _elementTopLeft(ContentElement element) {
    if (element is StrokeElement) {
      final pts = element.data.points;
      if (pts.isEmpty) return Offset.zero;
      double minX = pts.first.x;
      double minY = pts.first.y;
      for (final p in pts) {
        if (p.x < minX) minX = p.x;
        if (p.y < minY) minY = p.y;
      }
      return Offset(minX, minY);
    } else if (element is TextElement) {
      return Offset(element.data.x, element.data.y);
    } else if (element is ImageElement) {
      return Offset(element.data.x, element.data.y);
    } else if (element is MathElement) {
      return Offset(element.data.x, element.data.y);
    } else {
      final s = (element as ShapeElement).data;
      return Offset(min(s.x1, s.x2), min(s.y1, s.y2));
    }
  }

  /// Paint the page content without zoom/pan transform.
  /// Used for export (PNG/PDF).
  void paintPage(Canvas canvas, Size size, double scale, Offset offset) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    _bgPatternScale = scale;

    // Background
    _paintBackground(canvas, pageData.layers.background);

    // Content
    final sortedContent = List<ContentElement>.from(pageData.layers.content)
      ..sort((a, b) {
        final aZ = a.map(stroke: (s) => s.zIndex, text: (t) => t.zIndex, image: (i) => i.zIndex, shape: (s) => s.zIndex, math: (m) => m.zIndex);
        final bZ = b.map(stroke: (s) => s.zIndex, text: (t) => t.zIndex, image: (i) => i.zIndex, shape: (s) => s.zIndex, math: (m) => m.zIndex);
        return aZ.compareTo(bZ);
      });

    for (final element in sortedContent) {
      element.map(
        stroke: (e) => _paintStroke(canvas, e.data),
        text: (e) => _paintText(canvas, e.data),
        image: (e) => _paintImage(canvas, e.data),
        shape: (e) => _paintShape(canvas, e.data),
        math: (e) => _paintMath(canvas, e.data),
      );
    }

    canvas.restore();
  }

  void _paintPageBorder(Canvas canvas) {
    final borderPaint = Paint()
      ..color = const Color(0xFFD0D0D0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(Rect.fromLTWH(0, 0, pageData.width, pageData.height), borderPaint);
  }

  void _paintBackground(Canvas canvas, BackgroundLayer bg) {
    // Infinite canvas draws its background separately, tiled across the
    // live viewport (see [_paintInfiniteBackground]). Skip the bounded
    // A4-rect fill so no page edge is ever recorded into the cache.
    if (infiniteCanvas) return;

    final bgPaint = Paint()..color = Color(bg.color);
    canvas.drawRect(Rect.fromLTWH(0, 0, pageData.width, pageData.height), bgPaint);

    // At tiny render scales (page-manager thumbnails of big scratch pages)
    // the pattern collapses below pixel size into blurry moiré mush and
    // costs tens of thousands of draw ops per thumbnail (a 6000×6000
    // dotted sheet is ~58k dots) — plain paper reads better and paints
    // instantly.
    final patternSpacing = bg.lineSpacing > 0 ? bg.lineSpacing : 25.0;
    if (patternSpacing * _bgPatternScale < 3.0) return;

    final linePaint = Paint()
      ..color = Color(bg.lineColor)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    switch (bg.type) {
      case 'lined':
      case 'lined_wide':
        _paintLinedBackground(canvas, bg.lineSpacing > 0 ? bg.lineSpacing : 35.0, linePaint, showMargin: true);
        break;
      case 'lined_narrow':
        _paintLinedBackground(canvas, bg.lineSpacing > 0 ? bg.lineSpacing : 20.0, linePaint, showMargin: false);
        break;
      case 'grid':
        _paintGridBackground(canvas, bg.lineSpacing > 0 ? bg.lineSpacing : 25.0, linePaint);
        break;
      case 'dotted':
        _paintDottedBackground(canvas, bg.lineSpacing > 0 ? bg.lineSpacing : 25.0, linePaint);
        break;
      case 'cornell':
        _paintCornellBackground(canvas, bg.lineSpacing > 0 ? bg.lineSpacing : 25.0, linePaint);
        break;
      case 'isometric':
        _paintIsometricBackground(canvas, bg.lineSpacing > 0 ? bg.lineSpacing : 30.0, linePaint);
        break;
      case 'music':
        _paintMusicBackground(canvas, bg.lineSpacing > 0 ? bg.lineSpacing : 8.0, linePaint);
        break;
    }
  }

  /// Infinite/scratch background: paper fill + optional texture tiled across
  /// the currently-visible page region only. Called every frame with the live
  /// pan/zoom so the sheet has no edge — panning anywhere always shows more
  /// paper. Cheap: only the visible ~viewport of dots/lines is emitted, in a
  /// single batched draw where possible. Runs on the transformed canvas
  /// (page space), so `spacing` and stroke widths scale with zoom just like
  /// the A4 textures.
  void _paintInfiniteBackground(Canvas canvas, Size size) {
    final bg = pageData.layers.background;
    if (zoom <= 0) return;
    // Transform in infinite mode is: screen = panOffset + P * zoom
    // (baseScale 1, no centering). Invert the four screen corners to get
    // the visible page-space rectangle.
    final visible = Rect.fromLTRB(
      -panOffset.dx / zoom,
      -panOffset.dy / zoom,
      (size.width - panOffset.dx) / zoom,
      (size.height - panOffset.dy) / zoom,
    );

    // Paper fill — inflate slightly so a sub-pixel seam never shows.
    canvas.drawRect(visible.inflate(2), Paint()..color = Color(bg.color));

    final spacing = bg.lineSpacing > 0 ? bg.lineSpacing : 25.0;
    final linePaint = Paint()
      ..color = Color(bg.lineColor)
      // Same anti-alias clamp as the dots: never let a grid/ruled line go
      // below ~0.6 physical px or it flickers with the pixel grid.
      ..strokeWidth = max(0.8, 0.6 / zoom)
      ..style = PaintingStyle.stroke;

    switch (bg.type) {
      case 'grid':
        for (double x = _snapDown(visible.left, spacing);
            x <= visible.right; x += spacing) {
          canvas.drawLine(
              Offset(x, visible.top), Offset(x, visible.bottom), linePaint);
        }
        for (double y = _snapDown(visible.top, spacing);
            y <= visible.bottom; y += spacing) {
          canvas.drawLine(
              Offset(visible.left, y), Offset(visible.right, y), linePaint);
        }
        break;
      case 'dotted':
        // Keep the dot at least ~1.4 physical px once zoom shrinks it
        // below that: a sub-pixel round point aliases in and out of
        // existence depending on where it lands on the pixel grid (dots
        // "disappearing at some zoom percentages"). Clamp in page units.
        final dotWidth = max(3.0, 1.4 / zoom);
        // Zoomed out so far that dots would blur into solid gray (and the
        // visible rect would need millions of points): plain paper.
        if (spacing * zoom < 2.5) break;
        final dotPaint = Paint()
          ..color = Color(bg.lineColor)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = dotWidth;
        final pts = <Offset>[];
        for (double y = _snapDown(visible.top, spacing);
            y <= visible.bottom; y += spacing) {
          for (double x = _snapDown(visible.left, spacing);
              x <= visible.right; x += spacing) {
            pts.add(Offset(x, y));
          }
        }
        if (pts.isNotEmpty) {
          canvas.drawPoints(ui.PointMode.points, pts, dotPaint);
        }
        break;
      case 'lined':
      case 'lined_wide':
      case 'lined_narrow':
        for (double y = _snapDown(visible.top, spacing);
            y <= visible.bottom; y += spacing) {
          canvas.drawLine(
              Offset(visible.left, y), Offset(visible.right, y), linePaint);
        }
        break;
      // 'blank' (and anything unmapped) → just the paper fill.
    }
  }

  /// Largest multiple of [step] that is <= [v] — snaps a tiling loop's start
  /// to the grid so lines/dots stay put as the viewport pans.
  double _snapDown(double v, double step) => (v / step).floorToDouble() * step;

  void _paintLinedBackground(Canvas canvas, double spacing, Paint paint, {required bool showMargin}) {
    if (showMargin) {
      final marginPaint = Paint()
        ..color = const Color(0xFFE8B4B8)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      canvas.drawLine(const Offset(60, 0), Offset(60, pageData.height), marginPaint);
    }
    for (double y = spacing; y < pageData.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(pageData.width, y), paint);
    }
  }

  void _paintGridBackground(Canvas canvas, double spacing, Paint paint) {
    for (double y = spacing; y < pageData.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(pageData.width, y), paint);
    }
    for (double x = spacing; x < pageData.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, pageData.height), paint);
    }
  }

  void _paintDottedBackground(Canvas canvas, double spacing, Paint paint) {
    // Use drawPoints(points) instead of per-dot drawCircle(). On an A4
    // portrait page with spacing=25 this issues ~2500 draw calls per
    // paint frame; drawPoints batches them into a single Skia op.
    // Visual match: a round-capped stroke of width=diameter produces
    // the same dot as a filled circle of radius=diameter/2.
    final dotPaint = Paint()
      ..color = Color(pageData.layers.background.lineColor)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0; // matches previous radius 1.5
    final offsets = <Offset>[];
    for (double y = spacing; y < pageData.height; y += spacing) {
      for (double x = spacing; x < pageData.width; x += spacing) {
        offsets.add(Offset(x, y));
      }
    }
    if (offsets.isNotEmpty) {
      canvas.drawPoints(ui.PointMode.points, offsets, dotPaint);
    }
  }

  void _paintCornellBackground(Canvas canvas, double spacing, Paint paint) {
    // Cornell notes: horizontal lines + left margin (cue column) + bottom summary area
    final w = pageData.width;
    final h = pageData.height;
    const cueWidth = 120.0;
    const summaryHeight = 140.0;

    // Horizontal lines in note-taking area
    for (double y = spacing + 50; y < h - summaryHeight; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(w, y), paint);
    }

    // Vertical cue column line
    final cuePaint = Paint()
      ..color = const Color(0xFFE8B4B8)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(cueWidth, 0), Offset(cueWidth, h - summaryHeight), cuePaint);

    // Horizontal summary separator
    canvas.drawLine(Offset(0, h - summaryHeight), Offset(w, h - summaryHeight), cuePaint);

    // Title area separator at top
    final titlePaint = Paint()
      ..color = const Color(0xFFB0B0B0)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(0, 50), Offset(w, 50), titlePaint);
  }

  void _paintIsometricBackground(Canvas canvas, double spacing, Paint paint) {
    final w = pageData.width;
    final h = pageData.height;
    final isoHeight = spacing * sqrt(3) / 2;

    // Horizontal rows of triangles
    for (double y = 0; y < h + isoHeight; y += isoHeight) {
      // Horizontal line
      canvas.drawLine(Offset(0, y), Offset(w, y), paint);
    }
    // Diagonal lines (/)
    for (double x = -h; x < w + spacing; x += spacing) {
      canvas.drawLine(
        Offset(x, h),
        Offset(x + h / tan(pi / 3), 0),
        paint,
      );
    }
    // Diagonal lines (\)
    for (double x = 0; x < w + h; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x - h / tan(pi / 3), h),
        paint,
      );
    }
  }

  void _paintMusicBackground(Canvas canvas, double spacing, Paint paint) {
    // Music staff: groups of 5 lines with larger gaps between staves
    final w = pageData.width;
    final h = pageData.height;
    const staffLines = 5;
    final staffGap = spacing * 4; // gap between staves
    double y = 60; // top margin

    while (y + staffLines * spacing < h - 40) {
      // Draw 5 lines (one staff)
      for (int i = 0; i < staffLines; i++) {
        canvas.drawLine(Offset(30, y + i * spacing), Offset(w - 30, y + i * spacing), paint);
      }
      y += staffLines * spacing + staffGap;
    }
  }

  /// Fill a variable-width ribbon along the given interpolated points.
  /// Extracted from the fountain-pen code so the calligraphy branch can
  /// share the same crisp-edge polygon fill.
  void _paintVariableWidthRibbon(
      Canvas canvas, List<_InterpolatedPoint> interp, Color fillColor) {
    final count = interp.length;
    if (count < 2) return;
    final nxArr = List<double>.filled(count, 0.0);
    final nyArr = List<double>.filled(count, 0.0);
    for (int i = 0; i < count; i++) {
      double dx, dy;
      if (i == 0) {
        dx = interp[1].x - interp[0].x;
        dy = interp[1].y - interp[0].y;
      } else if (i == count - 1) {
        dx = interp[i].x - interp[i - 1].x;
        dy = interp[i].y - interp[i - 1].y;
      } else {
        dx = interp[i + 1].x - interp[i - 1].x;
        dy = interp[i + 1].y - interp[i - 1].y;
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
    final hw0 = (interp[0].w * 0.5).clamp(0.2, 999.0);
    path.moveTo(interp[0].x + nxArr[0] * hw0, interp[0].y + nyArr[0] * hw0);
    for (int i = 1; i < count; i++) {
      final hw = (interp[i].w * 0.5).clamp(0.2, 999.0);
      path.lineTo(interp[i].x + nxArr[i] * hw, interp[i].y + nyArr[i] * hw);
    }
    for (int i = count - 1; i >= 0; i--) {
      final hw = (interp[i].w * 0.5).clamp(0.2, 999.0);
      path.lineTo(interp[i].x - nxArr[i] * hw, interp[i].y - nyArr[i] * hw);
    }
    path.close();
    final paint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);
    canvas.drawCircle(Offset(interp.first.x, interp.first.y), hw0, paint);
    final lastHw = (interp.last.w * 0.5).clamp(0.2, 999.0);
    canvas.drawCircle(Offset(interp.last.x, interp.last.y), lastHw, paint);
  }

  void _paintStroke(Canvas canvas, StrokeData stroke) {
    if (stroke.points.isEmpty) return;
    // Single-point stroke = Apple Pencil quick tap. Render as a filled
    // circle proportional to baseWidth so dots actually appear (the old
    // `< 2` early-return silently dropped them).
    if (stroke.points.length == 1) {
      final p = stroke.points.first;
      final color = Color(stroke.color);
      final paint = Paint()
        ..color = color.withValues(
            alpha: stroke.isHighlighter ? 0.35 : stroke.opacity)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      // Match the per-tool width math: pen ~baseWidth, brush 1.5×, etc.
      // Bumped 0.55 → 0.75 so single-tap dots are actually visible
      // (a tap left a 1.5 px diameter dot at default — sub-pixel on
      // many displays). Now ~2.6 px at default baseWidth, matching
      // GoodNotes/Notability quick-tap visibility.
      double radius = stroke.baseWidth * 0.75;
      if (stroke.toolType == 'brush') radius *= 1.4;
      if (stroke.toolType == 'highlighter') radius = stroke.baseWidth * 0.6;
      // Pressure factor: floor 0.6 + slope 0.4 (was 0.4+0.6) keeps
      // body on the worst-case-light Apple Pencil quick tap.
      final pf = 0.6 + p.pressure * 0.4;
      canvas.drawCircle(Offset(p.x, p.y), (radius * pf).clamp(0.5, 50.0), paint);
      return;
    }

    final color = Color(stroke.color);

    if (stroke.isHighlighter) {
      // Highlighter: flat width, semi-transparent, multiply blend
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

    // Ballpoint: simple line-by-line with mild pressure
    if (stroke.toolType == 'ballpoint') {
      final paint = Paint()
        ..color = color.withValues(alpha: stroke.opacity)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      final zoomBucketKey = (zoom / 0.5).round();
      final cached = _strokePathCache[stroke];
      if (cached != null && cached.zoomBucket == zoomBucketKey) {
        for (final run in cached.runs) {
          paint.strokeWidth = run.width;
          canvas.drawPath(run.path, paint);
        }
        return;
      }
      final interpolated = _catmullRomInterpolate(stroke.points, zoom);
      final runs = _bucketSegmentsToPaths(
          interpolated,
          (p0, p1) => stroke.baseWidth *
              (0.6 + ((p0.pressure + p1.pressure) / 2) * 0.4));
      _strokePathCache[stroke] = _StrokeCacheEntry(zoomBucketKey, runs);
      for (final run in runs) {
        paint.strokeWidth = run.width;
        canvas.drawPath(run.path, paint);
      }
      return;
    }

    // Brush: wide, soft edges via multiple overlapping strokes
    if (stroke.toolType == 'brush') {
      final zoomBucketKey = (zoom / 0.5).round();
      final cached = _brushPathCache[stroke];
      if (cached != null && cached.zoomBucket == zoomBucketKey) {
        for (final layer in cached.layers) {
          final paint = Paint()
            ..color = color.withValues(alpha: layer.alpha)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true;
          for (final run in layer.runs) {
            paint.strokeWidth = run.width;
            canvas.drawPath(run.path, paint);
          }
        }
        return;
      }
      final interpolated = _catmullRomInterpolate(stroke.points, zoom);
      final layers = <_BrushLayer>[];
      for (int layer = 0; layer < 3; layer++) {
        final alpha = (stroke.opacity * (0.3 - layer * 0.08)).clamp(0.05, 1.0);
        final widthMul = 1.0 + layer * 0.6;
        final runs = _bucketSegmentsToPaths(
            interpolated,
            (p0, p1) => stroke.baseWidth *
                widthMul *
                (0.2 + ((p0.pressure + p1.pressure) / 2) * 0.8));
        layers.add(_BrushLayer(alpha, runs));
        final paint = Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
        for (final run in runs) {
          paint.strokeWidth = run.width;
          canvas.drawPath(run.path, paint);
        }
      }
      _brushPathCache[stroke] = _BrushCacheEntry(zoomBucketKey, layers);
      return;
    }

    // ── Calligraphy brush (variable-width, velocity + angle driven) ──
    // Like a dip-pen nib: thick when moving slowly OR along the nib axis
    // (NE→SW by convention), thin on fast movement orthogonal to the nib.
    // Renders as a filled polygon between the two offset edges (same
    // technique as fountain pen below) so edges stay crisp at any zoom.
    if (stroke.toolType == 'calligraphy') {
      final n = stroke.points.length;
      // Nib angle: 45° (NE-SW), traditional italic calligraphy direction.
      // Strokes moving perpendicular to this axis get the full nib width;
      // strokes moving parallel to it get the thin side.
      const nibAngle = -pi / 4;
      final nibDx = cos(nibAngle);
      final nibDy = sin(nibAngle);

      final velocities = List<double>.filled(n, 0.0);
      final angleFactors = List<double>.filled(n, 1.0);
      for (int i = 1; i < n; i++) {
        final dx = stroke.points[i].x - stroke.points[i - 1].x;
        final dy = stroke.points[i].y - stroke.points[i - 1].y;
        final len = sqrt(dx * dx + dy * dy);
        velocities[i] = len;
        if (len > 0.001) {
          // cos of angle between motion direction and nib axis, 0..1.
          // Parallel (cos = 1) → thin side, perpendicular (cos = 0) → fat side.
          final cosTheta = ((dx * nibDx + dy * nibDy) / len).abs();
          // Smooth falloff: thin at 20% base when parallel, 150% when perp.
          angleFactors[i] = 1.5 - 1.3 * cosTheta;
        }
      }
      if (n > 1) {
        velocities[0] = velocities[1];
        angleFactors[0] = angleFactors[1];
      }

      final calligWidths = List<double>.filled(n, stroke.baseWidth);
      for (int i = 0; i < n; i++) {
        // Velocity scales from 2.2× (stationary) down to 0.25× (very fast).
        // The wide range is what makes calligraphy feel "inked": a slow
        // pause on a letter apex deposits a visible blob.
        final vF = (2.2 - (velocities[i] / 10.0).clamp(0.0, 1.95));
        final pF = 0.4 + stroke.points[i].pressure * 0.6;
        calligWidths[i] = stroke.baseWidth * pF * vF * angleFactors[i];
      }
      // Heavy smoothing (4 passes) because angle changes point-to-point
      // would otherwise create sawtooth edges on the rendered ribbon.
      for (int pass = 0; pass < 4; pass++) {
        for (int i = 1; i < n - 1; i++) {
          calligWidths[i] = (calligWidths[i - 1] + calligWidths[i] * 2 + calligWidths[i + 1]) / 4;
        }
      }

      final interp = _catmullRomAdaptiveWithWidth(stroke.points, calligWidths, zoom);
      if (interp.length < 2) return;
      _paintVariableWidthRibbon(canvas, interp, color.withValues(alpha: stroke.opacity));
      return;
    }

    // ── Fountain pen (default "pen") ──
    // CACHE FAST-PATH FIRST — before any interpolation work. The
    // cache lookup is O(1) on the StrokeData identity (Expando) and a
    // hit means we skip all of velocity sqrt, smoothing passes, and
    // adaptive Catmull-Rom (192k math ops for a 100-stroke page).
    // Mirrors the ballpoint/brush branches above; the pen branch
    // previously checked the cache AFTER all this precompute, wasting
    // the cache's whole purpose on every cache-miss frame.
    final zoomBucketKey = (zoom / 0.5).round();
    final cachedRuns = _strokePathCache[stroke];
    if (cachedRuns != null && cachedRuns.zoomBucket == zoomBucketKey) {
      final paint = Paint()
        ..color = color.withValues(alpha: stroke.opacity)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      for (final run in cachedRuns.runs) {
        paint.strokeWidth = run.width;
        canvas.drawPath(run.path, paint);
      }
      return;
    }

    // Cache miss — compute per-original-point width from pressure +
    // velocity, smooth, then interpolate through adaptive Catmull-Rom.
    //
    // Width-modulation curves tuned (0.36.x) to feel closer to GoodNotes:
    //   - pressure: 0.45 → 1.05 (was 0.15 → 1.0). The old lower bound made
    //     the stroke "anorexic" at light touches and especially at the
    //     start/end of a fast scribble where Apple Pencil reports near-zero
    //     pressure. Keeping more body matches the visual weight of a real
    //     fountain pen and the "pen" tool in GoodNotes.
    //   - velocity: clamp thinning at 30% (was 50%). A 50% reduction at
    //     speed turned the middle of fast cursive strokes into hairlines;
    //     30% preserves character without losing all the velocity feedback.
    //   - 3 smoothing passes (was 2). Cheaper than it looks (operates on
    //     N original points, not interpolated) and removes the small
    //     width-step artifacts visible on slow zoomed-in strokes.
    final n = stroke.points.length;

    // Velocity in PAGE-UNITS PER SECOND, normalised across input rates.
    final velocities = List<double>.filled(n, 0.0);
    for (int i = 1; i < n; i++) {
      final dx = stroke.points[i].x - stroke.points[i - 1].x;
      final dy = stroke.points[i].y - stroke.points[i - 1].y;
      final dt = (stroke.points[i].timestamp -
                  stroke.points[i - 1].timestamp);
      final dtMs = dt < 1 ? 1 : dt;
      velocities[i] = sqrt(dx * dx + dy * dy) * 1000.0 / dtMs;
    }
    if (n > 1) velocities[0] = velocities[1];

    // Light velocity smoothing — one 1-2-1 pass kills the worst
    // millisecond-quantisation jitter without flattening the genuine
    // fast→slow envelope of the hand gesture. Three passes (the
    // previous attempt) over-smoothed at medium writing speed and
    // erased the visible width modulation that gives a fountain-pen
    // line its character.
    for (int i = 1; i < n - 1; i++) {
      velocities[i] = (velocities[i - 1] + velocities[i] * 2 + velocities[i + 1]) / 4;
    }

    final rawWidths = List<double>.filled(n, stroke.baseWidth);
    for (int i = 0; i < n; i++) {
      // Velocity factor gated by a "normal writing" threshold:
      //   ≤ 800 px/s ("normal handwriting") → no thinning at all,
      //   linearly up to 15% thinning at ≥ 4000 px/s (very fast).
      // The previous unconditional 40% thinning crushed strokes at
      // moderate speed (the user's "medio-veloce" complaint).
      // Pressure already carries the bulk of the modulation on a
      // stylus — the wrist naturally lightens at speed — so velocity
      // here is just a subtle assist, not the primary signal.
      final excessV = (velocities[i] - 800.0).clamp(0.0, 4000.0);
      final velocityFactor = 1.0 - (excessV / 4000.0) * 0.15;
      // Pressure→width. `pressure` is already normalized to 0..1 against the
      // device's real full-scale, but raw tablet pressure is perceptually
      // weak (normal writing sits low on the scale), so a gamma (sqrt) lifts
      // light/medium presses into a usable range, then a WIDE linear map makes
      // pressing clearly thicken the line. Tunable: the 0.35 floor (min width
      // factor) and 1.15 span give 0.35×..1.50× baseWidth.
      final pc = sqrt(stroke.points[i].pressure.clamp(0.0, 1.0));
      final pressureFactor = 0.35 + pc * 1.15;
      rawWidths[i] = stroke.baseWidth * pressureFactor * velocityFactor;
    }
    // Two more smoothing passes on the final widths — pressure was
    // already EMA-smoothed in ActiveStrokeNotifier; combined with the
    // velocity-smoothing above this gives the final width signal a
    // continuous look without lag.
    for (int pass = 0; pass < 2; pass++) {
      for (int i = 1; i < n - 1; i++) {
        rawWidths[i] = (rawWidths[i - 1] + rawWidths[i] * 2 + rawWidths[i + 1]) / 4;
      }
    }

    final interpolated = _catmullRomAdaptiveWithWidth(stroke.points, rawWidths, zoom);
    if (interpolated.length < 2) return;

    // ── Render as bucketed Path runs ──
    //
    // The previous implementation issued ONE `canvas.drawLine` per
    // interpolated segment with a per-segment `strokeWidth`. For an
    // 80-point stroke that adaptive Catmull-Rom blew up to ~1.9 k
    // segments → 1.9 k drawLine + 1.9 k strokeWidth state changes.
    // A page with 100 strokes = ~190 k drawLine commands recorded
    // into the Picture, and Skia couldn't batch them because every
    // call had a different paint width. **THIS was why pages with
    // dense ink were ~100× slower than pages with images** even with
    // the Picture cache hitting (the cache stored the bloated command
    // list verbatim).
    //
    // Group consecutive segments whose width quantises to the same
    // 0.5 px bucket and emit ONE `drawPath` per bucket. A typical
    // pen stroke has width range 1.5–3.0 → 3-4 buckets → 3-4 drawPath
    // commands per stroke instead of 1.9 k. The visual is
    // indistinguishable: a 0.5 px width step is invisible at 1× zoom
    // and the round stroke caps blend the bucket boundaries seamlessly
    // (same trick that made the original drawLine implementation work
    // around the polygon-ribbon pinching issue).
    // Cache-miss path: build the bucketed runs and store them. The
    // shared Paint object is created here (not at top of function)
    // because the early-return cache-hit branch above creates its own.
    final paint = Paint()
      ..color = color.withValues(alpha: stroke.opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final count = interpolated.length;
    if (count < 2) return;
    // 0.25 px (was 0.5): on a default 2-3 px pen the 0.5 px buckets were
    // only 3-4 discrete widths across a whole letter — the user saw the
    // steps ("più spessa e meno spessa, non smoothato"). Halving the
    // quantum doubles the bucket count (typ. 6-8 drawPath per stroke,
    // still ~250× fewer commands than per-segment drawLine) and brings
    // the steps under the round-cap blend threshold.
    const widthQuantum = 0.25;
    final runs = <_PathRun>[];
    Path? currentPath;
    double currentBucket = double.nan;
    for (int i = 0; i < count - 1; i++) {
      final p0 = interpolated[i];
      final p1 = interpolated[i + 1];
      final w = ((p0.w + p1.w) * 0.5).clamp(0.4, 999.0);
      final bucket = (w / widthQuantum).round() * widthQuantum;
      if (bucket != currentBucket) {
        if (currentPath != null) {
          runs.add(_PathRun(currentPath, currentBucket));
        }
        currentPath = Path()..moveTo(p0.x, p0.y);
        currentBucket = bucket;
      }
      currentPath!.lineTo(p1.x, p1.y);
    }
    if (currentPath != null) {
      runs.add(_PathRun(currentPath, currentBucket));
    }
    _strokePathCache[stroke] = _StrokeCacheEntry(zoomBucketKey, runs);
    for (final run in runs) {
      paint.strokeWidth = run.width;
      canvas.drawPath(run.path, paint);
    }
  }

  /// Build a list of (Path, width) bucketed runs from a sequence of
  /// `StrokePoint`s + a width function. Returns runs the caller can
  /// either draw directly or stash in [_strokePathCache] for reuse.
  List<_PathRun> _bucketSegmentsToPaths(
    List<StrokePoint> pts,
    double Function(StrokePoint p0, StrokePoint p1) widthFn,
  ) {
    final n = pts.length;
    final runs = <_PathRun>[];
    if (n < 2) return runs;
    const widthQuantum = 0.25; // see pen branch — 0.5 showed visible steps
    Path? currentPath;
    double currentBucket = double.nan;
    for (int i = 0; i < n - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final w = widthFn(p0, p1).clamp(0.4, 999.0);
      final bucket = (w / widthQuantum).round() * widthQuantum;
      if (bucket != currentBucket) {
        if (currentPath != null) {
          runs.add(_PathRun(currentPath, currentBucket));
        }
        currentPath = Path()..moveTo(p0.x, p0.y);
        currentBucket = bucket;
      }
      currentPath!.lineTo(p1.x, p1.y);
    }
    if (currentPath != null) {
      runs.add(_PathRun(currentPath, currentBucket));
    }
    return runs;
  }

  List<StrokePoint> _catmullRomInterpolate(List<StrokePoint> points, double zoom) {
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
      // Proportional to screen-space distance: ~1 segment per 3 screen pixels
      final segments = max(2, min(24, (dist * zoom / 3.0).ceil()));

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

  /// Adaptive Catmull-Rom interpolation that carries pre-computed stroke width.
  /// Segments proportional to screen-space distance for smooth rendering at any zoom.
  List<_InterpolatedPoint> _catmullRomAdaptiveWithWidth(
      List<StrokePoint> points, List<double> widths, double zoom) {
    if (points.length < 4) {
      return List.generate(points.length, (i) =>
          _InterpolatedPoint(points[i].x, points[i].y, points[i].pressure, widths[i]));
    }
    final result = <_InterpolatedPoint>[];

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
      // Proportional to screen-space distance: ~1 segment per 3 screen pixels
      final segments = max(2, min(24, (dist * zoom / 3.0).ceil()));

      for (int j = 0; j < segments; j++) {
        final t = j / segments;
        final t2 = t * t;
        final t3 = t2 * t;

        final x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t +
            (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
            (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3);
        final y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t +
            (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
            (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);
        final pressure = p1.pressure + (p2.pressure - p1.pressure) * t;
        final w = w1 + (w2 - w1) * t;

        result.add(_InterpolatedPoint(x, y, pressure, w));
      }
    }
    result.add(_InterpolatedPoint(
        points.last.x, points.last.y, points.last.pressure, widths.last));
    return result;
  }

  void _paintText(Canvas canvas, TextData textData, {double? widthOverride}) {
    // Paragraph shaping lives in text_paragraph_factory.dart so that the
    // import paginator measures exactly what this painter draws.
    final paragraph = buildTextParagraph(textData, width: widthOverride);
    canvas.drawParagraph(paragraph, Offset(textData.x, textData.y));
  }

  void _paintImage(Canvas canvas, ImageData imageData) {
    canvas.save();
    if (imageData.rotation != 0) {
      final cx = imageData.x + imageData.width / 2;
      final cy = imageData.y + imageData.height / 2;
      canvas.translate(cx, cy);
      canvas.rotate(imageData.rotation);
      canvas.translate(-cx, -cy);
    }
    // Horizontal mirror around the image's vertical centerline.
    if (imageData.flipHorizontal) {
      final cx = imageData.x + imageData.width / 2;
      final cy = imageData.y + imageData.height / 2;
      canvas.translate(cx, cy);
      canvas.scale(-1, 1);
      canvas.translate(-cx, -cy);
    }

    final rect = Rect.fromLTWH(imageData.x, imageData.y, imageData.width, imageData.height);

    // Try to render from cache (read LIVE — if the parent widget didn't
    // rebuild for the latest decode, this getter still returns the fresh map).
    final cachedImage = _liveImageCache[imageData.assetPath];
    if (cachedImage != null) {
      final srcRect = Rect.fromLTWH(0, 0, cachedImage.width.toDouble(), cachedImage.height.toDouble());
      // Use medium quality (bilinear with mipmaps) so that imported raster
      // content — especially old handwritten notes exported from OneNote —
      // degrades gracefully when zoomed in. `low` (nearest-neighbour) made
      // small strokes look blocky at high zoom.
      final imgPaint = Paint()
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true
        ..color = Colors.white.withValues(alpha: imageData.opacity);
      canvas.drawImageRect(cachedImage, srcRect, rect, imgPaint);
    } else {
      // Placeholder
      final placeholderPaint = Paint()..color = Colors.grey.shade200..style = PaintingStyle.fill;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), placeholderPaint);

      final borderPaint = Paint()
        ..color = Colors.grey.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), borderPaint);

      // Image icon in center
      final iconSize = min(imageData.width, imageData.height) * 0.3;
      final iconPaint = Paint()..color = Colors.grey.shade500..style = PaintingStyle.stroke..strokeWidth = 2;
      final center = rect.center;
      canvas.drawCircle(center, iconSize * 0.3, iconPaint);
      // Mountain icon
      final path = Path()
        ..moveTo(center.dx - iconSize * 0.4, center.dy + iconSize * 0.3)
        ..lineTo(center.dx - iconSize * 0.1, center.dy - iconSize * 0.1)
        ..lineTo(center.dx + iconSize * 0.1, center.dy + iconSize * 0.15)
        ..lineTo(center.dx + iconSize * 0.3, center.dy - iconSize * 0.2)
        ..lineTo(center.dx + iconSize * 0.5, center.dy + iconSize * 0.3);
      canvas.drawPath(path, iconPaint);

      // File name text
      final nameStyle = ui.TextStyle(color: const Color(0xFF757575), fontSize: 10);
      final nameBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
        ..pushStyle(nameStyle)
        ..addText(imageData.assetPath.length > 20 ? '${imageData.assetPath.substring(0, 17)}...' : imageData.assetPath);
      final nameParagraph = nameBuilder.build()..layout(ui.ParagraphConstraints(width: imageData.width - 8));
      canvas.drawParagraph(nameParagraph, Offset(imageData.x + 4, imageData.y + imageData.height - 16));
    }

    canvas.restore();
  }

  /// Draw a typeset LaTeX equation from the math raster cache. Mirrors
  /// [_paintImage]'s sync-lookup-then-placeholder pattern: on a cache hit
  /// the pre-rasterized ui.Image is blitted into the element box; on a miss
  /// a subtle box + the raw LaTeX source is drawn and an async rasterize is
  /// requested (via [onMathCacheMiss]) — when it lands the cache version
  /// notifier bumps, paint() re-runs, and the equation appears next frame.
  void _paintMath(Canvas canvas, MathData m) {
    final key = mathCacheKey(
        m.latex, m.color, m.fontSize, m.displayMode, mathPixelRatio);
    final cached = _liveMathCache[key];
    final rect = Rect.fromLTWH(m.x, m.y, m.width, m.height);
    if (cached != null) {
      final src = Rect.fromLTWH(
          0, 0, cached.image.width.toDouble(), cached.image.height.toDouble());
      canvas.drawImageRect(
        cached.image,
        src,
        rect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..isAntiAlias = true,
      );
    } else {
      // Miss: lightweight, visually-distinct placeholder (the raw source in
      // a tinted box) so it never looks like a broken/missing image, then
      // kick the async raster.
      final box = Paint()
        ..color = const Color(0x0F1565C0)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)), box);
      final tb = ui.ParagraphBuilder(
          ui.ParagraphStyle(textAlign: TextAlign.left, maxLines: 3))
        ..pushStyle(ui.TextStyle(
            color: Color(m.color),
            fontSize: (m.fontSize * 0.6).clamp(8.0, 16.0),
            fontFamily: 'monospace'))
        ..addText(m.latex);
      final para = tb.build()
        ..layout(ui.ParagraphConstraints(width: (m.width - 6).clamp(8.0, 4000.0)));
      canvas.drawParagraph(para, Offset(m.x + 3, m.y + 3));
      onMathCacheMiss?.call(m);
    }
  }

  void _paintShape(Canvas canvas, ShapeData shape) {
    // A shape recognized while the highlighter was active must render
    // with the same translucent multiply blend as highlighter ink (see
    // the isHighlighter branch in _paintStroke below) — otherwise it
    // paints as an opaque mark that covers whatever is underneath it.
    final strokePaint = Paint()
      ..color = shape.isHighlighter
          ? Color(shape.strokeColor).withValues(alpha: 0.35)
          : Color(shape.strokeColor)
      ..style = PaintingStyle.stroke
      ..strokeWidth = shape.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..blendMode = shape.isHighlighter ? BlendMode.multiply : BlendMode.srcOver;

    Paint? fillPaint;
    if (shape.fillColor != null) {
      fillPaint = Paint()
        ..color = Color(shape.fillColor!)
        ..style = PaintingStyle.fill
        ..blendMode = shape.isHighlighter ? BlendMode.multiply : BlendMode.srcOver;
    }

    // For triangles with a CARDINAL rotation (multiples of π/2) we
    // bake the apex direction into the path inside the 'triangle' case
    // below — applying canvas.rotate here would double-rotate. For
    // OBLIQUE triangles with explicit vertices stored, the vertices are
    // already in absolute page coords, so canvas.rotate would also
    // double-rotate. Skip the outer rotation in both cases.
    final isCardinalTriangle = shape.shapeType == 'triangle' &&
        ((shape.rotation % (pi / 2)).abs() < 1e-3 ||
         ((shape.rotation % (pi / 2)) - (pi / 2)).abs() < 1e-3);
    final isVertexTriangle = shape.shapeType == 'triangle' &&
        shape.vertices.length == 6;
    canvas.save();
    if (shape.rotation != 0 && !isCardinalTriangle && !isVertexTriangle) {
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
        final radius = (shape.x2 - shape.x1).abs() / 2;
        if (fillPaint != null) canvas.drawCircle(center, radius, fillPaint);
        canvas.drawCircle(center, radius, strokePaint);
        break;
      case 'line':
        canvas.drawLine(Offset(shape.x1, shape.y1), Offset(shape.x2, shape.y2), strokePaint);
        break;
      case 'arrow':
        canvas.drawLine(Offset(shape.x1, shape.y1), Offset(shape.x2, shape.y2), strokePaint);
        _paintArrowHead(canvas, shape, strokePaint);
        break;
      case 'triangle': {
        // Highest-priority path: oblique triangles store explicit
        // vertices captured at recognition time. Render them directly —
        // no rotation transform (the outer canvas.rotate guard above
        // already skipped). Resizing remaps these via affine bbox→bbox.
        if (shape.vertices.length == 6) {
          final v = shape.vertices;
          final tPath = Path()
            ..moveTo(v[0], v[1])
            ..lineTo(v[2], v[3])
            ..lineTo(v[4], v[5])
            ..close();
          if (fillPaint != null) canvas.drawPath(tPath, fillPaint);
          canvas.drawPath(tPath, strokePaint);
          break;
        }
        final tLeft = min(shape.x1, shape.x2);
        final tRight = max(shape.x1, shape.x2);
        final tTop = min(shape.y1, shape.y2);
        final tBottom = max(shape.y1, shape.y2);
        final tCx = (tLeft + tRight) / 2;
        final tCy = (tTop + tBottom) / 2;
        // For cardinal apex directions (rotation ≈ 0, π/2, π, 3π/2) we
        // pre-compute the apex/base inside the bbox directly. This
        // avoids the previous behaviour where canvas.rotate(π/2) around
        // the bbox center placed the apex at distance H/2 to the right
        // of center — outside the bbox when H > W — and visually
        // distorted the triangle on resize. For non-cardinal rotations
        // (rare; user drew tilted apex outside the snap window) fall
        // back to the rotation transform.
        final isCardinal =
            (shape.rotation % (pi / 2)).abs() < 1e-3 ||
            ((shape.rotation % (pi / 2)) - (pi / 2)).abs() < 1e-3;
        if (isCardinal) {
          // Quadrant: 0=up, 1=right, 2=down, 3=left
          var q = ((shape.rotation / (pi / 2)).round()) % 4;
          if (q < 0) q += 4;
          final tPath = Path();
          switch (q) {
            case 0: // apex up
              tPath..moveTo(tCx, tTop)
                   ..lineTo(tLeft, tBottom)
                   ..lineTo(tRight, tBottom)..close();
              break;
            case 1: // apex right
              tPath..moveTo(tRight, tCy)
                   ..lineTo(tLeft, tTop)
                   ..lineTo(tLeft, tBottom)..close();
              break;
            case 2: // apex down
              tPath..moveTo(tCx, tBottom)
                   ..lineTo(tRight, tTop)
                   ..lineTo(tLeft, tTop)..close();
              break;
            case 3: // apex left
              tPath..moveTo(tLeft, tCy)
                   ..lineTo(tRight, tBottom)
                   ..lineTo(tRight, tTop)..close();
              break;
          }
          if (fillPaint != null) canvas.drawPath(tPath, fillPaint);
          canvas.drawPath(tPath, strokePaint);
        } else {
          // Non-cardinal: the outer canvas.rotate handles the apex
          // direction; render the canonical apex-up triangle.
          final tPath = Path()
            ..moveTo(tCx, tTop)
            ..lineTo(tLeft, tBottom)
            ..lineTo(tRight, tBottom)
            ..close();
          if (fillPaint != null) canvas.drawPath(tPath, fillPaint);
          canvas.drawPath(tPath, strokePaint);
        }
        break;
      }
      case 'rhombus':
        final rLeft = min(shape.x1, shape.x2);
        final rRight = max(shape.x1, shape.x2);
        final rTop = min(shape.y1, shape.y2);
        final rBottom = max(shape.y1, shape.y2);
        final rCx = (rLeft + rRight) / 2;
        final rCy = (rTop + rBottom) / 2;
        final rPath = Path()
          ..moveTo(rCx, rTop)       // top
          ..lineTo(rRight, rCy)     // right
          ..lineTo(rCx, rBottom)    // bottom
          ..lineTo(rLeft, rCy)      // left
          ..close();
        if (fillPaint != null) canvas.drawPath(rPath, fillPaint);
        canvas.drawPath(rPath, strokePaint);
        break;
      case 'xy_plane':
        // XY plane: two arrows from an origin, with optional grid lines
        final ox = shape.x1;
        final oy = shape.y2; // origin at bottom-left
        final ex = shape.x2;
        final ey = shape.y1;
        final w = ex - ox;
        final h = oy - ey;
        final arrowSz = (min(w, h) * 0.06).clamp(6.0, 16.0);
        // X axis
        canvas.drawLine(Offset(ox, oy), Offset(ex, oy), strokePaint);
        _paintArrowHeadPoints(canvas, Offset(ex - arrowSz * 2, oy), Offset(ex, oy), arrowSz, strokePaint);
        // Y axis
        canvas.drawLine(Offset(ox, oy), Offset(ox, ey), strokePaint);
        _paintArrowHeadPoints(canvas, Offset(ox, ey + arrowSz * 2), Offset(ox, ey), arrowSz, strokePaint);
        // Labels using canvas.drawParagraph is complex; draw small tick marks
        final tickPaint = Paint()
          ..color = Color(shape.strokeColor).withValues(alpha: 0.4)
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke;
        const numTicks = 5;
        for (int i = 1; i <= numTicks; i++) {
          final tx = ox + i * w / (numTicks + 1);
          canvas.drawLine(Offset(tx, oy - 4), Offset(tx, oy + 4), tickPaint);
          final ty = oy - i * h / (numTicks + 1);
          canvas.drawLine(Offset(ox - 4, ty), Offset(ox + 4, ty), tickPaint);
        }
        break;
    }
    canvas.restore();
  }

  void _paintArrowHead(Canvas canvas, ShapeData shape, Paint paint) {
    final angle = atan2(shape.y2 - shape.y1, shape.x2 - shape.x1);
    const arrowLen = 15.0;
    const arrowAngle = 0.5;
    final path = Path()
      ..moveTo(shape.x2, shape.y2)
      ..lineTo(shape.x2 - arrowLen * cos(angle - arrowAngle), shape.y2 - arrowLen * sin(angle - arrowAngle))
      ..moveTo(shape.x2, shape.y2)
      ..lineTo(shape.x2 - arrowLen * cos(angle + arrowAngle), shape.y2 - arrowLen * sin(angle + arrowAngle));
    canvas.drawPath(path, paint);
  }

  void _paintArrowHeadPoints(Canvas canvas, Offset from, Offset to, double size, Paint paint) {
    final angle = atan2(to.dy - from.dy, to.dx - from.dx);
    const spread = 0.5;
    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(to.dx - size * cos(angle - spread), to.dy - size * sin(angle - spread))
      ..moveTo(to.dx, to.dy)
      ..lineTo(to.dx - size * cos(angle + spread), to.dy - size * sin(angle + spread));
    canvas.drawPath(path, paint);
  }

  void _paintShapePreview(Canvas canvas, (Offset, Offset, String) preview) {
    final (start, end, shapeType) = preview;
    final previewPaint = Paint()
      ..color = const Color(0xFF2196F3).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..isAntiAlias = true;

    switch (shapeType) {
      case 'rectangle':
        canvas.drawRect(Rect.fromPoints(start, end), previewPaint);
        break;
      case 'circle':
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final radius = (end - start).distance / 2;
        canvas.drawCircle(center, radius, previewPaint);
        break;
      case 'line':
        canvas.drawLine(start, end, previewPaint);
        break;
      case 'arrow':
        canvas.drawLine(start, end, previewPaint);
        break;
      case 'triangle':
        final tLeft = min(start.dx, end.dx);
        final tRight = max(start.dx, end.dx);
        final tTop = min(start.dy, end.dy);
        final tBottom = max(start.dy, end.dy);
        final tPath = Path()
          ..moveTo((tLeft + tRight) / 2, tTop)
          ..lineTo(tLeft, tBottom)
          ..lineTo(tRight, tBottom)
          ..close();
        canvas.drawPath(tPath, previewPaint);
        break;
      case 'rhombus':
        final rLeft = min(start.dx, end.dx);
        final rRight = max(start.dx, end.dx);
        final rTop = min(start.dy, end.dy);
        final rBottom = max(start.dy, end.dy);
        final rCx = (rLeft + rRight) / 2;
        final rCy = (rTop + rBottom) / 2;
        final rPath = Path()
          ..moveTo(rCx, rTop)
          ..lineTo(rRight, rCy)
          ..lineTo(rCx, rBottom)
          ..lineTo(rLeft, rCy)
          ..close();
        canvas.drawPath(rPath, previewPaint);
        break;
      case 'xy_plane':
        canvas.drawLine(Offset(start.dx, end.dy), Offset(end.dx, end.dy), previewPaint);
        canvas.drawLine(Offset(start.dx, end.dy), Offset(start.dx, start.dy), previewPaint);
        break;
    }
  }

  void _paintRecognizedShapePreview(Canvas canvas, ShapeData shape) {
    // Render the shape itself
    _paintShape(canvas, shape);

    // Subtle glow border to indicate it's a recognized shape
    final glowPaint = Paint()
      ..color = const Color(0xFF4CAF50).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = shape.strokeWidth + 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    switch (shape.shapeType) {
      case 'line':
        canvas.drawLine(Offset(shape.x1, shape.y1), Offset(shape.x2, shape.y2), glowPaint);
        break;
      case 'circle':
        final rect = Rect.fromPoints(Offset(shape.x1, shape.y1), Offset(shape.x2, shape.y2));
        canvas.drawOval(rect, glowPaint);
        break;
      default:
        final rect = Rect.fromPoints(Offset(shape.x1, shape.y1), Offset(shape.x2, shape.y2));
        canvas.drawRect(rect, glowPaint);
    }
  }

  void _paintLassoPathFromPoints(Canvas canvas, List<Offset> points) {
    // Build the full closed path
    final fullPath = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      fullPath.lineTo(points[i].dx, points[i].dy);
    }
    fullPath.close(); // Always close back to start

    // Fill inside lasso path with translucent blue
    final fillPaint = Paint()
      ..color = const Color(0xFF90CAF9).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fullPath, fillPaint);

    // Dashed grey stroke outline (marching ants style)
    final dashPaint = Paint()
      ..color = const Color(0xFF616161)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..isAntiAlias = true;

    // Compute total path length and draw dashes
    final allPoints = [...points, points[0]]; // include closing segment
    const dashLen = 6.0;
    const gapLen = 4.0;
    double accumulator = 0;
    bool drawing = true;

    for (int i = 0; i < allPoints.length - 1; i++) {
      final p0 = allPoints[i];
      final p1 = allPoints[i + 1];
      final dx = p1.dx - p0.dx;
      final dy = p1.dy - p0.dy;
      final segLen = sqrt(dx * dx + dy * dy);
      if (segLen == 0) continue;
      final ux = dx / segLen;
      final uy = dy / segLen;
      double traveled = 0;

      while (traveled < segLen) {
        final needed = drawing ? dashLen - accumulator : gapLen - accumulator;
        final available = segLen - traveled;
        final step = min(needed, available);

        if (drawing) {
          final startX = p0.dx + ux * traveled;
          final startY = p0.dy + uy * traveled;
          final endX = p0.dx + ux * (traveled + step);
          final endY = p0.dy + uy * (traveled + step);
          canvas.drawLine(Offset(startX, startY), Offset(endX, endY), dashPaint);
        }

        accumulator += step;
        traveled += step;
        if (accumulator >= (drawing ? dashLen : gapLen)) {
          drawing = !drawing;
          accumulator = 0;
        }
      }
    }
  }

  /// Render the laser-pointer trail. Strategy:
  /// - Group consecutive points into 4 alpha buckets (0-25%, 25-50%,
  ///   50-75%, 75-100% of fade window). Each bucket renders ONE Path
  ///   with strokeJoin.round and StrokeCap.round — Skia draws a
  ///   continuous fading line instead of N independent drawLine calls,
  ///   which used to expose every vertex as a circular blob ("pallini
  ///   visibili durante il tratto") because each segment-end is an
  ///   independent round cap.
  /// - Reduced intensity: thinner core (2.5 vs 4), softer glow (alpha
  ///   0.18 vs 0.30, width 7 vs 12, sigma 3 vs 6) — the prior version
  ///   was overpowering on white pages.
  /// - Smaller head dot (r=4 vs 7, sigma 2 vs 4).
  void _paintLaserTrail(
      Canvas canvas, List<({double x, double y, int t, bool start})> pts) {
    if (pts.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    const fadeMs = 1500;
    const buckets = 4;
    if (pts.length >= 2) {
      // Build one Path per alpha bucket. Each path is a piecewise
      // polyline; Skia's strokeJoin.round eliminates the per-vertex
      // "pallini" the prior implementation had.
      final paths = List<Path?>.filled(buckets, null);
      Path? currentPath;
      int currentBucket = -1;
      for (int i = 1; i < pts.length; i++) {
        final age = now - pts[i].t;
        if (age > fadeMs) {
          currentPath = null;
          currentBucket = -1;
          continue;
        }
        // Stroke-break: the user lifted and started a new laser
        // gesture. Don't bridge from the previous point — moveTo this
        // point and skip the lineTo (no segment from the prior stroke).
        if (pts[i].start) {
          currentPath = null;
          currentBucket = -1;
          continue;
        }
        final alpha01 = 1.0 - (age / fadeMs);
        final bucket = (alpha01 * buckets).floor().clamp(0, buckets - 1);
        if (bucket != currentBucket) {
          paths[bucket] ??= Path();
          paths[bucket]!.moveTo(pts[i - 1].x, pts[i - 1].y);
          currentPath = paths[bucket];
          currentBucket = bucket;
        }
        currentPath!.lineTo(pts[i].x, pts[i].y);
      }
      const baseColor = Color(0xFFFF3B30);
      for (int b = 0; b < buckets; b++) {
        final path = paths[b];
        if (path == null) continue;
        final alpha = (b + 0.5) / buckets;
        final glow = Paint()
          ..color = baseColor.withValues(alpha: alpha * 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        final core = Paint()
          ..color = baseColor.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(path, glow);
        canvas.drawPath(path, core);
      }
    }
    // Bright head dot at the latest point — smaller and softer.
    final last = pts.last;
    final headAge = now - last.t;
    if (headAge < fadeMs) {
      final headAlpha = (1.0 - (headAge / fadeMs)).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(last.x, last.y),
        4,
        Paint()
          ..color = const Color(0xFFFF3B30).withValues(alpha: headAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  void _paintSelectionBounds(
    Canvas canvas, {
    Offset? liveDragOffset,
    double? liveRotation,
    double? liveScale,
  }) {
    final sel = lassoSelection!;
    // Use the resolved live values when present (caller passes the
    // already-merged ones from liveLassoTransform). Falls back to the
    // Riverpod state when no gesture is in flight.
    final dragOffset = liveDragOffset ?? sel.dragOffset;
    final rotation = liveRotation ?? sel.rotation;
    final scale = liveScale ?? sel.scale;
    final center = sel.bounds.center;
    final scaledBounds = Rect.fromCenter(
      center: center,
      width: sel.bounds.width * scale,
      height: sel.bounds.height * scale,
    ).translate(dragOffset.dx, dragOffset.dy);
    final selRect = scaledBounds.inflate(4);

    canvas.save();
    if (rotation != 0.0) {
      final transformCenter = scaledBounds.center;
      canvas.translate(transformCenter.dx, transformCenter.dy);
      canvas.rotate(rotation);
      canvas.translate(-transformCenter.dx, -transformCenter.dy);
    }

    // Dashed border
    _paintDashedRect(canvas, selRect, const Color(0xFF2196F3), 1.0);

    canvas.restore();
  }

  void _paintDashedRect(Canvas canvas, Rect rect, Color color, double strokeWidth) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    const double dashLen = 5.0;
    const double gapLen = 3.0;
    for (final edge in [
      [rect.topLeft, rect.topRight],
      [rect.topRight, rect.bottomRight],
      [rect.bottomRight, rect.bottomLeft],
      [rect.bottomLeft, rect.topLeft],
    ]) {
      final start = edge[0];
      final end = edge[1];
      final dx = end.dx - start.dx;
      final dy = end.dy - start.dy;
      final length = (Offset(dx, dy)).distance;
      if (length == 0) continue;
      final ux = dx / length;
      final uy = dy / length;
      double d = 0;
      while (d < length) {
        final segEnd = (d + dashLen).clamp(0.0, length);
        canvas.drawLine(
          Offset(start.dx + ux * d, start.dy + uy * d),
          Offset(start.dx + ux * segEnd, start.dy + uy * segEnd),
          paint,
        );
        d += dashLen + gapLen;
      }
    }
  }

  /// True iff every ImageElement on this page has a decoded ui.Image in
  /// imageCache OR is flagged as corrupt (placeholder is the final
  /// rendered output, no live update will arrive). Used by the
  /// picture-cache build to decide whether to store the recorded
  /// picture: storing while images are still legitimately decoding
  /// would bake placeholders that only refresh on the next pageData
  /// identity change. Treating corrupt as "decoded" matters because
  /// otherwise a single broken PNG (common after the 1024-byte
  /// truncation incidents) blocks the cache forever and every frame
  /// re-records the full static layers — sustained-core CPU on idle.
  bool _allImageAssetsDecoded() {
    // The Expando memoizes "page has any async-decoded content" — images
    // OR typeset math. A page with neither short-circuits to true.
    final hasAsync = _hasImageCache[pageData];
    if (hasAsync == false) return true;
    final live = _liveImageCache;
    final liveMath = _liveMathCache;
    var sawAny = false;
    for (final el in pageData.layers.content) {
      if (el is ImageElement) {
        sawAny = true;
        final p = el.data.assetPath;
        if (p.isEmpty) continue;
        if (live[p] == null && !corruptAssetIds.contains(p)) {
          return false;
        }
      } else if (el is MathElement) {
        // Math rasterizes async like an image — until its raster lands
        // (or permanently fails) the placeholder is non-final, so the
        // static picture must NOT be cached yet (would bake the box).
        sawAny = true;
        final d = el.data;
        final key = mathCacheKey(
            d.latex, d.color, d.fontSize, d.displayMode, mathPixelRatio);
        if (liveMath[key] == null && !failedMathKeys.contains(key)) {
          return false;
        }
      }
    }
    // Populate the "page has any async content" Expando on first walk so
    // stroke-only pages can short-circuit on subsequent frames.
    _hasImageCache[pageData] ??= sawAny;
    return true;
  }

  /// Identity signature of the decoded ui.Images (and math rasters) this
  /// page's elements resolve to RIGHT NOW. Part of the static-picture cache
  /// key: when _evictDistantImages disposes a texture and the asset is
  /// later re-decoded, the new ui.Image has a new identity — without this
  /// in the key, lookup() kept returning the Picture recorded against the
  /// disposed texture (stale pixels forever) while pinning the evicted
  /// texture's GPU memory alive, defeating the eviction entirely. Same for
  /// corrupt→healed asset transitions (placeholder baked into the cached
  /// Picture never refreshed).
  int _pageImageSignature() {
    if (_hasImageCache[pageData] == false) return 0;
    final live = _liveImageCache;
    final liveMath = _liveMathCache;
    var sig = 0;
    for (final el in pageData.layers.content) {
      if (el is ImageElement) {
        final img = live[el.data.assetPath];
        if (img != null) {
          sig = 0x1fffffff & (sig + identityHashCode(img));
        }
      } else if (el is MathElement) {
        final d = el.data;
        final key = mathCacheKey(
            d.latex, d.color, d.fontSize, d.displayMode, mathPixelRatio);
        final r = liveMath[key];
        if (r != null) {
          sig = 0x1fffffff & (sig + identityHashCode(r.image));
        }
      }
    }
    return sig;
  }

  // Cached sort to avoid O(n log n) per paint frame
  static List<ContentElement>? _cachedSortedContent;
  static List<ContentElement>? _cachedSourceContent;

  /// Drop every cached picture and the static sort cache. Call this
  /// from notebook close so the static `_staticPictureCache` doesn't
  /// keep the closed notebook's PageData refs (and ~5-10 MB of Skia
  /// picture buffers) alive across notebook switches.
  static void disposeStaticCache() {
    _staticPictureCache.clearAll();
    _cachedSortedContent = null;
    _cachedSourceContent = null;
  }

  static int _zIndexOf(ContentElement e) {
    if (e is StrokeElement) return e.zIndex;
    if (e is TextElement) return e.zIndex;
    if (e is ImageElement) return e.zIndex;
    if (e is ShapeElement) return e.zIndex;
    return (e as MathElement).zIndex;
  }

  static List<ContentElement> _getSortedContent(List<ContentElement> content) {
    if (identical(content, _cachedSourceContent) && _cachedSortedContent != null) {
      return _cachedSortedContent!;
    }
    _cachedSourceContent = content;
    // Use is-checks (zero-alloc) instead of `.map(stroke:..., text:...,
    // image:..., shape:...)` — that allocated 8 closures per A/B
    // comparison × O(n log n) compares. For 200 elements that's
    // ~12 000 closure allocations per sort.
    _cachedSortedContent = List<ContentElement>.from(content)
      ..sort((a, b) => _zIndexOf(a).compareTo(_zIndexOf(b)));
    return _cachedSortedContent!;
  }

  @override
  bool shouldRepaint(covariant CanvasRenderEngine oldDelegate) {
    // Repaint when data changes; the repaintNotifier handles active stroke changes
    //
    // imageCache is a Map<String, ui.Image>; in Dart the default `!=`
    // is identity, so every state.copyWith(imageCache: Map.from(...))
    // produced a fresh reference and forced a repaint of the entire
    // 100-stroke page even when the contents were functionally
    // identical. Compare the map by length + per-key identity of the
    // ui.Image instances instead — same-content maps no longer
    // false-trigger repaints (~70% of idle CPU on a 215-page notebook
    // came from this).
    // !identical instead of != throughout — every comparison field is
    // either an immutable freezed object (PageData, LassoSelection,
    // ShapeData) or a List/Map. With `!=`, freezed runs deep equality
    // on PageData, walking all 200 stroke points × 80 points per
    // shouldRepaint call. With `!identical`, page mutation always
    // produces a new ref so identity is sufficient AND ~1000× faster.
    return !identical(pageData, oldDelegate.pageData) ||
        !identical(activeStroke, oldDelegate.activeStroke) ||
        !identical(lassoSelection, oldDelegate.lassoSelection) ||
        !identical(lassoPath, oldDelegate.lassoPath) ||
        shapePreview != oldDelegate.shapePreview ||
        !identical(recognizedShapePreview, oldDelegate.recognizedShapePreview) ||
        zoom != oldDelegate.zoom ||
        panOffset != oldDelegate.panOffset ||
        infiniteCanvas != oldDelegate.infiniteCanvas ||
        !identical(corruptAssetIds, oldDelegate.corruptAssetIds) ||
        !_imageCacheEqual(imageCache, oldDelegate.imageCache);
  }

  static bool _imageCacheEqual(
      Map<String, ui.Image> a, Map<String, ui.Image> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!identical(b[entry.key], entry.value)) return false;
    }
    return true;
  }

  /// Process-wide picture cache for the static page-content layer.
  /// Bounded LRU so memory doesn't grow unboundedly as the user flips
  /// through pages.
  static final _staticPictureCache = _StaticPictureCache();

  /// Per-StrokeData cache of bucketed Path runs. Skips the expensive
  /// Catmull-Rom interpolation + width bucketing on every Picture
  /// rebuild — the interpolation result depends only on the stroke
  /// points + zoom-bucket, neither of which change as the user erases
  /// other strokes on the same page. Entries are GC'd along with their
  /// owning StrokeData (Expando = weak-keyed map).
  static final Expando<_StrokeCacheEntry> _strokePathCache = Expando();

  /// Brush has 3 overlapping layers per stroke, each with its own
  /// width multiplier and alpha — needs a separate cache shape.
  static final Expando<_BrushCacheEntry> _brushPathCache = Expando();

  /// Cached "does this page have any image element?" answer. Page
  /// mutations produce new PageData refs so the cache lifetime is
  /// naturally bounded; missing entries lazy-fill on first read.
  static final Expando<bool> _hasImageCache = Expando();
}

class _PathRun {
  final Path path;
  final double width;
  const _PathRun(this.path, this.width);
}

class _StrokeCacheEntry {
  final int zoomBucket;
  final List<_PathRun> runs;
  const _StrokeCacheEntry(this.zoomBucket, this.runs);
}

class _BrushLayer {
  final double alpha;
  final List<_PathRun> runs;
  const _BrushLayer(this.alpha, this.runs);
}

class _BrushCacheEntry {
  final int zoomBucket;
  final List<_BrushLayer> layers;
  const _BrushCacheEntry(this.zoomBucket, this.layers);
}

/// Lightweight struct for Catmull-Rom interpolated points with pre-computed width.
class _InterpolatedPoint {
  final double x, y, pressure, w;
  const _InterpolatedPoint(this.x, this.y, this.pressure, this.w);
}

/// LRU cache of the static-content `ui.Picture` keyed by page identity +
/// quantised zoom (and the asset-cache+selection state, since both can
/// affect the rendered output). Bounded so a notebook with hundreds of
/// pages doesn't pile up retained pictures across page flips.
///
/// Cache miss conditions (any one of these triggers a rebuild):
///   - Different `pageData` reference (page edited or different page)
///   - Different `imageCache` key/value identity set
///   - Different lasso-selection (which IDs are highlighted shifts the
///     drawing because selected ids may be transformed)
///   - Zoom moved beyond the quantisation bucket — needed because
///     adaptive Catmull-Rom interpolates more densely at higher zoom,
///     and replaying a low-zoom picture at high zoom looks polygonal.
class _StaticPictureCache {
  static const int _maxEntries = 6;
  // Was 0.1 → mouse-wheel zoom (which moves zoom by ~10% per tick) crossed a
  // bucket on every event and invalidated the Picture cache continuously.
  // 0.5 means strokes interpolated for zoom 1.0 are reused up to ~1.49 and
  // again for 1.5–1.99 etc. — a few buckets in the typical 0.3–5.0 range
  // instead of dozens. The Catmull-Rom segment density at record time is
  // sufficient that replaying within a 50 % zoom window stays visually
  // smooth.
  static const double _zoomQuantum = 0.5;

  final List<_StaticPictureEntry> _entries = [];

  ui.Picture? lookup({
    required PageData pageData,
    required double zoom,
    required LassoSelection? lassoSelection,
    required int imageSig,
  }) {
    final zoomBucket = (zoom / _zoomQuantum).round();
    final lassoKey = _lassoKey(lassoSelection);
    for (var i = _entries.length - 1; i >= 0; i--) {
      final e = _entries[i];
      if (identical(e.pageData, pageData) &&
          e.zoomBucket == zoomBucket &&
          e.lassoKey == lassoKey &&
          e.imageSig == imageSig) {
        // Move to MRU end
        _entries.removeAt(i);
        _entries.add(e);
        return e.picture;
      }
    }
    return null;
  }

  void store({
    required PageData pageData,
    required double zoom,
    required LassoSelection? lassoSelection,
    required int imageSig,
    required ui.Picture picture,
  }) {
    final zoomBucket = (zoom / _zoomQuantum).round();
    final lassoKey = _lassoKey(lassoSelection);
    _entries.add(_StaticPictureEntry(
      pageData: pageData,
      zoomBucket: zoomBucket,
      lassoKey: lassoKey,
      imageSig: imageSig,
      picture: picture,
    ));
    while (_entries.length > _maxEntries) {
      // Dispose the LRU picture to release GPU/native memory.
      final evicted = _entries.removeAt(0);
      evicted.picture.dispose();
    }
  }

  /// Memoised cache-key per LassoSelection identity. Without this the
  /// O(N) toList+sort+join ran on every paint, even on cache HITS where
  /// the selection hadn't actually changed.
  static final Expando<String> _lassoKeyExpando = Expando();

  static String _lassoKey(LassoSelection? sel) {
    if (sel == null) return '';
    final cached = _lassoKeyExpando[sel];
    if (cached != null) return cached;
    final ids = sel.selectedIds.toList()..sort();
    final key = ids.join(',');
    _lassoKeyExpando[sel] = key;
    return key;
  }

  /// Drop every entry and dispose the underlying ui.Pictures. Called on
  /// notebook close so closed notebooks' PageData refs and Skia native
  /// buffers don't linger as zombie memory across notebook switches.
  void clearAll() {
    for (final e in _entries) {
      try { e.picture.dispose(); } catch (_) {}
    }
    _entries.clear();
  }

}

class _StaticPictureEntry {
  final PageData pageData;
  final int zoomBucket;
  final String lassoKey;
  final int imageSig;
  final ui.Picture picture;

  _StaticPictureEntry({
    required this.pageData,
    required this.zoomBucket,
    required this.lassoKey,
    required this.imageSig,
    required this.picture,
  });
}
