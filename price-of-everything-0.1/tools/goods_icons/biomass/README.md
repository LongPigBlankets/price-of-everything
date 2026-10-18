# Biomass (g_062) Blender icon

Builder for the approved biomass alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_062_biomass.png` (internal name `biomass`). The approval
record, renders and proof sheets are in `artifacts/goods_biomass/`.

It keeps the shipped art's layout:
- three wooden logs stacked two and one, their sawn ends toward the viewer at the lower left;
- a heap of wood chips leaning against the right log;
- a deep wicker basket on the top log, with five apples, three carrots and a bunch of loose leaves.

It uses the fixed orthographic goods camera, the set's light, 12/4 px ink (thinner on the chips and the weave) and dots
on the shaded sides. The installed revision is `biomass_v29`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
blender -b --factory-startup --python-exit-code 1 --python tools/goods_icons/biomass/render.py -- <out_dir> biomass
python3 tools/goods_icons/biomass/icon_export.py <out_dir>/biomass_raw.png <out_dir>/biomass_800.png --vib 1.0
```

Re-rendered from this folder at install, the 800 px master was pixel-identical to the approved one. `render.py` checks the
camera, that nothing is below ground, and that every host mesh is closed.

## `bm_kit.py`

- **Logs (`bm_log`, `LOGS`)**: hand-built lumpy, slightly oval cylinders along world Y, tapering 6% toward the back.
  - The grid is fine (144 x 72) and the bark noise gentle and long; coarser grids or stronger noise blotched the toon steps.
  - The sawn ends face -Y, which falls in the set's shade step, so they use their own ramp (`END_STEPS`) and take no dots.
  - `bm_end` lays the end's decals: a bark rim, three growth bands that follow the outline toward an off-centre pith,
    the pith, and a drying check on the top log.
  - `bm_dashes` adds the bark furrows as short tapered ink dashes.
  - Each log has its own part label, so the seams between them ink.
- **Chip heap (`bm_heap`, `HEAP`)**: about 90 broad, flat, angular chips (`bm_chip`) laid on the vertices of a low dark
  dome (`bm_clump`), tipped a little and stacked. It sits beside the right log, and no chip is placed inside it.
  - Overlapping chips take different part labels (greedy colouring over 5–15), so each gets its own thin (3 px) outline.
  - Dead ends: small chips read as confetti, chips on the silhouette as ink spikes, outlined clumps as potatoes or
    pebbles, and bumps displaced into one surface blotched under the toon steps.
- **Basket (`bm_basket`, `BASKET`)**: a superellipse tub, long along the top log and sunk into it.
  - Its top is closed by an inner wall and a deep bed in a dark inside tone, so gaps between the produce fall dark.
  - The bed ring sits inside the tapered wall at its own height; a fixed radius poked out through the wall.
  - A tube rim (`bm_tube`), a flat band handle across it, and the weave: courses and staggered uprights ray-cast onto the
    wall.
- **Produce**:
  - five apples (`bm_apple`: dimpled spheres with a stem line and a folded leaf), sunk to the rim (`APPLE_SINK`);
  - three carrots (`bm_carrot`: tapered sweeps with domed tops, ring dashes and four leaves), rising out of the basket
    (`CARROT_Z`);
  - seven loose leaves (`LOOSE_LEAVES`, `bm_leaf`) standing behind the left carrot.
- **Labels**: `id_step` 8 allows 31 parts: logs 1–3, heap 4, chips 5–15, basket, rim and handle 16–18, apples 19–23,
  carrots 24–26, leaves 27–31.

It reuses the shared kits copied beside it from `metallurgical_silicon` (so its `standard_lines.py` has `min_fragment_px`).
