# Decision Events — design + implementation spec

Status: IMPLEMENTED 2026-07-08 (owner rulings in §13). Engine: `scripts/decision_state.gd`
(autoload), modal: `scripts/decision_dialog.gd`, shot tool: `tools/decision_shot.tscn`,
cheats: `decision list | fire <id> | resolve <choice_id>`. Unit coverage in
test_runner (`_test_decision_*`). Headless runs keep decisions disabled, so the e2e
balance failure set is untouched.
Depends on: EventScheduler (live), Modifiers (live), advisor seats/loyalty (live)
Related: `docs/feature-plans.md`, advisor system (match_state.gd §advisors), carbon-arc plans

---

## 1. Overview

Every few turns the player faces a **decision**: a short, flavoured dilemma with 2–3
choices, scoped to a tile, a building, a building type, or the whole company. Hired
advisors argue sides — their portrait, a 1–2 sentence stance, and the loyalty stakes
appear on the choices they advocate. Some choices are **gated**: selectable only when a
specific seat is filled by an advisor hired at least one full turn ago.

Goals:
- Make the mid-game DECIDE phase eventful without adding micromanagement.
- Give advisors a felt presence (today their agendas react passively; decisions make
  them *speak*), and make loyalty a currency the player actively spends.
- Provide a narrative delivery channel that the carbon arc (turn 80+) can reuse.

Non-goals (v1): branching multi-decision story arcs (single follow-up events only),
decision chains driven by hidden counters, advisor-initiated decisions.

## 2. Player experience

1. During turn resolution (NARRATIVE phase) the scheduler draws a decision if one is
   due and eligible.
2. At the start of the next DECIDE phase the **Decision Dialog** opens: title, flavour
   body, the affected target (tile nickname / building name, with a "focus" button that
   pans the camera), and 2–3 choice cards.
3. Each card shows: the choice label, an honest mechanical consequence line
   (auto-rendered from the payload — legibility stance: no hidden effects), and — if an
   eligible advisor advocates it — that advisor's portrait in an accent-coloured frame,
   their stance line, and the loyalty stakes.
4. The player must pick a choice **now** — the dialog is modal with no dismiss: no
   defer, no Esc-close, scrim clicks are inert. This is deliberate (owner ruling): any
   grace window can be gamed — raise cash first, finish a build, reshuffle the board,
   *then* answer. The dialog header therefore carries everything needed to decide
   without leaving it: current cash, the target's name and status line, and a focus
   button that pans the camera behind the scrim (read-only peek). `default_choice`
   exists only for the non-interactive path (§3, `auto_resolve`).
5. Effects apply immediately (modifiers grant in DECIDE ⇒ they apply in this turn's
   PROCESS and live exactly `duration_turns` applications — the existing modifier
   timing rule). A toast + bell entry record the outcome; the politics panel (future)
   lists decision history.

## 3. Architecture

New autoload **`DecisionState`** (`scripts/decision_state.gd`) — sim-side, UI-free.

- Owns: the decision catalog (const `DECISION_DEFINITIONS`), the seeded RNG stream,
  cadence/cooldown state, the active decision (if any), and history.
- Wired in `TurnManager._wire_sim_listeners()` **after** `Modifiers` (listener order is
  an explicit contract — append, never insert). On NARRATIVE it runs `_maybe_draw()`.
- UI (`scripts/decision_dialog.gd`) is read-only; the single mutation entry point is
  `DecisionState.resolve(decision_uid, choice_id)` (sim-boundary rule).
- Headless/e2e: `DecisionState.auto_resolve := true` makes every drawn decision resolve
  its `default_choice` immediately — the e2e harness and the skip-turns cheat must
  never block on a modal. The skip cheat instead **halts the skip** when a decision is
  drawn (returns control to the player), unless `auto_resolve` is set.

### 3.1 Determinism

