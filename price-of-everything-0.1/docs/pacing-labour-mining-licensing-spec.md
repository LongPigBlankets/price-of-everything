# Pacing, Labour, Mining and Licensing — Design Spec

*v3, 25 October 2026. Written from the owner design thread of 24–25 October.*

*v3 owner rulings:*
- *Third licence rate is 8%; licence-out steps are 2.5% and 5%; each licence sold out lowers
  prices by 2%.*
- *The Magnate seam triples outside the demo.*
- *Finite seams keep the −30% penalty.*
- *The legacy perk is tied to the "Original Furnace".*
- *Strike pay raises; strikers paid at 50%.*
- *Factories use 20 land.*
- *The first licence price steps by era.*
- *Union Agreement: +15 satisfaction and a rising cost.*
- *v4: the Union Agreement splits into Partial (+15) and Comprehensive (+30, halves labour cost
  cuts).*
- *v5: satisfaction from workforce size (+5 above 5,000 workers, +5 more above 25,000) and from
  the HR Director (3 stars +5, 1 star −5).*
- *v6: an eighth knob, Work week (35 / 40 / 45 / 50 hours).*
- *v7:*
  - *Work week gains are cumulative and new games start at 45 hours.*
  - *Comprehensive halves only labour cuts gained after signing, and the halving outlives the
    union.*
  - *"Renege on Union Agreements" removes the halving for −50 satisfaction, instantly.*
  - *Satisfaction moves by max(10% of the gap, 2) a turn, and nothing else is instant.*
- *v8: stepping down a union tier costs 5% of revenue and a −15 satisfaction shift that decays
  0.5 a turn. Comprehensive to none counts double.*
- *Purchases cannot be cancelled.*
- *Andrew's Expansion package is set.*

*v2 owner rulings:*
- *Staffing starts when construction begins.*
- *Freight is priced by distance.*
- *Strikes cut output.*
- *Licences are charged on company revenue.*
- *Licence-out income is max(£50, 10%).*
- *Metal Magnate's demo seam stays at 2,000.*
- *Local Suppliers stay same turn.*

*Owner rulings are **LOCKED**. My defaults are *(proposed)*: every proposed number is a starting
point for the harness, not a ruling. Unresolved items are listed in §16. Nothing in this spec is
built.*

Covers:

- §3 Output and throughput, the two bonus types
- §4 Labour satisfaction, a new company metric, with its top bar and Labour tab UX
- §5 Staffing new and bought buildings
- §6 Strikes, with a new People tab
- §7 Pacing: construction, upgrades, recipe switching, buying, shipping
- §8 Mining: seam caps, over-cap costs, deposit sizes, the seam-running-out card
- §9 Larger mine footprint
- §10 Research licensing, in and out

Out of scope: §18.

---

## 1. Problem

The scouting pass of 24 October (main at `761259a7e`) found that turns 1–50 are a solo
optimisation puzzle with one binding constraint and one kind of purchase.

| Finding | Evidence |
|---|---|
| Cash is the only gate. Build time never binds | Metal Magnate starts with £300 and an authored steady profit of £16/turn. A kit costs £400 (mine) to £1,089 (assembly) at base prices. Every production building builds in 3 turns (CSV 2 + `BUILD_DURATION_BUMP` 1, `match_state.gd:781`) |
| Buying already beats building | NPC buildings are instant and priced at (materials + land) × 0.70–1.00 (`building_price.gd`) |
| Labour policies create free product | `workforce_output_multiplier` scales output (`production.gd:1028`) but never inputs (`production.gd:3112`). +15% output is +15% revenue at no input cost, about +45% profit at a 33% margin. Profit Share 10% therefore always wins |
| Policies have no commitment or risk | Every policy toggles instantly and for free (`labour_state.gd:201`). Lax Safety can be cycled |
| Finite seams are strictly worse | The −30% "exhausted deposits" penalty hits finite and endless seams alike (`modifier_state.gd:356`). Finite seams also end |
| Extraction per tile is unbounded | 8 level 1 mines fit on a rural tile today |
| Research is a checklist | 254 nodes, all unlock by doing, nothing excludes anything. 55 nodes plus about 18 mining-yield entries are flat output bonuses |

Metal Magnate benchmark (`reports/balance/balance_v4_motors_metal_magnate.json`, a scripted bot
that never borrows) used throughout this spec:

| Turn | Revenue/turn | Profit/turn | Margin | Buildings |
|---|---|---|---|---|
| 10 | £145 | £44 | 31% | 4–5 |
| 30 | £313 | £109 | 35% | 6 |
| 50 | £527 | £133 | 25% | ~12 |

## 2. Principles

1. **Time has a price, and the player sets it.** Satisfaction, temporary speed-ups and buying
   decide how fast a company grows. Waiting for cash alone is not a decision.
2. **Growth is physical.** More output comes from more capacity, better recipes and throughput.
   Output bonuses are rare.
3. **Deep pushes need modifiers.** Over-cap extraction and stacked labour boosts lose money
   unless labour and maintenance modifiers have been earned.
4. **No new flat costs** (early-game spec §2). Penalties and fees scale with the building or the
   company. The one deliberate exception is the first licence in a group: £200, £500 or £2,000
   by era (§10.2). It steps with company scale. The £50 floor on licence-out income is income,
   not a cost.
5. **Legible before money moves.** Every cap, multiplier and wait is shown in the dialog that
   spends the money, and in the build forecast.
6. **Deterministic.** Every draw uses the seeded match RNG (`match_state.gd:48`).
7. **Unlock-by-doing stays the gate.** Licence fees sit on top of conditions and never replace
   them (§11).

---

## 3. Output and throughput — **LOCKED** (magnitudes *proposed*)

### 3.1 Definitions

| | Output bonus (`recipe_output`, exists) | Throughput bonus (`throughput`, new) |
|---|---|---|
| Outputs | × (1 + pct) | × (1 + pct) |
| Material inputs | unchanged | × (1 + pct) |
| Power | unchanged | × (1 + pct) |
| Labour, maintenance | unchanged | unchanged (the gain is spreading fixed costs) |
| Mines, oil wells, platforms | more recovered per unit dug (yield) | none: throughput does not reach them (§3.2a) |
| Effect on a 4-stage chain at +10% each | +46% apex output from the same ore | +10% apex, needs +10% ore |

At turn 30 (value added about £177 of £313 revenue), +10% output is worth about +£31/turn and
+10% throughput about +£18/turn.

### 3.2 Where output bonuses survive — LOCKED

1. **Extraction buildings** keep output bonuses: mines (`b_001`), oil wells (`b_032`–`b_034`),
   the water pump (`b_037`). This includes all mining-yield research (the `yield_*` table and
   `on_infinite_deposit` nodes).
2. **Legacy perks**, conditional:
   - Metal Magnate: +10% on iron, copper and alloy ingots and steel.
   - Glass Merchant: +5% on glass and windows.
   - **LOCKED condition: the perk holds while the original furnace is still owned.**
     - The starting furnace is named **"Original Furnace"**: Metal Magnate's on `tile_9_9`, and
       Glass Merchant's starting glass furnace *(proposed: same rule)*.
     - The perk's condition line reads exactly: "While the original furnace is still owned".
     - Selling or demolishing the Original Furnace ends the perk for good *(proposed)*. Buying it
       back does not restore it.
   - Code:
     - The start file marks the building (`"legacy_anchor": true`, `"name": "Original Furnace"`).
     - `BuildingNaming` honours a per-instance name override on the building dict. This is an
       owner-approved exception to the derived naming convention (`building_naming.gd`,
       `docs/building-names.md`).
     - The reconcile removes the start modifiers once the anchor instance is no longer the
       player's.
3. **Mission rewards**, temporary only: 15–30 turns. Throughput, cost and other rewards may stay
   permanent.
4. **Tier III capstones**: a handful of +5% output nodes (Appendix A marks the candidates).
5. **Satisfaction of +90 or more**: +5% output on everything (§4.3).
6. **Building level 3 ratio** (output ×3.5 for inputs ×3, `building_levels.gd:20`) *(proposed:
   keep)*. It is paid for with capital and labour.

Everything else that gives output today becomes throughput, a cost reduction, or a licence group
member (§10).

### 3.2a Extraction takes no throughput — owner ruling 30 October 2026

- Throughput does not reach mines (`b_001`), oil wells (`b_032`, `b_034`) or offshore oil platforms
  (`b_033`). The labour policies (work effort, work week, Minimal safety, the leave lockers) and every
  `throughput` modifier leave how hard they run alone, so their inputs, outputs, power and seam draw
  ignore it.
- Output still counts. Output modifiers (yield research, the −30% penalty, mission rewards), the +90
  satisfaction prize and strikes still change what they recover. Level, staffing and accidents still
  scale the run.
- Why: company wide labour settings must not quietly change mining costs. Overtime and the work week
  used to raise every mine's seam draw, so speeding up factories pushed mines past their free amount.
- Unchanged: their labour costs still follow the policies, so overtime still raises a mine's salary.
- *My call, flagged:* the water pump (`b_037`) keeps throughput, because the ruling names mines, wells
  and platforms only.
- Code: `LabourState.NO_THROUGHPUT_BUILDINGS` and `LabourState.takes_throughput`.
  `MatchState.throughput_multiplier` returns 1 for them, so `run_multiplier`, the seam draw, the
  finite charge, the forecasts and the tooltips all follow.

### 3.3 Conversion rules *(proposed)*

| Source | Today | Becomes |
|---|---|---|
| Research output node, building with material inputs | +x% output | +1.5x% throughput (start at ×1.5; harness decides ×1.5–2) |
| Research output node, building without material inputs (solar, wind, hydro) | +x% output | unchanged (output and throughput are the same there apart from power) |
| Research node in a licence group | +x% output | differentiated licence effect (§10.5) |
| Labour policies | output multipliers | throughput plus satisfaction (§4.4) |
| Mission `mm_ship_coal` | +5% all output, permanent | +5% all output for 20 turns, or +5% throughput permanent |
| Mission `t_port` | +10% output, 10 turns | +10% output, 15 turns |
| Mission `mm_furnace` | +10% coal and iron ore output, permanent | unchanged (extraction) |
| Disabled boards `gp_firm`, `ef_scale`, `br_factory`, `br_chemistry` | +3% to +5% output, permanent | 20-turn output, or permanent throughput. Convert before enabling the boards |
| Start modifiers (Legacy of Metal, Ashmouth Glassworks) | permanent output | conditional output (§3.2) |

Appendix A lists every research output node with its proposed conversion.

### 3.4 Stacking order

Per building per turn:

```
base × level mult × throughput (1 + Σ throughput pct) × staffing fill (§5) × accident factor (§4.5)
     → quantity run
outputs: quantity run × output modifiers (1 + Σ recipe_output pct) × strike factor 0.4 (§6)
inputs:  quantity run × input modifiers (1 + Σ recipe_input pct)
power:   quantity run share of energy
```

- Throughput pct values add, as Modifiers pct values do (`modifier_state.gd:545`).
- Staffing, accidents and caps multiply the run.
- A strike multiplies output only (LOCKED). It is a `mult` 0.4 modifier, not a −60 pct. Pct values
  add, so −60% beside a +10% legacy perk would net −50% instead of cutting 60%.

### 3.5 Code

- New Modifiers domain `throughput`, with the same `target` / `target_match` scoping as
  `recipe_output`.
- Apply the existing but unused `recipe_input` domain in `_scaled_input_qty`
  (`production.gd:3112`). Licence effects such as "coal input −15%" need it.
- `MatchState.startup_capacity_multiplier` (`match_state.gd:1191`) already scales inputs and
  outputs together. It becomes `run_fraction(building)` = staffing fill × accident factor.
  Throughput modifiers are folded in at the same sites. Strikes are an output modifier (§6).
- Replace every `LabourState.workforce_output_multiplier()` call with the throughput path:
  - `production.gd:1028, 1830, 2085`
  - `building_status.gd:89, 125, 369`
  - `build_forecast.gd:355`
  - `money_panel.gd:867`
- `CostSolver` and `tools/balance.py` model throughput: inputs and power scale too.
- Legacy perks need a per-turn idempotent reconcile that adds and removes the start modifier, the
  same pattern as `AdvisorState`'s seat reconcile.

---

## 4. Labour satisfaction — **LOCKED** (contributions *proposed*)

### 4.1 The metric

- `LabourState.satisfaction`: a float from −100 to +100, shown as an integer.
- It replaces `labour_output_pressure_pct` and its accrual (`labour_state.gd:127`). The current
  "output pressure" of Lean and Overtime goes away.
- **Target** = the sum of active policy contributions, company contributions (§4.4) and active
  event shifts (§4.5). Clamp to [−100, +100].
- **Movement (LOCKED)**: each turn satisfaction moves toward the target by **max(10% of the gap,
  2 points)**, and stops on the target once the gap is 2 or less.
  - The 10% keeps big changes from landing as a cliff.
  - The 2-point floor keeps the approach from crawling forever.
  - It moves at the same speed both ways.
  - A full swing takes about 25 turns. Metal Magnate's default start (+40 toward −55) crosses −5
    at turn 8 and settles at turn 26. A model employer from 0 toward +95 passes +50 at turn 9 and
    +90 at turn 24.
- **Nothing is instant except reneging on union agreements (LOCKED, §4.4a).** Every other event
  shifts the target for a while and satisfaction follows it.

### 4.2 Thresholds — LOCKED

| Satisfaction | Effect |
|---|---|
| +90 or more | +5% output on every building (§3.2) |
| +50 or more | new and expanding sites fill staff in **5 turns** |
| −5 to under +50 | staff fill in **8 turns** |
| under −5 | staff fill in **12 turns** |
| under −70 | strikes: 25% of buildings every 10 turns (§6) |
| under −90 | strikes: 50% of buildings every 10 turns |

### 4.3 What satisfaction buys

| Benefit | Detail |
|---|---|
| Expansion speed | Staffing fill rate (§5): first output at turn 4, 6 or 9 after placing a build |
| Acquisitions | Bought buildings arrive 80% staffed, or 50% under −5 (§7.5) |
| Peace | No strikes above −70 |
| Output | The +5% output prize at +90 or more |

A "model employer" pays roughly £25–40/turn more labour at turn 50 and gets faster growth, no
strikes and +5% output. A "sweatshop" gets +15–35% throughput and slow hiring, accidents and
strikes.

### 4.4 Policies redesigned *(proposed)*

The People > Labour tab keeps its six knobs, the automation switch and the lockers
(`people_ds2/labour_ds2.gd:215, 446`). Each option gets a throughput effect, a cash effect and a
satisfaction contribution.

**Hazardous buildings** are mine, furnace, power plant, EAF, petro refinery, chem plant, poly
plant and oil wells (`b_001, b_002, b_003, b_008, b_011, b_012, b_013, b_032–b_034`).

| Knob | Option | Throughput | Cash | Satisfaction |
|---|---|---|---|---|
| Work effort | Lean | −10% | salary −20% | −15 |
| | Standard | — | — | 0 |
| | Overtime | +15% | salary +25% | −25 |
| Pay while idle | 50% / 75% / 100% | — | as today | −10 / −5 / +5 |
| Safety | Minimal | +10% at hazardous sites | labour −5% | −20, plus accidents (§4.5) |
| | Standard | — | — | 0 |
| | High | — | labour +5% at hazardous sites | +10; no accidents; halves seam-card accident odds (§8.7) |
| Pensions | Minimum legal / Average / Generous | — | −5% / — / +3% rising (existing ramp) | −10 / 0 / +10, rising to +20 after 30 turns |
| Annual bonus | None / Small / Generous | — | — / +2.5% / +5% | 0 / +8 / +15 |
| Profit share | None / 10% / 20% | — (no output effect any more) | share of profit after tax and dividends | 20%: +5 at a loss, +10 below £25 profit after tax a turn, +15 at £25 or more; 10%: half of each (owner ruling 27 October) |
| Automation (switch) | On | — | labour −15% on level 2+ buildings, power +10%, maintenance +10% | −5, plus a −10 jump when switched on (layoffs) |
| Locker | Extended Annual Leave | −5% | — | +8 |
| Locker | Generous Parental Leave | −5% | — | +8 |
| Locker | Long Tenure Awards (HR Director) | — | existing trend | +5 |
| Locker | Stock Options (HR mission) | — | existing dividend effect | +10 |
| **New knob: Union** (always available) | None | — | — | 0 |
| | **Partial Union Agreement** | — | labour +10% at once, then +1% more each pay round (every 10th turn), to +25% *(ramp proposed)* | **+15**; no strikes while active |
| | **Comprehensive Union Agreement** | — | the same pay-round ramp *(proposed)*; **every labour cost cut counts at half** while it stands (§4.4a) | **+30**; no strikes while active; satisfaction **rises twice as fast** (falls are unchanged) |
| **New knob: Work week** (LOCKED, §4.4b) | 35 hours (level 1) | +5% | union: labour +10%; no union: — | union: 0; no union: −5 |
| | 40 hours (level 2) | +9% | union: labour +20%; no union: — | union: 0; no union: −10 |
| | 45 hours (level 3) | +12% | union: labour +30%; no union: — | union: 0; no union: −15 |
| | 50 hours (level 4) | +14.5% | union: labour +40%; no union: — | union: 0; no union: −20 |

