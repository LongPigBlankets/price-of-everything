# Map editor & authored-map plan

**Status: PLAN, 2026-08-16.** Written against `decorative-buildings-and-city-look` just after
PR #115 (the midcentury fabric renderer) merged. Companion docs:
`map-mass-form-vocabulary.md` (the 17-form vocabulary), `map-density-and-port-addendum.md`,
`hero-loop-stopping-criteria.md`.

## 1. Why

Every 4/5 map result ever produced came from the per-settlement **authored** hero loop; eight
straight inside-parcel procedural mechanisms were rejected for repetition. The logical end of
that finding is to stop steering the generator and hand-author the fabric directly — and the
owner's stated goal (2026-08-16) is to hand-author **all tiles**, migrating
settlement-by-settlement with map-wide authored coverage as the end state. This plan turns
that into tooling:

- an **in-Godot map editor** that shows the real relief map (bands, sea, rivers, lakes) as a
  locked underlay and lets the designer draw on it in world coordinates;
- an **authored-map document** (`data/map_authored.json`) storing roads (curves + straights,
  3 width classes, per-stroke `unlockable` tags), decorative masses from the established
  vocabulary, parks, and gameplay-building slots;
- an **export step** that bakes the authored look into world-aligned textures the game
  renders, plus a thin runtime layer for the parts that must stay dynamic (unlockable roads,
  gameplay buildings).

Everything here is **aesthetic** per the 2026-08-15 architecture ruling: the per-tile
infrastructure flag/level remains the only gameplay surface, and this plan never touches it.

## 2. Ground rules: coordinates, zoom, widths

Facts verified in code (see §9 for the seam table):

- Flat-top hexes, odd-q offset. Tile cell 540×480 u, column pitch 405 u, row pitch 480 u,
  odd columns +240 u down. World rect `(0,0)–(13905,11760)`; `tile_1_1` centre `(1080,1200)`.
  All conversion goes through `%TerrainLayer.map_to_local()` — never digit arithmetic on ids.
- **Camera `zoom` is px per world unit.** `zoom_max` is viewport-relative:
  `viewport.y / 1200` (`camera_controller.gd::_configure_for_map`), i.e. full zoom always
  shows 2.5 tile-heights vertically — **~1.107 px/u** on the owner's 2360×1328 window,
  0.9 px/u at 1080p.
- Therefore the requested road thicknesses translate as:

| class | px @ full zoom (spec) | world units (constant) | today's nearest |
|---|---|---|---|
| major | 20 | **18.0** | midcentury trunk bed 8.2 |
| mid | 14 | **12.6** | midcentury local bed 5.0 |
| minor | 7 | **6.3** | fabric alleys 2.2–3.6 |

  Widths are stored in **world units** (the px spec is display-relative); the editor gets a
  one-key "preview at full zoom" toggle so the on-screen px can be eyeballed against the spec.
  These are bed widths ~2× today's midcentury streets — a deliberate look change toward the
  figure-ground reference. The **treatment derives from the midcentury road look** (paper
  bed + solid ink casing + seeded wobble) but each class gets its own curated values —
  see §10.1. Constants live with the other midcentury style values in
  `map_midcentury_style.gd`.
- **Roads are zoom-invariant world geometry** (owner ruling, 2026-08-16). A stroke's shape
  and width never change with camera zoom — no screen-space width floors (the
  constant-screen-width `iw = 1/s` trick belongs to building linework, never roads), no
  zoom-dependent simplification or reshaping. Zoom only scales them optically; the bake
  gives this by construction, and the far-zoom generalization of §7 therefore applies to
  fabric and parks only, never to roads.

## 3. The authored-map document

`data/map_authored.json`, versioned, pretty-printed, stable ordering (sorted keys, monotonic
never-reused ids). Loaded by a new static `scripts/authored_map.gd` following the
`roads_baked.gd` loader pattern (cache, `reset_for_tests()`, staleness warning against
`HillBaked.source_hash()`).

