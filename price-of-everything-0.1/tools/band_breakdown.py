#!/usr/bin/env python3
"""The three band populations, listed rather than counted.

    python3 -B tools/band_breakdown.py [--csv reports/balance/band_breakdown.csv]

  1. BASE recipes, standalone at game start        target +15..+40
  2. GATED recipes against their base sibling      research must never be a downgrade
  3. TWO-STEP pairs (producer feeding consumer)    target +30..+75

Section 3 costs a pair by its EXTERNAL position: the internal transfer cancels, whatever the
producer makes beyond the consumer's need is sold, any shortfall is bought, and both
buildings' fixed costs stay on the books. Valuing that transfer at the same price on both
sides makes pair profit identically net(producer) + net(consumer) — which the tool asserts
rather than assumes, since the identity is what makes the section trustworthy. It holds only
because the static model has no bid-ask spread; the live engine charges a 5% buy markup, so
in game a pair earns slightly less than its two halves did apart.
"""
import csv
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RU, RS, RH, GRID = 0.00304, 0.00912, 0.0304, 0.12
MAX_IN, MAX_OUT = 6, 5
BASE_BAND, PAIR_BAND = (15.0, 40.0), (30.0, 75.0)

gr = list(csv.reader(open(ROOT / "data/Goods - goodsMVP.csv")))
br = list(csv.reader(open(ROOT / "data/Buildings - buildingsMVP.csv")))
rr = list(csv.reader(open(ROOT / "data/recipes_all.csv")))
GH, BH, RHDR = gr[0], br[0], rr[0]
price = {r[GH.index("internal_name")]: float(r[GH.index("base_price")] or 0)
         for r in gr[1:] if len(r) > GH.index("base_price")}
SELL = {r[GH.index("internal_name")] for r in gr[1:]
        if len(r) > GH.index("is_sellable") and r[GH.index("is_sellable")].strip().upper() == "TRUE"}
BUY = {r[GH.index("internal_name")] for r in gr[1:]
       if len(r) > GH.index("is_buyable") and r[GH.index("is_buyable")].strip().upper() == "TRUE"}
maint = {r[BH.index("internal_name")]: float(r[BH.index("maintenance_cost")] or 0)
         for r in br[1:] if len(r) > BH.index("maintenance_cost")}
bname = {r[BH.index("internal_name")]: r[BH.index("display_name")] for r in br[1:] if len(r) > 1}
_m = re.search(r"const BUILDING_ALIAS := \{(.*?)\n\}", (ROOT / "scripts/catalog.gd").read_text(), re.S)
ALIAS = dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', _m.group(1))) if _m else {}
recs = [dict(zip(RHDR, x)) for x in rr[1:] if x and x[0]]


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


def costable(r):
    return any(g in SELL for g, _ in outs(r)) and all(g in BUY for g, _ in ins(r))


def fixed(r):
    return (float(r["energy_req"] or 0) * GRID + maint[bld(r)]
            + int(r["labour_unskilled_required"] or 0) * RU
            + int(r["labour_skilled_required"] or 0) * RS
            + int(r["labour_h_skilled_required"] or 0) * RH)


def net(r):
    return (sum(price[g] * q for g, q in outs(r) if g in SELL)
            - sum(price[g] * q for g, q in ins(r)) - fixed(r))


L = [r for r in recs if live(r)]
C = [r for r in L if costable(r)]
BASE = [r for r in C if not (r.get("required_research") or "").strip()]
GATED = [r for r in C if (r.get("required_research") or "").strip()]
rows_csv = []

