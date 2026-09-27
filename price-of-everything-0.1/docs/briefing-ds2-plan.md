# Turn briefing: how it is used, what it holds, and a DS2 arrangement

Status: planning, 27 September 2026. Nothing of the DS2 look is built. One concept study is rendered for the owner (§5): `artifacts/briefing_ds2/briefing_study_v1.png`, render set `briefingstudy` (seed 460) in `tools/button_mockup/cluster.html`, a study and not a game layer. Captures of today's briefing and dock: `artifacts/briefing_ds2/before/` (contact sheet `artifacts/briefing_ds2/before_contact_sheet.png`), made by `tools/briefing_tour_shot.tscn`.

Read with `docs/ds2-theme.md` (the look, the kit, §13 and §14 for the method), `docs/ds2-owner-decisions.md` (settled rulings: the updates dock, Digital displays, copy) and `docs/turn-briefing-panel-spec.md` (the July spec this panel was built from). The tile view's plan is the model for this one.

## 0. The brief

The owner, 27 September 2026: "look at the notices / update panel appearing midscreen. That needs a revamp."

The panel is the "THIS TURN" briefing: a 900 × 640 navy card in the middle of the screen with a list on the left (Decisions, Alerts, Info) and the chosen item on the right. This plan reviews what it is for, where it should sit and how it relates to the updates dock, then proposes one DS2 concept. It adds **no new player action**.

## 1. How it is used

### 1.1 When it appears, and the ways in

| Way in | From | Lands on |
|---|---|---|
| Turn start, a decision waiting or a new critical alert | `TurnBriefing._on_turn_advanced` → `expand()` | the first decision, else the first critical alert |
| A decision drawn mid turn (story beats, cheats) | `DecisionState.decision_drawn` | the same |
| End Turn refused | `TurnManager.commit_blocked_by_decisions` → expand and flash | the same |
| The dock's pen | `toast_manager.gd _open_decisions` (toggles) | the first decision, or the list with none |
| The top bar's bankruptcy strip | `top_bar.gd` → `expand("alert:bankruptcy")` | the bankruptcy alert |
| A save loaded with a decision waiting | `_on_match_loaded` | the first decision |

Ways out: the header's ▴ key, the footer's Collapse key, Esc (PanelStack), the pen again, opening a top bar flyout. There is no collapsed form on screen any more: the top bar turned the old strip off (`TurnBriefing.strip_enabled = false`), so once collapsed only the pen's pill says anything, and it counts decisions only.

### 1.2 What blocks the end of the turn

Only decisions. `TurnManager.commit_turn()` refuses while `DecisionState.pending_queue` holds one (cap 4); the briefing then opens and flashes. Alerts never block. The tutorial shows decisions only.

### 1.3 The jobs it does

1. **Answer a decision**: read the letter, weigh the choices, pick one (blocks the turn).
2. **Notice what went wrong last turn**: starved buildings, full or undersized storage, cash short for inputs, cables full, a deposit running out, bankruptcy near.
3. **Go and fix it**: a row opens the building or the tile (storage rows open the Stock tab).
4. **Quieten it**: Dismiss, until the condition worsens.

Telemetry records none of this (no briefing event in `TelemetryState`).

## 2. What it holds, by item type

Captured on turn 4 of a seeded start (`tools/briefing_tour_shot.tscn`): one decision, three alerts, one info echo.

| Type | Source | Figures today | Actions |
|---|---|---|---|
| **Decision** (blocking) | `DecisionState.pending_views()` | none as figures: the choices' effects are one sentence each from `_describe_effects` ("a one-off £200 loan at 5% as a signing gift") | a Choose key per choice card (resolve), no dismiss |
| **Bankruptcy near** | `_bankruptcy_item`: cash + `LoanState.available_capacity()` under £100 | cash, loan capacity left, net last turn, runway | Dismiss |
| **Buildings starved** | `Production.missing_by_building`, less cable capped plants | starved of power, starved of inputs (counts) | a row per building (Go), Dismiss |
| **Storage full** | `TransportState.overflow_shipments`, `last_turn_summary.input_orders_capped` | units waiting, units of orders cut | a row per tile (Stock tab), Dismiss |
| **Stockpile too small** | `last_turn_summary.storage_overcommitted` | working set over capacity, tiles | a row per tile, Dismiss |
| **Cables full** | `_cable_capped_producers` | plants, MW blocked, tiles at top cable level | rows, Dismiss |
| **Deposit running out** | `last_turn_summary.deposits_running_out` | turns left, remaining, rate | rows, Dismiss |
| **Cash short for inputs** | `last_turn_summary.input_orders_short` | orders skipped, extra cash needed | rows, Dismiss |
| **Inputs spliced** (info) | `last_turn_summary.input_splices` | local and market units | rows, Dismiss |
| **Bell events** | `EventScheduler.active_events()` of the last two turns: research (rolled up), construction done, decision resolved or incoming, bridge loan, deposit exhausted, tile at capacity, policy enacted, forewarnings | the event's body | Go to it, Acknowledge (news), Dismiss |

