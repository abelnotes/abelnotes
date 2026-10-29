import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/editor/hw_editor_chrome.dart';

void main() {
  late List<bool> toggled;
  late List<Offset> options;

  Future<void> pumpDock(WidgetTester tester, {bool withOptions = true}) {
    toggled = [];
    options = [];
    return tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: Center(
          child: HwFloatingDock(
            currentTool: CanvasTool.pen,
            onToolChanged: (_, __) {},
            onActiveTap: (_) {},
            activeInkColor: const Color(0xFF000000),
            shapeGuess: false,
            onShapeGuessChanged: toggled.add,
            onShapeGuessSecondary: withOptions ? options.add : null,
            position: DockPosition.bottom,
          ),
        ),
      ),
    ));
  }

  Finder button() => find.bySemanticsLabel('Auto-shape · off');

  testWidgets('tap toggles auto-shape', (tester) async {
    await pumpDock(tester);
    await tester.tap(button());
    expect(toggled, [true]);
    expect(options, isEmpty);
  });

  testWidgets('long press opens the options, does not toggle', (tester) async {
    await pumpDock(tester);
    await tester.longPress(button());
    await tester.pumpAndSettle();
    expect(options, hasLength(1));
    expect(toggled, isEmpty);
  });

  testWidgets('right click opens the options', (tester) async {
    await pumpDock(tester);
    await tester.tap(button(),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    expect(options, hasLength(1));
    expect(toggled, isEmpty);
  });

  testWidgets('tooltip hints at the options only when they exist',
      (tester) async {
    await pumpDock(tester);
    expect(find.byTooltip('Auto-shape · off\nHold or right-click for options'),
        findsOneWidget);
    await pumpDock(tester, withOptions: false);
    expect(find.byTooltip('Auto-shape · off'), findsOneWidget);
  });
}
