# Carbon and Capital — Holistic Audit (mechanics · economics · architecture · UX)

**Date:** 13 July 2026 · **State audited:** branch `rebalancing-v4`, working tree including the
uncommitted v4 balance pass. Four parallel deep-reads (sim engine, architecture/code health,
player scaffolding/UX, economy data) plus targeted re-verification of the July 2026 mechanics
audit's headline findings against this checkout.

**Companion doc:** `docs/mechanics_audit_2026-07.md` (the earlier deep mechanics audit). Section 6
below records which of its findings are fixed vs still open *in this checkout* — read that before
acting on the older doc.

---

## Verdict in one paragraph

The engine plumbing is unusually disciplined for a solo EA project — explicit turn ordering, real
determinism, versioned saves with migrations, a genuine Leontief cost solver, per-network power
settlement, and a diagnostics/alert layer that is best-in-class for the genre. The exposure is one
level up: the *economic model* the plumbing executes is still missing its negative-feedback core
(prices are a deterministic decay curve; the grid is an infinite fixed-price sink), the live engine
cannot yet finance the integrated mid-game the design model promises (e2e portfolios go bankrupt),
and a handful of "wired but dead" UI elements sit exactly where players are most vulnerable. None
of the criticals are structural rewrites; most are seams the codebase has already prepared.

---

## 1. Game mechanics

### Strengths
- **Explicit, profiled turn pipeline.** `_wire_sim_listeners()` (`turn_manager.gd:74-84`) replaced
  the old autoload-registration race with deliberate listener order; all 14 PROCESS sub-phases are
  TurnProfiler-sectioned. Fragile ordering is at least *visible* and measured.
- **CostSolver is a real Leontief solver** (`cost_solver.gd:75-168`): topological sweep, market-value
  byproduct allocation across multi-output recipes, cycle/starvation guard, level-scaled cost basis.
- **Per-network power settlement** (`power.gd:114-221`): connected-component flood fill, independent
  surplus/deficit settlement per physical cable network, deterministic self-supply attribution.
- **Battle-hardened logistics edges**: unreachable routes charge nothing (INF_TURNS guarded,
  `transport_service.gd:72-78`); warehouse overflow is held-and-retried; the input pipeline is
  storage-budget-aware and counts in-flight + overflow-held goods (`production.gd:2089,2216-2225`),
  killing the historic re-buy doom loop; JIT direct feed works.
- **Save/load & determinism rigor**: tolerant readers everywhere, RNG state round-trips, the
  mid-resolution-load corruption now guarded (`save_load.gd:158,183-188`).
- **Victory design**: monotonic best-ever tracks with minimum-scale gates and the rising win bar
  (`victory_state.gd:130-133,301-327`) — a clean time-pressure mechanic.

### Weaknesses
- **W-M1 · The price system's designed counterweight barely binds.** Monotonic per-good decay and
  scenery-only NPCs are **deliberate design stances** (see `cnc-design-intent`: decay is the
  move-up-the-value-chain pressure; simulating NPC economics is an owner-ruled landmine — do not
  "fix" either). The *actual* weakness is that the stance's designated counterweight — the
  player-driven glut/deficit price-impact model — rarely triggers at shipped volumes
  (`GLUT_UNITS=100` vs median run output 22, see W-E6), so in practice the squeeze runs
  uncounterweighted against a known curve. This is a tuning gap inside the stance, not a paradigm
  problem.
- **W-M2 · The grid is an infinite source/sink at fixed prices** (`power.gd:91-97`,
  `economy_config.gd:113-114`): power is never scarce, only cable-capped. Grid-oversupply glut is
  acknowledged as pending in the balance docs — this is the unbuilt half of the counterweight, not
  a deliberate stance.
- **W-M3 · RAG misprices self-generated power.** `production.gd:1325` imputes
  `energy_req × GRID_BUY_PRICE` for *all* consumers, even fully self-powered ones; cash only pays
  net grid import. The profitability signal punishes the exact green/vertical strategy the carbon
  squeeze pushes players toward.
- **W-M4 · Power-cap zero-output cliff.** A generator or (levelled-up) consumer whose effective
  MW crosses the tile cable cap flips to `can_run=false` — zero output, not throttled
  (`production.gd:1895-1898`). An upgrade the player thinks strictly positive can fully starve a
  building with no obvious cause.
