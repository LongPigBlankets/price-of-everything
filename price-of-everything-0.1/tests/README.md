# Tests

Run from the Godot project root (`price-of-everything-0.1/`):

```bash
python3 tools/run_tests.py                          # whole unit suite
python3 tools/run_tests.py --tags market            # one feature
python3 tools/run_tests.py --tags market,stockpile  # any of these tags
python3 tools/run_tests.py --tags production+stockpile   # tests carrying ALL of these
python3 tools/run_tests.py --test market_buy        # tests whose name contains this
python3 tools/run_tests.py --list                   # files, tests and tags; runs nothing
```

`run_tests.py` launches `res://tests/test_runner.tscn` headless and fails the run on any
`SCRIPT ERROR` line as well as on a failed assertion. Anything after the script name is passed
to the Godot runner unchanged (it lands after `--` on the command line).

The e2e balance harness is **not** part of this suite. Run it separately:

```bash
"$GODOT_BIN" --headless --path . res://tests/e2e_stoneshore.tscn -- 100
```

The persistent [Pepper Valley Motors benchmark](../docs/pepper-valley-motors-benchmark.md)
runs one actual inland motor factory through the road/rail and port pipeline. It compares
regular shipments with a £40 middleman reference: £16 inputs, £16 outputs and £8 storage.
The middleman is arithmetic until provider service is implemented.

```bash
python3 tools/run_pepper_valley_benchmark.py --check-baseline
python3 tools/run_pepper_valley_benchmark.py --route rail --check-baseline
python3 tools/run_pepper_valley_benchmark.py --route rail-three-owned --check-baseline
python3 tools/run_pepper_valley_benchmark.py --route rail-three-owned --stage research --check-baseline
```

Current setup: `scenarios/pepper_valley_motors_middleman_ports.json`, 33 motors and
normal 3% base ports from turn one under `middleman_v1`. The reusable start is
`data/starts/pepper_valley_motors.json`. Current snapshots use `_v5`; temporary outputs
use `/tmp/pepper-valley-motors-benchmark-fee40/`, with `-rail` or `-rail-three-owned`
before `-fee40` for rail. Use `--write-baseline` only for an intentional reviewed update.

Rail owns seven sections by default; `rail-three-owned` owns three (£9 upkeep per turn),
with four completed government sections. Road maintenance is zero. Each run reports
storage, weight/distance freight, inland ad valorem, congestion, upkeep and port fees.
Government construction timing and infrastructure acquisition costs are excluded.

`--stage early` measures turns 10–19; default `base` measures 40–49. `output` applies
an actual +10% recipe-output modifier (36 motors after rounding); `research` also applies
the existing Depot Scheduling and Groupage rewards through the game modifier system.
These stages test rewards, not research acquisition timing or cost. Each has its own
snapshot and temporary directory suffix. Maximum tile throughput is 97 at base and 100
with output gains, with zero congestion.

Historical snapshots remain: v1 before congestion correction, v2 corrected 30-output
control, v3 33-output/£20, and v4 £40 with introductory port relief. `--balance targeted`
selects v3; `--balance control` selects v2 and requires explicitly reverting the trial
manifest first. Profiles never alter live recipe data. See the
[trial/revert instructions](../docs/reviews/targeted-output-gains-2026-09-19.md) and
[current progression review](../docs/reviews/middleman-fee40-progression-2026-09-19.md).

The additional `jit`, `furnace` and `furnace-jit` stages test the existing JIT unlock
and a same-tile Steelmaking furnace. The furnace imports 37 iron ingots and 20 coal,
feeds 32 of its 44 steel locally and sells 12 through a per-good surplus order.
Standalone JIT retains v5 snapshots; furnace stages use v7 with the £76 combined
provider reference (motor £40; furnace procurement £12 + sales £16 + storage £8).
Provider buildings trade independently: furnace sells 44 steel, motors buy 32. Only
direct logistics shares steel. Historical v5/v6 chain snapshots preserve superseded
local-sharing experiments. See the
[JIT/furnace comparison](../docs/reviews/pepper-jit-furnace-2026-09-19.md), including
the current redundant stockpile reserve that prevents a JIT storage saving.

## Layout

