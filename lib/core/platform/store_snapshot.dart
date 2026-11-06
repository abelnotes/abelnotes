// Zips a notebook's loose store straight to a file, one entry at a time, so a
// snapshot of a large notebook never sits in memory. Native only.
export 'store_snapshot_io.dart' if (dart.library.js_interop) 'store_snapshot_web.dart';
