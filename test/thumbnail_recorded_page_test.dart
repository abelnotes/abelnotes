// A cover thumbnail replays the canvas's recording of the page when there is
// one: it must look the same as painting the page from scratch.

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/thumbnail_service.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

PageData _page() {
  final rnd = Random(5);
  return PageData(
    pageId: 'p',
    pageNumber: 0,
    width: 1240,
    height: 1754,
    layers: RenderingLayers(
      background: const BackgroundLayer(type: 'grid'),
      content: [
        for (var i = 0; i < 30; i++)
          ContentElement.stroke(
            id: 's$i',
            zIndex: i,
            data: StrokeData(
              baseWidth: 2 + rnd.nextDouble() * 3,
              color: 0xFF000000 | rnd.nextInt(0xFFFFFF),
              points: [
                for (var j = 0; j < 40; j++)
                  StrokePoint(
                    x: 100 + rnd.nextDouble() * 1000 + j * 3,
                    y: 100 + i * 50 + 20 * sin(j / 3),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

Future<ui.Image> _decode(List<int> png) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
  return (await codec.getNextFrame()).image;
}

void main() {
  test('a thumbnail from the canvas recording matches a fresh paint', () async {
    final page = _page();
    final thumbs = ThumbnailService();
    CanvasRenderEngine.disposeStaticCache();
    expect(CanvasRenderEngine.recordedPage(page), isNull);
    final fresh = await thumbs.renderPng(page);

    // The canvas paints the page at its own size and zoom, which records it.
    final rec = ui.PictureRecorder();
    CanvasRenderEngine(pageData: page, zoom: 1.7).paint(Canvas(rec), const Size(900, 1300));
    rec.endRecording().dispose();
    expect(CanvasRenderEngine.recordedPage(page), isNotNull);
    final replayed = await thumbs.renderPng(page);

    final a = (await (await _decode(fresh!)).toByteData())!.buffer.asUint8List();
    final b = (await (await _decode(replayed!)).toByteData())!.buffer.asUint8List();
    var bad = 0;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 24) bad++;
    }
    expect(bad / a.length, lessThan(0.002));
    CanvasRenderEngine.disposeStaticCache();
  });
}
