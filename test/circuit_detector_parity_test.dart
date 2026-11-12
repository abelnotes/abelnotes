// Checks the Dart detector against the numpy reference that export_detector.py
// verified against PyTorch. Skips when the exported files are not on this
// machine (they live outside the repo); ABELNOTES_CIRCUIT_MODEL overrides.
import 'dart:io';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/detector.dart';
import 'package:abelnotes/features/canvas/data/ink_recognizer/model_file.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ml_dir.dart';

void main() {
  final model = Platform.environment['ABELNOTES_CIRCUIT_MODEL'] ??
      '${mlDir()}/out/circuits/detector.ablm';
  final vectors = model.replaceAll('.ablm', '_testvectors.bin');
  final present = File(model).existsSync() && File(vectors).existsSync();

  test('forward pass matches the numpy reference', () {
    final det = CircuitDetector.fromModelFile(ModelFile.parse(File(model).readAsBytesSync()));
    final tv = ModelFile.parse(File(vectors).readAsBytesSync());
    final shape = (tv.header['shape'] as List).cast<int>();
    final h = shape[1], w = shape[2];
    final input = tv['input'].floats.sublist(0, h * w);
    final expected = tv['expected'].floats;

    final watch = Stopwatch()..start();
    final got = det.forward(input, h, w);
    // ignore: avoid_print
    print('forward ${h}x$w: ${watch.elapsedMilliseconds} ms');

    expect(got.length, expected.length);
    final n = got.length ~/ (4 + det.names.length);
    var boxErr = 0.0, scoreErr = 0.0;
    for (var i = 0; i < got.length; i++) {
      final e = (got[i] - expected[i]).abs();
      if (i < 4 * n) {
        if (e > boxErr) boxErr = e;
      } else if (e > scoreErr) {
        scoreErr = e;
      }
    }
    // ignore: avoid_print
    print('max box err $boxErr px, max score err $scoreErr');
    expect(boxErr, lessThan(0.5));
    expect(scoreErr, lessThan(2e-3));
  }, skip: present ? false : 'exported detector not found at $model');
}
