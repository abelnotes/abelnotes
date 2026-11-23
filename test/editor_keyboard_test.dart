// The editor's keyboard shortcuts through the real key path: every key of the
// table, so moving the handler cannot change one silently.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/editor_harness.dart';

Future<void> press(EditorHarness h, LogicalKeyboardKey k,
    {bool ctrl = false, bool shift = false}) async {
  if (ctrl) await h.tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await h.tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await h.tester.sendKeyEvent(k);
  if (shift) await h.tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await h.tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await h.tester.pump(const Duration(milliseconds: 50));
}

Map<String, PageData> threePages() => {
      'p1.json': blankPage('p1'),
      'p2.json': blankPage('p2'),
      'p3.json': blankPage('p3'),
    };

void main() {
  testEditor('single keys pick the tools', (h) async {
    for (final (k, tool) in [
      (LogicalKeyboardKey.keyL, CanvasTool.lasso),
      (LogicalKeyboardKey.keyH, CanvasTool.pan),
      (LogicalKeyboardKey.keyT, CanvasTool.text),
      (LogicalKeyboardKey.keyB, CanvasTool.brush),
      (LogicalKeyboardKey.keyP, CanvasTool.pen),
    ]) {
      await press(h, k);
      expect(h.state.currentTool, tool, reason: '$k');
    }
    await press(h, LogicalKeyboardKey.keyE);
    expect(h.state.currentTool, h.notifier.lastEraserMode);
  });

  testEditor('Ctrl+P is not the pen shortcut', (h) async {
    await press(h, LogicalKeyboardKey.keyL);
    await press(h, LogicalKeyboardKey.keyP, ctrl: true);
    expect(h.state.currentTool, CanvasTool.lasso);
  });

  testEditor('Ctrl+Z, Ctrl+Shift+Z and Ctrl+Y undo and redo', (h) async {
    await h.scribble(h.canvasCenter);
    await press(h, LogicalKeyboardKey.keyZ, ctrl: true);
    expect(h.strokeCount, 0);
    await press(h, LogicalKeyboardKey.keyZ, ctrl: true, shift: true);
    expect(h.strokeCount, 1);
    await press(h, LogicalKeyboardKey.keyZ, ctrl: true);
    expect(h.strokeCount, 0);
    await press(h, LogicalKeyboardKey.keyY, ctrl: true);
    expect(h.strokeCount, 1);
  });

  testEditor('Ctrl plus, minus and 0 zoom', (h) async {
    final z0 = h.state.zoom;
    await press(h, LogicalKeyboardKey.equal, ctrl: true);
    expect(h.state.zoom, closeTo(z0 * 1.25, 1e-6));
    await press(h, LogicalKeyboardKey.minus, ctrl: true);
    expect(h.state.zoom, closeTo(z0, 1e-6));
    await press(h, LogicalKeyboardKey.numpadAdd, ctrl: true);
    expect(h.state.zoom, greaterThan(z0));
    await press(h, LogicalKeyboardKey.numpadSubtract, ctrl: true);
    expect(h.state.zoom, closeTo(z0, 1e-6));
    await press(h, LogicalKeyboardKey.equal, ctrl: true);
    await press(h, LogicalKeyboardKey.digit0, ctrl: true);
    expect(h.state.zoom, closeTo(z0, 1e-6));
  });

  testEditor('arrows, Page keys, Home and End move between pages', (h) async {
    expect(h.state.currentPageIndex, 0);
    await press(h, LogicalKeyboardKey.arrowRight);
    expect(h.state.currentPageIndex, 1);
    await press(h, LogicalKeyboardKey.pageDown);
    expect(h.state.currentPageIndex, 2);
    await h.tester.pump(const Duration(milliseconds: 400));
    await press(h, LogicalKeyboardKey.arrowLeft);
    expect(h.state.currentPageIndex, 1);
    await h.tester.pump(const Duration(milliseconds: 400));
    await press(h, LogicalKeyboardKey.pageUp);
    expect(h.state.currentPageIndex, 0);
    await press(h, LogicalKeyboardKey.end);
    expect(h.state.currentPageIndex, 2);
    await press(h, LogicalKeyboardKey.home);
    expect(h.state.currentPageIndex, 0);
  }, pages: threePages());

  testEditor('arrows do nothing with Ctrl held', (h) async {
    await press(h, LogicalKeyboardKey.arrowRight, ctrl: true);
    await press(h, LogicalKeyboardKey.end, ctrl: true);
    expect(h.state.currentPageIndex, 0);
  }, pages: threePages());

  testEditor('Ctrl+A selects all, Delete removes, Escape clears', (h) async {
    await h.scribble(h.canvasCenter + const Offset(-200, -100));
    await h.scribble(h.canvasCenter + const Offset(-200, 100));
    await press(h, LogicalKeyboardKey.keyA, ctrl: true);
    expect(h.state.lassoSelection?.selectedIds.length, 2);
    await press(h, LogicalKeyboardKey.escape);
    expect(h.state.lassoSelection, isNull);
    await press(h, LogicalKeyboardKey.keyA, ctrl: true);
    await press(h, LogicalKeyboardKey.backspace);
    expect(h.strokeCount, 0);
  });

  testEditor('Ctrl+D duplicates, Ctrl+C and Ctrl+X fill the clipboard', (h) async {
    await h.scribble(h.canvasCenter);
    await press(h, LogicalKeyboardKey.keyA, ctrl: true);
    await press(h, LogicalKeyboardKey.keyD, ctrl: true);
    await h.settle();
    expect(h.strokeCount, 2);
    await press(h, LogicalKeyboardKey.keyA, ctrl: true);
    await press(h, LogicalKeyboardKey.keyC, ctrl: true);
    expect(h.state.clipboard, isNotNull);
    expect(find.text('Selection copied'), findsOneWidget);
    await press(h, LogicalKeyboardKey.keyX, ctrl: true);
    expect(find.text('Selection cut'), findsOneWidget);
    expect(h.strokeCount, 0);
  });

  testEditor('Ctrl+C and Ctrl+X with nothing selected are left alone', (h) async {
    await press(h, LogicalKeyboardKey.keyC, ctrl: true);
    await press(h, LogicalKeyboardKey.keyX, ctrl: true);
    expect(find.text('Selection copied'), findsNothing);
    expect(find.text('Selection cut'), findsNothing);
  });

  testEditor('Ctrl+F opens the find bar and Escape closes it', (h) async {
    await press(h, LogicalKeyboardKey.keyF, ctrl: true);
    await h.tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(EditableText), findsWidgets);
    await press(h, LogicalKeyboardKey.escape);
    await h.tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(EditableText), findsNothing);
  });

  testEditor('? opens the shortcut sheet, / without Shift does not', (h) async {
    await press(h, LogicalKeyboardKey.slash);
    expect(find.text('Keyboard shortcuts'), findsNothing);
    await press(h, LogicalKeyboardKey.slash, shift: true);
    await h.tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
  });

  testEditor('typing in the find field is not a tool shortcut', (h) async {
    await press(h, LogicalKeyboardKey.keyF, ctrl: true);
    await h.tester.pump(const Duration(milliseconds: 300));
    final before = h.state.currentTool;
    await h.tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await h.tester.pump(const Duration(milliseconds: 50));
    expect(h.state.currentTool, before);
  });
}
