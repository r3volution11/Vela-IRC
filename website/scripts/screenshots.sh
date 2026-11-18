#!/bin/zsh
# Regenerates every screenshot on velairc.app from Vela's demo mode (the main
# window, or a Settings pane), plus the social card. Shots render offscreen (no screen-recording permission) with
# scripts/demo-screenshot.sh, then are downscaled with sips and encoded as WebP.
#
#   website/scripts/screenshots.sh                  # build Release, then shoot everything
#   website/scripts/screenshots.sh build/Vela.app   # use an existing build
#   website/scripts/screenshots.sh build/Vela.app theme-nord home-palenight
#                                                   # only the named shots
#
# Needs cwebp (`brew install webp`) and network access: the demo's #vela and
# #media channels show images, videos and link cards that load from the web.
set -euo pipefail

root="${0:A:h:h:h}"          # repository root
out="$root/website/public/screenshots"
public="$root/website/public"
work="$(mktemp -d -t vela-screenshots)"
trap 'rm -rf "$work"' EXIT

if ! command -v cwebp >/dev/null; then
  echo "cwebp not found. Install it with: brew install webp" >&2
  exit 1
fi

app="${1:-}"
[[ $# -gt 0 ]] && shift
only=("$@")

if [[ -z "$app" ]]; then
  echo "Building Vela (Release)…"
  xcodebuild -project "$root/Vela.xcodeproj" -scheme Vela -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$root/build/DerivedData" -quiet build \
    2>&1 | grep -vE "CoreSimulator|appintentsmetadataprocessor|^$" || true
  app="$root/build/DerivedData/Build/Products/Release/Vela.app"
fi
app="${app:A}"
[[ -x "$app/Contents/MacOS/Vela" ]] || { echo "No Vela app at $app" >&2; exit 1; }
mkdir -p "$out"

# shot <name> <window size> <output width> [demo args…]
# Shows #vela unless the demo args --select another buffer. Remote media in
# the demo needs a few seconds, hence --snapshot-delay 8.
shot() {
  local name=$1 size=$2 width=$3
  shift 3
  if (( ${#only} )) && (( ! ${only[(Ie)$name]} )); then return; fi
  local select=(--select "#vela")
  (( ${argv[(Ie)--select]} )) && select=()
  "$root/scripts/demo-screenshot.sh" "$app" "$work/$name.png" \
    --size "$size" --snapshot-delay 8 "${select[@]}" "$@" >/dev/null
  sips -Z "$width" "$work/$name.png" >/dev/null
  cwebp -quiet -q 82 -m 6 -sharp_yuv "$work/$name.png" -o "$out/$name.webp"
  printf '%-28s %s\n' "$name.webp" "$(du -h "$out/$name.webp" | cut -f1)"
}

# Home page: the hero in the default dark and light themes.
shot home-palenight 1400x900 1600 --theme Palenight --preset modern
shot home-lighter   1400x900 1600 --theme Lighter   --preset modern

# Presets, all in Palenight so they compare at a glance.
for preset in classic modern tabbed focus; do
  shot "preset-$preset" 1280x800 1400 --theme Palenight --preset "$preset"
done

# Message layouts (the grouped layout is preset-modern).
shot layout-classic 1280x800 1400 --theme Palenight --preset modern --set chat.layout=classic
shot layout-columns 1280x800 1400 --theme Palenight --preset modern --set chat.layout=columns
# Modern with each group's time at the right edge (chat.timestampPosition.grouped).
shot timestamps-right 1280x800 1400 --theme Palenight --preset modern --set chat.timestampPosition.grouped=right

# Tab stacks: placements and roundness (top + 0.5 is preset-tabbed).
shot tabs-title-bar 1280x800 1400 --theme Palenight --preset tabbed --set tabs.placement=titleBar
shot tabs-bottom    1280x800 1400 --theme Palenight --preset tabbed --set tabs.placement=bottom
shot tabs-square    1280x800 1400 --theme Palenight --preset tabbed --set tabs.roundness=0
shot tabs-pill      1280x800 1400 --theme Palenight --preset tabbed --set tabs.roundness=1

# The collapsed sidebar (rail).
shot sidebar-rail   1280x800 1400 --theme Palenight --preset modern --set sidebar.collapsed=true

# Inline media. media-compact is #vela with every preview at its smallest;
# the rest show the demo's #media channel (a Vimeo video, an ESO article and
# links to an adult and a blocked site) or its blurred #vela-offtopic.
shot media-compact        1280x800 1400 --theme Palenight --preset modern \
  --set media.linkPreviewSize=minimal --set media.videos=compact --set media.imageSize=thumbnail
shot media-link-standard  1280x800 1400 --theme Palenight --preset modern --select "#media"
shot media-link-large     1280x800 1400 --theme Palenight --preset modern --select "#media" \
  --set media.linkPreviewSize=large
shot media-videos-compact 1280x800 1400 --theme Palenight --preset modern --select "#media" \
  --set media.videos=compact
shot media-restrictions   1280x800 1400 --theme Palenight --preset modern --select "#media" \
  --set media.blurImages=true
shot media-blur           1280x800 1400 --theme Palenight --preset modern --select "#vela-offtopic" \
  --set 'translation.autoTranslate=[]'
# #macdev's two unread lines are GIFs from GIPHY and Tenor; open at the newest
# so both are in view. Each shows its first frame (the snapshot can't draw video).
shot media-gifs           1280x800 1400 --theme Palenight --preset modern --select "#macdev" \
  --set chat.openAt=newest

# Apple Intelligence: a Catch me up card (the demo's summaries are canned)
# and #vela-offtopic's Spanish, Japanese and German lines, translated.
shot ai-catch-up  1280x800 1400 --theme Palenight --preset modern --select "#swift" \
  --set intelligence.catchUpThreshold=1 --catch-up
shot ai-translate 1280x800 1400 --theme Palenight --preset modern --select "#vela-offtopic"

# A theme accent other than the default, in the main window.
shot accent-cyan  1280x800 1400 --theme Palenight --preset modern --accent Cyan

# Settings panes, 820 points wide; the heights crop each shot to whole
# sections. --settings-scroll scrolls the pane down first, and a large number
# scrolls to the end.
pane() {
  local name=$1 size=$2 pane=$3
  shift 3
  shot "$name" "$size" 1200 --theme Palenight --preset modern --settings-pane "$pane" "$@"
}
pane settings-intelligence 820x530 intelligence
pane settings-siri         820x620 intelligence --settings-scroll 9999
# Typing, Memory and History; Chat logs follows them at the end of the pane.
# Timestamps, with Position for the current layout (Modern) and Other layouts.
pane settings-timestamps   820x450 messages --settings-scroll 915
pane settings-typing       820x708 messages --settings-scroll 1944
pane settings-chat-logs    820x425 messages --settings-scroll 9999 --set logging.enabled=true
pane settings-accent       820x705 appearance --accent Cyan
# The last two rows of theme cards, drawn from each theme's colors, down to
# the end of "Make your own".
pane settings-themes       820x736 appearance --settings-scroll 1375
pane settings-app-icon     820x600 appearance --settings-scroll 9999 --set appearance.appIcon=sunrise
pane settings-dock         820x450 notifications --settings-scroll 262
# A theme file with typos (screenshot-themes/harbor.json, copied into the
# demo's own Themes folder): what Settings → Appearance says about it.
pane settings-theme-problems 820x438 appearance --themes-dir "$root/website/scripts/screenshot-themes" \
  --settings-scroll 2050

# The settings editor (Settings → Advanced): the UI view, filtered to
# @modified, and the JSON view of a small settings.json with a typo and a
# bad value. --settings-json-text saves the file first; the other
# --settings-json-* flags take a UTF-16 offset into the text (ASCII here).
pane settings-editor          820x660 advanced
pane settings-editor-modified 820x585 advanced --settings-search "@modified"
settings_json=$(cat <<'EOF'
// Comments and trailing commas are fine.
{
    // Always Palenight
    "appearance.theme": "Palenight",
    "appearance.followSystem": false,
    "appearance.messageBoxBorder": "accent",

    /* Messages */
    "chat.layout": "columns",
    "chat.fontSzie": 14,
    "chat.clock": "24-hour",
    "chat.timestampSeconds": true,

    // Three months is plenty
    "history.retentionDays": 90,
}
EOF
)
# The same file with a setting half typed, for the suggestions list.
settings_json_typing=${settings_json/'"chat.timestampSeconds": true,'/'"chat.timestampSeconds": true,
    "media.'}
offset() { local index=${1[(i)$2]}; print $(( index - 1 )) }   # where $2 starts in $1
json() {
  local name=$1 size=$2
  shift 2
  shot "$name" "$size" 1400 --theme Palenight --preset modern --settings-pane advanced \
    --settings-mode json --settings-json-text "$settings_json" "$@"
}
json settings-json          1040x620 --settings-json-defaults
json settings-json-complete 820x600 --settings-json-unsaved "$settings_json_typing" \
  --settings-json-complete $(( $(offset "$settings_json_typing" '"media.') + 7 ))
json settings-json-problems 820x540 --settings-json-problems \
  --settings-json-hover $(( $(offset "$settings_json" '"chat.fontSzie"') + 3 ))
json settings-json-hover    820x540 \
  --settings-json-hover $(( $(offset "$settings_json" '"history.retentionDays"') + 3 ))

# One shot per built-in theme, for the theme gallery.
themes=(
  palenight:Palenight lighter:Lighter oceanic:Oceanic darker:Darker ocean:Ocean
  deepforest:Deepforest volcano:Volcano sandy-beach:"Sandy Beach"
  vela-graphite:"Vela Graphite" vela-paper:"Vela Paper" vela-mist:"Vela Mist"
  dracula:Dracula nord:Nord catppuccin-latte:"Catppuccin Latte" catppuccin-mocha:"Catppuccin Mocha"
  tokyo-night:"Tokyo Night" one-dark:"One Dark" gruvbox-dark:"Gruvbox Dark"
  solarized-dark:"Solarized Dark" solarized-light:"Solarized Light" rose-pine:"Rosé Pine"
)
for entry in "${themes[@]}"; do
  shot "theme-${entry%%:*}" 1280x800 1200 --theme "${entry#*:}" --preset modern
done

# Social card (Open Graph / Twitter): the app icon, name and tagline beside the
# hero window, drawn by social-card.swift.
if (( ! ${#only} )) || (( ${only[(Ie)og-image]} )); then
  "$root/scripts/demo-screenshot.sh" "$app" "$work/og-shot.png" \
    --size 1400x900 --snapshot-delay 8 --select "#vela" --theme Palenight --preset modern >/dev/null
  swift "$root/website/scripts/social-card.swift" \
    "$root/docs/vela-icon.png" "$work/og-shot.png" "$work/og-image.png"
  sips -s format jpeg -s formatOptions 86 "$work/og-image.png" --out "$public/og-image.jpg" >/dev/null
  printf '%-28s %s\n' "og-image.jpg" "$(du -h "$public/og-image.jpg" | cut -f1)"
fi
