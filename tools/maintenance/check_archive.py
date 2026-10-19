#!/usr/bin/env python3
"""Verify the retained source/data archive against its provenance manifest."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    manifest = json.loads((ROOT / "archive/manifest.json").read_text())
    failures = []
    seen = set()
    for entry in manifest["entries"]:
        name = entry["archive_path"]
        path = ROOT / name
        if name in seen or not path.resolve().is_relative_to(ROOT / "archive"):
            failures.append(f"Invalid or duplicate archive path: {name}")
            continue
        seen.add(name)
        if not path.is_file():
            failures.append(f"Missing: {name}")
            continue
        data = path.read_bytes()
        if len(data) != entry["bytes"] or hashlib.sha256(data).hexdigest() != entry["archive_sha256"]:
            failures.append(f"Changed: {name}")
    if failures:
        print("\n".join(failures))
        return 1
    print(f"Verified {len(seen)} archived files; "
          f"{len(manifest['removed_generated'])} retired generated files recorded.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
