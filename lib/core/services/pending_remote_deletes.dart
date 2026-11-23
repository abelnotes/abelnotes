import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Notebooks deleted here whose remote copy is not yet confirmed gone.
///
/// Keyed by notebook id, valued by the root remote path: the local row is
/// already in the trash, so the path can't be looked up again at retry time.
/// While an id sits here the library sync must not download its root back.
class PendingRemoteDeletes {
  static const _prefsKey = 'pending_remote_deletes_v1';

  static Future<Map<String, String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Another app window (Android) may have written since this one cached.
    await prefs.reload();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  static Future<void> add(String notebookId, String remotePath) =>
      _update((m) => m[notebookId] = remotePath);

  static Future<void> remove(String notebookId) =>
      _update((m) => m.remove(notebookId));

  static Future<void> _update(void Function(Map<String, String>) change) async {
    final prefs = await SharedPreferences.getInstance();
    // Another app window (Android) may have written since this one cached.
    await prefs.reload();
    final map = await load();
    change(map);
    await prefs.setString(_prefsKey, jsonEncode(map));
  }
}
