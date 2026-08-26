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
}
