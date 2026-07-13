#!/usr/bin/env python3
"""Read-only rebalance model for the live recipe CSVs.

The model uses one-turn logistics: rail for solids (half road cost), pipes for
liquids/gases, and roads only as a fallback. It never changes game data.
"""
from __future__ import annotations

import csv
import math
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
OUT = ROOT / "reports" / "balance"
ALIASES = {"power_plant": "coal_power", "factory": "industrial_factory", "industrial_goods_factory": "industrial_factory", "consumer_goods_factory": "consumer_factory", "water_well": "water_pump", "desal_plant": "desal", "water_treatment_plant": "water_recycling", "hydro_dam": "hydro_power_plant", "forest": "new_forest"}
WAGE = (0.0032, 0.0096, 0.032)
# Every active recipe must retain a baseline operating crew.  The third figure
# is highly skilled labour (the user-facing shorthand is "skilled").
MIN_STAFF = (500, 100, 50)
MIN_LABOUR_COST = sum(count * wage for count, wage in zip(MIN_STAFF, WAGE))
GRID = 0.10
GRID_SELL = 0.06
BUY_MARKUP = 0.05
# Capital is shown separately from operating cash and levelized over the live
# 36-turn loan term.  It is an analysis horizon, not a new simulation rule.
POWER_INVESTMENT_HORIZON_TURNS = 36
# Live L1 storage calibration from EconomyConfig: 18 lithium cells fill 1000
# firming units.  One L1 housing therefore covers every base onshore-wind run.
BATTERY_L1_FIRMING = 1000.0
LITHIUM_CELLS_PER_L1 = 18.0
# The live production loop charges the building CSV maintenance value once per
# turn.  Keep this in lock-step with Production._calculate_maintenance_cost():
# applying the retired 2x multiplier here made every formula margin too low.
MAINT_MULT = 1.0
EXTRACTION_PENALTY_PCT = {
    "coal": -30.0,
    "iron_ore": -30.0,
    "copper_ore": -30.0,
    "limestone": -30.0,
    "sand": -30.0,
    "basic_salt": -30.0,
    "ree_ore": -30.0,
    "alloy_ore": -30.0,
    "sulphur": -15.0,
    "bauxite_ore": -15.0,
}
CAP_SENSITIVITY_FIELDS = (
    "recipe_id", "recipe", "output_good", "current_base_price",
    "max_base_price_for_400_cap", "price_reduction_per_unit",
    "standalone_after_cap_price_with_minimum_labour",
    "price_only_keeps_start_margin", "downstream_consumer_count",
    "downstream_consumers",
)
ROAD = {"standard": .02, "solid_light": .02, "solid_heavy": .03, "ultra_heavy": .06, "safe_liquid": .03, "hazard_liquid": .03, "liquid": .03, "gas": .03, "electricity": .02}
STORE = {"solid_light": .01, "solid_heavy": .01, "ultra_heavy": .01, "safe_liquid": .03, "liquid": .03, "hazard_liquid": .10, "gas": .10, "electricity": 0.0}
SOLIDS = {"solid_light", "solid_heavy", "ultra_heavy"}
PIPEABLE = {"safe_liquid", "hazard_liquid", "liquid", "gas"}
ADVANCED = {"chem_plant", "bio_chem_plant", "poly_plant", "assembly_plant", "high_tech_manufactory", "electrolyser", "eaf"}
MIX = {"mine": (.85,.13,.02), "furnace": (.70,.25,.05), "industrial_factory": (.60,.32,.08), "chem_plant": (.40,.40,.20), "bio_chem_plant": (.35,.40,.25), "poly_plant": (.35,.45,.20), "assembly_plant": (.30,.45,.25), "high_tech_manufactory": (.20,.45,.35), "electrolyser": (.25,.45,.30), "eaf": (.35,.45,.20)}
DEFAULT_TARGETS = {
    # Target is pre-tax cash after a representative one-turn market leg and a
    # one-turn working-inventory warehouse reserve, not a headline revenue
    # margin.  £7.50 leaves ordinary starter recipes in the requested £5–10
    # range once those new operating frictions are paid.
    0: (7.5, 5.0, 10.0, "start-unlocked after freight and warehouse reserve"),
    1: (15.0, 5.0, 30.0, "rank I default"),
    2: (30.0, 20.0, 60.0, "rank II default"),
    3: (60.0, 30.0, 100.0, "rank III default"),
}
RECIPE_TARGET_OVERRIDES = {
    "r_023": (5.0, 0.0, 5.0, "ethylene keeps the upper starter margin"),
    "r_024": (5.0, 0.0, 5.0, "plastics keeps the upper starter margin"),
    "r_039": (20.0, 15.0, 25.0, "lithium electrolysis remains a modest advanced route"),
    "r_040": (3.6, 0.0, 5.0, "alumina supports the aluminium starter chain"),
    "r_050": (5.0, 0.0, 5.0, "aluminium keeps the upper starter margin"),
    "r_067": (4.2, 0.0, 5.0, "tyres support modest direct integration"),
    "r_099": (45.0, 30.0, 60.0, "researched LFP batteries should profitably outperform conventional lithium-ion cells"),
    "r_136": (5.0, 0.0, 10.0, "iron-air cells are a deliberately thin-margin route to cheap bulk storage"),
    "r_115": (5.0, 0.0, 10.0, "sulphuric acid should be modestly profitable"),
    "r_116": (-12.5, -20.0, -5.0, "generic acid should be deliberately loss-making"),
    "r_118": (40.0, 30.0, 50.0, "automated ICE assembly should beat the base recipe margin"),
    "r_119": (65.0, 30.0, 100.0, "unlocked EVs can carry larger base profit"),
    "r_124": (60.0, 40.0, 80.0, "3D semiconductor printing has a controlled advanced margin"),
    "r_165": (7.5, 0.0, 15.0, "radial axial tyres should be modestly profitable"),
    "r_204": (15.0, 0.0, 30.0, "base heavy vehicles should stay slightly profitable"),
    "r_205": (50.0, 30.0, 70.0, "automated heavy vehicles should have a controlled advanced margin"),
    "r_206": (60.0, 60.0, 90.0, "electric heavy vehicles should lead the heavy vehicle tier without breaching the integration cap"),
}
FORCED_CHAIN_SCENARIOS = {
    "Steelmaking + regular pig-iron furnace": ("r_003", {"iron_ingots": "r_005", "coal": "r_001"}),
    "Base motors + steel furnace + copper wiring factory": ("r_009", {"steel": "r_003", "copper_wiring": "r_008"}),
    "Aluminium + alumina refinery": ("r_050", {"alumina": "r_040"}),
    "Aluminium windows + glass + aluminium": ("r_056", {"glass": "r_053", "aluminium": "r_050"}),
    "Building frames + steel, windows, copper pipe, electrical components": ("r_057", {"steel": "r_003", "windows": "r_056", "copper_pipe": "r_220", "electrical_components": "r_126"}),
    "Construction equipment (ICE) + conventional direct suppliers": ("r_033", {"steel": "r_003", "rubber": "r_028", "plastics": "r_024", "fuels": "r_022", "motor": "r_009"}),
    "Tyres + rubber + sulphur": ("r_067", {"rubber": "r_028", "sulphur": "r_179"}),
    "Plastics + ethylene refinery": ("r_024", {"ethylene": "r_023"}),
}

