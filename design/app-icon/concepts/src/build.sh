#!/bin/zsh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Rebuilds every concept in design/app-icon/concepts from concepts.py:
# the .icon documents and flat SVGs, then ictool renders, the per-concept
# PNGs, the contact sheet and the alternates sheet.
#
#   design/app-icon/concepts/src/build.sh
#
# Needs Xcode 26+ (ictool). Touches nothing outside the concepts folder.
set -euo pipefail

src=${0:A:h}
out=${src:h}
finalists=${FINALISTS:-ADE}
ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
work=$(mktemp -d -t vela-concepts)
trap 'rm -rf "$work"' EXIT

FINALISTS=$finalists python3 -I "$src/concepts.py" "$out" >/dev/null
swiftc -O -o "$work/compose" "$src/compose.swift" 2>/dev/null
compose() { "$work/compose" "$@" }

render() { # <icon> <out.png> <rendition> <size>
  local extra=()
  [[ $3 == Tinted* ]] && extra=(--tint-color 0.6 --tint-strength 0.75)
  "$ictool" "$1" --export-image --output-file "$2" --platform macOS --rendition "$3" \
    --width "$4" --height "$4" --scale 1 "${extra[@]}" >/dev/null
}

# Real-size icons: the body is rendered by ictool at its true pixel size
# (824/1024 of the canvas, rounded) and placed on the pixel grid.
smalls() { # <icon> <prefix>
  local s b i
  for s b i in 16 13 1  32 26 3  64 52 6; do
    render "$1" "$work/body-$b.png" Default $b
    compose small "$work/body-$b.png" "$2-$s.png" $s $i
  done
}

contact=()
for dir in "$out"/[A-F]-*(/); do
  id=${dir:t}; icon="$dir/$id.icon"
  title=$(python3 -I -c "import json,sys; print([m['title'] for m in json.load(open(sys.argv[1])) if m['id']==sys.argv[2]][0])" "$src/manifest.json" "$id")
  render "$icon" "$work/$id-full.png" Default 1024
  compose pad "$work/$id-full.png" "$dir/$id-1024.png" 1024
  smalls "$icon" "$dir/$id"
  compose legibility "$dir/$id-legibility.png" "${id[1]} $title" "$dir/$id-64.png" "$dir/$id-32.png" "$dir/$id-16.png"
  modes=()
  for r in Default Dark ClearLight ClearDark TintedLight TintedDark; do
    render "$icon" "$work/$id-$r.png" $r 512
    label=${r/Light/ (light)}; label=${label/Dark/ (dark)}; [[ $r == Dark ]] && label=Dark
    modes+=("$label=$work/$id-$r.png")
  done
  compose modes "$dir/$id-appearances.png" "${id[1]} $title" "${modes[@]}"
  contact+=("{\"letter\":\"${id[1]}\",\"title\":\"$title\",\"big\":\"$work/$id-full.png\",\"s32\":\"$dir/$id-32.png\",\"s16\":\"$dir/$id-16.png\"}")
  echo "rendered $id"
done
print -r -- "[${(j:,:)contact}]" > "$work/contact.json"
compose contact "$out/contact-sheet.png" "$work/contact.json"

# Alternates for the finalists
rows=()
for dir in "$out"/alternates/*(/N); do
  id=${dir:t}
  [[ $finalists == *${id[1]}* ]] || continue
  title=$(python3 -I -c "import json,sys; print([m['title'] for m in json.load(open(sys.argv[1])) if m['id']==sys.argv[2]][0])" "$src/manifest.json" "$id")
  items=()
  for cw in vela midnight sunrise graphite paper vivid; do
    name="$id-$cw"; icon="$dir/$name.icon"
    render "$icon" "$work/$name-full.png" Default 1024
    compose pad "$work/$name-full.png" "$dir/$name-1024.png" 1024
    render "$icon" "$work/$name-b26.png" Default 26
    compose small "$work/$name-b26.png" "$dir/$name-32.png" 32 3
    label=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$src/colorways.json" $cw)
    items+=("{\"label\":\"$label\",\"big\":\"$work/$name-full.png\",\"s32\":\"$dir/$name-32.png\"}")
  done
  rows+=("{\"title\":\"${id[1]}  $title\",\"items\":[${(j:,:)items}]}")
  echo "rendered alternates for $id"
done
if (( ${#rows} )); then
  print -r -- "{\"rows\":[${(j:,:)rows}]}" > "$work/alternates.json"
  compose alternates "$out/alternates-sheet.png" "$work/alternates.json"
fi
echo "done: $out"
