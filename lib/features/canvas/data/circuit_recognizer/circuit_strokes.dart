// A circuit rewrite as page strokes: kept ink in the user's pen, wires and
// symbols as technical lines.

import 'dart:math';
import 'dart:typed_data';

import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'circuit_recognizer_service.dart';

/// One stroke per added polyline of [result] (degenerate ones dropped), each
/// coloured like its entry in [styles].
List<StrokeData> circuitStrokes(CircuitResult result, List<StrokeData> styles) {
  final now = DateTime.now();
  final width = wireWidth(result.rlen);
  return [
    for (var i = 0; i < result.added.length; i++)
      if (result.added[i].length >= 4)
        switch (i < result.kinds.length ? result.kinds[i] : CircuitInk.drawn) {
          CircuitInk.drawn => styles[i].copyWith(
              points: _drawnPoints(result.added[i], _meanPressure(styles[i])),
              timestamp: now,
            ),
          final kind => StrokeData(
              // Older clients draw an unknown tool with the fountain pen: at
              // this pressure it comes out about baseWidth wide.
              points: _drawnPoints(result.added[i], 0.32),
              toolType: switch (kind) {
                CircuitInk.fill => kTechnicalFillTool,
                CircuitInk.body => kTechnicalBodyTool,
                _ => kTechnicalTool,
              },
              color: styles[i].color,
              baseWidth: kind == CircuitInk.body ? 2 * width : width,
              opacity: styles[i].isHighlighter ? 1.0 : styles[i].opacity,
              timestamp: now,
            ),
        },
  ];
}

/// CircuiTikZ's wire, 0.4 pt on its 1.4 cm basic length: 0.01 R, part
/// outlines twice that. Never under 0.3 page units, which a small drawing
/// would otherwise fade to on screen.
double wireWidth(double rlen) => max(0.01 * rlen, 0.3);

/// [flat] as technical-pen points, dense like a drawn line.
List<StrokePoint> technicalPoints(Float64List flat) => _drawnPoints(flat, 0.32);

double _meanPressure(StrokeData d) =>
    d.points.length < 2 ? 0.5 : d.points.fold(0.0, (a, p) => a + p.pressure) / d.points.length;

/// Points every page unit along [flat] at an even, unhurried pace: the pen
/// splines through points and thins fast ones, so sparse corner points alone
/// would round off zigzags and bulge at bends.
List<StrokePoint> _drawnPoints(Float64List flat, double pressure) {
  final out = <StrokePoint>[];
  var t = 0.0;
  void add(double x, double y) => out.add(StrokePoint(x: x, y: y, pressure: pressure, timestamp: t.round()));
  add(flat[0], flat[1]);
  for (var k = 2; k + 1 < flat.length; k += 2) {
    final x0 = flat[k - 2], y0 = flat[k - 1], x1 = flat[k], y1 = flat[k + 1];
    final len = sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    final n = max(1, len.ceil());
    for (var j = 1; j <= n; j++) {
      t += len / n * 5; // 200 units/s
      add(x0 + (x1 - x0) * j / n, y0 + (y1 - y0) * j / n);
    }
  }
  return out;
}
