// The missing-page view can be replaced by the canvas while its confirm dialog
// is open (the page arrives); confirming afterwards must do nothing, not throw.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/missing_page_view.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

class _FakeCanvas extends CanvasNotifier {
  _FakeCanvas(super.ref) {
    final now = DateTime(2026);
    state = CanvasState(
      metadata: NotebookMetadata(
          id: 'n', title: 't', createdAt: now, modifiedAt: now),
      document: DocumentStructure(notebookId: 'n', pages: [
        PageEntry(pageId: 'a', pageNumber: 1, fileName: 'p1'),
      ]),
      pages: const {},
      remotePath: '',
    );
  }
  final deleted = <int>[];

  @override
  Future<({bool reachable, bool noServer, Set<String> goneFromServer})>
      checkMissingPages() async =>
          (reachable: false, noServer: true, goneFromServer: {'p1', 'p2'});

  @override
  void deletePage(int index) => deleted.add(index);
}

void main() {
  late _FakeCanvas canvas;
  late ValueNotifier<bool> show;

  Future<void> pump(WidgetTester tester) async {
    show = ValueNotifier(true);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        canvasProvider.overrideWith((ref) => canvas = _FakeCanvas(ref)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, v, __) => v
              ? MissingPageView(title: 'N', onBack: () {})
              : const SizedBox(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> confirmAfterDispose(WidgetTester tester, Finder action) async {
    await tester.tap(action);
    await tester.pumpAndSettle();
    final confirm = find.byType(FilledButton);
    expect(confirm, findsOneWidget);
    show.value = false;
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('delete confirmed after the view is gone does nothing',
      (tester) async {
    await pump(tester);
    await confirmAfterDispose(tester, find.byIcon(Icons.delete_outline));
    expect(canvas.deleted, isEmpty);
  });

  testWidgets('replace confirmed after the view is gone does nothing',
      (tester) async {
    await pump(tester);
    await confirmAfterDispose(
        tester, find.byIcon(Icons.note_add_outlined).first);
  });

  testWidgets('delete confirmed while the view is shown deletes the page',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(canvas.deleted, [0]);
  });
}
