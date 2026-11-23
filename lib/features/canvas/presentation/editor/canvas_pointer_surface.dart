// Pointer input of the page: raw pointer events to the pipeline, wheel and
// trackpad zoom, the touch scale gesture, and the double tap.

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/platform/device_class.dart';
import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/editor/editor_pointer_controller.dart';
import 'package:abelnotes/features/canvas/presentation/multi_finger_tap.dart';
import 'package:abelnotes/features/canvas/presentation/pdf_text_selection.dart';

/// Wraps the page in the listeners that feed [ptr]. Reads the live state on
/// every event: pan and zoom change at pointer rate and never rebuild this.
class CanvasPointerSurface extends ConsumerWidget {
  const CanvasPointerSurface({
    super.key,
    required this.ptr,
    required this.fingerTaps,
    required this.showContextMenu,
    required this.ensurePdfTextSel,
    required this.canvasSize,
    required this.fallback,
    required this.child,
  });

  final EditorPointerController ptr;
  final MultiFingerTapDetector fingerTaps;
  final void Function(
          Offset global, Offset local, CanvasState state, Size canvasSize)
      showContextMenu;
  final PdfTextSelectionController? Function(CanvasState state)
      ensurePdfTextSel;
  final Size canvasSize;

  /// State to use only if the provider has none.
  final CanvasState fallback;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doubleTapZoom = ref.watch(canvasProvider.select((s) {
      final tool = (s ?? fallback).currentTool;
      return tool == CanvasTool.pan || tool == CanvasTool.image;
    }));

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        // ── Live-state read (was the phantom-line bug) ──
        // the build-time `fallback` is intentionally
        // STALE on pan/zoom/pages — the chrome's select excludes
        // those fields. ptr.toPageCoords reads state.panOffset and
        // state.zoom, so feeding it the stale state turned the
        // very first point of a new stroke into the wrong page
        // coordinate (it lived in the OLD pan/zoom frame). The
        // next pointer-move could land in the right frame and
        // the user saw the new stroke "stretch" from a phantom
        // start to the real one. Same fix as onPointerSignal
        // below — always pull live state.
        final live = ref.read(canvasProvider) ?? fallback;
        if (e.kind == PointerDeviceKind.mouse &&
            e.buttons == kSecondaryMouseButton) {
          if (live.pendingSymbol != null) {
            ref.read(canvasProvider.notifier).clearPendingSymbol();
            return;
          }
          showContextMenu(e.position, e.localPosition, live, canvasSize);
          return;
        }
        if (kIsWeb &&
            e.kind != PointerDeviceKind.mouse &&
            e.kind != PointerDeviceKind.trackpad) {
          noteWebTouchInput();
        }
        ptr.mouseDoubleClickZoom(e, live);
        // Fingers landing while the pen writes (or just wrote)
        // are a palm, not a tap.
        fingerTaps.down(e);
        if (ptr.stylusDown || ptr.webPenRecentlyActive) {
          fingerTaps.spoil();
        }
        ptr.onPointerDown(e, live, canvasSize);
        // A touch the canvas just dropped as a palm.
        if (ptr.ignoredPalmPointers.contains(e.pointer)) {
          fingerTaps.spoil();
        }
      },
      onPointerMove: (e) {
        fingerTaps.move(e);
        final live = ref.read(canvasProvider) ?? fallback;
        ptr.updatePenHover(e, live);
        ptr.onPointerMove(e, live, canvasSize);
      },
      onPointerHover: (e) {
        fingerTaps.hover(e);
        if (!EditorPointerController.hoverKindUnreliable) {
          ptr.lastPointerWasMouse = e.kind == PointerDeviceKind.mouse;
        }
        final live = ref.read(canvasProvider);
        ptr.updatePenHover(e, live);
        // Pen/stylus (or no state) → tool default cursor (crosshair).
        if (e.kind != PointerDeviceKind.mouse || live == null) {
          if (ptr.mouseHoverCursor.value != null) {
            ptr.mouseHoverCursor.value = null;
          }
          return;
        }
        // Mouse over an ink tool = selection device: arrow normally,
        // I-beam over selectable PDF text. Other tools keep their
        // default cursor (override = null). When the user opted the
        // mouse into drawing, keep the drawing crosshair.
        MouseCursor? c;
        if (!ref.read(appSettingsProvider).mouseDraws &&
            EditorPointerController.mouseSelectTools
                .contains(live.currentTool)) {
          final sel = ensurePdfTextSel(live);
          final overText = sel != null &&
              !sel.isEmpty &&
              sel.isOverText(
                  ptr.toPageCoords(e.localPosition, live, canvasSize));
          c = overText ? SystemMouseCursors.text : SystemMouseCursors.basic;
        }
        if (ptr.mouseHoverCursor.value != c) ptr.mouseHoverCursor.value = c;
      },
      onPointerUp: (e) {
        ptr.onPointerUp(e);
        // After the canvas: an undo lands once the second
        // finger's lift has finished its own bookkeeping.
        fingerTaps.up(e);
      },
      onPointerCancel: (e) {
        fingerTaps.cancel(e);
        ptr.onPointerCancel(e);
      },
      onPointerSignal: (event) {
        // Read live state — the build-time `fallback`
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
          // (handled in ptr.onScaleUpdate), but when the engine
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
          ref.read(canvasProvider.notifier).setZoomAndPan(newZoom, newPan);
        } else if (event is PointerScaleEvent) {
          // Trackpad pinch-to-zoom (may not fire on all platforms)
          final oldZoom = live.zoom;
          final newZoom = (oldZoom * event.scale).clamp(0.3, 5.0);
          final cursorPos = event.localPosition;
          final newPan = live.panOffset +
              (cursorPos - live.panOffset) * (1 - (newZoom / oldZoom));
          ref.read(canvasProvider.notifier).setZoomAndPan(newZoom, newPan);
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
        // Listener. ptr.onPointerCancel then tears down the active
        // stroke mid-letter — the user perceives this as the pen
        // suddenly "lifting" and a new stroke starting at the
        // same place ("stroke break mid-pen-down" on iPad).
        //
        // Pinch-to-zoom on iPad still works (touch+touch), and
        // trackpad pinch on desktop still works (trackpad). The
        // _onScale* callbacks already early-return on `ptr.stylusDown`
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
        onScaleStart: ptr.onScaleStart,
        onScaleUpdate: ptr.onScaleUpdate,
        // Double-tap toggles zoom-to-fit <-> default 2.0x zoom.
        // Only fires for non-drawing tools so a user can't
        // accidentally zoom while sketching fast.
        onDoubleTap: doubleTapZoom
            ? () {
                // Toggle: if already near fit-zoom, go back to 2.0
                // default; otherwise fit the full page.
                final notifier = ref.read(canvasProvider.notifier);
                // Zoom changes don't rebuild this screen: read it now.
                final zoom = ref.read(canvasProvider)?.zoom ?? fallback.zoom;
                if (zoom < 1.4) {
                  notifier.resetZoom();
                } else {
                  notifier.zoomToFit();
                }
              }
            : null,
        child: child,
      ),
    );
  }
}

/// The mouse cursor over the page: the tool's default, unless the pointer
/// pipeline set a device-aware override (selection arrow, I-beam over PDF text).
class CanvasCursorRegion extends ConsumerWidget {
  const CanvasCursorRegion({
    super.key,
    required this.hoverCursor,
    required this.onExit,
    required this.child,
  });

  final ValueListenable<MouseCursor?> hoverCursor;
  final VoidCallback onExit;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The pen keeps the drawing crosshair; the mouse overrides it on hover.
    final tool = ref.watch(canvasProvider.select((s) => s?.currentTool));
    final cursor = switch (tool) {
      CanvasTool.pan => SystemMouseCursors.grab,
      CanvasTool.image => SystemMouseCursors.click,
      _ => SystemMouseCursors.precise,
    };
    return ValueListenableBuilder<MouseCursor?>(
      valueListenable: hoverCursor,
      builder: (context, hover, child) => MouseRegion(
        onExit: (_) => onExit(),
        cursor: hover ?? cursor,
        child: child,
      ),
      child: child,
    );
  }
}
