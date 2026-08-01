# Arc districts, silhouettes and water discipline — implementation spec

**Status:** design complete, prototyped, **not implemented in-engine**.
**Reference implementation:** `tools/packing_lab.html` — a live dial tool (open it in a
browser). Every algorithm below exists there as working JavaScript with the function names
cited. Constants were ported *from* this repo, so they transfer back unchanged unless the
spec says otherwise.
**Written against:** branch `map-ink-restyle` @ `8a87ce5b`. Verify the line numbers before
trusting them — this file moves fast.

---

## 0. Read this before starting

The lab was built while the engine was being worked on in parallel, and **several problems
it was built to explore have already been fixed**. Do not re-do these:

| Already fixed | Commit |
|---|---|
| Buildable mask was 20u cells → now `CELL := 5.0`, `GRID_COLS 108 × GRID_ROWS 96` | `0d763b90` |
| `_crop_to_sprite` ran after the search, parking sprites too far out | `d84c9fa5` |
| Blocks that stopped growing when lots were invalidated | `b54b510f` |
| Block side roads (re-added, gated on an earned second row) | `dc465897` |
| Service lanes into a tile's roadless pocket | `8a87ce5b` |
| `ROAD_CLEAR` relaxed 18 → 15 | (in tree) |

Consequently the "buildings float ~65u off their street" problem the lab was built around is
**largely an engine problem of the past**. What remains below is genuinely additive, plus one
confirmed live bug.

**One lab bug worth knowing about, because the engine gets it right:** the lab measured the
river-hug band from the river *centreline*. The engine measures from the bank —
`RIVER_HUG_NEAR := 4.0` ("nearer than this you're in the bank itself") and
`RIVER_HUG_FAR := 24.0` in `road_realizer.gd:56-57`. **Do not change the engine here.**

---

## 1. Confirmed live bug: rotated buildings can never form a terrace

**`scenes/building_visuals.gd:3389` `_overlaps()`** rejects a candidate using an
**axis-aligned box** test:

```gdscript
func _overlaps(center: Vector2, half: Vector2, placed_here: Array) -> bool:
    var lo := center - half - Vector2(DESIGN_GAP, DESIGN_GAP)
    var hi := center + half + Vector2(DESIGN_GAP, DESIGN_GAP)
    ...
```

`half` is the footprint's half-extent in **local** space, but the comparison is done in world
space against other buildings' AABBs. A footprint rotated to face a street has a bounding box
far larger than itself — at 45° a 30×19u unit occupies a 35×35u box. Two neighbours 1u apart
along a street therefore reject each other.

**Consequence:** `DESIGN_GAP := 1.0` and the header's stated intent at `building_visuals.gd:9-12`
("the 1-2u Sanborn terrace look") are **unreachable for any street that is not near
axis-aligned**. This is likely a bigger brake on terracing than density.

**Evidence:** in the lab, welded masses were impossible until the test was replaced. With SAT,
the same inputs produce masses of 5–16 units. See `sep()` and `clear()` in `packing_lab.html`.

**Fix:** separating-axis test on the oriented quads, AABB kept as a cheap prefilter:

```gdscript
# reject only if BOTH the cheap box test and the exact oriented test say they touch
func _clear(a_poly, a_bb, b_poly, b_bb, gap) -> bool:
    if _gap_ok(a_bb, b_bb, gap): return true          # separated by boxes alone
    return _sat_separated(a_poly, b_poly, gap)        # 4 axes, 2 per quad
```

**Refactor note:** `placed_here` entries currently carry `{pos, half}`. They will need the
four rotated vertices too. Footprints already exist as polygons at placement time
(`_rotate(base_verts, tangent.angle())`), so this is plumbing, not new geometry.

**Blast radius:** placement becomes *more* permissive, so tiles will hold more buildings.
Re-run `tools/road_frontage_audit.tscn` and the unit suite; expect placement counts to rise.

---

## 2. Arc districts (new)

### 2.1 The design

One district per tile. Concentric half-turn arcs springing off the tile's main road, both ends
landing back on it, with radial streets crossing the rings. Reads as a New England green /
structured European town rather than a scatter.

