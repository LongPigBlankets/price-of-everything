#!/usr/bin/env python3
"""Apply a rebalance change set to the live CSVs and CHECK it against the four structural rules.

    python3 -B tools/apply_rebalance.py changes.json [--dry-run]

changes.json:
    {
      "prices":      [{"good": "glass",  "new": 2.40, "why": "..."}],
      "input_qty":   [{"recipe": "r_056", "good": "glass", "new": 24, "why": "..."}],
      "output_qty":  [{"recipe": "r_054", "good": "glass", "new": 30, "why": "..."}],
      "labour_mult": [{"recipe": "r_056", "mult": 0.75, "why": "..."}]
    }

Nothing is written unless every rule check passes, so a bad change set fails loudly instead of
half-applying. --dry-run reports the checks and the projected band fit without touching anything.

THE FOUR RULES (owner spec 2026-07-28), enforced here rather than trusted:
  R1 one base producer building must meet one consumer building's per-turn need
  R2 a gated recipe makes exactly 1.0 / 1.2 / 1.5 / 2.0x its base recipe's output, never less
  R3 every output quantity is a multiple of 3, 4 or 5
  R4 (advisory) chemistry recipes stay near stoichiometric — flagged, not enforced, because the
     ideal ratio is not derivable from the CSVs alone
"""
import csv
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DRY = "--dry-run" in sys.argv
SPEC = json.loads(Path(sys.argv[1]).read_text())

RU, RS, RH, GRID = 0.00304, 0.00912, 0.0304, 0.12
MAX_IN, MAX_OUT = 6, 5
BAND_STANDALONE = (15.0, 40.0)

goods_rows = list(csv.reader(open(ROOT / "data/Goods - goodsMVP.csv")))
build_rows = list(csv.reader(open(ROOT / "data/Buildings - buildingsMVP.csv")))
rec_rows = list(csv.reader(open(ROOT / "data/recipes_all.csv")))
GH, BH, RH_ = goods_rows[0], build_rows[0], rec_rows[0]

price = {r[GH.index("internal_name")]: float(r[GH.index("base_price")] or 0)
         for r in goods_rows[1:] if len(r) > GH.index("base_price")}
maint = {r[BH.index("internal_name")]: float(r[BH.index("maintenance_cost")] or 0)
         for r in build_rows[1:] if len(r) > BH.index("maintenance_cost")}
building_names = set(maint)
# Revenue counts SELLABLE outputs only, and a recipe needing an unbuyable input cannot be
# costed standalone at all. waste_water is both, so a producer must not be paid for effluent.
SELLABLE = {r[GH.index("internal_name")] for r in goods_rows[1:]
            if len(r) > GH.index("is_sellable") and r[GH.index("is_sellable")].strip().upper() == "TRUE"}
BUYABLE = {r[GH.index("internal_name")] for r in goods_rows[1:]
           if len(r) > GH.index("is_buyable") and r[GH.index("is_buyable")].strip().upper() == "TRUE"}

# catalog.gd BUILDING_ALIAS — recipes name a few buildings by an older internal name.
import re
alias_src = (ROOT / "scripts/catalog.gd").read_text()
_m = re.search(r"const BUILDING_ALIAS := \{(.*?)\n\}", alias_src, re.S)
ALIAS = dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', _m.group(1))) if _m else {}


def col(h, name):
    return h.index(name)


def recipe_dicts():
    return [dict(zip(RH_, r)) for r in rec_rows[1:] if r and r[0]]


def is_live(r):
    b = ALIAS.get(r["building_id"], r["building_id"])
    if b not in building_names:
        return False
    for i in range(1, MAX_IN + 1):
        n = (r.get("input_%d" % i) or "").strip()
        if n and n not in price:
            return False
    for i in range(1, MAX_OUT + 1):
        n = (r.get("output_%d" % i) or "").strip()
        if n and n not in price:
            return False
    return True


def net_of(r):
    b = ALIAS.get(r["building_id"], r["building_id"])
    rev = sum(price[r["output_%d" % i]] * int(r["output_qty_%d" % i])
              for i in range(1, MAX_OUT + 1)
              if (r.get("output_%d" % i) or "").strip() in SELLABLE and (r.get("output_qty_%d" % i) or "").strip())
    inp = sum(price[r["input_%d" % i]] * int(r["qty_%d" % i])
              for i in range(1, MAX_IN + 1)
              if (r.get("input_%d" % i) or "").strip() and (r.get("qty_%d" % i) or "").strip())
    lab = (int(r["labour_unskilled_required"] or 0) * RU
           + int(r["labour_skilled_required"] or 0) * RS
           + int(r["labour_h_skilled_required"] or 0) * RH)
    return rev - inp - float(r["energy_req"] or 0) * GRID - maint.get(b, 0) - lab


