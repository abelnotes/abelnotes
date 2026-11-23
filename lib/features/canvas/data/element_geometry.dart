// Pure geometry on page elements and shapes: translate, scale, rotate, bounds, outlines.
import 'dart:math';
import 'dart:ui';

import 'package:abelnotes/features/canvas/data/render_engine.dart'
    show shapeEllipseRect, triangleCorners;
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Apply a point transform to each vertex pair in [v] (length 6 = 3
/// vertices). Returns the input unchanged when empty. Used to keep
/// oblique-triangle vertices coherent under translate / scale / rotate
/// / flip operations on a shape — without this, transforms updated the
/// bbox + rotation field but the absolute-coord vertices stayed frozen
/// and the triangle rendered at the OLD position/orientation.
List<double> transformVertices(List<double> v, Offset Function(Offset) fn) {
  if (v.length != 6) return v;
  final out = List<double>.filled(6, 0);
  for (var i = 0; i < 6; i += 2) {
    final p = fn(Offset(v[i], v[i + 1]));
    out[i] = p.dx;
    out[i + 1] = p.dy;
  }
  return out;
}

/// A circle whose box is square and unrotated (not a recognized oval).
bool isRound(ShapeData s) =>
    s.rotation == 0 && ((s.x2 - s.x1).abs() - (s.y2 - s.y1).abs()).abs() < 1;

/// Moves the (x2,y2) corner of a possibly rotated rectangle to [cursor] on
/// the page, keeping the opposite corner where it is on the page.
ShapeData dragRectCorner(ShapeData s, Offset cursor) {
  if (s.rotation == 0) return s.copyWith(x2: cursor.dx, y2: cursor.dy);
  final c0 = Offset((s.x1 + s.x2) / 2, (s.y1 + s.y2) / 2);
  final ca = cos(s.rotation), sa = sin(s.rotation);
  Offset rot(Offset p, double c, double sn) =>
      Offset(p.dx * c - p.dy * sn, p.dx * sn + p.dy * c);
  final anchor = c0 + rot(Offset(s.x1, s.y1) - c0, ca, sa);
  final u = rot(cursor - anchor, ca, -sa);
  final c1 = anchor + rot(u / 2, ca, sa);
  final a = c1 - u / 2, b = c1 + u / 2;
  return s.copyWith(x1: a.dx, y1: a.dy, x2: b.dx, y2: b.dy);
}

/// True if any sampled point of [sh]'s outline lies within [radius] of [p].
bool shapeOutlineWithin(ShapeData sh, Offset p, double radius) {
  final r2 = radius * radius;
  for (final edge in shapeToSampledEdges(sh, radius * 0.5)) {
    for (final pt in edge) {
      final dx = pt.x - p.dx;
      final dy = pt.y - p.dy;
      if (dx * dx + dy * dy < r2) return true;
    }
  }
  return false;
}

/// Convert a shape outline into sampled edge segments (list of point lists).
/// Each edge is densely sampled so point-by-point erasure works.
/// Points are in final (rotated) coordinates.
List<List<StrokePoint>> shapeToSampledEdges(ShapeData sh, double stepSize) {
  final rawEdges = <List<Offset>>[];

  switch (sh.shapeType) {
    case 'line':
    case 'arrow':
      rawEdges.add([Offset(sh.x1, sh.y1), Offset(sh.x2, sh.y2)]);
      break;
    case 'rectangle':
      final l = min(sh.x1, sh.x2), r = max(sh.x1, sh.x2);
      final t = min(sh.y1, sh.y2), b = max(sh.y1, sh.y2);
      rawEdges.addAll([
        [Offset(l, t), Offset(r, t)],
        [Offset(r, t), Offset(r, b)],
        [Offset(r, b), Offset(l, b)],
        [Offset(l, b), Offset(l, t)],
      ]);
      break;
    case 'triangle':
      final tc = triangleCorners(sh);
      rawEdges.addAll([
        [tc[0], tc[1]],
        [tc[1], tc[2]],
        [tc[2], tc[0]]
      ]);
      break;
    case 'rhombus':
      final rl = min(sh.x1, sh.x2), rr = max(sh.x1, sh.x2);
      final rt = min(sh.y1, sh.y2), rb = max(sh.y1, sh.y2);
      final mx = (rl + rr) / 2, my = (rt + rb) / 2;
      final top = Offset(mx, rt), right = Offset(rr, my);
      final bottom = Offset(mx, rb), left = Offset(rl, my);
      rawEdges.addAll([
        [top, right],
        [right, bottom],
        [bottom, left],
        [left, top],
      ]);
      break;
    case 'circle':
      // MUST match what the painter draws (the ellipse inscribed in the
      // bbox). This used to sample a circle of half-DIAGONAL radius —
      // ~1.41× the drawn outline on the square bbox recognition emits —
      // so every sampled point sat well outside the ink and the eraser
      // never hit a circle no matter where the user put it.
      final oval = shapeEllipseRect(sh);
      final rx = oval.width / 2, ry = oval.height / 2;
      final cx = oval.center.dx, cy = oval.center.dy;
      // Ramanujan's perimeter approximation → point count.
      final sum = rx + ry;
      final h = sum == 0 ? 0.0 : ((rx - ry) * (rx - ry)) / (sum * sum);
      final perimeter = pi * sum * (1 + (3 * h) / (10 + sqrt(4 - 3 * h)));
      final n = max(36, (perimeter / stepSize).ceil());
      // Ellipse as one continuous edge of n+1 points
      final pts = <Offset>[];
      for (int i = 0; i <= n; i++) {
        final a = 2 * pi * i / n;
        pts.add(Offset(cx + rx * cos(a), cy + ry * sin(a)));
      }
      rawEdges.add(pts);
      break;
    default:
      final l = min(sh.x1, sh.x2), r = max(sh.x1, sh.x2);
      final t = min(sh.y1, sh.y2), b = max(sh.y1, sh.y2);
      rawEdges.addAll([
        [Offset(l, t), Offset(r, t)],
        [Offset(r, t), Offset(r, b)],
        [Offset(r, b), Offset(l, b)],
        [Offset(l, b), Offset(l, t)],
      ]);
      break;
  }

  // Rotation transform
  final cx = (sh.x1 + sh.x2) / 2;
  final cy = (sh.y1 + sh.y2) / 2;
  final hasRotation = sh.rotation != 0 && sh.shapeType != 'triangle';
  final cosA = hasRotation ? cos(sh.rotation) : 1.0;
  final sinA = hasRotation ? sin(sh.rotation) : 0.0;

  Offset rotatePoint(Offset p) {
    if (!hasRotation) return p;
    final dx = p.dx - cx;
    final dy = p.dy - cy;
    return Offset(cx + dx * cosA - dy * sinA, cy + dx * sinA + dy * cosA);
  }

  // Sample each edge and apply rotation
  final result = <List<StrokePoint>>[];
  for (final edge in rawEdges) {
    final sampled = <StrokePoint>[];
    // For multi-point edges (circles), sample between consecutive pairs
    for (int i = 0; i < edge.length - 1; i++) {
      final p1 = edge[i];
      final p2 = edge[i + 1];
      final dist = (p2 - p1).distance;
      final count = max(2, (dist / stepSize).ceil() + 1);
      // Don't duplicate the start point for interior segments
      final startIdx = (i == 0) ? 0 : 1;
      for (int j = startIdx; j < count; j++) {
        final t = j / (count - 1);
        final raw =
            Offset(p1.dx + (p2.dx - p1.dx) * t, p1.dy + (p2.dy - p1.dy) * t);
        final rotated = rotatePoint(raw);
        sampled.add(StrokePoint(x: rotated.dx, y: rotated.dy, pressure: 1.0));
      }
    }
    if (sampled.length >= 2) result.add(sampled);
  }
  return result;
}

/// Ray casting point-in-polygon test
bool pointInPolygon(Offset point, List<Offset> polygon) {
  bool inside = false;
  int j = polygon.length - 1;
  for (int i = 0; i < polygon.length; i++) {
    if ((polygon[i].dy > point.dy) != (polygon[j].dy > point.dy) &&
        point.dx <
            (polygon[j].dx - polygon[i].dx) *
                    (point.dy - polygon[i].dy) /
                    (polygon[j].dy - polygon[i].dy) +
                polygon[i].dx) {
      inside = !inside;
    }
    j = i;
  }
  return inside;
}

Rect? getElementBounds(ContentElement element) {
  Rect getRotatedBounds(Rect rect, double rotation) {
    if (rotation == 0.0) return rect;
    final c = rect.center;
    final cosA = cos(rotation);
    final sinA = sin(rotation);
    Offset r(Offset p) {
      final dx = p.dx - c.dx;
      final dy = p.dy - c.dy;
      return Offset(c.dx + dx * cosA - dy * sinA, c.dy + dx * sinA + dy * cosA);
    }

    final pts = [
      r(rect.topLeft),
      r(rect.topRight),
      r(rect.bottomLeft),
      r(rect.bottomRight)
    ];
    final xs = pts.map((p) => p.dx);
    final ys = pts.map((p) => p.dy);
    return Rect.fromLTRB(
        xs.reduce(min), ys.reduce(min), xs.reduce(max), ys.reduce(max));
  }

  return element.map(
    unknown: (_) => null,
    stroke: (e) {
      if (e.data.points.isEmpty) return null;
      final xs = e.data.points.map((p) => p.x);
      final ys = e.data.points.map((p) => p.y);
      final halfW = e.data.baseWidth / 2.0;
      return Rect.fromLTRB(xs.reduce(min) - halfW, ys.reduce(min) - halfW,
          xs.reduce(max) + halfW, ys.reduce(max) + halfW);
    },
    text: (e) => Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
    image: (e) {
      final rect =
          Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height);
      return getRotatedBounds(rect, e.data.rotation);
    },
    shape: (e) {
      final halfW = e.data.strokeWidth / 2.0;
      final baseRect = Rect.fromPoints(
              Offset(e.data.x1, e.data.y1), Offset(e.data.x2, e.data.y2))
          .inflate(halfW);
      return getRotatedBounds(baseRect, e.data.rotation);
    },
    math: (e) => Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
  );
}

