# Goods Balancing — Logic, Decisions, and Process

This document explains how goods/recipes in *Price of Everything* are balanced: the
design philosophy, the cost model, the levers, the gotchas, and the per-chain decisions
made so far. It is the reference for anyone touching `data/Goods - goodsMVP.csv`,
`data/recipes_all.csv`, or `data/Buildings - buildingsMVP.csv`.

> Balance constants are **data** (CLAUDE.md rule #7). This doc records *why* the numbers
> are what they are, so changes are deliberate rather than guesses.

---

## 1. The core pattern

> **Digging things up does not pay. Processing them does. Owning the chain pays most.**

The economy is built around one question: *why would you integrate?* The answer must never
be "because standalone production is arbitrarily crippled" — that reads as punishment. It
is instead that **not integrating costs you money you can see**, and **integrating lets you
keep profit you can also see**. Every incentive below is one of those two shapes.

### 1.1 Raw extraction does not pay at game start

Mining a raw good and selling it straight to market is **not** a viable standalone
business at game start. Two forces do that work, and neither is a thin margin:

- **Deposit penalties.** Common deposits start at **−30%** output, bauxite and sulphur at
  **−15%**. You extract less than the recipe nominally yields.
- **The cost of getting it to market.** Inland freight is charged per unit by weight class
  (plus a small share of value), so a heavy, low-value good pays far more of its value to
  move than a light, valuable one. Every market sale then pays the port charge, a share of
  the goods' value (see §1.5), and a raw good's margin is too thin to carry both.

To make extraction pay you must **internalise more of the cost** — feed the ore into your
own smelter instead of selling it, build next to the port, own the port (it halves the
charge), or research the nodes that cut it. That is the intended lesson of the opening turns.

> A raw-only position is a **bridge**, not a business: it converts a deposit into the cash
> and credit that fund your first real chain. Tests must never assert profit on it — see
> §1.4.

### 1.2 Processing pays modestly; integration multiplies it

A processed good is **mildly profitable standalone** — you can build one plant, buy inputs
at market, sell output at market, and make a little. That is deliberate: there is no wrong
first move, and no dead opening. But the same plant fed by upstream you own earns
substantially more, because owning the upstream deletes costs rather than adding bonuses.

### 1.3 The integration levers are costs avoided, not bonuses granted

Nearly every incentive to integrate is a **cost you stop paying**, which is why the design
holds together without special-casing:

| Lever | Cost if you *don't* integrate | Kept if you *do* |
|---|---|---|
| Market spread | You buy inputs at market price and sell output 5% under it | Internal transfers cross no spread |
| Port charge | Every market sale and purchase pays a share of the goods' value at the port | Internal moves never touch a port |
| Transport | Every market leg is hauled and charged | Co-located or short-hauled stages cost less |
| Deposit penalty | You sell reduced raw output at raw prices | You sell reduced raw output embedded in a finished good |
| Glut | Dumping one raw good craters its own price | Value spread across several outputs moves no single price far |

The port charge is **ad valorem** (§1.5): it scales with what actually moves, so it holds
its share of revenue as an empire grows and as prices fall.

**Tech-gated recipes are rewards.** A recipe unlocked by research may be clearly
profitable — that profit *is* the return on the tech investment.

### 1.4 What this means for tests

Profitability must be asserted **at least one level above raw** — iron ingots, steel,
motors — never on ore or coal alone. A test that asserts a mine-and-sell position breaks
even is asserting the opposite of this design, and will either fail or be quietly loosened
until it means nothing.

`e2e_stoneshore.gd` had exactly one such assertion (the coal runway, carrying a −£10
"port-fee tolerance" fitted to an observed −9.2). It now asserts revenue and solvency and
*prints* the profit figure instead. The correct assertions live in
`_check_economy_end_state()`: last-10-turn post-tax profit positive, cumulative post-tax
profit positive, and cash rising after buildout.


### 1.5 Port charges

Ports charge **ad valorem only** (`TransportState.preview_sea_shipping` / `commit_sea_shipping`,
rates in `EconomyConfig`):

- **What pays it:** every market sale (a building's output sold straight to market, surplus
  auto-sold from a stockpile, a manual sale) and every market purchase (inputs, construction
  materials). Moves between your own tiles and trades through the logistics intermediary
  pay none; the intermediary's fee covers its logistics.
- **The rate:** a share of the goods' value at the market **buy** price, for imports and
  exports alike: **0.5%** until turn 30, **3%** from turn 31 (`SEAPORT_AD_VALOREM_EARLY`,
  `_LATE`, `_STEP_TURN`). Under the Middleman ruleset it is 3% from the start; tutorial games
  keep 0.5% throughout.
- **Growth:** it rises 0.1% a turn, compounded from turn 1 (`SEAPORT_FEE_GROWTH_PER_TURN`).
- **Owning the port** halves it (`OWNED_SEAPORT_AD_VALOREM_SHARE`). Research modifiers
  (`port_ad_valorem_fee`) cut it further.
- **Capacity:** a port handles 1,500 units of a transport class a turn (300 for hazardous
  liquids, gases and ultra-heavy goods, `SEAPORT_THROUGHPUT_*`; `port_throughput` research
  raises it). A shipment that takes a port to its cap pays **double**, the whole shipment.
- **The flat per-good fee is retired:** `SEAPORT_BASE_FEE_PER_GOOD = 0.0`. It was charged once
  per good per turn, so quantity shipped was effectively free and freight collapsed as an
  empire grew. The mechanism is still there (once per good per port per turn, never at an
  owned port) and evaluates to zero.
- **Seaport subscriptions** (a subscribed good within `SEAPORT_RANGE_TILES`, 10, of the port)
  waive the inland freight between the port and the tile and make the trip one turn; the
  port charge is still paid.
- **Timing:** a sale pays its freight and port charge when it is dispatched; a purchase is
  quoted and paid when the goods arrive.

Reports call the charge `port_insurance` (and `port_inbound` for purchases' freight); it is
this charge, not an insurance bill on top of it.

---

## 2. Tiers

| Tier | Standalone | Integrated | Examples |
|---|---|---|---|
| **Raw resource** | **not viable** — deposit penalty + freight and the port charge | pays once embedded in your own chain | ore/coal mines, crude oil, refined REE, lithium carbonate |
| **Intermediate** | modestly profitable | materially better | ingots, steel, copper wiring, ethylene, silicon, alumina, pvc, hydrogen, concrete |
| **Finished / apex** | modestly profitable | far better | motor, CPU, computer, ICE/EV car, heavy vehicle, batteries |
| **Gated (reward)** | ≥ its base recipe | ≥ its base recipe | Basic Oxygen Steel, Magnetic Separation REE, Automated Heavy Vehicles, EV Assembly |

The integrated figure scales with **chain depth** — an apex that embeds a deep chain
(CPU: silicon + circuit boards + REE) earns far more than a shallow one (motor: steel +
wiring).

> **On numbers in this table.** Earlier revisions quoted per-recipe £/turn figures here.
> They are omitted deliberately: they were design-model outputs from
> `tools/band_breakdown.py`, which does not net the port charge, so they read
> higher than a real position earns. Treat `reports/balance/band_breakdown.csv` as a
> *relative* instrument — is this recipe in band, is the integrated pair ahead of the
> standalone — rather than as a promise of a specific number. Quote it in balance
> discussions, not in player-facing or marketing copy.

---

## 3. The cost model

A recipe's per-turn running cost = **labour + maintenance + energy + transport**.

- **Labour** = `pct × build_material_value`, where `pct` is solved to break the *lone*
  building even (single ≈ 0), clamped to **5–25%**. `build_material_value` is the
  building's build-kit valued at current market prices.
- **Maintenance** = `5% × build_material_value`.
- **Energy** = `energy_req × power_price`. Power costs **£0.10** bought from the grid.
  Existing self-generated power has a **£0.06 minimum opportunity cost** because that is
  the grid sale forgone by consuming it internally. Source comparisons also report actual
  operating cost and a 36-turn levelized investment cost: coal, oil, and onshore wind with
  lithium-cell battery firming are not collapsed into one universal "own power" number.
- **Exempt goods** skip the break-even solve and take a flat 5% labour, so they read as
  *profitable resources*: power, mining, `processed_oil`, `refined_ree`,
  `lithium_carbonate`.

Because labour is a **% of the building's build cost**, an expensive building (the
£980 assembly plant) carries heavy labour — which is why apex goods made there are hard
to run profitably alone, and why the build-material loop (§6) is dangerous.

---

## 4. The integration-gain mechanic (the key insight)

For any recipe:

```
single = revenue − market_inputs − energy(grid)  − run_cost     # standalone
full   = revenue − own_inputs    − energy(opportunity) − run_cost # integrated

full − single = (market_inputs − own_inputs) + energy × (grid − own)
              = the INTEGRATION GAIN
```

The old diagnostic selected the cheapest power recipe anywhere in the tech tree and applied
its technical production cost to every chain. That understated electricity at roughly £0.0064.
The repaired model floors internal power at the £0.06 export opportunity and keeps generator
operating/investment scenarios separate.

The gain is **independent of the output price** — raising the price lifts `single` and
`full` by the same amount. So:

> To make a good a bigger apex (higher integrated) **without** making it profitable
> standalone, you **widen the gain**, not raise the price.

The gain comes from (a) owning inputs that carry a big market-vs-own markup, and
(b) self-supplying energy. This is why energy-intensive goods (hydrogen, lithium
electrolysis) have the most integrated upside.

---

## 5. The levers

1. **Recipe depth** — embed more/ richer inputs. The motor was deepened (15 steel + 12
   wiring → 30 + 24) and the CPU (circuit boards 2 → 12 + REE) to widen the gain while
   standalone stayed flat.
2. **Output yield / batch scaling** — scale the whole recipe (inputs *and* output). This
   dilutes the **fixed** building cost, raising per-run profit **without touching the
   price**. The computer went 2 → 9 cells/run; Heavy Vehicles Automated is literally a
   bigger batch (its "automation" reward).
3. **Price** — sets where `single` lands (the harness flattens it via labour%). **Held
   constant for build materials** (§6).
4. **Energy intensity** — high `energy_req` → large own-power gain → very negative
   standalone, healthy integrated. Used to make hydrogen and lithium electrolysis
   "barely profitable alone, profitable with your own power."
5. **Exemption** — flag a good as a profitable resource (REE, lithium carbonate) so the
   harness stops flattening it.

A note on "efficiency": in this model, a *more efficient* recipe (fewer inputs, less
energy) often has a **smaller** integration gain — less to own, less power to save. So
the reward for a gated "efficient" recipe usually has to come from **yield/throughput**,
not input-thrift (this bit us on Basic Oxygen Steel, membraneless hydrogen, and the
automated heavy vehicle).

---

## 6. The build-material feedback loop (critical gotcha)

Several goods are **build materials** — they appear in building build-kits:

| good | in build kits |
|---|---|
| concrete | 25 buildings |
| rubber, plastics | ~25 each |
| building_frame | industrial_factory, furnace, assembly_plant |
| electrical_components | 6 buildings |
| **computer** | assembly_plant ×4, high_tech_manufactory ×6 |

Raising a build material's **market price** inflates the construction cost of every
building that uses it → its labour/maintenance → and crushes the margins of every recipe
made there — **including the recipe that produces that good** (a circular trap).

> **Confirmed:** the £980 assembly-plant build cost is **£600 of computers**. Pushing the
> computer to £520 drove the CPU from −£21 to **−£169** standalone.

**Rule: never raise a build-material's price to make it more profitable.** Improve it via
**recipe yield/depth at a held price.** The computer became the top apex (+£537) via
*volume* at a held £150; concrete was flattened via yield at a held £4.5.

---

## 7. Per-chain decisions

| Chain | Decision |
|---|---|
| **Mines / raw** | Profitable standalone; −30% common-deposit / −15% bauxite-and-sulphur start + glut governance. Each +15% recovery node restores one step. Coal remains cheap and abundant. |
| **Ingots → steel / wiring → motor** | Break-even ladder: each step flat-single; motor deepened so integrated ≥ +£75. |
| **Petrochemical (crude→processed→ethylene→rubber/plastics)** | Crude/processed profitable (deposit+glut); ethylene/rubber/plastics flat-single, profitable integrated. Build-kit quantities trimmed to dampen the loop. |
| **ICE car (engine/body/tyres → car)** | Car flattened (£260→£174): single ≈ 0, integrated +£340. |
| **Glass / silicon** | Break-even intermediates feeding cars + electronics. |
| **CPU (the apex chip)** | Deepened with circuit boards + REE → single −£21, integrated +£425. Tough semiconductor start, huge integrated. |
| **Computer (top apex)** | Held £150 (build-material loop), made apex via **volume** (9/run, 4 embedded CPUs) → +£537. |
| **Solar panel / building frame** | Deepened to ~+£100 integrated, flat single, prices held (both feed downstream/build kits). |
| **REE** | Valuable resource (exempt). Base reduction inefficient; gated Magnetic Separation Electrolysis = the efficient reward. |
| **Lithium** | Valuable resource like REE. **Split refining:** crude *Rudimentary Refinement* (very negative standalone, barely integrated) vs gated *Lithium Electrolysis* (barely-profitable standalone, +£105 integrated). Ore priced up to carry the gain. |
| **Batteries** | Conventional lithium-ion is deliberately loss-making standalone (−£25.88), while researched LFP is profitable (+£42.29) and yields 8 cells from 8 lithium carbonate. Installed cell capital for 1,000 storage falls lithium £450 > sodium £360 > iron-air £300 (18×£25, 24×£15, 60×£5). |
| **EVs / heavy vehicles** | Base flat standalone; gated variants reward via throughput (Automated = bigger batch) or embedded value (Electric/EV own batteries + CPUs). |
| **Steel / aluminium / windows** | Flat-single intermediates; gated Basic Oxygen beats base steel via yield; uPVC kept the better window recipe over aluminium. |
| **PVC / hydrogen / chlor-alkali** | Negative standalone, profitable integrated. Hydrogen deliberately marginal (multiple routes); membraneless = the yield boost. PVC fixed via yield (was underwater). |
| **Concrete** | Flat standalone, ~+£40 integrated; price held (25 build kits). Clean electric route edges the coal-fired one. |
| **Power** | The **integration lever** — cheap to self-supply, so the whole economy benefits. Ladder: gas (120, best) > coal (100) > wind (80) > solar (70). Gated renewables catch gas once unlocked. Per-tile wind/solar **potential** (60–90% / 50–80%) is the multiplier on top. *Pending: grid oversupply glut + the tile-potential multiplier are sim changes, not recipe numbers; carbon tax (coal + crude oil) deferred.* |

---

## 8. Verification

- **`tools/chain_profit.gd`** — the balancing harness. Reads the live CSVs and prints,
  per recipe: `single` (standalone), `full` (integrated), break-even price, mines at the
  live deposit penalties, and chain totals. **This is the primary tool — iterate here.**
  Run: `<godot> --headless --path . res://tools/chain_profit.tscn --quit-after 200`.
- **`tests/e2e_stoneshore.gd`** — full headless playthrough; its `balance_v4` mode uses
  live land purchase, construction, loans, deposits, transport maintenance, owned power,
  production and market sales. Run `python3 -B tools/run_balance_v4_e2e.py` for the
  150-turn, 10-recipe portfolio benchmark and consolidated report.
- **`data/balance_v4_changes.json`** and **`tools/manage_balance_v4_data.py`** — exact
  field-level old/new runtime values plus safe `--status`, `--revert` and `--apply`
  commands. See `docs/balance-v4-playtest.md` for the manual motor strategy and expected
  checkpoints.
- **`tools/run_tests.py`** — ~860 unit asserts (mechanical correctness).

---

## 9. The decision-making loop

1. **Investigate** — the recipe(s), prices, downstream consumers, build-material usage
   (does raising the price ripple?), and gated variants.
2. **Set targets** — the tier pattern (§2) plus the specific design goal.
3. **Tune in the harness** — pick the lever (§5): depth, yield/volume, price, energy.
   Read `single` and `full`.
4. **Verify** — no build-material ripple (§6), downstream consumers undisturbed, the
   ordering correct (e.g., gated ≥ base, gas > coal > wind > solar).
5. **Iterate** — the harness is fast; converge on the targets, then re-check the
   neighbours that share inputs or buildings.
