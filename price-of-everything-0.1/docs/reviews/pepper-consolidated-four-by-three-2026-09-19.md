# Consolidating hubs: four setups × three transport models

> The two-chain scenario now selects L1 rail over L2 roads, with identical hub costs. See the [infrastructure comparison](pepper-two-chain-infrastructure-2026-09-19.md). The original L1-road results below remain the historical control.

Default hub behaviour is now consolidation at the same tile and availability turn, for compatible equipment and a shared directed onward segment. Original origin and departure turn do not matter. Loads may be reassembled at later covered meeting tiles without adding a waiting turn or gaining extra movement. This supersedes the previous separate-batch and same-origin alternatives.

## Working numerical assumptions

Use 100 **weighted** cargo units per load and one LC per loaded edge, applying the agreed class factors once. Ten LC per installed vehicle and 125 LC per operating recipe remain unchanged. The 100-unit payload is provisional; adopting consolidation does not finalize this number. Coal/ores use a bulk equipment pool; ingots/steel/wiring/motors use a general dry-cargo pool. Empty repositioning and equipment-specific fleet capital are not yet priced.

All streams recur once per turn. The steady model assumes arrivals and local goods are available at each tile’s dispatch window; it does not replay the engine’s intra-turn events. Different original departure turns can therefore meet after different journey lengths. A live implementation must respect the available travel budget when reassembling cargo. No goods are teleported and no holding delay is assumed.

Prices, recipes, port fees, warehouse charges, surplus policy and two-tile layout remain unchanged. The hub uses diesel, buys operating inputs through the middleman, and consumes at least one of each recipe input when active. The five-factory chain is motors + steel + copper wiring + copper ingots + iron ingots, without mines. Middleman buildings still trade independently.

## Operating profit per turn, including current engine congestion quotes

| Setup | Middleman | Generic road carrier | Consolidating hub |
| --- | ---: | ---: | ---: |
| Motors only | £22.72 | £-3.86 | £-12.46 |
| Motors + steel | £27.62 | £6.67 | £-0.73 |
| Five-factory chain | £46.80 | £54.08 | £50.37 |
| Two five-factory chains | £93.59 | £5.26 | £15.79 |

The first three carrier rows use recorded steady-state economics. The fourth is a full-output model with congestion quoted by actual game code against a complete recurring transport pipeline. It is **not** a passing ten-factory production run: the conservative incoming-inventory reservation still throttles that run. The model retains twice the five-factory warehouse cost rather than claiming measured ten-factory occupancy. Middleman and hub behaviour remain arithmetic models, not implemented gameplay.

## Hub workload and investment

| Setup | LC/turn | Vehicles | Vehicle investment | Hydraulics / tyres / fuel | Hub advantage over carrier |
| --- | ---: | ---: | ---: | --- | ---: |
| Motors only | 8 | 1 | £309.45 | 1 / 1 / 1 | £-8.60 |
| Motors + steel | 10 | 1 | £309.45 | 1 / 1 / 1 | £-7.40 |
| Five-factory chain | 12 | 2 | £618.89 | 1 / 1 / 1 | £-3.71 |
| Two five-factory chains | 22 | 3 | £928.34 | 1 / 1 / 1 | £+10.53 |

At the doubled chain, hub inputs cost £17.96/turn and replace £28.50 of base carrier freight. Vehicle-only payback versus the carrier is about 88 turns. Hub construction, land, wages, maintenance, power, financing and capital recovery remain unpriced. Positive operating savings are not a complete investment return.

## Logistics cost breakdown

| Setup | Carrier base freight | Hub remaining base freight | Congestion retained in either model | Port fees/ad valorem | Warehouse | Hub running inputs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Motors only | £37.45 | £28.09 | £0.00 | £19.44 | £2.19 | £17.96 |
| Motors + steel | £42.26 | £31.70 | £0.00 | £19.82 | £3.56 | £17.96 |
| Five-factory chain | £51.45 | £37.21 | £0.00 | £17.45 | £5.80 | £17.96 |
| Two five-factory chains | £102.91 | £74.41 | £102.91 | £34.91 | £11.61 | £17.96 |

There is no player road maintenance in this setup. Provider fees include logistics/storage; they are not added to these direct-trade cost columns.

## Why the doubled result changes so much

Full-output road flows are 390 units on common external links and 580 on the furnace tile, versus a 300-unit threshold. The engine sets zero headroom when the previous turn is already over capacity. Its current route quote then applies the tier-1 multiplier to the whole new shipment’s freight. In this fixture every route touches an overloaded tile, producing a £102.91 surcharge—not a charge only on the 90 external units above 300. This is a pricing behaviour distinct from the earlier pipeline flow-counting fix; no gameplay pricing was changed here.

Conservatively retain that entire congestion expense for the hub as well. Owned-hub-specific congestion pricing is not implemented or calibrated. Consolidation does not reduce the road system’s goods-unit count. This interim assumption should not be mistaken for a finalized hub tariff.

For continuity with the earlier comparison **before additional congestion**, doubled profits are £93.59 middleman, £108.16 carrier and £118.70 hub. With the engine’s current surcharge, those become £93.59, £5.26 and £15.79. Consolidation creates a hub-versus-carrier crossover, but the current congestion tariff prevents it from beating the middleman at this scale.

## Payload sensitivity and verification

| Setup | LC at payload 50 | LC at payload 100 | LC at payload 200 |
| --- | ---: | ---: | ---: |
| Motors only | 14 | 8 | 4 |
| Motors + steel | 16 | 10 | 6 |
| Five-factory chain | 22 | 12 | 8 |
| Two five-factory chains | 42 | 22 | 12 |

The doubled chain remains cheaper to operate with the hub across these payloads: at payload 50 the running recipe becomes 1 hydraulic + 1 tyre + 2 fuel, giving £6.90/turn advantage; at 100 or 200 it is £10.53. Fleet investment changes with payload.

Checks cover conservation of weighted cargo, payload limits, invariance under splitting building orders, separation of different availability turns and opposite directions, and reconciliation of engine base freight with all source snapshots. The engine probe prices one batch at every pipeline age, using actual per-turn link accounting; it does not count the whole pipeline at every tile.

```sh
python3 tools/analyse_pepper_chain_matrix.py
python3 tools/analyse_pepper_consolidation.py
```

[Machine-readable report](../../reports/balance/pepper_four_by_three_consolidated_2026-09-19.json). [Default behaviour contract](../../tests/scenarios/logistics_hub_lc_weights.json).
