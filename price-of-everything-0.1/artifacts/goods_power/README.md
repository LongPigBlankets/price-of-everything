# Power (g_010) Blender icon

**Approved 2026-09-29** (owner: "approved"). v13 is installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_010_power.png` (800, 450 and
256 px), and listed in `approved_manifest.json` with source `goods_power/v13`. The shipped main
art in `assets/icons/goods/{medium,small,very_small}/` is unchanged; the alternate takes priority
at runtime.

## v13 (approved)

- `power_800.png` is the transparent master. `power_450.png`, `power_256.png` and `power_60.png`
  are LANCZOS downsizes of it. The 800, 450 and 256 px files are the installed tiers.
- `power.blend` is the editable saved scene. `power_kit_v13.py` is the builder as approved (the
  same file as `tools/goods_icons/power/power_kit.py`).
- `comparison.png` sets the shipped art beside v12 and v13. `ds2_well.png` shows it at game size
  (72 and 144 px wells) beside approved neighbours. `owner_sheet.png` is the owner's review sheet:
  the old art beside v13, then both in DS2 wells.
- `power_metrics.json` is the build record (outline, depth, stipple settings, camera, mesh
  checks); its `topology` string is left over from the v8 layout. `power_800_line_weights.json`
  records the 12 px outer and 6 px inner lines. `pixel_metrics.json` holds the ink and gold
  measurements.

The builder and re-render commands are in `tools/goods_icons/power/`. Re-rendered from that copy
at install, the 800 px master came out byte-identical to the one here.

## Review record

Owner rulings, in order:

1. "needs the lighting updated because the old ai icon has shading on the left side"
2. "don't flip the power icon, still show it in the same orientation but fix the lighting"
3. "i think the perspective is still broken. Need it to follow the isometric perspective"
4. "now rotate it so it has the same layout as the AI one"
5. "now we'll want stippling on the shaded sides"

What that produced:

- The bolt is drawn on the isometric grid: its face is the world YZ plane facing +X, its flats
  run along world +Y and its depth runs back along -X. That gives the shipped art's layout: flats
  rising to the right, the thickness on the left, the top opening up-left.
- The set's light makes the tops palest. The left thickness faces the light and is light gold.
  The face turns to the shade side and is deeper gold, with the kit's 2x stipple: 14.8 % cover in
  the face, against 17-18 % on the approved siblings' shadow faces.
- Rejected on the way: a mirrored copy (v2), a traced outline on a plane turned 15 degrees (v3-v7,
  "perspective broken"), and the unturned grid version (v10).
- One adversarial review ran, on v9: the grid (within 0.15 px of the ingots' axes), lighting, pose
  and ink passed. Its sliver fix was folded into the build.
