#!/usr/bin/env python3
"""Score fully-integrated CHAINS against the owner's depth bands, not just single recipes.

    python3 -B tools/chain_bands.py [changeset.json]

A per-recipe band says nothing about the thing the player actually experiences: owning the
whole chain. Building every upstream step in-house replaces each purchased input with a
building that has its own maintenance, labour and power, so a chain's profit is emphatically
not the sum of its parts as bought.

For each sellable good this builds the cheapest in-house chain that makes it — every input
produced internally where a base recipe exists, bought from market otherwise — and reports
the whole chain's per-turn profit against the cap for its depth:

    depth 1 (raw)   +40        depth 4          +450
    depth 2         +100       depth 5+ (apex)  +600
    depth 3         +200       every chain      +30 minimum

Depth is the longest producer path, so a good is only "two-step" if nothing beneath it is
deeper. Chains are costed at ONE building per step: a step needing three of its feeder's
output still counts one building, which is the optimistic reading and therefore the one that
catches a cap breach.
"""
import csv
import json
import re
import sys
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RU, RS, RH, GRID = 0.00304, 0.00912, 0.0304, 0.12
MAX_IN, MAX_OUT = 6, 5
CAPS = {1: 40.0, 2: 100.0, 3: 200.0, 4: 450.0}
APEX_CAP, FLOOR = 600.0, 30.0

gr = list(csv.reader(open(ROOT / "data/Goods - goodsMVP.csv")))
br = list(csv.reader(open(ROOT / "data/Buildings - buildingsMVP.csv")))
rr = list(csv.reader(open(ROOT / "data/recipes_all.csv")))
GH, BH, RHDR = gr[0], br[0], rr[0]

price = {r[GH.index("internal_name")]: float(r[GH.index("base_price")] or 0)
         for r in gr[1:] if len(r) > GH.index("base_price")}
SELLABLE = {r[GH.index("internal_name")] for r in gr[1:]
            if len(r) > GH.index("is_sellable") and r[GH.index("is_sellable")].strip().upper() == "TRUE"}
BUYABLE = {r[GH.index("internal_name")] for r in gr[1:]
           if len(r) > GH.index("is_buyable") and r[GH.index("is_buyable")].strip().upper() == "TRUE"}
maint = {r[BH.index("internal_name")]: float(r[BH.index("maintenance_cost")] or 0)
         for r in br[1:] if len(r) > BH.index("maintenance_cost")}
_m = re.search(r"const BUILDING_ALIAS := \{(.*?)\n\}", (ROOT / "scripts/catalog.gd").read_text(), re.S)
ALIAS = dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', _m.group(1))) if _m else {}
recs = {r["recipe_id"]: r for r in (dict(zip(RHDR, x)) for x in rr[1:] if x and x[0])}

# ---- optionally overlay a change set so a chain can be scored before it is applied -------
if len(sys.argv) > 1:
    S = json.loads(Path(sys.argv[1]).read_text())
    for e in S.get("prices", []):
        price[e["good"]] = float(e["new"])
    for e in S.get("input_qty", []):
        r = recs[e["recipe"]]
        for i in range(1, MAX_IN + 1):
            if (r.get("input_%d" % i) or "").strip() == e["good"]:
                r["qty_%d" % i] = str(int(e["new"])); break
    for e in S.get("output_qty", []):
        r = recs[e["recipe"]]
        for i in range(1, MAX_OUT + 1):
            if (r.get("output_%d" % i) or "").strip() == e["good"]:
                r["output_qty_%d" % i] = str(int(e["new"])); break
    for e in S.get("labour_mult", []):
        r = recs[e["recipe"]]
        for c, f in (("labour_unskilled_required", 500), ("labour_skilled_required", 100),
                     ("labour_h_skilled_required", 50)):
            o = int(r[c] or 0)
            r[c] = str(max(min(o, f), round(o * float(e["mult"]))))


def bld(r):
    return ALIAS.get(r["building_id"], r["building_id"])


def outs(r):
    return [(r["output_%d" % i].strip(), int(r["output_qty_%d" % i])) for i in range(1, MAX_OUT + 1)
            if (r.get("output_%d" % i) or "").strip() and (r.get("output_qty_%d" % i) or "").strip()]


def ins(r):
    return [(r["input_%d" % i].strip(), int(r["qty_%d" % i])) for i in range(1, MAX_IN + 1)
            if (r.get("input_%d" % i) or "").strip() and (r.get("qty_%d" % i) or "").strip()]


def live(r):
    if bld(r) not in maint:
        return False
    return all(g in price for g, _ in ins(r)) and all(g in price for g, _ in outs(r))


L = [r for r in recs.values() if live(r)]
BASE = [r for r in L if not (r.get("required_research") or "").strip()]
maker = {}
for r in BASE:
    o = outs(r)
    if o and (o[0][0] not in maker or o[0][1] > outs(maker[o[0][0]])[0][1]):
        maker[o[0][0]] = r


