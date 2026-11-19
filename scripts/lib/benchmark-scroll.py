#!/usr/bin/env python3
# Summarizes scroll benchmark runs and compares them with the baseline. Used
# by scripts/benchmark-scroll.sh (run that, not this):
#
#   benchmark-scroll.py summarize <summary.json> <run.json>...
#   benchmark-scroll.py compare <summary.json> <baseline.json> [--check]
#   benchmark-scroll.py baseline <summary.json> <baseline.json> [commit]
#
# A run is the JSON the app writes (`--demo --scroll-benchmark`, see
# ScrollBenchmark.swift). A summary has the median, lowest and highest value
# of every metric, per mode (the run's --bench-label: normal, lowend) and
# scenario. The baseline is a summary without the per-run spread.
#
# compare prints each budgeted metric next to the baseline. With --check it
# exits 1 when one is over budget (see BUDGETS), 0 otherwise, and 3 when the
# baseline was recorded on another kind of Mac or display, or with another
# layout or window size, since the numbers wouldn't compare.

import json
import statistics
import sys

# Every per-scenario number worth keeping.
METRICS = [
    "durationS", "activeS", "distancePt", "frames", "movedFrames", "ticksPerS",
    "frameP50Ms", "frameP95Ms", "frameP99Ms", "frameMaxMs",
    "framesOver1_5x", "framesOver2x", "hitchMsPerS",
    "cpuMsPerS", "cpuMsPer1000Pt", "cpuMsPerMovedFrame", "mainThreadCpuMsPerS", "mainBusyPct",
    "instructionsMPer1000Pt", "instructionsMPerMovedFrame", "footprintPeakMB",
]

# The budgets: (scenarios, metric, how much worse than the baseline it may
# get as a ratio, an absolute allowance on top for numbers near zero, and
# whether going over fails the check: True, False, or the modes where it
# does). A number is over budget when
#     median > baseline * ratio + allowance
#
# Only the sweeps' costs fail the check. A sweep moves the list exactly 48
# points every frame, so the work it does doesn't depend on how fast frames
# come: on an M5 Pro, its instructions per frame differed by 2% between
# runs on a quiet Mac and by up to 8% while other apps were building. Its
# CPU time per frame differed by up to 30% then (the same work runs slower
# on a busy Mac), so that budget is wider, and only Macs without instruction
# counts lean on it.
# Under taskpolicy -b (lowend) CPU time swings by a third between runs, so
# there it's only reported.
# A real regression is bigger than either: a body that re-evaluates every
# frame cost 30% more instructions, accessibility 110% more, the invisible
# copy of each message's text 5%. Frame times and hitches swing by half or
# more between runs whenever anything else on the Mac wakes up, so they're
# reported, never failed on.
BUDGETS = [
    (("sweep", "sweep-a11y"), "instructionsMPerMovedFrame", 1.15, 0, True),
    (("sweep", "sweep-a11y"), "cpuMsPerMovedFrame", 1.40, 0.3, ("normal",)),
    (("medium", "fling"), "hitchMsPerS", 1.5, 10, False),
    (("medium", "fling"), "frameP95Ms", 1.35, 4, False),
]
MEMORY_BUDGET = ("peakMB", 1.25, 25)


def load(path):
    with open(path) as handle:
        return json.load(handle)


def number(value):
    return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def stats(values):
    values = [v for v in values if v is not None]
    if not values:
        return None
    return {"median": statistics.median(values), "min": min(values), "max": max(values), "runs": len(values)}


def scenario_key(scenario):
    """A scenario's name, marked when an accessibility client had SwiftUI
    build accessibility (which costs about twice as much) where the scenario
    doesn't say so itself; None for one where that started midway."""
    state = scenario.get("accessibility", "off")
    if state == "turned on":
        return None
    name = scenario["name"]
    if state == "on" and not name.endswith("-a11y"):
        name += "-a11y"
    return name


