# Roads v2 — review of the existing system & design for organic heightmap-driven roads

Status: **design only** (no implementation in this branch yet).
Inputs: multi-agent review of the road + terrain code (3 readers), three competing
architecture designs, two adversarial judges (codebase feasibility; principle
coverage a–k + aesthetics). This document is the synthesis.

Reference aesthetic: a UK regional road atlas — organic curving A-roads (orange)
and B-roads (yellow), ring roads around urban areas, valley- and river-following
trunk routes.

---

## 1. Review: how roads work today

Roads are **cosmetic geometry layered over a boolean flag**. A tile "has roads"
iff `infrastructure_present` contains `"roads"` (seeded from
`tile_properties.csv`, flipped when a road construction completes). Gameplay
(transport routing in `catalog.gd`) keeps its own infra map parsed from the same
CSV and never touches the drawn geometry. Drawing lives in
`road_visuals.gd::_draw()`, which iterates every map tile:

- **City tiles** (`city_id` set) short-circuit into one region-level plan from
  `region_road_planner.gd`: convex hull of member hexes, inset wobbled beltway
  loop (coastal-clamped when sea-adjacent), inner spurs, core connector stars,
  seeded fractal outer branches. Cached per city + member-signature.
- **Non-city road tiles** get a per-tile plan from the 3,280-line
  `road_planner.gd`: HSM edge-midpoint exits, simple/dense/river builders,
  post-hoc repair passes, a graph fallback. **No cache** — and `_init` re-reads
  `road_templates.json` from disk on every redraw.

### 1.1 Live vs dead code

`road_planner.gd` contains at least **four generations** of planners; roughly
half the file is unreachable:

| Subsystem | Lines (≈) | Status |
|---|---|---|
| Entry/dispatch + repair passes | 106–179, 1696–1751 | live |
| City planning (inset-circle + eroded-contour beltways) | 213–1196 | **bypassed** (`USE_REGION_PLANNER=true`), incl. an older fully-dead contour generation |
| Simple / dense-grid / river builders | 1213–1641 | live |
| Graph subsystem | 2095–2450 | only the 0-exit path reachable; spine/arterial parts dead |
| Route-context subsystem | 2452–2616 | **entirely dead** (no callers) |
| Templates | 1752–2093 | near-dead (0-HSM + explicit road_type only) |
| Geometry/river/bridge core | 2618–3280 | live, the valuable part |

### 1.2 What is genuinely worth salvaging

The **bridge/crossing primitive layer** is good and lifts nearly verbatim:

- `_segment_intersection` (2968), `_path_river_crossings` (2949) — dedupe within
  `BRIDGE_LENGTH`, sorted along the road.
- The key invariant `_path_crossings_are_bound` (2681): *a path is legal iff
  every river crossing lies within `BRIDGE_LENGTH` of a registered bridge.*
  This is exactly the bookkeeping v2 needs.
- Bank classification (`_river_side_value/_sign`, `_path_endpoints_same_river_side`),
  bridge tangents (`_bridge_tangent_for_river`), nearest-existing-bridge choice.
- The detour kit: `_push_path_away_from_river`, `_same_bank_detour_path`,
  `_riverbank_template_path` (river-hug offset 42), arc-length trims.
- The **HSM shared-anchor contract** (`_road_anchor_world` + `_edge_key`):
  flanking tiles agree on one edge point. v2 keeps the *contract* but moves it
  into a persistent graph (see §3).
- `region_road_planner.gd`'s boundary/inset scaffolding (`_trace_boundary`,
  `_coastal_anchor_loop`, `_inset_polygon`) for orbital ring placement.

### 1.3 Debt and traps that fight v2

1. **No plan cache + disk I/O per redraw** (a fresh `RoadPlanner` per `_draw`).
2. **Total invalidation**: any `building_placed` / `construction_completed`
   anywhere clears the region cache and queues a full-map redraw — the exact
   opposite of incremental, and the known blocker for per-turn growth.
