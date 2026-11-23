import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Writing the open notebook to its local store: the queue of writes, what
/// the store holds, the retry after a failed write and the error shown.
class NotebookSave {
  NotebookSave(
    this._core, {
    required bool Function() writeBlocked,
    required Future<void> Function(String id) persistUnpushedBase,
    required Future<Map<String, Uint8List>> Function(
            Map<String, PageData> pages, {bool evictMissing})
        encodePages,
    required List<Chapter> Function(List<Chapter>, DocumentStructure)
        chaptersWithMembership,
    required String? Function() remoteMetaEtag,
    required Future<void> Function(String id) persistRemoteMetaEtag,
    required Future<void> Function(String id) persistLastPageEtags,
  })  : _writeBlocked = writeBlocked,
        _persistUnpushedBase = persistUnpushedBase,
        _encodePagesWithCache = encodePages,
        _chaptersWithMembership = chaptersWithMembership,
        _remoteMetaEtag = remoteMetaEtag,
        _persistRemoteMetaEtag = persistRemoteMetaEtag,
        _persistLastPageEtags = persistLastPageEtags;

  final CanvasCore _core;

  /// True for a preview or a snapshot being shown: nothing is written.
  final bool Function() _writeBlocked;
  final Future<void> Function(String id) _persistUnpushedBase;
  final Future<Map<String, Uint8List>> Function(Map<String, PageData> pages,
      {bool evictMissing}) _encodePagesWithCache;
  final List<Chapter> Function(List<Chapter>, DocumentStructure)
      _chaptersWithMembership;
  final String? Function() _remoteMetaEtag;
  final Future<void> Function(String id) _persistRemoteMetaEtag;
  final Future<void> Function(String id) _persistLastPageEtags;

  /// The user chose to leave without what could not be saved: closing must
  /// neither write nor upload it.
  bool discardRequested = false;

  /// Tracks the in-flight local ZIP rebuild from save(). Runs in background
  /// so save() returns quickly; closeNotebook awaits this so the ZIP lands
  /// on disk before the notebook is torn down.
  Future<bool>? _pendingLocalSave;

  /// Tail of the local-write queue: every write to this notebook's store
  /// (edits and pulled changes) runs after the previous one. Never held
  /// across a network call, so a slow server cannot keep edits off disk.
  Future<void> _localWriteTail = Future<void>.value();

  /// The last local write's error, or null once one succeeds. The editor
  /// shows it: a write that fails is retried, but the user must know.
  final ValueNotifier<Object?> localSaveError = ValueNotifier<Object?>(null);
  Timer? _localRetryTimer;
  int _localFailures = 0;

  /// Assets whose bytes changed since the local store last took them.
  final Set<String> dirtyAssetKeys = <String>{};

  /// Page objects known to be written in the local loose store, by identity.
  /// The web pulled-save writes only pages that differ from these.
  Map<String, PageData> storedPages = {};
  Set<String> storedAssets = {};

  /// Document, metadata and symbol objects last written to the local store.
  DocumentStructure? storedDoc;
  NotebookMetadata? storedMeta;
  List<SymbolLibrary>? storedSymbols;

  /// A notebook was opened: what the store holds is what was loaded.
  void openedWith(
      {required Map<String, PageData> pages,
      required Set<String> assets,
      required DocumentStructure? doc,
      required NotebookMetadata meta,
      required List<SymbolLibrary>? symbols}) {
    storedPages = pages;
    storedAssets = assets;
    dirtyAssetKeys.clear();
    storedDoc = doc;
    storedMeta = meta;
    storedSymbols = symbols;
    _localFailures = 0;
    _localRetryTimer?.cancel();
    localSaveError.value = null;
  }

  /// The notebook was closed: forget the store and stop retrying.
  void closed() {
    storedPages = {};
    storedAssets = {};
    dirtyAssetKeys.clear();
    storedDoc = null;
    storedMeta = null;
    storedSymbols = null;
    _localRetryTimer?.cancel();
    _localRetryTimer = null;
    _localFailures = 0;
    localSaveError.value = null;
    discardRequested = false;
  }

