#!/usr/bin/env python3
"""R7 — the owner's SAWTOOTH global demand, per good, on the R6 event kit:

  GROW 20 turns: demand multiplier rises U(0.5,4)%/turn  (total +10..80%)
  DECAY 10 turns: falls U(1,5)%/turn                      (total -10..50%)
  PLATEAU 10 turns: flat. Repeat. Phases staggered per good (seeded offset).
  dem = (M_g(t) - 1) x beta x rival gross supply of g  ->  subtracted from net.

Base: R4 (bands +/-40, lag 5, exits, 3/3/3, beta .75) + depreciation 0.75%/turn
+ acquisitions (50% write-down) + strict entrants (+30x5t / +40x2t).

Scenarios: ambient | steel PRODUCER (usual build-out) | MOTOR MAKER (sells motors,
buys 32 steel + 32 wiring per 28) under sawtooth AND under R6b steady growth.
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
LABOUR_L1 = 1356 * 0.002 + 515 * 0.006 + 51 * 0.010   # approximation reused for motor overheads
MAINT_L1 = 10.0
STEEL, II, H2 = by_name["steel"]["id"], by_name["iron_ingots"]["id"], by_name["hydrogen"]["id"]
SOL, MOT, CW = by_name["solar_panel"]["id"], by_name["motor"]["id"], by_name["copper_wiring"]["id"]
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

def demand_series(seed, gid, mode):
    """M_g(t) demand multiplier."""
    M, out = 1.0, []
    rng = random.Random(int(seed) * 104729 + int(gid.split("_")[1]) * 271)
    if mode == "r6b":
        slots = [1]*5 + [-1]*2 + [0]*3
        order = slots[:]; rng.shuffle(order)
        for t in range(MAX_TURN + 1):
            ph = order[t % 10]
            if ph == 1: M *= 1.010
            elif ph == -1: M *= 0.985
            out.append(M)
        return out
    offset = rng.randrange(40)
    if mode == "saw":
        for t in range(MAX_TURN + 1):
            ph = (t + offset) % 40
            if ph < 20: M *= 1 + rng.uniform(0.005, 0.04)
            elif ph < 30: M *= 1 - rng.uniform(0.01, 0.05)
            out.append(M)
        return out
    # saw2: balanced — each bust unwinds ~its boom (x U(0.8,1.2)) over 10 turns
    import math as _m
    boom_log = 0.0; bust_step = 0.0
    for t in range(MAX_TURN + 1):
        ph = (t + offset) % 40
        if ph == 0: boom_log = 0.0
        if ph < 20:
            s = _m.log(1 + rng.uniform(0.005, 0.04)); boom_log += s; M *= _m.exp(s)
        elif ph == 20:
            bust_step = boom_log * rng.uniform(0.8, 1.2) / 10.0; M *= _m.exp(-bust_step)
        elif ph < 30: M *= _m.exp(-bust_step)
        out.append(M)
    return out

def run_r7(seed, mode, player=None):
    inc = {gid: [[D["rivals"][str(seed)][gid][i][b] - D["rivals"][str(seed)][gid][i][b - 1]
                  for b in range(1, 61)] for i in range(R_CT)] for gid in producible}
    q = {gid: [float(goods[gid]["base_output"])] * R_CT for gid in producible}
    active = {gid: [True] * R_CT for gid in producible}
    Mdem = {gid: demand_series(seed, gid, mode) for gid in producible}
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
            if dis_cnt[gid] >= 10 and cd_acq[gid] <= 0:
                cands = [i for i in range(len(active[gid])) if active[gid][i] and q[gid][i] > 2 * base]
                if len(cands) >= 2:
                    seller = min(cands, key=lambda i: q[gid][i])
                    buyer = max(cands, key=lambda i: q[gid][i])
                    if seller != buyer:
                        q[gid][buyer] += q[gid][seller] * 0.5
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
        lv = LV[t]
        if player == "steel":
            pnet = {STEEL: sum(54 * OUT_M[l] for l in lv),
                    II: -sum(21 * IN_M[l] for l in lv), H2: -sum(5 * IN_M[l] for l in lv)}
        elif player == "motor":
            pnet = {MOT: sum(28 * OUT_M[l] for l in lv),
                    STEEL: -sum(32 * IN_M[l] for l in lv), CW: -sum(32 * IN_M[l] for l in lv)}
        for gid, g in goods.items():
            base = g["base_output"]
            if base <= 0:
                traj[gid].append(0.0); continue
            dem = (Mdem[gid][t] - 1) * BETA * sold.get(gid, 0) if gid in Mdem else 0.0
            net = pnet.get(gid, 0) + (1 - BETA) * (sold.get(gid, 0) - bought.get(gid, 0.0)) - dem
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

def pnl(imp_of, out_gid, out_batch, ins, energy):
    """ins: [(gid, qty_per_batch)]"""
    cum = 0.0; neg = 0; prof = []
    for t in range(MAX_TURN + 1):
        lv = LV[t]
        out_u = sum(out_batch * OUT_M[l] for l in lv)
        en = sum(energy * EN_M[l] for l in lv)
        lab = sum(LABOUR_L1 * LAB_M[l] for l in lv); mnt = sum(MAINT_L1 * MAINT_M[l] for l in lv)
        rev = out_u * dec_price(out_gid, t) * (1 + imp_of(out_gid, t) / 100) * (1 - adval(t))
        cost = en * GRID + lab + mnt
        for jgid, qty in ins:
            in_u = sum(qty * IN_M[l] for l in lv)
            cost += in_u * dec_price(jgid, t) * (1 + imp_of(jgid, t) / 100) * (1 + MARKUP)
        p = rev - cost; prof.append(p); cum += p
        if p < 0: neg += 1
    return prof, cum, neg

seeds = list(D["rivals"].keys())
CPS = [50, 100, 150, 200, 250, 300]
def msr(runs, gid): return [statistics.mean(r[0][gid][t] for r in runs) for t in range(MAX_TURN + 1)]
_, cb_steel, _ = pnl(lambda g, t: 0.0, STEEL, 54, [(II, 21), (H2, 5)], 140)
_, cb_motor, _ = pnl(lambda g, t: 0.0, MOT, 28, [(STEEL, 32), (CW, 32)], 30)

print("=== R7b BALANCED SAWTOOTH ambient ===")
amb = [run_r7(s, "saw2") for s in seeds]
st, so, mo = msr(amb, STEEL), msr(amb, SOL), msr(amb, MOT)
for n, s_ in [("steel", st), ("solar", so), ("motor", mo)]:
    print(f"  {n:<8}" + "".join(f"{s_[c]:>8.1f}" for c in CPS))
tot_ext = 0; pers = []; amps = []
for gid in producible:
    s_ = [amb[0][0][gid][t] for t in range(MAX_TURN + 1)]
    nc, per, amp = cycles(s_)
    tot_ext += nc
    if per: pers.append(per)
    if amp: amps.append(amp)
print(f"  CYCLES seed0 all goods: {tot_ext} extrema | median period {statistics.median(pers) if pers else 0:.0f}t | median swing {statistics.median(amps) if amps else 0:.0f}pp")
bk = statistics.mean(r[1] for r in amb); acq = statistics.mean(r[2] for r in amb); en = statistics.mean(r[3] for r in amb)
at300 = [statistics.mean(r[0][gid][300] for r in amb) for gid in producible]
print(f"  events: {bk:.0f} bk, {acq:.0f} acq, {en:.0f} entrants | mean|imp| t300 {statistics.mean(abs(v) for v in at300):.1f}%  >=30: {sum(1 for v in at300 if abs(v) >= 29)}")

print("\n=== steel PRODUCER under sawtooth ===")
spec = [run_r7(s, "saw2", player="steel") for s in seeds]
sp = msr(spec, STEEL)
w10 = sum(1 for t in range(MAX_TURN + 1) if sp[t] >= 10)
_, cum, neg = pnl(lambda g, t: statistics.mean(r[0][g][t] for r in spec), STEEL, 54, [(II, 21), (H2, 5)], 140)
print("  steel:  " + "".join(f"{sp[c]:>8.1f}" for c in CPS))
nc, per, amp = cycles([statistics.mean(r[0][STEEL][t] for r in spec) for t in range(MAX_TURN + 1)])
print(f"  window {w10}t | P&L {100*cum/cb_steel:.0f}% | neg-turns {neg} | cycles: {nc} extrema, period {per:.0f}t, swing {amp:.0f}pp")

print("\n=== MOTOR MAKER (consumes steel+wiring) ===")
for label, mode in [("balanced sawtooth", "saw2")]:
    mspec = [run_r7(s, mode, player="motor") for s in seeds]
    mm = msr(mspec, MOT); ms_ = msr(mspec, STEEL); mc = msr(mspec, CW)
    _, cum, neg = pnl(lambda g, t: statistics.mean(r[0][g][t] for r in mspec), MOT, 28, [(STEEL, 32), (CW, 32)], 30)
    print(f"  [{label}] motor: " + "".join(f"{mm[c]:>7.1f}" for c in CPS))
    print(f"  {'':<12} steel: " + "".join(f"{ms_[c]:>7.1f}" for c in CPS) + "   wiring: " + "".join(f"{mc[c]:>6.1f}" for c in [100, 200, 300]))
    print(f"  {'':<12} P&L {100*cum/cb_motor:.0f}% of baseline | neg-turns {neg}")
    if mode == "saw2":
        saw_out = {"motor": [round(x, 2) for x in mm], "steel_in": [round(x, 2) for x in ms_]}

json.dump({"amb_steel": [round(x,2) for x in st], "amb_solar": [round(x,2) for x in so],
           "amb_motor": [round(x,2) for x in mo],
           "amb_steel_s0": [round(amb[0][0][STEEL][t],2) for t in range(MAX_TURN+1)],
           "spec_steel": [round(x,2) for x in sp], "motor_saw": saw_out},
          open(f"{ROOT}/r7b.json", "w"))
print("\nwrote r7.json")
