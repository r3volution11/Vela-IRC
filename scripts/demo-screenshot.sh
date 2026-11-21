#!/bin/zsh
# Renders Vela's main window (or a Settings pane) in demo mode to a PNG and
# quits. The window is hosted offscreen and stays invisible, and Vela opens
# hidden without taking the focus; no screen-recording permission needed.
#
#   scripts/demo-screenshot.sh <Vela.app> <out.png> [demo args…]
#   scripts/demo-screenshot.sh build/Vela.app shot.png --theme Lighter --preset tabbed --size 1280x800
#
# Demo args: --theme <name>, --preset classic|modern|tabbed|focus,
#            --set key=value (any settings.json key), --size WxH,
#            --snapshot-delay <seconds> (default 3; raise it for remote images),
#            --select <buffer> ("#swift" or "OFTC/#debian"), --catch-up,
#            --no-networks (no networks: the first launch's welcome screen),
#            --no-selection (the demo's networks with no conversation open),
#            --accent <name> (one of the theme's accent swatches, e.g. Cyan),
#            --settings-pane <pane> (presets, appearance, layout, messages,
#              media, networks, notifications, intelligence, updates,
#              advanced; renders the Settings window instead, 820x600
#              unless --size is given),
#            --settings-scroll <points> (scroll the pane down first),
#            --theme-editor <theme> (renders the Theme Editor started from
#              that theme, 760x680 unless --size is given),
#            --themes-dir <folder> (theme files to offer, e.g. one with
#              "vibrancy"; copied in, so the folder is never changed)
#
# Demo mode never touches your real Themes folder: without --themes-dir it
# shows the built-in themes only.
set -euo pipefail
app="${1:A}"; out="${2:A}"; shift 2
rm -f "$out"
# The app is sandboxed, so it writes into its container's tmp and we copy out.
# Release builds are io.github.r3volution11.Vela; Debug ("Vela Dev") builds
# end in .dev and have their own container.
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || echo io.github.r3volution11.Vela)
container_tmp="$HOME/Library/Containers/$bundle_id/Data/tmp"
mkdir -p "$container_tmp"
tmp_out="$container_tmp/snapshot-$$.png"
# The sandbox can't read arbitrary folders, so --themes-dir is staged in the
# container's tmp first.
args=()
staged_themes=""
while (( $# )); do
  if [[ "$1" == --themes-dir && $# -ge 2 ]]; then
    staged_themes="$container_tmp/themes-$$"
    rm -rf "$staged_themes"; mkdir -p "$staged_themes"
    cp "${2:A}"/*.json(N) "${2:A}"/*.jsonc(N) "$staged_themes"/ 2>/dev/null || true
    args+=(--themes-dir "$staged_themes")
    shift 2
  else
    args+=("$1")
    shift
  fi
done
# Launched hidden (-j) and in the background (-g), as a new instance (-n)
# that this waits for (-W): running the binary directly would activate Vela
# and take the focus from whatever you're working in.
open -g -j -n -W -a "$app" --args --demo --snapshot "$tmp_out" "${args[@]}" >/dev/null 2>&1 || true
[[ -n "$staged_themes" ]] && rm -rf "$staged_themes"
if [[ -f "$tmp_out" ]]; then mv "$tmp_out" "$out"; echo "$out"; else echo "snapshot failed" >&2; exit 1; fi
