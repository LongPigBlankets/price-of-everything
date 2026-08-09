# Early-Game Onboarding & Kindness — Design Spec

*v2, 2026-08-09 — updated after the owner's second review round (Andrew Keeler, the
5-turn tab, CFO gating, era turns 31/33, goods-graph transport icons). Owner rulings
are **LOCKED**; my proposed defaults are *(proposed)*; unresolved items in §9.*

---

## 1. Evidence & problem statement

One Linux tester, 53 minutes, five runs (telemetry sheet, 2026-08-08, player
`d7dacab6…`):

- 4 of 5 runs net-negative; best run's profit **decayed +27 → 0** over 34 turns while
  buildings went 5 → 14.
- **Expansion is punished**: doubling the ingot line turned +27/turn into −106/turn in
  one turn (power + input costs land before output sells; revenue even *fell* under
  glut).
- **The tutorial bankrupted the player** (t25, second attempt): £2500 start burns
  −£240/turn at £0 revenue until the first sale step (~26 of 45).
- Loans accelerate the spiral: auto-bridge escalated 20 → 53 → 102 → 153 over four
  turns of worsening profit.

**Diagnosis.** The early game is *asymmetric*: a correct action earns +£10–30/turn
while a single wrong build costs −£50–250/turn — and learning requires probing the
loss surface. Starting cash is not the lever (the tutorial's £2500 still died);
**bleed rate while thinking** is. Most difficulty levers are *flat* fees, and flat
fees are regressive — every flat midgame brake doubles as an early-game hammer.

## 2. Design principles

1. **Kindness must dilute with scale** (grace windows, tax floors, starter kits, tabs).
2. **Brakes must engage with scale.** No new flat costs, ever.
3. **The anti-raw lever rotates by era**: t1–30 nothing (learning) → t33–110 port flat
   fee (climb-the-chain squeeze) → t110+ depletion + carbon levy.
4. **Costs stay legible.** Deferred or auto-financed costs keep a visible panel row.
5. **Cap the cost of mistakes; do not raise the reward of success.**

---

## 3. Tutorial rescue — **LOCKED**

Tutorial runs only (`ruleset.tutorial_enabled`).

- End of PROCESS, if `money < 0`: reset to **£2500** (always exactly £2500 —
  confirmed), increment `rescue_count`, popup (coach-overlay *annotate*, non-blocking):
  1. "**The tutorial is feeling kind**"
  2. "**You're testing the tutorial's kindness**"
  3. "**Last chance. Don't waste it**"
- After the third rescue: no more rescues; bankruptcy may genuinely fire.
- Victory disabled for tutorial runs.
- Rescue #3 *(proposed)* names the concrete fix ("check what the factory is buying
  each turn").
- Telemetry: `rescues` on the `-T` envelope (§7).

## 4. Market & fees timeline

### 4.1 Calm market era, t1–30 — **LOCKED**

- Turns 1–30: prices **frozen** — no `decay_rate` drift, no glut/deficit impact,
  both directions. Guards at the two `market_state.gd` sites (`decay_live` switch;
  `price_impact_rate`).
- **Prices float from t31, and the decay clock STARTS at t31** — **LOCKED**: decay is
  applied incrementally from the frozen price, never precomputed from t1 (no
  30-turns-of-decay cliff on unfreeze). §8 probe asserts
  `price(t31) = price(t1) × (1 − decay)`, not `× (1 − decay)^31`. Same rule for the
  seaport fee growth (indexed from its own start turn, §4.2).
- ~t28 bell notice: *"Your father's long-term contracts expire. From turn 31, the
  markets float."*

### 4.2 Port fee era, t33–110 — **LOCKED**

- **t1–32:** no flat seaport fee; ad valorem insurance only (0.05% / owned 0.025%).
- **t33** *(tied to the advisor: Andrew's 30-turn tenure from t3 ends here, §5.4)*:
  event — *"The National Port Authority introduces export and import fees to
  strengthen national resource independence."* Flat fee at
  `SEAPORT_BASE_FEE_PER_GOOD` (£5/good/turn), growth indexed from t33.
- **t110:** event; flat fee removed, ad valorem only. Depletion + carbon levy own the
  anti-raw job from here (§8 verifies, not assumes).
- Fee keeps its `Modifiers` wrap (`port_per_turn_fee`).

### 4.3 Tax & dividend floor — **LOCKED**

Marginal, both lines: `take = rate × max(0, profit − 20)` per turn, applied after the
CFO carry-forward. £25 profit → take £2; £100 → take £32 (keep £68 vs £60 today).

## 5. Expansion economics

### 5.1 Build-time margin preview + trajectory chart — **LOCKED**

In the construct panel on recipe selection:

- DS mini-chart, ~10 turns of per-turn net at current prices, **break-even marker**
  ("pays back ~t9").
- **Visual style — LOCKED**: **5px-thick line segments** — **grey** for the
  construction turns, **red** while net is negative, **green** while positive — each
  with a **more-transparent same-colour fill** between line and zero axis
  (below the line for losses, above-axis area for gains). Hammer icons across the
  construction span.
- Assumptions caption: *sells direct to market · pipes/reinforced pipes assumed
  built*. Single-good `quote_market_sell` for the port leg; steady margin from
  CostSolver. Kit-aware (§5.2): the dip starts ~2 turns later and shallower.
- Red inline warning when the tile has no input supply ("projected −£X/turn: no ore
  supply on this tile").

### 5.2 Starter kit + dearer buildings — **LOCKED**

- Constructing a building: capex += **market value of 2 turns of its recipe inputs**,
  **no premium** (exact market prices — confirmed).
- **With COO-Andrew seated: 3 turns of inputs at the 2-turn price** (§5.4) — the extra
  turn is his gift, not a capex increase.
- The kit **materialises in the tile stockpile, claim-reserved** for this building
  (reuse the construction-materials claim so co-located consumers / sell-all-surplus
  cannot consume or flog it).
- **Capacity edge case — LOCKED**: if the tile stockpile is full / short of room,
  **log it** (expected rare). *(proposed)* fallback: a **ghost holding** — visible to
  the player, not usable — that feeds only this building until room frees; verify
  against warehouse-capacity rules at impl.
- **Buildings only — nothing for infra.** NPC-bought buildings inherit their existing
  stock instead; no kit.

### 5.3 Building operational loans — **LOCKED** (simplified 5-turn form)

Per newly *constructed* building (not NPC purchases, **never infrastructure**).
Construct-panel setting, enabled by default. **Requires a seated CFO — any CFO**
(§5.4); with no CFO there is no popup and no rollup — costs hit cash as today.

- **Popup at completion−1** (the building is 1 turn from finishing; inputs start
  sourcing now), titled **"Building operational loans"**.
- **Scope — simplified**: the building's running costs for **the next 5 turns only**
  are rolled into a loan. Attribution per line — **LOCKED**:

| line | rule |
|---|---|
| inputs | synthetic: recipe inputs × qty × market price, per turn it attempts to run |
| power | own-network generation free; **grid-imported deficit share** of the building's energy requirement is rolled |
| labour | the building's own labour line (at the §5.6 policy rate when starving) |
| maintenance | the building's own maintenance line |

- **The choice is made on the popup, upfront**: repay in **12 interest-free slices**
  (one/turn, loan_payments phase, starting when the 5-turn window closes) **or** as a
  **regular 48-turn loan** at standard interest. *(flag: this introduces a 48-turn
  term alongside today's `TERM_TURNS = 36` — deliberate? see §9.)*
- Bounded by construction: exposure is exactly 5 turns of burn. **No cap, no
  auto-sale** — both retired with the open-ended accrual that needed them.
- Popups auto-suppress after **2 buildings** (suppressed default = 12 slices); the
  panel rows never disappear:
  - Building Details: **"Building debt"** row (balance / slices remaining).
  - Money panel: **"Building operational loans"** row (sum across buildings).
- Save: per-building key (window turns left, accrued, repayment mode, slices left);
  `schema_version` bump + migration (absent key = no tab).

### 5.4 Advisors: CFO/COO + Andrew Keeler — **LOCKED**

- At game start only **CFO and COO** seats exist; all other roles disabled.
- **Turn 3, always** (sandbox starts; suppressed under `tutorial_enabled`): a
  DecisionState event shows **both advisor roles** and the family friend —
  **Andrew Keeler** — offering to fill **one**. His line, verbatim:
  *"I've negotiated lots of deals with suppliers and banks in the past. But my
  specialty will always be transporting goods cheap."*
- **The benefits are shown per post in a scrollable accordion** — each seat expands
  to list exactly what it grants:
  - **CFO** (30-turn tenure): **Distressed Asset Program** gate, the existing
    **tax-loss carry-forward**, and **Building operational loans** (§5.3).
    **Signing gift — LOCKED**: a single **£200** loan at **5% interest** over the
    standard 48-turn life (12 grace + 36 repayment). Implementation note: the rate
    rides the existing `loan_interest` CFO modifier hook in
    `effective_loan_interest_rate()` (−50% → 5%), and `CONSTRUCTION_LOAN_RATE` is
    already 0.05, so 5% has precedent.
  - **COO** (30-turn tenure) — **LOCKED**:
    - **Signing gift: 1000 units of free DOMESTIC freight** — inland road/rail
      haulage, **not** port throughput (ports are fee-free until t33 anyway, so a
      port credit in this window would be worth nothing).
    - **Ongoing: −20% transport costs** for his whole tenure (t3 → t33). One-line
      hook: `Modifiers.apply("transport_cost", …)` already exists at
      `transport_service.gd:80`.
    - **Ongoing: starter kits carry 3 turns of inputs instead of 2, at the 2-turn
      price** (§5.2) — one free turn of inputs per new building.
      *(Ambiguity flagged: read as newly CONSTRUCTED buildings' kit. If it was meant
      as NPC-bought buildings receiving a 3-turn kit, say so — those currently
      inherit stock and get no kit at all.)*
- **Andrew actually joins and is not fireable** during his 30 turns (**t3 → t33**;
  "leaves at turn 30" = the 30-turn tenure, which from t3 lands on t33). His
  departure coincides with the Port Authority event (§4.2) — farewell and squeeze are
  one narrative beat.
- After his tenure: farewell event, seat opens for a normal hire. The *other* of the
  two seats is hireable normally from the start *(assumption — confirm)*.
- **Strategic consequence (deliberate)**: picking COO-Andrew means cheap freight but
  **no ramp financing** until a CFO is hired — the t3 choice is real.
- **Remaining seats** unlock via a **people/labour research node** gated on
  **5 buildings running profitably** — profitability = **the existing
  research-condition definition** (output cheaper than market, imputed ≤99%, NOT the
  RAG-green ≤90% bar), sustained for the same streak length other research conditions
  use (`_profitable_run_streaks`).

### 5.5 metal_magnate pre-sets — **LOCKED**

Start-config data only:
1. The **1.2× labour cost policy** enabled with its output modifier already at max cap.
2. The new §5.6 policy enabled at **50%**.
No other policy changes — the rest of the people panel stays a discovery.

### 5.6 New labour policy: "Worker pay while building not running" — **LOCKED** (later phase)

- A people-panel policy with **three settings: 50% / 75% / 100%** (default 100% =
  today's behaviour).
- **Wired for real**: any turn a building starves / fails to run (including startup),
  its labour line is paid at the policy rate.
- metal_magnate ships at **50%** (§5.5).
- **Interaction audit required at impl** (owner-flagged): CostSolver imputed-cost
  labour line, `tools/balance.py` offline model, e2e baseline expectations, the §5.3
  tab's labour attribution (a starving ramp at 50% pay halves that line), the
  labour-headcount unlock modifiers, and the §7 cost-breakdown telemetry. Exploit
  check: 50% pay for zero output is still pure loss — no idle-farming vector, but
  verify the profitable-streak detectors don't misread it.

## 6. Fluids by road & rail — **LOCKED** (shape), multipliers swept

`Catalog.requires_pipeline()` demotes from hard gate to *preference*:

- Liquids/hazard liquids by **road** (~×3–4 tanker premium) and **rail** (~×2–3);
  **gas** dearest by road (~×5). **Pipes stay cheapest.** Retires the
  `INF_TURNS`-sentinel unreachable class. Seaport restricted-class throughput
  unchanged. Tutorial glass-pipe copy tweaked (pipe = the margin play, not the gate).

**Goods-graph transport icons — LOCKED**: when a good is **selected** (selected good
only), its card **extends sideways** to fit transport icons:
- Pipe / reinforced-pipe goods: the one icon; hover — *"cheapest transport method is
  [infrastructure for that good type]"*.
- Road/rail-only goods: **two icons side by side**; hover — *"good can only travel by
  road or rail"*.

## 7. Telemetry schema 3 — **LOCKED**

Client `SCHEMA_VERSION` 2 → 3; `Code.gs` turns-tab `FIXED` extended; runs tab gains
`start`. Sheet-side: fresh turns tab / new spreadsheet (rotation policy), not header
migration.

New fields:

- `run.start` — start-scenario id (had to be fingerprinted from t1 production this
  week).
- `rescues` (int) — §3, `-T` runs.
- `cheats_used` (sticky bool) — unflagged cheat runs poison aggregates.
- `buildings_list` — per-turn array, one entry per owned building: **`name(lN)`**
  (e.g. `furnace(l2)`); pipe-joined in the sheet.
- `building_states` — index-aligned array: running or the starving reason
  *(enum verified against the starvation report at impl)*:
  `running | starting | construction | no_power | missing_inputs | no_labour | paused`.
- **`costs` — per-turn cost-breakdown array for diagnosis** — **LOCKED**: pipe-joined
  `name:value` (like `goods`), lines matched to the engine's money_out components at
  impl — e.g. `inputs:120|transport:15|labour:40|maintenance:22|loans:10|tax:8|power:5`.
  (money_out already includes tax/dividends at emission — the breakdown must sum to
  it, not double-count.)

Perf: arrays scale with building count — stay inside the 0.5 ms/turn capture budget
and the 50k-char cell cap (assert at 500+ buildings).

## 8. Verification — harness probes (all pre-merge)

1. **Raw-only, tri-window**: t1–30 at most mildly cash-positive (ceiling swept);
   **unprofitable t33–110**; still unattractive t110+ under depletion + carbon.
2. **Idle-start probe**: every shipped start, idle 15 turns, then play reasonably →
   never bankrupt or unrecoverable.
3. **Decay-clock probe**: `price(t31) = price(t1) × (1 − decay)` — no precompute
   cliff; port-fee growth likewise indexes from t33.
4. **Expansion e2e**: magnate + one new consumer building, CFO seated → kit claim
   honoured; tab rolls exactly 5 turns per §5.3 attribution; slices/48t both paths
   deterministic. No-CFO control: no popup, costs hit cash.
5. **Tax floor**: £25 / £100 arithmetic per §4.3; carry-forward ordering.
6. **Era sweep**: calm era t1–30 + fees t33–110 with the t31/t33 stagger; report
   outcome curves.
7. **Gift valuation**: price the COO package (1000 domestic freight units + −20%
   transport for 30 turns + one free kit-turn per build) against the CFO package
   (£200 @5%, DAP, carry-forward, operational loans) over t3–t33; report the
   asymmetry (owner judges — parity not required, but the choice must not be
   obviously one-sided).
8. **Labour-policy audit** (§5.6): CostSolver / balance.py / e2e / tab / streak
   detectors under 50% starve-pay.
9. **Fluids premium sweep**: pipe strictly cheapest at all distances; no route
   returns `INF_TURNS`.
10. Determinism, save round-trip + migrations (tab key, policy), unit + e2e green,
    telemetry capture ≤0.5 ms at 500+ buildings.

## 9. Open questions (owner)

1. Ghost holding (§5.2): log-only first, or build the visible-locked holding now?
2. During Andrew's tenure, is the **other** seat hireable immediately (current
   assumption: yes)?
3. **Orphan found — needs a ruling.** `loan_state.gd` already has
   **construction-on-credit** (`CONSTRUCTION_LOAN_TERM = 10`,
   `CONSTRUCTION_LOAN_RATE = 0.05`) unlocked by a **Chief Investment advisor**. §5.4
   disables every seat except CFO/COO, so that feature becomes **unreachable** until
   the research node opens seats. Options: (a) leave it dormant — it returns when
   seats unlock; (b) fold construction-on-credit into the CFO package; (c) retire it
   as superseded by the operational-loans tab. It also overlaps the tab conceptually
   (both finance a build), so (b) risks two competing build-financing paths.
4. **Is 1000 domestic freight units the right size?** For scale: the tester's
   metal_magnate runs moved roughly 150–250 units/turn — 1000 units ≈ 4–6 turns of
   total haulage, spent well before Andrew leaves at t33. Fine if it's meant as an
   opening cushion; say so if it should instead last the tenure.

*(Resolved this round: CFO gift = **£200 at 5%** · **48 turns confirmed correct** — it
is the standard loan life, `LOAN_GRACE_TURNS 12 + LOAN_TERM_TURNS 36`, verified in
`economy_config.gd:374,383`; no new term is being introduced anywhere · COO gift =
**1000 units domestic freight, not port** · COO ongoing = **−20% transport costs**
+ **3-turn kits at the 2-turn price** · departure t33.)*

*(Resolved previously: port fees t33 / prices float t31 · trigger t3 always ·
profitability = research definition ≤99% · auto-sale retired with the 5-turn tab ·
slices CFO-gated · kit at exact market value, no premium · rescue always to £2500.)*

## 10. Constants touched (rule-7 ledger — nothing lands without sign-off)

| constant / data | change |
|---|---|
| `TAX_RATE`, `DIVIDEND_RATE` application | marginal floor at £20/turn (rates unchanged) |
| `SEAPORT_BASE_FEE_PER_GOOD` | unchanged value; **active only t33–110**, growth indexed from t33 |
| `decay_rate` columns / price impact | suppressed t1–30; decay clock starts t31 (no precompute) |
| building capex | += 2-turn input kit at exact market value (no premium) |
| transport class costs | new road/rail carriage multipliers for liquid/hazard/gas |
| tab terms | 5-turn rollup; 12 slices @0% (CFO-gated) or the **standard loan** (12 grace + 36 repay = 48 life) |
| CFO signing gift | £200 principal at 5% (half `LOAN_INTEREST_RATE`, via the existing `loan_interest` modifier) — **no new loan term** |
| COO signing gift + tenure | 1000 units domestic freight; −20% `transport_cost` modifier; 3-turn kits at 2-turn price (t3–t33) |
| labour policy | new "pay while not running" 50/75/100 (default 100 = today) |
| metal_magnate start config | 1.2× labour policy @ max output cap + not-running pay @50% |
| tutorial | rescue floor £2500 ×3 |

## 11. Implementation phases (v2 — advisors moved ahead of the tab, which is CFO-gated)

- **P1 — self-contained, no balance constants**: tutorial rescue (+`rescues`), build
  preview + trajectory chart (§5.1 colours), tax/dividend floor, magnate **1.2×
  labour pre-set only** (the §5.6 policy doesn't exist yet), telemetry schema 3
  **including the `costs` breakdown**.
- **P2 — advisors**: CFO/COO-only seats, the t3 Andrew Keeler event (accordion UI,
  verbatim line), unfireable 30-turn tenure, signing gifts (5%/48t loan · 500-unit
  freight credit), farewell at t33, seat-unlock research node (research-standard
  profitability ×streak). *Must precede the tab: §5.3 is CFO-gated and dead code
  until a CFO can exist.*
- **P3 — expansion economics**: starter kit (exact market value, claim-reserved,
  capacity log/ghost holding) + the 5-turn operational-loans tab (completion−1
  popup, slices/48t, rows, save key + migration) + **§5.6 labour policy** with the
  magnate 50% pre-set and the §8.8 interaction audit (deferred here per owner: "one
  of the later phases", and it directly feeds the tab's labour line).
- **P4 — era timing**: calm era t1–30 with the t31 decay-clock start, port fees
  t33–110 tied to Andrew's departure, both diegetic notices; ships only with the §8
  sweep attached.
- **P5 — transport**: fluids by road/rail + goods-graph transport icons + tutorial
  copy tweak.
- **P6 — distribution split (LAST, next full export)**: §12. No retroactive patching
  of shipped builds — the July Linux tester re-downloads once; the scheme applies
  going forward.

Each phase: unit suite → e2e → (UI) screenshot, per the standard loop.

---

## 12. Distribution: split packs & patch pipeline — **LOCKED** (lands last, next export)

Today's Linux build is a single ~700MB executable with the PCK embedded. Going
forward, four artifacts:

| artifact | contents | ~size | changes when |
|---|---|---|---|
| `carbon.x86_64` (etc.) | engine template, `embed_pck=false` | ~80MB | Godot version bumps |
| `assets.pck` | `res://assets/**` — icons, banners, audio, video | ~550–600MB | art/music lands |
| `game.pck` (main pck) | scripts, scenes, UI glue, **fonts** | ~30–60MB | every code build |
| `data.pck` | `res://data/**` — CSVs, starts, ruleset | <1MB | every balance pass |

**Mechanics.** Three export presets with **disjoint** filters; a **`PackLoader`
autoload inserted FIRST (above `DS`)** mounts `assets.pck`, `data.pck`, then
`patches/*.pck` sorted, via `ProjectSettings.load_resource_pack()`.

**Rules.** (1) Nothing before the mounts may touch `assets/`/`data/` paths — fonts
live in `game.pck` so the error dialog can render. (2) **Fail loudly on skew**:
per-pack version manifest; missing/mismatched → readable dialog + quit; telemetry
`client.version` becomes the tuple. (3) **Filter-drift guard**: export script asserts
`game.pck` under a size ceiling. (4) Hotfixes via Godot's native **export-as-patch**
(the preset `patch_delta_*` fields) → KB-sized `patches/*.pck`.

**Consequences.** Balance pass = `data.pck` (KBs); code build = `game.pck` (tens of
MB); 700MB moves only when art does. The itch **demo ruleset becomes a `data.pck`
variant**. macOS caveat: external packs break the signing seal — single-file there,
or accept the unsigned-tester dance. Butler/itch-app remains the launch channel.