**Lab reference:** `arcDistrict()`, `inDistrict()`, `ringGap()`, `hexF()`.

### 2.2 Rules

1. **Core** = midpoint of the longest straight run (≥90u, <14° cumulative turn) of a **trunk**
   crossing the tile. Reuse `straightRuns()` — the engine equivalent is
   `_longest_straight_road()` (`building_visuals.gd`), which already applies the same test at
   `BLOCK_MIN_ROAD := 70.0`.
2. **Extent.** If that road **bisects** the tile (both ends of its in-hex run on the rim,
   `hexF > 0.88`) the district takes **half the tile**; otherwise **a quarter**. Because the
   arc is a half-turn, area `πr²/2` gives the radius directly:
   `r = sqrt(2 · frac · HEX_AREA / π)` → **249u** (half) or **176u** (quarter), clamped by how
   far the fan can grow before leaving the hex **or reaching the river**.
3. **Ring spacing is derived, never chosen** — this is the load-bearing rule:
   ```
   ringGap = 2 · (depth + W_LOCAL/2 + pad) + DESIGN_GAP
   pad     = max(BLOCK_ROAD_PAD, MASK_ROAD_CLEAR + maskCell · 0.75)
   ```
   Two building rows plus both kerb clearances. Guarantees a block always fits between two
   rings. With the engine's current 5u mask, `pad = BLOCK_ROAD_PAD = 7`, so a 44u `BLOCK_LOT`
   at `BLOCK_ASPECT 0.62` gives **ringGap ≈ 76u**.
4. **Ring count** `= clamp(floor(rOuter / ringGap), 1, 3)`, placed at `rOuter · k / rings` —
   even spacing that is never tighter than one `ringGap`.
5. **Ends.** An intact arc end connects to the nearest point on a trunk; an end clipped by the
   hex runs out to the nearest rim port instead ("meet the main road, or an exit").
6. **Radials:** 3 if bisecting, else 2, from the main road out past the outer arc.
7. **The district owns its sector.** Any non-trunk road with a point inside the disc is
   suppressed — *except* river bank roads (§4.4).
8. **Adjacency:** a district blocks its seam-neighbours. Claims go out in a seeded order.

### 2.3 What this collides with in the engine

- `road_regions.gd` / `road_region_jobs.gd` already generate per-identity webs, including a
  `dense_city` **beltway** through 8-12 inset boundary ports plus spokes. An arc district is a
  *different, tighter* structure and would have to either replace the beltway inside its sector
  or be reconciled with it. **Recommend:** treat the arc district as a new region identity
  (e.g. `town_district`) so it slots into the existing job pipeline rather than bypassing it.
- Arcs must be **realizer-routed like everything else** (`road_realizer.gd`), not injected as
  raw geometry. The enclosure subsystem was deleted precisely because it bypassed the cost
  field — see `[[roads-enclosures-redesign]]` and the deletion inventory. **Do not reintroduce
  geometry-only roads.** Generate the arc as a sequence of waypoints and let the realizer
  route between them; accept that terrain will deform the circle.

### 2.4 Design tension to resolve with the owner first

`building_visuals.gd:135` records a standing ruling: *"Service streets were tried and REMOVED
(owner): inventing roads to suit buildings is backwards."* Arc districts derive their ring
spacing from building depth — that is, by construction, roads shaped to suit buildings.

