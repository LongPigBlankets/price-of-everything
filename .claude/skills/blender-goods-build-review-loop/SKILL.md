---
name: blender-goods-build-review-loop
description: Load this to take over or continue a GOODS ICON or any complex 3D structure for Carbon and Capital in Blender — the method, not the style rules. Covers how to study the reference, rank the symbol, plan proportions, build with the kit, render headless, run the adversarial reviewer against a fixed criteria sheet, fold one consolidated fix per round, and gate on the owner. Includes four worked cases at different difficulty (aluminium = simple stack, motor = engineered assembly, iron ore = organic lumps, unfinished; diesel car = lofted body, hardest, unstarted) with what was tried, what failed and why. Style numbers live in the blender-goods-icons skill; this skill is the loop and the reviewer's contract.
---

# Goods icons and complex structures in Blender — the build-review-iterate method

This is the process document. The style contract (tones, ink weights, rig traps, geometry
rules 1–53) is the sibling skill `blender-goods-icons`; read that first, then this. The
building-sprite skill is a third sibling and shares the kit.

Everything below was learned on 2026-09-03/04 over ~25 render rounds across four goods. The
scratchpad renders from that session are gone; **the kit reproduces every version from code**
(`blender-assets/goods_icon_kit.py`, copies beside the sibling skill), so re-render rather
than look for PNGs.

## 0. State at handoff

| Good | Builder | Status | Owner's last word |
|---|---|---|---|
| Aluminium | `build_aluminium` | approved in spirit, 4-5-4 hex, tensioned straps | "looks good now" |
| Motor | `build_motor` (v8) | approved | "motor is there" |
| Iron ore | `build_iron_ore` (v13) | **open** | hero must be as wide as tall (done); "silver facets look less nice than the original — lighting missing; thin linework bounding the silvery side" (attempted, not yet accepted) |
| Diesel car | `build_diesel_car` | **failed first pass, unstarted since** | never reviewed by owner; box-built sedan reads as a boxy limo |
| Cage loft | `cage_loft`, `build_cage_test` | tool proven on a smoke test | not yet used on a real good |

Nothing is installed in `assets/icons/goods/`. Installing needs the owner's eye on the 800² file.

## 1. The loop

One round = one consolidated change set, one render, one export, one review. Budget three to
four rounds per good before showing the owner unless the owner is directing live.

1. **Brief.** Write the good's name, its reference file, the owner's rulings that apply, and
   the ONE thing this round must change. A round with five goals produces a render nobody can
   judge.
2. **Study the reference — with numbers, not adjectives.** Measure before modelling:
   bbox aspect; body length / diameter (D); the diameters of every stepped part in D; the
   accent's share of bbox width; outer contour and interior line widths (erosion-band method,
   §5); the tone steps (luma histogram peaks on the body colour); which faces carry halftone;
   the palette's top eight colours. Ten minutes of PIL saves two rounds.
3. **Rank the symbol** (only when the reference could be replaced). List the plausible
   depictions of the good, rank each for recognisability against the confidence the shipped
   icon already has, and pick. Write the ranking down; the owner asked for it explicitly on
   iron ore and will again. Prefer the shipped language unless it is wrong about the good.
4. **Proportion sheet in D.** Every dimension as a ratio of the main body's diameter, in the
   builder's docstring, before geometry. The motor's whole anatomy fits in six lines this way.
5. **Build** as a `build_<good>()` over `sprite_kit.Kit` + the goods-icon helpers. Materials
   are toon materials. Run `K.validate()`.
6. **Render headless** (`render_icons_headless.py`), ~10 s per icon; never wait on the MCP.
7. **Export** with the icon's own contour weight (`icon_export.py --contour`).
8. **Self-check before review:** zoom four regions at 3× NEAREST; measure ink colour, line
   widths and tone peaks; check the mask pass rendered (a mask that is uniformly white means
   the override was None — the silent failure).
9. **Adversarial review** (§2) with the reference, the candidate, the previous candidate, and
   the owner's asks for this round.
10. **Fold** the review into ONE consolidated change set, dropping anything on the overrule
    list (§3). Do not fix things one at a time across renders.
