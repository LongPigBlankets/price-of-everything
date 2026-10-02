# Resources panel: how it is used, what it holds, and a DS2 arrangement

Status: first build, 2 October 2026, behind `toggle resources ds2` (off by default): the shell, the table and a good's costs opened under its row (§9). The owner's answers to §8 are recorded there. One concept study is rendered (§5). Read with `docs/ds2-theme.md` (the look, the kit, the method in §13 and §14), `docs/ds2-owner-decisions.md` (settled rulings, including the Digital displays money rule) and `docs/building-ledger-ds2-plan.md` (the sibling this panel borrows from). The tile view's plan is the model for this one.

## 0. The brief

The owner, 26 September 2026: "Resources needs an inventory / audit kind of look, though here it could also be a generic DS2 look as well, similar to the building ledger, since they have similar functions."

This plan suggests **no new player actions**. It keeps the panel's one action (open a good's detail), moves the freight table the detail holds today, and adds figures the engine already keeps but no panel shows.

## 1. How it is used

### 1.1 The ways in

| Way in | From | Lands on |
|---|---|---|
| Bottom menu Resources, or R | `bottom_menu.gd` `_on_resources_pressed` | the table, top, every row closed |
| Tutorial | `coach_overlay.gd` lists `ResourcePanel` as a panel it can point at | the same |

Nothing else opens it: no bell, briefing row, tile view or market link lands here. The panel links out once, to the Goods Graph (header key, or G).

### 1.2 The jobs it does

