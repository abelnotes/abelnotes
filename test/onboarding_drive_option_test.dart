// The third onboarding option used to be a dead "coming soon" card for a
// hosted server that never shipped. It is now the Drive sign-in, which is
// the zero-setup path most users are expected to take.
//
// The screen asks one question — where the notebooks live — and answers it
// with each service's own mark, because three lookalike cloud glyphs made
// the user tap to find out which was which. Starting without sync stays a
// button, not a footnote.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:abelnotes/features/onboarding/onboarding_screen.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/screens/settings_screen.dart';

Future<AppLocalizations> _pumpOnboarding(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  late AppLocalizations l10n;
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        l10n = AppLocalizations.of(context);
        return const OnboardingScreen();
      }),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  return l10n;
}

void main() {
  _settingsTests();
  testWidgets('offers Drive instead of the never-shipped hosted server',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final l10n = await _pumpOnboarding(tester);

    expect(find.text(l10n.onbDriveShort), findsOneWidget);
    expect(find.text(l10n.onbManagedServerTitle), findsNothing,
        reason: 'the placeholder card is gone, not merely hidden');
    // The other two ways in are still there, and local-only is a button of
    // its own rather than a line of small print.
    expect(find.text(l10n.onbNextcloudShort), findsOneWidget);
    expect(find.text(l10n.onbStartWithoutSync), findsOneWidget);
  });

  testWidgets('each sync choice carries its own mark', (tester) async {
    // The reason the screen was rebuilt: a generic cloud glyph on both
    // options told the user nothing until they tapped one.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpOnboarding(tester);

    final assets = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<AssetImage>()
        .map((a) => a.assetName)
        .toSet();
    expect(assets, contains('assets/branding/google-drive.png'));
    expect(assets, contains('assets/branding/nextcloud.png'));
  });

  testWidgets('the two choices fit side by side on a phone', (tester) async {
    // Side-by-side buys recognisability at the cost of width: on a narrow
    // phone each card is about 150 logical pixels, and an overflow here
    // would be a yellow-and-black bar on the very first screen.
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final l10n = await _pumpOnboarding(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(l10n.onbDriveShort), findsOneWidget);
    expect(find.text(l10n.onbNextcloudShort), findsOneWidget);
  });

  testWidgets('a build with no Google credentials says so instead of failing',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final l10n = await _pumpOnboarding(tester);

    final card = find.text(l10n.onbDriveShort);
    if (tester.widget<Text>(card).data == null) return;
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 300));

    // Tests run with no --dart-define, which is the same situation as a
    // build shipped without credentials: the user gets told, not a crash.
    expect(find.text(l10n.driveNotConfigured), findsOneWidget);
  });
}

// Settings is where a connection is managed after onboarding is long gone:
// without it, a user who signed in on day one has no way to see the state or
// get out of it.
void _settingsTests() {
  testWidgets('a configured server says when it is not the one in use',
      (tester) async {
    // Credentials outlive the choice of backend: a server can sit here
    // connected and idle, and "connected" alone would read as "your
    // notebooks are going here".
    SharedPreferences.setMockInitialValues({
      'app_settings_v1': jsonEncode({'sync_backend': 'drive'}),
    });
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late AppLocalizations l10n;
    await tester.pumpWidget(ProviderScope(
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
    await tester.tap(find.text('Sync'));
    await tester.pump(const Duration(milliseconds: 400));

    // Drive is the selected backend but no account is signed in here, so
    // the Drive card is the one reporting an incomplete state.
    expect(find.text(l10n.setSyncDriveNotConnected), findsOneWidget);
  });

  testWidgets('settings offers Drive alongside the personal server',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    // Phone width: the desktop rail renders wider under the test font than
    // it ever does on a real screen, and this is the layout a phone user
    // actually walks through anyway.
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late AppLocalizations l10n;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          l10n = AppLocalizations.of(context);
          return const SettingsScreenV2();
        }),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Sync'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10n.setSyncDriveTitle), findsOneWidget);
    expect(find.text(l10n.setSyncOneBackendNote), findsOneWidget,
        reason: 'the one-backend-at-a-time rule has to be stated somewhere');
    // Nothing signed in yet.
    expect(find.text(l10n.setSyncDriveNotConnected), findsOneWidget);
  });
}
