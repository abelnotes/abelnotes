// Tidy-up for a circuit pasted as a picture: the image is traced into
// strokes, those go through the circuit pipeline, and the result lands
// where the image was, over what is left of the picture.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'circuit_recognizer_service.dart';
import 'circuit_strokes.dart';
import 'image_ink.dart';
import 'raster.dart';

/// A picture's circuit redrawn: [strokes] for the parts and wires, and
/// [rest] (PNG and placement), what is left of the picture (labels, notes)
/// on a clear background, to lie under them.
typedef ImageCircuit = ({List<StrokeData> strokes, ({Uint8List png, ImageData data})? rest});

/// The circuit in image [d] (file [bytes]) redrawn, or null when nothing in
/// it reads as a circuit; the string says why, for the log.
Future<(ImageCircuit?, String)> imageCircuitStrokes(CircuitRecognizer recognizer, Uint8List bytes, ImageData d) async {
  final watch = Stopwatch()..start();
  final pixels = await _decode(bytes);
  if (pixels == null) return (null, 'image not decoded');
  final (rgba, w, h) = pixels;
  final tDecode = watch.elapsedMilliseconds;
  final (ink, mask) = await compute(_trace, pixels);
  final tTrace = watch.elapsedMilliseconds;
  if (ink.isEmpty) return (null, 'no ink in image');
  // Recognised in image pixels with the image as the page: the circuit
  // fills the detector's input wherever and however small it sits.
  final result = await recognizer.recognize([
    for (final t in ink)
      StrokeData(
        points: [for (var i = 0; i + 1 < t.points.length; i += 2) StrokePoint(x: t.points[i], y: t.points[i + 1])],
        toolType: kTechnicalTool,
      )
  ], w.toDouble(), ink: mask);
  if (!result.ok || result.removed.isEmpty) return (null, result.error ?? 'nothing recognised');

  final sx = d.width / w, sy = d.height / h, scale = (sx + sy) / 2;
  final cosR = math.cos(d.rotation), sinR = math.sin(d.rotation);
  Float64List toPage(Float64List flat) {
    final out = Float64List(flat.length);
    for (var i = 0; i + 1 < flat.length; i += 2) {
      // Flip and rotation act about the image's centre, as when it is drawn.
      final lx = ((d.flipHorizontal ? w - flat[i] : flat[i]) - w / 2) * sx;
      final ly = (flat[i + 1] - h / 2) * sy;
      out[i] = d.x + d.width / 2 + lx * cosR - ly * sinR;
      out[i + 1] = d.y + d.height / 2 + lx * sinR + ly * cosR;
    }
    return out;
  }

  final now = DateTime.now();
  StrokeData traceStyle(TracedStroke t, Float64List page) => StrokeData(
        points: technicalPoints(page),
        toolType: kTechnicalTool,
        color: t.color,
        baseWidth: t.width * scale,
        opacity: d.opacity,
        timestamp: now,
      );
  final pageInk = [for (final t in ink) toPage(t.points)];
  final styles = [for (var i = 0; i < ink.length; i++) traceStyle(ink[i], pageInk[i])];
  final onPage = CircuitResult(
    result.removed,
    [for (final a in result.added) toPage(a)],
    result.sources,
    result.components,
    result.milliseconds,
    null,
    kinds: result.kinds,
    rlen: result.rlen * scale,
  );
  final fallback = styles[result.removed.first];
  final drawn = circuitStrokes(onPage, [for (final src in result.sources) src >= 0 ? styles[src] : fallback]);
  final tRecognise = watch.elapsedMilliseconds;
  final left = await compute(_leftover, (rgba, w, h, [for (final i in result.removed) (ink[i].points, ink[i].width)]));
  final why = '${result.components} components from ${ink.length} traced lines; decode $tDecode, trace '
      '${tTrace - tDecode}, recognise ${tRecognise - tTrace}, leftover ${watch.elapsedMilliseconds - tRecognise} ms';
  if (left == null) return ((strokes: drawn, rest: null), why);
  // The leftover's centre, carried through flip and rotation like the image.
  final (premul, x0, y0, cw, ch) = left;
  final png = await _encodePng(premul, cw, ch);
  final lx = ((d.flipHorizontal ? w - x0 - cw / 2 : x0 + cw / 2) - w / 2) * sx;
  final ly = (y0 + ch / 2 - h / 2) * sy;
  final cx = d.x + d.width / 2 + lx * cosR - ly * sinR, cy = d.y + d.height / 2 + lx * sinR + ly * cosR;
  final rest = d.copyWith(x: cx - cw * sx / 2, y: cy - ch * sy / 2, width: cw * sx, height: ch * sy, comment: null);
  return ((strokes: drawn, rest: (png: png, data: rest)), why);
}

/// RGBA (straight alpha) through the engine's own decoder; package:image
/// only where that fails (it is ten times slower on a photo).
Future<(Uint8List, int, int)?> _decode(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final w = image.width, h = image.height;
    image.dispose();
    codec.dispose();
    if (data != null) return (data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), w, h);
  } catch (_) {
    // Fall through to the Dart decoder.
  }
  return compute(_decodeDart, bytes);
}

(Uint8List, int, int)? _decodeDart(Uint8List bytes) {
  final im = img.decodeImage(bytes)?.convert(numChannels: 4);
  return im == null ? null : (im.getBytes(order: img.ChannelOrder.rgba), im.width, im.height);
}

(Uint8List, int, int, int, int)? _leftover((Uint8List, int, int, List<(Float64List, double)>) job) {
  final (rgba, w, h, cut) = job;
  final left = inkLeftover(rgba, w, h, cut);
  if (left == null) return null;
  final (out, x0, y0, cw, ch) = left;
  // The engine takes premultiplied pixels.
  for (var i = 0; i < out.length; i += 4) {
    final a = out[i + 3];
    if (a == 255) continue;
    for (var c = 0; c < 3; c++) {
      out[i + c] = (out[i + c] * a + 127) ~/ 255;
    }
  }
  return (out, x0, y0, cw, ch);
}

/// PNG through the engine's encoder, off the UI thread (Dart's took 0.6 s on
/// a photo); package:image where that fails.
Future<Uint8List> _encodePng(Uint8List premul, int w, int h) async {
  try {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(premul, w, h, ui.PixelFormat.rgba8888, done.complete);
    final image = await done.future;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data != null) return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    // Fall through to the Dart encoder.
  }
  return img.encodePng(img.Image.fromBytes(width: w, height: h, bytes: premul.buffer, numChannels: 4),
      level: 1, filter: img.PngFilter.none);
}

(List<TracedStroke>, InkMask) _trace((Uint8List, int, int) pixels) {
  final t = traceImage(pixels.$1, pixels.$2, pixels.$3);
  return (t.strokes, t.ink);
}
