# Construction payments at confirmation

The placement flow already charged its construction fee immediately. Market material orders placed by a construction confirmation now also deduct their full quoted goods and freight cost immediately. They remain reserved, undispatched orders until the next transport phase. No unpaid material bill is created, so the same cost neither consumes headroom twice nor reappears in Upcoming extra costs. The construction buffer now covers startup costs only, as the construction kit is paid at confirmation.

The original tile-panel Cancel button calls the existing Construction.cancel API. Before End Turn it cancels that project's reserved orders, refunds their prepayment plus the existing construction-fee refund, and returns any reserved own stock to its original source. Cancelled market goods are never granted. Repeated cancellation cannot refund twice. After dispatch, existing cancellation semantics retain materials as incoming/owned stock. Land purchases always remain paid and owned, including automatically purchased land. No new cancellation UI was added.

Dispatch applies the reserved orders' market-volume/trade/port effects once, before the usual transport snapshot and countdown. Cancelled orders therefore have no phantom trade or market-pressure effect. The small undispatched-reservation index is rebuilt on load and avoids scanning all in-flight freight on each quote. Sequential basket quotations include prior reservations so freight/capacity pricing agrees with the commitment. Failed reservation batches roll back their own orders, preserving other projects.

Optional shipment fields (`construction_order_pending`, `construction_prepaid`, `reserved_sea_charge`) ride the existing dictionary serialization; old shipments retain their previous pay-on-arrival behavior. Prepaid construction deliveries preserve the existing arrival-date tax/dividend deduction through a separate non-cash summary field, without reporting a second cash expense. No balance constants were changed.

## Verification

- Parse: 610 scripts, zero failures; 47 established skips.
- Full suite: 412 tests / 3992 assertions passed.
- 100-turn E2E: 723 assertions passed.
- New regression tests cover immediate full charging, same-turn refunds, no duplicate refunds, save/load, no double charge on delivery, original delivery timing, failed second orders preserving the first, own-stock returns and preserved tax/dividend deductions.
- Windowed actual placement and original tile-panel Cancel: £473.212310125 charged = £30 fee + £433.212310125 materials/freight + £10 land. Cancellation refunds £463.212310125 and retains purchased land. No queued materials remain and owned stock is restored. No future material bill appears for the prepaid build.
- Screenshots inspected. Existing shutdown resource-leak warnings remain.

Evidence in `outputs/construction-prepayment-2026-09-13/`. No exports rebuilt.
