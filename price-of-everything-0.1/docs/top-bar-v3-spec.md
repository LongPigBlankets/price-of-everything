# Top Bar v3 — thin bar, transport module, anomaly popups

Status: SPEC, decisions resolved with owner 2026-08-20 (§7). Nothing implemented.
Owner request: three changes — (1) thinner restyled bar with LED status lights,
(2) a transport button + logistics panel, (3) anomaly popups under the money and
power modules — plus the rankings module face change and a bar-wide text pass.

Primary file: `scripts/top_bar.gd` (Top Bar v2, 1856 lines). Everything below
cites the code it touches.

---

## 1 · Bar restyle: thinner, flatter, brighter

### 1.1 Height

Current geometry (`top_bar.gd:32-35`): `BAR_H := 69`, `MOD_H := 48`, module
stylebox padding 14/14/5/5 (`_module_box`, `:231-241`), bar content margins
6 top / 6+`EDGE_H` bottom (`_style_bar`, `:183-184`), metallic bezel
`EDGE_H := 7` — **bezel stays** (owner decision).

Target: **BAR_H ≈ 53, MOD_H ≈ 38** (final by eye). Budget: 4 top + 38 module +
4 bottom + 7 bezel. Gained by:

- Removing the module chrome (below) and its vertical padding (5/5 → 2/2).
- Capping every module at **two text lines** (head + sub). The only 3-line
  module today is Rankings (`_tag("Rankings")` + head + sub, `:491-495`) — the
  tag row is deleted (§2). `_tag()` (`:244-249`) loses its last caller; remove it.
- The briefing notch (`NOTCH_H := 102`, hangs below the bar) is unchanged; its
  centring math keys off the bar rect, so it follows the new height for free
  (`_recenter_notch`).

### 1.2 Remove per-module outline and shading

Delete the button-by-button box look:

- `_module_box()` (`:231`): no border (`set_border_width_all(0)`), transparent
  bg in the normal state. Modules become flat text on the bar.
- `_ModuleBtn._draw()` sheen polygon (`:283-289`) and the `_Sheen` class
  (`:295-307`, mounted on Treasury/Encyclopedia buttons) — delete both.
- Treasury `money_widget` stylebox overrides (`:344-345`) use the same
  `_module_box`, so they flatten with it.
- Keep the `_divider()` hairlines (`:317-325`) — with boxes gone they are the
  only section separators; height tracks the new MOD_H.
- Hover affordance: hover paints a faint `Color(1,1,1,0.05)` rounded fill
  only; active keeps `C_ACTIVE_BG`. (Proposal, unobjected — ships.)
- The old warn state (red-tinted border `C_WARN_BORDER`, `:56`) is **replaced
  by the LED lights** (§1.3); delete the warn border path.

### 1.3 LED status lights

Each signalling module gets a small LED-style lamp: a **5px-radius dot with a
glow**, drawn as concentric alpha circles (no shader needed). Two states only:

- **Red** — problem. Fill `C_RED #e2604a` core with a brighter centre
  (`lighten ~0.3`) and 2-3 soft outer glow rings (red at alpha .35/.18/.08).
- **Unlit** — dark grey, no glow: `EDGE_SEAM #3a4048` fill with a faint
  inner-shadow ring. Never any third colour.

