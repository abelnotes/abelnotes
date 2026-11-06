// Undo/redo is per page, understands an uncommitted lasso transform and keeps
// elements that a sync merge brought in.

import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

ContentElement _line(String id, double y, {int z = 0}) => ContentElement.stroke(
      id: id,
      zIndex: z,
      data: StrokeData(
          points: [StrokePoint(x: 10, y: y), StrokePoint(x: 100, y: y)]),
    );

PageData _page(String id, List<ContentElement> content) => PageData(
      pageId: id,
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: RenderingLayers(content: content),
    );

List<String> _ids(PageData? p) => [
      for (final e in p!.layers.content) e.map(unknown: (u) => u.id,
          stroke: (s) => s.id,
          text: (t) => t.id,
          image: (i) => i.id,
          shape: (s) => s.id,
          math: (m) => m.id),
    ];

double _y(PageData p, String id) => p.layers.content
    .map((e) => e.mapOrNull(stroke: (s) => s))
    .firstWhere((s) => s!.id == id)!
    .data
    .points
    .first
    .y;

CanvasState _state(Map<String, PageData> pages,
    {List<UndoEntry> undo = const [], LassoSelection? lasso}) {
  final now = DateTime(2026);
  return CanvasState(
    metadata: NotebookMetadata(id: 'n', title: 't', createdAt: now, modifiedAt: now),
    document: DocumentStructure(notebookId: 'n', pages: [
      for (final e in pages.entries)
        PageEntry(pageId: e.value.pageId, pageNumber: 1, fileName: e.key),
    ]),
    pages: pages,
    undoStack: undo,
    lassoSelection: lasso,
    remotePath: '',
  );
}

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

  test('undo only touches the page being looked at', () {
    final p1 = _page('p1', [_line('a', 10)]);
    final p2 = _page('p2', [_line('b', 20), _line('c', 30)]);
    n.state = _state({'p1.json': _page('p1', [_line('a', 10), _line('x', 50)]), 'p2.json': p2},
        undo: [
          UndoEntry('p2.json', _page('p2', [_line('b', 20)])),
          UndoEntry('p1.json', p1),
        ]);
    expect(n.canUndo, isTrue);
    n.undo();
    expect(_ids(c.read(canvasProvider)!.pages['p1.json']), ['a']);
    expect(_ids(c.read(canvasProvider)!.pages['p2.json']), ['b', 'c']);
    // Page 1 has nothing left; page 2's entry must stay untouched.
    expect(n.canUndo, isFalse);
    n.undo();
    expect(_ids(c.read(canvasProvider)!.pages['p2.json']), ['b', 'c']);
    expect(c.read(canvasProvider)!.undoStack.length, 1);
    n.redo();
    expect(_ids(c.read(canvasProvider)!.pages['p1.json']), ['a', 'x']);
  });

  test('undo with a pending move reverts that move and keeps older strokes', () {
    final older = _page('p1', [_line('a', 10)]);
    final cur = _page('p1', [_line('a', 10), _line('b', 40)]);
    n.state = _state({'p1.json': cur},
        undo: [UndoEntry('p1.json', older)],
        lasso: const LassoSelection(
            selectedIds: ['b'],
            bounds: Rect.fromLTWH(10, 40, 90, 0),
            dragOffset: Offset(0, 100)));
    n.undo();
    var s = c.read(canvasProvider)!;
    expect(s.lassoSelection, isNull);
    expect(_ids(s.pages['p1.json']), ['a', 'b']);
    expect(_y(s.pages['p1.json']!, 'b'), 40);
    // The move is redoable, and the older stroke was never touched.
    n.redo();
    s = c.read(canvasProvider)!;
    expect(_y(s.pages['p1.json']!, 'b'), 140);
    expect(_ids(s.pages['p1.json']), ['a', 'b']);
  });

  test('redo does not commit a pending move over the redo history', () {
    final cur = _page('p1', [_line('a', 10)]);
    n.state = _state({'p1.json': cur},
        lasso: const LassoSelection(
            selectedIds: ['a'],
            bounds: Rect.fromLTWH(10, 10, 90, 0),
            dragOffset: Offset(0, 5)));
    n.state = n.state!.copyWith(
        redoStack: [UndoEntry('p1.json', _page('p1', [_line('a', 10), _line('z', 90)]))]);
    n.redo();
    final s = c.read(canvasProvider)!;
    expect(s.redoStack.length, 1);
    expect(s.lassoSelection, isNotNull);
    expect(s.undoStack, isEmpty);
  });

  test('a stroke merged from another device survives undo of a local step', () {
    final before = _page('p1', [_line('a', 10)]);
    final live = _page('p1', [_line('a', 10), _line('mine', 40)]);
    final merged = _page('p1', [_line('a', 10), _line('mine', 40), _line('theirs', 70)]);
    final undo = CanvasNotifier.rebaseHistoryOnMerge(
        [UndoEntry('p1.json', before)], {'p1.json': live}, {'p1.json': merged});
    n.state = _state({'p1.json': merged}, undo: undo);
    n.undo();
    expect(_ids(c.read(canvasProvider)!.pages['p1.json']), ['a', 'theirs']);
  });

  test('an element the other device deleted does not come back through undo', () {
    final before = _page('p1', [_line('a', 10), _line('b', 20)]);
    final live = _page('p1', [_line('a', 10), _line('b', 20), _line('mine', 40)]);
    final merged = _page('p1', [_line('a', 10), _line('mine', 40)]);
    final undo = CanvasNotifier.rebaseHistoryOnMerge(
        [UndoEntry('p1.json', before)], {'p1.json': live}, {'p1.json': merged});
    expect(_ids(undo.single.pageData), ['a']);
  });

  test('a page resize is one undo step and keeps the page list in step', () {
    final drawn = _page('p1', [_line('a', 10)]);
    n.state = _state({'p1.json': drawn},
        undo: [UndoEntry('p1.json', _page('p1', []))]);
    n.setPageSize(420, 595);
    PageData cur() => c.read(canvasProvider)!.pages['p1.json']!;
    PageEntry entry() => c.read(canvasProvider)!.document.pages.single;
    expect([cur().width, cur().height, entry().width, entry().height],
        [420, 595, 420, 595]);
    expect(_ids(cur()), ['a']);

    n.undo(); // the resize, not the stroke before it
    expect([cur().width, cur().height, entry().width, entry().height],
        [595, 842, 595, 842]);
    expect(_ids(cur()), ['a']);

    n.redo();
    expect([cur().width, cur().height, entry().width], [420, 595, 420]);
    n.undo();
    n.undo(); // now the stroke, at the original size
    expect(_ids(cur()), isEmpty);
    expect(cur().width, 595);
  });

  test('a resize made by the other device is kept by an undo here', () {
    final before = {'p1.json': _page('p1', [_line('a', 10)])};
    final after = {
      'p1.json': _page('p1', [_line('a', 10)]).copyWith(width: 420)
    };
    final rebased = CanvasNotifier.rebaseHistoryOnMerge(
        [UndoEntry('p1.json', _page('p1', []))], before, after);
    expect(rebased.single.pageData.width, 420);
  });
}
