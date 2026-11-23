// A page upload that lands but whose reply is lost, then another edit
// before the next pull: the pull must see our own bytes, not a conflict.

@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/core/sync/stroke_ops.dart';

import 'support/fake_remote_store.dart';
import 'support/sync_devices.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeRemoteStore server;
  late SyncDevice a, b;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    for (final d in syncDevices) {
      await d.dispose();
    }
    syncDevices.clear();
    StrokeOps.restoreDefaults();
  });

  for (final crash in [false, true]) {
    for (final chunks in [false, true]) {
      test(
          'lost reply${crash ? ', app killed and reopened,' : ''} then a '
          'replacing edit: no conflict, edit wins '
          '(chunks ${chunks ? 'on' : 'off'})', () async {
        StrokeOps.read = chunks;
        StrokeOps.write = chunks;
        server = FakeRemoteStore();
        await server.ensureBaseDirectory();
        a = SyncDevice('a', DeviceStore(server));
        b = SyncDevice('b', DeviceStore(server));
        syncDevices.addAll([a, b]);
        for (final d in syncDevices) {
          await d.init();
        }

        final e = await a.run(() async {
          final e = await a.library.createNotebook(title: 'Echo');
          for (var i = 0; i < 100; i++) {
            if (server.files.keys
                .any((k) => k.endsWith(AppConfig.storageExtension))) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          await a.open(e);
          a.draw('a0', y: 50);
          await a.canvas.save();
          await a.waitFor(() => !a.state!.isDirty);
          return e;
        });
        final id = e.metadata.id;
        final dir = '${server.basePath}${AppConfig.deltaSyncDir}$id/';

        await a.run(() async {
          server.loseReply =
              (p) => p.startsWith(dir) && !p.endsWith(AppConfig.metadataFile);
          a.draw('ink', y: 70);
          await a.canvas.save();
          await a.waitFor(() => !a.canvas.remoteSaveInFlight.value);
          server.loseReply = null;
          if (crash) {
            await a.crash();
            await a.open(e);
          }
        });
        final landed =
            await SyncService(server).downloadDeltaPage(id, kPageFile);
        expect(idsOf(landed), contains('ink'), reason: 'the write landed');

        await a.run(() async {
          // Recognize: the ink becomes one formula element.
          final s = a.state!;
          final page = s.pages[kPageFile]!;
          a.canvas.state = s.copyWith(pages: {
            ...s.pages,
            kPageFile: page.copyWith(
                layers: page.layers.copyWith(content: [
              for (final x in page.layers.content)
                if (x.id != 'ink') x,
            ])),
          }, isDirty: true);
          a.draw('latex', y: 70);
          await a.canvas.save();
          await a.waitFor(
              () => !a.state!.isDirty && !a.canvas.remoteSaveInFlight.value);
        });
        await a.run(() async {
          await a.waitFor(() => a.state!.pendingConflicts.isNotEmpty,
              timeout: const Duration(seconds: 3));
        });
        expect(a.state!.pendingConflicts, isEmpty);
        const want = ['a0', 'latex'];
        expect(idsOf(a.state!.pages[kPageFile]), want);
        await a.run(() async {
          await a.waitFor(() => !a.state!.isDirty);
        });
        expect(
            idsOf(await SyncService(server).downloadDeltaPage(id, kPageFile)),
            want);
        await b.run(() async {
          await b.library.refresh();
          final be = (b.c.read(notebookListProvider).valueOrNull ?? [])
              .singleWhere((x) => x.metadata.id == id);
          await b.open(be);
        });
        expect(idsOf(b.state!.pages[kPageFile]), want);
      });
    }
  }
}
