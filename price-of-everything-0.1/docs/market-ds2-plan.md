# Market panel: how it is used, what it holds, and a DS2 arrangement

Status: the default since 29 September 2026 (owner); `toggle market ds2` (`UiPrefs.use_market_ds2`) switches back to today's panel. Built 27 September 2026: the numbers (§6), today's panel's fixes (§9.1) and the DS2 exchange, every tab (§9.2). The owner's decisions are in §8. Before that: planning, 26 September 2026. One concept study is rendered for the owner (§5): `artifacts/market_ds2/market_study_v1.png`, render set `marketstudy` (seed 435) in `tools/button_mockup/cluster.html`, a study and not a game layer.

Read with `docs/ds2-theme.md` (the look, the kit, the method in §13 and §14) and `docs/ds2-owner-decisions.md` (settled rulings, including the new money rule under "Digital displays"). The tile view's plan (`docs/tile-view-ds2-plan.md`) and Construct's (`docs/construct-ds2-plan.md`) are the models for this one. Captures of today's panel, every tab paged top to bottom: `artifacts/market_ds2/before/`.

## 0. The brief

The owner, 26 September 2026: "For markets come up with a commodities exchange themed look." A trading floor: a big quote board of price tiles per good with up and down arrows, ticker tape, a trading pit with its bell and hand signal cards, brass and enamel exchange fittings, order tickets and blotters for sales and transactions. All inside the DS2 rules, and **one width across the panel's tabs**, with no size seesaw.

As with the tile view, this plan first reviews the information architecture and suggests **no new player actions** except where one is missing outright (§8, decisions 11 and 12).

## 1. How it is used

### 1.1 What we can measure

Nothing. Telemetry records no market opens, tab switches or actions (`TelemetryState` has no market event). Phase 0 adds the counters.

### 1.2 The ways in, and the ways out

| Way in | From | Lands on |
|---|---|---|
| Market button (bottom menu) | `bottom_menu.gd` `_on_market_pressed` (toggle) | the last tab shown, Good prices on first open |
| Buy Buildings (tile view) | `MatchState.buildings_market_for_tile_requested` → `open_buildings_for_tile` | Buildings, filtered to the tile (the filter drops when the panel closes) |
| The tutorial | `build_close_buy`, `buy_factory` (spotlight on `MarketPanel`, `lock_panel`) | Buildings, filtered to the window factory's tile |

