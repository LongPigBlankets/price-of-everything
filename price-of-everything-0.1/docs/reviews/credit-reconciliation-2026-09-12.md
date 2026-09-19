# Building-credit cash reconciliation — 12 September 2026

Treasury now shows the building-credit deferral that Balance already included. Balance and Treasury also show actual building-credit repayments and cash disbursed by the existing credit-to-loan conversion. The top bar and its runway calculation use the same corrected cash movement. Loan instalments are labelled **Loan repayments**, and the main cash change is labelled **last turn** rather than **per turn**.

`MatchState.tick_building_tabs()` now returns gross repayments and loan proceeds separately. A simultaneous loan conversion and repayment can no longer cancel each other inside a single net repayment value. The underlying transactions, repayment timing and amounts are unchanged. Production publishes those two amounts separately, and `Production.cash_change_of()` adds their net effect for the cash UI. The existing `money_in`/`money_out` basis remains unchanged for tax, dividends, research and other economic consumers. No balance constants or saved-state schema changed.

## Controlled real-turn trial

The harness runs the actual Metal Magnate game for six turns. Before turn 3 it stages a £120 tab paying three £40 slices, an active building with two credit-window turns left, and a £90 tab converting to a loan after three turns. Existing construction/arrival/loan/recurring-order checks remain enabled. The production-completed callback measures actual treasury movement independently of the summary calculation. A rendered Treasury check also sums the individual visible cash rows.

| Turn | Deferred onto credit | Credit repaid | Conversion loan received | Actual cash change | Balance / Treasury |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | £0.00 | £0.00 | £0.00 | £56.21 | £56.21 |
| 2 | £0.00 | £0.00 | £0.00 | £58.62 | £58.62 |
| 3 | £14.47 | £40.00 | £0.00 | £-57.82 | £-57.82 |
| 4 | £13.12 | £40.00 | £0.00 | £44.62 | £44.62 |
| 5 | £0.00 | £42.30 | £90.00 | £119.01 | £119.01 |
| 6 | £0.00 | £2.30 | £0.00 | £66.52 | £66.52 |

All six turns matched to under one penny. The rendered Balance and Treasury screenshots show both deferral and repayment on turn 3. A unit test separately verifies that window expiry does not charge a slice early, conversion closes the old tab, and the first slice starts on the following turn.

## Scope

This is reconciliation of the last production settlement. Transactions between turns and later event-phase cash changes are still separate; the cash-change tooltip states that scope. The new Upcoming estimate remains gross before building credit and does not yet forecast every running cost. This change does not claim to complete a full opening-to-closing ledger for every phase.

The existing credit-to-loan conversion disburses principal into cash; this update reports that behaviour without changing it. Whether conversion should instead refinance debt without disbursing extra cash is a separate mechanics decision.

## Verification

- All-script parse sweep: 607 scripts, zero failures.
- Windowed six-turn trial: zero failures; displayed Treasury rows sum to the reported cash change.
- Full unit suite: 401 tests / 3,923 assertions passed, zero failures.
- 100-turn E2E: 723 assertions passed, zero failures; non-timing results match the preceding run.
- Screenshots and logs: repository-root `outputs/credit-reconciliation-2026-09-12/`.

Reproduce from the Godot project directory:

```sh
/Users/crisu/Desktop/Godot.app/Contents/MacOS/Godot --path . res://tools/commitments_trial.tscn -- --no-telemetry --credit-reconciliation
```
