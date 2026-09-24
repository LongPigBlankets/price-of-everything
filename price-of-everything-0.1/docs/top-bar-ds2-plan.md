# Top Bar DS2: a thin instrument strip, and one place for what happened

Status: PLAN, 24 September 2026. The updates dock (§4) is partly built: the toasts, research unlocks, notices and decisions are in it, and the notch is gone. The owner's decisions are listed in §10.

Read with:

- `docs/ds2-theme.md`: the DS2 rules, the render → export → Godot pipeline, the component catalogue and the kit plan. It lives on branch `claude/bdp-v3-visual-diagnostics` until that branch merges.
- `docs/bdp-v3-roadmap.md`: how Building Detail v3 was phased, and the shared components it still plans (the option key and the display window are both needed here).
- `docs/top-bar-v3-spec.md`: the bar as built in August (LED dots, the transport module, anomaly popups). The v3.1 icon faces (`UiPrefs.use_topbar_v3_1`, on by default) came after it.

Captures and measurements for this plan are in `artifacts/ui_ds2_plan/`, made by `tools/ui_plan_shot.tscn`, which renders the game in a fixed 1920 × 1080 SubViewport at two pixels per logical pixel, the way the BDP v3 standard is captured.

## 0. The brief

The owner, 24 September 2026: bring the top bar to the Building Detail v3 look and method. Two problems: the bar is a bit too tall on large screens, and its icons are different sizes when you look at the pixels they actually use, especially their height. There is also a lot of text on it. The owner is tempted to move the updates off the bar altogether, into a new place in the bottom-left corner for updates and toasts, or else to move the money to the centre and the updates to the bar's left edge.

## 1. Where the bar is today

### 1.1 Height

| | logical px | share of 1080 | at 2560 × 1440 | at 3840 × 2160 |
|---|---|---|---|---|
| The bar's rect | **83** | 7.7% | 111 | 166 |
| The briefing notch hangs to | **98** | 9.1% | 131 | 196 |

- `BAR_H` is 65 and `MOD_H` 50 (`top_bar.gd:39-40`), but the bar renders at 83: it grows to its tallest module. Each v3.1 icon sits in a holder 8 px taller than the icon (`V31_ICON_BOTTOM_PAD`), so a 44 px icon makes a 56 px module and a 71 px bar. The Goods Graph's sankey was given a 56 px box (`SANKEY_ICON_PX`, a day after the 65/50 budget was set), which makes its module 68 and the bar 4 + 68 + 11 = 83. **One hand-enlarged icon adds 12 px to the whole bar.** The notch (`BAR_H + NOTCH_DROP` = 98) now hangs only 15 px below it.
- The game stretches its whole canvas with the window (`canvas_items`, `expand`, base 1920 × 1080). The bar is always the same share of the screen, so on a large monitor it is physically large: 26 mm tall on a 27-inch 1440p screen against 15 mm on a 15-inch 1080p laptop. That is why it reads too tall on large screens.
- Every panel docked at the top starts below the notch. The tile view's top is at y ≈ 115 (`tile_info_panel_v2.gd` `_apply_anchors`: `offset_top = 78` in HUDContent, whose origin is y ≈ 37).

### 1.2 Icons

