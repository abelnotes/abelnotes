#!/usr/bin/env bash
# Build the AbelNotes web app (PWA) into build/web, ready to upload to any
# static host.
#
#   tool/build_web.sh                    # served from the site root
#   tool/build_web.sh /abelnotes/        # served from a sub-path
#   tool/build_web.sh / --dart-define=GOOGLE_WEB_CLIENT_ID=...   # extra flags
#
# What it adds on top of `flutter build web`:
#   * --no-web-resources-cdn  CanvasKit and fonts are bundled, not fetched from
#                             gstatic, so the app can start with no network.
#   * an offline service worker (tool/web_sw.js) replacing Flutter's stub.
set -euo pipefail
cd "$(dirname "$0")/.."

BASE_HREF="${1:-/}"
# SOURCE_MAPS=1 adds main.dart.js.map, to read stack traces from a device log.
flutter build web --release --no-web-resources-cdn --base-href "$BASE_HREF" \
  ${SOURCE_MAPS:+--source-maps} "${@:2}"

OUT=build/web
BUILD_ID="$(date +%Y%m%d%H%M%S)"

# The app script carries the build id, so a cached older shell never runs a
# newer script (the service worker leaves this file to the browser, see WEB_PWA.md).
MAIN_JS="main.dart.$BUILD_ID.js"
# flutter build leaves files it did not write: drop earlier builds' scripts.
rm -f "$OUT"/main.dart.[0-9]*.js
mv "$OUT/main.dart.js" "$OUT/$MAIN_JS"
python3 - "$OUT/flutter_bootstrap.js" "$MAIN_JS" <<'PY'
import sys
path, main_js = sys.argv[1:3]
src = open(path).read()
old = '"mainJsPath":"main.dart.js"'
if src.count(old) != 1:
    sys.exit(f'{path}: expected one {old}')
open(path, 'w').write(src.replace(old, f'"mainJsPath":"{main_js}"'))
PY

# Everything the app can need, relative to the site root. The CanvasKit
# variants for other renderers (skwasm, webparagraph) are never loaded.
FILES="$(cd "$OUT" && find . -type f \
  ! -name 'flutter_service_worker.js' ! -name '*.symbols' ! -name '*.map' \
  ! -name '.last_build_id' ! -name 'update.html' ! -path './canvaskit/skwasm*' \
  ! -path './canvaskit/experimental_webparagraph/*' \
  | sed 's|^\./||' | sort | python3 -c \
  'import sys,json; print(json.dumps(["./"]+[l.strip() for l in sys.stdin if l.strip()]))')"

python3 - "$OUT/flutter_service_worker.js" "$BUILD_ID" "$FILES" <<'PY'
import sys
out, build_id, files = sys.argv[1:4]
src = open('tool/web_sw.js').read()
open(out, 'w').write(src.replace('__BUILD_ID__', build_id).replace('__FILES__', files))
PY

echo "Built $OUT (offline cache id $BUILD_ID), $(du -sh "$OUT" | cut -f1)"
