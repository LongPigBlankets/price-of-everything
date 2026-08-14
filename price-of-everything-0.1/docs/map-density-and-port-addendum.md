# Addendum — settlement density, park balance, coastal reach, and port form

> **Owner design direction, 2026-08-14, given from direct visual inspection of four
> in-game captures.** This addendum is BINDING and takes precedence over the gauntlet II
> prompt where they differ. It converts the owner's visual feedback into hard, testable
> gates.
>
> Everything in `map-visual-gauntlet-2-prompt.md` still applies: the frozen invariants, the
> draw-only contract, the two-attempt stopping rule, blind-critic acceptance, reject-neutral,
> and the retired-mechanism graveyard.

## 1. The owner's verdict, verbatim in substance

1. **Too many single-tile urban centres are too sparse.** Arin is the reference that works.
2. **Stoneshore is too small** — it should fill more of its tile, and *"real cities would
   absolutely push closer to the sea on the coastal urban tiles."*
3. **Vandel is undersized** — *"a port with that location would push against the lake and
   the sea."*
4. **Capital is sparse at max zoom-out in its centre-east tile** — *"it almost looks like the
   city is split in two. Perhaps the issue is park density."*
5. **Ports should have straight arms, not kinked ones** — and *"between the arms there is
   still land"*, which should be harbour water.

## 2. Hard gate — building-count minimums by tile class

These are floors, not targets. Every tile must satisfy the row for its class. Counts are of
**decorative masses actually rendered** in the mid-century style (gameplay buildings are
never counted — they are frozen and separate).

| Tile class | Small buildings | Large buildings | Green spaces / parks |
|---|---|---|---|
| **Urban** (the 92 profiled urban tiles) | **≥ 10** | **≥ 3** | **≥ 2** |
| **Sparse** (non-urban WITH ≥1 authoritative road) | **3 – 10** | **0 – 2** | — |
| **Mountain** (terrain class mountain) | **≤ 2** (cap) | 0 | — |
| **Remote** (non-urban, NO road) | **1 – 4** | 0 | — |

Rules of precedence and interpretation:

- **Mountain cap wins over the sparse floor.** A mountain tile that carries a road is capped
  at 2 small buildings; it does not have to reach the sparse minimum of 3.
- **Remote tiles are exempt from the sparse floor** — they are deliberately quiet, 1–4 small
  buildings only, and 0 large.
- A tile physically unable to meet its floor (water margin, relief shoulders, forest
  occupancy, gameplay footprints leaving no dry buildable area) must be **reported as a
  documented physical shortfall with its rejected-candidate counts**, exactly as the
  accommodation planner already does. A documented shortfall is acceptable; a silent miss
  is a gate failure.
- **Small vs large must be defined once, from the existing mass-area distribution, and
  stated in the audit output.** Do not invent a per-tile relative threshold — one absolute
  world-unit area threshold, applied map-wide, so counts are comparable between tiles.

This gate **supersedes and sharpens gate C** of the gauntlet II prompt. Gate C's failure
histogram (19 components short on `minimum_mass_count`, 18 on `largest_mass_dominance`) is
the same defect the owner is seeing; where the two disagree, **this table wins**.

## 3. Hard gate — park/green area halved in the four largest cities

- Identify the **four largest connected urban settlement components by tile count** (state
  which they are in the audit output; on current data these are expected to be the Arin,
  Capital Port, Patran and Teganfort components — verify, do not assume).
- **Halve the total green/park AREA** in those four components, to ±10%.
- **Backfill the freed area** with either:
  - **plots for future industrial gameplay buildings** — prefer routing this through the
    existing `AccommodationSitePlanner`, which already plans deterministic draw-only
    future-building sites and is the natural home for "reserved plot"; or
  - **smaller decorative buildings**, finer-grained than the current ordinary vocabulary.
- The urban floor of **≥2 green spaces per urban tile still applies.** Halving is an *area*
  reduction, not a count reduction — fewer and smaller parks, never zero parks on a tile.
- Target defect: at max zoom-out, Capital's centre-east tile must no longer read as a gap
  splitting the city in two.

## 4. Hard gate — coastal reach and tile fill

- **Coastal urban tiles must push their fabric toward the shoreline.** The current inset
  leaves an unbuilt collar between the settlement and the water that real cities would not
  have. Reduce that collar to the minimum the water-safety guards require.
