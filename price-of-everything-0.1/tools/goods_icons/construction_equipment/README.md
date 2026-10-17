# Construction equipment (g_071, g_072) Blender icon

Builder for the approved construction equipment alternate icon. One image serves both goods:
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_071_construction_equipment_ice.png` and
`.../g_072_construction_equipment_ev.png`. The approval record, renders and proof sheets are in
`artifacts/goods_construction_equipment/`.

It shows a backhoe loader, a standing hand-held hydraulic breaker and a site toolbox. All dimensions are in metres, on
the fixed orthographic goods camera, with the set's light, 12/4 px ink (6/3 px on the breaker and toolbox) and dots
on the shaded sides. The installed revision is `construction_equipment_v7`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
blender -b --factory-startup --python-exit-code 1 --python tools/goods_icons/construction_equipment/render.py -- <out_dir> construction_equipment
python3 tools/goods_icons/construction_equipment/icon_export.py <out_dir>/construction_equipment_raw.png <out_dir>/construction_equipment_800.png --vib 1.0
```

Re-rendered from this folder at install, the 800 px master was pixel-identical to the approved one.

## `ce_kit.py`

- **Constants:**
  - `REAR` and `FRONT`: axle, tyre radius, width and track.
  - `BREAKER` and `TOOLBOX`: where they stand and their scale.
  - `SIDESHIFT`: how far the backhoe carriage sits toward the visible side.
- **Primitives:** `ce_box`, `ce_prism_y` and `ce_prism_z` (profiles extruded), `ce_cyl`, `ce_arc_shell` (wheel
  guards), `ce_beam` (box-section members swept along a path) and `ce_ram` (dark barrel, bright rod).
- **`ce_wheel()`:** a tyre with 18 alternating tread lugs and a sidewall ring. On its outer face, a yellow wheel with a
  dished disc, a raised centre, six nuts and six vent holes.
- **`build_construction_equipment()`:** builds, in order:
  - the chassis, the rear deck, the hood and grille;
  - the half-octagon cab (`ce_prism_z` plans, pillars at every angle);
  - the wheels and guards;
  - the loader (towers, arms, rams, pins, bucket);
  - the backhoe (carriage rail, swing post, boom, dipper, D-bucket, rams on lugs, pins), slid by `SIDESHIFT`;
  - the stabilisers;
  - the breaker;
  - the toolbox.

  Part labels drive the component boundary lines. `outer_by_label` and `component_weight_by_label` thin the
  breaker's and toolbox's lines.

It reuses the shared kits copied beside it. `standard_lines.py` here differs from the building frame's copy in one line:
each outline pixel takes its weight from the nearest pixel that belongs to a part.
