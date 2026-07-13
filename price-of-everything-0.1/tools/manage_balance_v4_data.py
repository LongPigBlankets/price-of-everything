#!/usr/bin/env python3
"""Safely inspect, deploy, or revert the balance-v4 runtime CSV fields."""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
from pathlib import Path
import stat
import tempfile


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = PROJECT_ROOT / "data" / "balance_v4_changes.json"


class PresetError(RuntimeError):
    pass


def load_manifest(path: Path) -> dict:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != 1:
        raise PresetError(f"Unsupported manifest schema: {manifest.get('schema_version')!r}")
    if not manifest.get("files"):
        raise PresetError("Manifest contains no files")
    return manifest


def read_csv(path: Path) -> dict:
    raw = path.read_bytes()
    has_bom = raw.startswith(b"\xef\xbb\xbf")
    encoding = "utf-8-sig" if has_bom else "utf-8"
    text = raw.decode(encoding)
    lines = text.splitlines(keepends=True)
    if not lines:
        raise PresetError(f"Missing CSV header: {path}")
    parsed_lines: list[list[str]] = []
    for line_number, line in enumerate(lines, start=1):
        parsed = list(csv.reader([line]))
        if len(parsed) != 1:
            raise PresetError(f"{path}:{line_number}: multiline CSV records are not supported")
        parsed_lines.append(parsed[0])
    fieldnames = parsed_lines[0]
    rows: list[dict[str, str]] = []
    for line_number, values in enumerate(parsed_lines[1:], start=2):
        if len(values) != len(fieldnames):
            raise PresetError(
                f"{path}:{line_number}: expected {len(fieldnames)} columns, found {len(values)}"
            )
        rows.append(dict(zip(fieldnames, values)))
    return {
        "fieldnames": fieldnames,
        "rows": rows,
        "lines": lines,
        "has_bom": has_bom,
        "mode": stat.S_IMODE(path.stat().st_mode),
    }


def index_rows(path: Path, data: dict, key_column: str) -> dict[str, tuple[dict, int]]:
    if key_column not in data["fieldnames"]:
        raise PresetError(f"{path}: key column {key_column!r} is absent")
    indexed: dict[str, tuple[dict, int]] = {}
    for line_index, row in enumerate(data["rows"], start=1):
        key = row.get(key_column, "")
        if key in indexed:
            raise PresetError(f"{path}: duplicate {key_column} value {key!r}")
        indexed[key] = (row, line_index)
    return indexed


def inspect(manifest: dict) -> tuple[dict[str, int], list[str]]:
    counts = {"deployed": 0, "reverted": 0, "conflict": 0}
    details: list[str] = []
    for file_spec in manifest["files"]:
        relative = Path(file_spec["path"])
        path = PROJECT_ROOT / relative
        data = read_csv(path)
        indexed = index_rows(path, data, file_spec["key_column"])
        for row_change in file_spec["changes"]:
            key = row_change["key"]
            if key not in indexed:
                raise PresetError(f"{relative}: row {key!r} is absent")
            row, _line_index = indexed[key]
            for column, values in row_change["fields"].items():
                if column not in data["fieldnames"]:
                    raise PresetError(f"{relative}: column {column!r} is absent")
                current = row[column]
                if current == values["new"]:
                    state = "deployed"
                elif current == values["old"]:
                    state = "reverted"
                else:
                    state = "conflict"
                    details.append(
                        f"{relative}:{key}.{column} is {current!r}; "
                        f"expected old {values['old']!r} or new {values['new']!r}"
                    )
                counts[state] += 1
    return counts, details


def csv_cell_spans(line: str) -> list[tuple[int, int]]:
    """Return raw cell spans for one CSV record, preserving its original formatting."""
    spans: list[tuple[int, int]] = []
    start = 0
    index = 0
    in_quotes = False
    while index < len(line):
        char = line[index]
        if char == '"':
            if in_quotes and index + 1 < len(line) and line[index + 1] == '"':
                index += 2
                continue
            in_quotes = not in_quotes
        elif char == "," and not in_quotes:
            spans.append((start, index))
            start = index + 1
        index += 1
    if in_quotes:
        raise PresetError("Unterminated quoted CSV field")
    spans.append((start, len(line)))
    return spans


def encode_csv_cell(value: str) -> str:
    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="")
    writer.writerow([value])
    return output.getvalue()


