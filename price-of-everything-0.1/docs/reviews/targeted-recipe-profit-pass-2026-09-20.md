# Targeted recipe profit pass — 2026-09-20

This pass records the original six-recipe floor pass, then applies the same small-change test to terminal goods and an explicit construction-material supply follow-up.

## Applied changes

The active catalogue is `data/Goods - goodsMVP.csv` plus `data/recipes_all.csv`.

| Change | Before | After | Reason |
| --- | ---: | ---: | --- |
| Wind Turbine price | £119.192 | £129.9193 | +9% apex price shared by the two highlighted wind recipes |
| Heavy Vehicle price | £292.485 | £318.8087 | +9% highlighted apex price |
| Computer price | £90.3998 | £98.5358 | +9% highlighted apex price |
| Building Frame output (`r_057`) | 25 | 28 | +12% output; avoids raising construction material prices |
| Large Vehicle Engine output (`r_073`) | 10 | 11 | +10% output; improves an intermediate feeding terminal vehicle recipes |
| ICE/V8 Engine output (`r_071`, `r_072`) | 6 | 7 | One extra unit for the two qualifying engine recipes |
| Solar Panel price | £44.5997 | £48.6137 | +9% for the qualifying apex solar recipe |
| Sodium Battery price | £22.7411 | £25.0152 | +10% for the qualifying apex battery recipe |
| Electric Concrete output (`r_030`) | 28 | 31 | +10.7% output for a consumer-free good |
| uPVC Window output (`r_055`) | 18 | 20 | +11.1% output; its only consumer is terminal building frame production |
| Window output (`r_056`) | 16 | 18 | +12.5% output; its only consumer is terminal building frame production |
| Automated Hydraulics output (`r_237`) | 18 | 20 | +11.1% output; all five consumers are terminal equipment/vehicle recipes |
| Concrete Firing output (`r_029`) | 21 | 23 | +9.5% output; construction-material supply is intentionally increased |
| ICE Construction Equipment output (`r_033`) | 13 | 14 | +7.7% output; construction-equipment supply is intentionally increased |
| Sodium Ion Battery output (`r_102`) | 6 | 7 | +16.7% output; the one-unit step is unavoidable at this small batch |
| Lithium Ion Battery output (`r_032`) | 6 | 7 | +16.7% output; the one-unit step is unavoidable at this small batch |
| Lithium Phosphate Battery output (`r_099`) | 8 | 9 | +12.5% output |
| Primary Copper Wiring output (`r_008`, `r_233`) | 33 | 37 | +12.1% output; the 3-unit e-waste co-product (`r_107`) is unchanged |
| Copper Pipe output (`r_026`, `r_219`, `r_220`) | 18 / 27 / 48 | 20 / 30 / 53 | +10–11% output; copper pipe is a building-frame input, so this deliberately changes construction-material supply |
| Electrical Components output (`r_126`, `r_127`) | 12 / 21 | 13 / 23 | +8.3–9.5% output; these routes feed construction kits as well as downstream factories |
| Steel output (`r_003`, `r_025`, `r_077`, `r_234`, `r_235`) | 44 | 49 | +11.4% output |
| Electric Arc Steel output (`r_076`) | 54 | 60 | +11.1% output |
| Scrap Recycling steel output (`r_106`) | 27 | 30 | +11.1% output; available when recycling recipes are enabled |

The price changes are deliberately limited to apex goods or intermediates whose consumers are all terminal outputs. The engine candidates use one extra output unit instead of raising the intermediate price, so the two ICE-car recipes keep their existing input costs. No construction kit quantities were changed.

Heavy Vehicle is also an input to rail level-2/level-3 upgrade kits, so its price increase raises those upgrade quotes. That is the one deliberate construction-cost side effect in this pass.

## Live benchmark

The values below are retained cash change per turn from the real engine, averaged over ten turns after first successful production. The comparison baseline is `reports/recipe_profitability/standalone-current-2026-09-20/summary.json`; the final run used:

