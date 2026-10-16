# Flatpak / Flathub packaging

Flatpak packaging for AbelNotes, for [Flathub](https://flathub.org) or an own
repository. The offline sandbox build is verified with `flatpak-builder
--sandbox` on x86_64.

## Layout

- `flatpak-flutter.yml` — the maintained template (source of truth).
- `app.abelnotes.notes.desktop` — installed from the tagged app source.
- `app.abelnotes.notes.metainfo.xml` — AppStream metadata, installed from this
  folder (not from the tag), so release notes can be added without a new tag.
  `flathub-submission/` links to it.
- `flathub-submission/` — the generated offline manifest
  (`app.abelnotes.notes.yml`) plus `generated/` (pinned Flutter SDK, pub
  packages, Rust crates, patches). This is what goes into the Flathub repo.
- `build-defines.json` (never committed) — written next to the manifest before
  each build: `{"GIT_COMMIT": "...", "GOOGLE_CLIENT_ID": "...",
  "GOOGLE_CLIENT_SECRET": "..."}`, the desktop Drive client. Missing values
  only disable Drive; the file itself must exist.

## App ID

`app.abelnotes.notes` — the reverse of the `abelnotes.app` domain, shared with
the Android namespace and the Linux runner. Domain ownership is proven after
publishing through Flathub's website-verification flow.

## Cutting a new release

1. Bump the version and tag it (`vX.Y.Z`), push the tag to this repo.
2. Point the app source at the new tag in `flatpak-flutter.yml`, and add a
   `<release>` entry to `app.abelnotes.notes.metainfo.xml`.
3. Regenerate the offline sources when dependencies or the Flutter version
   changed (otherwise the existing `generated/` stays valid):

   ```sh
   git clone https://github.com/TheAppgineer/flatpak-flutter
   cd flatpak
   python3 /path/to/flatpak-flutter/flatpak-flutter.py --app-module abelnotes flatpak-flutter.yml
   ```

4. Verify the offline build, then update the Flathub repo with the contents of
   `flathub-submission/`.

## CI

`.github/workflows/flatpak.yml` builds `flathub-submission/` on every change
under `flatpak/` and uploads the resulting `app.abelnotes.notes.flatpak` as an
artifact, so a broken manifest or stale generated sources show up in the PR.
It writes a `build-defines.json` with only `GIT_COMMIT`, so Drive is off in
that artifact. Install it with `flatpak install --user app.abelnotes.notes.flatpak`.

## Verifying the offline build

Run this outside the source tree so the build artifacts do not land in the repo:

```sh
C=$(git rev-parse --short 'v0.37.7^{commit}')   # the tag the manifest builds
cp -rL flatpak/flathub-submission /tmp/abelnotes-flathub && cd /tmp/abelnotes-flathub
echo "{\"GIT_COMMIT\": \"$C\"}" > build-defines.json
flatpak-builder --repo=repo --force-clean --sandbox --user \
    --install-deps-from=flathub build-dir app.abelnotes.notes.yml
```

`-L` copies the metainfo symlink as a file.

## Runtime

`org.freedesktop.Platform` **25.08**: 24.08 is end-of-life (no security
fixes), and installs on it print an EOL notice. 26.08 has no llvm20 SDK
extension yet. Moving runtime installs the new one on users' machines through a
normal update.

## Own repository (until Flathub)

A signed OSTree repo served as static files gives the same update path as
Flathub. The build above already produced `repo/`; sign and index it:

```sh
flatpak build-update-repo --title=AbelNotes --default-branch=stable \
    --generate-static-deltas --prune --gpg-sign=KEYID repo
```

Users install with one click from an `abelnotes.flatpakref`, which adds the
`abelnotes` remote (and Flathub for the runtime) on its own:

```ini
[Flatpak Ref]
Title=AbelNotes
Name=app.abelnotes.notes
Branch=stable
Url=https://<host>/repo/
SuggestRemoteName=abelnotes
Homepage=https://abelnotes.app
RuntimeRepo=https://dl.flathub.org/repo/flathub.flatpakrepo
IsRuntime=false
GPGKey=<base64 of `gpg --export KEYID`>
```

A single-file bundle for the GitHub release does the same, its `notes-origin`
remote pointing at the repo with GPG verification on:

```sh
flatpak build-bundle --repo-url=https://<host>/repo/ \
    --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
    --gpg-keys=key.gpg repo abelnotes.flatpak app.abelnotes.notes stable
```

Verified on 0.37.7 with a throwaway key: one-click install into an empty
installation, a wrong key is refused, a new commit shows up in
`flatpak update`, and the bundle keeps updating from the repo.

## Why the extra modules exist

- **libsecret** (`--libdir=lib`) — `flutter_secure_storage_linux` links it and
  the runtime ships none; meson defaults to `lib64`, which is off
  `PKG_CONFIG_PATH`.
- **zenity** (3.44, GTK3) — `file_picker` shells out to it for file dialogs.
  Inside the sandbox GTK routes it through the FileChooser portal, so the
  dialog is the desktop's own. Built manually so its `gtk-update-icon-cache`
  step can be seeded with an `index.theme`.
- **xrandr** + **xinput** — used by the optional "restrict the pen to one
  monitor" feature (`pen_monitor_service.dart`). X11 only; the app hides the
  entry on Wayland and other platforms.
- `CXXFLAGS=-Wno-error=deprecated-literal-operator` — the secure-storage plugin
  bundles an old `nlohmann/json.hpp` that clang (llvm20) rejects under
  `-Werror`.
- `--filesystem=home` — notebooks live in the host `~/Documents/AbelNotes`
  (shared with a `.deb` install). File dialogs go through the portal and would
  not need it on their own.
- Passwords: inside the sandbox libsecret uses its file backend
  (`~/.var/app/app.abelnotes.notes/data/keyrings/`), encrypted with a key the
  Secret portal keeps in the host keyring. Nothing is stored in plain text.
- `--device=input` stays **off**: the stylus pressure path that matters reads
  the GDK axis through the display server and works sandboxed. Only tablets
  with no GDK pressure axis would need raw `/dev/input`.

## Relationship to the `.deb`

`tool/build_deb.sh` covers Debian/Ubuntu/Mint. Flatpak covers Fedora, immutable
distros and everyone installing through GNOME Software, KDE Discover or the
Mint Software Manager. The two are complementary.

## Sandbox caveats

- **Data location**: notebooks live in the host `~/Documents/AbelNotes`, the
  same folder a `.deb` install uses. Settings live in
  `~/.var/app/app.abelnotes.notes/`, so switching from the `.deb` shows the
  same notebooks but the server has to be connected again.
- **Credentials**: need a running Secret Service on the host (see above);
  logins saved by a native install are not carried over.
- **Files outside `$HOME`**: picking them in a file dialog works through the
  portal; only the notebook folder itself has to be under `$HOME`.
- **Private CAs**: the host CA store is not visible, so a Nextcloud behind a
  self-signed or private CA is expected to fail TLS until the CA is trusted
  another way.
- **Pen-to-monitor restriction**: `xrandr`/`xinput` only see Xwayland inside the
  sandbox, so the feature is not expected to work on Wayland.
