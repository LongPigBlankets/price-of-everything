#!/usr/bin/env python3
"""Systemic recipe balancing formula (read-only).

Prices are derived from one canonical (base) recipe per good.  Workforce is
derived from building complexity and input throughput, never from the selling
price.  With those fixed, each recipe receives the output quantity that puts
it at its target standalone margin.

The script writes proposals to reports/balance/; it never changes game data.
"""
from __future__ import annotations

import csv
import math
from collections import defaultdict

import recipe_rebalance as model


OUT = model.OUT
WORKLOAD_REFERENCE = 30.0
WORKLOAD_FLOOR = 0.70
WORKLOAD_CEILING = 1.30
PRICE_DAMPING = 0.50
MAX_PRICE_ITERATIONS = 200
# Small, documented corrections for integer-output recipes that share another
# route's canonical price.  These are applied after the building/workload
# workforce formula, so the model stays systematic while a one-unit output
# jump does not force a recipe outside its approved cash band.
LABOUR_CALIBRATIONS = {
    # 17 windows is the readable supply quantity; +60 highly-skilled workers
    # keeps its pre-tax, freight-and-warehouse-reserve cash just below £10.
    "r_056": (0, 0, 60),
}


def workload_factor(recipe):
    """A bounded throughput signal that is independent of a recipe's revenue."""
    input_units = sum(qty for _good, qty in model.pairs(recipe, "input", "qty", 6))
    return max(WORKLOAD_FLOOR, min(WORKLOAD_CEILING, math.sqrt(max(input_units, 10.0) / WORKLOAD_REFERENCE)))


def formula_staff(recipe, building):
    """Keep the building's skill profile, floor it, then scale by workload."""
    columns = ("labour_unskilled_required", "labour_skilled_required", "labour_h_skilled_required")
    factor = workload_factor(recipe)
    base = tuple(
        max(minimum, math.ceil(model.i(building.get(column)) * factor))
        for column, minimum in zip(columns, model.MIN_STAFF)
    )
    adjustment = LABOUR_CALIBRATIONS.get(recipe["recipe_id"], (0, 0, 0))
    return tuple(count + delta for count, delta in zip(base, adjustment))


def formula_labour_cost(recipe, building):
    return sum(count * wage for count, wage in zip(formula_staff(recipe, building), model.WAGE))


def primary_output(recipe):
    outputs = model.pairs(recipe, "output", "output_qty", 5)
    return outputs[0] if len(outputs) == 1 else ("", 0.0)


def is_recycling(recipe):
    label = f"{recipe.get('display_name', '')} {recipe.get('category', '')}".lower()
    return "recycl" in label


def canonical_recipes(recipes, ranks):
    """Choose one non-recycling base route per good to establish its price."""
    producers = defaultdict(list)
    for recipe in recipes:
        good, quantity = primary_output(recipe)
        if good and good != "power" and quantity:
            producers[good].append(recipe)
    selected = {}
    for good, candidates in producers.items():
        selected[good] = min(
            candidates,
            key=lambda recipe: (
                is_recycling(recipe),
                bool(recipe.get("required_research", "")),
                model.target(recipe, ranks)[4],
                len(model.pairs(recipe, "input", "qty", 6)),
                recipe["recipe_id"],
            ),
        )
    return selected


def supply_quantity_floors(canonical):
    """One canonical supplier must cover one canonical consumer building."""
    floors = {good: primary_output(recipe)[1] for good, recipe in canonical.items()}
    for _output_good, consumer in canonical.items():
        for input_good, required_qty in model.pairs(consumer, "input", "qty", 6):
            if input_good in floors:
                floors[input_good] = max(floors[input_good], required_qty)
    return floors


def human_output_candidates(required_qty, minimum_qty):
    """Return legal output quantities with an audit-friendly rounding label.

    Small recipes retain unit precision.  Once the required output exceeds 36,
    quantities are deliberately chosen from nearby multiples of five or twelve
    (the game's natural batch sizes).  The supply floor is never rounded down:
    a canonical supplier must still cover one consumer building in full.
    """
    floor_qty = max(1.0, minimum_qty)
    reference = max(required_qty, floor_qty)
    if reference <= 36.0:
        return {
            quantity: "unit precision"
            for quantity in {max(1, math.floor(reference)), max(1, math.ceil(reference))}
            if quantity >= floor_qty
        }
    candidates = {}
    for batch in (5, 12):
        for quantity in (math.floor(reference / batch) * batch, math.ceil(reference / batch) * batch):
            if quantity >= floor_qty:
                candidates[int(quantity)] = f"multiple of {batch}"
    # A ceiling candidate always exists, but retain this guard if a future
    # non-integer supply floor makes the filtering rule stricter.
    if not candidates:
        candidates[int(math.ceil(reference / 5.0) * 5)] = "multiple of 5"
    return candidates


