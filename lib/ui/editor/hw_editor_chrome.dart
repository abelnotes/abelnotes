import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/primitives/hw_button.dart';
import 'package:abelnotes/ui/primitives/sync_badge.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Top bar for the editor: Library back button, notebook title (with cover
/// chip + sync badge), undo/redo, page indicator, symbols, export, more.
class HwEditorTopBar extends StatelessWidget {
  final String notebookTitle;
  final Color coverColor;
  final int currentPage;
  final int totalPages;
  final bool dirty;
  final bool canUndo;
  final bool canRedo;
  final HwSyncState syncState;
  final VoidCallback? onBack;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onPagesTap;
  final VoidCallback? onAddPage;
  final VoidCallback? onSymbolsTap;
  final VoidCallback? onExportTap;
  final VoidCallback? onMoreTap;
  /// Mouse mode: true = mouse draws like a pen; false = mouse selects.
  final bool mouseDraws;
  final VoidCallback? onToggleMouseMode;
  /// Show the page-count indicator + "all pages" button. False for the
  /// infinite scratch canvas, which has no A4 pages to navigate.
  final bool showPages;

  const HwEditorTopBar({
    super.key,
    required this.notebookTitle,
    required this.coverColor,
    required this.currentPage,
    required this.totalPages,
    required this.dirty,
    required this.canUndo,
    required this.canRedo,
    required this.syncState,
    this.onBack,
    this.onUndo,
    this.onRedo,
    this.onPagesTap,
    this.onAddPage,
    this.onSymbolsTap,
    this.onExportTap,
    this.onMoreTap,
    this.showPages = true,
    this.mouseDraws = false,
    this.onToggleMouseMode,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    // On iPad the front camera / dynamic island sits centred along the
    // long edge — in landscape that's right above the start of the top
    // bar. Push the back button rightwards by a small amount so it
    // doesn't sit directly under the lens.
    final isIPad = !kIsWeb &&
        io.Platform.isIOS &&
        MediaQuery.of(context).size.shortestSide >= 600;
    return LayoutBuilder(builder: (ctx, c) {
      final isCompact = c.maxWidth < 720;
      final leftPad = (isCompact ? 6.0 : 12.0) + (isIPad ? 28.0 : 0.0);
      return Container(
        height: 52,
        padding: EdgeInsets.fromLTRB(
            leftPad, 0, isCompact ? 6 : 12, 0),
        decoration: BoxDecoration(
          color: p.paper0,
          border: Border(bottom: BorderSide(color: p.paper3)),
        ),
        child: Row(
          children: [
            // Back button — icon-only on compact to save space.
            if (isCompact)
              HwButton.icon(
                icon: const HwIcon('chevron-left', size: 16),
                tooltip: l10n.chromeBackToLibraryTooltip,
                onPressed: onBack,
              )
            else
              HwButton(
                leading: const HwIcon('chevron-left', size: 16),
                label: l10n.chromeLibrary,
                onPressed: onBack,
                tooltip: l10n.chromeBackToLibraryTooltip,
              ),
            const SizedBox(width: 4),
            const HwDivider(),
            const SizedBox(width: 8),
            // Cover chip + title
            Container(
              width: 14,
              height: 18,
              decoration: BoxDecoration(
                color: coverColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(1),
                  bottomLeft: Radius.circular(1),
                  topRight: Radius.circular(3),
                  bottomRight: Radius.circular(3),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                notebookTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: p.ink0,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SyncBadge(state: syncState),
            // Reserve constant space for the "Non salvato" pill so the
            // toolbar to the right (undo/redo/pages/etc.) doesn't shift
            // every time the dirty flag flips. Visibility.maintainSize
            // keeps the slot in the layout regardless of visibility.
            if (!isCompact) ...[
              const SizedBox(width: 8),
              Visibility(
                visible: dirty,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: HwPill(
                  label: l10n.chromeUnsaved,
                  background: HwTheme.syncPending.withValues(alpha: 0.20),
                  foreground: HwTheme.syncPending,
                ),
              ),
            ],
            const Spacer(),
            // Mouse mode toggle: draw like a pen vs select. Tinted accent when
            // the mouse draws, so the current mode is always visible.
            if (onToggleMouseMode != null)
              HwButton.icon(
                icon: HwIcon(mouseDraws ? 'pen' : 'mouse', size: 16,
                    color: mouseDraws ? p.accentDeep : null),
                tooltip: mouseDraws
                    ? l10n.chromeMouseDrawsTooltip
                    : l10n.chromeMouseSelectsTooltip,
                onPressed: onToggleMouseMode,
              ),
            // Always-visible essentials
            HwButton.icon(
              icon: const HwIcon('undo', size: 16),
              tooltip: l10n.chromeUndo,
              onPressed: canUndo ? onUndo : null,
            ),
            HwButton.icon(
              icon: const HwIcon('redo', size: 16),
              tooltip: l10n.chromeRedo,
              onPressed: canRedo ? onRedo : null,
            ),
            const SizedBox(width: 4),
            const HwDivider(),
            const SizedBox(width: 4),
            // Page indicator: show with label on wide, icon-only on compact.
            // Hidden for the infinite scratch canvas (single page, no nav).
            if (showPages)
              if (isCompact)
                HwButton.icon(
                  icon: const HwIcon('pages', size: 16),
                  tooltip: l10n.chromeAllPages,
                  onPressed: onPagesTap,
                )
              else
                HwButton(
                  leading: const HwIcon('pages', size: 16),
                  label: l10n.chromePageIndicator(
                      currentPage
                          .toString()
                          .padLeft(totalPages.toString().length, '0'),
                      totalPages),
                  onPressed: onPagesTap,
                  tooltip: l10n.chromeAllPages,
                ),
            if (onAddPage != null)
              HwButton.icon(
                icon: const HwIcon('plus', size: 16),
                tooltip: l10n.chromeAddPage,
                onPressed: onAddPage,
              ),
            // Secondary actions: keep visible on wide, fold into the
            // overflow menu on compact.
            if (!isCompact) ...[
              const SizedBox(width: 4),
              const HwDivider(),
              const SizedBox(width: 4),
              HwButton.icon(
                  icon: const HwIcon('symbol', size: 16),
                  tooltip: l10n.chromeSymbols,
                  onPressed: onSymbolsTap),
              HwButton.icon(
                  icon: const HwIcon('export', size: 16),
                  tooltip: l10n.chromeExport,
                  onPressed: onExportTap),
            ],
            HwButton.icon(
              icon: const HwIcon('more', size: 16),
              tooltip: l10n.chromeMore,
              onPressed: isCompact
                  ? () => _showCompactOverflow(
                        ctx,
                        onSymbolsTap: onSymbolsTap,
                        onExportTap: onExportTap,
                        onMoreTap: onMoreTap,
                      )
                  : onMoreTap,
            ),
          ],
        ),
      );
    });
  }

  /// Compact-mode overflow: bundles symbols + export + the original
  /// "more" menu in a single popup so phone-width devices don't need
  /// to fit 7 buttons in the top bar.
  void _showCompactOverflow(
    BuildContext context, {
    VoidCallback? onSymbolsTap,
    VoidCallback? onExportTap,
    VoidCallback? onMoreTap,
  }) async {
    final p = HwThemeScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.paper0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const HwIcon('symbol', size: 18),
              title: Text(AppLocalizations.of(ctx).chromeSymbols),
              onTap: () {
                Navigator.of(ctx).pop();
                onSymbolsTap?.call();
              },
            ),
            ListTile(
              leading: const HwIcon('export', size: 18),
              title: Text(AppLocalizations.of(ctx).chromeExport),
              onTap: () {
                Navigator.of(ctx).pop();
                onExportTap?.call();
              },
            ),
            const Divider(),
            ListTile(
              leading: const HwIcon('more', size: 18),
              title: Text(AppLocalizations.of(ctx).chromeMoreEllipsis),
              onTap: () {
                Navigator.of(ctx).pop();
                onMoreTap?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum DockPosition { floating, left, right, top, bottom }

/// Floating tool dock — circular pill with all tools + shape-guess toggle.
/// Tap a tool to select; tap again (or popOpen=true) opens the tool popup.
class HwFloatingDock extends StatelessWidget {
  final CanvasTool currentTool;
  final ValueChanged<CanvasTool> onToolChanged;
  final VoidCallback onActiveTap;
  final Color activeInkColor;
  final DockPosition position;
  final bool shapeGuess;
  final ValueChanged<bool> onShapeGuessChanged;
  /// Last eraser sub-mode the user picked (per-stroke vs per-area). The
  /// dock's eraser button activates THIS instead of always defaulting
  /// to `eraserStroke`, so going pen → eraser → pen → eraser keeps the
  /// area mode the user just chose.
  final CanvasTool lastEraserMode;
  /// Drag-to-reposition callbacks. When [onDragUpdate] is non-null a grip
  /// handle appears at the leading edge of the dock (top when vertical,
  /// left when horizontal); dragging it lets the user park the toolbar on
  /// any screen edge. Deltas are reported in global logical pixels — the
  /// parent decides where the dock lands and re-docks it.
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;
  /// True while the user is actively dragging the dock — tints the grip
  /// so it reads as "live".
  final bool dragging;

  const HwFloatingDock({
    super.key,
    required this.currentTool,
    required this.onToolChanged,
    required this.onActiveTap,
    required this.activeInkColor,
    required this.shapeGuess,
    required this.onShapeGuessChanged,
    this.lastEraserMode = CanvasTool.eraserStroke,
    this.position = DockPosition.floating,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.dragging = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isVert =
        position == DockPosition.left || position == DockPosition.right;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: HwThemeScope.of(context).paper0,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: HwThemeScope.of(context).paper3),
        boxShadow: hwShadow2(HwThemeScope.of(context).brightness),
      ),
      child: Flex(
        direction: isVert ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onDragUpdate != null) ...[
            _dragHandle(context, isVert),
            _gap(isVert, context),
          ],
          _toolBtn(context, CanvasTool.pen, 'pen', l10n.chromeToolPen),
          _toolBtn(context, CanvasTool.highlighter, 'highlighter',
              l10n.chromeToolHighlighter),
          _gap(isVert, context),
          // Eraser button restores whichever sub-mode (per-stroke or
          // per-area) the user picked last. `lastEraserMode` is the
          // memory; flipping it happens in CanvasNotifier.setTool
          // whenever the user explicitly chooses one variant via the
          // popup. Tapping this dock button when eraser is NOT active
          // restores that memory; tapping it when active opens the
          // popup so the user can flip.
          _toolBtn(context, lastEraserMode, 'eraser', l10n.chromeToolEraser),
          _toolBtn(context, CanvasTool.lasso, 'lasso', l10n.chromeToolLasso),
          _toolBtn(context, CanvasTool.text, 'text', l10n.chromeToolText),
          _toolBtn(context, CanvasTool.laser, 'laser', l10n.chromeToolLaser),
          _toolBtn(context, CanvasTool.pan, 'hand', l10n.chromeToolPan),
          _gap(isVert, context),
          _shapeGuessBtn(context),
        ],
      ),
    );
  }

  /// Grip the user drags to move + re-dock the toolbar. Shows the
  /// 6-dot grip when the dock is horizontal (handle on the left) and
  /// the horizontal-bars grip when vertical (handle on top), so the
  /// affordance always points "along" the bar. onPan* forwards raw
  /// drag details to the parent, which owns the positioning maths.
  Widget _dragHandle(BuildContext context, bool isVert) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.chromeDragToMoveBar,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: onDragStart,
          onPanUpdate: onDragUpdate,
          onPanEnd: onDragEnd,
          child: Tooltip(
            message: l10n.chromeDragToMoveBar,
            waitDuration: const Duration(milliseconds: 500),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Icon(
                  isVert ? Icons.drag_handle : Icons.drag_indicator,
                  size: 18,
                  color: dragging ? p.accentDeep : p.ink1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _gap(bool isVert, BuildContext context) {
    final p = HwThemeScope.of(context);
    return Padding(
      padding: isVert
          ? const EdgeInsets.symmetric(vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        width: isVert ? 20 : 1,
        height: isVert ? 1 : 20,
        color: p.paper3,
      ),
    );
  }

  static const Set<CanvasTool> _inkTools = {
    CanvasTool.pen,
    CanvasTool.ballpoint,
    CanvasTool.brush,
    CanvasTool.calligraphy,
    CanvasTool.highlighter,
  };

  Widget _toolBtn(
      BuildContext context, CanvasTool tool, String icon, String tooltip) {
    // The eraser dock button represents both per-stroke and per-area
    // erasers — the user picks the mode in the popup. Highlight the
    // single button whichever variant is active.
    final isEraserBtn = tool == CanvasTool.eraserStroke ||
        tool == CanvasTool.eraserStandard;
    final isEraserActive = currentTool == CanvasTool.eraserStroke ||
        currentTool == CanvasTool.eraserStandard;
    final active = isEraserBtn ? isEraserActive : currentTool == tool;
    final p = HwThemeScope.of(context);
    final isInkTool = _inkTools.contains(tool);

    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (active) {
              onActiveTap();
            } else {
              onToolChanged(tool);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: active ? p.ink0 : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                HwIcon(icon,
                    size: 18, color: active ? p.paper0 : p.ink1),
                // Color stripe under active ink tool
                if (active && isInkTool)
                  Positioned(
                    bottom: 6,
                    child: Container(
                      width: 14,
                      height: 3,
                      decoration: BoxDecoration(
                        color: activeInkColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _shapeGuessBtn(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final label =
        shapeGuess ? l10n.chromeShapeGuessOn : l10n.chromeShapeGuessOff;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onShapeGuessChanged(!shapeGuess),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: shapeGuess ? p.accentSoft : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: HwIcon('shape-guess',
                    size: 18,
                    color: shapeGuess ? p.accentDeep : p.ink1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Popup with color preset + thickness slider + per-tool extras.
class HwToolPopup extends StatelessWidget {
  final CanvasTool tool;
  final Color color;
  final ValueChanged<Color> onColorChanged;
  /// Long-press a preset color chip to replace it with a freshly-picked
  /// color (index = slot in [presetColors]). Lets the user change the
  /// default palette directly from the pen panel. Null disables editing.
  final void Function(int index, Color color)? onPresetColorEdited;
  final double thickness;
  final ValueChanged<double> onThicknessChanged;
  final List<Color> presetColors;
  final EraserSize? eraserSize;
  final ValueChanged<EraserSize>? onEraserSizeChanged;
  final bool? eraserPerStroke;
  final ValueChanged<bool>? onEraserPerStrokeChanged;
  final VoidCallback onClose;
  /// 3-slot pen-preset rail. `null` slot = empty (tap to save current,
  /// shows "+" placeholder). `onApplyPreset` activates the preset's
  /// tool+settings via CanvasNotifier.applyPenPreset; `onSavePreset`
  /// writes the active tool's current (color, width, opacity) into
  /// the slot. Only shown for pen-class tools — eraser/lasso/etc.
  /// don't have presets.
  final List<PenPreset?>? penPresets;
  final void Function(int slot)? onApplyPreset;
  final void Function(int slot)? onSavePreset;
  final void Function(int slot)? onClearPreset;

  const HwToolPopup({
    super.key,
    required this.tool,
    required this.color,
    required this.onColorChanged,
    this.onPresetColorEdited,
    required this.thickness,
    required this.onThicknessChanged,
    required this.presetColors,
    required this.onClose,
    this.eraserSize,
    this.onEraserSizeChanged,
    this.eraserPerStroke,
    this.onEraserPerStrokeChanged,
    this.penPresets,
    this.onApplyPreset,
    this.onSavePreset,
    this.onClearPreset,
  });

  bool get _showPresets =>
      penPresets != null &&
      (tool == CanvasTool.pen ||
          tool == CanvasTool.ballpoint ||
          tool == CanvasTool.brush ||
          tool == CanvasTool.highlighter);

  bool get _showColor => !{
        CanvasTool.eraserStandard,
        CanvasTool.eraserStroke,
        CanvasTool.lasso,
        CanvasTool.pan,
        CanvasTool.laser,
      }.contains(tool);

  bool get _showThickness => !{
        CanvasTool.lasso,
        CanvasTool.pan,
        CanvasTool.text,
        CanvasTool.laser,
      }.contains(tool);

  bool get _isEraser =>
      tool == CanvasTool.eraserStandard || tool == CanvasTool.eraserStroke;

  String _label(AppLocalizations l10n) {
    switch (tool) {
      case CanvasTool.pen:
        return l10n.chromeLabelPen;
      case CanvasTool.ballpoint:
        return l10n.chromeLabelBallpoint;
      case CanvasTool.brush:
        return l10n.chromeLabelBrush;
      case CanvasTool.calligraphy:
        return l10n.chromeLabelCalligraphy;
      case CanvasTool.highlighter:
        return l10n.chromeLabelHighlighter;
      case CanvasTool.eraserStandard:
      case CanvasTool.eraserStroke:
        return l10n.chromeLabelEraser;
      case CanvasTool.lasso:
        return l10n.chromeLabelLasso;
      case CanvasTool.text:
        return l10n.chromeLabelText;
      case CanvasTool.shape:
        return l10n.chromeLabelShape;
      case CanvasTool.image:
        return l10n.chromeLabelImage;
      case CanvasTool.pan:
        return l10n.chromeLabelPan;
      case CanvasTool.laser:
        return l10n.chromeLabelLaser;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      width: math.min(300, MediaQuery.of(context).size.width - 32),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.paper0,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.paper3),
        boxShadow: hwShadow3(p.brightness),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_label(l10n),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: p.ink0)),
              const Spacer(),
              HwButton.icon(
                  icon: const HwIcon('x', size: 14), onPressed: onClose),
            ],
          ),
          const SizedBox(height: 8),
          if (_showPresets) ...[
            _section(l10n.chromePresetsSection, p),
            const SizedBox(height: 6),
            Row(
              children: [
                for (int i = 0; i < 3; i++) ...[
                  Expanded(child: _presetSlot(i, p, context)),
                  if (i < 2) const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.chromePresetHint,
              style: TextStyle(fontSize: 10, color: p.ink3),
            ),
            const SizedBox(height: 14),
          ],
          if (_showColor) ...[
            _section(l10n.chromeColorSection, p),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (int i = 0; i < presetColors.length; i++)
                  _colorChip(presetColors[i], i, p, context),
                _customColorChip(context, p),
              ],
            ),
            const SizedBox(height: 6),
            if (onPresetColorEdited != null)
              Text(
                l10n.chromeColorEditHint,
                style: TextStyle(fontSize: 10, color: p.ink3),
              ),
            const SizedBox(height: 14),
          ],
          if (_showThickness) ...[
            Row(
              children: [
                _section(l10n.chromeThicknessSection, p),
                const Spacer(),
                Text(l10n.chromeThicknessPx(thickness.toStringAsFixed(1)),
                    style: TextStyle(
                      fontSize: 12,
                      color: p.ink1,
                      fontFamily: HwTheme.fontMono,
                    )),
              ],
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8, elevation: 1),
                activeTrackColor: p.ink0,
                inactiveTrackColor: p.paper3,
                thumbColor: p.ink0,
              ),
              child: Slider(
                min: 0.5,
                max: 20.0,
                divisions: 39,
                value: thickness.clamp(0.5, 20.0),
                onChanged: onThicknessChanged,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.paper2)),
              ),
              child: Row(
                children: [
                  Text(l10n.chromePreview,
                      style: TextStyle(fontSize: 12, color: p.ink2)),
                  const Spacer(),
                  CustomPaint(
                    size: const Size(160, 20),
                    painter: _StrokePreviewPainter(
                        color: color,
                        width: thickness,
                        isHighlighter: tool == CanvasTool.highlighter),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_isEraser) ...[
            _section(l10n.chromeModeSection, p),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _modeBtn(
                      p,
                      l10n.chromeEraserPerArea,
                      !(eraserPerStroke ?? false),
                      () => onEraserPerStrokeChanged?.call(false)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _modeBtn(p, l10n.chromeEraserPerStroke,
                      eraserPerStroke ?? false,
                      () => onEraserPerStrokeChanged?.call(true)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _section(l10n.chromeSizeSection, p),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final s in EraserSize.values) ...[
                  Expanded(
                    child: _modeBtn(
                        p,
                        switch (s) {
                          EraserSize.small => 'S',
                          EraserSize.medium => 'M',
                          EraserSize.large => 'L',
                        },
                        eraserSize == s,
                        () => onEraserSizeChanged?.call(s)),
                  ),
                  if (s != EraserSize.large) const SizedBox(width: 6),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String label, HwPalette p) => Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: p.ink2,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      );

  Widget _colorChip(Color c, int index, HwPalette p, BuildContext context) {
    final selected = c.toARGB32() == color.toARGB32();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onColorChanged(c),
        onLongPress: onPresetColorEdited == null
            ? null
            : () async {
                final picked = await showHwColorPicker(context, c);
                if (picked != null) onPresetColorEdited!(index, picked);
              },
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(color: p.paper0, width: 2)
                : Border.all(color: const Color(0x1A000000), width: 1),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: c, blurRadius: 0, spreadRadius: 2),
                  ]
                : null,
          ),
        ),
      ),
    );
  }

  Widget _customColorChip(BuildContext context, HwPalette p) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          final picked = await showHwColorPicker(context, color);
          if (picked != null) onColorChanged(picked);
        },
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: p.paper3),
            gradient: const SweepGradient(colors: [
              Colors.red,
              Colors.yellow,
              Colors.green,
              Colors.cyan,
              Colors.blue,
              Colors.purple,
              Colors.red,
            ]),
          ),
        ),
      ),
    );
  }

  Widget _modeBtn(HwPalette p, String label, bool active, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? p.ink0 : p.paper2,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    color: active ? p.paper0 : p.ink0,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }

  /// One of the 3 OneNote-style preset slots in the popup rail. Empty
  /// → "+" placeholder, tap = save current; long-press = no-op.
  /// Filled → shows a coloured pen-tip with thickness ring, tap =
  /// activate, long-press = menu to overwrite/clear.
  Widget _presetSlot(int slot, HwPalette p, BuildContext context) {
    final preset = (penPresets != null && slot < penPresets!.length)
        ? penPresets![slot]
        : null;
    final isActive = preset != null &&
        preset.tool == tool &&
        preset.color == color.toARGB32() &&
        (preset.strokeWidth - thickness).abs() < 0.01;
    final body = Container(
      height: 42,
      decoration: BoxDecoration(
        color: isActive ? p.accentSoft : p.paper2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isActive ? p.accent : p.paper3,
            width: isActive ? 1.5 : 1),
      ),
      child: Center(
        child: preset == null
            ? Icon(Icons.add_rounded, size: 18, color: p.ink3)
            : _presetGlyph(preset, p),
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (preset == null) {
            onSavePreset?.call(slot); // save current tool as preset
          } else {
            onApplyPreset?.call(slot);
          }
        },
        onLongPress: preset == null
            ? null
            : () => _showPresetMenu(context, slot, p),
        child: body,
      ),
    );
  }

  Widget _presetGlyph(PenPreset preset, HwPalette p) {
    final tip = Color(preset.color).withValues(alpha: preset.opacity);
    // Visual: a horizontal stroke that scales with the preset's width.
    final w = preset.strokeWidth.clamp(0.5, 14.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: w,
          decoration: BoxDecoration(
            color: tip,
            borderRadius: BorderRadius.circular(w / 2),
          ),
        ),
      ],
    );
  }

  void _showPresetMenu(BuildContext context, int slot, HwPalette p) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final pos = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final l10n = AppLocalizations.of(context);
    final action = await showMenu<String>(
      context: context,
      position: pos,
      items: [
        PopupMenuItem(value: 'save', child: Text(l10n.chromePresetOverwrite)),
        PopupMenuItem(value: 'clear', child: Text(l10n.chromePresetClearSlot)),
      ],
    );
    if (action == 'save') onSavePreset?.call(slot);
    if (action == 'clear') onClearPreset?.call(slot);
  }
}

