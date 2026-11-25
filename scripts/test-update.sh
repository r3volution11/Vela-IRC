#!/bin/zsh
# Tests the in-app updater end to end on this Mac: an older Vela finds a
# newer one in a local update feed, downloads it, checks its signature,
# installs it and relaunches, the way users get updates, with everything
# local. It never touches your Vela or Vela Dev (the test app has its own
# bundle id, container and settings), velairc.app, GitHub or 1Password.
#
#   scripts/test-update.sh             # the whole test: opens the old app (ask first: it takes the focus)
#   scripts/test-update.sh --prepare   # everything short of opening an app; safe any time
#   scripts/test-update.sh --clean     # delete the test apps, their data and the test key
#
# What it does (docs/RELEASING.md, "Testing an update"):
#   1. Makes a throwaway EdDSA key for this test only, in build/update-test.
#   2. Builds Release twice as "Vela Update Test" (bundle id
#      io.github.r3volution11.Vela.updatetest): 1.0.0 (1), the old app, and
#      99.0.0 (99), the update. Both have Vela/Info.plist's update settings,
#      with the test key's public half and a feed on
#      http://localhost:<port>/appcast.xml instead.
#   3. Puts the update in a Vela.dmg made by scripts/make-dmg.sh, as
#      releases are, signs it with Sparkle's sign_update, checks the
#      signature with sign_update --verify and against the old app's public
#      key, and adds it to a local feed with website/scripts/appcast.mjs,
#      release notes from CHANGELOG.md included.
#   4. Serves the feed and the DMG on localhost:<port>, and checks that both
#      download.
#   5. Without --prepare: opens the old app. When it checks (if it hasn't
#      by itself within 30 seconds, the script says to choose Vela Update
#      Test → Check for Updates…), Sparkle's update window shows; choose
#      Install Update.
#      The script waits until the app at build/update-test is 99.0.0,
#      running and correctly signed, then says so.
#
# Options:
#   --port <port>   The local server's port (default: 8723).
#   --no-build      Reuse the apps from the last run.
#
# Needs Xcode, Python 3.10 or later (for scripts/make-dmg.sh and the local
# server) and Node.js (for the feed).
set -euo pipefail
script="${0:A}"
cd "${0:A:h}/.."
source scripts/lib/release-checks.zsh
source scripts/lib/sparkle.zsh

usage() { sed -n '2,/^set -euo/p' "$script" | sed -e '$d' -e 's/^# \{0,1\}//'; }

