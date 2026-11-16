#!/bin/zsh
# Builds Vela and launches it — no need to open Xcode.
#
#   scripts/run.sh            # build (Release) and launch Vela
#   scripts/run.sh --demo     # launch with offline sample content
#   scripts/run.sh --debug    # build the Debug configuration instead
#
# The built app is copied to build/Vela.app (ignored by git), so you can also
# drag it to /Applications or double-click it in Finder.
set -euo pipefail
cd "${0:A:h}/.."

configuration=Release
args=()
for arg in "$@"; do
  if [[ "$arg" == "--debug" ]]; then configuration=Debug; else args+=("$arg"); fi
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

# Quit a running copy so the fresh build is the one that opens.
pkill -f "$PWD/build/Vela.app/Contents/MacOS/Vela" 2>/dev/null && sleep 1 || true
rm -rf build/Vela.app
cp -R "$product" build/Vela.app
echo "Launching build/Vela.app"
open build/Vela.app --args "${args[@]}"
