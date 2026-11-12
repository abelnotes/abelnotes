// The native engine (packages/circuit_engine) against the Dart detector and
// picture passes: same output, and how much faster. Skips without the built
// library (see that package's README). Pictures: a synthetic schematic, plus
// any listed in ABELNOTES_ENGINE_IMAGES (comma separated).
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/detector.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/image_ink.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/native_engine.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/raster.dart';
import 'package:abelnotes/features/canvas/data/ink_recognizer/model_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A synthetic printed schematic: wires, a zigzag, two plates and a ring.
img.Image _schematic() {
  final im = img.Image(width: 640, height: 480, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));
  final ink = img.ColorRgba8(0, 0, 0, 255);
  void line(int x0, int y0, int x1, int y1) => img.drawLine(im, x1: x0, y1: y0, x2: x1, y2: y1, color: ink, thickness: 2);
  line(80, 80, 240, 80);
  for (var i = 0; i < 6; i++) {
    line(240 + 20 * i, i.isEven ? 80 : 65, 260 + 20 * i, i.isEven ? 65 : 95);
  }
  line(360, 80, 560, 80);
  line(560, 80, 560, 220);
  line(530, 220, 590, 220);
  line(530, 240, 590, 240);
  line(560, 240, 560, 400);
  line(560, 400, 80, 400);
  line(80, 400, 80, 280);
  img.drawCircle(im, x: 80, y: 240, radius: 40, color: ink);
  line(80, 200, 80, 80);
  return im;
}

void main() {
  final env = Platform.environment;
  final model = env['ABELNOTES_CIRCUIT_MODEL'] ?? 'assets/models/circuit_detector.ablm';
  final present = File(model).existsSync() && NativeEngine.open() != null;

  test('native engine matches the Dart forward pass', () {
    final det = CircuitDetector.fromModelFile(ModelFile.parse(File(model).readAsBytesSync()));
    final rng = Random(7);
    // A synthetic page: ink lines on paper, at two raster sizes.
    for (final (h, w) in [(320, 224), (640, 928)]) {
      final img = Float32List(h * w)..fillRange(0, h * w, 1);
      for (var k = 0; k < 60; k++) {
        final y = rng.nextInt(h), x0 = rng.nextInt(w - 40);
        for (var x = x0; x < x0 + 40; x++) {
          img[y * w + x] = 0;
        }
      }
      det.profile = <String, int>{};
      final watch = Stopwatch()..start();
      final dart = det.forward(img, h, w);
      final tDart = watch.elapsedMilliseconds;
      det.profile = null;
      watch.reset();
      det.forward(img, h, w); // builds the native graph
      final tFirst = watch.elapsedMilliseconds;
      watch.reset();
      final native = det.forward(img, h, w);
      final tNative = watch.elapsedMilliseconds;
      expect(native.length, dart.length);
      var worst = 0.0;
      for (var i = 0; i < dart.length; i++) {
        worst = max(worst, (dart[i] - native[i]).abs() / max(1.0, dart[i].abs()));
      }
      // ignore: avoid_print
      print('${w}x$h dart $tDart ms, native $tNative ms (first $tFirst), worst rel diff ${worst.toStringAsExponential(2)}');
      expect(worst, lessThan(1e-3));
    }
  }, skip: present ? false : 'model or native engine missing', timeout: Timeout.none);

  test('same detections on a traced picture', () {
    final path = env['ABELNOTES_ENGINE_IMAGE'];
    final det = CircuitDetector.fromModelFile(ModelFile.parse(File(model).readAsBytesSync()));
    final im = path == null ? _schematic() : img.decodeImage(File(path).readAsBytesSync())!.convert(numChannels: 4);
    final t = traceImage(im.getBytes(order: img.ChannelOrder.rgba), im.width, im.height);
    final r = rasterizeInk(t.ink, [for (final s in t.strokes) s.points], im.width.toDouble());
    det.profile = <String, int>{};
    final a = det.detect(r.data, r.height, r.width);
    det.profile = null;
    final watch = Stopwatch()..start();
    final b = det.detect(r.data, r.height, r.width);
    // ignore: avoid_print
    print('${r.width}x${r.height}: ${a.length} vs ${b.length} detections, native ${watch.elapsedMilliseconds} ms');
    expect(b.map((d) => '${d.cls} ${d.x0.round()} ${d.y0.round()}').toList(),
        a.map((d) => '${d.cls} ${d.x0.round()} ${d.y0.round()}').toList());
  }, skip: present ? false : 'model or native engine missing', timeout: Timeout.none);

  test('picture passes: native and Dart trace and cut the same', () {
    final dir = env['ABELNOTES_ENGINE_IMAGES'];
    if (NativeImage.open() == null) return;
    for (final path in [null, ...?dir?.split(',')]) {
      final im = path == null ? _schematic() : img.decodeImage(File(path).readAsBytesSync())!.convert(numChannels: 4);
      final rgba = im.getBytes(order: img.ChannelOrder.rgba);
      NativeImage.forceDart = true;
      final w = Stopwatch()..start();
      final a = traceImage(rgba, im.width, im.height);
      final tDart = w.elapsedMilliseconds;
      final cut = [for (final s in a.strokes.take(a.strokes.length ~/ 2)) (s.points, s.width)];
      w.reset();
      final la = inkLeftover(rgba, im.width, im.height, cut);
      final lDart = w.elapsedMilliseconds;
      NativeImage.forceDart = false;
      w.reset();
      final b = traceImage(rgba, im.width, im.height);
      final tNative = w.elapsedMilliseconds;
      w.reset();
      final lb = inkLeftover(rgba, im.width, im.height, cut);
      final lNative = w.elapsedMilliseconds;
      // ignore: avoid_print
      print('${path?.split('/').last ?? 'schematic'}: trace dart $tDart native $tNative ms, leftover dart $lDart native $lNative ms');
      expect(b.ink.data, a.ink.data);
      expect(b.strokes.length, a.strokes.length);
      for (var i = 0; i < a.strokes.length; i++) {
        expect(b.strokes[i].points, a.strokes[i].points);
        expect(b.strokes[i].width, a.strokes[i].width);
        expect(b.strokes[i].color, a.strokes[i].color);
      }
      final r = rasterize([for (final s in a.strokes) s.points], im.width.toDouble());
      NativeImage.forceDart = true;
      final ra = rasterizeInk(a.ink, [for (final s in a.strokes) s.points], im.width.toDouble());
      NativeImage.forceDart = false;
      final rb = rasterizeInk(b.ink, [for (final s in b.strokes) s.points], im.width.toDouble());
      expect(rb.data, ra.data);
      expect(r.width, ra.width);
      expect(lb?.$2, la?.$2);
      expect(lb?.$4, la?.$4);
      expect(lb?.$1, la?.$1);
    }
  }, skip: present ? false : 'model or native engine missing', timeout: Timeout.none);
}