One dedicated `RandomNumberGenerator` seeded from the match seed
(`hash([match_seed, "decisions"])`). `rng.state` persists in saves. All candidate
selection (which decision, which target tile/building) sorts candidates by stable keys
(instance_id / tile_id) before drawing. No global `randi()` (architecture rule 3).

### 3.2 Scheduling — the pulse pipeline (BUILT 2026-07-08)

Deliberately **leaning deterministic** (owner ruling): a regular *pulse* pulls an
event, and the reveal is telegraphed a fixed lead later. The cadence is derived from
state, not a per-turn coin flip; only *which* event is random.

Every definition carries `priority` and `category` alongside `weight`:

- `priority`: **0 = story** (scripted arc beats — carbon-act dilemmas, distressed
  asset), **1 = major** (company-scope dilemmas), **2 = ambient** (local flavour).
- `category`: `labour | market | environment | infrastructure | land | tech | story`
  (extensible; one per definition).

Each NARRATIVE, `DecisionState._tick_narrative`:

1. **Reveal.** If a pulled decision's lead is up (`current_turn + 1 ≥ show_turn`),
   promote it to `pending` → the modal opens at the next DECIDE. Only ever one
   decision pending/scheduled at a time.
2. **Story reservation** (bypasses the pulse): a beat reserved for this turn fires
   immediately (reveal next DECIDE); a reservation next turn holds fire.
