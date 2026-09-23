# Targeted output and terminal-price trial — 19 September 2026

> Follow-up: the current £40 tariff and replacement of introductory port relief are covered in the [fee/progression review](middleman-fee40-progression-2026-09-19.md). The £20 results below remain historical evidence.

Status: **applied trial on `codex/transport-middleman-layer`**, with an exact reversible field manifest. This follows the [balance review](middleman-balance-design-2026-09-19.md) and the user's direction to try output gains around 8–10%, use prices for batches below 12, and permit construction-material compensation if needed. This is a focused motor/equipment/car trial, not a blanket economy-wide change.

## Exact changes

| Recipe / good | Before | Trial | Change |
| --- | ---: | ---: | ---: |
| Motor Manufacture (`r_009`) output | 30 | 33 | +10% |
| SynRM Magnetless Motors (`r_065`) output | 29 | 32 | +10.34%, nearest integer |
| Axial Flux Motors (`r_066`) output | 30 | 33 | +10% |
| Hairpin Stator Motors (`r_203`) output | 30 | 33 | +10% |
| Construction Equipment ICE (`r_033`) output | 12 | 13 | +8.33% |
| Construction Equipment EV (`r_034`) output | 12 | 13 | +8.33% |
| ICE car base price (`g_056`) | £123.897 | £135.0477 | +9%, rounded to four decimals |
| EV car base price (`g_057`) | £267.722 | £291.8170 | +9%, rounded to four decimals |

Only these **eight CSV fields** changed. Input quantities, energy, staffing, upkeep, motor prices, construction/upgrade materials and all transport/port tariffs are unchanged. Research alternatives are changed together within the motor family. The factory's input/output *ratio* improves through yield, but its input quantities and suppliers' production quantities stay fixed.

The price-based car change applies to both ICE producers (batches 6 and 9) and EV Assembly (batch 5). A one-unit output increase would overshoot the requested range for those recipes. Construction equipment at exactly 12 qualifies for the output lever.

## Construction dependency check

ICE/EV cars are absent from recipe inputs, catalysts, CSV building kits and scripted `BuildingLevels` upgrade kits. Their price changes do not increase those construction costs. No compensating material reduction is necessary in this trial.

Heavy vehicles were considered for +9% pricing but **held at £292.485** after finding them in scripted road/rail upgrade kits: rail uses 2/6 vehicles for levels 2/3 and roads use 2 at level 3. Reducing a two-vehicle kit to one would be a much larger capital-cost change than the price rise. Heavy-vehicle recipes already retain positive margins in the control. The comparison still includes all three as downstream/research controls.

For a future small-batch good that is a construction input, treat repricing and kit adjustment as one explicit change. Compare each complete kit's old and new purchase value, including its freight where applicable, and choose integer quantities close to the old total while retaining required material types. If integer granularity cannot provide a modest correction, hold the price or review the whole kit instead of silently cutting a two-unit requirement in half. Also audit scripted upgrades, not just CSV construction columns.

## Pepper Valley: actual steady-state simulation

Same site, one motor factory, 32 steel + 32 copper wiring + 30 power, regular shipments on turns 40–49. Roads are public; the preferred rail case has three player sections and four completed public sections. All costs except output-dependent transport/port charges remain matched.

| Per-turn operating contribution, before tax/financing | Control: 30 motors | Trial: 33 motors |
| --- | ---: | ---: |
| Middleman reference, £10 purchases + £10 sales | +£2.09 | **+£35.22** |
| Public roads | −£33.86 | **−£3.86** |
| Rail, three player-owned sections | −£16.32 | **+£15.22** |
| Rail, all seven player-owned sections | −£28.32 | **+£3.22** |

Maximum per-tile flow is **97**, with no congestion surcharge. Road and rail results are actual game code, matching the earlier analytical estimates. The middleman column is still reference arithmetic; no middleman gameplay has been implemented. Road logistics rise from £55.95 to £59.08 because three extra motors are shipped; three-owned-rail logistics rise from £38.41 to £40.01.

V1 snapshots retain the original congestion bug; v2 retains the corrected 30-motor control; **v3** records this 33-motor trial. The old scenario contract is preserved and the new [targeted scenario](../../tests/scenarios/pepper_valley_motors_targeted_gains.json) explicitly versions the changed output. The same start and £10/£10 fee remain the anchor for future phases.

## Coastal producer and consumer regression

Nineteen matched cases before and after, each in a fresh real-engine Stoneshore Docks run. The normal construction handler, market pipeline, price impact, cost growth, tax and dividends remain active. All 38 runs produced on all ten sample turns and reconciled cash and components. These figures are **retained cash after tax/dividends**, unlike Pepper Valley's pre-tax contribution above; see the [methodology](../../tools/RECIPE_PROFITABILITY.md). The before/after source hashes differ in exactly the two intended CSVs.

