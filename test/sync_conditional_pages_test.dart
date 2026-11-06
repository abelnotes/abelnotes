// A page upload must land only over the server version the edit started
// from. A blind PUT replaced strokes another device had just pushed, and that
// device's next pull then read them as deleted and dropped them too.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/remote_store.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/fake_remote_store.dart';

PageData _page(String id, int strokes) => PageData(
      pageId: id,
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: RenderingLayers(content: [
        for (var i = 0; i < strokes; i++)
          ContentElement.stroke(
            id: '$id-$i',
            zIndex: i,
            data: StrokeData(points: [
              StrokePoint(x: 0, y: i.toDouble()),
              StrokePoint(x: 10, y: i.toDouble()),
            ]),
          ),
      ]),
    );

/// A server that answers every If-Match with 412, even for its own version.
class _IfMatchBlindStore extends FakeRemoteStore {
  @override
  Future<String?> uploadFileAtomic(String remotePath, Uint8List data,
      {String? ifMatchVersion, int? timeoutSeconds}) async {
    if (ifMatchVersion == null) {
      return super.uploadFileAtomic(remotePath, data);
    }
    calls.add('upload-atomic-if $remotePath');
    throw RemoteStoreException('precondition failed', 412);
  }
}

void main() {
  final now = DateTime(2026);
  final meta =
      NotebookMetadata(id: 'nb', title: 't', createdAt: now, modifiedAt: now);
  const doc = DocumentStructure(notebookId: 'nb', pages: [
    PageEntry(pageId: 'a', pageNumber: 1, fileName: 'a.json'),
    PageEntry(pageId: 'b', pageNumber: 2, fileName: 'b.json'),
  ]);

  Future<Map<String, String>> firstPush(FakeRemoteStore store, SyncService sync) async {
    final r = await sync.syncDelta(
      notebookId: 'nb',
      metadata: meta,
      document: doc,
      dirtyPages: {'a.json': _page('a', 1), 'b.json': _page('b', 1)},
    );
    return r.pageEtags;
  }

  String pagePath(FakeRemoteStore store, String fn) =>
      store.files.keys.singleWhere((k) => k.endsWith('/pages/$fn'));

  test('a page edited from the current server version goes up', () async {
    final store = FakeRemoteStore();
    final sync = SyncService(store);
    final etags = await firstPush(store, sync);

    final r = await sync.syncDelta(
      notebookId: 'nb',
      metadata: meta,
      document: doc,
      dirtyPages: {'a.json': _page('a', 2)},
      pageBaseVersions: {'a.json': etags['a.json']!},
    );

    expect(r.pageEtags.keys, ['a.json']);
    expect(store.calls.where((c) => c.startsWith('upload-atomic-if')), hasLength(1));
  });

  test('another device wrote the page: nothing lands over it, nothing commits',
      () async {
    final store = FakeRemoteStore();
    final sync = SyncService(store);
    final etags = await firstPush(store, sync);
    final aPath = pagePath(store, 'a.json');
    final theirs = Uint8List.fromList([9, 9, 9]);
    store.files[aPath] = theirs;
    store.bumpVersion(aPath);
    store.calls.clear();

    await expectLater(
      sync.syncDelta(
        notebookId: 'nb',
        metadata: meta,
        document: doc,
        dirtyPages: {'a.json': _page('a', 2), 'b.json': _page('b', 2)},
        pageBaseVersions: {
          'a.json': etags['a.json']!,
          'b.json': etags['b.json']!,
        },
      ),
      throwsA(isA<RemotePagesChangedException>()
          .having((e) => e.fileNames, 'fileNames', ['a.json'])
          .having((e) => e.uploadedEtags.keys, 'uploaded', ['b.json'])),
    );

    expect(store.files[aPath], same(theirs), reason: 'their strokes stay');
    expect(store.calls.any((c) => c.endsWith('document.json')), isFalse);
    expect(store.calls.any((c) => c.endsWith('metadata.json')), isFalse);
  });

  test('a page deleted on the server is not resurrected by the push',
      () async {
    final store = FakeRemoteStore();
    final sync = SyncService(store);
    final etags = await firstPush(store, sync);
    final aPath = pagePath(store, 'a.json');
    await store.delete(aPath);

    await expectLater(
      sync.syncDelta(
        notebookId: 'nb',
        metadata: meta,
        document: doc,
        dirtyPages: {'a.json': _page('a', 2)},
        pageBaseVersions: {'a.json': etags['a.json']!},
      ),
      throwsA(isA<RemotePagesChangedException>()),
    );
    expect(store.files.containsKey(aPath), isFalse);
  });

  test('a page with no known server version still goes up atomically',
      () async {
    final store = FakeRemoteStore();
    final sync = SyncService(store);
    await firstPush(store, sync);
    store.calls.clear();

    await sync.syncDelta(
      notebookId: 'nb',
      metadata: meta,
      document: doc,
      dirtyPages: {'a.json': _page('a', 3)},
    );
    expect(store.calls.any((c) => c.startsWith('upload-atomic-if')), isFalse);
    expect(store.calls.where((c) => c.startsWith('upload-atomic ')),
        hasLength(1));
  });

  test('a server that never honours If-Match falls back to plain uploads',
      () async {
    final store = _IfMatchBlindStore();
    final sync = SyncService(store);
    final etags = await firstPush(store, sync);

    final r = await sync.syncDelta(
      notebookId: 'nb',
      metadata: meta,
      document: doc,
      dirtyPages: {'a.json': _page('a', 2)},
      pageBaseVersions: {'a.json': etags['a.json']!},
    );
    expect(r.pageEtags.keys, ['a.json']);

    // Learned once: the next push does not ask again.
    store.calls.clear();
    await sync.syncDelta(
      notebookId: 'nb',
      metadata: meta,
      document: doc,
      dirtyPages: {'a.json': _page('a', 3)},
      pageBaseVersions: {'a.json': r.pageEtags['a.json']!},
    );
    expect(store.calls.any((c) => c.startsWith('upload-atomic-if')), isFalse);
  });
}
