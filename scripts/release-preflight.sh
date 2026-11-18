#!/bin/zsh
# Checks that everything is ready for a Vela release. scripts/release.sh runs
# it before archiving and stops if a check fails; run it on its own (or as
# scripts/release.sh --preflight) while you prepare a release. It builds no
# app and doesn't touch your files or branches: besides fetching main and the
# tags from origin, it writes only to ignored folders (build/,
# website/node_modules, the website's build output).
#
#   scripts/release-preflight.sh                  # every check
#   scripts/release-preflight.sh --skip-tests     # every check but swift test
#
# Checks (docs/RELEASING.md, "Release checks", says what to do when one fails):
#   Git            On main; the working tree is clean (untracked files count,
#                  ignored ones don't); HEAD is on origin/main; the tag
#                  v<version> doesn't exist here or on origin.
#   Version        MARKETING_VERSION is the same in the Vela target's Debug and
#                  Release configurations and newer than the previous release's;
#                  CURRENT_PROJECT_VERSION is a positive integer, the same in
#                  both, and higher than the previous release's; CHANGELOG.md's
#                  newest version section is "## <version> - <yyyy-mm-dd>" and
#                  has entries; "## Unreleased", if there is one, has none.
#   CI             The CI workflow passed for HEAD's commit, and so did the
#                  Media sites workflow if it ran for it (needs gh, signed in).
#   Adult domains  adult-domains.txt was refreshed since the previous release
#                  (no release yet: in the last 30 days).
#   Generated      The settings reference generator changes no committed file;
#                  the theme schema, the token table in docs/THEMES.md and the
#                  supported media sites page match what the code generates.
#   Tests          swift test --package-path Packages/VelaKit
#   Website        npm ci (only if node_modules is missing), npm run docs:build,
#                  npm run docs:check
#   Media sites    scripts/check-media-sites.sh
#
# Every check runs, even after one fails, so you see everything to fix at once.
#
# Options:
#   --adhoc              For an ad hoc build (scripts/release.sh --adhoc): skip the
#                        git, version and CI checks, and the media check unless
#                        --media-check is given.
#   --allow-dirty        Let uncommitted changes through (for testing the pipeline).
#   --skip-tests         Don't run swift test.
#   --skip-ci-check      Don't ask GitHub about CI.
#   --skip-media-check   Don't check the media sites.
#   --media-check        Check the media sites even with --adhoc.
#   --results <file>     Append each result to <file> and leave the summary to the
#                        caller (scripts/release.sh).
#
# Logs: build/release-preflight/ (swift test, the website build, the generators).
# SwiftPM builds in build/release-preflight/swift, away from Xcode's and your
# editor's builds.
#
# Exits 0 when every check that ran passed, 1 when one failed, 2 for an
# unknown option.
set -euo pipefail
script="${0:A}"
cd "${0:A:h}/.."
source scripts/lib/release-checks.zsh

remote=origin
branch=main
adhoc=0
allow_dirty=0
run_tests=1
ci_check=1
media_check_option=""
results=""

usage() { sed -n '2,/^set -euo/p' "$script" | sed -e '$d' -e 's/^# \{0,1\}//'; }

