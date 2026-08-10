#!/usr/bin/env python3
"""Extract every player-visible tutorial string to a CSV for editing.

    python3 tools/extract_tutorial_strings.py            # -> tools/tutorial_strings.csv
    python3 tools/extract_tutorial_strings.py --check     # verify the CSV is in sync, exit 1 if not

One row per string LITERAL in the source, in source order, so the CSV reads like the
tutorial top-to-bottom and every row maps back to exactly one place in exactly one file.
`file` + `line` + `key` identify the row; `text` is the only column meant to be edited.

Two things to respect when editing `text`:

  * Rows with a non-empty `format_args` are printf templates — the `%d` / `%s` / `%%`
    placeholders are filled at runtime from the live Catalog (so the copy can't quote a
    stale price). Keep the placeholders, in the same order and of the same type, or the
    step will crash on `%`.
  * `active=FALSE` rows are authored but not currently shown: `_integration_steps()` is
    deferred content that `steps()` does not return.

Deliberately NOT extracted: `spotlight.ref` and `decide.title` values such as
"Bauxite Carbochlorination". They look like prose but are lookup keys matched against
research node titles — editing them breaks step completion rather than changing copy.
"""
from __future__ import annotations

import argparse
import csv
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent          # price-of-everything-0.1/
REPO = ROOT.parent
STEPS_GD = ROOT / "scripts/tutorial/tutorial_steps.gd"
OUT = ROOT / "tools/tutorial_strings.csv"

# Chrome around the steps: the coach card's own furniture and the tutorial's menu screens.
# (file, line-matching regex, key, field) - the regex must have one group: the literal.
CHROME = [
	("scripts/tutorial/tutorial_engine.gd",    r'PORT_PURCHASE_DISABLED_TOOLTIP\s*:=\s*("(?:[^"\\]|\\.)*")', "tutorial.port_purchase_disabled", "tooltip"),
	("scripts/tutorial/coach_overlay.gd",     r'_eyebrow\.text = ("(?:[^"\\]|\\.)*")',    "coach.eyebrow_format",       "format"),
    ("scripts/tutorial/coach_overlay.gd",     r'\.get\("label", ("(?:[^"\\]|\\.)*")\)',   "coach.choice_fallback",      "button"),
    ("scripts/tutorial/coach_overlay.gd",     r'skip\.text = ("(?:[^"\\]|\\.)*")',        "coach.skip_button",          "button"),
    ("scripts/tutorial/coach_overlay.gd",     r'_next_btn\.text = ("(?:[^"\\]|\\.)*")',   "coach.next_button",          "button"),
    ("scripts/tutorial/coach_overlay.gd",     r'wskip\.text = ("(?:[^"\\]|\\.)*")',       "coach.welcome_skip_button",  "button"),
    ("scripts/tutorial/coach_overlay.gd",     r'_welcome_btn\.text = ("(?:[^"\\]|\\.)*")', "coach.welcome_cta_default", "button"),
    ("scripts/tutorial_intro_panel.gd",       r'back\.text = ("(?:[^"\\]|\\.)*")',        "intro.back_button",          "button"),
    ("scripts/tutorial_intro_panel.gd",       r'banner\.text = ("(?:[^"\\]|\\.)*")',      "intro.banner",               "title"),
    ("scripts/tutorial_intro_panel.gd",       r'blurb\.text = ("(?:[^"\\]|\\.)*")',       "intro.blurb",                "body"),
    ("scripts/tutorial_intro_panel.gd",       r'begin\.text = ("(?:[^"\\]|\\.)*")',       "intro.begin_button",         "button"),
    ("scripts/tutorial_prompt_dialog.gd",     r'title\.text = ("(?:[^"\\]|\\.)*")',       "prompt.title",               "title"),
    ("scripts/tutorial_prompt_dialog.gd",     r'blurb\.text = ("(?:[^"\\]|\\.)*")',       "prompt.blurb",               "body"),
    ("scripts/tutorial_prompt_dialog.gd",     r'go\.text = ("(?:[^"\\]|\\.)*")',          "prompt.accept_button",       "button"),
    ("scripts/tutorial_prompt_dialog.gd",     r'skip\.text = ("(?:[^"\\]|\\.)*")',        "prompt.decline_button",      "button"),
    ("scripts/main_menu.gd",                  r'_make_button\(("Tutorial")',              "menu.tutorial_button",       "button"),
]
# The intro screen's bullet list is a const Array of bare literals.
CHROME_ARRAY = ("scripts/tutorial_intro_panel.gd", "COVERS", "intro.covers", "bullet")

