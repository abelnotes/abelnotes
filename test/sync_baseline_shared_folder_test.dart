// Two installs on one machine (e.g. native + flatpak) share the notebooks
// folder but not their prefs. The second one used to download every page of
// a notebook the first had already synced; now it reuses the baseline kept
// in the store folder. Another server never reuses it.

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
import 'package:abelnotes/core/services/sync_baselines.dart';
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

class _CountingStore extends FakeRemoteStore {
  _CountingStore({super.identity});
  int pageGets = 0;

  @override
  Future<Uint8List> downloadFile(String remotePath,
      {int? timeoutSeconds, bool criticalVerify = false}) async {
    if (remotePath.contains('/pages/')) pageGets++;
    return super.downloadFile(remotePath,
        timeoutSeconds: timeoutSeconds, criticalVerify: criticalVerify);
  }
}

PageData _page(String id, int n) => PageData(
      pageId: id,
      pageNumber: n,
      width: 595,
      height: 842,
      layers: RenderingLayers(content: [
        ContentElement.stroke(
          id: 's$id',
          zIndex: 0,
          data: StrokeData(points: [
            StrokePoint(x: 10, y: 10.0 + n),
            StrokePoint(x: 100, y: 10.0 + n),
          ]),
        ),
      ]),
    );

const _id = '5ba5e11e-shared-notebooks-folder';
const _pageCount = 30;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('sync_baseline_shared');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  final now = DateTime(2026);
  final meta =
      NotebookMetadata(id: _id, title: 't', createdAt: now, modifiedAt: now);
  final pages = {
    for (var i = 1; i <= _pageCount; i++) 'p$i.json': _page('p$i', i),
  };
  final doc = DocumentStructure(notebookId: _id, pages: [
    for (var i = 1; i <= _pageCount; i++)
      PageEntry(pageId: 'p$i', pageNumber: i, fileName: 'p$i.json'),
  ]);

  Future<void> until(bool Function() ok, {int seconds = 20}) async {
    for (var i = 0; i < seconds * 50 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<_CountingStore> server(String identity) async {
    final s = _CountingStore(identity: identity);
    await SyncService(s).syncDelta(
        notebookId: _id, metadata: meta, document: doc, dirtyPages: pages);
    return s;
  }

  /// One install: own prefs, own FileService, the shared folder.
  Future<int> openOn(_CountingStore store, {required bool freshPrefs}) async {
    if (freshPrefs) SharedPreferences.setMockInitialValues({});
    final fs = FileService();
    await fs.init();
    if (!await fs.hasLocalCopy(_id)) {
      await fs.saveNotebookFile(
          _id,
          SyncService.buildPackageBytes(
              metadata: meta, document: doc, pages: pages));
    }
    final c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(store),
    ]);
    final n = c.read(canvasProvider.notifier);
    final before = store.pageGets;
    final metaChecks = store.calls.length;
    await n.openNotebook(
        metadata: meta,
        document: doc,
        pages: pages,
        remotePath: '/AbelNotes/nb.abelnote');
    // The first pull has looked at the server (meta HEAD or listing)...
    await until(() => store.calls.skip(metaChecks).any((c) =>
        c.startsWith('version ') || c.startsWith('list ')));
    // ...and either skipped or downloaded what it needed.
    await until(() => store.pageGets - before >= _pageCount, seconds: 2);
    if (store.pageGets - before >= _pageCount) {
      final dir = fs.notebookStoreDir(_id);
      final idKey = await SyncBaselines.identityOf(store);
      await until(() =>
          File('$dir/${SyncBaselines.fileName}').existsSync() &&
          File('$dir/${SyncBaselines.fileName}')
              .readAsStringSync()
              .contains(idKey!));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await n.closeNotebook();
    c.dispose();

    return store.pageGets - before;
  }

  test('a second install on the same folder downloads no page', () async {
    final nc = await server('nextcloud-a');
    expect(await openOn(nc, freshPrefs: true), _pageCount,
        reason: 'first install, no baseline anywhere: full pull as before');

    expect(await openOn(nc, freshPrefs: true), 0,
        reason: 'second install reads the baseline from the store folder');
  });

  test('another server with the same versions still gets a full pull',
      () async {
    final a = await server('nextcloud-a');
    expect(await openOn(a, freshPrefs: true), _pageCount);

    // Same notebook uploaded the same way elsewhere: identical version
    // tokens, so only the key keeps its stale pages from being trusted.
    final b = await server('nextcloud-b');
    expect(await openOn(b, freshPrefs: true), _pageCount);

    // Both entries now live side by side; back on A nothing is fetched.
    expect(await openOn(a, freshPrefs: true), 0);
  });
}
