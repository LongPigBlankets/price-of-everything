#!/usr/bin/env python3
"""Run the balance-v4 player benchmarks and generate the requested result table."""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
from pathlib import Path


SCENARIOS = {
    "balance_v4_motors": ["r_009"],
    "balance_v4_motors_road_1200": ["r_009"],
    "balance_v4_motors_metal_path_1200": ["r_009"],
    "balance_v4_motors_metal_magnate": ["r_009"],
    "balance_v4_electrochem": ["r_012", "r_079", "r_080"],
    "balance_v4_advanced_materials": ["r_020", "r_044", "r_076", "r_082"],
    "balance_v4_batteries": ["r_099", "r_102", "r_136"],
}
EXPECTED_RED_SCENARIOS = {
    "balance_v4_motors",
    "balance_v4_motors_road_1200",
    "balance_v4_motors_metal_path_1200",
    "balance_v4_motors_metal_magnate",
    "balance_v4_electrochem",
    "balance_v4_advanced_materials",
    "balance_v4_batteries",
}
TARGET_TURN = 150


def default_godot() -> str:
    configured = os.environ.get("GODOT_BIN", "")
    if configured:
        return configured
    mac = Path("/Users/crisu/Desktop/Godot.app/Contents/MacOS/Godot")
    return str(mac) if mac.exists() else "godot"


def run_scenario(godot: str, project: Path, scenario: str, output: Path) -> None:
    log_path = Path("/tmp") / f"{scenario}_turn_{TARGET_TURN}.log"
    command = [
        godot,
        "--headless",
        "--quiet",
        "--log-file",
        str(log_path),
        "--path",
        str(project),
        "tests/e2e_stoneshore.tscn",
        "--",
        scenario,
        str(TARGET_TURN),
        str(output),
    ]
    completed = subprocess.run(command, text=True, capture_output=True, check=False)
    if completed.returncode != 0:
        if scenario in EXPECTED_RED_SCENARIOS and output.exists():
            data = json.loads(output.read_text(encoding="utf-8"))
            if int(data.get("assertions_failed", 0)) > 0:
                print(
                    f"{scenario}: recorded {data['assertions_failed']} red balance assertions",
                    flush=True,
                )
                return
        failures = [line for line in completed.stdout.splitlines() if "FAIL" in line]
        detail = "\n".join(failures[-20:]) or completed.stderr[-4000:] or completed.stdout[-4000:]
        raise RuntimeError(f"{scenario} failed with exit {completed.returncode}:\n{detail}")
    if not output.exists():
        raise RuntimeError(f"{scenario} passed but did not write {output}")


def metric_row(name: str, recipes: list[str], data: dict) -> dict:
    row = {
        "scenario": name.removeprefix("balance_v4_").replace("_", " ").title(),
        "recipes": ", ".join(recipes),
        "profit_gt_100": data["turn_profit_gt_100"],
        "profit_gt_200": data["turn_profit_gt_200"],
        "profit_gt_500": data["turn_profit_gt_500"],
        "profit_gt_1000": data["turn_profit_gt_1000"],
        "buildings_30": data["turn_30"]["building_count"],
        "buildings_80": data["turn_80"]["building_count"],
        "buildings_150": data["turn_150"]["building_count"],
        "units_sold_30": data["turn_30"]["units_sold"],
        "units_sold_80": data["turn_80"]["units_sold"],
        "units_sold_150": data["turn_150"]["units_sold"],
        "fully_integrated": data["turn_chain_fully_integrated"],
        "bankruptcy_turn": data["bankruptcy_turn"],
        "max_bankruptcy_streak": data["max_bankruptcy_streak"],
        "average_port_distance": data["average_port_distance"],
        "grid_bought_after_integration": data.get("grid_bought_after_integration", 0),
        "integration_scope": data.get("integration_scope", "all scenario targets"),
        "assertions_failed": data["assertions_failed"],
        "starting_money": data.get("starting_money", 1500),
        "expansion_loans": data.get("expansion_loans_taken", 0),
        "expansion_principal": data.get("expansion_loan_principal", 0),
        "loan_gate_rejections": data.get("expansion_loan_gate_rejections", 0),
        "cash_cushion_waits": data.get("unprofitable_cash_cushion_waits", 0),
        "emergency_bridge_loans": data.get("emergency_bridge_loans_taken", 0),
    }
    return row


def shown(value: int | float) -> str:
    if isinstance(value, int) and value < 0:
        return "—"
    if isinstance(value, float):
        return f"{value:.1f}"
    return str(value)


