from __future__ import annotations

import csv
from pathlib import Path

from .models import Good, Ingredient, Recipe

DEFAULT_DATA_DIR = Path(__file__).resolve().parent.parent / "data"


class LoaderError(Exception):
    pass


def _parse_bool(value: str, *, row_id: str, field: str) -> bool:
    v = value.strip().upper()
    if v == "TRUE":
        return True
    if v == "FALSE":
        return False
    raise LoaderError(
        f"{row_id}: field {field!r} expected TRUE/FALSE, got {value!r}"
    )


def _parse_yesno(value: str, *, row_id: str, field: str) -> bool:
    v = value.strip().lower()
    if v == "yes":
        return True
    if v == "no":
        return False
    raise LoaderError(
        f"{row_id}: field {field!r} expected yes/no, got {value!r}"
    )


def _parse_float(value: str, *, row_id: str, field: str, default: float | None = None) -> float:
    v = value.strip()
    if not v:
        if default is not None:
            return default
        raise LoaderError(f"{row_id}: field {field!r} is empty (expected a number)")
    try:
        return float(v)
    except ValueError as exc:
        raise LoaderError(
            f"{row_id}: field {field!r} expected a number, got {value!r}"
        ) from exc


def _optional_float(value: str, *, row_id: str, field: str) -> float | None:
    v = value.strip()
    if not v:
        return None
    try:
        return float(v)
    except ValueError as exc:
        raise LoaderError(
            f"{row_id}: field {field!r} expected a number or empty, got {value!r}"
        ) from exc


def load_goods(path: str | Path) -> list[Good]:
    path = Path(path)
    goods: list[Good] = []
    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            good_id = row["ID"].strip()
            if not good_id:
                continue
            goods.append(
                Good(
                    id=good_id,
                    internal_name=row["internal_name"].strip(),
                    display_name=row["display_name"].strip(),
                    category=row["category"].strip(),
                    transport_class=row["transport_class"].strip(),
                    transport_cost=_parse_float(
                        row["transport_cost"], row_id=good_id, field="transport_cost"
                    ),
                    transport_duration=_parse_float(
                        row["transport_duration"], row_id=good_id, field="transport_duration"
                    ),
                    transport_method=row["transport_method"].strip(),
                    good_type=row["good_type"].strip(),
                    decay_rate=_parse_float(
                        row["decay_rate"], row_id=good_id, field="decay_rate"
                    ),
                    base_price=_parse_float(
                        row["base_price"], row_id=good_id, field="base_price"
                    ),
                    is_buyable=_parse_bool(
                        row["is_buyable"], row_id=good_id, field="is_buyable"
                    ),
                    is_sellable=_parse_bool(
                        row["is_sellable"], row_id=good_id, field="is_sellable"
                    ),
                    green_sales_premium=_parse_float(
                        row["green_sales_premium"], row_id=good_id, field="green_sales_premium"
                    ),
                    is_fossil_fuel=_parse_yesno(
                        row["is_fossil_fuel"], row_id=good_id, field="is_fossil_fuel"
                    ),
                    co2_tax_multiplier=_parse_float(
                        row["co2_tax_multiplier"], row_id=good_id, field="co2_tax_multiplier"
                    ),
                )
            )
    return goods


def _collect_ingredients(
    row: dict[str, str], *, prefix: str, qty_prefix: str, count: int, row_id: str
) -> tuple[Ingredient, ...]:
    out: list[Ingredient] = []
    for i in range(1, count + 1):
        good = row.get(f"{prefix}{i}", "").strip()
        qty_raw = row.get(f"{qty_prefix}{i}", "").strip()
        if not good and not qty_raw:
            continue
        qty = _optional_float(qty_raw, row_id=row_id, field=f"{qty_prefix}{i}")
        out.append(Ingredient(good=good, qty=qty if qty is not None else 0.0))
    return tuple(out)


def _is_placeholder_recipe(row: dict[str, str]) -> bool:
    for key, value in row.items():
        if key == "recipe_id":
            continue
        if value is not None and value.strip() != "":
            return False
    return True


def load_recipes(path: str | Path) -> list[Recipe]:
    path = Path(path)
    recipes: list[Recipe] = []
    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            recipe_id = row["recipe_id"].strip()
            if not recipe_id:
                continue
            if _is_placeholder_recipe(row):
                continue
            inputs = _collect_ingredients(
                row, prefix="input_", qty_prefix="qty_", count=5, row_id=recipe_id
            )
            outputs = _collect_ingredients(
                row, prefix="output_", qty_prefix="output_qty_", count=5, row_id=recipe_id
            )
            optional_input = row.get("optional_input", "").strip() or None
            optional_multiplier = _optional_float(
                row.get("optional_production_multiplier", ""),
                row_id=recipe_id,
                field="optional_production_multiplier",
            )
            energy_req = _parse_float(
                row.get("energy_req", ""), row_id=recipe_id, field="energy_req", default=0.0
            )
            recipes.append(
                Recipe(
                    id=recipe_id,
                    display_name=row["display_name"].strip(),
                    building_id=row["building_id"].strip(),
                    inputs=inputs,
                    optional_input=optional_input,
                    optional_production_multiplier=optional_multiplier,
                    energy_req=energy_req,
                    outputs=outputs,
                )
            )
    return recipes


def load_all(data_dir: str | Path = DEFAULT_DATA_DIR) -> tuple[list[Good], list[Recipe]]:
    data_dir = Path(data_dir)
    return load_goods(data_dir / "goods.csv"), load_recipes(data_dir / "recipes.csv")
