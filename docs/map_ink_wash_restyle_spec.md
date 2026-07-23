# Map restyle — vintage ink & wash board look

Goal: move the in-game map from its current clean flat-vector look toward the
hand-drawn "vintage board game" mockup (parchment plate map: sepia ink, olive
washes, dashed roads, cross-tie rails, stamped trees, patchwork fields,
red/yellow/grey buildings). This extends the already-started "ink & wash"
direction (building outlines + wash triad + parchment overlay) to the whole map.

Reference images: the current-game screenshot (port + hills area) and the
mockup board. Drop copies at `docs/reference/ink_map_mockup.png` and
`docs/reference/current_map_screenshot.png` so this spec stays self-contained.

Constraint set by the owner: the mockup has **no elevation concept**, but the
real game has relief (prebaked height bands that roads and buildings are aware
of). The restyle must keep elevation legible — see §4.

**Owner rulings (2026-07-23):**
1. **Runtime style toggle.** The restyle must be switchable against the
   current look via a debug-terminal cheat (`toggle ink`, joining the existing
   `toggle logs|heightmap|roads|roadocc` family). Consequence: no restyle
   constant is edited in place — every changed value moves behind a `MapStyle`
   indirection from P0 onward (retrofitting a toggle later would be rework).
2. **Hex borders are DROPPED from the target style.** The map should read as
   continuous terrain that blends across hexes, not as separate plates. All
   plate-border / map-frame / edge-tick items are removed from the plan; any
   tonal variance must be organic (noise-scale), never hex-aligned. (The
   hover grid and brass selection outline stay as-is — they're interaction
   feedback, not style.)
3. **Roads get a dedicated deep-dive** (§3c): stroke-level changes are free;
   layout-level changes are gameplay-coupled and separately gated.

---

## 1. The mockup's visual language

The gap between the two images comes down to six axes. Everything below hangs
off one of these:

1. **Grade & palette** — everything warm, muted, parchment-toned; no saturated
   greens/blues/yellows.
2. **Ink linework** — one warm sepia ink draws *everything*, with a clear
   weight hierarchy and slight hand wobble.
3. **Symbolic glyphs instead of literal ribbons/blobs** — dashed-casing roads,
   ladder railways, stamped individual trees, furrowed field parcels. The
   mockup renders *map symbols*, the game renders *shapes*.
4. **Paper materiality** — visible grain, per-hex tonal variance, drop-shadow
   hints, heavy plate-like hex borders, tick marks and stubs at board edges.
5. **Parcel fabric** — nearly all land is subdivided into small tinted field
   parcels; this "fabric" is what makes empty land feel authored, not empty.
6. **Elevation** — absent in the mockup; must be *translated* into the idiom
   (engraved contours), not copied.

### Attribute inventory (mockup → current game)

