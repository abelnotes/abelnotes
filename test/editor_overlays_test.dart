// The overlays drawn above the page: PDF text selection, find highlights,
// lasso handles and floating actions, element handles, sync pills.
// Pins what is on screen so building them elsewhere changes nothing.

import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/presentation/editor/pdf_selection_painter.dart';
import 'package:abelnotes/features/canvas/presentation/image_handle_overlay.dart';
import 'package:abelnotes/ui/editor/hw_editor_chrome.dart';
import 'package:abelnotes/features/search/notebook_find_bar.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/editor_harness.dart';

/// Closed loop around [r] (screen coordinates).
List<Offset> loopAround(Rect r) {
  final b = r.inflate(24);
  return [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft, b.topLeft + const Offset(0, 6)];
}

Finder painterOf<T extends CustomPainter>() =>
    find.byWidgetPredicate((w) => w is CustomPaint && w.painter is T);

List<Rect> pdfRects(WidgetTester t) => [
      for (final w in t.widgetList<CustomPaint>(painterOf<PdfSelectionPainter>()))
        ...(w.painter as PdfSelectionPainter).rects
    ];

PageData pdfPage() => const PageData(
      pageId: 'p1',
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: RenderingLayers(content: []),
      pdfTextLayer: PdfTextLayer(sourceAssetPath: 'a.png', runs: [
        PdfTextRun(text: 'Hello', x: 100, y: 100, width: 400, height: 600, chars: [
          PdfCharBox(x: 100, y: 100, width: 80, height: 600),
          PdfCharBox(x: 180, y: 100, width: 80, height: 600),
          PdfCharBox(x: 260, y: 100, width: 80, height: 600),
          PdfCharBox(x: 340, y: 100, width: 80, height: 600),
          PdfCharBox(x: 420, y: 100, width: 80, height: 600),
        ]),
      ]),
    );

