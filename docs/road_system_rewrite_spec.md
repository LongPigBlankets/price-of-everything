# Road System Rewrite — Spec (Hand-Drawn Baseline + Template Expansion)

> Supersedes the previous algorithmic spec. This version replaces the per-region procedural planner with a hand-authored baseline traced from a map screenshot, plus a small template library for player-driven expansion.

## Architectural premise

The world map is handcrafted and stable. The starting road network (~100 tiles, 30 cities) is **drawn by hand over a screenshot of the map**, then traced into a structured graph. This baseline is loaded at game start, immutable.

When players add road tiles during play, an **expansion system** stitches new tiles into the baseline by picking from a small library of hand-drawn single-tile templates, transforming each to fit the tile, and snapping its exits to the existing network's HSM anchors.

Target final scope: ~600 LOC of game code + ~200 LOC of offline Python tracer + ~30-50 hand-drawn assets.

The old `RoadPlanner` (~3000 LOC) is deleted in full.

---

## Glossary

- **Baseline network** — the immutable, hand-authored road graph loaded at game start.
- **Tracer** — offline Python tool that converts a PNG of drawn roads into a JSON graph.
- **Template** — a single-tile hand-drawn road pattern keyed by HSM exit signature, density, and river config.
- **HSM** — Hex Side Midpoint, one of 6 sides per tile. Existing concept, reused.
- **Anchor** — a deterministic world point on a hex edge where roads from adjacent tiles meet.
- **Expansion plan** — the road geometry generated for a single player-placed road tile, attached to the baseline.

---

## Phase 0 — Tracer prototype & authoring conventions

**Goal:** Lock in the tracer pipeline and the authoring conventions before the artist draws the real baseline.

### Scope

Create `tools/road_tracer/` (offline Python, not shipped with the game):
- `trace.py` — entry point. Args: `--input <png>`, `--map-config <json>`, `--output <json>`.
- `requirements.txt` — `pillow`, `scikit-image`, `numpy`.

Pipeline inside `trace.py`:
1. Load PNG (transparent background, black strokes, red 1-2 px dots at HSM exits).
2. Separate the red dot layer from the black road layer via per-channel thresholds.
3. Threshold the black layer to a binary mask. Skeletonize with `skimage.morphology.skeletonize` (Zhang-Suen).
4. Walk the skeleton: classify each pixel by neighbour count. 1-neighbour = endpoint, 2 = interior, ≥3 = junction.
5. Trace polylines between consecutive endpoints/junctions. Each polyline is a list of pixel coords.
6. Simplify each polyline with Douglas-Peucker (`epsilon=1.5px`). Target ~10-30 points per polyline.
7. **Map-config** JSON gives the pixel rect of the playable map and the hex grid dimensions. Convert all pixel coords to world coords using the same `HexMap` layout math (port the formulas — do not re-derive).
8. For each red dot in the PNG:
   - Map to world coords.
   - Identify the nearest tile and the nearest HSM of that tile.
   - Find the polyline endpoint within `match_radius_px` (default 8). Tag that endpoint with `{tile_id, hsm, dot_id}`.
   - Polylines whose endpoint sits exactly on a red dot have semantic identity; others are "interior" polylines (connectors, beltway segments).
9. For every polyline, compute the set of tile_ids it passes through (point-in-hex test, sampled every N points).
10. Output JSON schema:

```
{
  "schema_version": 1,
  "source_image": "<filename>",
  "world_bounds": { "min": [x, y], "max": [x, y] },
  "polylines": [
    {
      "id": "p_0",
      "points": [[x, y], ...],
      "tile_ids": ["tile_5_8", "tile_5_9", ...],
      "endpoints": [
        { "point": [x, y], "exit": { "tile_id": "tile_5_8", "hsm": "HSM3" } | null },
        { "point": [x, y], "exit": null }
      ],
      "junction_node_ids": [3, 7]
    }
  ],
  "nodes": [
    { "id": 0, "point": [x, y], "kind": "junction" | "exit",
      "exit_data": { "tile_id": "tile_5_8", "hsm": "HSM3" } | null,
      "polyline_ids": ["p_0", "p_3"] }
  ]
}
```

Nodes deduplicate coincident polyline endpoints into a single graph node. The output is a proper directed-or-undirected graph, not just a bag of polylines.

