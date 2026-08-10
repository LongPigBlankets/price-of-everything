# Plan — two new mapmodes: Stockpile and Ownership

Owner brief, 9 August 2026. The panel self-sizes, so the two extra rows cost nothing — measured
at 10 rows: 231 px of buttons in 231 px of room, no scrollbar, bottom at y=460 against a bottom
menu that starts at 980.

**Status.** Both modes are BUILT. Stockpile shipped as a **storage-pressure** mode rather than
the goods-filter mode specced below — owner call, 9 Aug. Ownership shipped as a **bottom-filling band gauge**
rather than the three flat colours originally specced — owner call, same day. The
goods-filter/icons/hover-chart design further down is NOT superseded: it is a second layer that
could sit on top of the fill-level mode later, and its three open questions are still unanswered.

---

## BUILT — Stockpile as a storage-pressure mode

`scripts/stockpile_overlay.gd`, mounted in `main.tscn` beside the other overlays.

| Tile state | Colour | Source |
|---|---|---|
| Holding stock, room to spare | light green | `Stockpile.get_used_capacity` > 0 |
| Over 80% of capacity | amber | `used / Stockpile.get_capacity` > `STOCK_WARN` |
| 95% or more | red | ≥ `STOCK_FULL` |
| Goods blocked here last turn | red, pulsing every 0.3 s | see below |

Tiles holding nothing are left untinted — the mode is about pressure on storage, and a wash over
every empty tile would bury the handful that matter.

**"Blocked" counts both ways a good fails to land.** `Stockpile.get_refused(tile)` is units the
cap turned away during the turn — `roll_turn_peaks()` clears it at the top of the next PROCESS, so
between turns it holds the completed turn's figure, which is exactly "as of last turn". A tile can
also have shipments parked outside it that were never unloaded
(`MatchState.overflow_shipments`); those goods are just as blocked, and that state persists across
turns, so both set the flash.

**The flash alternates between two reds**, not red and nothing. A tile blinking out to bare
terrain reads as a rendering fault, and while it was off it would read as "nothing stored here" —
the opposite of what it means.

**Cost control.** Only tiles that can possibly be tinted are costed: everything in
`Stockpile.tiles_with_stock()` plus any overflow destination — typically a handful, never the full
285. That matters because `get_capacity()` runs the modifier stack. Rebuilds are coalesced
(`stockpile_changed` fires on every add and consume), and `_process` returns immediately unless
something is actually blocked, so a calm map never redraws on a timer.

The legend takes its swatch colours from the overlay's own constants, so the key cannot drift from
what is drawn.

Verified with `tools/stockpile_mapmode_shot.gd`, which stocks four tiles to 30 / 85 / 97 / 100%+
through the real `Stockpile` API — overfilling the last one is what sets the refusal counter — and
saves both halves of the flash.

---

## The seam they both used

Neither mode needed a change to the mapmode machinery. This is the recipe, kept for the next one.

`MapMode` (`scripts/map_mode.gd`) is the single source of truth for which overlay is live. A new
whole-map mode is five small edits, no new architecture:

1. `MapMode.Mode` — add `STOCKPILE` and `OWNERSHIP`.
2. `MapMode` — add `STOCKPILE_SENTINEL` / `OWNERSHIP_SENTINEL` consts and list both modes in
   `SENTINEL_MODES` (they are whole-map toggles, not per-good pickers).
3. `mapmodes_panel.ROWS` — two rows, `kind: "sentinel"`.
4. `mapmodes_panel._mode_for_id` / `_sentinel_for` — two match arms each.
5. A `Node2D` overlay per mode, mounted in `scenes/main.tscn` beside `DepositsOverlay` /
   `WaterOverlay`, listening to `MapMode.selections_changed` + `mode_cleared`.

The panel grid is two columns and self-sizing (`_resize_to_content`), so ten rows lay out with no
work. Button names follow `MapModeRow_<id>` — the tutorial spotlights those, so keep the pattern.

**Reuse, not reinvention** — the pieces that already exist:

| Need | Existing thing |
|---|---|
| Per-tile hex tint | `scripts/power_hex_overlay.gd` — a flat-top hex mask, `color` + `tile_size`; `map_overlay.gd:785` shows how it's instanced |
| Good icons clustered in a hex | `map_overlay.RESOURCE_CLUSTER_OFFSETS` / `RESOURCE_CLUSTER_SCALE`, and `GoodIcons.texture_for()` |
| Hover-a-tile machinery | `deposits_overlay.gd` — `_process` polls `terrain_layer.tile_id_under_mouse()`, `_mouse_over_blocking_panel()` makes HUD panels swallow the hover, a `CanvasLayer` holds screen-space content repositioned from world coords |
| Redraw discipline | `deposits_overlay._last_zoom` — world-space icons need a redraw on ZOOM only, never on pan. Do not `queue_redraw()` every frame |
| Tickbox + search filter panel | `scripts/good_select_panel.gd` — framed icon rows, a search bar already doing case-insensitive `contains` partial match, a Clear-all row |

