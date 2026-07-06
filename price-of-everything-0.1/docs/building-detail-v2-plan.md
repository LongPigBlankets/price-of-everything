# Building Detail Panel v2 — redesign plan (behind `swap bdp`)

Status: **shipped (Phase 3, 2026-07-06)** — the v2 panel is now the DEFAULT (`MatchState.use_bdp_v2`
default true). The classic v1 panel is retained as a fallback via the `swap bdp` cheat; full v1 removal
is a later cleanup. Origin: offline React prototype "Building Detail — Price of Everything"
(scenario showcase). This doc is the porting plan from that prototype to a live Godot panel,
shipped dark behind a debug cheat and promoted the same way `tile_info_panel_v2` was.

---

## 1. What v2 is (and isn't)

v2 is a **presentation + information-architecture** rewrite of the read path. The current panel
([`scripts/building_detail_panel.gd`](../scripts/building_detail_panel.gd), ~3,240 lines) already
**computes every number** v2 displays — imputed cost/RAG (`_update_cost_label`), the four status
colours (`_power_status_color` / `_input_status_color` / `_transport_*_status_color`), power
sources (`_add_power_sources_section`), net modifier % (`_update_mod_label`), labour, maintenance,
inbound shipments, construction ETAs. So v2 is not new economics — it's a new arrangement.

Two genuinely new UI concepts from the prototype:

1. **Always-open Diagnostics checklist** — ranked ok/warn/bad/info rows synthesised from signals
   the panel already has (prototype `buildDiagnostics()`). Replaces scattered `Field: value` text.
2. **Economics card with a headline `Net / turn`** = output value − maintenance − labour.

Layout: metallic silver frame → header (type icon + name + status badge + level + tile) → banner
image → **adaptive recipe/flow strip** → **Diagnostics** → **Economics (Net/turn)** → labour split
cards → inbound-shipment cards. Construction swaps the body for a materials checklist + countdown +
cancel.

## 2. Locked design decisions

- **Panel model: floating single.** v2 keeps the current floating / draggable / docks-left-of-tile
  behaviour and `PanelStack` registration, but **drops the multi-panel (up-to-4) system**. "Go to
  supplier/consumer" re-targets the *same* v2 panel via `show_building` (optional back-stack later).
- **Routing: kept in v2.** The interactive Inputs/Outputs buttons, stockpile-destination selection,
  and the `building_connections_changed` map-highlight signal are ported into v2 (Phase 1), not
  dropped. No routing regression versus today.

## 3. Scenario matrix (what v2 must render)

Prototype ships 9; v2 must also cover **NPC** (prototype omitted it). Map to current render branches:

| # | Scenario | Prototype | Current branch in `_rebuild_fields` |
|---|---|---|---|
| 1 | Thermal power (fuel → power) | ✔ | recipe flow, output_name=="power" |
| 2 | Renewable power (no inputs → power) | ✔ | recipe flow, no inputs |
| 3 | Production (inputs + power → output, Δ%) | ✔ | recipe flow (main path) |
| 4 | Liquid + pipeline (stalled) | ✔ | recipe flow + `_pipe_problem` |
| 5 | Battery (stores energy, no recipe) | ✔ | `category=="battery"` → `_show_storage_diagram` |
| 6 | Infrastructure (throughput, no recipe) | ✔ | `is_infrastructure` |
| 7 | Port (market connection + lanes) | ✔ | *new surfacing* (ports.csv / transport cap) |
| 8 | Construction — awaiting materials | ✔ | `_render_construction_mode` (awaiting) |
| 9 | Construction — build countdown | ✔ | `_render_construction_mode` (building) |
| 10 | **NPC-owned (frosted "operated by X")** | �’✗ MISSING | `_resolve_owner_id` → `_apply_npc_mode` |

New data to surface (not in panel today): infra **throughput bar** and port **lanes** (7 & 6).

## 4. Key architecture move: extract a shared readout layer

Before building v2, extract the **pure computation** helpers out of `building_detail_panel.gd`
into `scripts/building_readout.gd` (RefCounted, no Nodes). Both v1 and v2 render from identical
numbers — otherwise v2 forks balance-sensitive logic (imputed cost, routing, status) and they
drift. This turns `buildDiagnostics()` into a thin GDScript port over the shared layer.

