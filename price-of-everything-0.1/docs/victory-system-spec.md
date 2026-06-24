# Victory System — Full Spec (Top-Bar Widget + Fullscreen Panel)

Status: **design only, no implementation**. Extends "Plan 2". All file:line references
verified against the current tree.

---

## 0. Plan review — what's confirmed, what's resolved

**Confirmed against the codebase**
- A new `victory_state.gd` autoload is the right home — `run_metrics.gd:2` ("per-turn
  strategy/economy observability", append-only CSV, no `import_state`) is explicitly
  not part of save snapshots.
- `save_load.gd` snapshots each system via `X.export_state()` / `import_state()`
  (`export_snapshot` ~L54-76, `import_snapshot` ~L78-101). Adding one line each side works.
- `Production.turn_processed(summary: Dictionary)` (production.gd:27, emitted once/turn at
  ~L342) carries the per-turn economics. `TurnManager.turn_resolution_completed` (no args)
  fires after all phases. Both are real.
- `TurnManager.current_turn` (int) drives the base time score. `MAX_TURNS = 300`, soft-end
  via `game_ended_signal("turn_cap_reached")`. No victory/win/game-over concept exists yet.

**Win-curve design intent (the spine of the scoring):** you can win with **1 victory track
at turn 100**, scaling to **4 tracks by turn 300**. This is achieved by a **decaying base
score outside the five tracks**: a fixed win threshold of **4000**, all tracks worth **1000**,
and a base that is **3000 flat through turn 100** then decays linearly to **0 at turn 300**.
So `win = base + Σ track ≥ 4000` means turn 100 needs 1000 of track score (1 track), turn 200
needs ~2500 (~2.5 tracks), turn 300 needs 4000 (4 tracks). You only ever need 4 of the 5 tracks
— the 5th is your free choice to skip. See §5.0 + §6.

**Conflicts / gaps resolved in this spec**
1. **All five tracks are worth 1000** (no halving). Each still has a `MAX_SCORE` constant for
   tunability, but the default is a flat 1000 across; the UI fill bar shows *progress* (0–1).
   See §10.
2. **`power_supply_by_type` does not exist** — only `power_demand_by_type` (production.gd:94).
   Greenest requires adding it (mirrors the demand version). Prerequisite, see §4.1.
3. **Retained (post-tax) profit is not a summary key**, but is exactly `money_in - money_out`
   (taxes + dividends are already added into `money_out`; tax 20% / dividend 20%, see
   production.gd `_apply_tax_and_dividends` ~L387). Richest uses that. See §5.4.
4. **0-turn movements never create a shipment** (immediate `Stockpile.add` / instant payout),
   so Logistics *cannot* be driven by `pending_transport_shipments` / `transport_shipments_changed`
   alone — it would miss the most-efficient movements and bias efficiency down. Logistics needs
   a per-movement hook at the queue chokepoints. See §4.2 + §5.3.
5. **Autarky = zero market buys of ANY kind** (per design): production inputs, recurring buys,
   building materials, upgrade materials, manual buys — *any* purchase breaks the streak. The
   victory screen shows a transparent per-category transaction tally (inputs / building /
   upgrades / other). See §5.1 + §8.3 + §9.3.
6. **Score volatility / win latching.** Track contributions are stored as **best-ever**
   (monotonic, bars only fill up); the **win latches** the first turn `total ≥ 4000`. Base
   score still decays with turns (intended time pressure). See §6.

---

## 1. Goals & scope

A single victory score (0–8000, win at 4000), surfaced as (a) a compact clickable top-bar widget and
(b) a fullscreen breakdown panel. Score = a decaying **base time score** + five independent
**track scores** (Autarkic, Logistics, Richest, Widest, Greenest). Reaching the win
threshold latches a victory.

Out of scope (note as future): defeat conditions, multiplayer/AI victory, a full
end-of-game victory cinematic. This spec includes a minimal victory moment (§6).

---

## 2. Architecture overview

```
            (PROCESS phase)                         (after all phases)
Production --turn_processed(summary)--> VictoryState <--turn_resolution_completed-- TurnManager
MatchState --goods_movement_recorded(kind, turns)--> (Logistics counters, live)
MatchState --state_reset--> VictoryState.reset()

VictoryState --score_changed(total, breakdown)--> TopBar widget + VictoryPanel
VictoryState --victory_achieved(total, turn)--> HUD (victory moment)
SaveLoad <--export_state()/import_state()--> VictoryState
```

- **`VictoryState`** (new autoload) owns all accumulated victory data, recomputes the score
  once per turn, and is the single source of truth for the UI.
- **Scoring tick:** cache `summary` on `turn_processed`; do the full recompute + win check on
  `turn_resolution_completed` (so late-phase recurring moves/sells are already counted).
- **Logistics** is fed live by a movement signal during the turn; the counters are read at
  the scoring tick.

---

## 3. Data model — `VictoryState` (scripts/victory_state.gd)

Saved fields (round-trip via export/import):

| Field | Type | Meaning |
|---|---|---|
| `autarkic_streak` | int | consecutive turns with no market goods purchase |
| `logistics_total` | int | lifetime movements recorded |
| `logistics_efficient` | int | lifetime movements with `transport_turns ≤ 1` |
| `richest_window` | Array[float] | trailing retained-profit buffer (len ≤ `RICHEST_WINDOW`) |
| `track_best[track]` | Dictionary[String→float] | best-ever progress (0–1) per track |
| `score_history` | Array[Dictionary] | last `TREND_LEN` snapshots `{turn, total, base, tracks{...}}` for trends |
| `won` | bool | win latched |
| `won_turn` | int | turn the win latched (0 if not) |

Derived each tick (not saved): `base_score`, per-track live progress, per-track contribution,
`total`, the breakdown dict the UI reads.

Transient (not saved): `_last_summary` (cached from `turn_processed`).

Public API:
- `export_state() -> Dictionary` / `import_state(d: Dictionary) -> void`
- `reset() -> void` (wired to `MatchState.state_reset`)
- `record_movement(kind: String, transport_turns: int) -> void` (Logistics feed)
- `get_breakdown() -> Dictionary` — everything the UI renders (see §8.3)
- Signals: `score_changed(total: int, breakdown: Dictionary)`, `victory_achieved(total: int, turn: int)`

---

## 4. Engine integration (the only non-UI engine edits)

### 4.1 Add `power_supply_by_type` to the production summary (Greenest prerequisite)
- In production.gd, initialise `"power_supply_by_type": {}` in the summary literal (next to
  `power_demand_by_type`, ~L94).
- Where a power building's output is recorded (`Power.record_produced(tile_id, output_qty)` in
  the power branch of `_process_production`, ~L167-171), also accumulate by building type,
  mirroring the existing `_accumulate_by_type(summary.power_demand_by_type, building_id, ...)`
  pattern: `_accumulate_by_type(summary.power_supply_by_type, str(building.get("building_id")), float(output_qty))`.
