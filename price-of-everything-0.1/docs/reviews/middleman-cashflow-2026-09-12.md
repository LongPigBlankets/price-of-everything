# Same-turn logistics middleman: cash-flow analysis — 12 September 2026

Proposal only. The simulation was not changed. Notice copy was updated to “Upcoming costs: X. If the treasury is short, we might need to take a loan.” Estimates retain ≈, and the complete sentence is allowed to wrap rather than being truncated.

## Evidence from the current implementation

- `MatchState.queue_buy`: market inputs with transit are paid on arrival, not on ordering (the introductory comment is stale). Zero-turn purchases settle immediately. Quoted unpaid shipments consume purchase headroom.
- `Production._process_transport_arrivals`: arrival bills, including freight, settle before production; full arrival payment occurs even if the warehouse cannot unload everything.
- `InputOrderPlanner.allocate`: imported input target is uncovered recipe demand × (lead + 1), less shared stock/inbound. Partial local supply may add a safety buffer. Road distance alone does not determine lead: routes, infrastructure, terrain and goods matter.
- Production replenishment orders are placed after production. Simply setting freight time to zero does not permit purchased inputs to feed the production pass that has already finished.
- Market sales remove output and charge freight on dispatch; revenue reaches cash on port arrival. Both the ordinary production-sale and stockpile-sale paths implement this timing.
- The purchase spread is already 5%. Local freight has per-unit/per-route and class-specific ad-valorem components; sea handling currently adds a scheduled percentage (early 0.5%, later 3%, with growth/modifiers). The proposed tariff must explicitly replace or supplement these charges.

## Real-map quote sample

Fresh Metal Magnate start, turn 1. One reachable sampled tile for each straight-line nearest-port distance. Full L1 recipe quantities, external purchase of every input, all output sold. These are read-only quotes, not factory profitability or a simulated middleman playthrough. Location feasibility, ramp-up, labour, power, maintenance, storage, taxes, credit and market-price evolution are excluded. Different tiles at the same distance can have different routes.

Illustrative middleman tariff (not a recommended calibration): **3% of transaction value + (£1 + £0.50 × port distance) per good shipment**, on both imports and exports. The percentage uses the quoted purchase invoice value (including the existing ask spread) and sale value. It replaces all current freight in this comparison. No doubled port charge.

| Recipe | Distance | Tile | Input / sale lead | Current total freight | Illustrative middleman fee | Current trade contribution | Middleman contribution |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: |
| Pig iron | 0 | tile_5_10 | 0 / 0 | £0.71 | £7.12 | £41.18 | £34.77 |
| Pig iron | 2 | tile_4_8 | 1 / 1 | £5.69 | £10.12 | £36.20 | £31.77 |
| Pig iron | 4 | tile_2_12 | 5 / 5 | £25.62 | £13.12 | £16.28 | £28.77 |
| Pig iron | 6 | tile_3_5 | 4 / 4 | £20.63 | £16.12 | £21.26 | £25.77 |
| Pig iron | 8 | tile_2_16 | 6 / 6 | £30.60 | £19.12 | £11.30 | £22.77 |
| Motors | 0 | tile_5_10 | 0 / 0 | £2.93 | £20.10 | £89.73 | £72.56 |
| Motors | 2 | tile_4_8 | 1 / 1 | £11.79 | £23.10 | £80.87 | £69.56 |
| Motors | 4 | tile_2_12 | 5 / 5 | £47.19 | £26.10 | £45.46 | £66.56 |
| Motors | 6 | tile_3_5 | 4 / 4 | £38.34 | £29.10 | £54.32 | £63.56 |
| Motors | 8 | tile_2_16 | 6 / 6 | £56.05 | £32.10 | £36.61 | £60.56 |
| Hydraulics | 0 | tile_5_10 | 0 / 0 | £0.92 | £9.33 | £45.28 | £36.86 |
| Hydraulics | 2 | tile_4_8 | 1 / 1 | £3.84 | £13.33 | £42.35 | £32.86 |
| Hydraulics | 4 | tile_2_12 | 5 / 5 | £15.54 | £17.33 | £30.66 | £28.86 |
| Hydraulics | 6 | tile_3_5 | 5 / 4 | £13.15 | £21.33 | £33.04 | £24.86 |
| Hydraulics | 8 | tile_2_16 | 6 / 6 | £18.46 | £25.33 | £27.73 | £20.86 |

“Contribution” here means sales minus input purchases and freight only, before every other business cost. It is not net profit.

## Cash consequences

