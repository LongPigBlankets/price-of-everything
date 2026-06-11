# Roads v2 — review of the existing system & design for organic heightmap-driven roads

Status: **design with decisions taken** (no implementation in this branch yet).
Inputs: multi-agent review of the road + terrain code (3 readers), three competing
architecture designs, two adversarial judges, plus designer rulings on the
decision gates (2026-06-11, see §8.5).

Reference aesthetic: a UK regional road atlas — organic curving A-roads (orange)
and B-roads (yellow), ring roads around urban areas, valley- and river-following
trunk routes, serpentine mountain ascents.

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

### 1.2 What is salvaged (designer ruling: keep this, nuke the rest)

The **bridge/crossing primitive layer** lifts nearly verbatim:

- `_segment_intersection` (2968), `_path_river_crossings` (2949) — dedupe within
  `BRIDGE_LENGTH`, sorted along the road.
- The key invariant `_path_crossings_are_bound` (2681): *a path is legal iff
  every river crossing lies within `BRIDGE_LENGTH` of a registered bridge.*
- Bank classification (`_river_side_value/_sign`, `_path_endpoints_same_river_side`),
  bridge tangents (`_bridge_tangent_for_river`), nearest-existing-bridge choice.
- The detour kit: `_push_path_away_from_river`, `_same_bank_detour_path`,
  `_riverbank_template_path` (river-hug offset 42), arc-length trims.
- The **HSM shared-anchor contract** (`_road_anchor_world` + `_edge_key`) as the
  *convention* for shared graph nodes (the cache moves into the network graph).
- `region_road_planner.gd`'s boundary/inset scaffolding (`_trace_boundary`,
  `_coastal_anchor_loop`, `_inset_polygon`) for orbital ring port placement.

Everything else — all four planner generations, templates, repair passes,
dense grids — **is deleted** in Phase 5 (big-bang migration, §6).

### 1.3 Debt and traps v2 eliminates

1. **No plan cache + disk I/O per redraw** (a fresh `RoadPlanner` per `_draw`).
2. **Total invalidation**: any `building_placed` / `construction_completed`
   anywhere clears the region cache and queues a full-map redraw.
3. **Roads don't block anything**: `hex_map._road_segments_for_tile` has zero
   callers; every `is_subtile_buildable` call site passes `road_segments=[]`.
   Buildings can sit on drawn roads today. (Ruled: v2 fixes this — §4 (k).)
4. **River-kind bug**: the planner's private river path builder only understands
   the `single` kind; `source`/`merge`/`joint` rivers get a bogus path through
   tile center — bridges and bank roads on those tiles are wrong today.
5. **River geometry triplication**: `RIVER_POINTS` + Bezier sampling exist in
   `subtile_grid.gd`, `river_visuals.gd`, and `road_planner.gd` (the third copy
   is the buggy one). v2 extracts a single static `RiverGeometry`.
6. **`SubtileGrid.hex_polygon()` is rotated 90°** from the real flat-top tile —
   ruled: fixed in Phase 0 (pending bug chip).
7. Brute-force geometry everywhere (no spatial index).

---

## 2. What the heightmap provides — and the one missing layer

The terrain bake (`hill_field.gd`) computes a continuous elevation field over
the whole map on a 12-unit lattice, with everything roads need **alive at bake
time**: `ctx.grid` (field values), `ctx.types` raster, `ctx.coast_land`,
`ctx.lake_blur`, river valley caps, distance transforms. But
`hills_baked.json` persists only render polygons + binary blocked masks — **no
height grid survives the bake**.

Principle (i) is therefore a bake change, not a runtime computation: a
`_collect_levels` pass beside `_collect_blocked` emits, for every playable
tile, per-cell **level + water class** (LAND / SEA / LAKE / SOURCE_LAKE /
RIVER_CORRIDOR — lakes must be an explicit channel; their rims clamp to field
0.06–0.33 and cannot be inferred from height). Persisted as a `"heights"` key
(hex digits + RLE water channel), GEN_VERSION bump, decoded once at runtime
into a lazy-static `TileHeights` registry beside `TileOccupancy`. During
migration `TileOccupancy.is_blocked` ≡ `level_at >= 3` so nothing downstream
changes until roads opt into real costs.

