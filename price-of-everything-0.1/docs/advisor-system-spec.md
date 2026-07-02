# Advisor System — Design & Implementation Spec

> **Status:** design locked (v1), not yet implemented. 2026-07-02.
> **Supersedes:** the v0 roster draft (`carbon_and_capital_advisors.md`). Key departures from v0: **reputation removed**, **star rating is now a derived score function**, stat blocks re-tuned, effects re-expressed as a concrete lever list, seat governance formalised.
> **Prerequisite reading:** repo `CLAUDE.md` (arch rules — determinism, save versioning, balance-constants-are-data), `docs/victory-system-spec.md`.

---

## 1. Overview

Advisors are hired personalities you assign to **seats** (roles). Each advisor has a block of **five discipline stats** (1–3); each seat is **governed by a discipline**, and the advisor's stat in that discipline scales the seat's effects (**3 = strong bonus, 2 = small bonus, 1 = malus**). On top of the seat's generic effect, each advisor carries a **signature specialty** (some passive, some delivered via a mission). The puzzle is placement under scarcity — you never have enough seats or enough high-stat bodies to green everything, and the pool deals you flawed advisors you must find a home for.

**Engine reality today (the starting point):** advisors are *100% decorative*. `permanent_advisor_ids` (`match_state.gd:55`) is a flat array that is saved but **never reaches the sim**; `advisor.role`/`bonuses` are display text; `production.gd:539`'s "advisor bonuses" is a comment naming a future hook. There are no stat fields, no seat map, no advisor→modifier registration. This spec defines all of that.

**Good news from grounding:** the modifier machinery this design routes through (`ModifierState` domains, `duration_turns`, the unlock framework, seeded-RNG save pattern, the additive labour model) already exists and is proven. After removing reputation, **nothing here needs a new reactive subsystem** — it's "author a lot of modifiers + a handful of single-site seams + the seat framework."

---

## 2. Core model

### 2.1 Stats
Five disciplines, each **1–3**:
**Influencing (Inf) · Operations (Ops) · Leadership (Lead) · Innovation (Inn) · Finance (Fin)**.

### 2.2 Star rating — derived score function
`score = Inf + Ops + Lead + Inn + Fin` (range 5–15). Evaluate in this **precedence order**:

