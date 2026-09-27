# Construct panel: how it is used, what it holds, and a DS2 arrangement

Status: the default since 27 September 2026 (`UiPrefs.use_construct_ds2`; `toggle construct ds2` switches back to today's panel). Built: the shell (the hoarding, the crane and its head, the site's plate, the settings key on the crane, one width of 600), the build order for every recipe (§4.2) and the catalogue (§4.1), reading `ConstructionRules.quote()`. Still today's bodies inside the hoarding: the settings and the infrastructure confirm (phase 5). Earlier: the engine helpers every stage reads (`scripts/construction_rules.gd`, proven against the real build by `tests/construction_rules_parity.tscn`), the construction credit facility removed (owner, 26 September: a stopgap from before the Logistics Intermediary), and the two concept studies (§5); the owner chose the construction lot.

Read with `docs/ds2-theme.md` (the look, the kit, the method in §13 and §14) and `docs/ds2-owner-decisions.md` (settled rulings). The tile view's plan (`docs/tile-view-ds2-plan.md`) is the model for this one.

## 0. The brief

The owner, 26 September 2026: the construct flow has several screens and many scenarios; tackle it after the DS2 top bar, tile view, upgrade panel and ledger. First evaluate the credit option (removed), then build the engine helpers from the identified flows (done), then the look. The owner suggests **either a works office or a construction lot with its crane** as the metaphor, and wants **one width across every stage** instead of the old panel's seesaw (560 px browsing, 448 px confirming, 510 px for some buildings).

## 1. How it is used

### 1.1 The ways in

| Way in | State passed | Lands on |
|---|---|---|
| Bottom menu Construct, or C | nothing | catalogue, no site |
| Tile view Build key (Buildings tab) | the tile | catalogue filtered to what the tile allows; Confirm builds there |
| Tile view Power tab: Build power, Reduce intermittency | the tile, the Power filter, a "Battery" search | the same, filtered |
| Market row Expand; a deposit's Build key with no single option; the tutorial | an output good | catalogue filtered to that good (the filter is invisible today) |
| Esc during the map pick | the building and recipe | the confirm stage restored |

Paths that build **without** the panel: the search overlay's Build (straight to the map pick), a deposit's Build key with one option (builds at once), the tile view's infrastructure keys, the tutorial's build actions. Owner decision 3 asks whether they should go through the build order.

### 1.2 The stages today

1. **Catalogue**: building cards (icon, name, price), a search field, nine single-select category chips, a locked Blueprint tab; a card opens to its recipe rows.
2. **Confirm**: three layouts. The v3 confirm for a recipe (requirements, settings for intermittent power, timeline and payback, materials table, totals, recipe, cash after, Confirm with its reason, a materials source accordion); the old layout for infrastructure (purpose, level stats, materials, a land tickbox); the old layout behind a toggle.
3. **Settings**: output destination, material source, start at half capacity, auto-buy land, expanded recipe cards.
4. **Map pick** (no site chosen): the panel closes, the map shades, a hover card quotes the tile.

Captures of every stage and state as it stands: `tools/construct_flow_shot.tscn` (to be moved into the repo with the flag, Phase 0).

## 2. The scenarios

What changes what the player sees. Most are rows and lamps, not layouts; the engine answers each one (`ConstructionRules.quote()`), so a stage shows the verdict and the figures the build acts on.

