import 'dart:typed_data';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/features/import/data/block_paginator.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/onenote_importer.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:uuid/uuid.dart';

/// Registration back-end shared by every notebook importer (.ncnote archives
/// and the foreign-format adapters). UI-free: title-collision naming and
/// toasts stay with the caller.
class ImportService {
  final FileService fileService;

  ImportService(this.fileService);

  /// Remote path a freshly imported notebook will sync to. Same sanitising
  /// rules the .ncnote import has always used.
  static String remotePathFor(String title, String id) {
    final safeName = title
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
    return '${AppConfig.defaultRemotePath}${safeName}_$id${AppConfig.fileExtension}';
  }

  /// Zip-encodes the notebook off the UI thread, writes it to local storage
  /// and registers the library row with `syncStatus: 'modified'` so the next
  /// background sync uploads it. [metadata] must already carry its final
  /// id/title. Returns the package size in bytes.
  Future<int> registerNotebook({
    required NotebookMetadata metadata,
    required DocumentStructure document,
    required Map<String, PageData> pages,
    Map<String, Uint8List>? assets,
    List<Map<String, dynamic>>? symbolLibraries,
  }) async {
    final bytes = await SyncService.buildPackageBytesIsolated(
      metadata: metadata,
      document: document,
      pages: pages,
      assets: (assets != null && assets.isNotEmpty) ? assets : null,
      symbolLibraries: (symbolLibraries != null && symbolLibraries.isNotEmpty)
          ? symbolLibraries
          : null,
    );

    await fileService.saveNotebookFile(metadata.id, bytes);
    await fileService.upsertNotebookMeta(
      id: metadata.id,
      title: metadata.title,
      remotePath: remotePathFor(metadata.title, metadata.id),
      localModifiedAt: metadata.modifiedAt,
      // 'modified' so the next background sync uploads it.
      syncStatus: 'modified',
      fileSize: bytes.length,
      coverColor: metadata.coverColor,
      paperType: metadata.paperType,
      pageCount: metadata.pageCount,
      createdAt: metadata.createdAt,
    );
    return bytes.length;
  }