ContentElement rotateElementAroundCenter(
    ContentElement element, Offset center, double angle) {
  Offset rotatePoint(double x, double y) {
    final cosA = cos(angle);
    final sinA = sin(angle);
    final dx = x - center.dx;
    final dy = y - center.dy;
    return Offset(
        center.dx + dx * cosA - dy * sinA, center.dy + dx * sinA + dy * cosA);
  }

  return element.map(
    unknown: (u) => u,
    stroke: (e) => ContentElement.stroke(
      id: e.id,
      zIndex: e.zIndex,
      data: StrokeData(
        points: e.data.points.map((p) {
          final rp = rotatePoint(p.x, p.y);
          return StrokePoint(
              x: rp.dx,
              y: rp.dy,
              pressure: p.pressure,
              tilt: p.tilt,
              timestamp: p.timestamp);
        }).toList(),
        toolType: e.data.toolType,
        color: e.data.color,
        baseWidth: e.data.baseWidth,
        isHighlighter: e.data.isHighlighter,
        opacity: e.data.opacity,
        timestamp: e.data.timestamp,
      ),
    ),
    text: (e) {
      final rp = rotatePoint(e.data.x, e.data.y);
      return ContentElement.text(
        id: e.id, zIndex: e.zIndex,
        // copyWith preserves spans/fontFamily; rotation only moves the box.
        data: e.data.copyWith(x: rp.dx, y: rp.dy),
      );
    },
    image: (e) {
      // Rotate only the element center around the selection center,
      // then translate the bounding box by the center offset.
      // The internal rotation is incremented to match the visual preview.
      final oldCx = e.data.x + e.data.width / 2;
      final oldCy = e.data.y + e.data.height / 2;
      final rCenter = rotatePoint(oldCx, oldCy);
      final dx = rCenter.dx - oldCx;
      final dy = rCenter.dy - oldCy;
      return ContentElement.image(
        id: e.id, zIndex: e.zIndex,
        // copyWith preserves flipHorizontal (and any future field).
        data: e.data.copyWith(
          x: e.data.x + dx,
          y: e.data.y + dy,
          rotation: e.data.rotation + angle,
        ),
      );
    },
    shape: (e) {
      // Rotate only the element center around the selection center,
      // then translate the bounding box by the center offset.
      final oldCx = (e.data.x1 + e.data.x2) / 2;
      final oldCy = (e.data.y1 + e.data.y2) / 2;
      final rCenter = rotatePoint(oldCx, oldCy);
      final dx = rCenter.dx - oldCx;
      final dy = rCenter.dy - oldCy;
      // For vertex triangles, rotate each vertex around the new bbox
      // centre too — the bbox translation alone wouldn't carry the
      // shape's orientation through.
      final cosA = cos(angle);
      final sinA = sin(angle);
      final newCx = oldCx + dx;
      final newCy = oldCy + dy;
      final newVertices = transformVertices(e.data.vertices, (p) {
        final ddx = p.dx + dx - newCx;
        final ddy = p.dy + dy - newCy;
        return Offset(
            newCx + ddx * cosA - ddy * sinA, newCy + ddx * sinA + ddy * cosA);
      });
      return ContentElement.shape(
        id: e.id,
        zIndex: e.zIndex,
        data: e.data.copyWith(
          x1: e.data.x1 + dx,
          y1: e.data.y1 + dy,
          x2: e.data.x2 + dx,
          y2: e.data.y2 + dy,
          rotation: e.data.rotation + angle,
          vertices: newVertices,
        ),
      );
    },
    math: (e) {
      final rp = rotatePoint(e.data.x, e.data.y);
      return ContentElement.math(
        id: e.id,
        zIndex: e.zIndex,
        data: e.data.copyWith(x: rp.dx, y: rp.dy),
      );
    },
  );
}

