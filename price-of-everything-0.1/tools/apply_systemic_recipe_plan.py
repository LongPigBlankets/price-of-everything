#!/usr/bin/env python3
"""Deploy the approved systemic recipe plan into the live CSV data.

``systemic_recipe_formula.py`` is the source of truth for canonical prices,
single-output quantities and the normal recipe workforce.  This script keeps
the formula output intact, then applies the small set of explicitly approved
route exceptions whose workforce is intentionally margin-controlled.
"""
from __future__ import annotations

import csv
from pathlib import Path

import recipe_rebalance as model
import systemic_recipe_formula as systemic


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
REPORTS = ROOT / "reports" / "balance"
RECIPE_PATH = DATA / "recipes_all.csv"
GOODS_PATH = DATA / "Goods - goodsMVP.csv"
PLAN_PATH = REPORTS / "systemic_formula_recipe_plan.csv"
PRICES_PATH = REPORTS / "systemic_formula_prices.csv"
LABOUR_COLUMNS = (
    "labour_unskilled_required",
    "labour_skilled_required",
    "labour_h_skilled_required",
)

# These routes deliberately depart from the formula's normal fixed workforce.
# They keep the output quantity of their formula-planned, non-research base
# recipe while their specialist staff absorbs the permitted additional margin.
SPECIAL_TARGETS = {
    "r_039": (20.0, (0.05, 0.35, 0.60)),  # lithium electrolysis
    "r_066": (15.0, (0.20, 0.45, 0.35)),  # axial-flux motors
    "r_072": (15.0, (0.35, 0.45, 0.20)),  # V8 engines
    "r_123": (70.0, (0.05, 0.25, 0.70)),  # fabless semiconductors
    "r_124": (70.0, (0.05, 0.25, 0.70)),  # 3D semiconductors
    "r_203": (15.0, (0.20, 0.45, 0.35)),  # hairpin motors
    "r_204": (15.0, (0.55, 0.35, 0.10)),  # base heavy vehicle
    "r_205": (50.0, (0.20, 0.45, 0.35)),  # automated heavy vehicle
    "r_206": (60.0, (0.15, 0.45, 0.40)),  # electric heavy vehicle
}
BASE_MATCH = {
    "r_039": "r_227",
    "r_066": "r_009",
    "r_072": "r_071",
    "r_123": "r_122",
    "r_124": "r_122",
    "r_203": "r_009",
    "r_205": "r_204",
    "r_206": "r_204",
}
# The heavy-vehicle workforce ladder is calibrated against this approved
# terminal price.  Full-integration cap work must reduce the external-versus-
# integrated input spread; simply cutting price also cuts the fitted labour
# bill and therefore does not solve that structural issue.
HEAVY_VEHICLE_PRICE = 228.0


def read_csv(path: Path):
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows, fields) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def staff_for_budget(budget: float, mix: tuple[float, float, float]):
    """Allocate a recipe crew within a labour budget, keeping every minimum."""
    counts = list(model.MIN_STAFF)
    cost = sum(count * wage for count, wage in zip(counts, model.WAGE))
    if budget <= cost:
        return tuple(counts)
    blended_rate = sum(weight * wage for weight, wage in zip(mix, model.WAGE))
    additions = int((budget - cost) / blended_rate)
    for index, weight in enumerate(mix):
        counts[index] += round(additions * weight)
    cost = sum(count * wage for count, wage in zip(counts, model.WAGE))
    while cost > budget:
        removable = [i for i in range(3) if counts[i] > model.MIN_STAFF[i]]
        if not removable:
            break
        index = max(removable, key=lambda i: model.WAGE[i])
        counts[index] -= 1
        cost -= model.WAGE[index]
    return tuple(counts)


def direct_cost_without_labour(recipe, building, goods) -> float:
    inputs = sum(
        quantity * model.f(goods[good].get("base_price")) * (1 + model.BUY_MARKUP)
        for good, quantity in model.pairs(recipe, "input", "qty", 6)
    )
    return inputs + model.f(recipe.get("energy_req")) * model.GRID + model.f(building.get("maintenance_cost")) * model.MAINT_MULT