Measured by hiding each icon (alpha 0, so the layout doesn't move), capturing, and bounding the pixels that changed: the icon as drawn, its shadow included. `artifacts/ui_ds2_plan/topbar_icon_footprints.png` draws these boxes on the bar.

| Icon | Box | Drawn w × h | Top | Bottom |
|---|---|---|---|---|
| Money (coin stack) | 44 | 44 × 44 | 20 | 64 |
| Power | 44 | 22.5 × 44 | 18 | 62 |
| Victory (trophy) | 44 | 39 × 43 | 19 | 62 |
| Stockpiles (warehouse) | 44 | 44 × 33.5 | 23 | 56.5 |
| Infrastructure (road) | 44 | 44 × 37 | 21.5 | 58.5 |
| In transit (port) | 44 | 43 × 44 | 18 | 62 |
| Council | 44 | 43 × 42.5 | 19.5 | 62 |
| Goods graph (sankey) | 56 | 46.5 × 44.5 | 11 | 55.5 |
| Encyclopedia (book) | 44 | 44 × 34 | 24.5 | 58.5 |
| Menu | 44 | 44 × 30 | 25 | 55 |
| Briefing bells (two) | 52.5 | 45 × 52 | 23 | 75 |

Heights run from 30 to 52 px, tops from 11 to 25, bottoms from 55 to 75. Four causes, each fixable:

1. **Aspect.** Every icon is a `TextureRect` with keep-aspect-centred, so a canvas's longer side fills the box. The power canvas is 420 × 661, so it draws 22 px wide and full height; the menu canvas is 512 × 356, so it draws full width and 30 px high.
2. **Empty canvas.** The art doesn't fill its canvas: the warehouse's art is 76% of its canvas height, the sankey's 79%, the book's 83%.
3. **Three box sizes.** 44 for most, 52.5 for the bells, 56 for the sankey, which was enlarged by hand so its thin strokes "weigh the same" (`SANKEY_ICON_PX`).
4. **Alignment.** Boxes are bottom-aligned in rows of different heights, so neither tops nor bottoms line up.

### 1.3 Text

Six font sizes (11, 12, 13, 15, 16, 20) on one strip: cash at 20 over "−£555 last turn" at 13; "0/1,000" at 15; "Turn 4 / 300" at 16 over "April Year 1" at 12; bell counts at 13; the mission module's two lines at 13 and 11, which run to 354 px across the middle of the bar while the mission is shown in full.

### 1.4 What happened goes to six places

`artifacts/ui_ds2_plan/hud_updates_today.png` marks them on a turn-4 screen:

1. The briefing notch, centre top: a bell for decisions and a bell for updates. "Updates" is everything that isn't a decision, so critical alerts (bankruptcy looming, starved buildings, full storage) share a count with routine news and research.
2. Research-unlock flyouts, sliding down under the notch, up to four and a "+N more". Clicking one opens the Research panel on that technology.
3. The mission module, inside the bar: its text reveal (to about 425 px wide) and its gold-fill completion.
4. Toasts, bottom-left: `toast_manager.gd`'s success stack (x 20, 380 px wide, bottom 140 px above the screen's foot, up to 6, 5 s each, not clickable, not dismissible). Cautions and errors land here too. About 110 call sites raise toasts.
5. Warning toasts, bottom-centre, when triggered (cash in the red, the auto-bridge loan).
6. Anomaly cards under the Treasury (loan, big payment, abnormal spend, transport, and an "upcoming bills" card with a › key into the Money panel), Power, and Transport (a good accumulating on a tile, which opens that tile's stockpile), when triggered.

Plus the bankruptcy strip pinned under the money and the CFO's intro popup at a fixed (20, 72). A player who wants to know what happened this turn has to look in up to six places, three of them on or hanging from the bar.

## 2. What the DS2 bar should achieve

1. **One strip of one height, no notch: 52 logical px** (4.8% of the screen, 69 px on a 1440p monitor, against 111 + the notch today). Every panel docked at the top moves up by the 46 px the notch took.
2. **Icons on one cap height, by their art**, centred on one midline.
3. **One line per module.** A figure sits on a display (DS2 rule 5); words go to the hover readout and the flyout.
4. **Everything that happened in one place**, off the bar (§4).
5. **The DS2 rules** (`ds2-theme.md` §1) hold unchanged: physical objects, one light, white text on dark, raised lettering, numbers on displays, status as lamps, figures from the engine.

## 3. Layout: where the money and the updates go

`artifacts/ui_ds2_plan/topbar_proportions.png` sets today's bar over the proposed strip at the same scale (proportions only; it is not the DS2 render).

| Option | Bar | For | Against |
|---|---|---|---|
| **A. Keep the notch** in the centre | as today, thinner | no relearning | the notch alone sets the bar's depth (98 px); updates stay split over six places |
| **B. Money centre, updates at the bar's left edge** | a bell and count at the far left | one fewer hang; updates in the first place the eye reads | a thin bar has no room for the notch's two rows, so the list still opens elsewhere; whatever hangs from the left edge lands on the Treasury flyout's slot, the bankruptcy strip, the CFO card and the left-slot panels (all at y 72–114); toasts and the mission stay where they are; transient items take the most-read spot from the most important number |
| **C. Updates off the bar, into a dispatch at the bottom-left; money centre** (recommended) | no bell at all | the notch goes, so the bar is one height; the dispatch takes the place toasts already use, so players already look there; all six surfaces merge; the bar's centre is free for the money | a new component; the corner is shared with the map legends and the coach card, so it needs placement rules (§4); decisions need a second home (below); tutorial steps anchored on the bells move |

**Recommendation: C.** Decisions are not lost by leaving the bar. They already block End Turn: pressing it with one outstanding emits `TurnManager.commit_blocked_by_decisions`, which opens the briefing and flashes it; that now opens the dispatch's hub instead. The dispatch lists decisions first, with an amber lamp that turns red while one is blocking the turn. A lamp of the same tone on the End Turn key would tie the two together without adding an action. (The "Decide" beside End Turn today is the turn-phase roller, not a decisions control.)

The strip, left to right, in three groups:

| Group | What | DS2 part |
|---|---|---|
| **The works** (left) | Power, Stockpiles, Infrastructure, In transit | a raised cream icon and a pilot lamp each; the lamp's tone from the rules the LED dots use today (`top-bar-v3-spec.md` §1.3); hover shows a readout, click opens the flyout or panel as now |
| **The till** (centre) | £ and cash; net last turn; a runway lamp when cash and borrowing room would run out within 12 turns at last turn's loss (today's "≈N TURNS") | a printed £, an LED screen for cash (green, red below zero), a second LED screen for the net (green or red, signed); click opens the Treasury flyout (loans) |
| **The office** (right) | Victory score; Rankings (when enabled); Council; Goods graph; Encyclopedia; Turn; Menu | trophy and a drum counter with the target printed after it ("/1,000", live from `win_threshold_for_turn()`, since the bar rises); podium and council icons with lamps (council lamp for disloyalty); Goods graph, Encyclopedia and Menu as small keycaps; the turn on a drum counter with a printed "/300", the date on hover |