ContentElement translateElement(ContentElement element, Offset offset) {
  return element.map(
    unknown: (u) => u,
    stroke: (e) => ContentElement.stroke(
      id: e.id,
      zIndex: e.zIndex,
      data: StrokeData(
        points: e.data.points
            .map((p) => StrokePoint(
                  x: p.x + offset.dx,
                  y: p.y + offset.dy,
                  pressure: p.pressure,
                  tilt: p.tilt,
                  timestamp: p.timestamp,
                ))
            .toList(),
        toolType: e.data.toolType,
        color: e.data.color,
        baseWidth: e.data.baseWidth,
        isHighlighter: e.data.isHighlighter,
        opacity: e.data.opacity,
        timestamp: e.data.timestamp,
      ),
    ),
    // copyWith preserves spans/fontFamily/flipHorizontal — a from-scratch
    // rebuild dropped them on every move (and powers paste/duplicate).
    text: (e) => ContentElement.text(
      id: e.id,
      zIndex: e.zIndex,
      data: e.data.copyWith(
        x: e.data.x + offset.dx,
        y: e.data.y + offset.dy,
      ),
    ),
    image: (e) => ContentElement.image(
      id: e.id,
      zIndex: e.zIndex,
      data: e.data.copyWith(
        x: e.data.x + offset.dx,
        y: e.data.y + offset.dy,
      ),
    ),
    // copyWith preserves isHighlighter (and any other untouched field)
    // — a from-scratch rebuild silently reset it to opaque on every move.
    shape: (e) => ContentElement.shape(
      id: e.id,
      zIndex: e.zIndex,
      data: e.data.copyWith(
        x1: e.data.x1 + offset.dx,
        y1: e.data.y1 + offset.dy,
        x2: e.data.x2 + offset.dx,
        y2: e.data.y2 + offset.dy,
        vertices: transformVertices(e.data.vertices, (p) => p + offset),
      ),
    ),
    math: (e) => ContentElement.math(
      id: e.id,
      zIndex: e.zIndex,
      data: e.data.copyWith(
        x: e.data.x + offset.dx,
        y: e.data.y + offset.dy,
      ),
    ),
  );
}

