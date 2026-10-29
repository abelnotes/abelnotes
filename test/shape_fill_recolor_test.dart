// Issue #20: recolouring a filled shape left the old fill, and the fill
// veiled the ink it framed.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/features/canvas/data/shape_recognizer.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

const _ink = 0xFF2A7A9E;
const _red = 0xFFD32F2F;

ContentElement _rect(String id, int z, {required bool filled}) =>
    ContentElement.shape(
      id: id,
      zIndex: z,
      data: ShapeData(
        shapeType: 'rectangle',
        x1: 20,
        y1: 20,
        x2: 180,
        y2: 120,
        strokeColor: _ink,
        strokeWidth: 2,
        fillColor: filled ? shapeFillTint(_ink) : null,
      ),
    );

ContentElement _bar(String id, int z) => ContentElement.stroke(
      id: id,
      zIndex: z,
      data: StrokeData(
        color: 0xFF000000,
        baseWidth: 16,
        points: [
          for (var x = 60.0; x <= 140; x += 4)
            StrokePoint(x: x, y: 70, pressure: 1, timestamp: x.toInt() * 10),
        ],
      ),
    );

PageData _page(List<ContentElement> content) => PageData(
      pageId: 'p1',
      pageNumber: 1,
      width: 200,
      height: 140,
      layers: RenderingLayers(content: content),
    );

CanvasState _state(PageData page, List<String> selected) {
  final now = DateTime(2026);
  return CanvasState(
    metadata:
        NotebookMetadata(id: 'n', title: 't', createdAt: now, modifiedAt: now),
    document: DocumentStructure(notebookId: 'n', pages: [
      PageEntry(pageId: page.pageId, pageNumber: 1, fileName: 'p1.json'),
    ]),
    pages: {'p1.json': page},
    currentTool: CanvasTool.lasso,
    remotePath: '',
    lassoSelection: LassoSelection(
        selectedIds: selected, bounds: const Rect.fromLTWH(0, 0, 200, 140)),
  );
}

Future<ui.Color> _pixel(PageData page, Offset at) async {
  final recorder = ui.PictureRecorder();
  CanvasRenderEngine(pageData: page)
      .paintPage(Canvas(recorder), const Size(200, 140), 1, Offset.zero);
  final img = await recorder.endRecording().toImage(200, 140);
  final data = (await img.toByteData())!;
  final i = (at.dy.toInt() * 200 + at.dx.toInt()) * 4;
  return ui.Color.fromARGB(data.getUint8(i + 3), data.getUint8(i),
      data.getUint8(i + 1), data.getUint8(i + 2));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer c;
  late CanvasNotifier n;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CanvasRenderEngine.disposeStaticCache();
    c = ProviderContainer();
    n = c.read(canvasProvider.notifier);
  });
  tearDown(() => c.dispose());

  ShapeData shape(String id) => (c
          .read(canvasProvider)!
          .pages['p1.json']!
          .layers
          .content
          .firstWhere((e) => e.id == id) as ShapeElement)
      .data;

  test('recolour re-tints the fill, leaves unfilled shapes unfilled', () {
    n.state = _state(
      _page([_rect('f', 0, filled: true), _rect('u', 1, filled: false)]),
      ['f', 'u'],
    );
    n.changeSelectionColor(_red);

    expect(shape('f').strokeColor, _red);
    expect(shape('f').fillColor, shapeFillTint(_red));
    expect(shape('u').strokeColor, _red);
    expect(shape('u').fillColor, isNull);

    n.undo();
    expect(shape('f').strokeColor, _ink);
    expect(shape('f').fillColor, shapeFillTint(_ink));
  });

  test('a fill drawn over ink leaves the ink untouched', () async {
    // Shape above the bar in z-order, as when boxing existing notes.
    final page = _page([_bar('ink', 0), _rect('f', 1, filled: true)]);
    final onInk = await _pixel(page, const Offset(100, 70));
    expect(onInk.r, lessThan(0.02));
    expect(onInk.g, lessThan(0.02));
    expect(onInk.b, lessThan(0.02));

    // Paper inside the box still shows the tint.
    final onPaper = await _pixel(page, const Offset(40, 105));
    expect(onPaper.b, lessThan(1.0));
    expect(onPaper.b, greaterThan(onPaper.r));
  });
}