void main() {
  testEditor('a tap on PDF text selects its line and offers to copy it', (h) async {
    expect(painterOf<PdfSelectionPainter>(), findsOneWidget);
    expect(pdfRects(h.tester), isEmpty);
    await h.drag([h.canvasCenter, h.canvasCenter], kind: PointerDeviceKind.mouse);
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(pdfRects(h.tester), hasLength(5));
    final r = pdfRects(h.tester).first;
    expect(r.height, greaterThan(400));
    expect(find.text('Copy'), findsOneWidget);
    // Drawing dismisses it.
    await h.scribble(h.canvasCenter + const Offset(-250, -200));
    expect(find.text('Copy'), findsNothing);
    expect(pdfRects(h.tester), isEmpty);
  }, pages: {'p1.json': pdfPage()});

  testEditor('find draws a highlight on each match and a bar at the top right', (h) async {
    h.notifier.addTextElement(const Offset(80, 120), 'hello world');
    await h.tester.pump();
    expect(find.byType(NotebookFindBar), findsNothing);
    await h.tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await h.tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await h.tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await h.tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(NotebookFindBar), findsOneWidget);
    final bar = h.tester.getRect(find.byType(NotebookFindBar));
    expect(bar.width, 440);
    expect(h.tester.getTopRight(find.byType(NotebookFindBar)).dx,
        h.surface.width - 12);
    await h.tester.enterText(find.byType(EditableText).first, 'o');
    await h.tester.pump(const Duration(milliseconds: 400));
    final p = h.tester
        .widgetList<CustomPaint>(painterOf<FindHighlightPainter>())
        .map((w) => w.painter as FindHighlightPainter)
        .single;
    expect(p.others.length + p.current.length, 2);
    expect(p.current.length, 1);
    await h.tester.enterText(find.byType(EditableText).first, 'zzz');
    await h.tester.pump(const Duration(milliseconds: 400));
    expect(painterOf<FindHighlightPainter>(), findsNothing);
    await h.settle(const Duration(seconds: 1));
    await h.tester.pump(const Duration(seconds: 2));
    await h.tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.tester.pump(const Duration(seconds: 1));
    expect(find.byType(NotebookFindBar), findsNothing);
  });

  testEditor('the find bar spans the width on a narrow editor', (h) async {
    await h.tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await h.tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await h.tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await h.tester.pump(const Duration(milliseconds: 300));
    final bar = h.tester.getRect(find.byType(NotebookFindBar));
    expect(bar.left, 12);
    expect(bar.right, h.surface.width - 12);
    await h.settle(const Duration(seconds: 1));
    await h.tester.pump(const Duration(seconds: 2));
    await h.tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.tester.pump(const Duration(seconds: 2));
  }, size: const Size(500, 800));

  testEditor('a pull in flight shows the syncing pill with its progress', (h) async {
    expect(find.text('Syncing…'), findsNothing);
    h.notifier.isPullingFromRemote.value = true;
    await h.tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Syncing…'), findsOneWidget);
    final pill = h.tester.getTopRight(find.text('Syncing…'));
    expect(pill.dx, lessThan(h.surface.width - 12));
    h.notifier.pullProgress.value = (done: 2, total: 5);
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Syncing 2/5'), findsOneWidget);
    h.notifier.isPullingFromRemote.value = false;
    await h.tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Syncing 2/5'), findsNothing);
  });

  testEditor('while pages load a thin bar shows and the page ignores touches', (h) async {
    expect(find.byType(LinearProgressIndicator), findsNothing);
    h.notifier.pagesLoading.value = true;
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await h.scribble(h.canvasCenter);
    expect(h.strokeCount, 0);
    h.notifier.pagesLoading.value = false;
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await h.scribble(h.canvasCenter);
    expect(h.strokeCount, 1);
  });

  testEditor('on an infinite page a pill brings back content panned away', (h) async {
    await h.scribble(h.canvasCenter);
    expect(find.text('Back to content'), findsNothing);
    h.notifier.setZoomAndPan(1, const Offset(5000, 5000));
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Back to content'), findsOneWidget);
    await h.tester.tap(find.text('Back to content'));
    await h.tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Back to content'), findsNothing);
  }, paperType: 'infinite');

  testEditor('a paged notebook never offers to go back to content', (h) async {
    await h.scribble(h.canvasCenter);
    h.notifier.setZoomAndPan(1, const Offset(5000, 5000));
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Back to content'), findsNothing);
  });

  // ── Lasso handles and floating actions ──

  Finder corners() => find.byWidgetPredicate((w) =>
      w is Container &&
      w.constraints == BoxConstraints.tight(const Size(14, 14)) &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).shape == BoxShape.circle);

  /// Draws a stroke at [at] and lassos it: a selection with handles.
  Future<void> lassoStroke(EditorHarness h, Offset at) async {
    await h.scribble(at);
    await h.tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await h.tester.pump(const Duration(milliseconds: 50));
    await h.drag(loopAround(Rect.fromPoints(at + const Offset(0, -6), at + const Offset(96, 6))));
    expect(h.state.lassoSelection, isNotNull);
  }

  testEditor('a lasso selection shows four corner handles, a rotate handle and an action bar',
      (h) async {
    expect(corners(), findsNothing);
    expect(find.byIcon(Icons.rotate_right_rounded), findsNothing);
    await lassoStroke(h, h.canvasCenter + const Offset(-200, -150));
    expect(corners(), findsNWidgets(4));
    final tl = h.tester.getCenter(corners().at(0));
    final tr = h.tester.getCenter(corners().at(1));
    final bl = h.tester.getCenter(corners().at(2));
    final br = h.tester.getCenter(corners().at(3));
    expect(tl.dy, tr.dy);
    expect(bl.dy, br.dy);
    expect(tl.dx, bl.dx);
    expect(tr.dx, br.dx);
    expect(tr.dx, greaterThan(tl.dx));
    expect(bl.dy, greaterThan(tl.dy));
    // The rotate handle sits above the middle of the top edge.
    final rot = h.tester.getCenter(find.byIcon(Icons.rotate_right_rounded));
    expect(rot.dx, closeTo((tl.dx + tr.dx) / 2, 1));
    expect(rot.dy, lessThan(tl.dy - 30));
    // The bar sits under the selection, whole icon set in view.
    for (final i in [
      Icons.copy_rounded,
      Icons.content_cut_rounded,
      Icons.copy_all_rounded,
      Icons.palette_rounded,
      Icons.line_weight_rounded,
      Icons.delete_outline,
      Icons.more_horiz,
      Icons.close,
    ]) {
      expect(find.byIcon(i), findsOneWidget, reason: '$i');
    }
    expect(find.byIcon(Icons.paste_rounded), findsNothing);
    expect(h.tester.getCenter(find.byIcon(Icons.copy_rounded)).dy, greaterThan(bl.dy));
    await h.tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.tester.pump(const Duration(milliseconds: 50));
    expect(corners(), findsNothing);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
  });

  testEditor('dragging a corner handle scales the selection and the handles follow',
      (h) async {
    await lassoStroke(h, h.canvasCenter + const Offset(-200, -150));
    final br0 = h.tester.getCenter(corners().at(3));
    final g = await h.tester.startGesture(br0);
    await g.moveTo(br0 + const Offset(20, 20));
    await h.tester.pump(const Duration(milliseconds: 16));
    await g.moveTo(br0 + const Offset(80, 80));
    await h.tester.pump(const Duration(milliseconds: 16));
    final live = h.tester.getCenter(corners().at(3));
    expect(live.dx, greaterThan(br0.dx + 20));
    await g.up();
    await h.tester.pump(const Duration(milliseconds: 50));
    expect(h.state.lassoSelection!.scale, greaterThan(1.3));
    expect(h.tester.getCenter(corners().at(3)).dx, greaterThan(br0.dx + 20));
  });

  testEditor('dragging the rotate handle turns the selection', (h) async {
    await lassoStroke(h, h.canvasCenter + const Offset(-200, -150));
    final rot0 = h.tester.getCenter(find.byIcon(Icons.rotate_right_rounded));
    final g = await h.tester.startGesture(rot0);
    for (var i = 1; i <= 6; i++) {
      await g.moveTo(rot0 + Offset(i * 30.0, i * 6.0));
      await h.tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await h.tester.pump(const Duration(milliseconds: 50));
    expect(h.state.lassoSelection!.rotation.abs(), greaterThan(0.1));
  });

  testEditor('the action bar copies, duplicates, deletes and closes', (h) async {
    await lassoStroke(h, h.canvasCenter + const Offset(-200, -150));
    await h.tester.tap(find.byIcon(Icons.copy_rounded));
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(h.state.clipboard, isNotNull);
    expect(find.text('Selection copied'), findsOneWidget);
    expect(find.byIcon(Icons.paste_rounded), findsOneWidget);
    await h.tester.tap(find.byIcon(Icons.copy_all_rounded));
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(h.strokeCount, 2);
    expect(find.text('Selection duplicated'), findsOneWidget);
    await h.tester.tap(find.byIcon(Icons.delete_outline));
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(h.strokeCount, 1);
    expect(h.state.lassoSelection, isNull);
    await h.tester.pump(const Duration(seconds: 2));
  });

  testEditor('the action bar cuts and the close button drops the selection', (h) async {
    await lassoStroke(h, h.canvasCenter + const Offset(-200, -150));
    await h.tester.tap(find.byIcon(Icons.close));
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(h.state.lassoSelection, isNull);
    expect(h.strokeCount, 1);
    await h.drag(loopAround(Rect.fromPoints(h.canvasCenter + const Offset(-200, -156),
        h.canvasCenter + const Offset(-104, -144))));
    await h.tester.tap(find.byIcon(Icons.content_cut_rounded));
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(h.strokeCount, 0);
    expect(find.text('Selection cut'), findsOneWidget);
    await h.tester.pump(const Duration(seconds: 2));
  });

  testEditor('near a bottom dock the action bar moves above the selection', (h) async {
    await lassoStroke(h, Offset(h.canvasCenter.dx - 200, h.surface.height - 210));
    final dock = h.tester.getRect(find.byType(HwFloatingDock));
    final bar = h.tester.getRect(find.byIcon(Icons.copy_rounded));
    expect(bar.overlaps(dock), isFalse);
    expect(bar.bottom, lessThan(dock.top + 1));
  });

  // ── Handles of a selected element ──

  PageData elementsPage() => const PageData(
        pageId: 'p1',
        pageNumber: 1,
        width: 595,
        height: 842,
        layers: RenderingLayers(content: [
          ContentElement.shape(
            id: 'sh',
            zIndex: 1,
            data: ShapeData(
                shapeType: 'rectangle', x1: 100, y1: 100, x2: 300, y2: 200),
          ),
          ContentElement.text(
            id: 'tx',
            zIndex: 2,
            data: TextData(
                x: 100, y: 300, width: 200, height: 40, content: 'hello'),
          ),
        ]),
      );

  ImageHandleOverlay overlay(EditorHarness h) =>
      h.tester.widget<ImageHandleOverlay>(find.byType(ImageHandleOverlay));

  testEditor('a selected shape gets handles that move, resize and rotate it', (h) async {
    expect(find.byType(ImageHandleOverlay), findsNothing);
    h.notifier.selectElement('sh');
    await h.tester.pump();
    var o = overlay(h);
    expect(o.rotation, 0);
    expect(o.onCrop, isNull);
    expect(o.onToggleLock, isNull);
    expect(o.onFontLarger, isNull);
    expect(o.bounds.width, greaterThan(150));
    expect(o.bounds.height * 2, closeTo(o.bounds.width, 1.0));
    final w0 = o.bounds.width;
    // Move by a screen delta: the shape shifts by that over the page scale.
    o.onDragStart!();
    o.onMove(const Offset(60, 0));
    await h.tester.pump();
    expect(overlay(h).bounds.left, closeTo(o.bounds.left + 60, 0.5));
    o.onDragEnd!();
    await h.tester.pump();
    var sh = h.content.firstWhere((e) => e.id == 'sh') as ShapeElement;
    expect(sh.data.x1, greaterThan(100));
    expect(sh.data.x2 - sh.data.x1, closeTo(200, 0.01));
    // Resize to twice the width.
    o = overlay(h);
    o.onDragStart!();
    o.onResize(Rect.fromLTWH(o.bounds.left, o.bounds.top, o.bounds.width * 2, o.bounds.height));
    await h.tester.pump();
    expect(overlay(h).bounds.width, closeTo(w0 * 2, 0.5));
    o.onDragEnd!();
    await h.tester.pump();
    sh = h.content.firstWhere((e) => e.id == 'sh') as ShapeElement;
    expect(sh.data.x2 - sh.data.x1, closeTo(400, 0.5));
    // Rotate.
    o = overlay(h);
    o.onDragStart!();
    o.onRotate(0.5);
    await h.tester.pump();
    expect(overlay(h).rotation, closeTo(0.5, 1e-9));
    o.onDragEnd!();
    await h.tester.pump();
    sh = h.content.firstWhere((e) => e.id == 'sh') as ShapeElement;
    expect(sh.data.rotation, closeTo(0.5, 1e-9));
    // Z order, deselect, delete.
    o.onSendToBack!();
    o.onBringToFront!();
    o.onDeselect();
    await h.tester.pump();
    expect(find.byType(ImageHandleOverlay), findsNothing);
    h.notifier.selectElement('sh');
    await h.tester.pump();
    overlay(h).onDelete();
    await h.tester.pump();
    expect(h.content.any((e) => e.id == 'sh'), isFalse);
    expect(find.byType(ImageHandleOverlay), findsNothing);
  }, pages: {'p1.json': elementsPage()});

  testEditor('a selected text box offers font buttons and no picture actions', (h) async {
    h.notifier.selectElement('tx');
    await h.tester.pump();
    final o = overlay(h);
    expect(o.onFontSmaller, isNotNull);
    expect(o.onFontLarger, isNotNull);
    expect(o.onCrop, isNull);
    expect(o.onCopy, isNull);
    expect(o.onFlipHorizontal, isNull);
    expect(o.onEditMath, isNull);
    final before = (h.content.firstWhere((e) => e.id == 'tx') as TextElement).data.fontSize;
    o.onFontLarger!();
    await h.tester.pump();
    final after = (h.content.firstWhere((e) => e.id == 'tx') as TextElement).data.fontSize;
    expect(after, closeTo(before * 1.15, 0.01));
    o.onFontSmaller!();
    await h.tester.pump();
    expect((h.content.firstWhere((e) => e.id == 'tx') as TextElement).data.fontSize,
        closeTo(before, 0.01));
  }, pages: {'p1.json': elementsPage()});

  testEditor('a selected picture offers lock, flip, cut and comment', (h) async {
    final png = Uint8List.fromList(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));
    h.notifier.addImageElement(const Offset(100, 100), 'a.png', png, 200, 100);
    await h.tester.pump();
    final id = h.content.whereType<ImageElement>().single.id;
    h.notifier.selectElement(id);
    await h.tester.pump();
    var o = overlay(h);
    expect(o.isLocked, isFalse);
    expect(o.isFlipped, isFalse);
    expect(o.hasComment, isFalse);
    expect(o.onCrop, isNotNull);
    expect(o.onCopy, isNotNull);
    expect(o.onEditComment, isNotNull);
    expect(o.onFontLarger, isNull);
    expect(o.onTidyCircuit, isNull);
    o.onFlipHorizontal!();
    await h.tester.pump();
    expect(overlay(h).isFlipped, isTrue);
    overlay(h).onToggleLock!();
    await h.tester.pump();
    expect(overlay(h).isLocked, isTrue);
    overlay(h).onCut!();
    await h.tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Image cut'), findsOneWidget);
    expect(h.content.any((e) => e.id == id), isFalse);
    await h.tester.pump(const Duration(seconds: 2));
  });
}