Candidates to move (pure, no widget building): `_output_route_summary`, `_maintenance_cost`,
`_labour_cost`, `_power_status_color` / `_input_status_color` / `_transport_*_status_color`,
`get_power_sources` wrapper, `_modified_output_qty`, modifier-net computation (`_update_mod_label`
math), CostSolver read (`_update_cost_label` math). Keep them side-effect free and unit-testable.

## 5. The `swap bdp` cheat + seam (proven pattern)

Exact precedent: `tile_info_panel_v2` shipped behind `MatchState.use_alt_tvp`, toggled by console
`swap tvp`, then v1 deleted + renamed once proven (commits f16102b → e48bd67). Copy it.

**Cheat wiring**
- `scripts/match_state.gd` (~L339, by `use_alt_bottom_menu`): add `var use_bdp_v2: bool = false`
  (**default false — ship dark**), a `set_use_bdp_v2()` / `toggle_use_bdp_v2()` (~L2237), and a
  `bdp_v2_changed(enabled: bool)` signal (~L429).
- `scripts/debug_terminal.gd` `_run_command()` (~L126, next to `swap bottom menu`): add
  `swap bdp` → `MatchState.toggle_use_bdp_v2()`.

**Panel seam** — all opens funnel through `building_panel.show_building(building)`:
- `world_map.gd` — instantiate `building_panel_v2 = load("res://scripts/building_detail_panel_v2.gd").new()`
  in `_build_base()`, name it `BuildingDetailPanelV2`, add to `HUDContent`, hide it.
- Add `func _active_building_panel() -> PanelContainer: return building_panel_v2 if (MatchState.use_bdp_v2 and building_panel_v2) else building_panel`.
- Route the two open sites through it: `_on_v2_building_clicked` (L414) and
  `_on_focus_building_requested` (L1120). Also connect `building_panel_v2.building_connections_changed`
  the same way v1 is at L188.
- On `bdp_v2_changed`: hide both, re-open `_last_selected` building in the active one (mirror
  `_on_alt_tvp_changed`).
- Entry points unchanged upstream: ledger row → `MatchState.focus_building_requested` →
  `_on_focus_building_requested`; tile click → `tile_info_panel_v2.building_clicked`.

## 6. Phases

**Phase 0 — Seam + cheat. ✅ DONE (2026-07-05).** Shipped:
- `MatchState.use_bdp_v2` (default false), `bdp_v2_changed` signal, `set/toggle_use_bdp_v2()`.
- `debug_terminal.gd`: `swap bdp` command + help entries.
- `world_map.gd`: `building_panel_v2` code-instantiated in `_build_base()` (node `BuildingDetailPanelV2`),
  `_active_building_panel()` routes both open sites + a `_hide_building_detail()` helper; the toggle
  handler `_on_bdp_v2_changed` re-renders `_last_detail_building` in the now-active panel.
- `scripts/building_detail_panel_v2.gd` — DS-themed floating stub (header + subtitle + amber
  "Phase 0 stub" marker + value/category/instance + note), PanelStack-registered, header-drag,
  right-dock positioning, emits `building_connections_changed`.
- Verified: unit suite **1165 passed / 0 failed**; windowed shot `tools/bdp_v2_shot.tscn` →
  `/tmp/poe_bdp_v1.png` (classic) + `/tmp/poe_bdp_v2.png` (v2 stub) confirm the live swap.
- Gotcha fixed: autowrap labels in a plain-Control parent ballooned the panel height on the first
  layout pass — bounded label widths + `reset_size()` + explicit size in `_position_panel()`.

**Phase 1 — Read-only core + routing. 🔵 IN PROGRESS.**

*Increment 1 (DONE 2026-07-05) — the read-only heart:*
- `scripts/building_readout.gd` — shared, UI-agnostic aggregator over `BuildingStatus` +
  `CostSolver` (thin: BuildingStatus already is the single source of truth for RAG colours,
  `net_output_modifier`, `produce_cost_status`, `effective_output_qty/energy`, `selected_output_route`).
  Exposes `status / flow / economics / labour / power / diagnostics`.
- `building_detail_panel_v2.gd` rebuilt: status badge (RAG-consistent) → adaptive recipe strip
  (real framed good icons, power pill, arrow, modified-qty) → **always-open Diagnostics checklist**
  → Economics card → power line → Labour split cards. Scrolling body (no balloon), DS-themed.
