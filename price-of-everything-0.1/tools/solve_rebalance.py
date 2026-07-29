#!/usr/bin/env python3
"""Constrained solve for the 2026-07-28 rebalance. Writes a change set; applies nothing.

    python3 -B tools/solve_rebalance.py [out.json]

THE PROBLEM
  Land every live recipe in a profit band, subject to hard structural rules, using only
  three levers: output quantity, good price, and labour 0.40-1.00x. Input and output GOODS
  are untouchable — quantities may move, the goods themselves may not.

RULES (owner spec)
  RATIO  consumer_demand / producer_supply must be one of 0.33 0.5 0.75 1.0 1.2 1.5 2.0
         (a consumer needing 33 against a producer making 100 is the 0.33x case)
  R2     a gated recipe makes 1.0 / 1.2 / 1.5 / 2.0x its base on the SAME building, never less
  R3     every output quantity is a multiple of 3, 4 or 5
  R4     stoichiometric recipes keep their ratios — joint-product chemistry is PINNED here
         rather than solved, because moving one output silently moves the others
  BANDS  standalone +15..+40 pre-tax per turn

WHY WEIGHTED
  A good with one bulk consumer and a dozen trace consumers cannot put every pair on the
  ladder at any output. Minimising raw movement lets the trace users outvote the bulk one and
  collapses every output to a third of its value. Each consumer is therefore weighted by its
  share of the producer's output, so the relationship the player actually experiences (one
  furnace feeding one factory) survives and the trace users absorb the movement.
"""
import csv
import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "reports/balance/solved_changeset.json"

RU, RS, RH, GRID = 0.00304, 0.00912, 0.0304, 0.12
LADDER = [0.33, 0.5, 0.75, 1.0, 1.2, 1.5, 2.0]
GATED_MULT = [1.0, 1.2, 1.5, 2.0]
BAND = (15.0, 40.0)
MAX_IN, MAX_OUT = 6, 5

# Recipes whose output RATIOS encode a real balanced reaction. Their quantities may scale as a
# whole but never independently, so the solver leaves them alone and lets price carry them.
STOICH_PINNED = {
    "r_012",  # chlor-alkali 2NaCl+2H2O -> 2NaOH+Cl2+H2, exactly 2:1:1
    "r_079", "r_080",  # water electrolysis 2H2O -> 2H2+O2
    "r_046",  # Haber-Bosch N2+3H2 -> 2NH3
    "r_117",  # methane pyrolysis
}

goods_rows = list(csv.reader(open(ROOT / "data/Goods - goodsMVP.csv")))
build_rows = list(csv.reader(open(ROOT / "data/Buildings - buildingsMVP.csv")))
rec_rows = list(csv.reader(open(ROOT / "data/recipes_all.csv")))
GH, BH, RHDR = goods_rows[0], build_rows[0], rec_rows[0]

price0 = {r[GH.index("internal_name")]: float(r[GH.index("base_price")] or 0)
          for r in goods_rows[1:] if len(r) > GH.index("base_price")}
# waste_water is is_sellable=FALSE / is_buyable=FALSE: it has no market. Its base_price feeds
# internal imputed-cost accounting only, so counting it as revenue pays a producer for effluent
# and lets the price solve inflate it without limit. Revenue counts SELLABLE outputs only.
SELLABLE = {r[GH.index("internal_name")] for r in goods_rows[1:]
            if len(r) > GH.index("is_sellable") and r[GH.index("is_sellable")].strip().upper() == "TRUE"}
BUYABLE = {r[GH.index("internal_name")] for r in goods_rows[1:]
           if len(r) > GH.index("is_buyable") and r[GH.index("is_buyable")].strip().upper() == "TRUE"}
PRICE_FLOOR_MULT, PRICE_CEIL_MULT = 0.40, 2.50   # a rebalance, not a new economy
maint = {r[BH.index("internal_name")]: float(r[BH.index("maintenance_cost")] or 0)
         for r in build_rows[1:] if len(r) > BH.index("maintenance_cost")}
