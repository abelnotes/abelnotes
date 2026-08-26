import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/features/canvas/presentation/text_editor_dialog.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/main.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/ui/editor/hw_editor_chrome.dart';
import 'package:abelnotes/ui/primitives/sync_badge.dart';
import 'package:abelnotes/ui/screens/library_screen.dart';
import 'package:abelnotes/ui/screens/settings_screen.dart';

/// Phone widths that used to break the editor chrome, and the system font
/// scales a user can pick in the OS accessibility settings.
const _widths = [320.0, 360.0, 412.0];
const _scales = [1.0, 1.3, 1.6];

/// The editor insets the dock by 16px on each side (see canvas_screen).
const double _sideInset = 16;

final _overflows = <String>[];

/// Drains the frame's exceptions, keeping the layout overflows.
void collect(WidgetTester tester, String name, double w, double s) {
  var e = tester.takeException();
  while (e != null) {
    final msg = e.toString();
    if (msg.contains('overflowed')) {
      _overflows.add('$name w=${w.toInt()} scale=$s :: ${msg.trim()}');
    }
    e = tester.takeException();
  }
}

Widget _app(double s, Widget home, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (ctx, c) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)),
        child: c!,
      ),
      home: home,
    ),
  );
}

/// Library list backed by fixed entries — the real one needs a database.
class _FakeLibrary extends NotebookListNotifier {
  _FakeLibrary(super.ref) {
    state = AsyncValue.data([
      for (var i = 0; i < 6; i++)
        NotebookEntry(
          metadata: NotebookMetadata(
            id: 'nb$i',
            title: i.isEven
                ? 'Appunti di Analisi Matematica II — Serie di Fourier'
                : 'Quaderno $i',
            createdAt: DateTime(2026, 1, 1),
            modifiedAt: DateTime(2026, 8, 20),
            pageCount: 120 + i,
          ),
          remotePath: '/nb$i.abelnote',
          isLocal: i.isOdd,
        ),
    ]);
  }
  @override
  Future<void> refresh({bool showProgress = true}) async {}
  @override
  Future<void> retryPendingUploads() async {}
}