| Path | Role |
|---|---|
| `test_runner.gd` / `.tscn` | Discovery runner. Finds every `unit/test_*.gd`, instantiates it, runs each `func _test_*()` in source order, applies the tag filter, prints the summary, sets the exit code. File order is `RUN_ORDER` in the runner (smoke first, then sim core, then views). |
| `test_base.gd` | Base class every unit file extends. Holds `_check(ok, name)`, the shared preloads, helpers used by more than one file, `_await_turn_settled()` and `_boot_main_scene_once()`. |
| `unit/test_<feature>.gd` | One file per feature: smoke, map, production, stockpile, market, power, transport, construction, research, finance, advisors, decisions, events, special_orders, victory, save_load, tutorial, telemetry, goods_views, ui. |
| `scenarios/`, `snapshots/`, `fixtures/` | Data for the e2e harness and fixture-driven tests. |
| `*_test.tscn`, `*_smoke.tscn`, `ui_probe`, `ui_screenshot` | Standalone scene tests. Not run by the runner; launch them directly. |

## Tags

Each unit file declares its feature and, optionally, per-test tag lists:

```gdscript
extends "res://tests/test_base.gd"
const FEATURE := "stockpile"
const TAGS := {
	"_test_exhausted_input_source_falls_back_to_market": ["power", "production", "stockpile"],
}
```

Rules, in order:

1. A test listed in `TAGS` carries exactly those tags.
2. Otherwise it carries `[FEATURE]`.
3. An **empty** tag list (`FEATURE == ""`, or `TAGS[name] == []`) is a **wildcard**: the test is
   treated as relevant to every feature and runs under any `--tags` filter. `test_smoke.gd` is
   wildcard by design, so parse, boot and instantiate checks run on every filtered run.

A test that exercises several systems belongs in the file of its primary subject and lists the
others in `TAGS`. It then shows up under every tag it names. Nothing is duplicated or moved.

## Adding a test

1. Pick the file for the feature under test. Write `func _test_my_thing() -> void:` using
   `_check(condition, "message")`. No registration is needed; the runner discovers it.
2. If the test drives other systems as its subject (not just as a fixture), add a `TAGS` entry
   listing every feature it covers, including the file's own.
3. **Restore global state you touch.** Autoload state is shared across the whole run. Snapshot
   what you mutate and put it back at the end (the price-impact test is the pattern of record).
4. If you call `TurnManager.commit_turn()`, `await _await_turn_settled()` before restoring state:
   resolution yields a frame per phase, and the runner will otherwise wait for it after your test.
5. If you assert on state the main scene seeds (NPC ports, start buildings), call
   `await _boot_main_scene_once()` when it is missing, so the test also holds in isolation.
6. Tests may drive phases directly via `TurnManager.phase_started.emit(...)`; that is a supported
   contract.
7. Good ids vs names: `"coal"` is an internal name, ids are `g_0xx`. Resolve with
   `Catalog.get_good_by_internal_name("coal").get("id")`.

## Isolation the runner provides

Between tests the runner yields one frame (so `queue_free`'d fixtures actually die, and a stale
node in the `hex_map` group is not found first by the next test) and waits for any in-flight turn
resolution to finish. It also yields one frame before the first test so a test may parent a
fixture to the scene root without hitting "Parent node is busy setting up children".

Two perf tests ("road works: zero frames over 8 ms", "B4: ≤2% frames over 8 ms") sit close to
their budgets and can fail on a loaded machine; a failure in only those two is pass-equivalent.

## Dynamic middleman tariff analysis

`python3 tools/analyse_middleman_dynamic_fee.py` evaluates the proposed inclusive
0.5% price plus weight/location tariff against retained motor and independent-furnace
benchmarks. It leaves live rates and historical snapshots unchanged, checks density
precedence and the progression constraints, and writes the comparison to
`reports/balance/middleman_dynamic_fee_2026-09-19.json`. It is arithmetic sensitivity,
not a provider gameplay test. See the [review](../docs/reviews/middleman-dynamic-fee-2026-09-19.md).

## Logistics Hub model

`python3 tools/analyse_logistics_hub.py` evaluates the proposed installed vehicles and
per-turn hydraulic/tyre/fuel-or-battery recipes against saved road routes and costs.
It checks route adjacency, minimal corridor coverage and purchase markup, and reports
optimistic cost bounds, finite-payload sensitivities and unresolved timing assumptions.
See [the hub review](../docs/reviews/logistics-hub-capacity-2026-09-19.md). Economic targets
in the dynamic-fee analyser are report findings, not mandatory invariants: adverse
parameter choices still produce a report.

