# Tile View: how it is used, what it holds, and a DS2 arrangement

Status: REVIEW and PLAN, 24 September 2026. Nothing is built. The owner's decisions are listed in §8.

Read with `docs/ds2-theme.md` (on branch `claude/bdp-v3-visual-diagnostics` until it merges), `docs/bdp-v3-roadmap.md` and `docs/top-bar-ds2-plan.md`: a 52 px bar with no notch gives this panel back about 46 px at its top.

Captures are in `artifacts/ui_ds2_plan/` (`tile_bl`, `tile_power`, `tile_prod`, `tile_stock`, an empty unsurveyed tile, an NPC tile, and the whole screen with the building detail docked beside the panel), made by `tools/ui_plan_shot.tscn` on a fixed 1920 × 1080 viewport at two pixels per logical pixel. `tile_view_arrangement.png` sets today's Buildings tab beside the proposed arrangement.

## 0. The brief

The owner, 24 September 2026: plan the tile view panel the same way. First review its information architecture: how it is used now, the insights, links and actions it offers, and how they could be arranged better. Suggest new actions only if they are critical to the game loop.

This plan suggests **no new player actions**. It moves existing ones, merges duplicates, makes deep links land on the right tab, and corrects the figures that aren't the engine's.

## 1. How it is used

### 1.1 What we can measure

Nothing yet. Telemetry records no tile view opens, tab switches or actions: `TelemetryState.track_interaction` takes a fixed list with no tile-view event, and nothing in the panel or the world map calls it. So this review infers use from the ways in, the tutorial, and the game loop. Phase 0 adds the counters (§7), so the arrangement can be checked against real play after it ships.

### 1.2 The ways in

Every way in ends in `show_tile()`, which **always opens the Buildings tab**; the last tab is not remembered.

| Way in | From | Lands on |
|---|---|---|
| Click a map tile (no camera pan) | the map | Buildings |
| `focus_tile_requested` (camera pans) | search results, briefing rows, bell links, transport panel infrastructure rows, tutorial | Buildings |
| `focus_building_requested` (pans; the building detail opens too) | Building Ledger, briefing, market's buildings for sale, transport panel, the building detail's supply "Go To", the tile view's own intermittency "Go to →", tutorial | Buildings + detail |
| `tile_stockpile_requested` | transport panel's stockpile rows, the top bar's "accumulating" card (which also selects the good), the overflow dialog | Stockpile |

One link lands on the wrong tab: the briefing's "Storage full" items tell the player to act "from the Stockpile tab", and their link opens Buildings.

### 1.3 The jobs it does

In the order a player meets them:

| Job | Where it happens today |
|---|---|
| **Judge a site**: terrain, survey state, deposits, land, infrastructure, who else is there | the banner (photo, chips), the land rail, Buildings (other companies, Infrastructure), Goods (Deposits) |
| **Acquire**: survey, buy land, buy a building, buy the port | Survey in the banner; Buy Land at the foot of the rail; Buy Buildings and the port card's Buy in Buildings |
| **Build**: a building, on a deposit, power, batteries, infrastructure | Build (Construct, locked to the tile) in Buildings; Build on a deposit row in Goods; five power plants and two batteries in Power; the "+" cells in Buildings' Infrastructure |
| **Run the place**: is everything working, what does it earn, is power enough, is the warehouse filling | the four tab plates' figures and lamps; building cards (diagnostics lamp, cost basis); Power's balance and batteries; Goods' outputs and sales; Stockpile's utilisation |
| **Move goods**: surplus, logistics, move or sell stock, expand the warehouse | all in Stockpile |

The tutorial teaches most of these here: it spotlights the land chart, Buy Land, Build (three times), Buy Buildings, the port card, a building card, the cables and reinforced-pipes cells, and the market surplus button (§7 lists the names).

There is no owner logic in the panel: every tab and every action appears on every tile, whether or not you own land there.

## 2. What it holds today

The panel is 655 px wide (796 with the land rail expanded) and 870 tall, from y 114 to the bottom menu. Only the tab body scrolls, in a viewport of about 554 px: the rail, header, banner and tab plates are fixed.

