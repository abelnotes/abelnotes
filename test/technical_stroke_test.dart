// Technical strokes (tidied circuits): solid where the fill tool asks for it,
// hollow otherwise, on the page and in page previews alike.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

StrokeData _square(String tool, double left) => StrokeData(
      toolType: tool,
      baseWidth: 1,
      points: [
        for (final (dx, dy) in const [(0, 0), (20, 0), (20, 20), (0, 20), (0, 0)])
          StrokePoint(x: left + dx, y: 10.0 + dy),
      ],
    );

PageData _page() => PageData(
      pageId: 'p',
      pageNumber: 0,
      width: 100,
      height: 40,
      layers: RenderingLayers(
        background: const BackgroundLayer(type: 'blank'),
        content: [
          ContentElement.stroke(id: 'fill', zIndex: 0, data: _square(kTechnicalFillTool, 10)),
          ContentElement.stroke(id: 'body', zIndex: 1, data: _square(kTechnicalBodyTool, 60)),
        ],
      ),
    );

Future<ByteData> _render(void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 40);
  picture.dispose();
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  return bytes;
}

/// Red channel at (x, y): 255 on white paper, near 0 on black ink.
int _red(ByteData px, int x, int y) => px.getUint8((y * 100 + x) * 4);

void main() {
  setUp(CanvasRenderEngine.disposeStaticCache);

  test('the fill variant is solid, outlines stay hollow', () async {
    final px = await _render((c) => CanvasRenderEngine(pageData: _page())
        .paintPage(c, const Size(100, 40), 1, Offset.zero));
    expect(_red(px, 20, 20), lessThan(64), reason: 'inside the filled square');
    expect(_red(px, 70, 20), greaterThan(192), reason: 'inside the outline');
    expect(_red(px, 60, 20), lessThan(128), reason: 'on the outline');
  });

  test('page previews draw technical strokes with the full painter', () async {
    final px = await _render((c) => CanvasRenderEngine(pageData: _page(), previewStrokes: true)
        .paint(c, const Size(100, 40)));
    expect(_red(px, 20, 20), lessThan(64));
    expect(_red(px, 70, 20), greaterThan(192));
  });

  test('the type helper knows all three tools and nothing else', () {
    expect([kTechnicalTool, kTechnicalBodyTool, kTechnicalFillTool].every(isTechnicalTool), isTrue);
    expect(isTechnicalTool('pen'), isFalse);
    expect(isTechnicalTool('highlighter'), isFalse);
  });
}
