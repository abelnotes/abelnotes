# Microsoft Store release

MSIX packaging only. Config lives in `pubspec.yaml` under `msix_config`.

## Test build

```bash
dart run msix:create
# -> build/windows/x64/runner/Release/abelnotes.msix
```

Uses the self-signed cert at `certs/abelnotes_test.pfx` (gitignored, as is any
`*.pfx`). Regenerate it with:

```powershell
$cert = New-SelfSignedCertificate -Type Custom -Subject "CN=AbelNotes Test" `
  -KeyUsage DigitalSignature -CertStoreLocation "Cert:\CurrentUser\My" `
  -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3","2.5.29.19={text}")
Export-PfxCertificate -Cert $cert -FilePath certs\abelnotes_test.pfx `
  -Password (ConvertTo-SecureString -String "abelnotes" -Force -AsPlainText)
```

`publisher` in `msix_config` must equal the cert's CN exactly, and the cert
needs the code-signing EKU (`1.3.6.1.5.5.7.3.3`) — without it signing fails.

## Installing the test package

Sideloading requires the signing cert in **Local Machine → Trusted People**,
which needs an elevated shell:

```powershell
Import-PfxCertificate -FilePath certs\abelnotes_test.pfx `
  -CertStoreLocation Cert:\LocalMachine\TrustedPeople `
  -Password (ConvertTo-SecureString -String "abelnotes" -Force -AsPlainText)
Add-AppxPackage build\windows\x64\runner\Release\abelnotes.msix
```

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

Take `identity_name` (Package/Identity/Name) and `publisher` (`CN=<GUID>`) from
Partner Center → Product identity. Then in `msix_config`:

- set those two values
- delete `certificate_path` and `certificate_password`
- add `store: true`

```bash
dart run msix:create --store
```

The output is **unsigned**. That is correct — the Store signs it.

## Versioning

`msix_version` is four numbers, the last always `0`, and must increase on every
submission. It is independent of `version:` in `pubspec.yaml` — the `+41` build
number has no place in it. Bump the patch: `0.37.2.0` → `0.37.3.0`.

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