  /// Stops what could not be saved from ever being written.
  void discard() {
    discardRequested = true;
    _localRetryTimer?.cancel();
  }

  /// Waits for the last queued local write (the notebook is closing).
  Future<void> awaitPendingWrite() async {
    final pending = _pendingLocalSave;
    if (pending != null) {
      try { await pending; } catch (_) {}
    }
    _pendingLocalSave = null;
  }

  /// Waits for every queued local write.
  Future<void> awaitWriteQueue() async {
    try { await _localWriteTail; } catch (_) {}
  }

  /// Runs [body] after every local write queued before it.
  Future<T> withLocalLock<T>(Future<T> Function() body) {
    final prev = _localWriteTail;
    final done = Completer<void>();
    _localWriteTail = done.future;
    return () async {
      try {
        await prev;
      } catch (_) {}
      try {
        return await body();
      } finally {
        done.complete();
      }
    }();
  }

  /// Queues a write of everything the state holds that the local store
  /// does not. It waits only for earlier local writes, never for the sync
  /// lock: an upload or a pull can hold that for minutes, and edits that
  /// sit only in memory meanwhile are lost to any crash.
  Future<bool> persistLocal() {
    if (discardRequested || _writeBlocked()) {
      return Future<bool>.value(false);
    }
    final f = withLocalLock(_persistLocked);
    _pendingLocalSave = f;
    unawaited(f.whenComplete(() {
      if (identical(_pendingLocalSave, f)) _pendingLocalSave = null;
    }));
    return f;
  }

  /// Schedules a local write when pulled changes landed under edits made
  /// after the merge.
  void persistLocalIfBehind() {
    final st = _core.state;
    if (st == null || _core.isDisposed) return;
    final behind = st.pages.entries
            .any((e) => !identical(storedPages[e.key], e.value)) ||
        storedPages.keys.any((k) => !st.pages.containsKey(k));
    if (behind) unawaited(persistLocal());
  }

