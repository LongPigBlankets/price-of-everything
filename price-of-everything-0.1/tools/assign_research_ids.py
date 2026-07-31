#!/usr/bin/env python3
"""Assign stable research_node_id values in data/research_unlocks.csv.

THE CONTRACT — read before running:
  * IDs are PERMANENT. Once a row has one it is never changed and never reused,
    because saves and the modifier table reference it.
  * This script is APPEND-ONLY and idempotent: rows that already carry an id keep
    it byte-for-byte, and new rows continue from the highest number already used
    in their category. Re-running it after adding content is safe and is the
    intended workflow.
  * It therefore never renumbers. Renumbering would break exactly what the ids
    exist to protect, so there is deliberately no flag to force it.

Usage (from the Godot project root):
    python3 tools/assign_research_ids.py [--check]

  --check  exit 1 if any row is missing an id or any id is duplicated, and
           change nothing. For CI / pre-commit.
"""
import argparse
import csv
import re
import sys
from pathlib import Path

CSV_PATH = Path(__file__).resolve().parent.parent / "data" / "research_unlocks.csv"
ID_COL = "research_node_id"

# Short, permanent per-category prefixes. Adding a category means adding a prefix
# here; never change an existing one (the ids built from it are already in saves).
PREFIX = {
    "Biochemistry": "biochem",
    "Hydrocarbon Power": "hcpower",
    "Infrastructure": "infra",
    "Inorganic Chemistry": "inorg",
    "Logistics": "logi",
    "Manufacturing": "mfg",
    "Markets and Operations": "markets",
    "Metallurgy": "metal",
    "Mining and Surveying": "mining",
    "People Management": "people",
    "Petrochemistry": "petro",
    "Recycling": "recyc",
    "Renewable Power": "renew",
}

ID_RE = re.compile(r"^research_([a-z]+)_(\d{3})$")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    with CSV_PATH.open(newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        print("no rows read — aborting")
        return 1
    fieldnames = list(rows[0].keys())

    # Highest number already used per prefix, so new ids continue rather than collide.
    highest: dict[str, int] = {}
    seen: dict[str, str] = {}
    dupes: list[str] = []
    for r in rows:
        rid = (r.get(ID_COL) or "").strip()
        if not rid:
            continue
        if rid in seen:
            dupes.append(rid)
        seen[rid] = r.get("title", "")
        m = ID_RE.match(rid)
        if not m:
            print(f"  MALFORMED id {rid!r} on {r.get('title')!r}")
            return 1
        highest[m.group(1)] = max(highest.get(m.group(1), 0), int(m.group(2)))

    missing = [r for r in rows if not (r.get(ID_COL) or "").strip()]

    if args.check:
        ok = not missing and not dupes
        print(f"rows={len(rows)} with_id={len(rows) - len(missing)} "
              f"missing={len(missing)} duplicate={len(dupes)}")
        for r in missing[:10]:
            print(f"  MISSING  {r.get('category')} / {r.get('title')}")
        for d in dupes[:10]:
            print(f"  DUPLICATE {d}")
        return 0 if ok else 1

    if dupes:
        print(f"duplicate ids present, refusing to write: {sorted(set(dupes))}")
        return 1

    assigned = 0
    for r in rows:
        if (r.get(ID_COL) or "").strip():
            continue
        cat = (r.get("category") or "").strip()
        if cat not in PREFIX:
            print(f"  no prefix registered for category {cat!r} — add it to PREFIX")
            return 1
        p = PREFIX[cat]
        highest[p] = highest.get(p, 0) + 1
        r[ID_COL] = f"research_{p}_{highest[p]:03d}"
        assigned += 1

    if ID_COL not in fieldnames:
        fieldnames = [ID_COL] + fieldnames

    with CSV_PATH.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fieldnames, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    print(f"assigned {assigned} new id(s); {len(rows)} rows total")
    return 0


if __name__ == "__main__":
    sys.exit(main())