Create `data/baseline_test_input/`:
- `tracer_test_strip.png` — a synthetic test image: 3 hexes in a line with a simple road, two red dots at the entry/exit HSMs, one Y-junction in the middle. Authored by the spec author, committed.
- `tracer_test_strip.expected.json` — hand-written expected output. Used as a regression fixture.

### Authoring conventions document

Add `docs/road_authoring.md` with:
- Required image format (PNG, transparent BG).
- Required stroke colour (`#000000`), recommended brush width (8-12 px at 1:1 map scale).
- Red dot specification: `#FF0000`, 2-3 px diameter, centered exactly on the HSM midpoint.
- HSM dot placement: at each tile boundary the network crosses, place exactly one red dot on the HSM midpoint of the *entering* side. The same dot serves both adjacent tiles.
- A red dot is *not* required for purely internal junctions or for endpoints that terminate inside a tile (dead-end spurs).
- Reference image: a 3-hex strip with annotations.

### Out of scope
- Tracing the real map (Phase 1).
- Runtime integration (Phase 2).
- Anti-aliasing / colour bleed robustness — assume clean inputs.

### Acceptance criteria
- [ ] `python tools/road_tracer/trace.py --input data/baseline_test_input/tracer_test_strip.png --map-config data/baseline_test_input/tracer_test_strip.map.json --output /tmp/out.json` produces output matching `tracer_test_strip.expected.json` byte-for-byte (after JSON normalization).
- [ ] The tracer correctly classifies all red dots in the test image as `exit` nodes with the right `(tile_id, hsm)` pair.
- [ ] The tracer correctly identifies the central Y-junction as a `junction` node connecting 3 polylines.
- [ ] `docs/road_authoring.md` exists with at least the conventions listed above and one annotated reference image.
- [ ] Running the tracer on a malformed input (no red dots, or stroke colour wrong) produces a clear error message, not a crash.

---

## Phase 1 — Author and load the real baseline

**Goal:** Replace the running road system with the hand-drawn baseline. Old planner is bypassed entirely.

### Scope

**Authoring (art task, not code):**
1. Export the current in-game map at high resolution. Recommended: 8000 × something matching the playable rect aspect ratio. Hex grid alignment must be exact.
2. Lock the export as a background layer in the drawing app.
3. Draw the road network on top per the conventions in `docs/road_authoring.md`. Include:
   - All 30 cities (beltways, internal streets, intra-city connectors).
   - All ~100 starting road-bearing rural tiles.
   - All HSM exit red dots.
   - All river crossings as a visible road stroke (bridges are inferred at intersections with the river layer — see Phase 1.5).
4. Export the road layer as `data/baseline_roads.png` (strokes + dots, transparent background).
5. Run the tracer:
   ```
   python tools/road_tracer/trace.py \
     --input data/baseline_roads.png \
     --map-config data/baseline_map_config.json \
     --output data/baseline_road_network.json
   ```
6. Commit `baseline_roads.png` (artifact-of-record) and `baseline_road_network.json` (build output, also committed for reproducibility).

**Code:**

Create `scripts/road_network.gd`:

```
class_name RoadNetwork extends RefCounted

class Node:
    var id: int
    var point: Vector2
    var kind: String          # "junction" | "exit"
    var exit_data: Dictionary # {tile_id, hsm} or empty
    var polyline_ids: Array[String]

class Polyline:
    var id: String
    var points: PackedVector2Array
    var tile_ids: Array[String]
    var endpoint_node_ids: Array[int]   # length 2

var nodes: Array[Node]
var polylines: Dictionary           # id -> Polyline
var polylines_by_tile: Dictionary   # tile_id -> Array[String]
var exit_nodes_by_anchor: Dictionary # "<tile_id>:<hsm>" -> node_id

static func load_from_json(path: String) -> RoadNetwork
```

Create `scripts/road_system.gd` (autoload singleton `RoadSystem`):

```
var baseline: RoadNetwork

func _ready():
    baseline = RoadNetwork.load_from_json("res://data/baseline_road_network.json")

func polylines_for_tile(tile_id: String) -> Array[Polyline]
func exit_node_for(tile_id: String, hsm: String) -> RoadNetwork.Node
```

Replace `scripts/road_visuals.gd` (rewrite, not edit):

