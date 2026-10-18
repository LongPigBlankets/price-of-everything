# Pet coke (g_075) Blender icon

Builder for the approved pet coke alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_075_pet_coke.png` (internal name `pet_coke`). The
approval record, renders and proof sheets are in `artifacts/goods_pet_coke/`.

It keeps the shipped art's layout: a long hero lump, its raised end resting on a second lump behind it, and a third lump
in front. Each lump is split along its length into long parallel strips, broad taupe and narrow dark grey, with slate
broken ends. It uses the fixed orthographic goods camera, the set's light, 12/4 px ink and dots on the shaded sides. The
installed revision is `pet_coke_v29`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
blender -b --factory-startup --python-exit-code 1 --python tools/goods_icons/pet_coke/render.py -- <out_dir> pet_coke
python3 tools/goods_icons/pet_coke/icon_export.py <out_dir>/pet_coke_raw.png <out_dir>/pet_coke_800.png --vib 1.0
```

`pet_coke_hero` renders the hero alone, for reviewing its shape. Re-rendered from this folder at install, the 800 px
master was pixel-identical to the approved one. `render.py` checks the camera, that nothing is below ground, and that the
three lumps are closed meshes; the log's `PC_SETTLE overlap` lines must all read False.

## `pc_kit.py`

- **The section (`pc_section`, `SEC`)**: a fluted ellipse. Ridge points sit at radius 1; between each pair a valley point
  is pulled in a little and skewed toward the next ridge. The ridges are packed over the visible top and front.
- **Colour by role**: facets running ridge to valley are broad (taupe), valley to ridge are grooves (dark grey), and every
  cut face is an end (slate); each has its own toon ramp. Light alone left the whole top one tone.
- **The lump (`pc_lump`)**: the section swept along local X through taper rings. Each ring is a homothetic scale of the
  section, so every facet stays planar. The hero widens from 0.62 at its raised end to 1.22 at its foot (`HERO_TAPER`).
  - Ends: hand-placed ragged cuts on the hero (`HERO_RAGGED`) plus chips round its foot (`FOOT_CHIPS`); the chunks use
    `pc_auto_ragged`.
  - Long edges: angular cutters knocked out of the silhouette rims (`side_chips`). The boolean keeps the material slots;
    `pl_cut` re-appends them and every face falls back to the broad colour.
  - A positive roll tips the top toward the viewer; the hero uses a negative roll to show its front ridges.
- **Placement (`pc_build`)**: the chunks lie on the ground. The hero stands on its foot and its lift is searched downward
  until it first touches the left chunk (BVH overlap), so it rests there. The front chunk is pushed away from whatever it
  touches until it is clear of both.

Dead ends, kept out of the code: a flat stepped slab (a plank), V-notch grooves (tangled slivers), deep flutes with domed
ends (starbursts), eight thin ridges (corduroy), spall cuts (huge slate faces), and a broad slate front wall (the owner
wanted the ridges on that side).

It reuses the shared kits copied beside it from `biomass`.
