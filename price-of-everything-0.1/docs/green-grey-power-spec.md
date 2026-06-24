# Green / Grey Power — Interchangeable Electricity Goods (design spec)

Status: **design only, pending approval. No implementation in this branch** — only the
two icons (`g_077_green_power`, `g_078_grey_power`) and the bake tool are committed.

Goal: split electricity into **two interchangeable goods** — `green_power` (clean:
solar / wind / hydro) and `grey_power` (fossil: coal / gas / waste) — mirroring the
carbon-substitution group (coal / petroleum needle coke / carbonised biomass). Consumers
accept **either** to satisfy their power demand, but the carbon decarbonisation squeeze
(rising CO₂ tax on grey) and a green premium make the *mix* a live strategic choice that
feeds straight into the **Greenest** victory track.

---

## 1. How power works today (verified)

- **One good, `g_010 power`** (`good_type=power`, `transport_class=electricity`,
  `is_buyable/sellable=TRUE`, `decay_rate=0`, `is_fossil_fuel=yes`).
- **Power is a GRID resource, not a stockpiled/transported good.** In `production.gd`'s
  PROCESS pass, a power building's output goes to `Power.record_produced(tile_id, qty)`
  (the `output_name == "power"` branch), **not** to a `Stockpile`. Consumers draw via the
  building's `energy_req` → `Power.record_drawn(...)`. The `Power` autoload aggregates
  supply vs demand each turn and settles the deficit/surplus against a national grid at
  fixed buy/sell prices (`EconomyConfig`).
- **Producers** (recipes outputting `power`): `r_004` coal_power (coal→power), `r_037`
  onshore wind, `r_038` gas CCGT, solar/offshore/hydro, plus a waste-to-power route.
- **Consumers**: every building with `energy_req > 0` draws from the grid; there is no
  per-type power input on recipes.
- **Greenest victory track** (already shipped) measures the **green share** of generation
  using `summary.power_supply_by_type` for the green building ids (solar `b_024`, onshore
  `b_025`, offshore `b_026`) over total `power_supply`. This feature formalises that share
  as goods.
- **"Interchangeable like carbon"**: coal / pet_coke (`g_075`) / carbonised_biomass
  (`g_076`) are not a single code switch — they're offered as **parallel recipe routes**
  for the same output, with `is_fossil_fuel` + `co2_tax_multiplier` + `green_sales_premium`
  CSV columns making the dirty/clean choice bite economically. Green/grey power should reuse
  exactly this lever, not invent a new one.

---

## 2. The one decision that shapes everything

Power is grid-settled, **not** a stockpiled recipe input. So "two power goods" can mean two
quite different things:

- **Option A — typed grid (recommended).** Keep the single grid and the `energy_req` model,
  but **tag each unit of supply green or grey by plant type**. The `Power` autoload tracks
  two supply pools; demand is satisfied from the blend (green drawn first, or pro-rata — a
  sub-decision). `green_power`/`grey_power` are the *names* of those pools (and what the grid
  buys/sells). The grey pool carries the CO₂ tax; green earns the premium. **Smallest change,
  fits the existing grid + Greenest track directly.**
- **Option B — full goods.** Make `green_power`/`grey_power` real stockpiled, transported
  goods that plants produce into stockpiles and buildings consume as **recipe inputs**
  (replacing `energy_req`). This is a much larger change (transport of electricity, storage,
  per-building input wiring) and fights the existing grid model. **Not recommended for EA.**

> **Recommendation: Option A.** The rest of this spec assumes A. Flag if you want B.

---

## 3. Proposed goods (CSV rows) — *values are balance decisions, need sign-off*

Add to `data/Goods - goodsMVP.csv` (next free ids):

| col | green_power (g_077) | grey_power (g_078) |
|---|---|---|
| internal_name | green_power | grey_power |
| display_name | Green Power | Grey Power |
| category | energy | energy |
| transport_class | electricity | electricity |
| good_type | power | power |
| decay_rate | 0 | 0 |
| base_price | = current power | = current power |
| is_buyable / is_sellable | TRUE / TRUE | TRUE / TRUE |
| is_fossil_fuel | no | **yes** |
| co2_tax_multiplier | 0 | **> 0** (the squeeze lever) |
| green_sales_premium | **> 0** | 0 |

`g_010 power` then becomes either (a) a deprecated alias kept for save-compat, or (b)
removed with a migration. **Decision needed** (see §7).

---

## 4. Production mapping (which plant makes which)

- **Green** → `green_power`: solar_farm `b_024`, onshore_wind `b_025`, offshore_wind `b_026`,
  hydro_power_plant `b_027`. (These are exactly the Greenest track's green ids + hydro.)
- **Grey** → `grey_power`: coal_power `b_003`, gas CCGT, and the existing power_plant routes.
- **Ambiguous, needs a call**: waste-to-power / biomass routes (`r_109`) — green, grey, or a
  third bucket? (Carbonised biomass is `is_fossil_fuel=no` but combusted.) **Decision needed.**

Mechanically: the power-output branch in `production.gd` already knows the producing
`building_id`; it would record into the green or grey pool instead of one `power` total —
a near-mirror of the `power_supply_by_type` accumulation the Greenest track added.

---

## 5. Consumption & interchangeability

- Buildings keep `energy_req` (no per-recipe power inputs). The grid satisfies demand from
  **green + grey combined** — that is the interchangeability: a factory doesn't care which
  it gets, exactly like a furnace doesn't care which carbon it burns.
- **Draw order** (sub-decision): green-first (rewards building clean capacity) vs pro-rata
  (mix reflects the real fleet). Green-first couples cleanly to the Greenest track.
- **The squeeze**: the grey pool pays `co2_tax_multiplier` (rising over the game per the
  carbon schedule); green pays none and can earn the premium on surplus sold to the grid.
  So as the squeeze tightens, a grey-heavy grid bleeds money — the intended pressure.

---

## 6. Victory / balance interactions

- **Greenest track**: green share = green_power supply ÷ (green + grey). This *replaces* the
  building-id-list heuristic with a first-class number — cleaner, and behaviour-preserving if
  the green plant set matches. Minor change to `victory_state.gd` (read the typed pools).
- **Balance levers (all need sign-off, rule #7)**: the two `base_price`s, `grey` CO₂
  multiplier, `green` premium, grid buy/sell prices for each pool, and the draw order. These
  decide whether going green is worth it — the core of the feature.

---

## 7. Open decisions (please confirm before implementation)

1. **Option A (typed grid) vs B (full goods)?** — recommend A.
2. **Keep `g_010 power` as a compat alias, or migrate it away** (save-schema change)?
3. **Draw order**: green-first vs pro-rata.
4. **Waste/biomass power**: green, grey, or separate?
5. **Balance starting values** for the table in §3 + grid prices (or "use placeholders,
   tune in the e2e harness").

---

## 8. Implementation phasing (after approval)

1. Goods rows (g_077/g_078) + retire/alias g_010 (+ save migration if removed).
2. `Power` autoload: split supply into green/grey pools; grid settlement per pool.
3. `production.gd`: route power output to the pool by `building_id`.
4. `victory_state.gd`: Greenest reads the typed pools.
5. Recipe/CSV wiring + unit tests (pool accounting, tax on grey, Greenest parity) + an
   e2e balance pass to tune §6 levers.

---

## 9. Already done in this branch

- `g_077_green_power`, `g_078_grey_power` icons (medium + small), baked from the blue-screen
  bolt art via `tools/bake_power_icons.gd` — three bolts, outer two recoloured to the left's
  amber, green/grey core. **Icons only; no goods/recipes/grid changes.**
