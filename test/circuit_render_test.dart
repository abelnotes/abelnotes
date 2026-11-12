// Renders fixture circuits before and after the tidy-up with the app's own
// stroke renderer, to judge the redrawn symbols by eye. Skips unless
// ABELNOTES_CIRCUIT_RENDER names an output folder; fixtures default to the
// synthetic ones in test/fixtures/circuits.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_recognizer_service.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_strokes.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/detector.dart';
import 'package:abelnotes/features/canvas/data/ink_recognizer/model_file.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final out = env['ABELNOTES_CIRCUIT_RENDER'];
  final model = env['ABELNOTES_CIRCUIT_MODEL'] ?? 'assets/models/circuit_detector.ablm';
  final dir = env['ABELNOTES_CIRCUIT_FIXTURES'] ?? 'test/fixtures/circuits';
  final penWidth = double.parse(env['ABELNOTES_CIRCUIT_PEN'] ?? '1.5');
  final scale = double.parse(env['ABELNOTES_CIRCUIT_SCALE'] ?? '4');

  test('render tidied circuits', () async {
    final det = CircuitDetector.fromModelFile(ModelFile.parse(File(model).readAsBytesSync()));
    Directory(out!).createSync(recursive: true);
    final files = Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final strokes = [
        for (final s in j['strokes'] as List) Float64List.fromList([for (final v in s as List) (v as num).toDouble()])
      ];
      final result = CircuitRecognizer.run(det, strokes, (j['pageWidth'] as num).toDouble());
      final pen = [for (final s in strokes) StrokeData(points: _penPoints(s), baseWidth: penWidth)];
      if (result.removed.isEmpty) continue;
      final fallback = pen[result.removed.first];
      final added = circuitStrokes(result, [for (final src in result.sources) src >= 0 ? pen[src] : fallback]);
      final after = [
        for (var i = 0; i < pen.length; i++)
          if (!result.removed.contains(i)) pen[i],
        ...added,
      ];
      final name = f.uri.pathSegments.last.replaceAll('.json', '');
      // ignore: avoid_print
      print('$name R ${result.rlen.toStringAsFixed(1)} line ${added.firstWhere((s) => s.toolType == kTechnicalTool).baseWidth.toStringAsFixed(2)}');
      File('$out/$name.png').writeAsBytesSync(await _sideBySide(pen, after, scale));
    }
  }, skip: out == null ? 'set ABELNOTES_CIRCUIT_RENDER' : false, timeout: Timeout.none);
}

List<StrokePoint> _penPoints(Float64List flat) => [
      for (var i = 0; i + 1 < flat.length; i += 2) StrokePoint(x: flat[i], y: flat[i + 1], timestamp: i * 4),
    ];

/// The two drawings next to each other, [scale] px per page unit.
Future<Uint8List> _sideBySide(List<StrokeData> before, List<StrokeData> after, double scale) async {
  var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
  for (final s in [...before, ...after]) {
    for (final p in s.points) {
      x0 = min(x0, p.x);
      y0 = min(y0, p.y);
      x1 = max(x1, p.x);
      y1 = max(y1, p.y);
    }
  }
  const pad = 10.0;
  final w = (x1 - x0 + 2 * pad) * scale, h = (y1 - y0 + 2 * pad) * scale;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (final (k, strokes) in [before, after].indexed) {
    final page = PageData(
      pageId: 'p',
      pageNumber: 1,
      width: x1 + pad,
      height: y1 + pad,
      layers: RenderingLayers(
        background: const BackgroundLayer(type: 'blank'),
        content: [
          for (final (i, s) in strokes.indexed) ContentElement.stroke(id: '$i', zIndex: i, data: s),
        ],
      ),
      createdAt: DateTime(2026),
      modifiedAt: DateTime(2026),
    );
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(k * w, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(k * w, 0, w, h), Paint()..color = Colors.white);
    CanvasRenderEngine(pageData: page)
        .paintPage(canvas, Size(w, h), scale, Offset(k * w - (x0 - pad) * scale, -(y0 - pad) * scale));
    canvas.restore();
  }
  final image = await recorder.endRecording().toImage((2 * w).ceil(), h.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
