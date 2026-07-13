# Recipe rebalance baseline

- Active recipes: 137 of 200 CSV rows
- Internal-power short-run opportunity cost: 0.0600 (foregone grid sale)
- Grid purchase price: 0.1000
- Power investment horizon: 36 turns
- One-turn route assumption: rail for solids, pipe for liquids/gases, roads otherwise
- Maintenance is charged once, matching the live production loop
- Standalone target metric: pre-tax cash after one-turn market freight and a one-turn working-inventory warehouse reserve
- Static deployed recipe economics in target band: 99
- Structural +400 reviews: 3

## Power opportunity-cost scenarios

Short-run cost includes operating cash and the export forgone by internal use. Long-run cost also levelizes generator, battery-housing and locked-cell investment over the stated horizon.

| Scenario | Operating £/power | Levelized £/power | Short-run opportunity | Long-run opportunity |
|---|---:|---:|---:|---:|
| grid purchase | 0.1000 | 0.1000 | 0.1000 | 0.1000 |
| foregone grid sale | 0.0600 | 0.0600 | 0.0600 | 0.0600 |
| coal power | 0.0447 | 0.0500 | 0.0600 | 0.0600 |
| oil power | 0.0450 | 0.0511 | 0.0600 | 0.0600 |
| onshore wind + lithium battery | 0.0584 | 0.1038 | 0.0600 | 0.1038 |

| Recipe | Input integrated | Fully integrated | Reduce to cap by |
|---|---:|---:|---:|
| Electric Heavy Vehicles Manufacturing | 404.0 | 443.8 | 43.8 |
| Heavy Vehicles Automated Manufacturing | 396.2 | 438.3 | 38.3 |
| Heavy Vehicles Assembly | 361.2 | 403.3 | 3.3 |

`deployed_recipe_economics.csv` is the authoritative standalone view: deployed labour and output, one-turn market freight, working-inventory warehouse reserve, tax and dividends. Fields labelled `diagnostic` or `proxy` in `recipe_rebalance_baseline.csv` are not cashflow predictions.
See `integer_one_layer_chains.csv` for selected whole-building chains, including actual deployed labour, supplier surplus, freight, warehousing, tax and dividends.