# ---- apply the spec in memory -------------------------------------------------------
for e in SPEC.get("prices", []):
    if e["good"] not in price:
        sys.exit("price change names an unknown good: %s" % e["good"])
    price[e["good"]] = float(e["new"])

recs = {r["recipe_id"]: r for r in recipe_dicts()}
for e in SPEC.get("input_qty", []):
    r = recs.get(e["recipe"]) or sys.exit("unknown recipe %s" % e["recipe"])
    for i in range(1, MAX_IN + 1):
        if (r.get("input_%d" % i) or "").strip() == e["good"]:
            r["qty_%d" % i] = str(int(e["new"]))
            break
    else:
        sys.exit("%s does not consume %s" % (e["recipe"], e["good"]))
for e in SPEC.get("output_qty", []):
    r = recs.get(e["recipe"]) or sys.exit("unknown recipe %s" % e["recipe"])
    for i in range(1, MAX_OUT + 1):
        if (r.get("output_%d" % i) or "").strip() == e["good"]:
            r["output_qty_%d" % i] = str(int(e["new"]))
            break
    else:
        sys.exit("%s does not produce %s" % (e["recipe"], e["good"]))
for e in SPEC.get("labour_mult", []):
    r = recs.get(e["recipe"]) or sys.exit("unknown recipe %s" % e["recipe"])
    m = float(e["mult"])
    if not 0.40 - 1e-9 <= m <= 1.0 + 1e-9:
        sys.exit("labour mult for %s outside 0.40-1.00: %s" % (e["recipe"], m))
    for c, floor in (("labour_unskilled_required", 500), ("labour_skilled_required", 100),
                     ("labour_h_skilled_required", 50)):
        orig = int(r[c] or 0)
        r[c] = str(max(min(orig, floor), round(orig * m)))

live = [r for r in recs.values() if is_live(r)]

# ---- rule checks --------------------------------------------------------------------
problems = []

# R3 nice numbers
for r in live:
    for i in range(1, MAX_OUT + 1):
        q = (r.get("output_qty_%d" % i) or "").strip()
        if q and int(q) % 3 and int(q) % 4 and int(q) % 5:
            problems.append("R3 %s outputs %s %s — not a multiple of 3, 4 or 5"
                            % (r["recipe_id"], q, r["output_%d" % i]))

# R2 gated multipliers
by_out = defaultdict(list)
for r in live:
    o = (r.get("output_1") or "").strip()
    if o:
        by_out[o].append(r)
# R2 compares a gated recipe against the BASE RECIPE IT UPGRADES — same good AND same building.
# Grouping by good alone would compare an onshore wind farm to a coal plant, which is a different
# technology rather than a research upgrade of it.
by_out_bld = defaultdict(list)
for r in live:
    o = (r.get("output_1") or "").strip()
    if o:
        by_out_bld[(o, ALIAS.get(r["building_id"], r["building_id"]))].append(r)
for (good, _bld), rs in by_out_bld.items():
    base = [r for r in rs if not (r.get("required_research") or "").strip()]
    gated = [r for r in rs if (r.get("required_research") or "").strip()]
    if not base or not gated:
        continue
    b_out = max(int(r["output_qty_1"]) for r in base)
    for g in gated:
        ratio = int(g["output_qty_1"]) / b_out
        if ratio < 1.0 - 0.02:
            problems.append("R2 %s (%s) makes %.2fx the base — research must not downgrade"
                            % (g["recipe_id"], good, ratio))
        elif not any(abs(ratio - t) <= 0.02 for t in (1.0, 1.2, 1.5, 2.0)):
            problems.append("R2 %s (%s) makes %.2fx the base — not 1.0/1.2/1.5/2.0"
                            % (g["recipe_id"], good, ratio))

# RATIO — consumer_demand / producer_supply must sit on the ladder (owner spec 2026-07-28).
# A consumer needing 33 against a producer making 100 is the 0.33x case.
LADDER = [0.33, 0.5, 0.75, 1.0, 1.2, 1.5, 2.0]
for good, rs in by_out.items():
    base = [r for r in rs if not (r.get("required_research") or "").strip()]
    if not base:
        continue
    b_out = max(int(r["output_qty_1"]) for r in base)
    if b_out <= 0:
        continue
    for r in live:
        for i in range(1, MAX_IN + 1):
            if (r.get("input_%d" % i) or "").strip() == good:
                need = int(r["qty_%d" % i] or 0)
                ratio = need / b_out
                if not any(abs(ratio - a) <= 0.04 for a in LADDER):
                    problems.append("RATIO %s needs %d %s against a producer making %d = %.2fx"
                                    % (r["recipe_id"], need, good, b_out, ratio))