3. **Roads don't block anything**: `hex_map._road_segments_for_tile` has zero
   callers; every `is_subtile_buildable` call site passes `road_segments=[]`.
   Visual roads and occupancy are fully disconnected (buildings can sit on
   roads). Principle (k) will need this wired eventually — by design, not by
   accident.
4. **River-kind bug**: the planner's private river path builder only understands
   the `single` kind; `source`/`merge`/`joint` rivers get a bogus path through
   tile center — bridges and bank roads on those tiles are wrong today.
5. **River geometry triplication**: `RIVER_POINTS` + Bezier sampling exist in
   `subtile_grid.gd`, `river_visuals.gd`, and `road_planner.gd` (the third copy
   is the buggy one). v2 must extract a single static `RiverGeometry`.
6. **`SubtileGrid.hex_polygon()` is rotated 90°** from the real flat-top tile
   (pending bug chip) — it is the "inside the tile" gate for buildability and
   must be fixed before heights replace blocking.
7. Brute-force geometry everywhere (no spatial index); fine at current scale
   only because redraws are event-driven.

---

## 2. What the heightmap already gives us — and the one thing it doesn't

The terrain bake (`hill_field.gd`) computes a continuous elevation field over
the whole map on a 12-unit lattice, with everything roads need **alive at bake
time**: `ctx.grid` (field values), `ctx.types` (land/sea/hill/mtn/lake raster),
`ctx.coast_land` (organic coastline), `ctx.lake_blur` (lake shapes), river
valley caps, distance transforms. But `hills_baked.json` persists only render
polygons + binary blocked masks — **no height grid survives the bake**.

Principle (i) is therefore a bake change, not a runtime computation:

- Add a `_collect_levels` pass next to `_collect_blocked`
  (hill_field.gd:1946-1960): for **every** playable tile, emit per-subtile
  level (via `_band_at` at the existing subtile-center transform) plus a
  **water class channel** (LAND / SEA / LAKE / SOURCE_LAKE / RIVER_CORRIDOR).
  Lakes must be an explicit channel — their rims clamp to field 0.06–0.33,
  far below any threshold you could infer them from.
- Persist as `"heights"` in the bake (one hex digit per subtile + RLE for the
  water channel ≈ +0.4 MB on the current 5.4 MB). Bump `GEN_VERSION` so
  staleness detection forces a re-bake everywhere.
- Runtime: a lazy-static `TileHeights` registry beside `TileOccupancy`
  (`level_at(tile_id, col, row)`, `water_kind(...)`). During migration
  `TileOccupancy.is_blocked` simply becomes `level_at >= 3` so nothing
  downstream changes until roads opt into real costs.

---

## 3. The synthesized architecture

The judges split — feasibility preferred the turn-phased pipeline design
("RoadWorks"), aesthetics decisively preferred world-space cost-field routing
("Wayfield") — and both flagged the same grafts. The synthesis:

> **Wayfield's cost-field router as the core, inside RoadWorks' turn-phased
> work-order pipeline, organized by Atlas's persistent network graph.**

### Components

| Component | Kind | Responsibility |
|---|---|---|
| `heights` bake layer | baked | per-subtile level + water class (§2) |
| `river_geometry.gd` | static | single owner of river polylines, all 4 kinds, binned segment hash (kills the triplication) |
| `road_crossings.gd` | static, lazy | predetermined crossing(s) per river tile (principle a) |
| `road_network.gd` | persistent node / autoload | the graph: nodes (GATEWAY / CROSSING / ORBITAL_PORT / BUNCH / JUNCTION), edges (tier TRUNK/LOCAL, state PLANNED/BUILDING/BUILT, geometry, bridges, `planned_turn`), per-tile edge buckets; **serialized in saves** |
| `road_realizer.gd` | per-job | resumable, frame-budgeted A* over the height lattice + smoothing + junction merge + bridge emission; carries the salvaged primitive belt |
| `road_works.gd` | queue | turn-phased work orders: gameplay flag flips atomically in PROCESS; geometry plans under a 4 ms/frame budget; visuals reveal over ~3 s (principle j) |
| `road_visuals_v2` | render | static layer (settled network, redrawn on settlement only) + active layer (in-flight reveals only); tiered atlas styling |

