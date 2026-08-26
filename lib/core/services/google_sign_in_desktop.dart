import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:abelnotes/core/services/google_oauth.dart';

/// PKCE pair for one authorization request.
///
/// PKCE is what makes an installed app's client secret harmless: the code
/// Google hands back is useless to anyone who didn't generate [verifier],
/// so extracting the secret from the binary buys an attacker nothing.
class PkcePair {
  final String verifier;
  final String challenge;

  const PkcePair(this.verifier, this.challenge);

  factory PkcePair.generate() {
    final random = Random.secure();
    final verifier = _base64Url(
        List<int>.generate(64, (_) => random.nextInt(256)));
    return PkcePair(verifier, _base64Url(sha256.convert(ascii.encode(verifier)).bytes));
  }

  /// Google rejects padded base64url, so `=` is stripped.
  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}

/// Sign-in for platforms with a real loopback interface: Linux, Windows,
/// macOS.
///
/// Android and iOS cannot use this — their OAuth clients redirect to a custom
/// scheme the OS routes back to the app — so they get their own
/// implementation and this one stays free of platform channels.
///
/// The loopback redirect is the flow Google documents for installed apps: a
/// short-lived local server on 127.0.0.1 collects the authorization code, so
/// the code never travels through a third party.
class DesktopGoogleSignIn {
  final GoogleOAuthClient _oauth;

  /// Opens the consent page. Left to the caller so this class needs no
  /// plugin: the UI can launch a browser, and a test can just record it.
  final Future<void> Function(Uri url) openUrl;

  /// What the browser shows once the code is in. The user sees this page,
  /// not the app, so it is the only place to tell them to go back.
  final String doneHtml;

  DesktopGoogleSignIn(
    this._oauth, {
    required this.openUrl,
    this.doneHtml = '<!doctype html><meta charset="utf-8">'
        '<title>AbelNotes</title>'
        '<body style="font-family:system-ui;padding:3rem">'
        '<h2>Signed in.</h2><p>You can close this tab and go back to '
        'AbelNotes.</p></body>',
  });

  /// Runs the whole flow and returns the tokens. Throws
  /// [GoogleReauthRequired] if the user refuses or the window times out.
  Future<GoogleTokens> signIn({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (!_oauth.config.isConfigured) {
      throw GoogleReauthRequired(
          'no OAuth client id was built into this binary');
    }
    final pkce = PkcePair.generate();
    // Port 0: the OS picks a free one. A fixed port would collide with
    // whatever else the user runs, and Google allows any loopback port.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}';
    // Guards against a redirect that didn't come from the request we just
    // made — the browser will happily deliver anything to a local port.
    final state = PkcePair.generate().verifier;

    try {
      await openUrl(_authorizationUrl(pkce, redirectUri, state));
      final code = await _awaitCode(server, state).timeout(timeout,
          onTimeout: () => throw GoogleReauthRequired(
              'no answer from the consent screen within '
              '${timeout.inMinutes} minutes'));
      return await _oauth.exchangeCode(
        code: code,
        codeVerifier: pkce.verifier,
        redirectUri: redirectUri,
      );
    } finally {
      await server.close(force: true);
    }
  }

  Uri _authorizationUrl(PkcePair pkce, String redirectUri, String state) =>
      Uri.parse('https://accounts.google.com/o/oauth2/v2/auth').replace(
        queryParameters: {
          'client_id': _oauth.config.clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': GoogleOAuthClient.scope,
          'code_challenge': pkce.challenge,
          'code_challenge_method': 'S256',
          'state': state,
          // Both are required to get a refresh token: without offline
          // access there is none, and without an explicit consent Google
          // omits it on every sign-in after the first — which strands the
          // user as soon as the access token dies.
          'access_type': 'offline',
          'prompt': 'consent',
        },
      );

  Future<String> _awaitCode(HttpServer server, String state) async {
    await for (final request in server) {
      final params = request.uri.queryParameters;
      final code = params['code'];
      final error = params['error'];
      final ok = code != null && params['state'] == state;

      request.response
        ..statusCode = ok ? 200 : 400
        ..headers.contentType = ContentType.html
        ..write(ok
            ? doneHtml
            : '<!doctype html><meta charset="utf-8">'
                '<body style="font-family:system-ui;padding:3rem">'
                '<h2>Sign-in failed.</h2><p>${error ?? 'unexpected redirect'}'
                '</p></body>');
      await request.response.close();

      if (ok) return code;
      if (error != null) throw GoogleReauthRequired(error);
      // A redirect with no code and no error, or a state that doesn't
      // match: ignore it and keep listening rather than failing the flow.
    }
    throw GoogleReauthRequired('the sign-in window closed before answering');
  }
}
