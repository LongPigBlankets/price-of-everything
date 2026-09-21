# Transport middleman layer

Current direction: independent-building middleman trades at the dynamic 0.5% tariff. [Phase-0 readiness and remaining contracts](middleman-phase-0-readiness.md). [Selected original-input Logistics Hub design](logistics-hub-design.md). Earlier reviews are historical evidence, not competing build targets.

Status: [Phase 1 is implemented](middleman-phase-1-implementation.md): real funded middleman operation for the Pepper Valley motor prototype. Broader service/UI rollout and hub gameplay remain later phases.
Date: 13 September 2026. Baseline: demo 0.4.2, before the transport redesign.
Clarified: 19 September 2026 — the middleman absorbs logistics into one visible fee; see the [phasing and turn-order assessment](transport-middleman-phasing-plan.md).

## Design intention

Make running a business understandable before asking the player to run its logistics network. A new company should be able to buy inputs, produce and sell through a middleman during the same turn, including when it starts inland. The middleman represents access to the national/local market and handles the inventory and transport behind that service.

The player-facing contract is **one Middleman fee for outsourced logistics**. It covers the service's transport, distance costs, congestion, port handling, warehousing within each building’s buy/sell service. These are the provider's responsibilities, not separate charges or systems the player must manage while fully outsourced. Goods purchase prices and sale receipts remain visible, as do the factory's own power, labour and other non-logistics costs. The fee may vary with the quoted service and volume; one fee does not mean a flat subscription or one payment event.

As the player takes individual logistics functions in-house, they assume the relevant operating costs and constraints: warehouse capacity and upkeep, transport distance and fleet costs, congestion, and direct port charges. Reveal these by the functions actually operated, not by company size or merely unlocking research. A mixed company sees one aggregate Middleman fee for building-level market trades plus generic-carrier invoices and the costs of its owned operations. Never charge both the bundled fee and its constituent logistics costs for the same work.

Extend the central choice — **buy it or make it yourself** — to storage, handling, transport and market access. Growth creates opportunities to take profitable functions in-house. Owning logistics should improve control and potentially margins while introducing capital investment, capacity management and working-capital requirements.

This is optional vertical integration, not a compulsory ladder. A company may own power and production but outsource all transport, operate a warehouse with generic-carrier haulage, or run selected routes itself while retaining independent-building middleman trades elsewhere. Direct global trade through ports should have a substantial entry cost and an attractive cost structure at sufficient volume. It must not remain strictly worse than outsourcing after that investment.

The intended opening shifts towards inland businesses. Geography still matters through service tariffs, deposits, land, power, network access and eventual routes. Exact starting locations and tariff values require trials; this spec does not rebalance recipes or relocate starts automatically.

## Scope and decision status

Agreed direction:

- Same-turn outsourced market purchases and sales as the simple default.
- A visible choice to build player-owned storage from the tile Stockpile tab.
- Explicit routing to that storage, independent of who transports the goods.
- Company, tile and building defaults, with route-specific control where needed.
- Visible progression into owned local handling, road/rail transport and direct trade.
- Money-panel reconciliation, understandable cash requirements, and visual ownership cues in Empire view.
- A shorter introductory tutorial and optional advanced logistics teaching.

Recommended first implementation, subject to prototype results:

- Fund purchased inputs before production; collect sales proceeds in the same resolution. No implicit unlimited intermediary credit.
- Physical Logistics Hub for road/rail fleet service; research improves capabilities rather than being the sole entry gate.
- Warehouse-provided local handling; separate fleet and network capacity.
- Pipelines operate as compatible direct infrastructure initially; defer Pumping Stations until they support a meaningful decision.
- Use the existing market price/impact model behind intermediary quotes initially. Do not introduce a separate national-market simulation at the same time.

Open decisions are listed at the end. Recommendations here are design proposals, not claims that the current game supports them.

## Economic and payment model

### Outsourced market service

