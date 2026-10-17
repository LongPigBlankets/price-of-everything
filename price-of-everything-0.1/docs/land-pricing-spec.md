# Spec — Land Pricing (bands, ramps, stand-alone purchases, economy index)

Status: **BUILT** on `claude/land-pricing` (stacked on PR #204). Written 2026-10-12 against `main` at `3d8e032a`.
Every *(proposed)* default below shipped as written; §14 lists where the build reads the spec a particular way.
Change class: **Mechanic change** (`cnc-balance-change-control`): balance protocol plus this design note.

Owner rulings from 12 October 2026 are marked **LOCKED**. Defaults I chose where no ruling
exists are marked *(proposed)* and collected in §13 for a decision. Figures marked *estimate*
come from arithmetic on the current data, not from a harness run.

---

## 0. Why this exists (design intent)

Land is a flat £10 per 10-unit patch on every tile today (`BuildingState.LAND_PATCH_COST`).
A furnace plot costs £20 against builds of several hundred pounds, so where the player builds is
a pricing detail. Local Suppliers already make cities the cheapest place to trade
(`MiddlemanLocations`: hub city 1.1, city 1.25, town 1.5, countryside 1.75, mountain 2.0), and
nothing pushes the other way.

This spec makes land the opposing force. The same settlement class that gives cheap haulage gives
dear land, so location becomes an investment decision. Land also gets dearer as the player stacks
buildings on a tile and spreads onto neighbouring tiles, and urban land rises as the whole economy
grows.

It follows the game's existing pattern: the player's own scale pushes back, as it does on prices.

A consequence worth keeping: buying an existing works never moves a land price (§7), so
acquisition becomes the way into an expensive city. That extends buy-versus-make to buildings.

---

## 1. The rules in one breath

1. **Starting price by settlement.** Hub city ×10, city ×6, town ×4, everywhere else ×2 of
   today's £10 a patch. **LOCKED**
2. **Each building you construct on a tile adds 50% of that tile's starting price** to the next
   patch bought there. **LOCKED**
3. **Owning land next door adds 25% of the tile's starting price.** Applies on every tile,
   urban or not. **LOCKED**
4. **Land bought on its own costs double**, and it raises every neighbouring tile by 200% of
   that neighbour's starting price, in place of the 25%. **LOCKED**
5. **Urban land rises 25% of its starting price each time the economy doubles.** The economy is
   the summed revenue of every rival plus the player. **LOCKED**
6. **Buying another company's building changes no land price anywhere.** **LOCKED**
7. **Every rise is a share of the tile's starting price**, so rises add and never compound.
   **LOCKED**

---

## 2. The formula

```
S(tile)   = LAND_PATCH_COST × BAND[band(tile)]            # the tile's starting price per patch
share     = 1 + 0.5 × n(tile) + a(tile) + e(tile)
per_patch = S(tile) × share × (2 if stand-alone else 1)
cost      = AdvisorState.purchase_cost_after_advisor(per_patch × patches, {"tile_id": tile})
```

| Term | Meaning | Section |
|---|---|---|
| `BAND` | hub city 10, city 6, town 4, rest 2 | §3 |
| `n(tile)` | counted buildings on the tile | §4 |
| `a(tile)` | 2.0 beside a stand-alone purchase, else 0.25 beside land you bought, else 0 | §5 |
| `e(tile)` | 0.25 × economy level on urban tiles, 0 elsewhere | §6 |
| stand-alone | land bought without a build or an upgrade | §5 |

All patches in one purchase are priced on the state before that purchase. The existing advisor
`purchase_cost` modifier still applies last, as it does today.

### Constants (`scripts/economy_config.gd`)

```gdscript
const LAND_BAND_MULT := {"hub_city": 10.0, "city": 6.0, "town": 4.0, "rest": 2.0}
const LAND_RAMP_PER_BUILDING := 0.5     # share of S per counted building on the tile
const LAND_ADJACENT := 0.25             # share of S when a neighbour holds land you bought
const LAND_ADJACENT_STANDALONE := 2.0   # share of S when a neighbour was bought stand-alone
const LAND_STANDALONE_MULT := 2.0       # whole quote, stand-alone purchases only
const LAND_ECONOMY_STEP := 0.25         # share of S per doubling of global revenue, urban only
```

`BuildingState.LAND_PATCH_COST` (10.0) and `LAND_PATCH_SIZE` (10) are unchanged.

---

## 3. Bands

**Ruling:** a large city is a hub city, the class Local Suppliers already use. **LOCKED**

| Band | Definition (as `MiddlemanLocations.classify`) | Tiles | Patch | Furnace plot (2 patches) |
|---|---|---:|---:|---:|
| Hub city | urban area containing a port or inland hub | 27 | £100 | £200 |
| City | urban area of 3 or more tiles, no hub | 31 | £60 | £120 |
| Town | urban area of 1 or 2 tiles | 34 | £40 | £80 |
| Rest | rural, hill, mountain | 303 | £20 | £40 |

Both demo starts are in towns: Greyroad is a 2-tile settlement and Ashmouth a single tile.
Stoneshore, Vandel Port and Port Lightning are hub cities despite having 3 or 4 tiles.

- **Bands are fixed at match start** *(proposed)*. `MiddlemanLocations.factors()` re-derives hub
  cities when the player builds a port, which would lift a city from ×6 to ×10 mid-match. The land
  band uses the authored hubs only (`data/ports.csv` plus `INLAND_HUB_TILES`).
- **Sea tiles take the "rest" band** *(proposed)*, for offshore platforms and wind farms.
- **Name the band in the UI as Local Suppliers do.** One label then explains both prices.

---

## 4. The building ramp

`n(tile)` counts buildings that are all of:

- owned by the local player,
- not infrastructure (`Catalog.get_building(id).category != "infrastructure"`, the same test
  `VictoryState._count_widest_tiles` uses: roads, cables, pipes, rail and ports drop out),
- not flagged `land_exempt` (below),
- standing **or under construction** on the tile, so five builds queued in one turn each pay one
  step more than the last.

The count is live: demolishing or selling a counted building lowers it *(proposed)*. Money already
paid is never refunded by a falling count.

### `land_exempt`

A new boolean on the building instance. Exempt buildings never count. It is set for:

1. **Buildings bought from another company.** Set in `BuildingState.set_building_owner` beside
   `acquired_from_npc`. **LOCKED** (rule 6)
2. **The starting estate** *(proposed)*: buildings created from the start config in
   `SaveLoad.prepare_new_game`. Without this, Greyroad opens with two counted buildings and the
   first mission's plot doubles.
3. **Every player building in a migrated save** (§9), so nothing changes retroactively.

The flag is separate from `acquired_from_npc` on purpose. That one drives the tile chart's
stacking order and should not carry a pricing rule.

---

## 5. Adjacency and stand-alone purchases

### Priced land

`a(tile)` reads a new per-tile counter, `tile_land_priced`: land units the player bought through
`BuildingState.purchase_tile_land`. It excludes:

- land granted under a bought building (`_grant_building_land`). **LOCKED** (rule 6)
- the start config's land grant *(proposed)*.

`tile_land_owned` keeps its present meaning and still gates building.

### The neighbour term

```
a(tile) = 2.0   if any neighbour is in tile_land_standalone
        = 0.25  else if any neighbour has tile_land_priced > 0
        = 0     otherwise
```

- **It applies once per tile** *(proposed)*, however many neighbours qualify.
- **The 200% replaces the 25%.** It is the larger of the two, never their sum.
- **A tile's own land does not raise its own price.** Only the building ramp does that.
- Neighbours come from `Catalog.tile_neighbours` (six on the hex grid, fewer at the map edge).

### Stand-alone purchases

**A purchase is stand-alone when it is not attached to a build or an upgrade** *(proposed)*.
The code already separates the two:

| Path | Where | Stand-alone |
|---|---|---|
| Build buys its shortfall | `construction_rules.land_plan`, `world_map.gd` (~L2980) | no |
| Upgrade buys its shortfall | `building_works.upgrade_land_purchase` (~L117, L755) | no |
| "Buy land" on the tile panel | `tile_info_panel_v2._buy_land_amount` | **yes** |

A stand-alone purchase:

1. pays `LAND_STANDALONE_MULT` × the normal quote,
2. adds the tile to `tile_land_standalone`,
3. takes effect **immediately**. The next quote in the same turn, on any neighbour, already
   carries the 200%. Buying a block of tiles in one turn must not dodge it.

The flag clears if all priced land on the tile is later sold.

**Why it is a decision and not a trap:** on a fresh tile, paying as you go costs the same as a
stand-alone purchase at five buildings and more from the sixth.

| Buildings on the tile | As you go (× plot at S) | Stand-alone (× plot at S) |
|---:|---:|---:|
| 3 | 4.5 | 6 |
| 5 | 10 | 10 |
| 8 | 22 | 16 |
| 10 | 32.5 | 20 |

---

## 6. The economy index

**Rulings:** it covers all urban tiles, and it grows 25% per doubling. **LOCKED**

```
G(t)  = sum of revenue over CompanyRankings.standings()      # 19 rivals + the player
G0    = CompanyRankings.TOTAL_COMPANIES × CompanyRankings.STARTING_REVENUE   # 20 × £150 = £3,000
level = max(previous level, floor(log2(G(t) / G0)))          # never negative, never falls
e(tile) = LAND_ECONOMY_STEP × level   on hub city, city and town tiles;  0 elsewhere
```

- **`G0` is a constant** *(proposed)*, so no baseline needs saving. `standings()` reports the
  player at £0 before the first turn resolves, so the level starts at 0 and cannot go below it.
- **The level latches** *(proposed)*. A revenue dip around a threshold must not make prices flicker.
- **It ticks once a turn on `TurnManager.turn_advanced`.** That fires after the AI phase, where
  `CompanyRankings` recomputes, so the level a player sees in DECIDE is the one they pay.
- **It is a clock.** Nineteen of the twenty firms follow a seeded curve; the player is about a
  twentieth of the total. That is acceptable, and it makes the index forecastable.
- **Expected steps (estimate):** the first doubling around turns 35–50 and the second around
  70–90 on the current "hard" preset, so a 100-turn game ends near +50% and a 300-turn game near
  +200%. Record the actual turns for three seeds before tuning.

### Stance change to record

`docs/company-rankings-spec.md` says the table is cosmetic and must change no number. This index
is the first place rival revenue changes a cost the player pays. Update that spec and the
"scenery-with-services" line in `cnc-design-intent` when this ships. Retuning rival difficulty
will also retune land prices; note that beside `CompanyRankings.DIFFICULTIES`.

---

## 7. What never moves a land price

- **Buying another company's building.** No quote changes on its tile, on a neighbour, or
  anywhere else. The building is `land_exempt` and its footprint is not priced land. **LOCKED**
- **Selling a building, or buying one back.**
- **Rival and NPC buildings**, which are static scenery.
- **Infrastructure**, including tendered infrastructure that crosses land the player does not own.
- **Research, advisers and decisions**, except through the existing `purchase_cost` modifier.

Land the player later buys on the same tile as a bought building is ordinary priced land.

---

## 8. Code shape

One new stateless script owns the price. Nothing else multiplies by `LAND_PATCH_COST`.

```gdscript
# scripts/land_price.gd  (RefCounted, static, typed; reads state, owns none)
static func band(tile_id: String) -> String              # "hub_city" | "city" | "town" | "rest"
static func starting_price(tile_id: String) -> float     # S(tile)
static func counted_buildings(tile_id: String) -> int    # n(tile)
static func adjacency_share(tile_id: String) -> float    # a(tile)
static func economy_share(tile_id: String) -> float      # e(tile)
static func quote(tile_id: String, patches: int, standalone: bool) -> Dictionary
#   {"per_patch", "total", "patches", "standalone",
#    "terms": [{"id", "label", "share", "amount"}],   # the lines the UI prints; they sum to per_patch
#    "advisor_pct"}
```

`BuildingState.purchase_tile_land(tile_id, patches, cap, standalone := false)` charges
`LandPrice.quote(...)`. On success it adds the granted units to `tile_land_priced` and, when
`standalone`, adds the tile to `tile_land_standalone`. `return_tile_land` (a refused build)
restores `tile_land_priced` along with the land and the cash.

### Touch points

| File | Change |
|---|---|
| `scripts/building_state.gd` | new state; `purchase_tile_land`, `return_tile_land`, `sell_tile_land`; `land_exempt` in `set_building_owner` |
| `scripts/construction_rules.gd` | `land_plan` cost from `LandPrice.quote(..., false)` |
| `scripts/world_map.gd` | build attempt passes `standalone = false` |
| `scripts/building_works.gd` | `upgrade_land_purchase` cost from `LandPrice` |
| `scripts/tile_info_panel_v2.gd` | stand-alone purchase, its confirm dialog and the price lines (§10) |
| `scripts/tvp_v3/transport_quote.gd` | quote text reads `LandPrice` |
| `scripts/construct_ds2/build_order.gd` | row already prints `plan.cost`; add the breakdown |
| `scripts/company_rankings.gd` | read-only `global_revenue()` accessor |
| `scripts/save_load.gd` | start-estate flag in `prepare_new_game`; migration (§9) |
| `scripts/middleman_locations.gd` | expose the class name, and a variant on authored hubs only |

Architecture contract: the sim stays out of the scene tree, the UI only reads, there is no RNG,
and the one per-turn tick runs from `turn_advanced`. Quotes are pure reads made during DECIDE.

---

## 9. State, saves and migration

New saved state, all in `BuildingState.export_fields` under the existing "match" section:

| Field | Type | Meaning |
|---|---|---|
| `tile_land_priced` | `{tile_id: int}` | land units bought through `purchase_tile_land` |
| `tile_land_standalone` | `{tile_id: true}` | tiles holding a stand-alone purchase |
| `land_economy_level` | `int` | latched doublings (§6) |
| `land_exempt` | `bool` on a building | never counts toward the ramp (§4) |

`SAVE_VERSION` 16 → 17, with `_migrate_v16_to_v17`:

- stamp every player-owned building `land_exempt = true`,
- leave `tile_land_priced` and `tile_land_standalone` empty,
- set `land_economy_level` from the save's current standings.

An old save therefore reopens with every tile at its band price plus the economy step, and the
ramps start from the next thing the player does. Readers stay tolerant (`d.get(key, default)`).

---

## 10. Legibility

The mechanic ships with its readouts, as the design-intent rules require.

- **Tile panel, land list.** A "Land price" block whose lines sum to the patch price:
  `Town ×4  £40` · `2 buildings here  +£40` · `Next to your land  +£10` ·
  `Economy doubled once  +£10` · `Per patch  £100`. It prints `quote.terms` directly.
- **Construct panel.** The existing "Buys 20 land for £200" row gains the same breakdown.
- **Stand-alone confirm.** The dialog shows the doubled price and names the neighbouring tiles
  that will rise 200%, before the player commits.
- **Map overlay.** A "Land price" mode shading each tile by its current patch price.
- **Turn briefing.** A news line when the economy doubles, and an earlier line when global
  revenue passes 80% of the next doubling *(proposed)*.
- **Rankings panel.** One line for global revenue and the current level.
- **Encyclopedia.** A "Land prices" concept entry stating the seven rules in §1.

No readout may reveal an unsurveyed deposit.

---

## 11. Worked examples

Each uses today's data and assumes the proposed defaults.

| # | Situation | Working | Cost | Today |
|---|---|---|---:|---:|
| A | Metal Magnate's first steel furnace on Greyroad. It needs 18 land and 14 are free, so 1 patch. Town, starting estate exempt. | £40 × 1 | £40 | £10 |
| B | Fourth furnace you build on one countryside tile | £20 × (1 + 1.5) = £50 a patch, 2 patches | £100 | £20 |
| C | Fifth building you construct on a hub-city tile, with your land next door, after one doubling | £100 × (1 + 2.0 + 0.25 + 0.25) = £350 a patch, 2 patches | £700 | £20 |
| D | Stand-alone purchase of a whole fresh countryside tile, 20 patches | £20 × 2 = £40 a patch | £800 | £200 |
| E | Buy a rival's furnace on the tile in C | no quote changes anywhere | n/a | n/a |

After D, a countryside neighbour's patch goes from £20 to £60 and a town neighbour's from £40 to
£120.

**Location payback (estimate).** One pig-iron furnace trading through Local Suppliers at one trip
from its hub, at the base heavy-goods rate: a hub-city plot costs £160 more than a countryside one
and saves about £7 a turn in haulage, so it pays back in roughly 24 turns. City and town plots pay
back in roughly 15. Verify against live haul rates.

---

## 12. Interactions, balance and tests

### Interactions

- **Local Suppliers.** Shares the settlement classes. The two gradients run in opposite directions
  by design.
- **Pollution (designed, not built).** It will be a second cost on stacking. Sweep the two
  together when pollution lands.
- **Victory tracks.** Widest and the demo's Estate both reward spreading, which now costs 25% a
  neighbour. Include both in the sweep.
- **Advisers.** The Chief Investment `purchase_cost` discount is worth more than it was.
- **Thin starts.** Open Field (£1,500, nothing built) and Ambitious Start (£300) pay the new
  price on every plot. Check both still open.

### Predictions to record before running (balance protocol step 1)

- First steel furnace land, Metal Magnate: £10 → £40.
- A furnace plot on a fresh tile: £20 → £40 countryside, £80 town, £120 city, £200 hub city.
- Start soaks with no builds: profit per turn unchanged, because the rules touch purchases only.
- Economy doublings: first at turns 35–50, second at 70–90.

### Gates

Parse check, the unit suite, the e2e run with its failure set unchanged apart from declared
intent, and 50-turn soaks for both demo starts. State "sweep N/A" if the sweep harness is still
unbuilt.

### Unit tests (tag `land`)

1. A fresh tile quotes £100, £60, £40 and £20 by band.
2. The ramp adds: four counted buildings give 3.0 × S, not 1.5⁴ × S.
3. **Buying a rival's building leaves every one of the 600 tiles' quotes unchanged.**
4. Starting-estate buildings and infrastructure do not count.
5. Buildings under construction count.
6. Two qualifying neighbours still add 0.25 once.
7. A stand-alone purchase charges double and sets its neighbours to 2.0 at once; a second
   stand-alone purchase on a neighbour in the same turn pays S × 3 × 2.
8. The 200% replaces the 25% and does not add to it.
9. At twice `G0`, urban tiles gain 0.25 and other tiles gain nothing; a later dip does not lower it.
10. A refused build returns the land, the cash and the priced-land count.
11. The adviser modifier applies after the formula.
12. Save round trip, and a v16 save migrates to band prices for its existing estate.
13. Same seed and same actions give the same quotes, headless and windowed.
14. The tile panel's lines sum to the quote, and the construct panel's land cost equals it.

---

## 13. Decisions still needed

| # | Question | Default in this spec | Why it matters |
|---|---|---|---|
| 1 | Does the starting estate count toward ramps and adjacency? | No, it is exempt | If it counts, example A is £80 and the opening tiles' neighbours start at +25% |
| 2 | Does the 25% stack per owned neighbour? | No, once per tile | Stacking could reach +150% on a tile ringed by your land |
| 3 | Is every tile-panel purchase stand-alone, even one patch? | Yes | A size threshold would be gentler but adds a rule to explain |
| 4 | Does demolishing or selling lower the ramp? | Yes, the count is live | A permanent count is simpler to explain and harsher |
| 5 | Are bands fixed at match start? | Yes | Otherwise a player-built port lifts its city to ×10 |
| 6 | **How is the land under a building valued?** | Unchanged, flat £10 a patch | See below |
| 7 | **Does the planning limit stay?** | Unchanged | See below |
| 8 | What does the land-deal decision's `sell_land` pay? | Unchanged, flat £10 × `price_mult` | It should never pay more than the land cost |

**6. Land under a building.** `BuildingPrice._land_cost` values a building's land at the flat £10.
Buying a building grants its footprint as owned land, and demolishing leaves that land owned. With
hub-city patches at £100, buying a cheap building and demolishing it yields city land far below
the land price. Disused Buildings are the clearest case: 15 land and a near-empty kit. I recommend
valuing the land leg at the tile's starting price, with no ramp, index or stand-alone multiplier.
That raises the price of buildings for sale in cities, so it is a balance change of its own. It
does not conflict with rule 6, which concerns land prices and not building prices.

**7. The planning limit.** `DENSITY_SOFT_CAPACITY` adds 50% to a new building's material and
money cost once a tile passes 100 land in use, other companies' buildings included. The building
ramp now prices the same behaviour smoothly. I recommend retiring the limit in this change, so
stacking is charged once here and once more when pollution lands.

---

## Provenance

Verified on 2026-10-12 in `building_state.gd`, `construction_rules.gd`, `building_works.gd`,
`building_price.gd`, `middleman_locations.gd`, `company_rankings.gd`, `save_load.gd` and
`data/tile_properties.csv`. Settlement counts were computed from the tile data with the same
neighbour rule and class thresholds the code uses. `SAVE_VERSION` is 16.

---

## 14. Implementation notes

| Where | What |
|---|---|
| `scripts/land_price.gd` | The formula, the quote's `terms`, `lines()` for every readout, `tick_economy()` |
| `scripts/middleman_locations.gd` | `land_band()` (authored hubs only, cached for the session) and `settlement_class()`; the urban-area walk is shared with `factors()` |
| `scripts/economy_config.gd` | The six constants of §2, plus `LAND_ECONOMY_FOREWARN` (0.8) for the briefing's early line |
| `scripts/building_state.gd` | `tile_land_priced`, `tile_land_standalone`, `land_economy_level`, `land_economy_warned`; `purchase_tile_land(..., standalone)`; `land_exempt` in `set_building_owner` |
| `scripts/company_rankings.gd` | `global_revenue()`; connects `turn_advanced` to `LandPrice.tick_economy` |
| `scripts/save_load.gd` | v17: start estate stamped `land_exempt`; `_migrate_v16_to_v17` |
| Readouts | tile panel land list ("Land price" block) and Buy Land confirm; construct row hover; rankings line; briefing dock rows (`land_prices` events); `Land price` map mode (`land_price_overlay.gd`); encyclopedia "Land prices" |

Readings of the spec:

- **Selling a building.** §4 makes the count live, so selling or demolishing a counted building lowers the
  next quote on its tile; §7 lists selling as never moving a price. The build follows §4. Buying a building
  back never raises one: it returns `land_exempt`.
- **Selling land.** `sell_tile_land` takes the sold units off `tile_land_priced` first; when none is left
  the stand-alone flag clears.
- **The economy level on an old save.** The migration stores -1, and the first read takes `doublings()` of the
  loaded standings, since the standings are not built until after import.
- **The forewarning** fires once per step: `land_economy_warned` remembers the doubling already warned of.
- **Band labels.** The rest band prints the ground Local Suppliers name: Countryside, Mountain or Sea.
- **The legacy tutorial's** Buy Land lesson is a stand-alone purchase like any other; its copy now quotes the
  live price.
- Decisions 6 (land under a building) and 7 (the planning limit) are unchanged, as their defaults say.

### Measured (balance protocol step 3)

| Prediction (§12) | Measured |
|---|---|
| First steel furnace land, Metal Magnate: £10 → £40 | £40, one patch (`_test_land_example_metal_magnate`) |
| Fresh furnace plot: £40 / £80 / £120 / £200 | per-patch quotes £20 / £40 / £60 / £100 by band (`_test_land_band_prices`); bands hold 27 / 31 / 34 / 303 land tiles as §3 says |
| Start soaks: profit unchanged | 50-turn `start_soak` for Metal Magnate and Glass Merchant identical to PR #204's head, field for field |
| Doublings at turns 35–50 and 70–90 | `tools/land_economy_probe.tscn`, seeds 1–3: first at 46–49, second at 81–83, then about every 35 turns (8 by turn 288, so +200% at the cap); a player at £150 a turn moves the first one about 2 turns earlier |

E2E (`tests/e2e_stoneshore.tscn -- 100`): 723 passed, 0 failed before and after. Post-tax profit unchanged
(-£4,613); the land bill is cash: after buildout £7,692 → £5,522, final cash £3,178 → £508. Unit suite: the
same 14 failures as PR #204's head, 48 new land checks passing. Sweep N/A (harness not built).
