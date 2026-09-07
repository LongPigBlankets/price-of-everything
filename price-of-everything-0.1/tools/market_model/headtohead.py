#!/usr/bin/env python3
"""Head-to-head: Control vs V1-V4 for steel / solar_panel / lithium_battery.

Player build-out (per good): B1 L1@t10, L2@t30, L3@t60; B2 L1@t70; from t75 an
event every 5 turns cycling upgrade->upgrade->build-next. Output per building =
batch x OUTPUT_MULT{1:1.0, 2:2.0, 3:3.5} (building_levels.gd). All output sold
to market. Player buys of the charted good: none.

C : player-only net, static thresholds x base_output [1,2,4,10], rates .05/.1/.2/.5
V1: + NPC sold & NPC input-buys counted; same thresholds
V2: as V1; thresholds = [1,2,3,5] x (9 x base)  (sum of all producers at t1), static
V3: as V1; integer threshold base, T=floor(T*1.02) each turn  (literal rounding)
V4: as V1; float growth +1.5%/t to t100, +2.5% to t200, +4% to t300
Cap +/-40, recovery 0.1/turn when no band hit. Price = base_price x decay(t>=30) x (1+a/100).
"""
import json, math, statistics
from collections import defaultdict

import os
ROOT = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(f"{ROOT}/npc_market_dump.json"))
CFG = D["config"]
CAP, REC = CFG["PRICE_IMPACT_CAP_PCT"], CFG["PRICE_IMPACT_RECOVERY_PCT"]
STEP, MAX_TURN, R = D["turn_step"], D["max_turn"], D["rival_count"]
goods = {g["id"]: g for g in D["goods"]}
by_name = {g["internal_name"]: g for g in D["goods"]}
producible = [gid for gid, g in goods.items() if g["goods_graph_tier"] != "apex" and g["base_output"] > 0]
GOODS = ["steel", "solar_panel", "lithium_battery"]
OUT_MULT = {1: 1.0, 2: 2.0, 3: 3.5}
RATES = [0.05, 0.1, 0.2, 0.5]

