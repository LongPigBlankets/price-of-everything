# Lithium-ion battery (g_059) Blender icon

**Approved 2026-09-29** (owner: "approved"), first version. v1 is installed as the approved
alternate, `assets/icons/goods/alternate_icons/{medium,small,very_small}/g_059_lithium_battery.png`
(800, 450 and 256 px), and listed in `approved_manifest.json` with source
`goods_lithium_battery/v1`. The shipped main art
(`assets/icons/goods/{medium,small,very_small}/g_059_lithium_battery.png`) is unchanged; the
alternate takes priority at runtime.

## v1 (approved)

- `lithium_battery_800.png` is the transparent master. `lithium_battery_450.png`,
  `lithium_battery_256.png` and `lithium_battery_60.png` are LANCZOS downsizes of it. The 800, 450
  and 256 px files are the installed tiers.
- `lithium_battery.blend` is the editable saved scene. `lithium_kit_v1.py` is the builder as
  approved (the same file as `tools/goods_icons/lithium_battery/lithium_kit.py`).
- `owner_sheet.png` sets the shipped art beside v1, with the DS2 well below. `comparison.png` sets
  the shipped art beside v1. `zoom_cells.png` shows the red cells, their thin-lined plates and the
  red + washers. `regions_3x.png` is the 800 px master's four quadrants at 3x. `ds2_well.png` shows
  it at game size (72 and 144 px wells) beside the old lithium art and the new sodium-ion,
  alkaline, power, electrical components and computer alternates.
- `lithium_battery_metrics.json` is the build record (dimensions, outline and stipple settings,
  camera, mesh checks). `saved_scene_verification.json` checks the camera, closed hosts, contacts
  and clearances (no failures). `lithium_battery_800_line_weights.json` records the 12 px outer and
  6 px inner lines. `pixel_metrics.json` holds the bounding box, ink colour, grey-step and
  red-share measurements.

The builder and re-render commands are in `tools/goods_icons/lithium_battery/`.

## Record

Owner direction: "approved. please do Lithium ion next" (on approving sodium-ion v12).

The shipped lithium-ion art is the sodium-ion pack with red cells, so v1 is built by the approved
sodium builder, `sodium_kit.build_ion_pack`, unchanged: the slotted steel crate (1.00 x 1.11 x
0.54, 0.05 rim lip), individual rounded cells 0.045 apart with raised plates inked in 3 px (the
owner-approved third weight from sodium), light-grey terminal pegs and the charcoal cover.
`lithium_kit.py` changes only:

- the cells and plates: coral red, linear (0.70, 0.107, 0.098), a lit top of about (218,92,88)
  (the shipped art's are about (208,95,95)); the red shows through the wall slots as shipped;
- the lettering: "Li-ion" in Arial Bold on the cover;
- the + terminals: as shipped, each cell's left (+) terminal sits on a dark-red washer, linear
  (0.402, 0.045, 0.048), while the right (-) washer stays plain grey. The red washer shares the
  terminal's part label, so no line is drawn between washer and post.

Carried-over rulings: the shipped layout (already lit like the set, so kept as drawn), the
isometric grid, the set's light, dots on the shaded sides, ink at every junction, and the shipped
art's printed marks.

Checks: `li_verify.py` on v1 reported no failures (no collisions; the + washers clear the plates
and cover; cells on the floor, clear of the walls and lip; nothing but terminal posts above the
rim). A repeat render of v1 was pixel-identical. Sodium rendered from the lithium workspace was
byte-identical to the approved sodium v12, so the shared builder is unchanged. No separate
adversarial review: only colours, lettering and the + washers differ from the reviewed and
approved sodium design.