```
extends Node2D

const ROAD_COLOR := Color.BLACK
const ROAD_WIDTH := 5.0

func _ready():
    queue_redraw()
    var world_map: Node = get_parent()
    if world_map and world_map.has_signal("building_placed"):
        world_map.connect("building_placed", _on_building_placed)

func _draw():
    for polyline in RoadSystem.baseline.polylines.values():
        draw_polyline(polyline.points, ROAD_COLOR, ROAD_WIDTH, true)

func _on_building_placed(...):
    queue_redraw()  # expansions added in Phase 3
```

Delete from `road_planner.gd` everything except river math (`_river_curve_world_path`, `_river_point_local`, `_river_path_tangents`, `_hsm_outward_direction`, `_path_river_crossings`, `_segment_intersection`). Move those to `scripts/river_geometry.gd` (static class).

### Phase 1.5 — Bridge inference (sub-step inside Phase 1)

The tracer outputs road geometry but not "this is a bridge." Bridges are inferred at load time:

In `RoadNetwork.load_from_json`, after parsing polylines:
1. Load the river layer geometry (existing `river_properties.csv` + per-tile river data).
2. For every polyline, compute intersections with every river curve in the tiles it passes through.
3. Each intersection becomes a `Bridge { point, tangent: perpendicular_to_river }` stored on the polyline.
4. The renderer in `road_visuals.gd` draws bridges as small filled rectangles at those points (port `_draw_bridge` from the old visuals).

This means the artist just draws a road over a river; the system figures out bridges automatically.

### Out of scope
- Player-added expansions (Phase 3).
- Style variants per region (Phase 4).
- Bridge styling beyond the simple rectangle.

### Acceptance criteria
- [ ] `data/baseline_roads.png` and `data/baseline_road_network.json` exist and are version-controlled.
- [ ] Tracer reproduces `baseline_road_network.json` byte-for-byte (modulo JSON whitespace) when re-run on the same PNG with the same config.
- [ ] At game start the baseline network is loaded once; `RoadSystem.baseline` is non-null.
- [ ] All ~100 starting road tiles render with the hand-drawn geometry; no old-planner code is invoked.
- [ ] All river crossings in the baseline render with a bridge marker; no road segment crosses a river without a bridge.
- [ ] `road_planner.gd` has been reduced to ≤200 LOC (or deleted) and only `river_geometry.gd` remains for river math.
- [ ] Tests/road_compare.tscn (from old Phase 0, if it exists, else build it here) shows side-by-side baseline rendering on the 4 fixture maps.

---

## Phase 2 — Expansion template library: tracer + authoring

**Goal:** Build the tooling and asset library that lets a single player-placed road tile produce believable geometry by selecting a hand-drawn template.

### Scope

**Tracer extension (`tools/road_tracer/trace_template.py`):**

A separate entry point that runs on single-tile PNGs (drawn inside a single hex bounding box, on a transparent background, no map screenshot beneath):
1. Same skeletonize + walk + simplify pipeline as `trace.py`.
2. Coordinate system: template-local. The hex inscribed in the image bounds is canonical-orientation (flat-top, HSM1 at top per existing `HSM_POINTS`).
3. Red dots are HSM exits; each gets tagged with which HSM (1-6) by angle from image center.
4. Output JSON:

```
{
  "schema_version": 1,
  "template_id": "<filename-stem>",
  "signature": {
    "hsm_exits": ["HSM1", "HSM3", "HSM4"],
    "density": "sparse" | "medium" | "dense",
    "river_config": "none" | "bisect:HSM1-HSM4" | ...
  },
  "polylines": [ { "points": [[x,y],...], "endpoint_hsms": ["HSM1", null] } ],
  "junction_points": [[x, y], ...],
  "bounding_box": { "min": [x,y], "max": [x,y] }
}
```

5. Signature fields not derivable from geometry (density, river_config) come from a sidecar `<template_id>.meta.json` authored alongside the PNG.

**Authoring task (art):**

Author the initial template set in `data/templates/source/`:

Minimum required coverage:
- **Sparse** (`density: sparse`):
  - 2-exit through (adjacent HSMs): 3 stylistic variants
  - 2-exit through (opposite HSMs): 2 variants
  - 3-exit Y-junction: 3 variants
  - 4-exit cross: 2 variants
