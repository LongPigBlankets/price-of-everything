#!/usr/bin/env python3
# Recipe balance calculator — loads goods/buildings/recipes from the live CSVs.
# Columns: naked (buy all, sell all, pay transport+power), coloc (transport->0),
# +pwr (also self-power x0.3), +inp (also self-supply inputs @0.85) = FULLY INTEGRATED.
# Run from project root: python tools/balance.py
# Power consumption per run = recipe energy_req only (building energy_cost is ignored).
#
# Reads recipes_all.csv and applies the same promotion gate as the game (Catalog):
# a recipe is shown only if its building resolves AND every input + output is a
# priced good. transport_class names (solid_heavy, hazard_liquid, ...) are mapped
# to the model's rate buckets below.
import csv
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"
GOODS_CSV     = DATA / "Goods - goodsMVP.csv"
BUILDINGS_CSV = DATA / "Buildings - buildingsMVP.csv"
RECIPES_CSV   = DATA / "recipes_all.csv"

# recipes_all.csv references some buildings by alias; resolve them to the real
# building internal_name exactly like the game (scripts/catalog.gd BUILDING_ALIAS)
# so the promotion gate here matches the Catalog's.
BUILDING_ALIAS = {
    "factory": "industrial_factory",
    "industrial_goods_factory": "industrial_factory",
    "consumer_goods_factory": "consumer_factory",
    "water_well": "water_pump",
    "desal_plant": "desal",
    "water_treatment_plant": "water_recycling",
    "hydro_dam": "hydro_power_plant",
    "forest": "new_forest",
}

# --- cost-model parameters (not in CSVs; edit here to retune) ---
SELL      = 0.95
WAGE      = {"u": 0.002, "s": 0.006, "h": 0.010}   # engine rates (economy_config.gd)
TRANSPORT = {"heavy": 0.20, "liquid": 0.10, "gas": 0.20, "power": 0.0}
SELFPOWER = 0.30

# Map the goods CSV's transport_class values onto the rate buckets above.
CLASS_MAP = {
    "solid_heavy": "heavy", "solid_light": "heavy",
    "safe_liquid": "liquid", "hazard_liquid": "gas",
    "electricity": "power",
}
# Fallback per good name, used only when transport_class is empty/unknown.
CLASS_DEFAULT = {
    "coal": "heavy", "iron_ore": "heavy", "copper_ore": "heavy", "basic_salt": "heavy",
    "iron_ingots": "heavy", "copper_ingots": "heavy", "steel": "heavy",
    "copper_wiring": "heavy", "motor": "heavy",
    "pure_water": "liquid",
    "chlorine": "gas", "sodium_hydroxide": "gas", "hydrogen": "gas", "oxygen": "gas",
    "power": "power",
}

def class_key(raw, name):
    if raw in CLASS_MAP:   return CLASS_MAP[raw]
    if raw in TRANSPORT:   return raw            # already a bucket name
    return CLASS_DEFAULT.get(name, "heavy")

# --- load goods (internal_name -> base_price, transport bucket) ---
PRICE, CLASS = {}, {}
with open(GOODS_CSV) as f:
    for row in csv.DictReader(f):
        name = row["internal_name"]
        if not name: continue
        PRICE[name] = float(row["base_price"]) if row["base_price"] else 0.0
        CLASS[name] = class_key((row.get("transport_class") or "").strip(), name)

# --- load buildings (internal_name -> per-run overhead: maintenance + labour wage bill) ---
BLD = {}
with open(BUILDINGS_CSV) as f:
    for row in csv.DictReader(f):
        key = row.get("internal_name") or row.get("ID")
        if not key: continue
        m = float(row["maintenance_cost"] or 0)
        u = int(row["labour_unskilled_required"] or 0)
        s = int(row["labour_skilled_required"] or 0)
        h = int(row["labour_h_skilled_required"] or 0)
        BLD[key] = 2.0*m + u*WAGE["u"] + s*WAGE["s"] + h*WAGE["h"]   # maint x2 (catalog MAINTENANCE_MULTIPLIER)

# --- load recipes (input_1..6, output_1..5) ---
def parse_recipe(row):
    ins, outs = {}, {}
    for i in range(1, 7):
        g, q = row.get(f"input_{i}", ""), row.get(f"qty_{i}", "")
        if g and q: ins[g] = float(q)
    for i in range(1, 6):
        g, q = row.get(f"output_{i}", ""), row.get(f"output_qty_{i}", "")
        if g and q: outs[g] = float(q)
    return ins, float(row.get("energy_req", "0") or 0), outs

R, skipped = [], 0
with open(RECIPES_CSV) as f:
    for row in csv.DictReader(f):
        if not row.get("recipe_id"): continue
        ins, energy, outs = parse_recipe(row)
        if not outs: continue                                   # infra / no production
        bid_raw = row.get("building_id", "")
        bid = BUILDING_ALIAS.get(bid_raw, bid_raw)              # resolve alias like the game
        if bid not in BLD:                                      # building must resolve
            skipped += 1; continue
        if any(g not in PRICE for g in list(ins) + list(outs)): # promotion gate: priced goods only
            skipped += 1; continue
        R.append((row["recipe_id"], row["display_name"], bid, ins, energy, outs))

# --- compute margins ---
ic = lambda d: sum(q*PRICE[g] for g,q in d.items())
tp = lambda d: sum(q*TRANSPORT[CLASS[g]] for g,q in d.items())
fmt_q = lambda q: int(q) if q == int(q) else q

print(f"Active recipes: {len(R)}  (dormant/unpriced skipped: {skipped})")
print(f"{'recipe':24}{'rev':>6}{'naked':>7}{'coloc':>7}{'+pwr':>6}{'+inp':>7}  outputs")
print("-"*86)
for rid, name, bid, ins, E, outs in R:
    I = ic(ins); P = E*PRICE.get("power", 1.0); F = BLD[bid]; T = tp(ins) + tp(outs)
    rev = sum(q*PRICE[g]*SELL for g,q in outs.items())
    naked = rev - I - P - F - T
    coloc = rev - I - P - F
    pwr   = rev - I - P*SELFPOWER - F
    inp   = rev - ic({g:q*0.85 for g,q in ins.items()}) - P*SELFPOWER - F
    pc = lambda x: f"{100*x/rev:.0f}%" if rev else "n/a"
    od = ",".join(f"{g}:{fmt_q(q)}" for g,q in outs.items())
    print(f"{name[:23]:24}{rev:6.0f}{pc(naked):>7}{pc(coloc):>7}{pc(pwr):>6}{pc(inp):>7}  {od}")
