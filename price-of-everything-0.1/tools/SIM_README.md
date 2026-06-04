# Headless Economy Sim — `sim_profitable_run.gd`

A headless, compute-only simulation that builds and runs **one supply chain** end-to-end
under the live game rules (deposits, land caps, transport, loans) and reports how fast it
reaches profit/equity milestones. Use it to balance recipes, prices and transport without
clicking through turns in the editor.

> **For AI agents:** everything you need to run, read, and tune the sim is in this file.
> The sim is deterministic — same data + same chain ⇒ same result. After changing any
> CSV in `data/` or constant below, just re-run the command and compare the report.

---

## How to run

```
<godot-binary> --headless --path . --script res://tools/sim_profitable_run.gd -- <chain>
```

- `<godot-binary>` is the Godot 4.6 console executable (e.g. `Godot_v4.6.2-stable_win64_console.exe`).
- `--path .` must point at the project root (the folder with `project.godot`).
- Everything after the `--` is passed to the sim; the first token is the **chain name**.

Run all seven and grab the report lines (PowerShell):

```powershell
$g = "<godot-binary>"
foreach ($c in @("motors","concrete","electrical","upvc_windows","aluminium_windows","building_frame","plastics")) {
  & $g --headless --path . --script res://tools/sim_profitable_run.gd -- $c 2>&1 |
    Select-String -Pattern "REPORT:|steady net|profit@|equity@|tiles=" | Select-Object -Last 6
}
```

Run the test suite (should stay green after data/engine edits):

```
<godot-binary> --headless --path . res://tests/test_runner.tscn --quit-after 600
```

### Available chains

| Chain | Sells (product) | Notes |
|---|---|---|
| `motors` | Motors (g_008) | copper + iron + coal → motor |
| `concrete` | Concrete (g_017) | EAF-only; a **loss-leader** (concrete is a construction input, not meant to sell at a profit) |
| `electrical` | Electrical Components (g_036) | copper + salt + **self-made plastics** (co-located oil train) |
| `upvc_windows` | Windows (g_039) | full **chlor-alkali** chain (builds its own NaOH); buys PVC |
| `aluminium_windows` | Windows (g_039) | **imports NaOH** instead of building chlor-alkali; buys aluminium |
| `building_frame` | Building Frame (g_023) | makes its own windows in-chain |
| `plastics` | Plastics (g_027) | shale → refining → ethylene → plastics, all co-located |

---

## Reading the report

```
==== REPORT: <chain> ====
chains=N tiles=M  seed/last_cost=C  stopped=T          # chains built, land tiles owned, last chain cost, marginal-stop turn
build=.. land=.. road=.. rail=.. pipe=.. borrowed=.. wc_debt=.. debt_end=..
out_of_red=..  2nd_chain=..  transport/turn=..  product_lifetime=..
steady net/turn=+X  equity_slope=+Y  final_equity=Z  profitable=YES/NO
profit@/turn: 100=.. 500=.. 1000=..                    # first turn rolling net hit each £/turn threshold
equity@: 500=.. 1000=.. 2500=.. 5000=.. 10000=..       # first turn equity hit each £ threshold
tiles=.. 80pct-cap_tiles=.. transit-cap_tiles=.. (max outflow=../turn vs road200/rail400)  marginal0@turn=..
power_station=built@turn .. (coal-fired | processed_oil-fired)
```

Key fields:
- **steady net/turn** — average operating profit over the last 20 turns (the headline "is it profitable").
- **equity_slope** — change in net worth/turn over the last 20 turns. `profitable=YES` requires steady net **and** equity slope positive.
- **out_of_red** — first turn operating cash flow turned positive.
- **profit@ / equity@** — milestone turns (`-` = never reached).
- **tiles / 80pct-cap_tiles** — tiles built on / tiles at ≥80 % of the 200-land cap (densified).
- **transit-cap_tiles (max outflow)** — tiles whose per-turn off-tile shipping ≥ the 200/turn road cap (the cap is **not enforced** yet — this just flags where it would bind).
- **marginal0@turn** — the turn the last expansion's marginal profit went negative and the sim stopped adding chains.

---

## The levers

### A. Sim constants — `tools/sim_profitable_run.gd` (top of file)

| Constant | Default | Meaning |
|---|---|---|
| `TURNS` | 300 | turns simulated |
| `STARTING_CASH` | 300 | starting money (seed is then financed) |
| `MAX_CHAINS` | 12 | hard cap on replicated chains |
| `PROFIT_MILESTONES` | 100, 500, 1000 | £/turn rolling-net milestones tracked |
| `EQUITY_MILESTONES` | 500…10000 | £ equity milestones tracked |
| `PORT` | `tile_5_10` | reference port (Stoneshore) used to sort tiles by distance |
| `MAX_TILE_LAND` | 200 | hard per-tile build cap |
| `FREE_LAND` / `LAND_PATCH` / `LAND_PATCH_COST` | 100 / 10 / 10 | free land per tile, then £10 per 10-land patch |
| `DENSITY_SOFT_CAP` | 100 | above this, buildings cost 1.5× (density premium) |
| `RAMP_TURNS` | 10 | turns to wait after an expansion before judging its marginal profit |
| `WC_FLOOR` | 400 | per-turn working-capital floor (see "Divergences") |

**Chain definitions** are the `CH_*` constant arrays. A chain is a list of **branches**;
each branch is co-located on one tile and ships its `export_good` to another branch
(`export_to` = role) or to `MARKET`. Branch dict format:

```
{"role": "X", "deposit": "<deposit or ''>", "builds": [[building_id, recipe_id, count], ...],
 "export_good": "g_0NN", "export_to": "<role|MARKET>", "buy": ["g_0NN", ...]}
```

