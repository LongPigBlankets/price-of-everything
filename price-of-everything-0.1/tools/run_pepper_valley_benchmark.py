#!/usr/bin/env python3
"""Run the persistent Pepper Valley benchmark; reject script errors and optional drift."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from run_tests import PROJECT_DIR, find_godot

OUT = Path("/tmp/pepper-valley-motors-benchmark")
BASELINE_DIR = Path(PROJECT_DIR) / "tests/snapshots"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--route", choices=("roads", "rail", "rail-three-owned"), default="roads")
    parser.add_argument("--balance", choices=("fee40", "targeted", "control"), default="fee40",
                        help="Expected live-data preset; does not modify or override game data")
    parser.add_argument("--stage", choices=("base", "early", "output", "research", "jit", "furnace", "furnace-jit"), default="base")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write-baseline", action="store_true")
    mode.add_argument("--check-baseline", action="store_true")
    args = parser.parse_args()
    if args.stage in ("furnace", "furnace-jit") and args.balance != "fee40":
        parser.error("Local-steel extension requires the current fee40 motor profile")
    out = OUT if args.route == "roads" else Path(str(OUT) + "-" + args.route)
    out = Path(str(out) + "-" + args.balance)
    suffix = "" if args.route == "roads" else "_" + args.route.replace("-", "_")
    revision = {"control": 2, "targeted": 3, "fee40": 5}[args.balance]
    if args.stage in ("furnace", "furnace-jit"):
        revision = 7
    stage_suffix = "" if args.stage == "base" else "_" + args.stage
    if args.stage != "base":
        out = Path(str(out) + "-" + args.stage)
    baseline_path = BASELINE_DIR / f"pepper_valley_motors{suffix}_v{revision}{stage_suffix}.json"
    game_args = ["--", "--stage=" + args.stage]
    if args.route != "roads":
        game_args.append("--rail")
    if args.route == "rail-three-owned":
        game_args.append("--three-owned")
    if args.balance == "control":
        game_args.append("--control")
    elif args.balance == "targeted":
        game_args.append("--targeted")
    godot = find_godot()
    if not godot:
        parser.error("Godot not found; set GODOT_BIN")
    out.mkdir(parents=True, exist_ok=True)
    result_path = out / "result.json"
    result_path.unlink(missing_ok=True)
    with (out / "run.log").open("w") as log:
        run = subprocess.run(
            [godot, "--headless", "--path", PROJECT_DIR, "--log-file",
             str(out / "godot.log"), "res://tools/pepper_valley_motors_benchmark.tscn"]
            + game_args,
            stdout=log, stderr=subprocess.STDOUT, timeout=260, check=False,
        )
    log_text = (out / "run.log").read_text()
    if run.returncode or "SCRIPT ERROR" in log_text or not result_path.exists():
        print(f"Benchmark failed; inspect {out / 'run.log'}", file=sys.stderr)
        return 1
    report = json.loads(result_path.read_text())
    if report["failures"]:
        print(report["failures"], file=sys.stderr)
        return 1
    # Retain routes, validated steady window and control settings; full startup
    # trace remains in result.json. No timestamps or wall-clock measurements.
    baseline = {key: value for key, value in report.items() if key != "turns"}
    if args.write_baseline:
        baseline_path.write_text(json.dumps(baseline, indent=2, sort_keys=True) + "\n")
        print(f"Baseline written: {baseline_path}")
    if args.check_baseline:
        previous = json.loads(baseline_path.read_text())
        for key, expected in previous["means"].items():
            actual = report["means"].get(key)
            if actual is None or abs(actual - expected) > 0.001:
                print(f"Benchmark drift: {key}: {expected} -> {actual}", file=sys.stderr)
                return 1
        for key in ("spec", "congestion_accounting_version", "settled_links", "route_quotes_at_start", "first_production_turn",
                    "first_receipt_turn", "first_regular_shipment_turn") + (
                        ("owned_rail_tiles", "rail_variant") if args.route != "roads" else ()):
            if previous[key] != report[key]:
                print(f"Benchmark drift: {key}", file=sys.stderr)
                return 1
        print("Baseline verified.")
    print(json.dumps(report["means"], indent=2))
    print(f"Middleman: reference calculation only. Full trace: {result_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