STR_RE = re.compile(r'"(?:[^"\\]|\\.)*"')


def unquote(lit: str) -> str:
    """GDScript double-quoted literal -> its value (only \\" and \\\\ appear in this corpus)."""
    return lit[1:-1].replace('\\"', '"').replace("\\\\", "\\")


def requote(val: str) -> str:
    return '"' + val.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _pairs(line: str, key: str):
    """Yield literals assigned to `"<key>":` on this line."""
    for m in re.finditer(r'"%s"\s*:\s*(%s)' % (re.escape(key), STR_RE.pattern), line):
        yield m


def _key_at_start(line: str, key: str):
    """Match `"<key>": "..."` only when it OPENS the line.

    Step dict entries are always one per line, so anchoring here excludes the same key
    nested inside a predicate on a `"done"` line - notably
    `"decide": { "kind": "research_unlocked", "title": "High Strength Glassmaking" }`,
    where "title" is a research-node matcher and not copy anyone should be editing.
    """
    return re.match(r'"%s"\s*:\s*(%s)' % (re.escape(key), STR_RE.pattern), line)


def _format_expr(lines: list[str], n: int, tail: str) -> str:
    """The `% <args>` expression after a literal, following it across line breaks.

    `n` is the 1-based line the literal sits on; several bodies carry a `% [` whose
    argument list runs on for two or three more lines.
    """
    m = re.match(r"\s*%\s*(.*)$", tail)
    if not m:
        return ""
    expr = m.group(1).strip()
    i = n                                        # lines[n] is the NEXT source line
    while expr.count("[") > expr.count("]") and i < len(lines):
        expr += " " + lines[i].strip()
        i += 1
    return re.sub(r"\s+", " ", expr).rstrip(",").strip()


def extract_steps() -> list[dict]:
    rows: list[dict] = []
    lines = STEPS_GD.read_text(encoding="utf-8").splitlines()
    rel = str(STEPS_GD.relative_to(REPO))

    active = True                 # steps() ships; _integration_steps() is deferred
    step_id = ""
    chapter = ""
    block = None                  # None | "paragraphs" | "hints" | "targets" | "choices" | "branch"
    idx = 0

    for n, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("#") or stripped.startswith("##"):
            continue
        if re.match(r"static func steps\(", stripped):
            active = True
        elif re.match(r"static func _integration_steps\(", stripped):
            active = False
        elif re.match(r"static func ", stripped) and "steps(" not in stripped:
            block = None

        def add(field, text, key_suffix, fmt=""):
            rows.append({
                "key": f"step.{step_id}.{key_suffix}",
                "file": rel, "line": n, "step_id": step_id, "chapter": chapter,
                "field": field, "active": "TRUE" if active else "FALSE",
                "format_args": fmt, "text": text,
            })

        # --- inside a multi-line block -------------------------------------------------
        if block:
            if stripped.startswith("]") or stripped.startswith("}"):
                block = None
                continue
            if block in ("paragraphs", "hints"):
                for m in STR_RE.finditer(line):
                    add(block.rstrip("s"), unquote(m.group(0)), f"{block}[{idx}]")
                    idx += 1
            elif block in ("targets", "choices"):
                for m in _pairs(line, "label"):
                    add(f"{block.rstrip('s')}_label", unquote(m.group(1)), f"{block}[{idx}].label")
                    idx += 1
            elif block == "branch":
                bm = re.match(r'"(\w+)"\s*:\s*(%s)' % STR_RE.pattern, stripped)
                if bm:
                    add("body_by_branch", unquote(bm.group(2)), f"body_by_branch.{bm.group(1)}")
            continue

        # --- identity ------------------------------------------------------------------
        m = re.match(r'"id"\s*:\s*(%s)' % STR_RE.pattern, stripped)
        if m:
            step_id = unquote(m.group(1))
            continue
        m = re.match(r'"chapter"\s*:\s*(%s)' % STR_RE.pattern, stripped)
        if m:
            chapter = unquote(m.group(1))
            rows.append({
                "key": f"step.{step_id}.chapter", "file": rel, "line": n, "step_id": step_id,
                "chapter": chapter, "field": "chapter",
                "active": "TRUE" if active else "FALSE", "format_args": "", "text": chapter,
            })
            continue

        # --- block openers ---------------------------------------------------------------
        opened = False
        for name in ("paragraphs", "hints", "targets", "choices"):
            if re.match(r'"%s"\s*:\s*\[' % name, stripped):
                block, idx, opened = name, 0, True
                break
        if opened:
            continue
        if re.match(r'"body_by_branch"\s*:\s*\{', stripped):
            block = "branch"
            continue

        # --- single-line copy fields -------------------------------------------------------
        for field in ("title", "body", "cta"):
            m = _key_at_start(stripped, field)
            if m:
                add(field, unquote(m.group(1)), field,
                    _format_expr(lines, n, stripped[m.end():]))
    return rows