_m = re.search(r"const BUILDING_ALIAS := \{(.*?)\n\}", (ROOT / "scripts/catalog.gd").read_text(), re.S)
ALIAS = dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', _m.group(1))) if _m else {}

recipes = [dict(zip(RHDR, r)) for r in rec_rows[1:] if r and r[0]]


def bld(r):
    return ALIAS.get(r["building_id"], r["building_id"])


def live(r):
    if bld(r) not in maint:
        return False
    for i in range(1, MAX_IN + 1):
        n = (r.get("input_%d" % i) or "").strip()
        if n and n not in price0:
            return False
    for i in range(1, MAX_OUT + 1):
        n = (r.get("output_%d" % i) or "").strip()
        if n and n not in price0:
            return False
    return True


L = [r for r in recipes if live(r)]
BASE = [r for r in L if not (r.get("required_research") or "").strip()]


def outs(r):
    return [((r["output_%d" % i]).strip(), int(r["output_qty_%d" % i]))
            for i in range(1, MAX_OUT + 1)
            if (r.get("output_%d" % i) or "").strip() and (r.get("output_qty_%d" % i) or "").strip()]


def ins(r):
    return [((r["input_%d" % i]).strip(), int(r["qty_%d" % i]))
            for i in range(1, MAX_IN + 1)
            if (r.get("input_%d" % i) or "").strip() and (r.get("qty_%d" % i) or "").strip()]


def nice(q):
    return q > 0 and (q % 3 == 0 or q % 4 == 0 or q % 5 == 0)


def labour(r, mult=1.0):
    tot = 0.0
    for c, rate, floor in (("labour_unskilled_required", RU, 500),
                           ("labour_skilled_required", RS, 100),
                           ("labour_h_skilled_required", RH, 50)):
        o = int(r[c] or 0)
        tot += max(min(o, floor), round(o * mult)) * rate
    return tot



TOL = 0.04          # same tolerance the rule checker uses, so the two agree exactly


def legal_for(P):
    """Consumer quantities that actually LAND on a ladder rung against a producer making P.

    Not round(rung * P): at small P the integers cannot express the ladder — a producer
    making 5 against round(0.33*5)=2 gives 0.40x, which is off-ladder however it was derived.
    Generating from the achieved ratio instead means an output that cannot express the rungs
    its consumers need is simply rejected, and the search moves to one that can."""
    return [n for n in range(1, 3 * P + 1)
            if min(abs(n / P - a) for a in LADDER) <= TOL]


# ============ PHASE 1 — quantities ==================================================
new_out = {}   # (recipe_id, good) -> qty
new_in = {}    # (recipe_id, good) -> qty

# --- 1a. pinned chemistry, scaled as whole recipes -----------------------------------
# These settle FIRST: they set the producer supply that the ratio snap then measures against.
# Scaling a whole recipe by one rational factor is what lets R3 (nice numbers) and R4
# (stoichiometry) coexist — moving a single output would unbalance the reaction.
FACTORS = [(1,1),(10,11),(8,7),(6,7),(12,11),(5,7),(4,7),(3,2),(2,1),(4,3),(5,4),(5,3),
           (20,11),(16,11),(24,11),(7,5),(9,7),(11,7),(15,11),(18,11),(9,5),(12,7)]


def scale_pinned(r, want=None):
    """Smallest whole-recipe rescale making every output nice. `want` pins output_1 exactly,
    which is how a gated variant is held on its R2 multiplier."""
    o = outs(r)
    for num, den in FACTORS:
        f = num / den
        scaled = [(g, max(1, round(q * f))) for g, q in o]
        if not all(nice(q) for _, q in scaled):
            continue
        if want is not None and scaled[0][1] != want:
            continue
        if any(not legal_for(q) for _, q in scaled):
            continue
        for g, q in scaled:
            new_out[(r["recipe_id"], g)] = q
        for g, q in ins(r):
            new_in[(r["recipe_id"], g)] = max(1, round(q * f))
        return True
    return False


