// The editor's edits must reach the local store without waiting on the
// server, and a local write that fails must be retried rather than counted
// as done once the upload (or the offline no-op) went through.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/providers/remote_store_provider.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/remote_store.dart';
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

/// A server that accepts the connection and never answers.
class _HangingStore extends FakeRemoteStore {
  final _never = Completer<Never>();
  int requests = 0;
  Future<Never> _hang() {
    requests++;
    return _never.future;
  }

  @override
  Future<List<RemoteItem>> listDirectory(String remotePath) => _hang();
  @override
  Future<({String? version, DateTime? lastModified})?> getFileInfo(
          String remotePath) =>
      _hang();
  @override
  Future<String?> getVersion(String remotePath) => _hang();
  @override
  Future<Uint8List> downloadFile(String remotePath,
          {int? timeoutSeconds, bool criticalVerify = false}) =>
      _hang();
  @override
  Future<String?> uploadFile(String remotePath, Uint8List data,
          {int? timeoutSeconds,
          bool criticalVerify = false,
          bool skipVerify = false}) =>
      _hang();
}

ContentElement _line(String id, double y) => ContentElement.stroke(
      id: id,
      zIndex: 0,
      data: StrokeData(
          points: [StrokePoint(x: 10, y: y), StrokePoint(x: 100, y: y)]),
    );

PageData _page(List<ContentElement> content) => PageData(
      pageId: 'p1',
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: RenderingLayers(content: content),
    );

const _id = '0b5e1c2a-data-integrity-test';

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
    tmp = await Directory.systemTemp.createTemp('canvas_persist_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    fs = FileService();
    await fs.init();
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<CanvasNotifier> open(ProviderContainer c) async {
    final n = c.read(canvasProvider.notifier);
    final now = DateTime(2026);
    await n.openNotebook(
      metadata: NotebookMetadata(
          id: _id, title: 't', createdAt: now, modifiedAt: now),
      document: const DocumentStructure(notebookId: _id, pages: [
        PageEntry(pageId: 'p1', pageNumber: 1, fileName: 'p1.json'),
      ]),
      pages: {'p1.json': _page([_line('a', 10)])},
      remotePath: '/AbelNotes/nb.abelnote',
    );
    return n;
  }

  void draw(CanvasNotifier n, String id) {
    final s = n.state!;
    final page = s.pages['p1.json']!;
    n.state = s.copyWith(
      pages: {
        'p1.json': page.copyWith(
            layers: page.layers
                .copyWith(content: [...page.layers.content, _line(id, 200)])),
      },
      isDirty: true,
    );
  }

  String onDisk() {
    final f = File(
        p.join(fs.notebookStoreDir(_id), AppConfig.pagesDir, 'p1.json'));
    try {
      return f.readAsStringSync();
    } on FileSystemException {
      return ''; // not written yet, or mid-rename
    }
  }

  Future<void> until(bool Function() cond) async {
    for (var i = 0; i < 400 && !cond(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('a stroke reaches the disk while the server never answers', () async {
    final store = _HangingStore();
    final c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(store),
    ]);
    final n = await open(c);
    draw(n, 'new-stroke');

    unawaited(n.save());
    await until(() => onDisk().contains('new-stroke'));

    expect(onDisk(), contains('new-stroke'));
    expect(store.requests, greaterThan(0), reason: 'the upload is stuck');
    // Marked unpushed before it hit the disk: a crash now still uploads it.
    expect(await fs.dirtyPagesOf(_id), contains('p1.json'));

    // A second edit while that save is still stuck goes to disk too.
    draw(n, 'second-stroke');
    await n.persistLocalNow();
    expect(onDisk(), contains('second-stroke'));
  });

  test('a local write that failed is retried, not counted as saved',
      () async {
    final c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(null), // offline
    ]);
    final n = await open(c);
    await n.persistLocalNow(); // seed the store
    final pagesDir =
        Directory(p.join(fs.notebookStoreDir(_id), AppConfig.pagesDir));
    expect(pagesDir.existsSync(), isTrue);

    await Process.run('chmod', ['a-w', pagesDir.path]);
    try {
      draw(n, 'lost-before');
      await n.save();
      await until(() => n.localSaveError.value != null);
      expect(n.localSaveError.value, isNotNull);
      expect(onDisk(), isNot(contains('lost-before')));
    } finally {
      await Process.run('chmod', ['u+w', pagesDir.path]);
    }

    // The offline "upload" succeeded, so the old code thought this page
    // was saved and never wrote it again. The retry timer must.
    await until(() =>
        onDisk().contains('lost-before') && n.localSaveError.value == null);
    expect(onDisk(), contains('lost-before'));
    expect(n.localSaveError.value, isNull);
    await n.closeNotebook();
  });

  test('closing after a discard writes nothing', () async {
    final c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(null),
    ]);
    final n = await open(c);
    await n.persistLocalNow();
    draw(n, 'unwanted');
    n.discardUnsavedEdits();
    await n.closeNotebook();
    expect(onDisk(), isNot(contains('unwanted')));
  });

  test('a preview writes nothing, even when closed after an edit', () async {
    final c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(FakeRemoteStore()),
    ]);
    final n = c.read(canvasProvider.notifier);
    final now = DateTime(2026);
    await n.openNotebook(
      metadata: NotebookMetadata(
          id: _id, title: 't', createdAt: now, modifiedAt: now),
      document: const DocumentStructure(notebookId: _id, pages: [
        PageEntry(pageId: 'p1', pageNumber: 1, fileName: 'p1.json'),
      ]),
      pages: {'p1.json': _page([_line('a', 10)])},
      remotePath: '',
      preview: true,
    );
    expect(n.isPreview, isTrue);
    expect(n.state!.currentTool, CanvasTool.pan);
    n.setTool(CanvasTool.pen);
    expect(n.state!.currentTool, CanvasTool.pan, reason: 'read-only');

    draw(n, 'not-kept');
    await n.save();
    expect(await n.persistLocalNow(), isFalse);
    await n.closeNotebook();

    expect(Directory(fs.notebookStoreDir(_id)).existsSync(), isFalse);
    expect(await fs.dirtyPagesOf(_id), isEmpty);
    expect(n.isPreview, isFalse, reason: 'the next notebook is a normal one');
  });

  test('closing writes the last edit even with no autosave run', () async {
    final c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(null),
    ]);
    final n = await open(c);
    draw(n, 'last-stroke');
    await n.closeNotebook();
    expect(onDisk(), contains('last-stroke'));
  });
}
