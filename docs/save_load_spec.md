# Save / Load — implementation spec & progress tracker

Goal: persistent save/load that also powers **different game starts** — custom owned
buildings, money, debt, and pre-configured recurring goods transfers/transactions.

**Key design move:** a "start" is just a small save file. One snapshot format, one
apply path; New Game, Load Game and scenario starts all flow through it.

Format: JSON at `user://saves/<slot>.json`:

```json
{ "save_version": 1,
  "meta": { "turn": 42, "money": 1234.5, "timestamp": "...", "scenario": "default" },
  "turn": {}, "match": {}, "stockpile": {}, "loans": {},
  "construction": {}, "market": {}, "infrastructure": {}, "production": {} }
```

Conventions:
- Every system gets `export_state() -> Dictionary` / `import_state(data: Dictionary)`.
- Import normalises JSON floats back to ints on known-int fields (qtys, turns, counters).
- Shipment route fields (`tiles`/`path`/`legs`, may hold Vector2) are **stripped on
  save and re-quoted via `TransportService.route()` on load** — paths stay valid if
  infrastructure changed; `qty`/`good_id`/`turns_remaining` stay exact.
- Saving only allowed in DECIDE phase and not while resolving.
- UI-only state (alt panels, chart ring buffers, RunMetrics) is NOT saved.
- Caches (`tile_buildings`, `_surveyable_cache`) are rebuilt, not saved.

---

## Phase 1 — Snapshot core

- [x] `scripts/save_load.gd` autoload (registered LAST in `[autoload]`): orchestrates
      export/import, JSON I/O, slot listing, sanitise/normalise helpers
- [x] `MatchState.export_state/import_state` — money, buildings, instance counter,
      land, routing (`output_stockpile_destinations`, `input_tile_only`),
      recurring/scheduled orders, auto-sell state, shipments (pending + overflow),
      ledgers, survey state, `deposit_remaining`, research unlocks/progress,
      labour multiplier, sell mode, route objective, seaport subscriptions
- [x] `Stockpile.export_state/import_state` — `_by_tile`
- [x] `LoanState.export_state/import_state` — loans, next id, profit/revenue history
- [x] `Construction.export_state/import_state` — `construction_projects`
- [x] `TurnManager.export_state/import_state` — `current_turn`, `game_ended`
- [x] `MarketState.export_state/import_state` — `prices` (catalog re-seed + overlay,
      so goods added after a save keep their base price)
- [x] `Production.export_state/import_state` — lifetime produced/streak stats
- [x] Shipment route strip-on-save + re-quote-on-load (countdown fields untouched)
- [x] Debug terminal: `save <name>` / `load <name>` / `saves`
- [x] Round-trip test in `tests/test_runner.gd` (`_test_save_load_roundtrip`:
      export → file → load → re-export, section-by-section canonical-JSON compare
      + live spot-checks; suite green: 202 passed, 0 failed)

## Phase 2 — Load sequencing & UI

- [x] `SaveLoad.load_slot()` → pending snapshot → scene change → `apply_pending()`
      called at the end of `world_map._ready()` (after NPC ports / `seed_deposits`)
- [x] Silent import, then refresh signals (`money_changed`, `surveyed_tiles_changed`,
      `prices_updated`, `loans_updated`, `transport_shipments_changed`,
      `stockpile_changed`, …) + `SaveLoad.match_loaded`
- [x] Building visuals rebuilt via `world_map._rebuild_after_load()`: clears
      `building_visuals` then re-emits `building_placed` per building + per
      construction project (NOT `building_added`/`construction_started`, so no
      toast spam); turn counter/phase label refreshed manually (no
      `turn_advanced` re-emit — it would tick market price decay)
