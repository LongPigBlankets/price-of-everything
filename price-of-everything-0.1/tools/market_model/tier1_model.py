#!/usr/bin/env python3
"""Part 2: player-margin consequences of scenarios A/B, and the proposed
ratio-based demand/price-discovery model (Tier 1) simulated on real data.

Tier 1 price model:
  S_g(t) = rival sales + imports M_g + player sales
  D_g(t) = rival input buys + final/export demand F_g + player buys
  F_g = max(0, nu_g)*gamma(t),  M_g = max(0, -nu_g)*gamma(t)   (trade closure:
        the expected NPC surplus is exported, the expected shortfall imported,
        so the world starts in equilibrium and only deviations move prices)
  target price mult = clamp((D/S)^k, 1-CAP, 1+CAP), k = 0.65
  mult moves toward target at most MOVE %/turn (multiplicative).
"""
import json, math, statistics
from collections import defaultdict

import os
ROOT = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(f"{ROOT}/npc_market_dump.json"))
RES = json.load(open(f"{ROOT}/scenario_results.json"))

STEP = D["turn_step"]; MAX_TURN = D["max_turn"]; R = D["rival_count"]
MARKUP = D["config"]["MARKET_BUY_MARKUP"]
goods = {g["id"]: g for g in D["goods"]}
by_name = {g["internal_name"]: g for g in D["goods"]}
producible = [gid for gid, g in goods.items()
              if g["goods_graph_tier"] != "apex" and g["base_output"] > 0]

