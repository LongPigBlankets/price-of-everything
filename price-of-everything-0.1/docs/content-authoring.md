# Game content authoring

Current instructions, verified against main on 19 October 2026. Paths in this guide
are relative to `price-of-everything-0.1/` unless stated otherwise.

## Authoritative inputs

| Source | Reader / purpose |
|---|---|
| `data/Goods - goodsMVP.csv` | `scripts/catalog.gd`: goods, prices, transport classes, carbon and graph tiers |
| `data/Buildings - buildingsMVP.csv` | Catalog: building definitions, costs, materials, labour and research |
| `data/recipes_all.csv` | Catalog: the maintained full recipe pool, edited directly |
| `data/research_unlocks.csv` and `data/research_presentation.json` | Research definitions and presentation; see `scripts/research_state.gd` |
| `data/starts/*.json`, `data/start_buildings.json` | Match starts and NPC placement |
| `data/tile_properties.csv`, `data/ports.csv`, `data/infrastructure.csv` | Map properties and transport definitions |
| `data/map_authored/` | Authored map source; see its README and the bake guides |
| `scripts/economy_config.gd`, `scripts/market_state.gd`, `scripts/market_rules.gd` | Economic policy, market state and pricing rules |

The root `data/goods.csv` and `data/recipes.csv` serve the
[legacy Python prototype](../../docs/legacy-python-prototype.md).
They are not alternate sources for the game. Import a spreadsheet only after reviewing
its IDs, schema and row-level diff against the maintained game table.

The former `recipes_master_source.csv` and generated rebalance proposals are
[historical material](../../archive/legacy-recipes/README.md). **Do not regenerate
`recipes_all.csv` from them or copy a proposal over the live table.** The retired
commands at `scripts/build_recipes_all.py` and `scripts/rebalance_recipes.py` always
exit without writing, including with the old force argument.

## Editing procedure

1. Establish the intended rows and stable identifiers before editing. Save games,
   tutorials, research, starts, icons and tests refer to those identifiers. Add IDs;
   do not renumber existing recipes or reuse an old ID for a different recipe.
2. Preserve every existing column, including `tech_unlock_req`, `catalysts`, the
   three `labour_*_required` columns and pollution fields. Keep CSV header order and
   line endings. Use `csv.reader`/`csv.writer` with `newline=''`; select the file's
   existing line terminator. Never rewrite a whole table just to change a few rows.
3. Review `git diff -- <file>` immediately. If unrelated rows changed, correct the
   edit before continuing. Prices, costs, quantities and rates require the project's
   balance-change workflow and before/after evidence.
4. Trace dependencies through the actual runtime readers, not file names or a dated
   design document. Check both the full game and the staged demo when relevant.

For a targeted CSV edit, preserve the file's existing line terminator explicitly:

```python
import csv
from pathlib import Path
path = Path("data/recipes_all.csv")
line_ending = "\r\n" if b"\r\n" in path.read_bytes() else "\n"
with path.open(newline="", encoding="utf-8") as stream:
    rows = list(csv.reader(stream))
# Change the intended cells by stable ID here, keeping every other cell and column.
with path.open("w", newline="", encoding="utf-8") as stream:
    csv.writer(stream, lineterminator=line_ending).writerows(rows)
```

The four main tables currently use LF. CSV quoting may also affect a diff: inspect it
before accepting the edit rather than assuming a read/write round trip is byte-identical.

As a dated inventory, the full source currently has 77 goods, 38 buildings, 210 recipe
rows and 253 research rows. Catalog promotes 147 recipes at startup. These counts are
observations, not schema constraints or a reason to delete dormant rows.

## Recipe and research checks

Catalog reads `input_1` through `input_6` with `qty_1` through `qty_6`, and
`output_1` through `output_5` with `output_qty_1` through `output_qty_5`.
Fill each name/quantity pair together; missing quantities can remove an input/output.
Use goods' `internal_name` values in these fields and resolve building names through
Catalog's `BUILDING_ALIAS` table when applicable.

The promotion gate rejects recipes whose buildings or goods cannot resolve. Authored,
promoted, demo-visible and currently unlocked recipes are different sets. For every
changed recipe, check `Catalog.get_recipe(id)` in a full-game test and check its
availability via `Catalog.get_recipes_for_building(building_id)` at the intended
research state. A CSV row alone is not evidence that the recipe appears in the game.

Recipe research is **`tech_unlock_req`**; building research is **`required_research`**.
Trace the exact token through `ResearchState.is_unlocked` and the research definitions.
Research includes node IDs, titles and a few compatibility tokens; do not assume these
fields are interchangeable. Verify prerequisites, the implemented condition handler
and a reachable unlock path. For requirements, follow the current parser and runtime
checks; prose such as `river` or `deep_sea` is not proof of enforcement.

Recycling is retained full-game/future content. Pollution/carbon fields and market
pricing are retained even when a particular future mechanic is not visible in the
demo. Avoid deleting their schema, recipes, tests, art or design evidence during pruning.

## Derived files and demo exports

`scripts/build_goods_flow.py` generates `data/goods_flow.json` and
`docs/goods_flow_chart.html`. These are documentation/visualization snapshots; their
generation does not replace Catalog's inputs. See [goods_flow.md](goods_flow.md).

The full source remains canonical. `scripts/demo_build.gd`,
`tools/demo_build/excludes.txt`, strip regions and the demo export plugin select the
demo's code/data. **Do not remove full-only rows from the canonical CSVs to make a
demo.** See [demo-build.md](demo-build.md); refresh presets with:

```sh
python3 tools/demo_build/build_demo.py sync
python3 tools/demo_build/build_demo.py check
```

## Verification and bakes

```sh
godot --headless --path . res://tools/parse_check.tscn
python3 tools/run_tests.py
# Simulation, economy or content changes also require the separate E2E harness:
godot --headless --path . res://tests/e2e_stoneshore.tscn -- 100
```

Report actual output and any existing failure set; a passing parser is not content
validation. Add a focused check for affected references and exercise the relevant
in-game surface. UI changes require rendered checks via `AGENT_GODOT_WINDOW=1 godot`.
Serialize Godot runs. Root pytest and the Python prototype validator do not validate
the game schema.

If a change affects a stored resource's inputs, use [load-time-bakes.md](load-time-bakes.md)
and [supply_chain_3d.md](supply_chain_3d.md). Refresh only affected production resources,
install them, validate fingerprints and bundled hits, then measure a fresh process.
Documentation and retiring unused data exports do not invalidate terrain/model bakes.
