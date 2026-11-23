// A pull whose document/metadata fetch fails must not mark the pages it
// downloaded as received: they were never merged, so the next pull would
// skip them and the edit would stay missing until the page changes again.

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
import 'package:abelnotes/core/services/remote_store.dart';
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

/// Fails the document and metadata downloads on demand, as a link that
/// drops right after the pages came through.
class _MetaFlakyStore extends FakeRemoteStore {
  bool failMeta = false;
  int metaFailures = 0;

  @override
  Future<Uint8List> downloadFile(String remotePath,
      {int? timeoutSeconds, bool criticalVerify = false}) {
    if (failMeta &&
        (remotePath.endsWith('/metadata.json') ||
            remotePath.endsWith('/document.json'))) {
      metaFailures++;
      throw RemoteStoreException('link dropped', 500);
    }
    return super.downloadFile(remotePath,
        timeoutSeconds: timeoutSeconds, criticalVerify: criticalVerify);
  }
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

const _id = '1c0de0aa-meta-failure-test';

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

  test('pages downloaded while the metadata fetch failed are merged by the '
      'next pull', () async {
    final store = _MetaFlakyStore();
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
    // The first pull lets this device learn the server's page versions.
    await until(() => store.calls.any((c) => c.endsWith('/p2.json')));
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Another device edits page 2; this device's next pull loses its metadata.
    store.failMeta = true;
    await other.syncDelta(
      notebookId: _id,
      metadata: meta.copyWith(modifiedAt: DateTime(2026, 2)),
      document: doc2,
      dirtyPages: {
        'p2.json': _page('p2', 2, [_line('b', 20), _line('remote-edit', 300)]),
      },
    );
    await until(() => store.metaFailures > 0);
    expect(store.metaFailures, greaterThan(0), reason: 'the pull hit the drop');
    store.failMeta = false;

    bool merged() {
      final s = n.state;
      if (s == null) return false;
      final live = s.pages['p2.json']?.layers.content ?? const [];
      final pending = s.pendingRemoteChanges?.pages['p2.json']?.layers.content ??
          const [];
      return [...live, ...pending].any((e) => e.id == 'remote-edit');
    }

    await until(merged);
    expect(merged(), isTrue,
        reason: 'the edit made elsewhere reaches this device');
  });
}