- **All existing water safety remains absolute.** The seven W1.01 counters stay zero: no
  ordinary-mass water overlap, no industrial-support overlap, no cross-bank masses, no
  disconnected post-clip masses, no roof-element or shadow overlap, no uncovered river
  joins. Pushing toward the sea must never put a building, roof, mark or shadow on water.
- **Named targets:** Stoneshore must fill materially more of its tile and reach its coast;
  Vandel must read as a port that presses against **both** the lake and the sea.
- Success is judged by the blind critic against the Arin reference, not by coverage
  percentage alone — but report the coverage change.

## 5. Hard gate — port arm geometry

- **Arms must be STRAIGHT.** The current bent/kinked arm (independent per-arm bend, from the
  L1 coastline-adaptive search) is rejected by the owner. Arms may differ in length, width
  and angle from each other, but each arm is a straight run.
- **The water between the arms must be water.** The owner can see land between the arms.
  Investigate the contradiction with L1's recorded audit, which claims *"100% sampled basin
  water"* and *"0 opaque basin overlap"* for all four ports — one of these is true:
  1. the audit samples the basin polygon while the *drawn* apron/head/land fill covers it;
  2. the arms are land-rooted (L1 itself recorded Arin's right arm at only **29.53%**
     sea-deck coverage) so the enclosed area is genuinely land; or
  3. the basin polygon and the rendered geometry have diverged.
  **Diagnose which before changing anything, and say so in the report.** A metric that
  passed while the defect was visible is itself a finding worth recording.
- Retained from L1 and still required: exactly two cranes per port, one per arm; real
  authoritative-road access; zero river/channel obstruction; zero gameplay overlap; zero
  decorative/park overlap; the marine reservation still protecting navigable water.
- The rectangle-and-shore-normal primitive from K1 stays **retired** — straightening the
  arms is not permission to revive a fixed symmetric U stamped on every site.

### 5a. Owner ruling, 2026-08-14 — close the foreshore by moving the port out

Straight arms were delivered (max bend 0.00°, was 18.66–27.24°) but **land remained between
the arms**: 2,352u² residual, 95.6% inter-arm water. That residual is bounded by the 12u
NavGrid dry-land lattice, not by the coastline, so it could not be closed by extending the
apron without drawing geometry outside the instrument that certifies it dry.

> **Owner's ruling:** *"close it by moving the port further out if needed. Port is allowed
> to sit on up to +10/-10 degrees from perfect orientation on the shore as long as the main
> body touches the shore at least 75% on the shore-side and there is only sea between the
> arms."*

The rule now in force:

- **The port may be moved SEAWARD** as far as needed to eliminate land between the arms.
  This is the sanctioned fix and it replaces the "acceptable foreshore" option.
- **Orientation tolerance: ±10°** from perfect orientation to the local shore. Ports need
  not be exactly shore-normal; up to ten degrees either way is permitted to find a seating
  where the basin is entirely water.
- **The main body must touch the shore along at least 75% of its shore-side edge.** Moving
  seaward must not leave the port floating offshore — it stays a landward-rooted structure.
- **Only sea between the arms. `interarm_sea_coverage` must be 100%** — zero land inside
  the U, not 95.6%. This is now a hard gate, not a threshold to tune.
- **Do NOT loosen the existing NavGrid dry-land gate** to achieve this. That was flagged as
  a goalpost move and remains forbidden. Move the structure; do not weaken the instrument.
- Everything in section 5 above is retained: straight arms, two cranes one per arm, real
  road access, no river obstruction, no gameplay or decorative overlap, marine reservations,
  and all four catalog ports valid.

## 6. Verification additions

A new deterministic audit must emit, per tile: tile id, nickname, class (urban / sparse /
mountain / remote), small count, large count, park count, park area, buildable dry area,
and pass/fail against §2. It must fail the run on any undocumented miss. Add it to the
capture harness family and to the standing invariant suite.

Everything already required stays required: unit suite green, two byte-identical capture
runs, legacy classic/ink/plate byte-identical with the legacy→midcentury→legacy round trip
exact, road-frontage audit frozen on all eight counters, the seven water counters zero,
relief counters zero, `git diff --check` clean.

## 7. Explicitly out of scope for this pass

- Gameplay changes of any kind. Reserved "plots" are **draw-only**; they must not enter
  occupancy, placement legality, click testing, ownership, economy or save data.
- The gauntlet II gate A (road-density gradient) and gate B (hex-edge boundaries) mechanisms
  — they remain open and are not reopened here.
- Gate E.3 attempt 2 (the industrial-landmark bounding-box geometry fix) — a known pending
  item, deferred to keep this pass focused on the owner's feedback.
