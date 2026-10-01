# Plastics (g_027) Blender icon

Builder for the approved plastics alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_027_plastics.png` (the good's internal
name is `plastics`): a cream monobloc armchair, a PET bottle with a blue cap standing in front of its left
side, and a dusty-blue T-shirt carrier bag brim-full of cream pellets at its front right. It is drawn on the
set's isometric grid with the fixed orthographic goods camera and lit by the set's light, with a 12 px outer
line, 4 px interior lines (3 px on small detail) and dots on the shaded sides. It keeps the shipped art's
layout (see `artifacts/goods_plastics/README.md`). The installed revision is `plastics_v33`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/plastics/render.py -- <out_dir> plastics
python3 tools/goods_icons/plastics/icon_export.py <out_dir>/plastics_raw.png <out_dir>/plastics_800.png --vib 1.0
```

The Blender step writes the raw colour, mask, contour, ID, host ID, ink and path passes, `plastics.blend`
and `plastics_metrics.json`. The export step writes the 800 px master, its ink layers and its line-weight
record; it imports `standard_lines.py` from this folder, the frozen exporter.

`pl_proof.py <out_dir> [<previous_dir>]` writes:
- the 450, 256 and 60 px tiers (LANCZOS downsizes of the master);
- the comparison sheet, the 3x crops and the DS2 well sheet;
- `pixel_metrics.json`.

It reads the shipped art, the font and the neighbouring icons from the main checkout.

The saved-scene check reads `plastics.blend` and `plastics_metrics.json` from `<out_dir>` and writes
`saved_scene_verification.json` there:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/plastics/pl_verify.py -- <out_dir>
```

It fails on any of these:
- an open or degenerate host;
- anything below ground;
- the bottle or cap intersecting the chair;
- the bag or its handles intersecting the chair;
- the cap not touching the bottle.

Re-rendered from this copy at install, the 800 px master matched the approved v33 render except for 3 pixels
that differ by one level (Blender's render is not bit-exact here). The check reported no failures.

## Files

### `plastics_kit.py`

`build_plastics()` and its parts. Each revision's change is recorded in the comments, and `PL_REVISION`
names the installed `plastics_v33`. It uses the frozen kit's helpers unchanged (`base_kit.py`,
`goods_icon_kit.py`, `pure_water_kit.py`, `alkaline_kit.py` and the rest).

- **The chair: `pl_chair_mesh()` with `CHAIR_MESH`.**
  - It is the owner's downloaded model: Poly Haven's "Plastic Monobloc Chair 01" by Kuutti Siitonen,
    licensed CC0.
  - It is loaded from `monobloc_chair.npz` (one closed solid), turned square to the grid to face +X, and
    placed on the shipped chair by its inked silhouette (`fit/gfit.py`, IoU 0.829).
  - It is smooth-shaded with hard edges past 45 degrees.
  - Its ink comes from the mesh itself (`pl_mesh_lines`): the visible creases past 50 degrees, and the
    contours where it covers itself. Chains shorter than about 6 px on screen are dropped.
  - The earlier parametric chair (`chair_geom.py`, `pl_chair`) stays in the file but is unused.
- **The bottle: `pl_bottle()`.** Fitted to the shipped bottle (`fit/bottle_fit.py`, `B5_p1.6.json`), with the
  shipped cap, shoulder and ring heights.
- **The bag: `pl_bag()`.** A thin closed film fitted to the shipped bag's silhouette (`fit/bag_fit.py`,
  `G7_fit.json`), with its lips, heap and creases read off the shipped bag (`bag_creases.py`).
  - **Handles.** The left loop runs across the mouth's left end and faces the viewer. Its inner leg rises
    out of the front lip and its outer leg out of the bag's rounded end; both twist out of the film's plane
    into the loop's (`pl_sweep_n`). Each is a hair thicker than the film, so its foot takes in the rim's top
    face. The right loop is the fitted v16 band, its inner leg tucked into the heap. The lip line stops at
    every leg.
  - **Pellets.** They fill the mouth down past the front lip, and the pile slopes down to the lip. They are
    chosen nearest the camera first. A bead stays only if every clean piece of it holds a 3 px circle at
    800 px and the largest piece is half its disc (a third where only the lip cuts it). A clean piece is one
    not under a nearer bead, that bead's outline included, and not under the film or a strap.
  - **Spacing.** Beads at about the same depth keep 2.25 radii apart, so their outlines stay visible.
  - **Walls.** A row of beads is laid first along the walls; beads left as tips are nudged up or inward
    until they are whole.
  - **Core.** A core in the beads' shaded tone, with its dots, sits under them.
  - The bag's normals split at its hard edges, so no pale band runs along the lip.

### Other files

- `monobloc_chair.npz`: the chair's welded mesh. `monobloc/` holds the source glTF (`untitled.gltf`,
  `untitled.bin`; the zip's 4k texture maps are not needed). `monobloc/weld_monobloc.py` rebuilds the npz
  from it exactly:
  ```sh
  Blender --background --factory-startup --python monobloc/weld_monobloc.py -- monobloc monobloc_chair.npz
  ```
- `render.py`: loads the kit files and builds the icon, as the other goods' copies do (plus `chair_geom.py`).
- `fit/`: the fits behind the numbers in the kit, kept as a record. They ran in a scratch folder beside the
  shipped art's masks, which are not included.
  - `gfit.py` (+ `G2.json`): the chair's placement, using `chair_fit2.py`'s camera and ink model.
  - `bottle_fit.py` (+ `B5_p1.6.json`): the bottle.
  - `bag_fit.py` (+ `G7_fit.json`), `bag_creases.py` (+ `bag_creases.json`) and `set_bag.py`: the bag.
  - `best_powell.py`: a bounded Powell that keeps its best point.
  - `ink_overlay.py`: the shipped ink over a render.
  - `pellet_debug.py`: each bead marked on the 800 px render.
  - `pellet_clear.py`: the pellets against the film and straps.
  - `pick.py`: what the camera sees at given 800 px pixels.
  - `owner_sheet_bag.py`: the owner's before and after sheet.
