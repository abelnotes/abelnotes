// What the editor does when it is laid out or opened from a search hit: the
// page area size reaches the notebook, a pending find is taken once, the
// app-wide stroke width rule follows the setting.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/features/search/notebook_find_bar.dart';
import 'package:abelnotes/ui/primitives/file_drop_zone.dart';

import 'support/editor_harness.dart';

void main() {
  testEditor('the page area size reaches the notebook, and follows a resize', (h) async {
    Size area() => h.tester.getSize(find.byType(FileDropZone));
    expect(h.notifier.viewportSize, area());
    expect(area().width, 1280);
    expect(area().height, lessThan(800));
    h.tester.view.physicalSize = const Size(900, 700);
    await h.tester.pump();
    await h.tester.pump(const Duration(milliseconds: 50));
    expect(h.notifier.viewportSize, area());
    expect(area().width, 900);
  });

  testEditor('a search hit opened before the editor shows its find bar once', (h) async {
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(NotebookFindBar), findsOneWidget);
    expect(h.container.read(pendingFindProvider), isNull);
    final field = h.tester.widget<EditableText>(find.byType(EditableText).first);
    expect(field.controller.text, 'hello');
    // Once only: a later request for the same editor is not taken again.
    h.container.read(pendingFindProvider.notifier).state =
        (notebookId: harnessNotebookId, query: 'again');
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(h.container.read(pendingFindProvider), isNotNull);
    expect(h.tester.widget<EditableText>(find.byType(EditableText).first).controller.text,
        'hello');
    await h.settle(const Duration(seconds: 1));
    await h.tester.pump(const Duration(seconds: 2));
  }, beforeShow: (c) {
    c.read(pendingFindProvider.notifier).state =
        (notebookId: harnessNotebookId, query: 'hello');
  });

  testEditor('a search hit for another notebook is dropped, not shown', (h) async {
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(NotebookFindBar), findsNothing);
    expect(h.container.read(pendingFindProvider), isNull);
  }, beforeShow: (c) {
    c.read(pendingFindProvider.notifier).state =
        (notebookId: 'some-other-notebook', query: 'hello');
  });

  testEditor('the stroke width rule follows the speed-width setting', (h) async {
    final settings = h.container.read(appSettingsProvider.notifier);
    settings.setSpeedWidth(false);
    await h.tester.pump();
    expect(CanvasRenderEngine.speedWidth, isFalse);
    settings.setSpeedWidth(true);
    await h.tester.pump();
    expect(CanvasRenderEngine.speedWidth, isTrue);
  });
}