Every way out closes the panel: Expand (Construct filtered to the good), Purchase and Move (the map's pick flows), a building row (the building detail on its tile).

### 1.3 The jobs it does

| Job | Where today |
|---|---|
| **Read prices**: what a good costs to buy and pays to sell, which way it is heading | Good prices (six screens of rows, seven rows a screen) |
| **Judge my goods**: what I make them for, whether I sell at a profit | Good prices' Cost/unit and Profit/unit, the three filters |
| **Act on a good**: buy, move, build more of it | a row's expansion (Sell, Purchase, Move, Expand, and the price chart) |
| **Buy a going concern** | Buildings (559 lots in the capture) |
| **Chase a contract** | Special Orders (read only here; delivery is from the tile view or the building detail) |
| **Keep standing orders** | Sales (recurring sales, bulk sell), Movements (recurring moves) |
| **Check what happened** | Transactions, Movements' one offs |

## 2. What each tab holds today

The panel is 1220 logical px wide (capped to the screen) and about 884 tall, set by `_centre_and_resize`. The width is there for the ten impact ladder columns that "Show impact columns" adds.

| Tab | Insights | Actions |
|---|---|---|
| **Good prices** | per good: icon, name, price to buy and to sell with the impact free price in brackets, an arrow on both, sold last turn, cost per unit (green, amber, red against the market), profit per unit; optional ten impact ladder columns | search; Goods you produce, Profitable, Unprofitable (toggles); Show impact columns; the name opens Sell, Purchase, Move, Expand and a price chart |
| **Buildings** | count; per lot: building icon, name, tile, output good and quantity, owner, price | search; eight filter chips; the price button buys after a confirm dialog ("Do not show again"); the row opens the building detail |
| **Special Orders** | count; per order: good, Target, Committed, Delivered, Due (T20 (15t)), Premium, Bonus, Producer ("Mine, 5t") | none |
| **Sales** | recurring sales as cards (route, goods) | search and a good filter; Cancel; bulk sell form (good, finished only, keep per tile, make recurring, Sell from all tiles) |
| **Transactions** | recurring (sales, bulk sales, recurring buys) and one offs as a table: Type, From, To, Good, Qty, Started, Ended | none |
| **Movements** | recurring moves as cards; one off moves as a table | search and filter; Cancel |

## 3. Findings

1. **The width serves one toggle.** 1220 px exists for the impact ladder columns, which are per good detail. Every other tab uses a fraction of it (Transactions ends at about 60%).
2. **The sell price is not what a sale pays.** The column shows `MarketState.get_price`; a sale is paid `get_sale_price`, which adds the `market_price` modifier (research, the Chief Markets advisor) and clamps to the buy price. With an uplift in play the board understates every sale.
3. **Figures re-derived in the panel**: the buy price's bracket is `buy / impact multiplier`, while the sell's comes from `get_base_price_now`; the arrow is `_price_direction`, a copy of `_tick_impact`'s regime logic kept in step by a comment; the special order Bonus is spot price times premium times target, while the engine pays the premium on delivered revenue in `SpecialOrderState.settle_delivery`.
4. **Duplicates**: the arrow sits on both price columns; recurring sales are listed in Sales and again in Transactions; the building owner repeats on every row (the list is already sorted by owner); Special Orders shows Target, then Delivered as "0 / Target".
5. **A dead key**: a row's Sell key has no handler (`market_row.gd` connects Purchase, Move and Expand only).
6. **Recurring buys can't be cancelled.** They show read only in Transactions, and nothing in the game removes one (only `PolicyState`'s purge).
7. **Transactions has no money**, its Ended column is the planned arrival turn rather than a record (every row in the capture reads "Ongoing"), and places carry coordinates ("Stoneshore Docks - (5, 10)", or only "(10, 2)").
8. **The buy is copied three times**: the Buildings tab, the tile view's port card and Building Detail each deduct, transfer and toast; the market's copy skips the tutorial's purchase gate. Its confirm dialog's "Do not show again" lasts the session.
9. **Names**: lots mix the new names ("Chlor Alkali Complex B") and the old ("Desalination Plant - Pure Water - C"); `label_for_tile` rather than `BuildingNaming.family_name`.
10. **Profitable and Unprofitable** only know goods sold to market last turn; a good you make and use yourself is neither.
11. **Grey on navy** (`CLAUDE.md`): "No sales", the empty states, the special order headings, the idle filter keys.
12. **Copy**: hyphens, dots and dashes ("Finished goods only (non-raw)", "·", "—"), and abbreviations ("T20 (15t)", "Lvl 1").

## 4. The arrangement

**Principles.** One width for every tab, each a body in one shell swapped in place under a fixed head. Every figure from the engine's helpers (§6). Show only what informs. A good's own detail lives with the good, not in columns every good pays for.

**Head (fixed on every tab).** The title, the bell, Close; five latching tab keys under one dot matrix strip that carries each tab's figure (the tile view's pattern); the ticker; the seam.

**Tabs: six become five.**

| Key | Holds | From |
|---|---|---|
| **Prices** | the quote board: a tile per good (icon, name, buy, sell, one arrow lamp, a lamp where you make it); search and three filters; a tile opens its slip: the price chart, the impact ladder as one meter, "Your buying raises it 0.1%/turn.", your cost and last turn's sales when you make it, and Buy, Sell, Move, Build more | Good prices; the ladder columns fold into the slip |
| **Buildings** | lots grouped under their owner; per lot the building, its tile, its output in a well, the price and the guarded Buy key; search and eight filter keys; the tile filter as a removable tag | Buildings |
| **Special Orders** | an order ticket per order: the good in its well with the target in its pill, delivered against target as a meter, turns left on a drum, the premium, the bonus quoted by the engine, where to deliver from | Special Orders |
| **Recurring** | every standing order in one list (sales, bulk sales, moves, buys), each with Cancel; the bulk sell as a sell ticket | Sales, Movements' recurring, Transactions' recurring |
| **History** | the blotter: every one off buy, sale and move, newest first, one line each, with its value | Transactions' one offs, Movements' one offs |

## 5. DS2 concept: the commodities exchange

The panel is the exchange's floor furniture: the quote board over the pit, the listing board for lots, tickets and a blotter on the desk.