while (( $# )); do
  case "$1" in
    --adhoc) adhoc=1; shift ;;
    --allow-dirty) allow_dirty=1; shift ;;
    --skip-tests) run_tests=0; shift ;;
    --skip-ci-check) ci_check=0; shift ;;
    --skip-media-check) media_check_option=0; shift ;;
    --media-check) media_check_option=1; shift ;;
    --results)
      [[ $# -ge 2 && -n "$2" ]] || { print -u2 "--results needs a file"; exit 2; }
      results="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 -r -- "Unknown option: $1 (see --help)"; exit 2 ;;
  esac
done
# An ad hoc build is for trying things on this Mac, not for shipping.
media_check=${media_check_option:-$(( adhoc ? 0 : 1 ))}

work="$PWD/build/release-preflight"
swift_scratch="$work/swift"
mkdir -p "$work"
tmp=$(mktemp -d -t vela-preflight)
trap 'rm -rf "$tmp"' EXIT

if [[ -n "$results" ]]; then
  RELEASE_CHECKS_RESULTS="$results"
else
  RELEASE_CHECKS_RESULTS="$tmp/results"
fi
: >> "$RELEASE_CHECKS_RESULTS"

project=Vela.xcodeproj/project.pbxproj
changelog=CHANGELOG.md
adult_list=Packages/VelaKit/Sources/VelaMedia/Resources/adult-domains.txt
version=$(vela_setting "$project" Release MARKETING_VERSION || true)
build_number=$(vela_setting "$project" Release CURRENT_PROJECT_VERSION || true)
head_sha=$(git rev-parse HEAD)
short_sha=${head_sha[1,7]}
today=$(date +%Y-%m-%d)

# The release before this one: the newest v<version> tag in HEAD's history,
# other than this version's own.
previous_tag() {
  git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude "v$version" HEAD 2>/dev/null || true
}

# Text from a log, colors removed, that says why swift (build or test) failed.
swift_failures() {
  local clean errors
  clean=$(sed $'s/\x1b\\[[0-9;]*m//g' "$1")
  errors=$(print -r -- "$clean" | grep -E '^/.*: error: ' | sort -u | head -n 20 || true)
  if [[ -n "$errors" ]]; then
    print "Build errors:"
    print -r -- "$errors"
    return
  fi
  # Swift Testing marks lines with SF Symbols, so match the words: "Test x()
  # recorded an issue at …", "… failed after …"; and XCTest's "error: -[…]".
  errors=$(print -r -- "$clean" | grep -E '(recorded an issue|failed after|error: -\[|: error: )' | head -n 40 || true)
  if [[ -n "$errors" ]]; then
    print -r -- "$errors"
  else
    print -r -- "$clean" | tail -n 25
  fi
}

indent() { sed 's/^/          /'; }

# plural <n> <word>: "1 line", "2 lines".
plural() { if [[ $1 == 1 ]]; then print -r -- "1 $2"; else print -r -- "$1 ${2}s"; fi; }

print -P "%F{magenta}==>%f %BRelease preflight for Vela ${version:-?} (${build_number:-?}) at $short_sha%b"

# ---------------------------------------------------------------- git
check_git() {
  check_section "Git"
  if (( adhoc )); then
    check_skip "Git checks" "ad hoc build"
    return
  fi

  local current changes count unpushed fetch_output local_tag remote_status
  current=$(git symbolic-ref --short -q HEAD || true)
  if [[ "$current" == "$branch" ]]; then
    check_pass "On $branch"
  else
    check_fail "On $branch" "on ${current:-a detached HEAD}" \
      "Releases are built from $branch: git switch $branch (and merge your work into it first)."
  fi

  changes=$(git status --porcelain=v1 --untracked-files=all)
  if [[ -z "$changes" ]]; then
    check_pass "Clean working tree"
  else
    count=$(print -r -- "$changes" | wc -l | tr -d ' ')
    if (( allow_dirty )); then
      check_skip "Clean working tree" "$(plural $count "uncommitted change") let through by --allow-dirty"
    else
      check_fail "Clean working tree" "$(plural $count "uncommitted change") (untracked files included)" \
        "Commit them, stash them (git stash -u) or delete stray files; see git status. For a test build, add --allow-dirty."
      print -r -- "$changes" | head -n 10 | indent
      (( count > 10 )) && print "          … and $(( count - 10 )) more"
    fi
  fi

  if fetch_output=$(git fetch --quiet --tags "$remote" "$branch" 2>&1); then
    if git merge-base --is-ancestor HEAD "refs/remotes/$remote/$branch" 2>/dev/null; then
      check_pass "Pushed" "$remote/$branch contains $short_sha"
    else
      unpushed=$(git rev-list --count "refs/remotes/$remote/$branch..HEAD" 2>/dev/null || print "?")
      if [[ "$unpushed" == 1 ]]; then unpushed="1 commit isn't"; else unpushed="$unpushed commits aren't"; fi
      check_fail "Pushed" "$unpushed on $remote/$branch" \
        "Push them (git push $remote $branch) and wait for CI. If $remote/$branch has moved on, pull first."
    fi
  else
    check_fail "Pushed" "couldn't fetch $remote: ${fetch_output//$'\n'/ }" \
      "Check your connection and that git fetch $remote works."
  fi

  if [[ -z "$version" ]]; then
    check_fail "Tag is new" "no version to check" "See the Version checks."
    return
  fi
  local tag="v$version" local_tag=0 where="" undo=""
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null && local_tag=1
  remote_status=0
  git ls-remote --exit-code --tags "$remote" "refs/tags/$tag" >/dev/null 2>&1 || remote_status=$?
  if (( remote_status != 0 && remote_status != 2 )); then
    check_fail "Tag $tag is new" "couldn't ask $remote about $tag" "Check your connection and that git ls-remote $remote works."
    return
  fi
  if (( local_tag )); then
    where="here"
    undo="git tag -d $tag"
  fi
  if (( remote_status == 0 )); then
    where+="${where:+ and }on $remote"
    undo+="${undo:+, }git push $remote :refs/tags/$tag"
  fi
  if [[ -z "$where" ]]; then
    check_pass "Tag $tag is new" "not here, not on $remote"
  else
    check_fail "Tag $tag is new" "$tag already exists $where" \
      "If $version was released, bump MARKETING_VERSION and the changelog. If the tag was made by mistake and nothing was published, delete it: $undo."
  fi
}

# ---------------------------------------------------------------- version
check_version() {
  check_section "Version"
  if (( adhoc )); then
    check_skip "Version checks" "ad hoc build"
    return
  fi

  local debug_version debug_build tag previous_version="" previous_build="" tag_project
  debug_version=$(vela_setting "$project" Debug MARKETING_VERSION || true)
  debug_build=$(vela_setting "$project" Debug CURRENT_PROJECT_VERSION || true)
  tag=$(previous_tag)
  if [[ -n "$tag" ]]; then
    previous_version=${tag#v}
    tag_project="$tmp/previous.pbxproj"
    if git show "$tag:$project" > "$tag_project" 2>/dev/null; then
      previous_build=$(vela_setting "$tag_project" Release CURRENT_PROJECT_VERSION || true)
    fi
  fi

  local edit_fix="Set it in Xcode (Vela target → General → Version and Build), which changes both configurations, or in $project."
  if [[ -z "$version" || -z "$debug_version" ]]; then
    check_fail "Version" "couldn't read MARKETING_VERSION from the Vela target in $project" "$edit_fix"
  elif [[ "$version" != "$debug_version" ]]; then
    check_fail "Version" "Debug has $debug_version, Release has $version" "$edit_fix"
  elif [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    check_fail "Version" "$version isn't <major>.<minor>.<patch>" "$edit_fix"
  elif [[ -n "$previous_version" && "$(print -l -- "$previous_version" "$version" | sort -V | tail -n 1)" != "$version" ]]; then
    check_fail "Version" "$version isn't newer than the previous release, $tag" \
      "Pick the next version (docs/RELEASING.md, \"Before each release\"). $edit_fix"
  else
    check_pass "Version" "$version in Debug and Release${tag:+ (previous release $tag)}"
  fi

  if [[ -z "$build_number" || -z "$debug_build" ]]; then
    check_fail "Build number" "couldn't read CURRENT_PROJECT_VERSION from the Vela target" "$edit_fix"
  elif [[ "$build_number" != "$debug_build" ]]; then
    check_fail "Build number" "Debug has $debug_build, Release has $build_number" "$edit_fix"
  elif [[ ! "$build_number" =~ '^[1-9][0-9]*$' ]]; then
    check_fail "Build number" "$build_number isn't a positive whole number" "$edit_fix"
  elif [[ -n "$tag" && -z "$previous_build" ]]; then
    check_fail "Build number" "couldn't read the build number of $tag" \
      "Check that $tag is a release tag and that git show $tag:$project works."
  elif [[ -n "$previous_build" ]] && (( build_number <= previous_build )); then
    check_fail "Build number" "$build_number isn't higher than $tag's $previous_build" \
      "Set it to $(( previous_build + 1 )). $edit_fix"
  else
    check_pass "Build number" "$build_number${previous_build:+ (previous release $previous_build)}"
  fi

  check_changelog
}

# Reads CHANGELOG.md: its "## Unreleased" section and its newest version
# section. Headings, blank lines and HTML comments aren't entries.
check_changelog() {
  local line section="" newest="" heading_fix
  local -i newest_entries=0 unreleased_entries=0 has_unreleased=0
  if [[ ! -f "$changelog" ]]; then
    check_fail "Changelog" "$changelog is missing" "Restore it from git."
    return
  fi
  for line in "${(@f)$(<$changelog)}"; do
    if [[ "$line" == '## '* ]]; then
      if [[ "${line:l}" == '## unreleased'* || "${line:l}" == '## [unreleased]'* ]]; then
        section=unreleased
        has_unreleased=1
      elif [[ -z "$newest" ]]; then
        newest=${line#'## '}
        section=newest
      else
        break
      fi
      continue
    fi
    [[ -z "${line//[[:space:]]/}" || "$line" == '#'* || "$line" == '<!--'* ]] && continue
    case $section in
      unreleased) unreleased_entries+=1 ;;
      newest) newest_entries+=1 ;;
    esac
  done

  heading_fix="Rename \"## Unreleased\" to \"## ${version:-<version>} - $today\" (the release date) and start a new, empty \"## Unreleased\" above it."
  local date=""
  if [[ "$newest" =~ '^([^ ]+) - ([0-9]{4}-[0-9]{2}-[0-9]{2})$' ]]; then
    date=$match[2]
    [[ "$(date -j -f %Y-%m-%d "$date" +%Y-%m-%d 2>/dev/null || true)" == "$date" ]] || date=""
  fi
  if [[ -z "$newest" ]]; then
    check_fail "Changelog section" "$changelog has no version section" "$heading_fix"
  elif [[ "${newest%% *}" != "$version" ]]; then
    check_fail "Changelog section" "the newest section is \"## $newest\", not $version" \
      "$heading_fix If $version is already in the changelog under another heading, fix the heading."
  elif [[ -z "$date" ]]; then
    check_fail "Changelog section" "\"## $newest\" should be \"## $version - <yyyy-mm-dd>\"" \
      "Write the heading as \"## $version - $today\", with the release date."
  elif (( newest_entries == 0 )); then
    check_fail "Changelog section" "\"## $newest\" has no entries" \
      "Move this release's entries from \"## Unreleased\" into it."
  else
    check_pass "Changelog section" "\"## $newest\", $(plural $newest_entries line)"
  fi

  if (( ! has_unreleased )); then
    check_pass "Changelog Unreleased" "no Unreleased section"
  elif (( unreleased_entries == 0 )); then
    check_pass "Changelog Unreleased" "empty"
  else
    check_fail "Changelog Unreleased" "\"## Unreleased\" has $(plural $unreleased_entries line), which this build includes but its version section doesn't" \
      "Move them into \"## ${version:-<version>} - <date>\" and leave \"## Unreleased\" empty."
  fi
}

# ---------------------------------------------------------------- CI
# workflow_name <file in .github/workflows>: the workflow's name: line.
workflow_name() {
  sed -n 's/^name: *//p' ".github/workflows/$1" 2>/dev/null | head -n 1 | tr -d "\"'"
}

# ci_status <workflow name>: "none", or the newest run of that workflow for
# HEAD as status<TAB>conclusion<TAB>url<TAB>id. Fails (with gh's message) if
# gh does. It filters by name rather than asking for the workflow file, which
# GitHub only knows once it's on the default branch.
ci_status() {
  local out
  out=$(gh run list --commit "$head_sha" --limit 100 \
    --json workflowName,status,conclusion,url,databaseId \
    --jq "[.[] | select(.workflowName == \"$1\")] | .[0] // empty | [.status, (.conclusion // \"\"), .url, (.databaseId | tostring)] | @tsv" 2>&1) || {
    print -r -- "${out//$'\n'/ }"
    return 1
  }
  print -r -- "${out:-none}"
}

check_ci() {
  check_section "CI"
  if (( adhoc )); then
    check_skip "CI checks" "ad hoc build"
    return
  fi
  if (( ! ci_check )); then
    check_skip "CI checks" "--skip-ci-check"
    return
  fi
  if ! command -v gh >/dev/null; then
    check_fail "CI workflow" "the GitHub CLI (gh) isn't installed" \
      "brew install gh, then gh auth login. Or rerun with --skip-ci-check."
    return
  fi
  if ! gh auth status >/dev/null 2>&1; then
    check_fail "CI workflow" "gh isn't signed in to GitHub" "Run gh auth login. Or rerun with --skip-ci-check."
    return
  fi

  local workflow label name run
  local -a fields
  for workflow label in ci.yml "CI workflow" media-sites.yml "Media sites workflow"; do
    name=$(workflow_name "$workflow")
    if [[ -z "$name" ]]; then
      if [[ $workflow == ci.yml ]]; then
        check_fail "$label" ".github/workflows/$workflow is missing or has no name" "Restore it from git."
      else
        check_skip "$label" "no .github/workflows/$workflow"
      fi
      continue
    fi
    if ! run=$(ci_status "$name"); then
      check_fail "$label" "couldn't list the runs for $short_sha: $run" \
        "Check that gh works here (gh run list --commit $head_sha), or rerun with --skip-ci-check."
      continue
    fi
    if [[ "$run" == none ]]; then
      if [[ $workflow == ci.yml ]]; then
        check_fail "$label" "no run for $short_sha yet" \
          "Push it (git push $remote $branch), wait for CI to finish (gh run watch), then run this again."
      else
        check_pass "$label" "didn't run for $short_sha (it runs when media code changes)"
      fi
      continue
    fi
    fields=("${(@ps:\t:)run}")
    if [[ "$fields[1]" != completed ]]; then
      check_fail "$label" "still running for $short_sha ($fields[3])" \
        "Wait for it to finish (gh run watch $fields[4]), then run this again."
    elif [[ "$fields[2]" == success ]]; then
      check_pass "$label" "passed for $short_sha"
    else
      local outcome
      case "$fields[2]" in
        failure|"") outcome="failed" ;;
        cancelled) outcome="was cancelled" ;;
        timed_out) outcome="timed out" ;;
        *) outcome="ended with ${fields[2]}" ;;
      esac
      check_fail "$label" "$outcome for $short_sha: $fields[3]" \
        "Open the run and fix what failed, then push and wait for CI again. If it was a fluke: gh run rerun $fields[4] --failed."
    fi
  done
}

