from __future__ import annotations

import pytest

from price_of_everything.query import (
    GoodNotFoundError,
    find_good,
    format_record_table,
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


def test_format_record_table_basic():
    out = format_record_table([("id", "g_001"), ("internal_name", "coal")])
    lines = out.splitlines()
    # top border + 2 data rows + bottom border = 4 lines
    assert len(lines) == 4
    assert lines[0] == lines[-1]
    assert lines[0].startswith("+") and lines[0].endswith("+")
    assert "id" in lines[1] and "g_001" in lines[1]
    assert "internal_name" in lines[2] and "coal" in lines[2]


def test_format_record_table_pads_columns_consistently():
    out = format_record_table(
        [("a", "very_long_value"), ("long_field_name", "x")]
    )
    lines = out.splitlines()
    assert len({len(line) for line in lines}) == 1
