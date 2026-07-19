// Regression: the painter's manual element-type dispatch assumed any
// non-stroke/text/image element was a ShapeElement and did `as ShapeElement`.
// A MathElement (added later) fell into that branch and the cast threw on
// EVERY frame, so pasted LaTeX never rendered. Guard all three dispatch sites
// (_paintStaticLayers, _elementCenter, _elementTopLeft) by painting a math
// element — once statically, once under a live transform (which exercises the
// center/top-left anchors).

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

PageData _pageWithMath() => PageData(
      pageId: 'p1',
      pageNumber: 0,
      width: 400,
      height: 600,
      layers: const RenderingLayers(
        content: [
          ContentElement.math(
            id: 'm1',
            zIndex: 0,
            data: MathData(
              x: 10,
              y: 10,
              width: 120,
              height: 40,
              latex: r'\int_0^1 x^2\,dx',
            ),
          ),
        ],
      ),
    );

void _paint(CanvasRenderEngine engine) {
  final recorder = ui.PictureRecorder();
  engine.paint(Canvas(recorder), const Size(400, 600));
  recorder.endRecording().dispose();
}

void main() {
  test('painting a MathElement does not throw (static)', () {
    expect(() => _paint(CanvasRenderEngine(pageData: _pageWithMath())),
        returnsNormally);
  });

  test('painting a MathElement under a live transform does not throw', () {
    // Non-identity scale + rotation drives _elementTopLeft and _elementCenter,
    // the other two sites that used `as ShapeElement`.
    final engine = CanvasRenderEngine(
      pageData: _pageWithMath(),
      liveElementTransform: () => (
        elementId: 'm1',
        dragOffset: const Offset(5, 5),
        rotationDelta: 0.2,
        scaleW: 1.5,
        scaleH: 1.5,
      ),
    );
    expect(() => _paint(engine), returnsNormally);
  });
}
