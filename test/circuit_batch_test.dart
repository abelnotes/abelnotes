// Runs the circuit pipeline over a folder of stroke fixtures (for instance
// hand-drawn photos traced by ml/circuits/photos_to_strokes.py) and writes,
// per fixture, the input, detections and output for ml/circuits/batch_report.py.
// Skips unless ABELNOTES_CIRCUIT_BATCH and ABELNOTES_CIRCUIT_BATCH_OUT are set.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_graph.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/detector.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/raster.dart';
import 'package:abelnotes/features/canvas/data/ink_recognizer/model_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final env = Platform.environment;
  final dir = env['ABELNOTES_CIRCUIT_BATCH'], out = env['ABELNOTES_CIRCUIT_BATCH_OUT'];
  final model = env['ABELNOTES_CIRCUIT_MODEL'] ?? 'assets/models/circuit_detector.ablm';

  test('circuit batch', () {
    final det = CircuitDetector.fromModelFile(ModelFile.parse(File(model).readAsBytesSync()));
    Directory(out!).createSync(recursive: true);
    var failed = 0;
    final files = Directory(dir!).listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final name = f.uri.pathSegments.last.replaceAll('.json', '');
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final strokes = [
        for (final s in j['strokes'] as List)
          Float64List.fromList([for (final v in s as List) (v as num).toDouble()])
      ];
      final watch = Stopwatch()..start();
      final record = <String, dynamic>{'name': name};
      try {
        final r = rasterize(strokes, (j['pageWidth'] as num).toDouble());
        final dets = det.detect(r.data, r.height, r.width);
        final px = [
          for (final s in strokes) [for (var i = 0; i + 1 < s.length; i += 2) Pt(r.toPxX(s[i]), r.toPxY(s[i + 1]))]
        ];
        final rw = rewriteCircuit(px, dets);
        List<List<double>> flat(List<Pt> pts) => [for (final p in pts) [p.x, p.y]];
        record.addAll({
          'w': r.width,
          'h': r.height,
          'before': [for (final s in px) flat(s)],
          'removed': rw.removed.toList(),
          'added': [for (final o in rw.added) {'pts': flat(o.points), 'src': o.source, 'wire': o.wire}],
          'dets': [for (final d in dets) [d.cls, d.score, d.x0, d.y0, d.x1, d.y1]],
        });
      } catch (e, st) {
        failed++;
        record['error'] = '$e\n$st';
      }
      record['ms'] = watch.elapsedMilliseconds;
      File('$out/$name.json').writeAsStringSync(jsonEncode(record));
    }
    // ignore: avoid_print
    print('${files.length} fixtures, $failed threw');
    expect(failed, 0);
  }, skip: dir == null || out == null ? 'set ABELNOTES_CIRCUIT_BATCH and _OUT' : false, timeout: Timeout.none);
}
