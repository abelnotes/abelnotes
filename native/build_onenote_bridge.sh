#!/usr/bin/env bash
# Builds the OneNote FFI bridge and refreshes the committed prebuilt binary
# that the Flutter desktop build bundles (see linux/CMakeLists.txt).
# Requires a Rust toolchain (rustup.rs).
set -euo pipefail
cd "$(dirname "$0")/onenote_bridge"

# Remap local build paths (home dir, cargo registry) out of the compiled
# binary — panic!/source-location strings otherwise bake the dev machine's
# absolute paths into every release build.
repo_root="$(cd ../.. && pwd)"
export RUSTFLAGS="--remap-path-prefix=$HOME=~ --remap-path-prefix=$repo_root=."

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