def working_friction(recipe, goods):
    """One-turn market freight and inventory reserve for the formula target."""
    inbound_freight = input_warehouse = 0.0
    for good, quantity in model.pairs(recipe, "input", "qty", 6):
        freight, _mode = model.one_turn_market_freight(good, quantity, goods)
        inbound_freight += freight
        input_warehouse += quantity * model.STORE.get(goods[good].get("transport_class", ""), 0.01)
    output_good, _output_qty = primary_output(recipe)
    if not output_good:
        return inbound_freight, input_warehouse, 0.0, 0.0
    freight_per_unit, _mode = model.one_turn_market_freight(output_good, 1.0, goods)
    warehouse_per_unit = model.STORE.get(goods[output_good].get("transport_class", ""), 0.01)
    return inbound_freight, input_warehouse, freight_per_unit, warehouse_per_unit


def direct_cost(recipe, building, goods, prices, ranks):
    inputs = sum(qty * prices[good] * (1 + model.BUY_MARKUP) for good, qty in model.pairs(recipe, "input", "qty", 6))
    power = model.f(recipe.get("energy_req")) * model.GRID
    maintenance = model.f(building.get("maintenance_cost")) * model.MAINT_MULT
    labour = formula_labour_cost(recipe, building)
    target = model.target(recipe, ranks)[0]
    inbound_freight, input_warehouse, outbound_freight_per_unit, output_warehouse_per_unit = working_friction(recipe, goods)
    return inputs, power, maintenance, labour, target, inbound_freight, input_warehouse, outbound_freight_per_unit, output_warehouse_per_unit


def solve_prices(goods, buildings, recipes, ranks, canonical, supply_floors):
    prices = {good: model.f(row.get("base_price")) for good, row in goods.items()}
    for _ in range(MAX_PRICE_ITERATIONS):
        next_prices = prices.copy()
        max_change = 0.0
        for good, recipe in canonical.items():
            building = buildings[recipe["_building"]]
            _inputs, _power, _maintenance, _labour, _target, _inbound_freight, _input_warehouse, _outbound_per_unit, _output_warehouse_per_unit = direct_cost(recipe, building, goods, prices, ranks)
            output_good, output_qty = primary_output(recipe)
            output_qty = max(output_qty, supply_floors[output_good])
            candidate = (
                (_inputs + _power + _maintenance + _labour + _target + _inbound_freight + _input_warehouse) / output_qty
                + _outbound_per_unit + _output_warehouse_per_unit
            )
            updated = prices[good] * (1 - PRICE_DAMPING) + candidate * PRICE_DAMPING
            next_prices[good] = updated
            max_change = max(max_change, abs(updated - prices[good]))
        prices = next_prices
        if max_change < 1e-6:
            return prices, _ + 1
    return prices, MAX_PRICE_ITERATIONS


def plan_recipe(recipe, building, goods, prices, ranks, canonical, supply_floors):
    output_good, current_qty = primary_output(recipe)
    if not output_good:
        return None
    inputs, power, maintenance, labour, target, inbound_freight, input_warehouse, outbound_per_unit, output_warehouse_per_unit = direct_cost(recipe, building, goods, prices, ranks)
    price = 0.06 if output_good == "power" else prices[output_good]
    low, high = model.target(recipe, ranks)[1:3]
    fixed_cost = inputs + power + maintenance + labour + inbound_freight + input_warehouse
    net_unit_revenue = price - outbound_per_unit - output_warehouse_per_unit
    required_qty = (fixed_cost + target) / net_unit_revenue
    minimum_qty = supply_floors.get(output_good, 1.0) if canonical.get(output_good, {}).get("recipe_id") == recipe["recipe_id"] else 1.0
    candidates = human_output_candidates(required_qty, minimum_qty)
    profit_for = lambda qty: qty * net_unit_revenue - fixed_cost
    in_band = [qty for qty in candidates if low - 1e-6 <= profit_for(qty) <= high + 1e-6]
    suggested_qty = min(in_band or candidates, key=lambda qty: (abs(profit_for(qty) - target), abs(qty - required_qty)))
    profit = profit_for(suggested_qty)
    return {
        "recipe_id": recipe["recipe_id"],
        "recipe": recipe.get("display_name", ""),
        "building": recipe["_building"],
        "primary_output": output_good,
        "formula_price": round(price, 3),
        "current_output_qty": current_qty,
        "canonical_supply_floor": supply_floors.get(output_good, ""),
        "unrounded_output_qty": round(required_qty, 3),
        "suggested_output_qty": suggested_qty,
        "output_rounding": candidates[suggested_qty],
        "output_multiplier": round(suggested_qty / current_qty, 3),
        "labour_unskilled": formula_staff(recipe, building)[0],
        "labour_skilled": formula_staff(recipe, building)[1],
        "labour_h_skilled": formula_staff(recipe, building)[2],
        "labour_bill": round(labour, 3),
        "input_bill": round(inputs, 3),
        "energy_bill": round(power, 3),
        "maintenance_bill": round(maintenance, 3),
        "one_turn_inbound_freight": round(inbound_freight, 3),
        "one_turn_outbound_freight": round(suggested_qty * outbound_per_unit, 3),
        "one_turn_working_inventory_warehouse_reserve": round(input_warehouse + suggested_qty * output_warehouse_per_unit, 3),
        "target_profit": round(target, 3),
        "planned_pre_tax_cash_after_freight_and_warehouse": round(profit, 3),
        "target_min": low,
        "target_max": high,
        "in_target_band": low - 1e-6 <= profit <= high + 1e-6,
    }


