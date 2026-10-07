# Local Suppliers: hub haulage and sale bands

Local Suppliers (`middleman_v1` games; `middleman` in code) price their haulage on the same freight model the
player's own logistics use, measured to the nearest market hub, and buy each hub area's goods in volume bands.
The aim: Local Suppliers are the convenient early route; hauling your own goods to the global market beats
them once you have built roads, rail or pipes, and selling past a hub area's demand pushes volume to the market.

## Fee per unit

| | Local Suppliers | Own logistics |
|---|---|---|
| You receive | P − port(P) − n × S × r − band change | P − port(P) − Σ legs r × mode multiplier |
| Haul basis | trips over bare ground to the nearest hub | the route actually built |
| n, trips | ceil(hex distance to hub ÷ 2), at least 1 | legs; infrastructure levels lengthen a leg |
| Multiplier | settlement factor S (below) | bare ground 2.0, road 1.0, rail 0.5, pipe 1.0, tankers 3/6 (safe), 5/10 (hazardous) |
| Volume | sale bands per hub area (below) | congestion |
| Cash | same turn | on arrival |

- `P` is the market sale price; `port(P)` the port's base charge (3% ad valorem plus the weight fee), passed on
  at the base tariff exactly as before.
- `r` is the good's freight rate per turn-move, `EconomyConfig.transport_rate_for_good` (class flat rate plus
  the class's share of the good's value, ×1.4), before the player's research. Because both routes use `r`,
  the comparison is the same for every good: own route wins when `legs × mode multiplier < n × S`.
- Purchases through Local Suppliers pay the same haul.

## Hubs and settlement factor

Hubs are the authored ports, completed runtime ports (`b_004`) and the inland hubs in
`middleman_locations.gd` (`INLAND_HUB_TILES`: Port Lightning, a lake city with a deep hinterland). Every land
tile belongs to its nearest hub.

| Settlement | S |
|---|---|
| Hub city: an urban area holding a hub | 1.1 |
| City: 3 or more connected urban tiles | 1.25 |
| Town: 1 or 2 urban tiles | 1.5 |
| Rural or hill | 1.75 |
| Mountain | 2.0 |
| Sea or deep sea | no Local Suppliers |

With bare ground at 2.0 the order holds on every tile:
own bare ground ≥ Local Suppliers > own road > own rail.

## Sale bands

Every sale is priced against what its hub area has already sold of that good this turn, per unit:

| Hub area's volume this turn | Price |
|---|---|
| up to 3 × band size | +5% |
| 3 to 4.5 × band size | market price |
| above 4.5 × band size | −5% |

Band size is the good's base output (`Catalog.base_output_for_good`, one building of its best unlocked
recipe) times `EconomyConfig.impact_threshold_scale`, the same growth the market's impact thresholds use.
A sale never fetches more than the market's buy price, so nothing can be bought globally to resell.
The ledger is per production pass (`MiddlemanService.area_sold`/`note_area_sale`) and is not saved.

## Freight changes that come with it (all games)

- Bare-ground turn-moves, and straight-line hauls with no route, cost 2× a road.
- Gas flat freight 0.30 → 0.05 per turn-move; its 4% value share is unchanged.

## Map check

Classified from `data/tile_properties.csv`: 27 hub-city tiles, 31 city, 34 town, 258 rural/hill,
45 mountain. Port Lightning as a hub shortens the haul for 76 northern tiles.

Own haul as a share of the Local Suppliers haul, 6 tiles from the hub:

| Mode | S 1.1 | 1.25 | 1.5 | 1.75 | 2.0 |
|---|---|---|---|---|---|
| Bare ground | 182% | 160% | 133% | 114% | 100% |
| Road / pipe L1 | 91% | 80% | 67% | 57% | 50% |
| Rail L1 | 30% | 27% | 22% | 19% | 17% |

Gases: nitrogen sells through Local Suppliers on 394 of 395 land tiles; oxygen (sale £0.275) only near hubs,
75 tiles. Gases are hauled to the hub like any other good.
