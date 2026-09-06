---
name: blender-goods-build-review-loop
description: Build and refine Blender goods icons for Carbon and Capital using the original goods art and real-world geometry references. Covers structural diagnosis, measured comparisons, independent review, reproducible revisions and installation. Includes an approved sedan/jerrycan case and an executable pipeline for complex vehicles, equipment and engines.
---

# Goods icons and complex structures in Blender — the build-review-iterate method

## Complex goods: current workflow (September 2026)

For vehicles, equipment, engines or difficult accessories, read the
[car and jerrycan lessons](references/car-and-jerrycan.md). Use the executable
[complex-goods pipeline](../../../price-of-everything-0.1/tools/goods_icons/complex_goods/README.md)
to freeze revisions, render from their exact source, compare reference/previous/current,
and verify the selected output. The approved diesel seed includes durable real-world
references and the final reusable can construction.

Assign reference roles explicitly: the goods icon supplies composition, graphic outlines,
shared boundaries and intended visibility; real-world images/models supply subtype,
profile, curvature and assembly. User corrections decide conflicts. Establish silhouette,
support and negative space before decals and ink. For each requested refinement, write
one observable criterion and measure that feature rather than relying on a generic PASS.

Diesel is now approved and installed as an **alternate**. All main tiers retain priority.
The older handoff and case histories below describe earlier work, not the current diesel
state. A reviewer saying “ready for feedback” is not an approval to install; existing user
approval is sufficient and must not be requested again.