  Future<bool> _persistLocked() async {
    final s = _core.state;
    if (s == null || discardRequested) return false;
    final id = s.metadata.id;
    final fileService = _core.ref.read(fileServiceProvider);
    try {
      final hasStore = await fileService.hasLooseStore(id);
      final changed = <String, PageData>{
        for (final e in s.pages.entries)
          if (!hasStore || !identical(storedPages[e.key], e.value))
            e.key: e.value,
      };
      final assets = <String, Uint8List>{
        for (final e in s.assetBytes.entries)
          if (!hasStore ||
              !storedAssets.contains(e.key) ||
              dirtyAssetKeys.contains(e.key))
            e.key: e.value,
      };
      // A document listing pages not in memory (a pull still filling it in)
      // must not replace the one on disk: pages only, until it is whole.
      final docWhole =
          s.document.pages.every((e) => s.pages.containsKey(e.fileName));
      final deleted = hasStore && docWhole
          ? [
              for (final fn in storedPages.keys)
                if (!s.pages.containsKey(fn)) fn,
            ]
          : const <String>[];
      final docChanged = !hasStore ||
          !identical(s.document, storedDoc) ||
          !identical(s.metadata, storedMeta) ||
          !identical(s.symbolLibraries, storedSymbols);
      final writeDoc = docWhole && (docChanged || changed.isNotEmpty ||
          deleted.isNotEmpty || assets.isNotEmpty);
      if (changed.isEmpty && assets.isEmpty && deleted.isEmpty && !writeDoc) {
        _onLocalWriteOk(id);
        return true;
      }

      // Write-ahead: mark what the server does not have before it is on
      // disk, so a crash before the upload still pushes it on reopen.
      await fileService.addDirtyPages(id, [
        ...changed.keys,
        for (final k in assets.keys) 'asset:$k',
        if (writeDoc) 'doc',
      ]);
      await _persistUnpushedBase(id);

      final contentChanged = changed.isNotEmpty ||
          deleted.isNotEmpty ||
          assets.isNotEmpty ||
          !identical(s.document, storedDoc);
      final meta = s.metadata.copyWith(
        pageCount: s.document.pages.length,
        chapters: _chaptersWithMembership(s.metadata.chapters, s.document),
        modifiedAt: contentChanged ? DateTime.now() : s.metadata.modifiedAt,
      );
      final encoded = await _encodePagesWithCache(changed,
          evictMissing: !hasStore);
      final hasSymbols = s.symbolLibraries.isNotEmpty;
      // A stroke changes a page and the metadata, not the page list or the
      // symbols: those files stay as they are on disk.
      final writeDocFile =
          writeDoc && (!hasStore || !identical(s.document, storedDoc));
      final writeSymbols = writeDoc &&
          (!hasStore || !identical(s.symbolLibraries, storedSymbols));
      await fileService.saveNotebookIncremental(
        id,
        metadataJson: writeDoc
            ? Uint8List.fromList(utf8.encode(jsonEncode(meta.toJson())))
            : null,
        documentJson: writeDocFile
            ? Uint8List.fromList(utf8.encode(jsonEncode(s.document.toJson())))
            : null,
        changedPages: encoded,
        changedAssets: assets,
        deletedPages: deleted,
        symbolsJson: writeSymbols && hasSymbols
            ? Uint8List.fromList(utf8.encode(
                jsonEncode(s.symbolLibraries.map((l) => l.toJson()).toList())))
            : null,
        removeSymbols: writeSymbols && !hasSymbols,
      );
      if (_core.state?.metadata.id == id) {
        if (!hasStore) {
          storedPages = {};
          storedAssets = {};
        }
        storedPages.addAll(changed);
        for (final fn in deleted) {
          storedPages.remove(fn);
        }
        storedAssets.addAll(assets.keys);
        for (final k in assets.keys) {
          if (identical(s.assetBytes[k], _core.state?.assetBytes[k])) {
            dirtyAssetKeys.remove(k);
          }
        }
        if (writeDoc) {
          storedDoc = s.document;
          storedMeta = s.metadata;
          storedSymbols = s.symbolLibraries;
        }
      }
      // Preserve the delta ETag: upsert replaces the row.
      await fileService.upsertNotebookMeta(
        id: id,
        title: meta.title,
        remotePath: s.remotePath,
        etag: _remoteMetaEtag(),
        localModifiedAt: meta.modifiedAt,
        syncStatus: 'modified',
        fileSize: await fileService.looseStoreSize(id),
        coverColor: meta.coverColor,
        coverStyle: meta.coverStyle,
        paperType: meta.paperType,
        pageCount: meta.pageCount,
        createdAt: meta.createdAt,
      );
      debugPrint('[Canvas] Saved locally: ${encoded.length} pages, '
          '${assets.length} assets, ${deleted.length} deleted'
          '${writeDoc ? '' : ' (page list held back)'}');
      _onLocalWriteOk(id);
      return true;
    } catch (e) {
      _onLocalWriteFailed(e);
      return false;
    }
  }

  void _onLocalWriteOk(String id) {
    final recovered = _localFailures > 0;
    _localRetryTimer?.cancel();
    _localRetryTimer = null;
    _localFailures = 0;
    if (localSaveError.value != null) localSaveError.value = null;
    // An upload that went through meanwhile skipped its ETag persist; the
    // disk now holds at least what it sent, so record them now.
    if (recovered && _core.state?.metadata.id == id) {
      unawaited(_persistRemoteMetaEtag(id));
      unawaited(_persistLastPageEtags(id));
    }
  }

  /// Nothing else would retry: the edits are no longer "dirty" for the
  /// autosave once the upload went through.
  void _onLocalWriteFailed(Object e) {
    _localFailures++;
    localSaveError.value = e;
    debugPrint('[Canvas] Local save failed ($_localFailures in a row): $e');
    unawaited(CrashLogger.append('[Save] local write FAILED: $e'));
    _localRetryTimer?.cancel();
    final secs = (2 * (1 << (_localFailures - 1).clamp(0, 4))).clamp(2, 30);
    _localRetryTimer = Timer(Duration(seconds: secs), () {
      if (!_core.isDisposed && _core.state != null) unawaited(persistLocal());
    });
  }
}