mode=full
port=8723
build=1
while (( $# )); do
  case "$1" in
    --prepare) mode=prepare; shift ;;
    --clean) mode=clean; shift ;;
    --no-build) build=0; shift ;;
    --port)
      [[ $# -ge 2 && "$2" == <1024-65535> ]] || { print -u2 "--port needs a port number (1024–65535)."; exit 2; }
      port=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 -r -- "Unknown option: $1 (see --help)"; exit 2 ;;
  esac
done

bundle_id=io.github.r3volution11.Vela.updatetest
display_name="Vela Update Test"
work=build/update-test
derived="$work/DerivedData"
site="$work/site"
old_app="$work/$display_name.app"
new_app="$work/new/$display_name.app"
key_file="$work/test-key"
feed="$site/appcast.xml"
feed_url="http://localhost:$port/appcast.xml"
container="$HOME/Library/Containers/$bundle_id"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [[ $mode == clean ]]; then
  pkill -f "$PWD/$old_app/Contents/MacOS/" 2>/dev/null || true
  for app in "$old_app" "$new_app"; do
    [[ -d "$app" ]] && "$lsregister" -u "$app" 2>/dev/null || true
  done
  rm -rf "$work"
  # The test app's own sandbox container: its settings and Sparkle's state.
  # Only this test makes that bundle id, so nothing else lives there.
  [[ -d "$container" ]] && rm -rf "$container"
  print "Deleted $work and $container."
  exit 0
fi

results="$work/results"
mkdir -p "$work" "$site"
: > "$results"
RELEASE_CHECKS_RESULTS="$results"
server_pid=""
cleanup() {
  [[ -n $server_pid ]] && kill "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT
finish() {
  print_check_summary "$results"
  print
  if (( release_checks_failed )); then
    print -P "%F{red}✗ The update test failed: $release_checks_failed check(s).%f"
    exit 1
  fi
  print -P "%F{green}✓ $1%f"
  exit 0
}

# ---------------------------------------------------------------- key
check_section "Test key"
if [[ ! -s "$key_file" ]]; then
  # A throwaway key that signs nothing but this test's DMG. It's in a file
  # (in build/, ignored by git) only because it's worthless.
  keys=$(swift "$sparkle_ed25519" generate)
  print -r -- "${keys%%$'\n'*}" > "$key_file"
  chmod 600 "$key_file"
fi
test_public_key=$(swift "$sparkle_ed25519" public < "$key_file")
check_pass "Throwaway key" "public key ${test_public_key[1,8]}… (in $key_file)"

# ---------------------------------------------------------------- builds
# build_test_app <version> <build> <destination .app>
build_test_app() {
  local version=$1 build_number=$2 destination=$3 plist="$work/Info-$2.plist" log="$work/build-$2.log"
  # Vela/Info.plist's update settings with the test key and the local feed.
  cp "$sparkle_info_plist" "$plist"
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL $feed_url" -c "Set :SUPublicEDKey $test_public_key" "$plist"
  # Plain http to localhost is fine for a local test (App Transport
  # Security): Vela/Info.plist already allows it (NSAllowsLocalNetworking,
  # for AI servers such as Ollama), so the copy needs nothing more.
  /usr/libexec/PlistBuddy -c "Print :NSAppTransportSecurity:NSAllowsLocalNetworking" "$plist" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$plist"
  print "    Building $display_name $version ($build_number)…"
  if ! xcodebuild build \
      -project Vela.xcodeproj -scheme Vela -configuration Release \
      -destination 'platform=macOS' -derivedDataPath "$derived" \
      ONLY_ACTIVE_ARCH=YES \
      PRODUCT_BUNDLE_IDENTIFIER=$bundle_id \
      INFOPLIST_KEY_CFBundleDisplayName="$display_name" \
      INFOPLIST_FILE="${plist:A}" \
      MARKETING_VERSION=$version CURRENT_PROJECT_VERSION=$build_number \
      -quiet > "$log" 2>&1; then
    grep -E ': error: ' "$log" | sort -u | head -n 20 >&2 || tail -n 20 "$log" >&2
    return 1
  fi
  rm -rf "$destination"
  mkdir -p "${destination:h}"
  ditto "$derived/Build/Products/Release/Vela.app" "$destination"
}

check_section "Builds"
if (( build )); then
  pkill -f "$PWD/$old_app/Contents/MacOS/" 2>/dev/null || true
  build_test_app 1.0.0 1 "$old_app" || { check_fail "Old app" "the build failed" "See $work/build-1.log."; finish; }
  build_test_app 99.0.0 99 "$new_app" || { check_fail "Update" "the build failed" "See $work/build-99.log."; finish; }
fi
for app label expected in "$old_app" "Old app" "1.0.0 (1)" "$new_app" "Update" "99.0.0 (99)"; do
  info="$app/Contents/Info.plist"
  found="$(plutil -extract CFBundleShortVersionString raw -o - "$info" 2>/dev/null || true) ($(plutil -extract CFBundleVersion raw -o - "$info" 2>/dev/null || true))"
  if [[ ! -d "$app" ]]; then
    check_fail "$label" "$app is missing" "Run without --no-build."
  elif [[ "$found" != "$expected" ]]; then
    check_fail "$label" "it's $found, expected $expected" "Run without --no-build."
  elif [[ $(sparkle_public_key "$info") != "$test_public_key" || $(plutil -extract SUFeedURL raw -o - "$info") != "$feed_url" ]]; then
    check_fail "$label" "its feed or key isn't this test's (another --port, or a new key)" "Run without --no-build."
  elif ! output=$(codesign --verify --deep --strict "$app" 2>&1); then
    check_fail "$label" "codesign --verify --deep --strict: ${output//$'\n'/ }" "Build it again."
  else
    check_pass "$label" "$found, feed $feed_url, signature verifies"
  fi
done
if (( release_checks_failed )); then
  finish
fi

# ---------------------------------------------------------------- the update
check_section "Update"
sparkle_tools=$(sparkle_bin "$derived") || { check_fail "Sparkle's tools" "sign_update isn't in $derived" "Run without --no-build."; finish; }
dmg="$site/Vela.dmg"
print "    Making the update's disk image…"
if ! output=$(scripts/make-dmg.sh "$new_app" "$dmg" "Vela Update Test" 2>&1); then
  check_fail "Disk image" "scripts/make-dmg.sh failed: ${output//$'\n'/ }" "Run scripts/make-dmg.sh --prepare, then try again."
  finish
fi
check_pass "Disk image" "made by scripts/make-dmg.sh, $(stat -f %z "$dmg") bytes"

signature=$("$sparkle_tools/sign_update" --ed-key-file - -p "$dmg" < "$key_file" 2>/dev/null || true)
if [[ "$signature" =~ '^[A-Za-z0-9+/]{86}==$' ]] \
    && "$sparkle_tools/sign_update" --ed-key-file - --verify "$dmg" "$signature" < "$key_file" >/dev/null 2>&1 \
    && sparkle_verify_signature "$dmg" "$signature" "$(sparkle_public_key "$old_app/Contents/Info.plist")"; then
  check_pass "Signature" "sign_update signed it; sign_update --verify and the old app's public key accept it"
else
  check_fail "Signature" "sign_update couldn't sign it, or the signature doesn't verify" "Delete $key_file and run again."
  finish
fi
# A changed byte must fail.
tampered="$work/tampered.dmg"
cp "$dmg" "$tampered"
printf 'x' | dd of="$tampered" bs=1 seek=4096 conv=notrunc 2>/dev/null
if sparkle_verify_signature "$tampered" "$signature" "$test_public_key"; then
  check_fail "Tampered update" "a changed DMG still verifies" "Something is wrong with signature checking; don't release."
else
  check_pass "Tampered update" "a DMG with one byte changed is refused"
fi
rm -f "$tampered"

# The feed: the release notes are the newest changelog section.
notes="$work/notes.md"
# The first changelog section with entries (Unreleased, while there's one).
awk '/^## / { if (entries) exit; inside = 1; next } inside { print; if (NF) entries++ }' CHANGELOG.md > "$notes"
grep -q '[^[:space:]]' "$notes" || print -r -- "- A test update." > "$notes"
node website/scripts/appcast.mjs empty "$feed"
if output=$(node website/scripts/appcast.mjs add "$feed" --version 99.0.0 --build 99 \
    --minimum-system "$(plutil -extract LSMinimumSystemVersion raw -o - "$new_app/Contents/Info.plist")" \
    --length "$(stat -f %z "$dmg")" --signature "$signature" --notes-file "$notes" \
    --url "http://localhost:$port/Vela.dmg" 2>&1) \
    && node website/scripts/appcast.mjs check "$feed" --local >/dev/null 2>&1 \
    && { ! command -v xmllint >/dev/null || xmllint --noout "$feed"; }; then
  check_pass "Feed" "$feed has 99.0.0 (99) with the signature, length and release notes"
else
  check_fail "Feed" "${output//$'\n'/ }" "Fix website/scripts/appcast.mjs."
  finish
fi

# ---------------------------------------------------------------- serving
check_section "Local server"
if curl -s -o /dev/null "http://localhost:$port/" 2>/dev/null; then
  check_fail "Server" "something already answers on port $port" "Stop it, or pass --port <another port>."
  finish
fi
python3 -I -m http.server "$port" --bind 127.0.0.1 --directory "$site" > "$work/server.log" 2>&1 &
server_pid=$!
for attempt in {1..50}; do
  curl -s -o /dev/null "$feed_url" 2>/dev/null && break
  sleep 0.1
done
served_feed=$(curl -fsS "$feed_url" 2>/dev/null || true)
served_sha=$(curl -fsS "http://localhost:$port/Vela.dmg" 2>/dev/null | shasum -a 256 | cut -d ' ' -f 1)
if [[ $served_feed == *"<sparkle:version>99</sparkle:version>"* && $served_sha == $(shasum -a 256 "$dmg" | cut -d ' ' -f 1) ]]; then
  check_pass "Server" "$feed_url and the DMG download, intact"
else
  check_fail "Server" "the feed or the DMG didn't download intact" "See $work/server.log."
  finish
fi

if [[ $mode == prepare ]]; then
  finish "Ready: run scripts/test-update.sh (without --prepare) to update the old app for real."
fi

# ---------------------------------------------------------------- the real thing
check_section "Updating"
print
print -P "    %BOpening $display_name 1.0.0.%b"
print -r -- "    In Sparkle's window, choose Install Update. It quits, installs 99.0.0 and opens again."
print -r -- "    Waiting up to 10 minutes; Ctrl-C stops the test."
print
feed_requests() { grep -c 'GET /appcast.xml' "$work/server.log" 2>/dev/null || print 0; }
requests_before=$(feed_requests)
open "$old_app"
# Sparkle may leave an app's very first launch alone; if the app hasn't
# asked for the feed after 30 seconds, ask for the check by hand.
asked=0
updated=0
for attempt in {1..300}; do
  if (( ! asked && attempt == 15 )) && (( $(feed_requests) == requests_before )); then
    asked=1
    print -P "    %F{yellow}It hasn't checked by itself.%f Choose $display_name → Check for Updates… now."
  fi
  if [[ $(plutil -extract CFBundleVersion raw -o - "$old_app/Contents/Info.plist" 2>/dev/null || true) == 99 ]] \
      && pgrep -f "$PWD/$old_app/Contents/MacOS/" >/dev/null; then
    updated=1
    break
  fi
  sleep 2
done
if (( ! updated )); then
  check_fail "Update installed" "$old_app is still $(plutil -extract CFBundleShortVersionString raw -o - "$old_app/Contents/Info.plist" 2>/dev/null || print '?') after 10 minutes" \
    "See Console.app (filter: Sparkle, or the process Vela) and $work/server.log for what the app asked for."
  finish
fi
check_pass "Update installed" "$old_app is 99.0.0 (99) and running again"
if output=$(codesign --verify --deep --strict "$old_app" 2>&1); then
  check_pass "Installed signature" "codesign --verify --deep --strict passes"
else
  check_fail "Installed signature" "${output//$'\n'/ }" "Sparkle installed a damaged app; see Console.app."
fi
if grep -q 'GET /Vela.dmg' "$work/server.log"; then
  check_pass "Download" "the app downloaded Vela.dmg from the local feed"
else
  check_fail "Download" "the server never sent Vela.dmg" "See $work/server.log."
fi
print
print -r -- "    Quit $display_name, then delete the test apps and their data: scripts/test-update.sh --clean"
finish "The update test passed: $display_name went from 1.0.0 to 99.0.0 by itself."