The header repeats the turn and the cash. The footer says "1 decision must be answered before you can end the turn." or "All caught up — you can end the turn."

## 3. Findings

1. **It covers the game.** A 900 × 640 card in the middle of the screen, opening by itself at the start of any turn with a decision or a new critical alert, over the map and whatever the player had open.
2. **Two places say the same thing.** Research unlocks show as a briefing item and as green dock rows (`top_bar._refresh_briefing` posts them). An answered decision comes back as an Info item ("Decision: A Retired Man Who Misses the Work") and as a dock row. A full tile is told three ways: the Storage full alert, a "tile at capacity" bell event, and the capacity dialog, a second mid screen modal that was open behind the briefing in the captures ("Tile (10, 2) has reached maximum capacity").
3. **Alerts vanish when collapsed.** With the strip off, nothing on screen says an alert is live; the pen counts decisions only and the red bell counts toasts, not alerts.
4. **A dead reference.** The dismiss hint says "stays in the bell", but the notification bell is no longer mounted anywhere.
5. **Coordinates and ids on screen.** Rows read "Lightning Bourne - (10, 3)   tile_10_3   — missing silica" (`Catalog.tile_label` and the raw id); event titles read "(10, 2) at capacity".
6. **Zeros shown.** "Starved of power: 0 buildings", "Goods waiting to unload: 0 units" (DS2 rule 9).
7. **One jam, three alerts.** Thistle River Valley is at once "lacks stockpile" (critical, 816 needed against 800), "Storage full" and a starved building; nothing ties them together, and the smallest overrun carries the worst severity.
8. **Decisions have no figures.** The £200 loan and the 1000 freight units are words in a sentence; "Affects: the company" is noise; the choice cards are 300 px tall and mostly empty; the keys say only "Choose".
9. **Duplicated chrome.** Cash and turn repeat the top bar; Collapse appears twice; the 224 px list stays up for a single item.
10. **Copy and contrast.** Dashes, middle dots, hyphens and ellipses ("All caught up — …", "re-surfaces only if it worsens · stays in the bell", "…and 2 more in the Ledger", "≈816"); unselected list titles and the hint in `TEXT_MUTED`, research conditions in `TEXT_DIM`, on navy (`CLAUDE.md`).
11. **Icons that don't say what.** Starved uses the goods icon, storage the map modes icon; the list's status marks are drawn triangles and rings with no meaning of their own.

## 4. The arrangement

**Principles.** One place per kind of message. Decisions are letters to answer; alerts are live conditions shown as lamps; one-off news is a dock row. One width. Every figure from the engine's helpers (§6). Show only what informs.

**Placement: the tray over the dock, bottom left** (recommended; decision 1). The briefing stops being a card in the middle and becomes the dock's own tray, rising from behind the dock at x 12, 460 logical px wide, growing up to its content and never above the top bar's 72 px line (the rest scrolls). The pen opens it; the bells open the rows. It no longer covers the middle of the map, the tile view and Building Detail (docked right) or the top bar; it can cover a bottom menu panel (Construct, Market) while it is up, as the dock's rows already do. Weighed and set aside: mid screen (today; covers the game), a slide-out on the right (collides with the tile view and Building Detail), under the top bar in the middle (covers the map's centre and the money).

**Decisions against alerts.** Decisions head the tray, one letter at a time ("1 of 2"), each with its answer keys; while one waits the tray opens by itself at turn start, as today. Alerts are an annunciator: one window per kind, lit amber or red with its count, dark when clear. Picking a lit window shows its readout and rows; with a decision waiting the readout stays shut, so the letter keeps the room.

