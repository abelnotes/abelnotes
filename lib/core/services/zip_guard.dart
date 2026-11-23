import 'package:archive/archive.dart';

import 'package:abelnotes/features/import/data/import_limits.dart';

/// Decodes a notebook package, refusing one that declares far more content
/// than its own size (a zip bomb): past [ImportLimits.ratioCheckFloorBytes],
/// at most [ImportLimits.maxZipRatio] times the file.
Archive decodeNotebookArchive(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  var total = 0;
  for (final f in archive) {
    total += f.size;
  }
  if (total > ImportLimits.ratioCheckFloorBytes &&
      total > bytes.length * ImportLimits.maxZipRatio) {
    throw const FormatException('notebook archive expands too much');
  }
  return archive;
}
