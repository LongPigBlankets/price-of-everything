# Alkaline battery (g_070) Blender icon

**Approved 2026-09-29** (owner: "approved"). v4 is installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_070_alkaline_battery.png` (800,
450 and 256 px), and listed in `approved_manifest.json` with source `goods_alkaline_battery/v4`.
The shipped main art (`assets/icons/goods/{medium,small}/alkaline_battery.png`) is unchanged; the
alternate takes priority at runtime.

## v4 (approved)

- `alkaline_battery_800.png` is the transparent master. `alkaline_battery_450.png`,
  `alkaline_battery_256.png` and `alkaline_battery_60.png` are LANCZOS downsizes of it. The 800,
  450 and 256 px files are the installed tiers.
- `alkaline_battery.blend` is the editable saved scene. `alkaline_kit_v4.py` is the builder as
  approved (the same file as `tools/goods_icons/alkaline_battery/alkaline_kit.py`).
- `comparison.png` sets the shipped art beside v3 and v4. `lid_v3_v4.png` shows the lid before
  and after the owner's fix. `ds2_well.png` shows it at game size (72 and 144 px wells) beside
  the old lithium battery art and approved neighbours.
- `alkaline_battery_metrics.json` is the build record (dimensions, outline and stipple settings,
  camera, mesh checks). `saved_scene_verification.json` checks the camera, closed hosts and
  contacts (no failures). `alkaline_battery_800_line_weights.json` records the 12 px outer and
  6 px inner lines. `pixel_metrics.json` holds the ink, grey-step, green and cream measurements.

The builder and re-render commands are in `tools/goods_icons/alkaline_battery/`. Re-rendered from
that copy at install, the 800 px master came out byte-identical to the one here.

## Review record

Owner direction: "Next look at alkaline battery". One owner fix on the way, v3 to v4:
"missing the - on the far side". v4 prints a - on the lid to the right of the - post, the way
the + sits by the + post.

Rulings carried over from power and pure water: keep the shipped art's layout, draw on the
isometric grid, light with the set's light, stipple the shaded sides; ink every junction between
parts.

What that produced:

- The shipped starter battery rebuilt on the grid in the same layout: the short end lower left
  (world -Y), the long label face lower right (world +X). The + terminal sits in a well at the
  front corner and the - terminal in a well at the right corner; both wells are cut from a raised
  panel on a charcoal lid slab that overhangs the case. Proportions measured off the shipped art:
  case 1.00 x 1.55 x 1.10.
- Under the set's light the long label face is the shade side. The case around the label carries
  the kit's 2x dot lattice (as on power), and the printed label (green frame, cream band, grey
  tabs, + and - discs) is kept clean so it reads. The end and the lid are lit and clean.

Revisions:

1. v1: first build. The label tabs were too big, a 0.04 ledge drew as a doubled line, and an ink
   tick showed at the - well's hidden corner.
2. v2: label rows re-measured from the shipped art, a 0.075 ledge, and vertical corner lines only
   where a corner can be seen.
3. v3: panel outlines stroked as round-jointed lines (the polygon strokes left a pinhole at sharp
   corners).
4. v4: the printed - (owner fix). Approved.

Checks:

- Saved-scene verification of v4: no collisions between terminals, panel and prints; closed
  solids; nothing below ground.
- A repeat render of v3 was pixel-identical.
- One adversarial review ran, on v3. Every criterion passed (stepped tones, dots only on +X faces
  and none on the label, 99.5 % of ink within 30 of navy, 12/6 px lines, every silhouette edge at
  30.00 degrees, all junctions inked, no artefacts, reads at 64 px) except the terminals: the
  collars read as stacked rings rather than the shipped art's flat washer. It suggested `R_COL`
  0.09 -> 0.105, `H_COL` 0.066 -> about 0.035-0.04, no collar split line, and `H_POST`
  0.135 -> 0.12. Not applied: the owner approved v4 as it is. It stays an optional follow-up.
