#!/bin/zsh
# Checks a built Vela disk image the way users get it. scripts/release.sh runs
# it on build/release/Vela.dmg once the DMG is made, notarized and stapled, and
# stops if a check fails. Run it on its own to check a DMG again, such as the
# one you downloaded from the release page.
#
#   scripts/verify-release.sh build/release/Vela.dmg
#   scripts/verify-release.sh ~/Downloads/Vela.dmg --version 0.2.0 --build 3
#
# It mounts the DMG read-only (out of sight, in a temporary folder), checks
# the Vela.app inside, and unmounts it:
#   • the bundle id is io.github.r3volution11.Vela (never the .dev one);
#   • CFBundleShortVersionString and CFBundleVersion are the version and build;
#   • it runs on Apple silicon and Intel (arm64 and x86_64);
#   • the App Sandbox entitlement is on;
#   • the updater (Sparkle) can work and is safe (check_update_support in
#     scripts/lib/sparkle.zsh): the mach-lookup exception for its installer
#     and no local-build exceptions; its Info.plist keys (the velairc.app
#     feed, daily checks, the installer service, no system profile); a real
#     public key in SUPublicEDKey, not the placeholder; Sparkle is the
#     pinned version, and its framework, XPC services and helpers are
#     signed (Developer ID, hardened runtime, timestamp);
#   • no GIF key, and no Private Cloud Compute (its Settings switch, its
#     mention in Siri's description of Catch Me Up, or the entitlement):
#     both are in development builds only for now;
#   • its App Intents metadata has every App Shortcut, Catch Me Up and Open
#     Channel, and the VelaIntents package (check_app_intents in
#     scripts/lib/release-checks.zsh);
#   • codesign --verify --deep --strict passes;
#   • it's signed with a Developer ID Application certificate (of --team, if
#     given), with a secure timestamp;
#   • Gatekeeper (spctl) accepts it as "Notarized Developer ID";
#   • the notarization ticket is stapled to the app and to the DMG;
#   • the DMG has the Applications shortcut.
#
# Options:
#   --version <version>  The version to expect (default: MARKETING_VERSION of
#                        the Vela target's Release configuration).
#   --build <number>     The build number to expect (default: CURRENT_PROJECT_VERSION).
#   --team <id>          The Team ID to expect (default: VELA_TEAM_ID; with
#                        neither, any Developer ID team passes and is shown).
#   --skip-notarize      The build was signed but not notarized: skip the
#                        Gatekeeper and stapled-ticket checks.
#   --adhoc              An ad hoc build: also skip the Developer ID checks,
#                        allow the local entitlements, and only note a
#                        missing update key.
#   --results <file>     Append each result to <file> and leave the summary to
#                        the caller (scripts/release.sh).
#
# Exits 0 when every check that ran passed, 1 when one failed, 2 for a usage
# error.
set -euo pipefail
script="${0:A}"
cd "${0:A:h}/.."
source scripts/lib/release-checks.zsh
source scripts/lib/sparkle.zsh

usage() { sed -n '2,/^set -euo/p' "$script" | sed -e '$d' -e 's/^# \{0,1\}//'; }
needs_value() { [[ $# -ge 2 && -n "$2" ]] || { print -u2 -r -- "$1 needs a value"; exit 2; } }

bundle_id=io.github.r3volution11.Vela
dmg=""
version=""
build_number=""
team="${VELA_TEAM_ID:-}"
notarized=1
adhoc=0
results=""
while (( $# )); do
  case "$1" in
    --version) needs_value "$@"; version="$2"; shift 2 ;;
    --build) needs_value "$@"; build_number="$2"; shift 2 ;;
    --team) needs_value "$@"; team="$2"; shift 2 ;;
    --skip-notarize) notarized=0; shift ;;
    --adhoc) adhoc=1; notarized=0; shift ;;
    --results) needs_value "$@"; results="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) print -u2 -r -- "Unknown option: $1 (see --help)"; exit 2 ;;
    *) [[ -z "$dmg" ]] || { print -u2 "Give one disk image."; exit 2; }; dmg="$1"; shift ;;
  esac
done
[[ -n "$dmg" ]] || { usage >&2; exit 2; }
[[ -n "$version" ]] || version=$(vela_setting Vela.xcodeproj/project.pbxproj Release MARKETING_VERSION || true)
[[ -n "$build_number" ]] || build_number=$(vela_setting Vela.xcodeproj/project.pbxproj Release CURRENT_PROJECT_VERSION || true)

