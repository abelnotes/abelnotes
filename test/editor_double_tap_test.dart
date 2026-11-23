// Double tap on the canvas toggles zoom-to-fit and the default zoom, from the
// zoom the page has NOW, not the one it had when the screen last built.

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/editor_harness.dart';

Future<void> doubleTap(EditorHarness h) async {
  final at = h.canvasCenter;
  for (var i = 0; i < 2; i++) {
    final g = await h.tester.startGesture(at, kind: PointerDeviceKind.touch);
    await h.tester.pump(const Duration(milliseconds: 30));
    await g.up();
    await h.tester.pump(const Duration(milliseconds: 60));
  }
  await h.tester.pump(const Duration(milliseconds: 400));
}

/// Pan tool at [zoom], with the screen rebuilt at that zoom (a tool change
/// rebuilds it; a zoom alone does not).
Future<void> panToolAt(EditorHarness h, double zoom) async {
  // Around the centre, so the page stays in view (off to the side, a tap
  // would count as a page swipe).
  h.notifier.zoomBy(zoom / h.state.zoom);
  await h.tester.sendKeyEvent(LogicalKeyboardKey.keyT);
  await h.tester.pump(const Duration(milliseconds: 100));
  await h.tester.sendKeyEvent(LogicalKeyboardKey.keyH);
  await h.tester.pump(const Duration(milliseconds: 100));
  expect(h.state.zoom, zoom);
}

void main() {
  testEditor('double tap after zooming in fits the page instead of resetting', (h) async {
    await panToolAt(h, 1.0);
    // The screen's build still holds zoom 1.0 after this.
    h.notifier.zoomBy(2.5);
    await h.tester.pump(const Duration(milliseconds: 100));
    await doubleTap(h);
    expect(h.state.zoom, lessThan(1.4), reason: 'zoomed in: the toggle fits the page');
  });

  testEditor('double tap toggles between the default zoom and fit, twice in a row', (h) async {
    await panToolAt(h, 1.0);
    await doubleTap(h);
    expect(h.state.zoom, 2.0);
    await doubleTap(h);
    expect(h.state.zoom, lessThan(1.4));
    await doubleTap(h);
    expect(h.state.zoom, 2.0);
  });
}
