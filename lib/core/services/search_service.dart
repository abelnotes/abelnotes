import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/features/search/page_text.dart';
import 'package:abelnotes/features/search/search_index.dart';
import 'package:abelnotes/shared/utils/text_fold.dart';

/// Full-text search over every notebook, answered from the `page_text` index
/// (see lib/features/search/README.md). Handwriting is not searchable yet.
class SearchService {
  final FileService fileService;
  SearchService(this.fileService);

  late final SearchIndex index = SearchIndex(fileService.database);

  /// Splits a query into folded tokens, all of which a hit must contain.
  static List<String> tokens(String query) => [
        for (final t in foldForSearch(query.trim()).split(RegExp(r'\s+')))
          if (t.isNotEmpty) t,
      ];

  /// At most [limit] hits: notebooks whose title matches first, then newest
  /// notebook first, pages in order. With [titles], notebooks whose own title
  /// matches are listed too (kind [SearchHitKind.notebookTitle]).
  Future<List<SearchHit>> search(String query,
      {int limit = 100, bool titles = true}) async {
    final toks = tokens(query);
    if (toks.isEmpty) return const [];

    final titleMatched = <String>{};
    final hits = <SearchHit>[];
    for (final row in await fileService.getAllNotebookMeta()) {
      final title = row['title'] as String? ?? '';
      final f = foldForSearch(title);
      if (!toks.every(f.contains)) continue;
      final id = row['id'] as String;
      titleMatched.add(id);
      if (titles) {
        hits.add(SearchHit(
          notebookId: id,
          notebookTitle: title,
          pageNumber: 1,
          pageIndex: 0,
          pageId: '',
          chapterId: null,
          snippet: title,
          ranges: rangesIn(foldForSearch(title), toks),
          kind: SearchHitKind.notebookTitle,
        ));
      }
    }

    final matches =
        await index.match(toks, limit: limit, firstNotebooks: titleMatched);
    for (final m in matches) {
      if (hits.length >= limit) break;
      hits.add(_hitOf(m, toks));
    }
    return hits;
  }

  static SearchHit _hitOf(RawMatch m, List<String> toks) {
    final rawLines = m.raw.split('\n');
    final foldedLines = m.folded.split('\n');
    var line = foldedLines.indexWhere((l) => l.contains(toks.first));
    if (line < 0 || line >= rawLines.length) line = 0;
    var text = rawLines[line];
    var folded = foldForSearch(text);
    // Offsets only carry over when folding kept the length.
    if (folded.length != text.length) text = folded = foldedLines[line];

    final at = _anchor(folded, toks);
    final start = (at - _context).clamp(0, text.length);
    final end = (at + toks.first.length + _context).clamp(0, text.length);
    final lead = start > 0 ? '…' : '';
    final snippet =
        '$lead${text.substring(start, end)}${end < text.length ? '…' : ''}';
    final shown = '$lead${folded.substring(start, end)}';

    final kind = m.sources & TextSource.chapter != 0
        ? SearchHitKind.chapter
        : _kindOfLine(line, m.parts);
    return SearchHit(
      notebookId: m.notebookId,
      notebookTitle: m.notebookTitle,
      pageNumber: m.pageIndex + 1,
      pageIndex: m.pageIndex,
      pageId: m.pageId ?? '',
      chapterId: m.chapterId,
      snippet: snippet,
      ranges: rangesIn(shown, toks),
      kind: kind,
    );
  }

  static const _context = 40;

  /// Where to centre the snippet: the occurrence with the most distinct
  /// tokens around it (the first one when they are far apart).
  static int _anchor(String folded, List<String> toks) {
    var best = -1, bestCount = 0;
    for (final t in toks) {
      var from = 0;
      for (var n = 0; n < 5; n++) {
        final i = folded.indexOf(t, from);
        if (i < 0) break;
        from = i + 1;
        final lo = i - _context, hi = i + t.length + _context;
        var count = 0;
        for (final u in toks) {
          final j = folded.indexOf(u, lo < 0 ? 0 : lo);
          if (j >= 0 && j <= hi) count++;
        }
        if (count > bestCount || (count == bestCount && i < best)) {
          best = i;
          bestCount = count;
        }
      }
    }
    return best < 0 ? 0 : best;
  }

  static SearchHitKind _kindOfLine(int line, String parts) {
    final n = parts.split(',').map((e) => int.tryParse(e) ?? 0).toList();
    if (n.length < 3) return SearchHitKind.text;
    if (line < n[0]) return SearchHitKind.text;
    if (line < n[0] + n[1]) return SearchHitKind.math;
    if (line < n[0] + n[1] + n[2]) return SearchHitKind.pdf;
    return n.length > 3 ? SearchHitKind.ink : SearchHitKind.pdf;
  }

  /// Where the tokens occur in [folded], as (start, end) pairs in order.
  static List<(int, int)> rangesIn(String folded, List<String> toks) {
    final out = <(int, int)>[];
    for (final t in toks) {
      // Beside longer words a one-letter token ("e", "a") is a word of its
      // own, not every such letter in the snippet.
      final alone = t.length == 1 && toks.length > 1;
      var from = 0;
      while (true) {
        final i = folded.indexOf(t, from);
        if (i < 0) break;
        from = i + t.length;
        if (alone &&
            (_wordChar(folded, i - 1) || _wordChar(folded, i + t.length))) {
          continue;
        }
        out.add((i, i + t.length));
      }
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    // Overlaps (two tokens in one word) merge into one range.
    final merged = <(int, int)>[];
    for (final r in out) {
      if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
        if (r.$2 > merged.last.$2) {
          merged[merged.length - 1] = (merged.last.$1, r.$2);
        }
      } else {
        merged.add(r);
      }
    }
    return merged;
  }

  static final _word = RegExp(r'[\p{L}\p{N}]', unicode: true);

  static bool _wordChar(String s, int i) =>
      i >= 0 && i < s.length && _word.hasMatch(s[i]);
}

enum SearchHitKind { notebookTitle, chapter, text, math, pdf, ink }

class SearchHit {
  final String notebookId;
  final String notebookTitle;

  /// 1-based, as shown to the user.
  final int pageNumber;

  /// Position in the notebook's document, 0-based.
  final int pageIndex;
  final String pageId;
  final String? chapterId;
  final String snippet;

  /// Matched spans of [snippet] (start, end), for highlighting.
  final List<(int, int)> ranges;
  final SearchHitKind kind;

  const SearchHit({
    required this.notebookId,
    required this.notebookTitle,
    required this.pageNumber,
    required this.pageIndex,
    required this.pageId,
    required this.chapterId,
    required this.snippet,
    required this.ranges,
    required this.kind,
  });
}
