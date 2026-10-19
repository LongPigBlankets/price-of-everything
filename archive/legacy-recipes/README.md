# Retired recipe generations

Archived 19 October 2026. The active game reads the maintained
[`recipes_all.csv`](../../price-of-everything-0.1/data/recipes_all.csv).
Follow [content authoring](../../price-of-everything-0.1/docs/content-authoring.md).

| Material | Reason |
|---|---|
| `scripts/build_recipes_all.py.txt` | June bootstrap: renumbers stable IDs, removes hand-authored recipes/columns and resets quantities. Preserved as non-tool source evidence. |
| `scripts/rebalance_recipes.py.txt` | Historical fixed-cost/energy/price proposal generator; assumptions no longer describe the current economy. Preserved for research. |
| `data/recipes_master_source.csv` | Earlier generation consumed by the retired bootstrap; conflicts with maintained IDs and schema. |
| `data/goods.csv`, `data/recipes.csv`, `data/recipesMVP.csv` | Older Godot-project CSV exports with no current runtime/tool consumers. Root Python prototype data stays at root `data/`. |
| `data/recipes_rebalanced.csv`, `data/good_prices_rebalanced.csv` | Historical proposal outputs, never authoritative runtime inputs. |
| `docs/recipe-rebalance-spec.md`, `docs/recipe-rebalance-table.md` | Historical method/proposal and report; links relocated, numeric content retained. |

Original Python and CSV bytes are retained. The old script paths contain refusal
messages; the destructive override no longer runs there. Godot's obsolete generated
translation/import companions were removed rather than copied here; the archive
manifest records their source hashes and they remain recoverable from Git history.

The archive preserves historical recycling, pollution and price-analysis information.
Current/future implementations, design documents, tests and balance baselines remain
in their existing locations. Historical row IDs must never be merged by ID alone.
