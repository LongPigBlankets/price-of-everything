# Phase 3 — building logistics and shared storage

Implemented on `codex/transport-middleman-layer`, 19 September 2026.

## Controls

Building details expose independent Inputs and Outputs controls directly below the recipe. An intermediary side shows a compact **Manage Logistics** button with a cream truck to its left; a managed side shows the regular routing card. Both selectors include **Logistics Intermediary** alongside ordinary sources/destinations. Choosing an ordinary route first confirms the supplier change, then applies that route only if the mode transition succeeds. The warning reads: “Are you sure you want to change your transport supplier? This will incur costs and require you to sell to the global market via a port.” **Do not show again** suppresses future supplier warnings across buildings for the current session, consistent with other routing prompts; cancellation or a rejected transition does not save that preference. Returning to the intermediary is immediate. **Logistics costs & funding** opens the common overview with estimates and private holdings. Managed routes use generic carriers.

Managed inputs can use automatic supply with market fallback, this tile's shared stock only, or a specified owned tile stockpile. A remote source creates a standing physical delivery for one recipe's input requirement each turn, scaled with building level and operating modifiers. It has normal freight and transit time, shares inventory on arrival, and has no automatic market fallback. Switching back to intermediary inputs pauses future source deliveries; existing shipments continue unchanged. Choosing another source replaces only that building/input's standing order.

Managed output can stay on the tile, ship to another tile (including existing split routes), or sell through the market/port. Taking control of outputs defaults to local retention, so the switch does not silently sell production. Existing route controls handle subsequent choices.

The tile header's truck button opens **Tile logistics and warehousing**: owned usage/capacity, estimated storage cost at current holdings, links to each building's modes, and the existing warehouse expansion/surplus controls. The top-bar Transport panel lists building modes with navigation links alongside stockpiles, infrastructure and shipments. Building changes remain explicit; no automatic tile-wide mode switch is introduced.

## Inventory and accounting

Private intermediary holdings remain separate from shared tile stock. Managed consumers use the existing stock/feed allocation and surplus reservations. Their input requirements count toward tile reserves; intermediary input requirements do not. Producers selling through the intermediary cannot masquerade as local suppliers. Empire endpoints and input/output connections follow each side independently.

Storage reuses existing 800/1,600/2,500-unit warehouse levels, expansion costs, per-good storage charges and overflow handling. There is no separate middleman warehouse toggle. Switching a side to managed releases only that side's already-paid holdings, atomically and only if all units fit. It neither refunds nor sells goods. Other private holdings and existing physical shipments are untouched.

Middleman fees apply only to the selected sides. Managed freight and owned warehousing remain separate charges. The remote-source acceptance run also exposed an existing reporting omission: recurring/scheduled movement freight was deducted from cash but absent from production accounts. Production now records the returned movement costs and transport breakdown before calculating profit/taxes; it does not debit cash again.

The turn sequence is unchanged. Without JIT, newly retained local outputs become available next turn. Existing JIT behavior remains research-dependent. Each service input batch is funded before production; expected sales never fund the same purchase. Ordinary managed procurement retains its established funding rules.

Save format **13** protects the new side modes from older clients. Version-12 middleman buildings migrate to both sides covered; saves without service data remain direct. Mixed modes, private goods, shared stock and remote source orders survive save/load. Recipe changes require both sides managed first, avoiding an unsupported service contract after retooling.

## Scope and tariff

The service now supports the five benchmark recipes—motors, steel, copper wiring, copper ingots and iron ingots—on Pepper Valley (`tile_5_4`, coefficient 1.5) and Pepper Valley Farmlands (`tile_6_4`, coefficient 1.75). All eight involved material goods use the already-selected heavy/ultra-heavy tariff. Other goods, locations and unpriced cargo classes remain outside this experimental rollout.

No recipe quantities, prices, middleman rates, generic carrier rates, warehouse capacities or construction kits were rebalanced. New eligible construction in the Pepper start joins both service sides on completion, after ordinary material delivery.

## Acceptance evidence

```sh
python3 tools/run_middleman_phase3.py --full
```

This runs the full unit suite and preserved P0–P2 controls, then real 60-turn chain scenarios. Scenarios use controlled market prices, no mines, no JIT/research/events, and ample working capital to isolate recurring economics; they are not startup-capital or payback claims. Each checks cash reconciliation, full production at turns 40–49, and save/reload at turn 30. All-middleman cases additionally check independent purchases and absence of shared provider stock. A seventh case explicitly tests remote-stockpile source orders.

Mean operating contribution per turn (sales minus goods, transport including middleman, storage, labour, upkeep and purchased power; before company taxes/financing):

| Chain | Both sides middleman | Fully managed, generic carriers | Managed inputs; middleman motor sales |
|---|---:|---:|---:|
| Motors + steel, one tile | £27.62 | £6.67 | £14.58 |
| Five factories, two tiles | £46.80 | £54.08 | £62.00 |

In the mixed comparison, upstream buildings use managed logistics and only the motor factory sells via the middleman. Intermediate production reaches shared stock; existing surplus rules handle exports. This demonstrates a useful intermediate integration choice without changing balance.

The full suite passes **4,376 checks**. The remote-source scenario also passes windowed with the same operating averages as headless.

Regression tests cover side-specific fees, no duplicate purchases, retained outputs earning no revenue, warehouse-full switch rejection, one-sided release, pipeline preservation, remote order scaling/pausing, save migration and separate graph endpoints. Windowed screenshots verify the building overview, private/managed input sheets, tile dialog and top-bar overview (`tools/middleman_p2_preview.tscn -- --no-telemetry --p3`).

Detailed actual-turn evidence: `reports/balance/middleman_phase3_chains_2026-09-19.json`. Earlier controlled benchmarks remain unchanged.

## Next phase

P4 introduces owned logistics hubs, their coverage, installed equipment, LC workload and running consumption. P3 does not activate the parked hub model or invent rates for additional cargo classes.

UI refinement verification: 532 assertions passed across the middleman-tagged tests. The windowed preview checks independent controls, cancelling and confirming a supplier change, session warning suppression, returning to the intermediary, and applying the selected market route after switching.