3. **Pulse.** On or after `_next_pulse_turn` (and `≥ FIRST_DECISION_TURN` 10, never in
   the tutorial), **PULL** one event: pick from the eligible pool, stamp it
   `show_turn = pull_turn + PULSE_LEAD_TURNS` (3), and set the next pulse
   `pull_turn + pulse_interval`. A quiet bell forewarning ("a decision is reaching your
   desk") makes the lead legible. If nothing is eligible, retry next turn.

**Pulse interval** (`_pulse_interval`) is `clamp(PULSE_MAX − ⌊eligible/2⌋, 3, 6)` plus
one seeded turn of 0–1 variation — a fuller eligible pool pulses sooner. So decisions
appear every **3–6 turns**, each pulled **3 turns** before it lands.

**Eligibility** (`_eligible_ids`, the cheap RNG-free filter that also sizes the
interval): not a story beat; not a spent one-shot; off its own `cooldown_turns`; and —
the key spacing rule — its **category (event type) has not fired within
`CATEGORY_COOLDOWN_TURNS` (20)**. So the same event *type* triggers **at most once per
20 turns**. Within the eligible pool the pull applies target-resolvability,
`weight_after_turn` arc multipliers, priority tiering (highest tier present wins), then
a weighted seeded draw.

State (persisted): `recent_draws` ring buffer (`{turn, id, category}`, cap 16, stamped
at PULL time — so the 20-turn spacing is measured pull-to-pull and, via the fixed lead,
reveal-to-reveal), `_next_pulse_turn`, and `_scheduled_pull` (the pulled-not-yet-shown
decision). `force_draw`/`reserve` bypass the lead and reveal at the next DECIDE.

## 4. Decision definition schema

```gdscript
{
  "id": "union_demands",
  "title": "Union Demands",
  "body_template": "Stewards at {target_name} tabled a pay claim…",
  "scope": "building_type",        # tile | building | building_type | company
  "target_selector": "highest_labour_building_type",   # named, deterministic
  "once": false, "cooldown_turns": 25, "weight": 1.0,
  "priority": 2, "category": "labour",          # scheduling, see §3.2
  "default_choice": "output_hit",               # auto_resolve paths ONLY (§3)
  "choices": [
    {
      "id": "pay_rise",
      "label": "Concede the pay claim",
      "effects": [ {"kind": "modifier", "domain": "labour_headcount",
                    "pct": 20.0, "duration_turns": 10, "target": "@target"} ],
      "advocate_seat": "coo",
      "stance": "Lines that stop don't restart cheap. Pay them and keep moving.",
    },
    {
      "id": "output_hit",
      "label": "Hold the line on pay",
      "effects": [ {"kind": "modifier", "domain": "recipe_output",
                    "pct": -10.0, "duration_turns": 10, "target": "@target"} ],
      "advocate_seat": "cfo",
      "stance": "A wage rise never goes back down. Ride out the slowdown.",
      "agenda_tags": ["AGENDA_LABOUR_SQUEEZE"],
    },
    {
      "id": "mediate",
      "label": "Bring in a mediator",
      "requires_seat": "hr_director",
      "effects": [ {"kind": "cash", "amount": -40.0},
                   {"kind": "modifier", "domain": "labour_headcount",
                    "pct": 8.0, "duration_turns": 10, "target": "@target"} ],
      "advocate_seat": "hr_director",
      "stance": "Both sides want a story they can sell. Let me write it.",
    },
  ],
}
```

`@target` resolves to the drawn target (instance_id, `target_match: {building_id}` for
building_type scope, or omitted for company scope). Optional per-choice
`stance_overrides: {advisor_id: "…"}` lets a specific occupant speak in character
(e.g. Gerald vs Priya arguing the same seat very differently).

### 4.1 Effects vocabulary (all map to existing APIs)

| kind | Payload | Applied via |
|---|---|---|
| `modifier` | any `Modifiers.add()` dict; `@target` injected | `modifier_state.gd add()` (duration/expiry handled there) |
| `cash` | `amount` (±), or `formula: "pct_of_building_revenue", pct` | `MatchState.add_money()` / `_building_turn_reports` for the base |
| `construction_delta` | `turns: +2` | mutate project `turns_remaining` via a new `Construction.adjust_remaining(iid, delta)` |
| `construction_complete` | — | set `turns_remaining = 0` (promotes on next tick; pair with `cash`) |
| `grant_unlock` | `title` | `MatchState.grant_unlock()` (auto-applies UNLOCK_MODIFIERS) |
| `agenda_tag` | tag string | `MatchState.flag_agenda_event()` — lets *non-advocate* advisors react via their existing likes/dislikes |
| `schedule_event` | `in_turns`, event dict | `EventScheduler.schedule()` — follow-up news / delayed consequences |
| `set_flag` | key | `DecisionState.flags` (e.g. per-building environmental exemption) |

All cash amounts in the catalog are **balance-volatile placeholders** (rule 7) — tune
via the e2e harness before shipping.

## 5. Advisor gating — "requires a seat"

A choice with `requires_seat: "research_director"` is selectable iff:

1. `MatchState.advisor_seats["research_director"]` is filled, AND
2. the occupant is **tenured**: hired on an earlier turn than the current one.

### 5.1 The 1-turn hire timer

`hire_advisor()` gains one line: `advisor_hired_turn[advisor_id] = TurnManager.current_turn`
(new persisted dict; cleared on fire/walk). Tenure check:

```gdscript
func is_advisor_tenured(aid: String) -> bool:
    return permanent_advisor_ids.has(aid) \
        and TurnManager.current_turn > int(advisor_hired_turn.get(aid, -1))
```

So an advisor hired this turn neither unlocks gated choices nor speaks on decisions
until the next turn — you can't panic-hire your way through a live dilemma. Eligibility
is evaluated when the decision is **presented** (start of DECIDE) and re-checked on
`resolve()`; seat reassignment between tenured advisors is free (tenure follows the
advisor, not the seat). Migration: old saves default `advisor_hired_turn` to
`current_turn - 1` so existing councils count immediately.

### 5.2 Gating rules for content

- Every decision keeps **≥1 ungated choice** (never soft-lock a dilemma).
- At most 2 gated choices per decision.
- Locked choices are **shown, not hidden** (legibility stance): greyed card, lock
  glyph, requirement line — "Requires a seated Research Director (hired at least one
  turn ago)". This advertises the advisor system every time it bites.

## 6. Advisor recommendations and loyalty

### 6.1 Who speaks

