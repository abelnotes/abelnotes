// The tool-prefs debounce must not outlive the notifier, and a pref changed
// just before the editor closes must still be saved.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

CanvasState _state() {
  final now = DateTime(2026);
  return CanvasState(
    metadata: NotebookMetadata(id: 'n', title: 't', createdAt: now, modifiedAt: now),
    document: const DocumentStructure(notebookId: 'n', pages: [
      PageEntry(pageId: 'p1', pageNumber: 1, fileName: 'p1.json'),
    ]),
    pages: {
      'p1.json': const PageData(
          pageId: 'p1',
          pageNumber: 1,
          width: 595,
          height: 842,
          layers: RenderingLayers(content: [])),
    },
    currentPageIndex: 0,
    currentTool: CanvasTool.pen,
    remotePath: '',
  );
}

void main() {
  testWidgets('disposing the notifier saves pending tool prefs and leaves no timer',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    final n = c.read(canvasProvider.notifier);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    n.state = _state();
    n.setToolSettings(
        n.state!.toolSettings.copyWith(strokeWidth: 7.5, color: 0xFF112233));
    c.dispose();
    // A pending timer here fails the test at teardown.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    final raw = prefs!.getString('canvas_tool_prefs_v1');
    expect(raw, isNotNull);
    final pen = (jsonDecode(raw!) as Map)['tools']['pen'] as Map;
    expect(pen['strokeWidth'], 7.5);
    expect(pen['color'], 0xFF112233);
  });
}
