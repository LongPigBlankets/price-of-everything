# Logistics Hub hand-offs and ten shipments per vehicle — 19 September 2026

This revision limits each hub to its own tile and adjacent tiles. It supplies only the covered road segments; uncovered segments use the ordinary carrier, or another hub covers them. One installed vehicle supplies ten shipment movements per turn. No live logistics, tariffs or recipe data changed.

## Service contract

- A shipment movement is one canonical batch of one good moving across one adjacent-tile edge. The same batch moving across two covered edges consumes two LC. This is an explicit modelling interpretation of “ten shipments”, preserving distance as a capacity cost.
- Shipments remain player-owned through hand-offs. There is no middleman purchase/sale, duplicate port charge or new goods receipt at a hub boundary. The regular carrier is the existing direct transport system, not the building-only middleman.
- An edge is hub-covered when both endpoints lie within that hub’s radius. A boundary-crossing edge belongs to another eligible hub or the carrier. Overlap never bills or consumes capacity twice.
- Each hub installs `ceil(allocated LC / 10)` vehicles. Capacity is local to the hub; it cannot borrow vehicles from a distant hub. Adjacent hubs hand over at a shared boundary tile.
- Split API calls must not change logical shipment count. A finite payload cap is still needed: otherwise an unlimited cargo batch costs the same LC as a tiny one. All current benchmark batches are below 100 units, so a proposed 100-unit cap would not change these results. Mixed cargo, empty returns, loading and freight-class payload factors remain unmodelled.
- Record the transfer once with progress and ownership preserved. Changes to transport operator must not reset travel time, accelerate the shipment or advance it twice in one turn. This is an implementation requirement, not something the arithmetic model validates.

The financial model retains 0.5% middleman ad valorem, solid-heavy .05, ultra-heavy .50, and the existing direct-road/port/storage bills. Hub supplies use the middleman; hub fuel’s safe-liquid rate remains provisionally .03. Only covered inland freight is replaced.

## Actual Pepper Valley route coverage

Existing road paths each contain eight adjacent-tile hops grouped into four game movement legs. A hub at `tile_5_4` covers one hop in each direction. An adjacent hub at `tile_5_5` (or `tile_6_4`) covers two in each direction. These are geometric placements; land/buildability and hub construction costs are not priced.

For the two-building chain there are three inbound good batches (iron ingots, coal, copper wiring) and two outbound batches (motors, surplus steel). Local furnace-to-motor consumption remains existing same-tile handling and is not assigned invented road shipment work. Thus the factory-site hub handles 5 LC per turn; the adjacent hub handles 10 LC. Either needs one vehicle.

| Coverage for motors + furnace | Vehicles | Equipment upfront | Freight avoided/turn | Carrier freight remaining/turn |
| --- | ---: | ---: | ---: | ---: |
| Hub on factory tile | 1 | £309.32 | £5.28 | £36.98 |
| Well-placed adjacent hub | 1 | £309.45 | £10.57 | £31.70 |
| Five-hub corridor | 5 | £1,547.23 | £42.26 | £0.00 |

The full corridor has 40 shipment-hop units of work per turn. Five hub-local vehicles suffice after assigning overlapping coverage to keep every hub at ten LC or below; using a global `ceil(40/10)=4` would incorrectly share capacity between sites. Selected hub workloads are 5, 10, 10, 8 and 7. One motor factory alone uses 24 LC across the same network and still needs five vehicles because of geography.

Vehicle prices include the existing buy markup and experimental middleman delivery. Rural adjacent hubs use coefficient 1.75; the small urban port hub uses 1.5. Counts optimize assignments for this fixed five-hub coverage, not all possible depot layouts or construction costs.

### Partial-leg tariff caveat

Current game freight is charged by whole movement legs. The experiment prorates a covered fraction of a leg by physical edges, conserving the original charge. A factory-tile hub covers only half a leg and would save **nothing** if the carrier still charged that whole leg. The adjacent placement covers a complete leg in each direction, so its £10.57 saving does not depend on fractional billing. The raw report includes both billing interpretations. Real hand-off support needs explicit partial-leg quotes; these savings are not already implemented game behaviour.

## Running cost remains the constraint

