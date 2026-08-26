import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:abelnotes/core/services/google_drive_store.dart';

/// OAuth client identity, injected at build time.
///
/// The secret of an installed app is not really secret — anyone can pull it
/// out of the binary — which is why the flows here all use PKCE. It stays out
/// of the repo anyway: the public repo is scanned for committed credentials,
/// and a hit there is a support incident even when the value is harmless.
///
/// Pass them at build time:
/// `--dart-define=GOOGLE_CLIENT_ID=... --dart-define=GOOGLE_CLIENT_SECRET=...`
class GoogleOAuthConfig {
  final String clientId;

  /// Empty on Android, where the client has no secret at all.
  final String clientSecret;

  const GoogleOAuthConfig({required this.clientId, this.clientSecret = ''});

  static const fromEnvironment = GoogleOAuthConfig(
    clientId: String.fromEnvironment('GOOGLE_CLIENT_ID'),
    clientSecret: String.fromEnvironment('GOOGLE_CLIENT_SECRET'),
  );

  bool get isConfigured => clientId.isNotEmpty;
}

/// Thrown when the user has to go through the consent screen again.
///
/// This is a routine event, not a bug: the refresh token expires after seven
/// days while the Cloud project is in Testing, and in production it still
/// dies whenever the user revokes access, changes their password or hits the
/// per-account token limit. Everything above must treat it as "ask the user
/// to sign in again", never as a sync failure to retry.
class GoogleReauthRequired implements Exception {
  final String reason;
  GoogleReauthRequired(this.reason);

  @override
  String toString() => 'GoogleReauthRequired: $reason';
}

/// Long-lived credentials for one signed-in Google account.
class GoogleTokens {
  final String refreshToken;
  final String? accessToken;
  final DateTime? expiresAt;

  const GoogleTokens({
    required this.refreshToken,
    this.accessToken,
    this.expiresAt,
  });

  /// Treated as expired a minute early: a token that dies mid-flight costs a
  /// failed sync round, and a minute of unused life costs nothing.
  bool get isFresh =>
      accessToken != null &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now().add(const Duration(minutes: 1)));

  Map<String, dynamic> toJson() => {
        'refresh_token': refreshToken,
        if (accessToken != null) 'access_token': accessToken,
        if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      };

  static GoogleTokens fromJson(Map<String, dynamic> json) => GoogleTokens(
        refreshToken: json['refresh_token'] as String,
        accessToken: json['access_token'] as String?,
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
      );
}

/// Where the refresh token lives between launches.
///
/// An interface so tests don't need a keyring, and so a platform with no
/// working secure storage can be given something else deliberately rather
/// than silently falling back to plaintext.
abstract class GoogleTokenStorage {
  Future<GoogleTokens?> read();
  Future<void> write(GoogleTokens tokens);
  Future<void> clear();
}

/// Talks to Google's token endpoint. No storage, no UI, no platform code.
class GoogleOAuthClient {
  static const tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const revokeEndpoint = 'https://oauth2.googleapis.com/revoke';
  static const scope = 'https://www.googleapis.com/auth/drive.file';

  final GoogleOAuthConfig config;
  final http.Client _client;

  GoogleOAuthClient(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  /// Exchanges an authorization code for tokens. [codeVerifier] is the PKCE
  /// secret whose challenge was sent with the authorization request.
  Future<GoogleTokens> exchangeCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final json = await _post({
      'client_id': config.clientId,
      if (config.clientSecret.isNotEmpty) 'client_secret': config.clientSecret,
      'code': code,
      'code_verifier': codeVerifier,
      'grant_type': 'authorization_code',
      'redirect_uri': redirectUri,
    });
    final refresh = json['refresh_token'] as String?;
    if (refresh == null) {
      // Google only returns one when the consent screen was actually shown.
      // Without it the account would work until the access token died and
      // then strand the user with no way back, so fail loudly here instead.
      throw GoogleReauthRequired('no refresh token returned; '
          'the authorization request must ask for offline access and consent');
    }
    return GoogleTokens(
      refreshToken: refresh,
      accessToken: json['access_token'] as String?,
      expiresAt: _expiryFrom(json),
    );
  }

