from __future__ import annotations

import argparse
import csv
import sys

from .loader import load_all, load_goods, DEFAULT_DATA_DIR
from .query import GoodNotFoundError, find_good, good_as_row, good_field_names
from .validation import ValidationError, validate_all


def _cmd_validate() -> int:
    goods, recipes = load_all()
    try:
        validate_all(goods, recipes)
    except ValidationError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(f"OK: {len(goods)} goods, {len(recipes)} recipes")
    return 0


def _cmd_good(identifier: str) -> int:
    goods = load_goods(DEFAULT_DATA_DIR / "goods.csv")
    try:
        good = find_good(goods, identifier)
    except GoodNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    writer = csv.writer(sys.stdout, lineterminator="\n")
    writer.writerow(good_field_names())
    writer.writerow(good_as_row(good))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="price_of_everything")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("validate", help="Load both CSVs and run all data checks (default).")

    p_good = sub.add_parser("good", help="Look up a single good by id or internal_name.")
    p_good.add_argument("identifier", help="Good id (e.g. g_001) or internal_name (e.g. coal).")

    args = parser.parse_args(argv)

    if args.command == "good":
        return _cmd_good(args.identifier)
    return _cmd_validate()


if __name__ == "__main__":
    raise SystemExit(main())
