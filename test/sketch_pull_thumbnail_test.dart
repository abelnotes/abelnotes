// A sketch edited on another device gets a fresh library preview when the
// pull merges it; a pulled change of an ordinary notebook does not render one.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/providers/remote_store_provider.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/core/services/thumbnail_service.dart';
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

ContentElement _line(String id, double y) => ContentElement.stroke(
      id: id,
      zIndex: 0,
      data: StrokeData(
          points: [StrokePoint(x: 3000, y: 3000 + y), StrokePoint(x: 3100, y: 3000 + y)]),
    );

PageData _page(double size, List<ContentElement> content) => PageData(
      pageId: 'p1',
      pageNumber: 1,
      width: size,
      height: size,
      layers: RenderingLayers(content: content),
    );

const _id = '5ce7c4a0-sketch-pull-test';

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
    tmp = await Directory.systemTemp.createTemp('sketch_pull_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    fs = FileService();
    await fs.init();
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  final now = DateTime(2026);
  const doc = DocumentStructure(notebookId: _id, pages: [
    PageEntry(pageId: 'p1', pageNumber: 1, fileName: 'p1.json'),
  ]);

  Future<void> until(bool Function() ok, {int seconds = 20}) async {
    for (var i = 0; i < seconds * 20 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Opens the notebook, lets another device edit its page, and returns the
  /// thumbnail file once that edit has been merged here.
  Future<File> pullEdit({required bool sketch}) async {
    final size = sketch ? AppConfig.scratchPageSize : 1240.0;
    final meta = NotebookMetadata(
        id: _id,
        title: 't',
        createdAt: now,
        modifiedAt: now,
        paperType: sketch ? AppConfig.infinitePaperType : 'lined');
    final store = FakeRemoteStore();
    final other = SyncService(store);
    await other.syncDelta(
      notebookId: _id,
      metadata: meta,
      document: doc,
      dirtyPages: {'p1.json': _page(size, [_line('a', 10)])},
    );
    final thumbs = ThumbnailService();
    final c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(store),
      thumbnailServiceProvider.overrideWithValue(thumbs),
    ]);
    addTearDown(c.dispose);
    final n = c.read(canvasProvider.notifier);
    await n.openNotebook(
      metadata: meta,
      document: doc,
      pages: {'p1.json': _page(size, [_line('a', 10)])},
      remotePath: '/AbelNotes/nb.abelnote',
    );
    // The first pull lets this device learn the server's page versions.
    await until(() => store.calls.any((c) => c.endsWith('/p1.json')));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await thumbs.init();
    final file = File(thumbs.thumbnailPath(_id));
    if (await file.exists()) await file.delete();

    await other.syncDelta(
      notebookId: _id,
      metadata: meta.copyWith(modifiedAt: DateTime(2026, 2)),
      document: doc,
      dirtyPages: {
        'p1.json': _page(size, [_line('a', 10), _line('remote-edit', 300)]),
      },
    );
    await until(() =>
        n.state?.pages['p1.json']?.layers.content
            .any((e) => e.id == 'remote-edit') ??
        false);
    expect(
        n.state?.pages['p1.json']?.layers.content
            .any((e) => e.id == 'remote-edit'),
        isTrue,
        reason: 'the edit made elsewhere reaches this device');
    await until(file.existsSync, seconds: 5);
    // Let any thumbnail work in flight finish before the test ends.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return file;
  }

  test('a pulled change of a sketch refreshes its thumbnail', () async {
    final file = await pullEdit(sketch: true);
    expect(file.existsSync(), isTrue);
    final d = ByteData.sublistView(await file.readAsBytes());
    expect(d.getUint32(16), greaterThan(d.getUint32(20)), reason: 'landscape');
  });

  test('a pulled change of a normal notebook does not', () async {
    final file = await pullEdit(sketch: false);
    expect(file.existsSync(), isFalse);
  });
}
