#!/bin/zsh
# Builds Vela and launches it — no need to open Xcode.
#
#   scripts/run.sh            # build (Release) and launch Vela
#   scripts/run.sh --demo     # launch with offline sample content
#   scripts/run.sh --dev      # build and launch "Vela Dev" (Debug) instead
#
# Release builds are copied to build/Vela.app; --dev builds to
# build/Vela Dev.app (both ignored by git), so you can also drag them to
# /Applications or double-click them in Finder.
#
# "Vela Dev" (bundle id io.github.r3volution11.Vela.dev) is a separate app:
# its own settings, networks, history, Keychain items, Siri/Shortcuts and
# Dock icon (badged DEV). It runs side by side with your everyday Vela and
# never touches its data. --debug is an alias for --dev.
set -euo pipefail
cd "${0:A:h}/.."

configuration=Release
args=()
for arg in "$@"; do
  if [[ "$arg" == "--debug" || "$arg" == "--dev" ]]; then configuration=Debug; else args+=("$arg"); fi
done

echo "Building Vela ($configuration)…"
xcodebuild \
  -project Vela.xcodeproj \
  -scheme Vela \
  -configuration "$configuration" \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  -quiet \
  build 2>&1 | grep -vE "CoreSimulator|appintentsmetadataprocessor|^$" || true

product="build/DerivedData/Build/Products/$configuration/Vela.app"
if [[ ! -d "$product" ]]; then
  echo "Build failed — see the output above." >&2
  exit 1
fi

if [[ "$configuration" == "Debug" ]]; then
  installed="build/Vela Dev.app"
else
  installed="build/Vela.app"
fi

# Quit a running copy of this build so the fresh one is what opens. The
# other build (release or dev) keeps running.
pkill -f "$PWD/$installed/Contents/MacOS/Vela" 2>/dev/null && sleep 1 || true
rm -rf "$installed"
cp -R "$product" "$installed"
echo "Launching $installed"
open "$installed" --args "${args[@]}"
