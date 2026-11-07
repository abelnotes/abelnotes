// Where a page lands when a notebook opens or the view is reset (zoom 2).
// screen = (page * fit + fitCentre) * zoom + pan, as in the canvas.

import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';

const phone = Size(411, 731);
const desktop = Size(1200, 800);
const a4 = Size(595, 842);
const a5Landscape = Size(595, 420);
const square = Size(600, 600);

({double top, double bottom}) placed(Size vp, Size page, double zoom) {
  final fit = min(vp.width / page.width, vp.height / page.height);
  final fitTop = (vp.height - page.height * fit) / 2;
  final pan = CanvasNotifier.centeredPanIn(vp, zoom, page);
  final top = fitTop * zoom + pan.dy;
  return (top: top, bottom: top + page.height * fit * zoom);
}

void main() {
  test('a page taller than the screen starts at the top', () {
    expect(placed(phone, a4, 2).top, closeTo(0, 1e-9));
    expect(placed(phone, square, 2).top, closeTo(0, 1e-9));
  });

  test('a page that fits the height is centred down the screen', () {
    final p = placed(phone, a5Landscape, 2);
    expect(p.top, greaterThan(0));
    expect(p.top, closeTo(phone.height - p.bottom, 1e-9));
  });

  test('desktop and the fitted view are unchanged', () {
    for (final page in [a4, a5Landscape, square]) {
      // Zoom 1 is the plain fit: no pan at all.
      expect(CanvasNotifier.centeredPanIn(desktop, 1, page).dy,
          closeTo(0, 1e-9));
      expect(CanvasNotifier.centeredPanIn(phone, 1, page).dy,
          closeTo(0, 1e-9));
    }
    // A height-limited fit had no band to begin with.
    expect(CanvasNotifier.centeredPanIn(desktop, 2, a4).dy, closeTo(0, 1e-9));
  });

  test('horizontal centring is as before', () {
    for (final page in [a4, a5Landscape, null]) {
      expect(CanvasNotifier.centeredPanIn(phone, 2, page).dx,
          phone.width * (1 - 2) / 2);
    }
    expect(CanvasNotifier.centeredPanIn(phone, 2, null).dy, 0);
  });
}
