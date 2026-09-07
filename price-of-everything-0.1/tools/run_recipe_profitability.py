#!/usr/bin/env python3
"""Run isolated, real-engine recipe cases and export a three-column SD comparison.

Defaults to serialized engine runs. --jobs supports independent workers; import the
project once before starting concurrent runs. No scene, UI clicks or offline model.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import time


PROJECT = Path(__file__).resolve().parents[1]
SCENE = "res://tools/recipe_profitability_case.tscn"


def run_case(godot: str, recipe: str, directory: Path) -> dict:
    directory.mkdir(parents=True, exist_ok=False)
    output = directory / "result.json"
    command = [godot, "--headless", "--path", str(PROJECT), "--log-file",
               str(directory / "engine.log"), SCENE, "--", recipe, str(output)]
    with (directory / "stdout.log").open("w") as log:
        process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=90)
    logs = (directory / "stdout.log").read_text()
    if process.returncode or not output.exists() or "SCRIPT ERROR:" in logs:
        raise RuntimeError(f"{recipe} failed; see {directory / 'stdout.log'}")
    data = json.loads(output.read_text())
    if recipe != "--list":
        validate(data)
    return data


def validate(data: dict) -> None:
    if data["status"] != "completed":
        return
    rows = [row for row in data["turns"] if row["in_sample"]]
    assert len(rows) == 10, data["recipe_id"]
    assert rows[0]["ran"]
    assert [r["turn"] for r in rows] == list(range(rows[0]["turn"], rows[0]["turn"] + 10))
    for row in rows:
        for field in ("sales", "cash_delta", "reported_net", "cash_reconciliation_residual"):
            assert math.isfinite(row[field]), (data["recipe_id"], field)
        assert abs(row["cash_reconciliation_residual"]) < 0.00001, (data["recipe_id"], row["turn"], row["cash_reconciliation_residual"])
        empire = row["empire"]
        assert empire.get("advisor_paid", 0) == 0
        assert empire.get("building_tab_carried", 0) == 0
        income = sum(float(empire.get(key, 0)) for key in
                     ("goods_sales_revenue", "power_sales_revenue", "green_subsidy_received"))
        costs = sum(float(empire.get(key, 0)) for key in
                    ("goods_purchased_cost", "power_purchase_cost", "transport_paid", "warehousing_paid",
                     "labour_paid", "maintenance_paid", "advisor_paid", "taxes_paid", "dividends_paid",
                     "carbon_tax_paid", "interest_paid", "profit_sharing_paid"))
        assert abs(income - costs - row["cash_delta"]) < 0.00001, (data["recipe_id"], row["turn"], "component reconciliation")
    assert not any(any(flags) for flags in data["final_missions"]["completed"].values()), data["recipe_id"]
    assert not data["final_missions"]["granted"]
    assert not data["final_loans"]["loans"]
    assert all(m["source"] == "deposit_penalty" for m in data["final_modifiers"]["modifiers"].values())


def aggregate(case: dict) -> dict:
    rows = [r for r in case["turns"] if r["in_sample"]]
    result = {key: case[key] for key in ("recipe_id", "building_id", "building_name", "recipe_name", "status")}
    result["label"] = f"{case['building_name']} ({case['recipe_name']})"
    result["reason"] = case.get("reason", "")
    if case["status"] != "completed":
        if case["turns"]:
            result["reason"] = str(case["turns"][-1].get("blocked_reason") or case["turns"][-1].get("missing_inputs"))
        return result
    result.update(sales=statistics.mean(r["sales"] for r in rows),
                  profit=statistics.mean(r["cash_delta"] for r in rows),
                  first_running_turn=case["first_running_turn"],
                  running_turns=sum(r["ran"] for r in rows),
                  final_turn_profit=rows[-1]["cash_delta"],
                  last_five_profit=statistics.mean(r["cash_delta"] for r in rows[-5:]),
                  profit_min=min(r["cash_delta"] for r in rows),
                  profit_max=max(r["cash_delta"] for r in rows),
                  max_reconciliation_error=max(abs(r["cash_reconciliation_residual"]) for r in rows))
    result["average_costs"] = {key: statistics.mean(float(r["empire"].get(key, 0)) for r in rows)
        for key in ["goods_purchased_cost", "power_purchase_cost", "transport_paid", "warehousing_paid",
                    "labour_paid", "maintenance_paid", "taxes_paid", "dividends_paid",
                    "carbon_tax_paid", "green_subsidy_received", "interest_paid", "profit_sharing_paid"]}
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot") or "/Users/crisu/Desktop/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--out", type=Path, required=True, help="New output directory; existing results are never reused")
    parser.add_argument("--recipes", nargs="*", help="Optional recipe IDs for pilot/repeat runs")
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--collect", action="store_true", help="Explicitly revalidate and re-export completed case JSON without running the engine")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    output = args.out.resolve()
    if not args.collect:
        output.mkdir(parents=True, exist_ok=False)
    started = time.monotonic()
    catalogue = (json.loads((output / "catalogue/result.json").read_text()) if args.collect
                 else run_case(args.godot, "--list", output / "catalogue"))
    recipes = [r for r in catalogue["recipes"] if not r["mining"]]
    if args.recipes:
        recipes = [r for r in recipes if r["recipe_id"] in args.recipes]
        if {r["recipe_id"] for r in recipes} != set(args.recipes):
            parser.error("Unknown or mining recipe requested")
    cases = []
    if args.collect:
        for recipe in recipes:
            case = json.loads((output / "cases" / recipe["recipe_id"] / "result.json").read_text())
            assert case["recipe_id"] == recipe["recipe_id"]
            validate(case)
            cases.append(case)
    else:
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            pending = {pool.submit(run_case, args.godot, r["recipe_id"], output / "cases" / r["recipe_id"]): r for r in recipes}
            for future in as_completed(pending):
                case = future.result()
                cases.append(case)
                print(f"{len(cases)}/{len(recipes)} {case['recipe_id']}: {case['status']}", flush=True)
    cases.sort(key=lambda c: (c["building_name"], c["recipe_name"], c["recipe_id"]))
    rows = [aggregate(c) for c in cases]
    report = {"schema_version": 1, "site": "Stoneshore Docks", "tile_id": "tile_5_10",
              "measure": "mean per turn across 10 consecutive turns from first successful production",
              "profit_basis": "retained cash change after all operating charges, tax and dividends; construction and initial pre-operation inventory purchases excluded",
              "export_elapsed_seconds": time.monotonic() - started, "jobs": args.jobs, "collected_existing_cases": args.collect,
              "excluded_mining": [r for r in catalogue["recipes"] if r["mining"]], "rows": rows}
    report["source_commit"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=PROJECT, text=True).strip()
    source_files = sorted([*PROJECT.joinpath("scripts").rglob("*.gd"), *PROJECT.joinpath("data").glob("*.csv"),
                           Path(__file__), PROJECT / "tools/recipe_profitability_case.gd"])
    report["source_sha256"] = {str(p.relative_to(PROJECT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files}
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    with (output / "recipe_profitability_sd.csv").open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["Building (Recipe)", "Sales (SD)", "Profit (SD)"])
        for row in rows:
            writer.writerow([row["label"], round(row["sales"], 2) if "sales" in row else "N/A",
                             round(row["profit"], 2) if "profit" in row else "N/A"])
    print(f"Wrote {len(rows)} recipe rows to {output}", flush=True)


if __name__ == "__main__":
    main()
