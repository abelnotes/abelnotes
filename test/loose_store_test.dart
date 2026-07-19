// Round-trip tests for FileService's incremental "loose store" — the per-page
// local persistence that replaces rewriting the whole .ncnote ZIP on every
// save. Data-critical, so we exercise explode → assemble → incremental patch →
// delete → legacy migration against the real FileService methods.

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
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/core/services/webdav_service.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

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

Uint8List _buildZip({
  Map<String, dynamic> metadata = const {'id': 'nb', 'title': 'T'},
  Map<String, dynamic> document = const {'pages': []},
  Map<String, Uint8List> pages = const {},
  Map<String, Uint8List> assets = const {},
  List<dynamic>? symbols,
}) {
  final a = Archive();
  void add(String name, List<int> b) => a.addFile(ArchiveFile(name, b.length, b));
  add(AppConfig.metadataFile, utf8.encode(jsonEncode(metadata)));
  add(AppConfig.documentFile, utf8.encode(jsonEncode(document)));
  pages.forEach((k, v) => add('${AppConfig.pagesDir}/$k', v));
  assets.forEach((k, v) => add('${AppConfig.assetsDir}/$k', v));
  if (symbols != null) add('symbols.json', utf8.encode(jsonEncode(symbols)));
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

Map<String, Uint8List> _entries(Uint8List zip, String prefix) {
  final out = <String, Uint8List>{};
  for (final f in ZipDecoder().decodeBytes(zip).files) {
    if (f.isFile && f.name.startsWith(prefix)) {
      out[f.name.substring(prefix.length)] =
          Uint8List.fromList(f.content as List<int>);
    }
  }
  return out;
}

void main() {
  late Directory tmp;
  late FileService fs;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('loose_store_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    fs = FileService();
    await fs.init();
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('loadLooseStoreFromDisk parses pages/assets/symbols off disk', () async {
    // A valid page so PageData.fromJson / decodePageData succeed.
    final page = PageData(
      pageId: 'pg-1',
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: RenderingLayers(
        content: [
          ContentElement.stroke(
            id: 'stroke-1',
            zIndex: 0,
            data: StrokeData(
              points: const [StrokePoint(x: 1, y: 2), StrokePoint(x: 3, y: 4)],
              baseWidth: 2.0,
              color: 0xFF000000,
            ),
          ),
        ],
      ),
    );
    final metadata = NotebookMetadata(
      id: 'nb',
      title: 'T',
      createdAt: DateTime.utc(2020),
      modifiedAt: DateTime.utc(2020),
    );
    final document = DocumentStructure(
      notebookId: 'nb',
      pages: const [
        PageEntry(pageId: 'pg-1', pageNumber: 1, fileName: 'page_001.json'),
      ],
    );

    final zip = _buildZip(
      metadata: metadata.toJson(),
      document: document.toJson(),
      pages: {'page_001.json': _u(jsonEncode(page.toJson()))},
      assets: {'img_1.png': Uint8List.fromList([1, 2, 3, 4])},
      symbols: [
        {'name': 'lib'}
      ],
    );
    await fs.explodeZipToLooseStore('nb', zip);

    final sync = SyncService(WebDavService(
        serverUrl: 'https://example.invalid', username: 'u', password: 'p'));
    final data = (await sync.loadLooseStoreFromDisk(fs.notebookStoreDir('nb')))!;

    expect(data.metadata.id, 'nb');
    expect(data.metadata.title, 'T');
    expect(data.document.pages.single.fileName, 'page_001.json');
    // Page decoded into real PageData (keyed by file name).
    expect(data.pages.keys, {'page_001.json'});
    expect(data.pages['page_001.json']!.pageId, 'pg-1');
    // Asset bytes preserved verbatim, keyed by sub-path after assets/.
    expect(data.assets['img_1.png'], Uint8List.fromList([1, 2, 3, 4]));
    expect(data.symbolLibraries, [
      {'name': 'lib'}
    ]);
  });

  test('loadLooseStoreFromDisk returns null when no loose store exists',
      () async {
    final sync = SyncService(WebDavService(
        serverUrl: 'https://example.invalid', username: 'u', password: 'p'));
    expect(await sync.loadLooseStoreFromDisk(fs.notebookStoreDir('missing')),
        isNull);
  });

  test('explode → assemble round-trips every entry byte-for-byte', () async {
    final zip = _buildZip(
      pages: {'page_001.json': _u('{"a":1}'), 'page_002.json': _u('{"b":2}')},
      assets: {'img_1.png': Uint8List.fromList([1, 2, 3, 4])},
      symbols: [
        {'name': 'lib'}
      ],
    );

    await fs.explodeZipToLooseStore('nb', zip);
    expect(await fs.hasLooseStore('nb'), isTrue);

    final out = (await fs.assembleZipFromLooseStore('nb'))!;
    final pages = _entries(out, '${AppConfig.pagesDir}/');
    final assets = _entries(out, '${AppConfig.assetsDir}/');
    expect(pages.keys.toSet(), {'page_001.json', 'page_002.json'});
    expect(pages['page_001.json'], _u('{"a":1}'));
    expect(assets['img_1.png'], Uint8List.fromList([1, 2, 3, 4]));
    // symbols + metadata + document present
    final all = ZipDecoder().decodeBytes(out).files.map((f) => f.name).toSet();
    expect(all, containsAll([AppConfig.metadataFile, AppConfig.documentFile, 'symbols.json']));
  });

  test('incremental patch changes only the touched page', () async {
    await fs.explodeZipToLooseStore(
      'nb',
      _buildZip(pages: {
        'page_001.json': _u('{"v":1}'),
        'page_002.json': _u('{"v":2}'),
      }, assets: {
        'a.bin': Uint8List.fromList([9])
      }),
    );

    // Capture page_002's on-disk mtime, then patch only page_001.
    final p2 = File(p.join(fs.notebookStoreDir('nb'), AppConfig.pagesDir, 'page_002.json'));
    final mtimeBefore = await p2.lastModified();

    await fs.saveNotebookIncremental(
      'nb',
      metadataJson: _u('{"id":"nb"}'),
      documentJson: _u('{"pages":[]}'),
      changedPages: {'page_001.json': _u('{"v":99}')},
    );

    final out = (await fs.assembleZipFromLooseStore('nb'))!;
    final pages = _entries(out, '${AppConfig.pagesDir}/');
    expect(pages['page_001.json'], _u('{"v":99}'), reason: 'patched');
    expect(pages['page_002.json'], _u('{"v":2}'), reason: 'untouched page intact');
    expect(_entries(out, '${AppConfig.assetsDir}/')['a.bin'],
        Uint8List.fromList([9]), reason: 'assets untouched by a page edit');
    // The untouched page file must not have been rewritten.
    expect(await p2.lastModified(), mtimeBefore);
  });

  test('deletedPages removes the page from the store', () async {
    await fs.explodeZipToLooseStore(
      'nb',
      _buildZip(pages: {
        'page_001.json': _u('{"v":1}'),
        'page_002.json': _u('{"v":2}'),
      }),
    );
    await fs.saveNotebookIncremental('nb', deletedPages: ['page_002.json']);
    final pages = _entries((await fs.assembleZipFromLooseStore('nb'))!,
        '${AppConfig.pagesDir}/');
    expect(pages.keys, {'page_001.json'});
  });

  test('ensureLooseStore migrates a legacy .ncnote exactly once', () async {
    final zip = _buildZip(pages: {'page_001.json': _u('{"legacy":true}')});
    // Simulate a pre-migration notebook: only the legacy file exists.
    await File(fs.localPath('nb')).writeAsBytes(zip, flush: true);
    expect(await fs.hasLooseStore('nb'), isFalse);

    final migrated = await fs.ensureLooseStore('nb');
    expect(migrated, isTrue);
    expect(await fs.hasLooseStore('nb'), isTrue);

    final pages = _entries((await fs.assembleZipFromLooseStore('nb'))!,
        '${AppConfig.pagesDir}/');
    expect(pages['page_001.json'], _u('{"legacy":true}'));

    // No legacy file → no migration.
    expect(await fs.ensureLooseStore('absent'), isFalse);
  });

  test('readNotebookFile prefers the loose store over a stale legacy file',
      () async {
    // Legacy file says v1; loose store (source of truth) says v2.
    await File(fs.localPath('nb'))
        .writeAsBytes(_buildZip(pages: {'page_001.json': _u('{"v":1}')}), flush: true);
    await fs.explodeZipToLooseStore(
        'nb', _buildZip(pages: {'page_001.json': _u('{"v":2}')}));

    final bytes = (await fs.readNotebookFile('nb'))!;
    expect(_entries(bytes, '${AppConfig.pagesDir}/')['page_001.json'], _u('{"v":2}'));
  });

  test('looseStoreSize is positive and deleteLooseStore clears it', () async {
    await fs.explodeZipToLooseStore(
        'nb', _buildZip(pages: {'page_001.json': _u('{"v":1}')}));
    expect(await fs.looseStoreSize('nb'), greaterThan(0));
    await fs.deleteLooseStore('nb');
    expect(await fs.hasLooseStore('nb'), isFalse);
    expect(await fs.looseStoreSize('nb'), 0);
  });
}
