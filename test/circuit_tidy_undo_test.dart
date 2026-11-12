// Replacing the selected ink with a tidied drawing: what is read, what is
// swapped, and that one undo brings the ink back.

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

ContentElement _line(String id, double y, {int z = 0}) => ContentElement.stroke(
      id: id,
      zIndex: z,
      data: StrokeData(points: [StrokePoint(x: 10, y: y), StrokePoint(x: 100, y: y)]),
    );

const _text = ContentElement.text(
  id: 'txt',
  zIndex: 5,
  data: TextData(x: 10, y: 300, width: 100, height: 20, content: 'note'),
);

const _ring = ContentElement.shape(
  id: 'ring',
  zIndex: 6,
  data: ShapeData(shapeType: 'circle', x1: 0, y1: 0, x2: 20, y2: 20),
);

const _arrow = ContentElement.shape(
  id: 'arrow',
  zIndex: 7,
  data: ShapeData(shapeType: 'arrow', x1: 0, y1: 0, x2: 20, y2: 20),
);

PageData _page(String id, List<ContentElement> content) => PageData(
      pageId: id,
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: RenderingLayers(content: content),
    );

List<String> _ids(PageData? p) => [for (final e in p!.layers.content) e.id];

CanvasState _state(Map<String, PageData> pages, {LassoSelection? lasso}) {
  final now = DateTime(2026);
  return CanvasState(
    metadata: NotebookMetadata(id: 'n', title: 't', createdAt: now, modifiedAt: now),
    document: DocumentStructure(notebookId: 'n', pages: [
      for (final e in pages.entries) PageEntry(pageId: e.value.pageId, pageNumber: 1, fileName: e.key),
    ]),
    pages: pages,
    lassoSelection: lasso,
    remotePath: '',
  );
}

LassoSelection _sel(List<String> ids, {Offset drag = Offset.zero}) =>
    LassoSelection(selectedIds: ids, bounds: const Rect.fromLTWH(10, 10, 90, 300), dragOffset: drag);

StrokeData _clean() => const StrokeData(
      points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 50, y: 0)],
      toolType: kTechnicalTool,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer c;
  late CanvasNotifier n;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    c = ProviderContainer();
    n = c.read(canvasProvider.notifier);
  });
  tearDown(() => c.dispose());

  test('one undo restores the ink the drawing replaced', () {
    n.state = _state({
      'p.json': _page('p', [_line('a', 10), _line('b', 20, z: 1), _line('keep', 30, z: 2)]),
    }, lasso: _sel(['a', 'b']));

    n.replaceStrokesWithDrawing('p.json', {'a', 'b'}, [_clean(), _clean()]);
    var s = c.read(canvasProvider)!;
    expect(s.lassoSelection, isNull);
    expect(s.undoStack.length, 1);
    final after = s.pages['p.json']!.layers.content;
    expect(after.length, 3);
    expect(after.first.id, 'keep');
    expect(after.whereType<StrokeElement>().where((e) => e.data.toolType == kTechnicalTool).length, 2);

    n.undo();
    s = c.read(canvasProvider)!;
    expect(_ids(s.pages['p.json']), ['a', 'b', 'keep']);
    expect(s.undoStack, isEmpty);
  });

  test('a page without those strokes any more stays as it is', () {
    final page = _page('p', [_line('other', 10)]);
    n.state = _state({'p.json': page});
    n.replaceStrokesWithDrawing('p.json', {'gone'}, [_clean()]);
    final s = c.read(canvasProvider)!;
    expect(_ids(s.pages['p.json']), ['other']);
    expect(s.undoStack, isEmpty);
  });

  test('the result lands on the page the ink came from', () {
    n.state = _state({
      'p1.json': _page('p1', [_line('a', 10)]),
      'p2.json': _page('p2', [_line('b', 10)]),
    });
    expect(c.read(canvasProvider)!.currentPageFileName, 'p1.json');
    n.replaceStrokesWithDrawing('p2.json', {'b'}, [_clean()]);
    final s = c.read(canvasProvider)!;
    expect(_ids(s.pages['p1.json']), ['a']);
    expect(_ids(s.pages['p2.json']), isNot(contains('b')));
  });

  test('a moved selection is read where it now is', () {
    n.state = _state({'p.json': _page('p', [_line('a', 10)])}, lasso: _sel(['a'], drag: const Offset(0, 100)));
    n.applySelectionTransform();
    expect(n.selectedInk().single.$2.points.first.y, 110);
  });

  test('a picture swaps for its leftover and strokes, one undo brings it back', () {
    const original = ContentElement.image(
      id: 'pic',
      zIndex: 0,
      data: ImageData(x: 10, y: 10, width: 200, height: 100, assetPath: 'a.png'),
    );
    n.state = _state({'p.json': _page('p', [original, _line('keep', 300, z: 1)])});
    final png = Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));
    n.replaceStrokesWithDrawing('p.json', {'pic'}, [_clean()],
        image: (png: png, data: const ImageData(x: 20, y: 20, width: 100, height: 50, assetPath: '')));
    var s = c.read(canvasProvider)!;
    final page = s.pages['p.json']!;
    expect(_ids(page).contains('pic'), isFalse);
    final rest = page.layers.content.whereType<ImageElement>().single;
    expect(rest.data.x, 20);
    expect(rest.data.assetPath, endsWith('_circuit_rest.png'));
    expect(s.assetBytes[rest.data.assetPath], png);
    expect(page.assetReferences, contains(rest.data.assetPath));
    // Under the redrawn strokes.
    final stroke = page.layers.content.whereType<StrokeElement>().where((e) => e.id != 'keep').single;
    expect(rest.zIndex, lessThan(stroke.zIndex));

    n.undo();
    s = c.read(canvasProvider)!;
    expect(_ids(s.pages['p.json']), ['pic', 'keep']);
  });

  group('what counts as ink', () {
    void select(List<ContentElement> content, List<String> ids) =>
        n.state = _state({'p.json': _page('p', content)}, lasso: _sel(ids));

    test('text alone is not', () {
      select([_text], ['txt']);
      expect(n.selectionHasInk, isFalse);
      expect(n.selectedInk(), isEmpty);
    });

    test('strokes are, text beside them is ignored', () {
      select([_line('a', 10), _text], ['a', 'txt']);
      expect(n.selectionHasInk, isTrue);
      expect(n.selectedInk().map((e) => e.$1), ['a']);
    });

    test('a shape is, traced as its outline', () {
      select([_ring], ['ring']);
      expect(n.selectionHasInk, isTrue);
      expect(n.selectedInk().single.$2.points.length, greaterThan(30));
    });

    test('a shape with no outline to trace is not', () {
      select([_arrow], ['arrow']);
      expect(n.selectionHasInk, isFalse);
    });
  });
}
