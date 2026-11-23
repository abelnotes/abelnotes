import 'dart:async';
import 'package:abelnotes/shared/utils/text_controller_scope.dart';
import 'package:abelnotes/features/reference/reference_pane.dart';
import 'package:abelnotes/core/platform/device_class.dart';
import 'package:abelnotes/core/platform/io.dart' as io;
import 'package:abelnotes/features/canvas/presentation/notebook_preview.dart';
import 'package:abelnotes/core/platform/storage_health.dart'
    if (dart.library.js_interop) 'package:abelnotes/core/platform/storage_health_web.dart'
    show isOutOfSpace;
import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/services/desktop_window.dart';
import 'package:abelnotes/core/services/ocr_service.dart';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/utils/chapter_title.dart';
import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/auth_provider.dart'
    show webdavServiceProvider, nextcloudShareServiceProvider;
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/pdf_sharpener.dart';
import 'package:abelnotes/core/providers/offline_providers.dart' show fileServiceProvider;
import 'package:abelnotes/core/providers/cross_notebook_clipboard_provider.dart';
import 'package:abelnotes/core/providers/pending_import_provider.dart';
import 'package:abelnotes/core/providers/preset_colors_provider.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/features/canvas/data/zoom_snapshot.dart';
import 'package:abelnotes/features/canvas/data/pdf_export.dart';
import 'package:abelnotes/features/canvas/presentation/pdf_text_selection.dart';
import 'package:abelnotes/features/search/notebook_find_bar.dart';
import 'package:abelnotes/features/search/region_route.dart' show RegionKind;
import 'package:abelnotes/core/providers/notebook_provider.dart'
    show searchIndexerProvider, syncServiceProvider;
import 'package:abelnotes/core/services/app_windows.dart';
import 'package:abelnotes/features/canvas/presentation/remote_changes_banner.dart';
import 'package:abelnotes/features/canvas/presentation/conflict_resolution_screen.dart';
import 'package:abelnotes/features/canvas/presentation/symbol_library_panel.dart';
import 'package:abelnotes/features/canvas/presentation/math_editor_dialog.dart';
import 'package:abelnotes/features/canvas/presentation/text_editor_dialog.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/core/services/apple_pencil_channel.dart';
import 'package:abelnotes/core/services/oplus_pencil_channel.dart';
import 'package:abelnotes/core/services/pen_input_channel.dart'
    if (dart.library.js_interop) 'package:abelnotes/core/services/pen_input_channel_web.dart';
import 'package:abelnotes/core/services/pen_monitor_service.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_recognizer_service.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/image_circuit.dart';
import 'package:abelnotes/features/canvas/data/photo_ink/photo_ink_strokes.dart';
import 'package:abelnotes/features/modules/module_registry.dart';
import 'package:abelnotes/features/modules/recognize_route.dart';
import 'package:abelnotes/features/modules/selection_action.dart';
import 'package:abelnotes/features/canvas/presentation/multi_finger_tap.dart';
import 'package:abelnotes/features/canvas/presentation/canvas_crop_dialog.dart';
import 'package:abelnotes/features/canvas/presentation/page_manager_sheet.dart';
import 'package:abelnotes/features/pages_tray/application/pages_tray_provider.dart';
import 'package:abelnotes/ui/editor/hw_editor_chrome.dart';
import 'package:abelnotes/ui/primitives/file_drop_zone.dart';
import 'package:abelnotes/ui/primitives/hw_segmented.dart';
import 'package:abelnotes/ui/primitives/page_size_picker.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';
import 'package:abelnotes/ui/theme/hw_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:abelnotes/features/canvas/presentation/editor/back_to_content_pill.dart';
import 'package:abelnotes/features/canvas/presentation/editor/clipboard_flow.dart';
import 'package:abelnotes/features/canvas/presentation/editor/dock_controller.dart';
import 'package:abelnotes/features/canvas/presentation/editor/element_hit_test.dart';
import 'package:abelnotes/features/canvas/presentation/editor/element_handles.dart';
import 'package:abelnotes/features/canvas/presentation/editor/lasso_overlay.dart';
import 'package:abelnotes/features/canvas/presentation/editor/selection_action_bar.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_keyboard.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_pointer_controller.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_types.dart';
import 'package:abelnotes/features/canvas/presentation/editor/export_flow.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_widgets.dart';
import 'package:abelnotes/features/canvas/presentation/editor/page_view_transform.dart';
import 'package:abelnotes/features/canvas/presentation/editor/pdf_import_flow.dart';
import 'package:abelnotes/features/canvas/presentation/editor/find_layer.dart';
import 'package:abelnotes/features/canvas/presentation/editor/pdf_selection_layer.dart';
import 'package:abelnotes/features/canvas/presentation/editor/sync_banners.dart';
import 'package:abelnotes/features/canvas/presentation/editor/canvas_paint_layer.dart';
import 'package:abelnotes/features/canvas/presentation/editor/canvas_pointer_surface.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_banners.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_dock.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_page_strip.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_states.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_tool_panel.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_top_bar.dart';
import 'package:abelnotes/features/canvas/presentation/editor/pen_cursor_layer.dart';

/// What the editor's route completes with when the user leaves: the save
/// still running. Wrapped so the route completes at the pop, not after it.
class EditorExit {
  const EditorExit(this.save);
  final Future<void> save;
}

/// Which view the editor shows: nothing to edit, a missing page, or the page.
enum _EditorView { closed, noPage, page }

class CanvasScreen extends ConsumerStatefulWidget {
  const CanvasScreen({super.key});

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends ConsumerState<CanvasScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final ClipboardFlow _clipboard = ClipboardFlow(
    context: context,
    ref: ref,
    insertImage: _insertImage,
    visibleCenterPagePos: _visibleCenterPagePos,
    mathPixelRatio: CanvasPaintLayer.mathPixelRatio,
  );

  late final EditorKeyboard _keyboard = EditorKeyboard(
    context: context,
    ref: ref,
    clipboard: _clipboard,
    findHasFocus: () => _findFocus.hasFocus,
    isFindOpen: () => _find.isOpen,
    openFind: _openFind,
    closeFind: _closeFind,
    save: _save,
    pickTool: _pickTool,
    showShortcutHelp: _showShortcutHelp,
    toast: _toast,
    isPresentationMode: () => _presentationMode,
    exitPresentationMode: _exitPresentationMode,
    isPopupOpen: () => _popupOpen,
    closePopup: _closePopup,
  );

  late final PdfImportFlow _pdfImport = PdfImportFlow(
    context: context,
    ref: ref,
    getSharpener: () => _pdfSharpener,
    reloadPdfSources: reloadPdfSources,
  );

  late final ExportFlow _export = ExportFlow(
    context: context,
    ref: ref,
    currentChapterLabel: _currentChapterLabel,
  );

  bool _isSaving = false;
  Future<void>? _saveInFlight;
  bool _closing = false;
  /// Set while a Back is leaving, and for good once it popped: a second
  /// Back would pop the library too (black screen).
  bool _leaving = false;
  bool _popped = false;
  /// One-shot latch for the auto-pop in [build]'s no-notebook fallback, so a
  /// second rebuild while the route is already animating out doesn't queue a
  /// second pop (which would take the library with it).
  bool _autoPopScheduled = false;
  // Drag-left to create new page / drag-right to go to previous page
  final ValueNotifier<PageHint> _pageHint = ValueNotifier(PageHint.none);

  // ── New chrome state (warm-paper redesign) ─────────────────────
  /// The tool panel: shown or not, and where it was asked to open (see below).
  /// A notifier so opening it rebuilds only the panel.
  final ValueNotifier<({bool open, ({Offset tip, Rect area})? at})> _popup =
      ValueNotifier((open: false, at: null));
  bool get _popupOpen => _popup.value.open;
  void _closePopup() {
    if (_popup.value.open) _popup.value = (open: false, at: _popup.value.at);
  }

  /// Where the tool panel opens instead of beside the dock: next to the
  /// Pencil's tip after a squeeze, with the canvas area it must stay in,
  /// both in body-stack ([_stackKey]) coordinates. The dock clears it when
  /// it opens the panel itself.

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

  // ── Movable tool dock ──────────────────────────────────────────
  // Edge and alignment persist in AppSettings.toolDock; drag and fly state
  // live in the controller.
  final GlobalKey _stackKey = GlobalKey();
  late final DockController _dock = DockController(
    vsync: this,
    context: context,
    ref: ref,
    stackKey: _stackKey,
    isMounted: () => mounted,
    cancelLongPress: _ptr.cancelLongPressTimer,
    closePopup: _closePopup,
  );

  late final EditorPointerController _ptr = EditorPointerController(
    ref: ref,
    canvasStackKey: _canvasStackKey,
    zoomSnapshot: _zoomSnapshot,
    pdfTileVersion: _pdfTileVersion,
    isMounted: () => mounted,
    ensurePdfTextSel: _ensurePdfTextSel,
    handleTextTool: _handleTextTool,
    editMath: _editMath,
    pickAndInsertImage: _pickAndInsertImage,
    showContextMenu: _showContextMenu,
    checkPageDrag: _checkPageDrag,
    commitOrCancelPageDrag: _commitOrCancelPageDrag,
    clearPageHints: _clearPageHints,
    commitLassoTransform: _commitLassoTransform,
    tryOpenLinkAt: _tryOpenLinkAt,
    maybeHintMouseDraw: _maybeHintMouseDraw,
  );

  // Cached Listenable.merge for the CustomPaint.repaintNotifier — avoids
  // rebuilding the composite on every parent rebuild (each new merge re-
  // subscribes to both underlying notifiers, which is non-trivial work on
  // the hot draw path).
  // Web only: raster stand-in while zooming, repaints crisp once it settles.
  final ZoomSnapshot _zoomSnapshot = ZoomSnapshot();
  // ── Sharp zoom of imported PDF pages (see pdf_sharpener.dart) ──
  PdfSharpener? _pdfSharpener;
  final ValueNotifier<int> _pdfTileVersion = ValueNotifier(0);
  late final ViewportSettler _pdfSettler = ViewportSettler(_showPdfViewport);
  ProviderSubscription<Object?>? _pdfNotebookSub;
  ProviderSubscription<Object?>? _pdfViewportSub;
  // Kept so dispose can detach without ref, which may already be unusable.
  CanvasNotifier? _pdfListenNotifier;

  void _watchPdfSources() {
    _pdfNotebookSub = ref.listenManual<String?>(
      canvasProvider.select((s) => s?.metadata.id),
      (_, id) => _openPdfSharpener(id),
      fireImmediately: true,
    );
    _pdfViewportSub = ref.listenManual<Object?>(
      canvasProvider.select((s) =>
          s == null ? null : (s.zoom, s.panOffset, s.currentPageFileName)),
      (_, __) => _pdfSettler.poke(),
    );
    final notifier = ref.read(canvasProvider.notifier);
    _pdfListenNotifier = notifier;
    notifier.imageCacheVersion.addListener(_pdfSettler.poke);
    notifier.pdfSourcesVersion.addListener(reloadPdfSources);
  }

  Future<void> _openPdfSharpener(String? id) async {
    if (id != null && id == _pdfSharpener?.notebookId) return;
    _pdfSharpener?.version.removeListener(_bumpPdfTiles);
    _pdfSharpener?.dispose();
    _pdfSharpener = null;
    if (id == null) return;
    final sharpener = PdfSharpener(
      id,
      ref.read(fileServiceProvider).notebookStoreDir(id),
      cacheBytes: pdfTileCacheBytes(defaultTargetPlatform),
    );
    _pdfSharpener = sharpener;
    sharpener.version.addListener(_bumpPdfTiles);
    await reloadPdfSources();
  }

  /// Re-reads the notebook's source PDFs, after an import or a sync.
  Future<void> reloadPdfSources() async {
    final sharpener = _pdfSharpener;
    if (sharpener == null) return;
    await sharpener.reload();
    if (mounted && identical(_pdfSharpener, sharpener)) _pdfSettler.poke();
  }

  void _bumpPdfTiles() => _pdfTileVersion.value++;

