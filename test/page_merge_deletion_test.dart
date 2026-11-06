// A stroke erased on one device and untouched on the other must stay erased
// after the 3-way merge, while strokes the other device added are kept.

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

ContentElement stroke(String id) => ContentElement.stroke(
      id: id,
      zIndex: 0,
      data: StrokeData(points: [const StrokePoint(x: 0, y: 0)]),
    );

PageData page(List<String> ids) => PageData(
      pageId: 'p',
      pageNumber: 1,
      width: 100,
      height: 100,
      layers: RenderingLayers(
        background: const BackgroundLayer(type: 'lined'),
        content: [for (final id in ids) stroke(id)],
      ),
    );

List<String> idsOf(PageData? p) => [
      for (final e in p!.layers.content) e.map(unknown: (u) => u.id,
          stroke: (s) => s.id,
          text: (t) => t.id,
          image: (i) => i.id,
          shape: (s) => s.id,
          math: (m) => m.id)
    ]..sort();

void main() {
  test('erased here, added there: erase stays, addition is kept', () {
    final merged = CanvasNotifier.mergePageElementsForTest(
      base: page(['s1', 's2']),
      local: page(['s2']), // s1 erased offline
      remote: page(['s1', 's2', 's3']), // other device added s3
    );
    expect(idsOf(merged), ['s2', 's3']);
  });

  test('erased there, added here: same result from the other side', () {
    final merged = CanvasNotifier.mergePageElementsForTest(
      base: page(['s1', 's2']),
      local: page(['s1', 's2', 's3']),
      remote: page(['s2']),
    );
    expect(idsOf(merged), ['s2', 's3']);
  });

  test('erased on both sides stays erased', () {
    final merged = CanvasNotifier.mergePageElementsForTest(
      base: page(['s1', 's2']),
      local: page(['s2']),
      remote: page(['s2', 's4']),
    );
    expect(idsOf(merged), ['s2', 's4']);
  });

  test('a resize on one side survives a merge with strokes from the other', () {
    final resized = page(['s1']).copyWith(width: 200, height: 150);
    final merged = CanvasNotifier.mergePageElementsForTest(
      base: page(['s1']),
      local: resized,
      remote: page(['s1', 's2']),
    );
    expect(idsOf(merged), ['s1', 's2']);
    expect([merged!.width, merged.height], [200, 150]);

    final mirrored = CanvasNotifier.mergePageElementsForTest(
      base: page(['s1']),
      local: page(['s1', 's2']),
      remote: resized,
    );
    expect([mirrored!.width, mirrored.height], [200, 150]);
  });

  test('resized differently on both sides is a conflict', () {
    final merged = CanvasNotifier.mergePageElementsForTest(
      base: page(['s1']),
      local: page(['s1']).copyWith(width: 200),
      remote: page(['s1', 's2']).copyWith(width: 300),
    );
    expect(merged, isNull);
  });
}
