// Golden snapshots of CanvasNotifier: scripted public calls, then the whole
// editor state (normalised) compared with test/fixtures/editor_snapshots/.
// A refactor of the notifier must leave every file byte-identical.
// Regenerate on purpose with: UPDATE_SNAPSHOTS=1 flutter test <this file>.
//
// Normalised: uuids -> e1.., pg1.., c1.. in order of first appearance, doubles
// rounded to 2 decimals, timestamps dropped, stroke points summarised.
// Not covered here (native/timers/network): sync, save, PDF import, assets
// decode, symbols library files, pull timers.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Offset, Rect;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/providers/remote_store_provider.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/features/pages_tray/domain/page_transfer.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

const _nbId = '0c4a0000-characterization';
final _update = Platform.environment['UPDATE_SNAPSHOTS'] == '1';
const _dir = 'test/fixtures/editor_snapshots';

class _TempPaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _TempPaths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

// ---- fixtures -------------------------------------------------------------

String _idOf(ContentElement e) => e.map(
    unknown: (u) => u.id,
    stroke: (s) => s.id,
    text: (t) => t.id,
    image: (i) => i.id,
    shape: (s) => s.id,
    math: (m) => m.id);

ContentElement stroke(String id, List<Offset> pts,
        {int z = 0, String tool = 'pen', int color = 0xFF000000}) =>
    ContentElement.stroke(
      id: id,
      zIndex: z,
      data: StrokeData(
        points: [for (final p in pts) StrokePoint(x: p.dx, y: p.dy)],
        toolType: tool,
        color: color,
        baseWidth: 2,
      ),
    );

ContentElement text(String id, double x, double y, String content,
        {int z = 0}) =>
    ContentElement.text(
      id: id,
      zIndex: z,
      data: TextData(x: x, y: y, width: 160, height: 24, content: content),
    );

ContentElement shape(String id, String type, double x1, double y1, double x2,
        double y2,
        {int z = 0}) =>
    ContentElement.shape(
      id: id,
      zIndex: z,
      data: ShapeData(shapeType: type, x1: x1, y1: y1, x2: x2, y2: y2),
    );

ContentElement math(String id, double x, double y, {int z = 0}) =>
    ContentElement.math(
      id: id,
      zIndex: z,
      data: MathData(x: x, y: y, width: 60, height: 30, latex: r'x^2'),
    );

PageData page(String id, int number, List<ContentElement> content,
        {double w = 595, double h = 842, String bg = 'lined'}) =>
    PageData(
      pageId: id,
      pageNumber: number,
      width: w,
      height: h,
      layers: RenderingLayers(
          background: BackgroundLayer(type: bg), content: content),
    );

/// A horizontal line of [n] points from [x0] at height [y].
List<Offset> hline(double x0, double y, {int n = 8, double step = 10}) =>
    [for (var i = 0; i < n; i++) Offset(x0 + i * step, y)];

// ---- normalisation --------------------------------------------------------

class Norm {
  final _maps = <String, Map<String, String>>{};
  final _keep = <String, Set<String>>{};
  final _prefix = {
    'el': 'e',
    'pg': 'pg',
    'ch': 'c',
    'file': 'file',
    'asset': 'asset',
  };

  void keep(String kind, Iterable<String> values) =>
      (_keep[kind] ??= {}).addAll(values);

  String? id(String kind, String? raw) {
    if (raw == null) return null;
    if (_keep[kind]?.contains(raw) ?? false) return raw;
    final m = _maps[kind] ??= {};
    return m.putIfAbsent(raw, () => '${_prefix[kind]}${m.length + 1}');
  }
}

double _r(num v) {
  final x = (v * 100).round() / 100;
  return x == 0 ? 0.0 : x; // no "-0.0"
}

Map<String, dynamic> _pt(StrokePoint p) =>
    {'x': _r(p.x), 'y': _r(p.y), 'p': _r(p.pressure)};

