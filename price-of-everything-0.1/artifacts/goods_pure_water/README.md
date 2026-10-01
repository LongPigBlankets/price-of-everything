# Pure water (g_009) Blender icon

**Approved 2026-09-29** (owner: "cool, approved"). v22 is installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_009_pure_water.png` (800, 450 and
256 px), and listed in `approved_manifest.json` with source `goods_pure_water/v22`. The shipped
main art in `assets/icons/goods/{medium,small,very_small}/` is unchanged; the alternate takes
priority at runtime.

## v22 (approved)

- `pure_water_800.png` is the transparent master. `pure_water_450.png`, `pure_water_256.png` and
  `pure_water_60.png` are LANCZOS downsizes of it. The 800, 450 and 256 px files are the
  installed tiers.
- `pure_water.blend` is the editable saved scene.
- `comparison.png` sets the shipped art beside v22. `ds2_well.png` shows it at game size (72 and
  144 px wells) beside approved neighbours. `owner_sheet_junctions.png` shows the pipe junctions
  before (v18) and after (v22), with the master.
- `pure_water_metrics.json` is the build record (dimensions, outline and stipple settings, mesh
  checks). `saved_scene_verification.json` checks the camera, closed hosts and contacts (no
  failures). `pure_water_800_line_weights.json` records the 12 px outer and 6 px inner lines.
  `pixel_metrics.json` holds the ink, water and khaki measurements.

The builder and re-render commands are in `tools/goods_icons/pure_water/`. Re-rendered from that
copy at install, the 800 px master came out byte-identical to the one here.

## Review record

- Owner ruling, v18 to v22: "look at the flange and ribs on the pipe. It's ignoring where the
  flange meets the pipe." A step must show its face, with ink on both edges. From the fixed
  camera a face turned away never shows, so steps that face away (the flange's back, the
  coupling's back) are 30 degree shoulders. The coupling's front is a crescent closed by the
  pipe's own silhouette edges. The post's collar shows below the coupling.
- Two adversarial review rounds, on v5 and v11. Their asks were folded into the build, except
  one overrule: the reference's dense full-ink halftone screen and an 8.5 px line tier were not
  adopted, because the approved alternates carry 2.5-3.7 % dots and 12/6 px lines.
- The water is clean (no dots), per the glass ruling.