### 2.1 Lattice resolution (decided: finest affordable; benchmark picks)

Ruling: prefer the **denser grid** — higher zooms will eventually show more
road detail — with the Phase-0 benchmark deciding what we can afford. The
candidate matrix (map ≈ 12,950 × 10,500 world units incl. decorative border):

| Lattice | Cells | Height layer (raw) | Notes |
|---|---|---|---|
| 20u (subtile) | ~340k | ~340 KB | gameplay-aligned, coarsest |
| **12u (= hills field)** | **~944k** | **~950 KB** | free — the bake already computes exactly this grid |
| 8u | ~2.1M | ~2.1 MB | resample field at bake (cheap); A* area ×2.25 vs 12u |
| 6u | ~3.8M | ~3.8 MB | A* area ×4 vs 12u |

Two clarifications that bound how fine we *need* to go:

- **Lattice fineness controls path-placement fidelity** (how precisely a road
  hugs a contour or threads a gap), not visual smoothness — Catmull-Rom
  smoothing already removes lattice staircase at any resolution.
- **Road density at high zoom is network density** (more LOCAL edges per
  region, governed by the hand-authored region identities, §3.1), not lattice
  resolution. A 12u lattice can carry arbitrarily dense networks; what it
  cannot do is place two parallel roads closer than ~2 cells (~24u ≈ 1.2
  subtiles), which is already denser than v1 ever draws.

Plan: bench 12u and 8u (20u only as a fallback datum). 12u is the default —
it is literally the grid the bake already computes and throws away. Go to 8u
only if µs/expansion × worst-case search area stays inside the 4 ms slice.
Per-subtile (20u) heights are exported *as well* for gameplay queries
(`TileHeights.level_at(tile_id, col, row)`) regardless of navgrid choice.

---

## 3. The synthesized architecture

> **Cost-field A\* routing core (Wayfield) inside a turn-phased work-order
> pipeline (RoadWorks), organized by a persistent network graph (Atlas),
> styled by hand-authored region identities.**

### Components

| Component | Kind | Responsibility |
|---|---|---|
| `heights` bake layer | baked | navgrid level + water class (§2), per-subtile levels for gameplay |
| `data/road_regions.json` | hand-authored | region → member tiles + identity (§3.1) |
| `river_geometry.gd` | static | single owner of river polylines, all 4 kinds, binned segment hash |
| `road_crossings.gd` | static, lazy | predetermined quartile crossings per river tile (§4 a) |
| `road_network.gd` | persistent, **saved** | the graph: nodes (GATEWAY / CROSSING / ORBITAL_PORT / BUNCH / JUNCTION), edges (tier, state, geometry, bridges, `planned_turn`), per-tile edge buckets |
| `road_realizer.gd` | per-job | resumable frame-budgeted A* + serpentine handling + smoothing + junction merge + bridge emission; carries the salvaged primitive belt |
| `road_works.gd` | queue | turn-phased work orders; gameplay flag atomic in PROCESS; 4 ms/frame planning; ~3 s chunked reveal |
| `road_visuals_v2` | render | static layer (settled network) + active layer (in-flight reveals); tiered atlas styling |

### 3.1 Hand-authored region identities (designer ruling)

A new input replaces auto-detected miniregion *identity* (clustering still
finds tile groups; the designer names what they are):
`data/road_regions.json`: `{region_id: {tiles: [...], identity: dense_city |
sparse_city | dense_rural | sparse_rural | mountain_range}}`.

Identity drives a style table (all tunables in one place):

