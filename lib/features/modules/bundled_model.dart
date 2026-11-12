// Materialises a model bundled as an asset on disk, where an isolate loads it.

import 'package:abelnotes/core/platform/io.dart';
import 'package:flutter/foundation.dart';

/// Copies the bundled model to [path] unless the copy there is that very file:
/// a stamp beside it records the installed hash, since two models can have the
/// same length. [load] runs only when a copy is needed.
Future<void> installBundledModel(String path, String sha256, Future<ByteData> Function() load) async {
  final file = File(path);
  final stamp = File('$path.sha256');
  if (file.existsSync() && stamp.existsSync() && stamp.readAsStringSync().trim() == sha256) return;
  final ByteData data;
  try {
    data = await load();
  } catch (e) {
    debugPrint('[module] bundled model missing: $e');
    return;
  }
  await file.parent.create(recursive: true);
  // Stamp last, so a copy cut short is redone at the next start.
  if (stamp.existsSync()) await stamp.delete();
  final tmp = File('$path.tmp');
  await tmp.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
  await tmp.rename(path);
  await stamp.writeAsString(sha256, flush: true);
}
