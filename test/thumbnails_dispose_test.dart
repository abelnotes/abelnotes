// The web cover-thumbnail debounce must not outlive the notifier.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas/thumbnails.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

final _refProvider = Provider<Ref>((ref) => ref);

class _Core implements CanvasCore {
  _Core(this.ref);
  @override
  final Ref ref;
  @override
  CanvasState? state;
  @override
  bool get isDisposed => false;

  // Only ref is read by the thumbnail queue.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CanvasState _state() {
  final now = DateTime(2026);
  return CanvasState(
    metadata: NotebookMetadata(id: 'n', title: 't', createdAt: now, modifiedAt: now),
    document: const DocumentStructure(notebookId: 'n', pages: [
      PageEntry(pageId: 'p1', pageNumber: 1, fileName: 'p1.json'),
    ]),
    pages: const {
      'p1.json': PageData(
          pageId: 'p1',
          pageNumber: 1,
          width: 595,
          height: 842,
          layers: RenderingLayers(content: [])),
    },
    currentPageIndex: 0,
    currentTool: CanvasTool.pen,
    remotePath: '',
  );
}

void main() {
  testWidgets('dispose drops the queued refresh and leaves no timer', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final core = _Core(c.read(_refProvider))..state = _state();
    var ran = 0;
    final thumbs = Thumbnails(core, () async => ran++, debounced: true);

    thumbs.refresh(core.state!, 'n');
    thumbs.dispose();
    // A pending timer here fails the test at teardown.
    await tester.pump(const Duration(seconds: 2));
    expect(ran, 0);
  });

  testWidgets('without dispose the debounced refresh still runs once', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final core = _Core(c.read(_refProvider))..state = _state();
    var ran = 0;
    final thumbs = Thumbnails(core, () async => ran++, debounced: true);

    thumbs.refresh(core.state!, 'n');
    thumbs.refresh(core.state!, 'n');
    expect(ran, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(ran, 1);
  });
}