- `deposit != ""` → the branch may only sit on a tile carrying that deposit (mines/wells/pumps).
- inputs are produced in-chain (tile-only) **unless** listed in `buy` (then bought from the market).
- corridors are auto-built: **rail** for solids, **pipes** for liquids/gas (reinforced for
  hazardous), land-only, costed per the rates below.

### B. Economy constants — `scripts/economy_config.gd`

| Lever | Default | Meaning |
|---|---|---|
| `STARTING_MONEY` | 200 | the *game's* starting money (sim overrides with its own `STARTING_CASH`) |
| `MAINTENANCE_PER_BUILDING` / `MAINTENANCE_MULTIPLIER`* | 1.0 / 2.0 | per-building upkeep |
| `LABOUR_*_RATE` / `LABOUR_*_GROWTH` | see file | wage rates + per-turn wage inflation |
| `TRANSPORT_COST_PER_UNIT_PER_TURN_BY_WEIGHT_CLASS` | 0.02 std / 0.03 solid-heavy & liquids / 0.06 ultra-heavy | per-unit-per-turn land transport |
| `TRANSPORT_MODE_COST_MULT` | rail 0.5, roads/pipes 1.0 | per-mode multiplier on the class rate |
| `SEAPORT_SUBSCRIPTION_COST_PER_GOOD` | 1.0 | flat £/turn per subscribed good (port shipping) |
| `SEAPORT_RANGE_TILES` | 10 | a port only services tiles within this range |
| `GRID_BUY_PRICE` / `GRID_SELL_PRICE` | 1.0 / 0.6 | power bought from / sold to the grid |
| `LOAN_BASE_CAPACITY` / `LOAN_TERM_TURNS` / `LOAN_INTEREST_RATE` | 50 / 36 / 0.10 | loan terms |
| `TAX_RATE` / `DIVIDEND_RATE` | 0.20 / 0.20 | tax & dividends |

(*`MAINTENANCE_MULTIPLIER` lives in `scripts/catalog.gd`.)

### C. Data tables — `data/`

- `Goods - goodsMVP.csv` — prices (`base_price`), transport class, buyable/sellable.
- `recipes_all.csv` — inputs/outputs/energy per recipe (`recipe_id, building_id, input_1..6/qty, energy_req, output_1..5/qty, requirements, …`). `deposit:X` in the requirements column gates extraction.
- `Buildings - buildingsMVP.csv` — build cost, tile size, maintenance, labour.
- `infrastructure.csv` — roads/rail/pipe ranges and tolerated goods classes; pipes carry liquids/gas (reinforced adds hazardous), rail/roads carry solids.
- `tile_properties.csv` — tile type, deposits (pipe-separated, `name(amount)` for finite), river flag.
- `ports.csv` — seaport tiles (Stoneshore `tile_5_10` W, Arin `tile_11_17` S, Capital `tile_24_7` E, Vandel `tile_22_16` E).

---

## How the sim behaves (the rules it follows)

1. **Seed** one chain, financing the build cost; then each turn:
2. **Finance** — borrow against capacity when negative, plus top up to `WC_FLOOR` working capital.
3. **Build a power station once profitable** — one self-supply plant (coal-fired; `processed_oil`-fired for `plastics`), co-located with its fuel/water so power flows to the shared grid.
4. **Expand** — when *real* cash (money minus the working-capital loan) exceeds the last chain's cost, build another chain; then wait `RAMP_TURNS` and **judge** its marginal profit. If marginal profit is negative, record `marginal0` and stop expanding (but keep running to `TURNS`).
5. **Place** branches on deposit-valid tiles nearest the port, respecting the 200-land cap (buying land patches and paying the density premium past 100), and auto-build road/rail/pipe corridors.

---

## Where the sim DIVERGES from human game rules

These shortcuts make the sim a clean economic probe. In the actual game a human is more constrained / more flexible:

| Area | Sim | Human game |
|---|---|---|
| **Seaport subscriptions** | Auto-subscribes **every** traded good from turn 1 (`MatchState.seaport_auto_subscribe = true`) | Player toggles subscriptions per good |
| **Working capital** | Per-turn floor of `WC_FLOOR` injected as *construction debt* (equity-neutral) so import chains can fund their first purchases | Only real, capacity-limited loans; no automatic working-capital line |
| **Build gating** | Restricts mines/wells/pumps to correct **deposits**, but bypasses other build-time terrain/adjacency checks | Full `world_map._tile_meets_build_req` checks (terrain, adjacency, deposits) |
| **Power/cables** | Every built tile is auto-cabled, so grid power is always available | Player must lay cables and connect the grid |
| **Layout & expansion** | Auto-places optimal co-located branches and auto-expands until marginal profit ≤ 0 | Player chooses every placement and when to expand |
| **Transit caps** | Reports where the 200/400 road/rail cap *would* bind but does **not** enforce it | (also currently unenforced in-game; flagged for future) |
| **UI flows** | Skips dialogs (e.g. the capacity-full modal); auto-enables "sell surplus" on each tile | Player resolves these interactively |
| **Starting cash** | `STARTING_CASH` = 300 (sim-only), seed financed immediately | `EconomyConfig.STARTING_MONEY` = 200 |

When tuning **game** balance from sim results, remember the sim assumes near-frictionless
logistics (auto co-location, auto subscriptions, auto working capital). Treat its
profit/turn figures as an **upper bound** a skilled player approaches, not a guarantee.

---

## Companion tool

`tools/bake_good_icons.gd` — one-time cleaner for goods icons: flood-fills the magenta
chroma-key background transparent, strips watermarks, trims, and emits a `medium` master +
`small` variant. Idempotent (skips already-clean icons). Run after dropping a raw icon into
`assets/icons/goods/medium/` named `g_0NN_<internal_name>.png`, then run `--import`.
