import 'dart:io';
import 'dart:typed_data';

import 'package:abelnotes/core/platform/zip_file_sink.dart';
import 'package:abelnotes/ui/services/library_export.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final books = [
    (id: 'a', name: 'First_a.abelnote'),
    (id: 'b', name: 'Missing_b.abelnote'),
    (id: 'c', name: 'Third_c.abelnote'),
  ];
  final data = {
    'a': Uint8List.fromList(List.generate(5000, (i) => i % 251)),
    'c': Uint8List.fromList(List.generate(70000, (i) => (i * 7) % 256)),
  };
  Future<Uint8List?> read(String id) async => data[id];

  test('every readable notebook lands in the ZIP, stored and intact', () async {
    final out = OutputStream();
    final progress = <int>[];
    final written = await writeLibraryZip(out, books, read, onProgress: progress.add);
    expect(written, 2);
    expect(progress, [1, 2, 3]);
    final zip = ZipDecoder().decodeBytes(out.getBytes());
    expect(zip.files.map((f) => f.name), ['First_a.abelnote', 'Third_c.abelnote']);
    expect(zip.files[0].content, data['a']);
    expect(zip.files[1].content, data['c']);
    expect(zip.files.every((f) => f.compressionType == ArchiveFile.STORE), isTrue);
  });

  test('cancel stops before the next notebook is read', () async {
    final reads = <String>[];
    var cancel = false;
    final written = await writeLibraryZip(OutputStream(), books, (id) async {
      reads.add(id);
      cancel = true;
      return data[id];
    }, isCancelled: () => cancel);
    expect(written, isNull);
    expect(reads, ['a']);
  });

  test('the file sink writes a valid ZIP to disk', () async {
    final dir = await Directory.systemTemp.createTemp('lib_export_test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/library.zip';
    final sink = openZipFileSink(path);
    expect(await writeLibraryZip(sink, books, read), 2);
    await closeZipFileSink(sink);
    final zip = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    expect(zip.files.length, 2);
    expect(zip.files[1].content, data['c']);
  });
}