### Data flow

CSV/bake (heights, rivers, cities) → static registries (heights, crossings,
river geometry) → `RoadNetwork` accumulates nodes/edges as players build →
`RoadRealizer` routes each edge through the cost field → smoothed segments +
bridges land in the network → visuals reveal them in chunks.

GATEWAY nodes reuse the undirected `_edge_key` convention so flanking tiles
share one node — the per-instance anchor cache disappears because **the graph
is the cache**. Invalidation becomes event-scoped (road built on/adjacent to a
tile; miniregion membership changed) — the map-wide `building_placed` redraw
handler is deleted.

---

## 4. The principles, mechanism by mechanism

**a) Predetermined river crossings.** Built lazily at first query from baked
field + CSV (both static → fixed for the whole game, no serialization). Per
river *arm* (1 for `single`; 2 where `exit_hsm_2` branches): crossing = argmin
over polyline samples of
`2.0·|level(bank_a) − level(bank_b)| + 0.05·max(level) + edge_proximity_penalty + tangent_instability`,
ties by sample index. Output includes bridge tangent and two *gate* points at
±(BRIDGE_LENGTH/2 + 6). Routing-wise the river corridor is impassable **except
within ~18 px of a gate** — crossings are mandatory without waypoint plumbing.
⚠ Seam rule (judge-flagged): rivers cross HSM edges, so adjacent river tiles
must canonicalize crossings near a shared edge with the same undirected
edge-key trick as gateways, or two bridges 60 px apart will straddle seams.

**b) Hug rivers / be efficient.** Step-cost multiplier 0.85 inside the hug band
(30–60 px from the river, centred on v1's proven 42), 1.15 when crowding
(13–30 px). Efficiency is the A* objective itself (ε = 1.1 weighted).

**c) Height costs with hysteresis.** Step cost = base ×
`(1 + 0.5·|level(v) − level(u)|)` — 50% per altitude level changed — plus a mild
per-step surcharge `×(1 + 0.03·max(level, 0))` so equal-length options prefer
the valley floor. "Prefers to stay at the new height" is *emergent*: staying
costs nothing, re-transitioning pays again; the simplification pass refuses
shortcuts that change level more often than the raw path did.
⚠ Open decision: 50% **per level crossed** (a 2-level jump costs +100%) vs per
transition event. The panel recommends per-level (above); confirm.

**d) Lakes are obstacles.** LAKE and SOURCE_LAKE water classes are
infinite-cost. Explicit channel, not inferred from height (see §2).

**e) Only −1 and above tolerate roads.** Passability = `water_class == LAND`
(and outside the river corridor except at gates). Level is **never** a hard
block for roads — bands −1..10 are all routable, only priced. This formally
ends BLOCK_FIELD-style binary cliffs for road routing (principle i).

**f) Curves; crossroads only at genuine meetings.** A* state is
(cell, direction-octant) with turn penalties: straight 0, 45° +0.2·STEP,
90° +0.9·STEP, ≥135° +3.0·STEP; Catmull-Rom smoothing (min turn radius ~28 px)
converts the 45° staircase into arcs. Junctions: a route ending within ~10 px
of an existing segment splits it into a 3-way node; cells within ~24 px of the
existing network get cost ×0.6 (**reuse discount**) so new roads merge and run
along old ones — T-junctions are the natural outcome. A 4-way crossroads forms
only when a new path transversally crosses an existing segment with both sides
continuing and crossing angle ≥50°.

**g) Urban miniregions with orbitals.** Miniregion = flood-fill cluster of
urban tiles (re-clustered when membership changes). Keep
`region_road_planner.gd`'s boundary/inset scaffolding to place 8–12
ORBITAL_PORT waypoints; the ring itself is *routed* through the cost field
between consecutive ports (not clamped geometry), so the ≤50% overflow into
non-urban neighbours happens exactly where the heightmap allows it and nowhere
else. Trunk roads attach at ports — defined junctions, like real ring-road
interchanges.