| Scenario | Decided by | Shows as |
|---|---|---|
| Site known or not | the way in | with a site: verdicts, freight, land, forecast; without: estimates and "chosen on the map" |
| Research locked recipe or building | `recipe_offer`, `building_offer` | hidden, as today |
| Terrain (sea, offshore) | `recipe_offer`, `site_check` | not offered on that tile |
| Deposit known missing, or unsurveyed | `requirement_block`, `blind_deposit` | refused, or a blind build warning |
| Land: enough, buys, short, cannot buy, tile full | `land_plan` | a land line with its lamp; the buy intent |
| Planning limit passed | `land_plan.density_multiplier` | the fee 50% higher, said once |
| Material source and its research gates | `material_source` | the source, and a note when a gate changes it |
| Kit on the tile, bought, from a surplus tile, missing | `materials_quote` | each good's line and the materials figure |
| Cables or pipes missing | `site_needs` | advisory lamps |
| Intermittent power | `is_intermittent` | the supply choice |
| Not enough cash | `quote().blocks` | the spend key refused with the reason |
| Infrastructure (tendering, already there, in progress, roads on sea) | `quote()` with no recipe | the same order, levels instead of a forecast |
| Tutorial board | `quote().blocks` | refused off the board |
| Demo ruleset | `BuildForecastTable.show_balance_impact()` | payback only |

The parity check runs 31 of these through the real build and the helper, 96 checks.

## 3. Findings

1. **The same build is priced four ways.** Browse (base price plus the kit at buy price), the refusal toast, Confirm (the ledger) and the hover card each add it up differently; none matches the fee the build charges (base times the planning multiplier less the rebate). Fixed at the source: `quote()`.
2. **A refused build could report success.** From the tile's Build, Confirm said "Building X on Y" and closed when the map refused for anything but space. *Fixed (owner, 26 September): the map says whether it placed anything (`BuildMode.last_attempt_placed`), and that is what `attempt_direct_build` answers.*
3. **Land bought for a refused build was kept.** The build buys land before it checks the kit and the cash. *Fixed (owner): the purchase is held for the attempt and returned with its cash on any refusal (`world_map._settle_attempt_land`, `BuildingState.return_tile_land`); its toast only shows once the build is placed.*
4. **The width seesaws** between stages (560, 448, 510).
5. **Infrastructure uses the old confirm**, and is offered without checking Infrastructure Tendering.
6. **The goods filter is invisible** and cannot be cleared.
7. **Picking a material source without Remember** leaves the totals stale, and the pick carries to the next build anywhere.
8. **Railways on sea** passed the sea rule (it checked `rail`, the building is `rails`). *Fixed with the owner's rule for water (26 September): roads, rail, pipes and reinforced pipes are land only; cables reach the sea but not deep sea; HVDC, offshore wind farms and oil platforms go on deep sea (`EconomyConfig.SEA_INFRASTRUCTURE`, `Catalog.is_allowed_on_tile_type`). The build, the helpers, the map's infrastructure shading and the tile view's add keys all read it.*
9. **Confirm's materials figure** skips the import licence rule and the intermediary's free units.
10. **The Blueprint tab** is a locked stub.

## 4. The arrangement

