# Fourth chain: two copies of all five factories — 19 September 2026

> Current default: hubs consolidate compatible cargo at the same tile and availability turn, regardless of original origin/departure. See the [updated four-by-three comparison](pepper-consolidated-four-by-three-2026-09-19.md) for weighted payload, engine congestion quotes and model limitations. Earlier batching comparisons below are historical.

Doubling the five-factory chain does **not quite pay for the hub if shipment batches stay separate**. It can pay if the hub consolidates compatible cargo, but the existing two-tile game setup also encounters a conservative input-order storage budget and road congestion charges. These findings must be kept separate.

## Matched full-output sensitivity

Ten L1 production buildings on the same two production tiles, one hub covering both, full existing recipe quantities, surplus sold from the consuming tile. Middleman 0.5%, heavy .05, ultra .50; hub weights and rounding unchanged, 125 LC per recipe. The calculation below doubles the prior full-output goods, factory, port, storage and base carrier costs, before additional congestion charges and without resolving the input-order planning constraint described below.

| Operating profit per turn | Middleman | Generic carrier | Hub, separate batches | Hub, pooled 100-unit batches |
| --- | ---: | ---: | ---: | ---: |
| Two five-factory sets | £93.59 | £108.16 | £104.57 | £115.06 |

The first two columns and hub overlays are **linear full-output models**, not new steady simulation results. The middleman remains independent building trades. The model retains all regular-carrier charges outside the hub and all port/storage obligations.

| Hub requirement | Separate batches | Pool matching same-route goods, cap 100 units |
| --- | ---: | ---: |
| Weighted LC per turn | 72 | 38 |
| Vehicles | 8 | 4 |
| Vehicle investment | £2,475.57 | £1,237.79 |
| Hydraulic components / tyres / fuel per turn | 1 / 2 / 3 | 1 / 1 / 2 |
| Delivered running inputs | £32.09 | £21.60 |
| Covered freight avoided | £28.50 | £28.50 |
| **Advantage over carrier per turn** | **−£3.59** | **+£6.90** |

The separate-batch case doubles the previous 36-LC per-factory workload. In the pooled alternative, matching goods on the same route share batches up to 100 units. Most doubled quantities still fit one batch; the 140 iron ingots moved between the two tiles need two instead of one. Consequently workload is 38 rather than 72 LC. Pooling keeps goods with different destinations or cargo types separate, and is not permission to merge incompatible or unlimited cargo.

The distinction was not settled in the prior canonical-shipment/payload rule. Neither should silently become the only answer. Treat pooling as a potential genuine benefit of the top-tier logistics hub, with an explicit payload cap and deterministic grouping; arbitrary API splitting must not change capacity cost. The 100-unit cap remains illustrative, not an approved gameplay rule.

At +£6.90/turn, vehicle-only payback against the generic carrier is about **179 turns**, before constructing the hub, land, overhead or finance. Existing vehicles from the one-set case could lower incremental expansion investment, but do not eliminate the cost of owning that fleet overall. This is a modest operating crossover, not a strong capital return yet.

## Actual unchanged two-tile run

The new `--double` game run did not reach the required ten consecutive full-output turns. During turns 40–49:

- Input orders hit the planner’s storage reservation budget on all ten turns; this does not establish that physical inventory reached the warehouse cap.
- Motor production averaged **59.4**, against a full-output target of **66**.
- Actual generic-carrier operating contribution averaged **−£1.44/turn** in this constrained diagnostic window.
- Shared road traffic exceeded the existing 300-unit congestion threshold. Shipments still move; excess flow increases charges. At intended full output, external port traffic alone is 390 units per turn, before internal transfers at the factory-side tiles.

Do not compare that constrained £−1.44 with the table’s full-output provider or hub figures as though throughput were identical. Road congestion is a financial penalty, not a throughput cap. The input-order planner separately subtracts all incoming freight from current warehouse headroom, regardless of arrival turn or intervening consumption. At full output, the furnace tile needs 80 iron ore + 72 copper ore + 40 coal = 192 units per turn. Its four-turn import lead produces a five-turn pipeline target of 960, above the 800-unit warehouse cap, although those goods need not be on the shelf simultaneously. At the end of turn 40, physical stock was only 212 on that tile and 258 on the other production tile. The 1,340-unit structural warning adds output buffers to the pipeline target; it is not measured simultaneous occupancy.

This is evidence of a conservative planning constraint, not proof that the chain requires a bigger warehouse. Arrival, consumption and output timing must be checked before prescribing storage upgrades or changing balance. Installing a hub does not itself alter this planner in the current arithmetic overlay.

No full-output ten-factory snapshot was written. The [diagnostic window](../../reports/balance/pepper_ten_factory_capacity_diagnostic_2026-09-19.json) retains the failed qualification and actual turn summaries. The failure records an input-planning constraint and congestion expense, not a passing benchmark or proof of physical warehouse overflow.

## Reproduction

```sh
# Expected to fail full-output qualification with the unchanged two-tile layout:
python3 tools/run_pepper_five_factory_benchmark.py --double
# Rebuild both full-output arithmetic alternatives:
python3 tools/analyse_pepper_double_chain.py
```

[Fourth-row report](../../reports/balance/pepper_double_chain_2026-09-19.json). [Earlier three rows](pepper-three-by-three-2026-09-19.md). The original five-factory baseline remains separate. Live production, storage, tariffs and hub gameplay were not changed.

## Consolidation design clarification

Recommended dispatch grouping is same departure turn, origin, shared directed route segment and compatible cargo equipment. Begin with identical goods; mixed goods can share loads only when equipment compatibility and payload limits explicitly allow it. Cargo class alone is insufficient: a matching LC weight does not establish that liquids, hazardous liquids and gases can share a vehicle. Do not delay departures to fill loads by default, and do not pool opposite directions. Loads can split at route divergences or handoffs.

Canonical grouping must be independent of how many buildings or API calls created orders. Under the illustrative unweighted 100-unit cap, two 33-motor orders can share one load; two 70-iron orders require two. That example is a sensitivity assumption, not an implemented payload rule. A final capacity model should define standardized payload and load-movements, applying cargo weight once (either through weighted payload or a load-class LC multiplier). Consolidation does not reduce the goods-unit road congestion count in current gameplay. The reported £6.90 hub advantage is conditional on the illustrative batching rule.