For each choice with an `advocate_seat`, if that seat is filled by a tenured advisor,
the choice card shows that advisor's endorsement. Empty/untenured seat ⇒ the choice
simply has no advocate strip (the stance text is unused). A decision therefore
naturally presents 0–3 "sides of the argument" depending on the council — exactly the
2–3-sided debate when the board is staffed.

### 6.2 Loyalty stakes (the contract)

| Situation | Loyalty delta |
|---|---|
| You pick a choice an advisor advocated — decision scope tile / building / building_type | **+0.5** to that advisor |
| You pick a choice an advisor advocated — company scope | **+2.0** to that advisor |
| You resolve the decision and an advisor's advocated choice was NOT picked | **−0.5** to that advisor, regardless of scope |
| Advisor advocated nothing on this decision (or was ineligible) | no change |
| `auto_resolve` (headless/e2e/skip only) | deltas apply exactly as if the player picked `default_choice` — keeps headless runs deterministic and save-equivalent |

Multiple advocates on the same picked choice each receive the reward. Applied through a
new public `MatchState.apply_decision_loyalty(advisor_id, delta, decision_id)` that
routes to `_set_advisor_loyalty(…, check_missions = true)` and records a driver row so
the advisor's Agenda display shows *"Backed you on: Union Demands (+2.0)"* — decisions
must be legible in the same place the other loyalty drivers are.

Deliberate interactions (features, not bugs — surface them in flavour):
- **Missions**: +2.0 company-scope rewards can tip an advisor across a mission loyalty
  milestone — following your Government Affairs chief on a big call can literally
  complete their arc.
- **Walk-outs**: repeatedly ignoring one advisor (−0.5 per snub, on top of per-turn
  decay toward 0) can drive them to `LOYALTY_WALK_THRESHOLD` and out the door. Losing
  your only Sustainability Officer because you kept siding with Hal *is the story*.
- Deltas ride the existing clamp [−10, +10] and the `advisor_loyalty_changed` signal —
  no new UI plumbing for the people panel.

### 6.3 Advocate strip UI

On the choice card, left-aligned: the advisor portrait at ~64px in a 2px frame tinted
with the advisor's `accent` colour (reuse `people_panel._portrait_panel()` — extract it
to `UIHelpers.make_advisor_portrait(advisor, size)`; it already handles the
portrait-PNG vs accent+initials fallback, which matters because several cast members
have no portrait art yet). Beside it: seat name + advisor name (Caption), the stance
text (Body, italic, 1–2 sentences), and the stakes line (Numeric, small):
`Follow: +0.5 loyalty · Ignore: −0.5`.

## 7. Decision Dialog (UI spec)

- **Pattern of record**: the confirm-dialog shape (`buy_building_dialog.gd`) — full-rect
  scrim, centred `PanelContainer` card, mounted lazily on a CanvasLayer (layer 130).
- **Deliberately inescapable** (the one exception to the dialog norms): scrim clicks
  are inert (a subtle card nudge signals "you must choose"); it does NOT register with
  `PanelStack`, so Esc never closes it. Esc may still open the pause menu above it —
  pausing is fine, escaping the decision is not; it's still there on return. Header
  row shows current cash (live via `money_changed`) and the target summary, since the
  player can't browse other panels before answering.
- Choice cards use the `_ClickCard` pattern from `advisor_council_tab.gd` (never a
  Button wrapping a container). Hover swap; `disabled` state for locked cards.
- DS theme only: Title/Body/Caption/Numeric variations, `DS.PALETTE` (navy card, cream
  outline), WPA/mid-century treatment matched to the research panel.
- Consequence lines are generated from the effects payload by a single
  `describe_effects(effects) -> String` helper (also used by the bell entry and the
  future politics-panel history) — one source of truth, no hand-written summaries that
  can drift from the numbers.
- The dialog is presented from a `turn_advanced` listener; it never appears mid
  resolution (`is_resolving` contract). The bell records resolved outcomes only —
  there is no deferred state to badge.