Map<String, dynamic> _element(ContentElement e, Norm n) {
  final base = <String, dynamic>{'id': n.id('el', _idOf(e)), 'z': 0};
  return e.map(
    unknown: (u) => {...base, 'type': 'unknown', 'z': u.zIndex},
    stroke: (s) {
      final pts = s.data.points;
      var sx = 0.0, sy = 0.0;
      for (final p in pts) {
        sx += p.x;
        sy += p.y;
      }
      return {
        ...base,
        'type': 'stroke',
        'z': s.zIndex,
        'tool': s.data.toolType,
        'color': s.data.color,
        'width': _r(s.data.baseWidth),
        'hl': s.data.isHighlighter,
        'opacity': _r(s.data.opacity),
        'points': pts.length,
        'first': pts.isEmpty ? null : _pt(pts.first),
        'last': pts.isEmpty ? null : _pt(pts.last),
        'sum': [_r(sx), _r(sy)],
      };
    },
    text: (t) {
      final d = t.data;
      return {
        ...base,
        'type': 'text',
        'z': t.zIndex,
        'x': _r(d.x),
        'y': _r(d.y),
        'w': _r(d.width),
        'h': _r(d.height),
        'content': d.content,
        'font': d.fontFamily,
        'size': _r(d.fontSize),
        'color': d.color,
        'bold': d.bold,
        'italic': d.italic,
        'align': d.alignment,
        'spans': [
          for (final s in d.spans)
            [s.text, s.bold, s.italic, s.underline, s.strikethrough, s.color, s.fontSize]
        ],
      };
    },
    image: (i) {
      final d = i.data;
      return {
        ...base,
        'type': 'image',
        'z': i.zIndex,
        'x': _r(d.x),
        'y': _r(d.y),
        'w': _r(d.width),
        'h': _r(d.height),
        'asset': n.id('asset', d.assetPath),
        'rot': _r(d.rotation),
        'opacity': _r(d.opacity),
        'locked': d.locked,
        'flipH': d.flipHorizontal,
        'comment': d.comment,
        'pdfPt': [d.pdfWidthPt, d.pdfHeightPt],
      };
    },
    shape: (s) {
      final d = s.data;
      return {
        ...base,
        'type': 'shape',
        'z': s.zIndex,
        'shape': d.shapeType,
        'p1': [_r(d.x1), _r(d.y1)],
        'p2': [_r(d.x2), _r(d.y2)],
        'color': d.strokeColor,
        'width': _r(d.strokeWidth),
        'hl': d.isHighlighter,
        'fill': d.fillColor,
        'rot': _r(d.rotation),
        'vertices': [for (final v in d.vertices) _r(v)],
      };
    },
    math: (m) {
      final d = m.data;
      return {
        ...base,
        'type': 'math',
        'z': m.zIndex,
        'x': _r(d.x),
        'y': _r(d.y),
        'w': _r(d.width),
        'h': _r(d.height),
        'latex': d.latex,
        'display': d.displayMode,
        'color': d.color,
        'size': _r(d.fontSize),
      };
    },
  );
}

Map<String, dynamic> _page(PageData p, Norm n) {
  final bg = p.layers.background;
  return {
    'pageId': n.id('pg', p.pageId),
    'number': p.pageNumber,
    'size': [_r(p.width), _r(p.height)],
    'background': {
      'type': bg.type,
      'color': bg.color,
      'spacing': _r(bg.lineSpacing),
      'lineColor': bg.lineColor,
      'pdfAsset': bg.pdfAsset,
      'pdfPage': bg.pdfPage,
    },
    'pdfTextLayer': p.pdfTextLayer?.runs.length,
    'assetRefs': [for (final a in p.assetReferences) n.id('asset', a)],
    'content': [for (final e in p.layers.content) _element(e, n)],
  };
}

Map<String, dynamic> _rect(Rect r) =>
    {'l': _r(r.left), 't': _r(r.top), 'r': _r(r.right), 'b': _r(r.bottom)};

Map<String, dynamic> snapshot(CanvasState s, Norm n) {
  // File names first, in document order, so the numbering is stable.
  final files = [for (final e in s.document.pages) e.fileName];
  final extra = s.pages.keys.where((k) => !files.contains(k)).toList()..sort();
  final sel = s.lassoSelection;
  return {
    'document': [
      for (final e in s.document.pages)
        {
          'file': n.id('file', e.fileName),
          'pageId': n.id('pg', e.pageId),
          'number': e.pageNumber,
          'chapterId': n.id('ch', e.chapterId),
          'size': [_r(e.width), _r(e.height)],
        }
    ],
    'metadata': {
      'title': s.metadata.title,
      'pageCount': s.metadata.pageCount,
      'paperType': s.metadata.paperType,
      'chapters': [
        for (final c in s.metadata.chapters)
          {
            'id': n.id('ch', c.id),
            'title': c.title,
            'pageIds': [for (final p in c.pageIds) n.id('pg', p)],
          }
      ],
    },
    'pages': {
      for (final f in [...files, ...extra])
        n.id('file', f)!: _page(s.pages[f]!, n),
    },
    'currentPageIndex': s.currentPageIndex,
    'previousPageIndex': s.previousPageIndex,
    'activeChapterId': n.id('ch', s.activeChapterId),
    'tool': s.currentTool.name,
    'zoom': _r(s.zoom),
    'pan': [_r(s.panOffset.dx), _r(s.panOffset.dy)],
    'undo': [
      for (final u in s.undoStack)
        {
          'file': n.id('file', u.pageFileName),
          'ids': [for (final e in u.pageData.layers.content) n.id('el', _idOf(e))],
        }
    ],
    'redo': [
      for (final u in s.redoStack)
        {
          'file': n.id('file', u.pageFileName),
          'ids': [for (final e in u.pageData.layers.content) n.id('el', _idOf(e))],
        }
    ],
    'isDirty': s.isDirty,
    'selectedElementId': n.id('el', s.selectedElementId),
    'lasso': sel == null
        ? null
        : {
            'ids': [for (final i in sel.selectedIds) n.id('el', i)],
            'bounds': _rect(sel.bounds),
            'drag': [_r(sel.dragOffset.dx), _r(sel.dragOffset.dy)],
            'rotation': _r(sel.rotation),
            'scale': _r(sel.scale),
          },
    'lassoPath': s.lassoPath.length,
    'pendingPaste': s.pendingPaste,
    'pendingSymbol': s.pendingSymbol?.name,
    'activeStroke': s.activeStroke.length,
    'clipboard': s.clipboard == null
        ? null
        : {
            'ids': [for (final e in s.clipboard!.elements) n.id('el', _idOf(e))],
            'bounds': _rect(s.clipboard!.bounds),
          },
    'recognizedShape': s.recognizedShape == null
        ? null
        : {
            'shape': s.recognizedShape!.shapeType,
            'p1': [_r(s.recognizedShape!.x1), _r(s.recognizedShape!.y1)],
            'p2': [_r(s.recognizedShape!.x2), _r(s.recognizedShape!.y2)],
          },
    'toolSettings': {
      'color': s.toolSettings.color,
      'width': _r(s.toolSettings.strokeWidth),
      'opacity': _r(s.toolSettings.opacity),
      'shapeType': s.toolSettings.shapeType,
      'shapeRecognition': s.toolSettings.shapeRecognition,
    },
  };
}