| Job | Where today |
|---|---|
| What do I hold, empire wide | Stock column |
| What does a unit cost me to make | Cost/unit column |
| Is it being made and used | Produced and Consumed (last turn) |
| What will the carbon levy take | Carbon tax column (per unit, today's phase) |
| What does it cost to move | a row's hidden detail: freight per tile per mode and level, the port charge |

Telemetry records no opens or row clicks, so use is inferred (Phase 0 adds the counters).

## 2. What it holds today

`scripts/resource_panel.gd`, 924 logical px wide, 600 tall, one table paged top to bottom: a 90 px good chip, then five figures. Captures: `artifacts/resources_ds2/before/`.

| Column | Meaning | Source |
|---|---|---|
| Good | the good's chip and name | `MatchState.visible_goods()`, built once in `_ready` |
| Stock | units in every tile's stockpile | `Stockpile.get_total(gid)`: sums every tile key |
| Cost/unit | what a unit of it cost you to make last turn, "--" if you made none | `CostSolver.get_good_unit_cost(gid)`: the quantity weighted average of `output_costs` over your buildings that made it |
| Produced | units made last turn, "—" when none | `Production.last_turn_summary.produced`, your buildings only |
| Consumed | units used last turn, "—" when none | `Production.last_turn_summary.consumed`, your buildings only |
| Carbon tax | £ a unit pays when burned, "—" when untaxed or before the levy | the panel's own `_carbon_per_unit`: `co2_tax_multiplier × CO2_TAX_RATE × co2_tax_scale(turn)` |
| Detail (click a row) | freight £ per unit per tile by mode and level; the port charge per unit and its rate | `TransportService.freight_per_tile`, `port_ad_valorem_per_unit` |

It refreshes on `Stockpile.stockpile_changed`, `CostSolver.costs_updated` and `turn_advanced`. The header strip drags the panel.

## 3. Findings

1. **Mostly empty.** Every visible good gets a row whether or not you have ever touched it. At turn 5 the captures page through thirty or so rows at about 4.5 a screen; most read "0", "--", "—", "—", "—".
2. **Dashes for nothing, two kinds.** "--" means no cost, "—" means zero. DS2 copy has no dashes (the ledger went to blank).
3. **A figure not from the engine** (DS2 rule 10): the carbon column re-derives the levy inline. `PolicyState.carbon_charge(gid, 1, turn)` is the helper the turn's cash moves by, with the same formula today; the panel should call it.
4. **Stock is not all you own.** Goods staged by the Logistics Intermediary (`Middleman` feed and bridge) and goods in transit are not in `Stockpile`, so a player on the intermediary sees less than they hold. There is no per good in transit helper; `TransportState.get_pending_transport_shipments()` holds the data.
5. **Cost/unit is only for goods you made.** Bought goods and stock from earlier turns read "--". Nothing on the panel says what the good is worth, so a cost has nothing to be judged against (the ledger and tile view both set unit cost against market).
6. **Power in a goods table.** Power's row counts MW made and drawn in a units column, and its stock is always 0.
7. **The freight table is hidden** behind a row click with only a tooltip to say so, in three decimal pounds, with dashes in its copy.
8. **The list is built once, at load.** A good that becomes visible later (recycling unlocked) never gets a row until the game is reloaded.
9. **The last column is clipped** by the scrollbar in the captures.

**What a player cannot learn here:** where a good is held (which tiles); what made it and what used it (which buildings); what was bought and sold (`summary.purchased`, `summary.sold`, both kept per good); whether stock covers its use or a building went short of it (`summary.starved[].missing`); what the stock is worth; what storing it costs (`EconomyConfig.warehousing_cost_per_unit`).

## 4. The arrangement

**Principles.** The ledger's shape, so the two read as one family: a fixed head (title, count, search, filters), headings that sort, then a good a row. Show only what informs: goods you hold or use, by default. One width with a row open or closed: the detail opens inline, under its row, never as a wider panel. Every figure from the engine's helper.

- **Head (fixed).** Title, Goods Graph and Close keys. The count ("14 IN STOCK") and the search. Filters: In stock (the default), Short, Made, Bought, Sold, Carbon taxed.
- **Headings (sort).** Stock (default, largest first), Good, Status, Made/turn, Used/turn, Cost/unit, Market, Carbon tax.
- **Row.** The good in its well, stock on the pill; its name over where it is held (a tile's name, or "2 tiles"); made and used last turn (blank when none); cost, market and carbon tax a unit on LED screens (a screen only where there is a figure).
- **A row opened: its bin card.** Held at (each tile and its units, the total); Came in last turn (each of your buildings that made it, bought from market, the total); Went out last turn (each building that used it, sold to market, the total); the stock's worth at market, its storage fee a turn, the net change; a Freight rates key opening today's freight table on a sheet.
- **Power** leaves the table (it is shown in the top bar's Power and the tile view's Power tab), or keeps a row with MW in words: owner decision 6.

## 5. DS2 treatment: the ledger's sibling, with a bin card

Four looks were weighed. **An audit clipboard or a stocktake sheet** puts 14 to 40 rows of navy print on one large cream sheet: the brightest thing on screen, and unlike the ledger. **Warehouse bin labels on a steel racking face** read well for a dozen goods but become a grid, not a table: no column to sort by or compare down. **Bin cards** are the right metaphor for the detail: a stores bin card is exactly receipts, issues and balance. **The ledger's DS2 language** already solved the table (rows as modules, sort by metal headings, money columns on LEDs, lamps).

**Recommendation: the ledger's sibling for the panel, the bin card for the opened good.** The table is the ledger's so the player learns one table; the audit look lives in the one place it carries meaning.

| Part | Metaphor | On screen |
|---|---|---|
| Frame | Building Detail's navy steel backing in its brass trim | `panel_backing`, as the ledger |
| Title, keys | raised Bebas lettering; cream keycaps | `BdpV3Title`; `BdpV3Key` Close and a Goods Graph key with the sankey glyph printed navy |
| Count | a framed dot-matrix display | `scripts/ds2/dot_matrix.gd`: "14 IN STOCK", "3/14 SHOWN" while filtered |
| Search | dark glass in the screens' bezel, white print | the ledger's search |
| Filters | latching keys on the black key bed, one row of six | `latch_key.gd`, `tile_keybed` |
| Seam | the ribbed rubber nosing | `BdpV3Seam` |
| Headings | metal labels; the sorted one cream with a drawn mark | the ledger's headings |
| Table | black plastic case with silver screws; a raised module a good | `scripts/ds2/parts.gd` case and modules, `CARD_H` |
| Good | cream tile in a thin gunmetal well, stock on the navy pill | `scripts/ds2/good_well.gd`, 72 px |
| Status | pilot lamp and a word | `BdpV3Lamp`: green Enough, amber Low, red Short, off Held |
| Money | printed £ and a five cell LED; cost red, market white, carbon tax red | `BdpV3Led`, `money_figure.gd` (after the point cell change) |
| Opened good | a bin card: the keycaps' cream plastic slid out from under its module, navy print, ruled like a stores card | a new plate (the `sheetw` plastic), inline under the module |
| Freight | a sheet sliding in from the right | the DS2 sheet pattern |

**The study:** `artifacts/resources_ds2/resources_study_v1.png` (render set `resourcesstudy`, seed 436, a study, not a game layer). 924 logical px wide (1732.5 layout), the whole "In stock" list drawn with the fold at 890 px marked, Coal opened. Figures: stock, Coal's cost and made from the captures; market prices are base prices; Coal's use (30 by Coal Power Plant B), its split between two tiles and the tones of Ethylene and Basic Salt are illustrative.

**Width: 924 logical, today's.** It holds eight columns at the ledger's sizes (72 px wells, five cell LEDs with a clear gap before each £, names to "Port Lightning Old Quarter") with the rail's room kept, and changes nothing about where the panel sits on the map. The bin card opens inside it. 900 was tried and crowded the LED columns.

## 6. Numbers first

Before any restyle, each figure from the helper the turn moves by:

| Figure | Helper |
|---|---|
| Stock, per tile | `Stockpile.get_total`, `get_at_tile`, `tiles_with_stock()`; plus a new `Middleman.staged_units(gid)` and `TransportState.in_transit_units(gid)` if the owner wants them counted (decision 3) |
| Made, used, bought, sold | `Production.last_turn_summary` `produced`, `consumed`, `purchased`, `sold[gid].qty` |
| Made by, used by | a new per building per good record (`_record_building_output` exists for outputs; inputs are kept per tile in `tile_consumed`, not per building) |
| Cost/unit | `CostSolver.get_good_unit_cost` |
| Market | `MarketState.get_sale_price(gid)` (what a sale fetches); the card can add `get_buy_price` |
| Carbon tax | `PolicyState.carbon_charge(gid, 1, TurnManager.current_turn)` |
| Status | a `stock_tone(gid)` helper with the data: red when `summary.starved[].missing` holds the good, amber under three turns of use, green otherwise when used, off when unused |
| Worth, storage fee | stock × sale price; stock × `EconomyConfig.warehousing_cost_per_unit(gid)` |
| Freight | `TransportService.freight_per_tile`, `port_ad_valorem_per_unit` (unchanged) |

Also: rebuild the list when a good becomes visible (finding 8).

## 7. Phases

Behind `UiPrefs.use_resources_ds2` and `toggle resources ds2`; with the flag off the panel is today's exactly, and a test checks that.

| Phase | What | Size |
|---|---|---|
| 0. Measure | flag and cheat; `tools/resource_panel_shot.tscn` extended (empty start, busy mid game, a good opened, filtered, levy in force); telemetry counters (opened, row opened, filter, sort) | S |
| 1. Numbers | §6's helpers; carbon from `PolicyState`; the list rebuilt on unlocks | S |
| 2. Shell | backing, title, keys, count, search, key bed, seam, headings, lamp overlay; one width | M (kit) |
| 3. Table | case, modules, wells, lamps, LED columns, sort, filters | M |
| 4. Bin card | the card plate render, its three columns and foot; the freight sheet | M |
| 5. Default | owner review rounds, a standard, flag on | S |

Contracts kept: the node name `ResourcePanel` (tutorial, `bottom_menu.gd`, `sell_freeze_probe.gd`), `_on_resources_pressed` (`test_smoke.gd`), the Goods Graph link (`MatchState.goods_graph_requested`), dragging by the head.

## 8. Decisions for the owner

1. **Look**: the ledger's sibling with a bin card for an opened good (recommended, the study), or an audit look throughout (stocktake sheet or racking face)?
2. **Width**: 924 logical, today's (recommended), for every state.
3. **Stock counts** goods staged by the intermediary and goods in transit (in the card as their own lines, the pill keeping the stockpile), or the stockpile only, as today?
4. **Default filter**: In stock (hold or used last turn) (recommended), or every good as today?
5. **Status words and the amber rule**: Enough, Low, Short, Held; amber under three turns of use? *Decided (owner, 27 September 2026): no status lamps or words. A player running just in time, or buying over a turn or two and selling straight away, holds little stock by design, so Low or Short would read as a problem when nothing is wrong; the cases are too unclear to judge with one lamp. The column and its lamps come out; the study keeps them only as a record.*
6. **Power**: out of the table (recommended), or a row with MW in words?
7. **Carbon tax column**: a screen for every taxed good from turn 1 (reading 0.00 before the levy, as in the study, so the player sees which goods will be taxed), or the column only once the levy is announced?
8. **Market column**: the sale price (recommended), the buy price, or both on the card?
9. **Freight table**: a Freight rates key on the bin card opening a sheet (the study), or move it to the Encyclopedia's good page? Its figures are three decimal pounds, past the money rule's two.
10. **Made by and used by**: worth a new per building per good record (§6), or the card shows only totals?

## 9. Owner decisions, 2 October 2026, and the first build

**Decided.**

1. **Look**: the ledger's sibling.
2. **Width**: start at 1080 logical and work down from there.
3. **Counts**: produced, used, sold and stored, with in transit beside them. Stored is what sits in the stockpiles that nothing sold or used, and leaves out goods construction has claimed. In transit counts goods on the way to another tile or to a port, never the intermediary's own deliveries.
4. **Default filter**: every good.
5. **Status lamps**: none (27 September).
6. **Power**: no row.
7. **Carbon tax column**: only once the levy is in force.
9. **Freight and transport**: opened under a good when it is selected. It shows what moving it cost, what storing it cost and what the intermediary's fee was, each as a total and a unit.
10. **Made by and used by**: not yet. No per building rows.

Decision 8 (the Market column) was not answered. The build shows the sale price, the plan's recommendation.

**Built.**

- `scripts/goods_figures.gd`: every figure, read from the engine. `rows()`, `costs(good)`, `freight_rates(good)`, `transit_units()`, `reserved_units()`, `carbon_in_force()`.
- `Production.note_good_cost`: the turn now books what it charged on each good in `last_turn_summary.good_costs` (transport, storage, intermediary, each with the units it was paid on). It splits charges the turn already makes and moves no money.
- `scripts/resources_ds2/resources_ds2.gd`: the view. The ledger's backing, title row, count display, search, key bed, seam, sorting headings and case. A good a module; pressing it opens its costs and freight under it.
- `scripts/resource_panel.gd` builds the view while `UiPrefs.use_resources_ds2` is on and keeps the v2 table untouched under it.
- Captures: `PANEL_TOUR=resources PANEL_TOUR_RESOURCES_DS2=1` with `tools/panel_tour_shot.tscn`; the first set is in `artifacts/resources_ds2/ds2_v1/`.

**Open.**

- The width: 1080 holds every column with room to spare before the levy. Narrowing waits for the owner's review.
- Transport on a deferred sale is booked when it is charged, so a good's transport total and its sold count can be a turn apart.
- A purchase's freight counts the units ordered.
- Telemetry counters (Phase 0) are not added.
