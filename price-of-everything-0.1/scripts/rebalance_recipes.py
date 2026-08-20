#!/usr/bin/env python3
"""Rebalance non-MVP recipes (r_013+) per docs/recipe-rebalance-spec.md.

Encodes the framework so it is reproducible and re-tunable:
  * energy_req from a real-world energy ladder (aluminium smelting = 20 cap),
  * output batch sizes by tier so % modifiers survive int(round) (20-30 / 10-20 / >=5),
  * input quantities matched to the producing recipe's output batch (x0.5/0.8/1/1.5/2),
    rounded to the nearest 5/10 (never 9/11/19/21),
  * integrated cost C computed bottom-up (self-power £0.15, fixed cost per building),
  * output price set inside the designer's per-tier price band.

MVP recipes r_001-r_012 are kept verbatim (and only used to seed the cost graph).
Reads  data/recipes_all.csv  (structure: which recipes/goods/buildings exist).
Writes data/recipes_rebalanced.csv      (full rebalanced recipe table)
       data/good_prices_rebalanced.csv  (good -> tier, C, new price)
       docs/recipe-rebalance-table.md    (human review report)

Run: python scripts/rebalance_recipes.py
"""
import csv, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "data", "recipes_all.csv")

# ---- economic constants (mirror economy_config.gd) ----
SELF_POWER = 0.15
GRID_POWER = 1.00
MARKUP = 1.05

# Fixed cost per turn per building (maintenance x2 + turn-1 labour stub).
FIXED = {
    "mine": 2.8, "furnace": 4.8, "coal_power": 6.78, "power_plant": 6.78,
    "industrial_factory": 5.6, "factory": 5.6, "industrial_goods_factory": 5.6,
    "consumer_factory": 4.8, "consumer_goods_factory": 4.8,
    "eaf": 4.8, "electrolyser": 4.8, "chem_plant": 5.6, "poly_plant": 4.8,
    "petro_refinery": 4.8, "bio_chem_plant": 4.8, "brine_processing_plant": 4.8,
    "assembly_plant": 4.8, "high_tech_manufactory": 4.8, "recycling_plant": 4.8,
    "timber_paper_factory": 4.8, "farm": 4.8, "forest": 4.8, "new_forest": 4.8,
    "old_forest": 4.8, "desal": 4.8, "desal_plant": 4.8, "water_recycling": 4.8,
    "water_treatment_plant": 4.8, "water_pump": 4.8, "water_well": 4.8,
    "oil_well": 4.8, "offshore_oil_platform": 4.8, "fracking_oil_well": 4.8,
    "solar_farm": 4.8, "onshore_wind_farm": 4.8, "offshore_wind_farm": 4.8,
    "hydro_power_plant": 4.8, "battery": 4.8,
}
DEFAULT_FIXED = 4.8

# ---- energy ladder ----
ENERGY_BY_BUILDING = {
    "mine": 3, "oil_well": 2, "offshore_oil_platform": 3, "fracking_oil_well": 3,
    "water_pump": 3, "water_well": 3, "farm": 2, "forest": 1, "new_forest": 1,
    "old_forest": 1, "desal": 6, "desal_plant": 6, "water_recycling": 2,
    "water_treatment_plant": 2, "furnace": 9, "eaf": 12, "electrolyser": 14,
    "chem_plant": 9, "poly_plant": 5, "petro_refinery": 5, "bio_chem_plant": 4,
    "brine_processing_plant": 3, "industrial_factory": 4, "factory": 4,
    "industrial_goods_factory": 4, "consumer_factory": 3, "consumer_goods_factory": 3,
    "assembly_plant": 4, "high_tech_manufactory": 5, "recycling_plant": 3,
    "timber_paper_factory": 5,
    "coal_power": 0, "power_plant": 0, "solar_farm": 0, "onshore_wind_farm": 0,
    "offshore_wind_farm": 0, "hydro_power_plant": 0, "battery": 0,
}
# keyword -> energy override (scanned against display_name, lowercased)
ENERGY_KEYWORD = [
    ("hall heroult", 20), ("hall-heroult", 20), ("carbothermic", 20), ("elysis", 20),
    ("aluminium (hall", 20), ("aluminium direct", 20),
    ("polysilicon", 16), ("siemens", 16), ("silicon smelting", 16),
    ("fluidised bed reactor", 16),
    ("water electrolysis", 14), ("membraneless", 14), ("methane pyrolysis", 14),
    ("rare earth reduction", 14), ("rare earth recycl", 4),
    ("electric arc steel", 12), ("hisarna", 11), ("direct reduced iron", 10),
    ("high strength glass", 12), ("silica glass", 14), ("industrial glassmaking", 10),
    ("traditional glassblowing", 8), ("electric concrete", 10), ("concrete firing", 6),
    ("bayer", 10), ("haber bosch", 8), ("needle coke calcination", 14),
    ("desalination", 6), ("electric calcination", 12),
    ("oxygen air separation", 12), ("nitrogen air separation", 10),
    ("lithium electrolysis", 12), ("alloy metal electrolysis", 14),
]

