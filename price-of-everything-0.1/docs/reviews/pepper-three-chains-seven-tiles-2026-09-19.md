# Three chains across seven tiles, level-2 rail — 19 September 2026

The larger site earns more, but the generic rail carrier still beats the owned logistics hub. Consolidation is enabled by default at shared meeting tiles and availability turns, with compatible cargo and shared onward edges.

## Layout

The central tile is the existing hub location, tile_5_5 (Seasalt Flats), now containing the hub and all three motor factories. Its six neighbours host the remaining twelve factories. Each chain pairs a smelting tile with a steel/wiring tile:

| Tile | Buildings |
| --- | --- |
| tile_5_5, centre | Hub + 3 motor factories |
| tile_5_4 | Steel furnace + copper wiring |
| tile_6_4 | Iron furnace + copper furnace |
| tile_6_5 | Steel furnace + copper wiring |
| tile_5_6 | Iron furnace + copper furnace |
| tile_4_4 | Steel furnace + copper wiring |
| tile_4_5 | Iron furnace + copper furnace |

All seven sites are within the hub's radius-one coverage. Rail is level 2 between the sites and all the way to the same port. The engine-selected routes were checked to use rail and every traversed tile was checked at level 2; existing connectors selected by the router were upgraded too. Three owned rail tiles remain tile_5_4, tile_5_5 and tile_5_6; the remaining corridor is public.

No mines. Whole ingot output moves to its paired steel/wiring tile; whole steel/wiring output moves to the centre. Surplus is sold from the receiving stockpile. This retains the previous full-batch transfer policy instead of optimizing away surplus movements. Imported quantities are 120 iron ore, 108 copper ore and 120 coal per turn. External sales are 99 motors, 99 iron ingots, 36 steel and 3 wire.

## Profit per turn

| Model | Operating profit |
| --- | ---: |
| Independent-building middleman | £121.24 |
| Generic L2 rail carrier | **£269.81** |
| Owned hub + outside L2 rail carrier | £264.65 |

Middleman fees are £212.25/turn. Location coefficients were recalculated for each tile, so provider profit is not simply three times the old chain result. The central motor factories now use the rural-adjacent coefficient of 1.75; local urban sites retain the Pepper Valley coefficient of 1.5. Independent building trades do not share inputs.

## Direct-trade cost breakdown

| Per-turn item | Generic carrier | Owned hub |
| --- | ---: | ---: |
| Goods receipts | £1,319.73 | £1,319.73 |
| Materials purchased | £286.46 | £286.46 |
| Factory labour, maintenance and power | £646.90 | £646.90 |
| Carrier freight | £30.60 | £14.16 |
| Hub running inputs | £0 | £21.60 |
| Congestion | £0 | £0 |
| Three L2 rail tiles' upkeep | £16.20 | £16.20 |
| Port fees/ad valorem | £52.36 | £52.36 |
| Warehousing estimate | £17.41 | £17.41 |

Peak measured recurring rail flow is 647 units against the L2 threshold of 1,200. No repeated-tile routes were returned in this fixture. Rail upkeep is engine-calculated at level 2; it is not the previous £9 L1 cost. Rail labour is zero.

## Hub workload

At the working payload of 100 weighted units per load, the hub handles **32 LC/turn**, needing **four vehicles (£1,237.79)**. Its rounded recipe is **one hydraulic component, one tyre and two fuel per turn**, costing £21.60 delivered. It replaces £16.44 of base rail freight, leaving it £5.16/turn behind the carrier before hub construction or overhead.

Even the minimum active recipe, one hydraulic + one tyre + one fuel at £17.96, exceeds the £16.44 local rail bill replaced. Under these routes and prices, more efficient packing alone cannot produce an operating crossover. Payload sensitivity is 58 LC at 50 weighted units, 32 at 100, and 19 at 200. At payload 200 the recipe reaches its minimum, but the hub still trails by £1.52/turn.

## Evidence and limits

This is a full-output periodic economic model. Actual game code supplies selected routes, per-turn congestion accounting, freight prices, site-specific factory costs and rail upkeep. Goods are conserved at every production tile; aggregate receipts and purchases reconcile with three complete chains. Cargo consolidation uses the existing shared-tile, same-turn algorithm and applies cargo weights once.

It is not a validated fifteen-factory production run. Arrivals are assumed phase-aligned for recurring dispatch. Warehousing is held at three times the earlier five-factory baseline (£17.41), not measured for these seven tiles. Actual storage changes affect the carrier and hub equally under the retained same-inventory assumption; they could also affect production qualification. No claim is made that seven physical warehouses are full or required to be upgraded. Middleman/hub services remain modelled rather than implemented gameplay.

Infrastructure construction/upgrade capital, hub construction/land, hub overhead and fleet amortization are excluded. Government corridor completion is assumed. The full-output comparison does not resolve the previous input-order reservation constraint.

Reproduce:

```sh
python3 tools/analyse_pepper_seven_tiles.py
```

[Scenario contract](../../tests/scenarios/pepper_three_chains_seven_tiles.json). [Engine quotes and full report](../../reports/balance/pepper_three_chains_seven_tiles_2026-09-19.json).
