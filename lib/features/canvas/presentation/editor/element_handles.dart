// Handles of a single selected element (image, shape, text, math): move,
// resize, rotate and the action bar, following the live transform of a gesture.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/canvas_painter_notifiers.dart';
import 'package:abelnotes/features/canvas/presentation/editor/page_view_transform.dart';
import 'package:abelnotes/features/canvas/presentation/image_handle_overlay.dart';
import 'package:abelnotes/features/modules/builtin_modules.dart';
import 'package:abelnotes/features/modules/module_registry.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

class ElementHandles extends ConsumerWidget {
  const ElementHandles({
    super.key,
    required this.fallback,
    required this.canvasSize,
    required this.transform,
    required this.onCrop,
    required this.onEditComment,
    required this.onEditMath,
    required this.onTidyCircuit,
    required this.onConvertToInk,
    required this.copyImageToSystemClipboard,
    required this.toast,
  });

  /// State to draw from before the provider has one.
  final CanvasState fallback;
  final Size canvasSize;
  final ElementTransformNotifier transform;
  final void Function(String elementId) onCrop;
  final void Function(String elementId) onEditComment;
  final void Function(MathElement element) onEditMath;
  final void Function(String elementId) onTidyCircuit;
  final void Function(String elementId) onConvertToInk;
  final void Function(String elementId) copyImageToSystemClipboard;
  final void Function(String message) toast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // pages: so a commit refreshes the state the handles anchor to; zoom and
    // pan re-project them.
    ref.watch(canvasProvider.select((s) => (
          zoom: s?.zoom ?? 1.0,
          panOffset: s?.panOffset ?? Offset.zero,
          pages: s?.pages,
          page: s?.currentPageIndex,
          lassoSelection: s?.lassoSelection,
          selectedElementId: s?.selectedElementId,
          hasClipboard: s?.clipboard != null,
        )));
    final live = ref.read(canvasProvider) ?? fallback;
    final circuitsReady = ref.watch(moduleEntriesProvider).any((e) =>
        e.module.manifest.id == kCircuitsModuleId &&
        e.status == ModuleStatus.ready);
    return ListenableBuilder(
      listenable: transform,
      builder: (_, __) => Stack(
          children: _handles(context, ref, live, circuitsReady: circuitsReady)),
    );
  }

  List<Widget> _handles(BuildContext context, WidgetRef ref, CanvasState state,
      {required bool circuitsReady}) {
    final view = PageViewTransform.of(state, canvasSize);
    if (state.selectedElementId == null) return [];
    final page = state.currentPage;
    if (page == null) return [];

    final element = page.layers.content.where((e) {
      final id = e.id;
      return id == state.selectedElementId;
    }).firstOrNull;
    if (element == null) return [];

    Rect? pageBounds;
    double rotation = 0;
    element.map(unknown: (u) => u,
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
    // very element, transform holds the deltas. Apply
    // them so the bounding box and rotation handle stay glued to the
    // moving content instead of snapping at pan-end.
    final liveActive = transform.isActive &&
        transform.elementId == state.selectedElementId;
    if (liveActive) {
      final dx = transform.dragOffset.dx;
      final dy = transform.dragOffset.dy;
      final sw = transform.scaleW;
      final sh = transform.scaleH;
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
      rotation += transform.rotationDelta;
    }

    final screenTL = view.toScreen(pageBounds!.topLeft);
    final screenBR = view.toScreen(pageBounds!.bottomRight);
    final screenRect = Rect.fromPoints(screenTL, screenBR);

    // Determine if the selected element is an image (to show crop button)
    final isImage = element.map(unknown: (_) => false,
      stroke: (_) => false,
      text: (_) => false,
      image: (_) => true,
      shape: (_) => false,
      math: (_) => false,
    );

    final isLocked = element.map(unknown: (_) => false,
      stroke: (_) => false,
      text: (_) => false,
      image: (e) => e.data.locked,
      shape: (_) => false,
      math: (_) => false,
    );

    final hasComment = element.map(unknown: (_) => false,
      stroke: (_) => false,
      text: (_) => false,
      image: (e) => e.data.comment != null && e.data.comment!.isNotEmpty,
      shape: (_) => false,
      math: (_) => false,
    );

    final isFlipped = element.map(unknown: (_) => false,
      stroke: (_) => false,
      text: (_) => false,
      image: (e) => e.data.flipHorizontal,
      shape: (_) => false,
      math: (_) => false,
    );

    // Text boxes resize like GoodNotes/Keynote: corners scale the font,
    // sides change the wrap width, and height auto-fits (so the top/bottom
    // handles are hidden). Images/shapes/math keep free-deform corners.
    final isText = element.map(unknown: (_) => false,
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
        onEditMath: element is MathElement ? () => onEditMath(element) : null,
        onDragStart: () {
          // Push undo once (Riverpod), then switch to the local notifier
          // for the rest of the gesture so per-frame moves don't fire
          // state updates. Pass the ORIGINAL element bounds so onResize
          // can compute true cumulative scale (vs. the live, already-
          // scaled bounds the parent rebuilds with each setScale tick).
          ref.read(canvasProvider.notifier).startDragElement(elementId);
          transform.begin(elementId, origBounds: pageBounds);
        },
        onDragEnd: () => _commit(ref, elementId, state),
        onMove: (delta) {
          final pageDelta = delta / (state.zoom * view.renderScale);
          // Local-only — Riverpod catches up at pan-end via onDragEnd.
          transform.translate(pageDelta);
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
          final orig = transform.origBounds ?? pageBounds!;
          final origScreenTL = view.toScreen(orig.topLeft);
          final origScreenBR = view.toScreen(orig.bottomRight);
          final origScreenRect = Rect.fromPoints(origScreenTL, origScreenBR);
          final sw = (origScreenRect.width <= 0)
              ? 1.0
              : (newBounds.width / origScreenRect.width);
          final sh = (origScreenRect.height <= 0)
              ? 1.0
              : (newBounds.height / origScreenRect.height);
          // Translate the top-left if it moved (e.g. resize from top/left).
          final dx = (newBounds.left - origScreenRect.left) /
              (state.zoom * view.renderScale);
          final dy = (newBounds.top - origScreenRect.top) /
              (state.zoom * view.renderScale);
          transform.setScale(sw, sh);
          transform.translate(
              Offset(dx - transform.dragOffset.dx,
                  dy - transform.dragOffset.dy));
        },
        onRotate: (angle) {
          transform.rotateBy(angle);
        },
        onDelete: () {
          ref.read(canvasProvider.notifier).deleteElement(elementId);
        },
        onDeselect: () {
          ref.read(canvasProvider.notifier).deselectElement();
        },
        onCrop: isImage ? () => onCrop(elementId) : null,
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
          onEditComment(elementId);
        } : null,
        onCopy: isImage ? () {
          ref.read(canvasProvider.notifier).copyElement(elementId);
          // Also push the PNG to the system clipboard so the user can
          // paste it into another app.
          copyImageToSystemClipboard(elementId);
          toast(AppLocalizations.of(context).csImageCopied);
        } : null,
        onCut: isImage ? () {
          ref.read(canvasProvider.notifier).cutElement(elementId);
          toast(AppLocalizations.of(context).csImageCut);
        } : null,
        onFlipHorizontal: isImage ? () {
          ref.read(canvasProvider.notifier).flipImageElement(elementId);
        } : null,
        onTidyCircuit:
            isImage && circuitsReady ? () => onTidyCircuit(elementId) : null,
        onConvertToInk: isImage ? () => onConvertToInk(elementId) : null,
      ),
    ];
  }

  /// Commit the locally-tracked element transform back to Riverpod once,
  /// at the end of a drag/rotate/resize gesture. During the gesture
  /// transform received every delta; here Riverpod
  /// catches up exactly once.
  void _commit(WidgetRef ref, String elementId, CanvasState state) {
    if (!transform.isActive) return;
    final dragOffset = transform.dragOffset;
    final rotationDelta = transform.rotationDelta;
    final sw = transform.scaleW;
    final sh = transform.scaleH;
    transform.end();

    final notifier = ref.read(canvasProvider.notifier);
    // Resize: derive the new page-bounds from the original element
    // bounds + accumulated drag + scale.
    final page = state.currentPage;
    if (page == null) return;
    final element = page.layers.content.where((e) {
      final id = e.id;
      return id == elementId;
    }).firstOrNull;
    if (element == null) return;
    Rect? origBounds;
    element.map(unknown: (u) => u,
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

    final isTextEl = element.map(unknown: (_) => false,
      stroke: (_) => false,
      text: (_) => true,
      image: (_) => false,
      shape: (_) => false,
      math: (_) => false,
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
}
