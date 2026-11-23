// The whole editor driven by pointer events (Phase 0, Tier A of
// test/work/arch-split/PLAN.md). Each scenario asserts what reached the page
// state, so moving code around cannot change behaviour silently.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/editor_harness.dart';

/// Ctrl+[key] through the real keyboard path.
Future<void> ctrl(EditorHarness h, LogicalKeyboardKey key) async {
  await h.tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await h.tester.sendKeyEvent(key);
  await h.tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await h.tester.pump(const Duration(milliseconds: 50));
}

Future<void> key(EditorHarness h, LogicalKeyboardKey k) async {
  await h.tester.sendKeyEvent(k);
  await h.tester.pump(const Duration(milliseconds: 50));
}

Rect strokeBounds(StrokeElement e) {
  final pts = e.data.points;
  var r = Rect.fromLTWH(pts.first.x, pts.first.y, 0, 0);
  for (final q in pts) {
    r = r.expandToInclude(Rect.fromLTWH(q.x, q.y, 0, 0));
  }
  return r;
}

/// Closed loop around [r] (screen coordinates), mouse/stylus friendly.
List<Offset> loopAround(Rect r) {
  final b = r.inflate(24);
  return [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft, b.topLeft + const Offset(0, 6)];
}

void main() {
  // The web has no native drop zone around the canvas: the sheet once
  // collapsed to 0x0 there (blank pages on the PWA).
  testEditor('the page area fills the editor without a drop zone', (h) async {
    final top = h.tester.hitTestOnBinding(h.canvasCenter).path.first.target;
    expect(top, isA<RenderCustomPaint>(), reason: 'the canvas painter is under the centre');
  });

  testEditor('a pen stroke lands on the page, undo removes it, redo brings it back',
      (h) async {
    expect(h.strokeCount, 0);
    await h.scribble(h.canvasCenter);
    expect(h.strokeCount, 1);
    h.notifier.undo();
    await h.tester.pump();
    expect(h.strokeCount, 0);
    h.notifier.redo();
    await h.tester.pump();
    expect(h.strokeCount, 1);
  });

  testEditor('a finger draws by default (finger mode on)', (h) async {
    await h.scribble(h.canvasCenter, kind: PointerDeviceKind.touch);
    expect(h.strokeCount, 1);
  });

  testEditor('the stroke eraser removes the stroke under it, undo restores it', (h) async {
    final a = h.canvasCenter + const Offset(-200, -150);
    final b = h.canvasCenter + const Offset(-200, 100);
    await h.scribble(a);
    await h.scribble(b);
    expect(h.strokeCount, 2);
    final keep = h.content.whereType<StrokeElement>().last.id;
    await key(h, LogicalKeyboardKey.keyE);
    expect(h.state.currentTool, CanvasTool.eraserStroke);
    await h.drag([for (var i = 0; i <= 8; i++) a + Offset(i * 12.0, 0)]);
    expect(h.strokeCount, 1);
    expect(h.content.single.id, keep);
    await ctrl(h, LogicalKeyboardKey.keyZ);
    expect(h.strokeCount, 2);
  });

  testEditor('the highlighter draws a highlighter stroke', (h) async {
    await key(h, LogicalKeyboardKey.keyP);
    h.notifier.setTool(CanvasTool.highlighter);
    await h.tester.pump();
    await h.scribble(h.canvasCenter);
    expect(h.strokeCount, 1);
    final s = h.content.single as StrokeElement;
    expect(s.data.isHighlighter || s.data.toolType == 'highlighter', isTrue);
  });

  testEditor('lasso selects, moves, deletes and restores a stroke', (h) async {
    final a = h.canvasCenter + const Offset(-200, -150);
    final b = h.canvasCenter + const Offset(-200, 100);
    await h.scribble(a);
    await h.scribble(b);
    final ids = h.content.map((e) => e.id).toList();
    await key(h, LogicalKeyboardKey.keyL);
    expect(h.state.currentTool, CanvasTool.lasso);
    await h.drag(loopAround(Rect.fromPoints(a + const Offset(0, -6), a + const Offset(96, 6))));
    final sel = h.state.lassoSelection;
    expect(sel?.selectedIds, [ids.first]);

    final before = strokeBounds(h.content.first as StrokeElement);
    final inside = a + const Offset(48, 0);
    await h.drag([inside, inside + const Offset(30, 20), inside + const Offset(60, 40)]);
    final off = h.state.lassoSelection!.dragOffset;
    expect(off.dx, greaterThan(10));
    expect(off.dy, greaterThan(5));
    // Clicking away bakes the move into the stroke.
    await key(h, LogicalKeyboardKey.escape);
    expect(h.state.lassoSelection, isNull);
    final after = strokeBounds(h.content.first as StrokeElement);
    expect(after.left, greaterThan(before.left + 10));
    expect(after.top, greaterThan(before.top + 5));
    expect(h.content.last.id, ids.last);
    await h.drag(loopAround(Rect.fromPoints(a + const Offset(60, 34), a + const Offset(156, 46))));
    expect(h.state.lassoSelection?.selectedIds, [ids.first]);

    await key(h, LogicalKeyboardKey.delete);
    expect(h.strokeCount, 1);
    expect(h.content.single.id, ids.last);
    await ctrl(h, LogicalKeyboardKey.keyZ);
    expect(h.strokeCount, 2);
  });

  testEditor('copy and paste of a lasso selection adds a copy', (h) async {
    final a = h.canvasCenter + const Offset(-200, -150);
    await h.scribble(a);
    await key(h, LogicalKeyboardKey.keyL);
    await h.drag(loopAround(Rect.fromPoints(a + const Offset(0, -6), a + const Offset(96, 6))));
    expect(h.state.lassoSelection, isNotNull);
    await ctrl(h, LogicalKeyboardKey.keyC);
    expect(h.state.clipboard, isNotNull);
    await ctrl(h, LogicalKeyboardKey.keyV);
    await h.settle();
    if (h.state.pendingPaste) {
      await h.tester.tapAt(h.canvasCenter + const Offset(100, 100));
      await h.tester.pump(const Duration(milliseconds: 50));
    }
    expect(h.strokeCount, 2);
    final ids = h.content.map((e) => e.id).toSet();
    expect(ids.length, 2, reason: 'the copy has its own id');
  });

  testEditor('a text element holds its content and is found with Ctrl+F', (h) async {
    h.notifier.addTextElement(const Offset(80, 120), 'hello world');
    await h.tester.pump();
    final t = h.content.single as TextElement;
    expect(t.data.content, 'hello world');
    expect(t.data.x, 80);
    await ctrl(h, LogicalKeyboardKey.keyF);
    await h.tester.pump(const Duration(milliseconds: 300));
    await h.tester.enterText(find.byType(EditableText).first, 'world');
    await h.tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 of 1'), findsOneWidget);
    await h.tester.enterText(find.byType(EditableText).first, 'nothere');
    await h.tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 of 1'), findsNothing);
    await h.settle(const Duration(seconds: 1));
    await h.tester.pump(const Duration(seconds: 2));
    await h.tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.tester.pump(const Duration(seconds: 2));
  });

  testEditor('strokes stay on the page they were drawn on', (h) async {
    await h.scribble(h.canvasCenter);
    h.notifier.addPage();
    await h.tester.pump();
    expect(h.state.pageCount, 2);
    expect(h.state.currentPageIndex, 1);
    expect(h.strokeCount, 0);
    await h.scribble(h.canvasCenter);
    await h.scribble(h.canvasCenter + const Offset(0, 80));
    expect(h.strokeCount, 2);
    await key(h, LogicalKeyboardKey.arrowLeft);
    expect(h.state.currentPageIndex, 0);
    expect(h.strokeCount, 1);
    await key(h, LogicalKeyboardKey.pageDown);
    expect(h.state.currentPageIndex, 1);
    expect(h.strokeCount, 2);
  });

  testEditor('a chapter filters the page list', (h) async {
    h.notifier.addPage();
    h.notifier.addChapter('Maths');
    await h.tester.pump();
    final s = h.state;
    expect(s.pageCount, 3);
    expect(s.metadata.chapters.single.title, 'Maths');
    expect(s.activeChapterId, s.metadata.chapters.single.id);
    expect(s.filteredPageIndices, [s.currentPageIndex]);
    expect(s.document.pages[s.currentPageIndex].chapterId, s.activeChapterId);
    h.notifier.setActiveChapter(null);
    await h.tester.pump();
    expect(h.state.filteredPageIndices.length, 3);
  });

  testEditor('two fingers pinching zoom in and draw nothing', (h) async {
    final before = h.state.zoom;
    final c = h.canvasCenter;
    final g1 = await h.tester.startGesture(c + const Offset(-40, 0), kind: PointerDeviceKind.touch);
    final g2 = await h.tester.startGesture(c + const Offset(40, 0), kind: PointerDeviceKind.touch);
    await h.tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 10; i++) {
      await g1.moveTo(c + Offset(-40.0 - i * 15, 0));
      await g2.moveTo(c + Offset(40.0 + i * 15, 0));
      await h.tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await h.tester.pump(const Duration(milliseconds: 300));
    expect(h.state.zoom, greaterThan(before * 1.3));
    expect(h.strokeCount, 0);
  });

  testEditor('a palm touching while the stylus writes makes one stroke', (h) async {
    final pen = await h.tester.createGesture(kind: PointerDeviceKind.stylus);
    final c = h.canvasCenter;
    await pen.down(c);
    await h.tester.pump(const Duration(milliseconds: 16));
    final palm = await h.tester.createGesture(kind: PointerDeviceKind.touch);
    await palm.down(c + const Offset(150, 150));
    await h.tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 12; i++) {
      await pen.moveTo(c + Offset(i * 8.0, i.isEven ? -6 : 6));
      await palm.moveTo(c + Offset(150, 150.0 + i * 3));
      await h.tester.pump(const Duration(milliseconds: 16));
    }
    await pen.up();
    await palm.up();
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(h.strokeCount, 1);
    // The stroke follows the stylus, not the palm 150 px away.
    final b = strokeBounds(h.content.single as StrokeElement);
    expect(b.width, greaterThan(30));
    expect(b.height, lessThan(30));
  });

  testEditor('a mouse drag selects instead of drawing by default', (h) async {
    final a = h.canvasCenter + const Offset(-200, -100);
    await h.scribble(a);
    expect(h.container.read(appSettingsProvider).mouseDraws, isFalse);
    await h.drag(loopAround(Rect.fromPoints(a + const Offset(0, -6), a + const Offset(96, 6))),
        kind: PointerDeviceKind.mouse);
    expect(h.strokeCount, 1, reason: 'the mouse drew nothing');
    expect(h.state.lassoSelection?.selectedIds, [h.content.single.id]);
  });

  testEditor('a mouse drag draws once mouse drawing is on', (h) async {
    h.container.read(appSettingsProvider.notifier).setMouseDraws(true);
    await h.tester.pump();
    await h.scribble(h.canvasCenter, kind: PointerDeviceKind.mouse);
    expect(h.strokeCount, 1);
    expect(h.state.lassoSelection, isNull);
  });

  testEditor('presentation mode hides the chrome and Escape leaves it untouched', (h) async {
    await h.scribble(h.canvasCenter);
    final before = jsonEncode(h.content.map((e) => e.toJson()).toList());
    final tool = h.state.currentTool;
    await h.tester.tap(find.byTooltip('More'));
    await h.tester.pumpAndSettle();
    await h.tester.tap(find.text('Presentation mode'));
    await h.tester.pumpAndSettle();
    expect(h.state.currentTool, CanvasTool.laser);
    await key(h, LogicalKeyboardKey.escape);
    await h.tester.pump(const Duration(milliseconds: 300));
    expect(h.state.currentTool, tool);
    expect(jsonEncode(h.content.map((e) => e.toJson()).toList()), before);
  });

  testEditor('a drawn stroke reaches the local store', (h) async {
    await h.scribble(h.canvasCenter);
    final id = h.content.single.id;
    final f = File(p.join(h.files.notebookStoreDir(harnessNotebookId), AppConfig.pagesDir, 'p1.json'));
    // Autosave runs on fake timers; its file IO needs real time in between.
    String onDisk() => f.existsSync() ? f.readAsStringSync() : '';
    for (var i = 0; i < 40 && !onDisk().contains(id); i++) {
      await h.tester.pump(const Duration(milliseconds: 250));
      await h.settle(const Duration(milliseconds: 200));
    }
    expect(onDisk(), contains(id));
    expect(h.state.isDirty, isFalse);
  });
}