def write_reports(report_dir: Path, rows: list[dict], raw: dict) -> None:
    json_path = report_dir / "balance_v4_e2e_results.json"
    csv_path = report_dir / "balance_v4_e2e_results.csv"
    md_path = report_dir / "balance_v4_e2e_results.md"
    json_path.write_text(json.dumps(raw, indent=2) + "\n", encoding="utf-8")
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    headers = [
        "Scenario (recipes)", "Profit >100", ">200", ">500", ">1000",
        "Start / port distance", "Buildings 30/80/150", "Units sold 30/80/150",
        "Expansion loans / gate waits", "Integrated", "Bankrupt", "Red",
    ]
    table_rows = []
    for row in rows:
        table_rows.append([
            f"{row['scenario']} ({row['recipes']})",
            shown(row["profit_gt_100"]),
            shown(row["profit_gt_200"]),
            shown(row["profit_gt_500"]),
            shown(row["profit_gt_1000"]),
            f"£{row['starting_money']:,.0f} / {row['average_port_distance']:.1f}",
            f"{row['buildings_30']}/{row['buildings_80']}/{row['buildings_150']}",
            f"{row['units_sold_30']}/{row['units_sold_80']}/{row['units_sold_150']}",
            f"{row['expansion_loans']} / {row['loan_gate_rejections']}+{row['cash_cushion_waits']}",
            shown(row["fully_integrated"]),
            shown(row["bankruptcy_turn"]),
            shown(row["assertions_failed"]),
        ])
    lines = [
        "# Balance v4 end-to-end results",
        "",
        f"Turn horizon: {TARGET_TURN}. A dash means the threshold or bankruptcy condition was not reached.",
        "",
        "| " + " | ".join(headers) + " |",
        "|" + "|".join(["---"] + ["---:"] * (len(headers) - 1)) + "|",
    ]
    lines.extend("| " + " | ".join(values) + " |" for values in table_rows)
    rail_motor = raw["balance_v4_motors"]
    road_motor = raw["balance_v4_motors_road_1200"]
    prudent_motor = raw["balance_v4_motors_metal_path_1200"]
    magnate_motor = raw["balance_v4_motors_metal_magnate"]
    lines.extend([
        "",
        "## Integration scope",
        "",
    ])
    for row in rows:
        lines.append(f"- **{row['scenario']}:** {row['integration_scope']}")
    lines.extend([
        "",
        "## Findings",
        "",
        "- All scenarios used their configured starting cash, live loan and land capacity, construction materials, physical deposits, transport maintenance, and owned power.",
        "- Building sale and demolition were not used. The prudent motor path retains standing extraction penalties while neutralizing earned bonuses; the older portfolio fixtures neutralize all modifiers and remain legacy comparisons.",
        f"- The exact Metal Magnate portfolio reaches full integration on turn {magnate_motor['turn_chain_fully_integrated']}; the blank-start portfolios do not.",
        "- No portfolio reached profit above £100/turn by turn 150; all higher thresholds also remained unreached.",
        f"- Electrochem reaches bankruptcy on turn {raw['balance_v4_electrochem']['bankruptcy_turn']} and Advanced Materials on turn {raw['balance_v4_advanced_materials']['bankruptcy_turn']}; their earlier green results depended on earned bonuses.",
        f"- Batteries reaches bankruptcy on turn {raw['balance_v4_batteries']['bankruptcy_turn']} before any target battery recipe runs.",
        f"- The £1,200 road motor variant starts two tiles from port, first runs motors on turn {road_motor['target_recipe_first_run']['r_009']}, sells {road_motor['target_units_sold']['motor']} motors, and reaches bankruptcy on turn {road_motor['bankruptcy_turn']}. It survives much longer than the £1,500 rail benchmark (turn {rail_motor['bankruptcy_turn']}) but still cannot finance copper extraction and full integration.",
        f"- The prudent £1,200 motor path first runs motors on turn {prudent_motor['target_recipe_first_run']['r_009']} and sells {prudent_motor['target_units_sold']['motor']} motors. It takes {prudent_motor.get('expansion_loans_taken', 0)} strategy-approved expansion loan(s), waits {prudent_motor.get('unprofitable_cash_cushion_waits', 0)} times for the 1.5× loss-making cash cushion, and reaches bankruptcy on turn {prudent_motor['bankruptcy_turn']} before full raw integration.",
        f"- Metal Magnate first runs motors on turn {magnate_motor['target_recipe_first_run']['r_009']}, sells {magnate_motor['target_units_sold']['motor']} motors and takes no strategy-approved expansion loan. Its inherited finite coal and iron deposits eventually exhaust; owned generation then stalls, cumulative post-integration grid purchases reach {magnate_motor['grid_bought_after_integration']} power, and bankruptcy follows on turn {magnate_motor['bankruptcy_turn']}.",
    ])
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=default_godot())
    parser.add_argument("--no-run", action="store_true", help="Regenerate reports from existing per-scenario JSON")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    report_dir = project / "reports" / "balance"
    report_dir.mkdir(parents=True, exist_ok=True)
    raw: dict[str, dict] = {}
    rows: list[dict] = []
    for scenario, recipes in SCENARIOS.items():
        output = report_dir / f"{scenario}.json"
        if not args.no_run:
            print(f"Running {scenario} to turn {TARGET_TURN}...", flush=True)
            run_scenario(args.godot, project, scenario, output)
        if not output.exists():
            raise RuntimeError(f"Missing metrics file: {output}")
        data = json.loads(output.read_text(encoding="utf-8"))
        raw[scenario] = data
        rows.append(metric_row(scenario, recipes, data))
    write_reports(report_dir, rows, raw)
    print(report_dir / "balance_v4_e2e_results.md")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(exc, file=sys.stderr)
        raise SystemExit(1)
