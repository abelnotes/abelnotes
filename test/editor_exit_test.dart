// Leaving the editor with Back, over a library route.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/presentation/canvas_screen.dart';

import 'support/editor_harness.dart';

void main() {
  testWidgets('a second Back while the first is still saving leaves once',
      (tester) async {
    final h = await EditorHarness.open(tester, overLibrary: true);
    await h.scribble(h.canvasCenter);
    // The first Back waits on the disk write; the second lands meanwhile.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    for (var i = 0; i < 40 && find.byType(CanvasScreen).evaluate().isNotEmpty; i++) {
      // Real time for the disk, almost none for the exit animation.
      await h.settle(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 1));
    }
    await tester.pumpAndSettle();
    expect(find.byType(CanvasScreen), findsNothing);
    // Popping twice took the library down too: a black, empty navigator.
    expect(find.text('library'), findsOneWidget);
    // Nor may it ask about unsaved changes of a notebook already closed.
    expect(find.byType(AlertDialog), findsNothing);
    await h.settle(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
