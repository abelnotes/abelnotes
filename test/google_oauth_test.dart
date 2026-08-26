// Token handling is where a sync backend quietly rots: a refresh token that
// dies is normal (seven days while the project is in Testing, any revocation
// afterwards), and the app has to tell "ask the user to sign in again" apart
// from "the network hiccuped". These tests pin that boundary.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:abelnotes/core/services/google_oauth.dart';
import 'package:abelnotes/core/services/google_sign_in_desktop.dart';

class _MemoryStorage implements GoogleTokenStorage {
  GoogleTokens? tokens;
  var writes = 0;
  var clears = 0;

  _MemoryStorage([this.tokens]);

  @override
  Future<GoogleTokens?> read() async => tokens;

  @override
  Future<void> write(GoogleTokens t) async {
    tokens = t;
    writes++;
  }

  @override
  Future<void> clear() async {
    tokens = null;
    clears++;
  }
}

const _config = GoogleOAuthConfig(clientId: 'cid', clientSecret: 'secret');

void main() {
  group('token exchange', () {
    test('keeps the refresh token and computes an expiry', () async {
      late Map<String, String> sent;
      final oauth = GoogleOAuthClient(_config,
          client: MockClient((req) async {
            sent = Uri.splitQueryString(req.body);
            return http.Response(
                jsonEncode({
                  'access_token': 'at-1',
                  'refresh_token': 'rt-1',
                  'expires_in': 3600,
                }),
                200);
          }));

      final tokens = await oauth.exchangeCode(
          code: 'the-code', codeVerifier: 'verifier', redirectUri: 'http://x');

      expect(tokens.refreshToken, 'rt-1');
      expect(tokens.isFresh, isTrue);
      expect(sent['code_verifier'], 'verifier',
          reason: 'PKCE verifier must reach the token endpoint');
      expect(sent['grant_type'], 'authorization_code');
    });

    test('a response with no refresh token fails loudly', () async {
      // Silently accepting it would work until the access token expired and
      // then leave the user signed in with no way to renew.
      final oauth = GoogleOAuthClient(_config,
          client: MockClient((_) async => http.Response(
              jsonEncode({'access_token': 'at-1', 'expires_in': 3600}), 200)));

      expect(
        () => oauth.exchangeCode(
            code: 'c', codeVerifier: 'v', redirectUri: 'http://x'),
        throwsA(isA<GoogleReauthRequired>()),
      );
    });

    test('invalid_grant asks for a new sign-in', () async {
      final oauth = GoogleOAuthClient(_config,
          client: MockClient((_) async => http.Response(
              jsonEncode({
                'error': 'invalid_grant',
                'error_description': 'Token has been expired or revoked.',
              }),
              400)));

      expect(
        () => oauth.refresh(const GoogleTokens(refreshToken: 'dead')),
        throwsA(isA<GoogleReauthRequired>()),
      );
    });

    test('a refresh response may omit the refresh token', () async {
      final oauth = GoogleOAuthClient(_config,
          client: MockClient((_) async => http.Response(
              jsonEncode({'access_token': 'at-2', 'expires_in': 3600}), 200)));

      final renewed =
          await oauth.refresh(const GoogleTokens(refreshToken: 'rt-1'));

      expect(renewed.refreshToken, 'rt-1', reason: 'the old one stays valid');
      expect(renewed.accessToken, 'at-2');
    });
  });

  group('GoogleDriveAuth', () {
    test('serves the cached token until it is near expiry', () async {
      var calls = 0;
      final oauth = GoogleOAuthClient(_config,
          client: MockClient((_) async {
            calls++;
            return http.Response(
                jsonEncode({'access_token': 'fresh', 'expires_in': 3600}), 200);
          }));
      final storage = _MemoryStorage(GoogleTokens(
        refreshToken: 'rt-1',
        accessToken: 'cached',
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      ));

      final auth = GoogleDriveAuth(oauth, storage);

      expect(await auth.accessToken(), 'cached');
      expect(calls, 0, reason: 'no reason to talk to Google yet');
    });

    test('renews an expired token and persists it', () async {
      final oauth = GoogleOAuthClient(_config,
          client: MockClient((_) async => http.Response(
              jsonEncode({'access_token': 'renewed', 'expires_in': 3600}),
              200)));
      final storage = _MemoryStorage(GoogleTokens(
        refreshToken: 'rt-1',
        accessToken: 'stale',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ));

      final auth = GoogleDriveAuth(oauth, storage);

      expect(await auth.accessToken(), 'renewed');
      expect(storage.writes, 1, reason: 'a renewed token must survive a restart');
    });

    test('a burst of callers triggers exactly one refresh', () async {
      var refreshes = 0;
      final oauth = GoogleOAuthClient(_config,
          client: MockClient((_) async {
            refreshes++;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return http.Response(
                jsonEncode({'access_token': 'renewed', 'expires_in': 3600}),
                200);
          }));
      final auth = GoogleDriveAuth(
        oauth,
        _MemoryStorage(const GoogleTokens(refreshToken: 'rt-1')),
      );

      // The shape of a delta sync: several uploads asking at once.
      final tokens = await Future.wait([
        for (var i = 0; i < 6; i++) auth.accessToken(),
      ]);

      expect(tokens, everyElement('renewed'));
      expect(refreshes, 1,
          reason: 'parallel refreshes burn tokens and trip account limits');
    });

    test('a dead refresh token is dropped, not retried forever', () async {
      final oauth = GoogleOAuthClient(_config,
          client: MockClient((_) async => http.Response(
              jsonEncode({'error': 'invalid_grant'}), 400)));
      final storage =
          _MemoryStorage(const GoogleTokens(refreshToken: 'revoked'));
      final auth = GoogleDriveAuth(oauth, storage);

      await expectLater(
          auth.accessToken(), throwsA(isA<GoogleReauthRequired>()));
      expect(storage.clears, 1);
      expect(await auth.isSignedIn, isFalse,
          reason: 'the app must now offer sign-in, not keep failing syncs');
    });

    test('asking with no account signed in is a re-auth, not a crash',
        () async {
      final auth = GoogleDriveAuth(
        GoogleOAuthClient(_config, client: MockClient((_) async =>
            http.Response('{}', 200))),
        _MemoryStorage(),
      );

      expect(auth.accessToken(), throwsA(isA<GoogleReauthRequired>()));
    });
  });

  group('desktop sign-in', () {
    test('the PKCE challenge is the SHA-256 of the verifier, unpadded', () {
      final pkce = PkcePair.generate();

      expect(pkce.challenge, isNot(contains('=')));
      expect(pkce.challenge, isNot(contains('+')));
      expect(pkce.challenge, isNot(contains('/')));
      // 32 bytes base64url without padding.
      expect(pkce.challenge.length, 43);
      expect(pkce.verifier, isNot(equals(pkce.challenge)));
    });

    test('two runs never share a verifier', () {
      final a = PkcePair.generate();
      final b = PkcePair.generate();
      expect(a.verifier, isNot(b.verifier));
    });

    test('asks for offline access and forces the consent screen', () async {
      late Uri opened;
      final signIn = DesktopGoogleSignIn(
        GoogleOAuthClient(_config,
            client: MockClient((_) async => http.Response('{}', 200))),
        openUrl: (url) async {
          opened = url;
          throw StateError('stop here: the browser half is the user\'s job');
        },
      );

      await expectLater(signIn.signIn(), throwsA(isA<StateError>()));

      final q = opened.queryParameters;
      expect(q['scope'], GoogleOAuthClient.scope,
          reason: 'drive.file only — anything wider needs a paid annual audit');
      expect(q['access_type'], 'offline');
      expect(q['prompt'], 'consent');
      expect(q['code_challenge_method'], 'S256');
      expect(q['state'], isNotEmpty);
      expect(q['redirect_uri'], startsWith('http://127.0.0.1:'));
    });

    test('refuses to start with no client id built in', () async {
      final signIn = DesktopGoogleSignIn(
        GoogleOAuthClient(const GoogleOAuthConfig(clientId: '')),
        openUrl: (_) async {},
      );

      expect(signIn.signIn(), throwsA(isA<GoogleReauthRequired>()));
    });
  });
}
