#!/usr/bin/env bash
# Builds discwriter_<version>_amd64.deb from the Linux release bundle.
#
# Run from the repo root after `flutter build linux --release`:
#
#     packaging/build_deb.sh [output-dir]        # default output-dir: dist/
#
# Needs the app icons (python3 tool/make_icon.py → assets/icon/) and
# dpkg-deb. Same layout as the other Dhiva Labs Linux .debs: a
# /usr/lib/<pkg> install prefix, a thin /usr/bin wrapper, and standard
# hicolor icon + .desktop registration.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT_DIR="${1:-dist}"
BUNDLE=build/linux/x64/release/bundle
ICON_DIR=assets/icon
ICON_SIZES="16 32 48 64 128 256 512"
VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"

[ -x "$BUNDLE/cd_writer" ] || {
  echo "error: $BUNDLE/cd_writer not found — run 'flutter build linux --release' first" >&2
  exit 1
}

for size in $ICON_SIZES; do
  [ -f "$ICON_DIR/discwriter_${size}.png" ] || {
    echo "error: $ICON_DIR/discwriter_${size}.png missing — run 'python3 tool/make_icon.py' first" >&2
    exit 1
  }
done

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
PKG="$STAGE/discwriter"

mkdir -p \
  "$PKG/DEBIAN" \
  "$PKG/usr/lib/discwriter" \
  "$PKG/usr/bin" \
  "$PKG/usr/share/applications" \
  "$PKG/usr/share/doc/discwriter"
for size in $ICON_SIZES; do
  mkdir -p "$PKG/usr/share/icons/hicolor/${size}x${size}/apps"
done

cp -r "$BUNDLE/." "$PKG/usr/lib/discwriter/"

cat > "$PKG/usr/bin/discwriter" <<'WRAPPER'
#!/bin/sh
exec /usr/lib/discwriter/cd_writer "$@"
WRAPPER

install -m 0644 packaging/com.dhivalabs.discwriter.desktop \
  "$PKG/usr/share/applications/com.dhivalabs.discwriter.desktop"

for size in $ICON_SIZES; do
  cp "$ICON_DIR/discwriter_${size}.png" \
     "$PKG/usr/share/icons/hicolor/${size}x${size}/apps/discwriter.png"
done

cat > "$PKG/usr/share/doc/discwriter/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: discwriter
Source: https://github.com/Dhiva-Labs/DiscWriter

Files: *
Copyright: $(date +%Y) Dhiva Labs
License: MIT
 See the LICENSE file at the project root (or
 https://opensource.org/license/mit) for the full license text.
COPYRIGHT

INSTALLED_SIZE="$(du -sk "$PKG/usr" | cut -f1)"
cat > "$PKG/DEBIAN/control" <<CONTROL
Package: discwriter
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Dhiva Labs <dhivakar1010@gmail.com>
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0t64 | libgtk-3-0, xorriso
Homepage: https://github.com/Dhiva-Labs/DiscWriter
Description: Burn CDs, DVDs and Blu-ray discs on Linux
 Disc Writer is a modern disc burner for the Linux desktop, driving the
 xorriso command-line tool. It builds data discs with a live capacity gauge
 and an exact pre-burn size check, appends sessions to open discs, verifies
 every burn (recorded MD5s for data discs, byte for byte for images), burns
 and saves ISO images, erases rewritable media and can simulate any job
 with the laser off.
CONTROL

# Normalize permissions — mkdir -p/cp inherit the caller's umask, which
# otherwise leaves group-writable dirs/files (lintian: non-standard-*-perm).
find "$PKG" -type d -exec chmod 0755 {} +
find "$PKG" -type f -exec chmod 0644 {} +
chmod 0755 "$PKG/usr/bin/discwriter" "$PKG/usr/lib/discwriter/cd_writer"

mkdir -p "$OUT_DIR"
DEB="$OUT_DIR/discwriter_${VERSION}_amd64.deb"
dpkg-deb --build --root-owner-group "$PKG" "$DEB" >/dev/null
echo "built $DEB"
