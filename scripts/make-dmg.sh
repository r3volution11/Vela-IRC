#!/bin/zsh
# Makes Vela's disk image: Vela.app and an Applications shortcut in a window
# that looks like velairc.app in dark mode (scripts/dmg/).
#
#   scripts/make-dmg.sh <Vela.app> <out.dmg> [volume name]
#   scripts/make-dmg.sh --prepare     # only install dmgbuild (release.sh does this first)
#
# scripts/release.sh runs it, then signs and notarizes the result. Run it by
# itself to try a change to the window: open the DMG it makes.
#
# The window's layout comes from dmgbuild (pinned, with hashes, in
# scripts/dmg/requirements.txt), installed on first use into build/dmg-venv.
# Nothing scripts Finder, and the image is built without appearing on screen.
set -euo pipefail

prepare_only=0
if [[ "${1:-}" == --prepare && $# -eq 1 ]]; then
  prepare_only=1
elif (( $# < 2 || $# > 3 )); then
  print -u2 "usage: scripts/make-dmg.sh <Vela.app> <out.dmg> [volume name]"
  print -u2 "       scripts/make-dmg.sh --prepare"
  exit 2
else
  app=${1:A}
  out=${2:A}
  volume_name=${3:-Vela}
fi
cd "${0:A:h}/.."

# dmgbuild needs Python 3.10 or later.
python=$(command -v python3 || true)
if [[ -z "$python" ]] || ! "$python" -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
  print -u2 "make-dmg: needs Python 3.10 or later as python3 (brew install python)."
  exit 1
fi

venv=build/dmg-venv
if [[ ! -x "$venv/bin/dmgbuild" ]] || ! cmp -s scripts/dmg/requirements.txt "$venv/requirements.txt"; then
  print "    Installing dmgbuild into $venv…"
  rm -rf "$venv"
  "$python" -m venv "$venv"
  "$venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes --only-binary :all: \
    -r scripts/dmg/requirements.txt
  cp scripts/dmg/requirements.txt "$venv/requirements.txt"
fi
(( prepare_only )) && exit 0

[[ -d "$app/Contents" ]] || { print -u2 "make-dmg: $app isn't an app."; exit 1; }
[[ -f "$app/Contents/Resources/AppIcon.icns" ]] || { print -u2 "make-dmg: $app has no AppIcon.icns."; exit 1; }

work=$(mktemp -d -t vela-dmg)
trap 'rm -rf "$work"' EXIT

# The background at 1x and 2x, joined so Retina screens get the sharp one.
swift scripts/dmg/background.swift scripts/dmg/layout.json "$work/background"
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$work/background.tiff" 2>/dev/null

rm -f "$out"
"$venv/bin/dmgbuild" -s scripts/dmg/settings.py \
  -D app="$app" -D background="$work/background.tiff" -D layout=scripts/dmg/layout.json \
  "$volume_name" "$out" > /dev/null 2> >(grep -v 'is deprecated' >&2)
print "    $out"