def q_at(seed, gid, i, t): return D["rivals"][str(seed)][gid][i][t // STEP]

# ---- player output schedule ----
def player_units(batch):
    """units sold per turn, t=0..300"""
    levels = []  # per building
    events = {10: ("build",), 30: ("up",), 60: ("up",), 70: ("build",)}
    t = 75
    while t <= 300:
        events[t] = ("auto",); t += 5
    out = []
    for t in range(MAX_TURN + 1):
        if t in events:
            kind = events[t][0]
            if kind == "build": levels.append(1)
            elif kind == "up": levels[-1] += 1
            else:  # auto: upgrade newest if < L3 else build next
                if levels and levels[-1] < 3: levels[-1] += 1
                else: levels.append(1)
        out.append(int(round(sum(batch * OUT_MULT[l] for l in levels))))
    return out

# ---- NPC flows per (seed, turn): sold & bought for the charted goods ----
def npc_net(seed, gid, t):
    sold = sum(q_at(seed, gid, i, t) for i in range(R)) if gid in producible else 0
    bought = 0.0
    for cg in producible:
        g = goods[cg]; oq = g["base_recipe_output_qty"]
        if oq <= 0: continue
        for inp in g["base_recipe_inputs"]:
            if inp["good_id"] == gid:
                bought += sum(q_at(seed, cg, i, t) for i in range(R)) * inp["qty"] / oq
    return sold, bought

def simulate(gname, variant, seed):
    g = by_name[gname]; gid = g["id"]; base = g["base_output"]
    punits = player_units(g["base_recipe_output_qty"])
    a = 0.0; traj = []
    T_int = base  # V3 integer state
    for t in range(MAX_TURN + 1):
        if variant == "C":
            net = punits[t]
        else:
            s, b = npc_net(seed, gid, t)
            net = (s + punits[t]) - b
        if variant == "V2":
            thr, mults = 9 * base, [1, 2, 3, 5]
        elif variant == "V3":
            if t >= 1: T_int = math.floor(T_int * 1.02)
            thr, mults = T_int, [1, 2, 4, 10]
        elif variant == "V4":
            gr = 1.0
            for u in range(1, t + 1):
                gr *= 1.015 if u <= 100 else (1.025 if u <= 200 else 1.04)
            thr, mults = base * gr, [1, 2, 4, 10]
        else:
            thr, mults = base, [1, 2, 4, 10]
        v = abs(net); rate = 0.0
        for m, r_ in zip(reversed(mults), reversed(RATES)):
            if v > m * thr: rate = r_; break
        if rate > 0.0:
            a += -rate if net > 0 else rate
        else:
            a = a - math.copysign(min(REC, abs(a)), a) if a != 0 else 0.0
        a = max(-CAP, min(CAP, a))
        traj.append(a)
    return traj

# V4 growth is O(t) inside the loop -> precompute instead for speed
_v4 = [1.0]
for u in range(1, MAX_TURN + 1):
    _v4.append(_v4[-1] * (1.015 if u <= 100 else (1.025 if u <= 200 else 1.04)))

def simulate_fast(gname, variant, seed):
    g = by_name[gname]; gid = g["id"]; base = g["base_output"]
    punits = player_units(g["base_recipe_output_qty"])
    npc = [npc_net(seed, gid, t) for t in range(0, MAX_TURN + 1, STEP)] if variant != "C" else None
    a = 0.0; traj = []; T_int = base
    for t in range(MAX_TURN + 1):
        if variant == "C":
            net = punits[t]
        else:
            s, b = npc[t // STEP]
            net = (s + punits[t]) - b
        if variant == "V2": thr, mults = 9 * base, [1, 2, 3, 5]
        elif variant == "V3":
            if t >= 1: T_int = math.floor(T_int * 1.02)
            thr, mults = T_int, [1, 2, 4, 10]
        elif variant == "V4": thr, mults = base * _v4[t], [1, 2, 4, 10]
        else: thr, mults = base, [1, 2, 4, 10]
        v = abs(net); rate = 0.0
        for m, r_ in zip(reversed(mults), reversed(RATES)):
            if v > m * thr: rate = r_; break
        if rate > 0.0: a += -rate if net > 0 else rate
        else: a = a - math.copysign(min(REC, abs(a)), a) if a != 0 else 0.0
        a = max(-CAP, min(CAP, a))
        traj.append(a)
    return traj

seeds = list(D["rivals"].keys())
VARIANTS = ["C", "V1", "V2", "V3", "V4"]
out = {}
for gname in GOODS:
    g = by_name[gname]
    decay = g["decay_rate"]; p0 = g["base_price"]
    dec = [p0 * ((1 - decay) ** max(0, t - 29)) for t in range(MAX_TURN + 1)]
    series = {"base_decayed": [round(v, 4) for v in dec]}
    imp = {}
    for var in VARIANTS:
        runs = [simulate_fast(gname, var, s) for s in (seeds if var != "C" else seeds[:1])]
        mean = [statistics.mean(r[t] for r in runs) for t in range(MAX_TURN + 1)]
        imp[var] = mean
        series[var] = [round(dec[t] * (1 + mean[t] / 100.0), 4) for t in range(MAX_TURN + 1)]
    out[gname] = {"price": series, "impact": {v: [round(x, 2) for x in imp[v]] for v in VARIANTS},
                  "base_price": p0, "punits": player_units(g["base_recipe_output_qty"])}
    print(f"\n{gname}  (base_output {g['base_output']}, batch {g['base_recipe_output_qty']}, £{p0})")
    print(f"  player units/turn: t10:{out[gname]['punits'][10]} t30:{out[gname]['punits'][30]} "
          f"t60:{out[gname]['punits'][60]} t100:{out[gname]['punits'][100]} t200:{out[gname]['punits'][200]} t300:{out[gname]['punits'][300]}")
    print(f"  {'variant':<6}" + "".join(f"{'t'+str(c):>10}" for c in [50, 100, 150, 200, 250, 300]) + "   (impact %, then £)")
    for var in VARIANTS:
        row1 = "".join(f"{imp[var][c]:>10.1f}" for c in [50, 100, 150, 200, 250, 300])
        row2 = "".join(f"{series[var][c]:>10.2f}" for c in [50, 100, 150, 200, 250, 300])
        print(f"  {var:<6}{row1}")
        print(f"  {'':<6}{row2}")

json.dump(out, open(f"{ROOT}/headtohead.json", "w"))
print("\nwrote headtohead.json")
