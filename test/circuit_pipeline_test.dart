// End-to-end smoke test on synthetic mouse-drawn circuits: strokes -> raster ->
// the bundled detector -> rewrite -> page strokes.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_recognizer_service.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_strokes.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/detector.dart';
import 'package:abelnotes/features/canvas/data/ink_recognizer/model_file.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:flutter_test/flutter_test.dart';

({List<Float64List> strokes, double pageWidth}) _fixture(String name) {
  final j = jsonDecode(File('test/fixtures/circuits/$name.json').readAsStringSync()) as Map<String, dynamic>;
  return (
    strokes: [
      for (final s in j['strokes'] as List)
        Float64List.fromList([for (final v in s as List) (v as num).toDouble()])
    ],
    pageWidth: (j['pageWidth'] as num).toDouble(),
  );
}

void main() {
  late CircuitDetector det;
  setUpAll(() {
    det = CircuitDetector.fromModelFile(ModelFile.parse(File(kBundledCircuitModelAsset).readAsBytesSync()));
  });

  // syn_bjt's supply bar and syn_opamp's input resistor stay as drawn: run7 turned
  // them into a ground and an inductor.
  const parts = {'mouse_rc': 4, 'syn_bjt': 3, 'syn_opamp': 3, 'syn_pmos': 3, 'syn_coil_dependent': 4};
  for (final MapEntry(key: name, value: count) in parts.entries) {
    test('$name comes out tidied', () {
      final f = _fixture(name);
      final r = CircuitRecognizer.run(det, f.strokes, f.pageWidth);
      expect(r.ok, isTrue);
      expect(r.components, count);
      expect(r.removed, isNotEmpty);
      final pen = [
        for (final s in f.strokes)
          StrokeData(points: [
            for (var i = 0; i + 1 < s.length; i += 2) StrokePoint(x: s[i], y: s[i + 1]),
          ])
      ];
      final out = circuitStrokes(r, [for (final src in r.sources) src >= 0 ? pen[src] : pen[r.removed.first]]);
      expect(out.where((s) => isTechnicalTool(s.toolType)), isNotEmpty);
    });
  }

  test('the same input gives the same output', () {
    final f = _fixture('mouse_rc');
    final a = CircuitRecognizer.run(det, f.strokes, f.pageWidth);
    final b = CircuitRecognizer.run(det, f.strokes, f.pageWidth);
    expect(b.removed, a.removed);
    expect(b.added, a.added);
  });
}
