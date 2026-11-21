#!/bin/zsh
# Builds a signed, notarized, stapled Vela.dmg ready for a GitHub release, and
# with --publish, publishes it.
#
#   scripts/release.sh --preflight          # only the release checks; builds no release
#   scripts/release.sh --publish            # the whole release: build, check, tag, publish
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
# With --publish, once every check has passed, it signs Vela.dmg for the
# in-app updater (Sparkle's sign_update, with the EdDSA key read from
# 1Password into a pipe), adds the release to the update feed
# (website/public/appcast.xml) and commits it, tags the commit it built as
# v<version>, pushes the tag to origin, creates the GitHub release with
# Vela.dmg and SHA256SUMS, marked Latest, checks that the website's download
# link (releases/latest/download/Vela.dmg) gives this DMG, then pushes the
# feed's commit to main and waits for velairc.app to serve it. The feed goes
# last, so the updater never offers a release whose download isn't there
# yet. The tag is signed when git has a signing key (user.signingkey or
# tag.gpgSign), and annotated otherwise. The release notes are CHANGELOG.md's
# section for the version followed by scripts/release-notes-footer.md, written
# to build/release/release-notes.md, unless --notes gives a file; the feed
# shows the changelog section. Whether gh and the 1Password CLI are ready, the
# update key in 1Password matches Vela/Info.plist, and there are notes is
# checked before anything is built. If a publishing step fails, nothing is
# deleted: it prints the commands left to finish by hand. See
# docs/RELEASING.md, "Publishing" and "Updates".
#
# Options:
#   --preflight          Run only the preflight checks, and build no release.
#   --publish            Publish the release on GitHub once it's built and
#                        checked (see above). Doesn't go with --preflight,
#                        --adhoc, --skip-notarize, --skip-preflight or
#                        --allow-dirty.
#   --notes <file>       With --publish: the release notes, instead of the ones
#                        made from CHANGELOG.md.
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
#   • For --publish: the GitHub CLI (gh), signed in (gh auth login)
#   • For --publish: the 1Password CLI (op) and the update signing key in
#     1Password (scripts/sparkle-key.sh --create, once), and Node.js
#   • A real update key in Vela/Info.plist (SUPublicEDKey): a release refuses
#     the placeholder (only --adhoc builds go without)
#
# Environment overrides:
#   VELA_TEAM_ID         Apple Developer Team ID (auto-detected from the certificate)
#   VELA_NOTARY_PROFILE  notarytool keychain profile (default: vela-notary)
#   VELA_OP_ACCOUNT, VELA_SPARKLE_VAULT, VELA_SPARKLE_ITEM
#                        Where the update signing key is in 1Password
#                        (default: my.1password.com, Personal,
#                        "Vela - Sparkle - Mac Update Signing Key")
#
# Output: build/release/Vela.dmg (+ SHA256SUMS),
# and with --publish (without --notes) build/release/release-notes.md, plus
# build/release/appcast-notes.md (the feed's release notes) and a commit of
# website/public/appcast.xml
set -euo pipefail
invoked_from=$PWD
cd "${0:A:h}/.."
source scripts/lib/release-checks.zsh
source scripts/lib/sparkle.zsh

notarize=1
adhoc=0
preflight_only=0
skip_preflight=0
allow_dirty=0
publish=0
notes_file=""
preflight_options=()
unpublishable=()
while (( $# )); do
  case "$1" in
    --skip-notarize) notarize=0; unpublishable+=("$1") ;;
    --adhoc) adhoc=1; notarize=0; unpublishable+=("$1") ;;
    --preflight) preflight_only=1; unpublishable+=("$1") ;;
    --skip-preflight) skip_preflight=1; unpublishable+=("$1") ;;
    --allow-dirty) allow_dirty=1; preflight_options+=("$1"); unpublishable+=("$1") ;;
    --publish) publish=1 ;;
    --notes)
      [[ $# -ge 2 && -n "$2" ]] || { print -u2 -r -- "--notes needs a file."; exit 2; }
      notes_file="$2"; shift ;;
    --skip-tests|--skip-ci-check|--skip-media-check|--media-check|--skip-scroll-benchmark|--scroll-benchmark) preflight_options+=("$1") ;;
    *) print -u2 -r -- "Unknown option: $1"; exit 2 ;;
  esac
  shift