| Identity | Wiggle (cost jitter amp) | Interconnections (redundant LOCAL links) | Local density | Orbital |
|---|---|---|---|---|
| dense_city | low | high (grid-like mesh) | high | yes |
| sparse_city | medium | medium | medium | yes |
| dense_rural | medium | low-medium | medium | no |
| sparse_rural | high | low (spurs + single links) | low | no |
| mountain_range | high | minimal (one pass road) | minimal | no |

Tiles outside any region default to sparse_rural. The orbital-ring machinery
(§4 g) keys off identity, not raw urban-tile clustering.

### Data flow

CSV/bake (heights, rivers) + `road_regions.json` → static registries
(heights, crossings, river geometry, region styles) → `RoadNetwork`
accumulates nodes/edges as players build → `RoadRealizer` routes each edge
through the cost field → smoothed segments + bridges land in the network →
visuals reveal them in chunks. Invalidation is event-scoped; the map-wide
`building_placed` redraw handler is deleted.

---

## 4. The principles, mechanism by mechanism

**a) Predetermined river crossings (designer ruling: quartile points).** Per
river *arm* on a tile (1 for `single`; 2 where the river branches), the
crossing is a **seeded random pick among the ¼, ½, and ¾ arc-length points**
of that arm's polyline within the tile. Branch tiles get one crossing per arm.
Output per crossing: {point, river tangent, perpendicular bridge tangent, two
gate points at ±(BRIDGE_LENGTH/2 + 6)}. Routing-wise the river corridor is
impassable except within ~18 px of a gate — crossings are mandatory without
waypoint plumbing. Side effect of the quartile rule: crossings are interior to
the tile by construction, so the hex-seam duplicate-crossing risk from the
panel review largely evaporates (kept as a cheap assert, not a mechanism).

**b) Hug rivers / be efficient.** Step-cost ×0.85 inside the hug band
(30–60 u from the river, centred on v1's proven 42), ×1.15 when crowding
(13–30 u). Efficiency is the A* objective itself (ε = 1.1 weighted).

**c) Height costs + serpentine ascents (designer ruling).** Step cost = base ×
`(1 + 0.5·|level(v) − level(u)|)` — **50% per altitude level crossed** (a
2-level climb costs +100%). "Prefers to stay at the new height" is emergent:
staying costs nothing, re-transitioning pays again; the simplification pass
refuses shortcuts that change level more often than the raw path did.

*Serpentines:* climbs of more than one level must wind perpendicular to the
ascent. Mechanism is emergent, not templated:

- **Gradient-alignment penalty**: on steep cells (local slope ≥ ~1 level per
  2 cells), step cost ×(1 + k·|dot(step_dir, ∇height)|), k ≈ 1.5 — moving
  *along* the gradient is expensive, traversing *across* it is cheap, so A*
  naturally tacks diagonally up slopes.
- **Conditional hairpin allowance**: the ≥135° turn penalty (which normally
  forbids hairpins) is waived when both adjacent steps are on steep cells and
  the elevation gained since the last reversal exceeds ~1 level — without
  this, the turn costs would fight the zigzag and A* would pay the direct
  climb instead.
- Post-check: any realized segment ascending ≥2 levels must contain ≥2
  direction reversals; failures re-route with doubled k (assert in tests).

**d) Lakes are obstacles.** LAKE and SOURCE_LAKE water classes are
infinite-cost. Explicit channel, not inferred from height. *Lake rims*
(designer ruling): roads may hug the rim — no special discount or penalty;
the rim's constant level makes it naturally cheap, and normal height rules
apply on the way in and out.

**e) Only −1 and above tolerate roads.** Passability = `water_class == LAND`
(and outside the river corridor except at gates). Level is never a hard block
for roads — bands −1..10 all routable, only priced.

