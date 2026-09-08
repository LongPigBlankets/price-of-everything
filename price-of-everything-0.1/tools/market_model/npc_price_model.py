#!/usr/bin/env python3
"""Model: what happens to prices if rival (competitors' panel) production hits the market.

Scenario A: 100% of rival output counted as sold-to-market; the inputs needed to
            make it (base recipe, scaled proportionally) counted as bought.
Scenario B: 50% sold / 50% 'used' (vanishes); input buys scale with the sold half.

Impact model = the LIVE engine model (economy_config.gd / market_state.gd):
  net volume vs base_output bands  >1x:0.05  >2x:0.1  >4x:0.2  >10x:0.5  %/turn
  accumulate, cap +/-40, recover 0.1/turn when |net| <= 1x base.
"""
import json, math, statistics
from collections import defaultdict

import os
ROOT = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(f"{ROOT}/npc_market_dump.json"))

CFG = D["config"]
CAP = CFG["PRICE_IMPACT_CAP_PCT"]
REC = CFG["PRICE_IMPACT_RECOVERY_PCT"]
RATES = [(10.0, CFG["RATE_10X"]), (4.0, CFG["RATE_4X"]), (2.0, CFG["RATE_2X"]), (1.0, CFG["RATE_1X"])]
STEP = D["turn_step"]; MAX_TURN = D["max_turn"]; R = D["rival_count"]

goods = {g["id"]: g for g in D["goods"]}
producible = [gid for gid, g in goods.items()
              if g["goods_graph_tier"] != "apex" and g["base_output"] > 0]

# input coefficient per unit of output: A[j][g] = qty_j / out_qty  (base recipe of g)
A = defaultdict(dict)
for gid, g in goods.items():
    oq = g["base_recipe_output_qty"]
    if oq <= 0:
        continue
    for inp in g["base_recipe_inputs"]:
        j = inp["good_id"]
        A[j][gid] = A[j].get(gid, 0.0) + inp["qty"] / oq

def rate_for(net, base):
    if base <= 0:
        return 0.0
    v = abs(net)
    for mult, r in RATES:
        if v > mult * base:
            return r
    return 0.0

# ---------- structural net position (expectation, growth factor cancels) ----------
# E[q_i(g,t)] = base_g * gamma(t); nu_j = R*(base_j - sum_g A[j,g]*base_g)
nu = {}
for gid, g in goods.items():
    sold = g["base_output"] if gid in producible else 0
    bought = sum(coeff * goods[cg]["base_output"] for cg, coeff in A.get(gid, {}).items()
                 if cg in producible)
    nu[gid] = R * (sold - bought)

print("=" * 100)
print("STRUCTURAL NET POSITION nu_j = rivals x (base_output_j - sum inputs consumed by rival base batches)")
print("  (expected NET market volume at t=0 under scenario A; grows x gamma(t)=1+0.425*floor(t/5))")
print("=" * 100)
rows = []
for gid, g in goods.items():
    if g["base_output"] <= 0 and abs(nu[gid]) < 1e-9:
        continue
    base = g["base_output"]
    ratio = nu[gid] / base if base > 0 else float("inf")
    rows.append((gid, g["internal_name"], g["goods_graph_tier"], base, nu[gid], ratio))
rows.sort(key=lambda r: (r[5] if r[3] > 0 else -999))
print(f"{'good':<26}{'tier':<10}{'base':>6}{'nu (net units/turn)':>20}{'nu/base':>10}")
for gid, name, tier, base, n, ratio in rows:
    tag = ""
    if base > 0:
        if ratio > 1: tag = "  << GLUT band from t0"
        elif ratio < -1: tag = "  << DEFICIT band from t0"
    print(f"{name:<26}{tier:<10}{base:>6}{n:>20.1f}{ratio:>10.2f}{tag}")

