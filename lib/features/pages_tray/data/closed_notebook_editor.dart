import 'dart:convert';
import 'package:abelnotes/core/platform/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart'
    show decodePageBytes, encodePageBytes;
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/thumbnail_service.dart';
import 'package:abelnotes/features/pages_tray/domain/page_transfer.dart';
import 'package:abelnotes/features/pages_tray/domain/pages_tray.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// The notebook is open in the editor, which owns it.
class NotebookBusyException implements Exception {
  final String notebookId;
  NotebookBusyException(this.notebookId);
  @override
  String toString() => 'NotebookBusyException: $notebookId is open in the editor';
}

/// No readable local copy of the notebook.
class NotebookUnavailableException implements Exception {
  final String notebookId;
  NotebookUnavailableException(this.notebookId);
  @override
  String toString() =>
      'NotebookUnavailableException: no readable local copy of $notebookId';
}

class ClosedInsert {
  final List<String> newPageIds;
  final List<String> newFileNames;
  final int insertIndex;
  const ClosedInsert(this.newPageIds, this.newFileNames, this.insertIndex);
}

class ClosedRemoval {
  final List<RemovedPage> removed;
  final String? blankPageId;
  const ClosedRemoval(this.removed, this.blankPageId);
}

/// Edits a notebook that is not open, on its loose store; sync marking as in
/// ../README.md ("Headless edit and sync").
class ClosedNotebookEditor {
  final FileService files;
  final ThumbnailService? thumbnails;
  final bool Function(String notebookId) isOpenInEditor;

  ClosedNotebookEditor(this.files,
      {this.thumbnails, required this.isOpenInEditor});

  static String _baseDocKey(String id) => 'unpushed_base_doc_$id';
  static String _baseMetaKey(String id) => 'unpushed_base_meta_$id';
  static String _pageDeletesKey(String id) => 'pending_page_deletes_$id';

  Future<({NotebookMetadata meta, DocumentStructure doc})> _read(String id) async {
    if (isOpenInEditor(id)) throw NotebookBusyException(id);
    if (!await files.ensureLooseStore(id)) throw NotebookUnavailableException(id);
    final dir = files.notebookStoreDir(id);
    try {
      final meta = NotebookMetadata.fromJson(jsonDecode(
              await File(p.join(dir, AppConfig.metadataFile)).readAsString())
          as Map<String, dynamic>);
      final doc = DocumentStructure.fromJson(jsonDecode(
              await File(p.join(dir, AppConfig.documentFile)).readAsString())
          as Map<String, dynamic>);
      return (meta: meta, doc: doc);
    } catch (_) {
      throw NotebookUnavailableException(id);
    }
  }

  Uint8List _json(Object o) => Uint8List.fromList(utf8.encode(jsonEncode(o)));

  /// Document page ids of the notebook as stored, null if unreadable.
  Future<Set<String>?> storedPageIds(String id) async {
    try {
      final doc = DocumentStructure.fromJson(jsonDecode(await File(p.join(
                  files.notebookStoreDir(id), AppConfig.documentFile))
              .readAsString())
          as Map<String, dynamic>);
      return {for (final e in doc.pages) e.pageId};
    } catch (_) {
      return null;
    }
  }