# ---- tier per good (0 raw .. 5 top hi-tech) ----
ALIAS = {
    "alloy_metal_ingots": "alloy_ingots", "copper_piping": "copper_pipe",
    "lithium_ion_battery": "lithium_battery", "water": "pure_water",
    "paper_products": "paper_goods", "mined_salt": "basic_salt",
    "table_salt": "basic_salt", "engine_ice": "engine", "engine_ev": "engine",
}
TIER = {
    # 0 raw
    "coal": 0, "iron_ore": 0, "copper_ore": 0, "bauxite_ore": 0, "lithium_ore": 0,
    "ree_ore": 0, "alloy_ore": 0, "crude_oil": 0, "basic_salt": 0, "sand": 0,
    "limestone": 0, "sulphur": 0, "pure_water": 0, "biomass": 0, "wood": 0,
    "nitrogen": 0, "oil_crops": 0, "fabric_crops": 0, "municipal_waste": 0,
    "waste_water": 0, "scrap": 0, "battery_waste": 0, "chem_salts": 0, "food": 0,
    # 1 primary
    "iron_ingots": 1, "copper_ingots": 1, "alloy_ingots": 1, "alumina": 1,
    "chlorine": 1, "sodium_hydroxide": 1, "hydrogen": 1, "oxygen": 1, "silica": 1,
    "processed_oil": 1, "heavy_oil": 1, "light_oil": 1, "petro_gases": 1,
    "methane": 1, "propane": 1, "refined_lithium": 1, "refined_ree": 1,
    "compressed_biomass": 1, "ammonia": 1, "methanol": 1, "ethanol": 1,
    "wood_pulp": 1, "petro_coke": 1, "spec_microbes": 1, "industrial_acids": 1,
    "noble_gases": 1, "power": 1, "hydrocarbon_power": 1,
    # 2 refined
    "steel": 2, "aluminium": 2, "copper_wiring": 2, "copper_pipe": 2, "glass": 2,
    "plastics": 2, "rubber": 2, "ethylene": 2, "pvc": 2, "concrete": 2,
    "fibreglass": 2, "graphite": 2, "hq_steel": 2, "fuels": 2, "SAF": 2,
    "paper_pulp": 2, "fertilisers": 2, "api": 2, "silicon": 2,
    # 3 components
    "motor": 3, "electrical_components": 3, "circuit_board": 3, "windows": 3,
    "car_body": 3, "engine": 3, "tires": 3, "carbon_fibre": 3, "paper_goods": 3,
    "food_products": 3, "toys": 3, "alkaline_battery": 3, "iron_battery": 3,
    "sodium_battery": 3, "polysilicon": 3,
    "large_engine": 4,  # big engine: too input-heavy for the tier-3 £10 cap
    # 4 assemblies
    "solar_panels": 4, "wind_turbine": 4, "lithium_battery": 4, "flow_battery": 4,
    "battery": 4, "CPU": 4, "construction_equipment_ice": 4,
    "ice_car": 4, "building_frame": 4,
    # 5 top hi-tech (consume a tier-4 battery/CPU, so must price above it)
    "computer": 5, "ev_car": 5, "solid_battery": 5, "medical_components": 5,
    "construction_equipment_ev": 5,
}
# goods held at their MVP/established sale price (not repriced)
HOLD_PRICE = {
    "coal": 1.0, "iron_ore": 1.0, "copper_ore": 1.0, "iron_ingots": 1.6,
    "copper_ingots": 1.6, "steel": 2.25, "copper_wiring": 3.2, "motor": 6.5,
    "pure_water": 0.5, "power": 1.0, "basic_salt": 0.5, "chlorine": 0.72,
    "sodium_hydroxide": 0.8, "hydrogen": 1.5,
    # Scarce strategic materials held at the top of their band — being expensive is
    # the whole point of "substitute away from REE/lithium" and makes recycling them
    # worthwhile. (Otherwise the formula floors them at ~£1.)
    "refined_ree": 4.0, "refined_lithium": 4.0,
}
# Waste/feedstock goods: market BUY/SELL price (PIN) is the designer-set value
# (waste water 0.1, bio/municipal 0.5, scrap & e-waste 2.0) — Goods CSV must also
# flip is_buyable=TRUE on these. But their INTEGRATED cost (WASTE_C) is near-zero
# because when you self-supply you get them as a free byproduct. The split is what
# makes recycling pay only when you feed it your OWN waste, not bought waste.
PIN = {
    "waste_water": 0.1, "municipal_waste": 0.5, "city_waste": 0.5,
    "scrap": 2.0, "battery_waste": 2.0, "ev_waste": 2.0,
}
WASTE_C = {
    "waste_water": 0.05, "municipal_waste": 0.1, "city_waste": 0.1,
    "scrap": 0.3, "battery_waste": 0.3, "ev_waste": 0.3,
}