**h) Building bunches.** BUNCH nodes with the formal invariant
`bunch.created_turn < edge.planned_turn` — roads only connect bunches that
existed before the road was planned. API lands now; populated when buildings
get map footprints.

**i) Heights instead of blocking.** §2. `SubtileGrid.is_subtile_buildable`
remains the single choke point: its TileOccupancy check becomes a height/water
rule, and its rotated `hex_polygon()` must be fixed first (pending chip).

**j) Chunked layout over ~3 s.** RoadWorks pipeline: the gameplay flag flips
atomically during PROCESS (turn correctness unchanged — transport routing never
waits on geometry). Geometry planning runs in `_process` under
`PLAN_BUDGET_MS = 4.0` with a *resumable* A* (budget checked every N
expansions); visuals reveal each order over `REVEAL_DURATION = 3.0 s`, with
concurrent reveals. Worst case examined: 100 road tiles completing in one turn
≈ 300–400 ms of planning spread over ~75–100 frames with zero over-budget
frames; the whole batch is visually complete ~4–5 s after the turn. Save/load
mid-layout: finished geometry persists in the network; unfinished orders
re-plan deterministically from the queue.

**k) Building symbiosis (future).** The network's per-tile edge buckets +
`road_segments` already give future building-placement the query it needs
("does this footprint cross a road?"). Nothing else built now — but the v1
discovery that roads block nothing today means (k) starts from an honest
baseline.

---

## 4.5 Gateways: tile entry/exit policy

**Topology: demand-driven hierarchy, not adjacency.** v1 already caps visible
exits at 3–4 per tile (spread scoring) because 6-way connection reads as a
triangular lattice; v2 goes further — edges exist because of *demand events*,
never because two road tiles happen to touch:

- **TRUNK** edges come from the network (crossings, orbital ports,
  inter-region corridors) and are routed as **single multi-tile jobs** — a
  trunk crosses six tiles as one polyline with no internal seams.
- **LOCAL** rule on road-tile creation: enqueue exactly one job, *"connect to
  the nearest point of the existing network"*. The reuse discount turns this
  into a T-junction merge. Additional jobs only if a road neighbour is not
  reachable through the drawn network within a ~2-tile detour.
- Result: degree emerges (dead-end spurs allowed, 6-way stars structurally
  impossible); a tile ringed by road neighbours shows a trunk passing through
  plus at most one joining spur. The gameplay boolean is honoured as a
  *network* property (adjacent road pairs connected through the network), not
  per shared edge — `catalog.gd` routing only consumes the boolean.

**Geometry: terrain-elected gateways, not enumerated slots.** Multi-tile
routes cross hex edges wherever the cost field dictates — i.e. at local height
minima, the way real roads cross ridgelines at passes. Fixed quarter-point
slots (even randomized) would re-print a hex-edge rhythm onto the map.
Gateway points are only *needed* where jobs split (a route ends at an edge and
a later job continues from the far side; miniregion boundaries; the one-time
CSV re-seed). Mechanism:

1. **First-writer-wins, graph-stored**: the first route to reach a shared edge
   records crossing point **and arrival tangent** on the GATEWAY node
   (undirected edge key — both tiles see the same node). Later jobs on the far
   side take that point+tangent as a boundary constraint. This single
   mechanism is also the fix for the tangent-continuity kink risk (§7.3).
2. **Election rule when no route exists yet** (CSV re-seeding, pre-planned
   gateways): deterministic and terrain-derived — argmin of height along the
   shared edge, ≥40 units from hex corners, river-cleared (reuse v1's
   `_offset_anchor_to_buildable_edge` tangent search), ±5% deterministic
   jitter for wobble. HSM midpoints survive only as the tie-break default on
   featureless edges.
3. **One gateway per tile-pair edge** (crossroads rule (f) governs meetings);
   per-tile gateway degree soft-capped at 3 unless a trunk passes through.

---

## 5. Performance plan and the Phase-0 gate

