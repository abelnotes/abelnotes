import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/import_service.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ImportedNotebookDraft draft() => ImportedNotebookDraft(
        title: 'Vault',
        tags: const ['uni'],
        chapters: [
          const ImportedChapterDraft(title: 'Cap 1', blocks: [
            TextBlock(
                spans: [TextSpanData(text: 'ciao', bold: true)],
                plain: 'ciao',
                kind: BlockKind.heading1),
            const ImageBlock(assetKey: 'k_a.png', pxW: 10, pxH: 10),
          ]),
          const ImportedChapterDraft(title: 'Cap 2 (vuoto)', blocks: []),
        ],
        assets: {
          'k_a.png': Uint8List.fromList([1, 2, 3]),
          'k_orfano.png': Uint8List.fromList([9]), // must be dropped
        },
      );

  test('assembleDraft: chapters/pages/assets coherent, orphan asset dropped',
      () async {
    final a = await ImportService.assembleDraft(draft(),
        resolvedTitle: 'Vault (importato)');
    expect(a, isNotNull);
    expect(a!.metadata.title, 'Vault (importato)');
    expect(a.metadata.paperType, 'blank');
    expect(a.metadata.tags, ['uni']);
    expect(a.metadata.chapters, hasLength(2));
    // Empty chapter still gets one blank page.
    expect(a.metadata.chapters[1].pageIds, hasLength(1));
    expect(a.metadata.pageCount, a.pages.length);
    // Every chapter pageId exists in the document and in the pages map.
    final entryIds = a.document.pages.map((p) => p.pageId).toSet();
    for (final ch in a.metadata.chapters) {
      for (final id in ch.pageIds) {
        expect(entryIds, contains(id));
      }
    }
    // Referenced-only assets survive.
    expect(a.assets.keys, ['k_a.png']);
    for (final page in a.pages.values) {
      for (final ref in page.assetReferences) {
        expect(a.assets, contains(ref));
      }
    }
  });

  test('package round-trip: buildPackageBytes → valid zip, pages parse back',
      () async {
    final a = await ImportService.assembleDraft(draft(),
        resolvedTitle: 'Vault');
    final bytes = SyncService.buildPackageBytes(
      metadata: a!.metadata,
      document: a.document,
      pages: a.pages,
      assets: a.assets,
    );
    SyncService.validateNcnoteArchive(bytes, context: 'test');
    final zip = ZipDecoder().decodeBytes(bytes);
    final names = zip.files.map((f) => f.name).toSet();
    expect(names, contains('metadata.json'));
    expect(names, contains('document.json'));
    var parsedPages = 0;
    for (final f in zip.files) {
      if (!f.name.startsWith('pages/')) continue;
      final pd = PageData.fromJson(
          jsonDecode(utf8.decode(f.content as List<int>)));
      expect(pd.width, 595.0);
      parsedPages++;
    }
    expect(parsedPages, a.pages.length);
    expect(names.any((n) => n.contains('k_a.png')), isTrue);
  });

  test('cancellation before packaging returns null', () async {
    final a = await ImportService.assembleDraft(draft(),
        resolvedTitle: 'X', isCancelled: () => true);
    expect(a, isNull);
  });
}