The mission leaves the bar for the dispatch (§4), where its text has room and its completion (gold fill, tick) can play without pushing the bar about.

## 4. The dispatch (bottom-left)

A new DS2 component, built on existing patterns.

**First step built (24 September 2026, branch `top-bar-v3-and-updates`).** The owner asked to start with a container for what exists: the toasts, kept, but as rows in a slide-out that collapses after 5 s into a 60 px section in the bottom-left corner with three bells, green, amber and red, in the notch's bell icon. `scripts/toast_manager.gd` is now that container:

- Every toast is a row (the toast's own look). A row opens the slide-out, which rises from behind the dock with the newest rows it hasn't shown (at most 6) and collapses 5 s after the last one. Like the toasts, it takes no clicks, so the map and the Construct panel under it keep theirs.
- The dock (12 px from the corner, 60 px tall) counts each colour's rows since the player last opened it: success and info green, caution amber, warning and error red. A bell with nothing new is dimmed; a new row pulses its bell.
- Clicking the dock opens every kept row (the last 40); that slide-out takes the mouse, scrolls, stays up while hovered (2 s after the mouse leaves), and clears the counts. Clicking again closes it. The dock's rim lights while it is open.
- The bottom-centre warning stack is gone; every toast is in the dock. The map's bottom-left legends now sit on top of the dock (`LEGEND_CLEARANCE`).
- Tests: `_test_updates_dock` (`tests/unit/test_ui.gd`); captures: `tools/updates_dock_shot.tscn`.

**Second step built (same day).** The research unlocks and the notices moved in too:

- Each research unlock is a green row reading "Unlocked: <name>", above every other row (in the order they came), and a link: clicking it opens the Research panel on that technology. The flyouts under the notch are gone. The top bar still decides what to post (once per technology per match).
- The notices (a loan, a big payment, abnormal spending, transport, next turn's bill, power going dark, intermittency, grid draw, stock building up on a tile) are amber rows. Each is keyed by its notice and the turn, so next turn's bill, re-evaluated as orders change, keeps one row, is replaced when its figure changes, and is withdrawn when it no longer holds. Next turn's bill opens the Money panel's Upcoming tab; stock building up opens that tile's stockpile on the good. Their rules (thresholds, cooldowns, at most two money notices a turn, none in the tutorial or before turn 2) are unchanged. The cards under the modules, their scrim and `anomaly_popup.gd` are gone.
- A link row takes its own click, even when the slide-out lets clicks through, and ends in a chevron.

**Third step built (same day).** The decisions moved in and the notch went:

- A fountain pen (`assets/icons/ui_icons/standalone/fountain_pen.png`, baked by `tools/bake_pen_icon.py` in the bell's cream) sits before the bells and counts the decisions waiting in the turn briefing, on a salmon pill. It pulses when one arrives and when End Turn is refused for one. Clicking it opens the Turn Briefing panel on the first decision; clicking again closes it.
- Each bell is a filter: clicking it opens the slide-out on that colour's rows only (green updates, amber notices, red warnings) and clears only its count. Clicking the same bell again closes it; clicking the dock between its icons shows every row.
- The briefing notch and its bells are gone from the top bar. The mission module sits centred where the notch was. Research unlocks still reach the dock through the briefing's research event.
- The auto bridge posts one red row. The top bar's loan notice stands down for it (`SolvencyState.bridging` is set while its loan is taken); the briefing keeps its info item, which only shows when the panel is open.
- Every shown row carries the old toasts' countdown sweep again: a faint white band that shrinks to the left as the slide-out's time runs out, one edge across all the rows (full while the mouse holds it up).
- The tutorial's screen tour labels the dock "Updates and decisions" instead of the notch.
- Tests: `_test_updates_dock_filters_and_decisions` (`test_ui.gd`), the bridge flag in `_test_auto_bridge_loan` (`test_finance.gd`).

Not yet moved into it: the mission. It keeps today's DS look, not DS2.

The full design, as planned:

- **Where.** The toast column's place: x 20, 380 px wide, its foot near the screen's foot. It grows upward, never over the top bar. The bottom menu's plate starts at x 485, so the width budget is W/2 − 475 (about 460 at 1920 wide): the plate fits.
- **Its neighbours.** The corner is not empty. The map-overlay legend (12–252 × 866–1056, while an overlay is on), the stockpile, transfer and buy pick legends (x 12, foot at H − 24), the tutorial coach card's default slot (x 24, foot at H − 161, at least 460 wide) and the left-slot panels (the Construct panel reaches y 994) all use it. The rules: the plate sits at the corner's foot; an active legend stacks on top of the plate; slips rise above both; while a left-slot panel is open, slips wait and the plate stays below the panel; the coach overlay adds the dispatch to its avoid-list and takes its default slot above it.
- **Collapsed.** A small steel plate: three pilot lamps, each with a drum count: Decisions (amber; red while one blocks End Turn), Alerts (red), Updates (off until there are any). One line of the latest item on a display window (the BDP roadmap's display window, Phase 1). Click opens the Turn Briefing hub at the first outstanding item, as the bells do now.
- **Slips.** Every toast, research unlock, mission completion, loan notice and anomaly paragraph becomes a slip that slides up out of the plate, holds for `TOAST_DURATION` (5 s), and slides back in. This is DS2's outcome slide-out (`ds2-theme.md` §7.6) turned upward. Up to six show at once (`MAX_TOASTS`); the rest queue. Red slips for warnings and errors, amber for cautions, cream otherwise. The warning stack at the bottom-centre retires.
- **Links kept.** A slip does what its source did when clicked: a research slip opens the Research panel on that technology, the accumulating-stock slip opens the tile's stockpile with the good selected, the upcoming-bills slip opens the Money panel's Upcoming tab, an alert opens the hub on that alert. A slip that leads somewhere has a small › key; the rest are not clickable, as toasts are today.
- **The mission.** Pinned above the plate as a work order on a white plastic sheet (navy print, `sheetw`), with its progress and its completion animation. Its flyout (the mission tree) opens from the work order.
- **Anomalies.** The module's lamp on the bar lights, and the paragraph arrives as a slip. The lamp is the pointer back to the figure (owner decision, §10).
- **The hub.** The Turn Briefing panel (`turn_briefing_panel.gd`) is unchanged in this plan. Moving it to DS2 is its own step.

## 5. Icons: one rule

1. **One render per icon, at the bar's size.** A new render set, `baricon` (its own seed, after the last used), raises each bar icon from the game's own art (`trimAlpha` or `keyCream`) at the cap height, so every icon has the same relief height, the same swept shadow and the same face grade under the house light.
2. **Fitted by its art, not its frame.** Godot fits each render by its art rect (`BdpV3Indicator.art_rect` / `art_dest`) to a **26 px cap height**, width at most 36 px (a wide icon is limited by width instead), centred on the plate's midline.
3. **Exceptions in one table.** An icon that reads light at the cap (the thin power bolt, the stroke-only sankey) gets an optical factor in one table in the component, with its reason. Nothing else sizes an icon.
4. **Checked by a test.** The shot tool keeps the footprint probe from `tools/ui_plan_shot.gd`: every bar icon's drawn art is the cap height ± 1 px (or its tabled exception) and sits within ± 1 px of the midline band.

**Built on today's bar (24 September, before DS2).** `top_bar.gd` `_v31_icon` fits every icon by its used rect (`BdpV3Indicator.art_rect`, shadow included) to `ICON_CAP` 34 px tall or `ICON_MAX_W` 42 px wide, centred in a box that centres on the module row. `ICON_OPTICAL` holds the exceptions: the power bolt ×1.08 and the sankey ×1.12 (thin strokes, the reason it was once given a 56 px box). The bar is 60 px (`BAR_H`, modules 45); it was 83. Measured with `tools/ui_plan_shot.tscn`: every icon draws 29 to 37 px tall with its midline at y 25 to 27, against 30 to 52 px and tops from 11 to 25 before. With the notch gone and the bar shorter, everything docked under it moved up from y 114 to 72 (the left-slot panels and the tile view at 36 in HUDContent, Building Detail's `TOP_BAR_CLEARANCE`, the coach's `top_safe`), keeping their bottoms, so each gains 42 px of height. Test: `_test_top_bar_icon_fit` (`test_ui.gd`).

At a 26 px cap, the current art comes out as follows (art aspect from the PNGs' alpha): money 26 × 26, power 13 × 26, trophy 24 × 26, podium 26 × 26, warehouse 34 × 26, road 31 × 26, port 25 × 26, council 26 × 26, sankey 27 × 26, book 34 × 26, menu 36 × 25. Power is the one clear candidate for an optical factor.

## 6. Inventory: every element and its DS2 part

| Element today | What it shows | DS2 part | New? |
|---|---|---|---|
| Bar background: navy gradient, 7 px silver bezel | — | **Strip plate**: navy steel cropped from one long render (DS2's "crop, not slice"), wide enough for 32:9; a welded brass trim along its foot, as the BDP backing | new render set `bar` |
| LED dots (unlit grey, lit red / amber / green) | module status | `BdpV3Lamp` at about 0.5 scale | kit |
| Treasury: coin icon, cash, "−£555 last turn", runway | cash, net, runway | printed £ + `BdpV3Led` screens (§3) | kit |
| Power, Stockpiles, Infrastructure, In transit icons | status and counts | raised icon (§5) + lamp; hover readout (`BdpV3Readout`) dropping under the bar | kit + `baricon` |
| Victory: trophy + "0/1,000" | score against the bar | raised trophy + `BdpV3Counter` + printed "/1,000" | kit |
| Rankings (podium, hidden unless on) | rank | raised icon + lamp | `baricon` |
| Council | seated advisers, loyalty | raised icon + lamp (disloyalty) | `baricon` |
| Goods graph, Encyclopedia, Menu | open a view | small keycap (`BdpV3Key`) with the icon printed navy on its face | kit + key faces |
| Turn "Turn 4 / 300", date "April Year 1" | turn, date | `BdpV3Counter` + printed "/300"; date in the hover readout | kit |
| Mission module | current mission, completion | moves to the dispatch (§4) | — |
| Briefing notch, bells, counts | decisions, updates | moves to the dispatch (§4) | new component |
| Research-unlock banners | unlocks | slips in the dispatch | new component |
| Flyouts (`Flyout_<id>`: treasury, power, victory, rankings, council, quest); the transport module opens the logistics panel instead | detail | phase 5: steel sheets that slide down from the bar (DS2's sheet pattern, from the top instead of the right); the quest flyout goes with the mission to the dispatch | pattern |
| Hover glow on icons | hover | the indicator's `hot` state (icon brightens) | kit |

The inventory is re-done against the code before Phase 1 starts (`ds2-theme.md` §11 step 2); the table above is from the captures, the tree dump (`topbar_tree.txt`) and the v3 spec.

## 7. Numbers first

Before a figure moves to a display, it is traced to the helper the engine moves cash by (`ds2-theme.md` §8), and a test pins it:

- **Cash**: `MatchState.money`.
- **Net last turn**: already an engine helper, `Production.cash_change_of(Production.last_turn_summary)`. Keep it, and pin it in a test against the figure the Money panel shows for the same turn.
- **Runway**: today computed inside the bar (`_runway_turns()`: cash plus `LoanState.available_capacity()`, over the last turn's loss, shown at 12 turns or fewer), and the bankruptcy strip computes its own cash-plus-capacity figure. Move both into one solvency helper that the bar, the Treasury flyout and the strip all call.
- **Power, stockpiles, infrastructure, transit lamps**: one status helper per module returning `{tone, name, detail}`, so the hover readout and the lamp can't disagree. Power's tones follow `BuildingReadout.power_checks`, so the bar and the BDP's diagnostics say the same thing about the same grid. (`power_checks` is part of the diagnostics' visual view, uncommitted in the `poe-bdp-v3-lamp` worktree on 24 September.)
- **Victory score**: `VictoryState.get_breakdown()`.

## 8. Phases

Each phase is one branch-sized change with its renders, scripts, tests and captures, behind `UiPrefs.use_topbar_ds2` (cheat `toggle topbar ds2`). With the flag off the bar is v3.1 exactly, and a test switches the flag off and checks that.

| Phase | What | Size | Needs |
|---|---|---|---|
| **0. Groundwork** | The flag and cheat. `tools/topbar_ds2_shot.tscn` on a fixed SubViewport (1920 × 1080, plus 2520 × 1080 and 1920 × 1200 for width), with calm, crisis, every flyout, hover, long numbers (£12,345,678), negative cash, and the dispatch collapsed, busy and overflowing; its first standard. Extract the kit components the bar uses (lamp, LED, counter, key, nine, light, indicator, readout) into `scripts/ds2/`, one at a time, each at 0.0 against the BDP v3 standard (`ds2-theme.md` §10). | M | the DS2 branch merged, or the bar branched from it; the indicator and readout (`bdp_v3_indicator.gd`, `bdp_v3_readout.gd`) are still uncommitted in the `poe-bdp-v3-lamp` worktree and must be committed first |
| **1. The strip** | The `bar` render set; 52 px; the three groups; the contracts in §9 kept. Every place that assumes today's bar moves with it: the flyouts' y (`BAR_H + 8`), the tile view and building detail tops (114), the left-slot panels (114 in `main.tscn`), the coach's `top_safe` (110), the Goods Graph's back button (y 98), the CFO card (20, 72) and the Rankings flyout (x 12). | M | owner: height, trim |
| **2. The icons** | The `baricon` set; the fit rule and its test; lamps from each module's status helper. | M | |
| **3. The readouts** | Cash and net on LED screens; turn and victory on drum counters; the three keys; hover readouts. | M | owner: money format |
| **4. The dispatch** | The plate, slips, mission work order; toasts, research banners, anomalies and the bells re-routed; the notch and the bottom-centre warning stack retired; tutorial anchors moved. | L | owner: option C, anomalies, mission |
| **5. Flyouts** | Each flyout on a sliding steel sheet, content moved to the kit. | L | |

**Phase 0 built (24 September).** `UiPrefs.use_topbar_ds2` (off by default, session only) and its signal `topbar_ds2_changed`; the cheat `toggle topbar ds2`; `tools/topbar_ds2_shot.tscn`, which renders the real HUD at 1920 × 1080, 2520 × 1080 and 1920 × 1200 (two pixels each) and saves, for v3.1 and DS2, the bar calm, in crisis, with long numbers, with Power hovered and with the Treasury flyout open (`$TOPBAR_SHOT_DIR`). The kit components stay where BDP v3 has them (`scripts/bdp_v3_*.gd`) and the bar preloads them by path; moving them into `scripts/ds2/` is left for when a third panel needs them, since each move must hold the BDP v3 comparison at 0.0. The owner's money rule is `scripts/ds2/money_figure.gd`.

**Phase 1 built (24 September), the strip.** Render set `bar` (seed 424, `cluster.html`) → `assets/ui/bdp_v3/bar_strip.png`: the backing's navy steel running off the screen's top and sides, a 14 layout px brass trim along its foot with a weld bead and heat tint above the join, and the shadow on the map painted as one band below (a shadow map 7200 layout px long lost its far end). It is 3840 logical px wide (32:9 at 1080) and 68 tall (the 60 px bar and 8 of shadow); `top_bar.gd` `_ds2_draw_strip` crops it from the middle at two texels a pixel, so it never stretches. Under the flag the bar's stylebox shadow and silver bezel give way to it, the lamp's multiply overlay (`BdpV3Light.shade_material`, a Node2D so the container leaves it alone) is drawn last over the strip, and the bar's labels take half the shade back. The modules regroup: the works (Power, Transport) on the left, the money on the screen's centre line (a gap before it sized each layout, `_ds2_centre_money`), then Victory, Rankings and the office on the right. The mission sits after the works until it moves to the dock. The modules themselves are still the v3.1 faces; phases 2 and 3 replace them. Switched off, the v3.1 order and look come back exactly. Test: `_test_topbar_ds2_strip`.

**Phase 1 revised (24 September), owner's look.** The owner compared the navy steel with brushed dark titanium and a navy lacquered sheet, then chose the standard DS2 weathered steel without the brass. The strip (`bar`) is now the backing's navy steel with a riveted steel beam along its foot (a 16 layout px flange, two staggered rows of rivets with rust blooming round them). A concrete slab (`barconcrete`, seed 425, `bar_concrete.png`) stands behind the money: dark weathered cast concrete with aggregate, bugholes, four form-tie holes with rust runs and chipped edges, its top off the screen and its foot on the beam, drawn by `_ds2_draw_strip` on the money's centre line. The cash is on an LED screen (`BdpV3Led` at 0.75 scale, five cells always, blank ones unlit) in white, with the £ printed before it and the K or M after it (`scripts/ds2/money_figure.gd`); the net line under it is unchanged. The bar's icons keep their cream under the lamp and stand on a dark lift. The mission sits against the concrete's left edge. Then (owner): the concrete became clean light grey between two proud pillars (`barconcrete`); the coin sits on three dark iron pipes rising out of the beam (`barcoinpipes`, seed 426, drawn under the coin); pairs of gleaming silver pipes rising out of the beam and off the screen, clamped together, divide the works from the mission and the concrete from Victory (`barpipes`, seed 427, `_ds2_divider_xs`); the figures on the concrete (net, runway, £, K) take a thin dark outline and a shadow. Then (owner, same day): the beam became an H-beam (two raised flanges, the web recessed and bolted, little rust); the concrete beige grey; the coin's pipes thick and touching, filling the space behind it; the text shadow softer (1 px outline, a blurred shadow); the silver pair became one pipe system (`barpipes` → `bar_pipes_left`, `bar_pipes_right`, `bar_pipes_run`): down at a divider, over the beam, along beneath the bar on hangers and back up at the other divider, the two dividers the same distance either side of the money; and the bar's icons became raised cream enamel with their swept shadow, rendered as Building Detail's are (`baricon`, seed 428, `bar_icon_<name>` + `_shadow`), fitted by the render's own art into the same boxes. Then: the iron pipes and the coin went (the £ and the screen say what the figure is); the silver pipes stand 17 px off the concrete's sides; the mission sits outside the left pair; the figures' shadow sits 1 px off the letters with a light blur; the cash turns red (DS2 DANGER, #E66060) below zero. Then: the mission keeps to its own section, from the works' end to the left pipes (`_ds2_quest_area`, held while its width tweens), its icon first and its text opening to the right, cut with an ellipsis where the section ends (the tooltip has it in full); every StatusLed on the bar carries Building Detail's pilot lamp (`BdpV3Lamp` at 0.72, `_ds2_add_lamp`), lit in the tone of its colour, off when it is off or blinked off, the StatusLed drawing nothing in DS2 so the code that sets it is unchanged. Tried and set aside: the lacquer, a silver pipe along the foot rising in arches between the groups, and titanium.

**Numbers first, Power and Transport (24 September).** `scripts/top_bar_status.gd` (`TopBarStatus`) judges both modules once: `power()` and `transport()` return `{tone, name, detail}` (Transport one each for storage, links and freight; Power with `blink` for intermittency), from the same engine figures and rules the lamps used before, so no lamp changes when it lights. The lamps light from the tone and the DS2 readout shows the name and detail, so the two cannot disagree. Aligning Power with Building Detail's per-building `power_checks` is still open. Test: `_test_top_bar_status`.

**Phase 3 in part (24 September).** Hover readouts: in DS2, hovering Treasury, Power, Transport (the lamp under the pointer), Victory, Rankings, Council, Goods Graph, Encyclopedia or Menu shows Building Detail's readout (`BdpV3Readout`, 360 × 72) under the bar, centred on the module, gone when the pointer leaves or a flyout opens; the modules' tooltips stand down for it. Victory's score is on a drum counter (`BdpV3Counter`, four drums) with the target printed after it ("/1,000", live); the turn stays as text. The Victory lamp now lights green (it had no colour and lit red). The silver pipes are 1 px thinner each and 1 px closer, so the loop ends at y 69, clear of the panels at 72. The e2e harness takes `--topbar-ds2` and passes with it (723). Not built: keycaps (owner question open).

**Phase 5, flyouts (24 September, owner's decisions).** On the DS2 bar: Treasury and Power are steel sheets in the bar's own navy steel (`barsheet`, seed 429, `bar_sheet.png`: Building Detail's action-sheet shape, no trim, nine-sliced behind the content), dropping in under their module. Treasury sets its figures in three dark plates (Building Detail's dark metal plate on its own, `BdpV3Section` style "slab": no steel rim, a thin dark edge and a soft shadow, Building Detail's silver screw set in near each corner; cash on hand and the change last turn; cash in and costs; loans), its key labels centred (`BdpV3ModKey.centred`), the keys below them, and carries the same figures on LED screens (the money column padded to one width, the breakdown on smaller screens) and its actions as keycaps that are real Buttons under their old names (`FlyTakeLoanButton`, `FlyBalanceButton`, `FlyChartsButton`; `Flyout_treasury`, `FlyRowCash`, `FlyRowNet` kept for the tutorial and e2e); "Loan capacity" replaces "Borrowing capacity left". Power is two DS2 slide switches (Grid at the left, your buildings at the right) with a line saying what the setting does, and a keycap for the power balance map. Victory and Council open their full panels on click (the flyouts only repeated them). Rankings is a panel of its own, docked at the left under the bar like the Market panel, closing on Esc, sized to stop above the bottom menu; its tables are the flyout's builders, shared. The mission's flyout moves with the mission to the dock (not built). On v3.1 every flyout is unchanged. The rankings notes were reworded without the middle dot and hyphens (both bars).

Each closes with the ladder in `ds2-theme.md` §9: parse check, the bar's tests (check counts, not only failures), the full suite with a grep for `SCRIPT ERROR`, the captures, the compare against the standard, and the e2e leg: the e2e harness drives the Treasury by node path, so a top-bar change runs e2e even when it looks UI-only.

## 9. Contracts to keep

From `top_bar.gd`'s header and the v2/v3 builds:

- `$MarginContainer/HBoxContainer/MoneyWidget` stays a `Button` at that path: the e2e loan flow presses it, then `FlyTakeLoanButton` in the flyout. Moving the money to the centre reorders children; the path does not change.
- `%EncyclopediaButton` and `%TurnCounter` keep their unique names (world map, tutorial spotlights).
- The `money_panel_tab_requested`, `victory_widget_clicked` and `council_widget_clicked` signals, consumed by `bottom_menu.gd`. (`money_widget_clicked` is declared and connected but never emitted; drop it.)
- The bankruptcy strip under the money and the CFO intro popup.
- The tutorial walks the bar module by module (`scripts/tutorial/tutorial_steps.gd`): `MoneyWidget`, `Flyout_treasury`, `FlyRowCash`, `FlyRowNet`, `FlyTakeLoanButton`, `FlyBalanceButton`, `PowerModule`, `VictoryModule`, `TransportModule`, `RankingsModule`, `CouncilModule`, `GoodsGraphModule`, `EncyclopediaButton`, `MenuModule` and `BriefingModule`. Every DS2 module keeps its node name. `BriefingModule`'s step moves to the dispatch plate in the same change that moves the bells.
- The coach overlay's avoid-list (it keeps coach cards off `TopBar`) gains the dispatch.
- Tests and tools that reach into the bar's privates: `construct_panel_v2_smoke.gd` (`_open_fly`, `_fly_panel`, `_close_fly`), `tutorial_regression_check.gd` (research toasts, anomaly cards, council lamp), `commitments_trial.gd` and `stockpile_guidance_check.gd` (money and stockpile notices), `test_victory.gd` (`_ranking_position_at_risk`). Each is ported in the phase that moves what it touches.
- Telemetry: `money_panel_opened` counts the Treasury flyout.

## 10. Decisions for the owner

1. **Updates**: C, a bottom-left dispatch (recommended); B, the bar's left edge; or A, keep the notch. *Decided: C. Built so far: toasts, research, notices and decisions are in the bottom-left dock and the notch is gone (§4); the mission has not moved.*
2. **Money**: centre (recommended with C) or keep it at the left. *Decided: centre.*
3. **Mission**: to the dispatch as a pinned work order (recommended), or keep it on the bar as an icon that opens its flyout. *Decided: to the dock as a work order.*
4. **Height**: 52 px (recommended). *Decided: about 60 px, keeping two lines for cash and net. Built on today's bar (§5).* Separately, a HUD-size setting (0.85 / 1.0 / 1.15, defaulting by physical screen size) is the thorough fix for large screens. None exists today (Settings offers only the monitor, fullscreen and three window sizes), and it scales every panel and the map with it, so it is a decision of its own.
5. **Status modules**: raised icons with lamps that you click (recommended: lighter, matches today), or square keycaps with icons that latch down while their flyout is open (the BDP roadmap's option key).
6. **Victory**: drum counter and "/1,000" on the bar (recommended), with the gauge in the flyout; or a small gauge on the bar (DS2 rule 5 prefers a gauge for a ratio, but a 26 px gauge won't read).
7. **Money format**: LED digits have no comma. Whole pounds on a seven-digit screen (to £9,999,999), or a comma segment added to the LED render. *Decided: at most five characters on the screen. Two decimals below £1,000 (£999.99); whole pounds from £1,000 (£9999); from £10,000 in thousands with one decimal (£15.6K, up to £999.9K); from there in millions (£1.01M), and so on. The LED's point lights on the digit before it, so it takes no cell; the K or M is printed after the screen, as the £ is printed before it.*
8. **Anomalies**: lamp on the module plus a slip in the dispatch (recommended), or popups under the module as now.
9. **Trim**: brass along the foot, as the BDP backing (recommended), the current silver bezel, or the seam's rubber nosing.
10. **The lamp overlay**: shared with the panels, the bar's right end falls to about 0.71 of the left's light (the screen lamp is at the top-left). Accept it (it is the left-to-right lighting asked for in July), or give the bar a gentler fall-off.
11. **A fix before DS2**: the icon rule (§5, steps 2–4) doesn't need DS2. Fitting today's PNGs by their used rect (`Image.get_used_rect()`) to one cap height, centred on one midline, fixes the uneven icons on the shipping v3.1 bar in a small change, while the DS2 bar is built. Take it now, or wait for DS2. *Decided: now, before DS2. Built (§5).*

## 11. Found while taking the inventory

Small faults in today's bar, for whoever picks it up (none needs the redesign):

- The Victory lamp never has its colour set, so when it lights (more than half the tracks rising) it lights red, the default, where green was meant.
- The Council lamp is built and coloured every refresh, then hidden.
- A module's `warn` state is accepted and ignored.
- Esc doesn't close a flyout (flyouts aren't on `PanelStack`).
- The Treasury, Power, Victory and Council flyouts sit on a `CanvasLayer` without the DS theme, so they draw in the engine's default font, and several flyout rows still use `TEXT_DIM` on navy, against `CLAUDE.md`.
- Tooltips set on labels whose mouse filter is IGNORE (net, victory ratio, the transport cells' "Storage" / "Infrastructure" / "Freight to market", the bell counts) are probably never shown (inferred from Godot's hit-testing, not seen in play).
- The first-intermittency power card's latch isn't saved, so it can fire again after a reload; the anomaly baselines also restart after a reload.
- `tools/topbar_v31_shot.gd` writes to a hard-coded Windows path, and its "classic" capture shows v3.1 now that v3.1 is the default.