**Principles.** One width for every stage. Each stage a body in one shell, swapped in place (as the tile view's tabs are), never a panel that resizes. Every figure and every refusal from `quote()`. Show only what informs (a section with nothing to say is not drawn).

**Proposed flow: two stages and a sheet.**

1. **Catalogue**: buildings by category, search, the goods filter shown as a removable tag. A building opens to its recipes; a recipe opens the order. Infrastructure is in the catalogue like any building.
2. **Build order** (one layout for everything): a fixed head (what, where, the total, turns to build, the spend key with its reason), then the sections that inform: requirements (lamps: land, cables, pipes, deposit, tutorial), money (materials, fee, land, total, cash after), the outlook (payback, the timeline outside the demo), materials (goods in wells, on tile, elsewhere, bought), recipe. Infrastructure swaps the outlook for its levels; intermittent power adds its supply choice; no site says the site is chosen on the map.
3. **Settings as a sheet** sliding over either stage (the DS2 sheet pattern), since they are company defaults, not a step.
4. **Map pick**: the hover card becomes a dot card (`scripts/ds2/dot_card.gd`) reading `quote()`, or the order stays open and follows the hovered tile (owner decision 4).

## 5. DS2 treatment: two concepts

Rendered side by side on the real surface, catalogue and build order at the same width (600 logical px), for the owner to choose.

- **Works office** (render set `constructoffice`, seed 433, study only): the catalogue is a steel plan chest, a drawer per building with a brass card holder, its raised emblem and price on an LED; the build order is a white plastic works order clipped to a steel board, lamps for requirements, goods in wells, the money column on LEDs in a dark plate, turns on a drum counter, the guarded Build key.
- **Construction lot with its crane** (render set `constructlot`, seed 434, study only): the panel is a site hoarding in navy painted steel with a yellow lattice crane along its top, the title in its cab; the catalogue is enamel site boards bolted to the hoarding; the build order is the lot, the site board lowered on the hook, the plot taped off with the land it takes, materials on pallets, lamps on a site power pillar, the money on LEDs in the site cabin, turns on the cab's drum counter, the guarded Build key.

Studies (rendered 26 September 2026, catalogue and build order side by side, each 1125 layout px = 600 logical wide):
- `artifacts/construct_ds2/construct_study_office.png`: the plan chest (ten latching keys with an All key, a dot-matrix search, drawers with brass card holders, the Furnace drawer open to its recipe cards) and the works order on white plastic under a clip (site, building, recipe, requirement lamps, goods in wells, a dark plate with the drum counter, payback, the money column and the guarded Build key).
- `artifacts/construct_ds2/construct_study_lot.png`: the hoarding with a yellow tower crane (mast, cab carrying the title, lattice jib, trolley and hook), enamel site boards two a row with recipe tags on chains; the build order with the site board lowered on a spreader, the lot taped off as a grid of 18 slabs and 2 to buy, a site clock drum counter, the cost cabin on LEDs, materials on timber pallets, a feeder pillar with the requirement lamps, payback and the guarded Build key.
- `artifacts/construct_ds2/construct_study_lot_v2.png` (round 2, after the owner's first review): the tower cut off by the panel's edge, STONESHORE DOCKS on a plate hung from the jib, the search in a tab rising from the category plate, recipe tags as diagrams (goods in wells, power on the arrow), and the whole build order to the fold and past it: the site board with its recipe, the verdict (total, cash after £49.5K, turns, the guarded Build key), requirement lamps, the cost cabin with the Materials from knob, pallets with on tile, elsewhere and price, the outlook with the timeline and buffer, and the land lot last and small.
- `artifacts/construct_ds2/construct_study_lot_v3.png` (round 3, after the owner's second review): the tower half as wide; LED points in their own cells and the new money rule (Materials £441 whole, Total £481.3, Cash after £49.5K); materials as one yard in two columns and three rows with the Materials from knob in the sixth bay, set to the intermediary, and no per good prices; the site board as the blueprint icon beside an enamel recipe sign (expanded), the catalogue's tags as enamel plates (condensed); names Iron Furnace and Steel Furnace; building icons flat blueprint, with a swatch of relief, simple emboss and flat; the ribbed seam under the verdict marking the fixed head.
Open points the studies raise: the site named twice on the works order; the lot's land note repeating its lamp; the lot's small recipe pills and board LEDs below the game's sizes; seven boards leaving one cell empty in two columns.

## 6. Numbers first (done)

`scripts/construction_rules.gd`: `catalogue`, `recipe_offer`, `building_offer`, `site_check`, `requirement_block`, `blind_deposit`, `land_plan`, `material_source`, `materials_quote`, `build_fee`, `infrastructure_fee`, `site_needs`, `is_intermittent`, `quote`. The build (`world_map.gd`) calls its requirement, land, source and fee rules. Unit test `_test_construction_rules`; parity `tests/construction_rules_parity.tscn` (headless; exits 1 on any disagreement). The panel, the map overlay and the hover card still carry their own copies until the DS2 stages read `quote()`.

## 7. Phases

| Phase | What | Size |
|---|---|---|
| 0. Measure | the flag `UiPrefs.use_construct_ds2` and `toggle construct ds2`; the capture tool in the repo with a view per scenario of §2; the first standard of today's look | S |
| 1. Concept | the two studies; the owner picks; the numbered decisions answered | S |
| 2. Shell | backing, title, the stage switch, seam, scroll, lamp overlay; the one width | M |
| 3. Build order | first, since money moves there and it has the most branches; reads `quote()`; replaces the old infrastructure layout | L |
| 4. Catalogue | cards, categories, search, the goods filter tag | M |
| 5. Settings sheet, map card | the sheet; the hover card as a dot card on `quote()` | M |
| 6. Default | the owner's review rounds; the standard saved; the flag on by default | S |

Each body is reviewed against §2's scenarios, up to three rounds, as the tile view's were. Tutorial and test handles kept: `ConstructPanelV2`, `BuildingCard_<id>`, `RecipeRow_<id>`, `BuildConfirmButton`, `ConstructionMaterialsSection`, `expand_building()`.

**Built so far (27 September 2026).**

- **The panel.** `scripts/construct_ds2/construct_ds2.gd` extends `construct_panel_v2.gd`: every way in, the state, Confirm and the handles the tutorial and tests look up are the parent's; the shell and the build order are its own. `bottom_menu.gd` builds it in place of today's panel while the flag is on and rebuilds it when the flag flips (`_construct_v2_script`, `_on_construct_ds2_changed`), under the same name, `ConstructPanelV2`.
- **The build order** (`scripts/construct_ds2/build_order.gd`): the site board on the hook (the name raised, the icon printed flat as a blueprint from its emblem's silhouette, `flat_print.gdshader`, the recipe on an enamel sign in the board's recess), the verdict on the cabin desk (Total and Cash after on LEDs, Turns to build on a drum, when the materials arrive, the Build key named `BuildConfirmButton`: a plain cream key in a brass bezel, not guarded (owner, 27 September; render `construct_key_brass`, set constructkey 468, drawn by `cream_key.gd` with `rim = "brass"`); refused, it prints red and a press makes the blocking part glow, the money or the land's row or the requirement, `flag_blocker`), the seam; then the requirements on the feeder pillar (two lamps a pillar), the cost in the cabin, the materials yard (a good on its pallet in its well, a white label with what is on the tile and elsewhere, the Materials from knob in the sixth bay, which sets `MatchState.pending_build_material_source`), the outlook on the programme board and the land lot. The Build key's refusal is the quote's first block (`_v3_confirm_block_reason`).
- **Renders** (`tools/button_mockup/cluster.html`, inside the `constructlot` block so they share the study's parts; the study still renders byte identical): `constructhead` (464: `construct_head`, `construct_mast`, `construct_placard`, `construct_trolley`, `construct_rig`, `construct_hoarding`), `constructboard` (465: `construct_board`, `guard_build` and its pressed and cover layers), `constructyard` (466: `construct_yard`, `construct_pallet`, `construct_pillar`, `construct_lot`, `construct_slab`, `construct_stake`, `construct_tape`), `constructcat` (467: `construct_settings` and `_pressed`, `construct_catplate`, `construct_card`, `construct_tag`). Each is placed by the game at its `origin` in layout px.
- **The catalogue** (`scripts/construct_ds2/catalogue.gd`, 27 September): the black control plate under the crane, its tab rising under the jib with the search set into its dark glass, the nine category keys (the tile view's latching keys, one latched while its category is shown) in two rows; an enamel site board per building, two to a row (the blueprint icon, the name, the price on a red LED, `quote()`'s total for the building on the site), dimmed with the reason on its hover when no recipe can be built there or the money is short; the building opened across the width with its recipes hung under it on chains as enamel tags (the name it will take, the recipe condensed or expanded as the Construct setting says). The goods filter shows as a line with a Show all key (finding 6). Names kept: `BuildingCard_<id>`, `RecipeRow_<id>`, `Filter_<category>`.
- **Land** follows the Construct setting Auto-buy land until the player chooses on the build order: with it off and the tile short, the Land row says what it would buy and offers a **Buy land** key (the old confirm's land tickbox, `buy_land`).
- **Infrastructure** has the same build order: its purpose on the enamel sign in place of a recipe, LEVELS (units or power a tile carries a turn, tiles a turn, cost per unit, for levels 1 to 3, from EconomyConfig and TransportService) in place of the outlook, no land lot; the yard only where it takes materials (Cables, not Roads, Pipes or Rails). It is chosen from the catalogue alone, so its site is always chosen on the map. The old confirm's infrastructure layout is no longer used in DS2.
- **Recipes of any size** (`build_order.fit_plan`, owner rulings 27 September): one row while each side has two goods at most and they keep 48 px or more (64 px for most); a side of three or more goods goes into two rows, the longer on top and the shorter centred under it, and a side of one or two beside it stands larger (one good as tall as the grid, up to 72 px). The game's recipes run to six inputs and four outputs, seven in all; all 146 fit the tag and the build order's sign in both settings (`tools/recipe_fit_sheet.tscn` renders them side by side). Every output is drawn (RecipeDiagram.flow_from_recipe gives the first alone); a good with no icon yet (Electronic Waste) shows its name on a cream tile.
- **A recipe's name sits outside its diagram** (owner): on a tag, in a tab rising from its top edge between the chains, 15 px in from each, so the whole body is the diagram's; on the build order, raised on the site board above the enamel sign.
- **The building card is a shipping container** (owner, 27 September): blue painted corrugated steel between darker rails, a corner casting at each corner (`construct_container`, cropped to the card's width, never stretched), with the enamel plate bolted to its left end holding the blueprint icon, the name and the price (`construct_card_plate`); the price's foot level with the foot of the icon's tile. Set constructbox, 469.
- **A recipe tag glows while hovered**: the amber lamp glow added over its diagram (`catalogue.HoverGlow`).
- **Settings on the crane** (owner, 27 September): a steel plate bolted over the jib's root beside the cab, a white plastic key with a chamfered bevel and a navy gear (`construct_settings`, `_pressed`); it opens the settings and, pressed again, comes back.
- **Captures:** `tools/construct_ds2_shot.tscn`: the catalogue (whole, the Furnace opened condensed and expanded, Metallurgy picked, the goods filter), the settings, the build order on Stoneshore at its top, middle and foot, the build order with no site. Step one in `artifacts/construct_ds2/ds2_v1/`, with the catalogue in `ds2_v2/`.
- **Tests:** `tests/unit/test_construct_ds2.gd`.

## 8. Decisions for the owner

1. **Metaphor**: works office or construction lot with its crane (studies, §5). *Decided: the construction lot with its crane (26 September 2026). The owner's first review of it:*
   - *The tile's name, when one is chosen, on a placard hanging off the jib, symmetrical to the CONSTRUCT plate on the cab.*
   - *The crane's mast much wider, running off the panel's edge so only part of it shows.*
   - *The land lot is good to look at but far from the most important information: smaller, lower.*
   - *Cash after follows the money rule used elsewhere (`scripts/ds2/money_figure.gd`: £999.99, £9999, £15.6K, £1.01M, £1.01B, no pence past £1,000).*
   - *Show the whole build order, not a crop.*
   - *The search field moves under the crane, in a notch rising from the category plate.*
   - *A recipe on a building's board shows what it consumes and makes, not only its name.*
   *Round 2 of the study answers these (`artifacts/construct_ds2/construct_study_lot_v2.png`).*
2. **Width**: one width for every stage (decided); 600 logical px proposed (the tile view is 800, Building Detail 460, the upgrade panel 780).
3. **Paths that skip the panel** (search Build, a deposit's Build key, the tile view's infrastructure keys): through the build order, or stay quick builds?
4. **Map pick**: the build order stays open and follows the hovered tile, or a separate hover card as a dot card?
5. **Blueprint tab**: cut, or planned?
6. **Settings as a sheet** over the stages rather than a stage of its own?
7. **Findings 2, 3 and 8**: fixed now, separately from the look (decided, 26 September 2026).
8. **Credit facility**: removed (decided, 26 September 2026).
