// A pull or a retry still running when the editor goes away must stop: no
// state touched, no further requests, no timer left behind.

import 'dart:async';
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

/// Holds every read until [release], and counts the requests that got in.
class _GatedStore extends FakeRemoteStore {
  /// Every upload fails, as on a dead link.
  bool failing = false;

  /// While set, uploads wait for it: a link that stalls mid-upload.
  Completer<void>? uploadGate;

  @override
  Future<String?> uploadFile(String remotePath, Uint8List data,
      {int? timeoutSeconds,
      bool criticalVerify = false,
      bool skipVerify = false}) async {
    if (uploadGate != null) await uploadGate!.future;
    if (failing) throw RemoteStoreException('link down', 500);
    return super.uploadFile(remotePath, data,
        timeoutSeconds: timeoutSeconds,
        criticalVerify: criticalVerify,
        skipVerify: skipVerify);
  }

  Completer<void>? gate;
  int entered = 0;
  Future<void> _wait() {
    entered++;
    return gate?.future ?? Future<void>.value();
  }

  @override
  Future<List<RemoteItem>> listDirectory(String remotePath) async {
    await _wait();
    return super.listDirectory(remotePath);
  }

  @override
  Future<String?> getVersion(String remotePath) async {
    await _wait();
    return super.getVersion(remotePath);
  }

  @override
  Future<String?> getVersionFast(String remotePath) async {
    await _wait();
    return super.getVersionFast(remotePath);
  }

  @override
  Future<Uint8List> downloadFile(String remotePath,
      {int? timeoutSeconds, bool criticalVerify = false}) async {
    await _wait();
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

const _id = '1c0de0aa-sync-dispose-test';

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
    tmp = await Directory.systemTemp.createTemp('sync_dispose_test');
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

  /// A server that holds two pages of the notebook, as another device left it.
  Future<void> seed(FakeRemoteStore store) async {
    await SyncService(store).syncDelta(
      notebookId: _id,
      metadata: meta,
      document: doc2,
      dirtyPages: {
        'p1.json': _page('p1', 1, [_line('a', 10)]),
        'p2.json': _page('p2', 2, [_line('b', 20)]),
      },
    );
  }

  Future<CanvasNotifier> open(ProviderContainer c) async {
    final n = c.read(canvasProvider.notifier);
    await n.openNotebook(
      metadata: meta,
      document: const DocumentStructure(notebookId: _id, pages: [
        PageEntry(pageId: 'p1', pageNumber: 1, fileName: 'p1.json'),
      ]),
      pages: {
        'p1.json': _page('p1', 1, [_line('a', 10)])
      },
      remotePath: '/AbelNotes/nb.abelnote',
    );
    return n;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  test('reopening with unpushed pages and closing at once throws nothing later',
      () async {
    final store = FakeRemoteStore();
    await seed(store);
    await fs.addDirtyPages(_id, ['p1.json']);
    final errors = <Object>[];
    await runZonedGuarded(() async {
      final c = ProviderContainer(overrides: [
        fileServiceProvider.overrideWithValue(fs),
        remoteStoreProvider.overrideWithValue(store),
      ]);
      await open(c);
      c.dispose();
      // The "flip to dirty" step runs 2 s after the open.
      await Future<void>.delayed(const Duration(milliseconds: 2600));
    }, (e, _) => errors.add(e));
    expect(errors.where((e) => '$e'.contains('after `dispose`')), isEmpty);
  });

  test('a pull in flight when the notebook is disposed stops quietly',
      () async {
    final logs = <String>[];
    await runZoned(() async {
      final store = _GatedStore();
      await seed(store);
      store.gate = Completer<void>();
      store.entered = 0;
      final c = ProviderContainer(overrides: [
        fileServiceProvider.overrideWithValue(fs),
        remoteStoreProvider.overrideWithValue(store),
      ]);
      await open(c);
      for (var i = 0; i < 100 && store.entered == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(store.entered, greaterThan(0), reason: 'the pull is under way');

      c.dispose();
      final enteredAtDispose = store.entered;
      store.gate!.complete();
      await settle();

      expect(store.entered, enteredAtDispose,
          reason: 'no request after the dispose');
    },
        zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => logs.add(line)));

    expect(logs.where((l) => l.contains('after dispose')), isEmpty);
    expect(logs.where((l) => l.contains('Pull failed')), isEmpty);
  });

  test('the upload retry timer is cancelled when the notebook is disposed',
      () async {
    final store = _GatedStore();
    final c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(store),
    ]);
    final n = await open(c);
    final s = n.state!;
    store.failing = true;
    n.state = s.copyWith(
      pages: {
        'p1.json': s.pages['p1.json']!.copyWith(
            layers: s.pages['p1.json']!.layers.copyWith(content: [
          ..._page('p1', 1, [_line('a', 10)]).layers.content,
          _line('b', 200)
        ]))
      },
      isDirty: true,
    );
    await n.save();
    for (var i = 0; i < 100 && !n.hasSyncTimers; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(n.hasSyncTimers, isTrue, reason: 'the failed upload arms a retry');
    await n.persistLocalNow(); // its local write lands before the container goes

    c.dispose();
    expect(n.hasSyncTimers, isFalse);
  });

  test('a save waiting for the sync lock is freed when the notebook is disposed',
      () async {
    final store = _GatedStore();
    final c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(store),
    ]);
    final n = await open(c);
    PageData edited(CanvasState s, String id, double y) => s.pages['p1.json']!
        .copyWith(
            layers: s.pages['p1.json']!.layers.copyWith(
                content: [...s.pages['p1.json']!.layers.content, _line(id, y)]));
    store.uploadGate = Completer<void>();
    var s = n.state!;
    n.state = s.copyWith(pages: {'p1.json': edited(s, 'b', 200)}, isDirty: true);
    await n.save(); // the upload stalls and keeps the lock
    await n.persistLocalNow(); // its local write lands
    s = n.state!;
    n.state = s.copyWith(pages: {'p1.json': edited(s, 'c', 300)}, isDirty: true);
    var second = false;
    unawaited(n.save().then((_) => second = true));
    await settle();
    expect(second, isFalse, reason: 'the second save waits for the lock');

    c.dispose();
    await settle();
    expect(second, isTrue, reason: 'dispose releases the lock it waits on');
  });
}
