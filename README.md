# price-of-everything
A supply-chain tycoon simulation about the cost of the green transition.

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

## Development

```
pip install -e .[dev]
pytest
```