# ---- per-tier knobs ----
BATCH = {0: 20, 1: 20, 2: 20, 3: 10, 4: 5, 5: 5}
PRICE_BAND = {0: (1.0, 4.0), 1: (1.0, 4.0), 2: (1.0, 4.0),
              3: (3.0, 10.0), 4: (5.0, 20.0), 5: (7.0, 55.0)}
MARGIN_MID = {0: 0.08, 1: 0.13, 2: 0.19, 3: 0.27, 4: 0.33, 5: 0.38}
RATIOS = [0.5, 0.8, 1.0, 1.5, 2.0]

MVP_IDS = {"r_%03d" % i for i in range(1, 13)}
SKIP_OUTPUTS = {"money"}

# Premium recipes earn their edge as EXTRA OUTPUT (same inputs, more product),
# +10% (a little better) up to +50% (best-in-class). Three rationales:
#   (S) substitute away from a scarce/expensive good (REE, aluminium, lithium)
#   (R) regulation/carbon-tax-proof "better good" (electric/EV/green process)
#   (E) genuine process-efficiency improvement
# The good's PRICE is still anchored by its basic recipe, so the bonus lands as
# margin on the premium recipe. Inputs are sized to the BASE yield, not the bonus.
YIELD_BONUS = {
    # --- substitution: away from REE / aluminium / lithium (S) ---
    "r_065": 0.30,  # SynRM magnetless motors — no REE
    "r_102": 0.30,  # sodium-ion battery — no lithium
    "r_136": 0.30,  # iron-air battery — no lithium/REE
    "r_100": 0.20,  # redox flow battery — no lithium
    "r_055": 0.20,  # uPVC windows — pvc instead of aluminium
    "r_128": 0.20,  # inert-atmosphere components — noble gas route, less REE
    # --- regulation / carbon-tax-proof better goods (R) ---
    "r_076": 0.20,  # electric-arc (green) steel
    "r_077": 0.20,  # HIsarna low-carbon steel
    "r_030": 0.20,  # electric (low-CO2) concrete
    "r_083": 0.20,  # ELYSIS inert-anode aluminium
    "r_141": 0.20,  # HEFA biofuels (SAF)
    "r_152": 0.20,  # alcohol-to-jet SAF
    "r_034": 0.30,  # EV construction equipment vs ICE
    "r_119": 0.30,  # EV car assembly vs ICE
    "r_074": 0.20,  # hybrid (electrified) engine
    "r_089": 0.20,  # hydrogen direct-injection engine
    "r_062": 0.20,  # carbon-fibre wind turbine
    "r_070": 0.20,  # superlight (carbon-fibre) car body — efficiency/regs
    "r_099": 0.20,  # LFP battery (cobalt-free)
    # --- process efficiency, "a little better" (E) ---
    "r_080": 0.10,  # membraneless electrolysis
    "r_143": 0.10,  # catalytic cracking
    "r_053": 0.20,  # industrial glassmaking vs glassblowing
    "r_121": 0.10,  # circuit printing vs soldering
    "r_130": 0.10,  # carbon-fibre 3D printing vs weaving
    "r_124": 0.30,  # semiconductor 3D printing
    "r_123": 0.20,  # fabless semiconductors
    "r_066": 0.10,  # axial-flux motors (performance, but REE)
    "r_069": 0.10,  # lightweight car body
    "r_127": 0.10,  # precision electrical components
    "r_060": 0.20,  # perovskite solar
    "r_063": 0.30,  # heterojunction solar
    "r_064": 0.50,  # triple-tandem solar — best-in-class
    "r_137": 0.40,  # solid-state battery — next-gen flagship
    "r_164": 0.30,  # plastic toy mass production
    "r_118": 0.10,  # automated ICE car assembly
}


