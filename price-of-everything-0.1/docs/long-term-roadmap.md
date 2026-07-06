# Long-term roadmap

Deferred ideas and improvements that are worth doing but out of scope for now.

## Extend input-buy netting to cross-tile (1-turn+) linked producers

`Production._buy_market_inputs` currently nets out only **same-tile (0-turn)** production from the
market pipeline (`_same_tile_supply`, tallied in `_flush_output_buffer`). The same over-buying bug
exists for **cross-tile linked producers**: an adjacent steel furnace shipping 30/turn only ever has
~1 turn in transit, so `_inbound_qty` subtracts 30 but the pipeline target is `need × (lead+1)` — so the
consumer still buys `~lead × need` from the market despite the linked supply.

Extending the netting to cross-tile is a genuine fix but riskier than the 0-turn case:

1. **Double-counting** — cross-tile output is already partly accounted for via `_inbound_qty` (in-transit
   shipments). Netting its recurring rate as well would double-count and make the consumer under-buy /
   starve (worst in the partial-supply case). Requires splitting the in-transit deduction into
   "market orders" vs "producer deliveries" and only netting the market ones.
2. **Ramp-up starvation** — a cross-tile supply takes its lead to arrive; netting it pre-emptively leaves
   no market buffer during the ramp when a chain is first built or a producer restarts. Exposure grows
   with route length. (0-turn/same-tile has no ramp, which is why it's safe.)

Recommended approach if/when done: net the recurring linked-supply rate for **any** lead; switch
`_inbound_qty` to market-orders-only; keep a **1-turn market safety margin** on the netted portion; and
re-run the e2e to report the material-spend delta (it will move balance, unlike the 0-turn fix which was
inert in the scenario because it uses `tile_only` inputs). ~20-30 lines in
`_buy_market_inputs`/`_inbound_qty` + a test.
