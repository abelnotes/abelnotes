import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final meta = NotebookMetadata(
    id: 'nb',
    title: 'T',
    createdAt: DateTime.utc(2020),
    modifiedAt: DateTime.utc(2020),
    chapters: const [
      Chapter(id: 'empty', title: 'E'),
      Chapter(id: 'a', title: 'A'),
      Chapter(id: 'b', title: 'B'),
    ],
  );
  final doc = DocumentStructure(notebookId: 'nb', pages: [
    for (var i = 0; i < 5; i++)
      PageEntry(
          pageId: 'p$i',
          pageNumber: i,
          fileName: 'page_$i.json',
          chapterId: i < 2 ? 'a' : 'b'),
  ]);
  final start = CanvasNotifier.startPosition;

  test('a saved page inside its saved chapter is kept', () {
    expect(start(meta, doc, 'b', 3), (chapterId: 'b', pageIndex: 3));
  });
  test('a saved page of another chapter goes to that chapter\'s first page', () {
    expect(start(meta, doc, 'b', 1), (chapterId: 'b', pageIndex: 2));
    expect(start(meta, doc, 'a', 99), (chapterId: 'a', pageIndex: 0));
  });
  test('an unknown or empty chapter falls back to the first one with pages', () {
    expect(start(meta, doc, 'gone', 3), (chapterId: 'a', pageIndex: 0));
    expect(start(meta, doc, 'empty', 0), (chapterId: 'a', pageIndex: 0));
    expect(start(meta, doc, null, 4), (chapterId: 'a', pageIndex: 0));
  });
  test('no chapter with pages: all pages, first page', () {
    expect(start(meta.copyWith(chapters: const []), doc, null, 3),
        (chapterId: null, pageIndex: 0));
  });
}
