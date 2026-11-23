// The editor's pointer pipeline: pen, touch and mouse down/move/up/cancel,
// palm rejection, barrel buttons, long press, pinch and the live gesture
// notifiers the painter listens to. The screen forwards its Listener here.

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/core/platform/device_class.dart';
import 'package:abelnotes/core/platform/io.dart' as io;
import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/core/services/pen_input_channel.dart'
    if (dart.library.js_interop) 'package:abelnotes/core/services/pen_input_channel_web.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/features/canvas/presentation/canvas_painter_notifiers.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_types.dart';
import 'package:abelnotes/features/canvas/presentation/editor/element_hit_test.dart';
import 'package:abelnotes/features/canvas/presentation/editor/page_view_transform.dart';
import 'package:abelnotes/features/canvas/presentation/pdf_text_selection.dart';
import 'package:abelnotes/features/canvas/presentation/pen_contact.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

class EditorPointerController {
  EditorPointerController({
    required this.ref,
    required this.canvasStackKey,
    required this.zoomSnapshot,
    required this.pdfTileVersion,
    required this.isMounted,
    required this.ensurePdfTextSel,
    required this.handleTextTool,
    required this.editMath,
    required this.pickAndInsertImage,
    required this.showContextMenu,
    required this.checkPageDrag,
    required this.commitOrCancelPageDrag,
    required this.clearPageHints,
    required this.commitLassoTransform,
    required this.tryOpenLinkAt,
    required this.maybeHintMouseDraw,
  });

  final WidgetRef ref;
  /// Key of the canvas stack, the pointer events' coordinate space.
  final GlobalKey canvasStackKey;
  final Listenable zoomSnapshot;
  final Listenable pdfTileVersion;
  final bool Function() isMounted;
  final PdfTextSelectionController? Function(CanvasState state) ensurePdfTextSel;
  final void Function(Offset localPos, CanvasState state, Size canvasSize) handleTextTool;
  final void Function(MathElement element) editMath;
  final void Function(Offset pagePos) pickAndInsertImage;
  final void Function(Offset globalPos, Offset localPos, CanvasState state, Size canvasSize)
      showContextMenu;
  final void Function(CanvasState state, Size canvasSize, {Offset? panOverride}) checkPageDrag;
  final void Function(CanvasState state, Size canvasSize) commitOrCancelPageDrag;
  final void Function() clearPageHints;
  final void Function() commitLassoTransform;
  final bool Function(CanvasState state, Offset pagePos) tryOpenLinkAt;
  final void Function(List<Offset> marquee) maybeHintMouseDraw;

  /// Flushes the deferred stylus commit as the editor closes, so a partial
  /// stroke is not lost. Clearing the notifiers happens in [dispose].
  void flushOnDispose() {
    deferredCommitTimer?.cancel();
    deferredCommitTimer = null;
    if (deferredCommitPoints != null) {
      try {
        ref.read(canvasProvider.notifier).commitAndEndStroke(deferredCommitPoints!);
      } catch (_) {
        // Provider may already be disposed; swallow.
      }
      deferredCommitPoints = null;
      deferredCommitAt = null;
      deferredCommitLastScreenPos = null;
    }
  }

  void dispose() {
    activeStroke.dispose();
    lassoPath.dispose();
    lassoTransform.dispose();
    elementTransform.dispose();
    laserStroke.dispose();
    holdRecognizeTimer?.cancel();
    longPressTimer?.cancel();
    mouseHoverCursor.dispose();
    mouseSeen.dispose();
    webPenHoverTimer?.cancel();
    penHoverPos.dispose();
  }

  bool _isTouchPanning = false;

  // Pinch-to-zoom state
  int _activePointers = 0;
  double _baseZoom = 1.0;
  Offset _lastFocalPoint = Offset.zero;

  /// Set while [_lastFocalPoint] holds a pinch's focal point — the midpoint
  /// between two fingers — instead of a single pointer's position. The
  /// single-pointer pan paths must re-anchor before using it as their origin.
  bool _panAnchorFromPinch = false;

  // Lasso drag
  bool _isDraggingSelection = false;
  Offset _lastLassoDragPos = Offset.zero;

  // Hold-to-recognize shape (GoodNotes style)
  Timer? holdRecognizeTimer;
  bool _shapeRecognizedDuringHold = false;
  Offset _lastHoldCheckPos = Offset.zero;

  // Stylus barrel button — OneNote-style temporary tool override.
  // Two buttons supported (Wacom EMR / Surface / Galaxy stylus all
  // report the same Flutter button bits):
  //   - kTertiaryButton (0x04, upper barrel) → temporary eraser
  //   - kSecondaryButton (0x02, lower barrel) → temporary lasso
  // Whatever the user was using before the hold is restored on
  // pointer-up / pointer-cancel.
  bool barrelButtonOverride = false;
  CanvasTool? barrelButtonPreviousTool;

  // Override armed but the tip isn't touching: GTK reports a barrel press
  // made while hovering as the pointer-down, before any contact.
  bool _barrelAwaitingContact = false;

  // Hovering pen's tool hint (eraser radius / lasso badge), canvas-local;
  // kept out of CanvasState so autosave/sync don't read it as an erase.
  int? _penHoverPointer;
  final ValueNotifier<Offset?> penHoverPos = ValueNotifier<Offset?>(null);

  // Web: touch-screen pens send a stray hover sample where they lift and
  // never leave, which pinned the hover badge there. See updatePenHover.
  Timer? webPenHoverTimer;
  DateTime? _webPenUpAt;
  PenHoverHint penHoverHint = PenHoverHint.eraser;

  // Hint comes from a held barrel, not the dock tool.
  bool penHoverBarrel = false;

  // GTK and browsers send a side-button press while hovering as a down.
  static final bool _downMayPrecedeContact = kIsWeb || io.Platform.isLinux;

  // Long-press context menu for touch
  Timer? longPressTimer;
  Offset _longPressGlobalPos = Offset.zero;
  bool _longPressFired = false;

  // Track last stroke activity to suppress long-press menu while drawing
  DateTime _lastStrokeActivity = DateTime(0);

  // Track whether the stylus is physically touching the screen right now
  bool stylusDown = false;

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
  Timer? deferredCommitTimer;
  List<StrokePoint>? deferredCommitPoints;
  DateTime? deferredCommitAt;
  Offset? deferredCommitLastScreenPos;

  /// True for the very next pointer-move after a "continuation" decision —
  /// lets us double-check that the new pointer position is actually close
  /// to the tail of the kept-alive stroke. If the user really started a
  /// fresh stroke that just happened to land within the defer window, the
  /// first move will be far away from the kept tail; in that case we
  /// commit the old stroke and start a new one. Without this guard, the
  /// new mark would graft onto the previous stroke, producing the
  /// "phantom line stretching from the old end-point" bug.
  bool _justContinuedFromDefer = false;

  // Double-tap detection for element selection
  DateTime _lastTapTime = DateTime(0);
  Offset _lastTapPos = Offset.zero;

  // Cached canvas size for pointer-up page-drag commit
  Size lastCanvasSize = Size.zero;

  // ── High-performance active stroke notifier ──
  final activeStroke = ActiveStrokeNotifier();

  // ── High-performance lasso path notifier (avoids Riverpod rebuild per point) ──
  final lassoPath = LassoPathNotifier();

  // ── Laser pointer trail (fades out, never committed) ──
  final laserStroke = LaserStrokeNotifier();

  // ── Live transform of an existing lasso selection (drag/rotate/scale) ──
  // Updated on every pointer-move so the painter repaints without firing
  // a Riverpod state update; committed back to Riverpod once on pan-end.
  final lassoTransform = LassoTransformNotifier();

  // ── Live transform of a single non-lasso element (image / shape / text
  // selected via double-tap). Same purpose as the lasso notifier — bypass
  // Riverpod during the gesture, commit once on pan-end.
  final elementTransform = ElementTransformNotifier();

  late final Listenable repaintNotifier = Listenable.merge([
    zoomSnapshot,
    activeStroke,
    lassoPath,
    lassoTransform,
    elementTransform,
    laserStroke,
    // imageCache changes (asset decode lands, eviction, pull merge)
    // ride the same repaint listenable now — used to be observed via
    // ref.watch(canvasProvider.select(s.imageCache)) which fired the
    // full Riverpod consumer cascade on every PDF-import decode.
    ref.read(canvasProvider.notifier).imageCacheVersion,
    // Math raster fills bump this so the equation appears on the next frame.
    ref.read(canvasProvider.notifier).mathCacheVersion,
    pdfTileVersion,
  ]);

  /// True while a device-aware text-selection drag is in progress (mouse over
  /// text). Gates the move/up handlers so the drag is independent of the tool.
  bool _pdfTextDragActive = false;

  /// True while the mouse is dragging a marquee (the mouse is a pure selection
  /// device — it never draws). Drives [lassoPath] directly.
  bool _mouseSelecting = false;

