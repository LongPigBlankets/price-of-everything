#!/usr/bin/env python3
"""Model P + competitor SUPPLY RESPONSE (owner spec 2026-08-12):

Growth multiplier per good, applied to every rival's 5-turn expansion increment:
  INPUT channel  (value-weighted mean input price deviation, w_j ~ market_price_j x qty_j):
      dev_in <= -25%  ->  x2.0     dev_in >= +25%  ->  x0.5     else x1
  OUTPUT channel (the good's own price deviation vs impact-free base):
      dev_out >= +10% ->  x1.5     dev_out <= -10% ->  x0.75    else x1
  G = clamp(G_in * G_out, 0.25, 2.5)

Price deviations = Model P impact (decay excluded from the signal).
Netting simplification that endogenous growth forces: 75% of the REALIZED NPC net
flow is absorbed by trade (no precomputed nu needed):
      net = player_net + 0.25 * (rival_sold - rival_buys)
Rival capacity is stateful: q[g][i] starts at base, each 5-turn batch adds
round(original_increment * G_g(t)). Coupled turn loop; 3 seeds.
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
OUT_MULT = {1: 1.0, 2: 2.0, 3: 3.5}

def gamma(t): return 1.0 + 0.425 * (t // 5)

# consumers[input_gid] = [(consumer_gid, qty_per_unit_output)]
consumers = defaultdict(list)
inputs_of = {}
for gid in producible:
    g = goods[gid]; oq = g["base_recipe_output_qty"]
    inputs_of[gid] = []
    if oq <= 0: continue
    for inp in g["base_recipe_inputs"]:
        consumers[inp["good_id"]].append((gid, inp["qty"] / oq))
        inputs_of[gid].append((inp["good_id"], inp["qty"]))

# per-seed original increments: inc[gid][i][b] (units), b = 1..60
def increments(seed):
    inc = {}
    for gid in producible:
        rows = D["rivals"][str(seed)][gid]
        inc[gid] = [[rows[i][b] - rows[i][b - 1] for b in range(1, len(rows[i]))] for i in range(R_CT)]
    return inc

def target_for(ratio):
    for m, tgt in BAND_EDGES:
        if ratio > m: return tgt
    return 0.0

def growth_mult(gid, imp):
    g_out = 1.0
    d_out = imp.get(gid, 0.0)
    if d_out >= 10.0: g_out = 1.5
    elif d_out <= -10.0: g_out = 0.75
    g_in = 1.0
    ins = inputs_of.get(gid, [])
    if ins:
        wsum = 0.0; dev = 0.0
        for j, qty in ins:
            pj = goods[j]["base_price"] * (1 + imp.get(j, 0.0) / 100.0)
            w = pj * qty
            wsum += w; dev += w * (imp.get(j, 0.0) / 100.0)
        if wsum > 0:
            dev /= wsum
            if dev <= -0.25: g_in = 2.0
            elif dev >= 0.25: g_in = 0.5
    return max(0.25, min(2.5, g_in * g_out))

def coupled_sim(seed, player_good=None, player_sell=None, response=True):
    inc = increments(seed)
    q = {gid: [goods[gid]["base_output"]] * R_CT for gid in producible}
    imp = defaultdict(float); ema = {}
    traj = defaultdict(list); qtot_traj = defaultdict(list); g_traj = defaultdict(list)
    for t in range(MAX_TURN + 1):
        # rival expansion first (batch b applies from turn b*5)
        if t > 0 and t % STEP == 0:
            b = t // STEP - 1
            for gid in producible:
                G = growth_mult(gid, imp) if response else 1.0
                g_traj[gid].append(G)
                for i in range(R_CT):
                    if b < len(inc[gid][i]):
                        q[gid][i] += int(round(inc[gid][i][b] * G))
        sold = {gid: sum(q[gid]) for gid in producible}
        bought = defaultdict(float)
        for j, cons in consumers.items():
            for cgid, per_unit in cons:
                if cgid in sold:
                    bought[j] += sold[cgid] * per_unit
        for gid, g in goods.items():
            base = g["base_output"]
            if base <= 0:
                traj[gid].append(0.0); continue
            npc_net = sold.get(gid, 0) - bought.get(gid, 0.0)
            p_net = 0
            if player_good == gid and player_sell is not None:
                p_net = player_sell[t]
            net = p_net + (1 - BETA) * npc_net
            T = max(base, C_THR * base * gamma(t))
            r = net / T
            ema[gid] = r if gid not in ema else ema[gid] + (r - ema[gid]) / EMA_N
            e = ema[gid]
            tgt = 0.0 if abs(e) <= 1 else target_for(abs(e)) * (-1 if e > 0 else 1)
            imp[gid] += max(-SPEED, min(SPEED, tgt - imp[gid]))
            traj[gid].append(imp[gid])
            qtot_traj[gid].append(sold.get(gid, 0))
    return traj, qtot_traj, g_traj

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
CPS = [50, 100, 150, 200, 250, 300]

def mean_over_seeds(runs, gid):
    return [statistics.mean(r[gid][t] for r in runs) for t in range(MAX_TURN + 1)]

print("=== AMBIENT (no player): response OFF vs ON, mean 3 seeds ===")
off_runs = [coupled_sim(s, response=False)[0] for s in seeds]
on_all = [coupled_sim(s, response=True) for s in seeds]
on_runs = [x[0] for x in on_all]
for name in ["steel", "solar_panel", "lithium_battery", "motor", "copper_wiring", "concrete"]:
    gid = by_name[name]["id"]
    off = mean_over_seeds(off_runs, gid); on = mean_over_seeds(on_runs, gid)
    print(f"  {name:<16} OFF:" + "".join(f"{off[c]:>8.1f}" for c in CPS))
    print(f"  {'':<16}  ON:" + "".join(f"{on[c]:>8.1f}" for c in CPS))

def spread_stats(runs, label):
    at300 = [statistics.mean(r[gid][300] for r in runs) for gid in producible]
    off_base = sum(1 for v in at300 if abs(v) >= 5)
    print(f"  {label}: mean |impact| t300 = {statistics.mean(abs(v) for v in at300):.1f}%; "
          f"goods off base (|.|>=5%): {off_base}/{len(producible)}; "
          f"at +-30 or beyond: {sum(1 for v in at300 if abs(v) >= 29)}")

print("\n=== ambient spread ===")
spread_stats(off_runs, "response OFF")
spread_stats(on_runs, "response ON ")

# regime stretch lengths (ON, seed0): time between impact-target moves of >=5%
print("\n=== regime behaviour (response ON, seed 1337) ===")
tr0 = on_all[0][0]
lens = []; reversals = 0
for gid in producible:
    x = tr0[gid]; moves = []
    last_dir = 0; last_move_t = 20
    for t in range(21, MAX_TURN + 1):
        d = x[t] - x[t - 1]
        dirn = 1 if d > 0.01 else (-1 if d < -0.01 else 0)
        if dirn != 0 and last_dir != 0 and dirn != last_dir:
            reversals += 1
        if dirn != 0 and last_dir == 0:
            lens.append(t - last_move_t)
        if dirn == 0 and last_dir != 0:
            last_move_t = t
        if dirn != 0: last_dir = dirn
    # crude: count plateaus
print(f"  direction reversals across all goods over 280 turns: {reversals} "
      f"({reversals/len(producible):.1f} per good) -> waves, not monotone drift")
plateau = []
for gid in producible:
    x = tr0[gid]; runl = 0
    for t in range(21, MAX_TURN + 1):
        if abs(x[t] - x[t - 1]) < 0.01: runl += 1
        else:
            if runl >= 5: plateau.append(runl)
            runl = 0
    if runl >= 5: plateau.append(runl)
print(f"  stable plateaus (>=5 turns): median {statistics.median(plateau):.0f}, "
      f"p75 {sorted(plateau)[3*len(plateau)//4]}, max {max(plateau)} turns; count {len(plateau)}")

# growth multiplier usage
print("\n=== growth multipliers actually used (ON, seed 1337) ===")
g_traj = on_all[0][2]
from collections import Counter
for name in ["steel", "solar_panel", "motor", "iron_ingots"]:
    gid = by_name[name]["id"]
    cnt = Counter(g_traj[gid])
    tot = sum(cnt.values())
    top = ", ".join(f"x{k:g}:{v*100//tot}%" for k, v in sorted(cnt.items()))
    print(f"  {name:<14} {top}")

# supply multiple vs baseline
print("\n=== rival supply at t300 as multiple of no-response baseline (seed 1337) ===")
q_on = on_all[0][1]; q_off = coupled_sim(seeds[0], response=False)[1]
for name in ["steel", "solar_panel", "lithium_battery", "motor"]:
    gid = by_name[name]["id"]
    print(f"  {name:<16} ON {q_on[gid][300]:>8} vs OFF {q_off[gid][300]:>8}  (x{q_on[gid][300]/max(1,q_off[gid][300]):.2f})")

# player steel specialist with response ON vs OFF
print("\n=== steel specialist (build-out) premium arc ===")
pu = player_units(54)
gid = by_name["steel"]["id"]
spec_off = [coupled_sim(s, player_good=gid, player_sell=pu, response=False)[0] for s in seeds]
spec_on = [coupled_sim(s, player_good=gid, player_sell=pu, response=True)[0] for s in seeds]
m_off = mean_over_seeds(spec_off, gid); m_on = mean_over_seeds(spec_on, gid)
print("  turn:      " + "".join(f"{c:>8}" for c in CPS))
print("  OFF:       " + "".join(f"{m_off[c]:>8.1f}" for c in CPS))
print("  ON:        " + "".join(f"{m_on[c]:>8.1f}" for c in CPS))
window_off = sum(1 for t in range(MAX_TURN + 1) if m_off[t] >= 10)
window_on = sum(1 for t in range(MAX_TURN + 1) if m_on[t] >= 10)
print(f"  turns with premium >= +10%: OFF {window_off}, ON {window_on}")

amb_off_steel = mean_over_seeds(off_runs, gid); amb_on_steel = mean_over_seeds(on_runs, gid)
sol = by_name["solar_panel"]["id"]
json.dump({
    "steel_amb_off": [round(x, 2) for x in amb_off_steel],
    "steel_amb_on": [round(x, 2) for x in mean_over_seeds(on_runs, gid)],
    "solar_amb_off": [round(x, 2) for x in mean_over_seeds(off_runs, sol)],
    "solar_amb_on": [round(x, 2) for x in mean_over_seeds(on_runs, sol)],
    "steel_spec_off": [round(x, 2) for x in m_off],
    "steel_spec_on": [round(x, 2) for x in m_on],
}, open(f"{ROOT}/response.json", "w"))
print("\nwrote response.json")
