// FileService paths where a crash, a concurrent save or a library edit used
// to lose notebook content: the store swap, reads racing writes, library
// metadata edits, and backups that copied a stale file.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/services/file_service.dart';

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

Uint8List _u(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((k, v) {
    final b = utf8.encode(v);
    a.addFile(ArchiveFile(k, b.length, b));
  });
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

Uint8List _notebook({String title = 'T', Map<String, String> pages = const {}}) =>
    _zip({
      AppConfig.metadataFile: jsonEncode({'id': 'nb', 'title': title}),
      AppConfig.documentFile: jsonEncode({'pages': []}),
      for (final e in pages.entries) '${AppConfig.pagesDir}/${e.key}': e.value,
    });

void main() {
  late Directory tmp;
  late FileService fs;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fs_integrity_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    fs = FileService();
    await fs.init();
  });

  tearDown(() async {
    try {
      await fs.dispose();
    } catch (_) {}
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  String page(String id, String fn) =>
      File(p.join(fs.notebookStoreDir(id), AppConfig.pagesDir, fn))
          .readAsStringSync();

  test('a store parked by an interrupted swap is put back at start', () async {
    await fs.explodeZipToLooseStore('nb', _notebook(pages: {'p1.json': 'mine'}));
    final live = Directory(fs.notebookStoreDir('nb'));
    // Crash between "park the old store" and "move the new one in".
    await live.rename('${live.path}.1700000000-1.olddir');
    await Directory('${live.path}.1700000000-2.tmpdir').create();

    final fresh = FileService();
    await fresh.init();

    expect(live.existsSync(), isTrue);
    expect(page('nb', 'p1.json'), 'mine');
    expect(Directory('${live.path}.1700000000-2.tmpdir').existsSync(), isFalse);
    await fresh.dispose();
  });

  test('a parked store beside a live one is dropped, the live one kept',
      () async {
    await fs.explodeZipToLooseStore('nb', _notebook(pages: {'p1.json': 'new'}));
    final live = fs.notebookStoreDir('nb');
    final parked = Directory('$live.1700000000-1.olddir');
    await Directory(p.join(parked.path, AppConfig.pagesDir)).create(recursive: true);
    File(p.join(parked.path, AppConfig.pagesDir, 'p1.json')).writeAsStringSync('old');

    final fresh = FileService();
    await fresh.init();

    expect(parked.existsSync(), isFalse);
    expect(page('nb', 'p1.json'), 'new');
    await fresh.dispose();
  });

  test('a full write swaps the store in and leaves nothing beside it',
      () async {
    await fs.saveNotebookFile('nb', _notebook(pages: {'p1.json': 'v1'}));
    await fs.saveNotebookFile('nb', _notebook(pages: {'p1.json': 'v2'}));

    expect(page('nb', 'p1.json'), 'v2');
    final leftovers = Directory(p.dirname(fs.notebookStoreDir('nb')))
        .listSync()
        .where((e) => e.path.contains('.tmpdir') || e.path.contains('.olddir'));
    expect(leftovers, isEmpty);
  });

  test('a library metadata edit leaves every page alone', () async {
    await fs.explodeZipToLooseStore('nb', _notebook(pages: {'p1.json': 'v1'}));
    // The editor saves a page; a rename read the notebook before that.
    await fs.saveNotebookIncremental('nb',
        changedPages: {'p1.json': _u('v2 with the last stroke')});

    final meta = await fs.patchStoredMetadata(
        'nb', (m) => {...m, 'title': 'Renamed'});

    expect(meta?['title'], 'Renamed');
    expect(page('nb', 'p1.json'), 'v2 with the last stroke');
    final onDisk = jsonDecode(File(p.join(
            fs.notebookStoreDir('nb'), AppConfig.metadataFile))
        .readAsStringSync()) as Map<String, dynamic>;
    expect(onDisk['title'], 'Renamed');
  });

  test('patchStoredMetadata migrates a legacy-only notebook first', () async {
    await File(fs.localPath('nb'))
        .writeAsBytes(_notebook(pages: {'p1.json': 'legacy'}));
    final meta = await fs.patchStoredMetadata('nb', (m) => {...m, 'title': 'X'});
    expect(meta?['title'], 'X');
    expect(page('nb', 'p1.json'), 'legacy');
  });

  test('patchStoredMetadata returns null with no copy on this device',
      () async {
    expect(await fs.patchStoredMetadata('ghost', (m) => m), isNull);
  });

  test('a read waits for the write in progress instead of mixing two states',
      () async {
    await fs.explodeZipToLooseStore('nb', _notebook(pages: {'p1.json': 'v1'}));
    final write = fs.saveNotebookFile('nb', _notebook(pages: {'p2.json': 'v2'}));
    final read = fs.readNotebookFile('nb');
    await write;
    final names = ZipDecoder()
        .decodeBytes((await read)!)
        .files
        .map((f) => f.name)
        .toSet();
    expect(names, contains('${AppConfig.pagesDir}/p2.json'));
    expect(names, isNot(contains('${AppConfig.pagesDir}/p1.json')));
  });

  test('a backup holds the current store, not the stale legacy file',
      () async {
    await fs.saveNotebookFile('nb', _notebook(pages: {'p1.json': 'v1'}));
    // Every later edit only touches the store.
    await fs.saveNotebookIncremental('nb',
        changedPages: {'p1.json': _u('v2')});

    await fs.snapshotIfDue('nb', every: Duration.zero);

    final snaps = await fs.listSnapshots('nb');
    expect(snaps, isNotEmpty);
    final entries = ZipDecoder().decodeBytes(File(snaps.first.$2).readAsBytesSync());
    final p1 = entries.findFile('${AppConfig.pagesDir}/p1.json')!;
    expect(utf8.decode(p1.content as List<int>), 'v2');
  });

  test('backups are spaced out and capped at three', () async {
    await fs.explodeZipToLooseStore('nb', _notebook(pages: {'p1.json': 'v'}));
    await fs.snapshotIfDue('nb');
    await fs.snapshotIfDue('nb'); // too soon: skipped
    expect(await fs.listSnapshots('nb'), hasLength(1));
    for (var i = 0; i < 5; i++) {
      await fs.snapshotIfDue('nb', every: Duration.zero);
    }
    expect(await fs.listSnapshots('nb'), hasLength(3));
  });
}
