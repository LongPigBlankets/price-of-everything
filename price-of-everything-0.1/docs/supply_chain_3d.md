# Supply-chain 3D overview: first iteration

Branch `codex/supply-chain-3d` starts at PR #197 (`6266b19a`) and also merges the
supply-chain work in PR #196 (`86cb0e02`). The regular map is unchanged.

The overview now uses an isolated World3D and orthographic Camera3D. Terrain is
meshed from the existing supply-chain height field; 53 building/level meshes are
exported from the existing Blender sprite builders. Rotation changes the camera,
not the geometry. Building networks still open in the existing graph view.

## Controls

- Left drag: pan. Right or middle drag: orbit and tilt.
- Scroll: zoom about the terrain under the pointer.
- Q/E or the arrow buttons: rotate; Home or Reset view: frame the company.
- Click terrain or a warehouse: open that tile's existing detail panel.
- Click a building: open its supply-chain network; Shift-click selects its tile.
- Tab: return to the regular map. Escape follows the existing panel stack.

Tile selection also forwards active destination-selection and construction actions.
The original motion key and visibility switches remain available. Pausing goods
shows outputs above their producers. Terrain selection is highlighted in the scene.

## Implementation and limits

`scripts/supply_chain_3d/board.gd` owns the viewport, picking, overlays and lifecycle;
`orbit_camera.gd` owns the rig; `world_builder.gd` builds the static meshes. Existing
model, river, relief and graph data remain authoritative. Source sprite builders,
regular-map assets, Camera2D and map scripts have not been modified.

The viewport and its processing stop while hidden. Mesh resources are shared per
building type/level, glTF imports generate mesh LODs, terrain meshes are cached per
tile/height field, and unchanged models retain their whole scene. Geometry is
frustum-culled by Godot. Camera movements do not rebuild or rebake terrain. Static
terrain/trees are batched per tile; infrastructure is currently one shared batch.

This remains the company-only overview. It does not add the whole-world toggle,
procedural city blocks, chunk streaming or distant impostors. Changed models rebuild
the standing objects/infrastructure; a later large-company pass should make those
updates incremental. Terrain colour boundaries currently follow a 12-unit mesh and
could use exact shoreline clipping. Types without an exported builder use simple
solid placeholders. This is the first playable 3D pass, not final marketing art.

## Verification

- Map, goods-view and 3D tests: **2,320 checks passed**, 235 tests, no script errors.
- Final parse sweep: **770 scripts, 0 failures**, 47 skipped by the existing checker.
- Rendered four yaw angles and the tile panel with Godot 4.6.2, OpenGL compatibility,
  Apple M5 Pro, 1920 × 1080. Routed GUI right-drag changes both yaw and pitch;
  routed Shift-click opens the tile panel.
- The captured Metal Magnate start has 8 tiles and 38 standing objects. The final
  close view reports roughly 493 frame draw calls and 139,000 primitives including
  the HUD. This is a scene-count observation, not a GPU timing or full-map benchmark.
- Regression coverage includes four-direction ray picking, triangle-edge precision,
  drag-versus-click separation, graph drilldown, unchanged-build reuse, all exported
  meshes, and restoration of the regular map camera/input.

Run tests from the game directory:

```sh
python3 tools/run_tests.py --tags goods_views,map,supply_chain_3d --no-telemetry
godot --headless --path . res://tools/parse_check.tscn --quit-after 600 -- --no-telemetry
```

Render the disposable, autosave-disabled capture scenario:

```sh
AGENT_GODOT_WINDOW=1 godot --path . --windowed --resolution 1920x1080 \
  res://tools/supply_chain_3d/capture.tscn -- --no-telemetry
```

It writes `/private/tmp/supply3d_*.png`. Selected reviewed captures are stored under
`outputs/supply-chain-3d` at the repository root.

To regenerate the assets from the repository root:

```sh
blender --background --factory-startup \
  --python price-of-everything-0.1/tools/supply_chain_3d/export_models.py
```
