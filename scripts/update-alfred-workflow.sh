#!/bin/zsh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Refreshes the Alfred workflow bundled with Vela, which Settings →
# Integrations → Install Workflow opens in Alfred. The workflow lives in its
# own repository, github.com/r3volution11/vela-alfred-workflow; Vela carries a
# built copy of it, with its version and SHA-256 recorded beside it.
#
#   scripts/update-alfred-workflow.sh --release v1.5.0   # a published release of the workflow
#   scripts/update-alfred-workflow.sh --release latest   # its newest release
#   scripts/update-alfred-workflow.sh --local            # build ../Vela Alfred Workflow
#   scripts/update-alfred-workflow.sh --local <dir>      # build the workflow in <dir>
#   scripts/update-alfred-workflow.sh --file <workflow>  # a Vela.alfredworkflow you already have
#   scripts/update-alfred-workflow.sh --check            # the bundled file matches its record
#
# --release downloads the release's Vela.alfredworkflow (and checks it against
# the release's SHA256SUMS, when it has one). --local builds the workflow with
# its repository's scripts/build.sh --output <file>, which tests it first and
# takes the version from the workflow's own info.plist; <dir> defaults to
# "Vela Alfred Workflow" next to Vela's main checkout. --skip-tests passes
# --skip-tests on to it.
#
# Every new file must be a zip with info.plist at its top, for the workflow
# io.github.r3volution11.Vela.alfred, with a version. Then it's copied to
# Vela/Integrations/Vela.alfredworkflow (the app target copies it into the
# app's Resources) and integrations/alfred-workflow.json records its version,
# SHA-256, source (the release's URL, or "local build" with the commit it was
# built from) and the date. Commit both.
#
# --check changes nothing: it fails when the bundled file is missing, isn't a
# valid workflow, or doesn't match the record's SHA-256 and version. CI and
# scripts/release-preflight.sh run it.
#
# Needs curl, unzip, plutil and shasum (all part of macOS).
set -euo pipefail
script="${0:A}"
invoked_from=$PWD
cd "${0:A:h}/.."

repo=r3volution11/vela-alfred-workflow
bundle_id=io.github.r3volution11.Vela.alfred
bundled=Vela/Integrations/Vela.alfredworkflow
record=integrations/alfred-workflow.json

