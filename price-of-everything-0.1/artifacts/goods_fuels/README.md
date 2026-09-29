# Diesel fuel (g_031) Blender icon

**Approved 2026-09-29** (owner: "great, approved", on v9). The good's internal name is `fuels`; the
catalogue calls it Diesel Fuel. v9 is installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_031_fuels.png` (800, 450 and
256 px), and listed in `approved_manifest.json` with source `goods_fuels/v9`. The shipped main art
(`assets/icons/goods/{medium,small,very_small}/g_031_fuels.png`) is unchanged; the alternate takes
priority at runtime.

## v9 (installed)

- `fuels_800.png` is the transparent master. `fuels_450.png`, `fuels_256.png` and `fuels_60.png`
  are LANCZOS downsizes of it. The 800, 450 and 256 px files are the installed tiers.
- `fuels.blend` is the editable saved scene. `diesel_kit_v9.py` is the builder as installed (the
  same file as `tools/goods_icons/fuels/diesel_kit.py`).
- `owner_sheet.png` is the sheet the owner approved: diesel fuel v8 beside v9, and the ICE car as
  installed beside the ICE car with its can in the pump red. That car change is installed and
  recorded separately, in `artifacts/goods_icon_diesel/passat_rebuild/can_pump_red/`.
- `v8_owner_sheet.png` is the v8 sheet: the shipped art beside v5 and v8, with close-ups of the
  holster (the hose coming out of the hole), the pistol nozzle, the can and the same can on the
  ICE car. `v8_nozzle_compare.png` sets the shipped nozzle beside v8's.
- `comparison.png` sets the shipped art beside v8 and v9. `regions_3x.png` is the 800 px master's
  four quadrants at 3x. `ds2_well.png` shows it at game size (72 and 144 px wells) beside the old
  diesel art and the approved processed oil, crude oil, ICE car, chlorine and alkaline battery
  alternates. Its ICE car is the one installed in the main checkout, with the can in its old red.
- `fuels_metrics.json` is the build record (dimensions, the can's builder, size, place and cap
  swing, the nozzle's profiles, outline and stipple settings, camera, mesh checks).
  `saved_scene_verification.json` checks the camera, closed hosts, contacts and clearances (no
  failures). `fuels_800_line_weights.json` records the 12 px outer and 6 px inner lines.
  `pixel_metrics.json` holds the bounding box, ink colour, grey-step measurements and the red
  paint's share (0.485); its cream share is 0.

The builder and re-render commands are in `tools/goods_icons/fuels/`. Re-rendered from that copy
at install, the 800 px master came out byte-identical to the one here.

## Record

Owner direction: "approved, let's move on to diesel fuel".

Owner rulings on the way, in order:

1. On v5: "reuse the canister used on the ICE car, dont build it from scratch. The refine the
   shape of the pistol and look at the hose coming out of the petrol pump, the cable needs to
   come out of a hole"
2. On v8: "make the canister the same colour as the pump in this icon and the diesel car icon
   too"
3. On v9: "great, approved"

Rulings carried over from the earlier goods: keep the shipped art's layout (it is already lit like
the set, so it is kept as drawn), draw on the isometric grid, light with the set's light, stipple
the shaded sides, ink every junction between parts, and use 3 px lines for small detail.

What it is:

- The shipped layout on the grid, lit like the set. A red fuel pump (1.0 x 1.5 x 3.05 on a 0.15
  plinth, every edge rounded, a raised rim round the +X display face) carries a light display
  panel (two readouts and three buttons, in 3 px lines).
- On its -Y face, a holster that is a real hole (light walls, a bezel round it, 3 px inner
  corners), with the hose coming out of it and hanging in a loop round the front-left corner.
- A second hose arches from the pump to a pistol nozzle: a tall chamfered head with the spout
  dropping from its underside, a slim handle back to a grey hose collar, and a D-shaped trigger
  guard with the lever inside. The spout feeds the jerrycan's neck.
- The can is the ICE car's (g_056), built by that icon's own builder,
  `build_reference_jerrycan` (yaw 90, D 1.25), plus an adapter for the standard exporter: part
  labels, and ink paths read off the can's own geometry (its loft profile's perimeter and sharp
  depth corners, the pressed X's rims found on the finished Boolean mesh, the neck and cap rims).
  Its own cap is swung open 158 degrees on the neck.
- The can's two materials are rebuilt in place with the pump red's three tones: shade
  (160,58,49), -Y faces (190,78,66) and tops (211,113,100), with a set 0.55 darker for the neck
  and the pressing floors. They keep the can's toon thresholds (0.66, 0.92), so the pump's and
  the can's pixels share the same three tones.

Revisions:

1. v1-v5: first builds (a box can, a stick nozzle, the holster as a print).
2. v6: the ICE car's can, the holster as a hole, a pistol nozzle (owner ruling 1).
3. v7: the cap swung further open.
4. v8: the pistol reshaped after the shipped nozzle.
5. v9: the can in the pump red (owner ruling 2). Approved.

Checks:

- `ds_verify.py` on v9: no collisions (the hoses clear the can, the plinth and each other; the
  nozzle and the open cap clear the can and its handle); the spout sits in the neck and in the
  nozzle's head; closed hosts; nothing below ground.
- A repeat render of v9 was pixel-identical.
- No independent review ran this round; the iterations were owner-directed.