**f) Curves; crossroads only at genuine meetings.** A* state is
(cell, direction-octant); turn penalties: straight 0, 45° +0.2·STEP,
90° +0.9·STEP, ≥135° +3.0·STEP (waived per the hairpin rule above);
Catmull-Rom smoothing (min turn radius ~28 u). Junction rules: route ending
within ~10 u of an existing segment splits it into a 3-way node; cells within
~24 u of the network get cost ×0.6 (reuse discount) so roads merge and run
along each other — T-junctions are the natural outcome. A 4-way crossroads
forms only on a transversal crossing with both sides continuing and angle
≥50°. **Wiggle amount and interconnection count come from the region style
table (§3.1)**: wiggle = deterministic per-cell cost jitter amplitude;
interconnections = how many redundant LOCAL jobs the region enqueues.

**g) Urban miniregions with orbitals.** Regions with city identity get an
orbital: `region_road_planner.gd`'s boundary/inset scaffolding places 8–12
ORBITAL_PORT waypoints; the ring is *routed* through the cost field between
consecutive ports, so the ≤50% overflow into non-urban neighbours happens
exactly where the heightmap allows. Trunk roads attach at ports.

**h) Building bunches.** BUNCH nodes with the invariant
`bunch.created_turn < edge.planned_turn` — roads only connect bunches that
existed before the road was planned. API lands now; populated when buildings
get map footprints.

**i) Heights instead of blocking.** §2. `SubtileGrid.is_subtile_buildable`
remains the single choke point: TileOccupancy check becomes a height/water
rule; the rotated `hex_polygon()` is fixed in Phase 0.

**j) Chunked layout (designer ruling on order).** Gameplay flag flips
atomically during PROCESS; geometry planned in `_process` under
`PLAN_BUDGET_MS = 4.0` with resumable A*; visuals reveal over
`REVEAL_DURATION ≈ 3.0 s`. **Reveal order: grow from the existing network —
start at the connection edge on already-built tiles and extend outward into
the new tiles; trunk segments reveal before their branches.** Worst case
examined: 100 road tiles in one turn ≈ 300–400 ms planning spread over
~75–100 frames, batch visually complete ~4–5 s after the turn. Save/load
mid-layout: finished geometry persists; unfinished orders re-plan
deterministically from the queue.

**k) Roads block pixels (designer ruling: yes, now).** v2 registers road
footprints into `TileOccupancy` from day one: blocked corridor = road
half-width + small buffer (~width/2 + 3 u, matching v1's `ROAD_BUILD_BUFFER`),
so buildings can sit close to roads but never on them. This also feeds the
**congestion mechanic** (designer ruling on tiers): each tile carries a
congestion factor = fraction of subtiles occupied (buildings + roads). High
congestion raises local routing costs, so crowded tiles narratively force
roundabout, wiggly routes instead of straight lines — and when buildings get
real footprints later (k), the same factor keeps working with no new design.

---

## 4.5 Gateways: tile entry/exit policy

**Topology: demand-driven hierarchy, not adjacency.** Edges exist because of
demand events, never because two road tiles touch:

- **TRUNK** edges come from the network (crossings, orbital ports,
  inter-region corridors) and are routed as **single multi-tile jobs** — no
  internal seams.
- **LOCAL** rule on road-tile creation: enqueue one job, *"connect to the
  nearest point of the existing network"* (reuse discount → T-junction
  merge). The region's interconnection style (§3.1) adds redundant LOCAL jobs
  in dense identities. Additional connectivity jobs only if a road neighbour
  is unreachable through the drawn network within a ~2-tile detour.
- **Tier assignment (designer ruling): contextual, not fixed by origin.**
  Base tier by origin (crossing/orbital/inter-region = trunk; tile-connect =
  local), then locally modulated: how many nearby tiles carry roads, and how
  congested the corridor tiles are. A heavily-roaded corridor upgrades the
  through-edge's visual weight; a congested tile downgrades straightness
  (higher effective wiggle) regardless of tier.
