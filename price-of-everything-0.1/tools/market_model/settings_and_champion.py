#!/usr/bin/env python3
"""1. MARKET DEPTH sweep: beta (global-demand absorption) 0.60 / 0.75 / 0.90
   at 3/3/3 personas, lag 5 — ambient + steel specialist. Did it matter?
2. STATE-OWNED CHAMPION: a 10th non-responding competitor producing every good,
   expanding by the MAX increment (f=1.0, +base per 5 turns) to t85, frozen, then
   production scaled 75%/50%/25%/0% at t95/100/105/110 (gone by t115).
   Config: beta 0.75, 3/3/3, lag 5. Ambient + steel specialist, ON vs OFF.
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
BAND_EDGES = [(10, 40.0), (4, 30.0), (2, 20.0), (1, 10.0)]
OUT_M = {1: 1.0, 2: 2.0, 3: 3.5}; IN_M = {1: 1.0, 2: 2.0, 3: 3.0}
EN_M = {1: 1.0, 2: 1.8, 3: 2.5}; LAB_M = {1: 1.0, 2: 1.5, 3: 2.0}; MAINT_M = {1: 1.0, 2: 1.8, 3: 2.5}
MARKUP, GRID = 0.05, 0.12
LABOUR_L1 = 1356 * 0.002 + 515 * 0.006 + 51 * 0.010
MAINT_L1 = 10.0
STEEL, II, H2 = by_name["steel"]["id"], by_name["iron_ingots"]["id"], by_name["hydrogen"]["id"]
SOL = by_name["solar_panel"]["id"]
EXIT_HOLD = 5
P333 = [0]*3 + [.5]*3 + [1]*3

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

def champ_scale(t):
    if t < 95: return 1.0
    if t < 100: return 0.75
    if t < 105: return 0.5
    if t < 110: return 0.25
    return 0.0

def run(seed, beta, lag, player=None, champion=False):
    inc = {gid: [[D["rivals"][str(seed)][gid][i][b] - D["rivals"][str(seed)][gid][i][b - 1]
                  for b in range(1, 61)] for i in range(R_CT)] for gid in producible}
    q = {gid: [goods[gid]["base_output"]] * R_CT for gid in producible}
    champ = {gid: goods[gid]["base_output"] for gid in producible} if champion else {}
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
                go = out_mag(imp.get(gid, 0.0)) if out_cnt[gid] >= lag else 1.0
                gi = in_mag(in_dev(gid)) if in_cnt[gid] >= lag else 1.0
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
                if champion and t <= 85:
                    champ[gid] += goods[gid]["base_output"]   # max increment every batch
        sold = {gid: sum(q[gid]) for gid in producible}
        bought = defaultdict(float)
        if champion:
            cs = champ_scale(t)
            for gid in producible:
                sold[gid] += champ[gid] * cs
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
                for m, tg in BAND_EDGES:
                    if abs(e) > m: tgt = tg * (-1 if e > 0 else 1); break
            imp[gid] += max(-SPEED, min(SPEED, tgt - imp[gid]))
            traj[gid].append(imp[gid])
    return traj

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
def ms(runs, gid): return [statistics.mean(r[gid][t] for r in runs) for t in range(MAX_TURN + 1)]

print("=" * 96)
print("MARKET DEPTH SWEEP (beta = share of NPC flow absorbed by world trade), 3/3/3, lag 5")
print("=" * 96)
depth_out = {}
for beta in [0.60, 0.75, 0.90]:
    amb = [run(s, beta, 5) for s in seeds]
    spec = [run(s, beta, 5, player="steel") for s in seeds]
    st_a = ms(amb, STEEL); so_a = ms(amb, SOL); sp = ms(spec, STEEL)
    at300 = [statistics.mean(r[gid][300] for r in amb) for gid in producible]
    w = sum(1 for t in range(MAX_TURN + 1) if sp[t] >= 10)
    _, cum = pnl_steel(lambda g, t: statistics.mean(r[g][t] for r in spec))
    depth_out[str(beta)] = {"spec": [round(x, 2) for x in sp], "amb_steel": [round(x, 2) for x in st_a]}
    print(f"beta {beta:.2f}: ambient mean|imp| {statistics.mean(abs(v) for v in at300):.1f}%  "
          f">=|30|: {sum(1 for v in at300 if abs(v) >= 29)}  solar t300 {so_a[300]:.1f}%  "
          f"steel amb t50 {st_a[50]:+.1f}%")
    print(f"           specialist window {w}t  P&L £{cum:,.0f} ({100*cum/cum_base:.0f}%)  "
          f"spec impact: " + "".join(f"{sp[c]:>7.1f}" for c in CPS))

print("\n" + "=" * 96)
print("STATE-OWNED CHAMPION (max growth to t85, wind-down 95-110), beta 0.75, 3/3/3, lag 5")
print("=" * 96)
amb_off = [run(s, 0.75, 5) for s in seeds]
amb_on = [run(s, 0.75, 5, champion=True) for s in seeds]
spec_off = [run(s, 0.75, 5, player="steel") for s in seeds]
spec_on = [run(s, 0.75, 5, player="steel", champion=True) for s in seeds]
for name, gid in [("steel", STEEL), ("solar_panel", SOL), ("iron_ingots", II), ("hydrogen", H2)]:
    a_off = ms(amb_off, gid); a_on = ms(amb_on, gid)
    print(f"  {name:<14} ambient OFF: " + "".join(f"{a_off[c]:>7.1f}" for c in [50, 85, 100, 115, 150, 200, 300]))
    print(f"  {'':<14} ambient ON:  " + "".join(f"{a_on[c]:>7.1f}" for c in [50, 85, 100, 115, 150, 200, 300]))
sp_off = ms(spec_off, STEEL); sp_on = ms(spec_on, STEEL)
w_off = sum(1 for t in range(MAX_TURN + 1) if sp_off[t] >= 10)
w_on = sum(1 for t in range(MAX_TURN + 1) if sp_on[t] >= 10)
_, cum_off = pnl_steel(lambda g, t: statistics.mean(r[g][t] for r in spec_off))
_, cum_on = pnl_steel(lambda g, t: statistics.mean(r[g][t] for r in spec_on))
prof_on, _ = pnl_steel(lambda g, t: statistics.mean(r[g][t] for r in spec_on))
prof_off, _ = pnl_steel(lambda g, t: statistics.mean(r[g][t] for r in spec_off))
print(f"\n  steel specialist OFF: window {w_off}t, P&L £{cum_off:,.0f} ({100*cum_off/cum_base:.0f}%)")
print(f"  steel specialist ON:  window {w_on}t, P&L £{cum_on:,.0f} ({100*cum_on/cum_base:.0f}%)")
print("  spec impact ON:  " + "".join(f"{sp_on[c]:>7.1f}" for c in [50, 85, 100, 115, 150, 200, 300]))
print("  spec impact OFF: " + "".join(f"{sp_off[c]:>7.1f}" for c in [50, 85, 100, 115, 150, 200, 300]))

json.dump({"depth": depth_out,
           "champ": {"amb_steel_off": [round(x, 2) for x in ms(amb_off, STEEL)],
                     "amb_steel_on": [round(x, 2) for x in ms(amb_on, STEEL)],
                     "spec_on": [round(x, 2) for x in sp_on], "spec_off": [round(x, 2) for x in sp_off],
                     "prof_on": [round(x, 1) for x in prof_on], "prof_off": [round(x, 1) for x in prof_off]}},
          open(f"{ROOT}/settings_champion.json", "w"))
print("\nwrote settings_champion.json")
