# Upcoming extra costs — shared scope and startup attribution

The notice, Balance/Treasury links and Upcoming tab now use the same exceptional-cost calculation. It includes pending construction/upgrade material bills, projected material purchases and the starting building's share of initial input purchases. Known arrival bills remain included until paid, with payment timing displayed in the detail rows. Routine orders, labour, maintenance, standing purchases and loan/building-credit instalments are excluded from this UI; their accounting is unchanged.

Removed the last-turn order-history heuristic: an intermittent refill is not a startup. Construction completion, a real pause/resume transition and retrofit completion set an optional `startup_inputs_pending` building field. It clears on the first actual production turn. Authored starts and legacy saves default to false. The existing dictionary serialization preserves it. Forecasts project this state without mutating the sim. Shared input orders use the existing allocator's optional attribution trace, and a `startup_input_share` shipment tag preserves only the exceptional portion of unpaid freight. Financing-clipped orders retain the same proportion. No prices, quantities, routing or payment timing were changed.

The build confirmation's planning block now contains two elements: recommended buffer purpose, then amount. Buffer = material purchases payable on arrival + the existing pre-revenue operating buffer estimate, excluding unrelated company bills and repayments. Immediate construction charges remain in the existing build quote.

## Verification

- Parse: 609 scripts, zero failures, 47 established skips.
- Full suite: 407 tests, 3967 assertions passed.
- Unchanged Metal Magnate and Glass Merchant: notice and panel totals both £0 across all 12 turns each.
- Windowed real UI: initial panel/link £0, no zero-cost warning; construction scenario reconciled at £89.28 (£27.50 booked materials + £61.78 initial inputs). Actual next-turn orders and booked payments matched the underlying forecast across the six-turn trial. Both links navigate to Upcoming. Build buffer has only purpose and amount. Screenshots inspected.
- 100-turn E2E: 723 assertions passed; final economic results unchanged from the prior run.
- Known existing shutdown resource-leak warnings remain.

Evidence: `outputs/extra-costs-2026-09-13/`. Exports not rebuilt.
