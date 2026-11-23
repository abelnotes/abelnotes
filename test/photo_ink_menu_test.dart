// "Convert to ink" in a picture's menu: the picture is swapped for strokes
// over its box, and one undo brings the picture back.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/editor_harness.dart';

/// A white picture with a few handwriting-like loops and bars in blue.
Uint8List _notesPng() {
  final im = img.Image(width: 800, height: 400);
  img.fill(im, color: img.ColorRgb8(248, 248, 245));
  final ink = img.ColorRgb8(30, 50, 150);
  for (var k = 0; k < 8; k++) {
    final cx = 80.0 + k * 85, cy = 200.0;
    if (k.isEven) {
      for (var t = 0; t < 36; t++) {
        final a0 = t / 36 * 2 * math.pi, a1 = (t + 1) / 36 * 2 * math.pi;
        img.drawLine(im,
            x1: (cx + 25 * math.cos(a0)).round(), y1: (cy + 25 * math.sin(a0)).round(),
            x2: (cx + 25 * math.cos(a1)).round(), y2: (cy + 25 * math.sin(a1)).round(),
            color: ink, thickness: 5, antialias: true);
      }
    } else {
      img.drawLine(im, x1: cx.round(), y1: 140, x2: cx.round(), y2: 230, color: ink, thickness: 5, antialias: true);
    }
  }
  return img.encodePng(im);
}

void main() {
  testEditor('Convert to ink swaps the picture for strokes; undo restores it', (h) async {
    h.notifier.addImageElement(const Offset(50, 80), 'notes.png', _notesPng(), 400, 200);
    await h.tester.pump();
    final id = h.content.whereType<ImageElement>().single.id;
    h.notifier.selectElement(id);
    await h.tester.pump();

    await h.tester.tap(find.byIcon(Icons.more_vert_rounded));
    await h.tester.pump();
    await h.tester.pump(const Duration(seconds: 1));
    await h.tester.tap(find.text('Convert to ink'));
    await h.tester.pump(const Duration(milliseconds: 100));
    // Decoding and tracing run outside the fake clock.
    for (var i = 0; i < 100 && h.strokeCount == 0; i++) {
      await h.tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await h.tester.pump();
    }

    expect(h.content.whereType<ImageElement>(), isEmpty);
    final strokes = h.content.whereType<StrokeElement>().toList();
    expect(strokes.length, inInclusiveRange(4, 40));
    // All inside the picture's box, in the blue pen.
    for (final s in strokes) {
      expect(s.data.color, 0xFF1F4FC1);
      for (final p in s.data.points) {
        expect(p.x, inInclusiveRange(48, 452));
        expect(p.y, inInclusiveRange(78, 282));
      }
    }

    h.notifier.undo();
    await h.tester.pump();
    expect(h.content.whereType<ImageElement>().single.id, id);
    expect(h.strokeCount, 0);
    await h.tester.pump(const Duration(seconds: 2));
  });
}