- Result shape: `building_id -> {count: int, amount: float}` (same as the demand map).

### 4.2 Add a movement hook (Logistics feed + Autarky feed, captures 0-turn movements)
Add one signal that carries both the logistics turns and the buy category:
`signal goods_movement_recorded(kind: String, category: String, transport_turns: int)`.
Emit it once per movement at the chokepoints, **for every movement including 0-turn ones**:
- `queue_buy(...)` — after a successful buy: `emit("buy", category, turns)`, where
  **category** is derived from the `extra` tag / caller:
  - `extra.has("construction_instance_id")` → `"building"`
  - `extra.has("upgrade_instance_id")` → `"upgrade"`
  - `extra.get("buy_kind","")` non-empty → that value (production input buys pass
    `{"buy_kind":"input"}`; recurring buys also `"input"`)
  - else → `"other"` (manual/direct buys from world_map)
- `queue_move(...)` — `emit("move", "", turns)`.
- Sales emit from **two** chokepoints (not all sales funnel through `execute_sale`):
  - `MarketState.execute_sale(...)` — `emit("sale", "", turns)` — covers production-output
    dispatch and the player/UI `queue_sell` / bulk `sell_all_to_market`.
  - `Production._sell_stockpile_totals(...)` — `emit("sale", "", ship_turns)` — the PROCESS
    `sell_phase` stockpile path (auto-sell standing orders, bulk SELL_ALL, queued
    stockpile sales) sells directly without `execute_sale`, so it emits its own event.
    Guard on `sale_record.total_qty > 0`; the two paths never cover the same sale, so no
    double-count.

