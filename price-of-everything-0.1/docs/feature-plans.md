# Feature implementation plans

Planning doc for 5 features on branch `all-features`. Grounded in the current code
(file:line refs). Effort sizes are rough relative estimates (S < M < L), assuming
solo dev + AI assistance. Suggested build order: **1 → 3 → 4 → 5 → 2**.

Shared building blocks (build once, reused by several features):
- `focus_on_tile()` camera helper — Features 3 & 5.
- `_tile_distance()` lifted into `hex_map.gd`/`EconomyConfig` (currently in building_detail_panel.gd:1586) — Features 4 & 5.
- `MarketState.get_buy_price/get_sell_price` (spread) — Feature 4.
- `DS` + `SectionCard` + the ledger template chassis — Features 2, 3, 5.

**Locked design decisions:**
- Market spread: **buy at market price P, sell at 0.95·P** (5% gap).
- Market supports **both buy and sell** orders (manual), and **auto-sell stays** as the default `SellMode`
  (manual supplements it).
- **4 fixed state-owned ports** on urban coastal tiles (1 west, 1 south, 2 east); player doesn't
  manage them; each grants **+500 storage** to its tile and is the market I/O gateway.
- **Buy:** pay now → goods arrive at destination in 2 + travel turns. **Sell:** commit now → units lock and
  route to nearest port → sold at port → **cash arrives next turn** (1-turn lag).
- NPC building purchase **includes its land/footprint** — no separate land-buying step.
- Building Ledger opens from the **bottom-menu Buildings button**.
- Feature 2 = **restyle existing panels onto the ledger chassis + extract shared widgets** (incremental),
  not a single unified panel.

---

## Feature 1 — Construct panel search + filter  (Size: S–M, risk: low)

**Goal:** text search + filters (by building type, by output good) inside the Construct panel.

**Files:** `scripts/construct_panel.gd`, `scenes/construct_panel.tscn`.

**Steps:**
1. `construct_panel.tscn`: insert a `LineEdit` (search) + a category chip row / `OptionButton`
   + an output-good `OptionButton`, between `HeaderRow` and `ScrollContainer`.
2. `construct_panel.gd`: add `@onready` refs + state `_search_query`, `_category_filter`, `_output_filter`.
3. Connect `LineEdit.text_changed` and the filter controls → `_apply_filters()`.
4. `_building_matches(building, recipes) -> bool`: name/internal_name `to_lower().contains(query)`;
   category == filter; any `recipe.output_name` maps to the output filter.
5. `_apply_filters()`: toggle visibility of the already-tracked `_building_rows`
   (construct_panel.gd:200) + hide empty section headers. Avoid full rebuild.
6. Populate the output-good dropdown from distinct recipe outputs.
7. Clearing search restores all rows. Affordability greying already handled by
   `_refresh_affordability()` (construct_panel.gd:273) — no change.

**Reuse:** optional — `SearchOverlay._score_text()` scoring; plain substring is enough.

**Gotcha / tech-debt:** construct_panel **re-parses CSVs itself** (construct_panel.gd:47-97) instead of
using `Catalog`; `output_name` is a string vs Catalog's `good_id`. Optional cleanup: switch to
`Catalog.all_buildings()` / `get_recipes_for_building()` so the output filter uses good_ids cleanly.

---

## Feature 3 — Building ledger as a sortable/filterable list  (Size: M, risk: low–med)

**Goal:** ledger lists ALL buildings with power cost, recipe running, tile, go-to link + sort/filter
by productivity / output good / building type.

**Files:** `scripts/building_ledger_panel.gd` (rewrite from demo), `scenes/building_ledger_panel.tscn`
(repurpose template), new `scripts/camera_controller.gd` focus method + `world_map.gd` helper,
optional new `scenes/ledger_row.tscn`+`.gd`.

**Data join per instance** (`MatchState.buildings` → instance dict):
- `building_id` → `Catalog.get_building()` → display_name, category (=type), maintenance.
- `recipe_id` → `Catalog.get_recipe()` → outputs, `energy_req` (use as **power cost**).
- `tile_id` (direct field).
- Productivity → `Production.last_turn_run[instance_id]` + `Production.full_output_streak_by_building[instance_id]`.

