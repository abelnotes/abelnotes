// A sample written to a prompt, as the receiver accepts it: classes match the
// model, ink moves to its own origin, nothing beyond strokes and label leaves.
import 'dart:convert';
import 'dart:io';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_recognizer_service.dart';
import 'package:abelnotes/features/canvas/data/ink_recognizer/model_file.dart';
import 'package:abelnotes/features/donate/donation_sample.dart';
import 'package:flutter_test/flutter_test.dart';

const _strokes = [
  [50.0, 60.0, 1000.0, 0.4, 70.0, 80.0, 1016.0, 1.7],
  [90.0, 55.0, 1500.0, 0.876],
];

DonationSample _circuit({String label = 'resistor', List<List<double>> strokes = _strokes}) => DonationSample.guided(
    id: 'c', created: DateTime.utc(2026, 11, 8), kind: DonationKind.circuit, strokes: strokes, label: label)!;

DonationSample _formula(String latex) => DonationSample.guided(
    id: 'f', created: DateTime.utc(2026, 11, 8), kind: DonationKind.formula, strokes: _strokes, label: latex)!;

void main() {
  test('the symbols are the bundled model\'s classes', () {
    final model = ModelFile.parse(File(kBundledCircuitModelAsset).readAsBytesSync());
    expect(kDonationSymbols.toSet(), (model.header['names'] as List).cast<String>().toSet());
    expect(kDonationSymbols.length, kDonationSymbols.toSet().length);
  });

  test('a guided sample moves to its own origin and counts as reviewed', () {
    final f = _formula('x^{2}');
    expect(f.sendable, isTrue);
    expect(f.strokes, [
      [0, 5, 0, 0.4, 20, 25, 16, 1],
      [40, 0, 500, 0.88],
    ]);
    expect((f.toWire()['label'] as Map)['latex'], 'x^{2}');

    final c = _circuit();
    expect(c.toWire()['source'], 'guided');
    expect((c.toWire()['label'] as Map)['parts'], [
      {
        'symbol': 'resistor',
        'box': [0.0, 0.0, 40.0, 25.0]
      }
    ]);
  });

  test('nothing is kept without ink, with an unknown symbol, or past the receiver limits', () {
    DonationSample? make(DonationKind kind, List<List<double>> strokes, String label) =>
        DonationSample.guided(id: 'x', created: DateTime.utc(2026), kind: kind, strokes: strokes, label: label);
    expect(make(DonationKind.circuit, _strokes, 'nope'), isNull);
    expect(make(DonationKind.formula, const [], 'x'), isNull);
    expect(make(DonationKind.formula, _strokes, 'x²'), isNull);
    expect(
        make(DonationKind.circuit, [
          for (var i = 0; i <= kMaxStrokesPerSample; i++) [0.0, 0.0, 0.0, 0.5]
        ], 'diode'),
        isNull);
  });

  test('a dot still gets a box the receiver accepts', () {
    final s = _circuit(strokes: const [
      [5.0, 5.0, 0.0, 0.5]
    ]);
    final p = s.parts.single;
    expect([p.x, p.y, p.w, p.h], [0, 0, 1, 1]);
  });

  test('corrections count changed, removed and added parts', () {
    final s = _circuit();
    expect(s.corrections, 0);
    final edited = s.copyWith(parts: [
      s.parts[0].withSymbol('inductor'),
      const DonationPart('gnd', 1, 1, 5, 5),
    ]);
    // inductor (changed) + gnd (added).
    expect(edited.corrections, 2);
    expect(edited.copyWith(parts: const []).corrections, 1);
    expect(edited.copyWith(parts: [...edited.detected]).corrections, 0);
  });

  test('round-trips through its local file', () {
    for (final s in [_circuit().copyWith(reviewed: false), _formula(r'\frac{a}{b}')]) {
      final back = DonationSample.fromJson(jsonDecode(jsonEncode(s.toJson())))!;
      expect(back.toJson(), s.toJson());
    }
    expect(DonationSample.fromJson(jsonDecode(jsonEncode(_circuit().toJson())))!.detected.single.symbol, 'resistor');
    expect(DonationSample.fromJson({..._formula('x').toJson(), 'kind': 'other'}), isNull);
  });

  test('the wire form holds only what the receiver accepts', () {
    final s = _circuit().copyWith(parts: [_circuit().parts.single.withSymbol('inductor')]);
    final w = s.toWire();
    expect(w.keys.toSet(), {'kind', 'source', 'strokes', 'label'});
    expect(w['kind'], 'circuit');
    expect((w['label'] as Map)['parts'], [
      {
        'symbol': 'inductor',
        'box': [0.0, 0.0, 40.0, 25.0]
      }
    ]);
    for (final st in w['strokes'] as List<List<double>>) {
      expect(st.length % 4, 0);
      for (var i = 0; i < st.length; i += 4) {
        expect(st[i + 2], inInclusiveRange(0, kMaxSampleMs));
        expect(st[i + 3], inInclusiveRange(0, 1));
      }
    }
  });

  test('a formula keeps the prompt for Reset and sends the LaTeX as reviewed', () {
    final s = _formula(r'\frac{a}{b}');
    expect([s.latex, s.prompt, s.reviewed, s.corrections], [r'\frac{a}{b}', r'\frac{a}{b}', true, 0]);
    final fixed = s.copyWith(latex: r'\frac{a}{c}');
    expect(fixed.corrections, 1);
    expect(fixed.sendable, isTrue);
    expect(fixed.toWire(), {
      'kind': 'formula',
      'source': 'guided',
      'strokes': s.strokes,
      'label': {'latex': r'\frac{a}{c}'},
    });
    expect(fixed.toJson().containsKey('parts'), isFalse);
  });

  test('a formula the receiver would refuse is not sendable', () {
    final s = _formula('x');
    for (final bad in ['', '   ', 'x²', 'a' * (kMaxLatexChars + 1)]) {
      expect(s.copyWith(latex: bad).sendable, isFalse, reason: bad);
    }
    expect(latexProblem('x²'), LatexProblem.notAscii);
    expect(latexProblem(''), LatexProblem.empty);
    expect(latexProblem('a' * (kMaxLatexChars + 1)), LatexProblem.tooLong);
    expect(latexProblem(r'\alpha_{1}'), isNull);
  });
}
