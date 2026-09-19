# Phase 4: road logistics hubs — implementation contract

Status: paused at the user’s request; pure foundation helpers only, no live hub gameplay. 19 September 2026. This document turns the selected [hub design](logistics-hub-design.md) into the road-only P4 scope. P0–P3 remain the playable baseline until the acceptance checks below pass.

## Retained decisions

- Hubs move player-owned goods. They never buy or sell goods on behalf of another factory, and never provide intermediary netting between buildings.
- A road hub covers its own tile and the six neighbours, subject to actual connected road access. Generic overland fallback does not establish hub access.
- Installed Heavy Vehicles are durable equipment: ten **loaded** LC per vehicle per turn, with empty return and unloading included (confirmed by the user). Payload is 100 weighted units per load. Road service consumes one recipe per 125 loaded adjacent-tile movements.
- Diesel recipe: two Hydraulic Components, four Tyres and six Diesel Fuel. Electric alternatives replace the fuel with one Lithium Ion or Sodium Ion Battery. Whole recipes are consumed before work; unused service credit persists. Idle hubs consume no operating recipe.
- Light/heavy/ultra-heavy solids have weights 1/2/5. Bulk ores and coal consolidate separately from general dry cargo. Liquids, hazardous liquids and gases retain the selected weights 2/4/3, but require dedicated equipment in a later extension; ordinary road trucks must not move them by inference.
- Pool compatible goods meeting on the same tile in the same turn and travelling along the same directed next segment. Retain original goods ownership, quantities, destination and market settlement. Do not require identical original departure, source or factory.
- A handoff neither advances the shipment an extra turn nor imposes an extra waiting turn. Congestion remains a charge, not a hard network cap. Fleet capacity is a distinct constraint.
- Existing in-flight shipments keep their operator assignments when policies change. Save fleet allocations, remaining service credit and partially progressed cargo. Loading cannot rebuy supplies or repeat a sale.
- Rail L1/L2 efficiency (125/300 LC per recipe) remains P5, with separate equipment/access requirements. A generic rail leg does not increase a road hub's efficiency.

## Integration boundaries

`TransportState.pending_transport_shipments` remains the sole cargo store. Extend shipment progress rather than adding a second hub inventory or settling copies of shipments. Hub equipment and operating-credit state should be saved alongside transport state.

Current transport advances a whole shipment by decrementing `turns_remaining`. Owned operation needs position-aware progress and a scheduling pass before arrivals. It must support partial dispatch of oversized consignments; a shipment larger than one turn's fleet capacity must make progress rather than wait forever. Preserve all proportional purchase liabilities and sale receipts when cargo is split.

Current freight is quoted and billed in several paths: stockpile moves, production output transfers, market imports, production sales, stockpile sales and construction reservations. A hub discount in only one of those paths would invalidate the comparison. Quote carrier-operated portions through the common transport facade, freeze the accepted assignment on dispatch, and book hub supplies/access costs exactly once. Port charges remain separate and unchanged.

At each actual handoff, quote the remaining carrier route. Do not calculate savings by prorating an old end-to-end invoice. Network traversal and congestion must follow the physical journey, independent of invoice boundaries.

Retain the outer turn sequence. Schedule movement of existing cargo and settle arrivals before construction/production. Newly dispatched cargo first advances next turn. Supplies arriving later in the same movement pass cannot retroactively fund an earlier dispatch. Existing same-tile/JIT production rules remain unchanged.

## Product decisions needed before fleet activation

The earlier economic models intentionally omitted hub construction, fixed overhead, unloading time and empty repositioning. These must be explicit prototype parameters, not hidden assumptions in a claim of profitability.

1. **Resolved:** user authorizes provisional, tunable costs. Initial parameters in `data/logistics_hub_config.json`: £50 construction fee plus 10 concrete, 7 building frames and 3 ICE construction equipment; two turns; 15 tile space; £3 fixed overhead per turn. Installed Heavy Vehicles are additional durable equipment. These are trial inputs, not an economic sign-off.
2. **Resolved:** retain ten loaded LC per vehicle; positioning, unloading and return are included. Do not debit them again or lower the selected capacity.
3. Replenishment policy for hub supplies: player-delivered stock versus an independently priced, funded automatic procurement service. A hub must not obtain free materials or silently inherit intermediary procurement for unsupported goods.
4. Default shortfall response: queue. Paid generic fallback requires an explicit nonzero per-turn spending cap and available funding; default cap £0.

## Acceptance gates

- Pure quotes do not mutate inventory, fleet capacity, service credit, market volume or cash.
- API splitting and different original departure turns cannot alter consolidation bills for compatible cargo meeting together.
- Opposite directions, bulk/general incompatibility and different next segments do not share a load.
- Empty, full, oversized and partial loads account for weight exactly once; capacity cannot be allocated twice.
- Missing supplies, insufficient cash, disconnected roads and full destination storage preserve cargo and liabilities.
- Quotes and actual charges agree; purchase liabilities, sale revenue, refunds, port charges and hub supplies reconcile to cash.
- Mid-journey save/load and changing input/output suppliers preserve assignments, amounts and settlements.
- Previewed bulk policy changes show which building sides change and leave private intermediary holdings subject to the existing safe-release check.
- Tile controls and the company dashboard expose installed vehicles, used/available capacity, remaining service credit, queued cargo, fallback spend and actual operator assignments.
- Real-turn Pepper Valley controls compare one factory, integrated small chains and a compact 9+ building district; include hub capital and working capital in payback rather than claiming success from running profit alone.
- Run focused transport/market/production/save/finance checks, preserved P0–P3 benchmarks, the full suite and a windowed advanced lesson.

## Foundation implementation

`logistics_hub_contract.gd` implements pure compatible-cargo pooling, weighted load calculation, installed capacity, whole-recipe service credit, atomic stock admission and partial dispatch/queue planning. It does not yet activate hubs or mutate live shipments. Seven focused tests cover convergence, splitting invariance, opposite directions, equipment/access rejection, persisted-credit arithmetic, missing inputs, oversized shipments and shared capacity/supply reservations.
