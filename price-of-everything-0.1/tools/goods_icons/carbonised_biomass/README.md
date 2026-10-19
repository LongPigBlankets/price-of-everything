# Carbonised biomass (g_076) Blender icon

Builder for the approved carbonised biomass alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_076_carbonised_biomass.png` (internal name
`carbonised_biomass`). The approval record, renders and proof sheets are in `artifacts/goods_carbonised_biomass/`.

It keeps the shipped art's subject: a mound of charcoal with long charred sticks lying criss-crossed over it. It uses
the fixed orthographic goods camera, the set's light, 12/4 px ink (6 px round the sticks) and dots on the shaded sides.
The installed revision is `carbonised_biomass_v26`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
blender -b --factory-startup --python-exit-code 1 --python tools/goods_icons/carbonised_biomass/render.py -- <out_dir> carbonised_biomass
python3 tools/goods_icons/carbonised_biomass/icon_export.py <out_dir>/carbonised_biomass_raw.png <out_dir>/carbonised_biomass_800.png --vib 1.0
```

Re-rendered from this folder at install, the 800 px master was pixel-identical to the approved one. The log's
`CB_STICKS placed` line gives the stick count.

## `cb_kit.py`

- **The mound (`HEAP`)**: a solid dark dome with a flattened top carries a few large lumps (`cb_lump`: noisy level-2
  icospheres, flat shaded, no facet lines), sunk into its visible face. Lumps alone leave a hollow ring.
- **The pile**: the dome and lumps are sampled into a height field. Each straight stick (`cb_stick`) rests on the support
  line under its middle, the upper convex hull of the field beneath it evaluated at its centre, so it sits on two
  contacts either side of its middle and never bends or floats. It then joins the height field.
- **Settling (`settle`)**: a stick rolls sideways off its contacts when the cross-slope is steeper than friction (`mu`),
  and slides along itself when it is steeper than friction unless its low end rests on something; past `lean` it is
  rejected. So the sticks lean on the nuggets the way they would on a real pile.
- **Placement**: each stick takes the best of many candidates, centred over the side the camera sees and turned 30 to
  65 degrees off the downhill line, scored by how high it sits over the bare heap and how much of its footprint other
  sticks already cover. `rise` caps the first, so a stick lies on the lumps or one stick up. The first fit stacks
  sticks into a tower, and the lowest rest alone caps the top and leaves the front bare.
- **The sticks**: slightly crooked tapered prisms with grey-brown sawn ends, bark grain lines along them, a crack and a
  long check; some carry a forked twig.

It reuses the shared kits copied beside it from `biomass`.