  /// Trades a refresh token for a fresh access token.
  Future<GoogleTokens> refresh(GoogleTokens current) async {
    final json = await _post({
      'client_id': config.clientId,
      if (config.clientSecret.isNotEmpty) 'client_secret': config.clientSecret,
      'refresh_token': current.refreshToken,
      'grant_type': 'refresh_token',
    });
    return GoogleTokens(
      // A refresh response usually omits it: the old one stays valid.
      refreshToken: json['refresh_token'] as String? ?? current.refreshToken,
      accessToken: json['access_token'] as String?,
      expiresAt: _expiryFrom(json),
    );
  }

  /// Best-effort: tells Google to forget the grant on sign-out. A failure
  /// here doesn't matter to the app, which drops its own copy regardless.
  Future<void> revoke(String token) async {
    try {
      await _client.post(Uri.parse(revokeEndpoint), body: {'token': token});
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _post(Map<String, String> body) async {
    final res = await _client.post(Uri.parse(tokenEndpoint), body: body);
    final json = _decode(res.body);
    if (res.statusCode == 200) return json;

    final error = json['error'] as String? ?? 'http ${res.statusCode}';
    // invalid_grant is Google's answer for expired, revoked and reused
    // tokens alike: all of them mean the user has to consent again.
    if (error == 'invalid_grant' || res.statusCode == 400) {
      throw GoogleReauthRequired(
          '$error: ${json['error_description'] ?? res.body}');
    }
    throw GoogleOAuthException(error, res.statusCode);
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  static DateTime? _expiryFrom(Map<String, dynamic> json) {
    final seconds = json['expires_in'];
    if (seconds is! num) return null;
    return DateTime.now().add(Duration(seconds: seconds.toInt()));
  }
}

class GoogleOAuthException implements Exception {
  final String error;
  final int statusCode;
  GoogleOAuthException(this.error, this.statusCode);

  @override
  String toString() => 'GoogleOAuthException($statusCode): $error';
}

/// [DriveAuth] for the Drive store: hands out access tokens and renews them.
///
/// One refresh at a time, shared by every caller. A delta sync asks up to
/// four requests' worth of tokens at once, and letting each start its own
/// refresh would burn refresh tokens and can trip Google's per-account
/// limits — the first caller does the work and the rest await it.
class GoogleDriveAuth implements DriveAuth {
  final GoogleOAuthClient _oauth;
  final GoogleTokenStorage _storage;

  GoogleTokens? _tokens;
  Future<GoogleTokens>? _refreshing;

  GoogleDriveAuth(this._oauth, this._storage);

  /// True once an account is signed in — checked before offering Drive sync.
  Future<bool> get isSignedIn async => (await _current()) != null;

  /// Stores the tokens a completed sign-in produced.
  Future<void> adopt(GoogleTokens tokens) async {
    _tokens = tokens;
    await _storage.write(tokens);
  }

  Future<void> signOut() async {
    final token = _tokens?.refreshToken ?? (await _storage.read())?.refreshToken;
    _tokens = null;
    await _storage.clear();
    if (token != null) await _oauth.revoke(token);
  }

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    final current = await _current();
    if (current == null) {
      throw GoogleReauthRequired('no Google account is signed in');
    }
    if (!forceRefresh && current.isFresh) return current.accessToken!;

    // Coalesce: whoever gets here first refreshes, everyone else waits on it.
    var inFlight = _refreshing;
    if (inFlight == null) {
      inFlight = _refreshAndStore(current);
      _refreshing = inFlight;
      // ignore() because this derived future exists only to free the slot;
      // the real error is delivered to whoever awaits `inFlight`, and left
      // unignored it would surface again as an unhandled async error.
      inFlight.whenComplete(() => _refreshing = null).ignore();
    }
    final renewed = await inFlight;
    final token = renewed.accessToken;
    if (token == null) {
      throw GoogleReauthRequired('refresh returned no access token');
    }
    return token;
  }

  Future<GoogleTokens> _refreshAndStore(GoogleTokens current) async {
    try {
      final renewed = await _oauth.refresh(current);
      _tokens = renewed;
      await _storage.write(renewed);
      return renewed;
    } on GoogleReauthRequired {
      // The refresh token is dead: drop it so the app stops retrying with
      // something that can never work and asks for a fresh sign-in instead.
      _tokens = null;
      await _storage.clear();
      rethrow;
    }
  }

  Future<GoogleTokens?> _current() async => _tokens ??= await _storage.read();
}