- **Economics decision:** no engine per-building per-turn profit exists, and the prototype's
  "Net/turn = value − maint − labour" mixes asset value with flows (meaningless). v2 shows real
  cash flows (Maintenance/turn, Labour/turn, **Running cost/turn**) + the engine's actual
  profitability signal, **Cost-to-produce vs market** (RAG). Revisit if a true P&L basis is chosen.
- Verified: unit suite **1165/0**; `tools/bdp_v2_shot.tscn` demos b_007 running r_009 (Motor
  Manufacture) → recipe strip + diagnostics (Cannot run / Powered / Starved) all live.

*Increment 2 (DONE 2026-07-05) — live data + shipments + routing + refinements:*
- **Refresh-coalescing** wired: `_queue_refresh`/`_apply_refresh` (one rebuild per frame; catches
  up on `visibility_changed`) connected to costs_updated / modifiers_changed / workforce /
  stockpile / transport / output-dest / deposits / turn_processed / upgrade signals. Refresh
  re-reads the live building and keeps the current (possibly dragged) position.
- **Inbound shipments** cards (stored/need + inbound qty/ETA), **Routing** summary (input sources +
  output destination via ported `input_sources`/`output_route`), and the **map-highlight** signal
  (`building_connections_changed` with real supplier/consumer tiles, ported connection-finding).
- Owner-requested refinements: (1) **frameless** good icons (`GoodIcons.texture_for`, no metal
  plate) in **independent input & output grids** on the cream strip; (2) labour shown as a
  **headcount** (not per-turn) — the wage is the per-turn figure; (3) **emphasised cost-to-produce**
  — a bold 24px £/unit per output good, coloured green/amber/red vs that good's market price, one
  row per output (multi-output aware).
- Verified: unit suite **1165/0**; shot shows Motor £7.2/unit (green, -28%) + Steel £4.1/unit
  (red, +28%), flat icons, shipments, routing, map highlight.

*Increment 3 (DONE 2026-07-05) — modes, variants, height:*
- **Height** now matches the tile view panel exactly (`_target_height` reads `TileInfoPanel.size.y`;
  fixed-height panel, body scrolls inside) — no more overflow past the bottom menu. Docks left of it.
- **NPC (owner decision: no frost).** NPC-owned buildings show ONLY the recipe strip + a big
  **"OWNED BY [fake company]"** card + a **Buy — £N** button (price = `BuildingPrice.sale_price` →
  `purchase_cost_after_advisor`, matching the Buildings-market listing). Company name is a
  deterministic char-fold pick per owner id (no RNG). Buy reuses `buy_building_dialog.gd` →
  `deduct_money` + `set_building_owner`; `building_owner_changed` refreshes to the full panel.
  Ruins (b_031) show "DISUSED — FORMERLY", no Buy.
- **Construction** mode: recipe strip + awaiting/under-way status + materials checklist
  (secured / arrives-in-N) + Cancel construction (`Construction.cancel`).
- **Battery** → storage card (cells loaded/slots); **infrastructure** → "moves goods, runs no
  recipe" card; recipe-oriented sections (cost/shipments/routing) gate off for these kinds.
- Verified: unit suite **1165/0**; screenshots — normal panel height-matches the tile panel; NPC
  panel shows recipe + "OWNED BY IRONBRIDGE GROUP" + "Buy — £191".

*Increment 4 (DONE 2026-07-05):*
- **Port variant** — `classify` now returns "port" for `b_004`; the BDP shows a "Connected to the
  global market" card. NPC-owned ports render the port card + "OWNED BY [company]" + Buy.
- **Port pinned atop the tile panel** — `tile_info_panel_v2._maybe_add_port_card` adds a SEAPORT
  card (Port · owned-by · Buy — £N) as the first child of the Buildings tab; click → opens the BDP
  (`building_clicked`); Buy uses the same confirm→`deduct_money`+`set_building_owner` flow;
  `building_owner_changed` (already wired) re-renders it as owned.
- **"Restarting" state** — new amber run-state: a building that didn't run but now has all inputs in
  stock AND is powered → badge "Restarting" (amber) + a matching diagnostics row, instead of red
  "Stalled". Shared `run_state()` keeps the badge and checklist in agreement. (Renewables with no
  inputs read as "running" when powered.)
- **Labour card** — now shows `£X.XX/turn` (the wage) with an `N workers` subtitle underneath.
- Verified: unit suite **1165/0**; screenshots — port variant + tile-panel SEAPORT card (owner
  "Nordvik Materials"), amber "Restarting" badge + diagnostics.