---

## BUILT — Ownership as a band gauge

`scripts/ownership_overlay.gd`. Owner call: not three flat colours, but each tile as a gauge that
fills from the BOTTOM, with the built part drawn half-width so it climbs twice as high.

**The band count is not arbitrary.** Land is bought in patches of `MatchState.LAND_PATCH_SIZE`
(10 units) out of `MAX_TILE_LAND` (200), so a tile is exactly **20 patches** — one band per patch,
5% of the tile each. The gauge is the game's own unit of land, not an invented scale.

| Cell | Colour |
|---|---|
| Not owned | dark grey |
| Owned, still empty | medium blue — full-width bands, bottom to top |
| Owned and built on | light blue — HALF-width, up the left of the owned stack, spilling into the right half only once the left column is full |

A half-cell is **half a patch** (5 units), so the built area still equals the land it represents —
half the width, twice the height. That is the whole point of the split (owner call, 9 Aug): a
small estate drawn full-width was too easy to miss.

Cells are the hex intersected with horizontal slices (`Geometry2D.intersect_polygons`, computed
once per tile size, not per tile), each inset slightly so the bands read as separate bars rather
than one block. Counts use **ceil**, not round: a part-used patch is a used patch, and
`built <= owned` always, so ceil preserves that order — plus a clamp to `2 x bands_owned`, since
tools that place buildings directly can bypass the land gate a real build goes through.

"Built" is `MatchState.get_tile_player_space_used` — owned buildings **plus construction and
upgrade reservations**. That is the game's own definition of the player's estate on a tile and
what the owned-land gate measures against; showing reserved land as free would contradict the
build dialog.

**Hover shows a plate, nothing by default.** Same navy-with-cream-bevel treatment as the Logistics
mapmode's hover panel (`logistics_overlay._draw_stockpile_panel` is the visual reference), sized
in screen pixels and divided through by the canvas scale so it holds its size at any zoom. Tile
name across the top, then five rows with the label ranged left and the value ranged right:

| Row | Source |
|---|---|
| Your buildings | player-owned, non-infrastructure, on the tile |
| NPC buildings | the same count for everyone else |
| Land owned by you | `get_tile_land_owned` / `MAX_TILE_LAND` |
| Land left to buy | `get_tile_land_units_available` — the cap less what you hold AND less the land NPC buildings sit on, which is never for sale |
| Your buildings occupy | `get_tile_player_space_used` |

Infrastructure is excluded from both counts twice over: map-seeded road/rail/pipe/cable has no
building instance at all, and anything that does exist as one carries the `infrastructure`
category. The rows are built when the cursor ENTERS a tile, not stored for all ~400 — only one
tile is ever shown and every figure walks that tile's buildings.

`draw_set_transform` moves the canvas per tile instead of translating point arrays — a redraw
fires on every hover change, i.e. whenever the cursor crosses a tile, and rebuilding ~400
`PackedVector2Array`s each time is a lot of garbage for a mouse sweep.

Verified with `tools/ownership_mapmode_shot.gd`: tiles at 0 / 50 / 100(+90 built) / 200(+150 built)
units → 0 / 5 / 10 bands with 18 halves (left 10, right 8) / 20 bands with 30 halves (left 20,
right 10), and the plate reading 3 / 3 / 100 of 200 / 40 / 90.

### Data (for reference)

- Land: `MatchState.get_tile_land_owned(tile_id)`. `DEFAULT_TILE_LAND_OWNED = 0`, so an untouched
  tile correctly reads as unowned — no special-casing needed.
- Buildings: `MatchState.get_buildings_on_tile(tile_id)`, filtered by `MatchState.is_player_owned`
  **and** `Catalog.get_building(building_id).category != "infrastructure"` — the same filter
  `DecisionState._productive_building_count()` already uses.
- Infrastructure exclusion is covered twice over, which is what the brief wants: road/rail/pipe/
  reinforced-pipe/cable that came from the map's own seeding has **no MatchState building instance
  at all** and so never appears in `get_buildings_on_tile`; anything that does exist as a building
  instance is caught by the category filter.

### Notes

- Owned and built are not independent: `_grant_building_land` gives a building's tile land
  automatically, so built land is always a subset of owned land — which is exactly why the light
  blue can sit inside the owned run rather than needing its own region.
- Refreshes on `MatchState.building_added` / `building_removed` / `tile_land_owned_changed` and
  `Production.turn_processed`, coalesced — `building_added` fires in bursts during a build-out.
- Sea tiles are skipped: there is no land to own there, and a grey wash over the ocean would
  fight the map for nothing.

