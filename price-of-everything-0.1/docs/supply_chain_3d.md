# Supply-chain 3D overview

Branch `codex/supply-chain-3d` starts at PR #197 (`6266b19a`) and merges the
supply-chain work in PR #196 (`86cb0e02`). The regular map remains unchanged.

The company overview uses an isolated World3D and an orthographic orbit camera.
The existing board model and smooth height field remain authoritative. Its 53
building meshes come from the original Blender sprite builders. Buildings still
open their supply-chain graphs; terrain clicks open the existing tile panel.

## Controls

- Left drag / two-finger trackpad pan: pan.
- Middle drag, or hold `0` while panning with two fingers: rotate and tilt around the camera centre. Right drag also remains available.
- Mouse wheel / trackpad pinch: zoom around the terrain under the pointer.
- Q/E: rotate. Home / Reset view: frame the current coverage. The corner rotation arrows have been removed.
- Click terrain or a warehouse: select its tile; Shift-click selects through buildings.
- Click a building: open its network once its projected width **and** height exceed 20 logical screen pixels. Smaller player/NPC buildings select their tile instead. The outermost continent view always selects tiles. Eligible hitboxes follow the visible mesh with a two-world-unit edge tolerance; empty space around the building selects the tile. Retina scaling does not change the threshold. Tab returns to the regular map.
- Visibility → **Show player owned tiles only** (default) / **Show all tiles**. This preference is saved in the player profile. Owned coverage includes company routes, goods and purchased empty land; all coverage includes every real terrain tile, without inventing stockpiles or player buildings.
- The maximum camera span is 28,000 units. The 600-tile test continent fits within it, exceeding the requested 50-tile minimum.

Tile selection also forwards active construction and destination-selection actions.
The motion key pauses moving goods and shows outputs above their producers.

## Matching the original artwork

Terrain colours are now painted from the original contour polygons into **plan-space**
textures. The camera is not part of a bake, so orbiting never changes or rebakes the
artwork. All tiers retain the original layered beaches, wet sand, foam, lake edges
and riverbanks, plus subtle deterministic vegetation marks and water strokes.
Smooth vertex normals follow the shared spline. The cutaway uses the original
printed strata texture rather than four solid colour bands.

The ground shader reproduces the source slope shading and warm-sun/cool-shade grade.
Building paint keeps the source palette, object-anchored stippling and restrained
world-space face lighting. The source rig is mostly ambient: applying a second strong
blue directional shadow changed the balance of its already-graded colours.

The mesh export now preserves the original Freestyle rules from `sprite_kit.py` and
`housing.py`: 2.4px ordinary ink and 1.05px fine ink at the source render resolution,
with marked painted windows, doors, tower spandrels and silver mullions excluded.
Stroke widths travel with the mesh in model units and shrink with zoom, including
antialiased subpixel coverage. They no longer remain 1.6 screen pixels thick. Pale
materials are no longer repainted navy, and glass has no extra darkening multiplier.
Painted window quads render from both sides, as they did in Blender. Separate
feathered ground shadows match the source board's illustrated grounding. The sprite exporter disabling cast shadows does **not** mean
the original board lacked shadows: it drew them as a separate layer.

Decorative house and tower meshes follow the exact sprite variety chosen by the
model, rather than the footprint-sizing level. Windows and inexpensive additive
lamp/yard glows light polluted districts. Glass towers light individual panes rather
than their whole facade. Foundations are added where ground is uneven. Cream goods
tokens with navy borders and the old label plates are restored.

