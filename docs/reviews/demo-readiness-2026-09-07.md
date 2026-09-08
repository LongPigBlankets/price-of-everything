# Demo readiness review — 7 September 2026

Reviewed commit `420997ba` on `final-fixes-before-demo`. This is an initial readiness audit, not release sign-off.

## Findings

### P2 — Loading a match retains the previous match’s unit costs

`SaveLoad.import_snapshot` (scripts/save_load.gd:94) resets/imports match and production state but neither restores nor clears `CostSolver.last_result`. A runtime probe seeded a motor cost of 123.45, loaded a previously captured snapshot and still read 123.45 afterward. A fresh process instead has no cost results until production runs. The market produced-goods filter and chart cost visibility depend on this cache (scripts/market_price_chart.gd:55), so save/load behaviour depends on what was open previously. Restore or recompute the loaded match’s derived costs, and cover both fresh-process and cross-match loading.

### P2 — Autosaves omit the latest market-history observation

Runtime inspection confirmed `SaveLoad._on_turn_resolution_completed` is invoked before `MarketState._record_price_history`. Autosaves therefore serialize the history before its current-turn point is appended. Loading that autosave preserves the incomplete history because import only seeds observations when the entire history key is absent. Record history before snapshot capture, or explicitly order turn-completion persistence after history recording. Add an autosave-specific regression, beyond the existing direct market-state round trip.

## Passed evidence

- Parse sweep: 555 scripts, zero failures, 40 exclusions.
- Unit suite: 3,719 checks passed.
- 100-turn simulation: 723 checks passed after impact rates doubled.
- Windowed tutorial regression rerun: 44 checks passed, covering both construction branches, research, advisor hiring, completion and demo loyalty visibility.
- Market windowed visual check: fixed historical cost line and three-line off-white hover readout.
- Demo menu code locks starts to Metal Magnate/Glass Merchant, Normal difficulty and the 100-turn demo ruleset.

## Remaining release verification

- Resolve the two save/load findings before sign-off.
- Run the packaged release on intended demo platforms. No packaged build was produced in this audit. The initial combined probe/export approval timed out; the isolated probe retry succeeded.
- Audit export contents: all three presets use all_resources and omit development artifacts from their exclusion lists. The local artifacts directory is 1.2 GB, so a package manifest/size check is warranted; actual inclusion has not yet been verified.
- Complete a continuous manual tutorial and representative playthrough for both permitted starts. The staged tutorial harness is not a complete manual playthrough; the 100-turn simulation is not a balance guarantee for both starts.

Only the review document was added after the reviewed commit. Local art experiments, generated reports/import byproducts and skill notes remain outside the commit.

## Follow-up

Both save/load findings are fixed and regression-tested. The Windows packaging audit also fixed the missing binary layout bake and removed development files from the export. See `windows-build-audit-2026-09-07.md` for validation and remaining release checks.
