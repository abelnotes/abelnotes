import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/ui/primitives/file_drop_zone.dart';

void main() {
  test('dropped file URIs become local paths, hosts and all', () {
    expect(dropUriPath(Uri.parse('file:///tmp/Lecture%20notes.sdocx')),
        '/tmp/Lecture notes.sdocx');
    expect(dropUriPath(Uri.parse('file://laptop/srv/notes/notes.pdf')),
        '/srv/notes/notes.pdf');
    expect(dropUriPath(Uri.parse('file://localhost/srv/notes/x.png')),
        '/srv/notes/x.png');
    expect(dropUriPath(Uri.parse('https://example.com/x.pdf')), isNull);
  }, testOn: '!windows');
}