def costable(r):
    outs_ok = any((r.get("output_%d" % i) or "").strip() in SELLABLE for i in range(1, MAX_OUT + 1))
    ins_ok = all((r.get("input_%d" % i) or "").strip() in BUYABLE
                 for i in range(1, MAX_IN + 1) if (r.get("input_%d" % i) or "").strip())
    return outs_ok and ins_ok


# TRAP — a gated recipe must not lose to the best BASE route for the same good.
# Scoped by GOOD, not by good-and-building: R2 only compares within a building, so a gated
# recipe in a NEW building can be worse than the base route it actually competes with and
# still pass every structural check. That is how five research traps survived the first solve,
# and how r_206 Electric Heavy Vehicles stayed hidden after them.
#
# Some recipes are deliberately uneconomic — an owner design call, not a defect. They are named
# here so the exemption is explicit and reviewable rather than the test being silently loose.
DELIBERATELY_UNECONOMIC = {
    "r_131": "hydrogen power is a decarbonisation choice, not a profitable one (owner, 2026-07-28)",
}


def out1(r):
    return (r.get("output_1") or "").strip()


for r in live:
    if not (r.get("required_research") or "").strip() or r["recipe_id"] in DELIBERATELY_UNECONOMIC:
        continue
    if not costable(r):
        continue
    rivals = [b for b in live if out1(b) == out1(r) and costable(b)
              and not (b.get("required_research") or "").strip()]
    if not rivals:
        continue
    best = max(rivals, key=net_of)
    if net_of(r) < net_of(best) - 0.01:
        problems.append("TRAP %s (%s) earns %+.1f but base %s earns %+.1f — research makes you poorer"
                        % (r["recipe_id"], out1(r), net_of(r), best["recipe_id"], net_of(best)))

base_live = [r for r in live if costable(r) and not (r.get("required_research") or "").strip()]
bn = sorted(net_of(r) for r in base_live)
print("BASE (game start, standalone-costable): %d / %d in +%.0f..+%.0f  (%.0f%%)"
      % (sum(1 for n in bn if BAND_STANDALONE[0] <= n <= BAND_STANDALONE[1]), len(bn),
         *BAND_STANDALONE, 100 * sum(1 for n in bn if BAND_STANDALONE[0] <= n <= BAND_STANDALONE[1]) / len(bn)))
nets = sorted(net_of(r) for r in live if costable(r))
inb = sum(1 for n in nets if BAND_STANDALONE[0] <= n <= BAND_STANDALONE[1])
print("PROJECTED: %d / %d live recipes in +%.0f..+%.0f  (%.0f%%)"
      % (inb, len(live), *BAND_STANDALONE, 100 * inb / len(live)))
print("  median net %+.1f   below %d   above %d"
      % (nets[len(nets) // 2], sum(1 for n in nets if n < BAND_STANDALONE[0]),
         sum(1 for n in nets if n > BAND_STANDALONE[1])))
if problems:
    print("\nRULE VIOLATIONS (%d) — nothing written:" % len(problems))
    for p in problems:
        print("  " + p)
    if len(problems) > 40:
        print("  ... and %d more" % (len(problems) - 40))
    sys.exit(1)
print("\nall rule checks passed (ratio ladder, R2 multipliers, R3 nice numbers, no research traps)")
for _rid, _why in DELIBERATELY_UNECONOMIC.items():
    print("  trap-check exemption: %s — %s" % (_rid, _why))

if DRY:
    print("--dry-run: nothing written")
    sys.exit(0)

# ---- write ---------------------------------------------------------------------------
gi, gp = GH.index("internal_name"), GH.index("base_price")
for r in goods_rows[1:]:
    if len(r) > gp and r[gi] in price:
        r[gp] = "%.6g" % price[r[gi]]
csv.writer(open(ROOT / "data/Goods - goodsMVP.csv", "w", newline="")).writerows(goods_rows)

out = [RH_]
for r in rec_rows[1:]:
    if r and r[0] in recs:
        out.append([recs[r[0]].get(c, "") for c in RH_])
    elif r:
        out.append(r)
csv.writer(open(ROOT / "data/recipes_all.csv", "w", newline="")).writerows(out)
print("written: goods prices + recipe quantities/labour")
