# Building Ledger — Implementation Plan

Status: **design-only, no implementation.** Backend/architecture grounded against the current
tree (all file:line verified). The **visual design** (`Building Ledger.html` from the Claude
Design project) is **not yet imported** — the design MCP needs `/design-login` (design scopes).
Sections marked **[design-pending]** will be pinned down once that import succeeds.

> **Revision note.** Re-verified every claim against the real code and corrected the mistakes (§14).
> Economic model: salvage/`sell_building` is **replaced** by **demolish + `refund_cost`** — the refund
> is `build_cost_money` **+ every material kit consumed over the building's life** (construction kit +
> each completed upgrade level, so an L3 refunds all 3 levels), scaled by a tunable
> `EconomyConfig.demolish_refund_share` (**`var`, default 1.0** = 100%). `refund_plan` returns materials
> to the tile stockpile up to capacity and **offers cash for any overflow** at market price (the
> cash-offer dialog). **Phase 1 backend is implemented and the suite is green** (+14 assertions);
> the demolish dialog + actual removal remain deferred, and **bulk demolish is a no-op button**.
> Multi-upgrade gets a real **grid dialog**; the power column is **rechecked every turn from
> production's last-turn state**.

---

## 0. Where things stand

- **Design import blocked.** `DesignSync.get_project` returned "needs a claude.ai login … run
  /design-login". Until that's granted, the exact column set/order, filter affordances, action-bar
  styling, and whether the ledger is a sized panel vs fullscreen come from the stub + codebase
  conventions, not the mockup.
- **Backend is design-independent** and fully mapped below — it's the bulk of the engineering and
  carries the real risk (new `refund_cost`, the demolish dialog, carrying construction cost onto the
  building instance at promotion).

---

## 1. Stub review — confirmed / corrected / extended

| Stub claim | Verdict | Detail |
|---|---|---|
| `building_ledger_panel.gd` is placeholder | ⚠️ mostly | `extends PanelContainer`; **section2/section3** are Lorem `SectionCard`s, but **section1 is already a LIVE control** — `_populate_routing_section` wires an `OptionButton` to `MatchState.route_objective` (building_ledger_panel.gd:60). Do **not** blind-wipe all sections. The `.tscn` (780×760) also carries a Hero image, a MetaStrip (3 captions), an IconButtonRow (3 buttons) and a ButtonRow (4 buttons) — more demo nodes than "3 cards". Plan to remove those too. |
| Source rows from `MatchState.buildings`, filter `is_player_owned()` | ✅ correct | `is_player_owned(building: Dictionary)` returns `str(building.get("owner", LOCAL_PLAYER)) == LOCAL_PLAYER` (match_state.gd:221). It takes the **building dict**, and an unset/empty owner reads as player-owned. |
| Optional "Under construction" group from `Construction.construction_projects` | ✅ correct, with caveat | Those projects are a **separate dict**, NOT in `MatchState.buildings` until promotion. Query both. Use `projects_on_tile(tile_id)` or iterate `construction_projects.values()` (returns **live** dicts — read-only). |
| Row click → `MatchState.focus_building_requested(instance_id)`, reuse world_map deep-link | ✅ correct (handler at **world_map.gd:983**) | `_on_focus_building_requested` **jumps** the camera (instant `cam.position =`, not a tween) and opens the **detail panel**. ⚠️ Hide the ledger first or the focus opens *behind/over* it (see §6.5). The ledger does **not** emit this signal today (only `notification_bell.gd:614` does) — wiring it is new. |
| Multi-select action bar → shared state APIs, not panel-local mutation | ✅ correct principle | No checkbox/multi-select or sortable-header widget exists in the codebase — build from scratch (§6.3/§6.4). |
| Add `MatchState.sell_building` / `demolish_building` / `upgrade_building` | ⚠️ reworked | `upgrade_building` **already exists** as `start_upgrade(instance_id, mode)` (returns a **Dictionary** `{ok, …}`, modes `tile`/`market`/`transfer`) + `preview_upgrade(instance_id)` + `is_upgrading`. **Salvage/`sell_building` is dropped**; replaced by **demolish + `refund_cost`** (§5). `demolish_building` removal is **deferred** this pass. |
| Sell = liquidate for salvage value | ❌ replaced | New model: **demolish refunds construction materials + `build_cost_money`** via `refund_cost`, shown in a dialog. `remove_building` still gives **no money back**, so the refund credit is net-new — and removal is deferred for now (§5). |
| Emit a new `building_changed` / `building_owner_changed` signal | ⚠️ unnecessary | Live recipe/owner edits don't exist today (recipe change is a no-op, world_map.gd:1436). Refresh on existing signals + per-turn (§7). Add `building_changed` only if live in-place edits appear later. |