- [x] Re-apply `infrastructure_present` to `hex_map.tiles` + Catalog routing graph
      on load, after `Catalog.reset_runtime_infrastructure()` (the Catalog autoload
      outlives the scene, so a previous match's roads would otherwise leak in)
- [x] Main menu "Load Game" → slot list (slot, turn, money; timestamp as tooltip)
- [x] In-game save entry: top-bar "Save" button → `quicksave` slot with toast
      feedback (named slots via the debug terminal); DECIDE-phase guard lives in
      `SaveLoad.save_slot`
- [x] Scene-level test: `_test_pending_load_applies_on_scene_ready` instantiates
      `main.tscn` with a pending snapshot and asserts it applies (suite: 206/0)

## Phase 3 — Start configurations

- [x] Authoring schema for `res://data/starts/*.json` (money, loans/debt, buildings,
      stockpile, surveyed tiles, land, unlocks, recurring moves/sells/bulk_sells/buys,
      infrastructure) — see `data/starts/coal_baron.json` for a worked example
- [x] `SaveLoad.expand_start_config()`: instance ids from `START_COUNTER_BASE` (no
      collision with scene-seeded NPC ids), amortised loans WITHOUT disbursing
      principal (debt-only starts), recurring orders stamped `turn_started: 1`,
      port tiles + owned-building tiles pre-surveyed
- [x] Start-specific apply rules: scene-seeded NPC buildings (ports/ruins) merged
      into the snapshot before import (`_merge_npc_buildings`); CSV deposit yields
      survive (import defaults `deposit_remaining` to the seeded current value
      when the key is absent)
- [x] `data/starts/default.json` reproducing today's start (`STARTING_MONEY`,
      nothing owned)
- [x] New Game = `SaveLoad.start_new_game()` → expand `default.json` → same
      pending-snapshot pipeline as Load Game (also fixes the pre-existing
      state-leak when starting a new game after playing a match)
- [x] Tests: expander unit checks + `coal_baron.json` applied end-to-end through
      the scene (money/debt/mine/NPC-survival/stockpile/recurring/deposits;
      suite: 221/0)
- [ ] (later) scenario picker on New Game

## Phase 4 — Hardening

- [x] Save-version migration ladder (`SaveLoad._migrate`, one rung per version;
      v1 → v2 implemented and tested against a real v1 file)
- [x] `ruleset` field (SAVE_VERSION 2): `MatchState.ruleset` dict (default
      `{"name": "standard"}`) carried in `match.ruleset` + `meta.ruleset` and in
      start configs (string or dict authoring form, `_normalize_ruleset`).
      Future rule variants key off it; add per-rule keys beside `name`
- [x] Autosave: every 10th finished turn (on `turn_resolution_completed`, when
      the DECIDE save-guard is guaranteed to pass), rotating `autosave_1..3`,
      skipped once the game has ended; `SaveLoad.autosave_enabled` kill-switch
- [x] Construction projects verified across load: awaiting-materials project,
      its missing-materials map and `construction_instance_id`-tagged shipments
      survive; claim_materials promotes the loaded project once materials land
- [x] Persist/restore ended-game state (`game_ended` + final turn; tested)

Suite after Phase 4: 232 passed, 0 failed.

## UI (post-Phase 4)

- [x] Load Game screen (`scripts/save_load_screen.gd`, LOAD mode): dimmed backdrop +
      black rounded-corner panel inset 80px from every screen edge; selectable
      slot rows (slot, turn, money, timestamp); "Load Game" CTA enabled on pick
- [x] Save Game screen (same component, SAVE mode): name input + "Save Game" CTA;
      Enter submits; toast on success
- [x] Loading screen (`scripts/loading_screen.gd`): black overlay with animated
      "Loading…" dots, parented to the tree root so it survives the scene change;
      self-dismisses once the new map scene is up and the pending snapshot applied;
      shown by the load CTA and New Game
- [x] Esc pause menu (`scripts/pause_menu.gd`): opens when `PanelStack.close_top()`
      has nothing left to close — Return to game / Save Game / Load Game /
      Settings (disabled placeholder) / Quit to Desktop
- [x] Main menu "Load Game" routed through the full-screen component (the small
      Phase 2 popup is gone); top-bar quicksave button retained as a convenience

Suite after UI: 240 passed, 0 failed.
NOTE: after adding new `class_name` scripts, run `<godot> --headless --import`
once before headless test runs — a stale global class cache hangs at startup.
NOTE: for code-built Controls use `set_anchors_AND_OFFSETS_preset(...)` —
`set_anchors_preset` alone compensates the offsets to preserve the node's
current (0×0) rect, which strands panels at the top-left and breaks hit-testing.
Debug tools: `tests/ui_probe.tscn` (headless rect dump of the menus inside the
real scene), `tests/ui_screenshot.tscn` (windowed; saves /tmp/poe_*.png shots).
