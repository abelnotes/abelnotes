#!/usr/bin/env bash
# Build the circuit engine (packages/circuit_engine/src) to WebAssembly for
# the web app: web/circuit_engine.wasm, committed, shipped by tool/build_web.sh.
#
#   pip install ziglang==0.17.1   # the pinned toolchain (zig cc, wasm-ld)
#   tool/build_circuit_wasm.sh
#
# ZIG overrides the command (default: zig, else python3 -m ziglang).
set -euo pipefail
cd "$(dirname "$0")/.."

ZIG_VERSION=0.17.1
if [ -n "${ZIG:-}" ]; then
  read -r -a zig <<<"$ZIG"
elif command -v zig >/dev/null; then
  zig=(zig)
else
  zig=(python3 -m ziglang)
fi
have="$("${zig[@]}" version)"
if [ "$have" != "$ZIG_VERSION" ]; then
  echo "zig $have, want $ZIG_VERSION (pip install ziglang==$ZIG_VERSION)" >&2
  exit 1
fi

SRC=packages/circuit_engine/src
OUT=web/circuit_engine.wasm
# One thread, no WASI imports (the engine reads no files, clock or environment
# there); SIMD128 for the vector loops, supported by every current browser.
"${zig[@]}" cc -target wasm32-wasi -mexec-model=reactor -O3 -msimd128 -fno-math-errno \
  -fvisibility=hidden -g0 -ffile-prefix-map="$PWD"=. \
  -Wl,--export-dynamic -Wl,--strip-all \
  -o "$OUT" "$SRC/circuit_engine.c" "$SRC/image_ink.c" "$SRC/abnn.c" "$SRC/region_router.c"

# The page instantiates it with no imports: fail here, not in a browser.
if command -v node >/dev/null; then
  node -e '
const m = new WebAssembly.Module(require("fs").readFileSync(process.argv[1]));
const imports = WebAssembly.Module.imports(m);
if (imports.length) { console.error("unexpected imports", imports); process.exit(1); }
' "$OUT"
fi

echo "Built $OUT ($(wc -c <"$OUT") bytes), sha256 $(sha256sum "$OUT" | cut -c1-16)"
