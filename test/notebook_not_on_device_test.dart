// A device shouldn't have to hold every notebook the account owns. This flag
// is the mirror of local_only: the notebook lives on the remote and this
// device chose not to keep it. Evicting is not deleting, so it only runs when
// the remote is known to hold everything — and the flag has to survive the
// upsert, which is a REPLACE and would otherwise reset it on the next save.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/core/services/file_service.dart';

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
  late FileService fs;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('not_on_device_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    fs = FileService();
    await fs.init();
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> addNotebook(String id, {String status = 'synced'}) {
    return fs.upsertNotebookMeta(
      id: id,
      title: id,
      remotePath: '/AbelNotes/$id.ncnote',
      localModifiedAt: DateTime(2026, 8, 26),
      syncStatus: status,
    );
  }

  /// Writes a byte-sized local copy so eviction has something to free.
  Future<void> writeLocalCopy(String id, int bytes) async {
    final f = File(fs.localPath(id));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(Uint8List(bytes));
  }

  test('notebooks are downloaded by default', () async {
    await addNotebook('nb');
    expect(await fs.isNotebookDownloadSkipped('nb'), isFalse);
  });

  test('the flag can be set and cleared', () async {
    await addNotebook('nb');
    await fs.setNotebookDownloadSkipped('nb', true);
    expect(await fs.isNotebookDownloadSkipped('nb'), isTrue);
    await fs.setNotebookDownloadSkipped('nb', false);
    expect(await fs.isNotebookDownloadSkipped('nb'), isFalse);
  });

  // The upsert is a REPLACE and no caller passes the per-device flags. Before
  // this was fixed, one save was enough to put a local-only notebook back on
  // the cloud the user had taken it off.
  test('a save does not reset the per-device flags', () async {
    await addNotebook('nb');
    await fs.setNotebookLocalOnly('nb', true);
    await fs.setNotebookDownloadSkipped('nb', true);

    await addNotebook('nb'); // same path a save takes

    expect(await fs.isNotebookLocalOnly('nb'), isTrue);
    expect(await fs.isNotebookDownloadSkipped('nb'), isTrue);
  });

  test('eviction frees the files, keeps the row and flags it', () async {
    await addNotebook('nb');
    await writeLocalCopy('nb', 4096);

    final freed = await fs.evictLocalCopy('nb');

    expect(freed, 4096);
    expect(await fs.hasLocalCopy('nb'), isFalse);
    expect(await fs.getNotebookMeta('nb'), isNotNull,
        reason: 'the card has to stay so the user can get it back');
    expect(await fs.isNotebookDownloadSkipped('nb'), isTrue);
  });

  test('eviction refuses a notebook with unsynced changes', () async {
    await addNotebook('nb', status: 'modified');
    await writeLocalCopy('nb', 1024);

    expect(() => fs.evictLocalCopy('nb'), throwsStateError);
    expect(await fs.hasLocalCopy('nb'), isTrue);
  });

  test('eviction refuses a local-only notebook', () async {
    await addNotebook('nb');
    await fs.setNotebookLocalOnly('nb', true);
    await writeLocalCopy('nb', 1024);

    expect(() => fs.evictLocalCopy('nb'), throwsStateError);
    expect(await fs.hasLocalCopy('nb'), isTrue);
  });

  test('eviction refuses while pages are still dirty', () async {
    await addNotebook('nb');
    await fs.addDirtyPage('nb', 'page_001');
    await writeLocalCopy('nb', 1024);

    expect(() => fs.evictLocalCopy('nb'), throwsStateError);
    expect(await fs.hasLocalCopy('nb'), isTrue);
  });

  // Disconnecting is the one case where the stub has to go: its content only
  // ever lived on the server being disconnected, so the card would point at
  // nothing, and the deletion cleanup would never reach it because it skips
  // rows that aren't `synced`.
  test('disconnecting drops the stubs and keeps everything else', () async {
    await addNotebook('here');
    await writeLocalCopy('here', 1024);
    await addNotebook('gone');
    await writeLocalCopy('gone', 1024);
    await fs.evictLocalCopy('gone');

    await fs.markAllNotebooksLocal();

    expect(await fs.getNotebookMeta('gone'), isNull);
    final kept = await fs.getNotebookMeta('here');
    expect(kept, isNotNull);
    expect(kept!['sync_status'], 'modified');
  });

  test('an evicted notebook is not queued for upload', () async {
    await addNotebook('nb');
    await writeLocalCopy('nb', 1024);
    await fs.evictLocalCopy('nb');

    final dirty = await fs.getDirtyNotebooks();
    expect(dirty.where((r) => r['id'] == 'nb'), isEmpty);
  });
}
