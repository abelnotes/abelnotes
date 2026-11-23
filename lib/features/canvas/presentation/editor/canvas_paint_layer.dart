// The page itself: a painter watching only viewport, pages and the pen, so a
// pan, zoom or stroke repaints this and nothing else.

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/features/canvas/data/zoom_snapshot.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_pointer_controller.dart';
import 'package:abelnotes/features/canvas/presentation/pdf_sharpener.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

class CanvasPaintLayer extends StatelessWidget {
  const CanvasPaintLayer({
    super.key,
    required this.ptr,
    required this.zoomSnapshot,
    required this.pdfSharpener,
    required this.pdfTileVersion,
    required this.canvasSize,
    required this.fallback,
    required this.fallbackPage,
  });

  final EditorPointerController ptr;
  final ZoomSnapshot zoomSnapshot;
  final PdfSharpener? Function() pdfSharpener;
  final ValueListenable<int> pdfTileVersion;
  final Size canvasSize;

  /// State and page to paint only if the provider has none yet.
  final CanvasState fallback;
  final PageData fallbackPage;

  static String _toolTypeString(CanvasTool tool) {
    switch (tool) {
      case CanvasTool.pen:
        return 'pen';
      case CanvasTool.calligraphy:
        return 'calligraphy';
      case CanvasTool.ballpoint:
        return 'ballpoint';
      case CanvasTool.brush:
        return 'brush';
      case CanvasTool.highlighter:
        return 'highlighter';
      default:
        return 'pen';
    }
  }

