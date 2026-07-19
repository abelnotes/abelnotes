# Security Policy

## Reporting a vulnerability

Please report security issues privately via [GitHub Security Advisories](../../security/advisories/new) — use the "Report a vulnerability" button on this repo's Security tab. Do not open a public issue for anything that could put users at risk before a fix ships.

This is a solo-maintained project: expect an initial response within a few days, not a guaranteed SLA. I'll credit reporters in the advisory unless you ask not to be named.

## Scope

In scope: the app's own code (this repository) — sync, storage, auth, credential handling, PDF/import parsing.

Out of scope: your own WebDAV/Nextcloud server's security, and third-party dependencies (report those upstream; see [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md) for the dependency list).

## Known limitations

These are already known and intentionally not treated as new vulnerability reports — please check here before opening one.

**In transit** — WebDAV connections use TLS. On first connect, the certificate's SHA-256 fingerprint is pinned (trust-on-first-use); if it later changes without you re-authenticating, the connection fails instead of silently trusting it.

**Credentials at rest** — the WebDAV/Nextcloud password goes through `flutter_secure_storage`: Android Keystore (AES-256/GCM, hardware-backed where available), iOS/macOS Keychain (`WhenUnlocked`, not iCloud-synced), Windows DPAPI, Linux Secret Service (GNOME Keyring/KWallet). Server URL, username and the pinned fingerprint live in plain `SharedPreferences` — not secrets.

**Notebook content at rest — not encrypted.** Notes are plain JSON/ZIP, on-device and on your server. Protect them the way you protect the rest of your self-hosted data (full-disk encryption, a trusted server). End-to-end encryption of note content is on the roadmap, not yet built — if it matters to you, weigh in on the tracking issue.

**Headless Linux with no Secret Service daemon** — `flutter_secure_storage` falls back to storing the credential in plaintext. This is a known limitation of the platform/plugin, not silently hidden — see `lib/core/providers/auth_provider.dart`. Use full-disk encryption or a keyring provider if you run headless.

## Supported versions

Pre-1.0: only the latest release gets security fixes.
