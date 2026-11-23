import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:uuid/uuid.dart';

import 'package:abelnotes/core/providers/canvas/asset_cache.dart';
import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/core/providers/cross_notebook_clipboard_provider.dart';
import 'package:abelnotes/features/canvas/data/element_geometry.dart';
import 'package:abelnotes/features/canvas/data/text_measure.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/shared/utils/rich_paste.dart';

/// Copy, paste and duplicate of elements, in-app and across notebooks.
class ClipboardActions {
  ClipboardActions(this._core, this._assets, this._applySelectionTransform);

  final CanvasCore _core;
  final AssetCache _assets;

  /// Bakes a pending lasso move/resize into the page.
  final void Function() _applySelectionTransform;

  /// Collect the asset bytes referenced by [elements] from the CURRENT
  /// notebook's asset store, so the clipboard stays pasteable across
  /// notebooks (see [CanvasClipboard.assets]). Best-effort: assets whose
  /// bytes aren't resident in memory are skipped.
  Map<String, Uint8List> _collectClipboardAssets(
      List<ContentElement> elements) {
    final s = _core.state;
    if (s == null) return const {};
    final out = <String, Uint8List>{};
    for (final el in elements) {
      if (el is ImageElement) {
        final p = el.data.assetPath;
        final bytes = s.assetBytes[p];
        if (p.isNotEmpty && bytes != null) out[p] = bytes;
      }
    }
    return out;
  }

  void copySelection() {
    if (_core.state == null || _core.state!.lassoSelection == null) return;
    _applySelectionTransform();
    final sel = _core.state!.lassoSelection!;
    final page = _core.state!.currentPage;
    if (page == null) return;

    final copied = page.layers.content.where((element) {
      final id = element.id;
      return sel.selectedIds.contains(id);
    }).toList();

    if (copied.isEmpty) return;
    final clip = CanvasClipboard(
      elements: copied,
      bounds: sel.bounds,
      assets: _collectClipboardAssets(copied),
    );
    _core.state = _core.state!.copyWith(clipboard: clip);
    _core.ref.read(crossNotebookClipboardProvider.notifier).state = clip;
  }

  /// Copy a single element (e.g. an image / PDF preview) to the clipboard.
  void copyElement(String elementId) {
    if (_core.state == null) return;
    final page = _core.state!.currentPage;
    if (page == null) return;
    final element = page.layers.content.where((e) {
      final id = e.id;
      return id == elementId;
    }).firstOrNull;
    if (element == null) return;
    final bounds = getElementBounds(element);
    if (bounds == null) return;
    final clip = CanvasClipboard(
      elements: [element],
      bounds: bounds,
      assets: _collectClipboardAssets([element]),
    );
    _core.state = _core.state!.copyWith(clipboard: clip);
    _core.ref.read(crossNotebookClipboardProvider.notifier).state = clip;
  }

  void paste({Offset? at}) {
    if (_core.state == null || _core.state!.clipboard == null) return;
    final s = _core.state!;
    final clip = s.clipboard!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    // Offset paste position slightly from original
    final pasteOffset = at != null
        ? Offset(at.dx - clip.bounds.center.dx, at.dy - clip.bounds.center.dy)
        : const Offset(20, 20);

    final baseZ = _core.nextZIndex(page);
    final newElements = <ContentElement>[];
    final newIds = <String>[];
    for (int idx = 0; idx < clip.elements.length; idx++) {
      final element = clip.elements[idx];
      final newId = const Uuid().v4();
      newIds.add(newId);
      final translated = translateElement(element, pasteOffset);
      final z = baseZ + idx;
      newElements.add(translated.map(unknown: (u) => u.copyWith(id: newId, zIndex: z),
        stroke: (e) => ContentElement.stroke(id: newId, zIndex: z, data: e.data),
        text: (e) => ContentElement.text(id: newId, zIndex: z, data: e.data),
        image: (e) => ContentElement.image(id: newId, zIndex: z, data: e.data),
        shape: (e) => ContentElement.shape(id: newId, zIndex: z, data: e.data),
        math: (e) => ContentElement.math(id: newId, zIndex: z, data: e.data),
      ));
    }

    // Materialize assets this notebook doesn't have (cross-notebook paste:
    // the clipboard carries the source notebook's bytes) and register the
    // pasted elements' asset ids on the destination page so orphan-asset
    // pruning never mistakes them for garbage.
    final newAssetBytes = Map<String, Uint8List>.from(s.assetBytes);
    final newRefs = <String>[];
    var assetsChanged = false;
    for (final element in clip.elements) {
      if (element is! ImageElement) continue;
      final p = element.data.assetPath;
      if (p.isEmpty) continue;
      if (!page.assetReferences.contains(p) && !newRefs.contains(p)) {
        newRefs.add(p);
      }
      if (!newAssetBytes.containsKey(p)) {
        final carried = clip.assets[p];
        if (carried != null) {
          newAssetBytes[p] = carried;
          (_core.assetsByLength[carried.length] ??= []).add(p);
          _core.markAssetDirty(p);
          _assets.decodeAndCache(p, carried);
          assetsChanged = true;
        }
      }
    }

    final updatedPage = _core.pageWithContent(page, [...page.layers.content, ...newElements], assetReferences: [...page.assetReferences, ...newRefs]);

    // The cross-notebook clipboard is a one-shot "carry to the next
    // notebook" intent: once the user has pasted ANYWHERE it is consumed.
    // Leaving it set made openNotebook re-arm the "Tocca per posizionare"
    // banner on every subsequent notebook open, even after the paste.
    if (_core.ref.read(crossNotebookClipboardProvider) != null) {
      _core.ref.read(crossNotebookClipboardProvider.notifier).state = null;
    }

    // Keep the pasted elements SELECTED (same as duplicateSelection): the
    // paste often lands on top of existing content, and re-selecting it by
    // hand to move it away is fiddly. Switching to lasso makes the handles
    // immediately usable.
    _core.commitPageEdit(s, fileName, updatedPage,
        undoOf: page,
        alsoState: (n) => n.copyWith(
              assetBytes: assetsChanged ? newAssetBytes : s.assetBytes,
              lassoPath: [],
              lassoSelection: LassoSelection(
                selectedIds: newIds,
                bounds: clip.bounds.shift(pasteOffset),
              ),
              currentTool: CanvasTool.lasso,
              pendingPaste: false,
            ));
  }

