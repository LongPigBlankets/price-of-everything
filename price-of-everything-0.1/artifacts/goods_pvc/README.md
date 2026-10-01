# PVC (g_033) Blender icon

**Approved 2026-09-29** (owner: "approved", on v14). v15 is v14 with the two drawing defects found
by the independent review fixed; the design is unchanged (see Checks). v15 is installed as the
approved alternate, `assets/icons/goods/alternate_icons/{medium,small,very_small}/g_033_pvc.png`
(800, 450 and 256 px), and listed in `approved_manifest.json` with source `goods_pvc/v15`. The
shipped main art (`assets/icons/goods/{medium,small,very_small}/g_033_pvc.png`) is unchanged; the
alternate takes priority at runtime.

## v15 (installed)

- `pvc_800.png` is the transparent master. `pvc_450.png`, `pvc_256.png` and `pvc_60.png` are
  LANCZOS downsizes of it. The 800, 450 and 256 px files are the installed tiers.
- `pvc.blend` is the editable saved scene. `pvc_kit_v15.py` is the builder as installed (the same
  file as `tools/goods_icons/pvc/pvc_kit.py`).
- `v14_owner_sheet.png` and `v14_section_compare.png` are the sheets the owner approved. The owner
  sheet sets the shipped art beside v12 (the step out) and v14 (the rib out and back in), the
  shipped front section beside v14's, and the DS2 well. The section sheet is that front-section
  comparison on its own.
- `review_v14_artefacts.png` is the review's evidence for its two defects: pane 0's edge merging
  with the lip's section line (front and top sections), and a 1 px seam inside the outer contour
  along the strip under the rib (up the upright and along the bottom member).
- `fixes_v14_v15.png` shows both fixes, v14 beside v15: the glass edge by the lip (4x), the strip
  under the rib (2x) and the whole corner.
- `comparison.png` sets the shipped art beside v14 and v15. `regions_3x.png` is the 800 px
  master's four quadrants at 3x. `ds2_well.png` shows it at game size (72 and 144 px wells) beside
  the old PVC art and the approved copper pipe, windows, ethylene, glass and sodium-ion
  alternates.
- `pvc_metrics.json` is the build record (dimensions, profile, chambers, panes, outline and
  stipple settings, camera, mesh checks). `saved_scene_verification.json` checks the camera,
  closed hosts, contacts and clearances (no failures). `pvc_800_line_weights.json` records the
  12 px outer and 6 px inner lines. `pixel_metrics.json` holds the bounding box, ink colour and
  grey-step measurements (its green and cream shares come from the battery proof sheets and are 0
  here).

The builder and re-render commands are in `tools/goods_icons/pvc/`. Re-rendered from that copy at
install, the 800 px master came out byte-identical to the one here.

## Record

Owner direction: "ok next go for pvc and nitrogen".

Owner rulings on the way, in order:

1. On v4: "that PVC isnt right, try using 3 point line for the linework on the crosssection of
   the PVC and also check the glass. it looks nothing like the old version"
2. On v9: "pretty good. check that the PVC tubes and the slice of windo have the same colour"
3. On v10: "good but the shape is a bit simplistic for the window crossection. can you add an
   outer ridge like the old version used"
4. On v12: "the outer ridge needs to then go back in - look at the cross section and try to map
   that outer ridge's shape"
5. On v14: "approved"

Rulings carried over from the earlier goods: keep the shipped art's layout (it is already lit
like the set, so it is kept as drawn), draw on the isometric grid, light with the set's light,
stipple the shaded sides, and ink every junction between parts.

What it is:

- The shipped layout on the grid, lit like the set. Seven hollow PVC pipes (outer diameter 1.0,
  bore 0.8, 3.4 long) lie in a strapped hexagonal bundle, their ends facing -Y, tied with two
  khaki straps with drawn rims. Beside them a PVC window-frame corner, two members of one stepped
  profile meeting on a drawn 45 degree mitre, stands in the YZ plane facing +X.
- Pipes and frame share one PVC material, so their tones are identical.
- The profile: a main chambered body, a raised lip on the room side, a glazing seat, and on the
  outer face a rib that stands out 0.20 and then returns 0.08 further in than the face above it,
  mapped off the shipped cross-section. The chambers are real tunnels, open at both cut ends.
- The double glazing is cut flush with the frame, so it shows only as its two panes' cut edges:
  light strips rising out of the front section, slanting up and running flat into the top
  section.
- The cross-sections (at both cut ends: the profile outline, the chamber rims and the glass cut
  edges) are inked at 3 px, an owner-approved third weight; the long edges keep the set's 6 px.
- The frame, glass and straps share the right-hand pipe's part label on purpose, so the thin
  glass edges get no 6 px component boundaries where they cross that pipe and strap; the straps
  carry explicit rim paths so they keep their outline.

Revisions:

1. v1-v4: first builds (the frame too thin, the glass drawn as a filled triangle).
2. v5-v8: 3 px sections, flush-cut glass edges, chambers as tunnels, strap rims (owner ruling 1:
   3 px lines and the glass).
3. v9: a paler frame.
4. v10: one PVC material (owner ruling 2: the same colour).
5. v11-v12: an outer step and rebalanced chambers (owner ruling 3: the ridge).
6. v13-v14: the rib that goes back in (owner ruling 4: map the ridge). Approved.
7. v15: the review's two fixes.

Checks:

- `pvc_verify.py` on v15: no collisions between the frame, the glass, the pipes and the straps;
  closed hosts; nothing below ground.
- A repeat render of v15 was pixel-identical.
- One independent defect review ran, on v14. It passed stepped tones, shared PVC tones (identical
  modes), dots only on the shade faces (none on the glass, sections or tops), 97.3 % of ink within
  30 of navy and no pure black, line weights of 12/6.26/3.27 px with 3 px only on the sections
  and glass edges, the grid within 0.1 degrees, every junction inked, a clear read at 58-64 px,
  and all five owner rulings met.
- It found two artefacts, both fixed in v15:
  - Pane 0's edge sat 0.05 from the lip's section line, so their two 3 px lines merged. `PANES`
    moved from ((2.02, 2.14), (2.27, 2.39)) to ((2.06, 2.18), (2.31, 2.43)), which centres the
    glazing in the 1.97-2.52 seat.
  - The 0.12 strip under the rib left a 1 px seam inside the outer contour. `RIB_H` went from
    (0.40, 0.75) to (0.37, 0.75).
- Minor findings, not changed: strap_0's back rim runs along pane 0's edge for about 20 px (it
  reads as one 6.5 px line), and a 3.5 x 15 px olive wedge shows where strap_0 turns (true
  geometry).
