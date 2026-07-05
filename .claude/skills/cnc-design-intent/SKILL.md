---
name: cnc-design-intent
description: Load this BEFORE "fixing" anything that feels like a design flaw in price-of-everything - prices always falling, hidden deposits, no research points, goods nobody consumes, no combat, blind building on unsurveyed tiles - and before proposing design changes. The WHY document - deliberate decisions marked do-not-fix, with what a regression would look like.
---

# Design intent — deliberate, do not "fix"

The most expensive junior failure mode on this project is the well-intentioned
regression: "fixing" a deliberate design decision back into a genre default. Every item
below is DELIBERATE. If you think one is wrong, that's a design conversation with the
owner — not a patch.

Sources of record: `docs/feature-plans.md` (closest to an overview),
`docs/victory-system-spec.md`, `docs/tech-gating-and-deposit-penalty-spec.md`,
`docs/goods-balancing.md`, CLAUDE.md. (All under `price-of-everything-0.1/docs/`.)

## The stances

**Five simultaneous victory tracks** (Greenest, Richest, Efficient, Widest, Autarkic)
scored every turn on an escalating-commitment curve, with minimum-shipment floors
before scoring. DELIBERATE: players optimize a portfolio, not one number. Regression
smell: collapsing to a single score, or making one track dominant "for clarity".
(Known-quirky by design: market buys count in the Logistics/Efficient feed both sides;
construction market buys break Autarkic streaks — documented in `TRACK_EXPLAIN`.)

**The carbon three-act squeeze.** A scheduled decarbonisation ratchet with warning
windows is the game's spine; the CSV carries `co2_tax_multiplier` per good NOW, but
the tax MECHANIC is PENDING (open/candidate — do not claim it works, do not delete the
"unused" columns). The dirty→clean recipe routes exist to serve this arc.

**Recipe routes: dirty→clean spectrum.** Most goods have multiple routes;
coal / petroleum needle-coke / carbonised-biomass are interchangeable across recipes —
THE carbon-substitution lever. Regression smell: "deduplicating" parallel recipes or
normalizing their costs into equivalence (the cost gap IS the choice).

**Unlock-by-doing. No research points.** Research unlocks fire from what you DO
(build counts, production, profitable runs) plus limited free picks. A stance, not an
omission. Regression smell: adding a science-points currency, or converting
condition-gates to purchases. (Separately, many conditions are currently DEAD — a bug,
see `cnc-content-pipeline` — fixing the conditions is good; changing the paradigm is not.)

**Prices decay monotonically and forecasts are honest.** Per-good decay + visible
10-turn forecasts are designed pressure: yesterday's product gets cheaper; you must
move up the value chain. The counterweight is the player-driven price-impact model
(2026-07). Regression smell: "fixing" decay with mean-reversion to base, or hiding
forecasts because they feel like cheating.

**Blind building on unsurveyed tiles is a gamble, on purpose.** Deposits are hidden
until surveyed; building a mine blind is allowed and can fail. The UI must NOT leak
deposit knowledge (the construct panel was survey-gated in 2026-07 precisely to close
a leak). Regression smell: any panel/tooltip that reveals unsurveyed deposits "for
convenience".

**Legibility is first-class.** The RAG imputed-cost indicator, the encyclopedia/
X-search, price forecasts, impact-threshold columns, agenda/loyalty readouts — the
game explains itself. New mechanics ship WITH their legibility surface. Regression
smell: a mechanic whose only readout is a debug print.

**Apex goods are sell-only endpoints.** ev_car, wind_turbine, heavy_vehicle etc. have
no consumers by design — they're the value-chain summits (volume-apex pricing). Not
"orphaned data".

**The NPC world is scenery-with-services.** ~472 pre-placed NPC buildings don't
simulate; they sell (building market), anchor ports, and dress the map. Regression
smell: simulating NPC economics "for realism" (a performance and balance landmine).

**No combat. 300-turn cap.** The cap (turn_manager `MAX_TURNS`) shapes every curve;
the game soft-ends and still shows DECIDE for overlays.

**Make-vs-buy flips with integration depth.** Early: buying inputs from the market is
correct. Later: integration (own chains) wins. The tension is tuned, not incidental —
freight, spreads, impact thresholds and seaport subscriptions all lean on it.

**Aesthetic: functional WPA / mid-century cartographic** (Booth, Sanborn). The DS
theme and the research panel are the anchors (`cnc-ui-and-theming`). Regression smell:
modern flat-UI drift, decorative gradients, non-DS colors.

**Advisors: seats-first, missions as arcs.** 10 seats with governing disciplines, a
12-advisor roster with derived stars, loyalty driven by likes/dislikes agendas, 5-step
mission chains. The 2026-07 UI made assignment ROLE-first (pick the seat, then the
person) — keep that paradigm. Known-open: three seats have no mechanical effects yet
(labelled, not hidden).

**Deliberate friction that looks like UX debt (it isn't):**
- Special orders are one-off commitments (no recurring) — scarcity is the point.
- The anti-arbitrage clamp (sale ≤ buy) — no riskless market loops.
- Same-turn output buffering — co-located chains lag one turn (fairness; see
  `cnc-turn-pipeline-reference`'s worked trace).

## How to use this file in review

For any diff that changes player-facing behavior, check it against this list. If it
touches a stance: the PR/commit must say "changes design stance X, approved by owner"
— otherwise reject. If it merely brushes one (e.g. adds a price readout), cite the
stance it serves.

## When NOT to use this skill
- The numeric details of a mechanic → `cnc-economy-reference`
- Whether a specific oddity is a bug or intent → check the audit's known-weak list
  (`cnc-architecture-contract`) first; if absent there AND absent here, treat as a bug
  and go to `cnc-debugging-playbook`

## Provenance and maintenance
Compiled 2026-07-05 from docs/ + owner rulings. Volatile: the carbon mechanic's
status (PENDING), the advisor effect gaps, the dead research conditions.
- Re-check carbon status: `grep -rn "co2_tax" price-of-everything-0.1/scripts/ | grep -v csv` (few/no sim hits = still pending).
- Re-check track feed quirks: `grep -n "TRACK_EXPLAIN" price-of-everything-0.1/scripts/victory_state.gd`
- Docs list: `ls price-of-everything-0.1/docs/`