- Result: degree is emergent (dead-end spurs allowed, 6-way stars
  structurally impossible); the gameplay boolean is honoured as a *network*
  property — `catalog.gd` routing only consumes the boolean.

**Geometry: terrain-elected gateways, not enumerated slots.** Multi-tile
routes cross hex edges wherever the cost field dictates (local passes).
Gateways only exist where jobs split. Mechanism:

1. **First-writer-wins, graph-stored**: the first route to reach a shared edge
   records crossing point **and arrival tangent** on the GATEWAY node
   (undirected edge key). Later jobs take both as boundary constraints — this
   is also the tangent-continuity fix (§7).
2. **Election when no route exists yet** (CSV re-seed): deterministic —
   height-argmin along the shared edge, ≥40 u from corners, river-cleared
   (v1's `_offset_anchor_to_buildable_edge` search), ±5% seeded jitter. HSM
   midpoints survive only as the featureless-edge tie-break.
3. **One gateway per tile-pair edge**; per-tile gateway degree soft-capped at
   3 unless a trunk passes through.

---

## 5. Performance plan, the Phase-0 gate, and the escape ladder

**Benchmark first.** The three designs' GDScript A* per-expansion estimates
spanned 50× (0.1–5 µs). Phase 0: route random pairs over the real baked
lattice at **12u and 8u** on target hardware; measure µs/expansion; derive
worst-case search areas for the longest realistic trunk job. Exit criterion
for every budget (4 ms slice, 3 s reveal, lattice choice §2.1).

**Escape ladder if the numbers disappoint (designer question 7 answered —
C# de-prioritized):**

1. **Corridor-bounding**: restrict each job's search space to a capsule
   around the straight line between endpoints (×3–10 area reduction, no
   quality loss for sane corridors).
2. **Hierarchical routing**: route trunk jobs on a 24u downsample, then
   refine per-segment on the fine lattice (×4+ on long jobs).
3. **Per-region lattice**: fine lattice only inside city identities; 12u
   elsewhere.
4. **GDExtension (C++) module** for the inner A* loop only — last resort.

**Why not C#:** Godot's C# (.NET) typically gives 5–20× on tight numeric
loops over GDScript (real arrays, JIT, no Variant boxing) — but it brings the
.NET toolchain into the project for every contributor, complicates exports,
and **Godot 4 C# does not support web export** — which would close the door
on a browser demo build, a real distribution option for the beta. The
cross-language call overhead also means only the hot loop could move anyway —
which is exactly what GDExtension does without the platform cost. C# is
struck from the ladder.

Eliminated v1 traps: no planner construction or JSON disk read per redraw, no
map-wide replans on building placement, no per-call river tessellation, no
brute-force crossing scans (crossings predetermined).

---

## 6. Migration from v1 (designer ruling: nuke and re-seed)

1. Bake heights (+ water classes, lake rims, river mouths) — GEN_VERSION bump.
2. Extract `RiverGeometry` (fixes the source/merge/joint river path bug for
   anything that still reads river polylines).
3. Fix `hex_polygon()` rotation (pending chip) before heights replace blocking.
4. Stand up `RoadNetwork` + realizer + region styles behind a debug flag.
5. **Big-bang cutover**: re-seed the hand-painted CSV road network through the
   v2 realizer once (one designer approval pass over the result), then
   **delete v1 wholesale** — all four planner generations, templates, repair
   passes (~2,400+ lines). Only the salvage list (§1.2) survives, relocated
   into `road_realizer.gd` / `river_geometry.gd`. The `road_type`,
   `road_hsms`, `road_density` CSV columns retire; `road_regions.json` takes
   over pattern control; `road_seed` survives as the per-tile determinism
   seed.

---

## 7. Risks (updated after rulings)

1. **Benchmark first** (§5) — Phase-0 exit criterion.
2. **Tangent continuity at shared gateways** — solved by design (first-writer
   stores point + tangent); keep a visual test (long trunk across 4+ tiles,
   no kinks at seams).
3. **Hairpin/turn-penalty interaction** (new, from the serpentine ruling):
   the waiver condition must be tight or flatland routes will exploit free
   hairpins; covered by the ≥2-reversals post-check + a flatland no-hairpin
   assert.
4. **The atlas visual language ships WITH the router** (tiered widths/colors,
   casing, roundabout glyphs at ports) — a perfect router drawn as uniform
   black lines reads as spiderweb.
5. **Quartile crossings vs terrain**: a seeded quartile point can land on a
   poor spot (steep bank). Accepted by ruling (simplicity + variety win);
   keep bank-level delta as a tie-break among the three candidates if it
   bothers the eye in practice.
6. **Determinism hygiene**: FNV-1a style explicit hashing for seeds (GDScript
   `hash()` is not guaranteed stable across engine versions); ±5%
   deterministic per-cell cost jitter scaled by region wiggle.
7. **Mass-build worst case** (100 tiles/turn) stays an automated perf test.

## 8. Remaining open questions

1. Trunk vs local turn-penalty split (straighter A-roads, twistier B-roads)?
   — likely fold into the region style table as a per-identity multiplier.
2. Do predetermined crossings ever upgrade visually (ford → bridge art)?
   Schema field reserved.
3. Region style table numbers (§3.1) — first pass at implementation time,
   tuned against the reference atlas.

## 8.5 Decision log (designer rulings, 2026-06-11)

| # | Decision | Ruling |
|---|---|---|
| 1 | Lattice resolution | **Finest affordable**; 12u default (= hills field), bench 8u; density at zoom comes from network density via region identities; per-subtile heights exported for gameplay regardless |
| 2 | 50% penalty semantics | **Per level crossed** (2-level climb = +100%); multi-level climbs must serpentine perpendicular to ascent (emergent: gradient-alignment penalty + conditional hairpin waiver) |
| 3 | Persistence / order-dependence | **Save stores the network as built**; build order produces different networks — accepted ("same save, same result" is the only guarantee) |
| 4 | Migration | **Nuke v1**, keep bridge logic + salvage list; pattern control moves to hand-authored `road_regions.json` (dense/sparse city, dense/sparse rural, mountain range) |
| 5 | Roads in occupancy | **Yes** — block road corridor + small buffer so buildings get close but never on top |
| 6 | Tier rule | **Contextual**: origin base + nearby road count + tile congestion (occupied-subtile fraction forces roundabout routes) |
| 7 | C# | **Struck** — no web export in Godot 4 C#, toolchain cost; escape ladder is corridor-bounding → hierarchical routing → per-region lattice → GDExtension |
| 8 | River crossings | **Seeded quartile pick** (¼ / ½ / ¾ of the arm's in-tile arc length; one per arm, two on branch tiles) |
| — | Lake rims | Roads may hug rims; normal height rules, no special pricing |
| — | Reveal order | From existing network at the connection edge, outward; trunk before branches |

## 9. Phases

- **Phase 0** — A* benchmark spike at 12u and 8u (gate); `RiverGeometry`
  extraction; `hex_polygon()` rotation fix (pending chip).
- **Phase 1** — heights/water bake layer (navgrid at chosen resolution +
  per-subtile levels) + `TileHeights`; blocking becomes level-derived
  (no behavior change); `road_regions.json` format + loader.
- **Phase 2** — `RoadNetwork` + quartile crossings registry + realizer core
  (cost function b/c/e/f incl. serpentine rules), behind a debug flag;
  tiered atlas rendering.
- **Phase 3** — RoadWorks queue + chunked reveal (j) with
  network-outward/trunk-first order; event-scoped invalidation; road
  footprints into TileOccupancy (k).
- **Phase 4** — region-identity styles + orbitals (g) for city identities.
- **Phase 5** — big-bang re-seed of CSV roads through v2 (designer approval
  pass); delete v1 planners; bunch API (h) stubbed for buildings.
