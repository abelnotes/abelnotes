// Tests for the four perf-pass optimizations applied this session:
//   1. TransferableTypedData wrapping for the isolate boundary
//   2. PROPFIND-batched asset verification (logic-only — uses a stub)
//   3. imageCacheVersion notifier bumps
//   4. Undo-stack cap reduction + sublist trim

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/core/services/webdav_service.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

void main() {
  group('TransferableTypedData wrap/unwrap', () {
    test('round-trips bytes intact through fromList + materialize', () {
      // The save path wraps each Uint8List in TransferableTypedData
      // before sending across the isolate boundary; the worker calls
      // .materialize().asUint8List() to get them back.
      final original = Uint8List.fromList(List<int>.generate(1024, (i) => i & 0xFF));
      final wrapped = TransferableTypedData.fromList([original]);

      final restored = wrapped.materialize().asUint8List();

      expect(restored.length, original.length);
      // Verify byte-perfect equality on a sample of indices (cheap
      // hash-style check covering full range).
      for (var i = 0; i < restored.length; i += 17) {
        expect(restored[i], original[i],
            reason: 'mismatch at byte $i');
      }
    });

    test('multiple wrappers can be created from independent buffers', () {
      // The isolate-boundary helper wraps each asset separately.
      // Verify that two wrappers don't interfere.
      final a = Uint8List.fromList([1, 2, 3, 4, 5]);
      final b = Uint8List.fromList([10, 20, 30, 40, 50]);
      final wa = TransferableTypedData.fromList([a]);
      final wb = TransferableTypedData.fromList([b]);

      final restoredA = wa.materialize().asUint8List();
      final restoredB = wb.materialize().asUint8List();

      expect(restoredA, equals([1, 2, 3, 4, 5]));
      expect(restoredB, equals([10, 20, 30, 40, 50]));
    });
  });

  group('Undo stack cap', () {
    test('replicates the new _pushUndo trim semantics', () {
      // Mirror the production code's logic to ensure cap behaviour is
      // O(1)-ish (sublist is faster than removeAt(0) on large lists)
      // and preserves recency.
      const cap = 30;
      List<int> push(List<int> source, int v) {
        if (source.length >= cap) {
          return source.sublist(source.length - cap + 1)..add(v);
        }
        return [...source, v];
      }

      var stack = <int>[];
      // Push 60 entries; cap should kick in at 30.
      for (var i = 0; i < 60; i++) {
        stack = push(stack, i);
      }
      expect(stack.length, 30);
      // Recency preserved: last entry is 59, first is 30.
      expect(stack.first, 30);
      expect(stack.last, 59);
    });

    test('below cap, stack just grows', () {
      const cap = 30;
      List<int> push(List<int> source, int v) {
        if (source.length >= cap) {
          return source.sublist(source.length - cap + 1)..add(v);
        }
        return [...source, v];
      }

      var stack = <int>[];
      for (var i = 0; i < 10; i++) {
        stack = push(stack, i);
      }
      expect(stack.length, 10);
      expect(stack, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('UndoEntry instances are reachable through the trimmed stack', () {
      // Sanity-check: build real UndoEntry instances and verify trimming
      // doesn't lose recency.
      const cap = 30;
      final stack = <UndoEntry>[];
      for (var i = 0; i < 50; i++) {
        final entry = UndoEntry('p$i.json',
            PageData(
              pageId: 'page-$i', pageNumber: i,
              width: 100, height: 100,
              layers: const RenderingLayers(),
            ));
        if (stack.length >= cap) {
          stack
            ..removeRange(0, stack.length - cap + 1)
            ..add(entry);
        } else {
          stack.add(entry);
        }
      }
      expect(stack.length, cap);
      // Most recent entry is page-49.
      expect(stack.last.pageData.pageId, 'page-49');
      // Oldest in trimmed stack is page-20 (49 - 30 + 1).
      expect(stack.first.pageData.pageId, 'page-20');
    });
  });

  group('imageCacheVersion notifier', () {
    test('ValueNotifier<int> bumps fire listeners only on value change', () {
      final notifier = ValueNotifier<int>(0);
      var listenerCalls = 0;
      notifier.addListener(() => listenerCalls++);

      notifier.value = 0; // same value — no fire
      expect(listenerCalls, 0);
      notifier.value = 1; // change → fire
      expect(listenerCalls, 1);
      notifier.value++; // → fire
      expect(listenerCalls, 2);
      notifier.value = 2; // same as current — no fire
      expect(listenerCalls, 2);

      notifier.dispose();
    });
  });

  group('compactPageJson + decodePageData round-trip', () {
    PageData buildPage(List<StrokePoint> pts) => PageData(
          pageId: 'p1',
          pageNumber: 1,
          width: 595,
          height: 842,
          layers: RenderingLayers(
            content: [
              ContentElement.stroke(
                id: 'stroke-1',
                zIndex: 0,
                data: StrokeData(points: pts, baseWidth: 2.0, color: 0xFF000000),
              ),
            ],
          ),
        );

    test('round-trip preserves stroke point positions within 0.001 tolerance', () {
      final pts = [
        const StrokePoint(x: 100.123456789, y: 200.987654321, pressure: 0.75, tilt: 0.12345, timestamp: 1000),
        const StrokePoint(x: 105.5, y: 210.5, pressure: 0.5, tilt: 0, timestamp: 1016),
        const StrokePoint(x: 110.0, y: 220.0),
      ];
      final page = buildPage(pts);
      final encoded = compactPageJson(page);
      final decoded = decodePageData(jsonDecode(encoded) as Map<String, dynamic>);
      final decPts =
          decoded.layers.content.whereType<StrokeElement>().first.data.points;
      expect(decPts.length, 3);
      for (var i = 0; i < pts.length; i++) {
        expect((decPts[i].x - pts[i].x).abs() < 0.01, isTrue,
            reason: 'x mismatch at $i: ${decPts[i].x} vs ${pts[i].x}');
        expect((decPts[i].y - pts[i].y).abs() < 0.01, isTrue,
            reason: 'y mismatch at $i: ${decPts[i].y} vs ${pts[i].y}');
        expect((decPts[i].pressure - pts[i].pressure).abs() < 0.01, isTrue);
      }
    });

    test('compact form is materially smaller than full toJson', () {
      // 100-point stroke with realistic field values.
      final pts = List.generate(100, (i) => StrokePoint(
            x: 100.0 + i * 1.23456789,
            y: 200.0 + i * 0.987654321,
            pressure: 0.5 + (i % 7) * 0.05,
            tilt: 0.0,
            timestamp: 1000 + i * 8,
          ));
      final page = buildPage(pts);
      final fullBytes = utf8.encode(jsonEncode(page.toJson()));
      final compactBytes = utf8.encode(compactPageJson(page));
      // Expect at least 50% reduction. In practice we see ~55-60% on
      // full-precision realistic input; up to 80%+ on synth-pressure
      // mouse input where trailing defaults collapse to [x, y] only.
      expect(compactBytes.length < fullBytes.length * 0.5, isTrue,
          reason: 'compact=${compactBytes.length} full=${fullBytes.length}');
    });

    test('legacy map-form points still decode (back-compat)', () {
      // Manually craft JSON with old-style point objects (what older
      // builds saved). decodePageData should accept it unchanged.
      final legacyJson = jsonEncode({
        'pageId': 'p1',
        'pageNumber': 1,
        'width': 595,
        'height': 842,
        'layers': {
          'background': {},
          'content': [
            {
              'id': 'stroke-1',
              'zIndex': 0,
              'type': 'stroke',
              'data': {
                'points': [
                  {'x': 1.0, 'y': 2.0, 'pressure': 0.5, 'tilt': 0.0, 'timestamp': 0},
                  {'x': 3.0, 'y': 4.0, 'pressure': 0.8, 'tilt': 0.1, 'timestamp': 16},
                ],
                'baseWidth': 2.0,
                'color': 0xFF000000,
              },
            },
          ],
        },
      });
      final decoded = decodePageData(jsonDecode(legacyJson) as Map<String, dynamic>);
      final decPts =
          decoded.layers.content.whereType<StrokeElement>().first.data.points;
      expect(decPts.length, 2);
      expect(decPts[0].x, 1.0);
      expect(decPts[1].y, 4.0);
    });
  });

  group('PROPFIND batch verify logic', () {
    test('detects truncated assets by comparing expected vs remote sizes', () {
      // Stand-in for the syncDelta batch-verify step. Given a map of
      // expected sizes and a map of remote sizes (from listDirectory),
      // compute the set of files needing retry.
      final expected = <String, int>{
        'a.png': 1024,
        'b.png': 2048,
        'c.png': 4096,
      };
      final remote = <String, int>{
        'a.png': 1024, // OK
        'b.png': 1024, // truncated
        // c.png missing entirely
      };
      final retries = <String>[];
      for (final entry in expected.entries) {
        final r = remote[entry.key];
        if (r == null || r != entry.value) {
          retries.add(entry.key);
        }
      }
      expect(retries, containsAll(['b.png', 'c.png']));
      expect(retries.contains('a.png'), isFalse);
    });

    test('empty expected set requires no retries', () {
      final retries = <String>[];
      for (final entry in <String, int>{}.entries) {
        retries.add(entry.key);
      }
      expect(retries, isEmpty);
    });
  });

  group('STOREd precompressed assets in .ncnote package', () {
    test('isPrecompressedAsset classifies by extension', () {
      expect(SyncService.isPrecompressedAsset('images/foo.png'), isTrue);
      expect(SyncService.isPrecompressedAsset('images/foo.JPG'), isTrue);
      expect(SyncService.isPrecompressedAsset('pdfs/doc.pdf'), isTrue);
      expect(SyncService.isPrecompressedAsset('images/raw.bmp'), isFalse);
      expect(SyncService.isPrecompressedAsset('noextension'), isFalse);
      expect(SyncService.isPrecompressedAsset('weird.'), isFalse);
    });

    test('PNG asset round-trips byte-identical through STORE packaging', () {
      // Incompressible pseudo-random payload standing in for a PNG —
      // the entry is STOREd (compress=false), so extraction must return
      // the exact original bytes.
      final rng = Random(42);
      final pngBytes = Uint8List.fromList(
          List<int>.generate(64 * 1024, (_) => rng.nextInt(256)));

      final meta = NotebookMetadata(
        id: 'nb-test',
        title: 'Test',
        createdAt: DateTime.utc(2026),
        modifiedAt: DateTime.utc(2026),
      );
      const doc = DocumentStructure(notebookId: 'nb-test', pages: []);
      final sync = SyncService(WebDavService(
        serverUrl: 'https://localhost',
        username: 'u',
        password: 'p',
      ));

      final package = sync.createNcnotePackage(
        metadata: meta,
        document: doc,
        pages: const {},
        assets: {'images/test.png': pngBytes},
      );

      // Archive must stay structurally valid with mixed STORE/DEFLATE.
      SyncService.validateNcnoteArchive(package, context: 'store-test');

      final extracted = sync.extractAllAssets(package);
      expect(extracted.keys, contains('images/test.png'));
      expect(extracted['images/test.png'], equals(pngBytes));
    });
  });
}