**Proposed columns:** Name | Type | Recipe | Output | Power (energy_req) | Maintenance | Tile | Productivity | [Go-to].
**Default sort:** Productivity desc. (Confirm "other important info" you want — e.g. £/turn is harder, needs per-building profit.)

**Steps:**
1. Add `focus_on_tile(tile_coord)` to camera_controller (tween position to
   `map_to_local(map_coord_for_tile_coord(coord))`); expose `world_map.go_to_tile(tile_id)` that
   focuses + `info_panel.show_tile()`.
2. Rewrite `building_ledger_panel.gd`: `show_ledger()` builds a header row + one row **per instance**
   from `MatchState.buildings`.
3. Build columns (DS Body/Numeric labels).
4. Sorting: clickable headers → sort `_rows` by comparator.
5. Filtering: filter bar (type, output good) — same pattern as Feature 1.
6. Go-to button → `world_map.go_to_tile(building.tile_id)` (optionally open building detail).
7. Refresh on `MatchState.building_added/removed` and `TurnManager.turn_advanced`.
8. **Entry point:** wire the **bottom-menu Buildings button** (the `buildings_icon.png` already exists) to open
   the ledger.

**Reuse:** ledger template chassis (Title/Scroll/SectionCards/MetaStrip), `DS`.

**Gotchas:** wire the bottom-menu Buildings button to open it (no trigger today). Productivity is a derived
snapshot. Overlaps Feature 2 — do this first so the ledger is real before any panel merge. The Building-market
tab (Feature 5) reuses this row.

---

## Feature 4 — Goods market: buy/sell via state ports + spread  (Size: M–L, risk: med — mostly UI)

**~70% of mechanics already exist:** `MatchState.pending_transport_shipments` + `queue_transport_shipment()`
+ `advance_transport_shipments()` (match_state.gd:261-291); arrivals deposit to stockpile (production.gd:288-305);
hex distance `_tile_distance` (building_detail_panel.gd:1586); `EconomyConfig.transport_turns_for_tile_distance()`;
`MarketState.get_price()` + forecast; per-tile `Stockpile` (cap 500, stockpile.gd:5); TurnManager phases.

### The port model (your spec)
- **4 fixed ports**, state-owned, on **urban coastal tiles**: 1 west, 1 south, 2 east. Player never manages them.
- Each port **adds +500 storage** to its tile (port tile cap becomes ~1000) and is the **market gateway**.
- **Buy:** market purchases arrive into the **nearest port's tile storage**, then (optionally) travel on to a
  destination building.
- **Sell:** units **committed for sale** sitting in a port's tile storage are **sold to the market**.

### Buy flow (import)
1. DECIDE: player orders good G ×Q to a destination (a building/tile, or "leave at port"). Money deducted now
   at **P** (buy price) ×Q. System picks the **nearest of the 4 ports** to the destination.
2. ETA = **2 turns** (market→port) + `transport_turns(port → destination)` (existing,
   `TRANSPORT_MAX_TILES_PER_TURN = 2`).
3. Goods land in the **port tile storage**; if a building destination was chosen, the existing transport
   system carries them port→building.

### Sell flow (export)
1. Trigger a sale from a building (detail panel) or the market screen for good G ×Q.
2. The units **lock** (reserved so they can't be reused/double-sold) and route to the **nearest port** via the
   existing transport queue (travel = distance ÷ 2 turns).
3. On arrival at the port they're **sold at 0.95·P** (SEND phase).
4. **Cash posts to the account the following turn** (1-turn settlement lag) — deliberate asymmetry with buying
   (buy = pay now, goods in 2 + travel turns).

### Turn-phase decision (you asked me to choose)
- **RECEIVE = inbound:** market **purchases** that finished their delay land in the destination storage.
- **SEND = outbound:** locked **sell** units that have reached a port are sold at 0.95·P; the **revenue is
  credited the next turn** (1-turn lag — a small cash queue mirroring the goods queue).
- Rationale: matches the phase names. The existing building→stockpile transport arrival runs in PROCESS
  (production.gd:288); reuse that same queue for the buy onward-leg and the sell→port leg, keeping the market
  settle/credit in SEND/RECEIVE.

**Files:** `market_state.gd` (spread getters), `economy_config.gd` (`MARKET_SELL_FACTOR=0.95`,
`MARKET_LEAD_TURNS=2`), `match_state.gd` (order queue + port registry + sell commitments),
`turn_manager`/`production.gd` (SEND sells, RECEIVE buys), `hex_map.gd` (port tiles + nearest-port lookup),
`stockpile.gd` (+500 cap on port tiles), `market_panel.gd` + `building_detail_panel.gd` (UI).

**Steps:**
1. **Designate ports:** pick 4 urban coastal tiles (1 W / 1 S / 2 E); mark as state ports (place `b_004`
   owned by state, or an `is_port` tile flag). Each adds +500 to its tile's Stockpile capacity (make
   stockpile capacity per-tile instead of the flat `TILE_CAPACITY` const).