Rect elementBounds(ContentElement element) {
  return element.map(
    unknown: (_) => Rect.zero,
    stroke: (e) {
      if (e.data.points.isEmpty) return Rect.zero;
      double mnX = e.data.points.first.x,
          mxX = mnX,
          mnY = e.data.points.first.y,
          mxY = mnY;
      for (final p in e.data.points) {
        if (p.x < mnX) mnX = p.x;
        if (p.x > mxX) mxX = p.x;
        if (p.y < mnY) mnY = p.y;
        if (p.y > mxY) mxY = p.y;
      }
      return Rect.fromLTRB(mnX, mnY, mxX, mxY);
    },
    text: (e) => Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
    image: (e) =>
        Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
    shape: (e) => Rect.fromPoints(
        Offset(e.data.x1, e.data.y1), Offset(e.data.x2, e.data.y2)),
    math: (e) => Rect.fromLTWH(e.data.x, e.data.y, e.data.width, e.data.height),
  );
}

ContentElement scaleElement(
    ContentElement element, Offset center, double scale) {
  return element.map(
    unknown: (u) => u,
    stroke: (e) => ContentElement.stroke(
      id: e.id,
      zIndex: e.zIndex,
      data: StrokeData(
        points: e.data.points
            .map((p) => StrokePoint(
                  x: center.dx + (p.x - center.dx) * scale,
                  y: center.dy + (p.y - center.dy) * scale,
                  pressure: p.pressure,
                  tilt: p.tilt,
                  timestamp: p.timestamp,
                ))
            .toList(),
        toolType: e.data.toolType,
        color: e.data.color,
        baseWidth: e.data.baseWidth * scale,
        isHighlighter: e.data.isHighlighter,
        opacity: e.data.opacity,
        timestamp: e.data.timestamp,
      ),
    ),
    // copyWith preserves spans/fontFamily; scale also multiplies the
    // element fontSize AND every per-span fontSize override so multi-size
    // rich text scales uniformly instead of collapsing overridden runs.
    text: (e) => ContentElement.text(
      id: e.id,
      zIndex: e.zIndex,
      data: e.data.copyWith(
        x: center.dx + (e.data.x - center.dx) * scale,
        y: center.dy + (e.data.y - center.dy) * scale,
        width: e.data.width * scale,
        height: e.data.height * scale,
        fontSize: e.data.fontSize * scale,
        spans: e.data.spans
            .map((sp) => sp.fontSize == null
                ? sp
                : sp.copyWith(fontSize: sp.fontSize! * scale))
            .toList(),
      ),
    ),
    image: (e) => ContentElement.image(
      id: e.id,
      zIndex: e.zIndex,
      data: e.data.copyWith(
        x: center.dx + (e.data.x - center.dx) * scale,
        y: center.dy + (e.data.y - center.dy) * scale,
        width: e.data.width * scale,
        height: e.data.height * scale,
      ),
    ),
    shape: (e) => ContentElement.shape(
      id: e.id,
      zIndex: e.zIndex,
      data: e.data.copyWith(
        x1: center.dx + (e.data.x1 - center.dx) * scale,
        y1: center.dy + (e.data.y1 - center.dy) * scale,
        x2: center.dx + (e.data.x2 - center.dx) * scale,
        y2: center.dy + (e.data.y2 - center.dy) * scale,
        strokeWidth: e.data.strokeWidth * scale,
        vertices: transformVertices(
            e.data.vertices,
            (p) => Offset(center.dx + (p.dx - center.dx) * scale,
                center.dy + (p.dy - center.dy) * scale)),
      ),
    ),
    math: (e) => ContentElement.math(
      id: e.id,
      zIndex: e.zIndex,
      data: e.data.copyWith(
        x: center.dx + (e.data.x - center.dx) * scale,
        y: center.dy + (e.data.y - center.dy) * scale,
        width: e.data.width * scale,
        height: e.data.height * scale,
        fontSize: e.data.fontSize * scale,
      ),
    ),
  );
}
