# Green / Grey Power — Intermittency, layered on the single `power` good

Status: **IMPLEMENTED** (branch `power-allocation`). The single `power` good and the
`output_name == "power"` discriminator are **untouched**; green/grey + intermittent/steady
are tracked as **quality flags on top** of the existing grid. No good split, no save
migration, no ~70-site refactor.

Two mechanics:
1. **Intermittency** — solar/wind produce *intermittent* green; a recipe running on
   **unfirmed** intermittent power produces less. Grey and steady green never derate.
   **Storage firms intermittent → steady, per tile.**
2. **Greenest victory track** — all green (intermittent + steady) counts; grey does not.

Power carries **no carbon tax** (carbon stays upstream on coal/crude; coal ban later).

---

## How it works (as built)

**Quality classification** (`production._power_quality`, lists in `economy_config.gd`):
- `green_intermittent`: solar_farm, onshore_wind_farm, offshore_wind_farm.
- `green_steady`: hydro_power_plant; a generic power_plant burning a `POWER_STEADY_FUELS`
  fuel (compressed_biomass / bio_waste / carbonised_biomass).
- `grey`: coal/gas/everything else (firm default).

**Per-turn flow** (all in `production.gd`, power is grid-settled and never cascades):
1. Pre-cascade, `_compute_power_intermittency(all_buildings)` gathers green supply per
   producing tile (plants that can run), the power consumers, and each tile's firming cap,
   then calls the pure `_allocate_power_derates(...)`.
2. `_allocate_power_derates` (no scene deps — hex distance is string arithmetic):
   - **Producer-side firming**: a battery on a generating tile converts intermittent → steady,
     up to `BATTERY_STORAGE_CAP[level]` (L1/L2/L3 = 100/200/320 — abstracted cap, not a
     charge/discharge sim).
   - **Allocation**: each green source pushes to consumers **nearest-first**, then **L3 > L2 >
     L1**, then **most profitable** (last turn's `(price − unit_cost) × qty`, snapped to 2dp),
     then **oldest instance** (parsed from `inst_<id>_<hex>`). A consumer receives the source's
     int/steady mix proportionally. Deterministic total order (age is unique). Grid import is
     grey and fills the remainder (never derates).
   - **Consumer-side firming**: a battery on a consuming tile firms the intermittent it drew.
   - **Derate**: `derate = INTERMITTENCY_DERATE(0.4) × unfirmed_intermittent_share`, stored
     per instance_id.
3. The cascade's power branch tags **actual** generation into `summary.power_supply_by_quality`
   `{green_intermittent, green_steady, grey}`.
4. `_produce_outputs` multiplies each output by `1 − derate` (0 for grey/steady/no-power).
5. `victory_state` Greenest reads `power_supply_by_quality` (green = intermittent + steady;
   hydro/biomass now count), falling back to the building-id heuristic for old summaries.

Profitability uses last turn's `CostSolver.last_result` (no circularity); turn-1 / post-load
fall back to the instance-age tiebreak.

---

## Performance

Wrapped in a `TurnProfiler` section `power_alloc`. The e2e (`e2e_stoneshore`) is **coal-only**,
so green supply is empty there → the pass is ≈0 ms and the change is inert (433/87 unchanged).
Before/after benchmark: **perf-neutral** — the baseline's own runs swing p95 98.8–125.9 ms
(mean 49–50), and the after sits inside that band (mean 50.0, p95 125.8). The green path is
**not e2e-stressed** (no green plants in the scenario); it is unit-tested for correctness, the
allocation is bounded by construction (few green sources × the small player set), and the
`power_alloc` profiler section will surface any cost if a green-heavy late game emerges.

---

## Tests (tests/test_runner.gd)

`_test_power_quality` (classification), `_test_power_instance_age` (hex parse + ordering),
`_test_power_intermittency_alloc` (full-unfirmed → 0.4, storage firms → 0, steady → 0, 50%
share → 0.2, level priority, oldest tiebreak), `_test_greenest_reads_quality`. Suite 766/0.

---

## Locked decisions

Derate 0.4 · storage cap 100/200/320 (abstracted) · firms at producer or consumer per tile ·
grid = grey · nearest → L3>L2>L1 → profit(2dp) → oldest · hydro + waste/biomass = steady green ·
no carbon tax on power · single `power` good kept (flags on top).

## Future / not in scope

Hydro drought sensitivity (later free update); a green-plant e2e scenario to stress the
allocation perf; the `g_077_green_power` / `g_078_grey_power` icons (committed earlier) are
available for power-quality UI but are not goods.
