// Two (or more) simulated devices on one server, for sync tests: each has
// its own temp dir, SQLite, SharedPreferences snapshot and ProviderContainer.
// Prefs and path provider are process-wide, so only one device is active at
// a time (run) and the others' stores park their calls.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/providers/remote_store_provider.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/remote_store.dart';
import 'package:abelnotes/core/services/sync_service.dart' show LooseStoreContents;
import 'package:abelnotes/core/sync/stroke_ops.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

class SyncTestPaths extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  SyncTestPaths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

/// A device's view of the server: counts requests, can go "offline" and parks every
/// call while its device is not the active one.
class DeviceStore implements RemoteStore {
  DeviceStore(this.inner);
  final RemoteStore inner;
  int bytesUp = 0;

  bool offline = false;
  bool active = true;
  Completer<void> _wake = Completer<void>()..complete();
  final getsByPath = <String, int>{};
  int puts = 0, inFlightPuts = 0, maxPuts = 0;

  void setActive(bool v) {
    active = v;
    if (v) {
      if (!_wake.isCompleted) _wake.complete();
    } else if (_wake.isCompleted) {
      _wake = Completer<void>();
    }
  }

  Future<T> _call<T>(Future<T> Function() f) async {
    if (!active) await _wake.future;
    if (offline) throw const SocketException('simulated offline');
    return f();
  }

  /// Paths of every upload, in order.
  final putPaths = <String>[];

  Future<T> _put<T>(String p, Uint8List d, Future<T> Function() f) =>
      _call(() async {
        puts++;
        putPaths.add(p);
        bytesUp += d.length;
        maxPuts = ++inFlightPuts > maxPuts ? inFlightPuts : maxPuts;
        try {
          return await f();
        } finally {
          inFlightPuts--;
        }
      });

  @override
  String get basePath => inner.basePath;
  @override
  bool get nullVersionMeansAbsent => inner.nullVersionMeansAbsent;
  @override
  Future<void> ensureBaseDirectory() => _call(inner.ensureBaseDirectory);
  @override
  Future<List<RemoteItem>> listDirectory(String p) =>
      _call(() => inner.listDirectory(p));
  @override
  Future<Uint8List> downloadFile(String p,
          {int? timeoutSeconds, bool criticalVerify = false}) =>
      _call(() {
        getsByPath[p] = (getsByPath[p] ?? 0) + 1;
        return inner.downloadFile(p,
            timeoutSeconds: timeoutSeconds, criticalVerify: criticalVerify);
      });
  @override
  Future<String?> uploadFile(String p, Uint8List d,
          {int? timeoutSeconds,
          bool criticalVerify = false,
          bool skipVerify = false}) =>
      _put(p, d, () => inner.uploadFile(p, d,
          timeoutSeconds: timeoutSeconds,
          criticalVerify: criticalVerify,
          skipVerify: skipVerify));
  @override
  Future<String?> uploadFileConditional(String p, Uint8List d,
          {String? ifMatchVersion,
          bool ifAbsent = false,
          int? timeoutSeconds}) =>
      _put(p, d, () => inner.uploadFileConditional(p, d,
          ifMatchVersion: ifMatchVersion,
          ifAbsent: ifAbsent,
          timeoutSeconds: timeoutSeconds));
  @override
  Future<String?> uploadFileAtomic(String p, Uint8List d,
          {String? ifMatchVersion, int? timeoutSeconds}) =>
      _put(p, d, () => inner.uploadFileAtomic(p, d,
          ifMatchVersion: ifMatchVersion, timeoutSeconds: timeoutSeconds));
  @override
  Future<void> createDirectory(String p) => _call(() => inner.createDirectory(p));
  @override
  void forgetCached(String p) => inner.forgetCached(p);
  @override
  Future<void> delete(String p) => _call(() => inner.delete(p));
  @override
  Future<void> rename(String a, String b) => _call(() => inner.rename(a, b));
  @override
  Future<({String? version, DateTime? lastModified})?> getFileInfo(String p) =>
      _call(() => inner.getFileInfo(p));
  @override
  Future<String?> getVersion(String p) => _call(() => inner.getVersion(p));
  @override
  Future<String?> getVersionFast(String p) =>
      _call(() => inner.getVersionFast(p));
  @override
  Future<int?> getContentLength(String p) =>
      _call(() => inner.getContentLength(p));
  @override
  Future<String?> baselineIdentity() => inner.baselineIdentity();
}

const kPageFile = 'page_001.json';

ContentElement syncLine(String id, double y) => ContentElement.stroke(
      id: id,
      zIndex: 0,
      data: StrokeData(
          points: [StrokePoint(x: 10, y: y), StrokePoint(x: 100, y: y)]),
    );

String elementIdOf(ContentElement e) => e.map(
    unknown: (u) => u.id,
    stroke: (s) => s.id,
    text: (t) => t.id,
    image: (i) => i.id,
    shape: (s) => s.id,
    math: (m) => m.id);