11. **Owner gate.** Show a progress sheet (shipped / previous / current) and the 800² file.
    The owner's sentence becomes the next round's brief, verbatim, in the docstring.

Stop conditions: the owner says "there"; or three rounds moved no measurable metric.

## 2. The adversarial reviewer's contract

Spawn a general-purpose subagent. Give it, in this order: the style summary (one paragraph),
the reference path, the candidate path, the previous candidate path, the owner's asks for the
round, and the criteria sheet below. Require the method and the output format. Run it in the
background while you prepare the next change set, never blocking on it.

**Method the reviewer must follow** (each step produced a finding a human missed):
- Read all images. Build a same-region side-by-side sheet, reference left / candidate right,
  five anatomical regions, 3× NEAREST, and Read it. Save the sheet to the scratchpad and
  report the path.
- Diff against the previous candidate first and state what actually changed. (A v5 review
  found the change set was two of six asks; the sheet made it undeniable.)
- Measure with PIL, do not eyeball: line widths (p50/p90) by ridge-run length, outer contour
  by erosion bands, tone peaks by histogram on the body hue, halftone density per face
  region, the accent's share of bbox width, the ratios in D.
- Rank by structure, not by size of defect.

**Criteria sheet** — every item gets PASS / FAIL with the number that decided it:

| # | Criterion | Pass condition |
|---|---|---|
| C1 | Form is stepped, not graded | body-colour luma histogram shows 2–3 peaks ≥ 25 apart; no continuous ramp wider than 30 luma |
| C2 | Tone range matches reference | lit step within 15 luma of the reference's lit step; shadow within 15 of its shadow |
| C3 | Halftone on the shadow step only | dots/kpx on lit and mid regions < 0.3× the reference's; shadow region ≥ 0.6× |
| C4 | Ink is one navy | > 95% of ink pixels within colour distance 30 of sRGB (20, 28, 60); zero pure black |
| C5 | Line hierarchy | outer contour 1.1–1.8% of the long side; interior 0.4–1.5%; outer/interior ratio 1.4–2.0; a thin class present on fine detail |
| C6 | Proportions in D | each stepped part within ±10% of the reference's ratio, or of the owner's ruling where one exists |
| C7 | Accent size | accent bbox share within ±5 points of the reference's (motor box: 38% of width) |
| C8 | Joins are closed | no line ends mid-face; no part shows daylight where it meets another; no dashed circles |
| C9 | No artefacts | no doubled lines, slivers, zipper edges, starbursts, moiré, stray planes, floating parts |
| C10 | Silhouette reads at 64 px | downscale to 64 px: the good is still identifiable; adjacent drums differ in diameter |
| C11 | Owner asks | each ask MET / PARTLY / NOT with evidence |
| C12 | Recognisability | the candidate is the same good as the reference to a stranger; note any drift (e.g. "reads as a gearbox") |

**Output format** (max ~600 words): (1) delta from previous candidate; (2) criteria table;
(3) ranked STRUCTURAL gaps, each with region, evidence, severity and a builder instruction in
D; (4) artefacts; (5) what the candidate does better; (6) the single biggest payoff.

**The reviewer must not:** report nits under 2 px; propose realism the reference does not
draw (a domed motor face, six flange bolts, vent slits); suggest a change on the overrule
list; praise-pad; or soften. Its first-round prompt that worked verbatim: *"why does the
reference read as a confident inked poster and the candidate as a 3D render with lines on
it — the five or six STRUCTURAL causes."* Nit-hunting prompts ("list every defect") wasted a
round on the motor.

## 3. Owner rulings — the overrule list

The reviewer and the builder both yield to these. Add to the list as rulings arrive; quote
them verbatim.

- Goods shading is gentler than building shading.
- No all-over halftone; stipple is shading on the shadow step only.
- Polygon budget is not the constraint; accept the render cost.
- Motor: face FLAT with a bold cover over the shaft base; thick long plates left and right;
  the yellow box much bigger (then: right width, too tall → 0.32 D); glands yellow with a
  clear seam; the pad under the box runs to the rear circular face; no navy notch on the
  shaft; legs raised, angled (splayed) with a skirt between; interior ink thinner still.
