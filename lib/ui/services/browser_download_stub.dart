import 'dart:typed_data';

/// Native builds use the save dialog/share sheet in file_export.dart instead.
void downloadFile(String fileName, Uint8List data, String mimeType) {
  throw UnsupportedError('Browser downloads are only available on the web');
}
