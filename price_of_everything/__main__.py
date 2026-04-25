from __future__ import annotations

import sys

from .loader import load_all
from .validation import ValidationError, validate_all


def main() -> int:
    goods, recipes = load_all()
    try:
        validate_all(goods, recipes)
    except ValidationError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(f"OK: {len(goods)} goods, {len(recipes)} recipes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
