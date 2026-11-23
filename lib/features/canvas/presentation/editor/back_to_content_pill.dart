// Infinite page: a floating pill that brings the content back when the user
// has panned or zoomed it fully off-screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';

/// Positioned: put it straight in a Stack. Watches the full provider: the
/// enclosing build select()s pan and zoom away, so the pill tracks them itself.
class BackToContentPill extends ConsumerWidget {
  const BackToContentPill({super.key});

  bool _offScreen(CanvasNotifier notifier, CanvasState s) {
    if (!s.isScratch || s.zoom <= 0) return false;
    final vp = notifier.viewportSize;
    if (vp == null) return false;
    final bbox = notifier.currentPageContentBounds();
    if (bbox == null) return false;
    // Scratch transform: screen = panOffset + P x zoom, so invert the
    // viewport corners into page space.
    final visible = Rect.fromLTRB(
      -s.panOffset.dx / s.zoom,
      -s.panOffset.dy / s.zoom,
      (vp.width - s.panOffset.dx) / s.zoom,
      (vp.height - s.panOffset.dy) / s.zoom,
    );
    return !visible.overlaps(bbox.inflate(40));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(canvasProvider);
    if (live == null || !_offScreen(ref.read(canvasProvider.notifier), live)) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 0,
      right: 0,
      bottom: 28,
      child: Center(
        child: Material(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => ref.read(canvasProvider.notifier).fitToContent(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HwIcon('fit', size: 15, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context).csBackToContent,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
