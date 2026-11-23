// The tool options panel (colour, width, eraser size) beside the dock, or
// next to the Pencil's tip after a squeeze.

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/providers/preset_colors_provider.dart';
import 'package:abelnotes/features/canvas/presentation/editor/dock_controller.dart';
import 'package:abelnotes/ui/editor/hw_editor_chrome.dart';
import 'package:abelnotes/ui/primitives/hw_motion_widgets.dart';

/// A Stack child: the panel placed for [dockPosition], shown while [open].
class EditorToolPanel extends StatelessWidget {
  const EditorToolPanel({
    super.key,
    required this.dockPosition,
    required this.align,
    required this.area,
    required this.popup,
    required this.onClose,
  });

  final DockPosition dockPosition;
  final double align;
  final Size area;

  /// Whether the panel shows, and the Pencil tip it was asked to open next to.
  final ValueListenable<({bool open, ({Offset tip, Rect area})? at})> popup;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: popup,
      builder: (context, p, _) => DockController.placePopup(
        dockPosition,
        align,
        area,
        p.at,
        HwMaterialize(
          visible: p.open,
          alignment: switch (dockPosition) {
            DockPosition.left => Alignment.centerLeft,
            DockPosition.right => Alignment.centerRight,
            DockPosition.top || DockPosition.bar => Alignment.topCenter,
            _ => Alignment.bottomCenter,
          },
          // Absorb taps so a near-miss on the small colour chips doesn't fall
          // through to the canvas "tap closes popup" handler.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: _ToolPopupContent(onClose: onClose),
          ),
        ),
      ),
    );
  }
}

class _ToolPopupContent extends ConsumerWidget {
  const _ToolPopupContent({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(canvasProvider.select((s) =>
        s == null ? null : (tool: s.currentTool, settings: s.toolSettings)));
    final presetColors = ref.watch(presetColorsProvider);
    if (s == null) return const SizedBox.shrink();
    final notifier = ref.read(canvasProvider.notifier);
    final settings = s.settings;
    return HwToolPopup(
      tool: s.tool,
      color: Color(settings.color),
      onColorChanged: (c) {
        notifier.setToolSettings(settings.copyWith(color: c.toARGB32()));
      },
      onPresetColorEdited: (index, c) {
        ref.read(presetColorsProvider.notifier).setColor(index, c.toARGB32());
      },
      thickness: settings.strokeWidth,
      onThicknessChanged: (v) {
        notifier.setToolSettings(settings.copyWith(strokeWidth: v));
      },
      presetColors: presetColors.map((c) => Color(c)).toList(),
      eraserSize: settings.eraserSize,
      onEraserSizeChanged: (s) => notifier.setEraserSize(s),
      eraserDiameterPt: settings.eraserDiameterPt,
      onEraserDiameterChanged: (pt) => notifier.setEraserDiameterPt(pt),
      eraserPerStroke: s.tool == CanvasTool.eraserStroke,
      onEraserPerStrokeChanged: (perStroke) {
        notifier.setTool(
            perStroke ? CanvasTool.eraserStroke : CanvasTool.eraserStandard);
      },
      shapeGuess: settings.shapeRecognition,
      onShapeGuessChanged: (v) {
        notifier.setToolSettings(settings.copyWith(shapeRecognition: v));
      },
      onClose: onClose,
    );
  }
}
