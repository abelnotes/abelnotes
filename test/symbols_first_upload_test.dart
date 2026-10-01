// The shared symbol library is pushed by its first reconcile. On WebDAV a
// missing symbols.json answers getVersion with a 404, which used to abort the
// reconcile, so the library never reached the server.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/core/providers/canvas_state.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/remote_store.dart';
import 'package:abelnotes/core/services/symbol_library_service.dart';

import 'support/fake_remote_store.dart';

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

class _WebDavLikeStore extends FakeRemoteStore {
  @override
  bool get nullVersionMeansAbsent => false;

  @override
  Future<String?> getVersion(String remotePath) async {
    if (!files.containsKey(remotePath)) {
      throw RemoteStoreException('PROPFIND 404', 404);
    }
    return super.getVersion(remotePath);
  }
}

void main() {
  late Directory tmp;
  late FileService fs;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('symbols_first_upload');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    fs = FileService();
    await fs.init();
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  for (final entry in {
    'WebDAV (404)': () => _WebDavLikeStore(),
    'Drive (null)': () => FakeRemoteStore(),
  }.entries) {
    test('first reconcile uploads the library on ${entry.key}', () async {
      final store = entry.value();
      final svc = SymbolLibraryService(
          fileService: fs, remoteStore: () => store);
      await svc.save(const SymbolCollection(
          libraries: [SymbolLibrary(id: 'l1', name: 'Mine')]));

      await svc.reconcile();

      expect(store.files.keys.where((k) => k.endsWith('symbols.json')),
          isNotEmpty);
    });
  }
}
