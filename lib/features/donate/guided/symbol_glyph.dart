// A circuit symbol drawn on its own, to show what the guided page asks for.
// Two-terminal parts come from the tidy-up's own geometry (CircuiTikZ's, see
// circuit_graph.dart), the rest are drawn here in the same proportions.

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_graph.dart';

class GlyphLine {
  const GlyphLine(this.points, {this.fill = false});
  final List<Offset> points;
  final bool fill;
}

List<Offset> _arc(Offset c, double r, double from, double to, [int n = 16]) => [
      for (var i = 0; i <= n; i++) c + Offset.fromDirection(from + (to - from) * i / n, r),
    ];

GlyphLine _head(Offset tip, Offset dir, double size) {
  final u = dir / dir.distance, v = Offset(-u.dy, u.dx);
  final back = tip - u * size;
  return GlyphLine([tip, back + v * (size * 0.5), back - v * (size * 0.5), tip], fill: true);
}

GlyphLine _plus(Offset c, double h) => GlyphLine([c - Offset(h, 0), c + Offset(h, 0), c, c - Offset(0, h), c + Offset(0, h)]);

/// [symbol] in units of CircuiTikZ's basic length; empty for `text`, which
/// the painter writes instead.
List<GlyphLine> symbolGlyph(String symbol) {
  final drawn = symbolDrawing(symbol, 1);
  if (drawn != null) {
    return [
      for (final o in drawn) GlyphLine([for (final p in o.points) Offset(p.x, p.y)], fill: o.fill),
    ];
  }
  return switch (symbol) {
    'capacitor.polarized' => [
        const GlyphLine([Offset(0, 0), Offset(0.62, 0)]),
        const GlyphLine([Offset(0.62, -0.3), Offset(0.62, 0.3)]),
        GlyphLine([for (var i = 0; i <= 12; i++) Offset(0.78 + 0.06 * math.pow((i - 6) / 6, 2), -0.3 + 0.05 * i)]),
        const GlyphLine([Offset(0.78, 0), Offset(1.4, 0)]),
        _plus(const Offset(0.48, -0.22), 0.06),
      ],
    'gnd' => const [
        GlyphLine([Offset(0.7, -0.5), Offset(0.7, 0)]),
        GlyphLine([Offset(0.45, 0), Offset(0.95, 0)]),
        GlyphLine([Offset(0.54, 0.1), Offset(0.86, 0.1)]),
        GlyphLine([Offset(0.63, 0.2), Offset(0.77, 0.2)]),
      ],
    'vss' => const [
        GlyphLine([Offset(0.7, 0.5), Offset(0.7, -0.2)]),
        GlyphLine([Offset(0.58, -0.05), Offset(0.7, -0.2), Offset(0.82, -0.05)]),
      ],
    'opamp' => [
        const GlyphLine([Offset(0.3, -0.5), Offset(0.3, 0.5), Offset(1.1, 0), Offset(0.3, -0.5)]),
        const GlyphLine([Offset(0, -0.25), Offset(0.3, -0.25)]),
        const GlyphLine([Offset(0, 0.25), Offset(0.3, 0.25)]),
        const GlyphLine([Offset(1.1, 0), Offset(1.4, 0)]),
        const GlyphLine([Offset(0.38, -0.25), Offset(0.5, -0.25)]),
        _plus(const Offset(0.44, 0.25), 0.06),
      ],
    'transistor.bjt' => [
        const GlyphLine([Offset(0, 0), Offset(0.5, 0)]),
        const GlyphLine([Offset(0.5, -0.3), Offset(0.5, 0.3)]),
        const GlyphLine([Offset(0.5, -0.12), Offset(0.85, -0.4), Offset(0.85, -0.65)]),
        const GlyphLine([Offset(0.5, 0.12), Offset(0.85, 0.4), Offset(0.85, 0.65)]),
        _head(const Offset(0.85, 0.4), const Offset(0.35, 0.28), 0.12),
      ],
    'transistor.fet' => [
        const GlyphLine([Offset(0, 0.25), Offset(0.45, 0.25)]),
        const GlyphLine([Offset(0.45, -0.25), Offset(0.45, 0.25)]),
        const GlyphLine([Offset(0.55, -0.3), Offset(0.55, 0.3)]),
        const GlyphLine([Offset(0.55, -0.22), Offset(0.85, -0.22), Offset(0.85, -0.65)]),
        const GlyphLine([Offset(0.55, 0.22), Offset(0.85, 0.22), Offset(0.85, 0.65)]),
        _head(const Offset(0.8, 0.22), const Offset(1, 0), 0.12),
      ],
    'transformer' => [
        for (final (x, side) in [(0.5, 1.0), (0.9, -1.0)]) ...[
          GlyphLine([
            Offset(x - side * 0.3, -0.6),
            Offset(x, -0.6),
            for (var k = 0; k < 4; k++)
              ..._arc(Offset(x, -0.3 + 0.2 * k), 0.1, -math.pi / 2, side > 0 ? math.pi / 2 : -3 * math.pi / 2, 10),
            Offset(x, 0.6),
            Offset(x - side * 0.3, 0.6),
          ]),
        ],
        const GlyphLine([Offset(0.67, -0.45), Offset(0.67, 0.45)]),
        const GlyphLine([Offset(0.73, -0.45), Offset(0.73, 0.45)]),
      ],
    'ic' => [
        const GlyphLine([Offset(0.35, -0.5), Offset(1.05, -0.5), Offset(1.05, 0.5), Offset(0.35, 0.5), Offset(0.35, -0.5)]),
        for (final y in [-0.3, 0.0, 0.3]) ...[
          GlyphLine([Offset(0.15, y), Offset(0.35, y)]),
          GlyphLine([Offset(1.05, y), Offset(1.25, y)]),
        ],
      ],
    'crossover' => [
        GlyphLine([const Offset(0, 0), const Offset(0.55, 0), ..._arc(const Offset(0.7, 0), 0.15, math.pi, 2 * math.pi), const Offset(1.4, 0)]),
        const GlyphLine([Offset(0.7, -0.6), Offset(0.7, 0.6)]),
      ],
    'terminal' => [
        const GlyphLine([Offset(0, 0), Offset(1.0, 0)]),
        GlyphLine(_arc(const Offset(1.09, 0), 0.09, 0, 2 * math.pi, 20)),
      ],
    'arrow' => [
        const GlyphLine([Offset(0.1, 0), Offset(1.2, 0)]),
        _head(const Offset(1.32, 0), const Offset(1, 0), 0.16),
      ],
    _ => const [],
  };
}

