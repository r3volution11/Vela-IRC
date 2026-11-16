#!/bin/zsh
# Builds a signed, notarized, stapled Vela.dmg ready for a GitHub release.
#
#   scripts/release.sh                      # Developer ID sign + notarize + staple
#   scripts/release.sh --skip-notarize      # sign only (for testing the pipeline)
#   scripts/release.sh --adhoc              # no Developer ID at all (local testing)
#
# Requirements (one-time, see docs/RELEASING.md):
#   • A "Developer ID Application" certificate in your login keychain
#   • Notarization credentials stored with:
#       xcrun notarytool store-credentials vela-notary --apple-id … --team-id …
#
# Environment overrides:
#   VELA_TEAM_ID         Apple Developer Team ID (auto-detected from the certificate)
#   VELA_NOTARY_PROFILE  notarytool keychain profile (default: vela-notary)
#
# Output: build/release/Vela.dmg and build/release/Vela-<version>.dmg (+ .sha256)
set -euo pipefail
cd "${0:A:h}/.."

notarize=1
adhoc=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) notarize=0 ;;
    --adhoc) adhoc=1; notarize=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

profile="${VELA_NOTARY_PROFILE:-vela-notary}"
out="build/release"
version=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Vela.xcodeproj/project.pbxproj | head -1)
build_number=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \(.*\);/\1/p' Vela.xcodeproj/project.pbxproj | head -1)
step() { print -P "%F{magenta}==>%f %B$1%b"; }
fail() { print -P "%F{red}error:%f $1" >&2; exit 1; }

step "Vela $version ($build_number)"
if [[ -n "$(git status --porcelain)" ]]; then
  print -P "%F{yellow}warning:%f the working tree has uncommitted changes"
fi

# ---------------------------------------------------------------- signing setup
if (( adhoc )); then
  identity="-"
  team=""
else
  identity_line=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 || true)
  [[ -n "$identity_line" ]] || fail "No \"Developer ID Application\" certificate found. See docs/RELEASING.md, or use --adhoc."
  identity=$(echo "$identity_line" | sed -E 's/.*"(.*)"/\1/')
  team="${VELA_TEAM_ID:-$(echo "$identity" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')}"
  [[ -n "$team" ]] || fail "Couldn't determine the Team ID; set VELA_TEAM_ID."
  print "    identity: $identity"
  print "    team:     $team"
  if (( notarize )); then
    xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1 \
      || fail "Notarization profile \"$profile\" not found. Run: xcrun notarytool store-credentials $profile --apple-id <email> --team-id $team"
  fi
fi

rm -rf "$out"
mkdir -p "$out"

# ---------------------------------------------------------------- archive
step "Archiving (Release, universal)"
sign_settings=(CODE_SIGN_IDENTITY="$identity")
if (( ! adhoc )); then
  sign_settings+=(CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$team" OTHER_CODE_SIGN_FLAGS="--timestamp")
fi
xcodebuild archive \
  -project Vela.xcodeproj \
  -scheme Vela \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$out/Vela.xcarchive" \
  -derivedDataPath build/DerivedData-release \
  ONLY_ACTIVE_ARCH=NO \
  "${sign_settings[@]}" \
  -quiet 2>&1 | grep -vE "CoreSimulator|appintentsmetadataprocessor" || true
[[ -d "$out/Vela.xcarchive/Products/Applications/Vela.app" ]] || fail "Archive failed."

app="$out/Vela.app"
if (( adhoc )); then
  cp -R "$out/Vela.xcarchive/Products/Applications/Vela.app" "$app"
else
  step "Exporting with Developer ID"
  cat > "$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive \
    -archivePath "$out/Vela.xcarchive" \
    -exportOptionsPlist "$out/ExportOptions.plist" \
    -exportPath "$out/export" \
    -quiet
  cp -R "$out/export/Vela.app" "$app"
fi

step "Verifying the app signature"
codesign --verify --deep --strict --verbose=2 "$app"
lipo -archs "$app/Contents/MacOS/Vela" | sed 's/^/    architectures: /'
codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null \
  | grep -q "com.apple.security.app-sandbox" && print "    sandbox: on" || fail "App sandbox entitlement missing."

notarize_file() {
  local file="$1"
  step "Notarizing $(basename "$file") (this can take a few minutes)"
  local result
  result=$(xcrun notarytool submit "$file" --keychain-profile "$profile" --wait --output-format json)
  local submission_status submission_id
  submission_status=$(echo "$result" | plutil -extract status raw - 2>/dev/null || echo "unknown")
  submission_id=$(echo "$result" | plutil -extract id raw - 2>/dev/null || echo "")
  print "    status: $submission_status"
  if [[ "$submission_status" != "Accepted" ]]; then
    [[ -n "$submission_id" ]] && xcrun notarytool log "$submission_id" --keychain-profile "$profile" >&2
    fail "Notarization of $(basename "$file") was not accepted."
  fi
}

if (( notarize )); then
  # Notarize and staple the app itself, so it stays verifiable offline after
  # it's copied out of the disk image.
  ditto -c -k --keepParent "$app" "$out/Vela-notarize.zip"
  notarize_file "$out/Vela-notarize.zip"
  xcrun stapler staple "$app"
  rm -f "$out/Vela-notarize.zip"
fi

# ---------------------------------------------------------------- disk image
step "Creating the disk image"
staging="$out/dmg"
mkdir -p "$staging"
cp -R "$app" "$staging/Vela.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Vela $version" -srcfolder "$staging" -ov -format UDZO -fs APFS "$out/Vela.dmg" -quiet
rm -rf "$staging"
if (( ! adhoc )); then
  codesign --sign "$identity" --timestamp "$out/Vela.dmg"
fi

if (( notarize )); then
  notarize_file "$out/Vela.dmg"
  xcrun stapler staple "$out/Vela.dmg"
  step "Gatekeeper assessment"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$out/Vela.dmg"
  spctl --assess --type execute --verbose=2 "$app"
fi

cp "$out/Vela.dmg" "$out/Vela-$version.dmg"
(cd "$out" && shasum -a 256 Vela.dmg "Vela-$version.dmg" > SHA256SUMS)
step "Done"
print "    $out/Vela.dmg"
print "    $out/Vela-$version.dmg"
sed 's/^/    /' "$out/SHA256SUMS"
