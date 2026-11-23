// Which element lies under a page position: strokes and shapes against their
// real geometry, the rest by bounding box. Pure functions of the page state.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

abstract final class ElementHitTest {
  /// Distance from [p] to the segment [a]-[b].
  static double distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq)
        .clamp(0.0, 1.0);
    return (p - Offset(a.dx + ab.dx * t, a.dy + ab.dy * t)).distance;
  }

  /// True if [pagePos] hits [sh]: its outline within tolerance, or — when
  /// the shape is filled — anywhere inside its body. Tapping the middle of
  /// a solid blob used to select nothing, because only the outline counted.
  static bool shapeHit(ShapeData sh, Offset pagePos) {
    if (distToShapeOutline(sh, pagePos) < max(8.0, sh.strokeWidth)) {
      return true;
    }
    return sh.fillColor != null && shapeBodyContains(sh, pagePos);
  }

  /// Distance from [p] to the OUTLINE of [sh] (handles rotation).
  /// A shape's bounding box is mostly empty space for lines/circles, so
  /// hit-testing must use the real geometry — bbox-contains selected a
  /// diagonal line from taps nowhere near it.
  static double distToShapeOutline(ShapeData sh, Offset p) {
    // Undo the shape's rotation on the probe point so all the outline
    // math below can stay axis-aligned.
    if (sh.shapeType == 'triangle') {
      final tc = triangleCorners(sh);
      return [
        distToSegment(p, tc[0], tc[1]),
        distToSegment(p, tc[1], tc[2]),
        distToSegment(p, tc[2], tc[0]),
      ].reduce(min);
    }
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
        return distToSegment(q, Offset(sh.x1, sh.y1), Offset(sh.x2, sh.y2));
      case 'circle':
        // Distance to the inscribed ellipse the painter actually draws.
        // Radial approximation: scale the probe into unit-circle space,
        // project onto the circle, scale back. Exact when rx == ry (the
        // recognized-circle case) and within a few percent otherwise —
        // fine against an 8 px tap tolerance.
        final oval = shapeEllipseRect(sh);
        final rx = oval.width / 2, ry = oval.height / 2;
        if (rx == 0 || ry == 0) return (q - oval.center).distance;
        final vx = q.dx - oval.center.dx, vy = q.dy - oval.center.dy;
        final k = sqrt((vx * vx) / (rx * rx) + (vy * vy) / (ry * ry));
        if (k == 0) return min(rx, ry);
        return (Offset(vx, vy) * (1 - 1 / k)).distance;
      case 'triangle':
        final apex = Offset((l + r) / 2, t);
        final bl = Offset(l, b), br = Offset(r, b);
        return [
          distToSegment(q, apex, bl),
          distToSegment(q, bl, br),
          distToSegment(q, br, apex),
        ].reduce(min);
      case 'rhombus':
        final top = Offset((l + r) / 2, t), right = Offset(r, (t + b) / 2);
        final bottom = Offset((l + r) / 2, b), left = Offset(l, (t + b) / 2);
        return [
          distToSegment(q, top, right),
          distToSegment(q, right, bottom),
          distToSegment(q, bottom, left),
          distToSegment(q, left, top),
        ].reduce(min);
      default: // rectangle and anything unknown: rect edges
        final tl = Offset(l, t), tr = Offset(r, t);
        final brc = Offset(r, b), blc = Offset(l, b);
        return [
          distToSegment(q, tl, tr),
          distToSegment(q, tr, brc),
          distToSegment(q, brc, blc),
          distToSegment(q, blc, tl),
        ].reduce(min);
    }
  }

  /// True if [pagePos] is within [tolerance] of any point of the stroke.
  static bool strokeHit(StrokeData data, Offset pagePos, double tolerance) {
    final tolSq = tolerance * tolerance;
    for (final p in data.points) {
      final dx = p.x - pagePos.dx;
      final dy = p.y - pagePos.dy;
      if (dx * dx + dy * dy < tolSq) return true;
    }
    return false;
  }

  static String? findElementAt(CanvasState state, Offset pagePos,
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
      element.map(unknown: (u) => u,
        stroke: (s) {
          if (s.data.points.isEmpty) return;
          if (strokeHit(s.data, pagePos, max(8.0, s.data.baseWidth))) {
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
          if (shapeHit(s.data, pagePos)) {
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
  static String? findImageOrShapeAt(CanvasState state, Offset pagePos, {bool imagesOnly = false}) {
    final page = state.currentPage;
    if (page == null) return null;
    for (int i = page.layers.content.length - 1; i >= 0; i--) {
      final element = page.layers.content[i];
      Rect? bounds;
      String? id;
      var geometryHit = false;
      element.map(unknown: (u) => u,
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
          if (!imagesOnly && shapeHit(s.data, pagePos)) {
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

  static Rect? getSelectedElementBounds(CanvasState state) {
    if (state.selectedElementId == null) return null;
    final page = state.currentPage;
    if (page == null) return null;
    for (final element in page.layers.content) {
      final id = element.id;
      if (id != state.selectedElementId) continue;
      return element.map(unknown: (_) => null,
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

  /// Topmost TextElement whose bounds contain [pagePos], or null.
  static TextElement? findTextElementAt(CanvasState state, Offset pagePos) {
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
}
