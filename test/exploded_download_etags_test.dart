// Opening a notebook this device never held downloads it whole; the pull
// that follows used to fetch every page again because it had no baseline.
// The download now hands back the version of each page it received.

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/fake_remote_store.dart';

void main() {
  test('downloadExplodedFull reports the version of every page it got',
      () async {
    final store = FakeRemoteStore();
    final sync = SyncService(store);
    PageData page(int n) => PageData(
          pageId: 'p$n',
          pageNumber: n,
          width: 595,
          height: 842,
          layers: const RenderingLayers(
              background: BackgroundLayer(type: 'blank'), content: []),
          createdAt: DateTime.utc(2026),
          modifiedAt: DateTime.utc(2026),
        );
    final document = DocumentStructure(notebookId: 'nb', pages: [
      for (var n = 1; n <= 3; n++)
        PageEntry(pageId: 'p$n', pageNumber: n, fileName: 'page_00$n.json'),
    ]);
    await sync.syncDelta(
      notebookId: 'nb',
      metadata: NotebookMetadata(
        id: 'nb',
        title: 'T',
        createdAt: DateTime.utc(2026),
        modifiedAt: DateTime.utc(2026),
        pageCount: 3,
      ),
      document: document,
      dirtyPages: {for (var n = 1; n <= 3; n++) 'page_00$n.json': page(n)},
    );

    final r = await sync.downloadExplodedFull('nb');
    expect(r.pages.keys.toSet(), r.pageEtags.keys.toSet());
    expect(r.pageEtags, hasLength(3));
    for (final e in r.pageEtags.entries) {
      expect(e.value,
          await store.getVersion('/AbelNotes/_delta/nb/pages/${e.key}'));
    }
  });
}
