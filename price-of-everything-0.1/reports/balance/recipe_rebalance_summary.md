# Recipe rebalance baseline

- Active recipes: 137 of 200 CSV rows
- Own-power unit cost: 0.0064
- One-turn route assumption: rail for solids, pipe for liquids/gases, roads otherwise
- Maintenance is charged once, matching the live production loop
- Standalone target metric: pre-tax cash after one-turn market freight and a one-turn working-inventory warehouse reserve
- Static deployed recipe economics in target band: 102
- Structural +400 reviews: 3

| Recipe | Input integrated | Fully integrated | Reduce to cap by |
|---|---:|---:|---:|
| Heavy Vehicles Automated Manufacturing | 366.9 | 477.1 | 77.1 |
| Electric Heavy Vehicles Manufacturing | 367.6 | 474.4 | 74.4 |
| Heavy Vehicles Assembly | 331.9 | 442.1 | 42.1 |

`deployed_recipe_economics.csv` is the authoritative standalone view: deployed labour and output, one-turn market freight, working-inventory warehouse reserve, tax and dividends. Fields labelled `diagnostic` or `proxy` in `recipe_rebalance_baseline.csv` are not cashflow predictions.
See `integer_one_layer_chains.csv` for selected whole-building chains, including actual deployed labour, supplier surplus, freight, warehousing, tax and dividends.
