#!/bin/zsh
# Builds Vela.alfredworkflow, the Alfred workflow, from integrations/alfred.
#
#   scripts/build-alfred-workflow.sh                    # build/Vela.alfredworkflow
#   scripts/build-alfred-workflow.sh --output <file>    # somewhere else (release.sh: build/release/)
#   scripts/build-alfred-workflow.sh --version 1.5.0    # the version it says it is
#   scripts/build-alfred-workflow.sh --skip-tests
#
# First it checks the workflow: info.plist is a valid property list,
# scripts/vela.js compiles (osacompile -l JavaScript), and the tests pass
# (node --test integrations/alfred/test/*.test.mjs, which never talk to
# Vela). If one fails, nothing is built.
#
# The workflow it zips has info.plist (as Alfred writes it, XML), icon.png,
# icons/*.png and scripts/vela.js, and nothing else. In info.plist, "version"
# is Vela's (the Vela target's Release MARKETING_VERSION, unless --version
# gives one) and "readme", which Alfred shows as the workflow's About, is
# integrations/alfred/README.md from its first "##" heading to the
# "end of the workflow's About" marker. Every file gets the same date, so
# the same sources and version make the same file.
#
# scripts/release.sh runs it for every release and attaches the result to
# the GitHub release. To try a change, build it and double-click
# build/Vela.alfredworkflow, or see integrations/alfred/README.md for
# working on the workflow inside Alfred.
#
# Options:
#   --output <file>   Where to write it (default: build/Vela.alfredworkflow).
#   --version <x.y.z> The workflow's version (default: Vela's).
#   --skip-tests      Don't run the tests (the other checks still run).
set -euo pipefail
invoked_from=$PWD
cd "${0:A:h}/.."
source scripts/lib/release-checks.zsh

source_dir=integrations/alfred
output=build/Vela.alfredworkflow
version=""
run_tests=1
while (( $# )); do
  case "$1" in
    --output)
      [[ $# -ge 2 && -n "$2" ]] || { print -u2 -r -- "--output needs a file."; exit 2; }
      output="$2"
      [[ "$output" == /* ]] || output="$invoked_from/$output"
      shift ;;
    --version)
      [[ $# -ge 2 && -n "$2" ]] || { print -u2 -r -- "--version needs a version."; exit 2; }
      version="$2"; shift ;;
    --skip-tests) run_tests=0 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) print -u2 -r -- "Unknown option: $1"; exit 2 ;;
  esac
  shift
done
fail() { print -P "%F{red}error:%f $1" >&2; exit 1; }
output=${output:a}

if [[ -z "$version" ]]; then
  version=$(vela_setting Vela.xcodeproj/project.pbxproj Release MARKETING_VERSION) \
    || fail "Couldn't read MARKETING_VERSION from Vela.xcodeproj; give the version with --version."
fi
[[ "$version" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] || fail "\"$version\" isn't a version like 1.5.0."

# ---------------------------------------------------------------- checks
plutil -lint -s "$source_dir/info.plist" || fail "$source_dir/info.plist isn't a valid property list (above)."
compiled=$(mktemp -d -t vela-alfred)
trap 'rm -rf "$compiled"' EXIT
osacompile -l JavaScript -o "$compiled/vela.scpt" "$source_dir/scripts/vela.js" \
  || fail "$source_dir/scripts/vela.js doesn't compile (above)."
if (( run_tests )); then
  command -v node >/dev/null || fail "The tests need Node.js 20 or later (brew install node), or pass --skip-tests."
  print "    Testing the workflow…"
  node --test "$source_dir"/test/*.test.mjs > "$compiled/test.log" 2>&1 || {
    grep -E "^not ok|^# (tests|pass|fail)|Error|expected|actual" "$compiled/test.log" | head -40 >&2
    fail "The workflow's tests failed (node --test $source_dir/test/*.test.mjs)."
  }
  print "    $(grep -E '^# pass' "$compiled/test.log" | sed 's/^# pass /passed: /') tests"
fi

# ---------------------------------------------------------------- the workflow
staging="$compiled/Vela"
mkdir -p "$staging/scripts" "$staging/icons"
cp "$source_dir/info.plist" "$source_dir/icon.png" "$staging/"
cp "$source_dir/scripts/vela.js" "$staging/scripts/"
cp "$source_dir"/icons/*.png "$staging/icons/"

# The About Alfred shows: README.md from its first "##" heading to the marker.
about=$(awk '/end of the workflow.s About/ { exit } /^## / { started = 1 } started' "$source_dir/README.md")
[[ -n "$about" ]] || fail "$source_dir/README.md has no \"##\" section before its \"end of the workflow's About\" marker."
plutil -replace version -string "$version" "$staging/info.plist"
plutil -replace readme -string "$about" "$staging/info.plist"
plutil -convert xml1 "$staging/info.plist"

# Same date on every file, and a sorted list, so the same input makes the same zip.
find "$staging" -exec touch -h -t 202601010000 {} +
mkdir -p "${output:h}"
rm -f "$output"
(cd "$staging" && find . -mindepth 1 | LC_ALL=C sort | sed 's|^\./||' | zip -q -X -@ "$output")

print "    ${output#$PWD/} (version $version, $(stat -f %z "$output") bytes)"
print "    sha256 $(shasum -a 256 "$output" | cut -d' ' -f1)"
