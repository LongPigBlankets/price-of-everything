---
name: cnc-architecture-contract
description: Load this before ANY code change to the simulation, turn logic, saves, RNG, or UI/sim boundary in Carbon and Capital (price-of-everything). Triggers - adding a feature that touches sim state; anything involving nodes for buildings/goods; anything using randi/randf; save format questions; "why is this designed this way"; reviewing whether a change is architecturally legal. This is the contract of load-bearing decisions, the invariants that must hold, and the honest list of known-weak points.
---

# Architecture contract — the rules that hold this project together

Every rule below is load-bearing. Each is paired with the concrete failure it prevents.
Violating one usually doesn't fail a test — it corrupts determinism, saves, or performance
*silently*. When in doubt, this file wins over Godot instinct.

## The seven invariants

### 1. The simulation lives OUTSIDE the scene tree
Sim state = plain Dictionaries/Arrays owned by autoload singletons (`MatchState`,
`Production`, `MarketState`, `Stockpile`, `Construction`, `LoanState`, `Power`,
`SpecialOrderState`, `Modifiers`, `VictoryState`, …). Buildings, goods, tiles, markets
are **data, never Nodes**.

- The scene tree *renders*; the sim *computes*. `world_map.gd` and panels read sim state.
- **Failure prevented:** a Node per building hits a hard rendering/GC ceiling in the
  hundreds (the project supports 500+ NPC buildings + a growing player empire), and node
  lifecycle entangles sim correctness with scene reloads (load/save would need scene
  serialization — see rule 4).
- **Junior trap:** "I made buildings into nodes so they could animate." Rendering for
  buildings goes through `scenes/building_visuals.gd` (packed drawing), map decoration
  through `_draw()` layers (e.g. `scripts/port_visuals.gd`, `scripts/survey_overlay.gd`).

### 2. Turn logic advances ONLY by explicit calls
`scripts/turn_manager.gd` drives DECIDE → (commit_turn) → PROCESS → SEND → AI → NARRATIVE
→ RECEIVE → turn++ → DECIDE. Zero economic logic in `_process`/`_physics_process`/`_draw`.

- Frame callbacks exist only for rendering/input. Grep check:
  `grep -n "_process(" price-of-everything-0.1/scripts/production.gd` → must return nothing.
- **Failure prevented:** frame-dependent economics = non-reproducible outcomes = broken
  saves and a useless balance harness.
- Since 2026-07 the *intra-phase listener order* is also explicit:
  `TurnManager._wire_sim_listeners()` connects `phase_started` hooks in a fixed,
  documented order (MatchState → Production → EventScheduler → Modifiers). It used to
  fall out of autoload registration + deferred-connect timing — an implicit race.
  **Never reorder that list** without checking the dependencies documented at the hook
  (battery fills must precede the production cascade; unlock checks precede event tick
  precedes modifier pruning in NARRATIVE). See `cnc-turn-pipeline-reference` for the
  full order.

### 3. Determinism is mandatory
Same seed + same inputs ⇒ identical outcome. Required by BOTH the save system and the
headless balance harness (`tests/e2e_stoneshore.gd`).

- One seeded `RandomNumberGenerator` per sim domain, and its **state is saved**:
  `MatchState._match_rng` (+ `match_rng_seed`), `SpecialOrderState`'s own RNG
  (`rng_state` in its save dict).
- **NEVER** call global `randi()`/`randf()` in sim code. The only tolerated unseeded RNG
  is pure visuals that touch no sim state: hills/forest decoration, the main-menu goods
  deck shuffle (`goods_grid.gd`).
- Road seeds use explicit FNV-1a hashing (`scripts/road_hash.gd`) because GDScript's
  built-in `hash()` is not stable across engine versions and those seeds persist in saves.
- **Failure prevented:** a single stray `randf()` makes save/reload diverge from
  continuous play, and makes every balance sweep unreproducible.
- Audit check (sim core must have ZERO unseeded RNG — seeded `rng.randi()` calls are
  fine and are filtered out):
  ```bash
  grep -rnE "\b(randi|randf|randi_range|randf_range)\(" \
    price-of-everything-0.1/scripts/{match_state,production,market_state,cost_solver,modifier_state,special_order_state,turn_manager,power}.gd \
    | grep -vE "rng\.(randi|randf)"
  ```
  Must return nothing. Bare-`grep randi()` over all of `scripts/` returns ~52 hits —
  those are seeded `rng.randi()` method calls and the visual whitelist above, not
  violations; the filtered sim-core check is the real gate.

