#!/usr/bin/env python3
"""R4 persona-mix sweep, player involved.

Mixes (cautious / half-cautious / aggressive):
  A 4/3/2 (Plate XIV)   B 3/3/3   C 2/3/4   D 2/4/3
Scenarios per mix (3 seeds each):
  - steel specialist (sells steel, buys ingots+H2)  -> impact arc, window, P&L
  - solar dumper (sells solar, buys its inputs)     -> solar arc, rival capacity kill
  - ambient                                          -> solar healing, reversals
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
LABOUR_L1 = 1356 * 0.002 + 515 * 0.006 + 51 * 0.010
MAINT_L1 = 10.0
STEEL, II, H2 = by_name["steel"]["id"], by_name["iron_ingots"]["id"], by_name["hydrogen"]["id"]
SOL = by_name["solar_panel"]["id"]
EXIT_HOLD, LAG = 5, 10
MIXES = {"A 4/3/2": [0]*4 + [.5]*3 + [1]*2, "B 3/3/3": [0]*3 + [.5]*3 + [1]*3,
         "C 2/3/4": [0]*2 + [.5]*3 + [1]*4, "D 2/4/3": [0]*2 + [.5]*4 + [1]*3}

def gamma(t): return 1.0 + 0.425 * (t // 5)
def adval(t): return 0.005 if t < 31 else 0.03
def out_mag(d):
    if d >= 10: return 2.0
    if d >= 5: return 1.5
    if d <= -10: return 0.5
    if d <= -5: return 0.75
    return 1.0
def in_mag(d):
    if d <= -0.25: return 2.0
    if d <= -0.12: return 1.5
    if d >= 0.25: return 0.5
    if d >= 0.12: return 0.75
    return 1.0

consumers = defaultdict(list); inputs_of = {}
for gid in producible:
    g = goods[gid]; oq = g["base_recipe_output_qty"]
    inputs_of[gid] = []
    if oq <= 0: continue
    for inp in g["base_recipe_inputs"]:
        consumers[inp["good_id"]].append((gid, inp["qty"] / oq))
        inputs_of[gid].append((inp["good_id"], inp["qty"]))

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

def run(seed, personas, player=None):
    inc = {gid: [[D["rivals"][str(seed)][gid][i][b] - D["rivals"][str(seed)][gid][i][b - 1]
                  for b in range(1, 61)] for i in range(R_CT)] for gid in producible}
    q = {gid: [goods[gid]["base_output"]] * R_CT for gid in producible}
    imp = defaultdict(float); ema = {}
    out_dir = defaultdict(int); out_cnt = defaultdict(int)
    in_dir = defaultdict(int); in_cnt = defaultdict(int)
    exit_cnt = defaultdict(int); retired = defaultdict(int)
    traj = defaultdict(list)
    def in_dev(gid):
        ins = inputs_of.get(gid, [])
        if not ins: return 0.0
        ws = dv = 0.0
        for j, qty in ins:
            pj = goods[j]["base_price"] * (1 + imp.get(j, 0.0) / 100)
            ws += pj * qty; dv += pj * qty * imp.get(j, 0.0) / 100
        return dv / ws if ws > 0 else 0.0
    for t in range(MAX_TURN + 1):
        for gid in producible:
            d_o = imp.get(gid, 0.0)
            s_o = 1 if d_o >= 5 else (-1 if d_o <= -5 else 0)
            out_cnt[gid] = out_cnt[gid] + 1 if s_o == out_dir[gid] and s_o != 0 else (1 if s_o != 0 else 0)
            out_dir[gid] = s_o
            d_i = in_dev(gid)
            s_i = 1 if d_i >= 0.12 else (-1 if d_i <= -0.12 else 0)
            in_cnt[gid] = in_cnt[gid] + 1 if s_i == in_dir[gid] and s_i != 0 else (1 if s_i != 0 else 0)
            in_dir[gid] = s_i
            exit_cnt[gid] = exit_cnt[gid] + 1 if imp.get(gid, 0.0) <= -20 else 0
        if t > 0 and t % STEP == 0:
            b = t // STEP - 1
            for gid in producible:
                go = out_mag(imp.get(gid, 0.0)) if out_cnt[gid] >= LAG else 1.0
                gi = in_mag(in_dev(gid)) if in_cnt[gid] >= LAG else 1.0
                G_full = max(0.25, min(2.5, go * gi))
                exiting = exit_cnt[gid] >= EXIT_HOLD
                for i in range(R_CT):
                    if b >= len(inc[gid][i]): continue
                    s = personas[i]
                    if exiting and s > 0:
                        cut = int(round(inc[gid][i][b] * s))
                        newq = max(goods[gid]["base_output"], q[gid][i] - cut)
                        retired[gid] += q[gid][i] - newq
                        q[gid][i] = newq
                    else:
                        Gr = 1 + (G_full - 1) * s if s > 0 else 1.0
                        q[gid][i] += int(round(inc[gid][i][b] * Gr))
        sold = {gid: sum(q[gid]) for gid in producible}
        bought = defaultdict(float)
        for j, cons in consumers.items():
            for cgid, pu in cons:
                bought[j] += sold.get(cgid, 0) * pu
        pnet = {}
        if player == "steel":
            lv = LV[t]
            pnet = {STEEL: sum(54 * OUT_M[l] for l in lv),
                    II: -sum(21 * IN_M[l] for l in lv), H2: -sum(5 * IN_M[l] for l in lv)}
        elif player == "solar":
            lv = LV[t]
            pnet = {SOL: sum(15 * OUT_M[l] for l in lv)}
            for n, qty in [("polysilicon", 8), ("electrical_components", 4),
                           ("alloy_ingots", 9), ("aluminium", 6), ("refined_ree", 2)]:
                pnet[by_name[n]["id"]] = -sum(qty * IN_M[l] for l in lv)
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
    return traj, sold, retired

def dec_price(gid, t):
    g = goods[gid]
    return g["base_price"] * ((1 - g["decay_rate"]) ** max(0, t - 29))

def pnl_steel(imp_of):
    cum = 0.0; prof = []
    for t in range(MAX_TURN + 1):
        lv = LV[t]
        out_u = sum(54 * OUT_M[l] for l in lv); in_ii = sum(21 * IN_M[l] for l in lv)
        in_h2 = sum(5 * IN_M[l] for l in lv); en = sum(140 * EN_M[l] for l in lv)
        lab = sum(LABOUR_L1 * LAB_M[l] for l in lv); mnt = sum(MAINT_L1 * MAINT_M[l] for l in lv)
        rev = out_u * dec_price(STEEL, t) * (1 + imp_of(STEEL, t) / 100) * (1 - adval(t))
        cost = (in_ii * dec_price(II, t) * (1 + imp_of(II, t) / 100) * (1 + MARKUP)
                + in_h2 * dec_price(H2, t) * (1 + imp_of(H2, t) / 100) * (1 + MARKUP) + en * GRID + lab + mnt)
        p = rev - cost; prof.append(p); cum += p
    return prof, cum

seeds = list(D["rivals"].keys())
CPS = [50, 100, 150, 200, 250, 300]
_, cum_base = pnl_steel(lambda g, t: 0.0)
out = {}
for name, personas in MIXES.items():
    spec = [run(s, personas, "steel") for s in seeds]
    dump = [run(s, personas, "solar") for s in seeds]
    amb = [run(s, personas) for s in seeds]
    def m(runs, gid): return [statistics.mean(r[0][gid][t] for r in runs) for t in range(MAX_TURN + 1)]
    sp = m(spec, STEEL); sd = m(dump, SOL); sa = m(amb, SOL)
    prof, cum = pnl_steel(lambda g, t: statistics.mean(r[0][g][t] for r in spec))
    w = sum(1 for t in range(MAX_TURN + 1) if sp[t] >= 10)
    riv_cap = statistics.mean(r[1].get(SOL, 0) for r in dump)
    riv_ret = statistics.mean(r[2].get(SOL, 0) for r in dump)
    tr0 = amb[0][0]; rev_ct = 0
    for gid in producible:
        x = tr0[gid]; last = 0
        for t in range(21, MAX_TURN + 1):
            d = x[t] - x[t - 1]
            dirn = 1 if d > 0.01 else (-1 if d < -0.01 else 0)
            if dirn != 0 and last != 0 and dirn != last: rev_ct += 1
            if dirn != 0: last = dirn
    out[name] = {"spec": [round(x, 2) for x in sp], "dump": [round(x, 2) for x in sd],
                 "prof": [round(x, 1) for x in prof],
                 "window": w, "pnl": round(cum), "pnl_pct": round(100 * cum / cum_base),
                 "amb_solar_300": round(sa[300], 1), "dump_cap": round(riv_cap),
                 "dump_retired": round(riv_ret), "reversals": round(rev_ct / len(producible), 1)}
    print(f"\n=== {name} ===")
    print("  steel spec:  " + "".join(f"{sp[c]:>8.1f}" for c in CPS))
    print("  solar dump:  " + "".join(f"{sd[c]:>8.1f}" for c in CPS))
    print(f"  window >=+10%: {w}t | P&L £{cum:,.0f} ({out[name]['pnl_pct']}%) | ambient solar t300: {out[name]['amb_solar_300']}%")
    print(f"  dumper: rival solar cap t300 {out[name]['dump_cap']} (retired {out[name]['dump_retired']}) | reversals/good {out[name]['reversals']}")

json.dump(out, open(f"{ROOT}/mixes.json", "w"))
print("\nwrote mixes.json")
