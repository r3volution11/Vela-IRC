#!/bin/zsh
# Measures how smoothly, and how cheaply, Vela scrolls a big channel, and
# compares the numbers with the committed baseline, benchmarks/scroll-baseline.json.
#
#   scripts/benchmark-scroll.sh                     # build, 3 runs per mode, compare
#   scripts/benchmark-scroll.sh --update-baseline   # the same, then record the medians as the baseline
#   scripts/benchmark-scroll.sh --runs 5 --modes normal
#   scripts/benchmark-scroll.sh --no-build -- --bench-scenarios fling --preset classic
#
# It builds an optimized Release copy of Vela for this Mac's architecture in
# build/benchmark, with a bundle id of its own (io.github.r3volution11.Vela.bench,
# named "Vela Bench"), so it never touches your Vela: it has its own sandbox
# container, settings and Keychain, runs in demo mode, and gets every link
# preview and picture from local stand-ins, never the network. The copy is a
# background app (LSUIElement: no Dock icon or menu bar, never brought
# forward at launch). It's started from its executable rather than with open,
# so LaunchServices can't hand the run to another copy, and your running Vela
# is left alone. The copy is unregistered from LaunchServices when the script
# ends.
#
# Each run takes about 100 seconds: a window opens in the middle of the
# display with the menu bar, scrolls a 2,000-line channel the way a person does
# with a trackpad, writes its numbers and quits. You won't see it or notice
# it: the window is on screen and draws as usual, but it's fully transparent
# and lets clicks through, Vela Bench is never activated, nothing is clicked,
# and the pointer stays where it is, so you can keep working. (To watch a run,
# pass -- --bench-window visible.) Busy apps make the numbers noisier, so
# lighter work is better meanwhile. Plug in the power, and turn off Low Power
# Mode.
# See ScrollBenchmark.swift for the scenarios and what each number means.
#
# Modes:
#   normal   As is.
#   lowend   Under taskpolicy -b: background priority, on the slowest cores,
#            throttled. On an M5 Pro that runs CPU-bound code about 2.9 times
#            slower, a stand-in for the slowest Macs Vela supports (2019-2020
#            Intel MacBook Pros and iMacs, an 8 GB M1). taskpolicy -c background
#            slows it down too, but by anywhere from 1.6 to 3 times.
#
# Options:
#   --runs <n>          Runs per mode (default 3). Medians are reported, with
#                       the spread between runs.
#   --modes <list>      normal, lowend, or normal,lowend (the default).
#   --update-baseline   Record the medians in benchmarks/scroll-baseline.json.
#   --check             Exit 1 when a number is over budget (see BUDGETS in
#                       scripts/lib/benchmark-scroll.py), and 3 when there's
#                       no baseline from this kind of Mac and display to
#                       compare with. scripts/release-preflight.sh uses it.
#   --baseline <file>   Compare with this file instead.
#   --no-build          Use the copy built last time.
#   --out <dir>         Where the runs go (default: build/benchmark/results/<date-time>).
#   -- <arguments>      Passed to the app, e.g. --bench-scenarios slow,medium,
#                       --bench-mix text (no links), --preset classic,
#                       --set chat.showAvatars=true, --bench-screen 1 (another
#                       display). --bench-pointer list moves your pointer over
#                       the list for each run (and back), which the script warns
#                       about first; without focus the window gets no hover
#                       events either way.
#
# Output: each run's JSON and summary (runs/), and summary.json with the
# medians, in the output folder. Logs of the build: build/benchmark/build.log.
#
# Exits 0 when the runs worked (and, with --check, everything is within
# budget), 1 when a run failed or a number is over budget, 2 for an unknown
# option, and 3 (with --check) when there's nothing to compare with.
set -euo pipefail
script="${0:A}"
cd "${0:A:h}/.."

runs=3
modes=(normal lowend)
update_baseline=0
check=0
build=1
baseline=benchmarks/scroll-baseline.json
out=""
app_args=()

usage() { sed -n '2,/^set -euo/p' "$script" | sed -e '$d' -e 's/^# \{0,1\}//'; }

