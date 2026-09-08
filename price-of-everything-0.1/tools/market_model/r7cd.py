#!/usr/bin/env python3
"""R7c/R7d — whipsaw demand + the integrated 3-chain player.

R7c: ALL goods saw with totals G~U(20,100)% over 20 turns, D~U(30,90)% over 10,
     plateau 10, staggered. Constant log-steps within each phase.
R7d: tiered — raw G20-40/D25-35, processed G20-50/D25-45, intermediate G20-75/D30-65,
     finished+apex G20-100/D30-90. Apex demand anchored to a notional market of
     9 x base x gamma(t) (rivals don't produce apex).
Base machinery: R6 event kit (R4 bands/lag5/exits/333/beta.75 + depreciation +
acquisitions + strict entrants).

INTEGRATED PLAYER: steel -> motors -> EVs. One action every 5 turns rotating
steel/motor/EV (so each chain steps every 15 turns: build,up,up,build,...,
starting t10/t15/t20). Internal feeding: motors eat own steel, EVs eat own
motors; surpluses sold, shortfalls + all other inputs bought at market.
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
impactable = [gid for gid, g in goods.items() if g["base_output"] > 0]
BETA, C_THR, SPEED, EMA_N = 0.75, 0.6, 0.5, 5
BAND_EDGES = [(10, 40.0), (4, 30.0), (2, 20.0), (1, 10.0)]
OUT_M = {1: 1.0, 2: 2.0, 3: 3.5}; IN_M = {1: 1.0, 2: 2.0, 3: 3.0}
EN_M = {1: 1.0, 2: 1.8, 3: 2.5}; LAB_M = {1: 1.0, 2: 1.5, 3: 2.0}; MAINT_M = {1: 1.0, 2: 1.8, 3: 2.5}
MARKUP, GRID = 0.05, 0.12
LABOUR_L1 = 1356 * 0.002 + 515 * 0.006 + 51 * 0.010
MAINT_L1 = 10.0
EXIT_HOLD, LAG, DELTA = 5, 5, 0.0075
P333 = [0]*3 + [.5]*3 + [1]*3
N = lambda n: by_name[n]["id"]
STEEL, MOT, EV = N("steel"), N("motor"), N("ev_car")
II, H2, CW = N("iron_ingots"), N("hydrogen"), N("copper_wiring")
EV_INPUTS = [(N("car_body"), 5), (N("motor"), 9), (N("glass"), 10), (N("tyres"), 19),
             (N("lithium_battery"), 6), (N("cpu"), 5)]
TIER_RANGES = {"raw": (0.20, 0.40, 0.25, 0.35), "processed": (0.20, 0.50, 0.25, 0.45),
               "intermediate": (0.20, 0.75, 0.30, 0.65), "finished": (0.20, 1.00, 0.30, 0.90),
               "apex": (0.20, 1.00, 0.30, 0.90)}

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

def demand_series(seed, gid, mode):
    g = goods[gid]
    if mode == "r7c": glo, ghi, dlo, dhi = 0.20, 1.00, 0.30, 0.90
    else: glo, ghi, dlo, dhi = TIER_RANGES[g["goods_graph_tier"]]
    rng = random.Random(int(seed) * 104729 + int(gid.split("_")[1]) * 271)
    offset = rng.randrange(40)
    M, out = 1.0, []
    gstep = dstep = 0.0
    for t in range(MAX_TURN + 1):
        ph = (t + offset) % 40
        if ph == 0: gstep = math.log(1 + rng.uniform(glo, ghi)) / 20
        if ph == 20: dstep = math.log(1 - rng.uniform(dlo, dhi)) / 10
        if ph < 20: M *= math.exp(gstep)
        elif ph < 30: M *= math.exp(dstep)
        out.append(M)
    return out

def chains_at():
    """Integrated 3-chain schedule: rotate steel/motor/ev, one action per 5 turns."""
    seqs = {"steel": [], "motor": [], "ev": []}
    order = ["steel", "motor", "ev"]
    counts = {k: 0 for k in order}
    hist = []
    t = 10
    while t <= 300:
        chain = order[(len(hist)) % 3]
        step_i = counts[chain]; counts[chain] += 1
        hist.append((t, chain, step_i))
        t += 5
    levels = {k: [] for k in order}
    out = {k: [] for k in order}
    hi = 0
    for t in range(MAX_TURN + 1):
        while hi < len(hist) and hist[hi][0] == t:
            _, chain, si = hist[hi]; hi += 1
            mod = si % 3
            if mod == 0: levels[chain].append(1)
            else: levels[chain][-1] = min(3, levels[chain][-1] + 1)
        for k in order:
            out[k].append(list(levels[k]))
    return out
CH = chains_at()
BATCH = {"steel": (STEEL, 54, [(II, 21), (H2, 5)], 140),
         "motor": (MOT, 28, [(STEEL, 32), (CW, 32)], 30),
         "ev": (EV, 5, EV_INPUTS, 20)}

def player_flows(t):
    """Returns pnet dict {gid: +sell/-buy} and production info for P&L."""
    prod = {}; need = defaultdict(float)
    for chain, (gid, batch, ins, en) in BATCH.items():
        lv = CH[chain][t]
        out_u = sum(batch * OUT_M[l] for l in lv)
        prod[chain] = out_u
        for jgid, qty in ins:
            need[jgid] += sum(qty * IN_M[l] for l in lv)
    pnet = defaultdict(float)
    steel_net = prod["steel"] - need[STEEL]; pnet[STEEL] += steel_net
    mot_net = prod["motor"] - need[MOT]; pnet[MOT] += mot_net
    pnet[EV] += prod["ev"]
    for jgid, amt in need.items():
        if jgid in (STEEL, MOT): continue
        pnet[jgid] -= amt
    return dict(pnet), prod, dict(need)

def run(seed, mode, player=False):
    inc = {gid: [[D["rivals"][str(seed)][gid][i][b] - D["rivals"][str(seed)][gid][i][b - 1]
                  for b in range(1, 61)] for i in range(R_CT)] for gid in producible}
    q = {gid: [float(goods[gid]["base_output"])] * R_CT for gid in producible}
    active = {gid: [True] * R_CT for gid in producible}
    Mdem = {gid: demand_series(seed, gid, mode) for gid in impactable}
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
                    seller = min(cands, key=lambda i: q[gid][i]); buyer = max(cands, key=lambda i: q[gid][i])
                    if seller != buyer:
                        q[gid][buyer] += q[gid][seller] * 0.5
                        q[gid][seller] = 0.0; active[gid][seller] = False
                        n_acq += 1; cd_acq[gid] = 15; dis_cnt[gid] = 0
            if low_cnt[gid] >= 15:
                for i in range(len(active[gid])):
                    if active[gid][i] and q[gid][i] <= base * 1.05:
                        active[gid][i] = False; q[gid][i] = 0.0; n_bk += 1; low_cnt[gid] = 0
                        break
            if (hi30[gid] >= 5 or hi40[gid] >= 2) and cd_en[gid] <= 0:
                placed = False
                for i in range(len(active[gid])):
                    if not active[gid][i]:
                        active[gid][i] = True; q[gid][i] = float(base); placed = True; break
                if not placed and len(active[gid]) < 12:
                    active[gid].append(True); q[gid].append(float(base))
                    inc[gid].append(inc[gid][len(active[gid]) % R_CT]); placed = True
                if placed: n_en += 1; cd_en[gid] = 10; hi30[gid] = 0; hi40[gid] = 0
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
        pnet = player_flows(t)[0] if player else {}
        for gid, g in goods.items():
            base = g["base_output"]
            if base <= 0:
                traj[gid].append(0.0); continue
            anchor = sold.get(gid, 0) if gid in producible else 9 * base * gamma(t)
            dem = (Mdem[gid][t] - 1) * BETA * anchor if gid in Mdem else 0.0
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

def pnl_integrated(imp_of):
    cum = 0.0; neg = 0; prof = []
    for t in range(MAX_TURN + 1):
        pnet, prod, need = player_flows(t)
        rev = cost = 0.0
        for gid, amt in pnet.items():
            p = dec_price(gid, t) * (1 + imp_of(gid, t) / 100)
            if amt > 0: rev += amt * p * (1 - adval(t))
            else: cost += -amt * p * (1 + MARKUP)
        for chain, (gid, batch, ins, en) in BATCH.items():
            lv = CH[chain][t]
            cost += sum(en * EN_M[l] for l in lv) * GRID
            cost += sum(LABOUR_L1 * LAB_M[l] for l in lv) + sum(MAINT_L1 * MAINT_M[l] for l in lv)
        p = rev - cost; prof.append(p); cum += p
        if p < 0: neg += 1
    return prof, cum, neg

seeds = list(D["rivals"].keys())
CPS = [50, 100, 150, 200, 250, 300]
def msr(runs, gid): return [statistics.mean(r[0][gid][t] for r in runs) for t in range(MAX_TURN + 1)]
_, cum_base, _ = pnl_integrated(lambda g, t: 0.0)
out = {}
R7B = json.load(open(f"{ROOT}/r7b.json"))

for mode in ["r7c", "r7d"]:
    print(f"\n=== {mode.upper()} ambient ===")
    amb = [run(s, mode) for s in seeds]
    st = msr(amb, STEEL)
    demM = statistics.mean(demand_series(seeds[0], gid, mode)[300] for gid in producible)
    st0 = [amb[0][0][STEEL][t] for t in range(MAX_TURN + 1)]
    nc, per, amp = cycles(st0)
    vol = statistics.pstdev(st0[20:])
    print(f"  steel: " + "".join(f"{st[c]:>8.1f}" for c in CPS))
    print(f"  steel seed0: {nc} extrema, period {per:.0f}t, swing {amp:.0f}pp, std {vol:.1f}pp")
    tot_ext = sum(cycles([amb[0][0][gid][t] for t in range(MAX_TURN + 1)])[0] for gid in producible)
    at300 = [statistics.mean(r[0][gid][300] for r in amb) for gid in producible]
    bk = statistics.mean(r[1] for r in amb); acq = statistics.mean(r[2] for r in amb); en = statistics.mean(r[3] for r in amb)
    print(f"  ALL goods seed0 extrema: {tot_ext} | mean|imp| t300 {statistics.mean(abs(v) for v in at300):.1f}% | mean demand mult t300 {demM:.2f}")
    print(f"  events: {bk:.0f} bk, {acq:.0f} acq, {en:.0f} entrants")
    if mode == "r7d":
        for tier in ["raw", "processed", "intermediate", "finished", "apex"]:
            tg = [gid for gid in impactable if goods[gid]["goods_graph_tier"] == tier]
            vals = [statistics.mean(r[0][g][300] for r in amb) for g in tg]
            exs = [cycles([amb[0][0][g][t] for t in range(MAX_TURN + 1)])[0] for g in tg if g in producible]
            print(f"    {tier:<13} t300 mean {statistics.mean(vals):+6.1f}%  extrema/good {statistics.mean(exs) if exs else 0:.1f}")
    ev0 = [amb[0][0][EV][t] for t in range(MAX_TURN + 1)]
    nc2, per2, amp2 = cycles(ev0)
    print(f"  ev_car (apex, ambient): {nc2} extrema, period {per2:.0f}t, swing {amp2:.0f}pp")
    out[mode + "_amb"] = {"steel": [round(x, 2) for x in st],
                          "steel_s0": [round(x, 2) for x in st0],
                          "ev_s0": [round(x, 2) for x in ev0],
                          "ore_s0": [round(amb[0][0][N('iron_ore')][t], 2) for t in range(MAX_TURN + 1)]}
    print(f"  --- integrated 3-chain player under {mode.upper()} ---")
    ply = [run(s, mode, player=True) for s in seeds]
    imp_of = lambda g, t: statistics.mean(r[0][g][t] for r in ply)
    prof, cum, neg = pnl_integrated(imp_of)
    stp, mop, evp = msr(ply, STEEL), msr(ply, MOT), msr(ply, EV)
    print(f"  steel: " + "".join(f"{stp[c]:>7.1f}" for c in CPS))
    print(f"  motor: " + "".join(f"{mop[c]:>7.1f}" for c in CPS))
    print(f"  ev:    " + "".join(f"{evp[c]:>7.1f}" for c in CPS))
    print(f"  P&L £{cum:,.0f} ({100*cum/cum_base:.0f}% of impact-free baseline £{cum_base:,.0f}) | loss turns {neg}")
    out[mode + "_player"] = {"steel": [round(x, 2) for x in stp], "motor": [round(x, 2) for x in mop],
                             "ev": [round(x, 2) for x in evp], "pnl_pct": round(100 * cum / cum_base),
                             "neg": neg}

# R7b steel volatility reference
st_b = R7B["amb_steel"]
print(f"\nR7b reference: steel ambient std {statistics.pstdev(st_b[20:]):.1f}pp")
json.dump(out, open(f"{ROOT}/r7cd.json", "w"))
print("wrote r7cd.json")