- Screenshot tool: `tools/decision_shot.tscn` (windowed, writes `decision_shot.png`)
  per the validation doctrine.

## 8. Turn-pipeline integration (exact)

1. **NARRATIVE (turn T)**: `DecisionState._on_phase_started` — if no decision is
   active, run the §3.2 scheduler → sets `pending_decision`, emits `decision_drawn`.
2. **turn_advanced (T→T+1 DECIDE)**: dialog opens for `pending_decision`; the player
   must resolve it during this DECIDE. Belt-and-braces alongside the modal:
   `TurnManager.commit_turn()` is guarded — it refuses while a decision is pending in
   interactive mode (with `auto_resolve` it resolves the default instead).
3. **Player resolves in DECIDE of T+1**: effects apply now ⇒ modifiers granted in/before
   PROCESS get `expires_turn = (T+1) + duration − 1` and live exactly `duration`
   applications (existing tested rule; do not special-case).
4. Loyalty deltas apply at resolve time; agenda tags flagged at resolve time are
   collected by `_evaluate_agendas` during the same turn's resolution.

## 9. Persistence

Purely **additive** — per the tolerant-reader doctrine no `SAVE_VERSION` bump is
needed; pre-feature saves load with defaults:

- `MatchState.advisor_hired_turn: Dictionary` in the match block (old saves default
  every employed advisor to `current_turn − 1`, so existing councils count
  immediately).
- A new `decisions` snapshot key: rng seed+state, active/pending decision (uid,
  definition id, resolved target), per-definition cooldowns + fired-once set, the
  `recent_draws` ring buffer (§3.2), story reservations, history (capped, for the
  politics panel), and flags (e.g. environmental exemptions). Saves without the key
  load a fresh decision state.

## 10. Debug & testing

- Terminal cheats: `decision list`, `decision fire <id>` (forces a draw next NARRATIVE,
  respecting target selection), `decision resolve <choice>`.
- Unit tests (test_runner):
  - gating: seat empty / occupant hired-this-turn / tenured — only the last unlocks.
  - loyalty matrix: follow-local +0.5, follow-company +2.0, snub −0.5, no-advocate 0,
    auto_resolve default applies deltas, mission milestone fires on a +2 crossing.
  - scheduler: same definition never twice running; same category never twice
    running; recency halving applied; story reservation suppresses random draws on
    its turn and the turn before; priority tier always wins over weight.
  - commit guard: `commit_turn()` refuses while a decision is pending (interactive);
    resolves the default under `auto_resolve`.
  - determinism: same seed + same inputs ⇒ same draw sequence and targets.
  - modifier lifetimes via the existing expiry test pattern.
  - auto_resolve path never leaves a pending decision (e2e safety).
- e2e_stoneshore: run with `auto_resolve = true`; assert no pending decision at target
  turn and that decision cash effects appear in summaries.

---

## 11. Decision catalog (v1: 8 decisions)

Seat-gate coverage across the catalog: research_director, coo, hr_director (×2),
chief_markets, chief_investment, sustainability, government_affairs (×2) — 7 distinct
seats. Every decision keeps ≥1 ungated choice. £ values are placeholders (rule 7).
"Default" on each entry = its `default_choice`, used **only** by `auto_resolve`
(headless/e2e/skip); interactive play has no default — the player must choose (§2).

Scheduling fields (§3.2): all are priority 2 (ambient) except D5 (priority 1, the one
company-scope dilemma). Categories: D1 `infrastructure` · D2 `labour` · D3 `tech` ·
D4 `infrastructure` · D5 `market` · D6 `environment` · D7 `labour` · D8 `land` — so
e.g. the two labour dilemmas (D2/D7) can never fire in consecutive draws.

### D1 · Planning Pushback *(original)* — scope: building (under construction, ≥2 turns left)

> Residents' associations have packed the planning hearing for {target_name}.