The intermediary owns its upstream stock and transit. The player does not manage or finance a hidden multi-turn market pipeline. Inputs transfer to the player when supplied for production; output transfers to the intermediary when sold. Completed intermediary purchases and sales have transaction records, not player-owned shipments awaiting a port.

For a normal operating cycle:

1. Determine feasible production, the building’s private input holdings, power and service eligibility; physical logistics constraints apply only to separately selected direct operations.
2. Plan the building’s purchased shortfall for one cycle after reusing its own private holdings. Fully outsourced buildings cannot draw another building’s stock; direct-mode reservations remain separate.
3. Quote and fund those purchases and applicable intermediary charges.
4. Supply the purchased goods before the production pass that consumes them.
5. Produce within the existing per-turn production limits.
6. Sell output assigned to the intermediary and receive proceeds, less the explicit service fee, during the same resolution.
7. Reconcile operating and financing movements with the money panel and top bar.

Simply setting shipment ETA to zero is insufficient: current replenishment happens after production. The implementation must change input planning and settlement together, without adding an extra production cycle or allowing repeated buy/produce/sell loops.

Confirmed funding rule: current cash and explicitly drawn permitted credit fund complete feasible batches before sales. Never use anticipated sales. Reserve due obligations and batch running costs first; show the initial funding requirement before starting a building.

An unaffordable plan must reduce or reject production according to a documented deterministic allocation policy before charging. It must not partially charge an order and then silently discard the corresponding goods. Purchased goods left unused after a later production failure remain an explicit player asset; define their temporary holding/return policy before implementing storage-free purchasing.

### Tariffs

Current prototype tariff, for both building purchases and sales:

`fee = sum(quantity × (0.005 × quoted market-reference price + class tariff × location coefficient))`

The current class tariffs are £0.025 for light solids, £0.08 for solid-heavy goods, £0.60 for ultra-heavy goods, £0.08 for safe liquids, £0.15 for hazardous liquids and £0.20 for gases. Storage is included; there is no additional fixed £8 warehouse fee, £16 transaction fee or £40 building fee. Market goods prices and factory operating costs remain separate. Location coefficients are 1.05 for eligible large port cities, 1.25 for medium cities with 4+ urban tiles, 1.5 for small cities with 1–3 urban tiles, 1.75 for rural/hill tiles adjacent to a city, 2 for other rural/hill tiles and 2.5 for mountains regardless of adjacency.

The first fixture is one L1 motor factory on Pepper Valley tile_5_4 (explicit coefficient 1.5), purchasing 32 steel and 32 wire and selling 33 motors. Grid power remains separately supplied/billed. The fee reference is the snapshotted current `MarketState.get_price()` including impact/carbon, before buy markup. Goods use ordinary market buy/sale prices. Preserve float ledger precision and round only for display; historical controlled benchmarks use catalogue base prices.

Account by building, good, direction, turn and stable operation ID. Splitting calls cannot change fees or duplicate settlement. Purchase and sale fees appear as one aggregate Middleman fee with optional building/transaction attribution. Do not pool or net independent buildings' goods: a furnace sells all 44 steel, while a neighbouring motor factory independently buys 32 steel. No middleman same-tile transfer or JIT exists.

Input purchases and their fee must be funded before production. Settle actual sales and their fee after the bounded production pass, with exactly-once market impact. Provider service does not create player-managed shipments or consume player port/warehouse capacity; do not run legacy logistics billing and relabel it. Private unfinished-cycle holdings require an explicit failure/reuse contract, not a general hidden warehouse.

**Port relief replacement:** `ruleset.logistics_model = middleman_v1` uses the normal 3% base port rate from turn one for physical direct trades. Existing fee growth, ownership shares and research discounts still apply. Old saves/tutorials retain their schedules until explicitly migrated. The flag currently changes port pricing only, not provider gameplay.

Progression targets are middleman at 1–3 buildings, generic carriers around 3–12, and owned hubs beginning to pay off around 9+ buildings with traffic across 3–4 adjacent sites. These are overlapping economic targets, not building-count fee gates. Preserve the established recipes/prices while testing provider costs and actual startup working capital.

