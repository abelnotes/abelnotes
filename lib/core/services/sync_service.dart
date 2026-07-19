import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart'
    show compactPageJson, decodePageData;
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/webdav_service.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Engine di sincronizzazione offline-first.
///
/// Strategia:
/// 1. Ogni modifica va prima in locale (immediata)
/// 2. Le pagine modificate vengono marcate "dirty"
/// 3. Upload solo delle pagine dirty (delta sync)
/// 4. Conflict detection via ETag comparison
class SyncService {
  final WebDavService? _webdavOrNull;
  final Set<String> _explodedDirsReady = {}; // notebook IDs with confirmed folders

  SyncService(this._webdavOrNull, [FileService? fileService]);

  /// True when no server is connected (local-only mode): every pure ZIP /
  /// loose-store helper still works, only genuine network calls are blocked.
  bool get isOffline => _webdavOrNull == null;

  /// Network client. Throws a clear error in local-only mode. Pure helpers
  /// (createNcnotePackage, extractNotebookContents, loadLooseStoreFromDisk,
  /// parseNcnoteMetadata, buildPackageBytes) never touch this, so they run
  /// offline; only real network operations reach this getter.
  WebDavService get _webdav =>
      _webdavOrNull ??
      (throw StateError(
          'Operazione di rete richiesta senza server connesso '
          '(modalità solo-locale).'));

  // ── Integrity Protection ──

  /// Validates that a byte buffer is a well-formed ZIP with the required
  /// ncnote entries (metadata.json + document.json).
  /// Throws [CorruptedArchiveException] on failure.
  static void validateNcnoteArchive(Uint8List data, {String context = ''}) {
    if (data.length < 22) {
      throw CorruptedArchiveException(
        'Archive too small (${data.length} bytes)${context.isNotEmpty ? ' [$context]' : ''}',
      );
    }
    // Quick check: ZIP magic number
    if (data[0] != 0x50 || data[1] != 0x4B) {
      throw CorruptedArchiveException(
        'Not a ZIP file (bad magic)${context.isNotEmpty ? ' [$context]' : ''}',
      );
    }
    // Full parse to find End of Central Directory
    try {
      final archive = ZipDecoder().decodeBytes(data);
      final hasMetadata = archive.findFile(AppConfig.metadataFile) != null;
      final hasDocument = archive.findFile(AppConfig.documentFile) != null;
      if (!hasMetadata || !hasDocument) {
        throw CorruptedArchiveException(
          'Missing required files (metadata=$hasMetadata, document=$hasDocument)'
          '${context.isNotEmpty ? ' [$context]' : ''}',
        );
      }
    } on CorruptedArchiveException {
      rethrow;
    } catch (e) {
      throw CorruptedArchiveException(
        'ZIP parse failed: $e${context.isNotEmpty ? ' [$context]' : ''}',
      );
    }
  }

