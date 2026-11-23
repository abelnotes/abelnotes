import 'package:flutter/foundation.dart';

import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/features/canvas/data/pdf_sources.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Source PDFs of imported pages: mirrored with the server, unused ones retired.
class PdfSources {
  PdfSources(this._core, this._allReferencedAssetIds);

  final CanvasCore _core;
  final Set<String> Function(DocumentStructure, Map<String, PageData>)
      _allReferencedAssetIds;

  /// Bumped when source PDFs of imported pages arrive from the server.
  final ValueNotifier<int> version = ValueNotifier<int>(0);
  bool _dirty = true;
  DateTime? _checkedAt;
  bool _running = false;

  /// Whether a sync is owed (a local import, or never checked this open).
  bool get dirty => _dirty;

  void noteChanged() => _dirty = true;

  /// Forget the last check: a freshly opened notebook syncs at once.
  void resetOnOpen() {
    _dirty = true;
    _checkedAt = null;
  }

  /// Retires imports none of whose pages is left. Only imports older than a
  /// week: a device that hasn't pulled a fresh import's pages yet must not
  /// take them for deleted. Losing a source only costs the sharp zoom.
  Future<bool> _retireUnused(
      PdfSourceStore store, String notebookId) async {
    final s = _core.state;
    if (s == null || s.metadata.id != notebookId || s.isDirty) return false;
    if (s.pendingConflicts.isNotEmpty || s.pendingRemoteChanges != null) {
      return false;
    }
    if (!s.document.pages.every((e) => s.pages.containsKey(e.fileName))) {
      return false;
    }
    final used = _allReferencedAssetIds(s.document, s.pages);
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;
    var retired = false;
    for (final idx in await store.loadIndexes()) {
      final t = idx.createdMs;
      if (t == null || t > cutoff || idx.pages.keys.any(used.contains)) continue;
      await store.retire(idx);
      retired = true;
    }
    return retired;
  }

  /// Mirrors `sources/` with the server on open, after local changes and
  /// every few minutes; its files never change, so this is cheap to skip.
  /// [upToDate]: this copy matches the server, so unused imports may go.
  Future<void> syncQuietly(SyncService sync, String notebookId,
      {bool upToDate = false}) async {
    if (_running) return;
    final last = _checkedAt;
    if (!_dirty &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 5)) {
      return;
    }
    _running = true;
    try {
      final store = PdfSourceStore(
          _core.ref.read(fileServiceProvider).notebookStoreDir(notebookId));
      var arrived = await sync.syncPdfSources(notebookId, store);
      if (upToDate && await _retireUnused(store, notebookId)) {
        await sync.syncPdfSources(notebookId, store);
        arrived = true;
      }
      _dirty = false;
      _checkedAt = DateTime.now();
      if (arrived && _core.state?.metadata.id == notebookId) version.value++;
    } catch (e) {
      debugPrint('[Canvas] source PDF sync failed: $e');
    } finally {
      _running = false;
    }
  }
}
