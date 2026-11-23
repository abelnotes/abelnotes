// Drives the whole editor (CanvasScreen) in `flutter test`: a temp FileService,
// a FakeRemoteStore, the app's theme and translations, real pointer events.
// Used by test/editor_e2e_test.dart (Phase 0 of test/work/arch-split/PLAN.md).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:abelnotes/core/services/pen_input_channel.dart' show LinuxPenPressure;
import 'package:abelnotes/ui/primitives/file_drop_zone.dart';
import 'package:abelnotes/features/canvas/presentation/canvas_screen.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

import 'fake_remote_store.dart';

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

const harnessNotebookId = '0e2e0000-harness-notebook';

/// One editor scenario: opens the harness, runs [body], then lets debounced
/// timers (tool prefs, autosave) fire and unmounts, inside the test itself.
void testEditor(String description, Future<void> Function(EditorHarness h) body,
    {Map<String, PageData>? pages,
    Size size = const Size(1280, 800),
    String? paperType,
    void Function(ProviderContainer container)? beforeShow,
    List<Override> overrides = const []}) {
  testWidgets(description, (tester) async {
    final h = await EditorHarness.open(tester,
        pages: pages,
        size: size,
        paperType: paperType,
        beforeShow: beforeShow,
        overrides: overrides);
    await body(h);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}

PageData blankPage(String id, {List<ContentElement> content = const []}) => PageData(
      pageId: id,
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: RenderingLayers(content: content),
    );

/// One editor on one notebook. Create with [EditorHarness.open].
class EditorHarness {
  EditorHarness._(this.tester, this.container, this.files, this.remote, this.tmp);

  final WidgetTester tester;
  final ProviderContainer container;
  final FileService files;
  final FakeRemoteStore remote;
  final Directory tmp;

  CanvasNotifier get notifier => container.read(canvasProvider.notifier);
  CanvasState get state => container.read(canvasProvider)!;

  /// Boots storage, opens [pages] (default: one blank page) and pumps the editor
  /// at [size] logical pixels.
  static Future<EditorHarness> open(
    WidgetTester tester, {
    Map<String, PageData>? pages,
    Size size = const Size(1280, 800),
    Map<String, Object> prefs = const {},
    String? paperType,
    void Function(ProviderContainer container)? beforeShow,
    List<Override> overrides = const [],
    bool overLibrary = false,
  }) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FileDropZone.debugEnabled = false;
    LinuxPenPressure.debugEnabled = false;
    SharedPreferences.setMockInitialValues({...prefs});
    final tmp = await tester.runAsync(() => Directory.systemTemp.createTemp('editor_e2e'));
    PathProviderPlatform.instance = _TempPaths(tmp!.path);
    final files = FileService();
    await tester.runAsync(files.init);
    // No identity: baselines stay in (fake) prefs; real file IO inside the
    // pull lock would stall under the fake clock.
    final remote = FakeRemoteStore(identity: null);
    final container = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(files),
      remoteStoreProvider.overrideWithValue(remote),
      ...overrides,
    ]);
    final pg = pages ?? {'p1.json': blankPage('p1')};
    final now = DateTime(2026);
    await tester.runAsync(() => container.read(canvasProvider.notifier).openNotebook(
          metadata: NotebookMetadata(
              id: harnessNotebookId,
              title: 'Harness',
              createdAt: now,
              modifiedAt: now,
              paperType: paperType ?? 'lined'),
          document: DocumentStructure(notebookId: harnessNotebookId, pages: [
            for (final (i, f) in pg.keys.indexed)
              PageEntry(pageId: pg[f]!.pageId, pageNumber: i + 1, fileName: f),
          ]),
          pages: pg,
          remotePath: '/AbelNotes/harness.abelnote',
        ));
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    beforeShow?.call(container);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        theme: buildHwThemeData(HwThemeVariant.light),
        builder: (context, child) => HwThemeScope(
          palette: HwPalette.light,
          variant: HwThemeVariant.light,
          child: child ?? const SizedBox.shrink(),
        ),
        home: overLibrary ? const LibraryStub() : const CanvasScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    if (overLibrary) {
      await tester.pumpAndSettle();
      expect(find.byType(CanvasScreen), findsOneWidget);
    }
    final h = EditorHarness._(tester, container, files, remote, tmp);
    // Tests run as a touch platform, which starts on the hand tool.
    h.notifier.setTool(CanvasTool.pen);
    await tester.pump();
    addTearDown(h._close);
    return h;
  }

  Future<void> _close() async {
    container.dispose();
    await tester.runAsync(() async {
      // Close the database first: a save still running would otherwise hold
      // its lock in the shared sqlite isolate and stall the next test's open.
      try {
        await files.dispose();
      } catch (_) {}
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });
  }

  /// Centre of the page area on screen.
  Offset get canvasCenter => tester.getCenter(find.byType(CanvasScreen));

  /// A stroke through [points] (screen coordinates) with [kind].
  Future<void> drag(List<Offset> points,
      {PointerDeviceKind kind = PointerDeviceKind.stylus, int buttons = kPrimaryButton}) async {
    final g = await tester.createGesture(kind: kind, buttons: buttons);
    await g.down(points.first);
    await tester.pump(const Duration(milliseconds: 16));
    for (final p in points.skip(1)) {
      await g.moveTo(p);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// A short wavy stroke around [at].
  Future<void> scribble(Offset at, {PointerDeviceKind kind = PointerDeviceKind.stylus}) =>
      drag([for (var i = 0; i <= 12; i++) at + Offset(i * 8.0, (i.isEven ? -6 : 6))], kind: kind);

  List<ContentElement> get content => state.currentPage!.layers.content;
  int get strokeCount => content.whereType<StrokeElement>().length;

  /// Lets timers (autosave, debounces) run in real time for [d].
  Future<void> settle([Duration d = const Duration(milliseconds: 300)]) async {
    await tester.runAsync(() => Future<void>.delayed(d));
    await tester.pump();
  }

  /// Raw pixel size, for tests that need to place the pointer precisely.
  ui.Size get surface => tester.view.physicalSize / tester.view.devicePixelRatio;
}

/// Stands in for the library: pushes the editor over itself, so leaving the
/// editor has somewhere to go.
class LibraryStub extends StatefulWidget {
  const LibraryStub({super.key});
  @override
  State<LibraryStub> createState() => _LibraryStubState();
}

class _LibraryStubState extends State<LibraryStub> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).push(
          MaterialPageRoute<Object?>(builder: (_) => const CanvasScreen()));
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('library')));
}