  /// Which physical input last touched the canvas — null until the first
  /// pointer event. Used only to decide, at the moment of an EXPLICIT tool
  /// pick (dock tap / keyboard shortcut, see [_pickTool]), whether that pick
  /// was meant for the mouse. Kept up to date from [onPointerDown] and the
  /// hover handler so it reflects the device currently in the user's hand,
  /// not just whichever last happened to click.
  bool? get lastPointerWasMouse => mouseSeen.value;
  set lastPointerWasMouse(bool? v) => mouseSeen.value = v;

  /// Notifies when the device in hand changes, so the dock can follow it.
  final ValueNotifier<bool?> mouseSeen = ValueNotifier<bool?>(null);

  /// The iPad app gets every hover as a mouse, the Apple Pencil hovering
  /// above the glass (M2 iPads and later) included, so there a hover says
  /// nothing about the device in the hand and only a click does. Trusting
  /// it flipped the dock to Lasso (the mouse's selection mode) while the
  /// Pencil kept drawing with the pen.
  static final bool hoverKindUnreliable =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Ink tools for which the MOUSE acts as a selection device instead
  /// (text / element / marquee). Pan, lasso, the erasers, and the explicit
  /// shape/laser tools are excluded — they keep their own mouse behaviour, so
  /// the mouse can still draw a shape or point the laser when deliberately
  /// chosen.
  static const Set<CanvasTool> mouseSelectTools = {
    CanvasTool.pen,
    CanvasTool.ballpoint,
    CanvasTool.brush,
    CanvasTool.calligraphy,
    CanvasTool.highlighter,
  };

  DateTime _lastMouseClickTime = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastMouseClickPos = Offset.zero;

  /// Cursor shown while a MOUSE hovers the canvas (null ⇒ use the tool's
  /// default — e.g. the pen crosshair). Set device-aware in onPointerHover so
  /// the pen keeps its drawing cursor while the mouse shows the selection one
  /// (arrow, or I-beam over PDF text).
  final ValueNotifier<MouseCursor?> mouseHoverCursor =
      ValueNotifier<MouseCursor?>(null);

  /// `UITouch.maximumPossibleForce` of an Apple Pencil (500/120).
  static const double _applePencilMaxForce = 4.1666666667;

  /// Active native-barrel override — `null` when neither side button
  /// is held. Distinct from `barrelButtonOverride` (which is the
  /// pointer-event-side override for Wacom-class stylus pens that DO
  /// report buttons through Flutter's normal pipeline).
  NativeBarrel? activeNativeBarrel;
  CanvasTool? nativeBarrelPreviousTool;

  /// Pointer IDs of synth middle-mouse events the Gaomon driver injects
  /// in parallel with the real stylus stream when barrel-held + tip-
  /// contact. Tracked so the matching move/up/cancel can be dropped
  /// without touching `_activePointers` — otherwise the parallel synth
  /// pointer pushes the counter to 2 and the multi-touch guard in
  /// `onPointerMove` drops every lasso point.
  final Set<int> _suppressedSynthBarrelPointers = <int>{};

  /// Pointer IDs of palm touches that landed while the stylus was drawing.
  /// They are ignored on DOWN — and must NOT stay counted in
  /// `_activePointers` either: a counted palm froze the stylus stroke
  /// (the `>= 2` guard in `onPointerMove` dropped every pen move) and
  /// suppressed the pen-up commit, losing all ink drawn after the wrist
  /// touched the screen. Tracked so their UP/CANCEL skips the decrement.
  final Set<int> ignoredPalmPointers = <int>{};

  // ── Web palm rejection ──
  //
  // Natively iPadOS drops a resting palm by itself while the Pencil is in
  // use. Safari doesn't: the palm reaches the page as ordinary touches. The
  // case above (palm lands while the pen is down) was already covered, but
  // a palm landing just BEFORE the pen made the pen the second pointer,
  // which reads as a two-finger pinch: the stroke in progress was cancelled
  // and the pen drew nothing until the hand lifted — strokes "vanishing"
  // whenever the user wrote quickly. On the web the pen therefore always
  // wins, and a touch right after pen activity is a palm.

  /// Touch pointers currently down and counted (web only).
  final Set<int> _webTouchPointers = <int>{};

  /// Last stylus down/move/up (web only).
  DateTime? _lastStylusAt;

  /// How long after the pen was last on the glass a touch is still a palm.
  static const Duration _webPalmWindow = Duration(milliseconds: 800);

  /// Tool the current bridge-driven pen gesture is driving. Set on
  /// `onBarrelPen("down", …)` from the live state and used through
  /// `"up"` so the commit doesn't depend on `activeNativeBarrel`
  /// still being non-null at that moment (the C++ bridge fires "up"
  /// before any matching barrel-release transition, so this normally
  /// holds — but if the user releases the barrel BEFORE lifting the
  /// tip the bridge tears the gesture down first, and the captured
  /// tool here lets us still commit the partial path).
  CanvasTool? _bridgePenTool;

  /// True after the barrel was released mid-gesture; onPointerUp resolves the
  /// keep-or-revert once the lasso / text selection has actually committed.
  bool _barrelRevertPending = false;

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
  void flushDeferredCommit() {
    final pts = deferredCommitPoints;
    if (pts == null) return;
    deferredCommitPoints = null;
    deferredCommitAt = null;
    deferredCommitLastScreenPos = null;
    deferredCommitTimer?.cancel();
    deferredCommitTimer = null;
    // Clear the live notifier BEFORE the commit so the painter, which
    // pulls from the notifier when it has points, doesn't keep drawing
    // the old stroke as "live" alongside the freshly-committed one.
    // Forgetting this clear was the cause of the "phantom segment from
    // a previous stroke when I start drawing again" bug — if the next
    // pointer event arrived as a MOVE rather than a fresh DOWN (iPad
    // sometimes resumes from a hovering pen this way), the move would
    // append to the still-active notifier and the user saw a line from
    // the old end-point stretching to where they really wrote.
    activeStroke.clear();
    _justContinuedFromDefer = false;
    ref.read(canvasProvider.notifier).commitAndEndStroke(pts);
    activeStroke.clear();
    _markStrokeEnded('pointerUp.commit');
  }

  /// Mouse counterpart of the touch/trackpad double-tap zoom toggle (the
  /// scale recognizer deliberately excludes the mouse).
  void mouseDoubleClickZoom(PointerDownEvent e, CanvasState live) {
    if (e.kind != PointerDeviceKind.mouse ||
        e.buttons != kPrimaryMouseButton ||
        (live.currentTool != CanvasTool.pan &&
            live.currentTool != CanvasTool.image)) {
      return;
    }
    final now = DateTime.now();
    final isDouble = now.difference(_lastMouseClickTime).inMilliseconds < 400 &&
        (e.localPosition - _lastMouseClickPos).distance < 30;
    _lastMouseClickTime = isDouble ? DateTime.fromMillisecondsSinceEpoch(0) : now;
    _lastMouseClickPos = e.localPosition;
    if (!isDouble) return;
    final notifier = ref.read(canvasProvider.notifier);
    if (live.zoom < 1.4) {
      notifier.resetZoom();
    } else {
      notifier.zoomToFit();
    }
  }

  /// Pressure for the active pen sample, with the Linux fallback applied.
  ///
  /// On Linux the GTK embedder always reports `event.pressure == 0` for a
  /// stylus (flutter#63209), so we substitute the latest real pressure the
  /// native bridge captured. Everywhere else (and when no fresh bridge
  /// sample exists) we return the raw event pressure unchanged — devices
  /// that genuinely have no pressure (mouse) keep returning 0 so the
  /// notifier's velocity-synth path still kicks in.
  double penPressure(PointerEvent event) {
    final p = _rawPenPressure(event);
    // Pressure switched off: a fixed value, the one strokes without
    // pressure start from, so every pen stroke gets the same width. A pen's
    // zero samples get it too: the Apple Pencil can report 0 as it leaves
    // the glass at the end of a fast stroke, and passing those through
    // still tapered the stroke's end. A mouse or a finger keeps its 0 (no
    // pressure at all), which the live stroke turns into speed-based width.
    if (!ref.read(appSettingsProvider).pressureWidth &&
        (p > 0 || isPenEvent(event))) {
      return 0.6;
    }
    return p;
  }

  double _rawPenPressure(PointerEvent event) {
    final raw = _normalizedEventPressure(event);
    if (raw > 0.0 || kIsWeb || !io.Platform.isLinux) return raw;
    final bridged = LinuxPenPressure.latest();
    return bridged > 0 ? bridged : raw;
  }

