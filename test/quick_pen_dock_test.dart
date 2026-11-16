import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/editor/hw_editor_chrome.dart';

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  late List<int> taps;
  late List<int> menus;

  Future<void> pumpDock(WidgetTester tester, {int? active}) {
    taps = [];
    menus = [];
    return tester.pumpWidget(_app(HwFloatingDock(
      currentTool: CanvasTool.pen,
      onToolChanged: (_, __) {},
      onActiveTap: (_) {},
      activeInkColor: const Color(0xFF000000),
      quickPens: PenPreset.defaultsFor(CanvasTool.pen),
      activeQuickPen: active,
      onQuickPenTap: taps.add,
      onQuickPenSecondary: (slot, _) => menus.add(slot),
      position: DockPosition.bottom,
    )));
  }

  Finder pen(int n) => find.bySemanticsLabel('Quick pen $n');

  testWidgets('dock shows three quick pens, no laser or auto-shape',
      (tester) async {
    await pumpDock(tester);
    for (var n = 1; n <= 3; n++) {
      expect(pen(n), findsOneWidget);
    }
    expect(find.byTooltip('Laser'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Auto-shape')), findsNothing);
  });

  testWidgets('tap applies, hold and right click open the menu',
      (tester) async {
    await pumpDock(tester);
    await tester.tap(pen(2));
    expect(taps, [1]);
    await tester.longPress(pen(3));
    expect(menus, [2]);
    await tester.tap(pen(1),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    expect(menus, [2, 0]);
    expect(taps, [1]);
  });

  test('empty slots fall back to defaults, saved ones win', () {
    const saved = PenPreset(
        tool: CanvasTool.pen, color: 0xFF00FF00, strokeWidth: 4);
    final s = const AppSettings().copyWith(toolPresets: {
      'pen': [null, saved, null],
    });
    final pens = s.quickPensFor(CanvasTool.pen);
    expect(pens.map((p) => p.color),
        [0xFF000000, 0xFF00FF00, 0xFFC62828]);
    expect(s.quickPensFor(CanvasTool.highlighter).first.opacity, 0.35);
  });

  testWidgets('tool popup carries the auto-shape switch for ink tools',
      (tester) async {
    final toggled = <bool>[];
    Widget popup(CanvasTool tool) => HwToolPopup(
          tool: tool,
          color: const Color(0xFF000000),
          onColorChanged: (_) {},
          thickness: 2,
          onThicknessChanged: (_) {},
          presetColors: const [Color(0xFF000000)],
          onClose: () {},
          shapeGuess: false,
          onShapeGuessChanged: toggled.add,
        );
    await tester.pumpWidget(_app(popup(CanvasTool.pen)));
    expect(find.text('Auto-shape'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    expect(toggled, [true]);
    await tester.pumpWidget(_app(popup(CanvasTool.lasso)));
    expect(find.text('Auto-shape'), findsNothing);
  });
}
