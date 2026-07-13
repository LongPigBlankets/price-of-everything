#!/usr/bin/env python3
"""Systemic recipe balancing formula (read-only).

Prices are derived from one canonical (base) recipe per good.  Workforce is
derived from building complexity and input throughput, never from the selling
price.  With those fixed, each recipe's complete output basket is scaled to
put it at its target standalone margin.  Joint-product cost and revenue are
allocated by ``output quantity * market price``; no output is silently ignored.

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

# Player-facing industrial batches approved after comparing the unlocked route
# with its base recipe.  Values are scales of the recipe's reduced output
# ratio: flash copper has a 1-ingot ratio unit, so scale 36 means 36 ingots.
APPROVED_OUTPUT_BATCH_SCALES = {
    # Industrial reaction-unit batches accepted for the v4 demo balance pass.
    "r_012": 22,
    # 30 ore -> 36 ingots versus base blistering's 36 ore -> 24 ingots.
    "r_020": 36,
    "r_031": 80,
    "r_032": 6,
    "r_044": 20,
    "r_076": 50,
    "r_078": 8,
    "r_079": 7,
    "r_080": 11,
    "r_081": 6,
    "r_082": 54,
    # Research improves cell chemistry and profitability without changing the
    # storage good loaded by the battery building.
    "r_099": 8,
    "r_102": 6,
    "r_116": 36,
    "r_118": 9,
    "r_124": 5,
    "r_136": 6,
}

# These goods are accumulated over several production turns or supplied by
# parallel plants.  A single electrolyser/cell factory is intentionally not
# required to cover one downstream building in one turn.
MULTI_TURN_SUPPLY_GOODS = {
    "hydrogen", "oxygen", "lithium_battery", "sodium_battery", "iron_battery",
}

# Owner-approved v4 market anchors.  The solver continues to derive every
# other price from canonical recipes, but these values are fixed because they
# encode coproduct allocation, downstream affordability and installed-storage
# progression decisions made outside the generic canonical formula.
APPROVED_GOOD_PRICES = {
    "oxygen": 0.25,
    "hydrogen": 3.3,
    "rubber": 3.888,
    "cpu": 70.811,
    "metallurgical_silicon": 3.528,
    "polysilicon": 24.503,
    "lithium_carbonate": 6.653,
    "solar_panel": 30.843,
    "lithium_battery": 25.0,
    "sodium_battery": 15.0,
    "iron_battery": 5.0,
    "industrial_acids": 3.47,
    "ammonia": 3.533,
}

# Reaction-unit industrial output ratios.  These use stoichiometric
# coefficients (game production units), not molecular mass.  The formula
# scales the whole basket in these ratios
# and never tunes one coproduct independently.  Other multi-output recipes
# retain their deployed integer ratio (reduced by its greatest common divisor).
STOICHIOMETRIC_OUTPUT_RATIOS = {
    # 2 NaCl + 2 H2O -> Cl2 + 2 NaOH + H2.
    "r_012": {"chlorine": 1, "sodium_hydroxide": 2, "hydrogen": 1},
    # CH4 -> C + 2 H2.
    "r_078": {"hydrogen": 2, "graphite": 1},
    # 2 H2O -> 2 H2 + O2.
    "r_079": {"hydrogen": 2, "oxygen": 1},
    "r_080": {"hydrogen": 2, "oxygen": 1},
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


def recipe_outputs(recipe):
    return model.pairs(recipe, "output", "output_qty", 5)


def output_ratio(recipe):
    """Return the indivisible integer basket for one recipe batch."""
    outputs = recipe_outputs(recipe)
    if not outputs:
        return []
    override = STOICHIOMETRIC_OUTPUT_RATIOS.get(recipe["recipe_id"])
    if override:
        missing = set(override) ^ {good for good, _qty in outputs}
        if missing:
            raise ValueError(f"{recipe['recipe_id']} stoichiometric outputs do not match data: {sorted(missing)}")
        return [(good, int(override[good])) for good, _qty in outputs]
    integer_quantities = [max(1, int(round(quantity))) for _good, quantity in outputs]
    divisor = integer_quantities[0]
    for quantity in integer_quantities[1:]:
        divisor = math.gcd(divisor, quantity)
    return [(good, quantity // divisor) for (good, _old), quantity in zip(outputs, integer_quantities)]


def current_batch_scale(recipe):
    """Closest scale of the selected output ratio to the deployed total volume."""
    outputs = recipe_outputs(recipe)
    ratio = output_ratio(recipe)
    if not outputs or not ratio:
        return 0.0
    return sum(quantity for _good, quantity in outputs) / sum(quantity for _good, quantity in ratio)


def scaled_outputs(recipe, batch_scale):
    return [(good, quantity * batch_scale) for good, quantity in output_ratio(recipe)]


def primary_output(recipe):
    outputs = recipe_outputs(recipe)
    return outputs[0] if outputs else ("", 0.0)


def output_price(good, prices):
    return model.GRID_SELL if good == "power" else prices[good]


def output_value_weights(outputs, prices):
    """User-selected joint-cost allocation: quantity times market price."""
    raw = [max(0.000001, quantity * output_price(good, prices)) for good, quantity in outputs]
    total = sum(raw)
    return {good: weight / total for (good, _quantity), weight in zip(outputs, raw)}


def is_recycling(recipe):
    label = f"{recipe.get('display_name', '')} {recipe.get('category', '')}".lower()
    return "recycl" in label


def canonical_recipes(recipes, ranks):
    """Choose one non-recycling base route per good to establish its price."""
    producers = defaultdict(list)
    for recipe in recipes:
        for good, quantity in recipe_outputs(recipe):
            if good and good not in {"power", "money"} and quantity:
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


def unique_canonical_recipes(canonical):
    """Joint producers may be canonical for several goods; visit each once."""
    return {recipe["recipe_id"]: recipe for recipe in canonical.values()}.values()


def supply_quantity_floors(canonical):
    """One canonical supplier must cover one canonical consumer building."""
    floors = {
        good: next(quantity for output_good, quantity in recipe_outputs(recipe) if output_good == good)
        for good, recipe in canonical.items()
    }
    for consumer in unique_canonical_recipes(canonical):
        for input_good, required_qty in model.pairs(consumer, "input", "qty", 6):
            if input_good in floors and input_good not in MULTI_TURN_SUPPLY_GOODS:
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


def working_friction(recipe, goods, outputs=None):
    """One-turn market freight and inventory reserve for the formula target."""
    inbound_freight = input_warehouse = 0.0
    for good, quantity in model.pairs(recipe, "input", "qty", 6):
        freight, _mode = model.one_turn_market_freight(good, quantity, goods)
        inbound_freight += freight
        input_warehouse += quantity * model.STORE.get(goods[good].get("transport_class", ""), 0.01)
    output_freight = output_warehouse = 0.0
    for output_good, output_qty in outputs if outputs is not None else recipe_outputs(recipe):
        freight, _mode = model.one_turn_market_freight(output_good, output_qty, goods)
        output_freight += freight
        output_warehouse += output_qty * model.STORE.get(goods[output_good].get("transport_class", ""), 0.01)
    return inbound_freight, input_warehouse, output_freight, output_warehouse


def direct_cost(recipe, building, goods, prices, ranks):
    inputs = sum(qty * prices[good] * (1 + model.BUY_MARKUP) for good, qty in model.pairs(recipe, "input", "qty", 6))
    power = model.f(recipe.get("energy_req")) * model.GRID
    maintenance = model.f(building.get("maintenance_cost")) * model.MAINT_MULT
    labour = formula_labour_cost(recipe, building)
    target = model.target(recipe, ranks)[0]
    inbound_freight, input_warehouse, _output_freight, _output_warehouse = working_friction(recipe, goods, [])
    return inputs, power, maintenance, labour, target, inbound_freight, input_warehouse


def canonical_recipe_scales(canonical, supply_floors):
    """Keep every joint-output canonical recipe on one ratio-preserving scale."""
    scales = {}
    for source in unique_canonical_recipes(canonical):
        recipe = source["recipe_id"]
        scale = current_batch_scale(source)
        ratio = dict(output_ratio(source))
        for good, floor in supply_floors.items():
            if canonical.get(good, {}).get("recipe_id") == recipe and good in ratio:
                scale = max(scale, floor / ratio[good])
        scales[recipe] = scale
    return scales


def solve_prices(goods, buildings, recipes, ranks, canonical, supply_floors):
    prices = {good: model.f(row.get("base_price")) for good, row in goods.items()}
    recipe_scales = canonical_recipe_scales(canonical, supply_floors)
    for _ in range(MAX_PRICE_ITERATIONS):
        next_prices = prices.copy()
        max_change = 0.0
        for good, recipe in canonical.items():
            if good in APPROVED_GOOD_PRICES:
                next_prices[good] = APPROVED_GOOD_PRICES[good]
                continue
            building = buildings[recipe["_building"]]
            inputs, power, maintenance, labour, target, inbound_freight, input_warehouse = direct_cost(recipe, building, goods, prices, ranks)
            outputs = scaled_outputs(recipe, recipe_scales[recipe["recipe_id"]])
            output_freight, output_warehouse = working_friction(recipe, goods, outputs)[2:]
            required_gross_revenue = inputs + power + maintenance + labour + target + inbound_freight + input_warehouse + output_freight + output_warehouse
            weights = output_value_weights(outputs, prices)
            output_qty = next(quantity for output_good, quantity in outputs if output_good == good)
            candidate = required_gross_revenue * weights[good] / output_qty
            updated = prices[good] * (1 - PRICE_DAMPING) + candidate * PRICE_DAMPING
            next_prices[good] = updated
            max_change = max(max_change, abs(updated - prices[good]))
        prices = next_prices
        if max_change < 1e-6:
            return prices, _ + 1
    return prices, MAX_PRICE_ITERATIONS


def plan_recipe(recipe, building, goods, prices, ranks, canonical, supply_floors):
    current_outputs = recipe_outputs(recipe)
    if not current_outputs:
        return None
    inputs, power, maintenance, labour, target, inbound_freight, input_warehouse = direct_cost(recipe, building, goods, prices, ranks)
    low, high = model.target(recipe, ranks)[1:3]
    fixed_cost = inputs + power + maintenance + labour + inbound_freight + input_warehouse
    ratio = output_ratio(recipe)
    net_batch_revenue = 0.0
    for good, quantity in ratio:
        freight, _mode = model.one_turn_market_freight(good, quantity, goods)
        warehouse = quantity * model.STORE.get(goods[good].get("transport_class", ""), 0.01)
        net_batch_revenue += quantity * output_price(good, prices) - freight - warehouse
    if net_batch_revenue <= 0:
        return None
    required_scale = (fixed_cost + target) / net_batch_revenue
    minimum_scale = 1.0
    ratio_by_good = dict(ratio)
    for good, floor in supply_floors.items():
        if canonical.get(good, {}).get("recipe_id") == recipe["recipe_id"] and good in ratio_by_good:
            minimum_scale = max(minimum_scale, floor / ratio_by_good[good])
    if len(ratio) == 1:
        candidates = human_output_candidates(required_scale, minimum_scale)
    else:
        reference = max(required_scale, minimum_scale)
        candidates = {
            scale: "integer ratio batch"
            for scale in {max(1, math.floor(reference)), max(1, math.ceil(reference))}
            if scale >= minimum_scale
        }
    approved_scale = APPROVED_OUTPUT_BATCH_SCALES.get(recipe["recipe_id"])
    if approved_scale is not None:
        if approved_scale < minimum_scale:
            raise ValueError(
                f"{recipe['recipe_id']} approved output scale {approved_scale} "
                f"is below canonical supply floor {minimum_scale:g}"
            )
        candidates = {approved_scale: "approved industrial batch"}
    profit_for = lambda scale: scale * net_batch_revenue - fixed_cost
    in_band = [scale for scale in candidates if low - 1e-6 <= profit_for(scale) <= high + 1e-6]
    suggested_scale = min(in_band or candidates, key=lambda scale: (abs(profit_for(scale) - target), abs(scale - required_scale)))
    suggested_outputs = scaled_outputs(recipe, suggested_scale)
    output_good, current_qty = primary_output(recipe)
    suggested_qty = suggested_outputs[0][1]
    profit = profit_for(suggested_scale)
    return {
        "recipe_id": recipe["recipe_id"],
        "recipe": recipe.get("display_name", ""),
        "building": recipe["_building"],
        "primary_output": output_good,
        "formula_price": round(output_price(output_good, prices), 3),
        "output_ratio": "|".join(f"{good}:{quantity:g}" for good, quantity in ratio),
        "suggested_outputs": "|".join(f"{good}:{quantity:g}" for good, quantity in suggested_outputs),
        "current_output_qty": current_qty,
        "canonical_supply_floor": supply_floors.get(output_good, ""),
        "unrounded_output_qty": round(required_scale * ratio[0][1], 3),
        "suggested_output_qty": suggested_qty,
        "output_rounding": candidates[suggested_scale],
        "output_multiplier": round(suggested_scale / current_batch_scale(recipe), 3),
        "labour_unskilled": formula_staff(recipe, building)[0],
        "labour_skilled": formula_staff(recipe, building)[1],
        "labour_h_skilled": formula_staff(recipe, building)[2],
        "labour_bill": round(labour, 3),
        "input_bill": round(inputs, 3),
        "energy_bill": round(power, 3),
        "maintenance_bill": round(maintenance, 3),
        "one_turn_inbound_freight": round(inbound_freight, 3),
        "one_turn_outbound_freight": round(working_friction(recipe, goods, suggested_outputs)[2], 3),
        "one_turn_working_inventory_warehouse_reserve": round(input_warehouse + working_friction(recipe, goods, suggested_outputs)[3], 3),
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
    for consumer in unique_canonical_recipes(canonical):
        for input_good, required_qty in model.pairs(consumer, "input", "qty", 6):
            supplier = canonical.get(input_good)
            if not supplier or supplier["recipe_id"] not in plan_by_id:
                continue
            supplied_outputs = {
                item.split(":", 1)[0]: float(item.split(":", 1)[1])
                for item in plan_by_id[supplier["recipe_id"]]["suggested_outputs"].split("|")
            }
            supplied_qty = supplied_outputs[input_good]
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
        handle.write(f"- All-output-basket recipes in their target profit band after formula output quantities: {covered} / {len(plans)}\n")
        handle.write(f"- Recipes using explicit industrial stoichiometric output ratios: {len(STOICHIOMETRIC_OUTPUT_RATIOS)}\n")
        handle.write(f"- Canonical supply links requiring more than one supplier building: {supply_violations} / {len(supply_rows)}\n")
        handle.write(f"- Workload factor: `clamp({WORKLOAD_FLOOR}, {WORKLOAD_CEILING}, sqrt(max(input_qty, 10) / {WORKLOAD_REFERENCE}))`\n")
        handle.write("- Recommended outputs above 36 use a nearby multiple of 5 or 12, while retaining canonical one-building supply floors.\n")
    print(f"Canonical prices: {len(canonical)}; planned recipes in target band: {covered} / {len(plans)}; supply violations: {supply_violations}; iterations: {iterations}")


if __name__ == "__main__":
    run()
