// Headless smoke check for the REAL native PDFium path the PDF importer relies
// on (render a page + extract embedded text with char boxes). Pure Dart, so it
// runs outside the Flutter engine / `flutter test`:
//
//   dart run tool/pdfrx_native_check.dart
//
// If `dart run` can't resolve the bundled native asset, point it at a built
// libpdfium explicitly:
//
//   PDFIUM_PATH=build/linux/x64/release/bundle/lib/libpdfium.so \
//     dart run tool/pdfrx_native_check.dart
//
// Exits 0 and prints PASS on success; throws (non-zero) otherwise. This is the
// check that catches native crashes the unit tests can't see.

import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> main() async {
  // Born-digital PDF with selectable text.
  final gen = pw.Document();
  gen.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    build: (ctx) => pw.Center(child: pw.Text('Selectable Hello 12345')),
  ));
  final bytes = Uint8List.fromList(await gen.save());

  // Reads PDFIUM_PATH from the environment if set.
  await pdfrxInitialize();

  final doc = await PdfDocument.openData(bytes);
  if (doc.pages.length != 1) {
    throw StateError('expected 1 page, got ${doc.pages.length}');
  }
  final page = doc.pages.first;

  // 1) Embedded text + per-character boxes.
  final text = await page.loadStructuredText();
  if (!text.fullText.contains('Selectable')) {
    throw StateError('embedded text not extracted: "${text.fullText}"');
  }
  final hasChars = text.fragments.any((f) => f.charRects.isNotEmpty);
  if (!hasChars) throw StateError('no per-character boxes');

  // 2) Rasterize the page (the importer's render call).
  final img = await page.render(
    fullWidth: page.width,
    fullHeight: page.height,
    backgroundColor: 0xFFFFFFFF,
  );
  if (img == null) throw StateError('render returned null');
  final w = img.width, h = img.height;
  if (w <= 0 || h <= 0 || img.pixels.lengthInBytes != w * h * 4) {
    throw StateError('bad raster: ${w}x$h, ${img.pixels.lengthInBytes} bytes');
  }
  img.dispose();
  await doc.dispose();

  stdout.writeln(
      'PASS: pages=1, text="${text.fullText.trim()}", raster=${w}x$h, charBoxes=$hasChars');
}