pinned_recs = [r for r in L if r["recipe_id"] in STOICH_PINNED]
for r in pinned_recs:
    if not (r.get("required_research") or "").strip():
        scale_pinned(r)
for r in pinned_recs:                       # gated variants, held to their R2 multiplier
    if not (r.get("required_research") or "").strip():
        continue
    g0 = outs(r)[0][0]
    sib = [b for b in L if not (b.get("required_research") or "").strip()
           and outs(b) and outs(b)[0][0] == g0 and bld(b) == bld(r)]
    if not sib:
        scale_pinned(r)
        continue
    bq = max(new_out.get((b["recipe_id"], g0), dict(outs(b))[g0]) for b in sib)
    for m in GATED_MULT:                    # nearest legal multiplier that is also reachable
        if scale_pinned(r, want=max(1, round(m * bq))):
            break

# --- 1b. ratio snap -------------------------------------------------------------------
# A good's producer supply is the ungated recipe whose PRIMARY output is that good — the
# recipe a player builds to make it. A byproduct stream (chlor-alkali's hydrogen) is not a
# hydrogen plant, and treating it as one measures every consumer against the wrong number.
base_producer = {}
for good in price0:
    ps = [r for r in BASE if outs(r) and outs(r)[0][0] == good]
    if ps:
        p = max(ps, key=lambda r: new_out.get((r["recipe_id"], good), dict(outs(r))[good]))
        base_producer[good] = (p["recipe_id"],
                               new_out.get((p["recipe_id"], good), dict(outs(p))[good]))

consumers = defaultdict(list)
for r in L:
    for g, q in ins(r):
        if g in base_producer:
            consumers[g].append((r["recipe_id"], q))

for good, (prid, P0) in base_producer.items():
    cons = consumers.get(good, [])
    if not cons:
        continue

    def cost(P):
        legal = legal_for(P)
        if not legal:
            return float("inf")
        c = abs(math.log(P / P0)) * 2.0
        for _, q in cons:
            n = min(legal, key=lambda x: abs(math.log(x / q)))
            c += min(1.0, q / P0) * abs(math.log(n / q))
        return c

    if prid in STOICH_PINNED:
        P = P0                              # already settled in 1a; consumers move to it
    else:
        P = min([p for p in range(1, int(P0 * 2.5) + 1) if nice(p)] or [P0], key=cost)
        if P != P0:
            new_out[(prid, good)] = P
    legal = legal_for(P)
    for rid, q in cons:
        n = min(legal, key=lambda x: abs(math.log(x / q)))
        if n != q:
            new_in[(rid, good)] = n

# R3 on every output that is still off a nice number, nudging to the nearest legal value.
for r in L:
    if r["recipe_id"] in STOICH_PINNED:
        continue
    for g, q in outs(r):
        cur = new_out.get((r["recipe_id"], g), q)
        if not nice(cur):
            cand = [x for x in range(max(1, cur - 4), cur + 5) if nice(x)]
            if cand:
                new_out[(r["recipe_id"], g)] = min(cand, key=lambda x: (abs(x - cur), x))

# R2 — every gated recipe onto the multiplier ladder against its same-building base.
# A function, not a one-shot pass: phase 4 may move a base output later, and a gated sibling
# left on its old quantity would then read as a research DOWNGRADE.
by_ob = defaultdict(list)
for r in L:
    o = outs(r)
    if o:
        by_ob[(o[0][0], bld(r))].append(r)


def enforce_r2():
    for (good, _b), rs in by_ob.items():
        bases = [r for r in rs if not (r.get("required_research") or "").strip()]
        gated = [r for r in rs if (r.get("required_research") or "").strip()]
        if not bases or not gated:
            continue
        bq = max(new_out.get((r["recipe_id"], good), dict(outs(r))[good]) for r in bases)
        for g in gated:
            if g["recipe_id"] in STOICH_PINNED:
                continue
            cur = new_out.get((g["recipe_id"], good), dict(outs(g))[good])
            opts = [(abs(math.log(max(1, round(m * bq)) / max(cur, 1))), max(1, round(m * bq)))
                    for m in GATED_MULT if nice(max(1, round(m * bq)))]
            if opts:
                new_out[(g["recipe_id"], good)] = min(opts)[1]