### 4. Saves are custom, versioned dict/JSON — NEVER ResourceSaver or scene serialization
`scripts/save_load.gd`: `SAVE_VERSION` (4 as of 2026-07-05), stepwise `_migrate_vN_to_vN+1`
hooks, tolerant-reader imports (`d.get(key, default)` everywhere), atomic writes
(temp file + rename), and a guard that refuses `load_slot` during turn resolution.

- **Failure prevented:** Resource/scene serialization breaks the moment a class changes
  shape; explicit dicts + migrations let old saves survive schema evolution.
- Full procedure for shape changes: `cnc-save-and-migration`.

### 5. UI is read-only against the sim
UI observes via signals and reads state; it never writes sim fields directly. All
mutations go through the sim API (`MatchState.set_*`, `enable_*`, `queue_*`,
`Construction.start_*`, …), which validates and emits.

- **Failure prevented:** UI writes bypass validation/emission, so panels desync and the
  sim becomes untestable headlessly.
- Corollary doctrine: panels use **coalesced deferred refresh** (the notification-bell
  pattern) — see `cnc-ui-and-theming`. Rebuilding per `money_changed` emission once cost
  hundreds of rebuilds per turn.

### 6. Typed GDScript everywhere
`var n: int`, `func f(x: float) -> Dictionary:`. Untyped code is where subtle bugs and
hot-path slowdowns enter. New code without types fails review.

### 7. Balance constants are DATA, and never change silently
Tunables live in `scripts/economy_config.gd` (its header says so) and per-good columns of
`data/Goods - goodsMVP.csv` (`base_price`, `decay_rate`, `co2_tax_multiplier`,
`green_sales_premium`). Owner ruling (2026-07-05): **everything is volatile until EA
ships** — tuning is expected — but every change routes through
`cnc-balance-change-control` with harness evidence. No exceptions, including "obvious"
fixes.

## Known-weak points (OPEN as of 2026-07-05 — do not "discover" these again)

Full detail with criticality ratings lives in
`price-of-everything-0.1/docs/mechanics_audit_2026-07.md`. Headlines:

| Weakness | Status |
|---|---|
| No bankruptcy enforcement — money can go arbitrarily negative | OPEN (design pending) |
| Loan principal counts as a tax-deductible expense | OPEN (audit H3) |
| Manual sells pay no freight; auto-sells do | OPEN |
| Auto-sell path skips `market_price` modifiers (prices raw) | OPEN |
| Special-order arbitrage (buy from market → deliver to order) | OPEN |
| Demolish not implemented, but three UIs promise it | OPEN |
| Capacity dialog "Expand storage / Stop production" are no-ops | OPEN |
| Infra "upgrades" charge materials but change nothing | OPEN |
| 3 advisor seats have no effects; most specialties decorative | OPEN |
| Some fluid moves still route overland (non-TVP paths) | PARTIAL fix at UI seams |
| Unreachable-route fallback can beat real routes | OPEN |
| Demo infrastructure hardcoded on 8 tiles (`_apply_demo_infra_levels`) | OPEN, in live balance |
| Road network artifacts are irreversible (no remove path) | BY DESIGN for now |
| `OCCUPANCY_ROADS_ENABLED = false` — buildings can straddle roads | GATED feature |
| Legacy `GLUT_UNITS` only feeds the auto-sell cap UI (mismatch with live impact model) | OPEN |

If your change touches one of these, say so in the change note — don't silently fix or
silently depend on the broken behavior.

## When NOT to use this skill
- Godot API gotchas (Buttons, TileMapLayer, headless quirks) → `cnc-godot-discipline`
- The exact turn order and its worked trace → `cnc-turn-pipeline-reference`
- What the economic formulas mean → `cnc-economy-reference`
- Whether/how a change must be gated → `cnc-balance-change-control`

## Provenance and maintenance
Compiled 2026-07-05 from CLAUDE.md, the July 2026 mechanics audit, and direct code
verification. Re-verify before trusting drift-prone facts:
- Invariant 2 wiring: `grep -n "_wire_sim_listeners" price-of-everything-0.1/scripts/turn_manager.gd`
- Invariant 3 sim-core RNG gate: the filtered command in §3 above (must be empty)
- SAVE_VERSION: `grep -n "SAVE_VERSION" price-of-everything-0.1/scripts/save_load.gd`
- Weak-point list: re-read `price-of-everything-0.1/docs/mechanics_audit_2026-07.md` §Cross-cutting.
