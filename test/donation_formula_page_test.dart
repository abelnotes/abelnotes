// Reviewing a formula: the LaTeX is edited beside its preview, and only a
// label the receiver takes can be marked right.
import 'dart:io';

import 'package:abelnotes/features/donate/donation_formula_page.dart';
import 'package:abelnotes/features/donate/donation_sample.dart';
import 'package:abelnotes/features/donate/donation_store.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('donation_formula'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = (await tester.runAsync(() async {
      final c = ProviderContainer(overrides: [donationDirProvider.overrideWith((ref) async => dir)]);
      await c.read(donationProvider.notifier).ready;
      return c;
    }))!;
    addTearDown(c.dispose);
    final n = c.read(donationProvider.notifier);
    n.add(DonationSample(
      id: 'f',
      created: DateTime.utc(2026),
      kind: DonationKind.formula,
      strokes: const [
        [0, 0, 0, 0.5, 40, 10, 0, 0.5]
      ],
      latex: r'x^{2}',
      prompt: r'x^{2}',
    ));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FormulaReviewPage(sampleId: 'f'),
      ),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  Finder field() => find.byKey(const ValueKey('latex'));
  testWidgets('a correction is kept, previewed, and can be reset', (tester) async {
    final c = await pump(tester);
    expect(find.text('Reset'), findsNothing);
    await tester.enterText(field(), r'x^{3}');
    await tester.pumpAndSettle();
    var s = c.read(donationProvider).queue.single;
    expect([s.latex, s.prompt, s.reviewed], [r'x^{3}', r'x^{2}', false]);
    expect(find.text('Reset'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(c.read(donationProvider).queue.single.latex, r'x^{2}');
    await tester.enterText(field(), 'x^{3}\n + 1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Looks right'));
    await tester.pumpAndSettle();
    s = c.read(donationProvider).queue.single;
    // One line, as the receiver takes it.
    expect([s.latex, s.reviewed], ['x^{3} + 1', true]);
  });

  testWidgets('LaTeX that does not parse, or is not ASCII, cannot be marked right', (tester) async {
    final c = await pump(tester);
    await tester.enterText(field(), r'\frac{1}{');
    await tester.pumpAndSettle();
    expect(find.text('Not valid LaTeX: check the braces and commands'), findsOneWidget);
    await tester.tap(find.text('Looks right'));
    await tester.pumpAndSettle();
    expect(c.read(donationProvider).queue.single.reviewed, isFalse);
    await tester.enterText(field(), 'x²');
    await tester.pumpAndSettle();
    expect(find.textContaining('Plain characters only'), findsOneWidget);
    await tester.enterText(field(), r'\frac{1}{2}');
    await tester.pumpAndSettle();
    expect(find.textContaining('Plain characters only'), findsNothing);
    await tester.tap(find.text('Looks right'));
    await tester.pumpAndSettle();
    expect(c.read(donationProvider).queue.single.sendable, isTrue);
  });

  testWidgets('discard removes the sample', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(c.read(donationProvider).queue, isEmpty);
  });
}