| # | Attribute | Mockup treatment | Current game | Gap |
|---|-----------|------------------|--------------|-----|
| A1 | Ground base | Light olive/sage wash, subtly different tone per hex, fine engraving stipple | The visible ground is `hill_visuals.gd`'s **opaque baked relief bands** (`BAND_COLORS`, 12 steps dark-green→sand→greens→umber→white) — the terrain tile PNGs underneath are occluded. "Mottle" = parchment noise + the bands' own darkened outlines | Medium — but cheap: a whole-map re-grade is an array edit |
| A2 | Paper | Warm parchment visible outside board; grain + foxing over everything; slight vignette | `parchment_overlay.gd` active: runtime simplex noise, multiply ~14%, z=90 over all world layers, below UI | Small (strength/ramp + optional vignette + per-hex tonal variance) |
| A3 | Hex grid | Heavy dark sepia border per hex, reads as physical plates; inner offset line in places | **No persistent grid exists** — `hex_grid_overlay.gd` draws hover-neighborhood edges only (range 5, faded), plus a brass selection outline | **DROPPED (owner ruling)** — continuous cross-hex terrain preferred; keep hover/selection as-is |
| A4 | Board edge | Rail stubs with ties + paired tick marks poke off-board where routes exit | Map just ends | **DROPPED (owner ruling)** — part of the plate idiom |
| A5 | Field parcels | Land subdivided into irregular tinted parcels (sage/straw/tan/khaki), hairline borders; some with furrow hatching, some orchard dots | None — land is uniform | Largest new system |
| A6 | Roads | Narrow tan bed edged by **dashed** sepia casings; minor tracks a single dashed line; wobbly organic curves | 2-pass `draw_polyline` (dark casing under yellow local / orange trunk core), Chaikin-smoothed; bridge decks + terminus glyphs already exist | Medium (restyle existing renderer; the ink spec already defers exactly this item) |
| A7 | Rails | Classic ladder symbol: two dark rails + perpendicular ties; bridge glyphs at rivers | **No rails on the base map at all** — rail infra appears only in the Infrastructure map mode (tile circles + links) | Feature decision (§6), not a restyle |
| A8 | River | Muted blue ribbon, **dark ink strokes on both banks**, darker-blue flow squiggles inside, small bridge symbols where roads/rails cross | `river_visuals.gd`: cubic-bezier polylines, one blue (`#2D68C4`-ish), w15 (mouth 25), no bank stroke; the light halo is the baked sea **shelf band**, not a river effect; road bridge decks already drawn by the road layer | Small–Medium (2-pass casing like roads + seeded flow squiggles) |
| A9 | Sea/coast | (No sea in mockup) → adopt engraved-map treatment: ink coastline stroke + "water lining" (2–3 offset parallel lines fading seaward) | Baked sea polygons (`SEA_COLORS`: saturated navy depths → river-blue shelf → sand base); coast/lake shores get a darkened stroke already | Medium (re-grade + ink shore stroke + offset water lining) |
| A10 | Buildings | Flat fills in semantic triad — brick red (town), warm grey (industry), mustard (storage/special), cream (minor); dark ink outline, tiny window ticks, roof ridge lines, round tanks as circles; hint of SE drop shadow | **Already ~built** — ink & wash phases I1–I4 all landed: sepia ink `#3a2c18` outlines, hand-wobble, wings/courtyard massing, roof motifs (sawtooth/terrace/ridge), tanks as ink circles, an 11-color category wash (`_wash_for`). The screenshot's cream buildings are **NPC paper-white `#efe9db` by design** (the ownership cue — like uncolored lots on a vintage plate) | Small (palette harmonization + optional SE micro-shadow; NPC treatment is a deliberate decision to keep) |
| A11 | Forest | Individual stamped tree glyphs (lumpy cloud canopy, 2 greens, ink outline, trunk notch), clustered with overlap, occasional lighter under-wash; roadside singles | Jittered disc-lobe canopy batched into ONE MultiMesh (`#0d512b`→`#083b22` lerp), one offset shadow disc, arc highlights — mass, not trees | Large (new glyph variant of the existing batched mechanism) |
| A12 | Farms | Farmstead = small red/yellow buildings + surrounding parcels with parallel furrow lines at per-parcel angles | Rich system already: seeded 7-8-gon fields `#a8d98a` + single-direction diagonal hatch + brown barn/silo glyphs + dirt-lane web with river bridges. Explicitly exempted from the building plate restyle so far | Small–Medium (recolor to straw/olive + per-field furrow angles; keep the system) |
| A13 | Piers/port | (None in mockup) → translate: timber jetty — plank lines, sepia ink, tan deck | `port_visuals.gd`: white `draw_rect` dockhouse + 3 pier fingers, blue-grey outline stroke | Small |
| A14 | Ink wobble | All lines hand-drawn: low-amplitude wobble, occasional corner overshoot | Perfectly smooth vectors | Medium (shader or bake-time jitter — the open "I4" item) |
| A15 | Shadows | Buildings/trees carry a short warm-sepia offset shadow (SE) | None | Small |
| A16 | Elevation | Absent | Tint-band blobs (grass→tan→brown ramp), white peaks; roads/buildings respect relief spatially | Translation needed (§4) |

### Line-weight hierarchy (mockup)

One ink color, ~4 weights. This hierarchy is what keeps the busy map readable:

1. **Heavy** — hex/plate borders, board edge.
2. **Medium** — rails, bridges, building outlines, river banks.
3. **Light** — road casings (dashed), tree outlines, coast stroke.
4. **Hairline** — parcel borders, furrows, window ticks, water lining.

---

## 2. Palette (eyeballed starting swatches)

Sampled visually from the mockup; treat as starting points to iterate on-screen.
Everything sits inside a warm, low-saturation envelope.

| Role | Swatch | Notes |
|------|--------|-------|
| Parchment base | `#E7D7AE` | board surround + grain tone |
| Parchment deep | `#D8C392` | vignette / mottle darks |
| Ink (strong) | `#3A3226` | warm sepia near-black; ALL major linework |
| Ink (hairline) | `#6B5C44` | parcels, furrows, water lining |
| Land olive | `#B7B482` | base ground wash |
| Land sage | `#A9AE7C` | parcel variant |
| Field straw | `#D3C48F` | parcel variant |
| Field tan | `#CBB489` | parcel variant |
| Field khaki | `#B0A26B` | parcel variant |
| Urban ground | `#D9C9A2` | under town blocks |
| Forest light | `#7FA05E` | canopy top |
| Forest dark | `#5C7D46` | canopy shade half |
| Water fill | `#5E8FC4` | river/sea, warmed + muted |
| Water deep | `#3F6FA3` | flow squiggles / depth band |
| Road bed | `#E2D3A6` | near-parchment |
| Rail / road casing | `#4A3E2B` / `#33291C` | dashes and ties |
| Brick red | `#B5402F` | town/residential blocks |
| Mustard | `#D8A93B` | storage/commercial/special |
| Industrial grey | `#8E8C82` | industry slabs + tanks |
| Cream | `#EDE3C8` | minor buildings |
| Shadow | ink at ~13% alpha | offset ≈ (1.5, 2.5) world px, SE |

