// ═══════════════════════════════════════════════════════════════
//  math_rasterizer.dart
//
//  Rasterizes a typeset LaTeX expression to a ui.Image entirely
//  offscreen (no mounted host widget), via a self-contained render
//  pipeline. Safe to call from the paint-miss handler, the thumbnail
//  service, and export. Mirrors ThumbnailService's "render offscreen →
//  ui.Image → dispose" philosophy, but for an arbitrary Flutter widget
//  (the flutter_math_fork Math.tex layout) instead of a CustomPainter.
//
//  Only the LaTeX source + style are ever persisted (see MathData); the
//  pixels produced here are a derived, re-creatable cache.
// ═══════════════════════════════════════════════════════════════

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// A rasterized equation: the GPU image plus the LOGICAL size it occupies
/// (image.width == size.width * pixelRatio).
typedef MathRaster = ({ui.Image image, Size size});

class MathRasterizer {
  /// Renders [latex] in [color] at logical base [fontSize], producing a
  /// [ui.Image] at [pixelRatio] device pixels per logical pixel, plus the
  /// LOGICAL [Size] the equation occupies. Returns null if the platform has
  /// no implicit view or the pipeline fails. A LaTeX parse error does NOT
  /// fail — flutter_math_fork's onErrorFallback renders the raw source as
  /// plain monospace text instead, so a typo degrades to readable text.
  static Future<MathRaster?> rasterize({
    required String latex,
    required Color color,
    required double fontSize,
    bool displayMode = true,
    double pixelRatio = 3.0,
  }) async {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return null;

    // The widget to rasterize. NO Center/Align wrapper: under the (finite)
    // logical constraints below an Align does NOT shrink-wrap — it EXPANDS to
    // fill them, which blew the RenderRepaintBoundary up to maxDim×maxDim and
    // made toImage() return a 0×0 image (and measureMath report a giant box).
    // Math.tex sizes to the equation's intrinsic extent on its own. MediaQuery
    // is required because Math.tex.build() reads textScaleFactorOf/boldTextOf
    // (would throw without an ancestor); Directionality is required for TeX
    // text layout. textScaleFactor:1.0 keeps the size deterministic.
    final Widget content = MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Math.tex(
          latex,
          mathStyle: displayMode ? MathStyle.display : MathStyle.text,
          textStyle: TextStyle(color: color, fontSize: fontSize),
          textScaleFactor: 1.0,
          onErrorFallback: (FlutterMathException e) => Text(
            latex,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );

    // ── Offscreen render pipeline (Flutter 3.44 signatures) ──
    final RenderRepaintBoundary boundary = RenderRepaintBoundary();

    // Loose LOGICAL constraints → the subtree lays out at its intrinsic size
    // (not clipped, not stretched). physical = logical * pixelRatio. Do NOT
    // pre-scale the logical constraints by pixelRatio — toImage() already
    // multiplies by it.
    const double maxDim = 100000.0;
    final ViewConfiguration configuration = ViewConfiguration(
      logicalConstraints:
          const BoxConstraints(maxWidth: maxDim, maxHeight: maxDim),
      physicalConstraints: const BoxConstraints(
        maxWidth: maxDim * 4,
        maxHeight: maxDim * 4,
      ),
      devicePixelRatio: pixelRatio,
    );

    final PipelineOwner pipelineOwner = PipelineOwner();
    final RenderView renderView = RenderView(
      view: view,
      configuration: configuration,
      child: RenderPositionedBox(
        alignment: Alignment.topLeft,
        child: boundary,
      ),
    );

    final BuildOwner buildOwner = BuildOwner(focusManager: FocusManager());

    // Assigning rootNode is what attaches renderView to the owner; calling
    // renderView.attach() as well double-attaches it, which trips an assert
    // ("already has an owner") in debug — the rasterize then throws, math
    // never leaves its placeholder. prepareInitialFrame must run AFTER the
    // node is attached (it needs a non-null owner).
    pipelineOwner.rootNode = renderView;
    renderView.prepareInitialFrame();

    RenderObjectToWidgetElement<RenderBox>? rootElement;
    try {
      rootElement = RenderObjectToWidgetAdapter<RenderBox>(
        container: boundary,
        child: content,
      ).attachToRenderTree(buildOwner);

      buildOwner.buildScope(rootElement);
      buildOwner.finalizeTree();

      pipelineOwner.flushLayout();
      pipelineOwner.flushCompositingBits();
      pipelineOwner.flushPaint();

      final Size logicalSize = boundary.size;
      if (logicalSize.isEmpty) return null;

      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      return (image: image, size: logicalSize);
    } catch (e, st) {
      debugPrint('[MathRasterizer] rasterize failed for "$latex": $e\n$st');
      return null;
    } finally {
      // Tear down the pipeline so no RenderObjects/Elements leak.
      try {
        rootElement?.update(
          RenderObjectToWidgetAdapter<RenderBox>(container: boundary),
        );
        buildOwner.finalizeTree();
      } catch (_) {}
      renderView.detach();
      renderView.dispose();
    }
  }
}

/// Cache key for a rasterized equation: latex | colorARGB | fontSize-bucket
/// | displayMode | pixelRatio-bucket. fontSize bucketed to 0.5 px and
/// pixelRatio to 0.5 (capped at 4×) so pan/zoom jitter doesn't thrash the
/// cache (same spirit as render_engine's zoom bucket).
String mathCacheKey(
  String latex,
  int colorArgb,
  double fontSize,
  bool displayMode,
  double pixelRatio,
) {
  final fs = (fontSize * 2).round();
  final prb = (pixelRatio.clamp(1.0, 4.0) * 2).round();
  return '$latex|$colorArgb|$fs|${displayMode ? 1 : 0}|$prb';
}