| Part | Metaphor | What it is on screen |
|---|---|---|
| **Frame** | a floor panel in the house navy steel, a welded brass trim (Building Detail's backing) | the backing |
| **Title** | a black enamel nameplate in a brass rim, brass rivets | "MARKET" raised in white Bebas |
| **Bell** | the exchange's opening bell: a brass dome on a black base | beside the title; rings as a turn's prices are set; hover "Prices set for turn 5." (decision 8) |
| **Tab keys** | the cream latching keys of the tile view's cabinet, one dot matrix strip over them | Prices, Buildings, Special Orders, Recurring, History; "▲5 ▼2", "559", "4", "0", "22" |
| **Ticker** | the ticker tape as a long dot matrix board, scrolling | goods on the move and orders falling due: "▲ COPPER INGOTS", "▼ STEEL", "● COAL ORDER DUE TURN 20"; words and marks only, since money stays on LEDs |
| **Quote board** | the big board over the pit: a dark gunmetal board, a tile per good, each tile in a thin brass frame | two columns of tiles |
| **Good on a tile** | the good's cream icon tile in a gunmetal well (138 layout px, 73.6 logical) | the tile's left |
| **Name** | one wide split flap, as the destination field of an old station board | the name in white capitals, the flap's split across the letters |
| **Buy and sell** | the board's price windows | printed £ then a white seven segment LED, five cells, the point in its own cell (0.60, 11.60, 481.3, 1153) |
| **Direction** | a plain trend arrow, no lamp (owner, 27 September) | up while rising, down while falling, nothing while steady; red when it goes against the player's own trade (buying while it rises, selling while it falls), green when with it, off-white when the player is not trading it (`MParts.trend_tone`) |
| **Your goods** | a pilot lamp on the tile | green where you make it for less than the market pays, amber about even, red dearer, none where you don't make it |
| **The good's slip** | the pit's chart recorder and signal desk | under the tile, a dark plate: graph paper behind glass (the sell price over recent turns), the impact ladder as ten LED cells with its rung lit, one line in words, the good's four keys |
| **Listing board** | lots posted by the exchange | under a raised owner heading, each lot an enamel card in a brass holder: the building printed flat on its navy field (blueprint), name and tile in navy, output in its well with the quantity pill |
| **Price of a lot** | as every price | printed £ and a red LED, whole pounds as charged |
| **Buy a lot** | the guarded key (Building Detail's footer key) | amber cap reading BUY under a clear cover: the first click lifts it, the second buys; replaces the confirm dialog |
| **Special orders** | order tickets clipped to the desk | a white plastic ticket per order, printed navy, the premium and bonus on LEDs in a dark strip at its foot |
| **Recurring, History** | the standing order book and the blotter | white plastic sheets ruled in navy; Cancel as a small cream key per line; the bulk sell as a sell ticket ending in the guarded key |
| **Hand signal cards** | the pit's buy and sell signals | set aside in the study: palm in and palm out read alike from above; decision 9 |
| **Scroll, seam** | Building Detail's rail and rubber nosing | as built |

**The study** (`artifacts/market_ds2/market_study_v1.png`; one width, 720 logical px, both tabs to the same fold): (1) Prices, with the Coal tile's green lamp (made for £0.43 against £0.57), Coal and Steel falling, Copper Ingots rising and open on its slip; (2) Buildings for sale, five lots of Arin City Petrochemical Co. from the capture (£863, £824, £584, £255, £1080), the second lot's cover lifted. Figures and goods are the captures'; the chart's turns and the impact rung are illustrative but consistent with the captured bracket (£3.27 before a 0.3% impact).

**Why 720 logical px** (1350 layout). The board's tile needs the 72 px well, a name and two five cell money screens with the arrow lamp: about 318 logical. Two tiles, their gap, the board's and the panel's padding and the scroll rail make 720, which also fits a lot's row (card, price, guarded key) with room for the rail. One column of rows fits in 640 but halves what a screen of the board shows; 720 shows ten goods and a slip at the fold where today shows seven. It sits between Construct (600) and the tile view (800) and is 500 px narrower than today.

## 6. Numbers first

Before the restyle, as `ds2-theme.md` §11 step 3 asks. Built 27 September 2026 (step 1): every figure the market shows comes from one static script, `scripts/market_rules.gd` (`MarketRules`, preloaded by path, pure), which the engine's own sale paths call, the pattern `scripts/construction_rules.gd` set.

### 6.1 What the earlier DS2 moves already had, and what the market reuses

| Helper | What it is | Used here |
|---|---|---|
| `scripts/construction_rules.gd` | the construct flow's rules and quote, called by the build itself | the pattern: one static rules script, the engine calls it, a parity test proves it |
| `BuildingEconomics.per_turn` | a building's turn at the engine's own prices and charges | not directly (it is per building); its stock output line now values at `MarketRules.sale_price`, the price the sell phase pays |
| `MarketState.sale_charges` | a market sale's freight and port charge, commit or quote | the sell quote's charges; gained `sale_charges_with(..., reservations)` so a quote over several tiles counts the port's use tile by tile |
| `Production.stock_sale_charges` | a stockpile sale's leg to port and port charge (the sell phase) | not used by the sell panel: its sales go through `execute_sale`, which charges `sale_charges` (the buyer pays the inland freight on a manual sale) |
| `TransportService.quote_market_buy` | a purchase's goods, freight and port charge | not on the board (owner: raw prices, decision 6); kept for the Buy flow |
| `scripts/ds2/money_figure.gd` | the top bar's five cell money rule | the DS2 board's screens, with the new point cell rule (§9) |
| `TileViewData` | the tile view's per tile summaries | nothing fits: it is per tile, the market is per good |
| `ledger_v3` builders | the ledger's DS2 rows, headings with sort marks, money columns, the case | the DS2 board reuses the shell (dress, title row, seam, sort headings) and `buildings_parts` (modules, wells, money, captions) |
| `CashCommitments` | one turn's cash planning | nothing to show on the market; recurring buys it reads are unchanged |
| `MarketState.history_for`, `impact_thresholds`, `rolling_net_volume` | the price history, the ladder, the window | read through `MarketRules.history` and `impact_ladder` |

### 6.2 `MarketRules`, what each figure is

| Figure | Helper | Engine side |
|---|---|---|
| Sell price | `sale_price(gid)`: `get_sale_price` with the good's context (uplifts, clamped to the buy price) | `execute_sale` and the sell phase (`Production._sell_stockpile_totals`) both pay it. The sell phase paid the bare `get_price` before: the mechanics audit's "two sell paths price the same good differently", fixed |
| Buy price | `buy_price(gid)`: the raw `get_buy_price`, no transport (decision 6) | |
| Before impact | `board_row`'s `buy_before_impact`, `sell_before_impact`: new `MarketState.buy_price_from` / `sale_price_from` at `get_base_price_now` | `get_buy_price` and `get_sale_price` are these at today's price |
| Arrow, rung, rate | new `MarketState.price_trend(gid)` → `{dir, regime, rate, rung, avg, impact}` | `get_estimated_price_in_n_turns` reads it; the old row's copy (`_price_direction`, `_active_rung`) is gone |
| One board row | `board_row(gid)`: buy, sell, sold and bought last turn (`Production.last_turn_summary`), your cost (`CostSolver.get_good_unit_cost`), profit (sell less cost), `cost_tone`, `profit_tone`, the trend | |
| Tones | `cost_tone`: green below the sale price, red above, amber at it. `profit_tone`: green above break even, red below, amber within `BREAK_EVEN_SHARE` (2%) of the sale price, at least a penny | |
| Impact ladder | `impact_ladder(gid)`: each rung's net units a turn (this turn's thresholds) and %/turn, the active rung | |
| History | `history(gid, turns)`: per turn the price, the sale price, your cost then, and the units you sold and bought | new, save safe: `MarketState` writes `sold` and `bought` into the turn's history point as the turn advances (only when non zero; a missing key reads 0), and `sale` where it differs from the price |
| Sell sources | `sell_sources(gid)`: every tile of yours that holds it or makes it, held and made this turn | |
| Bulk sale | `sell_params(gid, tiles, mode, qty)`, `sell_plan(params)` | `MatchState.sell_all_to_market` sells exactly `sell_plan`; its params gained `tiles` (only these) and `per_tile_max` (only X) |
| Sell preview | `sell_quote(gid, tiles, mode, qty)`: per tile units, revenue, freight, port charge, net, turns; totals | a parity test sells and compares units, revenue and the charges paid |
| Transaction value | `transaction_log` entries carry `value` where booked: a sale's revenue (`execute_sale`, the sell phase), a buy's cost of goods (`queue_buy`) | older entries have none and show blank |
| Cancel | `MatchState.remove_recurring_buy`, `remove_recurring_order(sub, entry)`; recurring rows carry their order | `add_recurring_buy` now emits `recurring_orders_changed` |

Still as planned, not yet built: `SpecialOrderState.premium_quote`, `MatchState.buy_building`, `BuildingNaming.family_name` for lots.

## 7. Phases

Behind `UiPrefs.use_market_ds2` (cheat `toggle market ds2`); with the flag off the panel is today's exactly, and a test checks that.

| Phase | What | Size |
|---|---|---|
| **0. Measure** | telemetry (panel opened, tab, action); the flag; `tools/market_ds2_shot.tscn` with a view per tab, empty and busy, an uplift in play, the tile filter, the tutorial's lock; the first standard | S |
| **1. Numbers** | §6, which also corrects today's panel (the sale price, the dead Sell key, names, coordinates, grey text) | M |
| **2. Shell** | backing and trim, nameplate, bell, tab keys and strip, ticker, seam, rail, lamp overlay; the one width | M |
| **3. Prices** | tiles, split flap, arrow lamp, the slip | L |
| **4. Buildings** | owner headings, lot cards, guarded key | M |
| **5. Special Orders, Recurring, History** | tickets, the order book, the blotter, the sell ticket | M |
| **6. Default** | the owner's rounds; the standard saved; the flag on | S |

Contracts kept: `MarketPanel` (tutorial spotlight, `close_market_panel`), `open_buildings_for_tile`, `BuildingsContent`, `MarketGoodDetails`, `MarketActions` and `PriceHistoryChart` (`tests/unit/test_market.gd`, `tools/trailer_launch_capture.gd`), the three `MatchState` request signals.

## 8. Decisions (the owner, 27 September 2026)

1. **Metaphor**: DECIDED, the commodities exchange as studied: the nameplate, the bell, the ticker and the dot matrix key strip.
2. **Width**: DECIDED, **960 logical for every tab** (840 until the owner asked for the Resources panel's spacing, 27 September: 20 between value columns, Sold 56, Impact 64, the name 122) (`MarketDs2.WIDTH`, `market_panel.gd` `DS2_WIDTH`), against 1220 today. A test holds every tab, the open slip and the sell panel to it.
3. **Tabs**: DECIDED, as they are, the five: Prices, Buildings, Special Orders, Recurring, History. Moves stay in the market (Recurring and History).
4. **The board**: DECIDED, **one row per good**, not tiles: modules in the ledger's language with sortable headings. Columns: the good in its well and its name (the trend arrow and a word under it); Buy and Sell (raw; Sell at the sale price); Sold last turn; Your cost and Profit; the current Impact. The row opens its slip, which carries the Sell and Buy keys with Move and Build more (the owner allowed "a Sell key and a Buy key, or open the slip"; the slip keeps the row inside the width).
5. **Your cost and profit**: DECIDED, **no lamps**: LED screens lit green, amber or red. Profit is green above break even, red below it, amber within **2% of the sale price** (at least a penny) either way (`MarketRules.BREAK_EVEN_SHARE`, `profit_tone`). Your cost is green below the sale price, red above it (amber only at the price itself, `cost_tone`). Profit is the sale price less your cost (`board_row`), blank for a good you don't make.
6. **Prices on the board**: DECIDED, **raw**, no transport: `MarketRules.buy_price` and `sale_price`. What a sale pays is the sale price; its charges are the sell panel's.
7. **The impact**: DECIDED, **one column showing the current impact, underlined**, its hover a dot card with the good's impact ladder (`MarketRules.impact_ladder`). The ten columns and their toggle go (in DS2; today's look keeps them).
8. **Bell and ticker**: DECIDED, **kept**. The bell rings as a turn's prices are set and its hover says "Prices set for turn N."; the ticker scrolls the goods on the move (▲ ▼) and orders due within five turns (●), words and marks only.
9. **Hand signal cards**: DECIDED, kept as a decoration **for now**; not built yet (nothing on the keys).
10. **The slip**: DECIDED, opens **inline under its row**. Its chart's hover shows that turn's price with the units you sold and bought that turn (`MarketRules.history`).
11. **The Sell key**: DECIDED, opens the **sell panel**: every tile that holds or makes the good with a tick each and Select all; all from each tile, everything but X, or only X per tile; **one off (default) or recurring**; a live preview from `MarketRules.sell_quote`, per tile and in total; a **guarded Confirm sale key**. One off sells now (`sell_all_to_market`, the queue_sell path); recurring sets up the sale for the chosen tiles (`add_recurring_bulk_sell`, sold each turn in PROCESS). Both looks.
12. **Recurring**: DECIDED, every standing order with **Cancel**, recurring buys included. Both looks (today's in Transactions).
13. **Buying a lot**: DECIDED, a **guarded Buy key per lot**, replacing the confirm dialog in DS2.
14. **Lot grouping**: DECIDED (owner, 27 September 2026, round 2): "Have a Sort by Owner button, but the default should be by name of buildings." The lots sort by the building's name by default, with no headings; a latching **Sort by owner** key over the list (and the Owner heading) groups them, each company's name raised as a heading over its lots, as studied, and the rows then leave the owner out. Pressed again, back to names.
15. **Bulk sell**: DECIDED, in the sell panel: bulk sell is the sell panel for one good. The Sales tab's form is gone from today's look too.

## 9. What is built

### 9.1 Today's panel (both looks)

- The Sell column is `MarketRules.sale_price`; its bracket and the buy's are the engine's impact free prices; the arrow is `MarketState.price_trend`.
- A row's Sell key opens the sell panel (`scripts/market_sell_panel.gd`, laid over the market until Back). The Sales tab lists recurring sales only; its bulk form moved into the sell panel.
- Transactions: a Value column (each row's booked value) and Cancel on every recurring sale, bulk sale and buy.

### 9.2 The exchange (DS2, `toggle market ds2`)

| Part | Where | Reused / new |
|---|---|---|
| Backing, content margin, seam, sort marks, search screen, plastic case, modules, wells, captions | `ledger_v3.gd`, `tvp_v3/buildings_parts.gd` | reused |
| Nameplate (MARKET, black enamel in brass), exchange bell (the arrow lamp's renders `lamp_arrow_up`/`lamp_arrow_down` are retired for the drawn trend arrow) | render set `marketparts`, seed 450: `market_nameplate`, `market_bell`, `lamp_arrow_up`, `lamp_arrow_down`; `scripts/market_ds2/parts.gd` | new |
| Key bed and the strip of figures over five latching keys, the ticker | `market_ds2.gd` (the tile view's key bed pattern, `LatchKey`, `DotMatrix`) | reused parts; ▲ ▼ added to the dot matrix font |
| Money screens under the display rule (the point in its own cell, five cells) | `bdp_v3_led.gd` `point_cell` (off by default, so every other panel is unchanged), `money_figure.gd` `display()` | kit change, opt in |
| Prices: rows, sort, filters, impact card, the slip (chart recorder with its hover readout, impact meter, keys) | `prices_tab.gd`, `slip.gd` | new; dot card reused |
| Sell panel's skin: a sheet of the backing, quantity and one off keys on the key bed, a module a place with a latching Sell key, totals, the guarded key | `sell_skin.gd` | new; guard key reused |
| Buildings: lots with emblem, place, owner, output, a red whole pound price and a guarded Buy key; by name by default, Sort by owner with raised owner headings; the tile tag; Show more (40 at a time) | `lots_tab.gd`; `building_market_panel.gd` `lots()`, `buy_lot()` | new; the v2 tab's data and buy, made static |
| Special Orders (tickets: target on the pill, delivered on an LED meter, turns left on a drum, premium, bonus from `SpecialOrderState.premium_quote`), Recurring (Cancel), History (the blotter with values) | `book_tabs.gd` | new |

The lamp (round 2, owner: "Add lamp overlay to all these panels"): `scripts/ds2/lamp_overlay.gd` lights the exchange, its slip, the sell panel and its sheet, as it now lights the Building Ledger DS2, the DS2 upgrade sheet and the tile view v3 (docs/ds2-theme.md §4.1).

Captures: `tools/market_ds2_shot.tscn` (`MARKET_SHOT_DIR`, `MARKET_SHOT_LOOKS=v2,ds2`): every tab paged, the sell panel in each mode, one off and recurring, the cover lifted, the impact card and the chart hover, both looks. Tests: `tests/unit/test_market_rules.gd`, `test_market_panel.gd`, `test_market_ds2.gd`.

### 9.3 Left

- The owner's rounds on the look; a first standard once approved (Phase 6).
- Hand signal cards (decision 9).
- Telemetry counters (Phase 0); lot names through `BuildingNaming.family_name`; `MatchState.buy_building` shared with the tile view and Building Detail (and the tutorial's purchase gate).