tmp=$(mktemp -d -t vela-verify)
mountpoint="$tmp/volume"
mounted=0
cleanup() {
  if (( mounted )); then
    hdiutil detach "$mountpoint" -quiet 2>/dev/null || hdiutil detach "$mountpoint" -force -quiet 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

if [[ -n "$results" ]]; then
  RELEASE_CHECKS_RESULTS="$results"
else
  RELEASE_CHECKS_RESULTS="$tmp/results"
fi
: >> "$RELEASE_CHECKS_RESULTS"

finish() {
  [[ -n "$results" ]] || print_check_summary "$RELEASE_CHECKS_RESULTS"
  if (( release_checks_failed )); then
    print -P "%F{red}✗ $release_checks_failed post-build check(s) failed for ${dmg:t}.%f"
    exit 1
  fi
  print -P "%F{green}✓ ${dmg:t} passed the post-build checks.%f"
  exit 0
}

check_section "Post-build checks"
mkdir -p "$mountpoint"
if [[ ! -f "$dmg" ]]; then
  check_fail "Disk image" "$dmg doesn't exist" "Build it with scripts/release.sh."
  finish
fi
if attach_output=$(hdiutil attach "$dmg" -readonly -nobrowse -noautoopen -mountpoint "$mountpoint" 2>&1); then
  mounted=1
  check_pass "Disk image" "mounts read-only"
else
  check_fail "Disk image" "hdiutil couldn't mount it: ${attach_output//$'\n'/ }" "Rebuild it with scripts/release.sh."
  finish
fi

app="$mountpoint/Vela.app"
if [[ ! -d "$app" ]]; then
  check_fail "Vela.app" "the disk image has no Vela.app" "Rebuild it with scripts/release.sh."
  finish
fi
# tidy <output>: a tool's output on one line, without "Processing: …" lines
# or the path of the temporary mount folder.
tidy() {
  local -a lines=("${(@f)1}")
  lines=("${(@)lines:#Processing:*}")
  local text="${(j: :)lines}"
  print -r -- "${text//$mountpoint\//}"
}
info="$app/Contents/Info.plist"
plist_value() { plutil -extract "$1" raw -o - "$info" 2>/dev/null || true; }

found=$(plist_value CFBundleIdentifier)
if [[ "$found" == "$bundle_id" ]]; then
  check_pass "Bundle id" "$found"
else
  check_fail "Bundle id" "${found:-none}, expected $bundle_id" \
    "Only the Release configuration has the release bundle id; build with scripts/release.sh, not a Debug build."
fi

found_version=$(plist_value CFBundleShortVersionString)
found_build=$(plist_value CFBundleVersion)
if [[ -z "$version" || -z "$build_number" ]]; then
  check_fail "Version" "no version or build number to expect" "Give --version and --build."
elif [[ "$found_version" == "$version" && "$found_build" == "$build_number" ]]; then
  check_pass "Version" "$found_version ($found_build)"
else
  check_fail "Version" "the app is ${found_version:-?} (${found_build:-?}), expected $version ($build_number)" \
    "Rebuild from the committed project (MARKETING_VERSION and CURRENT_PROJECT_VERSION in both configurations)."
fi

executable="$app/Contents/MacOS/$(plist_value CFBundleExecutable)"
archs=$(lipo -archs "$executable" 2>/dev/null || true)
if [[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]]; then
  check_pass "Architectures" "$archs"
else
  check_fail "Architectures" "${archs:-none found}, expected arm64 and x86_64" \
    "Archive with ONLY_ACTIVE_ARCH=NO for generic/platform=macOS, as scripts/release.sh does."
fi

entitlements="$tmp/entitlements.plist"
codesign -d --entitlements - --xml "$app" > "$entitlements" 2>/dev/null || true
sandbox=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements" 2>/dev/null || true)
if [[ "$sandbox" == true ]]; then
  check_pass "App Sandbox" "on"
else
  check_fail "App Sandbox" "the com.apple.security.app-sandbox entitlement is missing" \
    "Check that scripts/release.sh passes VELA_ENTITLEMENTS=Vela/Vela.entitlements."
fi

# Updates: entitlements, Info.plist keys, the public key and Sparkle's
# signatures (lib/sparkle.zsh). Sparkle's code must be signed by the app's
# own team.
app_team=$(codesign -dvv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -n 1 || true)
[[ $app_team == "not set" ]] && app_team=""
check_update_support "$app" "$entitlements" "$adhoc" "${team:-$app_team}"

# GIF search is only in development builds for now (GIFAvailability): a
# release carries no KLIPY key until KLIPY approves it for production.
klipy_key=$(plist_value VelaKLIPYAPIKey)
if [[ -z "$klipy_key" ]]; then
  check_pass "GIF key" "none (GIF search is in development builds only)"
else
  check_fail "GIF key" "Info.plist has VelaKLIPYAPIKey" \
    "Releases carry no GIF key yet: check Vela/Info.plist and the build settings (docs/RELEASING.md, \"The GIF key\")."
fi
unset klipy_key

# Private Cloud Compute is only in development builds for now
# (PrivateCloudComputeAvailability): Vela doesn't have Apple's
# com.apple.developer.private-cloud-compute entitlement yet, so a release
# leaves its switch out of Settings (compiled out, so its title isn't in the
# app's code) and doesn't promise it to Siri (Catch Me Up's description in
# the App Intents metadata).
pcc_entitlement=com.apple.developer.private-cloud-compute
pcc_switch="Use Private Cloud Compute for long catch-ups"
pcc_found=()
grep -rlaqF -- "$pcc_switch" "$app/Contents/MacOS" "$app/Contents/Frameworks" 2>/dev/null && pcc_found+=("the Settings switch")
grep -qF "Private Cloud Compute" "$app/Contents/Resources/Metadata.appintents/extract.actionsdata" 2>/dev/null \
  && pcc_found+=("Siri's description of Catch Me Up")
if /usr/libexec/PlistBuddy -c "Print :$pcc_entitlement" "$entitlements" >/dev/null 2>&1; then
  check_fail "Private Cloud Compute" "the app has the $pcc_entitlement entitlement, but releases leave Private Cloud Compute out" \
    "If Apple granted it, make it available in releases (PrivateCloudComputeAvailability, the switch in IntelligenceCatchUpSection, CatchMeUpIntent's description), then update this check and the website (docs/RELEASING.md, \"Private Cloud Compute\")."
elif (( ${#pcc_found} )); then
  check_fail "Private Cloud Compute" "the app offers it without the entitlement: ${(j:, :)pcc_found}" \
    "Keep it to development builds (PrivateCloudComputeAvailability; docs/RELEASING.md, \"Private Cloud Compute\")."
else
  check_pass "Private Cloud Compute" "not offered (development builds only until Apple grants the entitlement)"
fi
unset pcc_entitlement pcc_switch pcc_found

# Siri, Shortcuts and Spotlight: the App Intents metadata (lib/release-checks.zsh).
check_app_intents "$app" Vela/VelaShortcuts.swift

if verify_output=$(codesign --verify --deep --strict "$app" 2>&1); then
  check_pass "Signature" "codesign --verify --deep --strict passes"
else
  check_fail "Signature" "$(tidy "$verify_output")" \
    "Rebuild with scripts/release.sh; a file changed after signing, or a nested binary isn't signed."
fi

signing=$(codesign -dvv "$app" 2>&1 || true)
if (( adhoc )); then
  check_skip "Developer ID" "ad hoc build"
else
  authority=$(print -r -- "$signing" | sed -n 's/^Authority=//p' | head -n 1)
  found_team=$(print -r -- "$signing" | sed -n 's/^TeamIdentifier=//p' | head -n 1)
  if [[ "$authority" != "Developer ID Application: "* ]] || ! print -r -- "$signing" | grep -q '^Authority=Developer ID Certification Authority$'; then
    if print -r -- "$signing" | grep -q '^Signature=adhoc'; then
      authority="an ad hoc signature"
    fi
    check_fail "Developer ID" "signed with ${authority:-no certificate}, not a Developer ID Application certificate" \
      "Release with your Developer ID certificate (scripts/release.sh, without --adhoc)."
  elif [[ -n "$team" && "$found_team" != "$team" ]]; then
    check_fail "Developer ID" "Team ID $found_team, expected $team" "Sign with your own team's certificate, or set VELA_TEAM_ID."
  elif [[ "$authority" != *"($found_team)" ]]; then
    check_fail "Developer ID" "the certificate ($authority) doesn't match Team ID $found_team" "Sign with your own team's certificate."
  elif ! print -r -- "$signing" | grep -q '^Timestamp='; then
    check_fail "Developer ID" "no secure timestamp" "Sign with --timestamp (OTHER_CODE_SIGN_FLAGS), as scripts/release.sh does."
  else
    check_pass "Developer ID" "$authority${team:+ (team as expected)}"
  fi
fi

if (( notarized )); then
  assessment=$(spctl -a -vvv "$app" 2>&1 || true)
  if print -r -- "$assessment" | grep -q 'source=Notarized Developer ID'; then
    check_pass "Gatekeeper" "accepted, Notarized Developer ID"
  else
    check_fail "Gatekeeper" "$(tidy "$assessment")" \
      "Notarize and staple the app (scripts/release.sh without --skip-notarize); see \"If something goes wrong\" in docs/RELEASING.md."
  fi
  for file label in "$app" "Stapled ticket (app)" "$dmg" "Stapled ticket (DMG)"; do
    if staple_output=$(xcrun stapler validate "$file" 2>&1); then
      check_pass "$label" "stapler validate passes"
    else
      check_fail "$label" "$(tidy "$staple_output")" "Notarize and staple it again: rerun scripts/release.sh."
    fi
  done
else
  if (( adhoc )); then reason="ad hoc build"; else reason="--skip-notarize"; fi
  check_skip "Gatekeeper" "not notarized ($reason)"
  check_skip "Stapled tickets" "not notarized ($reason)"
fi

if [[ -L "$mountpoint/Applications" && "$(readlink "$mountpoint/Applications")" == /Applications ]]; then
  check_pass "Applications link" "→ /Applications"
else
  check_fail "Applications link" "the DMG has no Applications shortcut" "Rebuild it with scripts/release.sh."
fi

backgrounds=("$mountpoint"/.background.*(N))
if [[ -f "$mountpoint/.DS_Store" && ${#backgrounds} -gt 0 && -f "$mountpoint/.VolumeIcon.icns" ]]; then
  check_pass "Window layout" "background, icon positions and volume icon"
else
  check_fail "Window layout" "the DMG's window has no background, layout or volume icon" "Rebuild it with scripts/release.sh, which makes it with scripts/make-dmg.sh."
fi

finish