List<String> idsOf(PageData? p) =>
    [for (final e in p?.layers.content ?? const <ContentElement>[]) elementIdOf(e)]
      ..sort();

/// Layer content as canonical JSON: what "same page" means across devices.
String normPage(PageData p) =>
    jsonEncode(p.layers.content.map((e) => e.toJson()).toList()
      ..sort((a, b) => '${a['id']}'.compareTo('${b['id']}')));

class SyncDevice {
  SyncDevice(this.name, this.store);
  final String name;
  final DeviceStore store;
  late Directory dir;
  late FileService fs;
  late ProviderContainer c;
  Map<String, Object> prefs = {};

  /// [StrokeOps.write] while this device runs: a fleet of two releases in
  /// one process. Null leaves the flag as it is.
  bool? writesChunks;

  CanvasNotifier get canvas => c.read(canvasProvider.notifier);
  CanvasState? get state => c.read(canvasProvider);
  NotebookListNotifier get library => c.read(notebookListProvider.notifier);

  void _activate() {
    if (writesChunks != null) StrokeOps.write = writesChunks!;
    PathProviderPlatform.instance = SyncTestPaths(dir.path);
    SharedPreferences.setMockInitialValues(Map.of(prefs));
  }

  Future<void> init() async {
    dir = await Directory.systemTemp.createTemp('nc_dev_$name');
    prefs = {};
    _activate();
    fs = FileService();
    await fs.init();
    c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(store),
    ]);
  }

  /// Runs [body] with this device as the only active one, then settles it
  /// (pull loop stopped, saves flushed) and keeps its prefs.
  Future<T> run<T>(Future<T> Function() body) async {
    for (final d in syncDevices) {
      d.store.setActive(identical(d, this));
    }
    _activate();
    if (state != null) canvas.restartPullTimerIfNeeded();
    try {
      return await body();
    } finally {
      if (state != null) await canvas.flushPendingWork();
      final p = await SharedPreferences.getInstance();
      prefs = {for (final k in p.getKeys()) k: p.get(k)!};
    }
  }

  /// The app is killed: nothing is flushed or closed, the prefs are what was
  /// written so far, and the next start runs on the same disk.
  Future<void> crash() async {
    final p = await SharedPreferences.getInstance();
    prefs = {for (final k in p.getKeys()) k: p.get(k)!};
    c.dispose();
    _activate();
    fs = FileService();
    await fs.init();
    c = ProviderContainer(overrides: [
      fileServiceProvider.overrideWithValue(fs),
      remoteStoreProvider.overrideWithValue(store),
    ]);
  }

  Future<void> dispose() async {
    try {
      store.setActive(true);
      if (writesChunks != null) StrokeOps.write = writesChunks!;
      await c.read(canvasProvider.notifier).closeNotebook();
    } catch (_) {}
    c.dispose();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// The way the library opens a held notebook: loose store, else the
  /// legacy file, else a download.
  Future<void> open(NotebookEntry e) async {
    final sync = c.read(syncServiceProvider)!;
    final id = e.metadata.id;
    LooseStoreContents? d =
        await sync.loadLooseStoreFromDisk(fs.notebookStoreDir(id));
    if (d == null || (d.pages.isEmpty && d.document.pages.isNotEmpty)) {
      final bytes = await fs.readNotebookFile(id);
      if (bytes != null) d = sync.parsePackage(bytes);
    }
    if (d == null || (d.pages.isEmpty && d.document.pages.isNotEmpty)) {
      final r = await library.fetchToDevice(id, e.remotePath);
      await canvas.openNotebook(
          metadata: r.metadata,
          document: r.document,
          pages: r.pages,
          remotePath: e.remotePath,
          assets: r.assets);
      return;
    }
    await canvas.openNotebook(
        metadata: d.metadata,
        document: d.document,
        pages: d.pages,
        remotePath: e.remotePath,
        assets: d.assets);
  }

  /// Adds [id] to [file] the way a pen stroke does: state write + dirty.
  void draw(String id, {String file = kPageFile, double y = 200}) {
    final s = state!;
    final page = s.pages[file]!;
    canvas.state = s.copyWith(
      pages: {
        ...s.pages,
        file: page.copyWith(
            layers: page.layers
                .copyWith(content: [...page.layers.content, syncLine(id, y)])),
      },
      isDirty: true,
    );
  }

  /// One new stroke on every page.
  void drawAll(String tag) {
    final s = state!;
    canvas.state = s.copyWith(
      pages: {
        for (final e in s.pages.entries)
          e.key: e.value.copyWith(
              layers: e.value.layers.copyWith(
                  content: [...e.value.layers.content, syncLine('$tag-${e.key}', 300)])),
      },
      isDirty: true,
    );
  }

  Future<bool> waitFor(bool Function() cond,
      {Duration timeout = const Duration(seconds: 45)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (cond()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return cond();
  }
}

final syncDevices = <SyncDevice>[];
