# REE ore (g_032) Blender icon

Builder for the approved REE ore alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_032_ree_ore.png` (internal name `ree_ore`). It keeps the
shipped art's layout:

- a brown host rock at the back left;
- a tan rock mottled with blue-grey, purple and green mineral patches in the middle;
- a grey fluted scandium crystal on the right;
- a red horseshoe magnet with pale pole pieces in front.

It uses the fixed orthographic goods camera, the set's light, 12/4 px ink and dots on the shaded sides. The installed
revision is `ree_ore_v19`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/ree_ore/render.py -- <out_dir> ree_ore
python3 tools/goods_icons/ree_ore/icon_export.py <out_dir>/ree_ore_raw.png <out_dir>/ree_ore_800.png --vib 1.0
python3 tools/goods_icons/ree_ore/ree_proof.py <out_dir>
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/ree_ore/ree_verify.py -- <out_dir>
```

`ree_verify.py` checks:

- the camera;
- closed hosts and nothing below ground;
- that the crystal and the magnet clear each other and both rocks.

The brown and mottled rocks overlap where the mottled one hides it; this overlap is reported, not failed.

Re-rendered from this copy at install, the 800 px master was pixel-identical to the approved one, and the check reported
no failures.

## `ree_kit.py`

Each revision's change is recorded in the comments.

- **`ree_rock()`:** an angular rock, the convex hull of jittered points with some vertices pushed in. Options give it
  smooth shading and a rounder shape.
- **Brown rock:** a faceted hull with three boolean-cut grooves (`ree_grooves`: wedges full-size for two thirds of
  their run, then tapering out). It also has tapered cracks (`ree_cracks`) and dots on every face not turned to the light
  (`ree_dots`).
- **Mottled rock:** 110 points near an ellipsoid. It is tapered wider at the bottom (`ree_taper`) and has concave scoops
  (`ree_carve`, cut one at a time, slivers cleaned between cuts). Its patches come from noise over an evenly re-split
  surface (`ree_mottle`). Its crevices are continuous ink following the surface (`ree_seams`).
- **Crystal (`ree_crystal`):**
  - seven flat ridge faces with concave arcs between them, which vary in width, depth and skew;
  - it leans 23 degrees, its bottom cut flat by the ground plane;
  - its top is cut square to the lean and tipped 10 degrees toward the viewer;
  - the grooves turned from the light, and every other groove in view, take a darker material and dots.
- **Placement:** the three rocks' centres are turned 24 degrees about their mean (`GROUP_TURN`). The crystal is moved
  toward the centre (`CRY_SHIFT`). The magnet is moved toward the crystal (`MAG_TOWARD`, `MAG_RIGHT`, `MAG_FWD`), about
  0.03 apart.

It reuses `plastics_kit.py`'s toon, sweep, cut and mesh-ink helpers. This copy's `pl_mesh_lines` takes `contours=False`.