| Choice | Effects | Advocate |
|---|---|---|
| Hold consultations | construction +2 turns | CFO — "Patience is free. Goodwill isn't, but it's close." *(+0.5 / −0.5)* |
| Pay for acceleration (£50) | −£50, no delay | COO — "Every idle turn is a turn the line isn't learning." *(+0.5 / −0.5)* |
| 🔒 Fast-track the permits (£20) — **requires Government Affairs** | −£20, no delay, `agenda_tag: AGENDA_BACKROOM_DEAL` | Government Affairs — "There's a committee chair who owes me lunch. Twenty covers lunch." *(+0.5 / −0.5)* |

Default: consultations.

### D2 · Union Demands *(original)* — scope: building_type (highest labour bill)

> Stewards across your {target_name} operations have tabled a coordinated pay claim.

| Choice | Effects | Advocate |
|---|---|---|
| Concede the pay claim | labour +20% on type, 10 turns | COO — "Lines that stop don't restart cheap. Pay them and keep moving." *(+0.5 / −0.5)* |
| Hold the line | output −10% on type, 10 turns, `agenda_tag` | CFO — "A wage rise never goes back down. Ride out the slowdown." *(+0.5 / −0.5)* |
| 🔒 Bring in a mediator (£40) — **requires HR Director** | −£40, labour +8% on type, 10 turns | HR Director — "Both sides want a story they can sell. Let me write it." *(+0.5 / −0.5)* |

Default: hold the line.

### D3 · A Better Way *(original)* — scope: building (producing, ran last turn)

> A shift worker at {target_name} has worked out a genuinely better process.

| Choice | Effects | Advocate |
|---|---|---|
| Adopt it on the line | output +10% on building, 20 turns | Technical Director — "Give the line six months with this and it pays for a new one." *(+0.5 / −0.5)* |
| License it out | one-off cash: +50% of building's last-turn revenue | CFO — "Cash today compounds. Cleverness on one line doesn't." *(+0.5 / −0.5)* |
| 🔒 Fold it into the research programme — **requires Research Director** | `grant_unlock`: the cheapest still-locked tech matching the building; if none, the cheapest matching its recipe family (owner ruling) | Research Director — "This isn't a tweak, it's a doorway. Let me take it through properly." *(+0.5 / −0.5)* |

Default: adopt it.

### D4 · Substation Failure *(new)* — scope: tile (cabled tile with ≥2 powered buildings)

> The transformer feeding {target_name} died overnight in a shower of copper rain.

| Choice | Effects | Advocate |
|---|---|---|
| Emergency repair crew (£60) | −£60 | *(no advocate)* |
| Ride out the brownout | output −20% on tile's buildings, 2 turns | CFO — "Two dim turns cost less than a crew on triple time." *(+0.5 / −0.5)* |
| 🔒 Cannibalise spares from stores — **requires COO** | maintenance +15% on tile's buildings, 6 turns | COO — "I can keep it lit with what's on the shelf — but we'll be patching patches for a while." *(+0.5 / −0.5)* |

Default: ride it out.

### D5 · The Broker's Offer *(new)* — scope: **company** (targets your top-sold good last turn; requires any market sales)

> A commodity house wants exclusive placement of your {good_name}.

| Choice | Effects | Advocate |
|---|---|---|
| Sign the placement (£80 fee) | −£80, `market_price` +10% on good, 10 turns | *(no advocate)* |
| Show them the door | — | CFO — "Exclusivity is a leash with a fee attached. We sell fine without them." *(+2.0 / −0.5)* |
| 🔒 Renegotiate the terms — **requires Chief Markets Officer** | `market_price` +6% on good, 15 turns, no fee | Chief Markets — "Their first offer prices our desperation. We aren't desperate — I'll re-cut it." *(+2.0 / −0.5)* |

Default: show them the door. *(Company scope: follow = +2.0.)*

### D6 · Environmental Inspection *(new)* — scope: building (fossil/mining building; `weight_after_turn: {80: 2.0}` — the carbon arc doubles these)

