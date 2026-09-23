# Upcoming payments trial — 12 September 2026

Implemented in the game as a trial, with automatic forecast/actual comparisons after each resolved turn. No balance constants or save schema changed.

## Where it appears

- Treasury flyout and default Balance tab: a white **Upcoming costs next turn: ≈ £X** row opens **Upcoming**.
- Money panel: **Upcoming** tab with a prominent next-turn subtotal, a proportional category strip, payment-timing bars, and expandable cards for booked bills, expected orders with goods icons, running costs and assumptions. The previous turn's forecast/actual comparison uses labelled paired bars.
- Construction confirmation, including the itch demo: **Payments to plan for**, showing the additional immediate spend, materials payable on arrival, existing next-turn commitments, and the existing operating-buffer estimate. Uses the selected materials ledger, with freight included.

## How the trial works

`cash_commitments.gd` reads a snapshot of current public state. It projects incoming stock, construction material claims, buildings due to complete, input consumption, routed outputs and ordinary replenishment. Normal production and the preview share the pure building-first allocation routine in `input_order_planner.gd`; shared stock is not independently allocated in full to each factory.

Known shipments keep the quoted bill they were ordered with. Already-paid overflow and old-save shipments without an unpaid bill are excluded. Existing bank and building-credit instalments are counted separately. Loan grace expiry does not invent a same-turn cash payment. Future loan instalments are displayed separately by their first payment date.

The snapshot taken at the start of PROCESS is compared with actual queued purchase quantities/costs and actual bill/repayment settlements. The record is session-only and clears on new game/load. The panel does not claim that the selected payment categories equal the total change in cash.

The white row and hero card share a subtotal: booked payments due next turn, estimated new orders payable next turn, and gross labour/maintenance. Orders payable later are excluded from that subtotal and appear on their expected payment date. The timeline's later dates include only listed bills/orders, not recurring projections. Exclusions and building-credit treatment remain visible beneath the summary.

Quotes are at current prices. New order rows say when payment is expected, including orders that settle immediately during the next turn. Buildings/goods starting to order after no order in the previous recorded turn are highlighted. Wanted quantities remain visible when the estimated order is limited.

## Actual comparison

A disposable Metal Magnate game was run for six turns. The first two used its starting position. Before the third, the harness added funds and staged a construction completion, a quoted £27.50 material shipment arriving next turn, a £100 loan repaying £11 per turn, and a recurring ore purchase. This is a controlled mechanics trial, not a replay of the player's turn-24 save.

| Turn | Booked payments: forecast / actual | New-order cost: forecast / actual |
| --- | --- | --- |
| 1 | £0.00 / £0.00 | £0.00 / £0.00 |
| 2 | £0.00 / £0.00 | £0.00 / £0.00 |
| 3 | £38.50 / £38.50 | £64.76 / £64.76 |
| 4 | £11.00 / £11.00 | £46.69 / £46.69 |
| 5 | £11.00 / £11.00 | £54.18 / £54.18 |
| 6 | £11.00 / £11.00 | £57.77 / £57.77 |

All six turns matched new-order quantities by tile/good, quoted order totals, booked payments, maintenance and labour in this scenario. The preview took roughly 0.7–1.2 ms in this small company. A before/after state comparison covers match state (including RNG), stockpiles and the market; the preview leaves these unchanged.

The read-only check caught an existing issue: `TransportState.preview_sea_shipping()` rotated the saved port ledger when asked for a new-turn quote. Previewing now reads new-turn usage without altering the ledger; committing an actual shipment performs the rotation. A regression test checks both immutability and quote/commit price agreement.

## Bounds of this version

This is a one-turn commitments estimate, not a complete cash-flow predictor. It does not price unrevealed events or decisions, predict market movement, or promise future revenue. Power, storage, advisor pay and taxes are called out as additional activity-dependent costs, not folded into a falsely exact total. Labour/maintenance estimates are gross, before any building-credit refund.

Order estimates model ordinary current-recipe operation, visible construction completion and production upgrade/retrofit completion. More complex cases can differ: JIT direct-feed buffers, cascade/power constraints, demolition refunds, interrupted logistics, standing bulk sales, stalled-upgrade reorders, and future port congestion. Low funding can also change actual order quantities because other transactions occur before buying. The comparison exposes discrepancies instead of presenting estimates as commitments. The six-turn match does not establish accuracy for all these situations.

The existing build operating-buffer estimate is retained and labelled; this trial checks the following turn, not that buffer against the entire construction-to-first-revenue interval.

## Reproduce

Run from the Godot project directory, serially:

```sh
"/Users/crisu/Desktop/Godot.app/Contents/MacOS/Godot" --path . res://tools/commitments_trial.tscn -- --no-telemetry
```

Headless mode runs the same comparisons without screenshots. Files are written to `/tmp/cnc-commitments-trial`; the retained copies live in repository-root `outputs/cash-commitments-trial-2026-09-12/`.

The test harness uses disposable runtime paths and disables telemetry. UI captures dismiss the start-introduction overlay and hide transient map-sale glyphs so the financial text is readable.

## Regression checks

- All-script parse sweep: 607 scripts, zero failures.
- Full unit suite after the visual update: 400 tests, 3,914 assertions passed, zero failures and no GDScript runtime errors. Existing test cleanup/resource warnings remain.
- 100-turn E2E: 723 assertions passed, zero failures. Ending cash, cumulative revenue/profit, building count and pending shipments exactly match the preceding stockpile-change run.
- Windowed six-turn trial: payment amounts, order quantities/costs and maintenance compared to actuals; match/RNG, stockpile and market state unchanged by preview. Screenshots inspected for both money and demo construction panels.
- Visual update screenshots and logs: repository-root `outputs/upcoming-payments-design-2026-09-12/`. The windowed harness also checks the Balance and Treasury navigation links.