# These are deliberately concrete arrangements, not a search for the cheapest
# producer.  Every listed plant is co-located, its output is counted in whole
# buildings, and any genuine excess can either be sold or held.  That matches
# what a player actually builds and avoids the old fractional-furnace mistake.
INTEGER_CHAIN_SCENARIOS = {
    "Steel + pig iron; market coal and iron ore": ("r_003", {"iron_ingots": "r_005"}),
    "Steel + pig iron + coal mine": ("r_003", {"iron_ingots": "r_005", "coal": "r_001"}),
    "Base motors + steel furnace + copper wiring factory": ("r_009", {"steel": "r_003", "copper_wiring": "r_008"}),
    "Aluminium + alumina refinery": ("r_050", {"alumina": "r_040"}),
    "Windows + industrial glass + Hall-Heroult aluminium": ("r_056", {"glass": "r_053", "aluminium": "r_050"}),
    "Windows + high-strength glass + Hall-Heroult aluminium": ("r_056", {"glass": "r_054", "aluminium": "r_050"}),
    "Windows + industrial glass; market aluminium": ("r_056", {"glass": "r_053"}),
    "Building frames + direct suppliers": ("r_057", {"steel": "r_003", "windows": "r_056", "copper_pipe": "r_220", "electrical_components": "r_126"}),
    "Construction equipment (ICE) + conventional direct suppliers": ("r_033", {"steel": "r_003", "rubber": "r_028", "plastics": "r_024", "fuels": "r_022", "motor": "r_009"}),
    "Tyres + rubber + sulphur": ("r_067", {"rubber": "r_028", "sulphur": "r_179"}),
    "Plastics + ethylene refinery": ("r_024", {"ethylene": "r_023"}),
}
INTEGER_CHAIN_TARGETS = {
    "Steel + pig iron; market coal and iron ore": (15.0, 10.0, 25.0),
    "Windows + industrial glass; market aluminium": (15.0, 10.0, 25.0),
}

def f(x):
    try: return float(x or 0)
    except ValueError: return 0.0
def i(x): return int(round(f(x)))
def read(path):
    with open(path, newline="", encoding="utf-8-sig") as h: return list(csv.DictReader(h))
def pairs(row, stem, qty, n):
    return [(row.get(f"{stem}_{x}", "").strip(), f(row.get(f"{qty}_{x}"))) for x in range(1,n+1) if row.get(f"{stem}_{x}", "").strip() and f(row.get(f"{qty}_{x}")) > 0]

def load():
    goods = {r["internal_name"]: r for r in read(DATA / "Goods - goodsMVP.csv")}
    buildings = {r["internal_name"]: r for r in read(DATA / "Buildings - buildingsMVP.csv")}
    raw = read(DATA / "recipes_all.csv")
    active = []
    for r in raw:
        b = ALIASES.get(r.get("building_id", ""), r.get("building_id", ""))
        ins, outs = pairs(r,"input","qty",6), pairs(r,"output","output_qty",5)
        catalysts = [x.strip() for x in r.get("catalysts", "").replace("|",";").split(";") if x.strip()]
        if b in buildings and (ins or outs or catalysts) and all(g in goods for g,_ in ins+outs) and all(g in goods for g in catalysts):
            r["_building"] = b
            active.append(r)
    return goods, buildings, raw, active

def labour(r, b):
    # Recipe values win once the labour migration is present; current CSVs fall back to building data.
    vals = []
    for col, fallback in (("labour_unskilled_required","labour_unskilled_required"),("labour_skilled_required","labour_skilled_required"),("labour_h_skilled_required","labour_h_skilled_required")):
        vals.append(i(r[col]) if r.get(col, "") != "" else i(b.get(fallback)))
    return sum(x*y for x,y in zip(vals,WAGE))

def revenue(r, goods):
    total = 0.0
    for g,q in pairs(r,"output","output_qty",5):
        total += q * (0.06 if g == "power" else f(goods[g].get("base_price")))
    return total

def route(good):
    """A single turn, selecting the cheaper compatible transport mode."""
    cls = good.get("transport_class", "") or "standard"
    road = ROAD.get(cls, ROAD["standard"])
    if cls in SOLIDS: return road * .5, "rail_1_turn"
    if cls in PIPEABLE: return road, "pipe_1_turn"
    return road, "road_1_turn"

def friction(r, goods):
    transport = storage = 0.0
    modes = set()
    for g,q in pairs(r,"input","qty",6) + pairs(r,"output","output_qty",5):
        rate, mode = route(goods[g]); modes.add(mode)
        transport += q * rate
        storage += q * STORE.get(goods[g].get("transport_class", ""), .01)
    return transport, storage, "+".join(sorted(modes))

def imputed(goods, buildings, recipes, power, labour_costs=None):
    costs = {g:f(row.get("base_price"))*(1+BUY_MARKUP) for g,row in goods.items()}
    costs["power"] = power
    for _ in range(200):
        changed = False
        for r in recipes:
            b = buildings[r["_building"]]; outs = pairs(r,"output","output_qty",5)
            if not outs: continue
            labour_cost = labour_costs.get(r["recipe_id"], labour(r,b)) if labour_costs else labour(r,b)
            direct = sum(q*costs[g] for g,q in pairs(r,"input","qty",6)) + f(r.get("energy_req"))*power + labour_cost + f(b.get("maintenance_cost"))*MAINT_MULT
            weights = [max(.000001, q*(.06 if g=="power" else f(goods[g].get("base_price")))) for g,q in outs]
            for (g,q),w in zip(outs,weights):
                if g == "power":
                    # `power` is an explicit scenario valuation (grid import,
                    # export opportunity, coal/oil, or firmed wind).  Letting
                    # the generic imputed-cost loop reduce it would silently
                    # reintroduce the old cheapest-generator bug.
                    continue
                candidate = direct*w/sum(weights)/q
                if candidate < costs[g] - 1e-8: costs[g] = candidate; changed = True
        if not changed: break
    return costs

