import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/auth_provider.dart';
import 'package:abelnotes/core/services/google_drive_store.dart';
import 'package:abelnotes/core/services/google_oauth.dart';
import 'package:abelnotes/core/services/remote_store.dart';
import 'package:abelnotes/core/services/native_google_auth.dart';
import 'package:abelnotes/core/services/secure_google_token_storage.dart';

/// Backend names as persisted in settings. Strings rather than an enum
/// because they are written to disk and read back by older builds.
class SyncBackend {
  static const webdav = 'webdav';
  static const drive = 'drive';
}

final googleOAuthConfigProvider = Provider<GoogleOAuthConfig>(
    (ref) => GoogleOAuthConfig.fromEnvironment);

final googleTokenStorageProvider = Provider<GoogleTokenStorage>(
    (ref) => const SecureGoogleTokenStorage());

final googleOAuthClientProvider = Provider<GoogleOAuthClient>(
    (ref) => GoogleOAuthClient(ref.watch(googleOAuthConfigProvider)));

/// True where the platform's own account picker is the way in.
///
/// Google turned browser redirects off for new Android OAuth clients, so on
/// phones the native sheet isn't merely nicer — it is the flow that still
/// works. Desktop has no such component and keeps the loopback flow.
bool get useNativeGoogleSignIn =>
    !kIsWeb && (io.Platform.isAndroid || io.Platform.isIOS);

/// Mobile: the platform owns the tokens, so there is nothing of ours to keep.
final nativeGoogleAuthProvider = Provider<NativeGoogleAuth>((ref) =>
    NativeGoogleAuth(PluginGoogleSignInGateway(
      // Optional: Android matches its OAuth client by package name and
      // signing certificate, so Drive works without a web client id.
      serverClientId: const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID')
              .isEmpty
          ? null
          : const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
    )));

/// Desktop: this app holds the refresh token itself and renews it.
final desktopGoogleAuthProvider = Provider<GoogleDriveAuth>((ref) =>
    GoogleDriveAuth(ref.watch(googleOAuthClientProvider),
        ref.watch(googleTokenStorageProvider)));

/// Whichever of the two this platform uses, as the Drive store sees it.
final googleDriveAuthProvider = Provider<DriveAuth>((ref) =>
    useNativeGoogleSignIn
        ? ref.watch(nativeGoogleAuthProvider)
        : ref.watch(desktopGoogleAuthProvider));

/// Whether a Google account is connected, asked of whichever flow is in use.
///
/// Always asked, never stored: on mobile the platform owns the session and on
/// desktop the refresh token can die between launches, so a remembered
/// "connected" flag would be a claim the app can't back up. Invalidate it
/// after signing in or out to re-ask.
final googleDriveSignedInProvider = FutureProvider<bool>((ref) async =>
    useNativeGoogleSignIn
        ? ref.watch(nativeGoogleAuthProvider).isSignedIn
        : ref.watch(desktopGoogleAuthProvider).isSignedIn);

/// The remote the sync engine talks to, or null in local-only mode.
///
/// One backend at a time, chosen by the user: their own server or their
/// Google Drive. Everything downstream sees a [RemoteStore] and neither
/// knows nor cares which one it got.
final remoteStoreProvider = Provider<RemoteStore?>((ref) {
  final backend = ref.watch(appSettingsProvider.select((s) => s.syncBackend));
  switch (backend) {
    case SyncBackend.drive:
      // The store is cheap to build and holds only a path->id cache; the
      // credentials live in GoogleDriveAuth, which outlives it.
      return GoogleDriveStore(ref.watch(googleDriveAuthProvider));
    case SyncBackend.webdav:
      return ref.watch(webdavServiceProvider);
    default:
      // No explicit choice: fall back to the WebDAV client, which is null
      // unless credentials were saved. Keeps installs made before this
      // setting existed syncing exactly as they did.
      return ref.watch(webdavServiceProvider);
  }
});