  /// Paginate a parsed [ImportedNotebookDraft] into A4 pages, assemble the
  /// notebook and register it. Runs the paginator chapter by chapter with
  /// progress callbacks; returns null when cancelled before packaging (no
  /// residue is left on disk in that case).
  Future<ImportReport?> importDraft(
    ImportedNotebookDraft draft, {
    required String resolvedTitle,
    void Function(ImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final assembled = await assembleDraft(
      draft,
      resolvedTitle: resolvedTitle,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (assembled == null) return null;

    onProgress?.call(const ImportProgress(phase: ImportPhase.packaging));
    if (isCancelled?.call() ?? false) return null;
    await registerNotebook(
      metadata: assembled.metadata,
      document: assembled.document,
      pages: assembled.pages,
      assets: assembled.assets,
    );
    onProgress?.call(const ImportProgress(phase: ImportPhase.done));

    return ImportReport(
      notebookTitle: resolvedTitle,
      notebookId: assembled.metadata.id,
      chapterCount: assembled.metadata.chapters.length,
      pageCount: assembled.pages.length,
      issues: draft.issues,
    );
  }

  /// Registers a parsed OneNote file as an infinite-canvas notebook (one
  /// chapter per section, elements at their original absolute positions —
  /// no A4 pagination). Returns null when cancelled before packaging.
  Future<ImportReport?> importOneNote(
    OneNoteParsed parsed, {
    required String resolvedTitle,
    void Function(ImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    const uuid = Uuid();
    final now = DateTime.now();
    final chapters = <Chapter>[];
    final pageEntries = <PageEntry>[];
    final pages = <String, PageData>{};
    var pageNumber = 1;

    for (final ch in parsed.chapters) {
      final chapterId = uuid.v4();
      final pageIds = <String>[];
      for (final draft in ch.pages) {
        final pageId = uuid.v4();
        final fileName = 'page_${pageNumber.toString().padLeft(3, '0')}.json';
        pageIds.add(pageId);
        pageEntries.add(PageEntry(
          pageId: pageId,
          pageNumber: pageNumber,
          fileName: fileName,
          width: AppConfig.scratchPageSize,
          height: AppConfig.scratchPageSize,
          chapterId: chapterId,
          lastModified: now,
        ));
        pages[fileName] = PageData(
          pageId: pageId,
          pageNumber: pageNumber,
          width: AppConfig.scratchPageSize,
          height: AppConfig.scratchPageSize,
          layers: RenderingLayers(
            // Same background native scratch notebooks are created with.
            background: const BackgroundLayer(type: 'dotted'),
            content: draft.elements,
          ),
          assetReferences: draft.assetRefs.toList(),
          createdAt: now,
          modifiedAt: now,
        );
        pageNumber++;
      }
      chapters.add(Chapter(id: chapterId, title: ch.title, pageIds: pageIds));
    }

    final referenced = <String>{
      for (final p in pages.values) ...p.assetReferences,
    };
    final assets = <String, Uint8List>{
      for (final e in parsed.assets.entries)
        if (referenced.contains(e.key)) e.key: e.value,
    };

    final notebookId = uuid.v4();
    final metadata = NotebookMetadata(
      id: notebookId,
      title: resolvedTitle,
      createdAt: now,
      modifiedAt: now,
      paperType: AppConfig.infinitePaperType,
      pageCount: pages.length,
      chapters: chapters,
    );
    final document =
        DocumentStructure(notebookId: notebookId, pages: pageEntries);

    onProgress?.call(const ImportProgress(phase: ImportPhase.packaging));
    if (isCancelled?.call() ?? false) return null;
    await registerNotebook(
      metadata: metadata,
      document: document,
      pages: pages,
      assets: assets,
    );
    onProgress?.call(const ImportProgress(phase: ImportPhase.done));

    return ImportReport(
      notebookTitle: resolvedTitle,
      notebookId: notebookId,
      chapterCount: chapters.length,
      pageCount: pages.length,
      issues: parsed.issues,
    );
  }

  /// Pure assembly step (no I/O): paginates every chapter and builds the
  /// ncnote structures. Split from [importDraft] so it can be tested without
  /// a [FileService]. Returns null when cancelled mid-way.
  static Future<AssembledNotebook?> assembleDraft(
    ImportedNotebookDraft draft, {
    required String resolvedTitle,
    void Function(ImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    const uuid = Uuid();
    final paginator = BlockPaginator();
    final now = DateTime.now();

    final chapters = <Chapter>[];
    final pageEntries = <PageEntry>[];
    final pages = <String, PageData>{};
    var pageNumber = 1;

    for (var i = 0; i < draft.chapters.length; i++) {
      final ch = draft.chapters[i];
      onProgress?.call(ImportProgress(
        phase: ImportPhase.paginating,
        current: i,
        total: draft.chapters.length,
        detail: ch.title,
      ));
      final draftPages =
          await paginator.paginate(ch.blocks, isCancelled: isCancelled);
      if (isCancelled?.call() ?? false) return null;

      final chapterId = uuid.v4();
      final pageIds = <String>[];
      for (final dp in draftPages) {
        final pageId = uuid.v4();
        final fileName =
            'page_${pageNumber.toString().padLeft(3, '0')}.json';
        pageIds.add(pageId);
        pageEntries.add(PageEntry(
          pageId: pageId,
          pageNumber: pageNumber,
          fileName: fileName,
          chapterId: chapterId,
          lastModified: now,
        ));
        pages[fileName] = PageData(
          pageId: pageId,
          pageNumber: pageNumber,
          width: BlockPaginator.pageW,
          height: BlockPaginator.pageH,
          layers: RenderingLayers(
            background: const BackgroundLayer(type: 'blank'),
            content: dp.elements,
          ),
          assetReferences: dp.assetRefs.toList(),
          createdAt: now,
          modifiedAt: now,
        );
        pageNumber++;
      }
      chapters.add(Chapter(id: chapterId, title: ch.title, pageIds: pageIds));
    }

    // Keep only the assets some page actually references (adapters may have
    // collected more than what survived parsing).
    final referenced = <String>{
      for (final p in pages.values) ...p.assetReferences,
    };
    final assets = <String, Uint8List>{
      for (final e in draft.assets.entries)
        if (referenced.contains(e.key)) e.key: e.value,
    };

    final notebookId = uuid.v4();
    final metadata = NotebookMetadata(
      id: notebookId,
      title: resolvedTitle,
      createdAt: now,
      modifiedAt: now,
      paperType: 'blank',
      pageCount: pages.length,
      tags: draft.tags,
      chapters: chapters,
    );
    final document = DocumentStructure(
      notebookId: notebookId,
      pages: pageEntries,
    );

    return AssembledNotebook(
      metadata: metadata,
      document: document,
      pages: pages,
      assets: assets,
    );
  }
}

/// Output of [ImportService.assembleDraft], ready for packaging.
class AssembledNotebook {
  final NotebookMetadata metadata;
  final DocumentStructure document;
  final Map<String, PageData> pages;
  final Map<String, Uint8List> assets;

  const AssembledNotebook({
    required this.metadata,
    required this.document,
    required this.pages,
    required this.assets,
  });
}