enforce_r2()

# Producer outputs are final only after R3 and R2; re-snap every consumer against the
# settled value, or the ladder is measured against a number that no longer exists.
for good, (prid, P0) in base_producer.items():
    P = new_out.get((prid, good), P0)
    legal = legal_for(P)
    for rid, q in consumers.get(good, []):
        cur = new_in.get((rid, good), q)
        n = min(legal, key=lambda x: abs(math.log(x / cur)))
        if n != q:
            new_in[(rid, good)] = n
        else:
            new_in.pop((rid, good), None)

print("PHASE 1 — quantities")
print("  base producers moved   : %d" % len({k[0] for k in new_out if any(
    k[0] == p for p, _ in base_producer.values())}))
print("  output changes         : %d" % len(new_out))
print("  input  changes         : %d" % len(new_in))
print("  stoichiometric recipes pinned: %s" % ", ".join(sorted(STOICH_PINNED)))


def eff_out(r):
    return [(g, new_out.get((r["recipe_id"], g), q)) for g, q in outs(r)]


def eff_in(r):
    return [(g, new_in.get((r["recipe_id"], g), q)) for g, q in ins(r)]


def standalone(r):
    """A recipe can only be costed standalone if it can buy every input and sell something.
    A grid service with no goods at all, or one needing an untradeable input, is neither a
    profit centre nor a solver failure — it is outside the band's scope."""
    if not any(g in SELLABLE for g, _ in eff_out(r)):
        return False
    return all(g in BUYABLE for g, _ in eff_in(r))


def net(r, price, mult=1.0):
    rev = sum(price[g] * q for g, q in eff_out(r) if g in SELLABLE)
    bill = sum(price[g] * q for g, q in eff_in(r))
    return rev - bill - float(r["energy_req"] or 0) * GRID - maint[bld(r)] - labour(r, mult)


price = dict(price0)
SA = [r for r in L if standalone(r)]
inb = sum(1 for r in SA if BAND[0] <= net(r, price) <= BAND[1])
print("  band fit on quantities alone: %d / %d" % (inb, len(SA)))
print("  outside band scope (no market for their goods): %d" % (len(L) - len(SA)))

# ============ PHASE 2 — prices ======================================================
# A price is revenue for its producer and cost for every consumer, so this is a system, not
# a per-recipe fix. Iterate: nudge each good's price toward what would centre its BASE
# producer in the band, damped, and re-evaluate. Goods with no live producer stay fixed.
producing = defaultdict(list)
for r in SA:
    for g, _ in eff_out(r):
        if g in SELLABLE:
            producing[g].append(r)
TARGET = sum(BAND) / 2
for it in range(400):
    moved = 0
    for good, prods in producing.items():
        anchor = next((r for r in prods if not (r.get("required_research") or "").strip()), prods[0])
        n = net(anchor, price)
        if BAND[0] <= n <= BAND[1]:
            continue
        q = dict(eff_out(anchor)).get(good, 0)
        if q <= 0:
            continue
        delta = (TARGET - n) / q          # price move that would centre this recipe
        newp = min(max(price0[good] * PRICE_FLOOR_MULT, price[good] + delta * 0.25),
                   price0[good] * PRICE_CEIL_MULT)
        if abs(newp - price[good]) > 1e-6:
            price[good] = newp
            moved += 1
    if not moved:
        break
inb = sum(1 for r in SA if BAND[0] <= net(r, price) <= BAND[1])
print("\nPHASE 2 — prices (%d iterations)" % (it + 1))
print("  band fit: %d / %d  (%.0f%%)" % (inb, len(SA), 100 * inb / len(SA)))