The ruling has since softened (`dc465897` re-added block side roads "earned by a second-row
build"), which suggests the real bar is **earned, not speculative**. An arc district should
probably have to be *earned* the same way — e.g. only form once the tile has N buildings or a
settlement of some size — rather than being drawn on an empty tile. **Raise this before
implementing.**

---

## 3. Building silhouettes and sub-components

### 3.1 Silhouette by land use (new)

| Land use | Shape | Sub-component |
|---|---|---|
| industrial | half cross (notch mid-way along one long side) | — |
| commercial | C (deep central notch) | detached annex |
| residential | L (corner notch) | 2–4 tanks in the notch |
| civic | plain rectangle | detached annex |
| decorative | plain rectangle | — |

**Lab reference:** `localShape()`, `toWorld()`, `SHAPE_FOR`.

**The rule that makes this cheap:** every notch is cut from the **far** edge, so the
street-facing face stays a clean straight line and frontage packing is untouched. And the
**collision footprint stays a plain rectangle** — only the drawn silhouette is notched. This
keeps `_overlaps`/SAT on convex input and means `d84c9fa5`'s "the lot is the sprite's box"
still holds.

Proportions (fraction of width `w` and mass depth `hm`):
- L: notch `0.48w × 0.50hm`. **Arms must stay thick** — a notch much over half the width turns
  the L into a thin hook and its "negative space" becomes open grass rather than a pocket.
- half cross: `0.30w × 0.42hm`
- C: `0.52w × 0.66hm`

### 3.2 What exists in-engine

`scripts/ink_building_gen.gd` already has 18 shape-language recipes × 3 levels with wings and
courtyard masses. **Check whether these silhouettes are already reachable there before adding
a parallel system.** The likely correct move is to express the four shapes as ink recipes, not
as new footprint code.

### 3.3 Sub-component changes

| Constant | Now | Proposed | Why |
|---|---|---|---|
| `SUBCOMP_ANNEX_OVERLAP` | `-2.0` (annex *merges* with parent) | **`+5.0` detached** | A separate outbuilding is the mockup's cream shed. Below ~4u the ink outline (1.0–2.3u, stroked centred) closes the gap and the two masses read as one — 5u is the minimum that reads. Verified by eye in the lab. |
| `SUBCOMP_TANK_R` | `4.0` (~0.7% of tile width) | **`6–10u`, in rows of 2–4** | Tank clusters are the loudest industrial signature in the reference art. One 4u dot reads as nothing at map zoom. |
| tank placement | beside the parent | **inside the L's notch**, hugging the inner corner at `SEP` from both closed faces | Gives the tanks a reason to be where they are. Lab: `localShape()` tank block. |

**Keep the annex inside the reserved depth** (`mass depth = h − SEP − annexSize`) so the
footprint rect is unchanged and an annex can never overlap a neighbour behind.

### 3.4 Welding key: owner vs land use

`_build_block_masses` (`building_visuals.gd:1555`) welds bunches of `COURT_MIN_BUNCH := 5`
**same-owner** buildings. The lab welds by **land use** instead, with land use assigned from
spatial settlement seeds (§5), which is what produces single-colour districts.

These answer different questions — ownership is gameplay truth, land use is legibility. If you
adopt land-use welding, it is a **rendering** grouping and must not disturb the ownership
grouping. Most likely both are wanted: owner decides who it belongs to, use decides how the
block reads. **Owner decision required.**

---

## 4. Water discipline

### 4.1 The invariant

> **No road paint may lie in the river channel except on a bridge deck.**

The engine already states this ("no road within the river outside a bridge") and implements
bank cuts. The additions below are about making it *unbypassable*.

### 4.2 Enforce it once, over the finished road list

**Lab reference:** `trimToBanks()`.

Rather than each generator remembering to test itself, run a single pass over the final road
list. Three details that matter:

1. **"Wet" is per road class, measured at the painted edge**, not the centreline:
   `wet = RIVER_HALF + halfWidth + CASING/2 + margin`. A trunk needs more room than a lane.
2. **Densify to ~8u before testing.** A single segment can straddle the channel with *both
   endpoints dry* — a vertex-only test sees nothing. This is exactly the trap round 9 hit
   (`e:57` hairpin-crossed twice with 0 wet vertices).
3. Split each road into its dry runs; drop fragments under ~18u.

### 4.3 The deck waiver must be a rectangle, not a radius

**This is the important one, and the engine has the same bug shape.**

The lab first waived the wet test within a **radius** of the bridge point. Gates sit at
`RIVER_HALF + 11`, so there was an annulus where an approach road could slice through the
water *beside* the deck and be waived — reading exactly as a second, deckless crossing.

`bake_roads.gd`'s `_wet_chord_off_gate` tolerates wet cells **within 36u of the gate segment**,
and round 8 already found this legalising "a join CROSSING the water beside the deck"
(fixed there by scoring both orientations by raw `_max_wet_chord`).

**Generalisable fix:** a point is waived only if it lies within `DECK_HALF_W` (6.5u) of the
**gate-to-gate segment** — the deck rectangle — *and* the road is the one funnelled through
that specific bridge. Not any bridge, not a radius.

### 4.4 Crossings

- **One crossing per rivered tile**, at the mid-arc of that tile's stretch. The engine already
  does per-arm crossings (`road_crossings.gd`, `GATE_RADIUS 18`, `BRIDGE_LENGTH 42`), so this
  is mostly alignment, not new work.
- **Every crossing must carry a road.** If nothing funnels through a tile's bridge, tie the
  gates into the nearest road on each bank — **bank-matched**, so the connector cannot reach
  across the water for its attachment. Otherwise you get the phantom deck that round 9 fixed
  at 18_18. Belt and braces: don't draw an unused deck.
- **River bank roads outrank arc districts**, and a district's growth stops at
  `RIVER_ROAD_PAD` from the water so it never spans a river (its rings would be cut into
  fragments anyway).

---

## 5. Main roads: centre as preference, not requirement

Today trunks run **anchor to anchor**, and the anchor is the tile centre
(`bake_roads.gd:287`, `terrain.map_to_local(...)`). Note `C0` — the river's centre point in
`subtile_grid.gd:18` — **is the same point**, so on a rivered tile the road anchor sits in the
water. `_push_to_land` exists for this reason.

**Proposed:** replace the anchor with a **town point** — the tile centre displaced toward the
heaviest settlement grouping, then drawn to the water where there is one.

```
townPoint = centre + (grouping − centre) · (1 − CENTRE_PULL)      # CENTRE_PULL = 0.55
          → pulled to RIVER_ROAD_PAD + 10 of the bank if the tile has a river
          → pushOffRiver(RIVER_ROAD_PAD)
```

**This requires settlement groupings to exist before roads are baked.** In the engine they
already do — `_anchor_tiles()` (`bake_roads.gd:266`) uses start-building tiles as anchors. The
refactor is to go from "this tile has buildings" to "the buildings in this tile are *here*",
and to use the same seeds for land use so the road bends toward where buildings actually end
up rather than toward a decoration.

**Also proposed:** `followRiver()` — pull trunk points within ~95u of the water onto the hug
line, weighted by distance. Each point only slides along the outward normal from its own
nearest bank point, so **a road can never be pulled across the river**, and the whole result is
discarded if it would cross. In-engine this is better expressed as cost-field bias
(`COST_RIVER_HUG` already exists) than as a post-process — prefer the cost field.

---

## 6. Smaller additions

### 6.1 Merging near-parallel roads

Two lanes 5u apart carry nothing a single street doesn't. The engine solves this **at routing
time** via the reuse discount (`MERGE_RADIUS`, `COST_REUSE`, `CROWD_RADIUS`, `COST_CROWD` in
`road_realizer.gd:73-90`) — that is the right mechanism and should stay primary.

The lab's `mergeOverlaps()` is a **post-process fallback** for geometry that never went through
the realizer: region-web job endpoints, terminus glyphs, offset bank roads. It snaps points
within `MERGE_RADIUS 7.0` **onto** the host centreline (so the stretch coincides and draws as
one line) rather than deleting them. Deleting was tried first and was wrong — it strips length,
leaves stubs, and empties tiles.

Only adopt this if geometry-only roads still exist after §2.3. If everything routes, skip it.

### 6.2 Paved pockets

Any area fully enclosed by roads and **30–200u²** is filled grey, standing **1.5u** off the
kerb. Detection is a raster flood-fill from outside at 2.5u cells — anything the flood can't
reach is enclosed. A planar face walk would be exact but the polylines aren't a clean planar
graph after merging and trimming; the flood doesn't care.

The **minimum** matters: without it most "pockets" are single 6u² cells where two roads nearly
touch, which is grit rather than a yard.

**Lab reference:** `roadPockets()`.

### 6.3 Decorative buildings

Five grey off-budget outbuildings per tile, clustered at the **densest junction**: score every
road segment midpoint by how much road lies within 70u, take the best, host only on segments
within 70u of it. They sit on the kerb using the same offset ladder as the frontage packer.

Keep them in a **separate array** from real buildings so they don't distort placement counts,
coverage, welding or setback statistics — but include them in the collision set.

---

## 7. Constants

New, or changed from current engine values:

| Name | Value | Note |
|---|---|---|
| `SEP` (annex/tank detachment) | `5.0` | replaces `SUBCOMP_ANNEX_OVERLAP := -2.0`; below ~4u the outline closes the gap |
| `SUBCOMP_TANK_R` | `6–10` | was `4.0` |
| `DECK_HALF_W` | `6.5` | deck-rectangle waiver half-width |
| `WET_MARGIN` | `1.0` | on top of the per-class painted edge |
| `MIN_PIECE` | `18.0` | dry fragment below this is litter |
| `MERGE_RADIUS` | `7.0` | matches the realizer's existing value |
| `POCKET_MIN_AREA` / `POCKET_MAX_AREA` | `30` / `200` | u² |
| `POCKET_INSET` / `POCKET_CELL` | `1.5` / `2.5` | u |
| `CENTRE_PULL` | `0.55` | 1.0 would pin the main road to the tile centre |
| `RIVER_FOLLOW` | `95.0` | trunk within this gets drawn alongside the water |
| `DENSITY_R` / `CLUSTER_R` | `70` / `70` | decor hub search and clustering |
| `DECOR_PER_TILE` | `5` | |
| district radius | `249` half-tile / `176` quarter | `sqrt(2·frac·HEX_AREA/π)` |
| bisect threshold | `hexF > 0.88` | at both ends of the in-hex run |

Unchanged and reused: `RIVER_HALF 10.5`, `RIVER_CLEAR 16`, `RIVER_ROAD_PAD 28`,
`BRIDGE_LENGTH 42`, `MASK_ROAD_CLEAR 5`, `DESIGN_GAP 1`, `BLOCK_ROAD_PAD 7`,
`BLOCK_ASPECT 0.62`, `COURT_ADJ 10`, `W_TRUNK 7`, `W_LOCAL 4.5`.

---

## 8. Acceptance tests

These are the checks that actually caught bugs in the lab. **Write them as headless probes over
the shipped bake, not as eyeballing** — every defect below survived at least one confident
visual inspection.

| Check | Pass condition |
|---|---|
| **Bank flip** — for every road densified to 3u, does the bank sign change, and is that point on a deck? | 0 off-deck flips |
| **Wet paint** — any road point closer than its painted edge to the centreline, off-deck | 0 |
| **Deck use** — bridges with no road funnelled through them | 0 |
| **Ring occupancy** — buildings strictly between consecutive ring radii | every inter-ring band non-empty |
| **District adjacency** — claimed districts sharing a seam | 0 |
| **Pocket bounds** — every paved pocket area | within `[30, 200]` u², 0 cells within 1.5u of road paint |
| **Terrace formation** (after §1) | welded masses of ≥5 form at realistic densities |
| **Near-parallel** — points within `MERGE_RADIUS` of another road but >1.5u from it | materially reduced; ~10% residual is junction convergence and is correct |

**Two verification traps, both of which bit during this work:**

1. **Do not test containment against an AABB.** A rotated footprint overflows its bounding box,
   so "tank centre inside footprint bb" passed while tanks sat outside the actual shape. Use
   point-in-polygon.
2. **Do not let the audit share the code's waiver.** The lab's wet-check skipped points near
   the bridge using the *same radius* the trim used, and so reported "0 wet points" while a
   road visibly crossed the water. An audit that assumes what the code assumes proves nothing.

---

## 9. Deliberately not proposed

- **Cross-shaped footprints.** A cross has four short faces and none of them line a street; it
  wastes frontage, refuses to tile with neighbours, and reads as civic/religious. It is also
  the one shape that cannot emerge from packing — which is the tell.
- **Changing the river-hug band.** The engine measures it from the bank and is correct
  (§0).
- **Reducing the buildable mask cell.** Already done in `0d763b90`.
- **Drawing the river over the roads** to hide crossings. Considered and rejected: the road
  still exists in the network, still stamps the mask, still hosts buildings, and it would bury
  the bridge deck.
