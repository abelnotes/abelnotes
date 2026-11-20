import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:abelnotes/features/canvas/data/pdf_export.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

Uint8List png(int w, int h) =>
    Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)));

PageData page(List<ContentElement> content, {PdfTextLayer? layer}) => PageData(
      pageId: 'p',
      pageNumber: 1,
      width: 400,
      height: 300,
      layers: RenderingLayers(content: content),
      pdfTextLayer: layer,
    );

ContentElement bg(
        {bool locked = true,
        double w = 400,
        double h = 300,
        double? srcW,
        double? srcH}) =>
    ContentElement.image(
        id: 'bg',
        zIndex: 0,
        data: ImageData(
            x: 0,
            y: 0,
            width: w,
            height: h,
            assetPath: 'a.png',
            locked: locked,
            pdfWidthPt: srcW,
            pdfHeightPt: srcH));

ContentElement ink({bool hl = false}) => ContentElement.stroke(
    id: 's',
    zIndex: 1,
    data: StrokeData(points: const [], isHighlighter: hl));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('split finds the full-page locked image, ignores partial ones', () {
    expect(splitPdfBackground(page([bg()]))!.overlayPage, isNull);
    final withInk = splitPdfBackground(page([bg(), ink()]))!;
    expect(withInk.assetPath, 'a.png');
    expect(withInk.overlayPage!.layers.content, hasLength(1));
    expect(splitPdfBackground(page([bg(w: 300)])), isNull);
    expect(splitPdfBackground(page([bg(locked: false)])), isNull);
    expect(splitPdfBackground(page([bg(), ink(hl: true)])), isNull);
  });

  test('runs need a live source image', () {
    const layer = PdfTextLayer(sourceAssetPath: 'a.png', runs: [
      PdfTextRun(text: 'hi', x: 1, y: 2, width: 30, height: 10),
    ]);
    expect(pdfExportRuns(page([bg()], layer: layer)), hasLength(1));
    expect(pdfExportRuns(page([], layer: layer)), isEmpty);
    expect(pdfExportRuns(page([bg()])), isEmpty);
  });

  test('export size follows the source PDF page when the shape matches', () {
    expect(pdfExportPageSize(page([bg(srcW: 200, srcH: 150)])),
        (width: 200.0, height: 150.0));
    // Older imports carry no source size: keep the notebook geometry.
    expect(pdfExportPageSize(page([bg()])), (width: 400.0, height: 300.0));
    // Page reshaped after import: the stored size no longer applies.
    expect(pdfExportPageSize(page([bg(srcW: 100, srcH: 300)])),
        (width: 400.0, height: 300.0));
  });

  test('runs are scaled with the exported page', () {
    const layer = PdfTextLayer(sourceAssetPath: 'a.png', runs: [
      PdfTextRun(text: 'hi', x: 40, y: 30, width: 80, height: 20),
    ]);
    final r = pdfExportRuns(
        page([bg(srcW: 200, srcH: 150)], layer: layer)).single;
    expect((r.x, r.y, r.width, r.height), (20.0, 15.0, 40.0, 10.0));
  });

  test('text is made encodable', () {
    expect(pdfSafeText('“caffè” – ﬁne 日本'), '"caffè" - fine ');
  });

  test('document keeps page sizes and a searchable text layer', () async {
    final bytes = await buildPdfDocument([
      PdfExportPage(
        width: 400,
        height: 300,
        flatPng: png(40, 30),
        runs: const [
          PdfExportRun(text: 'hello searchable world', x: 20, y: 20, width: 200, height: 14),
          PdfExportRun(text: '日本語のノート ABC 123', x: 20, y: 40, width: 145, height: 16),
        ],
      ),
      PdfExportPage(
        width: 200,
        height: 500,
        baseImage: png(20, 50),
        vector: const [
          PdfVecSearchText(
            m: [1, 0, 0, 1, 0, 0],
            text: '数式を記録する',
            x: 20, y: 55, size: 14, width: 105,
          ),
        ],
      ),
    ]);
    expect(String.fromCharCodes(bytes), contains('/NotoSansJP-Regular'));
    if (Process.runSync('which', ['pdftotext']).exitCode != 0) return;
    final f = File('${Directory.systemTemp.path}/abel_export_test.pdf')
      ..writeAsBytesSync(bytes);
    addTearDown(f.deleteSync);
    final info = Process.runSync('pdfinfo', ['-f', '1', '-l', '2', f.path])
        .stdout as String;
    expect(info, contains('Page    1 size:  400 x 300 pts'));
    expect(info, contains('Page    2 size:  200 x 500 pts'));
    final txt = Process.runSync('pdftotext', [f.path, '-']).stdout as String;
    expect(txt, contains('hello searchable world'));
    expect(txt, contains('日本語のノート ABC 123'));
    expect(txt, contains('数式を記録する'));
  });
}
