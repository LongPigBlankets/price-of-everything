# Car body (g_045) Blender icon

**Approved 2026-10-17** (owner: "Car body v17 approved. Install it as the alternate icon"). The internal name is
`car_body`. v17 is installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_045_car_body.png` (800, 450 and 256 px), and listed in
`approved_manifest.json` with source `goods_car_body/v17`. The shipped main art is unchanged; the alternate takes priority
at runtime.

## v17 (installed)

- **Renders:** `car_body_800.png` is the master. `car_body_450.png`, `car_body_256.png` and `car_body_60.png` are
  LANCZOS downsizes of it, and the 800, 450 and 256 px files are the installed tiers. `car_body_raw.png` and
  `car_body_raw_mask.png` are the Blender colour and shading passes.
- **Scene and builder:** `car_body.blend` is the saved scene, and `car_body_kit_v17.py` the builder as installed. The
  live builder and render tooling are in `tools/goods_icons/car_body/`.
- **Records:** `car_body_metrics.json` is the build record, and `car_body_800_line_weights.json` records the 12/4 px
  lines. `runtime_check.gd` loads the three tiers and checks sizes and mipmaps.
- **Proof sheets:**
  - `owner_sheet.png`: shipped / v16 / v17.
  - `owner_sheet_v11.png` to `owner_sheet_v16.png`: the earlier rounds.
  - `front_3x.png`: the cab's bumper.
  - `strip_study.png`: the first step, the diesel car with every non-body part removed.

## Record

Owner direction, verbatim, in order:

1. "ok now let's do the car body one. First appraise the existing diesel car blender file and try to remove all parts
   that are not the body"
2. "Open up the shell: hollow it, cut the window and lamp openings, prop the bonnet open, and move it to the newer line
   pipeline. Leave the truck cab for later."
3. On v3: "keep refining. Use a grey interior. And the bonnet would not open at that angle. the hinges would be closer
   to the corners"
4. On v5: "Go with the 65 degree bonnet and keep refining."
5. "do make sure to first do the lorry cab body as part of the car body icon"
6. On v11: "Darken the inside of the wheel arch and sweep back a bit the top of the front of the lorry cab compared to
   the bottom. Also the headlight sockets need to be higher, wider and a bit angled on the inside. Also the door needs
   work. The top of the cab also needs work"
7. On v13: "the headlamps need to be angled the other way (narrower at the top). Also they need a radiator slot between
   them. And look at the old icon's cab for reference on height, because it looks like you're fighting against
   proportions with the door. Look at the topology of the cab"
8. On v14: "make the door's bottom match the shape on the old icon please. And bring the cab closer to the car body"
9. On v15: "make the headlight holes dark inside and the same for the radiator hole. Also make the radiator hole between
   the headlights a bit larger and wider"
10. On v16: "smaller headlamp cutouts (20% less tall and 30% narrower). Then the radiator cutout in the middle can widen
    at the top to have parallel sides to the headlamp cutouts"
11. On v17: "Car body v17 approved."

What the icon is:

- **The car:** the approved diesel car's Passat sedan loft, unchanged, made into a bare body shell.
  - It is cut along the diesel car's own glass, lamp and radiator outlines, with return flanges at every opening.
  - Inside there is a firewall, a slam panel and a parcel shelf, and dark wheelhouse liners.
  - It is hollowed to a skin with a grey inside. Faces deep in the hollow take a dark cavity tone, from a 24-ray
    occlusion test, so the openings read as holes.
  - The bonnet is cut along its seams, hinged at its rear corners and propped at 65 degrees on a stay.
- **The lorry cab:** a European cab-over beside the car, about 1.2x as tall as it is wide, as on the old icon.
  - Its front sweeps back toward the top on a curve.
  - It has a high wheel arch with a door whose bottom follows it.
  - Entry steps and a door handle.
  - A windscreen and grille band.
  - A bumper stepped forward, with dark headlamp sockets (narrower at the top) and a radiator slot whose sides run
    parallel to them.
  - A smooth roof fairing.
  - A floor and a dash inside.

Two independent reviews (v5, v10) fed the rounds between the owner's notes.
