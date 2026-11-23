// cropImageElement awaits PNG encoding: edits made meanwhile must survive,
// and the crop lands on the page it was started on.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Offset, Rect;
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

class _TempPaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _TempPaths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

PageData _page(String id, int n) => PageData(
      pageId: id,
      pageNumber: n,
      width: 595,
      height: 842,
      layers: const RenderingLayers(
          background: BackgroundLayer(type: 'blank'), content: []),
    );

Future<Uint8List> _png(int w, int h) async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF3366CC));
  final img = await rec.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

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
    tmp = await Directory.systemTemp.createTemp('crop_race');
    PathProviderPlatform.instance = _TempPaths(tmp.path);
    fs = FileService();
    await fs.init();
  });
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<(CanvasNotifier, ProviderContainer)> open() async {
    final c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(null),
    ]);
    addTearDown(c.dispose);
    final n = c.read(canvasProvider.notifier);
    final now = DateTime(2026);
    await n.openNotebook(
      metadata: NotebookMetadata(
          id: 'crop-race',
          title: 'Crop',
          createdAt: now,
          modifiedAt: now,
          pageCount: 2),
      document: const DocumentStructure(notebookId: 'crop-race', pages: [
        PageEntry(pageId: 'pg-a', pageNumber: 1, fileName: 'p1.json'),
        PageEntry(pageId: 'pg-b', pageNumber: 2, fileName: 'p2.json'),
      ]),
      pages: {'p1.json': _page('pg-a', 1), 'p2.json': _page('pg-b', 2)},
      remotePath: '/AbelNotes/crop-race.abelnote',
    );
    n.setTool(CanvasTool.pen);
    return (n, c);
  }

  Future<String> addImage(CanvasNotifier n) async {
    n.addImageElement(
        const Offset(100, 100), 'a.png', await _png(40, 40), 200, 200);
    final id = n.state!.currentPage!.layers.content.single.id;
    for (var i = 0; i < 100; i++) {
      if (n.state!.imageCache.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(n.state!.imageCache, isNotEmpty);
    return id;
  }

  ImageElement img(CanvasState s, String file) =>
      s.pages[file]!.layers.content.whereType<ImageElement>().single;

  test('edits made during the crop survive and the crop hits its page',
      () async {
    final (n, _) = await open();
    final id = await addImage(n);
    final before = img(n.state!, 'p1.json').data.assetPath;

    final crop = n.cropImageElement(id, const Rect.fromLTRB(0, 0, 0.5, 0.5));
    // While the PNG is encoded: draw on page 1, then turn to page 2.
    n.commitAndEndStroke([
      for (var i = 0; i < 5; i++)
        StrokePoint(x: 10.0 + i, y: 10),
    ]);
    n.goToPage(1);
    await crop;

    final s = n.state!;
    expect(s.currentPageIndex, 1, reason: 'the page turn is kept');
    final p1 = s.pages['p1.json']!.layers.content;
    expect(p1.whereType<StrokeElement>(), hasLength(1),
        reason: 'the stroke drawn meanwhile is kept');
    expect(img(s, 'p1.json').data.assetPath, isNot(before));
    expect(img(s, 'p1.json').data.width, closeTo(100, 0.01));
  });

  test('an element deleted during the crop is not brought back', () async {
    final (n, _) = await open();
    final id = await addImage(n);

    final crop = n.cropImageElement(id, const Rect.fromLTRB(0, 0, 0.5, 0.5));
    n.deleteElement(id);
    await crop;

    expect(n.state!.pages['p1.json']!.layers.content, isEmpty);
  });

  test('a notifier disposed during the crop is left alone', () async {
    final (n, c) = await open();
    final id = await addImage(n);

    final crop = n.cropImageElement(id, const Rect.fromLTRB(0, 0, 0.5, 0.5));
    c.dispose();
    await crop;
  });
}