Two corrections worth flagging up front: the deep-link handler is at **world_map.gd:983**, and
**`upgrade_building` already exists** (don't re-add it) — but note `start_upgrade` returns a result
**Dictionary**, not bool/void.

---

## 2. Current state (what's already wired)

- **Mounting (reuse as-is):** `bottom_menu.gd:341 _on_buildings_pressed` first calls `_hide_all_panels()`,
  then lazily instantiates the panel, `add_child`s it under **HUDContent** (`construct_panel.get_parent()`),
  immediately `.hide()`s it (instantiate yields a *visible* node), wires `close_requested →
  _set_panel_visible(panel,false)`, links the button "rise" (`_link_rise`), and shows via
  `_set_panel_visible` (which does `PanelStack.push/remove` for Esc handling). **No mounting work
  needed** — just replace the panel's body. Note: the panel is **not** in `main.tscn`; it exists only
  after first open, so no scene-load node-path assumptions.
- **Esc caveat:** `PanelStack.close_top()` only calls `top.hide()` — it does **not** route through
  `close_requested`/`_set_panel_visible`'s remove path. Don't hang teardown off `close_requested`
  alone; it won't run on Esc.
- **Panel shell:** draggable header (`header.gui_input → _on_header_gui_input`), close button,
  `DS.theme`. Currently a 780×760 fixed-size **draggable** `PanelContainer`, recentred once via
  `call_deferred("_center_on_screen")`, **not** fullscreen like `research_panel` (which is a
  full-rect anchored `Control` declared statically in `main.tscn`). **[design-pending]**: the mockup
  may want a wider/fullscreen table — resize or re-anchor accordingly.

---

## 3. Architecture & data flow

```
MatchState.buildings (player-owned) ─┐
Construction.construction_projects ──┤→ BuildingLedger builds a row-model (VM) list per refresh
                                     │   (one VM dict per building / per construction project)
Production / Power / CostSolver / ───┘   pulled live for status & profit columns
Catalog                                  (recipe, category, names, base price)

Row click  → MatchState.focus_building_requested(instance_id)  → world_map.gd:983 (jump + detail)
Action bar → MatchState.start_upgrade (existing) · demolish (refund_cost dialog, removal deferred)
Refresh    ← building_added / building_removed / building_upgraded / *_upgrade_*
           + construction_started/completed/cancelled/materials_ordered/materials_updated
           + TurnManager.turn_resolution_completed (per-turn snapshot: power/profit/status)
```

The panel is a **view** over canonical state — it never mutates building/project dicts directly; all
actions call MatchState/Construction APIs and let the resulting signals drive the refresh. Keep the
**row-model (VM) decoupled from the Control rendering** so re-skinning after the design import is
cheap (see §12 perf note — this also matters for node reuse).

---

## 4. Row model — columns → data source (verified)

Build one view-model dict per row so rendering and filtering/sorting work off a flat structure.

| Column | Source | Notes |
|---|---|---|
| select checkbox | panel-local `Dictionary<instance_id,bool>` (Set) | new widget (§6.4); prune to visible rows each rebuild (§6.4) |
| building name | `Catalog.get_building(building_id).display_name` | `get_building` can return `{}` for a bad id — guard before reading fields |
| tile | `instance.tile_id` ("tile_X_Y") | **[design-pending]** region grouping — see §9.6: that's a **data** dependency, not pure rendering (no region field exists today) |
| recipe / output | `Catalog.get_recipe(recipe_id)` → `output_good_id`/`output_qty` (or `output_name` = first output's **internal_name**) | resolve internal_name→label via `get_good_by_internal_name`/`get_display_name`; recipe can be `{}` |
| category / type | `Catalog.get_building(building_id).category` | **four** values: `production` / `power` / `infrastructure` / **`battery`** — don't hardcode a 3-way branch |
| level | `instance.level` (1–3) | written by `tick_upgrades`; show "Lv2" |
| power status | **per-turn snapshot** from `Production.last_turn_run.has(id)` + recipe energy req, plus `Power.is_supplied(tile_id)` for current cabling; rebuilt on `turn_resolution_completed` (§7) | `_power_status_color` / `_power_supply` return the **literal** strings `"Owned Supply"` / `"Grid"` / `"Not connected"` (an API contract — `_power_status_color` compares `== "Owned Supply"`; do **not** rename to Owned/Grid/None) |
| input/run status | starved = **`not Production.last_turn_run.has(id)`** (or `summary.starved`), NOT `missing_by_building.has(id)` (misses empty-recipe buildings) | RAG via `_input_status_color(building, recipe, is_infrastructure)`; transient state — empty before turn 1 / after load → "—" |
| logistics | derive from inbound/outbound (detail-panel route helpers) | **[design-pending]** exact metric |
| profit / cost | `CostSolver.get_building_unit_cost(id)` vs `Catalog.get_base_price(output_good_id)`; RAG **green <90% / amber 90–110% (inclusive) / red >110%** (matches building_detail_panel.gd:2034) | `-1.0` (unsolved / mined-out) → grey "—"; only the `pct→color` band is reusable — `_update_cost_label` also mutates widgets |
| "ran" streak | `Production.full_output_streak_by_building.get(id,0)` | ⚠️ this counts **consecutive turns the building RAN**, not "full output" — label it "turns running", not "full output streak" |
| lifetime produced | `Production.produced_by_building.get(id,{})` (`_produced_since_construction`) | nested `id → {good_key → qty}`; power output is keyed by the **literal `"power"`**, not a good_id — special-case it |
| land used | `Catalog…tile_size_used × BuildingLevels.mult("size", level)` (`SIZE_MULT = {1:1.0, 2:1.8, 3:2.5}`) | **reuse `MatchState.get_tile_space_used(tile)` (match_state.gd:618)** rather than recompute; `BuildingLevels` is **not** an autoload — `const BuildingLevels := preload("res://scripts/building_levels.gd")` |
| actions | per-row buttons (focus / upgrade / demolish) | mirror multi-select bar (§6.4) |

**Under-construction rows** (separate group) use the construction project dict instead:
`status` (the **string** consts `"under_construction"` / `"awaiting_materials"`), `turns_remaining`
(⚠️ **frozen** while `awaiting_materials`; reset to `construction_duration` when materials are claimed),
`Construction.materials_eta(project)` (⚠️ returns **`-1` whenever no missing material has an inbound
shipment** — not "ready"; `0` = arriving this/next turn), `required_materials` vs `missing_materials`,
`build_cost`, and `source` (`{kind:"market"}` / `{kind:"tile", from_tile_id}`). Reuse the same
name/tile/recipe columns; status/profit columns show "—".

Reusable helpers to **lift from `building_detail_panel.gd`** into a shared `building_status.gd`
(recommended, to avoid drift): `_input_status_color`, `_power_status_color`, `_power_supply`,
the `pct→color` band of `_update_cost_label`, `_produced_since_construction`, `_full_output_streak`,
`_maintenance_cost`, and the `_primary_output_*` family (there is **no** plain `_primary_output` — it's
`_primary_output_good_id` / `_internal` / `_qty` / `_display_name`). Extraction caveats:

- `_power_supply`'s return strings are a **contract**; preserve the exact literals.
- `_update_cost_label` **mutates** `_cost_label`/`_cost_wrapper` and applies a `StyleBoxFlat` — extract
  only the pure `pct→color` decision, not the widget side-effects.
- `_maintenance_cost(building_data)` takes the **catalog record** (not the instance) and relies on a
  null-guard (`maintenance_cost` is `null` when the CSV cell is blank).
- Helpers take **three different argument types** (instance dict vs catalog record vs recipe dict) and
  pull transitive deps (`_recipe_deposit_exhausted`, `_flow_output_items`, `_produced_good_display_name`)
  plus the file-local `STATUS_*` color consts — move those together or keep them in the panel.
- These helpers read transient autoload state (`last_turn_run`, `missing_by_building`, `last_result`)
  that is **cleared on load** and before turn 1, so a ledger refreshed at those moments shows "—"/grey
  until the first turn resolves. That's expected, not a bug.

---

## 5. Backend additions (the only new engine code)

> **Phase 1 backend is implemented and tested** (suite green, +14 assertions in
> `tests/test_runner.gd:_test_refund`). §5.1–5.2 below are ✅ done; §5.3 (the demolish dialog +
> actual removal) is the UI phase and still deferred.

### 5.1 ✅ Carry construction cost onto the building instance (enables `refund_cost`)
The build cost was **lost at promotion**: `Construction._promote → _complete_build →
MatchState.add_building` stored only `{instance_id, building_id, recipe_id, tile_id, owner, level}`.
**Done** (construction.gd:`_promote`): after `_complete_build`, the live instance is stamped with
`build_cost` (money actually paid, density-aware) and `build_materials` (the consumed kit,
`good_id → qty`, a duplicate of `project.required_materials`). These ride in `MatchState.buildings`,
so save/load persists them for free. Buildings that never went through a timed project (zero-duration
builds, start buildings) lack the fields — `refund_cost` falls back to `Catalog` (§5.2). Covered by
the "promotion stamps …" tests.

### 5.2 ✅ `MatchState.refund_cost` + `refund_plan`
**`refund_cost(instance_id) -> {money, materials, materials_value, total}`** — pure, no side-effects.
The refund is the build money **plus every material kit consumed over the building's life**:
- **money** = stamped `build_cost` (or the Catalog `base_price` = `build_cost_money` fallback).
- **materials** (`good_id → qty`) = the construction kit (stamped `build_materials`, or
  `Construction.requirements_for(building_id)` fallback) **plus, for an upgraded building, every
  completed upgrade level's kit** `BuildingLevels.upgrade_materials(internal, lvl)` for `lvl` in
  `2..level`. (Upgrade kits are keyed by **internal_name** → converted to good_id via
  `Catalog.get_good_by_internal_name`.) So demolishing an **L3 returns all three levels' materials**
  (e.g. Mine L3 → `large_engine ×5` = L2 1 + L3 4, `computer ×2`, base kit ×2 levels, …).
- Everything is scaled by **`EconomyConfig.demolish_refund_share`** (a tunable **`var`, default `1.0`**
  = 100% refund; rounded for material qty). `materials_value` = the kit at **current market price**
  (`MarketState.get_price`); `total` = money + materials_value (the all-cash-equivalent headline).

**`refund_plan(instance_id) -> {money, to_stockpile, cash_overflow, fits_fully, …}`** — the payout
split given the tile's storage room. Materials go back to the building's **tile stockpile up to its
free capacity** (`Stockpile.get_free_capacity`); whatever **won't fit is offered as cash** at current
market price. `fits_fully == false` is the signal to **pop the cash-offer dialog** (§5.3). Pure —
reads capacity/prices, mutates nothing. (`Stockpile.add` silently drops overflow past capacity, which
is exactly why we plan the split up front rather than dumping and losing materials.)

- **£0 case:** infra and any building with no money cost and no materials yield `total == 0` — hide or
  relabel the Demolish/refund affordance so a £0 refund doesn't read as a bug (§9.7).

### 5.3 Demolish flow + cash-offer dialog (removal DEFERRED this pass)
Clicking **Demolish** on a row opens a **confirmation dialog** showing `refund_cost` (build money +
the material kit as an icon grid + the headline total). When `refund_plan(...).fits_fully` is
**false**, the dialog presents the **cash offer**: "Your stockpile can't hold N of these materials —
take £X cash for them this turn?" (X = `cash_overflow` at market price), with the in-room materials
still returned to the tile. **Confirming does NOT remove the building yet** — the actual removal +
credit is out of scope this pass (stub the confirm handler with `# TODO` + toast/log). When
implemented later it will: apply `refund_plan` (`add_money(money + cash_overflow)` and
`Stockpile.add(to_stockpile)`), then `remove_building(instance_id)`. **Also clear the leak:**
`remove_building` erases `tile_buildings`/`output_stockpile_destinations` but **not** `input_tile_only`
(keyed `"instance_id|good_id"`, match_state.gd:42) — the future removal path must clear those too.

### 5.4 Under-construction cancel (existing, reuse — do not demolish)
For under-construction rows, "demolish" must route to **`Construction.cancel(instance_id)`** (returns
bool), which refunds the full `build_cost` via `add_money`, returns already-**secured** materials to
the tile, erases the project, and emits `construction_cancelled(instance_id, tile_id)`. This is
*different* from the live-building demolish above and is already wired in the detail panel
(building_detail_panel.gd:512). It does **not** recall in-transit shipments — they still arrive as
ordinary tile stock.

### 5.5 Upgrade (reuse, do not re-add)
`start_upgrade(instance_id, mode)` already exists and returns `{ok, reason?, missing?, required?, …}`;
modes are `tile` / `market` / `transfer` (unknown mode rejected). `is_upgrading` gates re-entry;
`cancel_upgrade` re-banks the in-progress kit to the **tile stockpile** (not money). Single-building
upgrade opens the existing `upgrade_dialog`; multi-building upgrade uses the **grid dialog** in §9.4.

### 5.6 Signals
**Add no new signal.** The ledger refreshes on `building_added` (payload is the full **instance dict**),
`building_removed` / `building_upgraded` / `building_upgrade_started`(→target level, at queue time) /
`building_upgrade_progress` / `building_upgrade_cancelled` (all payload = **instance_id String**),
the **construction** set (§7), and `TurnManager.turn_resolution_completed` (no payload). Note the
asymmetric payloads. There is **no** `building_upgrade_completed` (completion = `building_upgraded`)
and **no** `construction_progress`.

---

## 6. UI plan

### 6.1 Reuse
- **Filter/search bar:** `market_panel._build_filter_row` pattern (LineEdit + toggle buttons),
  `_apply_filters` iterate-and-toggle `row.visible` (it does **not** reorder).
- **Header row:** `market_panel._rebuild_header` — headers are plain `Label`s with **no** click-to-sort.
  Sort is net-new (§6.3).
- **Row builder:** `market_row.setup(Dictionary)` pattern (HBox built in code; row scene is an empty
  container). ⚠️ `setup` self-subscribes to `CostSolver.costs_updated` + `Production.turn_processed`
  (guarded by `is_connected`) — keep that guard if you copy it, to avoid duplicate connections.
- **Per-good post-turn data** (if needed) comes from `Production.turn_processed(summary)` /
  `Production.last_turn_summary` — `turn_resolution_completed` carries **no payload**.

### 6.2 Filters & search [design-pending exact set]
Search box (name/output) + toggle chips for: category (production/power/infra/**battery**),
starved/running, powered/unpowered, profitable/loss-making, has-upgrade-available. Mirror `_apply_filters`.

### 6.3 Sort
No existing sortable-header widget → implement: a `sort_key`/`sort_asc` state, clickable headers
(headers are inert Labels today — add a `gui_input`/`pressed` handler), re-sort the row-model before
render. Sensible keys: name, tile, profit%, land, status.

### 6.4 Multi-select + action bar (build from scratch)
- Per-row `CheckBox`; panel keeps `_selected: Dictionary<instance_id,bool>` (Set). Closest existing
  pattern is `good_select_panel.gd`'s `_row_meta` (bespoke, not a reusable widget) — reference, not reuse.
- A header checkbox = select-all-visible (respects filters); show a **tri-state** (none/some/all).
- An action bar (hidden until ≥1 selected) with **Upgrade · Demolish** + the selected count.
- **Selection lifecycle (required):** on **every** row-model rebuild, **prune `_selected` to currently
  visible instance_ids** (ids vanish on sell/demolish and change group on construction promotion),
  recompute the header tri-state, and re-evaluate action-bar enablement. **Clear selection after a
  destructive op completes.**
- **Affordability — gate at click-time, don't pre-disable.** Upgrade affordability depends on
  money/materials (`money_changed`, `Stockpile.stockpile_changed`) which are **not** in the refresh
  list; rather than subscribe to keep a disabled state fresh, let the shared API reject and toast on
  click. Only disable for *structural* reasons that the refresh list already covers (all selected
  maxed/upgrading).
- **Demolish (single):** opens the `refund_cost` dialog (§5.3); if `refund_plan().fits_fully` is false,
  it shows the **cash-offer** for the materials that won't fit on the tile — **removal still deferred**.
- **Demolish (bulk):** a **button with no effect** for now (no-op; explicitly out of scope this pass).
- **Confirm UX:** there is **no shared confirm helper** — every site builds `ConfirmationDialog.new()`
  ad hoc (e.g. building_detail_panel.gd:1195). Build **one reusable confirm** with `"{verb} {N}
  buildings for {total}?"` copy, a **double/typed-confirm threshold** for large N, and a post-op result
  toast reporting successes **and** skips/failures separately ("Sold 3, skipped 2 (upgrading)").
  (Lands fully when removal is implemented; scaffold it now.)

### 6.5 Row click → focus (deep-link)
On row **body** click (not on the checkbox/action buttons): `MatchState.focus_building_requested(id)`
(the ledger must **emit** this — it doesn't today). The handler (world_map.gd:983) **jumps** the camera
and opens the **detail panel**. **Hide the ledger first** (`close_requested` / `_set_panel_visible(false)`)
so the focused tile + detail panel are visible — and verify z-order rather than assume (the handler only
`move_to_front()`s the detail panel; on 1920px both overlap x≈1022–1350). Decision §9.3.

### 6.6 Panel shell [design-pending]
Keep the draggable sized panel, or switch to a fullscreen `HUDContent`-anchored `Control` (like
`research_panel`) if the mockup is a full-width table. Decide after the import. Either way: keep
`close_requested` + `PanelStack` wiring, and remember Esc bypasses `close_requested`.

---

## 7. Refresh strategy
- **On open:** full rebuild of the row-model + render. Only rebuild while **visible** (guard each
  handler with `if not visible: return`, exactly as `building_detail_panel.gd:520/966/973` does).
- **Power column — recheck every turn from production's last-turn state.** Do **not** drive the power
  column off live `Power.is_supplied` alone (it's a cables-present topological check that can flip
  mid-turn when a cable finishes via `construction_completed`, with no `building_*` signal). Instead,
  **recompute the power column on `turn_resolution_completed`** from `Production.last_turn_run`
  (a production building that ran was cabled + fed) combined with the recipe's energy requirement and
  current `is_supplied(tile_id)`. This makes the column a **per-turn snapshot**: accurate as of the
  last resolved turn, with a deliberate one-turn lag for a cable built mid-turn. (No need to wire
  construction signals just for power.)
- **Per turn:** rebuild on `TurnManager.turn_resolution_completed` — status, profit/cost, streak,
  produced and the power snapshot are all freshest then (`CostSolver.solve` runs at production.gd:337,
  and `turn_resolution_completed` fires **last**, turn_manager.gd:128, so it already captures
  `costs_updated`/`modifiers_changed` — no need to subscribe to those separately).
- **On structural change:** `building_added` / `building_removed` / `building_upgraded` /
  `building_upgrade_started/_progress/_cancelled` → rebuild. ⚠️ `building_upgrade_progress` fires **every
  turn per in-progress upgrade** — update the affected row in place, don't tear down the whole table.
- **Under-construction group:** rebuild on the explicit **construction** set —
  `construction_started`, `construction_completed`, `construction_cancelled`, `materials_ordered`,
  `construction_materials_updated` (mirroring building_detail_panel.gd:188; there is **no**
  `construction_progress`). `materials_eta`/`turns_remaining` are per-turn quantities, so
  `turn_resolution_completed` keeps them fresh too.
- **Debounce:** several signals can fire in one frame (a future single demolish emits up to ~3; a bulk
  op ~20–30). Set a `_dirty` flag per signal and do **one** `call_deferred` rebuild that clears it.
  There's **no** existing debounce precedent in sibling panels, so this is net-new (small) plumbing.

---

## 8. Edge cases & gotchas (verified)
- **Trust the code, not the comment:** `match_state.gd:24-25` describes the building shape as
  `{… tile_coord, owner}` — **stale**. The real fields are `{instance_id, building_id, recipe_id,
  tile_id, owner, level}` (+ the new `build_cost`/`build_materials` from §5.1). Use `tile_id`, not
  `tile_coord`.
- `Production.last_turn_run` and `missing_by_building` are **cleared at the start of each PROCESS**
  (and on load); read after `turn_resolution_completed`. Before turn 1 / mid-turn / post-load → empty
  → show "—".
- Starvation = **`not last_turn_run.has(id)`** (or `summary.starved`), not `missing_by_building.has(id)`
  — empty-recipe buildings are `has_run=true` yet absent from both dicts.
- `full_output_streak_by_building` increments whenever a building **runs** (not only at full output)
  and is **zeroed on any non-run**; it persists across save/load. Label it "turns running".
- `produced_by_building` is `id → {good_key → lifetime qty}`; **power output is keyed by the literal
  string `"power"`**, normal goods by `good_id`. Persisted across save/load.
- `CostSolver.last_result` starts as `{"per_building": {}, "per_good": {}}`; `get_building_unit_cost`
  returns **`-1.0`** until the first PROCESS solve (and after a fresh load) → render grey "—".
- `Power.is_supplied(tile_id, _energy_req=0)` checks **only cables present** (the `energy_req` arg is
  unused); actual balance is settled in `settle_grid_transactions`. It also ignores cable **level**.
- `materials_eta(project)` returns `-1` whenever no still-missing material has an inbound shipment
  (incl. fully-stocked `under_construction` projects) — not "ready". `0` = arriving this/next turn.
- `turns_remaining` is **frozen** for `awaiting_materials` and **reset** to `construction_duration`
  when `claim_materials` flips it to `under_construction` — distinguish the two states.
- Construction projects are NOT in `MatchState.buildings` until promotion; the degenerate zero-duration
  build path **never** enters `construction_projects` (promotes synchronously) — such buildings show
  only as finished buildings, never as projects, and lack `build_materials` (use the §5.2 fallback).
- `remove_building` gives **no money back** and leaves stale `input_tile_only` entries (§5.3).
- Infrastructure has no recipe/profit → filter out by default or blank its status columns.
- NPC-owned buildings (`owner != "player_1"`) must be excluded from rows AND from upgrade/demolish.
  (`is_player_owned` treats owner-less buildings as the player's.)

---

## 9. Open decisions (recommendations)
1. **Refund payout form** — *Decided & implemented (compute side):* `refund_plan` returns build money
   as cash + **materials to the tile stockpile up to free capacity**, with **overflow offered as cash**
   at market price (the cash-offer dialog, §5.3). `demolish_refund_share` (a `var`) defaults to **1.0**
   (full refund as specified); lower it later if demolish-rebuild churn is too cheap. Refund **includes
   every upgrade level's materials** (an L3 refunds all 3 levels).
2. **Demolish while upgrading** — *Rec:* the future removal path goes through `remove_building`, which
   already `cancel_upgrade`s (re-banking the in-progress kit to the tile). For now removal is deferred,
   so the dialog can simply note an upgrade is in progress.
3. **Row click vs ledger visibility** — *Rec:* hide ledger on focus (detail panel takes over). Verify
   z-order empirically before locking. *Alt:* keep ledger open, just jump the camera.
4. **Multi-upgrade** — *Rec:* the **grid dialog** below.
5. **New refresh signal** — *Rec:* none (existing signals + per-turn suffice).
6. **Panel form** — *Rec:* decide from the design (sized draggable vs fullscreen). **[design-pending]**
7. **£0 refund** — *Rec:* hide/relabel Demolish-refund when `total` rounds to 0 (infra, zero-cost builds).

### 9.4 Multi-upgrade — extended upgrade dialog with a building grid
For a multi-selection Upgrade, do **not** blind-fire `start_upgrade(id,"tile")` per building — `tile`
mode returns `{ok:false}` for every building whose materials aren't already staged on-tile (the common
case), so it would silently no-op. Instead:

- Add `upgrade_dialog.open_batch(instance_ids: Array)`. It reuses the existing code-built shell
  (`_card`/`_content`, scrim, CenterContainer) and **extends** it with a **building grid**.
- For each selected building, call `preview_upgrade(id)` to determine whether **on-tile resources
  suffice** (the preview's `missing`/`required` fields). Flag each cell accordingly (e.g. green =
  on-tile ready, amber = needs market/transfer sourcing, grey = maxed/ineligible).
- **Grid layout:** a `GridContainer` of **max 4 columns × 4 rows = 16** building cells (icon + short
  name + the on-tile/needs-sourcing flag). If **more than 16** are selected, render the first 16 and add
  a **5th row** with a single cell reading **"+X more"** where `X = selected_count − 16`.
- One **sourcing choice applies to all** (tile / market / transfer), mirroring the single-building CTAs.
  On commit, call `start_upgrade(id, mode)` per building, **collect the result dicts**, skip those that
  return `{ok:false}`, and **toast a summary** ("Upgraded 7, skipped 3 (insufficient materials)").
- Re-entry/eligibility: skip buildings where `is_upgrading(id)` or already at `MAX_LEVEL`.

---

## 10. Testing plan (tests/test_runner.gd, pure-logic)
- ✅ **Carry construction cost (§5.1):** `_test_refund` seeds a project and calls `Construction._promote`
  → asserts the live instance carries `build_cost` + `build_materials`.
- ✅ **`refund_cost` (§5.2):** L1 returns build kit + money; **L3 sums all upgrade kits** (Mine:
  `large_engine ×5`, `computer ×2`, base kit ×2 levels); `demolish_refund_share` scales money + qty;
  Catalog fallback when the instance has no stamped fields.
- ✅ **`refund_plan` (§5.2):** with a near-full tile, only what fits is returned to the stockpile and the
  overflow is valued as cash at market price (`fits_fully == false`).
- *(later)* **Row sourcing:** seed player + NPC + infra + battery buildings → row-model includes only
  player rows; infra/battery filters toggle correctly; construction projects appear in the
  under-construction group (and the degenerate zero-duration build appears only as a finished building).
- *(later)* **Status mapping:** with stubbed `last_turn_run` / `missing_by_building` / `last_result`, the VM
  computes running/starved (via `last_turn_run`), the **per-turn power snapshot**, and profit RAG
  correctly — grey when `unit_cost == -1.0`; "—" when last-turn state is empty.
- **Construction cancel route (§5.4):** `Construction.cancel` refunds `build_cost` + secured materials,
  emits `construction_cancelled`, and the under-construction "demolish" routes here, not `remove_building`.
- **Multi-upgrade eligibility (§9.4):** given a mixed selection, the dialog classifies each building as
  on-tile-ready / needs-sourcing / ineligible; >16 selected yields 16 cells + a "+X more" row.
- **Selection lifecycle:** removing/repromoting an id prunes it from `_selected` on rebuild and updates
  the header tri-state + count.
- **Filter/sort:** filter predicates and sort comparators over a fixed row set.

## 11. Phasing
1. **Backend** — ✅ **done & green:** §5.1 carry-cost-at-promotion, `refund_cost` (with upgrade-level
   increments + `demolish_refund_share`), `refund_plan` (stockpile-room/cash split), + tests. Shared
   `scripts/building_status.gd` **extracted** (static, pure helpers — RAG colours, `power_supply`
   contract strings, `cost_rag_color` band split out of `_update_cost_label`, primary-output, produced,
   streak, maintenance); `building_detail_panel.gd` now **delegates** to it (single source of truth,
   suite green).
2. **Read-only ledger** — ✅ **done:** `scenes/building_ledger_panel.tscn` reduced to a clean shell and
   `scripts/building_ledger_panel.gd` rewritten as a real table — toolbar (count + relocated routing
   selector), header row, scrolling rows built from a per-building row-model. Columns: Building / Tile /
   Type / Output / Lv / Power (per-turn snapshot, RAG dot) / Status (running/starved/idle, RAG dot) /
   Cost-per-unit (RAG-coloured £, grey when unsolved) / Land (level-scaled). Per-turn + structural +
   construction refresh with a `_dirty` debounce and a visible-only guard; row-click emits
   `focus_building_requested` then `close_requested` (pan + detail, ledger hides). Verified headless
   (instantiation test) and visually (`tools/ledger_shot.tscn`). No actions yet.
3. **Filters / search / sort** — ✅ **done:** a filter bar (search over name/output + toggle chips
   Running · Starved · Unpowered · Loss-making · Upgradable; Running/Starved mutually exclusive) and
   **click-to-sort headers** (every column; ▲/▼ indicator; tap toggles asc/desc). Rendering is split —
   `_rebuild()` recomputes the cached row-model on data change; `_render()` filters + sorts + rebuilds
   the row widgets on a filter/sort change without recomputing data. Count shows "N of M buildings"
   when filtered. Suite green; verified visually (`tools/ledger_shot.tscn`).
4. **Multi-select + action bar:** Upgrade (single dialog / batch grid dialog §9.4), **Demolish (single)
   → refund_cost dialog (no removal)**, **bulk Demolish (no-op button)**, confirm scaffold, toasts.
5. **Under-construction group** (construction signal set + cancel route).
6. **Design polish** once `Building Ledger.html` is imported — align columns/layout/styling.
7. *(Later, out of this pass)* implement actual demolish removal + refund credit (`add_money` + return
   materials, then `remove_building`, clearing `input_tile_only`).

## 12. Risks
- **Helper duplication:** copying RAG/status logic risks drift — extract to `building_status.gd`,
  preserving the `_power_supply` string contract and the `pct→color`/widget split.
- **Performance is node churn, not queries.** `CostSolver.get_building_unit_cost` and `Power.is_supplied`
  are **O(1) cache lookups** against `last_result`/tile state — the data side is essentially free. The
  real cost is rebuilding Godot Control nodes per row. Mitigation that matters: **reuse row nodes**
  (update labels in place), and never full-rebuild on `building_upgrade_progress`. Don't optimize the
  queries.
- **Region grouping is a data dependency.** If the design groups by region, the row-model must gain a
  derived region key (no region field exists today) — so §13's "design only touches rendering" has this
  one hole. Acknowledge it.
- **Localization / formatting:** new strings (column headers, filter chips, action/confirm/toast copy)
  must route through the project's l10n path (or note there is none), with toast **pluralization** and
  number/£ formatting specified ("Sold 1 building" vs "Sold 3 buildings").
- **Accessibility / Esc:** define keyboard nav and Esc/`PanelStack` interplay when a confirm dialog is
  open over the ledger (Esc is overloaded — pop vs `close_requested`).
- **Refund balance:** `DEMOLISH_REFUND_PCT` (default 1.0) may need tuning so demolish-rebuild churn
  isn't free; a full refund makes build→demolish break-even.

## 13. Pending the design import (`/design-login` → fetch `Building Ledger.html`)
The HTML will pin down: exact column set/order/widths, filter affordances (chips vs dropdowns), sort
indicators, action-bar placement/labels, the under-construction grouping presentation, the demolish/
refund dialog styling, and whether the ledger is a sized draggable panel or a fullscreen table.
Everything in §1–§12 holds regardless; only §4 (column list), §6 (layout/filters), and §6.6 (panel
form) get refined — **except** region grouping (§9.6/§12), whose *data* the row-model doesn't carry yet.

## 14. Changelog (this revision)
Corrections applied after re-verifying against the tree:
- Building money cost field on the dict is **`base_price`** (sourced from the `build_cost_money` CSV
  column), not `build_cost_money`.
- Category has a **4th value, `battery`** (don't hardcode 3).
- `_power_supply` returns **`"Owned Supply"` / `"Grid"` / `"Not connected"`** (contract strings), not
  Owned/Grid/None.
- Starvation test is **`not last_turn_run.has(id)`** / `summary.starved`, not `missing_by_building.has(id)`.
- `full_output_streak_by_building` is **"turns running"**, not full-output.
- `start_upgrade` returns a **Dictionary** `{ok,…}` (modes tile/market/transfer), not bool/void.
- Camera focus is an **instant jump**, not a pan.
- No `_primary_output` — only `_primary_output_*` variants.
- `BuildingLevels` is **not an autoload** (preload it); reuse `get_tile_space_used` for land.
- `materials_eta` returns `-1` in more cases than "ready"; `turns_remaining` is frozen for awaiting.
- `building_ledger_panel` **section1 is a live control** (Transport routing); the `.tscn` has extra demo
  nodes beyond "3 cards".
- `turn_resolution_completed` has **no payload**; per-good data uses `Production.turn_processed` /
  `last_turn_summary`.
- `produced_by_building` keys power as the literal **`"power"`**.
- `remove_building` leaves stale **`input_tile_only`** entries; gives no money back.
- The construction signal set is explicit (no `construction_progress`); `building_added` payload is the
  full **instance dict** while the rest carry **instance_id**.
- Stale building-shape comment at `match_state.gd:24-25`.

Design changes applied:
- **Salvage/`sell_building` removed**; replaced by **demolish + `refund_cost`** shown in a **dialog**;
  **removal deferred**, **bulk demolish is a no-op button**.
- Refund = `build_cost_money` **+ every material kit consumed over the building's life** (construction
  kit + each completed upgrade level — an L3 refunds all 3 levels), scaled by tunable
  **`EconomyConfig.demolish_refund_share` (`var`, default 1.0 = 100%)**.
- **`refund_plan`**: materials returned to the tile stockpile up to free capacity; **overflow offered as
  cash** at market price (cash-offer dialog when `fits_fully` is false).
- Build cost (money + materials) **carried onto the building instance at promotion** to make `refund_cost`
  exact and density-aware.
- **Multi-upgrade grid dialog** (4×4 max, "+X more" row beyond 16; per-building on-tile sufficiency flag).
- **Power column rechecked every turn** from `Production.last_turn_run` (per-turn snapshot).

Phase 1 backend **implemented & green** (suite 0 failures): `EconomyConfig.demolish_refund_share`,
promotion cost-stamping (construction.gd `_promote`), `MatchState.refund_cost` + `refund_plan`, and
`tests/test_runner.gd:_test_refund` (14 assertions). Still open in Phase 1: extract `building_status.gd`.

Additions applied: O(1)-query/node-churn perf re-framing; click-time affordability gating; selection
lifecycle (prune-to-visible + tri-state + clear-after-op); reusable confirm with partial-failure
reporting; region-grouping data-dependency caveat; £0-refund handling; construction-cancel + bulk
partial-failure + stale-selection tests; localization/pluralization + accessibility/Esc notes.
