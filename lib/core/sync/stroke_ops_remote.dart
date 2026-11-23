// The server side of stroke delta chunks for SyncService: listing, reading
// and writing chunks under `<delta dir>/ops/`. Design: README.md.
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:abelnotes/core/notebook/page_codec.dart';
import 'package:abelnotes/core/services/remote_store.dart';
import 'package:abelnotes/core/sync/stroke_ops.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Chunks listed for one notebook: page file → chunk ids, plus their sizes.
class OpsListing {
  OpsListing(this.byPage, this.sizes);
  final Map<String, List<ChunkId>> byPage;
  final Map<String, int> sizes; // by chunk file name

  static final empty = OpsListing(const {}, const {});
}

class StrokeOpsRemote {
  StrokeOpsRemote(this._remote, {String? device, Random? random})
      : device = device ?? newDeviceTag(random);

  final RemoteStore _remote;

  /// This writer's tag in chunk names.
  final String device;

  int _clock = 0;

  final Map<String, OpsListing> _listed = {};
  final Map<String, ({String version, PageData page, Set<ChunkId> folded, int size})>
      _snapshots = {};
  final Map<String, OpChunk> _chunks = {};
  final Map<String, Set<ChunkId>> _damaged = {};
  final Map<String, ({String version, PageData page})> _bases = {};
  final Set<String> _dirsReady = {};

