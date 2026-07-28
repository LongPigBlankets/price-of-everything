#!/usr/bin/env python3
"""Report the embodied carbon Catalog derives for every good, and what it does to prices.

    python3 -B tools/carbon_intensity.py

Mirrors Catalog._compute_embodied_carbon so the derivation can be inspected without booting
the engine. TWO numbers per good, deliberately separate:

  co2_tax_multiplier  what the good releases when CONSUMED. Charged by PolicyState at the
                      point of combustion. Fossil fuels only.
  embodied carbon     what the good CARRIES from how it was made. Rides the market price via
                      MarketState.get_base_price_now, so buying cannot dodge the levy that
                      making it would have incurred.

Keeping them apart is what stops the same tonne of carbon being taxed at every step of a
chain — which would double-count and fall hardest on deep integration.

Derived from the BASE (ungated) route, dirtiest where a good has several, so a good is priced
as if produced the conventional way. The case where a player actually holds a clean route is
a later pass (owner, 2026-07-28).
"""
import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAX_IN, MAX_OUT = 6, 5
CO2_RATE = 1.0
PHASE = [0.0, 1.0, 2.0, 3.5]

gr = list(csv.reader(open(ROOT / "data/Goods - goodsMVP.csv")))
rr = list(csv.reader(open(ROOT / "data/recipes_all.csv")))
br = list(csv.reader(open(ROOT / "data/Buildings - buildingsMVP.csv")))
GH, RHDR, BH = gr[0], rr[0], br[0]
G = {x[GH.index("internal_name")]: dict(zip(GH, x)) for x in gr[1:] if len(x) > GH.index("base_price")}
price = {k: float(v["base_price"] or 0) for k, v in G.items()}
seed = {k: float(v["co2_tax_multiplier"] or 0) for k, v in G.items()}
fossil = {k for k, v in G.items() if v["is_fossil_fuel"].strip().lower() == "yes"}
maint = {x[BH.index("internal_name")]: float(x[BH.index("maintenance_cost")] or 0) for x in br[1:]
         if len(x) > BH.index("maintenance_cost")}
_m = re.search(r"const BUILDING_ALIAS := \{(.*?)\n\}", (ROOT / "scripts/catalog.gd").read_text(), re.S)
ALIAS = dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', _m.group(1))) if _m else {}
R = [dict(zip(RHDR, x)) for x in rr[1:] if x and x[0]]


def bld(r):
    return ALIAS.get(r["building_id"], r["building_id"])


def outs(r):
    return [(r["output_%d" % i].strip(), int(r["output_qty_%d" % i])) for i in range(1, MAX_OUT + 1)
            if (r.get("output_%d" % i) or "").strip() and (r.get("output_qty_%d" % i) or "").strip()]


def ins(r):
    return [(r["input_%d" % i].strip(), int(r["qty_%d" % i])) for i in range(1, MAX_IN + 1)
            if (r.get("input_%d" % i) or "").strip() and (r.get("qty_%d" % i) or "").strip()]


def live(r):
    return (bld(r) in maint and all(g in price for g, _ in ins(r))
            and all(g in price for g, _ in outs(r)))


L = [r for r in R if live(r)]
BASE = [r for r in L if not (r.get("required_research") or "").strip()]

# The representative route is the DIRTIEST base (ungated) producer, matching the engine:
# a good is priced as if produced the conventional way, so unlocking a clean recipe does not
# silently cheapen everyone else's market price.
makers = {}
for r in BASE:
    o = outs(r)
    if o:
        makers.setdefault(o[0][0], []).append(r)

