# Pepper Valley: three chains × three logistics models — 19 September 2026

> Current default: hubs consolidate compatible cargo at the same tile and availability turn, regardless of original origin/departure. See the [updated four-by-three comparison](pepper-consolidated-four-by-three-2026-09-19.md) for weighted payload, engine congestion quotes and model limitations. Earlier batching comparisons below are historical.

This comparison uses full existing recipe quantities, no mines, and tile-stockpile surplus sales. Generic supplier means the existing **public-road carrier plus port**, not the three-section rail case. The owned hub replaces only local covered road movements; the carrier still handles the rest of the journey.

## Results

Operating contribution per turn, averaged over turns 40–49. Factory labour, maintenance and power are included. Tax, financing and construction investment are excluded. Generic-carrier results are real simulation; middleman and hub results are arithmetic applied to those recorded costs. Hub building overhead is not yet defined and is excluded, so its results are optimistic on that point.

| Chain | Middleman | Generic road carrier | Local owned hub + carrier hand-offs |
| --- | ---: | ---: | ---: |
| Motors only | £22.72 | £-3.86 | £-12.46 |
| Motors + steel | £27.62 | £6.67 | £-0.73 |
| Motors + steel + copper wiring + copper ingots + iron ingots | £46.80 | £54.08 | £46.73 |

The provider is preferable at the first two sizes. The five-building chain makes the generic carrier more profitable than independent middleman trades by **£7.29/turn**. The hub still trails the carrier by **£7.35/turn** at this calibration. That is not a failure of the intended small-hub threshold; it shows this particular layout/recipe calibration has not yet delivered the top-tier advantage. Simply assuming more identical traffic fixes the balance would be unsafe: the unrounded recurring recipe cost per unit of LC must also beat the carrier’s avoided cost at high utilisation.

## Factory layouts and quantities

All recipes run at L1, without output research or JIT:

| Factory | Recipe | Full inputs | Full output | Site |
| --- | --- | --- | --- | --- |
| Motors | r_009 | 32 steel + 32 copper wiring + 30 power | 33 motors | Pepper Valley, tile_5_4 |
| Steel | r_003 | 37 iron ingots + 20 coal + 140 power | 44 steel | tile_5_4 |
| Copper wiring | r_008 | 25 copper ingots + 80 power | 33 wiring | tile_5_4 |
| Copper ingots | r_007 | 36 copper ore + 140 power | 25 copper ingots | Adjacent tile_6_4 |
| Iron ingots | r_005 | 40 iron ore + 20 coal + 140 power | 70 iron ingots | tile_6_4 |

The hub is at tile_5_5, whose own/adjacent area covers both production sites. Completed factory land/grid access is assumed. There are no mines: ore and coal remain external purchases.

In the generic-carrier and hub cases, intermediate producers route their output to the consuming tile’s stockpile. The two ingot furnaces send their whole batches from tile_6_4 to tile_5_4, where consumers reserve inputs and the tile sells surplus. This deliberately means excess iron travels to the consumer tile before being sold; moving only the required iron and selling surplus at the source is a separate optimisation, not hidden in the comparison.

| Chain | External goods bought per turn | Goods sold externally per turn |
| --- | --- | --- |
| Motors | 32 steel, 32 wiring | 33 motors |
| Motors + steel | 37 iron ingots, 20 coal, 32 wiring | 33 motors, 12 steel |
| Five factories | 40 iron ore, 36 copper ore, 40 coal | 33 motors, 33 iron ingots, 12 steel, 1 wiring |

The middleman case follows the agreed independent-building rule: each factory buys all its own inputs and sells all its output. Consequently its gross trades are larger, with no free internal netting or transfers. Each column contains exactly the same factories and full output quantities, but not the same external trade manifest.

## Costs and hub workload

| Per-turn component | Motors | Motors + steel | Five factories |
| --- | ---: | ---: | ---: |
| Direct goods receipts | £364.49 | £392.90 | £439.91 |
| Direct goods purchases | £238.69 | £220.92 | £95.49 |
| Factory operating costs | £70.57 | £99.67 | £215.63 |
| Generic inland freight | £37.45 | £42.26 | £51.45 |
| Port charges, retained with hub | £19.44 | £19.82 | £17.45 |
| Storage, retained with hub | £2.19 | £3.56 | £5.80 |
| Middleman inclusive fees | £32.51 | £40.90 | £64.37 |
| Freight replaced by hub | £9.36 | £10.57 | £14.25 |
| Carrier freight remaining with hub | £28.09 | £31.70 | £37.21 |
| Hub running inputs, delivered | £17.96 | £17.96 | £21.60 |

