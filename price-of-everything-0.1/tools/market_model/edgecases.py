#!/usr/bin/env python3
"""Edge cases for Model P + supply response.

CASE A - player-only output, rival-priced inputs ("apex-ified" solar):
  No rival solar production at all. The player's build-out sells solar AND buys
  the recipe inputs from the market (poly x8, elec x4, alloy x9, alu x6, ree x2
  per 15). Questions: what happens to the solar price (player-only volume), what
  happens to the input basket (player demand + rival response), margin arc.

CASE C - extraction good, no inputs (bauxite): does a downstream demand shock
  (player buys 150 aluminium/turn t50-200) transmit up aluminium -> alumina ->
  bauxite through prices + the growth response? Measure lags and band moves.
"""
import json, math, statistics
from collections import defaultdict

import os
ROOT = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(f"{ROOT}/npc_market_dump.json"))
STEP, MAX_TURN, R_CT = D["turn_step"], D["max_turn"], D["rival_count"]
goods = {g["id"]: g for g in D["goods"]}
by_name = {g["internal_name"]: g for g in D["goods"]}
producible_all = [gid for gid, g in goods.items() if g["goods_graph_tier"] != "apex" and g["base_output"] > 0]
BETA, C_THR, SPEED, EMA_N = 0.75, 0.6, 0.5, 5
BAND_EDGES = [(10, 40.0), (4, 30.0), (2, 20.0), (1, 10.0)]
OUT_MULT = {1: 1.0, 2: 2.0, 3: 3.5}
MARKUP = D["config"]["MARKET_BUY_MARKUP"]