  void _showPdfViewport() {
    if (!mounted) return;
    final sharpener = _pdfSharpener;
    final s = ref.read(canvasProvider);
    final size = _ptr.lastCanvasSize;
    if (sharpener == null || s == null || size.isEmpty) return;
    final page = s.currentPage;
    if (page == null) return;
    final a = _ptr.toPageCoords(Offset.zero, s, size);
    final b = _ptr.toPageCoords(Offset(size.width, size.height), s, size);
    sharpener.showViewport(
      page: page,
      visiblePage: Rect.fromPoints(a, b),
      screenDensity: s.zoom *
          _ptr.getRenderScale(s, size) *
          MediaQuery.devicePixelRatioOf(context),
      decoded: s.imageCache,
    );
  }

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

  /// Saves in a row that left the notebook dirty, for the retry backoff.
  int _stuckSaves = 0;

  /// The notice shown while local writes fail, closed once one succeeds.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _localErrorBar;
  ValueNotifier<Object?>? _localErrorSource;
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
  ScaffoldMessengerState? _hintMessenger;
  PdfTextLayer? _pdfTextSelLayer;
  bool _mouseDrawHintShown = false;
  void _maybeHintMouseDraw(List<Offset> marquee) {
    final live = ref.read(canvasProvider);
    if (_mouseDrawHintShown ||
        live == null ||
        !EditorPointerController.mouseSelectTools.contains(live.currentTool) ||
        ref.read(appSettingsProvider).mouseDraws) {
      return;
    }
    var length = 0.0;
    for (var i = 1; i < marquee.length; i++) {
      length += (marquee[i] - marquee[i - 1]).distance;
    }
    if (length < 40) return;
    _mouseDrawHintShown = true;
    final l10n = AppLocalizations.of(context);
    final messenger = _hintMessenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l10n.qcMouseSelectHint),
        persist: false,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: l10n.qcMouseDrawEnable,
          onPressed: () =>
              ref.read(appSettingsProvider.notifier).setMouseDraws(true),
        ),
      ));
  }

  /// A dock button was tapped by [kind]. The dock is part of the canvas as
  /// far as "which device is in the user's hand" goes: without this, hovering
  /// the mouse and then tapping the dock with the pen kept `mouseDraws`
  /// logic pointed at the mouse — so a pen tap on the ALREADY-ACTIVE pen
  /// button was read as "switch to pen" (the dock was masquerading as lasso
  /// for the mouse) and silently opted the mouse into drawing instead of
  /// opening the tool popup. `unknown` comes from the semantics/screen-reader
  /// path and says nothing about the physical device, so it's ignored.
  void _noteDockTapDevice(PointerDeviceKind kind) {
    if (kind == PointerDeviceKind.unknown) return;
    final isMouse = kind == PointerDeviceKind.mouse;
    if (_ptr.lastPointerWasMouse == isMouse) return;
    _ptr.lastPointerWasMouse = isMouse;
  }

  /// Explicit tool pick — dock tap or keyboard shortcut, as opposed to the
  /// transient barrel-button / native-barrel overrides (which restore
  /// afterwards and must NOT go through here). If the mouse was the last
  /// input to touch the canvas, picking an ink tool means "yes, draw with
  /// the mouse now" and picking lasso means "back to pure selection" — so
  /// `mouseDraws` always tracks the user's last deliberate choice instead of
  /// being a separate hidden toggle the toolbar selection can contradict.
  void _pickTool(CanvasTool tool) {
    ref.read(canvasProvider.notifier).setTool(tool);
    // Remembered across notebooks and restarts, so the editor reopens with
    // the tool the user last held instead of resetting under them.
    ref.read(appSettingsProvider.notifier).setLastTool(tool.name);
    if (_ptr.lastPointerWasMouse != true) return;
    if (EditorPointerController.mouseSelectTools.contains(tool)) {
      ref.read(appSettingsProvider.notifier).setMouseDraws(true);
    } else if (tool == CanvasTool.lasso) {
      ref.read(appSettingsProvider.notifier).setMouseDraws(false);
    }
  }

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

  // ── Keyboard shortcuts ──
  final _focusNode = FocusNode();

  // ── Find in notebook ──
  final _find = NotebookFindController();
  final _findText = TextEditingController();
  final _findFocus = FocusNode();
  bool _pendingFindTaken = false;

  @override
  void initState() {
    super.initState();
    _mirrorSub = AppWindows.saved.listen(_onOtherWindowSaved);
    webTouchDevice.addListener(_onWebTouchDeviceChanged);
    PaintingBinding.instance.systemFonts.addListener(_onSystemFonts);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_ptr.onGlobalPointerEvent);
    _startAutoSave();
    _localErrorSource = ref.read(canvasProvider.notifier).localSaveError
      ..addListener(_onLocalSaveError);
    _watchForPendingImport();
    // Hook the Windows-side pen-button bridge. No-op on other
    // platforms. See PenInputChannel for why this exists.
    _watchForLassoCleared();
    _watchPdfSources();
    PenInputChannel.register(
      onBarrel: (down) => _ptr.onNativeBarrelChange(NativeBarrel.lower, down),
      onInverted: (down) => _ptr.onNativeBarrelChange(NativeBarrel.upper, down),
      onBarrelPen: _ptr.onBarrelPen,
    );
    OplusPencilChannel.register(_onOplusDoubleTap);
    // iPad app only: the Apple Pencil's double-tap and squeeze.
    _watchToolChanges();
    ApplePencilChannel.register(
      onDoubleTap: _onPencilDoubleTap,
      onSqueeze: _runPencilAction,
    );
    // Linux-only: receive stylus pressure the GTK embedder drops. No-op
    // elsewhere. See LinuxPenPressure / _ptr.penPressure.
    LinuxPenPressure.register(onProximityOut: _ptr.clearPenHover);
    // Let the provider's save-prep pause while a stroke is mid-flight.
    // The ActiveStrokeNotifier is screen-local (it bypasses Riverpod for
    // perf), so the provider can't see pen-down state without this probe.
    // Cleared in dispose() before the notifier itself is disposed.
    ref.read(canvasProvider.notifier).strokeActiveProbe = () => _ptr.activeStroke.isActive;
    // A tray action can ask for this notebook's Pages: the library set the
    // request before opening us, or the tray pill sets it while we are open.
    _trayNavSub = ref.listenManual<TrayNavRequest?>(pagesTrayNavProvider, (_, next) {
      if (next != null) _onTrayNav(next);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final req = ref.read(pagesTrayNavProvider);
      if (req != null && mounted) _onTrayNav(req);
    });
    // The speed-width rule is app-wide (main sets it too): make sure it is in
    // place before the first page paints.
    CanvasRenderEngine.speedWidth = ref.read(appSettingsProvider).speedWidth;
    // A library search hit opened this notebook: show its words once the
    // notebook and its pages are there.
    _pendingFindSub = ref.listenManual<Object?>(
        pendingFindProvider, (_, __) => _takePendingFind());
    _pendingFindNotebookSub = ref.listenManual<String?>(
        canvasProvider.select((s) => s?.metadata.id),
        (_, __) => _takePendingFind());
    WidgetsBinding.instance.addPostFrameCallback((_) => _takePendingFind());
  }

  ProviderSubscription<Object?>? _pendingFindSub;
  ProviderSubscription<Object?>? _pendingFindNotebookSub;

  /// Tool the editor arms when a notebook opens: the one the user last
  /// picked, or — the first time — pan on a phone/tablet and the pen on
  /// desktop. Starting a touch device in navigate mode means a resting hand
  /// can't scribble on the page, and arming the pen is one tap in the dock.
  CanvasTool _startupTool() {
    final saved = ref.read(appSettingsProvider).lastTool;
    if (saved != null) {
      for (final t in CanvasTool.values) {
        if (t.name == saved) return t;
      }
    }
    return _isMobilePlatform ? CanvasTool.pan : CanvasTool.pen;
  }

  /// Applied once, on the first build that has a loaded notebook —
  /// `setTool` is a no-op while the canvas state is still null.
  bool _startupToolApplied = false;
  void _applyStartupTool() {
    if (_startupToolApplied) return;
    _startupToolApplied = true;
    final tool = _startupTool();
    if (tool == ref.read(canvasProvider)?.currentTool) return;
    ref.read(canvasProvider.notifier).setTool(tool);
  }

  /// Two fingers tapping undo, three redo (Settings → Finger tap to undo).
  late final MultiFingerTapDetector _fingerTaps =
      MultiFingerTapDetector(onTap: _onFingerTap);

  /// What the last finger tap did, shown briefly at the top of the canvas so
  /// an undo nobody meant (a palm) doesn't go unnoticed.
  final ValueNotifier<({bool redo, bool visible})> _tapFlash =
      ValueNotifier((redo: false, visible: false));
  Timer? _tapFlashTimer;

  void _onFingerTap(int fingers) {
    if (!mounted || !ref.read(appSettingsProvider).tapUndo) return;
    final notif = ref.read(canvasProvider.notifier);
    if (notif.pagesLoading.value || notif.isPreview) return;
    if (fingers == 2) {
      if (!notif.canUndo) return;
      notif.undo();
    } else {
      if (!notif.canRedo) return;
      notif.redo();
    }
    _tapFlash.value = (redo: fingers != 2, visible: true);
    _tapFlashTimer?.cancel();
    _tapFlashTimer = Timer(const Duration(milliseconds: 900), () {
      _tapFlash.value = (redo: _tapFlash.value.redo, visible: false);
    });
    HapticFeedback.selectionClick();
  }

  /// The tool before the latest tool change, and the latest one that wasn't
  /// an eraser: where the Pencil's double-tap goes back to.
  CanvasTool? _previousTool;
  CanvasTool? _lastNonEraserTool;

  static bool _isEraser(CanvasTool t) =>
      t == CanvasTool.eraserStandard || t == CanvasTool.eraserStroke;

  void _watchToolChanges() {
    _toolChangeSub = ref.listenManual<CanvasTool?>(
      canvasProvider.select((s) => s?.currentTool),
      (prev, next) {
        if (prev == null || next == null || prev == next) return;
        _previousTool = prev;
        if (!_isEraser(prev)) _lastNonEraserTool = prev;
      },
    );
  }

  /// OPPO / OnePlus pen gesture, following the system's selected action.
  void _onOplusDoubleTap(int mode) {
    // Never mid-stroke; the rest is checked by [_runPencilAction].
    if (_ptr.stylusDown || _ptr.activeStroke.isActive) return;
    final action = oplusPencilActionForMode(mode);
    if (action != null) _runPencilAction(action, null);
  }

  /// Apple Pencil double-tap; Settings → Pencil double-tap can turn it off.
  void _onPencilDoubleTap(String action, Offset? at) {
    if (!ref.read(appSettingsProvider).pencilDoubleTap) return;
    _runPencilAction(action, at);
  }

  /// An Apple Pencil double-tap or squeeze, doing what the user chose for it
  /// in the system's Apple Pencil settings (see [ApplePencilChannel]). [at]
  /// is where the Pencil hovers, in global coordinates, when known.
  void _runPencilAction(String action, Offset? at) {
    if (!mounted) return;
    // Only the canvas in front, once open and editable.
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final editor = ref.read(canvasProvider.notifier);
    if (editor.pagesLoading.value || editor.isPreview) return;
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final notif = ref.read(canvasProvider.notifier);
    final current = state.currentTool;
    switch (action) {
      case 'switchEraser':
        notif.setTool(_isEraser(current)
            ? _lastNonEraserTool ?? CanvasTool.pen
            : notif.lastEraserMode);
        break;
      case 'switchPrevious':
        final prev = _previousTool;
        if (prev == null) return;
        notif.setTool(prev);
        break;
      // iPadOS has three palettes; the app has one, the tool panel.
      case 'showColorPalette':
      case 'showInkAttributes':
      case 'showContextualPalette':
        if (_presentationMode) return;
        _toggleToolPanelAt(at);
        break;
      default:
        return;
    }
    HapticFeedback.selectionClick();
  }

  /// Opens the tool panel next to [global] (the Pencil's tip), or beside
  /// the dock as usual when that is unknown; closes it when it is open.
  void _toggleToolPanelAt(Offset? global) {
    // The panel is laid out in the body stack, which also holds the top bar.
    final body = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final canvas =
        _canvasStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (_popupOpen) {
      _closePopup();
      return;
    }
    _popup.value = (
      open: true,
      at: global != null && body != null && canvas != null
          ? (
              tip: body.globalToLocal(global),
              area: body.globalToLocal(canvas.localToGlobal(Offset.zero)) &
                  canvas.size,
            )
          : null,
    );
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
  /// The guard `_ptr.activeNativeBarrel == null` ensures we only fire in
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
  ProviderSubscription<Object?>? _toolChangeSub;
  ProviderSubscription<Object?>? _trayNavSub;

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
        if (_ptr.activeNativeBarrel == null && _ptr.nativeBarrelPreviousTool != null) {
          final tool = _ptr.nativeBarrelPreviousTool!;
          _ptr.nativeBarrelPreviousTool = null;
          ref.read(canvasProvider.notifier).setTool(tool);
        } else if (!_ptr.barrelButtonOverride && _ptr.barrelButtonPreviousTool != null) {
          final tool = _ptr.barrelButtonPreviousTool!;
          _ptr.barrelButtonPreviousTool = null;
          ref.read(canvasProvider.notifier).setTool(tool);
        }
      },
    );
  }

  /// Waits for the notebook to finish loading, then runs any pending share
  /// import (files dropped in via the Android/iOS share sheet). Fires once.
  ///
  /// Listens to a narrow select instead of the full state so the callback
  /// doesn't run 60×/s during pan/zoom.
  void _watchForPendingImport() {
    bool handled = false;
    // The id of the loaded notebook, null until its current page is there:
    // canvasProvider is global and may still hold the previous notebook.
    _pendingImportSub = ref.listenManual<String?>(
      canvasProvider
          .select((s) => s?.currentPage == null ? null : s!.metadata.id),
      (_, loadedId) {
        if (handled || loadedId == null) return;
        final pending = ref.read(pendingImportProvider);
        if (pending == null) return;
        if (pending.notebookId != null && pending.notebookId != loadedId) {
          return;
        }
        handled = true;
        // After the frame: this can fire from initState, where a provider
        // must not be written.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(pendingImportProvider.notifier).state = null;
          if (ref.read(canvasProvider)?.metadata.id != loadedId) return;
          _runPendingImport(pending);
        });
      },
      // The notebook is often loaded before this screen is pushed.
      fireImmediately: true,
    );
  }

  Future<void> _runPendingImport(PendingImport pending) async {
    if (!mounted) return;
    final notifier = ref.read(canvasProvider.notifier);
    if (pending.newChapterTitle != null && pending.newChapterTitle!.isNotEmpty) {
      notifier.addChapter(pending.newChapterTitle!);
      // The chapter switch rebuilds the page view; let it settle before the
      // import opens its dialog.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    } else if (pending.targetChapterId != null) {
      notifier.setActiveChapter(pending.targetChapterId);
      // Imported pages follow the chapter's last page.
      final last = ref.read(canvasProvider)?.document.pages.lastIndexWhere(
              (p) => p.chapterId == pending.targetChapterId) ??
          -1;
      if (pending.atEnd && last >= 0) notifier.goToPage(last);
    } else if (pending.atEnd) {
      final count = ref.read(canvasProvider)?.pageCount ?? 0;
      if (count > 0) notifier.goToPage(count - 1);
    }
    for (final path in pending.filePaths) {
      if (!mounted) break;
      try {
        final file = io.File(path);
        if (!await file.exists()) {
          debugPrint('[Canvas] Pending import: no file at $path');
          continue;
        }
        final bytes = await file.readAsBytes();
        final name = path.split(io.Platform.pathSeparator).last;
        final state = ref.read(canvasProvider);
        final pg = state?.currentPage;
        final center = pg == null
            ? const Offset(100, 100)
            : Offset(pg.width / 2, pg.height / 2);
        if (name.toLowerCase().endsWith('.pdf')) {
          await _pdfImport.insertPdf(bytes, name, center);
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

  StreamSubscription<String>? _mirrorSub;
  Timer? _mirrorReload;

  /// The window writing the mirrored notebook saved: show its new state.
  void _onOtherWindowSaved(String id) {
    if (ref.read(windowMirrorProvider) != id) return;
    _mirrorReload?.cancel();
    _mirrorReload =
        Timer(const Duration(milliseconds: 400), () => _reloadMirror(id));
  }

  Future<void> _reloadMirror(String id) async {
    final st = ref.read(canvasProvider);
    if (st == null || !mounted) return;
    final page = st.currentPageIndex;
    final mirrorId = st.metadata.id;
    try {
      final c = await readNotebookReadOnly(
          ref.read(fileServiceProvider), ref.read(syncServiceProvider), id);
      if (!mounted || ref.read(windowMirrorProvider) != id) return;
      final notifier = ref.read(canvasProvider.notifier);
      await notifier.openNotebook(
        metadata: c.metadata.copyWith(id: mirrorId),
        document: c.document.copyWith(notebookId: mirrorId),
        pages: c.pages,
        remotePath: '',
        assets: c.assets,
        symbolLibraries:
            c.symbolLibraries.map((j) => SymbolLibrary.fromJson(j)).toList(),
        preview: true,
      );
      if (c.document.pages.isNotEmpty) {
        notifier.goToPage(page.clamp(0, c.document.pages.length - 1));
      }
    } catch (e) {
      debugPrint('[Canvas] mirror reload failed: $e');
    }
  }

  @override
  void dispose() {
    _mirrorSub?.cancel();
    _mirrorReload?.cancel();
    _zoomSnapshot.dispose();
    _tapFlashTimer?.cancel();
    _tapFlash.dispose();
    webTouchDevice.removeListener(_onWebTouchDeviceChanged);
    PaintingBinding.instance.systemFonts.removeListener(_onSystemFonts);
    _dock.dispose();
    _pageHint.dispose();
    _popup.dispose();
    _hintMessenger?.hideCurrentSnackBar();
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _ptr.onGlobalPointerEvent,
    );
    PenInputChannel.unregister();
    OplusPencilChannel.unregister(_onOplusDoubleTap);
    ApplePencilChannel.unregister(_onPencilDoubleTap);
    LinuxPenPressure.unregister();
    // Flush a pending deferred stylus commit so a partial stroke isn't lost on close.
    _ptr.flushOnDispose();
    // Detach the probe BEFORE disposing the notifier it closes over —
    // an in-flight save polls it from the provider side.
    try {
      ref.read(canvasProvider.notifier).strokeActiveProbe = null;
    } catch (_) {}
    _ptr.dispose();
    _autoSaveDebounce?.cancel();
    _autoSaveMaxWait?.cancel();
    _localErrorSource?.removeListener(_onLocalSaveError);
    // Close the manual provider subscriptions opened in initState.
    _lassoClearedSub?.close();
    _pdfNotebookSub?.close();
    _pdfViewportSub?.close();
    final pdfNotifier = _pdfListenNotifier;
    if (pdfNotifier != null) {
      try {
        pdfNotifier.imageCacheVersion.removeListener(_pdfSettler.poke);
        pdfNotifier.pdfSourcesVersion.removeListener(reloadPdfSources);
      } catch (_) {}
    }
    _pdfSettler.dispose();
    _pdfSharpener?.dispose();
    _pdfTileVersion.dispose();
    _pendingImportSub?.close();
    _autoSaveSub?.close();
    _toolChangeSub?.close();
    _trayNavSub?.close();
    _pendingFindSub?.close();
    _pendingFindNotebookSub?.close();
    _fingerTaps.dispose();
    _ocr.dispose();
    _focusNode.dispose();
    try {
      _findWaitsOn?.removeListener(_onPagesLoadedForFind);
      _findIndexRevision?.removeListener(_onFindIndexChanged);
    } catch (_) {}
    _find.dispose();
    _findText.dispose();
    _findFocus.dispose();
    _pdfTextSelController?.dispose();
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
    if (state == null || !state.isDirty) return;
    // Defer the save while a stroke is mid-flight OR an eraser drag is
    // in progress. _saveInner does enough sync work (state.copyWith,
    // setState in the canvas chrome) plus a 50 MB ZIP rebuild via
    // compute() to drop many frames — a >1.2 s eraser drag would
    // otherwise stall mid-gesture. eraserCursorPos is non-null only
    // between pointer-down and pointer-up on an eraser tool, so it's
    // the right signal. Save fires the moment the pen/eraser lifts,
    // when the next dirty transition re-arms the debounce.
    if (_ptr.activeStroke.isActive || state.eraserCursorPos != null) {
      _autoSaveDebounce?.cancel();
      _autoSaveDebounce = Timer(const Duration(milliseconds: 600), _triggerAutoSave);
      return;
    }
    if (_isSaving) {
      // The running save may wait minutes on the network: keep the disk
      // current meanwhile and come back, instead of dropping this tick.
      unawaited(ref.read(canvasProvider.notifier).persistLocalNow());
      _autoSaveDebounce?.cancel();
      _autoSaveDebounce =
          Timer(const Duration(milliseconds: 1500), _triggerAutoSave);
      return;
    }
    _save(silent: true);
  }

  /// A save that leaves the notebook dirty (a guard held it back, the lock
  /// timed out) produces no clean-to-dirty edge, so nothing would ever
  /// autosave again: schedule the next attempt here.
  void _rearmAutoSaveIfStillDirty() {
    if (!mounted || _closing) return;
    final dirty = ref.read(canvasProvider)?.isDirty ?? false;
    if (!dirty) {
      _stuckSaves = 0;
      return;
    }
    _stuckSaves++;
    final secs = (2 * (1 << (_stuckSaves - 1).clamp(0, 4))).clamp(2, 30);
    _autoSaveDebounce?.cancel();
    _autoSaveDebounce = Timer(Duration(seconds: secs), _triggerAutoSave);
  }

  void _onLocalSaveError() {
    if (!mounted) return;
    final err = _localErrorSource?.value;
    if (err == null) {
      _localErrorBar?.close();
      _localErrorBar = null;
      return;
    }
    if (_localErrorBar != null) return;
    final l10n = AppLocalizations.of(context);
    final bar = ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isOutOfSpace(err)
          ? l10n.csLocalSaveFailedNoSpace
          : l10n.csLocalSaveFailed),
      duration: const Duration(days: 1),
      showCloseIcon: true,
    ));
    _localErrorBar = bar;
    bar.closed.then((_) {
      if (identical(_localErrorBar, bar)) _localErrorBar = null;
    });
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
      _ptr.flushDeferredCommit();

      // Disk first and unconditionally: a save already running may be
      // waiting on the network, and the OS can kill us any moment now.
      unawaited(ref.read(canvasProvider.notifier).persistLocalNow());
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
      _rearmAutoSaveIfStillDirty();
    }
  }

  // ── Find in notebook ──

  /// Top of the find bar in canvas coordinates (below a top-edge dock).
  /// Below a dock parked on the top edge.
  double get _findBarTop =>
      ref.read(appSettingsProvider).toolDock.edge == 'top' ? 76 : 12;
  static const double _findBarHeight = 48;

  /// Handwriting of this notebook from the search index (lines and where
  /// each character is), refreshed while find is open and the index moves.
  Future<void> _loadFindInk() async {
    final s = ref.read(canvasProvider);
    if (s == null) return;
    try {
      final ink = await ref.read(searchIndexerProvider).index.inkLines(s.metadata.id);
      if (!mounted || !_find.isOpen) return;
      final cur = ref.read(canvasProvider);
      if (_find.setInk(ink, fromPage: cur?.currentPageIndex ?? 0)) _revealFindMatch();
    } catch (e) {
      debugPrint('[Find] handwriting not loaded: $e');
    }
  }

  ValueNotifier<int>? _findIndexRevision;

  void _openFind({String? query, bool focus = true}) {
    if (ref.read(canvasProvider) == null) return;
    if (!_find.isOpen) {
      unawaited(_loadFindInk());
      _findIndexRevision = ref.read(searchIndexerProvider).revision
        ..addListener(_onFindIndexChanged);
    }
    _find.open();
    if (query != null) {
      _findText.text = query;
      _onFindChanged(query);
    }
    if (!focus) return;
    void take() {
      if (!mounted || !_find.isOpen) return;
      _findFocus.requestFocus();
      _findText.selection =
          TextSelection(baseOffset: 0, extentOffset: _findText.text.length);
    }
    // Field already on screen: now, so the next key is typed into it. A new
    // bar exists from the next frame on.
    if (_findFocus.context != null) {
      take();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => take());
    }
  }

  void _onFindIndexChanged() => unawaited(_loadFindInk());

  void _closeFind() {
    _findIndexRevision?.removeListener(_onFindIndexChanged);
    _findIndexRevision = null;
    _find.close();
    _findText.clear();
    _focusNode.requestFocus();
  }

  void _onFindChanged(String query) {
    final s = ref.read(canvasProvider);
    if (s == null) return;
    _find.setQuery(query, s.document, s.pages, s.currentPageIndex);
    _revealFindMatch();
  }

  void _findStep(int by) {
    final s = ref.read(canvasProvider);
    if (s != null) _find.sync(s.document, s.pages);
    _find.step(by);
    _revealFindMatch();
  }

  /// Turns to the current match's page and pans it into view when hidden.
  void _revealFindMatch() {
    final m = _find.currentMatch;
    final notifier = ref.read(canvasProvider.notifier);
    final before = ref.read(canvasProvider);
    if (m == null || before == null || m.pageIndex >= before.pageCount) return;
    final chapter = before.document.pages[m.pageIndex].chapterId;
    if (before.activeChapterId != null && before.activeChapterId != chapter) {
      notifier.setActiveChapter(chapter);
    }
    if (ref.read(canvasProvider)?.currentPageIndex != m.pageIndex) {
      notifier.goToPage(m.pageIndex);
    }
    final s = ref.read(canvasProvider);
    final vp = notifier.viewportSize;
    final page = s?.currentPage;
    if (s == null || vp == null || page == null) return;
    final rects = _find.rectsOf(page, m);
    if (rects.isEmpty) return;
    final box = rects.reduce((a, b) => a.expandToInclude(b));
    final rs = _ptr.getRenderScale(s, vp);
    final center = _ptr.getCenterOffset(s, vp);
    Offset toScreen(Offset pt, double zoom, Offset pan) =>
        (pt * rs + center) * zoom + pan;
    final visible = Rect.fromLTRB(
        24, _findBarTop + _findBarHeight + 12, vp.width - 24, vp.height - 72);
    if (visible.width <= 0 || visible.height <= 0) return;
    final tl = toScreen(box.topLeft, s.zoom, s.panOffset);
    final br = toScreen(box.bottomRight, s.zoom, s.panOffset);
    if (visible.contains(tl) && visible.contains(br)) return;
    final w = br.dx - tl.dx, h = br.dy - tl.dy;
    if (w > visible.width || h > visible.height) {
      final zoom = (s.zoom * min(visible.width / w, visible.height / h))
          .clamp(0.25, 5.0)
          .toDouble();
      notifier.setZoomAndPan(
          zoom, visible.center - (box.center * rs + center) * zoom);
      return;
    }
    // Only the axis it is hidden on moves; vertically it lands a third down.
    var pan = s.panOffset;
    if (tl.dx < visible.left || br.dx > visible.right) {
      pan += Offset(visible.center.dx - (tl.dx + br.dx) / 2, 0);
    }
    if (tl.dy < visible.top || br.dy > visible.bottom) {
      var dy = visible.top + visible.height / 3 - (tl.dy + br.dy) / 2;
      // No empty band above or below the sheet when the match is near an edge.
      if (!s.isScratch) {
        final top = center.dy * s.zoom + s.panOffset.dy + dy;
        final bottom = top + page.height * rs * s.zoom;
        if (dy > 0 && top > 0) dy = max(visible.top - tl.dy, dy - top);
        if (dy < 0 && bottom < vp.height) {
          dy = min(visible.bottom - br.dy, dy + vp.height - bottom);
        }
      }
      pan += Offset(0, dy);
    }
    notifier.setPanOffset(pan);
  }

  /// A library search hit was opened: show its words found on the page.
  void _takePendingFind() {
    if (_pendingFindTaken || !mounted) return;
    final s = ref.read(canvasProvider);
    final notifier = ref.read(canvasProvider.notifier);
    final pending = ref.read(pendingFindProvider);
    if (s == null || pending == null) return;
    if (pending.notebookId != s.metadata.id) {
      // Left over from an open that never got here.
      _pendingFindTaken = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(pendingFindProvider) == pending) {
          ref.read(pendingFindProvider.notifier).state = null;
        }
      });
      return;
    }
    if (notifier.pagesLoading.value) {
      if (_findWaitsOn == null) {
        final loading = notifier.pagesLoading;
        loading.addListener(_onPagesLoadedForFind);
        _findWaitsOn = loading;
      }
      return;
    }
    _pendingFindTaken = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(pendingFindProvider.notifier).state = null;
      _openFind(query: pending.query, focus: false);
    });
  }

  ValueNotifier<bool>? _findWaitsOn;

  void _onPagesLoadedForFind() {
    final loading = _findWaitsOn;
    if (loading == null || loading.value) return;
    loading.removeListener(_onPagesLoadedForFind);
    _findWaitsOn = null;
    _takePendingFind();
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
                  ShortcutGroup(l10n.csShortcutGroupGeneral, [
                    ('Ctrl+S', l10n.csSaveNow),
                    ('Ctrl+F', l10n.findInNotebook),
                    ('Ctrl+Z', l10n.csShortcutUndo),
                    ('Ctrl+Shift+Z / Ctrl+Y', l10n.csShortcutRedo),
                    ('Ctrl+A', l10n.csSelectAll),
                    ('Ctrl+0', l10n.csShortcutResetZoom),
                    ('Esc', l10n.csShortcutDeselect),
                    ('?', l10n.csShortcutThisGuide),
                  ]),
                  const SizedBox(height: 12),
                  ShortcutGroup(l10n.csShortcutGroupClipboard, [
                    ('Ctrl+C', l10n.csShortcutCopySelection),
                    ('Ctrl+X', l10n.csShortcutCutSelection),
                    ('Ctrl+V', l10n.csPaste),
                    ('Ctrl+D', l10n.csShortcutDuplicateSelection),
                    (l10n.csShortcutKeyDeleteBackspace, l10n.csShortcutDeleteElementOrSelection),
                  ]),
                  const SizedBox(height: 12),
                  ShortcutGroup(l10n.csShortcutGroupTools, [
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

  void _leavePreview(PreviewChoice choice) {
    _closing = true;
    final notifier = ref.read(canvasProvider.notifier);
    Navigator.of(context).pop(choice);
    unawaited(notifier.closeNotebook());
  }

  Future<bool> _onWillPop() async {
    if (_leaving) return false;
    _leaving = true;
    try {
      return await _leave();
    } finally {
      if (!_popped) _leaving = false;
    }
  }

  Future<bool> _leave() async {
    // Mark closing so didChangeAppLifecycleState doesn't fire a parallel
    // save if the OS backgrounds the app during the pop dialog.
    _closing = true;
    // A save in flight is not waited for: it may sit behind the network for
    // minutes, and the disk write below answers the only question here.
    if (!mounted) return false;
    _ptr.flushDeferredCommit();
    final editor = ref.read(canvasProvider.notifier);
    // Checked even when nothing is dirty: a write that failed after the
    // upload went through leaves the notebook clean but the disk behind.
    // A preview writes nothing, so it has nothing to lose.
    if (ref.read(canvasProvider) != null && !editor.isPreview) {
      // On disk already: the upload finishes in the background flush below,
      // so there is nothing to ask. Ask only when the disk refused it.
      var onDisk = await editor.persistLocalNow();
      while (!onDisk) {
        if (!mounted) return false;
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(ctx).csUnsavedChangesTitle),
            content: Text(AppLocalizations.of(ctx).csUnsavedLocalBody),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text(AppLocalizations.of(ctx).csDiscard)),
              TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: Text(AppLocalizations.of(ctx).csCancel)),
              FilledButton(onPressed: () => Navigator.pop(ctx, 'retry'), child: Text(AppLocalizations.of(ctx).csRetrySave)),
            ],
          ),
        );
        // Tapping outside the dialog chose nothing: stay, like Cancel.
        if (result == null || result == 'cancel') {
          _closing = false;
          return false;
        }
        if (result == 'discard') {
          editor.discardUnsavedEdits();
          break;
        }
        onDisk = await editor.persistLocalNow();
      }
      if (!mounted) return false;
    }
    // Fast-close flow: closeNotebook() drains pending pulls, pulled saves
    // and uploads, then tears the canvas down. It is NOT awaited before
    // popping: on a slow network that takes seconds or more, and back must
    // not wait on a spinner. Its future goes to the route, wrapped in
    // [EditorExit]: the opener awaits it before the library refreshes (no
    // stale "1 pagina" card), and the next notebook opens after it.
    final notifier = ref.read(canvasProvider.notifier);
    final closing = notifier.closeNotebook();
    if (mounted) {
      _popped = true;
      Navigator.of(context).pop(EditorExit(closing));
    }
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
    final t = PageViewTransform.of(state, canvasSize);

    final pan = panOverride ?? state.panOffset;
    // Right edge of the page in screen coords
    final pageRightScreen = t.pageRightScreen(pan.dx);
    // Left edge of the page in screen coords
    final pageLeftScreen = t.pageLeftScreen(pan.dx);

    final filtered = state.filteredPageIndices;
    final pos = filtered.indexOf(state.currentPageIndex);
    final hasNext = pos >= 0 && pos + 1 < filtered.length;
    final hasPrev = pos > 0;
    final isLastPage = pos >= 0 && pos == filtered.length - 1;

    // ─ Swipe LEFT: show next page or new page preview ─
    if (pageRightScreen < canvasSize.width * 0.68) {
      if (_pageHint.value == PageHint.prevPage) _pageHint.value = PageHint.none;
      if (isLastPage) {
        _pageHint.value = PageHint.newPage;
      } else if (hasNext) {
        _pageHint.value = PageHint.nextPage;
      }
    }
    // ─ Swipe RIGHT: show previous page preview ─
    else if (pageLeftScreen > canvasSize.width * 0.32 && hasPrev) {
      _pageHint.value = PageHint.prevPage;
    } else {
      _clearPageHints();
    }
  }

  /// Commit page navigation on pointer-up if page edge is past the commit
  /// threshold (50% of screen), otherwise just dismiss the preview.
  void _commitOrCancelPageDrag(CanvasState state, Size canvasSize) {
    if (state.isScratch) return;
    final t = PageViewTransform.of(state, canvasSize);

    final pageRightScreen = t.pageRightScreen(state.panOffset.dx);
    final pageLeftScreen = t.pageLeftScreen(state.panOffset.dx);

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
    _pageHint.value = PageHint.none;
  }

  // ── Coordinate conversion ──

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

  /// Open [url] with the platform's default handler. Only http(s) URLs with
  /// a host are accepted: the text comes from note content.
  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    final ok = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!ok) {
      _toast(AppLocalizations.of(context).csCannotOpenLink);
      return;
    }
    try {
      final opened =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      _toast(opened ? l.csOpeningLink : l.csCannotOpenLink);
    } catch (e) {
      CrashLogger.append('[Link] failed to open $url: $e');
      if (!mounted) return;
      _toast(AppLocalizations.of(context).csCannotOpenLink);
    }
  }

  // ── Pointer handling ──

  /// True on a touch-primary platform (no mouse to speak of) — gates
  /// whether the top bar shows the mouse-mode toggle or the touch-mode one,
  /// and is the platform-default fallback for [_ptr.effectiveStylusOnly].
  void _onWebTouchDeviceChanged() {
    if (mounted) setState(() {});
  }

  void _onSystemFonts() {
    CanvasRenderEngine.fontsChanged();
    if (mounted) setState(() {});
  }

  Locale? _locale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Typed text follows the app locale (Japanese forms): redraw on a switch.
    final locale = Localizations.localeOf(context);
    if (_locale != null && locale != _locale) CanvasRenderEngine.fontsChanged();
    _locale = locale;
  }

  bool get _isMobilePlatform => kIsWeb
      ? isWebTouchDevice
      : (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  // ── Pinch-to-zoom ──

  // ── Text insertion / editing ──

  /// Text tool tap: editing an existing text element when tapped on one,
  /// otherwise the rich editor for a brand-new element at that point.
  void _handleTextTool(Offset localPos, CanvasState state, Size canvasSize) async {
    final pagePos = _ptr.toPageCoords(localPos, state, canvasSize);
    final existing = ElementHitTest.findTextElementAt(state, pagePos);

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

    // Confirming a text box ends the text gesture: fall back to pan.
    //
    // Staying armed meant the very next tap — to scroll, to look at what was
    // just written, to reach a control — reopened the editor on an empty box.
    // Writing two boxes in a row is the rare case and costs one dock tap;
    // pan is the neutral state that can't do anything destructive. (Restoring
    // the tool used *before* text was the alternative, but dropping the user
    // back into a pen after they finish typing invites accidental marks.)
    notifier.setTool(CanvasTool.pan);
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

  /// Images and PDFs dragged in from the file manager, placed where dropped.
  Future<void> _onFilesDropped(List<String> paths, Offset local) async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    const kinds = {'pdf', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
    var pos = _ptr.toPageCoords(local, state, _ptr.lastCanvasSize);
    var inserted = false;
    for (final path in paths) {
      final ext = path.toLowerCase().split('.').last;
      if (!kinds.contains(ext)) continue;
      final Uint8List bytes;
      try {
        bytes = await io.File(path).readAsBytes();
      } catch (_) {
        continue;
      }
      if (!mounted) return;
      final name = path.split(RegExp(r'[\\/]')).last;
      if (ext == 'pdf') {
        await _pdfImport.insertPdf(bytes, name, pos);
      } else {
        _insertImage(bytes, name, pos);
      }
      inserted = true;
      pos += const Offset(24, 24); // several files: fanned out, not stacked
    }
    if (!inserted && mounted) {
      _toast(AppLocalizations.of(context).csDropUnsupported);
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
      await _pdfImport.insertPdf(bytes, file.name, pagePos);
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

  Dims? _decodeImageDimensions(Uint8List b) {
    if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50) {
      final w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
      final h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
      return Dims(w, h);
    }
    if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
      int off = 2;
      while (off < b.length - 9) {
        if (b[off] != 0xFF) break;
        final m = b[off + 1];
        if (m == 0xC0 || m == 0xC2) {
          return Dims((b[off + 7] << 8) | b[off + 8], (b[off + 5] << 8) | b[off + 6]);
        }
        off += 2 + ((b[off + 2] << 8) | b[off + 3]);
      }
    }
    return null;
  }

  // ── BUILD ──

  @override
  Widget build(BuildContext context) {
    // Only which view to show is watched here; each part of the chrome and the
    // page watches its own fields, so a tool change or a stroke skips this.
    ref.watch(canvasProvider.select((s) => s == null
        ? _EditorView.closed
        : s.currentPage == null
            ? _EditorView.noPage
            : _EditorView.page));
    // After the select-based subscription decides we should rebuild,
    // pull the full state synchronously for the build body's many
    // canvasState.X reads. ref.read does NOT subscribe.
    final canvasState = ref.read(canvasProvider);
    if (canvasState != null && !_startupToolApplied) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyStartupTool();
      });
    }

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
          unawaited(_clipboard.markSystemImageSeen());
        }
      },
    );

    if (canvasState == null) {
      // A null canvasProvider means the notebook is closed, so this editor has
      // nothing left to edit: leave rather than sit here. `_closing` is the
      // crucial exclusion: on the ordinary way out, _onWillPop has ALREADY
      // popped this route and closeNotebook() nulls the state a moment later,
      // so these frames are the exit animation. Popping again would take the
      // library down with us.
      if (!_closing && !_autoPopScheduled) {
        _autoPopScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Second belt: only the route the user is actually looking at may
          // pop itself. A route already mid-pop is no longer `isCurrent`.
          if (ModalRoute.of(context)?.isCurrent != true) return;
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.pop();
        });
      }
      return NoNotebookView(closing: _closing);
    }
    final currentPage = canvasState.currentPage;
    if (currentPage == null) {
      return MissingPageState(onBack: () => _onWillPop());
    }

    final palette = HwThemeScope.of(context);
    final notifier = ref.read(canvasProvider.notifier);
    final toolDock = ref.watch(appSettingsProvider.select((s) => s.toolDock));
    final barFits = MediaQuery.sizeOf(context).width >= DockController.barMinWidth;
    final dockPosition = toolDock.edge == 'bar'
        ? (barFits ? DockPosition.bar : DockPosition.bottom)
        : DockController.edgePosition(toolDock.edge);
    final dockInBar = dockPosition == DockPosition.bar;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Exit presentation (and its OS-level fullscreen) first, while the
        // window is still fully alive, not mid-teardown; a second back action
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
        onKeyEvent: _keyboard.handle,
        child: Scaffold(
          backgroundColor: palette.paper1,
          body: LayoutBuilder(builder: (context, constraints) {
            _onBodyLayout(constraints.biggest);
            EditorDock buildDock(Key? key, DockPosition position) => EditorDock(
                  key: key,
                  position: position,
                  dock: _dock,
                  ptr: _ptr,
                  onToolChanged: _onDockToolChanged,
                  onActiveTap: _onDockActiveTap,
                  onQuickPenTap: _applyQuickPen,
                  onQuickPenSecondary: _showQuickPenMenu,
                );
            final dockWidget = buildDock(_dock.key, dockPosition);
            // While dragged out of the bar, the real dock stays mounted there
            // (it owns the drag gesture) and this copy follows the pointer.
            final dockGhost = dockInBar
                ? IgnorePointer(child: buildDock(null, DockPosition.floating))
                : null;
            return Stack(
              key: _stackKey,
              children: [
                Column(
                  children: [
                    if (!_presentationMode)
                      EditorTopBar(
                        center: dockInBar && !notifier.isPreview
                            ? ValueListenableBuilder<bool>(
                                valueListenable: _dock.dragging,
                                child: dockWidget,
                                builder: (_, dragging, dock) => Opacity(
                                    opacity: dragging ? 0 : 1, child: dock),
                              )
                            : null,
                        isMobilePlatform: _isMobilePlatform,
                        onBack: () => _onWillPop(),
                        onPagesTap: () => _showPageManager(_live),
                        onImportFileTap: () =>
                            _pickAndInsertImage(_visibleCenterPagePos(_live)),
                        onMoreTap: () => _showMoreSheet(_live),
                        onFindTap: _openFind,
                      ),
                    if (notifier.isPreview)
                      NotebookPreviewBar(onChoice: _leavePreview),
                    Expanded(
                      // Any touch on the page (tap or stroke) closes the tool
                      // popup so it never covers what the user is writing.
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (_) {
                          _closePopup();
                        },
                        child: _buildCanvas(canvasState, currentPage),
                      ),
                    ),
                    if (!_presentationMode)
                      EditorPageStrip(
                        find: _find,
                        chapterLabel: _currentChapterLabel,
                        chapterShortLabel: _currentChapterTitle,
                        onChapterTap: _showChapterMenu,
                        onPageSecondary: _showPageStripContextMenu,
                        onAllPagesTap: () => _showPageManager(_live),
                      ),
                  ],
                ),
                // Movable tool dock: while dragging it follows the finger at a
                // free offset, otherwise it sits docked against its persisted
                // edge. Hidden in presentation mode.
                if (_presentationMode || notifier.isPreview)
                  const SizedBox.shrink()
                else
                  ValueListenableBuilder<Offset?>(
                    valueListenable: _dock.drag,
                    child: dockWidget,
                    builder: (_, drag, dock) => drag != null
                        ? Positioned(
                            left: drag.dx,
                            top: drag.dy,
                            child: dockGhost ?? dock!)
                        : dockInBar
                            // Lives in the top bar (its `center`).
                            ? const SizedBox.shrink()
                            : DockController.dockedPositioned(
                                dockPosition, toolDock.align, dock!),
                  ),
                if (_presentationMode)
                  PresentationOverlay(onExit: _exitPresentationMode),
                if (!_presentationMode && !notifier.isPreview)
                  EditorToolPanel(
                    dockPosition: dockPosition,
                    align: toolDock.align,
                    area: _dock.area,
                    popup: _popup,
                    onClose: _closePopup,
                  ),
                const RemoteChangesBanner(),
                const BackToContentPill(),
                PullProgressPill(
                  isPulling: notifier.isPullingFromRemote,
                  progress: notifier.pullProgress,
                ),
                PagesLoadingBar(loading: notifier.pagesLoading),
              ],
            );
          }),
        ),
      ),
    );
  }

  /// The page area got its size: the pointer pipeline and the notebook (which
  /// centres and refits the page) take it from here.
  void _onCanvasLayout(Size size) {
    _ptr.lastCanvasSize = size;
    ref.read(canvasProvider.notifier).setViewportSize(size);
  }

  /// The editor area, for the dock's edge-snap zones and drag clamping.
  void _onBodyLayout(Size size) => _dock.area = size;

  /// The live state; the editor only builds with a notebook open.
  CanvasState get _live => ref.read(canvasProvider)!;

  void _onDockToolChanged(CanvasTool tool, PointerDeviceKind kind) {
    _noteDockTapDevice(kind);
    _pickTool(tool);
    // Switching tool never auto-opens the popup: the user explicitly asks for
    // it by tapping the active tool again.
    _closePopup();
  }

  /// A tap on the dock's active tool; [shown] is the tool the dock displays.
  void _onDockActiveTap(PointerDeviceKind kind, CanvasTool shown) {
    final live = ref.read(canvasProvider);
    if (live == null) return;
    // Dock still shows the real pen while the mouse only selects (not yet seen
    // over the canvas): a mouse tap on it means "draw with the mouse", not
    // "open the popup".
    final penShown = shown == live.currentTool &&
        EditorPointerController.mouseSelectTools.contains(live.currentTool);
    _noteDockTapDevice(kind);
    if (kind == PointerDeviceKind.mouse &&
        penShown &&
        !ref.read(appSettingsProvider).mouseDraws) {
      ref.read(appSettingsProvider.notifier).setMouseDraws(true);
      return;
    }
    // These tools have no options: their popup would be empty.
    if (const {CanvasTool.lasso, CanvasTool.pan, CanvasTool.laser}
        .contains(live.currentTool)) {
      return;
    }
    _popup.value = (open: !_popupOpen, at: null);
  }

  Widget _buildCanvas(CanvasState canvasState, PageData currentPage) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        _onCanvasLayout(canvasSize);

        return FileDropZone(
          hint: AppLocalizations.of(context).csDropHint,
          onDrop: _onFilesDropped,
          child: CanvasCursorRegion(
            hoverCursor: _ptr.mouseHoverCursor,
            onExit: _ptr.clearPenHover,
            child: Stack(
              key: _canvasStackKey,
              // The canvas area, always: never sized by an overlay child.
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: CanvasPointerSurface(
                    ptr: _ptr,
                    fingerTaps: _fingerTaps,
                    showContextMenu: _showContextMenu,
                    ensurePdfTextSel: _ensurePdfTextSel,
                    canvasSize: canvasSize,
                    fallback: canvasState,
                    child: CanvasPaintLayer(
                      ptr: _ptr,
                      zoomSnapshot: _zoomSnapshot,
                      pdfSharpener: () => _pdfSharpener,
                      pdfTileVersion: _pdfTileVersion,
                      canvasSize: canvasSize,
                      fallback: canvasState,
                      fallbackPage: currentPage,
                    ),
                  ),
                ),
                PenCursorLayer(ptr: _ptr, canvasSize: canvasSize),
                // Handles of the selected element and of the lasso selection.
                Positioned.fill(
                  child: ElementHandles(
                    fallback: canvasState,
                    canvasSize: canvasSize,
                    transform: _ptr.elementTransform,
                    onCrop: _showCropDialog,
                    onEditComment: _showCommentDialog,
                    onEditMath: _editMath,
                    onTidyCircuit: _tidyImageCircuit,
                    onConvertToInk: _convertImageToInk,
                    copyImageToSystemClipboard:
                        _clipboard.copyImageElementToSystemClipboard,
                    toast: _toast,
                  ),
                ),
                Positioned.fill(
                  child: LassoOverlay(
                    fallback: canvasState,
                    canvasSize: canvasSize,
                    transform: _ptr.lassoTransform,
                    canvasStackKey: _canvasStackKey,
                    onCommit: _commitLassoTransform,
                    actionBar: (live) => SelectionActionBar(
                      state: live,
                      canvasSize: canvasSize,
                      transform: _ptr.lassoTransform,
                      dockRect: _dockRectInCanvas,
                      copyImageToSystemClipboard:
                          _clipboard.copyImageElementToSystemClipboard,
                      paste: () => _clipboard.pasteFromClipboard(),
                      toast: _toast,
                      strokeWidthOf: _selectionCurrentWidth,
                      onColor: _showSelectionColorPicker,
                      onWidth: _showSelectionWidthPicker,
                      onMore: _showSelectionMoreMenu,
                      onRecognize: _recognizeSelection,
                    ),
                  ),
                ),
                PdfSelectionOverlay(
                  selectionFor: _ensurePdfTextSel,
                  fallback: canvasState,
                  canvasSize: canvasSize,
                  onCopy: _copyPdfTextToClipboard,
                ),
                // Find in notebook: match highlights, then the bar over them.
                Positioned.fill(
                  child: FindHighlightsLayer(
                    find: _find,
                    fallback: canvasState,
                    canvasSize: canvasSize,
                  ),
                ),
                FindBarOverlay(
                  find: _find,
                  text: _findText,
                  focus: _findFocus,
                  canvasSize: canvasSize,
                  top: _findBarTop,
                  onChanged: _onFindChanged,
                  onNext: () => _findStep(1),
                  onPrevious: () => _findStep(-1),
                  onClose: _closeFind,
                  // Back to the page: keys are shortcuts again and the
                  // on-screen keyboard goes away; the bar stays.
                  onTapOutside: () {
                    if (_findFocus.hasFocus) _focusNode.requestFocus();
                  },
                ),
                const ShapeRecognizedBanner(),
                TapFlashPill(flash: _tapFlash),
                const PendingSymbolHint(),
                const PendingPasteHint(),
                PageDragHint(hint: _pageHint),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCommentDialog(String elementId) async {
    // Find current comment
    final st = ref.read(canvasProvider);
    if (st == null) return;
    String? currentComment;
    final pg = st.currentPage;
    if (pg != null) {
      for (final el in pg.layers.content) {
        final id = el.id;
        if (id == elementId) {
          el.map(unknown: (_) {},
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
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => TextControllerScope(text: currentComment ?? '', builder: (_, controller) => AlertDialog(
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
      )),
    );
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
      return e.id ==
          elementId;
    }).firstOrNull;
    if (element == null) return;

    ImageData? imageData;
    element.map(unknown: (_) {},
        stroke: (_) {}, text: (_) {}, image: (i) => imageData = i.data, shape: (_) {}, math: (_) {});
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

  // ── Selection overlays ──

  /// The tool dock's rect in the canvas stack's coordinates, if laid out.
  Rect? _dockRectInCanvas() {
    final dock = _dock.key.currentContext?.findRenderObject() as RenderBox?;
    final canvas = _canvasStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (dock == null || canvas == null || !dock.attached || !canvas.attached) {
      return null;
    }
    return canvas.globalToLocal(dock.localToGlobal(Offset.zero)) & dock.size;
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
        child: SingleChildScrollView(child: Padding(
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
                  GestureDetector(
                    onTap: () async {
                      final c = await showHwColorPicker(
                          ctx, Color(presets.first));
                      if (c != null && ctx.mounted) {
                        Navigator.of(ctx).pop(c.toARGB32());
                      }
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(colors: [
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
                ],
              ),
            ],
          ),
        )),
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
      final id = element.id;
      if (!sel.selectedIds.contains(id)) continue;
      final width = element.map(unknown: (_) => -1.0,
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
          child: SingleChildScrollView(child: Padding(
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
                    Text(AppLocalizations.of(ctx).csWidthPx(
                        width.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '')),
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
                    divisions: 78,
                    value: width.clamp(0.5, 20.0),
                    onChanged: (v) {
                      setSheetState(() => width = v);
                      notifier.changeSelectionStrokeWidth(v);
                    },
                  ),
                ),
              ],
            ),
          )),
        ),
      ),
    );
    notifier.endSelectionWidthEdit();
  }

  /// "Altro" menu for lass selection — surfaces the less-used actions
  /// (flip H/V, screenshot to clipboard, paste into another notebook).
  Future<void> _showSelectionMoreMenu(CanvasState state, bool compact) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Module actions: only ready, enabled modules contribute.
            Consumer(builder: (ctx, ref, _) {
              final summary = SelectionSummary(
                  hasInk: ref.read(canvasProvider.notifier).selectionHasInk);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final a in ref.watch(selectionActionsProvider))
                    if (a.appliesTo(summary) && !_isRecognizer(a))
                      ListTile(
                        leading: Icon(a.icon),
                        title: Text(a.label(AppLocalizations.of(ctx))),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _runSelectionAction(a);
                        },
                      ),
                ],
              );
            }),
            if (compact)
              ListTile(
                leading: const Icon(Icons.copy_all_rounded),
                title: Text(AppLocalizations.of(ctx).csDuplicate),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ref.read(canvasProvider.notifier).duplicateSelection();
                  _toast(AppLocalizations.of(ctx).csSelectionDuplicated);
                },
              ),
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
                _clipboard.copySelectionAsScreenshot();
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
        )),
      ),
    );
  }

  static bool _isRecognizer(SelectionAction a) => isRecognizerAction(a);

  /// Recognize: the region router picks the recognizer for the selection;
  /// unsure, the user picks. The chosen module action then runs as usual.
  Future<void> _recognizeSelection() async {
    final notifier = ref.read(canvasProvider.notifier);
    notifier.applySelectionTransform();
    final slots = RecognizerSlots.read(ref);
    RegionClassifier? classify;
    try {
      classify = await ref.read(regionClassifierProvider.future);
    } catch (e) {
      CrashLogger.append('[recognize] router unavailable: $e');
    }
    if (!mounted) return;
    final probs = await classify?.call([for (final e in notifier.selectedInk()) e.$2]);
    if (!mounted) return;
    CrashLogger.append('[recognize] $probs');
    var step = decideRecognize(probs, slots);
    if (step is AskRecognizer) {
      final kind = await _askRecognizer();
      if (kind == null || !mounted) return;
      step = recognizeAs(kind, slots);
    }
    await _applyRecognizeStep(step);
  }

  /// Runs [step]; a conversion is followed by its kind and a "Change" action.
  Future<void> _applyRecognizeStep(RecognizeStep step) async {
    final l10n = AppLocalizations.of(context);
    switch (step) {
      case RunRecognizer(:final action, :final kind):
        final notifier = ref.read(canvasProvider.notifier);
        final before = ref.read(canvasProvider)?.undoStack.lastOrNull;
        final ids = await _runSelectionAction(action);
        final s = ref.read(canvasProvider);
        if (ids == null || s == null || !mounted) return;
        // Change undoes exactly this step, so only while it is still the last one.
        final page = s.currentPageFileName, top = s.undoStack.lastOrNull;
        if (top == null || identical(top, before)) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: Text(kind == RegionKind.formula
              ? l10n.csRecognizedAsFormula
              : l10n.csRecognizedAsCircuit),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: l10n.csRecognizeChange,
            onPressed: () async {
              final now = ref.read(canvasProvider);
              if (!mounted || now == null || now.currentPageFileName != page ||
                  !identical(now.undoStack.lastOrNull, top)) {
                return;
              }
              notifier.undo();
              notifier.selectIds(ids);
              final kind = await _askRecognizer();
              if (kind == null || !mounted) return;
              await _applyRecognizeStep(recognizeAs(kind, RecognizerSlots.read(ref)));
            },
          ),
        ));
      case NoteRecognizer(:final note):
        _toast(switch (note) {
          RecognizeNote.textNotConverted => l10n.csRecognizeTextNotConverted,
          RecognizeNote.nothingToRecognize => l10n.csRecognizeDrawing,
          RecognizeNote.formulaOff => l10n.csRecognizeModuleOff(l10n.modMathInkName),
          RecognizeNote.circuitOff => l10n.csRecognizeModuleOff(l10n.modCircuitsName),
          RecognizeNote.unavailable => l10n.csRecognizeModelMissing,
        });
      case AskRecognizer():
        break;
    }
  }

  /// The choice offered when the router is unsure.
  Future<RegionKind?> _askRecognizer() => showModalBottomSheet<RegionKind>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          final l10n = AppLocalizations.of(ctx);
          ListTile tile(IconData icon, String label, RegionKind kind) => ListTile(
                key: Key('recognizeAs:${kind.name}'),
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.of(ctx).pop(kind),
              );
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(l10n.csRecognizeAs,
                      style: Theme.of(ctx).textTheme.titleSmall),
                ),
                tile(Icons.functions_rounded, l10n.csRecognizeAsFormula, RegionKind.formula),
                tile(Icons.electrical_services_rounded, l10n.csRecognizeAsCircuit,
                    RegionKind.circuit),
                tile(Icons.text_fields_rounded, l10n.csRecognizeAsText, RegionKind.text),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );

  /// Runs a module's lasso action and applies its outcome in one undo step.
  /// A miss is a toast: recognisers fail often and undo is the safety net.
  /// Returns the ids of the replaced ink, null when nothing changed.
  Future<Set<String>?> _runSelectionAction(SelectionAction action) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(canvasProvider.notifier);
    // A selection moved but not committed yet is read where it now is.
    notifier.applySelectionTransform();
    final s = ref.read(canvasProvider);
    final page = s?.currentPage;
    if (s == null || page == null) return null;
    final fileName = s.currentPageFileName;

    _toast(action.busyLabel(l10n));
    SelectionOutcome outcome;
    try {
      outcome = await action.run(SelectionRequest(
          ink: notifier.selectedInk,
          mathInk: notifier.selectedMathInk,
          // A sketch sheet is far wider than anything drawn on it: its ink is
          // sized like a regular page's.
          pageWidth: s.isScratch ? AppConfig.defaultPageWidth : page.width));
    } catch (e, st) {
      outcome = ActionFailed('$e\n$st', reason: ActionFailReason.error);
    }
    if (!mounted) return null;
    switch (outcome) {
      case ActionFailed(:final debug, :final reason):
        CrashLogger.append('[module] ${action.id} failed (${reason.name}): $debug');
        _toast(switch (reason) {
          ActionFailReason.notRecognized => action.failedLabel(l10n),
          ActionFailReason.modelMissing => l10n.csRecognizeModelMissing,
          ActionFailReason.noInk => l10n.csRecognizeNoInk,
          ActionFailReason.error => l10n.csRecognizeError,
        });
        return null;
      case ReplaceInk(:final removedIds, :final added):
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        notifier.replaceStrokesWithDrawing(fileName, removedIds, added);
        return removedIds;
      case InsertMath(:final removedIds, :final latex):
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await notifier.replaceInkWithMath(fileName, removedIds, latex);
        return removedIds;
    }
  }

  /// Opens the LaTeX editor on [element] and applies the result.
  Future<void> _editMath(MathElement element) async {
    final latex = await showMathEditorDialog(context, initial: element.data.latex);
    if (latex == null || !mounted) return;
    await ref.read(canvasProvider.notifier).updateMathLatex(element.id, latex);
  }

  /// Redraws the circuit in image [elementId] as strokes in its place, one
  /// undo step. A miss is a toast, as for the lasso tidy-up.
  Future<void> _tidyImageCircuit(String elementId) async {
    final l10n = AppLocalizations.of(context);
    final s = ref.read(canvasProvider);
    final image = s?.currentPage?.layers.content.whereType<ImageElement>().where((e) => e.id == elementId).firstOrNull;
    final bytes = image == null ? null : s!.assetBytes[image.data.assetPath];
    final recognizer = ref.read(circuitRecognizerProvider).valueOrNull;
    if (image == null || bytes == null || recognizer == null) {
      CrashLogger.append('[circuit] image $elementId: image=${image != null} bytes=${bytes != null} '
          'model=${recognizer != null}');
      _toast(recognizer == null ? l10n.csRecognizeModelMissing : l10n.csRecognizeImageMissing);
      return;
    }
    final fileName = s!.currentPageFileName;
    _toast(l10n.csRecognizeBusy);
    final (circuit, why) = await imageCircuitStrokes(recognizer, bytes, image.data);
    CrashLogger.append('[circuit] image $elementId: $why');
    if (!mounted) return;
    if (circuit == null) {
      _toast(l10n.csRecognizeCircuitFailed);
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final notifier = ref.read(canvasProvider.notifier);
    notifier.deselectElement();
    notifier.replaceStrokesWithDrawing(fileName, {elementId}, circuit.strokes, image: circuit.rest);
  }

  /// Traces the handwriting in image [elementId] into strokes in its place,
  /// one undo step. A picture with none is left as it is, with a toast.
  Future<void> _convertImageToInk(String elementId) async {
    final l10n = AppLocalizations.of(context);
    final s = ref.read(canvasProvider);
    final image = s?.currentPage?.layers.content.whereType<ImageElement>().where((e) => e.id == elementId).firstOrNull;
    final bytes = image == null ? null : s!.assetBytes[image.data.assetPath];
    if (image == null || bytes == null) {
      _toast(l10n.csRecognizeImageMissing);
      return;
    }
    final fileName = s!.currentPageFileName;
    _toast(l10n.csPhotoInkBusy);
    // On the web the trace runs on this thread: the toast paints first.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final (strokes, why) = await photoInkStrokes(bytes, image.data);
    CrashLogger.append('[photo-ink] image $elementId: $why');
    if (!mounted) return;
    if (strokes == null) {
      _toast(l10n.csPhotoInkFailed);
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final notifier = ref.read(canvasProvider.notifier);
    notifier.deselectElement();
    notifier.replaceStrokesWithDrawing(fileName, {elementId}, strokes);
  }

  /// Picks a photo of paper notes, puts it on the page across the width and
  /// converts it: undo brings the photo back.
  Future<void> _pickPhotoAsInk(Offset pagePos) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
    final page = ref.read(canvasProvider)?.currentPage;
    if (file == null || bytes == null || page == null || !mounted) return;
    final dims = _decodeImageDimensions(bytes);
    final iw = dims?.width.toDouble() ?? 3, ih = dims?.height.toDouble() ?? 4;
    final f = min(0.9 * page.width / iw, 0.9 * page.height / ih);
    // Returns the asset; the new element is the one left selected.
    final asset = ref.read(canvasProvider.notifier).addImageElement(
        Offset(0.05 * page.width, pagePos.dy.clamp(0, max(0, page.height - ih * f))), file.name, bytes, iw * f, ih * f);
    final id = ref.read(canvasProvider)?.selectedElementId;
    if (asset != null && id != null) await _convertImageToInk(id);
  }

  /// Snapshot the live transform from [_ptr.lassoTransform] back into
  /// Riverpod and clear the notifier. Called from drag/rotate/scale
  /// onPanEnd / onPanCancel + the drag-selection branch of _ptr.onPointerUp.
  /// Riverpod fires exactly once per gesture instead of once per
  /// pointer-move event.
  void _commitLassoTransform() {
    if (!_ptr.lassoTransform.isActive) return;
    final snap = _ptr.lassoTransform.snapshot();
    ref.read(canvasProvider.notifier).commitSelectionTransform(
          dragOffset: snap.dragOffset,
          rotation: snap.rotation,
          scale: snap.scale,
        );
    _ptr.lassoTransform.end();
  }

  // ── Context menu (right-click) ──

  void _showContextMenu(Offset globalPos, Offset localPos, CanvasState state, Size canvasSize) {
    final pagePos = _ptr.toPageCoords(localPos, state, canvasSize);
    final sel = state.lassoSelection;
    // On the selection the menu is about it; anywhere else drops the selection.
    final hasLassoSelection = sel != null &&
        Rect.fromCenter(
          center: sel.bounds.center,
          width: sel.bounds.width * sel.scale,
          height: sel.bounds.height * sel.scale,
        ).translate(sel.dragOffset.dx, sel.dragOffset.dy).inflate(12).contains(pagePos);
    if (sel != null && !hasLassoSelection) {
      ref.read(canvasProvider.notifier).clearSelection();
    }
    final tappedElement = hasLassoSelection ? null : ElementHitTest.findElementAt(ref.read(canvasProvider) ?? state, pagePos);
    // Page-wide entries belong to the empty canvas, not to a menu on an element.
    final onCanvas = !hasLassoSelection && tappedElement == null;
    final hasSymbols = state.symbols.isNotEmpty;
    final l10n = AppLocalizations.of(context);
    final summary = SelectionSummary(hasInk: ref.read(canvasProvider.notifier).selectionHasInk);
    final moduleActions = hasLassoSelection
        ? [
            for (final a in ref.read(selectionActionsProvider))
              if (a.appliesTo(summary) && !_isRecognizer(a)) a,
          ]
        : const <SelectionAction>[];
    final recognize = hasLassoSelection && summary.hasInk &&
        ref.read(selectionActionsProvider).any(_isRecognizer);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        // Selection operations
        if (hasLassoSelection) ...[
          PopupMenuItem(value: 'copy', child: MenuRow(Icons.copy_rounded, l10n.csCopy, 'Ctrl+C')),
          PopupMenuItem(value: 'copy_screenshot', child: MenuRow(Icons.screenshot_rounded, l10n.csCopyAsImage, null)),
          PopupMenuItem(value: 'cut', child: MenuRow(Icons.content_cut_rounded, l10n.csCut, 'Ctrl+X')),
          PopupMenuItem(value: 'duplicate_sel', child: MenuRow(Icons.copy_all_rounded, l10n.csDuplicate, 'Ctrl+D')),
          PopupMenuItem(value: 'delete_sel', child: MenuRow(Icons.delete_outline_rounded, l10n.csDelete, l10n.csKeyDelete)),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'create_symbol', child: MenuRow(Icons.star_outline_rounded, l10n.csCreateSymbol, null)),
          if (recognize)
            PopupMenuItem(value: 'recognize', child: MenuRow(Icons.auto_fix_high_rounded, l10n.csRecognize, null)),
          for (final a in moduleActions)
            PopupMenuItem(value: 'module:${a.id}', child: MenuRow(a.icon, a.label(l10n), null)),
        ],
        // Single element operations
        if (tappedElement != null) ...[
          PopupMenuItem(value: 'select_element', child: MenuRow(Icons.touch_app_outlined, l10n.csSelect, null)),
          PopupMenuItem(value: 'duplicate_element', child: MenuRow(Icons.copy_all_rounded, l10n.csDuplicate, null)),
          PopupMenuItem(value: 'delete_element', child: MenuRow(Icons.delete_outline_rounded, l10n.csDelete, null)),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'create_symbol_element', child: MenuRow(Icons.star_outline_rounded, l10n.csCreateSymbol, null)),
        ],
        if (onCanvas) ...[
          // Paste: single entry — _pasteFromClipboard resolves what the user
          // most recently copied (fresh system image/text wins over a stale
          // in-app selection, and vice versa).
          PopupMenuItem(value: 'paste', child: MenuRow(Icons.paste_rounded, l10n.csPaste, 'Ctrl+V')),
          // Insert: one picker for images AND PDFs (was two separate entries).
          PopupMenuItem(value: 'insert_file', child: MenuRow(Icons.attach_file_rounded, l10n.csImportFile, null)),
          if (_cameraAvailable)
            PopupMenuItem(value: 'insert_camera', child: MenuRow(Icons.camera_alt_rounded, l10n.csTakePhoto, null)),
          PopupMenuItem(value: 'insert_photo_ink', child: MenuRow(Icons.draw_rounded, l10n.csInsertPhotoInk, null)),
          PopupMenuItem(value: 'insert_text', child: MenuRow(Icons.text_fields_rounded, l10n.csInsertText, null)),
          // Symbols
          if (hasSymbols)
            PopupMenuItem(
              value: 'symbols',
              child: MenuRow(Icons.star_rounded, l10n.csInsertSymbolCount(state.symbols.length), null),
            ),
          const PopupMenuDivider(),
          // Page operations
          PopupMenuItem(value: 'select_all', child: MenuRow(Icons.select_all_rounded, l10n.csSelectAll, 'Ctrl+A')),
          PopupMenuItem(value: 'clear_page', child: MenuRow(Icons.cleaning_services_rounded, l10n.csClearPage, null)),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'export_png', child: MenuRow(Icons.image_outlined, l10n.csExportPng, null)),
          PopupMenuItem(value: 'export_pdf', child: MenuRow(Icons.picture_as_pdf_rounded, l10n.csExportPdf, null)),
        ],
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      final notifier = ref.read(canvasProvider.notifier);
      for (final a in moduleActions) {
        if (value == 'module:${a.id}') {
          _runSelectionAction(a);
          return;
        }
      }
      switch (value) {
        case 'recognize': _recognizeSelection(); break;
        case 'copy': notifier.copySelection(); _toast(AppLocalizations.of(context).csSelectionCopied); break;
        case 'copy_screenshot': _clipboard.copySelectionAsScreenshot(); break;
        case 'cut': notifier.cutSelection(); _toast(AppLocalizations.of(context).csSelectionCut); break;
        case 'duplicate_sel': notifier.duplicateSelection(); _toast(l10n.csSelectionDuplicated); break;
        case 'delete_sel': notifier.deleteSelection(); break;
        case 'paste': _clipboard.pasteFromClipboard(at: pagePos); break;
        case 'select_all': notifier.selectAll(); break;
        case 'clear_page': _confirmClearPage(); break;
        case 'insert_file': _pickAndInsertImage(pagePos); break;
        case 'insert_camera': _captureAndInsertImage(pagePos); break;
        case 'insert_photo_ink': _pickPhotoAsInk(pagePos); break;
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
        case 'export_png': _export.exportAsPng(); break;
        case 'export_pdf': _export.exportAsPdf(); break;
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
    String? selectedLibId = libs.isNotEmpty ? libs.first.id : null;

    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (ctx) => TextControllerScope(builder: (_, controller) => StatefulBuilder(
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
      )),
    );
    if (result != null && result.$1.isNotEmpty) {
      ref.read(canvasProvider.notifier).createSymbolFromSelection(result.$1,
          targetLibId: result.$2,
          defaultLibraryName: l10n.chromeSymbols);
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
    String? selectedLibId = libs.isNotEmpty ? libs.first.id : null;

    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (ctx) => TextControllerScope(builder: (_, controller) => StatefulBuilder(
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
      )),
    );
    if (result != null && result.$1.isNotEmpty) {
      ref.read(canvasProvider.notifier).createSymbolFromElement(elementId, result.$1,
          defaultLibraryName: l10n.chromeSymbols);
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

  String _currentChapterLabel(CanvasState state) {
    // Resolve with the same fallback the collector uses so the dialog
    // count stays in sync with the number of pages the PDF will contain
    // (and so "all pages" view still shows a chapter name).
    final ch = resolveActiveChapter(state);
    if (ch == null) return '';
    final count = chapterPageEntries(state, ch).length;
    return AppLocalizations.of(context).csChapterLabelWithCount(
        chapterDisplayTitle(AppLocalizations.of(context), ch.title), count);
  }

  String? _currentChapterTitle(CanvasState state) {
    final ch = resolveActiveChapter(state);
    return ch == null
        ? null
        : chapterDisplayTitle(AppLocalizations.of(context), ch.title);
  }

  /// Pull-down from the page strip's chapter button: every chapter with its
  /// page count, the current one ticked, and a way to start a new one.
  Future<void> _showChapterMenu(Rect anchor) async {
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final l10n = AppLocalizations.of(context);
    final p = HwThemeScope.of(context);
    final active = resolveActiveChapter(state)?.id;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    const newChapter = '\u0000new';
    // Open above the button, not over it: the strip sits at the bottom, and
    // a menu shifted up to fit would hide what was tapped.
    final menuH = state.metadata.chapters.length * 48.0 + 16 + 48 + 16;
    final top = (anchor.top - menuH - 6).clamp(8.0, anchor.top);
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
          Rect.fromLTWH(anchor.left, top, anchor.width, 1),
          Offset.zero & overlay.size),
      color: p.paper0,
      elevation: 8,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        for (final ch in state.metadata.chapters)
          PopupMenuItem(
            value: ch.id,
            child: Row(children: [
              SizedBox(
                width: 20,
                child: ch.id == active
                    ? HwIcon('check', size: 14, color: p.accent)
                    : null,
              ),
              Expanded(
                child: Text(chapterDisplayTitle(l10n, ch.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: p.ink0)),
              ),
              const SizedBox(width: 16),
              Text(l10n.csPagesCount(chapterPageEntries(state, ch).length),
                  style: TextStyle(fontSize: 12, color: p.ink2)),
            ]),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: newChapter,
          child: Row(children: [
            SizedBox(width: 20, child: HwIcon('plus', size: 14, color: p.ink1)),
            Text(l10n.pmNewChapter,
                style: TextStyle(fontSize: 14, color: p.ink0)),
          ]),
        ),
      ],
    );
    if (picked == null || !mounted) return;
    final notifier = ref.read(canvasProvider.notifier);
    if (picked != newChapter) {
      notifier.setActiveChapter(picked);
      return;
    }
    var title = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.pmNewChapter),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.pmChapterNameHint),
          onChanged: (v) => title = v,
          onSubmitted: (_) => Navigator.pop(dCtx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: Text(l10n.pmCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: Text(l10n.pmOk)),
        ],
      ),
    );
    if (ok == true && title.trim().isNotEmpty && mounted) {
      notifier.addChapter(title.trim());
    }
  }

  /// Right-click / long-press on a thumbnail in the bottom strip.
  /// Anchored at [pos] (global), shows quick actions on that page.
  /// Auto-shape options; the same switch as Settings → Fill shapes.
  void _applyQuickPen(CanvasTool tool, int slot) {
    final s = ref.read(canvasProvider);
    if (s == null) return;
    if (s.currentTool != tool) _pickTool(tool);
    ref.read(canvasProvider.notifier).applyPenPreset(
        ref.read(appSettingsProvider).quickPensFor(tool)[slot]);
    _closePopup();
  }

  void _showQuickPenMenu(CanvasTool tool, int slot, Offset pos) async {
    final l10n = AppLocalizations.of(context);
    // Saving needs the tool in hand: its live settings are what gets stored.
    final canSave = ref.read(canvasProvider)?.currentTool == tool;
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
            value: 'save',
            enabled: canSave,
            child: Text(l10n.chromePresetOverwrite)),
        PopupMenuItem(value: 'reset', child: Text(l10n.chromePresetReset)),
      ],
    );
    if (picked == null || !mounted) return;
    final settings = ref.read(appSettingsProvider.notifier);
    if (picked == 'reset') {
      settings.clearPenPreset(tool, slot);
      return;
    }
    final s = ref.read(canvasProvider);
    if (s == null || s.currentTool != tool) return;
    final from = s.toolSettings;
    settings.savePenPreset(
      tool,
      slot,
      PenPreset(
        tool: tool,
        color: from.color,
        strokeWidth: from.strokeWidth,
        opacity: from.opacity,
      ),
    );
  }

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
      constraints: const BoxConstraints(maxWidth: 1000),
      backgroundColor: Colors.transparent,
      builder: (ctx) => PageManagerSheet(
        initialState: canvasState,
        parentMessenger: parentMessenger,
        onGoTo: _goToNotebook,
      ),
    );
  }

  /// Leaves this notebook for [id] (null = the library) and, for a notebook,
  /// has the library open it on its Pages.
  Future<void> _goToNotebook(String? id) async {
    final container = ProviderScope.containerOf(context);
    final route = ModalRoute.of(context);
    await _onWillPop();
    // Still here: the user stayed (unsaved-changes dialog).
    if (route == null || route.isActive || id == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    container.read(pagesTrayNavProvider.notifier).state = TrayNavRequest(id);
  }

  /// A tray action asked for this notebook's Pages, or for another notebook.
  void _onTrayNav(TrayNavRequest req) {
    final s = ref.read(canvasProvider);
    if (s == null || !mounted) return;
    ref.read(pagesTrayNavProvider.notifier).state = null;
    if (req.notebookId == s.metadata.id) {
      if (req.landing.isNotEmpty) {
        ref.read(canvasProvider.notifier).setActiveChapter(null);
        ref.read(pagesTrayProvider.notifier).landPages(req.landing);
      }
      _showPageManager(ref.read(canvasProvider) ?? s);
    } else {
      unawaited(_goToNotebook(req.notebookId));
    }
  }

  /// Center of the visible viewport mapped to page coordinates.
  Offset _visibleCenterPagePos(CanvasState state) {
    // Use the CANVAS size (screen minus top bar / page strip): _ptr.toPageCoords
    // expects canvas-local coordinates, and the render scale is computed on
    // the canvas area, not the full screen.
    final size = _ptr.lastCanvasSize == Size.zero
        ? MediaQuery.of(context).size
        : _ptr.lastCanvasSize;
    final center = Offset(size.width / 2, size.height / 2);
    final p = _ptr.toPageCoords(center, state, size);
    // Infinite canvas has no page bounds — drop content wherever the user
    // is looking. A4 pages clamp so pastes/symbols land on-page.
    if (state.isScratch) return p;
    final pageW = state.currentPage?.width ?? 595;
    final pageH = state.currentPage?.height ?? 842;
    return Offset(p.dx.clamp(50, pageW - 50), p.dy.clamp(50, pageH - 50));
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
    final notifier = ref.read(canvasProvider.notifier);
    ListTile tile(Widget icon, String title, String? sub, VoidCallback run) =>
        ListTile(
          dense: true,
          leading: icon,
          title: Text(title),
          subtitle: sub == null ? null : Text(sub),
          onTap: () {
            Navigator.of(context).pop();
            run();
          },
        );
    // Same breakpoint as the top bar, which hides its Import button there.
    final compact = MediaQuery.of(context).size.width < 720;
    // Groups: show, insert, page, notebook, device. Empty groups vanish.
    final groups = <List<Widget>>[
      [
        // Wide windows have it in the top bar.
        if (compact)
          tile(const HwIcon('search', size: 22), l10n.findInNotebook,
              l10n.findInNotebookSub, () => _openFind()),
        if (!state.isScratch)
          tile(const Icon(Icons.slideshow_outlined), l10n.csPresentationMode,
              l10n.csPresentationModeSub, _enterPresentationMode),
        tile(const HwIcon('laser', size: 22), l10n.chromeToolLaser,
            l10n.csLaserSub, () => _pickTool(CanvasTool.laser)),
        if (!state.isScratch)
          ref.read(referenceNotebookProvider) == null
              ? tile(const Icon(Icons.vertical_split_outlined),
                  l10n.csOpenBeside, l10n.csOpenBesideSub,
                  () => showReferencePicker(context, ref, state.metadata.id))
              : tile(const Icon(Icons.vertical_split_outlined),
                  l10n.csCloseBeside, null,
                  () => ref.read(referenceNotebookProvider.notifier).state =
                      null),
      ],
      [
        if (compact)
          tile(const Icon(Icons.attach_file_rounded), l10n.csImportFile,
              l10n.csImageOrPdf,
              () => _pickAndInsertImage(_visibleCenterPagePos(state))),
        if (!notifier.isPreview)
          tile(const HwIcon('symbol', size: 22), l10n.chromeSymbols, null,
              () => _showSymbolsDialog(_visibleCenterPagePos(state))),
      ],
      [
        tile(const Icon(Icons.dashboard_customize_outlined),
            l10n.csChangePaperType,
            _paperTypeLabel(l10n, state.currentPaperType),
            () => _showPaperTypePicker(state)),
      ],
      [
        if (_ocr.isSupported)
          tile(const Icon(Icons.text_fields_rounded),
              l10n.csRecognizeHandwriting, l10n.csRecognizeHandwritingSub,
              () => _recognizeHandwriting(state)),
        tile(const HwIcon('export', size: 22), l10n.chromeExport, null,
            _export.showExportSheet),
        if (!state.isScratch &&
            ref.read(nextcloudShareServiceProvider) != null)
          tile(const Icon(Icons.link_rounded), l10n.csShareLink,
              l10n.csShareLinkSub, () => _export.shareNotebookLink(state)),
      ],
      [
        if (PenMonitorService.isSupported)
          tile(const Icon(Icons.cast_outlined), l10n.csPenToMonitor,
              l10n.csPenToMonitorSubtitle, _showPenMonitorPicker),
        if (state.isDirty)
          tile(const Icon(Icons.save_outlined), l10n.csSaveNow, null, _save),
      ],
    ].where((g) => g.isNotEmpty).toList();
    showModalBottomSheet(
      context: context,
      // Tall enough for every entry on a 720px window; scrolls below that.
      isScrollControlled: true,
      constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      backgroundColor: HwThemeScope.of(context).paper0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(l10n.csMore,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (var i = 0; i < groups.length; i++) ...[
              if (i > 0) const Divider(height: 9, indent: 16, endIndent: 16),
              ...groups[i],
            ],
            const SizedBox(height: 8),
          ],
        )),
      ),
    );
  }

  void _showPaperTypePicker(CanvasState state) {
    final l10n = AppLocalizations.of(context);
    // Spacing while the slider is being dragged; the page only takes it
    // when the drag ends, so a drag is one undo step.
    double? dragSpacingMm;
    showModalBottomSheet(
      context: context,
      backgroundColor: HwThemeScope.of(context).paper0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(builder: (ctx, setSheetState) => Consumer(
          builder: (ctx, ref, _) {
            final live = ref.watch(canvasProvider) ?? state;
            final page = live.currentPage;
            final bg = page?.layers.background;
            final isPdf = bg?.pdfAsset != null ||
                (page != null && hasFullPageBackground(page));
            final paper = live.currentPaperType;
            final notifier = ref.read(canvasProvider.notifier);
            final allPages = notifier.paperAllPages && live.pageCount > 1;
            final spacingPt = bg != null && bg.lineSpacing > 0
                ? bg.lineSpacing
                : paperTypeLineSpacing(paper);
            final spacingMm = (dragSpacingMm ?? spacingPt / ptPerMm)
                .clamp(minLineSpacingMm, maxLineSpacingMm);
            final p = HwThemeScope.of(ctx);
            return SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Text(l10n.csPaperType,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                if (live.pageCount > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Row(
                      children: [
                        Text(l10n.csPaperApplyTo,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: HwSegmented<bool>(
                              key: const Key('paperScope'),
                              segments: [
                                HwSegment(false, l10n.csPaperThisPage),
                                HwSegment(true, l10n.csPaperAllPages),
                              ],
                              selected: allPages,
                              onChanged: (v) => setSheetState(
                                  () => notifier.paperAllPages = v),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final t in PaperType.values)
                  ListTile(
                    leading: Icon(
                      paper == t
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: paper == t
                          ? Theme.of(ctx).colorScheme.primary
                          : null,
                    ),
                    title: Text(_paperTypeLabel(l10n, t)),
                    onTap: () =>
                        notifier.setPaperType(t, allPages: allPages),
                  ),
                if (paper != PaperType.blank && !isPdf)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(l10n.csLineSpacing,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            const Spacer(),
                            Text(
                                l10n.csLineSpacingMm(
                                    spacingMm.toStringAsFixed(1)),
                                style: TextStyle(fontSize: 12, color: p.ink1)),
                          ],
                        ),
                        Slider(
                          min: minLineSpacingMm,
                          max: maxLineSpacingMm,
                          divisions:
                              ((maxLineSpacingMm - minLineSpacingMm) * 2)
                                  .round(),
                          value: spacingMm,
                          onChanged: (v) =>
                              setSheetState(() => dragSpacingMm = v),
                          onChangeEnd: (v) {
                            notifier.setLineSpacing(v * ptPerMm,
                                allPages: allPages);
                            setSheetState(() => dragSpacingMm = null);
                          },
                        ),
                      ],
                    ),
                  ),
                // Page size stays per page: set apart from the scoped rows.
                if (page != null && !live.isScratch && !isPdf &&
                    live.pageCount > 1)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Divider(height: 1),
                  ),
                if (page != null && !live.isScratch && !isPdf)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: PageSizePicker(
                      label: Text(l10n.pageSizeLabel,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      size: Size(page.width, page.height),
                      onChanged: (size) =>
                          notifier.setPageSize(size.width, size.height),
                    ),
                  ),
              ],
            ));
          },
        )),
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
      if (mounted) _toast(_penMonitorErrorText(e));
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
        child: SingleChildScrollView(child: Column(
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
                    if (mounted) _toast(_penMonitorErrorText(e));
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
                  if (mounted) _toast(_penMonitorErrorText(e));
                }
              },
            ),
          ],
        )),
      ),
    );
  }

  String _penMonitorErrorText(Object e) {
    final l10n = AppLocalizations.of(context);
    if (e is! PenMonitorException) return l10n.csErrorGeneric('$e');
    return switch (e.error) {
      PenMonitorError.toolMissing => l10n.quPenToolMissing(e.tool ?? ''),
      PenMonitorError.toolFailed => l10n.quPenToolFailed(e.tool ?? ''),
      PenMonitorError.noMonitor => l10n.quPenNoMonitor,
      PenMonitorError.noPen => l10n.quPenNoDevice,
      PenMonitorError.badGeometry => l10n.quPenBadGeometry,
    };
  }

}