The original full recipe (2 hydraulics + 4 tyres + 6 fuel) costs £64.05 per turn at the factory, or £64.17 at the adjacent rural site, including supply delivery. Paying it at every active hub remains much more expensive than the freight saved. The adjacent-hub chain earns **−£46.94 per turn**, compared with £6.67 on ordinary roads or £27.62 through the middleman. Even consuming one batch every five turns leaves only £4.40, below ordinary roads.

Reducing the upfront fleet from many vehicles to one helps capital requirements; it does not reduce a fixed recipe charged once per hub per turn. A local hub cannot remove the other three-quarters of carrier freight. Even a free-to-operate adjacent hub leaves chain profit at £17.23, still below the £27.62 middleman result. It can nevertheless be an incremental improvement for a company that already runs direct logistics.

## Separate sensitivity: inputs scale with LC used

A possible next experiment is to express the supplied recipe as a maintenance budget for **125 LC**, then consume inputs proportionally to actual LC used. Ten LC at the adjacent hub consume 10/125 of a recipe, costing **£5.13/turn**. This changes the operating rule; it is not the requested full recipe every turn and has not been adopted in gameplay. Integer replacement components would need wear accounting or scheduled replenishment, rather than minting stockpilable LC.

| Operating contribution | Middleman | Ordinary roads | Adjacent hub, proportional 125-LC recipe | Full corridor, proportional 125-LC recipe |
| --- | ---: | ---: | ---: | ---: |
| Motors only | £22.72 | £-3.86 | £2.42 | £21.27 |
| Motors + furnace | £27.62 | £6.67 | £12.10 | £28.39 |

This keeps full-corridor outsourcing preferable for one factory but creates a small integration advantage for the local steel chain. That advantage is only about £0.77 per turn over the middleman, before hub overhead. Five vehicles alone would take roughly 2,024 turns to recover it. It is therefore a demonstration of the crossover, not investment-balance sign-off. Partial adoption can pay back against existing direct freight earlier, but it does not yet beat starting with the provider.

The report also evaluates 100 and 160 LC per recipe. The next tuning decision is the operating recipe’s LC output or proportional consumption, separate from installed vehicle capacity. Vehicle capacity remains ten LC per vehicle per turn in every sensitivity.

## Reproduction

```sh
python3 tools/analyse_logistics_hub_handoffs.py
```

[Scenario](../../tests/scenarios/pepper_valley_hub_handoffs.json). [Full results and per-edge hand-off trace](../../reports/balance/logistics_hub_handoffs_2026-09-19.json). The analyser reconstructs recorded inland charges, validates vehicle capacity, conserves covered/uncovered billing and checks that full corridor coverage replaces exactly the original inland charge. It is arithmetic on retained game routes, not a new physical simulation. Hub overhead, building/land capex and new shipment timing remain excluded. Earlier full-route single-hub assumptions remain historical evidence in the [previous review](logistics-hub-capacity-2026-09-19.md).

## Rounding and weight follow-up

User-specified consumption now rounds each input once per hub per turn: sum actual LC handled, multiply by the recipe quantity / 125, round half-up, and enforce a minimum of one unit for every positive result. An idle hub consumes zero. No fractional wear is carried to a later turn under this rule. Earlier fractional-consumption tables remain historical sensitivities, not the current rounding contract.

Apply weight to **LC workload**, then derive both installed fleet requirements and consumables from that same workload. Suggested initial multipliers are solid-heavy 1× and ultra-heavy 2×. These are illustrative capacity factors, separate from the .05/.50 middleman price weights; copying that 10× price ratio would impose an unvalidated capacity penalty. Other cargo classes, canonical batch size and payload limits remain open. Splitting identical orders must not change workload.

`weighted LC = sum(canonical shipment batches × covered tile-hops × cargo multiplier)`

`vehicles = ceil(weighted LC / 10)`

`consumption[good] = max(1, round_half_up(recipe[good] × weighted LC / 125))` for an active hub, otherwise zero.

Do not multiply consumables by cargo weight a second time. Apply rounding to hub totals, not to every individual movement, which would multiply the one-unit minimum repeatedly.

