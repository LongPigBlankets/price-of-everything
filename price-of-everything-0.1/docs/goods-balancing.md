# Goods Balancing — Logic, Decisions, and Process

This document explains how goods/recipes in *Price of Everything* are balanced: the
design philosophy, the cost model, the levers, the gotchas, and the per-chain decisions
made so far. It is the reference for anyone touching `data/Goods - goodsMVP.csv`,
`data/recipes_all.csv`, or `data/Buildings - buildingsMVP.csv`.

> Balance constants are **data** (CLAUDE.md rule #7). This doc records *why* the numbers
> are what they are, so changes are deliberate rather than guesses.

---

## 1. The core pattern

Almost every good follows one rule:

> **Flat or mildly negative standalone. Profitable only once integrated.**

You should not be able to build a single factory, buy its inputs at market, sell its
output at market, and print money. You profit by **owning the chain** — the margin lives
in the upstream you no longer pay market price for. This keeps the economy from being
trivially solvable (the genre's classic failure mode).

Two exceptions sit on top of that rule:

- **Raw resources** are profitable standalone (you *extract* value rather than add it).
  They are governed by **deposit depletion** (−30% for common deposits and −15% for
  bauxite/sulphur at start) and **oversupply glut**
  (selling too much craters the price), not by thin margins.
- **Tech-gated recipes are rewards.** A recipe unlocked by research may be clearly
  profitable — that profit *is* the reward for the tech investment.

---

## 2. Tiers

| Tier | Standalone | Integrated | Examples |
|---|---|---|---|
| **Raw resource** | profitable | profitable | ore/coal mines, crude oil, refined REE, lithium carbonate |
| **Intermediate** | flat / mildly negative | +£15–40 | ingots, steel, copper wiring, ethylene, silicon, alumina, pvc, hydrogen, concrete |
| **Finished / apex** | flat (≈£0) | +£75 → +£1000 | motor, CPU, computer, ICE/EV car, heavy vehicle, batteries |
| **Gated (reward)** | flat → modestly + | ≥ its base recipe | Basic Oxygen Steel, Magnetic Separation REE, Automated Heavy Vehicles, EV Assembly |

The integrated figure scales with **chain depth** — an apex that embeds a deep chain
(CPU: silicon + circuit boards + REE) earns far more than a shallow one (motor: steel +
wiring).

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