2. **Spread getters** in market_state.gd: `get_buy_price = get_price(g)`, `get_sell_price = get_price(g)*0.95`.
3. **Nearest-port lookup** in hex_map.gd using `_tile_distance` (lift it out of building_detail_panel).
4. **Buy order:** deduct money now at buy price; queue a delivery (reuse `queue_transport_shipment`)
   market→nearest port (ETA 2), + optional onward leg port→building.
5. **Sell commitment:** flag units in a port tile for sale; SEND phase sells them at 0.95·P.
6. **Settle:** SEND sells, RECEIVE buys (deposit into port storage).
7. **UI:** market_panel — Buy/Sell per good with buy & sell price + ETA + destination/port picker;
   building_detail_panel — a "Buy inputs" button prefilled to import this building's input good to its tile
   via the nearest port (reuse the existing inbound-shipment display).

**Gotchas:** **auto-sell stays** as the default `SellMode` (production auto-sells); manual orders supplement it.
Port storage overflow on arrival (queue vs reject). For buys, goods auto-travel port→destination unless the
player chose "leave at port". The sell-revenue lag needs a small cash-delivery queue (mirror of the goods queue).
Locking sell units must reserve them so production/auto-sell can't consume them mid-transit.

---

## Feature 5 — Building market: buy NPC buildings (INERT until bought)  (Size: M, risk: med)

