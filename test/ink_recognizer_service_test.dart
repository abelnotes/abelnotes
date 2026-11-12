// End-to-end check of the recognition service: StrokeData in, LaTeX out.
//
// The parity test in ink_recognizer_parity_test.dart pins the numerics against
// PyTorch, but it calls the model directly. This one goes through the layer the
// app actually uses — InkRecognizer, its isolate, the feature extraction on the
// calling side and the detokenizer on the way back — starting from StrokeData
// objects built the way canvas_provider hands them over.
//
// Skipped unless a model export is present (test/support/ml_dir.dart): the
// test vectors hold dataset ink that is not in the repo.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/data/ink_recognizer/ink_recognizer_service.dart';
import 'package:abelnotes/features/canvas/data/ink_recognizer/latex_delimiters.dart';
import 'package:abelnotes/features/canvas/data/ink_recognizer/model_file.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/ml_dir.dart';

/// Rebuilds StrokeData from a test vector's raw coordinates, so the service is
/// fed the same shape of input the canvas provides.
List<StrokeData> _strokesFrom(ModelFile vectors, int index) {
  final flat = vectors['strokes_$index'].floats;
  final offsets = vectors['strokeOff_$index'].ints;
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

  group('ink recognizer service', () {
    late ModelFile vectors;
    late InkRecognizer recognizer;
    late List<String> expected;

    setUpAll(() async {
      if (dir == null) return;
      vectors = ModelFile.parse(File('$dir/testvectors.bin').readAsBytesSync());
      // The service stretches delimiters after decoding; so does the reference.
      expected = (vectors.header['predictions'] as List<dynamic>)
          .map((e) => stretchDelimiters(e as String))
          .toList(growable: false);

      // The service looks for a file at a fixed name under a directory, so the
      // export is linked (not copied — it is 15-31 MB) into a temp dir laid out
      // the way InkRecognizer.pathIn expects.
      final temp = Directory.systemTemp.createTempSync('abelnotes-ink-test');
      Directory('${temp.path}/models').createSync();
      final target = InkRecognizer.pathIn(temp.path);
      Link(target).createSync('$dir/weights.bin');

      final loaded = await InkRecognizer.load(target);
      expect(loaded, isNotNull, reason: 'model at $target failed to load');
      recognizer = loaded!;
      addTearDown(() {
        recognizer.dispose();
        temp.deleteSync(recursive: true);
      });
    });

    test('reports unavailable when no model is installed', () async {
      final missing = await InkRecognizer.load(
          '${Directory.systemTemp.path}/definitely-not-a-model-${DateTime.now().microsecondsSinceEpoch}.ablm');
      // Absence is the default state of a fresh install, so it must be a null
      // result rather than an exception the caller has to catch.
      expect(missing, isNull);
    });

    test('empty selection fails without touching the isolate', () async {
      if (dir == null) return;
      final result = await recognizer.recognize(const []);
      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
    });

    test('recognizes every test vector from StrokeData', () async {
      if (dir == null) return;
      final n = vectors.header['n'] as int;
      var totalMs = 0;
      for (var i = 0; i < n; i++) {
        final result = await recognizer.recognize(_strokesFrom(vectors, i));
        expect(result.ok, isTrue, reason: 'vector $i: ${result.error}');
        totalMs += result.milliseconds;

        // The service must reproduce the checkpoint's own output. Comparing
        // against the ground-truth label instead would be wrong: the model is
        // not always right, and a port that "fixed" its mistakes would be the
        // thing that is broken.
        //
        // Compared after stripping spaces, because detokenize reinserts the
        // space that terminates a command name (`\int x`) and the reference
        // string from Python carries whatever spacing the label had.
        expect(result.latex!.replaceAll(' ', ''),
            expected[i].replaceAll(' ', ''),
            reason: 'vector $i diverged from the PyTorch prediction');
      }
      // ignore: avoid_print
      print('  ${(totalMs / n).round()} ms per recognition '
          'through the isolate (JIT, $n inks)');
    });

    test('every command in the output is a real command', () async {
      if (dir == null) return;
      // Catches the detokenization bug this code once had: joining tokens
      // without the space that terminates a command name turns `\int x` into
      // `\intx`, which is not a command and will not render. 18.9% of validation
      // labels contain a command followed by a letter, so this is not a corner
      // case. Any glued command shows up here as a token the vocabulary does not
      // contain.
      final weights = ModelFile.parse(File('$dir/weights.bin').readAsBytesSync());
      // \left/\right come from stretchDelimiters, not from the model.
      final known = {...weights.vocab!, r'\left', r'\right'};
      // The same pattern ml/src/vocab.py tokenizes with, and the alternation
      // order matters: `\\.` must get a chance at an escaped backslash before
      // anything reads it as the start of a name. `\\` is LaTeX's line break, a
      // complete two-character command that does not absorb the letter after it,
      // so `\\m` is valid and a plain `\\[a-zA-Z]+` scan reports it as a bogus
      // `\m`. That false positive is what this comment exists to prevent
      // rediscovering.
      final tokenPattern = RegExp(r'\\[a-zA-Z]+|\\.|\S');
      final namePattern = RegExp(r'^\\[a-zA-Z]+$');
      final n = vectors.header['n'] as int;

      for (var i = 0; i < n; i++) {
        final result = await recognizer.recognize(_strokesFrom(vectors, i));
        expect(result.ok, isTrue, reason: 'vector $i: ${result.error}');
        for (final match in tokenPattern.allMatches(result.latex!)) {
          final token = match.group(0)!;
          if (!namePattern.hasMatch(token)) continue;
          expect(known, contains(token),
              reason: 'vector $i produced "$token", which is not in the '
                  'vocabulary — a command name ran into the next token: '
                  '${result.latex}');
        }
      }
    });
  }, skip: dir == null ? 'no model export found; see the header of this file' : null);
}
