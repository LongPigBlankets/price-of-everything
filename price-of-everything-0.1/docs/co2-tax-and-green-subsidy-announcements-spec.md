# Spec — CO2 Tax & Green Energy Subsidy Announcements

> **STATUS: BUILT (2026-07-10, branch `co2-tax-narrative`).** Implemented as specced with
> owner rulings + deviations: (1) taxed goods are **coal 0.5 / processed_oil 2.7 /
> ethylene 1.0** (crude_oil keeps its authored 0.1) on the **consumed** base, confirmed by
> the owner; (2) `CO2_TAX_RATE = 1.0` so the multiplier column IS the £/unit at scale 1;
> (3) per-building attribution (`Production.carbon_tax_by_building`) + a "Carbon tax / turn"
> line in the Building Detail economics card (owner addition); (4) Money panel Balance /
> Budget-projection / Charts rows + Turn-Summary dock lines ("Carbon Tax", "Subsidy");
> (5) the biomass escape route is the NEW `r_228 Bio Ethylene` (chem_plant: 10 biomass +
> 100 energy → 3 ethylene — owner: biomass direct, medium-high power), tech-gated behind the
> new **Biomass Cracking** node (Biochemistry III, Produce 300 biomass, prereq Sustainable
> Forestry); `r_155 Micro Algae Digestion` was restored to its original dormant-pool form —
> at base prices r_228 runs −£0.20/run unintegrated (£6.67/u) vs taxed oil-route ethylene
> £7.00/u (P1) / £9.25/u (P2); (6) a `skip <n>` debug-terminal cheat was added for
> fast-forwarding to policy turns; (7) owner timeline: BOTH policies announce via
> BLOCKING story decisions with a big-bold owner-authored `headline` above the Lorem body
> (defs carbon_tax_notice / green_subsidy_notice; single "Understood" choice; reserved by
> PolicyState via DecisionState.reserve to present on turn 90 / turn 100's DECIDE and
> block End Turn until acknowledged — no passive forewarn news for either), the levy
> RAMPS IN linearly across turns 91..100 ((turn−90)/11 of P1, per the owner's "ramp up
> from turn 91 to turn 101"), is at full P1 from turn 101, P2 t165, P3 t230; (8) the
> subsidy is a WINDOW: live t105, paying through at least t185, lapsing on a seed-derived
> turn so the first unpaid turn lands in [186, 191] (green_subsidy_last_turn =
> 185 + seed % 6; a per-match lapse announcement is scheduled, forewarned 5 turns).
> NOTE the carbon headline copy says "100% of market price" and names crude oil — the
> LIVE rates are coal 0.5 (125% of base), processed_oil 2.7 (54%), ethylene 1.0 (15%),
> crude 0.1 — flagged to the owner for either copy or multiplier reconciliation.
> Verified: unit suite green (1 standing bake fail); e2e t100 failure set + metrics
> unchanged vs parent; tools/policy_shot.tscn (four surfaces) +
> tools/policy_notice_shot.tscn (blocking notice at t90, resolve unblocks).
>
> **Body/explanation text for every announcement is placeholder Lorem Ipsum below; the owner
> will replace it with lore.** Search this doc and `scripts/policy_schedule.gd` for
> `LOREM` to find every spot.

---

## 0. Why this exists (design intent)

CLAUDE.md frames the whole game as *"~300-turn games … under a scheduled carbon-decarbonisation
squeeze."* Today that squeeze is **not implemented** — `co2_tax_multiplier` is authored in the
goods CSV but never read, and there is no subsidy. This feature makes the squeeze real and,
crucially, **legible and predictable**: the player is *told in advance* what is coming so they
can adapt (build green power before the subsidy window, switch off coal before the levy bites).
The strategic tension is the whole point — a surprise tax is unfair; a **forewarned** one is a
planning problem.

Two policy tracks, one shared announcement mechanism:

| Track | Role | Effect (see §4) | First beat |
|---|---|---|---|
| **Green Energy Subsidy** | Carrot | Per-turn payment for green power generated | ~turn 15 (early) |
| **CO2 Tax (Carbon Levy)** | Stick | Per-turn charge on carbon-intensive goods burned, escalating in phases | ~turn 45, ratchets to ~turn 200 |

---

## 1. Player-facing arc (what the player sees)

Each policy *phase* produces **two Turn-Briefing news items**, both non-blocking and
`Acknowledge`-dismissible (they are announcements, not decisions):

1. **Forewarning** — fires `forewarn_turns` before the effect. Title auto-formats to
   *"Coming in N turns: Carbon Levy — Phase 1"*; body is the `forewarn_body` (LOREM). This is
   the player's cue to adapt.
2. **Enactment** — fires on the effective turn. Title *"Carbon Levy — Phase 1 now in effect"*;
   body is the `body` (LOREM). From this turn the economic effect (§4) is live.

Surfaces (all existing):
- **Turn Briefing → News** section (the collapsed strip shows an off-white policy chip; the
  expanded panel shows title + body + `Acknowledge`). Unknown event kinds already default to the
  `news` section, so this "just works" — we only add explicit section/icon mappings for polish.
- **Notification bell** — same event, one source of truth.
- **Auto-expand** — the *first* enactment of each track (and each CO2 escalation) is emitted at
  `severity: "warning"`, which makes the briefing auto-expand that turn (a genuine "critical
  turn"). Subsequent routine reminders are `info`/`news` and stay collapsed.
- **Turn Summary** — the charge/subsidy shows as its own budget line (**Carbon Tax**, **Green
  Subsidy**) in `end_turn_dock.gd`, so the money movement is never mysterious.

> The player is **never asked to choose** here — these are world events. A *response* decision
> (e.g. "petition the ministry", "buy carbon credits") is a natural **future** extension via
> `DecisionState`, and is explicitly out of scope for this spec (§9).

---

## 2. Architecture at a glance

```
policy_schedule.gd   (const table: the authored timeline — the ONE source of truth)
        │  seeds at new-game →
        ├──────────────► EventScheduler.schedule(turn, {…forewarn_turns, forewarn_body…})
        │                    → forewarning + enactment NEWS items (UI only)
        │
        └──────────────► PolicyState (autoload): pure fn of current_turn → active levels
                             co2_tax_level(turn)      → 0 | 1 | 2 | 3
                             green_subsidy_rate(turn) → £/MW this turn
                                   ▲
                                   │ read each turn (headless-safe, deterministic)
        production.gd  ────────────┘
           • grid_settlement  → pays green subsidy   (summary.green_subsidy_received)
           • carbon_tax phase → charges CO2 levy      (summary.carbon_tax_paid)
```

**Key separation:** the **announcement** (EventScheduler news items) and the **economic effect**
(PolicyState levels read by `production.gd`) are *both derived from the same const schedule table*
but are otherwise independent. The UI never drives economics; the economics never render UI. This
means the effect runs correctly in **headless/e2e** (where there is no briefing) while the
announcements are a passive overlay.

---

## 3. The schedule (authored data — the timeline)

A single const table in `scripts/policy_schedule.gd`. **All turns/values here are PROPOSALS and
are balance-volatile (CLAUDE.md rule 7) — tune against the e2e harness; do not treat as final.**

```gdscript
# scripts/policy_schedule.gd  (const data only; no logic)
const SCHEDULE: Array = [
    # --- Green Energy Subsidy (carrot, early) ---
    {
        "id": "green_subsidy_p1", "policy": "green_subsidy", "level": 1,
        "effective_turn": 20, "forewarn_turns": 5, "severity": "warning",
        "title": "Green Energy Subsidy",
        "forewarn_title": "Green Energy Subsidy (incoming)",
        # LOREM — replace with lore. Shown in the forewarning news item.
        "forewarn_body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Praesentium subsidium in paucis conversionibus incipiet.",
        # LOREM — replace with lore. Shown when the subsidy goes live.
        "body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore. Vis viridis nunc remuneratur.",
    },

    # --- CO2 Tax (stick, escalating) ---
    {
        "id": "co2_tax_p1", "policy": "co2_tax", "level": 1,
        "effective_turn": 101, "forewarn_turns": 10, "severity": "warning",
        "title": "Carbon Levy — Phase 1",
        "forewarn_title": "Carbon Levy — Phase 1 (incoming)",
        # LOREM
        "forewarn_body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vectigal carbonis mox imponetur; parate.",
        # LOREM
        "body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor. Vectigal carbonis nunc valet.",
    },
    {
        "id": "co2_tax_p2", "policy": "co2_tax", "level": 2,
        "effective_turn": 165, "forewarn_turns": 8, "severity": "warning",
        "title": "Carbon Levy — Phase 2",
        "forewarn_title": "Carbon Levy — Phase 2 (incoming)",
        "forewarn_body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vectigal duplicabitur.",   # LOREM
        "body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vectigal carbonis auctum est.",        # LOREM
    },
    {
        "id": "co2_tax_p3", "policy": "co2_tax", "level": 3,
        "effective_turn": 230, "forewarn_turns": 8, "severity": "warning",
        "title": "Carbon Levy — Phase 3",
        "forewarn_title": "Carbon Levy — Phase 3 (incoming)",
        "forewarn_body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Ultimum incrementum vectigalis.",  # LOREM
        "body": "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vectigal carbonis maximum est.",            # LOREM
    },
]
```

Proposed timeline summary (tunable):

| Turn | Event |
|---|---|
| 90 | **Blocking notice**: "Government Notice: Carbon Levy" — must click Understood |
| 100 | Forewarn: Green Energy Subsidy incoming |
| 101 | **Carbon Levy P1 live** (scale ×1) |
| 105 | **Green Subsidy live** (window) |
| 185+ | Subsidy pays through ≥185; lapses seed-picked in 186–191 (forewarned 5 turns) |
| 157 | Forewarn: Carbon Levy P2 incoming |
| 165 | **Carbon Levy P2 live** (scale ×2) |
| 222 | Forewarn: Carbon Levy P3 incoming |
| 230 | **Carbon Levy P3 live** (scale ×3.5) |

> Difficulty/start hooks: the `new-game-screen-v2` ruleset seam can later scale
> `effective_turn`s or the rates per difficulty. For v1, one fixed schedule for all starts.

---

## 4. The economic effects

### 4.1 CO2 Tax — charge on carbon burned

**Signal:** the dormant per-good `co2_tax_multiplier` column (a carbon-intensity factor;
crude_oil = 0.1 today, most goods 0). We **tax combustion**, i.e. carbon-intensive goods
*consumed as recipe inputs* — this is the "polluter pays at the point of burning" model and
matches the green/grey-power doc's *"carbon stays upstream on coal/crude."* A furnace or coal
plant burning coal is taxed; a hydrogen or biomass route (multiplier 0) is not.

**Wire the dormant data (currently unread):**
- `catalog.gd:_parse_good_row` (~525–544) — parse `co2_tax_multiplier` into the good dict
  (default 0.0). *(Grep confirms it is parsed nowhere today.)*
- `economy_config.gd` — add the rate + phase scale (balance data, rule 7):
  ```gdscript
  const CO2_TAX_RATE := 0.20              # £ per (unit × co2_tax_multiplier) at scale 1
  const CO2_TAX_PHASE_SCALE := [0.0, 1.0, 2.0, 3.5]   # index by level (0 = inactive)
  ```

**Per-turn charge** — new `carbon_tax` sub-phase in `production.gd`, immediately after
`tax_dividends` (so it lands after profit tax, as a separate government charge; it is *not*
profit-gated — you pay it even on a loss-making turn, which is the whole pressure):
```gdscript
var level := PolicyState.co2_tax_level(TurnManager.current_turn)
if level > 0:
    var scale := EconomyConfig.CO2_TAX_PHASE_SCALE[level]
    var charge := 0.0
    for gid in summary.consumed:                          # goods burned this turn
        charge += float(summary.consumed[gid]) * Catalog.get_good(gid).get("co2_tax_multiplier", 0.0)
    charge *= EconomyConfig.CO2_TAX_RATE * scale
    if charge > 0.0:
        MatchState.add_money(-charge)
        summary.carbon_tax_paid = charge
        summary.money_out += charge
```
- Records `summary.carbon_tax_paid`; add the key to the summary init dict (default 0).
- New Turn-Summary line **"Carbon Tax"** in `end_turn_dock.gd` (`_fin` list), red like other costs.

> **Balance note:** whether the base is `consumed` (burning) vs `produced` (extraction) is a real
> design lever — `consumed` taxes the burner, `produced` taxes the miner. This spec picks
> **consumed**; flag before committing if the owner prefers extraction-side. Either way the
> authored `co2_tax_multiplier` values (and `CO2_TAX_RATE`) are volatile and must be tuned on the
> e2e harness, not guessed.

### 4.2 Green Energy Subsidy — payment for green power generated

**Signal:** `summary.power_supply_by_quality = {green_intermittent, green_steady, grey}` (live,
computed in `production.gd:_power_quality`). We subsidise **green generation** (rewarding building
green capacity even when self-consumed — a production incentive, not a feed-in tariff).

**Config (balance data):**
```gdscript
const GREEN_SUBSIDY_RATE := 0.03           # £ per green MW at scale 1  (~half GRID_SELL_PRICE 0.06)
const GREEN_SUBSIDY_PHASE_SCALE := [0.0, 1.0]   # v1: one level; room to escalate later
```

**Per-turn payment** — in the existing `grid_settlement` block (`production.gd` ~339–363), right
after grid buy/sell settle:
```gdscript
var srate := PolicyState.green_subsidy_rate(TurnManager.current_turn)   # already scaled
if srate > 0.0:
    var q := summary.power_supply_by_quality
    var green_mw := float(q.green_intermittent) + float(q.green_steady)
    var subsidy := green_mw * srate
    if subsidy > 0.0:
        MatchState.add_money(subsidy)
        summary.green_subsidy_received = subsidy
        summary.money_in += subsidy
```
- Records `summary.green_subsidy_received`; add to summary init (default 0).
- New Turn-Summary line **"Green Subsidy"** in `end_turn_dock.gd`, green like other inflows.

> `green_intermittent + green_steady` matches the Greenest victory track's notion of green (hydro
> + biomass included), which is intentional — the subsidy and the Greenest track reward the same
> thing.

---

## 5. PolicyState (new autoload)

A tiny holder — the schedule is static, so levels are a **pure function of the turn** (no mutable
level state to persist). Mirrors the `VictoryState`/`SolvencyState` autoload pattern.

```gdscript
# scripts/policy_state.gd  (autoload "PolicyState")
const Schedule := preload("res://scripts/policy_schedule.gd")

var _seeded := false      # announcement events seeded into EventScheduler? (save-guarded)

func _ready() -> void:
    MatchState.state_reset.connect(_on_new_match)   # new game → seed announcements

# Pure functions of turn (read by production.gd; headless-safe, deterministic):
func co2_tax_level(turn: int) -> int:
    var lvl := 0
    for e in Schedule.SCHEDULE:
        if e.policy == "co2_tax" and turn >= e.effective_turn:
            lvl = maxi(lvl, e.level)
    return lvl

func green_subsidy_rate(turn: int) -> float:
    var lvl := 0
    for e in Schedule.SCHEDULE:
        if e.policy == "green_subsidy" and turn >= e.effective_turn:
            lvl = maxi(lvl, e.level)
    return EconomyConfig.GREEN_SUBSIDY_RATE * EconomyConfig.GREEN_SUBSIDY_PHASE_SCALE[lvl] if lvl > 0 else 0.0

func _on_new_match() -> void:
    # Seed the forewarn + enactment news items ONCE per match. On LOAD they arrive via
    # EventScheduler's saved _scheduled, so guard against double-seeding.
    _seed_announcements()
```

`_seed_announcements()` walks `SCHEDULE` and calls, for each entry:
```gdscript
EventScheduler.schedule(e.effective_turn, {
    "id": "policy:%s" % e.id,
    "kind": "policy_enacted",
    "severity": e.severity,
    "title": "%s now in effect" % e.title,
    "body": e.body,                       # LOREM
    "forewarn_turns": e.forewarn_turns,
    "forewarn_body": e.forewarn_body,     # LOREM (the forewarn event reuses this)
    "source": "policy",
    "deeplink": {"panel": "money"},       # opens the ledger so the player sees the charge
    "persistent": false,
    "auto_dismiss_turns": 6,
})
```
`EventScheduler.schedule` then auto-fires the forewarning `forewarn`-kind event
`forewarn_turns` earlier (title *"Coming in N turns: …"*, body = `forewarn_body`).

**Save/load & determinism:**
- Levels are derived from the const table → nothing to serialize for the effect.
- Announcement events already round-trip via `EventScheduler._scheduled`. To avoid re-seeding on
  load, persist `PolicyState._seeded` (additive key, tolerant reader — no `SAVE_VERSION` bump, per
  the established pattern) and only `_seed_announcements()` when `not _seeded`. On a fresh
  new-game `state_reset`, reset `_seeded=false` then seed.
- No RNG anywhere → deterministic, replay-safe.
- **Old saves** (pre-feature): `_seeded` defaults false, so the schedule seeds on next load →
  any beats already past their `effective_turn` simply won't re-fire (their turn is gone); future
  beats fire normally. Acceptable. (If back-fill of missed enactments matters, `co2_tax_level()`
  is already correct for the current turn regardless — the *effect* is retroactive-safe; only the
  *news items* for past beats are skipped.)

**project.godot:** register `PolicyState` as an autoload (after `EconomyConfig`, `MatchState`,
`EventScheduler`, before/near `VictoryState`).

---

## 6. Turn Briefing wiring (polish)

Add explicit mappings so the announcements get a proper section + icon instead of the `news`
default (`turn_briefing.gd`):
```gdscript
_EVENT_SECTIONS["policy_enacted"] = "news"     # forewarn kind already lands in news
_EVENT_ICONS["policy_enacted"]    = "scale"    # ⚖ policy/gavel glyph (or add a "leaf")
_EVENT_ICONS["forewarn"]          = "clock"    # "coming soon" (reuse an existing glyph if none)
```
- `news` items are `Acknowledge`-able (already handled by `ackable = section == "news"`).
- `severity: "warning"` on enactments makes the briefing **auto-expand** that turn (existing
  critical-turn behaviour) — so a new levy isn't missed. Verify against
  `TurnBriefing` auto-expand triggers; if it keys only on decisions/alerts, add `policy_enacted`
  (severity warning) as an auto-expand trigger.
- Optional flourish (mirrors the CFO popup): a first-levy **minister portrait** popup. Out of
  scope for v1 — the news item is enough — but noted as an easy add later.

---

## 7. Headless / e2e behaviour

- **Effects always run** (they are core economics): the e2e balance harness *must* feel the
  subsidy and the escalating tax — that is exactly the pressure the harness should be balanced
  against. `PolicyState.co2_tax_level` / `green_subsidy_rate` are pure and run headless.
- **Announcement UI is passive**: `EventScheduler` events emit headlessly but render nothing
  without the HUD, so no gating needed. No modal, no blocking.
- Expect the e2e (`e2e_stoneshore.tscn`) to show a step-down in profit at turns 55/120/200 and a
  lift for green-heavy strategies from turn 20 — this is the intended signal; re-baseline the
  standing balance assertions if they move.

---

## 8. Testing plan

**Unit (`tests/test_runner.gd`):**
- `PolicyState.co2_tax_level(turn)` returns 0 before 55, 1 at 55–119, 2 at 120–199, 3 at 200+.
- `PolicyState.green_subsidy_rate(turn)` is 0 before 20, `GREEN_SUBSIDY_RATE` after.
- Carbon charge math: a turn consuming N coal (multiplier m) at level L charges
  `N·m·CO2_TAX_RATE·scale[L]`; a clean turn (multiplier-0 inputs) charges 0.
- Subsidy math: `green_mw·rate`; grey-only power → 0 subsidy.
- Catalog parses `co2_tax_multiplier` (non-zero for a fossil good, 0 default).
- Seed guard: seeding twice does not duplicate scheduled events; `_seeded` round-trips.

**e2e:** run to 100 and 200; assert `carbon_tax_paid` becomes non-zero at/after 55 for a
coal-burning build and `green_subsidy_received` non-zero after 20 for a solar build.

**Screenshot:** a `policy_shot.tscn` seeding a near-term beat to verify the forewarn + enactment
news items render (strip chip + expanded card) and the Turn-Summary Carbon Tax / Green Subsidy
lines appear.

---

## 9. Out of scope (future extensions)

- **Response decisions** — turning an announcement into a `DecisionState` choice ("lobby the
  ministry −loyalty / buy offsets −cash / do nothing"). The event framework already supports a
  follow-up `schedule_event` payload, so this slots in cleanly later.
- **Carbon credits / offset market**, **coal ban** (green/grey doc hints "coal ban later"),
  **per-difficulty schedules**, **minister portrait popup**.
- Taxing power directly (deliberately excluded — carbon stays upstream on the fuels).

---

## 10. Build checklist

1. `data/Goods - goodsMVP.csv` — confirm/author `co2_tax_multiplier` values for fossil goods
   (coal, crude_oil, pet_coke, natural_gas…). *(Balance data — surface proposed values.)*
2. `catalog.gd:_parse_good_row` — parse `co2_tax_multiplier` (default 0.0).
3. `economy_config.gd` — `CO2_TAX_RATE`, `CO2_TAX_PHASE_SCALE`, `GREEN_SUBSIDY_RATE`,
   `GREEN_SUBSIDY_PHASE_SCALE`.
4. `scripts/policy_schedule.gd` — the const `SCHEDULE` table (**LOREM bodies**).
5. `scripts/policy_state.gd` (+ autoload registration) — level fns + `_seed_announcements`.
6. `production.gd` — subsidy in `grid_settlement`; new `carbon_tax` sub-phase after
   `tax_dividends`; summary keys `carbon_tax_paid` / `green_subsidy_received`.
7. `end_turn_dock.gd` — "Carbon Tax" + "Green Subsidy" budget lines.
8. `turn_briefing.gd` — `_EVENT_SECTIONS` / `_EVENT_ICONS` + auto-expand trigger.
9. Tests + `policy_shot.tscn`.
10. Re-baseline e2e balance assertions if the squeeze moves them.
