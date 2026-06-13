# Polygon buildings — implementation plan

Replace the per-tile **icon grid** (`scenes/building_visuals.gd`) with **coloured polygon
footprints** that lay themselves out inside the tile like a Sanborn/Booth map: shaped by type,
sized by the building's `tile_size_used`, gravitating to roads and to same-type neighbours,
filling the low ground first. Buildings are fixed once placed (until demolished). This is the
zoom-IN half of the [building-visuals LOD](building-visuals-lod) plan; the zoom-OUT grey
built-up blob is the same layer's second mode.

Branch: `polygon-buildings` (off `main`).

---

## 1. Architecture — store + renderer (mirrors roads)

Two pieces, like `RoadNetwork` (store) + `RoadNetworkVisuals` (renderer):

- **`BuildingLayout`** (new autoload, `scripts/building_layout.gd`) — the source of truth. Holds a
  `placements` dict `instance_id -> {tile_id, polygon: PackedVector2Array (world), field:
  PackedVector2Array, kind, color, is_npc, anchor, footprint}`. Placement is **incremental and
  persisted** so a building never moves until demolished:
  - `building_added` → place the new building in the tile's *current* free space, cache it.
  - `building_removed` → evict it, free its subtiles.
  - `export_state()` / `import_state()` for save/load (don't recompute on load — restore).
  - The 472 NPC seeds are placed at match start in seed order.
- **`BuildingPolygons`** (new `scripts/building_polygons.gd`, Node2D in `main.tscn`) — reads
  `BuildingLayout`, draws the polygons. Replaces the `BuildingVisuals` node. Reuses the existing
  zoom-cull pattern (`CULL_CAP`, per-placement `bb` Rect2, `_visible_world_rect`).

Why a separate store: positions must survive save/load and must not jitter when an unrelated
building is added elsewhere — recomputing the whole map deterministically would shift later
buildings when an earlier one is demolished. The cache is the guarantee.

---

## 2. Inputs (all verified)

| Need | API |
|---|---|
| Buildings on a tile | `MatchState.get_buildings_on_tile(tile_id)`; `MatchState.buildings`, `tile_buildings` |
| Category (fine) | `Catalog.get_building(id).building_type` (pipe list: `extraction`/`metallurgy`/`electrochemistry`/`refinery`/`manufacturing`/`water`/`power`/`infrastructure`/`farm_forests`); fall back to `.category` |
| Size | `Catalog.get_building(id).tile_size_used` (int 1–30) |
| Tile capacity | tile `build_capacity` (200) — the denominator |
| Roads on tile | `RoadNetwork.instance().edges_on_tile(coord)` → edge ids; `edges[id].geometry` (world PackedVector2Array) |
| Elevation | `NavGrid.instance()` — `.cell_of(world)`, `.world_of(ix,iy)`, `.level(ix,iy)` (−1..10), `.water(ix,iy)`, `.step`=12 |
| Free / buildable space | `SubtileGrid` (27×24 @ 20u): `subtile_center(c,r)`, `hex_polygon()`, `is_subtile_buildable(c,r,river,roads,tile_id)`; `TileOccupancy.is_blocked(tile_id,c,r)` (hills/roads/forests) |
| Forests | `ForestFootprint.footprint(...)` → `{center,radius}`, `is_forest(id)` (b_015/b_016) |
| Rivers | `RiverGeometry.arms(tile_data, river_properties, center)` → `Array[PackedVector2Array]` |
| Hex geometry | flat-top 540×480, verts `(135,0)(405,0)(540,240)(405,480)(135,480)(0,240)`; centre-relative point-in-hex `|dx|≤270 ∧ |dy|≤240 ∧ 240|dx|+135|dy|≤64800`; world centre `terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))` |
| Ownership | `MatchState.is_player_owned(b)` (owner `== "player_1"`); NPC otherwise |
| Determinism | `RoadHash.pick(text,n)`, `jitter01(x,y,salt)` — key everything on `tile_id` + instance/index |

---

## 3. Category → colour (from `tile_view_data.gd`, the size-chart palette)

Pick the building's colour from its `building_type` (first match in this priority — same order the
size chart uses), else `.category`, else default:

| type / spec name | colour |
|---|---|
| `infrastructure` | `#8FA3AE` |
| `extraction` (mining) | `#141414` |
| `metallurgy` | `#4A7A9B` |
| `electrochemistry` | `#A6E22E` |
| `refinery` (petrochem) | `#8E5BC0` |
| `manufacturing` | `#E08A3C` |
| `water` | `#3A7BD5` |
| `power` | `#E3C84A` |
| `farm_forests` → farm | `#7FC97F` (field colour) |
| `farm_forests` → forest | `#2E7D32` (already drawn by ForestVisuals — buildings layer skips forests) |
| ruins (`b_031`/internal `ruins`) | `#7A5230` |
| default | `#6B7682` |

