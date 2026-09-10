import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the user chose "local-only" mode at onboarding — use the app
/// without connecting any server. Notebooks live purely on-device.
///
/// The auth gate shows the library when EITHER real credentials exist OR
/// this flag is set; otherwise it shows onboarding. Cleared on full logout
/// so the user lands back on onboarding.
final localModeProvider =
    StateNotifierProvider<LocalModeNotifier, bool>((ref) {
  return LocalModeNotifier();
});

class LocalModeNotifier extends StateNotifier<bool> {
  LocalModeNotifier() : super(false) {
    _load();
  }

  static const _key = 'local_mode';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  /// Enter local-only mode (from onboarding's "try now" choice).
  Future<void> enable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    state = true;
  }

  /// Leave local-only mode (connecting a server, or logging out to
  /// return to onboarding).
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, false);
    state = false;
  }
}

/// Whether the user dismissed the library's local-only reminder. Onboarding
/// already asks once; this keeps the follow-up hint from nagging forever.
final localOnlyNoticeDismissedProvider =
    StateNotifierProvider<LocalOnlyNoticeNotifier, bool>((ref) {
  return LocalOnlyNoticeNotifier();
});

class LocalOnlyNoticeNotifier extends StateNotifier<bool> {
  LocalOnlyNoticeNotifier() : super(false) {
    _load();
  }

  static const _key = 'local_only_notice_dismissed';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    state = true;
  }

  /// Connecting a server and then disconnecting again should bring the hint
  /// back — the second local-only stretch is a different decision.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    state = false;
  }
}
