// The decoded-image cache must evict the least recently used image, not the
// first one it finds.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/core/providers/canvas/asset_cache.dart';
import 'package:abelnotes/core/providers/canvas/canvas_core.dart';
import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

// 1x1 PNG.
final _png = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));

final _refProvider = Provider<Ref>((ref) => ref);

class _Core implements CanvasCore {
  _Core(this.ref);
  @override
  final Ref ref;
  @override
  CanvasState? state;
  @override
  bool get isDisposed => false;

  // The page-edit hooks are not used by the cache.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CanvasState _state() {
  final now = DateTime(2026);
  return CanvasState(
    metadata: NotebookMetadata(id: 'n', title: 't', createdAt: now, modifiedAt: now),
    document: const DocumentStructure(notebookId: 'n', pages: [
      PageEntry(pageId: 'p1', pageNumber: 1, fileName: 'p1.json'),
    ]),
    pages: const {
      'p1.json': PageData(
          pageId: 'p1',
          pageNumber: 1,
          width: 595,
          height: 842,
          layers: RenderingLayers(content: [])),
    },
    currentPageIndex: 0,
    currentTool: CanvasTool.pen,
    remotePath: '',
  );
}

void main() {
  testWidgets('eviction drops the least recently used image', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final core = _Core(c.read(_refProvider))..state = _state();
    final cache = AssetCache(core);
    addTearDown(cache.dispose);

    final total = AssetCache.imageCacheMax + 2;
    await tester.runAsync(() async {
      for (var i = 0; i < total; i++) {
        await cache.decodeAndCache('a$i', _png);
      }
    });
    expect(core.state!.imageCache.length, total);

    // Reading the oldest image makes it the freshest.
    cache.ensureAssetDecodedForThumbnail('a0');
    cache.evictDistantImages();

    final kept = core.state!.imageCache.keys.toSet();
    expect(kept.length, AssetCache.imageCacheMax);
    expect(kept.contains('a0'), isTrue, reason: 'touched entry must survive');
    expect(kept.contains('a1'), isFalse);
    expect(kept.contains('a2'), isFalse);
  });
}