**Goal:** a Building tab under Market listing pre-existing NPC buildings for sale; shown on the map + in the
tile size chart; buy → ownership transfers to player (**including the building's land/footprint**); CSV of
buildings+tiles+price. NPC buildings are **inert** (no production/cost) until bought.

**Already there:** `owner` field on instances (default `player_1`) + `add_building(..., owner)`
(match_state.gd:84); `building_visuals.on_building_placed()` (building_visuals.gd:42);
`tile_size_chart.set_buildings()` accepts arbitrary building dicts; the disabled "See buildings for sale"
button (tile_info_panel.gd:959); Catalog's CSV-loader pattern.

**Files:** new `data/npc_buildings.csv` + loader, `scripts/production.gd` (one owner guard),
`scripts/building_visuals.gd` (startup render loop), `scripts/tile_size_chart.gd` (for_sale flag + color),
new `scripts/building_market_panel.gd` (tab), ownership transfer in `match_state.gd`.

**Steps:**
1. **CSV** `data/npc_buildings.csv`: `building_id, tile_id, recipe_id, owner, sale_price` (let MatchState
   generate instance_ids — don't supply them).
2. **Loader** at startup: per row `add_building(building_id, recipe_id, tile_id, owner="npc")`, store
   `sale_price` + `for_sale=true` on the instance dict.
3. **Production guard (the only engine change):** at the top of the per-building loop in `_process_production()`
   (production.gd:76+) and the maintenance/labour/power passes, `continue` when `building.owner != "player_1"`.
4. **Map render:** in building_visuals `_ready()` (post-load), loop `MatchState.buildings` and call
   `on_building_placed(...)` for each (currently only new builds render). Optionally tint NPC buildings.
5. **Tile size chart:** pass NPC buildings to `set_buildings` with `for_sale:true`; add a distinct color in
   `_color_for_building`.
6. **Building market UI:** tab/sub-panel listing for-sale buildings (name, tile, sale_price, go-to, Buy).
   Reuse the Feature 3 ledger row + camera go-to.
7. **Buy / ownership transfer:** check money → `deduct_money(sale_price)` → set `building.owner="player_1"`,
   clear `for_sale`; **grant the building's footprint as owned land** (no separate land purchase — purchase
   bundles the land); emit a signal; refresh visuals/chart/panels. Building becomes active in production next
   turn (guard now passes).
8. Wire the existing "See buildings for sale" button (tile_info_panel.gd:959) to open this tab filtered to the tile.

**Gotchas:** apply the owner guard everywhere the production loop assumes player ownership
(maintenance, labour, sales, power). Since purchase includes the footprint, ensure the buy path marks enough
land owned on the tile so the transferred building passes the existing land/space check. Startup render of many
buildings is cheap (Godot handles thousands of 2D nodes).

---

## Feature 2 — Unified detail panel (reframed: extract widgets)  (Size: L refactor; do last / incrementally)

**Decision (from your input):** the **ledger template is the chassis** (already has DS fonts, navy
`DS.PALETTE.BG_PANEL`, and the Hero→MetaStrip→SectionCards layout). From the tile view panel, graft only the
**pipe-frame skin** + the genuine **custom widgets**.

**Salvage from `tile_info_panel.gd` (beyond pipe frame + navy + layout):**
- ✅ `tile_size_chart` (already standalone; Feature 5 needs it) — top priority.
- ✅ Stockpile visualization (color grid + legend).
- ✅ Infrastructure slot grid (roads/rails/pipes).
- ✅ (optional) dynamic banner-image selection for the Hero.
- ❌ NOT the 1,682-line monolith, NOT `_restructure_layout()` reparenting, NOT inline color constants.

**Scope (locked):** restyle the existing tile & building panels onto the ledger chassis + extract shared
widgets, done **incrementally** alongside 3/4/5 — *not* a single unified tile-or-building panel.

**Files:** `scripts/building_ledger_panel.*` (chassis), lift pipe-frame draw from `tile_info_panel.gd`, reuse
`tile_size_chart.gd`, extract `StockpileViz` + `InfraGrid` into small widget scripts.

**Steps:**
1. Chassis = ledger template (DS Title/Hero/MetaStrip/SectionCards/buttons).
2. Lift the pipe-frame overlay (`assets/ui/tile_modal_pipe_frame.png`) onto the chassis (NinePatchRect/TextureRect).
3. Navy already = `DS.PALETTE.BG_PANEL` — no action; stop tile panel using local color constants.
4. Extract widgets: `tile_size_chart` (done), `StockpileViz` (new), `InfraGrid` (new), summary chips (or MetaStrip).
5. `show_tile()` / `show_building()` compose SectionCards holding those widgets.
6. Do this **incrementally** alongside 3/4/5, not as a big-bang rewrite.

---

## Summary table

| # | Feature | Size | Where the work is | Main risk |
|---|---------|------|-------------------|-----------|
| 1 | Construct search/filter | S–M | new UI in one file | low |
| 3 | Ledger sortable list | M | greenfield table + join + camera go-to | low–med |
| 4 | Goods market (ports, buy/sell) | M–L | order UI + port gateway + SEND/RECEIVE settling | med (UI) |
| 5 | NPC building market (inert) | M | owner guard in production + CSV/loader/tab | med |
| 2 | Unified panel | L | refactor; chassis already exists | regressions |

---

## Backlog / smaller ideas

### Building input run-history mini-chart (debug/UX)
Per-building widget in the building detail panel showing the last 10 turns of run history.
Agreed design: **10 bars — height = limiting-input fill ratio (`min(have/need)` that turn, 0–100%),
colour = ran (green) / starved (red)** — plus a "Ran N/10" headline and a bottleneck label
("short on Iron Ore, avg 12/20"). The sawtooth (fills over N turns → fires) distinguishes a
*healthy intermittent* building from a *chronically starved* one, which a plain run-rate cannot.
- Data: add a 10-slot ring buffer in `production.gd` keyed by instance_id
  (`{ran, fill_ratio, limiting_good}`), snapshotted on the existing `turn_processed` signal.
  need/have are already computed in `_can_run_recipe`/`missing_by_building`, so fill ratio is ~free.
- Lives beside the building detail inputs section + input-status RAG dot.
- Bonus: same per-building signal feeds the Feature 3 ledger "productivity" column.
