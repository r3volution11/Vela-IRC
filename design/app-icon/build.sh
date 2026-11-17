#!/bin/zsh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Rebuilds Vela's app icon, "Glint" (concept E in concepts/src/concepts.py):
#
#   Vela/AppIcon.icon     the Icon Composer document Xcode compiles into the
#                         app (the Vela colourway), with its Default, Dark,
#                         Clear and Tinted appearances
#   Packages/VelaKit/Sources/VelaUI/Resources/AppIcons/<colourway>.png
#                         the Dock icons for Settings → Appearance → Dock icon:
#                         flat 256 px renders on the macOS icon grid
#   website/public/screenshots/app-icons.webp, app-icons-light.webp
#                         the six icons in a row, for the website
#
# then renders previews of every appearance.
#
#   design/app-icon/build.sh          # previews in a temp folder
#   design/app-icon/build.sh <dir>    # previews in <dir>
#
# The geometry and palettes live in concepts/src/concepts.py (concept_glint
# and COLORWAYS). Afterwards, run scripts/export-icon.sh (README icon,
# website favicons and logo) and
# `website/scripts/screenshots.sh <path to Vela.app> og-image` (social card).
# Needs Xcode 26 or later (ictool).
set -euo pipefail

here=${0:A:h}
root=${here:h:h}
src="$here/concepts/src"
icon="$root/Vela/AppIcon.icon"
dock="$root/Packages/VelaKit/Sources/VelaUI/Resources/AppIcons"
ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
previews=${1:-$(mktemp -d -t vela-icon)}
work=$(mktemp -d -t vela-icon-work)
trap 'rm -rf "$work"' EXIT
mkdir -p "$previews" "$dock"

[[ -x $ictool ]] || { echo "ictool not found at $ictool (needs Xcode 26 or later)" >&2; exit 1; }
swiftc -O -o "$work/compose" "$src/compose.swift" 2>/dev/null

render() { # <icon> <out.png> <rendition> <size>
  local extra=()
  [[ $3 == Tinted* ]] && extra=(--tint-color 0.6 --tint-strength 0.75)
  "$ictool" "$1" --export-image --output-file "$2" --platform macOS --rendition "$3" \
    --width "$4" --height "$4" --scale 1 "${extra[@]}" >/dev/null
}

# The app icon.
python3 -I "$src/concepts.py" --icon E vela "$icon"

# Dock icons: every colourway, Vela included (the picker's thumbnail; the
# app itself restores the real icon for Vela). 256 px is the Dock's largest
# tile (128 pt) on a Retina display.
strip=()
for cw in vela midnight graphite sunrise paper vivid; do
  python3 -I "$src/concepts.py" --icon E $cw "$work/$cw.icon"
  render "$work/$cw.icon" "$work/$cw-full.png" Default 1024
  "$work/compose" pad "$work/$cw-full.png" "$dock/$cw.png" 256
  "$work/compose" pad "$work/$cw-full.png" "$work/$cw-512.png" 512
  strip+=("${(C)cw}=$work/$cw-512.png")
done

# The website's picture of the six (website/customize/app-icon.md), on a dark
# and a light desktop.
if command -v cwebp >/dev/null; then
  shots="$root/website/public/screenshots"
  for desk in dark light; do
    "$work/compose" strip "$work/strip-$desk.png" $desk "${strip[@]}"
    cwebp -quiet -q 90 -m 6 -sharp_yuv "$work/strip-$desk.png" \
      -o "$shots/app-icons${${desk:#dark}:+-$desk}.webp"
  done
else
  echo "cwebp not found (brew install webp): skipped the website's app-icons.webp" >&2
fi

# Previews (Display P3).
render "$icon" "$work/default-full.png" Default 1024
"$work/compose" pad "$work/default-full.png" "$previews/default-1024.png" 1024
modes=()
for r in Default Dark ClearLight ClearDark TintedLight TintedDark; do
  render "$icon" "$previews/${r:l}-512.png" $r 512
  label=${r/Light/ (light)}; label=${label/Dark/ (dark)}; [[ $r == Dark ]] && label=Dark
  modes+=("$label=$previews/${r:l}-512.png")
done
"$work/compose" modes "$previews/appearances.png" "Glint" "${modes[@]}"
for s b i in 16 13 1  32 26 3  64 52 6; do
  render "$icon" "$work/body-$b.png" Default $b
  "$work/compose" small "$work/body-$b.png" "$previews/small-$s.png" $s $i
done

echo "Vela/AppIcon.icon and $(ls "$dock" | wc -l | tr -d ' ') Dock icons written"
echo "Previews (Display P3): $previews"
