#!/usr/bin/env python3
"""Model Q — bandless P (owner spec 2026-08-12):

- NO band targets. Impact DRIFTS 0.5%/turn against the pressure whenever the
  smoothed |net/T| exceeds the 1x dead zone; inside it, decays 0.5/turn to 0.
  Hard cap +/-60%.
- GLOBAL-DEMAND stabiliser per good, state E (starts 0, clamp +/-2):
    impact <= -40  (price < 60% of base): E += 0.05/turn   (world buys the bargain)
    impact >= +60  (price at the cap):    E -= 0.05/turn   (demand destruction)
    else E decays 0.05/turn toward 0.
  Extra world demand = E x T units/turn: effective_net = player + (1-b)npc - E*T.
- Rival responsiveness scales with the same state: deviation x clamp(1+E, .5, 3)
  (stronger when goods are dirt-cheap, weaker at the price ceiling).
- Everything else = R4 config: R3 ladders, lag 5, exits (<=-20 held 5), 3/3/3,
  beta0 0.75 on NPC flows.
Compare vs Model P (cap40 bands, lag 5, 3/3/3 - the cap60_sweep cap40_b0.75 runs).
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
CAP = 60.0
OUT_M = {1: 1.0, 2: 2.0, 3: 3.5}; IN_M = {1: 1.0, 2: 2.0, 3: 3.0}
EN_M = {1: 1.0, 2: 1.8, 3: 2.5}; LAB_M = {1: 1.0, 2: 1.5, 3: 2.0}; MAINT_M = {1: 1.0, 2: 1.8, 3: 2.5}
MARKUP, GRID = 0.05, 0.12
LABOUR_L1 = 1356 * 0.002 + 515 * 0.006 + 51 * 0.010
MAINT_L1 = 10.0
STEEL, II, H2 = by_name["steel"]["id"], by_name["iron_ingots"]["id"], by_name["hydrogen"]["id"]
SOL = by_name["solar_panel"]["id"]
EXIT_HOLD, LAG = 5, 5
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

def run_q(seed, player=None):
    inc = {gid: [[D["rivals"][str(seed)][gid][i][b] - D["rivals"][str(seed)][gid][i][b - 1]
                  for b in range(1, 61)] for i in range(R_CT)] for gid in producible}
    q = {gid: [goods[gid]["base_output"]] * R_CT for gid in producible}
    imp = defaultdict(float); ema = {}; E = defaultdict(float)
    out_dir = defaultdict(int); out_cnt = defaultdict(int)
    in_dir = defaultdict(int); in_cnt = defaultdict(int)
    exit_cnt = defaultdict(int)
    traj = defaultdict(list); e_traj = defaultdict(list)
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
            # global-demand stabiliser state
            if imp.get(gid, 0.0) <= -40.0: E[gid] = min(2.0, E[gid] + 0.05)
            elif imp.get(gid, 0.0) >= CAP - 0.5: E[gid] = max(-2.0, E[gid] - 0.05)
            else: E[gid] = E[gid] - math.copysign(min(0.05, abs(E[gid])), E[gid]) if E[gid] != 0 else 0.0
        if t > 0 and t % STEP == 0:
            b = t // STEP - 1
            for gid in producible:
                go = out_mag(imp.get(gid, 0.0)) if out_cnt[gid] >= LAG else 1.0
                gi = in_mag(in_dev(gid)) if in_cnt[gid] >= LAG else 1.0
                G_full = max(0.25, min(2.5, go * gi))
                rs = max(0.5, min(3.0, 1.0 + E[gid]))   # responsiveness scale
                exiting = exit_cnt[gid] >= EXIT_HOLD
                for i in range(R_CT):
                    if b >= len(inc[gid][i]): continue
                    s = P333[i]
                    if exiting and s > 0:
                        cut = int(round(inc[gid][i][b] * s * rs))
                        q[gid][i] = max(goods[gid]["base_output"], q[gid][i] - cut)
                    else:
                        Gr = 1 + (G_full - 1) * s * rs if s > 0 else 1.0
                        Gr = max(0.25, min(2.5, Gr))
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
            T = max(base, C_THR * base * gamma(t))
            net = pnet.get(gid, 0) + (1 - BETA) * (sold.get(gid, 0) - bought.get(gid, 0.0)) - E[gid] * T
            r = net / T
            ema[gid] = r if gid not in ema else ema[gid] + (r - ema[gid]) / EMA_N
            e = ema[gid]
            a = imp[gid]
            if abs(e) > 1.0:
                a += -SPEED if e > 0 else SPEED
            else:
                a = a - math.copysign(min(SPEED, abs(a)), a) if a != 0 else 0.0
            imp[gid] = max(-CAP, min(CAP, a))
            traj[gid].append(imp[gid])
            e_traj[gid].append(E[gid])
    return traj, sold, e_traj

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

amb = [run_q(s)[0] for s in seeds]
spec = [run_q(s, "steel")[0] for s in seeds]
dump = [run_q(s, "solar")[0] for s in seeds]
st_a, so_a, hy_a = msr(amb, STEEL), msr(amb, SOL), msr(amb, H2)
sp, sd = msr(spec, STEEL), msr(dump, SOL)

print("MODEL Q ambient (3 seeds):")
for n, s in [("steel", st_a), ("solar", so_a), ("hydrogen", hy_a)]:
    print(f"  {n:<10}" + "".join(f"{s[c]:>8.1f}" for c in CPS))
at300 = [statistics.mean(r[gid][300] for r in amb) for gid in producible]
full = [msr(amb, gid) for gid in producible]
amps = [max(f[20:]) - min(f[20:]) for f in full]
at_cap_time = [sum(1 for t in range(20, MAX_TURN + 1) if abs(f[t]) >= CAP - 0.5) for f in full]
tr0 = amb[0]; reversals = 0
for gid in producible:
    x = tr0[gid]; last = 0
    for t in range(21, MAX_TURN + 1):
        d = x[t] - x[t - 1]
        dirn = 1 if d > 0.01 else (-1 if d < -0.01 else 0)
        if dirn != 0 and last != 0 and dirn != last: reversals += 1
        if dirn != 0: last = dirn
print(f"  mean|imp| t300 {statistics.mean(abs(v) for v in at300):.1f}%  >=30:{sum(1 for v in at300 if abs(v)>=29)}  "
      f">=45:{sum(1 for v in at300 if abs(v)>=44)}  at-cap goods:{sum(1 for v in at300 if abs(v)>=CAP-0.5)}")
print(f"  swing amplitude (max-min, t20+): median {statistics.median(amps):.0f}pp  p90 {sorted(amps)[int(len(amps)*.9)]:.0f}pp")
print(f"  turns spent at |60| cap: median {statistics.median(at_cap_time):.0f}  max {max(at_cap_time)}")
print(f"  reversals/good {reversals/len(producible):.1f}")

w10 = sum(1 for t in range(MAX_TURN + 1) if sp[t] >= 10)
prof, cum, neg = pnl_steel(lambda g, t: statistics.mean(r[g][t] for r in spec))
print(f"\nQ steel specialist: " + "".join(f"{sp[c]:>8.1f}" for c in CPS))
print(f"  window>=+10 {w10}t  peak {max(sp):.1f}  trough {min(sp):.1f}  P&L £{cum:,.0f} ({100*cum/cum_base:.0f}%)  neg-turns {neg}")
print(f"Q solar dumper:     " + "".join(f"{sd[c]:>8.1f}" for c in CPS))

CAP40 = json.load(open(f"{ROOT}/cap60.json"))["cap40_b0.75"]
print(f"\nP reference (cap40 b0.75): spec window 29t, P&L 68%; ambient mean|imp| 9.5%")

json.dump({"amb_steel": [round(x,2) for x in st_a], "amb_solar": [round(x,2) for x in so_a],
           "spec": [round(x,2) for x in sp], "dump": [round(x,2) for x in sd],
           "P_amb_steel": CAP40["amb_steel"], "P_amb_solar": CAP40["amb_solar"], "P_spec": CAP40["spec"]},
          open(f"{ROOT}/model_q.json", "w"))
print("wrote model_q.json")