[Current tariff contract](../tests/scenarios/middleman_dynamic_fee_candidate.json). [Phase-0 checklist](middleman-phase-0-readiness.md). The £20/£40/£76 and 0.4% profiles in earlier reviews are historical controls. Preserve their snapshots without presenting them as the new implementation tariff.

### Construction and exceptional bills

Retain the 0.4.2 construction confirmation/prepayment contract initially. Same-turn cancellation releases refundable construction costs; purchased land remains owned. Do not inadvertently make construction complete instantly because operating inputs use a middleman.

Whether construction materials can use an intermediary service is a separate extension. Its quote must state delivery timing, materials, fees and cancellation treatment.

The inclusive-fee contract does not imply instant construction. If construction logistics use the middleman, show their logistics charge within the same fee category while retaining construction prepayment, delivery and refund rules. A prototype that still exposes legacy construction freight is incomplete against the final simplicity goal; resolve that presentation and service boundary before the public introduction ships.

The existing upcoming-extra-costs calculation continues to exclude ordinary running purchases, labour and maintenance. Surface newly required startup inputs and eligible exceptional payments only when payable next turn. Preserve the £100 notice threshold, £50 upward buffer rounding and loading/turn-1 suppression unless explicitly redesigned. Immediate costs belong in the action confirmation, not a misleading next-turn notice.

## Ownership, destination and operator

Represent three separate questions:

| Question | Examples |
| --- | --- |
| Who owns the goods? | Player; intermediary after a sale |
| Where should they go? | Owned tile stockpile; another tile; intermediary sale; direct port sale |
| Who moves retained goods? | Own local handling; own road/rail fleet; pipeline |

Selling to the middleman transfers ownership and creates revenue. It is a building-level buyer/seller, not a carrier for player-owned goods. It cannot move goods to another building or warehouse, even on the same tile. Retaining and transferring goods requires owned logistics. A route to stockpile must never silently become a sale.

A building may use different arrangements for different inputs and outputs. For example, consume owned steel, buy other inputs, and sell finished hydraulic equipment through the intermediary.

Use one authoritative transfer/order record. The producer's output assignment and consumer's sourcing preference must resolve to that record, not create duplicate shipments. Reserve quantities across consumers deterministically. Preserve existing in-flight ownership when policies change; new defaults apply to new orders, with any cancellation offered explicitly.

## Storage and local handling

The tile Stockpile tab initially explains that market service is outsourced and offers **Build warehouse**. This opens normal construction and shows land/space, capital cost, capacity, running costs and the purpose of retained inventory. Draw the completed warehouse on the map and in Empire view.

Current free/base tile storage must receive an explicit migration/design rule. Hiding its bars does not make storage owned progression. Distinguish any minimal building operating buffer from a general warehouse the player can deliberately fill and trade from.

A warehouse provides storage and a proposed basic local handling allowance. Tile policy:

- **Own handling:** use available warehouse/local handling capacity.
- **Unavailable capacity:** queue unmet transfers and show the resulting production risk. Middleman service is not a local-haulage fallback; separately buying at a consumer and selling at a producer is two market trades.

Define local handling as a player-owned inventory movement within the tile, separately from market purchase/sale and cross-tile haulage. The middleman offers no such movement. Fully outsourced buildings trade independently and cannot share inventory or use JIT between them. Player-retained inventory and warehouses belong to owned logistics; provider service buffers are isolated to the building transaction.

Keep surplus guidance and Other Goods expansion. On redirecting output to retained stock, show expected accumulation, lost immediate sales and the option to sell only surplus after local needs. Reserved/inbound quantities must be visible separately from freely sellable stock.

## Logistics Hub and transport capacity

