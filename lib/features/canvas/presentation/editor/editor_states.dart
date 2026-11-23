// What the editor shows around the page besides the page itself: the
// presentation controls, the preview bar, and the views for a closed
// notebook or a page that is not there.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_widgets.dart';
import 'package:abelnotes/features/canvas/presentation/missing_page_view.dart';
import 'package:abelnotes/features/canvas/presentation/notebook_preview.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/screens/library_screen.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Small, corner-bounded controls only, never a full-screen tap layer: the
/// canvas underneath must keep receiving every pointer event for the laser.
/// A Stack child.
class PresentationOverlay extends ConsumerWidget {
  const PresentationOverlay({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(canvasProvider.notifier);
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            top: 16,
            right: 16,
            child: PresentationIconButton(
              icon: Icons.close_rounded,
              onTap: onExit,
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            child: PresentationIconButton(
              icon: Icons.chevron_left_rounded,
              onTap: () => notifier.prevPage(resetViewport: true),
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: PresentationIconButton(
              icon: Icons.chevron_right_rounded,
              onTap: () => notifier.nextPage(resetViewport: true),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says the notebook is only being looked at, and offers to keep it.
class NotebookPreviewBar extends ConsumerWidget {
  const NotebookPreviewBar({super.key, required this.onChoice});

  final void Function(PreviewChoice choice) onChoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(notebookPreviewProvider);
    final mirror = ref.watch(windowMirrorProvider);
    if (preview == null && mirror == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (preview == null) {
      return Material(
        color: scheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Icon(Icons.visibility_outlined,
                size: 18, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l10n.winMirrorBanner,
                  style: TextStyle(color: scheme.onSecondaryContainer)),
            ),
          ]),
        ),
      );
    }
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Icon(Icons.visibility_outlined,
                size: 18, color: scheme.onSecondaryContainer),
            Text(
                preview.libraryCopyId != null
                    ? l10n.csPreviewBannerOwned(preview.fileName)
                    : l10n.csPreviewBanner(preview.fileName),
                style: TextStyle(color: scheme.onSecondaryContainer)),
            if (preview.libraryCopyId != null)
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: scheme.onSecondaryContainer),
                onPressed: () => onChoice(PreviewChoice.openLibraryCopy),
                child: Text(l10n.csPreviewOpenMine),
              ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: scheme.onSecondaryContainer,
                  foregroundColor: scheme.secondaryContainer),
              onPressed: () => onChoice(PreviewChoice.addToLibrary),
              child: Text(preview.libraryCopyId != null
                  ? l10n.csPreviewAddCopy
                  : l10n.csPreviewAdd),
            ),
          ],
        ),
      ),
    );
  }
}

/// The notebook was closed under the editor: nothing to edit, a way out.
/// [closing] hides the button while the exit animation of an ordinary close
/// is still running.
class NoNotebookView extends StatelessWidget {
  const NoNotebookView({super.key, required this.closing});

  final bool closing;

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Scaffold(
      backgroundColor: p.paper1,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocalizations.of(context).csNoNotebookOpen,
                style: TextStyle(color: p.ink2)),
            const SizedBox(height: 16),
            // Safety net for when the auto-pop can't fire (this route is the
            // only one on the stack): rebuilding the library is still an exit.
            if (!closing)
              FilledButton(
                onPressed: () {
                  final navigator = Navigator.of(context);
                  if (navigator.canPop()) {
                    navigator.pop();
                  } else {
                    navigator.pushReplacement(MaterialPageRoute(
                      builder: (_) => const LibraryScreenV2(),
                    ));
                  }
                },
                child: Text(
                    AppLocalizations.of(context).chromeBackToLibraryTooltip),
              ),
          ],
        ),
      ),
    );
  }
}

/// An open notebook whose current page has no data: while pages are still
/// loading a blank, else recovery actions, or "no pages" for an empty book.
class MissingPageState extends ConsumerWidget {
  const MissingPageState({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(canvasProvider.select((s) => s == null
        ? null
        : (
            title: s.metadata.title,
            pages: s.document.pages,
            index: s.currentPageIndex,
          )));
    if (s == null) return const SizedBox.shrink();
    final isMissing =
        s.pages.isNotEmpty && s.index >= 0 && s.index < s.pages.length;
    // Not loaded yet is not missing: never offer recovery for it.
    if (isMissing && ref.read(canvasProvider.notifier).pagesLoading.value) {
      return ColoredBox(color: HwThemeScope.of(context).paper1);
    }
    if (isMissing) {
      return MissingPageView(
        key: ValueKey(s.pages[s.index].fileName),
        title: s.title,
        onBack: onBack,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined,
                size: 64, color: HwTheme.syncPending),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).csNoPages,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
