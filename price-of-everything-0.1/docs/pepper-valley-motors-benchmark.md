# Pepper Valley Motors benchmark

Current live provider evidence: [Phase-1 implementation and benchmark](middleman-phase-1-implementation.md). The historical runner and arithmetic controls below are retained unchanged.

> The runner profiles below retain historical fixed-fee arithmetic controls. The implementation target is now the [dynamic 0.5% middleman tariff](transport-middleman-layer.md#tariffs); phase 1 adds a separate versioned real provider run. Do not relabel the existing runner as implemented middleman gameplay.

Current scenario contract: 4; congestion accounting: 2; current balance snapshots: 5. Defined 19 September 2026 on `codex/transport-middleman-layer`.

This is the permanent first comparison for the [middleman proposal](transport-middleman-layer.md) and its [phasing plan](transport-middleman-phasing-plan.md). Keep the same factory/site and preserve versioned contracts when changing tariffs or output so improvements remain comparable.

## Current v5: £40 provider fee and normal ports from turn one

The current [contract](../tests/scenarios/pepper_valley_motors_middleman_ports.json) uses 33 motors, a **£40 middleman reference (£16 inputs + £16 outputs + £8 warehousing)**, and `middleman_v1` port policy: normal 3% base from turn one, with existing growth and research modifiers. Legacy saves and tutorials retain their existing policy until migrated. The provider itself is still reference arithmetic; the ruleset flag implements the port policy, not middleman service.

| Operating contribution per turn | Middleman reference | Public roads | Rail, three owned tiles |
| --- | ---: | ---: | ---: |
| Early regular shipments, turns 10–19 | £16.83 | −£1.68 | £17.39 |
| Base, turns 40–49 | £15.22 | −£3.86 | £15.22 |
| +10% output modifier, rounded to 36 motors | £48.36 | £26.14 | £46.75 |
| Same output plus Depot Scheduling and Groupage | £48.36 | £32.14 | £49.79 |

The start-of-game operating advantage for outsourcing is not fully achieved: rail is £0.57 ahead in the early window, then effectively tied in the base window. Research produces a small rail crossover; roads need further progression. See the [fee and progression review](reviews/middleman-fee40-progression-2026-09-19.md) for component costs, assumptions and remaining tuning.

The default runner writes `-fee40` outputs and v5 snapshots. `--stage early`, `--stage output` and `--stage research` select additional checks. The historical v3 profile uses `--balance targeted`; v4 preserves the exploratory £40 comparison before removing introductory port relief.

The [JIT and local-steel extension](reviews/pepper-jit-furnace-2026-09-19.md)
preserves separate `jit`, `furnace` and `furnace-jit` snapshots, with no changes
to the base comparison or live tariffs.

## Historical v3 balance trial

The [targeted output trial](reviews/targeted-output-gains-2026-09-19.md) is applied: Motor Manufacture now produces **33 motors** from the same inputs, power and staffing. That profile uses its explicit [scenario contract](../tests/scenarios/pepper_valley_motors_targeted_gains.json) and v3 snapshots. Same site and £10/£10 middleman fee. The original 30-output contract and v1/v2 snapshots below remain the historical controls.

| Operating contribution per turn | v2: 30 motors | v3: 33 motors |
| --- | ---: | ---: |
| Middleman reference | +£2.09 | +£35.22 |
| Public roads | −£33.86 | −£3.86 |
| Rail, three owned tiles | −£16.32 | +£15.22 |
| Rail, seven owned tiles | −£28.32 | +£3.22 |

Road and rail are actual game simulation; middleman is still reference arithmetic. Maximum tile flow is now 97 and congestion remains zero. Temporary output directories use `-targeted`; the control profile uses `-control`. After explicitly reverting the [trial manifest](../data/targeted_output_gains_2026_09_19.json), `--balance control` checks the v2 baseline. Profile selection never alters live data. See the trial review for exact apply/revert instructions and 19 paired coastal regressions.

## Original scenario contract (30-output control)

- **Site:** Pepper Valley city, `tile_5_4`. This deliberately differs from the existing NPC motor factory on neighbouring `tile_6_5`.
- **Business:** exactly one player-owned L1 industrial factory (`b_007`), Motor Manufacture (`r_009`), 32 steel + 32 copper wiring + 30 power → 30 motors per full operating turn. No upstream factories, production bonuses, owned generation or debt.
- **Shared setup:** owned land, grid cable access, £10,000 cash to isolate operating economics, no opening stock or pre-seeded shipments. The cash allowance is a benchmark control, not a balanced starting-cash recommendation.
- **Middleman:** purchases the whole input basket for one £10 fee and buys the entire output batch for one £10 fee. Total visible logistics fee: £20 per full operating turn. No percentage, per-good fee, port charge, congestion surcharge, distance bill or warehouse charge. Goods prices and factory operating costs remain separate. Zero activity has zero corresponding fee.
- **Direct:** the identical factory imports inputs and exports motors through the actual existing public roads and the catalogue-selected port. Retain real travel times, congestion, port fees, inventory buffering and storage costs. Do not give this case owned fleets or future infrastructure mechanics that do not yet exist.
- **Funding/timing:** the future middleman simulation must fund goods plus the purchase fee before production and receive sale proceeds less the sale fee afterward in the same resolution. Its minimum cash requirement must be measured separately from its recurring contribution.

The reusable [start file](../data/starts/pepper_valley_motors.json) currently loads the legacy simulation. It is intentionally not yet in the New Game selector: an ignored ruleset flag must not masquerade as implemented middleman service. Phase 1 adds the actual provider mode; the playable **Pepper Valley Motors** start can then expose the intended prototype. The [benchmark contract](../tests/scenarios/pepper_valley_motors_benchmark.json) records both modes and their implementation status.

## Measurement

The [runner](../tools/pepper_valley_motors_benchmark.gd) loads the real main scene and advances normal turn resolution. It checks the city, factory count, recipe quantities, actual road legs, cash reconciliation and equivalent goods values. It requires ten consecutive turns with full production, one batch of input orders, one batch of input arrivals and one batch of paid motor sales, plus stable on-hand and in-transit quantities. Startup turns cannot satisfy the steady-state comparison.

For a controlled comparison, reset goods prices/impact to the opening catalogue prices before each turn and disable research, events, decisions and public-road growth in the harness only. Existing shipment movement, congestion accounting, purchase/sale settlements, factory costs, storage, tax and scheduled cost inflation still run. Trade-volume recording is not evidence of a normal evolving-market playthrough here; the price reset deliberately removes that variable. The ordinary start has none of these harness-only controls.

By default sample no earlier than turn 40, then take ten qualifying turns. The `early` stage samples turns 10–19. Historical profiles retain their turn-31 port-rate change; the current profile uses normal ports throughout. The qualification is **steady shipment quantities**, not perfectly constant prices or costs: scheduled labour and port-cost growth can continue. Compare costs at matching sample turns and report their mean.

The direct result is real simulated cash/shipments. Until phase 1 exists, the middleman result is explicitly a **reference calculation** using the same full-batch goods values and factory costs, replacing all direct logistics costs with the selected contract’s fee (£40 currently). It does not validate new input planning, funding, save/load, middleman receipts or taxes. Operating contribution here is sales minus goods, power, labour, maintenance and logistics, before financing, taxes, dividends and capital investment. Do not describe it as post-tax cash profit.

Run from the Godot project directory:

```sh
python3 tools/run_pepper_valley_benchmark.py
python3 tools/run_pepper_valley_benchmark.py --check-baseline
```

Full trace and logs for the current road profile are written to `/tmp/pepper-valley-motors-benchmark-fee40/`. The wrapper rejects script errors even if Godot exits successfully. The historical [v2 control baseline](../tests/snapshots/pepper_valley_motors_v2.json) stores the setup, routes, startup milestones, steady window and averages. `--write-baseline` replaces the selected profile’s snapshot (v5 by default, v3 with `--balance targeted`, v2 with `--balance control`); use it only when reviewing an intentional baseline update, and introduce a new benchmark version when changing the comparison contract.

## Historical v2 results after congestion correction, before output trial

The game now counts only each shipment's traversal during that turn, preserving the full batch quantity. Same-mode leg boundaries belong to the arriving leg; mixed-mode transfers use each mode's capacity on its actual traversal. Congestion, settled tile readouts and per-good breakdowns share the calculation. Snapshot dictionaries freeze progress before movement. New saves preserve this state; obsolete whole-pipeline snapshots/history are discarded on loading older saves and rebuild with new turns. Previously charged or contracted freight is not refunded or repriced.

Actual reruns at turns 40–49, with **no price, recipe, staffing, maintenance or tariff changes**:

| Per turn | Public roads | Rail, three owned tiles | Rail, all seven owned | Middleman reference |
| --- | ---: | ---: | ---: | ---: |
| Maximum tile throughput | 94 | 94 | 94 | Not simulated |
| Congestion surcharge | £0.00 | £0.00 | £0.00 | Included |
| Player road/rail maintenance | £0.00 | £9.00 | £21.00 | Included |
| Total logistics | £55.95 | £38.41 | £50.41 | £20.00 |
| **Operating contribution** | **−£33.86** | **−£16.32** | **−£28.32** | **+£2.09** |

The former surcharge-removed road estimate is now verified by actual game code. The road pipeline still contains 376 units in total; those units are distributed along the route rather than charged to every tile. Arrival times, factory quantities and inventory buffers are unchanged. The government's four rail sections are assumed completed for the steady-state sample.

The control profile writes/checks `pepper_valley_motors_v2.json`, `pepper_valley_motors_rail_v2.json` and `pepper_valley_motors_rail_three_owned_v2.json`. It asserts zero congestion and tile flow at most 94 during the steady window, and checks saved routes, flow and economics against the baseline. The v1 snapshots below remain pre-fix evidence and are not the current expected results.

See the [balance design review](reviews/middleman-balance-design-2026-09-19.md) for the August source audit and price/output sensitivity. Its proposed balance alternatives are estimates, not deployed data changes.

## Historical v1 comparison (before congestion correction)

The controlled legacy run reproduced the following values on repeat execution. These are means over **turns 40–49**, with 30 motors produced and paid for every turn, and 32 units of each input ordered and received every turn.

| Per operating turn | Direct road/port, simulated | Middleman, reference calculation |
| --- | ---: | ---: |
| Motor sales | £331.35 | £331.35 |
| Steel and copper wiring | £238.69 | £238.69 |
| Factory power, labour and maintenance | £70.57 | £70.57 |
| All logistics | £91.36 | £20.00 |
| **Operating contribution before tax/financing** | **−£69.27** | **+£2.09** |

The reference improves recurring contribution by **£71.36 per turn**, entirely from replacing the direct logistics bill. The middleman margin is still thin; this is not evidence that the broader economy is balanced.

Direct logistics consists of £70.82 road freight including congestion, £18.35 port charges and £2.19 warehousing per turn. The catalogue selects Stoneshore port (`tile_5_10`), with four-turn road travel for both inputs and output. The road route is verified from explicit road legs, not inferred from straight-line distance. Several shared road tiles report 376 units of in-transit flow against capacity 300 under the current congestion model. This is an inflated throughput measure; see the diagnosis below. The recorded baseline preserves the observed game behaviour, including this flaw.

### Diagnosed v1 congestion accounting flaw (fixed in v2)

Steady traffic on a shared tile should be **32 steel + 32 copper wiring + 30 motors = 94 units per turn**, below the L1 road capacity of 300. `TransportState.transport_link_flow()` instead counts every pending shipment against every tile along its complete route, without considering which leg it traverses this turn. The four-turn road pipeline therefore contributes **4 × 94 = 376 units** on shared tiles. It conflates total inventory in transit with per-turn throughput. The resulting **£35.41 congestion surcharge is not justified by this factory's steady traffic**.

Subtracting only that surcharge from the recorded road result gives **£55.95 logistics and −£33.86 operating contribution per turn**. These are arithmetic adjustments, not a rerun of corrected game code. Owned rail remains at −£28.32 in the recorded run; its advantage over this adjusted road estimate is only **£5.54 per turn**, rather than £40.95. The middleman reference remains +£2.09.

Before using this benchmark to balance capacity or middleman pricing, measure each shipment's actual per-turn traversal and use that same accounting for congestion, capacity displays and history. Retain whole-pipeline inventory separately. Regression coverage should include staggered shipments on multi-turn routes, bidirectional traffic, mixed modes, and genuinely over-capacity bursts; simply dividing pipeline quantities by route duration would conceal bursts. Preserve the current snapshots as pre-fix evidence and capture new simulation results after the correction.

History checked: commit `459883a2` (27 August 2026, an ancestor of the 0.4.0 release commit `5da77646`) fixed duplicate counting of a single shipment at a boundary shared by consecutive same-mode legs. Its per-shipment `counted` guard is still present. It did not restrict a shipment to its current traversal, so the whole-pipeline problem remained. Commit `c823f4e2` (8 September) preserved settled throughput snapshots for displays/save-load; it also did not change this counting rule. The September 12 extraction into `transport_state.gd` retained the guard and whole-route calculation. The inspected history therefore shows a distinct unfixed accounting issue, not loss of the earlier boundary fix.

Starting with empty stock and no shipments, the direct factory first produces on **turn 5**, receives its first motor-sale payment on **turn 9**, and has regular shipment quantities from **turn 9**. At the end of each sampled turn it holds one input batch (32 steel + 32 wiring), has four input batches inbound (128 of each) and 120 motors outbound. These holdings are recorded separately from recurring costs; inbound goods are billed on arrival under the legacy rules.

The middleman reference needs **£248.69 for input goods plus the £10 purchase fee**, before other factory obligations. First-turn production and sales are the required future simulation behaviour, not an observed result of this run. The direct run's observed startup drawdown is recorded in the JSON; it is not a searched minimum-capital requirement, and its continuing losses consume further cash after startup.

## Historical v1 all-rail comparison and logistics components

**An owned L1 rail corridor improves the result but does not make this factory profitable:** operating contribution is **−£28.32 per turn**, against −£69.27 on public roads and +£2.09 in the middleman reference. These remain matched turns 40–49 at 30 motors per turn. The factory has only **£22.09 per turn available for logistics** after goods, power, labour and maintenance.

The [rail variant](../tests/scenarios/pepper_valley_motors_rail.json) uses a continuous shortest land corridor from `tile_5_4` through `tile_5_5`, `tile_5_6`, `tile_5_7`, `tile_5_8`, `tile_5_9` to `tile_5_10`. All seven tiles have completed, player-owned L1 `b_019` rail instances, so the real production accounting charges their maintenance. This is a direct corridor rather than a copy of the winding road route. Both imports and exports are verified to use rail exclusively and take two turns. The same NPC-owned Stoneshore port is retained; neither case owns the port or manufactures its steel/wiring inputs.

The table separates the weight/distance and cargo-value components of inland freight. Congestion is additional to those base components; it is already included in the game's road/rail subtotal and must not be added to that subtotal twice.

| Mean cost per turn | Direct: public roads | Direct: owned L1 rail | Middleman reference |
| --- | ---: | ---: | ---: |
| Warehousing | £2.19 | £2.19 | Included |
| Inland freight: weight/distance component | £14.88 | £3.72 | Included |
| Inland freight: ad valorem component | £20.53 | £5.13 | Included |
| Inland congestion surcharge | £35.41 | £0.00 | Included |
| Road/rail maintenance paid by player | £0.00 | £21.00 | Included |
| Infrastructure labour | £0.00 | £0.00 | Included |
| Flat port fee | £0.00 | £0.00 | Included |
| Port ad valorem: imports | £7.45 | £7.46 | Included |
| Port ad valorem: exports | £10.90 | £10.90 | Included |
| Other transport fees | £0.00 | £0.00 | Included |
| Middleman purchase fee | — | — | £10.00 |
| Middleman sale fee | — | — | £10.00 |
| **Total logistics** | **£91.36** | **£50.41** | **£20.00** |
| **Operating contribution before tax/financing** | **−£69.27** | **−£28.32** | **+£2.09** |

Components are rounded independently; totals use full precision. Both simulated cases have the same £331.35 receipts, £238.69 purchased materials and £70.57 factory costs (£56.47 labour, £10.50 maintenance, £3.60 power). Rail infrastructure maintenance is excluded from that common factory-cost figure and included in logistics instead.

Cost interpretation:

- **Maintenance:** the original road baseline uses existing public roads and pays no ownership upkeep. Seven owned rail instances each cost £3 per turn, totaling £21. Owned road instances would cost £1.50 each per turn; they are not part of the public-road baseline. Making the rail public would remove £21 but still leave **−£7.32 per turn** at these tariff settings.
- **Port fees:** `SEAPORT_BASE_FEE_PER_GOOD` is zero. The `port_insurance` report label is the scheduled ad valorem charge, not an extra insurance bill on top of it. At these turns the base rate is 3%, compounded by 0.1% per turn, using the goods' buy-price value for both directions. No port-capacity surcharge occurs at this throughput. Imports settle their previously quoted port charge on arrival, so two-turn rail imports carry a slightly newer/higher quote than four-turn road imports in the same cash-report window.
- **Warehousing:** both cases retain one full input batch after production (32 steel and 32 wiring), hence the same £2.19 recurring storage bill. Rail halves the inbound/outbound pipeline quantities to 64 of each input and 60 motors, but that transit reduction does not reduce the on-tile storage bill. Current storage uses the legacy tile capacity and per-unit tariff; there is no additional owned warehouse-building maintenance in either run.
- **Freight:** the existing tariff has a weight-class component and a separate cargo-value component per route leg. Rail's 0.5 mode multiplier and two-turn journey reduce both to one quarter of the four-turn road base cost. Road congestion doubles the base freight here; the rail route remains below its capacity and has no congestion surcharge.
- **Scope:** the current game does not run the proposed owned-fleet equipment/fuel/crew system. Do not invent extra locomotive fuel, crew or vehicle-maintenance debits in this comparison. Rail construction, land acquisition, financing, depreciation and capital payback are excluded; rail assets are seeded as already built. The recurring rail loss therefore cannot be rescued by including construction costs.

The [component results](../tests/snapshots/pepper_valley_motors_transport_costs_v1.json) and [rail baseline](../tests/snapshots/pepper_valley_motors_rail_v1.json) are retained separately from the original road baseline. Both actual simulation totals reconcile to their components. The road replay verifies that its original economics and routes are unchanged.

```sh
python3 tools/run_pepper_valley_benchmark.py --check-baseline
python3 tools/run_pepper_valley_benchmark.py --route rail --check-baseline
```

Rail output is written to `/tmp/pepper-valley-motors-benchmark-rail/`. `--route rail --write-baseline` now updates only the selected balance profile’s rail snapshot (v5 by default). Production starts on turn 3 and the first sale payment arrives on turn 5, versus turns 5 and 9 for roads. The middleman remains a reference calculation, not a third simulated run.

## Historical v1 three player-owned rail tiles, remainder government-built

This is the requested ongoing ownership assumption: the player maintains only `tile_5_4`, `tile_5_5` and `tile_5_6`; the remaining four tiles on the same continuous rail corridor are public. All seven have completed L1 rail, but only the three player sections have owned building instances and maintenance charges. The benchmark measures steady state after government construction has completed; it does not simulate the government's gradual construction schedule. Roads remain public, with zero player maintenance.

The real simulation settles into the same turn 40–49 sample with **£9 rail maintenance, £38.41 total logistics and −£16.32 operating contribution per turn**. Reducing ownership from seven to three tiles saves exactly £12 per turn. The factory still has only £22.09 available for logistics before these charges.

| Mean cost per turn | Public roads, simulated | Public roads, surcharge removed estimate | Rail, three owned tiles, simulated | Middleman reference |
| --- | ---: | ---: | ---: | ---: |
| Warehousing | £2.19 | £2.19 | £2.19 | Included |
| Inland weight/distance | £14.88 | £14.88 | £3.72 | Included |
| Inland ad valorem | £20.53 | £20.53 | £5.13 | Included |
| Congestion surcharge | £35.41 | £0.00 | £0.00 | Included |
| Player infrastructure maintenance | £0.00 | £0.00 | £9.00 | Included |
| Port import ad valorem | £7.45 | £7.45 | £7.46 | Included |
| Port export ad valorem | £10.90 | £10.90 | £10.90 | Included |
| Flat port fees, infrastructure labour, other transport fees | £0.00 | £0.00 | £0.00 | Included |
| Middleman fees | — | — | — | £20.00 |
| **Total logistics** | **£91.36** | **£55.95** | **£38.41** | **£20.00** |
| **Operating contribution before tax/financing** | **−£69.27** | **−£33.86** | **−£16.32** | **+£2.09** |

The rail case improves contribution by £17.54 against the road estimate without the erroneous congestion surcharge, or £52.95 against the current game road result. The middleman remains arithmetic only. Original all-owned rail and road snapshots are preserved; the new [three-owned-rail scenario](../tests/scenarios/pepper_valley_motors_rail_three_owned.json) and [simulation baseline](../tests/snapshots/pepper_valley_motors_rail_three_owned_v1.json) are separate.

```sh
python3 tools/run_pepper_valley_benchmark.py --route rail-three-owned --check-baseline
```

## Future phase gates

1. Run an actual middleman ruleset from the same start, and measure its own quantities, bills, cash and holdings. Keep the reference arithmetic as an independent expected-result check.
2. Verify one £16 purchase charge for both ingredients together, one £16 sale charge and one £8 storage charge per factory turn using provider storage. An absent purchase/sale direction has no corresponding charge; split calls must not multiply fees. Reserve input goods plus £24 before production; deduct £16 from sales afterward.
3. Verify a complete funded cycle from empty stock, no owned transport/storage requirement, no legacy charges and no duplicate trade/production cycle. Test cash below the input-basket requirement separately.
4. Reuse the benchmark after warehouse, road fleet, rail, port and pipeline work; add explicit variants rather than mutating v1. Compare total operating cost and working capital, including new fixed costs, at matched throughput.
5. Retain a separate evolving-market playthrough to assess real startup survival, price impact, borrowing and balance. The controlled benchmark isolates logistics; it does not replace that trial.
