# Upcoming links and priority notice — 12 September 2026

Balance and Treasury now use an underlined cream LinkButton, with no filled background. Both open Upcoming. The full preview and its link subtotal retain their existing scope.

A narrower notice appears under the money widget, ahead of loan/spending/transport/payment anomalies, within the existing two-card limit. Its larger primary-style caret opens Upcoming. The notice updates after resolution and relevant changes to stock, orders, construction, credit/loans, money and routes. Clicking outside dismisses it; identical costs do not immediately reopen it. A changed turn or changed costs can show it again. Tutorial suppression follows the existing notice pattern.

## Notice eligibility

- Construction/upgrade shipment bills, separating next-turn payments from later deliveries.
- Bank and building-credit repayments due next turn.
- Construction material orders expected next turn.
- Input orders starting/resuming where that tile/good had no actual order in the preceding recorded turn; and the allocated input-order share of a building about to complete.

Routine labour/maintenance, standing purchases, continuing ordinary input orders and their arrival bills do not trigger the notice. Future bank repayments still in grace are excluded. With no previous-turn history after load, ordinary existing orders are not assumed to be new. Restart detection uses tile/good ordering history; the forecast does not claim precise attribution of restarts between existing factories sharing a good.

The pure input allocator can optionally report quantities by building for the preview. The simulator keeps tracing off. This lets a new building sharing an input contribute only its own allocated order share to the alert. Cost attribution is proportional at the preview quote, so it remains an estimate including apportioned freight.

## Verification

- Script sweep: 607 scripts, zero failures.
- Windowed six-turn trial: all checks passed, including first priority, notice cap, caret styling/navigation, tertiary-link styling/navigation and unchanged-cost dismissal.
- Forecast/actual checks and preview immutability checks remain green.
- Full unit suite: 403 tests, 3,929 assertions passed, zero failures.
- 100-turn E2E: 723 assertions passed; non-timing economic results unchanged.
- Artifacts: repository-root `outputs/upcoming-notice-2026-09-12/`.