# ---------------------------------------------------------------- adult domains
check_adult_domains() {
  check_section "Adult-domain list"
  local name="Adult-domain list" fix="Run scripts/update-adult-domains.sh, check its summary and commit the list (docs/RELEASING.md, \"The adult-domain list\")."
  local date commit tag tag_header tag_date tag_commit now then_ age
  if [[ ! -f "$adult_list" ]]; then
    check_fail "$name" "$adult_list is missing" "$fix"
    return
  fi
  date=$(sed -n '1,40s/^# Date: *\([0-9-]*\).*/\1/p' "$adult_list" | head -n 1)
  commit=$(sed -n '1,40s/^# Commit: *\([0-9a-f]*\).*/\1/p' "$adult_list" | head -n 1)
  if [[ ! "$date" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ]]; then
    check_fail "$name" "its header has no \"# Date:\" line" "$fix"
    return
  fi
  local refreshed="refreshed $date${commit:+ (upstream ${commit[1,7]})}"
  tag=$(previous_tag)
  if [[ -n "$tag" ]]; then
    tag_header=$(git show "$tag:$adult_list" 2>/dev/null | head -n 40 || true)
    tag_date=$(print -r -- "$tag_header" | sed -n 's/^# Date: *\([0-9-]*\).*/\1/p' | head -n 1)
    tag_commit=$(print -r -- "$tag_header" | sed -n 's/^# Commit: *\([0-9a-f]*\).*/\1/p' | head -n 1)
    if [[ -z "$tag_date" ]]; then
      check_pass "$name" "$refreshed; $tag had no dated list"
    elif [[ "$date" > "$tag_date" || "$commit" != "$tag_commit" || "$date" == "$(date -u +%Y-%m-%d)" ]]; then
      check_pass "$name" "$refreshed; $tag shipped the one from $tag_date"
    else
      check_fail "$name" "last refreshed $date, the same list $tag shipped" "$fix"
    fi
  else
    now=$(date -u +%s)
    then_=$(date -j -u -f '%Y-%m-%d %H:%M:%S' "$date 00:00:00" +%s 2>/dev/null || print 0)
    age=$(( (now - then_) / 86400 ))
    if (( age <= 30 )); then
      check_pass "$name" "$refreshed, $age days ago"
    else
      check_fail "$name" "last refreshed $date, $age days ago (no release yet, so it must be at most 30 days old)" "$fix"
    fi
  fi
}

