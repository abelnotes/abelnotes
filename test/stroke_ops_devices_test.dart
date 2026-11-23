// Stroke delta chunks with the whole app on two devices (editor state, save,
// push, pull, merge) and one fake server. Real-server twin of these:
// test/sync_nextcloud_integration_test.dart, scenarios 7-9.

@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/core/sync/stroke_ops.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

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

  setUp(() async {
    StrokeOps.read = true;
    StrokeOps.write = true;
    server = FakeRemoteStore();
    await server.ensureBaseDirectory();
    syncDevices.clear();
    a = SyncDevice('a', DeviceStore(server));
    b = SyncDevice('b', DeviceStore(server));
    syncDevices.addAll([a, b]);
    for (final d in syncDevices) {
      await d.init();
    }
  });

  tearDown(() async {
    for (final d in syncDevices) {
      await d.dispose();
    }
    syncDevices.clear();
    StrokeOps.restoreDefaults();
  });

  String deltaDir(String id) =>
      '${server.basePath}${AppConfig.deltaSyncDir}$id/';

  /// Page writes (snapshot PUTs) and chunk writes the server took for [id].
  ({int pages, int chunks}) writes(String id) {
    var pages = 0, chunks = 0;
    for (final c in server.calls) {
      if (!c.startsWith('upload ') || !c.contains(deltaDir(id))) continue;
      if (c.contains('/pages/')) pages++;
      if (c.contains('/${StrokeOps.folder}')) chunks++;
    }
    return (pages: pages, chunks: chunks);
  }

  /// The page as a reader that applies chunks sees it.
  Future<PageData> serverPage(String id) =>
      SyncService(server).downloadDeltaPage(id, kPageFile);

  /// What a release without chunks reads.
  Future<PageData> snapshotOnly(String id) async {
    final read = StrokeOps.read;
    StrokeOps.read = false;
    try {
      return await SyncService(server).downloadDeltaPage(id, kPageFile);
    } finally {
      StrokeOps.read = read;
    }
  }

  Future<NotebookEntry> createOnA() => a.run(() async {
        final e = await a.library.createNotebook(title: 'Ops');
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
        return e;
      });

  Future<void> openOnB(String id) => b.run(() async {
        await b.library.refresh();
        final be = (b.c.read(notebookListProvider).valueOrNull ?? [])
            .singleWhere((x) => x.metadata.id == id);
        await b.open(be);
      });

  void erase(SyncDevice d, String id) {
    final s = d.state!;
    final page = s.pages[kPageFile]!;
    d.canvas.state = s.copyWith(
      pages: {
        ...s.pages,
        kPageFile: page.copyWith(
            layers: page.layers.copyWith(content: [
          for (final e in page.layers.content)
            if (e.id != id) e,
        ])),
      },
      isDirty: true,
    );
  }

  test('both devices draw on one page offline, then go online: every stroke '
      'everywhere, sent as chunks', () async {
    final e = await createOnA();
    final id = e.metadata.id;
    await openOnB(id);
    // One save on each, from the page they both pulled: from here on chunks.
    await a.run(() async {
      a.draw('a1', y: 70);
      await a.canvas.save();
    });
    await b.run(() async {
      await b.waitFor(() => idsOf(b.state!.pages[kPageFile]).contains('a1'));
    });
    server.calls.clear();

    await a.run(() async {
      a.store.offline = true;
      a.draw('sa', y: 120);
      await a.canvas.save();
    });
    await b.run(() async {
      b.store.offline = true;
      b.draw('sb', y: 160);
      await b.canvas.save();
    });
    await a.run(() async {
      a.store.offline = false;
      // The next pull finds the server again and marks the edit for upload.
      expect(await a.waitFor(() => a.state!.isDirty), isTrue);
      await a.canvas.save();
    });
    await b.run(() async {
      b.store.offline = false;
      await b.waitFor(() => idsOf(b.state!.pages[kPageFile]).contains('sa'));
      await b.canvas.save();
      await b.waitFor(() => !b.state!.isDirty);
    });
    await a.run(() async {
      await a.waitFor(() => idsOf(a.state!.pages[kPageFile]).contains('sb'));
    });

    const want = ['a0', 'a1', 'sa', 'sb'];
    expect(idsOf(a.state!.pages[kPageFile]), want);
    expect(idsOf(b.state!.pages[kPageFile]), want);
    expect(idsOf(await serverPage(id)), want);
    expect(a.state!.pendingConflicts, isEmpty);
    expect(b.state!.pendingConflicts, isEmpty);
    expect(writes(id), (pages: 0, chunks: 2));
  });

  test('an erase on one device and a stroke on the other both stand',
      () async {
    final e = await createOnA();
    final id = e.metadata.id;
    await openOnB(id);
    await a.run(() async {
      a.draw('a1', y: 70);
      await a.canvas.save();
    });
    await b.run(() async {
      await b.waitFor(() => idsOf(b.state!.pages[kPageFile]).contains('a1'));
      b.store.offline = true;
      b.draw('sb', y: 160);
      await b.canvas.save();
    });
    await a.run(() async {
      erase(a, 'a0');
      await a.canvas.save();
    });
    await b.run(() async {
      b.store.offline = false;
      await b.waitFor(() => !idsOf(b.state!.pages[kPageFile]).contains('a0'));
      await b.canvas.save();
      await b.waitFor(() => !b.state!.isDirty);
    });
    await a.run(() async {
      await a.waitFor(() => idsOf(a.state!.pages[kPageFile]).contains('sb'));
    });
    const want = ['a1', 'sb'];
    expect(idsOf(a.state!.pages[kPageFile]), want);
    expect(idsOf(b.state!.pages[kPageFile]), want);
    expect(idsOf(await serverPage(id)), want);
  });

  test('a release without chunks sees every stroke once the writer closes '
      'the notebook', () async {
    final e = await createOnA();
    final id = e.metadata.id;
    await a.run(() async {
      for (var i = 1; i <= 3; i++) {
        a.draw('s$i', y: 60.0 + i * 20);
        await a.canvas.save();
      }
    });
    expect(writes(id).chunks, greaterThan(0));
    expect(idsOf(await snapshotOnly(id)), isNot(contains('s3')),
        reason: 'still in chunks');
    await a.run(() => a.canvas.closeNotebook());
    expect(idsOf(await snapshotOnly(id)), ['a0', 's1', 's2', 's3']);
    expect(server.files.keys.where((k) => k.contains(StrokeOps.folder)),
        isEmpty);

    // And it opens, edits and saves on the same folder: nothing is lost.
    StrokeOps.read = false;
    StrokeOps.write = false;
    await openOnB(id);
    await b.run(() async {
      expect(idsOf(b.state!.pages[kPageFile]), ['a0', 's1', 's2', 's3']);
      b.draw('old', y: 300);
      await b.canvas.save();
    });
    expect(idsOf(await snapshotOnly(id)), ['a0', 'old', 's1', 's2', 's3']);
  });

  test('killed after the chunk upload whose metadata commit failed: '
      'after restart nothing is lost or doubled', () async {
    final e = await createOnA();
    final id = e.metadata.id;
    await a.run(() async {
      a.draw('a1', y: 70);
      await a.canvas.save();
    });
    final metaPath = '${deltaDir(id)}${AppConfig.metadataFile}';
    await a.run(() async {
      server.failUploads.add(metaPath);
      a.draw('lost?', y: 90);
      await a.canvas.save();
      await a.waitFor(() =>
          server.files.keys.any((k) => k.contains(StrokeOps.folder)));
      // The upload failed at its commit marker; then the app is killed with
      // that failure staged, before any etag of the chunk was kept.
      await a.waitFor(() => !a.canvas.remoteSaveInFlight.value);
      await a.crash();
    });
    expect(idsOf(await serverPage(id)), contains('lost?'),
        reason: 'the chunk landed');
    server.failUploads.remove(metaPath);

    await a.run(() async {
      await a.open(e);
      a.draw('after', y: 110);
      await a.canvas.save();
      await a.waitFor(() => !a.state!.isDirty);
    });
    const want = ['a0', 'a1', 'after', 'lost?']; // idsOf sorts
    expect(idsOf(a.state!.pages[kPageFile]), want);
    expect(idsOf(await serverPage(id)), want);
    await openOnB(id);
    expect(idsOf(b.state!.pages[kPageFile]), want);
  });

  test('with both flags off the same scenario writes only pages', () async {
    StrokeOps.read = false;
    StrokeOps.write = false;
    final e = await createOnA();
    final id = e.metadata.id;
    await a.run(() async {
      a.draw('a1', y: 70);
      await a.canvas.save();
    });
    expect(writes(id).chunks, 0);
    expect(server.directories.any((d) => d.endsWith('/${StrokeOps.folder}')),
        isFalse);
  });

  group('read on, write off (what this release ships)', () {
    setUp(StrokeOps.restoreDefaults);

    test('a device that only reads pulls a writer\'s chunks, folds them into '
        'its own page write, and both converge', () async {
      a.writesChunks = true; // a later release
      b.writesChunks = false;
      final e = await createOnA();
      final id = e.metadata.id;
      await openOnB(id);
      server.calls.clear();
      await a.run(() async {
        a.draw('a1', y: 70);
        await a.canvas.save();
        a.draw('a2', y: 90);
        await a.canvas.save();
      });
      expect(writes(id).chunks, greaterThan(0), reason: 'A writes chunks');
      await b.run(() async {
        expect(
            await b.waitFor(
                () => idsOf(b.state!.pages[kPageFile]).contains('a2')),
            isTrue);
        expect(idsOf(b.state!.pages[kPageFile]), ['a0', 'a1', 'a2']);
        server.calls.clear();
        b.draw('b1', y: 160);
        await b.canvas.save();
        await b.waitFor(() => !b.state!.isDirty);
      });
      expect(writes(id), (pages: 1, chunks: 0),
          reason: 'B writes the page, never a chunk');
      expect(server.files.keys.where((k) => k.contains(StrokeOps.folder)),
          isEmpty,
          reason: 'B folded and deleted the chunks it had read');
      expect(idsOf(await snapshotOnly(id)), ['a0', 'a1', 'a2', 'b1']);

      await a.run(() async {
        expect(
            await a.waitFor(
                () => idsOf(a.state!.pages[kPageFile]).contains('b1')),
            isTrue);
        a.draw('a3', y: 110);
        await a.canvas.save();
        await a.waitFor(() => !a.state!.isDirty);
      });
      await b.run(() async {
        expect(
            await b.waitFor(
                () => idsOf(b.state!.pages[kPageFile]).contains('a3')),
            isTrue);
      });
      const want = ['a0', 'a1', 'a2', 'a3', 'b1'];
      expect(idsOf(a.state!.pages[kPageFile]), want);
      expect(idsOf(b.state!.pages[kPageFile]), want);
      expect(idsOf(await serverPage(id)), want);
      expect(a.state!.pendingConflicts, isEmpty);
      expect(b.state!.pendingConflicts, isEmpty);
    });

    test('devices that only read never create chunk files', () async {
      a.writesChunks = false;
      b.writesChunks = false;
      final e = await createOnA();
      final id = e.metadata.id;
      await a.run(() async {
        for (var i = 1; i <= 3; i++) {
          a.draw('a$i', y: 60.0 + i * 20);
          await a.canvas.save();
        }
      });
      await openOnB(id);
      await b.run(() async {
        b.draw('b1', y: 200);
        await b.canvas.save();
        await b.waitFor(() => !b.state!.isDirty);
        await b.canvas.closeNotebook();
      });
      await a.run(() async {
        await a.waitFor(() => idsOf(a.state!.pages[kPageFile]).contains('b1'));
        await a.canvas.closeNotebook();
      });
      expect(writes(id).chunks, 0);
      expect(
          server.calls.where((c) =>
              c.contains('/${StrokeOps.folder}') &&
              !c.startsWith('list ')),
          isEmpty,
          reason: 'listing ops/ is all a reader does there');
      expect(server.directories.any((d) => d.endsWith('/${StrokeOps.folder}')),
          isFalse);
      expect(idsOf(await snapshotOnly(id)), ['a0', 'a1', 'a2', 'a3', 'b1']);
    });

    test('a folder written by a release without chunks is read and written '
        'as that release does', () async {
      StrokeOps.read = false; // the old release creates and fills it
      StrokeOps.write = false;
      final e = await createOnA();
      final id = e.metadata.id;
      await a.run(() async {
        a.draw('old', y: 70);
        await a.canvas.save();
      });
      StrokeOps.restoreDefaults();
      await openOnB(id);
      final pagePath = '${deltaDir(id)}pages/$kPageFile';
      await b.run(() async {
        expect(idsOf(b.state!.pages[kPageFile]), ['a0', 'old']);
        b.draw('new', y: 160);
        await b.canvas.save();
        await b.waitFor(() => !b.state!.isDirty);
      });
      final bytes = server.files[pagePath]!;
      expect(foldedOpsOf(bytes), isEmpty);
      expect(utf8.decode(bytes, allowMalformed: true), isNot(contains('foldedOps')));
      expect(idsOf(await snapshotOnly(id)), ['a0', 'new', 'old']);
      expect(server.directories.any((d) => d.endsWith('/${StrokeOps.folder}')),
          isFalse);

      StrokeOps.read = false; // and the old release reads what B wrote
      await a.run(() async {
        await a.waitFor(() => idsOf(a.state!.pages[kPageFile]).contains('new'));
        expect(idsOf(a.state!.pages[kPageFile]), ['a0', 'new', 'old']);
      });
    });
  });
}
