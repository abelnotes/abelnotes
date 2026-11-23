// Recognize on a lasso selection, through the editor: the action bar's
// Recognize, the router's verdict (faked) picks the module action, an unsure
// one asks, "Change" re-recognizes as another kind, undo is one step.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/presentation/editor/selection_action_bar.dart';
import 'package:abelnotes/features/modules/builtin_modules.dart';
import 'package:abelnotes/features/modules/module_manifest.dart';
import 'package:abelnotes/features/modules/module_registry.dart';
import 'package:abelnotes/features/modules/recognize_route.dart';
import 'package:abelnotes/features/modules/selection_action.dart';
import 'package:abelnotes/features/search/region_route.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'editor_e2e_test.dart' show loopAround, key;
import 'support/editor_harness.dart';

final runs = <String>[];

/// Stands in for a recognizer: replaces the ink with one straight stroke.
class _Fake extends SelectionAction {
  const _Fake(this.id);
  @override
  final String id;
  @override
  IconData get icon => Icons.star;
  @override
  String label(AppLocalizations l10n) => id;
  @override
  String busyLabel(AppLocalizations l10n) => 'busy';
  @override
  String failedLabel(AppLocalizations l10n) => 'failed';
  @override
  bool appliesTo(SelectionSummary selection) => selection.hasInk;
  @override
  Future<SelectionOutcome> run(SelectionRequest request) async {
    runs.add(id);
    final ink = request.ink();
    return ReplaceInk({for (final e in ink) e.$1}, [
      const StrokeData(points: [StrokePoint(x: 10, y: 10), StrokePoint(x: 60, y: 10)]),
    ]);
  }
}

AppModule _module(String id, String action) => AppModule(
      manifest: ModuleManifest(id: id, version: '1.0.0', license: 'MIT'),
      name: (_) => id,
      description: (_) => id,
      actions: (_) => [_Fake(action)],
    );

List<Override> _router(RegionProbs? p, {bool modules = true}) => [
      moduleCatalogProvider.overrideWithValue([
        if (modules) _module(kMathInkModuleId, kMathInkActionId),
        if (modules) _module(kCircuitsModuleId, kCircuitTidyActionId),
      ]),
      regionClassifierProvider.overrideWith((ref) async => (_) async => p),
    ];

Finder get _bar => find.byType(SelectionActionBar);

Future<void> _selectScribble(EditorHarness h, {Offset at = const Offset(-200, -150)}) async {
  final a = h.canvasCenter + at;
  await h.scribble(a);
  await key(h, LogicalKeyboardKey.keyL);
  await h.drag(loopAround(Rect.fromPoints(a + const Offset(0, -6), a + const Offset(96, 6))));
  expect(h.state.lassoSelection, isNotNull);
}

Future<void> _tapRecognize(EditorHarness h) async {
  await h.tester.pump(const Duration(milliseconds: 300));
  await h.tester.tap(find.descendant(of: _bar, matching: find.text('Recognize')));
  await h.tester.pumpAndSettle();
}

/// Lets the autosave after an edit finish (its file IO needs real time).
Future<void> _save(EditorHarness h) async {
  for (var i = 0; i < 40 && h.state.isDirty; i++) {
    await h.tester.pump(const Duration(milliseconds: 250));
    await h.settle(const Duration(milliseconds: 200));
  }
  await h.settle(const Duration(seconds: 1)); // the push to the (fake) server
  await h.tester.pump(const Duration(seconds: 30)); // retry and pull timers
}

