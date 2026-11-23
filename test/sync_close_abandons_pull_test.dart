// Closing a notebook while its pull downloads many pages must not wait for
// every page: the next notebook opens behind that close.

import 'dart:convert';
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

/// A slow link: every page download takes [delay].
class _SlowPagesStore extends FakeRemoteStore {
  Duration delay = Duration.zero;
  int pageGets = 0;

  @override
  Future<Uint8List> downloadFile(String remotePath,
      {int? timeoutSeconds, bool criticalVerify = false}) async {
    if (remotePath.contains('/pages/')) {
      pageGets++;
      await Future<void>.delayed(delay);
    }
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

const _id = '1c0de0aa-close-abandons-pull';
const _pageCount = 40;

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
    tmp = await Directory.systemTemp.createTemp('sync_close_abandons_pull');
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

  test('closing during a whole-notebook pull leaves at once and keeps the '
      'old page versions', () async {
    final store = _SlowPagesStore();
    await SyncService(store).syncDelta(
      notebookId: _id,
      metadata: meta,
      document: doc,
      dirtyPages: pages,
    );
    // Every page takes 300 ms: the whole pull would take 3 s at 4 in flight.
    store.delay = const Duration(milliseconds: 300);
    final c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(c.dispose);
    final n = c.read(canvasProvider.notifier);
    // No page versions known on this device: the pull fetches every page.
    await n.openNotebook(
        metadata: meta,
        document: doc,
        pages: pages,
        remotePath: '/AbelNotes/nb.abelnote');
    await until(() => store.pageGets >= 4);
    expect(store.pageGets, lessThan(_pageCount));

    final sw = Stopwatch()..start();
    await n.closeNotebook();
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(1500),
        reason: 'the close waits only for the downloads already in flight');
    expect(store.pageGets, lessThan(_pageCount ~/ 2),
        reason: 'no new page is fetched once the notebook is closing');
    expect(n.state, isNull);
    // Nothing was merged, so no page counts as received.
    final prefs = await SharedPreferences.getInstance();
    final known = prefs.getString('page_etags_$_id');
    expect(known == null || (jsonDecode(known) as Map).isEmpty, isTrue);

    // Reopened, the notebook pulls (and now merges) every page. Pages that
    // were in flight may come from the snapshot cache when chunk reading is
    // on (same version), so count merged versions, not only GETs.
    store.delay = Duration.zero;
    final before = store.pageGets;
    await n.openNotebook(
        metadata: meta,
        document: doc,
        pages: pages,
        remotePath: '/AbelNotes/nb.abelnote');
    int merged() {
      final raw = prefs.getString('page_etags_$_id');
      return raw == null ? 0 : (jsonDecode(raw) as Map).length;
    }

    await until(() => merged() >= _pageCount);
    expect(merged(), _pageCount);
    expect(store.pageGets - before, greaterThanOrEqualTo(_pageCount - before));
    expect(store.pageGets - before, lessThanOrEqualTo(_pageCount));
    await n.closeNotebook();
  });
}