def write_deployment_overrides(recipe_by_id, buildings, goods) -> None:
    """Record the small, intentional departures from the formula plan.

    The formula CSV is the generic recommendation.  These routes deliberately
    share a base recipe's output or use specialist labour, so their deployed
    margin must be inspected here rather than inferred from the generic plan.
    """
    rows = []
    for recipe_id in sorted(set(BASE_MATCH) | set(SPECIAL_TARGETS)):
        recipe = recipe_by_id[recipe_id]
        building_id = model.ALIASES.get(recipe["building_id"], recipe["building_id"])
        building = buildings[building_id]
        target_profit, target_min, target_max, target_policy, _rank = model.target(recipe, model.rank_map())
        margin = model.revenue(recipe, goods) - direct_cost_without_labour(recipe, building, goods) - model.labour(recipe, building)
        base_recipe_id = BASE_MATCH.get(recipe_id, "")
        matches_base = base_recipe_id != ""
        rows.append({
            "recipe_id": recipe_id,
            "recipe": recipe.get("display_name", ""),
            "deployment_rule": "matches base output; specialist labour target" if matches_base else "specialist labour target",
            "base_recipe_id": base_recipe_id,
            "deployed_output_qty": recipe["output_qty_1"],
            "base_output_qty": recipe_by_id[base_recipe_id]["output_qty_1"] if matches_base else "",
            "deployed_labour_unskilled": recipe["labour_unskilled_required"],
            "deployed_labour_skilled": recipe["labour_skilled_required"],
            "deployed_labour_h_skilled": recipe["labour_h_skilled_required"],
            "target_policy": target_policy,
            "target_profit": round(target_profit, 3),
            "target_min": target_min,
            "target_max": target_max,
            "deployed_production_margin": round(margin, 3),
            "in_target_band": target_min - 1e-6 <= margin <= target_max + 1e-6,
        })
    write_csv(REPORTS / "systemic_deployment_overrides.csv", rows, rows[0].keys())


def main() -> None:
    if not PLAN_PATH.exists() or not PRICES_PATH.exists():
        raise SystemExit("Run systemic_recipe_formula.py before deploying its plan.")
    recipes = read_csv(RECIPE_PATH)
    goods_rows = read_csv(GOODS_PATH)
    plans = {row["recipe_id"]: row for row in read_csv(PLAN_PATH)}
    prices = {row["good"]: row for row in read_csv(PRICES_PATH)}
    recipe_by_id = {row["recipe_id"]: row for row in recipes}
    good_by_name = {row["internal_name"]: row for row in goods_rows}

    # Deploy prices and formula-planned output quantity/workforce.  Recipes
    # absent from the plan are legacy/multi-output rows and retain their
    # formula-compatible existing values until they get a dedicated model.
    for good, source in prices.items():
        if good in good_by_name and source.get("formula_price", ""):
            good_by_name[good]["base_price"] = source["formula_price"]
    buildings = {row["internal_name"]: row for row in read_csv(DATA / "Buildings - buildingsMVP.csv")}
    for recipe_id, plan in plans.items():
        if recipe_id not in recipe_by_id:
            continue
        recipe = recipe_by_id[recipe_id]
        recipe["output_qty_1"] = plan["suggested_output_qty"]
        for column, plan_column in zip(LABOUR_COLUMNS, ("labour_unskilled", "labour_skilled", "labour_h_skilled")):
            recipe[column] = plan[plan_column]
    for recipe in recipes:
        if recipe["recipe_id"] in plans:
            continue
        building_id = model.ALIASES.get(recipe.get("building_id", ""), recipe.get("building_id", ""))
        if building_id not in buildings:
            # Retired/no-op legacy rows still need an explicit recipe crew so
            # there is no return path to zero labour after the migration.
            staff = model.MIN_STAFF
        else:
            staff = systemic.formula_staff(recipe, buildings[building_id])
        for column, count in zip(LABOUR_COLUMNS, staff):
            recipe[column] = str(count)

    # Formula-planned base quantities are authoritative for the researched
    # alternatives, irrespective of the legacy output quantities in the CSV.
    for recipe_id, base_recipe_id in BASE_MATCH.items():
        recipe_by_id[recipe_id]["output_qty_1"] = recipe_by_id[base_recipe_id]["output_qty_1"]

    # The old advanced heavy routes used far more batteries than their output
    # advantage justified.  Matching the base output lets automation use the
    # base pack count, while the electric route retains a modest two-pack
    # premium.  This also prevents full integration from exceeding +400.
    recipe_by_id["r_205"]["qty_3"] = "7"
    recipe_by_id["r_206"]["qty_3"] = "9"

    # The heavy variants need extra sales value to fund a greater specialist
    # workforce while keeping the base at roughly +15 and each unlock higher.
    good_by_name["heavy_vehicle"]["base_price"] = f"{HEAVY_VEHICLE_PRICE:g}"

    for recipe_id, (target_profit, mix) in SPECIAL_TARGETS.items():
        recipe = recipe_by_id[recipe_id]
        building_id = model.ALIASES.get(recipe["building_id"], recipe["building_id"])
        building = buildings[building_id]
        revenue = model.revenue(recipe, good_by_name)
        labour_budget = revenue - direct_cost_without_labour(recipe, building, good_by_name) - target_profit
        staff = staff_for_budget(labour_budget, mix)
        for column, count in zip(LABOUR_COLUMNS, staff):
            recipe[column] = str(count)

    recipe_fields = list(recipes[0].keys())
    for column in LABOUR_COLUMNS:
        if column not in recipe_fields:
            recipe_fields.append(column)
    write_csv(RECIPE_PATH, recipes, recipe_fields)
    write_csv(GOODS_PATH, goods_rows, list(goods_rows[0].keys()))
    write_deployment_overrides(recipe_by_id, buildings, good_by_name)


if __name__ == "__main__":
    main()
