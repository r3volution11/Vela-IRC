#!/bin/zsh
# Builds a signed, notarized, stapled Vela.dmg ready for a GitHub release.
#
#   scripts/release.sh --preflight          # only the release checks; builds no release
#   scripts/release.sh                      # Developer ID sign + notarize + staple
#   scripts/release.sh --skip-notarize      # sign only (for testing the pipeline)
#   scripts/release.sh --adhoc              # no Developer ID at all (local testing)
#
# Before archiving (after the quick certificate checks), it runs the preflight
# checks (scripts/release-preflight.sh): git, version and changelog, CI, the
# adult-domain list, generated files, the package tests, the website, the
# media sites (scripts/check-media-sites.sh) and the scroll benchmark
# (scripts/benchmark-scroll.sh). If one fails, no release is built. Once the DMG is made, notarized and stapled, scripts/verify-release.sh
# checks the app inside it, and a failure there stops the release too. A
# summary of every check ends the output. See docs/RELEASING.md,
# "Release checks", for what each check needs.
#
# Options:
#   --preflight          Run only the preflight checks, and build no release.
#   --skip-notarize      Sign, but don't notarize (for testing the pipeline).
#   --adhoc              No Developer ID at all (local testing). Skips the git,
#                        version and CI checks, the media check and the scroll
#                        benchmark.
#   --allow-dirty        Let uncommitted changes through (for testing).
#   --skip-tests         Don't run the package tests.
#   --skip-ci-check      Don't ask GitHub whether CI passed.
#   --skip-media-check   Don't check the media sites (say, a site is down for an afternoon).
#   --media-check        Check them even with --adhoc, which otherwise skips it.
#   --skip-scroll-benchmark  Don't run the scroll benchmark (it takes about 12
#                        minutes).
#   --scroll-benchmark   Run it even with --adhoc, which otherwise skips it.
#   --skip-preflight     Skip every preflight check. Only for emergencies, and
#                        for dry runs you won't ship.
#
# Requirements (one-time, see docs/RELEASING.md):
#   • A "Developer ID Application" certificate in your login keychain
#   • Notarization credentials stored as the "vela-notary" profile, from an
#     App Store Connect API team key (recommended) or an app-specific password:
#       xcrun notarytool store-credentials vela-notary --key AuthKey_….p8 --key-id … --issuer …
#       xcrun notarytool store-credentials vela-notary --apple-id … --team-id …
#
# Environment overrides:
#   VELA_TEAM_ID         Apple Developer Team ID (auto-detected from the certificate)
#   VELA_NOTARY_PROFILE  notarytool keychain profile (default: vela-notary)
#
# Output: build/release/Vela.dmg and build/release/Vela-<version>.dmg (+ SHA256SUMS)
set -euo pipefail
cd "${0:A:h}/.."
source scripts/lib/release-checks.zsh

notarize=1
adhoc=0
preflight_only=0
skip_preflight=0
allow_dirty=0
preflight_options=()
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) notarize=0 ;;
    --adhoc) adhoc=1; notarize=0 ;;
    --preflight) preflight_only=1 ;;
    --skip-preflight) skip_preflight=1 ;;
    --allow-dirty) allow_dirty=1; preflight_options+=("$arg") ;;
    --skip-tests|--skip-ci-check|--skip-media-check|--media-check|--skip-scroll-benchmark|--scroll-benchmark) preflight_options+=("$arg") ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
if (( preflight_only && skip_preflight )); then
  echo "--preflight and --skip-preflight don't go together." >&2
  exit 2
fi
# An ad hoc build is for trying things on this Mac, not for shipping: the
# preflight skips the git, version, CI and media checks and the scroll benchmark.
if (( adhoc )); then
  preflight_options+=(--adhoc)
fi

profile="${VELA_NOTARY_PROFILE:-vela-notary}"
out="build/release"
project=Vela.xcodeproj/project.pbxproj
version=$(vela_setting "$project" Release MARKETING_VERSION) || version=""
build_number=$(vela_setting "$project" Release CURRENT_PROJECT_VERSION) || build_number=""
fail() { print -P "%F{red}error:%f $1" >&2; exit 1; }
[[ -n "$version" && -n "$build_number" ]] \
  || fail "Couldn't read MARKETING_VERSION and CURRENT_PROJECT_VERSION of the Vela target's Release configuration in $project."