def canon(g):
    return ALIAS.get(g, g)


def tier_of(g):
    return TIER.get(canon(g), 1)  # default primary if unknown


def round5(x):
    r = int(round(x / 5.0)) * 5
    return max(5, r)


def round_premium(x):
    # Premium yields need 10% granularity, so round to the nearest whole unit
    # rather than to 5 — but still dodge the banned ugly numbers (…9, …1).
    n = max(5, int(round(x)))
    if n % 10 == 9:
        n += 1               # 19->20, 29->30
    elif n % 10 == 1 and n > 1:
        n += 1               # 11->12, 21->22
    return n


def energy_for(building, name):
    low = name.lower()
    for kw, e in ENERGY_KEYWORD:
        if kw in low:
            return e
    return ENERGY_BY_BUILDING.get(building, 4)


def parse():
    rows = []
    with open(SRC, newline="", encoding="utf-8-sig") as f:
        for raw in csv.DictReader(f):
            if not (raw.get("recipe_id") or "").strip():
                continue
            ins = []
            for i in range(1, 7):
                g = (raw.get("input_%d" % i) or "").strip()
                q = (raw.get("qty_%d" % i) or "").strip()
                if g and q:
                    ins.append([canon(g), int(float(q))])
            outs = []
            for i in range(1, 6):
                g = (raw.get("output_%d" % i) or "").strip()
                q = (raw.get("output_qty_%d" % i) or "").strip()
                if g and q and g not in SKIP_OUTPUTS:
                    outs.append([canon(g), int(float(q))])
            if not outs:
                continue
            rows.append({
                "id": raw["recipe_id"].strip(),
                "name": (raw.get("display_name") or "").strip(),
                "building": (raw.get("building_id") or "").strip(),
                "ins": ins, "outs": outs, "raw": raw,
            })
    return rows


