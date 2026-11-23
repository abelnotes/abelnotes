// Counts widget rebuilds in the editor per user action, so that moving a pill,
// the dock or a tool setting is seen to leave the page painter alone.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/presentation/canvas_screen.dart';
import 'package:abelnotes/ui/editor/hw_editor_chrome.dart';

import 'support/editor_harness.dart';

/// Rebuilds since the last [reset], by the widget that was rebuilt.
class Rebuilds {
  int screen = 0, topBar = 0, dock = 0, paint = 0;

  void install() {
    debugOnRebuildDirtyWidget = (el, builtOnce) {
      final w = el.widget;
      if (w is CanvasScreen) screen++;
      if (w is HwEditorTopBar) topBar++;
      if (w is HwFloatingDock) dock++;
      if (w.key == const ValueKey('canvas-paint')) paint++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
  }

  void reset() => screen = topBar = dock = paint = 0;

  @override
  String toString() => 'screen=$screen topBar=$topBar dock=$dock paint=$paint';
}

Future<Rebuilds> counted(EditorHarness h, String name, Future<void> Function() action) async {
  final r = Rebuilds()..install();
  await h.tester.pump(const Duration(milliseconds: 300));
  r.reset();
  await action();
  await h.tester.pump(const Duration(milliseconds: 300));
  // ignore: avoid_print
  print('REBUILDS $name: $r');
  debugOnRebuildDirtyWidget = null;
  return r;
}

void main() {
  testEditor('a tool change', (h) async {
    final r = await counted(h, 'tool change', () async {
      h.notifier.setTool(CanvasTool.highlighter);
      await h.tester.pump();
    });
    expect((r.screen, r.topBar), (0, 0));
  });

  testEditor('a placement banner shown and dismissed', (h) async {
    h.notifier.addTextElement(const Offset(80, 120), 'hello');
    await h.tester.pump();
    final id = h.content.last.id;
    final r = await counted(h, 'banner show+hide', () async {
      h.notifier.duplicateElement(id);
      await h.tester.pump(const Duration(milliseconds: 100));
      expect(h.state.pendingPaste, isTrue);
      h.notifier.cancelPendingPaste();
      await h.tester.pump(const Duration(milliseconds: 100));
    });
    expect((r.screen, r.topBar, r.dock, r.paint), (0, 0, 0, 0));
  });

  testEditor('a dock drag to another edge', (h) async {
    final grip = find.byTooltip('Drag to move the toolbar').first;
    final from = h.tester.getCenter(grip);
    final to = Offset(40, h.surface.height / 2);
    await counted(h, 'dock drag', () async {
      final g = await h.tester.startGesture(from);
      await g.moveTo(from + (to - from) / (to - from).distance * 30);
      await h.tester.pump(const Duration(milliseconds: 16));
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 8)!);
        await h.tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await h.tester.pump(const Duration(seconds: 2));
    });
  });

  testEditor('a lasso selection', (h) async {
    final at = h.canvasCenter + const Offset(-200, -150);
    await h.scribble(at);
    await h.tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await h.tester.pump(const Duration(milliseconds: 50));
    final b = Rect.fromPoints(at + const Offset(0, -6), at + const Offset(96, 6)).inflate(24);
    final r = await counted(h, 'lasso select', () async {
      await h.drag([b.topLeft, b.topRight, b.bottomRight, b.bottomLeft, b.topLeft + const Offset(0, 6)]);
      expect(h.state.lassoSelection, isNotNull);
    });
    expect((r.screen, r.topBar), (0, 0));
  });

  testEditor('one pen stroke', (h) async {
    await counted(h, 'stroke', () => h.scribble(h.canvasCenter));
  });

  testEditor('a setting the editor does not show', (h) async {
    final r = await counted(h, 'unrelated setting', () async {
      h.container.read(appSettingsProvider.notifier).setTapUndo(false);
      await h.tester.pump();
    });
    expect((r.screen, r.topBar, r.dock, r.paint), (0, 0, 0, 0));
  });

  testEditor('the tool panel opened and closed from the dock', (h) async {
    final pen = find.byTooltip('Pen · P').first;
    final r = await counted(h, 'tool panel open+close', () async {
      await h.tester.tap(pen);
      await h.tester.pump(const Duration(milliseconds: 300));
      await h.tester.tap(pen);
      await h.tester.pump(const Duration(milliseconds: 300));
    });
    expect((r.screen, r.topBar, r.paint), (0, 0, 0));
  });

  testEditor('a touch drag that shows the page swipe hint', (h) async {
    h.notifier.setTool(CanvasTool.pan);
    await h.tester.pump();
    final c = h.canvasCenter;
    await counted(h, 'page swipe hint', () async {
      final g = await h.tester.startGesture(c, kind: PointerDeviceKind.touch);
      await g.moveBy(const Offset(-20, 0));
      await h.tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(-50, 0));
        await h.tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await h.tester.pump(const Duration(milliseconds: 100));
    });
  });

  testEditor('a pan of the page', (h) async {
    await counted(h, 'pan', () async {
      h.notifier.setPanOffset(const Offset(30, 40));
      await h.tester.pump();
    });
  });
}