# ---- 1. base recipes, standalone -----------------------------------------------------
print("=" * 100)
print("1. BASE RECIPES — standalone at game start, target %+.0f..%+.0f" % BASE_BAND)
print("=" * 100)
print("  %-7s %-38s %-20s %8s  %s" % ("id", "recipe", "building", "net", "band"))
for r in sorted(BASE, key=lambda x: -net(x)):
    n = net(r)
    mark = "OK" if BASE_BAND[0] <= n <= BASE_BAND[1] else ("LOW" if n < BASE_BAND[0] else "HIGH")
    print("  %-7s %-38s %-20s %+8.1f  %s"
          % (r["recipe_id"], r["display_name"][:38], bname.get(bld(r), bld(r))[:20], n, mark))
    rows_csv.append(["base", r["recipe_id"], r["display_name"], bname.get(bld(r), bld(r)),
                     "%.2f" % n, "", mark])
nb = [net(r) for r in BASE]
print("  --> %d/%d in band | min %+.1f  median %+.1f  max %+.1f"
      % (sum(1 for x in nb if BASE_BAND[0] <= x <= BASE_BAND[1]), len(nb),
         min(nb), sorted(nb)[len(nb) // 2], max(nb)))

# ---- 2. gated vs the base route for the same good ------------------------------------
# "Base sibling" scoped to the same BUILDING is the right test for R2 — research must not
# downgrade a given building. It is the WRONG test for the question a player actually asks,
# which is "does this route beat the base route for this good?". Building is irrelevant to
# that: Fabless Semiconductors competes with Semiconductor Fabbing across a building change,
# and scoping by building hides the comparison entirely.
#
# Both tests are reported. Same-building is the structural rule; same-good is the economics.
def o1(r):
    return outs(r)[0][0] if outs(r) else ""


print()
print("=" * 100)
print("2. GATED RECIPES — against the best BASE route for the same good (any building)")
print("=" * 100)
same_bldg, diff_bldg, brand_new = [], [], []
for r in GATED:
    g = o1(r)
    sg = [b for b in BASE if o1(b) == g]
    if not sg:
        brand_new.append(r)
    elif [b for b in sg if bld(b) == bld(r)]:
        same_bldg.append((r, max(sg, key=net)))
    else:
        diff_bldg.append((r, max(sg, key=net)))

for title, group in (("2a. UPGRADE IN PLACE — base route is the same building",
                      sorted(same_bldg, key=lambda t: net(t[0]) - net(t[1]))),
                     ("2b. COMPETING ROUTE — base route is a different building",
                      sorted(diff_bldg, key=lambda t: net(t[0]) - net(t[1])))):
    print()
    print("  " + title)
    print("    %-7s %-32s %-22s %8s %8s %9s %8s"
          % ("id", "recipe", "beats / loses to", "gated", "base", "uplift", "per-unit"))
    for r, b in group:
        g = o1(r)
        qg, qb = dict(outs(r))[g], dict(outs(b))[g]
        up = net(r) - net(b)
        pu = net(r) / qg - net(b) / qb
        print("    %-7s %-32s %-22s %+8.1f %+8.1f %+9.1f %+8.2f%s"
              % (r["recipe_id"], r["display_name"][:32],
                 "%s %s" % (b["recipe_id"], b["display_name"][:14]), net(r), net(b), up, pu,
                 "   <-- WORSE THAN BASE" if up < 0 else ""))
        rows_csv.append(["gated_" + ("same_bldg" if (r, b) in same_bldg else "diff_bldg"),
                         r["recipe_id"], r["display_name"], r.get("required_research", ""),
                         "%.2f" % net(r), "%.2f" % net(b), "uplift %+.2f" % up])
    ups = [net(r) - net(b) for r, b in group]
    print("    --> %d recipes | uplift min %+.1f  median %+.1f  max %+.1f | %d worse than base"
          % (len(group), min(ups), sorted(ups)[len(ups) // 2], max(ups),
             sum(1 for u in ups if u < 0)))

print()
print("  2c. NEW GOOD — no base recipe produces this at all, so there is nothing to beat")
print("    %-7s %-38s %-24s %8s" % ("id", "recipe", "good", "net"))
for r in sorted(brand_new, key=lambda x: -net(x)):
    print("    %-7s %-38s %-24s %+8.1f  %s"
          % (r["recipe_id"], r["display_name"][:38], o1(r), net(r),
             "OK" if net(r) >= BASE_BAND[0] else "LOW"))
    rows_csv.append(["gated_new_good", r["recipe_id"], r["display_name"],
                     r.get("required_research", ""), "%.2f" % net(r), "", o1(r)])
print("    --> %d recipes | %d below the +%.0f floor"
      % (len(brand_new), sum(1 for r in brand_new if net(r) < BASE_BAND[0]), BASE_BAND[0]))

# ---- 3. two-step pairs ---------------------------------------------------------------
print()
print("=" * 100)
print("3. TWO-STEP PAIRS — one producer feeding one consumer, target %+.0f..%+.0f" % PAIR_BAND)
print("=" * 100)
producer = {}
for r in BASE:
    o = outs(r)
    if o and (o[0][0] not in producer or o[0][1] > outs(producer[o[0][0]])[0][1]):
        producer[o[0][0]] = r

pairs = []
for c in BASE:
    for g, qc in ins(c):
        p = producer.get(g)
        if p is None or p["recipe_id"] == c["recipe_id"]:
            continue
        qp = dict(outs(p))[g]
        # external position of the two buildings taken together
        made, used = defaultdict(int), defaultdict(int)
        for r in (p, c):
            for g2, q in outs(r):
                made[g2] += q
            for g2, q in ins(r):
                used[g2] += q
        flow = 0.0
        for g2 in set(made) | set(used):
            bal = made[g2] - used[g2]
            if bal > 0 and g2 in SELL:
                flow += price[g2] * bal
            elif bal < 0 and g2 in BUY:
                flow += price[g2] * bal
        prof = flow - fixed(p) - fixed(c)
        # the identity that makes this section trustworthy: with the transfer valued the same
        # on both sides, a pair is worth exactly its two halves. Assert, do not assume.
        assert abs(prof - (net(p) + net(c))) < 1e-6, (p["recipe_id"], c["recipe_id"], prof)
        pairs.append((g, p, c, qp, qc, prof))

print("  %-7s->%-7s %-30s %-26s %6s %8s  %s"
      % ("prod", "cons", "via good (make/need)", "consumer", "ratio", "pair", "band"))
for g, p, c, qp, qc, prof in sorted(pairs, key=lambda t: -t[5]):
    mark = "OK" if PAIR_BAND[0] <= prof <= PAIR_BAND[1] else ("LOW" if prof < PAIR_BAND[0] else "HIGH")
    print("  %-7s->%-7s %-30s %-26s %5.2fx %+8.1f  %s"
          % (p["recipe_id"], c["recipe_id"], "%s (%d/%d)" % (g[:18], qp, qc),
             c["display_name"][:26], qc / qp, prof, mark))
    rows_csv.append(["pair", "%s->%s" % (p["recipe_id"], c["recipe_id"]),
                     c["display_name"], g, "%.2f" % prof, "%.2f" % (qc / qp), mark])
pp = [x[5] for x in pairs]
inb = sum(1 for x in pp if PAIR_BAND[0] <= x <= PAIR_BAND[1])
print("  --> %d/%d pairs in band (%.0f%%) | min %+.1f  median %+.1f  max %+.1f"
      % (inb, len(pp), 100 * inb / len(pp), min(pp), sorted(pp)[len(pp) // 2], max(pp)))
print("      below %d   above %d" % (sum(1 for x in pp if x < PAIR_BAND[0]),
                                     sum(1 for x in pp if x > PAIR_BAND[1])))

if "--csv" in sys.argv:
    out = Path(sys.argv[sys.argv.index("--csv") + 1])
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["section", "id", "name", "context", "net", "compare", "verdict"])
        w.writerows(rows_csv)
    print("\nwrote %s (%d rows)" % (out, len(rows_csv)))
