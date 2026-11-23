import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/canvas/asset_cache.dart';
import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/features/canvas/data/pdf_text_carry.dart';
import 'package:abelnotes/features/pages_tray/domain/page_transfer.dart';
import 'package:abelnotes/features/pages_tray/domain/pages_tray.dart' show TrayPage;
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Page navigation, page structure (add, insert, duplicate, delete, move,
/// paste) and chapters.
class PagesAndChapters {
  PagesAndChapters(this._core, this._assets, this._nextPageFileName);

  final CanvasCore _core;
  final AssetCache _assets;

  /// Mints a file name for a new page of the given state.
  final String Function(CanvasState) _nextPageFileName;

  /// The page shown at [index] (clamped), or null when there are none.
  static PageData? pageAt(
      DocumentStructure document, Map<String, PageData> pages, int index) {
    if (document.pages.isEmpty) return null;
    return pages[document.pages[index.clamp(0, document.pages.length - 1)]
        .fileName];
  }

  void setActiveChapter(String? chapterId) {
    if (_core.state == null) return;
    final s = _core.state!;
    if (chapterId == null) {
      _core.state = s.copyWith(clearActiveChapter: true);
      return;
    }
    // True orphan only: chapterId not present in metadata.chapters at all
    // (legacy pageId leak from a pre-cleanup migration). Selecting a ghost
    // chip would leave a phantom selection. Fall back to all-pages.
    //
    // An EMPTY chapter (exists in metadata, 0 pages) is a legitimate user
    // state — reachable by deleting all pages of a chapter via the page
    // manager's multi-select. Previously this branch also caught that case
    // and silently deselected the chip; the user couldn't enter their own
    // empty chapter to add fresh pages to it.
    final chapterExists = s.metadata.chapters.any((c) => c.id == chapterId);
    if (!chapterExists) {
      _core.state = s.copyWith(clearActiveChapter: true, clearLasso: true, lassoPath: []);
      return;
    }
    final firstIdx = s.document.pages.indexWhere((p) => p.chapterId == chapterId);
    _core.state = s.copyWith(
      activeChapterId: chapterId,
      // If the chapter has no pages, leave currentPageIndex alone — the page
      // strip will show "0/0" and the user can add pages from the menu.
      currentPageIndex: firstIdx >= 0 ? firstIdx : s.currentPageIndex,
      clearLasso: true,
      lassoPath: [],
    );
  }

  /// Navigate to [index]. By default the user's zoom/pan is preserved so
  /// arrow-button and grid taps don't rip the viewport out from under them.
  /// Pass [resetViewport]=true for gestures where a fresh view is wanted
  /// (e.g. swipe-to-turn-page).
  void goToPage(int index, {bool resetViewport = false}) {
    if (_core.state == null || index < 0 || index >= _core.state!.pageCount) return;
    final s = _core.state!;
    // Record the index we're leaving so the page nav bar can offer a
    // one-tap jump back. Only update if the user is actually changing
    // pages — re-navigating to the current page (e.g. through "Vai a
    // pagina N") shouldn't trash the prior memory.
    final prev = (s.currentPageIndex != index) ? s.currentPageIndex : s.previousPageIndex;
    if (resetViewport) {
      _core.state = s.copyWith(
        currentPageIndex: index,
        previousPageIndex: prev,
        activeStroke: [],
        clearLasso: true,
        lassoPath: [],
        clearSelectedElement: true,
        zoom: 2.0,
        panOffset: _core.centeredPanOffset(2.0, pageAt(s.document, s.pages, index)),
      );
    } else {
      _core.state = s.copyWith(
        currentPageIndex: index,
        previousPageIndex: prev,
        activeStroke: [],
        clearLasso: true,
        lassoPath: [],
        clearSelectedElement: true,
      );
    }
    _assets.ensureForCurrentWindow();
  }

  void nextPage({bool resetViewport = false}) {
    if (_core.state == null) return;
    final s = _core.state!;
    final filtered = s.filteredPageIndices;
    final pos = filtered.indexOf(s.currentPageIndex);
    if (pos >= 0 && pos + 1 < filtered.length) {
      goToPage(filtered[pos + 1], resetViewport: resetViewport);
    }
  }

  void prevPage({bool resetViewport = false}) {
    if (_core.state == null) return;
    final s = _core.state!;
    final filtered = s.filteredPageIndices;
    final pos = filtered.indexOf(s.currentPageIndex);
    if (pos > 0) {
      goToPage(filtered[pos - 1], resetViewport: resetViewport);
    }
  }

  void addPage() {
    if (_core.state == null) return;
    final s = _core.state!;
    const uuid = Uuid();
    final pageId = uuid.v4();
    final now = DateTime.now();
    final pageNum = s.pageCount + 1;
    final fileName = _nextPageFileName(s);

    final currentBg = s.currentPage?.layers.background;
    final bgType = currentBg?.type ?? 'blank';
    final lineSpacing = currentBg?.lineSpacing ?? 30.0;
    // Inherit the current page's size so scratch (infinite) notebooks get
    // another big sheet instead of a stray A4 page.
    final pageW = s.currentPage?.width ?? AppConfig.defaultPageWidth;
    final pageH = s.currentPage?.height ?? AppConfig.defaultPageHeight;

    final newPage = PageData(
      pageId: pageId, pageNumber: pageNum,
      width: pageW, height: pageH,
      layers: RenderingLayers(
        background: BackgroundLayer(type: bgType, lineSpacing: lineSpacing),
        content: const [],
      ),
      createdAt: now, modifiedAt: now,
    );

    // Auto-assign chapter if one is active
    final newEntry = PageEntry(
      pageId: pageId, pageNumber: pageNum, fileName: fileName,
      width: pageW, height: pageH,
      lastModified: now, chapterId: s.activeChapterId,
    );

    // Insert after current page position (not always at end)
    // Clamp: a stale currentPageIndex (remote merge) must not make insert() throw.
    final insertIndex = (s.currentPageIndex + 1).clamp(0, s.document.pages.length);
    final pageList = List<PageEntry>.from(s.document.pages)..insert(insertIndex, newEntry);
    // Renumber: inserting mid-document would otherwise leave pageNumber
    // out of sync with position (search results sort on it).
    for (int i = 0; i < pageList.length; i++) {
      pageList[i] = pageList[i].copyWith(pageNumber: i + 1);
    }

    final updatedDoc = DocumentStructure(
      notebookId: s.document.notebookId,
      formatVersion: s.document.formatVersion,
      pages: pageList,
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = newPage;

    _core.state = s.copyWith(
      metadata: s.metadata.copyWith(pageCount: pageNum, modifiedAt: now),
      document: updatedDoc,
      pages: updatedPages,
      currentPageIndex: insertIndex,
      zoom: 2.0,
      panOffset: _core.centeredPanOffset(2.0, newPage),
      isDirty: true,
    );
  }

  /// Insert a new blank page at a specific position (0-based index).
  void insertPageAt(int index) {
    if (_core.state == null) return;
    final s = _core.state!;
    const uuid = Uuid();
    final pageId = uuid.v4();
    final now = DateTime.now();
    final pageNum = s.pageCount + 1;
    final fileName = _nextPageFileName(s);

    final currentBg = s.currentPage?.layers.background;
    final bgType = currentBg?.type ?? 'blank';
    final lineSpacing = currentBg?.lineSpacing ?? 30.0;
    // Inherit the current page's size, like addPage.
    final pageW = s.currentPage?.width ?? AppConfig.defaultPageWidth;
    final pageH = s.currentPage?.height ?? AppConfig.defaultPageHeight;

    final newPage = PageData(
      pageId: pageId, pageNumber: pageNum,
      width: pageW, height: pageH,
      layers: RenderingLayers(
        background: BackgroundLayer(type: bgType, lineSpacing: lineSpacing),
        content: const [],
      ),
      createdAt: now, modifiedAt: now,
    );

    final insertIdx = index.clamp(0, s.document.pages.length);

    // Inherit chapter from the page before the insert position
    String? chapterId;
    if (insertIdx > 0) {
      chapterId = s.document.pages[insertIdx - 1].chapterId;
    } else if (s.document.pages.isNotEmpty) {
      chapterId = s.document.pages[0].chapterId;
    }

    final newEntry = PageEntry(
      pageId: pageId, pageNumber: pageNum, fileName: fileName,
      width: pageW, height: pageH,
      lastModified: now, chapterId: chapterId,
    );

    final pageList = List<PageEntry>.from(s.document.pages)..insert(insertIdx, newEntry);
    // Same renumber as addPage: keep pageNumber == position + 1.
    for (int i = 0; i < pageList.length; i++) {
      pageList[i] = pageList[i].copyWith(pageNumber: i + 1);
    }
    final updatedDoc = s.document.copyWith(pages: pageList);
    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = newPage;

    _core.state = s.copyWith(
      metadata: s.metadata.copyWith(pageCount: pageNum, modifiedAt: now),
      document: updatedDoc,
      pages: updatedPages,
      currentPageIndex: insertIdx,
      zoom: 2.0,
      panOffset: _core.centeredPanOffset(2.0, newPage),
      isDirty: true,
    );
  }

  /// Pastes [pages] into this notebook at [slot] (default: end of the last
  /// chapter) and returns the new page ids. Fresh ids and file names; the
  /// chapter is the slot's, never invented. [assets] are materialized here so
  /// the pasted pages do not point at ids that exist only in the source.
  List<String> pastePages({
    required List<PageData> pages,
    required List<PageEntry> entries,
    Map<String, Uint8List> assets = const {},
    PasteSlot? slot,
    List<String>? pageIds,
  }) {
    if (_core.state == null) return const [];
    final s = _core.state!;
    if (pages.isEmpty) return const [];

    var newAssetBytes = s.assetBytes;
    if (assets.isNotEmpty) {
      final merged = Map<String, Uint8List>.from(s.assetBytes);
      var changed = false;
      for (final entry in assets.entries) {
        if (!merged.containsKey(entry.key)) {
          merged[entry.key] = entry.value;
          (_core.assetsByLength[entry.value.length] ??= []).add(entry.key);
          _core.markAssetDirty(entry.key);
          changed = true;
        }
      }
      if (changed) newAssetBytes = merged;
    }

    final now = DateTime.now();
    final plan = planInsert(
      document: s.document,
      chapters: s.metadata.chapters,
      pages: [
        for (var i = 0; i < pages.length; i++) TrayPage(entries[i], pages[i]),
      ],
      slot: slot ?? appendSlot(s.metadata.chapters, s.document),
      now: now,
      pageIds: pageIds,
    );
    _core.state = s.copyWith(
      document: plan.document,
      pages: {...s.pages, ...plan.newPages},
      assetBytes: newAssetBytes,
      currentPageIndex: plan.insertIndex,
      metadata: s.metadata.copyWith(
        pageCount: plan.document.pages.length,
        modifiedAt: now,
      ),
      isDirty: true,
    );
    return plan.newPageIds;
  }

  /// Deletes the pages with these ids (those not here are ignored).
  void deletePagesById(Set<String> pageIds) {
    final s = _core.state;
    if (s == null) return;
    deletePages([
      for (var i = 0; i < s.document.pages.length; i++)
        if (pageIds.contains(s.document.pages[i].pageId)) i,
    ]);
  }

  /// Moves pages inside this notebook to [slot] (see [planMoveWithin]); the
  /// editor stays on the page it was showing.
  void movePagesToSlot(Set<String> pageIds, PasteSlot slot) {
    final s = _core.state;
    if (s == null) return;
    final doc = planMoveWithin(
        document: s.document,
        chapters: s.metadata.chapters,
        pageIds: pageIds,
        slot: slot);
    _applyStructure(s, doc);
  }

  /// Page order and chapters back to [before] (Undo of [movePagesToSlot]).
  void restorePageOrder(List<PageEntry> before) {
    final s = _core.state;
    if (s == null) return;
    _applyStructure(s, restoreOrder(s.document, before));
  }

  void _applyStructure(CanvasState s, DocumentStructure doc) {
    final cur = s.currentPageIndex < s.document.pages.length
        ? s.document.pages[s.currentPageIndex].pageId
        : null;
    final idx = doc.pages.indexWhere((e) => e.pageId == cur);
    _core.state = s.copyWith(
      document: doc,
      currentPageIndex: idx >= 0 ? idx : s.currentPageIndex,
      metadata: s.metadata.copyWith(modifiedAt: DateTime.now()),
      isDirty: true,
    );
  }

  void addChapter(String title) {
    if (_core.state == null) return;
    final s = _core.state!;
    final now = DateTime.now();
    final chapterId = const Uuid().v4();
    const uuid = Uuid();

    // Create a new blank page for the chapter instead of reassigning the current page
    final pageId = uuid.v4();
    final pageNum = s.pageCount + 1;
    final fileName = _nextPageFileName(s);

    final currentBg = s.currentPage?.layers.background;
    final bgType = currentBg?.type ?? 'blank';
    final lineSpacing = currentBg?.lineSpacing ?? 30.0;
    // Inherit the current page's size (scratch chapters get big sheets).
    final pageW = s.currentPage?.width ?? AppConfig.defaultPageWidth;
    final pageH = s.currentPage?.height ?? AppConfig.defaultPageHeight;

    final newPage = PageData(
      pageId: pageId, pageNumber: pageNum,
      width: pageW, height: pageH,
      layers: RenderingLayers(
        background: BackgroundLayer(type: bgType, lineSpacing: lineSpacing),
        content: const [],
      ),
      createdAt: now, modifiedAt: now,
    );

    final newEntry = PageEntry(
      pageId: pageId, pageNumber: pageNum, fileName: fileName,
      width: pageW, height: pageH,
      lastModified: now, chapterId: chapterId,
    );

    final chapter = Chapter(id: chapterId, title: title, pageIds: [pageId]);

    // Insert the new page after current position
    final insertIndex = (s.currentPageIndex + 1).clamp(0, s.document.pages.length);
    final pageList = List<PageEntry>.from(s.document.pages)..insert(insertIndex, newEntry);
    final updatedDoc = s.document.copyWith(pages: pageList);

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = newPage;

    _core.state = s.copyWith(
      metadata: s.metadata.copyWith(
        chapters: [...s.metadata.chapters, chapter],
        pageCount: pageNum,
        modifiedAt: now,
      ),
      document: updatedDoc,
      pages: updatedPages,
      currentPageIndex: insertIndex,
      activeChapterId: chapterId,
      zoom: 2.0,
      panOffset: _core.centeredPanOffset(2.0, newPage),
      isDirty: true,
    );
  }

  void renameChapter(String chapterId, String title) {
    if (_core.state == null) return;
    final s = _core.state!;
    final chapters = s.metadata.chapters.map((c) => c.id == chapterId ? c.copyWith(title: title) : c).toList();
    _core.state = s.copyWith(
      metadata: s.metadata.copyWith(chapters: chapters, modifiedAt: DateTime.now()),
      isDirty: true,
    );
  }

  void reorderChapters(int oldIndex, int newIndex) {
    if (_core.state == null) return;
    final s = _core.state!;
    final chapters = List<Chapter>.from(s.metadata.chapters);
    if (oldIndex < 0 || oldIndex >= chapters.length) return;
    if (newIndex < 0 || newIndex >= chapters.length) return;
    final item = chapters.removeAt(oldIndex);
    chapters.insert(newIndex, item);
    _core.state = s.copyWith(
      metadata: s.metadata.copyWith(chapters: chapters, modifiedAt: DateTime.now()),
      isDirty: true,
    );
  }

  void deleteChapter(String chapterId) {
    if (_core.state == null) return;
    final s = _core.state!;
    final chapters = s.metadata.chapters.where((c) => c.id != chapterId).toList();
    // Pages remain, but chapterId is cleared.
    final pages = s.document.pages.map((p) => p.chapterId == chapterId ? p.copyWith(chapterId: null) : p).toList();
    final document = s.document.copyWith(pages: pages);
    // If deleted chapter was the active filter, clear the filter
    final clearActiveChapter = s.activeChapterId == chapterId;
    _core.state = s.copyWith(
      metadata: s.metadata.copyWith(chapters: chapters, modifiedAt: DateTime.now()),
      document: document,
      isDirty: true,
      clearActiveChapter: clearActiveChapter,
    );
  }

  void assignPageToChapter(int pageIndex, String? chapterId) {
    if (_core.state == null) return;
    final s = _core.state!;
    if (pageIndex < 0 || pageIndex >= s.document.pages.length) return;
    final pages = List<PageEntry>.from(s.document.pages);
    pages[pageIndex] = pages[pageIndex].copyWith(chapterId: chapterId);
    final document = s.document.copyWith(pages: pages);
    _core.state = s.copyWith(document: document, isDirty: true);
  }

  void deletePage(int index) {
    if (_core.state == null || _core.state!.pageCount <= 1) return;
    final s = _core.state!;
    if (index < 0 || index >= s.document.pages.length) return;
    final entry = s.document.pages[index];
    final fileName = entry.fileName;
    final deletedPageId = entry.pageId;

    final newPages = List<PageEntry>.from(s.document.pages)..removeAt(index);
    // Renumber pages (preserve all fields including chapterId)
    for (int i = 0; i < newPages.length; i++) {
      newPages[i] = newPages[i].copyWith(pageNumber: i + 1);
    }

    final updatedDoc = DocumentStructure(
      notebookId: s.document.notebookId,
      formatVersion: s.document.formatVersion,
      pages: newPages,
    );

    // Purge the deleted page's pageId from every chapter.pageIds list so
    // we don't leave dead references in metadata.chapters. These were
    // never fatal (the document is authoritative for navigation) but
    // accumulated over time as garbage and confused the heal path on
    // other devices.
    final cleanedChapters = s.metadata.chapters
        .map((c) => c.copyWith(
              pageIds: c.pageIds.where((pid) => pid != deletedPageId).toList(),
            ))
        .toList();
    final cleanedMeta = s.metadata.copyWith(
      chapters: cleanedChapters,
      pageCount: newPages.length,
      modifiedAt: DateTime.now(),
    );

    final updatedPages = Map<String, PageData>.from(s.pages)..remove(fileName);
    // Keep the user on the page they were viewing (the page manager can
    // delete an arbitrary index, not just the current one): indices after
    // the deleted page shift down by one; if the current page itself was
    // deleted, stay at the same position (now the following page).
    int newIndex = s.currentPageIndex > index
        ? s.currentPageIndex - 1
        : s.currentPageIndex;
    if (newIndex >= newPages.length) newIndex = newPages.length - 1;
    if (newIndex < 0) newIndex = 0;

    // If a chapter filter is active, the naive "stay at same index" rule
    // can land on a page outside the active chapter (the page-indicator
    // then reads "— / N"). Snap to a page that still belongs to the
    // chapter — the previous one within it, or the first one — and only
    // fall back to the global index if the chapter became empty.
    String? newActiveChapterId = s.activeChapterId;
    if (newActiveChapterId != null) {
      final chapterPagesInUnfiltered = <int>[
        for (int i = 0; i < newPages.length; i++)
          if (newPages[i].chapterId == newActiveChapterId) i,
      ];
      if (chapterPagesInUnfiltered.isNotEmpty) {
        // Only re-snap when the adjusted index fell outside the chapter.
        // Prefer the closest earlier page within the chapter; otherwise
        // the first one. Keeps the user near where they were.
        if (!chapterPagesInUnfiltered.contains(newIndex)) {
          final prior = chapterPagesInUnfiltered
              .where((i) => i < newIndex)
              .toList();
          newIndex =
              prior.isNotEmpty ? prior.last : chapterPagesInUnfiltered.first;
        }
      } else {
        // Chapter has no pages left — drop the filter so the nav isn't
        // stuck showing "— / 0".
        newActiveChapterId = null;
      }
    }

    final clearChapter = newActiveChapterId == null && s.activeChapterId != null;
    _core.state = s.copyWith(
      document: updatedDoc,
      pages: updatedPages,
      currentPageIndex: newIndex,
      // Drop undo/redo entries for the deleted page: undo would put its
      // PageData back into the pages map without a document entry — an
      // orphan the heal then resurrects. Deletion is declared
      // non-undoable in the UI, so the stacks must agree.
      undoStack:
          s.undoStack.where((e) => e.pageFileName != fileName).toList(),
      redoStack:
          s.redoStack.where((e) => e.pageFileName != fileName).toList(),
      // Deletion shifts all subsequent indices; the previously-tracked
      // page index would now point to a different page. Drop it so the
      // bottom-strip "↺ previous" badge doesn't mislead the user.
      clearPreviousPage: true,
      activeChapterId: clearChapter ? null : newActiveChapterId,
      clearActiveChapter: clearChapter,
      metadata: cleanedMeta,
      isDirty: true,
    );
  }

  /// Delete multiple pages in a single state update.
  ///
  /// [docIndices] are absolute document indices (not filtered/visible indices).
  /// Must contain at least one index and must not delete ALL pages if only one
  /// page remains.
  void deletePages(List<int> docIndices) {
    if (_core.state == null) return;
    final s = _core.state!;
    if (docIndices.isEmpty) return;
    // Never delete the last page
    final effective = docIndices.where((i) => i >= 0 && i < s.document.pages.length).toList();
    if (effective.isEmpty) return;
    if (s.pageCount - effective.length < 1) {
      // Keep at least one page — remove excess from deletion list
      effective.sort();
      effective.removeLast(); // keep the last one
      if (effective.isEmpty) return;
    }

    final indicesToRemove = effective.toSet();
    final removedFileNames = indicesToRemove.map((i) => s.document.pages[i].fileName).toSet();
    final removedPageIds = indicesToRemove.map((i) => s.document.pages[i].pageId).toSet();

    final newPages = <PageEntry>[];
    for (int i = 0; i < s.document.pages.length; i++) {
      if (!indicesToRemove.contains(i)) {
        newPages.add(s.document.pages[i].copyWith(pageNumber: newPages.length + 1));
      }
    }

    final updatedDoc = DocumentStructure(
      notebookId: s.document.notebookId,
      formatVersion: s.document.formatVersion,
      pages: newPages,
    );
    final updatedPagesMap = Map<String, PageData>.from(s.pages)
      ..removeWhere((k, _) => removedFileNames.contains(k));

    // Keep the user on the page they were viewing: shift by the number of
    // deleted pages that preceded it, then clamp to the shrunken list.
    int newIndex = s.currentPageIndex -
        indicesToRemove.where((i) => i < s.currentPageIndex).length;
    if (newIndex >= newPages.length) newIndex = newPages.length - 1;
    if (newIndex < 0) newIndex = 0;

    String? newActiveChapterId = s.activeChapterId;
    if (newActiveChapterId != null) {
      final chapterPages = [
        for (int i = 0; i < newPages.length; i++)
          if (newPages[i].chapterId == newActiveChapterId) i,
      ];
      if (chapterPages.isEmpty) {
        newActiveChapterId = null;
      } else if (!chapterPages.contains(newIndex)) {
        newIndex = chapterPages.first;
      }
    }

    // Purge dead pageIds from every chapter (same reason as deletePage).
    final cleanedChapters = s.metadata.chapters
        .map((c) => c.copyWith(
              pageIds: c.pageIds.where((pid) => !removedPageIds.contains(pid)).toList(),
            ))
        .toList();

    final clearChapter = newActiveChapterId == null && s.activeChapterId != null;
    _core.state = s.copyWith(
      document: updatedDoc,
      pages: updatedPagesMap,
      currentPageIndex: newIndex,
      // Same as deletePage: purge undo/redo entries for deleted pages or
      // undo restores them as document-less orphans.
      undoStack: s.undoStack
          .where((e) => !removedFileNames.contains(e.pageFileName))
          .toList(),
      redoStack: s.redoStack
          .where((e) => !removedFileNames.contains(e.pageFileName))
          .toList(),
      // Bulk deletion invalidates any prior "previous page" reference.
      clearPreviousPage: true,
      activeChapterId: clearChapter ? null : newActiveChapterId,
      clearActiveChapter: clearChapter,
      metadata: s.metadata.copyWith(
        pageCount: newPages.length,
        modifiedAt: DateTime.now(),
        chapters: cleanedChapters,
      ),
      isDirty: true,
    );
  }

  /// Assign multiple pages to a chapter (or clear their chapter) in a single
  /// state update.
  void assignPagesToChapter(List<int> docIndices, String? chapterId) {
    if (_core.state == null) return;
    final s = _core.state!;
    if (docIndices.isEmpty) return;
    final indicesSet = docIndices.toSet();
    final pages = List<PageEntry>.from(s.document.pages);
    for (final i in indicesSet) {
      if (i >= 0 && i < pages.length) {
        pages[i] = pages[i].copyWith(chapterId: chapterId);
      }
    }
    _core.state = s.copyWith(
      document: s.document.copyWith(pages: pages),
      isDirty: true,
    );
  }

  void duplicatePage(int index) {
    if (_core.state == null) return;
    final s = _core.state!;
    if (index < 0 || index >= s.document.pages.length) return;
    final entry = s.document.pages[index];
    final sourcePage = s.pages[entry.fileName];
    if (sourcePage == null) return;

    const uuid = Uuid();
    final pageId = uuid.v4();
    final now = DateTime.now();
    final pageNum = s.pageCount + 1;
    final fileName = _nextPageFileName(s);

    final newPage = carryPdfTextLayer(sourcePage, PageData(
      pageId: pageId, pageNumber: pageNum,
      width: sourcePage.width, height: sourcePage.height,
      layers: RenderingLayers(
        background: sourcePage.layers.background,
        content: sourcePage.layers.content.map((e) {
          final newId = uuid.v4();
          return e.map(unknown: (u) => u.copyWith(id: newId),
            stroke: (e) => ContentElement.stroke(id: newId, zIndex: e.zIndex, data: e.data),
            text: (e) => ContentElement.text(id: newId, zIndex: e.zIndex, data: e.data),
            image: (e) => ContentElement.image(id: newId, zIndex: e.zIndex, data: e.data),
            shape: (e) => ContentElement.shape(id: newId, zIndex: e.zIndex, data: e.data),
            math: (e) => ContentElement.math(id: newId, zIndex: e.zIndex, data: e.data),
          );
        }).toList(),
      ),
      createdAt: now, modifiedAt: now,
    ));

    final newEntry = PageEntry(pageId: pageId, pageNumber: pageNum, fileName: fileName, lastModified: now, chapterId: entry.chapterId);

    // Land right after the source page, like addPage does.
    final pageList = List<PageEntry>.from(s.document.pages)
      ..insert(index + 1, newEntry);
    for (int i = 0; i < pageList.length; i++) {
      pageList[i] = pageList[i].copyWith(pageNumber: i + 1);
    }
    final updatedDoc = DocumentStructure(
      notebookId: s.document.notebookId,
      formatVersion: s.document.formatVersion,
      pages: pageList,
    );

    final updatedPages = Map<String, PageData>.from(s.pages);
    updatedPages[fileName] = newPage;

    _core.state = s.copyWith(
      document: updatedDoc,
      pages: updatedPages,
      currentPageIndex: index + 1,
      metadata: s.metadata.copyWith(pageCount: pageNum, modifiedAt: now),
      isDirty: true,
    );
  }

  /// Move a set of pages (possibly non-contiguous) so that the first moved
  /// page lands at final 1-based position [targetPosition]. Complements
  /// drag-and-drop, which is impractical for long-distance moves in big
  /// notebooks.
  void movePagesToPosition(List<int> docIndices, int targetPosition) {
    if (_core.state == null) return;
    final s = _core.state!;
    final validSet = docIndices
        .where((i) => i >= 0 && i < s.document.pages.length)
        .toSet();
    if (validSet.isEmpty) return;
    final valid = validSet.toList()..sort();

    final currentPageId = s.document.pages[
        s.currentPageIndex.clamp(0, s.document.pages.length - 1)].pageId;

    final moved = [for (final i in valid) s.document.pages[i]];
    final remaining = [
      for (int i = 0; i < s.document.pages.length; i++)
        if (!validSet.contains(i)) s.document.pages[i],
    ];
    // "Position N" means: after the move, the first moved page is page N.
    final insertAt = (targetPosition - 1).clamp(0, remaining.length);
    final pages = [...remaining]..insertAll(insertAt, moved);

    for (int i = 0; i < pages.length; i++) {
      pages[i] = pages[i].copyWith(pageNumber: i + 1);
    }

    final newCurrentIndex =
        pages.indexWhere((e) => e.pageId == currentPageId);

    _core.state = s.copyWith(
      document: DocumentStructure(
        notebookId: s.document.notebookId,
        formatVersion: s.document.formatVersion,
        pages: pages,
      ),
      currentPageIndex: newCurrentIndex < 0 ? s.currentPageIndex : newCurrentIndex,
      metadata: s.metadata.copyWith(modifiedAt: DateTime.now()),
      isDirty: true,
    );
  }
}
