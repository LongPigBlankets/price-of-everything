# price-of-everything
A supply-chain tycoon simulation about the cost of the green transition.

## Licence

Carbon and Capital is proprietary commercial software. The [repository licence](LICENSE)
allows private personal use and modifications, plus gameplay videos and streams
(including monetized ones). Redistribution of the game, its code or its assets
requires separate permission. Official future demos also ship with the
[Demo EULA](price-of-everything-0.1/data/legal/demo_eula.txt).

Earlier MIT grants and third-party licences remain valid; the
[previous MIT notice](docs/legal/PREVIOUS-MIT-LICENSE.txt) is preserved for earlier material.
There is no public mod distribution policy yet.

## Startup check

The [demo startup workflow](.github/workflows/demo-startup.yml) exports a Linux release
and checks fresh and previously accepted EULA launches for Godot errors. See
[the startup check guide](docs/ci-startup-check.md) for its scope and local commands.

## Editing the data

Goods and recipes live in `data/goods.csv` and `data/recipes.csv`. Google Sheets is the source of truth.

To update them:

1. Edit in Sheets.
2. **File ▸ Download ▸ Comma-separated values** for each tab.
3. Save over `data/goods.csv` / `data/recipes.csv` — Sheets adds " - sheet" and "(1)" suffixes; rename when saving.
4. Run the validator:
   ```
   python -m price_of_everything
   ```
   It exits 0 with a row count on success, or prints every cross-reference and schema issue and exits 1.

## Looking up a good

```
python -m price_of_everything good g_001
python -m price_of_everything good coal
```

Accepts either the good id (e.g. `g_001`) or the `internal_name` (e.g. `coal`). Internally the name is resolved to an id, then the id is used for retrieval — single resolution path. Output is two CSV rows: header followed by values. Exits 1 if no match is found.

## Development

```
pip install -e .[dev]
pytest
```
