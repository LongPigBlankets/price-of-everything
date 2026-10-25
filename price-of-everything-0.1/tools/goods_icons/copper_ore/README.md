# Copper ore (g_003) Blender icon

Builder for the approved copper ore alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_003_copper_ore.png` (internal name `copper_ore`). It
replaced the earlier `mottle_rock` attempt. The approval record, renders and proof sheets are in
`artifacts/goods_copper_ore/`. The installed revision is `copper_ore_v15`.

It is drawn from real oxidised copper ore:

- an earthy red-brown host rock, stained by limonite and goethite, with paler and darker brown layers (the browns are
  the old icon's, at the owner's request);
- malachite in green streaks and stripes that run roughly parallel through a lump, one darker green (owner), plus green
  flecks scattered through the matrix;
- brassy, coppery gold grains of chalcopyrite, loose in the rock and caught inside the green veins.

The icon is a few hard broken lumps with broad planar breaks: a tall hero, a lump behind it on the left, a small one in
front and two chips. It uses the fixed orthographic goods camera, the set's light, 12/4 px ink and dots on the shaded
sides.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
blender -b --factory-startup --python-exit-code 1 --python tools/goods_icons/copper_ore/render.py -- <out_dir> copper_ore
python3 tools/goods_icons/copper_ore/icon_export.py <out_dir>/copper_ore_raw.png <out_dir>/copper_ore_800.png --vib 1.0
```

`render.py` checks the camera, that nothing is below ground, and that every host mesh is closed. Re-rendered from this
folder at install, the 800 px master was pixel-identical to the approved one.

## `copper_kit.py`

- **`cu_ore_mat()`:** the rock's skin. One toon ramp per mineral (host, paler host, darker host, green, gold, gold
  glint), all on one shading factor, picked per pixel by fields in object space:
  - stripes: `t` is the position along the rock's vein direction, warped by low noise. A 1D noise of `t` picks green
    bands of irregular width and spacing, a slower noise of `t` widens some whole stripes, and a slow 3D noise breaks
    them into streaks. Paler and darker brown bands come from their own 1D noises of the same `t`, so every layer runs
    the same way;
  - specks: Voronoi cells on noise jittered coordinates (irregular grains, not discs, none under about 5 px), kept by
    their random colour: green and dark brown flecks, and brassy coppery gold grains with a pale glint in the bigger
    ones. Gold also sits inside the green streaks. The gold's lit step starts lower, so the grains catch the light;
  - stripes thin out as a face turns from the view, and past about 77 degrees the pattern is off: specks squashed into
    slivers and a thinned stripe into a hairline there;
  - no crossing veins: thin ones inked as 1 px hairlines, and a wider one, a sheet in 3D, spread into a green blob
    wherever a face ran nearly parallel to it.
- **`cu_rock()`:** a lumpy rounded core (an icosphere on an ellipsoid under low noise) broken by planar cuts. `first`
  places the big break deliberately, and no two breaks face the same way, which would leave a sliver. Each break is
  flat shaded with hard rims, and its region id is kept in a face layer (`cu_region`) that survives later cuts.
- **`cu_region_lines()`:** ink where two regions meet (a break and the crust, or two breaks), on faces toward the
  camera. A rim always runs on to another rim or the silhouette, so no line stops mid-face. An angle threshold faded
  shallow rims out and left dangling ends.
- **`cu_build()`:** places the rocks (`CU_HERO`, `CU_ROCKS`, `CU_CHIPS`), each with its own vein direction, chosen so
  the stripes run diagonally on screen, and sets the outline and stipple contract.

It reuses the shared kits copied beside it from `bauxite_ore` (including `bauxite_kit.py` for `bx_cut`, `bx_dots` and
`scr`). This folder's `icon_export.py` adds one option to the stipple contract, `protect_gold`, which keeps the halftone
off the gold grains (dots on them read as dirty paint).