- **Medium** (`density: medium`):
  - 2-exit, 3-exit, 4-exit: 2 variants each
- **Dense** (`density: dense`):
  - 3-exit, 4-exit, 5-exit, 6-exit dense tile interior: 2 variants each
- **River variants** (`river_config != none`):
  - Sparse 2-exit with river bisecting between exits (bridge needed): 2 variants
  - Sparse 2-exit with river bisecting *not* between exits (both exits on same bank, no bridge): 1 variant
  - Sparse 3-exit with one exit across a river: 1 variant

Total target: **~30 templates**. Coverage gaps fall back to algorithmic stub (Phase 3).

Run the template tracer on the whole directory:
```
python tools/road_tracer/trace_template.py --input-dir data/templates/source --output data/templates/library.json
```

Output is a single bundled `library.json` indexable by signature.

**Code:**

Create `scripts/template_library.gd` (autoload `TemplateLibrary`):

```
var templates_by_signature: Dictionary  # signature_key -> Array[Template]

func _ready():
    _load_from_json("res://data/templates/library.json")

func find(signature: Dictionary) -> Template:
    var key = _signature_key(signature)
    var candidates = templates_by_signature.get(key, [])
    if candidates.is_empty():
        return null
    return candidates[deterministic_pick_index(candidates.size())]

func _signature_key(sig: Dictionary) -> String:
    # Canonicalize HSM exit set via rotational symmetry. Two signatures
    # that are hex-rotations of each other map to the same key, plus the
    # rotation needed to align candidate → request.
    ...
```

`Template` is a small class holding the polylines, endpoint HSMs (in canonical orientation), and the rotation/reflection to apply when matching.

Canonicalization rules (this is the only non-trivial logic in `TemplateLibrary`):
- The 6 rotational and 6 reflective hex symmetries form a group of 12.
- For each candidate template and each requested signature, find the symmetry that maps candidate HSMs → requested HSMs. If found, the template matches with that transform.
- This cuts the required template count by up to 12×. A 3-exit Y with HSMs {1,3,5} covers all rotations of {2,4,6}, {3,5,1}, etc.

### Out of scope
- Using templates at runtime (Phase 3).
- River-aware transforms (Phase 3).
- Authoring beyond ~30 templates.

### Acceptance criteria
- [ ] `tools/road_tracer/trace_template.py` produces `library.json` covering all source PNGs.
- [ ] `library.json` is committed.
- [ ] `TemplateLibrary.find()` returns a `Template` for every signature in the minimum coverage list above, including via rotational/reflective canonicalization.
- [ ] `TemplateLibrary.find()` returns `null` for signatures outside coverage, never crashes.
- [ ] Determinism: `deterministic_pick_index(N)` is a stable hash of `(tile_id, signature_key)`, so the same tile always picks the same template variant across sessions.
- [ ] A unit test (`tests/test_template_canonicalization.gd`) verifies that a request for `{HSM2, HSM4, HSM6}` matches a template authored for `{HSM1, HSM3, HSM5}` and returns the correct 60° rotation.
- [ ] All 30 source templates pass the tracer's red-dot validation (every polyline endpoint near a hex edge has a red dot; HSMs are correctly identified).

---

## Phase 3 — Expansion runtime

**Goal:** Player places a road tile → the tile gets believable geometry that connects seamlessly into the baseline.

### Scope

`RoadSystem` gains expansion state:

```
var baseline: RoadNetwork           # immutable
var expansions: Dictionary          # tile_id -> ExpansionPlan
var expansion_anchor_cache: Dictionary  # "<tile_id>:<hsm>" -> Vector2
```

`ExpansionPlan` is a small class holding the polylines + bridges for one expanded tile, in world coords.

**Expansion flow** (triggered from `world_map._on_infrastructure_attempted` after the tile is marked road-bearing):

1. **Compute the tile's HSM exit set.** For each of the 6 HSMs, check whether the adjacent tile has roads (in baseline *or* expansions). If yes, that HSM is an exit.
2. **Compute the anchor per exit HSM.** This is the *world point where this tile's road meets the neighbor's road*. Lookup rules:
   - If the neighbor's baseline polylines have an endpoint node tagged with this HSM, use that node's point.
   - Else if the neighbor is also an expansion and has its own anchor at the matching HSM, use that.
   - Else (this is the very first expansion at this edge) compute a canonical anchor: HSM midpoint, offset if adjacent to a river per the existing `_offset_anchor_to_buildable_edge` logic (ported to `hex_edge_anchor.gd` static utility).
   - Cache the result under both `<this_tile>:<hsm>` and `<neighbor>:<opposite_hsm>` so both sides see the same point.
