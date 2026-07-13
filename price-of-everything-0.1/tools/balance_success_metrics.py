#!/usr/bin/env python3
"""Decision-facing success metrics for the deployed recipe economy.

The report deliberately separates:

* standalone grid-powered cash after light market friction;
* research routes that beat the best start-unlocked route for the same output;
* exact two-building chains with one selected input integrated; and
* recursively integrated unit-cost profit under named owned-power scenarios.

It reads live CSV data and writes reports only; it never deploys proposals.
"""

from __future__ import annotations

import csv
from collections import defaultdict

import recipe_rebalance as model
import systemic_recipe_formula as systemic


OUT = model.OUT
THRESHOLDS = (50, 100, 150, 200, 300, 400)
FULL_POWER_SCENARIOS = (
    "coal power",
    "oil power",
    "onshore wind + lithium battery",
)
NAMED_EXAMPLES = {
    "Motors": "r_009",
    "Chlor-alkali": "r_012",
    "ICE cars": "r_117",
    "CPUs": "r_122",
    "Windows — aluminium": "r_056",
    "Windows — PVC": "r_055",
}


def outputs(recipe):
    return model.pairs(recipe, "output", "output_qty", 5)


def inputs(recipe):
    return model.pairs(recipe, "input", "qty", 6)


def _market_buy(good, quantity, goods):
    return quantity * model.f(goods[good].get("base_price")) * (1 + model.BUY_MARKUP)


def _market_sell(good, quantity, goods):
    return quantity * (model.GRID_SELL if good == "power" else model.f(goods[good].get("base_price")))


def _freight_and_storage(items, goods):
    freight = storage = 0.0
    for good, quantity in items:
        leg, _mode = model.one_turn_market_freight(good, quantity, goods)
        freight += leg
        storage += quantity * model.STORE.get(goods[good].get("transport_class", ""), 0.01)
    return freight, storage


def standalone_cash(recipe, goods, buildings):
    """Pre-tax cash with grid power, market inputs and one-turn friction."""
    building = buildings[recipe["_building"]]
    recipe_inputs = inputs(recipe)
    recipe_outputs = outputs(recipe)
    revenue = sum(_market_sell(good, quantity, goods) for good, quantity in recipe_outputs)
    input_bill = sum(_market_buy(good, quantity, goods) for good, quantity in recipe_inputs)
    inbound_freight, input_storage = _freight_and_storage(recipe_inputs, goods)
    outbound_freight, output_storage = _freight_and_storage(recipe_outputs, goods)
    power_bill = model.f(recipe.get("energy_req")) * model.GRID
    labour_bill = model.labour(recipe, building)
    maintenance_bill = model.f(building.get("maintenance_cost")) * model.MAINT_MULT
    profit = revenue - input_bill - power_bill - labour_bill - maintenance_bill - inbound_freight - outbound_freight - input_storage - output_storage
    return {
        "revenue": revenue,
        "market_input_bill": input_bill,
        "grid_power_bill": power_bill,
        "labour_bill": labour_bill,
        "maintenance_bill": maintenance_bill,
        "freight": inbound_freight + outbound_freight,
        "working_inventory_reserve": input_storage + output_storage,
        "profit": profit,
    }


def standalone_rows(recipes, goods, buildings, ranks):
    rows = []
    for recipe in recipes:
        if not outputs(recipe):
            continue
        result = standalone_cash(recipe, goods, buildings)
        research = str(recipe.get("required_research", ""))
        primary = outputs(recipe)[0][0]
        rows.append({
            "recipe_id": recipe["recipe_id"],
            "recipe": recipe.get("display_name", ""),
            "primary_output": primary,
            "start_unlocked": research == "",
            "research_unlock": research,
            "unlock_exists": research == "" or research in ranks,
            **result,
        })
    return rows


