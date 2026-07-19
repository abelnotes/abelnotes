#!/usr/bin/env bash
# Build a .deb package for AbelNotes (Linux desktop).
#
# Layout:
#   /usr/lib/abelnotes/              — Flutter bundle (binary + lib/ + data/)
#   /usr/bin/abelnotes               — wrapper symlink → /usr/lib/abelnotes/abelnotes
#   /usr/share/applications/abelnotes.desktop
#   /usr/share/icons/hicolor/{512x512,192x192}/apps/abelnotes.png
#
# The Flutter binary's RUNPATH is `$ORIGIN/lib`, so it finds its bundled
# .so files relative to itself — no LD_LIBRARY_PATH wrapper needed.
#
# Usage:
#   ./tool/build_deb.sh            # build using existing release bundle
#   ./tool/build_deb.sh --rebuild  # `flutter build linux --release` first

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

REBUILD=0
[[ "${1:-}" == "--rebuild" ]] && REBUILD=1

# Version composition:
#   pubspec.yaml `version: 0.36.9+38`     → upstream 0.36.9, revision 38
#   built suffix `+<UTC-timestamp>.g<sha>` → makes every rebuild unique AND
#                                            monotonically greater than the
#                                            previous one (timestamp leads)
#   `.dirty` appended when working tree has uncommitted changes
#
# Result example: `0.36.9-38+20260518T091530Z.g3579e86`
# dpkg --compare-versions orders these correctly (digit-grouped lexicographic).
PUBSPEC_VER=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
VER_BASE=${PUBSPEC_VER%+*}
VER_BUILD=${PUBSPEC_VER#*+}
BUILD_TS=$(date -u +%Y%m%dT%H%M%SZ)
GIT_SHA=$(git rev-parse --short=7 HEAD 2>/dev/null || echo "nogit")
DIRTY_TAG=""
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  DIRTY_TAG=".dirty"
fi
DEB_VER="${VER_BASE}-${VER_BUILD}+${BUILD_TS}.g${GIT_SHA}${DIRTY_TAG}"
ARCH="amd64"
PKG="abelnotes_${DEB_VER}_${ARCH}"

BUNDLE="${PROJECT_ROOT}/build/linux/x64/release/bundle"

if (( REBUILD )) || [[ ! -x "${BUNDLE}/abelnotes" ]]; then
  echo "→ flutter build linux --release"
  flutter build linux --release
fi

STAGE="${PROJECT_ROOT}/build/deb/${PKG}"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/DEBIAN"
mkdir -p "${STAGE}/usr/lib/abelnotes"
mkdir -p "${STAGE}/usr/bin"
mkdir -p "${STAGE}/usr/share/applications"
mkdir -p "${STAGE}/usr/share/icons/hicolor/512x512/apps"
mkdir -p "${STAGE}/usr/share/icons/hicolor/192x192/apps"

echo "→ Staging bundle"
cp -r "${BUNDLE}/abelnotes" "${BUNDLE}/lib" "${BUNDLE}/data" "${STAGE}/usr/lib/abelnotes/"
ln -sf "/usr/lib/abelnotes/abelnotes" "${STAGE}/usr/bin/abelnotes"

echo "→ Icons"
cp "${PROJECT_ROOT}/web/icons/Icon-512.png" \
   "${STAGE}/usr/share/icons/hicolor/512x512/apps/abelnotes.png"
cp "${PROJECT_ROOT}/web/icons/Icon-192.png" \
   "${STAGE}/usr/share/icons/hicolor/192x192/apps/abelnotes.png"

echo "→ .desktop"
cat > "${STAGE}/usr/share/applications/abelnotes.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=AbelNotes
Comment=Handwriting note-taking app with Nextcloud sync
Exec=abelnotes %F
Icon=abelnotes
Categories=Office;Graphics;
StartupNotify=true
Terminal=false
EOF

# Compute installed size (KB).
INSTALLED_SIZE=$(du -sk "${STAGE}/usr" | awk '{print $1}')

echo "→ DEBIAN/control"
cat > "${STAGE}/DEBIAN/control" <<EOF
Package: abelnotes
Version: ${DEB_VER}
Section: graphics
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${INSTALLED_SIZE}
Depends: libc6, libstdc++6, libgtk-3-0t64 | libgtk-3-0, libsecret-1-0, libsqlite3-0
Recommends: poppler-utils
Maintainer: AbelNotes <noreply@abelnotes.app>
Description: Handwriting note-taking app with Nextcloud sync
 AbelNotes is a desktop handwriting note-taking application with
 PDF import, multi-page notebooks, and bidirectional sync to a
 Nextcloud server via WebDAV. Optimised for stylus input on Linux.
EOF

cat > "${STAGE}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q /usr/share/icons/hicolor || true
fi
exit 0
EOF
chmod 0755 "${STAGE}/DEBIAN/postinst"

echo "→ dpkg-deb --build"
mkdir -p "${PROJECT_ROOT}/build/deb"
fakeroot dpkg-deb --build "${STAGE}" "${PROJECT_ROOT}/build/deb/${PKG}.deb"

echo ""
echo "═══ Done ═══"
ls -lh "${PROJECT_ROOT}/build/deb/${PKG}.deb"
echo ""
echo "Install:    sudo apt install ./build/deb/${PKG}.deb"
echo "Uninstall:  sudo apt remove abelnotes"