class _StrokePreviewPainter extends CustomPainter {
  final Color color;
  final double width;
  final bool isHighlighter;
  _StrokePreviewPainter(
      {required this.color, required this.width, this.isHighlighter = false});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isHighlighter ? color.withValues(alpha: 0.35) : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width.clamp(0.5, size.height)
      ..strokeCap = StrokeCap.round
      ..blendMode = isHighlighter ? BlendMode.multiply : BlendMode.srcOver;
    final path = Path()
      ..moveTo(0, size.height / 2)
      ..quadraticBezierTo(
          size.width * 0.25, 4, size.width * 0.5, size.height / 2)
      ..quadraticBezierTo(size.width * 0.75, size.height - 4, size.width,
          size.height / 2);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StrokePreviewPainter old) =>
      old.color != color ||
      old.width != width ||
      old.isHighlighter != isHighlighter;
}

/// Bottom strip with chapter label + horizontally scrolling page thumbnails.
///
/// Shows the pages whose 1-based numbers are in [pageNumbers] (typically
/// just the active chapter's pages). Auto-scrolls to keep the current page
/// roughly centered. Each thumbnail renders a mini sketch (4 ruled lines)
/// so it reads as a "page" instead of an empty box. Real rendered
/// thumbnails (via ThumbnailService) can be plugged in later.
class HwBottomPageStrip extends StatefulWidget {
  final String? chapterLabel;

