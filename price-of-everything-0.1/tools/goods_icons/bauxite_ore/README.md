# Bauxite ore (g_022) Blender icon

Builder for the approved bauxite ore alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_022_bauxite_ore.png` (internal name `bauxite_ore`). The
approval record, renders and proof sheets are in `artifacts/goods_bauxite_ore/`.

It is drawn from real bauxite rather than the old art:

- an earthy, dull rust red crust mottled with cream;
- pisoids, the pea sized round lumps it is made of, which show as rings where the rock is cut, stand out of the crust as
  dark knobs, and lie loose as pea gravel;
- rounded, crumbly lumps rather than crystal facets.

The icon is one rounded lump sawn in half through its widest point. The rear half stands with its cut toward the light,
the front half lies on its back with its cut face up, and three loose peas sit at the front right. It uses the fixed
orthographic goods camera, the set's light, 12/4 px ink and dots on the shaded sides. The installed revision is
`bauxite_ore_v19`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
blender -b --factory-startup --python-exit-code 1 --python tools/goods_icons/bauxite_ore/render.py -- <out_dir> bauxite_ore
python3 tools/goods_icons/bauxite_ore/icon_export.py <out_dir>/bauxite_ore_raw.png <out_dir>/bauxite_ore_800.png --vib 1.0
```

Re-rendered from this folder at install, the 800 px master was pixel-identical to the approved one. `render.py` checks the
camera, that nothing is below ground, and that every host mesh is closed.

## `bauxite_kit.py`

- **`bx_lump()`:** an even icosphere on a squashed ellipsoid, made lumpy by low-frequency noise, with a few worn flat
  faces pressed in and low round knobs raised where pisoids weather out. With `split`, it is sawn through a point and
  returns two halves. The half in front of the plane is turned cut face up, placed at `LIE_AT` and cut flat where it
  rests on the ground.
- **`bx_mottled_toon()`:** the crust material. Two toon ramps on the same shading are picked per pixel by a noise field,
  so the cream patches have smooth edges. The lying half has its own, sparser field.
- **`bx_pisoids()`:** the pea sections on a cut face, packed without overlap inside it: ringed (a pale rim round a dark
  core, with a pale heart on the big ones), solid dark, or pale. They are flat decals, not inked.
- **`bx_knob_spots()`:** a dark spot capping each crust knob. Each spot is concentric rings ray-cast onto the surface
  (a flat fan sat under the knob, which poked through it), with no lit step (a highlight read as an eye).
- **`bx_rim()`:** one closed ink line round each cut face. It is the only line inside a part: knob contours drew as
  stray ticks, and a crease filter broke the rim up where the cut is shallow.
- **`bx_pea()`:** a loose pea, a slightly irregular, flattened ball.
- **`bx_build()`:** places the parts (`HERO_AT`, `HERO_SIZE`, `SLICE_N`, `LIE_AT`, `PEAS`) and sets the outline and
  stipple contract. `BACK_LUMP` adds the weathered lump the owner set aside at v18.

It reuses the shared kits copied beside it from `ree_ore`.
