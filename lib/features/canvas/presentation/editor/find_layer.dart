// Find in notebook, drawn over the page: the match highlights and the bar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/editor/page_view_transform.dart';
import 'package:abelnotes/features/search/notebook_find_bar.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Marker swipes on the matches of the page on screen, while the find is open.
class FindHighlightsLayer extends StatelessWidget {
  const FindHighlightsLayer({
    super.key,
    required this.find,
    required this.fallback,
    required this.canvasSize,
  });

  final NotebookFindController find;
  /// State to draw from before the provider has one.
  final CanvasState fallback;
  final Size canvasSize;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: find,
      builder: (_, __) {
        if (!find.isOpen) return const SizedBox.shrink();
        return Consumer(builder: (_, ref2, __) {
          ref2.watch(canvasProvider.select((s) => (
                zoom: s?.zoom ?? 1.0,
                panOffset: s?.panOffset ?? Offset.zero,
                pages: s?.pages,
                document: s?.document,
                page: s?.currentPageIndex,
              )));
          final live = ref2.read(canvasProvider) ?? fallback;
          find.sync(live.document, live.pages);
          return _highlights(live);
        });
      },
    );
  }

  Widget _highlights(CanvasState state) {
    final page = state.currentPage;
    if (page == null) return const SizedBox.shrink();
    final current = find.currentMatch;
    final view = PageViewTransform.of(state, canvasSize);
    final rs = view.renderScale;
    final center = view.center;
    Rect toScreen(Rect r) => Rect.fromPoints(
        (r.topLeft * rs + center) * state.zoom + state.panOffset,
        (r.bottomRight * rs + center) * state.zoom + state.panOffset);
    final others = <Rect>[], now = <Rect>[];
    for (final m in find.matches) {
      if (m.pageIndex != state.currentPageIndex) continue;
      final out = m == current ? now : others;
      for (final r in find.rectsOf(page, m)) {
        out.add(toScreen(r));
      }
    }
    if (others.isEmpty && now.isEmpty) return const SizedBox.shrink();
    // Paper stays light in the dark theme: logo blue, not the theme accent.
    return IgnorePointer(
      child: CustomPaint(
        size: canvasSize,
        painter: FindHighlightPainter(
          others: others,
          current: now,
          marker: HwTheme.teal,
          ink: Color.lerp(HwTheme.teal, Colors.black, 0.35)!,
        ),
      ),
    );
  }
}

/// The find bar, top right of the canvas (full width when narrow).
class FindBarOverlay extends StatelessWidget {
  const FindBarOverlay({
    super.key,
    required this.find,
    required this.text,
    required this.focus,
    required this.canvasSize,
    required this.top,
    required this.onChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
    required this.onTapOutside,
  });

  final NotebookFindController find;
  final TextEditingController text;
  final FocusNode focus;
  final Size canvasSize;
  final double top;
  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;
  final VoidCallback onTapOutside;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: find,
      builder: (_, __) {
        // Always a positioned child: a non-positioned one would give the
        // Stack its own size (0x0 here) wherever nothing above forces the
        // canvas size (web, no drop zone).
        if (!find.isOpen) {
          return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
        }
        final narrow = canvasSize.width < 600;
        return Positioned(
          top: top,
          right: 12,
          left: narrow ? 12 : null,
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: narrow ? double.infinity : 440),
            child: SizedBox(
              width: narrow ? null : 440,
              child: Consumer(builder: (_, ref2, __) {
                // Counter follows edits made while the bar is open.
                final live = ref2.watch(canvasProvider
                    .select((s) => (pages: s?.pages, document: s?.document)));
                if (live.pages != null && live.document != null) {
                  find.sync(live.document!, live.pages!);
                }
                return NotebookFindBar(
                  controller: find,
                  text: text,
                  focus: focus,
                  onChanged: onChanged,
                  onNext: onNext,
                  onPrevious: onPrevious,
                  onClose: onClose,
                  onTapOutside: onTapOutside,
                );
              }),
            ),
          ),
        );
      },
    );
  }
}
