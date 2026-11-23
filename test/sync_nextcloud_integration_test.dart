// Two simulated devices against a real Nextcloud (Tier B of the arch-split
// plan). Skipped unless ABELNOTES_NC_URL / _USER / _PASS are set:
//
//   ABELNOTES_NC_URL=http://localhost:8080 ABELNOTES_NC_USER=tierb \
//   ABELNOTES_NC_PASS=... flutter test test/sync_nextcloud_integration_test.dart
//
// A device = own temp dir + own SQLite + own SharedPreferences snapshot +
// own ProviderContainer. Prefs and path provider are process-wide, so only one
// device is active at a time (run) and the others' stores park their calls.

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/providers/notebook_provider.dart';
import 'package:abelnotes/core/services/remote_store.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/core/services/webdav_service.dart';
import 'package:abelnotes/core/sync/stroke_ops.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/sync_devices.dart';

final _env = Platform.environment;
final _url = _env['ABELNOTES_NC_URL'];
final _user = _env['ABELNOTES_NC_USER'] ?? '';
final _pass = _env['ABELNOTES_NC_PASS'] ?? '';

WebDavService _dav() => WebDavService(
    serverUrl: _url!, username: _user, password: _pass);

typedef _Device = SyncDevice;
const _pageFile = kPageFile;
List<String> _ids(PageData? p) => idsOf(p);
String _norm(PageData p) => normPage(p);
List<SyncDevice> get _all => syncDevices;

