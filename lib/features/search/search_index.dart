import 'package:sqflite/sqflite.dart';

import 'package:abelnotes/features/search/ink_text.dart';
import 'package:abelnotes/features/search/page_text.dart';

/// One indexed unit: a page, or a chapter title (`page_file` `#chapter:<id>`).
class PageRow {
  final String notebookId;
  final String pageFile;
  final String? pageId;
  final int pageIndex;
  final String? chapterId;
  final PageText text;
  final String stamp;
  const PageRow({
    required this.notebookId,
    required this.pageFile,
    required this.pageId,
    required this.pageIndex,
    required this.chapterId,
    required this.text,
    required this.stamp,
  });
}

/// What the index holds for a row, to decide whether it is current.
typedef StoredRow = ({String stamp, int pageIndex, String? chapterId});

/// A row that matched a query, with the notebook fields the results need.
class RawMatch {
  final String notebookId;
  final String notebookTitle;
  final String modifiedAt;
  final String pageFile;
  final String? pageId;
  final int pageIndex;
  final String? chapterId;
  final String folded;
  final String raw;
  final int sources;
  final String parts;
  const RawMatch({
    required this.notebookId,
    required this.notebookTitle,
    required this.modifiedAt,
    required this.pageFile,
    required this.pageId,
    required this.pageIndex,
    required this.chapterId,
    required this.folded,
    required this.raw,
    required this.sources,
    required this.parts,
  });
}

const chapterFilePrefix = '#chapter:';

/// The `page_text` table. Matching is a LIKE scan over folded text, kept in
/// [match] so a full-text engine can replace it without touching callers.
class SearchIndex {
  final Database db;
  SearchIndex(this.db);

  static Future<void> createTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS page_text (
        notebook_id TEXT NOT NULL,
        page_file TEXT NOT NULL,
        page_id TEXT,
        page_index INTEGER NOT NULL DEFAULT 0,
        chapter_id TEXT,
        folded TEXT NOT NULL,
        raw TEXT NOT NULL,
        sources INTEGER NOT NULL,
        parts TEXT NOT NULL DEFAULT '0,0,0',
        ink TEXT NOT NULL DEFAULT '',
        stamp TEXT NOT NULL,
        PRIMARY KEY (notebook_id, page_file)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS page_text_nb '
        'ON page_text(notebook_id)');
  }

  Future<Map<String, StoredRow>> stored(String notebookId) async {
    final rows = await db.query('page_text',
        columns: ['page_file', 'stamp', 'page_index', 'chapter_id'],
        where: 'notebook_id = ?',
        whereArgs: [notebookId]);
    return {
      for (final r in rows)
        r['page_file'] as String: (
          stamp: r['stamp'] as String,
          pageIndex: r['page_index'] as int,
          chapterId: r['chapter_id'] as String?,
        ),
    };
  }

  Future<List<String>> notebookIds() async {
    final rows =
        await db.rawQuery('SELECT DISTINCT notebook_id FROM page_text');
    return [for (final r in rows) r['notebook_id'] as String];
  }

  Future<int> rowCount() async =>
      Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM page_text')) ??
      0;

  /// Writes [upsert], drops [delete] and moves [moved] rows to their new
  /// position, all in one transaction.
  Future<void> apply(
    String notebookId, {
    Iterable<PageRow> upsert = const [],
    Iterable<String> delete = const [],
    Map<String, ({int pageIndex, String? chapterId, String? pageId})> moved =
        const {},
  }) async {
    await db.transaction((txn) async {
      final b = txn.batch();
      for (final f in delete) {
        b.delete('page_text',
            where: 'notebook_id = ? AND page_file = ?',
            whereArgs: [notebookId, f]);
      }
      for (final r in upsert) {
        b.insert(
            'page_text',
            {
              'notebook_id': r.notebookId,
              'page_file': r.pageFile,
              'page_id': r.pageId,
              'page_index': r.pageIndex,
              'chapter_id': r.chapterId,
              'folded': r.text.folded,
              'raw': r.text.raw,
              'sources': r.text.sources,
              'parts': r.text.parts,
              'ink': r.text.ink,
              'stamp': r.stamp,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final e in moved.entries) {
        b.rawUpdate(
            'UPDATE page_text SET page_index = ?, chapter_id = ?, page_id = ? '
            'WHERE notebook_id = ? AND page_file = ?',
            [
              e.value.pageIndex,
              e.value.chapterId,
              e.value.pageId,
              notebookId,
              e.key
            ]);
      }
      await b.commit(noResult: true);
    });
  }

  /// Recognised handwriting per page file of one notebook.
  Future<Map<String, List<InkLine>>> inkLines(String notebookId) async {
    final rows = await db.query('page_text',
        columns: ['page_file', 'ink'],
        where: "notebook_id = ? AND ink != ''",
        whereArgs: [notebookId]);
    return {
      for (final r in rows)
        r['page_file'] as String: InkLine.decodeAll(r['ink'] as String?),
    };
  }

  Future<void> deleteNotebook(String notebookId) =>
      db.delete('page_text', where: 'notebook_id = ?', whereArgs: [notebookId]);

  static String _like(String token) =>
      '%${token.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';

  /// Rows whose folded text contains every one of [foldedTokens]: those of
  /// [firstNotebooks] first, then newest notebook first, then page order.
  /// Rows of notebooks gone from the library are left out by the join.
  Future<List<RawMatch>> match(List<String> foldedTokens,
      {int limit = 100, Set<String> firstNotebooks = const {}}) async {
    if (foldedTokens.isEmpty) return const [];
    final where =
        List.filled(foldedTokens.length, r"p.folded LIKE ? ESCAPE '\'")
            .join(' AND ');
    final first = firstNotebooks.take(500).toList();
    final rank = first.isEmpty
        ? ''
        : 'p.notebook_id IN (${List.filled(first.length, '?').join(',')}) DESC, ';
    // Sort and limit on small keys first; the text columns are read for the
    // winners only.
    const order = 'ORDER BY';
    final rows = await db.rawQuery('''
      SELECT p.notebook_id, p.page_file, p.page_id, p.page_index, p.chapter_id,
             p.folded, p.raw, p.sources, p.parts,
             n.title, n.local_modified_at
      FROM page_text p JOIN notebooks n ON n.id = p.notebook_id
      WHERE p.rowid IN (
        SELECT p.rowid
        FROM page_text p JOIN notebooks n ON n.id = p.notebook_id
        WHERE $where
        $order ${rank}n.local_modified_at DESC, p.notebook_id, p.page_index
        LIMIT ?)
      $order ${rank}n.local_modified_at DESC, p.notebook_id, p.page_index
    ''', [for (final t in foldedTokens) _like(t), ...first, limit, ...first]);
    return [
      for (final r in rows)
        RawMatch(
          notebookId: r['notebook_id'] as String,
          notebookTitle: r['title'] as String? ?? '',
          modifiedAt: r['local_modified_at'] as String? ?? '',
          pageFile: r['page_file'] as String,
          pageId: r['page_id'] as String?,
          pageIndex: r['page_index'] as int,
          chapterId: r['chapter_id'] as String?,
          folded: r['folded'] as String,
          raw: r['raw'] as String,
          sources: r['sources'] as int,
          parts: r['parts'] as String,
        ),
    ];
  }
}
