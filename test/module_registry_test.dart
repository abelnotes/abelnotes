import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/features/modules/builtin_modules.dart';
import 'package:abelnotes/features/modules/module_manifest.dart';
import 'package:abelnotes/features/modules/module_registry.dart';
import 'package:abelnotes/features/modules/selection_action.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/screens/settings_screen.dart';

class _Noop extends SelectionAction {
  const _Noop(this.id);
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
  Future<SelectionOutcome> run(SelectionRequest request) async =>
      const ActionFailed('noop');
}

int loads = 0;

AppModule fake(String id, Object? runtimeValue, {bool beta = false}) {
  final runtime = FutureProvider<Object?>((_) async {
    loads++;
    return runtimeValue;
  });
  return AppModule(
    manifest: ModuleManifest(id: id, version: '1.0.0', license: 'MIT'),
    name: (_) => id,
    description: (_) => id,
    runtime: runtime,
    actions: (_) => [_Noop('$id.act')],
    beta: beta,
  );
}

Future<ProviderContainer> container(Set<String> disabled) async {
  SharedPreferences.setMockInitialValues({
    'app_settings_v1': jsonEncode({'modules_disabled': disabled.toList()}),
  });
  final c = ProviderContainer(overrides: [
    moduleCatalogProvider.overrideWithValue([
      fake('t.ready', 'runtime'),
      fake('t.missing', null),
      fake('t.off', 'runtime'),
    ]),
  ]);
  c.read(appSettingsProvider);
  await Future<void>.delayed(Duration.zero);
  return c;
}

Future<AppLocalizations> pumpSettings(WidgetTester tester, List<AppModule> catalog) async {
  SharedPreferences.setMockInitialValues({});
  // Phone width: the desktop rail overflows under the test font.
  tester.view.physicalSize = const Size(600, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  late AppLocalizations l10n;
  await tester.pumpWidget(ProviderScope(
    overrides: [moduleCatalogProvider.overrideWithValue(catalog)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        l10n = AppLocalizations.of(context);
        return const SettingsScreenV2();
      }),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
  return l10n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('status follows runtime and the disabled set', () async {
    loads = 0;
    final c = await container({'t.off'});
    addTearDown(c.dispose);
    final sub = c.listen(moduleEntriesProvider, (_, __) {});
    expect(sub.read().map((e) => e.status), everyElement(isNot(ModuleStatus.ready)));
    await Future<void>.delayed(Duration.zero);
    final byId = {for (final e in c.read(moduleEntriesProvider)) e.module.manifest.id: e.status};
    expect(byId, {
      't.ready': ModuleStatus.ready,
      't.missing': ModuleStatus.unavailable,
      't.off': ModuleStatus.disabled,
    });
    expect(loads, 2, reason: 'a disabled module must not load its runtime');
    expect(c.read(selectionActionsProvider).map((a) => a.id), ['t.ready.act']);
  });

  test('toggling a module persists and updates actions', () async {
    final c = await container({});
    addTearDown(c.dispose);
    c.listen(selectionActionsProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    expect(c.read(selectionActionsProvider).map((a) => a.id), ['t.ready.act', 't.off.act']);

    c.read(appSettingsProvider.notifier).setModuleEnabled('t.ready', false);
    expect(c.read(selectionActionsProvider).map((a) => a.id), ['t.off.act']);
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('app_settings_v1')!) as Map<String, dynamic>;
    expect(saved['modules_disabled'], ['t.ready']);

    c.read(appSettingsProvider.notifier).setModuleEnabled('t.ready', true);
    expect(c.read(selectionActionsProvider).map((a) => a.id), ['t.ready.act', 't.off.act']);
  });

  test('switching a module off unloads its runtime', () async {
    var disposed = 0;
    final runtime = FutureProvider.autoDispose<Object?>((ref) async {
      ref.onDispose(() => disposed++);
      return 'runtime';
    });
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(overrides: [
      moduleCatalogProvider.overrideWithValue([
        AppModule(
          manifest: const ModuleManifest(id: 't.auto', version: '1.0.0', license: 'MIT'),
          name: (_) => 't.auto',
          description: (_) => 't.auto',
          runtime: runtime,
        ),
      ]),
    ]);
    addTearDown(c.dispose);
    c.listen(moduleEntriesProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    expect(c.read(moduleEntriesProvider).single.status, ModuleStatus.ready);

    c.read(appSettingsProvider.notifier).setModuleEnabled('t.auto', false);
    expect(c.read(moduleEntriesProvider).single.status, ModuleStatus.disabled);
    await Future<void>.delayed(Duration.zero);
    expect(disposed, 1);
  });

  test('circuits is a free built-in, marked Beta, off the web', () {
    final m = builtinModules.singleWhere((m) => m.manifest.id == kCircuitsModuleId);
    expect(m.beta, isTrue);
    expect(m.manifest.entitlement, ModuleEntitlement.free);
    expect(m.manifest.assets.single.license, 'AGPL-3.0, with CC BY 4.0 attribution to CGHD');
  });

  testWidgets('settings hides the section while no module exists', (tester) async {
    final l10n = await pumpSettings(tester, const []);
    expect(find.text(l10n.setSectionModules), findsNothing);
  });

  testWidgets('settings lists modules, with a Beta chip only where asked', (tester) async {
    final l10n = await pumpSettings(tester, [
      fake('t.beta', 'runtime', beta: true),
      fake('t.stable', 'runtime'),
    ]);
    await tester.tap(find.text(l10n.setSectionModules));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('t.beta'), findsOneWidget);
    expect(find.text('t.stable'), findsOneWidget);
    expect(find.text(l10n.modBeta), findsOneWidget);
  });
}
