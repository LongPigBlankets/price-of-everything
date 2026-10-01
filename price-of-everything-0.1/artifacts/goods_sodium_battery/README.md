# Sodium-ion battery (g_060) Blender icon

**Approved 2026-09-29** (owner: "approved"). v12 is installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_060_sodium_battery.png` (800,
450 and 256 px), and listed in `approved_manifest.json` with source `goods_sodium_battery/v12`.
The shipped main art (`assets/icons/goods/{medium,small,very_small}/g_060_sodium_battery.png`) is
unchanged; the alternate takes priority at runtime.

## v12 (approved)

- `sodium_battery_800.png` is the transparent master. `sodium_battery_450.png`,
  `sodium_battery_256.png` and `sodium_battery_60.png` are LANCZOS downsizes of it. The 800, 450
  and 256 px files are the installed tiers.
- `sodium_battery.blend` is the editable saved scene. `sodium_kit_v12.py` is the builder as
  approved (the same file as `tools/goods_icons/sodium_battery/sodium_kit.py`).
- `owner_sheet.png` sets the shipped art beside v12, with the DS2 well below. `comparison.png`
  sets the shipped art beside v10 and v12. `cells_v10_v12.png` shows the cells before (v10, plates
  in 6 px lines) and after (v12, 3 px lines, plates inset from the back and left edges).
  `plate_zoom4x.png` shows v12's plates at 4x: one in the front row, and one on the middle row
  running under the cover. `regions_3x.png` is the 800 px master's four quadrants at 3x.
  `ds2_well.png` shows it at game size (72 and 144 px wells) beside the old sodium and lithium
  battery art and the approved alkaline, power, electrical components and computer alternates.
- `sodium_battery_metrics.json` is the build record (dimensions, outline and stipple settings,
  camera, mesh checks). `saved_scene_verification.json` checks the camera, closed hosts, contacts
  and clearances (no failures). `sodium_battery_800_line_weights.json` records the 12 px outer and
  6 px inner lines. `pixel_metrics.json` holds the bounding box, ink colour and grey-step
  measurements.

The builder and re-render commands are in `tools/goods_icons/sodium_battery/`. Re-rendered from
that copy at install, the 800 px master came out byte-identical to the one here.

## Review record

Owner direction: "Next go for sodium ion batteries". Two owner fixes on the way:

1. v8 to v9/v10: "we seem to have lost the outline of each individual unit in the crate. They had
   rounded corners. And also a plate on top of the cathode-less section". Each cell is now its own
   rounded block with its own outline, with 0.045 grooves between the cells, and carries a raised
   rounded plate behind its terminals. On the middle row the plates run under the cover.
2. v10 to v11/v12: "maybe thinner lines for those plates?". The plates are inked in 3 px paths,
   half the set's 6 px interior weight: an owner-approved third weight, for this icon only. They
   share their cell's part label, so no 6 px boundary is drawn round them. They are 0.02 thick and
   inset 0.06 from the cell's back and left edges: on this camera a raised edge inset by its own
   height from a -X or +Y edge draws on that edge's line (v11's back and left plate edges vanished
   into the cell outline).

Rulings carried over from the earlier goods: keep the shipped art's layout (it is already lit like
the set, so it is kept as drawn: the short side lower left is world -Y, the long side lower right
is world +X, the cells in front, the cover at the back), draw on the isometric grid, light with the
set's light, stipple the shaded sides, ink every junction between parts, and keep the shipped
art's printed marks ("Na-ion").

What that produced:

- An open steel crate, 1.00 x 1.11 x 0.54 (measured off the shipped art), with 0.03 walls and a
  0.05 rim lip. Its walls carry slots, 6 across the -Y side and 7 along the +X side: two rows of
  tall rounded slots and a row of small ones. Each slot has one outer outline; the wall's
  thickness shows as a tone crescent, and the cells share the crate's part label, so no second
  ring is drawn where a slot's inner edge meets them.
- 3 x 3 white cells (two rows visible) with light-grey terminal pegs along their fronts.
- A charcoal cover over the back, printed "Na-ion" in Arial Bold, its top under the rim.

Revisions:

1. v1-v4: the slots and terminals (ink rings in the slots, stray bars through them, and terminal
   outlines that filled the pegs with ink).
2. v5: reviewed (see Checks).
3. v6-v8: the review's rule applied: anything shown between two 6 px lines is at least 0.045
   across or is left out. That gave the rim lip, a 0.045 cover, whiter windows, lighter terminals
   placed 0.03 clear of the rim's shadow, and cells that meet.
4. v9-v10: individual rounded units and raised plates (owner fix 1).
5. v11-v12: thin plate lines and plate insets (owner fix 2). Approved.

Checks:

- Saved-scene verification of v12: no collisions between terminals, plates and cover; the cells
  stand on the floor clear of the walls and lip; nothing but the terminal posts rises above the
  rim.
- A repeat render of v12 was pixel-identical.
- One adversarial review ran, on v5. Layout, grid, lighting, dots and ink colour passed. It was
  not ready because the 0.02-0.03 features collapsed into 15-28 px bars and the interior ink share
  was about 70 % above the sibling icons. Its fixes were folded into v6-v8.
- Interior ink share by a simple measure: v5 0.277; v12 about the approved wind turbine's 0.239.
