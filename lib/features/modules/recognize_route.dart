// "Recognize" on a lasso selection: the region router picks formula, circuit,
// text or drawing, and the selection goes to that module's own action.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/features/search/region_router.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'builtin_modules.dart';
import 'module_registry.dart';
import 'selection_action.dart';

/// Below this top probability, or with the runner-up this close, the user picks.
const recognizeMinTop = 0.6;
const recognizeMinMargin = 0.15;

const kMathInkActionId = 'abelnotes.math-ink.recognize';
const kCircuitTidyActionId = 'abelnotes.circuits.tidy';

/// The actions Recognize routes to; they are not offered on their own.
bool isRecognizerAction(SelectionAction a) =>
    a.id == kMathInkActionId || a.id == kCircuitTidyActionId;

/// Says what strokes are (null: no points).
typedef RegionClassifier = Future<RegionProbs?> Function(List<StrokeData> strokes);

/// The router, loaded on the first Recognize (null where the engine cannot
/// run). Lives as long as the app.
final regionClassifierProvider = FutureProvider<RegionClassifier?>((ref) async {
  final data = await rootBundle.load(regionRouterAsset);
  final router =
      await RegionRouter.load(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  if (router == null) return null;
  ref.onDispose(router.dispose);
  return router.classifyAsync;
});

/// Where each recognizer stands right now.
class RecognizerSlots {
  const RecognizerSlots({this.formula, this.circuit, this.formulaOff = false, this.circuitOff = false});

  /// The ready actions (null when the module is off, loading or missing).
  final SelectionAction? formula, circuit;

  /// The module is switched off in Settings.
  final bool formulaOff, circuitOff;

  /// Recognize is offered when at least one recognizer can run.
  bool get any => formula != null || circuit != null;

  static RecognizerSlots read(WidgetRef ref) {
    final actions = {for (final a in ref.read(selectionActionsProvider)) a.id: a};
    final off = {
      for (final e in ref.read(moduleEntriesProvider))
        if (e.status == ModuleStatus.disabled) e.module.manifest.id,
    };
    return RecognizerSlots(
      formula: actions[kMathInkActionId],
      circuit: actions[kCircuitTidyActionId],
      formulaOff: off.contains(kMathInkModuleId),
      circuitOff: off.contains(kCircuitsModuleId),
    );
  }
}

/// Why Recognize changed nothing.
enum RecognizeNote { textNotConverted, nothingToRecognize, formulaOff, circuitOff, unavailable }

sealed class RecognizeStep {
  const RecognizeStep();
}

/// Run this module action on the selection.
class RunRecognizer extends RecognizeStep {
  const RunRecognizer(this.action, this.kind);
  final SelectionAction action;
  final RegionKind kind;
}

/// Not sure: let the user pick formula, circuit or text.
class AskRecognizer extends RecognizeStep {
  const AskRecognizer();
}

/// Nothing to run: tell the user why.
class NoteRecognizer extends RecognizeStep {
  const NoteRecognizer(this.note);
  final RecognizeNote note;
}

/// The step for [probs]; null probabilities (no router) always ask.
RecognizeStep decideRecognize(RegionProbs? probs, RecognizerSlots slots) {
  if (probs == null) return const AskRecognizer();
  final r = probs.ranked;
  final top = probs.of(r[0]);
  if (top < recognizeMinTop || top - probs.of(r[1]) < recognizeMinMargin) {
    return const AskRecognizer();
  }
  return recognizeAs(r[0], slots);
}

/// The step once the kind is known (the router's or the user's pick).
RecognizeStep recognizeAs(RegionKind kind, RecognizerSlots slots) => switch (kind) {
      RegionKind.formula => slots.formula != null
          ? RunRecognizer(slots.formula!, kind)
          : NoteRecognizer(slots.formulaOff ? RecognizeNote.formulaOff : RecognizeNote.unavailable),
      RegionKind.circuit => slots.circuit != null
          ? RunRecognizer(slots.circuit!, kind)
          : NoteRecognizer(slots.circuitOff ? RecognizeNote.circuitOff : RecognizeNote.unavailable),
      RegionKind.text => const NoteRecognizer(RecognizeNote.textNotConverted),
      RegionKind.drawing => const NoteRecognizer(RecognizeNote.nothingToRecognize),
    };
