# Notes — 9 August 2026

Branch `easier-onboarding-and-mandatory-advisor`. Everything below is the state at the end of
the day: what shipped, what broke, what is still open. Written to be read cold.

---

## What shipped (P1 → P3, plus the freight redesign)

**P1 — early-game kindness.** Tutorial rescue (3× to £2500 with escalating copy, then real
bankruptcy). Marginal £20 tax/dividend floor. Build-forecast preview in the construct panel
(four phases: Building / Completes / Making-not-yet-paid / Selling, plus what it costs to reach
the first sale). metal_magnate pre-set to 1.2× overtime at max output momentum. Telemetry
schema 3.

**Freight redesign.** Port charging is ad valorem only — 0.5% to t30, 3% from t31, owned ports
half. The flat per-good fee is retired (`SEAPORT_BASE_FEE_PER_GOOD` = 0.0) because it was
charged per GOOD per turn, making quantity free: freight fell from 11.3% of revenue to 0.3% as
an empire grew. Logistics shipping line wired: Groupage Contracts → Multimodal Containerized
Freight → Port Network Acquisition, −10/−10/−20% RELATIVE, so a fully teched company pays 1.8%
against the scheduled 3%. Depot Scheduling re-pointed to −10% road and rail. Freight credit
(COO gift) spends on land legs only.

**P2 — advisors.** CFO and COO are the only seats until Executive Search (People Management II,
run 5 buildings profitably for 10 turns). Andrew Keeler arrives turn 3 in every sandbox match,
pro bono for 30 turns, in one of the two chairs; CFO brings a £200 loan at 5%, COO brings 1000
units of domestic freight plus −20% transport. Unfireable during his tenure, leaves at t33.

**P3 — expansion economics.** A BUILD gets the ramp financed (5-turn operational-loans tab,
12 interest-free slices or a loan, CFO-gated, with a construct-panel default setting). A
PURCHASE gets inventory seeded (2 turns of inputs, priced into the sale) with a ghost holding
for whatever will not fit. New labour policy: worker pay while not running (50/75/100).

**Tooling added:** `tools/transport_bands.py` (freight as a share of revenue, banded),
`tools/start_probe.gd` (run a shipped start headlessly and print its economics),
`tools/money_panel_shot.gd`, `tools/construct_settings_shot.gd`, `tools/credit_facility_shot.gd`.

Unit suite 2007 passing, e2e 748 passing.

---

## Failures — what I got wrong today, and why

These are recorded because the pattern matters more than the individual bugs.

**1. The money panel. Four attempts, still broken, and I shipped it blank twice.**
The Balance tab rendered EMPTY from commit `7e2d0412` — the commit whose message said it was
fixed. I "verified" that one by printing `fits_screen=true, scrolls=true` and never looked at
the image. The owner found it, I reverted, then broke it the same way again.
What is actually known: a runtime reparent of `BalanceContent` into a `ScrollContainer` empties
the tab, whatever the surrounding numbers. The sizing can be made exactly right (120 px bottom
gap, content 939 in a 783 tab, scrollbar present) and it still draws nothing.
**FIXED (scene-level, later the same day).** The blank tab was never the reparent as such — it
was `Balance/MarginContainer` not expanding. A `ScrollContainer`'s minimum height is ZERO, so the
moment the sheet went behind one, that MarginContainer (no `size_flags_vertical`, sitting in a
VBoxContainer) shrank to its minimum and gave the scroll a viewport 0 px tall. Every number the
old diagnostics printed stayed true — the sheet really was 939 px in a 783 px tab — because they
measured the CONTENT and the TAB and never the scroll's own height. `BalanceScroll` now lives in
`money_panel.tscn` with the MarginContainer set to expand, and the several dozen `@onready` paths
point through it. `_balance_panel_height()` gives the panel a height of its own (the sheet's, capped
to what fits below its top edge), since behind a scroll nothing else asks for one.
**Measured at 1920×1080:** panel 560×896, bottom gap 90, scroll viewport 718 showing a 939 sheet,
scrollbar present, scrolls 221 px to Dividends / Profit Sharing / Net Cash Flow. Both ends shot.

**2. Three bugs from adding to a system without checking every reader of it.**
- Andrew crashed the advisors tab: added to `ADVISOR_ROSTER` but not to the presentation table
  keyed by advisor id (initials/portrait/bio/agenda), which every reader assumes exists.
- His offer read "No direct effect": the three new effect kinds were wired into the effects
  ENGINE but not the describe pass.
- The port import/export lines read £0 forever: I split the charge as flat-fee-by-direction plus
  ad valorem on a separate line, then the flat fee was retired to zero.

**3. Andrew was immortal.** `founder_tenure_expired()` returns true once the turn arrives, so
the guard `not expired and turn >= leaves_turn` could never both hold. Fixed.

**4. The turn-3 offer never fired.** Booked as a reservation in `DecisionState.reset()`, which
`import_state({})` then cleared microseconds later on every new game. This was the THIRD
teardown-ordering bug of the session (after the telemetry ruleset clobber and the latched run
fields). Anything seeded during `reset()` must survive an import that runs straight after.

**5. The credit facility was offered for infrastructure.** Rail has no recipe and so no start-up
costs to carry. Fixed by gating on the project's recipe having inputs.