/// Pretty JSON, one line for every map or list that holds only scalars.
String _fmt(Object? v, [String ind = '']) {
  bool flat(Object? x) =>
      x is Map ? x.values.every((e) => e is! Map && e is! List) : x is List ? x.every((e) => e is! Map && e is! List) : true;
  if (v is Map) {
    if (v.isEmpty) return '{}';
    if (flat(v)) return jsonEncode(v);
    final i2 = '$ind  ';
    return '{\n${v.entries.map((e) => '$i2${jsonEncode(e.key)}: ${_fmt(e.value, i2)}').join(',\n')}\n$ind}';
  }
  if (v is List) {
    if (v.isEmpty) return '[]';
    if (flat(v)) return jsonEncode(v);
    final i2 = '$ind  ';
    return '[\n${v.map((e) => '$i2${_fmt(e, i2)}').join(',\n')}\n$ind]';
  }
  return jsonEncode(v);
}

// ---- scenario runner ------------------------------------------------------

class Run {
  Run(this.n);
  final CanvasNotifier n;
  final norm = Norm();
  final steps = <Map<String, dynamic>>[];

  CanvasState get s => n.state!;
  PageData get cur => s.currentPage!;
  List<String> get ids => [for (final e in cur.layers.content) _idOf(e)];
  String id(int i) => ids[i];

  /// Runs [op], then records the whole state under [label].
  void step(String label, void Function() op) {
    op();
    steps.add({'op': label, 'state': snapshot(s, norm)});
  }

  Future<void> astep(String label, Future<void> Function() op) async {
    await op();
    steps.add({'op': label, 'state': snapshot(s, norm)});
  }

  void draw(List<Offset> pts) => n.commitAndEndStroke(
      [for (final p in pts) StrokePoint(x: p.dx, y: p.dy, pressure: 0.6)]);

  void lasso(List<Offset> poly) {
    n.setTool(CanvasTool.lasso);
    n.commitLassoPath(poly);
  }
}

late Directory _tmp;
late FileService _fs;

