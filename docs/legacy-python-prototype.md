# Legacy Python prototype

Lifecycle: **legacy retained**. `price_of_everything/`, root `data/`, root `tests/`
and `pyproject.toml` form an earlier CSV validator/query prototype. Keep this dataset
separate from the active Godot schema. Its CLI does not validate the game tables.

From the repository root, the historical commands remain:

```sh
python3 -m price_of_everything
python3 -m price_of_everything good g_001
python3 -m price_of_everything good coal
# Optional development dependency for this prototype's own tests:
python3 -m pip install -e '.[dev]'
python3 -m pytest
```

The CLI defaults to root `data/goods.csv` and `data/recipes.csv` via
`price_of_everything/loader.py`. The validator currently reports 16 issues in this
historical dataset. That result is not a defect report for the Godot catalog.
The root tests exercise loader/query/validation behavior with their own fixtures.

No data is copied from this prototype into the game. For current editing and game
verification, follow [content authoring](../price-of-everything-0.1/docs/content-authoring.md).
Porting this validator to the game schema would be separate work with explicit
cross-reference and promotion semantics, rather than redirecting its data path.
