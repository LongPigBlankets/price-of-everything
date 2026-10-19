# Iron-air battery (g_061) Blender icon

Builder for the approved iron-air battery alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_061_iron_battery.png` (internal name `iron_battery`).
The approval record, renders and proof sheets are in `artifacts/goods_iron_battery/`.

It keeps the shipped art's layout: a grey steel cabinet on a yellow castor skid, a stack of blades down its long front,
rounded windows in its end, and a charcoal cover printed "Fe-Air" on top. It is drawn in the battery family's style (the
sodium and lithium packs), with the fixed orthographic goods camera, the set's light, 12/4 px ink (thinner on the
blades, castors, pipe and bracing) and dots on the shaded sides. The installed revision is `iron_battery_v11`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
blender -b --factory-startup --python-exit-code 1 --python tools/goods_icons/iron_battery/render.py -- <out_dir> iron_battery
python3 tools/goods_icons/iron_battery/icon_export.py <out_dir>/iron_battery_raw.png <out_dir>/iron_battery_800.png --vib 1.0
```

Re-rendered from this folder at install, the 800 px master was pixel-identical to the approved one.

## `fe_kit.py`

- **The cabinet (`CAB`)** is deep, as real iron-air enclosures are. A cutter box opens a bay over the blade stack (`BAY`
  deep), roof included, so the blades' tops show from above. The housing starts at `FRONT`, the bars' front plane, so
  its end walls and sill wrap round flush with the bracing. Faces inside the cabinet take the dark inside tone. A
  hand-written cutter box must have its faces wound outward for the boolean.
- **The blades (`FINS`)** fill the whole front and run back to the bay's rear wall. They have their own ramp, so their
  front edges read as mid charcoal, and 3 px lines; heavier lines at their pitch merge into a block.
- **The bracing** is two thin steel bars (`fe_bar`) from the top of each end wall to the bottom middle, a symmetric V.
  They stand proud of the housing; each tip hooks over the wall's top edge and the V's point clips over the sill.
- **The castors** have a swivel plate, a fork and a steel hub on the wheel's outer face, so they read under the skid.
- **The cover** sits behind the bay, with the print laid along +X.

It reuses the shared kits copied beside it from `sodium_battery`.
