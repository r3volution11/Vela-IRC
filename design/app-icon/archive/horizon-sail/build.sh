#!/bin/zsh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# ARCHIVED: Vela's app icon until November 2026 ("Horizon Sail"). The app
# now uses "Glint" (design/app-icon/README.md). This regenerates the artwork
# inside the archived copy, design/app-icon/archive/horizon-sail/AppIcon.icon,
# from params.json, then renders previews of every appearance. It no longer
# touches Vela/AppIcon.icon.
#
#   design/app-icon/archive/horizon-sail/build.sh          # previews in a temp folder
#   design/app-icon/archive/horizon-sail/build.sh <dir>    # previews in <dir>
#
# icon.json (layers, glass, shadows, appearance variants) is edited by hand
# or in Icon Composer.
set -euo pipefail

here=${0:A:h}
icon="$here/AppIcon.icon"
assets="$icon/Assets"
ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
previews=${1:-$(mktemp -d -t vela-icon)}
mkdir -p "$previews"

python3 -I "$here/gen/sails.py" "$assets" "$here/params.json"
swift "$here/gen/space.swift" "$assets/space.png" default "$here/gen/derived.json"
swift "$here/gen/space.swift" "$assets/space-dark.png" dark "$here/gen/derived.json"

render() { # <file> <rendition> <size> [extra ictool args]
  "$ictool" "$icon" --export-image --output-file "$previews/$1" --platform macOS \
    --rendition "$2" --width "$3" --height "$3" --scale 1 "${@:4}" >/dev/null
}
render default-1024.png    Default    1024
render dark-1024.png       Dark       1024
render clear-light-512.png ClearLight 512
render clear-dark-512.png  ClearDark  512
render tinted-dark-512.png TintedDark 512 --tint-color 0.6 --tint-strength 0.75
render small-64.png        Default    64
render small-32.png        Default    32

echo "Previews (Display P3): $previews"
