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
- Q/E or arrow buttons: rotate. Home / Reset view: frame the company.
- Click terrain or a warehouse: select its tile; Shift-click selects through buildings.
- Click a building: open its network. Tab returns to the regular map.

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
Building paint has fixed world-space directional face lighting, navy crease ink and
object-anchored stippling. Separate feathered ground shadows match the source board's
illustrated grounding. The sprite exporter disabling cast shadows does **not** mean
the original board lacked shadows: it drew them as a separate layer.

Decorative house and tower meshes follow the exact sprite variety chosen by the
model, rather than the footprint-sizing level. Windows and inexpensive additive
lamp/yard glows light polluted districts. Glass towers light individual panes rather
than their whole facade. Foundations are added where ground is uneven. Cream goods
tokens with navy borders and the old label plates are restored.

The 3D viewport follows physical screen resolution, with 4× MSAA. Projection/picking
converts between physical viewport pixels and logical UI coordinates. Lighting is
an illustrated approximation of the original Blender/AgX/Freestyle rendering, not a
pixel-identical transfer of the sprites. Some source models have simpler rear faces;
mines still use raised solid pit geometry rather than cutting the terrain surface.

## Three detail levels

LOD is selected from logical screen pixels per world unit, with hysteresis so a slow
pinch near a threshold does not flicker between tiers. The selected mesh and material
are cached resources; no terrain generation or image readback happens during zoom.

| Tier | Typical span at 1080px height | Ground mesh spacing | Terrain artwork width | Detail |
| --- | --- | --- | --- | --- |
| Far | Above ~1420 units | 12 units | 512px + mipmaps | Accurate contours/beaches, textured strata, denser rounded trees and bushes, roads, lamps, buildings, shadows and tokens |
| Medium | ~675–1420 units | 8 units | 1024px + mipmaps | Finer slopes, canopy lobes and branches, railway sleepers, increased building mesh detail |
| Near | Below ~675 units | 4 units | 2048px + mipmaps | Fine slope geometry, kerb markings, ground tufts and stones, highest building detail |

The far tier's surface paint has roughly 512 samples across a tile, versus about 45
triangle-colour samples in the first 3D pass. It also has up to 84 tree candidates per
tile versus 26, with placement excluding buildings, streets and riverbanks. All tiers
use the same deterministic positions. Medium and near add details to those positions.
Imported glTF LODs handle building meshes; tier-specific biases preserve more geometry
as the view approaches. Colliders remain stable across visual LOD changes.

## Performance and limits

Geometry is frustum-culled by Godot. Ground, vegetation and infrastructure details are
batched; lighting accents use shared materials and glow cards instead of an individual
real-time light for every lamp. The viewport and processing stop when the board is hidden.
Unchanged models retain their scene. Obsolete terrain cache entries are released on
rebuild, including tiles no longer in the company and old height fields.

Three complete terrain texture tiers for the eight-tile Metal Magnate company retain
approximately **199.5 MiB** including mipmaps. Keeping them resident avoids decode/upload
work while zooming. This is a quality-first company-view implementation: a whole-world
view needs visibility-driven texture residency/streaming and a fixed memory budget
before extending it to hundreds of tiles. Initial build/baking is paced during loading;
changed standing objects/infrastructure still rebuild rather than update incrementally.

Rendered measurements: Godot 4.6.2, OpenGL compatibility, Apple M5 Pro, 1920×1080,
eight tiles / 38 standing objects. After 60 forced-draw warm-up frames, 45 frame samples:

| Tier | Median frame interval | p95 | Frame draw calls | Primitives |
| --- | --- | --- | --- | --- |
| Far | 6.93 ms | 7.11 ms | 392 | 163,336 |
| Medium | 6.91 ms | 7.11 ms | 386 | 259,232 |
| Near | 6.91 ms | 7.13 ms | 300 | 305,534 |

These are local end-to-end frame intervals with forced draws, including HUD work, not
isolated GPU timings or a full-map benchmark. Near framing culls more tiles, hence fewer
draw calls. Initial cold captures included ~150ms spikes; those are not hidden by the
steady-state figures. The engine's total texture monitor also includes the main game's
prewarmed sprites and regular-map assets, so it is not the supply-chain cache size.

## Verification and captures

- Map, goods-view and 3D regression: **2,334 checks passed**, 236 tests, no script errors.
- The focused interaction test passes **19 checks**, including added high-DPI picking and house-variety regressions.
- Complete parse sweep: **775 scripts, 0 failures**, 47 excluded by the existing checker.
- Rendered New Game → Begin → supply chain, routed mouse orbit, routed trackpad pinch,
  tile selection, all three LODs, a rotated near view, and the original 2D renderer at
  matched far/medium framing. Captures live in `outputs/supply-chain-3d` at repo root.
- The default New Game start is also covered by the headless loading-path smoke tool.
- Headless logs retain fixture-level missing-node/dummy-texture diagnostics; the parse
  checker also reports its existing live-script reload diagnostic. No script parse
  failures or assertion failures were reported.
- The existing ObjectDB leak warning still appears on exit; the previous native logger
  shutdown abort remains fixed.

From the game directory:

```sh
python3 tools/run_tests.py --tags goods_views,map,supply_chain_3d --no-telemetry
godot --headless --path . res://tools/parse_check.tscn --quit-after 600 -- --no-telemetry
godot --headless --path . res://tools/supply_chain_3d/new_game_smoke.tscn \
  -- --no-telemetry --start=res://data/starts/default.json
AGENT_GODOT_WINDOW=1 godot --path . --windowed --resolution 1920x1080 \
  res://tools/supply_chain_3d/capture.tscn -- --no-telemetry --detail-review
```

The dummy headless renderer cannot bake viewport images; its tests exercise the same
meshes, lifecycle, picking and LOD policy with placeholder textures. Windowed captures
verify the actual shaders, terrain artwork and token composition.