3. **Compute density tier.** Sparse / medium / dense from `tile_data.road_density` if set, else inferred from `buildings_present.size()`.
4. **Compute river config.** From the existing `river_data_for_tile`, classify as `none` / `bisect:HSM<entry>-HSM<exit>`.
5. **Build the signature.** `{ hsm_exits, density, river_config }`.
6. **Template lookup.** `var t = TemplateLibrary.find(signature)`.
7. **If template found:**
   - Transform: scale template's bounding box to tile size, translate to tile center, apply the rotation/reflection from canonicalization.
   - Snap exits: for each polyline endpoint whose `endpoint_hsm` is non-null, translate the endpoint to the matching anchor, *and propagate the offset smoothly along the polyline* so the curve still looks natural (linear blend over the last 30% of the polyline).
   - Run bridge inference (same pass as Phase 1.5) on the transformed polylines.
   - Store as `ExpansionPlan` in `RoadSystem.expansions[tile_id]`.
8. **If no template found (fallback):**
   - Generate a single straight-or-bent polyline per HSM exit, from anchor to tile center, joined at the center.
   - This is the "algorithmic stub" — intentionally minimal, ~30 LOC.
   - Mark the `ExpansionPlan` with `from_fallback: true` for diagnostics.

`road_visuals.gd._draw` extends to also draw `RoadSystem.expansions`. Bridges from expansion plans render the same as baseline.