Caller changes required so categories are accurate:
- `Production._buy_market_inputs` passes `{"buy_kind":"input"}` into its `queue_buy` calls
  (both the auto-top-up and the recurring-buys loop).
- Construction & upgrade buys already tag `construction_instance_id` / `upgrade_instance_id`
  — no change needed.
- Manual buys (world_map) need no tag → fall through to `"other"`.

`VictoryState` connects this signal:
- **Logistics:** every emit → `total += 1`, `efficient += 1` if `transport_turns ≤ 1`.
- **Autarky:** `kind == "buy"` → mark the turn non-autarkic and increment
  `purchases_this_turn[category]` (and the lifetime tally). Moves and sales do NOT break
  autarky (you may export freely).

One emit = one transaction (a multi-good manifest counts once; see §11).

> Rationale: `queue_transport_shipment` / `transport_shipments_changed` only fire for
> `turns ≥ 1`. Counting there would silently exclude instant deliveries — exactly the
> movements that *should* score as maximally efficient — and would also miss instant buys
> for the autarky check.

### 4.3 Save/load wiring
- project.godot `[autoload]`: add `VictoryState="*res://scripts/victory_state.gd"`
  (place after `Production` / `LoanState`).
- save_load.gd `export_snapshot`: add `"victory": VictoryState.export_state(),`.
- save_load.gd `import_snapshot`: add `VictoryState.import_state(snap.get("victory", {}))`
  (after the others; `MatchState.reset()` at the top already fires `state_reset` → a clean
  `VictoryState.reset()` before the import overwrites it).

No other engine changes. Everything else reads existing state.

---

## 5. Scoring spec

### Common model
- Each track computes **live progress** `p ∈ [0,1]` each tick.
- Stored **best progress** `pb = max(pb, p)` (monotonic; bars only fill).
- Track **contribution** to total = `round(pb * MAX_SCORE[track])`.
- `total = base_score + Σ contributions`.

### 5.0 Base time score (the decaying component that sets the win curve)
```
base = max(0, BASE_MAX - max(0, turn - BASE_FREE) * BASE_DECAY)   # turn = TurnManager.current_turn
     # BASE_MAX 3000, BASE_FREE 100, BASE_DECAY 15  →  3000 flat to turn 100, linear to 0 at turn 300
```
- Turns 1–100 → 3000 (a fast finish only needs 1 track to clear 4000).
- Linear 3000→0 over turns 100→300 (MAX_TURNS). 0 thereafter.
- This base lives **outside** the five tracks and is what forces "more tracks later":

  | turn | base | track score needed to win (4000 − base) | ≈ tracks |
  |---|---|---|---|
  | ≤100 | 3000 | 1000 | 1 |
  | 150 | 2250 | 1750 | ~1.75 |
  | 200 | 1500 | 2500 | ~2.5 |
  | 250 | 750 | 3250 | ~3.25 |
  | 300 | 0 | 4000 | 4 |

- Base is **not** monotonic — it decays, which IS the time pressure. Shown separately from the
  five track bars in both UIs.

### 5.1 Autarkic — total self-sufficiency  (MAX_SCORE 1000)
- **Metric:** `autarkic_streak` = consecutive turns with **zero market buys of any kind**.
- **Breaks the streak this turn iff** any `goods_movement_recorded` with `kind == "buy"` fired
  this turn — i.e. `sum(purchases_this_turn.values()) > 0`. This covers **every** purchase
  category: `input`, `building`, `upgrade`, `other`. Sales and tile-to-tile moves do **not**
  break it.
- **Per-category tally (for transparency, §8.3/§9.3):** `purchases_this_turn = {input, building,
  upgrade, other}` reset each turn; `purchases_lifetime` = same, cumulative.
- **Update (per tick):** `streak = 0 if any-purchase-this-turn else streak + 1`.
- **Progress:** `p = clamp((streak - 10) / (30 - 10), 0, 1)` → starts scoring at 10 turns,
  caps at 30.

> Note: with this strict definition, **production input auto-buys** (`_buy_market_inputs`) are
> the usual streak-killers. Genuine autarky therefore requires sourcing every input internally
> (own mines/recipes) and stockpiling build/upgrade materials before constructing — which is the
> intended challenge. The card makes the cause visible (e.g. "broken by 4 input buys").