> Inspectors found runoff downstream of {target_name}, and a journalist found the inspectors.

| Choice | Effects | Advocate |
|---|---|---|
| Pay the fine, remediate (£75) | −£75 | *(no advocate)* |
| 🔒 Make it go away — **requires Government Affairs** | output −10% on building, 3 turns (disruption while it's "handled"), `agenda_tag: AGENDA_BACKROOM_DEAL` | Government Affairs — "Findings get revised all the time. Give me three weeks and a quiet room." *(+0.5 / −0.5)* |
| 🔒 Commission a public clean audit (£40) — **requires Sustainability Officer** | −£40, `set_flag`: building exempt from future environmental events, `agenda_tag: AGENDA_CLEAN_COMMITMENT` | Sustainability — "Own it in public once and this building stops being a target forever." *(+0.5 / −0.5)* |

Default: pay the fine. *(Two gated choices — the ungated path is always available. The
agenda tags make the wider cast react: Hal approves the backroom, Priya despises it.)*

### D7 · Headhunters Circling *(new)* — scope: building_type (highest labour bill)

> A rival operator is quietly poaching your best {target_name} crews.

| Choice | Effects | Advocate |
|---|---|---|
| Match their offers | labour +15% on type, 8 turns | COO — "Replacing a trained crew costs double what keeping one does." *(+0.5 / −0.5)* |
| Wish them well | output −15% on type, 4 turns (retraining) | CFO — "Nobody is irreplaceable, and panic raises are how payrolls rot." *(+0.5 / −0.5)* |
| 🔒 Stand up a retention programme (£50) — **requires HR Director** | −£50, labour +5% on type, 8 turns | HR Director — "People rarely leave for money alone. Give me a budget and a week." *(+0.5 / −0.5)* |

Default: wish them well.

### D8 · The Land Deal *(new)* — scope: tile (owned land ≥ footprints + 20 spare units)

> A developer wants your spare frontage on {target_name} — and they're paying over the odds.

| Choice | Effects | Advocate |
|---|---|---|
| Sell at their price | +cash: spare patches at 3× patch price | CFO — "Book the profit. Land is only worth what someone overpays for it." *(+0.5 / −0.5)* |
| Keep the land | — | *(no advocate)* |
| 🔒 Counter at a premium — **requires Chief Investment** | +cash: spare patches at 4×, `schedule_event`: in 5 turns, "the development breaks ground" — land patches on this tile cost 2× thereafter | Chief Investment — "They budgeted for a counter. And once they build, every acre around it reprices — sell high, then watch." *(+0.5 / −0.5)* |

Default: keep the land.

---

## 12. Other impacts and narrative potential

- **The cast argues in character.** Advocacy is seat-based, so *who* holds the seat
  changes the voice: `stance_overrides` lets Gerald and Priya deliver opposite moods
  from the same seat. D6 is deliberately a Hal-vs-Priya set piece.
- **Agenda tags ripple beyond the advocates.** Because choices can
  `flag_agenda_event()`, non-advocate advisors react through their existing
  likes/dislikes — siding with the fixer quietly erodes the idealist's loyalty even
  when she wasn't on the card. Two new tags in v1 (`AGENDA_BACKROOM_DEAL`,
  `AGENDA_CLEAN_COMMITMENT`), wired into 3–4 cast members' agendas.
- **Loyalty becomes a spendable currency.** Follow rewards can complete advisor
  missions; serial snubs (with decay) can walk an advisor out. The people panel's
  existing loyalty-driver rows make every decision's contribution auditable.
