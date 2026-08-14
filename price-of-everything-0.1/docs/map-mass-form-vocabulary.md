# Addendum — decorative mass form vocabulary

> **Owner design direction, 2026-08-14.** BINDING. Extends
> [`map-density-and-port-addendum.md`](map-density-and-port-addendum.md); the gauntlet II
> frozen invariants, two-attempt rule, blind-critic acceptance and reject-neutral rule all
> still apply.

## 1. Why this exists

The decorative fabric currently has **four** mass forms — `solid`, `u`, `l`, `ring` —
selected by a `form_roll` in `scripts/urban_fabric_visuals.gd` (see the roll sites near
lines 3962 and 5162, and the Arin form tally `44 solid / 27 U / 21 L / 26 ring`).

Every attempt to make the map denser has been rejected by the blind critic for
**procedural repetition**: V4.09 (hook glyphs), H2.04 (staggered ticks), V3.03 (cream
buttons), V3.05 (pale diamonds), and in gauntlet III both the density stream (repetition
3→2) and the parks stream (artifact resistance 4→2, explicitly reviving the V3.03/V3.05
tick family). By contrast the coastal stream, which **moved** existing fabric rather than
adding new marks, was accepted at 3.25 vs 2.58.

The conclusion: with only four forms, adding fabric necessarily repeats shapes. **The
vocabulary is the bottleneck, not the density rule.** This addendum widens the vocabulary
so density has somewhere to go.

## 2. New LARGE forms

Applies only to masses at or above the frozen large threshold (**1600 u²**, from
`docs/map-density-audit-baseline.txt`).

Definitions are given in a parcel-aligned frame: the **frontage edge** runs along the
bottom, width `w` across the frontage, depth `h` away from it.

| # | Form | Definition |
|---|---|---|
| 1 | **T-half** | A stroke bar of length `L` along the frontage, thickness `t`; a perpendicular leg from the stroke's centre, length **0.5 · L**, width `wl`. |
| 2 | **T-full** | As T-half, but leg length **= L** (equal to the stroke). |
| 3 | **Right triangle** | Three vertices forming one **right angle**; the two legs lie on the parcel-aligned axes, the hypotenuse closes the shape. |
| 4 | **Hollow triangle** | A **larger** right triangle with a **triangular** hollow core — a triangular ring of wall thickness `t`, inner triangle similar to the outer. |
| 5 | **Half-octagon** | A regular octagon bisected through its centre parallel to a flat side: one long base on the frontage plus four shorter chamfered edges. |
| 6 | **H** | Two parallel bars perpendicular to the frontage, joined by a central crossbar. |
| 7 | **Cross** | Two bars crossing at the centre, four arms. |
| 8 | **Shallow E** | A rectangle with **three notches** cut into one long edge. Notch depth is **shallow** — at most ~35% of the mass depth — so it reads as a shallow E, never a comb. |

## 3. New SMALL forms

Applies to masses below the 1600 u² threshold.

| # | Form | Definition |
|---|---|---|
| 1 | **Square** | Equal-sided; the plain base case. |
| 2 | **Rectangle** | Frontage-aligned, varied aspect. |
| 3 | **Kinked slim rectangle** | A slim bar with **one** bend — two runs meeting at an angle (a dog-leg), not a curve. |
| 4 | **L** | Small L. |
| 5 | **H** | Small H, coarser-limbed than the large H. |

`H` appears in both tables deliberately: the small H is a different instrument at a
different scale, not a shrunk copy of the large one.

## 4. THE CRITICAL CONSTRAINT — parameterise, do not stamp

**A form stamped at fixed proportions map-wide recreates exactly the defect this addendum
exists to cure.** Every form MUST carry deterministic per-instance variation in at least:

- overall aspect ratio;
- limb/stroke thickness as a fraction of the mass (arm width, wall thickness, notch depth);
- which way it faces — orientation is taken from the parcel's actual road frontage, as the
  existing forms already do.

Variation is seeded through `RoadHash` like everything else: no global `randi()`/`randf()`,
no wall-clock. Two instances of the same form in unrelated blocks must not be congruent.

## 5. Experimental design — this change is DENSITY-NEUTRAL

So the vocabulary can be judged on its own merits, this pass **must not change how many
masses are drawn**. Same mass counts, same parcels, same roles, same areas — only the
distribution of *forms* changes.

That makes the blind comparison a clean test of one question: *does a wider shape
vocabulary reduce the perception of procedural repetition?* Density retries (the rejected
density and parks streams) come **afterwards**, into the wider vocabulary.

Report the before/after form histogram map-wide, and confirm mass count and built area are
unchanged to within rounding.

## 6. Geometric safety — the V3.04 lesson

V3.04 was abandoned mid-flight because near-collinear inputs produced **degenerate polygons
and Godot triangulation errors**. Every new form must therefore:

- produce a **closed, simple (non-self-intersecting)** polygon at every parameter value it
  can be constructed with;
- **degrade gracefully**: if the parcel cannot host the chosen form at legal proportions,
  fall back deterministically to a simpler form (ultimately `solid`) rather than emitting a
  sliver, a zero-area limb or a self-touching outline;
- be **rejected whole** by the existing sanitizers if it collides with water, relief
  shoulders, gameplay footprints or road clearance — never clipped into a fragment that
  keeps the original's visual identity. This rule is already established and is not
  relaxed here.

All seven W1.01 water counters, the relief counters and the dry-land guard stay **zero**.

## 7. Verification

In addition to the standing invariant suite (unit tests with a real summary line, two
byte-identical capture runs **against a same-session control**, legacy classic/ink/plate
identity, the legacy→midcentury→legacy round trip, the road-frontage audit frozen on all
eight counters, `git diff --check` clean):

- **Pure-geometry unit tests per form**: closed, simple, correct limb count, correct area
  ratio to its bounding box, correct right angle where specified, and non-degenerate across
  the full legal parameter range including the extremes.
- **An adversarial geometry pass**: hammer each constructor with degenerate and hostile
  inputs — tiny areas, extreme aspect ratios, near-collinear frontages, parcels barely above
  the large threshold — and prove no self-intersection, no zero-area limb, and no
  triangulation error.
- **Form histogram** before and after, map-wide and for the Arin hero slice.

> Note on baselines: the archived `/tmp/poe_g2_baseline/v0` **pixels are no longer a valid
> comparison on this machine** — captures are now 2360×1328 (the display honours
> `window_width_override`), and the morphology harness *centre-crops* rather than
> downsamples, so even its same-sized 960×480 PNGs crop a different world extent. Compare
> against a **same-machine, same-session control captured from your own base commit**. The
> archived counters remain valid; the pixels do not.