def split_line_ending(line: str) -> tuple[str, str]:
    if line.endswith("\r\n"):
        return line[:-2], "\r\n"
    if line.endswith("\n") or line.endswith("\r"):
        return line[:-1], line[-1]
    return line, ""


def render_csv(data: dict, replacements: dict[int, dict[int, str]]) -> bytes:
    lines = list(data["lines"])
    for line_index, columns in replacements.items():
        body, ending = split_line_ending(lines[line_index])
        spans = csv_cell_spans(body)
        for column_index, desired in sorted(columns.items(), reverse=True):
            if column_index >= len(spans):
                raise PresetError(
                    f"CSV line {line_index + 1}: column index {column_index} is absent"
                )
            start, end = spans[column_index]
            body = body[:start] + encode_csv_cell(desired) + body[end:]
        lines[line_index] = body + ending
    encoding = "utf-8-sig" if data["has_bom"] else "utf-8"
    return "".join(lines).encode(encoding)


def write_atomic(path: Path, content: bytes, mode: int) -> None:
    temp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", delete=False) as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
            temp_path = Path(handle.name)
        os.chmod(temp_path, mode)
        os.replace(temp_path, path)
    finally:
        if temp_path is not None and temp_path.exists():
            temp_path.unlink()


def switch(manifest: dict, target: str) -> tuple[int, int]:
    source = "old" if target == "new" else "new"
    prepared: list[tuple[Path, bytes, int]] = []
    changed_fields = 0
    unchanged_fields = 0

    for file_spec in manifest["files"]:
        relative = Path(file_spec["path"])
        path = PROJECT_ROOT / relative
        data = read_csv(path)
        indexed = index_rows(path, data, file_spec["key_column"])
        column_indexes = {name: index for index, name in enumerate(data["fieldnames"])}
        replacements: dict[int, dict[int, str]] = {}
        file_changed = False
        for row_change in file_spec["changes"]:
            key = row_change["key"]
            if key not in indexed:
                raise PresetError(f"{relative}: row {key!r} is absent")
            row, line_index = indexed[key]
            for column, values in row_change["fields"].items():
                if column not in data["fieldnames"]:
                    raise PresetError(f"{relative}: column {column!r} is absent")
                current = row[column]
                desired = values[target]
                allowed_source = values[source]
                if current == desired:
                    unchanged_fields += 1
                    continue
                if current != allowed_source:
                    raise PresetError(
                        f"Refusing to overwrite {relative}:{key}.{column}: found {current!r}, "
                        f"expected {allowed_source!r}. Resolve the conflicting edit first."
                    )
                replacements.setdefault(line_index, {})[column_indexes[column]] = desired
                changed_fields += 1
                file_changed = True
        if file_changed:
            prepared.append((path, render_csv(data, replacements), data["mode"]))

    for path, content, mode in prepared:
        write_atomic(path, content, mode)
    return changed_fields, unchanged_fields


def state_label(counts: dict[str, int]) -> str:
    if counts["conflict"]:
        return "conflict"
    if counts["deployed"] and counts["reverted"]:
        return "mixed"
    if counts["deployed"]:
        return "deployed"
    return "reverted"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--apply", action="store_true", help="Deploy every balance-v4 new value")
    action.add_argument("--revert", action="store_true", help="Restore every recorded pre-v4 value")
    action.add_argument("--status", action="store_true", help="Inspect current values (default)")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args()

    try:
        manifest = load_manifest(args.manifest)
        if args.apply or args.revert:
            target = "new" if args.apply else "old"
            changed, unchanged = switch(manifest, target)
            verb = "deployed" if args.apply else "reverted"
            print(f"{manifest['preset']}: {verb} {changed} fields; {unchanged} already matched")

        counts, details = inspect(manifest)
        state = state_label(counts)
        total = sum(counts.values())
        print(
            f"{manifest['preset']}: {state} "
            f"({counts['deployed']} deployed, {counts['reverted']} reverted, "
            f"{counts['conflict']} conflicting; {total} total)"
        )
        for detail in details:
            print(f"ERROR: {detail}")
        return 0 if state in {"deployed", "reverted"} else 1
    except (OSError, csv.Error, json.JSONDecodeError, PresetError) as error:
        print(f"ERROR: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
