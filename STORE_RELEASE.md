# Microsoft Store release

MSIX packaging only. Config lives in `pubspec.yaml` under `msix_config`.

## Test build

`msix_config` holds the Store values, so a sideload build overrides the three
that differ on the command line rather than editing the file back and forth —
`--publisher` has to match the test cert's CN exactly, and `store: true` in the
yaml is what `--no-store` cancels.

```bash
flutter test          # AppConfig.appVersion is hand-maintained; this is the
                      # only thing that catches it drifting from pubspec, and
                      # CI would only catch it after the package is built
flutter build windows --release --dart-define=GIT_COMMIT=$(git rev-parse HEAD)
dart run msix:create --build-windows false --no-store `
  --certificate-path certs/abelnotes_test.pfx `
  --certificate-password "<the test cert's password>" `
  --publisher "CN=AbelNotes Test"
# -> build/windows/x64/runner/Release/abelnotes.msix
```

**Build first, package second.** `msix:create` runs its own `flutter build
windows` and has no `--dart-define` passthrough, so letting it build leaves
`AppConfig.gitCommit` at its `'dev'` fallback and the package cannot be traced
to a commit — that is how the first MSIX shipped as `v0.0.0+0 dev`. CI passes
the define, but CI does not build the MSIX. `--build-windows false` makes
`msix:create` package the output above instead of rebuilding it.

Both lines work verbatim in PowerShell. Confirm afterwards in Settings → About,
which shows the version and the commit on one line.

Uses the self-signed cert at `certs/abelnotes_test.pfx` (gitignored, as is any
`*.pfx`). Regenerate it with:

```powershell
$cert = New-SelfSignedCertificate -Type Custom -Subject "CN=AbelNotes Test" `
  -KeyUsage DigitalSignature -CertStoreLocation "Cert:\CurrentUser\My" `
  -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3","2.5.29.19={text}")
Export-PfxCertificate -Cert $cert -FilePath certs\abelnotes_test.pfx `
  -Password (ConvertTo-SecureString -String "<scegli-tu-una-password>" -Force -AsPlainText)
```

`publisher` in `msix_config` must equal the cert's CN exactly, and the cert
needs the code-signing EKU (`1.3.6.1.5.5.7.3.3`) — without it signing fails.

## Installing the test package

```powershell
powershell -ExecutionPolicy Bypass -File tool\install_test_msix.ps1
```

It elevates itself, trusts the cert and sideloads the package.

The cert is self-signed, so it is its own root: it has to go into **Local
Machine → Trusted Root**, not Trusted People. Anything less and install fails
with `0x800B010A` / `0x800B0109` and the publisher shows as Unknown. Writing
there needs admin — an unelevated shell fails with `E_ACCESSDENIED` and the
install then fails for the missing root, which reads like two bugs but is one.

A cert in Trusted Root is trusted machine-wide for anything it signs, so pull
it back out when done testing:

```powershell
Get-ChildItem Cert:\LocalMachine\Root |
  Where-Object Subject -eq "CN=AbelNotes Test" | Remove-Item
```

None of this applies to the Store build: the Store signs the package with its
own chain, so users never install a certificate.

`install_certificate: false` is deliberate: the prompt hangs any non-tty shell,
so trusting the cert stays a separate step.

## WACK

Run before every upload — it catches in minutes what a failed review costs in
days. Elevated shell:

```powershell
$k = "C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe"
& $k reset
& $k test -appxpackagepath "$PWD\build\windows\x64\runner\Release\abelnotes.msix" `
         -reportoutputpath "$PWD\build\wack-report.xml"
```

## Store build

`msix_config` is already set up for this: the three identity fields are
Partner Center's own (Product management → Product identity) and must stay
verbatim — a mismatch fails the upload, not the build, so nothing warns you
until Partner Center rejects it.

```bash
flutter test
flutter build windows --release --dart-define=GIT_COMMIT=$(git rev-parse HEAD)
dart run msix:create --store --build-windows false
```

The commit stamp matters most here: this is the package users get, and a crash
log pasted into an issue is only useful if it names the build it came from.

The output is **unsigned**. That is correct — the Store signs it.

## Versioning

`msix_version` is four numbers, the last always `0`, and must increase on every
submission. It is independent of `version:` in `pubspec.yaml` — the `+NN` build
number has no place in it. Bump the patch each time: `0.37.2.0` → `0.37.3.0`.

`version:` is a separate bump, and `AppConfig.appVersion` / `appBuildNumber` in
`lib/config/app_config.dart` must move with it — that pair is what Settings →
About and the crash log show. `test/app_version_test.dart` fails if they drift.
Flutter's generated `version.json` is not an option here: it does not exist on
Windows or Linux, which is how `0.0.0+0` reached the first MSIX.

## Data locations under MSIX

Notes stay in the real `Documents\AbelNotes` (unvirtualized, thanks to
`runFullTrust`). `shared_preferences` and `flutter_secure_storage` are
redirected into the package container, so moving between an MSIX and a plain
build keeps notes but loses settings and the saved server password.

## Store listing: licence terms

The Store's standard terms conflict with AGPL-3.0, so the submission must use
custom licence terms. Paste into Partner Center → Properties → Licence terms:

> AbelNotes is free software, licensed under the GNU Affero General Public
> License, version 3 or later (AGPL-3.0-or-later). The full licence text ships
> with the application and is available at
> https://www.gnu.org/licenses/agpl-3.0.html
>
> Source code: https://github.com/abelnotes/abelnotes
>
> This software is provided "as is", without warranty of any kind, express or
> implied. You may use, study, modify and redistribute it under the terms of
> the AGPL-3.0-or-later.

VLC is the precedent that a copyleft licence is accepted on the Store.
