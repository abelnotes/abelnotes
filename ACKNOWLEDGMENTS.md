# Acknowledgments

This app is built on open-source software. Thank you to every maintainer
and contributor of the projects below.

The complete license text of every package — including all transitive
dependencies — is available in-app via the licenses page (Flutter's
`LicenseRegistry`). This file lists the direct dependencies and the
notable native components.

License audit (last run 2026-07-19, 185 packages from pub.dev):
**no GPL/AGPL/LGPL dependencies** — everything is BSD, MIT, Apache-2.0,
plus one MPL-2.0 native component (file-level copyleft, used unmodified,
attributed below).

## Framework

| Component | License |
|---|---|
| [Flutter](https://flutter.dev) & Dart SDK (incl. `flutter_localizations`, `sky_engine`) | BSD-3-Clause |

## Runtime dependencies (pub.dev)

| Package | License |
|---|---|
| archive | MIT |
| collection | BSD-3-Clause |
| crypto | BSD-3-Clause |
| csv | MIT |
| cupertino_icons | MIT |
| ffi | BSD-3-Clause |
| file_picker | MIT |
| flutter_math_fork | Apache-2.0 (bundled KaTeX fonts: MIT, © Khan Academy) |
| flutter_riverpod / riverpod_annotation | MIT |
| flutter_secure_storage | BSD-3-Clause |
| freezed_annotation | MIT |
| http | BSD-3-Clause |
| image | MIT |
| image_picker | BSD-3-Clause |
| intl | BSD-3-Clause |
| json_annotation | BSD-3-Clause |
| markdown | BSD-3-Clause |
| path | BSD-3-Clause |
| path_provider | BSD-3-Clause |
| pdf | Apache-2.0 |
| pdfrx | MIT (bundles PDFium: BSD-3-Clause, © Google / Foxit) |
| receive_sharing_intent | Apache-2.0 |
| share_plus | BSD-3-Clause |
| shared_preferences | BSD-3-Clause |
| sqflite / sqflite_common_ffi | BSD-2-Clause |
| super_clipboard | MIT |
| uuid | MIT |
| vector_math | BSD-3-Clause |
| xml | MIT |
| yaml | MIT |

## Native components

| Component | License | Notes |
|---|---|---|
| [onenote.rs](https://github.com/msiemens/onenote.rs) (`onenote_parser`) | MPL-2.0 | Rust crate powering the OneNote import bridge (`native/onenote_bridge`). Used unmodified; license text shipped at `assets/licenses/onenote_parser_LICENSE.txt` and registered in the in-app licenses page. |
| Rust bridge transitive crates (serde, base64, flate2, …) | MIT / Apache-2.0 dual | Standard Rust ecosystem licensing. |
| PDFium | BSD-3-Clause | Bundled by `pdfrx` for PDF rendering and text extraction. |
| KaTeX fonts | MIT | Bundled by `flutter_math_fork` for math rendering. |

Pen pressure on Linux is read directly from the kernel evdev interface
(`/dev/input`) — no external library involved.

## Development-only dependencies

`flutter_test`, `flutter_lints`, `build_runner`, `freezed`,
`json_serializable`, `riverpod_generator`, `flutter_launcher_icons` —
BSD/MIT licensed, not distributed with the app.
