# Gauntlet II — Pass 1 results

**Date:** 2026-08-14 · **Base:** `decorative-buildings-and-city-look` @ `5443818d`
**Method:** multi-agent, blind-critic gated · **Spec:** [`map-visual-gauntlet-2-prompt.md`](map-visual-gauntlet-2-prompt.md)

---

## Bottom line

> **Zero gates closed.** One candidate was accepted and merged (E.3), one was rejected as
> neutral (D), one was rejected for breaking the hero lock despite genuinely good numbers
> (A+B). Nothing was merged into the owner's branch.

The map's measured defects are **unchanged from V0** except a handful of wide-zoom
industrial anchors — and the one accepted change pushed two rubric categories *down*.

---

## Gate outcomes

| Gate | Verdict | Blind critic | Numeric requirement | Branch |
|---|---|---|---|---|
| **A+B** road-density + organic boundaries | ❌ Not merged | *never run* | Improved, not met | `gauntlet2/gate-ab` @ `1460f16c` |
| **D** junction casing stitching | ❌ Rejected (neutral) | 2.92 vs 2.92 — indistinguishable | Structurally unreachable | `gauntlet2/gate-d` @ `539d1b60` |
| **E.3** industrial landmark tier | ⚠️ Accepted, gate still open | **3.17 vs 2.92 — candidate won** | ✅ Met | `gauntlet2/gate-e3` @ `f5a083ab` |
| **C** whole-body settlement gates | — no attempt this pass | — | 20 components failing | — |

---

## Gate A+B — the near miss

**It moved the numbers more than anything else in the pass**, and was still correctly rejected.

| Metric | V0 | Candidate |
|---|---:|---:|
| Gate A failing tiles | 7 of 87 | **3 of 88** |
| Gate B failing tiles | 13 | **7** |
| Gate C failing components | 20 | 19 |
| Urban blocks | 1,274 | 1,331 |

Arin Old's **−25.38pp gradient is genuinely fixed**. Every Silkstown, Capital and Patran
boundary failure clears; all seven survivors are Arin tiles.

**Why it was rejected anyway** — it broke the locked H2.11 hero slice:

| Hero contract | Locked | Candidate |
|---|---:|---:|
| Parcels | 151 | 164 |
| Built | 38.2881% | 39.6091% |
| Green | 17.5218% | **10.2256%** ← 42% cut |
| Negative | 44.1901% | 50.1652% |
| Forms (solid/U/L/ring) | 44/27/21/26 | 59/34/26/23 |

The spec's hero lock permits replacing that hash **only** if the candidate (a) passes the
+5pp gradient everywhere — it still fails three tiles, (b) scores ≥4/5 in all ten hero
categories in a dedicated critique — **never run, its agent died before scoring**, and
(c) visibly preserves connected perimeter street walls. Merging on metrics alone is exactly
what §12 forbids.

> Its own commits label this **attempt 2** — one materially different attempt remains before
> the two-attempt rule retires the mechanism.

---

## Gate D — rejected, but the postmortem is the payoff

The blind critic scored **both images identically** (2.92 average, no category moving in
either direction) and could not distinguish two of the four named framings at 1:1 *or* at 6×.
Reject-neutral rule applies (precedents H2.05, P4.02).

The structural finding matters more than the rejection:

- Internal endpoint caps: **1,835 → 661** (64% reduction)
- Pixels moved at player zoom: **0.045%**
- Structural floor for *any* matching abstraction: **564** — so the gate's "zero internal
  caps" clause is **unreachable by construction**, because of odd-degree junctions

Mechanism removed completely; the tree is byte-identical to base. **1 of 2 attempts spent** —
a third threshold tune is forbidden and would be pointless.

**Next lever:** draw the road *body*, not the road runs — one polygon per connected same-tier
component, constant width, casing computed once over the whole chain. The visible gore is
casing width taper and two beds of differing width overlapping at the joint, neither of which
point-stitching can touch. The one place stitching visibly helped was a *fill* effect, which
points at the width model as the real lever.

---

## Gate E.3 — accepted, and honestly short of closing

**Won its blind critic 3.17 vs 2.92.** Numeric requirement met and independently re-derived:

- **7 landmarks** selected of 270 industry sites (single digits map-wide, as required)
- Chroma **S 0.503–0.548** — strictly above the ordinary V4.08b tier (max 0.448) and
  strictly below the V4.08a saturated-field band (0.648–0.772). Both sides of the mandated
  window proven.

**But two categories regressed:**

| Category | Before | After |
|---|---:|---:|
| Decorative/gameplay hierarchy | 2 | **4** ↑ |
| Multiscale readability | 3 | **4** ↑ |
| Industrial colour discipline | 4 | **3** ↓ *(was passing)* |
| Absence of procedural repetition | 3 | **2** ↓ |

