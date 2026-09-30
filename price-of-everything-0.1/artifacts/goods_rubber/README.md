# Rubber (g_028) Blender icon

**Approved 2026-09-30** (owner: "rubber is approved", on v14). The good's internal name is `rubber`.
v15 is installed as the approved alternate,
`assets/icons/goods/alternate_icons/{medium,small,very_small}/g_028_rubber.png` (800, 450 and
256 px), and listed in `approved_manifest.json` with source `goods_rubber/v15`. The shipped main art
(`assets/icons/goods/{medium,small,very_small}/g_028_rubber.png`) is unchanged; the alternate takes
priority at runtime.

v15 is the approved v14 with three physical fixes the saved-scene check found, none of them visible:
the duck's head, pinned to the shipped head's circle, sat 0.10 above its body in depth (the body's far
side showed through the gap, so it read as joined), and now has a neck peg laid along the camera's line
of sight behind the head; the duck's hidden rear, which passed 0.03 into the stack's bottom fold, rests
against it; and the near boot's midsole bulges less on its hidden inner side, so the two midsoles no
longer meet. The 800 px render differs from v14 in 485 pixels, 124 of them by more than a trace, all
1-2 px line shifts where the duck's tail meets the stack and between the boots (`diff_v14_v15.png`).

## v15 (installed)

- `rubber_800.png` is the transparent master; `rubber_450.png`, `rubber_256.png` and `rubber_60.png`
  are LANCZOS downsizes of it. The 800, 450 and 256 px files are the installed tiers.
- `rubber.blend` is the editable saved scene. `rubber_kit_v15.py`, `boot_geom_v15.py` and
  `duck_geom_v15.py` are the builder as installed (the same files as `tools/goods_icons/rubber/`).
- `owner_sheet.png` is the sheet the owner approved (the shipped art beside v7, the first full build,
  and v14), with `owner_ds2_well.png`, its game-size strip. `comparison.png`, `ds2_well.png` and
  `regions_3x.png` are the same for v15 (the shipped art beside v7 and v15; the 72 and 144 px wells
  beside neighbouring goods; the master's quadrants at 3x).
- `rubber_metrics.json` is the build record: the stack's layers, the boots' fitted geometry
  (`BOOT_GEOM`, `BOOTS`), the duck's (`DUCK_GEOM`), the tread, the stitch dash, the outline and stipple
  settings, camera and mesh checks (all 26 hosts closed). `saved_scene_verification.json` checks the
  camera, closed hosts, nothing below ground, the intended contacts (each boot's upper with its rim
  and midsole, midsole with outsole; the duck's neck peg with its head and body, the bill with the
  head, the lower mandible with the bill) and that the duck, the two boots and the stack clear each
  other: no failures. `rubber_800_line_weights.json` records the set's 12 px outer and 6 px inner
  lines. `pixel_metrics.json` holds the bounding box, ink colour, grey steps and yellow share.

The builder and re-render commands are in `tools/goods_icons/rubber/`. Re-rendered from that copy at
install, the 800 px master came out byte-identical to the one here, and its saved-scene check matched.

## How it was built

Each object was mapped to the shipped art rather than drawn freehand (owner: "try to map the topology
of each object, one by one"), then reviewed by an adversarial reviewer until it passed ("keep looping
with the reviewer until its done"):

- **Stack.** Its size and the camera were fitted to the shipped stack's inked silhouette (IoU 0.98);
  the sequence and thickness of its thirteen sheets and folds were measured on the shipped stack's
  front face. The stitching was placed by back-projecting the shipped art's 119 dashes through the
  camera onto the layers: the top sheet's row rounds the front corner and runs nearly to the far end;
  the fold under it carries a row that wraps round its rounded end; the big middle fold a hairpin
  along its end with U-loops on its face; the bottom fold a row and a short-dash arc at each end.
- **Boots.** Each boot's opening, rim ring, cuff band, shaft, foot panel, midsole and outsole were
  read off the shipped ink as separate regions and a parametric boot (`boot_geom.py`) was fitted to
  all fourteen at once (mean IoU 0.785). The ankle seam's height round each boot was back-projected
  from the shipped ink: level over the instep, a rounded shoulder, a near-vertical drop, level along
  the side. The pair turns 9 degrees off the grid, as the shipped openings and soles do (round goods,
  not a flat face). The midsole bulges and the lugged outsole tucks in, so the toes curve as shipped.
- **Duck.** A parametric duck (`duck_geom.py`) was fitted to the shipped duck's inked silhouette, its
  bill's region and its neck line, with the head pinned to a circle fitted to the shipped head: it
  faces +X, 45 degrees off the viewer, so both of the shipped eyes show. Its back was refitted to the
  shipped top edge on the true silhouette (one smooth crest falling level to the neck). The eyes, neck
  line, mouth line, wing and feathers are the shipped strokes, traced and carried onto the surfaces
  through the camera; the wing is closed into the shipped teardrop.

## Record

Owner direction, verbatim, in order:

1. "approved. Please move onto plastics, iterate on that with the topology of the chair and the plastic
   bottle. The bag might be difficult but try to get close. Then rubber. Both are difficult icons but
   keep looping with the reviewer until its done"
2. "try to map the topology of each object, one by one. Do the plastic chair first"
3. On v14: "rubber is approved"

Reviews: v10 (first full rebuild of the boots and duck: not ready: the stack's right-face stitching,
the duck's back, wing, eyes and bill, the seams' corners), v11 (not ready: a notch at the tail, hidden
return rows, the far eye against the bill, the bill's shape), v12 (not ready: the tail notch hidden
by the fit's ink model, a dent in the duck's shading, a hidden stitch row, the far toe), v13 (ready
for the owner; v14 added two of its polish notes: a stitch row moved onto its own sheet band and the
bottom fold's end arc). Left as polish: a ~3 px shelf at the tail's rear corner, and the shipped art's
nested fold lines at the stack's right end are not drawn.
