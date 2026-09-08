#!/usr/bin/env python3
"""R6 — owner proposals (2026-08-12 late):

Base = R4 (bands +/-40, lag 5, exits, 3/3/3, beta .75) + rival-only depreciation 0.75%/turn.
  ACQUISITIONS  impact <= -15 for 10 turns -> smallest active rival with q > 2x base is
                acquired: 50% of its capacity DESTROYED, 50% transferred to the largest
                rival; seller inactive in that good. Cooldown 15/good. (Lumpy supply shock.)
  BANKRUPTCY    floor-dwellers (q <= 1.05x base) in <= -15% markets for 15 turns fold fully.
  ENTRANTS      owner triggers: impact >= +30 for 5 turns OR >= +40 for 2 turns
                -> new entrant at base capacity (slot reuse or append, max 12). Cooldown 10.
  DEMAND CYCLE  per-good world-demand wobble w_g(t): seeded shuffle of a 10-slot phase
                cycle [G x5, D x2, P x3]; G: +1.0%/turn, D: -1.5%/turn, P: 0
                (growth phases longer AND net-positive: +5 -3 = +2% per 10 turns above trend).
                Extra world demand = w_g x beta x gross rival supply of g, subtracted from net.
Configs: R6a events only | R6b = a + demand cycle 5-2-3 | R6c = a + slow cycle 20/8/12
         (G +0.5%, D -1.25%, P 0 -> +/-10% amplitude, 40-turn period, net +0 per cycle...
         20x0.5 -3x... 20*0.5=10, 8*1.25=10 -> net 0, amplitude +/-10%, period 40).
"""
import json, math, statistics, random
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
EXIT_HOLD, LAG, DELTA = 5, 5, 0.0075
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

def demand_wobble(seed, gid, mode):
    """w_g(t) series: cumulative % deviation of world demand for g."""
    if mode == "none": return [0.0] * (MAX_TURN + 1)
    if mode == "fast": slots, gstep, dstep = ([1]*5 + [-1]*2 + [0]*3), 0.010, 0.015
    elif mode == "slow": slots, gstep, dstep = ([1]*20 + [-1]*8 + [0]*12), 0.005, 0.0125
    else: slots, gstep, dstep = ([1]*20 + [-1]*8 + [0]*12), 0.015, 0.0375
    rng = random.Random(int(seed) * 7919 + int(gid.split("_")[1]) * 101)
    order = slots[:]; rng.shuffle(order)
    w, out = 0.0, []
    for t in range(MAX_TURN + 1):
        ph = order[t % len(order)]
        if ph == 1: w += gstep
        elif ph == -1: w -= dstep
        out.append(w)
    return out

def run_r6(seed, mode, player=None):
    inc = {gid: [[D["rivals"][str(seed)][gid][i][b] - D["rivals"][str(seed)][gid][i][b - 1]
                  for b in range(1, 61)] for i in range(R_CT)] for gid in producible}
    q = {gid: [float(goods[gid]["base_output"])] * R_CT for gid in producible}
    active = {gid: [True] * R_CT for gid in producible}
    wob = {gid: demand_wobble(seed, gid, mode) for gid in producible}
    imp = defaultdict(float); ema = {}
    out_dir = defaultdict(int); out_cnt = defaultdict(int)
    in_dir = defaultdict(int); in_cnt = defaultdict(int)
    exit_cnt = defaultdict(int); dis_cnt = defaultdict(int); low_cnt = defaultdict(int)
    hi30 = defaultdict(int); hi40 = defaultdict(int)
    cd_acq = defaultdict(int); cd_en = defaultdict(int)
    traj = defaultdict(list); n_bk = n_acq = n_en = 0
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
            cd_acq[gid] = max(0, cd_acq[gid] - 1); cd_en[gid] = max(0, cd_en[gid] - 1)
            d_o = imp.get(gid, 0.0)
            s_o = 1 if d_o >= 5 else (-1 if d_o <= -5 else 0)
            out_cnt[gid] = out_cnt[gid] + 1 if s_o == out_dir[gid] and s_o != 0 else (1 if s_o != 0 else 0)
            out_dir[gid] = s_o
            d_i = in_dev(gid)
            s_i = 1 if d_i >= 0.12 else (-1 if d_i <= -0.12 else 0)
            in_cnt[gid] = in_cnt[gid] + 1 if s_i == in_dir[gid] and s_i != 0 else (1 if s_i != 0 else 0)
            in_dir[gid] = s_i
            exit_cnt[gid] = exit_cnt[gid] + 1 if d_o <= -20 else 0
            dis_cnt[gid] = dis_cnt[gid] + 1 if d_o <= -15 else 0
            low_cnt[gid] = low_cnt[gid] + 1 if d_o <= -15 else 0
            hi30[gid] = hi30[gid] + 1 if d_o >= 30 else 0
            hi40[gid] = hi40[gid] + 1 if d_o >= 40 else 0
        for gid in producible:
            base = goods[gid]["base_output"]
            for i in range(len(active[gid])):
                if active[gid][i]: q[gid][i] *= (1 - DELTA)
            # acquisition: distressed 10 turns, a sizeable seller exists
            if dis_cnt[gid] >= 10 and cd_acq[gid] <= 0:
                cands = [i for i in range(len(active[gid])) if active[gid][i] and q[gid][i] > 2 * base]
                if len(cands) >= 2:
                    seller = min(cands, key=lambda i: q[gid][i])
                    buyer = max(cands, key=lambda i: q[gid][i])
                    if seller != buyer:
                        moved = q[gid][seller] * 0.5
                        q[gid][buyer] += moved
                        q[gid][seller] = 0.0; active[gid][seller] = False
                        n_acq += 1; cd_acq[gid] = 15; dis_cnt[gid] = 0
            if low_cnt[gid] >= 15:
                for i in range(len(active[gid])):
                    if active[gid][i] and q[gid][i] <= base * 1.05:
                        active[gid][i] = False; q[gid][i] = 0.0; n_bk += 1
                        low_cnt[gid] = 0
                        break
            if (hi30[gid] >= 5 or hi40[gid] >= 2) and cd_en[gid] <= 0:
                placed = False
                for i in range(len(active[gid])):
                    if not active[gid][i]:
                        active[gid][i] = True; q[gid][i] = float(base); placed = True; break
                if not placed and len(active[gid]) < 12:
                    active[gid].append(True); q[gid].append(float(base))
                    inc[gid].append(inc[gid][len(active[gid]) % R_CT])
                    placed = True
                if placed:
                    n_en += 1; cd_en[gid] = 10; hi30[gid] = 0; hi40[gid] = 0
        if t > 0 and t % STEP == 0:
            b = t // STEP - 1
            for gid in producible:
                go = out_mag(imp.get(gid, 0.0)) if out_cnt[gid] >= LAG else 1.0
                gi = in_mag(in_dev(gid)) if in_cnt[gid] >= LAG else 1.0
                G_full = max(0.25, min(2.5, go * gi))
                exiting = exit_cnt[gid] >= EXIT_HOLD
                base = goods[gid]["base_output"]
                for i in range(len(active[gid])):
                    if not active[gid][i] or b >= len(inc[gid][i]): continue
                    s = P333[i % R_CT] if i < R_CT else 1.0
                    if exiting and s > 0:
                        q[gid][i] = max(base * 0.5, q[gid][i] - inc[gid][i][b] * s)
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
            dem = wob[gid][t] * sold.get(gid, 0) if gid in wob else 0.0
            net = pnet.get(gid, 0) + (1 - BETA) * (sold.get(gid, 0) - bought.get(gid, 0.0)) - dem
            T = max(base, C_THR * sold.get(gid, 9 * base) / 9.0)
            r = net / T
            ema[gid] = r if gid not in ema else ema[gid] + (r - ema[gid]) / EMA_N
            e = ema[gid]
            tgt = 0.0
            if abs(e) > 1:
                for m, tg in BAND_EDGES:
                    if abs(e) > m: tgt = tg * (-1 if e > 0 else 1); break
            imp[gid] += max(-SPEED, min(SPEED, tgt - imp[gid]))
            traj[gid].append(imp[gid])
    return traj, n_bk, n_acq, n_en

