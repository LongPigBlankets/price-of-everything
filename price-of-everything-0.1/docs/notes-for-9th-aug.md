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
**Current state:** reverted, renders in full, does NOT scroll, and is 1117 px tall on a 1080p
screen so the bottom rows are off-display. The original complaint is unfixed.

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

## Open — reported by the owner, not yet investigated

- **Andrew's departure notice was never seen.** He vanished from the council with no message.
  The farewell is an `EventScheduler.emit_event` in `DecisionState._retire_founder`; whether it
  reaches the bell/briefing surface is unverified. Note the tenure bug (failure 3) means the
  observed disappearance may have come from a different path entirely — worth reproducing on the
  fixed build before chasing the notice.
- **Red rows in the advisor bonuses table were unexplained.** The effect column read "applied
  while seated" for every row, so a red row gave no reason. It now shows the signed percentage,
  and the heading is 20 px off-white instead of faint navy. Not yet seen in an image.

## Open — known work, not started

- **Money panel scroll (scene-level).** Add the `ScrollContainer` to `main.tscn` under
  `Balance/MarginContainer` with real anchors and repoint the panel's several dozen `@onready`
  paths through it. Do NOT attempt another runtime reparent.
- **Infrastructure upgrades.** Owner reports level 2/3 roads, pipes, reinforced pipes and rails
  cannot be upgraded to. `TRANSPORT_LINK_CAP_BY_MODE_LEVEL` carries per-level capacities (rail
  600/1200/2000) and `infra_upgrades` appears in e2e output, so some path exists. Unverified:
  whether per-level COSTS exist in `infrastructure.csv` / the buildings CSV, and where the
  upgrade action is gated in the UI. Needs a proper read before estimating.
- **Fluids by road and rail (P5).** Specced, never built. `Catalog.requires_pipeline()` still
  hard-gates, which is why water and hydrogen cannot ship without pipework. Also retires the
  `INF_TURNS` unreachable class.
- **Goods-graph transport icons** (P5), and the **distribution split** (P6, next full export).
- **Screenshot pass** over everything from this session: advisor bonuses table, credit dialog in
  the real flow, building-detail debt and stored-units rows, research panel rows.
- **Code.gs redeploy** with a fresh `turns` tab before any telemetry from this build is read.
  The freight split is now SIX values (`sea` was removed).

## Open questions still in the spec (§9)

Ghost holding scope confirmed; auto-sale retired. Remaining: the CFO gift principal is fixed at
£200 (confirmed), whether the second seat is hireable during Andrew's tenure, and whether
`balance.py` needs to know about the idle-pay policy (§8.8 audit).
