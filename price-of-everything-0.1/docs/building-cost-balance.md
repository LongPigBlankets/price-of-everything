# Building running costs — maintenance & labour (analysis + recommendation)

Status: **analysis only — no files changed.** Looks at
[`data/Buildings - buildingsMVP.csv`](../data/Buildings%20-%20buildingsMVP.csv)
(the only buildings CSV — there is no separate `buildings.csv`),
[`scripts/economy_config.gd`](../scripts/economy_config.gd) and how
[`scripts/production.gd`](../scripts/production.gd) /
[`scripts/catalog.gd`](../scripts/catalog.gd) actually charge them each turn.

---

## 1. How the two per‑turn costs are computed

Every player building pays, every turn (`production.gd` COSTS phase):

**Maintenance** — `_calculate_maintenance_cost()`:
- Reads the building's `maintenance_cost` column, but **`catalog.gd` multiplies it
  by `MAINTENANCE_MULTIPLIER = 2.0` at parse time** (line 75/793). So the real
  charge is **2 × the CSV value**.
- Falls back to `EconomyConfig.MAINTENANCE_PER_BUILDING = 1.0` only if the column
  is blank — which never happens (all rows are filled), so that constant is **dead
  code**, and confusingly it is *not* ×2‑scaled like the live path.

**Labour** — `_calculate_labour_cost()`:
- `cost = U·rate_U + S·rate_S + H·rate_H`, then `× MatchState.labour_multiplier`
  (0.75–1.25, default 1.0), where U/S/H are the building's
  `labour_(unskilled|skilled|h_skilled)_required` counts.
- Rates (per worker per turn): **unskilled 0.002, skilled 0.006, high‑skilled
  0.010** (ratio 1 : 3 : 5).
- Rates **compound every turn**: `rate · (1 + growth)^(turn−1)`, growth = +0.15 % /
  +0.25 % / +0.40 % per turn. So the wage bill drifts up over a long game (the
  stated intent: "margins compress over time").
- `STUB_*_PER_BUILDING` (100/50/50) is only a fallback for buildings with no
  labour data — also effectively dead, since every row has counts.

There is also an `energy_cost` column (e.g. `industrial_factory` = 10) that
`catalog.gd` parses into the building dict but **nothing ever reads** — a latent
third cost lever sitting unused.

---

## 2. Current values (turn 1, labour_multiplier = 1.0)

Labour £ = `U·0.002 + S·0.006 + H·0.010`. Maintenance £ = `2 × CSV`.

| Archetype (buildings) | maint CSV | **maint £** | labour U/S/H | **labour £** | **total £** | labour % |
|---|--:|--:|---|--:|--:|--:|
| Mine | 1 | 2.0 | 150/50/20 | 0.80 | **2.80** | 29 % |
| Furnace | 2 | 4.0 | 100/50/30 | 0.80 | **4.80** | 17 % |
| Big factory (industrial_factory, chem_plant) | 2 | 4.0 | 200/100/60 | 1.60 | **5.60** | 29 % |
| Standard production *(eaf, assembly, high‑tech, petro, poly, farm, forest, electrolyser, desal, water, solar, wind, hydro, battery, consumer, oil, recycling, water_pump, …)* | 2 | 4.0 | 100/50/30 | 0.80 | **4.80** | 17 % |
| Coal power | 1 | 2.0 | 50/280/300 | **4.78** | **6.78** | 70 % |
| Port | 10 | 20.0 | 0/0/0 | 0 | **20.0** | 0 % |
| Pipes / rails | 2 | 4.0 | 0/0/0 | 0 | **4.0** | 0 % |
| Roads / cables | 1 | 2.0 | 0/0/0 | 0 | **2.0** | 0 % |

**Bottom line:** a production building runs **£2.8–6.8/turn**, of which maintenance
is the large flat majority and labour is a near‑uniform afterthought.

---

## 3. Findings