- **W-M5 · Two disconnected bankruptcy concepts.** `BANKRUPTCY_FLOOR=-10` only emits a warning that
  routes to an empty/"superseded" briefing item; the real fail state is `SolvencyState`
  (−500 × 5 turns) — and `SolvencyState.enabled = false under headless` (`solvency_state.gd:39`),
  so the in-engine lose condition never fires on the balance harness.
- **W-M6 · `quote_market_sell` misprices mixed manifests**: one representative good picks the route
  and lag for the whole heterogeneous batch (`transport_service.gd:176-227`).
- **W-M7 · Loan principal is booked as interest** (`production.gd:528`), inflating `money_out` and
  shielding tax; `LoanState` already computes the split (`loan_state.gd:164-165`) but production
  doesn't use it. Money panel and RunMetrics are wrong by the same amount.
- **W-M8 · Ordering guarded only by comments.** The hard cross-dependencies inside
  `_process_production()` (same-tile supply before market buys, tick-before-claim, prune-before-draw)
  have no test asserting the sequence.
- Edit debris in the hottest file: mangled comments and a shadowed vestigial `summary` member in
  `production.gd` (~:75-82, :497, :530).

---

## 2. Economics & balance (v4 pass, working tree)

### Strengths
- **Reproducible formula pipeline** (`systemic_recipe_formula.py` → `apply_systemic_recipe_plan.py`
  → `recipe_rebalance.py` → `balance_success_metrics.py`) replacing ad-hoc price edits, with
  committed, diffable report CSVs and a decision-facing scorecard.
- **Healthy headline numbers**: 121/136 recipes in band on the design view, 99/137 on the deployed
  view; standalone viability 75/79 start-unlocked recipes; research-route superiority 44/47;
  integration links 105/105 profitable.
- **Bootstrap materially improved**: default start £200 → £600 (`economy_config.gd:7`,
  `data/starts/default.json`); mine-first is cash-positive by turn 3.
- **Past exploits closed in data+code**: labour-slider output pressure now real
  (`match_state.gd:4117`), labour floor 0.40, glut/deficit price impact live at the
  `execute_sale`/`_tick_impact` seam, farm/forest rescued via biomass recipes r_208–r_216.

### Weaknesses
- **W-E1 · The integration-financing wall (unsolved, live-engine).** `balance_v4_e2e_results.md`:
  no 150-turn portfolio exceeds £200/turn; the motors portfolio produces by turn 8, sells 672 units,
  and **goes bankrupt turn 43**; the batteries portfolio ends one turn short of insolvency. The
  design model promises +£108–£287 full-integration margins the live engine cannot reach under
  loan/land/insolvency rules. The report's own conclusion: an integration-*financing* problem, not
  an output problem.
- **W-E2 · Design-model ↔ live-engine divergence persists.** v4 tooling validates against the
  offline model, not the shipped `cost_solver.gd`/`production.gd`; imputed power (W-M3) is one
  concrete divergence; `tools/balance.py` constants remain a hand-copy of `economy_config.gd` with
  no sync check.
