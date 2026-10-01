// deltaFolderExists decides whether a dirty notebook is marked synced without
// uploading, and whether a notebook missing its root file gets wiped locally.
// An empty folder left by a failed first upload must not count as alive.

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/remote_store.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/fake_remote_store.dart';

/// WebDAV semantics: a missing file is a 404, not a null version.
class _WebDavLikeStore extends FakeRemoteStore {
  @override
  Future<String?> getVersion(String remotePath) async {
    if (!files.containsKey(remotePath)) {
      throw RemoteStoreException('PROPFIND 404', 404);
    }
    return super.getVersion(remotePath);
  }
}

void main() {
  final metadata = NotebookMetadata(
    id: 'nb',
    title: 'T',
    createdAt: DateTime.utc(2020),
    modifiedAt: DateTime.utc(2020),
  );
  const document = DocumentStructure(notebookId: 'nb', pages: []);

  test('a first upload that fails after MKCOL leaves the folder not alive',
      () async {
    final store = _WebDavLikeStore();
    final sync = SyncService(store);
    store.failUploads.add('/AbelNotes/_delta/nb/metadata.json');

    await expectLater(
      sync.syncDelta(
        notebookId: 'nb',
        metadata: metadata,
        document: document,
        dirtyPages: const {},
      ),
      throwsA(anything),
    );
    expect(store.directories, contains('/AbelNotes/_delta/nb/'));
    expect(await sync.deltaFolderExists('nb'), isFalse);

    store.failUploads.clear();
    await sync.syncDelta(
      notebookId: 'nb',
      metadata: metadata,
      document: document,
      dirtyPages: const {},
    );
    expect(await sync.deltaFolderExists('nb'), isTrue);
  });

  test('a backend that reports a missing file as null (Drive) is not alive',
      () async {
    final store = FakeRemoteStore();
    final sync = SyncService(store);
    expect(store.nullVersionMeansAbsent, isTrue);
    expect(await sync.deltaFolderExists('nb'), isFalse);

    await sync.syncDelta(
      notebookId: 'nb',
      metadata: metadata,
      document: document,
      dirtyPages: const {},
    );
    expect(await sync.deltaFolderExists('nb'), isTrue);
    // A fresh engine has no session cache: it must read the server.
    expect(await SyncService(store).deltaFolderExists('nb'), isTrue);
  });
}
