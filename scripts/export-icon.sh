#!/bin/zsh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Renders Vela/AppIcon.icon (the Icon Composer source of truth) into the
# flat images used outside the app: the README icon and the website's logo,
# home-page icon and apple-touch-icon. Also writes the website's favicons,
# which are Glint's V and star without the tile, from the geometry in
# design/app-icon/concepts/src/concepts.py (FAVICON):
#
#   favicon.svg        deep blue in light mode, cyan in dark mode
#   favicon-16x16.png, favicon-32x32.png, favicon.ico (16, 32 and 48 px)
#                      for browsers without SVG favicons, in one mid blue
#                      that reads on light and dark tabs
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
compose() { # <in.png or in.svg> <out.png> <size> <mode>
  swift "$root/scripts/icon-compose.swift" "$@"
}

render 1024 "$work/full-1024.png"

# README and social card: the macOS grid, like the icon in Finder.
compose "$work/full-1024.png" "$root/docs/vela-icon.png" 512 padded

# Website.
compose "$work/full-1024.png" "$work/vela-icon.png" 512 padded
cwebp -quiet -q 90 -m 6 -sharp_yuv -alpha_q 100 "$work/vela-icon.png" -o "$public/vela-icon.webp"
compose "$work/full-1024.png" "$public/logo.png" 128 padded
compose "$work/full-1024.png" "$public/apple-touch-icon.png" 180 opaque

# Favicons: the mark alone, no tile. The SVG follows the browser's light or
# dark mode; the PNGs and ICO can't, so they're rendered from the flat
# version at their real sizes rather than downscaled.
python3 -I -B "$root/design/app-icon/concepts/src/concepts.py" --favicon "$public/favicon.svg" "$work/favicon-flat.svg"
for s in 16 32 48; do
  compose "$work/favicon-flat.svg" "$work/favicon-$s.png" $s tight
done
cp "$work/favicon-16.png" "$public/favicon-16x16.png"
cp "$work/favicon-32.png" "$public/favicon-32x32.png"
# favicon.ico: all three sizes, each stored as a PNG.
python3 -I -B - "$public/favicon.ico" "$work"/favicon-{16,32,48}.png <<'EOF'
import struct, sys
out, images = sys.argv[1], [open(p, "rb").read() for p in sys.argv[2:]]
offset = 6 + 16 * len(images)
entries = b""
for png in images:
    width, height = struct.unpack(">II", png[16:24])
    entries += struct.pack("<BBBBHHII", width % 256, height % 256, 0, 0, 1, 32, len(png), offset)
    offset += len(png)
open(out, "wb").write(struct.pack("<HHH", 0, 1, len(images)) + entries + b"".join(images))
EOF

for f in "$root/docs/vela-icon.png" "$public"/{vela-icon.webp,logo.png,apple-touch-icon.png,favicon.svg,favicon-32x32.png,favicon-16x16.png,favicon.ico}; do
  printf '%-24s %s\n' "${f:t}" "$(du -h "$f" | cut -f1)"
done
