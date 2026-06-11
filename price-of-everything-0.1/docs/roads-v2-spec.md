# Roads v2 — implementation spec (phased, benchmarked, executable)

Companion to `docs/roads-v2-design.md` (architecture rationale + decision log
§8.5). This document is the execution plan: every phase has concrete
deliverables, file-level specs, benchmarks with pass/fail thresholds, tests,
and an exit checklist. Constants carry rationale; change them knowingly.

Already on this branch: the design doc, `data/road_regions.json`
(50 hand-authored regions, identities inferred then designer-edited — see
Appendix B for the review flags), `scripts/road_regions.gd`, the benchmark
harness, and the merged forest-visuals work (PR #34).

---

## 0. Ground rules

- **Determinism**: same save + same inputs → same roads. Build *order*
  changes the network (ruled acceptable). All seeds via an explicit FNV-1a
  helper (`RoadHash.fnv1a(s: String) -> int`) — GDScript `hash()` is not
  guaranteed stable across engine versions and the network persists in saves.
- **The bake is canonical**: terrain inputs to routing come from
  `hills_baked.json`; the game never regenerates terrain at runtime.
- **Turn correctness is atomic**: the gameplay `infrastructure_present`
  flag flips during PROCESS exactly as today. Geometry/visuals are *eventually
  consistent* (≤ ~5 s) and never gate a turn.
- **Feature flag**: everything ships behind `RoadNetwork.V2_ENABLED`
  (debug-terminal toggle `toggle roadsv2`) until Phase 5 cutover.
- Each phase ends with: headless editor compile clean, full test suite green,
  and the phase's exit checklist below.

---

## 1. Forests (new input — treat as the first real building obstacle)

What exists (merged forest-visuals): Old Growth Forest `b_016` is auto-seeded
at game start, one per rural/hill tile in rows 1–6 (`world_map.gd::
_place_northern_old_growth_forests`, owner `"tile_data"`); New Growth `b_015`
is plantable. They are **real MatchState buildings** (persist in saves) drawn
by `forest_visuals.gd` as a deterministic seeded blob: a centre picked from 28
seeded candidates (water-cleared, ≥28 u inside the hex) plus lobes reaching
~25 u — an effective footprint of **Ø ≈ 50–60 u (~2.5×2.5 subtiles)**.

Decisions:

1. **Single source of truth for the footprint.** Extract the centre + lobe
   computation into `scripts/forest_footprint.gd`
   (`static func footprint(instance_id, tile_id, coord, terrain) ->
   {center: Vector2, radius: float}` — radius = max lobe reach + 4 u pad).
   `forest_visuals.gd` refactors to call it; routing and occupancy consume
   the *same* numbers. Rationale: if visuals and obstacles compute the blob
   independently they WILL diverge after the next visual tweak.
2. **Roads treat forests as hard obstacles** (designer: "have to be avoided
   once built"): the routing layer carries a *dynamic obstacle overlay* —
   per-tile list of forest discs (centre, radius + `FOREST_ROAD_BUFFER := 8.0`)
   rebuilt from `MatchState.buildings` on load and maintained by
   `building_placed`/`building_removed`. Not baked (forests are plantable and
   removable at runtime). A* treats cells inside a disc as impassable.
3. **Occupancy**: in Phase 3, forests register their disc → subtile bits in
   `TileOccupancy` (same dynamic-producer API as road corridors), so future
   building placement respects them too, and they feed the congestion factor.
4. **Principles (h)/(k)**: the game-start northern forest belt is the first
   pre-existing "building bunch" — trunk routes through rows 1–6 must thread
   between forests from turn 0, which is exactly the organic look we want.

Tests: footprint determinism (same instance → same disc across two calls and
across save/load); a route through a forest-dense tile never intersects any
disc; visual blob ⊆ footprint disc (sample lobe extremes).

---

## 2. Phase 0 — gates and ground truth

### 0.1 `RiverGeometry` extraction

New `scripts/river_geometry.gd` (static), the single owner of river polylines:

- API: `arms(tile_coord) -> Array[{points: PackedVector2Array, kind, exits}]`
  (handles all four CSV kinds: single / joint / source / merge — port the
  sampling from `subtile_grid.gd:159-241`, the only complete implementation),
  `lake_ellipse(tile_coord) -> {center, rx, ry}` or empty,
  `dist_to_water(p, tile_coord)`, plus a world-space binned segment hash for
  global queries.
- Consumers migrate: `subtile_grid.gd`, `river_visuals.gd` (drawing keeps its
  own mouth-extension cosmetics), `forest_visuals.gd`'s private river cache,
  and v1 `road_planner.gd`'s buggy single-kind copy (this **fixes the
  source/merge/joint bridge bug** as a side effect, visible immediately).
- Tests: every river tile yields ≥1 arm; arm endpoints lie on hex edges
  (HSM ± mouth tolerance); `joint`/`source`/`merge` tiles yield 2 arms when
  `exit_hsm_2` is set; SubtileGrid blocking output unchanged (golden compare
  of `unbuildable_report` before/after on 5 river tiles).

### 0.2 `hex_polygon()` rotation fix (pending bug chip)

Replace the rotated vertex set in `subtile_grid.gd:42-50` with the flat-top
set `(135,0)(405,0)(540,240)(405,480)(135,480)(0,240)`. Run the suite; eyeball
road grids near tile corners (v1 grid placement may shift slightly — expected
and acceptable pre-cutover). Required *before* heights replace blocking so
the subtile domain is correct geometry.

### 0.3 Benchmark harness (skeleton now, numbers after Phase 1 bake)

`tools/bench_route.tscn` + `tools/bench_route.gd` (headless, exit code 0):

- Loads the baked navgrid(s) (Phase 1 emits 12u always, 8u behind a bake
  flag) and the realizer's cost function.
- Workload: 3 distance bands × 30 seeded start/goal pairs on land:
  *local* (~500 u, adjacent-tile jobs), *regional* (~2,000 u ≈ 5 tiles),
  *trunk* (~6,500 u ≈ 15 tiles). Pairs drawn by `RoadHash` seed so runs are
  reproducible; both corridor-bounded (capsule radius 480 u) and unbounded.
- Measures per job: expansions, µs/expansion (`Time.get_ticks_usec`), total
  ms, peak open-set size. Prints P50/P95 per band + a machine-readable
  summary line for CI.

**Decision thresholds** (rationale: a trunk job must fit inside the Phase-3
4 ms/frame budget without monopolizing the 3 s reveal window — 15 frame
slices ≈ 60 ms of compute is the comfort line; 150 ms is the absolute cap
before the queue visibly lags a mass build):

| Gate | Threshold | Consequence |
|---|---|---|
| G1 | 12u corridor-bounded trunk P50 ≤ 60 ms and P95 ≤ 150 ms | 12u adopted; proceed |
| G2 | 8u corridor-bounded trunk P95 ≤ 150 ms | adopt 8u instead (finer placement, designer preference for density) |
| G3 | G1 fails | corridor-bounding mandatory + hierarchical routing (24u coarse pass, fine refinement per segment) enters Phase 2 scope |
| G4 | G3 still fails (P95 > 300 ms) | per-region fine lattice (cities only) + GDExtension spike ticket; **C# stays struck** (no Godot 4 web export) |

### Phase 0 exit checklist

- [ ] RiverGeometry landed, all consumers migrated, suite green
- [ ] hex_polygon fixed, suite green, corner road grids eyeballed
- [ ] bench harness runs headless and prints the summary line
- [ ] (after Phase 1) gates G1–G4 evaluated, lattice decision recorded in the design doc decision log

---

## 3. Phase 1 — data layer

### 1.1 Bake: heights + navgrid + water classes

`hill_field.gd` (GEN_VERSION → 10):

- `_collect_levels(ctx, tiles)` beside `_collect_blocked`: for every playable
  tile, per-subtile **level** = `_band_at(...) − 1` (−1..10) at the existing
  subtile-centre transform, and **water class** ∈ {LAND 0, SEA 1, LAKE 2,
  SOURCE_LAKE 3, RIVER 4} from `ctx.coast_land < 0.5` / `ctx.lake_blur > 0.5`
  / source-lake ellipses / river corridor distance < 13 u (RIVER_BLOCK_RADIUS
  10.5 + road half-width). Encoding: per tile two 648-char hex strings
  (`lvl` digit = level+1 → 0..B; `wat` digit = class). ≈ +0.8 MB raw, ~half
  after the JSON dedupes via RLE of runs (`"lvl_rle"` when shorter).
- Navgrid export: the *existing* `ctx.grid` (12u lattice) quantized to the
  same level+water byte (`level+1` low nibble, water high nibble), row-major,
  RLE-encoded into `"navgrid"` {origin, step, gw, gh, data}. Behind
  `BAKE_NAVGRID_8U := false`, also emit an 8u resample (bilinear `_field_at`)
  for the benchmark only.
- Rationale: per-subtile strings serve gameplay queries by tile id; the
  navgrid serves world-space routing without per-tile seams. Both derive from
  one field so they can never disagree.

### 1.2 Runtime: `TileHeights` + `NavGrid`

- `scripts/tile_heights.gd` (lazy static, mirrors `TileOccupancy`):
  `level_at(tile_id, col, row) -> int`, `water_at(...) -> int`.
  `TileOccupancy.is_blocked` becomes `TileHeights.level_at(...) >= 3` —
  identical behavior to the baked masks (assert equality in a migration test
  across all 100 hill tiles), then the `blocked` key is dropped from the bake.
- `scripts/nav_grid.gd` (lazy static): decoded `PackedByteArray` + origin/
  step/dims; `level(ix, iy)`, `water(ix, iy)`, `cell_of(world) -> Vector2i`.

### 1.3 `road_regions.json` loader + validation

`scripts/road_regions.gd` (lazy static): `region_of(tile_id) -> String`,
`identity(region_id)`, `style(region_id) -> Dictionary` (from the Phase-4
style table). On load, re-run the validation the generator ran offline and
`push_warning` on: unknown tile ids, overlaps, lake-tile membership, sea/deep
sea membership, invalid identities, and hard-rule mountain mismatches.
Unassigned tiles → `sparse_rural` defaults. (Appendix B lists the current
designer cleanup flag — one sea tile.)

### Phase 1 exit checklist

- [ ] bake runs (~+10–15 s), JSON ≤ 8 MB, staleness machinery forces re-bake
- [ ] `TileHeights` equality test vs old blocked masks passes; `blocked` key dropped
- [ ] benchmark gates G1–G4 evaluated → lattice recorded
- [ ] regions loader warns on the known Vandel sea-tile flag and nothing else

---

## 4. Phase 2 — network, crossings, realizer (flagged off)

### 2.1 `RoadNetwork` (`scripts/road_network.gd`, autoload; saved)

```
node: {id: String, kind: GATEWAY|CROSSING|ORBITAL_PORT|BUNCH|JUNCTION,
       pos: Vector2, tile: Vector2i, tangent: Vector2 (GATEWAY: agreed
       arrival direction; zero until first writer sets it)}
edge: {id: String, a: String, b: String, tier: TRUNK|LOCAL,
       state: PLANNED|BUILDING|BUILT, tiles: Array[Vector2i],
       geometry: PackedVector2Array, bridges: Array[{point, tangent}],
       planned_turn: int}
```

- GATEWAY ids use the undirected edge-key convention (lift `_edge_key`,
  road_planner.gd:3261) — flanking tiles share one node; the v1 per-instance
  anchor cache disappears because the graph is the cache.
- Per-tile edge buckets (`Dictionary[Vector2i -> Array[edge_id]]`) for O(1)
  junction-merge candidate lookup and per-tile invalidation.
- Save: new `"roads"` snapshot section via `SaveLoad.export_snapshot()`
  (geometry persisted as-built — decision log #3); round-trip covered by the
  existing `_test_save_load_roundtrip` pattern.

### 2.2 Predetermined crossings (`scripts/road_crossings.gd`, static lazy)

Per river tile, per arm (via RiverGeometry): seeded pick among the **¼ / ½ /
¾ arc-length points** of the arm's in-tile polyline
(`RoadHash.fnv1a(tile_id + ":" + arm_index) % 3`). Output {point,
river_tangent, bridge_tangent ⊥, gate_a, gate_b at ±(BRIDGE_LENGTH/2 + 6)}.
Branch tiles (arms = 2) get one crossing per arm. Static inputs → fixed for
the whole game, nothing serialized. Quartile points are interior to the tile
by construction, so seam duplicates can't occur (cheap assert in tests).

### 2.3 Realizer (`scripts/road_realizer.gd`)

A* over the navgrid, state = (cell, direction-octant), packed into int64
(`cell_index * 8 + dir`); binary heap over a PackedInt64Array (cost in the
high bits — or parallel PackedFloat32Array, benchmark both in the harness);
resumable contract `route_step(budget_usec) -> RUNNING|DONE|FAILED` checking
the clock every 64 expansions; `MAX_EXPANSIONS` abort = 4× the bench P95.

**Cost function** (order of application; all constants in one
`RoadCost` table):

| Term | Value | Rationale |
|---|---|---|
| base step | 12 / 12√2 (straight/diagonal) | lattice metric |
| altitude change | ×(1 + 0.5·\|Δlevel\|) | decision #2: 50% per level crossed |
| valley preference | ×(1 + 0.03·max(level,0)) | equal-length options prefer lower ground ("lowest path within a tile") |
| river hug | ×0.85 @ 30–60 u from water; ×1.15 @ 13–30 u | principle (b); centred on v1's proven 42 u offset |
| turn penalty | +0.2·STEP @45°, +0.9 @90°, +3.0 @≥135° | principle (f) curves; hairpin waiver below |
| gradient alignment (steep cells: ≥1 level per 2 cells) | ×(1 + 1.5·\|dot(step_dir, ∇level)\|) | decision #2 serpentines: traverse across slopes, not up them |
| hairpin waiver | ≥135° penalty waived only on hill/mountain tiles when the local climb gains >1 elevation level within 20 u | lets switchbacks exist exactly where they belong, nowhere on flatland |
| reuse discount | ×0.6 within 24 u of existing network | organic T-junction merging; prevents parallel braids |
| congestion | ×(1 + 0.8·occupied_fraction(tile)) | decision #6: crowded tiles force roundabout routes |
| region wiggle | ×(1 ± jitter·noise(cell, seed)) | per-identity jitter amp (Phase 4 table), deterministic |
| water | impassable (SEA/DEEP_SEA/LAKE/SOURCE_LAKE; RIVER except within 18 u of a crossing gate) | roads never enter water; they follow land-side coastlines or choose cheaper inland routes |
| forest discs | impassable (dynamic overlay, §1) | forests avoided once built |

Water/coast rule: a road may run along the coast only on LAND cells adjacent to
water; it never steps onto sea, deep sea, lakes, or source lakes. Coastal
following is a cost-field preference, not a mandate: if the land-side coast is
the efficient path, the road hugs it; if the coast would be a long detour, A*
should find the cheaper inland route. The only water crossing exception is a
river at a predetermined gate/bridge.

Post-pass: Catmull-Rom smoothing (min turn radius 28 u), level-transition
preserving simplification (never adds transitions the raw path didn't pay
for), serpentine post-check (switchback reversals are legal on hill/mountain
tiles only when the segment ascends >1 elevation level within a 20 u window;
on failure re-route with gradient k doubled), bridge emission at gate
crossings using the salvaged v1 invariant
(`_path_crossings_are_bound`), junction merge (split within 10 u; 4-way only
on transversal crossing, both sides continuing, angle ≥50°).

**Gateway protocol** (design §4.5): multi-tile jobs cross edges freely; when
a job terminates at an unbuilt frontier the realizer writes {point, tangent}
to the GATEWAY node; continuations consume both as boundary constraints.
Pre-planned gateways (re-seed) use height-argmin along the edge, ≥40 u from
corners, river-cleared via the salvaged anchor-offset search, ±5% jitter.

### 2.4 Debug surface

`toggle roadsv2` (flag), `roads debug` (draw navgrid water classes + last
route's expansion heat + crossing gates), `roads route <tile_a> <tile_b>`
(manual route for eyeballing). Rendering in this phase: tiered placeholder
(TRUNK 6 u orange `#d97b29`-ish, LOCAL 4 u yellow `#e8c84a`-ish, 1 u darker
casing) — the atlas language ships now per risk #4, polish in Phase 4.

### Phase 2 tests

Golden-route determinism (5 fixed jobs → exact geometry hash, twice + across
save/load); switchback gate assert on a hill/mountain >1-level-in-20u climb
fixture; flatland no-hairpin assert; crossroads angle rule (crossing at 30°
must NOT create a 4-way); river crossing only at gates; forest disc avoidance; quartile
crossing determinism per arm; gateway tangent continuity (route A then B
through one gateway → angle between end tangents < 15°).

---

## 5. Phase 3 — RoadWorks pipeline (turn-phased, chunked)

- `scripts/road_works.gd`: WorkOrder {edges to plan, reveal state}. On road
  construction completion (PROCESS): flag flips (unchanged), order enqueued.
  Planning in `_process` under `PLAN_BUDGET_MS := 4.0`, outside TurnProfiler
  brackets. Reveal: `REVEAL_DURATION := 3.0 s` per order, **growing from the
  existing network at the connection edge outward; trunk segments before
  branches** (decision log). Implementation: order segments by network
  distance from the attachment node; reveal fraction advances per frame;
  active layer draws only in-flight orders, static layer redraws once on
  settlement.
- Invalidation matrix: road built on tile T → plan jobs for T only; region
  membership change → that region's style jobs/orbital only; building placed → nothing
  (the v1 map-wide handler is deleted); forest planted/removed → re-route
  PLANNED (not BUILT) edges intersecting its disc — built roads stay (history
  is history).
- Occupancy: road corridors (half-width + 3 u, v1's `ROAD_BUILD_BUFFER`) and
  forest discs register as dynamic `TileOccupancy` producers behind
  `OCCUPANCY_ROADS_ENABLED` (default on at cutover). Congestion factor =
  occupied subtile fraction per tile, cached, event-updated.
- Save/load mid-reveal: BUILT geometry persists; BUILDING orders resume
  planning deterministically; reveal restarts (cosmetic only).
- **Mass-build perf test** (automated, headless): script 100 road completions
  in one PROCESS; assert zero frames over 8 ms in planning, full settlement
  ≤ 6 s simulated, suite-runnable via fixed frame stepping.

### Phase 3 exit checklist

- [ ] 100-tile mass-build test green; no map-wide invalidations remain
- [ ] save/load round-trip incl. "roads" section + mid-reveal save
- [ ] forests + roads visible in `TileOccupancy`; congestion factor live

---

## 6. Phase 4 — region styles + orbitals

Style table (first-pass numbers; tune against the atlas reference; lives in
`road_regions.gd::STYLE`):

| Identity | wiggle jitter | job pattern | trunk turn-penalty x | orbital |
|---|---|---|---|---|
| dense_city | +/-2% | full beltway + urban minihubs + gateway spokes + adjacent member links within 1.5 tiles | 1.0 | yes, ports = external land neighbours (8-12) |
| sparse_city | +/-4% | 1-2 urban minihubs, gateway spokes, nearby member links, optional partial bypass | 1.0 | no full orbital |
| dense_rural | +/-5% | cohesive hub-and-spokes + 1 redundant link per 4 tiles | 1.2 | no |
| sparse_rural | +/-7% | through-route first; optionally connect nearby farms/isolated rural buildings along it | 1.3 | no |
| mountain_range | +/-8% | max 3 road segments; cheapest pass route(s) to the far side under elevation costs | 1.5 | no |

(Trunk turn-penalty multiplier answers open question: A-roads straighter in
cities, twistier in the wilds.) Any region with **more than 1 mountain tile**
uses the `mountain_range` special style. These regions are deliberately sparse:
no local web, no orbital, at most three realized road segments whose job is to
find the cheapest crossing to the other side under the elevation-change rules.

Job-generation contract:

1. `dense_city`: place a routed beltway first, then minihub nodes around urban
   subcenters and ports; add gateway spokes and short adjacent-member links so
   the result reads as an equal urban network rather than one star.
2. `sparse_city`: pick 1-2 urban minihubs, connect them to gateways and nearby
   member tiles, and only add a partial bypass if it improves through movement.
   A sparse city never gets a full orbital.
3. `dense_rural`: choose a hub (urban tile if present, otherwise the central or
   lowest-cost rural tile), route spokes to members, then add a small number of
   cross-links for resilience. Once seeded buildings exist, this identity should
   consider building character: three farm tiles can stay sparse, while farms
   plus a few factories can become dense rural.
4. `sparse_rural`: route through the region first; connect farms or isolated
   rural buildings along that route when cheap and nearby.
5. `mountain_range`: if a region has more than one mountain tile, cap it at
   three realized road segments and optimize for the cheapest far-side pass.
   Switchbacks are legal only under the hill/mountain + >1 level within 20 u
   gate from the realizer cost rules.

Dense-city orbitals: ports placed via the salvaged `region_road_planner.gd`
boundary/inset scaffolding; ring routed port-to-port through the cost field. The ≤50%
overflow rule is enforced as a post-check: if > 50% of realized ring length
lies outside member tiles, re-route the offending spans with an
outside-region penalty ×1.5 (repeat once; then accept and warn — heightmap
wins over the quota per the ruling "if heightmap allows").

Exit: every dense-city region grows an orbital on first member road; sparse
city regions get minihub/gateway networks and may get partial bypasses, never
full orbitals. Overflow
check covered by a test on a hand-picked coastal city (Stoneshore) and an inland
one (Patran City).

---

## 7. Phase 5 — cutover

1. Re-seed: one-time pass converts CSV `road_hsms` topology into v2 network
   edges (gateways elected by the Phase-2 rule), realizes everything, writes
   a review screenshot per region (`tools/roadsv2_review.gd` → user:// PNGs).
   **Designer approval pass on the screenshots is the gate.**
2. Flip `V2_ENABLED` default; delete v1: `road_planner.gd` (all of it),
   `road_templates.json`, v1 paths in `road_visuals.gd`,
   `region_road_planner.gd` (after port-placement code relocates into the
   orbital module). Retire CSV columns `road_type`, `road_hsms`,
   `road_density` (keep `road_seed`).
3. Suite + bake + mass-build test green; `toggle heightmap` and `toggle
   roadsv2` cheats still work; PR.

---

## 8. Benchmarks & tests master table

| # | Name | Phase | Pass criterion |
|---|---|---|---|
| B1 | µs/expansion (12u, 3 bands) | 0/1 | gates G1–G4 table |
| B2 | 8u adoption | 0/1 | G2 |
| B3 | heap vs parallel-array open set | 0 | pick faster, record |
| B4 | mass build 100 tiles | 3 | no frame > 8 ms; settle ≤ 6 s |
| B5 | bake time + JSON size | 1 | ≤ +20 s; ≤ 8 MB |
| T1 | golden routes ×5 deterministic | 2 | exact geometry hash |
| T2 | switchbacks only on hill/mountain climbs with >1 level gained within 20 u | 2 | fixture |
| T3 | flatland no-hairpin | 2 | fixture |
| T4 | crossroads only ≥50° transversal | 2 | fixture |
| T5 | crossings: gates only, quartile determinism, per-arm count | 2 | fixtures |
| T6 | gateway tangent continuity < 15° | 2 | fixture |
| T7 | forest disc avoidance + footprint determinism | 1/2 | fixtures |
| T8 | TileHeights ≡ old blocked masks | 1 | all 100 hill tiles |
| T9 | save round-trip "roads" + mid-reveal | 3 | section-equal |
| T10 | orbital overflow ≤ 50% (or warned) | 4 | Stoneshore + Patran City |
| T11 | RiverGeometry: 4 kinds, golden SubtileGrid compare | 0 | fixtures |

---

## Appendix A — constants (single table, all tunable)

`STEP=12` (or 8 per G2) · altitude ×1.5/level · valley 0.03 · hug 0.85 @30–60,
1.15 @13–30 · turns 0.2/0.9/3.0·STEP · gradient k=1.5 · steep = ≥1 lvl/2 cells
· reuse 0.6 @≤24 u · congestion 0.8 · jitter per identity (§6) · ε=1.1 A*
weight · JOIN_RADIUS=10 · crossroad angle ≥50° · gate radius 18 ·
FOREST_ROAD_BUFFER=8 · road corridor buffer = half-width+3 ·
PLAN_BUDGET_MS=4 · REVEAL=3 s · corridor capsule 480 u · smoothing min radius
28 u · gateway corner margin 40 u · gateway jitter ±5%.

## Appendix B — regions as authored (validation results)

`data/road_regions.json`: 50 regions, 286/600 tiles assigned (rest default
sparse_rural). Initial identities were inferred from tile composition (urban
≥3 → dense_city; ≥1 → sparse_city; mountains ≥34% or name → mountain_range;
hills ≥50% → sparse_rural; ≥7 tiles → dense_rural), then edited by designer
rules. Current hard rule: regions with >1 mountain tile are `mountain_range`
(e.g. Shoulderland). **Edit freely, the loader treats the file as truth**.

Designer review flags found by validation:

1. **Vandel Island** contains one sea tile (`tile_24_18`) — harmless (sea tiles
   never route) but flagged.
2. No overlapping member tiles.
3. No duplicate member tiles.
4. No region claims any of the 17 lake tiles.
5. Every region with more than one mountain tile uses `mountain_range`.
