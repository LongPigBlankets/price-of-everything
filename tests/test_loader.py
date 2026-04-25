from __future__ import annotations

import pytest

from price_of_everything.loader import LoaderError, load_goods, load_recipes


def test_load_goods_parses_one_row(goods_csv_factory):
    path = goods_csv_factory(
        ["g_001,coal,Coal,energy,solid_heavy,1,1,vehicle,raw,0.005,1,TRUE,TRUE,0,yes,0.2"]
    )
    goods = load_goods(path)
    assert len(goods) == 1
    g = goods[0]
    assert g.id == "g_001"
    assert g.internal_name == "coal"
    assert g.is_buyable is True
    assert g.is_fossil_fuel is True
    assert g.co2_tax_multiplier == 0.2


def test_load_goods_strict_boolean(goods_csv_factory):
    path = goods_csv_factory(
        ["g_001,coal,Coal,energy,solid_heavy,1,1,vehicle,raw,0.005,1,maybe,TRUE,0,no,0"]
    )
    with pytest.raises(LoaderError, match="is_buyable"):
        load_goods(path)


def test_load_recipes_collapses_wide_format(recipes_csv_factory):
    path = recipes_csv_factory(
        [
            "r_001,Steelmaking,furnace,"
            "iron_ingots,1,coal,1,oxygen,1,,,,,"
            "2,hydrogen,0.25,"
            "steel,1,,,,,,,,"
        ]
    )
    recipes = load_recipes(path)
    assert len(recipes) == 1
    r = recipes[0]
    assert r.id == "r_001"
    assert [i.good for i in r.inputs] == ["iron_ingots", "coal", "oxygen"]
    assert [i.qty for i in r.inputs] == [1.0, 1.0, 1.0]
    assert r.optional_input == "hydrogen"
    assert r.optional_production_multiplier == 0.25
    assert [o.good for o in r.outputs] == ["steel"]


def test_load_recipes_skips_placeholder_rows(recipes_csv_factory):
    path = recipes_csv_factory(
        [
            "r_001,Coal Mining,mine,,,,,,,,,,,1,,,coal,1,,,,,,,,",
            "r_002,,,,,,,,,,,,,,,,,,,,,,,,,",
            "r_003,,,,,,,,,,,,,,,,,,,,,,,,,",
        ]
    )
    recipes = load_recipes(path)
    assert [r.id for r in recipes] == ["r_001"]


def test_load_recipes_blank_qty_kept_as_zero(recipes_csv_factory):
    path = recipes_csv_factory(
        [
            "r_001,Chlor Alkali,chem_plant,"
            "mined_salt,1,pure_water,1,,,,,,,"
            "5,,,"
            "chlorine,2,sodium_hydroxide,,,,,,,"
        ]
    )
    recipes = load_recipes(path)
    r = recipes[0]
    assert [(o.good, o.qty) for o in r.outputs] == [
        ("chlorine", 2.0),
        ("sodium_hydroxide", 0.0),
    ]