def rebalance():
    rows = parse()

    # base yield per good = the MVP recipe's output if one makes it (so non-MVP
    # recipes match the MVP batch, e.g. steel 30, motor 15), else the tier batch.
    base_yield = {}
    for r in rows:
        if r["id"] in MVP_IDS:
            base_yield[r["outs"][0][0]] = r["outs"][0][1]

    def yield_of(g):
        return base_yield.get(g, BATCH[tier_of(g)])

    # 1. assign energy + output batches. Premium recipes add a yield bonus to the
    # PRIMARY output only (more product, same inputs); byproducts scale to base.
    for r in rows:
        r["energy"] = 0 if r["outs"][0][0] in ("power", "hydrocarbon_power") \
            else energy_for(r["building"], r["name"])
        if r["id"] in MVP_IDS:
            continue
        g0 = r["outs"][0][0]
        base_out = yield_of(g0)
        r["base_out"] = base_out
        bonus = YIELD_BONUS.get(r["id"], 0.0)
        prim = round_premium(base_out * (1.0 + bonus)) if bonus else base_out
        scale = base_out / r["outs"][0][1]
        new_outs = [[g0, prim]]
        for g, q in r["outs"][1:]:           # byproducts scale to base (no bonus)
            new_outs.append([g, round5(q * scale)])
        r["outs_new"] = new_outs

    # 2. match input quantities to the producing recipe's BASE output (so the
    # premium bonus is a pure ratio win, not cancelled by scaled-up inputs).
    for r in rows:
        if r["id"] in MVP_IDS:
            r["ins_new"] = r["ins"]
            continue
        base_out = r["base_out"]
        ins_new = []
        for g, q in r["ins"]:
            stoich = q / float(r["outs"][0][1])       # input per original output unit
            target = stoich * base_out                # input needed for base batch
            pb = yield_of(g)                          # producer's base output batch
            best = min(RATIOS, key=lambda m: abs(m * pb - target))
            ins_new.append([g, round5(best * pb)])
        r["ins_new"] = ins_new

    # index: which recipes produce each good
    producers = {}
    for r in rows:
        outs = r.get("outs_new", r["outs"])
        for g, q in outs:
            producers.setdefault(g, []).append(r)
    goods = set(producers) | {g for r in rows for g, _ in r["ins"]}

    # canonical (primary) recipe per good = lowest-id recipe with this good as its
    # FIRST output; fall back to lowest-id producer for byproduct-only goods. The
    # canonical recipe sets the good's cost/price; alternate & recycling recipes
    # then earn their own (better or worse) margin around that price.
    canonical = {}
    for r in sorted(rows, key=lambda x: x["id"]):
        g0 = r.get("outs_new", r["outs"])[0][0]
        canonical.setdefault(g0, r)
    for g in goods:
        if g not in canonical and g in producers:
            canonical[g] = sorted(producers[g], key=lambda x: x["id"])[0]

    # 3/4. fixpoint over integrated cost C and price (joint cost split by value)
    price = {g: PIN.get(g, HOLD_PRICE.get(g) or sum(PRICE_BAND[tier_of(g)]) / 2)
             for g in goods}
    C = {g: WASTE_C.get(g, PIN.get(g, 1.0)) for g in goods}  # waste C ≈ free byproduct
    for _ in range(80):
        newC = dict(C)
        for g in goods:
            if g in PIN:
                continue
            r = canonical.get(g)
            if r is None:
                continue
            outs = r.get("outs_new", r["outs"])
            ins = r.get("ins_new", r["ins"])
            fixed = FIXED.get(r["building"], DEFAULT_FIXED)
            batch_cost = r["energy"] * SELF_POWER + fixed
            for ig, iq in ins:
                batch_cost += C.get(ig, 1.0) * iq
            tot_val = sum(price.get(og, 1.0) * oq for og, oq in outs) or 1.0
            gq = next(oq for og, oq in outs if og == g)
            newC[g] = batch_cost * (price.get(g, 1.0) * gq / tot_val) / gq
        C = newC
        for g in goods:
            if g in PIN or g in HOLD_PRICE:
                continue
            t = tier_of(g)
            lo, hi = PRICE_BAND[t]
            price[g] = min(hi, max(lo, round(C[g] / (1.0 - MARGIN_MID[t]), 2)))
    return rows, C, price


def margins(r, C, price):
    outs = r.get("outs_new", r["outs"])
    ins = r.get("ins_new", r["ins"])
    fixed = FIXED.get(r["building"], DEFAULT_FIXED)
    R = sum(price.get(g, 1.0) * q for g, q in outs if g not in ("power", "hydrocarbon_power"))
    if R <= 0:
        return None, None, R
    icost = r["energy"] * SELF_POWER + fixed + sum(C.get(g, 1.0) * q for g, q in ins)
    ucost = r["energy"] * GRID_POWER + fixed + sum(price.get(g, 1.0) * MARKUP * q for g, q in ins)
    return (R - ucost) / R, (R - icost) / R, R