- Aluminium: 4-5-4 rod layout; straps curve around the rods; less aggressive shading.
- Iron ore: fewer, larger nuggets; they stand tall; the hero about as wide as tall (not tall
  and skinny); silver facets need the reference's light; thin linework on every facet to
  bound the silvery side; rank alternatives against the shipped icon's confidence first.
- Process: adversarial review is wanted; the owner overrules the reviewer.

## 4. Four cases, by difficulty

### Aluminium — a stacked good (simple). Two rounds.
Anatomy: rods in a hex pack on a pallet, two straps, one accent (wood).
- Worked immediately: 48-segment rods, flat EMISSIVE white (no gradient), pallet from boxes.
- Cost a round each: straps. A thick ribbon mesh zipper-inked at every segment; an open strip
  vanished into grey slivers between rods; the union-outline path dipped into valleys and hid
  behind rods as dashes. Final: convex-hull path, real thickness, face-marked out of
  Freestyle, outlined in 2D by the export.
- Review criteria that mattered: C3 (white rods took no dots on top), C9 (slivers), C5.
- Lesson: simple goods fail on one component. Find it in round one and spend the rounds there.

### Motor — an engineered assembly (complex). Eight versions.
Anatomy in D: barrel 10-facet prism 1.15 D long with three side plates per flank; flange
1.15 D proud; flat face with six bolt dots; cover rim 0.55 D + drum 0.46 D; shaft 0.2 D ×
0.5 D; cowl 1.15 D; box 0.57 × 0.60 × 0.32 D front-mounted on a full-length pad; two splayed
wedge feet + skirt; thin base plate ending at the flange plane.
- Arc: v1 smooth cylinder with rails ("loose slats on a can") → v2–3 detail without
  structure → v4 the turning point: toon shader (three flat steps), faceted barrel, flat
  face, big box, cowl step, skirt → v5–7 the owner's anatomy list → v8 review fixes (pad
  through the cowl rim, keyway sliver, light overhead-front so the flank gets a mid band).
- What moved the needle, in order: (1) three-step toon tones on every material, (2) the
  owner's anatomy list, (3) measuring ink (the "black" lines were a factory LineSet), (4)
  proportions in D, (5) bolt dots instead of inked cylinders.
- What wasted rounds: the reviewer's first nit list; a conical bell; a leaning-plate skirt
  that read as an X; an inked key slot; the cowl at 1.3 D.
- Review criteria that mattered: C1, C2, C6, C7, C8, C11.
- Lesson: an assembly is won on tone structure and proportion, then anatomy. Detail last.

### Iron ore — organic lumps (hard, UNFINISHED). Thirteen versions.
Target: the shipped icon's rust chunks with grey cleavage faces, ranked the most
recognisable iron symbol (pellets read as berries, magnetite as coal, a cart as mining).
- Tried and rejected: convex hulls of random points (dice); level-3 icosphere with strong
  noise (mush, no inked facets); six-lump heap (owner: fewer, larger); tall-skinny hero
  (unbalanced); grey cuts aimed at the camera (hero went grey); poke-fanned grey planes
  (spider web); deep chamfer cuts (grey again); marking every micro-facet with thin ink
  (wire mesh).
- Current v13: three lumps; hero r 1.02, squash (1.0, 0.9, 1.06), ten planar cuts of which
  two shallow grey caps (up-front and front-left), cut depths relative to the actual extent
  along the cut normal, rust cuts 0.74–0.86; two flank lumps r ≈ 0.6 with seven cuts and one
  grey cap; grey planes chamfered by one or two narrow steep cuts into bevel bands; thin ink
  (`ink_edge` lineset, 2.8 px) on edges with dihedral > 9°; halftone protect by ink distance
  so dark rust shadow still takes dots.
- Still open, in the owner's words: the silver facets look less nice than the original,
  which they attribute to missing light. Candidate causes for the next agent to test, one
  per round: (a) the reference's grey carries three tones on ONE plane (a soft highlight
  band) — try a per-face two-tone split by a fake light gradient, or a second lighter grey
  material on the bevel bands; (b) the reference draws short highlight strokes and a few
  stray dots on the grey — an export-pass mark, not geometry; (c) the reference's ink on
  grey planes is slightly heavier than on rust; (d) grey planes in the reference are
  bounded on ALL sides by ink, ours sometimes share an edge with a same-tone rust facet.
