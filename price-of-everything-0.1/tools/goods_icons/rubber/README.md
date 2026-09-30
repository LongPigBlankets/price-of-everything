# Rubber (g_028) Blender icon

Builder for the approved rubber alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_028_rubber.png` (the good's internal
name is `rubber`): a stack of folded dark rubber sheets with tan dashed stitching, a pair of black
wellington boots standing in front of its right face, and a yellow rubber duck at the front, drawn on
the set's isometric grid with the fixed orthographic goods camera, lit by the set's light, with 12/6 px
navy ink and dots on the shaded sides. It keeps the shipped art's layout and maps each object's shape
to the shipped art (see `artifacts/goods_rubber/README.md`). The installed revision is `rubber_v15`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/rubber/render.py -- <out_dir> rubber
python3 tools/goods_icons/rubber/icon_export.py <out_dir>/rubber_raw.png <out_dir>/rubber_800.png --vib 1.0
```

The Blender step writes the raw colour, mask, contour, ID, host ID, ink and path passes, `rubber.blend`
and `rubber_metrics.json`; the export step writes the 800 px master, its ink layers and its line-weight
record (it imports `standard_lines.py` from this folder: the frozen exporter with the optional per-part
weights added for fertilisers, unused here). `rb_proof.py <out_dir> [<previous_dir>]` writes the 450,
256 and 60 px tiers (LANCZOS downsizes of the master), the comparison sheet, the 3x crops, the DS2 well
sheet and `pixel_metrics.json`; it reads the shipped art, the font and the neighbouring icons from the
main checkout.

The saved-scene check reads `rubber.blend` and `rubber_metrics.json` from `<out_dir>` and writes
`saved_scene_verification.json` there:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/rubber/rb_verify.py -- <out_dir>
```

It fails on an open or degenerate host, anything below ground, a missing intended contact (each boot's
upper with its rim and midsole, the midsole with the outsole; the duck's neck peg with its head and
body, the bill with the head, the lower mandible with the bill) and any other intersection among the
duck, the two boots and the stack's sheets. Re-rendered from this copy at install, the 800 px master
came out byte-identical to the approved v15 one, and the check reported no failures.

## Files

- `rubber_kit.py`: `build_rubber()` and its parts.
  - `rb_stack()`: `LAYERS` (thirteen sheets and folds measured on the shipped stack's front face: kind,
    thickness, insets), each an extruded outline (`rb_prism`, folds with rounded ends); the stitching
    (`rb_stitch` walks tan dash strips along any 3D path at the shipped 21 px pitch, `DASH2`; short
    dashes on the fold ends, `DASH_ARC`) laid as the shipped art has it (`rb_fold_stitching`, and the
    top sheet's rounded-corner row).
  - `rb_boot()`: a wellington from `boot_geom.py` with the fitted `BOOT_GEOM` and `BOOTS`: the upper
    lofted from the sole to the cuff, the cuff band and its top ring round a dark opening, a rounded
    midsole on a lugged outsole (`LUG`); ink on the seam, the ring's front edge and the midsole/outsole
    split, on their camera-facing arcs only (`rb_arc_lines`, since a line on a label is clipped only to
    that label's pixels). The near boot's midsole bulges less on its hidden inner side (v15).
  - `rb_duck()`: the duck from `duck_geom.py` with the fitted `DUCK_GEOM`, its eyes, neck line, mouth
    line, wing and feathers from `DUCK_STROKES` (the shipped strokes in the duck's own frame), no dots
    on the head or the chest under it, the hidden rear resting against the bottom fold, and the neck
    peg (v15).
  - Each revision's change is recorded in the comments; `RB_REVISION` names the installed `rubber_v15`.
    It uses the frozen kit's helpers (`base_kit.py`, `goods_icon_kit.py`, `pure_water_kit.py`,
    `power_kit.py`, `alkaline_kit.py` and the rest, unchanged).
- `boot_geom.py`, `duck_geom.py`: the boots' and the duck's geometry in numpy, shared by the fits and
  the kit, so the render is the fitted shape.
- `render.py`: loads the kit files and builds the icon (as the other goods' copies, with the two
  geometry modules added).
- `fit/`: the fits behind the numbers in the kit, kept as a record (they ran in a scratch folder
  beside the shipped art's region masks, which are not included: they are the shipped PNG split by
  colour and ink, and large).
  - `stack_fit.py` (+ `stack_fit.json`): the stack's size and the camera, `rfit_common.py` the shared
    camera and ink model, `best_powell.py` a bounded Powell that keeps its best point.
  - `boot_fit2.py` (+ `boot_fit2c.json`): the boots fitted part by part (the shipped regions read off
    the ink, the model painted back to front, each region shrunk by the shipped line's half width).
  - `duck_fit2.py`, `duck_fit2_sub.py` (+ `duck_fit2g.json`): the duck's pose, body, pinned head and
    bill; `duck_tail_fit.py` (+ `duck_v13.json`): its back on the true 800 px silhouette.
  - `duck_backproject.py` (+ `duck_strokes.json`): the shipped strokes traced and carried onto the
    surfaces; `duck_strokes2.py` (+ `duck_strokes2.json`): the closed wing, scaled eyes and mouth
    carried onto the final duck. `kitconst.py` reads a constant out of the kit; `ink_overlay.py`
    overlays the shipped ink on a candidate.