  /// True for asset types that are already internally compressed (PNG,
  /// JPEG, PDF, ...). Deflating them again inside the .ncnote ZIP is the
  /// dominant CPU cost of every local autosave on image-heavy notebooks
  /// and yields a ~0-3% size gain — such entries are STOREd instead.
  /// Page/metadata JSON keeps normal deflate (it compresses 5-10×).
  static bool isPrecompressedAsset(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return false;
    switch (name.substring(dot + 1).toLowerCase()) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'gif':
      case 'heic':
      case 'heif':
      case 'avif':
      case 'pdf':
      case 'zip':
        return true;
    }
    return false;
  }

  /// Crea un pacchetto .ncnote da metadata, document e pagine.
  ///
  /// [preEncodedPages] è una cache opzionale di `fileName -> jsonBytes`: se la
  /// pagina è presente qui, i suoi byte verranno riusati senza rifare
  /// `jsonEncode`, che per pagine con molti stroke è l'overhead dominante.
  /// Le pagine non presenti nella cache vengono codificate normalmente.
  Uint8List createNcnotePackage({
    required NotebookMetadata metadata,
    required DocumentStructure document,
    required Map<String, PageData> pages,
    Map<String, Uint8List>? assets,
    List<Map<String, dynamic>>? symbolLibraries,
    Map<String, Uint8List>? preEncodedPages,
  }) {
    final archive = Archive();

    // metadata.json
    final metadataBytes = utf8.encode(jsonEncode(metadata.toJson()));
    archive.addFile(ArchiveFile(
      AppConfig.metadataFile,
      metadataBytes.length,
      metadataBytes,
    ));

    // document.json
    final documentBytes = utf8.encode(jsonEncode(document.toJson()));
    archive.addFile(ArchiveFile(
      AppConfig.documentFile,
      documentBytes.length,
      documentBytes,
    ));

    // pages/
    for (final entry in pages.entries) {
      final cached = preEncodedPages?[entry.key];
      final pageBytes = cached ?? utf8.encode(jsonEncode(entry.value.toJson()));
      archive.addFile(ArchiveFile(
        '${AppConfig.pagesDir}/${entry.key}',
        pageBytes.length,
        pageBytes,
      ));
    }

    // assets/
    if (assets != null) {
      for (final entry in assets.entries) {
        archive.addFile(ArchiveFile(
          '${AppConfig.assetsDir}/${entry.key}',
          entry.value.length,
          entry.value,
        )..compress = !isPrecompressedAsset(entry.key));
      }
    }

    // symbols.json
    if (symbolLibraries != null && symbolLibraries.isNotEmpty) {
      final symbolsBytes = utf8.encode(jsonEncode(symbolLibraries));
      archive.addFile(ArchiveFile(
        'symbols.json',
        symbolsBytes.length,
        symbolsBytes,
      ));
    }

    return Uint8List.fromList(ZipEncoder().encode(archive)!);

  }

  /// Parsa un archivio .ncnote scaricato.
  ({NotebookMetadata metadata, DocumentStructure document})
      _parseNcnoteArchive(Uint8List data) {
    final archive = ZipDecoder().decodeBytes(data);

    // Estrai metadata.json
    final metadataFile = archive.findFile(AppConfig.metadataFile);
    if (metadataFile == null) {
      throw Exception('Invalid .ncnote: missing ${AppConfig.metadataFile}');
    }
    final metadataJson = jsonDecode(
      utf8.decode(metadataFile.content as List<int>),
    );
    final metadata =
        NotebookMetadata.fromJson(metadataJson as Map<String, dynamic>);

    // Estrai document.json
    final documentFile = archive.findFile(AppConfig.documentFile);
    if (documentFile == null) {
      throw Exception('Invalid .ncnote: missing ${AppConfig.documentFile}');
    }
    final documentJson = jsonDecode(
      utf8.decode(documentFile.content as List<int>),
    );
    final document =
        DocumentStructure.fromJson(documentJson as Map<String, dynamic>);

    return (metadata: metadata, document: document);
  }

  /// Public wrapper for parsing .ncnote metadata from raw bytes.
  /// Used by the library to read from local cache.
  ({NotebookMetadata metadata, DocumentStructure document})
      parseNcnoteMetadata(Uint8List data) => _parseNcnoteArchive(data);

  /// Lightweight metadata-only extraction: validates ZIP and returns metadata
  /// in a single decode pass (no double decode).
  NotebookMetadata parseNcnoteMetadataOnly(Uint8List data) {
    final archive = ZipDecoder().decodeBytes(data);
    final metadataFile = archive.findFile(AppConfig.metadataFile);
    if (metadataFile == null) {
      throw CorruptedArchiveException('Missing ${AppConfig.metadataFile}');
    }
    final json = jsonDecode(utf8.decode(metadataFile.content as List<int>));
    return NotebookMetadata.fromJson(json as Map<String, dynamic>);
  }

  /// Parse .ncnote metadata off the main thread using compute().
  static Future<NotebookMetadata> parseNcnoteMetadataIsolate(Uint8List data) {
    return compute(_parseMetadataInIsolate, data);
  }

  static NotebookMetadata _parseMetadataInIsolate(Uint8List data) {
    final archive = ZipDecoder().decodeBytes(data);
    final metadataFile = archive.findFile(AppConfig.metadataFile);
    if (metadataFile == null) {
      throw Exception('Missing ${AppConfig.metadataFile}');
    }
    final json = jsonDecode(utf8.decode(metadataFile.content as List<int>));
    return NotebookMetadata.fromJson(json as Map<String, dynamic>);
  }

  /// Lista i notebook .ncnote presenti sul server nella cartella base.
  /// Throws on network/server errors so the UI can show them.
  Future<List<WebDavItem>> listRemoteNotebooks() async {
    await _webdav.ensureBaseDirectory();
    final items = await _webdav.listDirectory(_webdav.basePath);
    return items
        .where((item) =>
            !item.isDirectory &&
            item.name.endsWith(AppConfig.fileExtension))
        .toList();
  }

  /// Upload di un notebook completo sul server.
  /// Extract symbol libraries from an .ncnote archive.
  List<Map<String, dynamic>> extractSymbolLibraries(Uint8List data) {
    final archive = ZipDecoder().decodeBytes(data);
    final symbolsFile = archive.findFile('symbols.json');
    if (symbolsFile == null) return [];
    try {
      final json = jsonDecode(utf8.decode(symbolsFile.content as List<int>));
      return (json as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<String?> uploadNotebook({
    required String remotePath,
    required NotebookMetadata metadata,
    required DocumentStructure document,
    required Map<String, PageData> pages,
    Map<String, Uint8List>? assets,
    List<Map<String, dynamic>>? symbolLibraries,
  }) async {
    final package = createNcnotePackage(
      metadata: metadata,
      document: document,
      pages: pages,
      assets: assets,
      symbolLibraries: symbolLibraries,
    );

    // ── Pre-upload validation ──
    validateNcnoteArchive(package, context: 'pre-upload ${metadata.title}');
    debugPrint('[Sync] Validated package for "${metadata.title}": '
        '${package.length} bytes, uploading...');

    final etag = await _webdav.uploadFile(remotePath, package);

    // ── Post-upload size verification ──
    try {
      final remoteSize = await _webdav.getContentLength(remotePath);
      if (remoteSize != null && remoteSize != package.length) {
        debugPrint('[Sync] WARNING: Upload size mismatch for '
            '"${metadata.title}": local=${package.length}, '
            'remote=$remoteSize — deleting corrupted upload!');
        // Remove the corrupted file so other devices don't download it.
        try {
          await _webdav.delete(remotePath);
        } catch (_) {}
        throw CorruptedArchiveException(
          'Upload size mismatch: expected ${package.length} bytes, '
          'server has $remoteSize bytes. Upload corrupted and removed.',
        );
      }
      debugPrint('[Sync] Upload verified for "${metadata.title}": '
          '$remoteSize bytes on server.');
    } catch (e) {
      if (e is CorruptedArchiveException) rethrow;
      // Non-critical: size check failed but upload itself succeeded
      debugPrint('[Sync] Could not verify upload size: $e');
    }

    return etag;
  }

  /// Upload a pre-built, pre-validated .ncnote package directly.
  /// Skips redundant ZIP creation and validation — the caller already did it
  /// (e.g. via a background isolate).
  Future<String?> uploadRawPackage(String remotePath, Uint8List package) async {
    debugPrint('[Sync] Uploading pre-built package: '
        '${package.length} bytes → $remotePath');

    final etag = await _webdav.uploadFile(remotePath, package);

    // Post-upload size verification
    try {
      final remoteSize = await _webdav.getContentLength(remotePath);
      if (remoteSize != null && remoteSize != package.length) {
        debugPrint('[Sync] WARNING: Upload size mismatch: '
            'local=${package.length}, remote=$remoteSize — deleting corrupted upload!');
        try {
          await _webdav.delete(remotePath);
        } catch (_) {}
        throw CorruptedArchiveException(
          'Upload size mismatch: expected ${package.length} bytes, '
          'server has $remoteSize bytes. Upload corrupted and removed.',
        );
      }
      debugPrint('[Sync] Upload verified: $remoteSize bytes on server.');
    } catch (e) {
      if (e is CorruptedArchiveException) rethrow;
      debugPrint('[Sync] Could not verify upload size: $e');
    }

    return etag;
  }

  // ══════════════════════════════════════════════════════════════
  //  DELTA SYNC — exploded per-page storage on server
  // ══════════════════════════════════════════════════════════════

  /// Remote folder for a notebook's exploded files.
  /// Layout:  /HandWriter/.sync/<id>/metadata.json
  ///          /HandWriter/.sync/<id>/document.json
  ///          /HandWriter/.sync/<id>/pages/page_001.json
  ///          /HandWriter/.sync/<id>/assets/images/foo.png
  ///          /HandWriter/.sync/<id>/symbols.json
  String _deltaDir(String notebookId) =>
      '${_webdav.basePath}${AppConfig.deltaSyncDir}$notebookId/';

  /// Creates the exploded folder structure on the server (idempotent).
  /// Throws if any directory creation fails (except 405 = already exists).
  Future<void> _ensureDeltaDir(String notebookId) async {
    if (_explodedDirsReady.contains(notebookId)) return;
    final dir = _deltaDir(notebookId);
    debugPrint('[Sync] Ensuring delta dir: $dir');

    // MKCOL tolerates 405 (already exists) inside createDirectory().
    // Only catch WebDavException with 405 — propagate real errors.
    try {
      await _webdav.createDirectory(
          '${_webdav.basePath}${AppConfig.deltaSyncDir}');
    } on WebDavException catch (e) {
      if (e.statusCode != 405) rethrow;
    }
    // These are critical — propagate real errors.
    await _webdav.createDirectory(dir);
    await _webdav.createDirectory('${dir}pages/');
    await _webdav.createDirectory('${dir}assets/');

    _explodedDirsReady.add(notebookId);
  }

  /// Upload the full .ncnote ZIP to the server at the given remotePath.
  /// This keeps the ZIP in sync with the delta folder so other devices
  /// that download the .ncnote can see the latest changes.
  Future<String?> uploadNcnoteZip(String remotePath, Uint8List package) async {
    return _webdav.uploadFile(remotePath, package);
  }

  /// Delta upload: sends only the changed pages + metadata + document.
  /// Returns metadata.json ETag + the per-page ETags we actually wrote.
  ///
  /// Upload order ensures consistency:
  ///  1. Assets + pages in parallel (data files)
  ///  2. metadata.json LAST (acts as "commit" — other devices detect
  ///     changes via the metadata ETag, so updating it last guarantees
  ///     that all referenced data is already on the server).
  ///
  /// document.json is uploaded in parallel with Phase 1 because the
  /// "published state" is gated on metadata.json only.
  ///
  /// If any data upload fails, metadata is NOT updated → other devices
  /// see the old consistent state rather than a partial one.
  ///
  /// The returned `pageEtags` map contains ETags from THIS upload only.
  /// Callers should merge these into their cached ETag table rather than
  /// replace it — replacing would swallow concurrent uploads from other
  /// devices (the next pull would treat those pages as unchanged and
  /// silently miss remote edits).
  Future<({
    String? metaEtag,
    Map<String, String> pageEtags,
    List<String> failedPageDeletes,
    List<String> failedAssetDeletes,
  })> syncDelta({
    required String notebookId,
    required NotebookMetadata metadata,
    required DocumentStructure document,
    required Map<String, PageData> dirtyPages,
    Map<String, Uint8List>? preEncodedPages,
    Map<String, Uint8List>? dirtyAssets,
    List<Map<String, dynamic>>? symbolLibraries,
    List<String>? deletedPageFileNames,
    List<String>? deletedAssetFileNames,
  }) async {
    try {
      return await _syncDeltaInner(
        notebookId: notebookId,
        metadata: metadata,
        document: document,
        dirtyPages: dirtyPages,
        preEncodedPages: preEncodedPages,
        dirtyAssets: dirtyAssets,
        symbolLibraries: symbolLibraries,
        deletedPageFileNames: deletedPageFileNames,
        deletedAssetFileNames: deletedAssetFileNames,
      );
    } catch (e) {
      // A 409/404 mid-upload usually means the delta folder vanished under
      // us (deleted from another device). Drop the "confirmed" cache entry
      // so the next save re-runs MKCOL instead of failing with 409 forever
      // (until app restart, since _explodedDirsReady was never invalidated).
      final cause = e is MetadataCommitFailedException ? e.cause : e;
      if (cause is WebDavException &&
          (cause.statusCode == 409 || cause.statusCode == 404)) {
        _explodedDirsReady.remove(notebookId);
      }
      rethrow;
    }
  }

  Future<({
    String? metaEtag,
    Map<String, String> pageEtags,
    List<String> failedPageDeletes,
    List<String> failedAssetDeletes,
  })> _syncDeltaInner({
    required String notebookId,
    required NotebookMetadata metadata,
    required DocumentStructure document,
    required Map<String, PageData> dirtyPages,
    Map<String, Uint8List>? preEncodedPages,
    Map<String, Uint8List>? dirtyAssets,
    List<Map<String, dynamic>>? symbolLibraries,
    List<String>? deletedPageFileNames,
    List<String>? deletedAssetFileNames,
  }) async {
    await _ensureDeltaDir(notebookId);
    final dir = _deltaDir(notebookId);

    // ── Phase 0: Delete removed pages from server (fire in parallel) ──
    // Track which deletes actually failed (vs 404 = already-deleted) so
    // the caller can persist them and retry next save. Without this the
    // request was silently lost on flaky networks and the orphan stayed
    // on the server forever.
    final deleteFutures = <Future<void>>[];
    final failedPageDeletes = <String>[];
    final failedAssetDeletes = <String>[];
    if (deletedPageFileNames != null && deletedPageFileNames.isNotEmpty) {
      for (final fileName in deletedPageFileNames) {
        deleteFutures.add(
          _webdav.delete('${dir}pages/$fileName').catchError((Object e) {
            if (e is WebDavException && e.statusCode == 404) return;
            failedPageDeletes.add(fileName);
            debugPrint('[Sync] Delete of pages/$fileName failed: $e');
          }),
        );
      }
    }
    if (deletedAssetFileNames != null && deletedAssetFileNames.isNotEmpty) {
      for (final assetName in deletedAssetFileNames) {
        deleteFutures.add(
          _webdav.delete('${dir}assets/$assetName').catchError((Object e) {
            if (e is WebDavException && e.statusCode == 404) return;
            failedAssetDeletes.add(assetName);
            debugPrint('[Sync] Delete of assets/$assetName failed: $e');
          }),
        );
      }
    }

    // ── Phase 1: Upload raw data (pages + assets + symbols) in parallel ──
    //
    // Previously document.json was uploaded alongside pages in this phase.
    // That was a silent data-loss bug on flaky networks: if one page upload
    // failed, Future.wait threw and metadata.json stayed old — but
    // document.json had ALREADY uploaded successfully. The server was left
    // in a state where document.json referenced the new pages but some of
    // those page files were still the old version. Remote clients pulled
    // metadata's old ETag, skipped the sync, and silently dropped the
    // strokes that lived on the failed pages.
    //
    // Fix: ordered commit — pages/assets first, document.json only if they
    // all succeeded, then metadata.json as the final commit marker.
    const dt = AppConfig.webdavDeltaTimeoutSeconds;
    final pageUploads = <String, Future<String?>>{};
    final dataUploads = <Future<String?>>[];

    for (final e in dirtyPages.entries) {
      // compactPageJson() rounds doubles to 3 decimals — cuts the per-
      // page wire payload by ~60% with zero deserializer changes (it
      // already accepts any numeric precision via `as num`). On a
      // Tailscale link this is the biggest single win for sync speed.
      // preEncodedPages (from the save path's per-identity cache) skips
      // re-running that encode on the UI isolate — the save already
      // produced the exact same bytes for the local ZIP build.
      final bytes = preEncodedPages?[e.key] ??
          Uint8List.fromList(utf8.encode(compactPageJson(e.value)));
      pageUploads[e.key] = _webdav.uploadFile(
          '${dir}pages/${e.key}', bytes, timeoutSeconds: dt);
    }

    // Track expected sizes of asset uploads for the batched post-PUT
    // verification step below. Without batching, every asset PUT did its
    // own PROPFIND verify (50 PDF-import assets × 80ms RTT on Tailscale
    // = 4 seconds of serialised verification at the end of the save).
    // skipVerify=true here suppresses the per-PUT PROPFIND; we replace
    // it with one directory-level PROPFIND after Future.wait — same
    // truncation safety in 1 RTT instead of N.
    final expectedAssetSizes = <String, int>{};
    if (dirtyAssets != null && dirtyAssets.isNotEmpty) {
      for (final e in dirtyAssets.entries) {
        expectedAssetSizes[e.key] = e.value.length;
        dataUploads.add(_webdav.uploadFile(
            '${dir}assets/${e.key}', e.value,
            timeoutSeconds: dt, skipVerify: true));
      }
    }

    if (symbolLibraries != null && symbolLibraries.isNotEmpty) {
      final symBytes = Uint8List.fromList(
        utf8.encode(jsonEncode(symbolLibraries)),
      );
      dataUploads.add(_webdav.uploadFile('${dir}symbols.json', symBytes,
          timeoutSeconds: dt));
    }

    // Wait for every data file. If any throws, we exit here and document.json
    // / metadata.json are NOT written — the server stays in its previous
    // consistent state.
    await Future.wait([
      ...pageUploads.values,
      ...dataUploads,
      ...deleteFutures,
    ]);

    // ── Phase 1.4: Batched asset-size verification ──
    //
    // Replaces N per-PUT PROPFINDs with one directory listing. On a
    // 50-asset save (PDF re-import) this turns ~4s of serialised RTTs
    // into ~80ms. For each verified-truncated asset we re-upload with
    // criticalVerify (single-PROPFIND fallback) so the safety net is
    // identical to the prior per-asset path. Listing failure (network
    // blip on the PROPFIND) falls back to "trusting the PUT" — same
    // semantics as the per-PUT verify did when its own PROPFIND timed
    // out.
    //
    // Failure handling is split deliberately: a listDirectory hiccup is
    // transient and we fall through (PUTs probably stuck — best effort).
    // But a WebDavSizeMismatchException out of the retry path means we
    // ALREADY confirmed truncation and exhausted retries — that asset's
    // bytes on the server are corrupt and we must NOT proceed to
    // document.json / metadata.json (committing those would advertise
    // broken assets to every other device, exactly the May 2026
    // incident). Rethrow so syncDelta aborts before the commit markers.
    if (expectedAssetSizes.isNotEmpty) {
      Map<String, int>? remoteSizes;
      try {
        final items = await _webdav
            .listDirectory('${dir}assets/')
            .timeout(const Duration(seconds: 30));
        remoteSizes = <String, int>{};
        for (final it in items) {
          if (it.contentLength != null) {
            remoteSizes[it.name] = it.contentLength!;
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('[Sync] Batched asset listDirectory failed '
            '(${expectedAssetSizes.length} assets) — falling back to '
            'per-asset size checks: $e');
      }

      final retriesNeeded = <String>[];
      if (remoteSizes != null) {
        for (final entry in expectedAssetSizes.entries) {
          final remote = remoteSizes[entry.key];
          if (remote == null) {
            // PROPFIND didn't list it (some Nextcloud installations
            // miss freshly-PUT files in the listing for a moment).
            // Treat as "couldn't verify" → retry with single check.
            retriesNeeded.add(entry.key);
          } else if (remote != entry.value) {
            // ignore: avoid_print
            print('[Sync] Asset ${entry.key} TRUNCATED on server: '
                'sent ${entry.value}B, server has ${remote}B — retry');
            retriesNeeded.add(entry.key);
          }
        }
      } else {
        // A single listDirectory blip must NOT skip verification for the
        // WHOLE batch — that was how a truncated asset could slip through to
        // the commit markers (the May 2026 incident). Verify each asset with
        // an individual PROPFIND instead; on a per-asset error, conservatively
        // schedule a criticalVerify re-upload rather than trusting the PUT.
        final sizes = await Future.wait(
          expectedAssetSizes.keys.map((k) async {
            try {
              final sz = await _webdav
                  .getContentLength('${dir}assets/$k')
                  .timeout(const Duration(seconds: 15));
              return MapEntry(k, sz);
            } catch (_) {
              return MapEntry(k, null);
            }
          }),
        );
        for (final e in sizes) {
          final expected = expectedAssetSizes[e.key];
          if (e.value == null || e.value != expected) {
            if (e.value != null) {
              // ignore: avoid_print
              print('[Sync] Asset ${e.key} size mismatch on server: '
                  'sent ${expected}B, server has ${e.value}B — retry');
            }
            retriesNeeded.add(e.key);
          }
        }
      }

      if (retriesNeeded.isNotEmpty) {
        // Re-upload only the broken ones with criticalVerify (the
        // strict per-file PROPFIND-with-retries path). A
        // WebDavSizeMismatchException out of here means retries
        // exhausted — propagate, do NOT continue to commit markers.
        await Future.wait(retriesNeeded.map((k) {
          final bytes = dirtyAssets![k]!;
          return _webdav.uploadFile('${dir}assets/$k', bytes,
              timeoutSeconds: dt, criticalVerify: true);
        }));
      }
    }

    // ── Phase 1.5: document.json (only after every page/asset succeeded) ──
    final docBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(document.toJson())),
    );
    await _webdav.uploadFile('${dir}document.json', docBytes,
        timeoutSeconds: dt, criticalVerify: true);

    // ── Phase 2: Upload metadata.json LAST (commit marker) ──
    // CRITICAL: pages + document are ALREADY committed at this point.
    // If metadata.json fails here, the server is half-committed: other
    // devices fast-path-skip on the unchanged meta-ETag and never see
    // the new pages. We surface the failure with the metadata bytes so
    // the caller can persist them and replay metadata-only until it
    // lands. Prior behaviour swallowed the throw at the outer catch
    // and only retried on the next user save — leaving cross-device
    // sync indefinitely stuck.
    final metaBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(metadata.toJson())),
    );
    String? metaEtag;
    try {
      metaEtag = await _webdav.uploadFile('${dir}metadata.json', metaBytes,
          timeoutSeconds: dt, criticalVerify: true);
    } catch (e) {
      throw MetadataCommitFailedException(
        notebookId: notebookId,
        metadataBytes: metaBytes,
        cause: e,
      );
    }

    // Harvest per-page ETags from successful PUT responses.
    final pageEtags = <String, String>{};
    for (final entry in pageUploads.entries) {
      try {
        final etag = await entry.value;
        if (etag != null && etag.isNotEmpty) {
          pageEtags[entry.key] = etag.replaceAll('"', '');
        }
      } catch (_) {
        // Already surfaced via Future.wait above; ignore here.
      }
    }

    debugPrint('[Sync] Delta sync: ${dirtyPages.length} pages, '
        '${dirtyAssets?.length ?? 0} assets → $dir');

    return (
      metaEtag: metaEtag,
      pageEtags: pageEtags,
      failedPageDeletes: failedPageDeletes,
      failedAssetDeletes: failedAssetDeletes,
    );
  }

  /// Replay-only metadata.json upload, used to recover from a
  /// half-committed delta where pages + document.json landed on the
  /// server but [syncDelta]'s final metadata PUT failed
  /// ([MetadataCommitFailedException]). Returns the new ETag on
  /// success, throws on failure (caller keeps retrying). Idempotent:
  /// re-uploading identical bytes is harmless.
  Future<String?> replayMetadataCommit({
    required String notebookId,
    required Uint8List metadataBytes,
  }) async {
    final dir = _deltaDir(notebookId);
    return await _webdav.uploadFile(
      '${dir}metadata.json',
      metadataBytes,
      timeoutSeconds: AppConfig.webdavDeltaTimeoutSeconds,
      criticalVerify: true,
    );
  }

  /// Gets ETags for all pages in the exploded folder.
  /// Returns {pageFileName: etag}.
  ///
  /// Throws on network failure instead of returning an empty map. Returning
  /// empty on failure was catastrophic: the pull diff interpreted the zero
  /// result as 'every locally-cached page was deleted from the server' and
  /// wiped the local state (observed in production: 183 pages auto-removed
  /// then restored as BLANK placeholders after a Tailscale hiccup). Callers
  /// that want a tolerant default can catch and interpret themselves.
  Future<Map<String, String>> getRemotePageEtags(String notebookId) async {
    final dir = _deltaDir(notebookId);
    final items = await _webdav.listDirectory('${dir}pages/');
    return {
      for (final item in items)
        if (!item.isDirectory &&
            item.name.endsWith('.json') &&
            item.etag != null)
          item.name: item.etag!,
    };
  }

  /// Fetch metadata ETag + page ETags in one parallel call.
  /// Saves one full round-trip vs sequential getDeltaMetaEtag + getRemotePageEtags.
  Future<({String? metaEtag, Map<String, String> pageEtags})>
      getRemoteChangeState(String notebookId) async {
    final results = await Future.wait([
      getDeltaMetaEtag(notebookId),
      getRemotePageEtags(notebookId),
    ]);
    return (
      metaEtag: results[0] as String?,
      pageEtags: results[1] as Map<String, String>,
    );
  }

  /// Gets the ETag of the remote metadata.json (cheap change-detection).
  /// Uses HEAD request — faster than PROPFIND.
  Future<String?> getDeltaMetaEtag(String notebookId) async {
    try {
      return await _webdav.getEtagFast('${_deltaDir(notebookId)}metadata.json')
          ?? await _webdav.getEtag('${_deltaDir(notebookId)}metadata.json');
    } catch (_) {
      return null;
    }
  }

  /// Gets the ETag of the remote .ncnote ZIP file (fallback change-detection).
  /// Uses HEAD request — faster than PROPFIND.
  Future<String?> getNcnoteEtag(String remotePath) async {
    try {
      return await _webdav.getEtagFast(remotePath)
          ?? await _webdav.getEtag(remotePath);
    } catch (_) {
      return null;
    }
  }

  /// Gets both ETag + Last-Modified of the remote .ncnote in one PROPFIND.
  /// Returns null on any error or if the file doesn't exist.
  Future<({String? etag, DateTime? lastModified})?> getNcnoteInfo(
      String remotePath) async {
    return _webdav.getFileInfo(remotePath);
  }

  /// Downloads raw bytes from a remote path.
  Future<Uint8List> downloadFile(String remotePath) async {
    return _webdav.downloadFile(remotePath);
  }

  /// Downloads a single page from the exploded folder.
  Future<PageData> downloadDeltaPage(
    String notebookId,
    String pageFileName,
  ) async {
    final data = await _webdav.downloadFile(
      '${_deltaDir(notebookId)}pages/$pageFileName',
    );
    final json = jsonDecode(utf8.decode(data));
    return decodePageData(json as Map<String, dynamic>);
  }

  /// Fetches ONLY `.sync/<id>/metadata.json` — a ≤1 KB file containing the
  /// authoritative library-card info (title, pageCount, coverColor, ...).
  /// Much cheaper than [downloadDeltaMeta] (which also pulls the entire
  /// document.json) or [downloadExplodedFull] (which pulls every page).
  ///
  /// Returns null on any error so the caller can fall back to the root
  /// .ncnote metadata without propagating a failure.
  Future<NotebookMetadata?> downloadDeltaMetadataOnly(String notebookId) async {
    try {
      final bytes = await _webdav
          .downloadFile('${_deltaDir(notebookId)}metadata.json',
              criticalVerify: true)
          .timeout(const Duration(seconds: 10));
      return NotebookMetadata.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Downloads metadata + document from the exploded folder.
  /// Parallel download — both requests fire simultaneously.
  ///
  /// [criticalVerify] is forced on: a truncated body on either of these
  /// two files aborts the whole delta pull (the FormatException escapes
  /// every per-page handler), which strands `_lastPageEtags` and forces
  /// the same 300-page changeset to replay every cycle until the user
  /// sees their notebook frozen at 0/330. We pay the +1 RTT PROPFIND
  /// when Nextcloud serves chunked (Content-Length absent) so the body
  /// gets validated even when the cheap header check has nothing to
  /// compare against.
  Future<({NotebookMetadata metadata, DocumentStructure document})>
      downloadDeltaMeta(String notebookId) async {
    final dir = _deltaDir(notebookId);
    final results = await Future.wait([
      _webdav.downloadFile('${dir}metadata.json', criticalVerify: true),
      _webdav.downloadFile('${dir}document.json', criticalVerify: true),
    ]);

    return (
      metadata: NotebookMetadata.fromJson(
        jsonDecode(utf8.decode(results[0])) as Map<String, dynamic>,
      ),
      document: DocumentStructure.fromJson(
        jsonDecode(utf8.decode(results[1])) as Map<String, dynamic>,
      ),
    );
  }

  /// Downloads an asset from the exploded folder.
  Future<Uint8List> downloadDeltaAsset(
    String notebookId,
    String assetPath,
  ) async {
    return _webdav.downloadFile(
      '${_deltaDir(notebookId)}assets/$assetPath',
    );
  }

  /// Checks whether the exploded folder exists on the server.
  ///
  /// Returns true if the folder's metadata.json can be HEAD'd, false on a
  /// definite 404 (folder absent). Any OTHER error (timeout, TLS, 5xx) is
  /// RETHROWN so callers can distinguish "server says gone" from "I don't
  /// know". The library's remote-deletion cleanup depends on this
  /// distinction — treating a network blip as "gone" would permanently
  /// wipe the local .ncnote of a notebook that's actually still alive.
  Future<bool> deltaFolderExists(String notebookId) async {
    // Fast path: already confirmed in this session
    if (_explodedDirsReady.contains(notebookId)) return true;
    try {
      await _webdav.getEtag('${_deltaDir(notebookId)}metadata.json');
      _explodedDirsReady.add(notebookId);
      return true;
    } on WebDavException catch (e) {
      if (e.statusCode == 404) return false;
      rethrow;
    }
  }

  /// Deletes the notebook's exploded delta folder from the server.
  ///
  /// Must be called when a notebook is deleted: the library's remote-deletion
  /// cleanup keeps any notebook whose delta folder is still alive (see
  /// deltaFolderExists callers), so a leftover `.sync/<id>/` makes the
  /// deleted notebook resurrect on other devices at their next save.
  /// WebDAV DELETE on a collection is recursive; 404 is tolerated.
  Future<void> deleteDeltaFolder(String notebookId) async {
    _explodedDirsReady.remove(notebookId);
    await _webdav.delete(_deltaDir(notebookId));
  }

  /// One-time migration: explodes a .ncnote ZIP into the per-page folder.
  /// All files are uploaded in parallel for speed.
  Future<void> migrateToExploded(String notebookId, Uint8List ncnoteData) async {
    await _ensureDeltaDir(notebookId);
    final dir = _deltaDir(notebookId);
    final archive = ZipDecoder().decodeBytes(ncnoteData);

    // Create asset subdirectories that might be needed
    final subDirs = <String>{};
    for (final file in archive.files) {
      if (file.isFile && file.name.contains('/')) {
        final parent = file.name.substring(0, file.name.lastIndexOf('/'));
        if (parent.startsWith(AppConfig.assetsDir) && parent != AppConfig.assetsDir) {
          subDirs.add(parent);
        }
      }
    }
    for (final sub in subDirs) {
      await _webdav.createDirectory('$dir$sub/');
    }

    // Upload all files in parallel
    final futures = archive.files
        .where((f) => f.isFile)
        .map((f) => _webdav.uploadFile(
              '$dir${f.name}',
              Uint8List.fromList(f.content as List<int>),
            ))
        .toList();

    await Future.wait(futures);
    debugPrint('[Sync] Migrated $notebookId to exploded format '
        '(${futures.length} files)');
  }

  /// Downloads a full notebook from the exploded folder structure.
  Future<({NotebookMetadata metadata, DocumentStructure document, Map<String, PageData> pages, Map<String, Uint8List> assets, List<Map<String, dynamic>> symbolLibraries})>
      downloadExplodedFull(String notebookId) async {
    final dir = _deltaDir(notebookId);

    final meta = await downloadDeltaMeta(notebookId);

    // Download all pages with per-page retry
    final pageItems = await _webdav.listDirectory('${dir}pages/');
    final pages = <String, PageData>{};

    Future<void> downloadPage(String fileName) async {
      const maxPageRetries = 3;
      for (var attempt = 0; attempt < maxPageRetries; attempt++) {
        try {
          final data = await _webdav.downloadFile('${dir}pages/$fileName');
          final json = jsonDecode(utf8.decode(data));
          pages[fileName] = decodePageData(json as Map<String, dynamic>);
          return;
        } catch (e) {
          if (attempt == maxPageRetries - 1) {
            debugPrint('[Sync] FAILED to download page $fileName '
                'for $notebookId after $maxPageRetries attempts: $e');
            rethrow;
          }
          await Future.delayed(
              Duration(milliseconds: 200 * (attempt + 1)));
        }
      }
    }

    final pageFutures = <Future<void>>[];
    for (final item in pageItems) {
      if (!item.isDirectory && item.name.endsWith('.json')) {
        pageFutures.add(downloadPage(item.name));
      }
    }
    // eagerError:false so all pages attempt even if some fail
    await Future.wait(pageFutures, eagerError: false);

    // Verify we got every page listed in document.pages
    final expectedFileNames = meta.document.pages
        .map((e) => e.fileName)
        .where((f) => f.isNotEmpty)
        .toSet();
    final missingPages = expectedFileNames.difference(pages.keys.toSet());
    if (missingPages.isNotEmpty) {
      debugPrint('[Sync] Retrying ${missingPages.length} missing pages '
          'for $notebookId: $missingPages');
      // Sequential retry for the stragglers
      for (final fileName in missingPages) {
        try {
          await downloadPage(fileName);
        } catch (e) {
          debugPrint('[Sync] Page $fileName still missing after retry: $e');
          // Continue — caller will detect the mismatch
        }
      }
    }

    // Download assets. eagerError:false so a single transient WebDAV
    // failure on a flaky network (e.g. Tailscale) doesn't abort the
    // whole batch and leave the rebuilt .ncnote missing assets the
    // server actually has — those would later render with the orange
    // broken-image badge on the iPad even though "Ricarica" appeared
    // to succeed. Per-asset retry mirrors the per-page retry above.
    final assets = <String, Uint8List>{};
    final failedAssets = <String>[];
    try {
      final assetItems = await _webdav.listDirectory('${dir}assets/');

      Future<void> downloadAsset(String name) async {
        const maxAssetRetries = 3;
        for (var attempt = 0; attempt < maxAssetRetries; attempt++) {
          try {
            final data = await _webdav.downloadFile('${dir}assets/$name');
            assets[name] = data;
            return;
          } catch (e) {
            if (attempt == maxAssetRetries - 1) {
              debugPrint('[Sync] FAILED to download asset $name '
                  'for $notebookId after $maxAssetRetries attempts: $e');
              failedAssets.add(name);
              return;
            }
            await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
          }
        }
      }

      final assetFutures = <Future<void>>[];
      for (final item in assetItems) {
        if (!item.isDirectory) {
          assetFutures.add(downloadAsset(item.name));
        }
      }
      await Future.wait(assetFutures, eagerError: false);
      if (failedAssets.isNotEmpty) {
        debugPrint('[Sync] downloadExplodedFull($notebookId): '
            '${failedAssets.length} asset(s) failed after retries: '
            '$failedAssets');
      }
    } catch (e) {
      debugPrint('[Sync] downloadExplodedFull($notebookId) asset phase '
          'aborted: $e');
    }

    // Download symbols
    var symbols = <Map<String, dynamic>>[];
    try {
      final symData = await _webdav.downloadFile('${dir}symbols.json');
      symbols = (jsonDecode(utf8.decode(symData)) as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {}

    return (
      metadata: meta.metadata,
      document: meta.document,
      pages: pages,
      assets: assets,
      symbolLibraries: symbols,
    );
  }

  /// Builds a .ncnote ZIP package from already-decoded parts.
  ///
  /// Used after [downloadExplodedFull] so the caller can persist the freshly
  /// downloaded notebook to local storage (otherwise re-opening would
  /// re-download the whole exploded tree — the "open from server, close,
  /// reopen, re-downloads everything" bug).
  static Uint8List buildPackageBytes({
    required NotebookMetadata metadata,
    required DocumentStructure document,
    required Map<String, PageData> pages,
    Map<String, Uint8List>? assets,
    List<Map<String, dynamic>>? symbolLibraries,
  }) {
    final archive = Archive();

    final metaBytes = utf8.encode(jsonEncode(metadata.toJson()));
    archive.addFile(ArchiveFile(AppConfig.metadataFile, metaBytes.length, metaBytes));

    final docBytes = utf8.encode(jsonEncode(document.toJson()));
    archive.addFile(ArchiveFile(AppConfig.documentFile, docBytes.length, docBytes));

    for (final entry in pages.entries) {
      final bytes = utf8.encode(jsonEncode(entry.value.toJson()));
      archive.addFile(ArchiveFile(
        '${AppConfig.pagesDir}/${entry.key}', bytes.length, bytes,
      ));
    }

    if (assets != null) {
      for (final entry in assets.entries) {
        archive.addFile(ArchiveFile(
          '${AppConfig.assetsDir}/${entry.key}',
          entry.value.length,
          entry.value,
        )..compress = !isPrecompressedAsset(entry.key));
      }
    }

    if (symbolLibraries != null && symbolLibraries.isNotEmpty) {
      final symBytes = utf8.encode(jsonEncode(symbolLibraries));
      archive.addFile(ArchiveFile('symbols.json', symBytes.length, symBytes));
    }

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  /// Estrae tutte le pagine da un archivio .ncnote raw bytes.
  Map<String, PageData> extractAllPages(Uint8List data) {
    final archive = ZipDecoder().decodeBytes(data);
    final pages = <String, PageData>{};

    for (final file in archive.files) {
      if (file.name.startsWith('${AppConfig.pagesDir}/') &&
          file.name.endsWith('.json')) {
        final fileName = file.name.split('/').last;
        final json = jsonDecode(utf8.decode(file.content as List<int>));
        pages[fileName] = decodePageData(json as Map<String, dynamic>);
      }
    }

    return pages;
  }

  /// Extract all pages on a background isolate for large archives.
  ///
  /// Decoding a ZIP + parsing every page JSON on the UI isolate jank-locks
  /// notebooks with dozens of pages. This variant hops off onto a worker via
  /// [compute] and awaits the decoded map. Use it when the notebook is known
  /// to be heavy (see [AppConfig] and call sites in [library_screen]).
  Future<Map<String, PageData>> extractAllPagesIsolated(Uint8List data) {
    return compute(_extractAllPagesInIsolate, data);
  }

  /// Single-pass extraction of pages + assets + symbol libraries.
  ///
  /// One `ZipDecoder().decodeBytes` walk instead of the three separate
  /// passes that calling [extractAllPages] + [extractAllAssets] +
  /// [extractSymbolLibraries] on the same buffer costs. Use whenever
  /// more than one of those is needed on the same archive.
  NcnoteContents extractNotebookContents(Uint8List data) =>
      _extractContentsImpl(data);

  /// Background-isolate version of [extractNotebookContents].
  ///
  /// Replaces the old extractAllPagesIsolated + extractAllAssetsIsolated
  /// pair on the notebook-open path: one isolate spawn and ONE copy of
  /// the multi-MB archive across the isolate boundary instead of two.
  Future<NcnoteContents> extractNotebookContentsIsolated(Uint8List data) {
    return compute(_extractContentsImpl, data);
  }

  /// Load + parse a notebook's loose store directly from its on-disk directory
  /// [dir] (see [FileService.notebookStoreDir]), on a BACKGROUND ISOLATE,
  /// WITHOUT ever building or decoding a `.ncnote` ZIP. Returns null when the
  /// directory or its metadata/document are missing, so the caller can fall
  /// back to the legacy file / server-download recovery.
  ///
  /// Why an isolate with *synchronous* reads: reading the ~1700 small loose
  /// files with sequential `await readAsBytes` on the MAIN isolate took ~16 s
  /// on a 735-page / 228 MB notebook — not because the disk is slow (a warm
  /// `cat` of the same files is 0.1 s) but because each of the ~1700 async
  /// round-trips had to wait its turn on the open-time-congested main event
  /// loop. A dedicated isolate's event loop is idle and `readAsBytesSync`
  /// has no round-trips at all, bringing it back to ~1-2 s while never
  /// blocking the UI.
  Future<LooseStoreContents?> loadLooseStoreFromDisk(String dir) {
    return compute(_loadLooseStoreImpl, dir);
  }

  /// Scarica un notebook completo con tutte le pagine.
  /// Validates ZIP integrity before parsing.
  Future<({NotebookMetadata metadata, DocumentStructure document, Map<String, PageData> pages, Map<String, Uint8List> assets, List<Map<String, dynamic>> symbolLibraries})>
      downloadNotebookFull(String remotePath) async {
    final data = await _webdav.downloadFile(remotePath);

    // ── Validate before any parsing ──
    validateNcnoteArchive(data, context: 'downloadFull $remotePath');

    final result = _parseNcnoteArchive(data);
    final pages = extractAllPages(data);
    final assets = extractAllAssets(data);
    final symbols = extractSymbolLibraries(data);
    return (
      metadata: result.metadata,
      document: result.document,
      pages: pages,
      assets: assets,
      symbolLibraries: symbols,
    );
  }

  /// Estrae tutti gli asset binari (immagini) da un archivio .ncnote.
  Map<String, Uint8List> extractAllAssets(Uint8List data) {
    final archive = ZipDecoder().decodeBytes(data);
    final assets = <String, Uint8List>{};
    for (final file in archive.files) {
      if (file.name.startsWith('${AppConfig.assetsDir}/') && file.isFile) {
        final fileName = file.name.substring('${AppConfig.assetsDir}/'.length);
        if (fileName.isNotEmpty) {
          assets[fileName] = Uint8List.fromList(file.content as List<int>);
        }
      }
    }
    return assets;
  }

  /// Background-isolate version of [extractAllAssets].
  /// Hop off the UI thread for large notebooks that contain many images.
  Future<Map<String, Uint8List>> extractAllAssetsIsolated(Uint8List data) {
    return compute(_extractAllAssetsInIsolate, data);
  }

  /// Background-isolate version of [buildPackageBytes].
  ///
  /// Serialises the parameters to plain JSON-compatible types (sendable across
  /// isolate boundaries), builds the ZIP on a worker thread, and returns the
  /// raw bytes.  Use this whenever you build a .ncnote off the UI thread.
  static Future<Uint8List> buildPackageBytesIsolated({
    required NotebookMetadata metadata,
    required DocumentStructure document,
    required Map<String, PageData> pages,
    Map<String, Uint8List>? assets,
    List<Map<String, dynamic>>? symbolLibraries,
  }) {
    final params = <String, Object?>{
      'metadata': metadata.toJson(),
      'document': document.toJson(),
      'pages': pages.map((k, v) => MapEntry(k, v.toJson())),
      if (assets != null) 'assets': assets,
      if (symbolLibraries != null && symbolLibraries.isNotEmpty)
        'symbols': symbolLibraries,
    };
    return compute(_buildPackageBytesInIsolate, params);
  }

  void dispose() {}
}

/// Exception thrown when a .ncnote archive is detected as corrupted.
class CorruptedArchiveException implements Exception {
  final String message;
  CorruptedArchiveException(this.message);

  @override
  String toString() => 'CorruptedArchiveException: $message';
}

/// Thrown by [SyncService.syncDelta] when pages + document.json have
/// already been committed to the server but metadata.json (the commit
/// marker) failed to upload. The server is half-committed at this
/// moment: cross-device readers fast-path-skip on the unchanged
/// meta-ETag and miss the new pages. Caller MUST persist
/// [metadataBytes] and replay the metadata.json upload until it lands.
class MetadataCommitFailedException implements Exception {
  final String notebookId;
  final Uint8List metadataBytes;
  final Object cause;

  MetadataCommitFailedException({
    required this.notebookId,
    required this.metadataBytes,
    required this.cause,
  });

  @override
  String toString() =>
      'MetadataCommitFailedException(nb=$notebookId, bytes=${metadataBytes.length}, cause=$cause)';
}

/// Pages + assets + symbol libraries decoded from a .ncnote archive in a
/// single pass. See [SyncService.extractNotebookContents].
typedef NcnoteContents = ({
  Map<String, PageData> pages,
  Map<String, Uint8List> assets,
  List<Map<String, dynamic>> symbolLibraries,
});

/// Open-ready notebook data parsed straight from a loose store, bypassing the
/// `.ncnote` ZIP entirely. See [SyncService.loadLooseStoreFromDisk].
typedef LooseStoreContents = ({
  NotebookMetadata metadata,
  DocumentStructure document,
  Map<String, PageData> pages,
  Map<String, Uint8List> assets,
  List<Map<String, dynamic>> symbolLibraries,
});

/// Isolate entry point for [SyncService.loadLooseStoreFromDisk]. Reads every
/// loose-store file SYNCHRONOUSLY (no event-loop round-trips) and parses pages
/// inline — both cheap on a dedicated, idle isolate. Returns null if the store
/// or its metadata/document are missing.
LooseStoreContents? _loadLooseStoreImpl(String dir) {
  if (!Directory(dir).existsSync()) return null;

  final metaFile = File(p.join(dir, AppConfig.metadataFile));
  final docFile = File(p.join(dir, AppConfig.documentFile));
  if (!metaFile.existsSync() || !docFile.existsSync()) return null;

  // Any undecodable file (truncated/0-byte json from a crash mid-write)
  // makes the whole store unusable — return null instead of throwing so
  // the opener falls through to its designed recovery path (legacy .ncnote
  // → server download). Throwing here used to skip that recovery entirely
  // and brick the notebook behind an "Impossibile aprire" snackbar.
  final NotebookMetadata metadata;
  final DocumentStructure document;
  try {
    metadata = NotebookMetadata.fromJson(
        jsonDecode(utf8.decode(metaFile.readAsBytesSync()))
            as Map<String, dynamic>);
    document = DocumentStructure.fromJson(
        jsonDecode(utf8.decode(docFile.readAsBytesSync()))
            as Map<String, dynamic>);
  } catch (_) {
    return null;
  }

  // Pages: flat `pages/page_xxx.json`, keyed by file name (matches
  // extractAllPages' `file.name.split('/').last`).
  final pages = <String, PageData>{};
  final pagesDir = Directory(p.join(dir, AppConfig.pagesDir));
  if (pagesDir.existsSync()) {
    for (final e in pagesDir.listSync(recursive: true)) {
      if (e is File && e.path.endsWith('.json')) {
        try {
          final json = jsonDecode(utf8.decode(e.readAsBytesSync()));
          pages[p.basename(e.path)] =
              decodePageData(json as Map<String, dynamic>);
        } catch (_) {
          return null; // corrupt page → full fallback, see note above
        }
      }
    }
  }

  // Assets: keyed by the sub-path after `assets/` (matches extractAllAssets),
  // normalised to forward slashes so nested keys stay stable.
  final assets = <String, Uint8List>{};
  final assetsDir = Directory(p.join(dir, AppConfig.assetsDir));
  if (assetsDir.existsSync()) {
    for (final e in assetsDir.listSync(recursive: true)) {
      if (e is File && !e.path.endsWith('.tmp')) {
        final key =
            p.split(p.relative(e.path, from: assetsDir.path)).join('/');
        assets[key] = e.readAsBytesSync();
      }
    }
  }

  var symbols = <Map<String, dynamic>>[];
  final symFile = File(p.join(dir, 'symbols.json'));
  if (symFile.existsSync()) {
    // Same tolerance as extractSymbolLibraries: malformed symbols must not
    // abort the open — fall back to an empty library.
    try {
      symbols = (jsonDecode(utf8.decode(symFile.readAsBytesSync())) as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {}
  }

  return (
    metadata: metadata,
    document: document,
    pages: pages,
    assets: assets,
    symbolLibraries: symbols,
  );
}

/// Shared implementation for [SyncService.extractNotebookContents] and its
/// isolate variant — top level so [compute] can take it directly.
NcnoteContents _extractContentsImpl(Uint8List data) {
  final archive = ZipDecoder().decodeBytes(data);
  final pages = <String, PageData>{};
  final assets = <String, Uint8List>{};
  var symbols = <Map<String, dynamic>>[];
  const pagesPrefix = '${AppConfig.pagesDir}/';
  const assetsPrefix = '${AppConfig.assetsDir}/';
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final name = file.name;
    if (name.startsWith(pagesPrefix) && name.endsWith('.json')) {
      // Skip undecodable pages instead of aborting the whole extraction:
      // one truncated page.json used to brick the entire notebook. A
      // partially-opened notebook is recoverable (ghost-entry repair,
      // server pull); an unopenable one is not. If ALL pages are corrupt,
      // the opener's `pages.isEmpty` check still falls back to a full
      // server download.
      try {
        final json = jsonDecode(utf8.decode(file.content as List<int>));
        pages[name.split('/').last] =
            decodePageData(json as Map<String, dynamic>);
      } catch (_) {}
    } else if (name.startsWith(assetsPrefix)) {
      final assetName = name.substring(assetsPrefix.length);
      if (assetName.isNotEmpty) {
        assets[assetName] = Uint8List.fromList(file.content as List<int>);
      }
    } else if (name == 'symbols.json') {
      // Same tolerance as extractSymbolLibraries: malformed symbols must
      // not abort the open — fall back to an empty library.
      try {
        final json = jsonDecode(utf8.decode(file.content as List<int>));
        symbols = (json as List).cast<Map<String, dynamic>>();
      } catch (_) {}
    }
  }
  return (pages: pages, assets: assets, symbolLibraries: symbols);
}

/// Top-level entry point for [SyncService.extractAllPagesIsolated].
///
/// Must live at the top level (not inside the class) so it can be passed to
/// [compute], which uses a pure function pointer.
Map<String, PageData> _extractAllPagesInIsolate(Uint8List data) {
  final archive = ZipDecoder().decodeBytes(data);
  final pages = <String, PageData>{};
  const prefix = '${AppConfig.pagesDir}/';
  for (final file in archive.files) {
    if (file.name.startsWith(prefix) && file.name.endsWith('.json')) {
      final fileName = file.name.split('/').last;
      final json = jsonDecode(utf8.decode(file.content as List<int>));
      pages[fileName] = decodePageData(json as Map<String, dynamic>);
    }
  }
  return pages;
}

/// Top-level entry point for [SyncService.extractAllAssetsIsolated].
Map<String, Uint8List> _extractAllAssetsInIsolate(Uint8List data) {
  final archive = ZipDecoder().decodeBytes(data);
  final assets = <String, Uint8List>{};
  const prefix = '${AppConfig.assetsDir}/';
  for (final file in archive.files) {
    if (file.name.startsWith(prefix) && file.isFile) {
      final fileName = file.name.substring(prefix.length);
      if (fileName.isNotEmpty) {
        assets[fileName] = Uint8List.fromList(file.content as List<int>);
      }
    }
  }
  return assets;
}

/// Top-level entry point for [SyncService.buildPackageBytesIsolated].
///
/// Accepts plain JSON-compatible types so the data can cross the isolate
/// boundary via SendPort. All Freezed models are pre-serialised by the
/// calling side and reconstructed here before building the archive.
Uint8List _buildPackageBytesInIsolate(Map<String, Object?> params) {
  final metadataJson = params['metadata'] as Map<String, dynamic>;
  final documentJson = params['document'] as Map<String, dynamic>;
  final pagesRaw    = params['pages']    as Map<String, dynamic>;
  final assetsRaw   = params['assets']   as Map<String, Uint8List>?;
  final symbolsRaw  = params['symbols']  as List<dynamic>?;

  final pages = pagesRaw.map(
    (k, v) => MapEntry(k, PageData.fromJson(v as Map<String, dynamic>)),
  );
  final symbols = symbolsRaw
      ?.map((e) => e as Map<String, dynamic>)
      .toList();

  return SyncService.buildPackageBytes(
    metadata: NotebookMetadata.fromJson(metadataJson),
    document: DocumentStructure.fromJson(documentJson),
    pages: pages,
    assets: assetsRaw,
    symbolLibraries: symbols,
  );
}