while (( $# )); do
  case "$1" in
    --runs)
      [[ $# -ge 2 && "$2" == <1-> ]] || { print -u2 "--runs needs a number"; exit 2; }
      runs=$2; shift 2 ;;
    --modes)
      [[ $# -ge 2 ]] || { print -u2 "--modes needs a list"; exit 2; }
      modes=("${(@s:,:)2}"); shift 2 ;;
    --update-baseline) update_baseline=1; shift ;;
    --check) check=1; shift ;;
    --baseline)
      [[ $# -ge 2 ]] || { print -u2 "--baseline needs a file"; exit 2; }
      baseline=$2; shift 2 ;;
    --no-build) build=0; shift ;;
    --out)
      [[ $# -ge 2 ]] || { print -u2 "--out needs a folder"; exit 2; }
      out=${2:A}; shift 2 ;;
    --) shift; app_args=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 -r -- "Unknown option: $1 (see --help)"; exit 2 ;;
  esac
done
for mode in $modes; do
  [[ $mode == normal || $mode == lowend ]] || { print -u2 "Unknown mode: $mode (normal or lowend)"; exit 2; }
done
command -v python3 >/dev/null || { print -u2 "python3 is needed (it comes with Xcode's command line tools)."; exit 1; }

bundle_id=io.github.r3volution11.Vela.bench
derived="$PWD/build/benchmark/DerivedData"
app="$derived/Build/Products/Release/Vela.app"
exe="$app/Contents/MacOS/Vela"
container_tmp="$HOME/Library/Containers/$bundle_id/Data/tmp"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
out=${out:-$PWD/build/benchmark/results/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$out/runs" "$container_tmp"

step() { print -P "%F{magenta}==>%f %B$1%b"; }

# Only ever this copy: never build/Vela.app or an installed Vela.
cleanup() {
  pkill -f "^$exe" 2>/dev/null || true
  # LaunchServices can note the last run a moment after it quits.
  sleep 1
  [[ -d "$app" ]] && "$lsregister" -u "$app" 2>/dev/null || true
}
trap cleanup EXIT

if (( build )); then
  step "Building Vela Bench (Release, $(uname -m))"
  if ! xcodebuild \
      -project Vela.xcodeproj \
      -scheme Vela \
      -configuration Release \
      -destination 'platform=macOS' \
      -derivedDataPath "$derived" \
      ONLY_ACTIVE_ARCH=YES \
      PRODUCT_BUNDLE_IDENTIFIER=$bundle_id \
      INFOPLIST_KEY_CFBundleDisplayName="Vela Bench" \
      INFOPLIST_KEY_LSUIElement=YES \
      -quiet build > build/benchmark/build.log 2>&1; then
    grep -E ': error: ' build/benchmark/build.log | sort -u | head -n 20 >&2 || tail -n 20 build/benchmark/build.log >&2
    print -u2 "The build failed; see build/benchmark/build.log."
    exit 1
  fi
fi
[[ -x "$exe" ]] || { print -u2 "No benchmark build in $app; run without --no-build."; exit 1; }
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") == $bundle_id ]] \
  || { print -u2 "$app isn't the benchmark build ($bundle_id); run without --no-build."; exit 1; }
# Xcode registers what it builds with LaunchServices. Unregistered, the copy
# usually goes unnoticed by accessibility clients (window managers and the
# like), so runs start with SwiftUI's accessibility off; each scenario says
# whether it was, and sweep-a11y measures it on.
"$lsregister" -u "$app" 2>/dev/null || true

total=$(( runs * ${#modes} ))
step "Running $total runs, about $(( (total * 105 + 59) / 60 )) minutes"
print "    Vela Bench's window is invisible and never takes the focus; busy apps make the numbers noisier."
if [[ " ${app_args[*]} " == *" --bench-pointer list "* ]]; then
  print -P "    %F{yellow}--bench-pointer list: each run moves your pointer over its window, and back when it's done.%f"
fi
failed=0
for mode in $modes; do
  for (( i = 1; i <= runs; i++ )); do
    name="$mode-$i"
    result="$container_tmp/scroll-benchmark-$$-$name.json"
    rm -f "$result" "${result:r}.txt"
    command=("$exe" --demo --scroll-benchmark --bench-output "$result" --bench-label "$mode" "${app_args[@]}")
    [[ $mode == lowend ]] && command=(taskpolicy -b "${command[@]}")
    print "    $name"
    # A launch can register the copy again; each run starts unregistered.
    "$lsregister" -u "$app" 2>/dev/null || true
    "${command[@]}" > "$out/runs/$name.txt" 2> "$out/runs/$name.log" || true
    if [[ -f "$result" ]]; then
      mv "$result" "$out/runs/$name.json"
      rm -f "${result:r}.txt"
      if grep -q '"error"' "$out/runs/$name.json"; then
        failed=$(( failed + 1 ))
        print -u2 "    $name failed: $(grep -v '^$' "$out/runs/$name.txt" | tail -n 1)"
      else
        grep -v '^$' "$out/runs/$name.txt" | sed -n '2,$p' | sed 's/^/      /'
      fi
    else
      failed=$(( failed + 1 ))
      print -u2 "    $name wrote no results; see $out/runs/$name.log"
    fi
    sleep 3
  done
done

results=("$out"/runs/*.json(N))
if (( ${#results} == 0 )); then
  print -u2 "No run finished."
  exit 1
fi
step "Summary"
python3 scripts/lib/benchmark-scroll.py summarize "$out/summary.json" "${results[@]}"
print "\nResults: ${out#$PWD/}"

exit_status=0
if (( update_baseline )); then
  if (( failed )); then
    print -u2 "$failed run(s) failed, so the baseline wasn't updated."
    exit 1
  fi
  mkdir -p "${baseline:h}"
  commit=$(git rev-parse --short HEAD)
  [[ -n "$(git status --porcelain -- Packages Vela Vela.xcodeproj)" ]] && commit+=" with uncommitted changes"
  python3 scripts/lib/benchmark-scroll.py baseline "$out/summary.json" "$baseline" "$commit"
elif [[ -f "$baseline" ]]; then
  compare_args=()
  (( check )) && compare_args+=(--check)
  python3 scripts/lib/benchmark-scroll.py compare "$out/summary.json" "$baseline" "${compare_args[@]}" || exit_status=$?
else
  print "\nNo baseline yet ($baseline). Record one with --update-baseline."
  (( check )) && exit_status=3
fi
(( failed )) && exit_status=1
exit $exit_status