Middleman tariff: 0.5% of market base price plus .05 solid-heavy or .50 ultra-heavy per unit multiplied by location. City production uses 1.5, the two rural adjacent furnaces 1.75. This includes provider storage; independent factory costs remain separate. Other game tariffs are unchanged.

| Owned hub | Motors | Motors + steel | Five factories |
| --- | ---: | ---: | ---: |
| Weighted LC per turn | 18 | 26 | 36 |
| Installed vehicles (10 LC each) | 2 | 3 | 4 |
| Vehicle investment including supply | £618.89 | £928.34 | £1,237.79 |
| Hydraulics consumed per turn | 1 | 1 | 1 |
| Tyres consumed per turn | 1 | 1 | 1 |
| Fuel consumed per turn | 1 | 1 | 2 |

Hub running calibration remains 2 hydraulics + 4 tyres + 6 fuel per 125 LC, scaled to actual weighted movements and rounded half-up per good/hub/turn with minimum one when active. Idle consumption is zero. Installed vehicles are not consumed. LC weights are the user-selected light 1 / heavy 2 / ultra-heavy 5 / liquid 2 / hazardous liquid 4 / gas 3. All counted batches are under 100 units; payload and loading rules remain a future capacity gate. Hub inputs are procured via the middleman at the adjacent location coefficient, including provisional safe-liquid .03 freight weight for fuel.

The five-factory hub handles internal ingot transfers as well as covered parts of imports/exports. Its 36 LC comprises ten heavy-weight units for inbound road movements, twenty-two for covered outbound movements including motors, and four for the two internal ingot batches. No hub LC is invented for same-tile production consumption. The carrier covers all remaining route edges; port ownership, storage and shipment timing do not change in this arithmetic overlay.

## Simulation setup and validation

The new five-factory run uses normal game turn resolution and real roads, shipments, stockpiles, surplus orders, port billing and expenses. Consumer inputs supplied by the chain are set to tile-only. Leaving automatic import fallback on caused repeated extra ingot purchases and resale traffic in the initial diagnostic run; that is not the intended chain and is excluded from this benchmark. No production-system fix was made.

All five recipes reach full output with exact intended purchases and paid sales, stable stock and transit quantities across turns 40–49. No loans or congestion occur. Input purchases, sale receipts and factory costs are reconciled through the actual summary/cash pipeline. A fresh quote probe supplies game-calculated recipe labour, maintenance and power; the matrix verifies their totals against the real simulations and reconstructs every inland freight charge before applying hub savings.

The retained five-factory snapshot is [v1](../../tests/snapshots/pepper_valley_five_factories_v1.json). The [matrix report](../../reports/balance/pepper_three_by_three_2026-09-19.json) includes provider results by building, cost components and per-edge operator assignments. Earlier motor and two-building snapshots are unchanged. This is a controlled steady-state comparison, not a forecast of market prices, startup survival, land requirements or payback on all five factories.

```sh
python3 tools/run_pepper_five_factory_benchmark.py --check-baseline
python3 tools/analyse_pepper_chain_matrix.py
```

The quote-probe inputs are retained in `reports/balance/pepper_chain_quote_inputs_2026-09-19.json`; `tools/pepper_chain_quote_probe.tscn` can refresh them through the game. No live hub/provider gameplay, recipes or tariffs were changed by this review.

## Fourth scenario: two sets

The [ten-factory extension](pepper-double-chain-2026-09-19.md) adds a fourth scenario. At matched full output, arithmetic gives £93.59 middleman, £108.16 carrier and £104.57 hub with separate batches, or £115.06 with illustrative 100-unit shipment consolidation. These are not new steady-state results: the actual unchanged two-tile run encounters an input-order budget that reserves space for all incoming freight, plus congestion charges (not a road throughput cap or demonstrated physical warehouse overflow). See the extension for the failed qualification, batching assumptions and equipment costs.
