// The native sign-in is what still works on Android: Google switched off
// browser redirects for new OAuth clients there. These tests drive it with a
// stand-in for the platform, since the real one only exists on a device.

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:abelnotes/core/services/google_oauth.dart';
import 'package:abelnotes/core/services/native_google_auth.dart';

class _FakeGateway implements GoogleSignInGateway {
  _FakeGateway({this.silentToken});

  String? silentToken;
  // Starts true: the interesting cases flip it from inside the fake (a
  // sign-out, a successful sign-in), never from the constructor.
  bool hasSession = true;
  final List<String> calls = [];
  final List<String> discarded = [];
  Object? signInError;

  @override
  Future<void> initialize() async => calls.add('initialize');

  @override
  Future<bool> restoreSession() async {
    calls.add('restore');
    return hasSession;
  }

  int get restoreCount => calls.where((c) => c == 'restore').length;

  @override
  Future<void> signInAndAuthorize(List<String> scopes) async {
    calls.add('signIn ${scopes.join(",")}');
    if (signInError != null) throw signInError!;
    hasSession = true;
    silentToken = 'granted';
  }

  @override
  Future<String?> tokenIfAuthorized(List<String> scopes) async {
    calls.add('token');
    return silentToken;
  }

  @override
  Future<void> discardToken(String accessToken) async {
    discarded.add(accessToken);
    silentToken = 'renewed';
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    hasSession = false;
    silentToken = null;
  }
}

void main() {
  test('hands out the token the platform already holds', () async {
    final gateway = _FakeGateway(silentToken: 'at-1');

    expect(await NativeGoogleAuth(gateway).accessToken(), 'at-1');
    expect(gateway.calls, isNot(contains(startsWith('signIn'))),
        reason: 'a background sync must never open an account sheet');
  });

  test('never restores the session while handing out tokens', () async {
    // Restoring shows Android's One Tap sheet, and this runs once per HTTP
    // request during a sync: doing it here made the sheet slide up every
    // couple of seconds and the app unusable.
    final gateway = _FakeGateway(silentToken: 'at-1');
    final auth = NativeGoogleAuth(gateway);

    for (var i = 0; i < 5; i++) {
      await auth.accessToken();
    }

    expect(gateway.restoreCount, 0);
  });

  test('no token and no session still does not restore on the token path',
      () async {
    final gateway = _FakeGateway(silentToken: null);

    await expectLater(NativeGoogleAuth(gateway).accessToken(),
        throwsA(isA<GoogleReauthRequired>()));
    expect(gateway.restoreCount, 0,
        reason: 'a background sync must never put UI on screen');
  });

  test('asking whether we are signed in skips the restore when a token exists',
      () async {
    final gateway = _FakeGateway(silentToken: 'at-1');

    expect(await NativeGoogleAuth(gateway).isSignedIn, isTrue);
    expect(gateway.restoreCount, 0);
  });

  test('no authorization is a re-auth, not a prompt', () async {
    // Called from background syncs: an account sheet appearing over whatever
    // the user is doing is worse than a sync that waits.
    final gateway = _FakeGateway(silentToken: null);

    await expectLater(NativeGoogleAuth(gateway).accessToken(),
        throwsA(isA<GoogleReauthRequired>()));
    expect(gateway.calls, isNot(contains(startsWith('signIn'))));
  });

  test('a rejected token is discarded before asking for another', () async {
    final gateway = _FakeGateway(silentToken: 'stale');
    final auth = NativeGoogleAuth(gateway);

    expect(await auth.accessToken(), 'stale');
    // What the Drive store does after a 401.
    expect(await auth.accessToken(forceRefresh: true), 'renewed');
    expect(gateway.discarded, ['stale'],
        reason: 'the platform caches tokens and would hand back the dead one');
  });

  test('nothing to discard on the first call', () async {
    final gateway = _FakeGateway(silentToken: 'at-1');

    expect(await NativeGoogleAuth(gateway).accessToken(forceRefresh: true),
        'at-1');
    expect(gateway.discarded, isEmpty);
  });

  test('signing in grants the Drive scope and only that', () async {
    final gateway = _FakeGateway(silentToken: null);

    await NativeGoogleAuth(gateway).signIn();

    expect(gateway.calls, contains('signIn ${GoogleOAuthClient.scope}'),
        reason: 'a wider scope would drag in a paid annual audit');
  });

  test('a closed sheet is reported as cancelled', () async {
    final gateway = _FakeGateway()
      ..signInError = const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled);

    await expectLater(NativeGoogleAuth(gateway).signIn(),
        throwsA(isA<GoogleSignInCancelled>()));
  });

  test('a misconfigured build is NOT reported as cancelled', () async {
    // This is where a build missing its web client id lands, and it fails
    // before the user sees anything — calling that "cancelled" sends everyone
    // hunting in the wrong place.
    final gateway = _FakeGateway()
      ..signInError = const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
          description: 'serverClientId must be provided on Android');

    await expectLater(NativeGoogleAuth(gateway).signIn(),
        throwsA(isA<GoogleReauthRequired>()));
  });

  test('signed-in means the platform can produce a token', () async {
    // The only proof that survives a restart: this app stores no credentials
    // of its own on mobile.
    expect(await NativeGoogleAuth(_FakeGateway(silentToken: 'at')).isSignedIn,
        isTrue);
    expect(await NativeGoogleAuth(_FakeGateway(silentToken: null)).isSignedIn,
        isFalse);
  });

  test('signing out clears the session', () async {
    final gateway = _FakeGateway(silentToken: 'at');
    final auth = NativeGoogleAuth(gateway);

    await auth.signOut();

    expect(await auth.isSignedIn, isFalse);
  });
}
