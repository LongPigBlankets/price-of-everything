---
name: cnc-content-pipeline
description: Use when authoring goods, recipes, buildings, research, starts or icons, or diagnosing content that does not appear. Establishes current table ownership, promotion and demo boundaries, with the maintained authoring guide and verification requirements.
---

# Content pipeline

Follow [the current content-authoring guide](../../../price-of-everything-0.1/docs/content-authoring.md).
Verified 19 October 2026 against Catalog, ResearchState and the demo build pipeline.

## Source ownership

Within `price-of-everything-0.1/data/`:

- `Goods - goodsMVP.csv`: goods, prices, transport, carbon and graph tiers.
- `Buildings - buildingsMVP.csv`: buildings, kits, costs, labour, research.
- `recipes_all.csv`: maintained recipe source. Edit directly, preserving stable IDs,
  all columns and existing line endings. It is not generated from a master CSV.
- `research_unlocks.csv` / `research_presentation.json`: research and its presentation.
- Starts, NPCs, tile properties, ports and infrastructure retain their existing readers.

The dated full-source inventory is 77 goods, 38 buildings, 210 recipe rows and 253
research rows; Catalog promotes 147 recipes. Counts are observations, not constraints.
Root `data/` and `python -m price_of_everything` belong to a separate legacy prototype.

## Retired generators

`scripts/build_recipes_all.py` and `scripts/rebalance_recipes.py` now refuse all runs,
including the former force option. Original sources and competing CSV generations
are preserved under `archive/legacy-recipes/` at the repository root, with hashes.
Do not restore the bootstrap into an authoring workflow: it renumbers IDs, loses
hand-authored content/columns and resets balance quantities. Historical rebalance
outputs are proposal evidence, not a drop-in replacement for live tables.

## Resolve references and verify promotion

- Fill each `input_N` / `qty_N` and `output_N` / `output_qty_N` pair together.
  Missing quantities can drop an entry. Keep `catalysts` and all labour/pollution fields.
- Slot goods use `internal_name`; resolve building names via Catalog's aliases.
  The promotion gate rejects unresolved goods/buildings. Verify every changed recipe
  with `Catalog.get_recipe(id)` and its availability at the intended research state.
- Recipes use `tech_unlock_req`; buildings use `required_research`. Follow the exact
  token through `ResearchState.is_unlocked`. Node IDs, titles and compatibility tokens
  are not interchangeable. Verify condition handlers and reachable prerequisites.
- Requirements must have an implemented parser/runtime check; a descriptive token
  alone does not enforce a placement or production rule.
- Preserve IDs referenced by saves, tutorials, research, starts and tests. Never delete
  dormant rows or future systems merely because the current demo hides them.

## Demo and retained future content

The full source is canonical. The staged demo prunes copies via `DemoBuild`, its exclude
list, strip regions and export plugin; see `docs/demo-build.md`. Do not remove full-only
rows from canonical CSVs. Keep recycling, pollution/carbon and market-pricing logic,
art/tests and future designs. Refresh/check demo presets if their inputs change.

`build_goods_flow.py`, `goods_flow.json` and the HTML chart remain a derived
visualization workflow, documented in `docs/goods_flow.md`; they are not dead runtime
input replacements.

## Verification

Read `cnc-godot-discipline` for CSV editing mechanics and `cnc-validation-and-qa` for
full-context parse check, headless unit suite, separate E2E and rendered UI checks.
Inspect actual diffs and promotion results; root pytest does not validate game content.
For tuning columns, use `cnc-balance-change-control` and retain before/after evidence.
If inputs to production bakes change, refresh only the affected dependencies, install
and validate them, then measure fresh-process bundled hits and startup/first-open times.
