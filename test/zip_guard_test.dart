// Notebook packages that would expand absurdly are refused before decoding.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/zip_guard.dart';

List<int> _zip(Map<String, List<int>> files) {
  final a = Archive();
  files.forEach((name, data) => a.addFile(ArchiveFile(name, data.length, data)));
  return ZipEncoder().encode(a)!;
}

void main() {
  test('a normal package decodes', () {
    final bytes = _zip({
      'metadata.json': utf8.encode('{"id":"x"}'),
      'pages/p1.json': utf8.encode('{"strokes":[]}' * 1000),
    });
    expect(decodeNotebookArchive(bytes).length, 2);
  });

  test('a small file that expands past the ratio is refused', () {
    final bytes = _zip({'pages/p1.json': Uint8List(40 << 20)}); // zeros: ~40 KB zipped
    expect(bytes.length, lessThan(1 << 20));
    expect(() => decodeNotebookArchive(bytes), throwsFormatException);
  });

  test('a big package that compresses well but under the floor still decodes', () {
    final bytes = _zip({'pages/p1.json': Uint8List(4 << 20)});
    expect(decodeNotebookArchive(bytes).length, 1);
  });
}
