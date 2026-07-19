import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:abelnotes/config/app_config.dart';

/// Manages local notebook files and the sync-metadata database.
///
/// Directory layout (inside getApplicationDocumentsDirectory()):
///   AbelNotes/
///     notebooks/
///       <notebookId>.ncnote        ← full ZIP archive
///     snapshots/
///       <notebookId>/
///         <timestamp>.ncnote       ← rolling local backups (last 3)
///     trash/
///       <trashId>.ncnote           ← soft-deleted notebooks
///       <trashId>.meta.json        ← metadata sidecar for restore
///     abelnotes.db                 ← sync metadata
class FileService {
  /// Max rolling backups to keep per notebook.
  static const int _maxSnapshots = 3;

  late final String _basePath;
  late final String _notebooksDir;
  late final String _snapshotsDir;
  late final String _trashDir;
  late final Database _db;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Per-notebook save serialisation. Two concurrent writers (e.g. save()
  /// and _savePulledChangesLocally()) must not race on the same .ncnote
  /// path or the later rename can truncate the earlier ZIP mid-flush.
  final Map<String, Future<void>> _saveLocks = {};

  /// Counter used to guarantee a unique tmp filename per-invocation so two
  /// concurrent writers on the same notebook never stomp each other's tmp
  /// file (each then rename-atomically into the real path, serialised via
  /// [_saveLocks]).
  int _tmpCounter = 0;

  // ── Initialization ──

  Future<void> init() async {
    if (_initialized) return;

    final appDir = await getApplicationDocumentsDirectory();
    _basePath = p.join(appDir.path, AppConfig.appDirName);
    _notebooksDir = p.join(_basePath, 'notebooks');
    _snapshotsDir = p.join(_basePath, 'snapshots');
    _trashDir = p.join(_basePath, 'trash');

    await Directory(_notebooksDir).create(recursive: true);
    await Directory(_snapshotsDir).create(recursive: true);
    await Directory(_trashDir).create(recursive: true);

    _db = await openDatabase(
      p.join(_basePath, AppConfig.dbName),
      version: AppConfig.dbVersion,
      onCreate: _createTables,
      onUpgrade: _upgradeTables,
    );
    await _migrateRemotePathPrefix();

    _initialized = true;
    debugPrint('[FileService] Initialized at $_basePath');
  }

  /// One-time fixup for the HandWriter → AbelNotes rename: notebooks
  /// registered under the old build have `remote_path` stored with the old
  /// '/HandWriter/' prefix baked in (it's computed once at registration
  /// time, not re-derived from [AppConfig.defaultRemotePath] on every
  /// sync). Idempotent — after the first run no row matches the old prefix
  /// so this is a cheap no-op on every later launch. The server-side folder
  /// still has to be renamed by hand to match; this only fixes the local
  /// index.
  Future<void> _migrateRemotePathPrefix() async {
    const old = AppConfig.legacyRemotePath;
    const next = AppConfig.defaultRemotePath;
    if (old == next) return;
    await _db.rawUpdate(
      "UPDATE notebooks SET remote_path = ? || substr(remote_path, ?) "
      "WHERE remote_path LIKE ?",
      [next, old.length + 1, '$old%'],
    );
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notebooks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        remote_path TEXT NOT NULL,
        etag TEXT,
        local_modified_at TEXT NOT NULL,
        remote_modified_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        file_size INTEGER,
        cover_color INTEGER,
        paper_type TEXT,
        page_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE dirty_pages (
        notebook_id TEXT NOT NULL,
        page_id TEXT NOT NULL,
        modified_at TEXT NOT NULL,
        PRIMARY KEY (notebook_id, page_id),
        FOREIGN KEY (notebook_id) REFERENCES notebooks(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    // Future schema migrations go here
  }

  // ── Local File I/O ──

  /// Returns the local filesystem path for a notebook.
  String localPath(String notebookId) =>
      p.join(_notebooksDir, '$notebookId${AppConfig.fileExtension}');

  /// Saves a raw .ncnote archive to local storage.
  ///
  /// Before overwriting the existing file, snapshots the previous version
  /// to `snapshots/<id>/<timestamp>.ncnote` keeping only the latest [_maxSnapshots].
  Future<void> saveNotebookFile(String notebookId, Uint8List data) async {
    // Serialise concurrent writes to the same notebook so the later rename
    // never overwrites an in-flight tmp file and so the two producers don't
    // each leave a truncated .ncnote behind (the "save() vs _savePulledChanges
    // Locally() race" path).
    final prev = _saveLocks[notebookId];
    final completer = Completer<void>();
    _saveLocks[notebookId] = completer.future;
    try {
      if (prev != null) {
        try { await prev; } catch (_) {}
      }
      await _writeNotebookAtomic(notebookId, data);
      // Keep the loose store (the read source of truth) consistent with this
      // FULL write — the occasional paths: server download, import, rename,
      // cover/paper change, duplicate, pulled-changes save. Same lock, so no
      // _saveLocks re-entrancy. Best-effort: a failure here just leaves the
      // loose store stale until the next full write / incremental save; the
      // freshly-written legacy file is still correct.
      try {
        await _explodeZipUnlocked(notebookId, data);
      } catch (e) {
        debugPrint('[FileService] Loose-store sync after full write '
            'failed for $notebookId: $e');
      }
    } finally {
      completer.complete();
      if (identical(_saveLocks[notebookId], completer.future)) {
        _saveLocks.remove(notebookId);
      }
    }
  }

  Future<void> _writeNotebookAtomic(String notebookId, Uint8List data) async {
    final path = localPath(notebookId);

    // Roll a snapshot of the previous version (best-effort, never blocks save).
    try {
      final existing = File(path);
      if (await existing.exists()) {
        await _rotateSnapshot(notebookId, existing);
      }
    } catch (e) {
      debugPrint('[FileService] Snapshot rotation failed for $notebookId: $e');
    }

    // Unique tmp path per call — belt-and-braces alongside _saveLocks so a
    // crash mid-save never leaves a stale "$path.tmp" that a subsequent save
    // would silently overwrite.
    final ts = DateTime.now().microsecondsSinceEpoch;
    final seq = (++_tmpCounter).toRadixString(36);
    final rand = math.Random().nextInt(1 << 31).toRadixString(36);
    final tmpPath = '$path.$ts-$seq-$rand.tmp';
    final tmpFile = File(tmpPath);
    try {
      await tmpFile.writeAsBytes(data, flush: true);
      await tmpFile.rename(path);
      debugPrint('[FileService] Saved $notebookId (${data.length} bytes)');
    } catch (e) {
      // Clean the tmp file on any failure so we don't leak scratch files.
      try { if (await tmpFile.exists()) await tmpFile.delete(); } catch (_) {}
      rethrow;
    }
  }

  /// Copies the current .ncnote into the snapshot folder and prunes older ones.
  Future<void> _rotateSnapshot(String notebookId, File source) async {
    final dir = Directory(p.join(_snapshotsDir, notebookId));
    await dir.create(recursive: true);

    // Microsecond + counter stamp so two rotations landing on the same
    // millisecond don't collide (older snapshot would otherwise be
    // silently overwritten on the second `copy`).
    final micro = DateTime.now().microsecondsSinceEpoch;
    final seq = (++_tmpCounter).toRadixString(36);
    final stamp = '${micro}_$seq';
    final dest = File(p.join(dir.path, '$stamp${AppConfig.fileExtension}'));
    await source.copy(dest.path);

    // Prune old snapshots (keep newest _maxSnapshots).
    final snapshots = await dir
        .list()
        .where((e) => e is File && e.path.endsWith(AppConfig.fileExtension))
        .toList();
    snapshots.sort((a, b) => b.path.compareTo(a.path)); // timestamps sort lexically
    for (var i = _maxSnapshots; i < snapshots.length; i++) {
      try { await snapshots[i].delete(); } catch (_) {}
    }
  }

  /// Lists available snapshots for a notebook, newest first.
  /// Each entry is (timestamp, absolute path).
  Future<List<(DateTime, String)>> listSnapshots(String notebookId) async {
    final dir = Directory(p.join(_snapshotsDir, notebookId));
    if (!await dir.exists()) return const [];
    final out = <(DateTime, String)>[];
    await for (final entry in dir.list()) {
      if (entry is! File || !entry.path.endsWith(AppConfig.fileExtension)) continue;
      final name = p.basenameWithoutExtension(entry.path);
      // Accept both legacy "1700000000000" (ms) and new "1700000000000000_3q"
      // (µs + counter) naming so existing snapshots remain listable.
      final stampPart = name.split('_').first;
      final stampInt = int.tryParse(stampPart);
      if (stampInt == null) continue;
      final ms = stampInt > 100000000000000 // µs if beyond year ~5138 in ms
          ? stampInt ~/ 1000
          : stampInt;
      out.add((DateTime.fromMillisecondsSinceEpoch(ms), entry.path));
    }
    out.sort((a, b) => b.$1.compareTo(a.$1));
    return out;
  }

  /// Restores a snapshot as the current notebook file.
  Future<void> restoreSnapshot(String notebookId, String snapshotPath) async {
    final src = File(snapshotPath);
    if (!await src.exists()) throw StateError('Snapshot not found: $snapshotPath');
    final data = await src.readAsBytes();
    await saveNotebookFile(notebookId, data); // will also snapshot the current version
  }

  /// Reads a raw .ncnote archive from local storage.
  ///
  /// Prefers the incremental loose store (a directory of per-page / per-asset
  /// files) when present — assembling the `.ncnote` ZIP on demand — and falls
  /// back to the legacy monolithic `<id>.ncnote` file otherwise. Returns null
  /// if neither exists. Every existing consumer (sync upload, search, rename,
  /// export, trash) keeps getting a full ZIP and needs no change; only the
  /// hot-path *save* writes the loose store directly via
  /// [saveNotebookIncremental], so a one-page edit no longer rewrites the whole
  /// notebook.
  Future<Uint8List?> readNotebookFile(String notebookId) async {
    if (await hasLooseStore(notebookId)) {
      final zip = await assembleZipFromLooseStore(notebookId);
      if (zip != null) return zip;
      // Loose store unreadable for some reason — fall through to legacy file.
    }
    final file = File(localPath(notebookId));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  // ══════════════════════════════════════════════════════════════════════
  //  Incremental "loose store"
  //
  //  Local working copy of a notebook as a DIRECTORY mirroring the .ncnote
  //  ZIP layout (and the server's `.sync/<id>/` delta layout):
  //
  //    notebooks/<id>/
  //      metadata.json
  //      document.json
  //      pages/<fileName>          (e.g. page_001.json)
  //      assets/<assetId>
  //      symbols.json              (optional)
  //
  //  A one-page edit writes ONE small page file instead of rebuilding +
  //  re-snapshotting the entire (here ~232 MB) ZIP. The `.ncnote` ZIP becomes
  //  a derived/interchange artifact, assembled on demand for the consumers
  //  that still want a single blob. The legacy `<id>.ncnote` file is the
  //  fallback for notebooks not yet migrated and is exploded into the loose
  //  store lazily on first access.
  // ══════════════════════════════════════════════════════════════════════

  /// Directory backing the incremental loose store for [notebookId].
  /// Distinct from [localPath] (which ends in `.ncnote`), so the two coexist.
  String notebookStoreDir(String notebookId) =>
      p.join(_notebooksDir, notebookId);

  /// True when the incremental loose store exists for [notebookId].
  Future<bool> hasLooseStore(String notebookId) =>
      Directory(notebookStoreDir(notebookId)).exists();

  /// Atomic single-file write inside the loose store (tmp + rename), so a
  /// crash mid-write never leaves a half-written page/asset on disk.
  Future<void> _writeStoreFileAtomic(String path, List<int> data) async {
    final parent = Directory(p.dirname(path));
    if (!await parent.exists()) await parent.create(recursive: true);
    final ts = DateTime.now().microsecondsSinceEpoch;
    final seq = (++_tmpCounter).toRadixString(36);
    final tmp = File('$path.$ts-$seq.tmp');
    try {
      await tmp.writeAsBytes(data, flush: true);
      await tmp.rename(path);
    } catch (e) {
      try { if (await tmp.exists()) await tmp.delete(); } catch (_) {}
      rethrow;
    }
  }

  Future<void> _deleteStoreFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {/* best effort */}
  }

  /// Write ONLY the changed parts of a notebook to the loose store, creating
  /// it if missing. All byte buffers are pre-encoded by the caller (the page
  /// JSON encode already happens on the main isolate behind the notifier's
  /// quiet-pointer gate). Serialised per-notebook via [_saveLocks] so it can't
  /// race [saveNotebookFile] / [explodeZipToLooseStore] on the same notebook.
  Future<void> saveNotebookIncremental(
    String notebookId, {
    Uint8List? metadataJson,
    Uint8List? documentJson,
    Map<String, Uint8List> changedPages = const {},
    Map<String, Uint8List> changedAssets = const {},
    List<String> deletedPages = const [],
    List<String> deletedAssets = const [],
    Uint8List? symbolsJson,
    bool removeSymbols = false,
  }) async {
    final prev = _saveLocks[notebookId];
    final completer = Completer<void>();
    _saveLocks[notebookId] = completer.future;
    try {
      if (prev != null) {
        try { await prev; } catch (_) {}
      }
      final dir = notebookStoreDir(notebookId);
      final pagesDir = p.join(dir, AppConfig.pagesDir);
      final assetsDir = p.join(dir, AppConfig.assetsDir);

      if (metadataJson != null) {
        await _writeStoreFileAtomic(p.join(dir, AppConfig.metadataFile), metadataJson);
      }
      // Pages and assets BEFORE document.json: a crash in between leaves at
      // worst an orphan page file (the heal re-adds it), while the reverse
      // order would leave document.json referencing files that don't exist
      // yet. Deletions stay after the document write for the same reason:
      // the document must stop referencing a file before it disappears.
      for (final e in changedPages.entries) {
        await _writeStoreFileAtomic(p.join(pagesDir, e.key), e.value);
      }
      for (final e in changedAssets.entries) {
        await _writeStoreFileAtomic(p.join(assetsDir, e.key), e.value);
      }
      if (documentJson != null) {
        await _writeStoreFileAtomic(p.join(dir, AppConfig.documentFile), documentJson);
      }
      for (final fn in deletedPages) {
        await _deleteStoreFile(p.join(pagesDir, fn));
      }
      for (final aid in deletedAssets) {
        await _deleteStoreFile(p.join(assetsDir, aid));
      }
      if (removeSymbols) {
        await _deleteStoreFile(p.join(dir, 'symbols.json'));
      } else if (symbolsJson != null) {
        await _writeStoreFileAtomic(p.join(dir, 'symbols.json'), symbolsJson);
      }
    } finally {
      completer.complete();
      if (identical(_saveLocks[notebookId], completer.future)) {
        _saveLocks.remove(notebookId);
      }
    }
  }

  /// Assemble the `.ncnote` ZIP from the loose store on demand. Returns null if
  /// no loose store exists. Assets are STORED (not re-deflated) — they're
  /// already-compressed (PNG/JPEG/PDF) and this is an occasional, off-hot-path
  /// call (sync upload, search, export), so speed beats the ~0-3% size gain.
  Future<Uint8List?> assembleZipFromLooseStore(String notebookId) async {
    final dir = notebookStoreDir(notebookId);
    if (!await Directory(dir).exists()) return null;
    final archive = Archive();

    Future<void> addFile(String archiveName, String absPath,
        {bool compress = true}) async {
      final f = File(absPath);
      if (!await f.exists()) return;
      final bytes = await f.readAsBytes();
      archive.addFile(
        ArchiveFile(archiveName, bytes.length, bytes)..compress = compress,
      );
    }

    await addFile(AppConfig.metadataFile, p.join(dir, AppConfig.metadataFile));
    await addFile(AppConfig.documentFile, p.join(dir, AppConfig.documentFile));

    // Pages + assets: walk recursively and preserve the path relative to the
    // store root (normalised to forward slashes). Asset ids are flat today,
    // but extractAllAssets keys by the full sub-path after `assets/`, so this
    // stays correct even if a nested key ever appears.
    String archiveName(String absPath) =>
        p.split(p.relative(absPath, from: dir)).join('/');
    final pagesDir = Directory(p.join(dir, AppConfig.pagesDir));
    if (await pagesDir.exists()) {
      await for (final e in pagesDir.list(recursive: true)) {
        if (e is File && !e.path.endsWith('.tmp')) {
          await addFile(archiveName(e.path), e.path);
        }
      }
    }
    final assetsDir = Directory(p.join(dir, AppConfig.assetsDir));
    if (await assetsDir.exists()) {
      await for (final e in assetsDir.list(recursive: true)) {
        if (e is File && !e.path.endsWith('.tmp')) {
          await addFile(archiveName(e.path), e.path, compress: false);
        }
      }
    }
    final symbols = File(p.join(dir, 'symbols.json'));
    if (await symbols.exists()) {
      await addFile('symbols.json', symbols.path);
    }

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) return null;
    return Uint8List.fromList(encoded);
  }

  /// Explode a full `.ncnote` ZIP into the loose store (migration + the rare
  /// full-write paths: server download, import, rename/cover/paper rebuild,
  /// duplicate). Writes into a tmp dir then renames into place so a partially
  /// exploded store is never observed as "present".
  Future<void> explodeZipToLooseStore(
      String notebookId, Uint8List zipBytes) async {
    final prev = _saveLocks[notebookId];
    final completer = Completer<void>();
    _saveLocks[notebookId] = completer.future;
    try {
      if (prev != null) {
        try { await prev; } catch (_) {}
      }
      await _explodeZipUnlocked(notebookId, zipBytes);
    } finally {
      completer.complete();
      if (identical(_saveLocks[notebookId], completer.future)) {
        _saveLocks.remove(notebookId);
      }
    }
  }

  /// Explode worker — the CALLER must already hold this notebook's [_saveLocks]
  /// entry (used both by [explodeZipToLooseStore] and inline by
  /// [saveNotebookFile], which holds the lock for its legacy write).
  Future<void> _explodeZipUnlocked(
      String notebookId, Uint8List zipBytes) async {
    final dir = notebookStoreDir(notebookId);
    final ts = DateTime.now().microsecondsSinceEpoch;
    final seq = (++_tmpCounter).toRadixString(36);
    final tmpDir = '$dir.$ts-$seq.tmpdir';
    final archive = ZipDecoder().decodeBytes(zipBytes);
    for (final f in archive.files) {
      if (!f.isFile) continue;
      // Zip-slip guard: skip entries with absolute paths or `..` segments
      // that would escape the tmp dir (malicious/corrupt .ncnote).
      final entryPath = p.normalize(p.join(tmpDir, f.name));
      if (p.isAbsolute(f.name) || !p.isWithin(tmpDir, entryPath)) continue;
      final out = File(entryPath);
      final parent = Directory(p.dirname(out.path));
      if (!await parent.exists()) await parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>, flush: false);
    }
    // Swap into place: remove any existing store, then rename tmp → final.
    final existing = Directory(dir);
    if (await existing.exists()) await existing.delete(recursive: true);
    await Directory(tmpDir).rename(dir);
  }

  /// Best-effort total byte size of the loose store, for the DB `file_size`
  /// column (previously the package length). Sums file lengths; 0 if no store.
  /// Off the drawing hot path (runs in the background save task).
  Future<int> looseStoreSize(String notebookId) async {
    final d = Directory(notebookStoreDir(notebookId));
    if (!await d.exists()) return 0;
    var total = 0;
    try {
      await for (final e in d.list(recursive: true)) {
        if (e is File && !e.path.endsWith('.tmp')) {
          total += await e.length();
        }
      }
    } catch (_) {/* best effort */}
    return total;
  }

  /// Ensure the loose store exists for [notebookId], lazily exploding the
  /// legacy `<id>.ncnote` into it on first access. Returns true if a loose
  /// store is available afterwards. No-op (returns true) if it already exists.
  Future<bool> ensureLooseStore(String notebookId) async {
    if (await hasLooseStore(notebookId)) return true;
    final legacy = File(localPath(notebookId));
    if (!await legacy.exists()) return false;
    try {
      final bytes = await legacy.readAsBytes();
      await explodeZipToLooseStore(notebookId, bytes);
      debugPrint('[FileService] Migrated $notebookId to loose store');
      return true;
    } catch (e) {
      debugPrint('[FileService] Loose-store migration failed for $notebookId: $e');
      return false;
    }
  }

  /// Delete the loose store directory for [notebookId] (best effort).
  Future<void> deleteLooseStore(String notebookId) async {
    try {
      final d = Directory(notebookStoreDir(notebookId));
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {/* best effort */}
  }

  /// Checks whether a notebook is cached locally (loose store OR legacy file).
  Future<bool> hasLocalCopy(String notebookId) async {
    if (await hasLooseStore(notebookId)) return true;
    return File(localPath(notebookId)).exists();
  }

  /// Deletes a notebook's local data — both the loose store and the legacy file.
  Future<void> deleteNotebookFile(String notebookId) async {
    await deleteLooseStore(notebookId);
    final file = File(localPath(notebookId));
    if (await file.exists()) {
      await file.delete();
    }
  }

  // ── Sync Metadata DB ──

  /// Upserts notebook metadata in the local DB.
  Future<void> upsertNotebookMeta({
    required String id,
    required String title,
    required String remotePath,
    String? etag,
    required DateTime localModifiedAt,
    DateTime? remoteModifiedAt,
    String syncStatus = 'synced',
    int? fileSize,
    int? coverColor,
    String? paperType,
    int pageCount = 0,
    DateTime? createdAt,
  }) async {
    await _db.insert(
      'notebooks',
      {
        'id': id,
        'title': title,
        'remote_path': remotePath,
        'etag': etag,
        'local_modified_at': localModifiedAt.toIso8601String(),
        'remote_modified_at': remoteModifiedAt?.toIso8601String(),
        'sync_status': syncStatus,
        'file_size': fileSize,
        'cover_color': coverColor,
        'paper_type': paperType,
        'page_count': pageCount,
        'created_at': (createdAt ?? localModifiedAt).toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns all locally-tracked notebook metadata rows.
  Future<List<Map<String, dynamic>>> getAllNotebookMeta() async {
    return _db.query('notebooks', orderBy: 'local_modified_at DESC');
  }

  /// Returns metadata for a single notebook, or null.
  Future<Map<String, dynamic>?> getNotebookMeta(String id) async {
    final rows = await _db.query('notebooks', where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Marks a notebook as dirty (needs sync).
  Future<void> markNotebookDirty(String notebookId) async {
    await _db.update(
      'notebooks',
      {'sync_status': 'modified', 'local_modified_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [notebookId],
    );
  }

  /// Marks a notebook as synced with a new etag.
  Future<void> markNotebookSynced(String notebookId, String? etag) async {
    await _db.update(
      'notebooks',
      {
        'sync_status': 'synced',
        'etag': etag,
        'remote_modified_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [notebookId],
    );
  }

  /// Invalidates the cached ETag on every notebook so the next sync cycle
  /// must re-fetch metadata + pages from the server. Used by the
  /// "Pulisci cache sync" recovery path when the local state is stuck
  /// (e.g. a partial pull left state.pages with fewer entries than
  /// document, and the fast-path HEAD keeps saying "nothing changed").
  /// Doesn't touch the .ncnote files themselves — only the sync bookkeeping.
  Future<int> invalidateAllEtags() async {
    return _db.update(
      'notebooks',
      {'etag': null},
      where: '1 = 1',
    );
  }

  /// Returns all notebook IDs that need syncing.
  Future<List<Map<String, dynamic>>> getDirtyNotebooks() async {
    return _db.query(
      'notebooks',
      where: 'sync_status != ?',
      whereArgs: ['synced'],
    );
  }

  /// Tracks a dirty page for a notebook.
  Future<void> addDirtyPage(String notebookId, String pageId) async {
    await _db.insert(
      'dirty_pages',
      {
        'notebook_id': notebookId,
        'page_id': pageId,
        'modified_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Clears all dirty pages for a notebook (after successful sync).
  Future<void> clearDirtyPages(String notebookId) async {
    await _db.delete(
      'dirty_pages',
      where: 'notebook_id = ?',
      whereArgs: [notebookId],
    );
  }

  /// Deletes a notebook from the DB and local file.
  Future<void> deleteNotebook(String notebookId) async {
    await _db.delete('notebooks', where: 'id = ?', whereArgs: [notebookId]);
    await _db.delete('dirty_pages', where: 'notebook_id = ?', whereArgs: [notebookId]);
    await deleteNotebookFile(notebookId);
    // Also clean up any rolling snapshots for this notebook.
    try {
      final dir = Directory(p.join(_snapshotsDir, notebookId));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  // ── Trash (soft-delete with restore) ──

  /// Moves a notebook into the trash, preserving its metadata row for restore.
  ///
  /// Returns the opaque trash id that can be passed to [restoreFromTrash].
  /// Does NOT delete remote files — caller is responsible for deciding what
  /// to sync.
  Future<String?> moveNotebookToTrash(String notebookId) async {
    // Serialised via _saveLocks like every other writer: without the lock an
    // in-flight autosave could recreate the loose store between our snapshot
    // and deleteLooseStore, leaving an orphaned partial store that shadows
    // the .ncnote at the next restore (readNotebookFile prefers the store).
    final prev = _saveLocks[notebookId];
    final completer = Completer<void>();
    _saveLocks[notebookId] = completer.future;
    try {
      if (prev != null) {
        try { await prev; } catch (_) {}
      }
      // Capture the CURRENT content as a single .ncnote. readNotebookFile
      // resolves the live loose store first (the source of truth), falling back
      // to the legacy file — so trashing a notebook edited since migration
      // preserves the latest content, not a stale pre-migration ZIP.
      final bytes = await readNotebookFile(notebookId);
      if (bytes == null) {
        // Nothing to preserve; still purge any stray store + DB below.
        await deleteLooseStore(notebookId);
        await _db.delete('notebooks', where: 'id = ?', whereArgs: [notebookId]);
        await _db.delete('dirty_pages', where: 'notebook_id = ?', whereArgs: [notebookId]);
        return null;
      }

      final meta = await getNotebookMeta(notebookId);
      final stamp = DateTime.now().millisecondsSinceEpoch.toString();
      final trashId = '${notebookId}_$stamp';
      final destFile = File(p.join(_trashDir, '$trashId${AppConfig.fileExtension}'));
      final metaFile = File(p.join(_trashDir, '$trashId.meta.json'));

      // Atomic writes, meta BEFORE data: a crash between the two leaves a
      // meta without its .ncnote, which listTrash skips gracefully (and the
      // live notebook hasn't been deleted yet). The old order left an
      // invisible orphan .ncnote the UI could never restore or clean up.
      await _writeStoreFileAtomic(
          metaFile.path,
          utf8.encode(jsonEncode({
            'originalId': notebookId,
            'deletedAt': DateTime.now().toIso8601String(),
            'meta': meta,
          })));
      await _writeStoreFileAtomic(destFile.path, bytes);
      // Remove both representations of the live notebook.
      await deleteLooseStore(notebookId);
      final legacy = File(localPath(notebookId));
      if (await legacy.exists()) await legacy.delete();

      // Purge DB so library stops showing it.
      await _db.delete('notebooks', where: 'id = ?', whereArgs: [notebookId]);
      await _db.delete('dirty_pages', where: 'notebook_id = ?', whereArgs: [notebookId]);
      return trashId;
    } finally {
      completer.complete();
      if (identical(_saveLocks[notebookId], completer.future)) {
        _saveLocks.remove(notebookId);
      }
    }
  }

  /// Lists items currently in the trash, newest first.
  Future<List<TrashEntry>> listTrash() async {
    final dir = Directory(_trashDir);
    if (!await dir.exists()) return const [];
    final out = <TrashEntry>[];
    await for (final entry in dir.list()) {
      if (entry is! File || !entry.path.endsWith('.meta.json')) continue;
      try {
        final json = jsonDecode(await entry.readAsString()) as Map<String, dynamic>;
        final trashId = p.basenameWithoutExtension(entry.path).replaceAll('.meta', '');
        final data = File(p.join(_trashDir, '$trashId${AppConfig.fileExtension}'));
        if (!await data.exists()) continue;
        out.add(TrashEntry(
          trashId: trashId,
          originalId: json['originalId'] as String? ?? trashId,
          deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? '') ?? DateTime.now(),
          meta: (json['meta'] as Map?)?.cast<String, dynamic>(),
        ));
      } catch (_) {}
    }
    out.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return out;
  }

  /// Restores a trashed notebook. Returns the restored metadata row, or null
  /// if the trash entry is missing.
  Future<Map<String, dynamic>?> restoreFromTrash(String trashId) async {
    final dataFile = File(p.join(_trashDir, '$trashId${AppConfig.fileExtension}'));
    final metaFile = File(p.join(_trashDir, '$trashId.meta.json'));
    if (!await dataFile.exists() || !await metaFile.exists()) return null;

    final json = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
    final originalId = json['originalId'] as String;
    final meta = (json['meta'] as Map?)?.cast<String, dynamic>();

    final bytes = await dataFile.readAsBytes();
    // Under the per-notebook lock: purge any leftover loose store BEFORE
    // writing the legacy file. readNotebookFile always prefers the store, so
    // an orphaned/partial store (e.g. from a pre-lock trash race) would
    // shadow the restored content. Store-delete-first is safe: the trash
    // files are only removed at the end, so a crash in between loses nothing.
    final prev = _saveLocks[originalId];
    final completer = Completer<void>();
    _saveLocks[originalId] = completer.future;
    try {
      if (prev != null) {
        try { await prev; } catch (_) {}
      }
      await deleteLooseStore(originalId);
      // Restore the .ncnote file (atomically — a crash mid-write must not
      // leave a truncated live file that bricks the next open).
      await _writeNotebookAtomic(originalId, bytes);
    } finally {
      completer.complete();
      if (identical(_saveLocks[originalId], completer.future)) {
        _saveLocks.remove(originalId);
      }
    }

    // Restore DB row with a `modified` sync status so it re-syncs to remote.
    if (meta != null) {
      await upsertNotebookMeta(
        id: meta['id'] as String,
        title: meta['title'] as String? ?? 'Restored',
        remotePath: meta['remote_path'] as String? ?? '',
        etag: meta['etag'] as String?,
        localModifiedAt: DateTime.tryParse(meta['local_modified_at'] as String? ?? '') ?? DateTime.now(),
        remoteModifiedAt: meta['remote_modified_at'] != null
            ? DateTime.tryParse(meta['remote_modified_at'] as String)
            : null,
        syncStatus: 'modified', // needs re-upload; remote copy was deleted
        fileSize: meta['file_size'] as int?,
        coverColor: meta['cover_color'] as int?,
        paperType: meta['paper_type'] as String?,
        pageCount: meta['page_count'] as int? ?? 0,
        createdAt: DateTime.tryParse(meta['created_at'] as String? ?? '') ?? DateTime.now(),
      );
    }

    await dataFile.delete();
    await metaFile.delete();
    return meta;
  }

  /// Permanently deletes a single trash entry.
  Future<void> purgeTrashEntry(String trashId) async {
    final dataFile = File(p.join(_trashDir, '$trashId${AppConfig.fileExtension}'));
    final metaFile = File(p.join(_trashDir, '$trashId.meta.json'));
    if (await dataFile.exists()) await dataFile.delete();
    if (await metaFile.exists()) await metaFile.delete();
  }

  /// Permanently deletes all trash entries.
  Future<void> emptyTrash() async {
    final dir = Directory(_trashDir);
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      try { await entry.delete(recursive: true); } catch (_) {}
    }
  }

  /// Closes the database. Call on app shutdown.
  Future<void> dispose() async {
    await _db.close();
  }
}

/// Represents one item currently in the trash.
class TrashEntry {
  final String trashId;
  final String originalId;
  final DateTime deletedAt;
  final Map<String, dynamic>? meta;

  const TrashEntry({
    required this.trashId,
    required this.originalId,
    required this.deletedAt,
    required this.meta,
  });

  String get title => meta?['title'] as String? ?? 'Senza titolo';
  int get coverColor => meta?['cover_color'] as int? ?? 0xFF1565C0;
}
