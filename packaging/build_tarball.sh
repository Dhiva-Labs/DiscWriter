#!/usr/bin/env bash
# Builds discwriter-<version>-linux-<arch>.tar.gz, the portable bundle, from
# the Linux release bundle. <arch> is x64 or arm64, whichever machine this
# runs on. The archive holds one directory, discwriter-<version>/, with
# cd_writer, lib/ and data/ inside it.
#
# Run from the repo root after `flutter build linux --release`:
#
#     packaging/build_tarball.sh [output-dir]        # default output-dir: dist/
set -euo pipefail

cd "$(dirname "$0")/.."
OUT_DIR="${1:-dist}"
case "$(uname -m)" in
  x86_64) ARCH=x64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *)
    echo "error: unsupported machine '$(uname -m)' (x86_64 or aarch64)" >&2
    exit 1
    ;;
esac
BUNDLE="build/linux/$ARCH/release/bundle"
VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"

[ -x "$BUNDLE/cd_writer" ] || {
  echo "error: $BUNDLE/cd_writer not found — run 'flutter build linux --release' first" >&2
  exit 1
}

mkdir -p "$OUT_DIR"
TARBALL="$OUT_DIR/discwriter-${VERSION}-linux-${ARCH}.tar.gz"
tar -czf "$TARBALL" --owner=0 --group=0 --sort=name \
  --transform "s,^bundle,discwriter-${VERSION}," \
  -C "$(dirname "$BUNDLE")" bundle
echo "built $TARBALL"
