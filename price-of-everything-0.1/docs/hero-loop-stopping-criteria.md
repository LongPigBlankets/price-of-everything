# Hero-loop stopping criteria — agreed with the owner, 2026-08-15

> **BINDING for every per-settlement hero loop.** Agreed so the loops run
> autonomously through the queue without further owner instruction:
> **Capital → Arin → Stoneshore → Vandel**, then stop and report.

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
4. **Vandel**: fabric is thin — envelope grew +59% while built share FELL
   26.4% → 21.9%; the island reads as parallel bars on green. Roads are frozen,
   so the family is thickening/extending existing fabric along existing
   frontage. No new small marks (M3/V5 precedent).

## Process constants

One settlement at a time; strictly sequential Godot under the capture lock;
WIP-commit after every step (session limits have killed two runs — commits are
the only survivable state); HERO_NOTES.md in the worktree is the loop's memory;
each settlement ends with a durable before/after pair under
`reports/map_visual_gauntlet/hero_<settlement>/` and a report section.