| Recipe | Control retained cash/turn | Trial retained cash/turn | Change |
| --- | ---: | ---: | ---: |
| r_118 — Automated ICE Car Assembly | £-6.16 | £66.86 | £+73.02 |
| r_066 — Axial Flux Motors | £28.75 | £49.84 | £+21.09 |
| r_119 — EV Assembly | £-52.43 | £50.34 | £+102.77 |
| r_206 — Electric Heavy Vehicles Manufacturing | £38.26 | £38.30 | £+0.03 |
| r_203 — Hairpin Stator Motors | £30.56 | £51.65 | £+21.09 |
| r_207 — Heavy Electric Motor | £50.76 | £50.76 | £+0.00 |
| r_205 — Heavy Vehicles Automated Manufacturing | £31.06 | £31.06 | £+0.00 |
| r_074 — Hybrid Engine Manufacturing | £57.17 | £57.17 | £+0.00 |
| r_061 — Segmented Assembly Wind Turbines | £24.17 | £24.17 | £+0.00 |
| r_065 — SynRM Magnetless Motors | £17.18 | £39.29 | £+22.11 |
| r_059 — Wind Turbine Manufacturing | £5.93 | £5.93 | £+0.00 |
| r_054 — High Strength Glassmaking | £20.61 | £20.61 | £+0.00 |
| r_053 — Industrial Glassmaking | £7.73 | £7.73 | £+0.00 |
| r_033 — Construction Equiment Assembly (ICE) | £20.10 | £47.48 | £+27.38 |
| r_034 — Construction Equipment Assembly (EV) | £24.30 | £53.64 | £+29.34 |
| r_204 — Heavy Vehicles Assembly | £7.48 | £7.48 | £+0.00 |
| r_117 — ICE Car Production | £-32.71 | £28.86 | £+61.57 |
| r_009 — Motor Manufacture | £16.40 | £38.79 | £+22.39 |
| r_056 — Window Manufacturing | £17.59 | £17.59 | £+0.00 |

The motor ordering remains base < SynRM < Axial Flux < Hairpin. EV construction equipment remains ahead of ICE; automated ICE cars remain ahead of basic ICE cars; electric heavy vehicles remain ahead of automated combustion, which remains ahead of basic combustion. Nine unchanged control recipes match exactly. Electric heavy vehicles improve by about £0.04 through the simulated market response; there is no direct change to that recipe or its output price.

The producer/consumer coverage includes all eight current recipes that consume motors, all four motor producers, both construction-equipment producers, basic/automated ICE and EV cars, both combustion heavy-vehicle controls and three glass/window controls. These are isolated positions, not a new full-chain or long-campaign validation.

Raw [control results](../../reports/recipe_profitability/targeted-gains-2026-09-19-control/summary.json), [trial results](../../reports/recipe_profitability/targeted-gains-2026-09-19-trial/summary.json) and [paired comparison](../../reports/recipe_profitability/targeted-gains-2026-09-19-comparison.json) retain full precision, source hashes, per-turn traces and cost breakdowns.

## Interpretation

This trial provides an expansion surplus for the outsourced motor factory and makes its rail alternative profitable, while preserving input quantities and construction affordability. It also repairs the tested loss-making ICE/EV car positions using the small-batch price lever. Road-only Pepper Valley still loses approximately £3.86 per turn in the later port-rate window; it has not been declared profitable or pushed beyond the requested yield range to force it through.

Logistics ownership still contributes less than outsourcing at this factory's scale: three-owned-rail profit is roughly £20.01 below the middleman reference. The trial improves viability, not the relative incentive to own logistics. That requires a separate service-cost/scale/payback design. Upstream production integration remains a different comparison.

These results do not establish long-run price-impact equilibrium, multi-factory network capacity, construction payback, save migration of existing market prices, or whole-portfolio optimality. They are a controlled pilot with real production, purchasing, selling and cost settlement. Existing saves may retain their saved market prices; start a fresh match for the intended price trial.

## Reproduce or revert

The [manifest](../../data/targeted_output_gains_2026_09_19.json) records every original/new value. From the Godot project directory:

```sh
python3 tools/manage_balance_v4_data.py --manifest data/targeted_output_gains_2026_09_19.json --status
python3 tools/run_pepper_valley_benchmark.py --check-baseline
python3 tools/run_pepper_valley_benchmark.py --route rail-three-owned --check-baseline
python3 tools/run_pepper_valley_benchmark.py --route rail --check-baseline
```

To restore the pre-trial data, run the manifest manager with `--revert`. The control benchmark then uses `--balance control --check-baseline` (plus the route option for rail), which expects v2. To return to the trial, use `--apply`. These commands validate old/new values and refuse conflicting edits. Benchmark profile selection only chooses the expected contract; it does **not** secretly override live data. Default `--balance targeted` expects this trial and checks v3.

Validation: **4,109 unit checks passed, zero failures**; 19 paired coastal cases; road and both rail steady-state cases; exact eight-field diff and consumer/construction dependency audit. No new production mechanics or UI behaviour changed in this trial.