  /// 1-based page numbers to show. The strip mirrors the active chapter
  /// filter — when no filter is active this should be 1..totalPages.
  final List<int> pageNumbers;

  /// 1-based page number of the currently open page. May or may not be
  /// present in [pageNumbers] (if the user is on a page outside the
  /// filter, no thumbnail is highlighted).
  final int currentPage;

  /// 1-based page number of the page visited immediately before
  /// [currentPage]. The strip highlights it with a dashed/dotted outline
  /// so the user can flip between two pages with a single tap. `null`
  /// when there's no prior page (fresh notebook open).
  final int? previousPage;

  /// Tapping a thumbnail emits the underlying 1-based page number.
  final ValueChanged<int> onPageTap;
  /// Right-click / long-press on a thumbnail — opens a contextual menu.
  /// Receives the 1-based page number and the global tap position so the
  /// caller can position a popup menu correctly.
  final void Function(int pageNumber, Offset globalPosition)? onPageSecondary;
  final VoidCallback onAllPagesTap;
  /// Collapses the strip down to a thin handle (see [HwPageStripHandle]),
  /// reclaiming its height for the canvas. Null hides the affordance.
  final VoidCallback? onCollapse;

  const HwBottomPageStrip({
    super.key,
    this.chapterLabel,
    required this.pageNumbers,
    required this.currentPage,
    this.previousPage,
    required this.onPageTap,
    this.onPageSecondary,
    required this.onAllPagesTap,
    this.onCollapse,
  });

