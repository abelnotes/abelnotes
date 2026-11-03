import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Writes one ZIP entry per notebook into [out], reading them one at a time
/// so memory stays near the size of the largest notebook. Entries are stored,
/// not deflated: notebook files are ZIPs already.
///
/// Returns how many notebooks were written, or null if [isCancelled] stopped
/// it (the output is then incomplete).
Future<int?> writeLibraryZip(
  OutputStreamBase out,
  List<({String id, String name})> notebooks,
  Future<Uint8List?> Function(String id) read, {
  void Function(int done)? onProgress,
  bool Function()? isCancelled,
}) async {
  bool stop() => isCancelled?.call() ?? false;
  final zip = ZipEncoder()..startEncode(out, level: Deflate.NO_COMPRESSION);
  var written = 0;
  for (var i = 0; i < notebooks.length; i++) {
    if (stop()) return null;
    final bytes = await read(notebooks[i].id);
    if (stop()) return null;
    if (bytes != null) {
      zip.addFile(ArchiveFile(notebooks[i].name, bytes.length, bytes)..compress = false);
      written++;
    }
    onProgress?.call(i + 1);
    // Let a frame through so the progress dialog moves and Cancel responds.
    await Future<void>.delayed(Duration.zero);
  }
  zip.endEncode();
  return written;
}
