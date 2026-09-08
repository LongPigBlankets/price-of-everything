#!/usr/bin/env python3
"""Steel specialist P&L: current model (C) vs Model P + supply response (P+R).

Recipe r_076 (EAF): 21 iron_ingots + 5 hydrogen -> 54 steel, 140 energy.
Level scaling (building_levels.gd): OUT x1/2/3.5, INPUT x1/2/3, ENERGY x1/1.8/2.5,
LABOUR x1/1.5/2 (L1 cost from recipe staffing 1356/515/51 x engine wage rates
0.002/0.006/0.010 = 6.31/turn), MAINT x1/1.8/2.5 (5 x MAINTENANCE_MULTIPLIER 2 = 10/turn L1).
Revenue nets the seaport ad valorem (0.5% t<31, 3% after). Inputs bought just-in-time
at market buy price (x1.05). Player impacts BOTH sides in both models.
Baseline = same P&L at impact-free decayed base prices.
"""
import json, math, statistics
from collections import defaultdict

import os
ROOT = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(f"{ROOT}/npc_market_dump.json"))
STEP, MAX_TURN, R_CT = D["turn_step"], D["max_turn"], D["rival_count"]
goods = {g["id"]: g for g in D["goods"]}
by_name = {g["internal_name"]: g for g in D["goods"]}
producible = [gid for gid, g in goods.items() if g["goods_graph_tier"] != "apex" and g["base_output"] > 0]
BETA, C_THR, SPEED, EMA_N = 0.75, 0.6, 0.5, 5
BAND_EDGES = [(10, 40.0), (4, 30.0), (2, 20.0), (1, 10.0)]
OUT_M = {1: 1.0, 2: 2.0, 3: 3.5}; IN_M = {1: 1.0, 2: 2.0, 3: 3.0}
EN_M = {1: 1.0, 2: 1.8, 3: 2.5}; LAB_M = {1: 1.0, 2: 1.5, 3: 2.0}; MAINT_M = {1: 1.0, 2: 1.8, 3: 2.5}
MARKUP, GRID = 0.05, 0.12
LABOUR_L1 = 1356 * 0.002 + 515 * 0.006 + 51 * 0.010   # 6.31
MAINT_L1 = 5 * 2.0
STEEL = by_name["steel"]["id"]; II = by_name["iron_ingots"]["id"]; H2 = by_name["hydrogen"]["id"]
RATES_C = [(10, 0.5), (4, 0.2), (2, 0.1), (1, 0.05)]