  /// Duplicate the current lasso selection in place, then keep the
  /// new copies selected so the user can drag/scale/rotate them via
  /// the existing lasso handles. Pasting in select mode replaces the
  /// previous "tap somewhere to drop" flow which was disorienting for
  /// large selections (the user couldn't tell where the duplicate
  /// would land before committing).
  void duplicateSelection() {
    if (_core.state == null || _core.state!.lassoSelection == null) return;
    // A pending move/resize is part of what the user sees: bake it first.
    _applySelectionTransform();
    final s = _core.state!;
    final sel = s.lassoSelection!;
    final page = s.currentPage;
    if (page == null) return;

    final fileName = s.currentPageFileName;
    final originals = page.layers.content.where((element) {
      final id = element.id;
      return sel.selectedIds.contains(id);
    }).toList();
    if (originals.isEmpty) return;

    // Update clipboard so a follow-up Ctrl+V works as expected. NOTE: only
    // the in-app clipboard — duplicate places its copy immediately, so
    // arming the cross-notebook clipboard here would re-trigger the
    // "Tocca per posizionare" banner at the next notebook open.
    final clip = CanvasClipboard(
      elements: originals,
      bounds: sel.bounds,
      assets: _collectClipboardAssets(originals),
    );

    // Offset the copy by a small constant so it's visible next to the
    // original instead of overlapping it pixel-perfect.
    const offset = Offset(20, 20);

    final baseZ = _core.nextZIndex(page);
    final newElements = <ContentElement>[];
    final newIds = <String>[];
    for (int idx = 0; idx < originals.length; idx++) {
      final translated = translateElement(originals[idx], offset);
      final newId = const Uuid().v4();
      newIds.add(newId);
      final z = baseZ + idx;
      newElements.add(translated.map(unknown: (u) => u.copyWith(id: newId, zIndex: z),
        stroke: (e) => ContentElement.stroke(id: newId, zIndex: z, data: e.data),
        text: (e) => ContentElement.text(id: newId, zIndex: z, data: e.data),
        image: (e) => ContentElement.image(id: newId, zIndex: z, data: e.data),
        shape: (e) => ContentElement.shape(id: newId, zIndex: z, data: e.data),
        math: (e) => ContentElement.math(id: newId, zIndex: z, data: e.data),
      ));
    }

    final updatedPage = _core.pageWithContent(page, [...page.layers.content, ...newElements]);
    final newBounds = sel.bounds.shift(offset);

    _core.commitPageEdit(s, fileName, updatedPage,
        undoOf: page,
        alsoState: (n) => n.copyWith(
              clipboard: clip,
              lassoPath: [],
              lassoSelection:
                  LassoSelection(selectedIds: newIds, bounds: newBounds),
            ));
  }

  void duplicateElement(String elementId) {
    if (_core.state == null) return;
    final s = _core.state!;
    final page = s.currentPage;
    if (page == null) return;

    final original = page.layers.content.where((e) {
      final id = e.id;
      return id == elementId;
    }).firstOrNull;
    if (original == null) return;

    // Copy the element to clipboard and enter placement mode. In-app
    // clipboard only (see duplicateSelection): duplicating is a local
    // action, arming the cross-notebook clipboard re-triggered the
    // placement banner at the next notebook open.
    final bounds = elementBounds(original);
    final clip = CanvasClipboard(
      elements: [original],
      bounds: bounds,
      assets: _collectClipboardAssets([original]),
    );
    _core.state = s.copyWith(
      clipboard: clip,
      pendingPaste: true,
      clearSelectedElement: true,
    );
  }

