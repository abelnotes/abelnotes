import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

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

/// One recorded drawing op, in coordinates mapped to the PDF page (origin
/// top-left, points) by the affine [m] = [a, b, c, d, e, f].
sealed class PdfVecOp {
  final List<double> m;
  const PdfVecOp(this.m);
}

/// A filled or stroked path. [cmds] is flat: `0 x y` moveTo, `1 x y`
/// lineTo, `2 x1 y1 x2 y2 x3 y3` curveTo, `3` close.
class PdfVecPath extends PdfVecOp {
  final List<double> cmds;
  final int color; // ARGB
  final double? strokeWidth; // null = fill
  final int cap; // StrokeCap.index, same order as PdfLineCap
  final int join; // StrokeJoin.index, same order as PdfLineJoin
  final bool multiply;

  const PdfVecPath({
    required List<double> m,
    required this.cmds,
    required this.color,
    this.strokeWidth,
    this.cap = 0,
    this.join = 0,
    this.multiply = false,
  }) : super(m);
}

/// An encoded image (PNG/JPEG) drawn into the rect [x],[y],[w],[h].
class PdfVecImage extends PdfVecOp {
  final Uint8List bytes;
  final double x, y, w, h, alpha;

  const PdfVecImage({
    required List<double> m,
    required this.bytes,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.alpha = 1,
  }) : super(m);
}

/// Real text in a standard PDF font, baseline-left at [x],[y], stretched
/// horizontally by [hscale] to the width the canvas laid it out at.
class PdfVecText extends PdfVecOp {
  final String text; // already passed through [pdfSafeText]
  final double x, y, size, hscale;
  final int color; // ARGB
  final bool mono, bold, italic;

  const PdfVecText({
    required List<double> m,
    required this.text,
    required this.x,
    required this.y,
    required this.size,
    this.hscale = 1,
    required this.color,
    this.mono = false,
    this.bold = false,
    this.italic = false,
  }) : super(m);
}

/// Width of [text] at [size] in the standard font [buildPdfDocument] draws
/// a [PdfVecText] with. Plain metrics, no document needed.
double pdfTextWidth(String text, double size,
    {bool mono = false, bool bold = false, bool italic = false}) {
  final i = _fontIndex(mono, bold, italic);
  final font = _metricsFonts[i] ??= _standardFont(_metricsDoc, i);
  return font.stringMetrics(text).width * size;
}

int _fontIndex(bool mono, bool bold, bool italic) =>
    (mono ? 4 : 0) + (bold ? 2 : 0) + (italic ? 1 : 0);

PdfFont _standardFont(PdfDocument doc, int i) => switch (i) {
      0 => PdfFont.helvetica(doc),
      1 => PdfFont.helveticaOblique(doc),
      2 => PdfFont.helveticaBold(doc),
      3 => PdfFont.helveticaBoldOblique(doc),
      4 => PdfFont.courier(doc),
      5 => PdfFont.courierOblique(doc),
      6 => PdfFont.courierBold(doc),
      _ => PdfFont.courierBoldOblique(doc),
    };

final _metricsDoc = PdfDocument();
final _metricsFonts = <int, PdfFont>{};

/// A page ready for the PDF writer. Plain data so it crosses isolates.
/// Either [vector] (the page as drawing ops), [flatPng] (whole page
/// rasterised) or [baseImage] (the imported PDF page's own raster) plus an
/// optional transparent [overlayPng] of the annotations drawn on top.
class PdfExportPage {
  final double width;
  final double height;
  final List<PdfVecOp>? vector;
  final Uint8List? flatPng;
  final Uint8List? baseImage;
  final Uint8List? overlayPng;
  final List<PdfExportRun> runs;

