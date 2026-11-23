// Full-text search: the page_text table, the indexer that keeps it current
// and the query on top of it.

// The path_provider mock needs the platform-interface packages, as in the
// other FileService tests.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart'
    show compactPageJson;
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/search_service.dart';
import 'package:abelnotes/features/search/page_text.dart';
import 'package:abelnotes/features/search/search_index.dart';
import 'package:abelnotes/features/search/search_indexer.dart';
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

Uint8List _bytes(Object json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

/// A page file's bytes with these texts, maths and PDF runs.
Uint8List _pageBytes(String id,
    {List<String> texts = const [],
    List<String> maths = const [],
    List<String> pdf = const []}) {
  var z = 0;
  final page = PageData(
    pageId: id,
    pageNumber: 1,
    width: 595,
    height: 842,
    layers: RenderingLayers(content: [
      for (final t in texts)
        ContentElement.text(
            id: 't${z++}',
            zIndex: z,
            data: TextData(x: 0, y: 0, width: 1, height: 1, content: t)),
      for (final m in maths)
        ContentElement.math(
            id: 'm${z++}',
            zIndex: z,
            data: MathData(x: 0, y: 0, width: 1, height: 1, latex: m)),
    ]),
    pdfTextLayer: pdf.isEmpty
        ? null
        : PdfTextLayer(sourceAssetPath: 'a', runs: [
            for (final r in pdf)
              PdfTextRun(text: r, x: 0, y: 0, width: 1, height: 1)
          ]),
  );
  return Uint8List.fromList(utf8.encode(compactPageJson(page)));
}

typedef _Pg = ({String file, String id, String? chapter});

void main() {
  late Directory tmp;
  late FileService fs;
  late SearchIndexer indexer;
  late SearchService search;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('search_index_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    fs = FileService();
    await fs.init();
    indexer = SearchIndexer(fs,
        debounce: const Duration(milliseconds: 40),
        useIsolate: false,
        idle: () async {});
    search = SearchService(fs);
    indexer.start(reconcileDelay: const Duration(hours: 1));
  });

  tearDown(() async {
    indexer.dispose();
    try {
      await fs.dispose();
    } catch (_) {}
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> registerNotebook(String id, String title,
          {DateTime? modified}) =>
      fs.upsertNotebookMeta(
        id: id,
        title: title,
        remotePath: '/$id.ncnote',
        localModifiedAt: modified ?? DateTime(2026, 1, 1),
      );

  Uint8List docJson(String id, List<_Pg> pages) => _bytes({
        'notebookId': id,
        'pages': [
          for (var i = 0; i < pages.length; i++)
            {
              'pageId': pages[i].id,
              'pageNumber': i + 1,
              'fileName': pages[i].file,
              if (pages[i].chapter != null) 'chapterId': pages[i].chapter,
            }
        ],
      });

  Uint8List metaJson(String id, String title,
          [Map<String, String> chapters = const {}]) =>
      _bytes({
        'id': id,
        'title': title,
        'chapters': [
          for (final c in chapters.entries)
            {'id': c.key, 'title': c.value, 'pageIds': <String>[]}
        ],
      });

  /// Registers a notebook and saves it through FileService.
  Future<void> addNotebook(
      String id, String title, List<_Pg> pages, Map<String, Uint8List> files,
      {Map<String, String> chapters = const {}, DateTime? modified}) async {
    await registerNotebook(id, title, modified: modified);
    await fs.saveNotebookIncremental(id,
        metadataJson: metaJson(id, title, chapters),
        documentJson: docJson(id, pages),
        changedPages: files);
  }

  Future<List<SearchHit>> find(String q) => search.search(q, titles: false);

  group('migration', () {
    test('an existing v4 database gains page_text and keeps its rows',
        () async {
      await fs.dispose();
      final dbPath = p.join(tmp.path, AppConfig.appDirName, AppConfig.dbName);
      File(dbPath).deleteSync();
      final old = await databaseFactory.openDatabase(dbPath,
          options: OpenDatabaseOptions(
              version: 4,
              onCreate: (db, v) async {
                await db.execute('CREATE TABLE notebooks (id TEXT PRIMARY KEY, '
                    'title TEXT NOT NULL, remote_path TEXT NOT NULL, etag TEXT, '
                    'local_modified_at TEXT NOT NULL, remote_modified_at TEXT, '
                    "sync_status TEXT NOT NULL DEFAULT 'synced', file_size INTEGER, "
                    'cover_color INTEGER, cover_style TEXT, paper_type TEXT, '
                    'page_count INTEGER DEFAULT 0, created_at TEXT NOT NULL, '
                    'local_only INTEGER NOT NULL DEFAULT 0, '
                    'download_skipped INTEGER NOT NULL DEFAULT 0)');
                await db.execute(
                    'CREATE TABLE dirty_pages (notebook_id TEXT NOT '
                    'NULL, page_id TEXT NOT NULL, modified_at TEXT NOT NULL, '
                    'PRIMARY KEY (notebook_id, page_id))');
                await db.insert('notebooks', {
                  'id': 'old',
                  'title': 'Old one',
                  'remote_path': '/old',
                  'local_modified_at': '2026-01-01T00:00:00.000',
                  'created_at': '2026-01-01T00:00:00.000',
                });
              }));
      await old.close();

      final fs2 = FileService();
      await fs2.init();
      addTearDown(fs2.dispose);
      final db = fs2.database;
      expect(
          Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')), AppConfig.dbVersion);
      expect(await SearchIndex(db).rowCount(), 0);
      expect((await fs2.getAllNotebookMeta()).single['title'], 'Old one');
      // Reopening a database that already has the table is a no-op.
      await SearchIndex.createTable(db);
    });
  });

  group('query', () {
    setUp(() async {
      await addNotebook(
        'nb1',
        'Circuits',
        [
          (file: 'page_001.json', id: 'a1', chapter: 'c1'),
          (file: 'page_002.json', id: 'a2', chapter: 'c2'),
          (file: 'page_003.json', id: 'a3', chapter: 'c2'),
        ],
        {
          'page_001.json': _pageBytes('a1', texts: [
            'The resistor R1 limits the current',
            'Città nuova: 100% of 1000 units'
          ]),
          'page_002.json':
              _pageBytes('a2', maths: [r'\omega_0 = \frac{1}{\sqrt{LC}}']),
          'page_003.json': _pageBytes('a3',
              pdf: ['Fourier', 'transform of a signal'],
              texts: ['a_b and axb']),
        },
        chapters: {'c1': 'Basics', 'c2': 'Resonance'},
        modified: DateTime(2026, 3, 1),
      );
      await addNotebook(
        'nb2',
        'Resistor notes',
        [(file: 'page_001.json', id: 'b1', chapter: null)],
        {
          'page_001.json': _pageBytes('b1', texts: ['unrelated words only'])
        },
        modified: DateTime(2026, 2, 1),
      );
      await addNotebook(
        'nb3',
        'Newer notebook',
        [(file: 'page_001.json', id: 'c1p', chapter: null)],
        {
          'page_001.json': _pageBytes('c1p', texts: ['another resistor here'])
        },
        modified: DateTime(2026, 4, 1),
      );
      await indexer.flush();
    });

    test('finds text, math words and pdf text, and says which', () async {
      final r = await find('resistor');
      final byNb = {for (final h in r) h.notebookId: h};
      expect(byNb.keys, containsAll(['nb1', 'nb3']));
      expect(byNb['nb1']!.kind, SearchHitKind.text);
      expect(byNb['nb1']!.pageNumber, 1);

      final m = await find('omega');
      expect(m.single.kind, SearchHitKind.math);
      expect(m.single.pageNumber, 2);
      expect(m.single.snippet, r'\omega_0 = \frac{1}{\sqrt{LC}}');
      // The markup of a formula is not a word.
      expect(await find('frac'), isEmpty);
      expect(await find('sqrt'), isEmpty);

      final pdf = await find('fourier');
      expect(pdf.single.kind, SearchHitKind.pdf);
      expect(pdf.single.snippet, 'Fourier transform of a signal');
      expect(pdf.single.pageNumber, 3);
    });

    test('folds case and diacritics both ways', () async {
      expect((await find('CITTA')).single.pageNumber, 1);
      expect((await find('città')).single.pageNumber, 1);
      expect((await find('cittÀ NUOVA')).length, 1);
    });

    test('every token must be present, in any order and any box', () async {
      expect(
          (await find('current resistor')).map((h) => h.notebookId), ['nb1']);
      expect((await find('units città')).length, 1);
      expect(await find('resistor fourier'), isEmpty);
      expect(await find('   '), isEmpty);
    });

    test('LIKE wildcards in the query are literal', () async {
      expect((await find('100%')).length, 1);
      expect(await find('10%0'), isEmpty);
      expect((await find('a_b')).single.pageNumber, 3);
      expect(await find(r'a\b'), isEmpty);
      expect(await find('%'), hasLength(1)); // only the "100%" page
    });

    test('snippet is cut around the first token with matched spans', () async {
      final long = '${'lorem ipsum ' * 12}NEEDLE${' dolor sit ' * 12}';
      await addNotebook('nb4', 'Long', [
        (file: 'p.json', id: 'l1', chapter: null)
      ], {
        'p.json': _pageBytes('l1', texts: [long])
      });
      await indexer.flush();
      final h = (await find('needle')).single;
      expect(h.snippet.startsWith('…'), isTrue);
      expect(h.snippet.endsWith('…'), isTrue);
      expect(h.snippet.length, lessThanOrEqualTo(40 + 6 + 40 + 2));
      expect(h.ranges.length, 1);
      final (a, b) = h.ranges.single;
      expect(h.snippet.substring(a, b), 'NEEDLE');

      final two = (await find('dolor needle')).single;
      final marked = two.ranges
          .map((r) => two.snippet.substring(r.$1, r.$2).toLowerCase())
          .toSet();
      expect(marked, {'needle', 'dolor'});
    });

    test('chapter titles are hits that open the chapter', () async {
      final h = (await find('resonance')).single;
      expect(h.kind, SearchHitKind.chapter);
      expect(h.chapterId, 'c2');
      expect(h.pageIndex, 1);
      expect(h.snippet, 'Resonance');
    });

    test('order: title matches first, then newest notebook, then page order',
        () async {
      final r = await find('resistor');
      // nb1 (Mar), nb3 (Apr): nb3 is newer; nb2 matches by title only.
      expect(r.map((h) => h.notebookId), ['nb3', 'nb1']);
      final withTitles = await search.search('resistor');
      expect(withTitles.first.kind, SearchHitKind.notebookTitle);
      expect(withTitles.first.notebookId, 'nb2');

      await addNotebook(
        'nb5',
        'Resistor again',
        [(file: 'p.json', id: 'x', chapter: null)],
        {
          'p.json': _pageBytes('x', texts: ['old resistor page'])
        },
        modified: DateTime(2020, 1, 1),
      );
      await indexer.flush();
      // A title match outranks a newer notebook.
      expect((await find('resistor')).first.notebookId, 'nb5');
    });

    test('limit and hits carry the page index and chapter', () async {
      expect(await search.search('resistor', limit: 1, titles: false),
          hasLength(1));
      final h = (await find('transform')).single;
      expect((h.pageIndex, h.chapterId), (2, 'c2'));
    });
  });

  group('indexer follows the store', () {
    test('save, edit, page delete, notebook delete and trash', () async {
      await addNotebook('n', 'N', [
        (file: 'p1.json', id: 'a', chapter: null)
      ], {
        'p1.json': _pageBytes('a', texts: ['alpha bravo'])
      });
      await indexer.flush();
      expect(await find('bravo'), hasLength(1));

      // Edit: the new word is found, the old one is gone.
      await fs.saveNotebookIncremental('n', changedPages: {
        'p1.json': _pageBytes('a', texts: ['alpha charlie'])
      });
      await indexer.flush();
      expect(await find('charlie'), hasLength(1));
      expect(await find('bravo'), isEmpty);

      // A second page, then removing it.
      await fs.saveNotebookIncremental('n',
          documentJson: docJson('n', [
            (file: 'p1.json', id: 'a', chapter: null),
            (file: 'p2.json', id: 'b', chapter: null),
          ]),
          changedPages: {
            'p2.json': _pageBytes('b', texts: ['delta echo'])
          });
      await indexer.flush();
      expect((await find('echo')).single.pageNumber, 2);
      await fs.saveNotebookIncremental('n',
          documentJson:
              docJson('n', [(file: 'p1.json', id: 'a', chapter: null)]),
          deletedPages: ['p2.json']);
      await indexer.flush();
      expect(await find('echo'), isEmpty);
      expect(await find('charlie'), hasLength(1));

      // Trash removes it, and a later delete leaves nothing behind either.
      await fs.moveNotebookToTrash('n');
      await indexer.flush();
      expect(await indexer.index.rowCount(), 0);

      await addNotebook('m', 'M', [
        (file: 'p1.json', id: 'a', chapter: null)
      ], {
        'p1.json': _pageBytes('a', texts: ['foxtrot'])
      });
      await indexer.flush();
      expect(await find('foxtrot'), hasLength(1));
      await fs.deleteNotebook('m');
      await indexer.flush();
      expect(await indexer.index.rowCount(), 0);
    });

    test('a full package write is picked up', () async {
      await registerNotebook('full', 'Full');
      final src = Directory(p.join(tmp.path, 'src'))..createSync();
      // Same layout as the .ncnote zip, built through the loose store.
      await fs.saveNotebookIncremental('full',
          metadataJson: metaJson('full', 'Full'),
          documentJson:
              docJson('full', [(file: 'p1.json', id: 'a', chapter: null)]),
          changedPages: {
            'p1.json': _pageBytes('a', texts: ['golf'])
          });
      src.deleteSync();
      final zip = await fs.assembleZipFromLooseStore('full');
      await fs.deleteLooseStore('full');
      await indexer.index.deleteNotebook('full');
      await fs.saveNotebookFile('full', zip!);
      await indexer.flush();
      expect(await find('golf'), hasLength(1));
    });

    test('editing waits for the pause and then indexes once', () async {
      await addNotebook('n', 'N', [
        (file: 'p1.json', id: 'a', chapter: null)
      ], {
        'p1.json': _pageBytes('a', texts: ['hotel'])
      });
      await Future<void>.delayed(Duration.zero);
      expect(indexer.status.value.busy, isTrue);
      var runs = 0;
      indexer.revision.addListener(() => runs++);
      // Three saves inside the pause window.
      for (var i = 0; i < 3; i++) {
        await fs.saveNotebookIncremental('n', changedPages: {
          'p1.json': _pageBytes('a', texts: ['india$i'])
        });
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await find('india2'), isEmpty); // still paused
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(indexer.status.value.busy, isFalse);
      expect((await find('india2')), hasLength(1));
      expect(runs, 1);
    });

    test('an evicted notebook keeps its rows and stays findable', () async {
      await addNotebook('e', 'E', [
        (file: 'p1.json', id: 'a', chapter: null)
      ], {
        'p1.json': _pageBytes('a', texts: ['juliet'])
      });
      await indexer.flush();
      await fs.evictLocalCopy('e');
      await indexer.reconcile();
      final h = (await find('juliet')).single;
      expect(h.notebookId, 'e');
      expect(h.pageNumber, 1);
    });

    test('moving a page updates its position without a re-read', () async {
      await addNotebook('mv', 'MV', [
        (file: 'p1.json', id: 'a', chapter: null),
        (file: 'p2.json', id: 'b', chapter: null),
      ], {
        'p1.json': _pageBytes('a', texts: ['kilo']),
        'p2.json': _pageBytes('b', texts: ['lima']),
      });
      await indexer.flush();
      expect((await find('lima')).single.pageNumber, 2);
      await fs.saveNotebookIncremental('mv',
          documentJson: docJson('mv', [
            (file: 'p2.json', id: 'b', chapter: null),
            (file: 'p1.json', id: 'a', chapter: null),
          ]));
      await indexer.flush();
      expect((await find('lima')).single.pageNumber, 1);
      expect((await find('kilo')).single.pageNumber, 2);
    });
  });

  group('reconcile', () {
    test('adds missing rows, repairs stale ones, drops vanished ones',
        () async {
      await registerNotebook('r', 'R');
      final dir = fs.notebookStoreDir('r');
      Directory(p.join(dir, AppConfig.pagesDir)).createSync(recursive: true);
      File(p.join(dir, AppConfig.metadataFile))
          .writeAsBytesSync(metaJson('r', 'R'));
      File(p.join(dir, AppConfig.documentFile)).writeAsBytesSync(docJson('r', [
        (file: 'p1.json', id: 'a', chapter: null),
        (file: 'p2.json', id: 'b', chapter: null),
      ]));
      void put(String f, Uint8List b) =>
          File(p.join(dir, AppConfig.pagesDir, f)).writeAsBytesSync(b);
      put('p1.json', _pageBytes('a', texts: ['mike']));
      put('p2.json', _pageBytes('b', texts: ['november']));

      // Files written behind FileService's back: no event, reconcile finds them.
      expect(await find('mike'), isEmpty);
      await indexer.reconcile();
      expect(await find('mike'), hasLength(1));
      expect(await find('november'), hasLength(1));

      // Stale: the file changed on disk.
      put('p1.json', _pageBytes('a', texts: ['oscar is here']));
      await indexer.reconcile();
      expect(await find('mike'), isEmpty);
      expect(await find('oscar'), hasLength(1));

      // Missing: a row deleted from the table comes back.
      await fs.database.delete('page_text', where: "page_file = 'p2.json'");
      expect(await find('november'), isEmpty);
      await indexer.reconcile();
      expect(await find('november'), hasLength(1));

      // Vanished page file: its row goes.
      File(p.join(dir, AppConfig.pagesDir, 'p2.json')).deleteSync();
      await indexer.reconcile();
      expect(await find('november'), isEmpty);

      // A notebook that left the library: its rows go, even those of a ghost.
      await indexer.index.apply('ghost', upsert: [
        const PageRow(
            notebookId: 'ghost',
            pageFile: 'p.json',
            pageId: null,
            pageIndex: 0,
            chapterId: null,
            text: PageText('papa', 'papa', 1, '1,0,0'),
            stamp: 's')
      ]);
      expect(await indexer.index.notebookIds(), containsAll(['r', 'ghost']));
      await indexer.reconcile();
      expect(await indexer.index.notebookIds(), ['r']);
    });

    test('an unreadable page does not break the others and is not retried',
        () async {
      await addNotebook('bad', 'Bad', [
        (file: 'p1.json', id: 'a', chapter: null),
        (file: 'p2.json', id: 'b', chapter: null),
      ], {
        'p1.json': Uint8List.fromList(utf8.encode('{ broken')),
        'p2.json': _pageBytes('b', texts: ['quebec']),
      });
      await indexer.flush();
      expect(await find('quebec'), hasLength(1));
      final before = await indexer.index.stored('bad');
      expect(before.keys, containsAll(['p1.json', 'p2.json']));
    });

    test('the isolate path gives the same rows', () async {
      final iso = SearchIndexer(fs, useIsolate: true, idle: () async {});
      addTearDown(iso.dispose);
      await addNotebook('iso', 'Iso', [
        (file: 'p1.json', id: 'a', chapter: null)
      ], {
        'p1.json': _pageBytes('a', texts: ['romeo'], maths: [r'\sigma'])
      });
      await iso.indexNotebook('iso');
      expect(await find('romeo'), hasLength(1));
      expect(await find('sigma'), hasLength(1));
    });
  });

  test('perf: 5000 pages indexed, query time', () async {
    final index = SearchIndex(fs.database);
    final rng = _Lcg(7);
    const words = [
      'resistor',
      'capacitor',
      'voltage',
      'current',
      'inductor',
      'transistor',
      'laplace',
      'fourier',
      'matrix',
      'vector',
      'integral',
      'derivative',
      'circuit',
      'theorem',
      'proof',
      'lemma',
      'signal',
      'filter',
      'gain',
      'phase',
      'impedance',
      'frequency',
      'amplifier',
      'diode',
      'battery',
    ];
    String sentence() =>
        List.generate(80, (_) => words[rng.next(words.length)]).join(' ');
    // 50 notebooks of 100 pages, ~600 characters of text per page.
    for (var n = 0; n < 50; n++) {
      await registerNotebook('perf$n', 'Perf $n',
          modified: DateTime(2026, 1, 1).add(Duration(days: n)));
      for (var b = 0; b < 5; b++) {
        await index.apply('perf$n', upsert: [
          for (var i = 0; i < 20; i++)
            PageRow(
              notebookId: 'perf$n',
              pageFile: 'page_${b * 20 + i}.json',
              pageId: 'id',
              pageIndex: b * 20 + i,
              chapterId: null,
              text: () {
                final s = sentence();
                return PageText(s, s, TextSource.text, '1,0,0');
              }(),
              stamp: '1:1',
            )
        ]);
      }
    }
    expect(await index.rowCount(), 5000);
    // One page has the needle; other queries match many rows.
    await index.apply('perf3', upsert: [
      const PageRow(
          notebookId: 'perf3',
          pageFile: 'needle.json',
          pageId: 'n',
          pageIndex: 999,
          chapterId: null,
          text: PageText(
              'the zygomorphic page', 'the zygomorphic page', 1, '1,0,0'),
          stamp: '1:1')
    ]);

    // Best of three: a loaded CI box should not decide the verdict.
    Future<int> time(String q) async {
      var best = 1 << 30, count = 0;
      for (var i = 0; i < 3; i++) {
        final sw = Stopwatch()..start();
        final hits = await search.search(q, limit: 100);
        sw.stop();
        count = hits.length;
        if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
      }
      // ignore: avoid_print
      print('perf: "$q" -> $count hits in $best ms (5000 pages)');
      return best;
    }

    await time('warm'); // first query opens statement caches
    final rare = await time('zygomorphic');
    final common = await time('resistor capacitor');
    final broad = await time('re');
    expect(rare, lessThan(50));
    expect(common, lessThan(50));
    expect(broad, lessThan(50));
  });
}

class _Lcg {
  _Lcg(this._s);
  int _s;
  int next(int n) {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return (_s >> 8) % n;
  }
}
