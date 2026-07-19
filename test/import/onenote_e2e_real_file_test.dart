import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/features/import/data/onenote_importer.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// End-to-end smoke test against real OneNote desktop exports. Skips
/// silently where no sample paths are configured, or where the files or
/// the native bridge are absent (CI, other machines) — the mapping itself
/// is covered by onenote_importer_test.dart with a synthetic tree.
///
/// Set ONENOTE_E2E_SAMPLES to a `:`-separated list of local .one file paths
/// to run this against real files, e.g.:
///   ONENOTE_E2E_SAMPLES=/path/a.one:/path/b.one flutter test \
///       test/import/onenote_e2e_real_file_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final samples = Platform.environment['ONENOTE_E2E_SAMPLES']
          ?.split(':')
          .where((p) => p.isNotEmpty)
          .toList() ??
      const <String>[];

  test('e2e: real desktop .one files parse with sane geometry', () async {
    if (!OneNoteImporter.isSupported) {
      markTestSkipped('bridge nativo assente');
      return;
    }
    var ran = false;
    for (final path in samples) {
      if (!File(path).existsSync()) continue;
      ran = true;
      final parsed = await OneNoteImporter().parse(path);
      expect(parsed.chapters, isNotEmpty, reason: path);
      for (final ch in parsed.chapters) {
        for (final page in ch.pages) {
          for (final el in page.elements) {
            el.maybeMap(
              text: (t) {
                expect(t.data.height, greaterThan(0));
                if (t.data.spans.isNotEmpty) {
                  expect(
                      t.data.spans.map((s) => s.text).join(), t.data.content);
                }
              },
              stroke: (s) {
                expect(s.data.points.length, greaterThanOrEqualTo(2));
                // Delta-decoding sanity: a handwriting stroke spans
                // centimetres, not metres — a broken decoder produces
                // kilometre-long straight lines.
                var minX = double.infinity, maxX = -double.infinity;
                var minY = double.infinity, maxY = -double.infinity;
                for (final p in s.data.points) {
                  minX = minX > p.x ? p.x : minX;
                  maxX = maxX < p.x ? p.x : maxX;
                  minY = minY > p.y ? p.y : minY;
                  maxY = maxY < p.y ? p.y : maxY;
                }
                expect(maxX - minX, lessThan(2000),
                    reason: 'stroke largo ${maxX - minX}pt in $path');
                expect(maxY - minY, lessThan(2000),
                    reason: 'stroke alto ${maxY - minY}pt in $path');
              },
              orElse: () {},
            );
          }
        }
      }
    }
    if (!ran) markTestSkipped('nessun file campione presente');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
