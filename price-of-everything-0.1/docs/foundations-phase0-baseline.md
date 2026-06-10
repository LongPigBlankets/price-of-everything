# Foundations Sprint Phase 0

Phase 0 locks down the current baseline before the transport, market, save/load,
and tile-panel cleanup work begins.

## Acceptance Criteria

- The existing headless test suite runs and any failures are either fixed or
  recorded as explicit known baseline failures.
- The white-rimmed bottom menu is the default session state.
- A repeatable baseline harness records main-scene load time and early turn wall
  times.
- Stale CSVs are left untouched.
- No transport, market, save/load, or tile-panel deletion work begins in this phase.

## Commands

```powershell
& "C:\Users\urigi\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://tests/test_runner.tscn --quit-after 600
& "C:\Users\urigi\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://tools/phase0_baseline.gd -- 20
```

The baseline harness writes `user://phase0_baseline.json` and prints the same
headline metrics to the console.

## Latest Baseline

Measured with 20 turns on Godot 4.6.2:

- Scene resource load: 2282.74 ms
- Scene instantiate + ready: 3938.21 ms
- Turn wall time: mean 35.03 ms, median 34.66 ms, p95 36.25 ms, max 44.80 ms
- Starting runtime scale: 5 buildings, 0 pending shipments, GBP 200.00

Known residual console noise: missing icon warnings for `b_011` and `b_029`,
plus Godot cleanup leak warnings at process exit. These predate the Phase 0
changes and are not treated as Phase 0 blockers.
