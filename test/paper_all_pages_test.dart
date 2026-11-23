// Paper sheet "All pages": spacing and paper type reach every ruled page,
// PDF and image pages keep theirs, one undo step, every page saved.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/providers/remote_store_provider.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/fake_remote_store.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

const _id = '0b5e1c2a-paper-all-pages';

PageData _page(String id, int n, BackgroundLayer bg,
        {List<ContentElement> content = const []}) =>
    PageData(
      pageId: id,
      pageNumber: n,
      width: 595,
      height: 842,
      layers: RenderingLayers(background: bg, content: content),
    );

ContentElement _line(String id) => ContentElement.stroke(
      id: id,
      zIndex: 0,
      data: const StrokeData(
          points: [StrokePoint(x: 10, y: 10), StrokePoint(x: 90, y: 10)]),
    );

const _grid = BackgroundLayer(type: 'grid', lineSpacing: 20);
const _lined = BackgroundLayer(type: 'lined', lineSpacing: 30);
const _pdf = BackgroundLayer(type: 'blank', pdfAsset: 'doc.pdf', lineSpacing: 30);

/// p1 grid, p2 lined, p3 PDF, p4 full-page image, p5 grid.
Map<String, PageData> _pages() => {
      'p1.json': _page('p1', 1, _grid),
      'p2.json': _page('p2', 2, _lined, content: [_line('s2')]),
      'p3.json': _page('p3', 3, _pdf),
      'p4.json': _page('p4', 4, _lined, content: [
        const ContentElement.image(
          id: 'img',
          zIndex: 0,
          data: ImageData(
              x: 0, y: 0, width: 595, height: 842,
              assetPath: 'scan.png', locked: true),
        ),
      ]),
      'p5.json': _page('p5', 5, _grid),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late FileService fs;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('paper_all_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    fs = FileService();
    await fs.init();
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<CanvasNotifier> open(
      {Map<String, PageData>? pages, FakeRemoteStore? remote}) async {
    final c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(remote),
    ]);
    addTearDown(c.dispose);
    final pg = pages ?? _pages();
    final n = c.read(canvasProvider.notifier);
    final now = DateTime(2026);
    await n.openNotebook(
      metadata: NotebookMetadata(
          id: _id, title: 't', createdAt: now, modifiedAt: now,
          paperType: 'grid'),
      document: DocumentStructure(notebookId: _id, pages: [
        for (final (i, f) in pg.keys.indexed)
          PageEntry(pageId: pg[f]!.pageId, pageNumber: i + 1, fileName: f),
      ]),
      pages: pg,
      remotePath: '/AbelNotes/nb.abelnote',
    );
    n.goToPage(0);
    return n;
  }

  BackgroundLayer bg(CanvasNotifier n, String f) =>
      n.state!.pages[f]!.layers.background;

  test('the scope defaults to all pages', () async {
    final n = await open();
    expect(n.paperAllPages, isTrue);
  });

  test('all-pages spacing reaches every ruled page, not PDF or image pages',
      () async {
    final n = await open();
    n.setLineSpacing(42, allPages: true);
    for (final f in ['p1.json', 'p2.json', 'p5.json']) {
      expect(bg(n, f).lineSpacing, 42, reason: f);
    }
    expect(bg(n, 'p2.json').type, 'lined', reason: 'type is kept');
    expect(n.state!.pages['p2.json']!.layers.content, hasLength(1));
    expect(bg(n, 'p3.json'), _pdf, reason: 'PDF page untouched');
    expect(bg(n, 'p4.json'), _lined, reason: 'image page untouched');
    expect(n.state!.isDirty, isTrue);
  });

  test('all-pages paper type changes ruled pages and the notebook default',
      () async {
    final n = await open();
    n.setPaperType(PaperType.dotted, allPages: true);
    for (final f in ['p1.json', 'p2.json', 'p5.json']) {
      expect(bg(n, f).type, 'dotted', reason: f);
      expect(bg(n, f).lineSpacing, paperTypeLineSpacing(PaperType.dotted));
    }
    expect(bg(n, 'p3.json'), _pdf);
    expect(bg(n, 'p4.json'), _lined);
    expect(n.state!.metadata.paperType, 'dotted');
  });

  test('this page still changes only the current page', () async {
    final n = await open();
    n.goToPage(1);
    n.setLineSpacing(42);
    expect(bg(n, 'p2.json').lineSpacing, 42);
    expect(bg(n, 'p1.json').lineSpacing, 20);
    expect(bg(n, 'p5.json').lineSpacing, 20);
    n.setPaperType(PaperType.grid);
    expect(bg(n, 'p2.json').type, 'grid');
    expect(bg(n, 'p1.json').type, 'grid');
    expect(bg(n, 'p5.json').type, 'grid');
    expect(n.state!.metadata.paperType, 'grid', reason: 'page 2 is not the cover');
  });

  test('all-pages undo is one step on every page, redo brings it back',
      () async {
    final n = await open();
    n.setLineSpacing(42, allPages: true);
    n.undo();
    expect(bg(n, 'p1.json').lineSpacing, 20);
    expect(bg(n, 'p2.json').lineSpacing, 30);
    expect(bg(n, 'p5.json').lineSpacing, 20);
    expect(n.canUndo, isFalse);
    n.redo();
    for (final f in ['p1.json', 'p2.json', 'p5.json']) {
      expect(bg(n, f).lineSpacing, 42, reason: f);
    }
    // Undo works from any page of the group.
    n.goToPage(4);
    n.undo();
    expect(bg(n, 'p1.json').lineSpacing, 20);
    expect(bg(n, 'p5.json').lineSpacing, 20);
  });

  test('a page edited after the change keeps its later stroke on undo',
      () async {
    final n = await open();
    n.setLineSpacing(42, allPages: true);
    n.goToPage(1);
    final s = n.state!;
    n.commitPageEdit(
        s,
        'p2.json',
        s.pages['p2.json']!.copyWith(layers: s.pages['p2.json']!.layers
            .copyWith(content: [_line('s2'), _line('late')])),
        undoOf: s.pages['p2.json']);
    n.goToPage(0);
    n.undo();
    expect(bg(n, 'p1.json').lineSpacing, 20);
    expect(bg(n, 'p5.json').lineSpacing, 20);
    // p2 has a newer step: its spacing waits for its own undo.
    expect(n.state!.pages['p2.json']!.layers.content, hasLength(2));
    expect(bg(n, 'p2.json').lineSpacing, 42);
    n.goToPage(1);
    n.undo(); // the stroke
    n.undo(); // the spacing
    expect(n.state!.pages['p2.json']!.layers.content, hasLength(1));
    expect(bg(n, 'p2.json').lineSpacing, 30);
  });

  test('a grouped step counts once against the undo cap', () async {
    final pages = {
      for (var i = 1; i <= 40; i++) 'p$i.json': _page('p$i', i, _grid),
    };
    final n = await open(pages: pages);
    n.setLineSpacing(25); // a single step before the group
    n.setLineSpacing(42, allPages: true);
    expect(n.state!.undoStack, hasLength(41));
    n.undo();
    expect(bg(n, 'p40.json').lineSpacing, 20);
    expect(bg(n, 'p1.json').lineSpacing, 25);
    n.undo();
    expect(bg(n, 'p1.json').lineSpacing, 20);
  });

  test('saving uploads every changed page and only those', () async {
    final remote = FakeRemoteStore();
    final n = await open(remote: remote);
    await n.flushPendingWork(); // first push: the whole notebook
    remote.calls.clear();
    n.setLineSpacing(42, allPages: true);
    await n.flushPendingWork();
    final uploaded = remote.calls.where((c) => c.startsWith('upload ')).join('\n');
    for (final f in ['p1.json', 'p2.json', 'p5.json']) {
      expect(uploaded, contains(f), reason: uploaded);
    }
    expect(uploaded, isNot(contains('p3.json')));
    expect(uploaded, isNot(contains('p4.json')));
    expect(await fs.dirtyPagesOf(_id), isEmpty);
    await n.closeNotebook();
  });
}
