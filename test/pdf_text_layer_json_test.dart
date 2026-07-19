// Guards the persistence/sync path: a PageData carrying an extracted PDF text
// layer must survive toJson → fromJson byte-for-byte (it rides inside the
// per-page JSON written to the loose store and shipped by delta sync).

import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

void main() {
  test('PageData.pdfTextLayer round-trips through JSON', () {
    final page = PageData(
      pageId: 'p1',
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: const RenderingLayers(),
      pdfTextLayer: const PdfTextLayer(
        sourceAssetPath: 'uuid_doc_p1.png',
        source: 'embedded',
        runs: [
          PdfTextRun(
            text: 'Hello',
            x: 10,
            y: 20,
            width: 50,
            height: 12,
            chars: [
              PdfCharBox(x: 10, y: 20, width: 10, height: 12),
              PdfCharBox(x: 20, y: 20, width: 10, height: 12),
            ],
          ),
          PdfTextRun(text: 'World', x: 10, y: 40, width: 50, height: 12),
        ],
      ),
    );

    final restored = PageData.fromJson(page.toJson());
    expect(restored, page);
    expect(restored.pdfTextLayer, isNotNull);
    expect(restored.pdfTextLayer!.source, 'embedded');
    expect(restored.pdfTextLayer!.runs.length, 2);
    expect(restored.pdfTextLayer!.runs.first.chars.length, 2);
    expect(restored.pdfTextLayer!.runs[1].chars, isEmpty);
  });

  test('PageData without a text layer stays null (back-compat)', () {
    final page = PageData(
      pageId: 'p1',
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: const RenderingLayers(),
    );
    final restored = PageData.fromJson(page.toJson());
    expect(restored.pdfTextLayer, isNull);
  });
}
