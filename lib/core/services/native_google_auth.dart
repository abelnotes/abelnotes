import 'package:google_sign_in/google_sign_in.dart';

import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/core/services/google_drive_store.dart';
import 'package:abelnotes/core/services/google_oauth.dart';

/// The bits of the Google Sign-In plugin this app uses.
///
/// A seam, not ceremony: the plugin talks to platform channels, so without it
/// none of the logic below could be exercised outside a device.
abstract class GoogleSignInGateway {
  /// Must run once before anything else. Safe to call again.
  Future<void> initialize();

  /// Restores a previous sign-in. On Android this shows the One Tap sheet,
  /// so it is NOT free: call it when the app has a reason to ask "is anyone
  /// signed in", never on a hot path.
  Future<bool> restoreSession();

  /// Interactive sign-in plus scope grant. Only from a user gesture.
  Future<void> signInAndAuthorize(List<String> scopes);

  /// A token for [scopes] if one can be had without showing UI.
  Future<String?> tokenIfAuthorized(List<String> scopes);

  /// Drops a token the server rejected, so the next request fetches a new one.
  Future<void> discardToken(String accessToken);

  Future<void> signOut();
}

/// [GoogleSignInGateway] backed by the real plugin.
class PluginGoogleSignInGateway implements GoogleSignInGateway {
  /// A WEB OAuth client id, when the project has one. Android doesn't need it
  /// to authorize Drive scopes — the Android client is matched by package name
  /// and signing certificate — so this stays optional rather than becoming a
  /// second thing that must be configured before sign-in works at all.
  final String? serverClientId;

  bool _initialized = false;
  Future<bool>? _restoreOnce;

  PluginGoogleSignInGateway({this.serverClientId});

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: serverClientId);
    _initialized = true;
  }

  /// Memoised for the life of the process. The platform decides how much UI
  /// this shows — on Android it is the One Tap sheet sliding up over the app —
  /// so asking twice means showing it twice.
  @override
  Future<bool> restoreSession() => _restoreOnce ??= _restore();

  Future<bool> _restore() async {
    await initialize();
    final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
    if (attempt == null) return false;
    return await attempt != null;
  }

  @override
  Future<void> signInAndAuthorize(List<String> scopes) async {
    await initialize();
    // Authentication and authorization are separate steps by design: the user
    // says who they are, then says what this app may touch. scopeHint lets a
    // platform that can combine them do so, but the authorize call below is
    // what actually guarantees the grant.
    await GoogleSignIn.instance.authenticate(scopeHint: scopes);
    await GoogleSignIn.instance.authorizationClient.authorizeScopes(scopes);
  }

  @override
  Future<String?> tokenIfAuthorized(List<String> scopes) async {
    await initialize();
    final authorization = await GoogleSignIn.instance.authorizationClient
        .authorizationForScopes(scopes);
    return authorization?.accessToken;
  }

  @override
  Future<void> discardToken(String accessToken) async {
    await GoogleSignIn.instance.authorizationClient
        .clearAuthorizationToken(accessToken: accessToken);
  }

  @override
  Future<void> signOut() async {
    await initialize();
    await GoogleSignIn.instance.signOut();
    // The next "is anyone signed in?" must ask the platform again rather
    // than replay the answer from before the sign-out.
    _restoreOnce = null;
  }
}

/// The user closed the account sheet. Not an error to report as a failure.
class GoogleSignInCancelled implements Exception {
  @override
  String toString() => 'GoogleSignInCancelled';
}

/// [DriveAuth] for phones and tablets, using the platform's own account
/// picker instead of a browser round trip.
///
/// Google switched off browser redirects for new Android OAuth clients — the
/// custom URI scheme flow now has to be enabled by hand per client and is on
/// its way out — so this is the path that keeps working. It is also the better
/// experience: the account sheet appears over the app, with no browser tab and
/// no way to land back on the wrong screen.
///
/// The trade-off is that the platform owns the tokens. There is no refresh
/// token to store, which means nothing to keep in the keychain here, and
/// nothing this app can renew on its own: when the platform can't produce a
/// token silently, the only honest answer is to ask the user again.
class NativeGoogleAuth implements DriveAuth {
  static const _scopes = [GoogleOAuthClient.scope];

  final GoogleSignInGateway _gateway;

  /// The last token handed out, so a 401 can name the one to discard.
  String? _lastToken;

  NativeGoogleAuth(this._gateway);

  /// True when a silent token is available — the only proof that survives a
  /// restart, since this app holds no credentials of its own.
  ///
  /// Restores the session only if there is no token already, and the gateway
  /// only does that once per run: this is the one path allowed to put the
  /// account sheet on screen, and only because it is answering a question the
  /// UI just asked.
  Future<bool> get isSignedIn async {
    if (await _gateway.tokenIfAuthorized(_scopes) != null) return true;
    if (!await _gateway.restoreSession()) return false;
    return await _gateway.tokenIfAuthorized(_scopes) != null;
  }

  /// Interactive sign-in. Call from a user gesture: the account sheet needs a
  /// foregrounded app, and on Android an Activity to attach to.
  ///
  /// Throws [GoogleSignInCancelled] when the user backed out, and
  /// [GoogleReauthRequired] for everything else. The distinction is worth
  /// making because a misconfigured build fails here instantly, and telling
  /// the user "cancelled" for something they never got the chance to cancel
  /// sends everyone hunting in the wrong place.
  Future<void> signIn() async {
    try {
      await _gateway.signInAndAuthorize(_scopes);
    } on GoogleSignInException catch (e) {
      // Android's CredentialManager reports some configuration errors as a
      // cancellation and the plugin cannot tell them apart, so the code alone
      // is not proof of what happened — hence the log line.
      CrashLogger.append(
          'Google sign-in failed: ${e.code.name} ${e.description ?? ''}');
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw GoogleSignInCancelled();
      }
      throw GoogleReauthRequired('${e.code.name}: ${e.description ?? ''}');
    }
  }

  Future<void> signOut() => _gateway.signOut();

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    if (forceRefresh && _lastToken != null) {
      // The server rejected it, so it must not be handed out again — the
      // platform caches tokens and would otherwise return the same dead one.
      await _gateway.discardToken(_lastToken!);
      _lastToken = null;
    }

    final token = await _gateway.tokenIfAuthorized(_scopes);
    if (token == null) {
      // Deliberately does NOT prompt, and deliberately does not restore the
      // session either: restoring shows Android's One Tap sheet, and this
      // runs once per HTTP request during a sync. Doing it here made the
      // sheet reappear every couple of seconds and the app unusable.
      throw GoogleReauthRequired(
          'the platform has no Drive authorization for this account');
    }
    return _lastToken = token;
  }
}