**NPC** (`owner != "player_1"`): fill = category colour, plus a **thick white outline** (≈6–8u,
the role the old `NPC_OUTLINE_PX=10` icon outline played). Player buildings: category fill, thin
dark casing only.

---

## 4. Footprint sizing

```
target_area = (tile_size_used / build_capacity) * HEX_AREA(194400) * OCCUPANCY (~0.9)
```
`OCCUPANCY < 1` bakes in the "a little under" — roads/rivers already eat tile space, so a size-20
building on a 200-capacity tile aims at ~10% but lands under it once fit into the free mask. The
chosen shape is scaled to `target_area`; if the best free pocket can't hold it, shrink to fit
(min ~1 subtile) rather than overflow. A small **DESIGN_GAP** (~4–6u) is kept between footprints
and between footprint and road — for visibility and for future building/road upgrades growing.

---

## 5. The per-tile layout engine (`BuildingLayout._place`)

Working space is the **subtile grid** (27×24, 20u cells). For each tile maintain a `free` mask:
buildable (`is_subtile_buildable` ∧ not `TileOccupancy.is_blocked`) ∧ outside every forest disc ∧
not already covered by a placed building. Precompute, on the subtile grid:
- `road_dist[c,r]` — distance from the subtile centre to the nearest road polyline on the tile.
- `level[c,r]` — `NavGrid.level` at the subtile centre.
- `same_dist[c,r]` — distance to the nearest already-placed building of the **same** `building_type`.

**Placing one building** (category `t`, area `A`, shape `s` seeded by `instance_id`):