# ---------------------------------------------------------------- generated files
# A fingerprint of everything git would report: tracked changes and untracked
# files that aren't ignored.
tree_state() {
  { git status --porcelain=v1 --untracked-files=all; git diff HEAD --no-ext-diff --binary; } | shasum | cut -d' ' -f1
}

check_generated() {
  check_section "Generated files"
  local log="$work/generators.log" before after changed bin
  : > "$log"

  if ! command -v node >/dev/null; then
    check_fail "Settings reference" "node isn't installed" "Install Node 20 or later (nvm install 22)."
  else
    before=$(tree_state)
    if node website/scripts/generate.mjs >> "$log" 2>&1; then
      after=$(tree_state)
      if [[ "$before" == "$after" ]]; then
        check_pass "Settings reference" "website/scripts/generate.mjs changes no committed file"
      else
        changed=$(git status --porcelain=v1 --untracked-files=all | head -n 10)
        check_fail "Settings reference" "website/scripts/generate.mjs changed committed files" \
          "Review the changes it made (git status, git diff) and commit them."
        print -r -- "$changed" | indent
      fi
    else
      check_fail "Settings reference" "website/scripts/generate.mjs failed" \
        "Fix what it reports (node website/scripts/generate.mjs; full output in ${log#$PWD/})."
      grep '^generate:' "$log" | head -n 10 | indent || true
    fi
  fi

  print "    Building vela-theme-tool and vela-media-tool…"
  if ! { swift build --package-path Packages/VelaKit --scratch-path "$swift_scratch" --product vela-theme-tool \
         && swift build --package-path Packages/VelaKit --scratch-path "$swift_scratch" --product vela-media-tool; } >> "$log" 2>&1; then
    local why="couldn't build vela-theme-tool and vela-media-tool"
    local fix="Fix the build errors (full output in ${log#$PWD/})."
    check_fail "Theme schema" "$why" "$fix"
    check_fail "Theme token table" "$why" "$fix"
    check_fail "Media sites page" "$why" "$fix"
    swift_failures "$log" | indent
    return
  fi
  bin=$(swift build --package-path Packages/VelaKit --scratch-path "$swift_scratch" --show-bin-path)

  local schema=schemas/vela-theme.schema.json
  if "$bin/vela-theme-tool" schema > "$tmp/schema.json" 2>> "$log" && cmp -s "$tmp/schema.json" "$schema"; then
    check_pass "Theme schema" "$schema is up to date"
  else
    check_fail "Theme schema" "$schema doesn't match the token registry" \
      "swift run --package-path Packages/VelaKit vela-theme-tool schema > $schema, then commit it."
  fi

  local themes_doc=docs/THEMES.md
  sed -n '/^<!-- BEGIN TOKEN TABLE -->$/,/^<!-- END TOKEN TABLE -->$/p' "$themes_doc" | sed '1d;$d' > "$tmp/tokens-committed.md"
  if "$bin/vela-theme-tool" tokens > "$tmp/tokens.md" 2>> "$log" && [[ -s "$tmp/tokens-committed.md" ]] \
     && cmp -s "$tmp/tokens.md" "$tmp/tokens-committed.md"; then
    check_pass "Theme token table" "$themes_doc is up to date"
  else
    check_fail "Theme token table" "the token table in $themes_doc doesn't match the token registry" \
      "Replace everything between the TOKEN TABLE markers in $themes_doc with the output of: swift run --package-path Packages/VelaKit vela-theme-tool tokens. Then commit it."
  fi

  local page=website/reference/media-sites.md
  cp "$page" "$tmp/media-sites.md"
  if "$bin/vela-media-tool" docs --write "$tmp/media-sites.md" >> "$log" 2>&1 && cmp -s "$tmp/media-sites.md" "$page"; then
    check_pass "Media sites page" "$page is up to date"
  else
    check_fail "Media sites page" "$page doesn't match MediaSites.swift" \
      "swift run --package-path Packages/VelaKit vela-media-tool docs --write $page, then commit it."
  fi
}

