---
name: cnc-save-and-migration
description: Load this before ANY change that adds, removes, renames, or reshapes saved simulation state in price-of-everything - new sim fields, accumulators, dictionaries, per-building data - or when investigating a save/load bug (state resetting on load, phantom turns, corrupt slots, old saves crashing). The custom serialization contract, the migration procedure, and what is deliberately not saved.
---

# Save and migration — the contract for persistent state

Breaking old saves silently is a **release-blocking incident**. This runbook is how you
never do that. The system: custom versioned dict/JSON — never ResourceSaver, never
scene serialization (see `cnc-architecture-contract` rule 4).

## Anatomy (`scripts/save_load.gd`, verified 2026-07-05)

- `SAVE_VERSION := 4`. Migrations are **stepwise**: `_migrate_v1_to_v2` →
  `_migrate_v2_to_v3` → `_migrate_v3_to_v4`; each rung only knows the shape below it.
  Newer-than-current saves are rejected with a readable error, not a crash.
- One orchestrated snapshot: `export_snapshot()` / `import_snapshot()` gather every
  system's `export_state()` / `import_state()`. New game, Load, and scenario starts all
  flow through the same path. `MatchState.reset()` fires `state_reset` first so
  derived-state holders flush before new data lands.
- **Ordering matters and is deliberate**: `apply_pending()` applies infrastructure to
  the Catalog routing map BEFORE `import_snapshot`, so shipment route re-quoting
  (`_requote_shipment_routes`) sees the loaded network. Don't reorder.
- Writes are **atomic**: serialize to `<slot>.json.tmp`, then `DirAccess.rename_absolute`
  over the slot (also `player_profile.gd`). A crash mid-write can't destroy both copies.
- `load_slot` **refuses while `TurnManager.is_resolving`** — a suspended resolution
  coroutine survives scene changes and would resume over the imported snapshot,
  advancing a phantom turn (real bug, fixed 2026-07). Save is DECIDE-phase-only.
- Slot files: `user://saves/<name>.json`; autosave rotates 3 slots every 10 turns;
  `list_slots` ignores non-`.json` (so `.tmp` never shows).

## The tolerant-reader doctrine

Every `import_state` uses `d.get(key, sensible_default)`. Consequences you rely on:
- Old saves missing a whole subsystem load as fresh-zero state **without** a version
  bump (victory, roads, price impact, labour pressure all shipped this way).
- `MarketState.import_state` re-seeds prices from the catalog FIRST, then overlays the
  saved ones — goods added since the save get base prices instead of vanishing.
- Therefore: **most additive changes need NO version bump** — just a default.

## Procedure: changing saved-state shape

1. **Additive field** (new accumulator/dict): add to the owner's `export_state`, read
   with a default in `import_state`, clear it in `reset()`/`state_reset`. No bump.
   Exemplars shipped 2026-07: `MatchState.labour_output_pressure_pct` (default 0.0),
   `MarketState.impact_pct` (default `{}`), `auto_sell_keep`.
2. **Rename/reshape/remove**: bump `SAVE_VERSION`, add `_migrate_vN_to_vN+1` that
   rewrites the old shape, and update the version-history comment at the top of
   save_load.gd (it has drifted before — keep the ledger complete).
3. **Test both directions**:
   - Fresh: new game → save → load → assert the field round-trips (pattern:
     `_test_construction_survives_load`, `_test_*_round_trip` in test_runner.gd).
   - Legacy: hand-craft (or keep) a pre-change save dict and assert import applies the
     default/migration. The advisor system's v4 migration is the worked example.
4. Run the suite + load a real old save if one exists locally.

## Signal silence during import

Imports are **silent**; SaveLoad re-emits one batch of refresh signals at the end.
Per-building `building_added` is deliberately NOT re-fired (no toast/SFX spam — the
audio system's hammer cue is wired to build-commit handlers, not the broad signal, for
exactly this reason). `victory_achieved` is never re-emitted on load. If your feature
reacts to a signal, decide explicitly whether load-time re-emission is wanted, and
follow the existing pattern (world_map re-emits `building_placed` for visuals only).

## What is deliberately NOT saved / IS saved (don't "fix" either)

| NOT saved (derived/transient) | Rebuilt from |
|---|---|
| Power per-turn tallies | `power_reset` each PROCESS |
| Route/port caches, CostSolver results | recompute; caches invalidate on infra change |
| TileOccupancy | baked hills + producers |
| Per-turn market volume trackers (`_turn_sold/_bought`) | empty in DECIDE by construction |
| Camera/map-mode/panel view state | session-local |

| SAVED despite looking derived | Why |
|---|---|
| RNG seeds AND states (match + special orders) | determinism across reload |
| `impact_pct` (price impact) | accumulated economic state |
| `labour_output_pressure_pct` | accumulated |
| Shipments minus route geometry (`tiles/path/legs` stripped, re-quoted on import) | Vector2s aren't JSON-safe; network may have changed |
| Road network geometry (quantized 0.01) + idempotency markers | visual/routing identity, no double-linking on reload |

## Known open items (2026-07-05)

- Production's intermittency derates are neither saved nor cleared on import (1-turn
  divergence after load; stale-id edge in-session) — audit D2, open.
- Structurally-corrupt-but-valid-JSON saves can still crash mid-import (only the top
  level is shape-checked) — audit D4, open. Handle with care if touching import paths.

## When NOT to use this skill
- General sim invariants → `cnc-architecture-contract`
- A load "loses" UI state (by design — see table above) → check here first, then `cnc-debugging-playbook`
- Adding a tunable constant (not saved state) → `cnc-balance-change-control`

## Provenance and maintenance
Verified 2026-07-05 against save_load.gd and system export/import pairs.
- Version + migrations: `grep -n "SAVE_VERSION\|_migrate_v" price-of-everything-0.1/scripts/save_load.gd`
- Atomicity: `grep -n "tmp" price-of-everything-0.1/scripts/save_load.gd`
- Load guard: `grep -n "is_resolving" price-of-everything-0.1/scripts/save_load.gd`
- Snapshot contents: read `export_snapshot()` top to bottom before trusting the tables.