/// [symbol] fitted into the canvas, or [text] written for the `text` class.
class SymbolGlyphPainter extends CustomPainter {
  SymbolGlyphPainter(this.symbol, this.color, {this.text});
  final String symbol;
  final Color color;
  final String? text;

  @override
  void paint(Canvas canvas, Size size) {
    if (symbol == 'text') {
      final tp = TextPainter(
        text: TextSpan(text: text ?? 'R1', style: TextStyle(color: color, fontSize: size.height * 0.45)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
      return;
    }
    final lines = symbolGlyph(symbol);
    final all = [for (final l in lines) ...l.points];
    if (all.isEmpty) return;
    final bounds = all.skip(1).fold(Rect.fromPoints(all.first, all.first), (r, p) => r.expandToInclude(Rect.fromPoints(p, p)));
    const margin = 8.0;
    final scale = math.min((size.width - 2 * margin) / math.max(bounds.width, 1e-3),
        (size.height - 2 * margin) / math.max(bounds.height, 1e-3));
    final origin = Offset((size.width - bounds.width * scale) / 2, (size.height - bounds.height * scale) / 2) -
        bounds.topLeft * scale;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    for (final l in lines) {
      final path = Path()..addPolygon([for (final p in l.points) origin + p * scale], false);
      canvas.drawPath(path, l.fill ? fill : stroke);
    }
  }

  @override
  bool shouldRepaint(SymbolGlyphPainter old) => old.symbol != symbol || old.color != color || old.text != text;
}