```jsonc
{
  "version": 1,
  "hills_hash": "…",                  // staleness tripwire, same idiom as roads_baked
  "settlements": {
    "capital": {
      "tiles": ["tile_23_8", "tile_24_7", …],   // the authored-coverage set (suppression key)
      "next_id": 143,
      "roads": [
        { "id": "r:capital:12",
          "class": "major",                      // major | mid | minor  → 18 / 12.6 / 6.3 u
          "points": [ {"p":[x,y]}, {"p":[x,y], "in":[dx,dy], "out":[dx,dy]}, … ],
          "unlockable": true,                    // visible only when EVERY tile in `tiles`
          "tiles": ["tile_23_8","tile_23_9"],    //   carries the road flag; editor-derived,
                                                 //   stored like the baked network's edge.tiles
          "bridges": [ {"t": 0.41} ]             // param positions of auto-detected wet chords
        }
      ],
      "decor": [
        { "id": "d:capital:31", "form": "courtyard",   // 17-form vocabulary, §5
          "pos": [x,y], "rot": 0.42, "size": [w,h],
          "params": {"wall": 0.18, "gap": 0.31},        // form-specific, seeded default
          "roof": "pitched",
          "sacrificial": false }                        // only masses marked sacrificial
                                                        // may be evicted in-game (§4, §6)
      ],
      "parks": [ { "id": "p:capital:4", "kind": "green", "outline": [[x,y], …] } ],
      "farms":   [ { "id": "fa:capital:2", "outline": [[x,y], …] } ],           // ≤8 vertices
      "forests": [ { "id": "fo:capital:7", "outline": [[x,y], …], "density": 1.0 } ],
      "slots": {
        "tile_23_8": {
          "pins":   [ {"pos":[dx,dy], "angle": 1.1, "size": "medium"} ],  // tile-centre-relative
          "frames": [ {"origin":[dx,dy], "tangent":[tx,ty], "cols":3, "rows":2,
                       "lot":[44,44], "size": "small"} ],
          "large":  [ {"outline": [[dx,dy], …], "accepts": ["farm","forest"]} ]  // ≤8 vertices
        }
      }
    }
  }
}
```

Notes on the model:

- **Roads are Curve2D-shaped**: per-point optional in/out handles; a point with no handles is
  a corner, a run of handle-less points is a straight polyline. The editor tessellates with
  Godot's `Curve2D` and then applies the existing midcentury styling (RDP ε 8 is skipped for
  authored strokes — they are already economical — but the seeded `_wobble_polyline` [22, 1.1]
  is applied, keyed by stroke id, for the hand-inked feel).
