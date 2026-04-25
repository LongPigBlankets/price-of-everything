from __future__ import annotations

from pathlib import Path

import pytest

from price_of_everything.models import Good, Ingredient, Recipe

GOODS_HEADER = (
    "ID,internal_name,display_name,category,transport_class,transport_cost,"
    "transport_duration,transport_method,good_type,decay_rate,base_price,"
    "is_buyable,is_sellable,green_sales_premium,is_fossil_fuel,co2_tax_multiplier"
)

RECIPES_HEADER = (
    "recipe_id,display_name,building_id,"
    "input_1,qty_1,input_2,qty_2,input_3,qty_3,input_4,qty_4,input_5,qty_5,"
    "energy_req,optional_input,optional_production_multiplier,"
    "output_1,output_qty_1,output_2,output_qty_2,output_3,output_qty_3,"
    "output_4,output_qty_4,output_5,output_qty_5"
)


def _write_csv(path: Path, header: str, rows: list[str]) -> Path:
    path.write_text(header + "\n" + "\n".join(rows) + "\n", encoding="utf-8")
    return path


@pytest.fixture
def goods_csv_factory(tmp_path: Path):
    def make(rows: list[str]) -> Path:
        return _write_csv(tmp_path / "goods.csv", GOODS_HEADER, rows)

    return make


@pytest.fixture
def recipes_csv_factory(tmp_path: Path):
    def make(rows: list[str]) -> Path:
        return _write_csv(tmp_path / "recipes.csv", RECIPES_HEADER, rows)

    return make


@pytest.fixture
def clean_goods() -> list[Good]:
    return [
        _good("g_001", "coal"),
        _good("g_002", "iron_ore"),
        _good("g_003", "iron_ingots"),
        _good("g_004", "steel"),
    ]


@pytest.fixture
def clean_recipes() -> list[Recipe]:
    return [
        Recipe(
            id="r_001",
            display_name="Iron Smelting",
            building_id="smelter",
            inputs=(Ingredient("iron_ore", 1.0),),
            optional_input=None,
            optional_production_multiplier=None,
            energy_req=1.0,
            outputs=(Ingredient("iron_ingots", 1.0),),
        ),
        Recipe(
            id="r_002",
            display_name="Steelmaking",
            building_id="furnace",
            inputs=(Ingredient("iron_ingots", 1.0), Ingredient("coal", 1.0)),
            optional_input=None,
            optional_production_multiplier=None,
            energy_req=2.0,
            outputs=(Ingredient("steel", 1.0),),
        ),
    ]


def _good(good_id: str, internal_name: str) -> Good:
    return Good(
        id=good_id,
        internal_name=internal_name,
        display_name=internal_name.replace("_", " ").title(),
        category="metals",
        transport_class="solid_heavy",
        transport_cost=1.0,
        transport_duration=1.0,
        transport_method="vehicle",
        good_type="raw",
        decay_rate=0.005,
        base_price=1.0,
        is_buyable=True,
        is_sellable=True,
        green_sales_premium=0.0,
        is_fossil_fuel=False,
        co2_tax_multiplier=0.0,
    )
