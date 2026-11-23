// Recognize on a lasso: which recognizer the router's probabilities pick.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/modules/recognize_route.dart';
import 'package:abelnotes/features/modules/selection_action.dart';
import 'package:abelnotes/features/search/region_route.dart';
import 'package:abelnotes/l10n/app_localizations.dart';

class _Act extends SelectionAction {
  const _Act(this.id);
  @override
  final String id;
  @override
  IconData get icon => Icons.star;
  @override
  String label(AppLocalizations l10n) => id;
  @override
  String busyLabel(AppLocalizations l10n) => id;
  @override
  String failedLabel(AppLocalizations l10n) => id;
  @override
  bool appliesTo(SelectionSummary selection) => true;
  @override
  Future<SelectionOutcome> run(SelectionRequest request) async => const ActionFailed('x');
}

const math = _Act(kMathInkActionId), circuit = _Act(kCircuitTidyActionId);
const both = RecognizerSlots(formula: math, circuit: circuit);

void main() {
  test('only the two recognizers are routed (and kept out of the menus)', () {
    expect(isRecognizerAction(math), isTrue);
    expect(isRecognizerAction(circuit), isTrue);
    expect(isRecognizerAction(const _Act('other.module.action')), isFalse);
    expect(const RecognizerSlots().any, isFalse);
    expect(const RecognizerSlots(circuit: circuit).any, isTrue);
  });

  test('a confident formula runs the formula action', () {
    final s = decideRecognize(const RegionProbs(0.1, 0.8, 0.05, 0.05), both);
    expect(s, isA<RunRecognizer>().having((r) => r.action.id, 'action', kMathInkActionId));
  });

  test('a confident circuit runs the tidy-up', () {
    final s = decideRecognize(const RegionProbs(0.05, 0.1, 0.8, 0.05), both);
    expect(s, isA<RunRecognizer>().having((r) => r.action.id, 'action', kCircuitTidyActionId));
  });

  test('text and drawings only say why nothing changes', () {
    expect(decideRecognize(const RegionProbs(0.9, 0.05, 0.03, 0.02), both),
        isA<NoteRecognizer>().having((n) => n.note, 'note', RecognizeNote.textNotConverted));
    expect(decideRecognize(const RegionProbs(0.05, 0.05, 0.1, 0.8), both),
        isA<NoteRecognizer>().having((n) => n.note, 'note', RecognizeNote.nothingToRecognize));
  });

  test('low top probability or a close runner-up asks', () {
    // top 0.59 < 0.6
    expect(decideRecognize(const RegionProbs(0.2, 0.59, 0.11, 0.1), both), isA<AskRecognizer>());
    expect(decideRecognize(const RegionProbs(0.0, 0.6, 0.4, 0.0), both), isA<RunRecognizer>());
    // Runner-up within 0.15 (not reachable with a softmax once top >= 0.6; kept as a guard).
    expect(decideRecognize(const RegionProbs(0.0, 0.7, 0.6, 0.0), both), isA<AskRecognizer>());
    // no router (engine missing): always ask
    expect(decideRecognize(null, both), isA<AskRecognizer>());
  });

  test('a switched-off module is named, a missing model is reported', () {
    const off = RecognizerSlots(circuit: circuit, formulaOff: true);
    expect(decideRecognize(const RegionProbs(0.1, 0.8, 0.05, 0.05), off),
        isA<NoteRecognizer>().having((n) => n.note, 'note', RecognizeNote.formulaOff));
    const loading = RecognizerSlots(formula: math);
    expect(recognizeAs(RegionKind.circuit, loading),
        isA<NoteRecognizer>().having((n) => n.note, 'note', RecognizeNote.unavailable));
    const cOff = RecognizerSlots(formula: math, circuitOff: true);
    expect(recognizeAs(RegionKind.circuit, cOff),
        isA<NoteRecognizer>().having((n) => n.note, 'note', RecognizeNote.circuitOff));
  });

  test('the user pick goes through the same rules', () {
    expect(recognizeAs(RegionKind.formula, both), isA<RunRecognizer>());
    expect(recognizeAs(RegionKind.text, both), isA<NoteRecognizer>());
    expect(both.any, isTrue);
    expect(const RecognizerSlots(formulaOff: true, circuitOff: true).any, isFalse);
  });
}
