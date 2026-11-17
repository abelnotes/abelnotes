// Reviewing a sample by hand: one finger boxes a missed part, two fingers zoom
// without leaving a box behind, a tap corrects the part under it.
import 'dart:io';

import 'package:abelnotes/features/donate/donation_review_page.dart';
import 'package:abelnotes/features/donate/donation_sample.dart';
import 'package:abelnotes/features/donate/donation_store.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('donation_review'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The queue reads real files: load it outside the fake clock.
    final c = (await tester.runAsync(() async {
      final c = ProviderContainer(overrides: [donationDirProvider.overrideWith((ref) async => dir)]);
      await c.read(donationProvider.notifier).ready;
      return c;
    }))!;
    addTearDown(c.dispose);
    final n = c.read(donationProvider.notifier);
    const part = DonationPart('inductor', 0, 0, 100, 40, detected: 'inductor');
    n.add(DonationSample(
      id: 's',
      created: DateTime.utc(2026),
      strokes: const [
        [0, 0, 0, 0.5, 400, 0, 0, 0.5],
        [0, 300, 0, 0.5, 400, 300, 0, 0.5],
      ],
      parts: const [part],
      detected: const [part],
    ));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DonationReviewPage(sampleId: 's'),
      ),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  Finder canvas() => find.byType(CustomPaint).last;

  Future<void> pick(WidgetTester tester, String name) async {
    await tester.ensureVisible(find.text(name));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  testWidgets('one finger drags out a box for a missed part', (tester) async {
    final c = await pump(tester);
    final r = tester.getRect(canvas());
    await tester.dragFrom(r.center, const Offset(80, 60));
    await tester.pumpAndSettle();
    expect(find.text('Which part is this?'), findsOneWidget);
    // A new part: nothing to remove yet.
    expect(find.text('Remove this part'), findsNothing);
    await pick(tester, 'Resistor');
    final parts = c.read(donationProvider).queue.single.parts;
    expect([for (final p in parts) (p.symbol, p.detected)], [('inductor', 'inductor'), ('resistor', null)]);
  });

  testWidgets('two fingers zoom and add nothing', (tester) async {
    final c = await pump(tester);
    final r = tester.getRect(canvas());
    final a = await tester.startGesture(r.center - const Offset(40, 0), pointer: 1);
    final b = await tester.startGesture(r.center + const Offset(40, 0), pointer: 2);
    await tester.pump();
    for (var i = 1; i <= 5; i++) {
      await a.moveTo(r.center - Offset(40.0 + 20 * i, 0));
      await b.moveTo(r.center + Offset(40.0 + 20 * i, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(find.text('Which part is this?'), findsNothing);
    expect(c.read(donationProvider).queue.single.parts, hasLength(1));
    // Zoomed: the fit button is offered and puts the view back.
    expect(find.byTooltip('Fit to view'), findsOneWidget);
    await tester.tap(find.byTooltip('Fit to view'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Fit to view'), findsNothing);
  });

  testWidgets('a tap corrects the part under it; reviewed only on request', (tester) async {
    final c = await pump(tester);
    final r = tester.getRect(canvas());
    // The inductor's box sits at the drawing's top-left corner.
    final s = c.read(donationProvider).queue.single;
    final fit = SampleFit(s, r.size, margin: 24);
    await tester.tapAt(r.topLeft + fit.toView(50, 20));
    await tester.pumpAndSettle();
    expect(find.text('Remove this part'), findsOneWidget);
    await pick(tester, 'Resistor');
    expect(c.read(donationProvider).queue.single.parts.single.symbol, 'resistor');
    expect(c.read(donationProvider).queue.single.reviewed, isFalse);
    await tester.tap(find.text('Looks right'));
    await tester.pumpAndSettle();
    expect(c.read(donationProvider).queue.single.reviewed, isTrue);
  });
}
