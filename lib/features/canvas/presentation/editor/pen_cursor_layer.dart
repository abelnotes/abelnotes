// Eraser circle under the pen or finger, and the lasso badge beside a
// hovering tip. Watches only the tool and the erase position, so the page
// painter and the chrome stay out of its pointer-rate updates.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_pointer_controller.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_types.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Positioned.fill: put it straight in the canvas Stack. The inner Stacks give
/// the cursor's Positioned the Stack ancestor it needs.
class PenCursorLayer extends ConsumerWidget {
  const PenCursorLayer(
      {super.key, required this.ptr, required this.canvasSize});

  final EditorPointerController ptr;
  final Size canvasSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Consumer(
          builder: (context, ref, _) {
            final eraserState = ref.watch(canvasProvider.select((s) => s == null
                ? null
                : (tool: s.currentTool, pos: s.eraserCursorPos)));
            if (eraserState == null) return const SizedBox.shrink();
            final fullState = ref.read(canvasProvider);
            if (fullState == null) return const SizedBox.shrink();
            if (eraserState.pos != null &&
                EditorPointerController.isEraserTool(eraserState.tool)) {
              return Stack(
                children: [
                  _eraserCursor(
                    context,
                    fullState,
                    ptr.toScreenCoords(eraserState.pos!, fullState, canvasSize),
                    erasing: true,
                  ),
                ],
              );
            }
            // Drag cursor wins; otherwise the hovering pen's.
            return ValueListenableBuilder<Offset?>(
              valueListenable: ptr.penHoverPos,
              builder: (context, hoverPos, _) {
                final lasso = ptr.penHoverHint == PenHoverHint.lasso;
                final toolMatches = lasso
                    ? eraserState.tool == CanvasTool.lasso
                    : EditorPointerController.isEraserTool(eraserState.tool);
                if (hoverPos == null || !(toolMatches || ptr.penHoverBarrel)) {
                  return const SizedBox.shrink();
                }
                final live = ref.read(canvasProvider) ?? fullState;
                return Stack(
                  children: [
                    lasso
                        ? _lassoBadge(context, hoverPos)
                        : _eraserCursor(context, live, hoverPos,
                            erasing: false),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // Hover: thin outline. Tip down: accent fill, so contact is visible.
  Widget _eraserCursor(BuildContext context, CanvasState state, Offset pos,
      {required bool erasing}) {
    final p = HwThemeScope.of(context);
    // Radius is in page units: screen size needs the same renderScale x zoom
    // factor toScreenCoords applies to the position.
    final r = state.toolSettings.eraserRadius *
        ptr.getRenderScale(state, canvasSize) *
        state.zoom;
    return Positioned(
      left: pos.dx - r,
      top: pos.dy - r,
      child: IgnorePointer(
        child: Container(
          width: r * 2,
          height: r * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: erasing
                ? Border.all(color: p.accent, width: 2)
                : Border.all(color: p.ink3, width: 1),
            color: erasing
                ? p.accent.withValues(alpha: HwTheme.alphaMedium)
                : null,
          ),
        ),
      ),
    );
  }

  // Lasso icon beside a hovering tip: the barrel/tool will select on touch.
  Widget _lassoBadge(BuildContext context, Offset pos) {
    final p = HwThemeScope.of(context);
    return Positioned(
      left: pos.dx + 8,
      top: pos.dy + 8,
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.paper0,
          border: Border.all(color: p.ink3, width: 1),
        ),
        child: HwIcon('lasso', size: 14, color: p.ink1, strokeWidth: 1.4),
      ),
    );
  }
}