def gamma(t): return 1.0 + 0.425 * (t // 5)
def target_for(r):
    for m, tgt in BAND_EDGES:
        if r > m: return tgt
    return 0.0

def increments(seed, producible):
    inc = {}
    for gid in producible:
        rows = D["rivals"][str(seed)][gid]
        inc[gid] = [[rows[i][b] - rows[i][b - 1] for b in range(1, len(rows[i]))] for i in range(R_CT)]
    return inc

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

def run(seed, producible, sells, buys, response=True):
    """sells/buys: {gid: [units per turn]}."""
    consumers = defaultdict(list); inputs_of = {}
    for gid in producible:
        g = goods[gid]; oq = g["base_recipe_output_qty"]
        inputs_of[gid] = []
        if oq <= 0: continue
        for inp in g["base_recipe_inputs"]:
            consumers[inp["good_id"]].append((gid, inp["qty"] / oq))
            inputs_of[gid].append((inp["good_id"], inp["qty"]))
    inc = increments(seed, producible)
    q = {gid: [goods[gid]["base_output"]] * R_CT for gid in producible}
    imp = defaultdict(float); ema = {}
    traj = defaultdict(list); g_used = defaultdict(list)
    def growth_mult(gid):
        g_out = 1.0
        d = imp.get(gid, 0.0)
        if d >= 10.0: g_out = 1.5
        elif d <= -10.0: g_out = 0.75
        g_in = 1.0
        ins = inputs_of.get(gid, [])
        if ins:
            wsum = dev = 0.0
            for j, qty in ins:
                pj = goods[j]["base_price"] * (1 + imp.get(j, 0.0) / 100.0)
                wsum += pj * qty; dev += pj * qty * (imp.get(j, 0.0) / 100.0)
            if wsum > 0:
                dev /= wsum
                if dev <= -0.25: g_in = 2.0
                elif dev >= 0.25: g_in = 0.5
        return max(0.25, min(2.5, g_in * g_out))
    for t in range(MAX_TURN + 1):
        if t > 0 and t % STEP == 0:
            b = t // STEP - 1
            for gid in producible:
                G = growth_mult(gid) if response else 1.0
                g_used[gid].append(G)
                for i in range(R_CT):
                    if b < len(inc[gid][i]):
                        q[gid][i] += int(round(inc[gid][i][b] * G))
        sold = {gid: sum(q[gid]) for gid in producible}
        bought = defaultdict(float)
        for j, cons in consumers.items():
            for cgid, per_unit in cons:
                bought[j] += sold.get(cgid, 0) * per_unit
        for gid, g in goods.items():
            base = g["base_output"]
            if base <= 0:
                traj[gid].append(0.0); continue
            npc_net = sold.get(gid, 0) - bought.get(gid, 0.0)
            p_net = sells.get(gid, [0] * (MAX_TURN + 1))[t] - buys.get(gid, [0] * (MAX_TURN + 1))[t]
            net = p_net + (1 - BETA) * npc_net
            T = max(base, C_THR * base * gamma(t))
            r = net / T
            ema[gid] = r if gid not in ema else ema[gid] + (r - ema[gid]) / EMA_N
            e = ema[gid]
            tgt = 0.0 if abs(e) <= 1 else target_for(abs(e)) * (-1 if e > 0 else 1)
            imp[gid] += max(-SPEED, min(SPEED, tgt - imp[gid]))
            traj[gid].append(imp[gid])
    return traj, g_used

seeds = list(D["rivals"].keys())
CPS = [50, 100, 150, 200, 250, 300]
sol = by_name["solar_panel"]; sol_id = sol["id"]
SOL_INPUTS = [(by_name[n]["id"], qty) for n, qty in
              [("polysilicon", 8), ("electrical_components", 4), ("alloy_ingots", 9),
               ("aluminium", 6), ("refined_ree", 2)]]

# ---------- CASE A ----------
print("=== CASE A: solar player-only (no rival solar), player buys inputs ===")
prod_noSolar = [g for g in producible_all if g != sol_id]
pu = player_units(15)
sells = {sol_id: pu}
buys = {j: [int(round(pu[t] * qty / 15)) for t in range(MAX_TURN + 1)] for j, qty in SOL_INPUTS}
runsA = [run(s, prod_noSolar, sells, buys, True) for s in seeds]
runsA_off = [run(s, prod_noSolar, sells, buys, False) for s in seeds]
def mseries(runs, gid): return [statistics.mean(r[0][gid][t] for r in runs) for t in range(MAX_TURN + 1)]
solA = mseries(runsA, sol_id)
print("  solar impact (player-only volume): " + "".join(f"{solA[c]:>8.1f}" for c in CPS))
def basket_dev(runs, t):
    tot = dev = 0.0
    for j, qty in SOL_INPUTS:
        pj = goods[j]["base_price"] * qty
        ij = statistics.mean(r[0][j][t] for r in runs)
        tot += pj; dev += pj * ij / 100.0
    return 100.0 * dev / tot
print("  input basket dev ON:  " + "".join(f"{basket_dev(runsA, c):>8.1f}" for c in CPS))
print("  input basket dev OFF: " + "".join(f"{basket_dev(runsA_off, c):>8.1f}" for c in CPS))
# margin per batch: 15*p_sol*(1+imp) - sum(qty*p_j*(1+imp_j)*(1+markup))
def marginA(runs, t):
    rev = 15 * sol["base_price"] * (1 + statistics.mean(r[0][sol_id][t] for r in runs) / 100)
    cost = sum(qty * goods[j]["base_price"] * (1 + statistics.mean(r[0][j][t] for r in runs) / 100) * (1 + MARKUP)
               for j, qty in SOL_INPUTS)
    return rev - cost
m0 = 15 * sol["base_price"] - sum(qty * goods[j]["base_price"] * (1 + MARKUP) for j, qty in SOL_INPUTS)
print(f"  margin/batch (base £{m0:.0f}) ON:  " + "".join(f"{marginA(runsA, c):>8.0f}" for c in CPS))
print(f"  margin/batch          OFF: " + "".join(f"{marginA(runsA_off, c):>8.0f}" for c in CPS))
for n in ["polysilicon", "aluminium", "refined_ree"]:
    gid = by_name[n]["id"]
    on = mseries(runsA, gid)
    print(f"  {n:<22} ON: " + "".join(f"{on[c]:>8.1f}" for c in CPS))

# ---------- CASE C ----------
print("\n=== CASE C: bauxite chain, player buys 150 aluminium/turn t50-200 ===")
alu, alm, bx = by_name["aluminium"]["id"], by_name["alumina"]["id"], by_name["bauxite_ore"]["id"]
shock = {alu: [150 if 50 <= t <= 200 else 0 for t in range(MAX_TURN + 1)]}
amb = [run(s, producible_all, {}, {}, True) for s in seeds]
shk = [run(s, producible_all, {}, shock, True) for s in seeds]
for name, gid in [("aluminium", alu), ("alumina", alm), ("bauxite_ore", bx)]:
    a = mseries(amb, gid); s_ = mseries(shk, gid)
    print(f"  {name:<12} ambient: " + "".join(f"{a[c]:>8.1f}" for c in CPS))
    print(f"  {'':<12} shock:   " + "".join(f"{s_[c]:>8.1f}" for c in CPS))
# first turn each good's shock trace departs >=3% from ambient
for name, gid in [("aluminium", alu), ("alumina", alm), ("bauxite_ore", bx)]:
    a = mseries(amb, gid); s_ = mseries(shk, gid)
    dep = next((t for t in range(50, MAX_TURN + 1) if abs(s_[t] - a[t]) >= 3), None)
    print(f"  {name}: departs ambient by >=3% at t{dep}" if dep else f"  {name}: never departs ambient by 3%")
# rival aluminium capacity under shock vs ambient
g_amb = amb[0][1]; g_shk = shk[0][1]
from collections import Counter
print("  aluminium G usage ambient:", dict(Counter(g_amb[alu])), " shock:", dict(Counter(g_shk[alu])))

json.dump({
    "solA": [round(x, 2) for x in solA],
    "basketA_on": [round(basket_dev(runsA, t), 2) for t in range(MAX_TURN + 1)],
    "basketA_off": [round(basket_dev(runsA_off, t), 2) for t in range(MAX_TURN + 1)],
    "chain": {n: {"amb": [round(x, 2) for x in mseries(amb, g)],
                  "shock": [round(x, 2) for x in mseries(shk, g)]}
              for n, g in [("aluminium", alu), ("alumina", alm), ("bauxite_ore", bx)]},
}, open(f"{ROOT}/edgecases.json", "w"))
print("\nwrote edgecases.json")