def own_net(r):
    """Standalone profit: sell every sellable output, buy every input."""
    rev = sum(price[g] * q for g, q in outs(r) if g in SELLABLE)
    return (rev - sum(price[g] * q for g, q in ins(r)) - float(r["energy_req"] or 0) * GRID
            - maint[bld(r)] - (int(r["labour_unskilled_required"] or 0) * RU
                               + int(r["labour_skilled_required"] or 0) * RS
                               + int(r["labour_h_skilled_required"] or 0) * RH))


@lru_cache(maxsize=None)
def depth(good, seen=()):
    r = maker.get(good)
    if r is None or good in seen:
        return 1
    sub = [depth(g, seen + (good,)) for g, _ in ins(r) if g in maker]
    return 1 + max(sub) if sub else 1


def chain(good):
    """The SET of buildings that makes `good` in-house, and the set's profit.

    A set, not a recursion: two branches both needing steel share ONE steel mill, and
    recursing per-input would count that mill — and its profit — twice over.

    Profit is computed on the set's EXTERNAL position rather than by summing member nets:
    each good's internal production and consumption cancel, whatever is left over is sold
    (if sellable) or bought (if buyable), and every member's fixed costs stay on the books.
    """
    chosen, stack = {}, [good]
    while stack:
        g = stack.pop()
        r = maker.get(g)
        if r is None or r["recipe_id"] in chosen:
            continue
        chosen[r["recipe_id"]] = r
        for gi, _ in ins(r):
            if gi in maker:
                stack.append(gi)
    if not chosen:
        return {}, 0.0
    made, used = {}, {}
    fixed = 0.0
    for r in chosen.values():
        for g2, q in outs(r):
            made[g2] = made.get(g2, 0) + q
        for g2, q in ins(r):
            used[g2] = used.get(g2, 0) + q
        fixed += (float(r["energy_req"] or 0) * GRID + maint[bld(r)]
                  + int(r["labour_unskilled_required"] or 0) * RU
                  + int(r["labour_skilled_required"] or 0) * RS
                  + int(r["labour_h_skilled_required"] or 0) * RH)
    flow = 0.0
    for g2 in set(made) | set(used):
        bal = made.get(g2, 0) - used.get(g2, 0)
        if bal > 0 and g2 in SELLABLE:
            flow += price[g2] * bal          # surplus leaves the chain
        elif bal < 0 and g2 in BUYABLE:
            flow += price[g2] * bal          # shortfall is bought in
    return chosen, flow - fixed


rows = []
for good in sorted(maker):
    if good not in SELLABLE:
        continue
    d = depth(good)
    steps, p = chain(good)
    cap = CAPS.get(d, APEX_CAP)
    lo = 15.0 if d == 1 else FLOOR      # a one-building "chain" is the standalone case
    rows.append((good, d, len(steps), p, cap, lo <= p <= cap))

ok = sum(1 for x in rows if x[5])
print("FULLY-INTEGRATED CHAIN BANDS  (%s)"
      % (sys.argv[1] if len(sys.argv) > 1 else "live CSVs, no change set"))
print("  %d / %d chains inside +%.0f..cap  (%.0f%%)\n" % (ok, len(rows), FLOOR, 100 * ok / len(rows)))
for d in sorted({x[1] for x in rows}):
    grp = [x for x in rows if x[1] == d]
    g_ok = sum(1 for x in grp if x[5])
    lo = 15.0 if d == 1 else FLOOR
    print("  depth %d (%+.0f..%+.0f): %2d/%2d in band   below %d   above %d"
          % (d, lo, CAPS.get(d, APEX_CAP), g_ok, len(grp),
             sum(1 for x in grp if x[3] < lo), sum(1 for x in grp if x[3] > CAPS.get(d, APEX_CAP))))
print("\nEVERY CHAIN")
for good, d, n, pr, cap, okk in sorted(rows, key=lambda x: (x[1], -x[3])):
    print("  %-24s d%d %3d bldgs %+9.1f  (%+.1f/bldg)  cap %+.0f %s"
          % (good, d, n, pr, pr / n, cap, "" if okk else "  <-- OUT"))
print("\nWORST BREACHES")
for good, d, n, p, cap, good_ok in sorted(rows, key=lambda x: -(x[3] - x[4]))[:8]:
    if not good_ok:
        print("  %-24s depth %d  %2d bldgs  %+9.1f  cap %+.0f  OVER by %+.0f" % (good, d, n, p, cap, p - cap))
for good, d, n, p, cap, good_ok in sorted(rows, key=lambda x: x[3])[:6]:
    if not good_ok:
        print("  %-24s depth %d  %2d bldgs  %+9.1f  floor %+.0f  UNDER"
              % (good, d, n, p, 15.0 if d == 1 else FLOOR))