def write_outputs(rows, C, price):
    # good price table
    with open(os.path.join(ROOT, "data", "good_prices_rebalanced.csv"), "w",
              newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["good", "tier", "integrated_cost_C", "new_price", "held"])
        for g in sorted(price):
            w.writerow([g, tier_of(g), round(C.get(g, 0), 3),
                        round(price[g], 2), "yes" if g in HOLD_PRICE else ""])

    # rebalanced recipe table (same column layout as recipes_all.csv)
    HEADER = ["recipe_id", "display_name", "building_id",
              "input_1", "qty_1", "input_2", "qty_2", "input_3", "qty_3",
              "input_4", "qty_4", "input_5", "qty_5", "input_6", "qty_6", "energy_req",
              "output_1", "output_qty_1", "output_2", "output_qty_2", "output_3",
              "output_qty_3", "output_4", "output_qty_4", "output_5", "output_qty_5",
              "requirements", "pollution_output", "pollution_sensitivity",
              "category", "terminal_turns"]
    with open(os.path.join(ROOT, "data", "recipes_rebalanced.csv"), "w",
              newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=HEADER)
        w.writeheader()
        for r in rows:
            base = {h: (r["raw"].get(h) or "") for h in HEADER}
            ins = r.get("ins_new", r["ins"])
            outs = r.get("outs_new", r["outs"])
            for i in range(1, 7):
                base["input_%d" % i] = ins[i - 1][0] if i <= len(ins) else ""
                base["qty_%d" % i] = ins[i - 1][1] if i <= len(ins) else ""
            base["energy_req"] = r["energy"]
            for i in range(1, 6):
                base["output_%d" % i] = outs[i - 1][0] if i <= len(outs) else ""
                base["output_qty_%d" % i] = outs[i - 1][1] if i <= len(outs) else ""
            w.writerow(base)

    # human review report, grouped by tier of primary output
    lines = ["# Recipe rebalance — review table",
             "",
             "Auto-generated by `scripts/rebalance_recipes.py`. MVP recipes "
             "(r_001-r_012) shown for context but unchanged.",
             "",
             "`U%` = margin buying every input at market + grid power (want thin/negative). ",
             "`I%` = margin self-supplying inputs + self-power (want positive, rising with tier, <=40%).",
             ""]
    by_tier = {}
    for r in rows:
        by_tier.setdefault(tier_of(r["outs"][0][0]), []).append(r)
    names = {0: "Raw", 1: "Primary", 2: "Refined", 3: "Components",
             4: "Assemblies", 5: "Top hi-tech"}
    for t in range(6):
        rs = by_tier.get(t, [])
        if not rs:
            continue
        lines += ["## Tier %d — %s   (price band £%.0f–%.0f)" %
                  (t, names[t], *PRICE_BAND[t]), "",
                  "| id | recipe | bldg | inputs | en | outputs | +yield | price | U% | I% |",
                  "|---|---|---|---|--:|---|--:|--:|--:|--:|"]
        for r in sorted(rs, key=lambda x: x["id"]):
            u, i, _ = margins(r, C, price)
            ins = r.get("ins_new", r["ins"])
            outs = r.get("outs_new", r["outs"])
            istr = ", ".join("%d %s" % (q, g) for g, q in ins) or "—"
            ostr = ", ".join("%d %s" % (q, g) for g, q in outs)
            p0 = price.get(outs[0][0], 0)
            tag = " *(MVP)*" if r["id"] in MVP_IDS else ""
            yb = YIELD_BONUS.get(r["id"], 0.0)
            ystr = "+%.0f%%" % (yb * 100) if yb else ""
            lines.append("| %s | %s%s | %s | %s | %d | %s | %s | %.2f | %s | %s |" % (
                r["id"], r["name"], tag, r["building"], istr, r["energy"], ostr, ystr, p0,
                "%.0f%%" % (u * 100) if u is not None else "—",
                "%.0f%%" % (i * 100) if i is not None else "—"))
        lines.append("")
    with open(os.path.join(ROOT, "docs", "recipe-rebalance-table.md"), "w",
              encoding="utf-8") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    rows, C, price = rebalance()
    write_outputs(rows, C, price)
    miss = sorted({canon(g) for r in rows for g, _ in r["ins"] + r["outs"]
                   if canon(g) not in TIER and canon(g) not in ("power",)})
    print("recipes:", len(rows), " goods priced:", len(price))
    if miss:
        print("goods with no explicit tier (defaulted to 1):", ", ".join(miss))
