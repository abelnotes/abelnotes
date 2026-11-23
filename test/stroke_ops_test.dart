// Stroke delta chunks, without a server: codec, diff, apply order and the
// folded-chunk marker of a compacted snapshot.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/notebook/page_codec.dart';
import 'package:abelnotes/core/sync/stroke_ops.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

ContentElement line(String id, double y, {double x = 10}) =>
    ContentElement.stroke(
      id: id,
      zIndex: 0,
      data: StrokeData(points: [
        StrokePoint(x: x, y: y, pressure: 0.62, timestamp: 1781849370321),
        StrokePoint(x: x + 90, y: y, pressure: 0.48, timestamp: 1781849370329),
      ]),
    );

PageData page(List<ContentElement> content, {String id = 'pg', double w = 595}) =>
    PageData(
      pageId: id,
      pageNumber: 1,
      width: w,
      height: 842,
      layers: RenderingLayers(content: content),
      modifiedAt: DateTime.utc(2026, 11, 19, 10),
    );

List<String> ids(PageData p) => [for (final e in p.layers.content) e.id];

/// A chunk through its bytes, as another device reads it.
OpChunk wire(OpChunk c) => decodeChunk(encodeChunk(c));

void main() {
  group('codec', () {
    test('a chunk round-trips its ops, elements, header and time', () {
      final base = page([line('a', 10), line('b', 20)]);
      final edited = page([line('a', 10, x: 30), line('c', 40)], w: 600)
          .copyWith(modifiedAt: DateTime.utc(2026, 11, 19, 11));
      final c = wire(diffPage(base, edited)!);
      expect([for (final o in c.ops) (o.kind, o.id)], [
        (OpKind.delete, 'b'),
        (OpKind.replace, 'a'),
        (OpKind.add, 'c'),
      ]);
      expect(c.header!.width, 600);
      expect(c.modifiedAt, DateTime.utc(2026, 11, 19, 11));
      expect(applyChunks(base, [c]), edited);
    });

    test('a cut-off or foreign file is damage, a newer version is not', () {
      final bytes = encodeChunk(diffPage(page([]), page([line('a', 1)]))!);
      expect(() => decodeChunk(bytes.sublist(0, bytes.length - 3)),
          throwsFormatException);
      expect(() => decodeChunk(utf8.encode('{"pageId":"x"}')),
          throwsFormatException);
      final newer = Uint8List.fromList(bytes)..[4] = 9;
      expect(() => decodeChunk(newer), throwsA(isA<ChunkTooNewException>()));
      expect('${const ChunkTooNewException(9)}', isNot(contains('FormatException')));
    });

    test('file names and versions round-trip, sorted by clock then device', () {
      const a = ChunkId('k3f9a2x1', 1781849370321);
      final name = chunkFileName('page_015_zy34.json', a);
      expect(name, isNot(endsWith('.json')));
      expect(parseChunkFileName(name)!.pageFile, 'page_015_zy34.json');
      expect(parseChunkFileName(name)!.id, a);
      expect(parseChunkFileName('page_001.json'), isNull);
      const b = ChunkId('aaaaaaaa', 1781849370321), c = ChunkId('zz', 5);
      final v = pageVersion('etag1', [a, b, c]);
      expect(splitPageVersion(v).snapshot, 'etag1');
      expect(splitPageVersion(v).chunks, [c, b, a]);
      expect(pageVersion('etag1', const []), 'etag1');
      expect(splitPageVersion('etag1').chunks, isEmpty);
    });
  });

  group('diff', () {
    test('an unchanged page gives an empty chunk', () {
      final p = page([line('a', 1)]);
      expect(diffPage(p, p)!.isEmpty, isTrue);
    });

    test('what the ops cannot say writes the page', () {
      final base = page([line('a', 1), line('b', 2)]);
      expect(diffPage(base, page([line('a', 1), line('a', 1)])), isNull,
          reason: 'duplicate id');
      expect(diffPage(base, page([line('a', 1)], id: 'other')), isNull);
    });

    test('list order is not content: painting sorts by zIndex', () {
      final base = page([line('a', 1), line('b', 2)]);
      expect(diffPage(base, page([line('b', 2), line('a', 1)]))!.isEmpty, isTrue);
      final below = diffPage(base, page([line('c', 0), line('a', 1), line('b', 2)]))!;
      expect([for (final o in below.ops) o.id], ['c']);
    });
  });

  group('apply', () {
    final base = page([line('a', 10), line('b', 20)]);

    test('two devices drawing offline: both adds apply, in clock order', () {
      final fromA = wire(diffPage(base, page([...base.layers.content, line('a1', 50)]))!);
      final fromB = wire(diffPage(base, page([...base.layers.content, line('b1', 60)]))!);
      expect(ids(applyChunks(base, [fromA, fromB])), ['a', 'b', 'a1', 'b1']);
      expect(ids(applyChunks(base, [fromB, fromA])), ['a', 'b', 'b1', 'a1']);
    });

    test('delete wins over a concurrent replace, in either order', () {
      final erase = wire(diffPage(base, page([line('b', 20)]))!);
      final move = wire(diffPage(base, page([line('a', 10, x: 99), line('b', 20)]))!);
      expect(ids(applyChunks(base, [erase, move])), ['b']);
      expect(ids(applyChunks(base, [move, erase])), ['b']);
    });

    test('delete of one element and a concurrent add both stand', () {
      final erase = wire(diffPage(base, page([line('b', 20)]))!);
      final add = wire(diffPage(base, page([...base.layers.content, line('n', 70)]))!);
      expect(ids(applyChunks(base, [add, erase])), ['b', 'n']);
    });

    test('two replaces of one element: the later chunk wins', () {
      final first = wire(diffPage(base, page([line('a', 10, x: 1), line('b', 20)]))!);
      final second = wire(diffPage(base, page([line('a', 10, x: 2), line('b', 20)]))!);
      final out = applyChunks(base, [first, second]).layers.content.first;
      expect((out as StrokeElement).data.points.first.x, 2);
    });

    test('undo of an erase brings the element back, at the top', () {
      final erased = page([line('b', 20)]);
      final erase = wire(diffPage(base, erased)!);
      final undo = wire(diffPage(erased, page([line('b', 20), line('a', 10)]))!);
      expect(ids(applyChunks(base, [erase, undo])), ['b', 'a']);
    });

    test('a replayed chunk changes nothing', () {
      final add = wire(diffPage(base, page([...base.layers.content, line('n', 70)]))!);
      final once = applyChunks(base, [add]);
      expect(applyChunks(once, [add]), once);
    });

    test('a chunk of another page id is skipped', () {
      final other = wire(diffPage(page([], id: 'old'), page([line('x', 1)], id: 'old'))!);
      expect(applyChunks(base, [other]), same(base));
    });
  });

  group('folded marker', () {
    const ids = [ChunkId('dev1', 10), ChunkId('dev2', 11)];
    final p = page([line('a', 10)]);

    for (final binary in [false, true]) {
      test('${binary ? 'binary' : 'JSON'} snapshot keeps its content', () {
        final bytes = binary
            ? binaryPageBytes(p)!
            : Uint8List.fromList(utf8.encode(compactPageJson(p)));
        final marked = withFoldedOps(bytes, ids);
        expect(foldedOpsOf(marked), ids.toSet());
        expect(foldedOpsOf(bytes), isEmpty);
        expect(decodePageBytes(marked), decodePageBytes(bytes));
      });
    }
  });
}
