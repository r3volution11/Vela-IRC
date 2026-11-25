#!/bin/zsh
# Runs the message list fuzz test (MessageListFuzzTests) over and over, a few
# at a time, and catches any run that freezes.
#
#   scripts/fuzz-message-list.sh                 # 1 hour, 3 at a time
#   scripts/fuzz-message-list.sh --hours 6 --workers 3
#   scripts/fuzz-message-list.sh --stress        # only the steps that change the list's size, faster
#   scripts/fuzz-message-list.sh --no-build --out ~/fuzz
#
# Each run drives the real message list for 45 seconds in each of four
# presets (about three minutes) in an offscreen window: it never takes the
# focus. A run that writes nothing for 30 seconds is sampled (sample(1)),
# then watched for 90 seconds more: if it goes on, it was a stall; if not, it
# froze, and it's stopped. Every run adds a line to <out>/summary.txt:
#
#   w2-14 03:12:09 ok seeds_done=4 secs=184
#   w1-15 03:13:40 HUNG seeds_done=1 secs=163 seed=3 classic lastop=518 kind 10
#
# The logs and samples of runs that didn't end well stay in <out>; the
# others are deleted. On macOS 26 SwiftUI's lazy stack could freeze the
# list for good (MessageListView's sizeChangeAnchor); run this there (a VM)
# after changing how the list scrolls. Options:
#
#   --hours N      How long to keep starting runs (default 1).
#   --workers N    Runs at a time (default 3).
#   --stress       VELA_LIST_FUZZ_ONLY=0,1,2,3,4,5,10,11,12,13 and
#                  VELA_LIST_FUZZ_PAUSE=20: the mix that froze macOS 26 most.
#   --out DIR      Where the summary, logs and samples go (default
#                  build/list-fuzz).
#   --no-build     Use the test bundle as last built.
#
# Other VELA_LIST_FUZZ_* settings in the environment pass through (see
# MessageListFuzzTests.swift).

set -u
repo=${0:A:h:h}
package=$repo/Packages/VelaKit
hours=1
workers=3
out=$repo/build/list-fuzz
build=1
while (( $# )); do
  case $1 in
    --hours) hours=$2; shift 2 ;;
    --workers) workers=$2; shift 2 ;;
    --stress) export VELA_LIST_FUZZ_ONLY=0,1,2,3,4,5,10,11,12,13 VELA_LIST_FUZZ_PAUSE=20; shift ;;
    --out) out=$2; shift 2 ;;
    --no-build) build=0; shift ;;
    *) print -u2 "unknown option: $1"; exit 2 ;;
  esac
done

if (( build )); then
  swift build --package-path $package --build-tests > /dev/null || { print -u2 "build failed"; exit 1; }
fi
developer=$(xcode-select -p)
helper=$developer/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper
bundle=$package/.build/out/Products/Debug/VelaUITests.xctest/Contents/MacOS/VelaUITests
[[ -x $helper ]] || { print -u2 "no swiftpm-testing-helper in $developer"; exit 1; }
[[ -f $bundle ]] || { print -u2 "no test bundle at $bundle"; exit 1; }
# As swift test sets them, so the bundle finds XCTest and Testing.
export DYLD_FRAMEWORK_PATH=$developer/Platforms/MacOSX.platform/Developer/Library/Frameworks
export DYLD_LIBRARY_PATH=$developer/Platforms/MacOSX.platform/Developer/usr/lib
export VELA_LIST_FUZZ=1

mkdir -p $out
summary=$out/summary.txt
end=$(( $(date +%s) + hours * 3600 ))
print "start $(date '+%Y-%m-%d %H:%M:%S') hours=$hours workers=$workers only=${VELA_LIST_FUZZ_ONLY:-all} pause=${VELA_LIST_FUZZ_PAUSE:-60}" >> $summary

worker() {
  local w=$1 i=0
  while (( $(date +%s) < end )); do
    i=$(( i + 1 ))
    local name=w$w-$i
    local log=$out/$name.log
    local t0=$(date +%s)
    $helper --test-bundle-path $bundle --skip-build --filter MessageListFuzzTests $bundle --testing-library swift-testing > $log 2>&1 &
    local pid=$! state=ok note=""
    while kill -0 $pid 2> /dev/null; do
      sleep 2
      local now=$(date +%s)
      if (( now - t0 > 400 )); then state=timeout; break; fi
      if (( now - t0 > 40 && now - $(stat -f %m $log) > 30 )); then
        sample $pid 8 -mayDie -file $out/$name.sample.txt > /dev/null 2>&1
        local size=$(stat -f %z $log) going=0
        for _ in {1..45}; do
          sleep 2
          kill -0 $pid 2> /dev/null || { going=1; break }
          (( $(stat -f %z $log) != size )) && { going=1; break }
        done
        if (( going )); then
          state=stall
          note+=" stalled@$(( now - t0 ))s"
          continue
        fi
        state=HUNG
        note+=" seed=$(grep -a 'start seed' $log | tail -1 | sed 's/.*start seed //') lastop=$(grep -a 'FUZZ.* op ' $log | tail -1 | sed 's/.* op //' | cut -c1-40)"
        break
      fi
    done
    if kill -0 $pid 2> /dev/null; then
      kill $pid 2> /dev/null
      sleep 3
      kill -9 $pid 2> /dev/null
    fi
    wait $pid 2> /dev/null
    local seeds=$(grep -ac 'done seed' $log)
    [[ $state == ok ]] && ! grep -aq 'Test run with' $log && state=EXITED
    print "$name $(date '+%H:%M:%S') $state seeds_done=$seeds secs=$(( $(date +%s) - t0 ))$note" >> $summary
    [[ $state == ok ]] && rm -f $log $out/$name.sample.txt
  done
}

for w in {1..$workers}; do
  worker $w &
  sleep 7
done
wait
print "end $(date '+%Y-%m-%d %H:%M:%S')" >> $summary
print "$(grep -c ' ok ' $summary) ok, $(grep -c ' HUNG ' $summary) froze, $(grep -c ' stall ' $summary) stalled, $(grep -cE ' (EXITED|timeout) ' $summary) ended early; see $summary"
