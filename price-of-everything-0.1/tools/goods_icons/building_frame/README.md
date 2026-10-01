# Building frame (g_023) Blender icon

Builder for the approved building frame alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_023_building_frame.png` (internal name `building_frame`).

It shows the shipped art's steel cube frame, with four square-tube corner posts and rings of beams at the bottom,
middle and top. A white pane sits on the top ring. Three bundles of black cable with a yellow tracer stripe are draped
over the top: the left one runs down to the middle ring, along it and into the front bundle, which goes to the ground,
and the right one loops over its corner. Two copper pipes rise through cutouts in the three beams on the +X face by
the front post, their bores showing at the top. These parts are the recipe's steel, windows, electrical components
and copper pipe.

The steel takes the approved steel icon's blue-grey, the pipes the copper pipe icon's copper and the pane the windows
icon's white. It uses the fixed orthographic goods camera, the set's light, 12/4 px ink and dots on the shaded sides.
The installed revision is `building_frame_v5`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/building_frame/render.py -- <out_dir> building_frame
python3 tools/goods_icons/building_frame/icon_export.py <out_dir>/building_frame_raw.png <out_dir>/building_frame_800.png --vib 1.0
python3 tools/goods_icons/building_frame/bf_proof.py <out_dir>
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 \
  --python tools/goods_icons/building_frame/bf_verify.py -- <out_dir>
```

`bf_verify.py` checks the camera, closed hosts and nothing below ground. It also checks that the pipes pass through
their cutouts without touching the beams, and that no cable passes into the frame, the pane or a pipe.

Re-rendered from this copy at install, the 800 px master was pixel-identical to the approved one, and the check reported
no failures.

## `frame_kit.py`

- **`bf_frame()`:** the posts and three rings of beams, as boxes inked by their own creases and contours.
- **`bf_cable()`:** a flat bundle of four cables.
  - The bundle's spread is carried along the path by parallel transport, so it turns like a ribbon and its cables stay
    side by side through every bend.
  - Each cable is a black sweep with a yellow stripe: the faces turned toward the viewer as far as the cable's own
    direction allows.
- **`build_building_frame()`:** builds the pane, the cable routes and the pipes.
  - The pipes are hollow tubes, centred in the +X beams' depth.
  - A boolean cutout is made in each beam, and the beam is re-inked so the cutout's rim is drawn.
  - Each pipe has a coupling between the bottom and middle rings and a dark bore at the top.

It reuses `plastics_kit.py`'s toon, sweep, cut and mesh-ink helpers.
