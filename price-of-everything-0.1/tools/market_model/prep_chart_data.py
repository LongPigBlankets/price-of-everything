#!/usr/bin/env python3
"""Shape model outputs into chart_data.json for the artifact."""
import json

import os
ROOT = os.path.dirname(os.path.abspath(__file__))
RES = json.load(open(f"{ROOT}/scenario_results.json"))
T1 = json.load(open(f"{ROOT}/tier1_results.json"))
CAP = 40.0

impacted = [n for n, b in RES["base"].items() if b > 0]

def pinned_series(mean):
    dn, up = [], []
    for t in range(0, 301):
        dn.append(sum(1 for n in impacted if mean[n][t] <= -CAP + 0.5))
        up.append(sum(1 for n in impacted if mean[n][t] >= CAP - 0.5))
    return dn, up

adn, aup = pinned_series(RES["meanA"])
bdn, bup = pinned_series(RES["meanB"])

# net positions, per base, sorted
nu_rows = sorted(
    [{"name": n, "ratio": RES["nu"][n] / RES["base"][n], "nu": RES["nu"][n],
      "tier": RES["tier"][n]}
     for n in impacted if RES["tier"][n] != "apex"],
    key=lambda r: r["ratio"])
deficit = [r for r in nu_rows if r["ratio"] < -1][:14]
glut = [r for r in nu_rows if r["ratio"] > 1][-14:]
mid = [r for r in nu_rows if -1 <= r["ratio"] <= 1]

# current-model overlay for the shock chart: 0.1%/turn accrual t50-150 (both
# shocks land in the >2x band), 0.1%/turn recovery after. Same curve for both.
cur = []
a = 0.0
for t in range(0, 301):
    if 50 <= t <= 150:
        a = max(-CAP, a - 0.1)
    else:
        a = min(0.0, a + 0.1)
    cur.append(round(a, 2))

def pct(series):
    return [round((v - 1) * 100, 2) for v in series]

out = {
    "pinned": {"A_dn": adn, "A_up": aup, "B_dn": bdn, "B_up": bup, "n": len(impacted)},
    "nu": {"deficit": deficit, "glut": glut,
           "mid_n": len(mid), "mid_names": [r["name"] for r in mid]},
    "shock": {
        "steel_dump": pct(T1["tier1_steel_dump"]["steel"]),
        "steel_buy": pct(T1["tier1_steel_buy"]["steel"]),
        "wind_dump": pct(T1["tier1_thin"]["wind_turbine"]),
        "steel_control": pct(T1["tier1_base"]["steel"]),
        "current_model": cur,
    },
    "margins": [{"name": r[0], "now": round(r[2], 1), "a": round(r[3], 1),
                 "d": round(r[3] - r[2], 1)}
                for r in T1["margins"] if abs(r[3] - r[2]) > 40][:40],
}
json.dump(out, open(f"{ROOT}/chart_data.json", "w"))
ms = out["margins"]
print(f"pinned A t200: dn={adn[200]} up={aup[200]} of {len(impacted)}; margins rows={len(ms)}; mid goods={len(mid)}")
print("deficit top:", [r["name"] for r in deficit[:5]])
print("glut top:", [r["name"] for r in glut[-5:]])
