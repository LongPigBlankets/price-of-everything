# Polygon buildings — spec

Buildings are drawn as **coloured polygon footprints** that lay themselves out inside a tile like a
Sanborn fire-insurance / Booth poverty map: shaped by type, packed densely, gravitating to roads.
This doc has two parts:

- **Part A — Shipped** (what `main` actually does today, after PR #37).
- **Part B — v2 plan** (the dense-packing + road-enclosure rework we're building next).

Part A is the source of truth for the *current* code. Part B supersedes the original implementation
plan; where the two disagree, B is the intent and A is the starting point to change.

---

# Part A — Shipped (current `main`)

## A1. Architecture (NOTE: diverged from the original plan)

The original plan called for a separate `BuildingLayout` autoload (persisted store) + a
`BuildingPolygons` renderer, retiring `building_visuals.gd`. **That is not what shipped.** What's in
`main`:

- **`scenes/building_visuals.gd`** (node `BuildingVisuals` in `main.tscn`) — a single combined
  **store + renderer**. Holds `_placements` (array of footprint dicts) and `_placement_index`
  (`instance_id -> idx`), builds per-tile masks lazily, cost-searches for a pocket, and draws.
- **`scripts/building_shapes.gd`** (`class_name BuildingShapes`) — static, area-parameterised shape
  generators returning `{verts (CCW, bbox-centred), half}`.
- No autoload. No separate persisted store.

**Consequence — positions are NOT persisted.** `relayout()` re-derives every footprint from building
**emit order** (`scripts/building_visuals.gd` `relayout()`), so position stability across save/load is
*not* guaranteed today; the code comment flags it as a later milestone. Part B fixes this (B7).

## A2. Sizing — fixed area per size point (a reversal, now endorsed)

The original plan (and its "RESOLVED" §11.1) said a footprint takes
`tile_size_used / build_capacity` of the tile's **buildable area** (so crowding shrinks buildings).
**The code does the opposite and the designer now agrees with the code:** a building gets a **fixed
absolute area per `tile_size_used` point** — `SIZE_UNIT_AREA` (currently `165.0`) — identical on every
tile, never crowd-shrunk, never overlapping. Part B keeps this model but tunes the constant **down**
(B2) so even a near-full tile covers ≤ ~half its area.

## A3. What's built vs not

Built: phase 1 renderer skeleton, phase 2 shapes (`square, rectangle, l_base, l_length, c`), phase 3
cost-scored layout (road-distance + elevation + compactness + same-type clustering masks), phase 4
edge rule (extraction + recycling seek far corners).

**Not built / broken** (the Part B backlog):
- Footprints are **axis-aligned only** — the "orient long axis along the road tangent" step from the
  original §5 was never implemented, so buildings don't **align** to roads.
- Cost weights make `W_COMPACT` (×3) and `W_SAME` (×50) dominate `W_ROAD` (×1), so buildings clump to
  each other rather than **snap** to road frontage.
- The road generator has **no knowledge of building footprints**, so new roads never grow around or
  between buildings.
- Farms render as ordinary footprints — no farmhouse + field + hatch, no river affinity.
- No zoom-out grey blob LOD.
- No save/load persistence (see A1).

---

# Part B — v2 plan

## B0. Design goals (designer, this revision)

1. **Pack buildings more densely** on urban tiles.
2. **Smaller buildings** — even at 20+ buildings a tile fills ≤ ~half its area.
3. **Snap + align buildings to roads** (footprint flush to frontage, long axis along the road).
4. **Block formation**: treat groups of ~5–6 buildings as a block, leave a little spare space, and
   **grow new roads that enclose each block, grid-like**.
5. **Farms** stay far from industrial buildings and **close to rivers**.
6. **Zoom-out grey blob** LOD.
7. **Save/load + tests**.

## B1. Ordering & the road-growth trigger (the core new mechanic)

Match lifecycle, unchanged through step 2:

1. **Base roads** laid out by the existing RoadWorks pipeline (as now).
2. **NPC / game-start buildings** emitted and laid out — **no road changes**.
3. **Player adds a building** on a tile → run the **enclosure check** below.

### The enclosure check (urban tiles only)

Runs on `MatchState.building_added` for a **player-owned** building whose tile is **urban**
(`tile_data["type"].to_lower() == "urban"`). Two conditions:

1. **Threshold crossed** — `MatchState.get_tile_space_used(tile_id)` (NPC+player `tile_size_used`,
   denominator `MAX_TILE_LAND = 200`) has crossed one of the **thresholds `[50, 100, 150, 180]`**
   since the last enclosure on this tile. Track the highest threshold already enclosed per tile so
   each band fires once.
2. **Level check is per-block, not per-tile** — see B4. The threshold (condition 1) alone *triggers*
   enclosure; whether a given block gets the +50% growth buffer is decided by whether **that block**
   contains ≥1 level-1 building. Buildings carry no `level` field yet (default 1 until the upgrade
   system writes it), so today every block reads as "has a level-1 building" and gets the buffer; the
   check becomes meaningful once upgrades land.

**On a newly-crossed threshold, generate enclosing roads** around the tile's footprints, block by
block (B4). A block with ≥1 level-1 building is enclosed with a **+50% growth buffer** behind it (room
for level-2/3 upgrade growth without a building ever crossing a road); a fully-upgraded block is
enclosed **tight, as-is**. Prefer a **grid** layout (perimeter + internal lanes between blocks).

## B2. Density & sizing (goals 1–2)

- Drop `SIZE_UNIT_AREA` from `165` to **~80** (roughly half) as the starting value — this gives
  generous headroom so even 20+ buildings on a tile stay well under half the hex, leaving room for the
  enclosure roads (B4) and upgrade growth. Tune in-engine; the ≤50%-of-hex ceiling is the constraint,
  ~80 is the first guess. Footprints stay fixed-size per A2 — denser = more buildings, not bigger ones.
- Increase packing: raise `W_COMPACT`, shrink `DESIGN_GAP` toward the minimum that still reads as
  separate buildings, and (B3) let the road-snap term pull rows into shared frontage lines so blocks
  read as terraced rows, not a scatter.

## B3. Snap + align to roads (goal 3)

**DONE (this revision).** The 20u grid-cell placement couldn't produce sub-cell gaps or orientation,
so placement is now **continuous** in `building_visuals.gd` — the grid survives only as the buildable
*mask*. New model:

- **Align**: each footprint is rotated so its **long axis = tangent of the nearest road segment**
  (local-x maps onto the tangent, local-y onto the road normal).
- **Snap**: the footprint's near edge sits `ROAD_CLEAR + DESIGN_GAP` off the carriageway — flush
  frontage, not a free-floating pocket.
- **Tight rows (replaces `W_COMPACT`)**: gaps are now **geometric, not weighted**. A new building walks
  the frontage from the segment start and takes the **first non-overlapping slot**, so it butts up
  against the previous building with exactly `DESIGN_GAP` (= **2u**) between footprints. Same-type
  buildings prefer the same frontage (`_row_score`), forming terraced rows of a kind.
- **Fallbacks**: no usable frontage → abut the nearest neighbour with `DESIGN_GAP`; first building on a
  roadless tile → lowest-elevation free cell. Edge-seekers (recycling/extraction) → far empty corner.
- Overlap is a continuous AABB-with-gap test (`_overlaps`); cell occupancy / `_fits` / `_mark` are
  gone. `W_COMPACT`/`W_SAME`/`W_ROAD`/`W_ELEV` are removed.

Still **TODO**: `ROAD_CLEAR` (18u) is large — buildings may read as not-quite-hugging; tune down once
seen in-engine. Diagonal roads use an AABB overlap (slightly conservative). The `_footprint_on_land`
land test samples only the outline + centre.

## B4. Block formation + enclosing roads (goal 4) — the hard part

This inverts the current dependency (today roads come first, buildings follow). Now buildings drive
road creation. Mechanism for the enclosure step (B1):

1. **Group into blocks of exactly 6 adjacent buildings.** Fill a block to 6 (packed tight along shared
   frontage), then **leave a gap** (larger than the intra-block `DESIGN_GAP`) before the 7th. The 7th
   building — the start of the next block — goes either:
   - **after a junction** (across/along a newly grown enclosure road), or
   - **behind the original block**, set further back from the main road.
   So a tile reads as discrete 6-building blocks separated by road/gap, not one continuous mass.
2. For each block, compute its **bounding region**. If the block contains **≥1 level-1 building**,
   expand the region by the **+50% growth buffer** behind the building rows (away from the frontage
   road); if the block is fully upgraded, keep the region **tight**. Snap the result to a **grid**.
3. **Emit enclosing road geometry** into `RoadNetwork` as **built edges** (perimeter lanes between and
   around blocks) so `RoadNetworkVisuals` draws them with the normal style. Tag them so they're
   distinguishable from the base network and so a demolish/threshold-recompute can replace them.
4. Existing footprints **do not move** when enclosure roads appear (stability, A1/B7); only *future*
   placements use the new frontage and the 6-per-block / gap rule.

> Integration points to verify before coding: how RoadWorks stores built edges
> (`RoadNetwork.edges[id]` with `state = STATE_BUILT`, `geometry: PackedVector2Array`), whether edges
> can be injected post-bootstrap without a full re-realize, and how `RoadNetworkVisuals` redraws on
> edge changes. Spec these in the build phase.

## B5. Farms (goal 5)

- Farms (`b_014`) keep **far from industrial buildings** (existing edge-seek logic, but keyed to
  industrial categories) and **near rivers**: add a per-tile **river-distance field** (from
  `RiverGeometry.arms(...)`, listed in the original inputs but never used in shipped code) and make
  farms minimise river distance.
- Render: small brown **farmhouse** rectangle + a larger light-green **field** polygon that may cross
  roads/other fields (not added to the free mask), overlaid with zoom-scaled green **hatching**.

## B6. Zoom-out grey blob (goal 6)

Second LOD mode in the renderer. Zoom IN (`cam.zoom.x ≥ ~0.6`): footprints as now. Zoom OUT
(`< ~0.4`): per tile, one grey built-up blob (merged outline / convex hull of footprints, skip farm
fields), `#6B7682`. **Major roads stay crisp on top** — never abstracted.

## B7. Save/load + tests (goal 7)

- **Persist placements** so positions survive save/load verbatim (fixes A1). Either add the persisted
  store the original plan wanted, or serialise `_placements` (+ per-tile occupancy + enclosure-road
  edges + per-tile highest-threshold-enclosed) via `scripts/save_load.gd`. Restore, don't recompute.
- **Tests** (`tests/test_runner.gd`, extending the existing `_test_building_shapes`): threshold
  crossing fires enclosure once per band; enclosure only on urban tiles; +50% buffer present when
  level-1 buildings remain; footprints align to road tangent; farms minimise river distance and avoid
  industry; placement deterministic + stable across a save/load round-trip.

## B8. Verified inputs (new for v2)

| Need | API |
|---|---|
| Tile type | `tile_data["type"]` → `urban`/`rural`/`hill`/`mountain`/`sea`/`deep_sea`; sea set = `HillField.SEA_TYPES` (`["sea","deep_sea"]`). Urban gate: `.to_lower() == "urban"`. |
| Tile space used (NPC+player) | `MatchState.get_tile_space_used(tile_id)` → float total `tile_size_used` (+ reserved construction). Max = `MatchState.MAX_TILE_LAND` (200). |
| Buildings on a tile | `MatchState.get_buildings_on_tile(tile_id)` → instance dicts. |
| Building instance shape | `{instance_id, building_id, recipe_id, tile_id, owner}` (`MatchState.add_building`). **No `level` field yet** — default to 1. Owner `"player_1"` = player; `MatchState.is_player_owned(b)`. |
| Per-building size / type | `Catalog.get_building(id).tile_size_used` (int), `.building_type` (pipe list), `TileViewData.category_key/category_color`. |
| Roads (read + inject) | `RoadNetwork.instance()`, `.edges_on_tile(coord)`, `edges[id].geometry`, `edges[id].state == RoadNetwork.STATE_BUILT`. Injection path for enclosure roads: TBD in B4 build phase. |
| Rivers | `RiverGeometry.arms(tile_data, river_properties, center)` → `Array[PackedVector2Array]`. |
| Forest discs | `ForestVisuals.discs_on_tile(coord)` → `{center, radius}`. |
| Signals | `MatchState.building_added(instance)` / `building_removed(instance_id)`. |
| Determinism | `RoadHash.pick(text, n)` keyed on `"poly\|<tile_id>\|<instance_id>\|<field>"`. |

## B9. Phased build order (v2)

1. **Sizing + density** — drop `SIZE_UNIT_AREA` to the ≤50% ceiling; raise compaction / shrink gap.
   (Cheapest, immediately visible.)
2. **Road snap + align** — re-introduce road-tangent orientation + perpendicular frontage snap;
   rebalance weights so roads win in reach.
   - **Re-snap on road build — DONE**: the packer already reads real road geometry
     (`building_visuals._tile_road_segments` → `_place_frontage`), but `relayout()` ran only ONCE at
     startup, so a building placed BEFORE a road kept its roadless fallback layout forever — the
     "buildings don't snap" symptom. Fix: `building_visuals` subscribes to `RoadWorks.order_settled` and
     calls the new scoped `relayout_tile(tile_id)` (re-packs just that tile, coalesced via a deferred
     flush so a batch of settles is one pass). `RoadWorks.order_tile(order_id)` maps the signal to its
     tile. NOT global `relayout()` per settle (keeps B4 mass-build under the 8 ms ceiling). Verified by
     `_test_building_resnap` (building 140u from a built road → 30u frontage after re-pack).
   - **Stub gate — DONE**: the forked "Y" access stubs (`RoadOffshoots`, cosmetic, >3-building
     densifying tiles) are now gated to `type == "rural"` only — cities use the beige enclosure grid as
     their road fabric, so no Y-stubs there. (Also excludes hill/mountain densifying tiles; flip to
     `!= "urban"` if those should keep stubs.) Verified: rural sprouts stubs, urban sprouts 0.
   - **Latent polylines (proposed, DEFERRED)**: pre-bake an invisible local road polyline per tile so
     buildings snap from turn 0 ("snap to imaginary roads"). Sound polish but NOT the snapping fix (the
     re-snap trigger above is), and largely unnecessary given roads arrive on most tiles soon. Risks:
     eager all-tiles routing at start is too slow (~2.4–20 s) so must be bake-time/lazy; latent edges in
     `net.edges` would leak into `_nearest_attachment`/stubs/occupancy unless excluded. Revisit only if
     the roadless-window look still bothers after the re-snap fix lands in-engine.
   - **Block-subdivision (city blocks) — DONE**: ~`BLOCK_PROB`% of tiles (any type) anchor a "city
     block" to their longest near-STRAIGHT road RUN (≥`BLOCK_MIN_ROAD`, clipped to the in-tile portion —
     road polylines are finely sampled so a single segment is tiny and a multi-tile run would anchor
     outside the hex). A grid of `BLOCK_LOT`-pitch lots reaches back from that frontage (axis-aligned via
     90° snap so lots pack tight); only lots within `BLOCK_ROAD_ADJ` of a road are used (deeper interior =
     empty courtyard); buildings claim lots in emit order, the rest fall back to the continuous packer.
     Road geometry comes from `_block_road_segments` (RoadNetwork `edges_on_tile`, STATE_BUILT, NOT the
     `infrastructure_present` flag — which only 3/92 urban tiles carry). Empty templates are NOT cached
     (retry until a road exists); real blocks STAY PUT on road-settle (only blocked lots fall back).
     Block lots hug the road at `BLOCK_ROAD_PAD` (7u, vs ROAD_CLEAR 18) with tight inter-building gaps
     (`BLOCK_FILL_*`). Footprints are real (feed roads-avoid + LOD). Deterministic from `tile_id`; never
     persisted. `scenes/building_visuals.gd`; `_test_block_subdivision`.
   - **River/bridge road corridor (Option 2) — DONE**: roads were running over riverside factories
     near bridges because the packer had zero crossing awareness and the bridge gate is a forced waypoint
     the soft roads-avoid cost can't bend around. Fix: reserve a road corridor in the buildable mask
     (`_ensure_tile`) so neither packer puts a building there — a band along river arms (`RIVER_ROAD_PAD`
     28u, vs `RIVER_CLEAR` 16, leaving room for a bank road to the crossing) plus a stub straight out
     from each PREDETERMINED crossing along the bridge axis on both banks (`_bridge_approach_segments`,
     `BRIDGE_APPROACH` 50u ≈ "5u after the bridge"). Crossings are deterministic (`RoadCrossings`), so the
     corridor is stable + cheap. Chosen over the "shadow the overlap as an overpass" option for the
     Sanborn top-down legibility (clean street→bridge→street reads better than a road occluding the
     docks). Covers the bridge/river case; rare non-bridge overlaps still rely on the soft avoid-cost.
     `_test_bridge_corridor`. Tunable: `RIVER_ROAD_PAD`, `BRIDGE_APPROACH`.
   - **Subcomponents (80 + 20) — DONE**: each `tile_size_used` unit also funds ~`SUBCOMPONENT_AREA`
     (20u) of ancillaries — round storage tanks (`BuildingShapes.circle`) + small annexes — placed in a
     SECOND pass beside the parent, in spare buildable cells (count ≈ `round(size*20/60)`, cap 4). They
     AVOID roads (the buildable mask + a clears check) and re-derive whenever the tile changes
     (`_mark_subcomp_dirty` → coalesced `_flush_subcomponents` → `_rebuild_subcomponents`, fired from
     on_building_placed / relayout / relayout_tile / demolish), so roads never need to avoid them and they
     are NOT added to `footprint_discs` (which keeps the `footprint_discs == placed_n` test invariant and
     sidesteps `footprint_version`). Deterministic (seeded per parent instance_id), never persisted.
     `_test_subcomponents`. Tunable: `SUBCOMPONENT_AREA`, `SUBCOMP_UNIT_AREA`, `SUBCOMP_MAX`, `SUBCOMP_TANK_R`.
   - **Roof markings — DONE**: PLAYER buildings (not NPC) get thin grey roof ridges along the footprint's
     own long axis (derived from the quad's edges so they stay on the roof at any rotation); only 4-vertex
     square/rect footprints (incl. block lots) — L/C are skipped so a ridge never spills off the polygon.
     Draw-only in `_draw` (`ROOF_MARK`). Stubs-avoidance bug also fixed: a cosmetic stub that can't avoid a
     footprint is now DROPPED, not drawn over the building (`road_offshoots.gd` generate_stubs; regression test).
     Annexes take the PARENT's colour and touch/overlap it (drawn on top → an extension); only round tanks
     keep a small gap + steel colour (`SUBCOMP_ANNEX_OVERLAP`; annexes validated against everything EXCEPT the parent).
   - **Farms (B5 / goal 5) — DONE**: farms (`cat == "farm"`, e.g. `b_014`) are irregular polygonal
     **fields** (`BuildingShapes.farm_field` — seeded 7/8-gon with jittered radii, not in `KINDS`).
     Placement (`_search` farm branch → `_place_farm`): they **gravitate to the river** (score =
     `_dist_to_rivers`, which degrades to centre-distance on a riverless tile) UNLESS the tile already
     carries a non-farm building (`_has_non_farm_buildings`, so a farm built AFTER industry retreats to
     the **tile edge**, score = `-rel.length()`). A relaxed validity (`_farm_valid`/`_farm_footprint_ok`)
     lets a field **overhang the hex** — every in-hex vertex must still be buildable land, and the field
     clears roads/rivers/other buildings — then `_clip_to_hex` (`Geometry2D.intersect_polygons`, largest
     non-hole ring) cuts it to the hex edge. Render: light-green fill (`FARM_FIELD_COLOR`) + **3px
     dark-green hatch** (`FARM_HATCH`, 45° lines `intersect_polyline_with_polygon`-clipped, **baked once**
     into `placement["hatch"]` at placement / re-baked on every relayout). Outbuildings
     (`_place_farm_outbuildings`): a **brown size-60 barn** (`FARM_BARN` rect, abuts the field) + a **brown
     size-50 silo** (`FARM_SILO_R` circle, abuts the barn), both `FARM_BROWN`, replacing the generic
     annex/tank for farms. Farms also **bypass block-mode `_claim_slot`** (`cat != "farm"` gate in
     `_place_building`) so a roaded tile can't turn a field into a rectangular lot, and roof ridges are
     gated to non-farm player buildings. Regression: `_test_farms` (polygonal+clipped field, baked hatch,
     brown barn+silo, deterministic rebuild, river→edge affinity flip, block-mode keeps the field).
   - **Farm scale + lanes (revision) — DONE**: building `tile_size_used` 10→15; fields render **3× linear**
     (`FARM_FIELD_SCALE`, area ×9 via `farm_field(area*scale²)`) — big fields that clip at the hex edge.
     Barn+silo are now placed **ON the field** (near its centroid, kept inside via `_poly_inside`) at **3×**
     (`FARM_OUTBUILDING_SCALE`), drawn on TOP (kinds `farm_barn`/`farm_silo`). **Lanes between adjacent
     fields**: a per-tile pass (`_build_farm_layout`, run inside `_rebuild_subcomponents`) clips each field
     to its **Voronoi cell** so the field "snaps" to the lane (`_clip_poly_halfplane` Sutherland-Hodgman by
     each site-pair bisector; render = `intersect_polygons(field, cell)`), and draws the **Voronoi edges**
     as thin dirt tracks (`_voronoi_edge` = bisector clipped to hex + nearer-i half-planes; `FARM_LANE_*`) —
     "perfectly between" two fields. Farms pack closer for this: `_farm_overlaps` keeps full AABB clearance
     vs non-farm buildings but only `FARM_MIN_SEP` centre spacing vs other farms. Render shape + re-baked
     hatch live in `_farm_render[iid]` (neighbour-dependent, so re-derived per tile, never persisted; cleaned
     in `remove_instance`/`clear_all`); lanes in `_farm_lanes[tile_id]`. Self-contained half-plane clip kit
     (`_clip_seg_to_convex`/`_clip_seg_halfplane`/`_clip_seg_by_line`) — no `offset_polygon`. Regression:
     `_test_farm_lanes` (two farms → ≥1 lane, each field cell-clipped, deterministic) + `tile_size_used==15`.
     DEFERRED: "real roads connect to these tracks once built" — no dynamic RoadNetwork wiring yet.
   - **Farm lane refinements (revision) — DONE**: lanes are **5px** (`FARM_LANE_W`); kept **within
     `FARM_LANE_REACH`=5u of a field** (`_near_field_runs` returns the near-field param runs of each Voronoi
     edge — no more cross-tile projection); routed **around forests** — `_forest_heptagons_near` builds a
     heptagon (radius disc.r + `FOREST_HEP_MARGIN`) for each forest within `FOREST_RING_NEAR`=32u of a field,
     `_subtract_heptagons` removes lane parts inside them, and each heptagon edge is drawn as a ring **cut at
     rivers** (`_seg_keep_away_from_segs` vs river arms, `RIVER_CLEAR`); and they **cross rivers only at
     bridges** — the gap between two opposite-bank near-field runs is bridged where it intersects a river
     (`Geometry2D.segment_intersects_segment` → `_farm_bridges[tile]`, drawn as a deck + abutment rails). A
     run itself never crosses a river (fields clear rivers by 16u ≫ the 5u reach). Geometry kit added:
     `_near_field_runs`/`_seg_outside_convex`/`_seg_keep_away_from_segs`/`_make_heptagon`/`_dist_point_to_poly`.
     `_test_farm_lanes` gained map-independent unit checks (trim, forest-subtract).
   - **Farm lane revision 2 — DONE**: (a) the farm tracks **merge into real roads** without creating any
     RoadNetwork edges — `_build_farm_layout` finds the closest field-edge↔real-road point pair
     (`_block_road_segments` + `_closest_point_on_poly`) and, within `FARM_ROAD_MERGE_MAX`=120u, draws one
     cosmetic connector lane (forest-subtracted); recomputed on re-snap/relayout so existing roads connect on
     load. (b) Forest **heptagon rings are now ALSO trimmed to within FARM_LANE_REACH of a field** (partial
     heptagon is fine) — per-edge `_near_field_runs` then river-cut. (c) **De-duplicated forest heptagons**
     (`_forest_heptagons_near` skips a disc that overlaps an accepted one by >half their radii) — fixes the
     "heptagon drawn twice" from near-coincident forest instances on a tile. Regression: `_test_farm_lanes`
     now also asserts a connector reaches a built road.
   - **Farm lane revision 3 — DONE**: (1) an **outer wrap-around ring** — `_offset_poly_out` (convex hull of
     the field verts, `offset_polygon` JOIN_ROUND +8u) drawn as a loose-polygon track around the cluster
     (≥2 farms), river-cut + forest-subtracted. (3a) **Farms are sticky on road placement** — `relayout_tile`
     keeps farm placements (only non-farms re-snap; a farm-only tile just rebuilds its layout), so a new road
     never rearranges farms. (4) **Outbuildings snap to the plot's road edge** — `_place_farm_outbuildings`
     anchors the barn at the field-boundary point nearest any track/road (`snap_segs` = lanes + roads) and
     sits it just inside; **30% smaller** (`FARM_OUTBUILDING_SCALE` 3.0→2.1). (5) **biomass + fertiliser icons
     de-blued** — `tools/strip_icon_bg.gd` (reuses the bake corner-flood-fill, which works for any bg colour)
     made their blue backgrounds transparent. DEFERRED (needs scope decision): "(2) upgrade the outer ring +
     one web path to PROPER roads when a real road is built" and "the road FOLLOWS the web to its destination"
     — these are real RoadNetwork/road-realizer routing changes, not cosmetic.
   - **Farm→real-road, STAGE 1 (promotion) — DONE**: when a player road settles on (or crosses) a farm
     tile, that tile's web is PROMOTED to real RoadNetwork roads. `building_visuals` exposes promote
     candidates per tile — `_farm_promote[tile_id] = {ring (chained outer-ring polylines), trunk (longest
     inter-field path)}`, built in `_build_farm_layout`; accessors `farm_promote_candidates[_for_coord]`.
     `RoadWorks._settle` → `_promote_farm_roads_if_reached` iterates the settled edge's crossed tiles, and
     for each un-promoted farm tile creates `STATE_BUILT`/`TIER_LOCAL` edges (`ensure_node`+`add_edge`,
     stable ids `farmr:tile:idx`), sets `_farm_promoted[tile_id]`, emits `farm_roads_promoted`. Drawn
     coordination: `_build_farm_layout` omits the ring + trunk from the brown `_farm_lanes` once
     `RoadWorks.is_farm_promoted(tile)` (authoritative — robust to load signal-ordering; the rest of the web
     stays brown). Persisted in `RoadWorks.export/import_state` (`farm_promoted` key); idempotent (flag +
     stable node ids). Regression: `_test_farm_road_promotion` (edges created, ring+trunk removed from brown,
     idempotent, persists save/load). KNOWN LIMITATION: demolishing a farm leaves its promoted roads (built
     roads persist — no edge deletion).
   - **Farm→real-road, STAGE 2 (routing bias) — DONE**: a road threading a farm cluster now FOLLOWS the
     cosmetic web. `road_realizer` gained a `_farm_lane_cost` corridor raster (mirrors `_building_cost`): a
     new "farm_lanes" prep phase (after "buildings") stamps cells within `FARM_LANE_NEAR`=7u of a track
     (`_scatter_farm_lanes` from `building_visuals.all_farm_lane_segments()`, version-keyed off
     `farm_lanes_version`); in the A* hot loop a lane cell gets `COST_FARM_LANE`=0.5 AND **bypasses the
     field-footprint penalty**, so the cheapest path runs along the web instead of detouring around the big
     3× fields. Regression `_test_farm_road_routing_bias` (road across a cluster → 37% of path points on a
     track; ~0% if it detoured) + verified visually (`tools/farm_shot.gd` draws the routed path). Negligible
     perf (B4 max_frame_plan 5.66→5.71ms).
   - **River-split webs + borrow-the-web routing (revision)**: (A) a river now splits a farm cluster into
     **independent per-bank webs** — a field clips its Voronoi cell only against farms on its own bank
     (`_same_bank`: the segment between them crosses no river), and the outer ring is built per bank-group
     (`_bank_components`), so cells/lanes/rings never span the water. (B) **Borrow the web**: promotion now
     makes only the outer RING a real road (the through-path is the player's own road); and
     `RoadWorks._snap_route_to_web` post-processes a routed road so where it crosses a farm cluster it
     follows that cluster's outer ring (shorter arc, `_ring_arc`/`_closest_edge`) around the fields instead
     of cutting through — the ring is one connected loop so this always has a path (the inter-field web
     graph fragmented). `building_visuals.all_farm_cluster_rings()` exposes the ring polygons; the road
     keeps the cost-bias from Stage 2 as a soft pull and the snap as the hard "run on the ring". Regression:
     `_test_farm_road_routing_bias` (a straight cutting road 37%→56% on-track after the snap); promotion test
     now checks the RING leaves the brown tracks. The snap routes via `_web_path_through` (Dijkstra on the
     track graph), with the ring arc as fallback.
   - **Inter-field web extends to the ring (revision)**: inter-field Voronoi edges are now clipped to the
     cluster RING polygon (`_clip_seg_to_convex` vs the up-front `comp_ring`) instead of the old
     within-5u-of-fields trim — keeping the interior Voronoi junctions AND extending each edge out to MEET
     the ring, so the web is ONE connected graph. The road snap therefore threads THROUGH the cluster
     (shortest path on the connected graph) instead of only around the ring. Regression: a cutting road goes
     60%→73% on-track (threading); river-split has deterministic unit tests (`_same_bank`/`_bank_components`).
     Verified visually (`tools/farm_shot.gd`): the road threads the web through the cluster, and a river
     leaves the off-bank field as its own group with no track crossing the water.
   - **Adjacency webs + concave hugging ring (revision)**: webs now form by FIELD ADJACENCY, not just same
     bank — `_web_components` groups farms whose fields touch (`_polys_adjacent`, within `FARM_ADJ_MAX`=12u),
     and an inter-field lane is drawn only between directly-adjacent fields, so distant farms never share a
     web. The outer ring HUGS its fields: `_union_offset_fields` offsets each field outward by
     `FARM_RING_OFFSET`=6u and unions them (`_union_polys` via `Geometry2D.merge_polygons`), so the outline
     follows concavities (~6u from the farms) instead of a convex hull bridging far across a C-shaped cluster
     (convex-hull offset kept as a fallback). The (now possibly concave) ring is clipped with
     `intersect_polyline_with_polygon` and is fine for the snap (`is_point_in_polygon`/`_ring_arc` are
     concave-safe). `_same_bank`/`_bank_components` kept for the river-split unit tests. 587 tests pass;
     verified visually (ring traces each field's edge; no distant-farm webs). KNOWN/ACCEPTED: roads still
     occasionally cross a farm to reach the tile middle (rare — left as-is per the designer).
   - **Forest tolerance + no boundary sprawl (revision)**: (1) farms now nestle 30% closer to forests —
     `_ensure_tile` builds a second mask `_farm_land`/`_farm_landkeys` that excludes a cell only inside
     `FARM_FOREST_TOL`=0.7 × a forest disc's radius (vs the full disc for other buildings); `_place_farm`
     scans the farm mask. (2) The outer ring is NOT drawn within 3u of the hex boundary — each ring edge is
     clipped to the hex inset by 3u (`offset_polygon(hex, -3)`) before the river-cut/forest-subtract, so a
     field that reached the tile edge can't make the ring sprawl along the boundary (the full ring polygon
     still drives the snap's inside test). 587 tests pass; boundary cut verified visually (edge-affinity
     farms — ring stays inner, hex border clean).
   - **Decagon fields + cross-tile edge affinity (revision)**: (1) `BuildingShapes.farm_field` is now a
     strictly-CONVEX 10-gon (decagon) — vertices on a circle in angular order, radius jitter 0.90..1.08 +
     ±3° angular jitter (down from the spiky 7/8-gon at 0.74..1.20). This gives a "no outward corner < 120°"
     guarantee *for free, with no post-clip geometry*: a convex decagon clipped by the convex cell
     (hex ∩ same-bank Voronoi half-planes) and by the convex hex stays convex, so every clip-introduced
     vertex lies on a hex/Voronoi (shared/boundary) edge — exempt from the outward rule — while every
     retained original corner keeps its base angle (worst base interior angle ≈125.6°). Monte-Carlo verified
     (40k random clips: worst free corner 134.4°). NB: the guarantee relies on the clip cell staying convex
     — if a field is ever clipped against a CONCAVE polygon, a free-run smoothing pass would be needed.
     (2) Farms now have a STRONG preference for hex edges shared with a neighbour tile that already has farms,
     so clusters continue across the tile boundary: `_place_farm` precomputes (once per call) the world points
     of farms on the 6 hex-neighbour tiles within `FARM_CROSS_TILE_RADIUS`=440u (`_neighbor_farm_world_pts`);
     when any exist, the cell score becomes the world distance to the nearest of them — dominating (replacing)
     the river/edge term, so the cluster hugs the shared edge. `_farm_valid` still gates every cell (never on
     water/forest/road). Best-effort + order-dependent: only the LATER-placed tile of a pair aligns (existing
     farms are never re-placed); river-hugging is intentionally overridden on tiles adjacent to existing farms.
     587 tests pass; cross-tile pull verified quantitatively (+217u centroid shift toward the shared edge in a
     headless A/B check) and visually (two tiles' clusters meet at the boundary; rounder decagon fields).
   - **Outer-ring corners + icon de-blue (revision)**: outer-ring corners now MEET (sharp MITRE offset of
     the outermost-points hull, chained continuous polylines + a disc joint at every vertex — no more broken
     segments). biomass + fertiliser icons de-blued for real — the source was stripped but the game loads
     the imported `.ctex`, whose cache was stale; cleared it + re-imported (`tools/strip_icon_bg.gd` now
     saves to the globalized absolute path). I can self-verify visuals via `tools/farm_shot.tscn` (windowed
     Godot → viewport PNG).
   - **Buildings-under-roads ROOT CAUSE — FIXED**: the buildable mask's road-clearance used the GATED
     `_tile_road_segments` (only roads on tiles whose `infrastructure_present` has "roads" — which most
     tiles never set), so a tile with a baked-spine / NPC-connect / pre-mask road had NO road exclusion and
     the packer placed buildings straight over it. (Diagnostic confirmed e.g. tile_9_8 had 180 road segs
     hidden by the gate.) Fix: `_ensure_tile` now uses the UNGATED `_block_road_segments` (RoadNetwork
     `edges_on_tile`, STATE_BUILT) for the mask + frontage, so buildings avoid + line EVERY road on the
     tile regardless of the flag. This was the recurring "buildings under the road" cause for the continuous
     packer (the block path already used the ungated source). One-time effect: on load, riverside/roadside
     buildings re-pack a touch further off roads everywhere. `MASK_DEBUG` flag logs the gate's effect.
3. **Enclosure trigger** — urban gate + threshold tracking on `building_added`; fire once per band;
   resolve B-D1.
4. **Enclosure roads** — being built incrementally (new `scripts/enclosure_roads.gd` autoload, fires on
   `MatchState.building_added`, persisted via SaveLoad's `enclosure` key):
   - **4.0/4.1 — DONE**: trigger (player + urban + newly-crossed band of [50,100,150,180], one-shot per
     band) records ONE rectangular ring (AABB of the tile's footprints, expanded by `ROAD_CLEAR` + 50%
     buffer, hex-clamped to stay ≥5u inside the tile edge). Band recorded only on a *successful* ring.
     Enclosure roads are a SEPARATE visual class, NOT real roads: a dedicated `EnclosureVisuals` node
     (between BuildingVisuals and RoadNetworkVisuals) draws them THIN + BEIGE with a 1px edge, distinct
     from the yellow/thick real roads. They never enter `RoadNetwork` and never flag the tile `roads`,
     so they have **no routing/economy effect** — real (yellow) roads still come only from the player
     building the `roads` infrastructure. Tests cover fire / one-shot / urban-gate / NPC-gate.
   - **4.2 — DONE**: ring geometry + band tracking persisted via SaveLoad's `enclosure` key
     (`EnclosureRoads.export_state`/`import_state`); never re-fires on load (`building_added` not
     re-emitted; rings restore from the snapshot, `version` bump triggers a redraw).
   - **4.3 — TODO**: attach the ring to the base network (nearest built node/edge).
   - **4.4 — DONE (grid geometry)**: replaced the single ring with a **fat-centre 3×3 grid** (outer ring
     + two near-vertical + two near-horizontal dividing roads). Middle band is ~42% (large central cell
     → room for a river through the middle). Each dividing road leans a **seeded 0/15/30° left or right**
     (keyed on `tile_id` via `RoadHash`) so the grid reads irregular/organic, not a rigid lattice. Still
     **TODO**: pack buildings into the 9 cells (scenario 3); behind-the-rows growth direction.
   - **River handling — DONE**: `GridGeometry.drop_crossing_segments` breaks enclosure lanes at river
     arms (`_river_segments` via `RiverGeometry`), so no beige lane crosses the water without a bridge —
     the river acts as a natural cell boundary. (Real-road bridges are a separate system: `road_crossings.gd`
     predetermines one gated crossing per arm; a real road crossing off-gate is a realizer issue, not this.)
   - **Scenario 4 (prune) — DONE**: new static `scripts/grid_geometry.gd` `prune_polylines` splits each
     grid lane and drops segments that cross a building footprint (`building_visuals.footprint_rects_on_tile`),
     run at grid formation — so lanes break around buildings instead of over them. (Referenced via
     `preload`; a new file's `class_name` isn't in the headless class cache.) 3 unit tests.
   - **Scenario 1 (road-merge) — DONE (omit half)**: where a tile is flagged `roads`, `_real_road_segments`
     reads the built edges (via `edges_on_tile`, the same call `building_visuals` already uses — so the
     tile-key convention is verified) and `GridGeometry.drop_near_roads` omits grid lanes that run
     near-collinear with a real road (`MERGE_DIST=20`, `MERGE_DOT≈cos14°`), so the beige grid de-dups
     instead of drawing parallel to a road. 2 unit tests. **TODO**: snap grid endpoints onto road entry
     points (connect), and the grid-FROM-roads direction for scenario 3.
   - **Scenario 3 (placement inversion) — TODO, BLOCKED on a decision**: grid goes tile-wide and drives
     placement (buildings pack the 9 cells, counting under-construction footprints). Conflicts with B4
     step-4 "existing footprints do not move" → decide: pack only NEW buildings (honors B4, mixed) vs
     re-pack all (clean grid, NPC seeds jump).
   - **4.5 — TODO**: asymmetric +50% buffer *behind the rows* (−road-normal) per block; tune grid pitch.
   - **4.6 — TODO (needs new API)**: demolish/recompute — requires a new `RoadNetwork.remove_edge` and an
     `instance_id→tile_id` reverse map (`building_removed` emits only a String, building already erased).
   - **Roads-avoid-buildings (#2) — DONE**: the real A* realizer reads a `_building_cost` raster
     (tiers 0/none, 1/near, 2/core) scattered from `building_visuals.footprint_discs()` in a dedicated
     "buildings" prep phase, applied as a finite multiplier on step cost (`COST_BUILDING_CORE=4.0`,
     `COST_BUILDING_NEAR=1.5`). It NEVER writes `_passable`, so a saturated tile still routes — this is
     the explicit fix for the earlier hard-block bug that made dense tiles impassable and dropped their
     roads. Warmed at `road_works` enqueue (`warm_building_cache`). 3 unit tests in
     `_test_roads_avoid_buildings` (baseline routes, saturated tile still routes = no-wall guard, cost
     visibly changes the route = avoidance live). **TODO**: in-flight reroute when a building lands near
     an already-planned road; visual tuning of `COST_BUILDING_CORE`.
5. **Farms** — river-distance field, industry avoidance, farmhouse + field + hatch.
6. **Zoom-out grey blob** — second LOD mode; major roads stay crisp.
7. **Save/load persistence + tests + in-engine tuning pass.**

Each phase ships behind the current behaviour so the tile stays playable between steps.

## B10. Open decisions

- ~~**B-D1**: role of the level check~~ **RESOLVED** — per-block buffer-gate (B4 step 2): a block with
  ≥1 level-1 building gets the +50% buffer, a fully-upgraded block is enclosed tight.
- ~~**Block size**~~ **RESOLVED** — exactly 6 per block, gap then 7th after a junction or behind the
  block (B4 step 1). Still open: **grid spacing** and the gap width.
- **Enclosure-road injection**: can edges be added post-bootstrap cheaply, or must enclosure piggyback
  on a re-realize? (Verify in B4.)
- **Grey blob** geometry: convex hull (cheap, bloated) vs merged/inflated outline.
- **`SIZE_UNIT_AREA`** final value (starting ~80) + the full weight set — all in-engine tuning.