- **W-E3 · 38/137 deployed recipes outside their own band.** Money-printers: Fertilisers r_047
  **+£214.59** vs target 5–10; Coal Liquefaction +£154; Hydrogen Power +£138; solar panels up to
  +£95 vs 40–60. Under water: Sulphuric Acid r_115 **−£84** (the pass docs claim it was made
  slightly profitable — it isn't), Lithium Electrolysis −£64, Battery Storage −£7.
- **W-E4 · Large dead content surface.** 60/200 recipes reference 31 goods absent from
  `Goods - goodsMVP.csv` (food, wood, paper, petro-distillation, biofuel chains; `noble_gases`
  phantom ×4) and are silently filtered. Whole building families are inert
  (`timber_paper_factory` has *no building row at all*; `consumer_goods_factory` 0 active;
  `bio_chem_plant` 1/9). Buildable-looking buildings and research nodes lead nowhere.
  *Calibration:* apex goods with no consumers (ev_car, wind_turbine…) are deliberate sell-only
  endpoints per `cnc-design-intent` — the finding is specifically the orphaned-goods chains and
  the building with no row, not the apex endpoints.
- **W-E5 · Electronics build-material loop still un-costable**: computer remains a build material
  for the fabs that make it, and `cost_solver.gd:167-177` never costs cycle members — RAG blanks
  for the whole chain when the loop closes.
- **W-E6 · Glut rarely self-triggers** (`GLUT_UNITS=100` vs median run output 22); grid-oversupply
  glut and per-tile renewable potential remain unimplemented, so mine-and-sell keeps an edge.
- **W-E7 · Doc drift**: shipped labour-track modifiers are −10%/−10% (double the documented
  −5%/−5%); `economy-bootstrap-findings.md` and `battery-storage-spec.md` are stale vs engine.

---

## 3. Architecture & code health

### Strengths
- **Determinism is real**: exactly one global `randi()` in `scripts/` (audio, commented exempt).
- **Save system**: `SAVE_VERSION := 6`, stepwise migrations, newer-save rejection, 97 tolerant
  `.get(key, default)` reads, custom JSON (no ResourceSaver), mid-resolution load guard.
- **Clean node access**: zero `/root/…` absolute paths, zero `../..` traversals in 284 scripts.
- **Test mass**: 226 unit test functions + the 1,652-line e2e harness + scenario JSONs, with
  correct exit codes and a cross-platform runner.

### Weaknesses
- **W-A1 · `match_state.gd` is a god-object**: 5,266 lines, **350 functions**, referenced by 87 of
  284 scripts (31%). Merge-conflict epicenter across 30+ active branches; hardest thing to test.
- **W-A2 · Live v1/v2 duplication**: `building_detail_panel.gd` (3,293) **and** v2 (2,186) are both
  wired; same for `construct_panel` v1/v2. ~5,500 lines of parallel logic where a fix to one
  silently misses the other.
- **W-A3 · Silent CSV load failures**: `catalog.gd:619-648` drops malformed rows and turns a typo'd
  good name into `good_id == ""`/qty 0 with no `push_error`; no load-time referential validation;
  no data-integrity test. The offline Python validator points at a *stale, different* dataset.
- **W-A4 · CSV-as-translation import pollution**: 284 junk `.translation` files (166 from
  `reports/balance/`!) generated because every CSV imports as `csv_translation`, while
  `project.godot` has no `[internationalization]` section — zero runtime value, heavy git churn
  (176 dirty `.translation` + 207 dirty `reports/` files right now), and a latent hazard the day a
  real locale is added. Fix: import-exclude/`keep` these CSVs, gitignore `reports/`.
- **W-A5 · DS façade bypassed 1,129 times** (hardcoded `Color(...)` literals), worst in
  `victory_end_screen.gd` (108) and the designated reference panel `research_panel.gd` (53).
- **W-A6 · Repo hygiene**: 112 branches; the entire v4 rebalance uncommitted; 330 MB `assets/`
  (8 MB banner JPGs) against a web-export ambition; committed screenshots and generated artifacts.
- **W-A7 · No determinism-regression test** (same seed → identical state hash) despite the whole
  save/balance edifice resting on it; UI exercised only by assertion-free screenshot scenes.

---

## 4. Player scaffolding / UX / UI

### Strengths
- **Best-in-class stall diagnostics** (`building_readout.gd:272-411`): ordered plain-English causes
  (unpowered, cables overloaded with kW numbers, starved-with-good-list, no input pipeline,
  stockpile over-utilised, unreachable outputs) each with a prescriptive fix.
- **Self-clearing alert layer** (`turn_briefing.gd`): bankruptcy runway, starved counts split
  power-vs-input, storage-full vs structurally-undersized, input-cash shortfalls — each with
  magnitude-based re-surfacing so dismissed alerts return only when they worsen.
- **Tutorial hardened against deviation**: state-verified detectors (steps complete even if the
  event fired early), spotlight-fail passthrough, lock-panel re-open, advance-on-order predicates,
  always-available exit. No engine-level softlock found.
- **Balance-proof tutorial copy**: costs/prices computed live from Catalog at `steps()` time.
- **Real design system** (`ds.gd` façade, shared RAG single-source, shared tooltips) and
  scaffolded destructive actions (multi-turn demolish with Cancel, confirm dialogs).

### Weaknesses (ranked by player impact)
- **W-U1 · Fake buttons at the crisis moment.** `capacity_dialog.gd:102-105,142-144`: the dialog
  that auto-pops on tile-capacity shows a real cost card for "Expand Logistics and Storage +500"
  and "Stop Production" — both `pass`. The *working* expansion lives in the Stockpile tab
  (`tile_info_panel_v2.gd:1999`). The game's own suggested escape from the storage doom-loop
  silently fails.
- **W-U2 · Lorem Ipsum in shipped narrative**: three decision bodies (`decision_state.gd:302-337`)
  and the CO2-tax/green-subsidy announcement bodies (`policy_schedule.gd:20-35`) — core narrative
  beats every player hits.
- **W-U3 · Dead Politics (N) button** (`bottom_menu.gd:425-426`) — first-class bottom-bar button
  with a hotkey, labeled by the tutorial's UI primer, silent no-op.
- **W-U4 · Tutorial over-promises**: intro advertises surveying/mining/water/own-power
  (`tutorial_intro_panel.gd:15-19`); those steps are deferred and never returned by `steps()`.
- **W-U5 · Aluminium branch contradiction**: claims co-located output "feeds the factory on-site"
  but never has the player reroute output from the default Market destination; that branch also
  never teaches research or routing.
- **W-U6 · Victory and Market are never taught** — a tutorial graduate can integrate a chain but
  doesn't know how to win or read prices; encyclopedia "Game mechanics" has 3 entries.
- **W-U7 · No accessibility**: settings tabs beyond Audio are "Coming soon"; heavy RAG color
  reliance with no shape/text alternative, no font scaling, no rebinding.
- **W-U8 · Undiscoverable power features**: CTRL+click ship-quantity routing has no hint anywhere;
  labour policies openly say "No effect yet"; building-market non-tile view is an inert
  placeholder.
- **W-U9 · Per-building market-buy attribution gap** (known): input purchases pool at tile level,
  so "which building's purchases cost me £X" has no authoritative answer.

---

## 5. Critical issues — and what makes them critical

Ranked. "Critical" here = breaks the core loop, destroys player trust at a decisive moment,
invalidates the signal players/designers steer by, or can destroy the live dataset.

1. **The live engine cannot deliver the designed mid-game (W-E1).** Following the *intended*
   strategy — integrate a motor chain — bankrupts the player on turn 43 in the project's own e2e.
   Critical because it's not an edge case: it is the core loop failing under the shipped rules, and
   every balance number above it (targets, bands, scorecards) is validated on a model that doesn't
   include the financing constraint that kills the run. Compounded by `SolvencyState` being
   disabled headless (W-M5): the in-engine fail state is invisible to the harness that is supposed
   to catch exactly this.

2. **The squeeze's counterweights don't bind in practice (W-M1 + W-M2 + W-E6).** Monotonic decay
   and scenery NPCs are deliberate stances — but the design's own counterweight (player-driven
   price impact) rarely triggers at shipped output volumes, and the grid half (power glut) is
   unbuilt. Net effect today: optimal play is schedule-following against a known curve, and every
   balance pass tunes numbers on top of a price system whose feedback loop is nominally present
   but practically dormant. Critical because CLAUDE.md names the trivially-solvable economy as the
   genre-killer, and because it silently compounds with W-E1: the squeeze currently overwhelms the
   player *and* fails to constrain the degenerate strategies it was designed to punish. The fix is
   tuning within the stance (impact thresholds vs volumes, grid glut), not a paradigm change.

