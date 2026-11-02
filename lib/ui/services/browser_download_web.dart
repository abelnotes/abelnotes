import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Hand bytes directly to the browser, without a native file picker or path.
void downloadFile(String fileName, Uint8List data, String mimeType) {
  final body = web.document.body;
  if (body == null) {
    throw StateError('The document is not ready for a download');
  }

  final blob = web.Blob([data.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  var clicked = false;
  try {
    body.appendChild(anchor);
    anchor.click();
    clicked = true;
  } finally {
    anchor.remove();
    if (clicked) {
      // Navigation consumes the blob asynchronously. Revoking it in the same
      // turn as click() can cancel a download, particularly in Firefox.
      Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
    } else {
      web.URL.revokeObjectURL(url);
    }
  }
}
