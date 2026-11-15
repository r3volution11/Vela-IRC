#!/bin/zsh
# Renders Vela's main window in demo mode to a PNG and quits. The window is
# hosted offscreen and stays invisible; no screen-recording permission needed.
#
#   scripts/demo-screenshot.sh <Vela.app> <out.png> [demo args…]
#   scripts/demo-screenshot.sh build/Vela.app shot.png --theme Lighter --preset tabbed --size 1280x800
#
# Demo args: --theme <name>, --preset classic|modern|tabbed|focus,
#            --set key=value (any settings.json key), --size WxH,
#            --snapshot-delay <seconds> (default 3; raise it for remote images)
set -euo pipefail
app="${1:A}"; out="${2:A}"; shift 2
rm -f "$out"
# The app is sandboxed, so it writes into its container's tmp and we copy out.
container_tmp="$HOME/Library/Containers/io.github.r3volution11.Vela/Data/tmp"
mkdir -p "$container_tmp"
tmp_out="$container_tmp/snapshot-$$.png"
"$app/Contents/MacOS/Vela" --demo --snapshot "$tmp_out" "$@" >/dev/null 2>&1 || true
if [[ -f "$tmp_out" ]]; then mv "$tmp_out" "$out"; echo "$out"; else echo "snapshot failed" >&2; exit 1; fi
