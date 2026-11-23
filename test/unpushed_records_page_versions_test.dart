// Pages a previous session left unpushed go up from the library. When the
// server had not moved, only the meta ETag was recorded: the baseline kept
// the old page versions, so the editor took this device's own upload for a
// change made elsewhere and downloaded it again (or re-uploaded it as a
// ghost page).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/services/sync_baselines.dart';

import 'support/fake_remote_store.dart';
import 'support/sync_devices.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeRemoteStore server;
  late SyncDevice a;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    server = FakeRemoteStore();
    await server.ensureBaseDirectory();
    syncDevices.clear();
    a = SyncDevice('a', DeviceStore(server));
    syncDevices.add(a);
    await a.init();
  });

  tearDown(() async {
    await a.dispose();
    syncDevices.clear();
  });

  test('a library push with the server unchanged records the page versions',
      () async {
    final e = await a.run(() async {
      final e = await a.library.createNotebook(title: 'Unpushed');
      for (var i = 0; i < 100; i++) {
        if (server.files.keys
            .any((k) => k.endsWith(AppConfig.storageExtension))) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await a.open(e);
      a.draw('s1', y: 50);
      await a.canvas.save();
      await a.canvas.flushPendingWork();
      await a.canvas.closeNotebook();
      return e;
    });
    final id = e.metadata.id;
    final pagePath =
        '${server.basePath}${AppConfig.deltaSyncDir}$id/pages/$kPageFile';

    await a.run(() async {
      final dir = a.fs.notebookStoreDir(id);
      final key = await SyncBaselines.identityOf(a.store);
      final before = await SyncBaselines.read(dir, id, key);
      expect(before.metaEtag, isNotNull, reason: 'server state known');
      final uploadsBefore =
          server.calls.where((c) => c == 'upload $pagePath').length;

      // The previous session wrote the page locally but never sent it.
      await a.fs.addDirtyPages(id, [kPageFile]);
      expect(await a.library.resumeSync(e), isTrue);
      expect(server.calls.where((c) => c == 'upload $pagePath').length,
          uploadsBefore + 1, reason: 'the library pushed the page');

      final after = await SyncBaselines.read(dir, id, key);
      expect(after.pageEtags[kPageFile], await server.getVersion(pagePath),
          reason: 'the page this device just sent is not news to it');
      expect(after.metaEtag, isNot(before.metaEtag));
    });
  });
}
