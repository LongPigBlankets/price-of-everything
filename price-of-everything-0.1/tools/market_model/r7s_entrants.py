#!/usr/bin/env python3
"""R7m = R7l (beta 0.50) + two owner features:

1. APEX COMPETITION FROM ERA 2: apex goods start rival-free; from t>100 the
   entrant triggers (+10x5t / +20x2t) can place era-sized entrants (5/8/12x in
   era 2, 15/25/40x in era 3) with synthetic seeded growth streams. Apex rivals
   consume their recipe inputs (EV rivals buy motors, batteries, ...) and are
   subject to depreciation / exits / acquisitions / bankruptcy like anyone.
2. MARKET-DISRUPTION WINDOW: every entrant's output counts at FULL weight
   (bypassing the beta absorption) for its first 12 turns -- world trade takes
   time to re-route around a sudden domestic supplier. This is the below-base
   bust driver: the boom invites a titan, the titan crashes the price.

Metrics add: below-base time share and trough depth (p10) per tier.
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
apex_traded = [gid for gid in impactable if gid not in producible]
traded = producible + apex_traded
APEX = set(apex_traded)
C_THR, SPEED, EMA_N = 0.6, 2.5, 5
BAND_EDGES = [(30, 40.0), (18, 35.0), (11, 30.0), (6.9, 25.0), (4.2, 20.0), (2.6, 15.0), (1.6, 10.0), (1, 5.0)]
LADDERS = {
  'steady':    [(30,24.0),(18,21.0),(11,18.0),(6.9,15.0),(4.2,12.0),(2.6,9.0),(1.6,6.0),(1,3.0)],
  'standard':  [(30,40.0),(18,35.0),(11,30.0),(6.9,25.0),(4.2,20.0),(2.6,15.0),(1.6,10.0),(1,5.0)],
  'turbulent': [(20,60.0),(13,52.0),(8.5,44.0),(5.5,36.0),(3.5,28.0),(2.2,20.0),(1.4,13.0),(1,7.0)],
}
OUT_M = {1: 1.0, 2: 2.0, 3: 3.5}; IN_M = {1: 1.0, 2: 2.0, 3: 3.0}
EN_M = {1: 1.0, 2: 1.8, 3: 2.5}; LAB_M = {1: 1.0, 2: 1.5, 3: 2.0}; MAINT_M = {1: 1.0, 2: 1.8, 3: 2.5}
MARKUP, GRID = 0.05, 0.12
LABOUR_L1 = 1356 * 0.002 + 515 * 0.006 + 51 * 0.010
MAINT_L1 = 10.0
EXIT_HOLD, LAG, DELTA = 10, 5, 0.0075
DISRUPT = 12
P333 = [0]*3 + [.5]*3 + [1]*3
N = lambda n: by_name[n]["id"]
STEEL, MOT, EV = N("steel"), N("motor"), N("ev_car")
II, H2, CW = N("iron_ingots"), N("hydrogen"), N("copper_wiring")
EV_INPUTS = [(N("car_body"), 5), (N("motor"), 9), (N("glass"), 10), (N("tyres"), 19),
             (N("lithium_battery"), 6), (N("cpu"), 5)]
TIER_RANGES = {"raw": (0.20, 0.40, 0.25, 0.35), "processed": (0.20, 0.50, 0.25, 0.45),
               "intermediate": (0.20, 0.75, 0.30, 0.65), "finished": (0.20, 1.00, 0.30, 0.90),
               "apex": (0.20, 1.00, 0.30, 0.90)}
FRAC_RANGES = {"raw": (0.85, 1.15), "processed": (0.75, 1.25), "intermediate": (0.65, 1.35),
               "finished": (0.55, 1.45), "apex": (0.50, 1.50)}

def gamma(t): return 1.0 + 0.425 * (t // 5)
def adval(t): return 0.005 if t < 31 else 0.03
def out_mag(d):
    if d >= 5: return 1.3
    if d <= -10: return 0.5
    if d <= -5: return 0.75
    return 1.0
def in_mag(d):
    if d <= -0.12: return 1.3
    if d >= 0.25: return 0.5
    if d >= 0.12: return 0.75
    return 1.0

consumers = defaultdict(list); inputs_of = {}
for gid in traded:
    g = goods[gid]; oq = g["base_recipe_output_qty"]
    inputs_of[gid] = []
    if oq <= 0: continue
    for inp in g["base_recipe_inputs"]:
        consumers[inp["good_id"]].append((gid, inp["qty"] / oq))
        inputs_of[gid].append((inp["good_id"], inp["qty"]))

def demand_series(seed, gid, fscale=1.0):
    g = goods[gid]
    glo, ghi, _, _ = TIER_RANGES[g["goods_graph_tier"]]
    flo, fhi = FRAC_RANGES[g["goods_graph_tier"]]
    rng = random.Random(int(seed) * 104729 + int(gid.split("_")[1]) * 271)
    offset = rng.randrange(40)
    M, out = 1.0, []
    gstep = dstep = boom_log = 0.0
    for t in range(MAX_TURN + 1):
        ph = (t + offset) % 40
        if ph == 0:
            boom_log = math.log(1 + rng.uniform(glo, ghi)); gstep = boom_log / 20
        if ph == 20: dstep = -boom_log * rng.uniform(flo, fhi) * fscale / 10
        if ph < 20: M *= math.exp(gstep)
        elif ph < 30: M *= math.exp(dstep)
        out.append(M)
    return out

def chains_at():
    order = ["steel", "motor", "ev"]
    counts = {k: 0 for k in order}
    hist = []
    t = 10
    while t <= 300:
        chain = order[len(hist) % 3]
        hist.append((t, chain, counts[chain])); counts[chain] += 1
        t += 5
    levels = {k: [] for k in order}
    out = {k: [] for k in order}
    hi = 0
    for t in range(MAX_TURN + 1):
        while hi < len(hist) and hist[hi][0] == t:
            _, chain, si = hist[hi]; hi += 1
            if si % 3 == 0: levels[chain].append(1)
            else: levels[chain][-1] = min(3, levels[chain][-1] + 1)
        for k in order:
            out[k].append(list(levels[k]))
    return out
CH = chains_at()
BATCH = {"steel": (STEEL, 54, [(II, 21), (H2, 5)], 140),
         "motor": (MOT, 28, [(STEEL, 32), (CW, 32)], 30),
         "ev": (EV, 5, EV_INPUTS, 20)}

def player_flows(t):
    prod = {}; need = defaultdict(float)
    for chain, (gid, batch, ins, en) in BATCH.items():
        lv = CH[chain][t]
        prod[chain] = sum(batch * OUT_M[l] for l in lv)
        for jgid, qty in ins:
            need[jgid] += sum(qty * IN_M[l] for l in lv)
    pnet = defaultdict(float)
    pnet[STEEL] += prod["steel"] - need[STEEL]
    pnet[MOT] += prod["motor"] - need[MOT]
    pnet[EV] += prod["ev"]
    for jgid, amt in need.items():
        if jgid in (STEEL, MOT): continue
        pnet[jgid] -= amt
    return dict(pnet), prod, dict(need)

ENTRANT = {'eager': (8, 3, 15, 2, 6), 'standard': (10, 5, 20, 2, 10), 'patient': (15, 8, 25, 3, 15)}
PERSONAS = {'dramatic': [0]*4+[.5]*3+[1]*2, 'balanced': [0]*3+[.5]*3+[1]*3, 'disciplined': [0]*2+[.5]*3+[1]*4}
def run(seed, player=False, BETA=0.5, ladder='standard', lag=None, entrant='standard',
        personas='balanced', demand='cyclical', apex_from=100, budget=None):
    BAND_EDGES = LADDERS[ladder]
    LAG_L = LAG if lag is None else lag
    E_A, E_AT, E_B, E_BT, E_CD = ENTRANT[entrant]
    PERS = PERSONAS[personas]
    BAND_EDGES = LADDERS[ladder]
    LAG_L = LAG if lag is None else lag
    inc = {gid: [[D["rivals"][str(seed)][gid][i][b] - D["rivals"][str(seed)][gid][i][b - 1]
                  for b in range(1, 61)] for i in range(R_CT)] for gid in producible}
    for gid in apex_traded: inc[gid] = []
    q = {gid: [float(goods[gid]["base_output"])] * R_CT for gid in producible}
    for gid in apex_traded: q[gid] = []
    active = {gid: [True] * R_CT for gid in producible}
    for gid in apex_traded: active[gid] = []
    win = {gid: [0] * len(q[gid]) for gid in traded}
    Mdem = ({gid: [1.0]*(MAX_TURN+1) for gid in impactable} if demand == 'flat'
            else {gid: demand_series(seed, gid, 0.70 if demand == 'boom' else 1.0)
                  for gid in impactable})
    imp = defaultdict(float); ema = {}
    out_dir = defaultdict(int); out_cnt = defaultdict(int)
    in_dir = defaultdict(int); in_cnt = defaultdict(int)
    exit_cnt = defaultdict(int); dis_cnt = defaultdict(int); low_cnt = defaultdict(int)
    hi10 = defaultdict(int); hi20 = defaultdict(int)
    cd_acq = defaultdict(int); cd_en = defaultdict(int)
    traj = defaultdict(list); n_bk = n_acq = n_en = 0; n_en_apex = 0; first_apex = None
    budget_left = budget if budget is not None else 10**9
    exhausted_at = None; ent_by_tier = defaultdict(int); ent_turns = []
    def in_dev(gid):
        ins = inputs_of.get(gid, [])
        if not ins: return 0.0
        ws = dv = 0.0
        for j, qty in ins:
            pj = goods[j]["base_price"] * (1 + imp.get(j, 0.0) / 100)
            ws += pj * qty; dv += pj * qty * imp.get(j, 0.0) / 100
        return dv / ws if ws > 0 else 0.0
    for t in range(MAX_TURN + 1):
        for gid in traded:
            cd_acq[gid] = max(0, cd_acq[gid] - 1); cd_en[gid] = max(0, cd_en[gid] - 1)
            d_o = imp.get(gid, 0.0)
            s_o = 1 if d_o >= 5 else (-1 if d_o <= -5 else 0)
            out_cnt[gid] = out_cnt[gid] + 1 if s_o == out_dir[gid] and s_o != 0 else (1 if s_o != 0 else 0)
            out_dir[gid] = s_o
            d_i = in_dev(gid)
            s_i = 1 if d_i >= 0.12 else (-1 if d_i <= -0.12 else 0)
            in_cnt[gid] = in_cnt[gid] + 1 if s_i == in_dir[gid] and s_i != 0 else (1 if s_i != 0 else 0)
            in_dir[gid] = s_i
            exit_cnt[gid] = exit_cnt[gid] + 1 if d_o <= -15 else 0
            dis_cnt[gid] = dis_cnt[gid] + 1 if d_o <= -15 else 0
            low_cnt[gid] = low_cnt[gid] + 1 if d_o <= -15 else 0
            hi10[gid] = hi10[gid] + 1 if d_o >= E_A else 0
            hi20[gid] = hi20[gid] + 1 if d_o >= E_B else 0
        for gid in traded:
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
            allow_entry = (gid not in APEX) or (apex_from >= 0 and t > apex_from)
            if allow_entry and budget_left > 0 and (hi10[gid] >= E_AT or hi20[gid] >= E_BT) and cd_en[gid] <= 0:
                rng_e = random.Random(int(seed) * 31 + int(gid.split("_")[1]) * 17 + t)
                mult = rng_e.choice((1, 2, 3) if t <= 100 else ((5, 8, 12) if t <= 200 else (15, 25, 40)))
                size = float(base * mult)
                slot = None
                for i in range(len(active[gid])):
                    if not active[gid][i]: slot = i; break
                if slot is None and len(active[gid]) < 12:
                    active[gid].append(True); q[gid].append(0.0); win[gid].append(0)
                    if gid in APEX or len(inc[gid]) < len(active[gid]):
                        rng_s = random.Random(int(seed) * 53 + int(gid.split("_")[1]) * 7 + len(active[gid]))
                        inc[gid].append([base * rng_s.choice([0, .2, .5, 1.0]) for _ in range(60)])
                    slot = len(active[gid]) - 1
                if slot is not None:
                    active[gid][slot] = True; q[gid][slot] = size; win[gid][slot] = t + DISRUPT
                    n_en += 1; cd_en[gid] = E_CD; hi10[gid] = 0; hi20[gid] = 0
                    budget_left -= 1; ent_by_tier[goods[gid]['goods_graph_tier']] += 1
                    ent_turns.append(t)
                    if budget_left == 0 and exhausted_at is None: exhausted_at = t
                    if gid in APEX:
                        n_en_apex += 1
                        if first_apex is None: first_apex = t
        if t > 0 and t % STEP == 0:
            b = t // STEP - 1
            for gid in traded:
                go = out_mag(imp.get(gid, 0.0)) if out_cnt[gid] >= LAG_L else 1.0
                gi = in_mag(in_dev(gid)) if in_cnt[gid] >= LAG_L else 1.0
                G_full = max(0.25, min(2.5, go * gi))
                exiting = exit_cnt[gid] >= EXIT_HOLD
                base = goods[gid]["base_output"]
                for i in range(len(active[gid])):
                    if not active[gid][i] or b >= len(inc[gid][i]): continue
                    s = PERS[i % R_CT] if (gid not in APEX and i < R_CT) else 1.0
                    if exiting and s > 0:
                        q[gid][i] = max(base * 0.5, q[gid][i] - inc[gid][i][b] * s)
                    else:
                        Gr = 1 + (G_full - 1) * s if s > 0 else 1.0
                        q[gid][i] += inc[gid][i][b] * Gr
        sold = {gid: sum(qq for qq, a in zip(q[gid], active[gid]) if a) for gid in traded}
        disrupted = {gid: sum(qq for qq, a, w in zip(q[gid], active[gid], win[gid]) if a and w > t)
                     for gid in traded}
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
            dem = (Mdem[gid][t] - 1) * anchor if gid in Mdem else 0.0
            net = (pnet.get(gid, 0) + (1 - BETA) * (sold.get(gid, 0) - bought.get(gid, 0.0))
                   + BETA * disrupted.get(gid, 0.0) - dem)
            T = 9.0 * base
            r = net / T
            ema[gid] = r if gid not in ema else ema[gid] + (r - ema[gid]) / EMA_N
            e = ema[gid]
            tgt = 0.0
            if abs(e) > 1:
                for m, tg in BAND_EDGES:
                    if abs(e) > m: tgt = tg * (-1 if e > 0 else 1); break
            imp[gid] += max(-SPEED, min(SPEED, tgt - imp[gid]))
            traj[gid].append(imp[gid])
    return traj, n_bk, n_acq, n_en, n_en_apex, first_apex, exhausted_at, dict(ent_by_tier), ent_turns

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
    cum = 0.0; neg = 0
    for t in range(MAX_TURN + 1):
        pnet, _, _ = player_flows(t)
        rev = cost = 0.0
        for gid, amt in pnet.items():
            p = dec_price(gid, t) * (1 + imp_of(gid, t) / 100)
            if amt > 0: rev += amt * p * (1 - adval(t))
            else: cost += -amt * p * (1 + MARKUP)
        for chain, (gid, batch, ins, en) in BATCH.items():
            lv = CH[chain][t]
            cost += sum(en * EN_M[l] for l in lv) * GRID
            cost += sum(LABOUR_L1 * LAB_M[l] for l in lv) + sum(MAINT_L1 * MAINT_M[l] for l in lv)
        p = rev - cost; cum += p
        if p < 0: neg += 1
    return cum, neg

seeds = list(D["rivals"].keys())
def msr(runs, gid): return [statistics.mean(r[0][gid][t] for r in runs) for t in range(MAX_TURN + 1)]
cum_base, _ = pnl_integrated(lambda g, t: 0.0)
mid = [g for g in impactable if goods[g]["goods_graph_tier"] in ("intermediate", "finished")]

def profile(label, **kw):
    amb = [run(s, **kw) for s in seeds]
    ply = [run(s, player=True, **kw) for s in seeds]
    imp_of = lambda g, t: statistics.mean(r[0][g][t] for r in ply)
    cum, neg = pnl_integrated(imp_of)
    apex_std = statistics.mean(statistics.pstdev([amb[0][0][g][t] for t in range(20, MAX_TURN + 1)])
                               for g in impactable if goods[g]["goods_graph_tier"] == "apex")
    rng = statistics.mean(max(amb[0][0][g][20:]) - min(amb[0][0][g][20:]) for g in mid)
    below = statistics.mean(sum(1 for t in range(20, 301) if amb[0][0][g][t] < -2) / 281 for g in mid) * 100
    above = statistics.mean(sum(1 for t in range(20, 301) if amb[0][0][g][t] > 2) / 281 for g in mid) * 100
    ext = sum(cycles([amb[0][0][g][t] for t in range(MAX_TURN + 1)])[0] for g in impactable)
    acq = statistics.mean(r[2] for r in amb); en = statistics.mean(r[3] for r in amb)
    steel = statistics.mean(msr(amb, STEEL)[20:])
    exh = [r[6] for r in amb if r[6] is not None]
    exh_s = f"t{statistics.mean(exh):.0f}" if exh else "never"
    tiers = defaultdict(int)
    for r in amb:
        for k, v in r[7].items(): tiers[k] += v / len(amb)
    tier_s = " ".join(f"{k[:4]}{v:.0f}" for k, v in sorted(tiers.items(), key=lambda x: -x[1])[:3])
    print(f"{label:<22} ent {en:5.0f} | spent by {exh_s:>6} | acq {acq:4.0f} | {above:3.0f}%up/{below:3.0f}%dn"
          f" | apexσ {apex_std:4.1f} | range {rng:5.1f} | steel {steel:+5.1f} | P&L {100*cum/cum_base:4.0f}% ({neg} loss) | {tier_s}")
    return {"ent": round(en), "exhausted": exh_s, "acq": round(acq), "above": round(above), "below": round(below),
            "apex_std": round(apex_std,1), "mid_range": round(rng,1), "steel": round(steel,1),
            "pnl": round(100*cum/cum_base), "neg": neg, "ext": ext,
            "ev_s0": [round(amb[0][0][EV][t],2) for t in range(MAX_TURN+1)]}

out = {}
print("=== NATIONAL ENTRANT BUDGET (total new entrants per 300-turn run, all goods) ===")
for b in [10, 20, 50, 100, 150, 200, None]:
    lbl = f"  budget {b}" if b else "  uncapped (=179)"
    out["budget_" + str(b)] = profile(lbl, budget=b)
json.dump(out, open(f"{ROOT}/r7s.json", "w"))
print("wrote r7s.json")
