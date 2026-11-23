// Characterisation of the editor's pointer pipeline (pen, palm, touch, mouse,
// barrel buttons, cancel, long press). Each test asserts what happens TODAY;
// the oddities are marked "ODD:" and kept on purpose so the pipeline can move
// without changing behaviour. Raw events are used where TestGesture cannot
// change buttons mid-gesture.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/editor_harness.dart';

/// One pointer sent as raw events, so buttons can change between events.
class Ptr {
  Ptr(this.h, this.kind, this.id);
  final EditorHarness h;
  final PointerDeviceKind kind;
  final int id;
  Offset pos = Offset.zero;
  bool isDown = false;

  bool get _pen =>
      kind == PointerDeviceKind.stylus || kind == PointerDeviceKind.invertedStylus;

  Future<void> _send(PointerEvent e, [int ms = 16]) async {
    h.tester.binding.handlePointerEvent(e);
    await h.tester.pump(Duration(milliseconds: ms));
  }

  Future<void> down(Offset p, {int buttons = kPrimaryButton}) async {
    pos = p;
    isDown = true;
    await _send(PointerDownEvent(
      pointer: id,
      kind: kind,
      position: p,
      buttons: buttons,
      pressure: _pen ? 0.5 : 1,
      pressureMin: 0,
      pressureMax: 1,
    ));
  }

  Future<void> move(Offset p, {int buttons = kPrimaryButton, int ms = 16}) async {
    final d = p - pos;
    pos = p;
    await _send(
        PointerMoveEvent(
          pointer: id,
          kind: kind,
          position: p,
          delta: d,
          buttons: buttons,
          pressure: _pen ? 0.5 : 1,
          pressureMin: 0,
          pressureMax: 1,
        ),
        ms);
  }

  Future<void> up({int ms = 50}) async {
    isDown = false;
    await _send(PointerUpEvent(pointer: id, kind: kind, position: pos), ms);
  }

  Future<void> cancel({int ms = 50}) async {
    isDown = false;
    await _send(PointerCancelEvent(pointer: id, kind: kind, position: pos), ms);
  }

  /// A wavy run of [n] moves from the current position, [dx] px apart.
  Future<void> run(int n, {double dx = 8, int buttons = kPrimaryButton}) async {
    final o = pos;
    for (var i = 1; i <= n; i++) {
      await move(o + Offset(i * dx, i.isEven ? -6 : 6), buttons: buttons);
    }
  }
}

Rect boundsOf(StrokeElement e) {
  final pts = e.data.points;
  var r = Rect.fromLTWH(pts.first.x, pts.first.y, 0, 0);
  for (final q in pts) {
    r = r.expandToInclude(Rect.fromLTWH(q.x, q.y, 0, 0));
  }
  return r;
}

List<StrokeElement> strokes(EditorHarness h) => h.content.whereType<StrokeElement>().toList();

bool menuOpen(EditorHarness h) => find.byType(PopupMenuItem<String>).evaluate().isNotEmpty;

/// A page with one horizontal stroke at [at]; the eraser tests cross it.
Future<void> seedStroke(EditorHarness h, Offset at) async {
  await h.drag([for (var i = 0; i <= 12; i++) at + Offset(i * 8.0, 0)]);
  expect(h.strokeCount, 1);
}