**Owner ruling, 27 October.** Every policy option worth −10 or worse gives 5 back (Lean −15, Overtime −25, half pay
while idle −10, Minimal safety −20, Minimum legal pensions −10, Automation −5); options at −5 are unchanged. The work
week stays −5 a level (a −2.5 trial was taken back the same day). Events and their shifts (layoffs, demolition,
accidents, strikes broken, union step down, reneging) are unchanged. **Like Family**: Metal Magnate and Glass Merchant
get +25 while the company still owns its Original Furnace, ending for good with it as the legacy perk does
(`LegacyPerk.holds`). Also ruled the same day: profit share pays 10% or 20% and its satisfaction follows last turn's
profit after tax (`LabourState.profit_share_satisfaction`); the leave lockers cost 5% throughput each; a Comprehensive
Union Agreement doubles how fast satisfaction rises (`LabourState.rise_multiplier`); Metal Magnate starts on Standard
effort and 75% pay while idle so it settles above 0.

**Company contributions — LOCKED.** These are not policies; they come from the company itself:

| Source | Satisfaction |
|---|---|
| More than 5,000 workers | +5 |
| More than 25,000 workers | +5 more (+10 in total) |
| HR Director with 3 stars (Leadership 3) | +5 |
| HR Director with 2 stars | 0 |
| HR Director with 1 star | −5 |
| No HR Director | 0 |

- **Workers** are the Labour tab's headcount: `Production.labour_headcount()`
  (`production.gd:1965`), summed over unskilled, skilled and highly skilled.
  - Today it counts each building's base recipe headcount and skips paused buildings. It ignores
    level multipliers.
  - *(proposed)* Count level labour multipliers and staffing fill (§5), so the number is the
    workforce actually employed.
- Metal Magnate starts with 6,698 workers (two mines at 2,129, the furnace 1,623, the power plant
  817), so the first +5 applies from turn 1.
- At about 2,000 workers a building, 25,000 is a company of roughly 12–15 buildings. The
  benchmark gets there around turn 50.
- **HR Director stars** are the seat tier: `AdvisorState.advisor_seat_tier(advisor, "hr_director")`
  (`advisor_state.gd:493`), governed by Leadership.
  - HR Director is not one of the demo's base seats (`BASE_SEATS`, `advisor_state.gd:22`). In the
    demo it only appears after Executive Search research.
- The Labour tab ledger lists these lines beside the policies.

Example combinations:

| Combination | Throughput | Labour cost | Target |
|---|---|---|---|
All at the default 45-hour week unless stated:

| Combination | Throughput | Labour cost | Target |
|---|---|---|---|
| Overtime + Minimal safety, no union (squeeze) | +27%, +37% at hazardous sites | +20% | −60 (was −70, on the strike line, before the 27 October rulings) |
| Overtime + Partial Union (buy peace) | +27% | +65%, rising | −10: slow hiring, but no strikes |
| Comprehensive Union + 20% profit share (profitable, £25 a turn or more) + generous bonus + generous pensions (30 turns in) + High safety, at 35 hours (model employer) | +5% | about +35%, rising, plus profit share | +90, reached twice as fast |
| Comprehensive Union, then Automation | +12% | Automation's −15% counts as −7.5%, because it came after signing | +25 |

### 4.4a Comprehensive Union Agreement: halved labour cuts — LOCKED

- **From the turn it is signed**, every labour cost reduction gained afterwards counts at half
  strength.
- **Reductions already in force at signing are untouched.** At signing the game records them as
  grandfathered: each one's source id (research node, advisor seat effect, policy option, mission
  reward). A grandfathered policy that is switched off and on again later counts as new.
- **The halving outlives the union.** Dropping to Partial or None does not end it. It ends only
  if the company reneges.
- **What counts as a reduction**: every negative contribution to a building's labour bill.
  - research and mission `labour_headcount` cuts;
  - advisor seat cuts (COO, HR Director);
  - policy cuts: Lean effort, Minimum legal pensions, Minimal safety's −5%, Automation, the leave
    and Long Tenure trends;
  - licence effects that cut labour (§10.5).
- **Not halved**: labour increases, the 0.40 floor (applied after the halving), the seam over-cap
  multiplier (§8.3), strike and pay-rise costs, and the Work week's union labour cost.
- **Signing Comprehensive again later** keeps the existing record while a halving still stands (so
  stepping down and back up cannot launder halved cuts). After a renege, signing starts a new record.
- **Consequence**: cutting labour after going Comprehensive is half as effective for the rest of
  the game, unless the company reneges. Deep extraction (§8.3) and a model workforce pull against
  each other.

**Stepping down a union tier — LOCKED.**

| Change | One-off cost | Satisfaction |
|---|---|---|
| Comprehensive → Partial | 5% of revenue | a −15 target shift, decaying 0.5 a turn (gone after 30 turns) |
| Partial → None | 5% of revenue | a −15 target shift, decaying 0.5 a turn |
| Comprehensive → None | 10% of revenue | two −15 shifts, each decaying 0.5 a turn: −30, gone after 30 turns |

- **Double means two steps** *(proposed reading)*. Comprehensive straight to none costs exactly
  what stepping down twice does, so splitting it over two turns saves nothing.
- **Revenue** is the average of the last 5 turns *(proposed, the same basis as licensing)*. The
  cost is charged that turn as a "Union settlement" line before tax.
- **The higher tier's benefits go at once**: its standing contribution (+30 or +15), and strike
  protection when the company ends with no union.
- **The halving stays** (it ends only by reneging).
- **The Work week flips** with no union left: its +10% labour per level becomes −5 satisfaction
  per level (−15 at 45 hours).
- Example: Comprehensive to none at turn 50 (revenue about £527) costs about £53. The target
  falls 75 at first: 30 of standing contribution, 30 of shift, and 15 from the Work week at 45
  hours. It recovers as the shifts decay over 30 turns.
- Moving up a tier (None → Partial → Comprehensive) costs nothing beyond its labour.

**Renege on Union Agreements — LOCKED.**
- Available only while no union agreement stands and a halving is in force.
- Effect:
  - the halving ends, and every labour cut counts in full from the next turn;
  - **satisfaction −50 at once**, the only instant change in the system;
  - satisfaction then drifts back toward its target at the normal rate (from −20 down to −70,
    about 19 turns to recover).
- Strikes: a renege that drops satisfaction below −70 puts the company in strike territory at the
  next check.
- Copy:
  - button: "Renege on Union Agreements";
  - confirm: "Labour cuts count in full again. Satisfaction falls 50 at once."

**Code**:
- `LabourState`:
  - `union_halving_active`, `union_signed_turn`, `union_grandfathered_ids` (all saved);
  - `renege_union_agreements()`;
  - `step_down_union(to_tier)`, which charges the settlement and adds the decaying shifts.
- One target-shift list, `target_shifts` [{source, value, decay_per_turn, turns_left}], serves
  union step-downs (decaying) and events (fixed 10 turns).
- `labour_cost_factor` (`production.gd:1980`) today adds every labour change into one net figure
  before the floor. It must sum reductions by source, halve those not grandfathered while the
  halving is active, then apply the floor. `Modifiers.resolve_pct` needs a per-source breakdown
  (its modifier entries already carry ids). Policy and advisor deltas are tagged with their
  option and seat ids.

**Tests**:
- grandfathered cuts stay full and new cuts are halved;
- toggling a grandfathered policy makes it new;
- the halving survives dropping the union;
- renege restores full cuts and drops satisfaction by exactly 50;
- Comprehensive → None costs exactly Comprehensive → Partial plus Partial → None (money and
  shifts);
- a −15 shift decays 0.5 a turn and is gone after 30 turns;
- the floor applies after the halving;
- Partial and Comprehensive are exclusive.

### 4.4b Work week — LOCKED

- Four options: 35, 40, 45 and 50 hours.
- Each level adds throughput with diminishing returns: +5%, then +4%, +3% and +2.5%. They add
  up (LOCKED) to totals of +5%, +9%, +12% and +14.5%.
- The cost of each level depends on the union:
  - **under either union agreement**: labour cost +10% per level (+10% to +40%), and no
    satisfaction cost;
  - **without a union**: no labour cost, and −5 satisfaction per level (−5 to −20).
- **Default for a new game: 45 hours (LOCKED).** Every option has an effect; there is no "off".
  - Every company therefore runs at +12% throughput from turn 1: −15 satisfaction without a
    union, or +30% labour with one.
  - The e2e baseline must be re-measured with this default.
- It stacks with Work effort. Overtime and a 50-hour week give +29.5% throughput (throughput pct
  values add).
- On mines, longer hours raise seam draw (§8.1) and can push a site over its free cap.
- The labour increase is not a cut, so a Comprehensive Union does not halve it.

Rough value at turn 30 (value added about £177, labour about £58, estimates):

| Week | Throughput gain | Union labour cost | Net with a union | Without a union |
|---|---|---|---|---|
| 35 h | about £9 | about £6 | about +£3 | +£9 for −5 satisfaction |
| 50 h | about £26 | about £23 | about +£3 | +£26 for −20 satisfaction |

Under a union, hours are close to break-even money. Without one, they are cheap throughput paid
for in satisfaction. That ties the knob to the union choice.

### 4.5 Events (target shifts *proposed*)

Events never move satisfaction directly (LOCKED: renege is the only instant change). Each shifts
the **target** for 10 turns *(proposed)*, and satisfaction follows at the normal rate.

| Event | Target shift for 10 turns |
|---|---|
| Accident (Minimal safety only) | −10 each, stacking |
| Demolishing a staffed building | −15 |
| Selling a building | −5 |
| Automation switched on | −10 (on top of its standing −10) |
| Strike ends | +5 |
| Stepping down a union tier (§4.4a) | −15 per step, decaying 0.5 a turn instead of lasting 10 turns |

The annual bonus's bonus month is folded into the policy's standing contribution (§4.4) rather
than being an event.

**Accidents** (Minimal safety):
- Each hazardous building has a 2% chance per turn. It rises by 0.25 points per turn while
  Minimal stays on, to 6%. It resets when safety changes.
- An accident sets the building's run fraction to 0 for 2 turns.
- Compensation is 2 turns of that building's wage bill (scales; no flat cost).

### 4.6 Start values *(proposed)*

| Start | Satisfaction | Notes |
|---|---|---|
| Metal Magnate | +40 | Presets Standard effort, 75% idle pay and the 45-hour default, starts above 5,000 workers, and has Like Family while it owns the Original Furnace. Target is +10 (−5 −15 +5 +25; was −55 with Overtime and 50% idle pay before the 27 October rulings). Settles at +10 without going below 0 |
| Glass Merchant | +20 | Like Family while it owns the Original Furnace. Target +20 (+5 −15 +5 +25) |
| Other starts | 0 | |

### 4.7 UX: top bar — LOCKED (layout *proposed*)

The Workforce module **replaces the Council module in place**.
- Today the Council module is built at `top_bar.gd:1363` and refreshed at `:1379`, and its
  readout is at `:1225`.
- New contents:
  - **Figure**: signed satisfaction on a three-digit drum, with a trend arrow (up, down, steady).
  - **Lamp by band**:
    - gold at +90 or more
    - green at +50 or more
    - cream from −5 to +50
    - amber from −70 to −5
    - red under −70
    - blinking red while a strike warning is open
  - **Hover readout** (`stage`, `name`, `detail`):
    - stage "Workforce"
    - name "Satisfaction 42, falling"
    - detail by band, for example "New sites hire in 8 turns."
  - **Click** opens People on the Labour tab.
- Advisor loyalty moves:
  - The disloyal count becomes a lamp on the People > Advisors tab key.
  - A bell notice fires when an advisor turns disloyal. Loyalty stays visible on the Advisors tab
    as today.

UI copy follows the owner copy rule: brief, matter of fact, no hyphens, semicolons or dashes.

### 4.8 UX: People > Labour tab — LOCKED (layout *proposed*)

A new **satisfaction plate** goes at the top, above the time clock:

- **Dial**, −100 to +100, with band arcs: dark red under −90, red under −70, amber to −5, cream
  to +50, green to +90, gold above. The needle is current; a hollow marker is the target; a ghost
  needle is the 10-turn projection.
- **Ledger**: "Sources of Labour Satisfaction". Each active policy with its contribution, and the events of the
  last 10 turns with turn and value.