def unlock_superiority_rows(recipes, standalone_by_id, ranks):
    base_by_output = defaultdict(list)
    for recipe in recipes:
        if not outputs(recipe) or recipe.get("required_research", ""):
            continue
        base_by_output[outputs(recipe)[0][0]].append(recipe)
    rows = []
    for recipe in recipes:
        research = str(recipe.get("required_research", ""))
        if not outputs(recipe) or not research or research not in ranks:
            continue
        output_good = outputs(recipe)[0][0]
        candidates = base_by_output.get(output_good, [])
        if not candidates:
            rows.append({
                "recipe_id": recipe["recipe_id"], "recipe": recipe.get("display_name", ""),
                "research_unlock": research, "primary_output": output_good,
                "base_recipe_id": "", "base_recipe": "", "unlock_profit": standalone_by_id[recipe["recipe_id"]]["profit"],
                "base_profit": "", "profit_advantage": "", "beats_base": "no base comparator",
            })
            continue
        base = max(candidates, key=lambda candidate: standalone_by_id[candidate["recipe_id"]]["profit"])
        unlock_profit = standalone_by_id[recipe["recipe_id"]]["profit"]
        base_profit = standalone_by_id[base["recipe_id"]]["profit"]
        rows.append({
            "recipe_id": recipe["recipe_id"], "recipe": recipe.get("display_name", ""),
            "research_unlock": research, "primary_output": output_good,
            "base_recipe_id": base["recipe_id"], "base_recipe": base.get("display_name", ""),
            "unlock_profit": unlock_profit, "base_profit": base_profit,
            "profit_advantage": unlock_profit - base_profit,
            "beats_base": unlock_profit > base_profit,
        })
    return rows


def one_level_chain(root, supplier, integrated_good, goods, buildings, standalone_by_id):
    """One root plus one supplier, internalising only the selected input."""
    root_inputs = inputs(root)
    supplier_inputs = inputs(supplier)
    root_outputs = outputs(root)
    supplier_outputs = outputs(supplier)
    root_need = next(quantity for good, quantity in root_inputs if good == integrated_good)
    supplied = next(quantity for good, quantity in supplier_outputs if good == integrated_good)
    internal_quantity = min(root_need, supplied)

    external_inputs = list(supplier_inputs)
    for good, quantity in root_inputs:
        external_inputs.append((good, quantity - internal_quantity if good == integrated_good else quantity))
    external_inputs = [(good, quantity) for good, quantity in external_inputs if quantity > 1e-9]

    market_outputs = list(root_outputs)
    for good, quantity in supplier_outputs:
        market_outputs.append((good, quantity - internal_quantity if good == integrated_good else quantity))
    market_outputs = [(good, quantity) for good, quantity in market_outputs if quantity > 1e-9]

    input_bill = sum(_market_buy(good, quantity, goods) for good, quantity in external_inputs)
    revenue = sum(_market_sell(good, quantity, goods) for good, quantity in market_outputs)
    inbound_freight, input_storage = _freight_and_storage(external_inputs, goods)
    outbound_freight, output_storage = _freight_and_storage(market_outputs, goods)
    root_building = buildings[root["_building"]]
    supplier_building = buildings[supplier["_building"]]
    power_bill = (model.f(root.get("energy_req")) + model.f(supplier.get("energy_req"))) * model.GRID
    labour_bill = model.labour(root, root_building) + model.labour(supplier, supplier_building)
    maintenance_bill = (
        model.f(root_building.get("maintenance_cost")) + model.f(supplier_building.get("maintenance_cost"))
    ) * model.MAINT_MULT
    integrated_profit = revenue - input_bill - power_bill - labour_bill - maintenance_bill - inbound_freight - outbound_freight - input_storage - output_storage
    individual_profit = standalone_by_id[root["recipe_id"]]["profit"] + standalone_by_id[supplier["recipe_id"]]["profit"]
    return {
        "root_recipe_id": root["recipe_id"],
        "root_recipe": root.get("display_name", ""),
        "integrated_input": integrated_good,
        "supplier_recipe_id": supplier["recipe_id"],
        "supplier_recipe": supplier.get("display_name", ""),
        "internal_quantity": internal_quantity,
        "supplier_output_quantity": supplied,
        "root_input_quantity": root_need,
        "individual_two_building_profit": individual_profit,
        "integrated_two_building_profit": integrated_profit,
        "integration_gain": integrated_profit - individual_profit,
        "integration_is_better": integrated_profit > individual_profit,
    }


