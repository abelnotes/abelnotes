// Regression, found before it shipped: switching sync from a personal server
// to Google Drive left every notebook row at sync_status='synced' with the
// old remote_path. The Drive account is empty on the first connect, so the
// library's remote-deletion cleanup reads "this synced notebook is not on
// the server anymore" and hard deletes the local .ncnote, loose store,
// snapshots and DB row — for every notebook the user had.
//
// The disconnect path already knew this (see markAllNotebooksLocal); the
// backend switch has to do the same thing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/remote_store_provider.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/features/sync/drive_connect.dart';

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
  late ProviderContainer container;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('backend_switch_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues({});
    fs = FileService();
    await fs.init();
    container = ProviderContainer();
    addTearDown(container.dispose);
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
      localModifiedAt: DateTime(2026, 8, 25),
      syncStatus: status,
    );
  }

  test('connecting Drive does not leave notebooks claimed by the old server',
      () async {
    await addNotebook('nextcloud_nb', 'synced', etag: 'nc-etag');

    await applySyncBackend(
      files: fs,
      settings: container.read(appSettingsProvider.notifier),
      backend: SyncBackend.drive,
    );

    final row = (await fs.getAllNotebookMeta())
        .firstWhere((r) => r['id'] == 'nextcloud_nb');
    expect(row['sync_status'], 'modified',
        reason: 'a synced row here would be hard deleted by the cleanup');
    expect(row['etag'], isNull,
        reason: "the old server's ETag means nothing to Drive");
    expect(container.read(appSettingsProvider).syncBackend, SyncBackend.drive);

    // Queued for upload, so the notebook lands on Drive rather than being
    // mistaken for one the user deleted.
    final dirty = await fs.getDirtyNotebooks();
    expect(dirty.map((r) => r['id']), contains('nextcloud_nb'));
  });

  test('going back to local-only un-claims too', () async {
    await addNotebook('drive_nb', 'synced', etag: 'md5-abc');

    await applySyncBackend(
      files: fs,
      settings: container.read(appSettingsProvider.notifier),
      backend: null,
    );

    final row = (await fs.getAllNotebookMeta())
        .firstWhere((r) => r['id'] == 'drive_nb');
    expect(row['sync_status'], 'modified');
    expect(container.read(appSettingsProvider).syncBackend, isNull,
        reason: 'null is local-only, and copyWith must be able to reach it');
  });

  test('the local file itself is never touched by a switch', () async {
    await addNotebook('keep_me', 'synced', etag: 'e');
    final before = await fs.getAllNotebookMeta();

    await applySyncBackend(
      files: fs,
      settings: container.read(appSettingsProvider.notifier),
      backend: SyncBackend.drive,
    );

    final after = await fs.getAllNotebookMeta();
    expect(after.length, before.length,
        reason: 'switching remotes must never remove a notebook');
    expect(after.single['remote_path'], '/AbelNotes/keep_me.ncnote',
        reason: 'the retry needs a path to upload to');
  });
}
