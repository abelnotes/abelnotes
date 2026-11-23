// Stroke delta chunks through SyncService and a fake server: versions,
// reading pages with chunks, page writes folding them, and releases that
// do not know chunks reading the same folder.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/notebook/page_codec.dart';
import 'package:abelnotes/core/services/remote_store.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/core/sync/stroke_ops.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/fake_remote_store.dart';

ContentElement line(String id, double y, {double x = 10}) =>
    ContentElement.stroke(
      id: id,
      zIndex: 0,
      data: StrokeData(points: [
        StrokePoint(x: x, y: y, pressure: 0.6, timestamp: 1781849370321),
        StrokePoint(x: x + 90, y: y, pressure: 0.5, timestamp: 1781849370330),
      ]),
    );

PageData page(List<ContentElement> content) => PageData(
      pageId: 'pg-a',
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: RenderingLayers(content: content),
    );

List<String> ids(PageData p) => [for (final e in p.layers.content) e.id];

const nb = 'nb';
const fn = 'page_001.json';
final _now = DateTime(2026);
final meta = NotebookMetadata(id: nb, title: 't', createdAt: _now, modifiedAt: _now);
const doc = DocumentStructure(notebookId: nb, pages: [
  PageEntry(pageId: 'pg-a', pageNumber: 1, fileName: fn),
]);

const dir = '/AbelNotes/_delta/nb/';

Future<String> pushPage(SyncService s, PageData p, {String? base}) async {
  final r = await s.syncDelta(
    notebookId: nb,
    metadata: meta,
    document: doc,
    dirtyPages: {fn: p},
    pageBaseVersions: {if (base != null) fn: base},
  );
  return r.pageEtags[fn]!;
}

/// Writes a chunk the way a writer would: diff of [from] to [to].
Future<ChunkId> chunk(SyncService s, PageData from, PageData to) =>
    s.strokeOps.write(dir, fn, diffPage(from, to)!);

