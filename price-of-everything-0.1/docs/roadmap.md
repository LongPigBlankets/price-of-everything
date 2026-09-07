# Roadmap — post-demo

Written 2026-09-07, after the itch demo build. This is the post-demo layer; it sits above
`demo-roadmap-2026-08-23.md` (shipped) and beside `long-term-roadmap.md` (engineering debt) and
`feature-plans.md`. Four items. Each has what exists today, the design in one breath, what it
depends on, a size, and the evidence that should gate it. Nothing here is committed to a date.

Sequence as written: pollution → recycling → middleman logistics, because recycling's supply
side (landfill, city hubs) is where pollution's outputs go, and the middleman's distance-to-
population term is the same "city rank" concept recycling's hubs need. The goods decision (item
4) is orthogonal and can land before or after any of them.

---

## 1. Pollution — a second spatial layer

**Intent.** The carbon levy prices carbon wherever it burns; it is global. Pollution makes
*where you build* matter: a smelter cluster fouls its own valley, spills into the tiles around
it and pushes out the clean industry that lived there. The player gets a zoning problem on a map
that today only has port distance and deposits as spatial pressure.

**What exists.** `pollution-spec.md` (2026-07-19), designed and not built: per-tile air and
water pools, per-recipe emission, slow decay, overflow spill to neighbours, recipe blocking with
hysteresis, scrubbing as a cost. Its recipe-blocking touches the turn pipeline, which is why it
was cut from the demo. The recipe CSVs already carry a `pollution` column.

**Phase A — simple pollution.** Two channels (air, water), one number each per tile, emission
per recipe run from the CSV column, decay, spill above a threshold, a mapmode, and one
consequence: output malus on the tile above a band, scrub building or filter research to
remove it. No named pollutants. Ship the legibility surface with it (tile panel readout,
mapmode, construct-dialog warning) or it is a debug print.

**Phase B — named pollutants.** Red mud (alumina and Bayer-process routes), CO2 as a stock that
the levy can later read, sour water (refinery routes), broken glass (glass and window
manufacturing), slag and coal ash. Each is a *good* with a transport class so it can be moved,
stored, landfilled or recycled — which is the bridge into item 2. The generic pools stay as
the aggregate the player reads; the named pollutants are what they can do something about.

**Depends on.** Nothing new. Pipeline discipline (`cnc-turn-pipeline-reference`): the pool
tick and the blocking check go in fixed sub-phases and are covered by the e2e harness before
any UI. Save schema bump with migration.

**Size.** Phase A two to three weeks including harness sweeps; Phase B one week per two
pollutants once the goods pipeline (icons, prices, classes) is routine.

**Evidence gate.** Demo telemetry and comments showing players build clusters (co-location is
already the winning move, so they will): pollution only earns its complexity if clusters are
common. Balance gate: a sweep where the pollution-aware layout beats the naive one by 10–20%
profit at turn 100, not more (the mechanic should nudge layout, not dominate it).

---

## 2. Recycling — an alternative to extraction, with a supply problem

**Intent.** Offer a second way to source metals, plastics and glass that does not depend on
deposits, priced so it competes with mining only once volumes and the levy make virgin routes
expensive. It is the natural partner of pollution: the named pollutants and end-of-life goods
are its feedstock.

**What exists.** The good half: scrap, e-waste and bio-waste are goods; recycling plant,
landfill, water recycling and heat battery are buildings with **zero recipes**; aluminium
recycling, lithium recycling and e-waste recycling recipes exist in the file but are dropped
because municipal waste, battery waste and their outputs are missing from the goods CSV. Nothing
produces scrap, e-waste or bio-waste today.

**Design.** Two sources for feedstock, both new:
- **Landfill** as a building that *accumulates* waste goods from the player's own operations
  (Phase B pollutants, packaging from finished-goods recipes, end-of-life fraction of vehicles
  and appliances sold) and can be mined later — a stock the player builds up, which turns
  today's dead-end sell-only apexes into part of a loop without violating their sell-only
  status (the return flow is a fraction, not a consumer recipe).
- **City hubs** as a service: a settlement of rank N supplies M units of municipal waste,
  scrap and e-waste per turn to a collection building within range, priced by a **city
  rank**. City rank is the same settlement-size table the middleman's distance term needs
  (item 3), so define it once: a per-settlement size from `cities.json` / `tile_properties`
  road density, three or four bands.

Recipes: revive the dropped aluminium, lithium and e-waste recycling routes by adding municipal
waste and battery waste as goods; add scrap → electric-arc steel (the green steel route the
chain lacks) and glass cullet → glass. Recycled routes carry low carbon multipliers so they are
the levy's escape valves.

**Depends on.** City rank (shared with item 3). The Phase B pollutants for the full loop, but
the city-hub supply works without them. Goods pipeline for four to six new goods and icons.

**Size.** Two weeks for city rank + hubs + revived recipes; landfill accumulation another week.

**Evidence gate.** From the demo: do players run out of deposits or hit deficit premiums on
ore? If ore never binds, recycling's price has nothing to compete against and should wait for
the levy phases that make virgin routes dear.

