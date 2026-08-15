# Hero-loop stopping criteria — agreed with the owner, 2026-08-15

> **BINDING for every per-settlement hero loop.** Agreed so the loops run
> autonomously through the queue without further owner instruction:
> **Capital → Arin → Stoneshore**, then stop and report.
>
> **VANDEL IS DEFERRED (owner ruling, 2026-08-15)** — it is the settlement most
> vulnerable to a road-layout change, so it is accepted as it stands today and
> reviewed after any roads pass, rather than authored twice.

## The rule: critic-gated ratchet

Each iteration makes ONE authored change, captures fixed framings, and is judged
BLIND against the current best (initially the untouched control). Accepted →
committed, becomes the new best. Rejected/neutral → reverted exactly (verified
by re-capture hash).

**Stop-success** (either):
- blind critique reaches **≥4/5 on the in-scope categories** — inhabited
  impression, continuous figure/ground, green integration, decorative/gameplay
  hierarchy, artifact absence, multiscale readability — on the settlement's
  fixed framings (the bar H2.11 / S2.05 / C1.01 met); or
- **2 consecutive non-improving iterations after at least one accept** — bank
  the best, move on.

**Stop-failure:** two materially different mechanisms rejected with nothing
accepted → postmortem to the report, next settlement.

**Budget:** max **6 judged iterations** per settlement.

## Metrics are floors and tripwires, never accept triggers

Owner's decision (against coverage-as-target, on the evidence of five
documented metric-certified defects: L1 basin, N2 paving, tile_20_11, V5
coverage-while-fusing, the tautological park ring):

Every iteration must hold, vs the settlement's control:
- unit suite green with a REAL `==== N passed ====` line;
- seven W1.01 water counters and all relief counters **zero**;
- park **holes** not increased — where holes are the named defect they must
  **fall**;
- addendum §2 floors on the settlement's tiles not regressed (≥10 small /
  ≥3 large / ≥2 parks urban);
- no new `fabric_slab` / `fabric_confetti` / `fabric_paved` verdicts on the
  settlement's tiles;
- Arin hero metrics byte-identical — EXCEPT during Arin's own loop, where the
  standing hero-replacement rule applies: a candidate may replace the lock only
  by winning the blind critique against it; the accepted result becomes the new
  lock.
- Per-tile decorative coverage and settlement built % are REPORTED every
  iteration for the record — never targeted.

## Per-settlement scope (the named defect each loop exists to fix)

1. **Capital** (in flight): `tile_25_9` is an unenclosed pasture — 7 greens /
   31,625u² / zero large buildings, all 10 green verdicts `no_bounding_fabric`
   holes; Capital-tile hole baseline 25. Success = the wedge reads as enclosed
   deliberate pocket greens, holes materially down, the city one body at wide
   zoom.
2. **Arin**: the owner's reference — protect what works. Named defects: the
   west half reads as "field polygons, not blocks" (coarse parcel grain), and
   4 of 9 tiles fail density floors (mostly `green_below_floor`). Changes must
   beat the H2.11 lock blind.
3. **Stoneshore**: coastal reach already accepted. Remaining: `tile_5_10`
   Docks `green_below_floor` (the ports apron displaced a green — a known
   combination regression), and the K1 caveat that the central open field
   weakens figure/ground.
4. **Vandel — DEFERRED, do not run this loop.** Accepted as-is pending a roads
   review. Recorded for when it resumes: fabric is thin — envelope grew +59% while built share FELL
   26.4% → 21.9%; the island reads as parallel bars on green. Roads are frozen,
   so the family is thickening/extending existing fabric along existing
   frontage. No new small marks (M3/V5 precedent).

## Process constants

One settlement at a time; strictly sequential Godot under the capture lock;
WIP-commit after every step (session limits have killed two runs — commits are
the only survivable state); HERO_NOTES.md in the worktree is the loop's memory;
each settlement ends with a durable before/after pair under
`reports/map_visual_gauntlet/hero_<settlement>/` and a report section.


## Robustness to a later roads change (owner requirement, 2026-08-15)

A roads redesign is now known to be **gameplay-neutral if per-tile flags/levels are
preserved** (see the architecture-contract skill), so one is plausible later. The three
settlement systems built here must survive it.

**The rule: authored work is expressed as RULES OVER ROAD-DERIVED GEOMETRY, never as fixed
positions.**

- No hard-coded world coordinates, and no tile identity derived from arithmetic on ids.
  (Precedent: a Silkstown oracle hard-coded `(9, 8)`, which resolves to `tile_10_9`, not
  Silkstown — it measured the wrong tiles for days. Always resolve through `id_to_coord`.)
- Anchor authored guides to **road-caused features** — street faces, junctions, frontage
  runs — not to absolute points. If a road moves, the guide must move with it.
- Prefer selecting from what the road graph produces (nearest still-built parcel, the face a
  junction bounds) over placing at a chosen location.

**The test each settlement must ship:** a road-perturbation fixture, modelled on the K1
road-layout fixture that already exists. K1's proved that identical roads reproduce the exact
core polygon, that replacing a horizontal road with a vertical one moves growth from
horizontal to vertical, and that the core moves >40u away from a removed road. Each
settlement's loop must add the equivalent for its own authored work: perturb a road serving
that settlement, assert the authored fabric follows rather than staying put or vanishing.
A settlement whose fabric does not move when its road moves is hard-coded, and fails.
