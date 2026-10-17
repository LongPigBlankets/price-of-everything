# Car body (g_045) Blender icon

Builder for the approved car body alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_045_car_body.png` (internal name `car_body`). The approval
record, renders and proof sheets are in `artifacts/goods_car_body/`.

It shows two unfitted body shells, as the shipped art does:

- **The car:** the approved diesel car's Passat sedan (the same loft as `complex_goods/diesel_car`).
  - It is hollowed, with a grey inside and dark cavities.
  - Window, screen, lamp and radiator apertures are cut with return flanges.
  - Inside are a firewall, a slam panel, a parcel shelf and dark wheelhouse liners.
  - The bonnet is hinged at its rear corners and propped open at 65 degrees on a stay.
- **The lorry cab:** a blue cab-over beside the car, built the same way, plus:
  - a bumper with its lamp and radiator pockets;
  - a roof fairing;
  - a floor and a dash.

It uses the fixed orthographic goods camera, the set's light, 12/4 px ink and dots on the shaded sides. The installed
revision is `car_body_v17`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
blender -b --factory-startup --python-exit-code 1 --python tools/goods_icons/car_body/render.py -- <out_dir> car_body
python3 tools/goods_icons/car_body/icon_export.py <out_dir>/car_body_raw.png <out_dir>/car_body_800.png --vib 1.0
```

A full build takes about two minutes. Most of that is the booleans and the cavity pass. Re-rendered from this folder at
install, the 800 px master was pixel-identical to the approved one.

## `car_body_kit.py`

- **`cb_loft()`:** the diesel car's body loft, copied unchanged from `complex_goods/diesel_car/source/passat.py`.
- **`cb_prism()` / `cb_outline()`:** cutters. A 2D outline is projected onto the body, pushed out by 0.12, and in by
  the skin plus `FLANGE`. The cutters' walls stay as return flanges; their caps are dropped.
- **`cb_skin()`:** keeps the painted faces and the cutter walls, then thickens the skin inward by `SKIN`. Materials
  are paint, primer (the inside and rims) and liner (the wheelhouses, dark).
- **`cb_cavity()`:** inside faces where more than 70% of 24 hemisphere rays hit the body take the dark cavity tone.
  Three majority passes over each face's neighbours then smooth the boundary.
- **`build_car_body()`:**
  - cuts the bonnet free along its seams and the openings;
  - adds the bulkheads, clipped to the inside of the body;
  - hinges the bonnet at `HINGE_X` and opens it by `BONNET_OPEN`;
  - draws the stay and the door shut lines as ink lines;
  - then adds the cab.
- **`cb_cab()`, `CAB`, `cab_front_x()`:** the lorry cab.
  - It is a rounded slab (`cb_rslab`) raked back on a curve (`rake`, `rake_power`).
  - The windscreen, grille and door-window apertures are cut into it, with step and handle pockets and a wheel arch
    kept as liners.
  - A door shut line follows the arch.
  - The floor and dash are clipped inside.
  - The bumper has dark lamp sockets and a radiator pocket.
  - The roof fairing is a smooth loft.
  - It is placed at `CAB['at']` and scaled by `CAB['scale']`.

It reuses the shared kits copied beside it (`sprite_kit.py`, `base_kit.py`, `plastics_kit.py`'s toon and mesh-line
helpers, `goods_icon_kit.py`'s contract, `standard_lines.py`'s export).