done
if (( preflight_only && skip_preflight )); then
  echo "--preflight and --skip-preflight don't go together." >&2
  exit 2
fi
# Only a notarized build that passed every check is published.
if (( publish && ${#unpublishable} )); then
  print -u2 -r -- "--publish doesn't go with ${(j:, :)${(@u)unpublishable}}: only a notarized build that passed every check can be published."
  exit 2
fi
if [[ -n "$notes_file" ]] && (( ! publish )); then
  print -u2 -r -- "--notes goes with --publish."
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

# Publishing (--publish). The website's Download button links to
# releases/latest/download/Vela.dmg on this repository.
github_repo=r3volution11/Vela-IRC
remote=origin
tag="v$version"
release_title="Vela $version"
notes_footer=scripts/release-notes-footer.md
changelog_notes=""
built_commit=""
# The in-app updater's feed, and where Xcode puts Sparkle's tools.
appcast=website/public/appcast.xml
appcast_notes=""
derived_data=build/DerivedData-release

# changelog_section <version>: the body of CHANGELOG.md's "## <version> - …"
# section, without its heading or the blank lines around it.
changelog_section() {
  [[ -f CHANGELOG.md ]] || return 0
  awk -v version="$1" '
    /^## / {
      if (found) exit
      heading = $2
      gsub(/^\[|\]$/, "", heading)
      found = (heading == version)
      next
    }
    found && (NF || started) { started = 1; print }
  ' CHANGELOG.md
}

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
      print -P "%F{green}✓ Ready to release Vela $version ($build_number): run scripts/release.sh --publish.%f"
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

# ---------------------------------------------------------------- update key
# Installed copies of Vela only accept updates signed with the key whose
# public half is in Vela/Info.plist, so a release can't ship the placeholder.
public_key=$(sparkle_public_key)
if ! sparkle_key_is_valid "$public_key"; then
  if (( adhoc )); then
    print -P "    %F{yellow}note:%f $sparkle_info_plist has no update key yet, so this build's updater is off."
  else
    fail "$sparkle_info_plist has no update key yet (SUPublicEDKey is ${public_key:-missing}). Create it once with scripts/sparkle-key.sh --create and paste the public key it prints (docs/RELEASING.md, \"The update signing key\")."
  fi
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

# ---------------------------------------------------------------- publishing setup
# What --publish needs is checked now, before the long build: gh, signed in,
# and the release notes.
if (( publish )); then
  command -v gh >/dev/null \
    || fail "--publish needs the GitHub CLI (gh): brew install gh, then gh auth login."
  gh auth status --hostname github.com >/dev/null 2>&1 \
    || fail "--publish needs gh signed in to GitHub: run gh auth login."
  if [[ -n "$notes_file" ]]; then
    [[ "$notes_file" == /* ]] || notes_file="$invoked_from/$notes_file"
    notes_file=${notes_file:a}
    [[ -f "$notes_file" && -s "$notes_file" ]] || fail "The release notes file $notes_file is missing or empty."
    notes_from="given with --notes"
  else
    changelog_notes=$(changelog_section "$version")
    # Headings, blank lines and HTML comments aren't entries.
    [[ -n "$(print -r -- "$changelog_notes" | grep -vE '^[[:space:]]*(#|<!--|$)' || true)" ]] \
      || fail "CHANGELOG.md has no \"## $version\" section with entries to make the release notes from. Write it (docs/RELEASING.md, \"Before each release\"), or give the notes with --notes <file>."
    [[ -s "$notes_footer" ]] \
      || fail "$notes_footer, the end of the release notes, is missing. Restore it from git, or give the notes with --notes <file>."
    notes_file="$out/release-notes.md"
    notes_from="CHANGELOG.md's \"## $version\" section and $notes_footer, written when the build starts"
  fi
  # The update: the key in 1Password must be the one Vela/Info.plist trusts
  # (1Password asks now, not after the long build), and the feed must take
  # this build.
  command -v op >/dev/null \
    || fail "--publish needs the 1Password CLI (op) to sign the update: brew install 1password-cli, then turn on 1Password → Settings → Developer → Integrate with 1Password CLI."
  command -v node >/dev/null \
    || fail "--publish needs Node.js to add the release to the update feed (the website needs it too)."
  scripts/sparkle-key.sh --check >/dev/null \
    || fail "The update signing key in 1Password isn't ready (see above). docs/RELEASING.md, \"The update signing key\"."
  node website/scripts/appcast.mjs check "$appcast" \
    || fail "$appcast has problems (above). Fix them first (docs/RELEASING.md, \"Updates\")."
  if node website/scripts/appcast.mjs has "$appcast" --build "$build_number"; then
    fail "$appcast already has build $build_number. Bump CURRENT_PROJECT_VERSION."
  fi
  # The feed shows the changelog section (or, without one, the --notes file).
  appcast_notes=$(changelog_section "$version")
  if [[ -z "$(print -r -- "$appcast_notes" | grep -vE '^[[:space:]]*(#|<!--|$)' || true)" ]]; then
    [[ -f "$notes_file" ]] || fail "CHANGELOG.md has no \"## $version\" section for the update feed's release notes."
    appcast_notes=$(<"$notes_file")
  fi
  print "    update:   signed with \"$sparkle_item\" ($sparkle_vault, $sparkle_op_account); feed $appcast"
  # A signed tag when git has a signing key (as with 1Password's SSH signing),
  # an annotated one otherwise.
  if [[ -n "$(git config --get user.signingkey || true)" || "$(git config --bool --get tag.gpgSign || true)" == true ]]; then
    tag_flag=-s
    tag_kind="signed"
    print "    tag:      $tag, signed"
  else
    tag_flag=-a
    tag_kind="annotated, not signed"
    print "    tag:      $tag, annotated, not signed (git has no signing key)"
  fi
  print "    publish:  github.com/$github_repo, marked Latest"
  print "    notes:    $notes_file ($notes_from)"
fi

# The disk image's tools (dmgbuild, scripts/make-dmg.sh), set up now so a
# missing Python stops the release before the long build, not after it.
if (( ! preflight_only )); then
  scripts/make-dmg.sh --prepare \
    || fail "Couldn't set up the disk image tools (scripts/make-dmg.sh --prepare); see its message above."
fi

# ---------------------------------------------------------------- preflight
# Git, version and changelog, CI, the adult-domain list, generated files, the
# tests, the website, the media sites and the scroll benchmark (docs/RELEASING.md,
# "Release checks").
if (( publish )); then
  built_commit=$(git rev-parse HEAD)
fi
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
# --publish tags the commit that was built, so the checkout must still be the
# commit the preflight checked, with nothing changed.
if (( publish )) && [[ "$(git rev-parse HEAD)" != "$built_commit" || -n "$(git status --porcelain --untracked-files=all)" ]]; then
  show_summary
  print
  fail "The checkout changed while the preflight checks ran (they checked ${built_commit[1,7]}), so nothing was built or published. Run scripts/release.sh --publish again."
fi

rm -rf "$out"
mkdir -p "$out"

# The release notes for --publish: CHANGELOG.md's section for this version,
# with its relative links (such as ROADMAP.md) pointing at the files on GitHub
# as of the tag, then the standard footer. Written now, so they can be read
# while the release builds.
if (( publish )) && [[ -n "$changelog_notes" ]]; then
  step "Writing the release notes"
  {
    print -r -- "$changelog_notes" \
      | sed -E "s|\]\(([^):/#[:space:]][^):[:space:]]*)\)|](https://github.com/$github_repo/blob/$tag/\1)|g"
    print
    cat "$notes_footer"
  } > "$notes_file"
  print "    $notes_file"
fi

# ---------------------------------------------------------------- archive
step "Archiving (Release, universal)"
sign_settings=(CODE_SIGN_IDENTITY="$identity")
if (( ! adhoc )); then
  # Vela/Vela.entitlements, not the local builds' Vela-Local.entitlements:
  # Developer ID signs Sparkle too, so library validation stays on. It's
  # VELA_ENTITLEMENTS (Config/Vela.xcconfig), which only the app target uses:
  # CODE_SIGN_ENTITLEMENTS on the command line would apply to every package
  # target too, which have no such file.
  sign_settings+=(CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$team" OTHER_CODE_SIGN_FLAGS="--timestamp" VELA_ENTITLEMENTS=Vela/Vela.entitlements)
fi
xcodebuild archive \
  -project Vela.xcodeproj \
  -scheme Vela \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$out/Vela.xcarchive" \
  -derivedDataPath "$derived_data" \
  ONLY_ACTIVE_ARCH=NO \
  "${sign_settings[@]}" \
  -quiet 2>&1 | tee "$out/archive.log" | grep -vE "CoreSimulator|appintentsmetadataprocessor" || true
# The App Intents metadata processor's lines are kept out of the way above but
# stay in archive.log; the post-build checks look at what it wrote.
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
# Vela.app and an Applications shortcut, in a window drawn like the website's
# dark mode (scripts/make-dmg.sh, scripts/dmg/). Every release is Vela.dmg, the
# name the website's Download button links to. The mounted disk is "Vela", with
# the major version from 2 on ("Vela 2"), like the app names of Bartender 5 or
# Alfred 5: a new number marks a major release.
major=${version%%.*}
volume_name="Vela"
if [[ "$major" == <-> ]] && (( major >= 2 )); then
  volume_name="Vela $major"
fi
scripts/make-dmg.sh "$app" "$out/Vela.dmg" "$volume_name"
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
  fail "$out/Vela.dmg failed the post-build checks, so SHA256SUMS wasn't written. Fix what the summary lists, then build again."
fi

(cd "$out" && shasum -a 256 Vela.dmg > SHA256SUMS)
step "Done"
print "    $out/Vela.dmg"
sed 's/^/    /' "$out/SHA256SUMS"

# ---------------------------------------------------------------- publish
# With --publish: tag the commit that was built, push the tag, create the
# GitHub release, marked Latest, and check that the website's download link
# gives this DMG (docs/RELEASING.md, "Publishing"). If a step fails, nothing
# is deleted: the summary is followed by the commands left to finish by hand.
(( publish )) || exit 0

if grep -q '^FAIL' "$results"; then
  show_summary
  print
  fail "A check failed, so Vela $version wasn't published."
fi

release_url="https://github.com/$github_repo/releases/tag/$tag"
latest_url="https://github.com/$github_repo/releases/latest/download/Vela.dmg"
expected_location="https://github.com/$github_repo/releases/download/$tag/Vela.dmg"
expected_sha=$(awk '$2 == "Vela.dmg" || $2 == "*Vela.dmg" { print $1 }' "$out/SHA256SUMS")
assets=("$out/Vela.dmg" "$out/SHA256SUMS")
publish_steps=(sign appcast tag push release link checksum feed served)
typeset -A publish_check=(
  sign "Update signature"
  appcast "Update feed item"
  tag "Tag $tag"
  push "Push $tag"
  release "GitHub release"
  link "Download link"
  checksum "Download checksum"
  feed "Push the update feed"
  served "Update feed online"
)
# For the update: Sparkle's tools (as Package.resolved pins them, from the
# archive's packages), the app's minimum macOS, and the feed's release notes
# (appcast.mjs points their relative links at the files as of the tag).
sparkle_tools=$(sparkle_bin "$derived_data" || true)
minimum_system=$(plutil -extract LSMinimumSystemVersion raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)
appcast_notes_file="$out/appcast-notes.md"
print -r -- "$appcast_notes" > "$appcast_notes_file"
signature=""
dmg_length=$(stat -f %z "$out/Vela.dmg")
appcast_commit=""
feed_url="$sparkle_feed_url"


# skip_after <step> <why>: SKIP lines for the publishing steps after <step>.
skip_after() {
  local -i i=${publish_steps[(i)$1]}
  local name
  for name in "${(@)publish_steps[i+1,-1]}"; do
    check_skip "$publish_check[$name]" "$2"
  done
}

# finish_by_hand <step> <what happened>: prints the summary, what happened,
# and the commands left to finish by hand from <step> on, then stops.
# <step> is a publishing step, or finish-release for a release gh made but
# didn't finish.
finish_by_hand() {
  local first=$1 what=$2
  local -a commands=("cd ${(q-)PWD}")
  local signature_argument=${signature:-'"$signature"'}
  case $first in
    sign)
      commands+=("signature=\$(op --account ${(q-)sparkle_op_account} read --no-newline ${(q-)$(sparkle_secret_reference)} | ${(q-)${sparkle_tools:-<Sparkle tools>}}/sign_update --ed-key-file - -p $out/Vela.dmg)") ;&
    appcast)
      commands+=(
        "git checkout -- $appcast"
        "node website/scripts/appcast.mjs add $appcast --version $version --build $build_number --minimum-system ${minimum_system:-26.0} --length $dmg_length --signature $signature_argument --notes-file $appcast_notes_file"
        "git commit -m ${(q-)"Appcast: Vela $version"} -- $appcast"
      ) ;&
    tag)
      commands+=("git tag $tag_flag -m ${(q-)release_title} $tag $built_commit") ;&
    push)
      commands+=("git push $remote refs/tags/$tag") ;&
    release)
      commands+=("gh release create $tag ${(j: :)${(@q-)assets}} --repo $github_repo --verify-tag --title ${(q-)release_title} --notes-file ${(q-)notes_file} --latest") ;;
    finish-release)
      commands+=(
        "gh release upload $tag ${(j: :)${(@q-)assets}} --repo $github_repo --clobber"
        "gh release edit $tag --repo $github_repo --draft=false --latest"
      ) ;;
    link)
      commands+=("gh release edit $tag --repo $github_repo --latest") ;;
  esac
  local download_checks=0
  if [[ $first != (feed|served) ]]; then
    download_checks=1
    commands+=(
      "curl -sS -o /dev/null -w '%{redirect_url}\n' $latest_url"
      "curl -sSL $latest_url | shasum -a 256"
    )
  fi
  # The feed goes last, once the download works.
  [[ $first == served ]] || commands+=("git push $remote HEAD:refs/heads/main")
  commands+=("curl -fsSL '$feed_url?release=$build_number' | grep -c '<sparkle:version>$build_number</sparkle:version>'")
  show_summary
  print
  step "Finish by hand"
  print -r -- "    $what Nothing was deleted. To finish, run:"
  print
  print -rl -- "      "${^commands}
  print
  if (( download_checks )); then
    print -r -- "    The first curl should print $expected_location,"
    print -r -- "    and the second $expected_sha  - (Vela.dmg's line in $out/SHA256SUMS)."
  fi
  if [[ $first == checksum ]]; then
    print -r -- "    If the second still differs, upload this DMG again:"
    print -r -- "      gh release upload $tag $out/Vela.dmg --repo $github_repo --clobber"
  fi
  print -r -- "    Push the feed's commit only once the download works. The last curl prints 1 once velairc.app"
  print -r -- "    serves the feed with this release (the Deploy Website workflow takes a few minutes: gh run watch)."
  exit 1
}

RELEASE_CHECKS_RESULTS="$results"
check_section "Publish"

# The update's EdDSA signature: the private key goes from 1Password to
# sign_update through a pipe, and the signature is checked against the
# public key in the app that was built, as Sparkle will check it.
print "    Signing Vela.dmg for the updater (1Password asks to read the key)…"
if [[ -z "$sparkle_tools" ]]; then
  check_fail "$publish_check[sign]" "Sparkle's sign_update isn't in $derived_data/SourcePackages/artifacts" \
    "Resolve the packages (xcodebuild -resolvePackageDependencies -project Vela.xcodeproj -derivedDataPath $derived_data), then finish by hand (below)."
  skip_after sign "the update isn't signed"
  finish_by_hand sign "Vela.dmg isn't signed for the updater, so nothing was tagged or published."
fi
app_key=$(sparkle_public_key "$app/Contents/Info.plist")
signature=$(sparkle_read_private_key | "$sparkle_tools/sign_update" --ed-key-file - -p "$out/Vela.dmg" 2>/dev/null || true)
# Never print what sign_update said when it fails: its errors can quote the key.
if [[ ! "$signature" =~ '^[A-Za-z0-9+/]{86}==$' ]]; then
  signature=""
  check_fail "$publish_check[sign]" "couldn't sign Vela.dmg with the key in 1Password" \
    "Check that 1Password is unlocked and scripts/sparkle-key.sh --check passes, then finish by hand (below)."
  skip_after sign "the update isn't signed"
  finish_by_hand sign "Vela.dmg isn't signed for the updater, so nothing was tagged or published."
elif ! sparkle_verify_signature "$out/Vela.dmg" "$signature" "$app_key"; then
  check_fail "$publish_check[sign]" "the signature doesn't match the app's SUPublicEDKey (${app_key[1,8]}…)" \
    "The key in 1Password isn't the one Vela/Info.plist trusts: compare scripts/sparkle-key.sh --public with SUPublicEDKey, fix it, and build again."
  skip_after sign "the update's signature is wrong"
  finish_by_hand sign "Vela.dmg's update signature doesn't match the app, so nothing was tagged or published."
else
  check_pass "$publish_check[sign]" "EdDSA, valid for the app's SUPublicEDKey (${app_key[1,8]}…); $dmg_length bytes"
fi

# The feed's item (newest first, earlier ones kept), committed on top of the
# commit that was built. It's pushed last, once the download works.
appcast_ok=0
if [[ -z "$minimum_system" ]]; then
  output="couldn't read LSMinimumSystemVersion from the app"
elif output=$(node website/scripts/appcast.mjs add "$appcast" --version "$version" --build "$build_number" \
    --minimum-system "$minimum_system" --length "$dmg_length" --signature "$signature" --notes-file "$appcast_notes_file" 2>&1); then
  if command -v xmllint >/dev/null && ! xmllint --noout "$appcast" 2>/dev/null; then
    output="xmllint finds $appcast malformed"
  elif output=$(git commit --quiet -m "Appcast: Vela $version" -- "$appcast" 2>&1); then
    appcast_ok=1
  fi
fi
if (( appcast_ok )); then
  appcast_commit=$(git rev-parse HEAD)
  check_pass "$publish_check[appcast]" "Vela $version ($build_number), minimum macOS $minimum_system, committed as ${appcast_commit[1,7]}"
else
  git checkout -q -- "$appcast" 2>/dev/null || true
  check_fail "$publish_check[appcast]" "${output//$'\n'/ }" \
    "Fix what it says, then finish by hand (below)."
  skip_after appcast "the feed has no item for $version"
  finish_by_hand appcast "The feed has no item for Vela $version, so nothing was tagged or published."
fi

# The tag, on the commit that was built.
if [[ $tag_flag == -a ]]; then
  print -P "    %F{yellow}note:%f git has no signing key (user.signingkey or tag.gpgSign), so $tag is an annotated tag, not a signed one."
fi
if output=$(git tag "$tag_flag" -m "$release_title" "$tag" "$built_commit" 2>&1); then
  check_pass "$publish_check[tag]" "$tag_kind, on ${built_commit[1,7]}"
else
  check_fail "$publish_check[tag]" "git tag failed: ${output//$'\n'/ }" \
    "Fix what git says (for a signing problem, tag with -a instead of -s), then finish by hand (below)."
  skip_after tag "tagging failed"
  finish_by_hand tag "Tagging failed, so nothing was pushed or published."
fi

if output=$(git push "$remote" "refs/tags/$tag" 2>&1); then
  check_pass "$publish_check[push]" "to $remote"
else
  check_fail "$publish_check[push]" "git push failed: ${output//$'\n'/ }" \
    "Fix what git says, then finish by hand (below)."
  skip_after push "the tag isn't on $remote"
  finish_by_hand push "$tag is tagged here but isn't on $remote, so nothing was published."
fi

print "    Creating the release, with Vela.dmg and SHA256SUMS…"
if output=$(gh release create "$tag" "${assets[@]}" --repo "$github_repo" --verify-tag \
    --title "$release_title" --notes-file "$notes_file" --latest 2>&1); then
  check_pass "$publish_check[release]" "$release_url, marked Latest, notes from $notes_file"
else
  check_fail "$publish_check[release]" "gh release create failed: ${output//$'\n'/ }" \
    "Fix what gh says, then finish by hand (below)."
  skip_after release "the release wasn't published"
  if gh release view "$tag" --repo "$github_repo" >/dev/null 2>&1; then
    finish_by_hand finish-release "$tag is on $remote, and gh made the release but didn't finish it."
  else
    finish_by_hand release "$tag is on $remote, but the GitHub release wasn't created."
  fi
fi

# The website's Download button: GitHub can take a moment to point
# releases/latest at the new release, so try for about a minute.
print "    Checking the download link…"
location=""
for attempt in {1..6}; do
  location=$(curl -sS -o /dev/null -w '%{redirect_url}' "$latest_url" 2>&1 || true)
  if [[ "$location" == "$expected_location" ]]; then
    break
  fi
  if (( attempt < 6 )); then
    sleep 10
  fi
done
if [[ "$location" == "$expected_location" ]]; then
  check_pass "$publish_check[link]" "releases/latest/download/Vela.dmg goes to releases/download/$tag/Vela.dmg"
else
  if [[ "$location" == http* ]]; then
    location="releases/latest/download/Vela.dmg goes to $location, not to releases/download/$tag/Vela.dmg"
  elif [[ -n "$location" ]]; then
    location="couldn't check releases/latest/download/Vela.dmg: ${location//$'\n'/ }"
  else
    location="releases/latest/download/Vela.dmg doesn't redirect anywhere"
  fi
  check_fail "$publish_check[link]" "$location" \
    "Check that $tag is marked Latest and has Vela.dmg (gh release view $tag), then finish by hand (below)."
  skip_after link "the download link isn't this release's"
  finish_by_hand link "The release is published, but the website's download link doesn't give this DMG yet."
fi

curl_errors=$(mktemp -t vela-release-download)
download_problem=""
if downloaded=$(curl -fsSL --retry 3 "$latest_url" 2>"$curl_errors" | shasum -a 256); then
  downloaded=${downloaded%% *}
  if [[ "$downloaded" == "$expected_sha" ]]; then
    check_pass "$publish_check[checksum]" "the downloaded Vela.dmg matches SHA256SUMS"
  else
    download_problem="the Vela.dmg downloaded from it doesn't match SHA256SUMS"
    check_fail "$publish_check[checksum]" "the downloaded Vela.dmg is $downloaded, SHA256SUMS says $expected_sha" \
      "Download it again (below); if it still differs, upload the DMG again."
  fi
else
  download_problem="its Vela.dmg couldn't be downloaded to check it"
  check_fail "$publish_check[checksum]" "couldn't download it: $(tr '\n' ' ' < "$curl_errors" | sed 's/ *$//')" \
    "Check your connection, then check the download by hand (below)."
fi
rm -f "$curl_errors"
if [[ -n "$download_problem" ]]; then
  finish_by_hand checksum "The release is published, but $download_problem."
fi

# The feed, now that the download works: pushing to main deploys velairc.app
# (the Deploy Website workflow), and updaters find the release there.
if output=$(git push "$remote" "HEAD:refs/heads/main" 2>&1); then
  check_pass "$publish_check[feed]" "${appcast_commit[1,7]} is on $remote/main"
else
  check_fail "$publish_check[feed]" "git push failed: ${output//$'\n'/ }" \
    "If $remote/main moved on, git pull --rebase $remote main first; then finish by hand (below)."
  skip_after feed "the feed's commit isn't on $remote"
  finish_by_hand feed "The release is published and downloadable, but the update feed isn't pushed, so the updater doesn't offer it yet."
fi

# velairc.app serves the new feed once the Deploy Website workflow is done
# (a few minutes). Try for about 8 minutes.
print "    Waiting for velairc.app to serve the feed with $version (the Deploy Website workflow takes a few minutes)…"
served=0
for attempt in {1..24}; do
  if curl -fsSL "$feed_url?release=$build_number&try=$attempt" 2>/dev/null | grep -q "<sparkle:version>$build_number</sparkle:version>"; then
    served=1
    break
  fi
  if (( attempt < 24 )); then
    sleep 20
  fi
done
if (( served )); then
  check_pass "$publish_check[served]" "$feed_url offers $version ($build_number)"
else
  check_fail "$publish_check[served]" "$feed_url doesn't have build $build_number yet" \
    "Check the Deploy Website workflow (gh run list --workflow deploy-site.yml --repo $github_repo), then check the feed again (below)."
  finish_by_hand served "The release is published and the feed is pushed, but velairc.app doesn't serve it yet."
fi

show_summary
print
print -P "%F{green}✓ Vela $version is published: $release_url%f"
