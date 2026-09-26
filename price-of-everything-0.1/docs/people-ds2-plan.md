# People panel: how it is used, what it holds, and a DS2 arrangement

Status: planning, 26 September 2026. Nothing of the DS2 look is built. One concept study is rendered (§5): render set `peoplestudy`, seed 437, in `tools/button_mockup/cluster.html`, not a game layer. Figures in it come from the captures in `artifacts/people_ds2/before/`, except the doors' headcounts, which are illustrative.

Read with `docs/ds2-theme.md` (the look, the kit, §13 and §14 for the method), `docs/ds2-owner-decisions.md` (settled rulings, including Digital displays) and `docs/tile-view-ds2-plan.md`, the model for this plan.

## 0. The brief

The owner, 26 September 2026: "I think people might like a combination of the cabinet look + doors + general worker-themed metaphors. For advisors I recommend a table or board room with seats."

So the Labour tab takes the cabinet (painted steel), Building Detail's factory doors and the works' own things: a time clock and time card, a shift bell, lockers, a union notice board, the white knob for any choice of three to seven options (icons on its arc) and slide switches for on or off. The Advisors tab is a boardroom table seen from above, a seat per role, each place carrying its role's nameplate; a filled seat shows the portrait, stars, salary and net benefit on LEDs, and a lamp. Both tabs share one shell and one width.

This plan adds no new player action. It adds one new figure, the headcount by kind of worker on the doors, which is an owner decision (§8.8).

## 1. How it is used

### 1.1 The ways in

| Way in | From | Lands on |
|---|---|---|
| People on the bottom bar, or P | `bottom_menu.gd` `_on_people_pressed` | the tab last shown (the panel is built once and hidden, so the TabContainer keeps its tab) |
| The top bar's Council module | `top_bar.council_widget_clicked` → the same handler | the same |
| The tutorial's Advisors chapter | `tutorial_steps.gd` `advisors_intro` → `advisors_effect`: spotlights `PeopleButton`, waits for `PeoplePanel` visible, then the seat choice and bonus preview | Advisors |
| The founder's decision (turn 3) | `DecisionState`; the council refuses hires before it | Advisors |

Nothing opens Labour directly, and no telemetry records opens, tab switches or actions.

### 1.2 The jobs it does

1. **Staff the council**: see who sits where and whether each seat pays for itself; hire into a seat, reassign, unseat, dismiss.
2. **Set workforce policy**: effort, pay while idle, safety, pensions, bonus, profit share, automation, and four other policies.
3. **Watch the labour bill**: what labour costs a turn, against the base, and where it is heading.

## 2. What each tab holds today

The panel is 1220 logical px wide in a copper pipe frame, a TabContainer with Advisors first. `people_panel.gd` is 2030 lines, of which the live part is the shell (about 130); the rest is legacy code kept inert (§3.9). The tabs are `advisor_council_tab.gd` and `labour_policy_tab.gd`.

### 2.1 Advisors (`advisor_council_tab.gd`, three views: roster, picker, detail)

| Zone | Figures (source) | Actions |
|---|---|---|
| Council strip | seats filled of the cap: 2 / 2 (`advisor_seats.size()`, `max_advisor_slots`); council mood when the demo is unlocked | **Add new advisor** → picker |
| Filled seat card | portrait (`ADVISOR_DISPLAY.portrait_path`: Vera is `natasha.png`, Tom `lance.png`), name, role chip, the FIRST seat effect only ("-25% loan interest", `advisor_seat_effect_list(...)[0]`), stars (`advisor_star_by_id`: 5 and 2), preview bonuses (`advisor_bonus_preview_per_turn`: £0.00 and £27.80), salary (`advisor_cost_for`: £10.36 each), net = bonus less salary (−£10.36, +£17.44); loyalty meter when the demo is unlocked | the card → detail |
| Empty seat card | seat monogram, name, lever kit (`SEAT_DEFINITIONS.lever_kit`), "Locked" or "+ Assign advisor" | → picker for that seat |
| Picker | candidates (benched, then recruited), each with portrait, stars, fee | a card → detail |
| Detail | portrait, stars, fee, loyalty and missions (demo), seat choice chips, bio, skillset bars (1 to 3), the financial preview and bonus table for the chosen seat, agenda (demo) | **Hire & assign** / **Assign to seat**, **Reassign seat**, **Unseat (keep on payroll)**, **Dismiss** |