- ⚠️ **Flag:** the port Buy price came out as **£18** (`BuildingPrice.sale_price(b_004)`), which looks
  low for a £10k building — worth checking the port valuation before promoting.

*Increment 5 (DONE 2026-07-05) — Phase 1 closed out:*
- **Interactive routing** — the Output-destination row now has choice buttons: **Market** /
  **Store on tile** / **Ship to tile…** (reusing `route_output_to_market` /
  `set_output_stockpile_destination` / `begin_output_stockpile_selection`); the active one is
  highlighted; `output_stockpile_destination_changed` refreshes the panel. (Input sources stay a
  read-only summary.)
- **Construction / battery / infra screenshot-verified.** Construction shows the materials
  checklist (Concrete ×3 … pending delivery) + countdown + Cancel; battery shows the storage card
  (cells loaded/slots); both gate off the recipe-only sections. Fixed a bug where the construction
  materials card was built but never added to the body; material icons now resolve (real internal_name).
- Verified: unit suite **1165/0**, money-clean; screenshots — construction materials, battery
  storage, routing buttons, labour "£43.83/turn · 7,731 workers".

## Phase 1 — COMPLETE ✅ (2026-07-05)

The v2 panel (behind `swap bdp`) now covers the full read path + core interactions: header + status
badge (running / **restarting** / stalled / operational) → adaptive strip (recipe / battery / infra /
**port**) → always-open diagnostics → per-output cost-to-produce (RAG) → economics → power → inbound
shipments → **interactive routing** + map highlight → labour; plus NPC (no frost: recipe + "Owned by
[company]" + Buy), construction, and the tile-panel SEAPORT card. Height matches the tile panel.
## Phase 2 — COMPLETE ✅ (2026-07-05)

Action layer, behind `swap bdp`:
- **Primary-actions row** (Upgrade · Change recipe) after the recipe strip; **Sell / Demolish row**
  under labour. All on player-owned recipe buildings.
- **Upgrade** — the button opens the existing `upgrade_dialog.gd` (reused: material-sourcing modes,
  stat deltas, research gate). Deliberate deviation from "in-panel sheet" — the dialog is mature and
  a sheet would fork ~250 lines and lose the sourcing logic.
- **Change recipe** — in-panel sheet: recipe list (inputs→output·kW), current highlighted, fee/turns
  note; click → `start_retrofit`. Handles the retooling countdown + Cancel.
- **Sell** — in-panel sheet (value + note + "Sell for £N"). New sim `MatchState.sell_building()`:
  credits `BuildingPrice.sale_price`, flips owner → `SOLD_TO_OWNER` NPC (keeps standing, land stays,
  stops running for you); instant. Panel refreshes to the NPC view.
- **Demolish** — in-panel sheet (50%-materials preview + red "Demolish (1 turn)"). New **queued** sim:
  `demolish_queue` (additive save state, tolerant-reader default `{}` — **no SAVE_VERSION bump**),
  `start_demolish`/`cancel_demolish`/`is_demolishing`/`demolish_turns_remaining`, `tick_demolish`
  wired into `production.gd` next to upgrades/retrofits. On completion: refund half the material kits
  to the tile (overflow → cash), **no money**, then `remove_building` frees the land.
- **Balance change (authorized):** `EconomyConfig.demolish_refund_share` 1.0 → **0.5** (owner spec);
  the base an advisor can later modify.
- **Sheet framework** — an in-panel `PanelContainer` overlay (back + title + scroll body) that stacks
  over the whole panel; closed on show/hide.
- Verified: unit suite **1173/0** (8 new sell/demolish asserts incl. save round-trip); e2e **598/4**
  (standing gaps unchanged); screenshots — upgrade dialog, recipe sheet, sell sheet, demolish sheet.

### Phase 2 polish pass (owner tweaks, 2026-07-05)
- Recipe strip: **squared corners + 1.5px navy outline inset 4px** (drawn `_InsetOutline`); fixed
  height (156) with up-to-**2×2** input & output grids; **bigger frameless icons** that stretch to
  the card edges; qty shown as a **navy pill superimposed bottom-right** of each icon (`_qty_pill`,
  reused everywhere via `_flat_good_cell`→`_good_icon_pill`).
- Recipe arrow: **navy filled arrow** (rounded body + drawn triangle head `_ArrowHead`) with the
  power draw + bolt **on the arrow body**.
- Power: a building that hasn't run reads "**ready to draw from the grid**" (not "your own supply");
  own/grid attribution only after it runs (`BuildingReadout.power().state`).
- Economics: added a **Power / turn** line (effective energy × `GRID_BUY_PRICE`) folded into Running
  cost.
- Diagnostics enriched toward the prototype: added **Input sourcing** (per-input: supplier vs
  market) and **input distance** (some-inputs-travel-far) rows.
- Routing moved **directly under Upgrade / Change-recipe** as two cards → **action sheets**:
  Output destination is configurable (Global market / Tile stockpile / Ship to tile — radio cards);
  Input sources is a read-only sheet. (`_open_output_sheet` / `_open_input_sources_sheet`.)
- Verified: unit suite **1173/0**; screenshots — recipe strip, "ready to draw" power, Power/turn in
  economics, routing cards + output-destination sheet.

Open items: **Phase 3** (promotion: flip `use_bdp_v2` default, retire v1). ~~Flag: the port Buy price
(£18)~~ FIXED 2026-07-06 — `BuildingPrice.sale_price` returns a flat `PORT_PRICE = 10000` for the port
(internal_name == "port"), since its build kit is near-empty. Advisor-modifiability of the demolish share
is a hook, not yet wired.

**Phase 2 — Action sheets (upgrade · recipe · routing · sell · demolish).** See §9. The prototype
surfaces these as in-panel full-overlay *sheets* (back + apply footer), not separate dialogs. Plus
NPC frost polish, construction cancel. "Go to" re-targets the same panel (no secondary spawn).

**Phase 3 — Promote.** Flip `use_bdp_v2` default true; one release with v1 behind the inverse flag;
then delete v1 + flag + `swap bdp`, rename v2 to `BuildingDetailPanel` (mirror the tvp retirement).

## 7. What v2 deliberately does NOT carry over from v1

Because of the floating-single decision, drop: `_prepare_building_panel_template`,
`_create_building_panel_instance`, `_building_panel_instances`, `_next_available_building_panel`,
`_request_open_building_panel`, `_open_secondary_building`, `_visible_building_panels`,
`_position_visible_building_panels`, `_position_as_secondary_panel`, `_show_busy_screen_dialog`,
`_show_too_many_building_panels_dialog`, `_close_non_building_panels`, and the
`is_secondary_building_panel` meta plumbing (~250 lines).

## 9. Action sheets — upgrade · recipe · routing · sell · demolish (2nd prototype drop)

The updated prototype adds an **in-panel sheet** pattern: a full-panel overlay (back button +
apply/confirm footer) that slides over the panel body — not a separate CanvasLayer dialog. Six
sheets, opened from a **primary-actions row** (Upgrade / Change recipe), a **Routing** row (Input
sources / Output destination), and a **Sell / Demolish** row at the bottom. Apply → optimistic
state update + a bottom **toast**; sell/demolish → a full **result overlay**.

**Engine reality (what already exists) — this is mostly re-presentation, not new sim:**

| Sheet | Engine status | API to reuse |
|---|---|---|
| Upgrade | ✔ built + wired (queued, multi-turn) | `MatchState.preview_upgrade` / `start_upgrade` / `pending_upgrade` / `cancel_upgrade`; `upgrade_dialog.gd` is the current standalone dialog |
| Change recipe | ✔ built + wired (queued, multi-turn, has a fee) | `MatchState.retrofit_cost_tier` / `start_retrofit` / `retrofit_turns_remaining` / `cancel_retrofit`; BDP `_confirm_retrofit` |
| Input sources | ✔ built (supplier list) | BDP `_find_input_source_rows` / route controls |
| Output destination | ✔ built (stockpile-dest selection) | `MatchState.get_output_stockpile_destination` / `output_stockpile_destination_changed` |
| **Sell** (locked semantics) | NEW small sim op | reuse `BuildingPrice.sale_price(b)` (deterministic list value) + owner-setter (`match_state.gd:529`) + existing NPC render |
| **Demolish** (locked semantics) | repurpose refund → materials-only | `refund_plan` spill logic + `remove_building`; `EconomyConfig.demolish_refund_share` → 0.5, modifier-driven |

**Locked action semantics (owner decision 2026-07-05):**

- **Sell** — pays the player the building's value *as if bought off the market* =
  `BuildingPrice.sale_price(instance)` (deterministic; the same valuation the Buildings-market tab
  lists at). **Instantaneous.** Changes `owner` to an NPC (reuse the owner-setter at
  `match_state.gd:529`) and **stops it running for the player** — the building persists, land stays
  occupied, and the panel afterward shows the existing "operated by X" NPC-frosted mode. New sim:
  `MatchState.sell_building(instance_id)` = credit money + flip owner + emit. Very little new code
  (valuation + ownership + money already exist); it slots into the NPC + Buildings-market loop
  (a sold building can re-appear on the buy market).
  - ⚠️ **Balance risk to resolve before shipping Sell (rule #7):** if `sale_price` > build cost,
    build→sell is a free-money loop (rebuild and resell). Decide the valuation basis (depreciated
    build cost vs. market list price, or a cap) before wiring. Flag, don't silently pick.

- **Demolish** — returns **50 % of the materials** used to build (all levels' kits), **rounded
  down**, as goods to the tile stockpile (spill to cash if no room — reuse `refund_plan`). The 50 %
  is a **modifier alterable by specific advisors** → drive it from a Modifiers domain, not the flat
  const; set `EconomyConfig.demolish_refund_share` default **0.5** as the base the advisor modifies.
  **No money returned.** Takes **1 turn** → a queued job (`start_demolish` → `tick_demolish` →
  `building_demolished`, mirroring the retrofit/upgrade queue), then `remove_building` frees the
  land. New persistent state → **save-schema bump + migration** (`cnc-save-and-migration`). This is
  also one of the **first real advisor levers** (advisors are decorative today — see advisor memo).

**UI: port to in-panel sheets** (owner decision) — build the prototype's sheet overlays and reuse
the sim APIs beneath; the standalone `upgrade_dialog.gd` is eventually retired for the v2 path.

**Fidelity notes (prototype is optimistic; engine is queued):**
- Prototype upgrade/recipe apply *instantly* with a toast. Engine upgrade AND retrofit are
  **queued, multi-turn** (`*_started` → tick → `*_ed`). v2 sheets must show "queued · N turns" /
  pending states and a cancel affordance, not "Done!".
- Prototype input-source picker is an abstract tier (self / nearby / market / distant) with a
  per-tier transit cost. Engine routing picks a **specific supplier building** + stockpile
  destination. Reconcile: either keep the concrete supplier list, or add a small "source tier" API.
- Sheets replace some standalone dialogs (`upgrade_dialog.gd`) with in-panel overlays. Decision:
  reuse existing dialogs vs. port to sheets. Prototype-faithful = port to sheets, reuse sim APIs.

## 8. Invariants to hold (per cnc skills)

- UI reads sim, never mutates directly; all changes via `MatchState.*` / `Construction.*` setters.
- Refresh-coalescing doctrine: one rebuild per frame, catch up on `visibility_changed`.
- DS theme only — no invented per-panel styling; match the Research panel.
- Determinism / saves untouched (this is UI-only; the cheat flag is session-only, not persisted).
- Verify: `python3 tools/run_tests.py` + per-scenario windowed screenshot before "done".

## Tweak batch 5 — DONE (2026-07-06, icons/battery/money-panel + 2 sim bugs, 1184/0, e2e 598/4)

- Recipe-diagram overflow dialled back: single hero icon ~5% bleed, multi grid smaller + ~1% bleed.
- Qty-pill outline colour now follows the shown numbers (green when effective > base, red when lower),
  fixing red outlines on positive modifiers.
- Tile-view output pill shows the REAL (effective) output, not the recipe base.
- Battery BDP variant gets **Load from stockpile** + **Order from market** action sheets (per-chemistry,
  locked types greyed with their research gate).
- Money panel gains a **Purchases tab** (spend by good, mirrors Sales), and both tabs now show a framed
  good icon per row.
- **Sim fix**: buildings no longer buy market inputs they produce on the same tile (and no longer pile up
  2–4 turns of such stock). `_buy_market_inputs` now nets the recurring same-tile production rate out of
  the pipeline target (`need − local_rate`). Pure market inputs keep the `(lead+1)` transport buffer.

## Tweak batch 4 — DONE (2026-07-06, upgrade action sheet + recipe-diagram icons, 1181/0)

- **Upgrade is now an in-panel action sheet** (`_open_upgrade_sheet`) instead of the standalone
  upgrade_dialog.gd — same content (level deltas, materials + sourcing modes, blockers, upgrade/market/
  transfer/cancel actions), consistent with the recipe/sell/demolish sheets. Drives MatchState.preview_upgrade
  / start_upgrade / cancel_upgrade.
- **Panel widened 420 → 460px.**
- **Recipe-diagram icons are unframed** (bare art, no metal plate) and larger: a single input or single
  output is a big hero icon; multiple inputs are a 2-col grid; all bleed ~20% past their slot so the good
  reads larger and overflows the card edge. Arrow padding reduced to 5px each side. (The framed market-style
  icons are kept for the sheets/shipments/materials — only the recipe diagram is unframed.)

## Tweak batch 3b — DONE (2026-07-05, economics simplification + same-tile links, 1173/0, e2e 598/4)

- **Simplified economics**: one "Output value" row tagged `(sold)` / `(if sold)`, one "Transport cost" row
  (freight to the set destination), and Net = Output value − transport − inputs − maintenance − labour −
  power (always folds output value in, so Net is consistent whether or not the output is literally sold).
  Dropped the separate Sale/Hypothetical rows and the partial-units logic.
- **Same-tile producer/consumer links**: an iron-ingot furnace and a steel furnace on the SAME tile now
  link — the steel furnace lists the iron furnace under SUPPLIED BY (and vice-versa for CONSUMED BY),
  because same-tile output feeds the shared tile stockpile even without an explicit route. Detection is
  player-owned + unrouted + not-market + STOCKPILE_ALL.
- **Inputs valued at cost-to-produce** (fix, 2026-07-06): the Economics "Inputs / turn" row now prices
  inputs via `CostSolver.get_good_unit_cost` (imputed per-good cost, resolved over the whole chain),
  market only for external leaves — mirroring the solver. It previously used raw market base price
  (`Catalog.get_base_price`), disagreeing with the (already-correct) "Cost to produce" section.

## Tweak batch 3 — DONE (2026-07-05, economics + framed icons, verified 1173/0, e2e 598/4, screenshots)

Engine ground-truth (verified via a 5-agent research pass): there is **no per-building sales ledger** —
the economics card is a per-turn *projection* from the output's routing, not a realized figure. Market
sales *do* pay freight. `selected_output_route` returns `{}` for market routes (why the bands were
missing); `output_route` is market-aware (nearest port + cost/turns).

- **Framed good icons**: `_good_icon_pill` now uses `UIHelpers.make_framed_good_icon` (off-white plate +
  metal bevel, like the market row) with the qty pill overlaid; name tooltip comes from GoodIconHover.
- **Disposition-aware economics**: "Sale value / turn" + "Output transport / turn" show only when the
  output actually reaches the market (direct route, or a tile that auto-sells its surplus). Sale counts
  only the units that clear (partial-sale note when capped). Net includes sale − freight when selling,
  else running costs only. When not sold: "Hypothetical Output Sale Value" + "Hypothetical Output Transport
  Cost" rows (market value of the full output). Generators/infra (no sellable good) show neither.
- **Reach + transport bands** now render for market routes too (name the destination port), skipped for
  no-output buildings.
- **Output sheet** always shows a resolved DESTINATION card (port/tile + freight/turns) above CONSUMED BY.
- Producer/consumer links require an explicit output route — market buys/sells are opaque by design
  (confirmed correct behavior, not a bug).

## Tweak batch 2 — DONE (2026-07-05, 19 items, verified 1173/0 + screenshots)

Output sheet: Market/Tile selections re-render in place (no close), only "Ship to another tile" closes;
"CONSUMED BY" list of downstream player buildings with **Go To**. Input sheet: per-good section headers,
editable Auto-route / Tile-stockpile-only radios, "SUPPLIED BY" producer list with Go To. Back button "‹".
Recipe outline 4px from card edge. Output qty pill = struck base + effective, green(+)/red(−) 2px outline
only on a delta. Economics adds Sale value + **Net / turn**. Shipment icons enlarged (52px, overflow a 42px
slot) + 54px rows. "Restarting" → **Starting**. Good icons carry a name tooltip. Input-sourcing chip:
grey pre-source, else own=green / market=amber / missing=red. Pipeline warnings ("No input pipeline" /
"No input Reinforced Pipeline"). Output modifiers = a "See all modifiers" accordion of green/red rows.
Output reach band (easily/moderate/hard/cannot-be-reached) + transport band (cheap/average/expensive).