The [selected Logistics Hub design](logistics-hub-design.md) is authoritative for later hub phases. Keep the original operating inputs: 2 hydraulics + 4 tyres + 6 fuel, or one lithium/sodium battery instead of fuel. One recipe services 125 road/L1-rail LC or 300 L2-rail LC, applied to the actual hub-operated movement. Accumulated usage/service credit replaces the old per-turn minimum-one rule; exact inventory and failure semantics belong to the hub contract.

Coverage is the centre plus six adjacent tiles, with connected eligible routes. Consolidate compatible cargo at the same tile and availability turn, independent of original source/departure. Requote the generic carrier from a reachable shared handoff; no fractional invoice subtraction or automatic bulk discount. Preserve continuous physical journeys for congestion accounting. Installed fleet capacity, network congestion and operating supplies are separate constraints. Generic fallback cannot silently become a middleman sale and rebuy.

The working 100-weighted-unit payload and 10 LC per installed vehicle are documented with their calibration limits. Hub equipment, capex, fixed overhead, return/unloading occupancy, rail access and special-cargo compatibility still require later implementation contracts. They do not block middleman phases 0–2.

### Pipelines

Initially use compatible pipes/reinforced pipes with capacity, access and operating costs independent of truck/rail capacity. Show owned pipeline flow explicitly. Do not require a Logistics Hub to create fictitious truck capacity for pipe goods.

A Pumping Station is a later option if power, pressure, range or throughput creates a worthwhile tradeoff. Decide pipe operation, compatibility and ownership rules before adding the building; avoid a compulsory extra click with no strategic consequence.

## Defaults and controls

Resolve policy in this order: **company → tile → building → explicit route override**. Display the inherited source and provide Reset to default. Destination and ownership are not changed merely by selecting another transport provider.

The **Use own logistics** action should preview affected routes, required capacity, estimated fees avoided, running costs, additional inventory/cash buffer and fallback behaviour before applying changes. It must identify ineligible routes and leave existing in-flight shipments intact.

Keep a global logistics entry visible from the start with the intermediary bill and explanation of ownership opportunities. Reveal fleet, congestion and detailed shipment controls when relevant, rather than hiding the existence of the system entirely.

## UI surfaces

| Surface | Required change |
| --- | --- |
| Building detail: inputs | Source preference, provider, landed cost and startup funding; show inherited policy |
| Building detail: outputs | Distinguish intermediary sale, retained stock and direct sale; per-good operator |
| Build/upgrade confirmation | Initial batch funding, service fees, operating estimate and owned-logistics prerequisites |
| Tile Stockpile tab | Build warehouse, capacity/ownership, local handling policy, reservations and surplus controls |
| Logistics Hub detail | Equipment/configuration, fuel/power, workload, service area and available capacity |
| Stockpiles & Shipments dashboard | Separate intermediary transactions from owned inventory and in-flight shipments; fleet queues and fallback |
| Money panel and top bar | Goods purchases and sales, one aggregate Middleman fee, separately managed owned-logistics costs when applicable, and matching cash reconciliation |
| Market and port panels | Intermediary versus direct quotes, market impact, entry costs, settlement delay and buffer |
| Map/build menu | Warehouse and hub construction, mode connections and route selection |
| Empire/supply-chain view | Provider-aware connections, warehouses and intermediary endpoints |
| Research | Logistics improvements and accessible entry requirements |
| Tutorial, starts and help | Simple outsourced opening, optional owned-logistics lessons |
| Victory/progression | Re-evaluate logistics-efficiency and autarky scoring so outsourcing and ownership have deliberate consequences |

Do not promise lower costs solely because logistics is owned. Present savings estimates at stated throughput and prices, including fixed costs and working capital.

## Empire view and visual language

Attach short road, rail or pipe sections to the relevant building connections. Animate company vehicles or directional pipe flow on owned operations. Use an operator emblem/label as well as mode and colour: a truck alone does not establish who runs it.