| Zone | Insights | Links | Actions |
|---|---|---|---|
| **Land rail** (75 px; 216 expanded) | land chart: a segment per building (colour by category), construction and upgrade reservations hatched, other owners outlined, the owned bracket, the 100-unit soft cap; "free · owned / buyable" (expanded: built / free / buyable / max, and a high-density warning above 100 built) | a segment opens its building | ‹ Expand / Collapse ›; **Buy Land** (a popup of 10–50 or maximum, priced) |
| **Header** | tile name and coordinates | — | ✕; drag to move |
| **Banner** | 240 × 135 terrain photo; Surveyed, or the survey box; terrain; water; deposits (sizes once surveyed); "BUILT · BUYABLE · MAX" | — | **Survey** |
| **Tab plates** | Buildings count, Power net, Goods £ per turn, Stockpile fill and used / capacity; one lamp each, lit only for warn or problem | open their tab | — |
| **Buildings** | port card; your buildings (grouped cards: building icon, output and quantity, cost basis, diagnostics lamp); construction rows (materials, turns left); other companies' buildings ("Owned by" plates); Infrastructure: six dials (cables, roads, pipework, HVDC, rail, reinforced pipes) of transit against capacity | a card, a child card, a construction row or a built infrastructure cell opens the building detail | **Build**; **Buy Buildings** (Market, filtered to the tile); the port's **Buy**; construction **Cancel**; infrastructure **+**; "Show your buildings only"; expand a group |
| **Power** | production, consumption, net; green power and intermittency (affected buildings); battery storage by chemistry | "Go to →" per affected building; "see more →" (Ledger, filtered); Grid "Go To →" (the power map mode) | battery **Load** / **Unload**; five power plants, each with cost to build, recipe and a build button; "Reduce intermittency": two batteries |
| **Goods** | net value, outputs, sales (£ and units: the only per-tile sales figure in the game); outputs by value; deposits | deposit "Go to building" | deposit **Build** / **Build another** |
| **Stockpile** | stock utilisation last turn (the peak, deliberately); warehouse level and storage; JIT line; the stock chart (up to seven bars, "Other goods" opens a drawer of all); overflow shipments | "Other goods" drawer | **Surplus**: keep / intermediary / port (icon-only); **Manage Logistics** (intermediary games: every building's inputs and outputs); **Expand** the warehouse (an inline card: buy materials or use empire stock); select a good → **Move or Sell** (market, special order or a tile picked on the map; once or recurring); "Sell all X except N left" (applies the moment it is ticked) |

## 3. Findings

1. **Your first building starts halfway down, and the tabs are long.** The header, photo, chips, land line and plates fill the top 285 of 870 px, and on a port tile the port card, the two action buttons and the heading take another 190, so the first of your buildings starts at 475 px. In the 554 px scroll viewport, a busy tile's Buildings tab is about 1,200 px (2.2 screens), Power up to 1,700 (the power-plant catalogue alone is about 875), Goods about 820, Stockpile 560 to 980.
2. **Land is shown three ways in three vocabularies** (the rail's free · owned / buyable, the banner's built | buyable | max, the expanded rail's built | free | buyable | max), and **Buy Land sits at the foot of the rail**, far from the banner's figures. Its popup prices land at £1 a unit, but the charge is whole 10-unit patches at £10, through the advisor modifier, so the two can differ.
3. **Actions have no home.** Survey is in the banner, Buy Land at the bottom-left, Build and Buy Buildings in Buildings, building on a deposit in Goods, power in Power, infrastructure at the foot of Buildings, the port's Buy at its top, and warehouse, surplus and logistics in Stockpile. There are four ways to start a build and four ways to sell or route goods.
4. **Figures that aren't the engine's** (DS2 rule 10):
   - **Goods** sums recipe base output × market price, less the cost solver's cost, over **every building on the tile with a recipe: yours and other companies', whether it ran or not**. 290 of the 472 NPC start buildings have recipes, so their nominal output inflates the Goods figure, its tab plate and its output cards (the capture's "Motor, 99 per turn" is three factories, one an NPC's). The tutorial says this tab shows goods produced "by YOUR BUILDINGS ONLY". It is not the building detail's Net Value Added.
   - **Power** counts recipe base output and draw for buildings that ran (NPC buildings never run), not the engine's cable-capped, modified figures, which the cables dial's tooltip does use. The two can disagree on the same tile. MW is labelled "/turn".
   - **Output on the cards** ignores upgrade levels (the row has no level), so an upgraded building is understated; the building detail shows the right figure.
   - **Storage** appears four ways: the plate and the chart show the current fill against a capacity that includes boosts (517 / 1400 in the capture), the utilisation row shows last turn's peak, and the warehouse line shows the base capacity alone ("L1 · 800 storage"). Across the game there are five different warn/full threshold pairs for storage (this panel twice, the transport panel, the top bar, the stockpile map mode).
   - **The Buildings plate** counts every building on the tile (other companies', infrastructure, woods). Its "problem" and "stalled" variants can never appear: the run record it reads only ever holds `true`.
5. **Two roll-ups disagree with the building detail.** A card's lamp can be green over a detail whose diagnostics fold open onto an amber row. A group card shows the first member's cost and no lamp at all, so a stalled member hides in a group.
6. **Infrastructure is the least visible thing on the panel**, below every building card, and the HVDC cell is always disabled because no HVDC building exists.
7. **The Power tab repeats the Construct panel**: five power plants with cost to build and recipe, about 875 px.
8. **Icon-only choices.** Surplus and Manage Logistics are icon buttons (a deliberate change on 22 September, applied to the building detail and the transport panel too); their names are in tooltips, and the tutorial still quotes the retired dropdown's words ("Sell to global market").
9. **Names.** The title carries coordinates ("Stoneshore Docks - (5, 10)"), and an unnamed tile shows only "(16, 1)". Woods and ruins are listed as other companies' buildings under an invented company name (the building detail treats woods as not NPC).
10. **Deep links land on the wrong tab** (§1.2), and the panel ignores several changes: it doesn't refresh on research unlocks, upgrades, retrofits, pauses, demolitions, output-destination changes or power-priority changes. Every refresh rebuilds the tab, so an expanded group card closes whenever money or stock changes.
11. **No owner logic.** Warehouse expansion, surplus and logistics controls show on tiles you don't own, and warehouse expansion works there.
12. **The photo is decoration** at 240 × 135, the largest single thing in the fixed part.
13. **Grey on navy** remains in counts, land-stat labels, empty states and captions (`TEXT_DIM` / `TEXT_MUTED`), against `CLAUDE.md`.

Also seen: in a seeded state with more buildings than the tile's land, the rail's chart overflows its frame and covers the Expand key. Real play may not reach it, but the new land strip should cope with built > owned.

## 4. The arrangement

### 4.1 Principles

1. **The fixed part says what the place is and whether you can use it; the keys say whether anything is wrong; the body says what exactly.**
2. **One home per action, beside the figure it changes.** Buy Land by the land figures, Survey by the deposits, Expand by the warehouse's fill.
3. **Yours before theirs.** The owner's July split (Your Buildings, then NPC Buildings, never mixed) stays.
4. **A link lands where it points.** Every way in says which tab it wants.
5. **Show only what informs** (DS2 rule 9), and **only the engine's figures** (rule 10).

### 4.2 Layout

`artifacts/ui_ds2_plan/tile_view_arrangement.png` (a wireframe; its figures are illustrative).

- **Header (fixed).** The name in raised letters (coordinates in the hover); Close and Location keys, as the building detail's. One status line with a lamp: owner, terrain, survey state, deposits, seaport.
- **Land strip (fixed).** One horizontal bar in the one vocabulary `TileViewData.land_totals` already uses (built, free, buyable, other owners', of the maximum); segments still open their building, names on hover. **Buy Land** beside it, priced as charged; **Survey** beside it while the tile is unsurveyed. The rail and its Expand key go, and the panel keeps one width.
- **Summary keys (fixed).** Five option keys, each a lamp, a label and an LED figure, the open one latched down: **Buildings** (yours; stalled or problems when any), **Power** (net MW), **Goods** (net value added), **Stock** (fill), **Transport** (the infrastructure dials, moved up from the foot of Buildings: how many links are near capacity).
- **Body (scrolls under the seam).** Each tab in one order: its actions, then yours, then others'.

### 4.3 Each tab, today → proposed

| Tab | Today | Proposed |
|---|---|---|
| **Buildings** | port card first; Build, Buy Buildings; your cards; construction; other companies' cards; infrastructure | **Build**, **Buy buildings**; your buildings (lamp, output at its real level, cost against market), a group showing its worst member's lamp; under construction with Cancel; other companies' buildings folded to one line ("6 NPC buildings · the port and 5 more"), the port first inside with its Buy; woods and ruins as land features, not companies |
| **Power** | balance; intermittency; batteries; grid Go To; five-plant catalogue; batteries to build | balance on LED screens in MW, from the engine's per-tile figures; intermittency with its Go to links; batteries with Load and Unload; grid and Go To; one **Build power** key into Construct, locked to the tile and filtered to power; "Reduce intermittency" while the grid has intermittent supply |
| **Goods** | net value, outputs, sales; outputs by value; deposits | net value added (the building detail's figure, your buildings only); sales; outputs by value at this turn's output; deposits with their build key |
| **Stock** | surplus; manage logistics; utilisation; warehouse and Expand; JIT; chart and drawer; move or sell; overflow | fill against one capacity (the warehouse line says what makes it up, e.g. "800 + 600 port"), **Expand** beside it; utilisation named as last turn's peak; the goods, and select one to **Move or Sell** on a sliding sheet; **Surplus** and **Logistics**; overflow |
| **Transport** | (Buildings' Infrastructure section) | each infrastructure type: level, flow against capacity with a lamp, and its **+**; HVDC hidden until it exists; the same research gating |

### 4.4 What changes for the player

Nothing is taken away except duplicates: the power catalogue (it stays in Construct), the second and third land readouts, the coordinates in the title, and (if the owner agrees, §8) the "your buildings only" checkbox, which folding makes redundant. Every action keeps a place in a tab or moves into the fixed part beside its figure. The links that land on the wrong tab land on the right one.

## 5. DS2 treatment

The building detail v3 shell and kit, reused:

| Element | DS2 part |
|---|---|
| Frame | the backing plate and welded brass trim (`BdpV3Nine`), the raised title (`BdpV3Title`), Close and Location keys (`BdpV3Key`), the seam over the scrolling body (`BdpV3Seam`), the steel scrollbar, the lamp overlay with text give-back |
| Status line | a pilot lamp and metal labels |
| Land strip | a new **level bar on a display window** (the BDP roadmap's display window, Phase 1) with painted segments; Buy Land and Survey as wide keys (`BdpV3ModKey`, not openable) |
| Summary keys | the roadmap's **option key**, with an LED figure (`BdpV3Led`) and a lamp (`BdpV3Lamp`) on each |
| Building rows | raised building icon, the output good set in a well with its pill inside (`_v3_set_in_well`), a lamp, cost against market in white print; the fold for other companies is a wide key that opens its list |
| Power balance | LED screens in the money column's pattern (one width, one digit count) |
| Stock | fill as a level bar; goods in a bay (the shipments' bay pattern) with drum counts; Move or Sell as a sliding sheet |
| Surplus, logistics | option keys with the routes' raised icons, icon-only as decided on 22 September, the chosen one latched with its lamp lit; the name in the hover readout |
| Transport | raised infrastructure icons over lamps (the diagnostics' indicator), the level on a small drum |
| Confirmations (port buy, land amounts, warehouse expansion) | sheets, and the guarded button where money is spent |

## 6. Numbers first

Before any restyle, as `ds2-theme.md` §11 step 3 requires:

- **Goods**: net value added = Σ `BuildingEconomics.per_turn(b)` over the player's buildings on the tile; outputs from `BuildingReadout.flow(b, r, this_turn)`. Other companies' buildings out.
- **Power**: the engine's per-tile figures (`Power.tile_produced`, `Power.tile_drawn`, which the cables dial already reads), in MW.
- **Cards**: output from the live building, so levels apply; the lamp and a group's lamp from the same roll-up the building detail's diagnostics use, so the two agree.
- **Buildings plate**: your buildings, with stalled and problem counts from a run state that can say no.
- **Storage**: one capacity (`Stockpile.get_capacity`, boosts included) wherever capacity is shown, and one warn/full pair shared with the transport panel, the top bar and the stockpile map mode.
- **Land**: Buy Land's popup shows what the purchase will charge.

`BuildingEconomics` and `flow(..., this_turn)` exist only on the DS2 branch (commits 12b510d6 and 73a89d44), so this step lands after that branch merges, or with those two commits brought over. The corrections change what today's panel shows too, so they can ship before any restyle.

## 7. Phases

Behind `UiPrefs.use_tvp_ds2` (cheat `toggle tvp ds2`); with the flag off the panel is today's exactly, and a test checks that.

| Phase | What | Size |
|---|---|---|
| **0. Measure** | telemetry counters (tile view opened, tab opened, each action pressed); the flag and cheat; `tools/tile_view_ds2_shot.tscn` on a fixed viewport, with views for a busy player tile (each tab), empty unsurveyed land, an NPC tile, the port tile, construction, a full warehouse, and an intermediary game's Manage Logistics; its first standard | S |
| **1. Numbers and links** | §6; a tab argument on the way in (`show_tile(tile, tab)`, the `open_for_tile(tile, tab)` the v3 top-bar spec asked for) so every link lands on its tab; the missing refresh signals; open groups kept open across refreshes (the building detail's open-state dictionary) | S |
| **2. Shell** | frame, title, keys, seam, scrollbar, lamp overlay | M (kit) |
| **3. Fixed part** | status line, land strip, the five summary keys | M |
| **4. Bodies** | Buildings, then Stock, Power, Goods, Transport, one change each | L |
| **5. Sheets** | Move or Sell, land amounts, port buy, warehouse expansion, logistics | M |

Each closes with the ladder in `ds2-theme.md` §9 and keeps these contracts:

- **Tutorial spotlight names** (`scripts/tutorial/tutorial_steps.gd`): `TileInfoPanel`, `TileLandChart` (the land strip inherits it), `BLBuyLandButton`, `BLBuildButton`, `BLBuyBuildingsButton`, `PortBuildingCard`, `BuildingCard_<building>_<recipe>`, `InfraCell_<key>` (cables, reinforced pipes: they move to the Transport tab, so the steps that point at them open it first) and `SellSurplusToggle`. The coach scrolls a target into view only through a `ScrollContainer` ancestor.
- **Names tests and tools use**: `PlayerBuildingsOnlyCheckbox` (`test_ui.gd`), `OtherGoodsBar`, `StockpileAllGoods`, `StoredGood_<good>` (`stockpile_guidance_check.gd`).
- **Members others reach into**: `show_tile`, `select_stock_good` (the top bar's card), `on_destination_picked`, `_select_tab` and `_active_tab` (the world map, the tutorial), `_current_tile_id` (the grid overlay, the top bar, tutorial detectors), the group `tile_view_panel`.
- **Signals**: `building_clicked`, `survey_requested`, `pick_destination_requested`.
- **The building detail's docking** beside the panel at the same height, found by the sibling name `TileInfoPanel`.
- **Stale tools** to fix or retire on the way: `middleman_p2_preview.gd --tile-ledger`, `surplus_toggle_shot.gd`, `sell_freeze_probe.gd`.

## 8. Decisions for the owner

1. **Tabs**: five summary keys over a scrolling body (recommended), or one long scrolling panel of framed sections like the building detail.
2. **Transport** as a fifth key (recommended), or infrastructure stays at the foot of Buildings.
3. **The photo**: drop it (recommended), keep it as a thumbnail in the status line, or keep it as is.
4. **Power catalogue**: one Build power key into Construct, locked to the tile and filtered to power (recommended; Construct's `open_for_tile` needs a filter argument), or keep it in the tab.
5. **Other companies' buildings folded** to one line by default (recommended). You asked for the "Show your buildings only" checkbox in July; folding makes it redundant. Keep it or retire it.
6. **Goods and power figures**: yours only, at this turn's output (recommended; it can ship ahead of the restyle), or keep counting everyone's.
7. **Which tab opens**: Buildings for a new tile and the linked tab for a deep link (recommended), or the last tab used.
8. **Tiles you don't own**: hide warehouse, surplus and logistics controls until you own land there (recommended), or keep them everywhere, as today.
9. **Coordinates**: hover only (recommended) or in the title.
