// Covers the scale-aware stroke simplification the page-manager grid uses
// for its previews (see lib/features/canvas/data/thumbnail_simplify.dart).
//
// The contract has two halves, and both matter:
//   - Pages drawn at or near full size must come back UNTOUCHED, by identity
//     — the main canvas must never render simplified ink.
//   - Pages drawn into a small tile must lose the sub-pixel detail that the
//     tile cannot show, without the preview visibly changing.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/features/canvas/data/thumbnail_simplify.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// AppConfig.scratchPageSize — a free-sketch page.
const double kSketchSize = 6000.0;

/// The page-manager grid tile, and a typical raster density.
const ui.Size kTile = ui.Size(110, 150);
const double kDpr = 3.0;

double devicePixelsPerUnit(PageData page, ui.Size box, double dpr) =>
    math.min(box.width / page.width, box.height / page.height) * dpr;

PageData sketchPage({
  int strokes = 400,
  int pointsPerStroke = 40,
  double width = kSketchSize,
  double height = kSketchSize,
  int seed = 1,
  List<ContentElement> extra = const [],
}) {
  final rnd = math.Random(seed);
  final content = <ContentElement>[];
  for (var s = 0; s < strokes; s++) {
    var x = rnd.nextDouble() * width;
    var y = rnd.nextDouble() * height;
    final pts = <StrokePoint>[];
    for (var i = 0; i < pointsPerStroke; i++) {
      // ~6 page units between samples — what a stylus produces at 1:1.
      x += (rnd.nextDouble() - 0.5) * 12;
      y += (rnd.nextDouble() - 0.5) * 12;
      pts.add(StrokePoint(x: x, y: y, pressure: 0.5));
    }
    content.add(ContentElement.stroke(
      id: 's$s',
      zIndex: s,
      data: StrokeData(points: pts, baseWidth: 2.0),
    ));
  }
  content.addAll(extra);
  return PageData(
    pageId: 'p',
    pageNumber: 1,
    width: width,
    height: height,
    layers: RenderingLayers(content: content),
  );
}

int pointCount(PageData p) => p.layers.content
    .whereType<StrokeElement>()
    .fold<int>(0, (n, e) => n + e.data.points.length);

Future<Uint8List> raster(PageData page, ui.Size logical, double dpr) async {
  final pxW = (logical.width * dpr).round();
  final pxH = (logical.height * dpr).round();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, pxW.toDouble(), pxH.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  canvas.scale(dpr);
  CanvasRenderEngine(pageData: page, zoom: 1.0).paint(canvas, logical);
  final picture = recorder.endRecording();
  final image = await picture.toImage(pxW, pxH);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Mean per-pixel luminance difference, 0-255.
double meanPixelError(Uint8List a, Uint8List b) {
  var sum = 0.0;
  final n = a.length ~/ 4;
  for (var i = 0; i < n; i++) {
    final o = i * 4;
    final la = (a[o] + a[o + 1] + a[o + 2]) / 3;
    final lb = (b[o] + b[o + 1] + b[o + 2]) / 3;
    sum += (la - lb).abs();
  }
  return sum / n;
}

void main() {
  group('pages drawn at full size are left alone', () {
    test('A4 fitted to a desktop viewport returns the same instance', () {
      final page = sketchPage(strokes: 50, width: 595, height: 842);
      final dpu = devicePixelsPerUnit(page, const ui.Size(700, 990), 1.0);
      expect(identical(simplifyForPreview(page, dpu), page), isTrue);
    });

    test('a scratch page at 1:1 returns the same instance', () {
      final page = sketchPage(strokes: 50);
      expect(identical(simplifyForPreview(page, 1.0), page), isTrue);
    });

    test('degenerate scales are a no-op', () {
      final page = sketchPage(strokes: 10);
      expect(identical(simplifyForPreview(page, 0), page), isTrue);
      expect(identical(simplifyForPreview(page, -1), page), isTrue);
      expect(identical(simplifyForPreview(page, double.nan), page), isTrue);
      expect(identical(simplifyForPreview(page, double.infinity), page), isTrue);
    });
  });

  group('previews drop sub-pixel detail', () {
    test('a sketch page in a grid tile keeps a small fraction of its points',
        () {
      final page = sketchPage();
      final simplified =
          simplifyForPreview(page, devicePixelsPerUnit(page, kTile, kDpr));

      expect(identical(simplified, page), isFalse);
      expect(pointCount(simplified), lessThan(pointCount(page) ~/ 5));
    });

    test('stroke count, ids, z-order and endpoints survive', () {
      final page = sketchPage(strokes: 30);
      final simplified =
          simplifyForPreview(page, devicePixelsPerUnit(page, kTile, kDpr));

      final before = page.layers.content.whereType<StrokeElement>().toList();
      final after =
          simplified.layers.content.whereType<StrokeElement>().toList();
      expect(after.length, before.length);
      for (var i = 0; i < before.length; i++) {
        expect(after[i].id, before[i].id);
        expect(after[i].zIndex, before[i].zIndex);
        expect(after[i].data.points.first, before[i].data.points.first);
        expect(after[i].data.points.last, before[i].data.points.last);
        expect(after[i].data.points.length,
            lessThanOrEqualTo(before[i].data.points.length));
        // Width is never touched — imposing a minimum on-screen width to
        // compensate for lost sub-pixel coverage measured far worse.
        expect(after[i].data.baseWidth, before[i].data.baseWidth);
      }
    });

    test('non-stroke elements pass through untouched', () {
      const text = ContentElement.text(
        id: 't1',
        zIndex: 999,
        data: const TextData(
            x: 10, y: 20, width: 200, height: 40, content: 'hello'),
      );
      final page = sketchPage(strokes: 20, extra: [text]);
      final simplified =
          simplifyForPreview(page, devicePixelsPerUnit(page, kTile, kDpr));

      final passed =
          simplified.layers.content.whereType<TextElement>().single;
      expect(identical(passed, text), isTrue);
    });

    test('result is memoised per page + scale', () {
      final page = sketchPage(strokes: 20);
      final dpu = devicePixelsPerUnit(page, kTile, kDpr);
      expect(identical(simplifyForPreview(page, dpu),
          simplifyForPreview(page, dpu)), isTrue);
    });

    test('the rendered preview still looks the same', () async {
      final page = sketchPage(strokes: 800);
      final simplified =
          simplifyForPreview(page, devicePixelsPerUnit(page, kTile, kDpr));

      final error = meanPixelError(
        await raster(page, kTile, kDpr),
        await raster(simplified, kTile, kDpr),
      );
      // Measured ~3/255 (about 1%): simplified ink is a touch lighter,
      // because some of its darkness came from overlapping sub-pixel
      // segments. Well under a visible difference at tile size.
      expect(error, lessThan(8.0));
    });
  });
}
