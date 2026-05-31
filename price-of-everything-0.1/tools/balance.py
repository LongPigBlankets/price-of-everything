#!/usr/bin/env python3
# MVP recipe balance calculator — loads goods/buildings/recipes from the MVP CSVs.
# Columns: naked (buy all, sell all, pay transport+power), coloc (transport->0),
# +pwr (also self-power x0.3), +inp (also self-supply inputs @0.85) = FULLY INTEGRATED, no multipliers.
# Run from project root: python3 tools/balance.py
# Power consumption per run = recipe energy_req only (building energy_cost is ignored — energy is a recipe-level lever).
import csv
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"
GOODS_CSV     = DATA / "Goods - goodsMVP.csv"
BUILDINGS_CSV = DATA / "Buildings - buildingsMVP.csv"
RECIPES_CSV   = DATA / "recipesMVP.csv"

# --- cost-model parameters (not in CSVs; edit here to retune) ---
SELL      = 0.95
WAGE      = {"u": 0.02, "s": 0.05, "h": 0.10}
TRANSPORT = {"heavy": 0.20, "liquid": 0.10, "gas": 0.20, "power": 0.0}
SELFPOWER = 0.30

# Fallback transport class per good — used when transport_class is empty in goodsMVP.csv.
# If you populate transport_class with different names, add them as keys to TRANSPORT above.
CLASS_DEFAULT = {
    "coal":"heavy", "iron_ore":"heavy", "copper_ore":"heavy", "basic_salt":"heavy",
    "iron_ingots":"heavy", "copper_ingots":"heavy", "steel":"heavy",
    "copper_wiring":"heavy", "motor":"heavy",
    "pure_water":"liquid",
    "chlorine":"gas", "sodium_hydroxide":"gas", "hydrogen":"gas", "oxygen":"gas",
    "power":"power",
}

# --- load goods (internal_name -> base_price, transport_class) ---
PRICE, CLASS = {}, {}
with open(GOODS_CSV) as f:
    for row in csv.DictReader(f):
        name = row["internal_name"]
        if not name: continue
        PRICE[name] = float(row["base_price"]) if row["base_price"] else 0.0
        CLASS[name] = row["transport_class"] or CLASS_DEFAULT.get(name, "heavy")

# --- load buildings (ID -> per-run overhead: maintenance + labour wage bill) ---
BLD = {}
with open(BUILDINGS_CSV) as f:
    for row in csv.DictReader(f):
        bid = row["ID"]
        if not bid: continue
        m = float(row["maintenance_cost"] or 0)
        u = int(row["labour_unskilled_required"] or 0)
        s = int(row["labour_skilled_required"] or 0)
        h = int(row["labour_h_skilled_required"] or 0)
        BLD[bid] = m + u*WAGE["u"] + s*WAGE["s"] + h*WAGE["h"]

# --- load recipes ---
def parse_recipe(row):
    ins, outs = {}, {}
    for i in range(1, 6):
        g, q = row[f"input_{i}"], row[f"qty_{i}"]
        if g and q: ins[g] = float(q)
        g, q = row[f"output_{i}"], row[f"output_qty_{i}"]
        if g and q: outs[g] = float(q)
    return ins, float(row["energy_req"] or 0), outs

R = []
with open(RECIPES_CSV) as f:
    for row in csv.DictReader(f):
        if not row["recipe_id"]: continue
        ins, energy, outs = parse_recipe(row)
        if not outs: continue  # skip infrastructure rows (Roads, Port) — no production
        R.append((row["recipe_id"], row["display_name"], row["building_id"], ins, energy, outs))

# --- compute margins ---
ic = lambda d: sum(q*PRICE[g] for g,q in d.items())
tp = lambda d: sum(q*TRANSPORT[CLASS[g]] for g,q in d.items())
fmt_q = lambda q: int(q) if q == int(q) else q

print(f"{'recipe':22}{'rev':>6}{'naked':>7}{'coloc':>7}{'+pwr':>6}{'+inp':>7}  outputs")
print("-"*84)
for rid, name, bid, ins, E, outs in R:
    I = ic(ins); P = E*PRICE["power"]; F = BLD[bid]; T = tp(ins) + tp(outs)
    rev = sum(q*PRICE[g]*SELL for g,q in outs.items())
    naked = rev - I - P - F - T
    coloc = rev - I - P - F
    pwr   = rev - I - P*SELFPOWER - F
    inp   = rev - ic({g:q*0.85 for g,q in ins.items()}) - P*SELFPOWER - F
    pc = lambda x: f"{100*x/rev:.0f}%" if rev else "n/a"
    od = ",".join(f"{g}:{fmt_q(q)}" for g,q in outs.items())
    print(f"{name:22}{rev:6.0f}{pc(naked):>7}{pc(coloc):>7}{pc(pwr):>6}{pc(inp):>7}  {od}")