  void cancelPendingPaste() {
    if (_core.state == null) return;
    // Dismissing the banner is a "no thanks" for the carried clipboard too:
    // without this, the cross-notebook clipboard re-armed the banner at the
    // next notebook open even though the user explicitly closed it.
    if (_core.ref.read(crossNotebookClipboardProvider) != null) {
      _core.ref.read(crossNotebookClipboardProvider.notifier).state = null;
    }
    _core.state = _core.state!.copyWith(pendingPaste: false);
  }

  /// Paste a parsed Markdown/LaTeX document ([parsePastedRich] output) as a
  /// vertical stack of elements — styled text runs + typeset-math blocks —
  /// in a SINGLE undo step, anchored at [anchor] (viewport centre) and
  /// clamped within the page. Math blocks are pre-rasterized (async) to get
  /// their intrinsic typeset size. The inserted element(s) are selected so
  /// the user can immediately move them.
  Future<void> pasteRichBlocks(
    List<PastedBlock> blocks,
    Offset anchor, {
    int? color,
    double maxWidth = 360,
    double pixelRatio = 3.0,
  }) async {
    if (_core.state == null || blocks.isEmpty) return;
    var s = _core.state!;
    var page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final baseColor = color ?? 0xFF000000;
    final colWidth = maxWidth.clamp(40.0, max(40.0, page.width - 24)).toDouble();
    const gap = 10.0;

    // Pre-measure (math raster is async) so the y-cursor is exact.
    final built = <ContentElement>[];
    final x = anchor.dx;
    var y = anchor.dy;
    var z = _core.nextZIndex(page);
    for (final b in blocks) {
      if (b is PastedTextBlock) {
        if (b.content.trim().isEmpty) continue;
        final h = measureTextHeight(b.content, b.spans, b.fontSize, colWidth);
        built.add(ContentElement.text(
          id: const Uuid().v4(),
          zIndex: z++,
          data: TextData(
            x: x, y: y, width: colWidth, height: h,
            content: b.content, spans: b.spans,
            fontSize: b.fontSize, color: baseColor, alignment: b.alignment,
          ),
        ));
        y += h + gap;
      } else if (b is PastedMathBlock) {
        if (b.latex.trim().isEmpty) continue;
        final fontSize = b.display ? 26.0 : 20.0;
        final size = await _assets.measureMath(b.latex,
            colorArgb: baseColor, fontSize: fontSize, displayMode: b.display,
            pixelRatio: pixelRatio);
        final w = (size?.width ??
                (b.latex.length * fontSize * 0.5).clamp(20.0, colWidth))
            .toDouble();
        final h = (size?.height ?? fontSize * 1.6).toDouble();
        built.add(ContentElement.math(
          id: const Uuid().v4(),
          zIndex: z++,
          data: MathData(
            x: x, y: y, width: w, height: h, latex: b.latex,
            displayMode: b.display, color: baseColor, fontSize: fontSize,
          ),
        ));
        y += h + gap;
      }
    }
    if (built.isEmpty) return;

    // measureMath awaited — re-read state and bail if it changed underfoot.
    if (_core.isDisposed) return;
    s = _core.state!;
    // Re-read the ORIGINAL page by its fileName, not currentPage: if the
    // user switched page during the (slow) math rasterization, committing
    // currentPage's data under the old key would clobber the old page.
    page = s.pages[fileName];
    if (page == null) return;

    // If the column overflows the page bottom, shift the whole stack up to
    // fit (best-effort; very tall stacks just start near the top margin).
    final totalH = y - anchor.dy;
    var dy = 0.0;
    if (anchor.dy + totalH > page.height - 12) {
      dy = page.height - 12 - totalH - anchor.dy;
      if (anchor.dy + dy < 12) dy = 12 - anchor.dy;
    }
    final placed = dy == 0
        ? built
        : built.map((e) => translateElement(e, Offset(0, dy))).toList();

    final updatedPage = _core.pageWithContent(page, [...page.layers.content, ...placed]);

    final ids = placed
        .map((e) => e.id)
        .toList();

    if (ids.length == 1) {
      _core.commitPageEdit(s, fileName, updatedPage,
          undoOf: page,
          alsoState: (n) => n.copyWith(
              selectedElementId: ids.first, clearLasso: true, lassoPath: []));
    } else {
      var bounds = elementBounds(placed.first);
      for (final e in placed.skip(1)) {
        bounds = bounds.expandToInclude(elementBounds(e));
      }
      _core.commitPageEdit(s, fileName, updatedPage,
          undoOf: page,
          alsoState: (n) => n.copyWith(
              lassoSelection: LassoSelection(selectedIds: ids, bounds: bounds),
              clearSelectedElement: true,
              lassoPath: []));
    }
  }
}