# ============ PHASE 3 — labour fine adjuster ========================================
lab_mult = {}
for r in SA:
    if BAND[0] <= net(r, price) <= BAND[1]:
        continue
    best = None
    for i in range(0, 61):
        m = 0.40 + 0.60 * i / 60
        n = net(r, price, m)
        cand = (BAND[0] <= n <= BAND[1], -abs(n - TARGET), m)
        if best is None or cand > best:
            best = cand
    if best[0]:
        lab_mult[r["recipe_id"]] = round(best[2], 4)
BASE_SA = [r for r in SA if not (r.get("required_research") or "").strip()]
print("\nPHASE 3 — labour 0.40-1.00x on %d recipes" % len(lab_mult))


def fin(r):
    return net(r, price, lab_mult.get(r["recipe_id"], 1.0))


for tag, rs in (("all standalone-costable", SA), ("BASE (game start)", BASE_SA)):
    inb = sum(1 for r in rs if BAND[0] <= fin(r) <= BAND[1])
    print("  %-24s %3d / %3d  (%.0f%%)" % (tag, inb, len(rs), 100 * inb / len(rs)))
print("  BASE still out of band:")
for r in sorted(BASE_SA, key=fin):
    if not BAND[0] <= fin(r) <= BAND[1]:
        print("    %-7s %-38s %+8.1f" % (r["recipe_id"], r["display_name"][:38], fin(r)))

# ============ PHASE 4 — output quantity, targeted ===================================
# Recipes that share an output good cannot be separated by price: one price serves them all.
# The four biomass routes differ only in their input structure, so the last free lever is each
# recipe's own output quantity. Moving a good's ANCHOR (its largest base producer) moves the
# rung every consumer is snapped to, so consumers are re-snapped whenever that happens.
def anchor_of(good):
    ps = [r for r in BASE if outs(r) and outs(r)[0][0] == good]
    if not ps:
        return None
    return max(ps, key=lambda r: new_out.get((r["recipe_id"], good), dict(outs(r))[good]))


moved4 = 0
for r in sorted(BASE_SA, key=fin):
    if BAND[0] <= fin(r) <= BAND[1]:
        continue
    g0, q0 = outs(r)[0][0], eff_out(r)[0][1]
    m = lab_mult.get(r["recipe_id"], 1.0)
    gated_sibs = anchor_of(g0) is r and any(
        (x.get("required_research") or "").strip() for x in by_ob.get((g0, bld(r)), []))
    best = None
    for q in range(1, max(4 * q0, 40) + 1):
        if not nice(q) or not legal_for(q):
            continue
        saved = new_out.get((r["recipe_id"], g0))
        new_out[(r["recipe_id"], g0)] = q
        n = net(r, price, m)
        if saved is None:
            new_out.pop((r["recipe_id"], g0), None)
        else:
            new_out[(r["recipe_id"], g0)] = saved
        r2ok = all(nice(max(1, round(m * q))) for m in GATED_MULT) if gated_sibs else True
        cand = (BAND[0] <= n <= BAND[1], r2ok, -abs(n - TARGET), -abs(math.log(q / q0)))
        if best is None or cand > best[0]:
            best = (cand, q, n)
    if best and best[0][0]:
        new_out[(r["recipe_id"], g0)] = best[1]
        moved4 += 1
        if anchor_of(g0) is r:                  # the rung moved; every consumer must follow
            P = best[1]
            legal = legal_for(P)
            for rid, q in consumers.get(g0, []):
                n2 = min(legal, key=lambda x: abs(math.log(x / q)))
                if n2 != q:
                    new_in[(rid, g0)] = n2
                else:
                    new_in.pop((rid, g0), None)

enforce_r2()
print("\nPHASE 4 — output quantity on %d stragglers" % moved4)
for tag, rs in (("all standalone-costable", SA), ("BASE (game start)", BASE_SA)):
    inb = sum(1 for r in rs if BAND[0] <= fin(r) <= BAND[1])
    print("  %-24s %3d / %3d  (%.0f%%)" % (tag, inb, len(rs), 100 * inb / len(rs)))
for r in sorted(BASE_SA, key=fin):
    if not BAND[0] <= fin(r) <= BAND[1]:
        print("    still out: %-7s %-34s %+8.1f" % (r["recipe_id"], r["display_name"][:34], fin(r)))

