// Regression: nothing in the `notebooks` table records WHICH server a row
// came from. Disconnecting left every row at sync_status='synced' with the
// old remote_path/etag, so connecting a different account made the library's
// remote-deletion cleanup ("this synced notebook is not on the server
// anymore") hard-delete the local .ncnote, loose store, snapshots and DB row.
//
// Disconnect now downgrades the rows to 'modified' — the honest state for
// local content no server owns. The cleanup only touches 'synced' rows, and
// the pending-upload retry (which reads getDirtyNotebooks) picks them up on
// whatever server is connected next.

import 'dart:io';

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
    tmp = await Directory.systemTemp.createTemp('disconnect_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    fs = FileService();
    await fs.init();
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> addNotebook(String id, String status, {String? etag}) {
    return fs.upsertNotebookMeta(
      id: id,
      title: id,
      remotePath: '/AbelNotes/$id.ncnote',
      etag: etag,
      localModifiedAt: DateTime(2026, 7, 25),
      syncStatus: status,
    );
  }

  test('markAllNotebooksLocal un-claims synced rows on disconnect', () async {
    await addNotebook('synced_nb', 'synced', etag: 'abc123');
    await addNotebook('dirty_nb', 'modified');

    final touched = await fs.markAllNotebooksLocal();
    expect(touched, 1, reason: 'only the synced row needed downgrading');

    final rows = await fs.getAllNotebookMeta();
    final byId = {for (final r in rows) r['id'] as String: r};

    expect(byId['synced_nb']!['sync_status'], 'modified');
    expect(byId['synced_nb']!['etag'], isNull);
    expect(byId['synced_nb']!['remote_path'], '/AbelNotes/synced_nb.ncnote',
        reason: 'the retry needs a path to upload to');
    expect(byId['dirty_nb']!['sync_status'], 'modified');

    // Both are now pending uploads, so the next connected server bootstraps
    // them instead of the deletion cleanup wiping them.
    final dirty = await fs.getDirtyNotebooks();
    expect(dirty.map((r) => r['id']).toSet(), {'synced_nb', 'dirty_nb'});
  });
}
