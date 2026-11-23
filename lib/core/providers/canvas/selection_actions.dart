import 'dart:ui';

import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/features/canvas/data/element_geometry.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart'
    show shapeOutline;
import 'package:abelnotes/features/canvas/data/shape_recognizer.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Lasso and single-element selection: picking, the pending move/rotate/scale
/// and its bake into the page, flip, recolour, re-width and delete.
class SelectionActions {
  SelectionActions(this._core);

  final CanvasCore _core;

  /// One undo entry per selection-width slider drag, not one per tick.
  bool _selectionWidthUndoPushed = false;

  void startLasso(Offset position) {
    if (_core.state!.lassoSelection != null) {
      final sel = _core.state!.lassoSelection!;
      final dragBounds = sel.bounds.translate(sel.dragOffset.dx, sel.dragOffset.dy);
      // Wait, is it clicking inside the lasso to drag?
      if (dragBounds.contains(position)) return;
      applySelectionTransform(); // Bake if clicking outside
      _core.state = _core.state!.copyWith(clearLasso: true, lassoPath: []);
    }
    _core.state = _core.state!.copyWith(lassoPath: [position]);
  }

  void clearLassoPath() {
    if (_core.state == null) return;
    if (_core.state!.lassoSelection != null) applySelectionTransform();
    _core.state = _core.state!.copyWith(clearLasso: true, lassoPath: []);
  }

  /// Accept a locally-collected lasso path (from _LassoPathNotifier in the UI)
  /// and run selection — bypasses per-point Riverpod updates entirely.
  void commitLassoPath(List<Offset> path) {
    if (_core.state == null) return;
    final s = _core.state!;
    if (path.length < 3) {
      _core.state = s.copyWith(lassoPath: [], clearLasso: true);
      return;
    }
    // Reuse _endLasso logic by temporarily setting the path
    _core.state = s.copyWith(lassoPath: path);
    endLasso();
  }

  void continueLasso(Offset position) {
    if (_core.state!.lassoPath.isEmpty) return;
    _core.state = _core.state!.copyWith(lassoPath: [..._core.state!.lassoPath, position]);
  }

  void endLasso() {
    if (_core.state == null) return;
    final s = _core.state!;
    if (s.lassoPath.length < 3) {
      _core.state = s.copyWith(lassoPath: [], clearLasso: true);
      return;
    }

    final page = s.currentPage;
    if (page == null) return;

    // Build the lasso polygon for point-in-polygon testing
    final lassoPolygon = s.lassoPath;

    final selectedIds = <String>[];
    Rect? selectionBounds;

    for (final element in page.layers.content) {
      // Skip PDF images from lasso selection — they are only selectable via double-tap
      final isPdfImage = element.mapOrNull(
        image: (img) => img.data.assetPath.contains('.pdf_p'),
      ) ?? false;
      if (isPdfImage) continue;

      final elementBounds = getElementBounds(element);
      if (elementBounds == null) continue;

      bool isSelected = false;

      // Strokes and shapes are tested against their ACTUAL geometry, not
      // the bounding box: a diagonal line's (or C-shaped stroke's) bbox
      // center/corners are mostly empty space, so the old center+corner
      // heuristic selected elements the lasso was nowhere near.
      if (element is StrokeElement) {
        for (final p in element.data.points) {
          if (pointInPolygon(Offset(p.x, p.y), lassoPolygon)) {
            isSelected = true;
            break;
          }
        }
      } else if (element is ShapeElement) {
        outer:
        for (final edge in shapeToSampledEdges(element.data, 8.0)) {
          for (final p in edge) {
            if (pointInPolygon(Offset(p.x, p.y), lassoPolygon)) {
              isSelected = true;
              break outer;
            }
          }
        }
      } else {
        // Solid rectangular elements (text, image, math): center or any
        // corner inside the lasso counts.
        if (pointInPolygon(elementBounds.center, lassoPolygon)) {
          isSelected = true;
        }
        if (!isSelected) {
          final corners = [elementBounds.topLeft, elementBounds.topRight, elementBounds.bottomLeft, elementBounds.bottomRight];
          for (final corner in corners) {
            if (pointInPolygon(corner, lassoPolygon)) {
              isSelected = true;
              break;
            }
          }
        }
      }

      if (isSelected) {
        final id = element.id;
        selectedIds.add(id);
        selectionBounds = selectionBounds == null
            ? elementBounds
            : selectionBounds.expandToInclude(elementBounds);
      }
    }

    if (selectedIds.isEmpty || selectionBounds == null) {
      _core.state = s.copyWith(lassoPath: [], clearLasso: true);
      return;
    }

    _core.state = s.copyWith(
      lassoPath: [],
      lassoSelection: LassoSelection(selectedIds: selectedIds, bounds: selectionBounds),
    );
  }

