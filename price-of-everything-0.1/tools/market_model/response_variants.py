#!/usr/bin/env python3
"""Response-strength variants on Model P:

R1 (Plate X):    out >=+10 -> x1.5 | <=-10 -> x0.75      in <=-25% -> x2.0 | >=+25% -> x0.5
R2 (strong out): out >=+10 -> x2.0 | <=-10 -> x0.5       in unchanged
R3 (R2 + half steps):
                 out >=+10 -> x2.0 | +5..10 -> x1.5 | -5..-10 -> x0.75 | <=-10 -> x0.5
                 in  <=-25 -> x2.0 | -12..-25 -> x1.5 | +12..+25 -> x0.75 | >=+25 -> x0.5
G = clamp(G_in * G_out, 0.25, 2.5). Everything else = Model P.

Suite per variant: ambient stats + steel/solar arcs; steel specialist (sells steel,
buys 21 ingots + 5 H2 per batch, level-scaled); specialist P&L (Plate XII cost model).
"""
import json, math, statistics
from collections import defaultdict, Counter

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
LABOUR_L1 = 1356 * 0.002 + 515 * 0.006 + 51 * 0.010
MAINT_L1 = 10.0
STEEL, II, H2 = by_name["steel"]["id"], by_name["iron_ingots"]["id"], by_name["hydrogen"]["id"]

VARIANTS = {
    "R1": {"out_pos": [(10, 1.5)], "out_neg": [(-10, 0.75)],
           "in_pos": [(0.25, 0.5)], "in_neg": [(-0.25, 2.0)]},
    "R2": {"out_pos": [(10, 2.0)], "out_neg": [(-10, 0.5)],
           "in_pos": [(0.25, 0.5)], "in_neg": [(-0.25, 2.0)]},
    "R3": {"out_pos": [(10, 2.0), (5, 1.5)], "out_neg": [(-10, 0.5), (-5, 0.75)],
           "in_pos": [(0.25, 0.5), (0.12, 0.75)], "in_neg": [(-0.25, 2.0), (-0.12, 1.5)]},
}