---

## Mode 2 — Stockpile

### What it shows

- Every tile holding stock draws its goods as icons inside the hex.
- Tiles matching the filter are tinted **light green**. Default filter = all goods, so on opening,
  every stocked tile is green.
- A filter panel on the **right**: `Select all`, `Clear all`, and a search box doing partial
  case-insensitive match anywhere in the good's display name.
- On hover: that tile's stockpile chart, drawn over the tile, slightly larger than it — the same
  chart as the Stockpile tab of the tile view panel.

### Data

`TileViewData.stockpile_summary(tile_id)` returns exactly what both the icons and the hover chart
need — `{used, capacity, pct, is_full, goods:[{good_id, qty, display_name}], status}`, goods
already sorted by quantity descending. `Stockpile.tiles_with_stock()` gives the candidate tiles
without walking all 285.

### The three pieces of work

**A. The filter state.** Do **not** model this on `MapMode.selections` — that is capped at
`MAX_SELECTIONS = 6` and assigns each pick a colour from `PALETTE`, neither of which applies here.
Model it on `MapMode.deposit_hidden`: a hidden-set with "empty means show everything", its own
`stockpile_filter_changed` signal, and a `hide_all` / `show_all` pair that mutates once and emits
once. It is view state, not sim state — it does not go in the save (`deposit_hidden` doesn't).

**B. The filter panel.** `good_select_panel.gd` is ~90% of it already: icon rows, tick boxes, the
search bar with the exact partial-match semantics asked for, and a Clear-all row. Adding a
`"stockpile"` kind needs: a **Select all** button next to Clear all, default-all-ticked, and no
`MAX_SELECTIONS` disabling in `_sync`. Two frictions to settle first — see decisions below.

**C. The hover chart.** `tile_info_panel_v2._make_stock_chart(goods, pct_text, status)` is the
chart the brief asks for, but it is a private method on a 2,900-line panel and depends on
`_status_color` / `_make_muted_label` / `STOCK_MAX_BARS`. **Extract it into
`scripts/stock_chart.gd` as a static builder and have the TVP call that**, rather than
duplicating it or instantiating a hidden TVP to borrow the method. One chart, two callers, no
drift — the same move the DS recipe/good-icon façades already made.

### Notes

- Cap the icons per hex and cluster them the way the deposits mapmode does. A late-game warehouse
  tile can hold a dozen distinct goods; twelve icons in one hex is mush. `_make_stock_chart`
  already solves the same problem with `STOCK_MAX_BARS` + an "Other goods" bar — mirror that cap
  so the hex and the hover chart agree on what "the top goods" means.
- The hover chart is screen-space (a `CanvasLayer`, like the deposit pills) even though it is
  positioned from a world coordinate — otherwise it scales with zoom and is unreadable when zoomed
  out. "Slightly larger than the tile" should mean a fixed screen size, not a multiple of the hex.
- Rebuild on `Stockpile.stockpile_changed` and `Production.turn_processed`, coalesced.

### Open questions

1. **Do the in-hex icons respect the filter, or always show the whole stockpile?** Recommend
   **respect it** — filtering to `coal` should visibly reduce the map to coal, not just re-tint it.
   The hover chart still shows the tile's full stockpile.
2. **Panel side.** `good_select_panel.gd` is left-docked and shared with Producing / Consuming /
   Deposits. The brief says right. Either it grows a dock side per kind, or the stockpile filter
   becomes its own panel. Recommend **a dock-side property on the shared panel** — one panel, one
   search implementation, one place to fix.
3. **Which tiles are green — any stock at all, or only stock of a selected good?** Reading the
   brief literally: a tile is green when it holds ≥1 unit of any *selected* good. With the default
   all-ticked filter that means "every tile with any stock", which matches "by default all goods".
   Confirm that is the intent.

---

## Phasing and verification

1. **Ownership** — mode registration + tint + hover count. Proves the seam.
2. **Stock chart extraction** — `stock_chart.gd`, TVP delegates to it. No visible change; the TVP
   Stockpile tab must look identical afterwards (shot it before and after).
3. **Stockpile filter state + panel** — `Select all` / `Clear all` / search, on the shared panel.
4. **Stockpile overlay** — tint, icons, hover chart.

Each phase ends with a windowed screenshot from a `tools/*_shot.gd`, not a measurement — the money
panel shipped blank twice off numbers that all read correct. A shot tool for these two needs a game
with stock on the map and buildings on several tiles, so it should drive a handful of turns first
rather than shooting turn 1, where every tile is empty and every mode looks the same.

Unit coverage is thin for map overlays by nature, but two things are worth asserting headlessly:
the ownership classifier (given a tile with land only / a building / an infrastructure building
only, it returns the right one of three states) and the filter's partial-match predicate.
