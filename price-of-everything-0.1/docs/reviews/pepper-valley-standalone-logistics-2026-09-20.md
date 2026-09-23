# Pepper Valley standalone logistics comparison — 2026-09-20

This benchmark places one of the six recipes raised in the targeted profit pass on Pepper Valley tile `tile_5_4`. It runs the actual `Production`, `TransportService`, `MarketState`, and `MiddlemanService` code for 70 turns, discards construction and the first 35 operating turns, and averages the next ten repeating turns. Every case buys all material inputs at the same market prices; the middleman case also uses those market prices internally. Power stays on the grid.

For the two global-market cases, a completed level-1 corridor is seeded from Pepper Valley to the nearest port. Roads are government-built and have no player maintenance. Three of the rail tiles are player-owned, matching the earlier benchmark assumption; the other rail tiles are government-built. Market sales and market input arrivals keep their normal transport delay; the warm-up is long enough for both directions to settle.

The six-tile Pepper Valley–port corridor takes three road L1 legs, two rail L1 legs and one rail L2 leg in both directions.

## Results

Profit is retained cash change per turn after goods, logistics, warehouse, factory labour, maintenance, power, tax and dividend accounting. “Port” combines the inbound market-port charge and outbound sea insurance/handling; the flat port fee is currently zero. “Land” is the road/rail component. Middleman fee is the dynamic provider fee for that building’s complete material batch (input + output service and its provider storage allocation).

The rail figures include £9.00/turn for the three player-owned L1 rail tiles (the roads column includes £0 infrastructure maintenance); factory maintenance is included in both columns’ profit.

| Recipe | Logistics intermediary: profit / fee | Global market, roads L1: profit / land / port / warehouse | Global market, rail L1: profit / land / port / warehouse | Global market, rail L2: profit / land / port / warehouse |
|---|---:|---:|---:|---:|
| Building Frame Manufacture (`r_057`) | £24.84 / £28.13 | £-6.77 / £31.88 / £27.75 / £2.05 | £5.84 / £10.63 / £27.71 / £2.05 | £11.50 / £5.31 / £27.66 / £2.05 |
| Computer Assembly (`r_125`) | £35.73 / £9.19 | £-6.06 / £3.65 / £52.61 / £3.10 | £-12.35 / £1.22 / £52.53 / £3.10 | £-11.48 / £0.61 / £52.44 / £3.10 |
| Large Vehicle Engine Manufacturing (`r_073`) | £28.05 / £18.69 | £-28.60 / £43.86 / £32.30 / £2.84 | £-7.95 / £14.62 / £32.24 / £2.84 | £-0.24 / £7.31 / £32.19 / £2.84 |
| Wind Turbine Manufacturing (`r_059`) | £25.65 / £12.72 | £-1.27 / £19.69 / £20.98 / £1.67 | £3.07 / £6.56 / £20.95 / £1.67 | £6.58 / £3.28 / £20.92 / £1.67 |
| Segmented Assembly Wind Turbines (`r_061`) | £38.73 / £12.59 | £19.81 / £19.63 / £20.35 / £1.59 | £22.65 / £6.54 / £20.31 / £1.59 | £24.88 / £3.27 / £20.28 / £1.59 |
| Heavy Vehicles Assembly (`r_204`) | £85.06 / £35.38 | £-39.37 / £98.21 / £90.42 / £6.35 | £17.82 / £32.74 / £90.27 / £6.35 | £29.53 / £16.37 / £90.13 / £6.35 |

The market goods basket is identical in all three columns; only its delivery and sale route changes:

| Recipe | Material purchases / turn | Product sales / turn |
|---|---:|---:|
| Building Frame Manufacture | £333.81 | £523.23 |
| Computer Assembly | £743.36 | £886.82 |
| Large Vehicle Engine Manufacturing | £399.40 | £598.46 |
| Wind Turbine Manufacturing | £258.53 | £389.76 |
| Segmented Assembly Wind Turbines | £238.21 | £389.76 |
| Heavy Vehicles Assembly | £1,203.96 | £1,594.04 |

## Reading the result

- At one Pepper Valley building, the intermediary remains the most profitable option in all six cases. Its dynamic fee is below the direct market system’s combined inland haul, port charges and warehousing, while the material purchase and sale prices are unchanged.
- Rail L1 remains better than roads L1 for every recipe because the same corridor completes in fewer, cheaper legs, even after the three-tile rail maintenance charge. The profit advantage ranges from about £-6.29 per turn for computers to about £21.55 for heavy vehicles; computers are the one case where the maintenance charge makes rail worse than roads.
- Rail L2 halves the inland rail charge on this six-tile corridor and improves profit by about £0.88–£11.72 per turn over rail L1. It still does not overtake the intermediary at one building: the closest case is segmented wind turbines at £24.88 versus £38.73, while heavy vehicles reach £29.53 versus £85.06.
- The targeted output/price pass raises the ceiling enough for segmented wind turbines to clear £20/turn with rail L1 under the three-tile maintenance assumption. Heavy vehicles reach £17.82; ordinary wind, building frames, large vehicle engines and computers remain below zero or low at this single-building scale, so the intermediary is still the intended early choice.
- This is consistent with the intended progression: the intermediary is the early one-building choice, while direct transport only overtakes after volume, infrastructure ownership/levels, or chain consolidation removes enough per-shipment overhead.

## Infrastructure level diagnosis

Road and rail level ranges were already present in `EconomyConfig` (`roads` 2/3/5 tiles per turn and `rail` 4/6/9), and `Catalog._turn_move_neighbours()` already uses the departure tile’s level. Runtime upgrades through `BuildingWorks.set_tile_infra_level()` also mirrored the level into `Catalog` and cleared the route cache.

The visible failure was the authored/demo level pass in `scripts/world_map.gd`. `_apply_demo_infra_levels()` wrote `HexMap.tiles[*].infrastructure_levels` for the map and UI but never called `Catalog.set_tile_infra_level()`. Routing is headless and reads Catalog’s mirror, so those tiles silently stayed at level 1 for pathfinding even while the map displayed level 2 or 3. The pass now calls the Catalog setter after writing each level, so the displayed and routed levels agree. The existing construction unit test continues to lock the 9-tile rail comparison (three L1 moves versus one L3 move).

Benchmark artifact: `tools/recipe_profitability_case.gd` now accepts `--site=tile_5_4`, `--mode=middleman|market`, `--route=roads|rail`, and `--infra-level=1..3`; the default Stoneshore profitability runner remains unchanged.
