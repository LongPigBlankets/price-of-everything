# Building Ledger: DS2

Status: first pass BUILT behind `toggle ledger ds2` (26 September 2026), branch `building-ledger-ds2`. With the switch off the ledger is exactly as it was (a test switches it on and off and checks both). Read with `docs/ds2-theme.md` (the method, §11 and §13; the kit, §5 and §14).

## What the ledger is for

The one place to see every building you own at once, compare them, find the ones in trouble, and jump to one (a row opens its Building Detail). It is opened from the bottom menu's Buildings button (L). It holds, for each building: what it is and where, what it makes, its routes in and out, its power, whether it ran, what a unit costs to make, what it nets a turn, its land, and a way to raise its level. Above the table: the count, a search, the routing objective, eleven filters, and sorting by column.

## The inventory, v2 to DS2

| v2 element | DS2 part |
|---|---|
| Brown pipe frame, navy panel | Building Detail's navy steel backing in its brass trim (`panel_backing`) |
| Small icon and "BUILDINGS" label, X button | the raised title (`BdpV3Title`), Building Detail's Close key (`BdpV3Key`) |
| "8 buildings" caption | a framed dot-matrix display: "9 BUILDINGS", or "4/9 SHOWN" while filters hide some |
| Search box | the search on a mini screen's dark glass, white print |
| Routing dropdown | moved to the Shipments and Stockpiles panel |
| Eleven flat chips in two rows | eleven latching keys on the tile view's key bed: what a building is doing, then what kind it is; copy without hyphens ("Loss making", "Intermittent green") |
| Column captions, ▲▼ glyphs | metal labels; the sorted one cream with a drawn mark (no glyph a font may lack) |
| Metallic row plates | Building Detail's raised modules in one plastic case, on the steel rail |
| Embossed building icon | the building's emblem in polished metal |
| Name, then a Tile column of coordinates | the name over its tile's name (coordinates in words where a tile has none), so the Tile column is gone |
| Framed good icon with a pill | the good in its well, the quantity on the pill |
| Power text in colour ("360 (self)") | a lamp (green your supply, amber the grid, red no cable) and "360 MW" over "Your supply" / "Grid" / "No cable" / "Makes" |
| Status text in colour | a lamp and the word (green Running, amber Idle, red Starved) |
| Cost/u, Net/t as coloured text | a printed £ and an LED screen each, one width down the table, in the same colours |
| Numbered upgrade button | a cream Upgrade key whose hover is Building Detail's Upgrade card (the dot card); spent at the top level ("Max") and for infrastructure |
| "—" for nothing | blank (no dashes in DS2 copy) |

Every figure is the row model the v2 ledger already computes (`_row_vm`: CostSolver's unit cost, the market price, Production's run and missing records, BuildingStatus's power supply); DS2 changes none of them.

## Built (first pass)

`scripts/ledger_v3/ledger_v3.gd` builds the look from the kit (`scripts/tvp_v3/buildings_parts.gd` modules, case, captions, money, wells and emblems; `scripts/ds2/` dot matrix, latching keys, cream key, dot card; the BDP v3 backing, title, key, seam, lamp, LED and rail). `building_ledger_panel.gd` keeps the data, filters, sort and refresh, builds either look (`_build_look`) and rebuilds when the switch flips. Captures: `tools/ledger_ds2_shot.tscn` (v2, DS2, DS2 filtered and sorted), into `$LEDGER_SHOT_DIR`. Test: `_test_building_ledger_ds2`.

**Card height.** Each row is a DS2 building card, one height with the tile view's (`scripts/ds2/metrics.gd` CARD_H: a 72 px good in its well and 8 px above and below), its emblem and well the Buildings tab's.

**The owner's first review (26 September), built.** The routing objective moved to the Shipments and Stockpiles panel (its header, beside Logistics Settings, in every game), so the ledger's strip is the count and the search. Inputs and Outputs became Source and Destination: the places grouped by kind (the grid, the intermediary, stockpiles, the port, a producing building), one kind a full-height icon, two or three smaller with how many of each, never more than three kinds (the hover lists every place). The Upgrade key says "Upgrade to Lvl 2" ("Max level" at the top), and its card says what the level brings (each output a turn, now and then; a unit's cost, now and then) and what it takes. Power plants show their MW alone. The upgrade panel is DS2 (`scripts/ledger_v3/upgrade_dialog_ds2.gd`, the v2 dialog's own logic): the emblem, raised title and level on a dot display; Materials in wells with have/need lamps and the rest's price on an LED; Per turn as a table (now, the next level, the change); a unit's cost on LED screens; blockers on red lamps; the time and the keys.

**The owner's second review (26 September), built.** The upgrade panel's Per turn is a row a thing led by its icon (a good in its well for each output and input, the raised power, labour and upkeep icons, the land hex), the figure at this level and the next in 20 px print, the change, and a bar on one linear scale across every level (lit to now, the next step green where it helps and red where it costs, a tick at each level). Research still needed is the research icon, a red lamp, its name and a View Research key; land is the land hex, a lamp and "Need X. Only Y available. Buy more or demolish other buildings to make room." (green, with what is free, when it fits); then the clock and the time. One Upgrade key and Cancel, beside the materials dial: Order from market (the port, first), Use materials on tile (a hex with the warehouse), Move materials from other tiles (two hexes), each lit only where it can be done (`assets/icons/ui_icons/ds2/`).

**Third review (26 September), built.** The icons that aren't goods (the bolt, labour, upkeep, the land hex, all in the good tiles' cream) stand in a cream outline a good's size, so every Per turn row is a good's height. Its bars are the tile view's metering screens, and this level is the same grey length in every row with the next step running on from it on one scale, so the rows that grow most run furthest. Per turn sits on the black plastic case. Materials are three to a row with the Source dial and the market price on the right.

