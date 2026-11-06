// The page size picker: orientation flips the size, a custom size keeps the
// exact value of a field the user didn't touch.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/primitives/page_size_picker.dart';

void main() {
  late List<Size> picked;

  Future<void> pump(WidgetTester tester, Size size) {
    picked = [];
    return tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: PageSizePicker(
          label: const Text('Page size'),
          size: size,
          onChanged: picked.add,
        ),
      ),
    ));
  }

  testWidgets('orientation toggle flips the size', (tester) async {
    await pump(tester, const Size(595, 842));
    await tester.tap(find.bySemanticsLabel('Landscape'));
    expect(picked, [const Size(842, 595)]);
  });

  testWidgets('a square page shows the toggle but ignores it', (tester) async {
    await pump(tester, const Size(595, 595));
    expect(find.bySemanticsLabel('Landscape'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Landscape'),
        warnIfMissed: false);
    expect(picked, isEmpty);
  });

  testWidgets('custom size: an untouched field keeps its exact value',
      (tester) async {
    await pump(tester, const Size(500, 700)); // 176.4 x 246.9 mm shown
    await tester.tap(find.textContaining('Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '200');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(picked.single.width, 500);
    expect(picked.single.height, closeTo(200 * 72 / 25.4, 1e-9));
  });
}
