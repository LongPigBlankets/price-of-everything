#!/usr/bin/env python3
"""Band fit on MATCHED populations, before and after, using one costing model for both.

    python3 -B tools/band_census.py <before_goods.csv> <before_recipes.csv>

Comparing 45/140 against 80/80 says nothing: the denominators are different populations
(all live recipes vs base-only) and the two figures were produced by different costing
models, because the "before" number still counted unsellable waste_water as revenue.

This reports every population against both datasets with a single model, so each row is a
like-for-like comparison. Populations:

  live        every recipe the catalog can promote (building resolves, all goods exist)
  costable    live, minus recipes with no sellable output or an unbuyable input — these
              are grid services and treatment plants, not profit centres, and no lever
              can put them in a band
  base        costable and ungated: the recipes a player can build at game start, which
              is the population the +15..+40 band was specified for
  gated       costable and behind research
"""
import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RU, RS, RH, GRID = 0.00304, 0.00912, 0.0304, 0.12
MAX_IN, MAX_OUT = 6, 5
BAND = (15.0, 40.0)

_m = re.search(r"const BUILDING_ALIAS := \{(.*?)\n\}", (ROOT / "scripts/catalog.gd").read_text(), re.S)
ALIAS = dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', _m.group(1))) if _m else {}
br = list(csv.reader(open(ROOT / "data/Buildings - buildingsMVP.csv")))
BH = br[0]
maint = {r[BH.index("internal_name")]: float(r[BH.index("maintenance_cost")] or 0)
         for r in br[1:] if len(r) > BH.index("maintenance_cost")}


def load(goods_path, recipes_path):
    gr = list(csv.reader(open(goods_path)))
    rr = list(csv.reader(open(recipes_path)))
    GH, RHDR = gr[0], rr[0]
    price = {r[GH.index("internal_name")]: float(r[GH.index("base_price")] or 0)
             for r in gr[1:] if len(r) > GH.index("base_price")}
    sell = {r[GH.index("internal_name")] for r in gr[1:]
            if len(r) > GH.index("is_sellable") and r[GH.index("is_sellable")].strip().upper() == "TRUE"}
    buy = {r[GH.index("internal_name")] for r in gr[1:]
           if len(r) > GH.index("is_buyable") and r[GH.index("is_buyable")].strip().upper() == "TRUE"}
    recs = [dict(zip(RHDR, x)) for x in rr[1:] if x and x[0]]
    return price, sell, buy, recs


def census(goods_path, recipes_path):
    price, sell, buy, recs = load(goods_path, recipes_path)

    def bld(r):
        return ALIAS.get(r["building_id"], r["building_id"])

    def outs(r):
        return [(r["output_%d" % i].strip(), int(r["output_qty_%d" % i]))
                for i in range(1, MAX_OUT + 1)
                if (r.get("output_%d" % i) or "").strip() and (r.get("output_qty_%d" % i) or "").strip()]

    def ins(r):
        return [(r["input_%d" % i].strip(), int(r["qty_%d" % i])) for i in range(1, MAX_IN + 1)
                if (r.get("input_%d" % i) or "").strip() and (r.get("qty_%d" % i) or "").strip()]

    def live(r):
        return (bld(r) in maint and all(g in price for g, _ in ins(r))
                and all(g in price for g, _ in outs(r)))

    def costable(r):
        return any(g in sell for g, _ in outs(r)) and all(g in buy for g, _ in ins(r))

    def net(r):
        rev = sum(price[g] * q for g, q in outs(r) if g in sell)
        lab = (int(r["labour_unskilled_required"] or 0) * RU
               + int(r["labour_skilled_required"] or 0) * RS
               + int(r["labour_h_skilled_required"] or 0) * RH)
        return (rev - sum(price[g] * q for g, q in ins(r))
                - float(r["energy_req"] or 0) * GRID - maint[bld(r)] - lab)

    L = [r for r in recs if live(r)]
    C = [r for r in L if costable(r)]
    B = [r for r in C if not (r.get("required_research") or "").strip()]
    G = [r for r in C if (r.get("required_research") or "").strip()]
    return {"live": (L, net), "costable": (C, net), "base": (B, net), "gated": (G, net)}


before = census(sys.argv[1], sys.argv[2])
after = census(ROOT / "data/Goods - goodsMVP.csv", ROOT / "data/recipes_all.csv")

print("BAND FIT IN +%.0f..+%.0f, ONE COSTING MODEL, MATCHED POPULATIONS\n" % BAND)
print("  %-10s %-28s %-28s" % ("population", "BEFORE", "AFTER"))
for pop in ("live", "costable", "base", "gated"):
    out = []
    for src in (before, after):
        rs, net = src[pop]
        n = [net(r) for r in rs]
        ok = sum(1 for x in n if BAND[0] <= x <= BAND[1])
        out.append("%3d/%3d (%3.0f%%)  below %2d  above %2d"
                   % (ok, len(rs), 100 * ok / len(rs) if rs else 0,
                      sum(1 for x in n if x < BAND[0]), sum(1 for x in n if x > BAND[1])))
    print("  %-10s %-28s %-28s" % (pop, out[0], out[1]))

rs_b, net_b = before["live"]
rs_a, net_a = after["live"]
print("\n  live recipe count: %d before, %d after (a solve moves numbers, never the roster)"
      % (len(rs_b), len(rs_a)))
excl_b = len(before["live"][0]) - len(before["costable"][0])
excl_a = len(after["live"][0]) - len(after["costable"][0])
print("  excluded as uncostable: %d before, %d after" % (excl_b, excl_a))
for r in before["live"][0]:
    if r["recipe_id"] not in {x["recipe_id"] for x in before["costable"][0]}:
        print("    %-7s %s" % (r["recipe_id"], r["display_name"]))
