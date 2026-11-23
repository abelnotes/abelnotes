// Lexicon beam search of the handwriting recognizer.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/search/ink_decode.dart';

const _chars = [' ', 'a', 'c', 'e', 'o', 'r', 't', 'n', '1'];

/// One frame per entry: {class: prob}, the rest of the mass on blank.
Float32List _probs(List<Map<String, double>> frames) {
  final c = _chars.length + 1;
  final out = Float32List(frames.length * c);
  for (var t = 0; t < frames.length; t++) {
    var rest = 1.0;
    frames[t].forEach((ch, p) {
      out[t * c + _chars.indexOf(ch) + 1] = p;
      rest -= p;
    });
    out[t * c] = rest;
  }
  return out;
}

void main() {
  final lex = InkLexicon.parse('carne\t-9.0\ncane\t-8.0\nre\t-7.0\nnot a row\n');

  test('lexicon lookups', () {
    expect(lex.length, 3);
    expect(lex.logpOf('cane'), -8.0);
    expect(lex.logpOf('can'), isNull);
    expect(lex.isPrefix('ca'), isTrue);
    expect(lex.isPrefix('car'), isTrue);
    expect(lex.isPrefix('cb'), isFalse);
    expect(lex.isPrefix('zz'), isFalse);
  });

  test('an unsure letter snaps to the word', () {
    // "canc": the last letter is c (0.55) or e (0.45).
    final p = _probs([
      {'c': 0.9}, {}, {'a': 0.9}, {}, {'n': 0.9}, {}, {'c': 0.55, 'e': 0.45},
    ]);
    final r = beamDecode(p, 7, _chars.length + 1, _chars, lex, const InkDecoderParams());
    expect(r.text, 'cane');
    expect(r.frames, [0, 2, 4, 6]);
  });

  test('a token with a digit is left alone', () {
    final p = _probs([
      {'r': 0.95}, {}, {'1': 0.95}, {}, {' ': 0.95}, {'r': 0.95}, {}, {'e': 0.95},
    ]);
    final r = beamDecode(p, 8, _chars.length + 1, _chars, lex, const InkDecoderParams());
    expect(r.text, 'r1 re');
  });
}
