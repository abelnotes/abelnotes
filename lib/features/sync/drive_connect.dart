import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/providers/remote_store_provider.dart';
import 'package:abelnotes/core/services/google_oauth.dart';
import 'package:abelnotes/core/services/google_sign_in_desktop.dart';
import 'package:abelnotes/core/services/native_google_auth.dart';
import 'package:abelnotes/core/services/secure_google_token_storage.dart';
import 'package:abelnotes/l10n/app_localizations.dart';

/// Whether this platform can run the Drive sign-in.
///
/// Everything but the web: mobile uses the platform account sheet, desktop a
/// loopback redirect. A browser-hosted build would need a third flow and
/// doesn't have one.
bool get driveSignInSupported => !kIsWeb;

/// Signs in to Google and points sync at Drive. Returns true on success.
///
/// Every failure here is an ordinary outcome rather than a bug — the user
/// closes the browser tab, the build carries no credentials, the machine has
/// no keyring — so each gets its own message and nothing is changed.
Future<bool> connectDrive(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);

  void say(String message) =>
      messenger.showSnackBar(SnackBar(content: Text(message)));

  // Desktop needs an OAuth client compiled in; on mobile the platform's own
  // component holds the client, so there is nothing to check.
  if (!useNativeGoogleSignIn &&
      !ref.read(googleOAuthConfigProvider).isConfigured) {
    say(l10n.driveNotConfigured);
    return false;
  }

  // Coming from another remote, the user has to know two things before the
  // consent screen: their notebooks move to Drive, and the copies left on
  // the old remote stop updating. Discovering that three months later, with
  // a stale server copy they thought was a backup, is how trust is lost.
  if (!await _confirmSwitch(context, ref)) return false;

  try {
    if (useNativeGoogleSignIn) {
      // The account sheet appears over the app and the platform keeps the
      // tokens; nothing to store on our side.
      await ref.read(nativeGoogleAuthProvider).signIn();
    } else {
      final tokens = await DesktopGoogleSignIn(
        ref.read(googleOAuthClientProvider),
        openUrl: (url) async {
          if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
            throw GoogleReauthRequired('could not open a browser');
          }
        },
      ).signIn();
      await ref.read(desktopGoogleAuthProvider).adopt(tokens);
    }

    await applySyncBackend(
      files: ref.read(fileServiceProvider),
      settings: ref.read(appSettingsProvider.notifier),
      backend: SyncBackend.drive,
    );
    say(l10n.driveConnectedTitle);
    return true;
  } on GoogleTokenStorageUnavailable {
    say(l10n.driveNoKeyring);
  } on GoogleSignInCancelled {
    say(l10n.driveSignInCancelled);
  } on GoogleReauthRequired {
    // NOT "cancelled": on mobile this is where a build missing its web
    // client id lands, and it fails before the user is shown anything.
    say(l10n.driveSignInFailed);
  } catch (_) {
    say(l10n.driveSignInFailed);
  }
  return false;
}

/// Asks before moving sync off a remote that is already in use. Returns
/// true when there is nothing to warn about.
Future<bool> _confirmSwitch(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final current = ref.read(appSettingsProvider).syncBackend;
  if (current == SyncBackend.drive) return true;
  // Nothing configured means nothing to leave behind.
  if (ref.read(remoteStoreProvider) == null) return true;

  final answer = await showDialog<bool>(
    context: context,
    builder: (dCtx) => AlertDialog(
      title: Text(l10n.setSyncSwitchTitle),
      content: Text(l10n.setSyncSwitchBody),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l10n.setCancel)),
        TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(l10n.setSyncSwitchConfirm)),
      ],
    ),
  );
  return answer == true;
}

/// Drops the Google account and goes back to local-only.
///
/// The notebooks already in the user's Drive are left alone: this app put
/// them in a folder the user can see, and deleting someone's files because
/// they unlinked an account would be indefensible.
Future<void> disconnectDrive(WidgetRef ref) async {
  if (useNativeGoogleSignIn) {
    await ref.read(nativeGoogleAuthProvider).signOut();
  } else {
    await ref.read(desktopGoogleAuthProvider).signOut();
  }
  await applySyncBackend(
    files: ref.read(fileServiceProvider),
    settings: ref.read(appSettingsProvider.notifier),
    backend: null,
  );
}

/// Points sync at [backend], un-claiming every notebook first.
///
/// The un-claim is the whole point, and it is not optional. Nothing in the
/// notebooks table records WHICH remote a row came from: rows left `synced`
/// while a different remote answers are read by the library's cleanup as
/// "this notebook was deleted on the server" and hard deleted — DB row,
/// loose store, .ncnote and snapshots, with no trash to recover from.
///
/// Downgraded to `modified` they are what they actually are, local content
/// no remote owns yet. The cleanup skips them, and the pending-upload retry
/// puts them on whichever remote is now connected. The copies on the old
/// remote are never touched.
Future<void> applySyncBackend({
  required FileService files,
  required AppSettingsNotifier settings,
  required String? backend,
}) async {
  await files.markAllNotebooksLocal();
  settings.setSyncBackend(backend);
}