- Review criteria that mattered: C1 on the grey (single flat tone was the complaint), C9
  (starburst, wire mesh), C10, C12.
- Lesson: organic goods need the cut/tag/edge machinery to be right before taste enters;
  every ruling here was about silhouette balance and the grey planes' light, never about
  facet count.

### Diesel car — a lofted body (hardest, UNSTARTED). One failed pass.
- What exists: `build_diesel_car`, a box-built sedan lifted from the loading-film vehicle
  kit (authored for 20 px street scale) plus a jerrycan. At 800 px it reads as a boxy
  limousine with slab flanks; wheels tucked inside the body vanished; the jerrycan was first
  too big, then too small and too far.
- Why boxes cannot get there: the reference has rounded fenders, a raked glasshouse, a
  nose that falls away, open wheel arches, and glass-to-body about 40/60. Boxes give
  corners where the reference has curvature, and every chamfer is another coplanar seam.
- The approach for the next agent: (1) body shell with `cage_loft` — six to eight half
  profiles along the length (nose, bonnet, screen base, roof, rear screen base, boot, tail),
  crease rings at the screen bases and the sills; subdivision level 2; (2) wheel arches as
  real openings (bisect the shell with a cylinder-approximating set of planes, or model the
  arch as part of the profile); wheels proud of the flanks by 0.05 D with silver rims;
  (3) glasshouse as a second loft in the glass material, sunk 0.03 into the shell; (4) lamps,
  grille and mirrors as small boxes seamed with navy; (5) jerrycan at about 0.55 of the roof
  height, overlapping the front-right corner; (6) tones: the toon shader will band the loft
  automatically; check C1 on the bonnet. Expect four rounds; the first review should be the
  structural question, not a nit list.
- Review criteria that will matter: C1 (the loft must band, not blend), C6 (glass/body
  ratio, wheel diameter ≈ 0.28 of body length), C10, C12 ("is it a car or a van").

## 5. Measurement toolkit (describe, then reuse)

All in Python/PIL/numpy on the exported 800² PNG unless noted.
- **Outer contour width:** erode the alpha mask one pixel at a time; the outline thickness
  is the first band whose ink fraction (luma < 75) drops below 0.6.
- **Interior line width:** horizontal runs of ink pixels strictly inside the outline
  (beyond outline + 4 px); report the median and p90 of run lengths between 1 and 2× the
  outline.
- **Ink colour:** histogram of pixels with luma < 50, quantised to 4; the mode must be the
  navy. Pure black means the factory LineSet.
- **Tone steps:** select the body hue (e.g. g > r + 8 and |g − b| < 12 for teal), histogram
  luma, report peaks above 400 px. Compare peak positions to the reference's.
- **Halftone by face:** count dot-like blobs per 1,000 px inside hand-picked face regions
  on both images.
- **Mask sanity:** sample the `_mask.png` on a known top face (expect ≈ 0.86 after
  linearising), a front face (≈ 0.80) and a right face (≈ 0.36–0.42).
- **Proportions:** bbox of the accent colour vs full bbox width; ellipse major axes of the
  front face and the cowl for D ratios.
- **Reproducibility:** bake twice, require identical pixels (no `hash()`, seeded `random`).

## 6. Anti-patterns that cost rounds

- Fixing one thing per render. Fold the review into one change set.
- Trusting a thumbnail. Every "black ink", "dots on lit faces", "pad through the rim" was
  invisible at 800 px and obvious at 3×.
- Letting the reviewer set anatomy the owner has ruled on.
- Rendering through the MCP session. It disconnected mid-session; headless never did.
- Keeping BMesh element references across a bisect; positioning by `ob.location` before
  the depsgraph runs; face marks named `select_face_marks` (it is `select_by_face_marks`).
- Reaching for realism the reference does not draw. The reference is the spec; reality is a
  tiebreaker only when the reference is silent.
