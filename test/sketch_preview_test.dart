// A sketch tile shows its ink on every device: a missing or old portrait
// thumbnail is rendered from the sketch's own data, once.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/notebook/page_codec.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/thumbnail_service.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/ui/screens/library_screen.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

const _id = '5ce7c4a0-sketch-preview-test';

PageData _sketchPage() => const PageData(
      pageId: 'p1',
      pageNumber: 1,
      width: AppConfig.scratchPageSize,
      height: AppConfig.scratchPageSize,
      layers: RenderingLayers(content: [
        ContentElement.stroke(
            id: 's',
            zIndex: 0,
            data: StrokeData(baseWidth: 4, points: [
              StrokePoint(x: 3000, y: 3000),
              StrokePoint(x: 3300, y: 3100),
            ])),
      ]),
    );

({int w, int h}) _size(Uint8List png) {
  final d = ByteData.sublistView(png);
  return (w: d.getUint32(16), h: d.getUint32(20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late FileService fs;
  late ThumbnailService thumbs;
  final now = DateTime(2026, 11, 1);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sketch_preview_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    fs = FileService();
    await fs.init();
    thumbs = ThumbnailService();
    await thumbs.init();
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> storeSketch() async {
    final meta = NotebookMetadata(
        id: _id,
        title: 'Sketch',
        createdAt: now,
        modifiedAt: now,
        paperType: AppConfig.infinitePaperType);
    const doc = DocumentStructure(notebookId: _id, pages: [
      PageEntry(pageId: 'p1', pageNumber: 1, fileName: 'p1.json'),
    ]);
    Uint8List json(Object o) => Uint8List.fromList(utf8.encode(jsonEncode(o)));
    await fs.saveNotebookIncremental(
      _id,
      metadataJson: json(meta.toJson()),
      documentJson: json(doc.toJson()),
      changedPages: {'p1.json': encodePageBytes(_sketchPage())},
    );
  }

  Future<void> pump(WidgetTester tester, {bool notOnDevice = false}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        fileServiceProvider.overrideWithValue(fs),
        thumbnailServiceProvider.overrideWithValue(thumbs),
      ],
      child: MaterialApp(
        home: SizedBox(
          width: 200,
          height: 140,
          child: SketchPreview(
            entry: NotebookEntry(
              metadata: NotebookMetadata(
                  id: _id,
                  title: 'Sketch',
                  createdAt: now,
                  modifiedAt: now,
                  paperType: AppConfig.infinitePaperType),
              remotePath: '/AbelNotes/$_id.abelnote',
              notOnDevice: notOnDevice,
            ),
            dots: Colors.grey,
          ),
        ),
      ),
    ));
    // Real IO and isolates, with fake timers: alternate until it settles.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a portrait thumbnail is replaced by a landscape one and shown',
      (tester) async {
    await tester.runAsync(() async {
      await storeSketch();
      final old = await thumbs.renderPng(_sketchPage());
      await File(thumbs.thumbnailPath(_id)).writeAsBytes(old!);
      expect(_size(old).h, greaterThan(_size(old).w));
    });
    await pump(tester);

    final png = await tester.runAsync(
        () => File(thumbs.thumbnailPath(_id)).readAsBytes());
    expect(_size(png!).w, greaterThan(_size(png).h));
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a sketch with no thumbnail gets one', (tester) async {
    await tester.runAsync(storeSketch);
    await pump(tester);
    expect(await tester.runAsync(() => thumbs.hasThumbnail(_id)), isTrue);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a sketch not held on this device keeps the dots and renders '
      'nothing', (tester) async {
    await tester.runAsync(storeSketch);
    await pump(tester, notOnDevice: true);
    expect(await tester.runAsync(() => thumbs.hasThumbnail(_id)), isFalse);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a sketch with no data at all keeps the dots', (tester) async {
    await pump(tester);
    expect(await tester.runAsync(() => thumbs.hasThumbnail(_id)), isFalse);
    expect(find.byType(Image), findsNothing);
  });

  test('a failed render is not tried again this session', () async {
    final dir = fs.notebookStoreDir(_id);
    expect(await thumbs.renderSketchFromStore(_id, dir), isFalse);
    await storeSketch();
    expect(await thumbs.renderSketchFromStore(_id, dir), isFalse,
        reason: 'remembered, even though the data is there now');
    expect(await thumbs.hasThumbnail(_id), isFalse);
  });

  test('renders queue one at a time and share a notebook\'s job', () async {
    await storeSketch();
    final dir = fs.notebookStoreDir(_id);
    final a = thumbs.renderSketchFromStore(_id, dir);
    final b = thumbs.renderSketchFromStore(_id, dir);
    expect(identical(a, b), isTrue);
    expect(await a, isTrue);
  });
}
