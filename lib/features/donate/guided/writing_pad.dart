// The surface a volunteer writes on: one pointer at a time, pen, finger or
// mouse, with points kept as the sample stores them.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:abelnotes/features/canvas/presentation/pen_contact.dart';

/// Pad width in sample units: the same ink is the same size on a phone and
/// on a desktop. About a third of a page at the detector's scale (1024).
const double kPadUnits = 512;

class PadController extends ChangeNotifier {
  /// Strokes in pad pixels: flat [x, y, t, p, ...], t in ms on the event
  /// clock.
  final List<List<double>> strokes = [];
  List<double>? _live;
  int? _pointer, _device;

  /// Once a pen has written, fingers are a resting palm.
  bool penSeen = false;

  bool get isEmpty => strokes.isEmpty && _live == null;

  void undo() {
    if (strokes.isEmpty) return;
    strokes.removeLast();
    notifyListeners();
  }

  void clear() {
    strokes.clear();
    _live = null;
    _pointer = null;
    notifyListeners();
  }

  /// The strokes in sample units for a pad [width] pixels wide.
  List<List<double>> toUnits(double width) {
    final k = kPadUnits / width;
    return [
      for (final s in strokes)
        [for (var i = 0; i < s.length; i += 4) ...[s[i] * k, s[i + 1] * k, s[i + 2], s[i + 3]]],
    ];
  }

  static double _pressure(PointerEvent e) {
    final range = e.pressureMax - e.pressureMin;
    // Mice and most fingers report no pressure: a middle value.
    if (range <= 0 || e.kind == PointerDeviceKind.mouse) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
  }

  void _add(PointerEvent e) =>
      _live!.addAll([e.localPosition.dx, e.localPosition.dy, e.timeStamp.inMicroseconds / 1000, _pressure(e)]);

  bool _accepts(PointerEvent e) {
    if (e.kind == PointerDeviceKind.invertedStylus) return false;
    if (e.kind == PointerDeviceKind.stylus) {
      // Browsers report a side button pressed while hovering as a down.
      return penTipTouches(e.buttons, downMayPrecedeContact: true);
    }
    if (e.kind == PointerDeviceKind.touch) return !penSeen;
    return e.kind != PointerDeviceKind.mouse || (e.buttons & kPrimaryMouseButton) != 0;
  }

  void down(PointerDownEvent e) {
    if (!_accepts(e)) return;
    if (_pointer != null) {
      // A second finger is ignored. The same device again means its lift
      // never arrived (some browsers send a pen's as a hover): end it here.
      if (e.device != _device) return;
      up();
    }
    if (e.kind == PointerDeviceKind.stylus) penSeen = true;
    _pointer = e.pointer;
    _device = e.device;
    _live = [];
    _add(e);
    notifyListeners();
  }

  void move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _live == null) return;
    if (e.kind == PointerDeviceKind.stylus && !penTipTouches(e.buttons, downMayPrecedeContact: true)) {
      up();
      return;
    }
    _add(e);
    notifyListeners();
  }

  /// A hover from the writing device: the tip is off the surface.
  void hover(PointerHoverEvent e) {
    if (_pointer != null && e.device == _device) up();
  }

  void up([PointerEvent? e]) {
    if (e != null && e.pointer != _pointer) return;
    final s = _live;
    _live = null;
    _pointer = null;
    if (s != null && s.isNotEmpty) strokes.add(s);
    notifyListeners();
  }

  /// A cancelled pointer (the system took it over) leaves no stroke.
  void cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _live = null;
    _pointer = null;
    notifyListeners();
  }
}

class WritingPad extends StatelessWidget {
  const WritingPad({super.key, required this.controller, required this.color, this.hint, this.guide});
  final PadController controller;
  final Color color;

  /// Shown while the pad is empty.
  final String? hint;

  /// Colour of the baseline drawn across the middle; none when null.
  final Color? guide;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: controller.down,
      onPointerMove: controller.move,
      onPointerUp: controller.up,
      onPointerHover: controller.hover,
      onPointerCancel: controller.cancel,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Stack(fit: StackFit.expand, children: [
          if (hint != null && controller.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(hint!,
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: color.withValues(alpha: 0.4))),
              ),
            ),
          CustomPaint(painter: _PadPainter(controller, color, guide)),
        ]),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.c, this.color, this.guide) : super(repaint: c);
  final PadController c;
  final Color color;
  final Color? guide;

  @override
  void paint(Canvas canvas, Size size) {
    if (guide != null) {
      final y = size.height * 0.62;
      canvas.drawLine(Offset(24, y), Offset(size.width - 24, y), Paint()..color = guide!..strokeWidth = 1);
    }
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.6;
    for (final s in [...c.strokes, if (c._live != null) c._live!]) {
      if (s.length == 4) {
        canvas.drawCircle(Offset(s[0], s[1]), 1.6, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(s[0], s[1]);
      for (var i = 4; i < s.length; i += 4) {
        path.lineTo(s[i], s[i + 1]);
      }
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}
