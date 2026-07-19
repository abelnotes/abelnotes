import 'package:flutter/material.dart';

/// HandWriter custom icon set (line, rounded caps, 20x20 viewBox).
/// Stylistically aligned with the design spec.
class HwIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  final double strokeWidth;

  const HwIcon(
    this.name, {
    super.key,
    this.size = 20,
    this.color,
    this.strokeWidth = 1.6,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HwIconPainter(name: name, color: c, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _HwIconPainter extends CustomPainter {
  final String name;
  final Color color;
  final double strokeWidth;

  _HwIconPainter({
    required this.name,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 20;
    canvas.scale(scale, scale);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;

    void p(String d) => canvas.drawPath(_parsePath(d), stroke);
    void pf(String d) => canvas.drawPath(_parsePath(d), fill);
    void circle(double cx, double cy, double r, {bool filled = false}) {
      canvas.drawCircle(Offset(cx, cy), r, filled ? fill : stroke);
    }

    switch (name) {
      case 'pen':
        p('M3 17l3-1 9-9-2-2-9 9-1 3z');
        p('M14 5l1-1a1.4 1.4 0 0 1 2 2l-1 1');
        break;
      case 'ballpoint':
        p('M4 16l2-1 8-8-1-1-8 8-1 2z');
        p('M14 7l1-2');
        break;
      case 'brush':
        p('M4 16c1-2 3-3 5-2');
        p('M9 14l6-6a1.5 1.5 0 0 0-2-2l-6 6');
        p('M5 12c-1 1-1.5 3-1 4 1 .5 3 0 4-1');
        break;
      case 'calligraphy':
        p('M3 17l3-1 9-9-2-2-9 9-1 3z');
        p('M5 16l1-1');
        break;
      case 'highlighter':
        p('M5 17v-3l8-8 3 3-8 8h-3z');
        p('M11 7l3 3');
        p('M3 17h6');
        break;
      case 'eraser':
        p('M4 14l6-6a1.5 1.5 0 0 1 2 0l4 4a1.5 1.5 0 0 1 0 2l-3 3H6l-2-2a1.5 1.5 0 0 1 0-1z');
        p('M9 9l5 5');
        break;
      case 'eraser-stroke':
        p('M4 14l6-6a1.5 1.5 0 0 1 2 0l4 4a1.5 1.5 0 0 1 0 2l-3 3H6l-2-2a1.5 1.5 0 0 1 0-1z');
        // dashed underline
        for (var x = 3.0; x < 17; x += 4) {
          canvas.drawLine(Offset(x, 17), Offset(x + 2, 17), stroke);
        }
        break;
      case 'lasso':
        p('M10 4c4 0 7 2 7 5s-3 5-7 5c-2 0-4-.5-5-1.5');
        p('M5 12.5c-1 1-1 3 0 4 .5.5 1 .5 1.5 0');
        circle(6, 17, 1, filled: true);
        break;
      case 'hand':
        p('M7 11V5a1 1 0 0 1 2 0v5');
        p('M9 10V4a1 1 0 0 1 2 0v6');
        p('M11 10V5a1 1 0 0 1 2 0v6');
        p('M13 10V7a1 1 0 0 1 2 0v6c0 2-1 4-4 4-3 0-4-1-5-3l-2-4a1 1 0 0 1 2-1l1 2');
        break;
      case 'text':
        p('M5 5h10');
        p('M10 5v11');
        p('M8 16h4');
        break;
      case 'mouse':
        canvas.drawRRect(
            RRect.fromLTRBR(6, 3, 14, 17, const Radius.circular(4)), stroke);
        p('M10 3v4'); // scroll-wheel line
        break;
      case 'shape':
        canvas.drawRRect(
            RRect.fromLTRBR(3, 3, 11, 11, const Radius.circular(1)), stroke);
        circle(13, 13, 4);
        break;
      case 'shape-guess':
        p('M4 16l3-7 4 4 5-9');
        circle(4, 16, 0.8, filled: true);
        circle(16, 4, 0.8, filled: true);
        break;
      case 'image':
        canvas.drawRRect(
            RRect.fromLTRBR(3, 4, 17, 16, const Radius.circular(2)), stroke);
        circle(7, 8, 1.2);
        p('M3 14l4-3 4 3 3-2 3 2');
        break;
      case 'symbol':
        canvas.drawRRect(
            RRect.fromLTRBR(3, 3, 9, 9, const Radius.circular(1)), stroke);
        canvas.drawRRect(
            RRect.fromLTRBR(11, 3, 17, 9, const Radius.circular(1)), stroke);
        canvas.drawRRect(
            RRect.fromLTRBR(3, 11, 9, 17, const Radius.circular(1)), stroke);
        canvas.drawRRect(
            RRect.fromLTRBR(11, 11, 17, 17, const Radius.circular(1)), stroke);
        break;
      case 'undo':
        p('M5 9h7a4 4 0 0 1 0 8h-2');
        p('M8 6L5 9l3 3');
        break;
      case 'redo':
        p('M15 9H8a4 4 0 0 0 0 8h2');
        p('M12 6l3 3-3 3');
        break;
      case 'search':
        circle(9, 9, 5);
        p('M13 13l4 4');
        break;
      case 'plus':
        p('M10 4v12');
        p('M4 10h12');
        break;
      case 'minus':
        p('M4 10h12');
        break;
      case 'x':
        p('M5 5l10 10');
        p('M15 5L5 15');
        break;
      case 'check':
        p('M4 10l4 4 8-8');
        break;
      case 'star':
        p('M10 3l2.2 4.5 5 .7-3.6 3.5.85 5L10 14.3 5.55 16.7l.85-5L2.8 8.2l5-.7L10 3z');
        break;
      case 'star-filled':
        pf('M10 3l2.2 4.5 5 .7-3.6 3.5.85 5L10 14.3 5.55 16.7l.85-5L2.8 8.2l5-.7L10 3z');
        break;
      case 'menu':
        p('M4 6h12');
        p('M4 10h12');
        p('M4 14h12');
        break;
      case 'grid':
        canvas.drawRRect(
            RRect.fromLTRBR(3, 3, 9, 9, const Radius.circular(1)), stroke);
        canvas.drawRRect(
            RRect.fromLTRBR(11, 3, 17, 9, const Radius.circular(1)), stroke);
        canvas.drawRRect(
            RRect.fromLTRBR(3, 11, 9, 17, const Radius.circular(1)), stroke);
        canvas.drawRRect(
            RRect.fromLTRBR(11, 11, 17, 17, const Radius.circular(1)), stroke);
        break;
      case 'list':
        p('M7 5h10');
        p('M7 10h10');
        p('M7 15h10');
        circle(4, 5, 0.8, filled: true);
        circle(4, 10, 0.8, filled: true);
        circle(4, 15, 0.8, filled: true);
        break;
      case 'sort':
        p('M6 4v12');
        p('M3 7l3-3 3 3');
        p('M14 16V4');
        p('M11 13l3 3 3-3');
        break;
      case 'settings':
        circle(10, 10, 2.5);
        p('M10 3v2');
        p('M10 15v2');
        p('M3 10h2');
        p('M15 10h2');
        p('M5.5 5.5l1.4 1.4');
        p('M13.1 13.1l1.4 1.4');
        p('M5.5 14.5l1.4-1.4');
        p('M13.1 6.9l1.4-1.4');
        break;
      case 'trash':
        p('M4 6h12');
        p('M8 6V4h4v2');
        p('M5 6l1 11h8l1-11');
        break;
      case 'cloud':
        p('M6 14h9a3 3 0 0 0 .5-6 4.5 4.5 0 0 0-8.7-1A3.5 3.5 0 0 0 6 14z');
        break;
      case 'cloud-check':
        p('M6 14h9a3 3 0 0 0 .5-6 4.5 4.5 0 0 0-8.7-1A3.5 3.5 0 0 0 6 14z');
        p('M8 11l1.5 1.5L13 9.5');
        break;
      case 'cloud-pending':
        p('M6 14h9a3 3 0 0 0 .5-6 4.5 4.5 0 0 0-8.7-1A3.5 3.5 0 0 0 6 14z');
        circle(8, 11, 0.7, filled: true);
        circle(10.5, 11, 0.7, filled: true);
        circle(13, 11, 0.7, filled: true);
        break;
      case 'cloud-off':
        p('M6 14h9a3 3 0 0 0 .5-6 4.5 4.5 0 0 0-8.7-1A3.5 3.5 0 0 0 6 14z');
        p('M3 3l14 14');
        break;
      case 'cloud-conflict':
        p('M6 14h9a3 3 0 0 0 .5-6 4.5 4.5 0 0 0-8.7-1A3.5 3.5 0 0 0 6 14z');
        p('M10 9v2.5');
        circle(10, 13.2, 0.4, filled: true);
        break;
      case 'wifi':
        p('M3 8c4-4 10-4 14 0');
        p('M5.5 11c2.5-2.5 6.5-2.5 9 0');
        p('M8 13.5c1-1 3-1 4 0');
        break;
      case 'battery':
        canvas.drawRRect(
            RRect.fromLTRBR(2, 6, 16, 14, const Radius.circular(1.5)), stroke);
        p('M17 9v2');
        canvas.drawRRect(
            RRect.fromLTRBR(3.5, 7.5, 12.5, 12.5, const Radius.circular(0.5)),
            fill);
        break;
      case 'chevron-left':
        p('M12 5l-5 5 5 5');
        break;
      case 'chevron-right':
        p('M8 5l5 5-5 5');
        break;
      case 'chevron-down':
        p('M5 8l5 5 5-5');
        break;
      case 'chevron-up':
        p('M5 12l5-5 5 5');
        break;
      case 'more':
        circle(5, 10, 1.2, filled: true);
        circle(10, 10, 1.2, filled: true);
        circle(15, 10, 1.2, filled: true);
        break;
      case 'export':
        p('M10 3v9');
        p('M7 6l3-3 3 3');
        p('M4 13v3a1 1 0 0 0 1 1h10a1 1 0 0 0 1-1v-3');
        break;
      case 'pages':
        canvas.drawRRect(
            RRect.fromLTRBR(4, 3, 13, 15, const Radius.circular(1)), stroke);
        p('M7 17h9V6');
        break;
      case 'folder':
        p('M3 6a1 1 0 0 1 1-1h4l1.5 2H16a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6z');
        break;
      case 'chapter':
        p('M4 4h12v12H4z');
        p('M4 8h12');
        p('M8 4v12');
        break;
      case 'duplicate':
        canvas.drawRRect(
            RRect.fromLTRBR(3, 3, 13, 13, const Radius.circular(1.5)), stroke);
        canvas.drawRRect(
            RRect.fromLTRBR(7, 7, 17, 17, const Radius.circular(1.5)), stroke);
        break;
      case 'rotate':
        p('M4 10a6 6 0 1 1 2 4.5');
        p('M3 14l3 1 1-3');
        break;
      case 'flip':
        p('M10 3v14');
        p('M5 7l-2 3 2 3');
        p('M15 7l2 3-2 3');
        break;
      case 'lock':
        canvas.drawRRect(
            RRect.fromLTRBR(4, 9, 16, 17, const Radius.circular(1.5)), stroke);
        p('M7 9V6a3 3 0 0 1 6 0v3');
        break;
      case 'palette':
        p('M10 3a7 7 0 1 0 0 14h1a1.5 1.5 0 0 0 1-2.5 1.5 1.5 0 0 1 1-2.5h2a3 3 0 0 0 3-3 7 7 0 0 0-8-6z');
        circle(6, 9, 1, filled: true);
        circle(9, 6, 1, filled: true);
        circle(13, 6, 1, filled: true);
        break;
      case 'thickness':
        canvas.drawLine(
            const Offset(3, 6), const Offset(17, 6), stroke..strokeWidth = 1);
        canvas.drawLine(
            const Offset(3, 10), const Offset(17, 10), stroke..strokeWidth = 2);
        canvas.drawLine(const Offset(3, 14), const Offset(17, 14),
            stroke..strokeWidth = 3.5);
        break;
      case 'help':
        circle(10, 10, 7);
        p('M8 8a2 2 0 1 1 2.5 2c-.5.3-.5.7-.5 1.5');
        circle(10, 14, 0.6, filled: true);
        break;
      case 'globe':
        circle(10, 10, 7);
        p('M3 10h14');
        p('M10 3c2 2.5 3 5 3 7s-1 4.5-3 7');
        p('M10 3c-2 2.5-3 5-3 7s1 4.5 3 7');
        break;
      case 'moon':
        p('M16 11a6 6 0 0 1-7-7 6 6 0 1 0 7 7z');
        break;
      case 'sun':
        circle(10, 10, 3);
        p('M10 3v2');
        p('M10 15v2');
        p('M3 10h2');
        p('M15 10h2');
        p('M5.5 5.5l1.4 1.4');
        p('M13.1 13.1l1.4 1.4');
        p('M5.5 14.5l1.4-1.4');
        p('M13.1 6.9l1.4-1.4');
        break;
      case 'copy':
        canvas.drawRRect(
            RRect.fromLTRBR(6, 6, 17, 17, const Radius.circular(1.5)), stroke);
        p('M3 12V4a1 1 0 0 1 1-1h8');
        break;
      case 'cut':
        circle(6, 14, 2);
        circle(14, 14, 2);
        p('M7.5 12.5L16 4');
        p('M12.5 12.5L4 4');
        break;
      case 'arrow':
        p('M3 10h12');
        p('M11 6l4 4-4 4');
        break;
      case 'drag':
        circle(7, 5, 0.9, filled: true);
        circle(13, 5, 0.9, filled: true);
        circle(7, 10, 0.9, filled: true);
        circle(13, 10, 0.9, filled: true);
        circle(7, 15, 0.9, filled: true);
        circle(13, 15, 0.9, filled: true);
        break;
      case 'laser':
        // Pen body angled top-right to bottom-left + a glowing dot near
        // the tip — laser-pointer style.
        p('M14 4l2 2-9 9-3 1 1-3 9-9z');
        circle(5, 15, 1.6, filled: true);
        break;
      case 'fit':
        p('M4 7V4h3');
        p('M16 7V4h-3');
        p('M4 13v3h3');
        p('M16 13v3h-3');
        break;
      case 'keyboard':
        canvas.drawRRect(
            RRect.fromLTRBR(2, 6, 18, 15, const Radius.circular(1.5)), stroke);
        p('M5 12h10');
        circle(5, 9, 0.4, filled: true);
        circle(8, 9, 0.4, filled: true);
        circle(11, 9, 0.4, filled: true);
        circle(14, 9, 0.4, filled: true);
        break;
      case 'home':
        p('M3 10l7-6 7 6v6a1 1 0 0 1-1 1h-3v-5H7v5H4a1 1 0 0 1-1-1z');
        break;
      default:
        circle(10, 10, 6);
    }
  }

  @override
  bool shouldRepaint(_HwIconPainter old) =>
      old.name != name ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// Minimal SVG path parser supporting M, L, H, V, A, Q, T, C, Z (uppercase + lowercase).
Path _parsePath(String d) {
  final path = Path();
  final tokens = RegExp(r'([a-zA-Z])|(-?\d*\.?\d+)').allMatches(d);
  final list = tokens.map((m) => m.group(0)!).toList();
  double cx = 0, cy = 0;
  // Last cubic control point absolute coords — used by smooth cubic (S/s)
  // to reflect the previous control point. Null until the first C/c/S/s.
  double? lastCx2, lastCy2;
  String cmd = '';
  int i = 0;
  double next() => double.parse(list[i++]);

  while (i < list.length) {
    final t = list[i];
    if (RegExp(r'[a-zA-Z]').hasMatch(t)) {
      cmd = t;
      i++;
      continue;
    }
    switch (cmd) {
      case 'M':
        cx = next();
        cy = next();
        path.moveTo(cx, cy);
        cmd = 'L';
        break;
      case 'm':
        cx += next();
        cy += next();
        path.moveTo(cx, cy);
        cmd = 'l';
        break;
      case 'L':
        cx = next();
        cy = next();
        path.lineTo(cx, cy);
        break;
      case 'l':
        cx += next();
        cy += next();
        path.lineTo(cx, cy);
        break;
      case 'H':
        cx = next();
        path.lineTo(cx, cy);
        break;
      case 'h':
        cx += next();
        path.lineTo(cx, cy);
        break;
      case 'V':
        cy = next();
        path.lineTo(cx, cy);
        break;
      case 'v':
        cy += next();
        path.lineTo(cx, cy);
        break;
      case 'Q':
        final x1 = next(), y1 = next(), x = next(), y = next();
        path.quadraticBezierTo(x1, y1, x, y);
        cx = x;
        cy = y;
        break;
      case 'q':
        final x1 = cx + next(), y1 = cy + next();
        cx += next();
        cy += next();
        path.quadraticBezierTo(x1, y1, cx, cy);
        break;
      case 'T':
        final x = next(), y = next();
        path.quadraticBezierTo(cx, cy, x, y);
        cx = x;
        cy = y;
        break;
      case 't':
        final dx = next(), dy = next();
        path.quadraticBezierTo(cx, cy, cx + dx, cy + dy);
        cx += dx;
        cy += dy;
        break;
      case 'C':
        final x1 = next(), y1 = next(), x2 = next(), y2 = next(),
            x = next(), y = next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCx2 = x2;
        lastCy2 = y2;
        cx = x;
        cy = y;
        break;
      case 'c':
        // Relative cubic: all 6 params are deltas from current point.
        final x1 = cx + next(), y1 = cy + next();
        final x2 = cx + next(), y2 = cy + next();
        final nx = cx + next(), ny = cy + next();
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        lastCx2 = x2;
        lastCy2 = y2;
        cx = nx;
        cy = ny;
        break;
      case 'S':
        // Smooth cubic absolute: first ctrl point is reflection of
        // previous (lastCx2, lastCy2) around current point.
        {
          final x2 = next(), y2 = next(), x = next(), y = next();
          final lcx = lastCx2;
          final lcy = lastCy2;
          final x1 = lcx != null ? 2 * cx - lcx : cx;
          final y1 = lcy != null ? 2 * cy - lcy : cy;
          path.cubicTo(x1, y1, x2, y2, x, y);
          lastCx2 = x2;
          lastCy2 = y2;
          cx = x;
          cy = y;
        }
        break;
      case 's':
        // Smooth cubic relative.
        {
          final x2 = cx + next(), y2 = cy + next();
          final nx = cx + next(), ny = cy + next();
          final lcx = lastCx2;
          final lcy = lastCy2;
          final x1 = lcx != null ? 2 * cx - lcx : cx;
          final y1 = lcy != null ? 2 * cy - lcy : cy;
          path.cubicTo(x1, y1, x2, y2, nx, ny);
          lastCx2 = x2;
          lastCy2 = y2;
          cx = nx;
          cy = ny;
        }
        break;
      case 'A':
        // 7 params: rx, ry, rot, large, sweep, x, y. Approximate with arcTo.
        final rx = next(), ry = next();
        next(); // x-axis-rotation, ignored (small icons)
        final large = next() != 0;
        final sweep = next() != 0;
        final x = next(), y = next();
        path.arcToPoint(Offset(x, y),
            radius: Radius.elliptical(rx, ry),
            largeArc: large,
            clockwise: sweep);
        cx = x;
        cy = y;
        // Arcs reset the smooth-cubic anchor.
        lastCx2 = null;
        lastCy2 = null;
        break;
      case 'a':
        // Relative arc: same 7 params but x,y are deltas.
        final rx = next(), ry = next();
        next(); // x-axis-rotation, ignored
        final large = next() != 0;
        final sweep = next() != 0;
        final dx = next(), dy = next();
        cx += dx;
        cy += dy;
        path.arcToPoint(Offset(cx, cy),
            radius: Radius.elliptical(rx, ry),
            largeArc: large,
            clockwise: sweep);
        lastCx2 = null;
        lastCy2 = null;
        break;
      case 'Z':
      case 'z':
        path.close();
        lastCx2 = null;
        lastCy2 = null;
        break;
      default:
        i++;
    }
  }
  return path;
}
