// Picture tidy-up over a folder of images, for ml/circuits/image_bench.py:
// each image is traced, recognised and rewritten as the app does, and the
// result written as JSON in image pixels. Skips unless ABELNOTES_IMAGE_BENCH
// and ABELNOTES_IMAGE_BENCH_OUT are set; ABELNOTES_IMAGE_DETECT=strokes has
// the detector read the redrawn lines instead of the ink.
import 'dart:convert';
import 'dart:io';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_graph.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/detector.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/image_ink.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/raster.dart';
import 'package:abelnotes/features/canvas/data/ink_recognizer/model_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  final env = Platform.environment;
  final dir = env['ABELNOTES_IMAGE_BENCH'], out = env['ABELNOTES_IMAGE_BENCH_OUT'];
  final model = env['ABELNOTES_CIRCUIT_MODEL'] ?? 'assets/models/circuit_detector.ablm';

  test('pictures through the tidy-up', () {
    final det = CircuitDetector.fromModelFile(ModelFile.parse(File(model).readAsBytesSync()));
    Directory(out!).createSync(recursive: true);
    final files = Directory(dir!)
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'\.(png|jpe?g)$', caseSensitive: false).hasMatch(f.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final im = img.decodeImage(f.readAsBytesSync())!.convert(numChannels: 4);
      final watch = Stopwatch()..start();
      final tr = traceImage(im.getBytes(order: img.ChannelOrder.rgba), im.width, im.height);
      final traced = tr.strokes;
      final tTrace = watch.elapsedMilliseconds;
      final strokes = [for (final t in traced) t.points];
      // ABELNOTES_IMAGE_SCALE shrinks the detector's raster (cost goes as its square).
      final page = im.width / double.parse(env['ABELNOTES_IMAGE_SCALE'] ?? '1');
      final r = env['ABELNOTES_IMAGE_DETECT'] == 'strokes' ? rasterize(strokes, page) : rasterizeInk(tr.ink, strokes, page);
      final dets = det.detect(r.data, r.height, r.width);
      final px = [
        for (final s in strokes) [for (var i = 0; i + 1 < s.length; i += 2) Pt(r.toPxX(s[i]), r.toPxY(s[i + 1]))]
      ];
      final rw = rewriteCircuit(px, dets);
      List<double> box(Detection d) => [r.toPageX(d.x0), r.toPageY(d.y0), r.toPageX(d.x1), r.toPageY(d.y1)];
      final name = f.uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      File('$out/$name.json').writeAsStringSync(jsonEncode({
        'w': im.width,
        'h': im.height,
        'traceMs': tTrace,
        'totalMs': watch.elapsedMilliseconds,
        'traced': [for (final s in strokes) s.map((v) => (v * 10).round() / 10).toList()],
        'widths': [for (final t in traced) (t.width * 10).round() / 10],
        'dets': [for (final d in dets) {'cls': d.cls, 'score': d.score, 'box': box(d)}],
        'comps': [for (final d in rw.components) {'cls': d.cls, 'score': d.score, 'box': box(d)}],
        'removed': (rw.removed.toList()..sort()),
        'added': [
          for (final o in rw.added)
            {
              'pts': [for (final p in o.points) ...[r.toPageX(p.x), r.toPageY(p.y)]].map((v) => (v * 10).round() / 10).toList(),
              'clean': o.clean,
              'body': o.body,
              'fill': o.fill,
            }
        ],
      }));
      // ignore: avoid_print
      print('$name ${im.width}x${im.height} ${traced.length} lines, ${rw.components.length} parts, '
          'trace ${tTrace}ms total ${watch.elapsedMilliseconds}ms');
    }
  }, skip: dir == null || out == null ? 'set ABELNOTES_IMAGE_BENCH and _OUT' : false, timeout: Timeout.none);
}
