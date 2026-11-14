import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/core/services/webdav_service.dart';

void main() {
  late HttpServer server;
  final seen = <Uri>[];
  setUp(() async {
    seen.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      seen.add(request.uri);
      final fresh = request.uri.queryParameters.containsKey('_abelnotes_read');
      request.response.statusCode = 200;
      request.response.headers.set('ETag', fresh ? '"new"' : '"old"');
      if (request.method != 'HEAD') {
        // Simulate an HTTP cache containing the pre-MOVE response.
        request.response.write(fresh ? 'new' : 'old');
      }
      await request.response.close();
    });
  });
  tearDown(() => server.close(force: true));

  WebDavService dav(bool freshReads) {
    final d = WebDavService(
      serverUrl: 'http://127.0.0.1:${server.port}',
      username: 'synthetic',
      password: 'synthetic',
      serverType: WebDavServerType.generic,
      freshReads: freshReads,
    );
    addTearDown(d.dispose);
    return d;
  }

  test('web reads use unique cache keys on GET and HEAD without changing path',
      () async {
    final d = dav(true);
    expect(utf8.decode(await d.downloadFile('/AbelNotes/page #1.json')), 'new');
    expect(utf8.decode(await d.downloadFile('/AbelNotes/page #1.json')), 'new');
    expect(await d.getVersionFast('/AbelNotes/page #1.json'), 'new');
    final reads = seen.where((u) => u.path.startsWith('/AbelNotes/')).toList();
    expect(reads.map((u) => Uri.decodeComponent(u.path)).toSet(),
        {'/AbelNotes/page #1.json'});
    expect(reads.map((u) => u.queryParameters['_abelnotes_read']).toSet(),
        hasLength(3));
    expect(reads.every((u) => u.queryParameters.containsKey('_abelnotes_read')),
        isTrue);
  });

  test('native policy keeps original URL behavior', () async {
    final d = dav(false);
    expect(utf8.decode(await d.downloadFile('/AbelNotes/page.json')), 'old');
    expect(await d.getVersionFast('/AbelNotes/page.json'), 'old');
    expect(seen.every((u) => u.query.isEmpty), isTrue);
  });
}
