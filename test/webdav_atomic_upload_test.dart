// An overwritten page must never be left half-written on the server: a PUT
// cut off midway made Nextcloud keep the truncated bytes in place of the
// good file. uploadFileAtomic goes through a temporary file and a MOVE.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/remote_store.dart';
import 'package:abelnotes/core/services/webdav_service.dart';

void main() {
  late HttpServer server;
  final store = <String, ({List<int> body, String etag})>{};
  final log = <String>[];
  final moveIfHeaders = <String?>[];
  var counter = 0;
  var failPutsTo = '';

  setUp(() async {
    store.clear();
    log.clear();
    moveIfHeaders.clear();
    counter = 0;
    failPutsTo = '';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await req.fold<List<int>>([], (a, b) => a..addAll(b));
      final path = Uri.decodeFull(req.uri.path);
      log.add('${req.method} $path');
      switch (req.method) {
        case 'PUT':
          if (failPutsTo.isNotEmpty && path.contains(failPutsTo)) {
            req.response.statusCode = 400;
            break;
          }
          final etag = 'e${++counter}';
          store[path] = (body: body, etag: etag);
          req.response.statusCode = 201;
          req.response.headers.set('etag', '"$etag"');
        case 'MOVE':
          moveIfHeaders.add(req.headers.value('if'));
          final dest =
              Uri.decodeFull(Uri.parse(req.headers.value('destination')!).path);
          final cond = req.headers.value('if');
          if (cond != null) {
            final m = RegExp(r'^<([^>]+)> \(\["([^"]+)"\]\)$').firstMatch(cond)!;
            final cur = store[Uri.decodeFull(m.group(1)!)];
            if (cur == null || cur.etag != m.group(2)) {
              req.response.statusCode = 412;
              break;
            }
          }
          final src = store.remove(path)!;
          store[dest] = src;
          req.response.statusCode = 204;
          req.response.headers.set('etag', '"${src.etag}"');
        case 'DELETE':
          store.remove(path);
          req.response.statusCode = 204;
        case 'PROPFIND':
          final cur = store[path];
          if (cur == null) {
            req.response.statusCode = 404;
            break;
          }
          req.response.statusCode = 207;
          req.response.write('<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">'
              '<d:response><d:href>$path</d:href><d:propstat><d:prop>'
              '<d:getetag>"${cur.etag}"</d:getetag></d:prop>'
              '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>'
              '</d:multistatus>');
        default:
          req.response.statusCode = 404;
      }
      await req.response.close();
    });
  });
  tearDown(() => server.close(force: true));

  WebDavService dav({bool preconditionHeader = true}) {
    final d = WebDavService(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'u',
        password: 'p',
        preconditionHeader: preconditionHeader);
    addTearDown(d.dispose);
    return d;
  }

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
  String? at(String suffix) {
    final hit = store.entries.where((e) => e.key.endsWith(suffix));
    return hit.isEmpty ? null : utf8.decode(hit.single.value.body);
  }

  bool tmpLeft() => store.keys.any((k) => k.contains(atomicUploadMarker));

  Future<String> seed(WebDavService d) async =>
      (await d.uploadFile('/p.json', bytes('good')))!;

  test('the new content replaces the old one through a rename', () async {
    final d = dav();
    final v1 = await seed(d);

    final v2 = await d.uploadFileAtomic('/p.json', bytes('newer'),
        ifMatchVersion: v1);

    expect(at('/p.json'), 'newer');
    expect(v2, isNot(v1));
    expect(tmpLeft(), isFalse);
    expect(log.where((l) => l.startsWith('MOVE')), hasLength(1));
  });

  test('a stale version leaves the page alone and the temp file gone',
      () async {
    final d = dav();
    await seed(d);

    await expectLater(
      d.uploadFileAtomic('/p.json', bytes('stale edit'),
          ifMatchVersion: 'not-the-current-one'),
      throwsA(isA<RemoteStoreException>()
          .having((e) => e.statusCode, 'statusCode', 412)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(at('/p.json'), 'good');
    expect(tmpLeft(), isFalse);
  });

  test('a failed upload never touches the page', () async {
    final d = dav();
    await seed(d);
    failPutsTo = atomicUploadMarker;

    await expectLater(
      d.uploadFileAtomic('/p.json', bytes('cut off')),
      throwsA(isA<RemoteStoreException>()),
    );
    expect(at('/p.json'), 'good');
    expect(log.any((l) => l.startsWith('MOVE')), isFalse);
  });

  test('on the web the check runs before the move, with no If header',
      () async {
    final d = dav(preconditionHeader: false);
    final v1 = await seed(d);

    await d.uploadFileAtomic('/p.json', bytes('newer'), ifMatchVersion: v1);
    expect(at('/p.json'), 'newer');
    expect(moveIfHeaders.single, isNull, reason: 'CORS setups block it');

    await expectLater(
      d.uploadFileAtomic('/p.json', bytes('stale edit'), ifMatchVersion: v1),
      throwsA(isA<RemoteStoreException>()
          .having((e) => e.statusCode, 'statusCode', 412)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(at('/p.json'), 'newer');
    expect(tmpLeft(), isFalse);
    expect(log.where((l) => l.startsWith('MOVE')), hasLength(1));
  });
}
