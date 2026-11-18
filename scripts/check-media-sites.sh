#!/bin/zsh
# Checks that the media sites Vela supports still work: every live sample link
# in Packages/VelaKit/Sources/VelaMedia/MediaSites.swift is resolved against the
# real site, the way Vela resolves it, and a report per site is printed.
#
#   scripts/check-media-sites.sh                          # every site
#   scripts/check-media-sites.sh --site tenor --site giphy
#   scripts/check-media-sites.sh --list                   # the sites and their sample links
#
# Options:
#   --site <id>                  Check only this site; repeat for more. The ids are in
#                                MediaSites.swift (or see --list).
#   --list                       List the sites, their link forms and sample links.
#   --verbose                    Show swift test's output as it runs.
#   --scratch-path <dir>         SwiftPM's build folder (default: Packages/VelaKit/.build).
#   --failed-sites-file <file>   Also write the names of failing sites there, one per line.
#   --dry-run                    Say what would run, and run nothing. VELA_MEDIA_CHECK_DRY_RUN=1
#                                does the same (for the pre-push hook).
#
# It runs the LiveMediaSiteTests suite with VELA_LIVE_MEDIA_TESTS=1. The report
# is also saved to build/media-sites/report.txt, and swift test's output to
# build/media-sites/swift-test.log. In GitHub Actions it's added to the run's
# summary too.
#
# Exits 0 when every site works, 1 when one doesn't or the checks couldn't run,
# and 2 for an unknown option.
set -euo pipefail
script="${0:A}"
cd "${0:A:h}/.."

sites=()
scratch=""
failed_file=""
verbose=0
list=0
dry_run=0
[[ "${VELA_MEDIA_CHECK_DRY_RUN:-0}" == 1 ]] && dry_run=1

usage() { sed -n '2,/^set -euo/p' "$script" | sed -e '$d' -e 's/^# \{0,1\}//'; }
needs_value() { [[ $# -ge 2 && -n "$2" ]] || { print -u2 -r -- "$1 needs a value"; exit 2; } }

while (( $# )); do
  case "$1" in
    --site) needs_value "$@"; sites+=("$2"); shift 2 ;;
    --site=*) sites+=("${1#*=}"); shift ;;
    --scratch-path) needs_value "$@"; scratch="$2"; shift 2 ;;
    --failed-sites-file) needs_value "$@"; failed_file="$2"; shift 2 ;;
    --verbose) verbose=1; shift ;;
    --list) list=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 -r -- "Unknown option: $1 (see --help)"; exit 2 ;;
  esac
done

swift_args=(--package-path Packages/VelaKit)
[[ -n "$scratch" ]] && swift_args+=(--scratch-path "$scratch")

if (( list )); then
  exec swift run "${swift_args[@]}" -q vela-media-tool list
fi

out="$PWD/build/media-sites"
report="$out/report.txt"
log="$out/swift-test.log"
environment=(VELA_LIVE_MEDIA_TESTS=1 "VELA_MEDIA_REPORT=$report")
(( ${#sites} )) && environment+=("VELA_LIVE_MEDIA_SITES=${(j:,:)sites}")
command=(env "${environment[@]}" swift test "${swift_args[@]}" --filter LiveMediaSiteTests)

if (( dry_run )); then
  print "check-media-sites: dry run; would run:"
  print "    ${(j: :)${(q-)command[@]}}"
  print "  and print the report from ${report#$PWD/}"
  exit 0
fi

mkdir -p "$out"
: > "$report"
[[ -n "$failed_file" ]] && : > "$failed_file"

print -P "%F{magenta}==>%f %BChecking media sites against the real sites%b"
print "    Builds the package's tests first, so the first run takes a few minutes."
started=$SECONDS
test_status=0
if (( verbose )); then
  "${command[@]}" 2>&1 | tee "$log" || test_status=$?
else
  "${command[@]}" > "$log" 2>&1 || test_status=$?
fi

if [[ ! -s "$report" ]]; then
  print -P "%F{red}error:%f no site was checked." >&2
  if (( test_status )); then
    # A build error anywhere in the package's tests stops the run; show those first.
    errors=$(sed $'s/\x1b\\[[0-9;]*m//g' "$log" | grep -E '^/.*: error: ' | sort -u | head -n 15 || true)
    if [[ -n "$errors" ]]; then
      print "The package's tests don't build (full output in ${log#$PWD/}):" >&2
      print -r -- "$errors" >&2
    else
      print "swift test failed (exit $test_status); the end of ${log#$PWD/}:" >&2
      tail -n 30 "$log" >&2
    fi
  fi
  (( ${#sites} )) && print "Is ${(j:, :)sites} a site id? See: scripts/check-media-sites.sh --list" >&2
  exit 1
fi

print
cat "$report"

failed=(${(f)"$(sed -n 's/^FAIL  \(.*\) ([0-9]* links*)$/\1/p' "$report")"})
passed=$(grep -c '^PASS' "$report" || true)
skipped=$(grep -c '^SKIP' "$report" || true)

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    print "### Media sites"
    print
    if (( ${#failed} )); then print "**Broken:** ${(j:, :)failed}"; else print "Every site works."; fi
    print
    print '```'
    cat "$report"
    print '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi

print
elapsed=$(( SECONDS - started ))
if (( ${#failed} )); then
  [[ -n "$failed_file" ]] && print -l -- "${failed[@]}" > "$failed_file"
  print -P "%F{red}✗ ${#failed} of $(( passed + ${#failed} )) sites failed: ${(j:, :)failed}%f"
  print "  Each failure above says what went wrong. If a site changed, update its sample or its resolver;"
  print "  see \"When the media check fails\" in docs/RELEASING.md. The full report is in ${report#$PWD/}."
  exit 1
elif (( test_status )); then
  print -P "%F{red}✗ The checks passed, but swift test failed (exit $test_status); see ${log#$PWD/}.%f"
  exit 1
fi
summary="✓ All $passed sites work"
(( skipped )) && summary+=" ($skipped without live samples)"
print -P "%F{green}$summary.%f (${elapsed}s)"
