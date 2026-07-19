import 'package:flutter/foundation.dart';

import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Full-text search across all locally-cached notebooks.
///
/// Scans typed [TextElement] content and chapter titles. Handwritten strokes
/// are not OCR-ed — that would require an ML model that is out of scope for
/// this service. Users who want searchable handwriting can convert strokes to
/// [TextElement] inside the canvas.
class SearchService {
  final FileService fileService;
  final SyncService syncService;

  SearchService(this.fileService, this.syncService);

  /// Performs a case-insensitive substring search over all local notebooks.
  ///
  /// Returns at most [limit] hits, sorted by notebook title / page number.
  Future<List<SearchHit>> search(String query, {int limit = 200}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final rows = await fileService.getAllNotebookMeta();
    final hits = <SearchHit>[];

    for (final row in rows) {
      if (hits.length >= limit) break;
      final id = row['id'] as String;
      final title = row['title'] as String? ?? 'Senza titolo';

      final data = await fileService.readNotebookFile(id);
      if (data == null) continue;

      try {
        final parsed = syncService.parseNcnoteMetadata(data);

        // ── Notebook title match ──
        if (title.toLowerCase().contains(q)) {
          hits.add(SearchHit(
            notebookId: id,
            notebookTitle: title,
            pageNumber: 1,
            pageId: parsed.document.pages.isNotEmpty
                ? parsed.document.pages.first.pageId
                : '',
            snippet: title,
            kind: SearchHitKind.notebookTitle,
          ));
        }

        // ── Chapter title matches ──
        for (final ch in parsed.metadata.chapters) {
          if (ch.title.toLowerCase().contains(q)) {
            // Find the first page belonging to this chapter (if any).
            final pageEntry = parsed.document.pages.firstWhere(
              (p) => p.chapterId == ch.id,
              orElse: () => parsed.document.pages.isNotEmpty
                  ? parsed.document.pages.first
                  : const PageEntry(pageId: '', pageNumber: 1, fileName: ''),
            );
            hits.add(SearchHit(
              notebookId: id,
              notebookTitle: title,
              pageNumber: pageEntry.pageNumber,
              pageId: pageEntry.pageId,
              snippet: ch.title,
              kind: SearchHitKind.chapter,
            ));
          }
        }

        // ── Text element matches (may be heavy; skip on pathological match) ──
        final pages = syncService.extractAllPages(data);
        for (final pageEntry in parsed.document.pages) {
          if (hits.length >= limit) break;
          final page = pages[pageEntry.fileName];
          if (page == null) continue;
          for (final el in page.layers.content) {
            final text = el.maybeMap(
              text: (e) => e.data.content,
              // Index typeset math by its LaTeX source so equations are
              // searchable (e.g. searching "alpha" finds "\alpha").
              math: (e) => e.data.latex,
              orElse: () => null,
            );
            if (text == null || text.isEmpty) continue;
            final lower = text.toLowerCase();
            final idx = lower.indexOf(q);
            if (idx < 0) continue;
            final start = (idx - 24).clamp(0, text.length);
            final end = (idx + q.length + 24).clamp(0, text.length);
            final snippet = (start > 0 ? '…' : '') +
                text.substring(start, end) +
                (end < text.length ? '…' : '');
            hits.add(SearchHit(
              notebookId: id,
              notebookTitle: title,
              pageNumber: pageEntry.pageNumber,
              pageId: pageEntry.pageId,
              snippet: snippet.replaceAll('\n', ' '),
              kind: SearchHitKind.text,
            ));
            if (hits.length >= limit) break;
          }

          // ── Imported-PDF text layer (the embedded text we extracted at
          // import). Previously imported PDFs were pure rasters and thus
          // invisible to search; now their text is indexed too. ──
          final pdfLayer = page.pdfTextLayer;
          if (pdfLayer != null && hits.length < limit) {
            final text = pdfLayer.runs.map((r) => r.text).join(' ');
            final lower = text.toLowerCase();
            final idx = lower.indexOf(q);
            if (idx >= 0) {
              final start = (idx - 24).clamp(0, text.length);
              final end = (idx + q.length + 24).clamp(0, text.length);
              final snippet = (start > 0 ? '…' : '') +
                  text.substring(start, end) +
                  (end < text.length ? '…' : '');
              hits.add(SearchHit(
                notebookId: id,
                notebookTitle: title,
                pageNumber: pageEntry.pageNumber,
                pageId: pageEntry.pageId,
                snippet: snippet.replaceAll('\n', ' '),
                kind: SearchHitKind.text,
              ));
            }
          }
        }
      } catch (e) {
        debugPrint('[SearchService] Failed parsing $id: $e');
      }
    }

    hits.sort((a, b) {
      final t = a.notebookTitle.compareTo(b.notebookTitle);
      if (t != 0) return t;
      return a.pageNumber.compareTo(b.pageNumber);
    });
    return hits;
  }
}

enum SearchHitKind { notebookTitle, chapter, text }

class SearchHit {
  final String notebookId;
  final String notebookTitle;
  final int pageNumber;
  final String pageId;
  final String snippet;
  final SearchHitKind kind;

  const SearchHit({
    required this.notebookId,
    required this.notebookTitle,
    required this.pageNumber,
    required this.pageId,
    required this.snippet,
    required this.kind,
  });
}
