# Motor and heavy vehicle balance — 7 September 2026

Measured with the same isolated Stoneshore Docks scenario as `tools/RECIPE_PROFITABILITY.md`: ten consecutive operating turns, all inputs and power purchased, outputs sold, no advisors, research bonuses or loans. Profit is retained cash after operating costs, tax and dividends. Construction costs are excluded.

## Data changes

- Motor Manufacture, Axial Flux Motors and Hairpin Stator Motors: output 28 → 30.
- SynRM Magnetless Motors: output 27 → 29, preserving its one-unit difference.
- Both combustion heavy vehicle recipes: bodies 15 → 13 and large engines 11 → 10. Their inputs remain identical; batteries stay at 7 and fuel at 21.
- Electric heavy vehicles: bodies 15 → 13, large engines 11 → 4, add 27 motors. Batteries stay at 9.
- All heavy vehicle recipes still produce 5 vehicles. Prices, labour, maintenance and power requirements are unchanged.

Twenty motors would leave the electric recipe substantially more profitable than the combustion alternatives. The tested 27-motor mix keeps electric and automated combustion profits close, with electric slightly ahead.

| Recipe | Previous profit/turn | New profit/turn | Final sampled turn |
| --- | ---: | ---: | ---: |
| Motor Manufacture | £2.42 | £23.17 | £23.03 |
| SynRM Magnetless Motors | £2.84 | £23.44 | £23.11 |
| Axial Flux Motors | £19.56 | £34.16 | £33.63 |
| Hairpin Stator Motors | £21.54 | £35.97 | £35.35 |
| Heavy Vehicles Assembly | £-77.20 | £9.81 | £8.73 |
| Heavy Vehicles Automated Manufacturing | £-47.41 | £32.55 | £31.81 |
| Electric Heavy Vehicles Manufacturing | £-63.55 | £34.65 | £33.19 |

All seven recipes produced on all ten sampled turns. Related motor consumers were also rerun (16 cases total); their margins remain effectively unchanged. Car and construction equipment recipes still need a separate balance decision. Heavy Electric Motor (`r_207`) produces `large_engine`, not `motor`, so its output is unchanged.

Before-change snapshot: `data/balance_baselines/2026-09-07_pre-motor-heavy-vehicle.csv`. Final raw results and three-column export: `reports/recipe_profitability/sd-motor-heavy-final/`. The original full benchmark remains intact.

The maintained live data is `data/recipes_all.csv`. The old `build_recipes_all.py` explicitly refuses to run because it renumbers IDs, drops recipes and loses labour fields; it was not used for this edit.

## Validation

- All 16 headless cases completed and reconciled cash to the recorded costs.
- Parse check: 553 scripts, zero failures.
- Unit suite: 3,701 passed, zero failures. Two workforce-output assertions now derive their base quantity from the catalogue instead of hardcoding 28 motors.
- 100-turn Stoneshore regression: exit 0.
- The separate root Python CSV validator reports 16 existing issues in `data/goods.csv` and `data/recipes.csv`; both files are unchanged from HEAD and are not the Godot runtime data.

## Follow-up: motor base price reduced by 2.5%

Motor base price changed from £11.3283 to £11.0451 (rounded to four decimal places). Recipe quantities and all other goods prices are unchanged. The before-price-cut state is preserved in `data/balance_baselines/2026-09-07_pre-motor-price-cut.csv`.

The same ten-turn benchmark was repeated for all four motor producers, every visible recipe consuming motors, and both combustion heavy vehicle controls (14 cases). Latest results are in `reports/recipe_profitability/sd-motor-price-cut/`.

| Recipe | Before price cut | After price cut |
| --- | ---: | ---: |
| Axial Flux Motors | £34.16 | £28.75 |
| EV Assembly | £-54.71 | £-52.00 |
| Electric Heavy Vehicles Manufacturing | £34.65 | £39.86 |
| Hairpin Stator Motors | £35.97 | £30.56 |
| Heavy Electric Motor | £47.87 | £50.76 |
| Heavy Vehicles Automated Manufacturing | £32.55 | £32.55 |
| Hybrid Engine Manufacturing | £56.18 | £57.92 |
| Segmented Assembly Wind Turbines | £22.44 | £24.17 |
| SynRM Magnetless Motors | £23.44 | £17.21 |
| Wind Turbine Manufacturing | £3.22 | £5.93 |
| Construction Equiment Assembly (ICE) | £-18.88 | £-12.85 |
| Construction Equipment Assembly (EV) | £-29.65 | £-26.64 |
| Heavy Vehicles Assembly | £9.81 | £9.81 |
| Motor Manufacture | £23.17 | £16.51 |

Cheaper motors reduce producer revenue and purchased-input costs for consumers. Taxes, dividends and transport fees mean retained-profit changes need not equal the raw motor value change. Construction equipment remains loss-making under the all-market setup.

## Construction equipment: approved shared chassis and distinct powertrains

Both recipes now consume 20 steel, 8 rubber, 5 plastics and 2 electrical components. ICE adds 4 large engines and 1 motor; EV adds 10 motors and 3 lithium batteries. Both still output 12 equipment units. ICE assembly no longer consumes fuel. Output prices, labour and other operating constants are unchanged. Quantities represent game batches, not literal machine component counts.

The same 10-turn all-market test produced these results, after tax and dividends:

| Recipe | Before change profit/turn | New profit/turn | Final sampled turn |
| --- | ---: | ---: | ---: |
| Construction Equipment ICE | −£12.85 | £20.63 | £20.47 |
| Construction Equipment EV | −£26.64 | £24.82 | £24.68 |

Both recipes produced on every sampled turn and reconciled all cash costs. The before-change snapshot is `data/balance_baselines/2026-09-07_pre-construction-equipment.csv`; raw results and summary export are under `reports/recipe_profitability/sd-construction-equipment-final/`. Previous benchmark exports are historical and have been preserved.

Follow-up validation: 3,702 unit assertions and 723 end-to-end assertions passed, with a clean script parse check. The six-input change exposed a deferred-deletion minimum-width bug in the recipe sheet; detaching the closing sheet restores the panel from 560px to its original 501px, verified in a windowed capture. The legacy graph now refines port spacing using actual routed extents and finer candidate offsets, preserving the tested horizontal/vertical separation floors for the new connections.