# Every check's result, for the summary printed once, when the script ends
# (however it ends) or just before it stops on a failed check.
results=$(mktemp -t vela-release-checks)
show_summary() {
  [[ -f "$results" ]] || return 0
  print_check_summary "$results"
  rm -f "$results"
  if (( skip_preflight )); then
    print -P "%F{red}%B    This run skipped every preflight check (--skip-preflight).%b%f"
  fi
}
trap show_summary EXIT

step "Vela $version ($build_number)"

if (( preflight_only )); then
  if scripts/release-preflight.sh "${preflight_options[@]}" --results "$results"; then
    show_summary
    print
    if (( adhoc )); then
      print -P "%F{green}✓ The checks for an ad hoc build passed (git, version and CI aren't checked for one).%f"
    else
      print -P "%F{green}✓ Ready to release Vela $version ($build_number): run scripts/release.sh.%f"
    fi
    exit 0
  fi
  show_summary
  print
  print -P "%F{red}✗ Not ready to release Vela $version ($build_number). Fix the failed checks, then run scripts/release.sh --preflight again.%f"
  exit 1
fi

if (( skip_preflight || adhoc || allow_dirty )) && [[ -n "$(git status --porcelain)" ]]; then
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
      || fail "Notarization profile \"$profile\" not found. Store one with an App Store Connect API team key: xcrun notarytool store-credentials $profile --key <AuthKey_….p8> --key-id <key id> --issuer <issuer id> (or --apple-id <email> --team-id $team with an app-specific password). See docs/RELEASING.md."
  fi
fi

# ---------------------------------------------------------------- preflight
# Git, version and changelog, CI, the adult-domain list, generated files, the
# tests, the website, the media sites and the scroll benchmark (docs/RELEASING.md,
# "Release checks").
if (( skip_preflight )); then
  print
  print -P "%F{red}%B!!! --skip-preflight: NONE of the release checks run. !!!%b%f"
  print -P "%F{red}    Nothing checks the branch, a clean and pushed tree, the version, the changelog, CI,%f"
  print -P "%F{red}    the adult-domain list, the generated files, the tests, the website, the media sites%f"
  print -P "%F{red}    or the scroll benchmark.%f"
  print -P "%F{red}    Use it only in an emergency or for a build you won't ship. After an emergency release,%f"
  print -P "%F{red}    run scripts/release.sh --preflight as soon as you can.%f"
  print
  RELEASE_CHECKS_RESULTS="$results"
  check_section "Preflight"
  check_skip "Every preflight check" "--skip-preflight"
elif ! scripts/release-preflight.sh "${preflight_options[@]}" --results "$results"; then
  show_summary
  print
  fail "The preflight checks failed, so no release was built. Fix what the summary lists, then run scripts/release.sh again (docs/RELEASING.md, \"Release checks\")."
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

# ---------------------------------------------------------------- post-build checks
# The app inside the DMG, as users get it: identity, version, architectures,
# sandbox, signature, notarization (docs/RELEASING.md, "Release checks").
verify_options=(--version "$version" --build "$build_number" --results "$results")
if (( adhoc )); then
  verify_options+=(--adhoc)
elif (( ! notarize )); then
  verify_options+=(--skip-notarize)
fi
if [[ -n "$team" ]]; then
  verify_options+=(--team "$team")
fi
if ! scripts/verify-release.sh "$out/Vela.dmg" "${verify_options[@]}"; then
  show_summary
  print
  fail "$out/Vela.dmg failed the post-build checks, so it wasn't copied to Vela-$version.dmg or added to SHA256SUMS. Fix what the summary lists, then build again."
fi

cp "$out/Vela.dmg" "$out/Vela-$version.dmg"
(cd "$out" && shasum -a 256 Vela.dmg "Vela-$version.dmg" > SHA256SUMS)
step "Done"
print "    $out/Vela.dmg"
print "    $out/Vela-$version.dmg"
sed 's/^/    /' "$out/SHA256SUMS"
