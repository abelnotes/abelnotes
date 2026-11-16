import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/editor/hw_editor_chrome.dart';
import 'package:abelnotes/ui/primitives/sync_badge.dart';

void main() {
  test('the bar dock position survives a settings round trip', () {
    const c = ToolDockConfig(edge: 'bar', align: 0.5);
    expect(ToolDockConfig.fromJson(c.toJson()).edge, 'bar');
    expect(ToolDockConfig.fromJson({'edge': 'nowhere'}).edge, 'bottom');
  });

  testWidgets('the top bar shows docked tools in its middle', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: HwEditorTopBar(
          notebookTitle: 'A rather long notebook title for the bar',
          coverColor: Colors.teal,
          currentPage: 1,
          totalPages: 1,
          dirty: false,
          canUndo: false,
          canRedo: false,
          syncState: HwSyncState.ok,
          center: const SizedBox(key: Key('tools'), width: 400, height: 40),
        ),
      ),
    )));
    expect(find.byKey(const Key('tools')), findsOneWidget);
    expect(tester.takeException(), isNull);
    // With tools docked, the back button is an icon, not "Library".
    expect(find.text('Library'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