def extract_chrome() -> list[dict]:
    rows: list[dict] = []
    for rel, pattern, key, field in CHROME:
        p = ROOT / rel
        for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if line.strip().startswith("#"):
                continue
            m = re.search(pattern, line)
            if m:
                lit = m.group(1)
                tail = line[m.end():]
                fm = re.match(r"\s*%\s*(.+?)\s*$", tail)
                rows.append({
                    "key": key, "file": str((ROOT / rel).relative_to(REPO)), "line": n,
                    "step_id": "", "chapter": "", "field": field, "active": "TRUE",
                    "format_args": fm.group(1).strip() if fm else "", "text": unquote(lit),
                })
                break
        else:
            print(f"WARNING: no match for {key} in {rel}", file=sys.stderr)

    rel, const, key, field = CHROME_ARRAY
    p = ROOT / rel
    inside, i = False, 0
    for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
        if re.match(r"const %s\s*:" % const, line):
            inside = True
            continue
        if inside:
            if line.strip().startswith("]"):
                break
            for m in STR_RE.finditer(line):
                rows.append({
                    "key": f"{key}[{i}]", "file": str(p.relative_to(REPO)), "line": n,
                    "step_id": "", "chapter": "", "field": field, "active": "TRUE",
                    "format_args": "", "text": unquote(m.group(0)),
                })
                i += 1
    return rows


COLUMNS = ["key", "file", "line", "step_id", "chapter", "field", "active", "format_args", "text"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="fail if the CSV is stale")
    ap.add_argument("-o", "--out", default=str(OUT))
    args = ap.parse_args()

    rows = extract_chrome() + extract_steps()
    # chrome first (the screens before the coach starts), then the steps in source order
    out = pathlib.Path(args.out)

    if args.check:
        if not out.exists():
            print("CSV missing", file=sys.stderr)
            return 1
        have = list(csv.DictReader(out.open(encoding="utf-8")))
        same = len(have) == len(rows) and all(
            h["key"] == r["key"] and h["text"] == r["text"] for h, r in zip(have, rows))
        print("in sync" if same else "STALE - re-run without --check")
        return 0 if same else 1

    with out.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=COLUMNS)
        w.writeheader()
        w.writerows(rows)

    steps = {r["step_id"] for r in rows if r["step_id"]}
    live = {r["step_id"] for r in rows if r["step_id"] and r["active"] == "TRUE"}
    fmt = sum(1 for r in rows if r["format_args"])
    print(f"{len(rows)} strings -> {out}")
    print(f"  {len(live)} live steps ({len(steps) - len(live)} deferred), {fmt} format templates")
    words = sum(len(r["text"].split()) for r in rows)
    print(f"  ~{words} words")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