mode=""
release_tag=""
local_dir=""
given_file=""
skip_tests=0
usage() { sed -n '/^# Refreshes/,/^set -euo/p' "$script" | sed '$d; s/^# \{0,1\}//'; }
while (( $# )); do
  case "$1" in
    --release)
      [[ $# -ge 2 && -n "$2" ]] || { print -u2 -r -- "--release needs a tag, such as v1.5.0 or latest."; exit 2; }
      mode=release; release_tag="$2"; shift ;;
    --local)
      mode=local
      if [[ $# -ge 2 && "$2" != --* ]]; then local_dir="$2"; shift; fi ;;
    --file)
      [[ $# -ge 2 && -n "$2" ]] || { print -u2 -r -- "--file needs a Vela.alfredworkflow."; exit 2; }
      mode=file; given_file="$2"; shift ;;
    --check) mode=check ;;
    --skip-tests) skip_tests=1 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 -r -- "Unknown option: $1 (see --help)"; exit 2 ;;
  esac
  shift
done
[[ -n "$mode" ]] || { usage >&2; exit 2; }

step() { print -P "%F{magenta}==>%f %B$1%b"; }
fail() { print -P "%F{red}error:%f $1" >&2; exit 1; }
work=$(mktemp -d -t vela-alfred-workflow)
trap 'rm -rf "$work"' EXIT

# inspect <file>: checks that <file> is a workflow Vela can bundle, and sets
# $workflow_version. Fails with what's wrong.
workflow_version=""
inspect() {
  local file=$1 name=${2:-$1} plist="$work/inspect-info.plist" id
  [[ -s "$file" ]] || fail "$name is missing or empty."
  unzip -tqq "$file" >/dev/null 2>&1 || fail "$name isn't a valid zip archive."
  unzip -p "$file" info.plist > "$plist" 2>/dev/null && [[ -s "$plist" ]] \
    || fail "$name has no info.plist at its top, so Alfred can't import it."
  plutil -lint -s "$plist" || fail "$name's info.plist isn't a valid property list."
  id=$(plutil -extract bundleid raw -o - "$plist" 2>/dev/null || true)
  [[ "$id" == "$bundle_id" ]] || fail "$name is the workflow \"${id:-without a bundle id}\", not $bundle_id."
  workflow_version=$(plutil -extract version raw -o - "$plist" 2>/dev/null || true)
  [[ "$workflow_version" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] \
    || fail "$name's info.plist has no version like 1.5.0 (it says \"$workflow_version\")."
}

sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

# record_value <key>: a string from the record (plutil reads JSON).
record_value() { plutil -extract "$1" raw -o - "$record" 2>/dev/null; }

# ---------------------------------------------------------------- check
if [[ $mode == check ]]; then
  [[ -f "$record" ]] || fail "$record is missing. Restore it from git, or bundle the workflow again (--release or --local)."
  [[ -f "$bundled" ]] || fail "$bundled is missing. Restore it from git, or bundle the workflow again (--release or --local)."
  expected_sha=$(record_value sha256) || fail "$record has no sha256."
  expected_version=$(record_value version) || fail "$record has no version."
  source=$(record_value source || print "?")
  actual_sha=$(sha256 "$bundled")
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    fail "$bundled doesn't match $record: its SHA-256 is $actual_sha, the record says $expected_sha. Bundle it with scripts/update-alfred-workflow.sh (--release or --local), which writes both, instead of changing either by hand."
  fi
  inspect "$bundled"
  [[ "$workflow_version" == "$expected_version" ]] \
    || fail "$bundled is version $workflow_version, but $record says $expected_version."
  print -r -- "$bundled: version $workflow_version, sha256 $actual_sha, from $source"
  exit 0
fi

# ---------------------------------------------------------------- get the workflow
candidate="$work/Vela.alfredworkflow"
candidate_name=""
source=""
commit=""
case $mode in
  release)
    if [[ "$release_tag" == latest ]]; then
      step "Finding the newest release of $repo"
      latest=$(curl -fsSIL -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest") \
        || fail "Couldn't reach github.com/$repo."
      release_tag=${latest##*/releases/tag/}
      [[ "$latest" == */releases/tag/* && -n "$release_tag" ]] || fail "$repo has no published release yet."
      print "    $release_tag"
    fi
    [[ "$release_tag" =~ '^[A-Za-z0-9._-]+$' ]] || fail "\"$release_tag\" isn't a tag like v1.5.0."
    step "Downloading Vela.alfredworkflow from $repo $release_tag"
    base="https://github.com/$repo/releases/download/$release_tag"
    curl -fsSL --retry 3 -o "$candidate" "$base/Vela.alfredworkflow" \
      || fail "Couldn't download $base/Vela.alfredworkflow. Check that the release $release_tag exists and has that file (gh release view $release_tag --repo $repo)."
    if curl -fsSL --retry 3 -o "$work/SHA256SUMS" "$base/SHA256SUMS" 2>/dev/null; then
      listed=$(awk '$2 == "Vela.alfredworkflow" || $2 == "*Vela.alfredworkflow" { print $1 }' "$work/SHA256SUMS")
      [[ -n "$listed" ]] || fail "The release's SHA256SUMS doesn't list Vela.alfredworkflow."
      [[ "$listed" == "$(sha256 "$candidate")" ]] \
        || fail "The downloaded Vela.alfredworkflow doesn't match the release's SHA256SUMS. Try again; if it still differs, check the release."
      print "    matches the release's SHA256SUMS"
    else
      print -P "    %F{yellow}note:%f the release has no SHA256SUMS to check the download against."
    fi
    source="https://github.com/$repo/releases/tag/$release_tag"
    candidate_name="The $release_tag release's Vela.alfredworkflow"
    ;;
  local)
    if [[ -z "$local_dir" ]]; then
      # Next to Vela's main checkout, also from a git worktree.
      main_checkout=$(git rev-parse --path-format=absolute --git-common-dir)
      local_dir="${main_checkout:h:h}/Vela Alfred Workflow"
    elif [[ "$local_dir" != /* ]]; then
      local_dir="$invoked_from/$local_dir"
    fi
    local_dir=${local_dir:a}
    [[ -d "$local_dir" ]] || fail "No workflow checkout at $local_dir. Clone it (git clone https://github.com/$repo.git \"$local_dir\"), or give its folder: --local <dir>."
    [[ -x "$local_dir/scripts/build.sh" ]] || fail "$local_dir has no scripts/build.sh to build the workflow with."
    step "Building the workflow in $local_dir"
    build_options=(--output "$candidate")
    (( skip_tests )) && build_options+=(--skip-tests)
    "$local_dir/scripts/build.sh" "${build_options[@]}" || fail "$local_dir/scripts/build.sh failed (above)."
    commit=$(git -C "$local_dir" rev-parse --short=12 HEAD 2>/dev/null || true)
    if [[ -n "$commit" && -n "$(git -C "$local_dir" status --porcelain 2>/dev/null)" ]]; then
      commit+=" with uncommitted changes"
    fi
    source="local build"
    candidate_name="The workflow $local_dir/scripts/build.sh built"
    ;;
  file)
    [[ "$given_file" == /* ]] || given_file="$invoked_from/$given_file"
    [[ -f "$given_file" ]] || fail "$given_file doesn't exist."
    cp "$given_file" "$candidate"
    source="local build"
    candidate_name=$given_file
    ;;
esac

# ---------------------------------------------------------------- bundle it
inspect "$candidate" "$candidate_name"
if [[ $mode == release && "${release_tag#v}" != "$workflow_version" ]]; then
  print -P "    %F{yellow}note:%f the release is $release_tag, but its workflow says it's version $workflow_version."
fi
new_sha=$(sha256 "$candidate")
mkdir -p "${bundled:h}" "${record:h}"
cp "$candidate" "$bundled"
{
  print '{'
  print -r -- "  \"version\": \"$workflow_version\","
  print -r -- "  \"sha256\": \"$new_sha\","
  print -r -- "  \"source\": \"$source\","
  [[ -n "$commit" ]] && print -r -- "  \"commit\": \"$commit\","
  print -r -- "  \"updated\": \"$(date +%Y-%m-%d)\""
  print '}'
} > "$record"
plutil -convert xml1 -o /dev/null "$record" || fail "Wrote an invalid $record."

step "Bundled the Alfred workflow"
print "    $bundled: version $workflow_version, $(stat -f %z "$bundled") bytes"
print "    sha256 $new_sha"
print "    from $source${commit:+ ($commit)}"
print "    Commit $bundled and $record."