### 2.2 Labour (`labour_policy_tab.gd`)

| Zone | Figures (source) | Actions |
|---|---|---|
| Work effort | 0.8x Lean, 1.0x Standard, 1.2x Overtime (`LabourState.labour_multiplier`) and the chosen one's caption | three buttons |
| Worker pay while building not running | 50%, 75%, 100% (`idle_labour_pay_share`) | three buttons |
| Safety, Pensions, Annual bonus, Profit share | three rungs each (`workforce_policies`, exclusive groups) | three buttons each |
| Automation | Push / Don't push (`push_automation`) | two buttons |
| Labour cost per turn | £158.84, "100% of base", "10-turn estimate £158.84 (+0.00)" (`Production.labour_overview()`) | none |
| Other policies | Extended Annual Leave, Generous Parental Leave, Long Tenure Awards (needs a seated HR Director), Stock Options (an HR advisor's mission) | four toggles, the last two locked in the capture |

## 3. Findings

1. **The labour card's percentage and estimate never move.** `labour_policy_tab.gd` reads `base_total` and `est_ten`, but `Production.labour_overview()` returns `base` and `est_10_turns`. So the card always says "100% of base" and a 10-turn estimate equal to today, with +0.00. With Tom seated as COO (labour headcount −10% at tier 3), the true figure is nearer 90% of base.
2. **The labour cost is not the charge.** `labour_overview()` re-derives the factor inline: it skips the idle pay share, paused and retooling buildings, and the instance in the modifier context that `labour_cost_factor` passes. The turn charges `_calculate_labour_cost(b) × idle share` in `maintenance_labour`, and `CashCommitments` repeats that. Three copies, and the one the panel shows is the odd one out (DS2 rule 10).
3. **A seat card shows one effect of several.** Vera as CFO also cuts dividends by 40%; Tom as COO also cuts maintenance 10%, power 8%, grid imports 10% and lifts grid exports 10%. The card prints only the first.
4. **Vera's worth is invisible.** The loan interest cut is not a ledger line, so `advisor_bonus_preview_per_turn` values it at £0 and her net reads −£10.36 for as long as she sits. The preview should value interest saved on loans taken while she is seated.
5. **Every advisor costs the same.** `advisor_cost_for` is a £10 base grown 0.4% a turn plus 1% of revenue, for anyone. Vera's specialty says "reduced salary"; the roster's salary field it relied on is retired.
6. **"Locked" means two things.** An empty seat shows "Locked" when the council is full (`at_cap`), and seats the research has not opened are hidden entirely, except when advisors are unlocked, as in the capture. Two states, one word, one of them invisible.
7. **Copy and contrast.** Captions carry middle dots, dashes, minus signs and "±" ("Salary cost ±0% · output pressure recovers…", "Regulation compliance — no output…", "10-turn estimate"); section labels are `TEXT_DIM` and `TEXT_MUTED` on navy, against `CLAUDE.md`.
8. **Automation is a two-option spectrum** drawn as two wide buttons; it is an on or off policy.
9. **Dead weight.** About 1,800 lines of `people_panel.gd` are the legacy labour grid and card roster, inert while their node references stay null.
10. **Nothing counts people.** The panel prices the workforce but never says how many work, though every recipe carries unskilled, skilled and high skilled headcounts.

## 4. The arrangement

**Principles.** One shell, one width, two tabs swapped in place. Each figure from the engine (§6). A seat's lamp and words from one status helper. Show only what informs: a locked seat shows its levers, not empty LEDs.

- **Header (fixed):** the PEOPLE nameplate, the two latching tab keys (the open one sunk and darker), Close. The ribbed seam under it; the body scrolls.
- **Advisors:** the council strip (seats filled on a drum, payroll on an LED, Add advisor), then the table: five places a side in `SEAT_DEFINITIONS` order, CFO first. The picker and the detail become sheets over the table (the DS2 sheet pattern), not views that replace it.
- **Labour:** the labour cost first (it is the reason to be here), the workforce beside it, then the policy knobs with the notice board explaining the knob under the cursor, then automation and the other policies.

## 5. The DS2 concept

Study: `artifacts/people_ds2/people_study_v1.png` (both tabs side by side, each 1500 layout px = 800 logical, the fold at the tile view's 912 px marked). The shell is a painted steel cabinet in machinery green, three bolted sheets with two hinges down the left edge, chipped at its edges.

### 5.1 Advisors: the boardroom

| Part | Metaphor | What it is on screen |
|---|---|---|
| Council strip | the board's clerk's desk | a gunmetal plate: "Seats filled" on a drum (2) "of 2", "Payroll" £20.72/turn on a red LED, the **Add advisor** keycap |
| Table | the boardroom from above | an oxblood carpet bay, a polished walnut table with a brass inlay, a black leather chair at each place |
| Place | the director's blotter | green leather, stitched; the role's **brass nameplate** engraved navy at its head |
| Filled seat | the director at their place | chair pulled out; the **portrait** under glass in a brass frame; a **pilot lamp** (green: pays for itself; amber: costs more than it returns); name; **stars** raised in brass, the rest engraved; the seat's effect in words; **Bonus, Salary, Net** on LEDs (Vera 0.00, 10.36, −10.4; Tom 27.80, 10.36, 17.44) |
| Locked seat | the empty chair | chair pushed in; the nameplate on the bare table; a closed leather folder under a **brass padlock**; the seat's levers printed beside it |
| Picker, detail | the dossier | a sheet sliding over the table: candidates as files; the detail as an open dossier with seat choice keys and the guarded Hire key |

### 5.2 Labour: the works

| Part | Metaphor | What it is on screen |
|---|---|---|
| Labour cost | the **time clock** | a hammertone housing: the dial, a **time card** in its slot, "Labour cost" £158.8/turn and "In 10 turns" £158.8/turn on LEDs, "Of base" 100 % on a drum |
| Floor alarm | the **shift bell** | a red bell with a pilot lamp under it, lit when labour reaches its floor (40% of base, `at_floor`) |
| Workforce | Building Detail's **factory doors** | three doors, Unskilled, Skilled, High skilled, the headcount engraved on each kick plate, the glass lit where people work (study counts illustrative) |
| Policies | the plant's **selector knobs** | six white knobs on a gunmetal plate, three icon options on each arc, the chosen icon cream, the others dim: Work effort (hours), Pay while idle (a banknote's share), Safety (shields), Pensions (bars), Annual bonus (gifts), Profit share (a pie) |
| Effects | the **union notice board** | cork in a timber frame, index cards pinned: the knob under the cursor on top, then each policy in force, navy print |
| Automation | a **slide switch** on a plastic case | hands on the left, machines on the right, off |
| Other policies | the **lockers** | four painted lockers, each a name card in a brass holder and a slide switch; a locked policy has a padlock through its hasp and its reason on the card ("Needs an HR Director", "Opens with an HR mission") |

**Width: 800 logical px (1500 layout).** Today's 1220 covers most of a 1920 screen and leaves the map behind it. 800 is the tile view's width, the widest DS2 surface, so the People panel reads as the same family of cabinets. It is the narrowest width at which five places sit a side at 134 logical each with a 64 × 80 portrait and a five cell LED at the game's size, and at which two knobs with their icon arcs sit side by side. At 600 (Construct) a side would need four places and the table two rows of five would not fit.

**Ink.** White with a dark shadow on the painted steel, leather, walnut, gunmetal and plastic; navy on brass, paper, manila and the white plastic cards. Text never under 12 logical px (22.5 layout): captions and body at 26 layout (14), headings raised at 28.

## 6. Numbers first

Before any restyle, as `ds2-theme.md` §11 step 3 requires:

- **Labour cost**: one helper for a building's charge this turn, `Production.labour_charge(b, ran)` (`_calculate_labour_cost` × the idle share, zero when paused), called by `maintenance_labour`, `CashCommitments` and `labour_overview()`. `labour_overview()` keeps its keys; the tab reads `base`, `factor_pct` and `est_10_turns` (fixes §3.1 and §3.2). The 10-turn estimate stays `LabourState.projected_workforce_labour_delta(10)`; the bell reads `at_floor` against `EconomyConfig.LABOUR_FACTOR_MIN`.
- **Headcount** (if §8.8 says yes): `Production.labour_headcount()` → `{unskilled, skilled, high_skilled}`, from the same recipe and building columns `_base_labour_cost` reads, over the player's running buildings.
- **Seat effects**: every effect from `AdvisorState.advisor_seat_effect_list`, in words (§3.3).
- **Seat worth**: `advisor_bonus_preview_per_turn` values `loan_interest` against the interest in last turn's loan payments (`LoanState`), so a CFO's worth shows (§3.4).
- **Salary and payroll**: `advisor_cost_for`, `advisor_payroll_per_turn` (£20.72 = 2 × £10.36). If Vera's reduced salary is meant, it goes into `advisor_cost_for` (§3.5).
- **Seat state**: `AdvisorState.seat_state(seat_id)` → `{state: filled, open, full or locked, tone, reason}`, from `is_seat_available`, `max_advisor_slots` and the net; the lamp, the chair, the padlock and the hover words all read it (§3.6).
- **Money** on LEDs by the owner's five cell rule (`scripts/ds2/money_figure.gd`, the point in its own cell once the kit moves to it).

## 7. Phases

Behind `UiPrefs.use_people_ds2` (cheat `toggle people ds2`); with the flag off the panel is today's exactly, and a test checks that.

| Phase | What | Size |
|---|---|---|
| 0. Measure | the flag and cheat; `tools/people_ds2_shot.tscn` on a fixed viewport: roster (empty council, founder seated, two filled, council full, all seats open), picker, detail, Labour at defaults, at the extremes, at the floor, HR policies locked and open; telemetry counters for opens, tabs and actions; the legacy code in `people_panel.gd` removed first, with a capture proving nothing changed | S |
| 1. Numbers | §6; copy and contrast (§3.7) in today's panel too | S |
| 2. Shell | the cabinet, nameplate, tab keys, seam, scroll, lamp overlay, the one width | M |
| 3. Labour | time clock and bell, doors, knob plate and notice board, automation, lockers | L |
| 4. Advisors roster | the table, places, chairs, the council strip | L |
| 5. Sheets | picker and detail as dossiers over the table; the guarded Hire key | M |
| 6. Default | the owner's review rounds, a standard saved, the flag on | S |

Contracts kept: `PeoplePanel`, `PeopleButton`, the `close_requested` signal, `council_widget_clicked`, and the advisor names the tutorial, `test_smoke.gd` and `tools/tutorial_regression_check.gd` use: `AdvisorAddNewButton`, `AdvisorSeatChoice_<seat>`, `AdvisorHireAssignButton`, `AdvisorChooseCandidateButton`, `AdvisorBonusSection`, `AdvisorBonusPrompt`, `AdvisorFinancialPreview`, `AdvisorBonusValue`, `AdvisorSalaryValue`, `AdvisorNetBenefitValue`, `AdvisorHireCostLine`, `AdvisorPortrait`, and `tutorial_candidate_worthwhile()`.

## 8. Decisions for the owner

1. **Width**: 800 logical for both tabs (recommended, §5), or keep a wider panel.
2. **The shell**: painted machinery green steel (the study), the tile view's stainless, or the navy steel of Building Detail and the top bar.
3. **The table**: five places a side, every seat always shown (recommended: the locked seats show what the company can grow into), or only the seats the company has opened, as today.
4. **Four seat looks** (recommended): filled; open (chair pulled out, the blotter bare, "Assign advisor" on it); council full (chair pulled out, the folder closed without a padlock, "Council full"); not opened (the padlock). The study shows the first and the last.
5. **The seat lamp**: green when the seat returns more than it costs, amber when not (the study); or by loyalty once loyalty is shown.
6. **Three LEDs a place** (Bonus, Salary, Net, the study) or two (Salary, Net, the brief), the bonus in the hover.
7. **Vera's worth and salary**: value the loan interest cut in the preview (recommended), and apply or drop her "reduced salary" (§3.4, §3.5).
8. **Headcount on the doors**: a new figure from a new helper (recommended: the doors then say something), doors without numbers, or no doors.
9. **The shift bell**: lit when labour reaches its floor (the study), or rung on the bonus turn.
10. **The notice board**: the knob under the cursor and every policy in force (the study), or only the knob under the cursor.
11. **Knob icons**: the study's pictograms, or the owner's own art; numerals allowed where the option is a number (50%, 75%, 100%)?
12. **Lockers** for the four other policies, a padlock and its reason on a locked one (the study).
13. **Height**: both tabs run past the 912 px fold (Advisors about 1040 logical, Labour about 1190) and scroll under the seam; accept, or put the lockers beside the notice board to shorten Labour.
14. **Picker and detail as sheets** over the table (recommended), or views that replace it, as today.
