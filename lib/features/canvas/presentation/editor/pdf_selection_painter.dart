// Painter for the translucent PDF text selection highlight.

import 'package:flutter/material.dart';

/// Paints the translucent highlight rectangles for a PDF text selection.
class PdfSelectionPainter extends CustomPainter {
  PdfSelectionPainter(this.rects, this.color);

  final List<Rect> rects;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty) return;
    final paint = Paint()..color = color;
    for (final r in rects) {
      // Pad a hair so adjacent character boxes read as one continuous run.
      canvas.drawRect(r.inflate(0.5), paint);
    }
  }

  @override
  bool shouldRepaint(PdfSelectionPainter old) =>
      old.rects != rects || old.color != color;
}