def cycles(series, prom=8.0):
    ext = []
    for t in range(25, MAX_TURN - 4):
        w = series[t - 5:t + 6]
        if series[t] == max(w) and series[t] > min(w) + prom: ext.append((t, series[t], "pk"))
        if series[t] == min(w) and series[t] < max(w) - prom: ext.append((t, series[t], "tr"))
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
cum_base, _ = pnl_steel(lambda g, t: 0.0)
def msr(runs, gid): return [statistics.mean(r[0][gid][t] for r in runs) for t in range(MAX_TURN + 1)]

out = {}
for label, mode in [("R6e T-realized, no waves", "none"), ("R6f T-realized + waves ±30%", "slow3x")]:
    amb = [run_r6(s, mode) for s in seeds]
    spec = [run_r6(s, mode, player="steel") for s in seeds]
    st, so, hy = msr(amb, STEEL), msr(amb, SOL), msr(amb, H2)
    sp = msr(spec, STEEL)
    st1 = [amb[0][0][STEEL][t] for t in range(MAX_TURN + 1)]
    so1 = [amb[0][0][SOL][t] for t in range(MAX_TURN + 1)]
    at300 = [statistics.mean(r[0][gid][300] for r in amb) for gid in producible]
    # cycles across ALL goods, seed 0
    tot_ext = 0; pers = []; amps_all = []
    for gid in producible:
        s_ = [amb[0][0][gid][t] for t in range(MAX_TURN + 1)]
        nc, per, amp = cycles(s_)
        tot_ext += nc
        if per: pers.append(per)
        if amp: amps_all.append(amp)
    bk = statistics.mean(r[1] for r in amb); acq = statistics.mean(r[2] for r in amb); en = statistics.mean(r[3] for r in amb)
    w10 = sum(1 for t in range(MAX_TURN + 1) if sp[t] >= 10)
    cum, neg = pnl_steel(lambda g, t: statistics.mean(r[0][g][t] for r in spec))
    key = label.split()[0]
    out[key] = {"steel": [round(x, 2) for x in st], "solar": [round(x, 2) for x in so],
                "steel_s0": [round(x, 2) for x in st1], "solar_s0": [round(x, 2) for x in so1],
                "spec": [round(x, 2) for x in sp]}
    print(f"\n=== {label} ===")
    print("  steel amb:  " + "".join(f"{st[c]:>8.1f}" for c in CPS))
    print("  solar amb:  " + "".join(f"{so[c]:>8.1f}" for c in CPS))
    print(f"  CYCLES (seed0, all goods): {tot_ext} extrema | median period {statistics.median(pers) if pers else 0:.0f}t | median swing {statistics.median(amps_all) if amps_all else 0:.0f}pp")
    print(f"  events/run: {bk:.0f} bankruptcies, {acq:.0f} acquisitions, {en:.0f} entrants")
    print(f"  ambient t300: mean|imp| {statistics.mean(abs(v) for v in at300):.1f}%  >=30: {sum(1 for v in at300 if abs(v) >= 29)}")
    print(f"  specialist: window {w10}t  P&L {100*cum/cum_base:.0f}%  neg-turns {neg}")

json.dump(out, open(f"{ROOT}/r6ef.json", "w"))
print("\nwrote r6.json")
