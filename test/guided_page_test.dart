// The guided page: ink written to a prompt goes to the queue with the
// prompt as its label; a palm after the pen leaves nothing.
import 'dart:io';
import 'dart:math' as math;

import 'package:abelnotes/features/donate/donation_sample.dart';
import 'package:abelnotes/features/donate/donation_store.dart';
import 'package:abelnotes/features/donate/guided/guided_page.dart';
import 'package:abelnotes/features/donate/guided/guided_prompts.dart';
import 'package:abelnotes/features/donate/guided/writing_pad.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('guided'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<ProviderContainer> pump(WidgetTester tester, {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = (await tester.runAsync(() async {
      final c = ProviderContainer(overrides: [donationDirProvider.overrideWith((ref) async => dir)]);
      await c.read(donationProvider.notifier).ready;
      return c;
    }))!;
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            HwThemeScope(palette: HwPalette.paper, variant: HwThemeVariant.paper, child: child!),
        home: GuidedPage(prompts: GuidedPrompts(math.Random(11))),
      ),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> write(WidgetTester tester, Offset from, {PointerDeviceKind kind = PointerDeviceKind.stylus}) async {
    final g = await tester.startGesture(from, kind: kind, buttons: kind == PointerDeviceKind.stylus ? kPrimaryButton : kPrimaryButton);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(from + Offset(10.0 * i, 4.0 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump();
  }

  testWidgets('Next keeps the ink with the prompt as its label, then shows a new prompt', (tester) async {
    final c = await pump(tester);
    final pad = tester.getCenter(find.byKey(const ValueKey('pad')));
    await write(tester, pad - const Offset(60, 0));
    await write(tester, pad);
    // A finger after the pen: a palm, not ink.
    await write(tester, pad + const Offset(0, 80), kind: PointerDeviceKind.touch);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    final s = c.read(donationProvider).queue.single;
    expect([s.kind, s.toWire()['source'], s.sendable, s.strokes.length], [DonationKind.formula, 'guided', true, 2]);
    expect(latexProblem(s.latex), isNull);
    // Pad width maps to kPadUnits: 80 px of ink across a 358 px pad.
    final padWidth = tester.getSize(find.byKey(const ValueKey('pad'))).width;
    expect(s.strokes.first[32], closeTo(80 * kPadUnits / padWidth, 0.2));
    expect(find.text('Review and send (1)'), findsOneWidget);
  });

  testWidgets('a circuit symbol is labelled with its class and a box round the ink', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.text('Circuit symbols'));
    await tester.pumpAndSettle();
    expect(find.text('DRAW JUST THE SYMBOL, WITH SHORT LEADS'), findsWidgets);
    final pad = tester.getCenter(find.byKey(const ValueKey('pad')));
    // A finger writes when no pen was seen.
    await write(tester, pad, kind: PointerDeviceKind.touch);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    final s = c.read(donationProvider).queue.single;
    expect(s.kind, DonationKind.circuit);
    expect(kGuidedSymbols, contains(s.parts.single.symbol));
    expect([s.parts.single.x, s.parts.single.y], [0, 0]);
  });

  testWidgets('Skip and an empty pad keep nothing', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.text('Next'));
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(c.read(donationProvider).queue, isEmpty);
    final pad = tester.getCenter(find.byKey(const ValueKey('pad')));
    await write(tester, pad);
    await tester.tap(find.byTooltip('Undo stroke'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(c.read(donationProvider).queue, isEmpty);
  });

  for (final size in const [Size(320, 568), Size(390, 844), Size(1280, 800)]) {
    testWidgets('fits ${size.width.toInt()}x${size.height.toInt()} without overflow', (tester) async {
      await pump(tester, size: size);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Circuit symbols'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