3. **The repo's own docs instruct a data-destroying command (mechanics audit #4 — still open).**
   `CLAUDE.md` still says `recipes_all.csv` "is generated … edit the source, not the generated
   file," but `recipes_master_source.csv` is a *different data generation* (173/199 rows differ, no
   `required_research` column). One documented `build_recipes_all.py` run wipes the entire v4
   rebalance and all tech gates. Critical because the destroyer is the *documented workflow* —
   any collaborator or coding agent following instructions triggers it, and the v4 pass it would
   destroy is currently **uncommitted** (W-A6), making recovery genuinely painful. Quarantine the
   generator + master source and fix CLAUDE.md before anything else touches recipe data.

4. **Trust-destroying UI at the moment of crisis (W-U1, W-U2, W-U3).** The fake Expand-Storage
   button fires precisely when a new player is trapped in the storage deadlock; Lorem Ipsum fills
   the carbon-tax announcement that is the game's thematic centerpiece; the tutorial points at a
   dead Politics button. Individually small; critical in aggregate because they teach the player
   the UI cannot be trusted — and two of them sit on the new-player critical path of an EA build
   where first-session impressions decide reviews.

5. **The RAG profitability signal is wrong for the strategy the game is about (W-M3 + W-E5).**
   Self-powered chains show red on cash-profitable buildings; electronics chains blank entirely
   when the build-material loop closes. Critical because RAG is the primary steering instrument the
   UI offers, the carbon squeeze actively pushes players toward exactly the self-powered
   configurations it misprices, and the same divergence contaminates the design-model↔engine
   agreement (W-E2) the balance process depends on.

