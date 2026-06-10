# Foundations Sprint Phase 2

Phase 2 adds a repeatable end-to-end scenario and benchmark suite on top of the
transport refactor regression net. The runner name still uses its original
Stoneshore filename, but the optimized scenario now builds around the Capital
port because its coal, iron, copper, water, and port geometry make a profitable
turn-100 motor chain possible.

## Scope

- Add `tests/e2e_stoneshore.tscn`, a one-command headless scenario runner.
- Instantiate the real `scenes/main.tscn` and drive player-facing paths where
  practical: survey mapmode signals, loan dialog buttons, BuildMode placement,
  construction missing-material choices, output destination picking, turn
  advancement, and market sale routing.
- Build a deterministic Capital chain: coal, iron, copper, and water surveys;
  a coal-first market-sale runway; road/rail/cable infrastructure; mines;
  smelting; copper wiring; motors; dual coal power; market sales; loan payments;
  and turn timing.
- Compare load and turn-processing timings to
  `tests/snapshots/e2e_benchmark_baseline.json`.

## Harness Exceptions

- The scenario adds a cash runway through the in-game debug terminal so it can
  build the full chain deterministically without turning into a balance test.
- The scenario arms surplus auto-sell for harmless byproducts and final surplus
  goods so full stockpiles do not stall the chain before the turn-100 assertions.
- Output routing and tile-only input toggles are set through their public state
  helpers because those controls are not yet stable enough to click in headless
  mode.
- The E2E runner captures its own per-turn revenue and post-tax profit directly
  from `Production.last_turn_summary`; it does not trust any pre-existing
  `RunMetrics` CSV, which may have been written by another headless diagnostic
  run.

## Acceptance Criteria

- One command runs the full scenario:

```powershell
& "C:\Users\urigi\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe" --headless --path . tests/e2e_stoneshore.tscn -- 100
```

- The scenario executes at least 80 assertions.
- Coal, iron, copper, and water fixture tiles are resolved from live catalog and
  map data.
- Loans are taken through the loan dialog.
- The coal block is built first, powered through a cable, routed to market, and
  sells coal before the full motor buildout.
- Roads, rails, and cables are built through BuildMode and completed by the turn
  loop.
- Construction projects complete into live buildings.
- Motor production runs by turn 100 and motors sell to market.
- Dual local coal power fully covers scenario demand and sells surplus power to
  the grid.
- Cumulative post-tax profit and last-10-turn post-tax profit are both positive.
- Cash after the optimized motor buildout increases by turn 100.
- Load and turn timings are compared to the committed benchmark baseline.

## Latest Check

Measured on Godot 4.6.2 with the command above:

- E2E scenario: 514 passed, 0 failed
- Scene resource load: 1923.13 ms
- Scene instantiate + ready: 3598.11 ms
- Turn wall time: mean 131.91 ms, median 101.65 ms, p95 526.62 ms, max 625.08 ms
- Slow wall-clock turns over 200 ms: 7, 8, 17, 20, 21, 22
- Turn-100 money: GBP 28839.56
- Cumulative revenue: GBP 31676.06
- Cumulative post-tax profit: GBP 8212.68
- Last-10-turn post-tax profit: GBP 1152.20
- Cash delta after buildout: GBP 8655.43
- Runtime scale: 60 buildings, 24 pending shipments

Known residual console noise:

- Missing building icon warnings for `b_011` and `b_029`.
- Godot cleanup leak warnings at process exit.
