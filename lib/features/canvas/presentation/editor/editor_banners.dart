// Transient hints over the page: the recognised-shape confirmation, placement
// hints for a symbol or a paste, the undo/redo flash and the page-swipe
// previews. Each is a Stack child (Positioned or empty).

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Which page-swipe preview is on screen (at most one).
enum PageHint { none, newPage, nextPage, prevPage }

/// "Shape recognised" pill with confirm and cancel, while a recognised shape
/// is being adjusted.
class ShapeRecognizedBanner extends ConsumerWidget {
  const ShapeRecognizedBanner({super.key});

  String _label(AppLocalizations l10n, String shapeType) {
    switch (shapeType) {
      case 'line':
        return l10n.csShapeLine;
      case 'circle':
        return l10n.csShapeCircle;
      case 'rectangle':
        return l10n.csShapeRectangle;
      case 'triangle':
        return l10n.csShapeTriangle;
      case 'arrow':
        return l10n.csShapeArrow;
      default:
        return shapeType;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(canvasProvider.select((s) =>
        s != null && s.isAdjustingRecognized ? s.recognizedShape : null));
    if (shape == null) return const SizedBox.shrink();
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Positioned(
      bottom: 16,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: HwTheme.syncOk,
            borderRadius: BorderRadius.circular(20),
            boxShadow: hwShadow2(p.brightness),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_fix_high, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                l10n.csShapeRecognizedLabel(_label(l10n, shape.shapeType)),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 12),
              Semantics(
                button: true,
                label: l10n.csConfirmShapeSemantics,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(canvasProvider.notifier).commitRecognizedShape();
                  },
                  child: Container(
                    // Slightly larger tap area for fingers.
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(l10n.csConfirm,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Semantics(
                button: true,
                label: l10n.csCancelShapeSemantics,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => ref
                      .read(canvasProvider.notifier)
                      .dismissRecognizedShape(),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(l10n.csCancel,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a finger tap just undid or redid; sits below a placement hint when
/// one is showing.
class TapFlashPill extends ConsumerWidget {
  const TapFlashPill({super.key, required this.flash});

  final ValueListenable<({bool redo, bool visible})> flash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final belowHint = ref.watch(canvasProvider.select((s) =>
        s != null &&
        (s.pendingSymbol != null || (s.pendingPaste && s.clipboard != null))));
    final p = HwThemeScope.of(context);
    return Positioned(
      top: belowHint ? 64 : 16,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: ValueListenableBuilder(
            valueListenable: flash,
            builder: (context, flash, _) {
              final l10n = AppLocalizations.of(context);
              return AnimatedOpacity(
                opacity: flash.visible ? 1 : 0,
                duration: Duration(milliseconds: flash.visible ? 120 : 260),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: p.ink0.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: hwShadow2(p.brightness),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(flash.redo ? Icons.redo : Icons.undo,
                          color: p.paper0, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        flash.redo ? l10n.csTapRedone : l10n.csTapUndone,
                        style: TextStyle(
                            color: p.paper0,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// "Tap to place" hint for a pending symbol.
class PendingSymbolHint extends ConsumerWidget {
  const PendingSymbolHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final symbol = ref.watch(canvasProvider.select((s) => s?.pendingSymbol));
    if (symbol == null) return const SizedBox.shrink();
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Positioned(
      top: 16,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: p.accent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: hwShadow2(p.brightness),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.place, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                l10n.csTapToPlaceSymbol(symbol.name),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: l10n.csCancelSymbolInsertSemantics,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      ref.read(canvasProvider.notifier).clearPendingSymbol(),
                  child: const Padding(
                    // 12px on every side gives a 40-px hit area around the icon.
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.close, color: Colors.white70, size: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Tap to place" hint for a pending paste or duplicate.
class PendingPasteHint extends ConsumerWidget {
  const PendingPasteHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(canvasProvider
        .select((s) => s != null && s.pendingPaste && s.clipboard != null));
    if (!show) return const SizedBox.shrink();
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Positioned(
      top: 16,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: HwTheme.syncPending,
            borderRadius: BorderRadius.circular(20),
            boxShadow: hwShadow2(p.brightness),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.place, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                l10n.csTapToPlaceCopy,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: l10n.csCancelPasteSemantics,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      ref.read(canvasProvider.notifier).cancelPendingPaste(),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.close, color: Colors.white70, size: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Edge preview while dragging the page sideways: a new page on the right
/// of the last one, or the neighbouring page.
class PageDragHint extends StatelessWidget {
  const PageDragHint({super.key, required this.hint});

  final ValueListenable<PageHint> hint;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PageHint>(
      valueListenable: hint,
      builder: (context, h, _) {
        switch (h) {
          case PageHint.none:
            return const SizedBox.shrink();
          case PageHint.newPage:
            return const _NewPageHint();
          case PageHint.nextPage:
            return const _NeighbourPageHint(next: true);
          case PageHint.prevPage:
            return const _NeighbourPageHint(next: false);
        }
      },
    );
  }
}

class _NewPageHint extends StatelessWidget {
  const _NewPageHint();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: 120,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [
              HwTheme.syncOk.withValues(alpha: 0.85),
              HwTheme.syncOk.withValues(alpha: 0.0)
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_circle_outline,
                  color: Colors.white, size: 36),
              const SizedBox(height: 4),
              Text(AppLocalizations.of(context).csNewPage,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeighbourPageHint extends ConsumerWidget {
  const _NeighbourPageHint({required this.next});

  final bool next;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = HwThemeScope.of(context);
    final (page, imageCache) = ref.watch(canvasProvider.select((s) {
      if (s == null) return (null, const <String, ui.Image>{});
      final filtered = s.filteredPageIndices;
      final cur = filtered.indexOf(s.currentPageIndex);
      final at = next ? cur + 1 : cur - 1;
      final PageData? page = cur >= 0 && at >= 0 && at < filtered.length
          ? s.pages[s.document.pages[filtered[at]].fileName]
          : null;
      return (page, s.imageCache);
    }));
    final edge = BorderSide(color: p.paperEdge, width: 1);
    return Positioned(
      right: next ? 0 : null,
      left: next ? null : 0,
      top: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width * 0.35,
      child: Container(
        decoration: BoxDecoration(
          color: p.paper2,
          border: next ? Border(left: edge) : Border(right: edge),
          boxShadow: hwShadow2(p.brightness),
        ),
        child: page != null
            ? CustomPaint(
                painter: CanvasRenderEngine(
                  pageData: page,
                  zoom: 1.0,
                  panOffset: Offset.zero,
                  imageCache: imageCache,
                ),
                size: Size.infinite,
              )
            : Center(
                child: Icon(
                    next
                        ? Icons.arrow_forward_rounded
                        : Icons.arrow_back_rounded,
                    color: p.paperEdge,
                    size: 40)),
      ),
    );
  }
}