def gamma(t):  # expected growth factor of rival output
    return 1.0 + 0.425 * (t // 5)

def q_at(seed, gid, i, t):
    return D["rivals"][str(seed)][gid][i][t // STEP]

# expected net position (same as part 1)
nu = {}
for gid, g in goods.items():
    sold = g["base_output"] if gid in producible else 0
    bought = 0.0
    for cg in producible:
        cgd = goods[cg]
        oq = cgd["base_recipe_output_qty"]
        if oq <= 0: continue
        for inp in cgd["base_recipe_inputs"]:
            if inp["good_id"] == gid:
                bought += inp["qty"] / oq * cgd["base_output"]
    nu[gid] = R * (sold - bought)

# ---------------- 1. chain-margin consequences of A / B at t100 ----------------
print("=" * 104)
print("GROSS MATERIAL MARGIN per base-recipe batch (outputs at sale price, inputs at buy price = x1.05)")
print("  now = no impact; A/B = mean accumulated impact at t100 applied. Decay/overheads excluded.")
print("=" * 104)

def margin(gid, impact_map):
    g = goods[gid]
    oq = g["base_recipe_output_qty"]
    if oq <= 0: return None
    def mult(name):
        return 1.0 + impact_map.get(name, [0.0] * (MAX_TURN + 1))[100] / 100.0
    rev = oq * g["base_price"] * mult(g["internal_name"])
    cost = sum(inp["qty"] * goods[inp["good_id"]]["base_price"]
               * mult(goods[inp["good_id"]]["internal_name"]) * (1 + MARKUP)
               for inp in g["base_recipe_inputs"])
    return rev - cost

zero = {}
rows = []
for gid in producible:
    g = goods[gid]
    if not g["base_recipe_inputs"]:      # extraction: no market inputs, margin = revenue
        pass
    m0 = margin(gid, zero); mA = margin(gid, RES["meanA"]); mB = margin(gid, RES["meanB"])
    if m0 is None: continue
    rows.append((g["internal_name"], g["base_recipe_id"], m0, mA, mB))
rows.sort(key=lambda r: (r[3] - r[2]))
flipA = sum(1 for r in rows if r[2] > 0 and r[3] <= 0)
flipB = sum(1 for r in rows if r[2] > 0 and r[4] <= 0)
pos0 = sum(1 for r in rows if r[2] > 0)
print(f"{'good (base recipe)':<28}{'now £/batch':>12}{'A t100':>10}{'B t100':>10}{'dA':>9}{'dB':>9}")
for name, rid, m0, mA, mB in rows[:14]:
    print(f"{name:<28}{m0:>12.1f}{mA:>10.1f}{mB:>10.1f}{mA-m0:>9.1f}{mB-m0:>9.1f}")
print("  ...")
for name, rid, m0, mA, mB in rows[-6:]:
    print(f"{name:<28}{m0:>12.1f}{mA:>10.1f}{mB:>10.1f}{mA-m0:>9.1f}{mB-m0:>9.1f}")
print(f"\npositive-margin recipes now: {pos0}/{len(rows)}; flipped NEGATIVE by t100 — A: {flipA}, B: {flipB}")

# ---------------- 2. Tier-1 ratio model with player shocks ----------------
K = 0.65          # 1/(eps+sigma): demand+supply elasticity ~1.54 combined
MOVE = 0.015      # max 1.5%/turn price move
CAPM = 0.40       # +/-40% band kept from the live model

def tier1(seed, shocks):
    """shocks: list of (good_internal, sell_per_turn, buy_per_turn, t0, t1)"""
    mult = defaultdict(lambda: 1.0)
    traj = defaultdict(list)
    for t in range(0, MAX_TURN + 1):
        S = defaultdict(float); Dm = defaultdict(float)
        for gid in producible:
            tot = sum(q_at(seed, gid, i, t) for i in range(R))
            S[gid] += tot
            g = goods[gid]; oq = g["base_recipe_output_qty"]
            if oq > 0:
                for inp in g["base_recipe_inputs"]:
                    Dm[inp["good_id"]] += tot * inp["qty"] / oq
        for gid in goods:
            if nu[gid] > 0: Dm[gid] += nu[gid] * gamma(t)      # exports absorb surplus
            elif nu[gid] < 0: S[gid] += -nu[gid] * gamma(t)    # imports cover shortfall
        for name, sell, buy, t0, t1 in shocks:
            if t0 <= t <= t1:
                gid = by_name[name]["id"]
                S[gid] += sell; Dm[gid] += buy
        for gid, g in goods.items():
            if g["base_output"] <= 0:
                traj[gid].append(1.0); continue
            s = S.get(gid, 0.0); d = Dm.get(gid, 0.0)
            if s <= 0 and d <= 0:
                target = 1.0
            elif s <= 0:
                target = 1 + CAPM
            else:
                target = max(1 - CAPM, min(1 + CAPM, (d / s) ** K))
            m = mult[gid]
            m = m * max(1 - MOVE, min(1 + MOVE, target / m))
            mult[gid] = m
            traj[gid].append(m)
    return traj

seed0 = list(D["rivals"].keys())[0]
base_run = tier1(seed0, [])
steel_dump = tier1(seed0, [("steel", 162, 0, 50, 150)])          # sell 3x base steel
steel_buy  = tier1(seed0, [("steel", 0, 200, 50, 150)])          # buy 200 steel/turn
thin_dump  = tier1(seed0, [("wind_turbine", 9, 0, 50, 150)])     # sell 3x base, thin market

def show(name, run, gid_name, marks=(40, 60, 100, 150, 160, 200, 300)):
    gid = by_name[gid_name]["id"]
    s = "  ".join(f"t{t}:{(run[gid][t]-1)*100:+.1f}%" for t in marks)
    print(f"{name:<34} {s}")

print("\n" + "=" * 104)
print(f"TIER-1 RATIO MODEL (k={K}, max move {MOVE*100:.1f}%/turn, band +/-{CAPM*100:.0f}%) — seed {seed0}")
print("=" * 104)
print("No player activity — organic wobble (99th pct |deviation| across goods/turns):")
devs = [abs(base_run[g][t] - 1) * 100 for g in producible for t in range(20, MAX_TURN)]
print(f"  median {statistics.median(devs):.2f}%  p90 {sorted(devs)[int(len(devs)*.9)]:.2f}%  "
      f"p99 {sorted(devs)[int(len(devs)*.99)]:.2f}%  max {max(devs):.2f}%")
show("steel: PLAYER SELLS 162/t t50-150", steel_dump, "steel")
show("steel: PLAYER BUYS 200/t t50-150", steel_buy, "steel")
show("wind_turbine: SELLS 9/t t50-150", thin_dump, "wind_turbine")
show("steel: no player (control)", base_run, "steel")

# closed-form check for the steel dump at t=100
gid = by_name["steel"]["id"]
t = 100
S0 = R * goods[gid]["base_output"] * gamma(t) + (-nu[gid]) * gamma(t)
D0 = S0  # balanced by construction (expectation)
pred = (D0 / (S0 + 162)) ** K
print(f"\nclosed-form steel equilibrium at t100: (D/(S+162))^k = {pred:.3f} "
      f"(S_world≈{S0:.0f}/turn) vs simulated {steel_dump[gid][100]:.3f}")

# ---------------- 3. market depth table ----------------
print("\nMARKET DEPTH — player units/turn that move the price 1% (≈ S_world/(100k)), scenario-A liquidity:")
print(f"{'good':<24}{'t1':>8}{'t50':>8}{'t100':>8}{'t200':>8}   base_out")
for name in ["concrete", "steel", "motor", "coal", "power", "solar_panel", "wind_turbine", "cpu"]:
    g = by_name[name]
    gid = g["id"]
    def depth(t):
        if g["goods_graph_tier"] == "apex":
            return float("nan")
        s = R * g["base_output"] * gamma(t) + max(0.0, -nu[gid]) * gamma(t)
        return s / (100 * K)
    print(f"{name:<24}" + "".join(f"{depth(t):>8.1f}" for t in [1, 50, 100, 200]) + f"   {g['base_output']}")

json.dump({
    "tier1_base": {goods[g]["internal_name"]: base_run[g] for g in producible},
    "tier1_steel_dump": {"steel": steel_dump[by_name["steel"]["id"]]},
    "tier1_steel_buy": {"steel": steel_buy[by_name["steel"]["id"]]},
    "tier1_thin": {"wind_turbine": thin_dump[by_name["wind_turbine"]["id"]]},
    "margins": rows,
}, open(f"{ROOT}/tier1_results.json", "w"))
print("\nwrote tier1_results.json")