**Relation to the dock** (decision 3). The tray and the dock's rows are one surface with two leaves: the pen shows the briefing, the bells show rows. Everything that is a one-off event (research, construction done, a decision answered, the bridge loan, news, forewarnings) becomes a dock row only and leaves the briefing. The briefing keeps what persists: decisions until answered, alerts while the condition holds. The "tile at capacity" event and the capacity dialog fold into the Storage full window (decision 7).

**Collapsed.** The pen carries a lamp that follows the annunciator (amber or red while any window is lit), beside its decision count, so a live alert is visible with the tray down.

| Zone | Holds |
|---|---|
| Head | THIS TURN nameplate; a key to put the tray down |
| Gate | a readout with a lamp: "Answer 1 decision before you end the turn." (amber) or "No decisions waiting. You can end the turn." (green) |
| Letter | the decision on a clipboard: kicker, "1 of 1", title, body |
| Answer | the choices as cream keys, what each brings beside it, figures on screens |
| Annunciator | eight windows: Starved, Cash short, Bankruptcy, Cables full, Storage full, Stockpile small, Deposit low, Deposit out |
| Readout | the picked window's name and one line of why |
| Rows | per building or tile: the missing good in its well, the place (no coordinates), Go to |
| Dismiss | Dismiss and "It lights again if it gets worse." |

## 5. The DS2 concept: the foreman's clipboard and the annunciator

Study: `artifacts/briefing_ds2/briefing_study_v1.png` (the raw render beside it, `_render.png`). Both states over the real screen at their place, one width, 460 logical px (862 layout): (1) the founder's decision with three windows lit; (2) alerts only, Starved picked. Words and figures are the turn 4 captures'.

| Part | Metaphor | What it is on screen |
|---|---|---|
| Tray | the works office's dispatch tray | the top bar's and dock's navy steel, no trim, screws in its top corners; its foot tucked behind the dock |
| Title | a nameplate | THIS TURN raised white Bebas on black enamel, four rivets (the tile view's and People's plate) |
| Put down | a small key | Building Detail's small cream key with a chevron |
| Gate | the shift's status readout | `BdpV3Readout`: dark glass, a pilot lamp, one white line |
| Decision | a letter on a foreman's clipboard | tempered hardboard board, a pressed steel clip with a chrome roll, the letter on the keycaps' cream plastic printed navy: DECISION, 1 of 1, the title in Barlow, the body in Plex |
| Answer | the reply keys on a gunmetal plate | a wide cream key per choice with its label ("Give him the CFO's chair"), two white lines beside it; money on an LED (£ 200.0, the loan), counts on a drum (1000 freight units) |
| Alerts | an annunciator panel | black plastic case, silver screws, eight backlit windows: amber or red glass with navy black legends and the count when lit, dark smoked glass with white legends when clear |
| Picked alert | the latched window | a light ring round the window and a notch pointing to the readout |
| Readout | the annunciator's message screen | dark glass, the window's lamp colour, "2 buildings starved", "Inputs were missing, so they made nothing this turn." |
| Rows | job cards on a gunmetal plate | the missing good's cream tile in a well (72 logical, `GOOD_ICON`), the place and the reason in white, a Go to key |
| Dismiss | a cream key | "It lights again if it gets worse." |
| Dock | the tray's base | navy steel; the pen and the three bells raised (pen cream, bells green, amber, red, dimmed at zero), counts on navy pills, the pen's cell sunk while the tray is up, the pen's lamp lit in the worst lit window's colour (red here: Stockpile small) |

Also considered: a teleprinter tape (reads as a log, which the dock rows already are), a dispatch board with pigeonholes (a grid of slots is the annunciator without the lamps), a sealed envelope on a blotter (heavier than the clipboard and hides the words behind a step), a pneumatic tube capsule (a nice arrival animation, not a layout; decision 6).

**Width: 460 logical px.** The dock is 12 px in; the bottom menu starts about 480 px in, so 460 keeps the tray clear of it. At 460 the letter's body sets at 14 px in lines of about eight words, a choice key and its two lines and one screen sit side by side, and four annunciator windows sit in a row with legends at 13 px. The dock's rows (380 today) take the same width, so pen and bells open one tray. At the capture's 1205 px screen the decision state stands 763 px tall and the alerts state 597, both under the 1061 px between the top bar's line and the dock.

**Ink.** White with a dark shadow on the steel, gunmetal, plastic and glass; navy on the cream letter and keys; navy black on lit windows. Nothing under 12 logical px.

## 6. Numbers first

