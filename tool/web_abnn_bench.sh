#!/usr/bin/env bash
# The region router and handwriting OCR as WebAssembly against the native
# engine's pinned outputs (test/fixtures/region_router/engine_outputs.json), in
# headless Chromium (test/web/abnn_wasm_bench.dart): parity and timings.
#
#   tool/web_abnn_bench.sh
#
# Needs node with `playwright` (or PLAYWRIGHT_CORE pointing at playwright-core).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/web_abnn_bench
flutter build web --release --no-web-resources-cdn -t test/web/abnn_wasm_bench.dart -o "$OUT" >/dev/null
rm -rf "$OUT/bench"
mkdir -p "$OUT/bench"
cp test/fixtures/circuits/*.json test/fixtures/region_router/*.json "$OUT/bench/"
python3 - "$OUT/bench" <<'PY'
import json, os, sys
d = sys.argv[1]
circuits = sorted(f for f in os.listdir('test/fixtures/circuits') if f.endswith('.json'))
json.dump({'circuits': circuits}, open(os.path.join(d, 'index.json'), 'w'))
PY
node tool/web_circuit_bench.mjs "$OUT" ABNN
