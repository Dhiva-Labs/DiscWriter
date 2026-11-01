#!/usr/bin/env bash
# Smoke run of an installed Disc Writer, shared by every Linux format CI
# builds besides the .deb: the .rpm on Fedora and openSUSE, the Arch package,
# the AppImage and the Flatpak.
#
# usage: smoke.sh <command that starts Disc Writer...>
#
# Run it on a virtual display whose framebuffer Xvfb mirrors into a file:
#
#   xvfb-run -a -s "-screen 0 1280x800x24 -fbdir $SMOKE_FB" \
#     dbus-run-session -- bash smoke.sh discwriter
#
# 1. Burns a data session with MD5s to a file-backed drive (stdio:) and
#    verifies it, with the same xorriso options the app uses for data discs
#    (lib/burn/commands.dart), so the xorriso this format gives the app
#    really burns. There is no optical drive on CI runners.
# 2. Starts Disc Writer with a logging xorriso shim first on PATH (the app
#    looks for xorriso on PATH) and passes once both of these hold:
#    - the screen shows a painted Flutter UI. The native GTK runner opens its
#      window before any Dart code runs, so a window alone proves nothing. A
#      Flutter UI paints hundreds of distinct colours; a runner whose Dart
#      snapshot did not start shows a handful. This is the colour count of
#      the .deb smoke run in ci.yml, read from Xvfb's framebuffer file
#      because the Flatpak builder image has no ImageMagick or xdotool.
#    - the app ran xorriso through the shim: the drive scan
#      (`xorriso -devices`) it starts on launch.
#
# Environment: SMOKE_FB (the -fbdir directory), HOME (a fresh directory),
# XORRISO (the real xorriso, as a path the app can run; default: the one on
# PATH), XORRISO_CMD (how to run xorriso from here, default "$XORRISO"; the
# Flatpak passes the xorriso inside its sandbox), SMOKE_SECONDS (default 120).
# The app command must run with PATH="$HOME/xorriso-shim:$PATH"; smoke.sh
# exports that, and the Flatpak passes it with --env.
set -euo pipefail
: "${SMOKE_FB:?set SMOKE_FB to the directory given to Xvfb -fbdir}"
[ $# -ge 1 ] || { echo "usage: $0 <command...>" >&2; exit 2; }
XORRISO="${XORRISO:-$(command -v xorriso)}"
read -r -a xorriso <<< "${XORRISO_CMD:-$XORRISO}"
secs="${SMOKE_SECONDS:-120}"
min_colours=200
log="$HOME/discwriter-smoke.log"

# 1. Burn and verify on a file-backed drive.
src="$HOME/smoke-src"
iso="$HOME/smoke-disc.iso"
rm -rf "$src" "$iso"
mkdir -p "$src/docs"
printf 'Disc Writer smoke test\n' > "$src/README.txt"
head -c 3000000 /dev/urandom > "$src/docs/random.bin"
"${xorriso[@]}" -md5 on -abort_on FAILURE -outdev "stdio:$iso" \
  -volid SMOKE -map "$src" / -commit
"${xorriso[@]}" -md5 on -abort_on FAILURE -indev "stdio:$iso" \
  -check_md5 FAILURE -- -find / -type f
echo "burned and verified a data session on stdio:$iso"

# 2. The app, with the shim first on PATH.
shim="$HOME/xorriso-shim"
calls="$HOME/xorriso-calls.log"
rm -rf "$shim" "$calls"
mkdir -p "$shim"
cat > "$shim/xorriso" <<EOF
#!/bin/sh
"$XORRISO" "\$@"
rc=\$?
echo "exit \$rc: xorriso \$*" >> "$calls"
exit \$rc
EOF
chmod +x "$shim/xorriso"
export PATH="$shim:$PATH"

# Distinct pixel values on the screen, from the XWD file Xvfb keeps up to
# date (big-endian header, then the colour map, then the pixels).
colours() {
  python3 - "$SMOKE_FB/Xvfb_screen0" <<'EOF'
import struct, sys
data = open(sys.argv[1], 'rb').read()
h = struct.unpack('>25I', data[:100])
header_size, width, height, bpp, bpl, ncolours = h[0], h[4], h[5], h[11], h[12], h[19]
start = header_size + ncolours * 12
step = bpp // 8
seen = set()
for y in range(height):
    row = data[start + y * bpl:start + y * bpl + width * step]
    if step == 4:
        seen.update(memoryview(row).cast('I'))
    else:
        seen.update(row[i:i + step] for i in range(0, len(row), step))
print(len(seen))
EOF
}

scanned() { [ -f "$calls" ] && grep -e ' -devices' "$calls" > /dev/null; }

"$@" > "$log" 2>&1 &
pid=$!
painted=0
ran=0
n=0
for i in $(seq 1 "$secs"); do
  kill -0 "$pid" 2> /dev/null || { echo "Disc Writer exited early"; cat "$log"; exit 1; }
  if [ "$painted" = 0 ]; then
    n="$(colours)"
    echo "screenshot ${i}: $n distinct colours"
    if [ "$n" -ge "$min_colours" ]; then painted=1; fi
  fi
  if [ "$ran" = 0 ] && scanned; then
    echo "Disc Writer ran xorriso after ${i}s"
    ran=1
  fi
  if [ "$painted" = 1 ] && [ "$ran" = 1 ]; then break; fi
  sleep 1
done
kill -0 "$pid" 2> /dev/null || { echo "Disc Writer died"; cat "$log"; exit 1; }
kill "$pid"
cat "$log"
echo "--- xorriso calls made by the app"
if [ -f "$calls" ]; then cat "$calls"; fi
ok=1
if [ "$painted" = 0 ]; then
  echo "the window never painted a Flutter UI ($n colours, need $min_colours)"
  ok=0
fi
if [ "$ran" = 0 ]; then
  echo "Disc Writer never ran xorriso -devices: it did not find xorriso"
  ok=0
fi
if grep -E 'error while loading shared libraries|cannot open shared object|undefined symbol' "$log"; then
  ok=0
fi
[ "$ok" = 1 ]
echo "Flutter UI painted ($n distinct colours) and the app ran xorriso"