  const PdfExportPage({
    required this.width,
    required this.height,
    this.vector,
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

/// Whether [pdfSafeText] keeps every character of [s] (standard PDF
/// fonts only cover Latin-1).
bool pdfCanEncode(String s) => s.runes.every((r) =>
    (r >= 0x20 && r < 0x7F) ||
    (r >= 0xA0 && r <= 0xFF) ||
    r == 0x09 ||
    r == 0x0A ||
    _punct.containsKey(String.fromCharCode(r)));

/// Embeds [bytes]. Opaque pages drop the alpha channel (no SMask) and
/// scan-like ones (dense PNG) are re-encoded as JPEG; overlays keep alpha.
/// [opaque] null = decide from the image: JPEGs go in untouched, PNGs
/// without a single translucent pixel are treated as opaque.
PdfImage _embed(PdfDocument doc, Uint8List bytes, {bool? opaque}) {
  if (opaque == null && bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return PdfImage.jpeg(doc, image: bytes);
  }
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return PdfImage.file(doc, bytes: bytes);
  opaque ??= !decoded.hasAlpha ||
      decoded.every((px) => px.a >= px.maxChannelValue);
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
  final images = Map<Uint8List, PdfImage>.identity(); // one XObject per asset
  final fonts = <int, PdfFont>{0: font}; // the rest made on first use
  for (final p in pages) {
    final page = PdfPage(doc, pageFormat: PdfPageFormat(p.width, p.height));
    final g = page.getGraphics();
    if (p.vector != null) {
      g.saveContext();
      g.setTransform(_affine([1, 0, 0, -1, 0, p.height])); // y down, like the canvas
      for (final op in p.vector!) {
        _drawOp(g, op, (b) => images[b] ??= _embed(doc, b),
            (i) => fonts[i] ??= _standardFont(doc, i));
      }
      g.restoreContext();
    }
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

Matrix4 _affine(List<double> m) => Matrix4(
    m[0], m[1], 0, 0, m[2], m[3], 0, 0, 0, 0, 1, 0, m[4], m[5], 0, 1);

void _drawOp(PdfGraphics g, PdfVecOp op, PdfImage Function(Uint8List) image,
    PdfFont Function(int) font) {
  g.saveContext();
  g.setTransform(_affine(op.m));
  switch (op) {
    case PdfVecPath():
      final alpha = ((op.color >> 24) & 0xFF) / 255;
      if (alpha < 1 || op.multiply) {
        g.setGraphicState(PdfGraphicState(
            fillOpacity: alpha,
            strokeOpacity: alpha,
            blendMode: op.multiply ? PdfBlendMode.multiply : null));
      }
      final c = op.cmds;
      for (var i = 0; i < c.length;) {
        switch (c[i].toInt()) {
          case 0:
            g.moveTo(c[i + 1], c[i + 2]);
            i += 3;
          case 1:
            g.lineTo(c[i + 1], c[i + 2]);
            i += 3;
          case 2:
            g.curveTo(c[i + 1], c[i + 2], c[i + 3], c[i + 4], c[i + 5], c[i + 6]);
            i += 7;
          default:
            g.closePath();
            i += 1;
        }
      }
      final color = PdfColor.fromInt(op.color | 0xFF000000);
      if (op.strokeWidth == null) {
        g.setFillColor(color);
        g.fillPath();
      } else {
        g.setStrokeColor(color);
        g.setLineWidth(op.strokeWidth!);
        g.setLineCap(PdfLineCap.values[op.cap]);
        g.setLineJoin(PdfLineJoin.values[op.join]);
        g.strokePath();
      }
    case PdfVecText():
      final alpha = ((op.color >> 24) & 0xFF) / 255;
      if (alpha < 1) g.setGraphicState(PdfGraphicState(fillOpacity: alpha));
      g.setFillColor(PdfColor.fromInt(op.color | 0xFF000000));
      // Text draws y-up; flip back at the baseline.
      g.setTransform(_affine([1, 0, 0, -1, op.x, op.y]));
      g.drawString(font(_fontIndex(op.mono, op.bold, op.italic)), op.size,
          op.text, 0, 0,
          scale: op.hscale);
    case PdfVecImage():
      if (op.alpha < 1) {
        g.setGraphicState(
            PdfGraphicState(fillOpacity: op.alpha, strokeOpacity: op.alpha));
      }
      // Images draw y-up; flip back inside the target rect.
      g.setTransform(_affine([1, 0, 0, -1, op.x, op.y + op.h]));
      g.drawImage(image(op.bytes), 0, 0, op.w, op.h);
  }
  g.restoreContext();
}

/// Smallest raster scale (px per point) that keeps [widthPt]x[heightPt]
/// within [maxPixels]. 4 px/pt ≈ 288 DPI, print sharp; 2 looked blurry zoomed.
double exportScaleFor(double widthPt, double heightPt,
    {double preferred = 4.0, double maxPixels = 12e6}) {
  final px = widthPt * heightPt * preferred * preferred;
  if (px <= maxPixels) return preferred;
  return preferred * math.sqrt(maxPixels / px);
}