### 5.2 Logistics — transport efficiency  (MAX_SCORE 1000)
- **Counters (live, via §4.2):** `logistics_total += 1`, `logistics_efficient += 1` when
  `transport_turns ≤ 1`.
- **Gate:** progress 0 until `logistics_total ≥ 100`.
- **Efficiency:** `eff = logistics_efficient / logistics_total`.
- **Progress:** `p = clamp((eff - 0.25) / (1.0 - 0.25), 0, 1)` → 25%-efficient = 0,
  100%-efficient = 1.
- Lifetime cumulative (not a rolling window). "efficient" = 0 or 1 transport turns.

### 5.3 Richest — sustained profit  (MAX_SCORE 1000)
- **Per-turn retained profit:** `rp = summary.money_in - summary.money_out` (post-tax,
  post-dividend — both already in `money_out`).
- **Smoothing:** push `rp` into `richest_window` (cap `RICHEST_WINDOW = 5`); `metric =
  average(richest_window)`. (Smoothed so a one-off spike doesn't decide the track; best-ever
  capture means a bad turn won't claw it back.)
- **Progress:** `p = clamp((metric - 2000) / (12000 - 2000), 0, 1)`.

### 5.4 Widest — geographic spread  (MAX_SCORE 1000)
- **Metric:** count of **distinct `tile_id`** that have ≥1 building where
  `MatchState.is_player_owned(b)` and `Catalog.get_building(b.building_id).category !=
  "infrastructure"`. (Power/battery plants count; only roads/rail/pipes/cables/ports are
  infra.) Recompute each tick by scanning `MatchState.buildings.values()` (cheap; a few
  hundred entries max).
- **Progress:** `p = clamp((tiles - 30) / (230 - 30), 0, 1)`.

### 5.5 Greenest — clean grid  (MAX_SCORE 1000; requires §4.1)
- **Total power this turn:** `total = summary.power_supply` (int aggregate).
- **Green power this turn:** sum of `summary.power_supply_by_type[bid].amount` for the three
  green building_ids: `solar_farm` (b_024), `onshore_wind_farm` (b_025), `offshore_wind_farm`
  (b_026). Match by building_id resolved from internal name via Catalog, so it survives id
  renumbering.
- **Gate:** progress 0 unless `total ≥ 500` AND `green/total ≥ 0.20`.
- **Progress (when gated in):** `share = green/total`; `p = clamp((share - 0.20) / (1.0 -
  0.20), 0, 1)`.

> Greenest live progress reflects the current grid mix; best-ever capture means once you've
> hit a green share you keep the credit even if you later add fossil capacity.

---

## 6. Win condition & victory moment

- On each scoring tick, after recompute: if `not won and total ≥ WIN_THRESHOLD (4000)` →
  set `won = true`, `won_turn = current_turn`, emit `victory_achieved(total, turn)`.
- `total = base + Σ track_contribution`. With base 3000→0 and 5×1000 tracks, this yields the
  §5.0 win curve (1 track @ turn 100 → 4 tracks @ turn 300). Max achievable total = 3000 + 5000
  = 8000 early-game; you never need more than 4 tracks (4000) since base covers the rest until
  turn 300, and at turn 300 the game ends.
- **Latched:** once won, stays won (base decay can't un-win you).
- **Victory moment (minimal):** HUD listens for `victory_achieved` and (a) auto-opens the
  Victory panel with a "VICTORY — score N on turn T" banner, and (b) shows a toast. The game
  is **not** force-ended (the player may keep playing / pushing score). A future iteration can
  reuse `TurnManager.game_ended_signal` for a hard end-screen.
- Edge: if a loaded save already has `won = true`, do not re-emit; the panel shows the won
  state.

---

## 7. Save / load / reset

- `export_state` / `import_state` round-trip every saved field in §3. All are JSON-safe
  (ints, floats, arrays of dicts, bools) — no node/route geometry.
- `reset()` (on `MatchState.state_reset`): zero counters, clear buffers/history, `won=false`,
  `won_turn=0`. Mirrors the established reset pattern (match_state.gd `reset()` ~L1135).
- Import after reset: `MatchState.reset()` at the top of `import_snapshot` fires `state_reset`
  → VictoryState resets → then `VictoryState.import_state(...)` overwrites with the snapshot.
- Backward-compat: missing `"victory"` key → `import_state({})` leaves a fresh zero state
  (old saves load fine).

---

## 8. UI — top-bar widget

### 8.1 Mount & wiring (top_bar.gd)
- Built in code; add the widget as a sibling in the existing HBox:
  `money_widget.get_parent().add_child(victory_widget)` (same pattern as NotificationBell /
  Save button, top_bar.gd ~L25/L35).
- It is a `Button` (clickable). `pressed` → open the Victory panel (via the panel toggle in
  §9.1). Connect `VictoryState.score_changed` → refresh.

### 8.2 Appearance
- A compact control: **five thin vertical fill rectangles** (one per track, left→right:
  Autarkic, Logistics, Richest, Widest, Greenest) + a `score / 4000` numeric label. Optionally
  render the decaying **base** as a faint sixth backdrop bar or a thin underline so the time
  pressure is visible at a glance.
- Each bar: a track-background rect (`DS.PALETTE.BG_INSET` / 10% white) with a bottom-anchored
  fill whose height = that track's **best progress** (0–1), tinted per track (see §8.4).
- Reuse the fill/track idiom from `tile_info_panel_v2._make_meter_row` (track PanelContainer +
  ratio-driven fill), rotated to vertical (fill anchored bottom, height = `progress * H`), or
  draw via a tiny `_draw()` Control with `draw_rect`.
- Label: `"%d / 4000" % total`, `theme_type_variation = "Numeric"`. Tint by proximity to win
  (e.g. `TEXT` → `OK` as it approaches/passes 4000; `OK` solid once `won`).
- Tooltip: one-line summary ("Victory 2,400 / 4000 (base 1,500) — click for details").

### 8.3 Breakdown dict (what `get_breakdown()` returns — drives both UIs)
```
{
  total: int, base: int, win_threshold: 4000, won: bool, won_turn: int, turn: int,
  tracks: [
    { key:"autarkic", name:"Autarkic", color:Color, progress:float(best), live:float,
      contribution:int, max_score:int,
      metric_text:"Streak 18 / 30 turns", explain:"Consecutive turns buying nothing from market",
      trend:Array[float],   # last TREND_LEN progress values for a sparkline / ▲▼
      # autarkic-only transparency fields:
      purchases_this_turn:{input:int, building:int, upgrade:int, other:int},
      purchases_lifetime:{input:int, building:int, upgrade:int, other:int}
    },
    ... (logistics, richest, widest, greenest)
  ]
}
```

### 8.4 Track colors (DS-derived, distinct)
Autarkic = `WARN` (amber), Logistics = `ACCENT` (cream), Richest = `OK` (green),
Widest = a steel blue (`ACTION_BLUE_TOP`), Greenest = a brighter green (`OK`.lightened).
(Final palette is a polish detail; keep them DS tokens, not raw hex.)

---

## 9. UI — fullscreen Victory panel (scripts/victory_panel.gd)

### 9.1 Mount & toggle
- A `Control` under `HUDContent` (same parent as `ResearchPanel`, main.tscn ~L661), full
  anchors with the same insets (`offset_top 32`, `offset_bottom -130`, L/R `±10`),
  `visible=false`, `mouse_filter=STOP`.
- Toggle through the existing panel machinery: `PanelStack.push(self)` on show /
  `PanelStack.remove(self)` on hide (so Esc closes it; bottom_menu.gd `_set_panel_visible`
  ~L240). Opened by the top-bar widget click and closed by its own X button.
- A top-right close button identical to research_panel's `_create_close_button`
  (research_panel.gd ~L122).

### 9.2 Visual language (borrow research_panel's look, build with nodes)
Recommendation: **node-based layout** (PanelContainer cards + Labels + meter bars) rather
than research_panel's immediate-mode `_draw`. Borrow the *look* — navy fill
(`DS.PALETTE.BG_PANEL`), cream borders (`BORDER`/`BORDER_SOFT`), the `_make_stylebox`
card recipe, the header bar + close button — but lay out with containers (far simpler for
text + bars + trends than `_draw`). Use DS variations: `"Title"` (header), `"Section"`
(card titles), `"Body"` / `"Caption"` (text), `"Numeric"` (scores).

### 9.3 Layout
- **Header:** "VICTORY PROGRESS" (Title), right-aligned `total / 4000` (Numeric, big), and a
  caption line that makes the decaying component explicit:
  `Base time score: N / 3000 (turn T of 300)  ·  track score: M  ·  need 4000` +
  win state ("Win at 4000" / "✓ Won on turn T"). Optionally a one-line hint of the curve
  ("turn 100: 1 track · turn 300: 4 tracks").
- **Five track cards, 3 on top row + 2 on bottom row** (a `GridContainer` columns=3, the
  two bottom cards span/centre; or two HBox rows). Each card (a `Card`/`Outlined`
  PanelContainer):
  - Track name (Section) + its color swatch / icon.
  - **Current track score** `contribution / max_score` (Numeric).
  - **Threshold progress bar** (the meter idiom) showing best progress, with the live value
    ghosted behind if it differs.
  - **Metric line:** the concrete number vs thresholds, e.g.
    - Autarkic: `Streak 18 / 30 (start 10)`
    - Logistics: `Efficiency 62% over 240 moves (need ≥100; 25%→100%)`
    - Richest: `Avg profit £7.4k/turn (£2k→£12k)`
    - Widest: `84 / 230 tiles (start 30)`
    - Greenest: `Green 41% of 1,200 MW (need ≥500 MW & ≥20%)`
  - **Autarkic transaction breakdown (transparency):** a small four-row tally of market buys
    by category — `Inputs · Building · Upgrades · Other` — showing **this turn** (what reset
    the streak, e.g. "this turn: 4 inputs") and **lifetime** totals. When the streak is alive,
    show "this turn: none — streak +1" in `OK`.
  - **Explanation:** one muted Caption sentence of how to raise it.
  - **Recent trend:** a tiny sparkline (last `TREND_LEN` progress values) or a ▲/▼ delta vs
    `TREND_LEN` turns ago, from `track.trend`.
- Refreshes on `VictoryState.score_changed`; also repopulates on open.

---

## 10. Constants (all tunables, one block in victory_state.gd)

```
WIN_THRESHOLD        = 4000
BASE_MAX             = 3000     # base = max(0, BASE_MAX - max(0, turn-BASE_FREE)*BASE_DECAY)
BASE_FREE            = 100      # full base through turn 100
BASE_DECAY           = 15       # = BASE_MAX/(BASE_ZERO-BASE_FREE); base hits 0 at turn 300
BASE_ZERO            = 300      # (== TurnManager.MAX_TURNS) — documentary; decay derived from it

TRACK_MAX = { autarkic:1000, logistics:1000, richest:1000, widest:1000, greenest:1000 }
                                 # all equal — no track is worth less

AUTARKIC_START       = 10        AUTARKIC_CAP   = 30
LOGI_MIN_MOVES       = 100       LOGI_EFF_TURNS = 1     LOGI_FLOOR = 0.25
RICHEST_WINDOW       = 5         RICHEST_LO     = 2000  RICHEST_HI = 12000
WIDEST_LO            = 30        WIDEST_HI      = 230
GREEN_MIN_POWER      = 500       GREEN_FLOOR    = 0.20
GREEN_BUILDINGS      = ["solar_farm","onshore_wind_farm","offshore_wind_farm"]
PURCHASE_CATEGORIES  = ["input","building","upgrade","other"]

TREND_LEN            = 10
```

Win curve (base + track ≥ 4000): turn ≤100 → 1 track; turn 200 → ~2.5; turn 300 → 4 tracks.
Max total = `BASE_MAX + Σ TRACK_MAX = 8000` early game (you only ever need 4000). Tuning levers:
raise `WIN_THRESHOLD` or lower `BASE_MAX` to demand more tracks sooner; change `BASE_ZERO` to
move where the 4-track wall lands.

---

## 11. Decisions

**Locked by your direction:**
- **Autarky scope** — *any* market buy of any category (input / building / upgrade / other)
  breaks the streak; the panel shows a per-category transaction tally. (§5.1, §4.2, §9.3)
- **Per-track max** — all five worth 1000; no track is halved. (§10)
- **Win curve** — fixed 4000 threshold + decaying base (3000→0) gives 1 track @ turn 100 →
  4 tracks @ turn 300. (§5.0, §6)

**Remaining recommendations (flip a constant/flag to change):**
1. **Logistics movement unit** — *Recommended:* one count per queue call (a multi-good
   manifest = 1 movement). *Alternative:* per good/per shipment (count inside the manifest loop).
2. **Logistics window** — *Recommended:* lifetime cumulative (matches "after at least 100
   movements"). *Alternative:* trailing-N window so late play can still move the bar.
3. **Richest smoothing** — *Recommended:* 5-turn trailing average + best-ever capture.
   *Alternative:* raw current-turn retained profit (more volatile), or cumulative net worth.
4. **Monotonic tracks** — *Recommended:* best-ever per-track contribution (bars only fill;
   clean latched win). *Alternative:* live contributions (bars can drop; win still latches).
5. **Victory moment** — *Recommended:* auto-open panel + toast, game continues.
   *Alternative:* hard end-screen via `TurnManager.game_ended_signal`.
6. **Autarky transaction unit** — *Recommended:* one transaction per `queue_buy` call (matches
   the logistics unit). *Alternative:* per good / per unit bought.

---

## 12. Testing plan (tests/test_runner.gd)

Pure-logic, no UI:
- **Base score:** turns 1/100/200/300/350 → 3000/3000/1500/0/0.
- **Win curve:** assert `base(100)+1000 ≥ 4000`, `base(300)+3000 < 4000`, `base(300)+4000 ≥ 4000`
  (1 track wins at 100, 4 needed at 300).
- **Autarkic:** record a `buy` of each category (`input`/`building`/`upgrade`/`other`) → streak
  resets and `purchases_this_turn[category]` increments for each; a turn with only a `move`/`sale`
  does NOT reset; progress 0 at ≤10, ramps, caps at 30; lifetime tally accumulates.
- **Logistics:** record movements (mix of 0/1/3 turns); assert progress 0 below 100 moves,
  then `(eff-0.25)/0.75`, including a 0-turn movement counting as efficient.
- **Richest:** push retained-profit sequence; assert 5-turn average maps [2000,12000]→[0,1]
  and best-ever doesn't regress.
- **Widest:** add player non-infra buildings across distinct tiles (+ an infra building and an
  NPC building that must NOT count); assert distinct-tile count and [30,230] mapping.
- **Greenest:** synthesize a summary with `power_supply` and `power_supply_by_type`; assert
  gate (total<500 or share<0.20 → 0) and [0.20,1.0]→[0,1] above gate.
- **Total + win:** assemble a breakdown crossing 4000 → `victory_achieved` fires once,
  latches, survives a base-decay drop.
- **Save/load:** export → reset → import → identical state (incl. `won`, history, buffers,
  per-category purchase tallies).

---

## 13. Implementation phasing

1. **Engine prereqs:** `power_supply_by_type` (§4.1) + `goods_movement_recorded` (§4.2).
2. **VictoryState autoload** + save/load wiring (§3, §4.3, §7) — scoring + win, no UI.
   Add the §12 tests here (green before any UI).
3. **Top-bar widget** (§8) — read-only, opens nothing yet, just shows score + bars.
4. **Victory panel** (§9) + wire the widget click + victory moment (§6).
5. **Polish:** trends/sparklines, colors, victory banner copy.

---

## 14. Risks & perf

- **Perf:** per-turn cost is a single scan of `MatchState.buildings` (Widest) + dict reads;
  negligible vs production. Movement signal is O(1) per movement.
- **Greenest coupling:** depends on the new `power_supply_by_type`; if a power building bypasses
  the standard `record_produced` path it won't be attributed — audit power output sites when
  implementing §4.1.
- **Autarky** is strict (any input auto-buy breaks it) and is the most likely track to need
  threshold tuning after playtest (`AUTARKIC_START`/`AUTARKIC_CAP`).
- **Balance:** the win curve hinges on three constants — `WIN_THRESHOLD` (4000), `BASE_MAX`
  (3000), `BASE_ZERO` (300). Raise the threshold or lower `BASE_MAX` to demand more tracks
  earlier; move `BASE_ZERO` to shift where the 4-track wall lands. Validate with the §12
  win-curve test after any change.