  /// The next chunk clock: hybrid Lamport, past every clock seen.
  int nextClock() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _clock = max(_clock + 1, now);
    return _clock;
  }

  /// Lists `<dir>ops/`; no folder is no chunks.
  Future<OpsListing> list(String notebookId, String dir) async {
    List<RemoteItem> items;
    try {
      items = await _remote.listDirectory('$dir${StrokeOps.folder}');
    } on RemoteStoreException catch (e) {
      if (e.statusCode != 404) rethrow;
      items = const [];
    }
    final byPage = <String, List<ChunkId>>{};
    final sizes = <String, int>{};
    final modified = <String, DateTime>{};
    for (final item in items) {
      if (item.isDirectory) continue;
      final parsed = parseChunkFileName(item.name);
      if (parsed == null) continue;
      if (parsed.id.clock > _clock) _clock = parsed.id.clock;
      (byPage[parsed.pageFile] ??= []).add(parsed.id);
      if (item.contentLength != null) sizes[item.name] = item.contentLength!;
      if (item.lastModified != null) modified[item.name] = item.lastModified!;
    }
    for (final l in byPage.values) {
      l.sort();
    }
    _modified[notebookId] = modified;
    return _listed[notebookId] = OpsListing(byPage, sizes);
  }

  final Map<String, Map<String, DateTime>> _modified = {};

  /// Deletes chunks of pages not in [pageFiles] (deleted pages, often by a
  /// release that does not know chunks) once they are an hour old.
  void sweepOrphans(String notebookId, String dir, Set<String> pageFiles) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    final modified = _modified[notebookId] ?? const {};
    listed(notebookId).byPage.forEach((fileName, ids) {
      if (pageFiles.contains(fileName)) return;
      for (final id in ids) {
        final name = chunkFileName(fileName, id);
        final lm = modified[name];
        if (lm == null || lm.isAfter(cutoff)) continue;
        unawaited(_remote
            .delete('$dir${StrokeOps.folder}$name')
            .catchError((Object _) {}));
      }
    });
  }

  OpsListing listed(String notebookId) =>
      _listed[notebookId] ?? OpsListing.empty;

  /// Page versions: each snapshot etag with the chunks listed for its page.
  Map<String, String> versions(
          Map<String, String> snapshots, OpsListing listing) =>
      {
        for (final e in snapshots.entries)
          e.key: pageVersion(e.value, listing.byPage[e.key] ?? const []),
      };

  /// The page [fileName] at [version] (snapshot plus its chunks). Records it
  /// as this page's server baseline.
  Future<PageData> download(
      String notebookId, String dir, String fileName, String version) async {
    final want = splitPageVersion(version);
    final key = '$notebookId/$fileName';
    final path = '${dir}pages/$fileName';
    var snap = await _snapshot(key, path, want.snapshot);
    for (var attempt = 0;; attempt++) {
      final chunks = <OpChunk>[];
      var missing = false;
      for (final id in want.chunks) {
        if (snap.folded.contains(id)) continue;
        final chunk = await _chunk(notebookId, dir, fileName, id);
        if (chunk == null) {
          missing = true;
          break;
        }
        chunks.add(chunk);
      }
      if (!missing) {
        final page = applyChunks(snap.page, chunks);
        _bases[key] = (version: version, page: page);
        return page;
      }
      // Gone: a compaction folded it, so a fresh snapshot must name it.
      if (attempt > 0) {
        throw RemoteStoreException('a chunk of $fileName vanished', 503);
      }
      snap = await _snapshot(key, path, null);
    }
  }

  Future<({String version, PageData page, Set<ChunkId> folded, int size})>
      _snapshot(String key, String path, String? version) async {
    final cached = _snapshots[key];
    if (version != null && cached != null && cached.version == version) {
      return cached;
    }
    final bytes = await _remote.downloadFile(path);
    final page = decodePageBytes(bytes);
    final entry = (
      version: version ?? '',
      page: page,
      folded: foldedOpsOf(bytes),
      size: bytes.length,
    );
    if (version != null) _snapshots[key] = entry;
    return entry;
  }

  /// A chunk by id, null when the server no longer has it.
  Future<OpChunk?> _chunk(
      String notebookId, String dir, String fileName, ChunkId id) async {
    final name = chunkFileName(fileName, id);
    final key = '$notebookId/$name';
    final cached = _chunks[key];
    if (cached != null) return cached;
    final Uint8List bytes;
    try {
      bytes = await _remote.downloadFile('$dir${StrokeOps.folder}$name');
    } on RemoteStoreException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
    try {
      return _chunks[key] = decodeChunk(bytes);
    } on FormatException {
      (_damaged['$notebookId/$fileName'] ??= {}).add(id);
      rethrow;
    }
  }

  /// What this service last read or wrote for a page, and at which version.
  ({String version, PageData page})? baseOf(String notebookId, String fileName) =>
      _bases['$notebookId/$fileName'];

  void recordBase(
          String notebookId, String fileName, String version, PageData page) =>
      _bases['$notebookId/$fileName'] = (version: version, page: page);

  /// Chunks a whole-page write over [baseVersion] contains: those of the
  /// version, plus damaged ones nobody can read.
  Set<ChunkId> foldedBy(String notebookId, String fileName, String? baseVersion) => {
        if (baseVersion != null) ...splitPageVersion(baseVersion).chunks,
        ...?_damaged['$notebookId/$fileName'],
      };

  /// Deletes chunks of [fileName], best effort: a survivor is skipped by
  /// readers through the snapshot's folded marker.
  Future<void> deleteChunks(
      String notebookId, String dir, String fileName, Iterable<ChunkId> ids) async {
    await Future.wait(ids.map((id) async {
      final name = chunkFileName(fileName, id);
      try {
        await _remote.delete('$dir${StrokeOps.folder}$name');
      } on RemoteStoreException catch (e) {
        if (e.statusCode != 404) {
          debugPrint('[Ops] delete of $name failed: $e');
        }
      } catch (e) {
        debugPrint('[Ops] delete of $name failed: $e');
      }
      _chunks.remove('$notebookId/$name');
    }));
    _damaged['$notebookId/$fileName']?.removeAll(ids);
  }

  /// All listed chunks of [fileName], for deleting the page.
  List<ChunkId> chunksOf(String notebookId, String fileName) =>
      listed(notebookId).byPage[fileName] ?? const [];

  /// Writes [chunk] for [fileName]; returns its id.
  Future<ChunkId> write(String dir, String fileName, OpChunk chunk,
      {int? timeoutSeconds}) async {
    if (_dirsReady.add(dir)) {
      try {
        await _remote.createDirectory('$dir${StrokeOps.folder}');
      } catch (e) {
        _dirsReady.remove(dir);
        rethrow;
      }
    }
    final id = ChunkId(device, nextClock());
    await _remote.uploadFileAtomic(
        '$dir${StrokeOps.folder}${chunkFileName(fileName, id)}',
        encodeChunk(chunk),
        timeoutSeconds: timeoutSeconds);
    return id;
  }

  /// Total size of the chunks of [version] that the last listing knows.
  int chunkBytes(String notebookId, String fileName, String version) {
    final sizes = listed(notebookId).sizes;
    var n = 0;
    for (final id in splitPageVersion(version).chunks) {
      n += sizes[chunkFileName(fileName, id)] ?? 0;
    }
    return n;
  }

  /// This service wrote [page] as the snapshot of [fileName] at [version].
  void wroteSnapshot(String notebookId, String fileName, String version,
      PageData page, Set<ChunkId> folded, int size) {
    final key = '$notebookId/$fileName';
    _snapshots[key] = (version: version, page: page, folded: folded, size: size);
    _bases[key] = (version: version, page: page);
  }

  /// Size of the cached snapshot of [fileName], 0 when unknown.
  int snapshotBytes(String notebookId, String fileName) =>
      _snapshots['$notebookId/$fileName']?.size ?? 0;

  void forget(String notebookId) {
    _listed.remove(notebookId);
    _modified.remove(notebookId);
    final prefix = '$notebookId/';
    _snapshots.removeWhere((k, _) => k.startsWith(prefix));
    _chunks.removeWhere((k, _) => k.startsWith(prefix));
    _damaged.removeWhere((k, _) => k.startsWith(prefix));
    _bases.removeWhere((k, _) => k.startsWith(prefix));
  }
}
