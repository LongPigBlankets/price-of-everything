# Fertilisers (g_064) Blender icon

**Approved 2026-09-29** (owner: "approved", on v9). The good's internal name is `fertilisers`. v9 is
installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_064_fertilisers.png` (800, 450 and
256 px), and listed in `approved_manifest.json` with source `goods_fertilisers/v9`. The shipped main
art (`assets/icons/goods/{medium,small}/g_064_fertilisers.png`; it has no very_small tier) is
unchanged; the alternate takes priority at runtime.

## v9 (installed)

- `fertilisers_800.png` is the transparent master. `fertilisers_450.png`, `fertilisers_256.png` and
  `fertilisers_60.png` are LANCZOS downsizes of it. The 800, 450 and 256 px files are the installed
  tiers.
- `fertilisers.blend` is the editable saved scene. `fertiliser_kit_v9.py` is the builder as
  installed (the same file as `tools/goods_icons/fertilisers/fertiliser_kit.py`), and
  `standard_lines_v9.py` the exporter's line module as installed (the same file as
  `tools/goods_icons/fertilisers/standard_lines.py`, which adds optional per-part line weights to
  the frozen kit's copy).
- `owner_sheet.png` is the sheet the owner approved: the shipped art beside v5 and v9, close-ups of
  the bag (shipped and v9) and the leaves (v5 and v9, 6 px outside and 3 px inside), and the DS2
  well. `v5_owner_sheet.png` is the first sheet the owner reviewed: the shipped art beside v5, with
  the well.
- `comparison.png` sets the shipped art beside v5 and v9. `bag_compare.png` sets the shipped bag
  beside v9's, larger. `regions_3x.png` is the 800 px master's four quadrants at 3x. `ds2_well.png`
  shows it at game size (72 and 144 px wells) beside the old fertilisers art and the approved
  ammonia, sand, chem salts, industrial acids and PVC alternates.
- The shipped art (`assets/icons/goods/medium/g_064_fertilisers.png`, not copied here) has a
  baked-in blue background: its transparent pixels carry a blue (about RGB 44, 92, 148) under zero
  alpha, and a few enclosed gaps between the leaves are opaque blue. It shows in the comparison
  (behind the upper tomatoes) and wherever alpha is dropped, as in the close-ups of the shipped bag.
- `fertilisers_metrics.json` is the build record (the bed, soil, plant, tomato and leaf dimensions,
  the bag's parameters, the outline weights including the per-part ones, the stipple settings,
  camera, mesh checks). `saved_scene_verification.json` checks the camera, closed hosts, contacts
  and clearances (no failures). `fertilisers_800_line_weights.json` records the set's 12 px outer
  and 6 px inner lines; the leaves' and stems' own weights are in the metrics' `outline`.
  `pixel_metrics.json` holds the bounding box, ink colour, grey-step measurements and the green
  share (leaves, stems and bag: 0.305); its cream share is 0.
- `bag_fit/` is the bag's fit to the shipped sack. `bag_fit.py` picks the shipped sack out of the
  shipped art by its green (`ref_bag_mask.png`, 2048 px), projects the lofted bag model through the
  fixed camera, and fits its shape by IoU after normalising area and centroid (a seeded random
  search, then Nelder-Mead). `bag_fit.json` holds the fit (IoU 0.961, against v7's 0.928) and its
  parameters. `bag_fit_compare.png` sets v7's overlay beside the fitted one (green: shipped only;
  red: model only; dark: both). The script reads the shipped art as
  `reference/g_064_fertilisers.png` under its working directory and writes its outputs there; the
  two overlays it writes are kept only as `bag_fit_compare.png`.

The builder and re-render commands are in `tools/goods_icons/fertilisers/`. Re-rendered from that
copy at install, the 800 px master came out byte-identical to the one here.

## Record

Owner direction: "Next go for fertilisers. Quite a complex shape".

Owner notes on the way, verbatim, in order:

1. On v5: "its an ok first attempt but the bag needs to look plump. Map its topology and try to do
   the same. The tomatores are fine, but could use thinner linework on the leaves esp. the outside"
2. On v9: "approved"

Rulings carried over from the earlier goods: keep the shipped art's layout (it is already lit like
the set, so it is kept as drawn), draw on the isometric grid, light with the set's light, stipple
the shaded sides, ink every junction between parts, one colour per material, and use 3 px lines for
small detail.

What it is:

- The shipped layout on the grid, lit like the set. A wooden raised bed (1.0 x 1.25 x 0.35, two
  boards a side, with its rim and the seam between the boards drawn) is heaped with dark soil (a
  mound at the plant, crumb marks in 3 px).
- A tomato plant rises from it off-centre toward the front: a stem, nine compound leaves of three
  serrated leaflets with 3 px midribs, and seven tomatoes with calyx stars and glints (a truss of
  three to the left, three to the right and a big one in front).
- A plump green gusseted fertiliser bag leans against the bed's front-left side. Its shape was
  fitted to the shipped sack: the sack's silhouette was extracted from the shipped art, and a lofted
  model (rounded-rectangle sections, thickness sin(pi t^sag)^belly, a belly wider than the seams)
  projected through the fixed camera was fitted by IoU after normalising area and centroid (v7 0.928
  -> fit 0.961; parameters in `bag_fit/bag_fit.json`: lean 12.5, yaw 3, T/W 0.708, H/W 1.494, pinch
  -0.134, sag 0.722, belly 0.619, p 1.95). It is sized to the shipped bag-to-bed ratio, with flat
  crimped seam bands, pointed ears flaring to the ends, a softer lit step, one crease pulled from
  the top-right ear and one long crease on the lower right (3 px), and gloss streaks.
- Leaves and stems take a 6 px outer contour and the leaves 3 px boundaries (owner note 1: thinner
  leaf linework), through the new optional per-part weights in `standard_lines.py`; everything else
  keeps the set's 12/6 px.

Revisions:

1. v1-v5: first builds (the sand icon's pillow sack stood up, which read flat; the leaves and the
   plant's scale).
2. v6: thinner leaf lines (owner note 1), a first lofted bag.
3. v7: a belly, seam bands, ears.
4. v8: the bag fitted to the shipped silhouette.
5. v9: pointed ears, one crease, a softer lit step. Approved.

Checks:

- `fz_verify.py` on v9: no collisions (the bag clears the bed, the soil, the tomatoes and the
  leaves; the tomatoes clear the bed and the soil; some tomatoes in a truss touch each other, as
  allowed); the stem stands in the soil; closed hosts; nothing below ground.
- A repeat render of v9 was pixel-identical.
- No independent review ran this round; the iterations were owner-directed.
