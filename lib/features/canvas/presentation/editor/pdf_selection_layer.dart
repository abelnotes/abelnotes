// Highlight overlay and copy button for the active PDF text selection.
// Highlights ignore pointers so the canvas pipeline (which drives the
// selection) keeps getting events; only the copy button is tappable.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/pdf_text_selection.dart';
import 'package:abelnotes/features/canvas/presentation/editor/page_view_transform.dart';
import 'package:abelnotes/features/canvas/presentation/editor/pdf_selection_painter.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Positioned.fill: the PDF selection over the page. Re-projects on zoom, pan
/// and page change; [selectionFor] gives the page's controller or null.
class PdfSelectionOverlay extends StatelessWidget {
  const PdfSelectionOverlay({
    super.key,
    required this.selectionFor,
    required this.fallback,
    required this.canvasSize,
    required this.onCopy,
  });

  final PdfTextSelectionController? Function(CanvasState state) selectionFor;
  final CanvasState fallback;
  final Size canvasSize;
  final void Function(String text) onCopy;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Consumer(
        builder: (_, ref, __) {
          ref.watch(canvasProvider.select((s) => (
                zoom: s?.zoom ?? 1.0,
                panOffset: s?.panOffset ?? Offset.zero,
                pages: s?.pages,
                page: s?.currentPageIndex,
              )));
          final live = ref.read(canvasProvider) ?? fallback;
          // The overlay shows whenever the page has a text layer; it draws
          // nothing until a selection exists. No tool gating.
          final sel = selectionFor(live);
          if (sel == null) return const SizedBox.shrink();
          return PdfSelectionLayer(
            selection: sel,
            state: live,
            canvasSize: canvasSize,
            onCopy: onCopy,
          );
        },
      ),
    );
  }
}

class PdfSelectionLayer extends StatelessWidget {
  const PdfSelectionLayer({
    super.key,
    required this.selection,
    required this.state,
    required this.canvasSize,
    required this.onCopy,
  });

  final PdfTextSelectionController selection;
  final CanvasState state;
  final Size canvasSize;
  final void Function(String text) onCopy;

  @override
  Widget build(BuildContext context) {
    final view = PageViewTransform.of(state, canvasSize);
    final screenScale = view.renderScale * state.zoom;
    Rect pageRectToScreen(Rect r) {
      final tl = view.toScreen(r.topLeft);
      return Rect.fromLTWH(
          tl.dx, tl.dy, r.width * screenScale, r.height * screenScale);
    }

    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        final p = HwThemeScope.of(context);
        final screenRects = [
          for (final r in selection.selectedPageRects()) pageRectToScreen(r)
        ];
        final boundsPage = selection.selectionBoundsPage();
        return Stack(
          children: [
            IgnorePointer(
              child: CustomPaint(
                size: canvasSize,
                painter: PdfSelectionPainter(
                    screenRects, p.accentDeep.withValues(alpha: 0.28)),
              ),
            ),
            if (boundsPage != null)
              _copyButton(context, pageRectToScreen(boundsPage), p),
          ],
        );
      },
    );
  }

  Widget _copyButton(BuildContext context, Rect screenBounds, HwPalette p) {
    const btnW = 104.0, btnH = 36.0, gap = 8.0;
    double left = screenBounds.right - btnW;
    double top = screenBounds.top - btnH - gap;
    if (top < 8) top = screenBounds.bottom + gap; // flip below if no room above
    left = left.clamp(8.0, max(8.0, canvasSize.width - btnW - 8));
    top = top.clamp(8.0, max(8.0, canvasSize.height - btnH - 8));
    return Positioned(
      left: left,
      top: top,
      child: Material(
        color: p.ink0,
        borderRadius: BorderRadius.circular(18),
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onCopy(selection.selectedText()),
          child: SizedBox(
            width: btnW,
            height: btnH,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                HwIcon('copy', size: 16, color: p.paper0),
                const SizedBox(width: 6),
                Text(AppLocalizations.of(context).csCopy,
                    style: TextStyle(
                        color: p.paper0,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