def power_cost(goods, buildings, recipes, costs, labour_costs=None):
    """Legacy technical production-cost floor.

    Do not use this as the economic value of internally consumed electricity:
    a generated unit can be sold for GRID_SELL, so its operating opportunity
    cost cannot be below that export price.  Kept for report compatibility.
    """
    candidates=[]
    for r in recipes:
        qty=sum(q for g,q in pairs(r,"output","output_qty",5) if g=="power")
        if not qty: continue
        b=buildings[r["_building"]]
        labour_cost = labour_costs.get(r["recipe_id"], labour(r,b)) if labour_costs else labour(r,b)
        total=sum(q*costs[g] for g,q in pairs(r,"input","qty",6))+labour_cost+f(b.get("maintenance_cost"))*MAINT_MULT+f(r.get("energy_req"))*GRID
        candidates.append(total/qty)
    return min(candidates, default=GRID)


def building_capital_cost(building, goods):
    """Market-acquisition value of a building's cash and material kit."""
    total = f(building.get("build_cost_money"))
    for index in range(1, 8):
        good = str(building.get(f"build_material_{index}", "")).strip()
        quantity = f(building.get(f"build_qty_{index}"))
        if good and quantity > 0 and good in goods:
            total += quantity * f(goods[good].get("base_price")) * (1 + BUY_MARKUP)
    return total


def _power_generator_scenario(label, recipe, goods, buildings, battery_recipe=None):
    building = buildings[recipe["_building"]]
    output = output_qty(recipe, "power")
    if output <= 0:
        raise ValueError(f"{recipe['recipe_id']} has no power output")
    fuel_inputs = pairs(recipe, "input", "qty", 6)
    fuel_bill = sum(quantity * f(goods[good].get("base_price")) * (1 + BUY_MARKUP) for good, quantity in fuel_inputs)
    generator_labour = labour(recipe, building)
    generator_maintenance = f(building.get("maintenance_cost")) * MAINT_MULT
    battery_buildings = 0
    battery_cells = 0
    battery_locked_capital = 0.0
    battery_housing_capital = 0.0
    battery_labour = 0.0
    battery_maintenance = 0.0
    if battery_recipe is not None:
        battery_building = buildings[battery_recipe["_building"]]
        battery_buildings = int(math.ceil(output / BATTERY_L1_FIRMING))
        firming_per_cell = BATTERY_L1_FIRMING / LITHIUM_CELLS_PER_L1
        battery_cells = int(math.ceil(output / firming_per_cell))
        battery_locked_capital = battery_cells * f(goods["lithium_battery"].get("base_price")) * (1 + BUY_MARKUP)
        battery_housing_capital = battery_buildings * building_capital_cost(battery_building, goods)
        battery_labour = battery_buildings * labour(battery_recipe, battery_building)
        battery_maintenance = battery_buildings * f(battery_building.get("maintenance_cost")) * MAINT_MULT
    generator_capital = building_capital_cost(building, goods)
    total_investment = generator_capital + battery_housing_capital + battery_locked_capital
    operating_cost = fuel_bill + generator_labour + generator_maintenance + battery_labour + battery_maintenance
    operating_unit_cost = operating_cost / output
    levelized_unit_cost = (operating_cost + total_investment / POWER_INVESTMENT_HORIZON_TURNS) / output
    return {
        "scenario": label,
        "source_recipe_id": recipe["recipe_id"],
        "source_recipe": recipe.get("display_name", ""),
        "generator_output": output,
        "grid_purchase_price": GRID,
        "grid_sale_price": GRID_SELL,
        "fuel_inputs": "; ".join(f"{good} {quantity:g}" for good, quantity in fuel_inputs) or "none",
        "fuel_market_bill": fuel_bill,
        "generator_labour_bill": generator_labour,
        "generator_maintenance_bill": generator_maintenance,
        "battery_buildings": battery_buildings,
        "lithium_cells_locked": battery_cells,
        "battery_labour_bill": battery_labour,
        "battery_maintenance_bill": battery_maintenance,
        "generator_capital": generator_capital,
        "battery_housing_capital": battery_housing_capital,
        "battery_cell_locked_capital": battery_locked_capital,
        "total_investment": total_investment,
        "investment_horizon_turns": POWER_INVESTMENT_HORIZON_TURNS,
        "operating_cost_per_power": operating_unit_cost,
        "levelized_cost_per_power": levelized_unit_cost,
        "short_run_opportunity_cost_per_power": max(GRID_SELL, operating_unit_cost),
        "long_run_opportunity_cost_per_power": max(GRID_SELL, levelized_unit_cost),
    }


def power_opportunity_scenarios(goods, buildings, recipes):
    """Comparable grid and owned-generation electricity valuations."""
    recipe_by_id = {recipe["recipe_id"]: recipe for recipe in recipes}
    rows = [
        {
            "scenario": "grid purchase",
            "source_recipe_id": "",
            "source_recipe": "National grid import",
            "generator_output": "",
            "grid_purchase_price": GRID,
            "grid_sale_price": GRID_SELL,
            "fuel_inputs": "none",
            "investment_horizon_turns": POWER_INVESTMENT_HORIZON_TURNS,
            "operating_cost_per_power": GRID,
            "levelized_cost_per_power": GRID,
            "short_run_opportunity_cost_per_power": GRID,
            "long_run_opportunity_cost_per_power": GRID,
        },
        {
            "scenario": "foregone grid sale",
            "source_recipe_id": "",
            "source_recipe": "Existing surplus generation",
            "generator_output": "",
            "grid_purchase_price": GRID,
            "grid_sale_price": GRID_SELL,
            "fuel_inputs": "none",
            "investment_horizon_turns": POWER_INVESTMENT_HORIZON_TURNS,
            "operating_cost_per_power": GRID_SELL,
            "levelized_cost_per_power": GRID_SELL,
            "short_run_opportunity_cost_per_power": GRID_SELL,
            "long_run_opportunity_cost_per_power": GRID_SELL,
        },
        _power_generator_scenario("coal power", recipe_by_id["r_004"], goods, buildings),
        _power_generator_scenario("oil power", recipe_by_id["r_181"], goods, buildings),
        _power_generator_scenario("onshore wind + lithium battery", recipe_by_id["r_037"], goods, buildings, recipe_by_id["r_225"]),
    ]
    fields = (
        "scenario", "source_recipe_id", "source_recipe", "generator_output", "grid_purchase_price", "grid_sale_price",
        "fuel_inputs", "fuel_market_bill", "generator_labour_bill", "generator_maintenance_bill", "battery_buildings",
        "lithium_cells_locked", "battery_labour_bill", "battery_maintenance_bill", "generator_capital",
        "battery_housing_capital", "battery_cell_locked_capital", "total_investment", "investment_horizon_turns",
        "operating_cost_per_power", "levelized_cost_per_power", "short_run_opportunity_cost_per_power",
        "long_run_opportunity_cost_per_power",
    )
    for row in rows:
        for field in fields:
            row.setdefault(field, 0.0 if field not in {"source_recipe_id", "source_recipe", "fuel_inputs", "generator_output"} else "")
    return rows, fields


