# Heavy vehicle (g_055) Blender icon

Builder for the approved heavy vehicle alternate icon,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_055_heavy_vehicle.png` (internal name `heavy_vehicle`).
The approval record, renders and proof sheets are in `artifacts/goods_heavy_vehicle/`.

It keeps the shipped art's layout: a blue cab-over tipper lorry in front of a green electric locomotive, both running
along world X with their noses to the viewer's right. It uses the fixed orthographic goods camera, the set's light,
12/4 px ink (thinner on the loco's front, bogies and small parts) and dots on the shaded sides. The installed revision
is `heavy_vehicle_v38`.

## Re-render

From the game directory (`price-of-everything-0.1`):

```sh
blender -b --factory-startup --python-exit-code 1 --python tools/goods_icons/heavy_vehicle/render.py -- <out_dir> heavy_vehicle
python3 tools/goods_icons/heavy_vehicle/icon_export.py <out_dir>/heavy_vehicle_raw.png <out_dir>/heavy_vehicle_800.png --vib 1.0
```

Re-rendered from this folder at install, the 800 px master was pixel-identical to the approved one.

## `hv_kit.py`

- **The lorry (`hv_lorry2`, `hv_lorry_details`, `LORRY`)**: the approved car-body cab (`cb_cab`) is built at the origin
  in its own units and glazed (`hv_glass_slab`), then the lorry is built back from it: chassis rails, three axles, a
  fuel tank, a long open tipper with a dark inside, the tipper's headboard and rims, an under-run bar, arc guards over
  the rear tandem, a visor, wipers, a mirror, headlamps, a plate and grille slats. The whole lorry is then scaled 0.43
  into the scene, mesh data and ink paths alike. After a boolean (`hv_cut`) the material slots are set explicitly,
  because the cutter adds a slot and shifts the indexes.
- **The locomotive (`hv_loco3`, `LOCO3`)**: a 2010s Bo'Bo' electric in real proportion, scaled from the Siemens Vectron
  at the body's width (0.349 units a metre): 6.0 long, roof at 1.60, bogie centres 55% of the length, 1.05 between
  axles, 1.25 m wheels.
  - **Body**: an extrusion of `hv_loco_section3` (upright sides, a knuckle at the shoulder band, a tight rounded
    shoulder, so the flat top is wide). Each nose is three half-space cuts that lean back more from face to face
    (`hv_nose_planes`: lower face, windscreen, cap), so the nose stays convex; a notch cannot be cut this way. Corner
    chamfers are vertical cuts. The taupe hood is every face above the band or facing an end.
  - **Nose**: the windscreen panes are the screen face's own outline inset (`hv_inset`, which clips by each edge's line
    moved inward and so tolerates short edges) and split by `hv_clip`, in a dark frame. `hv_on_plane` places the
    radiator grilles flush on the leaning lower face, their outer edges running with the chamfer edge. The lamp housing
    sits on the near chamfer only, as the far one faces away and its leaning housing poked past the outline. A buffer
    beam carries long buffers, a coupler, hoses and a deflector.
  - **Sides**: two long continuous grilles either side of a builder's plate (four screws, three pointed-top hexes, one
    over two), doors with rounded corners, a grab rail and a step, and an angled skirt that tucks in at the bottom.
  - **Roof**: everything sits on the flat top and is centred across it: pantographs folded low near each end, a breaker
    box with insulators inboard of each, a conductor bar between them, and a central hatch with three fan grilles. The
    pantographs are real tubes (`hv_rod`) on their own part label with a thin outer line; drawn as lines they vanished,
    and as small solids they turned into black blobs under the 12 px silhouette.
  - **Bogies**: a dark frame over the axles, axleboxes under spring nests, sandboxes and a brake rod; the wheels' light
    webs keep them reading as wheels.
- **Labels**: id_step 8 allows 31. The lorry holds 1 to 9 and 16 to 18; the loco 10 to 15 and 19 to 31.

## `standard_lines.py`

This copy differs from the shared one in one place. With `outer_by_label`, each silhouette pixel takes the outer weight
of the nearest *labelled* pixel. Thin parts have edge pixels that the id pass leaves unlabelled; taking the default
weight there drew full-weight ticks along the thin, lighter-lined parts.

It reuses the shared kits copied beside it from `car_body`.
