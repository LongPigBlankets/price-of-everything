---
name: cnc-performance-playbook
description: Load this when price-of-everything is slow - long turn resolution, frame drops with panels or overlays open, slow load times - or before optimizing anything, or to run the ENDGAME PERFORMANCE CAMPAIGN (owner-defined target - 50+ buildings all running each turn). Covers measurement discipline (TurnProfiler, never editor numbers), the hot paths, the already-won optimizations you must not regress, and a decision-gated perf campaign.
---

# Performance playbook — measure, don't eyeball

## Part A — doctrine

### Measurement first
- **Turn time**: `TurnProfiler` (autoload, enabled by default) writes per-turn rows to
  `user://turn_profile.csv` — one column per phase + the 14 PROCESS sub-sections +
  scale counts (buildings, pending_shipments, production_passes). This is the
  instrument; read it before touching anything.
- The e2e harness prints a slow-turn digest (any turn > 200ms wall) WITH its profiler
  breakdown — free measurements on every run
  (`"$GODOT_BIN" --headless --path . res://tests/e2e_stoneshore.tscn -- 100`).
- **Never benchmark in the editor** — debug runtime + editor overhead distort
  everything. Headless or exported release only.
- Baselines (2026-07-05, e2e @ ~600 total buildings, ~30 player-run): mean turn
  ~57ms, median ~39ms, p95 ~164ms; scene load ~830ms; instantiate+ready ~10.9s.
  Baseline snapshot: `tests/snapshots/e2e_benchmark_baseline.json` (the harness
  asserts against it — a perf regression FAILS the run).

### Known hot paths (audit-verified)
| Path | Scaling | Candidate fix (ranked, unproven until measured) |
|---|---|---|
| `Modifiers.apply/resolve_pct` linear registry scans | ~60 modifiers × buildings × passes × domains | domain→modifiers index |
| Production cascade re-checks | O(passes × starved buildings), cap 30 | order by dependency; early-out starved |
| `Power` reads scene tree per building per pass (`get_first_node_in_group`) | hot-loop scene access | per-turn cached tile→cable dict |
| Market-input top-up scans all shipments per (tile,good) | O(shipments × demanders) | shipments-by-destination index per turn |
| Route cache invalidation on infra change | full-map re-quote burst next turn | per-tile invalidation |
| `RoadOffshoots.generate_stubs` on every building event | O(network geometry), synchronous | budget/queue it |
| Save stringify on autosave | O(state) on the end-turn frame | thread the stringify+write |

### Already-won optimizations — DO NOT regress
LoadPacing gate + threaded scene load; hills baked offline + sliced triangulation +
cached ArrayMeshes + far-zoom texture LOD; roads baked spine; route/port memo caches;
lazy MarketPanel tabs; NPC building pre-filter (sim iterates player-only); in-place
shipment advance (was a deep-copy hotspot); coalesced panel refreshes
(`cnc-ui-and-theming`); empire-view static-geometry cache + zoom floor; capped
histories (ledgers 500, charts 10). If your diff touches one of these files, re-read
the comment explaining the win before changing it.

### The cautionary tale: prewarm (built, then dropped)
Commits `ff96d06 → ef14f94 → 041d58a → 67bc37b` built a full "prewarm the map on the
menu" system; `969fb42` **dropped it** — the instantiation hitch proved irreducible,
and the keepers were the cheaper ideas (lazy panels, chunked triangulation, pacing).
Lesson: spike the measurement FIRST; a perf idea isn't validated by working, only by
numbers. Don't rebuild prewarm.

## Part B — the endgame performance campaign

**Owner-defined target (2026-07-05): 50+ player buildings ALL RUNNING each turn**, at
comfortable turn times. Decision-gated; run phases in order, record numbers at each.

### Phase 0 — baseline
```bash
cd "/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1"
"$GODOT_BIN" --headless --path . res://tests/e2e_stoneshore.tscn -- 100   # note metrics JSON
```
Record: turn_mean_ms, turn_p95_ms, slow_turns[].profiler_steps. GATE: if already
within budget (mean < ~60ms, p95 < ~200ms at the e2e scale) the campaign is about the
50-running scenario, not general slowness — continue.

### Phase 1 — build the 50-running scenario
Write a headless tool (clone `tools/sim_mini_strategy.gd` skeleton): seed ≥50 player
buildings that all pass their run checks (stock inputs via `Stockpile.add`, cables via
infra, deposits on real deposit tiles), set `TurnManager.fast_mode = true`, run 20
turns, dump `user://turn_profile.csv`. EXPECTED: all 50+ appear in
`Production.last_turn_run` each turn — if not, fix the scenario (starved ≠ running),
don't proceed on bad data.

### Phase 2 — attribute
Sort the profiler columns. GATES:
- `production_passes_ms` dominates → Modifiers index and/or Power cache (top table).
- `transport_arrivals_ms`/`buy_market_inputs_ms` → shipment destination index.
- `maintenance_labour_ms` → per-building modifier resolves (same Modifiers index).
- Wall ≫ profiler total → the cost is OUTSIDE the sim: UI signal storms (check a
  panel was left open; re-verify coalescing), or autosave stringify on 10th turns.
- Editor-only slowness → not a campaign item; re-measure headless.

### Phase 3 — fix ONE lever, re-measure
Implement the single indicated fix behind the smallest possible diff. Re-run Phase 1
identically (same seed/scenario). EXPECTED: the targeted column drops ≥30%; total mean
improves; NO change to any sim outcome (determinism check: money/turn trace identical
before/after — a perf fix that changes outcomes is a behavior change →
`cnc-balance-change-control`).

### Phase 4 — promote
Unit suite + e2e green with the benchmark assertion passing; commit with before/after
profiler numbers in the message. Update the baseline snapshot ONLY when the
improvement is the new intended floor, in its own commit.

Fenced wrong paths: C# ports (breaks web export — escalation needs owner signoff);
optimizing editor numbers; batching that reorders sim phases; caching that survives
infra changes without invalidation (the route cache's discipline exists for a reason).

## When NOT to use this skill
- Panel-open slowness during turns → first `cnc-ui-and-theming` (refresh doctrine)
- Load-time issues on NEW GAME specifically → the LoadPacing notes here + failure-archaeology's prewarm story
- Perf change that alters behavior → `cnc-balance-change-control`

## Provenance and maintenance
Compiled 2026-07-05 from the mechanics audit + TurnProfiler/e2e reads.
- Profiler columns: `grep -n "section_begin\|COLUMNS" price-of-everything-0.1/scripts/turn_profiler.gd`
- Baseline: `cat price-of-everything-0.1/tests/snapshots/e2e_benchmark_baseline.json`
- Hot-path claims: re-run Phase 0/1 and read the CSV — numbers beat this document.
