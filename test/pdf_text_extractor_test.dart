// Locks down the pure coordinate mapping that places a PDF page's embedded
// text onto the rasterized page image (page-logical points). The pdfrx /
// PDFium side (rotation + Y-flip) is exercised at runtime; here we pin the
// normalise → scale → offset step that the whole overlay alignment rides on.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/features/canvas/data/pdf_text_extractor.dart';

void main() {
  group('mapDisplayedRectToPage', () {
    test('identity: full-page image at origin, no scaling', () {
      final out = PdfTextExtractor.mapDisplayedRectToPage(
        const Rect.fromLTWH(100, 200, 50, 12),
        dispW: 595,
        dispH: 842,
        placement: const PdfImagePlacement(
            offset: Offset.zero, width: 595, height: 842),
      );
      expect(out, isNotNull);
      expect(out!.left, closeTo(100, 1e-9));
      expect(out.top, closeTo(200, 1e-9));
      expect(out.width, closeTo(50, 1e-9));
      expect(out.height, closeTo(12, 1e-9));
    });

    test('scaled + centred placement maps proportionally', () {
      // Image scaled to half and offset to (10, 20).
      final out = PdfTextExtractor.mapDisplayedRectToPage(
        const Rect.fromLTWH(100, 200, 50, 12),
        dispW: 595,
        dispH: 842,
        placement: const PdfImagePlacement(
            offset: Offset(10, 20), width: 297.5, height: 421),
      );
      expect(out, isNotNull);
      expect(out!.left, closeTo(10 + (100 / 595) * 297.5, 1e-6)); // 60
      expect(out.top, closeTo(20 + (200 / 842) * 421, 1e-6)); // 120
      expect(out.width, closeTo((50 / 595) * 297.5, 1e-6)); // 25
      expect(out.height, closeTo((12 / 842) * 421, 1e-6)); // 6
    });

    test('corner of displayed page maps to corner of image rect', () {
      final out = PdfTextExtractor.mapDisplayedRectToPage(
        const Rect.fromLTWH(595 - 10, 842 - 4, 10, 4),
        dispW: 595,
        dispH: 842,
        placement: const PdfImagePlacement(
            offset: Offset(30, 40), width: 200, height: 300),
      );
      expect(out, isNotNull);
      expect(out!.right, closeTo(30 + 200, 1e-6));
      expect(out.bottom, closeTo(40 + 300, 1e-6));
    });

    test('degenerate displayed size returns null', () {
      final out = PdfTextExtractor.mapDisplayedRectToPage(
        const Rect.fromLTWH(0, 0, 1, 1),
        dispW: 0,
        dispH: 842,
        placement: const PdfImagePlacement(
            offset: Offset.zero, width: 595, height: 842),
      );
      expect(out, isNull);
    });
  });
}
