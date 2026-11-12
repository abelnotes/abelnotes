// Extension point: an action offered for a lasso selection (its ⋯ menu and
// the context menu). The module computes an outcome; the host applies it, so
// every action gets the same single-step undo.

import 'package:flutter/widgets.dart';

import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Cheap facts about the selection, checked whenever a menu is built.
class SelectionSummary {
  const SelectionSummary({required this.hasInk});

  /// A stroke, or a shape with an outline to trace.
  final bool hasInk;
}

/// What an action receives when tapped. Element lists are built on demand.
class SelectionRequest {
  const SelectionRequest({required this.ink, required this.pageWidth});

  /// Every stroke plus shapes traced as polylines, with their element ids.
  final List<(String, StrokeData)> Function() ink;
  final double pageWidth;
}

sealed class SelectionOutcome {
  const SelectionOutcome();
}

/// Swap the elements with [removedIds] for [added] strokes.
class ReplaceInk extends SelectionOutcome {
  const ReplaceInk(this.removedIds, this.added);
  final Set<String> removedIds;
  final List<StrokeData> added;
}

/// Why an action changed nothing; each case has its own message.
enum ActionFailReason { notRecognized, modelMissing, noInk, error }

/// Nothing changes; [debug] goes to the log, the user sees a message for
/// [reason] (the action's failed label when nothing was recognised).
class ActionFailed extends SelectionOutcome {
  const ActionFailed(this.debug, {this.reason = ActionFailReason.notRecognized});
  final String debug;
  final ActionFailReason reason;
}

abstract class SelectionAction {
  const SelectionAction();

  /// Dotted id, unique across modules.
  String get id;
  IconData get icon;
  String label(AppLocalizations l10n);
  String busyLabel(AppLocalizations l10n);
  String failedLabel(AppLocalizations l10n);

  bool appliesTo(SelectionSummary selection);
  Future<SelectionOutcome> run(SelectionRequest request);
}
