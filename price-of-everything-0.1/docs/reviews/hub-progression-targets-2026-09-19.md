# Target progression and hub traffic replacement — 19 September 2026

> Shared-handoff candidate tested: [ten-building/four-tile results](pepper-district-handoff-2026-09-19.md). L2 rail direct carrier earns £174.47/turn versus £165.09 for the hub; the unchanged tariff/recipe does not yet meet the target crossover.

## Accepted progression targets

- 1–3 buildings: middleman should generally win.
- 3–12 buildings: generic carrier should generally win, depending on integration, chain completeness and colocation.
- 9+ buildings across 3–4 adjacent production tiles, with meaningful inter-tile traffic: owned logistics hubs should begin to pay off.

These overlapping bands are balancing acceptance targets, not unlock gates, explicit building-count discounts or guaranteed rankings for every cargo/layout. Real local workload and integration should produce the crossover. The previous fifteen-building/seven-tile experiment is a scale sensitivity, not the exact compact-district acceptance fixture.

## What is already replaced

Current arithmetic already removes the full base freight charge for movements wholly inside coverage. It also removes the covered fraction of each external shipment's quoted transport legs. Therefore merely counting internal shipments as owned again cannot create additional legitimate savings.

| Existing case | Fully replaced internal freight | Replaced covered import/export freight | Total replaced | Hub running cost | Additional saving to break even |
| --- | ---: | ---: | ---: | ---: | ---: |
| 10 buildings, 2 tiles, L1 rail | £4.19 | £6.99 | £11.18 | £17.96 | £6.78 |
| 15 buildings, 7 tiles, L2 rail | £12.88 | £3.56 | £16.44 | £21.60 | £5.16 |

The ten-building rail case retains its earlier fixed fleet/running-cost comparison. Its whole-network congestion charge remains a conservative modelling assumption, not a finalized owned-hub tariff. These numbers are diagnostic, not proposed new fees.

## Next candidate: shared collection/distribution point

Test the owned hub as a district pickup/delivery service, with generic rail or road supplying only the external route from a shared network handoff to the port:

1. Covered internal deliveries are entirely owned movements, consuming hub LC and operating goods.
2. Covered factories' exports are collected at a shared handoff; incoming materials arrive there and are distributed locally. Select a reachable handoff in coverage; don't assume the centre is always optimal.
3. Consolidate compatible cargo at each actual same-turn meeting tile, preserving goods identity, destination, payload and travel budget.
4. Quote the generic carrier's route from the handoff to the port (and reverse for imports), rather than prorating the old factory-to-port quote. Recompute local LC and vehicle requirements after rerouting. A shorter physical route does not guarantee a lower game tariff if both routes fit one transport leg.
5. Carrier charges apply to carrier work. Do not retain a generic transport invoice for a fully owned local movement. Network congestion still exists; separate the carrier's congestion surcharge from any real effect on hub operating costs. Removing a duplicated fee is different from erasing congestion.
6. Port charges, actual stock carrying costs and player infrastructure upkeep remain unless the new routing demonstrably avoids them. No invented warehouse savings or automatic bulk discounts.

This is a candidate to model, not implemented gameplay or a proven crossover. Some old routes already traverse the same covered approach, so simply introducing a handoff may produce little additional saving. If efficient rail still leaves the hub below break-even, consider an explicit generic pickup/delivery/handling service tariff that the hub truly replaces, or tune hub-specific operating economics. Adding such a tariff would change generic economics and requires rerunning every progression control; do not silently treat it as an existing cost or change all commodity prices.

## Acceptance fixtures

Keep the existing one-, two- and five-building controls. Add ten buildings over four covered tiles: two motors centrally, two steel furnaces on a second tile, two wire factories on a third, and two iron plus two copper furnaces on a fourth. Full recipes, no mines, tile-stockpile surplus policy retained. Compare with ten buildings on two tiles to separate colocation from actual traffic. Requote road and rail choices at adequate capacity; hold goods/recipes constant. Count all owned handling and repositioning assumptions explicitly rather than manufacturing savings by relabelling shipments.

Require positive hub operating savings at the target compact scale, then evaluate vehicle investment and defined hub overhead. A trivial positive operating margin is not sufficient evidence of a viable investment. Building-count targets alone do not establish land, warehouse, route or production feasibility; validate the new fixture before promoting it to a regression baseline.
