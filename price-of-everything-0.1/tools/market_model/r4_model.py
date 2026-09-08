#!/usr/bin/env python3
"""R4 = R3 + owner conditions (2026-08-12):

1. CAPACITY EXIT: when a good's impact has been <= -20% for >= 5 consecutive
   turns, responding rivals RETIRE capacity at batch time: q -= drawn_increment
   x personality scale (floor: never below the initial base plant). Cautious
   rivals never exit.
2. DECISION LAG: growth-multiplier responses (both channels) engage only after
   the trigger direction has persisted 10 consecutive turns (out-dir defined at
   +/-5%, in-dir at +/-12% weighted). Magnitude once engaged = R3 ladder at the
   CURRENT deviation. Exit keeps its own 5-turn rule.
3. PERSONALITIES: rivals 0-3 cautious (never respond, expand at x1, never exit),
   4-6 half-cautious (deviation from x1 halved; half-size exits), 7-8 aggressive
   (full response). NOTE: owner split 3/3/2 covers 8 of 9 rivals; the 9th is
   assigned CAUTIOUS (4/3/2) - flagged as a knob.
R3 ladder: out >=+10 x2.0 | +5..10 x1.5 | -5..-10 x0.75 | <=-10 x0.5
           in  <=-25 x2.0 | -12..-25 x1.5 | +12..+25 x0.75 | >=+25 x0.5
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
OUT_M = {1: 1.0, 2: 2.0, 3: 3.5}; IN_M = {1: 1.0, 2: 2.0, 3: 3.0}
EN_M = {1: 1.0, 2: 1.8, 3: 2.5}; LAB_M = {1: 1.0, 2: 1.5, 3: 2.0}; MAINT_M = {1: 1.0, 2: 1.8, 3: 2.5}
MARKUP, GRID = 0.05, 0.12
LABOUR_L1 = 1356 * 0.002 + 515 * 0.006 + 51 * 0.010
MAINT_L1 = 10.0
STEEL, II, H2 = by_name["steel"]["id"], by_name["iron_ingots"]["id"], by_name["hydrogen"]["id"]
SOL = by_name["solar_panel"]["id"]
PERSONALITY = [0.0] * 4 + [0.5] * 3 + [1.0] * 2   # 4 cautious / 3 half / 2 aggressive
EXIT_HOLD, LAG = 5, 10

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

def run_r4(seed, player=None, r3_mode=False):
    """player: None | 'steel' | 'solar'. r3_mode: no lag, no exit, shared full response."""
    inc = {gid: [[D["rivals"][str(seed)][gid][i][b] - D["rivals"][str(seed)][gid][i][b - 1]
                  for b in range(1, 61)] for i in range(R_CT)] for gid in producible}
    q = {gid: [goods[gid]["base_output"]] * R_CT for gid in producible}
    imp = defaultdict(float); ema = {}
    out_dir = defaultdict(int); out_cnt = defaultdict(int)
    in_dir = defaultdict(int); in_cnt = defaultdict(int)
    exit_cnt = defaultdict(int)
    traj = defaultdict(list); exits = defaultdict(int)
    def in_dev(gid):
        ins = inputs_of.get(gid, [])
        if not ins: return 0.0
        ws = dv = 0.0
        for j, qty in ins:
            pj = goods[j]["base_price"] * (1 + imp.get(j, 0.0) / 100)
            ws += pj * qty; dv += pj * qty * imp.get(j, 0.0) / 100
        return dv / ws if ws > 0 else 0.0
    for t in range(MAX_TURN + 1):
        # update persistence counters (turn granularity)
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
        if t > 0 and t % STEP == 0:
            b = t // STEP - 1
            for gid in producible:
                d_o = imp.get(gid, 0.0); d_i = in_dev(gid)
                if r3_mode:
                    G_full = max(0.25, min(2.5, out_mag(d_o) * in_mag(d_i)))
                    for i in range(R_CT):
                        if b < len(inc[gid][i]):
                            q[gid][i] += int(round(inc[gid][i][b] * G_full))
                    continue
                go = out_mag(d_o) if out_cnt[gid] >= LAG else 1.0
                gi = in_mag(d_i) if in_cnt[gid] >= LAG else 1.0
                G_full = max(0.25, min(2.5, go * gi))
                exiting = exit_cnt[gid] >= EXIT_HOLD
                for i in range(R_CT):
                    if b >= len(inc[gid][i]): continue
                    s = PERSONALITY[i]
                    if exiting and s > 0:
                        cut = int(round(inc[gid][i][b] * s))
                        newq = max(goods[gid]["base_output"], q[gid][i] - cut)
                        exits[gid] += q[gid][i] - newq
                        q[gid][i] = newq
                    else:
                        Gr = 1 + (G_full - 1) * s if s > 0 else 1.0
                        q[gid][i] += int(round(inc[gid][i][b] * Gr))
        sold = {gid: sum(q[gid]) for gid in producible}
        bought = defaultdict(float)
        for j, cons in consumers.items():
            for cgid, pu in cons:
                bought[j] += sold.get(cgid, 0) * pu
        pnet = {}
        if player:
            lv = LV[t]
            if player == "steel":
                pnet = {STEEL: sum(54 * OUT_M[l] for l in lv),
                        II: -sum(21 * IN_M[l] for l in lv), H2: -sum(5 * IN_M[l] for l in lv)}
            else:
                pnet = {SOL: sum(15 * OUT_M[l] for l in lv)}
                for n, qty in [("polysilicon", 8), ("electrical_components", 4),
                               ("alloy_ingots", 9), ("aluminium", 6), ("refined_ree", 2)]:
                    pnet[by_name[n]["id"]] = -sum(qty * IN_M[l] for l in lv)
        for gid, g in goods.items():
            base = g["base_output"]
            if base <= 0:
                traj[gid].append(0.0); continue
            net = pnet.get(gid, 0) + (1 - BETA) * (sold.get(gid, 0) - bought.get(gid, 0.0))
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
    return traj, sold, exits

def dec_price(gid, t):
    g = goods[gid]
    return g["base_price"] * ((1 - g["decay_rate"]) ** max(0, t - 29))

def pnl_steel(imp_of):
    cum = 0.0; prof = []
    for t in range(MAX_TURN + 1):
        lv = LV[t]
        out_u = sum(54 * OUT_M[l] for l in lv); in_ii = sum(21 * IN_M[l] for l in lv)
        in_h2 = sum(5 * IN_M[l] for l in lv); en = sum(140 * EN_M[l] for l in lv)
        lab = sum(LABOUR_L1 * LAB_M[l] for l in lv); mnt = sum(MAINT_L1 * MAINT_M[l] for l in lv)
        rev = out_u * dec_price(STEEL, t) * (1 + imp_of(STEEL, t) / 100) * (1 - adval(t))
        cost = (in_ii * dec_price(II, t) * (1 + imp_of(II, t) / 100) * (1 + MARKUP)
                + in_h2 * dec_price(H2, t) * (1 + imp_of(H2, t) / 100) * (1 + MARKUP) + en * GRID + lab + mnt)
        p = rev - cost; prof.append(p); cum += p
    return prof, cum

seeds = list(D["rivals"].keys())
CPS = [50, 100, 150, 200, 250, 300]
def ms(runs, gid): return [statistics.mean(r[0][gid][t] for r in runs) for t in range(MAX_TURN + 1)]

amb4 = [run_r4(s) for s in seeds]
amb3 = [run_r4(s, r3_mode=True) for s in seeds]
spec4 = [run_r4(s, player="steel") for s in seeds]
sol4 = [run_r4(s, player="solar") for s in seeds]
sol3 = [run_r4(s, player="solar", r3_mode=True) for s in seeds]

st4, st3 = ms(amb4, STEEL), ms(amb3, STEEL)
so4, so3 = ms(amb4, SOL), ms(amb3, SOL)
sp4 = ms(spec4, STEEL)
sd4, sd3 = ms(sol4, SOL), ms(sol3, SOL)

print("=== AMBIENT steel (R3 vs R4) ===")
print("  R3: " + "".join(f"{st3[c]:>8.1f}" for c in CPS))
print("  R4: " + "".join(f"{st4[c]:>8.1f}" for c in CPS))
print("=== AMBIENT solar (R3 vs R4 — exit rule test) ===")
print("  R3: " + "".join(f"{so3[c]:>8.1f}" for c in CPS))
print("  R4: " + "".join(f"{so4[c]:>8.1f}" for c in CPS))
sol_exits = statistics.mean(r[2].get(SOL, 0) for r in amb4)
print(f"  solar capacity retired (ambient, mean): {sol_exits:.0f} units/turn-equivalent")

print("\n=== STEEL SPECIALIST (R4) ===")
print("  impact: " + "".join(f"{sp4[c]:>8.1f}" for c in CPS))
w4 = sum(1 for t in range(MAX_TURN + 1) if sp4[t] >= 10)
prof4, cum4 = pnl_steel(lambda g, t: statistics.mean(r[0][g][t] for r in spec4))
_, cum_base = pnl_steel(lambda g, t: 0.0)
print(f"  premium window >=+10%: {w4} turns | P&L £{cum4:,.0f} ({100*cum4/cum_base:.0f}% of baseline)")

print("\n=== SOLAR DUMPER: predatory exit test (player sells solar, R3 vs R4) ===")
print("  R3 solar: " + "".join(f"{sd3[c]:>8.1f}" for c in CPS))
print("  R4 solar: " + "".join(f"{sd4[c]:>8.1f}" for c in CPS))
riv3 = statistics.mean(r[1].get(SOL, 0) for r in sol3)
riv4 = statistics.mean(r[1].get(SOL, 0) for r in sol4)
print(f"  rival solar capacity at t300: R3 {riv3:.0f} vs R4 {riv4:.0f} (x{riv4/max(riv3,1):.2f})")

# regime stats R4 ambient
tr0 = amb4[0][0]
reversals = 0
for gid in producible:
    x = tr0[gid]; last = 0
    for t in range(21, MAX_TURN + 1):
        d = x[t] - x[t - 1]
        dirn = 1 if d > 0.01 else (-1 if d < -0.01 else 0)
        if dirn != 0 and last != 0 and dirn != last: reversals += 1
        if dirn != 0: last = dirn
at300 = [statistics.mean(r[0][gid][300] for r in amb4) for gid in producible]
print(f"\nR4 ambient t300: mean|imp| {statistics.mean(abs(v) for v in at300):.1f}%, "
      f">=|30|: {sum(1 for v in at300 if abs(v) >= 29)}, reversals/good {reversals/len(producible):.1f}")

json.dump({"st3": [round(x,2) for x in st3], "st4": [round(x,2) for x in st4],
           "so3": [round(x,2) for x in so3], "so4": [round(x,2) for x in so4],
           "sp4": [round(x,2) for x in sp4], "sd3": [round(x,2) for x in sd3],
           "sd4": [round(x,2) for x in sd4], "prof4": [round(x,1) for x in prof4],
           "cum4": round(cum4), "w4": w4},
          open(f"{ROOT}/r4.json", "w"))
print("wrote r4.json")
