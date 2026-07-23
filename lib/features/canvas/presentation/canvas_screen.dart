import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:abelnotes/core/services/desktop_window.dart';
import 'package:abelnotes/core/services/nextcloud_share_service.dart' show ShareLink;
import 'package:abelnotes/core/services/ocr_service.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/auth_provider.dart'
    show webdavServiceProvider, nextcloudShareServiceProvider;
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/providers/cross_notebook_clipboard_provider.dart';
import 'package:abelnotes/core/providers/pending_import_provider.dart';
import 'package:abelnotes/core/providers/preset_colors_provider.dart';
import 'package:abelnotes/core/services/sync_service.dart' as sync_svc;
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/features/canvas/data/math_rasterizer.dart';
import 'package:abelnotes/features/canvas/data/pdf_text_extractor.dart';
import 'package:abelnotes/features/canvas/presentation/pdf_text_selection.dart';
import 'package:abelnotes/shared/utils/rich_paste.dart';
import 'package:abelnotes/features/canvas/presentation/image_handle_overlay.dart';
import 'package:abelnotes/features/canvas/presentation/remote_changes_banner.dart';
import 'package:abelnotes/features/canvas/presentation/conflict_resolution_screen.dart';
import 'package:abelnotes/features/canvas/presentation/symbol_library_panel.dart';
import 'package:abelnotes/features/canvas/presentation/text_editor_dialog.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/shared/utils/html_text.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/core/services/pen_input_channel.dart';
import 'package:abelnotes/core/services/pen_monitor_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:abelnotes/features/canvas/presentation/canvas_painter_notifiers.dart';
import 'package:abelnotes/features/canvas/presentation/canvas_crop_dialog.dart';
import 'package:abelnotes/features/canvas/presentation/page_manager_sheet.dart';
import 'package:abelnotes/ui/editor/hw_editor_chrome.dart';
import 'package:abelnotes/ui/primitives/sync_badge.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';

enum _ExportScope { currentPage, currentChapter, entireNotebook }

/// Full export selection — scope + scope-specific options.
class _ExportSelection {
  final _ExportScope scope;
  // currentChapter only: 1-based inclusive range within the chapter's pages
  final int? rangeStart;
  final int? rangeEnd;
  // entireNotebook only: insert a divider page before each chapter
  final bool chapterSeparators;

  const _ExportSelection({
    required this.scope,
    this.rangeStart,
    this.rangeEnd,
    this.chapterSeparators = false,
  });
}