Categories at ≥4 went 2 → 3, so net movement is positive — but **9 of 12 remain below the
4/5 bar**, and gate E's definition of done is *every* category ≥4.

**Root cause is geometry, not colour:** the accent draws the sprite group's **axis-aligned
bounding box**, so it cuts across 45° street grids, leaves a third-to-half dead margin, and
overprints a shoreline. One landmark of the seven is silently dropped by the dry-land guard
(coastal works `start_b_002_tile_4_9_1`), despite an in-source comment promising it shrinks
rather than vanishes.

**Attempt 2 is unused** and is the cheapest high-value fix in the whole backlog: clip/rotate/
inset the landmark yard instead of drawing its bounding box.

---

## What remains open (regenerated on the merged result, not transcribed)

**Gate A** — 7 of 87 tiles fail the +5pp gradient; four are *negative*:

`tile_10_16` Arin Old −25.38 · `tile_11_16` −5.47 · `tile_9_18` −3.93 · `tile_9_16` −2.22 ·
`tile_11_17` +2.25 · `tile_18_14` +4.80 · `tile_23_8` +4.93

**Gate B** — 13 tiles ≥20% hex-edge coincidence:

`tile_9_9` 81.92% · `tile_9_16` 80.01% · `tile_27_9` 78.43% · `tile_11_16` 77.96% ·
`tile_23_8` 74.25% · `tile_12_16` 52.28% · `tile_24_7` 45.78% · `tile_9_8` 36.14% ·
`tile_10_16` 35.75% · `tile_9_18` 29.38% · `tile_18_7` 23.94% · `tile_12_17` 22.58% ·
`tile_10_18` 20.99%

**Gate C** — 20 of 37 components fail; failure histogram: `minimum_mass_count` 19,
`largest_mass_dominance` 18, `minimum_body_area_outside_core` 16, `minimum_built_coverage` 15,
`minimum_road_frontage_occupancy` 1. Worst are villages (`tile_14_6` at 0.41% built,
`tile_15_14` 0.73%, `tile_7_11` 2.06%). **No attempt made this pass — largest untouched surface.**

**Gate D** — open, 1 of 2 attempts spent.

---

## Process notes worth keeping

**The commit-after-every-step rule paid for itself.** Gate A+B's agent died and reported
`null`, but its work was committed — including verification data written into commit messages.
The integration agent re-ran the harness itself and confirmed every number it claimed was
accurate. In the previous pass the same failure mode cost 100 minutes of work.

**Blind grading caught a real attribution error.** The orchestration prompt and the validating
agent disagreed about which slot held the candidate; the verdict agent resolved it by SHA-256
against the source captures rather than trusting either note. Without that, gate D's artifact
would have been credited to the baseline.

### New environment traps

| Trap | Consequence |
|---|---|
| Fresh worktree has no `.godot` cache | `run_tests.py` **exits 0 with no tests run and no summary** — a silent false green. Precede with `--headless --import`, or seed the cache. |
| Gate C metrics field is `passes`, not `ok` | A naive `ok` lookup silently reports **zero** failures. |
| 37 of 39 settlement records carry a `whole_body_gate` | Denominator wobble; the 20 failing components are the same either way. |
| Workflow `isolation: 'worktree'` | Fails — the session cwd isn't a git repo. Use manual `git worktree add` from `price-of-everything/`. |

---

## Repository state

- **Owner's branch** `decorative-buildings-and-city-look` — untouched by all agents; now carries
  the Goods Graph focus-reset fix (`2f03a5b9`), which repairs the two unit tests that shipped
  in `e8cd62ca` without their fix.
- **`gauntlet2/integrated`** @ `fe73101c` — gate E.3 source + 650 report lines covering all
  three postmortems. **Not merged into the owner's branch; that decision is yours.**
- Gate branches preserved: `gauntlet2/gate-ab`, `gauntlet2/gate-d`, `gauntlet2/gate-e3`.
- Evidence outside git: `/tmp/poe_g2_baseline/v0/` (V0 archive) and `/tmp/poe_g2_wt/int_scratch/`
  (merged-result manifest, first-ever hero PNG anchor). **`/tmp` is volatile — copy to keep.**

---

## Recommended next pass, in priority order

1. **Gate E.3 attempt 2** — clip/rotate/inset the landmark yard instead of its bounding box.
   Fixes both regressions *and* the dropped seventh landmark. Cheapest, highest value.
2. **Gate C** — untouched, 20 failing components, 19 short on mass count alone.
3. **Gate D road-body polygon** — the abstraction the postmortem identifies.
4. **Gate A+B revival** — only under the full hero-replacement burden, with the dedicated hero
   critique that was never run. One attempt remains.
