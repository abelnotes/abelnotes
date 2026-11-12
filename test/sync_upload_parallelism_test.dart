// A big first upload fired every page at once: the connection pool queued
// them, each timeout started at queue time, and the whole upload timed out in
// cascade and restarted. Uploads now go a few at a time.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/fake_remote_store.dart';

/// Counts page uploads in flight; each one takes a few event-loop turns.
/// The fake's atomic upload calls uploadFile itself, so only the outer call
/// for a page is counted.
class _SlowStore extends FakeRemoteStore {
  int inFlight = 0;
  int peak = 0;

  Future<T> _slow<T>(String path, Future<T> Function() f) async {
    if (!path.contains('/pages/')) return f();
    inFlight++;
    if (inFlight > peak) peak = inFlight;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    try {
      return await f();
    } finally {
      inFlight--;
    }
  }

  @override
  Future<String?> uploadFileAtomic(String remotePath, Uint8List data,
          {String? ifMatchVersion, int? timeoutSeconds}) =>
      _slow(
          remotePath,
          () => super.uploadFileAtomic(remotePath, data,
              ifMatchVersion: ifMatchVersion, timeoutSeconds: timeoutSeconds));
}

PageData _page(String id) => PageData(
      pageId: id,
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: RenderingLayers(content: [
        ContentElement.stroke(
          id: '$id-0',
          zIndex: 0,
          data: const StrokeData(points: [
            StrokePoint(x: 0, y: 0),
            StrokePoint(x: 10, y: 0),
          ]),
        ),
      ]),
    );

void main() {
  test('first upload of a 40-page notebook keeps at most 4 page PUTs in flight',
      () async {
    final store = _SlowStore();
    final sync = SyncService(store);
    final now = DateTime(2026);
    final ids = [for (var i = 0; i < 40; i++) 'p$i'];
    final r = await sync.syncDelta(
      notebookId: 'nb',
      metadata: NotebookMetadata(
          id: 'nb', title: 't', createdAt: now, modifiedAt: now),
      document: DocumentStructure(notebookId: 'nb', pages: [
        for (var i = 0; i < ids.length; i++)
          PageEntry(
              pageId: ids[i], pageNumber: i + 1, fileName: '${ids[i]}.json'),
      ]),
      dirtyPages: {for (final id in ids) '$id.json': _page(id)},
    );

    expect(r.pageEtags, hasLength(40));
    expect(store.files.keys.where((k) => k.contains('/pages/')), hasLength(40));
    expect(store.peak, lessThanOrEqualTo(4));
    expect(store.peak, greaterThan(1)); // still parallel, not serial
  });
}
