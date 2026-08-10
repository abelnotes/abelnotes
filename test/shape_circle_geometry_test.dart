// Regression: a 'circle' ShapeData had THREE different geometries in the
// codebase. The painter drew radius = (x2-x1)/2, while the eraser sampler
// (_shapeToSampledEdges) and the tap hit-test (_distToShapeOutline) probed
// radius = hypot(x2-x1, y2-y1)/2 — ~1.41× bigger on the square bbox shape
// recognition emits. The hit outline therefore sat ~40 % outside the ink, so
// putting the eraser on a drawn circle erased nothing.
//
// `shapeEllipseRect` is now the single source of truth. This test pins the
// painter to it: ink must be ON that ellipse and absent where the old
// half-diagonal outline used to be probed.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

const _shape = ShapeData(
  shapeType: 'circle',
  x1: 100,
  y1: 200,
  x2: 300,
  y2: 400,
  strokeColor: 0xFF000000,
  strokeWidth: 4,
);

PageData _pageWithCircle() => const PageData(
      pageId: 'p1',
      pageNumber: 0,
      width: 400,
      height: 600,
      layers: RenderingLayers(
        content: [ContentElement.shape(id: 's1', zIndex: 0, data: _shape)],
      ),
    );

Future<ui.Image> _render() async {
  final recorder = ui.PictureRecorder();
  CanvasRenderEngine(pageData: _pageWithCircle())
      .paint(Canvas(recorder), const Size(400, 600));
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 600);
  picture.dispose();
  return image;
}

/// True if any pixel within [radius] of ([x],[y]) is dark — i.e. the black
/// shape stroke rather than the page background. Searching a small window
/// tolerates the stroke width and antialiasing without pinning exact pixels.
bool _inkedNear(ByteData pixels, int x, int y, {int radius = 4}) {
  for (var dy = -radius; dy <= radius; dy++) {
    for (var dx = -radius; dx <= radius; dx++) {
      final px = x + dx, py = y + dy;
      if (px < 0 || py < 0 || px >= 400 || py >= 600) continue;
      final o = (py * 400 + px) * 4;
      if (pixels.getUint8(o + 3) == 0) continue;
      final lum = (pixels.getUint8(o) +
              pixels.getUint8(o + 1) +
              pixels.getUint8(o + 2)) /
          3;
      if (lum < 100) return true;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('circle shape paints the ellipse inscribed in its bounding box',
      () async {
    final oval = shapeEllipseRect(_shape);
    expect(oval, const Rect.fromLTRB(100, 200, 300, 400));

    final image = await _render();
    final pixels =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();

    final c = oval.center; // (200, 300)
    final rx = oval.width / 2; // 100

    // On the inscribed ellipse: ink.
    expect(_inkedNear(pixels, (c.dx + rx).round(), c.dy.round()), isTrue,
        reason: 'right edge of the inscribed ellipse must be inked');
    expect(_inkedNear(pixels, c.dx.round(), (c.dy - rx).round()), isTrue,
        reason: 'top edge of the inscribed ellipse must be inked');

    // Where the old half-diagonal outline was probed (rx * sqrt2 ≈ 141): blank.
    expect(_inkedNear(pixels, (c.dx + rx * 1.414).round(), c.dy.round()),
        isFalse,
        reason: 'nothing is drawn on the circumscribed circle');

    // Interior of an unfilled circle: blank.
    expect(_inkedNear(pixels, c.dx.round(), c.dy.round(), radius: 2), isFalse,
        reason: 'an unfilled circle has no ink at its centre');
  });

  group('shapeBodyContains', () {
    test('circle body is the inscribed ellipse, not its bbox', () {
      expect(shapeBodyContains(_shape, const Offset(200, 300)), isTrue,
          reason: 'centre');
      expect(shapeBodyContains(_shape, const Offset(295, 300)), isTrue,
          reason: 'just inside the right edge');
      expect(shapeBodyContains(_shape, const Offset(305, 300)), isFalse,
          reason: 'just outside the right edge');
      expect(shapeBodyContains(_shape, const Offset(105, 205)), isFalse,
          reason: 'bbox corner is outside the ellipse');
    });

    test('a line has no body to fill', () {
      const line = ShapeData(
        shapeType: 'line',
        x1: 0,
        y1: 0,
        x2: 100,
        y2: 100,
        strokeColor: 0xFF000000,
        strokeWidth: 2,
      );
      expect(shapeBodyContains(line, const Offset(50, 50)), isFalse);
    });

    test('rotation is undone before the containment test', () {
      const square = ShapeData(
        shapeType: 'rectangle',
        x1: 0,
        y1: 0,
        x2: 100,
        y2: 20,
        strokeColor: 0xFF000000,
        strokeWidth: 2,
        rotation: 1.5707963267948966, // 90°, so the bar stands upright
      );
      // Upright, the bar spans x∈[40,60], y∈[-40,60] around centre (50,10).
      expect(shapeBodyContains(square, const Offset(50, 55)), isTrue);
      expect(shapeBodyContains(square, const Offset(90, 10)), isFalse);
    });

    test('circleDragBox keeps the shape tool drawing circles, not ellipses',
        () {
      // A deliberately non-square drag: 200 wide, 60 tall.
      final box = circleDragBox(const Offset(100, 200), const Offset(300, 260));
      expect(box.width, box.height, reason: 'the stored box must be square');
      expect(box.width, 200, reason: 'diameter comes from the drag WIDTH');
      expect(box.center, const Offset(200, 230),
          reason: 'centred on the drag, as the old painter drew it');

      // Backwards drags describe the same circle.
      expect(circleDragBox(const Offset(300, 260), const Offset(100, 200)),
          box);

      // Recognition already emits a square bbox — unchanged by squaring.
      expect(circleDragBox(const Offset(100, 200), const Offset(300, 400)),
          const Rect.fromLTRB(100, 200, 300, 400));
    });

    test('triangle body excludes the bbox corners beside the apex', () {
      const tri = ShapeData(
        shapeType: 'triangle',
        x1: 0,
        y1: 0,
        x2: 100,
        y2: 100,
        strokeColor: 0xFF000000,
        strokeWidth: 2,
      );
      expect(shapeBodyContains(tri, const Offset(50, 80)), isTrue);
      expect(shapeBodyContains(tri, const Offset(5, 5)), isFalse);
    });
  });
}
