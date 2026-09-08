# Alumina, glass and windows — BUILT (2026-09-07). Record of work, not a plan.

Companion to `alumina-glass-windows-plan.md`. All three exist as builders and reproduce from
code. **Owner approved all three on 2026-09-07 and they are INSTALLED as alternates** (main
tiers keep priority); sidecars audited, runtime load verified — see
`artifacts/goods_icon_wga/verification.json`.

Source, renders and tooling: `price-of-everything-0.1/artifacts/goods_icon_wga/`
(its `README.md` has the exact commands and the accepted round per good).
Owner gate sheet: `artifacts/goods_icon_wga/progress_sheet.png`.

| Good | Builder | Accepted | Export | Rounds |
|---|---|---|---|---|
| Windows | `build_windows` | `final/windows_800.png` | `--contour 0.0065 --vib 1.15` | 7 — **approved** |
| Glass | `build_glass` | `final/glass_800.png` | `--contour 0.0065 --vib 1.15` | 9 — **owner approved** |
| Alumina | `build_alumina` | `final/alumina_800.png` | `--contour 0.004 --vib 1.15` | 14 — **approved** |

The owner reviewed the first gate and asked for six changes (longer bottle neck; a double
folded rim, a squarish base slightly wider than the top, near balls tucked behind the rim and
bigger type on the sack; both window handles on the same side). All are in; the table in the
artifacts' README maps each ask to what moved.

