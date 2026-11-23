// Pull baselines live in the notebook's store folder, keyed by server, so
// installs sharing the notebooks folder share them and no other server can
// ever reuse them.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/remote_baselines.dart';
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

void main() {
  late Directory tmp;
  late String store;
  const id = 'nb';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('sync_baselines_test');
    store = p.join(tmp.path, 'notebooks', id);
    await Directory(store).create(recursive: true);
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  File file([String dir = '']) =>
      File(p.join(dir.isEmpty ? store : dir, SyncBaselines.fileName));

  test('an entry is read back only for the server that wrote it', () async {
    await SyncBaselines.write(store, id, 'serverA',
        metaEtag: 'm1', pageEtags: {'page_001.json': 'e1'});
    SharedPreferences.setMockInitialValues({}); // another install

    final a = await SyncBaselines.read(store, id, 'serverA');
    expect(a.metaEtag, 'm1');
    expect(a.pageEtags, {'page_001.json': 'e1'});

    final b = await SyncBaselines.read(store, id, 'serverB');
    expect(b.metaEtag, isNull);
    expect(b.pageEtags, isEmpty);
  });

  test('pushed pages merge into the entry, meta updates keep the pages',
      () async {
    await SyncBaselines.write(store, id, 's',
        pageEtags: {'page_001.json': 'e1', 'page_002.json': 'e2'});
    await SyncBaselines.write(store, id, 's',
        pushedPages: {'page_002.json': 'e2b', 'page_003.json': 'e3'});
    await SyncBaselines.write(store, id, 's', metaEtag: 'm2');
    final r = await SyncBaselines.read(store, id, 's');
    expect(r.metaEtag, 'm2');
    expect(r.pageEtags, {
      'page_001.json': 'e1',
      'page_002.json': 'e2b',
      'page_003.json': 'e3',
    });
    // Prefs keep the same for older builds.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('delta_meta_etag_$id'), 'm2');
    expect(jsonDecode(prefs.getString('page_etags_$id')!), r.pageEtags);
  });

  test('a corrupt or foreign-format file reads as no baseline', () async {
    await file().writeAsString('{"v":1,"backends":{"s": [tru');
    expect((await SyncBaselines.read(store, id, 's')).pageEtags, isEmpty);
    await file().writeAsString('{"v":99,"backends":{"s":{"meta":"x"}}}');
    expect((await SyncBaselines.read(store, id, 's')).metaEtag, isNull);

    // The next write replaces it with a valid file.
    await SyncBaselines.write(store, id, 's', metaEtag: 'm');
    expect((await SyncBaselines.read(store, id, 's')).metaEtag, 'm');
  });

  test('prefs from before the file are used and copied into it', () async {
    SharedPreferences.setMockInitialValues({
      'delta_meta_etag_$id': 'old-meta',
      'page_etags_$id': '{"page_001.json":"old"}',
    });
    final r = await SyncBaselines.read(store, id, 's');
    expect(r.metaEtag, 'old-meta');
    expect(r.pageEtags, {'page_001.json': 'old'});
    expect(file().existsSync(), isTrue);

    SharedPreferences.setMockInitialValues({}); // a second install
    final shared = await SyncBaselines.read(store, id, 's');
    expect(shared.metaEtag, 'old-meta');
    expect(shared.pageEtags, {'page_001.json': 'old'});
  });

  test('a first write after the upgrade keeps the pages prefs knew', () async {
    SharedPreferences.setMockInitialValues({
      'page_etags_$id': '{"page_001.json":"e1"}',
    });
    await SyncBaselines.write(store, id, 's', metaEtag: 'm');
    SharedPreferences.setMockInitialValues({});
    final r = await SyncBaselines.read(store, id, 's');
    expect(r.metaEtag, 'm');
    expect(r.pageEtags, {'page_001.json': 'e1'});
  });

  test('no identity: prefs only, the file is left alone', () async {
    await SyncBaselines.write(store, id, null, metaEtag: 'm');
    expect(file().existsSync(), isFalse);
    expect((await SyncBaselines.read(store, id, null)).metaEtag, 'm');
  });

  test('never creates a store folder (a library stub stays a stub)',
      () async {
    final stub = p.join(tmp.path, 'notebooks', 'stub');
    await SyncBaselines.write(stub, 'stub', 's', metaEtag: 'm');
    expect(Directory(stub).existsSync(), isFalse);
  });

  test('forget drops one server, or all of them without an identity',
      () async {
    await SyncBaselines.write(store, id, 'a', metaEtag: 'ma');
    await SyncBaselines.write(store, id, 'b', metaEtag: 'mb');
    await SyncBaselines.forget(store, id, 'a');
    expect((await SyncBaselines.read(store, id, 'a')).metaEtag, isNull);
    SharedPreferences.setMockInitialValues({});
    expect((await SyncBaselines.read(store, id, 'b')).metaEtag, 'mb');

    await SyncBaselines.forget(store, id, null);
    expect(file().existsSync(), isFalse);
  });

  test('forgetAll drops the server being left in every notebook', () async {
    final other = p.join(tmp.path, 'notebooks', 'nb2');
    await Directory(other).create();
    for (final (dir, nb) in [(store, id), (other, 'nb2')]) {
      await SyncBaselines.write(dir, nb, 'left', metaEtag: 'm');
      await SyncBaselines.write(dir, nb, 'kept', metaEtag: 'k');
    }
    await RemoteBaselines.forgetAll(
        notebooksRoot: p.join(tmp.path, 'notebooks'), leaving: 'left');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('delta_meta_etag_$id'), isNull);
    for (final (dir, nb) in [(store, id), (other, 'nb2')]) {
      expect((await SyncBaselines.read(dir, nb, 'left')).metaEtag, isNull);
      expect((await SyncBaselines.read(dir, nb, 'kept')).metaEtag, 'k');
    }

    await RemoteBaselines.forgetAll(
        notebooksRoot: p.join(tmp.path, 'notebooks'), leaving: null);
    expect(file().existsSync(), isFalse);
    expect(file(other).existsSync(), isFalse);
  });

  test('identities: same remote same key, any difference another key',
      () async {
    final a = await SyncBaselines.identityOf(FakeRemoteStore(identity: 'x'));
    final a2 = await SyncBaselines.identityOf(FakeRemoteStore(identity: 'x'));
    final b = await SyncBaselines.identityOf(FakeRemoteStore(identity: 'y'));
    expect(a, a2);
    expect(a, isNot(b));
    expect(a, isNot(contains('x')), reason: 'hashed, no server name on disk');
    expect(await SyncBaselines.identityOf(FakeRemoteStore(identity: null)),
        isNull);
    expect(await SyncBaselines.identityOf(null), isNull);
  });

  group('store folder', () {
    late FileService fs;
    final now = DateTime(2026);
    final meta =
        NotebookMetadata(id: id, title: 't', createdAt: now, modifiedAt: now);
    const doc = DocumentStructure(notebookId: id, pages: [
      PageEntry(pageId: 'p1', pageNumber: 1, fileName: 'page_001.json'),
    ]);
    const page = PageData(
        pageId: 'p1',
        pageNumber: 1,
        width: 10,
        height: 10,
        layers: RenderingLayers(content: []));

    setUp(() async {
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
      fs = FileService();
      await fs.init();
      store = fs.notebookStoreDir(id);
      await fs.saveNotebookFile(
          id,
          SyncService.buildPackageBytes(
              metadata: meta, document: doc, pages: {'page_001.json': page}));
      await SyncBaselines.write(store, id, 's', metaEtag: 'm');
    });

    test('is not packaged, but survives a rebuild of the store', () async {
      final zip = ZipDecoder()
          .decodeBytes((await fs.assembleZipFromLooseStore(id))!);
      expect(zip.files.map((f) => f.name),
          isNot(contains(AppConfig.syncBaselineFile)));

      await fs.saveNotebookFile(
          id,
          SyncService.buildPackageBytes(
              metadata: meta, document: doc, pages: {'page_001.json': page}));
      expect((await SyncBaselines.read(store, id, 's')).metaEtag, 'm');
    });

    test('a package carrying one cannot plant a baseline', () async {
      await SyncBaselines.forget(store, id, null);
      final archive = ZipDecoder()
          .decodeBytes((await fs.assembleZipFromLooseStore(id))!);
      final planted = utf8.encode(
          '{"v":1,"backends":{"x":{"meta":"evil","pages":{}}}}');
      archive.addFile(
          ArchiveFile(AppConfig.syncBaselineFile, planted.length, planted));
      await fs.saveNotebookFile(
          id, Uint8List.fromList(ZipEncoder().encode(archive)!));
      expect(file().existsSync(), isFalse);
    });

    test('is left out of backups', () async {
      await fs.snapshotIfDue(id, every: Duration.zero);
      final snaps = await fs.listSnapshots(id);
      expect(snaps, isNotEmpty);
      final zip =
          ZipDecoder().decodeBytes(await File(snaps.first.$2).readAsBytes());
      expect(zip.files.map((f) => f.name), contains('document.json'));
      expect(zip.files.map((f) => f.name),
          isNot(contains(AppConfig.syncBaselineFile)));
    });
  });
}