  /// True when this `kind == mouse` event is really a stylus that GDK
  /// mislabelled as a generic pointer.
  ///
  /// Flutter's GTK embedder classifies a pointer from
  /// `gdk_device_get_source()` (fl_view.cc `get_pointer_device_kind`).
  /// Many touchscreen digitizers and driverless tablets (Gaomon / Huion /
  /// XP-Pen, and some Wacom-AES panels on Wayland + Xwayland) report
  /// `GDK_SOURCE_MOUSE`, so their pen arrives as `PointerDeviceKind.mouse`
  /// even in modern Flutter. Left unhandled, a tip-down on a drawing tool
  /// falls into the mouse-as-selector path (see `onPointerDown`) and never
  /// draws — the pen hovers the cursor but can't ink (issue on Fedora
  /// Wayland / Xwayland).
  ///
  /// The native bridge ([LinuxPenPressure]) reads `GDK_AXIS_PRESSURE` off
  /// the raw event regardless of the mislabelled source, so a non-zero
  /// bridged pressure is a positive "the tip is pressing" signal a real
  /// mouse can never produce (a mouse has no pressure axis, so the bridge
  /// stays at -1/0). We treat such an event as a stylus so it draws.
  bool _linuxPenAsMouse(PointerEvent event) {
    if (kIsWeb || !io.Platform.isLinux) return false;
    if (event.kind != PointerDeviceKind.mouse) return false;
    return LinuxPenPressure.latest() > 0;
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
    // Web on iPad: Safari hands out the Pencil's force already divided by
    // its full scale (0..1), while the native iOS embedder passes the raw
    // force (0..maximumPossibleForce ≈ 4.17) and everything downstream —
    // smoothing, the renderer's width curve — is tuned on that. Undo
    // Safari's normalisation so a stroke has the same weight as in the app.
    if (kIsWeb &&
        isWebTouchDevice &&
        (event.kind == PointerDeviceKind.stylus ||
            event.kind == PointerDeviceKind.invertedStylus)) {
      return event.pressure * _applePencilMaxForce;
    }
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

  bool get webPenRecentlyActive =>
      kIsWeb &&
      _lastStylusAt != null &&
      DateTime.now().difference(_lastStylusAt!) < _webPalmWindow;

  static bool isPenEvent(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus ||
      e.kind == PointerDeviceKind.invertedStylus;

  /// Web palm handling at pointer-down. Returns true when [event] is a palm
  /// and must be dropped.
  bool _webPalmDown(PointerEvent event) {
    if (!kIsWeb) return false;
    if (isPenEvent(event)) {
      _lastStylusAt = DateTime.now();
      if (_webTouchPointers.isEmpty) return false;
      // The palm got there first. Undo whatever it started (a finger
      // stroke, a pan) and hand the canvas to the pen.
      if (activeStroke.isActive && deferredCommitPoints == null) {
        activeStroke.clear();
        ref.read(canvasProvider.notifier).cancelStroke();
      }
      _isTouchPanning = false;
      cancelLongPressTimer();
      _activePointers = max(0, _activePointers - _webTouchPointers.length);
      ignoredPalmPointers.addAll(_webTouchPointers);
      _webTouchPointers.clear();
      return false;
    }
    if (event.kind == PointerDeviceKind.touch) {
      if (stylusDown || webPenRecentlyActive) {
        ignoredPalmPointers.add(event.pointer);
        _strokeDbg('PALM dropped p=${event.pointer}');
        return true;
      }
      _webTouchPointers.add(event.pointer);
    }
    return false;
  }

  /// The tool [action] switches to, null for none.
  CanvasTool? _penButtonToolFor(PenButtonAction action) => switch (action) {
        PenButtonAction.lasso => CanvasTool.lasso,
        PenButtonAction.eraser =>
          ref.read(canvasProvider.notifier).lastEraserMode,
        PenButtonAction.none => null,
      };

  /// Tool the held pen buttons of [event] switch to (eraser end: always the
  /// eraser; side buttons: as set in Settings), null when none acts.
  CanvasTool? penButtonTool(PointerEvent event) {
    if (isPenEraser(event)) {
      return ref.read(canvasProvider.notifier).lastEraserMode;
    }
    final settings = ref.read(appSettingsProvider);
    if ((event.buttons & kSecondaryStylusButton) != 0) {
      final tool = _penButtonToolFor(settings.penUpperButton);
      if (tool != null) return tool;
    }
    if ((event.buttons & kPrimaryStylusButton) != 0) {
      return _penButtonToolFor(settings.penLowerButton);
    }
    return null;
  }

  /// Called by the WM_POINTER bridge when the user presses or releases
  /// a side button. Press = save the current tool and switch to the
  /// override target; release = restore.
  void onNativeBarrelChange(NativeBarrel button, bool down) {
    if (!isMounted()) return;
    final notif = ref.read(canvasProvider.notifier);
    final state = ref.read(canvasProvider);
    if (state == null) return;

    if (down) {
      // Already in another override → ignore the second press so the
      // restore-tool slot doesn't get clobbered.
      if (activeNativeBarrel != null) return;
      final settings = ref.read(appSettingsProvider);
      final tool = _penButtonToolFor(button == NativeBarrel.upper
          ? settings.penUpperButton
          : settings.penLowerButton);
      if (tool == null) return;
      activeNativeBarrel = button;
      nativeBarrelPreviousTool = state.currentTool;
      notif.setTool(tool);
      HapticFeedback.selectionClick();
    } else {
      // Release only restores if we were actually overriding via
      // THIS button — guards against the C++ defensive-release path
      // firing twice or a transient flap.
      if (activeNativeBarrel != button) return;
      activeNativeBarrel = null;
      // If the lower-barrel lasso override just committed a real
      // selection (polygon caught at least one element), stay in
      // lasso so the user can manipulate it — drag / scale / rotate
      // / duplicate / delete. Restoring the previous tool here would
      // run `setTool(prev)`, whose `clearLasso: tool != lasso`
      // copyWith wipes `lassoSelection` and the marquee visibly
      // disappears the instant the user releases the barrel. We
      // KEEP `nativeBarrelPreviousTool` set in that case — the
      // `_watchForLassoCleared` listener restores the tool when the
      // user eventually deselects (tap outside / clearSelection /
      // anything that nulls `lassoSelection`).
      final live = ref.read(canvasProvider);
      final keepLassoForSelection = live?.currentTool == CanvasTool.lasso &&
          live?.lassoSelection != null;
      if (keepLassoForSelection) return;
      // Race fix: if the pen gesture is still in progress, the lasso / text
      // selection hasn't committed yet (it commits on pointer-up). Reverting
      // now would wipe a selection the user is mid-way through making — the
      // "faccio il cerchio e mollo, non mi prende la selezione" bug. Defer the
      // keep/revert to onPointerUp (see _resolveBarrelRevert).
      if (stylusDown || _pdfTextDragActive) {
        _barrelRevertPending = true;
        return;
      }
      final prev = nativeBarrelPreviousTool;
      nativeBarrelPreviousTool = null;
      if (prev != null) notif.setTool(prev);
    }
  }

  /// Resolve a deferred barrel revert (see [onNativeBarrelChange]). Keeps
  /// lasso mode when elements were selected, otherwise restores the pre-barrel
  /// tool. A PDF text selection persists regardless (it isn't tool-bound).
  void _resolveBarrelRevert() {
    if (!_barrelRevertPending) return;
    _barrelRevertPending = false;
    if (activeNativeBarrel != null) return; // barrel re-pressed; it will own it
    final live = ref.read(canvasProvider);
    if (live?.lassoSelection != null) {
      // Stay in lasso so the marquee is interactive; _watchForLassoCleared
      // restores the previous tool when the user deselects.
      return;
    }
    final prev = nativeBarrelPreviousTool;
    nativeBarrelPreviousTool = null;
    if (prev != null) ref.read(canvasProvider.notifier).setTool(prev);
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
  /// as "global". We convert to canvas-local via `canvasStackKey`'s
  /// RenderBox, then to page coords via `toPageCoords`.
  void onBarrelPen(String phase, Offset clientPos, double pressure) {
    if (!isMounted()) return;
    // Modern Flutter Windows embedders (3.4x) deliver the pen through the
    // normal pointer pipeline (kind=stylus, WM_POINTER) even while a side
    // button is held — the "Gaomon driverless suppresses PointerEvents"
    // behaviour this synthesis was written for no longer applies there.
    // When a real stylus pointer is down, the regular
    // onPointerDown/Move/Up flow owns the gesture: letting the bridge
    // drive it in parallel double-feeds the lasso path with points from a
    // second coordinate transform and commits it early, so the stylus
    // PointerUp then found an empty path and wiped the fresh selection.
    // The bridge only drives when Flutter is receiving nothing.
    if (stylusDown) return;
    final box = canvasStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final localPos = box.globalToLocal(clientPos);
    final state = ref.read(canvasProvider);
    if (state == null) return;
    final pagePos = toPageCoords(localPos, state, lastCanvasSize);

    final notif = ref.read(canvasProvider.notifier);
    final p = pressure > 0 ? pressure : 0.5;
    switch (phase) {
      case 'down':
        _bridgePenTool = state.currentTool;
        if (_bridgePenTool == CanvasTool.lasso) {
          notif.clearLassoPath();
          lassoPath.start(pagePos);
        } else if (_bridgePenTool == CanvasTool.eraserStandard ||
            _bridgePenTool == CanvasTool.eraserStroke) {
          notif.startStroke(pagePos, p);
        }
        break;
      case 'move':
        if (_bridgePenTool == CanvasTool.lasso && lassoPath.isActive) {
          lassoPath.addPoint(pagePos);
        } else if (_bridgePenTool == CanvasTool.eraserStandard ||
            _bridgePenTool == CanvasTool.eraserStroke) {
          notif.continueStroke(pagePos, p);
        }
        break;
      case 'up':
        if (_bridgePenTool == CanvasTool.lasso && lassoPath.isActive) {
          final pts = List<Offset>.from(lassoPath.points);
          lassoPath.clear();
          notif.commitLassoPath(pts);
        } else if (_bridgePenTool == CanvasTool.eraserStandard ||
            _bridgePenTool == CanvasTool.eraserStroke) {
          notif.endStroke();
        }
        _bridgePenTool = null;
        break;
    }
  }

  void _startLongPressTimer(Offset globalPos, Offset localPos, CanvasState state, Size canvasSize) {
    cancelLongPressTimer();
    // Never show context menu while stylus is actively touching the screen
    // (the touch event is almost certainly a palm).
    if (stylusDown) return;
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
    longPressTimer = Timer(const Duration(milliseconds: 600), () {
      longPressTimer = null;
      // Recheck guards at fire time — a palm could have landed during
      // the 600 ms wait. Don't open the menu if any of those triggered.
      if (stylusDown) return;
      if (_activePointers != 1) return;
      if (DateTime.now().difference(_lastStrokeActivity).inMilliseconds < 8000) return;
      _longPressFired = true;
      final latestState = ref.read(canvasProvider);
      if (latestState != null) {
        showContextMenu(globalPos, localPos, latestState, canvasSize);
      }
    });
  }

  void cancelLongPressTimer() {
    longPressTimer?.cancel();
    longPressTimer = null;
  }

  Offset toPageCoords(Offset localPos, CanvasState state, Size canvasSize) {
    return PageViewTransform.of(state, canvasSize).toPage(localPos);
  }

  Offset toScreenCoords(Offset pagePos, CanvasState state, Size canvasSize) {
    return PageViewTransform.of(state, canvasSize).toScreen(pagePos);
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
  /// the suppression in [onPointerUp]).
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

  double getRenderScale(CanvasState state, Size canvasSize) {
    return PageViewTransform.of(state, canvasSize).renderScale;
  }

  /// Offset that centres the fitted page inside the viewport. Zero for
  /// scratch mode (the big page isn't fit-centred; panOffset positions it).
  /// MUST stay in lock-step with [CanvasRenderEngine.paint]'s centerOffset.
  Offset getCenterOffset(CanvasState state, Size canvasSize) {
    return PageViewTransform.of(state, canvasSize).center;
  }

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

  /// Whether touch should be treated as pan-only (true) or as a drawing
  /// device on par with the stylus (false). Off unless the user turns on
  /// Settings → Stylus & Input → stylus only: a finger draws whatever tool
  /// is armed, and the dock's pan tool is how the user says "don't draw".
  bool effectiveStylusOnly() {
    return ref.read(appSettingsProvider).stylusOnlyDrawing ?? false;
  }

  bool _shouldTouchPan(PointerDeviceKind kind, CanvasTool tool) {
    return effectiveStylusOnly() && kind == PointerDeviceKind.touch && _isDrawLikeTool(tool);
  }

  // Out-of-contact pen sample: some Linux stacks send proximity as
  // PointerMoveEvent without the contact bit instead of PointerHoverEvent.
  bool _isPenHoverSample(PointerEvent event) {
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return false;
    }
    return event is PointerHoverEvent ||
        (event is PointerMoveEvent &&
            !penTipTouches(event.buttons, downMayPrecedeContact: true));
  }

  void updatePenHover(PointerEvent event, CanvasState? state) {
    // Tip down (a barrel press may have been the pointer-down) or another
    // device: no hover hint.
    if (!_isPenHoverSample(event)) {
      clearPenHover();
      return;
    }
    final buttonTool = penButtonTool(event);
    final tool = state?.currentTool;
    final PenHoverHint? hint = buttonTool != null
        ? (isEraserTool(buttonTool) ? PenHoverHint.eraser : PenHoverHint.lasso)
        : tool == null
                ? null
                : isEraserTool(tool)
                    ? PenHoverHint.eraser
                    : tool == CanvasTool.lasso
                        ? PenHoverHint.lasso
                        : null;
    if (hint == null) {
      clearPenHover();
      return;
    }
    if (kIsWeb) {
      // Right after a lift it is the tap's leftover, not a hover. A pen that
      // really hovers keeps sending samples, so the badge stays up for it.
      final up = _webPenUpAt;
      if (up != null &&
          DateTime.now().difference(up) < const Duration(milliseconds: 150)) {
        return;
      }
      webPenHoverTimer?.cancel();
      webPenHoverTimer =
          Timer(const Duration(milliseconds: 300), clearPenHover);
    }
    _penHoverPointer = event.pointer;
    penHoverBarrel = buttonTool != null;
    penHoverHint = hint;
    penHoverPos.value = _stylusLocalPosition(event);
  }

  void clearPenHover() {
    webPenHoverTimer?.cancel();
    webPenHoverTimer = null;
    _penHoverPointer = null;
    penHoverBarrel = false;
    penHoverPos.value = null;
  }

  // Hides the hover preview when the pen leaves proximity or the canvas
  // without a MouseRegion exit (e.g. over the dock).
  void onGlobalPointerEvent(PointerEvent event) {
    if (event.pointer != _penHoverPointer) return;
    if (event is PointerRemovedEvent) {
      clearPenHover();
      return;
    }
    if (!_isPenHoverSample(event)) return;
    final box = canvasStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached ||
        !(Offset.zero & box.size).contains(box.globalToLocal(event.position))) {
      clearPenHover();
    }
  }

  void onPointerDown(PointerEvent event, CanvasState state, Size canvasSize) {
    clearPenHover();
    // Gaomon driverless: barrel-held + tip-contact arrives as a
    // synth mouse event in parallel with the suppressed pen stream.
    // For the lower barrel it's WM_MBUTTONDOWN (kind=mouse,
    // buttons=0x4 = middle); for the upper barrel it's
    // WM_LBUTTONDOWN (kind=mouse, buttons=0x1 = left). Either way
    // the C++ bridge has already switched tool and is driving the
    // gesture via `onBarrelPen` — we don't want the synth click
    // ALSO landing in the regular pointer flow (would start a
    // phantom stroke / pan at the cursor location). Drop any
    // non-zero-button mouse DOWN while a barrel override is active.
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != 0 &&
        activeNativeBarrel != null) {
      _suppressedSynthBarrelPointers.add(event.pointer);
      return;
    }
    if (_webPalmDown(event)) return;
    _activePointers++;
    _panAnchorFromPinch = false;
    lastPointerWasMouse = event.kind == PointerDeviceKind.mouse;

    // A pen/touch interaction reverts the cursor to the tool default (so a
    // stale mouse-selection arrow doesn't linger while drawing with the pen).
    if (event.kind != PointerDeviceKind.mouse &&
        mouseHoverCursor.value != null) {
      mouseHoverCursor.value = null;
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
      final pagePos = toPageCoords(event.localPosition, state, canvasSize);
      final n = ref.read(canvasProvider.notifier);
      n.paste(at: pagePos);
      n.cancelPendingPaste();
      return;
    }

    // Pending symbol placement via mouse LEFT click — the same hole the paste
    // branch above plugs, and for the same reason: the marquee block below
    // returns on every left click with a drawing/lasso tool armed, so the
    // touch/pen placement check further down never ran on desktop. The
    // "tocca per posizionare" banner appeared and the click did nothing.
    // Nothing arms pendingSymbol today (the library places on tap instead),
    // but leaving the path broken is how it silently breaks again.
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton &&
        state.pendingSymbol != null) {
      final pagePos = toPageCoords(event.localPosition, state, canvasSize);
      ref.read(canvasProvider.notifier).insertSymbol(state.pendingSymbol!, pagePos);
      return;
    }

    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton &&
        !_linuxPenAsMouse(event) &&
        (state.currentTool == CanvasTool.lasso ||
            (!ref.read(appSettingsProvider).mouseDraws &&
                mouseSelectTools.contains(state.currentTool)))) {
      final pagePos = toPageCoords(event.localPosition, state, canvasSize);
      final notif = ref.read(canvasProvider.notifier);
      final isDouble = _isDoubleTap(event.localPosition);

      // 1. PDF text under the cursor → text selection.
      final sel = ensurePdfTextSel(state);
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
          lassoTransform.begin(
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
      final elId = ElementHitTest.findElementAt(state, pagePos, skipLocked: !isDouble);
      if (elId != null) {
        // Double-click a text element → open the rich text editor (the topmost
        // text under the cursor must be the hit element, i.e. not behind an
        // image). Single click still just selects it.
        if (isDouble) {
          final txt = ElementHitTest.findTextElementAt(state, pagePos);
          if (txt != null && txt.id == elId) {
            handleTextTool(event.localPosition, state, canvasSize);
            return;
          }
          // A math element: its LaTeX editor.
          final math = state.currentPage?.layers.content
              .whereType<MathElement>()
              .where((e) => e.id == elId)
              .firstOrNull;
          if (math != null) {
            notif.selectElement(elId);
            editMath(math);
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
      lassoPath.start(pagePos,
          minStep: 3 * _pageUnitsPerScreenPx(state, canvasSize));
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
      if (deferredCommitLastScreenPos != null) {
        final d = (event.position - deferredCommitLastScreenPos!).distance;
        distStr = ' deferDist=${d.toStringAsFixed(1)}px';
      }
      _strokeDbg(
        'DOWN stylus p=${event.pointer} t=${event.timeStamp.inMilliseconds}ms '
        'gap=${gapMs}ms prevEnd=$_lastStrokeEndReason '
        'tool=${state.currentTool.name} '
        'active=${activeStroke.isActive} '
        'activePointers=$_activePointers$distStr'
        '${isBreakSusp ? " BREAK_SUSPECTED" : ""} '
        'adjusting=${state.isAdjustingRecognized} '
        'shape=${state.recognizedShape?.shapeType} '
        'selected=${state.selectedElementId != null} '
        'lasso=${state.lassoSelection != null} '
        'paste=${state.pendingPaste}',
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
      final deferredPts = deferredCommitPoints;
      if (deferredPts != null && deferredCommitAt != null && deferredCommitLastScreenPos != null) {
        final defGapMs = now.difference(deferredCommitAt!).inMilliseconds;
        final defDist = (event.position - deferredCommitLastScreenPos!).distance;
        if (defGapMs < _deferStylusMs && defDist < _deferStylusPx) {
          deferredCommitTimer?.cancel();
          deferredCommitTimer = null;
          deferredCommitPoints = null;
          deferredCommitAt = null;
          deferredCommitLastScreenPos = null;
          _justContinuedFromDefer = true;
          _strokeDbg(
            'CONTINUATION p=${event.pointer} '
            'gap=${defGapMs}ms dist=${defDist.toStringAsFixed(1)}px '
            'liveStrokePts=${activeStroke.points.length}',
          );
          stylusDown = true;
          cancelLongPressTimer();
          return;
        }
        // Out of range → flush the pending commit before starting a new one
        flushDeferredCommit();
      }

      stylusDown = true;
      cancelLongPressTimer(); // kill any pending palm long-press immediately
    }

    if (_activePointers >= 2) {
      // Palm rejection: if a stylus is already drawing and the incoming
      // second pointer is a touch (the user's wrist landing on the screen
      // while writing), DO NOT treat this as a pinch-to-zoom. Previously
      // we cancelled the active stroke here the moment the palm touched
      // down, which wiped the first few strokes the user had just drawn.
      // Instead, ignore the palm touch entirely — the Listener keeps
      // feeding stylus moves to onPointerMove, and the scale handlers
      // below also early-return while stylusDown is true.
      if (stylusDown && event.kind == PointerDeviceKind.touch) {
        // Un-count the palm: leaving it in _activePointers blocks every
        // subsequent stylus move (>= 2 guard in onPointerMove) and
        // suppresses the pen-up commit. Its own UP/CANCEL is skipped via
        // ignoredPalmPointers so the counter stays balanced.
        _activePointers = max(0, _activePointers - 1);
        ignoredPalmPointers.add(event.pointer);
        cancelLongPressTimer();
        return;
      }
      // True multi-touch (two fingers, no stylus): pinch-to-zoom gesture.
      _strokeDbg('MULTITOUCH p=${event.pointer} kind=${event.kind.name} '
          'activePointers=$_activePointers');
      if (activeStroke.isActive) {
        activeStroke.clear();
        ref.read(canvasProvider.notifier).cancelStroke();
      }
      _isTouchPanning = false;
      cancelLongPressTimer();
      return;
    }

    // Ctrl/Cmd + click on a text element that contains a URL → open the
    // link in the system browser instead of drawing. Mouse-only (Ctrl+click
    // is a desktop interaction); the tip-down keeps drawing as normal.
    if (event.kind == PointerDeviceKind.mouse &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      final linkPos = toPageCoords(event.localPosition, state, canvasSize);
      if (tryOpenLinkAt(state, linkPos)) return;
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
        activeNativeBarrel == null) {
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
    //   - eraser end → eraser
    //   - upper / lower barrel → the tool set in Settings (default eraser /
    //     lasso), see [penButtonTool]
    //
    // Pending modal states (pendingSymbol / selectedElement /
    // lassoSelection) get "escape first" — either path cancels the
    // modal instead of switching tool.
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      final buttonTool = penButtonTool(event);
      if (buttonTool != null) {
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

        final pagePos = toPageCoords(event.localPosition, state, canvasSize);
        barrelButtonOverride = true;
        barrelButtonPreviousTool = state.currentTool;

        // The eraser keeps the user's last picked sub-mode (per-stroke vs
        // per-area) so it feels like the dock button.
        ref.read(canvasProvider.notifier).setTool(buttonTool);
        if (!penTipTouches(event.buttons,
            downMayPrecedeContact: _downMayPrecedeContact)) {
          // Pressed while hovering: switch now, act once the tip touches.
          _barrelAwaitingContact = true;
          return;
        }
        _beginBarrelGesture(pagePos);
        return;
      }
    }

    final pagePos =
        toPageCoords(_stylusLocalPosition(event), state, canvasSize);
    final normPressure = _normalizedEventPressure(event);
    final pressure = normPressure > 0 ? normPressure : 0.5;

    // Touch pan: only if no selected image is under the finger
    if (_shouldTouchPan(event.kind, tool)) {
      // If there's a selected element and we're touching it, let the overlay handle it
      if (state.selectedElementId != null) {
        final selBounds = ElementHitTest.getSelectedElementBounds(state);
        // Expand bounds to include the action bar and handles above the element.
        // The action bar sits ~92px above in screen coords; convert to page coords.
        final scale = state.zoom * getRenderScale(state, canvasSize);
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
            final tappedImage = ElementHitTest.findImageOrShapeAt(state, pagePos);
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
          if (!activeStroke.isActive) {
            _startLongPressTimer(event.position, event.localPosition, state, canvasSize);
          }
          return;
        }
      } else {
        // No selection — double-tap an image to select it
        if (_isDoubleTap(event.localPosition)) {
          final tappedImage = ElementHitTest.findImageOrShapeAt(state, pagePos);
          if (tappedImage != null) {
            ref.read(canvasProvider.notifier).selectElement(tappedImage);
            return;
          }
        }
        _isTouchPanning = true;
        _lastFocalPoint = event.position;
        // Don't show context menu if stylus is actively drawing (palm rest)
        if (!activeStroke.isActive) {
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
      pickAndInsertImage(pagePos);
      return;
    }

    if (tool == CanvasTool.pan) {
      _lastFocalPoint = event.position;
      return;
    }

    if (tool == CanvasTool.text) {
      handleTextTool(event.localPosition, state, canvasSize);
      return;
    }

    // If there's a selected element, handle tap interactions.
    // For draw tools: stylus/tablet pen deselects and draws through; plain mouse can interact.
    // For non-draw tools: all input devices can interact.
    if (state.selectedElementId != null) {
      final isPenLikeDevice = event.kind == PointerDeviceKind.stylus ||
          (event.kind == PointerDeviceKind.mouse && event.pressure > 0) ||
          _linuxPenAsMouse(event) ||
          (event.kind == PointerDeviceKind.touch && !effectiveStylusOnly());
      // The lasso counts as "draw-like" everywhere else, but it is a
      // SELECTION tool: a pen or finger landing on the current selection
      // means "move this", never "deselect and mark here". Without the
      // exclusion, a symbol dropped into selection mode (insertSymbol arms
      // the lasso and selects the new element) deselected itself the instant
      // it was touched, so it could be seen selected but never dragged.
      // Mouse users never hit this — a pressure-less mouse isn't pen-like.
      final drawsThrough = _isDrawLikeTool(tool) && tool != CanvasTool.lasso;
      if (drawsThrough && isPenLikeDevice) {
        // Stylus/tablet pen in draw mode: deselect image and proceed to draw
        ref.read(canvasProvider.notifier).deselectElement();
      } else {
        final selBounds = ElementHitTest.getSelectedElementBounds(state);
        // Expand bounds to include action bar/handles above
        final scale = state.zoom * getRenderScale(state, canvasSize);
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
        // (the stray "black dot on deselect" the user reported)...
        ref.read(canvasProvider.notifier).deselectElement();
        // ...except for the lasso, which must still open a fresh marquee
        // from this point: returning here would make the first drag after
        // a deselect do nothing at all.
        if (tool != CanvasTool.lasso) return;
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
          lassoTransform.begin(
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
                 event.pressure <= 0 &&
                 !_linuxPenAsMouse(event)) {
        shouldCheckImageTap = true;
      } else {
        shouldCheckImageTap = false;
      }
      if (shouldCheckImageTap && _isDoubleTap(event.localPosition)) {
        final onlyImages = _isDrawLikeTool(tool);
        final tappedImageOrShape = ElementHitTest.findImageOrShapeAt(state, pagePos, imagesOnly: onlyImages);
        if (tappedImageOrShape != null) {
          ref.read(canvasProvider.notifier).selectElement(tappedImageOrShape);
          return;
        }
      }
    }

    // Starting any pen/eraser/shape gesture dismisses a PDF text selection.
    if (tool != CanvasTool.lasso &&
        tool != CanvasTool.pan &&
        tool != CanvasTool.text) {
      ensurePdfTextSel(state)?.clear();
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
      laserStroke.addPoint(pagePos, start: true);
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
      lassoPath.start(pagePos,
          minStep: 3 * _pageUnitsPerScreenPx(state, canvasSize));
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
    final rawPressureForPen = penPressure(event);
    if (isPenEvent(event)) _strokeDbg('START stroke p=${event.pointer}');
    ref.read(canvasProvider.notifier).startStroke(pagePos, pressure);
    activeStroke.start(pagePos, rawPressureForPen,
        pageUnitsPerPx: _pageUnitsPerScreenPx(state, canvasSize),
        integerCoords: _onIntegerPixels(event.position),
        eventTime: kIsWeb ? event.timeStamp : null);
    _lastStrokeActivity = DateTime.now();
    _lastHoldCheckPos = pagePos;
  }

  /// Whether a web pointer position sits on whole logical pixels — Safari's
  /// integer CSS-pixel coordinates (see ActiveStrokeNotifier._integerCoords).
  /// Always false natively, where the platform paths handle precision.
  bool _onIntegerPixels(Offset position) =>
      kIsWeb &&
      position.dx == position.dx.roundToDouble() &&
      position.dy == position.dy.roundToDouble();

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
    final scale = state.zoom * getRenderScale(state, canvasSize);
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
        canvasStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return event.localPosition;
    final local = box.globalToLocal(sample);
    if ((local - event.localPosition).distance > 3.0) {
      return event.localPosition;
    }
    return local;
  }

  /// Re-anchors the pan origin after a pinch, returning true when the caller
  /// must skip this move.
  ///
  /// Two fingers never leave the glass together. When the first one lifts,
  /// [onPointerMove] starts seeing the survivor while [_lastFocalPoint] still
  /// holds the midpoint the pinch left there — so the pan paths read the
  /// difference between the two as user movement and jump by half the finger
  /// spread. Only the pan tool shows it, because it is the only thing that
  /// treats that field as its origin.
  bool _reanchorPanAfterPinch(Offset position) {
    if (!_panAnchorFromPinch) return false;
    _panAnchorFromPinch = false;
    _lastFocalPoint = position;
    return true;
  }

  /// A side button pressed after the tip landed: ends what the tip was doing,
  /// then begins the barrel's gesture here as if it had been held from the
  /// start. The stylus commit is flushed so the next down is no continuation.
  void _restartStrokeForBarrel(PointerEvent event, CanvasState state, Size canvasSize) {
    onPointerUp(event);
    flushDeferredCommit();
    onPointerDown(event, ref.read(canvasProvider) ?? state, canvasSize);
  }

  void onPointerMove(PointerMoveEvent event, CanvasState state, Size canvasSize) {
    if (_suppressedSynthBarrelPointers.contains(event.pointer)) return;
    // Palm resting next to the stylus: its own moves must not draw/pan.
    if (ignoredPalmPointers.contains(event.pointer)) return;
    if (kIsWeb && isPenEvent(event)) _lastStylusAt = DateTime.now();
    if (_activePointers >= 2) return;

    final isPen = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    final contact = penTipTouches(event.buttons,
        downMayPrecedeContact: _downMayPrecedeContact);
    if (isPen && barrelButtonOverride) {
      // Released in the air without an up (KDE Wayland): the pen is back now,
      // not at the next touch.
      if (!contact &&
          event.kind == PointerDeviceKind.stylus &&
          (event.buttons & (kPrimaryStylusButton | kSecondaryStylusButton)) == 0) {
        _finishBarrel('pointerMove.barrelReleased');
        return;
      }
      // While a barrel is held the tip can land and lift without a new
      // pointer-down (GTK): only erase/select while it touches.
      if (contact == _barrelAwaitingContact) {
        _barrelAwaitingContact = !contact;
        if (contact) {
          _beginBarrelGesture(
              toPageCoords(event.localPosition, state, canvasSize));
        } else {
          _endBarrelGesture();
        }
        return;
      }
      if (_barrelAwaitingContact) return;
    } else if (isPen &&
        contact &&
        penButtonTool(event) != null) {
      _restartStrokeForBarrel(event, state, canvasSize);
      return;
    }

    // ── PDF text selection drag (device-aware; started in onPointerDown) ──
    if (_pdfTextDragActive) {
      ensurePdfTextSel(state)
          ?.update(toPageCoords(event.localPosition, state, canvasSize));
      return;
    }
    // ── Mouse marquee drag (mouse = selection device) ──
    if (_mouseSelecting) {
      lassoPath
          .addPoint(toPageCoords(event.localPosition, state, canvasSize));
      return;
    }

    if (_isTouchPanning) {
      if (_reanchorPanAfterPinch(event.position)) return;
      // Cancel long-press if finger moved significantly
      if (longPressTimer != null) {
        final moved = (event.position - _longPressGlobalPos).distance;
        if (moved > 10) cancelLongPressTimer();
      }
      if (_longPressFired) return; // Don't pan after context menu shown
      final delta = event.position - _lastFocalPoint;
      _lastFocalPoint = event.position;
      final latest = ref.read(canvasProvider);
      if (latest != null) {
        ref.read(canvasProvider.notifier).setPanOffset(latest.panOffset + delta);
        checkPageDrag(latest, canvasSize,
            panOverride: latest.panOffset + delta);
      }
      return;
    }

    final tool = state.currentTool;

    // Shape adjustment mode: drag adjusts the recognized shape
    if (state.isAdjustingRecognized && state.recognizedShape != null) {
      final pagePos = toPageCoords(event.localPosition, state, canvasSize);
      ref.read(canvasProvider.notifier).adjustRecognizedShape(pagePos);
      return;
    }

    if (tool == CanvasTool.pan) {
      if (_reanchorPanAfterPinch(event.position)) return;
      final delta = event.position - _lastFocalPoint;
      _lastFocalPoint = event.position;
      final latest = ref.read(canvasProvider);
      if (latest != null) {
        ref.read(canvasProvider.notifier).setPanOffset(latest.panOffset + delta);
        checkPageDrag(latest, canvasSize,
            panOverride: latest.panOffset + delta);
      }
      return;
    }

    if (_isDraggingSelection) {
      final pagePos = toPageCoords(event.localPosition, state, canvasSize);
      final delta = pagePos - _lastLassoDragPos;
      _lastLassoDragPos = pagePos;
      // Update local notifier (no Riverpod). Painter listens via
      // repaintNotifier so only the canvas layer repaints.
      lassoTransform.translate(delta);
      return;
    }

    final pagePos =
        toPageCoords(_stylusLocalPosition(event), state, canvasSize);
    final normPressure = _normalizedEventPressure(event);
    final pressure = normPressure > 0 ? normPressure : 0.5;
    // Pass raw pressure (incl. 0) to the active-stroke notifier so it can
    // synth pseudo-pressure from velocity for non-pressure devices
    // (mouse/touchpad). Stylus events report > 0 (or are enriched from the
    // Linux native bridge via penPressure) and pass through.
    final rawPressureForPen = penPressure(event);

    if (tool == CanvasTool.lasso) {
      _onLassoPointerMove(pagePos);
      return;
    }

    // Laser: keep appending to the fading trail, never start a real
    // stroke. Bypasses Riverpod entirely; the painter listens on
    // laserStroke via repaintNotifier.
    if (tool == CanvasTool.laser) {
      laserStroke.addPoint(pagePos);
      return;
    }

    // If a selected element exists and no active stroke, don't draw
    // (If a stroke is in progress, the element was deselected in pointerDown;
    //  allow moves through until the state rebuilds.)
    if (state.selectedElementId != null && !activeStroke.isActive) return;

    // Fast path: during pen/brush drawing, only update the notifier (no Riverpod rebuild).
    // Riverpod is only updated for eraser/lasso/shape tools that need state tracking.
    if (activeStroke.isActive) {
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
        final notifierPts = activeStroke.points;
        if (notifierPts.isNotEmpty) {
          final last = notifierPts.last;
          final ddx = pagePos.dx - last.x;
          final ddy = pagePos.dy - last.y;
          // 12 page-units ≈ 24 screen-px at default 2× zoom — well above
          // any realistic Apple Pencil sample dropout but short enough to
          // catch unintended re-strokes nearby.
          if (ddx * ddx + ddy * ddy > 12 * 12) {
            final keptPts = activeStroke.snapshotForCommit();
            activeStroke.clear();
            ref.read(canvasProvider.notifier).commitAndEndStroke(keptPts);
            ref.read(canvasProvider.notifier).startStroke(pagePos, pressure);
            activeStroke.start(pagePos, rawPressureForPen,
                pageUnitsPerPx: _pageUnitsPerScreenPx(state, canvasSize),
                integerCoords: _onIntegerPixels(event.position),
        eventTime: kIsWeb ? event.timeStamp : null);
            _lastStrokeActivity = DateTime.now();
            _lastHoldCheckPos = pagePos;
            return;
          }
        }
      }
      if (kIsWeb && !_onIntegerPixels(event.position)) {
        activeStroke.noteFractionalInput();
      }
      activeStroke.addPoint(pagePos, rawPressureForPen,
          eventTime: kIsWeb ? event.timeStamp : null);
      _lastStrokeActivity = DateTime.now();

      // Reset hold-to-recognize timer (GoodNotes-style: recognize when user pauses)
      // Tolerate micro-jitter from stylus: only reset timer if movement > 3px
      final holdDx = pagePos.dx - _lastHoldCheckPos.dx;
      final holdDy = pagePos.dy - _lastHoldCheckPos.dy;
      final holdDistSq = holdDx * holdDx + holdDy * holdDy;
      const holdThresholdSq = 3.0 * 3.0; // 3px tolerance for stylus jitter

      if (holdDistSq > holdThresholdSq) {
        _lastHoldCheckPos = pagePos;
        holdRecognizeTimer?.cancel();
        final currentState = ref.read(canvasProvider);
        if (currentState != null && currentState.toolSettings.shapeRecognition) {
          holdRecognizeTimer = Timer(const Duration(milliseconds: 200), () {
            _tryRecognizeHeldStroke();
          });
        }
      }
      return;
    }
    ref.read(canvasProvider.notifier).continueStroke(pagePos, pressure);
  }

  /// Starts the barrel tool's gesture at the tip's contact point.
  void _beginBarrelGesture(Offset pagePos) {
    final n = ref.read(canvasProvider.notifier);
    final live = ref.read(canvasProvider);
    if (live?.currentTool == CanvasTool.lasso) {
      if (live?.lassoSelection != null) n.clearSelection();
      lassoPath.start(pagePos);
    } else {
      n.startStroke(pagePos, 0.5);
    }
  }

  /// Ends a barrel override: commits the eraser or lasso gesture and gives
  /// back the pre-barrel tool (kept while a lasso selection is up).
  void _finishBarrel(String reason) {
    barrelButtonOverride = false;
    _barrelAwaitingContact = false;
    clearPenHover();
    final notif = ref.read(canvasProvider.notifier);
    final prevTool = barrelButtonPreviousTool;
    final curTool = ref.read(canvasProvider)?.currentTool;
    // Tool-specific cleanup before restoring.
    if (curTool == CanvasTool.eraserStandard ||
        curTool == CanvasTool.eraserStroke) {
      notif.endStroke();
    } else if (curTool == CanvasTool.lasso && lassoPath.isActive) {
      final pts = List<Offset>.from(lassoPath.points);
      lassoPath.clear();
      notif.commitLassoPath(pts);
    }
    _markStrokeEnded(reason);
    // If the lasso caught a selection, STAY in lasso so the marquee is
    // interactive (move / scale / rotate / delete). Restoring the previous
    // tool now would run setTool(prev) → clearLasso → WIPE the just-made
    // selection — the "faccio il cerchio e mollo, non mi prende la selezione,
    // torna con la penna" bug. Keep barrelButtonPreviousTool so
    // _watchForLassoCleared restores it once the user deselects.
    if (ref.read(canvasProvider)?.lassoSelection != null) return;
    barrelButtonPreviousTool = null;
    if (prevTool != null) notif.setTool(prevTool);
  }

  /// The tip lifted with the barrel still held: commit, keep the override.
  void _endBarrelGesture() {
    final n = ref.read(canvasProvider.notifier);
    final tool = ref.read(canvasProvider)?.currentTool;
    if (tool == CanvasTool.eraserStandard || tool == CanvasTool.eraserStroke) {
      n.endStroke();
    } else if (tool == CanvasTool.lasso && lassoPath.isActive) {
      final pts = List<Offset>.from(lassoPath.points);
      lassoPath.clear();
      n.commitLassoPath(pts);
    }
  }

  void _onLassoPointerMove(Offset pagePos) {
    if (!lassoPath.isActive) return;
    lassoPath.addPoint(pagePos);
  }

  /// Try to recognize a shape when user holds still during drawing.
  void _tryRecognizeHeldStroke() {
    if (!activeStroke.isActive) return;
    final points = activeStroke.points;
    if (points.length < 5) return;

    final state = ref.read(canvasProvider);
    if (state == null || !state.toolSettings.shapeRecognition) return;

    // Ask provider to try recognition
    ref.read(canvasProvider.notifier).recognizeHeldStroke(List.of(points));

    // Check if it was recognized
    final newState = ref.read(canvasProvider);
    if (newState?.recognizedShape != null) {
      _strokeDbg('HOLD recognized ${newState!.recognizedShape!.shapeType} '
          'pts=${points.length}');
      _shapeRecognizedDuringHold = true;
      activeStroke.clearPoints(); // Hide stroke, keep active flag
    }
  }

  void onPointerUp(PointerEvent event) {
    if (kIsWeb && isPenEvent(event)) _webPenUpAt = DateTime.now();
    // Matching cleanup for the synth-mouse pointer suppressed in
    // `onPointerDown` — never bumped `_activePointers`, so don't
    // decrement it here either.
    if (_suppressedSynthBarrelPointers.remove(event.pointer)) return;
    // Ignored palm pointer lifting: never counted, so don't decrement.
    if (ignoredPalmPointers.remove(event.pointer)) return;
    _webTouchPointers.remove(event.pointer);
    if (kIsWeb && isPenEvent(event)) _lastStylusAt = DateTime.now();
    final wasMultiTouch = _activePointers >= 2;
    _activePointers = max(0, _activePointers - 1);

    // ── PDF text selection: finish the gesture (tap promotes to whole line) ──
    if (_pdfTextDragActive) {
      _pdfTextDragActive = false;
      final liveUp = ref.read(canvasProvider);
      if (liveUp != null) ensurePdfTextSel(liveUp)?.end();
      // If the barrel was released mid-drag, restore the pre-barrel tool now
      // that the selection has committed (the highlighted text stays).
      _resolveBarrelRevert();
      return;
    }
    // ── Mouse marquee: commit the polygon (a click with no drag = deselect) ──
    if (_mouseSelecting) {
      _mouseSelecting = false;
      if (lassoPath.isActive) {
        final pts = List<Offset>.from(lassoPath.points);
        lassoPath.clear();
        ref.read(canvasProvider.notifier).commitLassoPath(pts);
        maybeHintMouseDraw(pts);
      }
      return;
    }

    // Clear stylus tracking when stylus lifts
    if (event.kind == PointerDeviceKind.stylus || event.kind == PointerDeviceKind.invertedStylus) {
      _strokeDbg(
        'UP stylus p=${event.pointer} t=${event.timeStamp.inMilliseconds}ms '
        'active=${activeStroke.isActive} '
        'pts=${activeStroke.points.length} '
        'multiTouch=$wasMultiTouch '
        'activePointers=$_activePointers'
        '${kIsWeb ? ' intPx=${_onIntegerPixels(event.position)}' : ''}',
      );
      stylusDown = false;
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
    if (barrelButtonOverride) {
      _finishBarrel('pointerUp.barrelEnd');
      return;
    }

    if (_isTouchPanning) {
      _isTouchPanning = false;
      cancelLongPressTimer();
      _longPressFired = false;
      final latest = ref.read(canvasProvider);
      if (latest != null) {
        commitOrCancelPageDrag(latest, lastCanvasSize);
      } else {
        clearPageHints();
      }
      return;
    }

    holdRecognizeTimer?.cancel();

    if (_isDraggingSelection) {
      _isDraggingSelection = false;
      // Commit the locally-tracked drag offset back to Riverpod in one
      // shot. During the drag lassoTransform received every
      // delta; now Riverpod catches up exactly once per gesture.
      commitLassoTransform();
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
      activeStroke.clear();
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
      commitOrCancelPageDrag(state, lastCanvasSize);
      return;
    }
    if (state.currentTool == CanvasTool.image) return;

    // Lasso: commit the locally-tracked path to Riverpod and trigger selection
    if (state.currentTool == CanvasTool.lasso) {
      if (lassoPath.isActive) {
        final pts = List<Offset>.from(lassoPath.points); // copy before clear
        lassoPath.clear();
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
    if (activeStroke.isActive && activeStroke.points.isNotEmpty) {
      // ── Stroke break defense ──
      //
      // For stylus (Apple Pencil on iPad), defer the commit by
      // _deferStylusMs. iPad/Apple Pencil occasionally emits a spurious
      // PointerUp followed by a PointerDown while the user has not
      // actually lifted the pen. Without defer, each segment would be
      // committed as a separate stroke and the user sees a mid-letter
      // break. If a fresh stylus DOWN arrives in the defer window close
      // to this end position, onPointerDown resumes the same stroke
      // (notifier is kept active during defer; continuation just cancels
      // the timer). Otherwise the timer fires and commits normally
      // (notifier is cleared inside flushDeferredCommit, in the same
      // frame as the commit so the rendered stroke does not blink).
      //
      // For non-stylus (mouse/touchpad/touch) commit immediately as
      // before — the bug is iPad-specific and adding latency on PC
      // would be a regression.
      final isPen = event.kind == PointerDeviceKind.stylus ||
          event.kind == PointerDeviceKind.invertedStylus;
      // Web: the browser samples the pen far more sparsely than iPadOS
      // does natively (Safari: one move per frame at best), and the lift
      // position is never fed in as a point. On a fast stroke that drops
      // its whole last segment, so a quick "I" shrinks to a stub or a
      // dot. End the stroke where the pen actually left the glass. (UP
      // carries no pressure in the browser — reuse the last sample's.)
      if (isPen && kIsWeb) {
        final live = ref.read(canvasProvider);
        if (live != null) {
          activeStroke.addPoint(
              toPageCoords(event.localPosition, live, lastCanvasSize),
              activeStroke.points.last.pressure,
              eventTime: event.timeStamp);
        }
      }
      if (isPen && ref.read(appSettingsProvider).strokeContinuation) {
        // Snapshot points (notifier stays active so the rendered live
        // stroke remains on screen during the defer window). The
        // snapshot is the dequantized commit copy — the pen fallback
        // path benefits from the same refit as the mouse (no-op when
        // sub-pixel data was in use).
        deferredCommitPoints = activeStroke.snapshotForCommit();
        deferredCommitAt = DateTime.now();
        deferredCommitLastScreenPos = event.position;
        deferredCommitTimer?.cancel();
        deferredCommitTimer = Timer(
          const Duration(milliseconds: _deferStylusMs),
          flushDeferredCommit,
        );
      } else {
        final points = activeStroke.snapshotForCommit();
        // Plain-mouse "dot" suppression: a click that doesn't move (the
        // first half of a double-click-to-select, a click-to-deselect, or a
        // stray click) used to commit a tiny 1-point stroke — a black dot
        // the user never intended. Pen/touch dots (dotting an 'i') are kept;
        // only zero-movement MOUSE clicks are discarded.
        if (event.kind == PointerDeviceKind.mouse && _isDotStroke(points)) {
          activeStroke.clear();
          ref.read(canvasProvider.notifier).cancelStroke();
          _markStrokeEnded('pointerUp.mouseDotDropped');
        } else {
          activeStroke.clear();
          ref.read(canvasProvider.notifier).commitAndEndStroke(points);
          _markStrokeEnded('pointerUp.commit');
        }
      }
    } else {
      activeStroke.clear();
      ref.read(canvasProvider.notifier).endStroke();
      _markStrokeEnded('pointerUp.endEmpty');
    }
    // Catch-all for a barrel released mid-gesture that didn't go through the
    // lasso-commit return above (e.g. a barrel tap with no circle drawn).
    _resolveBarrelRevert();
  }

  void onPointerCancel(PointerCancelEvent event) {
    if (_suppressedSynthBarrelPointers.remove(event.pointer)) return;
    // Ignored palm pointer cancelled: never counted, so don't decrement —
    // and don't touch the active stylus stroke either.
    if (ignoredPalmPointers.remove(event.pointer)) return;
    _webTouchPointers.remove(event.pointer);
    _activePointers = max(0, _activePointers - 1);
    // A pen stroke lifted but held back for a continuation is finished: commit
    // it now instead of clearing the live stroke under it.
    flushDeferredCommit();
    cancelLongPressTimer();
    // End any in-progress PDF text drag / mouse marquee and resolve a deferred
    // barrel revert so a cancelled gesture doesn't leave the flags stuck.
    _pdfTextDragActive = false;
    if (_mouseSelecting) {
      _mouseSelecting = false;
      lassoPath.clear();
    }
    _resolveBarrelRevert();
    _strokeDbg(
      'CANCEL kind=${event.kind.name} p=${event.pointer} '
      't=${event.timeStamp.inMilliseconds}ms '
      'stylusDown=$stylusDown active=${activeStroke.isActive} '
      'pts=${activeStroke.points.length} '
      'activePointers=$_activePointers',
    );
    // If iOS palm-rejection cancels a touch pointer while the stylus is
    // actively drawing, DO NOT tear down the stylus stroke — the pen is
    // still making a valid mark. Only reset touch-specific gesture state
    // and return. Previously this path undid the user's first stroke
    // whenever their palm brushed the screen mid-draw on iPad.
    // The pen's hold-to-recognize state is the pen's, so it stays too.
    if (event.kind == PointerDeviceKind.touch && stylusDown) {
      _isTouchPanning = false;
      return;
    }
    _isTouchPanning = false;
    if (_isDraggingSelection) {
      _isDraggingSelection = false;
      // Close the local transform notifier too: leaving it active applies
      // the stale drag offset/rotation to the NEXT lasso selection and
      // bypasses the picture cache on every frame.
      commitLassoTransform();
    }
    holdRecognizeTimer?.cancel();
    final heldShape = _shapeRecognizedDuringHold &&
        ref.read(canvasProvider)?.recognizedShape != null;
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
    if (isStylusCancel) stylusDown = false;
    // A shape the pen held still for is already shown as recognised (its
    // stroke points are gone): keep it, as lifting the pen would. Safari can
    // cancel a pen that rests in place.
    if (isStylusCancel && heldShape) {
      activeStroke.clear();
      ref.read(canvasProvider.notifier).commitRecognizedShape();
      _markStrokeEnded('pointerCancel.shapeCommit');
      _strokeDbg('CANCEL_RESCUED shape kind=${event.kind.name}');
      return;
    }
    if (isStylusCancel &&
        activeStroke.isActive &&
        activeStroke.points.length >= 2) {
      final points = activeStroke.snapshotForCommit();
      activeStroke.clear();
      ref.read(canvasProvider.notifier).commitAndEndStroke(points);
      _markStrokeEnded('pointerCancel.committedStylus');
      _strokeDbg('CANCEL_RESCUED kind=${event.kind.name} pts=${points.length}');
      // Restore barrel button state if needed before returning
      if (barrelButtonOverride) {
        barrelButtonOverride = false;
        _barrelAwaitingContact = false;
        clearPenHover();
        if (barrelButtonPreviousTool != null) {
          ref.read(canvasProvider.notifier).setTool(barrelButtonPreviousTool!);
          barrelButtonPreviousTool = null;
        }
      }
      return;
    }
    // Cancel any in-progress stroke or lasso
    if (activeStroke.isActive) {
      activeStroke.clear();
      ref.read(canvasProvider.notifier).cancelStroke();
      _markStrokeEnded('pointerCancel.stroke');
    }
    if (lassoPath.isActive) {
      lassoPath.clear();
    }
    // Restore barrel button state
    if (barrelButtonOverride) {
      final live = ref.read(canvasProvider);
      if (live != null && isEraserTool(live.currentTool)) {
        ref.read(canvasProvider.notifier).endStroke();
      }
      barrelButtonOverride = false;
      _barrelAwaitingContact = false;
      clearPenHover();
      if (barrelButtonPreviousTool != null) {
        ref.read(canvasProvider.notifier).setTool(barrelButtonPreviousTool!);
        barrelButtonPreviousTool = null;
      }
    }
  }

  void onScaleStart(ScaleStartDetails details) {
    // Palm rejection: if the stylus is currently drawing, the scale gesture
    // was triggered by the user's wrist landing on the screen — ignore it
    // so the canvas doesn't zoom mid-stroke. On the web the same goes for
    // a hand that lands right after the pen lifted (see _webPalmWindow).
    if (stylusDown || webPenRecentlyActive) return;
    final state = ref.read(canvasProvider);
    if (state == null) return;
    _baseZoom = state.zoom;
    _lastFocalPoint = details.focalPoint;
    _panAnchorFromPinch = true;
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    // Same palm guard as onScaleStart. Even if onScaleStart was already
    // rejected, Flutter still calls onScaleUpdate during the gesture — we
    // must gate it too, otherwise a palm landing mid-stroke can still move
    // the zoom level via the accumulated scale delta.
    if (stylusDown || webPenRecentlyActive) return;
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
    _panAnchorFromPinch = true;
  }

  static bool isEraserTool(CanvasTool tool) =>
      tool == CanvasTool.eraserStandard || tool == CanvasTool.eraserStroke;
}
