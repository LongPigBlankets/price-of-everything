#!/usr/bin/env python3
"""The two 'real fixes', run through the same head-to-head as C/V1-V4.

N - NETTED ACCUMULATOR (minimal change to the live model):
    Keep bands/rates/cap/recovery exactly as today. Two changes:
      1. net(g) = (player_sold + npc_sold) - (player_bought + npc_bought) - nu_g*gamma(t)
         (subtract the EXPECTED NPC net flow: trade closure - exports absorb the
          expected surplus, imports the expected shortfall)
      2. threshold base scales with the world: T_g(t) = base_g * gamma(t)
    So bands measure "how far does total volume deviate from the expected market,
    relative to the market's current size". Player-only + noise is what remains.

R - FULL RATIO (Plate VI, now with the player's build-out):
    S = npc_sold + max(0,-nu)*gamma + player_sold
    D = npc_bought + max(0,+nu)*gamma + player_bought
    target = clamp((D/S)^k, 0.6..1.4), k=0.65; mult moves toward target <=1.5%/turn.
    impact_pct = (mult-1)*100.

Same player schedule, same 3 goods, mean of 3 seeds. Both keep +/-40% band.
"""
import json, math, statistics
from collections import defaultdict

import os
ROOT = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(f"{ROOT}/npc_market_dump.json"))
CFG = D["config"]
CAP, REC = CFG["PRICE_IMPACT_CAP_PCT"], CFG["PRICE_IMPACT_RECOVERY_PCT"]
STEP, MAX_TURN, R_CT = D["turn_step"], D["max_turn"], D["rival_count"]
goods = {g["id"]: g for g in D["goods"]}
by_name = {g["internal_name"]: g for g in D["goods"]}
producible = [gid for gid, g in goods.items() if g["goods_graph_tier"] != "apex" and g["base_output"] > 0]
GOODS = ["steel", "solar_panel", "lithium_battery"]
OUT_MULT = {1: 1.0, 2: 2.0, 3: 3.5}
RATES = [0.05, 0.1, 0.2, 0.5]
MULTS = [1, 2, 4, 10]
K, MOVE = 0.65, 0.015

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

def npc_flows(seed, gid):
    """(sold, bought) at each 5-turn sample."""
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

def sim_netted(gname, seed):
    g = by_name[gname]; gid = g["id"]; base = g["base_output"]
    pu = player_units(g["base_recipe_output_qty"])
    flows = npc_flows(seed, gid)
    a = 0.0; traj = []
    for t in range(MAX_TURN + 1):
        s, b = flows[t // STEP]
        net = (pu[t] + s) - b - nu[gid] * gamma(t)
        T = base * gamma(t)
        v = abs(net); rate = 0.0
        for m, r_ in zip(reversed(MULTS), reversed(RATES)):
            if v > m * T: rate = r_; break
        if rate > 0.0: a += -rate if net > 0 else rate
        else: a = a - math.copysign(min(REC, abs(a)), a) if a != 0 else 0.0
        a = max(-CAP, min(CAP, a))
        traj.append(a)
    return traj

def sim_ratio(gname, seed):
    g = by_name[gname]; gid = g["id"]
    pu = player_units(g["base_recipe_output_qty"])
    flows = npc_flows(seed, gid)
    mult = 1.0; traj = []
    for t in range(MAX_TURN + 1):
        s, b = flows[t // STEP]
        S = s + max(0.0, -nu[gid]) * gamma(t) + pu[t]
        Dm = b + max(0.0, nu[gid]) * gamma(t)
        if S <= 0 and Dm <= 0: target = 1.0
        elif S <= 0: target = 1 + CAP / 100
        else: target = max(1 - CAP / 100, min(1 + CAP / 100, (Dm / S) ** K))
        mult *= max(1 - MOVE, min(1 + MOVE, target / mult))
        traj.append((mult - 1) * 100)
    return traj

seeds = list(D["rivals"].keys())
H = json.load(open(f"{ROOT}/headtohead.json"))
out = {}
for gname in GOODS:
    g = by_name[gname]
    p0, decay = g["base_price"], g["decay_rate"]
    dec = [p0 * ((1 - decay) ** max(0, t - 29)) for t in range(MAX_TURN + 1)]
    res = {}
    for label, fn in [("N", sim_netted), ("R", sim_ratio)]:
        runs = [fn(gname, s) for s in seeds]
        mean = [statistics.mean(r[t] for r in runs) for t in range(MAX_TURN + 1)]
        res[label] = mean
    out[gname] = {
        "price": {"base_decayed": [round(v, 4) for v in dec],
                  "C": H[gname]["price"]["C"],
                  "N": [round(dec[t] * (1 + res["N"][t] / 100), 4) for t in range(MAX_TURN + 1)],
                  "R": [round(dec[t] * (1 + res["R"][t] / 100), 4) for t in range(MAX_TURN + 1)]},
        "impact": {"C": H[gname]["impact"]["C"],
                   "N": [round(x, 2) for x in res["N"]],
                   "R": [round(x, 2) for x in res["R"]]},
    }
    print(f"\n{gname}")
    print(f"  {'model':<4}" + "".join(f"{'t'+str(c):>9}" for c in [50, 100, 150, 200, 250, 300]) + "   impact % / £")
    for v in ["C", "N", "R"]:
        imp = out[gname]["impact"][v]; pr = out[gname]["price"][v]
        print(f"  {v:<4}" + "".join(f"{imp[c]:>9.1f}" for c in [50, 100, 150, 200, 250, 300]))
        print(f"  {'':<4}" + "".join(f"{pr[c]:>9.2f}" for c in [50, 100, 150, 200, 250, 300]))

json.dump(out, open(f"{ROOT}/fixes.json", "w"))
print("\nwrote fixes.json")