6. **Silent data-layer failure while mid-rebalance (W-A3 + W-E4).** A typo in a goods name becomes
   an empty `good_id` with qty 0, a short row vanishes, 60 recipes are already silently filtered —
   and there is no load-time validation or integrity test, while the largest data edit in the
   project's history sits uncommitted in the working tree amid 380+ dirty/untracked generated
   files (W-A4) that bury the meaningful diffs. Critical as *process* risk: the probability of
   shipping a corrupted or unreviewable dataset in this exact window is high, and the failure mode
   is invisible by design.

**Not critical but close (fix soon):** loan interest booking (W-M7 — systematically wrong money
reporting + tax shield; one-line fix exists in LoanState), the power-cap zero-output cliff (W-M4),
and mixed-manifest sell quotes (W-M6).

---

## 6. Status of `mechanics_audit_2026-07.md` findings in this checkout

Verified against `rebalancing-v4` working tree, 13 Jul 2026:

| Finding (July audit) | Status now |
|---|---|
| #1 Upgrade-rebate cancel pump | **Fixed** (`match_state.gd:1110` — no-kit no-rebate closes the pump) |
| #2 Glut/price impact never applied | **Fixed** — live accumulated impact in `MarketState` (`market_state.gd:124-138`) + buy-side mirror |
| #3 Mid-resolution load corruption | **Fixed** (`save_load.gd:158,183-188`) |
| #4 Recipe generator wipes rebalance | **Open** — files present, CLAUDE.md still instructs the workflow (Critical #3 above) |
| #5 Search overlay research bypass | **Fixed** (`search_overlay.gd:493-539`) |
| #6 Labour slider free −20% | **Fixed** — `tick_labour_output_pressure` (`match_state.gd:4117`) |
| #8 Loan principal booked as interest | **Open** (`production.gd:528`) |
| #10 Demolish is a no-op | **Fixed** — multi-turn demolish with cancel shipped |
| No bankruptcy enforcement (§1) | **Partly fixed** — SolvencyState exists but is headless-disabled; `BANKRUPTCY_FLOOR` still a dead constant |
| #16 Infra upgrades zero effect | **Fixed** (completion writes tile `infrastructure_levels`) |

Other entries in the July audit were not individually re-verified; treat unlisted items as
unknown-status rather than fixed.

---

## 7. Recommended order of attack

1. **Quarantine the generator** (delete/move `build_recipes_all.py` + `recipes_master_source.csv`,
   correct CLAUDE.md) and **commit the v4 pass** — eliminates the two data-loss windows in one
   sitting. Fix CSV import pollution (`keep` importer + gitignore `reports/`) in the same commit so
   future data diffs are reviewable.
2. **Add the ~50-line data-integrity test** (recipes↔goods↔buildings↔research referential check,
   loud `push_error` in `catalog.gd` on dangling refs) — converts the silent-failure class into a
   checklist.
3. **Enable SolvencyState under headless (flag-controlled) and put a bankruptcy check into the e2e
   scorecard** — makes the financing wall measurable, then attack W-E1 with the capital-cost lever
   the v4 report already proposes.
4. **The dead-UI sweep**: wire or visibly disable the capacity-dialog buttons, replace Lorem Ipsum,
   hide/disable Politics (N), align the tutorial-intro promises with shipped steps. Small diffs,
   outsized trust return.
5. **Fix RAG power imputation** (net-of-own-generation at the network level) and use the freed
   agreement to close the design↔engine gap before the next balance iteration.
6. Then the structural items on their own tracks: make the price-impact counterweight actually
   bind (retune `GLUT_UNITS`/bands against real output volumes, build grid-oversupply glut — both
   *within* the deliberate decay stance; mean-reversion is an explicit regression smell per
   `cnc-design-intent`), god-object decomposition of `match_state.gd`, v1 panel retirement.
