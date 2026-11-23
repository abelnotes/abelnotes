// The Drive backend is the first RemoteStore that isn't a filesystem behind
// HTTP: no paths, no ETags, and a server that says "slow down". These tests
// pin the three behaviours the sync engine depends on and cannot check for
// itself — path resolution, overwrite-by-id, and surviving a rate limit.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:abelnotes/core/services/google_drive_store.dart';
import 'package:abelnotes/core/services/remote_store.dart';
import 'package:abelnotes/core/services/sync_baselines.dart';
import 'package:abelnotes/core/services/sync_service.dart';

class _FixedAuth implements DriveAuth {
  @override
  Future<String> accessToken({bool forceRefresh = false}) async => 'token';
}

/// Records every request and answers from a scripted queue.
class _Fake {
  final List<http.BaseRequest> seen = [];
  final List<http.Response Function(http.Request)> script = [];

  http.Client get client => MockClient((req) async {
        seen.add(req);
        if (script.isEmpty) return http.Response('{}', 200);
        return script.removeAt(0)(req);
      });

  void reply(Object body, {int status = 200}) =>
      script.add((_) => http.Response(jsonEncode(body), status));

  void replyRaw(String body, {int status = 200}) =>
      script.add((_) => http.Response(body, status));
}

void main() {
  late _Fake fake;

  setUp(() => fake = _Fake());

  GoogleDriveStore store() =>
      GoogleDriveStore(_FixedAuth(), client: fake.client);

  test('walks the folder chain and caches what it resolved', () async {
    fake.reply({'files': [{'id': 'folder-1'}]});           // /AbelNotes/
    fake.reply({'files': [{'id': 'file-1'}]});             // nb.abelnote
    fake.reply({'id': 'file-1', 'size': '42', 'md5Checksum': 'abc'});

    final s = store();
    expect(await s.getVersion('/AbelNotes/nb.abelnote'), 'abc');

    // The lookup query must be scoped to the parent, else a same-named file
    // elsewhere in the user's Drive could be picked up.
    expect(fake.seen[1].url.queryParameters['q'],
        contains("'folder-1' in parents"));
    expect(fake.seen[1].url.queryParameters['q'],
        contains("name = 'nb.abelnote'"));

    // Second read of the same path resolves from cache: only the metadata
    // call goes out, not the two lookups.
    final before = fake.seen.length;
    fake.reply({'id': 'file-1', 'size': '42', 'md5Checksum': 'abc'});
    await s.getVersion('/AbelNotes/nb.abelnote');
    expect(fake.seen.length - before, 1);
  });

  test('a missing file is a 404, not an empty answer', () async {
    fake.reply({'files': [{'id': 'folder-1'}]});
    fake.reply({'files': []}); // no such child

    expect(
      () => store().downloadFile('/AbelNotes/ghost.abelnote'),
      throwsA(isA<RemoteStoreException>()
          .having((e) => e.statusCode, 'statusCode', 404)),
    );
  });

  test('re-uploading a known file updates it instead of creating a twin',
      () async {
    fake.reply({'files': [{'id': 'folder-1'}]});
    fake.reply({'files': [{'id': 'file-1'}]});
    fake.reply({'id': 'file-1', 'md5Checksum': 'v2'});

    final version = await store()
        .uploadFile('/AbelNotes/nb.abelnote', Uint8List.fromList([1, 2, 3]));

    expect(version, 'v2');
    final upload = fake.seen.last;
    // PATCH on the known id. A POST would leave two files with the same
    // name in the folder and the engine would read whichever came first.
    expect(upload.method, 'PATCH');
    expect(upload.url.path, contains('/files/file-1'));
    expect(upload.url.queryParameters['uploadType'], 'multipart');
  });

  test('renames in place by patching the name', () async {
    fake.reply({'files': [{'id': 'folder-1'}]}); // /AbelNotes/
    fake.reply({'files': []}); // target name is free
    fake.reply({'files': [{'id': 'file-1'}]}); // source
    fake.reply({'id': 'file-1'});

    await store().rename('/AbelNotes/nb.ncnote', '/AbelNotes/nb.abelnote');

    final patch = fake.seen.last as http.Request;
    expect(patch.method, 'PATCH');
    expect(patch.url.path, endsWith('/files/file-1'));
    expect(jsonDecode(patch.body), {'name': 'nb.abelnote'});
  });

  test('refuses to rename onto an existing file', () async {
    fake.reply({'files': [{'id': 'folder-1'}]});
    fake.reply({'files': [{'id': 'file-9'}]}); // target taken

    expect(
      () => store().rename('/AbelNotes/nb.ncnote', '/AbelNotes/nb.abelnote'),
      throwsA(isA<RemoteStoreException>()),
    );
  });

  test('a first upload creates the file under its parent', () async {
    fake.reply({'files': [{'id': 'folder-1'}]});
    fake.reply({'files': []}); // not there yet
    fake.reply({'id': 'file-new', 'md5Checksum': 'v1'});

    await store()
        .uploadFile('/AbelNotes/new.abelnote', Uint8List.fromList([9]));

    final upload = fake.seen.last as http.Request;
    expect(upload.method, 'POST');
    expect(upload.body, contains('"parents":["folder-1"]'));
  });

  test('retries a rate limit and then succeeds', () async {
    fake.reply({'files': [{'id': 'folder-1'}]});
    fake.reply({'files': [{'id': 'file-1'}]});
    fake.reply({
      'error': {
        'errors': [{'reason': 'userRateLimitExceeded'}],
        'message': 'Rate Limit Exceeded',
      }
    }, status: 403);
    fake.reply({'id': 'file-1', 'md5Checksum': 'v9'});

    final version = await store()
        .uploadFile('/AbelNotes/nb.abelnote', Uint8List.fromList([1]));

    expect(version, 'v9', reason: 'the retry should have gone through');
  });

  test('does not retry a 403 that means "not allowed"', () async {
    fake.reply({'files': [{'id': 'folder-1'}]});
    fake.reply({'files': [{'id': 'file-1'}]});
    fake.reply({
      'error': {
        'errors': [{'reason': 'insufficientFilePermissions'}],
        'message': 'The user does not have sufficient permissions',
      }
    }, status: 403);

    await expectLater(
      store().uploadFile('/AbelNotes/nb.abelnote', Uint8List.fromList([1])),
      throwsA(isA<RemoteStoreException>()
          .having((e) => e.statusCode, 'statusCode', 403)),
    );
    // Three calls: two lookups and the single refused upload. A retry here
    // would spin until the attempt budget ran out.
    expect(fake.seen.length, 3);
  });

  test('caps how many requests are in flight', () async {
    var live = 0;
    var peak = 0;
    final client = MockClient((req) async {
      live++;
      peak = peak > live ? peak : live;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      live--;
      return http.Response(jsonEncode({'files': [{'id': 'x'}]}), 200);
    });
    final s = GoogleDriveStore(_FixedAuth(), client: client);

    // Twenty parallel resolutions, the shape of a delta sync pushing every
    // changed page at once.
    await Future.wait([
      for (var i = 0; i < 20; i++) s.getVersion('/AbelNotes/page_$i.json'),
    ]);

    expect(peak, lessThanOrEqualTo(4));
  });

  test('an empty body is refused when the file has a size', () async {
    fake.reply({'files': [{'id': 'folder-1'}]});
    fake.reply({'files': [{'id': 'file-1'}]});
    fake.replyRaw(''); // truncated read dressed up as 200 OK
    fake.reply({'id': 'file-1', 'size': '1024'});

    expect(
      () => store().downloadFile('/AbelNotes/nb.abelnote'),
      throwsA(isA<RemoteStoreException>()
          .having((e) => e.statusCode, 'statusCode', 502)),
    );
  });

  test('a payload past the multipart limit goes resumable', () async {
    fake.reply({'files': [{'id': 'folder-1'}]});
    fake.reply({'files': []});
    // Session handshake: Drive answers with the URI to send the bytes to.
    fake.script.add((_) => http.Response('', 200,
        headers: {'location': 'https://upload.example/session-1'}));
    fake.reply({'id': 'big-1', 'md5Checksum': 'vbig'});

    final big = Uint8List(6 * 1024 * 1024); // a notebook with a PDF in it
    final version =
        await store().uploadFile('/AbelNotes/big.abelnote', big);

    expect(version, 'vbig');
    expect(fake.seen[2].url.queryParameters['uploadType'], 'resumable');
    expect(fake.seen[2].headers['X-Upload-Content-Length'], '6291456');
    // The bytes go to the session URI, not back to the API root.
    expect(fake.seen[3].method, 'PUT');
    expect(fake.seen[3].url.toString(), 'https://upload.example/session-1');
  });

  test('a small payload stays multipart', () async {
    fake.reply({'files': [{'id': 'folder-1'}]});
    fake.reply({'files': []});
    fake.reply({'id': 'small-1', 'md5Checksum': 'v1'});

    await store()
        .uploadFile('/AbelNotes/small.abelnote', Uint8List(1024));

    expect(fake.seen.last.url.queryParameters['uploadType'], 'multipart');
  });

  test('the sync engine runs on top of it end to end', () async {
    fake.reply({'files': [{'id': 'folder-1'}]});   // ensureBaseDirectory
    fake.reply({                                    // listDirectory
      'files': [
        {'id': 'f1', 'name': 'analisi.abelnote', 'mimeType': 'application/octet-stream', 'md5Checksum': 'aaa'},
        {'id': 'f2', 'name': 'notes.txt', 'mimeType': 'text/plain'},
      ]
    });

    final notebooks = await SyncService(store()).listRemoteNotebooks();

    expect(notebooks.map((n) => n.name), ['analisi.abelnote']);
    expect(notebooks.single.version, 'aaa');
  });

  test('listing maps Drive fields onto RemoteItem', () async {
    fake.reply({'files': [{'id': 'folder-1'}]});
    fake.reply({
      'files': [
        {
          'id': 'f1',
          'name': 'analisi.abelnote',
          'mimeType': 'application/octet-stream',
          'size': '2048',
          'md5Checksum': 'aaa',
          'modifiedTime': '2026-08-20T10:00:00.000Z',
        },
        {'id': 'd1', 'name': 'scratch', 'mimeType': 'application/vnd.google-apps.folder'},
      ]
    });

    final items = await store().listDirectory('/AbelNotes/');

    final file = items.firstWhere((i) => !i.isDirectory);
    expect(file.name, 'analisi.abelnote');
    expect(file.path, '/AbelNotes/analisi.abelnote');
    expect(file.contentLength, 2048);
    expect(file.version, 'aaa');
    expect(file.lastModified, DateTime.utc(2026, 8, 20, 10));

    final dir = items.firstWhere((i) => i.isDirectory);
    expect(dir.path, '/AbelNotes/scratch/', reason: 'directories keep a slash');
  });

  // ── Stale ids, duplicate folders, query escaping ──────────────────────

  const notFound = {
    'error': {'message': 'File not found'}
  };

  /// Primes the id cache the way a sync does: folder lookup, then listing.
  Future<GoogleDriveStore> storeWithListedFile() async {
    fake.reply({'files': [{'id': 'folder-1'}]});
    fake.reply({
      'files': [
        {'id': 'f1', 'name': 'nb.abelnote', 'mimeType': 'application/octet-stream'},
      ]
    });
    final s = store();
    await s.listDirectory('/AbelNotes/');
    fake.seen.clear();
    return s;
  }

  test('delete treats a 404 on a stale cached id as already gone', () async {
    final s = await storeWithListedFile();
    fake.reply(notFound, status: 404); // DELETE f1: removed by another device

    await s.delete('/AbelNotes/nb.abelnote');

    expect(fake.seen.first.method, 'DELETE');
  });

  test('a stale id is dropped and re-resolved for metadata reads', () async {
    final s = await storeWithListedFile();
    fake.reply(notFound, status: 404); // GET f1
    fake.reply({'files': [{'id': 'f2'}]}); // re-created under a new id
    fake.reply({'id': 'f2', 'md5Checksum': 'new'});

    expect(await s.getVersion('/AbelNotes/nb.abelnote'), 'new');
    expect(fake.seen.last.url.path, endsWith('/files/f2'));
  });

  test('a stale id for a vanished file reads as absent, not an error',
      () async {
    final s = await storeWithListedFile();
    fake.reply(notFound, status: 404);
    fake.reply({'files': []});

    expect(await s.getVersion('/AbelNotes/nb.abelnote'), isNull);
  });

  test('upload over a stale id falls back to creating the file', () async {
    final s = await storeWithListedFile();
    fake.reply(notFound, status: 404); // PATCH f1
    fake.reply({'files': []}); // really gone
    fake.reply({'id': 'f9', 'md5Checksum': 'v1'});

    final version =
        await s.uploadFile('/AbelNotes/nb.abelnote', Uint8List.fromList([1]));

    expect(version, 'v1');
    final last = fake.seen.last as http.Request;
    expect(last.method, 'POST');
    expect(last.body, contains('"parents":["folder-1"]'));
  });

  test('rename over a stale source id re-resolves it', () async {
    final s = await storeWithListedFile();
    fake.reply({'files': []}); // target free
    fake.reply(notFound, status: 404); // PATCH f1
    fake.reply({'files': [{'id': 'f2'}]});
    fake.reply({'id': 'f2'});

    await s.rename('/AbelNotes/nb.abelnote', '/AbelNotes/other.abelnote');

    expect(fake.seen.last.method, 'PATCH');
    expect(fake.seen.last.url.path, endsWith('/files/f2'));
  });

  test('concurrent creates of the same missing folder make only one',
      () async {
    var created = 0;
    final client = MockClient((req) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (req.method == 'POST') {
        created++;
        return http.Response(jsonEncode({'id': 'new-$created'}), 200);
      }
      return http.Response(jsonEncode({'files': []}), 200);
    });
    final s = GoogleDriveStore(_FixedAuth(), client: client);

    await Future.wait([
      s.createDirectory('/AbelNotes/.sync/'),
      s.createDirectory('/AbelNotes/.sync/'),
      s.createDirectory('/AbelNotes/'),
    ]);

    expect(created, 2, reason: '/AbelNotes/ once and .sync/ once');
  });

  test('a failed folder create does not wedge later attempts', () async {
    var posts = 0;
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        posts++;
        return posts == 1
            ? http.Response(jsonEncode(notFound), 400)
            : http.Response(jsonEncode({'id': 'ok'}), 200);
      }
      return http.Response(jsonEncode({'files': []}), 200);
    });
    final s = GoogleDriveStore(_FixedAuth(), client: client);

    await expectLater(s.createDirectory('/Notes/'),
        throwsA(isA<RemoteStoreException>()));
    await s.createDirectory('/Notes/');
    expect(posts, 2);
  });

  test('backslashes and quotes in a name are escaped in the query', () async {
    fake.reply({'files': [{'id': 'folder-1'}]});
    fake.reply({'files': [{'id': 'file-1'}]});
    fake.reply({'id': 'file-1', 'md5Checksum': 'v'});

    await store().getVersion(r"/AbelNotes/a\b'c.json");

    expect(fake.seen[1].url.queryParameters['q'],
        contains(r"name = 'a\\b\'c.json'"));
  });

  test('two concurrent uploads of a new file create it once', () async {
    fake.reply({'files': [{'id': 'folder-1'}]}); // /AbelNotes/
    fake.reply({'files': []}); // x.json not there yet
    fake.reply({'id': 'file-1', 'md5Checksum': 'a'}); // the create
    fake.reply({'id': 'file-1', 'md5Checksum': 'b'}); // the second write

    final s = store();
    await Future.wait([
      s.uploadFile('/AbelNotes/x.json', Uint8List.fromList([1])),
      s.uploadFile('/AbelNotes/x.json', Uint8List.fromList([2])),
    ]);

    // Two POSTs would leave two files named x.json, read at random later.
    expect(fake.seen.where((r) => r.method == 'POST').length, 1);
    expect(fake.seen.last.method, 'PATCH');
  });

  group('conditional upload', () {
    final data = Uint8List.fromList([1, 2]);

    test('writes over the version it was based on, atomically', () async {
      fake.reply({'files': [{'id': 'folder-1'}]});
      fake.reply({'files': [{'id': 'file-1'}]});
      fake.reply({'etag': '"e1"', 'md5Checksum': 'v1'}); // v2 metadata
      fake.reply({'md5Checksum': 'v2'}); // the conditional PUT

      final v = await store().uploadFileConditional('/AbelNotes/folders.json',
          data, ifMatchVersion: 'v1');

      expect(v, 'v2');
      final put = fake.seen.last;
      expect(put.method, 'PUT');
      expect(put.url.path, '/upload/drive/v2/files/file-1');
      // The check and the write are one request: a write landing between
      // a separate check and write was erased without anyone noticing.
      expect(put.headers['If-Match'], '"e1"');
    });

    test('a write that loses the race is a 412, not an overwrite', () async {
      fake.reply({'files': [{'id': 'folder-1'}]});
      fake.reply({'files': [{'id': 'file-1'}]});
      fake.reply({'etag': '"e1"', 'md5Checksum': 'v1'});
      fake.reply({'error': {'code': 412}}, status: 412); // someone wrote
      fake.reply({'etag': '"e2"', 'md5Checksum': 'theirs'});

      await expectLater(
        store().uploadFileConditional('/AbelNotes/folders.json', data,
            ifMatchVersion: 'v1'),
        throwsA(isA<RemoteStoreException>()
            .having((e) => e.statusCode, 'statusCode', 412)),
      );
    });

    test('a metadata-only etag change retries the write', () async {
      fake.reply({'files': [{'id': 'folder-1'}]});
      fake.reply({'files': [{'id': 'file-1'}]});
      fake.reply({'etag': '"e1"', 'md5Checksum': 'v1'});
      fake.reply({'error': {'code': 412}}, status: 412);
      fake.reply({'etag': '"e2"', 'md5Checksum': 'v1'}); // same content
      fake.reply({'md5Checksum': 'v2'});

      final v = await store().uploadFileConditional('/AbelNotes/folders.json',
          data, ifMatchVersion: 'v1');

      expect(v, 'v2');
      expect(fake.seen.last.headers['If-Match'], '"e2"');
    });

    test('refuses with 412 and writes nothing when the version moved', () async {
      fake.reply({'files': [{'id': 'folder-1'}]});
      fake.reply({'files': [{'id': 'file-1'}]});
      fake.reply({'id': 'file-1', 'md5Checksum': 'other'});

      await expectLater(
        store().uploadFileConditional('/AbelNotes/folders.json', data,
            ifMatchVersion: 'v1'),
        throwsA(isA<RemoteStoreException>()
            .having((e) => e.statusCode, 'statusCode', 412)),
      );
      expect(fake.seen.where((r) => r.method != 'GET'),
          isEmpty);
    });

    test('ifAbsent creates a missing file and refuses an existing one',
        () async {
      fake.reply({'files': [{'id': 'folder-1'}]});
      fake.reply({'files': []}); // not there
      fake.reply({'files': []}); // upload looks again before creating
      fake.reply({'id': 'file-new', 'md5Checksum': 'v1'});
      final s = store();
      await s.uploadFileConditional('/AbelNotes/folders.json', data,
          ifAbsent: true);
      expect(fake.seen.last.method, 'POST');

      // Now it exists (id cached from the create).
      fake.reply({'id': 'file-new', 'md5Checksum': 'v1'});
      await expectLater(
        s.uploadFileConditional('/AbelNotes/folders.json', data,
            ifAbsent: true),
        throwsA(isA<RemoteStoreException>()
            .having((e) => e.statusCode, 'statusCode', 412)),
      );
    });
  });

  group('baseline identity', () {
    test('is the root folder id: another account or folder is another key',
        () async {
      fake.reply({'files': [{'id': 'root-A'}]});
      final s = store();
      expect(await s.baselineIdentity(), 'drive|root-A');
      expect(fake.seen.single.url.queryParameters['q'],
          contains("'root' in parents"));
      // Cached: no second lookup.
      expect(await s.baselineIdentity(), 'drive|root-A');
      expect(fake.seen, hasLength(1));

      fake.reply({'files': [{'id': 'root-B'}]});
      expect(await store().baselineIdentity(), 'drive|root-B');
    });

    test('a missing folder or an unreachable Drive gives no key', () async {
      fake.reply({'files': <Object>[]});
      expect(await store().baselineIdentity(), isNull);
      expect(await SyncBaselines.identityOf(GoogleDriveStore(_FixedAuth(),
              client: MockClient((_) async => throw http.ClientException('offline')))),
          isNull);
    });
  });
}