def gamma(t): return 1.0 + 0.425 * (t // 5)
def adval(t): return 0.005 if t < 31 else 0.03

def step(d, pos, neg):
    for thr, m in pos:
        if d >= thr: return m
    for thr, m in neg:
        if d <= thr: return m
    return 1.0

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

consumers = defaultdict(list); inputs_of = {}
for gid in producible:
    g = goods[gid]; oq = g["base_recipe_output_qty"]
    inputs_of[gid] = []
    if oq <= 0: continue
    for inp in g["base_recipe_inputs"]:
        consumers[inp["good_id"]].append((gid, inp["qty"] / oq))
        inputs_of[gid].append((inp["good_id"], inp["qty"]))

def run(seed, cfg, with_player):
    inc = {gid: [[D["rivals"][str(seed)][gid][i][b] - D["rivals"][str(seed)][gid][i][b - 1]
                  for b in range(1, 61)] for i in range(R_CT)] for gid in producible}
    q = {gid: [goods[gid]["base_output"]] * R_CT for gid in producible}
    imp = defaultdict(float); ema = {}
    traj = defaultdict(list); g_used = defaultdict(list)
    def gmult(gid):
        g_out = step(imp.get(gid, 0.0), cfg["out_pos"], cfg["out_neg"])
        g_in = 1.0
        ins = inputs_of.get(gid, [])
        if ins:
            ws = dv = 0.0
            for j, qty in ins:
                pj = goods[j]["base_price"] * (1 + imp.get(j, 0.0) / 100)
                ws += pj * qty; dv += pj * qty * imp.get(j, 0.0) / 100
            if ws > 0:
                g_in = step(dv / ws, cfg["in_pos"], cfg["in_neg"])
        return max(0.25, min(2.5, g_in * g_out))
    for t in range(MAX_TURN + 1):
        if t > 0 and t % STEP == 0:
            b = t // STEP - 1
            for gid in producible:
                G = gmult(gid)
                g_used[gid].append(G)
                for i in range(R_CT):
                    if b < len(inc[gid][i]):
                        q[gid][i] += int(round(inc[gid][i][b] * G))
        sold = {gid: sum(q[gid]) for gid in producible}
        bought = defaultdict(float)
        for j, cons in consumers.items():
            for cgid, pu in cons:
                bought[j] += sold.get(cgid, 0) * pu
        pnet = {}
        if with_player:
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
    return traj, g_used

def dec_price(gid, t):
    g = goods[gid]
    return g["base_price"] * ((1 - g["decay_rate"]) ** max(0, t - 29))

def pnl(imp_of):
    cum = 0.0; prof = []
    for t in range(MAX_TURN + 1):
        out_u, in_ii, in_h2, en, lab, mnt = caps(t)
        rev = out_u * dec_price(STEEL, t) * (1 + imp_of(STEEL, t) / 100) * (1 - adval(t))
        cost = (in_ii * dec_price(II, t) * (1 + imp_of(II, t) / 100) * (1 + MARKUP)
                + in_h2 * dec_price(H2, t) * (1 + imp_of(H2, t) / 100) * (1 + MARKUP)
                + en * GRID + lab + mnt)
        p = rev - cost; prof.append(p); cum += p
    return prof, cum

seeds = list(D["rivals"].keys())
CPS = [50, 100, 150, 200, 250, 300]
base_prof, base_cum = pnl(lambda g, t: 0.0)
out = {}
for name, cfg in VARIANTS.items():
    amb = [run(s, cfg, False) for s in seeds]
    spec = [run(s, cfg, True) for s in seeds]
    def m(runs, gid): return [statistics.mean(r[0][gid][t] for r in runs) for t in range(MAX_TURN + 1)]
    st_a, so_a = m(amb, STEEL), m(amb, by_name["solar_panel"]["id"])
    st_s = m(spec, STEEL)
    prof, cum = pnl(lambda g, t: statistics.mean(r[0][g][t] for r in spec))
    at300 = [statistics.mean(r[0][gid][300] for r in amb) for gid in producible]
    tr0 = amb[0][0]
    reversals = 0
    for gid in producible:
        x = tr0[gid]; last = 0
        for t in range(21, MAX_TURN + 1):
            d = x[t] - x[t - 1]
            dirn = 1 if d > 0.01 else (-1 if d < -0.01 else 0)
            if dirn != 0 and last != 0 and dirn != last: reversals += 1
            if dirn != 0: last = dirn
    window = sum(1 for t in range(MAX_TURN + 1) if st_s[t] >= 10)
    g_cnt = Counter(amb[0][1][STEEL])
    out[name] = {"steel_amb": [round(x, 2) for x in st_a], "solar_amb": [round(x, 2) for x in so_a],
                 "steel_spec": [round(x, 2) for x in st_s], "prof": [round(x, 1) for x in prof],
                 "cum": round(cum), "window": window,
                 "mean_abs": round(statistics.mean(abs(v) for v in at300), 1),
                 "extreme": sum(1 for v in at300 if abs(v) >= 29),
                 "reversals": round(reversals / len(producible), 1)}
    print(f"\n=== {name} ===")
    print("  steel ambient:  " + "".join(f"{st_a[c]:>8.1f}" for c in CPS))
    print("  solar ambient:  " + "".join(f"{so_a[c]:>8.1f}" for c in CPS))
    print("  steel spec:     " + "".join(f"{st_s[c]:>8.1f}" for c in CPS))
    print("  spec profit/t:  " + "".join(f"{prof[c]:>8.0f}" for c in CPS))
    print(f"  cum P&L £{cum:,.0f} ({100*cum/base_cum:.0f}% of baseline) | premium window >=+10%: {window} turns")
    print(f"  ambient t300: mean|imp| {out[name]['mean_abs']}%, goods >=|30| {out[name]['extreme']}, reversals/good {out[name]['reversals']}")
    print(f"  steel rival G usage (amb seed0): {dict(sorted(g_cnt.items()))}")

out["base_cum"] = round(base_cum)
json.dump(out, open(f"{ROOT}/variants.json", "w"))
print("\nwrote variants.json")