Elevation re-grade draft (see §4): lowland `#B7B482` → `#C9BC85` → `#CDB27E` →
`#B99468` → `#A97F55` → peaks `#EFE6CE` (cream, not pure white).

---

## 3. How each attribute maps to the engine

House rules that bound every idea below: all map features are custom `_draw()`
or MultiMesh (no Line2D/Polygon2D nodes, no sprite assets — architecture rule
#1); per-entity nodes are banned at map scale; redraws are event-gated; all
seeded variation goes through `RoadHash.pick(...)` for determinism.

Base-map draw order (`scenes/main.tscn`, back→front): `TerrainLayer` (hex
TileMapLayer) → `HillVisuals` → `ForestVisuals` → `RiverVisuals` →
`BuildingVisuals` → `RoadNetworkVisuals` (roads draw **over** buildings) →
`HexGridOverlay` → map-mode overlays → `ParchmentOverlay` (multiply, z=90) →
UI. New ink layers slot naturally into this stack.

This spec extends two existing docs rather than replacing them:
`docs/building-visuals-ink-spec.md` (the building deconstruction — its
"deferred" list already names the road/rail ink restyle) and
`docs/polygon-buildings-spec.md`. Note the DS design language already cites
Sanborn fire-insurance plates as the aesthetic north star — the mockup *is*
that idiom, so this restyle converges the map with the stated direction.

### 3a. Feature layers

| Attribute | System today | Change |
|---|---|---|
| Roads (A6) | `scripts/road_network_visuals.gd` — per-edge 2-pass `draw_polyline`: `CASING Color(0.24,0.16,0.05,0.9)` at width+2.5 under `LOCAL #e8c84a` w4.5 / `TRUNK #d97b29` w7.0; Chaikin-smoothed baked spine; bridge decks (`BRIDGE_COLOR`, 10u stroke); seeded terminus glyphs (T/Y/cut) | Keep spine + passes; change pass 1 core to near-parchment `ROAD_BED`, narrow widths (~3/4.5), and replace pass 0's solid casing with **dashed segments** walked along the polyline (world-unit dash/gap, seeded phase). Trunk = double dashed casing or heavier dash; local = lighter. Bridges: two short parallel ink strokes + tan deck. Terminus glyphs inherit the ink color automatically |
| Rails (A7) | Nonexistent on base map; rail is a per-tile infra type shown only in `infra_mapmode_markers.gd` (circles + links, L2/L3 = parallel lines) | Decision (§6): (a) skip — mockup charm without gameplay meaning; (b) new always-on rail layer drawing a ladder symbol (2 rails + perpendicular tie ticks) along tiles with rail infra, following the road spine where available. (b) is a new feature, not a restyle — park it behind the main pass |
| Buildings (A10) | `scenes/building_visuals.gd` — complete ink & wash system: `INK #3a2c18` w1.3, `_wobble_poly` (±1.1u per 16u step), wash triad by category (`WASH_GREY #8d8a80`, `WASH_RED #b0483a`, `WASH_MUSTARD #c9992e`, +8 more), NPC `#efe9db`, roof motifs, wings/courtyards, tanks | Mostly done. Optional polish: SE micro-shadow (ink @ ~13% alpha, offset ~(1.5,2.5)u, drawn under fill); nudge a few wash values toward the mockup swatches (§2); leave NPC white — it *is* the vintage-plate look |
| Forests (A11) | `scripts/forest_visuals.gd` — canopy = jittered grid of disc lobes in ONE MultiMesh (GL-compat batching win), shadow disc, `draw_multiline` arc highlights; footprint shared with roads/occupancy via `ForestFootprint` | Swap lobe discs for **tree glyphs**: small ArrayMesh (lumpy canopy fan + trunk notch + ink outline ring) instanced via the same MultiMesh path, 2–3 seeded variants × size jitter, positions from the existing lobe grid (slightly sparser step so glyphs read individually), two-green per-instance color lerp kept, light under-wash disc per cluster kept from the shadow mechanism. Same draw-call budget, same footprint contract |
| Farms (A12) | `building_visuals.gd` farm branch — `FARM_FIELD_COLOR #a8d98a` fill, single-direction hatch (`_bake_farm_hatch`, spacing 12), white/grey outline, brown barn+silo, dirt-lane web + lane bridges | Recolor: fill → straw/olive per-field variant (seeded from §2 parcel swatches), hatch → **per-field furrow angle** (seeded, follow long axis) in hairline ink; outline white → hairline sepia; barn/silo → brick red / mustard washes + ink. Keep lanes/bridges (already in-idiom) |
| Piers (A13) | `scripts/port_visuals.gd` — white `draw_rect` slabs + `BUILDING_SHADOW` outline, 3 fingers seaward | Timber restyle: deck fill → tan `#CBB489`, outline → ink, add plank ticks (perpendicular hairlines every ~6u along each finger) |
| Shadows (A15) | Forests + ports have shadow treatment; buildings none | Add building SE micro-shadow (cheap: same polygon, offset, ink-alpha, drawn first). Tree glyphs inherit the existing forest shadow disc idea per-glyph |
| Map-mode overlays | `deposits_overlay.gd`, `infra_mapmode_markers.gd`, `map_overlay.gd` — icon/circle glyphs, functional colors | Out of scope for the base-map pass; revisit only if their saturated colors clash on top of the new grade |

### 3b. Terrain, water, grid, paper

| Attribute | System today | Change |
|---|---|---|
| Ground + relief (A1, A16) | `scripts/hill_visuals.gd` — 900 land contour polygons (marching-squares, baked offline in `tools/bake_hills.tscn` / `hill_field.gd`, seed 1337) filled from `BAND_COLORS[12]`, each stroked `darkened(0.22)` w1.5; LOD: cached `ArrayMesh` fills near, one 4096px SubViewport texture bake far — both go through the same painters | Re-grade `BAND_COLORS` to the §2/§4 parchment-family ramp; restroke outlines in sepia ink (this *is* the contour look — see §4). Both LOD paths inherit automatically |
| Sea (A9) | `SEA_COLORS[6]` baked polygons: `#000d94` deep navy → shelf river-blue → `#d9cda2` land base; lakes stroked `darkened(0.25)` w2 | Re-grade to warm muted blues; ink stroke on the coast polys; "water lining" = 2–3 `Geometry2D.offset_polygon` insets computed once at load, cached into the mesh/bake, drawn as fading hairlines |
| Rivers (A8) | `scripts/river_visuals.gd` — bezier `draw_line` polylines, `RIVER_COLOR` ≈ `#2D68C4`, w15/25 | Muted-blue re-grade + 2-pass bank casing (ink under, slightly wider) + seeded darker flow-squiggle segments inside |
| Hex borders (A3) | None persistent; hover grid + brass selection only | **Dropped by owner ruling** — no persistent border layer. The continuity the owner wants is already the default: bands, parcels, forests and roads are all whole-map geometry that ignores hex seams |
| Parchment (A2) | `scripts/parchment_overlay.gd` — runtime seamless simplex `NoiseTexture2D`, multiply ramp `(0.86,0.81,0.72)→(1,0.99,0.96)` (~14%), z=90 child of TerrainLayer, world-anchored, below UI | Deepen ramp floor slightly (~0.82), optional radial vignette pass, optional **organic tonal variance**: add a second, much lower-frequency octave to the existing noise ramp so large soft patches of tone drift across the map (hand-colored feel that deliberately ignores hex boundaries — per the continuity ruling) |
| Parcels (A5) | Nothing — but the ink spec's out-of-scope list names "Field linework (terrain-layer)" as anticipated future work | New baked "field fabric": subdivide lowest land band(s) into seeded irregular parcels; hairline ink borders + per-parcel tint jitter within the band family + furrow hatch on a seeded subset; clipped against sea/rivers/roads at bake. Drawn between HillVisuals and ForestVisuals; folded into the far-zoom texture bake via the shared painter. Buildings/forests are opaque and draw over it, so no runtime clipping needed |
| In-repo idiom reference | `scripts/survey_overlay.gd` — the cartographer sheet for unsurveyed tiles: cream paper + grunge textures (`survey_paper.png`, `survey_grunge.png`), wobbled coastlines, charcoal hills, thick river bands, `Inkfree.ttf` | Mine it for textures, wobble parameters, and tone; the restyle makes the surveyed map converge toward the same family so the survey→surveyed transition feels like *inking in* the sheet |

Verification tooling: shots must run **windowed** (headless skips the hill bake).
`tools/relief_shot.tscn` frames the whole landmass (`--quit-after 800`);
`tools/farm_shot.tscn` is an isolated farm closeup (no hills/parchment). The
restyle should add `tools/map_style_shot.tscn` (house skeleton: settle ~140
frames, disable edge-pan, pan camera, save PNG) capturing three fixed framings
— port coast, hill interior, farm belt — for A/B at every phase.

### 3c. Roads deep-dive — why they look the way they do, and the three lever classes

The road system is two decoupled layers, and the distinction decides what is
safe to change:

**Layout** (where roads go) is baked by `tools/bake_roads.gd` (roads-v3):
anchors = hand-authored road tiles ∪ urban tiles ∪ start-building tiles →
Prim's MST → loop edges wherever the tree's detour ratio exceeds 2.2 (so the
map reads "road atlas", not drainage tree) → seam stitching, dead-end
stitching, sparse-tile coverage spurs (≥12% of each flagged tile's interior
within 90u of a road), shared bridge-gate nodes. Every edge is routed by
`scripts/road_realizer.gd`'s documented cost model ("Appendix A — change
knowingly"): +50% cost per altitude level, valley preference, serpentine
climb behavior (across-slope cheap, up-slope dear), **river-hug discount
(0.6× within a 4–24u band — this is why roads shadow rivers; deliberate and
period-correct)**, merge/reuse discounts that collapse parallel strands,
graduated building/forest avoidance, farm-lane threading, per-region jitter
and turn-cost multipliers, all through a greedy ε=1.30 A* on a 12u grid.
The bake also emits `flagged_tiles`, which a fresh match applies as actual
"roads" infrastructure — **layout is gameplay** (geometry == gameplay).

**Stroke** (how the polyline is drawn) is `road_network_visuals.gd`: every
edge funnels through one choke point, `_draw_edge_polyline` (2-pass casing
under color), plus bridge decks and terminus glyphs that reuse the same
colors. Stroke changes are pure-visual by construction.

Why it currently reads "modern highway atlas" instead of the mockup's cart
tracks:
1. **Stroke weight/color** — 4.5–7u saturated yellow/orange ribbons with
   solid casings are the single biggest contributor.
2. **Macro-meander** — grid A* + seeded cost jitter + Chaikin corner-cutting
   yields continuous gentle curvature everywhere. The mockup's lines are
   *globally direct with small local wobble* — a shaky pen following a
   ruler, not a motorway alignment.
3. **Density taste** — MST + loops + stitching + coverage spurs guarantee a
   fairly even web; the mockup is sparser between settlements. (Gameplay
   wants the coverage; this is a taste knob, not a flaw.)

The three lever classes:

- **Class 1 — stroke restyle (P2, free).** Dashed sepia casings over a
  near-parchment bed, narrower widths, ink-unified bridge/terminus glyphs.
  No rebake, no gameplay contact.
- **Class 2 — stroke geometry post-pass (P2, free, the big one).** At
  draw-cache build time, per edge: **simplify the drawn polyline**
  (Ramer–Douglas–Peucker, ε ≈ 8–15u — kills the A*-grid meander and Chaikin
  roundness, restoring direct runs) **then apply seeded hand wobble**
  (perpendicular jitter ±~1.5u every ~20u — the exact pattern
  `building_visuals._wobble_poly` already uses, corners kept exact). The
  *logic* geometry, tiles, bridges and gameplay flags stay untouched — the
  same drawn-vs-logic separation buildings already practice. Displacement
  stays far under the tile-clip safety margin (`_clip_to_built` remains the
  net). Cached per edge; rebuilt only on the existing network-change events.
- **Class 3 — layout/bake levers (gated, owner sign-off per change).**
  Density (`SPARSE_COVERAGE_MIN 0.12`, `LOOP_CAP_DIVISOR 6`,
  `DETOUR_RATIO 2.2`), macro-straightness (`JITTER_BY_IDENTITY`, `TURN_*`,
  `COST_VALLEY`/`COST_GRADIENT_K`), hierarchy (`TRUNK_LENGTH`). Any of these
  means a **rebake that changes `flagged_tiles` → changes which tiles carry
  road infrastructure → gameplay**. Precedent: the roads-v3 rebake shifted
  two e2e power checks via free corridor roads. Protocol if ever pulled:
  rebake → diff flagged tiles vs previous bake → run the e2e harness and
  explain any failure-set change → screenshot A/B.

**Recommendation: do Class 1 + 2, then reassess.** Restyled strokes over
simplified-then-wobbled geometry should carry ~90% of the mockup's road
character; only reach for Class 3 if the A/B still reads too dense or too
serpentine, and treat it as its own gated mini-project.

---

## 4. The elevation question

The mockup is flat; the game's relief (prebaked height field, render-time tint
bands, roads/buildings that respect the shapes) is both gameplay-relevant and
part of the maps' character. Three candidate translations:

