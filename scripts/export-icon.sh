#!/bin/zsh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Renders Vela/AppIcon.icon (the Icon Composer source of truth) into the
# flat images used outside the app: the README icon and the website's
# favicons, logo and home-page icon.
#
#   scripts/export-icon.sh
#
# Needs Xcode (for ictool) and cwebp (`brew install webp`). The app itself
# needs no export: Xcode compiles AppIcon.icon directly. To refresh the
# social card afterwards, run
# `website/scripts/screenshots.sh <path to Vela.app> og-image`.
set -euo pipefail

root=${0:A:h:h}
icon="$root/Vela/AppIcon.icon"
public="$root/website/public"
ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

[[ -x $ictool ]] || { echo "ictool not found at $ictool (needs Xcode 26 or later)" >&2; exit 1; }
command -v cwebp >/dev/null || { echo "cwebp not found. Install it with: brew install webp" >&2; exit 1; }

render() { # <size> <out.png>
  "$ictool" "$icon" --export-image --output-file "$2" --platform macOS --rendition Default \
    --width "$1" --height "$1" --scale 1 >/dev/null
}
compose() { # <in.png> <out.png> <size> <mode>
  swift "$root/scripts/icon-compose.swift" "$@"
}

render 1024 "$work/full-1024.png"
render 32 "$work/full-32.png"
render 16 "$work/full-16.png"

# README and social card: the macOS grid, like the icon in Finder.
compose "$work/full-1024.png" "$root/docs/vela-icon.png" 512 padded

# Website.
compose "$work/full-1024.png" "$work/vela-icon.png" 512 padded
cwebp -quiet -q 90 -m 6 -sharp_yuv -alpha_q 100 "$work/vela-icon.png" -o "$public/vela-icon.webp"
compose "$work/full-1024.png" "$public/logo.png" 128 padded
compose "$work/full-1024.png" "$public/apple-touch-icon.png" 180 opaque
# Favicons are rendered at their real size by ictool (it hints small sizes)
# rather than downscaled.
compose "$work/full-32.png" "$public/favicon-32x32.png" 32 tight
compose "$work/full-16.png" "$public/favicon-16x16.png" 16 tight
sips -s format ico "$public/favicon-32x32.png" --out "$public/favicon.ico" >/dev/null

for f in "$root/docs/vela-icon.png" "$public"/{vela-icon.webp,logo.png,apple-touch-icon.png,favicon-32x32.png,favicon-16x16.png,favicon.ico}; do
  printf '%-24s %s\n' "${f:t}" "$(du -h "$f" | cut -f1)"
done
