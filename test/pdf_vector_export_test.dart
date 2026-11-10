import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/features/canvas/data/pdf_export.dart';
import 'package:abelnotes/features/canvas/data/pdf_vector_canvas.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

// A wobbly handwriting-like line, enough points to exercise interpolation.
List<StrokePoint> _scribble(double x0, double y0) => [
      for (var i = 0; i < 80; i++)
        StrokePoint(
            x: x0 + i * 4.0,
            y: y0 + 12 * math.sin(i / 3),
            pressure: 0.3 + 0.5 * ((i % 10) / 10)),
    ];

ContentElement _stroke(int i, String tool, {bool hl = false}) =>
    ContentElement.stroke(
        id: 's$i',
        zIndex: i,
        data: StrokeData(
            points: _scribble(20, 40.0 + i * 40),
            toolType: tool,
            isHighlighter: hl,
            baseWidth: hl ? 12 : 2));

ContentElement _shape(int i, String type, {int? fill}) => ContentElement.shape(
    id: 'h$i',
    zIndex: 100 + i,
    data: ShapeData(
        shapeType: type,
        x1: 20.0 + i * 70,
        y1: 600,
        x2: 80.0 + i * 70,
        y2: 660,
        fillColor: fill,
        rotation: i.isEven ? 0 : 0.3));

PageData _page(List<ContentElement> content, {String bg = 'lined'}) => PageData(
      pageId: 'p',
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: RenderingLayers(
          background: BackgroundLayer(type: bg), content: content),
    );

Future<List<PdfVecOp>> _vector(PageData page) {
  final canvas = VectorCanvas(knownBytes: Map.identity());
  CanvasRenderEngine(pageData: page, zoom: 3, pathFactory: VectorPath.new)
      .paintPage(canvas, Size(page.width, page.height), 1, Offset.zero);
  return canvas.finish();
}

Future<Uint8List> _rasterPng(PageData page, double scale) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec)..scale(scale);
  CanvasRenderEngine(pageData: page)
      .paintPage(c, Size(page.width, page.height), 1, Offset.zero);
  final im = await rec
      .endRecording()
      .toImage((page.width * scale).round(), (page.height * scale).round());
  final bd = await im.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

void main() {
  final ink = [
    for (final (i, t) in ['pen', 'ballpoint', 'brush', 'calligraphy'].indexed)
      _stroke(i, t),
    _stroke(4, 'highlighter', hl: true),
    for (var i = 0; i < 8; i++) _stroke(5 + i, 'pen'),
  ];

  testWidgets('every tool, shape and background records as vectors',
      (tester) async {
    await tester.runAsync(() async {
      final shapes = [
        for (final (i, t) in
            ['rectangle', 'circle', 'line', 'arrow', 'triangle', 'rhombus']
                .indexed)
          _shape(i, t, fill: i < 2 ? 0x8000FF00 : null),
      ];
      const text = ContentElement.text(
          id: 't',
          zIndex: 200,
          data: TextData(
              x: 20, y: 700, width: 300, height: 40, content: 'Hello'));
      for (final bg in [
        'blank', 'lined', 'lined_narrow', 'grid', 'dotted', 'cornell',
        'isometric', 'music',
      ]) {
        final ops = await _vector(_page([...ink, ...shapes, text], bg: bg));
        expect(ops.whereType<PdfVecPath>(), isNotEmpty, reason: bg);
        expect(ops.whereType<PdfVecImage>(), isEmpty, reason: bg);
        expect(ops.whereType<PdfVecText>().map((o) => o.text), ['Hello'],
            reason: bg);
        expect(ops.whereType<PdfVecPath>().where((o) => o.multiply),
            isNotEmpty, reason: '$bg highlighter keeps multiply');
      }
    });
  });

  testWidgets('typed text becomes real text, per line and style',
      (tester) async {
    await tester.runAsync(() async {
      const rich = ContentElement.text(
          id: 't',
          zIndex: 1,
          data: TextData(
              x: 50,
              y: 100,
              width: 200,
              height: 200,
              content: 'Plain words that wrap onto more lines\nbold www.x.it',
              fontSize: 14,
              spans: [
                TextSpanData(text: 'Plain words that wrap onto more lines\n'),
                TextSpanData(text: 'bold ', bold: true, underline: true),
                TextSpanData(text: 'www.x.it'),
              ]));
      final ops = await _vector(_page([rich], bg: 'blank'));
      final texts = ops.whereType<PdfVecText>().toList();
      expect(texts.map((t) => t.text).join(' '),
          'Plain words that wrap onto more lines bold www.x.it');
      expect(texts.length, greaterThan(3)); // wrapped + split by style
      expect(texts.map((t) => t.y).toSet().length, greaterThan(2));
      expect(texts.firstWhere((t) => t.text == 'bold').bold, isTrue);
      expect(texts.last.color, 0xFF1565C0); // link
      // Underlines for "bold" and the link, on top of the background rect.
      expect(ops.whereType<PdfVecPath>().where((o) => o.strokeWidth != null),
          hasLength(2));
      final pdf = await buildPdfDocument(
          [PdfExportPage(width: 595, height: 842, vector: ops)]);
      expect(pdf.length, greaterThan(0));
    });
  });

  testWidgets('text the standard fonts cannot encode stays an image',
      (tester) async {
    await tester.runAsync(() async {
      const greek = ContentElement.text(
          id: 't',
          zIndex: 1,
          data: TextData(
              x: 50, y: 100, width: 200, height: 40, content: 'αβγ ok'));
      final ops = await _vector(_page([greek], bg: 'blank'));
      expect(ops.whereType<PdfVecText>(), isEmpty);
      expect(ops.whereType<PdfVecImage>(), hasLength(1));
    });
  });

  testWidgets('a native path makes the page fall back', (tester) async {
    final canvas = VectorCanvas(knownBytes: Map.identity());
    expect(() => canvas.drawPath(Path(), Paint()),
        throwsA(isA<VectorUnsupported>()));
  });

  testWidgets('vector PDF of a handwritten page is smaller than raster',
      (tester) async {
    await tester.runAsync(() async {
      final page = _page(ink);
      final vec = await buildPdfDocument([
        PdfExportPage(width: 595, height: 842, vector: await _vector(page)),
      ]);
      final ras = await buildPdfDocument([
        PdfExportPage(
            width: 595, height: 842, flatPng: await _rasterPng(page, 4)),
      ]);
      // ignore: avoid_print
      print('vector ${vec.length} B vs raster ${ras.length} B');
      expect(vec.length, lessThan(ras.length));
      expect(String.fromCharCodes(vec.take(5)), '%PDF-');
    });
  });
}