| Figure | Helper |
|---|---|
| The gate line | `TurnBriefing.unresolved_decisions().size()`, the same count `commit_turn` refuses on |
| A choice's figures | new `DecisionState.choice_figures(def_id, choice_id, target)` → `[{kind: cash, loan, units, turns, seat}, value]`, read from the effects `_execute_effects` applies (`founder_loan.amount`, `.rate`, `freight_credit.units`, `cash.amount`, `construction_delta.turns`), so the screens and the resolve cannot disagree; `_describe_effects` keeps the words |
| Upfront cost, loan shortfall | `DecisionState._upfront_cost`, `loan_needed_for` (already in `pending_view`) |
| Window lit, tone, count | new `TurnBriefing.alert_windows()` → per kind `{tone, count, dismissed}`, from the item builders as they stand (`_starved_item`, `_storage_full_item`, …); the pen's lamp reads the same |
| Starved rows | `Production.missing_by_building`, the good's name from `Catalog.get_display_name` |
| Storage figures | `TransportState.overflow_shipments`, `Production.last_turn_summary` (`input_orders_capped`, `storage_overcommitted`) |
| Bankruptcy | `MatchState.money`, `LoanState.available_capacity()`, `SolvencyState.history` (the top bar's strip reads the same) |
| Cash short | `last_turn_summary.input_orders_short.short_cost` |
| Place names | `Catalog.tile_name`, never `tile_label` or the id |
| Money on screens | `scripts/ds2/money_figure.gd screen()`; counts on `drum_figure.gd` |

## 7. Phases

Behind `UiPrefs.use_briefing_ds2` (cheat `toggle briefing ds2`); with the flag off the briefing and dock are today's exactly, and a test checks that.

| Phase | What | Size |
|---|---|---|
| 0. Measure | the flag; `tools/briefing_tour_shot.tscn` extended to the flag on (every alert kind, two decisions queued, a three choice decision, a locked choice, the tutorial, a small screen); telemetry: opened, how, answered, dismissed, Go to | S |
| 1. Numbers and copy | §6; place names without coordinates, no zero rows, the dead bell hint, dashes and dots, grey text, in today's panel too | S |
| 2. One place per message | one-off events to dock rows only; tile at capacity and the capacity dialog into Storage full; the pen's lamp | M |
| 3. Tray and dock | the tray over the dock, one width with the rows; nameplate, gate readout, dock in DS2 | M |
| 4. Letter and answer | the clipboard, the letter, reply keys, screens and drums; several letters stacked | M |
| 5. Annunciator | windows, the latched window, readout, rows, Dismiss | M |
| 6. Default | the owner's rounds; a standard saved; the flag on | S |

Contracts kept: `TurnBriefing.expand/collapse/items/unresolved_decisions/dismiss`, `commit_blocked_by_decisions`, the pen's `Decisions` cell and `ToastLayer`'s `open_all`, `collapse`, `push_row`, `push_notice`, `push_research`; `DecisionState.resolve(choice, uid)`; the tutorial's decision steps.

## 8. Decisions for the owner

1. **Placement**: the tray over the dock at the bottom left (recommended), or keep it mid screen, or a slide-out on the right.
2. **Width**: 460 logical px for the tray and the dock's rows alike.
3. **One place per message**: one-off events (research, construction done, a decision answered, the bridge loan, news) become dock rows only; the briefing keeps decisions and live alerts.
4. **Concept**: the foreman's clipboard for decisions and the annunciator for alerts (studied), or another from §5's list.
5. **Answer keys**: plain cream keys, one press (studied), or Building Detail's guarded cover on choices that spend cash.
6. **Arrival**: the tray rises by itself when a decision arrives (as today), or the pen rings and the tray waits for a click; a capsule dropping into the tray as its animation?
7. **The capacity dialog**: fold "Tile has reached maximum capacity" into the Storage full window and its rows, retiring the modal.
8. **Annunciator windows**: the eight kinds studied (Starved, Cash short, Bankruptcy, Cables full, Storage full, Stockpile small, Deposit low, Deposit out), dark windows always shown so the panel keeps its shape; or lit windows only.
9. **The pen's lamp**: lit in the worst lit window's colour (amber or red) while any alert is lit, so alerts show with the tray down.
10. **Dismiss**: keep "quiet until it worsens" per kind (today), and the words "It lights again if it gets worse."
11. **Cash and turn** leave the briefing's head (the top bar has both).
12. **Letters stacked**: several decisions as letters on one clip, "1 of 2" on each, the next shown when one is answered.
