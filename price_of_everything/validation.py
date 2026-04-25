from __future__ import annotations

from collections import Counter
from collections.abc import Iterable

from .models import Good, Ingredient, Recipe


class ValidationError(Exception):
    def __init__(self, issues: list[str]):
        self.issues = issues
        header = f"{len(issues)} data issue(s) found:"
        body = "\n".join(f"  - {issue}" for issue in issues)
        super().__init__(f"{header}\n{body}")


def _duplicates(values: Iterable[str]) -> list[str]:
    counts = Counter(values)
    return sorted(v for v, n in counts.items() if n > 1)


def _check_goods(goods: list[Good]) -> list[str]:
    issues: list[str] = []

    for dup in _duplicates(g.id for g in goods):
        issues.append(f"goods: duplicate ID {dup!r}")

    for dup in _duplicates(g.internal_name for g in goods):
        issues.append(f"goods: duplicate internal_name {dup!r}")

    for g in goods:
        if not g.internal_name:
            issues.append(f"goods {g.id}: internal_name is empty")
            continue
        if " " in g.internal_name:
            issues.append(
                f"goods {g.id}: internal_name {g.internal_name!r} contains spaces "
                f"(use underscores)"
            )
        if not g.display_name:
            issues.append(f"goods {g.id}: display_name is empty")

    return issues


def _check_ingredient(
    ingredient: Ingredient, *, recipe_id: str, role: str, known_goods: set[str]
) -> list[str]:
    issues: list[str] = []
    if not ingredient.good:
        issues.append(
            f"recipes {recipe_id}: {role} has quantity but no good name"
        )
        return issues
    if ingredient.good not in known_goods:
        issues.append(
            f"recipes {recipe_id}: {role} references unknown good "
            f"{ingredient.good!r}"
        )
    if ingredient.qty <= 0:
        issues.append(
            f"recipes {recipe_id}: {role} for good {ingredient.good!r} "
            f"has non-positive quantity ({ingredient.qty})"
        )
    return issues


def _check_recipes(recipes: list[Recipe], goods: list[Good]) -> list[str]:
    issues: list[str] = []
    known_goods = {g.internal_name for g in goods}

    for dup in _duplicates(r.id for r in recipes):
        issues.append(f"recipes: duplicate recipe_id {dup!r}")

    for r in recipes:
        if not r.display_name:
            issues.append(f"recipes {r.id}: display_name is empty")
        if not r.building_id:
            issues.append(f"recipes {r.id}: building_id is empty")

        if not r.inputs and not r.outputs:
            issues.append(
                f"recipes {r.id}: has no inputs and no outputs"
            )

        for idx, ing in enumerate(r.inputs, start=1):
            issues.extend(
                _check_ingredient(
                    ing, recipe_id=r.id, role=f"input_{idx}", known_goods=known_goods
                )
            )

        for idx, ing in enumerate(r.outputs, start=1):
            issues.extend(
                _check_ingredient(
                    ing, recipe_id=r.id, role=f"output_{idx}", known_goods=known_goods
                )
            )

        opt_in = r.optional_input
        opt_mult = r.optional_production_multiplier
        if (opt_in is None) != (opt_mult is None):
            issues.append(
                f"recipes {r.id}: optional_input and optional_production_multiplier "
                f"must be set together (got optional_input={opt_in!r}, "
                f"optional_production_multiplier={opt_mult!r})"
            )
        if opt_in is not None and opt_in not in known_goods:
            issues.append(
                f"recipes {r.id}: optional_input references unknown good {opt_in!r}"
            )

    return issues


def validate_all(goods: list[Good], recipes: list[Recipe]) -> None:
    issues: list[str] = []
    issues.extend(_check_goods(goods))
    issues.extend(_check_recipes(recipes, goods))
    if issues:
        raise ValidationError(issues)