void main() {
  late FakeRemoteStore store;
  late SyncService a;

  setUp(() {
    StrokeOps.read = true;
    store = FakeRemoteStore();
    a = SyncService(store);
  });
  tearDown(StrokeOps.restoreDefaults);

  test('the delta folder path is what the tests expect', () async {
    await pushPage(a, page([line('a', 1)]));
    expect(store.files.keys, contains('${dir}pages/$fn'));
  });

  test('no chunks: versions are the bare etags, pages the snapshot', () async {
    final etag = await pushPage(a, page([line('a', 1)]));
    expect(await a.getRemotePageEtags(nb), {fn: etag});
    expect(await a.getPageVersions(nb, [fn]), {fn: etag});
    expect(ids(await a.downloadDeltaPage(nb, fn, version: etag)), ['a']);
  });

  test('chunks: version names them, the page applies them, a second read '
      'fetches only the new chunk', () async {
    final p0 = page([line('a', 1)]);
    final etag = await pushPage(a, p0);
    final p1 = page([...p0.layers.content, line('b', 2)]);
    final c1 = await chunk(a, p0, p1);

    final b = SyncService(store);
    final v1 = (await b.getRemotePageEtags(nb))[fn]!;
    expect(v1, pageVersion(etag, [c1]));
    expect(await b.getPageVersions(nb, [fn]), {fn: v1});
    expect(ids(await b.downloadDeltaPage(nb, fn, version: v1)), ['a', 'b']);

    final c2 = await chunk(a, p1, page([...p1.layers.content, line('c', 3)]));
    final v2 = (await b.getRemotePageEtags(nb))[fn]!;
    expect(splitPageVersion(v2).chunks, [c1, c2]);
    store.calls.clear();
    expect(ids(await b.downloadDeltaPage(nb, fn, version: v2)), ['a', 'b', 'c']);
    expect(store.calls.where((c) => c.startsWith('download')),
        ['download $dir${StrokeOps.folder}${chunkFileName(fn, c2)}']);
  });

  test('a page write folds the chunks of its base: marked, deleted, and an '
      'old release reads everything from the snapshot', () async {
    final p0 = page([line('a', 1)]);
    final etag = await pushPage(a, p0);
    final p1 = page([...p0.layers.content, line('b', 2, x: 5)]);
    final c1 = await chunk(a, p0, p1);
    final v1 = (await a.getRemotePageEtags(nb))[fn]!;
    final pulled = await a.downloadDeltaPage(nb, fn, version: v1);
    final moved = page([line('a', 1), line('b', 2, x: 50)]);
    expect(diffPage(pulled, moved), isNotNull);

    final etag2 = await pushPage(a, moved, base: v1);
    expect(etag2, isNot(etag));
    final snapshot = store.files['${dir}pages/$fn']!;
    expect(foldedOpsOf(snapshot), {c1});
    expect(store.files.keys.where((k) => k.contains(StrokeOps.folder)), isEmpty);

    StrokeOps.read = false; // a release without chunks
    final old = await SyncService(store).downloadDeltaPage(nb, fn);
    expect(old, decodePageBytes(snapshot));
    expect((old.layers.content[1] as StrokeElement).data.points.first.x, 50);
  });

  test('a folded chunk that survived its delete is not applied again',
      () async {
    final p0 = page([line('a', 1)]);
    await pushPage(a, p0);
    final p1 = page([line('a', 1, x: 5)]);
    final c1 = await chunk(a, p0, p1);
    final v1 = (await a.getRemotePageEtags(nb))[fn]!;
    await a.downloadDeltaPage(nb, fn, version: v1);
    // The delete of the folded chunk is lost.
    final kept = store.files['$dir${StrokeOps.folder}${chunkFileName(fn, c1)}']!;
    await pushPage(a, page([line('a', 1, x: 80)]), base: v1);
    store.files['$dir${StrokeOps.folder}${chunkFileName(fn, c1)}'] = kept;

    final b = SyncService(store);
    final v = (await b.getRemotePageEtags(nb))[fn]!;
    expect(splitPageVersion(v).chunks, [c1]);
    final p = await b.downloadDeltaPage(nb, fn, version: v);
    expect((p.layers.content.single as StrokeElement).data.points.first.x, 80);
  });

  test('a chunk deleted by a compaction under a reader: the reader takes the '
      'new snapshot', () async {
    final p0 = page([line('a', 1)]);
    await pushPage(a, p0);
    final p1 = page([...p0.layers.content, line('b', 2)]);
    await chunk(a, p0, p1);
    final b = SyncService(store);
    final v1 = (await b.getRemotePageEtags(nb))[fn]!;
    // A compacts between B's listing and B's download.
    final pulled = await a.downloadDeltaPage(nb, fn, version: v1);
    await pushPage(a, pulled, base: v1);
    expect(ids(await b.downloadDeltaPage(nb, fn, version: v1)), ['a', 'b']);
  });

  test('deleting a page deletes its chunks; leftovers never reach a new page '
      'with the same file name', () async {
    final p0 = page([line('a', 1)]);
    await pushPage(a, p0);
    final c1 = await chunk(a, p0, page([...p0.layers.content, line('b', 2)]));
    await a.getRemotePageEtags(nb);
    await a.syncDelta(
        notebookId: nb,
        metadata: meta,
        document: const DocumentStructure(notebookId: nb, pages: []),
        dirtyPages: const {},
        deletedPageFileNames: [fn]);
    expect(store.files.keys.where((k) => k.contains(StrokeOps.folder)), isEmpty);

    // A release without chunks deletes only the page: the chunk stays.
    final orphan = encodeChunk(diffPage(p0, page([...p0.layers.content, line('b', 2)]))!);
    store.files['$dir${StrokeOps.folder}${chunkFileName(fn, c1)}'] = orphan;
    final reused = PageData(
        pageId: 'pg-new', pageNumber: 1, width: 595, height: 842,
        layers: RenderingLayers(content: [line('z', 9)]));
    await pushPage(a, reused);
    final v = (await a.getRemotePageEtags(nb))[fn]!;
    expect(ids(await a.downloadDeltaPage(nb, fn, version: v)), ['z']);
  });

  test('a damaged chunk fails the read as damage; the next page write folds '
      'and deletes it', () async {
    final p0 = page([line('a', 1)]);
    await pushPage(a, p0);
    final c1 = await chunk(a, p0, page([...p0.layers.content, line('b', 2)]));
    final path = '$dir${StrokeOps.folder}${chunkFileName(fn, c1)}';
    store.files[path] = Uint8List.fromList(utf8.encode('garbage'));
    final b = SyncService(store);
    final v = (await b.getRemotePageEtags(nb))[fn]!;
    await expectLater(
        b.downloadDeltaPage(nb, fn, version: v), throwsFormatException);
    await pushPage(b, p0, base: splitPageVersion(v).snapshot);
    expect(store.files.containsKey(path), isFalse);
    expect(foldedOpsOf(store.files['${dir}pages/$fn']!), {c1});
  });

  test('an ops listing that fails is a failure, not "no chunks"', () async {
    await pushPage(a, page([line('a', 1)]));
    final failing = _FailingOpsStore(store);
    await expectLater(SyncService(failing).getRemotePageEtags(nb),
        throwsA(isA<RemoteStoreException>()));
  });

  test('an hour-old chunk of a page the listing lacks: a device that only '
      'reads keeps it, a writer sweeps it', () async {
    await pushPage(a, page([line('a', 1)]));
    final p0 = page([line('x', 1)]);
    final orphan = '$dir${StrokeOps.folder}'
        '${chunkFileName('page_009.json', const ChunkId('k3f9a2x1', 1))}';
    store.directories.add('$dir${StrokeOps.folder}');
    store.files[orphan] =
        encodeChunk(diffPage(p0, page([...p0.layers.content, line('y', 2)]))!);
    store.lastModified[orphan] =
        DateTime.now().subtract(const Duration(hours: 2));

    await SyncService(store).getRemotePageEtags(nb);
    await pumpEventQueue();
    expect(store.files.containsKey(orphan), isTrue);

    StrokeOps.write = true;
    await SyncService(store).getRemotePageEtags(nb);
    await pumpEventQueue();
    expect(store.files.containsKey(orphan), isFalse);
  });

  group('writing chunks', () {
    setUp(() => StrokeOps.write = true);

    /// [s] pushes [p] over what it last read or wrote for the page.
    Future<String> save(SyncService s, PageData p, String base,
        {Set<String> compact = const {}}) async {
      final r = await s.syncDelta(
        notebookId: nb,
        metadata: meta,
        document: doc,
        dirtyPages: {fn: p},
        pageBaseVersions: {fn: base},
        pageBaselines: {fn: s.strokeOps.baseOf(nb, fn)!.page},
        compactPages: compact,
      );
      return r.pageEtags[fn]!;
    }

    /// [s] reads the page as the pull does: listing, then download.
    Future<(String, PageData)> pull(SyncService s) async {
      final v = (await s.getRemotePageEtags(nb))[fn]!;
      return (v, await s.downloadDeltaPage(nb, fn, version: v));
    }

    int pagePuts() => store.calls
        .where((c) => c.startsWith('upload ') && c.contains('/pages/'))
        .length;

    test('a stroke goes up as a chunk, not as the page', () async {
      final p0 = page([line('a', 1)]);
      final v0 = await pushPage(a, p0);
      store.calls.clear();
      final v1 = await save(a, page([...p0.layers.content, line('b', 2)]), v0);
      expect(pagePuts(), 0);
      expect(splitPageVersion(v1).snapshot, v0);
      expect(splitPageVersion(v1).chunks, hasLength(1));
      expect((await a.getRemotePageEtags(nb))[fn], v1,
          reason: 'what the push reports is what the listing says');
      final (_, onServer) = await pull(SyncService(store));
      expect(ids(onServer), ['a', 'b']);
    });

    test('two devices drawing on one page offline, then both online: '
        'both strokes, no conflict', () async {
      final p0 = page([line('a', 1)]);
      final v0 = await pushPage(a, p0);
      final b = SyncService(store);
      final (vb, pb) = await pull(b);
      expect(vb, v0);
      final va1 = await save(a, page([...p0.layers.content, line('sa', 2)]), v0);
      // B never saw A's chunk: its push still lands, nothing is refused.
      final vb1 = await save(b, page([...pb.layers.content, line('sb', 3)]), vb);
      expect(vb1, isNot(va1));
      final (v, merged) = await pull(SyncService(store));
      expect(ids(merged), ['a', 'sa', 'sb']);
      expect(splitPageVersion(v).chunks, hasLength(2));
      expect(pagePuts(), 1, reason: 'only the first page write');
    });

    test('an erase and a concurrent stroke both stand', () async {
      final p0 = page([line('a', 1), line('b', 2)]);
      final v0 = await pushPage(a, p0);
      final b = SyncService(store);
      final (vb, pb) = await pull(b);
      await save(a, page([line('b', 2)]), v0);
      await save(b, page([...pb.layers.content, line('n', 3)]), vb);
      final (_, merged) = await pull(SyncService(store));
      expect(ids(merged), ['b', 'n']);
    });

    test('two moves of one stroke: the later clock wins', () async {
      final p0 = page([line('a', 1)]);
      final v0 = await pushPage(a, p0);
      final b = SyncService(store);
      final (vb, _) = await pull(b);
      await save(a, page([line('a', 1, x: 111)]), v0);
      await b.getRemotePageEtags(nb); // B's clock moves past A's chunk
      await save(b, page([line('a', 1, x: 222)]), vb);
      final (_, merged) = await pull(SyncService(store));
      expect((merged.layers.content.single as StrokeElement).data.points.first.x,
          222);
    });

    test('two devices compact at once: one wins, the other must merge, and a '
        'chunk written meanwhile stays', () async {
      final p0 = page([line('a', 1)]);
      final v0 = await pushPage(a, p0);
      await save(a, page([...p0.layers.content, line('c1', 2)]), v0);
      final b = SyncService(store), c = SyncService(store);
      final (va, pa) = await pull(a);
      final (vb, pb) = await pull(b);
      final (vc, pc) = await pull(c);
      await save(a, pa, va, compact: {fn});
      await expectLater(save(b, pb, vb, compact: {fn}),
          throwsA(isA<RemotePagesChangedException>()));
      await save(c, page([...pc.layers.content, line('c2', 3)]), vc);
      final (v, merged) = await pull(SyncService(store));
      expect(ids(merged), ['a', 'c1', 'c2']);
      expect(splitPageVersion(v).chunks, hasLength(1), reason: 'c2 only');
      StrokeOps.read = false;
      expect(ids(await SyncService(store).downloadDeltaPage(nb, fn)),
          ['a', 'c1'], reason: 'a release without chunks: the snapshot');
    });

    test('a baseline that is not what this service read writes the page',
        () async {
      final p0 = page([line('a', 1)]);
      final v0 = await pushPage(a, p0);
      store.calls.clear();
      await a.syncDelta(
        notebookId: nb,
        metadata: meta,
        document: doc,
        dirtyPages: {fn: page([line('b', 2)])},
        pageBaseVersions: {fn: v0},
        pageBaselines: {fn: page(const [])}, // rebuilt after a restart
      );
      expect(pagePuts(), 1);
      final (_, onServer) = await pull(SyncService(store));
      expect(ids(onServer), ['b'], reason: 'the erase of a is kept');
    });

    test('a page full of chunks is compacted by the next save', () async {
      var p = page([line('a', 0)]);
      var v = await pushPage(a, p);
      for (var i = 0; i < StrokeOps.maxLiveChunks; i++) {
        p = page([...p.layers.content, line('s$i', i + 1.0)]);
        v = await save(a, p, v);
      }
      expect(splitPageVersion(v).chunks, hasLength(StrokeOps.maxLiveChunks));
      store.calls.clear();
      p = page([...p.layers.content, line('last', 99)]);
      v = await save(a, p, v);
      expect(pagePuts(), 1);
      expect(splitPageVersion(v).chunks, isEmpty);
      expect(store.files.keys.where((k) => k.contains(StrokeOps.folder)), isEmpty);
      final (_, onServer) = await pull(SyncService(store));
      expect(onServer.layers.content, hasLength(StrokeOps.maxLiveChunks + 2));
    });

    test('a chunk for a page deleted meanwhile is taken back and the push '
        'must merge', () async {
      final p0 = page([line('a', 1)]);
      final v0 = await pushPage(a, p0);
      store.files.remove('${dir}pages/$fn'); // deleted on another device
      await expectLater(
          save(a, page([...p0.layers.content, line('b', 2)]), v0),
          throwsA(isA<RemotePagesChangedException>()));
      expect(store.files.keys.where((k) => k.contains(StrokeOps.folder)), isEmpty);
    });
  });
}

class _FailingOpsStore extends FakeRemoteStore {
  _FailingOpsStore(FakeRemoteStore from) {
    files.addAll(from.files);
    directories.addAll(from.directories);
  }

  @override
  Future<List<RemoteItem>> listDirectory(String remotePath) async {
    if (remotePath.endsWith(StrokeOps.folder)) {
      throw RemoteStoreException('PROPFIND 500', 500);
    }
    return super.listDirectory(remotePath);
  }
}