def summarize(output, paths):
    runs = [load(path) for path in paths]
    runs = [run for run in runs if "error" not in run and run.get("scenarios")]
    if not runs:
        sys.exit("benchmark-scroll: no complete runs to summarize")
    modes = {}
    for run in runs:
        modes.setdefault(run.get("label") or "normal", []).append(run)
    summary = {
        "schema": 1,
        "machine": runs[0].get("machine", {}),
        "display": runs[0].get("display", {}),
        "config": {k: v for k, v in runs[0].get("config", {}).items() if k != "arguments"},
        "app": runs[0].get("app", {}),
        "date": runs[-1].get("date"),
        "modes": {},
    }
    for mode, mode_runs in modes.items():
        names = []
        for run in mode_runs:
            for scenario in run["scenarios"]:
                key = scenario_key(scenario)
                if key and key not in names:
                    names.append(key)
        scenarios = {}
        for name in names:
            rows = [s for run in mode_runs for s in run["scenarios"] if scenario_key(s) == name]
            scenarios[name] = {
                metric: stats([number(row.get(metric)) for row in rows])
                for metric in METRICS
                if stats([number(row.get(metric)) for row in rows]) is not None
            }
        summary["modes"][mode] = {
            "runs": len(mode_runs),
            "scenarios": scenarios,
            "memory": {
                key: stats([number(run.get("memory", {}).get(key)) for run in mode_runs])
                for key in ("peakMB", "endMB")
            },
            "appActive": any(run.get("appActive", False) for run in mode_runs),
            "lowPowerMode": any(run.get("lowPowerMode", False) for run in mode_runs),
            "thermalState": max(run.get("thermalState", 0) for run in mode_runs),
        }
    with open(output, "w") as handle:
        json.dump(summary, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print_summary(summary)


def spread(entry):
    if not entry or not entry["median"]:
        return 0
    return (entry["max"] - entry["min"]) / entry["median"] * 100


def print_summary(summary):
    columns = [
        ("p50", "frameP50Ms", 1), ("p95", "frameP95Ms", 1), ("p99", "frameP99Ms", 1),
        (">2x", "framesOver2x", 0), ("hitch/s", "hitchMsPerS", 1), ("CPU/s", "cpuMsPerS", 0),
        ("CPU/1kpt", "cpuMsPer1000Pt", 1), ("CPU/frame", "cpuMsPerMovedFrame", 2),
        ("Minstr/frame", "instructionsMPerMovedFrame", 1), ("busy%", "mainBusyPct", 0),
    ]
    machine = summary.get("machine", {})
    display = summary.get("display", {})
    print(f"\n{machine.get('cpu', '?')} · {machine.get('model', '?')} · {display.get('refreshHz', '?')} Hz · "
          f"{summary['config'].get('layout', '?')} layout, {summary['config'].get('mix', '?')} mix")
    print("Medians of the runs; ± is the spread between runs (highest minus lowest, as % of the median).")
    for mode, data in summary["modes"].items():
        notes = []
        if data.get("appActive"):
            notes.append("the app had the focus at some point (it shouldn't)")
        if data.get("lowPowerMode"):
            notes.append("Low Power Mode was on")
        if data.get("thermalState", 0) >= 2:
            notes.append("the Mac was hot (thermal state serious or worse)")
        print(f"\n{mode} ({data['runs']} runs)" + (f" — {', '.join(notes)}" if notes else ""))
        print("  " + "scenario".ljust(11) + "".join(title.rjust(13) for title, _, _ in columns))
        for name, metrics in data["scenarios"].items():
            row = "  " + name.ljust(11)
            for _, key, decimals in columns:
                entry = metrics.get(key)
                if entry is None:
                    row += "-".rjust(13)
                    continue
                text = f"{entry['median']:.{decimals}f}±{spread(entry):.0f}%"
                row += text.rjust(13)
            print(row)
        peak = data["memory"].get("peakMB")
        end = data["memory"].get("endMB")
        if peak and end:
            print(f"  memory: peak {peak['median']:.0f} MB ±{spread(peak):.0f}%, at the end {end['median']:.0f} MB")


def same_setup(summary, baseline):
    reasons = []
    for key in ("cpu", "model"):
        if summary.get("machine", {}).get(key) != baseline.get("machine", {}).get(key):
            reasons.append(f"{key} {baseline.get('machine', {}).get(key)!r} → {summary.get('machine', {}).get(key)!r}")
    if summary.get("display", {}).get("refreshHz") != baseline.get("display", {}).get("refreshHz"):
        reasons.append(f"display {baseline.get('display', {}).get('refreshHz')} Hz → {summary.get('display', {}).get('refreshHz')} Hz")
    for key in ("layout", "mix", "window", "lines"):
        if summary.get("config", {}).get(key) != baseline.get("config", {}).get(key):
            reasons.append(f"{key} {baseline.get('config', {}).get(key)!r} → {summary.get('config', {}).get(key)!r}")
    return reasons


def compare(summary_path, baseline_path, check):
    summary = load(summary_path)
    baseline = load(baseline_path)
    if baseline.get("placeholder") or not baseline.get("modes"):
        print(f"\nNo baseline recorded yet ({baseline_path} is a placeholder), so nothing is checked. "
              "Record one with --update-baseline.")
        return 3 if check else 0
    differences = same_setup(summary, baseline)
    if differences:
        print(f"\nThe baseline ({baseline.get('date', '?')}) was recorded on a different setup: {'; '.join(differences)}.")
        print("Its numbers don't compare with these, so nothing is checked. Record one here with --update-baseline.")
        return 3 if check else 0
    failures = []
    print(f"\nCompared with the baseline from {baseline.get('date', '?')} (app {baseline.get('app', {}).get('version', '?')}"
          f" build {baseline.get('app', {}).get('build', '?')}):")
    for mode, data in summary["modes"].items():
        base_mode = baseline.get("modes", {}).get(mode)
        if not base_mode:
            print(f"  {mode}: not in the baseline")
            continue
        print(f"  {mode}")
        for scenarios, metric, ratio, allowance, gates in BUDGETS:
            for name in scenarios:
                now = data["scenarios"].get(name, {}).get(metric)
                then = base_mode.get("scenarios", {}).get(name, {}).get(metric)
                if not now or not then:
                    continue
                now_value, then_value = now["median"], then["median"]
                if metric.startswith("instructions") and (now_value == 0 or then_value == 0):
                    continue   # No instruction counts on this Mac.
                limit = then_value * ratio + allowance
                change = (now_value - then_value) / then_value * 100 if then_value else 0
                over = now_value > limit
                gated = gates is True or (isinstance(gates, tuple) and mode in gates)
                mark = ("OVER" if gated else "high") if over else "ok"
                print(f"    {mark:4}  {name:10} {metric:26} {now_value:10.2f}  baseline {then_value:9.2f}  "
                      f"{change:+6.0f}%  ({'budget' if gated else 'reported only, budget'} {limit:.2f})")
                if over and gated:
                    failures.append(f"{mode} {name} {metric} {now_value:.2f} > {limit:.2f} (baseline {then_value:.2f})")
        key, ratio, allowance = MEMORY_BUDGET
        now = data.get("memory", {}).get(key)
        then = base_mode.get("memory", {}).get(key)
        if now and then:
            limit = then["median"] * ratio + allowance
            over = now["median"] > limit
            change = (now["median"] - then["median"]) / then["median"] * 100
            print(f"    {'OVER' if over else 'ok':4}  {'memory':10} {key:26} {now['median']:10.0f}  baseline {then['median']:9.0f}  "
                  f"{change:+6.0f}%  (budget {limit:.0f})")
            if over:
                failures.append(f"{mode} memory {key} {now['median']:.0f} MB > {limit:.0f} MB")
    if failures:
        print("\nOver budget:\n  " + "\n  ".join(failures))
        return 1 if check else 0
    print("\nEverything is within budget.")
    return 0


def write_baseline(summary_path, baseline_path, commit=None):
    summary = load(summary_path)
    if commit:
        summary["commit"] = commit
    # Medians only: the spread belongs to one recording.
    for data in summary["modes"].values():
        for metrics in data["scenarios"].values():
            for metric, entry in metrics.items():
                metrics[metric] = {"median": entry["median"]}
        for key, entry in data["memory"].items():
            if entry:
                data["memory"][key] = {"median": entry["median"]}
    summary["note"] = "Medians of scripts/benchmark-scroll.sh runs. Rewrite with scripts/benchmark-scroll.sh --update-baseline."
    with open(baseline_path, "w") as handle:
        json.dump(summary, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(f"\nWrote {baseline_path}")


def main(argv):
    if len(argv) >= 3 and argv[0] == "summarize":
        summarize(argv[1], argv[2:])
        return 0
    if len(argv) >= 3 and argv[0] == "compare":
        return compare(argv[1], argv[2], "--check" in argv[3:])
    if len(argv) in (3, 4) and argv[0] == "baseline":
        write_baseline(argv[1], argv[2], argv[3] if len(argv) == 4 else None)
        return 0
    sys.stderr.write(__doc__ or "usage: see the comment at the top of this file\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