# ---------- full stochastic simulation ----------
def q_at(seed, gid, i, t):
    return D["rivals"][str(seed)][gid][i][t // STEP]

def simulate(alpha_out, alpha_in, seed):
    """Returns impact trajectory {gid: [pct at t=0..300]}."""
    imp = defaultdict(float)
    traj = defaultdict(list)
    for t in range(0, MAX_TURN + 1):
        sold = defaultdict(float); bought = defaultdict(float)
        for gid in producible:
            tot = sum(q_at(seed, gid, i, t) for i in range(R))
            sold[gid] += alpha_out * tot
            oq = goods[gid]["base_recipe_output_qty"]
            if oq > 0:
                for inp in goods[gid]["base_recipe_inputs"]:
                    bought[inp["good_id"]] += alpha_in * tot * inp["qty"] / oq
        for gid, g in goods.items():
            base = g["base_output"]
            if base <= 0:
                traj[gid].append(0.0); continue
            net = sold.get(gid, 0.0) - bought.get(gid, 0.0)
            r = rate_for(net, base)
            a = imp[gid]
            if r > 0.0:
                a += -r if net > 0 else r
            else:
                a = a - math.copysign(min(REC, abs(a)), a) if a != 0 else 0.0
            a = max(-CAP, min(CAP, a))
            imp[gid] = a
            traj[gid].append(a)
    return traj

def summarize(name, trajs):
    print("\n" + "=" * 100)
    print(f"SCENARIO {name}  (mean over {len(trajs)} seeds)")
    print("=" * 100)
    checkpoints = [30, 60, 100, 200, 300]
    mean_traj = {}
    for gid in goods:
        mean_traj[gid] = [statistics.mean(tr[gid][t] for tr in trajs) for t in range(MAX_TURN + 1)]
    print(f"{'good':<26}{'base':>6}" + "".join(f"{'t'+str(c):>9}" for c in checkpoints))
    order = sorted((gid for gid in goods if goods[gid]['base_output'] > 0),
                   key=lambda g: mean_traj[g][MAX_TURN])
    for gid in order:
        g = goods[gid]
        vals = "".join(f"{mean_traj[gid][c]:>9.1f}" for c in checkpoints)
        print(f"{g['internal_name']:<26}{g['base_output']:>6}{vals}")
    # aggregates
    for c in checkpoints:
        at = [mean_traj[g][c] for g in goods if goods[g]["base_output"] > 0]
        pinned_dn = sum(1 for v in at if v <= -CAP + 0.5)
        pinned_up = sum(1 for v in at if v >= CAP - 0.5)
        quiet = sum(1 for v in at if abs(v) < 2.0)
        print(f"t{c:<4} goods:{len(at)}  pinned -{CAP:.0f}%:{pinned_dn}  pinned +{CAP:.0f}%:{pinned_up}  "
              f"|impact|<2%:{quiet}  median:{statistics.median(at):+.1f}%  "
              f"mean|.|:{statistics.mean(abs(v) for v in at):.1f}%")
    return mean_traj

seeds = list(D["rivals"].keys())
tA = [simulate(1.0, 1.0, s) for s in seeds]
tB = [simulate(0.5, 0.5, s) for s in seeds]
mA = summarize("A: 100% sold + inputs bought", tA)
mB = summarize("B: 50% sold / 50% used (inputs at 50%)", tB)

json.dump({
    "nu": {goods[g]["internal_name"]: nu[g] for g in goods},
    "base": {goods[g]["internal_name"]: goods[g]["base_output"] for g in goods},
    "tier": {goods[g]["internal_name"]: goods[g]["goods_graph_tier"] for g in goods},
    "price": {goods[g]["internal_name"]: goods[g]["base_price"] for g in goods},
    "meanA": {goods[g]["internal_name"]: mA[g] for g in goods},
    "meanB": {goods[g]["internal_name"]: mB[g] for g in goods},
    "seedA0": {goods[g]["internal_name"]: tA[0][g] for g in goods},
}, open(f"{ROOT}/scenario_results.json", "w"))
print("\nwrote scenario_results.json")
