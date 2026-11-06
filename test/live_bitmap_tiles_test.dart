// The web page bitmap is made of tiles anchored to the page: what it shows
// must match the vector drawing, panning must keep the tiles, and merging new
// strokes must rebuild only the tiles they touch.

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/features/canvas/data/zoom_snapshot.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

const _size = Size(400, 600);
const _dpr = 2.0;
// Off-page pen sample: marks the pen as down without drawing anything visible.
const _penDown = [StrokePoint(x: -5000, y: -5000)];

ContentElement _stroke(Random rnd, int i, {double? x, double? y}) {
  final cx = x ?? 20 + rnd.nextDouble() * 360, cy = y ?? 20 + rnd.nextDouble() * 560;
  return ContentElement.stroke(
    id: 's$i',
    zIndex: i,
    data: StrokeData(
      baseWidth: 1.5 + rnd.nextDouble() * 2,
      color: 0xFF000000 | rnd.nextInt(0xFFFFFF),
      points: [
        for (var j = 0; j < 60; j++)
          StrokePoint(
            x: cx + 25 * sin(j / 6 + i),
            y: cy + j * 0.6 + 8 * cos(j / 4),
            pressure: 0.3 + 0.5 * (j % 7) / 7,
          ),
      ],
    ),
  );
}

PageData _page(List<ContentElement> content) => PageData(
      pageId: 'p',
      pageNumber: 0,
      width: 400,
      height: 600,
      layers: RenderingLayers(content: content),
    );

Future<Uint8List> _render(PageData page,
    {ZoomSnapshot? snap,
    required double zoom,
    required Offset pan,
    bool pen = true}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)..scale(_dpr);
  CanvasRenderEngine(
    pageData: page,
    zoom: zoom,
    panOffset: pan,
    devicePixelRatio: _dpr,
    zoomSnapshot: snap,
    activeStroke: pen ? _penDown : null,
  ).paint(canvas, _size);
  final img = rec.endRecording().toImageSync(
      (_size.width * _dpr).toInt(), (_size.height * _dpr).toInt());
  final bytes = (await img.toByteData())!.buffer.asUint8List();
  img.dispose();
  return bytes;
}

/// Share of channel values that differ by more than [tol].
double _diff(Uint8List a, Uint8List b, {int tol = 8}) {
  var bad = 0;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > tol) bad++;
  }
  return bad / a.length;
}

void main() {
  // Pan chosen so the page corner lands on a whole device pixel: tiles and
  // vector then rasterise the same pixels.
  const zoom = 1.3;
  const pan = Offset(5.7, 5.7);

  test('tiles show what the vector drawing shows, and survive a pan', () async {
    final rnd = Random(7);
    final page = _page([for (var i = 0; i < 40; i++) _stroke(rnd, i)]);
    final snap = ZoomSnapshot();
    final vector = await _render(page, zoom: zoom, pan: pan);
    final tiled = await _render(page, snap: snap, zoom: zoom, pan: pan);
    expect(snap.liveTiles, isNotEmpty, reason: 'busy page with the pen down');
    expect(_diff(vector, tiled), lessThan(0.001));

    final before = Map.of(snap.liveTiles);
    const panned = Offset(5.7 - 64, 5.7 - 32); // whole device pixels
    final v2 = await _render(page, zoom: zoom, pan: panned);
    final t2 = await _render(page, snap: snap, zoom: zoom, pan: panned);
    expect(_diff(v2, t2), lessThan(0.001));
    final kept = before.entries.where((e) => identical(snap.liveTiles[e.key], e.value));
    expect(kept, isNotEmpty, reason: 'panning reuses the tiles still on screen');
    snap.dispose();
  });

  test('new strokes draw over the tiles, then merge only where they land', () async {
    final rnd = Random(11);
    final base = [for (var i = 0; i < 40; i++) _stroke(rnd, i)];
    final snap = ZoomSnapshot();
    await _render(_page(base), snap: snap, zoom: zoom, pan: pan);
    final before = Map.of(snap.liveTiles);
    expect(before.length, greaterThan(4));

    // A few strokes in the top-left corner: drawn over the tiles, not merged.
    final added = [
      for (var i = 0; i < 3; i++) _stroke(rnd, 100 + i, x: 40 + i * 5.0, y: 40),
    ];
    var page = _page([...base, ...added]);
    expect(_diff(await _render(page, zoom: zoom, pan: pan),
            await _render(page, snap: snap, zoom: zoom, pan: pan)),
        lessThan(0.001));

    // More than the overlay limit: merged into the tiles under them only.
    final more = [
      for (var i = 0; i < 9; i++) _stroke(rnd, 200 + i, x: 50 + i * 4.0, y: 50),
    ];
    page = _page([...base, ...added, ...more]);
    final tiled = await _render(page, snap: snap, zoom: zoom, pan: pan);
    expect(identical(snap.livePage, page), isTrue, reason: 'merged');
    expect(_diff(await _render(page, zoom: zoom, pan: pan), tiled),
        lessThan(0.001));
    final changed = before.keys.where((k) => !identical(snap.liveTiles[k], before[k]));
    expect(changed, isNotEmpty);
    expect(changed.length, lessThan(before.length), reason: 'only touched tiles');
    snap.dispose();
  });

  test('an erase drops the tiles and the next paint rebuilds them', () async {
    final rnd = Random(3);
    final base = [for (var i = 0; i < 40; i++) _stroke(rnd, i)];
    final snap = ZoomSnapshot();
    await _render(_page(base), snap: snap, zoom: zoom, pan: pan);
    final page = _page(base.sublist(1));
    final tiled = await _render(page, snap: snap, zoom: zoom, pan: pan);
    expect(identical(snap.livePage, page), isTrue);
    expect(_diff(await _render(page, zoom: zoom, pan: pan), tiled),
        lessThan(0.001));
    snap.dispose();
  });

  test('a resting view gets its tiles even while frames keep coming', () async {
    final rnd = Random(9);
    final page = _page([for (var i = 0; i < 40; i++) _stroke(rnd, i)]);
    final snap = ZoomSnapshot();
    // Frames every 50 ms with the pen up, as an animation elsewhere would cause.
    for (var i = 0; i < 10 && snap.liveTiles.isEmpty; i++) {
      await _render(page, snap: snap, zoom: zoom, pan: pan, pen: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await _render(page, snap: snap, zoom: zoom, pan: pan, pen: false);
    expect(snap.liveTiles, isNotEmpty, reason: 'built before the next stroke');
    snap.dispose();
  });
}
