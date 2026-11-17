// Loads the browser's file store before the queue reads it (web only).
export 'page_storage_stub.dart' if (dart.library.js_interop) 'page_storage_web.dart';