---

## 3. Middleman logistics — buy delivered, sell ex-works, then grow out of it

**Intent.** Remove the buffer-and-cash wall that hits any site more than a tile or two from a
port, and turn transport into a progression: distributor (easy, dear) → direct-to-port (cheap,
you manage transit and cash lag) → own fleet (a sink for vehicles).

**What exists.** Market buys are paid now and ship from the nearest port at two tiles per
turn; sales are priced on departure and paid on arrival; stockpiles pay a two-part warehousing
tariff; the seaport range is ten tiles so reach is not the problem, time and settlement are.
Three mechanisms already work on this wall — port coverage, the Just-in-Time unlock, the
warehousing fee — so the distributor must be the *default early mode* that the existing
direct-to-port research (`Sell Through Ports`) replaces, not a fourth option beside them.

**Design.**
- **Distributor mode (default from turn 1):** inputs arrive at the building the turn they are
  bought, sales settle the same turn at the building. Tariff = weight-class flat + ad valorem
  (the port fee's shape) × a **distance-to-population multiplier**: inside a city tile ~1.5×,
  within one tile of a town ~2×, two tiles ~3×, further ~5×. Steep on purpose: direct-to-port
  must win clearly at volume or the transit system becomes decorative and the game loses its
  main tension. Distributor volume still counts toward price impact (no impact dodge).
- **Direct-to-port (unlock by doing, the existing node):** today's model — you pay freight and
  the port fee, wait for transit, and carry the cash lag. The construct dialog's runway line
  shows both figures so the trade is legible before building.
- **Own fleet (later):** capacity in units per turn bought as money, with the player's own
  heavy vehicles convertible into capacity at a premium. Keeps apex goods sell-only for
  scoring while making vehicle production a sink. Turning vehicles into a consumed input
  instead would change the "apex goods are sell-only" stance and needs an explicit ruling.
- **Legibility:** one readout on the transport panel (mode, tariff, break-even volume), one
  on the construct dialog (runway under each mode), one mapmode (distribution cost by tile).

**Depends on.** City rank (item 2). A check that the existing freight-credit path does not
overlap the tariff. New saved state for mode and fleet.

**Size.** Two to three weeks; the harness work first.

**Evidence gate.** Prototype in the balance harness before UI: the same site at one, three and
six tiles from a port, with and without the distributor; compare first-sale turn, solvency
floor and profit at turn 100. If the six-tile site is not solvent with it, or is not clearly
better without it once integrated, the tariff is wrong. Demo telemetry on how many players
build beyond two tiles from a port tells you how much this is worth.

---

## 4. Goods before the Steam demo, or after Early Access?

Candidates: phosphates, methane, lubricants, three alloys (lightweight, conductive, durable)
plus carbide. The question is not "are they good" — they are — but whether each is worth the
balance risk before a Steam demo, where first impressions of stability matter more than depth.

Decision rule: add before the Steam demo only if the good (a) revives dropped recipes or fixes
a chain that is currently wrong, (b) does not reshape the mid-game graph, (c) passes the e2e
sweep with the two demo starts unchanged in profit at turn 100 by more than ±5%, and (d) has
its icon. Anything that fails (b) waits for Early Access.

| Good | What it does | Rule (a)–(b) | Recommendation |
|---|---|---|---|
| **Methane** (+ gas power, the oil fractions it comes with) | Revives 18 dropped recipes; gives power a fuel between coal and renewables; blue hydrogen | (a) yes, (b) yes | **Before the Steam demo.** The most on-theme gap in the file. |
| **Phosphates** (+ potash) | Makes fertiliser an honest NPK recipe; LFP batteries stop using chemical salts as a stand-in; one new deposit type | (a) yes, (b) yes | **Before the Steam demo.** Small, clean, no graph reshaping. |
| **Lubricants** | A processed-oil derivative for engines and motors | (a) no — processed oil already plays this role in every engine recipe, (b) yes | **After EA**, or fold into the oil-fraction bundle as a rename of processed oil's engine use. Adds a good, not a decision. |
| **Three alloys + carbide** | Splits the generic alloy bus into four junction goods across the copper, aluminium/lithium, rare-earth and silicon chains; twelve consumer recipes re-pointed | (a) partly, (b) **no** | **After EA.** This reshapes the mid-game graph, retunes the Tiers track, and needs four icons and a full sweep. Carbide alone could go earlier: it has ready consumers and a strong levy story. |

Recommended split: methane and phosphates before the Steam demo, carbide if the sweep is
clean, lubricants folded away, the alloy split as the first EA content update where it can be
announced as depth rather than risked as churn.

---

## Not on this roadmap, on purpose

Era 2 market-disruption events and era 3 public goods (see the July era plan) are the campaign's
spine and belong to the EA roadmap. Cement, green steel by hydrogen and battery metals are
content that lands naturally with items 1–2 and the alloy split; they are noted in the goods
analysis and not scheduled here.
