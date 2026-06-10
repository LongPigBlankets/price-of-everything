# Foundations Sprint Phase 1

Phase 1 centralizes transport quoting and route fallback behind one helper while
leaving persistence and low-level route graph ownership unchanged.

## Scope

- Add `TransportService` as an autoload facade for route lookup, nearest-port
  lookup, per-route transport costs, market buy quotes, market sell quotes, and
  multi-good manifest quotes.
- Keep `Catalog` as the route graph owner.
- Keep `EconomyConfig` as the tariff/rate owner.
- Keep `MatchState` as the owner of shipment persistence, ledgers, and save/load
  state.
- Update production, construction previews, transport UI summaries, recurring
  ledger rows, and simulation setup to call `TransportService` instead of
  duplicating route fallback or transport-cost math.

## Acceptance Criteria

- Gameplay code no longer calls `Catalog.route()` or
  `EconomyConfig.transport_*()` directly for shipment or quote decisions outside
  `TransportService`.
- `queue_move`, `preview_move`, `queue_buy`, `preview_buy`, and stockpile or
  production market sales use `TransportService` quotes and preserve their
  existing shipment record shapes.
- Seaport coverage semantics are unchanged: executing a covered market action can
  subscribe the good, while previewing a buy only checks whether it would be
  covered.
- Construction ETA, spare-stock sourcing, building detail route summaries, tile
  list transport RAG, money projections, and market connection visuals agree with
  the same route helper used by the turn processor.
- Existing save/load data remains compatible because pending shipment records are
  still queued by `MatchState` with the same keys.
- The headless test suite passes.

## Test Scenarios

- Unit smoke: `TransportService.route()` returns an adjacent-tile route with one
  turn.
- Unit smoke: `TransportService.quote_manifest()` returns route turns and a
  positive cost for a non-empty manifest.
- Unit smoke: `TransportService.quote_market_buy()` resolves the nearest port and
  returns `goods_cost + transport_cost == cost`.
- Seaport regression: covered market buy and sell quotes are one turn with zero
  per-unit transport cost.
- Integration regression: existing queue/preview buy, sell, and move tests still
  pass with unchanged public summaries.

## Out Of Scope

- Unified market state.
- Save/load UI and scenario persistence tests.
- Deleting the old tile panel.
- The full player-driven end-to-end benchmark scenario from the foundations
  sprint brief.
- Stale CSV cleanup.

## Commands

```powershell
& "C:\Users\urigi\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://tests/test_runner.tscn --quit-after 600
& "C:\Users\urigi\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://tools/phase0_baseline.gd -- 20
```

## Latest Check

Measured with 20 turns on Godot 4.6.2 after the Phase 1 refactor:

- Test suite: 186 passed, 0 failed
- Scene resource load: 2161.81 ms
- Scene instantiate + ready: 3958.50 ms
- Turn wall time: mean 34.80 ms, median 34.81 ms, p95 36.05 ms, max 38.84 ms
- Runtime scale: 5 buildings, 0 pending shipments, GBP 200.00

Known residual console noise is unchanged from Phase 0: missing building icon
warnings for `b_011` and `b_029`, plus Godot cleanup leak warnings at process
exit.