def gamma(t): return 1.0 + 0.425 * (t // 5)
def adval(t): return 0.005 if t < 31 else 0.03

def levels_at():
    levels = []; events = {10: "build", 30: "up", 60: "up", 70: "build"}
    t = 75
    while t <= 300:
        events[t] = "auto"; t += 5
    out = []
    for t in range(MAX_TURN + 1):
        if t in events:
            k = events[t]
            if k == "build": levels.append(1)
            elif k == "up": levels[-1] += 1
            else:
                if levels and levels[-1] < 3: levels[-1] += 1
                else: levels.append(1)
        out.append(list(levels))
    return out

LV = levels_at()
def caps(t):
    lv = LV[t]
    return (sum(54 * OUT_M[l] for l in lv), sum(21 * IN_M[l] for l in lv), sum(5 * IN_M[l] for l in lv),
            sum(140 * EN_M[l] for l in lv), sum(LABOUR_L1 * LAB_M[l] for l in lv), sum(MAINT_L1 * MAINT_M[l] for l in lv))

def dec_price(gid, t):
    g = goods[gid]
    return g["base_price"] * ((1 - g["decay_rate"]) ** max(0, t - 29))

# ---- model C impacts: player-only, static thresholds, accumulate, recover ----
def sim_C():
    imp = {STEEL: 0.0, II: 0.0, H2: 0.0}
    traj = {k: [] for k in imp}
    for t in range(MAX_TURN + 1):
        out_u, in_ii, in_h2, *_ = caps(t)
        for gid, net in [(STEEL, out_u), (II, -in_ii), (H2, -in_h2)]:
            base = goods[gid]["base_output"]
            v = abs(net); rate = 0.0
            for m, r_ in RATES_C:
                if v > m * base: rate = r_; break
            a = imp[gid]
            if rate > 0: a += -rate if net > 0 else rate
            else: a = a - math.copysign(min(0.1, abs(a)), a) if a != 0 else 0.0
            imp[gid] = max(-40.0, min(40.0, a))
            traj[gid].append(imp[gid])
    return traj

# ---- model P + response: coupled, player on both sides ----
def sim_PR(seed):
    consumers = defaultdict(list); inputs_of = {}
    for gid in producible:
        g = goods[gid]; oq = g["base_recipe_output_qty"]
        inputs_of[gid] = []
        if oq <= 0: continue
        for inp in g["base_recipe_inputs"]:
            consumers[inp["good_id"]].append((gid, inp["qty"] / oq))
            inputs_of[gid].append((inp["good_id"], inp["qty"]))
    inc = {gid: [[D["rivals"][str(seed)][gid][i][b] - D["rivals"][str(seed)][gid][i][b - 1]
                  for b in range(1, 61)] for i in range(R_CT)] for gid in producible}
    q = {gid: [goods[gid]["base_output"]] * R_CT for gid in producible}
    imp = defaultdict(float); ema = {}
    traj = defaultdict(list)
    def gmult(gid):
        g_out = 1.0
        d = imp.get(gid, 0.0)
        if d >= 10: g_out = 1.5
        elif d <= -10: g_out = 0.75
        g_in = 1.0
        ins = inputs_of.get(gid, [])
        if ins:
            ws = dv = 0.0
            for j, qty in ins:
                pj = goods[j]["base_price"] * (1 + imp.get(j, 0.0) / 100)
                ws += pj * qty; dv += pj * qty * imp.get(j, 0.0) / 100
            if ws > 0:
                dv /= ws
                if dv <= -0.25: g_in = 2.0
                elif dv >= 0.25: g_in = 0.5
        return max(0.25, min(2.5, g_in * g_out))
    for t in range(MAX_TURN + 1):
        if t > 0 and t % STEP == 0:
            b = t // STEP - 1
            for gid in producible:
                G = gmult(gid)
                for i in range(R_CT):
                    if b < len(inc[gid][i]):
                        q[gid][i] += int(round(inc[gid][i][b] * G))
        sold = {gid: sum(q[gid]) for gid in producible}
        bought = defaultdict(float)
        for j, cons in consumers.items():
            for cgid, pu in cons:
                bought[j] += sold.get(cgid, 0) * pu
        out_u, in_ii, in_h2, *_ = caps(t)
        pnet = {STEEL: out_u, II: -in_ii, H2: -in_h2}
        for gid, g in goods.items():
            base = g["base_output"]
            if base <= 0:
                traj[gid].append(0.0); continue
            net = pnet.get(gid, 0) + (1 - BETA) * (sold.get(gid, 0) - bought.get(gid, 0.0))
            T = max(base, C_THR * base * gamma(t))
            r = net / T
            ema[gid] = r if gid not in ema else ema[gid] + (r - ema[gid]) / EMA_N
            e = ema[gid]
            tgt = 0.0
            if abs(e) > 1:
                for m, tg in BAND_EDGES:
                    if abs(e) > m: tgt = tg * (-1 if e > 0 else 1); break
            imp[gid] += max(-SPEED, min(SPEED, tgt - imp[gid]))
            traj[gid].append(imp[gid])
    return traj

def pnl(imp_of):
    """imp_of(gid, t) -> impact %. Returns profit/turn series + cumulative."""
    prof = []
    cum = 0.0; cums = []
    for t in range(MAX_TURN + 1):
        out_u, in_ii, in_h2, en, lab, mnt = caps(t)
        rev = out_u * dec_price(STEEL, t) * (1 + imp_of(STEEL, t) / 100) * (1 - adval(t))
        cost = (in_ii * dec_price(II, t) * (1 + imp_of(II, t) / 100) * (1 + MARKUP)
                + in_h2 * dec_price(H2, t) * (1 + imp_of(H2, t) / 100) * (1 + MARKUP)
                + en * GRID + lab + mnt)
        p = rev - cost
        prof.append(p); cum += p; cums.append(cum)
    return prof, cums

seeds = list(D["rivals"].keys())
cT = sim_C()
pr_runs = [sim_PR(s) for s in seeds]
def pr_imp(gid, t): return statistics.mean(r[gid][t] for r in pr_runs)

prof_base, cum_base = pnl(lambda g, t: 0.0)
prof_C, cum_C = pnl(lambda g, t: cT[g][t] if g in cT else 0.0)
prof_PR, cum_PR = pnl(pr_imp)

CPS = [30, 60, 100, 150, 200, 250, 300]
print("STEEL SPECIALIST P&L (per-turn profit £):")
print("  turn:      " + "".join(f"{c:>9}" for c in CPS))
print("  baseline:  " + "".join(f"{prof_base[c]:>9.0f}" for c in CPS))
print("  C current: " + "".join(f"{prof_C[c]:>9.0f}" for c in CPS))
print("  P+resp:    " + "".join(f"{prof_PR[c]:>9.0f}" for c in CPS))
print("\n  impacts driving it (C):  steel " + "".join(f"{cT[STEEL][c]:>7.1f}" for c in CPS))
print("                          ingots " + "".join(f"{cT[II][c]:>7.1f}" for c in CPS))
print("                        hydrogen " + "".join(f"{cT[H2][c]:>7.1f}" for c in CPS))
print("  impacts (P+R):           steel " + "".join(f"{pr_imp(STEEL, c):>7.1f}" for c in CPS))
print("                          ingots " + "".join(f"{pr_imp(II, c):>7.1f}" for c in CPS))
print("                        hydrogen " + "".join(f"{pr_imp(H2, c):>7.1f}" for c in CPS))
print(f"\nCUMULATIVE t300:  baseline £{cum_base[300]:,.0f}   C £{cum_C[300]:,.0f} ({100*cum_C[300]/cum_base[300]:.0f}%)   "
      f"P+R £{cum_PR[300]:,.0f} ({100*cum_PR[300]/cum_base[300]:.0f}%)")
# expansion still pays? profit before/after each build step under P+R
print("\nP+R: profit/turn around expansion steps (t-1 -> t+14):")
for t0 in [70, 100, 145, 190]:
    print(f"  t{t0}: {prof_PR[t0-1]:>7.0f} -> {prof_PR[min(t0+14,300)]:>7.0f}")

json.dump({"prof_base": [round(x, 1) for x in prof_base],
           "prof_C": [round(x, 1) for x in prof_C],
           "prof_PR": [round(x, 1) for x in prof_PR],
           "cum": {"base": round(cum_base[300]), "C": round(cum_C[300]), "PR": round(cum_PR[300])}},
          open(f"{ROOT}/profit_steel.json", "w"))
print("\nwrote profit_steel.json")