void main() {
  final skip = _url == null
      ? 'ABELNOTES_NC_URL not set (needs a Nextcloud with a dedicated test user)'
      : (_user.isEmpty || _pass.isEmpty)
          ? 'ABELNOTES_NC_USER / ABELNOTES_NC_PASS not set'
          : false;

  TestWidgetsFlutterBinding.ensureInitialized();

  late _Device a, b;
  late WebDavService admin; // uncounted view of the server

  setUpAll(() {
    HttpOverrides.global = null; // the test binding fakes every request with 400
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    admin = _dav();
    try {
      await admin.delete(AppConfig.defaultRemotePath);
    } on RemoteStoreException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    await admin.ensureBaseDirectory();
    _all.clear();
    a = _Device('a', DeviceStore(_dav()));
    b = _Device('b', DeviceStore(_dav()));
    _all.addAll([a, b]);
    for (final d in _all) {
      await d.init();
    }
  });

  tearDown(() async {
    StrokeOps.restoreDefaults();
    for (final d in _all) {
      await d.dispose();
    }
    _all.clear();
    admin.dispose();
  });

  /// A creates a notebook with one stroke and gets it onto the server.
  Future<NotebookEntry> createOnA({String stroke = 'a0'}) async {
    return a.run(() async {
      final e = await a.library.createNotebook(title: 'Nc Test');
      // The root upload is a background task: wait until the server lists it.
      var listed = false;
      for (var i = 0; i < 100 && !listed; i++) {
        listed = (await admin.listDirectory(AppConfig.defaultRemotePath))
            .any((x) => x.name.endsWith(AppConfig.storageExtension));
        if (!listed) await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(listed, isTrue);
      await a.open(e);
      a.draw(stroke, y: 50);
      await a.canvas.save();
      return e;
    });
  }

  Future<PageData> serverPage(String id, [String file = _pageFile]) =>
      SyncService(admin).downloadDeltaPage(id, file);

  test('1. round trip: A creates + saves, B downloads and sees the stroke',
      () async {
    final e = await createOnA();
    final id = e.metadata.id;

    final onServer = await serverPage(id);
    expect(_ids(onServer), ['a0']);

    await b.run(() async {
      await b.library.refresh();
      final list = b.c.read(notebookListProvider).valueOrNull ?? [];
      final be = list.singleWhere((x) => x.metadata.id == id);
      await b.open(be);
      expect(_ids(b.state!.pages[_pageFile]), ['a0']);
      expect(_norm(b.state!.pages[_pageFile]!),
          _norm(a.state!.pages[_pageFile]!));
      expect(_norm(b.state!.pages[_pageFile]!), _norm(onServer));
    });
  }, skip: skip);

  test('2. same page edited on both devices from one base: both strokes kept',
      () async {
    final e = await createOnA();
    final id = e.metadata.id;
    await b.run(() async {
      await b.library.refresh();
      final be = (b.c.read(notebookListProvider).valueOrNull ?? [])
          .singleWhere((x) => x.metadata.id == id);
      await b.open(be);
      expect(_ids(b.state!.pages[_pageFile]), ['a0']);
    });
    // Both open at base [a0]; A saves first, B saves on top of it.
    await a.run(() async {
      a.draw('sa', y: 120);
      await a.canvas.save();
    });
    await b.run(() async {
      b.draw('sb', y: 160);
      await b.canvas.save();
      await b.waitFor(() => _ids(b.state!.pages[_pageFile]).contains('sa'));
    });
    await a.run(() async {
      await a.waitFor(() => _ids(a.state!.pages[_pageFile]).contains('sb'));
    });
    final want = ['a0', 'sa', 'sb'];
    expect(_ids(a.state!.pages[_pageFile]), want, reason: 'device A');
    expect(_ids(b.state!.pages[_pageFile]), want, reason: 'device B');
    expect(_ids(await serverPage(id)), want, reason: 'server');
  }, skip: skip);

  test('3. B edits offline while A edits, B reconnects: both strokes survive',
      () async {
    final e = await createOnA();
    final id = e.metadata.id;
    await b.run(() async {
      await b.library.refresh();
      final be = (b.c.read(notebookListProvider).valueOrNull ?? [])
          .singleWhere((x) => x.metadata.id == id);
      await b.open(be);
    });
    await b.run(() async {
      b.store.offline = true;
      b.draw('sb', y: 160);
      await b.canvas.save();
    });
    await a.run(() async {
      a.draw('sa', y: 120);
      await a.canvas.save();
    });
    expect(_ids(await serverPage(id)), ['a0', 'sa']);

    await b.run(() async {
      expect(_ids(b.state!.pages[_pageFile]), ['a0', 'sb'],
          reason: 'the offline edit is still here');
      b.store.offline = false;
      // Reconnect: the app's own retry/pull must reconcile, then a save pushes.
      await b.waitFor(
          () => _ids(b.state!.pages[_pageFile]).contains('sa'));
      await b.canvas.save();
      await b.waitFor(() => !b.state!.isDirty);
    });
    await a.run(() async {
      await a.waitFor(() => _ids(a.state!.pages[_pageFile]).contains('sb'));
    });
    final want = ['a0', 'sa', 'sb'];
    expect(_ids(b.state!.pages[_pageFile]), want, reason: 'device B');
    expect(_ids(a.state!.pages[_pageFile]), want, reason: 'device A');
    expect(_ids(await serverPage(id)), want, reason: 'server');
  }, skip: skip);

  Future<NotebookEntry> syncToB(String id) async {
    await b.library.refresh();
    return (b.c.read(notebookListProvider).valueOrNull ?? [])
        .singleWhere((x) => x.metadata.id == id);
  }

  // Characterisation, not a spec: records what the app does today.
  test('4. A deletes a page while B edits it (characterisation)', () async {
    final e = await createOnA();
    final id = e.metadata.id;
    await a.run(() async {
      a.canvas.addPage();
      await a.canvas.save();
    });
    expect(a.state!.document.pages.length, 2);
    final doomed = a.state!.document.pages[1].fileName;
    expect(_ids(await serverPage(id, doomed)), isEmpty);

    await b.run(() async {
      await b.open(await syncToB(id));
      await b.waitFor(() => b.state!.document.pages.length == 2);
      expect(b.state!.document.pages.length, 2);
    });
    await a.run(() async {
      a.canvas.deletePage(1);
      await a.canvas.save();
    });
    await b.run(() async {
      b.draw('sb', file: doomed, y: 160);
      await b.canvas.save();
      await Future<void>.delayed(const Duration(seconds: 8));
    });
    await a.run(() async {
      await Future<void>.delayed(const Duration(seconds: 6));
    });

    final docOnServer = (await admin.listDirectory(
            '${AppConfig.defaultRemotePath}${AppConfig.deltaSyncDir}$id/pages/'))
        .map((x) => x.name)
        .toList()
      ..sort();
    // ignore: avoid_print
    print('[CHAR 4] A pages=${a.state!.document.pages.map((p) => p.fileName).toList()} '
        'B pages=${b.state!.document.pages.map((p) => p.fileName).toList()} '
        'B has stroke sb=${_ids(b.state!.pages[doomed]).contains('sb')} '
        'server page files=$docOnServer '
        'B keptLocal/hasSyncFailure=${b.canvas.keptLocal.value}/${b.canvas.hasSyncFailure.value} '
        'B pendingConflicts=${b.state!.pendingConflicts.length}');

    // Today: the server and A lose the page; B is not silently overwritten:
    // its pull raises an "edited here, deleted there" conflict for the user,
    // and B keeps the page (and the stroke) until it is resolved.
    expect(a.state!.document.pages.map((p) => p.fileName), isNot(contains(doomed)));
    expect(docOnServer, isNot(contains(doomed)));
    final conflicts = b.state!.pendingConflicts;
    expect(conflicts.map((c) => c.fileName), [doomed]);
    expect(conflicts.single.isDeletion, isTrue);
    expect(_ids(b.state!.pages[doomed]), contains('sb'));
  }, skip: skip);

  /// A notebook of [n] pages on A, each carrying a stroke, pushed.
  Future<NotebookEntry> bigOnA(int n) async {
    final e = await createOnA();
    await a.run(() async {
      for (var i = 1; i < n; i++) {
        a.canvas.addPage();
      }
      a.drawAll('p');
      a.store
        ..puts = 0
        ..maxPuts = 0;
      await a.canvas.save();
    });
    return e;
  }

  test('5. first download of a ~40 page notebook: GETs per page', () async {
    const n = 40;
    final e = await bigOnA(n);
    final id = e.metadata.id;
    expect(a.state!.document.pages.length, n);

    final phases = <String, int>{};
    int pageGets() => b.store.getsByPath.entries
        .where((x) => x.key.contains('/pages/'))
        .fold(0, (t, x) => t + x.value);
    await b.run(() async {
      final be = await syncToB(id);
      phases['after library refresh'] = pageGets();
      await b.open(be);
      phases['after open (fetch)'] = pageGets();
      await b.waitFor(() => b.state!.document.pages.length == n);
      // Let the pull loop run a few cycles: it must not fetch them again.
      await Future<void>.delayed(const Duration(seconds: 8));
      phases['after 8 s of pulling'] = pageGets();
    });
    final perPage = b.store.getsByPath.entries
        .where((x) => x.key.contains('/pages/'))
        .map((x) => x.value);
    final distinct = perPage.length;
    final maxPer = perPage.fold(0, (m, v) => v > m ? v : m);
    final total = perPage.fold(0, (t, v) => t + v);
    // ignore: avoid_print
    print('[MEASURE 5] pages=$n distinct page files fetched=$distinct '
        'total page GETs=$total (${(total / n).toStringAsFixed(2)} per page), '
        'max per page=$maxPer, phases=$phases, '
        'other GETs=${b.store.getsByPath.entries.where((x) => !x.key.contains('/pages/')).map((x) => '${x.key.split('/').last}:${x.value}').toList()}');
    expect(b.state!.document.pages.length, n);
    expect(distinct, n, reason: 'every page arrives');
    // Current behaviour: pinned so a change (better or worse) is noticed.
    expect(maxPer, lessThanOrEqualTo(3));
  }, skip: skip);

  test('6. ~40 changed pages saved at once: peak concurrent PUTs', () async {
    const n = 40;
    final e = await bigOnA(n);
    final id = e.metadata.id;
    final firstPeak = a.store.maxPuts, firstPuts = a.store.puts;
    final last = a.state!.document.pages.last.fileName;
    expect(_ids(await serverPage(id, last)), ['p-$last']);

    await a.run(() async {
      a.store
        ..puts = 0
        ..maxPuts = 0;
      a.drawAll('q');
      await a.canvas.save();
    });
    // ignore: avoid_print
    print('[MEASURE 6] $n pages: first push puts=$firstPuts peak concurrent=$firstPeak; '
        'second push (all $n changed) puts=${a.store.puts} peak concurrent=${a.store.maxPuts}');
    expect(_ids(await serverPage(id, last)), ['p-$last', 'q-$last']);
    expect(a.store.maxPuts, greaterThan(0));
  }, skip: skip);

  // Stroke delta chunks (lib/core/sync/README.md), flags on for these only.
  int chunkPuts(_Device d) => d.store.putPaths
      .where((p) => p.contains('/${StrokeOps.folder}'))
      .length;
  int pagePuts(_Device d) =>
      d.store.putPaths.where((p) => p.contains('/pages/')).length;

  Future<void> bothOpenWithChunks(String id) async {
    await b.run(() async {
      await b.open(await syncToB(id));
    });
    // One round on each so both hold a baseline read or written by the
    // same sync service: from here on edits travel as chunks.
    await a.run(() async {
      a.draw('a1', y: 70);
      await a.canvas.save();
    });
    await b.run(() async {
      await b.waitFor(() => _ids(b.state!.pages[_pageFile]).contains('a1'));
    });
    a.store.putPaths.clear();
    b.store.putPaths.clear();
  }

  test('7. chunks: both devices draw offline on one page, then online: '
      'union, no page rewrite', () async {
    StrokeOps.read = true;
    StrokeOps.write = true;
    final e = await createOnA();
    final id = e.metadata.id;
    await bothOpenWithChunks(id);
    await a.run(() async {
      a.store.offline = true;
      a.draw('sa', y: 120);
      await a.canvas.save();
    });
    await b.run(() async {
      b.store.offline = true;
      b.draw('sb', y: 160);
      await b.canvas.save();
    });
    await a.run(() async {
      a.store.offline = false;
      expect(await a.waitFor(() => a.state!.isDirty), isTrue);
      await a.canvas.save();
    });
    await b.run(() async {
      b.store.offline = false;
      await b.waitFor(() => _ids(b.state!.pages[_pageFile]).contains('sa'));
      await b.canvas.save();
      await b.waitFor(() => !b.state!.isDirty);
    });
    await a.run(() async {
      await a.waitFor(() => _ids(a.state!.pages[_pageFile]).contains('sb'));
    });
    const want = ['a0', 'a1', 'sa', 'sb'];
    expect(_ids(a.state!.pages[_pageFile]), want, reason: 'device A');
    expect(_ids(b.state!.pages[_pageFile]), want, reason: 'device B');
    expect(_ids(await serverPage(id)), want, reason: 'server');
    expect(a.state!.pendingConflicts, isEmpty);
    expect(b.state!.pendingConflicts, isEmpty);
    // ignore: avoid_print
    print('[OPS 7] A: ${chunkPuts(a)} chunk / ${pagePuts(a)} page PUTs, '
        'B: ${chunkPuts(b)} chunk / ${pagePuts(b)} page PUTs');
    expect(chunkPuts(a) + chunkPuts(b), 2);
    expect(pagePuts(a) + pagePuts(b), 0);
  }, skip: skip);

  test('8. chunks: an erase on A and a stroke on B both stand', () async {
    StrokeOps.read = true;
    StrokeOps.write = true;
    final e = await createOnA();
    final id = e.metadata.id;
    await bothOpenWithChunks(id);
    await b.run(() async {
      b.store.offline = true;
      b.draw('sb', y: 160);
      await b.canvas.save();
    });
    await a.run(() async {
      final s = a.state!;
      final page = s.pages[_pageFile]!;
      a.canvas.state = s.copyWith(pages: {
        ...s.pages,
        _pageFile: page.copyWith(
            layers: page.layers.copyWith(content: [
          for (final x in page.layers.content)
            if (x.id != 'a0') x,
        ])),
      }, isDirty: true);
      await a.canvas.save();
    });
    await b.run(() async {
      b.store.offline = false;
      await b.waitFor(() => !_ids(b.state!.pages[_pageFile]).contains('a0'));
      await b.canvas.save();
      await b.waitFor(() => !b.state!.isDirty);
    });
    await a.run(() async {
      await a.waitFor(() => _ids(a.state!.pages[_pageFile]).contains('sb'));
    });
    const want = ['a1', 'sb'];
    expect(_ids(a.state!.pages[_pageFile]), want, reason: 'device A');
    expect(_ids(b.state!.pages[_pageFile]), want, reason: 'device B');
    expect(_ids(await serverPage(id)), want, reason: 'server');
  }, skip: skip);

  test('9. chunks: a release without them sees every stroke once A closes',
      () async {
    StrokeOps.read = true;
    StrokeOps.write = true;
    final e = await createOnA();
    final id = e.metadata.id;
    await a.run(() async {
      for (var i = 1; i <= 3; i++) {
        a.draw('s$i', y: 60.0 + i * 20);
        await a.canvas.save();
      }
    });
    expect(chunkPuts(a), greaterThan(0));
    await a.run(() => a.canvas.closeNotebook());
    StrokeOps.read = false;
    StrokeOps.write = false;
    expect(_ids(await serverPage(id)), ['a0', 's1', 's2', 's3']);
    final ops = await admin
        .listDirectory('${AppConfig.defaultRemotePath}${AppConfig.deltaSyncDir}$id/${StrokeOps.folder}')
        .catchError((Object _) => <RemoteItem>[]);
    expect(ops.where((x) => !x.isDirectory), isEmpty);
    await b.run(() async {
      await b.open(await syncToB(id));
      expect(_ids(b.state!.pages[_pageFile]), ['a0', 's1', 's2', 's3']);
      b.draw('old', y: 300);
      await b.canvas.save();
    });
    expect(_ids(await serverPage(id)), ['a0', 'old', 's1', 's2', 's3']);
  }, skip: skip);

  test('10. read on, write off: B only reads, pulls A\'s chunks, folds them '
      'into its page write, both converge', () async {
    a.writesChunks = true; // a later release
    b.writesChunks = false; // this release
    final e = await createOnA();
    final id = e.metadata.id;
    await bothOpenWithChunks(id);
    await a.run(() async {
      a.draw('a2', y: 90);
      await a.canvas.save();
    });
    expect(chunkPuts(a), greaterThan(0), reason: 'A writes chunks');
    await b.run(() async {
      expect(await b.waitFor(() => _ids(b.state!.pages[_pageFile]).contains('a2')),
          isTrue);
      b.draw('b1', y: 160);
      await b.canvas.save();
      await b.waitFor(() => !b.state!.isDirty);
    });
    expect(chunkPuts(b), 0, reason: 'B never writes a chunk');
    expect(pagePuts(b), greaterThan(0));
    final ops = await admin
        .listDirectory('${AppConfig.defaultRemotePath}${AppConfig.deltaSyncDir}$id/${StrokeOps.folder}')
        .catchError((Object _) => <RemoteItem>[]);
    expect(ops.where((x) => !x.isDirectory), isEmpty,
        reason: 'B folded and deleted the chunks it read');
    await a.run(() async {
      await a.waitFor(() => _ids(a.state!.pages[_pageFile]).contains('b1'));
      a.draw('a3', y: 110);
      await a.canvas.save();
      await a.waitFor(() => !a.state!.isDirty);
    });
    await b.run(() async {
      await b.waitFor(() => _ids(b.state!.pages[_pageFile]).contains('a3'));
    });
    const want = ['a0', 'a1', 'a2', 'a3', 'b1'];
    expect(_ids(a.state!.pages[_pageFile]), want, reason: 'device A');
    expect(_ids(b.state!.pages[_pageFile]), want, reason: 'device B');
    expect(_ids(await serverPage(id)), want, reason: 'server');
    expect(a.state!.pendingConflicts, isEmpty);
    expect(b.state!.pendingConflicts, isEmpty);
  }, skip: skip);
}