Placement: leading edge of the module row, vertically centred (reads like a
panel lamp next to the module's text). Updated in the coalesced refresh
(`_queue_refresh`) once per resolved turn.

| Module | Red when | Data source |
|---|---|---|
| Treasury | `MatchState.money < 0` AND last turn's profit < 0 | money + `Production.last_turn_summary` (money_in − money_out) |
| Transport (new, §3) | **> 1** stockpile full and rejecting shipments, OR **> 3** infra links over capacity | `Stockpile.get_refused(tile) > 0` count (`stockpile.gd:283`); congestion tier ≥ 1 link count (`match_state.gd:5183`) |
| Power | any building suffering an intermittency derate, OR buildings drawing grid power while profit < 0 | Production intermittency bookkeeping (`get_building_intermittency` family — expose a cheap per-turn count); `grid_bought > 0` + profit sign |

The power grid-draw case lights **power only** — the treasury LED stays dark
unless its own condition holds (owner note: "no light for money but red light
for power").

No LED at all on Rankings, Encyclopedia, or Goods Graph (owner exclusion), nor
on Victory / Council / Briefing (no red condition defined — a permanently
unlit lamp is noise).

### 1.4 Bar colour = end-turn container blue

The bar today is flat `C_BAR_BG #0c1c2e` (`:50`). The end-turn dock's container
navy is the 4-corner gradient at `end_turn_dock.gd:28-31`:

| const | value | hex |
|---|---|---|
| `ETN_TL` | (0.07, 0.30, 0.50) | `#124D80` |
| `ETN_TR` | (0.00, 0.14, 0.27) | `#002445` |
| `ETN_BL` | (0.00, 0.11, 0.22) | `#001C38` |
| `ETN_BR` | (0.00, 0.045, 0.10) | `#000B1A` |

Owner decision: **the same 4-colour gradient, spread over the bar's full
span** — TL→TR across the whole width on the top edge, BL→BR along the bottom,
so the sweep that covers the dock's small face stretches across the entire
bar. Drawn in `_draw()` (`:201`) replacing the flat stylebox fill; the existing
ambient sweep polygons (`:208-213`) become redundant — delete them. The
metallic bottom bezel (`:214-229`) stays. Extract the four constants to a
shared home (DS or a small shared const file) so dock and bar can never drift.

### 1.5 Text colour pass — no dark-on-dark

Owner rule (extends the one recorded at `ds.gd:50`): **any text that is
currently dark navy on a navy background, or grey on a dark background, goes
to the off-white** the panels use, `DS.PALETTE.TEXT` (#E8EEF7). Semantic
colours are unaffected.

- Replace all `C_TEXT #cdd9e6` and `DS.PALETTE.TEXT_DIM` label colours in
  `top_bar.gd` (tags, subs: `:248`, `:408`, `:466`, `:494`, briefing sub,
  council status, date label) with `DS.PALETTE.TEXT`.
- `C_BRIGHT #f3f8fd` stays (already off-white; optionally alias to TEXT).
- Semantic colours stay: `C_GOOD`/`C_BAD` net-per-turn and ranking movement,
  `C_AMBER` warnings, `C_RED` runway, `C_CREAM` victory score.
- While in there, sweep the bar for any other dark-navy-on-navy strings (the
  same audit as the 9 Aug `TEXT_DIM` bump) — the rule is the contrast, not
  the specific constant.
- The §4 popups use `DS.PALETTE.TEXT` for all copy — off-white, never grey.

### 1.6 Contracts preserved

Unchanged (listed at `top_bar.gd:11-14`): `money_widget` node path (e2e),
`%EncyclopediaButton` / `%TurnCounter` unique names (world_map + tutorial
spotlights), the three `*_clicked` signals, bankruptcy strip, CFO intro popup.

---

## 2 · Rankings module face

Current face (`_build_rankings`, `:479-498` + `_refresh_rankings`, `:500-511`):
tag "RANKINGS" + "▲ 10TH OF 10" + "£N total revenue".

New face, two lines:

- Line 1 (head): unchanged — `"%s %s of %d"` from `CompanyRankings.standings()`
  (rank, movement arrow, colour by movement).
- Line 2 (sub): **"X goods you lead in"** — X = count of rows in
  `CompanyRankings.goods_standings()` (`company_rankings.gd:113`) where the
  player is rank 1. No revenue figure anywhere on the face.
- Delete the `_tag("Rankings")` row.
- The rankings flyout (`_toggle_fly("rankings")`) is unchanged. No LED.

Edge case: X = 0 → "0 goods you lead in" stays honest and is the motivating
read; no special casing.

---

## 3 · Transport module + logistics panel

### 3.1 Module face (new, sits between Victory and Rankings)

A new `_ModuleBtn` ("TransportModule") with an LED (§1.3), two lines:

- Head: **"N units → market"** — sum of qty over sale shipments in
  `MatchState.pending_transport_shipments` (`match_state.gd:358`). The exact
  aggregation (sale `items[]` vs move `good_id/qty`) already exists as the
  debug block at `production.gd:652-666` — lift it into a helper.
- Sub: **"Y infra over · Z stockpiles full"** —
  - Y = count of links `tile|mode` in `MatchState.transport_link_flow()`
    (`match_state.gd:5010`) whose flow exceeds
    `tile_mode_capacity(mode, _tile_infra_level(tile, mode))` — i.e. congestion
    tier ≥ 1 (`route_congestion`, `:5183-5217`).
  - Z = count of tiles with `Stockpile.get_used_capacity(t) / Stockpile.get_capacity(t) ≥ 0.95`
    (`stockpile.gd:55,100`), over `tiles_with_stock()` (`:245`).
- Click → opens the **Transport panel** (full DS panel, not a flyout).

### 3.2 Transport panel — DS style, three columns

New `scripts/transport_panel.gd`, built like the other DS panels
(`resource_panel.gd` is the closest template; DS theme + `PALETTE.BG_PANEL`,
cream borders, `TEXT` body). Three columns left → right: **Stockpiles ·
Infra · Units in transit**.

**Column 1 — Stockpiles.** One row per tile from `Stockpile.tiles_with_stock()`,
**ordered by fill % descending** (most full at top — owner decision):

- Tile name — warehouse/stockpile icon — level (`get_warehouse_level`) —
  fill % (`get_used_capacity / get_capacity`).
- Trend glyph over the last 3 turns: ▲ if used capacity rose, ▼ if it fell,
  — if flat (|Δ| < 1% of capacity). Requires the new per-tile history ring
  (§3.3).
- **Turns until full**, estimated: `(capacity − used) / avg net inflow per turn
  over the last 3 turns`, rounded to nearest integer; "—" when net inflow ≤ 0.
- Top goods as framed icons (`UIHelpers.make_framed_good_icon`) from
  `Stockpile.get_top_goods(tile, 3)` (`stockpile.gd:112`).
- Row click → open that tile's Tile View on the **Stockpile tab**: the tab id
  `"stock"` exists (`tile_info_panel_v2.gd:31-35`); needs a small deep-link API
  (`open_for_tile(tile_id, tab := "stock")`) routed the same way world_map
  opens the panel on tile selection.

**Column 2 — Infra.** One row per active link (`tile|mode` key with flow > 0,
from the same snapshot `route_congestion` reads, `_last_link_flow`,
`match_state.gd:373/5166`), **ordered worst-first by % utilisation**
(flow ÷ cap descending — owner decision):

- Mode icon — infra level (`_tile_infra_level`) — **usage this turn out of
  cap**: "flow / cap" (`tile_mode_capacity`).
- **At-capacity count**: "at cap N of last 10 turns" — new per-link history
  ring (§3.3).
- **Congestion cost added**: cumulative £ this link's overloads have added, if
  ever > 0 — new accumulator (§3.3) fed where the marginal congestion
  surcharge is charged (`transport_cost_for_route`,
  `transport_service.gd:72-107`; surcharge semantics documented at
  `match_state.gd:5175-5182`). Attribute each route's surcharge to its
  tightest congested link (the one that set `headroom`) — approximation, noted
  in code.

**Column 3 — Units in transit.** One row per shipment in
`pending_transport_shipments`, **ordered by shipment size** (total qty,
descending):

- Good icons at the usual framed size (`make_framed_good_icon`) — one per good
  in the manifest (sale shipments carry `items[] {good_id, qty, revenue}`;
  moves/purchases carry `good_id`/`qty`, see the purchase shape at
  `match_state.gd:4529-4542`).
- Count as the existing quantity pill — navy capsule, cream border/text
  (`UIHelpers.make_quantity_pill`, `ui_helpers.gd:98`; colours `PILL_NAVY` /
  `PILL_PAPER`, `:10-11`) — the pill already widens with longer text; the row
  widens when it holds multiple good icons.
- **Turns until destination**: `turns_remaining` field.
- **Port icon** when the destination is the market (sale shipments / port
  destination), i.e. goods going to `nearest_port_tile`.

### 3.3 New state (all additive, save-friendly)

| What | Where | Shape |
|---|---|---|
| Per-tile used-capacity history | `Stockpile` | ring of last 4 samples per tile, rolled once per turn (alongside `roll_turn_peaks()`, `stockpile.gd:271`) |
| Per-link at-capacity history | `MatchState` | ring of last 10 booleans per `tile\|mode`, appended in `update_transport_congestion()` (`match_state.gd:5165`) |
| Per-link congestion £ paid | `MatchState` | `Dictionary link_key -> float`, accumulated where the surcharge is charged |

All three export/import in save state; missing on old saves reads as empty
(rows show "—" until history accrues).

---

## 4 · Anomaly popups (money + power)

### 4.1 Component

One new small popup class, instanced under the Treasury module and under the
Power module. DS panel look (`BG_PANEL` bg, cream border), body text
`DS.PALETTE.TEXT` **(off-white, never grey — owner rule)**, width ~320, one
short paragraph. Behaviour:

- Opens when its trigger fires at turn resolution
  (`TurnManager.turn_resolution_completed`, same hook the bar refresh uses,
  `top_bar.gd:134`).
- **Dismissed by clicking anywhere else** — reuse the flyout scrim pattern
  (`_fly_scrim`, `_build_fly_layer`); consistent with flyouts, the dismissing
  click is swallowed. One click dismisses all open popups.
- A new turn's popups replace still-open older ones.
- **Up to 2 money popups may show at once** (owner decision), stacked
  vertically with **15px separation**; the money and power popups may also
  show simultaneously (different anchors).

### 4.2 Money popup triggers (evaluated once per resolved turn)

Baselines use the previous 3 resolved turns' averages, from a new ring of
`Production.last_turn_summary` lines kept by the popup controller (revenue =
`goods_sales_revenue + power_sales_revenue`; cost lines per `COST_LINES`
naming in `telemetry_state.gd:52-65`). No trigger fires before 3 turns of
history exist. Priority when more than 2 fire: **loan > spend > transport >
big payment** (owner-confirmed); 5-turn cooldown per trigger.

1. **Loan taken** — new loan principal drawn since the last resolved turn.
   Counts BOTH the auto-bridge (`solvency_state.gd:91/180`) and spread
   financing — owner ruling: 48-turn spread = 12 turns grace + 36 repaying,
   i.e. a loan at standard interest.
   Copy: **"We've taken a £X loan to cover this turn's bills."** (X = total
   new principal this turn.)
2. **Big payment** — turn revenue ≥ **150%** of the 3-turn average. Copy
   (owner-confirmed split): one good dominates the payout →
   "You sold A units of [good name] to the global market which earned you
   £B of profit." — otherwise →
   "You sold an unusually high X units of Y goods."
3. **Abnormal spend** — an operating cost line (inputs / labour / maintenance /
   power), each measured against **its own** 3-turn average, hits ≥ **150%**.
   One generic sentence for all lines (owner decision, reworded to "running
   costs"): **"We're spending abnormal amounts of money: £X due to running
   costs for [building name]."** — or "… for [N] buildings." when no single
   building dominates. Building attribution from the per-building cost
   breakdown Production already keeps for the Building Detail panel
   (`production.gd:688`).
4. **Transport** — transport costs up **> 25%** vs the 3-turn average AND
   revenue has not risen by the same absolute amount
   (`Δtransport > 0.25 × baseline_transport` and `Δrevenue < Δtransport`).
   Copy: "Transport costs are through the roof. Check if we're shipping by
   the most efficient transport."

### 4.3 Power popup triggers

Inputs from the turn summary: `power_supply`, `power_demand`, `grid_bought`
(read exactly as `_power_stats()` does, `top_bar.gd:421-439`).

1. **Production drop** — `power_supply(t) ≤ 0.8 × power_supply(t−1)`.
   Copy: "Our power plants are going dark!"
2. **Intermittency introduced** — fires when the run's **first intermittent
   green generator comes online** (owner-confirmed — the teachable moment,
   ahead of the first derate). Latched once per run; latch rides the save.
   Production already tracks intermittency (`get_tile_intermittency`,
   `get_building_intermittency`).
   Copy: "Renewable power's great but what do we do when the sun doesn't
   shine or the wind doesn't blow?"
3. **Consumption jump / net flip** — `power_demand(t) ≥ 1.2 × avg(demand,
   last 3 turns)` OR net position flips from `supply ≥ demand` at t−1 to
   `supply < demand` at t.
   Copy: "We're drawing power from the grid for now but this is becoming
   expensive."

---

## 5 · Out of scope

- The rankings flyout, victory flyout, treasury flyout, briefing notch and
  council module keep their current behaviour.
- No sim changes: every number above is already computed or is additive
  bookkeeping; production order and costs are untouched.
- Toast system changes (duration, persistence) are tracked in the demo
  roadmap, not here — but note the auto-bridge briefing notice and the §4.2
  loan popup overlap; the popup should supersede the toast for that event.

## 6 · Resolved decisions (owner, 2026-08-20)

1. Bezel: **keep**. LED status lights added (§1.3): 5px-radius glowing dot,
   red or unlit-grey only; red conditions per module as tabled; no light on
   Rankings / Encyclopedia / Goods Graph.
2. Bar colour: the dock's 4-colour gradient **stretched across the bar's full
   span** (§1.4).
3. Text pass targets **dark navy on navy and grey on dark** — those go to
   off-white; semantic colours stay (§1.5).
4. Loan popup copy as proposed; **spread financing counts as a loan**
   (12 grace + 36 repay at standard interest) (§4.2.1).
5. Sale copy split: dominant-good detailed sentence vs aggregate (§4.2.2).
6. Spend popup: one generic sentence, "running costs" wording (§4.2.3).
7. Popups: **max 2 at once, 15px apart**, priority loan > spend > transport >
   big payment (§4.1, §4.2).
8. Intermittency popup: first generator online (§4.3.2).
9. Sorts: stockpiles most-full-first by %, infra worst-first by % utilisation,
   transit largest-first (§3.2).

Assumptions shipping unless objected: hover = faint fill (§1.2); LEDs exist
only on Treasury / Power / Transport — Victory / Council / Briefing have no
red condition defined, so they carry no lamp (§1.3).
