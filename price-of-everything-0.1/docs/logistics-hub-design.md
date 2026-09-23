# Logistics Hub: selected design

Status: documented direction selected after the original-inputs/L1–L2 comparison. This is not implemented hub gameplay. The original-input recipe is retained; differentiated-input experiments remain historical sensitivities. Detailed hub equipment, capital and queue design belong to later phases and do not block middleman phase 0.

## Progression

Middleman should generally win at 1–3 buildings. Generic carriers should generally win around 3–12 buildings, depending on integration, complete chains and colocation. A hub should begin paying off at 9+ buildings with meaningful traffic between 3–4 adjacent production tiles. These overlapping bands are balancing targets, not building-count fee gates. L2 handoff should earn more total operating profit than L1 when each chooses its best reachable handoff.

## Coverage and operator responsibility

A hub covers its own tile and the six adjacent tiles. Coverage still requires a connected, eligible physical route. It handles internal transfers and local collection/distribution; a generic carrier or another hub handles the journey outside its coverage. Choose a reachable shared handoff within coverage; it need not be the hub's centre. Quote the carrier's actual remaining journey rather than subtracting a fraction of its old invoice. Ordinary per-unit carrier prices do not automatically grant a bulk discount.

The middleman remains a separate service: it buys/sells at individual buildings, never transports player-owned goods, never supplies a same-tile transfer or JIT link. A hub capacity shortfall may fall back to a generic carrier under an explicit spending policy; it must not silently turn goods into middleman market trades.

## Consolidation and timing

Pool cargo available at the same tile and dispatch turn, with compatible equipment and a shared directed next segment. Original source, original departure turn, building identity and API order splitting do not prevent consolidation. Repack at subsequent covered meeting tiles; split when routes diverge. Do not merge opposite directions or delay departures merely to fill loads by default.

A same-turn handoff adds no mandatory waiting turn and grants no extra movement. Keep ownership, goods quantities and destinations intact. Keep the physical journey continuous across an operator boundary, including for congestion accounting; do not count a same-mode gateway twice because billing has been split. Network capacity currently causes charges, not a hard shipment cap. Owned fleet availability is a separate constraint.

## LC and installed capacity

Apply cargo weights once to payload: light solids 1, heavy solids 2, ultra-heavy solids 5, liquids 2, hazardous liquids 4, gases 3. Existing eligibility rules still apply; equal weights do not establish equipment compatibility. The current model separates bulk coal/ores from general dry cargo. Liquid, hazardous and gas equipment/compatibility require explicit rules before their hub phase.

Working payload: 100 weighted units per load. One loaded adjacent-tile movement costs one LC. This payload remains a calibration assumption. Installed capacity is 10 LC per vehicle per turn; installed vehicles are upfront equipment, not consumed every turn. Trips, unloading and empty repositioning must ultimately fit real capacity accounting; the current economic models omit empty repositioning and do not establish a complete vehicle-occupancy implementation.

## Original operating inputs and level-specific efficiency

| Variant | Operating inputs per recipe |
| --- | --- |
| Diesel | 2 hydraulic components + 4 tyres + 6 fuel |
| Electric | 2 hydraulic components + 4 tyres + 1 lithium **or** sodium battery, replacing fuel |

| Hub-operated movement | LC serviced per recipe |
| --- | ---: |
| Road | 125 |
| L1 rail | 125 |
| L2 rail | 300 |

The selected balancing direction is original inputs plus this level-specific efficiency. An external rail carrier does not give the hub's own road deliveries rail efficiency. Mixed-mode usage scales the recipe by `road_LC / 125 + rail_L1_LC / 125 + rail_L2_LC / 300`. Road upgrades alone do not grant the L2 rail rate. Further rail levels/research need later definitions; do not invent them from this table.

## Consumption accounting required by this direction

Use accumulated usage/service capacity across turns, with whole goods purchased or drawn when needed. Unused service credit persists; idle hubs consume nothing. This replaces the earlier minimum-one-of-every-good on every active turn, which makes the efficiency changes ineffective at the tested scale. Save consumed supplies and remaining service credit exactly once so reloads cannot create free capacity.

Exact replenishment timing, required starting reserve, failure behaviour and service-credit schema are deferred to the hub implementation contract. Purchased material cannot supply free work before funding, and missing supplies must not silently permit an unfunded dispatch. This is a design requirement, not a claim that service-credit accounting exists in the game today.

## Selected evidence and remaining limits

The ten-building/four-tile owned-rail quote model with accumulated consumption gives £176.91/turn at the best L1 handoff and £179.85 at L2: **L2 gains £2.94/turn**. This retains three owned rail tiles (£9 versus £16.20 upkeep) and original operating inputs. Differentiated inputs were not selected; they narrow the upgrade delta. The per-turn-minimum control instead leaves L2 £7.20 behind.

These are full-output economic models, not production-qualified hub gameplay. The 100-weighted-unit payload, abstract fleet capital and warehouse costs are modelling assumptions. Hub construction, fixed overhead, rail-specific equipment, empty repositioning and upgrade payback remain unpriced. Validate the small-building controls and the compact-district crossover again when those mechanics exist.

[Factorial evidence](reviews/pepper-hub-factorial-2026-09-19.md). [Machine-readable selected design](../tests/scenarios/logistics_hub_design.json). [Middleman phase-0 readiness](middleman-phase-0-readiness.md).
