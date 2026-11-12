// Features that ship with the app, expressed through the module API so the
// API is exercised before any third party relies on it.

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_recognizer_service.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_strokes.dart';
import 'package:abelnotes/l10n/app_localizations.dart';

import 'module_manifest.dart';
import 'selection_action.dart';

/// A catalog entry, compiled into the app.
class AppModule {
  const AppModule({
    required this.manifest,
    required this.name,
    required this.description,
    this.runtime,
    this.actions = _noActions,
    this.beta = false,
  });

  final ModuleManifest manifest;
  final String Function(AppLocalizations l10n) name;
  final String Function(AppLocalizations l10n) description;

  /// Resolves to null when the module cannot run (e.g. no model file).
  /// Null means the module has nothing to load and is always ready.
  final ProviderListenable<AsyncValue<Object?>>? runtime;
  final List<SelectionAction> Function(Ref ref) actions;

  /// Still in testing: Settings marks it as Beta.
  final bool beta;
}

List<SelectionAction> _noActions(Ref _) => const [];

const kCircuitsModuleId = 'abelnotes.circuits';

final List<AppModule> builtinModules = [
  // Not on the web: the detector would freeze the UI for seconds there.
  if (!kIsWeb)
    AppModule(
      manifest: const ModuleManifest(
        id: kCircuitsModuleId,
        version: '1.0.0',
        license: 'AGPL-3.0-or-later AND GPL-3.0-only',
        permissions: {
          ModulePermission.selectionRead,
          ModulePermission.selectionWrite,
          ModulePermission.modelRun,
        },
        assets: [
          ModuleAsset(
            kCircuitModelFileName,
            sha256: kBundledCircuitModelSha256,
            license: 'AGPL-3.0, with CC BY 4.0 attribution to CGHD',
          ),
        ],
        selectionActions: ['abelnotes.circuits.tidy'],
      ),
      name: (l) => l.modCircuitsName,
      description: (l) => l.modCircuitsDesc,
      runtime: circuitRecognizerProvider,
      actions: (ref) => [_TidyCircuit(ref)],
      beta: true,
    ),
];

class _TidyCircuit extends SelectionAction {
  const _TidyCircuit(this._ref);
  final Ref _ref;

  @override
  String get id => 'abelnotes.circuits.tidy';
  @override
  IconData get icon => Icons.electrical_services_rounded;
  @override
  String label(AppLocalizations l10n) => l10n.csRecognizeCircuit;
  @override
  String busyLabel(AppLocalizations l10n) => l10n.csRecognizeBusy;
  @override
  String failedLabel(AppLocalizations l10n) => l10n.csRecognizeCircuitFailed;
  @override
  bool appliesTo(SelectionSummary selection) => selection.hasInk;

  @override
  Future<SelectionOutcome> run(SelectionRequest request) async {
    final recognizer = _ref.read(circuitRecognizerProvider).valueOrNull;
    if (recognizer == null) return const ActionFailed('model not loaded', reason: ActionFailReason.modelMissing);
    final elements = request.ink();
    if (elements.isEmpty) return const ActionFailed('no ink', reason: ActionFailReason.noInk);
    final result = await recognizer.recognize([for (final e in elements) e.$2], request.pageWidth);
    debugPrint('[circuit] ${result.components} components, ${result.removed.length} strokes '
        'replaced in ${result.milliseconds} ms${result.error == null ? '' : ': ${result.error}'}');
    if (result.error != null) return ActionFailed(result.error!, reason: ActionFailReason.error);
    if (!result.ok || result.removed.isEmpty) return ActionFailed('${result.components} components, nothing replaced');
    final fallback = elements[result.removed.first].$2;
    return ReplaceInk(
      {for (final i in result.removed) elements[i].$1},
      circuitStrokes(result, [for (final src in result.sources) src >= 0 ? elements[src].$2 : fallback]),
    );
  }
}
