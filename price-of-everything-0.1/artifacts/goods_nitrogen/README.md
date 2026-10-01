# Nitrogen (g_068) Blender icon

**Approved 2026-09-29** (owner: "approved", on v5). The good's internal name is `nitrogen`. v5 is
installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_068_nitrogen.png` (800, 450 and
256 px), and listed in `approved_manifest.json` with source `goods_nitrogen/v5`. The shipped main
art (`assets/icons/goods/{medium,small,very_small}/g_068_nitrogen.png`, a silver liquid-nitrogen
dewar) is unchanged; the alternate takes priority at runtime.

This icon replaces the shipped art's subject, by owner direction, and was built from the owner's
description, as no file matching it was found (see Record).

## v5 (installed)

- `nitrogen_800.png` is the transparent master. `nitrogen_450.png`, `nitrogen_256.png` and
  `nitrogen_60.png` are LANCZOS downsizes of it. The 800, 450 and 256 px files are the installed
  tiers.
- `nitrogen.blend` is the editable saved scene. `nitrogen_kit_v5.py` is the builder as installed
  (the same file as `tools/goods_icons/nitrogen/nitrogen_kit.py`).
- `owner_sheet.png` is the sheet the owner approved: the shipped silver dewar beside v4 and v5, and
  the DS2 well. `v2_owner_sheet.png` (the dewar beside v2) and `v4_owner_sheet.png` (the dewar
  beside v2 and v4) are the sheets the owner's two rulings answered, each with the well.
- `comparison.png` sets the shipped art beside v4 and v5. `regions_3x.png` is the 800 px master's
  four quadrants at 3x. `ds2_well.png` shows it at game size (72 and 144 px wells) beside the old
  nitrogen art and the approved oxygen, ammonia, hydrogen, chlorine and lithium-ion alternates.
- `history_sheet.png` and `compare_shipped_downloads.png` are the search for the icon the owner
  described. The history sheet sets the three nitrogen icons in git history side by side (commits
  2356031f of 19 Jun, 0981d717 of 24 Jun, and fb8c2a34 of 26 Jun, the shipped one). The other sets
  the shipped art beside the Downloads source (`nitrogen.png`, on a magenta key). All are silver
  liquid-nitrogen dewars, as is the research node icon
  (`assets/icons/research/nodes/research_inorg_014.png`, not on the sheets).
- `nitrogen_metrics.json` is the build record (the shell, diamond, lettering and sheen dimensions,
  the outline and stipple settings, camera, mesh checks). `saved_scene_verification.json` checks
  the camera, closed hosts, the valve's contacts and the prints' clearances and standoffs (no
  failures). `nitrogen_800_line_weights.json` records the set's 12 px outer and 6 px inner lines.
  `pixel_metrics.json` holds the bounding box, ink colour, grey-step measurements, the green share
  (the shoulders and the diamond's border: 0.292) and the cream share (the white face: 0.051).

The builder and re-render commands are in `tools/goods_icons/nitrogen/`. Re-rendered from that
copy at install, the 800 px master came out byte-identical to the one here.

## Record

Owner direction: "ok next go for pvc and nitrogen. I recommend using the new nitrogen (should be a
canister with grey body and green diamond on it) rather than the current silver on[e]".

No file matching that description was found anywhere: every nitrogen icon in the project and its
git history (three versions), the research node icon and the Downloads source are all silver
liquid-nitrogen dewars (see the two search sheets above). So the icon was built from the
description. The rulings that keep the shipped art's layout and marks don't apply: the owner asked
for a different object.

Owner rulings on the way, verbatim, in order:

1. On v2 (v2 -> v3): "darker grey, slightly metallic blue and make the green label be in the middle
   and the N2 text sits inside the diamond. Navy text on white diamond with thick green outline"
2. On v4 (v4 -> v5): "thicker green outline for nitrogen and rounded corners on the diamond. maybe
   also green shoulders"
3. On v5: "approved"

Rulings carried over from the earlier goods: draw on the isometric grid, light with the set's
light, stipple the shaded side and keep printed labels clean, and ink every junction between parts.

What it is:

- One upright steel gas cylinder on the grid (body radius 0.5, shell 2.19 tall: a foot bevel, the
  straight body, an elliptical shoulder and the neck; 2.73 to the top of the handwheel) in a dark,
  slightly metallic blue-grey, with a thin sheen streak down its lit side. The set's light turns
  its right (+X) flank to shade, dotted.
- The shoulder dome is painted green: its mid tone is the diamond's green, and the shoulder seam's
  line runs between it and the body.
- A diamond centred on the body, wrapped round the side that faces the camera: a green diamond
  (0.96 diagonal) with rounded corners, and a white rounded face (0.58 diagonal, so the green
  border is about 0.134 thick) carrying "N2" in navy Arial Bold with the subscript. The rounded
  shapes are fine grids pulled radially onto a rounded square, so they follow the cylinder without
  sagging. The diamond, its face and the lettering stand off the shell by 0.005, 0.008 and 0.011.
- A valve: a collar on the neck, the valve body, an outlet toward -Y with a dark bore, a spindle,
  and a handwheel ring on two spokes.

Revisions:

1. v1: a grey cylinder with the UN 2.2 green diamond (its white cylinder symbol and a "2") and a
   white N2 band.
2. v2: a stockier cylinder and a bigger diamond.
3. v3-v4: a darker, slightly metallic blue-grey; one centred white diamond with a green border and
   navy N2 on it (owner ruling 1).
4. v5: a thicker border, rounded corners and green shoulders (owner ruling 2). Approved.

Checks:

- `n2_verify.py` on v5: the valve's parts are joined (the collar on the neck, the body on the
  collar, the outlet and the spindle in the body, and the handwheel ring joined to the spindle
  through its two spokes); the diamond, its face and the lettering stand off the shell by
  0.005/0.008/0.011 and don't touch it or each other; closed hosts; nothing below ground.
- A repeat render of v5 was pixel-identical.
- No independent review ran this round; the iterations were owner-directed.
