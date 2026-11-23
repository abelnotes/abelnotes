// The strip of page thumbnails under the page, or its handle when collapsed.
// Nothing for an infinite scratch page.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/search/notebook_find_bar.dart';
import 'package:abelnotes/ui/editor/hw_editor_chrome.dart';

class EditorPageStrip extends ConsumerWidget {
  const EditorPageStrip({
    super.key,
    required this.find,
    required this.chapterLabel,
    required this.chapterShortLabel,
    required this.onChapterTap,
    required this.onPageSecondary,
    required this.onAllPagesTap,
  });

  final NotebookFindController find;
  final String Function(CanvasState state) chapterLabel;
  final String? Function(CanvasState state) chapterShortLabel;
  final ValueChanged<Rect> onChapterTap;
  final void Function(int pageNumber, Offset globalPosition) onPageSecondary;
  final VoidCallback onAllPagesTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isScratch =
        ref.watch(canvasProvider.select((s) => s?.isScratch ?? false));
    final show = ref.watch(appSettingsProvider.select((s) => s.showPageStrip));
    // The strip's inputs; the page lists are derived from them below.
    ref.watch(canvasProvider.select((s) => s == null
        ? null
        : (
            s.document,
            s.activeChapterId,
            s.currentPageIndex,
            s.previousPageIndex,
          )));
    final state = ref.read(canvasProvider);
    // Infinite scratch canvas: no page strip chrome at all.
    if (state == null || isScratch) return const SizedBox.shrink();
    if (!show) {
      return HwPageStripHandle(
        onExpand: () =>
            ref.read(appSettingsProvider.notifier).setShowPageStrip(true),
      );
    }
    final notifier = ref.read(canvasProvider.notifier);
    return ListenableBuilder(
      listenable: find,
      builder: (_, __) => HwBottomPageStrip(
        markedPages: find.isOpen
            ? {for (final i in find.pagesWithMatches) i + 1}
            : const {},
        chapterLabel: chapterLabel(state),
        chapterShortLabel: chapterShortLabel(state),
        onChapterTap: onChapterTap,
        // Only pages of the active chapter (or all when no filter is active).
        pageNumbers: [
          for (final i in state.filteredPageIndices) i + 1,
        ],
        currentPage: state.currentPageIndex + 1,
        previousPage: (() {
          final prev = state.previousPageIndex;
          if (prev == null) return null;
          if (prev < 0 || prev >= state.document.pages.length) return null;
          return prev + 1;
        })(),
        onPageTap: (n) => notifier.goToPage(n - 1),
        onPageSecondary: onPageSecondary,
        onAllPagesTap: onAllPagesTap,
        onCollapse: () =>
            ref.read(appSettingsProvider.notifier).setShowPageStrip(false),
      ),
    );
  }
}