# ---------------------------------------------------------------- tests
check_tests() {
  check_section "Tests"
  if (( ! run_tests )); then
    check_skip "Package tests" "--skip-tests"
    return
  fi
  local log="$work/swift-test.log" summary unfinished
  print "    Running swift test (the first run builds everything and takes a few minutes)…"
  if swift test --package-path Packages/VelaKit --scratch-path "$swift_scratch" > "$log" 2>&1; then
    # Each test target's run starts with "Test run started." and ends with
    # "Test run with N tests in M suites passed". A run with no end means the
    # test process quit early (a test exited it), which swift test can still
    # report as success. Name the last test each such run started.
    unfinished=$(sed $'s/\x1b\\[[0-9;]*m//g' "$log" | awk '
      /Test run started/ { if (open) print (last == "" ? "?" : last); open = 1; last = ""; next }
      /Test run with [0-9]+ tests? in [0-9]+ suites? (passed|failed)/ { open = 0; next }
      /Test .* started\.$/ { last = $0; sub(/^.*Test /, "", last); sub(/ started\.$/, "", last) }
      END { if (open) print (last == "" ? "?" : last) }' | paste -sd , - | sed 's/,/, /g')
    summary=$(awk '/Test run with [0-9]+ tests? in [0-9]+ suites? passed/ {
        for (i = 1; i < NF; i++) { if ($i == "with") tests += $(i + 1); if ($i == "in") suites += $(i + 1) }
      } END { if (tests) print tests " tests in " suites " suites" }' "$log")
    if [[ -n "$unfinished" ]]; then
      check_fail "Package tests" "swift test passed, but a test run never finished; the last test it started: $unfinished" \
        "That test (or one near it) ends the test process early, so the tests after it never ran. Fix it, then run swift test again (output in ${log#$PWD/})."
    else
      check_pass "Package tests" "${summary:+$summary passed}"
    fi
  else
    check_fail "Package tests" "swift test failed" \
      "Fix the failing tests (the output above; all of it in ${log#$PWD/}), then commit, push and wait for CI."
    swift_failures "$log" | indent
  fi
}

# ---------------------------------------------------------------- website
check_website() {
  check_section "Website"
  local log="$work/website.log" summary
  if ! command -v npm >/dev/null; then
    check_fail "Website" "npm isn't installed" "Install Node 20 or later (nvm install 22)."
    return
  fi
  print "    Building the website…"
  if (
    cd website
    if [[ ! -d node_modules ]]; then npm ci; fi
    npm run docs:build && npm run docs:check
  ) > "$log" 2>&1; then
    summary=$(grep '^check-site:' "$log" | tail -n 1 || true)
    check_pass "Website" "builds; ${summary#check-site: }"
  else
    check_fail "Website" "the website doesn't build or check out" \
      "Fix what the log says (${log#$PWD/}), then check with: (cd website && npm run docs:build && npm run docs:check)."
    sed $'s/\x1b\\[[0-9;]*m//g' "$log" | grep -E 'error|Error|check-site:|generate:|✖' | head -n 20 | indent || true
    if ! grep -qE 'error|Error|check-site:|generate:|✖' "$log"; then tail -n 15 "$log" | indent; fi
  fi
}

# ---------------------------------------------------------------- media sites
check_media_sites() {
  check_section "Media sites"
  if (( ! media_check )); then
    if [[ "$media_check_option" == 0 ]]; then
      check_skip "Media sites" "--skip-media-check"
    else
      check_skip "Media sites" "ad hoc build (add --media-check to check)"
    fi
    return
  fi
  # Every live sample in MediaSites.swift must still resolve against the real
  # site (docs/RELEASING.md, "When the media check fails").
  local failed_sites="$tmp/failed-sites" broken
  if scripts/check-media-sites.sh --scratch-path "$swift_scratch" --failed-sites-file "$failed_sites"; then
    check_pass "Media sites" "every site works"
  else
    broken=$(paste -sd , - < "$failed_sites" 2>/dev/null | sed 's/,/, /g' || true)
    check_fail "Media sites" "the check failed${broken:+ for $broken}" \
      "Update the site's sample or fix its resolver (see \"When the media check fails\" in docs/RELEASING.md), or rerun with --skip-media-check."
  fi
}

check_git
check_version
check_ci
check_adult_domains
check_generated
check_tests
check_website
check_media_sites

# With --results, the caller prints the summary and the verdict.
if [[ -n "$results" ]]; then
  if (( release_checks_failed )); then exit 1; fi
  exit 0
fi
print_check_summary "$RELEASE_CHECKS_RESULTS"
print
if (( release_checks_failed )); then
  print -P "%F{red}✗ $release_checks_failed preflight check(s) failed. Fix them and run the checks again.%f"
  exit 1
fi
if (( adhoc )); then
  print -P "%F{green}✓ The checks for an ad hoc build passed (git, version and CI aren't checked for one).%f"
else
  print -P "%F{green}✓ Ready to release Vela ${version:-?} (${build_number:-?}).%f"
fi
