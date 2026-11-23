// A page written by a newer app version is not damage: this device must not
// "heal" it by uploading its own older copy over it.

import 'dart:io';
import 'dart:typed_data';

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
import 'package:abelnotes/core/services/sync_service.dart';
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
          points: [StrokePoint(x: 10, y: y), StrokePoint(x: 100, y: y)]),
    );

PageData _page(String id, int n, List<ContentElement> content) => PageData(
      pageId: id,
      pageNumber: n,
      width: 595,
      height: 842,
      layers: RenderingLayers(content: content),
    );

const _id = '1c0de0aa-newer-format-test';

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
    tmp = await Directory.systemTemp.createTemp('sync_meta_failure_test');
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
  final meta =
      NotebookMetadata(id: _id, title: 't', createdAt: now, modifiedAt: now);
  const doc2 = DocumentStructure(notebookId: _id, pages: [
    PageEntry(pageId: 'p1', pageNumber: 1, fileName: 'p1.json'),
    PageEntry(pageId: 'p2', pageNumber: 2, fileName: 'p2.json'),
  ]);

  Future<void> until(bool Function() ok, {int seconds = 20}) async {
    for (var i = 0; i < seconds * 20 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('a page in a newer format is left alone on the server', () async {
    final store = FakeRemoteStore();
    final other = SyncService(store);
    await other.syncDelta(
      notebookId: _id,
      metadata: meta,
      document: doc2,
      dirtyPages: {
        'p1.json': _page('p1', 1, [_line('a', 10)]),
        'p2.json': _page('p2', 2, [_line('b', 20)]),
      },
    );
    final c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(c.dispose);
    final n = c.read(canvasProvider.notifier);
    await n.openNotebook(
      metadata: meta,
      document: doc2,
      pages: {
        'p1.json': _page('p1', 1, [_line('a', 10)]),
        'p2.json': _page('p2', 2, [_line('b', 20)]),
      },
      remotePath: '/AbelNotes/nb.abelnote',
    );
    await until(() => store.calls.any((c) => c.endsWith('/p2.json')));
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // A newer release rewrites page 2 in a binary format this app cannot read.
    final p2 = store.files.keys.firstWhere((k) => k.endsWith('/p2.json'));
    final newer = Uint8List.fromList([0x41, 0x42, 0x50, 0x47, 99, 0, 0, 0, 0]);
    await store.uploadFile(p2, newer);
    await other.syncDelta(
      notebookId: _id,
      metadata: meta.copyWith(modifiedAt: DateTime(2026, 2)),
      document: doc2,
      dirtyPages: const {},
    );
    expect(store.files[p2], newer);
    final before = store.calls.length;
    await until(() => store.calls.skip(before).any((c) => c.startsWith('download') && c.endsWith('/p2.json')));

    // An edit here makes this device save and push.
    n.addPage();
    await n.save();
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(store.files[p2], newer, reason: 'the newer page was not overwritten');
  });
}