**Invalidation:**
- When a road is added at tile T, expansions at T and *all six neighbors* are invalidated and recomputed. (Adding a road may give a neighbor a new HSM exit it didn't have before.)
- Baseline is never invalidated.

### Out of scope
- Removing roads (low priority — assume roads are not removable, or accept a "stub of road" left behind if they are).
- Inter-expansion stylistic blending (templates may visibly differ in style; that's Phase 4).
- Multi-tile expansion clusters as a single design (still per-tile).

### Acceptance criteria
- [ ] Player places a road tile adjacent to a baseline tile: the new tile's geometry shares an exact anchor point with the baseline polyline at the shared HSM (verified by a debug overlay showing anchor positions).
- [ ] Player places a road tile adjacent to another player-placed tile: both expansions share an anchor at the shared HSM.
- [ ] Placing the same sequence of road tiles in two sessions produces byte-identical expansion geometry (determinism check).
- [ ] A road expansion across a river produces a bridge marker via the same inference pass as the baseline.
- [ ] A signature outside library coverage triggers the algorithmic stub; the stub still connects correctly to anchors and doesn't crash.
- [ ] Adding a road to tile T invalidates and recomputes expansions for T and exactly its road-bearing neighbors; unrelated expansions are not touched.
- [ ] On `fixture_mixed_density` after a chain of 5 player placements, no visible gap between any two adjacent road tiles.
- [ ] Phase 3 code (template adaptation + anchor cache + invalidation) is ≤ 400 LOC.

---

## Phase 4 — Polish, diagnostics, performance

**Goal:** Make the system production-quality. Add observability. Validate performance.

### Scope

**Diagnostics overlay (`F8`):**
- Render baseline polylines in one colour, expansion polylines in another.
- Render exit nodes as small circles, junction nodes as squares.
- For each tile, optionally render its computed signature next to the tile id.
- Hovering a tile shows its `ExpansionPlan` details (template_id, was_fallback, signature) in a debug panel.

**Tracer regression suite:**
- `tests/road_tracer/` directory with N test PNGs and expected JSON outputs.
- A simple Python runner that diffs actual vs expected.
- Run in CI if CI exists.

**Performance:**
- Profile a worst-case session: 50 expansion tiles placed sequentially across the map.
- Target: each placement (including all neighbor invalidations) ≤ 5ms wall time.
- Target: full `_draw` of baseline + 50 expansions ≤ 8ms.
- If over budget, the most likely culprit is canonicalization lookup; cache `_signature_key` results.

**Style consistency pass:**
- Expansion templates render slightly thinner (`ROAD_WIDTH * 0.85`) than baseline, so stylistic seams read as intentional rather than as artifacts.
- Alternative if it reads worse: same width, but expansion strokes have a 5% darker base colour. Choose by visual review.

**Authoring docs:**
- `docs/road_authoring.md` updated with:
  - Template authoring conventions (canonical orientation, sidecar meta.json format).
  - Map-redraw workflow when the underlying map changes.
  - Adding new templates (drop PNG + meta, re-run tracer, commit).

**Deletion sweep:**
- Confirm `road_planner.gd` is gone (only `river_geometry.gd` + `hex_edge_anchor.gd` remain from the old system).
- Confirm `road_visuals.gd` is the thin renderer described in Phase 1.
- Confirm `_road_hsms_for_tile`, `_road_anchor_world`, and other now-redundant `HexMap` helpers are deleted from `hex_map.gd`.

### Out of scope
- New gameplay features.
- Auto-blending across template-style boundaries (would require either a single global style or post-processing; both are future work).

### Acceptance criteria
- [ ] F8 overlay shows baseline vs expansion colour-coded, with all nodes and per-tile signatures.
- [ ] Tracer regression suite runs cleanly on at least 5 test PNGs.
- [ ] Worst-case 50-expansion benchmark: ≤ 5ms per placement, ≤ 8ms full redraw, on dev machine.
- [ ] Visual review: stylistic seam between baseline and expansions reads as natural, not jarring.
- [ ] `road_planner.gd` is deleted.
- [ ] `docs/road_authoring.md` covers map authoring, template authoring, and the redraw workflow.
- [ ] Total road-system game-code LOC ≤ 700 (excluding `river_geometry.gd` and `hex_edge_anchor.gd`).

---

## Cross-cutting invariants

These hold after every phase from Phase 1 onward:

1. **Anchor agreement.** For any HSM shared by two road-bearing tiles, both tiles' road geometry meets at the exact same world point (byte-identical `Vector2`). Verified by `RoadSystem._assert_anchors_agree()` in debug builds.
2. **No orphan river crossings.** No polyline crosses a river except at a registered bridge point in the same plan. Verified by `_assert_no_orphan_crossings()`.
3. **Baseline immutability.** `RoadSystem.baseline` is never mutated after load. Verified by a deep-equality check after the first frame.
4. **Expansion determinism.** Given the same baseline + the same sequence of placement events, expansion geometry is byte-identical across runs.
5. **Coverage degradation, not failure.** A signature with no matching template falls back to the algorithmic stub; the system never crashes or produces no-op geometry.

---

## Deliverables summary by phase

| Phase | Game LOC added | Game LOC deleted | Tools (Python) | Assets | User-visible result |
|-------|----------------|-------------------|----------------|--------|----------------------|
| 0 | ~0 | ~0 | ~200 LOC tracer | 1 test PNG | Tracer reproducible on test input |
| 1 | ~250 | ~2800 | extended | 1 baseline PNG + JSON | All 100 starting tiles render hand-drawn |
| 2 | ~150 | 0 | ~80 LOC template tracer | ~30 template PNGs + library.json | Library queryable, canonicalization works |
| 3 | ~250 | ~200 | 0 | 0 | Player expansions snap to baseline cleanly |
| 4 | ~50 | ~200 (final cleanup) | regression suite | docs | Diagnostics + perf + final state |
| **Net** | **~700** | **~3200** | **~280** | **~32 PNGs** | **~600-700 LOC road system, baseline + expansions** |

Each phase ends in a committable, runnable state. Phases 0-1 are blocking for the rest; Phases 2-3 can overlap (template authoring while expansion runtime is being built against placeholder templates).

---

## Authoring task estimate (the non-code work)

- **Baseline PNG:** one careful pass over the screenshot. ~1 weekend (8-12 hours) for 30 cities + 100 tiles, including iteration.
- **Template library:** ~30 single-tile drawings at 5-10 minutes each + 5-minute meta sidecars. ~4-6 hours.
- **Map redraw if the world changes:** scoped per affected region. Typically 30 min - 2 hours for a localized change; full redraw matches initial cost.

If the map is iterated heavily after the baseline is drawn, factor in redraw time per design change. If the map is stable (as stated), this cost is paid once.