# ---- PINNED seeds ---------------------------------------------------------------------
# A good that already carries a hand-set multiplier is a deliberate point-of-combustion
# calibration and must NOT be re-derived: processed_oil is 2.7 while the crude it comes from
# is 0.1, because the tax is meant to land where the fuel is burned, not where it is pumped.
# Deriving it from the DAG would collapse it to 0.11 and gut the policy.
#
# pet_coke is the gap the owner named: a petroleum product, is_fossil_fuel=yes, taxed at 0.
# It is a solid carbon fuel burned like coal, and carries more carbon per unit than coal does,
# so it is seeded ABOVE coal rather than derived from the refinery route (which would give it
# crude's 0.1 and leave the coal-vs-needle-coke arbitrage wide open).
PIN = {g: v for g, v in seed.items() if v > 0}
PIN.setdefault("pet_coke", 0.75)          # coal is 0.50; pet coke is the denser carbon fuel
PRIMARY = set(PIN) | fossil


def cascade(good, seen=()):
    if good in PIN:
        return PIN[good]
    if good in PRIMARY or good in seen:
        return seed.get(good, 1.0 if good in fossil else 0.0)
    rs = makers.get(good)
    if not rs:
        return seed.get(good, 0.0)
    best = None
    for r in rs:
        q = dict(outs(r)).get(good, 0)
        if q <= 0:
            continue
        c = sum(qi * cascade(gi, seen + (good,)) for gi, qi in ins(r)) / q
        best = c if best is None else max(best, c)
    return PIN.get(good, seed.get(good, 0.0)) if best is None else best


def point(good):
    """Only the good's own fossil character is taxed. Manufactured goods carry nothing —
    they get dearer through the market price instead."""
    return PIN.get(good, 0.0) if good in fossil or good in PIN else 0.0


print("PER-GOOD CARBON MULTIPLIER — hand-set today vs derived\n")
print("  %-22s %8s %7s %9s %9s   %s" % ("good", "price", "fossil", "today", "CASCADE", "note"))
rows = []
for g in sorted(G):
    c, p = cascade(g), point(g)
    if seed[g] == 0 and c < 0.005:
        continue
    note = ""
    if g in fossil and seed[g] == 0:
        note = "FOSSIL but untaxed today"
    elif seed[g] == 0 and c > 0:
        note = "fossil-derived, untaxed today"
    print("  %-22s %8.3f %7s %9.2f %9.2f   %s"
          % (g, price[g], "yes" if g in fossil else "no", seed[g], c, note))
    rows.append((g, c, p))

print("\n\nWHAT THE CASCADE MODEL DOES TO A DEEP CHAIN (levy per turn at P1, scale 1.0)\n")
print("  %-7s %-34s %10s %10s   %s" % ("recipe", "name", "CASCADE", "POINT", "fossil inputs"))
for rid in ("r_003", "r_009", "r_071", "r_117", "r_231", "r_042", "r_023", "r_228", "r_150"):
    r = next((x for x in L if x["recipe_id"] == rid), None)
    if r is None:
        continue
    lc = sum(q * cascade(g) for g, q in ins(r)) * CO2_RATE * PHASE[1]
    lp = sum(q * point(g) for g, q in ins(r)) * CO2_RATE * PHASE[1]
    ff = ", ".join("%s x%d" % (g, q) for g, q in ins(r) if g in fossil) or "none direct"
    print("  %-7s %-34s %10.2f %10.2f   %s" % (rid, r["display_name"][:34], lc, lp, ff))

print("\n  CASCADE is what a levy on manufactured goods would charge; POINT is what is actually")
print("  charged. The gap is the double count avoided — it rides the market price instead.")

if "--write" in sys.argv:
    model = "point" if "--point" in sys.argv else "cascade"
    col = GH.index("co2_tax_multiplier")
    vals = {g: round(p if model == "point" else c, 4) for g, c, p in
            [(g, cascade(g), point(g)) for g in G]}
    for x in gr[1:]:
        if len(x) > col and x[GH.index("internal_name")] in vals:
            x[col] = "%.4g" % vals[x[GH.index("internal_name")]]
    csv.writer(open(ROOT / "data/Goods - goodsMVP.csv", "w", newline="")).writerows(gr)
    print("\nwrote co2_tax_multiplier for %d goods using the %s model" % (len(vals), model))