1. **≥4 disciplines equal to 3 → 5★**
2. else **score ≥ 12 → 4★**
3. else **score ≥ 10 → 3★**
4. else **score ≥ 8 → 2★**
5. else (score 5–7) → **1★**  *(floor — this subsumes "≥4 disciplines at 1", so 3-ones blocks aren't an undefined gap)*

Star is a **display summary only**, never a mechanic. This function is permutation-invariant (identical stat multisets always map to the same star), which fixes the v0 hand-assignment collision. UI may show the computed star; it will survive reverse-engineering because it is genuinely derived.

### 2.3 Governing rule (the "B+C" model)
- **B — base seat scaling:** each seat reads its governing discipline. **3 = full effect, 2 = ~40–50% effect, 1 = a malus (penalty).** Tune the exact 2- and 1-tier magnitudes per lever in the headless harness. Rationale for "2 = small" over "2 = neutral": it keeps the score-based star *honest* (every point contributes to value) and it means a random draw is never a dead hand — whoever you're dealt is usable somewhere; you're only punished if you *force* a 1 into a seat.
- **C — signature specialty:** on top of the scaled base kit, each advisor has one signature ability that differentiates advisors within the same discipline (e.g. two Fin-3 CFOs both grant the base interest/loan-term bonus, but one's specialty is a one-off cheap loan and the other's is enabling the dividend holiday). Specialties are some passive, some unlocked by that advisor's 10–15-turn mission.

---

## 3. The roster (12 advisors, final tuned stats)

Stats in **Inf / Ops / Lead / Inn / Fin** order. Stars derived via §2.2.

| # | Advisor | Inf | Ops | Lead | Inn | Fin | Score | ★ | Best seat(s) | Signature specialty |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **Vera Ashby** *(sister, starts)* | 3 | 3 | 3 | 2 | 3 | 14 | 5★ | CFO / COO / IR | *Family Trust* — reduced salary, no malus anywhere. The keystone. |
| 2 | **Alexandra Reyes** *(rival, late)* | 3 | 3 | 3 | 3 | 2 | 14 | 5★ | anywhere | *Prima Donna* — superb everywhere; **high salary + walk-risk if benched/under-slotted**. |
| 3 | **Gerald Vance** | 2 | 3 | 3 | 2 | 2 | 12 | 4★ | COO | *Dinosaur* — top operator; **brakes clean-recipe adoption / carbon transition** *(carbon-dependent — later phase)*. |
| 4 | **Eleanor Shaw** | 3 | 2 | 3 | 1 | 3 | 12 | 4★ | HR / COO / Chief Markets | *Beloved* — labour cost via HR + **slows advisor churn (retention)**. Fin 3 body. |
| 5 | **Tom Bracken** *(foreman, starts)* | 1 | 3 | 3 | 1 | 2 | 10 | 3★ | COO / VP Logistics | *Shop-Floor Respect* — extra labour reduction in an Ops seat. |
| 6 | **Sloane Vane** | 3 | 3 | 1 | 1 | 2 | 10 | 3★ | Chief Markets | *Slick* — extra temporary sale-price boost in a markets seat. |
| 7 | **Priya Anand** | 3 | 1 | 2 | 3 | 1 | 10 | 3★ | Sustainability / Research | *Idealist* — amplifies green (subsidy/greenest); **raises short-term spend** *(green-dependent — later phase)*. |
| 8 | **Hitomi Sato** | 1 | 3 | 1 | 3 | 2 | 10 | 3★ | VP Logistics / TD: Mfg | *Flow State* — logistics/mfg optimisation; **extra malus in Inf/Lead seats** (socially inept). |
| 9 | **Marcus Thorne** | 2 | 1 | 2 | 1 | 3 | 9 | 2★ | CFO / Chief Investment | *Leverage* — cheap capital + discounted acquisitions; **debt-risk exposure when reserves run low**. |
| 10 | **Hal Rooker** | 3 | 1 | 2 | 1 | 2 | 9 | 2★ | Government Affairs | *Backroom Deals* — regulatory relief (tax cut; carbon relief when it exists). |
| 11 | **Idris Kohl** | 1 | 2 | 1 | 3 | 1 | 8 | 2★ | TD: Petrochem | *Insufferable Genius* — big recipe efficiency in TD; **empire-wide labour malus unless siloed in a TD seat**. |
| 12 | **Rufus Ashby** *(cousin, starts)* | 3 | 1 | 1 | 1 | 1 | 7 | 1★ | Government Affairs (only) | *Silver Tongue, Empty Suit* — strong Influencing effect; a bad block everywhere else (his stat maluses are the cost). |

**Distribution:** 2× 5★ · 2× 4★ · 4× 3★ · 3× 2★ · 1× 1★ — matches the intended "two 5★, a couple of 4★, several 3★, cluster of 1–2★."

**Finance-3 bodies:** Vera, Marcus, Eleanor (3). Eased from 2, but Vera is a universal keystone and Marcus is only 2★ — so the Finance seats stay a genuine pinch without Marcus being a hard must-hire.

**Trait re-cast note:** v0 traits leaned on reputation/standing/morale, which is removed. Downsides now come from (a) stat maluses (placing an advisor where they're weak), (b) per-advisor salary, and (c) the concrete non-reputation effects retained above (Dinosaur's adoption brake, Idealist's spend, Leverage's debt exposure, Prima Donna's salary/walk, Insufferable Genius's conditional labour malus, Flow State's Inf/Lead malus, Beloved's retention). Sloane/Rufus/Hal lost their reputation-only downsides; they're balanced by weak stats + salary.

---

## 4. Acquisition, seats & determinism

### 4.1 Seats
- **2 seats at game start.** Unlockable **up to 5** via People-management unlocks (mirror the shipped OTM/SHD building-count unlock pattern — see `modifier_state.gd:192` "Operational Team Managers"/"Shift Handover Documentation"). New var `max_advisor_slots` (default 2), raised by unlock; enforced in `MatchState.add`/seat-assignment.
- You **assign an advisor to a role** per slot. A role has a governing discipline and a lever kit (§6). More roles exist than slots, so choosing *which* roles to run is part of the puzzle.

### 4.2 Starting three
Fixed cast, always the same (also satisfies "first 3 draws are deterministic"): **Vera (5★), Tom (3★), Rufus (1★)** — 3 advisors, 2 seats, so you pick which two to seat from turn 1.
> ⚠️ **Open flag:** this is **5★/3★/1★**, not the earlier "5★/2★/1★" — because Tom was promoted to 3★. Alternatives if the 2★ start is wanted: (a) leave Tom at 2★ (revert his Lead 2→3), or (b) swap the starting 2★ to Marcus/Hal/Idris and move Tom to the milestone pool. Currently specced as **5/3/1**.

### 4.3 Milestone acquisition
On first crossing each **profit-per-turn** milestone, gain one advisor drawn from the pool:

`50 · 100 · 150 · 200 · 300 · 400 · 500 · 750 · 1000`

- **Latching:** each milestone awards **once, on first crossing** (dips and recoveries don't re-trigger).
- **Pool:** the 12-advisor roster (3 fixed start + 9 milestones = 12 = whole roster for EA → draw-without-replacement). **Post-EA: grow the pool > 12** so draws become a subset and the endgame roster varies between runs.
- You can end up *holding* up to 12 advisors but only *seat* 2–5 — the puzzle is which to seat and in which role.

### 4.4 Determinism (must-hold — CLAUDE.md rule #3)
Draws use the **match's seeded RNG**, **not** global `randi()`/`randf()`. Mirror the `SpecialOrderState` pattern: persist `rng_seed` + `rng_state` in the save so draws replay identically on load and the balance harness can reproduce timelines.
- Consequence: a reload gives the **same** draw (anti-save-scum by default). If rerolls are ever wanted, advance the stream deliberately.
- **Fix the latent bug:** `match_state.gd:901` currently calls raw `randi()` — a standing rule-#3 violation; route it through the seeded RNG as part of this work.

---

## 5. Labour system changes (ships with / ahead of the advisor MVP)

Labour is the single biggest running cost and is attacked from multiple additive sources. This hardens it.

### 5.1 Dual-source advisor labour reduction
- **COO (Operations)** — up to **−10%** at Ops 3 (shop-floor efficiency).
- **HR Director (Leadership)** — up to **−10%** at Lead 3 (morale/policy).
- Both are `labour_headcount` pct modifiers; they **stack additively** (up to −20% combined), consistent with the shipped additive model (`labour_policy_factor()` / `labour_cost_factor()` — slider + policy + headcount deltas add, no compounding).
- Scale by the 3/2/1 curve: 3 = −10%, 2 = ~−5%, 1 = a labour *penalty*.

### 5.2 Labour floor — `LABOUR_FACTOR_MIN = 0.40`
All labour reductions stack additively across: COO + HR advisors, the OTM/SHD unlocks (−10%/−10%), workforce policies, and the 0.8–1.2× slider. Left unchecked the factor can approach zero (free labour). **Clamp the final labour factor to a minimum of 0.40** (40% of base). Implement in the labour-factor computation (`production.gd` `labour_cost_factor()` / `labour_policy_factor()`): `factor = maxf(EconomyConfig.LABOUR_FACTOR_MIN, 1.0 + sum_of_deltas)`. Add `const LABOUR_FACTOR_MIN := 0.40` to `economy_config.gd` (balance constant — surfaced per rule #7).

### 5.3 Debug/test cheat — `labour_cost −60% for 10 turns`
A dev cheat that adds a **−60%** labour modifier (same additive semantics as any other modifier, applied to *base* labour cost) with **`duration_turns: 10`** (auto-pruned in NARRATIVE, per `modifier_state.gd:354`). Because a single −60% lands exactly on the 0.40 floor (1 − 0.60 = 0.40), this one cheat exercises **both** the clamp and the flag (§5.4) instantly. Trigger via the existing debug path (dev keybind / debug menu — implementer's choice); gate behind a debug flag so it can't fire in normal play.

### 5.4 People-panel flag at the floor
When the computed labour factor is **clamped at 0.40** (i.e. the raw summed deltas would push below it), the **Labour tab of the People panel**, directly under the labour-cost indicator, shows:

> **Maximum labour cost reduction achieved. Further bonuses will not stack below 40% of base cost.**

Wire in `people_panel.gd` off the labour-overview data (extend `Production.labour_overview()` to return an `at_floor: bool`).

---

## 6. Seats → governing discipline → lever kit

Each seat reads its governing discipline (3/2/1 scaling). **Rigid** seats read one discipline; **flexible** seats read the **best of** several (this reduces dead-hands for the random draw and pushes the real scarcity onto the rigid seats).

### Rigid seats
| Seat | Governs | Lever kit |
|---|---|---|
| **CFO** | Finance | loan interest ↓, loan duration, dividend holiday (10/20t) |
| **COO** | Operations | labour cost ↓ (−10% cap), maintenance ↓, energy cost ↓ (buy + draw), energy sales price ↑, **retrofit/retooling** cost+speed (§7) |
| **VP Logistics** | Operations | transport cost ↓, throughput ↑, distance-per-turn |
| **HR Director** | Leadership | unlock unique labour policies, workforce morale/retention, labour cost ↓ (−10% cap) |
| **Technical Director** | Innovation | recipe output ↑ **for a chosen discipline/category** (the OP-guard), free tech unlock in it |
| **Research Director** | Innovation | free tech unlocks across disciplines |
| **Government Affairs** | Influencing | temporary tax reduction, green-energy subsidy, carbon-tax relief + forewarning *(carbon-blocked)* |

### Flexible seats (read best-of)
| Seat | Governs (best-of) | Lever kit |
|---|---|---|
| **Chief Investment** | max(Finance, Innovation) | one-off low-interest loan, land + building purchase value ↓, construction + upgrade capex ↓ |
| **Chief Markets Officer** | max(Influencing, Finance) | market spread ↓, temporary per-good sale-price boosts ↑, special-order forewarning, building-sale forewarning |
| **Sustainability Officer** | max(Influencing, Operations, Leadership) | greenest-track push, green-sales premium, clean-adoption discount (stacks with COO retrofit) *(mostly green/carbon-dependent — later phase)* |

> **Multi-governed resolution:** specced as **best-of eligible disciplines** (the advisor uses their highest applicable stat to set the 3/2/1 tier). Alternative if preferred: player *chooses* which eligible discipline governs when seating (more agency, more UI). **Confirm before build.**

**Coverage / scarcity:** Finance and Influencing are the broad homes; **Innovation and Leadership are narrow and high-impact** — which is the scarcity that makes the puzzle. Finance being both scarce *and* controlling the most capex is intended tension. **Harness must verify** no five-advisor board greens all rigid seats across the profit *and* Greenest strategies (flexible seats ease dominance — watch this).

---

## 7. Retrofit / retooling mechanic

Changing a **built** building's active recipe (a "retrofit"). No such action exists today — recipes are fixed at build time (`build_mode.gd`). This adds a post-build recipe-change action + a new building state.

### 7.1 New building state: **Retooling**
While retooling, the building produces nothing and incurs a **reduced per-turn labour cost** plus a **one-off money fee**. On completion it runs the new recipe.

### 7.2 Timing hierarchy
| Action | Turns |
|---|---|
| Full construction | **3** *(was 2 — directed `build_duration` change; balance-surfaced per rule #7)* |
| Retrofit (change recipe) | **2** |
| Advisor-accelerated retrofit (Ops 3) | **1** |

### 7.3 Cost tiers — governed by **Operations (COO)**
Keyed off the seated Ops advisor's stat (base = no relevant advisor seated). Labour % is **per-turn while retooling**; £ is a **one-off**.

| Governing Ops stat | Labour (per turn) | One-off £ | Turns |
|---|---|---|---|
| **Base** (no seat) | 50% | £25 | 2 |
| **3** | 30% | £15 | **1** |
| **2** | 30% | £15 | 2 |
| **1** (malus) | 75% | £40 | 2 |

Note the lever-specific curve: 2 matches 3 on **cost**, the 3-tier's edge is purely **speed** (1 turn); a 1 is *worse than base*. New `economy_config.gd` constants for the retrofit labour fractions + money fees.

---

## 8. Green building set (for the green-energy subsidy)

Subsidy-eligible: `solar_farm` (b_024), `onshore_wind_farm` (b_025), `offshore_wind_farm` (b_026), `battery` (b_028, electrochemical), `heat_battery` (b_029, thermal).
- **Hydro (b_027) is excluded** — carved out for a later free content update.
- **Keep two lists:** batteries *store*, they don't *generate* — fine for a construction subsidy, but do **not** add them to the victory generation-share calc. The victory track's `GREEN_BUILDINGS` (`victory_state.gd:46`, currently solar + 2 wind) stays generation-only.

---

## 9. Implementation map (FREE / SMALL / NEW / BLOCKED)

Classified against the live engine. "FREE" = author a modifier dict on an existing domain; "SMALL" = one hook line or one new single-site domain (~10–20 lines, same `ModifierState` idiom); "NEW" = a genuinely new mechanic; "BLOCKED" = depends on an unbuilt system.

### FREE — live `ModifierState` domains
| Lever | Domain | Note |
|---|---|---|
| Labour cost / headcount | `labour_headcount` | live |
| Output from specific recipes (TD) | `recipe_output` | `target_match` by category (`recipes_all.csv` col 30) |
| Maintenance | `maintenance` | live |
| Infra efficiency (cost + throughput) | `transport_cost` / `transport_throughput` | live, routed |
| Energy draw reduction | `building_power` | live (reduces `energy_req`) |

### SMALL — one hook or one new single-site domain
| Lever | Hook site | Note |
|---|---|---|
| Temporary market sale-price boost (per good) | `production.gd:816` sell path | `market_price` domain **and** `duration_turns` already exist but the domain isn't applied on sale — **one line** lights up all temp-boost effects |
| Loan interest / term / one-off cheap loan | `loan_state.gd` `take_loan()` (:38) | interest baked at issue; add `interest_rate_override` or a `loan_interest` domain read |
| Dividend holiday / temporary tax cut | `production.gd` `_apply_tax_and_dividends()` (~:373–385) | `TAX_RATE`/`DIVIDEND_RATE` are const; add a domain or a `*_holiday_turns` counter |
| Land purchase cost | `match_state.gd` `purchase_tile_land()` (`LAND_PATCH_COST` :1456) | new `land_purchase_cost` domain |
| Building purchase value | `building_market_panel.gd` `_do_buy()` / `building_price.gd` | new `building_purchase_cost` domain |
| Construction + upgrade cost | `world_map.gd` (build charge) / `building_levels.gd:95–109` + `match_state.start_upgrade()` | modifier on the material kit / money cost |
| Grid buy price + energy sales price | `power.gd` `settle_grid_transactions()` (:84–107) | new `grid_pricing` seam (`GRID_BUY_PRICE`/`GRID_SELL_PRICE` const) |
| Market spread | `market_state.gd` `get_buy_price()` (:26–29) | new `market_spread` domain (`MARKET_BUY_MARKUP` const) |
| Free tech unlock (scoped by discipline) | `match_state.gd` `grant_unlock()` (:1086) | grant the category's gated unlock(s) directly; categories exist |
| Forewarning: special orders | `special_order_state.gd` (schedule is seeded/deterministic) | add `upcoming_orders(turns_ahead)` that forks the RNG state to peek — pure read |
| Forewarning: buildings on sale | `building_market_panel.gd` `_collect_npc_buildings()` | pool is seeded at match start → data exists, just a UI reveal |
| Advisor slot unlock (2→5) | new `max_advisor_slots` + unlock (OTM/SHD pattern, `modifier_state.gd:192`) | enforce in seat assignment |

### NEW — a small new mechanic
- **Seat / role framework + stat blocks + specialties** — the advisor core: `seat_id → advisor_id` dict (replace flat `permanent_advisor_ids`), static seat→discipline table, 5 stat fields + traits/specialties as static data, and an **idempotent `reconcile_advisor_modifiers()`** (deterministic modifier ids like `advisor_seat_CFO`, **remove-then-add** on any change, re-run on save-load and on advisor departure — `Modifiers.add` auto-ids when none given, so naive re-adding **duplicates** effects).
- **Retrofit / retooling** — new building state + recipe-change action + timing/cost (§7).
- **Green-energy subsidy** — nothing tags a good/building green-for-subsidy today (`green_sales_premium` is an all-zero unused column); reuse a `GREEN_BUILDINGS`-style list; apply as a construction cash grant or sale premium.
- **Unique labour policies** — the 8-policy system exists (`match_state.gd:38`) but nothing gates/unlocks policies; add `unlock_workforce_policy()` + author new policy defs.
- **Per-advisor salary** — replace flat `ADVISOR_COST_PER_TURN := 2.0` (`match_state.gd:54`; summed in `production.gd` `_apply_advisor_costs`) with a per-advisor cost field.
- **Advisor churn / retention / walk** — hiring is one-way today (`happiness` is unused flavour); needed for Alexandra's walk-risk + Eleanor's retention. Depends on the seeded RNG.
- **Labour floor + cheat + flag** — §5.
- **Mission system** — the recruit/upgrade + specialty-delivery vector (10–15-turn missions). Largest net-new; defer past MVP.

### BLOCKED — needs the carbon subsystem (does not exist)
- **Carbon-tax relief + forewarning** (Hal), **Dinosaur** adoption brake (Gerald), **Idealist** subsidy timing (Priya). There is no carbon tax, no scheduled ratchet, no clean/dirty recipe tagging (`co2_tax_multiplier` is an all-zero unused column; no turn-90 event). These wait until the carbon system is built.

---

## 10. Save schema & migration
One clean **`SAVE_VERSION` bump (v3 → v4)** with a migration:
- Add `seat_id → advisor_id` map, `max_advisor_slots`, per-advisor `loyalty`/salary, and the advisor-draw `rng_seed`/`rng_state`.
- Stats + traits are **static data** (from advisor defs), not saved.
- Migration: default empty seat map + `max_advisor_slots = 2`; map or clear legacy `permanent_advisor_ids` (verify `_sanitize_advisor_ids`' drop-unknown behaviour doesn't silently empty a loaded board).
- `ModifierState.import_state` already round-trips advisor modifiers.

---

## 11. UI requirements (non-negotiable)
Before committing a placement, show: **the pentagon (5-stat radar), the governing discipline for the seat, and a live preview of the resulting bonuses/maluses** (including which discipline governs a flexible seat). Without the preview the puzzle is guesswork. Plus: the Labour-tab floor flag (§5.4), and the milestone-advisor arrival prompt. Existing 4 portraits (`assets/advisors/`) are a **stub** — the 12-advisor art expands later; use placeholders meanwhile.

---

## 12. MVP & sequencing

**Tier-A (ship first — real, fakes nothing):**
1. **Seat framework** — seat map, seat→discipline table, 5 stat fields + specialties as static data, idempotent `reconcile_advisor_modifiers()`, `max_advisor_slots` + slot-unlock.
2. **Labour hardening** — dual-source COO/HR labour, `LABOUR_FACTOR_MIN = 0.40`, the −60% debug cheat, the People-panel floor flag (§5). *(Independent of the rest — can land immediately on the live labour system.)*
3. **FREE-domain levers** — labour, maintenance, transport, recipe-output (TD), energy draw.
4. **The one-line `market_price` activation** at the sell path → all temporary sale-price boosts.
5. **Per-advisor salary.**
6. **Retrofit/retooling** (§7) + `build_duration 2→3`.
7. **UI:** pentagon + governing-stat + preview.
8. **`v3→v4` migration** + seeded-RNG draw plumbing.

**Tier-B (fast follows):** SMALL financial/market seams (interest/loans, dividend/tax, purchase/construction/upgrade costs, grid pricing, market spread), forewarning peeks, unique-policy gating.

**Deferred / gated:** green-energy subsidy + Sustainability seat (needs green tagging), churn/retention/walk (needs RNG + loyalty), the mission system, and **everything carbon-blocked** (Hal/Gerald/Priya signatures) until the carbon-tax/ratchet subsystem exists.

---

## 13. Open questions to close before/at build
1. **Multi-governed resolution** — best-of (specced) vs player-picks-discipline?
2. **Starting trio** — accept 5★/3★/1★, or restore a 2★ start (revert Tom, or swap the starting 2★)?
3. **Sustainability seat** — keep as the flexible green-champion (specced), or fold its powers into Innovation + Influencing and drop the seat?
4. **Retrofit discipline** — confirmed **Operations**; re-confirm it shouldn't also be a flexible best-of(Ops, Innovation) seat.
5. **Mission cadence** — do the 10–15-turn missions gate specialty *unlocks*, recruitment, or both?

---

## 14. Traceability
Grounded evidence: `match_state.gd` (advisor defs ~3050+, `permanent_advisor_ids`:55, `ADVISOR_COST_PER_TURN`:54, `add_advisor`:3027, `grant_unlock`:1086, `LAND_PATCH_COST`:1456, latent `randi()`:901, workforce policies:38), `production.gd` (:816 sell path, `_apply_tax_and_dividends` ~:373, `_apply_advisor_costs`, labour factor ~:1047, :539 future-hook comment), `modifier_state.gd` (live domains; `duration_turns`:354; OTM/SHD:192), `economy_config.gd` (const `TAX_RATE`/`DIVIDEND_RATE`/`GRID_BUY_PRICE`/`GRID_SELL_PRICE`/`MARKET_BUY_MARKUP`/`LOAN_INTEREST_RATE`/`LOAN_TERM_TURNS`), `loan_state.gd` (:38 issue, :155 capacity), `power.gd` (:84 `settle_grid_transactions`), `market_state.gd` (:26 `get_buy_price`), `building_levels.gd` (:95 upgrade kits), `build_mode.gd` (recipe at build time), `building_market_panel.gd` (`_do_buy`, `_collect_npc_buildings`), `special_order_state.gd` (:15 seeded RNG + spawn schedule), `victory_state.gd` (:46 `GREEN_BUILDINGS`), all-zero `co2_tax_multiplier`/`green_sales_premium` columns in the Goods CSV.