  /// Apply the full transform (drag/rotation/scale) atomically. Used by
  /// the UI when committing a locally-tracked LassoTransformNotifier on
  /// pointer-up, so Riverpod fires a single state update per gesture
  /// instead of one per pointer-move.
  void commitSelectionTransform({
    required Offset dragOffset,
    required double rotation,
    required double scale,
  }) {
    if (_core.state == null || _core.state!.lassoSelection == null) return;
    // No-op tap on the bounds: avoid the state churn (a fresh
    // LassoSelection + CanvasState allocation that would tickle every
    // chrome consumer for nothing).
    if (dragOffset == Offset.zero && rotation == 0.0 && scale == 1.0) {
      return;
    }
    _core.state = _core.state!.copyWith(
      lassoSelection: _core.state!.lassoSelection!.copyWith(
        dragOffset: dragOffset,
        rotation: rotation,
        scale: scale,
      ),
    );
  }

  void applySelectionTransform() {
    if (_core.state == null || _core.state!.lassoSelection == null) return;
    final s = _core.state!;
    final sel = s.lassoSelection!;
    if (sel.rotation == 0.0 && sel.dragOffset == Offset.zero && sel.scale == 1.0) return;

    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;
    final center = sel.bounds.center;

    final updatedContent = page.layers.content.map((element) {
      final id = element.id;
      if (!sel.selectedIds.contains(id)) return element;
      var updated = element;
      if (sel.scale != 1.0) {
        updated = scaleElement(updated, center, sel.scale);
      }
      if (sel.rotation != 0.0) {
        updated = rotateElementAroundCenter(updated, center, sel.rotation);
      }
      if (sel.dragOffset != Offset.zero) {
        updated = translateElement(updated, sel.dragOffset);
      }
      return updated;
    }).toList();

    final updatedPage = _core.pageWithContent(page, updatedContent);

    // Recalculate bounds from actual transformed element positions
    Rect? newBounds;
    for (final element in updatedContent) {
      final id = element.id;
      if (!sel.selectedIds.contains(id)) continue;
      final eb = getElementBounds(element);
      if (eb == null) continue;
      newBounds = newBounds == null ? eb : newBounds.expandToInclude(eb);
    }

    _core.commitPageEdit(s, fileName, updatedPage,
        undoOf: page,
        alsoState: (n) => n.copyWith(
              lassoSelection: LassoSelection(
                selectedIds: sel.selectedIds,
                bounds: newBounds ??
                    sel.bounds.translate(sel.dragOffset.dx, sel.dragOffset.dy),
              ),
            ));
  }

  /// Mirrors the selection around its horizontal ([horizontal]) or vertical center axis.
  void flipSelection({required bool horizontal}) {
    if (_core.state == null || _core.state!.lassoSelection == null) return;
    final s = _core.state!;
    final sel = s.lassoSelection!;
    final page = s.currentPage;
    if (page == null || sel.selectedIds.isEmpty) return;
    final fileName = s.currentPageFileName;
    final undoStack = _core.pushUndo(s, fileName, page);

    // Bake any pending translate/scale/rotate first so the flip axis is the
    // *visual* center the user sees, not the original bounds center.
    if (sel.rotation != 0.0 || sel.dragOffset != Offset.zero || sel.scale != 1.0) {
      applySelectionTransform();
    }
    final postState = _core.state!;
    final postSel = postState.lassoSelection!;
    final postPage = postState.currentPage!;
    final center = postSel.bounds.center;

    double reflectX(double x) => horizontal ? 2 * center.dx - x : x;
    double reflectY(double y) => horizontal ? y : 2 * center.dy - y;

    final updatedContent = postPage.layers.content.map((element) {
      final id = element.id;
      if (!postSel.selectedIds.contains(id)) return element;
      return element.map(unknown: (u) => u,
        stroke: (e) => ContentElement.stroke(
          id: e.id, zIndex: e.zIndex,
          data: StrokeData(
            points: e.data.points
                .map((p) => StrokePoint(
                      x: reflectX(p.x),
                      y: reflectY(p.y),
                      pressure: p.pressure,
                      tilt: p.tilt,
                      timestamp: p.timestamp,
                    ))
                .toList(),
            toolType: e.data.toolType, color: e.data.color,
            baseWidth: e.data.baseWidth, isHighlighter: e.data.isHighlighter,
            opacity: e.data.opacity, timestamp: e.data.timestamp,
          ),
        ),
        text: (e) => ContentElement.text(
          id: e.id, zIndex: e.zIndex,
          // copyWith preserves spans/fontFamily and every other field —
          // mirror only moves the box (reflect top-left by element size).
          data: e.data.copyWith(
            x: horizontal ? 2 * center.dx - e.data.x - e.data.width : e.data.x,
            y: horizontal ? e.data.y : 2 * center.dy - e.data.y - e.data.height,
          ),
        ),
        image: (e) => ContentElement.image(
          id: e.id, zIndex: e.zIndex,
          // copyWith preserves flipHorizontal (and any future field) —
          // a from-scratch ImageData silently dropped it on every mirror.
          data: e.data.copyWith(
            x: horizontal ? 2 * center.dx - e.data.x - e.data.width : e.data.x,
            y: horizontal ? e.data.y : 2 * center.dy - e.data.y - e.data.height,
            // Mirror rotation so the image visually stays aligned.
            rotation: -e.data.rotation,
          ),
        ),
        // copyWith preserves isHighlighter (and any other untouched
        // field) — a from-scratch rebuild silently reset it to opaque.
        shape: (e) => ContentElement.shape(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(
            x1: reflectX(e.data.x1), y1: reflectY(e.data.y1),
            x2: reflectX(e.data.x2), y2: reflectY(e.data.y2),
            rotation: -e.data.rotation,
            vertices: transformVertices(e.data.vertices,
                (p) => Offset(reflectX(p.dx), reflectY(p.dy))),
          ),
        ),
        math: (e) => ContentElement.math(
          id: e.id, zIndex: e.zIndex,
          data: e.data.copyWith(
            x: horizontal ? 2 * center.dx - e.data.x - e.data.width : e.data.x,
            y: horizontal ? e.data.y : 2 * center.dy - e.data.y - e.data.height,
          ),
        ),
      );
    }).toList();

    final updatedPage = _core.pageWithContent(postPage, updatedContent);

    final updatedPages = Map<String, PageData>.from(postState.pages);
    updatedPages[fileName] = updatedPage;

    // Recompute selection bounds from mirrored elements.
    Rect? newBounds;
    for (final element in updatedContent) {
      final id = element.id;
      if (!postSel.selectedIds.contains(id)) continue;
      final eb = getElementBounds(element);
      if (eb == null) continue;
      newBounds = newBounds == null ? eb : newBounds.expandToInclude(eb);
    }

    _core.state = postState.copyWith(
      pages: updatedPages,
      undoStack: undoStack,
      redoStack: [],
      isDirty: true,
      lassoSelection: LassoSelection(
        selectedIds: postSel.selectedIds,
        bounds: newBounds ?? postSel.bounds,
      ),
    );
  }

