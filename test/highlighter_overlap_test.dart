// Highlighter strokes of one colour read as a single mark where they cross
// (#37), on the vector drawing and on the tiles, and never hide the ink.

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/features/canvas/data/zoom_snapshot.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

const _w = 400, _h = 600;
const _penDown = [StrokePoint(x: -5000, y: -5000)];
const _yellow = 0xFFFFD60A, _pink = 0xFFFF4FA3;

ContentElement _line(String id, int z, Offset a, Offset b,
        {int color = _yellow, bool highlighter = true, double width = 20}) =>
    ContentElement.stroke(
      id: id,
      zIndex: z,
      data: StrokeData(
        toolType: highlighter ? 'highlighter' : 'pen',
        isHighlighter: highlighter,
        color: color,
        baseWidth: width,
        points: [
          for (var j = 0; j <= 40; j++)
            StrokePoint(
                x: a.dx + (b.dx - a.dx) * j / 40, y: a.dy + (b.dy - a.dy) * j / 40),
        ],
      ),
    );

PageData _page(List<ContentElement> content) => PageData(
      pageId: 'p',
      pageNumber: 0,
      width: _w.toDouble(),
      height: _h.toDouble(),
      layers: RenderingLayers(
          background: const BackgroundLayer(type: 'blank'), content: content),
    );

Future<Uint8List> _render(PageData page, {ZoomSnapshot? snap}) async {
  final rec = ui.PictureRecorder();
  CanvasRenderEngine(
    pageData: page,
    zoom: 1,
    panOffset: Offset.zero,
    devicePixelRatio: 1,
    zoomSnapshot: snap,
    activeStroke: snap != null ? _penDown : null,
  ).paint(Canvas(rec), Size(_w.toDouble(), _h.toDouble()));
  final img = rec.endRecording().toImageSync(_w, _h);
  final bytes = (await img.toByteData())!.buffer.asUint8List();
  img.dispose();
  return bytes;
}

List<int> _px(Uint8List b, int x, int y) {
  final i = (y * _w + x) * 4;
  return [b[i], b[i + 1], b[i + 2]];
}

void _same(List<int> a, List<int> b, {int tol = 2}) {
  for (var c = 0; c < 3; c++) {
    expect((a[c] - b[c]).abs(), lessThanOrEqualTo(tol), reason: '$a vs $b');
  }
}

void main() {
  final cross = [
    _line('h', 1, const Offset(50, 100), const Offset(350, 100)),
    _line('v', 2, const Offset(200, 50), const Offset(200, 300)),
  ];

  test('crossing strokes of one colour do not darken', () async {
    final img = await _render(_page(cross));
    final single = _px(img, 100, 100), both = _px(img, 200, 100);
    expect(single, isNot(equals([255, 255, 255])), reason: 'ink is visible');
    _same(both, single);
    // Same tint as the old 35% wash on white paper.
    final want = Color.alphaBlend(
        const Color(_yellow).withValues(alpha: 0.35), Colors.white);
    _same(single, [
      (want.r * 255).round(),
      (want.g * 255).round(),
      (want.b * 255).round()
    ]);
  });

  test('ink under the highlighter stays dark, colours still mix', () async {
    final img = await _render(_page([
      _line('ink', 0, const Offset(50, 400), const Offset(350, 400),
          color: 0xFF000000, highlighter: false, width: 4),
      _line('hl', 1, const Offset(50, 400), const Offset(350, 400)),
      _line('a', 2, const Offset(50, 500), const Offset(350, 500)),
      _line('b', 3, const Offset(200, 450), const Offset(200, 560),
          color: _pink),
    ]));
    expect(_px(img, 100, 400).every((c) => c < 40), isTrue,
        reason: 'black ink under yellow: ${_px(img, 100, 400)}');
    final mix = _px(img, 200, 500);
    expect(mix, isNot(equals(_px(img, 100, 500))));
    expect(mix, isNot(equals(_px(img, 200, 540))));
  });

  test('tiles match the vector drawing, also after merging new strokes',
      () async {
    final rnd = Random(5);
    final base = [
      for (var i = 0; i < 40; i++)
        _line('s$i', 10 + i, Offset(20 + rnd.nextDouble() * 300, 320 + i * 6.0),
            Offset(60 + rnd.nextDouble() * 300, 330 + i * 6.0),
            color: 0xFF000000, highlighter: false, width: 2),
      ...cross,
    ];
    final snap = ZoomSnapshot();
    var page = _page(base);
    final tiled = await _render(page, snap: snap);
    expect(snap.liveTiles, isNotEmpty);
    _same(_px(tiled, 200, 100), _px(tiled, 100, 100));

    // More highlighter strokes than the overlay holds: merged into old tiles.
    final more = [
      for (var i = 0; i < 12; i++)
        _line('m$i', 100 + i, Offset(60.0 + i * 20, 80),
            Offset(60.0 + i * 20, 200)),
    ];
    page = _page([...base, ...more]);
    final merged = await _render(page, snap: snap);
    expect(identical(snap.livePage, page), isTrue, reason: 'merged');
    final vector = await _render(page);
    var bad = 0;
    for (var i = 0; i < vector.length; i++) {
      if ((vector[i] - merged[i]).abs() > 8) bad++;
    }
    expect(bad / vector.length, lessThan(0.001));
    _same(_px(merged, 80, 100), _px(merged, 100, 150));
    snap.dispose();
  });
}
