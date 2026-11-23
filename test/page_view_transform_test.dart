import 'dart:math';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/features/canvas/presentation/editor/page_view_transform.dart';

// The formulas as they were open-coded in canvas_screen.dart.
double oldRenderScale(bool scratch, double pw, double ph, Size c) {
  if (scratch) return 1.0;
  return min(c.width / pw, c.height / ph);
}

Offset oldCenter(bool scratch, double pw, double ph, Size c) {
  if (scratch) return Offset.zero;
  final rs = min(c.width / pw, c.height / ph);
  return Offset((c.width - pw * rs) / 2, (c.height - ph * rs) / 2);
}

Offset oldToPage(Offset local, bool scratch, double pw, double ph, Size c,
    double zoom, Offset pan) {
  final rs = oldRenderScale(scratch, pw, ph, c);
  final center = oldCenter(scratch, pw, ph, c);
  final unPanned = local - pan - center * zoom;
  final unZoomed = unPanned / zoom;
  return unZoomed / rs;
}

Offset oldToScreen(Offset page, bool scratch, double pw, double ph, Size c,
    double zoom, Offset pan) {
  final rs = oldRenderScale(scratch, pw, ph, c);
  final center = oldCenter(scratch, pw, ph, c);
  final scaled = page * rs;
  return scaled * zoom + pan + center * zoom;
}

({double left, double right}) oldEdges(
    double pw, double ph, Size c, double zoom, double panX) {
  final rs = min(c.width / pw, c.height / ph);
  final scaledW = pw * rs;
  final cx = (c.width - scaledW) / 2;
  return (left: panX + (cx * zoom), right: (scaledW * zoom) + panX + (cx * zoom));
}

void main() {
  const canvases = [Size(1024, 700), Size(390, 780), Size(1920.5, 1013.25)];
  const pages = [(595.0, 842.0), (842.0, 595.0), (1000.0, 1000.0), (210.0, 297.5)];
  const zooms = [1.0, 0.37, 2.5, 5.0];
  const pans = [Offset.zero, Offset(-120.5, 33.25), Offset(400, -900)];
  const points = [Offset.zero, Offset(10, 20), Offset(333.3, 77.7), Offset(-5, 900)];

  for (final scratch in [false, true]) {
    test('matches the old formulas (${scratch ? 'scratch' : 'paged'})', () {
      for (final c in canvases) {
        for (final (pw, ph) in pages) {
          for (final z in zooms) {
            for (final pan in pans) {
              final t = PageViewTransform(
                  pageWidth: pw,
                  pageHeight: ph,
                  canvasSize: c,
                  isScratch: scratch,
                  zoom: z,
                  pan: pan);
              expect(t.renderScale, oldRenderScale(scratch, pw, ph, c));
              expect(t.center, oldCenter(scratch, pw, ph, c));
              for (final p in points) {
                expect(t.toPage(p), oldToPage(p, scratch, pw, ph, c, z, pan));
                expect(t.toScreen(p), oldToScreen(p, scratch, pw, ph, c, z, pan));
              }
              if (!scratch) {
                final e = oldEdges(pw, ph, c, z, pan.dx);
                expect(t.pageLeftScreen(pan.dx), e.left);
                expect(t.pageRightScreen(pan.dx), e.right);
              }
            }
          }
        }
      }
    });
  }

  test('toPage inverts toScreen', () {
    const t = PageViewTransform(
        pageWidth: 595,
        pageHeight: 842,
        canvasSize: Size(1024, 700),
        isScratch: false,
        zoom: 1.7,
        pan: Offset(-40, 12));
    final p = t.toPage(t.toScreen(const Offset(123, 456)));
    expect((p - const Offset(123, 456)).distance, lessThan(1e-9));
  });
}
