# AbelNotes branding assets

Copyright © 2026 **Joy**. All rights reserved.

**These files are NOT covered by the repository's AGPL-3.0 license.**

The name "AbelNotes", the wordmark, and the logo/icon in this folder are
the trademark and copyright of the rights holder named above. The AGPL-3.0
license (see [/LICENSE](../../LICENSE)) applies to the *source code* only —
it grants no rights to this brand identity. See [/TRADEMARK.md](../../TRADEMARK.md).

If you fork or redistribute AbelNotes, you must remove or replace everything
in this folder and choose your own name and icon (see TRADEMARK.md).

## Contents

Put the master/source brand files here, e.g.:

- `app_icon_master.svg` (or `.png`) — vector/large master the app icon is
  derived from. The build-time source consumed by `flutter_launcher_icons`
  lives at [`assets/icon/app_icon.png`](../icon/) (1024×1024); generate it
  from this master.
- `logo_wordmark.svg` — the "AbelNotes" wordmark, if/when one exists.

These are source-of-truth design files, kept out of the runtime asset
bundle on purpose — they are not shipped inside the app, only used to
produce the platform icon sets.
