from __future__ import annotations

from dataclasses import replace

import pytest

from price_of_everything.models import Ingredient, Recipe
from price_of_everything.validation import ValidationError, validate_all


def test_clean_data_passes(clean_goods, clean_recipes):
    validate_all(clean_goods, clean_recipes)


def test_duplicate_good_id(clean_goods, clean_recipes):
    dup = replace(clean_goods[0], internal_name="something_else")
    with pytest.raises(ValidationError, match="duplicate ID"):
        validate_all([*clean_goods, dup], clean_recipes)


def test_duplicate_internal_name(clean_goods, clean_recipes):
    dup = replace(clean_goods[0], id="g_999")
    with pytest.raises(ValidationError, match="duplicate internal_name"):
        validate_all([*clean_goods, dup], clean_recipes)


def test_internal_name_with_space(clean_goods, clean_recipes):
    bad = replace(clean_goods[0], internal_name="pure water")
    with pytest.raises(ValidationError, match="contains spaces"):
        validate_all([bad, *clean_goods[1:]], clean_recipes)


def test_recipe_unknown_input(clean_goods, clean_recipes):
    broken = Recipe(
        id="r_900",
        display_name="Bogus",
        building_id="smelter",
        inputs=(Ingredient("chem_salts", 1.0),),  # goods has chem_salt, not chem_salts
        optional_input=None,
        optional_production_multiplier=None,
        energy_req=1.0,
        outputs=(Ingredient("steel", 1.0),),
    )
    with pytest.raises(ValidationError, match="unknown good 'chem_salts'"):
        validate_all(clean_goods, [*clean_recipes, broken])


def test_recipe_blank_qty(clean_goods, clean_recipes):
    broken = Recipe(
        id="r_901",
        display_name="Chlor Alkali",
        building_id="chem_plant",
        inputs=(Ingredient("iron_ore", 1.0),),
        optional_input=None,
        optional_production_multiplier=None,
        energy_req=1.0,
        outputs=(Ingredient("steel", 1.0), Ingredient("iron_ingots", 0.0)),
    )
    with pytest.raises(ValidationError, match="non-positive quantity"):
        validate_all(clean_goods, [*clean_recipes, broken])


def test_recipe_no_inputs_or_outputs(clean_goods, clean_recipes):
    empty = Recipe(
        id="r_902",
        display_name="Hydroelectric Turbines",
        building_id="hydro_dam",
        inputs=(),
        optional_input=None,
        optional_production_multiplier=None,
        energy_req=0.0,
        outputs=(),
    )
    with pytest.raises(ValidationError, match="no inputs and no outputs"):
        validate_all(clean_goods, [*clean_recipes, empty])


def test_optional_input_without_multiplier(clean_goods, clean_recipes):
    half = Recipe(
        id="r_903",
        display_name="Half-set optional",
        building_id="water_well",
        inputs=(Ingredient("iron_ore", 1.0),),
        optional_input="coal",
        optional_production_multiplier=None,
        energy_req=1.0,
        outputs=(Ingredient("steel", 1.0),),
    )
    with pytest.raises(ValidationError, match="must be set together"):
        validate_all(clean_goods, [*clean_recipes, half])


def test_optional_input_unknown_good(clean_goods, clean_recipes):
    bad = Recipe(
        id="r_904",
        display_name="Unknown optional",
        building_id="water_well",
        inputs=(Ingredient("iron_ore", 1.0),),
        optional_input="ghost_good",
        optional_production_multiplier=0.5,
        energy_req=1.0,
        outputs=(Ingredient("steel", 1.0),),
    )
    with pytest.raises(ValidationError, match="optional_input references unknown good 'ghost_good'"):
        validate_all(clean_goods, [*clean_recipes, bad])


def test_error_aggregates_all_issues(clean_goods, clean_recipes):
    bad_good = replace(clean_goods[0], internal_name="bad name")
    bad_recipe = Recipe(
        id="r_905",
        display_name="Two issues",
        building_id="smelter",
        inputs=(Ingredient("nonexistent", 1.0),),
        optional_input=None,
        optional_production_multiplier=None,
        energy_req=1.0,
        outputs=(),
    )
    with pytest.raises(ValidationError) as exc:
        validate_all([bad_good, *clean_goods[1:]], [*clean_recipes, bad_recipe])
    assert len(exc.value.issues) >= 2