1. **Smaller input buffers and arrival bills.** A sampled four-tile pig-iron location quotes a five-turn input lead. The ordinary fully imported pipeline target is six batches. At £47.77 of inputs per recipe run, filling an empty pipeline represents about £286.62 of goods before freight. Instant demand-matched purchasing needs one batch (~£47.77) for that run. The existing target must be reduced alongside the timing change; otherwise instant delivery just charges the large buffer earlier. Stock, construction and funding caps change the actual initial order.
2. **No wait for customer receipts.** The same sample waits five turns from output dispatch to sale receipt. At one L1 run per turn, £89.66 sales per batch means roughly £448.30 of gross sales can be in transit at steady throughput. Instant sales remove that receivables delay. This is a working-capital comparison, not £448.30 of additional profit each turn, and must not be added to the inventory example as a universal exact funding saving.
3. **More legible operating cash.** With receipts and purchases settling in the same turn, the recurring change becomes much closer to one production cycle’s margin. The new fee still makes inland production less profitable than identical port-side production, but the extra cash tied up in transit largely disappears for market legs.
4. **Upfront payment can occur sooner.** Current inbound shipments give supplier credit until arrival. An instant purchase collects now. If inputs must be funded before sales, the player still needs one batch of inputs and applicable fees. If the intermediary accepts only net payment after sales, it is providing working-capital credit too; that is a separate balance choice.
5. **Fees can consume the recovered margin.** A hypothetical percentage plus per-good fee does not help all recipes equally. In the sample, pig iron and motors benefit from lower freight on the five-turn route, whereas hydraulics’ illustrative fee rises from £15.54 to £17.33. Better cash timing can coexist with lower profit.

## Formula and design choices

For sales R, input invoice value I, other operating cash costs O, percentage x on both trade directions, n shipments, and flat fee F(d):

`cash generated = R − I − O − x(R + I) − nF(d)`

At constant prices and throughput, instantaneous settlement changes timing; ongoing profit changes by the difference between the new fee and the current freight it replaces. Earlier startup, fewer stockouts, lower warehouse needs and lower borrowing interest are additional dynamic effects not priced in the static comparison.

- Define a shipment as a consolidated tile/good/direction/turn order (or another explicitly chosen unit). Charging per low-level API call would make fees depend on implementation details, while charging per building punishes an existing company sharing supplies on one tile. Per-good fees penalise recipes with many ingredients and small batches.
- Retain buy/sell price impact and the spread. Quote fees separately in build and money panels. Prevent repeated production or fee-avoidance loops within one turn.
- A uniform percentage changes the current relative advantages of bulk goods, gases and high-value light goods. Consider cargo-class handling rates and route accessibility. Flat distance only can make hauling gas no different from carrying electronics.
- Instant outsourced market trade weakens the value of ports, roads, inventory buffers and logistics research. Keep a clear benefit for owned logistics (lower cash cost, capacity, market access, emissions, or internal transport), and revisit the logistics victory track. Existing inter-company and internal shipments need not become instant.
- Resolve once per turn: plan and fund inputs → acquire them → produce once → sell → settle remaining costs. Merely making existing post-production orders zero-turn is insufficient. Net end-of-turn settlement would be a different financing mechanic.
- Existing saves need explicit handling of in-flight purchases/sales to avoid duplicate deliveries, bills or receipts. Construction delivery timing should be a separate decision rather than changing accidentally with market inputs.

## Recommendation

Worth prototyping as a simpler default market-access service. It directly addresses the current inland startup shock and delayed-sales confusion, but changes economic pacing and the value of geography substantially. Keep the visible buy-versus-make decision: outsourcing is convenient and predictable, while investing in direct logistics/integration should save enough fees to matter.

First compare the same pig-iron, motors and hydraulics businesses at the sampled locations under current and middleman rules. Measure minimum cash needed, first-sale turn, stalled production turns, recurring contribution, borrowing, fees as a share of revenue, and how quickly fee savings repay owned infrastructure. Tune percentage and flat fees from those results rather than assuming smoother cash flow also means viable margins.

Artifacts are in repository-root `outputs/middleman-analysis-2026-09-12/`. Reproduce read-only quotes with the existing commitments harness and `--middleman-study`.

Verification of the notice update: 403 unit tests / 3,929 assertions passed; 100-turn E2E 723 assertions passed with unchanged non-timing results; parse sweep 607 scripts / zero failures; windowed notice and navigation checks passed. The middleman comparison itself is static quote analysis, not a tested replacement simulation.