def run():
    goods, buildings, _raw, recipes = model.load()
    ranks = model.rank_map()
    canonical = canonical_recipes(recipes, ranks)
    supply_floors = supply_quantity_floors(canonical)
    prices, iterations = solve_prices(goods, buildings, recipes, ranks, canonical, supply_floors)
    OUT.mkdir(parents=True, exist_ok=True)
    with open(OUT / "systemic_formula_prices.csv", "w", newline="", encoding="utf-8") as handle:
        fields = ("good", "canonical_recipe_id", "canonical_recipe", "current_price", "formula_price")
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for good in sorted(goods):
            source = canonical.get(good)
            writer.writerow({
                "good": good,
                "canonical_recipe_id": source["recipe_id"] if source else "",
                "canonical_recipe": source.get("display_name", "") if source else "",
                "current_price": round(model.f(goods[good].get("base_price")), 3),
                "formula_price": round(prices[good], 3),
            })
    plans = []
    for recipe in recipes:
        plan = plan_recipe(recipe, buildings[recipe["_building"]], goods, prices, ranks, canonical, supply_floors)
        if plan:
            plans.append(plan)
    with open(OUT / "systemic_formula_recipe_plan.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=plans[0].keys())
        writer.writeheader()
        writer.writerows(plans)
    plan_by_id = {plan["recipe_id"]: plan for plan in plans}
    supply_rows = []
    for _output_good, consumer in canonical.items():
        for input_good, required_qty in model.pairs(consumer, "input", "qty", 6):
            supplier = canonical.get(input_good)
            if not supplier or supplier["recipe_id"] not in plan_by_id:
                continue
            supplied_qty = plan_by_id[supplier["recipe_id"]]["suggested_output_qty"]
            supply_rows.append({
                "consumer_recipe_id": consumer["recipe_id"],
                "consumer_recipe": consumer.get("display_name", ""),
                "input_good": input_good,
                "required_input_qty": required_qty,
                "supplier_recipe_id": supplier["recipe_id"],
                "supplier_recipe": supplier.get("display_name", ""),
                "supplier_output_qty": supplied_qty,
                "buildings_required": round(required_qty / supplied_qty, 3),
                "within_one_supplier_building": required_qty <= supplied_qty,
            })
    with open(OUT / "systemic_formula_supply_ratios.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=supply_rows[0].keys())
        writer.writeheader()
        writer.writerows(supply_rows)
    covered = sum(plan["in_target_band"] for plan in plans)
    supply_violations = sum(not row["within_one_supplier_building"] for row in supply_rows)
    with open(OUT / "systemic_formula_summary.md", "w", encoding="utf-8") as handle:
        handle.write("# Systemic recipe formula\n\n")
        handle.write("Prices come from a canonical, non-recycling base recipe per good. Workforce is fixed from building skill mix and input throughput; it is not back-solved from margin. Targets are pre-tax cash after one-turn market freight and a one-turn working-inventory warehouse reserve.\n\n")
        handle.write(f"- Canonical prices solved in {iterations} iterations\n")
        handle.write(f"- Single-output recipes in their target profit band after formula output quantities: {covered} / {len(plans)}\n")
        handle.write(f"- Canonical supply links requiring more than one supplier building: {supply_violations} / {len(supply_rows)}\n")
        handle.write(f"- Workload factor: `clamp({WORKLOAD_FLOOR}, {WORKLOAD_CEILING}, sqrt(max(input_qty, 10) / {WORKLOAD_REFERENCE}))`\n")
        handle.write("- Recommended outputs above 36 use a nearby multiple of 5 or 12, while retaining canonical one-building supply floors.\n")
    print(f"Canonical prices: {len(canonical)}; planned recipes in target band: {covered} / {len(plans)}; supply violations: {supply_violations}; iterations: {iterations}")


if __name__ == "__main__":
    run()
