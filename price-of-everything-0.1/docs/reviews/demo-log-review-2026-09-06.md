# Demo log review, 6 September 2026

Source: attached `pasted-text.txt`, attachment `661a75db-4587-422e-bfe5-d2abe5906874` (4,336 lines). Reviewed against the current simulation code. This is a steel and motor expansion run, not the earlier chlor-alkali run.

## Scope and stability

The log records turns 1–100, followed by a save reload and turns 85–88 again. The second sequence must not be counted as another four turns of the same continuous run. The loaded balance is £6,436.92.

There are no `ERROR`, `SCRIPT ERROR` or `WARNING` messages. All 104 recorded resolutions complete, averaging 55.11 ms, with a maximum of 79.70 ms. These are simulation timings, not frame-rate measurements.

Only turns 11 and 23 report a starved building. They coincide with the completion/startup periods of the new steel furnace and motor factory: first output appears on turns 12 and 24 respectively. There is no sustained input or power starvation. The company buys no grid power in the recorded run.

## Cash trajectory

These figures are the log's **reported company net**, not isolated building profit or a complete bank reconciliation.

| Period | Average reported net per turn | Interpretation |
| --- | ---: | --- |
| 1–10 | £57.17 | Opening operation |
| 12–14 | £132.04 | Steel starts; temporary operational credit contributes |
| 24–26 | £311.33 | Motors start; a much larger temporary credit contribution |
| 27–32 | £90.95 | The initial motor credit window has ended |
| 38–49 | £37.30 | Loan payments have risen to £51.83 per turn |
| 80–88 | £71.04 | Loan payments are zero; the carbon levy is active |
| 91–96 | £44.79 | Higher costs and lower output |
| 97–98 | −£50.27 | Reduced output following the substation failure |
| 99–100 | £44.20 | Output recovers |

The early £300-plus turns are not a lasting return from the motor factory. The operational credit refund is about £310 per turn during turns 24–26. That is borrowed cash, with later repayments.

The late decline is consistent with the brownout effect. Between turns 96 and 97, iron ingots fall from 85 to 69, steel from 53 to 44, and motors from 31 to 24. Input quantities continue to be consumed, and input purchases stay at £423.22 per turn. Company net falls from £44.55 to −£50.19, remains negative on turn 98, then returns to £44.25 on turn 99. This matches the event's two-turn output reduction; it is not a supply outage or a permanent deterioration.

The coal mine stops appearing in production from turn 35. The log does not explicitly record whether it was exhausted, paused, sold or demolished, so it cannot establish that cause. Coal becomes an external input in the cost solver.

## Reporting gaps and follow-up issues

1. **The printed cash breakdown omits operational credit and carbon tax.** In `production.gd`, `building_tab_carried` reduces `money_out`, and `carbon_tax_paid` increases it, but neither appears in the printed breakdown. The unexplained positive difference reaches £310.09 on turn 26. The negative difference grows from approximately £2.73 on turn 65 to £30.00 from turn 75 onward, matching the demo levy ramp. These differences are explained by existing fields, not evidence of random cash loss. The printed `interest` figure is also the full loan payment, including principal.

2. **Production inputs are being bought and sold repeatedly.** Late in the run, the log repeatedly lists sales of 60 coal, 23 pure water and 32 copper wiring, alongside consumption of the same quantities and £423.22 of purchases. These three input sales alone add £198.98 to reported goods revenue each turn. The code has a concrete mismatch: `_buy_market_inputs()` targets `(lead + 1)` runs of inputs, while `compute_sell_reserve_for_tile()` protects only one run. Surplus selling can release the inventory the purchasing loop just replenished. This inflates gross turnover and can incur avoidable trading costs. A follow-up should reconcile the purchase and sale targets while preserving the requested one-turn stock reserve.

3. **The cost solver's power allocation is not the bank's grid bill.** It attributes power to buildings at the retail grid rate even while the company imports no electricity. A new consumer using surplus company generation mainly forgoes export revenue. The construction forecast now accounts for that distinction, but the cost-solver rows should not be treated as actual incremental cash costs.

4. **Payback cannot be verified from this log alone.** It does not record the forecast displayed before construction or all construction spending. Company net also includes the existing business, credit, taxes, dividends and events. An accurate comparison needs a forecast snapshot and an isolated with/without-building comparison.

The economic and accounting follow-ups above are identified here, not changed by the event-copy and demo-visibility patch.

## Changes made with this review

- Rewrote decision bodies, advisor explanations, operational alerts and policy notices in plain, factual language.
- Shortened the deposit warning and removed repeated extraction arithmetic from its body; the table retains the underlying figures.
- Policy notice dates now resolve from the active saved timeline. The demo correctly states levy turns 65–75 and green subsidy start turn 80, instead of the campaign's 91–101 and 105.
- Demo construction previews show the payback label without the revenue/balance timeline. The confirm panel also hides its cash-after balance. Construction cost quotes remain visible, and campaign games retain their full forecast.

## Validation

The unit suite passed 3,692 checks; the isolated 100-turn regression passed 723 checks; the construction hover and confirm checks passed 64 checks. Windowed screenshots verified the demo payback-only panels and the revised event and deposit copy. The test harnesses still emit existing renderer/resource cleanup warnings on exit, separate from the supplied gameplay log, which contains none.
