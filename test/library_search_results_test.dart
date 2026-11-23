// "In your notes" on the library: rows, highlight, "Show N more", tap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/providers/notebook_provider.dart'
    show NotebookEntry;
import 'package:abelnotes/core/services/search_service.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/ui/screens/library_search_results.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

SearchHit _hit(int i, {String title = 'Circuits', String id = 'nb'}) =>
    SearchHit(
      notebookId: id,
      notebookTitle: title,
      pageNumber: i + 1,
      pageIndex: i,
      pageId: 'p$i',
      chapterId: null,
      snippet: 'the resistor value $i',
      ranges: const [(4, 12)],
      kind: SearchHitKind.text,
    );

void main() {
  Future<void> pump(WidgetTester tester, Widget child,
      {Size size = const Size(1000, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, c) => HwThemeScope(
          palette: HwPalette.paper, variant: HwThemeVariant.paper, child: c!),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));
  }

  final nb = NotebookEntry(
    metadata: NotebookMetadata(
        id: 'nb',
        title: 'Circuits',
        createdAt: DateTime(2026),
        modifiedAt: DateTime(2026)),
    remotePath: '/nb',
    notOnDevice: true,
  );

  testWidgets('rows show notebook, page and a highlighted snippet',
      (tester) async {
    SearchHit? opened;
    await pump(
        tester,
        LibrarySearchResults(
          hits: [_hit(0), _hit(4)],
          indexing: false,
          hPad: 24,
          notebooks: {'nb': nb},
          onOpen: (h) => opened = h,
        ));
    expect(find.text('In your notes'), findsOneWidget);
    expect(find.textContaining('Page 1'), findsOneWidget);
    expect(find.textContaining('Page 5'), findsOneWidget);
    expect(find.textContaining('Indexing'), findsNothing);
    // The matched span is its own bold span.
    final bold = <String>[];
    for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
      w.text.visitChildren((s) {
        if (s is TextSpan && s.style?.fontWeight == FontWeight.w700) {
          bold.add(s.text!);
        }
        return true;
      });
    }
    expect(bold, ['resistor', 'resistor']);

    await tester.tap(find.textContaining('Page 5'));
    expect(opened?.pageIndex, 4);
  });

  testWidgets('shows the first rows, then the rest on request', (tester) async {
    await pump(
        tester,
        LibrarySearchResults(
          hits: [for (var i = 0; i < 70; i++) _hit(i)],
          indexing: true,
          hPad: 24,
          notebooks: {'nb': nb},
          onOpen: (_) {},
        ));
    expect(find.text('Indexing notes…'), findsOneWidget);
    expect(find.textContaining('Page 50'), findsOneWidget);
    expect(find.textContaining('Page 51'), findsNothing);
    expect(find.text('Show 20 more'), findsOneWidget);
    await tester.ensureVisible(find.text('Show 20 more'));
    await tester.tap(find.text('Show 20 more'));
    await tester.pump();
    expect(find.textContaining('Page 70'), findsOneWidget);
    expect(find.textContaining('Show'), findsNothing);
  });

  testWidgets('a phone width neither overflows nor loses the page number',
      (tester) async {
    await pump(
        tester,
        LibrarySearchResults(
          hits: [_hit(0, title: 'A notebook with a really long title ' * 3)],
          indexing: false,
          hPad: 8,
          notebooks: {'nb': nb},
          onOpen: (_) {},
        ),
        size: const Size(360, 700));
    expect(tester.takeException(), isNull);
    expect(find.byType(LibrarySearchResults), findsOneWidget);
  });
}
