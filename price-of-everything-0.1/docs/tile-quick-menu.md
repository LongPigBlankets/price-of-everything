# Tile quick menu and favourite builds

Status: **BUILT** on `claude/tile-quick-menu` (stacked on the land pricing branch, PR #205).

A right click on a map tile opens a small DS2 menu: the tile's name over five actions. An action that cannot run
stays listed with its lamp dark and the reason as its words.

| Action | What it does |
|---|---|
| Sell all surplus | Sells the tile's stock above what its own buildings need (`Production.compute_sell_reserve_for_tile`, as the standing Sell surplus order) and above any keep the player set. |
| Sell all of a good | Opens the tile's goods; picking one sells all of it. |
| Buy all land | Buys every patch left for sale, on its own (double price, neighbours +200%). Asks first, naming the neighbours that rise. |
| Sell all spare land | Sells whole patches of land the player bought that no building, project or upgrade uses. |
| Build a favourite | Opens the favourites, each priced on this tile at its level; picking one builds it, buying the land it needs. |

Selling goes to the global market at once where it is open (`MatchState.queue_sell`). In a Local Suppliers game
before the Import/Export License it is queued (`MatchState.queue_local_sale`, saved) and Local Suppliers buy it in
that turn's sell phase.

## Land sale price

Spare land sells for the tile's starting price plus the economy's rise: `LandPrice.sale_price` = S x (1 + e). It
leaves out the rises the player makes (buildings on the tile, neighbouring purchases), so buying land and raising
its own price never makes money; land bought before an economy doubling sells for more after it. Only land the
player bought sells (`tile_land_priced`): land granted by the start or with a bought building was never paid for at
the land price.

## Favourites

The star at the end of Building Detail's status line (`key_star`, lit `key_star_on`) adds or removes the
building's type, recipe and level. Favourites are saved with the match (`MatchState.favourite_builds`).

A favourite above level 1 is built straight at that level: `BuildMode.attempt_direct_build(..., level)` hands the
level to `Construction.placing_level` for that one attempt. The kit is the level 1 kit plus each upgrade's
materials, the footprint is the level's (`BuildingLevels.mult("size")`), the build takes
`Construction.LEVELLED_BUILD_EXTRA_TURNS` (2) more turns, the fee is level 1's, and the level's research is
required. `ConstructionRules.quote(..., {"level": n})` prices it the same way.

## Code

`scripts/tile_quick_actions.gd` (what each action can do and does), `scripts/tile_quick_menu.gd` (the menu),
`hex_map.gd` `tile_menu_requested`, `world_map._on_tile_menu_requested`. Tests: `tests/unit/test_tile_quick_menu.gd`
(tag `tile_menu`). Captures: `tools/tile_quick_menu_shot.tscn`.
