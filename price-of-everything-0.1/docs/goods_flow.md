# Goods production-flow graph

Derived data + visualisation of how goods feed into one another, built from the
in-game tables the Godot client loads (`data/Goods - goodsMVP.csv` and
`data/recipes_all.csv`, see `scripts/catalog.gd`).

## Artifacts

| File | What |
| --- | --- |
| `scripts/build_goods_flow.py` | Generator. Reads the CSVs, computes the graph, writes the two files below. |
| `data/goods_flow.json` | Structured graph data (nodes, edges, tiers, metadata). |
| `docs/goods_flow_chart.html` | Wide left-to-right flow chart (raw materials → finished goods). |

## Regenerate

```sh
python3 scripts/build_goods_flow.py
```

No dependencies beyond the Python standard library. Paths can be overridden with
`--data`, `--out`, `--json`.

## How the graph is built

- **Nodes** are the goods in the goods table. A small number of goods are
  referenced by recipes but are not in the goods table (the two datasets have
  diverged); these are kept as **external feedstock** nodes (drawn dashed) so no
  real production flow is broken. Unambiguous spelling/casing duplicates are
  merged via the `ALIAS` map (`CPU`→`cpu`, `tires`→`tyres`, `copper_piping`→`copper_pipe`).
- **Edges** go `input_good → output_good`. They are taken from each good's
  *defining recipe*.
- **Defining recipe.** Many goods have more than one recipe. The
  **least-efficient** one is selected:
  1. most distinct inputs (more ingredients = less efficient),
  2. then highest power (`energy_req`),
  3. then largest total input quantity.

  A recipe counts as producing good *X* when *X* is its primary output
  (`output_1`); a good that only ever appears as a by-product falls back to any
  recipe that outputs it.
- **Hierarchy / tier** is the longest path from a raw source (tier 0 = raw
  materials and ores). Cycles (e.g. water ⇄ waste-water loops) are broken at
  their back-edge so the layering stays acyclic.

## `goods_flow.json` shape

```jsonc
{
  "meta": {
    "source_goods_csv": "...", "source_recipes_csv": "...",
    "selection_rule": "...", "aliases": { "CPU": "cpu", ... },
    "counts": { "goods_in_csv": 51, "external_feedstocks": 11, "edges": 100,
                "tiers": 9, "goods_with_multiple_recipes": 27,
                "goods_never_produced": [ ... ] }
  },
  "tiers": [ { "tier": 0, "label": "Raw / ores", "goods": [ ... ] }, ... ],
  "nodes": [
    {
      "id": "steel", "display_name": "Steel",
      "category": null, "good_type": "intermediate",
      "source": "goods_csv", "in_goods_csv": true,
      "tier": 2, "tier_label": "Tier 2", "is_raw": false,
      "recipe": {
        "id": "r_077", "name": "HIsarna Steel Making", "building": "furnace",
        "energy_req": 4.0,
        "inputs":  [ { "good": "iron_ingots", "qty": 4 }, ... ],
        "outputs": [ { "good": "steel", "qty": 4 } ],
        "requirements": null, "tag": "Extraction"
      },
      "recipe_options": 5,
      "alternative_recipe_ids": [ "r_003", "r_025", "r_076", "r_106" ],
      "inputs":     [ "coal", "iron_ingots", "oxygen" ],   // goods feeding in
      "feeds_into": [ "building_frame", "car_body", ... ]  // goods this feeds
    }
  ],
  "edges": [ { "from": "iron_ingots", "to": "steel" }, ... ]
}
```

The chart itself is intentionally quantity-free; quantities live in the JSON.
