#!/usr/bin/env python3
"""R5 = R4 + the cycle engine: capacity depreciation + bankruptcy + new entrants.

Additions to R4 (bands +/-40, lag 5, exits, 3/3/3, beta 0.75):
  DEPRECIATION  every rival's capacity decays 0.75%/turn (plants age out).
  BANKRUPTCY    a rival at/below its base plant in good g while impact <= -15
                for 15 consecutive turns goes bust in g: capacity -> 0, slot inactive.
                (All personas can go bankrupt - losses don't care about caution.)
  ENTRANT       impact >= +10 for 10 consecutive turns and an inactive slot exists
                -> a new entrant opens with capacity = base (inherits the slot's
                seeded draws + personality). Lumpy supply, ~panel news.
Cycle metrics: peaks/troughs with >=8pp prominence on ambient steel/solar,
median period + amplitude; bankruptcy/entry counts; specialist P&L.
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
EXIT_HOLD, LAG = 5, 5
P333 = [0]*3 + [.5]*3 + [1]*3
DELTA = 0.0075          # capacity depreciation per turn
BK_IMP, BK_HOLD = -15.0, 15
EN_IMP, EN_HOLD = 10.0, 10

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

def run_r5(seed, player=None):
    inc = {gid: [[D["rivals"][str(seed)][gid][i][b] - D["rivals"][str(seed)][gid][i][b - 1]
                  for b in range(1, 61)] for i in range(R_CT)] for gid in producible}
    q = {gid: [float(goods[gid]["base_output"])] * R_CT for gid in producible}
    active = {gid: [True] * R_CT for gid in producible}
    imp = defaultdict(float); ema = {}
    out_dir = defaultdict(int); out_cnt = defaultdict(int)
    in_dir = defaultdict(int); in_cnt = defaultdict(int)
    exit_cnt = defaultdict(int); low_cnt = defaultdict(int); hi_cnt = defaultdict(int)
    traj = defaultdict(list); n_bk = 0; n_en = 0
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
            exit_cnt[gid] = exit_cnt[gid] + 1 if d_o <= -20 else 0
            low_cnt[gid] = low_cnt[gid] + 1 if d_o <= BK_IMP else 0
            hi_cnt[gid] = hi_cnt[gid] + 1 if d_o >= EN_IMP else 0
        # depreciation every turn
        for gid in producible:
            base = goods[gid]["base_output"]
            for i in range(R_CT):
                if active[gid][i]:
                    q[gid][i] *= (1 - DELTA)
        # bankruptcy / entry checks (turn granularity)
        for gid in producible:
            base = goods[gid]["base_output"]
            if low_cnt[gid] >= BK_HOLD:
                for i in range(R_CT):
                    if active[gid][i] and q[gid][i] <= base * 1.05:
                        active[gid][i] = False; q[gid][i] = 0.0; n_bk += 1
                        low_cnt[gid] = 0
                        break   # one bankruptcy per good per trigger
            if hi_cnt[gid] >= EN_HOLD:
                for i in range(R_CT):
                    if not active[gid][i]:
                        active[gid][i] = True; q[gid][i] = float(base); n_en += 1
                        hi_cnt[gid] = 0
                        break
        if t > 0 and t % STEP == 0:
            b = t // STEP - 1
            for gid in producible:
                go = out_mag(imp.get(gid, 0.0)) if out_cnt[gid] >= LAG else 1.0
                gi = in_mag(in_dev(gid)) if in_cnt[gid] >= LAG else 1.0
                G_full = max(0.25, min(2.5, go * gi))
                exiting = exit_cnt[gid] >= EXIT_HOLD
                base = goods[gid]["base_output"]
                for i in range(R_CT):
                    if not active[gid][i] or b >= len(inc[gid][i]): continue
                    s = P333[i]
                    if exiting and s > 0:
                        cut = inc[gid][i][b] * s
                        q[gid][i] = max(base * 0.5, q[gid][i] - cut)
                    else:
                        Gr = 1 + (G_full - 1) * s if s > 0 else 1.0
                        q[gid][i] += inc[gid][i][b] * Gr
        sold = {gid: sum(qq for qq, a in zip(q[gid], active[gid]) if a) for gid in producible}
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
    return traj, n_bk, n_en

def cycles(series, prom=8.0):
    """peak/trough count with prominence, median period & amplitude."""
    ext = []
    for t in range(25, MAX_TURN - 4):
        w = series[t - 5:t + 6]
        if series[t] == max(w) and series[t] > min(w) + prom: ext.append((t, series[t], "pk"))
        if series[t] == min(w) and series[t] < max(w) - prom: ext.append((t, series[t], "tr"))
    # dedupe runs
    out = []
    for e in ext:
        if out and e[2] == out[-1][2] and abs(e[0] - out[-1][0]) < 12: continue
        out.append(e)
    periods = [out[i + 2][0] - out[i][0] for i in range(len(out) - 2)]
    amps = [abs(out[i + 1][1] - out[i][1]) for i in range(len(out) - 1)]
    return len(out), (statistics.median(periods) if periods else 0), (statistics.median(amps) if amps else 0)

def dec_price(gid, t):
    g = goods[gid]
    return g["base_price"] * ((1 - g["decay_rate"]) ** max(0, t - 29))

def pnl_steel(imp_of):
    cum = 0.0; neg = 0
    for t in range(MAX_TURN + 1):
        lv = LV[t]
        out_u = sum(54 * OUT_M[l] for l in lv); in_ii = sum(21 * IN_M[l] for l in lv)
        in_h2 = sum(5 * IN_M[l] for l in lv); en = sum(140 * EN_M[l] for l in lv)
        lab = sum(LABOUR_L1 * LAB_M[l] for l in lv); mnt = sum(MAINT_L1 * MAINT_M[l] for l in lv)
        rev = out_u * dec_price(STEEL, t) * (1 + imp_of(STEEL, t) / 100) * (1 - adval(t))
        cost = (in_ii * dec_price(II, t) * (1 + imp_of(II, t) / 100) * (1 + MARKUP)
                + in_h2 * dec_price(H2, t) * (1 + imp_of(H2, t) / 100) * (1 + MARKUP) + en * GRID + lab + mnt)
        p = rev - cost; cum += p
        if p < 0: neg += 1
    return cum, neg

seeds = list(D["rivals"].keys())
CPS = [50, 100, 150, 200, 250, 300]
_, cbn = pnl_steel(lambda g, t: 0.0)
cum_base, _ = pnl_steel(lambda g, t: 0.0)

amb = [run_r5(s) for s in seeds]
spec = [run_r5(s, "steel") for s in seeds]
def msr(runs, gid): return [statistics.mean(r[0][gid][t] for r in runs) for t in range(MAX_TURN + 1)]
st, so, hy = msr(amb, STEEL), msr(amb, SOL), msr(amb, H2)
sp = msr(spec, STEEL)

print("R5 ambient (3-seed mean):")
for n, s in [("steel", st), ("solar", so), ("hydrogen", hy)]:
    nc, per, amp = cycles(s)
    print(f"  {n:<10}" + "".join(f"{s[c]:>8.1f}" for c in CPS) + f"   extrema {nc}, median period {per:.0f}t, swing {amp:.0f}pp")
# single-seed (unaveraged) cycle stats — averaging can smear cycles
st1 = [amb[0][0][STEEL][t] for t in range(MAX_TURN + 1)]
so1 = [amb[0][0][SOL][t] for t in range(MAX_TURN + 1)]
for n, s in [("steel seed0", st1), ("solar seed0", so1)]:
    nc, per, amp = cycles(s)
    print(f"  {n:<12} extrema {nc}, median period {per:.0f}t, swing {amp:.0f}pp")
bk = statistics.mean(r[1] for r in amb); en = statistics.mean(r[2] for r in amb)
print(f"  events: {bk:.0f} bankruptcies, {en:.0f} entries per run (all goods)")
at300 = [statistics.mean(r[0][gid][300] for r in amb) for gid in producible]
print(f"  mean|imp| t300 {statistics.mean(abs(v) for v in at300):.1f}%  >=30: {sum(1 for v in at300 if abs(v) >= 29)}")

w10 = sum(1 for t in range(MAX_TURN + 1) if sp[t] >= 10)
cum, neg = pnl_steel(lambda g, t: statistics.mean(r[0][g][t] for r in spec))
print(f"\nR5 steel specialist: " + "".join(f"{sp[c]:>8.1f}" for c in CPS))
print(f"  window>=+10 {w10}t  peak {max(sp):.1f}  trough {min(sp):.1f}  P&L £{cum:,.0f} ({100*cum/cum_base:.0f}%)  neg-turns {neg}")

json.dump({"amb_steel": [round(x,2) for x in st], "amb_solar": [round(x,2) for x in so],
           "amb_steel_s0": [round(x,2) for x in st1], "amb_solar_s0": [round(x,2) for x in so1],
           "spec": [round(x,2) for x in sp]},
          open(f"{ROOT}/r5.json", "w"))
print("wrote r5.json")
