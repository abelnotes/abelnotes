import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/thumbnail_service.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

PageData _page(List<ContentElement> content) => PageData(
      pageId: 'p',
      pageNumber: 1,
      width: 6000,
      height: 6000,
      layers: RenderingLayers(content: content),
    );

void main() {
  test('sketch thumbnails frame what is drawn, not the whole sheet', () {
    expect(ThumbnailService.contentBounds(_page(const [])), isNull);
    final b = ThumbnailService.contentBounds(_page(const [
      ContentElement.stroke(
          id: 's',
          zIndex: 0,
          data: StrokeData(baseWidth: 2, points: [
            StrokePoint(x: 2800, y: 3000),
            StrokePoint(x: 3100, y: 3050),
          ])),
      ContentElement.shape(
          id: 'h',
          zIndex: 1,
          data: ShapeData(
              shapeType: 'rectangle', x1: 3200, y1: 2900, x2: 3000, y2: 3300)),
    ]))!;
    expect(b, const Rect.fromLTRB(2798, 2900, 3200, 3300));
  });

  test('a tall sketch shows its start, zoomed; a small one stays whole', () {
    final tall = ThumbnailService.sketchFrame(
        const Rect.fromLTRB(1500, 1900, 2450, 4100), 1.5);
    expect(tall.width, 900);
    expect(tall.height, 600);
    expect(tall.topLeft, const Offset(1470, 1870));
    final small = ThumbnailService.sketchFrame(
        const Rect.fromLTRB(3000, 3000, 3100, 3040), 1.5);
    expect(small.center, const Offset(3050, 3020));
    expect(small.width / small.height, closeTo(1.5, 1e-9));
  });
}
