// The movable tool dock through real drags of its grip: snap to every edge,
// into the top bar, and back out of it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';

import 'support/editor_harness.dart';

Finder get grip => find.byTooltip('Drag to move the toolbar').hitTestable();

/// A small first move: the drag starts where the pointer is once the slop is
/// passed, so a big first step would be lost.
Future<void> grab(EditorHarness h, TestGesture g, Offset from, Offset to) async {
  final dir = (to - from) / (to - from).distance;
  await g.moveTo(from + dir * 30);
  await h.tester.pump(const Duration(milliseconds: 16));
}

/// Drags the grip to [to] (screen coordinates) and lets the fly-to-edge end.
Future<void> dragGrip(EditorHarness h, Offset to) async {
  final from = h.tester.getCenter(find.byTooltip('Drag to move the toolbar').first);
  final g = await h.tester.startGesture(from);
  await grab(h, g, from, to);
  for (var i = 1; i <= 8; i++) {
    await g.moveTo(Offset.lerp(from, to, i / 8)!);
    await h.tester.pump(const Duration(milliseconds: 16));
  }
  await h.tester.pump(const Duration(milliseconds: 200));
  await g.up();
  await h.tester.pump(const Duration(seconds: 2));
}

String edgeOf(EditorHarness h) => h.container.read(appSettingsProvider).toolDock.edge;

void main() {
  testEditor('the dock snaps to the edge nearest where it is dropped', (h) async {
    final s = h.surface;
    expect(edgeOf(h), 'bottom');
    await dragGrip(h, Offset(40, s.height / 2));
    expect(edgeOf(h), 'left');
    await dragGrip(h, Offset(s.width - 30, s.height / 2));
    expect(edgeOf(h), 'right');
    await dragGrip(h, Offset(s.width / 2, 120));
    expect(edgeOf(h), 'top');
    await dragGrip(h, Offset(s.width / 2, s.height - 60));
    expect(edgeOf(h), 'bottom');
  });

  testEditor('dropped on the top bar the dock goes into it, and comes out again', (h) async {
    final s = h.surface;
    await dragGrip(h, Offset(s.width / 2, 20));
    expect(edgeOf(h), 'bar');
    // The tools are in the bar now: one dock, no floating copy left behind.
    expect(find.byTooltip('Drag to move the toolbar'), findsOneWidget);
    await dragGrip(h, Offset(s.width / 2, s.height - 60));
    expect(edgeOf(h), 'bottom');
    expect(find.byTooltip('Drag to move the toolbar'), findsOneWidget);
  });

  testEditor('a dock in the bar dragged out follows the pointer, then lands', (h) async {
    final s = h.surface;
    await dragGrip(h, Offset(s.width / 2, 20));
    expect(edgeOf(h), 'bar');
    final from = h.tester.getCenter(find.byTooltip('Drag to move the toolbar'));
    final g = await h.tester.startGesture(from);
    await grab(h, g, from, from + const Offset(0, 300));
    await g.moveTo(from + const Offset(0, 120));
    await h.tester.pump(const Duration(milliseconds: 16));
    await g.moveTo(from + const Offset(0, 300));
    await h.tester.pump(const Duration(milliseconds: 16));
    // Mid-drag the grip still answers and a second dock copy follows.
    expect(find.byTooltip('Drag to move the toolbar'), findsWidgets);
    await g.up();
    await h.tester.pump(const Duration(seconds: 2));
    expect(h.tester.takeException(), isNull);
  });

  testEditor('a narrow window never docks into the bar', (h) async {
    final s = h.surface;
    await dragGrip(h, Offset(s.width / 2, 20));
    expect(edgeOf(h), isNot('bar'));
  }, size: const Size(600, 800));
}
