// pdf_text_extractor.dart
//
// Pulls the *embedded* text layer out of a PDF page and maps it into the
// note's page-logical coordinate space so it can be overlaid (invisible) on
// the rasterized page image for selection + search.
//
// This is NOT OCR: it reads the real glyph positions PDFium already knows, so
// the result is pixel-accurate for any born-digital PDF. Scanned/image-only
// pages simply yield no text (an empty/garbage layer), and the caller treats
// that as "nothing to overlay".
//
// Coordinate pipeline (per character / fragment):
//   PDF page space (origin bottom-left, points, UNrotated)
//     → pdfrx `PdfRect.toRect(page:)`  ⇒ Flutter rect in the DISPLAYED
//       (rotation-applied) page, origin top-left, still in points
//     → normalise by the displayed page size (dispW × dispH)
//     → scale onto the placed raster image rect (imageOffset + imgW × imgH)
//   ⇒ page-logical points, the same space as everything in PageData.
//
// The displayed page size matches the orientation pdfrx's `page.render`
// produced (it renders the page rotation-applied), and the raster was scaled
// uniformly to `imgW × imgH` and centred at `imageOffset` by the importer — so
// the same normalisation lands the text exactly on top of the pixels.

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:abelnotes/shared/models/ncnote_format.dart';

/// How a raster image of a PDF page was placed on the note page, in
/// page-logical points. Mirrors the centring math in the PDF import loop.
class PdfImagePlacement {
  const PdfImagePlacement({
    required this.offset,
    required this.width,
    required this.height,
  });

  /// Top-left of the image on the note page (page-logical points).
  final Offset offset;

  /// Rendered size of the image on the note page (page-logical points).
  final double width;
  final double height;
}

class PdfTextExtractor {
  /// Extract the text layer for a single PDF page.
  ///
  /// [pageIndex] is 0-based. Returns null when the page carries no usable
  /// embedded text (scanned/image PDFs), so the caller can skip attaching a
  /// layer. Best-effort: any failure is swallowed and returns null — text
  /// extraction must never break the import.
  static Future<PdfTextLayer?> extractPageLayer({
    required PdfDocument doc,
    required int pageIndex,
    required String sourceAssetPath,
    required PdfImagePlacement placement,
  }) async {
    if (pageIndex < 0 || pageIndex >= doc.pages.length) return null;
    try {
      final page = doc.pages[pageIndex];

      // Displayed (rotation-applied) page size, matching the raster.
      final bool swap = page.rotation.index.isOdd;
      final double dispW = swap ? page.height : page.width;
      final double dispH = swap ? page.width : page.height;
      if (dispW <= 0 || dispH <= 0) return null;

      final pageText = await page.loadStructuredText();
      final runs = <PdfTextRun>[];

      for (final frag in pageText.fragments) {
        final text = frag.text;
        if (text.isEmpty) continue;
        if (frag.bounds.isEmpty) continue;

        final runRect = _toPageRect(
          frag.bounds.toRect(page: page),
          dispW: dispW,
          dispH: dispH,
          placement: placement,
        );
        if (runRect == null) continue;

        // Per-character boxes power caret-level selection. Only keep them when
        // there's exactly one box per UTF-16 unit of the fragment text — PDFium
        // usually matches, but combining marks / surrogate oddities can drift,
        // and a misaligned char box is worse than none (the UI then falls back
        // to whole-run selection for that run).
        List<PdfCharBox> chars = const [];
        if (frag.charRects.length == text.length) {
          final boxes = <PdfCharBox>[];
          for (final cr in frag.charRects) {
            final r = _toPageRect(
              cr.toRect(page: page),
              dispW: dispW,
              dispH: dispH,
              placement: placement,
            );
            if (r == null) {
              // Spaces frequently have an empty box — substitute a zero-width
              // sliver at the run's vertical extent so indices stay aligned.
              boxes.add(PdfCharBox(
                x: runRect.left, y: runRect.top, width: 0, height: runRect.height));
              continue;
            }
            boxes.add(PdfCharBox(
                x: r.left, y: r.top, width: r.width, height: r.height));
          }
          chars = boxes;
        }

        runs.add(PdfTextRun(
          text: text,
          x: runRect.left,
          y: runRect.top,
          width: runRect.width,
          height: runRect.height,
          chars: chars,
        ));
      }

      if (runs.isEmpty) return null;
      return PdfTextLayer(
        sourceAssetPath: sourceAssetPath,
        source: 'embedded',
        runs: runs,
      );
    } catch (e, st) {
      debugPrint('[PdfTextExtractor] page $pageIndex failed: $e\n$st');
      return null;
    }
  }

  /// Map a rect already in DISPLAYED-page points (origin top-left) onto the
  /// placed raster image, yielding page-logical points. Returns null for a
  /// degenerate rect.
  ///
  /// Pure & deterministic — unit-tested in test/pdf_text_extractor_test.dart.
  @visibleForTesting
  static Rect? mapDisplayedRectToPage(
    Rect displayed, {
    required double dispW,
    required double dispH,
    required PdfImagePlacement placement,
  }) =>
      _toPageRect(displayed, dispW: dispW, dispH: dispH, placement: placement);

  static Rect? _toPageRect(
    Rect displayed, {
    required double dispW,
    required double dispH,
    required PdfImagePlacement placement,
  }) {
    if (dispW <= 0 || dispH <= 0) return null;
    if (!displayed.left.isFinite || !displayed.top.isFinite) return null;
    final fx = displayed.left / dispW;
    final fy = displayed.top / dispH;
    final fw = displayed.width / dispW;
    final fh = displayed.height / dispH;
    return Rect.fromLTWH(
      placement.offset.dx + fx * placement.width,
      placement.offset.dy + fy * placement.height,
      fw * placement.width,
      fh * placement.height,
    );
  }
}
