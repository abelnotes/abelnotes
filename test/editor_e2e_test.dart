// The whole editor driven by pointer events (Phase 0, Tier A of
// test/work/arch-split/PLAN.md). Each scenario asserts what reached the page
// state, so moving code around cannot change behaviour silently.

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/editor_harness.dart';

void main() {
  // The web has no native drop zone around the canvas: the sheet once
  // collapsed to 0x0 there (blank pages on the PWA).
  testEditor('the page area fills the editor without a drop zone', (h) async {
    final top = h.tester.hitTestOnBinding(h.canvasCenter).path.first.target;
    expect(top, isA<RenderCustomPaint>(), reason: 'the canvas painter is under the centre');
  });

  testEditor('a pen stroke lands on the page, undo removes it, redo brings it back',
      (h) async {
    expect(h.strokeCount, 0);
    await h.scribble(h.canvasCenter);
    expect(h.strokeCount, 1);
    h.notifier.undo();
    await h.tester.pump();
    expect(h.strokeCount, 0);
    h.notifier.redo();
    await h.tester.pump();
    expect(h.strokeCount, 1);
  });

  testEditor('a finger draws by default (finger mode on)', (h) async {
    await h.scribble(h.canvasCenter, kind: PointerDeviceKind.touch);
    expect(h.strokeCount, 1);
  });
}
