// The sync engine must reach its backend only through RemoteStore. These
// tests drive SyncService against an in-memory store with no HTTP and no
// ETags: they pass only if nothing WebDAV-specific leaks into the engine,
// which is the precondition for adding a Google Drive backend.

import 'dart:typed_data';

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
    // The base directory is created before it is read: a first sync against
    // an empty account must not fail on a missing folder.
    expect(store.calls.first, 'ensureBaseDirectory');
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
