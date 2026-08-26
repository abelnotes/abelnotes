import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:abelnotes/core/services/google_oauth.dart';

/// Keeps the Google refresh token in the OS keychain.
///
/// Deliberately has no plaintext fallback, unlike the WebDAV password. A
/// refresh token is a standing key to the user's Drive files: on a machine
/// with no working keyring it is better for Drive sync to be unavailable —
/// and to say so — than to leave that key in a readable file.
class SecureGoogleTokenStorage implements GoogleTokenStorage {
  static const _key = 'google_drive_tokens';
  final FlutterSecureStorage _storage;

  const SecureGoogleTokenStorage([
    this._storage = const FlutterSecureStorage(),
  ]);

  @override
  Future<GoogleTokens?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return GoogleTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Unreadable or corrupt: treat as signed out. The user signs in again
      // and the write below replaces whatever is there.
      return null;
    }
  }

  @override
  Future<void> write(GoogleTokens tokens) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(tokens.toJson()));
    } catch (e) {
      throw GoogleTokenStorageUnavailable(e.toString());
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

/// No OS keyring to store the refresh token in — Drive sync can't be offered
/// on this machine. The UI maps this to its own message; the text here is
/// technical detail for logs, not something a user reads.
class GoogleTokenStorageUnavailable implements Exception {
  final String detail;
  GoogleTokenStorageUnavailable(this.detail);

  @override
  String toString() => 'GoogleTokenStorageUnavailable: $detail';
}
