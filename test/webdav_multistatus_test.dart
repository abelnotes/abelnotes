import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/core/services/webdav_service.dart';

/// Il parsing PROPFIND deve essere namespace-aware: sabre (Nextcloud,
/// ownCloud, Synology) usa il prefisso `d:`, Apache mod_dav usa `D:`,
/// wsgidav/Seafile può usare il namespace di default senza prefisso.
/// Il local name e il namespace URI (DAV:) sono gli unici invarianti.
void main() {
  const davUrl = 'https://server/dav';
  const requestPath = '/AbelNotes/';

  String multistatus({
    required String prefix,
    bool defaultNamespace = false,
  }) {
    final p = defaultNamespace ? '' : '$prefix:';
    final xmlns = defaultNamespace
        ? 'xmlns="DAV:"'
        : 'xmlns:$prefix="DAV:"';
    return '''<?xml version="1.0" encoding="utf-8"?>
<${p}multistatus $xmlns>
  <${p}response>
    <${p}href>/dav/AbelNotes/</${p}href>
    <${p}propstat>
      <${p}prop>
        <${p}resourcetype><${p}collection/></${p}resourcetype>
      </${p}prop>
      <${p}status>HTTP/1.1 200 OK</${p}status>
    </${p}propstat>
  </${p}response>
  <${p}response>
    <${p}href>/dav/AbelNotes/notebook.json</${p}href>
    <${p}propstat>
      <${p}prop>
        <${p}resourcetype/>
        <${p}getetag>"abc123"</${p}getetag>
        <${p}getcontentlength>42</${p}getcontentlength>
        <${p}getlastmodified>Wed, 15 Jul 2026 10:00:00 GMT</${p}getlastmodified>
        <${p}getcontenttype>application/json</${p}getcontenttype>
      </${p}prop>
      <${p}status>HTTP/1.1 200 OK</${p}status>
    </${p}propstat>
  </${p}response>
  <${p}response>
    <${p}href>/dav/AbelNotes/pages/</${p}href>
    <${p}propstat>
      <${p}prop>
        <${p}resourcetype><${p}collection/></${p}resourcetype>
      </${p}prop>
      <${p}status>HTTP/1.1 200 OK</${p}status>
    </${p}propstat>
  </${p}response>
</${p}multistatus>''';
  }

  void expectParsed(List<WebDavItem> items) {
    // L'entry della directory richiesta stessa viene saltata.
    expect(items, hasLength(2));

    final file = items.firstWhere((i) => !i.isDirectory);
    expect(file.name, 'notebook.json');
    expect(file.etag, 'abc123');
    expect(file.contentLength, 42);
    expect(file.contentType, 'application/json');
    expect(file.lastModified, isNotNull);

    final dir = items.firstWhere((i) => i.isDirectory);
    expect(dir.name, 'pages');
  }

  test('sabre-style d: prefix (Nextcloud/ownCloud/Synology)', () {
    expectParsed(WebDavService.parseMultiStatus(
        multistatus(prefix: 'd'), requestPath, davUrl));
  });

  test('Apache mod_dav D: prefix', () {
    expectParsed(WebDavService.parseMultiStatus(
        multistatus(prefix: 'D'), requestPath, davUrl));
  });

  test('default namespace, no prefix (wsgidav/Seafile)', () {
    expectParsed(WebDavService.parseMultiStatus(
        multistatus(prefix: '', defaultNamespace: true), requestPath, davUrl));
  });

  test('entry malformata non invalida il resto della listing', () {
    const broken = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response></d:response>
  <d:response>
    <d:href>/dav/AbelNotes/ok.json</d:href>
    <d:propstat>
      <d:prop><d:resourcetype/><d:getetag>"e1"</d:getetag></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';
    final items =
        WebDavService.parseMultiStatus(broken, requestPath, davUrl);
    expect(items, hasLength(1));
    expect(items.single.name, 'ok.json');
    expect(items.single.etag, 'e1');
  });
}
