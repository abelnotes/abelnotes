import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';

import 'package:abelnotes/shared/models/ncnote_format.dart';

/// One invisible text run placed over the page, in page-logical points
/// (origin top-left, same space as the notebook page).
class PdfExportRun {
  final String text;
  final double x;
  final double y;
  final double width;
  final double height;

  const PdfExportRun({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

/// A page ready for the PDF writer. Plain data so it crosses isolates.
/// Either [flatPng] (whole page rasterised) or [baseImage] (the imported
/// PDF page's own raster) plus an optional transparent [overlayPng] of the
/// annotations drawn on top.
class PdfExportPage {
  final double width;
  final double height;
  final Uint8List? flatPng;
  final Uint8List? baseImage;
  final Uint8List? overlayPng;
  final List<PdfExportRun> runs;

  const PdfExportPage({
    required this.width,
    required this.height,
    this.flatPng,
    this.baseImage,
    this.overlayPng,
    this.runs = const [],
  });
}

/// An imported PDF page seen as "background raster + annotations".
class PdfBackgroundSplit {
  final String assetPath;

  /// The page without the background raster and with a transparent paper,
  /// or null when nothing was drawn on top of it.
  final PageData? overlayPage;

  const PdfBackgroundSplit(this.assetPath, this.overlayPage);
}

ImageElement? _fullPageBackground(PageData page) {
  for (final el in page.layers.content) {
    if (el is! ImageElement || !el.data.locked) continue;
    final d = el.data;
    if (d.rotation == 0 &&
        d.x.abs() < 1.5 &&
        d.y.abs() < 1.5 &&
        (d.width - page.width).abs() < 1.5 &&
        (d.height - page.height).abs() < 1.5) {
      return el;
    }
  }
  return null;
}

/// True for an imported document page (a locked picture filling the page):
/// resizing it would crop that picture and break its PDF export.
bool hasFullPageBackground(PageData page) => _fullPageBackground(page) != null;

/// Finds a locked image covering the whole page (what PDF import creates).
/// Returns null for ordinary pages, partial images (older imports that were
/// letterboxed) and pages whose annotations include a multiply highlighter,
/// which only composites correctly on a flat render.
PdfBackgroundSplit? splitPdfBackground(PageData page) {
  final bg = _fullPageBackground(page);
  if (bg == null) return null;
  final rest = page.layers.content.where((e) => e.id != bg.id).toList();
  final hasHighlighter = rest.any((e) => e.map(unknown: (_) => false,
        stroke: (s) => s.data.isHighlighter,
        shape: (s) => s.data.isHighlighter,
        text: (_) => false,
        image: (_) => false,
        math: (_) => false,
      ));
  if (hasHighlighter) return null;
  if (rest.isEmpty) return PdfBackgroundSplit(bg.data.assetPath, null);
  return PdfBackgroundSplit(
    bg.data.assetPath,
    page.copyWith(
      layers: RenderingLayers(
        background: const BackgroundLayer(type: 'blank', color: 0x00FFFFFF),
        content: rest,
      ),
    ),
  );
}

/// Size of the exported PDF page: the source PDF page's own size in points
/// when the page is a full-bleed import whose shape still matches, else the
/// notebook page size.
({double width, double height}) pdfExportPageSize(PageData page) {
  final d = _fullPageBackground(page)?.data;
  final w = d?.pdfWidthPt;
  final h = d?.pdfHeightPt;
  if (w == null || h == null || w <= 0 || h <= 0 || !w.isFinite || !h.isFinite) {
    return (width: page.width, height: page.height);
  }
  final aspectRatio = (w / h) / (page.width / page.height);
  if ((aspectRatio - 1).abs() > 0.02) {
    return (width: page.width, height: page.height);
  }
  return (width: w, height: h);
}

/// Text runs to overlay invisibly, or empty when the page has no PDF text
/// layer or the raster it belongs to was deleted.
List<PdfExportRun> pdfExportRuns(PageData page) {
  final layer = page.pdfTextLayer;
  if (layer == null) return const [];
  final alive = page.layers.content.any(
      (e) => e is ImageElement && e.data.assetPath == layer.sourceAssetPath);
  if (!alive) return const [];
  final size = pdfExportPageSize(page);
  final kx = size.width / page.width;
  final ky = size.height / page.height;
  return [
    for (final r in layer.runs)
      PdfExportRun(
          text: r.text,
          x: r.x * kx,
          y: r.y * ky,
          width: r.width * kx,
          height: r.height * ky),
  ];
}

const _punct = {
  '‘': "'", '’': "'", '‚': ',', '‛': "'",
  '“': '"', '”': '"', '„': '"',
  '–': '-', '—': '-', '−': '-', '‐': '-', '‑': '-',
  '…': '...', '•': '*', ' ': ' ', ' ': ' ', ' ': ' ',
  'ﬀ': 'ff', 'ﬁ': 'fi', 'ﬂ': 'fl', 'ﬃ': 'ffi',
  'ﬄ': 'ffl',
};

/// Text the base-14 Helvetica can encode: Latin-1 plus common punctuation
/// mapped to ASCII. Anything else is dropped.
String pdfSafeText(String s) {
  final out = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final mapped = _punct[ch];
    if (mapped != null) {
      out.write(mapped);
    } else if ((r >= 0x20 && r < 0x7F) || (r >= 0xA0 && r <= 0xFF)) {
      out.write(ch);
    } else if (r == 0x09 || r == 0x0A) {
      out.write(' ');
    }
  }
  return out.toString();
}

/// Embeds [bytes]. Opaque pages drop the alpha channel (no SMask) and
/// scan-like ones (dense PNG) are re-encoded as JPEG; overlays keep alpha.
PdfImage _embed(PdfDocument doc, Uint8List bytes, {required bool opaque}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return PdfImage.file(doc, bytes: bytes);
  if (!opaque) return PdfImage.fromImage(doc, image: decoded);
  final rgb = decoded.numChannels == 3
      ? decoded
      : decoded.convert(numChannels: 3);
  final bytesPerPixel = bytes.length / (decoded.width * decoded.height);
  if (bytesPerPixel >= 0.25) {
    final jpg = Uint8List.fromList(img.encodeJpg(rgb, quality: 88));
    if (jpg.length < bytes.length * 0.7) {
      return PdfImage.jpeg(doc, image: jpg);
    }
  }
  return PdfImage.fromImage(doc, image: rgb);
}

/// Builds the PDF: every page keeps its own size, its raster (a re-encoded
/// JPEG for scan-like pages), and an invisible text layer so the exported
/// file stays searchable and selectable. Top-level for [compute].
Future<Uint8List> buildPdfDocument(List<PdfExportPage> pages) async {
  final doc = PdfDocument();
  final font = PdfFont.helvetica(doc);
  for (final p in pages) {
    final page = PdfPage(doc, pageFormat: PdfPageFormat(p.width, p.height));
    final g = page.getGraphics();
    final base = p.baseImage ?? p.flatPng;
    if (base != null) {
      g.drawImage(_embed(doc, base, opaque: true), 0, 0, p.width, p.height);
    }
    if (p.overlayPng != null) {
      g.drawImage(_embed(doc, p.overlayPng!, opaque: false), 0, 0, p.width,
          p.height);
    }
    for (final r in p.runs) {
      final text = pdfSafeText(r.text);
      if (text.trim().isEmpty || r.width <= 0 || r.height <= 0) continue;
      final size = (r.height * 0.8).clamp(1.0, 200.0);
      final natural = font.stringMetrics(text).width * size;
      if (natural <= 0) continue;
      final scale = (r.width / natural).clamp(0.05, 20.0);
      final baseline = p.height - (r.y + r.height * 0.8);
      g.drawString(font, size, text, r.x, baseline,
          scale: scale, mode: PdfTextRenderingMode.invisible);
    }
  }
  return Uint8List.fromList(await doc.save());
}

/// Smallest raster scale (px per point) that keeps [widthPt]x[heightPt]
/// within [maxPixels].
double exportScaleFor(double widthPt, double heightPt,
    {double preferred = 2.0, double maxPixels = 12e6}) {
  final px = widthPt * heightPt * preferred * preferred;
  if (px <= maxPixels) return preferred;
  return preferred * math.sqrt(maxPixels / px);
}