- **Unlockable = the connection rule.** An unlockable stroke stores the set of tiles it
  touches (editor-derived, recorded like the baked network's `edge.tiles`) and renders only
  when **every** one of them carries the road flag. One predicate covers both cases: a
  roadless tile's internal streets touch only that tile, so they appear when it gains roads;
  a **connector from an adjacent, already-roaded tile** touches both tiles, so it appears
  exactly when the new tile's roads can join the neighbour's pre-existing network. Hidden
  connectors leave no stub at the seam — the stroke appears whole (this is the baked
  network's `_all_tiles_flagged` fast path, not the point-clip). Strokes touching any
  start-unflagged tile default to unlockable; split-at-tile-boundary remains as an editing
  command for staging long runs.
- **Slots come in three sizes and two shapes** (size ruling 2026-08-16): **large** = farms
  and forests — ≤8-gon polygons; when a farm/forest building lands, the polygon becomes its
  footprint and the existing field-parcel / woodland machinery fills it. **medium** = mines
  plus any building whose drawn size reaches **40 u or more at any level**; **small** =
  buildings that stay **under 40 u through L3**. Classification is computed from the
  catalog × the generator's frames, always by the **maximum-level extent** — which is
  engine-consistent, because L1 already reserves the L3 frame (test-pinned: level frames
  are equal across L1–L3) — and published as an auto-derived table the owner reviews and
  can override per building. (A wrinkle the table will surface: `ART_DRAWN_MIN = 40`
  floors art buildings' drawn size at 40 u, so "small" as-specced mostly catches
  plate/infra buildings — the thresholds are constants to tune against the real list, not
  law.) Shape-wise, *pins* are individual placements (position + angle + class) and
  *frames* are authored block grids (origin/tangent/cols/rows/lot) expanding to classed
  lots like today's block template — one frame supplies dozens of placements on a dense
  tile. A building whose class has no free slot falls back to the next class up.
- **Farms and forests are authored as polygons of up to 8 vertices.** The outline is the
  authored truth; the fill is generated — farm polygons run the existing parcel fabric
  (PCA-framed strips, cross-cuts, seeded tints, furrows; barn/silo optional) and forest
  polygons fill with the canopy + tree-glyph scatter, clipped to the outline, seeded by the
  instance id. **Neither may overlap buildings**: the editor lints farm/forest outlines
  against decor masses, slots and gameplay footprints (a field may still run *under* a
  canopy edge — today's farm-under-forest contract — but neither touches built ground).
- **Coordinates**: roads/decor/parks/farms/forests in absolute world units; slots
  tile-centre-relative (that is what the placement pipeline consumes —
  `TILE_CENTER (270,240)`, `center_rel`).
- **Ids are stable and never renumbered.** This is a hard rule learned from the procedural
  fabric, where positional seed keys (`"%s|parcel|%d" % [key, records.size()]`) make any
  insertion reroll every downstream form/colour. All seeded variation in authored content
  keys off the instance id via `RoadHash`.

## 4. The editor

`tools/map_editor.tscn` + `scripts/map_editor/*.gd` — a **windowed Godot tool scene**, same
family as the shot tools. Not a browser tool: the ink/wobble/mass renderers, the NavGrid
water truth, and the bake all live in GDScript, and the Packing Lab taught us that porting
constants across runtimes is standing friction. The editor draws with the exact code the bake
uses, so preview and export cannot drift.

**Boot** (copied from `tile_shot.gd`): instantiate `res://scenes/main.tscn`, settle ~150
frames, hide `UILayer` + `HexGridOverlay`, force midcentury, take the camera (`set_process
false`, write `zoom` and `_target_zoom` directly, disable edge pan) but keep free pan/zoom
bound to the mouse — and, unlike shot tools, **do not** `set_disable_input(true)`. Full world
boot is ~20–30 s on this branch; acceptable for an editing session (a skip-placements fast
boot is a later nicety).

**Underlays / overlays** (each a toggle):

- live relief + rivers + lakes + forests (the real layers — at editing zooms the crisp
  vector LOD is active anyway);
- procedural fabric ghost (`MapStyle.set_midcentury` on/off) for tracing over the current map;
- tile borders + ids + terrain class; **road-flag state** (start-flagged 328 tiles vs not,
  the exact set `world_map._apply_baked_road_flags` uses) so the designer knows what needs an
  `unlock` tag; NavGrid water mask; forest discs; gameplay footprints + current accommodation
  sites; baked `RoadNetwork` edges with their **tile-entry gate points** (snap targets so
  authored strokes meet the procedural network cleanly at settlement boundaries).

**Tools**: select/transform (move, rotate, resize, delete; marquee), road pen (click =
corner, click-drag = curve handles, double-click/Esc = end; per-stroke class + unlockable +
wobble toggle; snapping to endpoints, gates, and optional angle-snap for straights), and a
**drag-and-drop palette** for everything with a shape — decor forms, parks, farm/forest
polygons, slot pins/frames/large-polygons: drag off the tool panel, drop on the map.
**Road snap** (owner flow, 2026-08-16): while a dragged shape is within `SNAP_ROAD_DIST`
(default **2 u** per the ruling; ≈2 px on screen at full zoom, so it ships as an editor
setting) of a road, it snaps to it — frontage edge rotated onto the road tangent and
seated at the kerb (bed half-width + margin), which is precisely the placement pipeline's
`verts[0]→[1] = road tangent` contract — and can be pulled away again (release threshold
~2× the snap distance so the state doesn't flicker mid-drag). Dropped stamps then take
param dials, "reroll variation", and R to rotate. **Sacrificial labeling** (owner flow,
2026-08-16): click any decor mass with the select tool (point-in-polygon hit), then toggle
with **X**, right-click → "Mark sacrificial", or the inspector checkbox — marquee selection
toggles many at once. Marked masses carry a persistent editor badge (dashed outline + small
✕, toggleable in the layers panel), and the tile readout counts them
("tile_23_8 — 14 slots, 3 sacrificial") so thin tiles show at a glance. Undo/redo as a
command stack;
autosave to the scratch dir; explicit save to `res://data/map_authored.json` (via
`ProjectSettings.globalize_path` — `save_png`/`FileAccess` to `res://` from a running build
is the documented trap).

**How it launches (owner ruling 2026-08-16): cheat-gated, from the main menu.** Enter
`debug CandC` in the main menu's debug terminal and a **Map Editor** entry appears in the
menu column, opening the editor. No new pass-phrase: the terminal's existing unlock
(`debug_terminal.gd`, static `_cheats_unlocked`, already survives scene reloads and already
runs on the menu) gains a public accessor plus a `cheats_unlocked` signal, and the menu
adds/reveals its button on it.

**The safety rule this creates.** `main_menu.gd` ships; the editor does not. A shipped
script may therefore never `preload` (or `const`-reference) anything under the excluded
paths — that resolves at parse time and would break the exported game. The button
instead **probes for the scene at runtime** (`ResourceLoader.exists(EDITOR_SCENE)`) and
loads it by path string only when present, so in an exported build the file is absent, the
probe fails, and the entry never appears — belt and braces with the export filter.

**Where it lives (owner ruling 2026-08-16): in the game project, out of the exported
builds.** A separate editor project would have to import or duplicate exactly the
renderers this plan depends on (`hill_visuals`, the painters, `MapStyle`, `RoadHash`,
NavGrid, the catalog) — and the Packing Lab already taught that shared-by-copy drifts.
Instead: editor scenes/scripts live at `tools/map_editor/` + `scripts/map_editor/`,
launched via `<godot> --path . res://tools/map_editor/map_editor.tscn`, and the export
presets exclude them. The mechanism is already in use — all three presets run
`export_filter="all_resources"` with `exclude_filter="assets/icons/goods/medium/*"`
(`export_presets.cfg:8-10`), and note that **`tools/*` ships in today's builds**: extend
the filter with `tools/*,scripts/map_editor/*` (optionally `tests/*` for a smaller pck —
nothing shipped references those directories), and add a pck-listing line to the export
runbook so the exclusion is verified, not assumed. One dependency rule keeps it safe:
**shipped code never references editor-only scripts** — the runtime layers, painters,
`FormVocabulary` and the `AuthoredMap` loader are shipped; editor UI/undo/palette live in
`scripts/map_editor/` and are editor-only by definition. A preload from shipped→excluded
would break the exported game at runtime, so the suite gains a one-line guard (grep
shipped scripts for `map_editor` references).

**Live lints** (same predicates as the export gate, §7): stroke/mass/park wet at 4 u vs
NavGrid (the `road_water_audit` idiom — W1.01 stays zero); mass or slot off dry land /
outside its hex; slot lot overlapping a road corridor or another slot; an always-on stroke
entering a start-unflagged tile (almost certainly meant to be unlockable); authored tile
with purchasable roads but zero unlockable strokes (the "player buys roads and nothing
appears" hole); authored tile with no sacrificial masses for overflow (the eviction stage
would have nothing to take — soft warning); a sacrificial mass whose SE shadow overlaps a
neighbouring mass (sprite compositing seam risk, §6).

## 5. Vocabulary: masses and parks

The stamp palette is the **17-form vocabulary**: the four live forms (`solid`, `u`/wings,
`l`, `ring`/courtyard) plus the 13 specced forms (T-half, T-full, right triangle, hollow
triangle, half-octagon, H, cross, shallow-E; small: square, rectangle, kinked slim bar, L,
H). The 13 constructors are **already built and tested** on `gauntlet4/form-geometry`
(165 asserts, suite green) — merging that branch (constructors only, no procedural wiring)
is Phase 0's first step, exposed as one static API (`FormVocabulary.build(form, params)
-> PackedVector2Array`) that the editor, the bake painter, and (later, if still wanted) the
procedural fabric all share.

Rendering reuses the fabric's mass treatment via a small extracted static painter
(fill + SE shadow offset `(2.2, 2.8)` + roof motif + `MapMidcenturyStyle` washes), so an
authored mass is pixel-identical to a procedural one. The §4 vocabulary rule stands in the
editor too: stamps default to seeded per-instance variation (aspect, limb thickness), and
the dials exist for deliberate overrides.

Parks reuse the three existing looks (`green` face-park inset, `courtyard` green, street
`park`) with the seeded 4-olive `PARKS` palette.

**Farms and forests** join the palette as the §3 polygons. Farms fill with the farm
renderer's parcel-fabric bake. **Forests fill with individual trees** (owner ruling
2026-08-16): `scripts/tree_shapes.gd` — the `TreeShapes` vocabulary written for the
city-plate work and currently parked on the **`road-density`** branch (added in `3a31df86`,
split off in `21e6e63b`; the merged line still draws forests as lobed canopy discs in
`forest_visuals._ensure_canopy`). It is a good fit as-is: three kinds (SMALL 2.6 u
hedgerow, FIR 4.2 u conifer rosette, LARGE 6.0 u specimen), seeded lumpy/spiky crowns
through `RoadHash`, a `scale` parameter so a caller varies a tree without inventing a
fourth kind, and SE shadows that scale more than proportionally with size so big trees
read as tall. Cherry-pick `tree_shapes.gd` into P2 (geometry only — no colour decisions,
no `randf()`); colours keep coming from `MapStyle`. The editor scatters trees inside the
polygon (seeded by polygon id, density dial, size mix, edge-denser option) and **clips
every crown and its shadow to the outline** — the polygon is a hard boundary, so a wood
can never spill onto neighbouring buildings.

**Procedural forest discs are suppressed inside authored polygons** (owner ruling, same
date) — the authored outline is the only forest there, in both the visual and the
non-visual sense. That matters because forest discs today also feed the buildable-mask
carve in `BuildingVisuals._ensure_tile` and the road bake's forest declamp: the authored
polygon replaces the disc for those consumers too, which keeps "no overflow onto other
buildings" true for *placement*, not just for pixels. Being placement-legality-adjacent
(occupancy legality is frozen for its own reasons per CLAUDE.md), that swap gets its own
verification pass — mask parity on an authored tile — not just a visual check.

**Slots and gameplay buildings**: a slot renders in-editor as its lot rectangle + facing
arrow. At runtime the actual building art (InkBuildingGen / compound / plate) draws itself;
the slot only supplies position + angle, preserving the `verts[0]→verts[1] = art +x = road
tangent` contract.

## 6. Runtime integration

Four new sibling nodes in `scenes/main.tscn` (sibling order IS layering — nothing may use
z_index):

- **`AuthoredFarmlandLayer`** just below the runtime `FarmUnderlay` insert point and
  **`AuthoredForestLayer`** at `ForestVisuals`' index — the authored ground, split in two
  so the existing sandwich survives: authored farmland at the bottom, **live** gameplay
  farm fields (`FarmUnderlay`) above it, authored canopy above those. A farm built beside
  an authored wood still tucks its field under the canopy edge.
- **`AuthoredFabricLayer`** at `UrbanFabricVisuals`' index (so rivers, buildings, roads draw
  over it, matching procedural fabric): draws the baked fabric textures (decor + parks).
- **`AuthoredRoadLayer`** at `RoadNetworkVisuals`' index (roads draw above buildings today;
  keep that): draws the per-tile base textures, and toggles the per-tile **unlock overlays**
  and **connector patches** (§7) by flag state. A live-vector path over the same document
  remains as the editor preview and a debug-terminal fallback for verifying bake fidelity.

Both are midcentury-gated like `UrbanFabricVisuals`, no-ops when the document is empty, and
listen to `MapStyle.style_changed`.

**Unlockable roads — plug into the shipped seam.** The engine already reveals baked roads
per tile: visibility = tile's `infrastructure_present` contains `"roads"`
(`road_network_visuals._flagged_tiles` / `_clip_to_built` / `_all_tiles_flagged`), and
`world_map.tutorial_install_infrastructure()` already demonstrates flag-flip + forced
repaint. The authored rule is the whole-stroke AND-gate from §3: when tile B gains roads,
B's unlock overlay **and** every A↔B connector whose other tiles are already flagged appear
together — the new streets join the neighbour's network in one reveal, with no pre-existing
stub at the seam. Two small engine changes:

1. a `tile_infrastructure_changed(tile_id)` signal emitted from
   `_apply_built_infrastructure` (today a flag flip repaints only by side effect —
   the tutorial pokes the node manually);
2. `AuthoredRoadLayer` re-evaluates, on that signal, every overlay/connector whose tile set
   contains the changed tile. Optional polish: a short fade-in (today's clip-flip pops in;
   the 3 s grow animation only serves RoadWorks orders).

**Suppression: authored tiles stand down the procedural systems.** Keyed off the settlement
`tiles` set, checked via `AuthoredMap.covers(tile)`:

| system | change |
|---|---|
| `UrbanFabricVisuals` | skip components whose tiles are authored (whole-component skip first; per-tile subtraction only if a settlement is ever part-authored) |
| `ForestVisuals` + disc consumers | suppress procedural discs inside authored forest polygons (owner ruling); the authored polygon feeds the buildable-mask carve and road-bake declamp in their place (legality-adjacent — own verification pass, §5) |
| `RoadNetworkVisuals` | drop baked-edge runs on authored tiles (inverse of `_clip_to_built`, same point-walk over `edge.tiles`) |
| `AccommodationSitePlanner` | skip authored tiles — slots supersede reserved plots |
| `RoadWorks.enqueue_for_tile` | when the bought tile is authored, skip the A* connect + densify **geometry** jobs (the flag flip still happens; unlockable strokes are the reveal). Otherwise procedural stubs grow beside hand-drawn roads |
| `BuildingVisuals._ensure_block_template` | consult authored slots first (below) |
| audits (`density_audit`, `road_frontage_audit`) | exempt authored tiles from procedural floors; the editor lints + water audit are the quality bar there |
| hard-coded landmines | `urban_fabric_visuals` Capital 7-tile `assert`s, `HERO_ARIN_TILES`, the `e:1166` Vandel fringe route, `SettlementPlanBuilder`'s literal Capital/Silkstown coordinates — each gets an `AuthoredMap.covers()` guard so authoring those areas can't crash a debug build or leave ghosts |

**Slots.** `_ensure_block_template(tile_id, coord)` first asks `AuthoredMap` for the tile's
pins+frames and synthesizes the **exact existing template shape** (`{lots, lot_angles,
claimed, origin, tangent, …}`) — `_claim_slot`, lot consumption, `relayout_tile`'s
free-all-and-reclaim, and the removal path then work unchanged (measured: `_claim_slot` is
~free; it's the search around it that costs). Assignment must be load-stable, so slot choice
is **content-hash keyed** (`RoadHash.pick("slot|<tile>|<instance_id>")` ranked over free
lots), not claim-order keyed — no save-schema change, verifiable with the existing
`LAYOUT_DUMP` byte-diff harness. Slot choice filters by the building's size class
(large = farm/forest polygons; medium; small — §3) across the tile's pins and frame lots,
and falls back to the next class up. When every slot is taken, the next stage — **owner
rule, 2026-08-16 — is to evict a decorative building**: among the tile's masses **marked
`sacrificial` in the editor** (§4 — eviction is opt-in per mass; unmarked masses are
untouchable), pick the best fit (area-ratio fit, `RoadHash` tie-break, computed over the
*set* of overflowing buildings sorted by instance id so load order cannot change the
outcome), remove it, and place the gameplay building at its position and facing. No
sacrificial mass left → fall through to today's procedural search (never a lost building).
Eviction mirrors what the procedural fabric already does implicitly — its sanitizer
deletes any decorative mass a gameplay footprint overlaps — but here it is chosen,
bounded, and visible: the town makes room exactly where the designer said it may. Opt-in
marking also picks the mechanism: the sacrificial set is small and known at export, so
**each sacrificial mass bakes as its own small overlay sprite** (same painter →
pixel-identical; drawn over the base until evicted, then hidden — the unlock-overlay
pattern again), and no runtime rebake is needed. Runtime tile rebake through the shipped
painter stays as the fallback mechanism — proven viable by the hills far-zoom runtime
bake — if sprite compositing ever shows a seam (a sacrificial mass whose SE shadow
overlaps a neighbour; the editor lints that case). A farm
or forest landing in a large polygon takes the polygon as its footprint, filled by the
existing field/woodland bake. **Slots are empty in the editor by
design and accept whoever arrives**: game-start placements (`start_buildings.json`, NPC
production — NPC ports keep their coastal `MidcenturyPortPlan` compound) and mid-game
construction by NPCs or the player, all of which already flow through the same
`_place_building` pipeline. This also deletes ~31 ms of the ~36 ms per-placement load cost
on authored tiles — the single biggest remaining loading lever.

**Untouched, by design**: `roads_baked.json` and `world_map._apply_baked_road_flags()` (the
flag/economy source — corridor flags stay exactly as they are), `RoadNetwork` and its
two-tier plumbing (authored strokes never enter the network, so the 3-width classes need no
`trunk/local` surgery), transport/`transport_service.gd`, save schema, classic/ink/plate
styles (they keep procedural visuals everywhere).

## 7. Bake & export

The bake is a derived artifact; **the JSON is the source of truth**. Export runs from the
editor (windowed — headless never draws) and follows `hill_visuals._bake_to_texture` +
`HillPainter`: per texture, a `SubViewport` (`transparent_bg`, `UPDATE_ONCE`), painter with
`Transform2D(Vector2(s,0), Vector2(0,s), -origin*s)`, `await process_frame` +
`frame_post_draw` (`force_draw()` loop if occluded), `get_image()` → PNG.

**Bake unit: one texture per tile.** The hex *bboxes* (540 wide at 405 pitch) overlap
neighbouring columns by 135 u, so the partition is the **pitch rect** — 405×480 u, the rect
that owns each tile's centre (odd columns offset +240 like the grid itself). Pitch rects
tile the plane exactly; every rect renders the same global geometry clipped at its edges,
so reassembly is pixel-exact and a stroke crossing a seam recomposes seamlessly.
`BAKE_SCALE = 4/3 px/u` — integer texel rects (**540×640 px per tile**), comfortably above
the ~1.107 px/u max play zoom. Unlike `HillPainter` (which deliberately keeps hairlines in
texture px), the authored painter scales **all** widths by the bake scale so the texture
matches the editor preview exactly.

**Four artifact kinds**, so the entire authored look ships baked:

- **base** (all layers — farmland, forest, fabric, roads): always-visible content on the
  tile rect;
- **unlock overlay** (roads layer): the tile's unlockable internal streets — toggled by the
  tile's own flag;
- **connector patches** (roads layer): cross-tile unlockable strokes, each baked to its own
  integer-texel bounds rect, toggled by its all-tiles-flagged condition;
- **sacrificial overlays** (fabric layer): each mass marked sacrificial bakes as its own
  small sprite (the base excludes it), drawn until evicted in-game (§6).

Other properties:

- **Output**: `assets/authored_map/{farmland,forest,fabric,roads}/tile_<q>_<r>[.unlock].png`,
  `assets/authored_map/roads/connector_<id>.png`,
  `assets/authored_map/fabric/sacrificial_<id>.png` + a `data/map_authored_bake.json` manifest
  (`bake_scale`, per-texture world rects, connector tile sets, md5 of the source JSON,
  `hills_hash`) — the `roads_baked` staleness idiom, warning at boot when the bake trails
  the document.
- **Incremental by construction**: an edit rebakes only the tiles/connectors whose rects it
  intersects — editing one settlement re-exports a handful of 540×640 textures, not a
  region. The same granularity is the runtime cache/stream unit.
- **Streaming**: near textures load for tiles intersecting the camera rect grown one ring,
  LRU-freed beyond; the import pipeline supplies VRAM compression (≈4:1) + mipmaps. A tile
  texture is ~1.4 MB raw / ~350 KB compressed, so the resident set at play zooms is tens of
  MB even on dense screens. Phase 4 v1 may load eagerly on desktop; streaming lands before
  the web/itch build.
- **Far zoom: fabric generalizes, roads stay faithful.** Both in-repo precedents run
  **two** styled states: hills = crisp vector meshes near / one 4096-long-side baked
  texture far; the midcentury fabric = full fabric / muted far plates below
  `FAR_PLATE_ZOOM = 0.28`. Faithful minification of *mass detail* turns to noise at
  0.14–0.28 px/u, so the **fabric/parks** far state **generalizes** the way the far plate
  already does: mass unions → settlement plates in `FAR_URBAN_PLATE`, parks merged or
  dropped. **Roads are exempt by ruling (§2): zoom-invariant** — their far texture renders
  the true geometry at true widths (major 18 u ≈ 5.3 px, mid ≈ 3.7, minor ≈ 1.9 at far
  scale: thinner on screen, never restyled). The bake emits **one whole-map far texture per
  layer** (4096 long side ≈ 0.295 px/u — native resolution right at the swap point),
  through the same painter (fabric with a far style table, roads/ground faithful), swapped
  at the existing 0.28 threshold so authored and procedural areas flip together. Roads
  unlocked mid-game draw over the static far texture as faithful thin vectors. A third
  mid-zoom variant is deliberately deferred: the pipeline makes adding one cheap if the
  near↔far transition pops in testing.
- Bake determinism: two consecutive exports must be byte-identical (`md5` the PNGs — the
  `bake_roads` precedent). Parchment stays live at z=90 (it multiplies the whole plate), so
  the bake contains no parchment — never bake from screenshots.
- Repo: commit the PNGs (solo dev, simple, `--headless --import` handles reimport; flat-art
  PNGs compress well). Revisit with gitignore+bake-on-pull if rebake churn ever bloats
  history.

## 8. Phases

Each phase ends green: unit suite + e2e unchanged with an **empty document** (the whole
feature is opt-in, like midcentury itself), plus the phase's own gates.

- **P0 — Foundations.** Merge `gauntlet4/form-geometry`; `AuthoredMap` loader + schema +
  round-trip tests; editor shell (boot, camera, overlays, save/load, undo); the cheat →
  main-menu → editor launch path; export exclusions + the shipped-code reference guard.
  *Gate: editor opens from the menu after `debug CandC`, draws nothing, suite green, and
  no shipped script references the excluded paths.*
- **P1 — Roads. ✅ BUILT.** Pen tool (click = corner, drag = curve handles), 3 classes at
  18/12.6/6.3 u, per-class curated style table (`authored_road_style.gd` — the values the
  owner rules on), seeded wobble, junction snapping, unlockable tagging from touched-tile
  sets, auto bridge decks at river crossings, water lint. `AuthoredRoadVisuals` (vector),
  suppression in `RoadNetworkVisuals` + `RoadWorks`, the `tile_infrastructure_changed`
  signal. *Gate MET, measured by `tools/map_editor/authored_unlock_check.tscn`: before the
  purchase only the always-on stroke draws and the connector is absent entirely (no stub);
  after it, the street and the connector appear together — verified as stroke-id lists AND
  as a 466-pixel change in the rendered frame. Suite 2671/0, e2e 748/0 with no document.*
  **Still owed: the per-class curation pass with the owner on real tiles (§10.1) — the
  table ships with defended defaults, not a ruling.**
- **P2 — Fabric & ground.** Stamp tool (17 forms + params + reroll), parks, **farm/forest
  polygon tool** (≤8 vertices, generated fills, building-overlap lints), shared mass
  painter, fabric + forest suppression, audit exemption, **import-existing command**
  (procedural masses/parks/farm+forest layout of a chosen settlement → editable
  stamps/polygons; baked edges → strokes with tier→class mapping and unlockable inferred
  from flag state) so authoring starts from today's map, not a blank page. Cherry-picks
  `tree_shapes.gd` from `road-density` for the tree scatter. *Gates: a settlement
  authored-over reads identically until edited; no tree crown or shadow crosses its
  polygon; forest mask/declamp parity verified on an authored tile.*
- **P3 — Slots.** Pin + frame + large-polygon tools, the **auto-derived size-class table**
  (catalog × generator frames, max-level extents, owner-reviewable overrides), template
  synthesis into `_ensure_block_template`, class-aware hash-keyed assignment, accommodation
  handoff. *Gates: `LAYOUT_DUMP` byte-identical across save/load; every catalog building
  maps to a class and lands in a correctly sized slot in a test bake; overflow past all
  slots evicts a sacrificial decor mass deterministically (byte-stable across save/load),
  the building takes its place, and the chain falls through cleanly when nothing is
  marked; placement time on an authored tile measurably down;
  buildings still claim/free slots through construction/demolition/relayout.*
- **P4 — Bake.** Per-tile export (base / unlock overlay / connector patches), the
  generalized far texture per layer, manifest + staleness, runtime display + streaming,
  import/mipmap settings, determinism md5 gate, VRAM + load-time measurement. *Gates:
  authored settlement renders from textures and the unlock flow works fully baked; toggling
  the debug vector fallback is visually identical at full zoom; near↔far swap at 0.28
  doesn't pop objectionably.*
- **P5 — Pilot: Capital.** Author the owner's #1 settlement with the full loop
  (edit → `tile_shot` → blind critique vs procedural control per
  `hero-loop-stopping-criteria.md`), then roll the queue (Arin, Stoneshore, …).

## 9. Key seams (verified 2026-08-16)

| seam | where |
|---|---|
| flag-clip reveal (the unlockable mechanism) | `road_network_visuals.gd` `_flagged_tiles` / `_all_tiles_flagged` / `_clip_to_built`; `world_map.gd` `tutorial_install_infrastructure` (flag-flip + forced repaint precedent), `_apply_built_infrastructure`, `_apply_baked_road_flags` |
| road ink styling to reuse | `road_network_visuals.gd` `_draw_runs_ink` / `_wobble_polyline` / `_ink_cache`; widths+wobble in `map_style.gd:645-705` / `map_midcentury_style.gd` |
| slot template contract | `building_visuals.gd` `_ensure_block_template` (template dict shape), `_claim_slot`, `relayout_tile`, `footprint_center_for`; art anchor = `verts[0]→[1]` tangent |
| bake recipe | `hill_visuals.gd` `_bake_to_texture` / `HillPainter` (transform, frame handshake, world-rect display); `tools/map_style_shot.gd` capture-staleness pattern |
| coordinates | `hex_map.gd` (`map_to_local`, `map_world_rect` `(0,0,13905,11760)`, odd-q, ids `tile_{q+1}_{r+1}`) ; camera px/u truth in `camera_controller.gd::_configure_for_map` |
| procedural systems to suppress | `urban_fabric_visuals.gd` (component build + Capital asserts + `HERO_ARIN_TILES` + `e:1166`), `accommodation_site_planner.gd`, `road_works.gd::enqueue_for_tile`, `settlement_plan_builder.gd` |
| loaders to imitate | `roads_baked.gd` (cache + staleness), `tools/bake_roads.gd` (write + determinism) |

## 10. Decision status before building

**Settled by owner rulings (2026-08-16):** hand-author all tiles; per-tile bakes; the
connection-rule unlockables; zoom-invariant roads; midcentury-derived road treatment;
slot size classes; opt-in sacrificial eviction; drag-drop + 2 u road snap; editor lives in
the game project and is export-excluded (§4).

**Ruled in-phase, inside the editor — scheduled, not blockers:** per-class road curation
values + width sign-off at true full zoom (P1); the slot-class table review (P3); the
fabric/parks far-style table on Capital's first far bake (P4).

**Parked:** procedural wiring of the 13 forms — a migration-era stopgap at most given
all-tiles authoring; revisit only if unauthored tiles jar beside authored ones.

**Also settled 2026-08-16 (the last two pre-build rulings):**

- **Hero-rule amended, not waived.** `hero-loop-stopping-criteria.md` banned fixed
  coordinates so authored fabric would survive a later roads redesign — a risk that existed
  precisely because road layout was generated independently of the fabric. In the editor
  the two are one document, drawn together and exported together, so a road cannot move
  without its settlement moving with it; the owner's words: *"with hand authored the two
  will finally be in sync for the first time since the project started."* Fixed coordinates
  are legal in `data/map_authored.json` and road-perturbation fixtures are not required on
  authored tiles. The amendment is written into that doc's robustness section; the rule
  stands for procedural tiles, and tile identity still resolves through `id_to_coord`
  everywhere.
- **Forests: individual trees, clipped, discs suppressed** — see §5.

**Nothing is blocking. P0 can start.**