def write_power_opportunity_report(goods, buildings, recipes):
    rows, fields = power_opportunity_scenarios(goods, buildings, recipes)
    with open(OUT / "power_opportunity_costs.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: round(value, 6) if isinstance(value, float) else value for key, value in row.items()})
    return rows

def recommended_labour_costs(goods, buildings, recipes, ranks):
    """Return the labour budget needed to put each recipe in its target band."""
    result = {}
    for r in recipes:
        b = buildings[r["_building"]]
        rev = revenue(r, goods)
        market = sum(q * f(goods[g].get("base_price")) * (1 + BUY_MARKUP) for g, q in pairs(r, "input", "qty", 6))
        energy = f(r.get("energy_req")) * GRID
        maint = f(b.get("maintenance_cost")) * MAINT_MULT
        targ, _low, _high, _policy, _rank = target(r, ranks)
        _counts, cost = suggested_staffing(r["_building"], rev - market - energy - maint - targ)
        result[r["recipe_id"]] = cost
    return result

def one_layer_input_costs(goods, buildings, recipes, recommended_labour):
    """Cheapest direct producer cost, with the producer's own inputs at market.

    This is intentionally one pass: it represents owning the selected direct
    supplier, not recursively integrating that supplier's own supply chain.
    """
    costs = {g: f(row.get("base_price")) * (1 + BUY_MARKUP) for g, row in goods.items()}
    suppliers = {}
    for r in recipes:
        b = buildings[r["_building"]]
        outs = pairs(r, "output", "output_qty", 5)
        if not outs:
            continue
        direct = sum(q * f(goods[g].get("base_price")) * (1 + BUY_MARKUP) for g, q in pairs(r, "input", "qty", 6))
        direct += f(r.get("energy_req")) * GRID + f(b.get("maintenance_cost")) * MAINT_MULT + recommended_labour[r["recipe_id"]]
        weights = [max(.000001, q * (.06 if g == "power" else f(goods[g].get("base_price")))) for g, q in outs]
        for (g, q), weight in zip(outs, weights):
            candidate = direct * weight / sum(weights) / q
            if candidate < costs[g] - 1e-8:
                costs[g] = candidate
                suppliers[g] = r
    return costs, suppliers

def allocated_recipe_output_cost(recipe, output_good, goods, buildings, recommended_labour):
    """Market-input cost of a nominated direct supplier, allocated by output value."""
    building = buildings[recipe["_building"]]
    direct = sum(q * f(goods[g].get("base_price")) * (1 + BUY_MARKUP) for g, q in pairs(recipe, "input", "qty", 6))
    direct += f(recipe.get("energy_req")) * GRID + f(building.get("maintenance_cost")) * MAINT_MULT + recommended_labour[recipe["recipe_id"]]
    outputs = pairs(recipe, "output", "output_qty", 5)
    weights = [max(.000001, q * (.06 if g == "power" else f(goods[g].get("base_price")))) for g, q in outputs]
    for (good, qty), weight in zip(outputs, weights):
        if good == output_good:
            return direct * weight / sum(weights) / qty
    raise ValueError(f"{recipe['recipe_id']} does not produce {output_good}")

def forced_chain_profit(recipe, sources, goods, buildings, recipe_by_id, recommended_labour):
    """Profit for the named building plus exactly the named direct suppliers."""
    building = buildings[recipe["_building"]]
    input_cost = 0.0
    for good, qty in pairs(recipe, "input", "qty", 6):
        if good in sources:
            input_cost += qty * allocated_recipe_output_cost(recipe_by_id[sources[good]], good, goods, buildings, recommended_labour)
        else:
            input_cost += qty * f(goods[good].get("base_price")) * (1 + BUY_MARKUP)
    return revenue(recipe, goods) - input_cost - f(recipe.get("energy_req")) * GRID - f(building.get("maintenance_cost")) * MAINT_MULT - recommended_labour[recipe["recipe_id"]]


def output_qty(recipe, good):
    for output_good, quantity in pairs(recipe, "output", "output_qty", 5):
        if output_good == good:
            return quantity
    return 0.0


def godot_round_nonnegative(value):
    """Match Godot round() for the non-negative recipe quantities used here."""
    # Decimal halves such as 45 * 0.7 can land just below the exact value in
    # binary floating point. The epsilon preserves Godot's half-up outcome.
    return math.floor(value + 0.5 + 1e-9)


def extraction_startup_revenue(recipe, goods):
    """Day-one mine revenue after the live per-output deposit penalties."""
    total = 0.0
    for good, quantity in pairs(recipe, "output", "output_qty", 5):
        pct = EXTRACTION_PENALTY_PCT.get(good, 0.0)
        deployed_quantity = godot_round_nonnegative(quantity * (1.0 + pct / 100.0))
        total += deployed_quantity * f(goods[good].get("base_price"))
    return total


def one_turn_market_freight(good, quantity, goods):
    """Freight for a representative one-turn market leg.

    Solids use rail where it is available because it is cheaper than road;
    liquids/gases use pipe; other goods use road.  This is deliberately only
    market freight: plant-to-plant transfers in an analysed chain are on the
    same tile and therefore cost nothing.
    """
    if good == "power":
        return 0.0, "grid"
    rate, mode = route(goods[good])
    return quantity * rate, mode


def one_turn_recipe_friction(recipe, goods):
    """Representative logistics cushion for a standalone recipe.

    The live game only charges warehouse rent on stock that remains at the
    end of a turn.  For balance targets we reserve one turn of each recipe's
    normal inputs and outputs, so the target remains viable with a practical
    working buffer rather than only in perfect just-in-time play.
    """
    inbound_freight = outbound_freight = warehouse_reserve = 0.0
    for good, quantity in pairs(recipe, "input", "qty", 6):
        freight, _mode = one_turn_market_freight(good, quantity, goods)
        inbound_freight += freight
        warehouse_reserve += quantity * STORE.get(goods[good].get("transport_class", ""), 0.01)
    for good, quantity in pairs(recipe, "output", "output_qty", 5):
        freight, _mode = one_turn_market_freight(good, quantity, goods)
        outbound_freight += freight
        warehouse_reserve += quantity * STORE.get(goods[good].get("transport_class", ""), 0.01)
    return inbound_freight, outbound_freight, warehouse_reserve


def _quantity_text(values):
    return "; ".join(
        f"{good} {quantity:g}"
        for good, quantity in sorted(values.items())
        if quantity > 1e-9
    ) or "none"


def _recipe_count_text(counts, recipe_by_id):
    return "; ".join(
        f"{recipe_id} ×{count} {recipe_by_id[recipe_id].get('display_name', '')}".strip()
        for recipe_id, count in sorted(counts.items())
        if count > 0
    )


def _integer_chain_counts(root_id, sources, recipe_by_id):
    """Resolve selected suppliers into full, integer plant counts.

    A selected supplier covers demand from the root *and* all other selected
    suppliers.  For example, a coal mine in the steel chain supplies both the
    steel furnace and the pig-iron furnace.  Inputs without a selected source
    remain market purchases.
    """
    counts = {root_id: 1}
    for _ in range(24):
        demand = defaultdict(float)
        for recipe_id, building_count in counts.items():
            for good, quantity in pairs(recipe_by_id[recipe_id], "input", "qty", 6):
                demand[good] += quantity * building_count
        next_counts = {root_id: 1}
        for good, supplier_id in sources.items():
            if supplier_id not in recipe_by_id:
                raise ValueError(f"{supplier_id} is not an active recipe")
            supplied_per_building = output_qty(recipe_by_id[supplier_id], good)
            if supplied_per_building <= 0:
                raise ValueError(f"{supplier_id} does not produce {good}")
            required = demand[good]
            if required > 0:
                next_counts[supplier_id] = max(
                    next_counts.get(supplier_id, 0),
                    int(math.ceil(required / supplied_per_building)),
                )
        if next_counts == counts:
            return counts
        counts = next_counts
    raise ValueError("selected supplier chain did not converge")


def integer_chain_report(label, root_id, sources, goods, buildings, recipe_by_id):
    """Cash analysis for an explicitly selected, whole-building supply chain.

    The two rows returned distinguish a settled tile with Sell surplus enabled
    from a tile that keeps the excess in storage for one more turn.  Labour and
    maintenance come from the deployed recipe/building data; no labour budget
    is back-solved from a target margin.
    """
    counts = _integer_chain_counts(root_id, sources, recipe_by_id)
    demand, produced = defaultdict(float), defaultdict(float)
    labour_cost = maintenance_cost = grid_power_cost = 0.0
    for recipe_id, building_count in counts.items():
        recipe = recipe_by_id[recipe_id]
        building = buildings[recipe["_building"]]
        labour_cost += labour(recipe, building) * building_count
        maintenance_cost += f(building.get("maintenance_cost")) * MAINT_MULT * building_count
        grid_power_cost += f(recipe.get("energy_req")) * GRID * building_count
        for good, quantity in pairs(recipe, "input", "qty", 6):
            demand[good] += quantity * building_count
        for good, quantity in pairs(recipe, "output", "output_qty", 5):
            produced[good] += quantity * building_count

    external = {}
    internal = {}
    surplus = {}
    all_goods = set(demand) | set(produced)
    for good in all_goods:
        internal[good] = min(demand[good], produced[good])
        external[good] = max(0.0, demand[good] - produced[good])
        surplus[good] = max(0.0, produced[good] - demand[good])

    market_inputs = 0.0
    inbound_freight = 0.0
    modes = set()
    for good, quantity in external.items():
        if quantity <= 0:
            continue
        market_inputs += quantity * (0.06 if good == "power" else f(goods[good].get("base_price"))) * (1 + BUY_MARKUP)
        freight, mode = one_turn_market_freight(good, quantity, goods)
        inbound_freight += freight
        modes.add(mode)

    market_sales = 0.0
    outbound_freight = 0.0
    inventory_value = 0.0
    warehouse_cost = 0.0
    for good, quantity in surplus.items():
        if quantity <= 0:
            continue
        unit_price = 0.06 if good == "power" else f(goods[good].get("base_price"))
        market_sales += quantity * unit_price
        freight, mode = one_turn_market_freight(good, quantity, goods)
        outbound_freight += freight
        modes.add(mode)
        inventory_value += quantity * unit_price
        warehouse_cost += quantity * STORE.get(goods[good].get("transport_class", ""), 0.01)

    # Use the same one-turn working-buffer convention as standalone recipes
    # when evaluating a cluster target.  This is distinct from the actual
    # warehouse bill in the "hold surplus" scenario below.
    working_warehouse_reserve = sum(
        (demand[good] + produced[good]) * STORE.get(goods[good].get("transport_class", ""), 0.01)
        for good in all_goods
    )
    target_profit, target_min, target_max = INTEGER_CHAIN_TARGETS.get(label, ("", "", ""))

    base = {
        "chain": label,
        "root_recipe_id": root_id,
        "selected_suppliers": "; ".join(f"{good}: {recipe_id}" for good, recipe_id in sources.items()),
        "deployed_components": _recipe_count_text(counts, recipe_by_id),
        "building_count": sum(counts.values()),
        "internal_flows": _quantity_text(internal),
        "market_inputs": _quantity_text(external),
        "surplus_outputs": _quantity_text(surplus),
        "market_input_bill": market_inputs,
        "grid_power_bill": grid_power_cost,
        "labour_bill": labour_cost,
        "maintenance_bill": maintenance_cost,
        "inbound_freight": inbound_freight,
        "assumed_transport": "+".join(sorted(modes)) or "none",
        "held_surplus_market_value": inventory_value,
        "working_inventory_warehouse_reserve": working_warehouse_reserve,
        "cluster_target_profit": target_profit,
        "cluster_target_min": target_min,
        "cluster_target_max": target_max,
    }
    rows = []
    for scenario, sell_surplus in (("settled auto-sell", True), ("hold surplus for one turn", False)):
        sale_revenue = market_sales if sell_surplus else 0.0
        sale_freight = outbound_freight if sell_surplus else 0.0
        warehousing = 0.0 if sell_surplus else warehouse_cost
        operating = sale_revenue - market_inputs - grid_power_cost - labour_cost - maintenance_cost - inbound_freight - sale_freight - warehousing
        taxes = max(0.0, operating) * 0.20
        post_tax = operating - taxes
        dividends = max(0.0, post_tax) * 0.20
        row = base | {
            "scenario": scenario,
            "market_sale_revenue": sale_revenue,
            "outbound_freight": sale_freight,
            "warehousing_bill": warehousing,
            "operating_profit": operating,
            "pre_tax_profit_after_freight_and_warehouse_reserve": operating - working_warehouse_reserve,
            "taxes": taxes,
            "dividends": dividends,
            "net_cash_after_tax_dividends": post_tax - dividends,
            "in_cluster_target_after_friction_reserve": (
                target_min - 1e-6 <= operating - working_warehouse_reserve <= target_max + 1e-6
                if scenario == "settled auto-sell" and target_min != "" else ""
            ),
        }
        rows.append({key: round(value, 3) if isinstance(value, float) else value for key, value in row.items()})
    return rows


def write_integer_chain_report(goods, buildings, recipe_by_id):
    rows = []
    for label, (root_id, sources) in INTEGER_CHAIN_SCENARIOS.items():
        try:
            rows.extend(integer_chain_report(label, root_id, sources, goods, buildings, recipe_by_id))
        except ValueError as exc:
            rows.append({"chain": label, "root_recipe_id": root_id, "scenario": "analysis error", "analysis_error": str(exc)})
    fields = (
        "chain", "scenario", "root_recipe_id", "selected_suppliers", "deployed_components", "building_count",
        "internal_flows", "market_inputs", "surplus_outputs", "market_sale_revenue", "market_input_bill",
        "grid_power_bill", "labour_bill", "maintenance_bill", "inbound_freight", "outbound_freight",
        "warehousing_bill", "working_inventory_warehouse_reserve", "operating_profit",
        "pre_tax_profit_after_freight_and_warehouse_reserve", "taxes", "dividends", "net_cash_after_tax_dividends",
        "cluster_target_profit", "cluster_target_min", "cluster_target_max", "in_cluster_target_after_friction_reserve",
        "held_surplus_market_value", "assumed_transport", "analysis_error",
    )
    for row in rows:
        for field in fields:
            row.setdefault(field, "")
    with open(OUT / "integer_one_layer_chains.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    return rows


def write_deployed_recipe_economics(goods, buildings, recipes, ranks):
    """Write the static, current-data recipe view used for balance decisions.

    This is the authoritative standalone report: it uses each recipe's deployed
    workforce and output quantity.  It shows freight separately because a
    building detail's production margin excludes the later market-sale leg.
    """
    rows = []
    for recipe in recipes:
        building = buildings[recipe["_building"]]
        gross_revenue = revenue(recipe, goods)
        input_bill = sum(
            quantity * f(goods[good].get("base_price")) * (1 + BUY_MARKUP)
            for good, quantity in pairs(recipe, "input", "qty", 6)
        )
        energy_bill = f(recipe.get("energy_req")) * GRID
        maintenance_bill = f(building.get("maintenance_cost")) * MAINT_MULT
        labour_bill = labour(recipe, building)
        inbound_freight = outbound_freight = warehouse_reserve = 0.0
        modes = set()
        for good, quantity in pairs(recipe, "input", "qty", 6):
            freight, mode = one_turn_market_freight(good, quantity, goods)
            inbound_freight += freight
            warehouse_reserve += quantity * STORE.get(goods[good].get("transport_class", ""), 0.01)
            modes.add(mode)
        for good, quantity in pairs(recipe, "output", "output_qty", 5):
            freight, mode = one_turn_market_freight(good, quantity, goods)
            outbound_freight += freight
            warehouse_reserve += quantity * STORE.get(goods[good].get("transport_class", ""), 0.01)
            modes.add(mode)
        production_margin = gross_revenue - input_bill - energy_bill - maintenance_bill - labour_bill
        cash_after_freight = production_margin - inbound_freight - outbound_freight
        cash_before_tax = cash_after_freight - warehouse_reserve
        taxes = max(0.0, cash_before_tax) * 0.20
        post_tax = cash_before_tax - taxes
        dividends = max(0.0, post_tax) * 0.20
        target_profit, target_min, target_max, target_policy, rank = target(recipe, ranks)
        primary, output_quantity = pairs(recipe, "output", "output_qty", 5)[0] if pairs(recipe, "output", "output_qty", 5) else ("", 0.0)
        mine = "deposit:" in recipe.get("requirements", "") or "mining" in recipe.get("category", "").lower()
        rows.append({
            "recipe_id": recipe["recipe_id"],
            "recipe": recipe.get("display_name", ""),
            "building_id": recipe["_building"],
            "tech_rank": rank,
            "primary_output": primary,
            "deployed_output_qty": output_quantity,
            "deployed_labour_unskilled": i(recipe.get("labour_unskilled_required")),
            "deployed_labour_skilled": i(recipe.get("labour_skilled_required")),
            "deployed_labour_h_skilled": i(recipe.get("labour_h_skilled_required")),
            "target_policy": target_policy,
            "target_profit": target_profit,
            "target_min": target_min,
            "target_max": target_max,
            "gross_market_revenue": gross_revenue,
            "market_input_bill": input_bill,
            "grid_power_bill": energy_bill,
            "maintenance_bill": maintenance_bill,
            "labour_bill": labour_bill,
            "production_margin_before_market_freight": production_margin,
            "one_turn_inbound_freight": inbound_freight,
            "one_turn_outbound_freight": outbound_freight,
            "one_turn_working_inventory_warehouse_reserve": warehouse_reserve,
            "cash_before_tax_after_one_turn_freight": cash_after_freight,
            "cash_before_tax_after_one_turn_freight_and_warehouse": cash_before_tax,
            "taxes": taxes,
            "dividends": dividends,
            "net_cash_after_tax_dividends": post_tax - dividends,
            "in_target_after_one_turn_friction_before_tax": "mine exception" if mine else target_min - 1e-6 <= cash_before_tax <= target_max + 1e-6,
            "freight_assumption": "+".join(sorted(modes)) or "none",
        })
    fields = tuple(rows[0].keys())
    with open(OUT / "deployed_recipe_economics.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: round(value, 3) if isinstance(value, float) else value for key, value in row.items()})
    return rows

def suggested_staffing(bid, budget):
    """Allocate the minimum crew first, then spend any remaining labour budget."""
    mix=MIX.get(bid, (.60,.30,.10)); blended=sum(a*w for a,w in zip(mix,WAGE))
    extra_budget=max(0.0, budget-MIN_LABOUR_COST)
    count=max(0,int(extra_budget/blended))
    counts=[minimum + round(count*x) for minimum,x in zip(MIN_STAFF,mix)]
    cost=sum(a*w for a,w in zip(counts,WAGE))
    while cost>budget and sum(counts):
        eligible=[j for j,x in enumerate(counts) if x>MIN_STAFF[j]]
        if not eligible: break
        k=max(eligible, key=lambda j:WAGE[j]); counts[k]-=1; cost=sum(a*w for a,w in zip(counts,WAGE))
    return tuple(counts),cost

def rank_map():
    return {r.get("title",""): {"I":1,"II":2,"III":3}.get(r.get("rank",""),1) for r in read(DATA / "research_unlocks.csv")}
def target(r, ranks):
    rank=0 if not r.get("required_research","") else ranks.get(r.get("required_research",""),1)
    primary = pairs(r,"output","output_qty",5)[0][0] if pairs(r,"output","output_qty",5) else ""
    if r["recipe_id"] in RECIPE_TARGET_OVERRIDES:
        targ, low, high, policy = RECIPE_TARGET_OVERRIDES[r["recipe_id"]]
        return targ, low, high, policy, rank
    if primary == "lithium_battery":
        return -10.0, -50.0, -1.0, "lithium batteries should be deliberately unprofitable", rank
    if primary == "solar_panel" and r.get("required_research",""):
        return 50.0, 40.0, 60.0, "research-unlocked solar panels should be modestly profitable", rank
    if primary in {"cpu", "computer"} and r.get("required_research",""):
        return 65.0, 30.0, 100.0, "unlocked CPU/computer recipes can carry larger base profit", rank
    if primary == "cpu":
        return -10.0, -50.0, -1.0, "base CPU production should be deliberately unprofitable", rank
    if primary == "ice_car":
        return 15.0, 0.0, 30.0, "ICE cars should be slightly profitable", rank
    return (*DEFAULT_TARGETS.get(rank, DEFAULT_TARGETS[1]), rank)

def run():
    goods, buildings, raw, recipes = load(); ranks=rank_map()
    recommended_labour = recommended_labour_costs(goods, buildings, recipes, ranks)
    grid=imputed(goods,buildings,recipes,GRID,recommended_labour)
    # Internal electricity is worth at least the grid revenue forgone by not
    # exporting it.  The former global-min technical cost selected a rank-III
    # wind recipe for every chain and incorrectly valued power at ~£0.0064.
    own=GRID_SELL
    full=imputed(goods,buildings,recipes,own,recommended_labour)
    one_layer_cost, one_layer_supplier = one_layer_input_costs(goods, buildings, recipes, recommended_labour)
    recipe_by_id = {r["recipe_id"]: r for r in recipes}
    rows=[]
    for r in recipes:
        b=buildings[r["_building"]]; rev=revenue(r,goods); maint=f(b.get("maintenance_cost"))*MAINT_MULT; market=sum(q*f(goods[g].get("base_price"))*(1+BUY_MARKUP) for g,q in pairs(r,"input","qty",6)); energy=f(r.get("energy_req"))*GRID; current_labour=labour(r,b); targ,target_min,target_max,target_policy,rank=target(r,ranks)
        budget=rev-market-energy-maint-targ; counts,newlab=suggested_staffing(r["_building"],budget)
        standalone=rev-market-energy-maint-newlab
        minimum_labour_standalone=rev-market-energy-maint-MIN_LABOUR_COST
        input_profit=rev-sum(q*grid[g] for g,q in pairs(r,"input","qty",6))-energy-maint-newlab
        full_profit=rev-sum(q*full[g] for g,q in pairs(r,"input","qty",6))-f(r.get("energy_req"))*own-maint-newlab
        one_layer_profit=rev-sum(q*one_layer_cost[g] for g,q in pairs(r,"input","qty",6))-energy-maint-newlab
        direct_suppliers=[]
        for g, _q in pairs(r, "input", "qty", 6):
            if g in one_layer_supplier:
                supplier=one_layer_supplier[g]
                direct_suppliers.append(f"{g}: {supplier['recipe_id']} {supplier.get('display_name','')}")
        transport,storage,modes=friction(r,goods)
        mine="deposit:" in r.get("requirements","") or "mining" in r.get("category","").lower()
        startup_revenue=extraction_startup_revenue(r, goods) if mine else ""
        startup=startup_revenue-market-energy-maint-current_labour if mine else ""
        flags=[]
        if not mine and not target_min<=standalone<=target_max: flags.append("standalone_band")
        if input_profit<20 or input_profit>100: flags.append("input_band")
        if full_profit<50 or full_profit>400: flags.append("full_band")
        if max(input_profit,full_profit)>400: flags.append("profit_cap")
        action="ok" if "standalone_band" not in flags else ("labour" if budget>=MIN_LABOUR_COST else "quantity_or_price")
        if "profit_cap" in flags: action="structural_cap_review"
        primary=pairs(r,"output","output_qty",5)[0][0] if pairs(r,"output","output_qty",5) else ""
        rows.append({"recipe_id":r["recipe_id"],"display_name":r.get("display_name",""),"building_id":r["_building"],"research":r.get("required_research",""),"tech_rank":rank,"primary_output":primary,"standalone_target":target_policy,"target_profit":round(targ,3),"target_min":target_min,"target_max":target_max,"standalone_revenue":round(rev,3),"standalone_inputs_bill":round(market,3),"standalone_power_units":f(r.get("energy_req")),"standalone_energy_bill":round(energy,3),"standalone_maintenance_bill":round(maint,3),"current_standalone_profit":round(rev-market-energy-maint-current_labour,3),"mine_startup_revenue_live_penalty":round(startup_revenue,3) if startup_revenue!="" else "","mine_startup_profit_live_penalty":round(startup,3) if startup!="" else "","minimum_labour_unskilled":MIN_STAFF[0],"minimum_labour_skilled":MIN_STAFF[1],"minimum_labour_h_skilled":MIN_STAFF[2],"minimum_labour_cost":round(MIN_LABOUR_COST,3),"diagnostic_target_fitted_labour_unskilled":counts[0],"diagnostic_target_fitted_labour_skilled":counts[1],"diagnostic_target_fitted_labour_h_skilled":counts[2],"diagnostic_target_fitted_labour_cost":round(newlab,3),"diagnostic_target_fitted_standalone_profit":round(standalone,3),"minimum_labour_standalone_profit":round(minimum_labour_standalone,3),"fractional_one_layer_cost_proxy_profit":round(one_layer_profit,3),"proxy_cheapest_direct_suppliers":"; ".join(direct_suppliers),"imputed_market_input_cost_proxy_profit":round(input_profit,3),"imputed_full_cost_proxy_profit":round(full_profit,3),"cap_reduction_needed":round(max(0,max(input_profit,full_profit)-400),3),"route_assumption":modes,"one_turn_transport_cost":round(transport,3),"one_turn_storage_cost":round(storage,3),"diagnostic_target_fitted_profit_after_one_turn_friction":round(standalone-transport-storage,3),"recommendation":action,"flags":";".join(flags)})
    OUT.mkdir(parents=True,exist_ok=True)
    power_rows = write_power_opportunity_report(goods, buildings, recipes)
    deployed_rows = write_deployed_recipe_economics(goods, buildings, recipes, ranks)
    with open(OUT/"recipe_rebalance_baseline.csv","w",newline="",encoding="utf-8") as h:
        w=csv.DictWriter(h,fieldnames=rows[0].keys());w.writeheader();w.writerows(rows)
    caps=sorted((r for r in rows if "profit_cap" in r["flags"]),key=lambda r:r["imputed_full_cost_proxy_profit"],reverse=True)
    consumers=defaultdict(list)
    for candidate in recipes:
        for good,qty in pairs(candidate,"input","qty",6):
            consumers[good].append(f"{candidate['recipe_id']} {candidate.get('display_name','')}")
    sensitivity=[]
    for row in caps:
        source=next(r for r in recipes if r["recipe_id"]==row["recipe_id"])
        output, qty=pairs(source,"output","output_qty",5)[0]
        current=f(goods[output].get("base_price"))
        required=max(0,current-f(row["cap_reduction_needed"])/qty)
        post_cut_min_labour=f(row["minimum_labour_standalone_profit"])-f(row["cap_reduction_needed"])
        sensitivity.append({"recipe_id":row["recipe_id"],"recipe":row["display_name"],"output_good":output,"current_base_price":round(current,3),"max_base_price_for_400_cap":round(required,3),"price_reduction_per_unit":round(current-required,3),"standalone_after_cap_price_with_minimum_labour":round(post_cut_min_labour,3),"price_only_keeps_start_margin":post_cut_min_labour>=0,"downstream_consumer_count":len(consumers[output]),"downstream_consumers":"; ".join(consumers[output]) or "none (terminal)"})
    with open(OUT/"profit_cap_price_sensitivity.csv","w",newline="",encoding="utf-8") as h:
        fields=sensitivity[0].keys() if sensitivity else CAP_SENSITIVITY_FIELDS
        w=csv.DictWriter(h,fieldnames=fields);w.writeheader();w.writerows(sensitivity)
    structural=[]
    for row in rows:
        if "standalone_band" not in row["flags"] or row["recommendation"] == "labour":
            continue
        recipe=recipe_by_id[row["recipe_id"]]; building=buildings[recipe["_building"]]
        minimum_profit=f(row["minimum_labour_standalone_profit"])
        needed_to_min=max(0.0, f(row["target_min"])-minimum_profit)
        needed_to_target=max(0.0, f(row["target_profit"])-minimum_profit)
        outputs=pairs(recipe,"output","output_qty",5)
        if not outputs:
            continue
        primary, output_qty=outputs[0] if outputs else ("",0.0)
        unit_price=.06 if primary=="power" else f(goods[primary].get("base_price"))
        inputs=pairs(recipe,"input","qty",6)
        if inputs:
            high_good, high_qty=max(inputs,key=lambda item:f(goods[item[0]].get("base_price"))*(1+BUY_MARKUP))
            high_unit=f(goods[high_good].get("base_price"))*(1+BUY_MARKUP)
        else:
            high_good, high_qty, high_unit="",0.0,0.0
        structural.append({"recipe_id":row["recipe_id"],"recipe":row["display_name"],"target_min":row["target_min"],"target_profit":row["target_profit"],"minimum_labour_profit":round(minimum_profit,3),"needed_to_minimum_band":round(needed_to_min,3),"needed_to_target":round(needed_to_target,3),"primary_output":primary,"output_qty":output_qty,"price_increase_per_output_to_minimum_band":round(needed_to_min/output_qty,3) if output_qty else "","extra_output_units_to_minimum_band":math.ceil(needed_to_min/unit_price) if unit_price else "","maintenance_reduction_to_minimum_band":round(min(f(building.get("maintenance_cost")),needed_to_min/MAINT_MULT),3),"highest_cost_input":high_good,"highest_cost_input_qty":high_qty,"highest_cost_input_unit_cost":round(high_unit,3),"input_units_to_remove_to_minimum_band":math.ceil(needed_to_min/high_unit) if high_unit else ""})
    with open(OUT/"minimum_labour_structural_candidates.csv","w",newline="",encoding="utf-8") as h:
        w=csv.DictWriter(h,fieldnames=structural[0].keys());w.writeheader();w.writerows(structural)
    integer_rows = write_integer_chain_report(goods, buildings, recipe_by_id)
    # Keep the historic filename, but replace its fractional-allocation number
    # with the whole-building cash result.  The detailed companion file keeps
    # both surplus choices and the complete cost breakdown.
    by_chain_scenario = {(row.get("chain", ""), row.get("scenario", "")): row for row in integer_rows}
    forced_rows=[]
    for label, (recipe_id, _sources) in INTEGER_CHAIN_SCENARIOS.items():
        sold = by_chain_scenario.get((label, "settled auto-sell"), {})
        held = by_chain_scenario.get((label, "hold surplus for one turn"), {})
        forced_rows.append({
            "chain": label,
            "recipe_id": recipe_id,
            "deployed_components": sold.get("deployed_components", ""),
            "surplus_outputs": sold.get("surplus_outputs", ""),
            "operating_profit_with_surplus_sold": sold.get("operating_profit", ""),
            "net_cash_with_surplus_sold": sold.get("net_cash_after_tax_dividends", ""),
            "net_cash_holding_surplus_one_turn": held.get("net_cash_after_tax_dividends", ""),
        })
    with open(OUT/"forced_one_layer_chains.csv","w",newline="",encoding="utf-8") as h:
        w=csv.DictWriter(h,fieldnames=forced_rows[0].keys());w.writeheader();w.writerows(forced_rows)
    with open(OUT/"recipe_rebalance_summary.md","w",encoding="utf-8") as h:
        h.write("# Recipe rebalance baseline\n\n")
        h.write(f"- Active recipes: {len(recipes)} of {len(raw)} CSV rows\n- Internal-power short-run opportunity cost: {own:.4f} (foregone grid sale)\n- Grid purchase price: {GRID:.4f}\n- Power investment horizon: {POWER_INVESTMENT_HORIZON_TURNS} turns\n- One-turn route assumption: rail for solids, pipe for liquids/gases, roads otherwise\n- Maintenance is charged once, matching the live production loop\n- Standalone target metric: pre-tax cash after one-turn market freight and a one-turn working-inventory warehouse reserve\n- Static deployed recipe economics in target band: {sum(row['in_target_after_one_turn_friction_before_tax'] is True for row in deployed_rows)}\n- Structural +400 reviews: {len(caps)}\n\n")
        h.write("## Power opportunity-cost scenarios\n\n")
        h.write("Short-run cost includes operating cash and the export forgone by internal use. Long-run cost also levelizes generator, battery-housing and locked-cell investment over the stated horizon.\n\n")
        h.write("| Scenario | Operating £/power | Levelized £/power | Short-run opportunity | Long-run opportunity |\n|---|---:|---:|---:|---:|\n")
        for row in power_rows:
            h.write(f"| {row['scenario']} | {float(row['operating_cost_per_power']):.4f} | {float(row['levelized_cost_per_power']):.4f} | {float(row['short_run_opportunity_cost_per_power']):.4f} | {float(row['long_run_opportunity_cost_per_power']):.4f} |\n")
        h.write("\n")
        h.write("| Recipe | Input integrated | Fully integrated | Reduce to cap by |\n|---|---:|---:|---:|\n")
        for r in caps: h.write(f"| {r['display_name']} | {r['imputed_market_input_cost_proxy_profit']:.1f} | {r['imputed_full_cost_proxy_profit']:.1f} | {r['cap_reduction_needed']:.1f} |\n")
        h.write("\n`deployed_recipe_economics.csv` is the authoritative standalone view: deployed labour and output, one-turn market freight, working-inventory warehouse reserve, tax and dividends. Fields labelled `diagnostic` or `proxy` in `recipe_rebalance_baseline.csv` are not cashflow predictions.\n")
        h.write("See `integer_one_layer_chains.csv` for selected whole-building chains, including actual deployed labour, supplier surplus, freight, warehousing, tax and dividends.\n")
    print(f"Active recipes: {len(recipes)} / {len(raw)}; minimum labour cost {MIN_LABOUR_COST:.3f}; structural reviews {len(structural)}; cap reviews {len(caps)}")

if __name__ == "__main__": run()
