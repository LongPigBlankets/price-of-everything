# Stockpile guidance and upcoming payments — 12 September 2026

## Implemented

- Redirecting output to a tile offers per-good surplus selling when the current routing/recipe estimate indicates accumulation. Explicit split quantities, automatic splits, capped remote deliveries and recurring onward orders are included. Split-route prompts are presented sequentially.
- Accepting enables the existing per-good policy. It does not enable sales for every good. The normal selling phase protects production inputs, awaiting construction requirements and the player's keep quantity; the reserve updates as consumers change. Existing excess is eligible too, and normal sale limits still apply. It is a standing policy, not a fixed recurring sale of today's estimated surplus.
- The grey Other goods bar opens an adjacent all-goods drawer aligned to the tile panel's height and vertical position. Every entry uses the existing Move/Sell controls, with those controls brought into view after selection. The drawer refreshes with the stockpane and closes when switching tiles/tabs or dismissing it.
- A clickable notice beneath Stockpiles & shipments opens the affected tile and selects its good. It requires actual stock and unreserved surplus to increase across three consecutive observed turns. Filling the protected reserve alone does not trigger it. One notice per turn, with an eight-turn cooldown per tile/good; explicitly keeping stock also suppresses reminders for eight turns. If selling is already enabled, the notice suggests checking sales rather than enabling it again.
- Guidance history resets on new games and loading. It is session guidance, not saved economic state. Tutorial and turn-resolution flows do not open route prompts. Projections describe current output, not guaranteed production or delivery.

## Upcoming payments: original proposal

A subsequent approved trial is now implemented. See [the implementation and actuals review](cash-commitments-trial-2026-09-12.md) for its delivered scope and limits. The proposal below records the broader design.

Use three distinct groups in the money panel. A purchase order is not necessarily a cash payment on the next turn.

| Group | Include | Certainty |
| --- | --- | --- |
| Payments due | Unpaid shipments scheduled to arrive; bank instalments; building-credit instalments already in repayment | Amount is known from the order or repayment schedule. Arrival timing follows the displayed ETA. |
| Likely new orders | Automatic input replenishment, player-set recurring purchases, construction material shortfalls/reorders | Quantities depend on stock, deliveries, production, warehouse space, access and purchase headroom. Quote at current prices and show expected payment/arrival turn. |
| Expected running costs | Labour, maintenance, advisor payroll, storage, grid purchases, currently applicable taxes and announced policy changes | Estimates; several depend on activity, revenue, stock peaks or consumption. Show assumptions and separate them from booked bills. |

Highlight a building that is expected to start ordering next turn after needing no order this turn, but retain all expected orders in the total. Otherwise a player could mistake an incremental warning for their complete budget.

### What the current simulation supports

1. **Purchased goods and freight in transit.** `TransportState.pending_transport_shipments` stores `purchase_cost`, `purchase_goods_cost` and `turns_remaining`. `Production._process_transport_arrivals()` settles the full bill on first arrival, even if warehouse capacity prevents unloading. Held overflow is already paid; do not charge it again. `purchase_cost` already includes freight. Old-save shipments with no unpaid cost must not be repriced. Zero-turn purchases settle immediately in `MatchState.queue_buy()`.
2. **Construction and upgrades.** Separate amounts already paid when confirming from unpaid materials en route and material shortfalls not ordered yet. `Construction.reorder_market_materials()` accounts for project-tagged inbound and held freight. Reuse this ownership distinction: materials reserved for one project cannot also cover a factory or another project. Reuse construction quotes for the additional proposed project, but never add the whole construction price again after it was charged.
3. **Bank and building credit.** `LoanState.process_payments()` and `MatchState.tick_building_tabs()` define the schedule. Grace expiry can change debt without a cash payment on that same turn. Building tabs can continue accruing before repayment, so future instalments during that window remain estimates. Honour the chosen slices/loan mode; a conversion must not appear as both an immediate bill and a loan repayment.
4. **Automatic inputs.** `Production._buy_market_inputs()` nets same-tile supply, scaled recipe demand, ordinary inbound, overflow and inventory against a lead-time pipeline. Forecast by tile/good, with building attribution, rather than independently summing each building's order. Two factories can share stock. Warehouse capacity clips requested quantities, and `MatchState.queue_buy()` further clips to financeable headroom and checks import restrictions/access. Keep desired orders and affordable orders distinguishable so a funding shortfall does not make the forecast look cheap.
5. **Standing purchases and moves.** `MatchState.recurring_buys` are processed explicitly at the end of input buying. Include them, and include applicable freight for standing moves. Avoid re-adding freight embedded in an existing purchase bill.
6. **Ongoing costs and announced changes.** Maintenance/labour, advisor pay and warehousing are charged in Production; advisor pay can depend on revenue and storage uses the turn's high-water marks. Grid purchases, carbon tax, company tax, dividends and profit sharing are activity-dependent estimates. Only use policy dates/rates already disclosed to this player, not a lookup of next turn's hidden policy schedule. Subsidies belong on the receipt side, not as negative committed bills.