void main() {
  tearDown(() {
    expect(_overflows, isEmpty, reason: _overflows.join('\n'));
    _overflows.clear();
  });

  group('editor chrome', () {
    testWidgets('fits every phone width and font scale', (tester) async {
      addTearDown(tester.view.reset);
      for (final w in _widths) {
        for (final s in _scales) {
          tester.view.physicalSize = Size(w, 800);
          tester.view.devicePixelRatio = 1.0;

          Future<void> pump(String name, Widget child) async {
            await tester.pumpWidget(
                _app(s, Scaffold(body: Column(children: [child]))));
            collect(tester, name, w, s);
          }

          await pump(
            'TopBar',
            HwEditorTopBar(
              notebookTitle: 'Appunti di Analisi Matematica II',
              coverColor: const Color(0xFF884422),
              currentPage: 12,
              totalPages: 240,
              dirty: true,
              canUndo: true,
              canRedo: true,
              syncState: HwSyncState.pending,
              onBack: () {},
              onUndo: () {},
              onRedo: () {},
              onPagesTap: () {},
              onAddPage: () {},
              onSymbolsTap: () {},
              onExportTap: () {},
              onMoreTap: () {},
              touchDraws: true,
              onToggleTouchDraws: () {},
            ),
          );

          await pump(
            'PageStrip',
            HwBottomPageStrip(
              chapterLabel: 'Capitolo 3 — Serie di Fourier',
              pageNumbers: List.generate(30, (i) => i + 1),
              currentPage: 4,
              previousPage: 2,
              onPageTap: (_) {},
              onAllPagesTap: () {},
              onCollapse: () {},
            ),
          );

          await pump(
            'ToolPopup',
            HwToolPopup(
              tool: CanvasTool.pen,
              color: const Color(0xFF000000),
              onColorChanged: (_) {},
              thickness: 2,
              onThicknessChanged: (_) {},
              presetColors: const [
                Color(0xFF000000),
                Color(0xFF1155CC),
                Color(0xFFCC0000),
                Color(0xFF008844),
                Color(0xFFFF8800),
                Color(0xFF8844CC),
              ],
              onClose: () {},
              penPresets: const [null, null, null],
            ),
          );

          await pump(
            'ToolPopupEraser',
            HwToolPopup(
              tool: CanvasTool.eraserStroke,
              color: const Color(0xFF000000),
              onColorChanged: (_) {},
              thickness: 2,
              onThicknessChanged: (_) {},
              presetColors: const [Color(0xFF000000)],
              onClose: () {},
              eraserSize: EraserSize.medium,
              onEraserSizeChanged: (_) {},
              eraserPerStroke: true,
              onEraserPerStrokeChanged: (_) {},
            ),
          );
        }
      }
    });

    testWidgets('tool dock fits its band', (tester) async {
      addTearDown(tester.view.reset);
      for (final w in _widths) {
        final band = w - _sideInset * 2;
        tester.view.physicalSize = Size(w, 800);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(_app(
          1.0,
          Scaffold(
            body: Center(
              child: SizedBox(
                width: band,
                child: Align(
                  child: HwFloatingDock(
                    currentTool: CanvasTool.pen,
                    onToolChanged: (_, __) {},
                    onActiveTap: (_) {},
                    activeInkColor: const Color(0xFF000000),
                    shapeGuess: false,
                    onShapeGuessChanged: (_) {},
                    position: DockPosition.bottom,
                    onDragStart: (_) {},
                    onDragUpdate: (_) {},
                    onDragEnd: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ));
        collect(tester, 'Dock', w, 1.0);
        expect(tester.getSize(find.byType(HwFloatingDock)).width,
            lessThanOrEqualTo(band + 0.5),
            reason: 'dock overflows its band on ${w}dp');
        // Buttons must stay tappable, not shrink to nothing.
        expect(HwFloatingDock.metricsFor(band).btn, greaterThanOrEqualTo(32.0));
      }
    });

    testWidgets('vertical dock in a short band', (tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        1.0,
        Scaffold(
          body: Center(
            child: SizedBox(
              height: 186, // 360 - 64 top inset - 110 bottom inset
              child: Align(
                child: HwFloatingDock(
                  currentTool: CanvasTool.pen,
                  onToolChanged: (_, __) {},
                  onActiveTap: (_) {},
                  activeInkColor: const Color(0xFF000000),
                  shapeGuess: false,
                  onShapeGuessChanged: (_) {},
                  position: DockPosition.left,
                  onDragStart: (_) {},
                  onDragUpdate: (_) {},
                  onDragEnd: (_) {},
                ),
              ),
            ),
          ),
        ),
      ));
      collect(tester, 'DockVertical', 800, 1.0);
      expect(tester.getSize(find.byType(HwFloatingDock)).height,
          lessThanOrEqualTo(186.5));
    });
  });

  testWidgets('wide page strip gives the thumbnails the whole row',
      (tester) async {
    // Regression: a loose Flexible chapter label was allotted half the free
    // width and left the unused half as a hole, so the thumbnails only got
    // half the bar on desktop.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(
      1.0,
      Scaffold(
        body: Column(children: [
          HwBottomPageStrip(
            chapterLabel: 'ESAMI (24 PAGES)',
            pageNumbers: List.generate(24, (i) => i + 1),
            currentPage: 24,
            onPageTap: (_) {},
            onAllPagesTap: () {},
          ),
        ]),
      ),
    ));
    collect(tester, 'PageStripWide', 1400, 1.0);
    final strip = tester.getRect(find.byType(HwBottomPageStrip));
    final list = tester.getRect(find.byType(ListView));
    final button = tester.getRect(find.text('All pages'));
    // The thumbnails run from just after the label to just before the
    // button, and the button itself sits against the right edge — a hole
    // anywhere in between would show up in one of these two.
    expect(list.width, greaterThan(strip.width * 0.6),
        reason: 'thumbnail strip is not using the available width');
    expect(strip.right - button.right, lessThan(60),
        reason: 'the row ends in dead space instead of the button');
  });

  testWidgets('text editor dialog', (tester) async {
    addTearDown(tester.view.reset);
    for (final w in _widths) {
      for (final s in _scales) {
        tester.view.physicalSize = Size(w, 740);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(_app(
          s,
          Builder(builder: (ctx) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showTextEditorDialog(ctx),
                  child: const Text('open'),
                ),
              ),
            );
          }),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        collect(tester, 'TextEditorDialog', w, s);
      }
    }
  });

  testWidgets('first run', (tester) async {
    addTearDown(tester.view.reset);
    for (final w in _widths) {
      for (final s in _scales) {
        tester.view.physicalSize = Size(w, 740);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(ProviderScope(
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(s)),
            child: const AbelNotesApp(),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        collect(tester, 'Onboarding', w, s);
      }
    }
  });

  testWidgets('library with notebooks', (tester) async {
    addTearDown(tester.view.reset);
    for (final w in _widths) {
      for (final s in _scales) {
        tester.view.physicalSize = Size(w, 740);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(_app(
          s,
          const LibraryScreenV2(),
          overrides: [
            notebookListProvider.overrideWith((ref) => _FakeLibrary(ref)),
          ],
        ));
        await tester.pump(const Duration(milliseconds: 300));
        collect(tester, 'Library', w, s);
      }
    }
  });

  testWidgets('the library says how many notebooks are still to upload',
      (tester) async {
    // The per-row cloud badge only answers the question if you know to hover
    // it, and after switching remotes there can be a dozen pending at once.
    SharedPreferences.setMockInitialValues({
      'app_settings_v1': jsonEncode({'sync_backend': 'drive'}),
    });
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late AppLocalizations l10n;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        notebookListProvider.overrideWith((ref) => _FakeLibrary(ref)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          l10n = AppLocalizations.of(context);
          return const LibraryScreenV2();
        }),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    collect(tester, 'PendingNotice', 412, 1.0);

    // The fake library marks the odd-numbered entries local.
    expect(find.text(l10n.libPendingUploadsDrive(3)), findsOneWidget);

    // The library arms a 2s delayed retry and a periodic background sync on
    // open. Let the delayed one fire, then dispose the tree so the periodic
    // one is cancelled — a timer left pending fails the run.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('every settings section', (tester) async {
    addTearDown(tester.view.reset);
    const sections = [
      'General',
      'Stylus & input',
      'Sync',
      'Storage',
      'Shortcuts',
      'Advanced',
      'About',
    ];
    for (final w in _widths) {
      for (final s in _scales) {
        for (final label in sections) {
          tester.view.physicalSize = Size(w, 740);
          tester.view.devicePixelRatio = 1.0;
          // A fresh key per case: the phone menu closes once a section is
          // picked, and a reused element tree would keep it closed.
          await tester.pumpWidget(
              _app(s, SettingsScreenV2(key: ValueKey('$w-$s-$label'))));
          await tester.pump(const Duration(milliseconds: 300));
          collect(tester, 'SettingsMenu', w, s);
          final item = find.text(label);
          expect(item, findsWidgets, reason: 'no "$label" entry at ${w}dp');
          await tester.tap(item.first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 400));
          collect(tester, 'Settings-$label', w, s);
        }
      }
    }
  });
}