  void deleteSelection() {
    if (_core.state == null || _core.state!.lassoSelection == null) return;
    final s = _core.state!;
    final sel = s.lassoSelection!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final filteredContent = page.layers.content.where((element) {
      final id = element.id;
      return !sel.selectedIds.contains(id);
    }).toList();

    final updatedPage = _core.pageWithContent(page, filteredContent);

    _core.commitPageEdit(s, fileName, updatedPage,
        undoOf: page,
        alsoState: (n) => n.copyWith(clearLasso: true, lassoPath: []));
  }

  /// Selected ink as (element id, stroke): freehand strokes plus shapes
  /// traced as their outline, as circuits use them (lines for wires, a
  /// circle for a source ring, a rhombus for a controlled source).
  List<(String, StrokeData)> selectedInk() {
    final s = _core.state;
    final sel = s?.lassoSelection;
    final page = s?.currentPage;
    if (s == null || sel == null || page == null) return const [];
    return [
      for (final e in page.layers.content)
        if (sel.selectedIds.contains(e.id))
          if (e is StrokeElement)
            (e.id, e.data)
          else if (e is ShapeElement)
            if (shapeOutline(e.data) case final outline?)
              (
                e.id,
                StrokeData(
                  points: [for (final p in outline) StrokePoint(x: p.dx, y: p.dy)],
                  color: e.data.strokeColor,
                  baseWidth: e.data.strokeWidth,
                ),
              ),
    ];
  }

  /// Whether [selectedInk] would find anything, without building it.
  bool get selectionHasInk {
    final sel = _core.state?.lassoSelection;
    final page = _core.state?.currentPage;
    if (sel == null || page == null) return false;
    return page.layers.content.any((e) =>
        sel.selectedIds.contains(e.id) &&
        (e is StrokeElement || (e is ShapeElement && shapeOutline(e.data) != null)));
  }

  /// Selected ink for formula recognition: pen strokes plus line shapes
  /// (fraction bars, minus signs). Highlighter is left out.
  List<(String, StrokeData)> selectedMathInk() {
    final s = _core.state;
    final sel = s?.lassoSelection;
    final page = s?.currentPage;
    if (s == null || sel == null || page == null) return const [];
    return [
      for (final e in page.layers.content)
        if (sel.selectedIds.contains(e.id))
          if (e is StrokeElement && !e.data.isHighlighter && e.data.toolType != 'highlighter')
            (e.id, e.data)
          else if (e is ShapeElement && e.data.shapeType == 'line' && !e.data.isHighlighter)
            if (shapeOutline(e.data) case final outline?)
              (
                e.id,
                StrokeData(
                  points: [for (final p in outline) StrokePoint(x: p.dx, y: p.dy)],
                  color: e.data.strokeColor,
                  baseWidth: e.data.strokeWidth,
                ),
              ),
    ];
  }

