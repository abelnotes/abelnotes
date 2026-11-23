// Floating action bar of a lasso selection: copy, cut, duplicate, colour,
// thickness, paste, delete, more and close.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/canvas_painter_notifiers.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_widgets.dart';
import 'package:abelnotes/features/canvas/presentation/editor/page_view_transform.dart';
import 'package:abelnotes/features/modules/module_registry.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Positioned: put it straight in a Stack.
class SelectionActionBar extends ConsumerWidget {
  const SelectionActionBar({
    super.key,
    required this.state,
    required this.canvasSize,
    required this.transform,
    required this.dockRect,
    required this.copyImageToSystemClipboard,
    required this.paste,
    required this.toast,
    required this.strokeWidthOf,
    required this.onColor,
    required this.onWidth,
    required this.onMore,
  });

  final CanvasState state;
  final Size canvasSize;
  final LassoTransformNotifier transform;
  /// The tool dock's rect in canvas coordinates, to keep clear of it.
  final Rect? Function() dockRect;
  final void Function(String elementId) copyImageToSystemClipboard;
  final VoidCallback paste;
  final void Function(String message) toast;
  /// Width of the selected ink, or null when it holds none.
  final double? Function(CanvasState state) strokeWidthOf;
  final VoidCallback onColor;
  final void Function(CanvasState state) onWidth;
  final void Function(CanvasState state) onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Starts loading module models, so the ⋯ menu can offer their actions.
    ref.read(selectionActionsProvider);
    final p = HwThemeScope.of(context);
    final view = PageViewTransform.of(state, canvasSize);
    final originalSel = state.lassoSelection!;
    // Same live-transform override as _buildLassoHandles — keeps the
    // floating action bar attached to the moving selection during a
    // drag/rotate/scale gesture.
    final sel = transform.isActive
        ? originalSel.copyWith(
            dragOffset: transform.dragOffset,
            rotation: transform.rotation,
            scale: transform.scale,
          )
        : originalSel;
    final center = sel.bounds.center;
    final scaledBounds = Rect.fromCenter(
      center: center,
      width: sel.bounds.width * sel.scale,
      height: sel.bounds.height * sel.scale,
    ).translate(sel.dragOffset.dx, sel.dragOffset.dy);

    // Position below the selection, or above it when that would land on a
    // horizontal tool dock (selection near the bottom of the screen).
    const barH = 52.0;
    final screenBottom = view.toScreen(scaledBounds.bottomCenter);
    var below = screenBottom.dy + 12;
    final dock = dockRect();
    if (dock != null &&
        dock.width > dock.height &&
        below + barH > dock.top &&
        below < dock.bottom) {
      // 48: clear of the rotation handle above the selection.
      final above = view.toScreen(scaledBounds.topCenter).dy -
          48 - barH;
      below = above >= 0 ? above : dock.top - barH - 8;
    }

    // Clamp to stay within view
    final top = below.clamp(0.0, canvasSize.height - 50);

    return Positioned(
      left: 0,
      right: 0,
      top: top,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: p.paper0,
            borderRadius: BorderRadius.circular(22),
            boxShadow: hwShadow2(p.brightness),
          ),
          // Module actions can outgrow a phone's width: scroll, don't overflow.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionBtn(Icons.copy_rounded, AppLocalizations.of(context).csCopy, () {
                ref.read(canvasProvider.notifier).copySelection();
                // If the selection is a single image, also push its PNG
                // to the system clipboard so the user can paste it elsewhere.
                final sel = state.lassoSelection;
                if (sel != null && sel.selectedIds.length == 1) {
                  final page = state.currentPage;
                  final id = sel.selectedIds.first;
                  final el = page?.layers.content
                      .where((e) =>
                          e.id ==
                          id)
                      .firstOrNull;
                  final isImg = el?.map(unknown: (_) => false,
                        stroke: (_) => false,
                        text: (_) => false,
                        image: (_) => true,
                        shape: (_) => false,
                        math: (_) => false,
                      ) ??
                      false;
                  if (isImg) copyImageToSystemClipboard(id);
                }
                toast(AppLocalizations.of(context).csSelectionCopied);
              }),
              FloatingActionBtn(Icons.content_cut_rounded, AppLocalizations.of(context).csCut, () {
                ref.read(canvasProvider.notifier).cutSelection();
                toast(AppLocalizations.of(context).csSelectionCut);
              }),
              FloatingActionBtn(Icons.copy_all_rounded, AppLocalizations.of(context).csDuplicate, () {
                ref.read(canvasProvider.notifier).duplicateSelection();
                toast(AppLocalizations.of(context).csSelectionDuplicated);
              }),
              // Quick color picker — restores the workflow from the
              // previous UI (select stroke → tap color to recolor).
              FloatingActionBtn(Icons.palette_rounded, AppLocalizations.of(context).csChangeColor,
                  onColor),
              // Thickness slider for already-drawn ink — only meaningful
              // when the selection actually contains a stroke or shape.
              if (strokeWidthOf(state) != null)
                FloatingActionBtn(Icons.line_weight_rounded, AppLocalizations.of(context).csThickness,
                    () => onWidth(state)),
              if (state.clipboard != null)
                // Same resolver as the menu: a newer system image/text wins.
                FloatingActionBtn(Icons.paste_rounded, AppLocalizations.of(context).csPaste, () {
                  paste();
                }),
              FloatingActionBtn(Icons.delete_outline, AppLocalizations.of(context).csDelete, () {
                ref.read(canvasProvider.notifier).deleteSelection();
              }, color: HwTheme.syncConflict),
              // Less-used actions folded into a "more" menu (Rifletti H/V,
              // Screenshot, Incolla in altro notebook).
              FloatingActionBtn(Icons.more_horiz, AppLocalizations.of(context).csMore,
                  () => onMore(state)),
              FloatingActionBtn(Icons.close, null, () {
                ref.read(canvasProvider.notifier).clearSelection();
              }),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