1. **Labour is dormant and undifferentiated.** ~30 of 37 buildings share the
   identical 100/50/30 profile → £0.80, ~17 % of fixed cost. The
   unskilled/skilled/high‑skilled distinction (and the whole labour market the
   roadmap's people/politics panels will hang off) does essentially nothing early.
   A high‑tech chip plant and a sand pit pay the same wage bill.
2. **Maintenance is flat (£2 or £4), blind to capital intensity.** A £400
   electrolyser and an £80 mine both pay ~£4. Real plants scale opex with capital.
3. **`coal_power` is an outlier** (50/280/300 → £4.78 labour, 70 % of its cost) —
   almost certainly placeholder data. It quietly makes self‑power pricier than it
   looks (and than the recipe rebalance assumed).
4. **Most `build_cost_money` are placeholders (`1`).** Only the ~14 MVP buildings
   have real build costs; the rest cost £1 to build. So "maintenance = % of build
   cost" (the clean rule) can't be applied until build costs are filled in.
5. **The ×2 maintenance knob lives in `catalog.gd`,** not `economy_config.gd`, and
   silently doubles every CSV value — easy to miss when balancing.
6. **Two dead constants** (`MAINTENANCE_PER_BUILDING`, `STUB_*`) and **one dead
   column** (`energy_cost`).
7. **Magnitude is about right, the *shape* is wrong.** £2.8–6.8/turn is ~10 % of a
   typical recipe's batch revenue (e.g. £4.8 on a £40–60 batch) — a sensible drag
   and roughly what the recipe rebalance assumes. **So the fix is to differentiate
   and rebalance the split, not to inflate totals.**

---

## 4. Recommendation

### 4a. Differentiate labour by archetype (the main change)

Keep the rates (1 : 3 : 5 is fine) and the growth mechanic; change the **counts** so
the wage bill rises with sophistication. Headcount ≈ operation scale; skill mix ≈
how advanced the work is. Proposed:

| Archetype | U / S / H | **labour £** | rationale |
|---|---|--:|---|
| Farm / forest | 150 / 20 / 5 | 0.47 | lots of hands, low skill |
| Mine / oil / fracking | 200 / 40 / 10 | 0.74 | unskilled‑heavy extraction |
| Water (pump, desal, recycling) | 60 / 40 / 20 | 0.56 | small, semi‑skilled |
| Power (coal, gas, wind, solar, hydro) | 40 / 40 / 30 | 0.62 | lean crews *(fixes coal_power)* |
| Smelting (furnace, eaf) | 120 / 70 / 40 | 1.06 | skilled trades |
| Chem / refinery / electrolyser / bio | 100 / 90 / 60 | 1.34 | process engineers |
| Manufacturing (factory, assembly) | 150 / 100 / 60 | 1.50 | mixed production |
| **High‑tech manufactory** | 60 / 100 / 140 | **2.12** | high‑skilled‑heavy |
| Infra (roads, cables, pipes, rails, port, airport) | 0 / 0 / 0 | 0 | unmanned |

This spreads labour from **£0.47 (farm) to £2.12 (high‑tech)** — a real 4.5×
gradient — and, because high‑tech is high‑skilled‑heavy and high‑skilled wages
inflate fastest (+0.40 %/turn), **advanced production is the thing the wage‑growth
mechanic squeezes over a long game**, exactly where it should bite.

### 4b. Make maintenance reflect capital (two options)

- **Now (build costs are placeholders):** a small per‑archetype table instead of
  flat £4 — extraction/farm £1.0–1.5, smelting/manufacturing/power £3.0,
  chem/electrolyser/high‑tech £4.0 (capital‑heavy), infra per current (roads £1,
  pipes £1.5, rails £2, port £20).
- **Later (preferred):** once real `build_cost_money` values exist for all
  buildings, set **maintenance ≈ 1.5 %/turn of build cost** (floored ~£1, capped
  for mega‑infra like the £10 000 port). Self‑documenting and scales automatically.

Resulting totals stay in the current £1.5–6 band but now *mean* something:

| Archetype | maint £ | + labour £ | **total £** |
|---|--:|--:|--:|
| Farm | 1.0 | 0.47 | **1.47** |
| Mine | 1.5 | 0.74 | **2.24** |
| Power | 3.0 | 0.62 | **3.62** |
| Furnace | 3.0 | 1.06 | **4.06** |
| Manufacturing | 3.0 | 1.50 | **4.50** |
| Chem / electrolyser | 4.0 | 1.34 | **5.34** |
| High‑tech | 4.0 | 2.12 | **6.12** |

Labour is now **25–35 %** of fixed cost everywhere (vs 17 % flat) and the total
tracks sophistication.

### 4c. Housekeeping (not balance, but worth doing)

- Move the `×2` maintenance factor out of `catalog.gd` into a named
  `EconomyConfig` constant (or just bake it into the CSV values and drop the
  multiplier) so there's one obvious place to tune.
- Delete or wire the dead `MAINTENANCE_PER_BUILDING` / `STUB_*` fallbacks.
- **`energy_cost` column:** either wire it as a flat per‑turn power draw per
  building (a nice extra integration lever — buildings burn some power just to
  exist, rewarding self‑generation) or remove it. Currently it misleads.

### 4d. Keep
Rates (0.002 / 0.006 / 0.010), the compounding growth, and the 0.75–1.25
`labour_multiplier` policy lever are all fine — differentiating the counts is what
gives them teeth.

---

## 5. Link to the recipe rebalance

The recipe generator
([`scripts/rebalance_recipes.py`](../scripts/rebalance_recipes.py)) hardcodes a
`FIXED` per‑building dict using *today's* numbers (mine 2.8, furnace 4.8, chem 5.6,
high‑tech 4.8, …). If these recommendations are adopted, update that `FIXED` dict
to match (mine 2.24, furnace 4.06, chem 5.34, high‑tech **6.12**, …) and re‑run —
mostly small shifts, except high‑tech goods get a little pricier (their labour
roughly doubles), which *reinforces* the "advanced goods reward integration"
design.

## 6. What I would not change
- Total fixed‑cost magnitude (£~1.5–6/turn) — it's already ~10 % of recipe
  revenue, the right drag.
- Wage rates and growth percentages.
- Infrastructure costs (roads/cables/pipes/port) — those are tuned by the roads
  work, not the production economy.
