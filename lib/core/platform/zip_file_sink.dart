// A ZIP output stream backed by a file, so a big archive is written as it
// grows instead of held in memory. The web has no files to stream into.
export 'zip_file_sink_io.dart' if (dart.library.js_interop) 'zip_file_sink_web.dart';