- Intermediary market leg: compact service badge and Local market endpoint.
- Owned haulage: short mode-specific connection and company vehicle animation.
- Retained inventory: visible warehouse endpoint and stored quantity.
- Direct global trade: actual port endpoint and shipping activity.
- Selected connection: provider, quantity, cost, capacity, destination and routing action.

Ownership is per leg, not a single building-wide decoration. A mixed factory must remain legible. A Logistics Hub provides service; do not draw all goods physically passing through it unless it is also their actual destination.

The current graph infers supply relationships from compatible recipes and is arranged around buy/sell ports. Extend its model to distinguish potential relationships from actual assignments, add intermediary endpoints independent of ports, and retain ports for direct trade. Goods graph remains the recipe possibility view; Empire view explains the player's operating company.

At large scale, show compact badges at rest and expand selected routes. Do not render the entire road network behind every supply-chain connection.

## Tutorial restructuring

Move **Find the factory inland** (`goto_tile`) near the beginning. Use stable step IDs, not the displayed step number, when restructuring. Move the Capital City road/rail/port lesson out of the opening tutorial.

Proposed introductory sequence:

1. Find and buy the window factory; introduce its tile panel through that action.
2. Read the graphical recipe: input quantities, output and power.
3. See that the intermediary supplies inputs and buys output, with an explicit fee.
4. Run production and reconcile one turn of receipts, costs and cash.
5. Explore the focused goods graph and the choice to make an input later.
6. Continue playing, with optional advanced lessons available.

The opening factory should already have power and intermediary service configured. Move most steps after the graphical recipe explanation to contextual or advanced lessons, but retain the short production-and-money demonstration so the player finishes with a working business.

Advanced chapters:

- Make your inputs: build a supplier and compare costs/recipes.
- Own storage and handling: warehouse, retained inventory, reservations and surplus.
- Run transport: Hub, road/rail route, capacity, fallback and shipment timing.
- Trade directly: port access, fee comparison and working-capital requirements.

Power, research and advisors can receive separate contextual introductions. Allow advanced lessons to be replayed from a prepared scenario without requiring the whole opening again.

The existing tutorial engine seeds shipments, grants resources/cash and hands off from Capital City to Stoneshore. Create dedicated scenario setup for the new introduction and advanced chapters; deleting/reordering step entries alone will leave invalid dependencies. Preserve useful flash/spotlight guidance for the retained steps.

## Technical boundaries and migration

Keep deterministic simulation outside per-building scene nodes. UI consumes quotes and submits commands; it does not independently calculate fees or mutate inventory.