The 3D viewport follows physical screen resolution, with 4× MSAA. Projection/picking
converts between physical viewport pixels and logical UI coordinates. Lighting is
an illustrated approximation of the original Blender/AgX/Freestyle rendering, not a
pixel-identical transfer of the sprites. Some source models still have simpler rear
faces (for example, the glass tower's mullion grid is authored on two walls).

Roads port the original `_capsule`, `_road_widths`, colour bands, level-specific lane
markings and junction clearance. Bands overlap by colour across the whole network,
with one shared triangulated height field (3-unit company / 6-unit continent spacing), so raised kerbs cannot slice through
an adjoining road on a slope. Geometry is batched per tile for culling. It adds roughly
109k primitives in the far company framing; the source widths and joins are retained at every LOD. The old 3D
rectangular strips and separate kerb lines are removed.

Mines omit the source builder's cut-pass earth block and shaft section, and use its
actual rim polygon and ground datum. All three terrain LODs and their colliders have
excavated openings. The first inner wall joins the graded terrain to the submerged
benches; the original two ragged rings of worked earth surround the pit. This small
local grading prevents hillsides cutting through benches or leaving machinery afloat.
Mines receive neither a building plinth nor a whole-building ground shadow. Their
collision volumes support both building clicks and Shift-click tile selection.
Changes to mine placement/level invalidate the affected terrain cache entries.

## Three detail levels

LOD is selected from logical screen pixels per world unit, with hysteresis so a slow
pinch near a threshold does not flicker between tiers. Company coverage keeps all three terrain tiers in memory. Continent coverage uses one
shared world-space atlas and a combined far mesh, then refines visible tiles progressively
as the camera approaches. Both modes reuse disk bakes between game processes.

| Tier | Typical span at 1080px height | Ground mesh spacing | Terrain artwork width | Detail |
| --- | --- | --- | --- | --- |
| Far (company) | Above ~1420 units | 12 units | 512px + mipmaps | Accurate contours/beaches, textured strata, denser rounded trees and bushes, roads, lamps, buildings, shadows and tokens |
| Medium | ~675–1420 units | 8 units | 1024px + mipmaps | Finer slopes, canopy lobes and branches, railway sleepers, increased building mesh detail |
| Near | Below ~675 units | 4 units | 2048px + mipmaps | Fine slope geometry, ground tufts and stones, highest building detail |

The far tier's surface paint has roughly 512 samples across a tile, versus about 45
triangle-colour samples in the first 3D pass. It also has up to 84 tree candidates per
tile versus 26, with placement excluding buildings, streets and riverbanks. All tiers
use the same deterministic positions. Medium and near add details to those positions.
Imported glTF LODs handle building meshes; tier-specific biases preserve more geometry
as the view approaches. Continent terrain colliders follow the currently displayed mesh.
The continent base uses 24-unit geometry and one 6144px atlas across the map. Below
0.27 logical pixels per world unit, its joined far geometry replaces per-tile rendering;
above 0.33, independent tiles return. The separate thresholds prevent flicker.
Fine ground decoration is intentionally sparse: warm stones appear only on exposed
slopes, with fewer grass marks, rather than grey specks across every flat tile.

## Performance and limits

Geometry is frustum-culled by Godot. Ground, vegetation and infrastructure details are
batched; lighting accents use shared materials and glow cards instead of an individual
real-time light for every lamp. The viewport and processing stop when the board is hidden.
Unchanged models retain their scene. Obsolete terrain cache entries are released on
rebuild, including tiles no longer in the company and old height fields. The shared
continent base survives a coverage switch within the same map; its finer tiers do not.

Three complete terrain texture tiers for the eight-tile Metal Magnate company retain
approximately **199.5 MiB** including mipmaps. Keeping them resident avoids decode/upload
work while zooming. At outermost continent zoom, one compressed bake contains a shared
6144px world-space atlas, joined terrain, roads, canopy/settlement masses and cutaway
edges. It remains genuinely 3D and rotatable. Per-tile collision geometry is retained
for tile selection; the far artwork is not rendered or baked as 600 independent images.
At closer zoom, tiles share the atlas as a fallback while at most 24 nearby tiles retain
1024px/8-unit or 2048px/4-unit bakes. Offscreen fine meshes, collision shapes and textures
are released from memory, and can be loaded again from disk.

The 600-tile atlas retains about 154 MiB including mipmaps; the measured medium/near
views retain about 268/510 MiB of terrain textures. Worst-case atlas plus both fine tiers
on 24 tiles is about 724 MiB. These figures exclude building assets, meshes, collision
data and the regular map. Switching to company coverage can retain the shared atlas;
switching back reuses one atlas rather than keeping a duplicate for every coverage swap.

Bakes are persisted under `user://supply_chain_3d_bakes/` as compressed `.res` resources.
The far map is one `continent-<hash>.res`; closer terrain is `tile-<hash>.res` per tile
and detail level. Company-mode road geometry is cached too. Keys include generator
source fingerprints, actual geography, palette, local mine cuts and relevant layout;
they contain no scene instance IDs, camera angles or display-density values. Changed
inputs invalidate the corresponding bakes. Writes use a temporary file and rename.
A periodic trim targets 2 GiB of runtime disk storage; optional packaged bakes in
`res://assets/supply_chain_3d/bakes/` are read-only. Headless tests never populate the
production cache with their placeholder artwork.

At very wide framing, trees become batched tiny multi-angle sprites, decorative settlements
use grouped masses, roads soften, and tiny traffic, lamps and water glints disappear.
City labels are limited and spaced to avoid obscuring the terrain. Nearby tiles restore
the source trees and buildings. Paint bleeds into texture gutters to prevent pale tile
seams. Roads and river crossings use spatial lookups instead of scanning the whole
network for every mesh vertex.

Initial terrain and road generation is paced with visible progress. Cache hits skip
texture painting and terrain/road tessellation. Loading/decompressing resources, building
colliders, and recreating live buildings, vegetation and goods still take time; this is
not an instant-loading whole-world scene snapshot. Incremental scene updates and lazy
creation of nearby live detail would be the next performance work.

Rendered measurements: Godot 4.6.2, OpenGL compatibility, Apple M5 Pro, 1920×1080,
eight tiles / 38 standing objects. After 60 forced-draw warm-up frames, 45 frame samples:

| Tier | Median frame interval | p95 | Frame draw calls | Primitives |
| --- | --- | --- | --- | --- |
| Far | 4.67 ms | 5.65 ms | 389 | 271,931 |
| Medium | 4.44 ms | 5.00 ms | 386 | 369,208 |
| Near | 4.00 ms | 4.75 ms | 303 | 353,553 |

These are local end-to-end frame intervals with forced draws, including HUD work, not
isolated GPU timings or a full-map benchmark. Across these revision captures, medians
varied from about 4.0 to 6.8ms and p95 reached 14.3ms; OS/window scheduling affects
forced-draw intervals, so the lower final numbers do not establish a GPU speed-up.
Near framing culls more tiles, hence fewer draw calls. Initial cold captures included ~150ms spikes; those are not hidden by the
steady-state figures. The engine's total texture monitor also includes the main game's
prewarmed sprites and regular-map assets, so it is not the supply-chain cache size.

With persistent bakes, the current 600-tile map took about **41–45 seconds cold** and
**22–24 seconds from disk** to open from company coverage. A fresh process reused the
continent resource and 39 tile-detail reads, with **zero writes**. Two consecutive
cached runs exited successfully after using normal reuse for immutable resources.
The final 3D viewport measured **88 visible draw calls** at continent framing, about
510 at medium and 192 near. These counters exclude the HUD and are taken after forced
draws; the historical global draw-call figures below use a different scope.

The far resource combines the static atlas and meshes; interactive buildings and goods
remain live. Cache inputs include pipeline/tree clearances and the full mine grading
reach, so edits cannot keep stale canopies or neighbouring terrain. The Sol reviewer
found no material loss of coastline, shading or detail against the previous approved
three LODs. Final captures use the `baked_continent_` prefix; cache keys, compressed
size and raw measurements are in `outputs/supply-chain-3d/bake_measurements.json`.


Before persistent bakes, the 600-tile continent was rendered through three Sol-reviewed iterations. Spatial
road/river indexing reduced the first build from 957 seconds to **45 seconds**;
wide-view batching and detail suppression reduced draw calls from **7,070 to 1,891**.
The final 1920×1080 capture (same hardware/renderer) measured:

| Continent framing | Fine tiles resident | Terrain textures | Draw calls | Primitives |
| --- | --- | --- | --- | --- |
| Far, entire continent | 0 | 178 MiB | 1,891 | 3,453,479 |
| Medium, 1,100-unit span | 24 | 292 MiB | 757 | 1,065,692 |
| Near, 560-unit span | 15 | 534 MiB | 423 | 888,792 |

Sixty process-frame samples after streaming settled gave approximately 6.9ms median
and 7.1–7.5ms p95. These include desktop scheduling/vsync and are **not isolated GPU
measurements**, nor directly comparable to the earlier forced-draw company benchmark.
Performance on lower-end hardware is unmeasured. High-detail streaming can still
introduce short generation/upload hitches during travel; first generation is not instant.

The reviewer approved the final three LODs as a coherent in-game map. The stepped
outer ocean border and subdued distant city silhouettes remain candidates for future
marketing-art work. Captures and measurement methodology are in
`outputs/supply-chain-3d/continent_{far,medium,near}.png` and
`outputs/supply-chain-3d/continent_measurements.json` at repo root.

## Verification and captures

- Map, goods-view and 3D regression: **2,390 checks passed**, 246 tests, no script errors.
- Includes **84 3D checks** covering coverage without invented assets, screen-space LOD
  hysteresis, release of streamed terrain, silhouette picking, high-DPI input,
  source trees/ink, joined roads at both mesh spacings and all mine levels/LODs,
  the 20px threshold, shared continent rendering and persistent bake invalidation.
- Complete parse sweep: **782 scripts, 0 failures**, 47 excluded by the existing checker.
- Windowed continent run: all 600 tiles present and visible at maximum zoom,
  unowned-tile picking succeeded, and owned coverage restored its original eight tiles.
- Rendered New Game → Begin → supply chain, routed mouse orbit, routed trackpad pinch,
  tile selection, all three LODs, a rotated near view, and the original 2D renderer at
  matched far/medium/near framing. All three mine levels are rendered from opposite
  camera angles on sloping terrain, with 3/3 real picking checks. Captures live in `outputs/supply-chain-3d` at repo root.
- The default New Game start is also covered by the headless loading-path smoke tool.
- Headless logs retain fixture-level missing-node/dummy-texture diagnostics; the parse
  checker also reports its existing live-script reload diagnostic. No script parse
  failures or assertion failures were reported.
- The existing ObjectDB leak warning still appears on exit. Rendered cold generation
  and consecutive cached reloads exited with code 0.

From the game directory:

```sh
python3 tools/run_tests.py --tags goods_views,map,supply_chain_3d --no-telemetry
godot --headless --path . res://tools/parse_check.tscn --quit-after 600 -- --no-telemetry
godot --headless --path . res://tools/supply_chain_3d/new_game_smoke.tscn \
  -- --no-telemetry --start=res://data/starts/default.json
AGENT_GODOT_WINDOW=1 godot --path . --windowed --resolution 1920x1080 \
  res://tools/supply_chain_3d/capture.tscn -- --no-telemetry --detail-review --artwork-review
```

The dummy headless renderer cannot bake viewport images; its tests exercise the same
meshes, lifecycle, picking and LOD policy with placeholder textures. Windowed captures
verify the actual shaders, terrain artwork and token composition.

Whole-continent visual capture and residency/zoom/picking checks:

```sh
AGENT_GODOT_WINDOW=1 godot --path . --windowed --resolution 1920x1080 \
  res://tools/supply_chain_3d/capture.tscn -- --no-telemetry \
  --continent-review --review-tag=continent_review
```

The bake capture reports cache hits/writes and its directory. Run it twice in separate
processes to verify actual disk reuse. Current bake artifacts live in the local runtime
cache; `outputs/supply-chain-3d/bake_measurements.json` records their keys and measurements.
The large binary runtime cache is not committed to the source repository.


## Tiny sprites for the wide far view

Trees and player/NPC buildings now switch to offline colour-and-depth sprites below
0.27 logical pixels per world unit and restore their full meshes above 0.33. This
is the wide end of the far tier, in both company and continent coverage. Medium and
near building artwork, regular-map rendering and selection rules are unchanged.
Decorative houses and towers now use their exact chosen source variant too: five
continent-wide batches retain roof shapes, palette, full tower height and the same
slope-adjusted ground anchor. Foundations remain geometry. Company coverage uses
the same sprite/mesh pairing for its decorative buildings.

Each of the 71 currently available source meshes has 16 azimuth views and five
camera pitches. The shader selects a view as the camera rotates/tilts. Trees use
16×16 cells and buildings 64×64 cells with mipmaps (including transparent margins).
The building cells retain enough samples for a Retina viewport; they are **not**
64-pixel map icons. Their world scale and ground anchor are those of the original
model, with no minimum screen-size enlargement. At 1080 logical pixels high:

| Example | Sprite cutoff | Whole continent (~10,725 span) | Maximum zoom-out (28,000 span) |
| --- | --- | --- | --- |
| Small tree | 6×7 px | 2×2 px | ~1–2 px |
| Fir | 5×9 px | 3×3 px | ~1–2 px |
| Large tree | 9×9 px | 3×3 px | ~1–2 px |
| Warehouse / NPC depot, level 1 | 16×12 px | 7×5 px | 3×3 px |
| Factory, level 3 | 23×20 px | 9×7 px | 4×3 px |
| Furnace, level 3 | 22×21 px | 8×8 px | 3×4 px |

These are measured visible alpha bounds in reference home-view frames, including
filter coverage; actual placement scale, pitch, display density and pixel alignment
can change the final raster footprint. The manifest stores a fixed camera square
and centre per asset so changing viewing angle cannot auto-fit or inflate its scale.
The maps keep the existing source palette, directional face shading and fine ink;
unresolved stippling is reduced. Colour is stored without the map's position grade,
which is applied once at runtime. Captures are converted from premultiplied to
straight alpha to prevent dark foliage fringes. Single-channel depth reconstructs
surface occlusion against slopes and mine holes. Angle selection is discrete at
22.5-degree intervals; these sprites intentionally only appear at tiny screen sizes.

Continent tree transforms are stored in its single persistent bake and rendered in
three MultiMeshes, one per species. Each tree or building becomes a two-triangle
card. Company coverage groups its trees per tile. The packaged sprite set totals
about 16.8 MiB of PNGs; only used atlas materials are loaded by the runtime. Existing
player/NPC model/collider creation still happens during board construction. On a
cached continent open, decorative meshes, detailed trees and per-tile base geometry
are deferred until the first closer zoom. Layout construction is still on the initial
path, so this does **not** yet meet the proposed sub-five-second startup target.

Rebuild and review from the game project directory:

```sh
AGENT_GODOT_WINDOW=1 godot --windowed res://tools/supply_chain_3d/bake_far_sprites.tscn
godot --headless --editor --import --quit
AGENT_GODOT_WINDOW=1 godot --windowed res://tools/supply_chain_3d/review_far_sprites.tscn
python3 tools/supply_chain_3d/far_sprite_sheet.py
```

The offline baker uses the existing editable source meshes and shaders; it does not
redesign them. `assets/supply_chain_3d/far_sprites/manifest.json` records their hashes.
The review emits comparisons at low/home/high pitch, real-size PNGs for three wide
zoom scales, a proportion sheet, and measurements under
`outputs/supply-chain-3d/far-sprites/` at the repository root.

The background capture tool drains deferred rendered-frame callbacks and frees its
disposable game before quitting. This avoids a native shutdown failure observed
when a pending image/coroutine survived into engine teardown; no regular-map or
normal gameplay shutdown code is changed by this capture-tool fix.


## Decorative scenery, static shadows and split bakes (2026-10-10)

Static tree and decorative-building contact shadows are painted into the terrain
artwork in map space. `shadow_art.gd` uses the source north-west direction, 0.17
maximum opacity and a feathered edge. The same footprint records feed the single
continent atlas and each finer tile texture; records crossing a tile boundary are
included in both painters. Switching tree representations no longer hides their
shadows. Static shadows do not also allocate ground-shadow geometry. Live player/NPC
building shadows remain separate so their artwork can update with gameplay.

The persistent format is schema 2:

- `scenery-*.res`: source variants, standing transforms, tree placements, shadow
  footprints by tile and the colour-grade range. No full mesh or sprite-texture
  resources are referenced by these placement records.
- `continent-*.res`: one atlas, joined terrain/roads/edge meshes, tree and decorative
  sprite transforms, camera bounds, labels and tile metadata. `tile_chunks` maps
  tile IDs to **string keys**, not Resource references. The old duplicate `parts`
  and `roads` dictionaries are absent.
- `base-tile-*.res`: a separately loadable coarse terrain/road/edge resource per tile.
- `tile-*.res`: existing medium/near terrain and artwork, now including static
  shadows in both the image and the content key.

A warm far open reads scenery metadata plus one continent resource. It uses one
joined terrain collider and resolves the tile from the map-space hit, preserving
far tile-only selection without constructing 600 per-tile colliders. Decorative
objects remain non-playable. Fine building selection still uses the existing
20-by-20 logical-pixel gate after detail is ready.

The first closer zoom loads base-tile resources and constructs detailed scenery
behind the still-visible far map, then switches when ready. **This first closer
preparation still constructs the whole base scene**; complete prop-chunk residency
is the next streaming step. The existing 24-tile budget applies to medium/near
terrain, not all props. Obsolete tile caches are released on coverage changes;
loading callbacks cannot retain the builder indefinitely if the user stays far out.
Missing tile resources can regenerate and persist locally without invalidating the
far resource. Road layout and surface geometry were not changed.

Cache fingerprints are separated by layer. Relevant source files are hashed and
`BakeCache.REVISIONS` must be bumped when a change in `world_builder.gd` alters a
layer's generated data. Runtime-only loading/visibility edits no longer invalidate
all artwork. Static shadow changes invalidate affected tile images. Sprite-atlas
changes invalidate the far composition but not unrelated fine terrain. Batched
base-tile writes defer cache trimming until the far root is durable; other writes
retain the 2 GiB trimming policy.

The final isolated cached validation opened in 9,513 ms (previous captured version:
23,547 ms), with zero detail chunks/base tiles opened initially and zero cache
writes during the full far/medium/near review. The compressed far root decreased
from 70.94 MiB to 46.95 MiB. The atlas still occupies approximately 154 MiB;
separating geometry does not reduce that texture allocation. Measurements exclude
main-game startup. The final run rendered all three LODs, verified tile picking and
coverage switching, and then reviewed sprites against full meshes at two yaw angles
and the lowest/highest permitted camera pitches. All 1,244 headless checks passed.

Validation and images live at repository-root
`outputs/supply-chain-3d/decor-shadow-cache/`. Reproduce the full cache, picking,
coverage and angle review with:

```sh
AGENT_GODOT_WINDOW=1 godot --windowed res://tools/supply_chain_3d/review_far_decor.tscn -- --continent-review --review-tag=far_decor_final
python3 tools/run_tests.py --tags supply_chain_3d
```

### Continent tree contrast and mountain relief

At whole-continent scale, tree sprite colours blend 55% towards a muted olive
green. This reduces the dark silhouette/outline contrast without thinning forests,
changing tree scale, altering their depth, or moving baked contact shadows. The
blend falls smoothly from full strength at 0.10 logical pixels per map unit to zero
at 0.27, before the existing mesh handover. Company-only coverage and buildings
keep their original colours. This is a material adjustment and does not require
regenerating sprite atlases or add draw calls.

The 3D-only `relief.gd` doubles the spacing of upper elevation bands, beginning
with the rise from map height 4 to height 5. The continuous transform is
`h + max(0, h - 77)`: source levels 5/6/10 (88/99/143 world units) become
99/121/209. Sea and levels through 4 are unchanged; there is no sudden vertical
step at the threshold. Terrain normals use the matching slope multiplier. All
terrain LODs, selection meshes, props, bridge/cable elevations and submerged mine
datums use this display height, without changing the shared source height field
or the regular map. Road routes are unchanged.

The relief helper is included in the terrain fingerprint, so both the joined
continent and its per-tile resources invalidate together. Existing geometry bakes
must regenerate once. Reproduce the three-LOD, tree contrast and mountain review:

```sh
AGENT_GODOT_WINDOW=1 godot --windowed res://tools/supply_chain_3d/review_relief.tscn -- --continent-review --review-tag=continent_relief
```

Matched tree contrast and summit views are saved under repository-root
`outputs/supply-chain-3d/continent-relief/`; the standard three LOD screenshots
and measurements use `/private/tmp/continent_relief_*`.

Validation: 1,258 checks across 135 tests passed. The rendered review checked
far/medium/near, tile picking, coverage switches and two mountain viewing angles;
the sampled highest source point moved from 132 to 187 world units. Far rendering
still uses 61 draw calls and 3,085,264 primitives. The affected continent and tile
caches were rebuilt; the review subsequently reopened the new cached continent.


## Progressive relief and local medium loading (10 October 2026)

The progressive preview is now the live 3D profile: elevations L4–L10 are
77, 99, 132, 176, 231, 297, 374. The source map remains unchanged. Terrain,
placement, normals and picking share this transform; affected bakes were rebuilt.

Closer zoom no longer creates all 600 tiles of detailed scenery. Visible tiles
and a screen-space buffer stream into a bounded working set (96 base tiles,
24 fine terrain tiles). A hex occupancy mask removes the corresponding parts of
the complete far backdrop. Local nodes, metadata and resource references leave
memory when they leave residency; the far view retains its last local set for
ten seconds after the transition, then releases it even without camera movement.
Camera requests are cancelled at tile boundaries and unchanged views skip
repeated visibility work. Coarse picking is ignored where local terrain replaces it.

There are now 71 medium sprite variants, with 128px building / 64px tree cells,
versus 64px / 16px at far. Exact scale, source palette and depth framing are
preserved. Nearest uses full meshes. Lit-window buildings keep their meshes at
medium to preserve dynamic lighting; medium impostors retain the far system's
16-yaw / five-pitch angle quantisation.

The warm review used 45 base tiles at medium and 16 near. First medium detail:
3.13s; subsequent pan loads: 0.65–1.26s. Far opening still takes 10.01s and needs
separate work to meet the earlier <5s target. Roads remain deferred. The full
warm review reused 271 cached resources with zero writes. All 1,270 checks passed.

See `outputs/supply-chain-3d/progressive-medium-streaming/` at the repository root
for final captures, cold/warm JSON, logs, trade-offs and reproduction commands.
This supersedes the earlier full-continent detail-loading limitation and constant
2× highland profile documented above.


## Two-frame far/medium transition (10 October 2026)

Whole-continent coverage keeps the far map visible while the requested local
view loads. Once ready, two rendered intermediate frames show one-third and
two-thirds local coverage, followed by the full local view. Zoom-out reverses
those fractions. Reversing the zoom mid-transition starts at the current blend.
The frames use complementary opaque pixel coverage, share the existing textures,
and require no new bakes or extra LOD assets. Picking remains tile-only until
local detail is fully shown.

Outgoing local meshes, textures and picking shapes survive both frames and a
ten-second far-view grace period. Returning within that period reuses them;
expiry is checked even if the camera stays still. This retains only the last
bounded working set, not a general continent-wide LRU cache. The residency
texture uploads only when tile membership changes, not when the blend changes.
Cached requests also skip the road spatial-index setup; cache repair still
constructs it lazily. Road layout is unchanged.

Capture with the production builder (no profiler-specific streaming override):

```sh
AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/review_handover.tscn -- --continent-review --no-telemetry
```

The tool records both intermediate frames in each direction, cache reads/writes,
render and transition-update timings, and repeated switches. First-use shader
and texture warm-up and screenshot readback are separate from repeat timings;
two visual transition frames do not imply that an uncached load takes two frames.

Review artifacts: `outputs/supply-chain-3d/two-frame-handover/` at repository root.
On the M5 Pro, final repeated transitions reached their endpoint state in 19–29ms
(23–37ms including its first draw), with no disk reads or writes. One earlier
uncaptured zoom-out still took 544ms, dominated by rendering, while transition
updates cost 0.4–1.4ms. The driver/rendering cause remains unproven; the capture
records this separately instead of treating every cached switch as steady state.
Outgoing medium trees use the same camera-dependent contrast softening as far
trees, avoiding a dark patch during a rapid jump to continent scale.

## Medium scene loading and retained tile resources (10 October 2026)

Production 3D boards now construct source building meshes, contours, full tree
MultiMeshes, grass and stones only on entry to near zoom. Medium uses its colour
and depth sprites throughout, including 64 new lit-window colour variants. Those
variants share the existing depth atlases, framing, world scale and angle choices.
Selectable buildings load a shared offline collision shape made from the source
mesh; medium picking no longer requires importing that render model. Unknown or
missing assets retain the original mesh/box fallback. Near geometry already
created is reused while its tile remains active, and local registrations are
removed when that tile's scene nodes are freed.

The streamed continent now has a per-world resource cache independent of its
live tile nodes. Terrain textures, meshes, road/scenery chunks and terrain picking
shapes survive a pan out of view. Return visits attach the retained resources
instead of decoding disk files and rebuilding collision geometry. Offscreen
scene nodes and their active physics bodies are still released. A rebuild of the
world creates a fresh resource cache, avoiding reuse across changed geography or
scenery. This supersedes the earlier last-view-only retention described above.

The decoded local-resource target is **700 MiB**, shared by medium and any visited
near terrain. It is a soft target: visible tiles, the nearby band and tiles used
within the previous ten seconds cannot be evicted. Under pressure, older eligible
tiles leave first, with distance breaking age ties. Merely reaching ten seconds
does not force an eviction when there is spare capacity. Nearby protection extends
roughly one tile beyond the active viewport buffer and is recomputed on camera
changes. Pressure cleanup also runs while the camera is stationary. Rapid travel
can temporarily exceed the target to honour the ten-second minimum.

Prefetch considers at most eight adjacent candidates, prioritises the direction
of travel and attempts at most two per stationary streaming tick. It reads only
existing base/medium bakes, creates no nodes or physics bodies, and never starts
an invisible rebake. It stops at 80% of the soft target, leaving foreground
headroom. Admission uses the decoded resource estimate; rejected upgrades cannot
mutate an existing cache entry. Active scene attachments share a 4ms work budget
instead of yielding a whole frame after every cached tile. Individual synchronous
loads can exceed that budget; it is not a hard frame-time guarantee.
Camera movement is checked every 50ms; stationary maintenance/prefetch retains
its 250ms interval.

The estimate includes RGBA mip chains, mesh payloads and an allowance for retained
terrain collision faces/BVH. It excludes the common far-continent atlas, shared
building/tree atlases, source models and building picking shapes, node overhead,
driver copies and the rest of the game. Thus 700 MiB is not a total process-memory
cap. The new lit PNGs add about 31 MiB on disk, and compressed picking resources
about 5.8 MiB. Only requested variants are loaded; each resident 2048×640 lit
colour atlas adds approximately 6.67 MiB decoded, sharing its existing depth art.

Rebuild lit/picking assets after updating their source models (run the regular
medium colour/depth baker first when its framing also changes):

```sh
AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/bake_medium_lighting.tscn -- --no-telemetry
godot --headless --editor --path . --import
AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/review_medium_cache.tscn -- --continent-review --no-telemetry
godot --headless --path . res://tests/test_runner.tscn -- --tags supply_chain_3d --no-telemetry
```

The review uses the production board and builder without profiler subclasses.
It exercises adjacent and continent-wide pans, recent returns, rotation,
near/medium changes, far-view scene release, tile/building picking and a matched
lit-sprite/source-model capture. Artifacts are saved at repository-root
`outputs/supply-chain-3d/medium-resource-cache/`.

On the M5 Pro at 1920×1080, the final production review measured:

| Request | Attach/refine work | Including settling and a forced draw | Disk reads |
| --- | ---: | ---: | ---: |
| First medium entry | 1,143ms | 1,259ms | 69 |
| Adjacent pan | 245ms | 265ms | 16 |
| First cross-continent visit, existing disk bakes | 924ms | 939ms | 57 |
| Return to previous area | 193ms | 210ms | 0 |
| Repeat cross-continent visit | 129ms | 141ms | 0 |
| Medium after far scene release | 166ms | 194ms | 0 |

These are scripted requests excluding the periodic input-to-stream scheduling
delay, not guaranteed interactive frame times. The main pan sequence wrote no
bakes; a later lit-building review filled four missing medium bakes. First-use
asset uploads and uncached geography can still exceed one second. The earlier
far-opening target and parked renderer hitch are not resolved by this change.

Initial medium contained no source/contour/clutter nodes. Eight prefetch candidates
were checked with zero node growth or writes, and all 24 original medium meshes
were identical on return. Seven projected building centres hit their expected
building after the lit-area pan. The cache held 95 tile entries at about 424 MiB
after medium visits and 689 MiB after near zoom. Eight loaded lit colour atlases
added about 53 MiB shared. A subsequent new-area visit temporarily reached 739 MiB
because the visited entries were still protected; the soft budget permits this.

Validation: 1,321 checks across 147 tests passed, including retention/proximity
protection, eviction order, rejected prefetch admission, offline asset freshness,
lazy near activation and resource identity after scene eviction. The existing
`%TerrainLayer` fixture error and shutdown leak warnings remain in the broader
tagged suite; there were no script errors or failed assertions. The rendered
production review had no script/runtime errors (its existing ObjectDB shutdown
warning remains).


## Complete medium package, range review and visible coverage (2026-10-10)

The authored Metal Magnate continent now ships all 600 medium terrain bakes,
600 base chunks, one far continent resource and one scenery resource. The 1,202
resources occupy 324,478,001 bytes (309.45 MiB), plus small JSON manifests. The
initial completion generated 496 missing medium tiles and reused 104; the final
resumable pass reused all 600. This covers this authored starting layout; other
starts, map edits or content-key changes can still need runtime bakes.

`bake_continent_package.gd` writes compressed, content-addressed resources and a
complete manifest. `bake_package.gd` validates every file's size/SHA-256, resource
schema, external dependencies, tile references, 1024×912 medium textures with
mipmaps, and the visibility bounds against the actual terrain meshes. A fresh
process validates with the user cache disabled. `source_fingerprints.json`
preserves the source-based cache keys in compiled exports: `.gd` source files
are absent in the PCK, so hashing them there would otherwise miss every bundled
bake. Editor validation rejects stale fingerprints. When engine/schema/revisions
do not match, the runtime derives new keys from the available compiled sources.

Repeatable release workflow, from the Godot project directory:

```sh
AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/bake_continent_package.tscn -- --continent-review --prune --no-telemetry
godot --headless --path . res://tools/supply_chain_3d/verify_continent_package.tscn -- --no-telemetry
godot --headless --editor --path . --export-pack macOS /private/tmp/continent-release.pck -- --no-telemetry
```

The baker also accepts `--package-output=...`. `--prune` removes superseded `.res`
files in that generated output directory; omit it to preserve old content keys.
Run the package validation before each export after changing baked artwork or
its generators. All three desktop export presets include the bakes. The actual
macOS PCK is also tested from an empty directory, with no loose-project fallback:

```sh
# Supply absolute tool paths from this checkout. Run with an empty directory as cwd.
godot --headless --main-pack /private/tmp/continent-release.pck --script /absolute/project/tools/supply_chain_3d/verify_exported_package.gd -- --no-telemetry --validator=/absolute/project/tools/supply_chain_3d/bake_package.gd
```

Medium detail now covers every visible tile. The old 24-tile fine-terrain cap
produced coarse patches at the sides of a medium view. The 96-node allowance now
limits only offscreen buffering; visible tiles are never dropped to meet it.
At the time of that pass, near zoom permitted 24 expensive near meshes, with medium terrain covering
remaining visible tiles. At the widest local zoom, all terrain consistently
uses the continent tier.

Visibility metadata is version 4: the tile centre plus eight corners of a
conservative 3D box. Bounds include the spline control-lattice extrema, interior
summits, mines, outside cutaway slabs, tree crowns, building roofs, and the
possible displacement between a live camera angle and its nearest sprite view.
Old corner-only metadata upgrades independently of the terrain images. The
review includes summits and roofs four screen pixels above the bottom edge,
with their ground footprints outside the viewport.

The visual pass enlarged only medium `pylon_lvl1`, `towers_lvl1` and `towers_lvl2`
frames from 128 to 192 pixels. Pylons now have 32 horizontal views rather than
16; other medium assets retain 16, with five pitch views throughout. Lit tower
variants were regenerated with identical framing. This adds about 66.7 MiB
of decoded atlas memory if all three assets and both lit tower variants are
resident. Trees and ordinary buildings retain their previous atlas sizes.
Foundations fit each model's actual footprint and use darker, segmented walls
that reach the hillside. The far foundation mesh upgrades separately, reusing
all existing terrain, roads and tile chunks.

The production capture matrix is reproducible with:

```sh
AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/review_medium_range.tscn -- --continent-review --no-telemetry --range-output=res://../outputs/supply-chain-3d/medium-range-final
godot --headless --path . res://tests/test_runner.tscn -- --tags supply_chain_3d --no-telemetry
```

Captures cover both ends of medium zoom, coastline and river areas, shallow and
high pitch, both 16- and 32-yaw boundaries, a pitch boundary, viewport edges, and
the far overview. The matched `coast_old_24_tile_limit.png` reconstructs the old
coverage policy for comparison. The Luna review found clearer pylons/towers,
better grounded foundations, continuous water edges, and no serious new
artifact in the threshold samples. Fine lattice/tree aliasing and some stepped
foundations on slopes remain. Discrete sprite angles still exist; threshold
stills do not prove a completely smooth live sweep.

The full 600-tile medium texture set decodes to 2,988,381,600 bytes (2.78 GiB);
it is packaged on disk, not eagerly retained in memory. The 700 MiB resource
cache remains a soft target because visible, nearby and recently used tiles
are protected. The rapid review tour temporarily retained about 1 GiB. The
larger visible-detail coverage can cost more than the former 24-tile limit.
These runs validate coverage and appearance, not a new pan-time promise: cold
first visits can still take over a second, and the previously parked renderer
hitch is outside this pass.


Final validation: **1,342 checks across 155 tests passed**. The existing
`%TerrainLayer` fixture error and shutdown leak warnings remain; there were no
script errors or failed assertions. All 18 production views recorded zero
missing tiles/terrain tiers and zero bake writes, with both edge-test tiles
retained. The middle coast view contained 44 fine tiles, and the wider fine view
contained 70, compared with the previous 24-tile cap. The release PCK loaded all
1,202 resources from an empty working directory with compiled scripts only,
matching editor fingerprints and no package errors. Final bake, export, test
and validation reports are at repository-root
`outputs/supply-chain-3d/continent-package/`; visual captures and the reviewer
notes are at `outputs/supply-chain-3d/medium-range-final/`.


### Decorative outline trim (2026-10-10)

Far decorative houses and towers use softer blue-grey ink: outer contours are
40% thinner, roof/window crease lines are 35% thinner, and crease opacity is
0.70 instead of 0.88. These settings apply only while baking the five far
decorative colour atlases. Medium and near retain their original treatment,
including the original medium colour, depth and lit-window images.

The far frames remain 64 pixels with the same 16 yaw and five pitch views.
`bake_far_sprites.tscn -- --colour-only --asset-keys=...` reuses existing framing
and preserves depth images and manifest bytes. The existing opaque extents stay
conservative after thinning the outlines. This colour-only update therefore
reuses the continent terrain package without generating another terrain bake.

`review_decor_ink.tscn` captures matched far views at whole-continent zoom,
0.20 and 0.30 pixels per unit, plus a rotated view, followed by medium and near
checks. Pass `--before-sprites=/path/to/previous/far/atlases` to include before
views. Captures are at repository-root
`outputs/supply-chain-3d/far-decor-outline-trim/`.

The far comparisons passed visual inspection with building silhouettes retained.
All six production views recorded no missing coverage and zero bake writes.
Byte comparisons confirmed the original 15 medium colour/depth/lit images,
five far depth images and live material configuration were preserved. The
existing regression suite passed 1,342 checks across 155 tests; its existing
TerrainLayer fixture/shutdown warnings remain.

### Near/closest camera radius (2026-10-10)

The existing near LOD now loads the tile under the viewport centre and all tiles
within four hex steps: 61 tiles for an interior location, clipped to the map at
the edges. This replaces the former 24-tile near terrain cap; it adds no fourth
visual tier and changes no artwork. The terrain ray at the screen centre defines
the focus tile, with the orbit pivot as a fallback when that ray misses.

All four rings receive near terrain, including offscreen tiles. Visible requests
load/refine before the offscreen ring, and the existing frame slices and camera
change cancellation remain in place. Visible tiles outside the radius retain
medium terrain as a coverage fallback. Medium and far keep their existing loading
policies. The normal scene frustum still culls offscreen geometry.

Leaving the radius releases unneeded scene nodes but retains their tile resources
for at least ten seconds, measured from departure. Active and nearby tiles remain
protected for longer. After the grace period, the existing least-recently-used
cache policy may evict unused resources under pressure; spare capacity does not
force an eviction. The 700 MiB cache target remains soft, so the mandatory radius
can exceed it. Existing terrain bake keys are unchanged.

`review_near_radius.tscn -- --continent-review --no-telemetry` exercises the full
61-tile neighbourhood, an adjacent pan, a return and expiry after far zoom. Captures
and measurements are at repository-root `outputs/supply-chain-3d/near-radius/`.

The rendered review loaded exactly 61 near tiles at both centres and reused 52
near meshes across the one-tile pan. With existing disk bakes, the initial full
radius loaded in 4,095 ms, the adjacent pan in 579 ms and the return in 52 ms;
all views recorded zero missing tiles and zero bake writes. These are complete
streaming-pass times on this machine, not frame-time guarantees. The tile cache
held 1,529 MiB at the first centre and 1,753 MiB after the pan, including recently
departed tiles; shared artwork, scene nodes and other native allocations are
additional. Expiry after far zoom released the scene tiles and reduced cached
resources to 681 MiB. The test advances the expiry timestamps rather than waiting
ten wall-clock seconds; unit tests exercise both sides of the real 10,000 ms rule.

The first run generated 39 missing near bakes and needed 19.1 seconds to fill the
initial radius, then 4.65 seconds for nine new bakes after the adjacent pan. This
policy does not remove that first-generation cost or promise subsecond initial
entry. The existing cache makes subsequent visits reusable. Final regression
validation passed 1,353 checks across 156 tests, including independent gameplay
neighbour-graph comparisons for odd/even columns, map edges, centre-hit selection,
offscreen radius coverage, visible-first priority and unchanged medium loading.

### Complete closest terrain package (2026-10-10)

The authored Metal Magnate continent now ships all 600 closest/near terrain bakes,
alongside the existing medium tiles and whole-continent far bake. These use the
existing highest-detail artwork: 2048 × 1824 textures with mipmaps and terrain
meshes sampled every four world units. No additional LOD or artwork change is
introduced. Buildings and trees continue using their existing near assets.

The offline package builder is resumable across both medium and near tiers. This
run reused all 600 medium tiles, copied 81 existing near bakes and generated the
remaining 519. Generation, copying and validation took 215.5 seconds. Manifest
schema 2 requires both tiers for every tile; the release gate verifies file hashes,
dependencies, texture sizes, mipmaps and terrain coverage inside the baked bounds.

The resulting package contains 1,802 resources totalling 1,100,870,159 bytes
(1,049.87 MiB). Near resources add 776,392,158 bytes (740.43 MiB). All 600 near
textures decoded together would occupy 11.13 GiB before geometry, which is why
these are stored on disk and streamed through the existing 61-tile neighbourhood
and ten-second retention policy. This package removes missing-bake generation for
the current authored continent; disk decoding, scene assembly and GPU upload
costs remain. Different map content still uses the content-keyed runtime fallback.

The package builder and a fresh headless process independently validated all
1,802 resources without runtime-cache fallback. The regression suite passed
1,355 checks across 156 tests, including rejection of missing near entries and
medium-resolution textures incorrectly indexed as near. Evidence is stored at
repository-root `outputs/supply-chain-3d/closest-package/`.

A macOS export pack also passed the full gate from an empty working directory,
with compiled scripts only and matching source fingerprints. A rendered run of
`review_near_radius.tscn -- --continent-review --bundled-only --no-telemetry`
confirmed 61 near tiles at both centres, no missing coverage and zero bake writes.
The initial neighbourhood streamed in 4,157 ms, an adjacent one-tile pan in 602 ms,
and the return in 59 ms. The pan reused 52 near meshes and retained the nine
departed tiles. Memory stayed at the previously measured 1,529 MiB initially and
1,753 MiB after the pan, dropping to 681 MiB after simulated grace expiry at far
zoom. These timings include the complete streaming pass on this machine; they
are not cold-storage or per-frame latency guarantees. The existing fixture and
shutdown warnings remain; the rendered package review had no script errors.

### Closest cache speed investigation (2026-10-10)

Measurement-only tools `profile_closest_loading.tscn` and
`profile_bake_storage.tscn` leave production streaming and shipped bakes unchanged.
The first extends the 61-tile review with stage timers; the second compares nine
near resources against temporary, lossless uncompressed copies, then deletes the
copies. Evidence is in `outputs/supply-chain-3d/closest-cache-profile/` at the
repository root. The later profile excludes capture time from frame intervals.

The detailed run took 3,490 ms for initial closest entry, 462 ms for an adjacent
pan and 35 ms to return. Initial / adjacent costs were respectively 925 / 125 ms
in near resource loading, 389 / 57 ms creating terrain picking shapes, 571 / 85 ms
attaching them, and 506 / 120 ms generating ground clutter. These selected stages
do not cover all elapsed time. A preceding instrumented run took 2,566 / 324 / 34 ms;
timings vary with runtime/render state. Both runs reported zero bake writes and
zero missing tiles. Every new tile in the adjacent pan was offscreen: nine outer
ring tiles were prepared while all visible tiles were already resident.

Current prefetching only loads medium resources. Its 80%-of-700-MiB admission
limit is below the compulsory near working set, so it cannot prefetch at closest
zoom. Its viewport-based candidate region also often contains no tiles beyond the
four-ring neighbourhood. Initial far-to-near reveal waits for the entire ring,
and all base scenes are built before visible near terrain is refined.

The storage comparison used three alternating-order rounds, warmed filesystem
data, and `CACHE_MODE_IGNORE` to reload embedded resources. Median resource-load
time for nine near tiles fell from 97.62 ms compressed to 36.20 ms uncompressed;
including a forced draw, from 109.92 to 47.66 ms. Storage rose from 12.42 to
191.28 MiB for those tiles. Raw file reads alone took 1.71 / 11.55 ms respectively.
This supports faster resource decoding as a useful option, not a whole-pan speed
claim or a cold-drive guarantee. GPU completion is not isolated by the load call.

Recommended next work: reveal and activate visible detail first while completing
the four-ring resource cache asynchronously; add near-aware directional prefetch
with explicit memory headroom; prewarm picking resources and bake/reuse ground
clutter; benchmark a faster local resource format in the complete streaming path.
Keep scene/physics activation and GPU work budgeted separately from background
loading. Serialized collision faces alone may still require native acceleration
structure construction on load. All recommendations remain unimplemented here.

### Raw storage and prepared local geometry (2026-10-10)

The next iteration implements the storage and geometry recommendations above.
Bake resources now use lossless, uncompressed Godot binary storage by default;
previous compressed resources remain readable. Base tiles also contain prepared
grass/stone meshes, water-glint meshes and tree-card transforms. Terrain resources
contain their picking shapes. Water animation, material setup and native collider
activation still happen at runtime. A separate detail-source fingerprint lets
local geometry regenerate without invalidating unchanged terrain artwork.

All 600 authored tiles have been converted, reusing the existing medium and near
terrain rather than repainting it. Package schema 3 checks raw storage, prepared
detail, picking shapes and their source fingerprints in addition to the previous
hash, texture, mipmap and bounds checks. The 1,802 resources now occupy
18,045,143,103 bytes (16.81 GiB), up from 1.03 GiB compressed. The runtime disk-cache
cap is 24 GiB. This is a substantial installed-space tradeoff; it does not increase
texture resolution or change the ten-second memory retention policy.

The rendered closest benchmark, with runtime-cache fallback disabled, measured:

| Complete streaming pass | Previous instrumented run | Prepared raw run |
| --- | ---: | ---: |
| Initial 61-tile radius | 3,490 ms | 1,967 ms |
| Adjacent pan, nine new tiles | 462 ms | 281 ms |
| Return within retention window | 35 ms | 9 ms |

These are measurements on the Apple M5 Pro using Godot 4.6.2 Compatibility, not
cold-storage or frame-time guarantees. The new run had zero missing tiles and
zero bake writes. Tile resource estimates were 1,531 MiB initially and 1,755 MiB
after the pan, close to the previous 1,529 / 1,753 MiB. Shared assets and native
allocations are additional. The closest first-view RGB capture was pixel-identical
to the previous profile. The medium review also reported zero writes, successful
tile picks at every stage and seven matching building picks.

Initial / adjacent resource loading fell to 512 / 70 ms; terrain shape lookup to
0.15 / 0.02 ms; ground clutter setup to 0.07 / 0.01 ms. Assigning the detailed
terrain colliders still cost 592 / 87 ms. Those colliders are static picking
surfaces, not a physical simulation of the landscape. They support clicks and the
camera-centre terrain query. A future visibility-based activation policy could
keep offscreen resource preparation while deferring that native physics work.
Removing physics entirely would require replacement terrain and building picking.

`profile_bake_granularity.tscn` compares actual embedded resource packages over
three alternating-order rounds with warmed filesystem data and fresh resource
loads. Its contiguous 3×3 region contains the same terrain payloads as nine
individual tile resources:

| Request | Individual tiles | Whole 3×3 region | Tile / region bytes |
| --- | ---: | ---: | ---: |
| One medium tile | 1.35 ms | 10.67 ms | 5.54 / 49.83 MiB |
| All nine medium tiles | 10.97 ms | 10.41 ms | 49.83 / 49.83 MiB |
| One near tile | 4.45 ms | 39.03 ms | 22.10 / 198.88 MiB |
| All nine near tiles | 40.68 ms | 38.91 ms | 198.88 / 198.88 MiB |

On the real closest pan trace, 3×3 packages would load 108 tile payloads to satisfy
the initial 61-tile radius. That overfetch does fully cover the next adjacent pan,
but costs 77% more initial payload and resident tile data. Per-tile storage keeps
nearly the same full-batch throughput while allowing targeted, budgeted loading.
The additional spatial model compares 2×2, 3×3 and 4×4 regions along a longer pan;
its byte counts are analytical, not timing measurements.

The building comparison covers model geometry, contours and picking resources,
excluding sprite atlases and scene activation. For 49 instances of six model
types, separate placement files used 3.17 MiB and loaded in 4.57 ms; shared type
files used 1.08 MiB and 0.68 ms. Tile bundles used 2.22 MiB and 1.61 ms; a region
bundle used 1.07 MiB and 0.41 ms. The small region advantage does not justify
duplicating shared models across regions. Production therefore retains per-tile
terrain and shared per-type building resources.

Measurements, logs, spatial models and captures are at repository-root
`outputs/supply-chain-3d/fast-prepared-bakes/`. The new cache regression checks
cover a fresh disk reload without terrain sampling, picking-shape reuse, memory
accounting and backward reading of compressed bakes. Three asset-freshness checks
currently fail because 15 building model sources have changed since their far,
medium and lighting/picking asset bakes; those independent asset changes are
preserved. They are not repaired by changing terrain cache metadata.

Final validation passed 1,357 checks with those three asset-freshness failures
remaining. A fresh headless process also validated all 1,802 resources / 600 tiles
from the exported macOS pack in an empty working directory, with compiled scripts
only and no loose-project fallback. Exported source fingerprints matched and the
package gate reported no errors.

### Cursor-local collision (2026-10-10)

Detailed collision now follows the cursor independently of terrain/resource
residency, in both company-only and whole-continent supply-chain views. The
requested 300-world-unit radius rounds down to zero neighbouring hex rings:
adjacent tile centres are approximately 471–480 units apart, so only the tile
under the cursor activates its detailed terrain and selectable building shapes.
The 61-tile closest neighbourhood, artwork and ten-second resource retention
policy are unchanged. No regular-map code is changed.

One shared coarse surface remains active to locate the cursor and serve far-zoom
tile selection. Its invisible mine-opening caps keep pits selectable when mine
bodies are detached. At medium/near zoom, clicking or moving across a tile boundary
attaches the prepared shape for the displayed LOD and detaches the previous tile's
shapes. Buildings retain the existing 20×20 logical-pixel selection threshold and
two-world-unit edge tolerance. Cheap building bounds nominate overhanging roofs;
exact collision decides which tile to retain. A coarse/fine terrain disagreement
at an edge can also probe resident neighbours one at a time, without keeping a
neighbour ring active. Camera-centre preload queries never move cursor collision.
Leaving the viewport, closing the view or entering far LOD detaches detailed
collision. Repeated queries at an unchanged cursor/camera/LOD reuse the result.

The rendered closest profile simulates a cursor at viewport centre. It retained
exactly one detailed terrain collider in each near view and none at far zoom:

| Complete streaming pass | Raw bakes, all tile colliders | Cursor-local colliders |
| --- | ---: | ---: |
| Initial 61-tile radius | 1,967 ms | 1,465 ms |
| Adjacent pan, nine new tiles | 281 ms | 159 ms |
| Return within retention window | 9 ms | 9 ms |

Detailed terrain collision synchronization took 10.26 ms initially and 10.01 ms
after the adjacent pan, down from 592 / 87 ms with every tile activated. These
machine-specific streaming times include resource loading and activation; they
are not cold-start or per-frame guarantees. Both runs have zero missing tiles and
zero bake writes; their closest-view RGB images are identical. Far-transition
render hitches remain outside this change. The medium/near/far rendered review
also passed all tile picks and seven building picks, with at most one detailed
terrain collider active. Evidence is in repository-root
`outputs/supply-chain-3d/cursor-collision/`.

Headless interaction tests cover immediate first clicks, fixed-cursor panning,
camera-query independence, cached-shape reuse, shared tile edges, coarse/fine relief
disagreement, overhanging roofs, mine openings and far-zoom selection. Existing
building-source/sprite freshness failures remain separate from collision changes.
No terrain or sprite rebake is required for this activation policy.
The final regression run passed 1,376 checks, including all 19 new collision
checks, with the same three asset-freshness failures and no script errors.

### Compact lossless storage (2026-10-10)

Native Zstd compression is now the default for both shipped and runtime-generated
bakes, superseding the raw-storage default above. Prepared meshes, picking shapes,
local detail, all texture pixels and mipmaps are preserved. Existing raw resources
remain readable. The package manifest is version 4 and declares the storage codec;
the release gate verifies each resource's actual header as well as its hash,
resolution, visibility bounds and prepared data. The runtime disk cache cap is
2 GiB; bundled resources remain separate and are never trimmed by that cache.

All 600 medium and 600 near bakes were reused and reserialized without terrain
generation. The 1,802 current resources fell from 18,045,143,103 bytes (16.81 GiB)
to 1,209,699,909 bytes (1.13 GiB), a 93.3% reduction. Four obsolete, unindexed
continent/scenery resources were also removed. Including package metadata, the
directory now occupies 1,210,200,036 bytes. This is the continent bake contribution,
not the size of the entire exported game.

| Payload | Compressed size |
| --- | ---: |
| 600 base tiles / prepared local detail | 37.62 MiB |
| 600 medium tiles | 250.65 MiB |
| 600 near tiles | 817.76 MiB |
| Joined far continent | 47.11 MiB |
| Shared scenery data | 0.52 MiB |

The rendered closest loading trace, with cursor-local collision enabled in both
runs, measured the following complete streaming passes on the Apple M5 Pro:

| Request | Raw storage | Lossless Zstd |
| --- | ---: | ---: |
| Initial 61-tile closest neighbourhood | 1,465 ms | 2,071 ms |
| Adjacent pan, nine newly loaded tiles | 159 ms | 231 ms |
| Return during the ten-second retention window | 9 ms | 9 ms |

These are single machine-specific streaming runs, not cold-storage, game-startup
or per-frame guarantees. Decompression adds 606 ms to initial closest preparation
and 72 ms to the adjacent pass; it does not change the retained-memory return.
The closest RGB capture is pixel-identical. There were no missing tiles or bake
writes, and only one detailed terrain collider remained active. Decoded resource
memory is unchanged (about 1,531 MiB initially and 1,755 MiB after the pan): this
change saves disk space, not texture RAM. Far-transition hitches remain outside
this change.

`profile_compact_bakes.tscn` compares nine varied near tiles over three alternating
rounds, with warmed filesystem data and fresh resource loads. Native lossless
Zstd reduced the sample from 198.87 MiB to 13.62 MiB. A FastLZ prototype used
19.66 MiB and loaded only about 8% faster than Zstd, so the production reader/writer
uses Godot's native Zstd resource format. GPU S3TC plus Zstd was a promising lossy
alternative at 7.06 MiB and 40.89 ms per nine-tile load, versus 116.09 ms for
lossless Zstd in that run. It has not been adopted because it changes pixel data.
BPTC fell back to CPU RGBA decoding on this machine's Compatibility renderer and
did not improve loading. The profiling tool creates disposable copies and never
changes shipped artwork.

Measurements, codec comparisons, logs and matching captures are under
`outputs/supply-chain-3d/compact-bakes/` at repository root.

Validation passed 1,377 regression checks with the same three pre-existing
building-source freshness failures and no script errors. The full exported game
data pack was 1,810,948,584 bytes (1.69 GiB, excluding the engine executable).
A fresh process in an empty directory validated all 1,802 bundled resources and
600 tiles from that pack, using compiled scripts only; source fingerprints matched
and the package gate reported no errors. The temporary export pack was removed
after verification.

The level immediately outside closest zoom is named `medium` internally (tier 1,
1024×912 terrain textures, versus tier 2's 2048×1824). Its 600 compressed tile
resources total 250.65 MiB, averaging 0.418 MiB each. It uses the same prepared
geometry, cursor-local collision, ten-second retention and nearby-tile protection.
Its loading coverage follows visible bounds plus a buffer and directional
prefetch; the fixed four-ring neighbourhood applies to closest zoom.

A separate production-board medium review after compression measured complete
arrival/streaming plus draw times, including the existing LOD transition:

| Middle-LOD request | Previous raw run | Compressed run |
| --- | ---: | ---: |
| First arrival | 646 ms | 908 ms |
| Adjacent pan | 86 ms | 189 ms |
| Jump across the continent | 356 ms | 563 ms |
| Return to retained tiles | 85 ms | 83 ms |
| Zoom out from closest | 37 ms | 30 ms |

These are single-run measurements on the same machine, not worst-case latency
guarantees. First arrival retained 55 tiles / 315 MiB of tile resources; after the
across-continent jump it retained 109 / 637 MiB. Shared assets and native allocations
are additional, and decoded memory is unchanged by storage compression. Every
tile-selection check passed, seven building picks matched, and the run produced
zero bake writes or script errors. Evidence is in
`outputs/supply-chain-3d/compact-bakes/medium/`, including full timing records and
capture-difference metrics. Full captures differ in 0.10–0.25% of pixels and are
not claimed to be pixel-identical; capture timing is not fixed for animated effects.

### Renderer and engine profiling (2026-10-10)

The working project remains Godot 4.6.2 / Compatibility. Eight disposable rendered
runs compared that baseline with 4.6.2 / Forward+ / Metal, 4.7.2 / Forward+ / Metal,
and 4.8 dev7 / Compatibility. Mobile and Forward+ on 4.8 were not tested. Engine
binaries, project copies, imported resources and shader caches were isolated under
`/private/tmp/poe-renderer-engines/` and `/private/tmp/poe-renderer-profile/`.
The application name in each copy isolates preferences from the user's game.
No regular-map source, production shader, project renderer setting or installed
Godot binary was changed by this experiment.

`tools/supply_chain_3d/profile_renderers.tscn` drives the real New Game path,
whole-continent setup, medium arrival/adjacent/across/return, closest
arrival/adjacent/return, and far return. It extends the existing loading probes,
records shader pipeline counters and rendering statistics, and captures each
view. The window is 1920×1080; the measured 3D viewport is 1920×1044 with existing
4× MSAA. VSync is disabled. Draws are forced during streaming because background
windows may otherwise stop rendering. This is a controlled background-window
benchmark, not a continuous mouse-pan FPS measurement. The OS filesystem cache was
not purged, and shader caches were not reset between repeated runs.

The opt-in `--reuse-reference-bakes` flag freezes source keys to the packaged
4.6.2 fingerprints in the test process only. This isolates engine/renderer work
from procedural regeneration and keeps the existing compressed payload identical.
It does not validate a production engine migration or remove the production
engine-version cache guard. All eight runs reported zero cache misses, zero bake
writes, zero missing requested terrain and successful centre-tile picks at all
nine stages. Scripts completed without errors. The capture harness reported
ObjectDB leaks at exit on every configuration; newer engines report 999 objects.
This is not a clean shutdown/leak certification or a full interaction regression.

| Complete streaming pass | 4.6.2 Compatibility, two runs | 4.6.2 Forward+, alpha prototype | 4.7.2 Forward+, alpha prototype | 4.8 dev7 Compatibility, two runs |
| --- | ---: | ---: | ---: | ---: |
| Whole-continent setup after company view | 9,950–10,093 ms | 10,078 ms | 9,927 ms | 9,350–9,502 ms |
| First medium arrival | 1,116–1,117 ms | 763 ms | 770 ms | 1,075–1,100 ms |
| Medium adjacent pan | 206–212 ms | 158 ms | 151 ms | 196–205 ms |
| Medium across-continent jump | 656–689 ms | 511 ms | 517 ms | 599–618 ms |
| First closest arrival on this route | 1,907–1,949 ms | 1,467 ms | 1,514 ms | 1,843–1,870 ms |
| Closest adjacent pan | 279–295 ms | 227 ms | 232 ms | 261–277 ms |

Forward+ gives a useful adjacent-loading improvement on this Apple M5 Pro, but
4.7.2 adds no clear benefit over 4.6.2 in this small sample. These totals span
multiple frames. The corrected Forward+ runs still had worst adjacent intervals
of 18.6–18.7 ms at medium and 27.8–30.6 ms at closest. Initial closest exposure in
the original Forward+ runs included 453 ms and 1,791 ms intervals respectively,
coinciding with additional pipeline creation. On the warmed alpha-prototype runs
these fell to 79–85 ms. Warming, shader correction and run order are confounded,
so the difference is not proof of a single hitch cause. Initial continent setup
is still roughly ten seconds in this full-game harness.

Per-viewport GPU timestamps returned zero on both Metal configurations despite
measurement being enabled. Treat them as unavailable, not zero GPU cost. The
force-draw timings include submission/synchronization and must not be presented
as pure GPU times or reciprocal-FPS estimates. Texture/buffer monitors include
other loaded game assets, including regular-map textures.

The unmodified sprite shader makes far/medium buildings and trees translucent in
Forward+. Its alpha antialiasing edge was 1.0 against a scissor threshold of 0.025;
Godot documents that the edge should be below the scissor threshold. A disposable
prototype sets the Forward+ edge to 0.01 and supplies atlas pixel coordinates via
`ALPHA_TEXTURE_COORDINATE`. This restores solid sprites while keeping geometry,
texture resolution and bake contents unchanged. The prototype is saved as
`outputs/supply-chain-3d/renderer-profile/far_sprite.forward-prototype.gdshader`
at repository root, and is not applied to production.

Forward+ still needs an appearance pass before adoption. The far background
changes from RGB (43,55,87) to (51,67,111), and sprite edges differ. The corrected
medium full-frame difference above eight channel values falls from approximately
20% of pixels to 3.7–3.8%; animated goods/water contribute to those comparisons.
The closest sample differs at about 0.75% of pixels. The 4.8 Compatibility closest
capture is pixel-identical to the repeated 4.6.2 baseline; the medium capture
differs at about 0.08% of pixels above that threshold. These observations do not
establish visual equivalence for every camera, asset or regular-map UI.

The 4.8 runs use existing embedded ImageTextures. They do not exercise the new
experimental mip-level texture streaming system. Evaluating that feature requires
a separate texture-import/bake-layout prototype, including coordination with the
ten-second resource retention policy. Background resource loading, bounded GPU
activation and correcting the prefetch budget remain necessary regardless of
renderer. A 4.6.2 Forward+ migration with the art corrections is the best-supported
renderer candidate from this experiment; upgrading the whole game is not yet
justified by these timings alone.

Evidence is in repository-root `outputs/supply-chain-3d/renderer-profile/`:
`comparison.json`, `image-differences.json`, per-run logs, `measurements.json`,
`profile.json`, `rendering.json`, and nine PNG captures per run. Reproduce in an
isolated copy with the relevant engine shim and:

```sh
AGENT_GODOT_WINDOW=1 godot --path /path/to/disposable/project --windowed \
  --resolution 1920x1080 --rendering-method forward_plus \
  --rendering-driver metal --disable-vsync \
  res://tools/supply_chain_3d/profile_renderers.tscn -- \
  --continent-review --no-telemetry --reuse-reference-bakes \
  --range-output=/absolute/path/to/results
```

Use `gl_compatibility` / `opengl3` for the baseline. The temporary alternate-engine
shims preserve the existing automatic-headless and focus-return behaviour.
References: [renderer comparison](https://docs.godotengine.org/en/4.6/tutorials/rendering/renderers.html),
[sprite alpha shader outputs](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html),
and [4.8 texture streaming](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-5/).

### Forward+ adoption and matched appearance captures (2026-10-10)

The desktop project now defaults to Forward+ on the existing Godot 4.6.2 engine.
This supersedes the prototype-only status above. The mobile override remains
Compatibility; no regular-map source or artwork was changed. Validation here was
on the Apple M5 Pro with Metal, not Windows or Linux.

The sprite correction is applied in `far_sprite.gdshader`: the Forward+ alpha
antialiasing edge is 0.01, below the 0.025 scissor threshold, with atlas pixel
coordinates supplied to `ALPHA_TEXTURE_COORDINATE`. The Compatibility branch
retains its previous edge value. This restores opaque building/tree interiors
without changing the sprite artwork, lighting setup, or LOD resolutions.

`compare_renderer_appearance.tscn` extends the renderer tour with a closest
building view and a regular-map smoke capture. Only this capture tool hides
moving goods, cars, smoke, and animated water glints. Production effects are
unchanged. The ten 3D camera states match between renderers; the regular-map
captures are visual smoke evidence only, as the 2D camera position was not fixed.
Full-resolution PNGs, logs and `appearance-comparison.json` are in repository-root
`outputs/supply-chain-3d/forward-adoption/`. The interactive preview uses identically
resized, 1200px-wide WebP images; use the original PNGs for pixel-level inspection.

The most obvious remaining change is the far background, from RGB (43,55,87) to
(51,67,111). Medium buildings and trees have different edge smoothing, while
terrain colours and shading remain close. In the matched medium frame, 3.30% of
pixels differ by more than eight values in any RGB channel; the closest building
frame is 0.94%. These are selected-frame comparisons, not a guarantee of parity
at all camera angles or for every asset.

Both renderers completed New Game and all ten centre-tile picks with no missing
requested terrain. The first current-catalogue capture in each project generated
602 cache resources (three misses), triggering the benchmark's no-new-bake
assertion. The source was the asset manifest's three added fracking-well entries,
which invalidate scenery/continent keys independently of the renderer. A repeated
Forward+ run used the normal production fingerprints with zero misses and zero
writes. No cache-key override or invalidation bypass was added. These appearance
runs should not be used as a new speed comparison.

The unrestricted headless `supply_chain_3d` suite reports 1,377 passing checks and
the same three existing source-asset freshness failures (far sprites, medium
sprites, and medium lighting/picking assets). The initial sandboxed test attempt
also failed user-cache writes; those extra failures disappear with normal access
to Godot's user data directory. The existing ObjectDB shutdown warning remains.

## Continent startup and stable panning (2026-10-10)

Enabling all tiles now keeps the current camera target and angle and opens at
medium detail (1.1 logical pixels per world unit). The first opening with all
tiles already enabled uses the regular map camera's current location. Subsequent
openings preserve the supply-chain camera. Home / Reset view still explicitly
frames the entire coverage. The regular map renderer and its controls are unchanged.

The reported minute-long first opening was not a 60-second texture read. The
old keys hashed the entire 3D asset catalogue and sprite manifest, so adding an
unrelated model invalidated scenery and the joined continent. The previous
Forward+ run recorded 602 writes after three fracking-well entries were added.
Keys now include the dimensions of placed models, tree scale, and sprite framing
actually used by the bake. Changes to those inputs still invalidate correctly;
unrelated artwork/catalogue changes do not. When rebuilding a backdrop, existing
independently keyed base chunks retain their prepared detail and picking data.

The remaining cached path also did substantial work that was not on disk:
clipping coastline/land polygons to each hex, checking street costs, finding
shore paths and street routes, and sampling traffic on every road. The new
`layout_queries.gd` adapter ships the pure geographic memo tables with the
package. Its key includes geography, coastlines and relevant generator sources;
callable IDs are rebound per process. A separate `layout` source-fingerprint layer
preserves the same keys when an export remaps scripts to compiled `.gdc` files.
Live buildings, stock, routes and goods
still run through `Model.build`, rather than loading a saved simulation model.
Traffic height paths and nodes are prepared for resident tiles within a small
frame budget instead of preparing offscreen traffic during opening.

Measured in fresh Godot 4.6.2 Forward+/Metal processes on the Apple M5 Pro,
1920×1044 supply-chain viewport, authored Metal Magnate start:

| Stage | Previous cached opening | Updated opening |
| --- | ---: | ---: |
| Model inputs and layout | 5,613 ms | 870 ms |
| Scenery read | 36 ms | 31 ms |
| Continent read/preparation | 297 ms | 350 ms |
| Scene/effect preparation | 3,529 ms | 346 ms |
| Board build total | 9,713 ms | 1,838 ms |
| Ready, including requested detail and render | 9,718 ms | 2,711 ms |

These timings start at switching an already prepared company view to all tiles.
The previous opening framed the far continent; the updated opening also loads
46 local tiles at medium detail. All 86 reads in the updated run came from the
shipped package, with zero cache misses/writes. This is a first-process opening,
not an OS-cache-purged disk benchmark or a timing for starting the entire game.
A genuinely changed map/layout still needs matching bakes; this result does not
claim sub-five-second regeneration. Textures and meshes were already bundled in
the game resources. Moving only the texture read into the loading screen would
not address the CPU work above. The existing loading-screen preparation remains
opportunistic rather than adding a blocking whole-continent build to New Game.

The refreshed package contains 1,803 resources / 600 tiles, validates with no
errors, and reuses all 1,200 medium/near terrain resources and 600 prepared base
tiles. The added geographical layout resource is 1,512,930 bytes. Evidence and
captures are under repository-root `outputs/supply-chain-3d/startup-pan-review/`;
`shipped/report.json` is the final rendered measurement and `package-export.stdout`
contains the package validation. The profiler supports `--profile-layout` to time
sections of an in-memory model copy without invalidating the measured bakes.

A separate `--combined-open` run bypasses the capture harness's explicit
preparation wait and opens the view immediately after the normal New Game/Begin
flow. In `combined/report.json`, the loading screen had already completed
1,373 ms of company-board preparation. First visible opening took 22 ms, followed
by 2,702 ms to show all tiles with the initial medium-detail region rendered:
2,724 ms combined visible wait. This run loaded 49 local tiles, with all 91
continent/stream reads bundled and zero cache writes. The background preparation
is additional work during game loading, not an additional wait after opening.

Capital City panning exposed a separate precision issue. Far/medium cards choose
one of 16 yaw views and five tilt views. `look_at(target)` recovered orientation
by subtracting large world positions, so a pure pan at an atlas boundary could
switch between adjacent views. In the reproduction, yaw stayed fixed at 11.25°
but 300 pan samples selected frame 0 on 250 samples and frame 1 on 50. The rig now
constructs its basis directly from yaw/pitch. Each tested yaw keeps exactly one
basis and one sprite frame through all 300 pan samples; a regression additionally
checks pitch boundaries. Deliberate orbiting still uses discrete far/medium views
(22.5° yaw steps); closest detail uses the original 3D meshes.

Focused startup/cache checks pass (27 checks), and camera controls/boundary checks
pass. The broader supply-chain-tag run recorded 1,398 passes and the same three
existing asset freshness failures. Its company-only integration fixture now
explicitly selects that coverage instead of inheriting the user's preference.
A scene closed while asynchronous scenery preparation yields is also handled.

### Pylon geometry and cable attachments (2026-10-10)

The sprite kit's descending X-braces used the bottom width at the top endpoint
and the top width at the bottom endpoint. On a taper this put their ends outside
the mast. It also braced only the two faces visible to the original fixed camera.
The supply-chain-only `tools/supply_chain_3d/pylon_builder.py` corrects those
endpoints and braces all four faces. The shared sprite kit and regular map are
unchanged. The solid mesh grows from 2,284 to 3,004 triangles, with exactly the
same footprint, height and sprite framing.

Four conductor clamps are exported with the model, one below each insulator
string. At the existing 62u model scale these are about 118.5u and 91.3u above
the foundation, replacing the renderer's single cable fixed at ground +62u.
`pylon_cables.gd` uses the actual foundation transform and these attachment
points, hangs four thinner conductors between towers and aligns the crossarms
across the line. Opposing spans reinforce the same axis; a bend is bisected,
and left/right conductors are matched within each tier to avoid crossing.

Pylons use their inexpensive mesh from medium inward. This keeps their thin
lattice and clamps continuously aligned with the cables rather than stepping
between medium sprite angles. Far retains the small atlas. The sprite shader
now chooses views relative to the model's world orientation; unrotated buildings
keep their original views. Both pylon atlases and its stored picking shape were
refreshed. No continent terrain/scenery rebake was needed: those resources store
the unchanged dimensions and framing, not this mesh artwork.

Rendered evidence is under repository-root `outputs/supply-chain-3d/pylons/`.
`before/` and `after/` record the geometry correction; `continent-final/` exercises
six angles at each actual far/medium/near LOD. The review asserts the selected
LOD, avoiding the near-to-medium hysteresis band. Focused tests cover sloping
spans, exact clamp endpoints, line reversal, branches and the medium/far handover.

### Regular-map roads in the supply-chain view — analysis only

No road rendering, layout or simulation was changed for this investigation.
The current supply-chain model generates its own repeating industrial-estate
street plan in `empire_board_streets.gd`: two cross streets, an avenue, building
spurs and fixed exits at the hex edges. Its route costs avoid water but do not
use the regular map's terrain-aware road geometry. This explains the repeated
straight roads and their willingness to climb the exaggerated mountains.

The regular map has two sources. The active document is
`data/map_authored/stoneshore-procedural.json`, with 984 road strokes, of which
136 are unlockable. The disposable Metal Magnate start displays 848 strokes.
`AuthoredRoadGeometry.sample()` gives their curves before visual wobble;
`polyline()` adds the exact authored styling. A separate `RoadNetwork` stores
1,120 baked edges / 26,749 points / 38 bridge records and subsequent live roads.
The renderer suppresses that network on authored tiles. In this particular
start none of those generated edges are visible: importing both indiscriminately
would draw a duplicate network. An adapter still needs the generated fallback
for uncovered tiles and other maps, using the current built state and the same
coverage/flag rules as `road_network_visuals.gd`.

The read-only `analyse_roads.gd` inventory found 11,822 points in the 848 visible
polylines before styling: 94,576 bytes of packed XY coordinates, excluding IDs,
adjacency and mesh data. It found 966 endpoints already on another road and 210
further endpoints within 2u of another polyline, 106 of them within 1u. These are
endpoint candidates, not distinct approved joins; two ends can describe one
gap and some apparent joins may belong at different elevations. Evidence:
`outputs/supply-chain-3d/pylons/after/roads-analysis.json`.

Recommended integration:

1. **Read one authoritative presentation network.** Combine visible authored
   strokes with built generated runs only where the regular map displays them.
   Keep stroke/edge IDs, curve shape, width class, bridge metadata and unlock
   dependencies. The coordinate systems already agree: the 3D builder maps XY
   to XZ and subtracts its origin. No screen-coordinate tracing or pathfinding
   regeneration is needed. Clip this network to company coverage only after
   building its global connectivity; all-tiles mode uses the same network.
2. **Unify nearby endpoints before styling or tile splitting.** Use a spatial
   index and a true distance tolerance (1u preferred, 2u maximum), not coordinate
   rounding. Endpoint-to-endpoint joins share one deterministic node. For an
   endpoint beside the interior of a road, project it onto that segment and
   split the segment to make a real T-junction. Short overlapping, aligned runs
   can be deduplicated; nearby parallel roads should not simply be collapsed.
   Preserve curve tangents, bound the total movement of a cluster to 2u and
   reject joins across water, separated bridge decks or incompatible heights.
   Keep every accepted/rejected candidate in a review overlay. Apply these
   corrections in the supply-chain adapter without editing the regular map.
3. **Fit the road surface to 3D relief.** Feed the corrected curves into joined
   road geometry, retaining common junction heights and global casing/bed pass
   order. Build junctions before dividing the mesh among tiles; include a border
   overlap when baking so adjacent tiles cannot reopen seams. Existing
   `road_surface.gd` provides the joined-surface foundation but currently accepts
   straight segments and legacy widths. It needs polyline/width-class input,
   deliberate bend treatment and bridge decks. Reusing the original routes
   avoids inventing new mountain crossings, but heights 5+ are exaggerated here:
   inspect grades and add local road cuttings/ramps where needed. The regular
   router penalizes altitude and slope and bans levels 9+, not every mountain.
4. **Reconcile building placement and goods animation.** This is the largest
   dependency. The board reads regular-map building positions, then moves them
   to its own fixed slots; decorative houses also use that slot grid. Replacing
   only the roads can put them through buildings and leave goods travelling
   along invisible old streets. Prefer the imported roads as the fixed layout,
   seat buildings/decor beside them, and connect each entrance with a short
   access road that respects footprints and water. Use the resulting graph for
   visual shipment paths within the simulation's existing tile itinerary.
   Traffic should follow whole polylines by arc length, rather than respawning
   on each small sampled segment. Freight costs/capacities stay unchanged.
5. **Bake the result offline and invalidate locally.** Keep the compact road
   graph resident; the measured coordinates alone are only about 92KiB. Bake
   joined far geometry and per-tile medium/near surfaces from the same graph.
   Trees avoid roads and their shadows are baked into terrain, so affected
   vegetation, shadows and building bounds also need updating. The present
   cache includes the entire road list in a global key: split static source and
   local road dependencies before supporting frequent road construction, so a
   changed road refreshes its tiles and seam neighbours rather than invalidating
   the continent. Retain the far fallback while replacements load. Final mesh
   memory and pan timing need profiling; the small graph size alone does not
   predict tessellation or texture costs.

The useful first implementation milestone would be a geometry-only comparison
overlay plus the 1–2u candidate review. Building/entrance placement and visual
goods routing should follow before replacing the current roads and rebaking.
This is a moderate network-import task with a larger layout/animation follow-on,
not just swapping a road texture.

## Stoneshore authored-road pilot (2026-10-10)

`authored_region.gd` adapts the regular map's active authored document into the
3D board model. It is restricted to `RoadRegions.get_region("stoneshore")`:
Stoneshore, Old Quarter, Docks, Fields and Coast (`tile_4_9`, `tile_4_10`,
`tile_5_10`, `tile_5_9`, `tile_6_9`). Regular-map data, rendering and simulation
are read-only. Other supply-chain tiles keep the previous layout.

The Metal Magnate opening imports 43 visible strokes. Curves retain their
control geometry and class widths; the 2D ink wobble is deliberately not used
as physical road geometry. Unlockable strokes use the same infrastructure
flags as `AuthoredRoadVisuals`. Nine endpoint gaps of at most 2 world units
are joined. Endpoint-to-interior joins and at-grade crossings split the graph
before flow routing; separate elevation layers are not unified. Segment
clipping follows the hex edges rather than assigning whole strokes to a tile.
The previous joined road surface continues to render all bands on one height
field, using the imported road widths in the pilot.

`authored_road_profile.gd` samples the terrain along the imported roads and
finds bank-to-bank river crossings. The Stoneshore Coast crossing on
`r:untitled:16` receives a level raised deck, underside, abutments, guard rails
and eased land approaches. Deck clearance includes the full road width and
height-field sampling margin so a sloping bank cannot bury the railing. A
second crossing belongs to the continuation outside the pilot and is not
rendered there. No additional roads are path-found over mountains. At the
pilot boundary, imported roads may terminate where the adjacent tile still
uses the previous street grid; rolling the adapter into neighbouring regions
will bring those continuations across with the authored network.

Decorative `house` records (including towers) are temporarily removed in these
five tiles at every LOD, including their baked shadows and far sprites. The
ordinary NPC buildings use the regular map's actual footprint centres. Mesh
scale fits the footprint bounding box, keeping industrial works and smaller
facilities proportional. Ports use the Blender harbour asset at the authored waterfront placement
described below, rather than their small gameplay lots. Missing regular-map placements are not replaced with overlapping
buildings at the tile centre. NPC building selection opens the existing real
building panel; the far-LOD and 20-pixel picking rules still apply.

Regional road goods paths use the imported graph; pipes, rails and cables
keep their own routes. A road flow without a connected regional path is
excluded from the visual animation rather than drawn across unconnected
land (reported as `unrouted_flows` in the review output; zero in this opening).
This does not change stockpiles, shipments or the simulation.

The package refresh retains byte-equivalent mesh/shape/placement payloads
under their existing tile resource keys. Comparison includes prepared local
geometry and picking, not just terrain. The new far root references the
retained keys. Pruning occurs only after package validation succeeds. This
pilot retained 588 of 600 base chunks and 586 of 600 textures at each closer
LOD; changes around the five tiles also refresh neighbouring tree/shadow
coverage. The validated package is 1,203,584,349 bytes, 1,803 resources,
600 tiles. The first offline regeneration takes about 48 seconds; this is
build tooling work, not the packaged loading path.

Validation: 25 focused region checks and 85 existing 3D checks passed.
`review_stoneshore.tscn -- --continent-review --no-telemetry` opens a disposable
new game, verifies the region scope and NPC positions, captures far/medium/near
views and the bridge, and exercises the NPC detail-panel handler. Captures and
load reports are under `outputs/supply-chain-3d/stoneshore/` in the repository
root. This review does not save a game or change map-authoring data.

Fresh-process packaged verification on Godot 4.6.2 Forward+/Metal (M5 Pro):
Show all tiles ready in 2,938.756 ms; board construction 2,116.985 ms, including
353.891 ms loading the continent resource. Three bundled cache hits, zero
misses and zero writes. Final views exercise LODs 0/1/2, and NPC selection
opened the actual port building's detail panel. Final evidence is in
`outputs/supply-chain-3d/stoneshore/final/report.json`.


## Authored shoreline and waterfront ports (2026-10-10)

The old supply-board relief omitted sea band 5, which the regular map uses as
its beach/land base. Using only the narrower height-band footprint as land
put authored roads 224–226 on the western side of Old Quarter in apparent
water. `coast.gd` adds that base polygon to the 3D relief, with a separate
height-field cache and a rebuilt shoreline. Texture painting, water artwork,
trees and terrain now share that coast. The source 2D map and legacy relief
cache are not edited. Road control points stay authored; the fix restores
the missing coastal land instead of moving the road.

`harbour.gd` reads the active authored map's port-tagged specials and decor.
The four harbours use the existing detailed Blender docks asset: green gantry
cranes, container ships, tanker, tank farm, containers and office. The 3D-only
export removes its rectangular water and land backdrops, the land edge and
land-only road; the remaining approach road and markings stop at the quay.
The original Blender sprite builder and regular-map artwork are untouched.

The broad authored quay fixes the width and shoreline anchor; authored crane
axes set the seaward direction. Older ports without crane metadata derive
that direction from the narrow piers’ long edges, facing away from the main quay. The model's waterline sits at the game's sea
level, and its deck meets the bank. Horizontal and vertical fitting are
independent, and the harbour slides inland only as far as needed for its
three back-edge contact points to reach the coast. An additional water check
limits this inland adjustment before it would ground any ship; curved coasts
can therefore leave a quay corner overhanging water. A bounded 100u search
prevents runaway movement for inconsistent authoring. The model extends
across hex borders. All LODs use the shared Blender mesh with native mesh LODs
and shader detail reduction; only near/medium add the outer contour shell.
There are four harbour instances, each sharing the same 4,828-triangle static
asset. The original asset's remaining 1,824 triangles now form three separate
ships, described below; they are absent from the static mesh and its collider.

The scenery bake stores the fitted transform and visibility dimensions, not
copies of port geometry. Harbour metadata participates in the scenery key,
so changed anchoring/bounds cannot reuse an old pose. Exact collision is
built when cursor proximity enables it; vertices receive the full fitted
transform so physics never depends on a nonuniformly scaled collision node.
Far and medium fallback sprites and the normalized picking resource are also
rebaked from the water-free export.

Trade graph IDs (`port_port_stoneshore`) and building instance IDs differ.
Deduplication therefore uses the logical port tile, and the resulting
harbour points to the real `b_004` instance for its building panel. A harbour
is not clipped to its owning hex. Its full geometry expands visibility and
picking bounds; adjacent-tile tree clearance includes its yard. Procedural
houses and towers intersecting that footprint are removed from 3D scenery,
including across tile borders; real NPC/player buildings remain intact. The hollow
basin remains water rather than a rectangular building hitbox. All authored
ports use this placement rule; the road-network pilot remains limited to
Stoneshore's five tiles.

Validation: 43 focused regional/coast/harbour checks and 85 existing 3D checks
pass. The rendered review verifies the outer pier selects the owning port
across the hex border, the basin selects water, and the real port instance
opens its NPC panel. Captures and reports are in
`outputs/supply-chain-3d/stoneshore/blender-harbour-final/`.

Before the Blender harbour replacement, the shoreline package validated all
600 tiles and 1,803 resources with no errors: 1,113,293,594 bytes on disk. Offline refresh took 288.3 seconds.
A fresh-process Forward+/Metal review loaded Show all tiles in
2713.913 ms, including 1900.432 ms board construction and
306.031 ms loading the continent. All three reads hit bundled
resources; there were zero cache misses and zero runtime bake writes.

The final Blender harbour package validates all 600 tiles and 1,803 resources:
1,112,552,597 bytes, with no errors. Removing decorative overlap updated nine
medium and nine near shadow textures; the other 591 tiles at each tier were
reused. Package copying/validation took 33.815 seconds after scene preparation.

Fresh-process Forward+/Metal verification with the final Blender harbours: Show all tiles ready in 2706.051 ms, board construction 1914.442 ms, and continent resource loading 313.585 ms. Three bundled hits, zero misses and zero runtime writes. Final captures cover all four harbours; their ship-water probes all pass. Stoneshore’s cross-tile pier selects its owning NPC, and the open basin selects water.

### Animated harbour ships

`harbour_traffic.gd` animates the two container ships and tanker extracted from
the original docks builder. Exporting `port` also exports these components,
preserving the source hull dimensions, colours, berth positions and waterline.
The regular-map sprite and Blender source remain unchanged.

Nearest uses the original detailed vessels (1,824 triangles per fleet) with
contours. Medium uses simplified vessels (468 triangles, 74% fewer), retaining
the hulls, bridges and five broad cargo stacks without the fine deck equipment or
contours. Far has no ships, including in fallback harbour sprites, and skips
their pose updates. Components load lazily and share meshes across the four
ports; switching detail preserves the current position and heading.

Each 177-second cycle staggers departures, leaves the berths empty briefly,
then brings in replacement vessels one at a time. Arriving vessels turn beyond
the pier mouths and reverse into their original berths. Routes are prepared
once against the actual coast: the hull clearance probes must remain over
water. A restricted bay can use a straight astern approach; an unsafe berth
holds its ship in place. Ships fade at the outer end of their route using the
existing opaque screen-coverage shader, keeping hull/contour depth ordering
intact instead of alpha-blending the outline over the vessel. These are
ambient visuals driven by the existing animation clock, with no physics bodies
or simulation changes.

Ships are runtime overlays; terrain and scenery bakes contain only the static
harbour. The sprite baking tools exclude ship components. Future changes to
animation timing or routes therefore do not require continent rebakes.

Run `review_harbour_traffic.tscn -- --continent-review --no-telemetry` for
rendered near/medium/far captures and a full-cycle water-clearance check at
all four harbours. Add `--traffic-movie` to capture a complete cycle as PNG
frames. Output and the timing report go to
`outputs/supply-chain-3d/harbour-traffic/`. The `harbour_ships` test filter
covers the mesh partition, simplified LODs, turn clearance, continuous docking,
coast clipping, hidden far traffic and absence of physics bodies.

Validation: 18 ship checks, 43 regional/coast/harbour checks and 85 existing 3D
checks pass. The rendered review sampled every visible vessel throughout the
cycle at all four actual ports; all 12 can depart and turn without failing the
coast probes. Near/medium continuity and far hiding also pass. On M5 Pro with
Godot 4.6.2 Forward+/Metal, the warmed medium animation updates for all 12 ships
take 0.022 ms per frame on the CPU (600 samples; excludes GPU rendering).
Show all tiles was ready in 2992.248 ms, with three bundled cache hits, zero
misses and zero runtime writes. The refreshed static package validates all
600 tiles/1,803 resources and reuses every medium/near terrain texture.

### Authored roads beyond Stoneshore — first iteration

The follow-up branch `codex/supply-chain-road-rollout` builds on checkpoint PR
#200. `authored_region.gd` now imports every visible stroke from the active
regular-map document, including its infrastructure unlock conditions. Built
RoadNetwork geometry is the fallback outside authored coverage. The regular
map, simulation transport costs, save format and building tile membership are
unchanged.

Topology is resolved across the complete map before clipping into visible
hexes. `road_index.gd` uses deterministic spatial buckets for endpoint joins,
T-junction insertion, crossings and tile lookup. Endpoint movement is bounded
to 3u; joins across water, steep height differences, or different road layers
are rejected. The prepared network persists in the layout bake. Company and
continent frontage variants are retained separately, so opening one does not
discard the other.

Road profiles follow the display terrain, including exaggerated highlands.
Authored bridge markers supplement sampled river/open-water crossings.
`bridge_network.gd` completes connected strokes which meet in the water into
one bank-to-bank deck, with graph-based approach ramps. A crossing without
opposing dry banks, or spanning more than 400u, is reported for review rather
than given an invented half bridge. Road-profile samples are included in the
scenery cache and their small spatial indexes are restored on load; bridge
construction and height sampling are not repeated on a cached opening.

NPC and player buildings use their regular-map footprint centres, orientation
and fitted scale. Warehouses, supplier depots and the existing decorative
house/tower assets are placed beside nearby streets. All LODs share their
positions and rotation. Plot tests reject water, steep slopes, roads and
overlapping lots; impossible decorative plots are omitted. Foundations sample
the rotated footprint, and baked visibility/picking extents cover the rotated
asset. Lamps and tree clearance use each authored road's actual width.

Dry access roads join building entrances to the road graph, splitting the
receiving street into a T-junction. Goods animations follow that graph; a
missing connection suppresses its visual flow instead of drawing over land
or water. This does not change deliveries in the simulation. The initial
continent review imported 848 strokes / 12,264 clipped segments, joined 136
nearby endpoints, restored 686 decorative assets, omitted 79 unsuitable plots,
and made 1,059 access roads. Forty-seven non-decorative entrances need a more
capable detour or an authored adjustment. Exact authored decorative building
polygons, density tuning and engineered mountain cuttings remain further art
iterations.

Use `review_stoneshore.tscn -- --continent-review --road-rollout --no-telemetry`
for four regions at all three LODs, including coastal and mountain terrain.
The report includes frontage exceptions and unfinished water crossings. The
package builder now carries prepared road profiles in its scenery resource.
The first uncached review took 80.1 seconds including new baking; it is not a
cached-load benchmark. Packaged-load measurements are recorded below.

Validation: 35 focused rollout assertions cover bounded/spatial joins,
cross-tile seams, safe frontage, connected access roads, identical cached
placements, joined bridge halves and goods routing. The broader supply-chain
suite passed 1,521 assertions with three existing asset-version failures and
no script errors. The parse sweep passed all 847 checked scripts.
The checkpoint already lacks oil/fracking well atlases and has stale source
hashes for farm, water-pump, forest and desalination atlases. Animated ship
components are intentionally excluded from those standalone building checks:
they use near/medium meshes and do not render at far LOD. The final 100-turn
end-to-end run passed 723 checks.

The final road layout has 189 bridge records, including 33 completed across
joined strokes. Thirty-five water-connection components still lack suitable
opposing banks; these and the 47 entrance exceptions remain the next targeted
art pass. Four visual goods paths cannot currently find a connected route.

A first packaged-load profile took 7.05 seconds despite three bundled hits
and zero misses/writes. Instrumentation attributed about 1.6 seconds each to
infrastructure mesh construction and live building-shadow geometry. Both now
persist as optional mesh resources in the scenery bake. Loading older bakes
can generate those additions once; the production package carries them.
Infrastructure cache identity includes line geometry, lighting state and
pylon anchors. Road indexing remains lazy for actual generation/repair.
Cache tests check zero terrain samples, retained traffic metadata, no duplicate
shadows and invalidation when pollution lighting changes.

Higher-detail building assets now follow tile residency too. Remote NPC/player
buildings keep their far cards until their tile is loaded, instead of preparing
medium/near assets for the whole continent. Panning and global LOD handovers
refresh that choice while retaining a far fallback outside the detail area.

Final fresh-process Forward+/Metal result on M5 Pro: **4,899.313 ms** from
Show all tiles to ready, including **4,075.615 ms** board construction.
The continent resource took 354.563 ms; cached infrastructure setup took
7.448 ms and cached frontage fitting took 96.911 ms. All three cache reads hit
bundled resources, with zero misses and zero runtime writes. This is within
the five-second target on the measured machine, with limited headroom;
standing-object creation still accounts for 1,335.299 ms.

The complete package validates 600 tiles / 1,803 resources, with zero errors,
at **1,034,937,774 bytes**. The prepared scene meshes added 1,007,641 bytes
without regenerating any medium/near terrain textures. Final captures and
metrics are in `outputs/supply-chain-3d/road-rollout/resident-assets/` (four
regions, each at far/medium/near). Roads, coast crossings, rotated decoration
and NPC placement were checked in those captures.

### Three-unit junction cleanup

The supply-chain adapter now joins compatible road ends within 3u, including
ends close to an existing internal vertex. It trims dead-end chains shorter
than 3u back to their junction, measuring the entire chain along the road.
This runs before snapping (so an overshoot cannot turn into a tiny kink),
after snapping, and after fitting building access roads. It operates on full
paths before tile clipping, keeping bridge profiles and all LODs consistent.
The regular-map document and simulation network remain unchanged.

Short links between two junctions, building doors, isolated roads, and separate
elevation layers are preserved. Proximity alone does not merge parallel
stretches. Shared endpoints bypass intersection calculations: nearly collinear
float32 samples at continent coordinates could otherwise generate tiny false
branches. Cached frontages retain the complete cleaned paths, including any
street trimmed at a newly added access junction.

`audit_road_junctions.gd` runs headlessly against the bundled layout. It reports
near endpoints, close parallel stretches, and short junction tails. Add
`--verify-cleanup` to check that another cleanup pass leaves the layout intact.
`review_stoneshore.tscn -- --continent-review --junction-review --no-telemetry`
also audits the live map against its terrain and captures three close junctions
plus Stoneshore at far, medium and near zoom.

Validation: all 55 road assertions pass, including a float32 regression using
actual authored curve samples and a cached driveway-junction trim. The broader
supply-chain suite passes 1,541 assertions with the same three pre-existing
sprite-version audit failures and no script errors.

The final 600-tile audit removes 64 authored overshoots plus one created by an
access-road junction. Both the authored graph and the graph including building
access now have zero unwanted tails under 3u; three repeated trim passes make
no further changes. Nearby unmatched authored ends fall from 133 in the prior
bake to 54: 39 parallel approaches, 11 water/height exclusions, and four tails
whose actual road length exceeds 3u despite their perpendicular gap being
smaller. There are 22 pairs of close parallel stretches, retained for separate
review. Building-door endpoints remain protected.

The refreshed package validates all 600 tiles / 1,803 resources with no errors.
A fresh Forward+/Metal opening measured 5,263.634 ms to ready (4,349.911 ms board
construction), with three bundled hits, zero misses and zero runtime writes.
This sample is slightly above the five-second target. The final six captures
and live terrain-aware audit are in
`outputs/supply-chain-3d/road-junctions/final/`.

### Farm plots without asset stretching

Authored farm lots now keep the standard 72u asset scale regardless of plot
dimensions. Renderer-only `farm_building` derivatives retain the barn, silos,
glasshouse and yard props; the complete farm GLBs and Blender builder remain
unchanged. Both player and NPC farms use the same path. Selection follows the
building core rather than giving the whole field a building hitbox.

`farm_fields.gd` fills each authored polygon with a repeated crop cell cut from
the existing field: the original 0.25-unit plant interval, 0.61-unit row pitch,
two planted ribbons, bed and (at near zoom) leaves and irrigation pipe. Copies
use a uniform scale and follow the ground. Boundary cells are omitted rather
than stretched; brown soil fills the margins and spaces between rows. Barn
yards, neighbouring barns, road clearances and water are excluded from planting.

Near uses the detailed crop component; medium omits leaves and irrigation.
Their import settings disable automatic mesh LODs, which otherwise prematurely
collapse small instanced components. Internal cell-edge ink is removed so copies
meet without drawing a rectangular grid. Far merges those placements into thin
crop strips, joined with earth into the single continent props mesh. Medium/near
soil and instance transforms live in the per-tile base bake and follow the same
residency/10-second eviction policy as other local detail. Fields add no physics.

Export derivatives with `export_models.py -- farm_building farm_crop_cell
farm_crop_cell_medium`, then bake far/medium/lighting for the three
`farm_building_lvl*` keys. `review_stoneshore.tscn -- --continent-review
--farm-review --no-telemetry` captures three plot shapes at all three LODs plus
an oblique orbit. `review_farm_components.tscn` compares near, medium and an
instanced near crop cell. Focused tests cover fixed farm scale, repeated cells,
ground following, plot edges, concave notches, yards, roads and the LOD imports.

Validation: 14 farm assertions pass; the full supply-chain suite reports 1,555
passes and the same three pre-existing asset-version audit failures, with no
script errors. The parse sweep checks 851 scripts with zero failures. All 600
tiles / 1,803 packaged resources validate. Total map bake size is 1,041,947,156
bytes (5,795,249 bytes above the road-junction package); existing medium and
near terrain textures were reused. A fresh packaged opening reaches ready in
4,742.854 ms (3,768.532 ms board construction), with three bundled hits and zero
misses or writes. This is one measured run, not a guaranteed load-time ceiling.
Ten final views and timings are in `outputs/supply-chain-3d/farms/final/`.

### Continuous road paint

The fragmented paint visible beside the farms had two separate causes: polygon
triangulation lost winding precision for thin strips at continent coordinates,
and every sampled/split segment restarted its dash pattern. Triangulating each
clipped polygon relative to its grid cell fixes the missing paint triangles.
`road_markings.gd` now walks connected carriageways across curve samples,
authored stroke boundaries and tile borders, retaining one 8u-on/8u-off phase.
Mitered offsets join the paint at bends; true junctions retain a clear area.

Duplicate edges share one paint layout. Near-coincident parallel overlaps within
3u defer to the wider road (then a deterministic source order), only for the
shared stretch. Separate carriageways and different elevation layers retain
their own markings. This is visual deduplication: it does not alter the authored
network or regular map. Level 2 uses a dashed centre line; level 3 uses a double
centre line and four dashed lane dividers for six lanes.

The final packaged 14,326-segment layout contains 526 duplicate edges; the paint
pass also suppresses 451 near-overlap pairs. Preparing the layout took 1,569 ms
in a headless audit; this work is baked, not repeated when loading the package.
`review_road_marks.tscn` captures both isolated flat roads and cached terrain
roads, with optional paint-only images, and writes the full-map overlap audit.
The 17 focused assertions cover coordinate precision, short samples, tile
boundaries, reversed and partial overlaps, shallow crossings, bridges, bends,
junctions and loops. The full suite has 1,572 passing assertions and the same
three existing asset-version failures; the parse sweep checks 854 scripts with
zero failures.

The regenerated 600-tile / 1,803-resource package validates without errors and
totals 1,051,120,361 bytes (+9,173,205 bytes). All 1,200 medium/near textures are
reused. A fresh process reaches the all-tiles view in 4,749.634 ms, including
3,800.362 ms board construction, with three bundled hits, zero misses and zero
writes. Ten in-game far/medium/near and orbit captures are in
`outputs/supply-chain-3d/road-marks/final/`.

### Stoneshore offices and public spaces

`civic_builder.py` adds five renderer-only assets using the existing Blender kit:
a long three-storey office, a stepped office with a recessed fourth floor, a grey
four-storey L-shaped block, a pocket park and a paved fountain plaza. The offices
have framed windows on every elevation, entrance canopies, parapets and rooftop
plant. Small facade and paving details avoid heavy ink. Parks include cross paths,
lawns, trees and benches; plazas include paving joints, planters and seating.

`civic_layout.gd` seeds infill only in Stoneshore's three urban tiles, before the
existing frontage fitting pass. Original buildings take priority. Additional plots
must clear roads, neighbouring footprints and water, with at most 6u ground relief
for buildings or 2u for public spaces. Entrances face the street. Public spaces do
not create asphalt driveways, window lighting or building-sized contact shadows.
These are decorative objects, with no new simulation buildings or physics bodies.

The final layout adds 44 offices, five L-shaped buildings, two parks and three
plazas: 13 additions each in Stoneshore and Old Quarter, and 28 in the Docks.
All five assets have 64px far and 128px medium colour/depth atlases, medium lit
variants, and near meshes. Far sprites use the lighter decorative outline settings.
The existing per-tile residency and 10-second eviction rules still apply.

Validation: 13 focused assertions pass, including placement clearance, wet-ground
exclusion, determinism, cached restoration and all five assets' LOD resources.
The full suite reports 1,585 passes and the same three pre-existing asset-version
audit failures. The parse sweep checks 857 scripts with zero failures. The package
validates 600 tiles / 1,803 resources without errors and totals 1,054,474,309 bytes
(+3,353,948 bytes over the road-paint package). A fresh packaged all-tiles opening
reaches ready in 4,891.896 ms, including 3,830.634 ms board construction, with three
bundled hits, zero misses and zero runtime writes. This is a single measured run.

`review_civic_assets.tscn` captures front/rear model galleries.
`review_stoneshore.tscn -- --continent-review --civic-review --no-telemetry`
captures far, medium and near views plus individual examples. Final captures and
timings are in `outputs/supply-chain-3d/civic/final/`; model galleries are in
`outputs/supply-chain-3d/civic/assets/`.

### Civic scale and outline calibration

The first civic pass used footprint widths of 43u/46u. Because each family is
normalised by its own source footprint, its nominal 1.1-unit Blender storeys
became only 5.8–7.9u after placement, versus 11.8u for full-size existing houses
and towers. Exported civic assets now record their normalised `storey_height`;
`civic_layout.gd` chooses a uniform scale giving a 12u storey. The resulting
footprints are about 71u for offices and 70u for the L block. Frontage fitting
omits crowded civic building plots instead of reducing their scale by 20%.
Building shapes take turns at the available plots, starting with the broad L,
before public spaces fill gaps. This prevents one shape consuming every suitable
site. Each urban tile accepts at most one park and one plaza; their sizes remain
48u, so enlarging offices does not accidentally fill the city with repeated fountains.

The new offices also lacked the outer contour meshes used by the existing
housing. They now use that same silhouette path. Their source stroke width is
calibrated per storey (the civic source module is 1.1u versus housing's 0.45u),
so the larger Blender units do not produce thinner world-space ink. The existing
lighter far-LOD outline settings continue to apply. Window trim is half as thick
and a muted grey; stringcourses and pilasters use the facade tone. Window faces
remain uninked, as on the existing housing.

`review_civic_assets.tscn -- --style-comparison` renders existing terraces and
flats beside the new buildings at their actual relative scales, with front/rear
views in `outputs/supply-chain-3d/civic/style/`. The directory also contains a
numeric scale audit. All 14 civic checks pass, including preserved storey scale
after frontage fitting and cache restoration; the full suite has 1,586 passes
and the same three existing asset-version failures. Far, medium and lit atlases
are refreshed. The 600-tile / 1,803-resource package validates without errors.
The final Stoneshore layout retains three long offices, one stepped office, four
L blocks, three parks and three plazas. Fewer of the larger infill footprints fit
than in the original miniature-scale pass. All three building shapes are visible
in the final game, with captures at all LODs in
`outputs/supply-chain-3d/civic/style-final/`. A fresh cached all-tiles opening
measures 4,774.665 ms, with three bundled hits, zero misses and zero runtime writes.

### Modular office frontage

The long office now fits by choosing 4–10 window columns in one-column steps.
The L block independently chooses 4–8 columns along its street wing and 2–4
additional columns in its return wing. A bay is 0.9 source units, or about
9.82 map units at the common 12u storey height. Windows, floor heights, wing
thickness, entrances and outline widths retain their size. The L has a single
concave wall/roof envelope, avoiding overlapping geometry where its wings join.

Frontage fitting tries the largest whole-bay assembly that clears roads, existing
lots, water and excessive relief. Sites below the minimum size are omitted. The
seven long and fifteen L variants are generated offline, with shared near meshes,
contours, far/medium colour and depth atlases, and medium lighting atlases. No
runtime mesh generation is needed. The placement cache stores the chosen asset,
bay counts and pad; its signature includes the module catalogue so geometry
changes invalidate old fits. Tile and continent bakes include the selected asset.

All 23 civic assertions pass, including narrow/wide plots, independent L-wing
extension, constant storey/window pitch, cache restoration and LOD resources.
`review_civic_modules.tscn` renders front/rear comparisons at a common scale in
`outputs/supply-chain-3d/civic/modular-assets/`. Add `--modular-review` to the
Stoneshore civic review to capture the shortest and longest placed examples.

The final pilot places nine modular long offices, nine modular L blocks and one
stepped office, plus two parks and two plazas. It uses nine different modular
sizes across the three urban tiles. Far, medium and near captures are in
`outputs/supply-chain-3d/civic/modular-final/`. The refreshed 600-tile package
validates all 1,803 resources and totals 1,053,343,125 bytes. A fresh process reaches
all-tiles ready in 4,984.234 ms (3,834.773 ms board construction), with three bundled
hits, zero misses and zero runtime writes; this is a single run. The wider suite
reports 1,595 passes and the same three existing asset-version audit failures.

### Farm road clearance and intermediate 3D relief (13 October 2026)

Farm soil now subtracts the same final road corridors that exclude crop cells:
road casing plus a 1u verge, including bends, junctions and rounded dead ends.
This fixes soil (lifted 1.25u) covering lower road surfaces. Tunnel segments do
not remove fields. A short enclosed segment is partitioned into simple polygons
so a hole is not accidentally filled by triangulation. Far crop ribbons reserve
their full pitch, and medium/near crop instances retain their source scale.

The 3D board adds half-level terraces from 1.5 to 9.5. The regular map's authored
hill JSON, navigation bands, whole-level summit heights and coastline are kept.
`tools/supply_chain_3d/bake_half_relief.py` derives contours midway between adjacent
authored bands using distance transforms, ignoring isolated hills without a
higher contour. It writes `data/supply_chain_half_relief.json` (438 contours,
1.22 MB), consumed only by the 3D adapter. Existing mountain amplification applies
after interpolation; for example, level 4.5 stands at 88u between L4 at 77u and
L5 at 99u. Terrain colours interpolate through the same half levels. Original
paint order is retained, including valleys painted over mountains.

`coast.gd.ground_for` defaults to the original integer-band sampler for depot
seeding; `board.gd` explicitly opts into intermediate terrain. These samplers
have separate caches, preventing a visual terrain change from moving regular-map
depots. The shared 2D sampler and source hill data are not edited.

To refresh the derivative (Python with NumPy and SciPy), then the production
package:

```bash
python3 tools/supply_chain_3d/bake_half_relief.py
python3 tools/supply_chain_3d/bake_half_relief.py --check
```

Follow the full package build/validation/fresh-start procedure in
`docs/load-time-bakes.md`; contour data, sampler and palette changes participate
in terrain fingerprints. Farm clearance participates in scenery/detail keys.
A focused capture alone does not refresh production assets.

Focused regression commands:

```bash
godot --headless --path . tests/test_runner.tscn -- --tags supply_chain_3d --test farm
godot --headless --path . tests/test_runner.tscn -- --tags supply_chain_3d --test half_relief
```

These cover projected triangle overlap with road surfaces, enclosed holes,
tunnels, explicit crop LODs, actual fractional-height terraces, unchanged
whole-level summits, isolated depot sampling and derived-data freshness.


## Standard residential height — 13 October 2026

`building_scale.gd` fixes each ordinary `house_lvl1/2/3` asset at 50u from
its base to its roof, independent of the fitted footprint. Width, depth,
placement and foundation clearance stay as authored; towers, offices, public
spaces and playable/NPC facilities keep their existing heights. The rule only
belongs to the 3D supply-chain renderer.

The same scale feeds live meshes and contours, medium cards, continent
MultiMeshes and visibility bounds. The sprite shader transforms the source
image plane and depth ray through the full instance basis and selects the
atlas pitch in local space, so independently scaling height does not merely
stretch a screen-facing image. Uniformly scaled trees and other assets retain
their original projection. Existing colour/depth atlases remain reusable.

A separate `buildings` bake fingerprint refreshes scenery frames, continent
transforms and visibility metadata without invalidating road engineering,
per-tile terrain textures or prepared local detail. Use the production package
baker and fresh-process checks described in `load-time-bakes.md`.


## Rail vegetation and medium track detail — 13 October 2026

Vegetation clearance uses `rail_vegetation.gd`, prepared from the same curved,
graded corridor profiles and tunnel cutoffs as the visible railway. It reserves
tree-canopy clearance beside exposed track, ballast embankments, open cuts,
road bridges, portal approaches/collars and depot yards. Fully covered tunnels
can retain vegetation. The clearance index also excludes close ground clutter.

Rural rail corridors propose two staggered rows on both sides, with a third on
some stretches, 13u apart along the line and 10.5u between rows. Small broadleaf
and occasional fir trees use 50% of their initial size (8.5–10.5u projected
height); the denser rows keep a 25u first-row setback. Other trees deterministically
choose 100%, 75% or 50% of their original size. Existing trees within the rail-side
belt also use only 50%. This scales the complete tree, including its shadow,
canopy clearance, sprite and near mesh. Rows follow curves;
bridges and hidden sections do not generate candidates. Existing fields,
buildings, roads, pipelines, rivers, nearby trees and steep ground can interrupt
planting. No rural rows are added inside urban tiles. Positions are deterministic
and the accepted placements/shadows are shared by all LODs.

Medium/far rail linework now uses continuous matte track bands. The old bright
steel heads, sleepers and tiny switch fittings were geometry rendered at every
zoom, not a reflective material; their subpixel detail produced the sparkly,
pixelated appearance. The detailed mesh is retained for near LOD, while ballast,
embankments, bridges and tunnel mouths remain at every tier. These two detail
meshes have nonoverlapping LOD ranges.

Cold generation builds railway art once before placing trees, then reuses those
meshes in infrastructure. Scenery cache lookup happens before this work. The
saved scenery includes the clearance index and both rail detail meshes. Changes
to vegetation also invalidate prepared tile tree cards/clutter; unchanged terrain
geometry and matching medium/near texture resources can still be reused by the
production baker. Regular-map assets and its rendering code are untouched.

The revised production package is installed and independently validated: 600
tiles, 1,806 resources, 1,452,283,259 bytes. Fresh-process review matches the
preview at all three zoom levels and in Stoneshore/Capital Port, with current
fingerprints, 343 bundled reads and no runtime writes. It counts 22,576 trees:
20,375 at 50%, 1,140 at 75%, and 1,061 at 100%. The 17,892 rail-row trees span
158 rural tiles and all use 50%; clearance and rail-side sizing audits find no
violations. The same-camera `rural-rail-old-linework` capture deliberately forces
the detailed rail mesh at medium zoom to isolate the previous sparkle.

Focused vegetation/size/LOD tests pass 24 assertions. First opening measures
2.56 s, continent loading 0.60 s, and Begin 24.98 s in a fresh process with warm
OS filesystem caches. Full preparation during loading is 8.69 s; the startup
probe uses 100 bundled reads and no writes. See `docs/load-time-bakes.md` for
package generation counts and measurement limits; captures and reports are in
repository-root `outputs/supply-chain-3d/rail-vegetation/`.
# Continuous water geography and closer rail planting (13 October 2026)

The 3D board uses `data/supply_chain_water.json` for coast/lake geometry. The
regular map continues to read its original authored geography. Global water
shapes and shoreline ribbons are calculated before tile clipping, so a clipped
polygon closing edge cannot become an artificial beach across a lake.

Coasts vary within 20u outward and 5u inward, including 82 small offshore islets.
Lakes can extend across tile boundaries on the same 3D plateau. Their masks
exclude other land levels and leave at least 1u of dry terrain at the plateau
edge. The baked minimum is slightly larger to absorb polygon simplification and
float32 coordinate conversion. Constrained boundaries vary inward as well.
Banks are 3u high in displayed space, including under mountain amplification.
Lake water has flat normals and is protected from road/rail earthwork warping.
The outer map's finite tile boundary remains the board boundary.

`water_geography.gd` reads the prepared polygons, indexes lake and shoreline
queries, and partitions cold-generated terrain along the lake edge and lip.
Production terrain textures, meshes and visibility bounds contain the result;
normal loading does not run Python/Shapely or regenerate shorelines.

To regenerate geography after changing authored hills, 3D plateau/rise inputs
or the water generator:

1. Run `godot --headless --path . tools/supply_chain_3d/export_water_inputs.tscn`.
   It exports actual plateau/rise boundaries and original authored lakes to
   `/private/tmp/water-inputs.json`. The full map review with
   `--audit-transport` exports the transport audit from a real loaded game.
2. Run `python3 tools/supply_chain_3d/bake_water_geography.py` in an environment
   with NumPy and Shapely installed, then
   `python3 tools/supply_chain_3d/verify_water_geography.py`.
3. Run the water and rail vegetation tests, render the focused water check or
   full map review, and regenerate/validate/install the production package using
   `docs/load-time-bakes.md`. Do not stop after the focused preview.

Rail-side trees remain 50% size, spaced 13u along each row. Their first-row
canopy-to-track gap is now one third of the former gap, measured from the actual
canopy and track edge. Rows on both sides use independent phases, starts and
ends. Earthwork toes, bridges, portals, depot yards and other existing clearance
rules still take precedence.

The read-only transport audit found 48 same-height candidate overlap runs over
10u, plus 324 elevated runs classified separately. Railway route cost currently
avoids buildings and water but lacks road corridor clearance; crossing treatment
does not resolve parallel footprints. Recommended repairs and exact coordinates
are in `../outputs/supply-chain-3d/water-greenery/transport-overlap-review.md`.
No dedicated overlap-repair or rerouting rules are part of this change. The
transport bake was regenerated against the updated water/terrain. The final
audit uses a fully loaded game's mine/depot/river/navigation context and the
current installed transport key.

### District building additions (13 October 2026)

`tools/supply_chain_3d/district_builder.py` extends the existing civic Blender kit
with four decorative families. No simulation catalogue entries are added.

- `civic_u_office`: a 20-storey central bar and 12-storey wings around an open
  U-shaped courtyard. The 12u floor module produces a 90.6u-wide footprint and
  a 246.4u total height including roof plant. Lower roofs have garden planters.
- `civic_semi`: a symmetrical pair of brick homes with two-storey canted bay
  windows, paired central doors and chimneys, and a shared pitched roof. The
  footprint is 64u × 43.47u and the complete asset retains the 50u house height.
- `civic_bauhaus`: a pale industrial hall inspired by the supplied factory
  reference, with blue gridded glazing, a flat roof, loading doors and twin tall
  chimneys. It is decorative; it produces no goods or pollution.
- `civic_commercial`: four floors with wide shopfronts, green awnings, a recessed
  upper storey and a planted roof terrace. The frontage has its own glazing,
  without the office windows showing through it.

The new families join the Stoneshore urban infill mix. They use the existing
road/water/lot/relief clearance checks and keep their physical scale when fitting.
Each tile admits at most one U tower, one factory, two shopping blocks and four
semi-detached pairs; unsuitable candidates are omitted. Original buildings still
take priority over infill. The large courtyard footprint is reserved conservatively
as a rectangle, keeping other buildings out of its courtyard.

All four have near meshes, contour meshes, cached picking shapes, 64px far colour/
depth atlases and medium colour/depth/lighting atlases. Medium cells are 128px,
except the tall office's 192px cells. Far outlines use the existing softer civic
settings. The office cap is explicitly triangulated around its concavity, and a
geometric regression checks that the exported courtyard remains open to ground.

Regenerate selected assets with background Blender:

```bash
blender -b --factory-startup --python tools/supply_chain_3d/export_models.py -- \
  civic_u_office civic_semi civic_bauhaus civic_commercial
```

Import headlessly, then run `bake_far_sprites.tscn` (far and `--medium`) and
`bake_medium_lighting.tscn` with those four level-1 `--asset-keys`. Use
`review_district_assets.tscn` for front, rear and overhead model previews.
`review_current_map.tscn -- --continent-review --district-review` also checks that
every new family fits a real plot and captures individual examples.

The civic checks pass 30 assertions, covering deterministic placement, clearance,
cache restoration, all LOD resources, storey/house scale and the open U geometry.
Artifacts are under repository-root
`outputs/supply-chain-3d/district-buildings/`. Production package validation and
fresh-process timings are recorded in `docs/load-time-bakes.md` after the bake.

### Stoneshore half-scale trial (13 October 2026)

The current review scope is **only five tiles**: Stoneshore (`tile_4_9`), Old
Quarter (`tile_4_10`), Docks (`tile_5_10`), Fields (`tile_5_9`) and Coast
(`tile_6_9`). The user has paused full-continent baking until explicit approval.
`--stoneshore-review` restricts the model before authored roads, frontage,
scenery and LOD generation. It is not merely a screenshot crop of a full bake.
The regular map is unchanged. Without this review flag, the normal coverage
setting still works; the unapproved continent package has not been refreshed.

`stoneshore_trial.gd` replaces the pilot's decorative buildings at 50% model
scale, including height. Houses and semis therefore become 25u tall in this
trial; their shared default remains 50u elsewhere. The same scale drives
meshes, both sprite tiers, shadows and visibility bounds. Modular offices still
extend by whole window bays at the new half-scale window/storey spacing.
Gameplay buildings (including NPCs and ports), trees and public-space assets
retain their sizes.

The measured baseline had 40 decorative buildings, excluding parks/plazas and
gameplay buildings. The trial places 80, distributed as follows:

| Tile | Before | Trial |
| --- | ---: | ---: |
| Stoneshore | 14 | 24 |
| Old Quarter | 13 | 22 |
| Docks | 13 | 22 |
| Fields | 0 | 6 |
| Coast | 0 | 6 |

Urban interiors use offices/commercial blocks; the edges facing rural tiles
use houses, apartments and semis. Both rural tiles use residential buildings.
A single Bauhaus works is reserved before ordinary infill, on dry land within
180u of the harbour's **shore anchor**, not its offshore pier centre. Its front
entrance has an unglazed bay; loading doors also have no overlapping glazing.
Both stacks are at the far left. A third floor occupies the right third only.

Review (from the Godot project directory):

```sh
AGENT_GODOT_WINDOW=1 godot --path . --log-file /private/tmp/stoneshore-review.log tools/supply_chain_3d/compare_stoneshore.tscn -- --stoneshore-review --continent-review --density-review --no-telemetry --comparison-output=res://../outputs/supply-chain-3d/stoneshore-half-size/after
```

The review asserts the five-tile scope, the 80-building distribution, half-scale
markers, and the factory's presence/distance. `--stoneshore-baseline` disables
only the density trial for a control render. Archived before images preserve
the earlier factory shape; rerunning a baseline uses the current asset meshes.

Scoped production package:

```sh
AGENT_GODOT_WINDOW=1 godot --path . --log-file /private/tmp/stoneshore-package.log tools/supply_chain_3d/bake_continent_package.tscn -- --stoneshore-review --continent-review --no-telemetry --prune
```

This writes `assets/supply_chain_3d/stoneshore_trial_bakes/`, with base, medium
and near resources for five tiles plus the shared far bake. It never overwrites
`assets/supply_chain_3d/bakes/`. The bake entry point currently rejects a full
continent run and rejects directing the scoped package at the full package.
Only remove that pause after the user approves a continent rebake.
Use `--trial-cache-directory=/private/tmp/<fresh-directory>` on a new review
process to verify bundled loading independently of the generation cache.


### Stoneshore neighbourhood density trial (13 October 2026)

This supersedes the 80-building half-scale trial above, within the same five-tile
scope. `district_blocks.gd` offsets deterministic seeds from the actual road
network, partitions the urban area with Voronoi cells, and connects safe cell
edges back to authored road centrelines. Unattached components and dangling
stubs are removed. The added streets have an 8.4u carriageway, two lanes total,
and a single thinner dashed centre divider. They are visual neighbourhood
streets only; the regular map and simulation routing are unchanged.

Streets reject water, height steps, gameplay building footprints, harbour quays,
rail corridors and depot yards. Harbour frontage is reserved for the existing
Bauhaus works. Rail clearance uses the curved rendered corridors rather than
straight chords between rail waypoints. The deterministic plan and frontage fits
are stored in the layout bake; valid lookups precede expensive generation.

The selected layout has 102 decorative buildings (previous trial: 80): Stoneshore
29, Old Quarter 24, Docks 33, Fields 8 and Coast 8. This includes 40 semidetached
buildings and 18 compact apartment blocks, alongside offices, commercial blocks,
two stepped U offices and the harbour factory. All retain the half-scale
building treatment. Density targets are caps: a building is omitted if no dry,
clear, sufficiently level frontage fits. They are not quotas that override
clearance.

Residential zoning includes every nonurban neighbouring tile, including sea-facing
edges, and excludes the 240u harbour precinct. Urban interiors favour apartments,
offices and commercial buildings. There are ten public green spaces: two wooded
ponds, four groves, three parks and a plaza. Ponds and groves have native Blender
geometry plus prepared far/medium/near representations. Pond parks are flat
ornamental assets on plots with at most 0.8u relief, not changes to the terrain's
hydrological lake network.

Use the existing scoped bake command above. Final images, counts, zoning checks
and fresh-process cache timings are under
`outputs/supply-chain-3d/stoneshore-neighbourhood/final/` at repository root.
The full-continent package remains paused and has not been refreshed.


### Semidetached proportions (14 October 2026)

The complete semidetached pair now spans 2.5 individual terrace homes and is
10% taller than the standalone terrace reference (`house_lvl1`, a row of three
homes). `BuildingScale.semi_side()` derives its width from that three-home row,
so the pair occupies five-sixths of the row's frontage. At Stoneshore's 50%
decorative scale, the terrace row is 36u wide / 25u tall and the pair is 30u
wide / 27.5u tall (previously 32u / 25u). Height includes the asset's chimney
bounds. The full-scale values are 60u / 55u.

The shared building transform carries these proportions through meshes,
contours, sprite tiers, shadows and visibility bounds. Frontage fitting uses
the revised width/depth before placing buildings. Existing reusable meshes
and sprite atlases remain valid; only their map composition needs rebaking.
The regular-map assets and player/NPC sizes are unchanged.

`review_housing_scale.tscn` renders the old pair, the three-home terrace and the
revised pair with the same camera. Images, dimensions and scoped-package
verification are in `outputs/supply-chain-3d/stoneshore-semi-scale/`.


### Urban sidewalks and exact decorative footprints (14 October 2026)

Paved urban streets now have 2u sidewalks, including the Voronoi side streets.
Their continuous paving and outer trim use the road surface's shared height
field and junction triangulation. Asphalt overlays the footway union at
junctions. Rural roads, unpaved tracks, access driveways and tunnels do not gain
sidewalks. These changes belong only to the 3D supply-chain renderer.

Decorative frontage, obstacle reservation, vegetation clearance and foundation
skirts use projected model silhouettes, preserving L/U concavities and disjoint
parts. The former 4u decorative exclusion margin is replaced with a 0.01u
numerical tolerance; the street-facing position clears the sidewalk by 0.35u.
Explicit farm/harbour/public-space parcels retain their own boundaries. Player
and NPC transforms are unchanged in the five-tile verification.

The prepared `assets/supply_chain_3d/building_footprints.json` contains silhouettes
for 34 existing assets and hashes of their source GLBs. After changing those
models, regenerate it before the scoped production bake:

```sh
godot --headless --path . --log-file /private/tmp/building-footprints.log \
  tools/supply_chain_3d/bake_building_footprints.tscn -- --no-telemetry
```

Projection excludes low courtyard paving and furniture, while retaining the
building silhouette, including overhangs. Multiple parts are authoritative;
legacy `footprint` consumers receive the largest part. No geometry projection
runs during normal map loading. The metadata and helper scripts participate in
road/building fingerprints; placement polygons also travel in cached layouts.

The refreshed Stoneshore trial has 133 decorative buildings (previously 105),
ten green spaces, 40 semidetached pairs and 224 sidewalk-bearing road segments.
The rendered-model audit finds no decorative building/building overlaps or
street/sidewalk intrusions. Scope remains the five Stoneshore tiles; full
continent rebaking remains paused. Images and audit results are under
`outputs/supply-chain-3d/stoneshore-sidewalks/` at repository root.


### Street-front infill and decorative access removal (14 October 2026)

Decorative buildings no longer emit asphalt driveways or add receiving-road
junctions. Their exact street-facing silhouette sits 0.1u beyond the sidewalk.
Gameplay structures retain their normal access-path handling; the regular map
and simulation layout are unchanged.

Stoneshore now seeds 34 landmark/variety buildings, reserves its ten public
spaces and harbour factory, then fills measured gaps along existing streets.
U-shaped office landmarks fit before ordinary infill. The placement pass tries
existing apartment, commercial, modular office and residential assets, then
quarter-turn orientations for narrower plots. It preserves their established
half-scale proportions, exact silhouettes, zoning and terrain/transport checks.
Successful generated records are stored in the frontage cache and restored
before any new fitting work. No asset/model/atlas rebake was needed.

The metric samples both street sides at no more than 4u intervals, weighted by
arc length. A facade must intersect the outward 10u frontage ray. Access paths
and tunnels are excluded. Report both raw roadside length and estimated usable
frontage: junctions, water, tile boundaries, railway/harbour reservations, public
spaces, works yards and unsuitable relief cannot all be built on. A conservative
16x14u land envelope rejects narrow slivers; exact fitting still tries these
borderline plots and restores them to the usable total when an actual asset
fits. Decorative gaps are not treated as permanent reservations. Crop fields
and industrial yards do not count as building facades.

Final trial: 245 decorative buildings (112 more than the previous 133), zero
decorative access stubs, and ten retained green spaces. Estimated usable-frontage
coverage is 78.20% region-wide: Town 81.27%, Old Quarter 80.01%, Docks 84.36%,
Fields 74.69%, Coast 70.26%. Covered length is 9,127.22u of 11,671.37u usable;
including every road edge yields 42.88% of 21,285.34u. **The 75% threshold applies
to estimated buildable frontage, not all road edges regardless of obstacles.**
The report deliberately exposes both denominators rather than treating reserved
land as buildings. The full five-tile geometric audit finds no decorative
building overlaps or street/sidewalk intrusions. All 16 gameplay structure
positions and dimensions match the previous trial.

Evidence and ten camera/LOD captures are in
`outputs/supply-chain-3d/stoneshore-frontage/` at repository root. The review
harness asserts regional usable coverage >=75%, zero decorative access stems,
retained neighbourhood features, and unchanged residential zoning.

### Fixed tunnel elevations and softer slope shading (14 October 2026)

The terrain shader now uses `slope / (slope + 0.45)` with 4–16% directional
contrast, replacing the linear response that saturated at a 13.235% slope with
up to 20% darkening. Ordinary road and rail approaches therefore retain a
light gradient; steep terrain can continue gaining contrast. The normal palette,
height levels, regular map and building materials are unchanged.

`rail_elevation.gd` solves the sampled rail graph once during transport baking.
Covered junction movements and short enclosed daylight gaps are resolved before
choosing elevations. Each connected bore has one absolute datum: at least 14u
below the lowest normal rail elevation across its width (normal ballast is 1.2u
above terrain). Stoneshore's connected bore is at Y=21.2, beneath its Y=34 plain.
Approaches ease along the network over at least 180u, extended for deeper bores;
operating depot parcels remain at grade. This replaces a local terrain-minus-depth
field whose urban tile boundary could produce an abrupt vertical step.

Rendered tracks, portal cutoffs and terrain excavation read the same baked
profile. Buried spans retain their roofs; visible approach floors sit 1.4u below
the ballast. Switch/buffer fittings no longer subtract the burial offset twice.
Transport schema 2 stores the profile, spatial index and tunnel datums, and both
road/scenery cache fingerprints include its solver. Cache hits do not solve it.

The five-tile audit finds zero hidden open cuts (previously 412.91u), zero grade
within the 595.78u covered rail, and three portal crowns at least 3.23u beneath
natural ground. None of 14,300 sampled terrain points reaches 95% of the new
contrast response. This is a tunnel/shading correction, not a complete surface
rail grading pass: an existing exposed slope near (2853,4915) still reaches 71%.
No whole-continent package was regenerated.
