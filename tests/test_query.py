from __future__ import annotations

import pytest

from price_of_everything.query import (
    GoodNotFoundError,
    find_good,
    good_as_row,
    good_field_names,
)


def test_find_good_by_id(clean_goods):
    g = find_good(clean_goods, "g_001")
    assert g.internal_name == "coal"


def test_find_good_by_internal_name(clean_goods):
    g = find_good(clean_goods, "iron_ore")
    assert g.id == "g_002"


def test_find_good_unknown_raises(clean_goods):
    with pytest.raises(GoodNotFoundError):
        find_good(clean_goods, "no_such_good")


def test_good_as_row_aligns_with_field_names(clean_goods):
    headers = good_field_names()
    row = good_as_row(clean_goods[0])
    assert len(headers) == len(row)
    assert "internal_name" in headers
    assert "coal" in row


def test_good_as_row_formats_booleans(clean_goods):
    row = good_as_row(clean_goods[0])
    headers = good_field_names()
    assert row[headers.index("is_buyable")] == "TRUE"
    assert row[headers.index("is_fossil_fuel")] == "FALSE"
