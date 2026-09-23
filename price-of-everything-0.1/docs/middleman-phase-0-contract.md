# Middleman phase 0 — implementation contract

Historical phase-0 record. [Phase 1 is now implemented and separately validated](middleman-phase-1-implementation.md).

Date: 2026-09-19. Branch: `codex/transport-middleman-layer`.

Phase 0 freezes the service contract and reference evidence. `scripts/middleman_contract.gd` implements pure quotes and complete-batch funding plans. It is not an autoload and does not execute trades or alter production. Live acquisition, holdings, production, sale settlement and save integration belong to phase 1.

The machine-readable authority is [middleman_phase0_contract.json](../tests/scenarios/middleman_phase0_contract.json). The [selected logistics hub design](logistics-hub-design.md) is parked for later phases.

## Confirmed economic and failure rules

Each building independently buys and sells through the market. No same-tile sharing, netting, shared hidden warehouse or physical provider shipment is created. The inclusive service fee covers transport and operating storage; goods and factory costs remain separate.

For each traded unit, charge `0.005 × reference price + class rate × location coefficient`. The current class rates are £0.025 light solid, £0.08 solid-heavy, £0.60 ultra-heavy, £0.08 safe liquid, £0.15 hazardous liquid and £0.20 gas before the location factor. Pepper Valley uses the explicitly authored factor 1.5. Prototype eligibility is steel, copper wiring and motors only. Other goods and unauthored locations must report an unsupported reason, never silently receive free service.

Snapshot `MarketState.get_price()` including current impact/carbon as the fee reference, before purchase markup. Purchase and sale goods prices come from the ordinary `get_buy_price()` and `get_sale_price()` APIs. Capture all prices before service trades mutate market volume. Canonicalize quantities by good and retain float ledger precision; rounding is for display only.

Funding uses cash and explicitly drawn permitted standard loans, never anticipated sales. First protect residual due obligations and unpaid commitments, then allocate in stable building creation order with immutable instance ID as tie breaker. Reserve a complete recipe basket plus input service fee, labour, maintenance and predicted grid expense. Reuse that building's paid inputs before buying the shortfall. Known infeasibility or insufficient funding rejects the whole batch without purchases, fees, volume or borrowing.

A standard loan must respect available capacity and the existing £20 minimum. Its existing repayment tick, interest and grace schedule remain the same as a loan drawn during DECIDE. Financing is not operating revenue. Initial service eligibility excludes building credit tabs until their synthetic refund path is explicitly integrated.

Unexpected failure after acquisition retains the paid ingredients and purchase receipt privately for that building. Retry uses them without another acquisition fee. This is bounded to one unfinished cycle, not unlimited storage. Disabled buildings retain holdings without recurring service charges. Recipe changes or final removal require explicit disposition of paid holdings. Unsold output is similarly bounded to one cycle and blocks further production; negative-net automatic sales are rejected rather than silently disposing of goods.

## Turn and ownership contract

Keep `DECIDE → PROCESS → SEND → AI → NARRATIVE → RECEIVE → DECIDE` and existing public signals. Within PROCESS, call these stages directly in order:

1. Advance existing physical shipments once; settle arrivals and construction claims.
2. Snapshot eligible building modes, recipe requirements, prices and known feasibility.
3. Reserve obligations and complete batches; explicitly draw required permitted loans.
4. Acquire building-private inputs and record purchase, input fee and market volume once.
5. Run the existing bounded power/production cascade, at most once per building.
6. Settle actual provider output and output fee; dispatch new physical shipments without advancing them.
7. Complete existing expenses, loan payments, tax and reporting with one inclusive service fee total.

Sales cannot reopen planning or finance another cycle in that resolution. Power remains the existing grid dependency, not a traded service ingredient. Preserve the bounded cascade so a funded power producer can enable its consumer.

`Production._process_production()` is the integration seam. Its old `_buy_market_inputs()` replenisher must skip covered buildings. Market-bound output currently can sell during the cascade; intercept that path as well as the later stockpile sale block. Private holdings must never enter shared stock, tile capacity, ordinary warehousing bills or direct-building input pools.

`MatchState.queue_buy()` and `MarketState.execute_sale()` currently combine market and physical-logistics effects. Extract/reuse their price, policy and volume operations through explicit service-aware settlement boundaries. Calling them with zero ETA does not implement the agreed service.

## Durable identity and save boundary