```text
python3 tools/run_recipe_profitability.py --out /tmp/recipe-profitability-final-all-2026-09-20 --recipes r_030 r_055 r_056 r_057 r_058 r_059 r_061 r_071 r_072 r_073 r_102 r_117 r_118 r_125 r_204 r_237 --jobs 8
```

| Recipe | Baseline | Final | Change |
| --- | ---: | ---: | ---: |
| Building Frame Manufacture (`r_057`) | £-3.63 | £40.58 | +£44.21 |
| Computer Assembly (`r_125`) | £-31.19 | £33.86 | +£65.04 |
| Large Vehicle Engine Manufacturing (`r_073`) | £-8.09 | £36.66 | +£44.75 |
| Wind Turbine Manufacturing (`r_059`) | £5.93 | £31.48 | +£25.55 |
| Segmented Assembly Wind Turbines (`r_061`) | £24.17 | £44.66 | +£20.49 |
| Heavy Vehicles Assembly (`r_204`) | £7.48 | £95.78 | +£88.30 |
| Solar Panel Manufacturing (`r_058`) | £5.89 | £31.41 | +£25.52 |
| Electric Concrete Production (`r_030`) | £19.67 | £31.36 | +£11.69 |
| uPVC Window Manufacturing (`r_055`) | £21.42 | £40.80 | +£19.37 |
| Window Manufacturing (`r_056`) | £17.59 | £37.83 | +£20.24 |
| ICE Engine Manufacturing (`r_071`) | £-1.16 | £43.32 | +£44.47 |
| V8 Engine Manufacturing (`r_072`) | £8.92 | £49.77 | +£40.84 |
| Sodium Ion Battery Manufacturing (`r_102`) | £15.87 | £26.05 | +£10.17 |
| Hydraulic Components Automated Assembly (`r_237`) | £16.96 | £26.97 | +£10.01 |

The segmented wind recipe was already above £25 and remains so; its increase is smaller because its starting margin was higher.

The engine output changes leave the terminal ICE car recipes essentially unchanged in the same run (`r_117`: £28.89 versus £28.86; `r_118`: £66.86 versus £66.86).

## Construction and core-material follow-up

The follow-up deliberately accepts cheaper construction inputs and a larger supply of the core materials used by the motor, vehicle and battery chains. The real-engine cases completed for every changed active recipe. At Stoneshore, the changed recipes now produce the following standalone operating profits: Concrete Firing £20.09, ICE Construction Equipment £74.85, Sodium Ion Batteries £41.97, Lithium Ion Batteries £41.17, Lithium Phosphate Batteries £75.77, Copper Wire Drawing £28.18, Copper Electrowinning £66.45, and the steel routes between £20.41 and £43.90 per turn. The added copper-pipe and electrical-component yields are supply-side construction changes: Copper Pipe Hot Rolling is £19.92, Electrical Components Production is £20.28, while their researched alternatives reach £35.76–£47.08. The base component routes therefore remain below the £25 target and should be rechecked with a construction-price pass if that margin target is still required. These are isolated recipe cases; a full-chain run is still needed to measure market-price and integration effects.

## Candidate rule and exclusions

The graph check counted recipes consuming each output good. A candidate was eligible when it had at most five consumers and every consumer output had no further recipe consumers. The additional candidates retained after the real-engine check were the consumer-free solar, sodium battery, and electric concrete recipes, the two terminal-window suppliers, the two engine recipes, and automated hydraulics. Each reaches at least £25 per turn with the listed small move.

The following candidates were tested and left unchanged because the same small output move did not reach £25 per turn: fuels (`r_022`) and factory hydraulics (`r_236`). Copper pipe (`r_026`, `r_219`, `r_220`) and electrical components (`r_126`, `r_127`) are now included because they directly affect construction-material availability; their output changes are a supply decision rather than a claim that every base component route clears £25. Power recipes were also left unchanged because their small output moves do not provide a useful margin lift. The later construction-material decision intentionally supersedes the earlier exclusion of concrete firing (`r_029`). This keeps the pass targeted rather than lifting every low-margin recipe indiscriminately.
