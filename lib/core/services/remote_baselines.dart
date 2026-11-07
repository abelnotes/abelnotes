import 'package:shared_preferences/shared_preferences.dart';

/// Per-notebook records of what one server held. After a disconnect or a
/// backend switch they describe a server that is gone from this device.
class RemoteBaselines {
  static const prefixes = [
    'delta_meta_etag_',
    'page_etags_',
    'pending_meta_commit_',
  ];

  /// Read as "this notebook was on the server", the next server's lack of
  /// it looked like a deletion elsewhere and stopped it syncing. Paired with
  /// [FileService.markAllNotebooksLocal], which clears the same in the DB.
  static Future<void> forgetAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (prefixes.any(key.startsWith)) await prefs.remove(key);
    }
  }
}