`python3 tools/analyse_logistics_hub_handoffs.py` models ten shipment-hop capacity
per installed vehicle, local radius-one coverage and carrier/hub hand-offs. It
checks original freight reconstruction, capacity allocation and billing conservation.
The proportional 100/125/160-LC recipe cases are separate design sensitivities; no
live operator hand-off or partial-leg billing is implemented.

`python3 tools/analyse_hub_rounding_weight.py` applies per-hub half-up consumption
rounding with a one-unit active minimum and zero idle use. It evaluates proposed
the selected light 1× / heavy 2× / ultra-heavy 5× / liquid 2× / hazard 4× / gas 3× LC factors, checks rounding boundaries and reports
the resulting recurring-cost floor. Selected factors are recorded in `scenarios/logistics_hub_lc_weights.json`; they are not yet live hub gameplay. Small-hub losses are intentional; high-utilization carrier comparisons remain the balance gate.

## Three chains × three logistics models

`python3 tools/run_pepper_five_factory_benchmark.py --check-baseline` verifies the
real two-tile motor/steel/wiring/copper-ingot/iron-ingot chain, with surplus sold from
the consuming tile and no mines. `python3 tools/analyse_pepper_chain_matrix.py`
combines it with retained one/two-factory runs, independent provider arithmetic and
the rounded local-hub model. See [the 3×3 review](../docs/reviews/pepper-three-by-three-2026-09-19.md).

The same runner accepts `--double` for ten factories on the same two tiles. That
layout currently fails full-output qualification because of storage/input constraints;
do not write or treat it as a passing baseline. The retained diagnostic and
`python3 tools/analyse_pepper_double_chain.py` distinguish this from full-output
sensitivities, including separate-batch and 100-unit consolidated hub workloads.
See the [fourth-scenario review](../docs/reviews/pepper-double-chain-2026-09-19.md).

### Consolidating hub four-by-three model

Run `python3 tools/analyse_pepper_chain_matrix.py` followed by `python3 tools/analyse_pepper_consolidation.py`. The latter runs the Godot freight quote probe at recurring full throughput, checks grouping/payload invariants, and writes `reports/balance/pepper_four_by_three_consolidated_2026-09-19.json`. This is a design model; the doubled chain is not a passing production baseline.

### Seven-tile, three-chain rail model

Run `python3 tools/analyse_pepper_seven_tiles.py` for fifteen factories around one hub with L2 rail. Checks include per-tile material conservation, rail-only routes, actual L2 on every traversed tile, and aggregate goods economics. The report retains a controlled warehouse-cost estimate and is not a production regression baseline.

### Compact district handoff quote trial

`python3 tools/analyse_pepper_district.py` tests ten factories across four tiles and all seven covered handoff locations. It checks material/delivery conservation and actual road L3/rail L2 carrier quotes. This is not a production baseline; owned-road congestion costs remain unpriced and are flagged in the report.

### Hub consumption / L1 rail sensitivity

`python3 tools/analyse_hub_consumption_sensitivity.py` reprices all compact-district handoffs with L1 rail and compares existing per-turn rounding with proposed accumulated-usage averages. No default operating rule is changed.

### L1/L2 hub delta factorial trial

`python3 tools/analyse_hub_factorial.py` runs isolated owned-rail quote probes in parallel, keeps physical journeys continuous across operator handoff, and compares separate/combined input-rate and capacity changes. The report retains the existing per-turn minimum as a control; no candidate rates are applied to gameplay.

## Live middleman phase 1

Run `python3 tools/run_middleman_phase0.py --phase1 --full` to run all unit checks, preserved direct-route controls and the 50-turn real provider benchmark. The internal start is `data/starts/pepper_valley_motors_middleman.json`; its explicit building mode activates private supply/production/sale settlement. This is separate from the historical arithmetic analyses above. See [implementation and scope](../docs/middleman-phase-1-implementation.md).

### Middleman phase 2

`python3 tools/run_middleman_phase0.py --phase2 --full` adds presentation/forecast checks and the real 50-turn public Pepper Valley introduction + second-factory construction exercise. See [P2 implementation](../docs/middleman-phase-2-implementation.md). Windowed screenshots: `res://tools/middleman_p2_preview.tscn`, with `-- --menu` for the selector.

### Middleman phase 3

`python3 tools/run_middleman_phase3.py --full` preserves earlier controls and runs seven actual chain/remote-source cases. Side-mode tests cover private/shared ownership, fees, stock capacity, live standing-order quantities and v12→v13 saves. See [P3 implementation](../docs/middleman-phase-3-implementation.md).