  /// True when [pageIds] are in the stored document and their files exist.
  Future<bool> storesPages(String id, Set<String> pageIds) async {
    try {
      final dir = files.notebookStoreDir(id);
      final doc = DocumentStructure.fromJson(jsonDecode(
              await File(p.join(dir, AppConfig.documentFile)).readAsString())
          as Map<String, dynamic>);
      final byId = {for (final e in doc.pages) e.pageId: e};
      for (final pid in pageIds) {
        final e = byId[pid];
        if (e == null) return false;
        if (!await File(p.join(dir, AppConfig.pagesDir, e.fileName)).exists()) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Marks the edit for the next push, before the store changes: a push that
  /// reads the old store meanwhile only re-sends what the server has.
  /// Chapters and page ids of notebook [id] as stored (for choosing a slot).
  Future<({NotebookMetadata meta, DocumentStructure doc})> readStructure(
          String id) =>
      _read(id);

  Future<void> _markDirty(String id, Iterable<String> keys) async {
    await files.addDirtyPages(id, ['doc', ...keys]);
    await files.markNotebookDirty(id);
  }

  /// Runs the store write; if it fails the pre-mark is taken back, so a
  /// failed edit does not leave the notebook looking pending.
  Future<void> _write(String id, Iterable<String> marked, bool hadUnpushed,
      Future<void> Function() write) async {
    try {
      await write();
    } catch (_) {
      try {
        await files.clearDirtyPagesOf(id, {'doc', ...marked});
        if (!hadUnpushed) {
          final row = await files.getNotebookMeta(id);
          await files.markNotebookSynced(id, row?['etag'] as String?);
        }
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _afterWrite(String id, NotebookMetadata meta,
      DocumentStructure before, NotebookMetadata metaBefore,
      {required bool hadUnpushed, Iterable<String> deletedFiles = const []}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!hadUnpushed) {
        if (!prefs.containsKey(_baseDocKey(id))) {
          await prefs.setString(_baseDocKey(id), jsonEncode(before.toJson()));
        }
        if (!prefs.containsKey(_baseMetaKey(id))) {
          await prefs.setString(
              _baseMetaKey(id), jsonEncode(metaBefore.toJson()));
        }
      }
      if (deletedFiles.isNotEmpty) {
        final cur = {...?prefs.getStringList(_pageDeletesKey(id))};
        await prefs.setStringList(
            _pageDeletesKey(id), {...cur, ...deletedFiles}.toList());
      }
    } catch (e) {
      debugPrint('[ClosedEditor] sync bookkeeping failed for $id: $e');
    }
    await files.refreshNotebookCard(
      id: id,
      title: meta.title,
      localModifiedAt: meta.modifiedAt,
      coverColor: meta.coverColor,
      coverStyle: meta.coverStyle,
      paperType: meta.paperType,
      pageCount: meta.pageCount,
      createdAt: meta.createdAt,
    );
  }

  /// Takes [pageIds] out of notebook [id]; ids already gone are ignored.
  Future<ClosedRemoval> removePages(String id, Set<String> pageIds) async {
    final cur = await _read(id);
    final now = DateTime.now();
    final plan = planRemove(
        document: cur.doc,
        chapters: cur.meta.chapters,
        pageIds: pageIds,
        paperType: cur.meta.paperType,
        now: now);
    if (plan.removed.isEmpty) return const ClosedRemoval([], null);
    final hadUnpushed = (await files.dirtyPagesOf(id)).isNotEmpty;
    final meta = cur.meta.copyWith(
        chapters: plan.chapters,
        pageCount: plan.document.pages.length,
        modifiedAt: now);
    final blank = plan.blankEntry;
    final marks = [if (blank != null) blank.fileName];
    await _markDirty(id, marks);
    await _write(
        id,
        marks,
        hadUnpushed,
        () => files.saveNotebookIncremental(
              id,
              metadataJson: _json(meta.toJson()),
              documentJson: _json(plan.document.toJson()),
              changedPages: {
                if (blank != null)
                  blank.fileName: encodePageBytes(plan.blankData!),
              },
              deletedPages: plan.removedFileNames.toList(),
            ));
    await _afterWrite(id, meta, cur.doc, cur.meta,
        hadUnpushed: hadUnpushed, deletedFiles: plan.removedFileNames);
    await _refreshCover(id, cur.doc, plan.document);
    return ClosedRemoval(plan.removed, blank?.pageId);
  }

  /// Inserts [pages] into notebook [id] at [slot] with fresh ids; [assets]
  /// are written when the notebook does not have them.
  Future<ClosedInsert> insertPages(String id, List<TrayPage> pages,
      Map<String, Uint8List> assets, PasteSlot slot,
      {List<String>? pageIds}) async {
    final cur = await _read(id);
    final now = DateTime.now();
    final plan = planInsert(
        document: cur.doc,
        chapters: cur.meta.chapters,
        pages: pages,
        slot: slot,
        now: now,
        pageIds: pageIds);
    return _writeInsert(id, cur, plan, assets, now);
  }

  /// Puts pages a move took out back with their old ids and files, and drops
  /// the blank page that stood in for an emptied notebook.
  Future<void> restoreRemoved(String id, ClosedRemoval removal,
      Map<String, PageData> data) async {
    final cur = await _read(id);
    final now = DateTime.now();
    var doc = cur.doc;
    final newData = <String, PageData>{};
    final newFiles = <String>[];
    for (final r in removal.removed.reversed) {
      final d = data[r.entry.pageId];
      if (d == null) continue;
      final plan = planInsert(
          document: doc,
          chapters: cur.meta.chapters,
          pages: [TrayPage(r.entry, d)],
          slot: PasteSlot(afterPageId: r.afterPageId),
          now: now,
          keepIdentity: true);
      doc = plan.document;
      newData.addAll(plan.newPages);
      newFiles.addAll(plan.newEntries.map((e) => e.fileName));
    }
    var deletedBlank = <String>[];
    if (removal.blankPageId != null) {
      final rm = planRemove(
          document: doc,
          chapters: cur.meta.chapters,
          pageIds: {removal.blankPageId!},
          paperType: cur.meta.paperType,
          now: now);
      doc = rm.document;
      deletedBlank = rm.removedFileNames.toList();
    }
    final meta = cur.meta.copyWith(
        chapters: chaptersWithMembership(cur.meta.chapters, doc),
        pageCount: doc.pages.length,
        modifiedAt: now);
    final hadUnpushed = (await files.dirtyPagesOf(id)).isNotEmpty;
    await _markDirty(id, newFiles);
    await _write(
        id,
        newFiles,
        hadUnpushed,
        () => files.saveNotebookIncremental(
              id,
              metadataJson: _json(meta.toJson()),
              documentJson: _json(doc.toJson()),
              changedPages: {
                for (final e in newData.entries)
                  e.key: encodePageBytes(e.value),
              },
              deletedPages: deletedBlank,
            ));
    await _afterWrite(id, meta, cur.doc, cur.meta,
        hadUnpushed: hadUnpushed, deletedFiles: deletedBlank);
    // Restored files are alive again: a delete still queued would remove them.
    try {
      final prefs = await SharedPreferences.getInstance();
      final queued = prefs.getStringList(_pageDeletesKey(id));
      if (queued != null) {
        await prefs.setStringList(_pageDeletesKey(id),
            queued.where((f) => !newFiles.contains(f)).toList());
      }
    } catch (_) {}
    await _refreshCover(id, cur.doc, doc);
  }

  Future<ClosedInsert> _writeInsert(
      String id,
      ({NotebookMetadata meta, DocumentStructure doc}) cur,
      InsertPlan plan,
      Map<String, Uint8List> assets,
      DateTime now) async {
    final dir = files.notebookStoreDir(id);
    final missing = <String, Uint8List>{};
    for (final e in assets.entries) {
      if (!await File(p.join(dir, AppConfig.assetsDir, e.key)).exists()) {
        missing[e.key] = e.value;
      }
    }
    final meta = cur.meta.copyWith(
        chapters: chaptersWithMembership(cur.meta.chapters, plan.document),
        pageCount: plan.document.pages.length,
        modifiedAt: now);
    final hadUnpushed = (await files.dirtyPagesOf(id)).isNotEmpty;
    final marks = [
      ...plan.newPages.keys,
      for (final a in missing.keys) 'asset:$a',
    ];
    await _markDirty(id, marks);
    await _write(
        id,
        marks,
        hadUnpushed,
        () => files.saveNotebookIncremental(
              id,
              metadataJson: _json(meta.toJson()),
              documentJson: _json(plan.document.toJson()),
              changedPages: {
                for (final e in plan.newPages.entries)
                  e.key: encodePageBytes(e.value),
              },
              changedAssets: missing,
            ));
    await _afterWrite(id, meta, cur.doc, cur.meta, hadUnpushed: hadUnpushed);
    await _refreshCover(id, cur.doc, plan.document);
    return ClosedInsert(plan.newPageIds,
        [for (final e in plan.newEntries) e.fileName], plan.insertIndex);
  }

  /// Re-renders the library cover when the first page changed.
  Future<void> _refreshCover(
      String id, DocumentStructure before, DocumentStructure after) async {
    final t = thumbnails;
    if (t == null || after.pages.isEmpty) return;
    if (before.pages.isNotEmpty &&
        before.pages.first.pageId == after.pages.first.pageId) {
      return;
    }
    try {
      final dir = files.notebookStoreDir(id);
      final first = after.pages.first;
      final page = decodePageBytes(await File(
              p.join(dir, AppConfig.pagesDir, first.fileName))
          .readAsBytes());
      final tp = TrayPage(first, page);
      final assets = <String, Uint8List>{};
      for (final a in tp.assetIds) {
        final f = File(p.join(dir, AppConfig.assetsDir, a));
        if (await f.exists()) assets[a] = await f.readAsBytes();
      }
      await t.renderAndCache(id, page, assetBytes: assets);
    } catch (e) {
      await t.deleteThumbnail(id);
      debugPrint('[ClosedEditor] cover refresh failed for $id: $e');
    }
  }
}