- **Carbon-arc delivery channel.** The government-change storyline (turn 80+) reuses
  this exact machinery: announcement events are bell events; its dilemmas ("accept the
  transition grant with strings vs lobby against") are just catalog entries with
  `weight_after_turn` and government-flavoured advocates (Government Affairs and
  Sustainability were given gates in v1 partly to seed those arcs).
- **Follow-ups make the world feel persistent.** `schedule_event` gives every decision
  a cheap epilogue (D8's ground-breaking). v2 candidates: escalation re-draws (the
  union returns harder if you held the line), hidden relation counters feeding weights.
- **Politics panel feed.** History (+ `describe_effects` strings) is stored from day
  one, so the future politics panel gets a ready-made "recent decisions" ledger.
- **Difficulty/ruleset seam.** Pacing knobs (`GLOBAL_COOLDOWN`,
  `CATEGORY_COOLDOWN_TURNS`) belong in the ruleset config once Phase-2 plumbing lands.
- **Victory-track texture.** D6's clean audit is Greenest-flavoured; future decisions
  can lean on other tracks (Autarkic: "a cheap import contract"…).

## 11.1 Distressed Asset Program (story one-shot, BUILT 2026-07-08)

A 9th, non-random decision `distressed_asset`: `SolvencyState` force-draws it the
first time cash reaches −£500 **with a CFO seated** (the CFO proposes it). Company
scope, so following/refusing moves CFO loyalty ±2.0 / −0.5.
- **Accept** → `SolvencyState.accept_distressed_program()`: investors buy every player
  building at 1.5× sale value (`MatchState.liquidate_all_buildings`) and a £500 grace
  loan lands (`LoanState.take_grace_loan` — interest-free 10 turns, then normal). The
  cash injection resets the bankruptcy clock; you keep playing with cash + no plant.
- **Refuse** → keep everything and trade out of it, with bankruptcy looming.
Part of the solvency batch (see memory `demolition-solvency-batch`): the bankruptcy
end-state (−£500 + non-positive profit for 5 straight turns) ends the game and mounts
the game-over screen. Both are gated off in headless.

## 12.1 Unaffordable cash choices (owner ruling, 2026-07-08)

A choice with an upfront cash cost the player cannot cover stays **selectable** — the
modal has no deadline, so no choice may be soft-locked by cash. Beneath its
consequence line the card shows a warning-toned note:
*"You're short £X — picking this takes out a loan to cover it."*
On resolve, the shortfall is borrowed automatically at standard terms via the existing
loan system, **bypassing the profit-gated borrowing capacity** (it's a distress loan,
booked with source "decision"), then the cost is paid. The loan appears in the money
panel like any other.

**Only the cost is ever financed** (owner ruling, 2026-07-08): with a negative
balance the loan equals the full cost and the overdraft stays exactly where it was —
`loan = cost − clamp(money, 0, cost)`. (The first implementation borrowed
`cost − money`, silently refinancing any deficit back to £0 — a free bailout; fixed
and regression-tested.) The card note adapts: *"You're in the red — the full £X cost
is covered by a loan."*

Related loan-system change shipped alongside (balance change, full protocol): loss
troughs no longer zero the credit line — `LoanState.capacity_total()` gained an
asset-collateral leg (`LOAN_COLLATERAL_LTV` 0.5 × player buildings' build cost) on
top of the profit-gated cashflow leg, so a firm with real plant can borrow through a
downturn instead of spiralling. Evidence: e2e failure set unchanged (the standing 4);
the harness's coal-backed loan branch now executes (£75 capacity where it saw £0).

## 13. Owner rulings (2026-07-08)

1. **No deadline — decide now.** Deferral windows can be gamed (raise cash, finish a
   build, reshuffle seats before answering), so the dialog is modal with no dismiss
   and `commit_turn()` is guarded. `default_choice` survives only for the
   non-interactive `auto_resolve` paths.
2. **Auto-resolve applies loyalty deltas** exactly as if the default was picked
   (headless/e2e/skip only — there is no interactive auto-resolve anymore).
3. **D3 free-tech selector**: cheapest still-locked tech matching the building; if
   none matches, cheapest matching the building's recipe family.
4. **Gate tenure is 1 full turn, flat.** No difficulty scaling.
