// Does the hand-written Dart forward pass agree with PyTorch?
//
// A transformer ported by hand either reproduces its reference or it does not,
// and the failure mode of "not" is confident nonsense on screen rather than an
// error. So every stage is pinned against reference tensors exported by
// ml/src/export_dart.py, starting from **raw ink** so feature extraction is
// verified too:
//
//   strokes_i   ->  features_i   feature pipeline: normalise, resample, 6 channels
//   features_i  ->  memory_i     conv stem, positions, encoder layers, final norm
//   memory_i    ->  tokens_i     greedy decode, then detokenize to LaTeX
//
// The reference is what *this checkpoint* emits, not the ground-truth label:
// reproducing the label would mean the port is better than the model, which
// would mean it is wrong.
//
// The export lives outside the repo (its test vectors hold dataset ink), so
// this test skips when it is absent; see inkExportDir in test/support/ml_dir.dart.
// Prefer an f32 export: comparing f16-rounded weights against an f32 reference
// measures rounding, not the port. Both are accepted and the tolerance follows
// the file's storage_dtype.

import 'dart:io';
import 'dart:typed_data';

import 'package:abelnotes/features/canvas/data/ink_recognizer/ink_features.dart';
import 'package:abelnotes/features/canvas/data/ink_recognizer/ink_to_latex.dart';
import 'package:abelnotes/features/canvas/data/ink_recognizer/model_file.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ml_dir.dart';

double _maxAbsDiff(Float32List a, Float32List b) {
  var worst = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > worst) worst = d;
  }
  return worst;
}

/// Rebuilds canvas strokes from the flat point list and stroke offsets, so the
/// test enters the pipeline through the same door the app does.
List<StrokeData> _strokesFrom(Float32List flat, Int32List offsets) {
  final strokes = <StrokeData>[];
  for (var s = 0; s + 1 < offsets.length; s++) {
    final points = <StrokePoint>[];
    for (var p = offsets[s]; p < offsets[s + 1]; p++) {
      points.add(StrokePoint(x: flat[p * 2], y: flat[p * 2 + 1]));
    }
    if (points.isNotEmpty) strokes.add(StrokeData(points: points));
  }
  return strokes;
}

void main() {
  final dir = inkExportDir();
  final skip = dir == null
      ? 'no Dart export found (set ABELNOTES_ML or ABELNOTES_ML_DART)'
      : null;

  group('ink recognizer parity with PyTorch', () {
    late ModelFile weightsFile;
    late ModelFile vectorsFile;
    late InkToLatexModel model;
    late int count;
    late double step;
    late List<String> predictions;
    // f32 storage leaves only arithmetic reordering and the erf approximation in
    // ops.dart; f16 storage adds a rounding error that grows through four
    // encoder layers, so the encoder tolerance follows the dtype. Token ids must
    // match either way — that is the claim that fp16 storage costs nothing.
    //
    // Both bounds are the measured worst case with ~50x headroom, not a guess:
    // 1.9e-6 for f32 and 1.2e-3 for f16 over the eight vectors of the first export. Kept tight
    // on purpose — a tolerance loose enough to absorb a real porting bug would
    // make this test decorative.
    late double memoryTolerance;

    setUpAll(() {
      weightsFile = ModelFile.parse(File('$dir/weights.bin').readAsBytesSync());
      vectorsFile = ModelFile.parse(File('$dir/testvectors.bin').readAsBytesSync());
      model = InkToLatexModel.fromFile(weightsFile);
      count = vectorsFile.header['n'] as int;
      step = (vectorsFile.header['step'] as num).toDouble();
      predictions =
          (vectorsFile.header['predictions'] as List<dynamic>).cast<String>();
      memoryTolerance = weightsFile.header['storage_dtype'] == 'f32' ? 1e-4 : 6e-2;
    });

    test('export is loadable and self-consistent', () {
      expect(weightsFile.kind, 'weights');
      expect(vectorsFile.kind, 'testvectors');
      expect(count, greaterThan(0));
      expect(step, kDefaultStep,
          reason: 'the cache was built with a different arc-length step than '
              'ink_features.dart uses; features cannot match');
      expect(model.config.nFeatures, kFeatureCount);
      expect(model.vocab.length, model.config.nVocab);
      expect(predictions.length, count);
    });

    test('feature extraction matches features.py', () {
      for (var i = 0; i < count; i++) {
        final expected = vectorsFile['features_$i'];
        final strokes = _strokesFrom(
            vectorsFile['strokes_$i'].floats, vectorsFile['strokeOff_$i'].ints);
        final got = extractFeatures(strokes, step: step);

        expect(got.pointCount, expected.shape[0],
            reason: 'ink $i resampled to a different number of points');
        expect(_maxAbsDiff(got.values, expected.floats), lessThan(1e-4),
            reason: 'ink $i feature values drifted from the Python pipeline');
      }
    });

    test('encoder matches model.py', () {
      var worst = 0.0;
      for (var i = 0; i < count; i++) {
        final expected = vectorsFile['memory_$i'];
        // Copied out of the container rather than viewed: this feeds the SIMD
        // matmul, and a view inherits the file's byte offset.
        final features = InkFeatures(
          Float32List.fromList(vectorsFile['features_$i'].floats),
          vectorsFile['features_$i'].shape[0],
        );

        final encoded = model.encode(features);
        expect(encoded.positions, expected.shape[0],
            reason: 'ink $i produced a different number of encoder positions; '
                'check the conv stem strides and padding');
        final diff = _maxAbsDiff(encoded.memory, expected.floats);
        if (diff > worst) worst = diff;
        expect(diff, lessThan(memoryTolerance),
            reason: 'ink $i encoder memory disagrees with PyTorch');
      }
      // Printed because the number is the actual finding: it says how much of the
      // gap is arithmetic reordering and how much is float16 storage.
      // ignore: avoid_print
      print('  encoder max abs diff over $count inks: '
          '${worst.toStringAsExponential(2)} '
          '(${weightsFile.header['storage_dtype']} weights, '
          'tolerance ${memoryTolerance.toStringAsExponential(0)})');
    });

    test('greedy decode reproduces the checkpoint predictions', () {
      final elapsed = Stopwatch();
      for (var i = 0; i < count; i++) {
        // From raw ink through the whole chain, which is what the app runs.
        final strokes = _strokesFrom(
            vectorsFile['strokes_$i'].floats, vectorsFile['strokeOff_$i'].ints);
        elapsed.start();
        final tokens = model.decode(model.encode(extractFeatures(strokes, step: step)));
        elapsed.stop();
        final expected = vectorsFile['tokens_$i'].ints;

        expect(tokens, expected.toList(),
            reason: 'ink $i decoded to different token ids; PyTorch said '
                '"${predictions[i]}", Dart said "${model.detokenize(tokens)}"');
        expect(model.detokenize(tokens), predictions[i],
            reason: 'ink $i detokenized differently; check the command-space '
                'rule against detokenize in ml/src/vocab.py');
      }
      // Indicative only, never asserted: this runs in the test VM's JIT on
      // whatever machine ran it, while the app ships AOT. Use ml/bench_dart for
      // a latency number worth quoting.
      // ignore: avoid_print
      print('  ${(elapsed.elapsedMicroseconds / 1000 / count).toStringAsFixed(0)} ms '
          'per recognition, raw ink to LaTeX (JIT, $count inks)');
    });
  }, skip: skip);
}
