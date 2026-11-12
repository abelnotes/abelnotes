#!/usr/bin/env bash
# Copy the web engine's Noto fallback fonts (emoji, CJK, other scripts) into a
# web build, so browsers load them from the app and never from fonts.gstatic.com.
#
#   tool/fetch_web_fonts.sh build/web     # called by build_web.sh
#   tool/fetch_web_fonts.sh --update      # after a Flutter upgrade: new checksums
#
# The files (724, about 22 MB) are not committed: they are downloaded once
# into a cache, checked against tool/web_fallback_fonts.sha256, then copied.
# SIL Open Font License 1.1, see web/fonts/fallback/OFL.txt.
set -euo pipefail
cd "$(dirname "$0")/.."

MANIFEST="$PWD/tool/web_fallback_fonts.sha256"
SRC=https://fonts.gstatic.com/s/
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/abelnotes/web-fallback-fonts"
FLUTTER_ROOT="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
ENGINE="$FLUTTER_ROOT/bin/cache/flutter_web_sdk/lib/_engine/engine"
[[ -f "$ENGINE/font_fallback_data.dart" ]] || { flutter precache --web >/dev/null; }

# Every path the engine appends to fontFallbackBaseUrl, for this Flutter version
# (its Roboto default is bundled as an asset, see pubspec.yaml).
engine_paths() {
  grep -oE "'[a-z0-9]+/v[0-9]+/[^']+\.(woff2|ttf|otf)'" "$ENGINE/font_fallback_data.dart" \
    | tr -d "'" | sort -u
}

fetch() { # <path>: into the cache, verified when the manifest has it
  local p="$1" want="${2:-}" f="$CACHE/$1"
  if [[ -f "$f" && ( -z "$want" || "$(sha256sum "$f" | cut -d' ' -f1)" == "$want" ) ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$f")"
  curl -fsSL --retry 3 -o "$f.part" "$SRC$p"
  if [[ -n "$want" && "$(sha256sum "$f.part" | cut -d' ' -f1)" != "$want" ]]; then
    rm -f "$f.part"; echo "checksum mismatch: $p" >&2; return 1
  fi
  mv "$f.part" "$f"
}
export -f fetch; export CACHE SRC

if [[ "${1:-}" == --update ]]; then
  engine_paths | xargs -P 8 -I{} bash -c 'fetch "$1"' _ {}
  ( cd "$CACHE" && engine_paths | xargs sha256sum ) > "$MANIFEST"
  echo "$MANIFEST: $(wc -l < "$MANIFEST") fonts, $(cd "$CACHE" && engine_paths | xargs du -cb | tail -1 | cut -f1) bytes"
  exit 0
fi

OUT="${1:?usage: $0 <build/web> | --update}"
if ! diff -q <(engine_paths) <(awk '{print $2}' "$MANIFEST" | sort) >/dev/null; then
  echo "Flutter's fallback font list differs from $MANIFEST: run $0 --update" >&2
  exit 1
fi
awk '{print $1, $2}' "$MANIFEST" | xargs -P 8 -n 2 bash -c 'fetch "$1" "$0"'
DEST="$OUT/fonts/fallback"
awk '{print $2}' "$MANIFEST" | while read -r p; do
  mkdir -p "$DEST/$(dirname "$p")"
  cp "$CACHE/$p" "$DEST/$p"
done
( cd "$DEST" && sha256sum --quiet -c "$MANIFEST" )
echo "Fallback fonts: $(wc -l < "$MANIFEST") files, $(du -sh "$DEST" | cut -f1) in $DEST"