Operation identity is the JSON tuple `[persistent match ID, resolution turn, immutable building instance ID]`. Recipe revision belongs in its immutable payload, not its identity. Persist separate acquisition, input-fee, consumed, produced, sale and output-fee receipts. Same ID and same payload returns the prior result; a conflicting payload rejects. Quotes never mutate state.

Lifecycle: planned → funded → supplied → consumed → produced → settled. Failures distinguish rejection before supply, blocked private inputs and blocked private output. A retry references the retained acquisition receipt, not a fresh purchase of those goods.

Phase 1 will put schema-1 `middleman_service` under MatchState's existing SaveLoad ownership. Persist building modes, tariff/price snapshots, private holdings and settlement receipts. Save only at the established DECIDE boundary. Missing payload means no active provider service, even for older `middleman_v1` saves whose flag only selected port rates. Missing logistics ruleset remains legacy. Phase 0 does not change save version 11.

The [holding fixture](../tests/scenarios/middleman_phase0_holding_fixture.json) demonstrates the proposed payload and serialization. It is not a complete playable save. Existing `test_save_load.gd` exercises actual whole-save round trips and generates/loads a legacy version-1 fixture through migration. Live middleman save/replay tests are required in phase 1.

## Evidence and reproducible gate

Run `python3 tools/run_middleman_phase0.py --full` from the project directory. The runner checks baseline SHA256s, the complete unit suite and real road, three-owned-rail and five-factory baseline replays. Without `--full` it runs the focused contract suite. The full suite writes temporary save fixtures through Godot's normal test paths and therefore needs access to those directories.

- [Baseline manifest](../tests/scenarios/middleman_phase0_baseline_manifest.json): retained direct-run snapshots and goods/recipe catalogue hashes. Phase 0 does not rebalance them.
- [Reference fixture](../tests/snapshots/middleman_phase0_reference_v1.json): controlled motor buy/sell quotes and expected cash trace under the current schedule. Input fee £8.81664; output fee £31.5224415; total £40.3390815. Its startup reserve uses a steady-state mean operating cost, not a measured actual turn-one minimum.
- `tests/unit/test_middleman_contract.gd`: 48 focused checks across eight tests for purity, pricing, split invariance, complete-batch funding, minimum loan, private-input reuse, identity and fixture consistency.
- Existing save tests cover actual legacy migration and whole-save round trips. Proposed private payload serialization alone does not prove runtime settlement idempotency.

Cash invariant: opening cash + receipts + financing − purchases − service fees − operating expenses − financing outflows = closing cash. Goods invariant: opening + acquisition + production = consumption + disposal + closing, with each unit owned exactly once across private holdings, shared stock and transit.

## Phase-1 integration acceptance matrix

These are required future integration tests, not phase-0 passing gameplay claims.

| Case | Required result through the normal turn path |
| --- | --- |
| Zero-stock inland motor factory, no road | Fund, purchase 32 steel/32 wire, consume 30 grid power, produce/sell 33 motors once; reconcile cash and fees. |
| Two same-tile outsourced buildings | Independent purchases/sales; no private-input sharing or intermediate netting. |
| Below/exact batch funding and limited credit | Reject without mutation or accept a complete batch; reserve running obligations; respect minimum loan and stable allocation. |
| Known missing power versus unexpected production failure | Known impossibility buys nothing; post-purchase failure retains paid inputs; retry buys only missing goods and never recharges retained goods. |
| Power supplier plus consumer | Existing bounded dependency cascade works; consumer cannot run twice. |
| Existing arrivals and construction completion | Existing obligations retain precedence; no goods/claims lost; service avoids physical transport effects. |
| New physical shipments | No extra movement caused by internal PROCESS reordering; ordinary replenishment still works for direct buildings. |
| Sales, taxes and accounting | Actual output only, no planning re-entry, no double fee/market impact; loan draws excluded from operating revenue. |
| Blocked/negative-net output sale | Preserve bounded output, expose reason, stop further accumulation; retry settles once. |
| Disable/change/remove with private assets | Retain ownership or require explicit disposition; no silent deletion/refund. |
| Save/reload and duplicate callbacks | Persist private goods and receipts; cannot repeat acquisition, consumption, sale, fee or volume. |
| Legacy/tutorial/old port-only flag | Existing stocks, prices, shipments and modes remain unchanged; no automatic service activation. |
| Headless versus windowed | Same funding, loan aging, settlement and resolution callback results. |

All-goods tariffs, city classification, public start selection, manual speculation, construction-service redesign, owned warehouses and hubs remain outside this phase.