  @override
  State<HwBottomPageStrip> createState() => _HwBottomPageStripState();
}

class _HwBottomPageStripState extends State<HwBottomPageStrip> {
  static const double _itemWidth = 50;
  static const double _itemSpacing = 8;
  static const double _stride = _itemWidth + _itemSpacing;

  final ScrollController _ctrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(covariant HwBottomPageStrip old) {
    super.didUpdateWidget(old);
    final pagesChanged = old.pageNumbers.length != widget.pageNumbers.length;
    if (old.currentPage != widget.currentPage || pagesChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  void _scrollToCurrent() {
    if (!_ctrl.hasClients) return;
    final viewport = _ctrl.position.viewportDimension;
    if (viewport <= 0) return;
    final pos = widget.pageNumbers.indexOf(widget.currentPage);
    if (pos < 0) return; // current page is outside the filter — no scroll
    final desired = pos * _stride - (viewport - _itemWidth) / 2;
    final clamped =
        desired.clamp(0.0, _ctrl.position.maxScrollExtent).toDouble();
    _ctrl.animateTo(
      clamped,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 84,
      decoration: BoxDecoration(
        color: p.paper0,
        border: Border(top: BorderSide(color: p.paper3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          if (widget.chapterLabel != null &&
              widget.chapterLabel!.isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                widget.chapterLabel!.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: p.ink2,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(width: 1, height: 18, color: p.paper3),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: widget.pageNumbers.isEmpty
                ? Center(
                    child: Text(l10n.chromeNoPages,
                        style:
                            TextStyle(fontSize: 12, color: p.ink2)))
                : Listener(
                    // Mouse-wheel translates vertical wheel ticks into
                    // horizontal scroll on the strip, so a desktop user
                    // can flick through pages with the wheel without
                    // touching the trackpad.
                    onPointerSignal: (signal) {
                      if (signal is PointerScrollEvent &&
                          _ctrl.hasClients) {
                        final dy = signal.scrollDelta.dy;
                        final dx = signal.scrollDelta.dx;
                        final delta = dy.abs() > dx.abs() ? dy : dx;
                        final next = (_ctrl.offset + delta).clamp(
                          0.0,
                          _ctrl.position.maxScrollExtent,
                        );
                        _ctrl.jumpTo(next);
                      }
                    },
                    child: ListView.separated(
                    controller: _ctrl,
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.pageNumbers.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: _itemSpacing),
                    itemBuilder: (_, i) {
                      // n = global 1-based page number (used for navigation
                      // and right-click menu); displayLabel = position
                      // within the chapter (1..N). Showing the chapter
                      // position avoids confusing "gaps" in the displayed
                      // numbers when a chapter's pages are not contiguous
                      // in the overall notebook (e.g. simulations 185–207
                      // followed by 212+ when 208–211 belong elsewhere).
                      final n = widget.pageNumbers[i];
                      final selected = n == widget.currentPage;
                      final isPrevious = !selected &&
                          widget.previousPage != null &&
                          n == widget.previousPage;
                      final displayLabel = i + 1;
                      return _PageThumb(
                        number: displayLabel,
                        selected: selected,
                        previous: isPrevious,
                        globalPageNumber: n,
                        onTap: () => widget.onPageTap(n),
                        onSecondary: widget.onPageSecondary == null
                            ? null
                            : (pos) => widget.onPageSecondary!(n, pos),
                      );
                    },
                  ),
                  ),
          ),
          const SizedBox(width: 12),
          HwButton(
            leading: const HwIcon('grid', size: 14),
            label: l10n.chromeAllPages,
            onPressed: widget.onAllPagesTap,
          ),
          if (widget.onCollapse != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: l10n.chromeHidePageBar,
              waitDuration: const Duration(milliseconds: 400),
              child: HwButton.icon(
                icon: const HwIcon('chevron-down', size: 14),
                onPressed: widget.onCollapse,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Thin collapsed placeholder shown in place of [HwBottomPageStrip] once
/// the user hides it — a one-tap handle to bring it back, so hiding the
/// strip never costs more than a tap to undo.
class HwPageStripHandle extends StatelessWidget {
  final VoidCallback onExpand;
  const HwPageStripHandle({super.key, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.chromeShowPageBar,
      child: Tooltip(
        message: l10n.chromeShowPageBar,
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onExpand,
            child: Container(
              height: 16,
              width: double.infinity,
              decoration: BoxDecoration(
                color: p.paper0,
                border: Border(top: BorderSide(color: p.paper3)),
              ),
              child: Center(
                child: HwIcon('chevron-up', size: 12, color: p.ink2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Single thumbnail in the bottom strip — renders a mini ruled "page" so the
/// strip reads as content rather than empty boxes.
class _PageThumb extends StatelessWidget {
  /// Label shown inside the thumbnail (chapter-local position, 1..N).
  final int number;
  /// Real notebook page number (1-based) — used only for the tooltip
  /// so the user can still find the page in the global numbering.
  final int? globalPageNumber;
  final bool selected;
  /// Highlights the page the user was on right before the current one,
  /// so they can flip back with a single tap.
  final bool previous;
  final VoidCallback onTap;
  /// Right-click / long-press → contextual menu. Receives the global
  /// pointer position so the caller can anchor the menu correctly.
  final void Function(Offset globalPosition)? onSecondary;
  const _PageThumb({
    required this.number,
    required this.selected,
    required this.onTap,
    this.previous = false,
    this.globalPageNumber,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final tooltip = previous
        ? l10n.chromePrevPageTooltip(number)
        : (globalPageNumber != null && globalPageNumber != number
            ? l10n.chromePageOfChapterTooltip(number, globalPageNumber!)
            : l10n.chromePageTooltip(number));
    final Color borderColor;
    final double borderWidth;
    if (selected) {
      borderColor = p.accent;
      borderWidth = 1.8;
    } else if (previous) {
      borderColor = p.accentDeep;
      borderWidth = 1.6;
    } else {
      borderColor = p.paper3;
      borderWidth = 1;
    }
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTapDown: onSecondary == null
            ? null
            : (d) => onSecondary!(d.globalPosition),
        onLongPressStart: onSecondary == null
            ? null
            : (d) => onSecondary!(d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 50,
          decoration: BoxDecoration(
            color: previous && !selected ? p.accentSoft : p.paper0,
            border: Border.all(
              color: borderColor,
              width: borderWidth,
            ),
            borderRadius: BorderRadius.circular(3),
            boxShadow: selected ? hwShadow1(p.brightness) : null,
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(5, 5, 5, 2),
                      child: CustomPaint(
                        painter: _MiniPagePainter(
                          lineColor: p.ink3.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    alignment: Alignment.center,
                    color: selected
                        ? p.accent
                        : previous
                            ? p.accentDeep
                            : Colors.transparent,
                    child: Text(
                      number.toString(),
                      style: TextStyle(
                        fontSize: 9,
                        color: selected || previous ? p.paper0 : p.ink3,
                        fontFamily: HwTheme.fontMono,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              // "↺" badge on the previously visited page — visual cue that
              // this thumbnail is the quick way back.
              if (previous && !selected)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      color: p.accentDeep,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.history_rounded,
                      size: 9,
                      color: p.paper0,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _MiniPagePainter extends CustomPainter {
  final Color lineColor;
  _MiniPagePainter({required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    // 4 short ruled lines of decreasing length — mimics a written page.
    final lengths = [size.width * 0.95, size.width * 0.8, size.width * 0.6, size.width * 0.4];
    final ySpacing = size.height / (lengths.length + 1);
    for (int i = 0; i < lengths.length; i++) {
      final y = ySpacing * (i + 1);
      canvas.drawLine(Offset(0, y), Offset(lengths[i], y), paint);
    }
  }

  @override
  bool shouldRepaint(_MiniPagePainter old) => old.lineColor != lineColor;
}

// ═══════════════════════════════════════════════════════════════
//  CUSTOM COLOR PICKER DIALOG (color wheel)
// ═══════════════════════════════════════════════════════════════

/// Color picker triggered by the sweep-gradient chip in the tool popup.
/// Uses a classic color-wheel layout — a hue ring around a square that
/// drives saturation (X) and value (Y) — plus a value slider for fine
/// brightness control. Replaces an earlier 3-slider variant the user
/// found unwieldy.
Future<Color?> showHwColorPicker(BuildContext context, Color initial) {
  return showDialog<Color>(
    context: context,
    builder: (ctx) => _HwColorPickerDialog(initial: initial),
  );
}

class _HwColorPickerDialog extends StatefulWidget {
  final Color initial;
  const _HwColorPickerDialog({required this.initial});

  @override
  State<_HwColorPickerDialog> createState() => _HwColorPickerDialogState();
}

class _HwColorPickerDialogState extends State<_HwColorPickerDialog> {
  late HSVColor _hsv;
  late TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexCtrl = TextEditingController(text: _toHex(widget.initial));
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  String _toHex(Color c) {
    final argb = c.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _syncHexFromHsv() {
    _hexCtrl.text = _toHex(_hsv.toColor());
  }

  void _tryParseHex(String text) {
    final clean = text.trim().replaceAll('#', '');
    if (clean.length != 6) return;
    final v = int.tryParse(clean, radix: 16);
    if (v == null) return;
    setState(() {
      _hsv = HSVColor.fromColor(Color(0xFF000000 | v));
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final current = _hsv.toColor();
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = math.min(300.0, screenWidth - 48);
    final wheelSize = math.min(260.0, dialogWidth - 40);
    return AlertDialog(
      backgroundColor: p.paper0,
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Color wheel: hue ring + SV square at center ──
            _ColorWheel(
              size: wheelSize,
              hsv: _hsv,
              palette: p,
              onChanged: (h) => setState(() {
                _hsv = h;
                _syncHexFromHsv();
              }),
            ),
            const SizedBox(height: 12),
            // ── Value (brightness) slider — separate so users can dim
            // a saturated hue without losing position on the SV square.
            _ValueSlider(
              hsv: _hsv,
              palette: p,
              onChanged: (v) => setState(() {
                _hsv = _hsv.withValue(v);
                _syncHexFromHsv();
              }),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: current,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: p.paperEdge),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hexCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.chromeHexLabel,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: _tryParseHex,
                    onChanged: (v) {
                      if (v.replaceAll('#', '').length == 6) _tryParseHex(v);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.chromeCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(current),
          child: Text(l10n.chromeApply),
        ),
      ],
    );
  }
}

/// Color wheel: hue ring on the outside, saturation/value square in the
/// middle. Dragging on the ring sets hue; dragging inside the square
/// sets (saturation, value). Both gestures live in one widget so the
/// pointer naturally hands off when the user slides from one to the
/// other.
class _ColorWheel extends StatelessWidget {
  final double size;
  final HSVColor hsv;
  final HwPalette palette;
  final ValueChanged<HSVColor> onChanged;
  const _ColorWheel({
    required this.size,
    required this.hsv,
    required this.palette,
    required this.onChanged,
  });

  static const double _ringThickness = 28;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _handlePointer(d.localPosition),
        onPanUpdate: (d) => _handlePointer(d.localPosition),
        onTapDown: (d) => _handlePointer(d.localPosition),
        child: CustomPaint(
          painter: _ColorWheelPainter(
            hsv: hsv,
            ringThickness: _ringThickness,
            indicatorFill: palette.paper0,
            indicatorOutline: palette.ink0,
            neutralStroke: palette.ink2,
          ),
        ),
      ),
    );
  }

  void _handlePointer(Offset local) {
    final center = Offset(size / 2, size / 2);
    final outerR = size / 2;
    final innerR = outerR - _ringThickness;
    final v = local - center;
    final dist = v.distance;

    if (dist >= innerR - 4) {
      // On (or near) the hue ring — set hue from polar angle.
      final angle = math.atan2(v.dy, v.dx); // -pi..pi, 0 = +x axis
      // Map so 0° = red at the right (standard wheel orientation).
      final degRaw = angle * 180.0 / math.pi;
      final deg = (degRaw + 360) % 360;
      onChanged(hsv.withHue(deg));
      return;
    }

    // Otherwise we're in the SV square inscribed in the inner circle.
    final squareHalf = innerR / math.sqrt2; // largest square inside circle
    final sx = (local.dx - (center.dx - squareHalf)) / (squareHalf * 2);
    final sy = (local.dy - (center.dy - squareHalf)) / (squareHalf * 2);
    final s = sx.clamp(0.0, 1.0);
    final val = (1.0 - sy).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(s).withValue(val));
  }
}

class _ColorWheelPainter extends CustomPainter {
  final HSVColor hsv;
  final double ringThickness;
  /// Indicator-dot fill ring (paper0) + its thin outline (ink0) — keeps the
  /// hue/SV markers visible against any wheel colour in either theme.
  final Color indicatorFill;
  final Color indicatorOutline;
  /// Neutral stroke used where a low-contrast hairline reads better than a
  /// pure black/white edge.
  final Color neutralStroke;
  _ColorWheelPainter({
    required this.hsv,
    required this.ringThickness,
    required this.indicatorFill,
    required this.indicatorOutline,
    required this.neutralStroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = math.min(size.width, size.height) / 2;
    final innerR = outerR - ringThickness;

    // ── Hue ring ──
    final ringRect = Rect.fromCircle(
      center: center,
      radius: outerR - ringThickness / 2,
    );
    final hueGradient = const SweepGradient(
      colors: [
        Color(0xFFFF0000),
        Color(0xFFFFFF00),
        Color(0xFF00FF00),
        Color(0xFF00FFFF),
        Color(0xFF0000FF),
        Color(0xFFFF00FF),
        Color(0xFFFF0000),
      ],
    );
    final ringPaint = Paint()
      ..shader = hueGradient.createShader(
        Rect.fromCircle(center: center, radius: outerR),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringThickness;
    canvas.drawArc(ringRect, 0, 2 * math.pi, false, ringPaint);

    // ── Hue indicator dot on the ring ──
    final hueRad = hsv.hue * math.pi / 180;
    final hueR = outerR - ringThickness / 2;
    final hueDot = center + Offset(math.cos(hueRad), math.sin(hueRad)) * hueR;
    canvas.drawCircle(
      hueDot,
      ringThickness / 2 - 2,
      Paint()
        ..color = indicatorFill
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      hueDot,
      ringThickness / 2 - 2,
      Paint()
        ..color = indicatorOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // ── SV square inscribed in the inner circle ──
    final half = innerR / math.sqrt2;
    final square = Rect.fromCenter(
      center: center,
      width: half * 2,
      height: half * 2,
    );
    // Base color = pure hue (S=1, V=1).
    final pureHue = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    // Horizontal: white → pure hue (saturation).
    final satShader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Colors.white, pureHue],
    ).createShader(square);
    canvas.drawRect(square, Paint()..shader = satShader);
    // Vertical: transparent → black (value).
    final valShader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black],
    ).createShader(square);
    canvas.drawRect(square, Paint()..shader = valShader);

    // SV indicator inside the square.
    final sx = square.left + hsv.saturation * square.width;
    final sy = square.top + (1.0 - hsv.value) * square.height;
    canvas.drawCircle(
      Offset(sx, sy),
      7,
      Paint()
        ..color = indicatorFill
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(
      Offset(sx, sy),
      7,
      Paint()
        ..color = indicatorOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ColorWheelPainter old) =>
      old.hsv != hsv ||
      old.ringThickness != ringThickness ||
      old.indicatorFill != indicatorFill ||
      old.indicatorOutline != indicatorOutline ||
      old.neutralStroke != neutralStroke;
}

/// Brightness slider — pure hue at S=current on the right, fades to
/// black on the left. Separate from the SV square so dragging value
/// doesn't lose the saturation position.
class _ValueSlider extends StatelessWidget {
  final HSVColor hsv;
  final HwPalette palette;
  final ValueChanged<double> onChanged;
  const _ValueSlider(
      {required this.hsv, required this.palette, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final width = constraints.maxWidth;
        void onTouch(Offset local) {
          final v = (local.dx / width).clamp(0.0, 1.0);
          onChanged(v);
        }

        final fullColor = hsv.withValue(1).toColor();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => onTouch(d.localPosition),
          onPanUpdate: (d) => onTouch(d.localPosition),
          onTapDown: (d) => onTouch(d.localPosition),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 18,
                decoration: BoxDecoration(
                  // Left endpoint stays black: it is the value=0 anchor of
                  // the brightness gradient, not decorative chrome.
                  gradient: LinearGradient(colors: [Colors.black, fullColor]),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: palette.ink2),
                ),
              ),
              Positioned(
                left: (hsv.value.clamp(0.0, 1.0) * width) - 8,
                child: IgnorePointer(
                  child: Container(
                    width: 16,
                    height: 22,
                    decoration: BoxDecoration(
                      color: palette.paper0,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: palette.ink0, width: 1),
                      boxShadow: hwShadow1(palette.brightness),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

