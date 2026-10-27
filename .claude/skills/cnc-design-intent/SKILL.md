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
omission. Licence groups add a price on top (2026-10, owner-approved). Each of a group's three
competing processes still needs its condition, and only then can be licensed: the first for £200,
£500 or £2,000 by era, then 2% and 8% of company revenue for 30 turns. A free pick develops one
in-house with no fee, and only in-house processes can be licensed out
(`scripts/research_licensing.gd`). Regression smell: adding a science-points currency,
converting condition-gates to purchases, letting money buy a node whose condition is unmet, or
licensing out a process that was licensed in. (Separately, many conditions are currently DEAD — a bug,
see `cnc-content-pipeline` — fixing the conditions is good; changing the paradigm is not.)

**Labour policies trade throughput, never free output (2026-10, owner-approved).** A labour policy
moves THROUGHPUT (inputs, outputs and power scale together, `MatchState.run_multiplier`), cash and
labour satisfaction. A flat output bonus makes product from nothing and compounds down a chain, so the
only output-only labour effect is +5% at satisfaction of +90 or more. Regression smell: a labour policy
that raises output without consuming inputs (Profit Share used to be +15% output and was always on).
See docs/pacing-labour-mining-licensing-spec.md §3.

**Output bonuses are rare; growth is physical (2026-10, owner-approved).** A flat output bonus makes
product from nothing and compounds down a chain (+10% at four stages is +46% at the apex). Output
bonuses exist only for extraction yield; the start legacies, while the Original Furnace is still owned
(`scripts/legacy_perk.gd`); timed mission rewards of 15 to 30 turns; a few tier III capstones at +5%;
and Labour satisfaction of +90 or more, at +5%. Everything else is throughput (inputs, outputs and power
scale together, the `throughput` Modifiers domain), a cost cut, or a licence. Research output nodes on
processing buildings became throughput at 1.5× (`modifier_state.gd` UNLOCK_MODIFIERS). Regression smell:
a new permanent output bonus on a processing building, or a labour policy that raises output without
consuming inputs. (Changes design stance A2, approved by owner.)

**Labour satisfaction is a budget (2026-10, owner-approved).** Policies trade throughput and cash for
satisfaction (−100 to +100); the workforce's size and the HR Director add to it. It moves toward its
target by max(10% of the gap, 2) a turn, and only reneging on union agreements (−50) is instant: every
other event shifts the target for a while. Satisfaction sets hiring speed and strikes (phases 2 and 3)
and the +5% output prize. A Comprehensive Union Agreement buys +30 by halving every labour cut made
after signing, for good unless the company reneges; stepping a union down costs 5% of revenue and a
decaying −15 per tier. Regression smell: a policy that raises throughput with no satisfaction cost,
strike protection that costs nothing, or an instant satisfaction jump for an ordinary event.

**Time has a price, and the player sets it (2026-10, owner-approved).** Construction takes 4–6 turns
(`build_duration` + `BUILD_DURATION_BUMP`). A building also waits for staff (`scripts/staffing.gd`): it
runs once 70% staffed, at its fill, and staffing takes 5, 8 or 12 turns by labour satisfaction, counted
from the materials claim. Bought buildings close in 2 turns but arrive 80% staffed. Upgrades take 5 turns,
recipe switches 3. Speed-ups are timed (Andrew Keeler as Expansion Director, mission rewards, the
`construction_time` domain with a 2 turn floor), never permanent. Regression smell: instant hiring or
construction "because waiting is boring", or a permanent cut to build time.
See docs/pacing-labour-mining-licensing-spec.md §5 and §7.

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
One sanctioned exception: the rankings' summed revenue (19 seeded rivals plus the
player) drives urban land prices, +25% of a tile's starting price per doubling
(`scripts/land_price.gd`, docs/land-pricing-spec.md). It is a clock, not a simulation.

**Seams have working limits.** Each deposit extracts freely up to 1.5 level 1 workings. Past a
limit of 3 nothing is held back but the seam may collapse,
5% a turn for each working over. Every working over the free cap adds 100% labour and maintenance on
the whole site, as a multiplier after labour discounts
(`scripts/mining_sites.gd`, docs/pacing-labour-mining-licensing-spec.md §8). Deep extraction
therefore needs labour and maintenance modifiers. Finite seams are charged for what is dug:
throughput counts, yield does not. Regression smell: removing the cap because players want to
upgrade, letting yield research burn seams, or turning the over-cap cost into a percentage that
labour discounts cancel. (Changes design stance A5, approved by owner.)

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
(labelled, not hidden). Expansion Director is an eleventh seat, Andrew Keeler's alone, for his 30-turn
tenure (`AdvisorState.FOUNDER_ONLY_SEATS`): it exists only while he holds it.

**Deliberate friction that looks like UX debt (it isn't):**
- Special orders are one-off commitments (no recurring) — scarcity is the point.
- The anti-arbitrage clamp (sale ≤ buy) — no riskless market loops.
- Same-turn output buffering — co-located chains lag one turn (fairness; see
  `cnc-turn-pipeline-reference`'s worked trace).
- A bought building cannot be cancelled during its 2-turn closing (`MatchState.offer_for_building`).
- A building idles until it is 70% staffed.
- Strikes cut output 60% while inputs are still consumed (`scripts/labour_unrest.gd`), and a struck mine
  still charges its deposit in full. A strike is a cash shock, not a pause.

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
