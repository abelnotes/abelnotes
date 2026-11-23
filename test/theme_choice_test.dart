// Settings > theme offers Light / Paper / Dark. Paper used to be stored as
// "follow the system", so a dark OS showed Dark whenever Paper was tapped.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/screens/settings_screen.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

/// Same wiring as AbelNotesApp: the variant comes from resolveThemeVariant.
class _Harness extends ConsumerWidget {
  const _Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final variant = resolveThemeVariant(
        s.themeMode, s.themeChoice, MediaQuery.platformBrightnessOf(context));
    final palette = switch (variant) {
      HwThemeVariant.paper => HwPalette.paper,
      HwThemeVariant.light => HwPalette.light,
      HwThemeVariant.dark => HwPalette.dark,
    };
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildHwThemeData(variant),
      builder: (context, child) =>
          HwThemeScope(palette: palette, variant: variant, child: child!),
      home: const SettingsScreenV2(),
    );
  }
}

Future<void> _pump(WidgetTester tester, Brightness os,
    {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = const Size(600, 900);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.platformBrightnessTestValue = os;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(const ProviderScope(child: _Harness()));
  await tester.pump(const Duration(milliseconds: 300));
  // The phone layout opens on the section menu.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.tap(find.text('General'));
  await tester.pump(const Duration(milliseconds: 400));
}

HwThemeVariant _shown(WidgetTester tester) => HwThemeScope.variantOf(
    tester.element(find.byType(SettingsScreenV2)));

/// The tile of [label] is the one drawn with the 2px accent border.
bool _highlighted(WidgetTester tester, String label) {
  final box = tester.widget<Container>(find
      .ancestor(of: find.text(label), matching: find.byType(Container))
      .first);
  final d = box.decoration as BoxDecoration;
  return (d.border as Border).top.width == 2;
}

void main() {
  testWidgets('Paper can be chosen while the OS is dark', (tester) async {
    await _pump(tester, Brightness.dark);
    expect(_shown(tester), HwThemeVariant.dark);
    expect(_highlighted(tester, 'Dark'), isTrue);

    await tester.tap(find.text('Paper'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_shown(tester), HwThemeVariant.paper);
    expect(_highlighted(tester, 'Paper'), isTrue);
    expect(_highlighted(tester, 'Dark'), isFalse);
    expect(
        Theme.of(tester.element(find.byType(SettingsScreenV2))).brightness,
        Brightness.light);

    // Light and Dark still work from there.
    await tester.tap(find.text('Light'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_shown(tester), HwThemeVariant.light);
    await tester.tap(find.text('Dark'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_shown(tester), HwThemeVariant.dark);
  });

  testWidgets('an explicit Paper survives a restart on a dark OS',
      (tester) async {
    await _pump(tester, Brightness.dark);
    await tester.tap(find.text('Paper'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('app_settings_v1')!;
    expect((jsonDecode(stored) as Map)['theme_choice'], 'paper');

    // Fresh process: only the stored prefs remain.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, Brightness.dark,
        prefs: {'app_settings_v1': stored});
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_shown(tester), HwThemeVariant.paper);
    expect(_highlighted(tester, 'Paper'), isTrue);
  });

  testWidgets('stored system mode with no explicit choice is unchanged',
      (tester) async {
    final prefs = {
      'app_settings_v1': jsonEncode({'theme': 'system'}),
    };
    await _pump(tester, Brightness.dark, prefs: prefs);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_shown(tester), HwThemeVariant.dark);

    await tester.pumpWidget(const SizedBox());
    await _pump(tester, Brightness.light, prefs: prefs);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_shown(tester), HwThemeVariant.paper);
  });

  test('resolveThemeVariant', () {
    for (final os in Brightness.values) {
      expect(resolveThemeVariant(ThemeMode.light, null, os),
          HwThemeVariant.light);
      expect(resolveThemeVariant(ThemeMode.dark, null, os),
          HwThemeVariant.dark);
      expect(resolveThemeVariant(ThemeMode.system, ThemeChoice.paper, os),
          HwThemeVariant.paper);
      expect(resolveThemeVariant(ThemeMode.dark, ThemeChoice.light, os),
          HwThemeVariant.light);
    }
    expect(resolveThemeVariant(ThemeMode.system, null, Brightness.dark),
        HwThemeVariant.dark);
    expect(resolveThemeVariant(ThemeMode.system, null, Brightness.light),
        HwThemeVariant.paper);
  });

  test('an unknown stored choice is ignored', () async {
    SharedPreferences.setMockInitialValues({
      'app_settings_v1':
          jsonEncode({'theme': 'system', 'theme_choice': 'sepia'}),
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).ready;
    expect(c.read(appSettingsProvider).themeChoice, isNull);
  });
}
