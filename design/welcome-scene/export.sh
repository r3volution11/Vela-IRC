#!/bin/zsh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Exports the welcome screen's picture from the app's own drawing code
# (Packages/VelaKit/Sources/VelaUI/Welcome), as PNG and SVG:
#
#   vela-welcome-night.png, .svg     Palenight (dark themes get night)
#   vela-welcome-day.png, .svg       Lighter (light themes get day)
#   themes/vela-welcome-<night|day>-<theme id>.png, .svg
#                                    every built-in theme
#
# Each is 1600 × 1013 points: the SVG at that size, the PNG at 2× (3200 ×
# 2026 pixels). The edges fade to transparent, as in the app.
#
#   design/welcome-scene/export.sh          # into design/welcome-scene/exports
#   design/welcome-scene/export.sh <dir>    # into <dir>
#
# It runs the WelcomeSceneExport test, which writes the files when
# VELA_WELCOME_EXPORT names a folder. exports/ is git-ignored.
set -euo pipefail

here=${0:A:h}
root=${here:h:h}
out=${1:-$here/exports}
mkdir -p "$out"
out=${out:A}

VELA_WELCOME_EXPORT=$out swift test --package-path "$root/Packages/VelaKit" --filter WelcomeSceneExport
print "Wrote the welcome scene to $out"