- **Recycling (`b_036`/internal `recycling_plant`) and Extraction (`building_type` has
  `extraction`)** → go to the **far edge**, away from everything. Candidate score (maximise):
  `dist_to_tile_centre + W_AWAY * dist_to_nearest_building`. Pick the free pocket that fits `A`
  with the highest score (a tile corner that's empty).
- **Everyone else** → road-frontage first, low ground as the tie-break:
  `cost(c,r) = W_ROAD*road_dist + W_ELEV*level − W_SAME*same_attract(c,r) + GAP_penalty`
  (`same_attract` falls off with `same_dist`, so same-type clusters). Choose the min-cost pocket
  that fits `A`. If **no pocket within road reach** fits, fall back to the lowest-`level` free
  pocket (the "prioritise roads unless the low ground is too small/taken" rule, read as: roads
  win when they're available, low ground is the fallback and the tie-break).
- **Orient along the road**: long axis = tangent of the nearest road segment at the anchor; offset
  the footprint perpendicular by `half-depth + DESIGN_GAP` onto the buildable side. With no road
  nearby, orient by `jitter01`. Buildings on the same frontage line up because successive same-type
  placements share the road attractor + clustering term.
- Rasterise the placed polygon's covered subtiles → mark `free=false`; cache the placement.

`W_ROAD ≫ W_ELEV` so "gravitate to roads" dominates while still preferring the lower contour near
the road. All weights are top-of-file constants to tune in-engine.

---

## 6. Shapes (`scripts/building_shapes.gd`, static, area-parameterised)

Given a target area `A` and aspect seed, return a polygon in a local frame (then rotate to the
road tangent + translate to the anchor). Variant seeded by `instance_id`:

- **square** — side `√A`.
- **rectangle** — `w×h=A`, aspect ∈ {1.4, 1.8, 2.4} (seeded).
- **L — thick-base** — wide short bar + a thinner upright (base bar ~60% of height).
- **L — thick-length** — the upright is the thick member, short base.
- **squared-C** — rectangle with a rectangular notch cut from one long side (a U/C).

Each returns CCW vertices; area is held to `A` by solving the free dimension. Keep them axis-blocky
(right angles) — these read as industrial footprints.

---

## 7. Farms — the exception (`farm` / `b_014`)

Two parts:
1. A **small brown rectangle** (the farmhouse, `#7A5230`), placed by §5 like any building (gravitates
   to a road, small).
2. A **field polygon** attached to it: a larger polygon (≈ the rest of the building's area budget)
   in `#7FC97F` light green, **allowed to cross roads and other fields** (it is *not* added to the
   `free` mask and ignores road/occupancy constraints — only stays inside the hex). Filled flat,
   then overlaid with **medium-green hatching** (`draw_line` parallel rules, ~5px thick **at max
   zoom** → scale the stroke by camera zoom so it stays ~5px on screen, drawn only in the zoom-IN
   mode). The field can be a slightly irregular convex-ish polygon (seeded), gravitating its long
   axis along the nearest road frontage.

Farms therefore overlap the road network freely (fields run up to and across roads), unlike the
hard-edged industrial footprints.

---

## 8. Rendering & LOD (`BuildingPolygons`)

Camera-zoom gated, two modes (reuse `road_offshoots`/`hill_visuals` patterns):

- **Zoom IN** (`cam.zoom.x ≥ ~0.6`): draw each placement — farm fields (fill + hatch) first, then
  footprints: casing → category fill → NPC white outline. Viewport-culled via `bb`.
- **Zoom OUT** (`cam.zoom.x < ~0.4`): per tile, one **grey built-up blob** = convex hull / merged
  outline of that tile's footprints (skip farm fields), drawn `#6B7682`-grey. This abstracts
  buildings + ownership; **major roads (`RoadNetworkVisuals`) stay on top and crisp**, never
  abstracted. (Blob is a later milestone — see §11.)

Layer order in `main.tscn`: insert `BuildingPolygons` **after `RoadOffshoots`, before
`RoadNetworkVisuals`** so the major network draws over buildings (matches the LOD plan: ancillary
roads + buildings under the major network). Redraw on `MatchState.building_added` /
`building_removed`; `order_settled` only matters once buildings react to new roads (they won't move,
but a *new* road can change a *future* placement's frontage — existing ones stay put).

---

## 9. Determinism & stability

- Placement is **incremental + cached** (§1) — a building's polygon is computed once and persisted;
  nothing recomputes it. Save/load restores the cache verbatim.
- Every choice (shape variant, aspect, field jitter, tie-breaks) is `RoadHash`-seeded on
  `"poly|<tile_id>|<instance_id>|<field>"`, so a demolish+rebuild of the *same* instance reproduces
  the *same* look, and there is zero frame-to-frame motion.

---

## 10. Files

New: `scripts/building_layout.gd` (autoload), `scripts/building_polygons.gd` (+ node in
`scenes/main.tscn`), `scripts/building_shapes.gd`. Touch: `scenes/main.tscn` (swap
`BuildingVisuals` → `BuildingPolygons`), `scripts/save_load.gd` (persist `BuildingLayout`),
`project.godot` (autoload). Retire `scenes/building_visuals.gd` once parity is reached. Tests in
`tests/test_runner.gd`: shape areas hold to target; placement is deterministic + cached;
recycling/extraction land on the tile edge; footprints don't overlap roads (farms may); NPC flag
drives the outline.

---

## 11. Open decisions (pick before/while building)

1. **Tile-size denominator**: fixed 200, or the live `build_capacity` (grows as land is bought, so
   buildings shrink as a fraction)? Plan assumes the live value.
2. **Weights**: `W_ROAD : W_ELEV : W_SAME`, `OCCUPANCY`, `DESIGN_GAP`, the two zoom thresholds, hatch
   spacing — all guesses to tune visually.
3. **Forests**: drawn by `ForestVisuals` already — buildings layer **skips** `is_forest` ids.
   Confirm we don't want to also re-skin forests here.
4. **Grey blob** geometry: convex hull (cheap, may look bloated) vs a merged/inflated outline.
5. **Recycling identification**: only `b_036` today — generalise by internal_name `recycling_plant`
   so future recyclers inherit the edge rule.

## 12. Phased build order

1. **Renderer skeleton** — `BuildingPolygons` node + `BuildingLayout` store; one fixed-size square
   per building at the tile centre, category colour, NPC outline; swap out the icon grid. Parity
   check: every building shows, right colour, NPC outlined, zoom-cull works.
2. **Sizing + shapes** — `tile_size_used` → area; square/rect/L×2/C generators; deterministic seed.
3. **Layout engine** — subtile free mask + road/elev/same-type fields; road-frontage placement with
   orientation + gap; same-type clustering.
4. **Edge rule** — recycling/extraction to the far corners.
5. **Farms** — farmhouse + crossing field + zoom-scaled hatch.
6. **Zoom-out grey blob** — second LOD mode; verify major roads stay crisp on top.
7. **Save/load + tests + in-game tuning pass.**

Build each phase behind the existing layer so the icon grid can stay until step 1 reaches parity.
