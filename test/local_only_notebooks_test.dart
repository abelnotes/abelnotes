// A notes app needs a notebook the user can keep off the cloud. The flag is
// only half the feature: every path that talks to the remote has to honour
// it, and the library's deletion cleanup has to not mistake "deliberately
// absent" for "deleted elsewhere" — which would wipe the local copy.

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
    tmp = await Directory.systemTemp.createTemp('local_only_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    fs = FileService();
    await fs.init();
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> addNotebook(String id, {String status = 'modified'}) {
    return fs.upsertNotebookMeta(
      id: id,
      title: id,
      remotePath: '/AbelNotes/$id.ncnote',
      localModifiedAt: DateTime(2026, 8, 26),
      syncStatus: status,
    );
  }

  test('notebooks sync by default', () async {
    await addNotebook('nb');

    expect(await fs.isNotebookLocalOnly('nb'), isFalse,
        reason: 'an opt-out that opted people out silently would be worse '
            'than not having one');
    expect((await fs.getDirtyNotebooks()).map((r) => r['id']), contains('nb'));
  });

  test('a local-only notebook is never queued for upload', () async {
    await addNotebook('secret');

    await fs.setNotebookLocalOnly('secret', true);

    expect(await fs.isNotebookLocalOnly('secret'), isTrue);
    expect((await fs.getDirtyNotebooks()).map((r) => r['id']),
        isNot(contains('secret')));
  });

  test('the flag reaches the library rows so the badge can show it', () async {
    await addNotebook('secret');
    await fs.setNotebookLocalOnly('secret', true);

    final row = (await fs.getAllNotebookMeta())
        .firstWhere((r) => r['id'] == 'secret');

    expect(row['local_only'], 1);
    // The notebook itself is untouched — this is a routing decision, not a
    // deletion.
    expect(row['remote_path'], '/AbelNotes/secret.ncnote');
  });

  test('turning sync back on re-queues it', () async {
    await addNotebook('secret');
    await fs.setNotebookLocalOnly('secret', true);

    await fs.setNotebookLocalOnly('secret', false);

    expect((await fs.getDirtyNotebooks()).map((r) => r['id']),
        contains('secret'));
  });

  test('one notebook opting out does not affect the others', () async {
    await addNotebook('secret');
    await addNotebook('shared');

    await fs.setNotebookLocalOnly('secret', true);

    final dirty = (await fs.getDirtyNotebooks()).map((r) => r['id']).toSet();
    expect(dirty, contains('shared'));
    expect(dirty, isNot(contains('secret')));
  });
}
