# Flatpak / Flathub packaging

Packaging for shipping AbelNotes on [Flathub](https://flathub.org). The offline
sandbox build is verified with `flatpak-builder --sandbox` on x86_64.

## Layout

- `flatpak-flutter.yml` — the maintained template (source of truth).
- `app.abelnotes.notes.desktop`, `app.abelnotes.notes.metainfo.xml` — AppStream
  metadata, installed by the build from this repo.
- `flathub-submission/` — the generated offline manifest
  (`app.abelnotes.notes.yml`) plus `generated/` (pinned Flutter SDK, pub
  packages, Rust crates, patches). This is what goes into the Flathub repo.

## App ID

`app.abelnotes.notes` — the reverse of the `abelnotes.app` domain, shared with
the Android namespace and the Linux runner. Domain ownership is proven after
publishing through Flathub's website-verification flow.

## Cutting a new release

1. Bump the version and tag it (`vX.Y.Z`), push the tag to this repo.
2. Point the app source at the new tag in `flatpak-flutter.yml`, and update the
   screenshot URLs in `app.abelnotes.notes.metainfo.xml` to the same tag.
3. Regenerate the offline sources when dependencies or the Flutter version
   changed (otherwise the existing `generated/` stays valid):

   ```sh
   git clone https://github.com/TheAppgineer/flatpak-flutter
   cd flatpak
   python3 /path/to/flatpak-flutter/flatpak-flutter.py --app-module abelnotes flatpak-flutter.yml
   ```

4. Verify the offline build, then update the Flathub repo with the contents of
   `flathub-submission/`.

## Verifying the offline build

Run this outside the source tree so the build artifacts do not land in the repo:

```sh
cp -r flatpak/flathub-submission /tmp/abelnotes-flathub && cd /tmp/abelnotes-flathub
flatpak-builder --repo=repo --force-clean --sandbox --user \
    --install-deps-from=flathub build-dir app.abelnotes.notes.yml
```

## Why the extra modules exist

- **libsecret** (`--libdir=lib`) — `flutter_secure_storage_linux` links it and
  the runtime ships none; meson defaults to `lib64`, which is off
  `PKG_CONFIG_PATH`.
- **zenity** (3.44, GTK3) — `file_picker` shells out to it for file dialogs.
  Built manually so its `gtk-update-icon-cache` step can be seeded with an
  `index.theme`.
- **xrandr** + **xinput** — used by the optional "restrict the pen to one
  monitor" feature (`pen_monitor_service.dart`). X11 only; the app hides the
  entry on Wayland and other platforms.
- `CXXFLAGS=-Wno-error=deprecated-literal-operator` — the secure-storage plugin
  bundles an old `nlohmann/json.hpp` that clang (llvm20) rejects under
  `-Werror`.
- `--filesystem=home` — the file dialog runs inside the sandbox without a
  portal, so it needs real filesystem access for note and PDF import/export.
- `--device=input` stays **off**: the stylus pressure path that matters reads
  the GDK axis through the display server and works sandboxed. Only tablets
  with no GDK pressure axis would need raw `/dev/input`.

## Relationship to the `.deb`

`tool/build_deb.sh` covers Debian/Ubuntu/Mint. Flathub covers Fedora, immutable
distros and everyone installing through GNOME Software, KDE Discover or the
Mint Software Manager. The two are complementary.