class CanvasScreen extends ConsumerStatefulWidget {
  const CanvasScreen({super.key});

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends ConsumerState<CanvasScreen>
    with WidgetsBindingObserver {
  bool _isSaving = false;
  Future<void>? _saveInFlight;
  bool _closing = false;
  bool _isTouchPanning = false;

  // Pinch-to-zoom state
  int _activePointers = 0;
  double _baseZoom = 1.0;
  Offset _lastFocalPoint = Offset.zero;

  // Lasso drag
  bool _isDraggingSelection = false;
  Offset _lastLassoDragPos = Offset.zero;

  // Hold-to-recognize shape (GoodNotes style)
  Timer? _holdRecognizeTimer;
  bool _shapeRecognizedDuringHold = false;
  Offset _lastHoldCheckPos = Offset.zero;

  // Drag-left to create new page / drag-right to go to previous page
  bool _showNewPageHint = false;
  bool _showPrevPageHint = false;
  bool _showNextPageHint = false;

  // Stylus barrel button — OneNote-style temporary tool override.
  // Two buttons supported (Wacom EMR / Surface / Galaxy stylus all
  // report the same Flutter button bits):
  //   - kTertiaryButton (0x04, upper barrel) → temporary eraser
  //   - kSecondaryButton (0x02, lower barrel) → temporary lasso
  // Whatever the user was using before the hold is restored on
  // pointer-up / pointer-cancel.
  bool _barrelButtonOverride = false;
  CanvasTool? _barrelButtonPreviousTool;

  // ── New chrome state (warm-paper redesign) ─────────────────────
  bool _popupOpen = false;

  // On-device handwriting recognition. Resolves to a no-op impl off
  // iOS/macOS, so `_ocr.isSupported` gates the UI entry point.
  final OcrService _ocr = createOcrService();

  // ── Presentation mode ───────────────────────────────────────────
  // Fullscreen, chrome-free view for showing pages to an audience: top bar,
  // floating dock and page strip all hidden. Page navigation still works via
  // the existing arrow-key handling above (unaffected by this flag) and via
  // tap zones on the canvas (see [_buildPresentationTapZones]). The laser
  // tool never leaves a mark, so we switch to it on entry (if the user
  // hasn't already picked it) and restore whatever tool was active before.
  bool _presentationMode = false;
  CanvasTool? _toolBeforePresentation;

  void _enterPresentationMode() {
    final current = ref.read(canvasProvider)?.currentTool;
    setState(() {
      _presentationMode = true;
      _toolBeforePresentation = current;
    });
    if (current != CanvasTool.laser) {
      ref.read(canvasProvider.notifier).setTool(CanvasTool.laser);
    }
    // SystemChrome.setEnabledSystemUIMode (already active since initState)
    // only hides the mobile status/nav bars — real desktop fullscreen goes
    // through our own runner channel (see DesktopWindow for why not a plugin).
    DesktopWindow.setFullScreen(true);
  }

  void _exitPresentationMode() {
    final restore = _toolBeforePresentation;
    setState(() {
      _presentationMode = false;
      _toolBeforePresentation = null;
    });
    if (restore != null) {
      ref.read(canvasProvider.notifier).setTool(restore);
    }
    DesktopWindow.setFullScreen(false);
  }

  /// Small, corner-bounded controls only — never a full-screen tap layer.
  /// The canvas underneath must keep receiving every pointer event for the
  /// laser tool to work, so these are the same footprint as the existing
  /// dock/page-strip-handle overlays (bounded hit area, not a tap-catcher).
  List<Widget> _presentationOverlay(CanvasState canvasState) {
    final notifier = ref.read(canvasProvider.notifier);
    return [
      Positioned(
        top: 16,
        right: 16,
        child: _PresentationIconButton(
          icon: Icons.close_rounded,
          onTap: _exitPresentationMode,
        ),
      ),
      Positioned(
        bottom: 16,
        left: 16,
        child: _PresentationIconButton(
          icon: Icons.chevron_left_rounded,
          onTap: () => notifier.prevPage(resetViewport: true),
        ),
      ),
      Positioned(
        bottom: 16,
        right: 16,
        child: _PresentationIconButton(
          icon: Icons.chevron_right_rounded,
          onTap: () => notifier.nextPage(resetViewport: true),
        ),
      ),
    ];
  }

  // ── Movable tool dock ──────────────────────────────────────────
  // The dock parks on one of four screen edges (left/right render it
  // vertically). The persisted edge + along-edge alignment live in
  // AppSettings.toolDock — this screen only holds transient drag state.
  // While the user drags the grip, [_dockDragOffset] holds the dock's
  // top-left in Stack-local coordinates and the dock follows the finger;
  // on release we snap to the nearest edge and write it back to settings.
  Offset? _dockDragOffset;
  Size _dockDragSize = Size.zero;
  Size _dockArea = Size.zero;
  final GlobalKey _dockKey = GlobalKey();
  final GlobalKey _stackKey = GlobalKey();

  // Dock placement geometry. The insets keep the docked toolbar clear of
  // the 52px top bar and the 84px bottom page strip; the thickness is the
  // dock's short-axis size (40px button + 6px padding on each side).
  static const double _dockTopInset = 64;
  static const double _dockBottomInset = 110;
  static const double _dockSideInset = 16;
  static const double _dockThickness = 52;
  static const double _dockPopupGap = 12;

  // ── Arrow-key hold acceleration ────────────────────────────────
  // Tracks consecutive same-direction arrow presses so holding the
  // key gradually jumps multiple pages per tick instead of one.
  // Reset whenever the gap between events exceeds ~220 ms (typical
  // OS key-repeat is ~30 Hz, so 220 ms gives a comfortable margin).
  DateTime? _lastArrowAt;
  int _lastArrowDir = 0; // -1 = left, 1 = right
  int _arrowHoldCount = 0;

  // Long-press context menu for touch
  Timer? _longPressTimer;
  Offset _longPressGlobalPos = Offset.zero;
  bool _longPressFired = false;

  // Track last stroke activity to suppress long-press menu while drawing
  DateTime _lastStrokeActivity = DateTime(0);

  // Track whether the stylus is physically touching the screen right now
  bool _stylusDown = false;

  // ── Stroke break debug ──
  // Records when the previous stroke finalized (commit / end / cancel).
  // On next stylus DOWN, gap < 200 ms is flagged as a likely break event
  // so the iPad-side log can pinpoint who is tearing strokes mid-pen-down.
  // Helper [_strokeDbg] writes a tagged line to CrashLogger; only DOWN /
  // UP / CANCEL are logged (not MOVE) to keep the log readable.
  DateTime? _strokeEndedAt;
  String _lastStrokeEndReason = 'never';

  // ── Deferred stylus commit (iPad spurious Up→Down protection) ──
  // On stylus PointerUp we hold the points for [_deferStylusMs] ms instead
  // of committing immediately. If a fresh stylus PointerDown arrives in
  // that window close in space (<= [_deferStylusPx] screen px) and time,
  // we resume the same stroke — preventing the visible mid-letter break
  // caused by Apple Pencil sample dropouts / iOS pointer rebatching.
  //
  // Tuning rationale:
  //   * Hardware spurious Up→Down has dist ≈ 0–3 logical px (the pen does
  //     not move during a sample dropout) and gap ≈ a few ms.
  //   * A deliberate new stroke (lift the pen, move, set down) takes the
  //     user 60+ ms even at sketch speed and lands a few px away once the
  //     pen has actually moved.
  //   * The previous 80 ms / 10 px window was generous enough to swallow
  //     short fast taps as "continuation": the new stroke would graft
  //     onto the tail of the previous one and the user saw a phantom
  //     line stretching from the old end-point to where they actually
  //     wrote. Tightened to 50 ms / 4 px — still well above any real
  //     hardware glitch but no longer captures intentional re-strokes.
  static const int _deferStylusMs = 50;
  static const double _deferStylusPx = 4.0;
  Timer? _deferredCommitTimer;
  List<StrokePoint>? _deferredCommitPoints;
  DateTime? _deferredCommitAt;
  Offset? _deferredCommitLastScreenPos;
  /// True for the very next pointer-move after a "continuation" decision —
  /// lets us double-check that the new pointer position is actually close
  /// to the tail of the kept-alive stroke. If the user really started a
  /// fresh stroke that just happened to land within the defer window, the
  /// first move will be far away from the kept tail; in that case we
  /// commit the old stroke and start a new one. Without this guard, the
  /// new mark would graft onto the previous stroke, producing the
  /// "phantom line stretching from the old end-point" bug.
  bool _justContinuedFromDefer = false;

  // [StrokeDbg] logging is gated by [CrashLogger.verboseEnabled] (default
  // false). Set that flag to true to re-enable [Pull], [Mem], [StrokeDbg]
  // and [Retry] tags all at once when investigating an issue.
  void _strokeDbg(String msg) {
    CrashLogger.append('[StrokeDbg] $msg');
  }

  void _markStrokeEnded(String reason) {
    _strokeEndedAt = DateTime.now();
    _lastStrokeEndReason = reason;
  }

  /// Flush a deferred stylus commit immediately (timer fired, or another
  /// code path needs the stroke to be persisted right now). Commits to
  /// provider state THEN clears the live notifier so the rendered stroke
  /// transitions seamlessly from "live (notifier)" to "committed (state
  /// strokes)" inside the same frame — no flicker.
  void _flushDeferredCommit() {
    final pts = _deferredCommitPoints;
    if (pts == null) return;
    _deferredCommitPoints = null;
    _deferredCommitAt = null;
    _deferredCommitLastScreenPos = null;
    _deferredCommitTimer?.cancel();
    _deferredCommitTimer = null;
    // Clear the live notifier BEFORE the commit so the painter, which
    // pulls from the notifier when it has points, doesn't keep drawing
    // the old stroke as "live" alongside the freshly-committed one.
    // Forgetting this clear was the cause of the "phantom segment from
    // a previous stroke when I start drawing again" bug — if the next
    // pointer event arrived as a MOVE rather than a fresh DOWN (iPad
    // sometimes resumes from a hovering pen this way), the move would
    // append to the still-active notifier and the user saw a line from
    // the old end-point stretching to where they really wrote.
    _activeStrokeNotifier.clear();
    _justContinuedFromDefer = false;
    ref.read(canvasProvider.notifier).commitAndEndStroke(pts);
    _activeStrokeNotifier.clear();
    _markStrokeEnded('pointerUp.commit');
  }

  // Double-tap detection for element selection
  DateTime _lastTapTime = DateTime(0);
  Offset _lastTapPos = Offset.zero;

  /// Signature of the system-clipboard image we currently treat as "already
  /// seen" — i.e. NOT newer than the in-app clipboard. Set when we write an
  /// image to the system clipboard (our own Ctrl+C of an image) and when the
  /// user makes an internal non-image copy while a stale image happens to sit
  /// on the system clipboard. Lets Ctrl+V tell a freshly-copied EXTERNAL
  /// image (→ paste it) from a stale one (→ use the richer in-app clipboard).
  /// Fixes "copy an image, Ctrl+V pastes the old in-app text instead".
  String? _seenSystemImageSig;
  String? _seenSystemTextSig;

  /// The most recent (possibly still-running) `_markSystemImageSeen()` call.
  /// A copy snapshots the system clipboard's identity ASYNCHRONOUSLY; a paste
  /// that fires right after (a user testing "does Ctrl+C/Ctrl+V work?" presses
  /// them milliseconds apart) MUST await this snapshot first — otherwise it
  /// compares the fresh system content against a STALE seen-sig, wrongly
  /// decides the external clipboard is "newer", and pastes the old image/text
  /// instead of what was just copied in-app. Awaited at the top of paste.
  Future<void>? _seenSnapshotInFlight;

  // Cached canvas size for pointer-up page-drag commit
  Size _lastCanvasSize = Size.zero;

  // ── High-performance active stroke notifier ──
  final _activeStrokeNotifier = ActiveStrokeNotifier();
  // ── High-performance lasso path notifier (avoids Riverpod rebuild per point) ──
  final _lassoPathNotifier = LassoPathNotifier();
  // ── Laser pointer trail (fades out, never committed) ──
  final _laserStrokeNotifier = LaserStrokeNotifier();
  // ── Live transform of an existing lasso selection (drag/rotate/scale) ──
  // Updated on every pointer-move so the painter repaints without firing
  // a Riverpod state update; committed back to Riverpod once on pan-end.
  final _lassoTransformNotifier = LassoTransformNotifier();
  // ── Live transform of a single non-lasso element (image / shape / text
  // selected via double-tap). Same purpose as the lasso notifier — bypass
  // Riverpod during the gesture, commit once on pan-end.
  final _elementTransformNotifier = ElementTransformNotifier();
  // Cached Listenable.merge for the CustomPaint.repaintNotifier — avoids
  // rebuilding the composite on every parent rebuild (each new merge re-
  // subscribes to both underlying notifiers, which is non-trivial work on
  // the hot draw path).
  late final Listenable _repaintNotifier = Listenable.merge([
    _activeStrokeNotifier,
    _lassoPathNotifier,
    _lassoTransformNotifier,
    _elementTransformNotifier,
    _laserStrokeNotifier,
    // imageCache changes (asset decode lands, eviction, pull merge)
    // ride the same repaint listenable now — used to be observed via
    // ref.watch(canvasProvider.select(s.imageCache)) which fired the
    // full Riverpod consumer cascade on every PDF-import decode.
    ref.read(canvasProvider.notifier).imageCacheVersion,
    // Math raster fills bump this so the equation appears on the next frame.
    ref.read(canvasProvider.notifier).mathCacheVersion,
  ]);

  /// Fixed device-pixel-ratio to rasterize math at — clamped to a crisp
  /// range and NOT multiplied by zoom, so the math cache key is stable
  /// across zoom (the cached bitmap scales like an image instead of
  /// re-rasterizing on every pinch — see critic note A4).
  double _mathPixelRatio(BuildContext context) =>
      MediaQuery.of(context).devicePixelRatio.clamp(2.0, 3.5);

  // ── Auto-save (debounced) ──
  //
  // We save after a short idle window (no new edits) so rapid strokes batch
  // into a single disk write. A second "max delay" timer guarantees we never
  // defer more than _autoSaveMaxDelay even if the user keeps drawing.
  //
  // Idle window tuned down from 4 s to 1.2 s so small-stroke edits reach
  // the server in ~2-3 s end-to-end on Tailscale instead of the old 6-8 s.
  // The hot-path save() is now non-blocking (remote delta fires first,
  // local ZIP rebuild runs in the background), so firing it more often
  // no longer pauses the UI.
  Timer? _autoSaveDebounce;
  Timer? _autoSaveMaxWait;
  bool _wasDirty = false;
  static const _autoSaveIdle = Duration(milliseconds: 1200);
  static const _autoSaveMaxDelay = Duration(seconds: 15);

  // Key for the canvas Stack to convert coordinates properly
  final _canvasStackKey = GlobalKey();

  // ── PDF text selection ──
  // Selection controller for the current page's invisible PDF text layer.
  // Rebuilt whenever the page's layer identity changes; null when the page
  // has no extracted text. Lives in page-logical coords so zoom/pan don't
  // invalidate a selection.
  PdfTextSelectionController? _pdfTextSelController;
  PdfTextLayer? _pdfTextSelLayer;
  /// True while a device-aware text-selection drag is in progress (mouse over
  /// text). Gates the move/up handlers so the drag is independent of the tool.
  bool _pdfTextDragActive = false;
  /// True while the mouse is dragging a marquee (the mouse is a pure selection
  /// device — it never draws). Drives [_lassoPathNotifier] directly.
  bool _mouseSelecting = false;

  /// Which physical input last touched the canvas — null until the first
  /// pointer event. Used only to decide, at the moment of an EXPLICIT tool
  /// pick (dock tap / keyboard shortcut, see [_pickTool]), whether that pick
  /// was meant for the mouse. Kept up to date from [_onPointerDown] and the
  /// hover handler so it reflects the device currently in the user's hand,
  /// not just whichever last happened to click.
  bool? _lastPointerWasMouse;

  /// Ink tools for which the MOUSE acts as a selection device instead
  /// (text / element / marquee). Pan, lasso, the erasers, and the explicit
  /// shape/laser tools are excluded — they keep their own mouse behaviour, so
  /// the mouse can still draw a shape or point the laser when deliberately
  /// chosen.
  static const Set<CanvasTool> _mouseSelectTools = {
    CanvasTool.pen,
    CanvasTool.ballpoint,
    CanvasTool.brush,
    CanvasTool.calligraphy,
    CanvasTool.highlighter,
  };

  /// Explicit tool pick — dock tap or keyboard shortcut, as opposed to the
  /// transient barrel-button / native-barrel overrides (which restore
  /// afterwards and must NOT go through here). If the mouse was the last
  /// input to touch the canvas, picking an ink tool means "yes, draw with
  /// the mouse now" and picking lasso means "back to pure selection" — so
  /// `mouseDraws` always tracks the user's last deliberate choice instead of
  /// being a separate hidden toggle the toolbar selection can contradict.
  void _pickTool(CanvasTool tool) {
    ref.read(canvasProvider.notifier).setTool(tool);
    if (_lastPointerWasMouse != true) return;
    if (_mouseSelectTools.contains(tool)) {
      ref.read(appSettingsProvider.notifier).setMouseDraws(true);
    } else if (tool == CanvasTool.lasso) {
      ref.read(appSettingsProvider.notifier).setMouseDraws(false);
    }
  }

  /// Tool the floating dock should show as active. Normally the real tool,
  /// but while the mouse is acting as a pure selector (mouseDraws == false)
  /// an ink tool would otherwise show as active while a mouse click actually
  /// selects — showing Lasso instead keeps the dock truthful to what a
  /// mouse click will do right now.
  CanvasTool _dockDisplayTool(CanvasState state, bool mouseDraws) {
    if (_lastPointerWasMouse == true &&
        !mouseDraws &&
        _mouseSelectTools.contains(state.currentTool)) {
      return CanvasTool.lasso;
    }
    return state.currentTool;
  }
  /// Cursor shown while a MOUSE hovers the canvas (null ⇒ use the tool's
  /// default — e.g. the pen crosshair). Set device-aware in onPointerHover so
  /// the pen keeps its drawing cursor while the mouse shows the selection one
  /// (arrow, or I-beam over PDF text).
  final ValueNotifier<MouseCursor?> _mouseHoverCursor =
      ValueNotifier<MouseCursor?>(null);

  /// Returns the selection controller for [state]'s current page, creating or
  /// swapping it when the page's text layer changes, or null if none.
  PdfTextSelectionController? _ensurePdfTextSel(CanvasState state) {
    final layer = state.currentPage?.pdfTextLayer;
    if (layer == null) {
      if (_pdfTextSelController != null) {
        _pdfTextSelController!.dispose();
        _pdfTextSelController = null;
        _pdfTextSelLayer = null;
      }
      return null;
    }
    if (!identical(layer, _pdfTextSelLayer)) {
      _pdfTextSelController?.dispose();
      _pdfTextSelController = PdfTextSelectionController(layer);
      _pdfTextSelLayer = layer;
    }
    return _pdfTextSelController;
  }

  Future<void> _copyPdfTextToClipboard(String text) async {
    if (text.isEmpty) return;
    try {
      final item = DataWriterItem();
      item.add(Formats.plainText(text));
      await SystemClipboard.instance?.write([item]);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context).csPdfTextCopied),
              duration: const Duration(seconds: 1)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).csCopyFailed(e.toString()))));
      }
    }
  }

  /// Highlight overlay + copy button for the active PDF text selection.
  /// Highlights are IgnorePointer so the canvas pointer pipeline (which drives
  /// the selection) keeps receiving events; only the copy button is tappable.
  Widget _buildPdfTextSelectionLayer(
      PdfTextSelectionController sel, CanvasState state, Size canvasSize) {
    final renderScale = _getRenderScale(state, canvasSize);
    final screenScale = renderScale * state.zoom;
    Rect pageRectToScreen(Rect r) {
      final tl = _toScreenCoords(r.topLeft, state, canvasSize);
      return Rect.fromLTWH(
          tl.dx, tl.dy, r.width * screenScale, r.height * screenScale);
    }

    return ListenableBuilder(
      listenable: sel,
      builder: (context, _) {
        final p = HwThemeScope.of(context);
        final screenRects = [
          for (final r in sel.selectedPageRects()) pageRectToScreen(r)
        ];
        final boundsPage = sel.selectionBoundsPage();
        return Stack(
          children: [
            IgnorePointer(
              child: CustomPaint(
                size: canvasSize,
                painter: _PdfSelectionPainter(
                    screenRects, p.accentDeep.withValues(alpha: 0.28)),
              ),
            ),
            if (boundsPage != null)
              _pdfCopyButton(pageRectToScreen(boundsPage), sel, canvasSize, p),
          ],
        );
      },
    );
  }

  Widget _pdfCopyButton(Rect screenBounds, PdfTextSelectionController sel,
      Size canvasSize, HwPalette p) {
    const btnW = 104.0, btnH = 36.0, gap = 8.0;
    double left = screenBounds.right - btnW;
    double top = screenBounds.top - btnH - gap;
    if (top < 8) top = screenBounds.bottom + gap; // flip below if no room above
    left = left.clamp(8.0, max(8.0, canvasSize.width - btnW - 8));
    top = top.clamp(8.0, max(8.0, canvasSize.height - btnH - 8));
    return Positioned(
      left: left,
      top: top,
      child: Material(
        color: p.ink0,
        borderRadius: BorderRadius.circular(18),
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _copyPdfTextToClipboard(sel.selectedText()),
          child: SizedBox(
            width: btnW,
            height: btnH,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                HwIcon('copy', size: 16, color: p.paper0),
                const SizedBox(width: 6),
                Text(AppLocalizations.of(context).csCopy,
                    style: TextStyle(
                        color: p.paper0,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Keyboard shortcuts ──
  final _focusNode = FocusNode();

  // ── Movable tool dock helpers ──────────────────────────────────

  DockPosition _edgePosition(String edge) {
    switch (edge) {
      case 'left':
        return DockPosition.left;
      case 'right':
        return DockPosition.right;
      case 'top':
        return DockPosition.top;
      default:
        return DockPosition.bottom;
    }
  }

  /// Map a 0..1 along-edge fraction to Flutter's -1..1 [Alignment] axis.
  double _alignToAxis(double align) => (align.clamp(0.0, 1.0) * 2) - 1;

  void _onDockDragStart(DragStartDetails _) {
    final dockCtx = _dockKey.currentContext;
    final stackCtx = _stackKey.currentContext;
    if (dockCtx == null || stackCtx == null) return;
    final dockBox = dockCtx.findRenderObject() as RenderBox?;
    final stackBox = stackCtx.findRenderObject() as RenderBox?;
    if (dockBox == null || stackBox == null) return;
    final topLeft = stackBox.globalToLocal(dockBox.localToGlobal(Offset.zero));
    // Grabbing the dock cancels any pending canvas long-press so the
    // context menu can't fire mid-drag (e.g. a resting finger started the
    // 600ms timer just before the other hand grabbed the grip).
    _cancelLongPressTimer();
    setState(() {
      _dockDragSize = dockBox.size;
      _dockDragOffset = topLeft;
      // A panel that floats around mid-drag is more distracting than
      // useful — close it; the user reopens it after parking the dock.
      _popupOpen = false;
    });
    HapticFeedback.selectionClick();
  }

  void _onDockDragUpdate(DragUpdateDetails d) {
    final base = _dockDragOffset;
    if (base == null) return;
    var next = base + d.delta;
    final area = _dockArea;
    if (area.width > 0 && area.height > 0) {
      // Keep the whole dock on-screen while dragging.
      next = Offset(
        next.dx.clamp(0.0, max(0.0, area.width - _dockDragSize.width)),
        next.dy.clamp(0.0, max(0.0, area.height - _dockDragSize.height)),
      );
    }
    setState(() => _dockDragOffset = next);
  }

  void _onDockDragEnd(DragEndDetails _) {
    final off = _dockDragOffset;
    final area = _dockArea;
    if (off == null || area.width <= 0 || area.height <= 0) {
      setState(() => _dockDragOffset = null);
      return;
    }
    final center = off +
        Offset(_dockDragSize.width / 2, _dockDragSize.height / 2);
    // Snap to whichever of the four edges the dock's centre is nearest.
    final dLeft = center.dx;
    final dRight = area.width - center.dx;
    final dTop = center.dy;
    final dBottom = area.height - center.dy;
    final nearest = [dLeft, dRight, dTop, dBottom].reduce(min);

    final String edge;
    final double align;
    if (nearest == dTop) {
      edge = 'top';
      align = _spanFraction(
          center.dx, _dockSideInset, area.width - _dockSideInset);
    } else if (nearest == dBottom) {
      edge = 'bottom';
      align = _spanFraction(
          center.dx, _dockSideInset, area.width - _dockSideInset);
    } else if (nearest == dLeft) {
      edge = 'left';
      align = _spanFraction(
          center.dy, _dockTopInset, area.height - _dockBottomInset);
    } else {
      edge = 'right';
      align = _spanFraction(
          center.dy, _dockTopInset, area.height - _dockBottomInset);
    }

    setState(() => _dockDragOffset = null);
    ref.read(appSettingsProvider.notifier).setToolDock(edge, align);
    HapticFeedback.lightImpact();
  }

  /// Normalise [v] within [lo, hi] to a 0..1 fraction (clamped).
  double _spanFraction(double v, double lo, double hi) {
    if (hi <= lo) return 0.5;
    return ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
  }

  /// Place the docked toolbar against its edge. Left/right anchor to the
  /// side and centre vertically by [align]; top/bottom anchor to the
  /// top/bottom and centre horizontally by [align].
  Widget _dockedPositioned(DockPosition pos, double align, Widget child) {
    final axis = _alignToAxis(align);
    switch (pos) {
      case DockPosition.left:
        return Positioned(
          left: _dockSideInset,
          top: _dockTopInset,
          bottom: _dockBottomInset,
          child: Align(alignment: Alignment(0, axis), child: child),
        );
      case DockPosition.right:
        return Positioned(
          right: _dockSideInset,
          top: _dockTopInset,
          bottom: _dockBottomInset,
          child: Align(alignment: Alignment(0, axis), child: child),
        );
      case DockPosition.top:
        return Positioned(
          left: _dockSideInset,
          right: _dockSideInset,
          top: _dockTopInset,
          child: Align(alignment: Alignment(axis, 0), child: child),
        );
      case DockPosition.bottom:
      case DockPosition.floating:
        return Positioned(
          left: _dockSideInset,
          right: _dockSideInset,
          bottom: _dockBottomInset,
          child: Align(alignment: Alignment(axis, 0), child: child),
        );
    }
  }

  /// Place the tool popup adjacent to the docked toolbar: above for the
  /// bottom edge, below for the top, and to the inner side for left/right.
  /// For the vertical edges we position by an estimated height so the
  /// ~300px panel can never be clipped against the top/bottom of the band.
  Widget _popupPositioned(
      DockPosition pos, double align, Size area, Widget child) {
    final axis = _alignToAxis(align);
    const offset = _dockSideInset + _dockThickness + _dockPopupGap;
    switch (pos) {
      case DockPosition.left:
      case DockPosition.right:
        const popupHeightGuess = 380.0;
        const bandTop = _dockTopInset;
        final bandBottom = area.height - _dockBottomInset;
        final top = (bandTop +
                (bandBottom - bandTop - popupHeightGuess) * align)
            .clamp(bandTop, max(bandTop, bandBottom - popupHeightGuess))
            .toDouble();
        return Positioned(
          left: pos == DockPosition.left ? offset : null,
          right: pos == DockPosition.right ? offset : null,
          top: top,
          child: child,
        );
      case DockPosition.top:
        return Positioned(
          left: _dockSideInset,
          right: _dockSideInset,
          top: _dockTopInset + _dockThickness + _dockPopupGap,
          child: Align(alignment: Alignment(axis, 0), child: child),
        );
      case DockPosition.bottom:
      case DockPosition.floating:
        return Positioned(
          left: _dockSideInset,
          right: _dockSideInset,
          bottom: _dockBottomInset + _dockThickness + _dockPopupGap,
          child: Align(alignment: Alignment(axis, 0), child: child),
        );
    }
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addObserver(this);
    _startAutoSave();
    _watchForPendingImport();
    // Hook the Windows-side pen-button bridge. No-op on other
    // platforms. See PenInputChannel for why this exists.
    _watchForLassoCleared();
    PenInputChannel.register(
      onBarrel: (down) => _onNativeBarrelChange(_NativeBarrel.lower, down),
      onInverted: (down) => _onNativeBarrelChange(_NativeBarrel.upper, down),
      onBarrelPen: _onBarrelPen,
    );
    // Linux-only: receive stylus pressure the GTK embedder drops. No-op
    // elsewhere. See LinuxPenPressure / _penPressure.
    LinuxPenPressure.register();
    // Let the provider's save-prep pause while a stroke is mid-flight.
    // The ActiveStrokeNotifier is screen-local (it bypasses Riverpod for
    // perf), so the provider can't see pen-down state without this probe.
    // Cleared in dispose() before the notifier itself is disposed.
    ref.read(canvasProvider.notifier).strokeActiveProbe =
        () => _activeStrokeNotifier.isActive;
  }

  /// Pressure for the active pen sample, with the Linux fallback applied.
  ///
  /// On Linux the GTK embedder always reports `event.pressure == 0` for a
  /// stylus (flutter#63209), so we substitute the latest real pressure the
  /// native bridge captured. Everywhere else (and when no fresh bridge
  /// sample exists) we return the raw event pressure unchanged — devices
  /// that genuinely have no pressure (mouse) keep returning 0 so the
  /// notifier's velocity-synth path still kicks in.
  double _penPressure(PointerEvent event) {
    final raw = _normalizedEventPressure(event);
    if (raw > 0.0 || kIsWeb || !io.Platform.isLinux) return raw;
    final bridged = LinuxPenPressure.latest();
    return bridged > 0 ? bridged : raw;
  }

  /// `PointerEvent.pressure` rescaled to the 0..1 range the whole app
  /// assumes.
  ///
  /// The Windows embedder forwards the RAW digitizer pressure (0..1024,
  /// `pressure_max = kMaxPenPressure = 1024` in the engine's
  /// flutter_window.cc) instead of a normalized value, so a stylus event
  /// arrives with pressure ≈ 300–900 — every width-modulation curve
  /// downstream clamps that to "always max" and strokes come out at a
  /// constant thickness. Rescale by pressureMin/Max only on Windows:
  /// iOS deliberately reports max ≈ 6.67 with 1.0 = "normal press", and
  /// rescaling there would flatten Apple Pencil strokes.
  double _normalizedEventPressure(PointerEvent event) {
    if (!kIsWeb && io.Platform.isWindows && event.pressureMax > 1.0) {
      final range = event.pressureMax - event.pressureMin;
      if (range > 0) {
        return ((event.pressure - event.pressureMin) / range)
            .clamp(0.0, 1.0)
            .toDouble();
      }
    }
    return event.pressure;
  }

  /// Active native-barrel override — `null` when neither side button
  /// is held. Distinct from `_barrelButtonOverride` (which is the
  /// pointer-event-side override for Wacom-class stylus pens that DO
  /// report buttons through Flutter's normal pipeline).
  _NativeBarrel? _activeNativeBarrel;
  CanvasTool? _nativeBarrelPreviousTool;

  /// Pointer IDs of synth middle-mouse events the Gaomon driver injects
  /// in parallel with the real stylus stream when barrel-held + tip-
  /// contact. Tracked so the matching move/up/cancel can be dropped
  /// without touching `_activePointers` — otherwise the parallel synth
  /// pointer pushes the counter to 2 and the multi-touch guard in
  /// `_onPointerMove` drops every lasso point.
  final Set<int> _suppressedSynthBarrelPointers = <int>{};

  /// Pointer IDs of palm touches that landed while the stylus was drawing.
  /// They are ignored on DOWN — and must NOT stay counted in
  /// `_activePointers` either: a counted palm froze the stylus stroke
  /// (the `>= 2` guard in `_onPointerMove` dropped every pen move) and
  /// suppressed the pen-up commit, losing all ink drawn after the wrist
  /// touched the screen. Tracked so their UP/CANCEL skips the decrement.
  final Set<int> _ignoredPalmPointers = <int>{};

  /// Tool the current bridge-driven pen gesture is driving. Set on
  /// `_onBarrelPen("down", …)` from the live state and used through
  /// `"up"` so the commit doesn't depend on `_activeNativeBarrel`
  /// still being non-null at that moment (the C++ bridge fires "up"
  /// before any matching barrel-release transition, so this normally
  /// holds — but if the user releases the barrel BEFORE lifting the
  /// tip the bridge tears the gesture down first, and the captured
  /// tool here lets us still commit the partial path).
  CanvasTool? _bridgePenTool;

  /// Called by the WM_POINTER bridge when the user presses or releases
  /// a side button. Press = save the current tool and switch to the
  /// override target; release = restore.
  void _onNativeBarrelChange(_NativeBarrel button, bool down) {
    if (!mounted) return;
    final notif = ref.read(canvasProvider.notifier);
    final state = ref.read(canvasProvider);
    if (state == null) return;

    if (down) {
      // Already in another override → ignore the second press so the
      // restore-tool slot doesn't get clobbered.
      if (_activeNativeBarrel != null) return;
      _activeNativeBarrel = button;
      _nativeBarrelPreviousTool = state.currentTool;
      switch (button) {
        case _NativeBarrel.upper:
          // Honour the user's last-picked eraser sub-mode (per-stroke
          // vs per-area) instead of hardcoding eraserStroke.
          notif.setTool(notif.lastEraserMode);
          break;
        case _NativeBarrel.lower:
          notif.setTool(CanvasTool.lasso);
          break;
      }
      HapticFeedback.selectionClick();
    } else {
      // Release only restores if we were actually overriding via
      // THIS button — guards against the C++ defensive-release path
      // firing twice or a transient flap.
      if (_activeNativeBarrel != button) return;
      _activeNativeBarrel = null;
      // If the lower-barrel lasso override just committed a real
      // selection (polygon caught at least one element), stay in
      // lasso so the user can manipulate it — drag / scale / rotate
      // / duplicate / delete. Restoring the previous tool here would
      // run `setTool(prev)`, whose `clearLasso: tool != lasso`
      // copyWith wipes `lassoSelection` and the marquee visibly
      // disappears the instant the user releases the barrel. We
      // KEEP `_nativeBarrelPreviousTool` set in that case — the
      // `_watchForLassoCleared` listener restores the tool when the
      // user eventually deselects (tap outside / clearSelection /
      // anything that nulls `lassoSelection`).
      final live = ref.read(canvasProvider);
      final keepLassoForSelection = button == _NativeBarrel.lower &&
          live?.lassoSelection != null;
      if (keepLassoForSelection) return;
      // Race fix: if the pen gesture is still in progress, the lasso / text
      // selection hasn't committed yet (it commits on pointer-up). Reverting
      // now would wipe a selection the user is mid-way through making — the
      // "faccio il cerchio e mollo, non mi prende la selezione" bug. Defer the
      // keep/revert to _onPointerUp (see _resolveBarrelRevert).
      if (_stylusDown || _pdfTextDragActive) {
        _barrelRevertPending = true;
        return;
      }
      final prev = _nativeBarrelPreviousTool;
      _nativeBarrelPreviousTool = null;
      if (prev != null) notif.setTool(prev);
    }
  }

  /// True after the barrel was released mid-gesture; _onPointerUp resolves the
  /// keep-or-revert once the lasso / text selection has actually committed.
  bool _barrelRevertPending = false;

  /// Resolve a deferred barrel revert (see [_onNativeBarrelChange]). Keeps
  /// lasso mode when elements were selected, otherwise restores the pre-barrel
  /// tool. A PDF text selection persists regardless (it isn't tool-bound).
  void _resolveBarrelRevert() {
    if (!_barrelRevertPending) return;
    _barrelRevertPending = false;
    if (_activeNativeBarrel != null) return; // barrel re-pressed; it will own it
    final live = ref.read(canvasProvider);
    if (live?.lassoSelection != null) {
      // Stay in lasso so the marquee is interactive; _watchForLassoCleared
      // restores the previous tool when the user deselects.
      return;
    }
    final prev = _nativeBarrelPreviousTool;
    _nativeBarrelPreviousTool = null;
    if (prev != null) ref.read(canvasProvider.notifier).setTool(prev);
  }

  /// Restore the previous tool when a barrel-driven lasso selection
  /// is cleared. The barrel-release path intentionally keeps the user
  /// in lasso mode while `lassoSelection != null` so the marquee is
  /// interactive (drag / scale / duplicate). When the user finally
  /// deselects — by tapping outside the marquee, by `clearSelection`,
  /// by undo, by any path that nulls `lassoSelection` — we want the
  /// tool to fall back to whatever they were using before the barrel
  /// press (typically the pen), instead of leaving them stuck in lasso.
  ///
  /// The guard `_activeNativeBarrel == null` ensures we only fire in
  /// the "post-release, selection visible" state: a barrel still held
  /// means the user is mid-gesture and the normal release path will
  /// own the restoration when they let go.
  // Manual provider subscriptions created in initState. listenManual does
  // NOT auto-dispose with the widget (unlike ref.listen in build), so we
  // hold the handles and close them in dispose() — otherwise each opened
  // notebook leaks three permanent listeners.
  ProviderSubscription<Object?>? _lassoClearedSub;
  ProviderSubscription<Object?>? _pendingImportSub;
  ProviderSubscription<Object?>? _autoSaveSub;

  void _watchForLassoCleared() {
    _lassoClearedSub = ref.listenManual<LassoSelection?>(
      canvasProvider.select((s) => s?.lassoSelection),
      (prev, next) {
        if (prev == null || next != null) return;
        // The barrel-driven lasso intentionally stays active while a selection
        // is visible (see the barrel-up handlers). When the user finally
        // deselects, fall back to the tool they had before the barrel press.
        // Two independent barrel mechanisms: the native (Windows) bridge and
        // the event-buttons (Linux/desktop) override.
        if (_activeNativeBarrel == null && _nativeBarrelPreviousTool != null) {
          final tool = _nativeBarrelPreviousTool!;
          _nativeBarrelPreviousTool = null;
          ref.read(canvasProvider.notifier).setTool(tool);
        } else if (!_barrelButtonOverride && _barrelButtonPreviousTool != null) {
          final tool = _barrelButtonPreviousTool!;
          _barrelButtonPreviousTool = null;
          ref.read(canvasProvider.notifier).setTool(tool);
        }
      },
    );
  }

  /// Called by the WM_POINTER bridge while a side button is held and
  /// the pen tip is in contact (or had been on the most recent frame).
  /// Drives the lasso path directly because Gaomon driverless
  /// suppresses Flutter's PointerEvents for the duration of the
  /// barrel press — the canvas Listener never sees the gesture, so
  /// the regular onPointerDown/Move/Up flow can't update the path.
  ///
  /// [clientPos] is in Flutter logical pixels relative to the
  /// renderer's child window — same coordinate space Flutter treats
  /// as "global". We convert to canvas-local via `_canvasStackKey`'s
  /// RenderBox, then to page coords via `_toPageCoords`.
  void _onBarrelPen(String phase, Offset clientPos, double pressure) {
    if (!mounted) return;
    // Modern Flutter Windows embedders (3.4x) deliver the pen through the
    // normal pointer pipeline (kind=stylus, WM_POINTER) even while a side
    // button is held — the "Gaomon driverless suppresses PointerEvents"
    // behaviour this synthesis was written for no longer applies there.
    // When a real stylus pointer is down, the regular
    // _onPointerDown/Move/Up flow owns the gesture: letting the bridge
    // drive it in parallel double-feeds the lasso path with points from a
    // second coordinate transform and commits it early, so the stylus
    // PointerUp then found an empty path and wiped the fresh selection.
    // The bridge only drives when Flutter is receiving nothing.
    if (_stylusDown) return;
    final box = _canvasStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final localPos = box.globalToLocal(clientPos);
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final pagePos = _toPageCoords(localPos, state, _lastCanvasSize);

    final notif = ref.read(canvasProvider.notifier);
    final p = pressure > 0 ? pressure : 0.5;
    switch (phase) {
      case 'down':
        _bridgePenTool = state.currentTool;
        if (_bridgePenTool == CanvasTool.lasso) {
          notif.clearLassoPath();
          _lassoPathNotifier.start(pagePos);
        } else if (_bridgePenTool == CanvasTool.eraserStandard ||
            _bridgePenTool == CanvasTool.eraserStroke) {
          notif.startStroke(pagePos, p);
        }
        break;
      case 'move':
        if (_bridgePenTool == CanvasTool.lasso && _lassoPathNotifier.isActive) {
          _lassoPathNotifier.addPoint(pagePos);
        } else if (_bridgePenTool == CanvasTool.eraserStandard ||
            _bridgePenTool == CanvasTool.eraserStroke) {
          notif.continueStroke(pagePos, p);
        }
        break;
      case 'up':
        if (_bridgePenTool == CanvasTool.lasso && _lassoPathNotifier.isActive) {
          final pts = List<Offset>.from(_lassoPathNotifier.points);
          _lassoPathNotifier.clear();
          notif.commitLassoPath(pts);
        } else if (_bridgePenTool == CanvasTool.eraserStandard ||
            _bridgePenTool == CanvasTool.eraserStroke) {
          notif.endStroke();
        }
        _bridgePenTool = null;
        break;
    }
  }

  /// Waits for the notebook to finish loading, then runs any pending share
  /// import (files dropped in via the Android/iOS share sheet). Fires once.
  ///
  /// Listens to a narrow select (`s != null`) instead of the full state so
  /// the callback doesn't run 60×/s during pan/zoom.
  void _watchForPendingImport() {
    bool handled = false;
    _pendingImportSub = ref.listenManual<bool>(
      canvasProvider.select((s) => s != null),
      (_, hasState) {
        if (handled) return;
        if (!hasState) return;
        final pending = ref.read(pendingImportProvider);
        if (pending == null) return;
        handled = true;
        ref.read(pendingImportProvider.notifier).state = null;
        // Pin the notebook that satisfied the select: canvasProvider is a
        // single GLOBAL provider, so if the user navigates to a different
        // notebook before the post-frame callback runs, the import would
        // silently land in the wrong notebook.
        final targetNotebookId = ref.read(canvasProvider)?.metadata.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (ref.read(canvasProvider)?.metadata.id != targetNotebookId) {
            return;
          }
          _runPendingImport(pending);
        });
      },
    );
  }

  Future<void> _runPendingImport(PendingImport pending) async {
    if (!mounted) return;
    final notifier = ref.read(canvasProvider.notifier);
    if (pending.newChapterTitle != null && pending.newChapterTitle!.isNotEmpty) {
      notifier.addChapter(pending.newChapterTitle!);
    } else if (pending.targetChapterId != null) {
      notifier.setActiveChapter(pending.targetChapterId);
    }
    for (final path in pending.filePaths) {
      if (!mounted) break;
      try {
        final file = io.File(path);
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        final name = path.split(io.Platform.pathSeparator).last;
        final state = ref.read(canvasProvider);
        final pg = state?.currentPage;
        final center = pg == null
            ? const Offset(100, 100)
            : Offset(pg.width / 2, pg.height / 2);
        if (name.toLowerCase().endsWith('.pdf')) {
          await _insertPdf(bytes, name, center);
        } else {
          _insertImage(bytes, name, center);
          // For multiple shared images, give each its own page.
          if (pending.filePaths.length > 1 &&
              path != pending.filePaths.last) {
            notifier.addPage();
          }
        }
      } catch (e) {
        debugPrint('[Canvas] Pending import failed for $path: $e');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PenInputChannel.unregister();
    LinuxPenPressure.unregister();
    // Flush any pending deferred stylus commit before tearing down so a
    // partial stroke isn't lost on screen close. Cancel the timer first
    // since dispose is the terminal callsite. Notifier clear happens in
    // the dispose() call below regardless, so we just need to push the
    // points into provider state.
    _deferredCommitTimer?.cancel();
    _deferredCommitTimer = null;
    if (_deferredCommitPoints != null) {
      try {
        ref.read(canvasProvider.notifier).commitAndEndStroke(_deferredCommitPoints!);
      } catch (_) {
        // Provider may already be disposed; swallow.
      }
      _deferredCommitPoints = null;
      _deferredCommitAt = null;
      _deferredCommitLastScreenPos = null;
    }
    // Detach the probe BEFORE disposing the notifier it closes over —
    // an in-flight save polls it from the provider side.
    try {
      ref.read(canvasProvider.notifier).strokeActiveProbe = null;
    } catch (_) {}
    _activeStrokeNotifier.dispose();
    _lassoPathNotifier.dispose();
    _lassoTransformNotifier.dispose();
    _elementTransformNotifier.dispose();
    _laserStrokeNotifier.dispose();
    _autoSaveDebounce?.cancel();
    _autoSaveMaxWait?.cancel();
    _holdRecognizeTimer?.cancel();
    _longPressTimer?.cancel();
    // Close the manual provider subscriptions opened in initState.
    _lassoClearedSub?.close();
    _pendingImportSub?.close();
    _autoSaveSub?.close();
    _focusNode.dispose();
    _pdfTextSelController?.dispose();
    _mouseHoverCursor.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Deliberately NOT calling DesktopWindow.setFullScreen(false) here: by
    // the time dispose() runs the native GTK window may already be
    // mid-teardown (e.g. closing the app while presenting). The PopScope
    // handler exits presentation mode (and un-fullscreens) first, while the
    // window is still fully alive, so normal navigation never reaches this
    // dispose still fullscreen. If the whole app is quitting, GTK tears the
    // window down regardless of its fullscreen flag — nothing to fix here.
    super.dispose();
  }

  void _startAutoSave() {
    // Listen to canvas state: every transition into `isDirty=true` bumps the
    // debounce timer. This saves after [_autoSaveIdle] of inactivity, with a
    // cap of [_autoSaveMaxDelay] per burst.
    //
    // Subscribes to `isDirty` only — not the whole state — so the callback
    // doesn't get invoked 60×/s during pan/zoom (each panOffset state.copyWith
    // would otherwise fire the listener even though dirty was unchanged,
    // costing real CPU on a 215-page notebook just to cancel + recreate
    // Timers that nobody needed touched).
    _autoSaveSub = ref.listenManual<bool>(
      canvasProvider.select((s) => s?.isDirty ?? false),
      (_, isDirty) {
        if (!isDirty) {
          // Clean state; cancel any pending save.
          _wasDirty = false;
          _autoSaveDebounce?.cancel();
          _autoSaveMaxWait?.cancel();
          return;
        }
        // Dirty: restart idle timer, start max-wait on first dirty of burst.
        _autoSaveDebounce?.cancel();
        _autoSaveDebounce = Timer(_autoSaveIdle, _triggerAutoSave);
        if (!_wasDirty) {
          _autoSaveMaxWait?.cancel();
          _autoSaveMaxWait = Timer(_autoSaveMaxDelay, _triggerAutoSave);
        }
        _wasDirty = true;
      },
    );
  }

  void _triggerAutoSave() {
    final state = ref.read(canvasProvider);
    if (state == null || !state.isDirty || _isSaving) return;
    // Defer the save while a stroke is mid-flight OR an eraser drag is
    // in progress. _saveInner does enough sync work (state.copyWith,
    // setState in the canvas chrome) plus a 50 MB ZIP rebuild via
    // compute() to drop many frames — a >1.2 s eraser drag would
    // otherwise stall mid-gesture. eraserCursorPos is non-null only
    // between pointer-down and pointer-up on an eraser tool, so it's
    // the right signal. Save fires the moment the pen/eraser lifts,
    // when the next dirty transition re-arms the debounce.
    if (_activeStrokeNotifier.isActive || state.eraserCursorPos != null) {
      _autoSaveDebounce?.cancel();
      _autoSaveDebounce = Timer(const Duration(milliseconds: 600), _triggerAutoSave);
      return;
    }
    _save(silent: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` fires VERY frequently on desktop (every window focus change,
    // dock click, alt-tab). Treating it like a pause killed the pull timer
    // for the entire duration the user was looking at another window and
    // never restarted it — strokes from the iPad became invisible on PC
    // until the user re-opened the notebook. Only treat `paused` and
    // `detached` as real teardown triggers; flush nothing on `inactive`.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // App is being backgrounded / screen locked / process about to die.
      // Skip if we're already tearing down (via _onWillPop → closeNotebook)
      // to avoid two concurrent save paths fighting over the .ncnote.
      if (_closing) return;

      // Commit any stroke still inside the 50 ms pen-up defer window FIRST.
      // commitAndEndStroke mutates provider state synchronously, so after
      // this the stroke is in `state` and `isDirty` is true. Without it, a
      // stroke finished microseconds before the app was backgrounded never
      // reached state → isDirty was false → the save below skipped it and
      // the last stroke was lost on a screen-lock/app-switch right after
      // lifting the pen.
      _flushDeferredCommit();

      final canvas = ref.read(canvasProvider);
      if (canvas != null && canvas.isDirty && !_isSaving) {
        _save(silent: true);
      }

      // Flush any in-flight pull-save / remote-sync (and the save just
      // queued above) so pages downloaded by the pull timer — and the last
      // stroke — actually land on disk before the OS kills us. Without this,
      // closing right after a pull lost the downloaded pages ("chiudo riapro
      // e la sync ricomincia").
      unawaited(ref.read(canvasProvider.notifier).flushPendingWork());

      // Detached = Flutter engine is shutting down. Release GPU textures
      // NOW so the Linux desktop build doesn't segfault at exit while
      // native ui.Image handles are still in the imageCache.
      if (state == AppLifecycleState.detached) {
        try {
          ref.read(canvasProvider.notifier).releaseImageCache();
        } catch (_) {}
      }
      return;
    }

    // Resume: if we're back in the foreground and a notebook is open but
    // the pull timer got killed by a previous teardown, restart it so
    // cross-device updates arrive promptly again. Also wake up the
    // WebDAV client — iOS backgrounds stranded NSURLSession handles after
    // a screen lock or app-switch and subsequent calls return null even
    // though the network itself is healthy.
    if (state == AppLifecycleState.resumed) {
      if (_closing) return;
      try {
        ref.read(webdavServiceProvider)?.wakeUp();
      } catch (_) {}
      final canvas = ref.read(canvasProvider);
      if (canvas != null) {
        ref.read(canvasProvider.notifier).restartPullTimerIfNeeded();
      }
    }
  }

  Future<void> _save({bool silent = false}) async {
    if (_isSaving) {
      // Coalesce: let the caller await the already-running save so guards
      // like _onWillPop don't race ahead and prompt while a save is still
      // in flight.
      final inFlight = _saveInFlight;
      if (inFlight != null) await inFlight;
      return;
    }
    _isSaving = true;
    if (!silent && mounted) setState(() {});
    final completer = Completer<void>();
    _saveInFlight = completer.future;
    try {
      await ref.read(canvasProvider.notifier).save();
      // Only say 'Salvato!' if the save actually cleared the dirty flag.
      // If state.isDirty is still true, _saveInner aborted silently (most
      // often: pre-save guard #2 fired because document references pages
      // whose data isn't in memory — a pull is now healing that). Tell
      // the user the truth so they don't think their work was saved when
      // it's still pending.
      final stillDirty = ref.read(canvasProvider)?.isDirty ?? false;
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(stillDirty
                ? AppLocalizations.of(context).csSyncInProgress
                : AppLocalizations.of(context).csSaved),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).csErrorGeneric(e.toString()))));
      }
    } finally {
      _isSaving = false;
      _saveInFlight = null;
      completer.complete();
      if (!silent && mounted) setState(() {});
    }
  }

  // ── Keyboard shortcut handler ──

  /// True when the scratch page has content and none of it intersects the
  /// current viewport — the moment the "torna al contenuto" pill helps.
  bool _showBackToContent(CanvasState s) {
    if (!s.isScratch || s.zoom <= 0) return false;
    final notifier = ref.read(canvasProvider.notifier);
    final vp = notifier.viewportSize;
    if (vp == null) return false;
    final bbox = notifier.currentPageContentBounds();
    if (bbox == null) return false;
    // Scratch transform: screen = panOffset + P × zoom → invert the
    // viewport corners into page space.
    final visible = Rect.fromLTRB(
      -s.panOffset.dx / s.zoom,
      -s.panOffset.dy / s.zoom,
      (vp.width - s.panOffset.dx) / s.zoom,
      (vp.height - s.panOffset.dy) / s.zoom,
    );
    return !visible.overlaps(bbox.inflate(40));
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (ctrl) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.digit0:
        case LogicalKeyboardKey.numpad0:
          // Ctrl+0 = re-frame on content (scratch mode; no-op elsewhere).
          ref.read(canvasProvider.notifier).fitToContent();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyZ:
          if (shift) {
            ref.read(canvasProvider.notifier).redo();
          } else {
            ref.read(canvasProvider.notifier).undo();
          }
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyY:
          ref.read(canvasProvider.notifier).redo();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyS:
          _save();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyC:
          {
            final s = ref.read(canvasProvider);
            final notif = ref.read(canvasProvider.notifier);
            // Lasso selection takes priority; otherwise fall back to the
            // single-element selection (image / shape / text picked via
            // double-tap) so Ctrl+C copies an image too.
            if (s?.lassoSelection != null) {
              notif.copySelection();
              // Strokes/text can't go on the system clipboard — make sure a
              // later Ctrl+V uses THIS copy, not a stale leftover image.
              unawaited(_markSystemImageSeen());
            } else if (s?.selectedElementId != null) {
              final elId = s!.selectedElementId!;
              notif.copyElement(elId);
              // Mirror image bytes to the system clipboard so paste in
              // Word / browsers / other apps just works. Without this,
              // Ctrl+C only filled the in-app cross-notebook clipboard
              // and the user had to dig the floating menu's "Copia"
              // entry for a real system-clipboard image copy. For a
              // non-image element this is a no-op write; mark any stale
              // system image as seen so Ctrl+V prefers this copy.
              if (_selectedElementIsImage(s, elId)) {
                unawaited(_copyImageElementToSystemClipboard(elId));
              } else {
                unawaited(_markSystemImageSeen());
              }
            } else {
              return KeyEventResult.ignored;
            }
            _toast(AppLocalizations.of(context).csSelectionCopied);
            return KeyEventResult.handled;
          }
        case LogicalKeyboardKey.keyX:
          {
            final s = ref.read(canvasProvider);
            final notif = ref.read(canvasProvider.notifier);
            if (s?.lassoSelection != null) {
              notif.cutSelection();
            } else if (s?.selectedElementId != null) {
              notif.cutElement(s!.selectedElementId!);
            } else {
              return KeyEventResult.ignored;
            }
            _toast(AppLocalizations.of(context).csSelectionCut);
            return KeyEventResult.handled;
          }
        case LogicalKeyboardKey.keyV:
          _pasteFromClipboard();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyD:
          ref.read(canvasProvider.notifier).duplicateSelection();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyA:
          ref.read(canvasProvider.notifier).selectAll();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.digit0:
          ref.read(canvasProvider.notifier).resetZoom();
          return KeyEventResult.handled;
        default:
          break;
      }
    }

    // Arrow / PgUp / PgDn / Home / End — page navigation. Gated by a
    // few conditions so we don't hijack typing in inline text editors
    // or scroll-arrow gestures inside sheets.
    if (!ctrl) {
      final notifier = ref.read(canvasProvider.notifier);
      final s = ref.read(canvasProvider);
      // Don't steal arrows during text edit, lasso transform, pending
      // paste/symbol placement, or while a stroke is being drawn — those
      // workflows have their own arrow semantics.
      final guardActive = s == null ||
          s.pendingSymbol != null ||
          s.pendingPaste ||
          s.activeStroke.isNotEmpty;
      if (!guardActive) {
        final isLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.pageUp;
        final isRight = event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.pageDown;
        if (isLeft || isRight) {
          // Hold-to-accelerate: each event within 220 ms of the last
          // one is treated as a continued hold. After ~0.6 s we jump
          // 2 pages per tick, after ~1.3 s 3 pages, after ~2 s 5
          // pages. Reset on first press or after a 220 ms gap.
          final now = DateTime.now();
          final isContinuation = _lastArrowAt != null &&
              _lastArrowDir == (isLeft ? -1 : 1) &&
              now.difference(_lastArrowAt!).inMilliseconds < 220;
          if (!isContinuation) {
            _arrowHoldCount = 0;
          }
          _arrowHoldCount++;
          _lastArrowAt = now;
          _lastArrowDir = isLeft ? -1 : 1;
          // Slower ramp than the typical OS key-repeat (~30 Hz) so a
          // brief tap stays single-page even if the user happens to
          // hit two keys close together.
          final step = _arrowHoldCount < 6
              ? 1
              : _arrowHoldCount < 12
                  ? 2
                  : _arrowHoldCount < 20
                      ? 3
                      : 5;
          for (int i = 0; i < step; i++) {
            if (isLeft) {
              notifier.prevPage();
            } else {
              notifier.nextPage();
            }
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.home) {
          final filtered = s.filteredPageIndices;
          if (filtered.isNotEmpty) notifier.goToPage(filtered.first);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.end) {
          final filtered = s.filteredPageIndices;
          if (filtered.isNotEmpty) notifier.goToPage(filtered.last);
          return KeyEventResult.handled;
        }
      }
    }

    // Delete / Backspace
    if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
      final state = ref.read(canvasProvider);
      if (state?.selectedElementId != null) {
        ref.read(canvasProvider.notifier).deleteElement(state!.selectedElementId!);
        return KeyEventResult.handled;
      }
      if (state?.lassoSelection != null) {
        ref.read(canvasProvider.notifier).deleteSelection();
        return KeyEventResult.handled;
      }
    }

    // Escape — exit presentation mode first (it owns the whole screen while
    // active), otherwise fall through to the normal deselect/cancel below.
    if (event.logicalKey == LogicalKeyboardKey.escape && _presentationMode) {
      _exitPresentationMode();
      return KeyEventResult.handled;
    }

    // Escape — deselect / cancel pending symbol / cancel pending paste
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final state = ref.read(canvasProvider);
      if (state?.pendingSymbol != null) {
        ref.read(canvasProvider.notifier).clearPendingSymbol();
        return KeyEventResult.handled;
      }
      if (state?.pendingPaste == true) {
        ref.read(canvasProvider.notifier).cancelPendingPaste();
        return KeyEventResult.handled;
      }
      ref.read(canvasProvider.notifier).clearSelection();
      ref.read(canvasProvider.notifier).deselectElement();
      return KeyEventResult.handled;
    }

    // P — pen tool
    if (event.logicalKey == LogicalKeyboardKey.keyP && !ctrl) {
      _pickTool(CanvasTool.pen);
      return KeyEventResult.handled;
    }
    // E — eraser (restores last picked sub-mode: per-stroke or per-area)
    if (event.logicalKey == LogicalKeyboardKey.keyE && !ctrl) {
      _pickTool(ref.read(canvasProvider.notifier).lastEraserMode);
      return KeyEventResult.handled;
    }
    // L — lasso select
    if (event.logicalKey == LogicalKeyboardKey.keyL && !ctrl) {
      _pickTool(CanvasTool.lasso);
      return KeyEventResult.handled;
    }
    // H — hand/pan tool
    if (event.logicalKey == LogicalKeyboardKey.keyH && !ctrl) {
      _pickTool(CanvasTool.pan);
      return KeyEventResult.handled;
    }
    // T — text tool
    if (event.logicalKey == LogicalKeyboardKey.keyT && !ctrl) {
      _pickTool(CanvasTool.text);
      return KeyEventResult.handled;
    }
    // B — brush tool
    if (event.logicalKey == LogicalKeyboardKey.keyB && !ctrl) {
      _pickTool(CanvasTool.brush);
      return KeyEventResult.handled;
    }

    // ? (Shift+/) — open keyboard shortcut cheat sheet. Power users on
    // desktop/iPad with keyboard have no other way to discover the
    // Ctrl+C/X/V/D/A/0, P/E/L/H/T/B/S single-key shortcuts — they were
    // only visible to someone reading the source code.
    if (shift && event.logicalKey == LogicalKeyboardKey.question) {
      _showShortcutHelp();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.slash && shift) {
      _showShortcutHelp();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _showShortcutHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.keyboard_rounded, size: 20),
              const SizedBox(width: 8),
              Text(l10n.csShortcutsTitle),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ShortcutGroup(l10n.csShortcutGroupGeneral, [
                    ('Ctrl+S', l10n.csSaveNow),
                    ('Ctrl+Z', l10n.csShortcutUndo),
                    ('Ctrl+Shift+Z / Ctrl+Y', l10n.csShortcutRedo),
                    ('Ctrl+A', l10n.csSelectAll),
                    ('Ctrl+0', l10n.csShortcutResetZoom),
                    ('Esc', l10n.csShortcutDeselect),
                    ('?', l10n.csShortcutThisGuide),
                  ]),
                  const SizedBox(height: 12),
                  _ShortcutGroup(l10n.csShortcutGroupClipboard, [
                    ('Ctrl+C', l10n.csShortcutCopySelection),
                    ('Ctrl+X', l10n.csShortcutCutSelection),
                    ('Ctrl+V', l10n.csPaste),
                    ('Ctrl+D', l10n.csShortcutDuplicateSelection),
                    (l10n.csShortcutKeyDeleteBackspace, l10n.csShortcutDeleteElementOrSelection),
                  ]),
                  const SizedBox(height: 12),
                  _ShortcutGroup(l10n.csShortcutGroupTools, [
                    ('P', l10n.csToolPen),
                    ('B', l10n.csToolBrush),
                    ('E', l10n.csToolEraser),
                    ('L', l10n.csToolLasso),
                    ('H', l10n.csToolHand),
                    ('T', l10n.csToolText),
                    ('S', l10n.csToolShape),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.csClose),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _onWillPop() async {
    // Mark closing so didChangeAppLifecycleState doesn't fire a parallel
    // save if the OS backgrounds the app during the pop dialog.
    _closing = true;
    // If a save is in flight, wait for it to finish before deciding whether
    // to prompt. Otherwise the user just pressed "Save" and sees a
    // "save before leaving?" dialog for the same changes that are already
    // being persisted.
    if (_isSaving) {
      final inFlight = _saveInFlight;
      if (inFlight != null) await inFlight;
    }
    if (!mounted) return false;
    final state = ref.read(canvasProvider);
    if (state != null && state.isDirty) {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(ctx).csUnsavedChangesTitle),
          content: Text(AppLocalizations.of(ctx).csUnsavedChangesBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text(AppLocalizations.of(ctx).csDiscard)),
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: Text(AppLocalizations.of(ctx).csCancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(AppLocalizations.of(ctx).csSave)),
          ],
        ),
      );
      if (result == 'cancel') {
        // User backed out — re-enable lifecycle autosave.
        _closing = false;
        return false;
      }
      if (result == 'save') await _save();
    }
    // Fast-close flow:
    //
    //  1) Kick off flushPendingWork() in the background — it drains
    //     pending pulls + pulled-saves + remote-syncs so the SQLite row
    //     reflects the final state.  We do NOT await it before popping
    //     because on a slow network the flush can take seconds and the
    //     user should not be held hostage to a spinner when pressing
    //     back.
    //  2) Hand the flush Future to the route as the pop result.  The
    //     library's `.then()` callback awaits it before refreshing so
    //     the library card still shows the up-to-date pageCount the
    //     moment the flush lands (no stale "1 pagina" card).
    //  3) Fire closeNotebook() unawaited — it internally awaits
    //     flushPendingWork (idempotent) and then tears down state.
    final notifier = ref.read(canvasProvider.notifier);
    final flushFuture = notifier.flushPendingWork();
    if (mounted) Navigator.of(context).pop<Future<void>>(flushFuture);
    unawaited(notifier.closeNotebook());
    return false; // already popped above — don't pop again
  }

  // ── Drag-left/right page navigation ──

  /// [panOverride] lets the caller pass the post-update pan without
  /// allocating a `state.copyWith(panOffset: ...)` per pointer-move
  /// just to read it back. CanvasState's copyWith touches every field
  /// (215 PageData refs, lists, etc.) which is real GC pressure at the
  /// 60–120 Hz pan rate.
  void _checkPageDrag(CanvasState state, Size canvasSize,
      {Offset? panOverride}) {
    // Scratch is a single infinite canvas — no page-to-page swipe.
    if (state.isScratch) return;
    final pageW = state.currentPage?.width ?? 595;
    final pageH = state.currentPage?.height ?? 842;
    final renderScale = min(canvasSize.width / pageW, canvasSize.height / pageH);
    final scaledW = pageW * renderScale;
    final centerOffsetX = (canvasSize.width - scaledW) / 2;

    final pan = panOverride ?? state.panOffset;
    // Right edge of the page in screen coords
    final pageRightScreen = (scaledW * state.zoom) + pan.dx + (centerOffsetX * state.zoom);
    // Left edge of the page in screen coords
    final pageLeftScreen = pan.dx + (centerOffsetX * state.zoom);

    final filtered = state.filteredPageIndices;
    final pos = filtered.indexOf(state.currentPageIndex);
    final hasNext = pos >= 0 && pos + 1 < filtered.length;
    final hasPrev = pos > 0;
    final isLastPage = pos >= 0 && pos == filtered.length - 1;

    // ─ Swipe LEFT: show next page or new page preview ─
    if (pageRightScreen < canvasSize.width * 0.68) {
      if (_showPrevPageHint) setState(() => _showPrevPageHint = false);
      if (isLastPage) {
        if (!_showNewPageHint) setState(() { _showNewPageHint = true; _showNextPageHint = false; });
      } else if (hasNext) {
        if (!_showNextPageHint) setState(() { _showNextPageHint = true; _showNewPageHint = false; });
      }
    }
    // ─ Swipe RIGHT: show previous page preview ─
    else if (pageLeftScreen > canvasSize.width * 0.32 && hasPrev) {
      if (!_showPrevPageHint) setState(() { _showPrevPageHint = true; _showNewPageHint = false; _showNextPageHint = false; });
    } else {
      _clearPageHints();
    }
  }

  /// Commit page navigation on pointer-up if page edge is past the commit
  /// threshold (50% of screen), otherwise just dismiss the preview.
  void _commitOrCancelPageDrag(CanvasState state, Size canvasSize) {
    if (state.isScratch) return;
    final pageW = state.currentPage?.width ?? 595;
    final pageH = state.currentPage?.height ?? 842;
    final renderScale = min(canvasSize.width / pageW, canvasSize.height / pageH);
    final scaledW = pageW * renderScale;
    final centerOffsetX = (canvasSize.width - scaledW) / 2;

    final pageRightScreen = (scaledW * state.zoom) + state.panOffset.dx + (centerOffsetX * state.zoom);
    final pageLeftScreen = state.panOffset.dx + (centerOffsetX * state.zoom);

    final filtered = state.filteredPageIndices;
    final pos = filtered.indexOf(state.currentPageIndex);
    final hasNext = pos >= 0 && pos + 1 < filtered.length;
    final hasPrev = pos > 0;
    final isLastPage = pos >= 0 && pos == filtered.length - 1;

    // Commit threshold: page edge must be past 50% of screen
    if (pageRightScreen < canvasSize.width * 0.50) {
      if (isLastPage) {
        HapticFeedback.mediumImpact();
        ref.read(canvasProvider.notifier).addPage();
      } else if (hasNext) {
        // Swipe commit: reset zoom/pan so the next page opens centered.
        HapticFeedback.selectionClick();
        ref.read(canvasProvider.notifier).nextPage(resetViewport: true);
      }
    } else if (pageLeftScreen > canvasSize.width * 0.50 && hasPrev) {
      // Swipe commit: reset zoom/pan so the prev page opens centered.
      HapticFeedback.selectionClick();
      ref.read(canvasProvider.notifier).prevPage(resetViewport: true);
    }

    _clearPageHints();
  }

  void _clearPageHints() {
    if (_showNewPageHint || _showPrevPageHint || _showNextPageHint) {
      setState(() {
        _showNewPageHint = false;
        _showPrevPageHint = false;
        _showNextPageHint = false;
      });
    }
  }

  void _startLongPressTimer(Offset globalPos, Offset localPos, CanvasState state, Size canvasSize) {
    _cancelLongPressTimer();
    // Never show context menu while stylus is actively touching the screen
    // (the touch event is almost certainly a palm).
    if (_stylusDown) return;
    // Bumped from 3 s → 8 s. A user pausing mid-sentence often rests the
    // palm for several seconds before writing again; the old window let
    // the context menu pop up unexpectedly during that pause. 8 s is
    // close to a 'really not writing anymore' threshold without being
    // annoying for legitimate context-menu requests.
    if (DateTime.now().difference(_lastStrokeActivity).inMilliseconds < 8000) return;
    // Require the touch to be the ONLY active pointer at start. Palm-rest
    // during writing typically registers as a touch alongside the stylus,
    // bringing _activePointers to 2; rejecting now avoids opening the
    // menu on the iPad while the user is mid-stroke.
    if (_activePointers > 1) return;
    _longPressGlobalPos = globalPos;
    _longPressFired = false;
    _longPressTimer = Timer(const Duration(milliseconds: 600), () {
      _longPressTimer = null;
      // Recheck guards at fire time — a palm could have landed during
      // the 600 ms wait. Don't open the menu if any of those triggered.
      if (_stylusDown) return;
      if (_activePointers != 1) return;
      if (DateTime.now().difference(_lastStrokeActivity).inMilliseconds < 8000) return;
      _longPressFired = true;
      final latestState = ref.read(canvasProvider);
      if (latestState != null) {
        _showContextMenu(globalPos, localPos, latestState, canvasSize);
      }
    });
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  // ── Coordinate conversion ──

  Offset _toPageCoords(Offset localPos, CanvasState state, Size canvasSize) {
    final renderScale = _getRenderScale(state, canvasSize);
    final center = _getCenterOffset(state, canvasSize);
    final unPanned = localPos - state.panOffset - center * state.zoom;
    final unZoomed = unPanned / state.zoom;
    return unZoomed / renderScale;
  }

  Offset _toScreenCoords(Offset pagePos, CanvasState state, Size canvasSize) {
    final renderScale = _getRenderScale(state, canvasSize);
    final center = _getCenterOffset(state, canvasSize);
    final scaled = pagePos * renderScale;
    return scaled * state.zoom + state.panOffset + center * state.zoom;
  }

  /// Returns true if this tap is a double-tap (close in position and time to the last tap).
  bool _isDoubleTap(Offset position) {
    final now = DateTime.now();
    final elapsed = now.difference(_lastTapTime).inMilliseconds;
    final dist = (position - _lastTapPos).distance;
    _lastTapTime = now;
    _lastTapPos = position;
    return elapsed < 400 && dist < 30;
  }

  /// True when [pts] cover a negligible area — a click with no real drag.
  /// Used to drop accidental "dots" produced by plain-mouse clicks (see
  /// the suppression in [_onPointerUp]).
  bool _isDotStroke(List<StrokePoint> pts) {
    if (pts.length <= 1) return true;
    double minX = pts.first.x, maxX = pts.first.x;
    double minY = pts.first.y, maxY = pts.first.y;
    for (final p in pts) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    return (maxX - minX) < 1.5 && (maxY - minY) < 1.5;
  }

  /// Matches http(s):// URLs and bare www. links inside text content.
  static final RegExp _urlPattern = RegExp(
    r'((https?://)|(www\.))[^\s]+',
    caseSensitive: false,
  );

  /// First URL found in [text], normalised to include a scheme, or null.
  String? _firstUrl(String text) {
    final m = _urlPattern.firstMatch(text);
    if (m == null) return null;
    var url = m.group(0)!;
    // Trim trailing punctuation that's usually NOT part of the link.
    url = url.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');
    if (url.isEmpty) return null;
    if (!url.toLowerCase().startsWith('http')) url = 'https://$url';
    return url;
  }

  /// If a text element under [pagePos] contains a URL, open it and return
  /// true. Topmost element wins (reverse z-order, matching hit-testing).
  bool _tryOpenLinkAt(CanvasState state, Offset pagePos) {
    final page = state.currentPage;
    if (page == null) return false;
    for (int i = page.layers.content.length - 1; i >= 0; i--) {
      String? url;
      page.layers.content[i].maybeMap(
        text: (t) {
          final b = Rect.fromLTWH(
              t.data.x, t.data.y, t.data.width, t.data.height);
          if (b.inflate(5).contains(pagePos)) {
            url = _firstUrl(t.data.content);
          }
        },
        orElse: () {},
      );
      if (url != null) {
        _openUrl(url!);
        return true;
      }
    }
    return false;
  }

  /// Open [url] with the platform's default handler. Uses the OS opener
  /// directly (no extra plugin dependency); this is a desktop-only path,
  /// which is fine because Ctrl+click is a desktop interaction.
  Future<void> _openUrl(String url) async {
    try {
      if (io.Platform.isLinux) {
        await io.Process.start('xdg-open', [url]);
      } else if (io.Platform.isMacOS) {
        await io.Process.start('open', [url]);
      } else if (io.Platform.isWindows) {
        await io.Process.start('cmd', ['/c', 'start', '', url]);
      } else {
        return;
      }
      _toast(AppLocalizations.of(context).csOpeningLink);
    } catch (e) {
      CrashLogger.append('[Link] failed to open $url: $e');
      _toast(AppLocalizations.of(context).csCannotOpenLink);
    }
  }

  double _getRenderScale(CanvasState state, Size canvasSize) {
    // Scratch (infinite canvas): fixed 1:1 so a pen stroke stays natural
    // size and the user roams via free pan/zoom — no fit-to-page shrink.
    if (state.isScratch) return 1.0;
    final pageW = state.currentPage?.width ?? 595;
    final pageH = state.currentPage?.height ?? 842;
    return min(canvasSize.width / pageW, canvasSize.height / pageH);
  }

  /// Offset that centres the fitted page inside the viewport. Zero for
  /// scratch mode (the big page isn't fit-centred; panOffset positions it).
  /// MUST stay in lock-step with [CanvasRenderEngine.paint]'s centerOffset.
  Offset _getCenterOffset(CanvasState state, Size canvasSize) {
    if (state.isScratch) return Offset.zero;
    final pageW = state.currentPage?.width ?? 595;
    final pageH = state.currentPage?.height ?? 842;
    final rs = min(canvasSize.width / pageW, canvasSize.height / pageH);
    return Offset(
      (canvasSize.width - pageW * rs) / 2,
      (canvasSize.height - pageH * rs) / 2,
    );
  }

  // ── Pointer handling ──

  bool _isDrawLikeTool(CanvasTool tool) {
    return tool == CanvasTool.pen ||
        tool == CanvasTool.ballpoint ||
        tool == CanvasTool.brush ||
        tool == CanvasTool.calligraphy ||
        tool == CanvasTool.highlighter ||
        tool == CanvasTool.eraserStandard ||
        tool == CanvasTool.eraserStroke ||
        tool == CanvasTool.lasso ||
        tool == CanvasTool.shape ||
        tool == CanvasTool.laser;
  }

  /// True on a touch-primary platform (no mouse to speak of) — gates
  /// whether the top bar shows the mouse-mode toggle or the touch-mode one,
  /// and is the platform-default fallback for [_effectiveStylusOnly].
  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Whether touch should be treated as pan-only (true) or as a drawing
  /// device on par with the stylus (false). Follows the user's explicit
  /// Settings → Stylus & Input override when set, else the platform
  /// default (on for Android/iOS, off for desktop/web).
  bool _effectiveStylusOnly() {
    final override = ref.read(appSettingsProvider).stylusOnlyDrawing;
    return override ?? _isMobilePlatform;
  }

  bool _shouldTouchPan(PointerDeviceKind kind, CanvasTool tool) {
    return _effectiveStylusOnly() && kind == PointerDeviceKind.touch && _isDrawLikeTool(tool);
  }

  void _onPointerDown(PointerDownEvent event, CanvasState state, Size canvasSize) {
    // Gaomon driverless: barrel-held + tip-contact arrives as a
    // synth mouse event in parallel with the suppressed pen stream.
    // For the lower barrel it's WM_MBUTTONDOWN (kind=mouse,
    // buttons=0x4 = middle); for the upper barrel it's
    // WM_LBUTTONDOWN (kind=mouse, buttons=0x1 = left). Either way
    // the C++ bridge has already switched tool and is driving the
    // gesture via `_onBarrelPen` — we don't want the synth click
    // ALSO landing in the regular pointer flow (would start a
    // phantom stroke / pan at the cursor location). Drop any
    // non-zero-button mouse DOWN while a barrel override is active.
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != 0 &&
        _activeNativeBarrel != null) {
      _suppressedSynthBarrelPointers.add(event.pointer);
      return;
    }
    _activePointers++;
    _lastPointerWasMouse = event.kind == PointerDeviceKind.mouse;

    // A pen/touch interaction reverts the cursor to the tool default (so a
    // stale mouse-selection arrow doesn't linger while drawing with the pen).
    if (event.kind != PointerDeviceKind.mouse &&
        _mouseHoverCursor.value != null) {
      _mouseHoverCursor.value = null;
    }

    // ── Mouse LEFT button = pure SELECTION device (it never draws) ──
    // While a drawing tool is active, a left-click selects instead of drawing:
    //   1. over PDF text   → text selection (drag to extend);
    //   2. over an element → select it (single click skips the locked PDF page;
    //      a DOUBLE-click grabs even the locked page/image);
    //   3. empty space     → marquee (drag) / deselect (click).
    // Only the LEFT button: the middle button still pans (handled below) and
    // the right button still opens the context menu. The pen/touch keep drawing.
    //
    // The literal lasso tool always qualifies, independent of `mouseDraws`:
    // that flag only redirects an INK tool into acting as a selector, and
    // code paths that set `currentTool` directly (e.g. PDF import lands on
    // CanvasTool.lasso via addImageElement) don't go through _pickTool, so
    // mouseDraws can be stale-true while the tool is already lasso. Without
    // this, the PDF-text hit-test below was unreachable right after import
    // — the single moment a user is most likely to try selecting text —
    // and a click there fell through to the plain marquee-only lasso path
    // further down, which never checks for PDF text at all.
    // Pending paste placement via mouse LEFT click. Must run BEFORE the
    // selection/marquee block below: that block returns for every left click
    // on a drawing/lasso tool, so it swallowed the click and the touch/pen
    // tap-to-place check further down was never reached on desktop — the
    // "tap to place the copy" banner did nothing when clicked with a mouse.
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton &&
        state.pendingPaste &&
        state.clipboard != null) {
      final pagePos = _toPageCoords(event.localPosition, state, canvasSize);
      final n = ref.read(canvasProvider.notifier);
      n.paste(at: pagePos);
      n.cancelPendingPaste();
      return;
    }

    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton &&
        (state.currentTool == CanvasTool.lasso ||
            (!ref.read(appSettingsProvider).mouseDraws &&
                _mouseSelectTools.contains(state.currentTool)))) {
      final pagePos = _toPageCoords(event.localPosition, state, canvasSize);
      final notif = ref.read(canvasProvider.notifier);
      final isDouble = _isDoubleTap(event.localPosition);

      // 1. PDF text under the cursor → text selection.
      final sel = _ensurePdfTextSel(state);
      if (sel != null && !sel.isEmpty && sel.isOverText(pagePos)) {
        _pdfTextDragActive = true;
        sel.begin(pagePos);
        return;
      }
      sel?.clear();

      // 1b. Press INSIDE an existing marquee/lasso selection → drag it.
      // Without this the fall-through below treats the press as "empty
      // space", clears the selection and starts a new marquee — making a
      // mouse-made selection impossible to move.
      if (state.lassoSelection != null) {
        final lassoSel = state.lassoSelection!;
        final bounds = lassoSel.bounds
            .translate(lassoSel.dragOffset.dx, lassoSel.dragOffset.dy);
        if (bounds.inflate(10).contains(pagePos)) {
          _isDraggingSelection = true;
          _lastLassoDragPos = pagePos;
          // Snapshot the current Riverpod transform so drag deltas
          // accumulate locally (same contract as the lasso-tool branch).
          _lassoTransformNotifier.begin(
            dragOffset: lassoSel.dragOffset,
            rotation: lassoSel.rotation,
            scale: lassoSel.scale,
          );
          return;
        }
      }

      // 2. An element under the cursor → select it. Single click skips the
      //    locked PDF raster (so you can annotate/marquee over the page);
      //    a double click includes it (to grab the whole page/image).
      final elId = _findElementAt(state, pagePos, skipLocked: !isDouble);
      if (elId != null) {
        // Double-click a text element → open the rich text editor (the topmost
        // text under the cursor must be the hit element, i.e. not behind an
        // image). Single click still just selects it.
        if (isDouble) {
          final txt = _findTextElementAt(state, pagePos);
          if (txt != null && txt.id == elId) {
            _handleTextTool(event.localPosition, state, canvasSize);
            return;
          }
        }
        notif.selectElement(elId);
        return;
      }

      // 3. Empty space → start a marquee (drives the lasso path directly; its
      //    preview renders without switching the dock tool). A click with no
      //    drag commits an empty polygon ⇒ deselect.
      if (state.selectedElementId != null) notif.deselectElement();
      if (state.lassoSelection != null) notif.clearSelection();
      notif.clearLassoPath();
      _lassoPathNotifier.start(pagePos);
      _mouseSelecting = true;
      return;
    }

    // Track stylus presence so we can suppress palm-triggered long-press
    if (event.kind == PointerDeviceKind.stylus || event.kind == PointerDeviceKind.invertedStylus) {
      // Debug: log every stylus-down with the gap from the previous stroke
      // end. A short gap (<200 ms) right after a non-UP end (cancel / commit
      // mid-stroke) is the smoking gun for a "stroke break".
      final now = DateTime.now();
      final gapMs = _strokeEndedAt == null
          ? -1
          : now.difference(_strokeEndedAt!).inMilliseconds;
      final isBreakSusp = gapMs >= 0 && gapMs < 200 && _lastStrokeEndReason != 'pointerUp.commit';
      // Distance from the previous deferred-commit position, if any. Logs
      // even when no continuation happens — helps tune _deferStylusPx if
      // a break sneaks past the threshold.
      String distStr = '';
      if (_deferredCommitLastScreenPos != null) {
        final d = (event.position - _deferredCommitLastScreenPos!).distance;
        distStr = ' deferDist=${d.toStringAsFixed(1)}px';
      }
      _strokeDbg(
        'DOWN stylus p=${event.pointer} t=${event.timeStamp.inMilliseconds}ms '
        'gap=${gapMs}ms prevEnd=$_lastStrokeEndReason '
        'tool=${state.currentTool.name} '
        'active=${_activeStrokeNotifier.isActive} '
        'activePointers=$_activePointers$distStr'
        '${isBreakSusp ? " BREAK_SUSPECTED" : ""}',
      );

      // ── Continuation check (iPad spurious Up→Down) ──
      //
      // If we just deferred a commit, see if this DOWN is close enough in
      // time and space to be the resumption of the same stroke. If so,
      // cancel the deferred commit and skip the rest of the DOWN handling
      // — the notifier is already active with the buffered points (we
      // intentionally never cleared it on PointerUp), so the next move
      // event simply appends to the existing live stroke. Without this
      // iPad / Apple Pencil produces visible mid-letter breaks because
      // the OS occasionally emits a spurious UP+DOWN pair (sample
      // dropout / pressure threshold / pointer rebatching).
      final deferredPts = _deferredCommitPoints;
      if (deferredPts != null && _deferredCommitAt != null && _deferredCommitLastScreenPos != null) {
        final defGapMs = now.difference(_deferredCommitAt!).inMilliseconds;
        final defDist = (event.position - _deferredCommitLastScreenPos!).distance;
        if (defGapMs < _deferStylusMs && defDist < _deferStylusPx) {
          _deferredCommitTimer?.cancel();
          _deferredCommitTimer = null;
          _deferredCommitPoints = null;
          _deferredCommitAt = null;
          _deferredCommitLastScreenPos = null;
          _justContinuedFromDefer = true;
          _strokeDbg(
            'CONTINUATION p=${event.pointer} '
            'gap=${defGapMs}ms dist=${defDist.toStringAsFixed(1)}px '
            'liveStrokePts=${_activeStrokeNotifier.points.length}',
          );
          _stylusDown = true;
          _cancelLongPressTimer();
          return;
        }
        // Out of range → flush the pending commit before starting a new one
        _flushDeferredCommit();
      }

      _stylusDown = true;
      _cancelLongPressTimer(); // kill any pending palm long-press immediately
    }

    if (_activePointers >= 2) {
      // Palm rejection: if a stylus is already drawing and the incoming
      // second pointer is a touch (the user's wrist landing on the screen
      // while writing), DO NOT treat this as a pinch-to-zoom. Previously
      // we cancelled the active stroke here the moment the palm touched
      // down, which wiped the first few strokes the user had just drawn.
      // Instead, ignore the palm touch entirely — the Listener keeps
      // feeding stylus moves to _onPointerMove, and the scale handlers
      // below also early-return while _stylusDown is true.
      if (_stylusDown && event.kind == PointerDeviceKind.touch) {
        // Un-count the palm: leaving it in _activePointers blocks every
        // subsequent stylus move (>= 2 guard in _onPointerMove) and
        // suppresses the pen-up commit. Its own UP/CANCEL is skipped via
        // _ignoredPalmPointers so the counter stays balanced.
        _activePointers = max(0, _activePointers - 1);
        _ignoredPalmPointers.add(event.pointer);
        _cancelLongPressTimer();
        return;
      }
      // True multi-touch (two fingers, no stylus): pinch-to-zoom gesture.
      if (_activeStrokeNotifier.isActive) {
        _activeStrokeNotifier.clear();
        ref.read(canvasProvider.notifier).cancelStroke();
      }
      _isTouchPanning = false;
      _cancelLongPressTimer();
      return;
    }

    // Ctrl/Cmd + click on a text element that contains a URL → open the
    // link in the system browser instead of drawing. Mouse-only (Ctrl+click
    // is a desktop interaction); the tip-down keeps drawing as normal.
    if (event.kind == PointerDeviceKind.mouse &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      final linkPos = _toPageCoords(event.localPosition, state, canvasSize);
      if (_tryOpenLinkAt(state, linkPos)) return;
    }

    final tool = state.currentTool;

    // Middle mouse button → always pan, EXCEPT when a native barrel
    // override is active. Reason: a Gaomon driverless pen reports
    // "barrel held + tip in contact" as a synthesised middle-mouse
    // click. Without the guard, the existing middle-mouse-pan branch
    // swallows the pen tip touch before the lasso/eraser branch
    // could pick it up — the toolbar already shows lasso (the C++
    // bridge switched it on the barrel press) but the tap goes
    // into pan mode and the lasso never starts.
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons == kMiddleMouseButton &&
        _activeNativeBarrel == null) {
      _isTouchPanning = true;
      _lastFocalPoint = event.position;
      return;
    }

    // Stylus barrel buttons — OneNote-style temporary tool override.
    //
    // Driver landscape:
    //   - Wacom EMR / Surface / Galaxy: bits 0x02 / 0x04 on the
    //     standard buttons mask (`kPrimaryStylusButton`,
    //     `kSecondaryStylusButton`).
    //   - Gaomon (and most off-brand Huion-derived drivers) on
    //     Windows: the UPPER side button switches the pointer kind
    //     to `PointerDeviceKind.invertedStylus` (the same signal a
    //     pen's flip-eraser end emits). The LOWER button is exposed
    //     by their driver as a configurable shortcut — by default
    //     "Right click" — which Flutter still routes to a stylus
    //     PointerDown with bit 0x02 set.
    //   - Apple Pencil 2: no buttons, only double-tap (ignored
    //     here; covered separately).
    //
    // We accept BOTH paths: invertedStylus kind for the upper
    // override, and the bit-mask test for the lower. Bitmask (not
    // strict equality) is required because contact + barrel report
    // the OR — `0x03` or `0x05` — never the raw barrel bit alone.
    //
    //   - upper barrel (or invertedStylus kind) → eraser
    //   - lower barrel (`kPrimaryStylusButton` bit) → lasso
    //
    // Pending modal states (pendingSymbol / selectedElement /
    // lassoSelection) get "escape first" — either path cancels the
    // modal instead of switching tool.
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      final invertedKind = event.kind == PointerDeviceKind.invertedStylus;
      final hasUpper =
          invertedKind || (event.buttons & kSecondaryStylusButton) != 0;
      final hasLower = !invertedKind &&
          (event.buttons & kPrimaryStylusButton) != 0;
      if (hasUpper || hasLower) {
        // Escape pending modal states first (any button).
        if (state.pendingSymbol != null) {
          ref.read(canvasProvider.notifier).clearPendingSymbol();
          return;
        }
        if (state.selectedElementId != null) {
          ref.read(canvasProvider.notifier).deselectElement();
          return;
        }
        if (state.lassoSelection != null) {
          ref.read(canvasProvider.notifier).clearSelection();
          return;
        }

        final pagePos = _toPageCoords(event.localPosition, state, canvasSize);
        _barrelButtonOverride = true;
        _barrelButtonPreviousTool = state.currentTool;

        if (hasUpper) {
          // Upper barrel → eraser. Honour the user's last picked
          // sub-mode (per-stroke vs per-area) so the barrel feels
          // like the eraser dock button.
          final n = ref.read(canvasProvider.notifier);
          n.setTool(n.lastEraserMode);
          n.startStroke(pagePos, 0.5);
        } else {
          // Lower barrel → lasso. Switch tool and open the polygon
          // at the contact point; the normal pointer-move branch
          // will feed it.
          ref.read(canvasProvider.notifier).setTool(CanvasTool.lasso);
          _lassoPathNotifier.start(pagePos);
        }
        return;
      }
    }

    final pagePos =
        _toPageCoords(_stylusLocalPosition(event), state, canvasSize);
    final normPressure = _normalizedEventPressure(event);
    final pressure = normPressure > 0 ? normPressure : 0.5;

    // Touch pan: only if no selected image is under the finger
    if (_shouldTouchPan(event.kind, tool)) {
      // If there's a selected element and we're touching it, let the overlay handle it
      if (state.selectedElementId != null) {
        final selBounds = _getSelectedElementBounds(state);
        // Expand bounds to include the action bar and handles above the element.
        // The action bar sits ~92px above in screen coords; convert to page coords.
        final scale = state.zoom * _getRenderScale(state, canvasSize);
        final topPadding = 100.0 / scale; // action bar + rotation handle
        final sidePadding = 20.0 / scale; // resize handles
        final extendedBounds = selBounds == null ? null : Rect.fromLTRB(
          selBounds.left - sidePadding,
          selBounds.top - topPadding,
          selBounds.right + sidePadding,
          selBounds.bottom + sidePadding,
        );
        if (extendedBounds != null && extendedBounds.contains(pagePos)) {
          // Fall through to selected element handling below
        } else {
          // Double-tap on an image to select it (single tap just pans)
          if (_isDoubleTap(event.localPosition)) {
            final tappedImage = _findImageOrShapeAt(state, pagePos);
            if (tappedImage != null) {
              ref.read(canvasProvider.notifier).selectElement(tappedImage);
              return;
            }
          }
          // Tapped away from selection and no other image → deselect
          ref.read(canvasProvider.notifier).deselectElement();
          _isTouchPanning = true;
          _lastFocalPoint = event.position;
          // Don't show context menu if stylus is actively drawing (palm rest)
          if (!_activeStrokeNotifier.isActive) {
            _startLongPressTimer(event.position, event.localPosition, state, canvasSize);
          }
          return;
        }
      } else {
        // No selection — double-tap an image to select it
        if (_isDoubleTap(event.localPosition)) {
          final tappedImage = _findImageOrShapeAt(state, pagePos);
          if (tappedImage != null) {
            ref.read(canvasProvider.notifier).selectElement(tappedImage);
            return;
          }
        }
        _isTouchPanning = true;
        _lastFocalPoint = event.position;
        // Don't show context menu if stylus is actively drawing (palm rest)
        if (!_activeStrokeNotifier.isActive) {
          _startLongPressTimer(event.position, event.localPosition, state, canvasSize);
        }
        return;
      }
    }

    // Pending symbol placement: tap to place symbol at this position
    if (state.pendingSymbol != null) {
      ref.read(canvasProvider.notifier).insertSymbol(state.pendingSymbol!, pagePos);
      return;
    }

    // Pending paste placement: tap to place duplicated/pasted content here
    if (state.pendingPaste && state.clipboard != null) {
      ref.read(canvasProvider.notifier).paste(at: pagePos);
      ref.read(canvasProvider.notifier).cancelPendingPaste();
      return;
    }

    // If we're in shape adjustment mode, user is adjusting the recognized shape
    if (state.isAdjustingRecognized && state.recognizedShape != null) {
      ref.read(canvasProvider.notifier).startAdjustRecognized(pagePos);
      return;
    }

    if (tool == CanvasTool.image) {
      _pickAndInsertImage(pagePos);
      return;
    }

    if (tool == CanvasTool.pan) {
      _lastFocalPoint = event.position;
      return;
    }

    if (tool == CanvasTool.text) {
      _handleTextTool(event.localPosition, state, canvasSize);
      return;
    }

    // If there's a selected element, handle tap interactions.
    // For draw tools: stylus/tablet pen deselects and draws through; plain mouse can interact.
    // For non-draw tools: all input devices can interact.
    if (state.selectedElementId != null) {
      final isPenLikeDevice = event.kind == PointerDeviceKind.stylus ||
          (event.kind == PointerDeviceKind.mouse && event.pressure > 0) ||
          (event.kind == PointerDeviceKind.touch && !_effectiveStylusOnly());
      if (_isDrawLikeTool(tool) && isPenLikeDevice) {
        // Stylus/tablet pen in draw mode: deselect image and proceed to draw
        ref.read(canvasProvider.notifier).deselectElement();
      } else {
        final isPlainMouseInDrawMode = _isDrawLikeTool(tool) && !isPenLikeDevice;
        if (!_isDrawLikeTool(tool) || isPlainMouseInDrawMode) {
          final selBounds = _getSelectedElementBounds(state);
          // Expand bounds to include action bar/handles above
          final scale = state.zoom * _getRenderScale(state, canvasSize);
          final topPad = 100.0 / scale;
          final sidePad = 20.0 / scale;
          final extended = selBounds == null ? null : Rect.fromLTRB(
            selBounds.left - sidePad,
            selBounds.top - topPad,
            selBounds.right + sidePad,
            selBounds.bottom + sidePad,
          );
          if (extended != null && extended.contains(pagePos)) {
            // Let ImageHandleOverlay or selection tool handle this interaction
            return;
          }
          // Tapped outside selection — deselect. Return so a plain-mouse
          // deselect click doesn't fall through and start a 1-point stroke
          // (the stray "black dot on deselect" the user reported).
          ref.read(canvasProvider.notifier).deselectElement();
          return;
        }
      }
    }

    // Check if tapping an image/shape to select it
    if (tool == CanvasTool.lasso) {
      // Check existing selection drag
      if (state.lassoSelection != null) {
        final sel = state.lassoSelection!;
        final bounds = sel.bounds.translate(sel.dragOffset.dx, sel.dragOffset.dy);
        if (bounds.inflate(10).contains(pagePos)) {
          _isDraggingSelection = true;
          _lastLassoDragPos = pagePos;
          // Snapshot the current Riverpod transform so subsequent drag
          // deltas accumulate locally — no per-frame Riverpod rebuild.
          _lassoTransformNotifier.begin(
            dragOffset: sel.dragOffset,
            rotation: sel.rotation,
            scale: sel.scale,
          );
          return;
        }
      }
    }

    // Check if double-tapping on an image/shape → select it.
    // MUST run before tool-specific early returns below (eraser/shape/lasso),
    // otherwise double-click is swallowed by the lasso path start for lasso,
    // and by the stroke start for eraser/shape.
    //
    // For non-draw tools (lasso/pan/text): check images and shapes.
    // For draw tools: only select images (not shapes) if input is a plain mouse
    // (no pressure), so stylus and tablet pens always draw through images.
    {
      final bool shouldCheckImageTap;
      if (tool == CanvasTool.lasso || tool == CanvasTool.pan || tool == CanvasTool.text) {
        shouldCheckImageTap = true;
      } else if (_isDrawLikeTool(tool) &&
                 event.kind == PointerDeviceKind.mouse &&
                 event.pressure <= 0) {
        shouldCheckImageTap = true;
      } else {
        shouldCheckImageTap = false;
      }
      if (shouldCheckImageTap && _isDoubleTap(event.localPosition)) {
        final onlyImages = _isDrawLikeTool(tool);
        final tappedImageOrShape = _findImageOrShapeAt(state, pagePos, imagesOnly: onlyImages);
        if (tappedImageOrShape != null) {
          ref.read(canvasProvider.notifier).selectElement(tappedImageOrShape);
          return;
        }
      }
    }

    // Eraser: only erase, don't start a stroke visual
    if (tool == CanvasTool.eraserStandard || tool == CanvasTool.eraserStroke) {
      ref.read(canvasProvider.notifier).startStroke(pagePos, pressure);
      return;
    }

    // Laser pointer: append to the fading-trail notifier ONLY. Never
    // touches Riverpod, never commits a stroke; the trail evaporates
    // on its own after a couple of seconds. start:true marks this as
    // the first point of a new gesture so the painter doesn't bridge
    // it with a long straight line from the previous stroke's end.
    if (tool == CanvasTool.laser) {
      _laserStrokeNotifier.addPoint(pagePos, start: true);
      return;
    }

    // Shape tool: only set start pos, no visual stroke
    if (tool == CanvasTool.shape) {
      ref.read(canvasProvider.notifier).startStroke(pagePos, pressure);
      return;
    }

    // Lasso tool: only track via provider (no visual pen stroke).
    // ORDER MATTERS: bake+clear the previous selection BEFORE starting the new
    // lasso path. Otherwise the render engine paints one frame with the stale
    // selection bounds (still carrying the previous dragOffset) while the new
    // path already contains its first point — the user perceives this as the
    // new lasso "starting offset" from the true touch location.
    if (tool == CanvasTool.lasso) {
      ref.read(canvasProvider.notifier).clearLassoPath(); // bake previous + reset provider path
      _lassoPathNotifier.start(pagePos);
      return;
    }

    // For pen/brush/highlighter only: pass the RAW pressure (incl. 0 for
    // mouse/touchpad) to the fast notifier. The notifier synthesises a
    // velocity-derived pseudo-pressure when the device reports no pressure,
    // restoring stroke modulation that's otherwise stuck at the 0.5
    // fallback. The provider keeps the 0.5 fallback for its own bookkeeping
    // (its activeStroke is overwritten on commit by the notifier's points).
    // A mouse-made marquee selection is transient: drawing with the pen
    // dismisses it so the dashed lasso doesn't linger on the page "forever".
    if (state.lassoSelection != null) {
      ref.read(canvasProvider.notifier).clearSelection();
    }
    final rawPressureForPen = _penPressure(event);
    ref.read(canvasProvider.notifier).startStroke(pagePos, pressure);
    _activeStrokeNotifier.start(pagePos, rawPressureForPen,
        pageUnitsPerPx: _pageUnitsPerScreenPx(state, canvasSize));
    _lastStrokeActivity = DateTime.now();
    _lastHoldCheckPos = pagePos;
  }

  /// Page units spanned by one logical screen pixel at the current zoom —
  /// the quantization scale of Windows' integer-pixel pointer coords. Fed
  /// to [ActiveStrokeNotifier] so its dejitter filter can reason in screen
  /// pixels while operating on page coordinates.
  ///
  /// Returns 0 (filter disabled) when the native sub-pixel stream is
  /// alive: those positions carry the digitizer's real precision, and
  /// smoothing them would only soften genuine detail — the same reason
  /// the Linux float-coordinate path is a passthrough.
  double _pageUnitsPerScreenPx(CanvasState state, Size canvasSize) {
    if (WindowsPenSubpixel.latestFresh() != null) return 0;
    final scale = state.zoom * _getRenderScale(state, canvasSize);
    return scale > 0 ? 1.0 / scale : 0;
  }

  /// Event position for drawing, upgraded to the digitizer's sub-pixel
  /// precision on Windows when the native bridge has a fresh in-contact
  /// sample (see [WindowsPenSubpixel]). The 3-px sanity gate discards a
  /// sample that belongs to a different moment than this event (channel
  /// vs pointer-queue ordering hiccup) — falling back to the quantized
  /// position is always safe.
  Offset _stylusLocalPosition(PointerEvent event) {
    if (kIsWeb || !io.Platform.isWindows) return event.localPosition;
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return event.localPosition;
    }
    final sample = WindowsPenSubpixel.latestFresh();
    if (sample == null) return event.localPosition;
    final box =
        _canvasStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return event.localPosition;
    final local = box.globalToLocal(sample);
    if ((local - event.localPosition).distance > 3.0) {
      return event.localPosition;
    }
    return local;
  }

  void _onPointerMove(PointerMoveEvent event, CanvasState state, Size canvasSize) {
    if (_suppressedSynthBarrelPointers.contains(event.pointer)) return;
    // Palm resting next to the stylus: its own moves must not draw/pan.
    if (_ignoredPalmPointers.contains(event.pointer)) return;
    if (_activePointers >= 2) return;

    // ── PDF text selection drag (device-aware; started in _onPointerDown) ──
    if (_pdfTextDragActive) {
      _ensurePdfTextSel(state)
          ?.update(_toPageCoords(event.localPosition, state, canvasSize));
      return;
    }
    // ── Mouse marquee drag (mouse = selection device) ──
    if (_mouseSelecting) {
      _lassoPathNotifier
          .addPoint(_toPageCoords(event.localPosition, state, canvasSize));
      return;
    }

    if (_isTouchPanning) {
      // Cancel long-press if finger moved significantly
      if (_longPressTimer != null) {
        final moved = (event.position - _longPressGlobalPos).distance;
        if (moved > 10) _cancelLongPressTimer();
      }
      if (_longPressFired) return; // Don't pan after context menu shown
      final delta = event.position - _lastFocalPoint;
      _lastFocalPoint = event.position;
      final latest = ref.read(canvasProvider);
      if (latest != null) {
        ref.read(canvasProvider.notifier).setPanOffset(latest.panOffset + delta);
        _checkPageDrag(latest, canvasSize,
            panOverride: latest.panOffset + delta);
      }
      return;
    }

    final tool = state.currentTool;

    // Shape adjustment mode: drag adjusts the recognized shape
    if (state.isAdjustingRecognized && state.recognizedShape != null) {
      final pagePos = _toPageCoords(event.localPosition, state, canvasSize);
      ref.read(canvasProvider.notifier).adjustRecognizedShape(pagePos);
      return;
    }

    if (tool == CanvasTool.pan) {
      final delta = event.position - _lastFocalPoint;
      _lastFocalPoint = event.position;
      final latest = ref.read(canvasProvider);
      if (latest != null) {
        ref.read(canvasProvider.notifier).setPanOffset(latest.panOffset + delta);
        _checkPageDrag(latest, canvasSize,
            panOverride: latest.panOffset + delta);
      }
      return;
    }

    if (_isDraggingSelection) {
      final pagePos = _toPageCoords(event.localPosition, state, canvasSize);
      final delta = pagePos - _lastLassoDragPos;
      _lastLassoDragPos = pagePos;
      // Update local notifier (no Riverpod). Painter listens via
      // _repaintNotifier so only the canvas layer repaints.
      _lassoTransformNotifier.translate(delta);
      return;
    }

    final pagePos =
        _toPageCoords(_stylusLocalPosition(event), state, canvasSize);
    final normPressure = _normalizedEventPressure(event);
    final pressure = normPressure > 0 ? normPressure : 0.5;
    // Pass raw pressure (incl. 0) to the active-stroke notifier so it can
    // synth pseudo-pressure from velocity for non-pressure devices
    // (mouse/touchpad). Stylus events report > 0 (or are enriched from the
    // Linux native bridge via _penPressure) and pass through.
    final rawPressureForPen = _penPressure(event);

    if (tool == CanvasTool.lasso) {
      _onLassoPointerMove(pagePos);
      return;
    }

    // Laser: keep appending to the fading trail, never start a real
    // stroke. Bypasses Riverpod entirely; the painter listens on
    // _laserStrokeNotifier via _repaintNotifier.
    if (tool == CanvasTool.laser) {
      _laserStrokeNotifier.addPoint(pagePos);
      return;
    }

    // If a selected element exists and no active stroke, don't draw
    // (If a stroke is in progress, the element was deselected in pointerDown;
    //  allow moves through until the state rebuilds.)
    if (state.selectedElementId != null && !_activeStrokeNotifier.isActive) return;

    // Fast path: during pen/brush drawing, only update the notifier (no Riverpod rebuild).
    // Riverpod is only updated for eraser/lasso/shape tools that need state tracking.
    if (_activeStrokeNotifier.isActive) {
      // Shape recognized during hold:
      // - line: fix start point, drag moves endpoint
      // - circle/rectangle/triangle: fix top-left, drag resizes (bottom-right follows cursor)
      if (_shapeRecognizedDuringHold) {
        final recognizedShape = ref.read(canvasProvider)?.recognizedShape;
        if (recognizedShape != null && recognizedShape.shapeType == 'line') {
          ref.read(canvasProvider.notifier).setRecognizedLineEndpoint(pagePos);
        } else {
          ref.read(canvasProvider.notifier).resizeRecognizedShape(pagePos);
        }
        return;
      }

      // Post-continuation guard: the very first MOVE after a continuation
      // decision must land near the tail of the kept-alive stroke. If it
      // doesn't (the user really started a fresh stroke that happened to
      // arrive inside the defer window), commit the old stroke and start
      // a fresh one — otherwise the new mark would graft a phantom line
      // onto the previous stroke.
      if (_justContinuedFromDefer) {
        _justContinuedFromDefer = false;
        final notifierPts = _activeStrokeNotifier.points;
        if (notifierPts.isNotEmpty) {
          final last = notifierPts.last;
          final ddx = pagePos.dx - last.x;
          final ddy = pagePos.dy - last.y;
          // 12 page-units ≈ 24 screen-px at default 2× zoom — well above
          // any realistic Apple Pencil sample dropout but short enough to
          // catch unintended re-strokes nearby.
          if (ddx * ddx + ddy * ddy > 12 * 12) {
            final keptPts = _activeStrokeNotifier.snapshotForCommit();
            _activeStrokeNotifier.clear();
            ref.read(canvasProvider.notifier).commitAndEndStroke(keptPts);
            ref.read(canvasProvider.notifier).startStroke(pagePos, pressure);
            _activeStrokeNotifier.start(pagePos, rawPressureForPen,
                pageUnitsPerPx: _pageUnitsPerScreenPx(state, canvasSize));
            _lastStrokeActivity = DateTime.now();
            _lastHoldCheckPos = pagePos;
            return;
          }
        }
      }
      _activeStrokeNotifier.addPoint(pagePos, rawPressureForPen);
      _lastStrokeActivity = DateTime.now();

      // Reset hold-to-recognize timer (GoodNotes-style: recognize when user pauses)
      // Tolerate micro-jitter from stylus: only reset timer if movement > 3px
      final holdDx = pagePos.dx - _lastHoldCheckPos.dx;
      final holdDy = pagePos.dy - _lastHoldCheckPos.dy;
      final holdDistSq = holdDx * holdDx + holdDy * holdDy;
      const holdThresholdSq = 3.0 * 3.0; // 3px tolerance for stylus jitter

      if (holdDistSq > holdThresholdSq) {
        _lastHoldCheckPos = pagePos;
        _holdRecognizeTimer?.cancel();
        final currentState = ref.read(canvasProvider);
        if (currentState != null && currentState.toolSettings.shapeRecognition) {
          _holdRecognizeTimer = Timer(const Duration(milliseconds: 200), () {
            _tryRecognizeHeldStroke();
          });
        }
      }
      return;
    }
    ref.read(canvasProvider.notifier).continueStroke(pagePos, pressure);
  }

  void _onLassoPointerMove(Offset pagePos) {
    if (!_lassoPathNotifier.isActive) return;
    _lassoPathNotifier.addPoint(pagePos);
  }

  /// Try to recognize a shape when user holds still during drawing.
  void _tryRecognizeHeldStroke() {
    if (!_activeStrokeNotifier.isActive) return;
    final points = _activeStrokeNotifier.points;
    if (points.length < 5) return;

    final state = ref.read(canvasProvider);
    if (state == null || !state.toolSettings.shapeRecognition) return;

    // Ask provider to try recognition
    ref.read(canvasProvider.notifier).recognizeHeldStroke(List.of(points));

    // Check if it was recognized
    final newState = ref.read(canvasProvider);
    if (newState?.recognizedShape != null) {
      _shapeRecognizedDuringHold = true;
      _activeStrokeNotifier.clearPoints(); // Hide stroke, keep active flag
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    // Matching cleanup for the synth-mouse pointer suppressed in
    // `_onPointerDown` — never bumped `_activePointers`, so don't
    // decrement it here either.
    if (_suppressedSynthBarrelPointers.remove(event.pointer)) return;
    // Ignored palm pointer lifting: never counted, so don't decrement.
    if (_ignoredPalmPointers.remove(event.pointer)) return;
    final wasMultiTouch = _activePointers >= 2;
    _activePointers = max(0, _activePointers - 1);

    // ── PDF text selection: finish the gesture (tap promotes to whole line) ──
    if (_pdfTextDragActive) {
      _pdfTextDragActive = false;
      final liveUp = ref.read(canvasProvider);
      if (liveUp != null) _ensurePdfTextSel(liveUp)?.end();
      // If the barrel was released mid-drag, restore the pre-barrel tool now
      // that the selection has committed (the highlighted text stays).
      _resolveBarrelRevert();
      return;
    }
    // ── Mouse marquee: commit the polygon (a click with no drag = deselect) ──
    if (_mouseSelecting) {
      _mouseSelecting = false;
      if (_lassoPathNotifier.isActive) {
        final pts = List<Offset>.from(_lassoPathNotifier.points);
        _lassoPathNotifier.clear();
        ref.read(canvasProvider.notifier).commitLassoPath(pts);
      }
      return;
    }

    // Clear stylus tracking when stylus lifts
    if (event.kind == PointerDeviceKind.stylus || event.kind == PointerDeviceKind.invertedStylus) {
      _strokeDbg(
        'UP stylus p=${event.pointer} t=${event.timeStamp.inMilliseconds}ms '
        'active=${_activeStrokeNotifier.isActive} '
        'pts=${_activeStrokeNotifier.points.length} '
        'multiTouch=$wasMultiTouch '
        'activePointers=$_activePointers',
      );
      _stylusDown = false;
    }

    // Don't commit anything if this was a multi-touch gesture (pinch-to-zoom)
    if (wasMultiTouch || _activePointers >= 1) return;

    // Barrel button override: commit + restore previous tool on lift.
    // Eraser → endStroke flushes any erasures. Lasso → commit the
    // collected path through the same provider call the normal lasso
    // pointer-up uses, so a selection lands if the user closed a
    // polygon around something. Either way, the user's original tool
    // (the one they were using before holding the barrel) is restored
    // so they fall right back into writing.
    if (_barrelButtonOverride) {
      _barrelButtonOverride = false;
      final notif = ref.read(canvasProvider.notifier);
      final prevTool = _barrelButtonPreviousTool;
      final curTool = ref.read(canvasProvider)?.currentTool;
      // Tool-specific cleanup before restoring.
      if (curTool == CanvasTool.eraserStandard ||
          curTool == CanvasTool.eraserStroke) {
        notif.endStroke();
      } else if (curTool == CanvasTool.lasso && _lassoPathNotifier.isActive) {
        final pts = List<Offset>.from(_lassoPathNotifier.points);
        _lassoPathNotifier.clear();
        notif.commitLassoPath(pts);
      }
      _markStrokeEnded('pointerUp.barrelEnd');
      // If the lasso caught a selection, STAY in lasso so the marquee is
      // interactive (move / scale / rotate / delete). Restoring the previous
      // tool now would run setTool(prev) → clearLasso → WIPE the just-made
      // selection — the "faccio il cerchio e mollo, non mi prende la selezione,
      // torna con la penna" bug. Keep _barrelButtonPreviousTool so
      // _watchForLassoCleared restores it once the user deselects.
      if (ref.read(canvasProvider)?.lassoSelection != null) {
        return;
      }
      _barrelButtonPreviousTool = null;
      if (prevTool != null) notif.setTool(prevTool);
      return;
    }

    if (_isTouchPanning) {
      _isTouchPanning = false;
      _cancelLongPressTimer();
      _longPressFired = false;
      final latest = ref.read(canvasProvider);
      if (latest != null) {
        _commitOrCancelPageDrag(latest, _lastCanvasSize);
      } else {
        _clearPageHints();
      }
      return;
    }

    _holdRecognizeTimer?.cancel();

    if (_isDraggingSelection) {
      _isDraggingSelection = false;
      // Commit the locally-tracked drag offset back to Riverpod in one
      // shot. During the drag _lassoTransformNotifier received every
      // delta; now Riverpod catches up exactly once per gesture.
      _commitLassoTransform();
      // The full transform (rotation/scale + drag) stays in lassoSelection
      // and is baked into the canvas when the user clicks away or
      // changes tool, same as before.
      return;
    }

    final state = ref.read(canvasProvider);
    if (state == null) return;

    // Shape recognized during hold → commit immediately
    if (_shapeRecognizedDuringHold && state.recognizedShape != null) {
      _shapeRecognizedDuringHold = false;
      _activeStrokeNotifier.clear();
      ref.read(canvasProvider.notifier).commitRecognizedShape();
      _markStrokeEnded('pointerUp.shapeCommit');
      return;
    }
    _shapeRecognizedDuringHold = false;

    // Shape adjustment mode: commit the adjusted shape
    if (state.isAdjustingRecognized && state.recognizedShape != null) {
      ref.read(canvasProvider.notifier).commitRecognizedShape();
      _markStrokeEnded('pointerUp.shapeAdjust');
      return;
    }

    if (state.currentTool == CanvasTool.pan) {
      _commitOrCancelPageDrag(state, _lastCanvasSize);
      return;
    }
    if (state.currentTool == CanvasTool.image) return;

    // Lasso: commit the locally-tracked path to Riverpod and trigger selection
    if (state.currentTool == CanvasTool.lasso) {
      if (_lassoPathNotifier.isActive) {
        final pts = List<Offset>.from(_lassoPathNotifier.points); // copy before clear
        _lassoPathNotifier.clear();
        ref.read(canvasProvider.notifier).commitLassoPath(pts);
        // Read fresh state — commitLassoPath sets lassoSelection synchronously
        // if any element was caught by the polygon. Fire a small confirm
        // haptic on success so the user knows their selection landed.
        final afterCommit = ref.read(canvasProvider);
        if (afterCommit?.lassoSelection != null) {
          HapticFeedback.selectionClick();
        }
      }
      // Return in the inactive case too — NEVER fall through to the
      // endStroke() catch-all below with the lasso tool active: with the
      // path already committed (e.g. by the Windows barrel bridge)
      // endStroke() → _endLasso() sees an empty path and clearLasso-wipes
      // the selection that was just made, cancelling the user's lasso the
      // instant they release the pen/barrel.
      // A barrel released mid-circle deferred its keep/revert to here, now
      // that lassoSelection is committed.
      _resolveBarrelRevert();
      return;
    }

    // Commit fast notifier points and finalize in one go to avoid
    // an intermediate render frame showing the raw points (line stretching).
    if (_activeStrokeNotifier.isActive && _activeStrokeNotifier.points.isNotEmpty) {
      // ── Stroke break defense ──
      //
      // For stylus (Apple Pencil on iPad), defer the commit by
      // _deferStylusMs. iPad/Apple Pencil occasionally emits a spurious
      // PointerUp followed by a PointerDown while the user has not
      // actually lifted the pen. Without defer, each segment would be
      // committed as a separate stroke and the user sees a mid-letter
      // break. If a fresh stylus DOWN arrives in the defer window close
      // to this end position, _onPointerDown resumes the same stroke
      // (notifier is kept active during defer; continuation just cancels
      // the timer). Otherwise the timer fires and commits normally
      // (notifier is cleared inside _flushDeferredCommit, in the same
      // frame as the commit so the rendered stroke does not blink).
      //
      // For non-stylus (mouse/touchpad/touch) commit immediately as
      // before — the bug is iPad-specific and adding latency on PC
      // would be a regression.
      if (event.kind == PointerDeviceKind.stylus ||
          event.kind == PointerDeviceKind.invertedStylus) {
        // Snapshot points (notifier stays active so the rendered live
        // stroke remains on screen during the defer window). The
        // snapshot is the dequantized commit copy — the pen fallback
        // path benefits from the same refit as the mouse (no-op when
        // sub-pixel data was in use).
        _deferredCommitPoints = _activeStrokeNotifier.snapshotForCommit();
        _deferredCommitAt = DateTime.now();
        _deferredCommitLastScreenPos = event.position;
        _deferredCommitTimer?.cancel();
        _deferredCommitTimer = Timer(
          const Duration(milliseconds: _deferStylusMs),
          _flushDeferredCommit,
        );
      } else {
        final points = _activeStrokeNotifier.snapshotForCommit();
        // Plain-mouse "dot" suppression: a click that doesn't move (the
        // first half of a double-click-to-select, a click-to-deselect, or a
        // stray click) used to commit a tiny 1-point stroke — a black dot
        // the user never intended. Pen/touch dots (dotting an 'i') are kept;
        // only zero-movement MOUSE clicks are discarded.
        if (event.kind == PointerDeviceKind.mouse && _isDotStroke(points)) {
          _activeStrokeNotifier.clear();
          ref.read(canvasProvider.notifier).cancelStroke();
          _markStrokeEnded('pointerUp.mouseDotDropped');
        } else {
          _activeStrokeNotifier.clear();
          ref.read(canvasProvider.notifier).commitAndEndStroke(points);
          _markStrokeEnded('pointerUp.commit');
        }
      }
    } else {
      _activeStrokeNotifier.clear();
      ref.read(canvasProvider.notifier).endStroke();
      _markStrokeEnded('pointerUp.endEmpty');
    }
    // Catch-all for a barrel released mid-gesture that didn't go through the
    // lasso-commit return above (e.g. a barrel tap with no circle drawn).
    _resolveBarrelRevert();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_suppressedSynthBarrelPointers.remove(event.pointer)) return;
    // Ignored palm pointer cancelled: never counted, so don't decrement —
    // and don't touch the active stylus stroke either.
    if (_ignoredPalmPointers.remove(event.pointer)) return;
    _activePointers = max(0, _activePointers - 1);
    // End any in-progress PDF text drag / mouse marquee and resolve a deferred
    // barrel revert so a cancelled gesture doesn't leave the flags stuck.
    _pdfTextDragActive = false;
    if (_mouseSelecting) {
      _mouseSelecting = false;
      _lassoPathNotifier.clear();
    }
    _resolveBarrelRevert();
    _strokeDbg(
      'CANCEL kind=${event.kind.name} p=${event.pointer} '
      't=${event.timeStamp.inMilliseconds}ms '
      'stylusDown=$_stylusDown active=${_activeStrokeNotifier.isActive} '
      'pts=${_activeStrokeNotifier.points.length} '
      'activePointers=$_activePointers',
    );
    // If iOS palm-rejection cancels a touch pointer while the stylus is
    // actively drawing, DO NOT tear down the stylus stroke — the pen is
    // still making a valid mark. Only reset touch-specific gesture state
    // and return. Previously this path undid the user's first stroke
    // whenever their palm brushed the screen mid-draw on iPad.
    if (event.kind == PointerDeviceKind.touch && _stylusDown) {
      _isTouchPanning = false;
      _holdRecognizeTimer?.cancel();
      _shapeRecognizedDuringHold = false;
      return;
    }
    _isTouchPanning = false;
    if (_isDraggingSelection) {
      _isDraggingSelection = false;
      // Close the local transform notifier too: leaving it active applies
      // the stale drag offset/rotation to the NEXT lasso selection and
      // bypasses the picture cache on every frame.
      _commitLassoTransform();
    }
    _holdRecognizeTimer?.cancel();
    _shapeRecognizedDuringHold = false;
    // ── Stroke-break defense ──
    //
    // If a stylus PointerCancel arrives while we already have meaningful
    // points buffered, COMMIT the partial stroke instead of discarding it.
    // This way an unexpected cancel (gesture arena race we didn't catch,
    // iPadOS palm-rejection misfire on the pen, transient Pencil
    // disconnect, app briefly losing focus) still leaves the user's mark
    // on the page rather than producing a visible mid-letter break. The
    // next pointer event simply starts a fresh stroke. <2 points means
    // the stroke is effectively a tap and is safe to discard.
    final isStylusCancel = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    // A cancelled stylus pointer never gets a PointerUp: clear the flag here
    // too, or it stays stuck true and keeps blocking zoom + treating every
    // touch as palm until the pen touches down again.
    if (isStylusCancel) _stylusDown = false;
    if (isStylusCancel &&
        _activeStrokeNotifier.isActive &&
        _activeStrokeNotifier.points.length >= 2) {
      final points = _activeStrokeNotifier.snapshotForCommit();
      _activeStrokeNotifier.clear();
      ref.read(canvasProvider.notifier).commitAndEndStroke(points);
      _markStrokeEnded('pointerCancel.committedStylus');
      _strokeDbg('CANCEL_RESCUED kind=${event.kind.name} pts=${points.length}');
      // Restore barrel button state if needed before returning
      if (_barrelButtonOverride) {
        _barrelButtonOverride = false;
        if (_barrelButtonPreviousTool != null) {
          ref.read(canvasProvider.notifier).setTool(_barrelButtonPreviousTool!);
          _barrelButtonPreviousTool = null;
        }
      }
      return;
    }
    // Cancel any in-progress stroke or lasso
    if (_activeStrokeNotifier.isActive) {
      _activeStrokeNotifier.clear();
      ref.read(canvasProvider.notifier).cancelStroke();
      _markStrokeEnded('pointerCancel.stroke');
    }
    if (_lassoPathNotifier.isActive) {
      _lassoPathNotifier.clear();
    }
    // Restore barrel button state
    if (_barrelButtonOverride) {
      _barrelButtonOverride = false;
      if (_barrelButtonPreviousTool != null) {
        ref.read(canvasProvider.notifier).setTool(_barrelButtonPreviousTool!);
        _barrelButtonPreviousTool = null;
      }
    }
  }

  /// Distance from [p] to the segment [a]-[b].
  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq)
        .clamp(0.0, 1.0);
    return (p - Offset(a.dx + ab.dx * t, a.dy + ab.dy * t)).distance;
  }

  /// Distance from [p] to the OUTLINE of [sh] (handles rotation).
  /// A shape's bounding box is mostly empty space for lines/circles, so
  /// hit-testing must use the real geometry — bbox-contains selected a
  /// diagonal line from taps nowhere near it.
  static double _distToShapeOutline(ShapeData sh, Offset p) {
    // Undo the shape's rotation on the probe point so all the outline
    // math below can stay axis-aligned.
    var q = p;
    if (sh.rotation != 0) {
      final cx = (sh.x1 + sh.x2) / 2, cy = (sh.y1 + sh.y2) / 2;
      final ca = cos(-sh.rotation), sa = sin(-sh.rotation);
      final dx = p.dx - cx, dy = p.dy - cy;
      q = Offset(cx + dx * ca - dy * sa, cy + dx * sa + dy * ca);
    }
    final l = min(sh.x1, sh.x2), r = max(sh.x1, sh.x2);
    final t = min(sh.y1, sh.y2), b = max(sh.y1, sh.y2);
    switch (sh.shapeType) {
      case 'line':
      case 'arrow':
        return _distToSegment(q, Offset(sh.x1, sh.y1), Offset(sh.x2, sh.y2));
      case 'circle':
        final c = Offset((sh.x1 + sh.x2) / 2, (sh.y1 + sh.y2) / 2);
        final radius = Offset(sh.x2 - sh.x1, sh.y2 - sh.y1).distance / 2;
        return ((q - c).distance - radius).abs();
      case 'triangle':
        final apex = Offset((l + r) / 2, t);
        final bl = Offset(l, b), br = Offset(r, b);
        return [
          _distToSegment(q, apex, bl),
          _distToSegment(q, bl, br),
          _distToSegment(q, br, apex),
        ].reduce(min);
      case 'rhombus':
        final top = Offset((l + r) / 2, t), right = Offset(r, (t + b) / 2);
        final bottom = Offset((l + r) / 2, b), left = Offset(l, (t + b) / 2);
        return [
          _distToSegment(q, top, right),
          _distToSegment(q, right, bottom),
          _distToSegment(q, bottom, left),
          _distToSegment(q, left, top),
        ].reduce(min);
      default: // rectangle and anything unknown: rect edges
        final tl = Offset(l, t), tr = Offset(r, t);
        final brc = Offset(r, b), blc = Offset(l, b);
        return [
          _distToSegment(q, tl, tr),
          _distToSegment(q, tr, brc),
          _distToSegment(q, brc, blc),
          _distToSegment(q, blc, tl),
        ].reduce(min);
    }
  }

  /// True if [pagePos] is within [tolerance] of any point of the stroke.
  static bool _strokeHit(StrokeData data, Offset pagePos, double tolerance) {
    final tolSq = tolerance * tolerance;
    for (final p in data.points) {
      final dx = p.x - pagePos.dx;
      final dy = p.y - pagePos.dy;
      if (dx * dx + dy * dy < tolSq) return true;
    }
    return false;
  }

  String? _findElementAt(CanvasState state, Offset pagePos,
      {bool skipLocked = false}) {
    final page = state.currentPage;
    if (page == null) return null;

    // Search in reverse order (top elements first)
    for (int i = page.layers.content.length - 1; i >= 0; i--) {
      final element = page.layers.content[i];
      Rect? bounds;
      String? id;
      // Strokes and shapes hit-test against real geometry (a diagonal
      // line's bbox is mostly empty space); solid rects keep bbox.
      var geometryHit = false;
      element.map(
        stroke: (s) {
          if (s.data.points.isEmpty) return;
          if (_strokeHit(s.data, pagePos, max(8.0, s.data.baseWidth))) {
            id = s.id;
            geometryHit = true;
          }
        },
        text: (t) {
          id = t.id;
          bounds = Rect.fromLTWH(t.data.x, t.data.y, t.data.width, t.data.height);
        },
        image: (img) {
          // Skip the locked full-page PDF raster so a click on the page
          // doesn't grab the background instead of selecting an annotation
          // or starting a marquee.
          if (skipLocked && img.data.locked) return;
          id = img.id;
          bounds = Rect.fromLTWH(img.data.x, img.data.y, img.data.width, img.data.height);
        },
        shape: (s) {
          if (_distToShapeOutline(s.data, pagePos) <
              max(8.0, s.data.strokeWidth)) {
            id = s.id;
            geometryHit = true;
          }
        },
        math: (e) {
          id = e.id;
          bounds = Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height);
        },
      );
      if (geometryHit && id != null) return id;
      if (bounds != null && bounds!.inflate(5).contains(pagePos) && id != null) {
        return id;
      }
    }
    return null;
  }

  /// Find an image or shape element at the given page position (ignoring strokes/text).
  String? _findImageOrShapeAt(CanvasState state, Offset pagePos, {bool imagesOnly = false}) {
    final page = state.currentPage;
    if (page == null) return null;
    for (int i = page.layers.content.length - 1; i >= 0; i--) {
      final element = page.layers.content[i];
      Rect? bounds;
      String? id;
      var geometryHit = false;
      element.map(
        stroke: (_) {},
        text: (t) {
          if (!imagesOnly) {
            id = t.id;
            bounds = Rect.fromLTWH(t.data.x, t.data.y, t.data.width, t.data.height);
          }
        },
        image: (img) {
          id = img.id;
          bounds = Rect.fromLTWH(img.data.x, img.data.y, img.data.width, img.data.height);
        },
        shape: (s) {
          if (!imagesOnly &&
              _distToShapeOutline(s.data, pagePos) <
                  max(8.0, s.data.strokeWidth)) {
            id = s.id;
            geometryHit = true;
          }
        },
        math: (e) {
          if (!imagesOnly) {
            id = e.id;
            bounds = Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height);
          }
        },
      );
      if (geometryHit && id != null) return id;
      if (bounds != null && bounds!.inflate(5).contains(pagePos) && id != null) {
        return id;
      }
    }
    return null;
  }

  Rect? _getSelectedElementBounds(CanvasState state) {
    if (state.selectedElementId == null) return null;
    final page = state.currentPage;
    if (page == null) return null;
    for (final element in page.layers.content) {
      final id = element.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
      if (id != state.selectedElementId) continue;
      return element.map(
        stroke: (e) {
          if (e.data.points.isEmpty) return null;
          final xs = e.data.points.map((p) => p.x);
          final ys = e.data.points.map((p) => p.y);
          return Rect.fromLTRB(xs.reduce(min), ys.reduce(min), xs.reduce(max), ys.reduce(max));
        },
        text: (e) => Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
        image: (e) => Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
        shape: (e) => Rect.fromPoints(Offset(e.data.x1, e.data.y1), Offset(e.data.x2, e.data.y2)),
        math: (e) => Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
      );
    }
    return null;
  }

  // ── Pinch-to-zoom ──

  void _onScaleStart(ScaleStartDetails details) {
    // Palm rejection: if the stylus is currently drawing, the scale gesture
    // was triggered by the user's wrist landing on the screen — ignore it
    // so the canvas doesn't zoom mid-stroke.
    if (_stylusDown) return;
    final state = ref.read(canvasProvider);
    if (state == null) return;
    _baseZoom = state.zoom;
    _lastFocalPoint = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Same palm guard as _onScaleStart. Even if onScaleStart was already
    // rejected, Flutter still calls onScaleUpdate during the gesture — we
    // must gate it too, otherwise a palm landing mid-stroke can still move
    // the zoom level via the accumulated scale delta.
    if (_stylusDown) return;
    // Accept scale gesture if either: 2+ pointers (multi-touch), or scale != 1 (trackpad pinch)
    if (details.pointerCount < 2 && (details.scale - 1).abs() < 0.001) return;

    final notifier = ref.read(canvasProvider.notifier);
    final state = ref.read(canvasProvider);
    if (state == null) return;

    final newZoom = (_baseZoom * details.scale).clamp(0.3, 5.0);

    // Use the CURRENT zoom (not _baseZoom) for pan calculation so the
    // focal-point anchor stays stable across incremental updates.
    final oldZoom = state.zoom;
    final focalPoint = details.localFocalPoint;
    // focalPointDelta makes two-finger gestures scroll the document:
    // trackpad two-finger scroll arrives here as a pan-zoom gesture with
    // scale == 1 (each pan-zoom pointer counts as 2 in pointerCount), and
    // two-finger touch pans while pinching, like every other note app.
    // Without it this handler was zoom-only and trackpad scroll did nothing.
    final newPan = state.panOffset +
        (focalPoint - state.panOffset) * (1 - (newZoom / oldZoom)) +
        details.focalPointDelta;

    notifier.setZoomAndPan(newZoom, newPan);
    _lastFocalPoint = details.focalPoint;
  }

  // ── Text insertion / editing ──

  /// Topmost TextElement whose bounds contain [pagePos], or null.
  TextElement? _findTextElementAt(CanvasState state, Offset pagePos) {
    final page = state.currentPage;
    if (page == null) return null;
    for (int i = page.layers.content.length - 1; i >= 0; i--) {
      final element = page.layers.content[i];
      if (element is! TextElement) continue;
      final t = element.data;
      final bounds = Rect.fromLTWH(t.x, t.y, t.width, t.height);
      if (bounds.inflate(5).contains(pagePos)) return element;
    }
    return null;
  }

  /// Text tool tap: editing an existing text element when tapped on one,
  /// otherwise the rich editor for a brand-new element at that point.
  void _handleTextTool(Offset localPos, CanvasState state, Size canvasSize) async {
    final pagePos = _toPageCoords(localPos, state, canvasSize);
    final existing = _findTextElementAt(state, pagePos);

    final result = await showTextEditorDialog(
      context,
      initial: existing?.data,
      defaultColor: state.toolSettings.color,
    );
    if (result == null || !mounted) return;

    final notifier = ref.read(canvasProvider.notifier);
    if (existing != null) {
      notifier.updateTextElement(
        existing.id,
        content: result.content,
        spans: result.spans,
        fontSize: result.fontSize,
        color: result.color,
        alignment: result.alignment,
      );
    } else {
      notifier.addTextElement(
        pagePos,
        result.content,
        spans: result.spans,
        fontSize: result.fontSize,
        color: result.color,
        alignment: result.alignment,
      );
    }
  }

  // ── Clipboard paste (system image or internal) ──

  /// Formats we accept from the system clipboard, in priority order.
  /// PNG/JPEG first because they're already universally decodable. iOS
  /// screenshots land as HEIC or TIFF on the clipboard — those fell
  /// through the old PNG-or-JPEG-only check and the paste silently did
  /// nothing on iPad. For exotic formats we transcode to PNG before
  /// storing so the asset is readable on every platform (Flutter on
  /// Windows/Linux can't decode HEIC natively).
  static const _clipboardImageFormats = <(SimpleFileFormat, String)>[
    (Formats.png, 'png'),
    (Formats.jpeg, 'jpg'),
    (Formats.heic, 'heic'),
    (Formats.heif, 'heif'),
    (Formats.tiff, 'tiff'),
    (Formats.webp, 'webp'),
    (Formats.gif, 'gif'),
    (Formats.bmp, 'bmp'),
  ];

  /// [at] anchors the paste at an explicit page position (context menu:
  /// paste where the user clicked); null → visible viewport centre.
  Future<void> _pasteFromClipboard(
      {bool preferSystemImage = false, Offset? at}) async {
    // Resolve "what did the user most recently copy?" instead of blindly
    // preferring the in-app clipboard. An image on the SYSTEM clipboard wins
    // when it's genuinely newer than the in-app selection — detected by
    // comparing its signature against the last image we know about
    // (`_seenSystemImageSig`). This fixes: copy an image → Ctrl+V used to
    // paste the old in-app text because the internal clipboard short-circuit
    // always won. `preferSystemImage` (the 'Incolla immagine' menu) forces
    // the image path regardless.
    // A copy that just happened snapshots the system clipboard's identity
    // asynchronously. If the user hits Ctrl+V right behind Ctrl+C, that
    // snapshot may still be running — wait for it so the freshness compare
    // below sees the correct seen-sigs, not stale ones.
    if (_seenSnapshotInFlight != null) {
      await _seenSnapshotInFlight;
    }

    final sysImg = await _readSystemImageRaw();
    final cs = ref.read(canvasProvider);
    final hasInternal = cs != null && cs.clipboard != null;

    final systemImageIsNew =
        sysImg != null && sysImg.sig != _seenSystemImageSig;

    final useSystemImage = sysImg != null &&
        (preferSystemImage || systemImageIsNew || !hasInternal);

    if (useSystemImage) {
      // NOTE: we deliberately do NOT mark this image "seen" here — leaving
      // `_seenSystemImageSig` untouched lets a repeated Ctrl+V keep pasting
      // the same most-recently-copied image. It only flips to the in-app
      // clipboard once the user makes a fresh internal copy (which snapshots
      // the sig) or copies a different image.
      // Transcode exotic formats (HEIC/TIFF/WEBP/…) to PNG so they're
      // portable across platforms.
      Uint8List bytes = sysImg.raw;
      String fileName = 'clipboard_image.${sysImg.ext}';
      if (sysImg.ext != 'png' && sysImg.ext != 'jpg') {
        final transcoded = await _transcodeToPng(sysImg.raw);
        if (transcoded == null) {
          CrashLogger.append(
            '[Paste] failed to transcode ${sysImg.ext} from clipboard '
            '(${sysImg.raw.length} bytes)',
          );
          // Couldn't decode — fall back to the in-app clipboard below.
          if (hasInternal) _pasteInternal(at);
          return;
        }
        bytes = transcoded;
        fileName = 'clipboard_image.png';
      }
      final s = ref.read(canvasProvider);
      if (s == null || !mounted) return;
      _insertImage(bytes, fileName, at ?? _visibleCenterPagePos(s));
      return;
    }

    // ── System TEXT ── (was completely unhandled: Ctrl+V with text
    // copied from another app silently did nothing). Same freshness
    // logic as images: external text that we haven't "seen" wins over a
    // stale internal selection; with no internal clipboard, any system
    // text pastes (repeat Ctrl+V keeps working — we don't mark it seen
    // on paste, only on internal copies).
    final sysText = await _readSystemText();
    final systemTextIsNew =
        sysText != null && _textSig(sysText.plain) != _seenSystemTextSig;
    if (sysText != null && (systemTextIsNew || !hasInternal)) {
      final s = ref.read(canvasProvider);
      if (s == null || !mounted) return;
      final anchor = at ?? _visibleCenterPagePos(s);

      // Interpret Markdown + LaTeX in the PLAIN text FIRST. A copied "$$…$$"
      // or "\[…\]" almost always ALSO carries an HTML flavour (the raw source
      // wrapped in <p>/<span> tags by the source app), but the user's intent
      // is the typeset math/markdown — NOT the literal string. So rich plain
      // text wins over HTML here; we only fall back to HTML spans when the
      // plain text isn't itself rich (e.g. bold/italic prose copied from a web
      // page, which has no markdown markers). A single all-plain block keeps
      // the legacy single-element paste; anything richer (headings, lists,
      // styled runs, display math) becomes a vertically-stacked set of
      // text + typeset-math blocks in one undo.
      final blocks = sysText.plain.trim().isEmpty
          ? const <PastedBlock>[]
          : parsePastedRich(sysText.plain);
      final plainIsRich = blocks.isNotEmpty &&
          !(blocks.length == 1 &&
              blocks.first is PastedTextBlock &&
              (blocks.first as PastedTextBlock).spans.isEmpty);
      if (plainIsRich) {
        unawaited(ref.read(canvasProvider.notifier).pasteRichBlocks(
              blocks, anchor,
              color: 0xFF000000, maxWidth: 360,
              pixelRatio: _mathPixelRatio(context),
            ));
        return;
      }

      // Plain text isn't markdown/LaTeX → prefer HTML, which preserves
      // bold/italic/underline as rich spans in a single text element.
      if (sysText.html != null) {
        final rich = htmlToSpans(sysText.html!);
        if (rich != null && rich.plain.trim().isNotEmpty) {
          ref.read(canvasProvider.notifier).addTextElement(
                anchor, rich.plain,
                spans: rich.spans, color: 0xFF000000, width: 360,
              );
          return;
        }
      }
      if (sysText.plain.trim().isEmpty) {
        if (hasInternal) _pasteInternal(at);
        return;
      }
      // Plain, non-rich text → single text element.
      ref.read(canvasProvider.notifier).addTextElement(
            anchor, (blocks.first as PastedTextBlock).content,
            color: 0xFF000000, width: 360,
          );
      return;
    }

    // No (new) system image/text → use the in-app clipboard, dropping it
    // at the viewport centre so it lands where the user is looking (not
    // off the right edge of the page, the previous fixed +20,+20
    // behaviour).
    if (hasInternal) {
      _pasteInternal(at);
    }
  }

  /// Reads plain text (and HTML when present) from the system clipboard.
  /// Returns null when no usable text is available.
  Future<({String plain, String? html})?> _readSystemText() async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) return null;
      final reader = await clipboard.read();
      String? html;
      if (reader.canProvide(Formats.htmlText)) {
        html = await reader.readValue(Formats.htmlText);
      }
      String? plain;
      if (reader.canProvide(Formats.plainText)) {
        plain = await reader.readValue(Formats.plainText);
      }
      // Some apps put only HTML on the clipboard — derive plain from it.
      if ((plain == null || plain.isEmpty) && html != null) {
        plain = htmlToSpans(html)?.plain;
      }
      if (plain == null || plain.trim().isEmpty) return null;
      return (plain: plain, html: html);
    } catch (e) {
      CrashLogger.append('[Paste] system text read failed: $e');
      return null;
    }
  }

  /// Cheap fingerprint for clipboard text (length + rolling sample).
  String _textSig(String t) {
    int h = t.length;
    for (var i = 0; i < t.length; i += (t.length ~/ 16) + 1) {
      h = (h * 31 + t.codeUnitAt(i)) & 0x7fffffff;
    }
    return '${t.length}:$h';
  }

  void _pasteInternal(Offset? at) {
    final s = ref.read(canvasProvider);
    if (s == null) return;
    ref.read(canvasProvider.notifier).paste(at: at ?? _visibleCenterPagePos(s));
  }

  /// Cheap fingerprint of clipboard image bytes — length + a few sampled
  /// bytes. Enough to tell two clipboard images apart without hashing
  /// megabytes on every copy/paste.
  String _imageSig(Uint8List b) {
    final n = b.length;
    if (n == 0) return '0';
    int h = n;
    for (final frac in const [0, 1, 2, 3, 4]) {
      final idx = ((n - 1) * frac ~/ 4);
      h = (h * 31 + b[idx]) & 0x7fffffff;
    }
    return '$n:$h';
  }

  /// Reads the first available image on the system clipboard as raw bytes
  /// (no transcode), with its extension and a signature. Returns null when
  /// no image is present. Used both to paste and to snapshot the current
  /// clipboard image's identity on internal copies.
  Future<({Uint8List raw, String ext, String sig})?>
      _readSystemImageRaw() async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) return null;
      final reader = await clipboard.read();
      for (final entry in _clipboardImageFormats) {
        final fmt = entry.$1;
        final ext = entry.$2;
        if (!reader.canProvide(fmt)) continue;
        final completer = Completer<Uint8List?>();
        reader.getFile(fmt, (file) async {
          try {
            completer.complete(await file.readAll());
          } catch (_) {
            completer.complete(null);
          }
        }, onError: (_) => completer.complete(null));
        final raw = await completer.future;
        if (raw == null || raw.isEmpty) continue;
        return (raw: raw, ext: ext, sig: _imageSig(raw));
      }
    } catch (e, st) {
      CrashLogger.append('[Paste] system image read failed: $e\n$st');
    }
    return null;
  }

  /// Records whatever image currently sits on the system clipboard as
  /// "seen / stale" — called after an internal NON-image copy so a later
  /// Ctrl+V doesn't resurrect a leftover external image instead of the
  /// strokes/text the user just copied. Cheap when no image is present.
  Future<void> _markSystemImageSeen() {
    final future = () async {
      final r = await _readSystemImageRaw();
      _seenSystemImageSig = r?.sig;
      // Same staleness snapshot for system TEXT, so an internal copy takes
      // priority over whatever external text was left on the clipboard.
      final t = await _readSystemText();
      _seenSystemTextSig = t == null ? null : _textSig(t.plain);
    }();
    // Publish the in-flight snapshot so a paste racing right behind a copy
    // waits for it instead of reading stale seen-sigs (see field doc).
    _seenSnapshotInFlight = future;
    return future;
  }

  /// Decode [bytes] with the platform image codec and re-encode as PNG,
  /// so exotic formats (HEIC/HEIF/TIFF/WEBP/...) become portable. Returns
  /// null if the platform can't decode this format.
  Future<Uint8List?> _transcodeToPng(Uint8List bytes) async {
    ui.Image? image;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final pngData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (pngData == null) return null;
      return pngData.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
    }
  }

  // ── Image / PDF insertion ──

  /// image_picker only implements ImageSource.camera on Android/iOS —
  /// on desktop it throws a raw "Bad state: This implementation of
  /// ImagePickerPlatform…" that used to surface verbatim in a snackbar.
  /// Gates the "Scatta foto" menu entry.
  static final bool _cameraAvailable =
      io.Platform.isAndroid || io.Platform.isIOS;

  Future<void> _captureAndInsertImage(Offset pagePos) async {
    // Capture ref before the async gap — the widget may be unmounted
    // when the camera activity returns on Android.
    final notifier = ref.read(canvasProvider.notifier);
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;
    final l10n = mounted ? AppLocalizations.of(context) : null;
    if (!_cameraAvailable) {
      messenger?.showSnackBar(
        SnackBar(
            content: Text(l10n!.csCameraUnavailable)),
      );
      return;
    }
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera);
      if (photo == null) return;
      final file = io.File(photo.path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final dims = _decodeImageDimensions(bytes);
      double w = dims?.width.toDouble() ?? 300;
      double h = dims?.height.toDouble() ?? 200;
      if (w > 300) {
        final s = 300 / w;
        w *= s;
        h *= s;
      }
      notifier.addImageElement(pagePos, photo.name, bytes, w, h);
    } on StateError {
      // No camera / unsupported platform (emulators, tablets without camera).
      messenger?.showSnackBar(
        SnackBar(
            content: Text(l10n!.csCameraUnavailable)),
      );
    } catch (e) {
      CrashLogger.append('[Camera] capture failed: $e');
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n!.csPhotoCaptureFailed)),
      );
    }
  }

  Future<void> _pickAndInsertImage(Offset pagePos) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final ext = file.name.split('.').last.toLowerCase();
    if (ext == 'pdf') {
      await _insertPdf(bytes, file.name, pagePos);
    } else {
      _insertImage(bytes, file.name, pagePos);
    }
  }

  void _insertImage(Uint8List bytes, String name, Offset pagePos) {
    final dims = _decodeImageDimensions(bytes);
    double w = dims?.width.toDouble() ?? 300;
    double h = dims?.height.toDouble() ?? 200;
    // Scale to max 300px wide on page
    if (w > 300) {
      final s = 300 / w;
      w *= s;
      h *= s;
    }
    ref.read(canvasProvider.notifier).addImageElement(pagePos, name, bytes, w, h);
  }

  /// Asks the user which pages of the PDF to import. Returns `null` if
  /// the user cancels. When the user picks "Tutte le pagine" both
  /// `start` and `end` come back null so the caller streams the entire
  /// PDF without bound checks.
  Future<_PdfImportRange?> _askPdfImportRange(int estimatedPages) async {
    if (!mounted) return null;
    return showDialog<_PdfImportRange>(
      context: context,
      builder: (ctx) => _PdfRangeDialog(estimatedPages: estimatedPages),
    );
  }

  /// Estimate the number of pages in a PDF from its raw bytes.
  /// Searches for /Type /Page (not /Pages) entries in the byte stream.
  int _countPdfPages(Uint8List bytes) {
    try {
      final str = latin1.decode(bytes, allowInvalid: true);
      return RegExp(r'/Type\s*/Page[^s]').allMatches(str).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _insertPdf(Uint8List bytes, String name, Offset pagePos) async {
    if (!mounted) return;

    // Estimate page count for pre-confirmation
    final estimated = _countPdfPages(bytes);

    // Always offer page-range selection (even for short PDFs) so the user
    // can import just the chunk they care about. The dialog falls back to
    // "all" by default so single-tap imports stay quick.
    final range = await _askPdfImportRange(estimated);
    if (range == null) return;
    // 1-based inclusive bounds; null = unbounded on that side.
    final int? rangeStart = range.start;
    final int? rangeEnd = range.end;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).csPdfRasterizing), duration: const Duration(seconds: 30)),
    );

    // Single PDF engine: pdfrx (PDFium) does BOTH rasterization and embedded
    // text extraction. We deliberately do NOT use printing's `Printing.raster`
    // — it bundles a *second* PDFium and calls FPDF_DestroyLibrary after every
    // raster, which tears the library out from under pdfrx (whose init is
    // one-time) and segfaults. One engine ⇒ one global PDFium state ⇒ no
    // conflict, and the raster + text come from the exact same page geometry.
    final notifier = ref.read(canvasProvider.notifier);
    pdfrx.PdfDocument? doc;
    bool bulkStarted = false;
    try {
      await pdfrx.pdfrxFlutterInitialize();
      doc = await pdfrx.PdfDocument.openData(bytes);

      // Adaptive DPI: big PDFs render at lower resolution so the raw pixel
      // buffers don't blow the iOS jetsam limit. 150 DPI on A4 is ~8.7 MB/page
      // of RGBA; we render → encode → free ONE page at a time to stay bounded.
      final pageCount = doc.pages.length;
      final int dpi = pageCount > 40 ? 100 : (pageCount > 15 ? 120 : 150);

      // Suppress remote pulls for the duration of the import (the per-page
      // awaits yield to the event loop; a pull mid-loop would shift
      // document.pages and misplace insertions).
      notifier.beginBulkOperation();
      bulkStarted = true;
      int processed = 0;

      for (int i = 0; i < pageCount; i++) {
        if (!mounted) return;
        final sourcePageNumber = i + 1; // 1-based, for the range filter
        if (rangeStart != null && sourcePageNumber < rangeStart) continue;
        if (rangeEnd != null && sourcePageNumber > rangeEnd) break;

        final page = doc.pages[i];
        // Render at the displayed (rotation-applied) size in pixels.
        final bool swap = page.rotation.index.isOdd;
        final double dispWpt = swap ? page.height : page.width;
        final double dispHpt = swap ? page.width : page.height;
        final int fullW = (dispWpt * dpi / 72.0).round().clamp(1, 12000);
        final int fullH = (dispHpt * dpi / 72.0).round().clamp(1, 12000);

        final pdfImg = await page.render(
          fullWidth: fullW.toDouble(),
          fullHeight: fullH.toDouble(),
          backgroundColor: 0xFFFFFFFF, // opaque white page
        );
        if (!mounted) {
          pdfImg?.dispose();
          return;
        }
        if (pdfImg == null) continue;
        final int rasterW = pdfImg.width;
        final int rasterH = pdfImg.height;
        // Encode to PNG (lossless, matches the prior import output). The native
        // BGRA buffer + ui.Image are freed before the next page is rendered.
        final assetBytes = await _pdfImageToPng(pdfImg);
        pdfImg.dispose();
        if (!mounted) return;
        if (assetBytes == null) continue;

        if (processed > 0) notifier.addPage();

        // Pin the target page NOW, in the same sync block as the image
        // insert below: the text-layer extraction that follows awaits, and
        // the user can navigate to another page during a long import.
        final st = ref.read(canvasProvider);
        final targetPageFileName = st?.currentPageFileName;
        final pageW = st?.currentPage?.width ?? 595.0;
        final pageH = st?.currentPage?.height ?? 842.0;
        double imgW = rasterW.toDouble();
        double imgH = rasterH.toDouble();
        final scaleToFit = min(pageW / imgW, pageH / imgH);
        imgW *= scaleToFit;
        imgH *= scaleToFit;
        final insertPos = Offset((pageW - imgW) / 2, (pageH - imgH) / 2);
        final assetId = notifier.addImageElement(
          insertPos,
          '${name}_p${processed + 1}.png',
          assetBytes,
          imgW,
          imgH,
          locked: true,
        );

        // Overlay the page's embedded text (selectable + searchable). Same
        // doc/engine as the raster, so the glyph boxes map onto the exact same
        // page geometry. Best-effort per page.
        if (assetId != null && targetPageFileName != null) {
          final layer = await PdfTextExtractor.extractPageLayer(
            doc: doc,
            pageIndex: i,
            sourceAssetPath: assetId,
            placement: PdfImagePlacement(
                offset: insertPos, width: imgW, height: imgH),
          );
          if (!mounted) return;
          if (layer != null) {
            notifier.setPageTextLayer(targetPageFileName, layer);
          }
        }

        processed++;

        // Progress feedback for long imports so the user sees we're alive.
        final rangeTotal = (rangeStart != null && rangeEnd != null)
            ? (rangeEnd - rangeStart + 1)
            : pageCount;
        if (mounted && rangeTotal > 5 && processed % 5 == 0) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context).csPdfImportProgress(processed, rangeTotal)),
              duration: const Duration(seconds: 30),
            ));
        }

        // Yield so the engine can free the page's pixel buffer + PNG bytes
        // before the next allocation — keeps a large PDF import memory-bounded
        // (this is what separates "78 pages imported cleanly" from host OOM).
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      notifier.endBulkOperation();
      // Decode the current page's images now that bulk import is done.
      // During import we skipped decode to keep GPU pressure bounded;
      // the user is on the last imported page and expects to see it
      // populated. Background-pull / thumbnail paths handle the rest.
      notifier.ensureCurrentPageImagesDecoded();

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();

      if (processed == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).csPdfReadFailed)),
        );
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).csPdfImported(processed))),
        );
      }
    } catch (e) {
      if (bulkStarted) notifier.endBulkOperation();
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).csPdfImportError(e.toString()))),
        );
      }
    } finally {
      // Release PDFium's parse of the source PDF. Runs on every exit path
      // (including the `if (!mounted) return` guards inside the loop).
      await doc?.dispose();
    }
  }

  /// Encode a pdfrx-rendered page (BGRA8888) to PNG bytes. Returns null on
  /// failure. The intermediate ui.Image is disposed before returning.
  Future<Uint8List?> _pdfImageToPng(pdfrx.PdfImage img) async {
    try {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        img.pixels,
        img.width,
        img.height,
        ui.PixelFormat.bgra8888,
        completer.complete,
      );
      final uiImage = await completer.future;
      final data = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      uiImage.dispose();
      return data?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[Canvas] PDF page → PNG encode failed: $e');
      return null;
    }
  }

  _Dims? _decodeImageDimensions(Uint8List b) {
    if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50) {
      final w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
      final h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
      return _Dims(w, h);
    }
    if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
      int off = 2;
      while (off < b.length - 9) {
        if (b[off] != 0xFF) break;
        final m = b[off + 1];
        if (m == 0xC0 || m == 0xC2) {
          return _Dims((b[off + 7] << 8) | b[off + 8], (b[off + 5] << 8) | b[off + 6]);
        }
        off += 2 + ((b[off + 2] << 8) | b[off + 3]);
      }
    }
    return null;
  }

  // ── BUILD ──

  @override
  Widget build(BuildContext context) {
    // ── Targeted watch: skip rebuilds during pan/zoom/eraser-cursor ──
    //
    // `state.copyWith(panOffset: x)` and friends fire on every pointer-
    // move event during pan, every wheel event during zoom, and every
    // hover during erase. With a plain `ref.watch(canvasProvider)` each
    // of those events caused a full rebuild of the editor chrome
    // (top bar + bottom strip + floating dock + tool popup) — visibly
    // choppy on a 215-page notebook.
    //
    // Instead we watch a record signature that EXCLUDES the volatile
    // fields. Riverpod's select compares the result with `==`, and a
    // record's `==` is field-wise — when the only change is panOffset,
    // every other field is identical-by-reference (state.copyWith
    // shares unchanged Map/List/object refs), the record compares
    // equal, and the watch is a no-op.
    //
    // The `_buildCanvas` path uses an inner Consumer (or notifier) to
    // pick up the live panOffset/zoom for the painter, so panning
    // still updates the canvas — it just doesn't drag the rest of the
    // UI tree along for the ride.
    ref.watch(canvasProvider.select((s) {
      if (s == null) return null;
      return (
        metadata: s.metadata,
        document: s.document,
        // pages: OMITTED — eraser commits replace the pages Map every
        // 50 ms and the chrome doesn't actually use page CONTENT, only
        // counts (which come from document.pages.length). Letting
        // pages-ref changes rebuild the chrome was the residual stutter
        // on dense ink during eraser drag.
        currentPageIndex: s.currentPageIndex,
        isDirty: s.isDirty,
        toolSettings: s.toolSettings,
        activeChapterId: s.activeChapterId,
        pendingConflicts: s.pendingConflicts,
        pendingRemoteChanges: s.pendingRemoteChanges,
        lassoSelection: s.lassoSelection,
        // activeStroke / lassoPath / shapeStartPos / shapeEndPos OMITTED:
        // these mutate at pointer rate but the chrome doesn't render
        // them (the painter does, via its own Consumer). Including them
        // here forced ~6 extra chrome rebuilds per stroke.
        recognizedShape: s.recognizedShape,
        selectedElementId: s.selectedElementId,
        currentTool: s.currentTool,
        // canUndo / canRedo derived booleans (was: full undoStack/redoStack
        // refs). Lists are replaced on every push/pop, so the chrome
        // rebuilt for every stroke commit just to enable the same icons.
        // Booleans only trip the select on actual empty↔non-empty transitions.
        canUndo: s.undoStack.isNotEmpty,
        canRedo: s.redoStack.isNotEmpty,
        symbolLibraries: s.symbolLibraries,
        // Placement banners ("Tocca per posizionare…"): without these the
        // X button's cancelPendingPaste/clearPendingSymbol changed ONLY
        // this field, the record compared equal, no rebuild — the banner
        // looked un-dismissable. Cheap: they change on copy/duplicate only.
        pendingPaste: s.pendingPaste,
        pendingSymbol: s.pendingSymbol,
        hasClipboard: s.clipboard != null,
      );
    }));
    // After the select-based subscription decides we should rebuild,
    // pull the full state synchronously for the build body's many
    // canvasState.X reads. ref.read does NOT subscribe.
    final canvasState = ref.read(canvasProvider);

    // Mouse mode (draw vs select) — watched so the top-bar toggle reflects
    // and the pointer pipeline sees changes immediately. Changes rarely.
    final mouseDraws =
        ref.watch(appSettingsProvider.select((s) => s.mouseDraws));
    final showPageStrip =
        ref.watch(appSettingsProvider.select((s) => s.showPageStrip));

    // Auto-open conflict resolution when conflicts detected
    ref.listen<int>(
      canvasProvider.select((s) => s?.pendingConflicts.length ?? 0),
      (prev, next) {
        if (next > 0 && (prev == null || prev == 0)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ConflictResolutionScreen(),
                ),
              );
            }
          });
        }
      },
    );

    // Any internal copy/cut (keyboard, context menu, floating bar, single
    // element) OR a cross-notebook clipboard arriving on notebook-open sets
    // `clipboard`. Snapshot the system clipboard's image/text identity as
    // "seen" so a following Ctrl+V / right-click paste prefers THIS fresh
    // in-app copy instead of resurrecting a stale leftover image/text that
    // still sits on the OS clipboard. Previously only the two Ctrl+C branches
    // did this, so cut and every non-keyboard copy pasted old content.
    ref.listen(
      canvasProvider.select((s) => s?.clipboard),
      (prev, next) {
        if (next != null && !identical(prev, next)) {
          unawaited(_markSystemImageSeen());
        }
      },
    );

    if (canvasState == null) {
      return Scaffold(body: Center(child: Text(AppLocalizations.of(context).csNoNotebookOpen)));
    }
    final currentPage = canvasState.currentPage;
    if (currentPage == null) {
      // Two distinct null-currentPage cases:
      //  (A) Notebook has zero pages altogether — rare, show plain message.
      //  (B) The PageEntry exists but its PageData is missing (server lost
      //      the file / partial pull / corruption). Offer recovery actions
      //      so the user isn't trapped — previously the canvas silently
      //      fell back to a different page's content, which hid the bug
      //      entirely ("pagine di 1P inv uguali a Control's prima pagina").
      final doc = canvasState.document;
      final isMissing = doc.pages.isNotEmpty &&
          canvasState.currentPageIndex >= 0 &&
          canvasState.currentPageIndex < doc.pages.length;
      final missingCount = ref
          .read(canvasProvider.notifier)
          .missingPageCount();
      final p = HwThemeScope.of(context);
      return Scaffold(
        appBar: AppBar(
          title: Text(canvasState.metadata.title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _onWillPop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isMissing ? Icons.warning_amber_rounded : Icons.description_outlined,
                  size: 64,
                  color: HwTheme.syncPending,
                ),
                const SizedBox(height: 16),
                Text(
                  isMissing
                      ? AppLocalizations.of(context).csMissingPageDataTitle
                      : AppLocalizations.of(context).csNoPages,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                if (isMissing) ...[
                  const SizedBox(height: 8),
                  Text(
                    missingCount > 1
                        ? AppLocalizations.of(context).csMissingPagesBodyMany(missingCount - 1)
                        : AppLocalizations.of(context).csMissingPageBodyOne,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.ink2),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: Text(AppLocalizations.of(context).csRetrySync),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(AppLocalizations.of(context).csSyncInProgress),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.note_add_outlined),
                        label: Text(AppLocalizations.of(context).csRestoreAsBlankPage),
                        onPressed: () async {
                          final n = ref.read(canvasProvider.notifier);
                          n.repairMissingPageData(canvasState.currentPageIndex);
                          await n.save();
                        },
                      ),
                      if (missingCount > 1)
                        FilledButton.icon(
                          icon: const Icon(Icons.auto_fix_high),
                          label: Text(AppLocalizations.of(context).csRestoreAllMissing(missingCount)),
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final l10n = AppLocalizations.of(context);
                            final n = ref.read(canvasProvider.notifier);
                            final repaired = n.repairAllMissingPages();
                            await n.save();
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                    l10n.csPagesRestoredBlank(repaired)),
                              ),
                            );
                          },
                        ),
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: Text(AppLocalizations.of(context).csDeletePage),
                        onPressed: () {
                          ref.read(canvasProvider.notifier)
                              .deletePage(canvasState.currentPageIndex);
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final palette = HwThemeScope.of(context);
    final notifier = ref.read(canvasProvider.notifier);
    final presetColors = ref.watch(presetColorsProvider);
    final activeColor = Color(canvasState.toolSettings.color);
    final appSettings = ref.watch(appSettingsProvider);
    final toolDock = appSettings.toolDock;
    final dockPosition = _edgePosition(toolDock.edge);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Exit presentation (and its OS-level fullscreen) first — while the
        // window is still fully alive, not mid-teardown. Calling
        // windowManager from dispose() risked touching the native GTK view
        // right as it's being destroyed on close; a second back action
        // actually leaves once we're back to windowed.
        if (_presentationMode) {
          _exitPresentationMode();
          return;
        }
        final navigator = Navigator.of(context);
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) navigator.pop();
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: palette.paper1,
          body: LayoutBuilder(builder: (context, constraints) {
            // Cache the live editor area so the dock drag handlers can
            // compute edge-snap zones and clamp the floating offset.
            _dockArea = constraints.biggest;
            final dockWidget = HwFloatingDock(
              key: _dockKey,
              currentTool: _dockDisplayTool(canvasState, appSettings.mouseDraws),
              activeInkColor: activeColor,
              lastEraserMode: notifier.lastEraserMode,
              shapeGuess: canvasState.toolSettings.shapeRecognition,
              onShapeGuessChanged: (v) {
                notifier.setToolSettings(
                    canvasState.toolSettings.copyWith(shapeRecognition: v));
              },
              onToolChanged: (t) {
                _pickTool(t);
                // Switching tool never auto-opens the popup — the user
                // explicitly asks for it by tapping the active tool again.
                if (_popupOpen) setState(() => _popupOpen = false);
              },
              onActiveTap: () => setState(() => _popupOpen = !_popupOpen),
              position: dockPosition,
              dragging: _dockDragOffset != null,
              onDragStart: _onDockDragStart,
              onDragUpdate: _onDockDragUpdate,
              onDragEnd: _onDockDragEnd,
            );
            return Stack(
              key: _stackKey,
              children: [
              Column(
                children: [
                  if (!_presentationMode)
                  ValueListenableBuilder<bool>(
                    valueListenable: notifier.hasSyncFailure,
                    builder: (_, syncFailing, __) {
                      // Honest state: conflict > offline > pending > ok.
                      // The previous binary "isDirty ? pending : ok" hid
                      // 20-minute Tailscale flaps under the green cloud.
                      final HwSyncState syncState;
                      if (canvasState.pendingConflicts.isNotEmpty) {
                        syncState = HwSyncState.conflict;
                      } else if (syncFailing) {
                        syncState = HwSyncState.offline;
                      } else if (canvasState.isDirty) {
                        syncState = HwSyncState.pending;
                      } else {
                        syncState = HwSyncState.ok;
                      }
                      return HwEditorTopBar(
                    notebookTitle: canvasState.metadata.title,
                    coverColor: Color(canvasState.metadata.coverColor),
                    currentPage: canvasState.currentPageIndex + 1,
                    totalPages: canvasState.document.pages.length,
                    dirty: canvasState.isDirty,
                    canUndo: notifier.canUndo,
                    canRedo: notifier.canRedo,
                    syncState: syncState,
                    onBack: () async {
                      await _onWillPop();
                    },
                    onUndo: () => notifier.undo(),
                    onRedo: () => notifier.redo(),
                    // Scratch notebooks get the pages/chapters UI too: a
                    // OneNote import (or the user) can have many infinite
                    // sheets organised in chapters — without this button
                    // every page beyond the first was unreachable.
                    showPages: true,
                    onPagesTap: () => _showPageManager(canvasState),
                    onAddPage: () =>
                        ref.read(canvasProvider.notifier).addPage(),
                    onSymbolsTap: () =>
                        _showSymbolsDialog(_visibleCenterPagePos(canvasState)),
                    onExportTap: () => _showExportSheet(),
                    onMoreTap: () => _showMoreSheet(canvasState),
                    mouseDraws: mouseDraws,
                    // No mouse ever shows up on a touch-only phone/tablet —
                    // swap the mouse toggle for a finger-draws-vs-pans one
                    // instead of showing a control that does nothing there.
                    onToggleMouseMode: _isMobilePlatform
                        ? null
                        : () => ref
                            .read(appSettingsProvider.notifier)
                            .setMouseDraws(!mouseDraws),
                    touchDraws: !_effectiveStylusOnly(),
                    onToggleTouchDraws: _isMobilePlatform
                        ? () => ref
                            .read(appSettingsProvider.notifier)
                            .setStylusOnlyDrawing(!_effectiveStylusOnly())
                        : null,
                      );
                    },
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        if (_popupOpen) setState(() => _popupOpen = false);
                      },
                      child: _buildCanvas(canvasState, currentPage),
                    ),
                  ),
                  if (_presentationMode || canvasState.isScratch)
                    // Infinite scratch canvas, or presentation mode: no
                    // page strip chrome at all.
                    const SizedBox.shrink()
                  else if (showPageStrip)
                    HwBottomPageStrip(
                      chapterLabel: _currentChapterLabel(canvasState),
                      // Only show pages of the active chapter (or all when
                      // no chapter filter is active).
                      pageNumbers: [
                        for (final i in canvasState.filteredPageIndices) i + 1,
                      ],
                      currentPage: canvasState.currentPageIndex + 1,
                      previousPage: (() {
                        final prev = canvasState.previousPageIndex;
                        if (prev == null) return null;
                        if (prev < 0 ||
                            prev >= canvasState.document.pages.length) {
                          return null;
                        }
                        return prev + 1;
                      })(),
                      onPageTap: (n) => notifier.goToPage(n - 1),
                      onPageSecondary: (n, pos) =>
                          _showPageStripContextMenu(n, pos),
                      onAllPagesTap: () => _showPageManager(canvasState),
                      onCollapse: () => ref
                          .read(appSettingsProvider.notifier)
                          .setShowPageStrip(false),
                    )
                  else
                    HwPageStripHandle(
                      onExpand: () => ref
                          .read(appSettingsProvider.notifier)
                          .setShowPageStrip(true),
                    ),
                ],
              ),
              // Movable tool dock — drag the grip to park it on any edge.
              // While dragging it follows the finger at a free offset;
              // otherwise it sits docked against its persisted edge. Hidden
              // entirely in presentation mode (see [_enterPresentationMode]).
              if (_presentationMode)
                const SizedBox.shrink()
              else if (_dockDragOffset != null)
                Positioned(
                  left: _dockDragOffset!.dx,
                  top: _dockDragOffset!.dy,
                  child: dockWidget,
                )
              else
                _dockedPositioned(dockPosition, toolDock.align, dockWidget),
              if (_presentationMode) ..._presentationOverlay(canvasState),
              // Tool option popup — anchored next to the dock wherever it
              // is parked (above for bottom, below for top, beside for
              // left/right).
              if (_popupOpen && !_presentationMode)
                _popupPositioned(
                  dockPosition,
                  toolDock.align,
                  _dockArea,
                  // Absorb taps so a near-miss on the small color chips
                  // (or any empty spot inside the panel) doesn't fall
                  // through to the canvas "tap closes popup" handler —
                  // which made colors seem unselectable and the panel
                  // close on the user.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: HwToolPopup(
                      tool: canvasState.currentTool,
                      color: activeColor,
                      onColorChanged: (c) {
                        notifier.setToolSettings(canvasState.toolSettings
                            .copyWith(color: c.toARGB32()));
                      },
                      onPresetColorEdited: (index, c) {
                        ref
                            .read(presetColorsProvider.notifier)
                            .setColor(index, c.toARGB32());
                      },
                      thickness: canvasState.toolSettings.strokeWidth,
                      onThicknessChanged: (v) {
                        notifier.setToolSettings(canvasState.toolSettings
                            .copyWith(strokeWidth: v));
                      },
                      presetColors: presetColors
                          .map((c) => Color(c))
                          .toList(),
                      eraserSize: canvasState.toolSettings.eraserSize,
                      onEraserSizeChanged: (s) {
                        notifier.setToolSettings(
                            canvasState.toolSettings.copyWith(eraserSize: s));
                      },
                      eraserPerStroke:
                          canvasState.currentTool == CanvasTool.eraserStroke,
                      onEraserPerStrokeChanged: (perStroke) {
                        notifier.setTool(perStroke
                            ? CanvasTool.eraserStroke
                            : CanvasTool.eraserStandard);
                      },
                      // Each ink tool keeps its own independent 3 slots —
                      // presetsFor(currentTool) so pen/highlighter/etc.
                      // never see (or delete) each other's presets.
                      penPresets: ref
                          .watch(appSettingsProvider)
                          .presetsFor(canvasState.currentTool),
                      onApplyPreset: (slot) {
                        final preset = ref
                            .read(appSettingsProvider)
                            .presetsFor(canvasState.currentTool)[slot];
                        if (preset == null) return;
                        notifier.applyPenPreset(preset);
                        // Dismiss the popup so the canvas is unobstructed
                        // — picking a preset is a committed choice, the
                        // user doesn't need to keep the panel open to
                        // tweak further.
                        if (_popupOpen) setState(() => _popupOpen = false);
                      },
                      onSavePreset: (slot) {
                        final s = canvasState;
                        ref.read(appSettingsProvider.notifier).savePenPreset(
                              s.currentTool,
                              slot,
                              PenPreset(
                                tool: s.currentTool,
                                color: s.toolSettings.color,
                                strokeWidth: s.toolSettings.strokeWidth,
                                opacity: s.toolSettings.opacity,
                              ),
                            );
                      },
                      onClearPreset: (slot) {
                        ref
                            .read(appSettingsProvider.notifier)
                            .clearPenPreset(canvasState.currentTool, slot);
                      },
                      onClose: () => setState(() => _popupOpen = false),
                    ),
                  ),
                ),
              const RemoteChangesBanner(),
              // Scratch mode: floating "torna al contenuto" pill, shown only
              // when the user has panned/zoomed the content fully off-screen.
              // Own Consumer with a FULL provider watch: the enclosing build
              // deliberately select()s AWAY pan/zoom (whole-screen rebuilds
              // per pan frame would be too costly), so the pill must track
              // them itself — otherwise its visibility only refreshed when
              // something else (e.g. a dock tap) happened to rebuild.
              Consumer(builder: (context, ref, _) {
                final live = ref.watch(canvasProvider);
                if (live == null || !_showBackToContent(live)) {
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
                        onTap: () =>
                            ref.read(canvasProvider.notifier).fitToContent(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const HwIcon('fit', size: 15,
                                  color: Colors.white),
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
              }),
              // Subtle "Sincronizzazione…" pill while a remote pull is in
              // flight — lets the user know the notebook may update shortly
              // so they don't think the app glitched.
              Positioned(
                top: 64,
                right: 12,
                child: ValueListenableBuilder<bool>(
                  valueListenable:
                      ref.read(canvasProvider.notifier).isPullingFromRemote,
                  builder: (_, pulling, __) => AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: pulling ? 1.0 : 0.0,
                    // Only MOUNT the spinner while actually pulling. An
                    // indeterminate CircularProgressIndicator (value: null)
                    // runs a Ticker every vsync for as long as it's in the
                    // tree — and AnimatedOpacity keeps its child mounted even
                    // at opacity 0. So the hidden sync spinner pegged the
                    // editor at ~60 fps / 50-99% CPU the ENTIRE time, even
                    // when no sync was running. Swapping in an empty box when
                    // idle stops the ticker and drops idle CPU to ~0.
                    child: !pulling
                        ? const SizedBox.shrink()
                        : IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: HwTheme.alphaScrim),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ValueListenableBuilder<({int done, int total})>(
                          valueListenable: ref
                              .read(canvasProvider.notifier)
                              .pullProgress,
                          builder: (_, progress, __) {
                            final label = progress.total > 0
                                ? AppLocalizations.of(context).csSyncProgressCount(progress.done, progress.total)
                                : AppLocalizations.of(context).csSyncing;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    value: progress.total > 0
                                        ? progress.done / progress.total
                                        : null,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  label,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
        ),
      ),
    );
  }

  Widget _buildCanvas(CanvasState canvasState, PageData currentPage) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final p = HwThemeScope.of(context);
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        _lastCanvasSize = canvasSize;
        ref.read(canvasProvider.notifier).setViewportSize(canvasSize);

        // Tool default cursor (used by the pen / non-mouse devices). The mouse
        // overrides this device-aware in onPointerHover (selection arrow /
        // I-beam) so the PEN keeps the drawing crosshair.
        MouseCursor cursor = SystemMouseCursors.precise;
        if (canvasState.currentTool == CanvasTool.pan) cursor = SystemMouseCursors.grab;
        if (canvasState.currentTool == CanvasTool.image) cursor = SystemMouseCursors.click;

        return ValueListenableBuilder<MouseCursor?>(
          valueListenable: _mouseHoverCursor,
          builder: (context, hoverCursor, child) => MouseRegion(
            // Mouse override (selection arrow / I-beam) when set; otherwise the
            // tool default so the pen keeps its drawing crosshair.
            cursor: hoverCursor ?? cursor,
            child: child,
          ),
          child: Stack(
            key: _canvasStackKey,
            children: [
              // Canvas painter
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    // ── Live-state read (was the phantom-line bug) ──
                    // `canvasState` from the build closure is intentionally
                    // STALE on pan/zoom/pages — the chrome's select excludes
                    // those fields. _toPageCoords reads state.panOffset and
                    // state.zoom, so feeding it the stale state turned the
                    // very first point of a new stroke into the wrong page
                    // coordinate (it lived in the OLD pan/zoom frame). The
                    // next pointer-move could land in the right frame and
                    // the user saw the new stroke "stretch" from a phantom
                    // start to the real one. Same fix as onPointerSignal
                    // below — always pull live state.
                    final live = ref.read(canvasProvider) ?? canvasState;
                    if (e.kind == PointerDeviceKind.mouse && e.buttons == kSecondaryMouseButton) {
                      if (live.pendingSymbol != null) {
                        ref.read(canvasProvider.notifier).clearPendingSymbol();
                        return;
                      }
                      _showContextMenu(e.position, e.localPosition, live, canvasSize);
                      return;
                    }
                    _onPointerDown(e, live, canvasSize);
                  },
                  onPointerMove: (e) {
                    final live = ref.read(canvasProvider) ?? canvasState;
                    _onPointerMove(e, live, canvasSize);
                  },
                  onPointerHover: (e) {
                    _lastPointerWasMouse = e.kind == PointerDeviceKind.mouse;
                    // Pen/stylus (or no state) → tool default cursor (crosshair).
                    final live = ref.read(canvasProvider);
                    if (e.kind != PointerDeviceKind.mouse || live == null) {
                      if (_mouseHoverCursor.value != null) {
                        _mouseHoverCursor.value = null;
                      }
                      return;
                    }
                    // Mouse over an ink tool = selection device: arrow normally,
                    // I-beam over selectable PDF text. Other tools keep their
                    // default cursor (override = null). When the user opted the
                    // mouse into drawing, keep the drawing crosshair.
                    MouseCursor? c;
                    if (!ref.read(appSettingsProvider).mouseDraws &&
                        _mouseSelectTools.contains(live.currentTool)) {
                      final sel = _ensurePdfTextSel(live);
                      final overText = sel != null &&
                          !sel.isEmpty &&
                          sel.isOverText(_toPageCoords(
                              e.localPosition, live, canvasSize));
                      c = overText
                          ? SystemMouseCursors.text
                          : SystemMouseCursors.basic;
                    }
                    if (_mouseHoverCursor.value != c) _mouseHoverCursor.value = c;
                  },
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  onPointerSignal: (event) {
                    // Read live state — `canvasState` from the build
                    // closure is intentionally STALE on pan/zoom/cursor
                    // because the parent's select excludes those fields,
                    // so using it here would feed back the OLD zoom/pan
                    // into every wheel calculation and snap the canvas
                    // back to the centre. ref.read returns current.
                    final live = ref.read(canvasProvider);
                    if (live == null) return;
                    if (event is PointerScrollEvent) {
                      // Trackpad two-finger scroll = scroll the document.
                      // Most platforms deliver it as a pan-zoom gesture
                      // (handled in _onScaleUpdate), but when the engine
                      // reports it as a scroll event instead, kind is
                      // trackpad — pan here rather than zooming, which is
                      // reserved for the mouse wheel.
                      if (event.kind == PointerDeviceKind.trackpad) {
                        ref
                            .read(canvasProvider.notifier)
                            .setPanOffset(live.panOffset - event.scrollDelta);
                        return;
                      }
                      final oldZoom = live.zoom;
                      final zoomDelta = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
                      final newZoom = (oldZoom * zoomDelta).clamp(0.3, 5.0);
                      final cursorPos = event.localPosition;
                      final newPan = live.panOffset +
                          (cursorPos - live.panOffset) * (1 - (newZoom / oldZoom));
                      ref
                          .read(canvasProvider.notifier)
                          .setZoomAndPan(newZoom, newPan);
                    } else if (event is PointerScaleEvent) {
                      // Trackpad pinch-to-zoom (may not fire on all platforms)
                      final oldZoom = live.zoom;
                      final newZoom = (oldZoom * event.scale).clamp(0.3, 5.0);
                      final cursorPos = event.localPosition;
                      final newPan = live.panOffset +
                          (cursorPos - live.panOffset) * (1 - (newZoom / oldZoom));
                      ref
                          .read(canvasProvider.notifier)
                          .setZoomAndPan(newZoom, newPan);
                    }
                  },
                  child: GestureDetector(
                    // ── Stroke-break fix ──
                    //
                    // Restrict the inner ScaleGestureRecognizer (and DoubleTap)
                    // to non-stylus pointers. With stylus included, the
                    // recognizer joins Flutter's gesture arena for every pen
                    // pointer; once the cumulative pen movement exceeds the
                    // pan slop (~36 logical px for stylus), the recognizer
                    // resolves `accepted` even with a single pointer, which
                    // sends `PointerCancel(stylus)` to the surrounding
                    // Listener. _onPointerCancel then tears down the active
                    // stroke mid-letter — the user perceives this as the pen
                    // suddenly "lifting" and a new stroke starting at the
                    // same place ("stroke break mid-pen-down" on iPad).
                    //
                    // Pinch-to-zoom on iPad still works (touch+touch), and
                    // trackpad pinch on desktop still works (trackpad). The
                    // _onScale* callbacks already early-return on `_stylusDown`
                    // for safety, but that guard only suppresses the callback
                    // body — not the arena claim. supportedDevices is the
                    // only way to keep the pen out of the arena entirely.
                    // Exclude `mouse` from supportedDevices: middle-
                    // mouse pan is handled directly by the outer
                    // Listener, and including mouse here put every
                    // PointerMoveEvent into the gesture arena. The
                    // ScaleGestureRecognizer holds the move events
                    // until the arena resolves (5–50 ms variable
                    // latency), turning continuous panning into
                    // bursty 6-11 ev/s — the "scattante" the user
                    // reported even with cache hits at 100 %.
                    supportedDevices: const {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.trackpad,
                    },
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    // Double-tap toggles zoom-to-fit <-> default 2.0x zoom.
                    // Only fires for non-drawing tools so a user can't
                    // accidentally zoom while sketching fast.
                    onDoubleTap: (canvasState.currentTool == CanvasTool.pan ||
                            canvasState.currentTool == CanvasTool.image)
                        ? () {
                            // Toggle: if already near fit-zoom, go back to 2.0
                            // default; otherwise fit the full page.
                            final notifier = ref.read(canvasProvider.notifier);
                            if (canvasState.zoom < 1.4) {
                              notifier.resetZoom();
                            } else {
                              notifier.zoomToFit();
                            }
                          }
                        : null,
                    child: ClipRect(
                      child: RepaintBoundary(
                        // ── Inner viewport watch ──
                        // The parent build's `ref.watch` deliberately
                        // EXCLUDES panOffset/zoom so pan/wheel events don't
                        // rebuild the editor chrome. But the painter still
                        // needs them — wrap CustomPaint in a Consumer that
                        // watches just `(zoom, panOffset)` so panning
                        // rebuilds only this CustomPaint subtree (a
                        // ~1-widget tree), and the rest of the UI is
                        // untouched.
                        child: Consumer(
                          builder: (context, ref, _) {
                            // Watch viewport + imageCache + pages so the
                            // painter rebuilds on pan/zoom, when a new
                            // asset image is decoded, AND when the eraser
                            // / draw / undo commits a new pages map. The
                            // chrome's parent select excludes ALL of
                            // those (they tick at 20-120 Hz during
                            // interaction), so this Consumer is the
                            // *only* widget that rebuilds for those
                            // changes.
                            ref.watch(canvasProvider.select((s) =>
                                s == null
                                    ? const (zoom: 1.0, panOffset: Offset.zero)
                                    : (zoom: s.zoom, panOffset: s.panOffset)));
                            // imageCache is observed via the painter's
                            // repaintNotifier (which now includes the
                            // notifier's `imageCacheVersion`) — pulling
                            // it through Riverpod here used to fire a
                            // full state-cascade and shouldRepaint walk
                            // on every PDF-import decode.
                            ref.watch(canvasProvider.select(
                                (s) => s?.pages));
                            // Read full state fresh — the parent's
                            // canvasState (closure) has stale fields
                            // because parent didn't rebuild for any of
                            // the above. Use `s.currentPage` (computed
                            // from the live `pages` map) as the painter's
                            // pageData; falling back to the parent's
                            // captured `currentPage` only for the very
                            // first paint when ref.read returns null.
                            final s = ref.read(canvasProvider) ?? canvasState;
                            final livePage = s.currentPage ?? currentPage;
                            return CustomPaint(
                              painter: CanvasRenderEngine(
                                pageData: livePage,
                                // Pass nothing as the snapshot — the painter
                                // resolves the active stroke via the getter
                                // every frame so a captured snapshot can
                                // never go stale between widget rebuilds.
                                activeStroke: null,
                                activeStrokeGetter: () {
                                  // Notifier always wins when it has points
                                  // (live drawing). Fall back to Riverpod's
                                  // activeStroke (carries the very first
                                  // point committed via startStroke before
                                  // the first PointerMove). Either may be
                                  // null between strokes.
                                  if (_activeStrokeNotifier.points.isNotEmpty) {
                                    return _activeStrokeNotifier.points;
                                  }
                                  final liveS = ref.read(canvasProvider);
                                  final stroke = liveS?.activeStroke;
                                  if (stroke != null && stroke.isNotEmpty) {
                                    return stroke;
                                  }
                                  return null;
                                },
                                activeToolType: _toolTypeString(s.currentTool),
                                activeColor: s.toolSettings.color,
                                activeWidth: s.toolSettings.strokeWidth,
                                lassoSelection: s.lassoSelection,
                                // Live transform during drag/rotate/scale —
                                // bypasses Riverpod so the page repaints
                                // without rebuilding the widget tree.
                                // ALWAYS pass the callback (it returns
                                // null when no gesture is in flight) —
                                // otherwise the CustomPaint, captured
                                // before _lassoTransformNotifier.begin()
                                // ran, would have a null callback for
                                // the entire gesture and the painter
                                // would fall back to stale Riverpod
                                // state.
                                liveLassoTransform: () =>
                                    _lassoTransformNotifier.isActive
                                        ? _lassoTransformNotifier.snapshot()
                                        : null,
                                liveElementTransform: () => _elementTransformNotifier.isActive
                                    ? (
                                          elementId: _elementTransformNotifier.elementId!,
                                          dragOffset: _elementTransformNotifier.dragOffset,
                                          rotationDelta: _elementTransformNotifier.rotationDelta,
                                          scaleW: _elementTransformNotifier.scaleW,
                                          scaleH: _elementTransformNotifier.scaleH,
                                        )
                                    : null,
                                lassoPath: _lassoPathNotifier.isActive && _lassoPathNotifier.points.isNotEmpty
                                    ? _lassoPathNotifier.points
                                    : (s.lassoPath.isNotEmpty ? s.lassoPath : null),
                                // ALWAYS pass the getter (returns the
                                // notifier's points, which is empty when no
                                // lasso is in flight) — same reasoning as
                                // liveLassoTransform above. If we gated it
                                // on isActive, the painter captured before
                                // the user starts a fresh lasso (e.g. just
                                // after switching from pen→lasso) held a
                                // null getter and fell back to the stale
                                // `lassoPath` field — also null at that
                                // moment because s.lassoPath is empty —
                                // so the marquee stayed invisible until
                                // some later state change rebuilt the
                                // CustomPaint with the getter wired up.
                                lassoPathGetter: () => _lassoPathNotifier.points,
                                laserTrailGetter: () =>
                                    _laserStrokeNotifier.points,
                                shapePreview: (s.shapeStartPos != null && s.shapeEndPos != null)
                                    ? (s.shapeStartPos!, s.shapeEndPos!, s.toolSettings.shapeType)
                                    : null,
                                recognizedShapePreview: s.recognizedShape,
                                zoom: s.zoom,
                                panOffset: s.panOffset,
                                infiniteCanvas: s.isScratch,
                                imageCache: s.imageCache,
                                // This Consumer intentionally doesn't watch
                                // s.imageCache (avoids a per-decode rebuild
                                // cascade on PDF imports), so when a freshly
                                // decoded image lands the widget tree stays
                                // put. The painter's repaintNotifier still
                                // fires `paint()`, but with the snapshot
                                // captured at the last build → the new image
                                // was invisible until the user panned/zoomed.
                                // This getter lets the painter read the LIVE
                                // map on every frame, so a decoded image
                                // appears immediately on the next repaint.
                                liveImageCacheGetter: () =>
                                    ref.read(canvasProvider)?.imageCache ??
                                    const {},
                                corruptAssetIds:
                                    ref.read(canvasProvider.notifier).corruptAssetIds,
                                // Typeset-math raster cache — same live-read +
                                // miss-then-async-fill pattern as images. A
                                // FIXED pixel ratio (not × zoom) keeps the
                                // cache key stable across zoom so equations
                                // don't re-rasterize on every pinch; the
                                // bitmap scales like an image instead.
                                mathCache:
                                    ref.read(canvasProvider.notifier).mathCache,
                                liveMathCacheGetter: () => ref
                                    .read(canvasProvider.notifier)
                                    .mathCache,
                                failedMathKeys: ref
                                    .read(canvasProvider.notifier)
                                    .failedMathKeys,
                                mathPixelRatio: _mathPixelRatio(context),
                                onMathCacheMiss: (d) => ref
                                    .read(canvasProvider.notifier)
                                    .requestMathRaster(d.latex, d.color,
                                        d.fontSize, d.displayMode,
                                        _mathPixelRatio(context)),
                                repaintNotifier: _repaintNotifier,
                              ),
                              // willChange: true tells Skia "do NOT
                              // bother rasterizing this layer to a
                              // GPU texture cache between frames" —
                              // ESSENTIAL during pan. With
                              // willChange:false + shouldRepaint=true
                              // (panOffset changes every frame),
                              // Flutter would create+invalidate the
                              // texture cache on every paint, paying
                              // GPU upload cost for nothing. Our
                              // own ui.Picture cache (in render_engine)
                              // already memoises the drawing commands
                              // at the right granularity (per
                              // pageData/zoom-bucket) — Skia's
                              // post-transform raster cache is
                              // counterproductive on a panning canvas.
                              // isComplex:true was hinting Skia to
                              // cache, which doubled down on the same
                              // mistake — also removed.
                              willChange: true,
                              size: canvasSize,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Eraser cursor — wrapped via Positioned.fill + inner
              // Stack so the cursor's `Positioned` (returned by
              // `_buildEraserCursor`) sits directly under a Stack
              // ancestor as required (ParentDataWidget invariant).
              // Without the inner Stack, putting a Positioned inside a
              // bare Consumer breaks the outer Stack's layout and the
              // entire canvas subtree fails to render.
              //
              // The Consumer watches just (currentTool, eraserCursorPos)
              // — the parent's record select intentionally omits
              // eraserCursorPos (would force a chrome rebuild at
              // pointer rate). Without this Consumer the cursor stays
              // frozen and "teleports" only when something else
              // triggers a parent rebuild.
              Positioned.fill(
                child: IgnorePointer(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final eraserState =
                          ref.watch(canvasProvider.select((s) =>
                              s == null
                                  ? null
                                  : (
                                      tool: s.currentTool,
                                      pos: s.eraserCursorPos,
                                    )));
                      if (eraserState == null ||
                          !_isEraserTool(eraserState.tool) ||
                          eraserState.pos == null) {
                        return const SizedBox.shrink();
                      }
                      final fullState = ref.read(canvasProvider);
                      if (fullState == null) {
                        return const SizedBox.shrink();
                      }
                      return Stack(
                        children: [
                          _buildEraserCursor(fullState, canvasSize),
                        ],
                      );
                    },
                  ),
                ),
              ),

              // Transform handles for selected elements + lasso handles.
              // Wrapped in a Consumer that watches (zoom, panOffset) so
              // the handles re-anchor as the viewport pans/zooms — the
              // chrome's parent select EXCLUDES those fields (perf), so
              // without this Consumer the handles would freeze in their
              // build-time screen positions during a pan and only catch
              // up when something else triggered a parent rebuild ("the
              // dashed border stays put but the corner circles move in
              // jumps"). _elementTransformNotifier handles the
              // drag/rotate/resize live values via its own listenable.
              Positioned.fill(
                child: Consumer(
                  builder: (_, ref2, __) {
                    // `pages` is in the selector so the overlay rebuilds
                    // when an element's geometry changes. Without it, the
                    // captured `live` stayed stale after a resize commit:
                    // _commitElementTransform called notifier.end() (which
                    // fires the inner ListenableBuilder) BEFORE
                    // resizeElement/moveElement updated Riverpod, and the
                    // outer Consumer didn't rebuild because (zoom,
                    // panOffset) hadn't changed — bbox + handles stayed
                    // at the pre-resize size for several seconds until
                    // some unrelated event triggered a rebuild.
                    ref2.watch(canvasProvider.select((s) => (
                          zoom: s?.zoom ?? 1.0,
                          panOffset: s?.panOffset ?? Offset.zero,
                          pages: s?.pages,
                        )));
                    final live = ref2.read(canvasProvider) ?? canvasState;
                    return ListenableBuilder(
                      listenable: _elementTransformNotifier,
                      builder: (_, __) => Stack(
                        children: _buildTransformHandles(live, canvasSize),
                      ),
                    );
                  },
                ),
              ),
              Positioned.fill(
                child: Consumer(
                  builder: (_, ref2, __) {
                    // Same stale-`live` fix as the element-transform
                    // Consumer above: include `pages` so a lasso commit
                    // (selection move/scale/rotate) refreshes the captured
                    // state and the lasso handles re-anchor correctly.
                    ref2.watch(canvasProvider.select((s) => (
                          zoom: s?.zoom ?? 1.0,
                          panOffset: s?.panOffset ?? Offset.zero,
                          pages: s?.pages,
                        )));
                    final live = ref2.read(canvasProvider) ?? canvasState;
                    return ListenableBuilder(
                      listenable: _lassoTransformNotifier,
                      builder: (_, __) => Stack(
                        children: [
                          ..._buildLassoHandles(live, canvasSize),
                          if (live.lassoSelection != null)
                            _buildFloatingSelectionActions(live, canvasSize),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // PDF text-selection highlight + copy affordance. Re-projects on
              // zoom/pan/page change, repaints on selection change.
              Positioned.fill(
                child: Consumer(
                  builder: (_, ref2, __) {
                    ref2.watch(canvasProvider.select((s) => (
                          zoom: s?.zoom ?? 1.0,
                          panOffset: s?.panOffset ?? Offset.zero,
                          pages: s?.pages,
                        )));
                    final live = ref2.read(canvasProvider) ?? canvasState;
                    // Device-aware: the overlay (highlight + copy button) shows
                    // whenever the current page has an extracted text layer; it
                    // draws nothing until a selection exists. No tool gating.
                    final sel = _ensurePdfTextSel(live);
                    if (sel == null) return const SizedBox.shrink();
                    return _buildPdfTextSelectionLayer(sel, live, canvasSize);
                  },
                ),
              ),

              // Recognized shape adjustment indicator (only for shape tool adjustment mode)
              if (canvasState.isAdjustingRecognized && canvasState.recognizedShape != null)
                Positioned(
                  bottom: 16,
                  left: 0, right: 0,
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
                            AppLocalizations.of(context).csShapeRecognizedLabel(_shapeTypeLabel(canvasState.recognizedShape!.shapeType)),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 12),
                          Semantics(
                            button: true,
                            label: AppLocalizations.of(context).csConfirmShapeSemantics,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                ref.read(canvasProvider.notifier).commitRecognizedShape();
                              },
                              child: Container(
                                // Slightly larger tap area for fingers — the
                                // original padding gave a 26-px-tall target.
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(AppLocalizations.of(context).csConfirm, style: const TextStyle(color: Colors.white, fontSize: 11)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Semantics(
                            button: true,
                            label: AppLocalizations.of(context).csCancelShapeSemantics,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => ref.read(canvasProvider.notifier).dismissRecognizedShape(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(AppLocalizations.of(context).csCancel, style: const TextStyle(color: Colors.white, fontSize: 11)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Pending symbol placement hint
              if (canvasState.pendingSymbol != null)
                Positioned(
                  top: 16,
                  left: 0, right: 0,
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
                            AppLocalizations.of(context).csTapToPlaceSymbol(canvasState.pendingSymbol!.name),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 8),
                          Semantics(
                            button: true,
                            label: AppLocalizations.of(context).csCancelSymbolInsertSemantics,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => ref.read(canvasProvider.notifier).clearPendingSymbol(),
                              child: const Padding(
                                // 12px on every side gives a 40-px hit area
                                // around the 16-px icon — close to Material's
                                // 48-px recommendation without bloating the
                                // pill's height.
                                padding: EdgeInsets.all(12),
                                child: Icon(Icons.close, color: Colors.white70, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Pending paste placement hint (duplicate / paste)
              if (canvasState.pendingPaste && canvasState.clipboard != null)
                Positioned(
                  top: 16,
                  left: 0, right: 0,
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
                            AppLocalizations.of(context).csTapToPlaceCopy,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 8),
                          Semantics(
                            button: true,
                            label: AppLocalizations.of(context).csCancelPasteSemantics,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => ref.read(canvasProvider.notifier).cancelPendingPaste(),
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
                ),

              // New page drag-left hint
              if (_showNewPageHint)
                Positioned(
                  right: 0,
                  top: 0, bottom: 0,
                  width: 120,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [HwTheme.syncOk.withValues(alpha: 0.85), HwTheme.syncOk.withValues(alpha: 0.0)],
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_circle_outline, color: Colors.white, size: 36),
                          const SizedBox(height: 4),
                          Text(AppLocalizations.of(context).csNewPage, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),

              // Next page drag-left hint (when not last page)
              if (_showNextPageHint)
                Builder(builder: (ctx) {
                  final filtered = canvasState.filteredPageIndices;
                  final curIdx = filtered.indexOf(canvasState.currentPageIndex);
                  PageData? nextPage;
                  if (curIdx >= 0 && curIdx + 1 < filtered.length) {
                    final nextDocIdx = filtered[curIdx + 1];
                    final nextEntry = canvasState.document.pages[nextDocIdx];
                    nextPage = canvasState.pages[nextEntry.fileName];
                  }
                  return Positioned(
                    right: 0,
                    top: 0, bottom: 0,
                    width: MediaQuery.of(context).size.width * 0.35,
                    child: Container(
                      decoration: BoxDecoration(
                        color: p.paper2,
                        border: Border(left: BorderSide(color: p.paperEdge, width: 1)),
                        boxShadow: hwShadow2(p.brightness),
                      ),
                      child: nextPage != null
                          ? CustomPaint(
                              painter: CanvasRenderEngine(
                                pageData: nextPage,
                                zoom: 1.0,
                                panOffset: Offset.zero,
                                imageCache: canvasState.imageCache,
                              ),
                              size: Size.infinite,
                            )
                          : Center(child: Icon(Icons.arrow_forward_rounded, color: p.paperEdge, size: 40)),
                    ),
                  );
                }),

              // Previous page drag-right hint
              if (_showPrevPageHint)
                Builder(builder: (ctx) {
                  final filtered = canvasState.filteredPageIndices;
                  final curIdx = filtered.indexOf(canvasState.currentPageIndex);
                  PageData? prevPage;
                  if (curIdx > 0) {
                    final prevDocIdx = filtered[curIdx - 1];
                    final prevEntry = canvasState.document.pages[prevDocIdx];
                    prevPage = canvasState.pages[prevEntry.fileName];
                  }
                  return Positioned(
                    left: 0,
                    top: 0, bottom: 0,
                    width: MediaQuery.of(context).size.width * 0.35,
                    child: Container(
                      decoration: BoxDecoration(
                        color: p.paper2,
                        border: Border(right: BorderSide(color: p.paperEdge, width: 1)),
                        boxShadow: hwShadow2(p.brightness),
                      ),
                      child: prevPage != null
                          ? CustomPaint(
                              painter: CanvasRenderEngine(
                                pageData: prevPage,
                                zoom: 1.0,
                                panOffset: Offset.zero,
                                imageCache: canvasState.imageCache,
                              ),
                              size: Size.infinite,
                            )
                          : Center(child: Icon(Icons.arrow_back_rounded, color: p.paperEdge, size: 40)),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  bool _isEraserTool(CanvasTool tool) =>
      tool == CanvasTool.eraserStandard || tool == CanvasTool.eraserStroke;

  Widget _buildEraserCursor(CanvasState state, Size canvasSize) {
    final p = HwThemeScope.of(context);
    final pos = _toScreenCoords(state.eraserCursorPos!, state, canvasSize);
    // Radius is in page units (see _eraseAt): screen size needs the same
    // renderScale × zoom factor _toScreenCoords applies to the position.
    final r = eraserSizeToRadius(state.toolSettings.eraserSize) *
        _getRenderScale(state, canvasSize) *
        state.zoom;
    return Positioned(
      left: pos.dx - r, top: pos.dy - r,
      child: IgnorePointer(
        child: Container(
          width: r * 2, height: r * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: p.ink2, width: 1.5),
            color: p.paper0.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTransformHandles(CanvasState state, Size canvasSize) {
    if (state.selectedElementId == null) return [];
    final page = state.currentPage;
    if (page == null) return [];

    final element = page.layers.content.where((e) {
      final id = e.map(stroke: (s) => s.id, text: (t) => t.id, image: (i) => i.id, shape: (s) => s.id, math: (e) => e.id);
      return id == state.selectedElementId;
    }).firstOrNull;
    if (element == null) return [];

    Rect? pageBounds;
    double rotation = 0;
    element.map(
      stroke: (_) {},
      text: (t) => pageBounds = Rect.fromLTWH(t.data.x, t.data.y, t.data.width, t.data.height),
      image: (i) {
        pageBounds = Rect.fromLTWH(i.data.x, i.data.y, i.data.width, i.data.height);
        rotation = i.data.rotation;
      },
      shape: (s) {
        pageBounds = Rect.fromPoints(Offset(s.data.x1, s.data.y1), Offset(s.data.x2, s.data.y2));
        rotation = s.data.rotation;
      },
      math: (e) => pageBounds = Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
    );
    if (pageBounds == null) return [];

    // Live override: while the user is dragging / rotating / resizing this
    // very element, _elementTransformNotifier holds the deltas. Apply
    // them so the bounding box and rotation handle stay glued to the
    // moving content instead of snapping at pan-end.
    final liveActive = _elementTransformNotifier.isActive &&
        _elementTransformNotifier.elementId == state.selectedElementId;
    if (liveActive) {
      final dx = _elementTransformNotifier.dragOffset.dx;
      final dy = _elementTransformNotifier.dragOffset.dy;
      final sw = _elementTransformNotifier.scaleW;
      final sh = _elementTransformNotifier.scaleH;
      final newW = pageBounds!.width * sw;
      final newH = pageBounds!.height * sh;
      // Resize keeps the top-left corner fixed (matches handle math),
      // then drag offset is added.
      pageBounds = Rect.fromLTWH(
        pageBounds!.left + dx,
        pageBounds!.top + dy,
        newW,
        newH,
      );
      rotation += _elementTransformNotifier.rotationDelta;
    }

    final screenTL = _toScreenCoords(pageBounds!.topLeft, state, canvasSize);
    final screenBR = _toScreenCoords(pageBounds!.bottomRight, state, canvasSize);
    final screenRect = Rect.fromPoints(screenTL, screenBR);

    // Determine if the selected element is an image (to show crop button)
    final isImage = element.map(
      stroke: (_) => false,
      text: (_) => false,
      image: (_) => true,
      shape: (_) => false,
      math: (_) => false,
    );

    final isLocked = element.map(
      stroke: (_) => false,
      text: (_) => false,
      image: (e) => e.data.locked,
      shape: (_) => false,
      math: (_) => false,
    );

    final hasComment = element.map(
      stroke: (_) => false,
      text: (_) => false,
      image: (e) => e.data.comment != null && e.data.comment!.isNotEmpty,
      shape: (_) => false,
      math: (_) => false,
    );

    final isFlipped = element.map(
      stroke: (_) => false,
      text: (_) => false,
      image: (e) => e.data.flipHorizontal,
      shape: (_) => false,
      math: (_) => false,
    );

    // Text boxes resize like GoodNotes/Keynote: corners scale the font,
    // sides change the wrap width, and height auto-fits (so the top/bottom
    // handles are hidden). Images/shapes/math keep free-deform corners.
    final isText = element.map(
      stroke: (_) => false,
      text: (_) => true,
      image: (_) => false,
      shape: (_) => false,
      math: (_) => false,
    );

    final elementId = state.selectedElementId!;

    return [
      ImageHandleOverlay(
        bounds: screenRect,
        rotation: rotation,
        isLocked: isLocked,
        hasComment: hasComment,
        isFlipped: isFlipped,
        // Text is now a reflow frame: all handles change the box (never the
        // font), so it free-deforms like an image and exposes height handles.
        showEdgeHeightHandles: true,
        // Font size is decoupled from resize — adjusted via the action bar.
        // Push one undo checkpoint per tap (resizeTextElement doesn't, since
        // the drag flow normally owns that via onDragStart).
        onFontSmaller: isText
            ? () {
                final n = ref.read(canvasProvider.notifier);
                n.startDragElement(elementId);
                n.resizeTextElement(elementId, fontScale: 1 / 1.15);
              }
            : null,
        onFontLarger: isText
            ? () {
                final n = ref.read(canvasProvider.notifier);
                n.startDragElement(elementId);
                n.resizeTextElement(elementId, fontScale: 1.15);
              }
            : null,
        onDragStart: () {
          // Push undo once (Riverpod), then switch to the local notifier
          // for the rest of the gesture so per-frame moves don't fire
          // state updates. Pass the ORIGINAL element bounds so onResize
          // can compute true cumulative scale (vs. the live, already-
          // scaled bounds the parent rebuilds with each setScale tick).
          ref.read(canvasProvider.notifier).startDragElement(elementId);
          _elementTransformNotifier.begin(elementId, origBounds: pageBounds);
        },
        onDragEnd: () => _commitElementTransform(elementId, state, canvasSize),
        onMove: (delta) {
          final pageDelta = delta / (state.zoom * _getRenderScale(state, canvasSize));
          // Local-only — Riverpod catches up at pan-end via onDragEnd.
          _elementTransformNotifier.translate(pageDelta);
        },
        onResize: (newBounds) {
          // Compute a CUMULATIVE scale relative to the element's bounds
          // at gesture-start (captured in the notifier on begin), NOT
          // relative to the current pageBounds — pageBounds was already
          // multiplied by the previous tick's notifier scale during the
          // ListenableBuilder rebuild, so dividing by it would yield a
          // per-tick relative scale that the replace-semantic setScale
          // would then overwrite the cumulative growth with. The image
          // jiggled around ~110% no matter how far you dragged.
          final orig = _elementTransformNotifier.origBounds ?? pageBounds!;
          final origScreenTL = _toScreenCoords(
              orig.topLeft, state, canvasSize);
          final origScreenBR = _toScreenCoords(
              orig.bottomRight, state, canvasSize);
          final origScreenRect = Rect.fromPoints(origScreenTL, origScreenBR);
          final sw = (origScreenRect.width <= 0)
              ? 1.0
              : (newBounds.width / origScreenRect.width);
          final sh = (origScreenRect.height <= 0)
              ? 1.0
              : (newBounds.height / origScreenRect.height);
          // Translate the top-left if it moved (e.g. resize from top/left).
          final dx = (newBounds.left - origScreenRect.left) /
              (state.zoom * _getRenderScale(state, canvasSize));
          final dy = (newBounds.top - origScreenRect.top) /
              (state.zoom * _getRenderScale(state, canvasSize));
          _elementTransformNotifier.setScale(sw, sh);
          _elementTransformNotifier.translate(
              Offset(dx - _elementTransformNotifier.dragOffset.dx,
                  dy - _elementTransformNotifier.dragOffset.dy));
        },
        onRotate: (angle) {
          _elementTransformNotifier.rotateBy(angle);
        },
        onDelete: () {
          ref.read(canvasProvider.notifier).deleteElement(elementId);
        },
        onDeselect: () {
          ref.read(canvasProvider.notifier).deselectElement();
        },
        onCrop: isImage ? () => _showCropDialog(elementId) : null,
        onBringToFront: () {
          ref.read(canvasProvider.notifier).bringToFront(elementId);
        },
        onSendToBack: () {
          ref.read(canvasProvider.notifier).sendToBack(elementId);
        },
        onToggleLock: isImage ? () {
          ref.read(canvasProvider.notifier).toggleImageLock(elementId);
        } : null,
        onEditComment: isImage ? () {
          _showCommentDialog(elementId);
        } : null,
        onCopy: isImage ? () {
          ref.read(canvasProvider.notifier).copyElement(elementId);
          // Also push the PNG to the system clipboard so the user can
          // paste it into another app.
          _copyImageElementToSystemClipboard(elementId);
          _toast(AppLocalizations.of(context).csImageCopied);
        } : null,
        onCut: isImage ? () {
          ref.read(canvasProvider.notifier).cutElement(elementId);
          _toast(AppLocalizations.of(context).csImageCut);
        } : null,
        onFlipHorizontal: isImage ? () {
          ref.read(canvasProvider.notifier).flipImageElement(elementId);
        } : null,
      ),
    ];
  }

  Future<void> _showCommentDialog(String elementId) async {
    // Find current comment
    final st = ref.read(canvasProvider);
    if (st == null) return;
    String? currentComment;
    final pg = st.currentPage;
    if (pg != null) {
      for (final el in pg.layers.content) {
        final id = el.map(stroke: (e) => e.id, text: (e) => e.id, image: (e) => e.id, shape: (e) => e.id, math: (e) => e.id);
        if (id == elementId) {
          el.map(
            stroke: (_) {},
            text: (_) {},
            image: (e) => currentComment = e.data.comment,
            shape: (_) {},
            math: (_) {},
          );
          break;
        }
      }
    }

    final controller = TextEditingController(text: currentComment ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).csImageCommentTitle),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: AppLocalizations.of(ctx).csAddCommentHint),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(AppLocalizations.of(ctx).csCancel),
          ),
          if (currentComment != null && currentComment!.isNotEmpty)
            TextButton(
              onPressed: () {
                ref.read(canvasProvider.notifier).setImageComment(elementId, null);
                Navigator.of(ctx).pop(null);
              },
              child: Text(AppLocalizations.of(ctx).csRemove, style: const TextStyle(color: HwTheme.syncConflict)),
            ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(AppLocalizations.of(ctx).csSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      ref.read(canvasProvider.notifier).setImageComment(elementId, result.isEmpty ? null : result);
    }
  }

  // ── Crop dialog ──

  void _showCropDialog(String elementId) {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final page = state.currentPage;
    if (page == null) return;

    final element = page.layers.content.where((e) {
      return e.map(stroke: (s) => s.id, text: (t) => t.id, image: (i) => i.id, shape: (s) => s.id, math: (e) => e.id) == elementId;
    }).firstOrNull;
    if (element == null) return;

    ImageData? imageData;
    element.map(stroke: (_) {}, text: (_) {}, image: (i) => imageData = i.data, shape: (_) {}, math: (_) {});
    if (imageData == null) return;
    final imgData = imageData!;

    final cachedImage = state.imageCache[imgData.assetPath];
    if (cachedImage == null) return;

    // Show a dialog with crop handles
    showDialog(
      context: context,
      builder: (ctx) => CropDialog(
        image: cachedImage,
        imageData: imgData,
        onCrop: (cropRect) {
          // cropRect is in normalized 0..1 coordinates
          ref.read(canvasProvider.notifier).cropImageElement(elementId, cropRect);
        },
      ),
    );
  }

  // ── Lasso selection rotation handle ──

  Widget _buildFloatingSelectionActions(CanvasState state, Size canvasSize) {
    final p = HwThemeScope.of(context);
    final originalSel = state.lassoSelection!;
    // Same live-transform override as _buildLassoHandles — keeps the
    // floating action bar attached to the moving selection during a
    // drag/rotate/scale gesture.
    final sel = _lassoTransformNotifier.isActive
        ? originalSel.copyWith(
            dragOffset: _lassoTransformNotifier.dragOffset,
            rotation: _lassoTransformNotifier.rotation,
            scale: _lassoTransformNotifier.scale,
          )
        : originalSel;
    final center = sel.bounds.center;
    final scaledBounds = Rect.fromCenter(
      center: center,
      width: sel.bounds.width * sel.scale,
      height: sel.bounds.height * sel.scale,
    ).translate(sel.dragOffset.dx, sel.dragOffset.dy);

    // Position below the selection
    final screenBottom = _toScreenCoords(scaledBounds.bottomCenter, state, canvasSize);

    // Clamp to stay within view
    final top = (screenBottom.dy + 12).clamp(0.0, canvasSize.height - 50);

    return Positioned(
      left: 0,
      right: 0,
      top: top,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: p.paper0,
            borderRadius: BorderRadius.circular(22),
            boxShadow: hwShadow2(p.brightness),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FloatingActionBtn(Icons.copy_rounded, AppLocalizations.of(context).csCopy, () {
                ref.read(canvasProvider.notifier).copySelection();
                // If the selection is a single image, also push its PNG
                // to the system clipboard so the user can paste it elsewhere.
                final sel = state.lassoSelection;
                if (sel != null && sel.selectedIds.length == 1) {
                  final page = state.currentPage;
                  final id = sel.selectedIds.first;
                  final el = page?.layers.content.where((e) => e.map(
                    stroke: (s) => s.id, text: (t) => t.id,
                    image: (i) => i.id, shape: (s) => s.id,
                    math: (e) => e.id,
                  ) == id).firstOrNull;
                  final isImg = el?.map(
                    stroke: (_) => false, text: (_) => false,
                    image: (_) => true, shape: (_) => false,
                    math: (_) => false,
                  ) ?? false;
                  if (isImg) _copyImageElementToSystemClipboard(id);
                }
                _toast(AppLocalizations.of(context).csSelectionCopied);
              }),
              _FloatingActionBtn(Icons.content_cut_rounded, AppLocalizations.of(context).csCut, () {
                ref.read(canvasProvider.notifier).cutSelection();
                _toast(AppLocalizations.of(context).csSelectionCut);
              }),
              _FloatingActionBtn(Icons.copy_all_rounded, AppLocalizations.of(context).csDuplicate, () {
                ref.read(canvasProvider.notifier).duplicateSelection();
                _toast(AppLocalizations.of(context).csSelectionDuplicated);
              }),
              // Quick color picker — restores the workflow from the
              // previous UI (select stroke → tap color to recolor).
              _FloatingActionBtn(Icons.palette_rounded, AppLocalizations.of(context).csChangeColor,
                  () => _showSelectionColorPicker()),
              // Thickness slider for already-drawn ink — only meaningful
              // when the selection actually contains a stroke or shape.
              if (_selectionCurrentWidth(state) != null)
                _FloatingActionBtn(Icons.line_weight_rounded, AppLocalizations.of(context).csThickness,
                    () => _showSelectionWidthPicker(state)),
              if (state.clipboard != null)
                _FloatingActionBtn(Icons.paste_rounded, AppLocalizations.of(context).csPaste, () {
                  _pasteInternal(null);
                }),
              _FloatingActionBtn(Icons.delete_outline, AppLocalizations.of(context).csDelete, () {
                ref.read(canvasProvider.notifier).deleteSelection();
              }, color: HwTheme.syncConflict),
              // Less-used actions folded into a "more" menu (Rifletti H/V,
              // Screenshot, Incolla in altro notebook).
              _FloatingActionBtn(Icons.more_horiz, AppLocalizations.of(context).csMore,
                  () => _showSelectionMoreMenu(state)),
              _FloatingActionBtn(Icons.close, null, () {
                ref.read(canvasProvider.notifier).clearSelection();
              }),
            ],
          ),
        ),
      ),
    );
  }

  /// Quick color picker for an existing lasso selection — restores the
  /// "select stroke → tap colour to recolour" workflow that the previous
  /// UI had via the toolbar palette.
  Future<void> _showSelectionColorPicker() async {
    final presets = ref.read(presetColorsProvider);
    if (!mounted) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(ctx).csChangeSelectionColor,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in presets)
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0x1A000000), width: 1),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      ref.read(canvasProvider.notifier).changeSelectionColor(picked);
    }
  }

  /// Stroke/shape width shared by the current selection, or null when it
  /// has no stroke/shape to adjust (e.g. a pure text or image selection).
  /// Used both to seed the width-picker slider and to decide whether the
  /// "Spessore" action makes sense to show at all.
  double? _selectionCurrentWidth(CanvasState state) {
    final sel = state.lassoSelection;
    final page = state.currentPage;
    if (sel == null || page == null) return null;
    for (final element in page.layers.content) {
      final id = element.map(
        stroke: (e) => e.id, text: (e) => e.id,
        image: (e) => e.id, shape: (e) => e.id,
        math: (e) => e.id,
      );
      if (!sel.selectedIds.contains(id)) continue;
      final width = element.map(
        stroke: (e) => e.data.baseWidth,
        text: (_) => -1.0,
        image: (_) => -1.0,
        shape: (e) => e.data.strokeWidth,
        math: (_) => -1.0,
      );
      if (width >= 0) return width;
    }
    return null;
  }

  /// Clean single-purpose UI for adjusting the thickness of ink that's
  /// already on the page: lasso-select it, tap "Spessore", drag the
  /// slider. Every tick writes the real width to the selected strokes/
  /// shapes so the canvas updates live; the whole drag coalesces into a
  /// single undo step (CanvasNotifier.changeSelectionStrokeWidth).
  Future<void> _showSelectionWidthPicker(CanvasState state) async {
    final notifier = ref.read(canvasProvider.notifier);
    final p = HwThemeScope.of(context);
    var width = _selectionCurrentWidth(state) ?? 2.0;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(AppLocalizations.of(ctx).csSelectionThickness,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(AppLocalizations.of(ctx).csWidthPx(width.toStringAsFixed(1)),
                        style: TextStyle(fontSize: 12, color: p.ink1)),
                  ],
                ),
                const SizedBox(height: 8),
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
                    value: width.clamp(0.5, 20.0),
                    onChanged: (v) {
                      setSheetState(() => width = v);
                      notifier.changeSelectionStrokeWidth(v);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    notifier.endSelectionWidthEdit();
  }

  /// "Altro" menu for lass selection — surfaces the less-used actions
  /// (flip H/V, screenshot to clipboard, paste into another notebook).
  Future<void> _showSelectionMoreMenu(CanvasState state) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.flip_rounded),
              title: Text(AppLocalizations.of(ctx).csFlipHorizontal),
              onTap: () {
                Navigator.of(ctx).pop();
                ref.read(canvasProvider.notifier).flipSelectionHorizontal();
              },
            ),
            ListTile(
              leading: Transform.rotate(
                angle: 1.5708,
                child: const Icon(Icons.flip_rounded),
              ),
              title: Text(AppLocalizations.of(ctx).csFlipVertical),
              onTap: () {
                Navigator.of(ctx).pop();
                ref.read(canvasProvider.notifier).flipSelectionVertical();
              },
            ),
            ListTile(
              leading: const Icon(Icons.screenshot_rounded),
              title: Text(AppLocalizations.of(ctx).csCopyAsImage),
              onTap: () {
                Navigator.of(ctx).pop();
                _copySelectionAsScreenshot();
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_outline_rounded),
              title: Text(AppLocalizations.of(ctx).csCreateSymbol),
              onTap: () {
                Navigator.of(ctx).pop();
                _promptCreateSymbolFromSelection();
              },
            ),
            if (state.clipboard != null)
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: Text(AppLocalizations.of(ctx).csPasteInAnotherNotebook),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pasteInAnotherNotebook(context, state.clipboard!);
                },
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLassoHandles(CanvasState state, Size canvasSize) {
    final originalSel = state.lassoSelection;
    if (originalSel == null) return [];
    final p = HwThemeScope.of(context);

    // During drag/rotate/scale the local LassoTransformNotifier holds the
    // live values. Riverpod state stays at the *initial* transform until
    // pointer-up, so reading sel.dragOffset/scale/rotation directly here
    // would freeze the handles in place while the canvas content moved
    // underneath — the visible "lag". Override with the live values.
    final sel = _lassoTransformNotifier.isActive
        ? originalSel.copyWith(
            dragOffset: _lassoTransformNotifier.dragOffset,
            rotation: _lassoTransformNotifier.rotation,
            scale: _lassoTransformNotifier.scale,
          )
        : originalSel;

    final center = sel.bounds.center;
    final scaledBounds = Rect.fromCenter(
      center: center,
      width: sel.bounds.width * sel.scale,
      height: sel.bounds.height * sel.scale,
    ).translate(sel.dragOffset.dx, sel.dragOffset.dy);

    final screenTL = _toScreenCoords(scaledBounds.topLeft, state, canvasSize);
    final screenBR = _toScreenCoords(scaledBounds.bottomRight, state, canvasSize);
    final screenRect = Rect.fromPoints(screenTL, screenBR);
    final selRotation = sel.rotation;

    Offset rotateScreenPoint(Offset point) {
      if (selRotation == 0.0) return point;
      final dx = point.dx - screenRect.center.dx;
      final dy = point.dy - screenRect.center.dy;
      final cosA = cos(selRotation);
      final sinA = sin(selRotation);
      return Offset(
        screenRect.center.dx + dx * cosA - dy * sinA,
        screenRect.center.dy + dx * sinA + dy * cosA,
      );
    }

    final unrotatedCenterTop = Offset(screenRect.center.dx, screenRect.top - 40);
    final centerTop = rotateScreenPoint(unrotatedCenterTop);

    Widget buildCornerHandle(Offset unrotatedPos, MouseCursor cursor) {
      final screenPos = rotateScreenPoint(unrotatedPos);
      return Positioned(
        left: screenPos.dx - 7,
        top: screenPos.dy - 7,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            onPanStart: (d) {
              _resizeDragStart = d.globalPosition;
              _resizeInitialScale = sel.scale;
              _lassoTransformNotifier.begin(
                dragOffset: sel.dragOffset,
                rotation: sel.rotation,
                scale: sel.scale,
              );
            },
            onPanUpdate: (d) {
              // Convert screenRect.center to global coordinates via the canvas Stack
              final stackBox = _canvasStackKey.currentContext?.findRenderObject() as RenderBox?;
              final centerGlobal = stackBox != null
                  ? stackBox.localToGlobal(screenRect.center)
                  : screenRect.center;
              final startDist = (_resizeDragStart - centerGlobal).distance;
              final currentDist = (d.globalPosition - centerGlobal).distance;
              if (startDist > 5) {
                final newScale = _resizeInitialScale * (currentDist / startDist);
                _lassoTransformNotifier.setScale(newScale.clamp(0.1, 10.0));
              }
            },
            onPanEnd: (_) => _commitLassoTransform(),
            onPanCancel: _commitLassoTransform,
            child: Container(
              width: 14, height: 14,
              decoration: BoxDecoration(
                color: p.paper0,
                shape: BoxShape.circle,
                border: Border.all(color: p.accent, width: 1.5),
                boxShadow: hwShadow2(p.brightness),
              ),
            ),
          ),
        ),
      );
    }

    return [
      // Corner resize handles
      buildCornerHandle(screenRect.topLeft, SystemMouseCursors.resizeUpLeft),
      buildCornerHandle(screenRect.topRight, SystemMouseCursors.resizeUpRight),
      buildCornerHandle(screenRect.bottomLeft, SystemMouseCursors.resizeDownLeft),
      buildCornerHandle(screenRect.bottomRight, SystemMouseCursors.resizeDownRight),

      // Rotation handle
      Positioned(
        left: centerTop.dx - 14,
        top: centerTop.dy - 14,
        child: Transform.rotate(
          angle: selRotation,
          origin: const Offset(0, -13), // Shift origin from the center of the 54px col (y=27) pointing to circle (y=14)
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onPanStart: (_) {
                  _lassoTransformNotifier.begin(
                    dragOffset: sel.dragOffset,
                    rotation: sel.rotation,
                    scale: sel.scale,
                  );
                },
                onPanUpdate: (d) {
                  // Use the canvas Stack's RenderBox for proper coordinate conversion
                  final stackBox = _canvasStackKey.currentContext?.findRenderObject() as RenderBox?;
                  final centerGlobal = stackBox != null
                      ? stackBox.localToGlobal(screenRect.center)
                      : screenRect.center;
                  final prev = d.globalPosition - d.delta;
                  final startAngle = atan2(prev.dy - centerGlobal.dy, prev.dx - centerGlobal.dx);
                  final currentAngle = atan2(d.globalPosition.dy - centerGlobal.dy, d.globalPosition.dx - centerGlobal.dx);
                  var deltaAngle = currentAngle - startAngle;
                  if (deltaAngle > pi) deltaAngle -= 2 * pi;
                  if (deltaAngle < -pi) deltaAngle += 2 * pi;
                  _lassoTransformNotifier.rotateBy(deltaAngle);
                },
                onPanEnd: (_) => _commitLassoTransform(),
                onPanCancel: _commitLassoTransform,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: p.paper0, shape: BoxShape.circle,
                    border: Border.all(color: p.accent, width: 2),
                    boxShadow: hwShadow2(p.brightness),
                  ),
                  child: Icon(Icons.rotate_right_rounded, size: 16, color: p.accent),
                ),
              ),
              IgnorePointer(
                child: Container(width: 1.5, height: 26, color: p.accent.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  // Fields for resize drag tracking
  Offset _resizeDragStart = Offset.zero;
  double _resizeInitialScale = 1.0;

  /// Commit the locally-tracked element transform back to Riverpod once,
  /// at the end of a drag/rotate/resize gesture. During the gesture
  /// _elementTransformNotifier received every delta; here Riverpod
  /// catches up exactly once.
  void _commitElementTransform(
      String elementId, CanvasState state, Size canvasSize) {
    if (!_elementTransformNotifier.isActive) return;
    final dragOffset = _elementTransformNotifier.dragOffset;
    final rotationDelta = _elementTransformNotifier.rotationDelta;
    final sw = _elementTransformNotifier.scaleW;
    final sh = _elementTransformNotifier.scaleH;
    _elementTransformNotifier.end();

    final notifier = ref.read(canvasProvider.notifier);
    // Resize: derive the new page-bounds from the original element
    // bounds + accumulated drag + scale.
    final page = state.currentPage;
    if (page == null) return;
    final element = page.layers.content.where((e) {
      final id = e.map(
          stroke: (s) => s.id,
          text: (t) => t.id,
          image: (i) => i.id,
          shape: (s) => s.id,
          math: (e) => e.id);
      return id == elementId;
    }).firstOrNull;
    if (element == null) return;
    Rect? origBounds;
    element.map(
      stroke: (_) {},
      text: (t) =>
          origBounds = Rect.fromLTWH(t.data.x, t.data.y, t.data.width, t.data.height),
      image: (i) =>
          origBounds = Rect.fromLTWH(i.data.x, i.data.y, i.data.width, i.data.height),
      shape: (s) => origBounds =
          Rect.fromPoints(Offset(s.data.x1, s.data.y1), Offset(s.data.x2, s.data.y2)),
      math: (e) =>
          origBounds = Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
    );
    if (origBounds == null) return;

    // Apply scale (if any) first, then translate.
    final scaledRect = Rect.fromLTWH(
      origBounds!.left,
      origBounds!.top,
      origBounds!.width * sw,
      origBounds!.height * sh,
    );
    final newBounds = scaledRect.translate(dragOffset.dx, dragOffset.dy);

    final isTextEl = element.map(
      stroke: (_) => false, text: (_) => true, image: (_) => false,
      shape: (_) => false, math: (_) => false,
    );

    // Single Riverpod update for the whole gesture.
    if (isTextEl) {
      // Text is a reflow FRAME ("box = zona"): every handle resizes the box,
      // the text wraps to the new width, and the font is NEVER deformed by a
      // drag (font size is changed via the +/- buttons in the action bar).
      // Corners scale the box proportionally (sw≈sh), edges change one side.
      // Height is honoured as the frame height (clamped so text is never
      // clipped — see resizeTextElement).
      final scaled = sw != 1.0 || sh != 1.0;
      final newTopLeft =
          Offset(origBounds!.left + dragOffset.dx, origBounds!.top + dragOffset.dy);
      if (scaled) {
        notifier.resizeTextElement(
          elementId,
          width: origBounds!.width * sw,
          height: origBounds!.height * sh,
          topLeft: dragOffset != Offset.zero ? newTopLeft : null,
        );
      } else if (dragOffset != Offset.zero) {
        notifier.moveElement(elementId, dragOffset);
      }
      // Text has no rotation field — rotationDelta is a no-op, drop it.
    } else {
      // Images / shapes / math: free-deform bbox, then move + rotate.
      if (sw != 1.0 || sh != 1.0) {
        notifier.resizeElement(elementId, scaledRect);
      }
      if (dragOffset != Offset.zero) {
        notifier.moveElement(elementId, dragOffset);
      }
      if (rotationDelta != 0.0) {
        notifier.rotateElement(elementId, rotationDelta);
      }
    }
    // Suppress unused-var warning.
    // ignore: unused_local_variable
    final _ = newBounds;
  }

  /// Snapshot the live transform from [_lassoTransformNotifier] back into
  /// Riverpod and clear the notifier. Called from drag/rotate/scale
  /// onPanEnd / onPanCancel + the drag-selection branch of _onPointerUp.
  /// Riverpod fires exactly once per gesture instead of once per
  /// pointer-move event.
  void _commitLassoTransform() {
    if (!_lassoTransformNotifier.isActive) return;
    final snap = _lassoTransformNotifier.snapshot();
    ref.read(canvasProvider.notifier).commitSelectionTransform(
          dragOffset: snap.dragOffset,
          rotation: snap.rotation,
          scale: snap.scale,
        );
    _lassoTransformNotifier.end();
  }

  // ── Context menu (right-click) ──

  void _showContextMenu(Offset globalPos, Offset localPos, CanvasState state, Size canvasSize) {
    final pagePos = _toPageCoords(localPos, state, canvasSize);
    final tappedElement = _findElementAt(state, pagePos);
    final hasLassoSelection = state.lassoSelection != null;
    final hasSymbols = state.symbols.isNotEmpty;
    final l10n = AppLocalizations.of(context);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        // Selection operations
        if (hasLassoSelection) ...[
          PopupMenuItem(value: 'copy', child: _MenuRow(Icons.copy_rounded, l10n.csCopy, 'Ctrl+C')),
          PopupMenuItem(value: 'copy_screenshot', child: _MenuRow(Icons.screenshot_rounded, l10n.csCopyAsImage, null)),
          PopupMenuItem(value: 'cut', child: _MenuRow(Icons.content_cut_rounded, l10n.csCut, 'Ctrl+X')),
          PopupMenuItem(value: 'duplicate_sel', child: _MenuRow(Icons.copy_all_rounded, l10n.csDuplicate, 'Ctrl+D')),
          PopupMenuItem(value: 'delete_sel', child: _MenuRow(Icons.delete_outline_rounded, l10n.csDelete, l10n.csKeyDelete)),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'create_symbol', child: _MenuRow(Icons.star_outline_rounded, l10n.csCreateSymbol, null)),
          const PopupMenuDivider(),
        ],
        // Single element operations
        if (tappedElement != null && !hasLassoSelection) ...[
          PopupMenuItem(value: 'select_element', child: _MenuRow(Icons.touch_app_outlined, l10n.csSelect, null)),
          PopupMenuItem(value: 'duplicate_element', child: _MenuRow(Icons.copy_all_rounded, l10n.csDuplicate, null)),
          PopupMenuItem(value: 'delete_element', child: _MenuRow(Icons.delete_outline_rounded, l10n.csDelete, null)),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'create_symbol_element', child: _MenuRow(Icons.star_outline_rounded, l10n.csCreateSymbol, null)),
          const PopupMenuDivider(),
        ],
        // Paste: single entry — _pasteFromClipboard resolves what the user
        // most recently copied (fresh system image/text wins over a stale
        // in-app selection, and vice versa).
        PopupMenuItem(value: 'paste', child: _MenuRow(Icons.paste_rounded, l10n.csPaste, 'Ctrl+V')),
        // Insert: one picker for images AND PDFs (was two separate entries).
        PopupMenuItem(value: 'insert_file', child: _MenuRow(Icons.attach_file_rounded, l10n.csImportFile, null)),
        if (_cameraAvailable)
          PopupMenuItem(value: 'insert_camera', child: _MenuRow(Icons.camera_alt_rounded, l10n.csTakePhoto, null)),
        PopupMenuItem(value: 'insert_text', child: _MenuRow(Icons.text_fields_rounded, l10n.csInsertText, null)),
        // Symbols
        if (hasSymbols)
          PopupMenuItem(
            value: 'symbols',
            child: _MenuRow(Icons.star_rounded, l10n.csInsertSymbolCount(state.symbols.length), null),
          ),
        const PopupMenuDivider(),
        // Page operations
        PopupMenuItem(value: 'select_all', child: _MenuRow(Icons.select_all_rounded, l10n.csSelectAll, 'Ctrl+A')),
        PopupMenuItem(value: 'clear_page', child: _MenuRow(Icons.cleaning_services_rounded, l10n.csClearPage, null)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'export_png', child: _MenuRow(Icons.image_outlined, l10n.csExportPng, null)),
        PopupMenuItem(value: 'export_pdf', child: _MenuRow(Icons.picture_as_pdf_rounded, l10n.csExportPdf, null)),
      ],
    ).then((value) {
      if (value == null) return;
      final notifier = ref.read(canvasProvider.notifier);
      switch (value) {
        case 'copy': notifier.copySelection(); _toast(AppLocalizations.of(context).csSelectionCopied); break;
        case 'copy_screenshot': _copySelectionAsScreenshot(); break;
        case 'cut': notifier.cutSelection(); _toast(AppLocalizations.of(context).csSelectionCut); break;
        case 'duplicate_sel': notifier.duplicateSelection(); _toast(l10n.csSelectionDuplicated); break;
        case 'delete_sel': notifier.deleteSelection(); break;
        case 'paste': _pasteFromClipboard(at: pagePos); break;
        case 'select_all': notifier.selectAll(); break;
        case 'clear_page': _confirmClearPage(); break;
        case 'insert_file': _pickAndInsertImage(pagePos); break;
        case 'insert_camera': _captureAndInsertImage(pagePos); break;
        case 'insert_text': _handleTextTool(localPos, state, canvasSize); break;
        case 'select_element':
          if (tappedElement != null) notifier.selectElement(tappedElement);
          break;
        case 'duplicate_element':
          if (tappedElement != null) notifier.duplicateElement(tappedElement);
          break;
        case 'delete_element':
          if (tappedElement != null) notifier.deleteElement(tappedElement);
          break;
        case 'create_symbol': _promptCreateSymbolFromSelection(); break;
        case 'create_symbol_element':
          if (tappedElement != null) _promptCreateSymbolFromElement(tappedElement);
          break;
        case 'symbols': _showSymbolsDialog(pagePos); break;
        case 'export_png': _exportAsPng(); break;
        case 'export_pdf': _exportAsPdf(); break;
      }
    });
  }

  void _confirmClearPage() async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.csClearPage),
        content: Text(l10n.csClearPageConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.csCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HwTheme.syncConflict),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.csClear),
          ),
        ],
      ),
    );
    if (confirm == true) ref.read(canvasProvider.notifier).clearPage();
  }

  void _promptCreateSymbolFromSelection() async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final libs = state.symbolLibraries;
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);

    final controller = TextEditingController();
    String? selectedLibId = libs.isNotEmpty ? libs.first.id : null;

    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(l10n.csCreateSymbolTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.csSymbolNameLabel, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              if (libs.isNotEmpty) ...[
                Text(l10n.csLibraryLabel, style: TextStyle(fontSize: 12, color: p.ink2)),
                const SizedBox(height: 4),
                DropdownButton<String>(
                  value: selectedLibId,
                  isExpanded: true,
                  items: libs.map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))).toList(),
                  onChanged: (v) => setS(() => selectedLibId = v),
                ),
              ] else
                Text(l10n.csNoLibraryNotice,
                    style: TextStyle(fontSize: 11, color: p.ink2)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.csCancel)),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (controller.text, selectedLibId)),
              child: Text(l10n.csCreate),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null && result.$1.isNotEmpty) {
      ref.read(canvasProvider.notifier).createSymbolFromSelection(result.$1, targetLibId: result.$2);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.csSymbolCreated(result.$1)), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  void _promptCreateSymbolFromElement(String elementId) async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final libs = state.symbolLibraries;
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    String? selectedLibId = libs.isNotEmpty ? libs.first.id : null;

    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(l10n.csCreateSymbolTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.csSymbolNameLabel, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              if (libs.isNotEmpty) ...[
                Text(l10n.csLibraryLabel, style: TextStyle(fontSize: 12, color: p.ink2)),
                const SizedBox(height: 4),
                DropdownButton<String>(
                  value: selectedLibId,
                  isExpanded: true,
                  items: libs.map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))).toList(),
                  onChanged: (v) => setS(() => selectedLibId = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.csCancel)),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (controller.text, selectedLibId)),
              child: Text(l10n.csCreate),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null && result.$1.isNotEmpty) {
      ref.read(canvasProvider.notifier).createSymbolFromElement(elementId, result.$1);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.csSymbolCreated(result.$1)), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  void _showSymbolsDialog(Offset insertPos) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: SymbolLibraryPanel(
          insertPos: insertPos,
          onClose: () => Navigator.pop(ctx),
        ),
      ),
    );
  }

  // ── Export ──

  /// Render a single page to a PNG [Uint8List] at the given [scale].
  Future<Uint8List?> _renderPageToPng(PageData page, Map<String, ui.Image> imageCache, {double scale = 2.0}) async {
    final w = page.width;
    final h = page.height;
    final renderW = (w * scale).round();
    final renderH = (h * scale).round();
    if (renderW <= 0 || renderH <= 0) return null;

    // The live imageCache only holds textures for pages near the current
    // one (windowed decode + LRU eviction). Pages outside the window
    // would export with grey placeholders — decode their assets here
    // into a temporary per-page cache, disposed right after the render.
    final temp = <String, ui.Image>{};
    final assetBytes = ref.read(canvasProvider)?.assetBytes ?? const <String, Uint8List>{};
    for (final el in page.layers.content) {
      if (el is! ImageElement) continue;
      final path = el.data.assetPath;
      if (path.isEmpty || imageCache.containsKey(path) || temp.containsKey(path)) {
        continue;
      }
      final bytes = assetBytes[path];
      if (bytes == null) continue;
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        temp[path] = frame.image;
      } catch (_) {
        // Corrupt asset — the engine paints its placeholder as on-canvas.
      }
    }
    final effectiveCache =
        temp.isEmpty ? imageCache : {...imageCache, ...temp};

    // Offscreen export runs paint() synchronously with a cold cache, so it
    // can't kick the async math raster + wait for a repaint. Pre-rasterize
    // every math element here (await) and inject a warm math cache, mirroring
    // the image pre-decode above. Without this, equations would export as
    // the placeholder box.
    final mathPr = scale.clamp(1.0, 4.0);
    final mathTemp = <String, MathRaster>{};
    for (final el in page.layers.content) {
      if (el is! MathElement) continue;
      final d = el.data;
      final key = mathCacheKey(
          d.latex, d.color, d.fontSize, d.displayMode, mathPr);
      if (mathTemp.containsKey(key)) continue;
      final r = await MathRasterizer.rasterize(
        latex: d.latex,
        color: Color(d.color),
        fontSize: d.fontSize,
        displayMode: d.displayMode,
        pixelRatio: mathPr,
      );
      if (r != null) mathTemp[key] = r;
    }

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w * scale, h * scale));
      canvas.scale(scale);
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);

      final engine = CanvasRenderEngine(
        pageData: page,
        zoom: 1.0,
        panOffset: Offset.zero,
        imageCache: effectiveCache,
        mathCache: mathTemp,
        mathPixelRatio: mathPr.toDouble(),
      );
      engine.paintPage(canvas, Size(w, h), 1.0, Offset.zero);

      final picture = recorder.endRecording();
      final img = await picture.toImage(renderW, renderH);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      picture.dispose();
      return byteData?.buffer.asUint8List();
    } finally {
      for (final img in temp.values) {
        img.dispose();
      }
      for (final m in mathTemp.values) {
        m.image.dispose();
      }
    }
  }

  /// Resolve the chapter the user means by "capitolo corrente". Prefers
  /// the navigator filter ([CanvasState.activeChapterId]) but falls back
  /// to the chapterId of the page currently under the viewport so the
  /// "all pages" view still exports a meaningful chapter.
  Chapter? _resolveActiveChapter(CanvasState state) {
    String? chId = state.activeChapterId;
    if (chId == null) {
      final idx = state.currentPageIndex;
      if (idx >= 0 && idx < state.document.pages.length) {
        chId = state.document.pages[idx].chapterId;
      }
    }
    if (chId == null) return null;
    return state.metadata.chapters
        .cast<Chapter?>()
        .firstWhere((c) => c?.id == chId, orElse: () => null);
  }

  /// Return every [PageEntry] that belongs to [chapter], using the same
  /// OR rule as the collector (PageEntry.chapterId match OR pageIds
  /// membership) so the count shown in the dialog and the pages exported
  /// stay in sync even after a heal pass truncated one side.
  List<PageEntry> _chapterPageEntries(CanvasState state, Chapter chapter) {
    final pageIds = chapter.pageIds.toSet();
    return state.document.pages
        .where((e) =>
            e.chapterId == chapter.id || pageIds.contains(e.pageId))
        .toList();
  }

  /// Sanitise a string for use inside a filename on every platform we
  /// ship on (Windows is the strict one: no `\ / : * ? " < > |` and no
  /// trailing dots or spaces). Returns a non-empty placeholder when
  /// nothing survives the filter.
  String _sanitiseForFilename(String raw) {
    var out = raw.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    while (out.endsWith('.') || out.endsWith(' ')) {
      out = out.substring(0, out.length - 1).trimRight();
    }
    return out.isEmpty ? 'Quaderno' : out;
  }

  /// Build the suggested export filename. For chapter scope we append
  /// ` - <chapter title>` so exports from different chapters don't
  /// collide in the user's downloads folder.
  String _exportFilename(
      CanvasState state, _ExportScope scope, String extension) {
    final base = _sanitiseForFilename(state.metadata.title);
    switch (scope) {
      case _ExportScope.currentPage:
        return '$base - pag. ${state.currentPageIndex + 1}.$extension';
      case _ExportScope.currentChapter:
        final ch = _resolveActiveChapter(state);
        if (ch != null && ch.title.trim().isNotEmpty) {
          final chTitle = _sanitiseForFilename(ch.title);
          return '$base - $chTitle.$extension';
        }
        return '$base.$extension';
      case _ExportScope.entireNotebook:
        return '$base.$extension';
    }
  }

  /// Collect the pages to export based on user-chosen [selection].
  /// For currentChapter, applies the optional 1-based inclusive range.
  /// For entireNotebook with chapterSeparators, see [_collectExportPagesWithSeparators].
  List<PageData> _collectExportPages(
      CanvasState state, _ExportSelection selection) {
    switch (selection.scope) {
      case _ExportScope.currentPage:
        final p = state.currentPage;
        return p != null ? [p] : [];
      case _ExportScope.currentChapter:
        final chapter = _resolveActiveChapter(state);
        if (chapter == null) {
          final p = state.currentPage;
          debugPrint('[Export] currentChapter fallback to currentPage: '
              'no chapter id resolvable');
          return p != null ? [p] : [];
        }
        final entries = _chapterPageEntries(state, chapter);
        final all = entries
            .map((e) => state.pages[e.fileName])
            .whereType<PageData>()
            .toList();
        // Apply range slice if provided (1-based, inclusive on both ends)
        final start = (selection.rangeStart ?? 1).clamp(1, all.length);
        final end = (selection.rangeEnd ?? all.length).clamp(start, all.length);
        final result = all.sublist(start - 1, end);
        debugPrint('[Export] currentChapter ${chapter.id}: '
            'pages=${all.length}, range=$start..$end, exporting=${result.length}');
        return result;
      case _ExportScope.entireNotebook:
        return state.document.pages
            .map((e) => state.pages[e.fileName])
            .whereType<PageData>()
            .toList();
    }
  }

  /// Group every page of the notebook by chapter, in document order.
  /// Returns a list of (chapterTitle, pages) — chapterTitle is null for
  /// pages with no chapter assigned.
  List<({String? chapterTitle, List<PageData> pages})>
      _groupPagesByChapter(CanvasState state) {
    final chaptersById = {
      for (final c in state.metadata.chapters) c.id: c,
    };
    final groups = <({String? chapterTitle, List<PageData> pages})>[];
    String? currentTitle;
    List<PageData> bucket = [];
    void flush() {
      if (bucket.isNotEmpty) {
        groups.add((chapterTitle: currentTitle, pages: bucket));
      }
    }
    for (final entry in state.document.pages) {
      final pageData = state.pages[entry.fileName];
      if (pageData == null) continue;
      final chTitle = chaptersById[entry.chapterId]?.title;
      if (chTitle != currentTitle) {
        flush();
        bucket = [];
        currentTitle = chTitle;
      }
      bucket.add(pageData);
    }
    flush();
    return groups;
  }

  /// Anchor rect for the iPad share-sheet popover. SharePlus rejects a
  /// zero rect with "sharePositionOrigin must be non-zero and within
  /// coordinates of source view". Use a small box at the screen centre.
  Rect _shareOriginRect() {
    final size = MediaQuery.of(context).size;
    final cx = size.width / 2;
    final cy = size.height / 2;
    return Rect.fromCenter(center: Offset(cx, cy), width: 40, height: 40);
  }

  /// Save or share a file cross-platform.
  /// On iOS/macOS, uses the system share sheet (FilePicker.saveFile is broken).
  /// On other platforms, uses FilePicker.saveFile.
  Future<void> _saveOrShare(String fileName, Uint8List data, String mimeType) async {
    if (io.Platform.isIOS || io.Platform.isMacOS) {
      final dir = await io.Directory.systemTemp.createTemp('handwriter_export');
      final file = io.File('${dir.path}/$fileName');
      await file.writeAsBytes(data, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: mimeType)],
          subject: fileName,
          // iPad requires a non-zero anchor rect for the share-sheet
          // popover; SharePlus throws "PlatformException(error,
          // sharePositionOrigin must be non-zero...)" otherwise. Use
          // the centre of the screen — it's always within the view.
          sharePositionOrigin: _shareOriginRect(),
        ),
      );
    } else {
      final ext = fileName.split('.').last;
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: AppLocalizations.of(context).csSaveFileDialogTitle(fileName),
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [ext],
      );
      if (savePath != null) {
        await io.File(savePath).writeAsBytes(data, flush: true);
      }
    }
  }

  /// Show the export scope picker, then export as PNG (single page) or
  /// a series of PNGs (multi-page → share sheet with multiple files).
  Future<void> _exportAsPng() async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final l10n = AppLocalizations.of(context);

    final selection = await _showExportScopeDialog(
      singlePageLabel: l10n.csExportCurrentPagePng,
      chapterLabel: l10n.csExportCurrentChapter,
      notebookLabel: l10n.csExportEntireNotebook,
    );
    if (selection == null) return;

    final pages = _collectExportPages(state, selection);
    if (pages.isEmpty) return;

    try {
      if (pages.length == 1) {
        final pngBytes = await _renderPageToPng(pages.first, state.imageCache);
        if (pngBytes == null) return;
        final fileName =
            '${_sanitiseForFilename(state.metadata.title)}_p${state.currentPageIndex + 1}.png';
        await _saveOrShare(fileName, pngBytes, 'image/png');
      } else {
        // Multiple pages → write to temp dir, share all
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.csExportingPages(pages.length))),
        );
        final dir = await io.Directory.systemTemp.createTemp('handwriter_export');
        final files = <XFile>[];
        for (var i = 0; i < pages.length; i++) {
          final pngBytes = await _renderPageToPng(pages[i], state.imageCache);
          if (pngBytes == null) continue;
          final f = io.File(
              '${dir.path}/${_sanitiseForFilename(state.metadata.title)}_p${i + 1}.png');
          await f.writeAsBytes(pngBytes, flush: true);
          files.add(XFile(f.path, mimeType: 'image/png'));
        }
        if (files.isNotEmpty) {
          if (io.Platform.isIOS || io.Platform.isMacOS) {
            await SharePlus.instance.share(
              ShareParams(
                files: files,
                subject: state.metadata.title,
                sharePositionOrigin: _shareOriginRect(),
              ),
            );
          } else {
            // Desktop: let user pick folder, save all
            final savePath = await FilePicker.platform.getDirectoryPath(
              dialogTitle: l10n.csChooseFolderForImages(files.length),
            );
            if (savePath != null) {
              for (final xf in files) {
                final name = xf.path.split('/').last.split('\\').last;
                await io.File('$savePath/$name').writeAsBytes(await xf.readAsBytes());
              }
            }
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.csPngExported(pages.length))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.csExportError(e.toString()))));
      }
    }
  }

  Future<void> _exportAsPdf() async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final l10n = AppLocalizations.of(context);

    final selection = await _showExportScopeDialog(
      singlePageLabel: l10n.csExportCurrentPage,
      chapterLabel: l10n.csExportCurrentChapter,
      notebookLabel: l10n.csExportEntireNotebook,
    );
    if (selection == null) return;

    // Build the actual page list. For "entireNotebook + chapterSeparators"
    // we interleave a synthetic separator page before every chapter group.
    final pagePayload = <_PdfPagePayload>[];
    const scale = 2.0;
    int pageCountForSnack = 0;

    if (selection.scope == _ExportScope.entireNotebook &&
        selection.chapterSeparators) {
      final groups = _groupPagesByChapter(state);
      pageCountForSnack = groups.fold(
          0, (sum, g) => sum + g.pages.length + (g.chapterTitle != null ? 1 : 0));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.csGeneratingPdf(pageCountForSnack))),
        );
      }

      try {
        for (final group in groups) {
          // Use the FIRST page of the group as the size template
          final w = group.pages.isNotEmpty ? group.pages.first.width : 595.0;
          final h = group.pages.isNotEmpty ? group.pages.first.height : 842.0;
          if (group.chapterTitle != null) {
            final sepPng =
                await _renderChapterSeparatorPng(group.chapterTitle!, w, h, scale);
            if (sepPng != null) {
              pagePayload.add(_PdfPagePayload(
                width: w,
                height: h,
                pngBytes: sepPng,
              ));
            }
          }
          for (final page in group.pages) {
            final pngBytes =
                await _renderPageToPng(page, state.imageCache, scale: scale);
            if (pngBytes == null) continue;
            pagePayload.add(_PdfPagePayload(
              width: page.width,
              height: page.height,
              pngBytes: pngBytes,
            ));
          }
        }
        if (pagePayload.isEmpty) return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.csPdfExportError(e.toString()))));
        }
        return;
      }
    } else {
      final pages = _collectExportPages(state, selection);
      if (pages.isEmpty) return;
      pageCountForSnack = pages.length;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.csGeneratingPdf(pages.length))),
        );
      }

      for (final page in pages) {
        final pngBytes = await _renderPageToPng(page, state.imageCache, scale: scale);
        if (pngBytes == null) continue;
        pagePayload.add(_PdfPagePayload(
          width: page.width,
          height: page.height,
          pngBytes: pngBytes,
        ));
      }
      if (pagePayload.isEmpty) return;
    }

    try {

      final pdfBytes = await compute(_buildPdfOnIsolate, pagePayload);
      final fileName = _exportFilename(state, selection.scope, 'pdf');
      await _saveOrShare(fileName, pdfBytes, 'application/pdf');

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.csPdfExported(pageCountForSnack))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.csPdfExportError(e.toString()))));
      }
    }
  }

  /// Builds PDF bytes for the ENTIRE notebook, no export/share dialog.
  /// Reused by the "share as public link" flow. Returns null if there are no
  /// renderable pages. Mirrors [_exportAsPdf]'s entire-notebook (no chapter
  /// separators) path, off-isolate for the actual document assembly.
  Future<Uint8List?> _buildNotebookPdfBytes(CanvasState state) async {
    const scale = 2.0;
    final pages = state.document.pages
        .map((e) => state.pages[e.fileName])
        .whereType<PageData>()
        .toList();
    if (pages.isEmpty) return null;
    final payload = <_PdfPagePayload>[];
    for (final page in pages) {
      final png = await _renderPageToPng(page, state.imageCache, scale: scale);
      if (png == null) continue;
      payload.add(_PdfPagePayload(
        width: page.width,
        height: page.height,
        pngBytes: png,
      ));
    }
    if (payload.isEmpty) return null;
    return compute(_buildPdfOnIsolate, payload);
  }

  /// Uploads a PDF render of the notebook to the user's Nextcloud and shows
  /// the resulting public link (copy / share). See NextcloudShareService for
  /// why this reuses the sync backend instead of our own server.
  Future<void> _shareNotebookLink(CanvasState state) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final share = ref.read(nextcloudShareServiceProvider);
    if (share == null) return; // not connected — UI is gated on this anyway

    final safeName = _sanitiseForFilename(state.metadata.title);
    try {
      // Already shared? Show the existing link instantly — no re-upload, no
      // duplicate link. Reopening the share sheet is then free.
      final existing = await share.existingLink(safeName);
      if (existing != null) {
        if (!mounted) return;
        await _showShareLinkDialog(existing, alreadyShared: true);
        return;
      }

      messenger.showSnackBar(SnackBar(
          content: Text(l10n.csShareLinkInProgress),
          duration: const Duration(seconds: 60)));
      final pdfBytes = await _buildNotebookPdfBytes(state);
      if (pdfBytes == null) {
        messenger.hideCurrentSnackBar();
        return;
      }
      final link = await share.sharePdf(safeName: safeName, pdfBytes: pdfBytes);
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      await _showShareLinkDialog(link, alreadyShared: false);
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.csShareLinkFailed(e.toString()))));
    }
  }

  Future<void> _showShareLinkDialog(ShareLink link,
      {required bool alreadyShared}) async {
    final l10n = AppLocalizations.of(context);
    final p = HwThemeScope.of(context);
    await showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.csShareLinkTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.csShareLinkBody,
                style: TextStyle(fontSize: 13, color: p.ink2)),
            const SizedBox(height: 12),
            SelectableText(link.url,
                style: TextStyle(
                    fontSize: 13,
                    fontFamily: HwTheme.fontMono,
                    color: p.ink0)),
            const SizedBox(height: 8),
            // When the link predates recent edits, let the user push a fresh
            // PDF to the SAME link (sharePdf reuses the existing share).
            if (alreadyShared)
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l10n.csShareLinkUpdate),
                onPressed: () async {
                  Navigator.pop(dCtx);
                  await _updateSharedPdf();
                },
              ),
            // Revoke lives inside the dialog (not a footer action) so it reads
            // as the destructive, deliberate choice it is — the primary
            // actions stay copy/share.
            TextButton.icon(
              style: TextButton.styleFrom(
                  foregroundColor: HwTheme.syncConflict,
                  padding: EdgeInsets.zero),
              icon: const Icon(Icons.link_off_rounded, size: 18),
              label: Text(l10n.csRevokeLink),
              onPressed: () async {
                Navigator.pop(dCtx);
                await _revokeShareLink(link.id);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text(l10n.csClose),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link.url));
              Navigator.pop(dCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.csShareLinkCopied)));
            },
            child: Text(l10n.csCopyLink),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dCtx);
              SharePlus.instance.share(ShareParams(text: link.url));
            },
            child: Text(l10n.csShare),
          ),
        ],
      ),
    );
  }

  /// Re-uploads a fresh PDF to the already-shared notebook, keeping the same
  /// public link (sharePdf reuses the existing share for the path).
  Future<void> _updateSharedPdf() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final state = ref.read(canvasProvider);
    final share = ref.read(nextcloudShareServiceProvider);
    if (state == null || share == null) return;
    messenger.showSnackBar(SnackBar(
        content: Text(l10n.csShareLinkInProgress),
        duration: const Duration(seconds: 60)));
    try {
      final pdfBytes = await _buildNotebookPdfBytes(state);
      if (pdfBytes == null) {
        messenger.hideCurrentSnackBar();
        return;
      }
      final safeName = _sanitiseForFilename(state.metadata.title);
      final link = await share.sharePdf(safeName: safeName, pdfBytes: pdfBytes);
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.csShareLinkUpdated)));
      await _showShareLinkDialog(link, alreadyShared: true);
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.csShareLinkFailed(e.toString()))));
    }
  }

  Future<void> _revokeShareLink(String shareId) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final share = ref.read(nextcloudShareServiceProvider);
    if (share == null) return;
    try {
      await share.revokeShare(shareId);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.csRevokeLinkDone)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.csShareLinkFailed(e.toString()))));
    }
  }

  /// Render a "Capitolo: TITOLO" cover page for a chapter group.
  Future<Uint8List?> _renderChapterSeparatorPng(
      String chapterTitle, double pageWidth, double pageHeight, double scale) async {
    try {
      final renderW = (pageWidth * scale).round();
      final renderH = (pageHeight * scale).round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
          recorder, Rect.fromLTWH(0, 0, renderW.toDouble(), renderH.toDouble()));
      // Soft warm-paper background
      canvas.drawRect(
        Rect.fromLTWH(0, 0, renderW.toDouble(), renderH.toDouble()),
        Paint()..color = const Color(0xFFFAF7F1),
      );
      // Top accent bar
      canvas.drawRect(
        Rect.fromLTWH(0, 0, renderW.toDouble(), 8 * scale),
        Paint()..color = const Color(0xFFB66744),
      );
      // "CAPITOLO" eyebrow
      final eyebrow = TextPainter(
        text: TextSpan(
          text: AppLocalizations.of(context).csChapterSeparatorEyebrow,
          style: TextStyle(
            color: const Color(0xFF6B6358),
            fontSize: 18 * scale,
            fontWeight: FontWeight.w600,
            letterSpacing: 4 * scale,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      eyebrow.paint(
        canvas,
        Offset(
          (renderW - eyebrow.width) / 2,
          renderH * 0.42,
        ),
      );
      // Chapter title
      final title = TextPainter(
        text: TextSpan(
          text: chapterTitle,
          style: TextStyle(
            color: const Color(0xFF1C1916),
            fontSize: 56 * scale,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.15,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 3,
      )..layout(maxWidth: renderW * 0.8);
      title.paint(
        canvas,
        Offset(
          (renderW - title.width) / 2,
          renderH * 0.46,
        ),
      );
      // Decorative underline
      final underlineY = renderH * 0.46 + title.height + 24 * scale;
      final underlineW = 80 * scale;
      canvas.drawRect(
        Rect.fromLTWH(
            (renderW - underlineW) / 2, underlineY, underlineW, 3 * scale),
        Paint()..color = const Color(0xFFB66744),
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(renderW, renderH);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[Export] Failed to render chapter separator: $e');
      return null;
    }
  }

  /// Copy the current lasso selection as a screenshot to the system clipboard.
  Future<void> _copySelectionAsScreenshot() async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final sel = state.lassoSelection;
    final page = state.currentPage;
    if (sel == null || page == null) return;

    try {
      final bounds = sel.bounds;
      if (bounds.isEmpty) return;

      // Render at 2x for retina quality
      const scale = 2.0;
      final renderW = (bounds.width * scale).round();
      final renderH = (bounds.height * scale).round();
      if (renderW <= 0 || renderH <= 0) return;

      // Build a temporary page containing only the selected elements,
      // translated so the selection bounds start at (0,0).
      final selectedElements = page.layers.content
          .where((e) => sel.selectedIds.contains(
                e.map(stroke: (s) => s.id, text: (t) => t.id,
                    image: (i) => i.id, shape: (s) => s.id, math: (e) => e.id)))
          .toList();

      final croppedPage = page.copyWith(
        layers: page.layers.copyWith(
          background: const BackgroundLayer(type: 'blank', color: 0xFFFFFFFF),
          content: selectedElements,
        ),
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, bounds.width * scale, bounds.height * scale));
      // White background
      canvas.drawRect(
        Rect.fromLTWH(0, 0, bounds.width * scale, bounds.height * scale),
        Paint()..color = Colors.white,
      );
      // Scale then translate so the selection bounds map to (0,0)
      canvas.scale(scale);
      canvas.translate(-bounds.left, -bounds.top);

      // Render only the selected elements via a temporary page. Reuse the
      // live math raster cache (these equations were just on-screen, so
      // they're already rasterized) at the same screen pixel ratio.
      final engine = CanvasRenderEngine(
        pageData: croppedPage,
        zoom: 1.0,
        panOffset: Offset.zero,
        imageCache: state.imageCache,
        mathCache: ref.read(canvasProvider.notifier).mathCache,
        mathPixelRatio: _mathPixelRatio(context),
      );
      // paintPage applies its own translate(offset)+scale(scale), so pass
      // the negative bounds as offset and 1.0 as scale to avoid double-transform.
      engine.paintPage(
        canvas,
        Size(croppedPage.width, croppedPage.height),
        1.0,
        Offset.zero,
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(renderW, renderH);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      picture.dispose();
      if (byteData == null) return;

      final item = DataWriterItem();
      item.add(Formats.png(byteData.buffer.asUint8List()));
      await SystemClipboard.instance?.write([item]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).csSelectionCopiedAsImage), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).csCopyImageError(e.toString()))),
        );
      }
    }
  }

  /// Encode an image element to PNG and push it onto the system clipboard
  /// so it can be pasted into other apps. Fire-and-forget; UI toast is
  /// shown by the caller.
  /// True when the element with [elementId] is an image (so its bytes can
  /// be mirrored to the system clipboard).
  bool _selectedElementIsImage(CanvasState? state, String elementId) {
    final page = state?.currentPage;
    if (page == null) return false;
    for (final e in page.layers.content) {
      final id =
          e.map(stroke: (s) => s.id, text: (t) => t.id, image: (i) => i.id, shape: (s) => s.id, math: (e) => e.id);
      if (id == elementId) {
        return e.maybeMap(image: (_) => true, orElse: () => false);
      }
    }
    return false;
  }

  Future<void> _copyImageElementToSystemClipboard(String elementId) async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final page = state.currentPage;
    if (page == null) return;
    final element = page.layers.content.where((e) {
      return e.map(stroke: (s) => s.id, text: (t) => t.id, image: (i) => i.id, shape: (s) => s.id, math: (e) => e.id) == elementId;
    }).firstOrNull;
    if (element == null) return;

    ImageData? imageData;
    element.map(
      stroke: (_) {}, text: (_) {},
      image: (i) => imageData = i.data,
      shape: (_) {},
      math: (_) {},
    );
    if (imageData == null) return;

    final uiImage = state.imageCache[imageData!.assetPath];
    if (uiImage == null) return;
    try {
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) return;
      final item = DataWriterItem();
      item.add(Formats.png(pngBytes));
      await clipboard.write([item]);
      // Remember our own write so a follow-up Ctrl+V prefers the in-app
      // element (richer) over re-importing these same bytes.
      _seenSystemImageSig = _imageSig(pngBytes);
    } catch (e) {
      debugPrint('[Canvas] System clipboard image write failed: $e');
    }
  }

  /// Small inline confirmation toast. Keeps a short duration so it doesn't
  /// obscure the canvas.
  Future<void> _pasteInAnotherNotebook(BuildContext ctx, CanvasClipboard clip) async {
    // Persist the clipboard globally so the target notebook can pick it up
    ref.read(crossNotebookClipboardProvider.notifier).state = clip;

    // Navigate back to library (pop canvas)
    Navigator.of(ctx).pop();
    // The library will show a banner; user taps a notebook to open it.
    // The cross-notebook clipboard is consumed by _restoreLastPosition.
  }

  void _toast(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show a dialog for choosing export scope.
  Future<_ExportSelection?> _showExportScopeDialog({
    required String singlePageLabel,
    required String chapterLabel,
    required String notebookLabel,
  }) async {
    final state = ref.read(canvasProvider);
    final hasChapters = state != null && state.metadata.chapters.length > 1;
    final hasMultiplePages = state != null && state.document.pages.length > 1;
    final l10n = AppLocalizations.of(context);

    // If only 1 page, skip dialog
    if (!hasMultiplePages) {
      return const _ExportSelection(scope: _ExportScope.currentPage);
    }

    final scope = await showDialog<_ExportScope>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.csExport),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _ExportScope.currentPage),
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(singlePageLabel),
              subtitle: Text(l10n.csPageNumber(state.currentPageIndex + 1)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (hasChapters)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, _ExportScope.currentChapter),
              child: ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text(chapterLabel),
                subtitle: Text(_currentChapterLabel(state)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _ExportScope.entireNotebook),
            child: ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: Text(notebookLabel),
              subtitle: Text(l10n.csPagesCount(state.document.pages.length)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
    if (scope == null) return null;

    // Scope-specific extra prompts
    switch (scope) {
      case _ExportScope.currentPage:
        return const _ExportSelection(scope: _ExportScope.currentPage);

      case _ExportScope.currentChapter:
        // Ask range start/end if the chapter has more than 1 page
        final chapter = _resolveActiveChapter(state);
        final chPagesCount = chapter == null
            ? 1
            : _chapterPageEntries(state, chapter).length;
        if (chPagesCount <= 1) {
          return const _ExportSelection(scope: _ExportScope.currentChapter);
        }
        if (!mounted) return null;
        final range = await _promptPageRange(
          title: l10n.csExportChapterTitle,
          subtitle: chapter?.title ?? l10n.csExportCurrentChapter,
          totalPages: chPagesCount,
        );
        if (range == null) return null;
        return _ExportSelection(
          scope: _ExportScope.currentChapter,
          rangeStart: range.$1,
          rangeEnd: range.$2,
        );

      case _ExportScope.entireNotebook:
        // If the notebook actually has chapters, offer the separator toggle
        if (!hasChapters) {
          return const _ExportSelection(scope: _ExportScope.entireNotebook);
        }
        if (!mounted) return null;
        final addSep = await _promptYesNo(
          title: l10n.csExportNotebookTitle,
          message: l10n.csChapterSeparatorQuestion,
          yesLabel: l10n.csYesWithSeparators,
          noLabel: l10n.csNoPagesOnly,
          initialValue: true,
        );
        if (addSep == null) return null;
        return _ExportSelection(
          scope: _ExportScope.entireNotebook,
          chapterSeparators: addSep,
        );
    }
  }

  /// Page-range picker dialog: returns (start, end) inclusive 1-based or null.
  Future<(int, int)?> _promptPageRange({
    required String title,
    String? subtitle,
    required int totalPages,
  }) async {
    int start = 1;
    int end = totalPages;
    final l10n = AppLocalizations.of(context);
    return showDialog<(int, int)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null) ...[
                  Text(subtitle, style: Theme.of(ctx).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                ],
                Text(l10n.csTotalPages(totalPages),
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 16),
                Text(l10n.csFromPage(start),
                    style: Theme.of(ctx).textTheme.bodyMedium),
                Slider(
                  value: start.toDouble(),
                  min: 1,
                  max: totalPages.toDouble(),
                  divisions: totalPages - 1,
                  label: '$start',
                  onChanged: (v) => setSt(() {
                    start = v.round();
                    if (start > end) end = start;
                  }),
                ),
                Text(l10n.csToPage(end),
                    style: Theme.of(ctx).textTheme.bodyMedium),
                Slider(
                  value: end.toDouble(),
                  min: 1,
                  max: totalPages.toDouble(),
                  divisions: totalPages - 1,
                  label: '$end',
                  onChanged: (v) => setSt(() {
                    end = v.round();
                    if (end < start) start = end;
                  }),
                ),
                const SizedBox(height: 8),
                Text(l10n.csWillExportPages(end - start + 1, start, end),
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.csCancel)),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, (start, end)),
                child: Text(l10n.csExport),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Yes/No picker — returns true/false or null on cancel.
  Future<bool?> _promptYesNo({
    required String title,
    required String message,
    required String yesLabel,
    required String noLabel,
    bool initialValue = true,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx).csCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(noLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yesLabel),
          ),
        ],
      ),
    );
  }

  String _currentChapterLabel(CanvasState state) {
    // Resolve with the same fallback the collector uses so the dialog
    // count stays in sync with the number of pages the PDF will contain
    // (and so "all pages" view still shows a chapter name).
    final ch = _resolveActiveChapter(state);
    if (ch == null) return '';
    final count = _chapterPageEntries(state, ch).length;
    return AppLocalizations.of(context).csChapterLabelWithCount(ch.title, count);
  }

  /// Right-click / long-press on a thumbnail in the bottom strip.
  /// Anchored at [pos] (global), shows quick actions on that page.
  void _showPageStripContextMenu(int pageNumber, Offset pos) async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final pageIndex = pageNumber - 1;
    if (pageIndex < 0 || pageIndex >= state.document.pages.length) return;
    final l10n = AppLocalizations.of(context);

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: 'goto',
          child: Row(children: [
            const Icon(Icons.open_in_new_rounded, size: 18),
            const SizedBox(width: 12),
            Text(l10n.csGoToPage),
          ]),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: Row(children: [
            const Icon(Icons.content_copy_rounded, size: 18),
            const SizedBox(width: 12),
            Text(l10n.csDuplicatePage),
          ]),
        ),
        PopupMenuItem(
          value: 'add_after',
          child: Row(children: [
            const Icon(Icons.add_circle_outline_rounded, size: 18),
            const SizedBox(width: 12),
            Text(l10n.csNewPageAfter),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            const Icon(Icons.delete_outline_rounded,
                size: 18, color: HwTheme.syncConflict),
            const SizedBox(width: 12),
            Text(l10n.csDeletePage,
                style: const TextStyle(color: HwTheme.syncConflict)),
          ]),
        ),
      ],
    );

    if (!mounted || action == null) return;
    final notifier = ref.read(canvasProvider.notifier);
    switch (action) {
      case 'goto':
        notifier.goToPage(pageIndex);
        break;
      case 'duplicate':
        notifier.duplicatePage(pageIndex);
        break;
      case 'add_after':
        notifier.goToPage(pageIndex);
        notifier.addPage();
        break;
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.csDeletePageConfirmTitle),
            content: Text(l10n.csDeletePageConfirmBody(pageNumber)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.csCancel)),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.csDelete),
              ),
            ],
          ),
        );
        if (ok == true) notifier.deletePage(pageIndex);
        break;
    }
  }

  void _showPageManager(CanvasState canvasState) {
    // Capture the canvas-screen messenger up front so SnackBars triggered
    // inside the sheet (delete page, paste, etc.) live in this screen's
    // scope and respect their duration timer even after the sheet closes.
    final parentMessenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => PageManagerSheet(
        initialState: canvasState,
        parentMessenger: parentMessenger,
      ),
    );
  }

  /// Center of the visible viewport mapped to page coordinates.
  Offset _visibleCenterPagePos(CanvasState state) {
    // Use the CANVAS size (screen minus top bar / page strip): _toPageCoords
    // expects canvas-local coordinates, and the render scale is computed on
    // the canvas area, not the full screen.
    final size = _lastCanvasSize == Size.zero
        ? MediaQuery.of(context).size
        : _lastCanvasSize;
    final center = Offset(size.width / 2, size.height / 2);
    final p = _toPageCoords(center, state, size);
    // Infinite canvas has no page bounds — drop content wherever the user
    // is looking. A4 pages clamp so pastes/symbols land on-page.
    if (state.isScratch) return p;
    final pageW = state.currentPage?.width ?? 595;
    final pageH = state.currentPage?.height ?? 842;
    return Offset(p.dx.clamp(50, pageW - 50), p.dy.clamp(50, pageH - 50));
  }

  /// Export bottom sheet with PDF / PNG choices.
  void _showExportSheet() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: HwThemeScope.of(context).paper0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(l10n.csExport,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(l10n.csExportAsPdf),
              onTap: () {
                Navigator.of(ctx).pop();
                _exportAsPdf();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(l10n.csExportAsPng),
              onTap: () {
                Navigator.of(ctx).pop();
                _exportAsPng();
              },
            ),
            const Divider(height: 8),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(l10n.csExportAsNcnote),
              subtitle: Text(l10n.csExportNcnoteSubtitle),
              onTap: () {
                Navigator.of(ctx).pop();
                _exportAsNcnote();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Native export: rebuild the .ncnote ZIP from current state and save it.
  /// Lossless — preserves vector strokes, text, shapes, images, symbols
  /// exactly as they're stored in memory.
  Future<void> _exportAsNcnote() async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final l10n = AppLocalizations.of(context);
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.csGeneratingNcnote)),
        );
      }
      final bytes = sync_svc.SyncService.buildPackageBytes(
        metadata: state.metadata,
        document: state.document,
        pages: state.pages,
        assets: state.assetBytes.isNotEmpty ? state.assetBytes : null,
        symbolLibraries: state.symbolLibraries.isNotEmpty
            ? state.symbolLibraries.map((l) => l.toJson()).toList()
            : null,
      );
      final fileName =
          '${_sanitiseForFilename(state.metadata.title)}.ncnote';
      await _saveOrShare(fileName, bytes, 'application/zip');
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.csNcnoteExported(
                (bytes.length / 1024).toStringAsFixed(1))),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.csNcnoteExportError(e.toString()))));
      }
    }
  }

  /// Misc actions: insert image / change paper / save now.
  /// Runs on-device handwriting recognition on the current page and attaches
  /// the result as a searchable text layer (reusing the PDF text-layer model,
  /// so search and text-selection light up with no extra plumbing). Lazy:
  /// only runs on this explicit action, never per stroke.
  Future<void> _recognizeHandwriting(CanvasState state) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final page = state.currentPage;
    if (page == null) return;
    final pageFileName = state.currentPageFileName;

    messenger.showSnackBar(SnackBar(
        content: Text(l10n.csRecognizeInProgress),
        duration: const Duration(seconds: 30)));
    try {
      final layer = await _ocr.recognizePage(page);
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      if (layer == null || layer.runs.isEmpty) {
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.csRecognizeNothing)));
        return;
      }
      ref.read(canvasProvider.notifier).setPageTextLayer(pageFileName, layer);
      await ref.read(canvasProvider.notifier).save();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text(l10n.csRecognizeDone(layer.runs.length))));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.csRecognizeFailed(e.toString()))));
    }
  }

  void _showMoreSheet(CanvasState state) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: HwThemeScope.of(context).paper0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(l10n.csMore,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (!state.isScratch)
              ListTile(
                leading: const Icon(Icons.slideshow_outlined),
                title: Text(l10n.csPresentationMode),
                subtitle: Text(l10n.csPresentationModeSub),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _enterPresentationMode();
                },
              ),
            if (_ocr.isSupported)
              ListTile(
                leading: const Icon(Icons.text_fields_rounded),
                title: Text(l10n.csRecognizeHandwriting),
                subtitle: Text(l10n.csRecognizeHandwritingSub),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _recognizeHandwriting(state);
                },
              ),
            if (!state.isScratch &&
                ref.read(nextcloudShareServiceProvider) != null)
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: Text(l10n.csShareLink),
                subtitle: Text(l10n.csShareLinkSub),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _shareNotebookLink(state);
                },
              ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded),
              title: Text(l10n.csImportFile),
              subtitle: Text(l10n.csImageOrPdf),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickAndInsertImage(_visibleCenterPagePos(state));
              },
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: Text(l10n.csChangePaperType),
              subtitle: Text(_paperTypeLabel(l10n, state.currentPaperType)),
              onTap: () {
                Navigator.of(ctx).pop();
                _showPaperTypePicker(state);
              },
            ),
            if (PenMonitorService.isSupported)
              ListTile(
                leading: const Icon(Icons.cast_outlined),
                title: Text(l10n.csPenToMonitor),
                subtitle: Text(l10n.csPenToMonitorSubtitle),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showPenMonitorPicker();
                },
              ),
            if (state.isDirty)
              ListTile(
                leading: const Icon(Icons.save_outlined),
                title: Text(l10n.csSaveNow),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _save();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showPaperTypePicker(CanvasState state) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: HwThemeScope.of(context).paper0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(l10n.csPaperType,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final t in PaperType.values)
              ListTile(
                leading: Icon(
                  state.currentPaperType == t
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: state.currentPaperType == t
                      ? Theme.of(ctx).colorScheme.primary
                      : null,
                ),
                title: Text(_paperTypeLabel(l10n, t)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ref.read(canvasProvider.notifier).setPaperType(t);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _paperTypeLabel(AppLocalizations l10n, PaperType type) {
    switch (type) {
      case PaperType.blank: return l10n.csPaperBlank;
      case PaperType.linedNarrow: return l10n.csPaperLinedNarrow;
      case PaperType.linedWide: return l10n.csPaperLinedWide;
      case PaperType.grid: return l10n.csPaperGrid;
      case PaperType.dotted: return l10n.csPaperDotted;
      case PaperType.cornell: return l10n.csPaperCornell;
      case PaperType.isometric: return l10n.csPaperIsometric;
      case PaperType.music: return l10n.csPaperMusic;
    }
  }

  /// Linux: pick which monitor the stylus/tablet should be confined to
  /// (the in-app version of pennina.sh). Maps the pen via xinput so its
  /// active area matches one screen, with a "tutti i monitor" reset entry.
  Future<void> _showPenMonitorPicker() async {
    final service = PenMonitorService();
    final List<PenMonitorInfo> monitors;
    try {
      monitors = await service.listMonitors();
    } catch (e) {
      if (mounted) _toast('$e');
      return;
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: HwThemeScope.of(context).paper0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(l10n.csMapPenToMonitor,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final m in monitors)
              ListTile(
                leading: const Icon(Icons.monitor_outlined),
                title: Text(m.name),
                subtitle: Text(m.geometry),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  try {
                    await service.mapPenToMonitor(m, monitors);
                    if (mounted) _toast(l10n.csPenMappedTo(m.name));
                  } catch (e) {
                    if (mounted) _toast('$e');
                  }
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.fullscreen),
              title: Text(l10n.csAllMonitors),
              subtitle: Text(l10n.csAllMonitorsSubtitle),
              onTap: () async {
                Navigator.of(ctx).pop();
                try {
                  await service.resetPen();
                  if (mounted) _toast(l10n.csPenReset);
                } catch (e) {
                  if (mounted) _toast('$e');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  String _toolTypeString(CanvasTool tool) {
    switch (tool) {
      case CanvasTool.pen: return 'pen';
      case CanvasTool.calligraphy: return 'calligraphy';
      case CanvasTool.ballpoint: return 'ballpoint';
      case CanvasTool.brush: return 'brush';
      case CanvasTool.highlighter: return 'highlighter';
      default: return 'pen';
    }
  }

  String _shapeTypeLabel(String shapeType) {
    final l10n = AppLocalizations.of(context);
    switch (shapeType) {
      case 'line': return l10n.csShapeLine;
      case 'circle': return l10n.csShapeCircle;
      case 'rectangle': return l10n.csShapeRectangle;
      case 'triangle': return l10n.csShapeTriangle;
      case 'arrow': return l10n.csShapeArrow;
      default: return shapeType;
    }
  }
}

class _Dims {
  final int width, height;
  _Dims(this.width, this.height);
}

/// Context menu row with icon, label, and optional shortcut
class _FloatingActionBtn extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final Color? color;

  const _FloatingActionBtn(this.icon, this.label, this.onTap, {this.color});

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final c = color ?? p.ink1;
    final iconWidget = Icon(icon, size: 20, color: c);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              if (label != null)
                Text(label!, style: TextStyle(fontSize: 9, color: c)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small, semi-transparent circular tap target used by presentation mode's
/// corner controls (exit / prev / next) — bounded hit area, unlike a
/// full-screen gesture layer, so it never steals pointer events meant for
/// the laser tool elsewhere on the canvas.
class _PresentationIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _PresentationIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? shortcut;

  const _MenuRow(this.icon, this.label, this.shortcut);

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: p.ink2),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        if (shortcut != null)
          Text(shortcut!, style: TextStyle(fontSize: 11, color: p.ink3)),
      ],
    );
  }
}

/// Group of keyboard-shortcut rows shown in the help dialog. Kept const so
/// the list of (combo, description) pairs can be declared inline without
/// per-build allocations.
class _ShortcutGroup extends StatelessWidget {
  final String title;
  final List<(String, String)> entries;
  const _ShortcutGroup(this.title, this.entries);

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: p.ink2,
          ),
        ),
        const SizedBox(height: 6),
        ...entries.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: p.paper2,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: p.paperEdge, width: 0.5),
                    ),
                    child: Text(
                      e.$1,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(e.$2, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  PDF export — isolate payload
// ═══════════════════════════════════════════════════════════════

/// Payload passed to the background isolate that assembles the PDF.
///
/// Kept intentionally simple (only primitives + Uint8List) so it serializes
/// cleanly across the isolate boundary.
class _PdfPagePayload {
  final double width;
  final double height;
  final Uint8List pngBytes;
  const _PdfPagePayload({
    required this.width,
    required this.height,
    required this.pngBytes,
  });
}

/// Top-level entry point for [compute]: builds a PDF document from the
/// pre-rendered PNGs and returns the encoded bytes. Runs off the UI isolate.
Future<Uint8List> _buildPdfOnIsolate(List<_PdfPagePayload> payloads) async {
  final doc = pw.Document();
  for (final p in payloads) {
    final img = pw.MemoryImage(p.pngBytes);
    doc.addPage(
      pw.Page(
        pageFormat: pw_pdf.PdfPageFormat(
          p.width * pw_pdf.PdfPageFormat.point,
          p.height * pw_pdf.PdfPageFormat.point,
        ),
        margin: pw.EdgeInsets.zero,
        build: (ctx) => pw.Image(img, fit: pw.BoxFit.fill),
      ),
    );
  }
  return Uint8List.fromList(await doc.save());
}

/// Identifies which side button of the pen triggered the native
/// barrel override. Mirrors the two `penFlags` bits the C++ runner
/// reads — see `PenInputChannel` doc comment.
enum _NativeBarrel { upper, lower }

// ═══════════════════════════════════════════════════════════════
//  PDF IMPORT RANGE PICKER
// ═══════════════════════════════════════════════════════════════

/// Page range chosen by the user when importing a PDF. `null` on either
/// side means "no bound on this side" — i.e. start from page 1 or end at
/// the last page. Both null = import every page.
class _PdfImportRange {
  final int? start;
  final int? end;
  const _PdfImportRange({this.start, this.end});
  const _PdfImportRange.all() : start = null, end = null;
}

class _PdfRangeDialog extends StatefulWidget {
  final int estimatedPages;
  const _PdfRangeDialog({required this.estimatedPages});

  @override
  State<_PdfRangeDialog> createState() => _PdfRangeDialogState();
}

class _PdfRangeDialogState extends State<_PdfRangeDialog> {
  /// 'all' or 'range'.
  String _mode = 'all';
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCtrl = TextEditingController(text: '1');
    _endCtrl = TextEditingController(
      text: widget.estimatedPages > 0 ? '${widget.estimatedPages}' : '',
    );
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_mode == 'all') {
      Navigator.of(context).pop(const _PdfImportRange.all());
      return;
    }
    final l10n = AppLocalizations.of(context);
    final start = int.tryParse(_startCtrl.text.trim());
    final end = int.tryParse(_endCtrl.text.trim());
    if (start == null || end == null || start < 1 || end < start) {
      setState(() => _error = l10n.csInvalidRangeError);
      return;
    }
    if (widget.estimatedPages > 0 && start > widget.estimatedPages) {
      setState(() => _error =
          l10n.csPdfStartOutOfRange(widget.estimatedPages));
      return;
    }
    final clampedEnd =
        widget.estimatedPages > 0 ? min(end, widget.estimatedPages) : end;
    Navigator.of(context).pop(_PdfImportRange(start: start, end: clampedEnd));
  }

  @override
  Widget build(BuildContext context) {
    final p = HwThemeScope.of(context);
    final l10n = AppLocalizations.of(context);
    final est = widget.estimatedPages;
    return AlertDialog(
      title: Text(l10n.csImportPdfTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (est > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                l10n.csPdfEstimatedPages(est),
                style: TextStyle(color: p.ink2),
              ),
            ),
          RadioListTile<String>(
            value: 'all',
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v ?? 'all'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(est > 0
                ? l10n.csAllPagesWithCount(est)
                : l10n.csAllPages),
          ),
          RadioListTile<String>(
            value: 'range',
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v ?? 'all'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l10n.csCustomRange),
          ),
          if (_mode == 'range') ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.csFromLabel,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _confirm(),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('–'),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _endCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.csToLabel,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _confirm(),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: HwTheme.syncConflict, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.csCancel),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(l10n.csImport),
        ),
      ],
    );
  }
}


/// Paints the translucent highlight rectangles for a PDF text selection.
class _PdfSelectionPainter extends CustomPainter {
  _PdfSelectionPainter(this.rects, this.color);

  final List<Rect> rects;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty) return;
    final paint = Paint()..color = color;
    for (final r in rects) {
      // Pad a hair so adjacent character boxes read as one continuous run.
      canvas.drawRect(r.inflate(0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_PdfSelectionPainter old) =>
      old.rects != rects || old.color != color;
}