# ============ PHASE 5 — gated recipes must not be a downgrade ========================
# R2 forces a gated recipe to OUT-PRODUCE its base sibling; it says nothing about profit. All
# five traps here are recipes whose gross margin does not cover their energy and maintenance,
# so they satisfy R2 while making the player strictly poorer for unlocking the tech — a trap
# the structural rules cannot see. r_074 is the extreme: its inputs cost more than its output
# is worth, so it destroys value at any scale.
#
# The lever is the R2 multiplier itself. Moving a gated recipe from 1.0x to 1.5x its base
# output is both the fix and the correct meaning of research, and it cannot disturb the ratio
# ladder because rungs are measured against BASE producers only.
def base_sibling(r):
    g0 = outs(r)[0][0]
    return [b for b in L if not (b.get("required_research") or "").strip()
            and outs(b) and outs(b)[0][0] == g0 and bld(b) == bld(r)]


traps, fixed5 = 0, 0
for r in SA:
    if not (r.get("required_research") or "").strip():
        continue
    sibs = base_sibling(r)
    sib_net = max((net(b, price, lab_mult.get(b["recipe_id"], 1.0)) for b in sibs), default=None)
    floor = BAND[0] if sib_net is None else max(sib_net, BAND[0])
    if net(r, price, lab_mult.get(r["recipe_id"], 1.0)) >= floor:
        continue
    traps += 1
    g0 = outs(r)[0][0]
    saved = new_out.get((r["recipe_id"], g0))
    bq = (max(new_out.get((b["recipe_id"], g0), dict(outs(b))[g0]) for b in sibs) if sibs
          else eff_out(r)[0][1])
    best = None
    for m in GATED_MULT:
        q = max(1, round(m * bq))
        if not nice(q):
            continue
        new_out[(r["recipe_id"], g0)] = q
        for lm in [0.40 + 0.05 * k for k in range(13)]:
            n = net(r, price, lm)
            # the smallest multiplier that clears the floor, so research improves the recipe
            # without turning a marginal one into a windfall
            if n >= floor and (best is None or (m, -n) < (best[1], -best[2])):
                best = (q, m, n, lm)
    if saved is None:
        new_out.pop((r["recipe_id"], g0), None)
    else:
        new_out[(r["recipe_id"], g0)] = saved
    if best:
        new_out[(r["recipe_id"], g0)] = best[0]
        lab_mult[r["recipe_id"]] = round(best[3], 4)
        fixed5 += 1

print("\nPHASE 5 — %d research traps found, %d repaired" % (traps, fixed5))
for r in SA:
    if not (r.get("required_research") or "").strip():
        continue
    sibs = base_sibling(r)
    sib_net = max((net(b, price, lab_mult.get(b["recipe_id"], 1.0)) for b in sibs), default=None)
    floor = BAND[0] if sib_net is None else max(sib_net, BAND[0])
    n = net(r, price, lab_mult.get(r["recipe_id"], 1.0))
    if n < floor:
        print("    STILL A TRAP %-7s %-30s %+7.1f  (needs %+.1f)"
              % (r["recipe_id"], r["display_name"][:30], n, floor))

spec = {
    "prices": [{"good": g, "new": round(p, 4)} for g, p in sorted(price.items())
               if abs(p - price0[g]) > 0.005],
    "input_qty": [{"recipe": rid, "good": g, "new": q} for (rid, g), q in sorted(new_in.items())],
    "output_qty": [{"recipe": rid, "good": g, "new": q} for (rid, g), q in sorted(new_out.items())],
    "labour_mult": [{"recipe": rid, "mult": m} for rid, m in sorted(lab_mult.items())],
}
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(spec, indent=1))
print("\nwrote %s" % OUT)
print("  %d price, %d input, %d output, %d labour changes"
      % (len(spec["prices"]), len(spec["input_qty"]), len(spec["output_qty"]), len(spec["labour_mult"])))