Two bakes are pixel-identical, colour and mask, individually and in one session (which also
proves alumina's per-icon `ink` override does not leak into the next builder).

## What the plan got right, and where it was wrong

Right: the symbol rankings, the owner rulings, the 2x3 glazing grid, the leaf at 0.44 D, the
`ring_loft` / `pellet_cluster` / `casement_leaf` helper list, and the warning that a flat pane
facing the camera cannot carry a gradient halftone.

Wrong or incomplete, each paid for with a render:

1. **"Windows first because it is 95% boxes" understated the hard part.** The hard part is not
   the boxes, it is that **true isometry shears a flat panel tall**: screen width is `0.707·W`,
   screen height `0.408·W + 0.816·H`, so a square panel lands at aspect 0.58 while these
   references sit near 0.85. The plan's right-hand hinge made it worse — a 90-degree leaf
   swings to −Y, which lands inside the frame's own screen column, so it stacked under the
   frame AND covered its own opening (0.55). Hinging on the **LEFT** jamb makes the identical
   90-degree swing widen the composition instead: **0.87**. Solve placement on the projection
   before modelling; `bb()`/`corners()` in the session log is six lines.
2. **The plan's frame member and depth ratios were taken from screen measurements of a
   reference that is not true-isometric.** Its vertical foreshortening is much shallower than
   ours, so its screen proportions do not convert. Take component RATIOS (pane grid, leaf
   width, member-to-depth) from the reference and take the overall aspect from the projection.
3. **All three goods mirror left-to-right, and that is forced.** Our −Y is the screen's lower
   LEFT and the sun is overhead-front, so depth returns the references draw on the left are
   +X faces here, and a bottle standing in front of a pane lands left. Tell every reviewer
   this or they will report it as a defect.
4. **The plan's glass bottle profile was a wine bottle.** Measured against the reference as
   fractions of the bottle's own screen height: body .544, shoulder .205, neck .029, collar
   .075, cork .146. And the reference's stopper is **olive glass** (120,132,108), not tan —
   sampling beats reading the picture.
5. **The plan said nothing about tone FLATNESS, which was the biggest defect in two of three.**
   The reference's bottle is 98.5% one green plus a narrow streak; the reference's pellets are
   98.5% one white. Toon steps that look reasonable on a box wrap a round body as a bright cap
   (the candidate's widest lit blob was 60% of the bottle's diameter against the reference's
   8%). For a round body, go near-flat and let the STREAK and the HALFTONE do the work.

## New kit pieces (in the artifacts' frozen `goods_icon_kit.py`)

`nomask_stipple` / `force_stipple` / `single_band_stipple` (pass_index 73 / 74 / 75),
`rect_ring`, `casement_leaf`, `swing_parts`, `lathe`, `band`, `surface_streak`,
`superellipse`, `dog_ear`, `ring_loft` (per-point z), `pellet_cluster`, `flat_text`.

## Traps this batch paid for

- **A flat plate on a tapered body dives into the skin.** The sack's label is placed by
  RAY-CASTING the evaluated sack over the plate's own footprint, sitting the front proud of the
  frontmost hit and the back behind the rearmost one, so the plate's thickness falls out of the
  measurement. Positioning it by hand from the ring radii bowed the skin up through the card
  and pushed the formula outside it. Same lesson as the pellets: measure the evaluated surface.
- **Lengthening a part re-creates coplanar rims (rule 26).** Running the bottle's neck out for
  the owner's "longer neck" put the collar's top rim exactly on the neck's cap; the two circles
  z-fought and Freestyle drew the collar as a dashed ellipse. Check every rim a change moves.
- **"Illogical" handles = handles on different FACES.** The final ruling on the window handles
  was about neither stile nor lever: the closed leaf's handle was on its front face and the
  open leaf's on its back face — one outside, one inside. Both now sit on the front face at
  the meeting stiles, a mirror pair. At 90° the open leaf's is therefore hidden except for the
  lever's tip past the free edge, and the owner chose that over a visible-but-wrong handle.
  Four rounds; the lesson is to reason about the CLOSED state first.
- **A label "moulded to the bag" is a conformed patch, not a plate.** Ray-cast a grid onto the
  evaluated skin, lift it 0.008, let Freestyle's border ink draw the edge; conform the glyphs
  the same way (subdivide first). A box, however well placed, reads as stapled on.
- **A handle's SIDE is judged by where its lever falls, not where its rose sits.** Three
  rounds went on the open leaf's handle. The rose was on the right stile all along; what the
  owner saw was the lever falling to the RIGHT of it (over the glass) because it protrudes +X,
  the screen's lower right, then hung straight down, while the closed leaf's fell left. The fix
  is a two-segment lever (`handle_hook`) that runs past the free edge and then hangs, so both
  levers fall the same way. Zoom on the handle BEFORE moving it: the first "move it to the
  other side" was answered by moving the rose, which was never the problem.
- **"Folded over" means one flap, not two folds.** A double fold with six creased loops was
  rejected as "too many lines to the rim"; the owner's folded-over top is ONE flat vertical flap
  with a sharp crest — three creased loops (flap bottom edge, crest, inner lip), which is also
  the reference's count. Count the lines in the reference before adding geometry.
- **Leaves sit IN from the frame, against a rebate ring.** Tucking a casement leaf under the
  frame's front face merges frame and stile into one cream mass. The reference reads frame →
  stippled reveal → wide stile → glass; that needs the leaf inside the opening with a gap, and a
  second, narrower ring BEHIND the front ring for it to close against (rule 33). Inset the
  rebate ring 0.010 outside and stop it short of the frame's back, or its faces are coplanar
  with the front ring's (rule 26).

- **`pass_index` is the per-object mask override.** 73 = never stipple, 74 = always,
  75 = floor the mask at 0.32. 75 exists because the exporter has three stipple bands and a
  **cylinder's far flank drops into the two deep ones**, giving ~66% coverage — a solid navy
  strip, not shading (the reference's bottle flank measures 20%). Flat faces never see this;
  round ones always do.
- **Measure clearance on the EVALUATED mesh.** Subsurf pulls the skin inside the control cage,
  so ring radii are optimistic. `pellet_clearance.py` BVH-tests every ball against the
  modified sack. The cage said +0.09 clear while the render showed a ball pressing through.
- **A near-150-degree corner makes Freestyle DASH.** The sack's flat interior floor met its
  wall at about the crease angle, so the crease test flipped face by face and inked the join
  as a broken arc inside the mouth. Diagnose by deleting everything else and re-rendering —
  the dashes survived with all the pellets gone, which ruled out the poke-through theory in
  one render. Fixed by removing the ambiguous corner (a funnel interior), not by tuning ink.
- **Freestyle thickness is per LINESET, so a bolder interior line is a per-icon override.**
  Alumina sets `ink` to 11.3 inside its builder (the ore builders' `_ore_linestyle` set the
  precedent) to bring the ball outlines to the reference's weight; `setup_icon_rig` resets it,
  which the one-session render proves.
- **A label is a card, not a slab.** Built as a box, its lit +X and −Z side faces render as an
  uninked white edge and only ~45% of its perimeter carries ink. Give every face but the front
  the navy material.
- **A sack's mouth is not level.** `dog_ear` lifts the ring at its corners; without it the cuff
  reads as a moulded tub rim. And the reference's body is WIDER than its cuff (1.034) — a
  filled sack bulges and its mouth gathers in.
- **`--script` GDScript: `var x := a[1] == b` fails to parse** ("cannot infer the type") because
  an untyped Array element gives the comparison no static type. Annotate: `var x: bool = ...`.
  Cost one blank-output round in the runtime texture check.
- **Kit branches have forked.** `tools/goods_icons/` carries the approved diesel/jerrycan;
  `artifacts/goods_icon_ammonia/source/` carries the ore builders plus the ammonia text
  precedent; `material_studies/` carries `lathe_cage`/`label`/`glass_window_nodes`. Neither of
  the first two is a superset. There is also a copy at the REPO root, `blender-assets/`.

## Open question for the owner

**Our halftone screen is about 2.7x coarser than these three references'** — exporter pitch
1.5% of the long side (rule 39), shared by every installed icon; the references measure ~0.57%.
This is why a fully stippled face reads here as a dirty screen door and there as shading. It
decided the windows' open leaf: tone separation beat halftone in a side-by-side render
(`artifacts/goods_icon_wga/ab/win_AB.png`), against the reviewer's recommendation. A finer
screen would be a **set-wide** change and is not one to settle inside a single icon.
