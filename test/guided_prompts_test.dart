// Prompts for the guided page: every formula typesets and is a label the
// receiver takes; circuit prompts cover the classes, one round at a time.
import 'dart:math' as math;

import 'package:abelnotes/features/donate/donation_formula_page.dart';
import 'package:abelnotes/features/donate/donation_sample.dart';
import 'package:abelnotes/features/donate/guided/guided_prompts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated formulas typeset and fit the receiver', () {
    final prompts = GuidedPrompts(math.Random(7));
    final bad = <String>[];
    final seen = <String>{};
    for (var i = 0; i < 3000; i++) {
      final f = prompts.formula();
      seen.add(f);
      if (latexProblem(f) != null || !latexParses(f)) bad.add(f);
    }
    expect(bad, isEmpty);
    // Templates are filled, not repeated.
    expect(seen.length, greaterThan(1500));
  });

  test('a command never runs into the letter after it', () {
    final prompts = GuidedPrompts(math.Random(1));
    expect(prompts.fill(r'@g@v').contains(RegExp(r'\\[a-z]+[a-zA-Z]{2,}$')), isFalse);
    for (var i = 0; i < 500; i++) {
      final f = prompts.fill(r'@f@v');
      expect(latexParses(f), isTrue, reason: f);
    }
  });

  test('next() skips formulas already shown and ones refused', () {
    final prompts = GuidedPrompts(math.Random(3));
    final shown = <String>{};
    for (var i = 0; i < 200; i++) {
      final p = prompts.next(DonationKind.formula, accept: (f) => !f.contains('frac'));
      expect(p.label.contains('frac'), isFalse);
      expect(shown.add(p.label), isTrue);
    }
  });

  test('circuit prompts go through every guided class before repeating', () {
    final prompts = GuidedPrompts(math.Random(5));
    final round = [for (var i = 0; i < kGuidedSymbols.length; i++) prompts.next(DonationKind.circuit)];
    expect(round.map((p) => p.label).toSet(), kGuidedSymbols.toSet());
    expect(kDonationSymbols.toSet().containsAll(kGuidedSymbols), isTrue);
    expect(round.firstWhere((p) => p.label == 'text').text, isNotEmpty);
  });
}