void main() {
  setUp(runs.clear);

  testEditor('Recognize sends a formula to the formula action, one undo step', (h) async {
    await _selectScribble(h);
    final before = h.content.single.id;
    await _tapRecognize(h);
    expect(runs, [kMathInkActionId]);
    expect(h.content.single.id, isNot(before));
    h.notifier.undo();
    await h.tester.pump();
    expect(h.content.single.id, before);
    await _save(h);
  }, overrides: _router(const RegionProbs(0.05, 0.9, 0.03, 0.02)));

  testEditor('Recognize sends a circuit to the tidy-up', (h) async {
    await _selectScribble(h);
    await _tapRecognize(h);
    expect(runs, [kCircuitTidyActionId]);
    await _save(h);
  }, overrides: _router(const RegionProbs(0.05, 0.05, 0.85, 0.05)));

  testEditor('an unsure verdict asks, and the pick runs', (h) async {
    await _selectScribble(h);
    await _tapRecognize(h);
    expect(runs, isEmpty);
    expect(find.text('Recognize as'), findsOneWidget);
    await h.tester.tap(find.byKey(const Key('recognizeAs:circuit')));
    await h.tester.pumpAndSettle();
    expect(runs, [kCircuitTidyActionId]);
    await _save(h);
  }, overrides: _router(const RegionProbs(0.3, 0.4, 0.2, 0.1)));

  testEditor('text is left alone with a note', (h) async {
    await _selectScribble(h);
    final before = h.content.single.id;
    await _tapRecognize(h);
    expect(runs, isEmpty);
    expect(h.content.single.id, before);
    expect(find.textContaining('searchable'), findsOneWidget);
  }, overrides: _router(const RegionProbs(0.9, 0.05, 0.03, 0.02)));

  testEditor('Recognize sits in the action bar; More holds no recognizer', (h) async {
    await _selectScribble(h);
    await h.tester.pump(const Duration(milliseconds: 300));
    expect(find.descendant(of: _bar, matching: find.text('Recognize')), findsOneWidget);
    await h.tester.tap(find.descendant(of: _bar, matching: find.text('More')));
    await h.tester.pumpAndSettle();
    expect(find.text(kMathInkActionId), findsNothing);
    expect(find.text(kCircuitTidyActionId), findsNothing);
    expect(find.text('Recognize'), findsOneWidget); // the bar's, under the sheet
  }, overrides: _router(const RegionProbs(0.05, 0.9, 0.03, 0.02)));

  testEditor('no recognizer module, no Recognize', (h) async {
    await _selectScribble(h);
    await h.tester.pump(const Duration(milliseconds: 300));
    expect(find.descendant(of: _bar, matching: find.text('Recognize')), findsNothing);
  }, overrides: _router(const RegionProbs(0.05, 0.9, 0.03, 0.02), modules: false));

  testEditor('Change undoes the formula and re-recognizes it as a circuit, one undo step',
      (h) async {
    await _selectScribble(h);
    final before = h.content.single.id;
    await _tapRecognize(h);
    expect(runs, [kMathInkActionId]);
    expect(find.text('Recognized as a formula'), findsOneWidget);
    await h.tester.tap(find.text('Change'));
    await h.tester.pumpAndSettle();
    // The ink is back and selected, the pick sheet is open.
    expect(h.content.single.id, before);
    expect(h.state.lassoSelection?.selectedIds, [before]);
    await h.tester.tap(find.byKey(const Key('recognizeAs:circuit')));
    await h.tester.pumpAndSettle();
    expect(runs, [kMathInkActionId, kCircuitTidyActionId]);
    expect(find.text('Recognized as a circuit'), findsOneWidget);
    expect(h.content.single.id, isNot(before));
    h.notifier.undo();
    await h.tester.pump();
    expect(h.content.single.id, before);
    await _save(h);
  }, overrides: _router(const RegionProbs(0.05, 0.9, 0.03, 0.02)));

  testEditor('Change after another edit leaves that edit alone', (h) async {
    await _selectScribble(h);
    await _tapRecognize(h);
    final converted = h.content.single.id;
    h.notifier.selectAll();
    h.notifier.deleteSelection();
    await h.tester.pump();
    expect(h.content, isEmpty);
    await h.tester.tap(find.text('Change'));
    await h.tester.pumpAndSettle();
    expect(h.content, isEmpty);
    expect(find.text('Recognize as'), findsNothing);
    h.notifier.undo();
    await h.tester.pump();
    expect(h.content.single.id, converted);
    await _save(h);
  }, overrides: _router(const RegionProbs(0.05, 0.05, 0.85, 0.05)));

  testEditor('on a phone Recognize leads the bar and Duplicate moves into More', (h) async {
    await _selectScribble(h, at: const Offset(-50, -100));
    await h.tester.pump(const Duration(milliseconds: 300));
    final bar = h.tester.getRect(_bar);
    final rec = h.tester.getRect(find.descendant(of: _bar, matching: find.text('Recognize')));
    expect(bar.contains(rec.center), isTrue);
    expect(find.descendant(of: _bar, matching: find.text('Duplicate')), findsNothing);
    // The test font is far wider than a real one: the bar scrolls here.
    final more = find.descendant(of: _bar, matching: find.text('More'));
    await h.tester.ensureVisible(more);
    await h.tester.pumpAndSettle();
    await h.tester.tap(more);
    await h.tester.pumpAndSettle();
    final copies = h.content.length;
    await h.tester.tap(find.text('Duplicate'));
    await h.tester.pumpAndSettle();
    expect(h.content.length, copies + 1);
    await _save(h);
  }, size: const Size(400, 800), overrides: _router(const RegionProbs(0.05, 0.9, 0.03, 0.02)));
}