Both judges converged on one hard prerequisite: **benchmark before
architecture hardens.** The three designs' GDScript A* per-expansion estimates
spanned 50× (0.1–5 µs). Phase 0 is a half-day spike: route random pairs over
the real baked lattice on target hardware, measure µs/expansion. Every budget
(4 ms slice, 3 s reveal, single-tile vs corridor routing, the
coarsen-lattice / C#-port escape hatches) keys off that number.

Eliminated v1 traps: no planner construction or JSON disk read per redraw, no
map-wide replans on building placement, no per-call river tessellation
(water pre-baked), no brute-force crossing scans in hot paths (crossings are
predetermined).

---

## 6. Migration from v1

1. Bake heights (+ water classes, lake rims, river mouths) — GEN_VERSION bump.
2. Extract `RiverGeometry` (fixes the source/merge/joint river bug as a side
   effect — v1's river builder gets the correct polylines too).
3. Fix `hex_polygon()` rotation (pending chip) before heights replace blocking.
4. Stand up `RoadNetwork` + realizer behind a debug flag; route NEW
   construction through v2 while existing CSV-seeded road tiles keep v1 art.
5. Migrate city beltways to routed orbitals (RegionRoadPlanner scaffolding
   reused for port placement, then retired).
6. Re-seed the hand-painted starting road network as v2 edges (one-time bake
   of the CSV `road_hsms` topology through the realizer); delete v1 planners
   (~2,400 lines, including all four dead generations).

---

## 7. Risks & gaps the panel flagged (do not lose these)

1. **Benchmark first** (§5) — exit criterion for Phase 0.
2. **Crossing dedup at hex seams** — canonicalize per river arm across tiles.
3. **Tangent continuity at shared anchors**: flanking tiles agree on the
   anchor *point* but not the arrival *direction*; per-route smoothing can
   kink at every gateway and print the hex grid onto long roads. Fix: store
   an agreed tangent on the GATEWAY node (first router to arrive sets it;
   the neighbour route receives it as a boundary constraint).
4. **The atlas visual language is the aesthetic** — tiered styling
   (orange trunk 6 px / yellow local 4 px with casing outlines, roundabout
   glyphs at orbital ports) must ship with v2, not after; a perfect router
   drawn as uniform black lines still reads as spiderweb.
5. **50%-penalty semantics** (per level vs per transition) — designer call.
6. **Determinism hygiene**: explicit FNV-1a hashing for seeds (GDScript
   `hash()` is not guaranteed stable across engine versions); ±5%
   deterministic per-subtile cost jitter for organic wobble.
7. **Mass-build worst case** is the design's stress test (100 tiles/turn);
   keep it as an automated perf test, not a hope.

## 8. Open questions for the designer

1. 50% penalty: per altitude level crossed, or per transition event?
2. Should trunk (orange) roads pay a *higher* turn penalty than local (yellow)
   ones — straighter A-roads, twistier B-roads?
3. Orbital ring tier: always trunk, or tier by miniregion size?
4. Do predetermined crossings ever upgrade (ford → bridge art) with tech?
5. Reveal order during the 3 s: outward from the construction site, or
   network-topological (trunk first)?
6. Lake-rim roads: principle (d) makes lakes obstacles — may roads use the
   constant-level rim as a scenic corridor (cheap ring around lakes), or
   should rims carry a small penalty to avoid every lake growing a ring road?

## 9. Suggested phases

- **Phase 0** — A* benchmark spike (gate); `RiverGeometry` extraction;
  `hex_polygon()` fix.
- **Phase 1** — heights/water bake layer + `TileHeights`; blocking becomes
  level-derived (no behavior change).
- **Phase 2** — `RoadNetwork` + crossings registry + realizer core (cost
  function b/c/e/f), behind a debug flag; tiered rendering.
- **Phase 3** — RoadWorks queue + 3 s chunked reveal (j); event-scoped
  invalidation replaces map-wide redraws.
- **Phase 4** — miniregion orbitals (g); migrate cities; retire v1 city code.
- **Phase 5** — re-seed CSV roads through v2; delete v1 planners; bunch API (h)
  stubbed for buildings (k).
