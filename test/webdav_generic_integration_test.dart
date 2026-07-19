import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/core/services/webdav_service.dart';

/// Integrazione contro un server WebDAV NON-sabre reale (wsgidav usa il
/// prefisso `D:` nel Multi-Status, dove Nextcloud usa `d:`) in modalità
/// [WebDavServerType.generic]. Skippato di default: gira solo quando
/// WEBDAV_TEST_URL punta a un server, es.
///
///   wsgidav -H 127.0.0.1 -p 8899 -r /tmp/davroot --auth anonymous
///   WEBDAV_TEST_URL=http://127.0.0.1:8899 flutter test \
///       test/webdav_generic_integration_test.dart
void main() {
  final url = Platform.environment['WEBDAV_TEST_URL'];

  test('ciclo completo su WebDAV generico: mkcol/put/list/etag/get/delete',
      () async {
    final dav = WebDavService(
      serverUrl: url!,
      username: 'test',
      password: 'test',
      serverType: WebDavServerType.generic,
    );
    addTearDown(dav.dispose);

    expect(await dav.testConnection(), isTrue,
        reason: 'PROPFIND Depth:0 sulla root DAV deve rispondere 207');

    await dav.ensureBaseDirectory();

    final payload = Uint8List.fromList(utf8.encode('{"pages": []}'));
    final putEtag =
        await dav.uploadFile('/AbelNotes/metadata.json', payload);
    expect(putEtag, isNotNull,
        reason: 'ETag da header PUT o dal fallback PROPFIND');

    final items = await dav.listDirectory('/AbelNotes/');
    expect(items.map((i) => i.name), contains('metadata.json'),
        reason: 'listing D:-prefixed deve essere parsato (fix namespace)');
    final meta = items.firstWhere((i) => i.name == 'metadata.json');
    expect(meta.isDirectory, isFalse);
    expect(meta.contentLength, payload.length);

    final propfindEtag = await dav.getEtag('/AbelNotes/metadata.json');
    expect(propfindEtag, putEtag);

    // getEtagFast: o l'ETag via HEAD, o null (server senza ETag su HEAD,
    // il capability-flag scatta) — mai un'eccezione.
    final fastEtag = await dav.getEtagFast('/AbelNotes/metadata.json');
    expect(fastEtag == null || fastEtag == putEtag, isTrue);

    final downloaded = await dav.downloadFile('/AbelNotes/metadata.json');
    expect(utf8.decode(downloaded), '{"pages": []}');

    await dav.delete('/AbelNotes/metadata.json');
    final after = await dav.listDirectory('/AbelNotes/');
    expect(after.map((i) => i.name), isNot(contains('metadata.json')));
  }, skip: url == null ? 'WEBDAV_TEST_URL non impostata' : false);
}
