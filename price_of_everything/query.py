from __future__ import annotations

from dataclasses import fields

from .models import Good


class GoodNotFoundError(LookupError):
    pass


def good_id_for_name(goods: list[Good], internal_name: str) -> str:
    for g in goods:
        if g.internal_name == internal_name:
            return g.id
    raise GoodNotFoundError(
        f"No good with internal_name {internal_name!r}"
    )


def get_good_by_id(goods: list[Good], good_id: str) -> Good:
    for g in goods:
        if g.id == good_id:
            return g
    raise GoodNotFoundError(f"No good with id {good_id!r}")


def find_good(goods: list[Good], identifier: str) -> Good:
    """Look up a single good by id or internal_name.

    Tries id first; on miss, resolves internal_name -> id and retrieves by id.
    Single resolution path keeps the lookup logic in one place.
    """
    try:
        return get_good_by_id(goods, identifier)
    except GoodNotFoundError:
        pass
    good_id = good_id_for_name(goods, identifier)
    return get_good_by_id(goods, good_id)


def good_field_names() -> list[str]:
    return [f.name for f in fields(Good)]


def good_as_row(good: Good) -> list[str]:
    return [_format(getattr(good, name)) for name in good_field_names()]


def _format(value: object) -> str:
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    return str(value)