- **Band card**: what the current band does ("New sites hire in 12 turns. Strikes start below
  70.").
- **Knob option cards** show three lines: throughput, cost and satisfaction. Example: "Overtime.
  Throughput 15% higher. Salary 25% higher. Satisfaction target 30 lower." The old output pressure
  copy is removed. Since the 30 October ruling (§3.2a), a throughput line adds "Not at mines, oil
  wells or platforms." and Minimal safety names only the hazardous sites it speeds up.
- The time clock (labour cost now and in 10 turns), the workforce doors, automation and the
  lockers remain.
- **Union** becomes a seventh knob (None, Partial, Comprehensive), and **Work week** an eighth
  (35, 40, 45, 50 hours). The knob plate becomes two rows of four *(proposed)*.
- Work week cards show the cost that applies now, for example:
  - "45 hours. Throughput 12% higher. Satisfaction target 15 lower."
  - under a union: "45 hours. Throughput 12% higher. Labour cost 30% higher."
- While a Comprehensive halving is in force, the ledger shows "Labour cuts made since turn N count
  at half."
- With no union standing, a red guarded key under the Union knob reads "Renege on Union
  Agreements", and a confirm step follows it (§4.4a).
  - Partial card: "Satisfaction target 15 higher. Labour cost 10% higher, rising each pay round.
    No strikes."
  - Comprehensive card: "Satisfaction target 30 higher. Labour cost 10% higher, rising each pay
    round. Labour cuts count at half. No strikes."

### 4.9 Code

- `LabourState`:
  - `satisfaction`, `satisfaction_events` (last 10 turns), `target_satisfaction()`,
    `tick_satisfaction()` at the existing PROCESS hook point;
  - `satisfaction_band()`, `fill_turns()`;
  - export and import fields.
- `_advance_workforce_effect` and `workforce_output_multiplier` are rewritten around throughput
  and contributions.
- Unit tests:
  - movement: max(10% of the gap, 2), stopping on the target
  - clamp
  - band boundaries (−5, +50, +90, −70, −90)
  - event target shifts expire after 10 turns
  - renege is the only instant change
  - projection matches the tick

---

## 5. Staffing — **LOCKED**

| Rule | Detail |
|---|---|
| Fill | Each building has `staff_fill` in [0, 1], stored on the building dict (saved by `building_state.gd`'s deep copy) |
| Start (LOCKED) | Fill starts at 0 the turn the building receives its construction materials and construction begins: the kit claim in `Construction.claim_materials` (`construction.gd:575`). A project still waiting for materials (market, Local Suppliers or another tile) does not hire |
| Rate | +1 / `fill_turns` per turn, read each turn from the current band: 5, 8 or 12 turns |
| Operating | A building runs once fill reaches **70%**. From there its run fraction equals its fill (70% fill runs at 70%) |
| Wages | The hired share is paid. Before 70% the building is idle and the idle-pay setting applies to the hired share |
| Starting buildings | Fill 1 |
| Bought buildings | Fill 0.8, or 0.5 if satisfaction is under −5 |
| Upgrades | The extra headcount hires from the day works start, against the new requirement. Output never falls below the previous level's while staff fill (level 1 staff is only 67% of level 2's requirement) |
| Recipe switch | Staff are kept |
| Strikes, accidents | Do not change fill |
| Bought buildings | Their fill (0.8 or 0.5) applies from the closing turn |
| Demolition | Staff are lost (satisfaction −15) |

Time to 70% fill: 3.5 turns (fast), 5.6 (normal), 8.4 (slow). First output is at the later of
construction completing and 70% fill (§7.7).

**Deposit charge**: today a building on partial output still charges its deposit the full base
rate (comment at `production.gd:987`). Under this spec deposits are charged what is actually dug,
including fill (§8.5).

**Code**:
- `startup_capacity_multiplier` (`match_state.gd:1191`) becomes the run fraction. The
  `startup_half_capacity` flag (default off) is retired.
- Fill ticks once per turn. The build forecast models the ramp. BDP diagnostics get a staffing
  lamp: "Staffed 64%. Starts at 70%."

---

## 6. Strikes — **LOCKED** (draw weights *proposed*)

### 6.1 Rules

| Rule | Detail |
|---|---|
| Check turns | Every 10th turn (10, 20, 30…) |
| Warning | At T−2: if satisfaction is under −70, the strikers are drawn and named |
| Size | ceil(25% × N) under −70, ceil(50% × N) under −90. N = the player's running production and power buildings (not infrastructure, batteries or sites under construction) |
| Draw *(proposed)* | Weighted, seeded RNG. Hazardous sites ×2 while safety is Minimal; buildings with an accident in the last 10 turns ×2; others ×1 |
| At turn T | Under −70: the strike starts. Under −90 at the warning but −70 to −90 at T: only the first 25% strike. At −70 or above at T: "Strike called off" |
| Effect (LOCKED) | **Output −60%** for 3 turns (T, T+1, T+2), as a `mult` 0.4 modifier with a 3-turn expiry (owner rulings 26 Oct: −50% to −30%, then doubled to −60%). Inputs are still consumed in full, so a strike also wastes 60% of the input value. A struck mine still digs and charges its deposit in full. Struck buildings pay **50% labour cost** (LOCKED) |
| Knock-on | Normal shortfall rules. In Local Suppliers starts, in-house inputs default to stockpile first with Local Suppliers buying the shortfall (`middleman_service.gd:229`). A strike upstream becomes a cash shock downstream; on tile-only routes it halts the chain |
| Union Agreement, Partial or Comprehensive | No warning and no strikes while active |

Scale at turn 50 (revenue £527, profit £133):
- 25% of buildings striking removes about 15% of output for 3 turns, about £79/turn or 60% of
  the profit.
- 50% removes about 30%, about £158/turn, more than the profit, plus bridging markup.
- Three turns cannot trigger bankruptcy on their own (−£500 for 5 turns).

### 6.2 Ending strikes with a pay rise — LOCKED

Two actions, open from the warning until the strike ends:

| Action | Cost | Effect |
|---|---|---|
| Settle at one building (a pay rise) | labour +40% at that building for 10 turns (owner, 26 Oct: doubled from +20%) | That building's strike ends (or is called off). It cannot be named or strike again for 25 turns (owner, 28 Oct) |
| Settle every strike (a pay rise at each) | labour +40% at every struck or named building for 10 turns *(duration proposed)* | Every strike ends, **no strikes anywhere for 15 turns**, and none of these buildings can strike again for 25 turns |

- Neither action changes satisfaction or the band. The workforce is still unhappy, so the next
  check after the protection ends can draw again.
- Saved: `pay_raises` {instance_id: turns_left} and `strike_free_until` (turn).

### 6.2c Quiet after a strike — owner ruling 28 Oct

A building whose strike is settled or broken stays quiet for a while: it cannot be named in a
warning, or strike, at any check before the quiet runs out.

| Ended by | Quiet at that building |
|---|---|
| Settle (one building, or every strike) | 25 turns from the turn it was settled |
| Break strike (one building, or the whole round) | 20 turns from the turn it was broken |

- The quiet counts from the turn of the action. A check turn T is blocked while T is before the
  action turn plus the quiet, so a strike broken while still named (turn T−2) skips one check and a
  strike broken while running skips two.
- The strike size still counts every eligible building; the strikers are drawn from those not
  quiet, so a settled or broken building passes its turn to the others.
- A strike that runs its course leaves no quiet (it gives the +5 instead, AC12.5).
- Saved: `strike_quiet_until` {instance_id: first check turn it can strike again}.

### 6.2d One off bonuses and the strike lists — owner ruling 28 Oct

Two bonuses buy a building quiet (§6.2c) before or during a strike:

| Action | Cost, one lump sum paid now | Effect at each building it covers |
|---|---|---|
| One off building bonus | half that building's Settle cost (§6.2) | its strike ends with no +5, or it leaves the warning, and it is quiet for N turns |
| One off bonus (company wide) | half the Settle cost of every building it covers | the same at every building it covers |

- N scales with satisfaction when the bonus is paid, from 10 turns at −100 to 20 at +100, 15 at
  0: `roundi(15 + 5 × satisfaction / 100)`. At −80, 11 turns.
- A bonus never shortens a quiet already running: the building is quiet to the later of the two.
- Neither bonus changes satisfaction or counts toward Routinely broke strikes. Charged as "One off
  bonus" in that turn's costs.
- *Proposed (my calls):* the company wide bonus covers every production and power building that
  strikes count (§6.1) whose quiet it would lengthen, so a building already quiet for longer is
  not paid for; a building's own bonus key is off when it would not lengthen its quiet.

The Strikes tab carries two rows, each with a Show key that opens its list (one at a time):

1. **Buildings on strike cooldown (N)**: the buildings quiet now, each with its turns left.
2. **Buildings vulnerable to strikes in next 10 turns (N)**: while a warning stands, the named
   buildings. Otherwise, when the next check's warning is still to be drawn and satisfaction is
   projected (`LabourState.projected_satisfaction`) below −70 at that draw, every building strikes
   count that would not sit out that check. None while a union agreement stands or strikes are
   blocked.

An open list starts with its suggested actions: "Increase company wide satisfaction through
policies" (a key that opens the Labour tab), "One off bonus" (its total beside its key) and "One
off building bonus" (on each building's row). Then a row a building, as the strike table's rows:
emblem, good, name and tile, then its turns left (cooldown) or its output loss if it struck
(vulnerable), then its bonus cost beside its Bonus key. Bonus keys open a key bed with Confirm and
Cancel.

### 6.2b Breaking strikes — owner ruling 26 Oct

Beside each pay rise, Break strike: replacement crews end the strike at once.

| Action | Cost | Satisfaction | Effect |
|---|---|---|---|
| Break one building | 2 turns of its base wages, paid this turn ("Strike breaking"; owner, 26 Oct: doubled from 1) | target −5 for 10 turns | its strike ends with no +5, or a named building leaves the warning |
| Break the whole round | 2 turns of base wages per named or striking building | target −20 for 10 turns | every strike ends, the warning clears, no company wide protection (each broken building is quiet for 20 turns, §6.2c) |

- **Routinely broke strikes**: 2 whole rounds broken, or 10 buildings broken one at a time, add a
  standing −15 to the satisfaction target. Only signing a Comprehensive Union Agreement removes it;
  signing also resets both counts. A Partial agreement does not.
- The cost is a first guess (*proposed*): half what a pay rise costs over its 10 turns, so breaking is
  cheaper in cash and dearer in satisfaction.
- Saved: `strike_rounds_broken`, `strike_buildings_broken`, `strike_routinely_broke`.

### 6.3 UX: People > Strikes tab — LOCKED (layout *proposed*)

`TABS` (`people_ds2/people_ds2.gd:24`) becomes `["Advisors", "Labour", "Strikes"]`. The tab body
uses the DS2 kit (`ds2/parts.gd`). Every part's raised heading stands inside its case. In order:

1. **Strike risk** (a case):
   - a module with the labour icon, the pilot lamp, the mood ("Restless at −78") and what it means
     ("A quarter of your buildings can strike."), and the turns to the next check on a drum (or the
     turns a settlement still protects). With a union agreement in force, no drum;
   - the strike scale: satisfaction from −100 to +100 on a mini screen, below −90 lit red, −90 to −70
     amber, a needle at today's value, the thresholds printed under it, and a key to its zones;
   - "How strikes work", a key that opens the encyclopedia's Mechanics page Strikes and accidents.
     The explanation lives there, not on the panel.
2. **Sub-tabs** (owner ruling 26 Oct): two latching keys on a key bed, "Upcoming Strikes (N)" and
   "Ongoing Strikes (N)". Upcoming counts the buildings named for a strike that starts within 5
   turns; Ongoing the buildings on strike. Ongoing opens by itself while strikes are on, else
   Upcoming. They replace the lamp the Strikes tab key carried.
3. **The table** for the open sub-tab, laid out as the Building Ledger is:
   - metal labels over the columns: Location, Output loss, Cost to manage, Action;
   - "All strikes (N buildings)": the labour icon, its lamp and its timer ("Starts in 2 turns", "2
     turns left") under the name, the total output loss, then two lines: the total to settle beside
     the Settle key, over the total to break beside the Break strike key;
   - a row "N buildings" with a fold mark, folded at first, that shows the buildings under it;
   - a row a building: its emblem and the good it makes in a well, both 48 px, at the left, then its
     name with its tile on the second line, then its own figures and keys in the same columns;
   - Settle is the pay rise (§6.2), Break strike §6.2b. A key opens a key bed under its row that
     says what it does, with Confirm and Cancel. Break strike's bed also says how near the
     workforce is to remembering it for good;
   - an empty sub-tab says so ("No strikes due in the next 5 turns.").
4. **Strike planning** (a case, §6.2d): "Buildings on strike cooldown (N)" and "Buildings
   vulnerable to strikes in next 10 turns (N)", each with a Show key that opens its list under it,
   the suggested actions first.
5. **Record**: a row per past strike with its turn, the buildings, the outcome's lamp and the output
   lost.

### 6.4 Code

- `LabourState`:
  - `strike_warning` {turn, buildings}
  - `active_strikes` {instance_id: turns_left}
  - `strike_record` (capped list)
  - all saved
- Each strike registers a per-instance `recipe_output` modifier (`target_match {instance_id}`,
  `mult` 0.5, 3-turn expiry, source `strike`). The modifier system already scopes per instance
  and saves timed entries.
- Bell events at warning, start, end and called off.
- Unit tests:
  - band to size rounding (N = 1…20)
  - weighted draw determinism with a fixed seed
  - call-off on recovery
  - Union block
  - both pay-raise actions: cost, strike end, 15-turn protection

---

## 7. Pacing — **LOCKED** direction (numbers *proposed*)

| Action | Today | New |
|---|---|---|
| Construction | 3 turns, every production building | 4 / 5 / 6 by class (§7.1), with staffing on top |
| Upgrade | 3 turns (`building_levels.gd:15`) | **5 turns**, runs at the old level meanwhile |
| Recipe switch | 2 turns; COO Ops 3: 1 (`economy_config.gd:516`) | base **3**, Ops 3 **2**, Ops 2 **3**, Ops 1 **4**. Fees unchanged |
| Buying an NPC building | instant | **2-turn closing** (§7.5) |
| Buying land | instant | instant (unchanged) |
| Demolish | 1 turn | unchanged |
| Own transport | road 2/3/5 tiles a turn, rail 4/6/9, port 10/16/25; priced per turn-move | slower, priced by distance (§7.6) |
| Local Suppliers | same turn | same turn (**LOCKED**), pricing unchanged |

### 7.1 Construction

New CSV `build_duration` values. `BUILD_DURATION_BUMP` of 1 is kept on top, so the turns below
are the totals.

| Total | Buildings |
|---|---|
| 4 turns | mine, water pump, oil well, fracking well, solar farm, onshore wind, farm, forests |
| 5 turns | furnace, power plant, EAF, petro refinery, chem plant, poly plant, electrolyser, desal, hydro, battery |
| 6 turns | industrial factory, assembly plant, high tech manufactory, consumer factory, offshore platform, offshore wind |
| 2 turns | infrastructure (unchanged) |

Kit delivery from a non-tile source still adds 1 turn (`construction.gd`).

### 7.2 Temporary speed-ups

- New Modifiers domain `construction_time` (pct, rounded to whole turns, floor 2), applied in
  `MatchState.effective_build_duration` (`match_state.gd:781`).
- That function already feeds construction, the build forecast, the missing-materials dialog and
  the transport quote. A raw CSV read in `search_overlay.gd` must switch to it.
- Durations freeze when a project starts (`construction.gd:301, 381, 434, 505`), so a timed boost
  applies to builds started inside its window.
- Gerald, the master builder (COO), keeps his −1 turn.

**Andrew Keeler as Expansion Director — LOCKED:**
- Andrew's turn 3 offer (`decision_state.gd:110`) gains a third option. He takes a new
  **Expansion Director** seat, his alone, for his 30-turn tenure.
- The package:
  - construction **−3 turns** (floor 2 *(proposed)*);
  - new sites start **50% staffed**;
  - NPC purchase closing **1 turn**.
- No purchase discount and no build on credit.
- Effect: first output on any build lands at turn 2–3 instead of 6 at normal satisfaction (§7.7).
- Code:
  - a seat row in `AdvisorState` (seat definitions, `_SEAT_EFFECTS`, Andrew's allowed seats);
  - the decision's third choice;
  - the effects are a `construction_time` modifier, a starting fill and a closing override, all
    removed when the tenure ends.

**Mission rewards** may grant construction speed-ups for 15–30 turns, for example "Builds started
in the next 20 turns finish 1 turn sooner."

### 7.3 Upgrades

- `UPGRADE_DURATION` 3 → 5 for production buildings. Infrastructure upgrades keep 3 turns
  (`INFRA_UPGRADE_DURATION`), as infrastructure construction is unchanged.
- UI fallbacks that assume 3 must read the constant: `building_detail_panel_v2.gd:1135` and
  `upgrade_dialog_ds2.gd:239` (`get("duration", 3)`).

### 7.4 Recipe switching

`RETROFIT_TIERS`: base 3 turns, `ops3` 2, `ops2` 3, `ops1` 4. Labour fractions and fees are
unchanged.

### 7.5 Buying NPC buildings

| Rule | Detail |
|---|---|
| Offer | The player pays in full at offer. **No cancellation** (LOCKED) |
| Closing | 2 turns (1 with Andrew's Expansion package). The building shows "Under offer" and leaves the buildings market |
| Transfer | At closing: owner, land grant, `land_exempt`, 2 turns of input stock (`PURCHASE_SEED_TURNS`, `match_state.gd:2172`), staff fill 0.8 (0.5 under −5 satisfaction) |
| Code | One `MatchState.offer_for_building(iid)` replaces the three duplicated transfers: `building_market_panel.gd:93`, `tile_info_panel_v2.gd:1126`, `building_detail_panel_v2.gd:554`. A saved `pending_purchases` dict, ticked each turn |

### 7.6 Shipping — **LOCKED** (speeds and calibration *proposed*)

**Price by distance, not by turns (LOCKED).**

- Today every leg of a route is one turn-move, charged `qty × class rate × mode multiplier`
  (`economy_config.gd` `transport_cost_for_route`: rail 0.5, road 1, bare ground 2, pipes flat).
  Per-tile cost is that leg divided by the level's range (`INFRA_RANGE_BY_LEVEL`, `:376`), so
  speed and price are tied together.
- New formula:

```
freight = Σ over route segments ( tiles × weight × qty × mode multiplier[mode][level] )
weight  = transport_rate_for_good(good)   # today's class rate: weight class plus its small value part
```

**Calibration.** Each mode and level multiplier is today's leg multiplier divided by today's
range, so a whole leg costs exactly what it does now:

| Mode | L1 | L2 | L3 |
|---|---|---|---|
| Road | 0.50 | 0.333 | 0.20 |
| Rail | 0.125 | 0.083 | 0.056 |
| Pipe, reinforced pipe | pipe rate ÷ 2 | ÷ 3 | ÷ 5 |
| Fluid overland (road or rail tanker) | `FLUID_OVERLAND_COST_MULT` ÷ range | | |
| Bare ground | 2.0 | | |

Effects:
- Part legs now pay for their tiles only. Today a 3-tile road trip at L1 pays 2 whole legs; it
  will pay 1.5. Short routes get up to a third cheaper, long routes converge.
- If the e2e shows total freight falling more than about 10%, scale every multiplier by one
  constant rather than retuning modes.

**Speed is a separate table**, `INFRA_SPEED_BY_LEVEL` *(proposed)*. It sets transit turns only:

| Mode | Speed today (tiles a turn, L1 / L2 / L3) | New speed |
|---|---|---|
| Road | 2 / 3 / 5 | 1 / 2 / 4 |
| Rail | 4 / 6 / 9 | 3 / 5 / 8 |
| Port | 10 / 16 / 25 | 8 / 12 / 20 |
| Bare ground | 1 | 1 |

**Unchanged:**
- Port ad valorem.
- Sea freight pricing.
- The freight credit, which counts units.
- The congestion surcharge, which is charged per turn of in-transit flow over a link's cap.

Slower goods sit on links longer, so congestion rises on busy links. The e2e should report it.

**Route choice (owner ruling, 27 October).** Shipments take the cheapest route, and between equal
costs the one with fewer turns. Upgrading a level buys speed.

**The Routing switch sets route choice (owner ruling, 30 October).** The Shipments and Stockpiles
panel's Routing switch (Fastest, Cheapest, Blended) was never read by the router: it said Fastest
while goods took the cheapest route. It now sets the route every new shipment takes.
- **Cheapest**, the default for new games: the 27 October rule above.
- **Fastest**: the fewest turns, and between equal turns the least freight.
- **Blended** *(my call, proposed)*: freight and turns count half each, each against the best the
  network allows. The route with the least ½ × freight ÷ cheapest freight + ½ × turns ÷ fewest
  turns, then the least freight. On a cheap road detour a turn slower than a run of bare ground,
  Blended takes the road.
- It is one company wide setting, as the panel already showed it. Shipments already on the way keep
  their route. Fluids still take a pipe route first whatever it says. Local Suppliers are unaffected.
- Saved as before. A save older than version 19 loads on Cheapest, because the switch did nothing
  then and its goods took the cheapest route.
- Code: `Catalog._best_route` reads `MatchState.route_objective`; the route cache keys on it.
  `MatchState.reset` sets Cheapest.

**Local Suppliers: same turn, LOCKED, pricing unchanged.**
- Their haul is trips to the hub × settlement factor × freight rate.
- Trips are `ceil(distance ÷ TRANSPORT_MAX_TILES_PER_TURN)` (`middleman_locations.gd:147`).
- That constant (2) must not follow the new speed table. Rename it to a Local Suppliers constant,
  so that slowing own transport cannot raise their prices.

**Code:**
- `transport_cost_for_route` charges per tile from the route's segments.
- `freight_per_tile` (`transport_service.gd`) reads the new multipliers directly.
- Transit time reads `INFRA_SPEED_BY_LEVEL`.
- `transport_turns_for_tile_distance` (`economy_config.gd:542`) is audited for callers that price
  by turns.
- The Resources panel and transport quotes show £ per tile per unit, as today.

### 7.7 Time to first output

Counted in turns from the turn construction begins: the materials are on the site and claimed
(§5). A kit bought from the market, Local Suppliers or another tile arrives first. That adds its
delivery time (usually 1 turn) before the clock starts. For a purchase, it is counted from the
offer.

| | Fast hiring (+50 or more) | Normal | Slow (under −5) | Today |
|---|---|---|---|---|
| 4-turn build (mine) | 4 | 6 | 9 | 3 |
| 5-turn build (furnace) | 5 | 6 | 9 | 3 |
| 6-turn build (factory) | 6 | 6 (at 75%) | 9 | 3 |
| Any build with Andrew's Expansion package | 2–3 | 2–3 | 3 | — |
| Bought building | 3 | 3 | 5 | 1 |

At normal satisfaction staffing is the binding constraint. Construction length only shows at high
satisfaction. Buying is the fast lane, which is what LOCKED pacing intends.

---

## 8. Mining — **LOCKED** (card and research *proposed*)

### 8.1 Draw

- A **site** is one deposit good on one tile.
- Its **draw** is the sum over the player's workings on it of: level multiplier (L1 1, L2 2,
  L3 3.5) × staffing fill × accident factor. Throughput does not reach extraction (§3.2a, owner
  ruling 30 October 2026; was × throughput).
- Strikes do not lower draw: a struck mine digs in full and recovers 70% (§6).
- Draw is measured in level 1 workings, so caps are recipe-agnostic. An offshore platform and an
  oil well each count 1 at level 1.
- NPC buildings do not simulate and never draw.

### 8.2 Caps — LOCKED

| Seam | Free cap | Collapse limit | Labour and maintenance at the limit |
|---|---|---|---|
| Endless (no amount in `tile_properties.csv`) | 1.5 | 3 | × 2.5 |
| Finite | 1.5 | 3 | × 2.5 |

**Owner ruling, 26 October 2026: free amount 1.5.** Every seam is free to 1.5 level 1 workings
and may collapse past 3 (was 2 and 4 for endless seams, 3 and 6 for finite ones). One mine on
overtime fits; a second on the same seam pays about ×1.7.

**Owner ruling, 26 October 2026: collapse risk.** Past the limit nothing is scaled back and
nothing is refused. Every working digs in full, M keeps rising, and each turn the seam may
collapse: 5% for each level 1 working's worth over the limit (`COLLAPSE_PER_WORKING`), rolled on
the seam cards' saved RNG. A finite seam that collapses loses what remains. An endless seam stops
all its mines for 3 turns (`COLLAPSE_OFFLINE_TURNS`).

Players never see workings. Every figure is units dug a turn: a working's draw × its recipe's
base output. A coal mine digs 60 a turn at level 1, so a coal seam is free to 90 and may collapse
above 180.

### 8.3 Over-cap cost — LOCKED

Site multiplier: **M = 1 + max(0, draw − free cap)**. It does not stop at the limit.

- That is +100% labour and maintenance for each full level 1 working over the free cap. It is
  continuous, so overtime pushing a site 0.2 over costs ×1.2, not a cliff.
- M applies to labour and maintenance of **every working on the site**.
- A Comprehensive Union Agreement halves every labour cut (§4.4a), so deep extraction is much
  harder for a model employer.
- **Implementation catch.** `labour_cost_factor` (`production.gd:1980`) adds all labour changes
  and then floors at 0.40 (`LABOUR_FACTOR_MIN`), and Modifiers pct values add. M must be a
  separate multiplicative factor applied after that floor, and after maintenance modifiers.
  Otherwise a −60% labour discount against +300% nets +240% (×3.4) instead of ×1.6, and "labour
  and maintenance modifiers unlock deep extraction" never happens.

Coal economics (yield −30% on both seam types; buying coal costs about £0.62 with Local Suppliers'
fees):

| Site | Draw | M | £ per coal, no discounts | £ per coal, labour ×0.4 and maintenance ×0.6 |
|---|---|---|---|---|
| Endless, one L2 | 2 | 1.5 | 0.45 | |
| Endless, one L3 | 3.5 | 3 | 0.65 (loses) | |
| Endless, two L2 | 4 | 3.5 | 0.96 (loses) | 0.49 |
| Finite, three L1 | 3 | 2.5 | 0.88 (loses) | |
| Finite, one L3 | 3.5 | 3 | 0.65 (loses) | |
| Finite, L3 + L2 | 5.5 | 5 | 1.15 (loses) | 0.57 |
| Finite, three L2 | 6 | 5.5 | 1.48 (loses) | 0.73 (loses) |

Mine upkeep basis:
- Labour about £9.50, maintenance £4, power £3.30 per turn at level 1.
- Level 2: ×1.5 labour, ×1.8 maintenance and power.
- Level 3: ×2 labour, ×2.5 maintenance and power.

Early sites grow by adding level 1 mines, because mine level 2 needs In-Pit Crushing (5
profitable mines). A seam takes one mine free; a second costs ×1.5 across the site, whatever the
labour policies (§3.2a; was ×1.7 at the 45 hour week).

### 8.4 Deposit sizes — LOCKED (×3)

- New `EconomyConfig.DEPOSIT_SIZE_MULT := 3.0`, applied in `seed_deposits`
  (`match_state.gd:470`) **after** `_normalized_deposit_qty` (`match_state.gd:553`).
- That function snaps coal and iron to 2,000 or 4,000 and turns anything above 4,000 endless. It
  must keep reading the raw CSV values. Appendix B has the table.

| Seam | Size | Life at 1 | Life at 3 (finite free cap) | Life at 6 |
|---|---|---|---|---|
| Coal 2,000 → | 6,000 | 100 turns | 33 | 17 |
| Iron 2,000 → | 6,000 | 150 | 50 | 25 |
| Iron 4,000 → | 12,000 | 300 | 100 | 50 |

**Metal Magnate's starting coal seam (LOCKED):**
- **In the demo it stays at 2,000.** The demo is only 100 turns long, and the seam has to run out
  inside it.
  - One level 1 mine lasts 33 turns, so the seam card (§8.7) lands around turn 25.
  - Filling the seam to its free cap (3) empties it in about 11 turns.
- **Outside the demo it triples to 6,000** like every other seam: 100 turns at one mine, 33 at
  the free cap.
- Code:
  - a start-file field `demo_deposit_overrides` (`{"tile_6_8": {"coal": 2000}}` in
    `data/starts/metal_magnate.json`);
  - applied in `seed_deposits` after `DEPOSIT_SIZE_MULT`, only when the match runs the demo rules
    (`MatchState.ruleset.victory_set == "demo_itch"`, which a demo build always forces,
    `save_validation.gd:731`);
  - `deposit_remaining` is already saved, so loads need nothing new.

### 8.5 Charging and yield

- Finite seams are charged **what is dug**: base × level × fill (no throughput, §3.2a). This
  replaces the rule at `production.gd:987` ("deposit life is independent of output multipliers").
- Yield (`recipe_output`) still never burns the seam: investing in recovery cannot shorten a
  field.
- The −30% yield penalty (`EXTRACTION_PENALTY_PCT`) stays on both seam types (**LOCKED**).
  Finite seams win on volume, not yield.
- That penalty and its staged research recovery are specified in
  `docs/tech-gating-and-deposit-penalty-spec.md` (Feature 2). This spec does not change them.

### 8.6 Raising caps *(proposed)*

- Research softens the per-working cost rather than raising free caps: +100% to +75% at tier II,
  to +50% at tier III. Labour and maintenance modifiers stay the main key.
- The Extraction licence group (§10.5) carries the first step.

### 8.7 Seam running out (finite only) *(proposed)*

At 25% remaining, a decision card replaces the 5-turn warning (`DEPOSIT_WARNING_TURNS`):

| Option | Effect |
|---|---|
| Sink a deeper shaft | Two turns of the site's wages plus kit materials; 2 turns offline. Remaining +40%. Site labour +40% and power +50% for the rest of the seam |
| Rob the pillars | Remaining +25%. Site labour ×1.5 while robbing. Accident chance 3%/turn (halved by High safety, doubled by Minimal). The working collapses when the seam ends: no salvage |
| Heavy blasting | Each turn 25% chance of a double-dig turn (charged double), 8% chance of a roof fall (2 turns offline), 2% chance the rest of the seam is lost |
| Sell with reserves | An NPC buyer pays the building price plus remaining units at 50% of market |
| Carry on | Mine to the end |

### 8.8 UX

- **Tile panel** deposit row, in units a turn, a figure a line: "Digging 150 a turn", "Costs rise
  above 90", "May collapse above 180", then what is left.
- **Construct and upgrade dialogs**, in units a turn: "Seam output will increase from 120 to 240.
  Above 180, deposit may collapse." Nothing is refused.
- **BDP diagnostics, Plant stage**: "Seam" lamp, amber over the free cap, red past the limit with
  its collapse chance.
- **Seam card choices** say what they do in a few short lines, each led by its icon, risks in
  amber ("Seam lasts longer", "Mines stop for 2 turns", "Risks roof falls and seam loss").
  Hovering a choice, its key included, opens a plate that explains it: a few sentences, then each
  phase (Now, For the next 2 turns, Then until the seam runs out, Each turn, On average) with a row
  a figure: icon, what it is, start, arrow, outcome, a clock for how long, a chance in amber.
- **Build forecast and CostSolver** include M.

### 8.9 Code

- Each site's draw and M are derived when asked (`scripts/mining_sites.gd`). They store no save
  state. The collapse roll runs first in the seam cards' PROCESS tick.
- Production charges the deposit what was dug (`production.gd:980–1050`). Labour and maintenance
  on the site multiply by M.
- Caps live in `EconomyConfig` per seam type, with an `extraction_cap_cost` Modifiers domain for
  the per-working cost.
- Unit tests:
  - endless and finite caps
  - collapse past the limit
  - M continuity
  - M applied after the labour floor
  - finite charge includes fill, never throughput
  - yield does not charge
  - ×3 sizes keep endless detection

---

## 9. Larger footprints — **LOCKED**: mines 32–40 (value *proposed*: 32), factories 20

**Mines.**

| Mine land at L1 | L1 / L2 / L3 land | Fits on rural 200 | Hill 160 | Mountain 120 |
|---|---|---|---|---|
| 25 (today) | 25 / 45 / 63 | 8 / 4 / 3 | 6 / 3 / 2 | 4 / 2 / 1 |
| **32** | 32 / 58 / 80 | 6 / 3 / 2 | 5 / 2 / 2 | 3 / 2 / 1 |
| 36 | 36 / 65 / 90 | 5 / 3 / 2 | 4 / 2 / 1 | 3 / 1 / 1 |
| 40 | 40 / 72 / 100 | 5 / 2 / 2 | 4 / 2 / 1 | 3 / 1 / 1 |

Why 32:
- Three level 1 mines (a finite seam's free cap) use 96. That stays under the planning limit of
  100 (`DENSITY_SOFT_CAPACITY`, +50% build cost past it). At 36 the third mine costs +50%.
- A rural mine's land goes from 3 patches (£60) to 4 (£80).

**Factories: 15 → 20 (LOCKED).**
- Applies to industrial factory, EAF, assembly plant, high tech manufactory and consumer factory
  *(proposed list)*. Refineries, chemical and polymer plants keep their current land.
- At 20 / 36 / 50 land for L1 / L2 / L3, a tile holds:
  - rural 200: 10 / 5 / 4
  - urban 170: 8 / 4 / 3
  - hill 160: 8 / 4 / 3
  - mountain 120: 6 / 3 / 2
  - today on rural: 13 / 7 / 5
- Land is sold in 10-unit patches, so a level 1 factory still buys 2 patches. Only tile capacity
  and the planning limit change.

**NPC map.**
- With mines at 32 and factories at 20, NPC tiles over the planning limit go from 6 to 8 of 193.
- The NPC map holds 106 factory-class buildings and 17 mines.

**Decouple the simulation from the art:**
- `tile_size_used` drives drawn building size and slot boxes (`authored_slot_sizes.gd:63`,
  clamped at 30). Changing it means map and 3D rebakes.
- Add a buildings CSV column `land_units` (blank means `tile_size_used`). Read it through one
  `Catalog.land_units(bdata)` helper at every simulation land site:
  - `construction_rules.gd:253`
  - `building_state.gd:269, 321`
  - `building_price.gd`
  - `building_works.gd`
  - the others found by grepping `tile_size_used`
- Art keeps reading `tile_size_used`.

---

## 10. Research licensing — **LOCKED** structure (bases and scales *proposed*)

### 10.1 Licence groups

- A licence group is **three competing processes for one problem**, sold by three fictional
  licensors. Historically, exclusivity came from patents (Bessemer, Solvay), not from knowledge,
  so a player can own all three, at a rising price.
- Each member keeps its own unlock-by-doing condition. Meeting it makes the member **ready to
  license**. It no longer auto-unlocks.
- Prereqs inside a group are removed. Members are rivals, not a ladder: today Steam Turbine
  Upgrades requires Pulverized Coal Boilers, and Continuous Casting requires Basic Blast Furnaces.

### 10.2 Licensing in — LOCKED prices

| Licences already held in the group | Price of the next |
|---|---|
| 0 | **£200** in era 1, **£500** in era 2, **£2,000** in era 3, one-off |
| 1 | **2% of company revenue** a turn for 30 turns |
| 2 | **8% of company revenue** a turn for 30 turns |

- The order of purchase sets the price: the first one licensed costs the era price, whichever
  it is.
- **Eras** follow the New Game era rule: 30% / 30% / 40% of the match length (`ERA_SHARES`,
  `new_game_ds2.gd:78`). The 300-turn campaign is turns 1–90, 91–180 and 181–300.
  - The demo draws its eras on the campaign's scale (`DEMO_ERA_SPAN`), so demo turns 91–100 are
    era 2.
  - Move `ERA_SHARES` to `EconomyConfig` and add `MatchState.era_for_turn(turn)`, so the sim and
    the New Game screen share one source.
- **Royalty base (LOCKED): company revenue.** Every held royalty licence costs every turn,
  whether the process is used or not. Hoarding therefore always costs.
- Scale at turns 20–50 (average revenue about £380, profit about £109):
  - 2% is about £7.60 a turn, roughly 7% of profit, or about £230 over the 30-turn term (close to
    the first licence's £200).
  - 8% is about £30 a turn, roughly 28% of profit, or about £910 over the term. Owning the whole
    group is a commitment.
  - A +10% throughput process on buildings making 30% of revenue returns roughly 1.7% of revenue.
    So the second licence only pays where the process covers a large share of the business, which
    is the "plan to monetise it" test.
- After 30 turns (the patent term) a royalty licence is paid up and kept for free.
- Turn summary and money panel get a **Royalties** row.

### 10.3 In-house development

- A free pick (turns 1, 12, 36, 60, 84; `research_panel.gd:89`) spent on a group member is
  in-house development: no fee, no royalty.
- An in-house process is the company's own and can be licensed out.
- Nodes outside licence groups unlock by doing as today and count as in-house.

### 10.4 Licensing out — LOCKED idea (scale *proposed*)

- **Eligible**: tier II and III processes developed in-house, within 60 turns of development
  *(proposed patent window)*. Never sublicensed, never tier I. Each process once.
- **Price (LOCKED): max(£50, rate × average company revenue of the last 5 turns)**, one-off.
  - Rate = **10% + 2.5% for each other unsold in-house tier II + 5% for each unsold in-house tier
    III**.
  - Counting only unsold processes makes each sale lower the next price *(proposed)*.
  - The 5-turn window blunts a one-turn stock dump.
  - Examples:
    - turn 30 with one other tier II: 12.5% of £313 is £39, so the £50 floor applies;
    - turn 50 with two: 15% of £527 is £79;
    - turn 100 with nine tier II and three tier III: 47.5% of £543 is £258.
  - Late in a run the rate can pass 100% of a turn's revenue (30 tier II and 10 tier III make
    135%). *(proposed)* Cap the rate at 50%, and have the harness check licence income at turns
    150 and 300.
- **Consequence (LOCKED): 2% lower sale price per licence taken.** Each process licensed out
  lowers the sale price of the goods it touches by 2%, stacking per licence, for 30 turns
  *(duration proposed)*. It is a timed `market_price` modifier. Local firms now compete, so
  selling processes for goods the company does not make costs nothing.
- Turn summary and money panel get a **Licence sales** row.

### 10.5 Initial groups *(proposed)*

Built from existing same-building trios. Effects are differentiated so each member is a distinct
process.

| Group | Members (existing nodes) | Proposed effects |
|---|---|---|
| Coal power (`b_003`) | Pulverized Coal Boilers, Steam Turbine Upgrades, Reheat Turbine Cycles | coal input −15%; +10% throughput; labour and maintenance −10% |
| Iron and steel (`b_002`) | Basic Blast Furnaces, Continuous Casting, Pulverised Carbon Injection | +10% furnace throughput; steel recipe inputs −10%; coal input −20% on steel, power +5% |
| Refining (`b_011`) | Fractional Distillation, Catalytic Cracking, Specialised Petrochemical Pipelines | +10% throughput; crude input −10%; power −15% |
| Extraction (`b_001`) | Bench Blasting Expansion, Bulk Haulage Fleets, Continuous Surface Miners | +5% yield; over-cap cost +100% → +75% per working; +20% yield on endless seams (as today) |
| Solar (`b_024`) | Utility Solar Arrays, Utility-Scale Inverters, Dual-Axis Tracking Farms | output as today (no material inputs) |
| Wind (`b_025`) | Onshore Wind Control, Taller Turbine Towers, Tall-Tower Wind Capture | output as today |
| Factory (`b_007`) | High-Volume Press Lines, Multi-Shift Production, Near-Net-Shape Stamping (new, P6) | +10% throughput; +15% throughput with labour +10%; inputs −10% |
| EAF (`b_008`) | Foamy Slag Practice, Ultra-High-Power Arcs, Eccentric Bottom Tapping (new, P6) | power −10%; +15% throughput with power +10%; labour and maintenance −10% |

### 10.6 UX

- **Research panel**: a group draws as three cards on one patent board. Each card shows its
  condition, its state and its price:
- Ready cards carry a lamp. Example price lines: "License for £200", "License for 2% of revenue,
  30 turns".
- The licence dialog shows the payback at the company's current buildings: "Costs about £8 a
  turn. Returns about £6 a turn."
- In-house nodes show "License out for £X", the market consequence and the turns left in the
  patent window.

### 10.7 Code

- `ResearchState`:
  - `licences` {title: {kind: inhouse | flat | royalty, rate, start_turn, end_turn}}
  - `licensed_out` {title: turn}
  - new CSV column `licence_group`
- The condition engine routes group members to a ready state, not `grant_unlock`. Effects apply
  when licensed. `is_node_available` (`research_state.gd:538`) handles group prereqs.
- Royalties are charged in the turn's costs before tax.
- Unit tests:
  - price by order
  - royalty on company revenue
  - paid-up after 30 turns
  - in-house via free pick
  - licence-out price and £50 floor
  - patent window
  - no sublicensing
  - market consequence expiry

---

## 11. Design-intent amendments (owner to approve)

Each change must land with the phase that needs it. The commit must say "changes design stance
X, approved by owner", per the skill's own review rule.

### A. `.claude/skills/cnc-design-intent/SKILL.md`

**A1. Unlock-by-doing** (P6). Keep the paragraph and insert after "A stance, not an omission.":

> Licence groups add a price on top. Each of a group's three competing processes still needs its
> condition, and only then can be licensed: the first for £200, £500 or £2,000 by era, then 2% and
> 8% of company revenue for 30 turns. A free pick develops one in-house with no fee, and only
> in-house processes can be licensed out.

Extend the regression smell to: "adding a science-points currency, letting money buy a node
whose condition is unmet, or licensing out a process that was licensed in."

**A2. New stance: output bonuses are rare** (P1, P5):

> **Output bonuses are rare; growth is physical.** A flat output bonus makes product from
> nothing and compounds down a chain (+10% at four stages is +46% at the apex). Output bonuses
> exist only for:
> - extraction yield;
> - the start legacies, while the Original Furnace is still owned;
> - timed mission rewards of 15–30 turns;
> - a few tier III capstones at +5%;
> - Labour satisfaction of +90 or more, at +5%.
>
> Everything else is throughput (inputs, outputs and power scale together), a cost cut, or a
> licence. Regression smell: a new permanent output bonus on a processing building, or a labour
> policy that raises output without consuming inputs.

**A3. New stance: time has a price** (P2):

> **Time has a price, and the player sets it.** Construction takes 4–6 turns. A building also
> waits for staff: it runs once 70% staffed, and staffing takes 5, 8 or 12 turns by Labour
> satisfaction. Bought buildings close in 2 turns but arrive staffed. Speed-ups are timed (Andrew
> Keeler as Expansion Director, mission rewards), never permanent. Regression smell: instant
> hiring or construction "because waiting is boring", or a permanent cut to build time.

**A4. New stance: labour satisfaction is a budget** (P1, P3):

> **Labour satisfaction is a budget.** Policies trade throughput and cash for satisfaction
> (−100 to +100). Satisfaction sets:
> - hiring speed;
> - strikes: 25% of buildings below −70 and 50% below −90, every 10 turns, at 60% less output;
> - the +5% output prize.
>
> Satisfaction moves toward its target by max(10% of the gap, 2) a turn; only reneging on union
> agreements (−50) is instant. Pay rises end strikes at a labour cost, not a satisfaction one. A
> Comprehensive Union Agreement buys +30 satisfaction by halving every labour cut made after it is
> signed, for good unless the company reneges. Stepping down a tier costs 5% of revenue and a
> −15 satisfaction shift that decays over 30 turns. Regression smell: a policy
> that raises throughput with no satisfaction cost, or strike protection that costs nothing.

**A5. New stance: seams have working limits** (P4):

> **Seams have working limits.** Each deposit extracts freely up to 1.5 level 1 workings. Past a
> limit of 3 the seam may collapse. Every working over the
> free cap adds 100% labour and maintenance on the whole site, as a multiplier after labour discounts. Deep
> extraction therefore needs labour and maintenance modifiers. Finite seams are charged for what
> is dug: level and staffing count, yield does not, and throughput never reaches a mine. Regression smell: removing the cap because players
> want to upgrade, letting yield research burn seams, or turning the over-cap cost into a
> percentage that labour discounts cancel.

**A6. Advisors stance** (P2). Append:

> Expansion Director is an eleventh seat, Andrew Keeler's alone, for his 30-turn tenure.

**A7. Deliberate friction list.** Add:

> - A bought building cannot be cancelled during its 2-turn closing.
> - A building idles until it is 70% staffed.
> - Strikes cut output 60% while inputs are still consumed.
> - Freight is priced by distance. Local Suppliers settle in the same turn and keep their own
>   trips constant.

**A8. Stale stance (cleanup, no ruling needed).** "Prices decay monotonically and forecasts are
honest" is out of date. Per-good decay was retired on 28 August (`market_state.gd:5-10`), and the
price-impact ladder is the only price model. Suggested replacement:

> **Prices move with trading, and forecasts are honest.** Base prices are static. The player's
> own net selling and buying move a price through the price-impact ladder.

### B. `docs/early-game-onboarding-spec.md` §2, principle 2

| | Text |
|---|---|
| Before | "**Brakes must engage with scale.** No new flat costs, ever." |
| After | "**Brakes must engage with scale.** No new flat costs, except the first licence in a research licence group, which steps by era (£200, £500, £2,000)." |

### C. `docs/tech-gating-and-deposit-penalty-spec.md`, Feature 2

Append:

> The −30% and −15% penalties apply to finite and endless seams alike (owner, 25 October 2026).
> Seam caps, over-cap costs and charging by what is dug: `pacing-labour-mining-licensing-spec.md`
> §8.

### D. Code comment, `production.gd:987`

- Today it says deposit life is "deliberately independent of output multipliers", and that a
  building throttled by the startup ramp still charges full base rate.
- P4 rewrites it to say that finite seams are charged for what is dug (level, throughput,
  staffing) and that yield modifiers never charge.

### E. `docs/building-names.md`

Add the per-instance name exception: "Original Furnace" for each start's legacy building.

## 12. Save and migration

`SAVE_VERSION` 17 → 18 (`save_load.gd:28`). Follow the `cnc-save-and-migration` skill.

| New state | Default for old saves |
|---|---|
| `LabourState.satisfaction`, event shifts, strike warning, active strikes, record | 0 (or the start value if the start is known); empty |
| Union halving: `union_halving_active`, `union_signed_turn`, `union_grandfathered_ids` | off, 0, empty |
| `target_shifts` | empty |
| Work week | 45 hours |
| `staff_fill` on buildings | 1 |
| `pending_purchases` | empty |
| `ResearchState.licences`, `licensed_out` | every unlocked node in a licence group becomes in-house, with no royalty |
| Legacy perk state | derived by reconcile; the anchor flag lives on the building dict (`legacy_anchor`). Old saves mark the start's furnace if it is still owned |
| `pay_raises`, `strike_free_until` | empty, 0 |
| Expansion Director seat | from `AdvisorState` seats (already saved) |
| Era | derived from the turn and match length (none saved) |
| Seam draw and M | derived each turn (none saved) |

Register every new field in `SaveValidation.FIELDS`.

## 13. Telemetry

Schema bump. Per turn:
- `satisfaction`
- `fill_waiting` (buildings under 70%)
- `strikes` (count, ids)
- `over_cap_sites` (count, max M)
- `royalties_paid`, `licence_income`

Per run: licences bought by kind; strikes total.

## 14. Tests and balance protocol

Every phase is a **mechanic change** under `cnc-balance-change-control`: state intent, record
before and after, unit suite green, e2e with metrics quoted, sweep where the harness exists.
P2, P4 and P5 move many numbers at once, so each starts with `python3 -B
tools/snapshot_balancing.py` (repo CLAUDE.md rule 8).

**Targets** for the Metal Magnate benchmark after all phases *(proposed)*:

| Metric | Today | Target |
|---|---|---|
| Profit/turn at turn 50 | £133 | £106–160 (±20%) |
| Buildings at turn 50 | ~12 | 8–10 (slower by design) |
| Bankruptcy in standard probes | none | none |
| Default-policy Magnate hiring slows | — | around turn 10 |
| Idle-15-turns probe | solvent | solvent |

Pinned strings and tests that change:
- `tests/unit/test_construction.gd:133-139`
- `test_tile_quick_menu.gd:150, 181`
- `test_research.gd:1238`
- Profit Share and labour policy tests

### 14.1 The Stoneshore e2e under Local Suppliers (owner direction, 26 October 2026)

The Stoneshore e2e (`tests/e2e_stoneshore.gd`, scenario `open_field_1`) plays the logistics
progression a player plays: Local Suppliers first, tile stockpiles once Open Logistics Contracts is
earned, Local Suppliers again only when a seam runs out and a nearby mine would cost more.

1. **AC25.1** The run uses the Local Suppliers rules (`logistics_model` `middleman_v1`), as Metal
   Magnate does.
2. **AC25.2** Until Open Logistics Contracts, every building buys its inputs and sells its outputs
   through Local Suppliers, and construction materials come from Local Suppliers. The builder
   checks it can pay the build fee plus the Local Suppliers materials price, so the game never
   refuses a build in silence; a build the game refuses fails the run with the game's reason.
3. **AC25.3** Open Logistics Contracts is earned by play (three goods, 300 units each, through
   Local Suppliers), never granted. The report prints the turn.
4. **AC25.4** On the first turn after the unlock, every input the chain makes for itself (coal,
   iron ore, iron ingots, copper ore, copper ingots, copper wiring, steel, water) switches to its
   tile stockpile, fed by the scenario's output routes. Final goods (motors) and any surplus keep
   selling through Local Suppliers (the global market needs the Import/Export License, out of
   scope).
5. **AC25.5** Coal for the smelters is routed to the smelters' tile, tile_25_5. The layout was set
   for the old free amounts (two mines on a seam that never runs out, the rest on the nearest tile
   with that deposit: coal tile_20_9, copper tile_18_10, iron tile_22_6); at 1.5 free each pair
   now pays about ×1.7. Rightsizing and the fallback only build where a seam has room.
6. **AC25.6** Each turn, for coal and iron ore: when a building's own supply has stopped because its
   seam ran out (a finite seam empty, or collapsed), the run prices a new mine on the nearest tile
   with that deposit and room under its free amount (running cost a unit at that site, plus haul a
   unit to the consumer, plus build fee, materials and land spread over 30 turns) against Local
   Suppliers' delivered price a unit. It builds the mine when that is cheaper, else switches the
   input back to Local Suppliers, and prints both figures and the choice.
7. **AC25.7** A unit test drives that choice both ways on a forced empty seam.
8. **AC25.8** The report prints the unlock turn, each seam's use against its free amount, every
   fallback choice, the profit trajectory and the cost lines. The run passes with no failed checks.
9. **AC25.9** The Metal Magnate benchmark bot uses the same builder, so its builds go through;
   its progression through tile stockpiles is a follow-up.

## 15. Phasing

**Phase gates.** Every phase lands only when:
- the unit suite is green;
- the parse check is clean;
- the e2e has run with its metrics quoted against the previous phase;
- UI phases have windowed screenshots;
- the commit message carries intent, before and after, and evidence (`cnc-balance-change-control`);
- any design-intent stance it touches is amended in the same change, marked "changes design
  stance X, approved by owner".

Phases P2, P4 and P5 start with `python3 -B tools/snapshot_balancing.py`.

| Phase | Name | Depends on | Size |
|---|---|---|---|
| **P1** | Throughput and labour satisfaction | — | large |
| **P2** | Staffing and pacing | P1 | large |
| **P3** | Strikes and accidents | P1 | medium |
| **P4** | Mining and land | P1 | large |
| **P5** | Output bonus conversion | P1 | medium |
| **P6** | Research licensing | P5 | large |
| **P7** | Freight by distance and transport speed | — | medium |

Recommended order: **P1 → P2 → P3 → P4 → P5 → P6**, with P7 slotting in anywhere (after P2 keeps
the pacing work together). One phase at a time, per the owner's one-agent rule.

### P1 — Throughput and labour satisfaction

- **Sim**:
  - the `throughput` Modifiers domain;
  - apply `recipe_input`;
  - replace every `workforce_output_multiplier` site;
  - CostSolver and `tools/balance.py` model throughput.
- **Labour**:
  - knob options rewritten as throughput, cash and satisfaction (§4.4);
  - the Work week knob (§4.4b);
  - the Union knob: Partial, and Comprehensive with halved labour cuts, which splits
    `labour_cost_factor` into cuts and increases (§4.4a);
  - satisfaction metric, target, movement (max of 10% of the gap and 2), event target shifts,
    start values, union step-down costs, Renege on Union Agreements, the
    workforce-size and HR Director contributions, and the +90 output prize;
  - `labour_output_pressure_pct` retired.
- **UX**:
  - top bar Workforce module replaces Council;
  - advisor loyalty moves to the Advisors tab key;
  - Labour tab satisfaction plate, ledger, knob cards, and the seventh and eighth knobs.
- **Save and telemetry**: `SAVE_VERSION` 18 with satisfaction and events; telemetry
  `satisfaction`.
- **Stances**: A2 (labour part), A4.
- **Evidence**:
  - Profit Share no longer dominant;
  - Magnate's default-policy satisfaction crosses −5 around turn 10;
  - e2e profit change at turns 30 and 50 quoted.
- **Interim**: until P2 and P3, satisfaction only drives the +90 prize.

#### P1 acceptance criteria

Each item is checked by a named unit test unless marked otherwise. "Knob" means the People >
Labour tab control.

**Throughput (§3)**

1. **AC1.1** A building with +x% throughput consumes x% more of every input, makes x% more of
   every output and draws x% more power. Its labour and maintenance are unchanged.
2. **AC1.2** `MatchState.run_multiplier(building)` is the single scaling point for inputs,
   outputs and power. It equals the startup factor × (1 + throughput pct / 100). Every former
   `startup_capacity_multiplier` call site in the simulation and its previews uses it.
3. **AC1.3** A `recipe_input` modifier scales that recipe's input quantities (production, Local
   Suppliers orders, cost solver and previews agree).
4. **AC1.4** No labour policy changes output without changing inputs. The only output-only labour
   effect is the +5% prize at satisfaction of +90 or more (AC2.9).
5. **AC1.5** The cost solver, the build forecast, building status, the money panel projection
   and the e2e diagnostics use the same throughput and prize figures as production (same
   quantities for the same building in the same turn).
6. **AC1.6** Mines (`b_001`), oil wells (`b_032`, `b_034`) and offshore oil platforms (`b_033`)
   run at throughput ×1 whatever the labour policies and `throughput` modifiers: their run
   multiplier is the staffing factor alone, their seam draw ignores the policies, and their
   output tooltip lists no throughput. Output modifiers and the +90 prize still raise their
   output. Every other building, the water pump included, is unchanged. (Owner ruling, 30
   October 2026, §3.2a.)

**Labour policies (§4.4, §4.4b)**

1. **AC2.1** Each knob option has exactly the throughput, cash and satisfaction values in §4.4
   and §4.4b. One table-driven test covers every option of all eight knobs: Work effort, Pay
   while idle, Safety, Pensions, Annual bonus, Profit share, Union, Work week. The automation
   switch and the four lockers are covered too.
2. **AC2.2** Minimal safety's +10% throughput and High safety's +5% labour apply only to
   hazardous buildings (`b_001, b_002, b_003, b_008, b_011, b_012, b_013, b_032–b_034`). The
   throughput skips the extraction ones among them (AC1.6).
3. **AC2.3** Profit share costs its share of profit after tax and dividends, as today, and no
   longer changes output.
4. **AC2.4** Work week:
   - new games start at 45 hours;
   - throughput is +5 / +9 / +12 / +14.5%;
   - under either union, labour +10% per level and no satisfaction cost;
   - with no union, −5 satisfaction per level and no labour cost.
5. **AC2.5** Union tiers:
   - Partial gives +15 and Comprehensive +30;
   - both cost labour +10%, rising 1% every 10 turns active, to +25%;
   - they are exclusive;
   - strike protection is stored for P3.
6. **AC2.6** Automation on level 2+ buildings: labour −15%, power +10%, maintenance +10%.
   Satisfaction −10 standing, plus a −10 target shift for 10 turns when switched on.
7. **AC2.7** `labour_output_pressure_pct` is retired: nothing reads it, it is no longer saved,
   and old saves that carry it still load.

**Satisfaction (§4.1–§4.6)**

1. **AC2.8** Target:
   - target = policy contributions + company contributions + active target shifts, clamped to
     −100…+100;
   - each turn satisfaction moves by max(10% of the gap, 2), stops on the target within 2, and
     moves at the same speed both ways;
   - the 10-turn projection matches 10 real ticks.
2. **AC2.9** At +90 or more every building's outputs (not inputs) are +5%. Below +90 the prize is
   gone the same turn.
3. **AC2.10** Company contributions:
   - workers above 5,000 give +5, and above 25,000 +10 in total (`Production.labour_headcount`);
   - an HR Director seat tier of 3 gives +5, tier 1 gives −5, and tier 2 or an empty seat gives 0.
4. **AC2.11** Events are target shifts that expire after 10 turns:
   - demolishing a staffed building −15;
   - selling a building −5;
   - switching automation on −10.
   - Satisfaction itself never jumps for them.
5. **AC2.12** Start values:
   - Metal Magnate +40, with a target of −55 from its presets;
   - Glass Merchant +20;
   - other starts 0.
   - A headless run of Metal Magnate's default policies crosses −5 on turn 8.
6. **AC2.13** Determinism: the same seed and the same actions give an identical satisfaction
   trajectory, including across a mid-run save and load.

**Comprehensive Union, step-downs and renege (§4.4a)**

1. **AC2.14** On signing Comprehensive, every labour reduction then in force is recorded as
   grandfathered:
   - research and mission `labour_headcount` cuts;
   - advisor seat cuts;
   - policy cuts.
   Grandfathered cuts stay at full strength. Reductions gained afterwards count at half.
2. **AC2.15** A grandfathered cut that ends is dropped from the record. A policy switched off and
   on again, or an advisor re-seated, counts as new.
3. **AC2.16** Labour increases are never halved. The 0.40 floor applies after halving.
4. **AC2.17** The halving survives dropping the union. Re-signing Comprehensive while a halving is
   in force keeps the existing record.
5. **AC2.18** Stepping down:
   - Comprehensive → Partial and Partial → None each book a "Union settlement" one-off charge of
     5% of the last 5 turns' average revenue (`LoanState` revenue window);
   - each adds a −15 target shift decaying 0.5 a turn, gone after 30 turns;
   - Comprehensive → None books both;
   - moving up a tier costs nothing extra.
6. **AC2.19** Renege on Union Agreements:
   - offered only with no union and a halving in force;
   - it ends the halving and clears the record;
   - it lowers satisfaction by exactly 50 at once, clamped at −100;
   - it is the only instant change.

**Save and telemetry**

1. **AC3.1** `SAVE_VERSION` 18. Every new field round-trips:
   - satisfaction, target shifts, union tier, halving flag, signing turn, grandfathered ids, work
     week, policy effect state.
   - Version 17 saves migrate: satisfaction from the start if known, otherwise 0; work week 45;
     no union; no halving.
   - `SaveValidation` accepts the new fields and rejects out-of-range values.
2. **AC3.2** The per-turn telemetry row records `satisfaction` locally. It is not added to the
   transmitted whitelist until the owner adds the sheet column (the live Apps Script has fixed
   columns). *Checked by review.*

**UX (§4.7, §4.8)**

1. **AC4.1** Top bar: a Workforce module replaces the Council module in place. It shows:
   - the signed satisfaction figure;
   - a trend arrow;
   - a lamp by band (gold at +90 or more, green at +50 or more, cream from −5, amber from −70, red
     below −70);
   - hover: stage "Workforce", name "Satisfaction N, rising" (falling or steady), detail by band.
   Clicking opens People on the Labour tab.
2. **AC4.2** The People > Advisors tab key carries a lamp while any seated advisor is disloyal.
   That warning leaves the top bar.
3. **AC4.3** People > Labour tab has a satisfaction plate:
   - a dial with band arcs, a needle for current, a marker for target and a ghost needle for the
     10-turn projection;
   - a ledger of every contribution and active shift, with signed values;
   - a band card.
4. **AC4.4** Eight knobs in two rows of four. Each option card shows its throughput, cost and
   satisfaction lines (§4.4, §4.4b copy). Work week cards show the cost that applies now, union or
   no union.
5. **AC4.5** A "Renege on Union Agreements" key appears only when renege is available, and needs
   a confirm step. While a halving is in force the ledger shows "Labour cuts made since turn N
   count at half."
6. **AC4.6** Player copy has no hyphens, semicolons or dashes. Text on navy uses
   `DS.PALETTE.TEXT`. Headers are not smaller or fainter than body text. *Checked by review.*
7. **AC4.7** Windowed screenshots of the top bar and the Labour tab at three states (fast
   hiring, normal, strike territory) are attached to the PR. *Checked by review.*

**Gates**

1. **AC5.1** Unit suite green. Only the two known flaky perf tests may fail. Parse check 0
   failed. No `SCRIPT ERROR` in the unit, e2e or shot logs.
2. **AC5.2** E2E run to turn 100, with revenue, profit and buildings at turns 30, 50 and 100
   quoted against this branch's pre-change baseline.
3. **AC5.3** A probe shows that Profit Share 10% is no longer strictly better than no profit
   share for the Metal Magnate default company over 50 turns.
4. **AC5.4** Design-intent stances A2 (labour part) and A4 are applied to
   `.claude/skills/cnc-design-intent/SKILL.md`. Commits carry intent, before and after, and
   evidence (`cnc-balance-change-control`).

### P2 — Staffing and pacing

- **Staffing**:
  - `staff_fill` starts at the materials claim;
  - 70% to run, linear above it;
  - hired-share wages;
  - bought buildings arrive 80% or 50% staffed;
  - the upgrade rule;
  - the demolish event.
- **Durations**:
  - construction 4 / 5 / 6 by class;
  - `construction_time` domain (floor 2), with Gerald kept;
  - upgrades 5;
  - retrofit 3 / 2 / 3 / 4.
- **Buying**:
  - 2-turn closing, no cancellation;
  - `offer_for_building` replaces the three duplicated transfers;
  - `pending_purchases`.
- **Andrew**: the Expansion Director seat (−3 turns, sites 50% staffed, closing 1 turn).
- **Copy and tests**: construction and quick-menu tests; deposits stop
  charging full rate on partial staffing.
- **Stances**: A3, A6, A7 (closing, 70%).
- **Evidence**:
  - the time-to-first-output table (§7.7) reproduced by the harness;
  - building count at turn 50.

#### P2 acceptance criteria

Each item is checked by a named unit test unless marked otherwise. A "tick" is one turn's
resolution. Fill is `staff_fill`, the hired share of a building's requirement.

**Staffing (§5)**

1. **AC6.1** Fill starts when construction begins: at placement when the kit is already on the
   tile, or at the materials claim for a project that waited for materials. It starts at 0, or
   0.5 while Andrew is Expansion Director. A project still awaiting materials does not hire.
2. **AC6.2** Each tick, before production, fill rises by 1 / fill turns (5, 8 or 12 by the band
   that tick), capped at 1. It rises on the same ticks construction counts down, and keeps rising
   on the finished building. Starting buildings, NPC buildings and anything saved before this
   phase read as fully staffed (a missing key is 1).
3. **AC6.3** Run fraction: 0 below 70% fill, equal to fill from 70%.
   `MatchState.startup_capacity_multiplier` returns it, so `run_multiplier` scales inputs,
   outputs and power by it. A building below 70% does not run, consumes nothing and carries the
   blocked reason code `staffing`.
4. **AC6.4** Labour is charged on the hired share. A building below 70% pays the idle pay share
   of its hired share.
5. **AC6.5** Upgrades:
   - when the works start, fill is rebased to the new level's headcount (×0.67 from level 1 to 2)
     and keeps rising;
   - the building runs at its old level during the works, as today, with output unchanged;
   - after completion its output never falls below the previous level's while fill is under 1;
   - cancelling the upgrade rebases fill back.
6. **AC6.6** A recipe switch keeps fill. Demolition keeps the −15 shift from P1.
7. **AC6.7** A deposit is charged its base draw × the staffing run fraction.
8. **AC6.8** The half capacity start is retired: the Construct switch is gone, nothing saves the
   flag, and saves that carry it still load.
9. **AC6.9** A harness reproduces the §7.7 table exactly: 4, 5 and 6 turn builds at fast, normal
   and slow hiring, with Andrew's package, and a bought building.

**Durations (§7.1–§7.4)**

1. **AC7.1** `build_duration` gives totals of 4, 5 and 6 turns per §7.1. Buildings §7.1 does not
   list: landfill 4, water recycling 5, heat battery 5, recycling plant 5, airport 6.
   Infrastructure stays at 2. A levelled build still adds 2.
2. **AC7.2** A `construction_time` Modifiers domain applies in `effective_build_duration` as
   (turns + add) × mult × (1 + pct / 100), rounded, never below 2 (a shorter unmodified duration
   is kept). Gerald keeps his −1. The search overlay reads `effective_build_duration`. A project
   keeps the duration it started with.
3. **AC7.3** `UPGRADE_DURATION` is 5, and the UI fallbacks read the constant. Infrastructure
   upgrades (roads, rails, pipes, cables) keep 3 turns, like their unchanged construction.
4. **AC7.4** Retrofit turns: base 3, Ops 3 2, Ops 2 3, Ops 1 4. Fees and labour fractions are
   unchanged.

**Buying (§7.5)**

1. **AC8.1** `MatchState.offer_for_building(iid)` is the one purchase path. The market lots, the
   building detail panel and the tile view's port purchase call it. It charges the full price at
   the offer, and there is no cancel.
2. **AC8.2** The building is under offer for 2 turns (1 with Andrew's package). It stays NPC
   owned, leaves the market lots and cannot be offered for twice. Panels say "Under offer.
   Yours in N turns."
3. **AC8.3** Closing happens at the end of the last closing tick. The transfer is today's: owner,
   land, `land_exempt`, seeded stock and Local Suppliers enrolment. Fill is 0.8, or 0.5 if
   satisfaction is below −5 at closing. The building first runs the tick after.
4. **AC8.4** `pending_purchases` is saved, validated and cleared on reset. Older saves load with
   none.

**Andrew Keeler as Expansion Director (§7.2)**

1. **AC9.1** The turn 3 offer has a third choice, Expansion Director. The `expansion_director`
   seat seats only Andrew and appears only while he holds it.
2. **AC9.2** While he holds it, for his 30 turn tenure: construction −3 turns (floor 2), new
   projects start 50% staffed, purchase closing takes 1 turn. No purchase discount and no build
   on credit. Every effect ends with his tenure.

**UI and copy**

1. **AC10.1** Building detail diagnostics show a staffing row while fill is under 1: "Staffed
   64%. Starts at 70%." below 70%, "Staffed 85%. Runs at 85%." from 70%.
2. **AC10.2** The construction view shows the staff hired so far.
3. **AC10.3** A building under offer leaves the market lots. The building detail panel shows
   "Under offer. Yours in N turns." in place of its Buy key, and the tile view's port key says the same.
4. **AC10.4** Panel copy that pins construction at 3 turns reads the real duration.
   Player copy has no hyphens, semicolons or dashes. *Checked by review.*
5. **AC10.5** Windowed screenshots: the staffing row, a building under offer and Andrew's offer.
   *Checked by review.*

**Gates**

1. **AC11.1** Unit suite green, with only known baseline failures. Parse check 0 failed. No new
   `SCRIPT ERROR` in the unit, e2e or shot logs.
2. **AC11.2** E2E to turn 100 with revenue, profit and buildings at turns 30, 50 and 100 quoted
   against P1.
3. **AC11.3** The Metal Magnate probe over 50 turns is quoted against P1 and stays solvent.
4. **AC11.4** Stances A3, A6 and A7 are applied to `.claude/skills/cnc-design-intent/SKILL.md`.

### P3 — Strikes and accidents

- **Strikes**:
  - check every 10 turns, warning at T−2, draw 25% or 50% of buildings weighted;
  - output ×0.4 as a `mult` modifier for 3 turns;
  - strikers at 50% labour cost;
  - called off when satisfaction recovers;
  - pay rises: one building +40% for 10 turns, or every striker +40% for 10 turns with 15 strike-free
    turns;
  - a settled building is quiet for 25 turns, a broken one for 20 (§6.2c);
  - either union blocks strikes.
- **Accidents**: under Minimal safety.
- **UX**:
  - People > Strikes tab;
  - Strikes key lamp;
  - top bar blink during a warning;
  - bell events.
- **Save and telemetry**: strike warning, active strikes, record, pay rises, protection; telemetry
  `strikes`.
- **Stances**: A7 (strikes cut output 60%).
- **Evidence**:
  - seeded draw determinism;
  - strike cost at turn 50 within the §6.1 scale.

#### P3 acceptance criteria

Each item is checked by a named unit test unless marked otherwise. Check turn T is 10, 20, 30…; a
turn's "resolution" is what happens when the player ends it.

**Strikes (§6.1)**

1. **AC12.1** The warning is drawn in the resolution of turn T−3, so the player sees it from turn
   T−2, if satisfaction is below −70. It names ceil(25% × N) buildings, or ceil(50% × N) below −90.
   N counts the player's production and power buildings that are not paused, infrastructure or
   batteries. Projects under construction don't count.
2. **AC12.2** The draw is weighted and seeded: hazardous buildings ×2 while safety is Minimal,
   buildings with an accident in the last 10 turns ×2, others ×1, and the factors multiply. A
   building under a pay rise or in its quiet (§6.2c) is never drawn. The same seed and state give
   the same names.
3. **AC12.3** In the resolution of turn T: below −70 the named buildings strike. If the warning was
   drawn below −90 and satisfaction is now −70 to −90, only the first ceil(25% × N) strike. At −70
   or above the strike is called off.
4. **AC12.4** A strike cuts the building's output 60% for 3 turns (T, T+1, T+2) through a per-building
   `recipe_output` `mult` 0.4 modifier, power plants included. Inputs are consumed in full, a mine's
   deposit is charged in full, and labour costs 50% while it lasts.
5. **AC12.5** A strike that runs its course ends with a +5 target shift for 10 turns.
6. **AC12.6** While a Partial or Comprehensive union is active there is no warning, and a standing
   warning is called off at T.

**Pay rises (§6.2)**

1. **AC13.1** "Raise pay here": labour +40% at that building for 10 turns. Its strike ends at once,
   or it leaves the warning, and it cannot be drawn for 25 turns (AC13.9).
2. **AC13.2** "Raise pay for all strikers": labour +40% at every named or striking building for 10
   turns. Every strike ends, the warning clears, and there are no warnings or strikes for 15 turns.
3. **AC13.3** Neither raise changes satisfaction, its target or the band. A strike ended by a raise
   gives no +5.
4. **AC13.4** Break strike at one building charges 2 turns of its base wages this turn as "Strike
   breaking", ends its strike with no +5 (or takes it out of the warning), shifts the target −5 for
   10 turns and records the round as broken.
5. **AC13.5** Break strike for the whole round ends every strike, clears the warning, charges every
   striker's two turns of wages and shifts the target −20 for 10 turns, with no company wide
   protection after.
6. **AC13.6** The second whole round broken, or the tenth building broken one at a time, adds
   "Routinely broke strikes", a standing −15 in the satisfaction sources.
7. **AC13.7** Only a Comprehensive Union Agreement clears it, with both counts. Partial does not.
8. **AC13.8** A building broken on turn t, alone or in a whole round, is not named or struck at any
   check before turn t + 20, and can be from turn t + 20. Other buildings are drawn as usual, and
   the strike size still counts it.
9. **AC13.9** A building settled on turn t, alone or with every strike, is not named or struck at
   any check before turn t + 25, and can be from turn t + 25. Settling every strike still blocks
   all strikes for 15 turns.
10. **AC13.10** The quiet is saved (`strike_quiet_until`) and validated. Older saves load with none.
11. **AC13.11** A bonus costs half the Settle cost of each building it covers and quiets it for
    `roundi(15 + 5 × satisfaction / 100)` turns: 10 at −100, 15 at 0, 20 at +100. It never
    shortens a running quiet.
12. **AC13.12** The One off building bonus charges its cost this turn as "One off bonus", ends the
    building's strike with no +5 or takes it out of the warning, and leaves satisfaction, its
    target and the strike breaking counts unchanged. It refuses a building it would not lengthen.
13. **AC13.13** The One off bonus covers every building strikes count whose quiet it would
    lengthen, charges their costs as one lump sum and quiets each. It refuses when it covers none.
14. **AC13.14** The cooldown list is the buildings quiet now. The vulnerable list is the named
    buildings while a warning stands, else every counted building that would not sit out the next
    check when its warning is still to be drawn and satisfaction is projected below −70 at the
    draw, else none. A union agreement, or a settlement's 15 turns, empties it.

**Accidents (§4.5)**

1. **AC14.1** Only under Minimal safety, only at hazardous buildings: a 2% chance a turn, rising 0.25
   points each turn Minimal stays on, to 6%. It resets when safety changes.
2. **AC14.2** An accident stops the building for 2 turns (it does not run, blocked reason
   `accident`), shifts the target −10 for 10 turns (stacking), and charges 2 turns of the building's
   wage bill as compensation in that turn's costs.

**State and telemetry**

1. **AC15.1** Saved and validated: the warning, active strikes, the strike record (last 20), pay
   rises, strike free turn, each building's quiet, accident downtime, last accident turns, Minimal safety's run of turns
   and the labour RNG's seed and state. Older saves load with none.
2. **AC15.2** Telemetry schema 7: each turn row carries `strikes`, the number of buildings on
   strike. The receiver appends a `strikes` column. The Settings disclosure names it.

**UI**

1. **AC16.1** People has a third tab, Strikes, laid out as §6.3: the strike risk case, the table
   with its column labels (Location, Output loss, Cost to manage, Action), "All strikes (N
   buildings)" first without the output words, a folded "N buildings" row with each building under
   it, Settle and Break strike on every row as two lines, each cost beside its key,
   each key opening what it does with Confirm and Cancel, the record, and "How strikes work"
   opening the encyclopedia's Mechanics page.
2. **AC16.2** The Strikes key carries no lamp. The sub-tabs read "Upcoming Strikes (N)" (named for a
   strike within 5 turns) and "Ongoing Strikes (N)", and the top bar's Workforce lamp blinks during
   a warning.
3. **AC16.3** Bell events at the warning, a strike's start, its end, a call off and an accident.
   Building detail diagnostics say when a building is on strike or down after an accident.
4. **AC16.4** Player copy has no hyphens, semicolons or dashes, and text on navy uses
   `DS.PALETTE.TEXT`. Windowed screenshots of the Strikes tab with a warning, with strikes on, and
   quiet. *Checked by review.*
5. **AC16.5** Strike planning: the two rows read "Buildings on strike cooldown (N)" and "Buildings
   vulnerable to strikes in next 10 turns (N)", each with a Show key. Show opens that list (and
   shuts the other) with the three suggested actions first: the policies key opens the Labour tab,
   One off bonus has its total beside its key, and each building row has its own bonus cost and
   Bonus key. A Bonus key opens a bed, and Confirm pays it.

**Gates**

1. **AC17.1** Unit suite green with only known baseline failures, parse check clean, no new
   `SCRIPT ERROR`.
2. **AC17.2** E2E to turn 100 quoted against P2. A Metal Magnate probe pushed below −70 shows strikes
   at the check turns and their cost at turn 50 within the §6.1 scale. *Checked by review.*
3. **AC17.3** Stance A7's strike line is applied to `.claude/skills/cnc-design-intent/SKILL.md`.

### P4 — Mining and land

- **Seams**:
  - draw, caps 2 / 4 endless and 3 / 6 finite;
  - M as a multiplier after the labour floor;
  - hard-max scaling;
  - finite seams charged for what is dug.
- **Deposits**:
  - `DEPOSIT_SIZE_MULT` 3 after normalisation;
  - the demo-only Magnate seam at 2,000;
  - finite −30% kept.
- **Land**: `land_units` column and helper; mines 32, factories 20.
- **Seam-running-out card**: deeper shaft, rob the pillars, heavy blasting, sell with reserves.
- **UX**:
  - tile panel deposit line;
  - construct and upgrade dialogs;
  - BDP seam lamp;
  - forecast and CostSolver include M.
- **Stances**: A5, plus the tech-gating spec note (C) and the `production.gd:987` comment (D).
- **Evidence**:
  - the coal cost table (§8.3) reproduced;
  - the demo seam card fires around turn 25.

#### P4 acceptance criteria

Each item is checked by a named unit test unless marked otherwise. A **site** is one deposit good on one
tile; a **working** is one of the player's buildings mining it.

**Seams (§8.1–8.3, §8.9)**

1. **AC18.1** A site's draw is the sum over its workings of level (1 / 2 / 3.5) × staffing run
   fraction (no throughput, AC1.6), 0 for a working down after an accident or offline. NPC buildings never
   draw. A strike does not lower draw.
2. **AC18.2** Every seam, endless (no amount in `tile_properties.csv`, water included) or finite, is
   free to 1.5 and may collapse past 3 (owner ruling 26 October 2026; was 2 and 4, 3 and 6).
3. **AC18.3** M = 1 + c × max(0, draw − free), with c = 1 (+100% a working) unless
   `extraction_cap_cost` modifiers change it. M multiplies the labour (after the 40% floor and the
   strike share) and the maintenance (after modifiers and level) of every working on the site, and
   it is continuous: 0.2 over the cap costs ×1.2.
4. **AC18.4** With labour cut 60% at the floor, M 4 makes labour ×1.6 of base, not ×3.4.
5. **AC18.5** Past the limit nothing is scaled back and M keeps rising. Each turn the seam collapses
   with chance 5% × (draw − max), rolled on a saved seeded RNG: a finite seam loses what remains, an
   endless one stops its mines for 3 turns. (Owner ruling, 26 October 2026.)
6. **AC18.6** A finite seam is charged what is dug: base × level × staffing (no throughput, AC1.6). Yield (`recipe_output`: the −30% penalty, research, strikes) never charges it.
7. **AC18.7** The coal table of §8.3 is reproduced within £0.02 by a test.

**Deposits (§8.4)**

1. **AC19.1** `EconomyConfig.DEPOSIT_SIZE_MULT` 3 multiplies every finite seam after
   normalisation: coal 2,000 → 6,000, iron 4,000 → 12,000, copper 5,000 → 15,000; a coal or iron
   seam above 4,000 in the CSV stays endless.
2. **AC19.2** Under the demo rules (`victory_set` `demo_itch`) Metal Magnate's coal on tile_6_8 is
   2,000, set by the start file's `demo_deposit_overrides`; in a standard match it is 6,000. A
   save keeps whatever remains.

**Land (§9)**

1. **AC20.1** The buildings CSV has a `land_units` column, blank meaning `tile_size_used`, read
   through `Catalog.land_units`. Mines are 32; the industrial factory, electric arc furnace,
   assembly plant, high tech manufactory and consumer factory are 20.
2. **AC20.2** Every simulation land read (building and upgrade checks, land in use, tile room,
   land quotes, building prices, the ledger and tile view figures) uses `land_units`. Art keeps
   reading `tile_size_used`, so no bake changes.

**A seam running out (§8.7)**

1. **AC21.1** When a finite site falls to 25% of its starting size, once per site, a decision card
   offers: Sink a deeper shaft, Rob the pillars, Heavy blasting, Sell with reserves, Carry on (the
   default). The 5-turn runway warning stays as the last notice. Each choice says what it does in
   a few lines led by icons; hovering it opens a plate with the figures phase by phase, including
   what happens after the mines stop.
2. **AC21.2** Deeper shaft: pays two turns of the site's wages plus a level 1 kit at market,
   takes the site offline 2 turns, adds 40% to what remains, then site labour ×1.4 and power ×1.5
   until the seam ends.
3. **AC21.3** Rob the pillars: adds 25%, site labour ×1.5, and each working has a 3% accident
   chance a turn (halved under High safety, doubled under Minimal). When the seam ends the
   workings collapse and are removed with nothing back.
4. **AC21.4** Heavy blasting, each turn, seeded: 25% a double dig (output and charge ×2), 8% a
   roof fall (offline 2 turns), 2% the rest of the seam is lost.
5. **AC21.5** Sell with reserves: the site's workings go to an NPC company; the player is paid
   their building price plus what remains at 50% of market.
6. **AC21.6** The card's state and its RNG are saved. The same seed gives the same blasting.

**UX (§8.8)**

1. **AC22.1** The tile view's deposit line, in units a turn: "Coal seam. Digging 150 a turn. Costs
   rise above 90. May collapse above 180. 4,120 left." (an endless seam: "Never runs out.").
2. **AC22.2** The construct and upgrade dialogs, in units a turn: "Seam output will increase from
   120 to 240. Above 180, deposit may collapse." No build or upgrade is refused for its seam.
3. **AC22.3** Building detail diagnostics, Plant stage: a Seam row, green within the free cap,
   amber over it, red past the limit with its collapse chance.
4. **AC22.4** The build forecast and CostSolver include M.

**Save, telemetry, stances**

1. **AC23.1** Draw and M are derived each turn, never saved. Old saves load with no card
   state.
2. **AC23.2** Telemetry schema 8: each turn row carries `over_cap_sites` and `max_site_m`.
3. **AC23.3** Stance A5, the tech-gating note (§11 C) and the production comment (§11 D) are
   applied.

**Gates**

1. **AC24.1** Unit suite green with only known baseline failures, parse check clean.
2. **AC24.2** E2E to turn 100 quoted against P3. A demo Metal Magnate probe shows the seam card
   around turn 25. *Checked by run.*

### P5 — Output bonus conversion

- **Research**: output nodes become throughput at ×1.5, extraction kept, a few +5% tier III
  capstones (Appendix A). Licence-group members get their differentiated effects but keep
  unlocking by doing until P6.
- **Missions**: output rewards become timed (15–30 turns). Convert the disabled boards before
  enabling them.
- **Legacy**:
  - the Original Furnace anchor and name override for Magnate and Glass Merchant;
  - the reconcile;
  - the copy "While the original furnace is still owned".
- **Stances**: A2 complete, E (building names).
- **Evidence**:
  - e2e profit at turn 50 within the §14 target (£106–160);
  - base recipe margins lifted if needed.

Each item is checked by a named unit test unless marked otherwise.

**Research (§3.2, §3.3, Appendix A)**

1. **AC26.1** Throughput, recipe input and building power modifiers can be scoped to the recipes
   that make a good (`target_match.makes`), so a converted node keeps its old scope.
2. **AC26.2** Every research output node on a building with material inputs becomes throughput at
   1.5× its old percentage, same scope: Continuous-Flow Reactors, Continuous Catalyst
   Regeneration, Atomic Layer Deposition, Coordinated Robot Handoff, Polymer Feedstocks, Chlor
   Alkali Cells, Industrial Salt Purification, Specialist Apprenticeships, Modular Sub-Assembly,
   Crop Rotation Programmes and Micro Silica Synthesis on concrete (+7.5%); Pozzolanic
   Vitrification, Fully-Automated Fabs and Micro Silica Synthesis on glass (+15%); Multi-Stage
   Flash Desal (+30%); Copper Froth Flotation (+7.5% on copper ingots: smelting, not extraction).
3. **AC26.3** Output stays for extraction (the mining yield table, mines, wells, the water pump,
   Block Caving, Enhanced Oil Recovery), for buildings with no material inputs (solar, wind,
   hydro, battery storage, Renewable Dispatch Forecasting) and for hidden recycling (Tertiary
   Filtration, converted when recycling ships).
4. **AC26.4** Tier III capstones give +5% output: Advanced Elastomers (rubber, was +10%), Modular
   Factory Cells, Continuous Improvement Teams.
5. **AC26.5** Licence-group members take their §10.5 effects now, still unlocked by doing:
   - Coal power: Pulverized Coal Boilers coal input −15%; Steam Turbine Upgrades throughput +10%;
     Reheat Turbine Cycles labour and maintenance −10%.
   - Iron and steel: Basic Blast Furnaces furnace throughput +10%; Continuous Casting steel inputs
     −10%; Pulverised Carbon Injection coal input −20% on steel, power +5% on steel.
   - Refining: Fractional Distillation throughput +10%; Catalytic Cracking crude input −10%;
     Specialised Petrochemical Pipelines power −15%.
   - Extraction: Bench Blasting Expansion +5% yield (as today); Bulk Haulage Fleets over-cap cost
     −25% (+100% to +75% a working); Continuous Surface Miners +20% yield on endless seams.
   - Factory: High-Volume Press Lines throughput +10%; Multi-Shift Production throughput +15%
     with labour +10%.
   - EAF: Foamy Slag Practice power −10%; Ultra-High-Power Arcs throughput +15% with power +10%.
   - Solar and wind keep their output.
6. **AC26.6** Each changed node's description in `research_unlocks.csv` and its modifier label say
   what it now does.
7. **AC26.7** A save from before P5 loads with its research modifiers taken from the new table:
   no converted node keeps its old output bonus.

**Missions (§3.3)**

1. **AC27.1** `mm_ship_coal` gives +5% output for 20 turns (was permanent); `t_port` +10% for 15
   turns (was 10); `gp_firm`, `ef_scale`, `br_factory`, `br_chemistry` their output for 20 turns
   (were permanent); `mm_furnace` is unchanged (extraction). Each reward's text names its turns.
2. **AC27.2** A reward already earned in a save keeps what it gave.

**Legacy (§3.2)**

1. **AC28.1** Metal Magnate's furnace on tile_9_9 and Glass Merchant's furnace on tile_18_16 are
   the legacy anchor and are named "Original Furnace"; BuildingNaming honours a per-instance name.
2. **AC28.2** The start perks hold while the Original Furnace is the player's. A per-turn
   reconcile removes them for good once it is sold or demolished; buying it back does not restore
   them. A save from before P5 takes its start furnace as the anchor if it still owns one.
3. **AC28.3** Wherever a perk is shown its condition reads "While the original furnace is still
   owned".

**Stances and gates**

1. **AC29.1** Stance A2 is in the design-intent skill and `docs/building-names.md` has the Original
   Furnace exception (§11 E).
2. **AC29.2** Unit suite with only known failures, parse check clean.
3. **AC29.3** The Stoneshore e2e and the Metal Magnate benchmark are quoted against P4. If the
   benchmark's turn 50 profit is under the §14 target, the recipe margin lift is proposed with
   numbers for the owner rather than applied. *Checked by run.*

### P6 — Research licensing

- **Groups**: `licence_group` column; group members move to a "ready to license" state.
- **Licensing in**:
  - first licence £200, £500 or £2,000 by era (`ERA_SHARES` moved to `EconomyConfig`,
    `era_for_turn`);
  - then 2% and 8% of company revenue for 30 turns, after which they are paid up;
  - in-house via free picks.
- **Licensing out**:
  - max(£50, (10% + 2.5% per other unsold tier II + 5% per tier III) × 5-turn average revenue),
    rate capped at 50%;
  - −2% sale price per licence taken, for 30 turns;
  - 60-turn patent window, no sublicensing.
- **UX**:
  - patent boards in the research panel;
  - licence dialog with payback;
  - Royalties and Licence sales rows.
- **Stances**: A1, B (flat-cost exception).
- **Evidence**:
  - licence income and royalties at turns 50, 150 and 300;
  - the third licence stays a deliberate commitment.

#### P6 acceptance criteria

Each item is checked by a named unit test unless marked otherwise.

**Groups (§10.1, §10.5)**

1. **AC30.1** `research_unlocks.csv` has a `licence_group` column naming eight groups:
   - Coal power: Pulverized Coal Boilers, Steam Turbine Upgrades, Reheat Turbine Cycles.
   - Iron and steel: Basic Blast Furnaces, Continuous Casting, Pulverised Carbon Injection.
   - Refining: Fractional Distillation, Catalytic Cracking, Specialised Petrochemical Pipelines.
   - Extraction: Bench Blasting Expansion, Bulk Haulage Fleets, Continuous Surface Miners.
   - Solar: Utility Solar Arrays, Utility-Scale Inverters, Dual-Axis Tracking Farms.
   - Wind: Onshore Wind Control, Taller Turbine Towers, Tall-Tower Wind Capture.
   - Factory: High-Volume Press Lines, Multi-Shift Production, and the new Near-Net-Shape Stamping
     (Industrial Goods Factory inputs −10%; run 3 distinct factory recipes).
   - EAF: Foamy Slag Practice, Ultra-High-Power Arcs, and the new Eccentric Bottom Tapping (Electric
     Arc Furnace labour and maintenance −10%; run 2 on one tile).
2. **AC30.2** Prerequisites between members of one group are gone (Catalytic Cracking, Continuous
   Casting, Steam Turbine Upgrades, Ultra-High-Power Arcs, Tall-Tower Wind Capture). Prerequisites
   outside the group and the rank gate stay.
3. **AC30.3** Meeting a member's condition makes it **ready to license**, with a notice. It is not
   granted, its effects do not apply and it does not count toward opening the next rank. Once
   ready it stays ready.
4. **AC30.4** `ERA_SHARES` and `DEMO_ERA_SPAN` live in `EconomyConfig`, and the New Game screen
   reads them there. `MatchState.era_for_turn(turn)` gives 1, 2 or 3: turns 1–90, 91–180 and
   181–300 of 300; a demo game counts on the campaign's 300 turns.

**Licensing in (§10.2)**

1. **AC31.1** A ready member can be licensed. Its price is set by the processes already held in
   its group, in-house ones included:
   - none: the era price, £200, £500 or £2,000, once. It is charged in the turn's costs before tax
     as a one-off charge, and the cash must be in hand;
   - one: 2% of company revenue a turn for 30 turns;
   - two: 8%.
2. **AC31.2** A member whose condition is unmet cannot be licensed: no money path skips a
   condition.
3. **AC31.3** Each turn, every royalty licence in its 30-turn term charges its rate on that turn's
   company revenue (goods and power sales), in the turn's costs before tax, used or not. After 30
   charges it is paid up and kept for free.
4. **AC31.4** Licensing grants the node, and its effects apply from that turn.

**In-house (§10.3)**

1. **AC32.1** A free pick on a group member develops it in-house: no fee, no royalty, condition
   not needed (as free picks today).
2. **AC32.2** Nodes outside groups unlock by doing and are in-house. So is a group member granted
   by a mission reward or a cheat.
3. **AC32.3** Free picks spent are kept by `ResearchState` and saved, so a load does not hand them
   back.

**Licensing out (§10.4)**

1. **AC33.1** Eligible: an in-house process of rank II or III, within 60 turns of its development, not
   yet licensed out. Never a licensed-in node, never rank I.
   - A process: a node with a production effect scoped to buildings, recipes or goods, or one that
     unlocks a recipe. A company-wide practice (an effect on every building, such as management and
     staffing) is not one, and neither are logistics, finance or council nodes.
   - The goods a process touches: the market goods made by the buildings and recipes its effects
     target, the goods its effects name, and those made by the recipes it unlocks. Power is sold to
     the grid, so a power plant process touches no market good.
2. **AC33.2** The price is max(£50, rate × the average company revenue of the last 5 turns), where:
   - rate = 10% + 2.5% for each other unsold in-house rank II process + 5% for each other unsold
     in-house rank III process;
   - the rate is capped at 50%.
3. **AC33.3** The sale is paid in that turn's costs phase as revenue before tax, on a
   **Licence sales** line.
4. **AC33.4** Each process licensed out lowers the sale price of every good it touches by 2% for
   30 turns: timed `market_price` modifiers, so two sales that touch steel make −4%.

**UX (§10.6)**

1. **AC34.1** On the research board (DS2), a **Licence groups** drawer pins each group as one row of
   its three drawings. The category drawers keep theirs. Each member's drawing shows:
   - its condition;
   - its state: ready (with a lamp), licensed or in-house;
   - its price: "License for £200", "License for 2% of revenue, 30 turns".
2. **AC34.2** Clicking a ready drawing opens the licence dialog. It shows the price and the payback
   at the company's current buildings ("Costs about £8 a turn. Returns about £6 a turn."), with
   License and Cancel.
3. **AC34.3** Clicking an eligible in-house drawing opens the licence-out dialog. It shows "License
   out for £X", the market consequence (the goods, −2% for 30 turns) and the turns left in the
   patent window.
4. **AC34.4** The old research canvas, which the demo ships, shows the same price and state lines
   and opens the same dialogs.
5. **AC34.5** Free picks read as in-house development ("free developments"), stamped DEVELOPED. A
   licensed drawing is stamped LICENSED.
6. **AC34.6** The money panel and the top bar's money sheet show **Royalties** (a cost) and
   **Licence sales** (revenue). `Production.cash_change_of` and `MoneyPanel.net_cash_of` still
   agree.

**Save and telemetry (§12, §13)**

1. **AC35.1** These round-trip through a save and are registered in `SaveValidation.FIELDS`:
   licences, licences sold, ready members, development turns, sales due and free picks spent.
   - A save from before P6 loads with every unlocked group member in-house and no royalty.
   - Its development turns are unknown and count as turn 0.
2. **AC35.2** Telemetry turn rows carry `royalties_paid` and `licence_income`. The run row carries
   licences by kind. Schema 9.

**Stances and gates**

1. **AC36.1** Stance A1 is in the design-intent skill, and §11 B is in the onboarding spec.
2. **AC36.2** The unit suite has only known failures and the parse check is clean. Windowed
   captures show:
   - the Licence groups drawer;
   - a ready drawing;
   - both dialogs;
   - the money rows.
3. **AC36.3** The Stoneshore e2e plays licensing:
   - it licenses the first ready member of each group its chain uses;
   - it takes a royalty licence only where the estimated return beats the royalty;
   - it licenses out an eligible process when its price beats the sales it would cost (2% of last
     turn's sales of the goods it touches, for 30 turns).
   It reports royalties, licence income and holdings at turns 50 and 100. A 300-turn run reports
   turns 150 and 300. Profit is quoted against P5. *Checked by run.*
4. **AC36.4** The third licence stays a commitment: at the e2e's turn 50 revenue, the 8% royalty is
   above the estimated return of each third member its chain could use. *Checked by run.*

### P7 — Freight by distance and transport speed

- **Cost**: per-tile cost multipliers calibrated to today's legs (§7.6) in
  `transport_cost_for_route` and `freight_per_tile`.
- **Speed**: `INFRA_SPEED_BY_LEVEL` drives transit turns.
- **Local Suppliers**: the trips constant is split from `TRANSPORT_MAX_TILES_PER_TURN`.
- **Audit**: callers of `transport_turns_for_tile_distance`.
- **Stances**: A7 (freight line).
- **Evidence**:
  - total freight within about 10% of today on the e2e;
  - congestion surcharge reported;
  - Local Suppliers prices unchanged.

#### P7 acceptance criteria

Each item is checked by a named unit test unless marked otherwise.

**Owner ruling (27 October).** Shipments take the **cheapest** route; between routes that cost the
same, the one with fewer turns. Today's router takes the fewest turns. Once a level 1 road is no faster
than bare ground, fewest turns would send goods over bare ground at four times the price per tile.

**Cost (§7.6)**

1. **AC37.1** A route's freight is the sum over its legs of tiles × weight × qty × the per-tile
   multiplier for the leg's mode at the level of the tile the leg leaves from
   (`EconomyConfig.FREIGHT_TILE_MULT`): road 0.5 / 0.333 / 0.2, rail 0.125 / 0.083 / 0.056, pipe and
   reinforced pipe 0.5 / 0.333 / 0.2, bare ground 2.0. A fluid on road or rail pays its tanker
   multiplier divided by the same reach. Weight is today's `transport_rate_for_good`.
2. **AC37.2** A whole leg at today's reach costs exactly what it costs today, for every mode and
   level, solids and fluids (2 road tiles at L1, 4 rail tiles at L1, 5 road tiles at L3, 9 rail tiles
   at L3, 2 pipe tiles at L1).
3. **AC37.3** A part leg pays for its tiles only: 3 road tiles at L1 cost 1.5 of today's legs, not 2.
4. **AC37.4** A route with no built leg (the straight-line fallback) pays bare ground per tile: tile
   distance × 2.0 × weight × qty.
5. **AC37.5** `TransportService.freight_per_tile` reads the same table, so the quote the Resources panel
   shows, times the tiles, is the charge on a one-mode route with no research and no congestion.
6. **AC37.6** One constant, `FREIGHT_TILE_SCALE` (1.0), scales every per-tile multiplier: the lever
   if the e2e shows freight moving more than about 10%.

**Speed (§7.6)**

1. **AC38.1** `EconomyConfig.INFRA_SPEED_BY_LEVEL` sets how many tiles one turn-move covers: road
   1 / 2 / 4, rail 3 / 5 / 8, port 8 / 12 / 20, bare ground 1. Pipes are not in the §7.6 table and
   keep 2 / 3 / 5. The `range` column of `infrastructure.csv` matches level 1. A route's transit turns
   are its turn-moves.
2. **AC38.2** Under the default Cheapest setting, shipments take the cheapest route, and between equal costs the one with fewer turns. A
   level 1 road is taken over a shorter run of bare ground while it costs less (up to four times the
   tiles), and rail over road on the same line.
3. **AC38.3** A fluid still takes a pipe route when one exists, and road or rail tankers only where
   the pipework does not reach.
4. **AC38.4** Every panel that shows a mode's reach (building infrastructure rows, the transport tab,
   the Construct build order) reads the speed table, and the cost line reads £ per unit per tile.
5. **AC38.5** In-transit shipments from an old save arrive on their saved countdown and are not charged
   again. A saved leg without a tile count is costed on its hex distance.
6. **AC38.6** The Routing switch sets route choice (owner ruling, 30 October 2026): Cheapest for a new
   game, Fastest the fewest turns then the least freight, Blended the least ½ × freight ÷ cheapest + ½ ×
   turns ÷ fewest. Beside a road detour a turn slower than bare ground, Fastest takes the bare ground,
   Cheapest and Blended the road. Each setting has its own cached route, a fluid still goes by pipe first,
   and each key says what it does.
7. **AC38.7** A save older than version 19 loads on Cheapest. The Stoneshore e2e and the Magnate bot,
   which never touch the switch, run exactly as before. *Checked by run.*

**Local Suppliers (§7.6)**

1. **AC39.1** Local Suppliers trips use `LOCAL_SUPPLIERS_TILES_PER_TRIP` (2), which is not a transport
   speed. Their coefficient and freight rate are unchanged for every tile they trade on.
2. **AC39.2** `TRANSPORT_MAX_TILES_PER_TURN` is gone. `transport_turns_for_tile_distance` uses the bare
   ground speed and gives a route's turns only: nothing prices by turns. *Checked by audit, listed in the
   commit.*

**Evidence and stance**

1. **AC40.1** Stance A7's freight line is in the design-intent skill.
2. **AC40.2** The unit suite has only known failures and the parse check is clean. Windowed captures
   show the reach and cost rows in the transport tab and the build order.
3. **AC40.3** The Stoneshore e2e reports freight by mode, the congestion surcharge, Local Suppliers
   fees and the average transit turns, against P6. Total freight is within about 10% of P6. Local
   Suppliers fees move only as far as what is bought through them moves. *Checked by run.*

## 16. Open questions

All thirteen v2 questions are answered (v3 rulings above). The rest are smaller *(proposed)*
details. They stand unless the owner changes them:

| Area | Proposed detail |
|---|---|
| Licence out | 60-turn patent window; the 2% price drop lasts 30 turns; the rate is capped at 50%; only unsold processes count toward the rate |
| Original Furnace | Glass Merchant's starting glass furnace follows the same rule; the perk is lost for good once the building leaves the company |
| Union agreements | both tiers: labour +10% at once, then +1% each pay round, to +25% |
| Events | each shifts the target for 10 turns |
| Strike pay rises | the all-strikers rise lasts 10 turns (a settled building's 25 turn quiet is the owner's, §6.2c) |
| Expansion Director | construction floor of 2 turns after the −3 |
| Factories | the five factory-class buildings listed in §9 |

**Proposed numbers to sign off as a batch.** The harness tunes them afterwards.

| Area | Numbers |
|---|---|
| Construction | 4 / 5 / 6 turns by class |
| Upgrades | 5 turns |
| Recipe switch | 3 turns (COO 2 / 3 / 4) |
| Purchase closing | 2 turns |
| Transport speeds | §7.6 table |
| Satisfaction | contributions in §4.4; event shifts and their 10-turn length in §4.5; start values in §4.6 |
| Accidents | 2% rising to 6% |
| Throughput conversion | ×1.5 of the old output pct |
| Strike draw | hazardous ×2 |
| Mine land | 32 |
| Balance targets | §14 |

## 17. Not changed by this spec

- Land purchase timing.
- Demolition time.
- Tax and dividends.
- Loans.
- The price-impact ladder.
- Local Suppliers pricing.
- Advisor seats, apart from Andrew's third option.

## 18. Out of scope (discussed, separate specs)

- Research doctrines.
- Building modules.
- The scripted state-owned rival.
- Destination contracts from cities.
- Recycling and landfills, including exhausted pits as landfill capacity.
- Construction crews.
- Labour-policy costs beyond §4.4.

---

## Appendix A — research output nodes and proposed conversion

From `modifier_state.gd` `UNLOCK_MODIFIERS` and the mining-yield table. "Throughput ×1.5" means
the old pct × 1.5 as throughput (§3.3).

| Category | Tier | Node | Today | Proposed |
|---|---|---|---|---|
| Chemistry | I | Chlor Alkali Cells (`b_012`) | +5% | throughput +7.5% |
| Chemistry | I | Multi-Stage Flash Desal (`b_021`) | +20% | throughput +30% (check desal inputs) |
| Chemistry | I | Novel Membrane Filtration (`b_037` pump) | +10% | keep (extraction) |
| Chemistry | I | Fractional Distillation, Catalytic Cracking, Specialised Petrochemical Pipelines (`b_011`) | +5% each | Refining licence group |
| Chemistry | II | Industrial Salt Purification (chlorine) | +5% | throughput +7.5% |
| Chemistry | II | Polymer Feedstocks (`b_013`) | +5% | throughput +7.5% |
| Chemistry | III | Advanced Elastomers (rubber) | +10% | **capstone** +5% output |
| Combustion Power | I | Pulverized Coal Boilers, Steam Turbine Upgrades, Reheat Turbine Cycles (`b_003`) | +5/+5/+10% | Coal power licence group |
| Extraction | I | Bench Blasting Expansion, Bulk Haulage Fleets, Continuous Surface Miners (`b_001`) | +5/+5/+20% | Extraction licence group |
| Extraction | II | Reservoir Stimulation (`b_032`) | +5% | keep (extraction) |
| Extraction | III | Deepwater Drilling, Subsea Tieback, Multiphase Subsea Boosting (`b_033`) | +10% each | keep (extraction) |
| Extraction | III | Enhanced Oil Recovery (crude, 30 turns) | +20% | keep (extraction, timed) |
| Farming & Forestry | I | Crop Rotation Programmes (`b_014`) | +5% | throughput +7.5% |
| Glass, Silica & Concrete | II | Pozzolanic Vitrification (concrete) | +10% | throughput +15% |
| Manufacturing | I | High-Volume Press Lines, Multi-Shift Production (`b_007`) | +5% each | Factory licence group |
| Manufacturing | I | Fully-Automated Fabs (`b_010`) | +10% | throughput +15% |
| Metallurgy | I | Basic Blast Furnaces (`b_002`), Continuous Casting (steel) | +5% each | Iron and steel licence group |
| Metallurgy | I / II | Foamy Slag Practice, Ultra-High-Power Arcs (`b_008`) | +5/+10% | EAF licence group |
| People & Management | II | Specialist Apprenticeships (`b_009`) | +5% | throughput +7.5% |
| Recycling | I | Tertiary Filtration (`b_022`) | +15% | convert when recycling ships (hidden today) |
| Renewable Power | I–II | Utility Solar Arrays, Utility-Scale Inverters, Dual-Axis Tracking (`b_024`) | +5/+10/+10% | Solar licence group |
| Renewable Power | I–II | Onshore Wind Control, Taller Turbine Towers, Tall-Tower Wind Capture (`b_025`) | +5/+10/+5% | Wind licence group |
| Renewable Power | I–II | Perovskite Layered Solar, Bifacial Panel Arrays, Anti-Reflective Coatings (`b_024`), Marine Wind Profiling (`b_026`), Hydro Intake Design (`b_027`) | +5–10% | keep (no material inputs) |
| Renewable Power | II | Battery Balancing (`b_028`) | +10% | throughput +15% |
| Renewable Power | III | Renewable Dispatch Forecasting (15 turns) | +25% | keep (timed, no inputs) |
| Vehicle Production | II | Modular Sub-Assembly (`b_009`) | +5% | throughput +7.5% |
| Vehicle Production | III | Modular Factory Cells (`b_009`) | +5% | **capstone** +5% output |
| (by id) | — | Pulverised Carbon Injection (steel) | +5% | Iron and steel licence group |
| (by id) | — | Micro Silica Synthesis (concrete +5%, glass +10%) | output | throughput +7.5% / +15% |
| (by id) | — | Continuous Improvement Teams (all buildings) | +5% | **capstone** if moved to tier III, else throughput +7.5% |
| (by id) | — | Directional & Horizontal Drilling, Microseismic Monitoring (wells) | +10% / +5% | keep (extraction) |
| (by id) | — | Block Caving (mines on endless seams) | +5% | keep (extraction) |
| (by id) | — | `cfr_chem_output`, `ccr_refinery_output`, `ald_hightech_output`, `crh_assembly_output` | output | throughput ×1.5 |
| Mining yield table | I–II | `yield_*` (coal, iron, copper, limestone, sand, salt, REE, alloy, sulphur, bauxite) | +15% each | keep (extraction) |

## Appendix B — deposit sizes ×3

From `tile_properties.csv`. "Endless" tiles carry no amount and are unchanged.

| Deposit | Tiles (endless) | Finite sizes today | Finite sizes ×3 |
|---|---|---|---|
| Coal | 14 (10) | 2,000 | 6,000 |
| Iron ore | 15 (11) | 2,000; 4,000 | 6,000; 12,000 |
| Copper ore | 11 (7) | 1,000; 5,000 | 3,000; 15,000 |
| Sand | 13 (7) | 1,000; 3,000; 5,000 | 3,000; 9,000; 15,000 |
| Basic salt | 12 (8) | 2,000; 5,000 | 6,000; 15,000 |
| Limestone | 10 (9) | 5,000 | 15,000 |
| Bauxite ore | 8 (5) | 500; 1,000; 2,000 | 1,500; 3,000; 6,000 |
| Alloy ore | 6 (4) | 500; 2,000 | 1,500; 6,000 |
| REE ore | 5 (3) | 500; 2,000 | 1,500; 6,000 |
| Crude oil | 10 (4) | 1,000; 2,000 | 3,000; 6,000 |
| Shale oil | 3 (2) | 2,000 | 6,000 |
| Sulphur | 3 (2) | 2,000 | 6,000 |
| Oil | 1 (0) | 2,000 | 6,000 |
| Water | 123 (123) | — | — |

Base level 1 draw per working: coal 60, iron 40, copper 36, sand 45, salt 25, limestone 25,
bauxite 20, alloy 25, REE 12, sulphur 24, crude 20 (well) / 45 (platform), water 48.