void main() {
  group('stylus', () {
    testEditor('a stylus stroke follows the pen and keeps its pressure', (h) async {
      final c = h.canvasCenter;
      final pen = Ptr(h, PointerDeviceKind.stylus, 1);
      await pen.down(c);
      await pen.run(12);
      await pen.up();
      expect(h.strokeCount, 1);
      final s = strokes(h).single;
      expect(s.data.points.length, greaterThan(5));
      final b = boundsOf(s);
      expect(b.width, greaterThan(60));
      expect(b.height, lessThan(30));
      expect(s.data.points.every((p) => p.pressure > 0), isTrue);
      expect(h.state.currentTool, CanvasTool.pen);
    });

    testEditor('the stylus commit is deferred a few ms, then lands once', (h) async {
      final pen = Ptr(h, PointerDeviceKind.stylus, 1);
      await pen.down(h.canvasCenter);
      await pen.run(12);
      await pen.up(ms: 10);
      expect(h.strokeCount, 0, reason: 'held back for the iPad up/down glitch');
      await h.tester.pump(const Duration(milliseconds: 100));
      expect(h.strokeCount, 1);
    });

    testEditor('a stylus down right after an up, at the same spot, continues the stroke',
        (h) async {
      final c = h.canvasCenter;
      final pen = Ptr(h, PointerDeviceKind.stylus, 1);
      await pen.down(c);
      await pen.run(8);
      final end = pen.pos;
      await pen.up(ms: 10);
      await pen.down(end);
      await pen.move(end + const Offset(8, 0));
      await pen.move(end + const Offset(16, 0));
      await pen.up();
      expect(h.strokeCount, 1, reason: 'one stroke, not two');
    });

    testEditor('a stylus down far from the last up starts a second stroke', (h) async {
      final c = h.canvasCenter;
      final pen = Ptr(h, PointerDeviceKind.stylus, 1);
      await pen.down(c);
      await pen.run(8);
      await pen.up(ms: 10);
      await pen.down(c + const Offset(0, 100));
      await pen.run(8);
      await pen.up();
      expect(h.strokeCount, 2);
    });

    testEditor('with stroke continuation off the stylus commits on lift', (h) async {
      h.container.read(appSettingsProvider.notifier).setStrokeContinuation(false);
      final pen = Ptr(h, PointerDeviceKind.stylus, 1);
      await pen.down(h.canvasCenter);
      await pen.run(12);
      await pen.up(ms: 0);
      expect(h.strokeCount, 1);
    });

    testEditor('the stylus erases a stroke it crosses with the stroke eraser', (h) async {
      final c = h.canvasCenter;
      await seedStroke(h, c);
      h.notifier.setTool(CanvasTool.eraserStroke);
      await h.tester.pump();
      await h.drag([c + const Offset(40, -30), c + const Offset(40, 0), c + const Offset(40, 30)]);
      expect(h.strokeCount, 0);
      expect(h.state.currentTool, CanvasTool.eraserStroke);
    });

    testEditor('the stylus area eraser cuts a stroke in two', (h) async {
      final c = h.canvasCenter;
      await seedStroke(h, c);
      h.notifier.setTool(CanvasTool.eraserStandard);
      await h.tester.pump();
      await h.drag([c + const Offset(48, -30), c + const Offset(48, 0), c + const Offset(48, 30)]);
      final rest = strokes(h);
      expect(rest.length, 2, reason: 'left and right piece');
      expect(rest.map((s) => boundsOf(s).width).every((w) => w < 60), isTrue);
    });

    testEditor('the laser leaves nothing on the page', (h) async {
      h.notifier.setTool(CanvasTool.laser);
      await h.tester.pump();
      await h.scribble(h.canvasCenter);
      expect(h.content, isEmpty);
    });
  });

  group('barrel buttons and the inverted end', () {
    testEditor('the inverted end erases while down and the pen tool comes back', (h) async {
      final c = h.canvasCenter;
      await seedStroke(h, c);
      final eraser = Ptr(h, PointerDeviceKind.invertedStylus, 2);
      await eraser.down(c + const Offset(40, -30));
      expect(h.state.currentTool, CanvasTool.eraserStroke, reason: 'default eraser mode');
      await eraser.move(c + const Offset(40, 0));
      await eraser.move(c + const Offset(40, 30));
      await eraser.up();
      expect(h.strokeCount, 0);
      expect(h.state.currentTool, CanvasTool.pen);
    });

    testEditor('the inverted end uses the last eraser sub-mode', (h) async {
      h.notifier.setTool(CanvasTool.eraserStandard);
      h.notifier.setTool(CanvasTool.pen);
      await h.tester.pump();
      final c = h.canvasCenter;
      await seedStroke(h, c);
      final eraser = Ptr(h, PointerDeviceKind.invertedStylus, 2);
      await eraser.down(c + const Offset(48, -30));
      expect(h.state.currentTool, CanvasTool.eraserStandard);
      await eraser.move(c + const Offset(48, 0));
      await eraser.move(c + const Offset(48, 30));
      await eraser.up();
      expect(strokes(h).length, 2);
      expect(h.state.currentTool, CanvasTool.pen);
    });

    testEditor('the upper side button held from the start erases', (h) async {
      final c = h.canvasCenter;
      await seedStroke(h, c);
      final pen = Ptr(h, PointerDeviceKind.stylus, 3);
      const b = kPrimaryButton | kSecondaryStylusButton;
      await pen.down(c + const Offset(40, -30), buttons: b);
      expect(h.state.currentTool, CanvasTool.eraserStroke);
      await pen.move(c + const Offset(40, 0), buttons: b);
      await pen.move(c + const Offset(40, 30), buttons: b);
      await pen.up();
      expect(h.strokeCount, 0);
      expect(h.state.currentTool, CanvasTool.pen);
    });

    testEditor('the lower side button set to the eraser erases (#19)', (h) async {
      h.container
          .read(appSettingsProvider.notifier)
          .setPenButton(upper: false, action: PenButtonAction.eraser);
      final c = h.canvasCenter;
      await seedStroke(h, c);
      final pen = Ptr(h, PointerDeviceKind.stylus, 3);
      const b = kPrimaryButton | kPrimaryStylusButton;
      await pen.down(c + const Offset(40, -30), buttons: b);
      expect(h.state.currentTool, CanvasTool.eraserStroke);
      await pen.move(c + const Offset(40, 0), buttons: b);
      await pen.move(c + const Offset(40, 30), buttons: b);
      await pen.up();
      expect(h.strokeCount, 0);
      expect(h.state.currentTool, CanvasTool.pen);
    });

    testEditor('a side button set to none leaves the pen writing (#19)', (h) async {
      h.container
          .read(appSettingsProvider.notifier)
          .setPenButton(upper: false, action: PenButtonAction.none);
      final c = h.canvasCenter;
      final pen = Ptr(h, PointerDeviceKind.stylus, 3);
      const b = kPrimaryButton | kPrimaryStylusButton;
      await pen.down(c, buttons: b);
      expect(h.state.currentTool, CanvasTool.pen);
      await pen.move(c + const Offset(30, 10), buttons: b);
      await pen.move(c + const Offset(60, 20), buttons: b);
      await pen.up();
      await h.settle();
      expect(h.strokeCount, 1);
      expect(h.state.currentTool, CanvasTool.pen);
    });

    testEditor('the upper side button set to the lasso selects (#19)', (h) async {
      h.container
          .read(appSettingsProvider.notifier)
          .setPenButton(upper: true, action: PenButtonAction.lasso);
      final c = h.canvasCenter;
      await seedStroke(h, c);
      final pen = Ptr(h, PointerDeviceKind.stylus, 3);
      const b = kPrimaryButton | kSecondaryStylusButton;
      await pen.down(c + const Offset(-20, -20), buttons: b);
      expect(h.state.currentTool, CanvasTool.lasso);
      await pen.up();
    });

    testEditor('the inverted end erases whatever the side buttons do (#19)', (h) async {
      h.container
          .read(appSettingsProvider.notifier)
          .setPenButton(upper: true, action: PenButtonAction.none);
      final eraser = Ptr(h, PointerDeviceKind.invertedStylus, 2);
      await eraser.down(h.canvasCenter);
      expect(h.state.currentTool, CanvasTool.eraserStroke);
      await eraser.up();
    });

    testEditor('the lower side button makes a lasso selection and stays in lasso', (h) async {
      final c = h.canvasCenter;
      await seedStroke(h, c);
      final pen = Ptr(h, PointerDeviceKind.stylus, 3);
      const b = kPrimaryButton | kPrimaryStylusButton;
      final loop = [
        c + const Offset(-20, -20), c + const Offset(120, -20),
        c + const Offset(120, 20), c + const Offset(-20, 20),
      ];
      await pen.down(loop.first, buttons: b);
      expect(h.state.currentTool, CanvasTool.lasso);
      for (final p in loop.skip(1)) {
        await pen.move(p, buttons: b);
      }
      await pen.move(loop.first + const Offset(0, 6), buttons: b);
      await pen.up();
      expect(h.state.lassoSelection?.selectedIds, [h.content.single.id]);
      // The selection keeps lasso mode until it is cleared.
      expect(h.state.currentTool, CanvasTool.lasso);
      h.notifier.clearSelection();
      await h.tester.pump();
      expect(h.state.currentTool, CanvasTool.pen, reason: 'the pre-barrel tool comes back');
    });

    testEditor('a side button pressed on a lasso selection only clears it', (h) async {
      final c = h.canvasCenter;
      await seedStroke(h, c);
      h.notifier.setTool(CanvasTool.lasso);
      await h.tester.pump();
      await h.drag([
        c + const Offset(-20, -20), c + const Offset(120, -20),
        c + const Offset(120, 20), c + const Offset(-20, 20),
        c + const Offset(-20, -14),
      ]);
      expect(h.state.lassoSelection, isNotNull);
      final pen = Ptr(h, PointerDeviceKind.stylus, 3);
      await pen.down(c + const Offset(300, 100),
          buttons: kPrimaryButton | kSecondaryStylusButton);
      expect(h.state.lassoSelection, isNull);
      expect(h.state.currentTool, CanvasTool.lasso, reason: 'no override: escape first');
      await pen.up();
    });

    testEditor('a side button pressed while hovering waits for the tip', (h) async {
      final c = h.canvasCenter;
      await seedStroke(h, c);
      final pen = Ptr(h, PointerDeviceKind.stylus, 3);
      // Linux and web report the press made while hovering as a down without
      // the contact bit.
      await pen.down(c + const Offset(40, -30), buttons: kSecondaryStylusButton);
      expect(h.state.currentTool, CanvasTool.eraserStroke, reason: 'switched at once');
      await pen.move(c + const Offset(40, -10), buttons: kSecondaryStylusButton);
      expect(h.strokeCount, 1, reason: 'nothing erased while the tip is in the air');
      const touching = kPrimaryButton | kSecondaryStylusButton;
      await pen.move(c + const Offset(40, 0), buttons: touching);
      await pen.move(c + const Offset(40, 30), buttons: touching);
      await pen.up();
      expect(h.strokeCount, 0);
      expect(h.state.currentTool, CanvasTool.pen);
    });

    testEditor('a side button released in the air brings the pen back at once', (h) async {
      final c = h.canvasCenter;
      await seedStroke(h, c);
      final pen = Ptr(h, PointerDeviceKind.stylus, 3);
      // KDE Wayland: press and release while hovering, no up in between.
      await pen.down(c + const Offset(40, -30), buttons: kSecondaryStylusButton);
      expect(h.state.currentTool, CanvasTool.eraserStroke);
      await pen.move(c + const Offset(40, -20), buttons: 0);
      expect(h.state.currentTool, CanvasTool.pen, reason: 'released: no eraser left in the dock');
      await pen.move(c + const Offset(40, 0), buttons: kPrimaryButton);
      await pen.move(c + const Offset(40, 30), buttons: kPrimaryButton);
      await pen.up();
      expect(h.strokeCount, 1, reason: 'the seed survives a plain pen touch after the release');
    });

    testEditor('a side button released after an erase in the air brings the pen back', (h) async {
      final c = h.canvasCenter;
      await seedStroke(h, c);
      final pen = Ptr(h, PointerDeviceKind.stylus, 3);
      const b = kSecondaryStylusButton;
      await pen.down(c + const Offset(40, -30), buttons: b);
      await pen.move(c + const Offset(40, 0), buttons: kPrimaryButton | b);
      await pen.move(c + const Offset(40, 30), buttons: kPrimaryButton | b);
      await pen.move(c + const Offset(40, 40), buttons: b); // tip lifted
      expect(h.strokeCount, 0);
      await pen.move(c + const Offset(40, 50), buttons: 0); // button released
      expect(h.state.currentTool, CanvasTool.pen);
      await pen.up();
      expect(h.state.currentTool, CanvasTool.pen);
    });

    testEditor('a side button pressed after the tip landed switches to the eraser on the spot',
        (h) async {
      final c = h.canvasCenter;
      await seedStroke(h, c + const Offset(0, -80));
      final pen = Ptr(h, PointerDeviceKind.stylus, 3);
      await pen.down(c);
      await pen.run(6);
      const b = kPrimaryButton | kSecondaryStylusButton;
      await pen.move(pen.pos + const Offset(8, 0), buttons: b);
      expect(h.state.currentTool, CanvasTool.eraserStroke);
      // ODD: the eraser starts on the tip of the stroke just committed and
      // erases it, so only the seed stroke is left.
      expect(h.strokeCount, 1);
      expect(boundsOf(strokes(h).single).top, lessThan(200), reason: 'the seed, not the new stroke');
      await pen.move(c + const Offset(40, -80), buttons: b);
      await pen.move(c + const Offset(40, -75), buttons: b);
      await pen.up();
      expect(h.strokeCount, 0, reason: 'the eraser then crossed the seed');
      expect(h.state.currentTool, CanvasTool.pen);
    });

    testEditor('the lower side button pressed mid-stroke keeps the stroke and starts a lasso',
        (h) async {
      final c = h.canvasCenter;
      final pen = Ptr(h, PointerDeviceKind.stylus, 3);
      await pen.down(c);
      await pen.run(10);
      const b = kPrimaryButton | kPrimaryStylusButton;
      await pen.move(pen.pos + const Offset(8, 0), buttons: b);
      // The stroke is on the page at once, without waiting for the commit
      // timer, and the tool is the lasso.
      expect(h.strokeCount, 1);
      expect(h.state.currentTool, CanvasTool.lasso);
      expect(boundsOf(strokes(h).single).width, greaterThan(30));
      // The lasso now follows the pen and closes around the new stroke.
      await pen.move(pen.pos + const Offset(0, 40), buttons: b);
      await pen.move(c + const Offset(-20, 40), buttons: b);
      await pen.move(c + const Offset(-20, -20), buttons: b);
      await pen.move(c + const Offset(120, -20), buttons: b);
      await pen.up();
      expect(h.state.lassoSelection?.selectedIds, [h.content.single.id]);
      expect(h.strokeCount, 1);
    });

    testEditor('a stylus cancel while a side button is held restores the pen', (h) async {
      final c = h.canvasCenter;
      await seedStroke(h, c);
      final pen = Ptr(h, PointerDeviceKind.stylus, 3);
      const b = kPrimaryButton | kSecondaryStylusButton;
      await pen.down(c + const Offset(40, -30), buttons: b);
      await pen.move(c + const Offset(40, -10), buttons: b);
      expect(h.state.currentTool, CanvasTool.eraserStroke);
      await pen.cancel();
      expect(h.state.currentTool, CanvasTool.pen);
    });
  });

  group('palm and touch', () {
    testEditor('a touch while the stylus is down is ignored and does not undo anything',
        (h) async {
      final c = h.canvasCenter;
      final pen = Ptr(h, PointerDeviceKind.stylus, 1);
      final palm = Ptr(h, PointerDeviceKind.touch, 2);
      final zoom = h.state.zoom;
      await pen.down(c);
      await palm.down(c + const Offset(150, 150));
      await pen.run(12);
      await palm.move(c + const Offset(150, 190));
      await palm.up();
      await pen.up();
      expect(h.strokeCount, 1);
      expect(boundsOf(strokes(h).single).height, lessThan(30), reason: 'the palm adds no points');
      expect(h.state.zoom, zoom);
      // Counters stay balanced: the next stroke draws normally.
      await h.scribble(c + const Offset(0, 100));
      expect(h.strokeCount, 2);
    });

    testEditor('a palm cancelled by the OS does not tear down the stylus stroke', (h) async {
      final c = h.canvasCenter;
      final pen = Ptr(h, PointerDeviceKind.stylus, 1);
      final palm = Ptr(h, PointerDeviceKind.touch, 2);
      await pen.down(c);
      await palm.down(c + const Offset(150, 150));
      await pen.run(6);
      await palm.cancel();
      await pen.run(6);
      await pen.up();
      expect(h.strokeCount, 1);
      expect(boundsOf(strokes(h).single).width, greaterThan(60));
    });

    testEditor('a finger that landed first, then the stylus: the finger stroke is dropped, the pen draws',
        (h) async {
      final c = h.canvasCenter;
      final finger = Ptr(h, PointerDeviceKind.touch, 2);
      final pen = Ptr(h, PointerDeviceKind.stylus, 1);
      await finger.down(c + const Offset(-200, 100));
      await finger.move(c + const Offset(-190, 100));
      await pen.down(c);
      await pen.run(10);
      await pen.up();
      await finger.up();
      // ODD: with a finger already down the stylus is the second pointer, so it
      // is treated as part of a multi-touch gesture and never draws.
      expect(h.strokeCount, 0);
    });

    testEditor('two fingers pinching in zoom out and draw nothing', (h) async {
      final c = h.canvasCenter;
      h.notifier.zoomBy(2);
      await h.tester.pump();
      final before = h.state.zoom;
      final a = Ptr(h, PointerDeviceKind.touch, 1);
      final b = Ptr(h, PointerDeviceKind.touch, 2);
      await a.down(c + const Offset(-150, 0));
      await b.down(c + const Offset(150, 0));
      for (var i = 1; i <= 10; i++) {
        await a.move(c + Offset(-150.0 + i * 12, 0));
        await b.move(c + Offset(150.0 - i * 12, 0));
      }
      await a.up();
      await b.up();
      await h.tester.pump(const Duration(milliseconds: 300));
      expect(h.state.zoom, lessThan(before * 0.8));
      expect(h.strokeCount, 0);
    });

    testEditor('a second finger landing during a finger stroke cancels the stroke', (h) async {
      final c = h.canvasCenter;
      final a = Ptr(h, PointerDeviceKind.touch, 1);
      final b = Ptr(h, PointerDeviceKind.touch, 2);
      await a.down(c);
      await a.run(6);
      await b.down(c + const Offset(100, 100));
      await a.run(6);
      await b.up();
      await a.up();
      expect(h.strokeCount, 0, reason: 'a pinch, not a stroke');
    });

    testEditor('a finger draws with the pen tool and pans with the pan tool', (h) async {
      final c = h.canvasCenter;
      final f = Ptr(h, PointerDeviceKind.touch, 1);
      await f.down(c);
      await f.run(12);
      await f.up();
      expect(h.strokeCount, 1);
      h.notifier.setTool(CanvasTool.pan);
      await h.tester.pump();
      final before = h.state.panOffset;
      await f.down(c);
      await f.move(c + const Offset(0, 20));
      await f.move(c + const Offset(0, 60));
      await f.up();
      expect(h.strokeCount, 1);
      expect(h.state.panOffset.dy, greaterThan(before.dy));
    });

    testEditor('with stylus-only drawing a finger pans instead of drawing', (h) async {
      h.container.read(appSettingsProvider.notifier).setStylusOnlyDrawing(true);
      await h.tester.pump();
      final c = h.canvasCenter;
      h.notifier.zoomBy(2);
      await h.tester.pump();
      final before = h.state.panOffset;
      final f = Ptr(h, PointerDeviceKind.touch, 1);
      await f.down(c);
      await f.move(c + const Offset(0, 30));
      await f.move(c + const Offset(0, 80));
      await f.up();
      expect(h.strokeCount, 0);
      expect(h.state.panOffset, isNot(before));
    });

    testEditor('two quick finger taps with the pen tool leave two dots', (h) async {
      final c = h.canvasCenter;
      for (var i = 0; i < 2; i++) {
        final f = Ptr(h, PointerDeviceKind.touch, 1);
        await f.down(c);
        await f.up(ms: 60);
      }
      // ODD: no double-tap action for a drawing tool; each tap is a dot stroke
      // (finger dots are kept, only mouse dots are dropped).
      expect(h.strokeCount, 2);
    });
  });

  group('mouse', () {
    testEditor('a mouse click on a stroke in draw mode selects it', (h) async {
      final c = h.canvasCenter;
      await seedStroke(h, c);
      final m = Ptr(h, PointerDeviceKind.mouse, 5);
      await m.down(c + const Offset(40, 0));
      await m.up();
      expect(h.strokeCount, 1);
      expect(h.state.selectedElementId, isNotNull);
    });

    testEditor('a mouse click on empty paper draws no dot', (h) async {
      final m = Ptr(h, PointerDeviceKind.mouse, 5);
      await m.down(h.canvasCenter + const Offset(0, 200));
      await m.up();
      expect(h.content, isEmpty);
      expect(h.state.selectedElementId, isNull);
    });

    testEditor('with mouse drawing on, a click draws no dot but a drag draws', (h) async {
      h.container.read(appSettingsProvider.notifier).setMouseDraws(true);
      await h.tester.pump();
      final c = h.canvasCenter;
      final m = Ptr(h, PointerDeviceKind.mouse, 5);
      await m.down(c);
      await m.up();
      expect(h.strokeCount, 0, reason: 'a mouse dot is dropped');
      await m.down(c);
      await m.run(12);
      await m.up();
      expect(h.strokeCount, 1);
    });

    testEditor('the middle mouse button pans the page', (h) async {
      final c = h.canvasCenter;
      h.notifier.zoomBy(2);
      await h.tester.pump();
      final before = h.state.panOffset;
      final m = Ptr(h, PointerDeviceKind.mouse, 5);
      await m.down(c, buttons: kMiddleMouseButton);
      await m.move(c + const Offset(30, 0), buttons: kMiddleMouseButton);
      await m.move(c + const Offset(90, 40), buttons: kMiddleMouseButton);
      await m.up();
      expect(h.strokeCount, 0);
      expect(h.state.panOffset, isNot(before));
    });

    testEditor('a right click opens the context menu and draws nothing', (h) async {
      final m = Ptr(h, PointerDeviceKind.mouse, 5);
      await m.down(h.canvasCenter, buttons: kSecondaryMouseButton);
      await m.up();
      await h.tester.pump(const Duration(milliseconds: 300));
      expect(menuOpen(h), isTrue);
      expect(h.content, isEmpty);
    });

    testEditor('a mouse marquee in select mode ends without selecting empty paper', (h) async {
      final c = h.canvasCenter;
      final m = Ptr(h, PointerDeviceKind.mouse, 5);
      await m.down(c);
      await m.move(c + const Offset(100, 0));
      await m.move(c + const Offset(100, 100));
      await m.move(c + const Offset(0, 100));
      await m.up();
      expect(h.state.lassoSelection, isNull);
      expect(h.content, isEmpty);
    });

    testEditor('a mouse cancelled mid-marquee leaves no selection and no stuck state',
        (h) async {
      final c = h.canvasCenter;
      await seedStroke(h, c);
      final m = Ptr(h, PointerDeviceKind.mouse, 5);
      await m.down(c + const Offset(-20, -20));
      await m.move(c + const Offset(120, -20));
      await m.move(c + const Offset(120, 20));
      await m.cancel();
      expect(h.state.lassoSelection, isNull);
      // The next click still selects normally.
      await m.down(c + const Offset(40, 0));
      await m.up();
      expect(h.state.selectedElementId, isNotNull);
    });
  });

  group('lasso', () {
    testEditor('a stylus lasso selects and a drag inside moves the selection', (h) async {
      final c = h.canvasCenter;
      await seedStroke(h, c);
      h.notifier.setTool(CanvasTool.lasso);
      await h.tester.pump();
      await h.drag([
        c + const Offset(-20, -20), c + const Offset(120, -20),
        c + const Offset(120, 20), c + const Offset(-20, 20),
        c + const Offset(-20, -14),
      ]);
      expect(h.state.lassoSelection?.selectedIds, [h.content.single.id]);
      final before = boundsOf(strokes(h).single);
      final pen = Ptr(h, PointerDeviceKind.stylus, 1);
      await pen.down(c + const Offset(40, 0));
      await pen.move(c + const Offset(40, 40));
      await pen.move(c + const Offset(40, 80));
      await pen.up();
      // The drag stays in the selection transform until it is baked.
      expect(h.state.lassoSelection, isNotNull);
      h.notifier.clearSelection();
      await h.tester.pump();
      final after = boundsOf(strokes(h).single);
      expect(after.top - before.top, closeTo(80 / h.state.zoom, 12));
      expect(after.left, closeTo(before.left, 1));
    });
  });

  group('cancel', () {
    testEditor('a stylus cancel mid-stroke keeps the partial stroke', (h) async {
      final pen = Ptr(h, PointerDeviceKind.stylus, 1);
      await pen.down(h.canvasCenter);
      await pen.run(8);
      await pen.cancel();
      expect(h.strokeCount, 1);
      expect(boundsOf(strokes(h).single).width, greaterThan(40));
    });

    testEditor('a stylus cancel after a single sample leaves nothing', (h) async {
      final pen = Ptr(h, PointerDeviceKind.stylus, 1);
      await pen.down(h.canvasCenter);
      await pen.cancel();
      await h.tester.pump(const Duration(milliseconds: 200));
      expect(h.content, isEmpty);
    });

    testEditor('a finger cancel mid-stroke leaves no half stroke', (h) async {
      final f = Ptr(h, PointerDeviceKind.touch, 1);
      await f.down(h.canvasCenter);
      await f.run(8);
      await f.cancel();
      await h.tester.pump(const Duration(milliseconds: 200));
      expect(h.content, isEmpty);
    });

    testEditor('a mouse cancel mid-stroke leaves no half stroke', (h) async {
      h.container.read(appSettingsProvider.notifier).setMouseDraws(true);
      await h.tester.pump();
      final m = Ptr(h, PointerDeviceKind.mouse, 5);
      await m.down(h.canvasCenter);
      await m.run(8);
      await m.cancel();
      await h.tester.pump(const Duration(milliseconds: 200));
      expect(h.content, isEmpty);
    });

    testEditor('a touch cancel in the deferral window commits the finished stroke at once',
        (h) async {
      h.container.read(appSettingsProvider.notifier).setStylusOnlyDrawing(true);
      await h.tester.pump();
      final c = h.canvasCenter;
      final pen = Ptr(h, PointerDeviceKind.stylus, 1);
      await pen.down(c);
      await pen.run(12);
      await pen.up(ms: 5);
      expect(h.strokeCount, 0, reason: 'the pen commit is deferred');
      final finger = Ptr(h, PointerDeviceKind.touch, 2);
      await finger.down(c + const Offset(0, 200));
      await finger.cancel(ms: 5);
      // The pen already lifted: the stroke is finished and a cancel of another
      // pointer neither drops it nor makes it wait for the timer.
      expect(h.strokeCount, 1);
      await h.tester.pump(const Duration(milliseconds: 100));
      expect(h.strokeCount, 1, reason: 'committed once, not twice');
    });

    testEditor('after a cancel the next stroke draws normally', (h) async {
      final f = Ptr(h, PointerDeviceKind.touch, 1);
      await f.down(h.canvasCenter);
      await f.run(8);
      await f.cancel();
      await h.scribble(h.canvasCenter + const Offset(0, 100));
      expect(h.strokeCount, 1);
    });
  });

  group('long press', () {
    Future<void> useFingerPan(EditorHarness h) async {
      h.container.read(appSettingsProvider.notifier).setStylusOnlyDrawing(true);
      await h.tester.pump();
    }

    testEditor('a finger held still for 600 ms opens the context menu (stylus-only mode)',
        (h) async {
      await useFingerPan(h);
      final f = Ptr(h, PointerDeviceKind.touch, 1);
      await f.down(h.canvasCenter);
      await h.tester.pump(const Duration(milliseconds: 500));
      expect(menuOpen(h), isFalse);
      await h.tester.pump(const Duration(milliseconds: 200));
      expect(menuOpen(h), isTrue);
      await f.up();
    });

    testEditor('a finger that drags more than 10 px cancels the long press', (h) async {
      await useFingerPan(h);
      final f = Ptr(h, PointerDeviceKind.touch, 1);
      await f.down(h.canvasCenter);
      for (var i = 1; i <= 6; i++) {
        await f.move(h.canvasCenter + Offset(0, i * 6.0));
      }
      await h.tester.pump(const Duration(milliseconds: 800));
      expect(menuOpen(h), isFalse);
      await f.up();
    });

    testEditor('ODD: one single jump past the slop does not cancel the long press', (h) async {
      await useFingerPan(h);
      final f = Ptr(h, PointerDeviceKind.touch, 1);
      await f.down(h.canvasCenter);
      // The scale recognizer accepts on this very move and the pan re-anchor
      // swallows it before the 10 px check runs.
      await f.move(h.canvasCenter + const Offset(0, 20));
      await h.tester.pump(const Duration(milliseconds: 800));
      expect(menuOpen(h), isTrue);
      await f.up();
    });

    testEditor('a finger lifted before 600 ms opens no menu', (h) async {
      await useFingerPan(h);
      final f = Ptr(h, PointerDeviceKind.touch, 1);
      await f.down(h.canvasCenter);
      await f.up(ms: 100);
      await h.tester.pump(const Duration(milliseconds: 800));
      expect(menuOpen(h), isFalse);
    });

    testEditor('a stylus touching down cancels a pending long press', (h) async {
      await useFingerPan(h);
      final f = Ptr(h, PointerDeviceKind.touch, 1);
      final pen = Ptr(h, PointerDeviceKind.stylus, 2);
      await f.down(h.canvasCenter);
      await pen.down(h.canvasCenter + const Offset(200, 100));
      await h.tester.pump(const Duration(milliseconds: 800));
      expect(menuOpen(h), isFalse);
      await pen.up();
      await f.up();
    });

    testEditor('no long press right after the stylus wrote', (h) async {
      await useFingerPan(h);
      await h.scribble(h.canvasCenter + const Offset(0, -100));
      final f = Ptr(h, PointerDeviceKind.touch, 1);
      await f.down(h.canvasCenter);
      await h.tester.pump(const Duration(milliseconds: 800));
      expect(menuOpen(h), isFalse, reason: 'a palm during writing, 8 s grace');
      await f.up();
    });

    testEditor('a cancelled finger takes its long press with it', (h) async {
      await useFingerPan(h);
      final c = h.canvasCenter;
      final f = Ptr(h, PointerDeviceKind.touch, 1);
      await f.down(c);
      await f.cancel(ms: 100);
      // A mouse takes over before the 600 ms are up (middle button: pan).
      final m = Ptr(h, PointerDeviceKind.mouse, 5);
      await m.down(c + const Offset(300, 100), buttons: kMiddleMouseButton);
      await h.tester.pump(const Duration(milliseconds: 600));
      expect(menuOpen(h), isFalse, reason: 'the finger is gone, so is its timer');
      await m.up();
    });

    testEditor('a mouse press held down never long-presses', (h) async {
      final m = Ptr(h, PointerDeviceKind.mouse, 5);
      await m.down(h.canvasCenter);
      await h.tester.pump(const Duration(milliseconds: 800));
      expect(menuOpen(h), isFalse);
      await m.up();
    });
  });

  group('shape hold', () {
    testEditor('holding the pen still after a line turns it into a shape being adjusted',
        (h) async {
      final c = h.canvasCenter;
      final pen = Ptr(h, PointerDeviceKind.stylus, 1);
      await pen.down(c);
      for (var i = 1; i <= 20; i++) {
        await pen.move(c + Offset(i * 8.0, 0));
      }
      await h.tester.pump(const Duration(milliseconds: 400));
      expect(h.state.recognizedShape?.shapeType, 'line');
      await pen.up();
      await h.tester.pump(const Duration(milliseconds: 100));
      expect(h.content.whereType<ShapeElement>().length, 1);
      expect(h.strokeCount, 0);
    });
  });
}
