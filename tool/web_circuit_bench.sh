#!/usr/bin/env bash
# The circuit engine's WebAssembly build against the Dart path in headless
# Chromium (test/web/circuit_wasm_bench.dart): parity and UI-thread time.
#
#   tool/web_circuit_bench.sh [picture ...]
#
# Stroke cases: test/fixtures/circuits. Pictures (PNG/JPEG) are optional.
# Needs node with `playwright` (or PLAYWRIGHT_CORE pointing at playwright-core).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/web_circuit_bench
flutter build web --release --no-web-resources-cdn -t test/web/circuit_wasm_bench.dart -o "$OUT" >/dev/null
rm -rf "$OUT/bench"
mkdir -p "$OUT/bench"
cp test/fixtures/circuits/*.json "$OUT/bench/"
images=()
for f in "$@"; do
  name="img$((${#images[@]} + 1)).${f##*.}"
  cp "$f" "$OUT/bench/$name"
  images+=("$name")
done
python3 - "$OUT/bench" "${images[@]}" <<'PY'
import json, os, sys
d, images = sys.argv[1], sys.argv[2:]
strokes = sorted(f for f in os.listdir(d) if f.endswith('.json') and f != 'index.json')
json.dump({'strokes': strokes, 'images': images}, open(os.path.join(d, 'index.json'), 'w'))
PY
node tool/web_circuit_bench.mjs "$OUT"
