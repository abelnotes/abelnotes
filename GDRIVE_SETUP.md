# Building with Google Drive sync

Drive sync is optional. A build without the credentials below still compiles,
installs and runs — the Drive option simply says it is unavailable, which is
what an unconfigured build should do. Everything else, including sync to your
own WebDAV/Nextcloud server, is unaffected.

To build it enabled you need your own Google Cloud project. The credentials
are per-project and are deliberately not in this repository.

## The scope, and why it matters

AbelNotes asks for `https://www.googleapis.com/auth/drive.file` and nothing
else: access to the files the app itself created, not to the user's Drive.

That is a product decision as much as a privacy one. `drive.file` is
classified non-sensitive, so it needs no verification, no demo video and no
annual third-party security assessment. `drive` and `drive.readonly` are
restricted scopes and drag in a paid audit that has to be repeated every
twelve months. Do not widen the scope without understanding that bill.

`drive.file` grants belong to the Cloud **project**, not to an individual
OAuth client. That is why one project can hold separate Android, desktop and
iOS clients and they all see the same notebooks. `tool/gdrive_scope_spike.dart`
is the experiment that established it, if you want to re-run it yourself.

## Cloud console setup

1. Create a project and enable the **Google Drive API** (not "Drive Labels").
2. Configure the consent screen as **External**, and add your own account
   under **Test users** while the project is in Testing.
3. Create an OAuth client per platform you build:
   - **Desktop app** for Linux/Windows/macOS — has a client secret.
   - **Android** for the APK/AAB — no secret; bound to the package name
     `app.abelnotes.notes` and the SHA-1 of the signing certificate. The
     debug certificate and the Play App Signing certificate are different
     fingerprints and each needs its own client.

While the project is in Testing, refresh tokens expire after seven days. The
app treats that as "ask the user to sign in again", which is the same path a
revoked or expired token takes in production — so it is worth leaving in
Testing long enough to see that path work.

## Desktop build

```bash
flutter build linux --release \
  --dart-define=GOOGLE_CLIENT_ID=<desktop client id> \
  --dart-define=GOOGLE_CLIENT_SECRET=<desktop client secret>
```

The desktop secret is not really secret — anyone can extract it from the
binary — which is why sign-in uses PKCE, where the secret alone is useless.
Keep it out of the repository regardless: committed credentials get scanned
for and reported whether or not they are dangerous.

Sign-in opens the browser and waits on a loopback port chosen by the OS.

## Android build

Android signs in through the platform's own account sheet, not a browser:
Google switched off browser redirects for new Android OAuth clients, and the
per-client toggle that re-enables them is being retired.

That component needs a **web** OAuth client id — not the Android one — even
though no web app exists. It identifies the project to the Credential Manager
SDK. Create an "Application web" client alongside the Android one; leave its
origins and redirect URIs empty.

```bash
flutter build appbundle --release \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>
```

The Android OAuth client itself is never named in the build: Google matches it
by package name plus signing certificate. Which is why the fingerprint has to
be the one that signs the app **as installed** — for anything from Play, that
is Google's app signing certificate, not your upload key. A build signed
locally for debugging needs its own Android client registered against the
debug certificate.

If the web client id is missing, sign-in fails instantly and Android reports
it as a *cancellation*: the plugin cannot tell that case apart from the user
closing the sheet. Do not go looking for a user-facing bug — check this first.

## Before publishing

- Update the Play Console **Data safety** form. The app now touches files in
  the user's Drive, and a declaration that doesn't match behaviour gets the
  app suspended, not fined.
- Add the OAuth client for the **Play App Signing** certificate, otherwise
  sign-in works in your testing and fails for everyone who installs from the
  store.
- Brand verification (homepage, privacy policy linked *from* that homepage,
  verified domain) is what puts your name and logo on the consent screen
  instead of a bare client id.
