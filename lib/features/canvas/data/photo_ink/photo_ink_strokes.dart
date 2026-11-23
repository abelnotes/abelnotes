// A picture's handwriting as page strokes: traced off the UI thread, placed
// where the picture was, in the nearest pen colour.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/image_circuit.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'photo_ink.dart';

/// The handwriting in image [d] (file [bytes]) as strokes over its box, or
/// null when none is found; the string says why, for the log.
Future<(List<StrokeData>?, String)> photoInkStrokes(Uint8List bytes, ImageData d) async {
  final watch = Stopwatch()..start();
  final pixels = await decodeRgba(bytes);
  if (pixels == null) return (null, 'image not decoded');
  final tDecode = watch.elapsedMilliseconds;
  final ink = await compute(_trace, pixels);
  final why = '${ink.strokes.length} strokes, rectified ${ink.rectified}; decode $tDecode, '
      'trace ${watch.elapsedMilliseconds - tDecode} ms';
  final strokes = placePhotoInk(ink, d);
  return (strokes.isEmpty ? null : strokes, why);
}

PhotoInk _trace((Uint8List, int, int) p) => photoToInk(p.$1, p.$2, p.$3);

/// [ink] laid over image [d]: a straightened sheet fits the box keeping its
/// proportions, a photo traced as is fills it; flip and rotation follow the
/// image's.
List<StrokeData> placePhotoInk(PhotoInk ink, ImageData d) {
  final ow = ink.width, oh = ink.height;
  final double sx, sy;
  if (ink.rectified) {
    sx = sy = math.min(d.width / ow, d.height / oh);
  } else {
    sx = d.width / ow;
    sy = d.height / oh;
  }
  final scale = (sx + sy) / 2;
  final cosR = math.cos(d.rotation), sinR = math.sin(d.rotation);
  Float64List toPage(Float64List flat) {
    final out = Float64List(flat.length);
    for (var i = 0; i + 1 < flat.length; i += 2) {
      final lx = ((d.flipHorizontal ? ow - flat[i] : flat[i]) - ow / 2) * sx;
      final ly = (flat[i + 1] - oh / 2) * sy;
      out[i] = d.x + d.width / 2 + lx * cosR - ly * sinR;
      out[i + 1] = d.y + d.height / 2 + lx * sinR + ly * cosR;
    }
    return out;
  }

  final pens = [for (final s in ink.strokes) if (!s.highlighter) s];
  final colors = penColors(pens);
  final now = DateTime.now();
  final out = <StrokeData>[];
  for (var i = 0; i < pens.length; i++) {
    final s = pens[i];
    // A dot is two equal points: it gets a short tick so it draws.
    final pts = s.points.length == 4 && s.points[0] == s.points[2] && s.points[1] == s.points[3]
        ? Float64List.fromList([s.points[0] - 0.25, s.points[1], s.points[0] + 0.25, s.points[1]])
        : s.points;
    // A ballpoint, not a technical line: it is handwriting, which the
    // handwriting search reads (technical lines are skipped as drawings).
    out.add(StrokeData(
      points: _penPoints(toPage(pts)),
      toolType: 'ballpoint',
      color: colors[i],
      baseWidth: math.max(0.6, s.width * scale),
      opacity: d.opacity,
      timestamp: now,
    ));
  }
  for (final s in ink.strokes) {
    if (!s.highlighter) continue;
    out.add(StrokeData(
      points: _penPoints(toPage(s.points)),
      toolType: 'highlighter',
      color: highlighterColor(s.color),
      baseWidth: math.max(2.0, s.width * scale),
      isHighlighter: true,
      opacity: 0.35,
      timestamp: now,
    ));
  }
  return out;
}

/// Points about every page unit along [flat] at full pressure, so a
/// ballpoint draws them at its base width.
List<StrokePoint> _penPoints(Float64List flat) {
  final out = [StrokePoint(x: flat[0], y: flat[1], pressure: 1)];
  var t = 0.0;
  for (var k = 2; k + 1 < flat.length; k += 2) {
    final x0 = flat[k - 2], y0 = flat[k - 1], x1 = flat[k], y1 = flat[k + 1];
    final len = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    final n = math.max(1, len.ceil());
    for (var j = 1; j <= n; j++) {
      t += len / n * 5;
      out.add(StrokePoint(x: x0 + (x1 - x0) * j / n, y: y0 + (y1 - y0) * j / n, pressure: 1, timestamp: t.round()));
    }
  }
  return out;
}

const int kPhotoBlack = 0xFF000000;
const int kPhotoBlue = 0xFF1F4FC1;
const int kPhotoRed = 0xFFD0312D;
const int kPhotoGreen = 0xFF2E7D32;

/// Each stroke's measured ink colour (against the paper) as a pen colour:
/// black, blue, red or green. Where one colour covers nearly all the ink
/// (90% of its length), every stroke takes it: a page in one pen stays one.
List<int> penColors(List<PhotoStroke> strokes) {
  final cls = [for (final s in strokes) inkClass(s.color)];
  final len = <int, double>{};
  var total = 0.0;
  for (var i = 0; i < strokes.length; i++) {
    final p = strokes[i].points;
    var l = 0.0;
    for (var k = 2; k + 1 < p.length; k += 2) {
      l += math.sqrt(math.pow(p[k] - p[k - 2], 2) + math.pow(p[k + 1] - p[k - 1], 2));
    }
    len[cls[i]] = (len[cls[i]] ?? 0) + l + 1;
    total += l + 1;
  }
  for (final e in len.entries) {
    if (e.value >= 0.9 * total) return List.filled(strokes.length, e.key);
  }
  return cls;
}

/// The pen colour nearest an ink measured against its paper (ARGB).
int inkClass(int argb) {
  final r = (argb >> 16 & 255) / 255, g = (argb >> 8 & 255) / 255, b = (argb & 255) / 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  if (mx - mn < 0.12) return kPhotoBlack;
  if (b >= r && b >= g) return kPhotoBlue;
  if (r >= g && r >= b) return r - g > 0.15 ? kPhotoRed : kPhotoBlack;
  return g - r > 0.08 ? kPhotoGreen : kPhotoBlack;
}

/// A highlighter's measured tint as the nearest highlighter colour.
int highlighterColor(int argb) {
  const presets = [0xFFFFEB3B, 0xFFFFA726, 0xFFFF4081, 0xFF76FF03, 0xFF40C4FF];
  double hue(int c) {
    final r = (c >> 16 & 255) / 255, g = (c >> 8 & 255) / 255, b = (c & 255) / 255;
    return math.atan2(math.sqrt(3) * (g - b), 2 * r - g - b);
  }

  final h = hue(argb);
  var best = presets.first;
  var bestD = double.infinity;
  for (final p in presets) {
    var dd = (hue(p) - h).abs();
    if (dd > math.pi) dd = 2 * math.pi - dd;
    if (dd < bestD) (best, bestD) = (p, dd);
  }
  return best;
}
