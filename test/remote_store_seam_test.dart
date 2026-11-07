// The sync engine must reach its backend only through RemoteStore. These
// tests drive SyncService against an in-memory store with no HTTP and no
// ETags: they pass only if nothing WebDAV-specific leaks into the engine,
// which is the precondition for adding a Google Drive backend.

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/remote_store.dart';
import 'package:abelnotes/core/services/sync_service.dart';

import 'support/fake_remote_store.dart';

void main() {
  late FakeRemoteStore store;
  late SyncService sync;

  setUp(() {
    store = FakeRemoteStore();
    sync = SyncService(store);
  });

  test('runs against a non-WebDAV backend', () {
    expect(sync.isOffline, isFalse);
    expect(SyncService(null).isOffline, isTrue);
  });

  test('lists only notebooks, ignoring directories and stray files', () async {
    await store.ensureBaseDirectory();
    await store.uploadFile(
        '/AbelNotes/analisi.abelnote', Uint8List.fromList([1]));
    await store.uploadFile('/AbelNotes/README.txt', Uint8List.fromList([2]));
    await store.createDirectory('/AbelNotes/scratch/');

    final found = await sync.listRemoteNotebooks();

    expect(found.map((f) => f.name), ['analisi.abelnote']);
  });

  test('a first sync against an empty account creates the base folder',
      () async {
    final found = await sync.listRemoteNotebooks();

    expect(found, isEmpty);
    expect(store.calls,
        ['list /AbelNotes/', 'ensureBaseDirectory', 'list /AbelNotes/']);
  });

  test('an existing base folder is only listed, never created again',
      () async {
    await store.ensureBaseDirectory();
    store.calls.clear();

    await sync.listRemoteRoot();
    await sync.listRemoteRoot();

    // Each MKCOL on an existing folder logs a 405 on the server (#34).
    expect(store.calls, ['list /AbelNotes/', 'list /AbelNotes/']);
  });

  test('the shared delta folder is created once, not per new notebook',
      () async {
    final zip = Uint8List.fromList(ZipEncoder().encode(Archive()
      ..addFile(ArchiveFile('metadata.json', 2, [123, 125])))!);
    const delta = 'mkdir /AbelNotes/_delta/';
    await store.ensureBaseDirectory();

    await sync.migrateToExploded('a', zip);
    await sync.migrateToExploded('b', zip);
    expect(store.calls.where((c) => c == delta), hasLength(1));

    // A later session that has listed the root already knows it is there.
    store.calls.clear();
    final next = SyncService(store);
    await next.listRemoteRoot();
    await next.migrateToExploded('c', zip);
    expect(store.calls, isNot(contains(delta)));
    expect(store.calls, contains('mkdir /AbelNotes/_delta/c/'));

    // Without that listing it still makes sure, once.
    store.calls.clear();
    final cold = SyncService(store);
    await cold.migrateToExploded('d', zip);
    await cold.migrateToExploded('e', zip);
    expect(store.calls.where((c) => c == delta), hasLength(1));
  });

  test('a failure other than a missing folder is not hidden by a create',
      () async {
    final failing = _FailingListStore(503);
    await expectLater(SyncService(failing).listRemoteRoot(),
        throwsA(isA<RemoteStoreException>()
            .having((e) => e.statusCode, 'statusCode', 503)));
    expect(failing.calls, ['list /AbelNotes/']);
  });

  test('carries the backend version token, whatever it is', () async {
    await store.ensureBaseDirectory();
    await store.uploadFile(
        '/AbelNotes/nb.abelnote', Uint8List.fromList([1, 2, 3]));

    final found = await sync.listRemoteNotebooks();

    // 'v1' is not an ETag and not a checksum. The engine only ever compares
    // these for equality, so a backend is free to use md5Checksum or a
    // revision id.
    expect(found.single.version, 'v1');

    final info = await sync.getNcnoteInfo('/AbelNotes/nb.abelnote');
    expect(info?.etag, 'v1');
  });

  test('a missing notebook surfaces as a 404, not a generic failure',
      () async {
    // The engine branches on this code to mean "not there, stop looking".
    expect(
      () => sync.downloadFile('/AbelNotes/ghost.abelnote'),
      throwsA(isA<RemoteStoreException>()
          .having((e) => e.statusCode, 'statusCode', 404)),
    );
  });
}

class _FailingListStore extends FakeRemoteStore {
  _FailingListStore(this.status);

  final int status;

  @override
  Future<List<RemoteItem>> listDirectory(String remotePath) async {
    calls.add('list $remotePath');
    throw RemoteStoreException('listing failed', status);
  }
}
