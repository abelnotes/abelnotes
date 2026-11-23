// The tool dock wired to the notebook: which tool shows as active, the quick
// pens of the ink tool, and the drag handlers of [DockController].

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/editor/dock_controller.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_pointer_controller.dart';
import 'package:abelnotes/ui/editor/hw_editor_chrome.dart';

/// Ink tool the dock's quick pens belong to: the active one, or the pen while
/// a non-ink tool (eraser, lasso, ...) is held.
CanvasTool quickPenToolFor(CanvasTool current) => const {
      CanvasTool.pen,
      CanvasTool.ballpoint,
      CanvasTool.brush,
      CanvasTool.calligraphy,
      CanvasTool.highlighter,
    }.contains(current)
        ? current
        : CanvasTool.pen;

/// Tool the dock shows as active. Normally the real tool, but while the mouse
/// is a pure selector (mouseDraws false) an ink tool would show as active
/// while a click selects: lasso keeps the dock truthful to what a click does.
CanvasTool dockDisplayTool(
    CanvasTool tool, bool mouseDraws, bool? lastWasMouse) {
  if (lastWasMouse == true &&
      !mouseDraws &&
      EditorPointerController.mouseSelectTools.contains(tool)) {
    return CanvasTool.lasso;
  }
  return tool;
}

class EditorDock extends ConsumerWidget {
  const EditorDock({
    super.key,
    required this.position,
    required this.dock,
    required this.ptr,
    required this.onToolChanged,
    required this.onActiveTap,
    required this.onQuickPenTap,
    required this.onQuickPenSecondary,
  });

  final DockPosition position;
  final DockController dock;
  final EditorPointerController ptr;
  final void Function(CanvasTool tool, PointerDeviceKind kind) onToolChanged;

  /// A tap on the active tool, with the tool the dock displayed.
  final void Function(PointerDeviceKind kind, CanvasTool shown) onActiveTap;
  final void Function(CanvasTool tool, int slot) onQuickPenTap;
  final void Function(CanvasTool tool, int slot, Offset globalPosition)
      onQuickPenSecondary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(canvasProvider.select((s) => s == null
        ? null
        : (
            tool: s.currentTool,
            color: s.toolSettings.color,
            width: s.toolSettings.strokeWidth,
          )));
    final mouseDraws =
        ref.watch(appSettingsProvider.select((s) => s.mouseDraws));
    if (s == null) return const SizedBox.shrink();
    final quickTool = quickPenToolFor(s.tool);
    ref.watch(appSettingsProvider.select((s) => s.toolPresets[quickTool.name]));
    final pens = ref.read(appSettingsProvider).quickPensFor(quickTool);
    int? activeSlot;
    if (quickTool == s.tool) {
      for (var i = 0; i < pens.length; i++) {
        if (pens[i].color == s.color &&
            (pens[i].strokeWidth - s.width).abs() < 0.01) {
          activeSlot = i;
          break;
        }
      }
    }
    // The device in hand and a drag in progress change how the dock looks.
    return ListenableBuilder(
      listenable: Listenable.merge([ptr.mouseSeen, dock.dragging]),
      builder: (_, __) {
        final shown =
            dockDisplayTool(s.tool, mouseDraws, ptr.lastPointerWasMouse);
        return HwFloatingDock(
          currentTool: shown,
          penDeviceTool: s.tool,
          activeInkColor: Color(s.color),
          lastEraserMode: ref.read(canvasProvider.notifier).lastEraserMode,
          quickPens: pens,
          activeQuickPen: activeSlot,
          onQuickPenTap: (slot) => onQuickPenTap(quickTool, slot),
          onQuickPenSecondary: (slot, pos) =>
              onQuickPenSecondary(quickTool, slot, pos),
          onToolChanged: onToolChanged,
          onActiveTap: (kind) => onActiveTap(kind, shown),
          position: position,
          dragging: dock.dragOffset != null,
          onDragStart: dock.onDragStart,
          onDragUpdate: dock.onDragUpdate,
          onDragEnd: dock.onDragEnd,
        );
      },
    );
  }
}
