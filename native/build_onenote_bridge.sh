#!/usr/bin/env bash
# Builds the OneNote FFI bridge and refreshes the committed prebuilt binary
# that the Flutter desktop build bundles (see linux/CMakeLists.txt).
# Requires a Rust toolchain (rustup.rs).
set -euo pipefail
cd "$(dirname "$0")/onenote_bridge"

# Remap local build paths (home dir, cargo registry) out of the compiled
# binary — panic!/source-location strings otherwise bake the dev machine's
# absolute paths into every release build.
#
# --remap-path-prefix matches literally, so on Windows the prefix has to be
# the Windows-shaped path rustc actually sees: under Git Bash `pwd` yields
# /c/… while cargo passes C:\…, and only the latter matches. Remap both.
repo_root="$(cd ../.. && pwd)"
remap="--remap-path-prefix=$HOME=~ --remap-path-prefix=$repo_root=."
repo_root_win="$(cd ../.. && pwd -W 2>/dev/null || true)"
if [ -n "$repo_root_win" ]; then
  remap="$remap --remap-path-prefix=$(printf '%s' "$repo_root_win" | tr '/' '\\')=."
  remap="$remap --remap-path-prefix=$repo_root_win=."
fi
if [ -n "${USERPROFILE:-}" ]; then
  remap="$remap --remap-path-prefix=$USERPROFILE=~"
fi
export RUSTFLAGS="$remap"

cargo build --release

case "$(uname -s)" in
  Linux)
    out="../prebuilt/linux-x64"
    lib="libonenote_bridge.so"
    ;;
  Darwin)
    out="../prebuilt/macos-x64"
    lib="libonenote_bridge.dylib"
    ;;
  *)
    out="../prebuilt/windows-x64"
    lib="onenote_bridge.dll"
    ;;
esac
mkdir -p "$out"
cp "target/release/$lib" "$out/"
echo "aggiornato $out/$lib"
