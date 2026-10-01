# CPU (g_041) Blender icon

Builder for the approved CPU alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_041_cpu.png` (internal name `cpu`). It shows the shipped
art's copper socket tray with a CPU seated in it, and a second CPU standing on its edge against the tray's right side,
its underside to the viewer. It is drawn on the set's grid with the fixed orthographic goods camera and the set's light,
12/4 px ink, and dots on the shaded sides. It is built from simple solids; no downloaded model is involved. The
installed revision is `cpu_v5`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/cpu/render.py -- <out_dir> cpu
python3 tools/goods_icons/cpu/icon_export.py <out_dir>/cpu_raw.png <out_dir>/cpu_800.png --vib 1.0
python3 tools/goods_icons/cpu/cpu_proof.py <out_dir>
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/cpu/cpu_verify.py -- <out_dir>
```

`cpu_verify.py` checks:
- the camera, closed hosts, and nothing below ground;
- the seated CPU's stack: board in the pocket, flange on the board, plateau on the flange;
- that the leaning CPU rests on the tray without passing into it.

Re-rendered from this copy at install, the 800 px master was pixel-identical to the approved one, and the check reported
no failures.

## `cpu_kit.py`

- **`cpu_tray()`:**
  - Two tiers: a base slab and an upper block, each with rounded vertical edges. The upper block has the well and
    the pocket boolean-cut into it.
  - Raised rim sections laid as shipped: one U along the back-left edge, wrapping both its corners into short arms,
    and a short L round each front corner. Their outer corners are rounded. Each arm ends square, with its outer
    corner cut at 45 degrees (the notch).
  - The sections are built along the band's rounded-square centreline (`at()`, `piece()`). Their caps are tessellated
    with points only on the arcs, so no collinear points leave holes.
- **`cpu_seated()`:** a green board, the silver heat spreader's flange and plateau, and two glint bands running straight
  up the screen.
- **`cpu_leaning()`:**
  - The second CPU leans 40 degrees from vertical, its foot on the ground and its back on the front rim sections.
  - The board has two notches in each side edge and a gold edge.
  - Its pad side carries a 22 x 22 gold pad grid round an empty field, a gold centre square and gold corner marks,
    all undotted.
  - The board's faces are tessellated here: a concave n-gon fans wrongly in the exporter's visibility test, which
    let the lines behind it show through.

It reuses `plastics_kit.py`'s toon, sweep and mesh-ink helpers, loaded by `render.py` with the frozen kit.