  void clearSelection() {
    if (_core.state == null) return;
    if (_core.state!.lassoSelection != null) applySelectionTransform();
    _core.state = _core.state!.copyWith(clearLasso: true, lassoPath: [], selectedElementId: null, clearSelectedElement: true);
  }

  /// Change the color of all selected strokes/shapes/text.
  void changeSelectionColor(int newColor) {
    if (_core.state == null || _core.state!.lassoSelection == null) return;
    final s = _core.state!;
    final sel = s.lassoSelection!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    final updatedContent = page.layers.content.map((element) {
      final id = element.id;
      if (!sel.selectedIds.contains(id)) return element;
      return element.map(unknown: (u) => u,
        stroke: (e) => e.copyWith(data: e.data.copyWith(color: newColor)),
        // Span colours would otherwise override the new base colour.
        text: (e) => e.copyWith(
          data: e.data.copyWith(
            color: newColor,
            spans: [
              for (final sp in e.data.spans)
                sp.color == null ? sp : sp.copyWith(color: null),
            ],
          ),
        ),
        image: (e) => e, // images don't have a stroke color
        // A filled shape keeps its fill, re-tinted to the new ink.
        shape: (e) => e.copyWith(
          data: e.data.copyWith(
            strokeColor: newColor,
            fillColor:
                e.data.fillColor == null ? null : shapeFillTint(newColor),
          ),
        ),
        math: (e) => e.copyWith(data: e.data.copyWith(color: newColor)),
      );
    }).toList();

    final updatedPage = _core.pageWithContent(page, updatedContent);

    _core.commitPageEdit(s, fileName, updatedPage, undoOf: page);
  }

  /// Change the stroke/shape width of everything in the current
  /// selection to an absolute value. Mirrors [changeSelectionColor], but
  /// a width control is a slider — it fires many times per drag — so
  /// only the first call of a gesture pushes an undo entry. The UI calls
  /// [endSelectionWidthEdit] on release so the next drag starts fresh.
  void changeSelectionStrokeWidth(double newWidth) {
    if (_core.state == null || _core.state!.lassoSelection == null) return;
    final s = _core.state!;
    final sel = s.lassoSelection!;
    final page = s.currentPage;
    if (page == null) return;
    final fileName = s.currentPageFileName;

    PageData? undoOf;
    if (!_selectionWidthUndoPushed) {
      undoOf = page;
      _selectionWidthUndoPushed = true;
    }

    final updatedContent = page.layers.content.map((element) {
      final id = element.id;
      if (!sel.selectedIds.contains(id)) return element;
      return element.map(unknown: (u) => u,
        stroke: (e) => e.copyWith(data: e.data.copyWith(baseWidth: newWidth)),
        text: (e) => e, // text has no stroke width
        image: (e) => e, // images don't have a stroke width
        shape: (e) => e.copyWith(data: e.data.copyWith(strokeWidth: newWidth)),
        math: (e) => e, // math has no stroke width
      );
    }).toList();

    final updatedPage = _core.pageWithContent(page, updatedContent);

    _core.commitPageEdit(s, fileName, updatedPage, undoOf: undoOf);
  }

  /// Ends the current width-adjustment gesture so the next slider drag
  /// starts its own undo entry instead of continuing the previous one.
  void endSelectionWidthEdit() {
    _selectionWidthUndoPushed = false;
  }

  void selectElement(String elementId) {
    if (_core.state == null) return;
    if (_core.state!.lassoSelection != null) applySelectionTransform();
    _core.state = _core.state!.copyWith(selectedElementId: elementId, clearLasso: true, lassoPath: []);
  }

  void deselectElement() {
    if (_core.state == null) return;
    _core.state = _core.state!.copyWith(clearSelectedElement: true);
  }

  void selectAll() {
    if (_core.state == null) return;
    final page = _core.state!.currentPage;
    if (page == null || page.layers.content.isEmpty) return;

    // UnknownElement is never painted: selecting it would let delete/cut/move destroy it unseen.
    final known = page.layers.content.where((e) => e is! UnknownElement).toList();
    final allIds = known.map((e) {
      return e.id;
    }).toList();

    Rect? bounds;
    for (final element in known) {
      final b = getElementBounds(element);
      if (b != null) bounds = bounds == null ? b : bounds.expandToInclude(b);
    }

    if (bounds == null) return;
    _core.state = _core.state!.copyWith(
      lassoSelection: LassoSelection(selectedIds: allIds, bounds: bounds),
      currentTool: CanvasTool.lasso,
    );
  }
}