**Option A — parchment-family band re-grade + ink contours (recommended).**
Keep the existing band geometry exactly as-is; re-grade `BAND_COLORS` into the
olive→ochre→sienna ramp above, and restroke the band outlines in hairline
sepia ink (every 2nd band slightly heavier). This is nearly free: the bands
are already closed marching-squares contour polygons, and they are *already
stroked* (`darkened(0.22)`, w1.5) — the change is the stroke color/width rule,
plus the fill ramp. Stroked in ink, the band boundaries literally *are*
contour lines, which is exactly how period maps drew relief. Zero new data,
both zoom LODs inherit through the shared painters, and placement legibility
is fully intact. Peaks go cream instead of white.

**Option B — hachures (later garnish).** Short ink ticks perpendicular to band
boundaries on the downhill side, upper bands only. Very evocative, medium
effort (needs local gradient direction), purely additive on top of A. Park it.

**Option C — soft hillshade multiply (default off).** A ≤8% multiply of the
prebaked hillshade under the flat washes. Risks muddying the gouache flatness
that makes the mockup work; keep as a debug toggle only.

Interplay rules:

- **Parcels stop where hills start** — generate field fabric only on the
  lowest band(s). Matches both the idiom (fields don't climb mountains) and
  gameplay (farms are lowland). Upper bands keep clean washes + contours.
- **Trees allowed on all bands** (forested hills read well over contours).
- **Roads/rails over hills** need no special casing — dashed symbology snaking
  around band shapes will read as mountain tracks automatically, because the
  underlying geometry already respects relief.

---

## 5. Phased plan

Ordered so the cheapest, most transformative work lands first; every phase is
independently shippable and A/B-verified with windowed shots. Phase 0 sets up
the harness; P1+P2 together get ~80% of the mockup's read.

**P0 — Style seam + harness + global re-grade** *(the architectural phase)*
- **`MapStyle`** (small static class or autoload): holds `ink: bool` plus the
  per-layer style tables — classic and ink values for every constant this
  restyle touches (`BAND_COLORS`, `SEA_COLORS`, river/road/port/farm/forest
  colors, widths, parchment ramp, feature flags like `parcels_enabled`).
  Layers swap hardcoded const reads for `MapStyle` lookups. Emits
  `style_changed`.
- **`toggle ink` cheat** in `debug_terminal.gd` (joins
  `toggle logs|heightmap|roads|roadocc`): flips `MapStyle.ink` and
  invalidates each layer through its existing rebuild seam — hills rebuild
  band meshes + re-bake the far-zoom texture, parchment regenerates its ramp
  texture, roads reset `_drawn_edges` and redraw, buildings/farms/ports/
  forests rebuild their caches. Switch cost is dominated by the hill texture
  re-bake (~sub-second); fine for a cheat.
- Author `tools/map_style_shot.tscn` (3 fixed framings; house skeleton),
  capturing **both modes** per run — the A/B harness for every later phase.
- First ink-mode content: `BAND_COLORS` → parchment-family ramp (§2/§4),
  `SEA_COLORS` → warmed muted blues, peaks → cream; `RIVER_COLOR` → muted
  `#5E8FC4`-family; road `LOCAL/TRUNK` → bed tans + `CASING` → ink
  `#3a2c18` (widths unchanged until P2); port + farm swatches; parchment
  floor 0.86 → ~0.82. Classic mode stays byte-identical to today.
- Verify: unit suite + both-mode shot triptych + a few toggle round-trips.

**P1 — Ink structure** *(contours, shores, hex borders)*
- Band strokes: `darkened(0.22)` → sepia ink hairline, every 2nd band heavier
  (elevation Option A). Touch all three paint sites (vector, direct, bake).
- Coast: ink shoreline stroke on sea polys; water lining = 2–3 cached
  `offset_polygon` insets, fading alpha; lakes keep their stroke, re-inked.
- Rivers: bank casing pass + seeded flow squiggles.
- Optional: organic tonal variance — a second low-frequency octave in the
  parchment ramp (soft cross-hex tone drift; no hex alignment, per ruling).
- *(Hex borders: dropped by owner ruling — nothing drawn here.)*

**P2 — Road stroke: geometry post-pass + symbology + timber ports** *(§3c
Classes 1+2)*
- **Simplify-then-wobble** the *drawn* polyline per edge (RDP ε≈8–15u, then
  seeded perpendicular wobble ±~1.5u/20u, corners exact — the
  `_wobble_poly` pattern). Logic geometry, tiles, bridges, gameplay flags
  untouched. Cached per edge alongside the dash lists below.
- Dashed casings: walk each (simplified) polyline emitting dash segments
  (world-unit dash/gap ~14/8u, seeded phase via `RoadHash`) into one batched
  multiline; keep a solid near-parchment bed core. Widths (owner +50% ruling
  2026-07-23): 6.75 trunk / 4.5 local. **Trunk = the cross-continent
  arteries** (the bake's long-haul spine tier) and carries a dashed ink
  centre line (11/9u, batched) on top of the bed. Rebuild only on the
  existing network-change events.
- Bridges: tan deck + two short parallel ink strokes; terminus glyphs inherit
  ink automatically.
- Piers: tan deck fill, ink outline, plank tick hairlines.
- Explicitly out of this phase: §3c Class 3 layout levers (density,
  straightness costs) — separate, gated decision after the A/B.

**P3 — Building & farm polish** *(the building system is already built)*
- SE micro-shadow under building fills (ink @ ~13%, offset ≈(1.5,2.5)u).
- Nudge wash values toward §2 where the A/B says so; NPC stays paper-white.
- Farms: field fill → seeded straw/olive variants; hatch → per-field furrow
  angle along the plot's long axis, hairline ink; outline white → sepia;
  barn/silo → red/mustard washes + ink. Lane web + lane bridges kept.

**P3b — Farm parcelization** *(DESIGNED 2026-07-23 after owner feedback:
"farms look too chunky"; grey lane web already removed in ink mode)*

Target read (from the mockup): a farm is not one big blob — it's a **block of
rectangular/trapezoid parcels** packed edge-to-edge, separated by thin light
paths ("small regular roads"), each parcel individually tinted and furrowed,
with irregular parcels where the grid meets the block's outer boundary.

Mechanism — draw-only, the logic footprint/occupancy polygon is untouched
(same drawn-vs-logic split as buildings and roads):

1. Keep the existing field polygon exactly as-is; it becomes the **clip
   boundary** for a parcel grid.
2. At layout bake (beside the existing hatch/furrow bakes, so the style
   toggle stays instant): build an **oriented grid in the field's PCA frame**
   — seeded strip widths ~30–55u along the long axis, seeded cross-cuts
   ~40–80u, each cross-cut sheared ±3° (seeded) so cells are trapezoids, not
   graph paper. Clip every cell to the field polygon
   (`Geometry2D.intersect_polygons`) → edge cells become the mockup's
   irregular boundary parcels. CCW-normalize before any offsetting (the
   Clipper winding gotcha).
3. **Paths between parcels**: fill the whole field with a parchment-tan path
   color first, then draw each parcel **inset ~2.2u** (negative
   `offset_polygon`) — the base showing through the gaps *is* the small-road
   network. No extra line drawing needed for paths.
4. Per parcel (all seeded via `RoadHash` on instance_id + parcel index):
   tint from the straw/olive variant set; ~60% get hairline furrows along
   the parcel's own long axis (a few deliberately perpendicular); hairline
   sepia outline at low alpha; the rest stay plain for rhythm.
5. Store as `placement.parcels` / `_farm_render.parcels`
   (`[{poly, tint_i, furrows}]`); ink draw renders parcels instead of the
   single fill+furrows; classic path untouched. Barn/silo unchanged.
6. Field outer outline: drop it in ink mode — the parcel edges + paths carry
   the boundary (removes the last "chunky blob" cue).

Cost: bake ~10–25 clip ops per farm × ~30 farms, once at layout — trivial.
Draw adds ~20–40 canvas commands per farm (parcel fills + hairlines);
farms redraw only on layout events. If command count ever matters, parcels
can collapse into one per-vertex-colored ArrayMesh per farm.

**P3c — Baked industrial sprites** *(BUILT 2026-07-23, owner-directed)*
Hand-drawn top-down art (two 3×3 magenta-keyed sheets, `assets/ink_buildings/
src/`) replaces the procedural plates in ink mode for exactly ten industrial
types: furnace, EAF, both factories, assembly plant, high-tech manufactory,
both refineries, chemical plant, electrolyser. Assignment rules: tank+pipework
art → refineries/chem/electrolyser; flues-without-tanks → furnace/EAF; plain
sheds/roof compounds → factories/assembly/high-tech. `tools/
bake_ink_buildings.gd` slices, hue-keys the magenta (incl. its shadows),
de-fringes, crops, and applies authored per-level erase rects: L3 = full art,
L2/L1 progressively trimmed along logical axes (tank yards, towers, satellite
sheds). Renderer (`_draw_ink_art`): sprite centered/rotated to the footprint,
long side = 2× footprint extent, level-picked live, silhouette shadow, NPC
lifted toward paper-white; procedural wings/tanks/storeys suppressed for these
instances. Classic untouched.

**P4 — Tree glyphs** *(forest identity)*
- Replace disc lobes with 2–3 seeded canopy-glyph `ArrayMesh` variants (lumpy
  fan + trunk notch + ink rim baked into the mesh), instanced through the
  existing single-MultiMesh path; slightly sparser grid step so glyphs read
  individually; keep two-green per-instance lerp, shadow disc, footprint
  contract, `begin/end_bulk` and one-per-frame seeding (LoadPacing).

**P5 — Field-parcel fabric** *(biggest new system; the "authored land" feel)*
- Bake-time generation (extend the hills bake or a sibling bake): subdivide
  the lowest land band(s) into irregular seeded parcels; outputs are
  visual-only arrays (hairline borders, per-parcel tint index, furrow subset)
  — **no gameplay data touched**.
- Render as one per-vertex-colored ArrayMesh + one batched hairline multiline
  between HillVisuals and ForestVisuals; include in the far-zoom texture bake.
- Suppress above the lowland bands (§4 interplay); clip against sea/rivers/
  road spine at bake; opaque buildings/forests/farms simply draw over it.

**P6 — Garnishes** *(decision-gated extras; plate-frame items removed by the
hex-border ruling)*
- Optional: hachures (Option B), always-on rail ladder layer (A7 decision),
  engraving stipple texture on land, map-mode overlay palette harmonization,
  §3c Class 3 road-layout tuning if the P2 A/B still wants it.

Definition of done per phase (house rules): unit suite green + windowed
before/after shots from `map_style_shot` (+ `relief_shot` for whole-map
grades). Pure-visual phases must not change any sim outcome; the P5 bake adds
visual-only arrays and must leave `roads_baked`/gameplay height data
byte-identical.

---

## 6. Decision points for the owner

1. ~~Hex borders~~ — **RESOLVED 2026-07-23: dropped**; continuous cross-hex
   blending preferred. (Recorded in the rulings block up top.)
2. **Rails**: the mockup's railways don't exist on the base map. Skip, or
   build an always-on rail-ladder layer for tiles with rail infra (new
   feature, not a restyle)?
8. **Road layout (§3c Class 3)**: only if the post-P2 A/B still reads too
   dense/serpentine — density and straightness knobs each require a rebake,
   a flagged-tile diff, and an e2e failure-set check. Default: don't touch.
3. **Parcels**: hairline borders only, or tinted fills too (recommended:
   tints, lowland-only)? Coverage density?
4. **NPC buildings**: keep paper-white ownership cue (recommended — it *is*
   the vintage-plate idiom) vs mockup-style full-color for everyone.
5. **Elevation**: contours only (A, recommended) vs + hachures (B) vs a ≤8%
   hillshade multiply debug toggle (C).
6. **Sea**: engraved water-lining + muted navy (recommended) vs plain wash.
7. **Palette sign-off**: §2 swatches are eyeballed; approve/adjust from the P0
   A/B triptych before P1+ builds on them.

---

## 7. Risks & constraints

- **GL Compatibility renderer**: every naive `draw_line`/`draw_circle` is its
  own draw call. All new linework must batch (multiline batches, ArrayMesh,
  MultiMesh) — the hills/forests/grid code shows the house patterns.
- **Do-not-regress perf wins**: hills offline bake + cached ArrayMeshes +
  far-zoom texture LOD; forests as ONE MultiMesh; roads baked spine;
  LoadPacing one-per-frame seeding; event-gated redraws, no `_process`.
  Per-entity nodes at map scale are banned (architecture rule #1).
- **Both zoom representations**: hills swap vector↔4096px texture bake —
  every terrain-level change must go through the shared painters so the far
  zoom matches; verify both ends (effective zoom ~1.0–4.0).
- **Overlay clash**: map-mode overlays (deposits icons, infra circles,
  stockpile tints z=10–23) keep functional saturated colors and will sit on a
  muted map; the parchment already multiplies over them. Harmonize only if
  the P0 A/B shows real clash (P6 item). Brass selection is already in-idiom.
- **Road layout is gameplay**: the bake's `flagged_tiles` become real road
  infrastructure on fresh matches. Stroke/draw changes are safe; any
  routing-cost or bake-parameter change is a gameplay change with an e2e
  protocol (§3c Class 3). Precedent: the roads-v3 rebake moved two e2e power
  checks.
- **The style toggle is load-bearing architecture**: every restyled value
  goes through `MapStyle` from day one; classic mode must stay byte-identical
  (the toggle doubles as the regression check). Layer invalidation reuses
  each layer's existing rebuild seam — no new per-frame work.
- **Wobble stays inside the corridor**: the road draw-pass displacement
  (≤~2u) is far under the tile-clip margin; `_clip_to_built` remains as the
  safety net.
- **Determinism**: all seeded variation via `RoadHash.pick` / fixed bake seeds
  (hills seed 1337); no `randi()` in draw paths.
- **Verification is windowed**: headless skips the hill bake — screenshots
  must run with a window (`--quit-after` pattern).
- **Branch hygiene**: `goods-focus-reorg` currently carries uncommitted edits
  to `building_visuals.gd` / `forest_visuals.gd` / `world_map.gd`. Land or
  stash those first; the restyle should be its own branch off the branch that
  carries the roads-v3 bake + ink work, with P0 as its first commit.