**The through-line:** the unit suite is structurally blind to UI and content. 2000 assertions
passed while the balance sheet was blank. Every UI change from here needs an image before it is
called done — the shot tools above exist for exactly that and each one caught a real failure the
moment it was used.

---

## Closed since — with an image each

- **Andrew's departure is now a blocking notice.** The bell entry was reaching the surface all
  along; a bell entry is just missable, and it was missed. `_retire_founder` now also draws a
  `founder_departs` decision — the same single-choice "Understood" shape as the government
  notices, `PRIORITY_STORY` so it stays out of the random pool. The Briefing auto-expands on an
  unresolved decision and End Turn is blocked until he is thanked. Retirement is held while the
  board is full (4 pending) so the farewell can never be dropped. Verified with
  `tools/founder_departs_shot.gd`, which plays the real arc: answer the turn-3 offer as COO,
  stand on turn 34, commit — seat empties, notice presents at 35, End Turn blocked.
- **Single-choice notices no longer bury their button.** `CHOICE_MIN_H` (300 px, there to keep
  side-by-side choice columns level) was applied to one-choice cards too, so the only CTA sat
  200 px below the text, past the fold and clipped. Content-sized now when there is one choice;
  the two- and three-choice cards keep the uniform height. Fixes the carbon/subsidy notices too.
- **Advisor bonuses table — seen in an image at last** (`tools/advisor_shot.gd`, which was itself
  broken: it drove a `people_panel._open_advisor_detail` that no longer exists and selected tab 1,
  which is Labour). The heading reads at 20 px `#E9F1FA`, and the rows carry the signed percentage
  in green/red — "Loan Interest −25%" green, correctly, because a cost coming down is good.
  Still weak: the table body is 12 px and its Bonus/Effect captions 11 px in dim navy, noticeably
  fainter and smaller than everything around them.

- **The money panel's two arithmetic bugs, both measured.**
  *Transport was missing from the Costs chart entirely* — `_record_chart_history` never wrote a
  `transport` key (its comment said "transport is excluded") and `money_chart.COST_SERIES` had no
  such band, so the chart understated every turn by the whole freight bill, the largest cost a
  grown empire has. Warehousing and advisor salaries were missing the same way. All three now
  recorded and charted.
  *The Balance tab's net disagreed with the top bar and the mini-panel*, which both read
  `money_in − money_out`. Two causes, found by reconciling the two figures turn by turn across a
  100-turn e2e: **advisor salaries** moved cash with no row on the sheet at all, and **building
  tabs** — running costs carried, not paid — were charged to the sheet in full while `money_out`
  excluded them (the sheet showed only the outstanding debt, on a row outside the totals). Gap
  was £1,844 on one turn of a tabbed build-out. The sheet now carries an "Advisor salaries" row
  and credits "Deferred to building tabs" (outstanding total moved to its tooltip), and
  `production.gd` records `building_tab_carried`. Re-measured: exact reconciliation on all 100
  turns with 61 tabs open and a salaried advisor.
  Guarded by `_test_balance_sheet_reconciles_with_cash` — a real committed turn asserted against
  the cash delta, since 2,000 assertions never noticed because nothing compared the two.

- **Fluids by road and rail — BUILT** (`docs/fluids-overland-spec.md`). Rail 3x/5x and road
  6x/10x against the pipe cost, hazard split preserved. Pipes are still chosen first, explicitly,
  so the change is strictly additive: the e2e's headline metrics are identical before and after.
  `INF_TURNS` was NOT retired — a fluid with no link at all is still stranded, which is what keeps
  the unreachable-cost guard meaningful. Port logistics is the part that wants a playtest.

## Open — known work, not started

- **Infrastructure upgrades.** Owner reports level 2/3 roads, pipes, reinforced pipes and rails
  cannot be upgraded to. `TRANSPORT_LINK_CAP_BY_MODE_LEVEL` carries per-level capacities (rail
  600/1200/2000) and `infra_upgrades` appears in e2e output, so some path exists. Unverified:
  whether per-level COSTS exist in `infrastructure.csv` / the buildings CSV, and where the
  upgrade action is gated in the UI. Needs a proper read before estimating.
- **Goods-graph transport icons** (P5), and the **distribution split** (P6, next full export).
- **Screenshot pass** — remaining: credit dialog in the real flow, building-detail debt and
  stored-units rows, research panel rows. (Advisor bonuses table done, above.)
- **Code.gs redeploy** with a fresh `turns` tab before any telemetry from this build is read.
  The freight split is now SIX values (`sea` was removed).
- **A silent `add_child` failure, somewhere.** Every run — including the headless e2e — prints
  "Parent node is busy setting up children, `add_child()` failed" followed by "Child is not a
  child of this node" from `move_child`. That is the add-then-move-child idiom failing, so some
  row is being built and dropped. Not the money panel (all its inserted rows render);
  `building_detail_panel.gd` uses that idiom in a dozen places and is the first place to look.
  Pre-dates today's work.

## Open questions still in the spec (§9)

Ghost holding scope confirmed; auto-sale retired. Remaining: the CFO gift principal is fixed at
£200 (confirmed), whether the second seat is hireable during Andrew's tenure, and whether
`balance.py` needs to know about the idle-pay policy (§8.8 audit).
