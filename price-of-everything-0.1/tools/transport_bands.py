#!/usr/bin/env python3
"""Report transport cost as a share of revenue, banded by turn.

The question this answers: does freight stay a live cost across a whole game, or does it
collapse to nothing once a player integrates? Measured 2026-08-09, it collapses — an
integrated build pays 11.3% of revenue over turns 1-30 and 0.3% by turn 100, because the
seaport fee is charged per GOOD per turn while revenue scales with VOLUME. A distributed
build (the tutorial chain) pays 13% throughout. The dispersion across playstyles is wider
than the dispersion across time, which is what makes this worth measuring rather than
reasoning about.

Owner's target shape (2026-08-09):  early 7-8%   mid 4-5%   late 2-3%

Source is RunMetrics' per-turn CSV (scripts/run_metrics.gd), which logs `revenue` and
`cost_transport` every turn and is enabled by default. It APPENDS across runs, so runs are
split here on turn resets rather than trusted as one series.

Usage:
    python3 tools/transport_bands.py                  # every run in the default CSV
    python3 tools/transport_bands.py --last           # only the most recent run
    python3 tools/transport_bands.py --bands 30,60,100
    python3 tools/transport_bands.py --check          # exit 1 if outside the target shape
    python3 tools/transport_bands.py --csv path/to/run_metrics.csv
"""
import argparse
import csv
import os
import sys

# AppPaths.base_dir() prefers a PROJECT-LOCAL directory when it is writable and only falls back
# to OS.get_user_data_dir(). Both are checked, newest first — pointing at the user-data copy
# alone reads a stale file and silently reports numbers from whichever session last ran there,
# which is exactly the mistake this comment exists to prevent.
_HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_CANDIDATES = [
    os.path.join(_HERE, "logs", "run_metrics.csv"),
    os.path.expanduser(
        "~/Library/Application Support/Godot/app_userdata/Price of Everything 0.1/run_metrics.csv"),
]


def _default_csv() -> str:
    found = [p for p in CSV_CANDIDATES if os.path.exists(p)]
    if not found:
        return CSV_CANDIDATES[0]
    return max(found, key=os.path.getmtime)


DEFAULT_CSV = _default_csv()
# (label, lower turn, upper turn, target low %, target high %)
DEFAULT_TARGETS = [("early", 7.0, 8.0), ("mid", 4.0, 5.0), ("late", 2.0, 3.0)]


def split_runs(rows):
    """RunMetrics appends; a turn that does not advance means a new run started."""
    runs, current, prev_turn = [], [], None
    for row in rows:
        try:
            turn = int(row["turn"])
        except (KeyError, ValueError):
            continue
        if prev_turn is not None and turn <= prev_turn:
            if current:
                runs.append(current)
            current = []
        current.append(row)
        prev_turn = turn
    if current:
        runs.append(current)
    return runs


def band_run(run, cuts):
    """Aggregate revenue and transport per turn band. Returns [(label, rev, transport)]."""
    edges = [(1, cuts[0])]
    for i in range(len(cuts) - 1):
        edges.append((cuts[i] + 1, cuts[i + 1]))
    edges.append((cuts[-1] + 1, 10 ** 9))
    out = []
    for lo, hi in edges:
        rev = trans = 0.0
        turns = 0
        for row in run:
            turn = int(row["turn"])
            if lo <= turn <= hi:
                rev += float(row.get("revenue") or 0.0)
                trans += float(row.get("cost_transport") or 0.0)
                turns += 1
        if turns:
            label = f"t{lo}-{hi}" if hi < 10 ** 9 else f"t{lo}+"
            out.append((label, rev, trans, turns))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default=DEFAULT_CSV)
    ap.add_argument("--bands", default="30,100", help="turn cut points, e.g. 30,60,100")
    ap.add_argument("--last", action="store_true", help="only the most recent run")
    ap.add_argument("--check", action="store_true", help="exit 1 if outside the target shape")
    args = ap.parse_args()

    if not os.path.exists(args.csv):
        sys.exit(f"no metrics at {args.csv}\n(run the e2e harness first; RunMetrics writes it)")
    cuts = [int(x) for x in args.bands.split(",") if x.strip()]

    with open(args.csv, newline="", encoding="utf-8", errors="replace") as fh:
        rows = list(csv.DictReader(fh))
    runs = split_runs(rows)
    if not runs:
        sys.exit("no complete runs found in the metrics CSV")
    if args.last:
        runs = runs[-1:]

    print(f"{len(runs)} run(s) in {os.path.basename(args.csv)}")
    print("target shape: " + "  ".join(f"{n} {lo:.0f}-{hi:.0f}%" for n, lo, hi in DEFAULT_TARGETS))
    breaches = 0
    for idx, run in enumerate(runs, 1):
        last_turn = max(int(r["turn"]) for r in run)
        print(f"\n-- run {idx}: {len(run)} rows, reaches turn {last_turn}")
        print(f"   {'band':<10}{'turns':>6}{'revenue':>12}{'transport':>11}{'share':>8}   target")
        for pos, (label, rev, trans, turns) in enumerate(band_run(run, cuts)):
            share = (100.0 * trans / rev) if rev > 0 else 0.0
            target = DEFAULT_TARGETS[pos] if pos < len(DEFAULT_TARGETS) else None
            verdict = ""
            if target and rev > 0:
                _, lo, hi = target
                if share < lo:
                    verdict = f"  under {lo:.0f}% (freight has stopped mattering)"
                    breaches += 1
                elif share > hi:
                    verdict = f"  over {hi:.0f}% (freight is punishing)"
                    breaches += 1
                else:
                    verdict = "  on target"
            print(f"   {label:<10}{turns:>6}{rev:>12,.0f}{trans:>11,.0f}{share:>7.1f}%{verdict}")

    if args.check and breaches:
        print(f"\nFAIL: {breaches} band(s) outside the target shape")
        return 1
    if args.check:
        print("\nOK: every band inside the target shape")
    return 0


if __name__ == "__main__":
    sys.exit(main())