Keep the existing top-level `DECIDE → PROCESS → SEND → AI → NARRATIVE → RECEIVE → DECIDE` sequence for the prototype. Refactor the internal `PROCESS` order: settle existing arrivals/construction → plan and fund inputs → supply middleman inputs → run the existing bounded production cascade → consolidate output sales and inclusive fees → finish accounting and publish results. Preserve power dependencies and at-most-once execution per building. The detailed [turn-order assessment](transport-middleman-phasing-plan.md#turn-order-assessment) records the required funding, output-dispatch and callback changes; the current internal order cannot remain unchanged.

Suggested responsibilities, to be mapped onto existing services rather than automatically creating more autoloads:

- Policy resolution and validated commands.
- Pure quotes for intermediary trade and contracted haulage.
- Shared input/transfer planning and funding reservations.
- Settlement and ownership ledger.
- Fleet/service allocation over existing route capacity.
- Read-only UI/Empire projections.

Orders need stable IDs, owner, source/destination, operator, good, quantity, pricing/fee basis, funding state and lifecycle status. Store durable orders and policies in versioned saves; recompute derived previews. Preserve deterministic ordering for allocation, price impact and settlement.

Introduce an explicit ruleset/save version boundary. Old saves must either retain legacy logistics or undergo a specified migration. Never convert existing in-flight purchases/sales into completed intermediary trades without settling their outstanding bills, ownership and receipts exactly once. Preserve construction prepayments, cancellation rights and loan associations.

Do not silently remove existing stock or warehouses when introducing ownership progression. Define treatment of baseline storage, overflow and stranded inventory. Save/load during mixed logistics must preserve reservations, fleet occupation and policy overrides.

## Delivery sequence

1. Prototype Pepper Valley Motors: outsourced operating market legs, funding, the dynamic 0.5% + class/location service tariff (storage included) and same-turn settlement behind an explicit ruleset flag. Compare with the versioned road/port steady-shipment baseline on the identical site.
2. Trial starts and reconcile every cash movement against the confirmed funding and tariff rules.
3. Add owned warehouse progression and owned local handling and independent building-level market service.
4. Add road fleet service and policy inheritance/bulk route conversion.
5. Add rail service and direct port trade comparisons.
6. Extend pipeline operation only where the base design requires it.
7. Finish provider-aware Empire visuals and the new tutorial scenarios alongside their corresponding playable mechanics.

Do not ship the shortened tutorial ahead of the economic model it teaches. Avoid mixing this redesign into the completed 0.4.2 fixes PR.

## Validation and acceptance criteria

Economic trials compare the same businesses under legacy and intermediary rules: metals, glass, motors, hydraulic equipment, ingredient-heavy recipes, and low-value bulk goods. Include port-side and inland tiles using actual route conditions. Measure first-sale turn, minimum starting cash, idle turns, fees, operating profit, borrowing, retained inventory, and payback/working capital when switching logistics.

Required behaviour checks:

- One funded operating cycle can purchase, produce and sell within one resolution; no extra production or duplicate market impact.
- Fully outsourced operation shows one Middleman fee and requires no management of provider congestion, port capacity, distance bills or warehousing; those responsibilities appear only for functions taken in-house.
- Covered work cannot accrue separate freight, congestion, port or warehouse charges, including indirectly through cost reports or legacy settlement paths.
- Ordinary operation does not fill the legacy multi-turn import buffer or generate repeated exceptional-bill notices.
- Splitting an order into UI/API calls cannot reduce its consolidated tariff.
- Shared inputs and fleet capacity cannot be allocated twice.
- Stockpile redirection retains goods and removes the corresponding sale receipt.
- Mixed providers, fallback, unavailable fuel/power, congestion and own-only queues behave as quoted.
- Money panel, building accounting and top bar reconcile the same settlement ledger, including credit movements.
- Construction prepayment and same-turn refund still work; land remains owned.
- Switching policy and save/load cannot duplicate deliveries, bills or receipts.
- New tutorial reaches a functioning company without compulsory road, rail or pipe building.
- Empire ownership indicators match actual assignments and remain legible at scale.
- Existing deterministic tests, parse checks and end-to-end scenarios pass under the intended legacy/new rulesets; UI changes receive windowed inspection.

## Remaining decisions and scope

[Phase-0 contract](middleman-phase-0-contract.md) freezes funding, runtime price basis, private holdings, failure, eligibility and save boundaries. Pure quote/budget code and fixtures exist; real gameplay settlement remains phase 1.

Later phases still need warehouse migration/local handling, hub equipment/capital/occupancy, generic fallback policy, full cargo-class eligibility, global city metadata, direct-trade investment targets and tutorial/release migration. The middleman never provides contracted internal haulage. Pumping Stations remain deferred.

## References

- [Earlier static cash-flow comparison](reviews/middleman-cashflow-2026-09-12.md): illustrative tariffs and current timing evidence, not calibrated new-model results.
- [Construction prepayment](reviews/construction-prepayment-2026-09-13.md).
- [Exceptional-cost scope](reviews/extra-costs-2026-09-13.md).
- [Stockpile guidance and commitments](reviews/stockpile-and-commitments-2026-09-12.md).
- Implementation touchpoints: `scripts/production.gd`, `input_order_planner.gd`, `transport_state.gd`, `transport_service.gd`, `cash_commitments.gd`, `empire_graph.gd`, and `scripts/tutorial/tutorial_steps.gd` / `tutorial_engine.gd`.
