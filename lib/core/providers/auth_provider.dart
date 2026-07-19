import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abelnotes/core/services/webdav_service.dart';
import 'package:abelnotes/core/services/nextcloud_share_service.dart';

/// Credenziali del server di sync (Nextcloud/ownCloud o WebDAV generico).
class NextcloudCredentials {
  final String serverUrl;
  final String username;
  final String password;

  /// Che tipo di server è [serverUrl]: per Nextcloud/ownCloud l'endpoint
  /// DAV viene derivato, per un server generico l'URL È l'endpoint DAV.
  /// Decide anche se la condivisione via OCS è disponibile.
  final WebDavServerType serverType;

  /// SHA-256 fingerprint of the TLS certificate pinned for [serverUrl] on
  /// first successful connection (trust-on-first-use). Null until the
  /// first connect completes — see [WebDavService].
  final String? certFingerprint;

  const NextcloudCredentials({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.serverType = WebDavServerType.nextcloud,
    this.certFingerprint,
  });

  Map<String, String> toMap() => {
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'serverType': serverType.name,
      };

  factory NextcloudCredentials.fromMap(Map<String, String> map) =>
      NextcloudCredentials(
        serverUrl: map['serverUrl']!,
        username: map['username']!,
        password: map['password']!,
        serverType: WebDavServerType.fromName(map['serverType']),
      );
}

/// Provider per le credenziali salvate.
final credentialsProvider =
    StateNotifierProvider<CredentialsNotifier, NextcloudCredentials?>((ref) {
  return CredentialsNotifier();
});

class CredentialsNotifier extends StateNotifier<NextcloudCredentials?> {
  static const _kCertFingerprint = 'nc_cert_fingerprint';
  static const _kPassword = 'nc_password';
  static const _kServerType = 'nc_server_type';

  static const _secureStorage = FlutterSecureStorage();

  CredentialsNotifier() : super(null) {
    _loadSaved();
  }

  /// Reads the password from the OS keychain/keystore, migrating over (and
  /// scrubbing) any plaintext copy left in SharedPreferences by installs
  /// from before secure storage was wired in. Some environments have no
  /// backing keyring at all (e.g. headless Linux with no Secret Service
  /// daemon running) — secure storage throws there, so we fall back to the
  /// plaintext copy rather than locking the user out of their own app.
  Future<String?> _readPassword(SharedPreferences prefs) async {
    try {
      final secure = await _secureStorage.read(key: _kPassword);
      if (secure != null) return secure;
    } catch (_) {
      // No OS keyring available — fall through to the legacy/plaintext copy.
    }
    final legacy = prefs.getString(_kPassword);
    if (legacy != null) {
      try {
        await _secureStorage.write(key: _kPassword, value: legacy);
        await prefs.remove(_kPassword);
      } catch (_) {
        // Secure storage unavailable here too — leave the plaintext copy
        // in place so the app keeps working, just not hardened yet.
      }
    }
    return legacy;
  }

  Future<void> _writePassword(String password, SharedPreferences prefs) async {
    try {
      await _secureStorage.write(key: _kPassword, value: password);
      await prefs.remove(_kPassword);
    } catch (_) {
      // Degrade to plaintext prefs rather than fail login outright — same
      // trade-off as _readPassword above.
      await prefs.setString(_kPassword, password);
    }
  }

  Future<void> _clearPassword(SharedPreferences prefs) async {
    try {
      await _secureStorage.delete(key: _kPassword);
    } catch (_) {}
    await prefs.remove(_kPassword);
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('nc_server_url');
    final user = prefs.getString('nc_username');
    final pass = await _readPassword(prefs);
    if (url != null && user != null && pass != null) {
      state = NextcloudCredentials(
        serverUrl: url,
        username: user,
        password: pass,
        // Installazioni pre-esistenti non hanno la chiave: erano tutte
        // Nextcloud, e fromName(null) torna nextcloud.
        serverType:
            WebDavServerType.fromName(prefs.getString(_kServerType)),
        certFingerprint: prefs.getString(_kCertFingerprint),
      );
    }
  }

  Future<void> login(NextcloudCredentials creds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nc_server_url', creds.serverUrl);
    await prefs.setString('nc_username', creds.username);
    await prefs.setString(_kServerType, creds.serverType.name);
    await _writePassword(creds.password, prefs);
    if (creds.certFingerprint != null) {
      await prefs.setString(_kCertFingerprint, creds.certFingerprint!);
    } else {
      // A fresh login to a (possibly different) server must not carry
      // over the previous server's pinned certificate.
      await prefs.remove(_kCertFingerprint);
    }
    state = creds;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('nc_server_url');
    await prefs.remove('nc_username');
    await prefs.remove(_kServerType);
    await _clearPassword(prefs);
    await prefs.remove(_kCertFingerprint);
    state = null;
  }

  /// Called by [WebDavService.onCertificatePinned] the first time a
  /// certificate is trusted for the current server, so the pin survives
  /// app restarts instead of re-trusting on first use every launch.
  Future<void> pinCertificate(String fingerprint) async {
    final current = state;
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCertFingerprint, fingerprint);
    state = NextcloudCredentials(
      serverUrl: current.serverUrl,
      username: current.username,
      password: current.password,
      serverType: current.serverType,
      certFingerprint: fingerprint,
    );
  }
}

/// Provider per il servizio WebDAV, dipende dalle credenziali.
///
/// On logout/credentials change the underlying `http.Client` must be closed
/// explicitly, otherwise the socket + connection pool leak for the lifetime
/// of the app (noticeable after repeated login/logout cycles on iPad).
final webdavServiceProvider = Provider<WebDavService?>((ref) {
  final creds = ref.watch(credentialsProvider);
  if (creds == null) return null;
  final service = WebDavService(
    serverUrl: creds.serverUrl,
    username: creds.username,
    password: creds.password,
    serverType: creds.serverType,
    pinnedCertFingerprint: creds.certFingerprint,
    onCertificatePinned: (fp) =>
        ref.read(credentialsProvider.notifier).pinCertificate(fp),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Public-link sharing via the user's Nextcloud. Null when not connected —
/// the share UI is gated on this, so local-only users just don't see it.
/// Null anche su server WebDAV generici: la OCS Share API esiste solo su
/// Nextcloud/ownCloud, quindi lì il bottone share semplicemente non appare.
final nextcloudShareServiceProvider = Provider<NextcloudShareService?>((ref) {
  final creds = ref.watch(credentialsProvider);
  final webdav = ref.watch(webdavServiceProvider);
  if (creds == null || webdav == null) return null;
  if (creds.serverType != WebDavServerType.nextcloud) return null;
  return NextcloudShareService(
    serverUrl: creds.serverUrl,
    username: creds.username,
    password: creds.password,
    webdav: webdav,
  );
});
