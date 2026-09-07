#!/usr/bin/env python3
"""Cap widening: +/-40% ladder (10/20/30/40) vs +/-60% ladder (15/30/45/60),
crossed with the market-depth sweep (beta 0.60/0.75/0.90). 3/3/3 personas, lag 5.
Checksum: 'top-only' variant (10/20/30/60) at beta 0.75 — how much the top band
alone matters. Response triggers and exit rule stay at their absolute values
(out +/-5,+/-10; in +/-12,+/-25; exit <=-20 held 5 turns).
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
C_THR, SPEED, EMA_N = 0.6, 0.5, 5
OUT_M = {1: 1.0, 2: 2.0, 3: 3.5}; IN_M = {1: 1.0, 2: 2.0, 3: 3.0}
EN_M = {1: 1.0, 2: 1.8, 3: 2.5}; LAB_M = {1: 1.0, 2: 1.5, 3: 2.0}; MAINT_M = {1: 1.0, 2: 1.8, 3: 2.5}
MARKUP, GRID = 0.05, 0.12
LABOUR_L1 = 1356 * 0.002 + 515 * 0.006 + 51 * 0.010
MAINT_L1 = 10.0
STEEL, II, H2 = by_name["steel"]["id"], by_name["iron_ingots"]["id"], by_name["hydrogen"]["id"]
SOL = by_name["solar_panel"]["id"]
EXIT_HOLD, LAG = 5, 5
P333 = [0]*3 + [.5]*3 + [1]*3
LADDERS = {"cap40": [(10, 40.0), (4, 30.0), (2, 20.0), (1, 10.0)],
           "cap60": [(10, 60.0), (4, 45.0), (2, 30.0), (1, 15.0)],
           "top60": [(10, 60.0), (4, 30.0), (2, 20.0), (1, 10.0)]}

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

def run(seed, beta, ladder, player=None):
    inc = {gid: [[D["rivals"][str(seed)][gid][i][b] - D["rivals"][str(seed)][gid][i][b - 1]
                  for b in range(1, 61)] for i in range(R_CT)] for gid in producible}
    q = {gid: [goods[gid]["base_output"]] * R_CT for gid in producible}
    imp = defaultdict(float); ema = {}
    out_dir = defaultdict(int); out_cnt = defaultdict(int)
    in_dir = defaultdict(int); in_cnt = defaultdict(int)
    exit_cnt = defaultdict(int)
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
                    s = P333[i]
                    if exiting and s > 0:
                        cut = int(round(inc[gid][i][b] * s))
                        q[gid][i] = max(goods[gid]["base_output"], q[gid][i] - cut)
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
        for gid, g in goods.items():
            base = g["base_output"]
            if base <= 0:
                traj[gid].append(0.0); continue
            net = pnet.get(gid, 0) + (1 - beta) * (sold.get(gid, 0) - bought.get(gid, 0.0))
            T = max(base, C_THR * base * gamma(t))
            r = net / T
            ema[gid] = r if gid not in ema else ema[gid] + (r - ema[gid]) / EMA_N
            e = ema[gid]
            tgt = 0.0
            if abs(e) > 1:
                for m, tg in ladder:
                    if abs(e) > m: tgt = tg * (-1 if e > 0 else 1); break
            imp[gid] += max(-SPEED, min(SPEED, tgt - imp[gid]))
            traj[gid].append(imp[gid])
    return traj

def dec_price(gid, t):
    g = goods[gid]
    return g["base_price"] * ((1 - g["decay_rate"]) ** max(0, t - 29))

def pnl_steel(imp_of):
    cum = 0.0; prof = []; neg = 0
    for t in range(MAX_TURN + 1):
        lv = LV[t]
        out_u = sum(54 * OUT_M[l] for l in lv); in_ii = sum(21 * IN_M[l] for l in lv)
        in_h2 = sum(5 * IN_M[l] for l in lv); en = sum(140 * EN_M[l] for l in lv)
        lab = sum(LABOUR_L1 * LAB_M[l] for l in lv); mnt = sum(MAINT_L1 * MAINT_M[l] for l in lv)
        rev = out_u * dec_price(STEEL, t) * (1 + imp_of(STEEL, t) / 100) * (1 - adval(t))
        cost = (in_ii * dec_price(II, t) * (1 + imp_of(II, t) / 100) * (1 + MARKUP)
                + in_h2 * dec_price(H2, t) * (1 + imp_of(H2, t) / 100) * (1 + MARKUP) + en * GRID + lab + mnt)
        p = rev - cost; prof.append(p); cum += p
        if p < 0: neg += 1
    return prof, cum, neg

seeds = list(D["rivals"].keys())
CPS = [50, 100, 150, 200, 250, 300]
_, cum_base, _ = pnl_steel(lambda g, t: 0.0)
def msr(runs, gid): return [statistics.mean(r[gid][t] for r in runs) for t in range(MAX_TURN + 1)]

out = {}
for lname in ["cap40", "cap60"]:
    ladder = LADDERS[lname]
    for beta in [0.60, 0.75, 0.90]:
        amb = [run(s, beta, ladder) for s in seeds]
        spec = [run(s, beta, ladder, player="steel") for s in seeds]
        st_a = msr(amb, STEEL); so_a = msr(amb, SOL); sp = msr(spec, STEEL)
        at300 = [statistics.mean(r[gid][300] for r in amb) for gid in producible]
        w10 = sum(1 for t in range(MAX_TURN + 1) if sp[t] >= 10)
        peak = max(sp); trough = min(sp)
        prof, cum, neg = pnl_steel(lambda g, t: statistics.mean(r[g][t] for r in spec))
        key = f"{lname}_b{beta:.2f}"
        out[key] = {"spec": [round(x, 2) for x in sp], "amb_steel": [round(x, 2) for x in st_a],
                    "amb_solar": [round(x, 2) for x in so_a],
                    "stats": {"mean_abs": round(statistics.mean(abs(v) for v in at300), 1),
                              "extreme30": sum(1 for v in at300 if abs(v) >= 29),
                              "extreme45": sum(1 for v in at300 if abs(v) >= 44),
                              "solar300": round(so_a[300], 1), "steel50": round(st_a[50], 1),
                              "w10": w10, "peak": round(peak, 1), "trough": round(trough, 1),
                              "pnl": round(cum), "pnl_pct": round(100 * cum / cum_base),
                              "neg_turns": neg}}
        s = out[key]["stats"]
        print(f"{lname} β{beta:.2f}: amb|imp| {s['mean_abs']:>5}%  ≥30:{s['extreme30']:>2}  ≥45:{s['extreme45']:>2}  "
              f"solar300 {s['solar300']:>6}  steel50 {s['steel50']:>6}  | spec w10 {s['w10']:>3}t  "
              f"peak {s['peak']:>6} trough {s['trough']:>6}  P&L {s['pnl_pct']:>3}%  neg-turns {s['neg_turns']}")

# top-only checksum at beta 0.75
amb = [run(s, 0.75, LADDERS["top60"]) for s in seeds]
spec = [run(s, 0.75, LADDERS["top60"], player="steel") for s in seeds]
sp = msr(spec, STEEL)
at300 = [statistics.mean(r[gid][300] for r in amb) for gid in producible]
prof, cum, neg = pnl_steel(lambda g, t: statistics.mean(r[g][t] for r in spec))
print(f"\ntop60-only β0.75 (checksum): amb|imp| {statistics.mean(abs(v) for v in at300):.1f}%  "
      f"spec P&L {100*cum/cum_base:.0f}%  (vs cap40 β0.75 above — top band alone changes little)")

json.dump(out, open(f"{ROOT}/cap60.json", "w"))
print("wrote cap60.json")
