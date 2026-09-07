# Recipe profitability benchmark

Run from the Godot project directory:

```sh
python3 tools/run_recipe_profitability.py --out reports/recipe_profitability/new-run
```

`--recipes r_009 r_012` limits a pilot to motors and chlor-alkali. Each case starts a
fresh headless Godot process. The output directory must be new: stale results cannot
be mistaken for successful runs. `--jobs N` supports independent workers after the
project has been imported; default 1 serializes Godot runs. Each case has separate
logs, runtime files and output JSON. No game saves are loaded.
`--collect --out <completed-run>` explicitly revalidates the recorded cases and
recreates exports without running the engine. It requires every requested case file.

## Scenario

- Stoneshore Docks, `tile_5_10`, using the actual HexMap CSV loader and starting
  infrastructure. No main scene, panels, decorative map bake or NPC building seeding.
- Zero other buildings, empty stockpile, no advisors, research, missions or loans.
- Default labour policy and wages, full production capacity, building level 1.
- £1,000,000 initial equity prevents financing or bankruptcy from censoring loss-making
  recipes. It is not sales or profit. There are no cash top-ups during the run.
- The real `BuildMode.attempt_direct_build` signal calls the same
  `world_map._on_build_attempted` handler as the construct panel, including land,
  density, material purchases, delivery and construction countdowns.
- Calling the handler bypasses only the recipe picker's research eligibility filter.
  Research is not granted, and automatic research definitions are cleared in the
  isolated fixture so no unlock-by-doing bonuses appear. Ordinary extraction penalties
  remain baseline rules. Decisions are disabled, so no event choices grant bonuses.
- All input sourcing uses the default automatic market pipeline. All outputs are
  routed to market. Both power priorities are set to grid, so generated power is sold
  and any power draw is bought. Seaport subscriptions are off, matching the default.
- Normal market price impact, labour growth, port charges, warehousing, taxes,
  dividends, shipment delays, capacity limits and production failures remain active.
  Repeated buying/selling behaviour is not changed or compensated for.

Mining includes mineral mining, oil extraction and recipes requiring a non-water deposit. Hidden catalogue recipes remain
hidden. A recipe with incompatible terrain, water or other site requirements is listed
as unavailable, never placed by overriding the tile. Cases that cannot begin production
stop after 60 turns and are reported separately from completed samples.

## Measures

The sample contains 10 consecutive resolved turns beginning with the first turn the
building actually produces. Later idle/starved turns stay in that window. Sales (SD)
is the arithmetic mean of actual goods and power sales. Profit (SD) is mean retained
cash change after operating costs, tax and dividends. This is a cash-flow measure,
not accrued accounting profit or the CostSolver's imputed margin.

Construction, land and initial inventory funding before the first run are excluded
from operating averages and recorded separately. Replenishment purchases and changes
in working inventory during the sample remain real cash costs. Ten turns do not prove
convergence: JSON also includes final-turn profit, the last-five-turn average, range,
running-turn count, remaining inventory and shipments.

The summary CSV has exactly `Building (Recipe)`, `Sales (SD)`, `Profit (SD)`.
Unavailable cases use `N/A`. `summary.json` carries IDs, reasons, detailed averages and
source hashes. Each `cases/<recipe>/result.json` contains every construction/running
turn, all empire line items, per-building reports, stock, shipments and transactions.

## Existing economics interfaces

These are in-process GDScript APIs, not HTTP endpoints:

| Interface | Scope |
| --- | --- |
| `Production.last_turn_summary` | Actual empire sales, purchases, labour, maintenance, power, transport, warehouse fees, tax, dividends, carbon, subsidies and financing charges. |
| `Production.turn_report_for(instance_id)` / `last_turn_reports()` | Consumed/produced quantities and allocated power, labour, maintenance, inbound transport and warehouse costs for buildings that ran. Not a complete building cash ledger. |
| `Production.carbon_tax_by_building` | Actual carbon charge attributed by building. |
| `CostSolver.get_building_output_cost(instance_id, good_id)` | Imputed unit production cost. It must not be presented as actual cash profit. |
| `TransportService.quote_market_buy` / `quote_market_sell` | Quotes before an order. Actual transport totals and breakdowns are in the production summary. |
| `MatchState.transaction_log` / `get_pending_transport_shipments()` | Market transaction and shipment detail. |
| `LoanState.export_state()` | Debt and repayment state. The legacy summary field `interest_paid` contains the full loan payment. |
| `Stockpile.export_state()` | Stock and warehouse state, including capacity observations. |
| `RunMetrics` | Existing whole-match CSV telemetry, disabled here to avoid redundant output. |

`scripts/economics_snapshot.gd` consolidates those read-only views. Call
`capture(cash_before, instance_id)` after `TurnManager.turn_resolution_completed`.
The caller captures cash immediately before `commit_turn()`. It returns independent
snapshots and an explicit difference between reported net and actual cash change.
In a multi-building empire, tax and dividend attribution is still empire-wide; this
helper does not fabricate per-building allocations. In the single-building benchmark,
all empire operating cash belongs to the tested recipe.

Every completed case checks 10 consecutive samples, finite values, cash-to-summary
and cash-to-component reconciliation, no advisors/tabs/loans/completed missions, and no acquired
modifiers. Baseline extraction penalties are retained. Do not alter these assumptions
silently when adding the later four-tiles-away road-only scenario; identify and record
the exact site, road levels, grid access and any impassable input routes.
