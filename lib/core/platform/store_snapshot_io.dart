import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Writes every file under [args] `[storeDir, destPath]` into a ZIP at
/// destPath, with paths relative to the store. Assets are stored, the JSON
/// deflated. Top-level so it can run in a background isolate.
Future<void> zipStoreToFile(List<String> args) async {
  final storeDir = args[0];
  final dest = args[1];
  final encoder = ZipFileEncoder()..create(dest);
  try {
    final entries = Directory(storeDir).listSync(recursive: true);
    for (final e in entries) {
      if (e is! File || e.path.endsWith('.tmp')) continue;
      final rel = p.split(p.relative(e.path, from: storeDir)).join('/');
      final binary = !rel.endsWith('.json');
      await encoder.addFile(
          e, rel, binary ? ZipFileEncoder.STORE : ZipFileEncoder.GZIP);
    }
  } finally {
    await encoder.close();
  }
}