This is the process document. The style contract (tones, ink weights, rig traps, geometry
rules in that skill) is the sibling skill `blender-goods-icons`; read that first, then this. The
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
| Iron ore | `build_iron_ore` (v38) | **shapes accepted** ("shapes look good"); silver coverage tuned per owner | hero grey pulled back, flanks big; awaiting final eye / install |
| Diesel car | approved `complex_goods/diesel_car/source` | **installed alternate** | Approved sedan, curved windshield base, fitted lamps/hood seams and low-handle sloped-shoulder can |
| Cage loft | `cage_loft`, `build_cage_test` | tool proven on a smoke test | not yet used on a real good |
| Coal | `build_coal` | **first pass** (v2): dark blue-black ANGULAR chunks (subsurf 1, hard crease) + small cubes; blue-grey lit / near-black shadow | owner reviewing |
| Alloy ore | `build_alloy_ore` | **first pass** (v1): 4 different-coloured metal rocks (nugget cuts=0, one solid colour each) | owner reviewing |
| Crude oil | `build_crude_oil` | **first pass** (v3): ribbed steel DRUM (body + washer rims/hoops so they don't cap the lid) + oil `blob` splash + bung washers; NOT in ID_SEPARATION_COLS | owner reviewing |
| Copper ore | `build_copper_ore` | **first pass** (v2): `mottle_rock` - rounded rock, per-face green-malachite/brown patches by noise | owner reviewing |
| Bauxite ore | `build_bauxite_ore` | **first pass** (v2): PISOLITIC - a fibonacci cluster of smooth pea-nodules (icosphere subdiv 2 so facets don't crease-ink; valleys between peas ink) | owner reviewing |
| Lithium ore | `build_lithium_ore` | **first pass** (v1): pink prismatic CRYSTAL cluster (nugget, subsurf 1 hard crease, tall squash); a couple of stray apex lines to clean | owner reviewing |
| Rare-earth ore | `build_ree_ore` | **first pass** (v1): `mottle_rock` - dark host + amber mineral patches (real-world look; shipped magnet omitted) | owner reviewing |

New kit pieces this batch: `mottle_rock` (per-face 2-colour noise mottling for ores that show colour patches not cleavage); `blob` (smooth silhouette-only mass, for liquids); `nugget` gained `subsurf_levels`/`crease`/`grey_depth`/`crack_range` params; `ID_SEPARATION_COLS` gates the object-ID seam pass to rock-PILE icons only (a manufactured object like the drum must NOT get seams between its sub-parts). Bauxite's nodule cluster is inline in `build_bauxite_ore`.

Old row: owner-requested 2026-09-04 - reference shipped icon AND real-world look, loop until it resembles one.

Current installations are recorded in `assets/icons/goods/alternate_icons/approved_manifest.json`.
Do not infer release status from these historical notes; honor the owner's current approval.
The iron-ore recipe (subsurf boulder, grey-cap depth = silver coverage, object-ID separation
pass, faded interior lines, short-edge filter) is documented as rules 54–64 in the sibling
`blender-goods-icons` skill — read those before any rock/ore good.

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
background while preparing proofs or validating the candidate. Fold its findings into one
consolidated revision after reading the evidence; do not change the reviewed snapshot.

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

### Iron ore — organic lumps (hard). THIRTY-EIGHT versions; shapes accepted at v38.
Target: the shipped icon's rust chunks with grey cleavage faces (ranked the most recognisable
iron symbol; pellets read as berries, magnetite as coal, a cart as mining). This case is now the
template for any ore/rock good — the winning recipe is rules 54–64 in `blender-goods-icons`.
- The arc that worked: v13 (inherited: flat single-tone grey, wire-mesh, dull rust) → v14–15
  gave the grey 3 toon tones + planarised the wire-mesh (limited dissolve) + brightened rust →
  a v16–20 DETOUR chasing a dark-rust monolith that kept trading grey area against faceting
  (grey collapsed / "egg" / too small — reverted) → **v24 the turning point: a Subdivision
  Surface over the cut polyhedron** turned the crystalline gem into a rounded BOULDER, which is
  what "reach the look of the goods icon" meant → v25–27 bold per-rock OUTLINES + an object-ID
  separation pass + faded interior lines → v28–30 killed "random lines" (short rust rims wisped
  by the taper; fixed by a stronger dissolve + gentler taper + a min-length filter) → v31–34
  the owner's "middle nugget has too many flat-ish sides": fewer cuts on the hero + drop the grey
  shadow bevel + keep rust cuts off the grey caps → v35–38 "more silver, esp. flanks": grey-cap
  DEPTH per nugget (flanks deep, hero pulled back).
- Tried and rejected across the run: convex hulls (dice); L3 icosphere + strong noise (mush);
  six-lump heap and tall-skinny hero (owner: fewer/larger, as wide as tall); even-azimuth rust
  cuts to break a monolith (ate the front grey); two grey caps per flank (bumpy boundary
  hatching — one big cap is cleaner); mesh-edge cracks (read as broken facet stubs); a vertex
  bevel for soft corners (only nibbles points — subsurf is the answer); an edge bevel (double- or
  erased the facet lines).
- What actually moved the needle, in order: (1) 3-step toon grey with a sun-ward highlight bevel;
  (2) the Subdivision-Surface boulder (rule 54–55); (3) the object-ID separation line (rule 60);
  (4) faded thin interior lines vs bold outlines (rule 61); (5) grey-cap depth for coverage
  (rule 56). Detail/cracks never helped.
- Review criteria that mattered: C1/C2 on the grey, C5 (outline vs interior hierarchy), C9
  (wire-mesh, random stubs), C10, C12.
- Lesson: an organic good is won by getting the FORM soft (subsurf) and the LINEWORK right
  (bold outlines from an ID pass, thin faded interiors, no short stubs) — taste (silver amount,
  which lump) is the last 10%. Every owner note was about form softness, silver coverage, or
  stray lines; never about facet count directly.

### Diesel car and jerrycan — approved complex assembly

The early box-built car and multiple cage/patch revisions failed on subtype, silhouette,
negative space and surface relationships. A fresh profile-driven sedan shell, fitted
lamp/glass patches, shared hood boundaries and an independently studied can finally
converged. The last windshield correction was settled by bow/chord measurement:
reference0.111, previous0.015, overcorrected0.177, accepted0.115.

The full evidence, mistakes, final constraints and reusable engineering details are in
[car-and-jerrycan.md](references/car-and-jerrycan.md). Read it for complex goods rather than
restarting from the legacy box car. Use the paired icon/real-object reference brief and
component-specific review gates in the linked pipeline.

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