void scenario(
  String name,
  Map<String, PageData> pages,
  Future<void> Function(Run r) body, {
  List<Chapter> chapters = const [],
  Map<String, String> chapterOf = const {},
}) {
  test(name, () async {
    final c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(_fs),
      remoteStoreProvider.overrideWithValue(null),
    ]);
    addTearDown(c.dispose);
    final n = c.read(canvasProvider.notifier);
    final now = DateTime(2026);
    await n.openNotebook(
      metadata: NotebookMetadata(
          id: _nbId,
          title: 'Characterization',
          createdAt: now,
          modifiedAt: now,
          pageCount: pages.length,
          chapters: chapters),
      document: DocumentStructure(notebookId: _nbId, pages: [
        for (final (i, f) in pages.keys.indexed)
          PageEntry(
              pageId: pages[f]!.pageId,
              pageNumber: i + 1,
              fileName: f,
              chapterId: chapterOf[pages[f]!.pageId]),
      ]),
      pages: pages,
      remotePath: '/AbelNotes/characterization.abelnote',
    );
    n.setTool(CanvasTool.pen);
    final r = Run(n)..norm.keep('file', pages.keys);
    r.steps.add({'op': 'open', 'state': snapshot(n.state!, r.norm)});
    await body(r);

    final out = '${_fmt({'scenario': name, 'steps': r.steps})}\n';
    final file = File('$_dir/$name.json');
    if (_update) {
      file.createSync(recursive: true);
      file.writeAsStringSync(out);
    } else {
      expect(file.existsSync(), isTrue,
          reason: '$name.json missing: run with UPDATE_SNAPSHOTS=1');
      expect(out, file.readAsStringSync(), reason: '$name snapshot changed');
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _tmp = await Directory.systemTemp.createTemp('editor_characterization');
    PathProviderPlatform.instance = _TempPaths(_tmp.path);
    _fs = FileService();
    await _fs.init();
  });

  tearDown(() async {
    try {
      await _tmp.delete(recursive: true);
    } catch (_) {}
  });

  // 1. strokes and history
  scenario('strokes', {'p1.json': page('pg-a', 1, [])}, (r) async {
    r.step('pen stroke 1', () => r.draw(hline(50, 100)));
    r.step('pen stroke 2', () => r.draw(hline(50, 140)));
    r.step('single point dot', () => r.draw([const Offset(300, 300)]));
    r.step('highlighter stroke', () {
      r.n.setTool(CanvasTool.highlighter);
      r.draw(hline(50, 180));
    });
    r.step('brush stroke via start/continue/end', () {
      r.n.setTool(CanvasTool.brush);
      r.n.startStroke(const Offset(10, 10), 0.5);
      r.n.continueStroke(const Offset(20, 20), 0.5);
      r.n.endStroke();
    });
    r.step('empty commit', () => r.n.commitAndEndStroke([]));
    r.step('undo', r.n.undo);
    r.step('undo', r.n.undo);
    r.step('redo', r.n.redo);
    r.step('undo', r.n.undo);
    r.step('new stroke clears redo', () {
      r.n.setTool(CanvasTool.ballpoint);
      r.draw(hline(60, 400, n: 5));
    });
    r.step('redo no-op', r.n.redo);
    r.step('undo all', () {
      for (var i = 0; i < 10; i++) {
        r.n.undo();
      }
    });
    r.step('undo past start', r.n.undo);
    r.step('clear page', () => r.n.clearPage());
    r.step('undo clear page', r.n.undo);
  });

  // 2. eraser (stroke and area)
  scenario('eraser', {
    'p1.json': page('pg-a', 1, [
      stroke('s1', hline(50, 100, n: 20), z: 0),
      stroke('s2', hline(50, 200, n: 20), z: 1),
      stroke('s3', hline(50, 300, n: 20), z: 2),
      text('t1', 50, 400, 'erase me', z: 3),
      shape('h1', 'rectangle', 300, 450, 400, 520, z: 4),
      shape('h2', 'line', 50, 600, 250, 600, z: 5),
    ]),
  }, (r) async {
    r.step('stroke eraser across s1', () {
      r.n.setTool(CanvasTool.eraserStroke);
      r.n.startStroke(const Offset(100, 90), 0.5);
      r.n.continueStroke(const Offset(100, 105), 0.5);
      r.n.endStroke();
    });
    r.step('area eraser cuts s2 in the middle', () {
      r.n.setTool(CanvasTool.eraserStandard);
      r.n.startStroke(const Offset(140, 190), 0.5);
      r.n.continueStroke(const Offset(140, 202), 0.5);
      r.n.endStroke();
    });
    r.step('area eraser on text', () {
      r.n.startStroke(const Offset(100, 410), 0.5);
      r.n.endStroke();
    });
    r.step('area eraser on shape edge', () {
      r.n.startStroke(const Offset(300, 480), 0.5);
      r.n.endStroke();
    });
    r.step('area eraser on line shape', () {
      r.n.startStroke(const Offset(150, 600), 0.5);
      r.n.endStroke();
    });
    r.step('eraser on nothing', () {
      r.n.startStroke(const Offset(500, 750), 0.5);
      r.n.endStroke();
    });
    r.step('undo', r.n.undo);
    r.step('undo', r.n.undo);
    r.step('undo', r.n.undo);
    r.step('redo', r.n.redo);
    r.step('stroke eraser on s3 after undo', () {
      r.n.setTool(CanvasTool.eraserStroke);
      r.n.startStroke(const Offset(150, 300), 0.5);
      r.n.endStroke();
    });
    r.step('redo cleared', r.n.redo);
  });

  // 3. lasso
  scenario('lasso', {
    'p1.json': page('pg-a', 1, [
      stroke('s1', hline(100, 100, n: 6), z: 0),
      stroke('s2', hline(100, 140, n: 6), z: 1),
      stroke('s3', hline(400, 400, n: 6), z: 2),
      shape('h1', 'rectangle', 100, 200, 180, 260, z: 3),
      text('t1', 100, 300, 'lasso text', z: 4),
    ]),
  }, (r) async {
    const around = [
      Offset(80, 80), Offset(300, 80), Offset(300, 290), Offset(80, 290),
    ];
    r.step('lasso select s1 s2 h1', () => r.lasso(around));
    r.step('pending drag', () => r.n.commitSelectionTransform(
        dragOffset: const Offset(30, 20), rotation: 0, scale: 1));
    r.step('apply drag', r.n.applySelectionTransform);
    r.step('pending scale 1.5', () => r.n.commitSelectionTransform(
        dragOffset: Offset.zero, rotation: 0, scale: 1.5));
    r.step('apply scale', r.n.applySelectionTransform);
    r.step('pending rotate', () => r.n.commitSelectionTransform(
        dragOffset: Offset.zero, rotation: 0.5, scale: 1));
    r.step('apply rotate', r.n.applySelectionTransform);
    r.step('pending drag then undo settles it', () => r.n.commitSelectionTransform(
        dragOffset: const Offset(10, 10), rotation: 0.2, scale: 1.2));
    r.step('undo', r.n.undo);
    r.step('undo', r.n.undo);
    r.step('redo', r.n.redo);
    r.step('select all again', r.n.selectAll);
    r.step('change colour', () => r.n.changeSelectionColor(0xFFC62828));
    r.step('change width', () {
      r.n.changeSelectionStrokeWidth(5);
      r.n.endSelectionWidthEdit();
    });
    r.step('flip horizontal', r.n.flipSelectionHorizontal);
    r.step('flip vertical', r.n.flipSelectionVertical);
    r.step('delete selection', r.n.deleteSelection);
    r.step('undo delete', r.n.undo);
    r.step('select all', r.n.selectAll);
    r.step('clear lasso path', r.n.clearLassoPath);
    r.step('delete without selection', r.n.deleteSelection);
    r.step('lasso too short', () => r.n.commitLassoPath(const [Offset(1, 1), Offset(2, 2)]));
    r.step('lasso empty area', () => r.lasso(const [
          Offset(500, 600), Offset(560, 600), Offset(560, 660), Offset(500, 660),
        ]));
    r.step('lasso via start/continue/end', () {
      r.n.setTool(CanvasTool.lasso);
      r.n.startStroke(const Offset(5, 5), 0.5);
      r.n.continueStroke(const Offset(590, 5), 0.5);
      r.n.continueStroke(const Offset(590, 800), 0.5);
      r.n.continueStroke(const Offset(5, 800), 0.5);
      r.n.endStroke();
    });
    r.step('switch tool bakes pending transform', () {
      r.n.commitSelectionTransform(
          dragOffset: const Offset(5, 5), rotation: 0, scale: 1);
      r.n.setTool(CanvasTool.pen);
    });
  });

  // 4. clipboard
  scenario('clipboard', {
    'p1.json': page('pg-a', 1, [
      stroke('s1', hline(100, 100, n: 6), z: 0),
      text('t1', 100, 200, 'copy text', z: 1),
      shape('h1', 'circle', 300, 100, 360, 160, z: 2),
    ]),
    'p2.json': page('pg-b', 2, [stroke('s9', hline(50, 50), z: 0)]),
  }, (r) async {
    const around = [
      Offset(80, 80), Offset(260, 80), Offset(260, 260), Offset(80, 260),
    ];
    r.step('select', () => r.lasso(around));
    r.step('copy', r.n.copySelection);
    r.step('paste at', () => r.n.paste(at: const Offset(400, 500)));
    r.step('paste default position', () => r.n.paste());
    r.step('cut', r.n.cutSelection);
    r.step('paste after cut', () => r.n.paste(at: const Offset(300, 300)));
    r.step('duplicate selection', r.n.duplicateSelection);
    r.step('go to page 2', () => r.n.goToPage(1));
    r.step('paste on page 2', () => r.n.paste(at: const Offset(200, 200)));
    r.step('copy single element', () => r.n.copyElement(r.id(0)));
    r.step('paste single', () => r.n.paste(at: const Offset(100, 400)));
    r.step('cut single element', () => r.n.cutElement(r.id(0)));
    r.step('duplicate element (arms placement)', () => r.n.duplicateElement(r.id(0)));
    r.step('place duplicate', () => r.n.paste(at: const Offset(250, 250)));
    r.step('undo', r.n.undo);
    r.step('undo', r.n.undo);
    r.step('redo', r.n.redo);
    r.step('copy with no selection', () {
      r.n.clearSelection();
      r.n.copySelection();
    });
    r.step('cancel pending paste', () => r.n.cancelPendingPaste());
  });

  // 5. elements
  scenario('elements', {
    'p1.json': page('pg-a', 1, [
      text('t1', 50, 50, 'first', z: 0),
      shape('h1', 'rectangle', 200, 200, 300, 260, z: 1),
      math('m1', 50, 400, z: 2),
      stroke('s1', hline(300, 100), z: 3),
    ]),
  }, (r) async {
    r.step('add text', () => r.n.addTextElement(const Offset(100, 300), 'hello world'));
    r.step('add rich text', () => r.n.addTextElement(
        const Offset(500, 700), 'bold plain',
        fontSize: 20,
        color: 0xFF1565C0,
        alignment: 'center',
        spans: const [
          TextSpanData(text: 'bold ', bold: true),
          TextSpanData(text: 'plain'),
        ]));
    r.step('edit text', () => r.n.updateTextElement(r.id(0),
        content: 'edited content that is a bit longer',
        spans: const [],
        fontSize: 18,
        color: 0xFF000000,
        alignment: 'right'));
    r.step('resize text side handle', () => r.n.resizeTextElement(r.id(0), width: 90));
    r.step('resize text corner', () => r.n.resizeTextElement(r.id(0),
        width: 200, fontScale: 1.5, topLeft: const Offset(40, 40)));
    r.step('select shape', () => r.n.selectElement(r.id(1)));
    r.step('start drag + move shape', () {
      r.n.startDragElement(r.id(1));
      r.n.moveElement(r.id(1), const Offset(30, -10));
      r.n.moveElement(r.id(1), const Offset(5, 5));
    });
    r.step('resize shape', () =>
        r.n.resizeElement(r.id(1), const Rect.fromLTWH(220, 190, 160, 120)));
    r.step('rotate shape', () => r.n.rotateElement(r.id(1), 0.4));
    r.step('move stroke', () => r.n.moveElement(r.id(3), const Offset(0, 50)));
    r.step('resize stroke', () =>
        r.n.resizeElement(r.id(3), const Rect.fromLTWH(300, 150, 200, 40)));
    r.step('move math', () => r.n.moveElement(r.id(2), const Offset(10, 10)));
    r.step('resize math', () =>
        r.n.resizeElement(r.id(2), const Rect.fromLTWH(50, 410, 120, 60)));
    r.step('bring to front', () => r.n.bringToFront(r.id(0)));
    r.step('send to back', () => r.n.sendToBack(r.id(r.ids.length - 1)));
    r.step('shape tool drag', () {
      r.n.setTool(CanvasTool.shape);
      r.n.setToolSettings(r.s.toolSettings.copyWith(shapeType: 'circle'));
      r.n.startStroke(const Offset(400, 400), 0.5);
      r.n.continueStroke(const Offset(460, 430), 0.5);
      r.n.endStroke();
    });
    r.step('shape tool arrow', () {
      r.n.setToolSettings(r.s.toolSettings.copyWith(shapeType: 'arrow'));
      r.n.startStroke(const Offset(100, 600), 0.5);
      r.n.continueStroke(const Offset(300, 640), 0.5);
      r.n.endStroke();
    });
    r.step('delete element', () => r.n.deleteElement(r.id(1)));
    r.step('delete unknown id', () => r.n.deleteElement('nope'));
    r.step('deselect', r.n.deselectElement);
    r.step('undo', r.n.undo);
    r.step('undo', r.n.undo);
    r.step('undo', r.n.undo);
    r.step('redo', r.n.redo);
  });

  // 5a. math: measured by really rasterizing glyphs, so sizes depend on the
  // bundled fonts; kept apart so a font change only touches this file.
  scenario('math', {
    'p1.json': page('pg-a', 1, [
      math('m1', 50, 400, z: 0),
      stroke('s1', hline(300, 100), z: 1),
    ]),
  }, (r) async {
    await r.astep('update math latex', () async {
      await r.n.updateMathLatex(r.id(0), r'\frac{a}{b}');
    });
    await r.astep('same latex is a no-op', () async {
      await r.n.updateMathLatex(r.id(0), r'\frac{a}{b}');
    });
    await r.astep('replace ink with math', () async {
      await r.n.replaceInkWithMath(r.s.currentPageFileName, {r.id(1)}, r'y=2x');
    });
    r.step('undo', r.n.undo);
    r.step('undo', r.n.undo);
    r.step('redo', r.n.redo);
  });

  // 5b. pictures
  scenario('images', {
    'p1.json': page('pg-a', 1, [stroke('s1', hline(50, 50), z: 0)]),
  }, (r) async {
    final png = Uint8List.fromList(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));
    String? aid;
    r.step('add image', () {
      aid = r.n.addImageElement(const Offset(100, 100), 'a.png', png, 200, 100);
    });
    r.step('add same bytes again (dedup)', () {
      r.n.addImageElement(const Offset(100, 300), 'b.png', png, 80, 80, locked: true);
    });
    r.step('flip image', () => r.n.flipImageElement(r.id(1)));
    r.step('toggle lock', () => r.n.toggleImageLock(r.id(1)));
    r.step('comment', () => r.n.setImageComment(r.id(1), 'a note'));
    r.step('rotate image', () => r.n.rotateElement(r.id(1), 0.3));
    r.step('resize image', () =>
        r.n.resizeElement(r.id(1), const Rect.fromLTWH(100, 100, 100, 50)));
    r.step('copy image', () => r.n.copyElement(r.id(1)));
    r.step('paste image', () => r.n.paste(at: const Offset(400, 400)));
    r.step('delete image', () => r.n.deleteElement(r.id(1)));
    r.step('undo', r.n.undo);
    expect(aid, isNotNull);
  });

  // 6. pages
  scenario('pages', {
    'p1.json': page('pg-a', 1, [stroke('s1', hline(50, 50), z: 0)]),
    'p2.json': page('pg-b', 2, [text('t1', 50, 50, 'two', z: 0)], bg: 'grid'),
    'p3.json': page('pg-c', 3, [shape('h1', 'circle', 50, 50, 90, 90, z: 0)]),
  }, (r) async {
    r.step('add page', r.n.addPage);
    r.step('insert page at 1', () => r.n.insertPageAt(1));
    r.step('duplicate page 0', () => r.n.duplicatePage(0));
    r.step('go to 2 and set paper', () {
      r.n.goToPage(2);
      r.n.setPaperType(PaperType.dotted);
    });
    r.step('line spacing', () => r.n.setLineSpacing(42));
    r.step('page size', () => r.n.setPageSize(420, 595));
    r.step('page size same (no-op)', () => r.n.setPageSize(420, 595));
    r.step('paper type music', () => r.n.setPaperType(PaperType.music));
    r.step('undo paper', r.n.undo);
    r.step('undo size', r.n.undo);
    r.step('redo size', r.n.redo);
    r.step('page geometry', () => r.n.setPageGeometry(r.s.currentPageFileName, 300, 400));
    r.step('pdf text layer', () => r.n.setPageTextLayer(
        r.s.currentPageFileName,
        const PdfTextLayer(sourceAssetPath: 'x.pdf_p1', runs: [
          PdfTextRun(text: 'hi', x: 1, y: 2, width: 10, height: 5),
        ])));
    r.step('edit page with text layer (carry)', () => r.draw(hline(10, 10)));
    r.step('nav next', () => r.n.nextPage());
    r.step('nav prev', () => r.n.prevPage());
    r.step('nav out of range', () => r.n.goToPage(99));
    r.step('go to 0 reset viewport', () => r.n.goToPage(0, resetViewport: true));
    r.step('move page 0 to position 3', () => r.n.movePagesToPosition([0], 3));
    r.step('move two pages to position 1', () => r.n.movePagesToPosition([2, 4], 1));
    r.step('delete page 1', () => r.n.deletePage(1));
    r.step('delete pages 0 and 2', () => r.n.deletePages([0, 2]));
    r.step('delete out of range', () => r.n.deletePage(42));
    r.step('delete all but one', () {
      while (r.s.pageCount > 1) {
        r.n.deletePage(0);
      }
    });
    r.step('delete last page refused', () => r.n.deletePage(0));
  });

  // 7. chapters
  scenario('chapters', {
    'p1.json': page('pg-a', 1, [stroke('s1', hline(50, 50), z: 0)]),
    'p2.json': page('pg-b', 2, []),
    'p3.json': page('pg-c', 3, []),
    'p4.json': page('pg-d', 4, []),
  }, (r) async {
    r.step('add chapter A', () => r.n.addChapter('A'));
    r.step('add chapter B', () => r.n.addChapter('B'));
    r.step('rename A', () => r.n.renameChapter(r.s.metadata.chapters[0].id, 'Alpha'));
    r.step('reorder chapters', () => r.n.reorderChapters(0, 1));
    r.step('reorder out of range', () => r.n.reorderChapters(5, 0));
    r.step('assign page 0 to chapter A', () =>
        r.n.assignPageToChapter(0, r.s.metadata.chapters.last.id));
    r.step('assign pages 1 and 2 to chapter B', () => r.n.assignPagesToChapter(
        [1, 2], r.s.metadata.chapters.first.id));
    r.step('assign out of range', () => r.n.assignPageToChapter(99, null));
    r.step('set active chapter B', () =>
        r.n.setActiveChapter(r.s.metadata.chapters.first.id));
    r.step('next in chapter', () => r.n.nextPage());
    r.step('next in chapter', () => r.n.nextPage());
    r.step('next at chapter end', () => r.n.nextPage());
    r.step('prev in chapter', () => r.n.prevPage());
    r.step('add page inside chapter', r.n.addPage);
    r.step('set unknown chapter', () => r.n.setActiveChapter('ghost'));
    r.step('set active chapter A', () =>
        r.n.setActiveChapter(r.s.metadata.chapters.last.id));
    r.step('move page to slot', () => r.n.movePagesToSlot(
        {r.s.document.pages[0].pageId},
        PasteSlot(
            afterPageId: r.s.document.pages.last.pageId,
            chapterId: r.s.metadata.chapters.first.id)));
    r.step('delete active chapter', () => r.n.deleteChapter(r.s.activeChapterId!));
    r.step('set no chapter', () => r.n.setActiveChapter(null));
    r.step('delete pages by id', () => r.n.deletePagesById(
        {r.s.document.pages[1].pageId, r.s.document.pages[2].pageId}));
    r.step('delete other chapter', () => r.n.deleteChapter(r.s.metadata.chapters.first.id));
  });

  // 8. long mixed sequence
  scenario('mixed', {
    'p1.json': page('pg-a', 1, [
      stroke('s1', hline(100, 100, n: 6), z: 0),
      shape('h1', 'rectangle', 100, 200, 180, 260, z: 1),
    ]),
    'p2.json': page('pg-b', 2, [text('t1', 60, 60, 'page two', z: 0)]),
  }, (r) async {
    const around = [
      Offset(80, 80), Offset(300, 80), Offset(300, 290), Offset(80, 290),
    ];
    r.step('1 draw', () => r.draw(hline(50, 400)));
    r.step('2 draw', () => r.draw(hline(50, 440)));
    r.step('3 text', () => r.n.addTextElement(const Offset(200, 500), 'mixed'));
    r.step('4 undo', r.n.undo);
    r.step('5 redo', r.n.redo);
    r.step('6 lasso', () => r.lasso(around));
    r.step('7 transform', () => r.n.commitSelectionTransform(
        dragOffset: const Offset(20, 20), rotation: 0.3, scale: 1.1));
    r.step('8 undo with pending', r.n.undo);
    r.step('9 undo', r.n.undo);
    r.step('10 redo', r.n.redo);
    r.step('11 select all + copy', () {
      r.n.selectAll();
      r.n.copySelection();
    });
    r.step('12 add page', r.n.addPage);
    r.step('13 paste in new page', () => r.n.paste(at: const Offset(300, 300)));
    r.step('14 undo', r.n.undo);
    r.step('15 go back', () => r.n.goToPage(0));
    r.step('16 undo on page 0 (per-page history)', r.n.undo);
    r.step('17 add chapter', () => r.n.addChapter('Ch'));
    r.step('18 draw in chapter page', () => r.draw(hline(70, 70)));
    r.step('19 set paper', () => r.n.setPaperType(PaperType.grid));
    r.step('20 active none', () => r.n.setActiveChapter(null));
    r.step('21 goto p2', () => r.n.goToPage(
        r.s.document.pages.indexWhere((e) => e.fileName == 'p2.json')));
    r.step('22 edit text', () => r.n.updateTextElement(r.id(0),
        content: 'changed',
        spans: const [],
        fontSize: 20,
        color: 0xFF000000,
        alignment: 'left'));
    r.step('23 eraser stroke', () {
      r.n.setTool(CanvasTool.eraserStroke);
      r.n.startStroke(const Offset(100, 72), 0.5);
      r.n.endStroke();
    });
    r.step('24 undo', r.n.undo);
    r.step('25 undo', r.n.undo);
    r.step('26 redo', r.n.redo);
    r.step('27 duplicate page', () => r.n.duplicatePage(1));
    r.step('28 delete page', () => r.n.deletePage(0));
    r.step('29 undo on remaining page', r.n.undo);
    r.step('30 select all + delete', () {
      r.n.selectAll();
      r.n.deleteSelection();
    });
    r.step('31 undo', r.n.undo);
    r.step('32 page size', () => r.n.setPageSize(500, 500));
    r.step('33 move page', () => r.n.movePagesToPosition([0], 3));
    r.step('34 undo', r.n.undo);
    r.step('35 redo', r.n.redo);
    r.step('36 new stroke clears redo', () => r.draw(hline(20, 20)));
    r.step('37 zoom pan', () {
      r.n.setZoomAndPan(3.0, const Offset(10, 20));
      r.n.zoomBy(1.5);
    });
    r.step('38 reset zoom', r.n.resetZoom);
  });

  // 9. shape recognition (hold-to-recognize path, no UI timers)
  scenario('shape_recognition', {
    'p1.json': page('pg-a', 1, []),
  }, (r) async {
    r.step('enable recognition', () => r.n.setToolSettings(
        r.s.toolSettings.copyWith(shapeRecognition: true)));
    List<StrokePoint> pts(List<Offset> o) =>
        [for (final p in o) StrokePoint(x: p.dx, y: p.dy, pressure: 0.5)];
    final line = [for (var i = 0; i <= 12; i++) Offset(100 + i * 15.0, 200 + i * 0.5)];
    final box = [
      for (var i = 0; i <= 10; i++) Offset(100 + i * 20.0, 100),
      for (var i = 1; i <= 10; i++) Offset(300, 100 + i * 15.0),
      for (var i = 1; i <= 10; i++) Offset(300 - i * 20.0, 250),
      for (var i = 1; i <= 10; i++) Offset(100, 250 - i * 15.0),
    ];
    r.step('held line recognized', () => r.n.recognizeHeldStroke(pts(line)));
    r.step('adjust line endpoint', () => r.n.setRecognizedLineEndpoint(const Offset(400, 260)));
    r.step('commit line', r.n.commitRecognizedShape);
    r.step('held rectangle recognized', () => r.n.recognizeHeldStroke(pts(box)));
    r.step('adjust rectangle', () => r.n.adjustRecognizedShape(const Offset(340, 300)));
    r.step('resize recognized', () => r.n.resizeRecognizedShape(const Offset(360, 320)));
    r.step('dismiss recognized', r.n.dismissRecognizedShape);
    r.step('held rectangle again then commit', () {
      r.n.recognizeHeldStroke(pts(box));
      r.n.commitRecognizedShape();
    });
    r.step('too few points', () => r.n.recognizeHeldStroke(pts(line.take(3).toList())));
    r.step('recognition on endStroke', () {
      r.n.startStroke(const Offset(100, 400), 0.5);
      r.n.state = r.s.copyWith(activeStroke: pts(box));
      r.n.endStroke();
    });
    r.step('undo', r.n.undo);
    r.step('undo', r.n.undo);
  });
}
