# Compact district: shared handoff trial — 19 September 2026

> Follow-up: [L1 rail and hub operating-consumption sensitivity](pepper-hub-consumption-sensitivity-2026-09-19.md). L1 with an edge handoff already yields a small hub advantage; L2 requires changing the per-turn consumption floor to benefit from lower positive recipe coefficients.

The shared collection/distribution point does not yet deliver the intended hub crossover. Actual external carrier requotes save less than the current minimum active hub recipe costs. No recipes, commodity prices, carrier tariffs, LC weights, payloads or rounding rules were changed to force a win.

## Fixture

Ten L1 buildings on four covered production tiles, with the hub at tile_5_5:

| Tile | Buildings |
| --- | --- |
| tile_5_5 | Two motors + hub |
| tile_5_4 | Two steel furnaces |
| tile_6_5 | Two copper-wire factories |
| tile_6_4 | Two iron and two copper furnaces |

Full recipes, no mines. All 140 iron ingots go to the steel tile, where 66 surplus are sold; all 50 copper ingots go to wiring. All 88 steel and 66 wire go to the motor tile, which sells 24 steel, 2 wire and 66 motors. Imports total 80 coal, 80 iron ore and 72 copper ore.

The trial evaluates all seven reachable handoff locations in the hub's coverage. Carrier imports/exports are combined by good at that point and freshly quoted to/from the port. Local deliveries and every internal movement use covered road edges operated by the hub; their LC and fleet needs are recalculated. They produce no generic-carrier invoice. Generic direct service instead quotes every factory route, including internal movements.

Road L3 and rail L2 were compared to reduce capacity effects. Every carrier route is verified to use the selected mode and installed level. Local hub roads are L3 in either case. Rail has three player-maintained L2 tiles (£16.20/turn); roads have no player maintenance. Other infrastructure is public and capital costs are excluded.

## Operating profit per turn

| External infrastructure | Middleman | Direct generic carrier | Shared-handoff hub |
| --- | ---: | ---: | ---: |
| L3 roads | £83.74 | £159.20 | £145.85* |
| L2 rail | £83.74 | **£174.47** | £165.09 |

*Road hub profit is an optimistic bound: it includes the engine's carrier charges, but the running-cost effect of congestion on owned hub vehicles is not implemented. The selected road gateway reaches 842 goods-unit touches against a 750 threshold. Congestion is not treated as a throughput cap. All road handoff alternatives have at least one overloaded tile; the selected rail alternative has none.

The central tile_5_5 is a best handoff under both infrastructure choices. All seven rail handoffs yield the same external carrier quote, so ties prefer lower fleet capital and then lower LC. The selected hub uses **15 LC**, **two vehicles (£618.89)** and **one hydraulic component, one tyre, one fuel (£17.96/turn)**.

## Why the rail hub still loses

| Transport item | Direct carrier | Shared-handoff hub |
| --- | ---: | ---: |
| Carrier invoices | £20.40 | £11.82 |
| Hub recipe | £0 | £17.96 |
| Total | **£20.40** | **£29.78** |

The hub removes £8.58 of carrier charges, but adds £17.96, so loses £9.38/turn before hub construction and overhead. Rail congestion is zero for this comparison. Factory costs (£431.26), port charges (£34.91), estimated warehouse charges (£11.61) and owned rail upkeep (£16.20) are identical between direct and hub cases.

The external L2 rail routes already fit into one priced transport leg. Moving the endpoint from each factory to the shared handoff still leaves one priced leg. Combining same-good orders does not reduce a linear per-unit tariff. The £8.58 saving is the removed internal carrier service; shortening the external physical journey does not create another price reduction here. This is why a fresh carrier quote differs from the earlier fractional-leg arithmetic overlay, which credited covered distances proportionally even if the residual carrier quote would remain one full leg.

No bulk discount, pickup charge or handling charge was invented. No warehousing or port fee was removed. This result rules out shared collection alone as a sufficient fix under the current rail tariff and minimum hub recipe. To make this fixture cross over while retaining those constraints, the hub must replace at least another £9.38 of real priced service, or its effective operating cost must fall. Adding a generic local-service tariff is a separate balancing decision requiring the smaller controls to be rerun.

## Verification and limits

Verified net delivery of every good at every tile before and after handoff splitting; full recipe material balance; aggregate purchases/receipts against two complete chains; reachable mode/level-correct routes; and recalculated local weighted loads. The engine provides actual route prices and per-turn congestion snapshots for each alternative.

This is a periodic full-output quote model, not a production regression benchmark. Local movement takes one road edge per turn, and external movement uses its actual quoted duration; there is no extra handoff dwell. Dispatch alignment and stock buffers are assumptions. End-to-end deliveries can therefore differ from direct rail, and warehouse carrying cost is held at the previous two-chain estimate rather than measured. Gateway inventory, land and handling overhead, empty vehicle repositioning, construction and capital recovery are not priced. These omissions favour the hub and cannot turn the negative result into a demonstrated win.

The earlier small-building controls are preserved; no new tariff was introduced and their gameplay was not changed. The tested fixture does not become a passing hub progression baseline.

```sh
python3 tools/analyse_pepper_district.py
```

[Scenario](../../tests/scenarios/pepper_district_handoff.json). [All seven handoffs, routes and quotes](../../reports/balance/pepper_district_handoff_2026-09-19.json).

## Later flow-accounting qualification

The subsequent [owned-rail factorial trial](pepper-hub-factorial-2026-09-19.md) keeps physical journeys continuous across same-mode operator handoffs. Splitting physical records at a same-mode handoff can count gateway flow twice. The earlier road-gateway overload figures above used split records and should not be treated as proven physical congestion until remeasured with continuous journeys; their candidate costs remain historical provisional results. No underlying gameplay accounting fix is claimed by this model correction.