**Fourth review (26 September), built.** Per turn's change reads on a dot-matrix screen in the row's tone, under the heading Change over the bars. Materials is a steel plate the rim's own steel (section style "plate", print navy), with a lattice crane on its edges (mast down the right edge from a yellow machinery box, jib along the right half of the top with a slanted tip, the yellow cab under it, crossbars and diagonals), the Source dial under it at 1.5 times its size. The plate is one piece of steel, edge and face, its grain calmed.

**Fifth review (26 September), built.** The Source dial's options are start_upgrade modes: This tile's stockpile (`tile_wait`: starts with what is missing and waits for it), Order from market (`market`, the first choice), All tile stockpiles (`stockpiles`: `BuildingWorks.upgrade_stockpile_plan` pulls every other tile's spare stock, nearest first, and waits for the rest). The two stockpile modes mark the pending upgrade `no_market`, so a stalled wait never re-orders from market, and the plate says "Missing materials will not be bought from market." while one is chosen. The price follows the dial (the market's goods and freight, the stockpiles' freight, £0 when all is on the tile: a building's upgrade has no fee) with its breakdown on a steel plate on hover. The crane is braced with a cross in every bay, its jib's tip slants down, its cab is up top. Per turn's inputs light red (they cost), and every row is a good's well tall.

**Sixth review (26 September), built.** The panel is 840 × 918 (it was 1459 tall and ran off a 1080 screen). Per turn became Estimated impact, a plastic case with no heading: Estimated Cost Increase, Estimated Cost per Unit and Estimated Value of Output, each 54 px, this level and the next on LED screens; See more opens the Per turn rows under them (outputs in one row, a cut, inputs in one row under the inputs icon, 54 px icons), and the case keeps its closed height and scrolls on a rail kept at its side. The price stands between the materials and the dial; the dial moved 30 px right.

**Seventh review (26 September), built.** 780 × 895: a fourth estimate, Estimated Net Value Add (the output's value less the costs); the price's foot level with the lowest materials' frames; Source 10 px under the knob; Upgrade and Cancel on the time line.

**The DS2 upgrade panel is the default** (`UiPrefs.use_upgrade_ds2`, `toggle upgrade ds2` switches back to the v2 dialog): Building Detail's Upgrade key and the ledger both open it; only infrastructure's cash upgrade keeps Building Detail's sheet. Its Upgrade key starts the upgrade the dial's way (test `_test_upgrade_ds2_commits`).

## Open decisions (owner)

1. **Default.** Keep behind the switch until approved, then make it the default with `toggle ledger ds2` switching back, as the top bar and tile view did?
2. **Filters' room.** The key bed takes two rows of keys (about 130 px) above the table. Keep all eleven always in view, or fold the kind row (Production, Power, Infrastructure, the two greens) behind a key?
3. **The house light.** Building Detail darkens its panel's far corner with its light overlay and gives the text back its brightness. The ledger is far wider; leave the light off (as now), or add it?
4. **Rows for infrastructure.** Roads, cables and pipes show as rows with no figures and a spent Upgrade key. Keep them, or leave them to the Transport tab and the Infrastructure filter only?
5. **Routes columns.** Inputs and Outputs keep the v2 route icons (flat buttons that open the building's logistics). Raise them as Building Detail's icons are, or keep them flat?
6. **Money width.** Cost and Net screens share one width, set by the widest figure shown. Fine, or a fixed width so the table never shifts when a filter changes?

## Next

After the owner's first look: the decisions above, a standard (`artifacts/ledger_ds2_standard/`), hover readouts on the lamps (Building Detail's diagnostics' words), and the width check (`_body` minimum within the scroll's width less its rail) as a test.