  /// Fixed device-pixel-ratio to rasterize math at, not multiplied by zoom so
  /// the cache key is stable across a pinch.
  static double mathPixelRatio(BuildContext context) =>
      MediaQuery.of(context).devicePixelRatio.clamp(2.0, 3.5);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: RepaintBoundary(
        // ── Inner viewport watch ──
        // The parent build's `ref.watch` deliberately
        // EXCLUDES panOffset/zoom so pan/wheel events don't
        // rebuild the editor chrome. But the painter still
        // needs them — wrap CustomPaint in a Consumer that
        // watches just `(zoom, panOffset)` so panning
        // rebuilds only this CustomPaint subtree (a
        // ~1-widget tree), and the rest of the UI is
        // untouched.
        child: Consumer(
          key: const ValueKey('canvas-paint'),
          builder: (context, ref, _) {
            // A toggle in Settings changes how strokes are drawn: rebuild the
            // painter, which then repaints with the new width rule.
            ref.watch(appSettingsProvider.select((s) => s.speedWidth));
            ref.listen(appSettingsProvider.select((s) => s.speedWidth),
                (_, v) => CanvasRenderEngine.speedWidth = v);
            // Watch viewport + imageCache + pages so the
            // painter rebuilds on pan/zoom, when a new
            // asset image is decoded, AND when the eraser
            // / draw / undo commits a new pages map. The
            // chrome's parent select excludes ALL of
            // those (they tick at 20-120 Hz during
            // interaction), so this Consumer is the
            // *only* widget that rebuilds for those
            // changes.
            ref.watch(canvasProvider.select((s) => s == null
                ? const (zoom: 1.0, panOffset: Offset.zero)
                : (zoom: s.zoom, panOffset: s.panOffset)));
            // imageCache is observed via the painter's
            // repaintNotifier (which now includes the
            // notifier's `imageCacheVersion`) — pulling
            // it through Riverpod here used to fire a
            // full state-cascade and shouldRepaint walk
            // on every PDF-import decode.
            ref.watch(canvasProvider.select((s) => s?.pages));
            // What the painter takes from the state besides the viewport: the
            // page on show, the pen it would draw with, the selection, the
            // recognised shape and the page kind.
            ref.watch(canvasProvider.select((s) => s == null
                ? null
                : (
                    page: s.currentPageIndex,
                    tool: _toolTypeString(s.currentTool),
                    color: s.toolSettings.color,
                    width: s.toolSettings.strokeWidth,
                    lasso: s.lassoSelection,
                    shape: s.recognizedShape,
                    scratch: s.isScratch,
                  )));
            // Read full state fresh — the parent's
            // fallback (closure) has stale fields
            // because parent didn't rebuild for any of
            // the above. Use `s.currentPage` (computed
            // from the live `pages` map) as the painter's
            // pageData; falling back to the parent's
            // captured `currentPage` only for the very
            // first paint when ref.read returns null.
            final s = ref.read(canvasProvider) ?? fallback;
            final livePage = s.currentPage ?? fallbackPage;
            return CustomPaint(
              painter: CanvasRenderEngine(
                pageData: livePage,
                pdfTilesFor: (asset) =>
                    pdfSharpener()?.tilesFor(asset) ?? const [],
                pdfTileVersion: () => pdfTileVersion.value,
                // Pass nothing as the snapshot — the painter
                // resolves the active stroke via the getter
                // every frame so a captured snapshot can
                // never go stale between widget rebuilds.
                activeStroke: null,
                activeStrokeGetter: () {
                  // Notifier always wins when it has points
                  // (live drawing). Fall back to Riverpod's
                  // activeStroke (carries the very first
                  // point committed via startStroke before
                  // the first PointerMove). Either may be
                  // null between strokes.
                  if (ptr.activeStroke.points.isNotEmpty) {
                    return ptr.activeStroke.displayPoints;
                  }
                  final liveS = ref.read(canvasProvider);
                  final stroke = liveS?.activeStroke;
                  if (stroke != null && stroke.isNotEmpty) {
                    return stroke;
                  }
                  return null;
                },
                activeToolType: _toolTypeString(s.currentTool),
                activeColor: s.toolSettings.color,
                activeWidth: s.toolSettings.strokeWidth,
                lassoSelection: s.lassoSelection,
                // Live transform during drag/rotate/scale —
                // bypasses Riverpod so the page repaints
                // without rebuilding the widget tree.
                // ALWAYS pass the callback (it returns
                // null when no gesture is in flight) —
                // otherwise the CustomPaint, captured
                // before ptr.lassoTransform.begin()
                // ran, would have a null callback for
                // the entire gesture and the painter
                // would fall back to stale Riverpod
                // state.
                liveLassoTransform: () => ptr.lassoTransform.isActive
                    ? ptr.lassoTransform.snapshot()
                    : null,
                liveElementTransform: () => ptr.elementTransform.isActive
                    ? (
                        elementId: ptr.elementTransform.elementId!,
                        dragOffset: ptr.elementTransform.dragOffset,
                        rotationDelta: ptr.elementTransform.rotationDelta,
                        scaleW: ptr.elementTransform.scaleW,
                        scaleH: ptr.elementTransform.scaleH,
                      )
                    : null,
                lassoPath:
                    ptr.lassoPath.isActive && ptr.lassoPath.points.isNotEmpty
                        ? ptr.lassoPath.points
                        : (s.lassoPath.isNotEmpty ? s.lassoPath : null),
                // ALWAYS pass the getter (returns the
                // notifier's points, which is empty when no
                // lasso is in flight) — same reasoning as
                // liveLassoTransform above. If we gated it
                // on isActive, the painter captured before
                // the user starts a fresh lasso (e.g. just
                // after switching from pen→lasso) held a
                // null getter and fell back to the stale
                // `lassoPath` field — also null at that
                // moment because s.lassoPath is empty —
                // so the marquee stayed invisible until
                // some later state change rebuilt the
                // CustomPaint with the getter wired up.
                lassoPathGetter: () => ptr.lassoPath.points,
                laserTrailGetter: () => ptr.laserStroke.points,
                shapePreview: (s.shapeStartPos != null && s.shapeEndPos != null)
                    ? (
                        s.shapeStartPos!,
                        s.shapeEndPos!,
                        s.toolSettings.shapeType
                      )
                    : null,
                recognizedShapePreview: s.recognizedShape,
                zoom: s.zoom,
                panOffset: s.panOffset,
                infiniteCanvas: s.isScratch,
                zoomSnapshot: kIsWeb ? zoomSnapshot : null,
                devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
                imageCache: s.imageCache,
                // This Consumer intentionally doesn't watch
                // s.imageCache (avoids a per-decode rebuild
                // cascade on PDF imports), so when a freshly
                // decoded image lands the widget tree stays
                // put. The painter's repaintNotifier still
                // fires `paint()`, but with the snapshot
                // captured at the last build → the new image
                // was invisible until the user panned/zoomed.
                // This getter lets the painter read the LIVE
                // map on every frame, so a decoded image
                // appears immediately on the next repaint.
                liveImageCacheGetter: () =>
                    ref.read(canvasProvider)?.imageCache ?? const {},
                corruptAssetIds:
                    ref.read(canvasProvider.notifier).corruptAssetIds,
                // Typeset-math raster cache — same live-read +
                // miss-then-async-fill pattern as images. A
                // FIXED pixel ratio (not × zoom) keeps the
                // cache key stable across zoom so equations
                // don't re-rasterize on every pinch; the
                // bitmap scales like an image instead.
                mathCache: ref.read(canvasProvider.notifier).mathCache,
                liveMathCacheGetter: () =>
                    ref.read(canvasProvider.notifier).mathCache,
                failedMathKeys:
                    ref.read(canvasProvider.notifier).failedMathKeys,
                mathPixelRatio: mathPixelRatio(context),
                onMathCacheMiss: (d) => ref
                    .read(canvasProvider.notifier)
                    .requestMathRaster(d.latex, d.color, d.fontSize,
                        d.displayMode, mathPixelRatio(context)),
                repaintNotifier: ptr.repaintNotifier,
              ),
              // willChange: true tells Skia "do NOT
              // bother rasterizing this layer to a
              // GPU texture cache between frames" —
              // ESSENTIAL during pan. With
              // willChange:false + shouldRepaint=true
              // (panOffset changes every frame),
              // Flutter would create+invalidate the
              // texture cache on every paint, paying
              // GPU upload cost for nothing. Our
              // own ui.Picture cache (in render_engine)
              // already memoises the drawing commands
              // at the right granularity (per
              // pageData/zoom-bucket) — Skia's
              // post-transform raster cache is
              // counterproductive on a panning canvas.
              // isComplex:true was hinting Skia to
              // cache, which doubled down on the same
              // mistake — also removed.
              willChange: true,
              size: canvasSize,
            );
          },
        ),
      ),
    );
  }
}