def one_level_rows(recipes, goods, buildings, standalone_by_id, ranks):
    canonical = systemic.canonical_recipes(recipes, ranks)
    rows = []
    for root in recipes:
        if not outputs(root):
            continue
        for good, _quantity in inputs(root):
            supplier = canonical.get(good)
            if supplier is None or supplier["recipe_id"] == root["recipe_id"]:
                continue
            rows.append(one_level_chain(root, supplier, good, goods, buildings, standalone_by_id))
    return rows


def full_integration_profit(recipe, goods, buildings, integrated_costs, power_cost):
    """Root-building profit with every input recursively costed to extraction."""
    building = buildings[recipe["_building"]]
    input_bill = sum(quantity * integrated_costs[good] for good, quantity in inputs(recipe))
    output_freight, output_storage = _freight_and_storage(outputs(recipe), goods)
    return (
        model.revenue(recipe, goods)
        - input_bill
        - model.f(recipe.get("energy_req")) * power_cost
        - model.labour(recipe, building)
        - model.f(building.get("maintenance_cost")) * model.MAINT_MULT
        - output_freight
        - output_storage
    )


def full_integration_rows(recipes, goods, buildings):
    power_rows, _fields = model.power_opportunity_scenarios(goods, buildings, recipes)
    power_by_name = {row["scenario"]: row for row in power_rows}
    rows = []
    for scenario in FULL_POWER_SCENARIOS:
        power_cost = float(power_by_name[scenario]["long_run_opportunity_cost_per_power"])
        integrated_costs = model.imputed(goods, buildings, recipes, power_cost)
        for recipe in recipes:
            if not outputs(recipe):
                continue
            profit = full_integration_profit(recipe, goods, buildings, integrated_costs, power_cost)
            row = {
                "power_scenario": scenario,
                "power_cost_per_unit": power_cost,
                "recipe_id": recipe["recipe_id"],
                "recipe": recipe.get("display_name", ""),
                "primary_output": outputs(recipe)[0][0],
                "full_integration_profit": profit,
            }
            for threshold in THRESHOLDS:
                row[f"over_{threshold}"] = profit > threshold
            rows.append(row)
    return rows


def named_example_rows(recipe_by_id, standalone_by_id, one_level, full_rows):
    one_by_root = defaultdict(list)
    for row in one_level:
        one_by_root[row["root_recipe_id"]].append(row)
    full_by_key = {(row["recipe_id"], row["power_scenario"]): row for row in full_rows}
    rows = []
    for label, recipe_id in NAMED_EXAMPLES.items():
        best_link = max(one_by_root.get(recipe_id, []), key=lambda row: row["integration_gain"], default={})
        rows.append({
            "example": label,
            "recipe_id": recipe_id,
            "recipe": recipe_by_id[recipe_id].get("display_name", ""),
            "standalone_grid_profit": standalone_by_id[recipe_id]["profit"],
            "one_integrated_input": best_link.get("integrated_input", ""),
            "one_input_supplier": best_link.get("supplier_recipe", ""),
            "individual_two_building_profit": best_link.get("individual_two_building_profit", ""),
            "one_level_integrated_profit": best_link.get("integrated_two_building_profit", ""),
            "one_level_integration_gain": best_link.get("integration_gain", ""),
            "fully_integrated_coal_power": full_by_key[(recipe_id, "coal power")]["full_integration_profit"],
            "fully_integrated_oil_power": full_by_key[(recipe_id, "oil power")]["full_integration_profit"],
            "fully_integrated_firmed_wind": full_by_key[(recipe_id, "onshore wind + lithium battery")]["full_integration_profit"],
        })
    return rows


def _write_csv(path, rows):
    if not rows:
        return
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        for row in rows:
            writer.writerow({key: round(value, 3) if isinstance(value, float) else value for key, value in row.items()})


def build_metrics():
    goods, buildings, _raw, recipes = model.load()
    ranks = model.rank_map()
    recipe_by_id = {recipe["recipe_id"]: recipe for recipe in recipes}
    standalone = standalone_rows(recipes, goods, buildings, ranks)
    standalone_by_id = {row["recipe_id"]: row for row in standalone}
    unlocks = unlock_superiority_rows(recipes, standalone_by_id, ranks)
    one_level = one_level_rows(recipes, goods, buildings, standalone_by_id, ranks)
    full_rows = full_integration_rows(recipes, goods, buildings)
    examples = named_example_rows(recipe_by_id, standalone_by_id, one_level, full_rows)
    return {
        "goods": goods, "buildings": buildings, "recipes": recipes, "ranks": ranks,
        "standalone": standalone, "unlocks": unlocks, "one_level": one_level,
        "full": full_rows, "examples": examples,
    }


