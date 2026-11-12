// Strokes -> grayscale plane at the scale the detector was trained on.
//
// Training pages were rendered so a page width maps to ~1024 px with ~3.3 px
// strokes, so selections are rasterized the same way regardless of zoom or
// pen width.

import 'dart:math' as math;
import 'dart:typed_data';

import 'native_engine.dart';

/// Pixels per page-width the detector expects.
const double kModelPageWidthPx = 1024;
const double _strokeRadius = 1.65;
const int _margin = 24;

class Raster {
  Raster(this.data, this.width, this.height, this.scale, this.originX, this.originY);

  /// 1 = paper, 0 = ink, row-major.
  final Float32List data;
  final int width, height;

  /// Model pixels per page unit, and the page point mapped to pixel (0, 0).
  final double scale, originX, originY;

  double toPageX(double px) => originX + px / scale;
  double toPageY(double py) => originY + py / scale;
  double toPxX(double x) => (x - originX) * scale;
  double toPxY(double y) => (y - originY) * scale;
}

/// [strokes] are flat [x0, y0, x1, y1, ...] polylines in page units.
/// Sides are padded up to a multiple of [multiple], as the network requires.
Raster rasterize(List<Float64List> strokes, double pageWidth,
    {int multiple = 32, double pagePx = kModelPageWidthPx}) {
  final scale = pagePx / pageWidth;
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final s in strokes) {
    for (var i = 0; i + 1 < s.length; i += 2) {
      minX = math.min(minX, s[i]);
      maxX = math.max(maxX, s[i]);
      minY = math.min(minY, s[i + 1]);
      maxY = math.max(maxY, s[i + 1]);
    }
  }
  if (!minX.isFinite) return Raster(Float32List(0), 0, 0, scale, 0, 0);
  final margin = _margin * pagePx / kModelPageWidthPx;
  final ox = minX - margin / scale, oy = minY - margin / scale;
  int up(double v) => ((v / multiple).ceil() * multiple).clamp(multiple, 1 << 14);
  final w = up((maxX - minX) * scale + 2 * margin);
  final h = up((maxY - minY) * scale + 2 * margin);
  final img = Float32List(w * h)..fillRange(0, w * h, 1.0);
  final r = _strokeRadius * pagePx / kModelPageWidthPx, r2 = r * r;
  for (final s in strokes) {
    final n = s.length ~/ 2;
    for (var i = 0; i < n; i++) {
      final ax = (s[2 * i] - ox) * scale, ay = (s[2 * i + 1] - oy) * scale;
      final j = i + 1 < n ? i + 1 : i;
      final bx = (s[2 * j] - ox) * scale, by = (s[2 * j + 1] - oy) * scale;
      final x0 = math.max(0, (math.min(ax, bx) - r).floor());
      final x1 = math.min(w - 1, (math.max(ax, bx) + r).ceil());
      final y0 = math.max(0, (math.min(ay, by) - r).floor());
      final y1 = math.min(h - 1, (math.max(ay, by) + r).ceil());
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          final px = x + 0.5 - ax, py = y + 0.5 - ay;
          final t = len2 == 0 ? 0.0 : ((px * dx + py * dy) / len2).clamp(0.0, 1.0);
          final ex = px - t * dx, ey = py - t * dy;
          if (ex * ex + ey * ey <= r2) img[y * w + x] = 0;
        }
      }
    }
  }
  return Raster(img, w, h, scale, ox, oy);
}

/// A picture's ink as a mask: 1 = ink, [scale] mask pixels per source pixel.
class InkMask {
  InkMask(this.data, this.width, this.height, this.scale);
  final Uint8List data;
  final int width, height;
  final double scale;
}

/// As [rasterize], but the plane is [ink] itself (at the ink's own width,
/// as the detector saw photos in training) rather than [strokes] redrawn
/// at a fixed pen width. Strokes are in the mask's source pixels.
Raster rasterizeInk(InkMask ink, List<Float64List> strokes, double pageWidth) {
  final r = rasterize(strokes, pageWidth);
  if (r.data.isEmpty) return r;
  final w = ink.width, h = ink.height;
  final native = NativeImage.open();
  if (native != null) {
    r.data.setAll(0, native.rasterizeInk(ink.data, w, h, ink.scale, r.originX, r.originY, r.scale, r.width, r.height));
    return r;
  }
  // Summed-area table: the ink in each raster pixel's footprint is four lookups.
  final sat = Int32List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0;
    for (var x = 0; x < w; x++) {
      row += ink.data[y * w + x];
      sat[(y + 1) * (w + 1) + x + 1] = sat[y * (w + 1) + x + 1] + row;
    }
  }
  double edge(double v, int hi) => v.clamp(0.0, hi.toDouble());
  for (var py = 0; py < r.height; py++) {
    final y0 = edge((r.originY + py / r.scale) * ink.scale, h), y1 = edge((r.originY + (py + 1) / r.scale) * ink.scale, h);
    for (var px = 0; px < r.width; px++) {
      final x0 = edge((r.originX + px / r.scale) * ink.scale, w), x1 = edge((r.originX + (px + 1) / r.scale) * ink.scale, w);
      // Whole mask pixels, grown to at least one so a thin line is not lost.
      final xa = x0.floor(), xb = math.max(xa + 1, x1.ceil()).clamp(0, w);
      final ya = y0.floor(), yb = math.max(ya + 1, y1.ceil()).clamp(0, h);
      if (xa >= w || ya >= h) {
        r.data[py * r.width + px] = 1;
        continue;
      }
      final sum = sat[yb * (w + 1) + xb] - sat[ya * (w + 1) + xb] - sat[yb * (w + 1) + xa] + sat[ya * (w + 1) + xa];
      r.data[py * r.width + px] = 1 - sum / ((xb - xa) * (yb - ya));
    }
  }
  return r;
}
