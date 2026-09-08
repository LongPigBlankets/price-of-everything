#!/usr/bin/env python3
"""Model P - "banded equilibrium": the EA-shaped model scored against the owner's
8 principles. NO demand model. Changes vs the live accumulator:

  1. NPC flows count, but 75% of the STRUCTURAL imbalance is absorbed by world
     trade (beta = 0.75):   net = (player + rival sold) - (rival buys) - beta*nu*gamma(t)
  2. Thresholds scale with the market, floored at today's value:
     T(g,t) = max(base, 0.6 * base * gamma(t))
  3. Each band has a STABLE TARGET instead of a shared runaway cap:
     band(|net|/T):  <=1x -> 0   >1x -> +/-10   >2x -> +/-20   >4x -> +/-30   >10x -> +/-40
     impact move_toward(target, 0.5)/turn  (one speed; no separate recovery constant)
  4. Band chosen on a 5-turn EMA of net/T (kills boundary flapping).

Outputs: head-to-head (same build-out) for the 3 goods vs C; ambient (no player)
regime behaviour + stretch lengths; principle traces (1xL1 / 1xL3 / 2xL3 on a
balanced good); steel-specialist premium-erosion arc.
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
BAND_EDGES = [(10, 40.0), (4, 30.0), (2, 20.0), (1, 10.0)]  # (mult, |target|)
OUT_MULT = {1: 1.0, 2: 2.0, 3: 3.5}

def gamma(t): return 1.0 + 0.425 * (t // 5)
def q_at(seed, gid, i, t): return D["rivals"][str(seed)][gid][i][t // STEP]

nu = {}
for gid, g in goods.items():
    sold = g["base_output"] if gid in producible else 0
    bought = 0.0
    for cg in producible:
        cgd = goods[cg]; oq = cgd["base_recipe_output_qty"]
        if oq <= 0: continue
        for inp in cgd["base_recipe_inputs"]:
            if inp["good_id"] == gid:
                bought += inp["qty"] / oq * cgd["base_output"]
    nu[gid] = R_CT * (sold - bought)

def npc_flows(seed, gid):
    out = []
    for t in range(0, MAX_TURN + 1, STEP):
        sold = sum(q_at(seed, gid, i, t) for i in range(R_CT)) if gid in producible else 0
        bought = 0.0
        for cg in producible:
            g = goods[cg]; oq = g["base_recipe_output_qty"]
            if oq <= 0: continue
            for inp in g["base_recipe_inputs"]:
                if inp["good_id"] == gid:
                    bought += sum(q_at(seed, cg, i, t) for i in range(R_CT)) * inp["qty"] / oq
        out.append((sold, bought))
    return out

def target_for(ratio):
    for m, tgt in BAND_EDGES:
        if ratio > m: return tgt
    return 0.0

def sim_p(gid, player_sell, player_buy, seed):
    """player_sell/buy: arrays len 301. Returns (impact traj, target traj)."""
    g = goods[gid]; base = g["base_output"]
    flows = npc_flows(seed, gid)
    a = 0.0; ema = None; traj = []; tgts = []
    for t in range(MAX_TURN + 1):
        s, b = flows[t // STEP]
        net = (player_sell[t] + s) - (player_buy[t] + b) - BETA * nu[gid] * gamma(t)
        T = max(base, C_THR * base * gamma(t))
        r = net / T
        ema = r if ema is None else ema + (r - ema) / EMA_N
        tgt = target_for(abs(ema)) * (-1 if ema > 0 else 1)  # oversupply -> price down
        if abs(ema) <= 1: tgt = 0.0
        a += max(-SPEED, min(SPEED, tgt - a))
        traj.append(a); tgts.append(tgt)
    return traj, tgts

def player_units(batch):
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
        out.append(int(round(sum(batch * OUT_MULT[l] for l in levels))))
    return out

seeds = list(D["rivals"].keys())
ZERO = [0] * (MAX_TURN + 1)

# ---- 1. head-to-head for the three goods ----
H = json.load(open(f"{ROOT}/headtohead.json"))
FX = json.load(open(f"{ROOT}/fixes.json"))
out = {}
print("HEAD-TO-HEAD (same build-out), Model P impact % (mean 3 seeds):")
for gname in ["steel", "solar_panel", "lithium_battery"]:
    g = by_name[gname]; gid = g["id"]
    pu = player_units(g["base_recipe_output_qty"])
    runs = [sim_p(gid, pu, ZERO, s)[0] for s in seeds]
    mean = [statistics.mean(r[t] for r in runs) for t in range(MAX_TURN + 1)]
    amb_runs = [sim_p(gid, ZERO, ZERO, s)[0] for s in seeds]
    amb = [statistics.mean(r[t] for r in amb_runs) for t in range(MAX_TURN + 1)]
    p0, decay = g["base_price"], g["decay_rate"]
    dec = [p0 * ((1 - decay) ** max(0, t - 29)) for t in range(MAX_TURN + 1)]
    out[gname] = {"P": [round(x, 2) for x in mean], "P_ambient": [round(x, 2) for x in amb],
                  "price_P": [round(dec[t] * (1 + mean[t] / 100), 4) for t in range(MAX_TURN + 1)],
                  "price_amb": [round(dec[t] * (1 + amb[t] / 100), 4) for t in range(MAX_TURN + 1)]}
    cps = [50, 100, 150, 200, 250, 300]
    print(f"  {gname:<16} player: " + "".join(f"{mean[c]:>8.1f}" for c in cps))
    print(f"  {'':<16} ambient:" + "".join(f"{amb[c]:>8.1f}" for c in cps))

# ---- 2. ambient regime stretches across ALL goods ----
lens = []; moved_goods = 0
amb_targets = {}
for gid in producible:
    _, tg = sim_p(gid, ZERO, ZERO, seeds[0])
    amb_targets[goods[gid]["internal_name"]] = tg
    runs_ = []; cur = tg[20]; start = 20
    for t in range(21, MAX_TURN + 1):
        if tg[t] != cur:
            runs_.append(t - start); cur = tg[t]; start = t
    if runs_: moved_goods += 1; lens.extend(runs_)
print(f"\nAMBIENT REGIMES (no player, seed {seeds[0]}): {moved_goods}/{len(producible)} goods change target at least once after t20")
if lens:
    print(f"  stretch length between moves: median {statistics.median(lens):.0f} turns, "
          f"mean {statistics.mean(lens):.0f}, p25 {sorted(lens)[len(lens)//4]}, p75 {sorted(lens)[3*len(lens)//4]}")
amb_final = {n: tg[300] for n, tg in amb_targets.items()}
from collections import Counter
print("  ambient band targets at t300:", dict(sorted(Counter(amb_final.values()).items())))

# ---- 3. principle traces on a balanced good (rubber) ----
print("\nPRINCIPLE TRACES (rubber, nu~0): impact after standing output starts at t0:")
rub = by_name["rubber"]["id"]; rb = by_name["rubber"]["base_recipe_output_qty"]
for label, units, t0 in [("1x L1 (16/t) from t10", rb, 10), ("1x L3 (56/t) from t60", int(rb * 3.5), 60),
                         ("2x L3 (112/t) from t100", int(rb * 7), 100), ("6x L3 (336/t) from t150", int(rb * 21), 150)]:
    sched = [units if t >= t0 else 0 for t in range(MAX_TURN + 1)]
    runs = [sim_p(rub, sched, ZERO, s)[0] for s in seeds]
    m = [statistics.mean(r[t] for r in runs) for t in range(MAX_TURN + 1)]
    probe = min(t0 + 40, 300)
    print(f"  {label:<26} impact at t{probe}: {m[probe]:+.1f}%   at t300: {m[300]:+.1f}%")

# ---- 4. steel specialist: premium erosion arc ----
print("\nSTEEL SPECIALIST (build-out sells steel into the rivals' structural deficit):")
gid = by_name["steel"]["id"]
pu = player_units(54)
runs = [sim_p(gid, pu, ZERO, s)[0] for s in seeds]
m = [statistics.mean(r[t] for r in runs) for t in range(MAX_TURN + 1)]
for c in [30, 60, 100, 150, 200, 250, 300]:
    print(f"  t{c:<4} premium {m[c]:+.1f}%  (player {pu[c]}/t vs residual gap {abs(BETA*nu[gid])*gamma(c):.0f}/t)")

json.dump(out, open(f"{ROOT}/model_p.json", "w"))
print("\nwrote model_p.json")