At the well-placed adjacent Pepper Valley hub, motor-only workload rises from 6 to 8 LC and still needs one vehicle. The motor/furnace chain rises from 10 to 12 LC and needs two vehicles for full coverage (or one vehicle with excess traffic billed by the carrier; that partial-capacity case is not calculated here). These counts treat each benchmark good batch as one canonical shipment before weight adjustment.

The rounding floor materially changes cost. Both cases now consume one hydraulic component, one tyre and one fuel per active turn: **£17.96 delivered**, compared with the previous unrounded £5.13 chain estimate. The chain only avoids £10.57 of freight, so the hub loses £7.40 against the ordinary carrier before hub overhead; company profit becomes −£0.73. Lithium’s one-unit minimum costs £67.79 and sodium’s £38.41 including the tyre and hydraulic component. Weight does not increase rounded consumption at these small loads, although it increases required vehicles.

Thus the integer rule is implemented in the analysis, but does not preserve the previous small-hub profitability. Lower utilisation is expensive because every active hub consumes a minimum of one of each input. Restoring an attractive entry hub would need a different maintenance cadence, operating quantities/prices, or enough shared traffic to spread that floor. Raising LC per recipe alone cannot remove the one-unit floor.

Run `python3 tools/analyse_hub_rounding_weight.py`. [Rounded/weighted results](../../reports/balance/hub_rounding_weight_2026-09-19.json). The analyser checks half-up boundaries, zero activity, full recipe consumption at 125 LC and both example workloads. No live gameplay change; weight multipliers remain a proposal.

## Adopted progression and LC weights

The intended progression is **middleman → generic carrier → self-owned Logistics Hub**. The hub is top-tier integration. Its minimum consumption and upfront vehicles deliberately make it uneconomic below a useful scale; small-hub losses are not themselves a balance failure. The relevant acceptance gate is that a sufficiently utilized hub can eventually outperform the generic carrier after recurring costs and recover its capital. The earlier suggestion to eliminate the small-hub cost floor is superseded.

User-selected LC weights:

| Cargo | LC per canonical shipment per covered tile-hop |
| --- | ---: |
| Light solids | 1 |
| Heavy solids | 2 |
| Ultra-heavy | 5 |
| Liquids (`safe_liquid` and legacy `liquid`) | 2 |
| Hazard liquids | 4 |
| Gases | 3 |

These multiply workload, not prices. Consume operating goods based on the resulting LC, then round each input once per hub per turn. Do not apply weight twice. One vehicle still supports ten weighted LC. Existing pipe eligibility, tanker restrictions and route capacities remain separate; assigning a gas multiplier does not grant an otherwise unavailable route. The model rejects unmapped classes instead of silently treating electricity or unclassified goods as truck cargo.

For the adjacent Pepper Valley hub, motors alone require **18 LC and two vehicles**: four heavy-solid movements ×2 plus two motor movements ×5. Motors plus furnace require **26 LC and three vehicles**: eight heavy-solid movements ×2 plus two motor movements ×5. At the current 125-LC recipe calibration, both still round to one hydraulic component, one tyre and one fuel per active turn. Such low-volume economics are intentionally not the top-tier target.

Capacity and operating efficiency remain separate calibration levers. With these higher LC weights, 125 LC per recipe has an unrounded diesel cost of about £13.35 for the chain’s 26 LC, versus £10.57 of covered carrier freight. Hence simply increasing copies of this exact traffic mix on the same route will not create a sustained large-volume advantage at unchanged prices/capacity. The LC recipe output needs to exceed roughly 158 for that mix even before hub overhead or capital recovery; batching/payload rules and different route economics may also change the comparison. This is a future high-utilization balance gate, not a reason to remove the intentional one-unit minimum. Fractional recipe output, capacity and actual integer consumption must be compared at scale before choosing the final recipe yield.

[LC contract](../../tests/scenarios/logistics_hub_lc_weights.json). [Updated v2 results](../../reports/balance/hub_rounding_weight_v2_2026-09-19.json). Run `python3 tools/analyse_hub_rounding_weight.py`; rounding, zero activity, all selected class mappings and the 18/26-LC examples pass. Prior 1×/2× weight results remain historical. No live hub implementation or goods-price changes.
