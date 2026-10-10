# Supply-chain 3D overview

Branch `codex/supply-chain-3d` starts at PR #197 (`6266b19a`) and merges the
supply-chain work in PR #196 (`86cb0e02`). The regular map remains unchanged.

The company overview uses an isolated World3D and an orthographic orbit camera.
The existing board model and smooth height field remain authoritative. Its 53
building meshes come from the original Blender sprite builders. Buildings still
open their supply-chain graphs; terrain clicks open the existing tile panel.

## Controls

- Left drag / two-finger trackpad pan: pan.
- Right or middle drag: orbit and tilt.
- Mouse wheel / trackpad pinch: zoom around the terrain under the pointer.
- Q/E or arrow buttons: rotate. Home / Reset view: frame the current coverage.
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

At very wide framing, trees become batched simplified canopies, decorative settlements
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