### Preview calculation

Extract a read-only order planner shared with the buying phase; do not invoke the mutating buy routine for a preview. Run it over a copied, player-visible snapshot in the real phase order: arrivals, material claims/completions, ordinary replenishment and standing orders. Preserve warehouse reservations, allocation order and financial headroom. A building likely to complete and start buying can be flagged using its visible materials/ETA/progress, with uncertainty when supplies are missing. The current recipe/output display alone is insufficient to predict this.

Return rows with source ID, tile/good, quantity, amount, order turn, payment turn, certainty, reason and included-freight information. Stable source IDs let the UI group the same unpaid order under a project without counting it twice. Regression tests should cover shared stock, project-reserved freight, full warehouses, grace expiry, zero-turn delivery and low purchase headroom.

Do not advance the live simulation, consume randomness or inspect unrevealed events to calculate the preview. Exclude unchosen decisions, future fines/opportunities, unrevealed policy changes and speculative market prices. Publicly visible receipts can appear separately, but are not needed to show the committed-payment total.

### Fit with the current demo UI

`BuildForecastTable.show_balance_impact()` hides the detailed balance/runway forecast in `demo_itch`; the construction panel retains the payback summary. Add a compact payment summary alongside that existing summary rather than requiring the full runway table:

- **Pay now** — additional immediate cash cost of this build.
- **Materials still payable** — additional unpaid material orders and their expected arrival/payment turns.
- **Already committed over this period** — existing bills and repayments, without the new build.
- **Expected costs before first sales arrive** — input orders and operating costs, explicitly estimated.

In the money panel, lead with **Payments due next turn**, then **Likely orders next turn** with a “payment expected” column, then expandable **Expected running costs**. Show current cash beside the committed subtotal. If an expected cash balance is displayed, show the assumed receipts and estimates used; subtracting commitments alone is not a complete cash forecast.

Suggested warning: “This factory is expected to order [quantity] [good] next turn. At today's prices, the goods and freight would cost about [amount], payable on arrival in [N] turns.” For an already placed order: “[Amount] due next turn for [quantity] [good] arriving at [tile].”

## Verification commands

Verified on this change: parse sweep 602 scripts / 0 failures; full unit suite 3,902 assertions passed / 0 failed; 100-turn E2E 723 assertions passed / 0 failed; windowed drawer/prompt/notice harness 12 checks passed. Screenshots and logs are in repository-root `outputs/stockpile-guidance-2026-09-12/`. Existing test harnesses still emit cleanup/resource warnings at exit.

From the Godot project directory, run serially:

```sh
"/Users/crisu/Desktop/Godot.app/Contents/MacOS/Godot" --headless --path . res://tools/parse_check.tscn --quit-after 600
python3 tools/run_tests.py
"/Users/crisu/Desktop/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/e2e_stoneshore.tscn -- 100
"/Users/crisu/Desktop/Godot.app/Contents/MacOS/Godot" --path . res://tools/stockpile_guidance_check.tscn -- --no-telemetry
```

The windowed harness stages disposable stock and takes screenshots in `/tmp/cnc-stockpile-ui`. The explicit telemetry opt-out prevents the harness from adding a launch to player analytics.
