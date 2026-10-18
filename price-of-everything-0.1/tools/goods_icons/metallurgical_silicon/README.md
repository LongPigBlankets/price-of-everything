# Metallurgical silicon (g_047) Blender icon

Builder for the approved metallurgical silicon alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_047_metallurgical_silicon.png` (internal name
`metallurgical_silicon`). The approval record, renders and proof sheets are in `artifacts/goods_metallurgical_silicon/`.

It keeps the shipped art's topology: a rough cast log of crystalline silicon lying along the view's rising diagonal
(world Y), its skin a patchwork of flat polygonal grains. Most grains are dark or mid blue-grey, a few pale, two
mirror-bright with a white streak, and a few tan on the lower flank. Its near end is a broken face of a few plates
split by jagged cracks, with a bevel round the corner. It uses the fixed orthographic goods camera, the set's light,
12/4 px ink (2 px on the end face) and dots on the shaded sides. The installed revision is `metallurgical_silicon_v44`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
blender -b --factory-startup --python-exit-code 1 --python tools/goods_icons/metallurgical_silicon/render.py -- <out_dir> metallurgical_silicon
python3 tools/goods_icons/metallurgical_silicon/icon_export.py <out_dir>/metallurgical_silicon_raw.png <out_dir>/metallurgical_silicon_800.png --vib 1.0
```

Re-rendered from this folder at install, the 800 px master was pixel-identical to the approved one. `render.py` checks the
camera, that nothing is below ground, and that the log and the end's floor are closed meshes.

## `ms_kit.py`

- **The log (`ms_log`)**: a boolean union of three overlapping eggs (`EGGS`) and six small grain chunks on the upper skin and
  along the top silhouette (`CHUNKS`).
  - Each egg is cut from a cube by tangent planes to an ellipsoid at jittered Fibonacci points (`ms_egg_planes`). This
    tiles it into even polygonal grains. Tilted rings of planes on a cylinder swallowed each other instead.
  - Grain kinds (`ms_kinds`) are kept one tone step apart so the light drives the read. A mirror grain is set on the
    crown of the middle and far eggs, and tan on the lower near flank.
- **The end**: the near egg is cut flat at `END['y']`. Two rings of bevel planes (`BEVEL`) soften the corner, and their
  kinds come from their own seed so the body's grains keep theirs.
- **The broken face (`ms_end_plates`, `PLATES`)**: the cut's outline is ray-cast from the axis. Jagged crack polylines
  split it into plates. A crack is skipped where it would leave a sliver.
  - Each plate is a solid on its own linear plane. Most are tipped up into the light, raised until every corner clears
    the near-black floor disc behind, and inset by half a crevice on their crack edges only.
  - The plates take the body's kinds: a mirror plate with the streak, one pale, and the rest mid or dark.
  - Each plate has its own part label (`id_step` 16), so the seams where tilted plates overlap are inked. Their lines and
    seams are `END_INK` (2 px).
- **`ms_streaks`**: the white bands across every mirror facet, on the log and the plates.
- **Exporter**: `standard_lines.stroke_projected` takes `min_fragment_px` from the outline contract (24 here). It drops
  short stubs where a raised grain hides most of a line.

`ms_end_cap` (a pleated radial fan, v22) and `ms_end_shards` (petal shards on a slanted plane, v27) are earlier end
studies the owner moved on from. They still build but are not called.

It reuses the shared kits copied beside it from `ree_ore`.
