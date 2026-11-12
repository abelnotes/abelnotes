// Circuit rewrite -> page strokes, and how technical strokes are painted.
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_recognizer_service.dart';
import 'package:abelnotes/features/canvas/data/circuit_recognizer/circuit_strokes.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StrokeData _pen(double width, double pressure, {int color = 0xFF112233}) => StrokeData(
      points: [
        StrokePoint(x: 0, y: 0, pressure: pressure),
        StrokePoint(x: 10, y: 0, pressure: pressure),
      ],
      baseWidth: width,
      color: color,
    );

CircuitResult _result(List<List<double>> added, List<CircuitInk> kinds, double rlen) => CircuitResult(
      {0},
      [for (final a in added) Float64List.fromList(a)],
      List.filled(added.length, -1),
      1,
      0,
      null,
      kinds: kinds,
      rlen: rlen,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('circuitStrokes', () {
    test('kept ink keeps the pen; wires and symbols become technical', () {
      final style = _pen(1.5, 0.5);
      final out = circuitStrokes(
        _result([
          [0, 0, 5, 5],
          [0, 0, 20, 0, 20, 20],
          [0, 0, 4, 0, 2, 3, 0, 0],
          [0, 0, 8, 0],
        ], [CircuitInk.drawn, CircuitInk.wire, CircuitInk.fill, CircuitInk.body], 50),
        [style, style, style, style],
      );
      expect(out.map((s) => s.toolType), ['pen', kTechnicalTool, kTechnicalFillTool, kTechnicalBodyTool]);
      expect(out.map((s) => s.color).toSet(), {0xFF112233});
      // CircuiTikZ's weights: 0.01 R wires, outlines twice that; kept ink
      // keeps the pen's.
      expect(out[1].baseWidth, closeTo(0.5, 1e-9));
      expect(out[2].baseWidth, out[1].baseWidth);
      expect(out[3].baseWidth, closeTo(1.0, 1e-9));
      expect(out[0].baseWidth, 1.5);
      // Corners survive as points; dense enough for an older client's pen.
      expect(out[1].points.any((p) => p.x == 20 && p.y == 0), isTrue);
      expect(out[1].points.length, greaterThanOrEqualTo(40));
    });

    test('pressure makes an older client draw the line at about baseWidth', () {
      final out = circuitStrokes(_result([[0, 0, 10, 0]], [CircuitInk.wire], 30), [_pen(1.5, 0.5)]);
      final p = out.single.points.first.pressure;
      // Fountain pen width factor: 0.35 + 1.15 * sqrt(pressure).
      expect(0.35 + 1.15 * sqrt(p), closeTo(1.0, 0.01));
    });

    test('wires are 0.01 R, never under 0.3 page units', () {
      expect(wireWidth(60), closeTo(0.6, 1e-9));
      expect(wireWidth(20), 0.3);
    });

    test('degenerate polylines are dropped', () {
      final out = circuitStrokes(_result([[3, 3]], [CircuitInk.wire], 30), [_pen(1.5, 0.5)]);
      expect(out, isEmpty);
    });
  });

  group('paintTechnicalStroke', () {
    List<StrokePoint> pts(List<(double, double)> xy) => [for (final (x, y) in xy) StrokePoint(x: x, y: y)];

    Future<ui.Image> paint(StrokeData s) async {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec)..drawRect(const Rect.fromLTWH(0, 0, 60, 60), Paint()..color = Colors.white);
      paintTechnicalStroke(canvas, s);
      return rec.endRecording().toImage(60, 60);
    }

    Future<bool> inked(ui.Image img, int x, int y) async {
      final data = await img.toByteData();
      return data!.getUint8((y * img.width + x) * 4) < 128;
    }

    test('a corner is square, not rounded', () async {
      final img = await paint(StrokeData(
        points: pts([(10, 40), (10, 10), (40, 10)]),
        toolType: kTechnicalTool,
        baseWidth: 6,
      ));
      // The outer corner pixel: inside a miter, outside a round join.
      expect(await inked(img, 7, 7), isTrue);
      expect(await inked(img, 25, 25), isFalse);
    });

    test('wires meeting end to end leave no seam', () async {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec)..drawRect(const Rect.fromLTWH(0, 0, 60, 60), Paint()..color = Colors.white);
      for (final xs in [(10.0, 30.5), (30.5, 50.0)]) {
        paintTechnicalStroke(
            canvas, StrokeData(points: pts([(xs.$1, 30), (xs.$2, 30)]), toolType: kTechnicalTool, baseWidth: 2));
      }
      final data = await (await rec.endRecording().toImage(60, 60)).toByteData();
      int at(int x) => data!.getUint8((30 * 60 + x) * 4);
      // Flat anti-aliased ends would each cover half of column 30.
      expect(at(30), lessThanOrEqualTo(at(20) + 8));
    });

    test('the fill variant is solid inside', () async {
      final img = await paint(StrokeData(
        points: pts([(10, 10), (50, 10), (30, 50), (10, 10)]),
        toolType: kTechnicalFillTool,
        baseWidth: 1,
      ));
      expect(await inked(img, 30, 22), isTrue);
    });

    test('a closed outline is not filled', () async {
      final img = await paint(StrokeData(
        points: pts([(10, 10), (50, 10), (30, 50), (10, 10)]),
        toolType: kTechnicalTool,
        baseWidth: 1,
      ));
      expect(await inked(img, 30, 22), isFalse);
      expect(await inked(img, 30, 10), isTrue);
    });
  });
}
