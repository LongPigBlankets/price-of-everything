#!/usr/bin/env python3
"""Retired historical generator. This entry point never writes game data."""
import sys

if __name__ == "__main__":
    print("RETIRED: edit price-of-everything-0.1/data/recipes_all.csv directly. "
          "See price-of-everything-0.1/docs/content-authoring.md. "
          "Historical source is in archive/legacy-recipes/scripts/; "
          "the former force option is no longer supported.", file=sys.stderr)
    raise SystemExit(2)
