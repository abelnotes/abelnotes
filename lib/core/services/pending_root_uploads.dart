import 'package:shared_preferences/shared_preferences.dart';

/// Notebooks whose root `.ncnote` has never reached the server.
///
/// Other devices discover notebooks only by listing root `.ncnote` files, and
/// the delta sync never writes one, so this set is what keeps a failed
/// create/import upload from leaving the notebook invisible elsewhere.
/// Per-device and separate from `sync_status`, which a delta save clears.
class PendingRootUploads {
  static const _prefsKey = 'pending_root_uploads_v1';

  static Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_prefsKey) ?? const <String>[]).toSet();
  }

  static Future<void> add(String notebookId) => _update((s) => s.add(notebookId));

  static Future<void> remove(String notebookId) =>
      _update((s) => s.remove(notebookId));

  static Future<void> _update(void Function(Set<String>) change) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_prefsKey) ?? const <String>[]).toSet();
    change(set);
    await prefs.setStringList(_prefsKey, set.toList());
  }
}