def write_reports(metrics):
    OUT.mkdir(parents=True, exist_ok=True)
    _write_csv(OUT / "success_standalone_recipes.csv", metrics["standalone"])
    _write_csv(OUT / "success_unlock_superiority.csv", metrics["unlocks"])
    _write_csv(OUT / "success_one_level_integration.csv", metrics["one_level"])
    _write_csv(OUT / "success_full_integration.csv", metrics["full"])
    _write_csv(OUT / "success_named_examples.csv", metrics["examples"])

    base = [row for row in metrics["standalone"] if row["start_unlocked"]]
    base_profitable = [row for row in base if row["profit"] > 0]
    unlock_comparable = [row for row in metrics["unlocks"] if isinstance(row["beats_base"], bool)]
    unlock_better = [row for row in unlock_comparable if row["beats_base"]]
    eligible_roots = {row["root_recipe_id"] for row in metrics["one_level"]}
    better_roots = {row["root_recipe_id"] for row in metrics["one_level"] if row["integration_is_better"]}
    better_links = [row for row in metrics["one_level"] if row["integration_is_better"]]

    with open(OUT / "balance_success_summary.md", "w", encoding="utf-8") as handle:
        handle.write("# Balance success metrics\n\n")
        handle.write("All profit is pre-tax cash. Standalone and one-level cases use grid power, one-turn market freight, and a one-turn working-inventory reserve. Full integration recursively costs inputs to extraction, charges only final-output friction, and uses the named owned-power scenario's long-run opportunity cost.\n\n")
        handle.write(f"- Start-unlocked recipes profitable above £0: **{len(base_profitable)} / {len(base)}**\n")
        handle.write(f"- Research recipes beating the best start-unlocked recipe for the same primary output: **{len(unlock_better)} / {len(unlock_comparable)}** ({len(metrics['unlocks']) - len(unlock_comparable)} without a base comparator)\n")
        handle.write(f"- Recipes with at least one profitable one-input integration link: **{len(better_roots)} / {len(eligible_roots)}**\n")
        handle.write(f"- Improved one-input links: **{len(better_links)} / {len(metrics['one_level'])}**\n\n")
        handle.write("## Fully integrated profit thresholds\n\n")
        handle.write("| Owned power | Recipes | >£50 | >£100 | >£150 | >£200 | >£300 | >£400 |\n|---|---:|---:|---:|---:|---:|---:|---:|\n")
        for scenario in FULL_POWER_SCENARIOS:
            rows = [row for row in metrics["full"] if row["power_scenario"] == scenario]
            counts = [sum(row[f"over_{threshold}"] for row in rows) for threshold in THRESHOLDS]
            handle.write(f"| {scenario} | {len(rows)} | " + " | ".join(str(count) for count in counts) + " |\n")
        handle.write("\n## Named examples\n\n")
        handle.write("One-level profit is the combined two-building chain; the adjacent comparison is what those same two buildings earn when operated independently.\n\n")
        handle.write("| Example | Standalone | Integrated input | Separate buildings | One-level chain | Gain | Full coal | Full oil | Full firmed wind |\n|---|---:|---|---:|---:|---:|---:|---:|---:|\n")
        for row in metrics["examples"]:
            handle.write(
                f"| {row['example']} | {row['standalone_grid_profit']:.1f} | {row['one_integrated_input']} via {row['one_input_supplier']} | "
                f"{float(row['individual_two_building_profit']):.1f} | {float(row['one_level_integrated_profit']):.1f} | {float(row['one_level_integration_gain']):+.1f} | "
                f"{row['fully_integrated_coal_power']:.1f} | {row['fully_integrated_oil_power']:.1f} | {row['fully_integrated_firmed_wind']:.1f} |\n"
            )


def run():
    metrics = build_metrics()
    write_reports(metrics)
    print((OUT / "balance_success_summary.md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    run()
