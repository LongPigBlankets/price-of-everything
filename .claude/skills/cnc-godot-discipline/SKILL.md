---
name: cnc-godot-discipline
description: Load this when writing or debugging ANY Godot-side code in price-of-everything - UI panels, map layers, input handling, headless tooling, CSV edits, or when a Control/layout/tooltip/click behaves strangely. It is the Godot-4.6.2 playbook for THIS repo, where several default Godot instincts are actively wrong and each has already cost real debugging time. Not for sim-logic questions.
---

# Godot discipline — where "knowing Godot" hurts you here

Pinned to **Godot 4.6.2** (project declares 4.6; GL Compatibility renderer; Jolt physics).
Stay on 4.6.x — 4.x minors have real API drift. A junior who "knows Godot" is more
dangerous than one who doesn't, because the default instincts below all violate this
project's architecture or have bitten before. Every item here is a documented incident.

## The gotcha table (each one cost real time in 2026)

| Instinct / surprise | Reality here | Pattern of record |
|---|---|---|
| "A Button can hold a VBox of content" | **Buttons do NOT size to child containers** — children don't contribute minimum size, so content clips (seat cards' CTA was cut off) | Clickable cards are `PanelContainer`s with a hand-wired `pressed` signal: `_ClickCard` inner class in `scripts/advisor_council_tab.gd` |
| "I'll reference my new class by `class_name`" | **`class_name` is not registered in fresh headless runs** (no editor rescan) — tests die with "Identifier not found" | `const XScript := preload("res://scripts/x.gd")` then `XScript.new()`; see `AdvisorCouncilTabScript` in `scripts/people_panel.gd` |
| "Typing a number into a SpinBox applies it" | It applies on **Enter/focus-out** only, by default | `spin.update_on_text_changed = true` (house rule for all quantity inputs) |
| "TileMap" | Deprecated here — the map is a **`TileMapLayer`** (`scripts/hex_map.gd`) | — |
| "tile coords == map cells" | Tile coord = map cell − `MAP_PADDING` (2). Tile ids are `"tile_X_Y"`, **1-based** | Always convert via `map_coord_for_tile_coord()` / `tile_coord_for_map_coord()`; camera pan bug happened by skipping this |
| "mouse click on UI is consumed" | UI consumes the **press**; the **release** often falls through to `_unhandled_input` | Tile clicks fire on release AND require the press to have reached the map (`hex_map._click_armed`) — don't undo this |
| "scripted runs behave like play" | In windowed scripted runs the mouse idles at the window corner → **edge-pan fires every frame** and cancels camera tweens | Shot tools set `cam.edge_pan_enabled = false` first |
| "child Node2D draws above siblings" | A `TileMapLayer`'s later-added sibling layers (hills etc.) can paint over your child layer | Set `z_index` explicitly (port dockhouses use `z_index = 60`, `scripts/world_map.gd`) |
| "`arr_of_packed[i][j] = x` writes back" | Indexing a packed array held inside an Array returns a COW copy — the write is lost | Pull into a local, mutate, reassign — or use plain Arrays |
| "I can skip the .uid files" | Every new `.gd` gets a generated `.uid`; uncommitted ones churn everyone's tree | **Commit `.uid` files** alongside their scripts |
| "I must disconnect signals on free" | Godot 4 auto-disconnects signals from freed objects | Panel-local `connect`s are safe; no teardown boilerplate needed |
| "editor perf numbers are representative" | Debug runtime + editor overhead distort everything | Benchmark headless or exported release; see `cnc-performance-playbook` |
| "£ is just a character" | A double-encoding once shipped `Â£` to players (`_money_text`) | After any money-string edit: `grep -rn "Â" price-of-everything-0.1/scripts/` must be empty |

## Rendering rules (map scale)

- **Never node-per-entity** for map content. Buildings render via packed drawing in
  `scenes/building_visuals.gd`; decoration layers use custom `_draw()` (exemplar:
  `scripts/survey_overlay.gd` — signal-driven redraws, merged `ArrayMesh` fills, no
  `_process`). Hills are baked offline (`data/hills_baked.json`, MD5-staleness-checked)
  and rendered with cached meshes + a far-zoom texture LOD (`scripts/hill_visuals.gd`).
- `_process`/`_draw` must contain zero sim logic (architecture rule 2) and should be
  event-gated: `set_process(false)` when idle, `queue_redraw()` only on change signals.
- No C# — it would break web export (the GL Compatibility choice exists for browser
  reach). Escalation for genuinely hot paths is a measured decision, not a default.

## Editing the data CSVs safely

The runtime CSVs (`price-of-everything-0.1/data/`) are **CRLF**. Hand-editing in an
LF editor rewrites every line. Procedure:

```bash
cd "/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1"
python3 - <<'EOF'
import csv
path = 'data/recipes_all.csv'
rows = list(csv.reader(open(path, newline='')))
hdr = rows[0]; col = hdr.index('requirements')
for r in rows[1:]:
    if r and r[0] == 'r_016':
        r[col] = 'deposit:lithium_ore'
with open(path, 'w', newline='') as f:
    csv.writer(f).writerows(rows)
EOF
git diff -- price-of-everything-0.1/data/recipes_all.csv   # MUST show exactly your row(s)
```
If the diff shows the whole file changed, you broke line endings — revert.

## Headless vs windowed

- Tests and the e2e harness run `--headless`. Anything editor-only in a runbook is a defect.
- UI verification is **windowed** (screenshot tools can't capture headless):
  `"$GODOT" --path . res://tools/<x>_shot.tscn --quit-after 900`. Authoring pattern and
  inventory: `cnc-validation-and-qa`.
- `--check-only --script foo.gd` false-positives on autoload identifiers (`DS`, etc.) —
  single-file checks can't see autoloads. The scripts-parse unit test (full context) is
  the real parse gate.

## When NOT to use this skill
- Sim invariants (determinism, saves, turn order) → `cnc-architecture-contract`
- Panel styling, theme tokens, refresh doctrine → `cnc-ui-and-theming`
- Adding content to the CSVs (schemas, gates) → `cnc-content-pipeline`

## Provenance and maintenance
Compiled 2026-07-05; every row in the gotcha table traces to a 2026 incident in this
repo (see `cnc-failure-archaeology` for the stories). Re-verify:
- Godot version pin: `grep -n "config/features" price-of-everything-0.1/project.godot`
- `_ClickCard` still the card pattern: `grep -n "_ClickCard" price-of-everything-0.1/scripts/advisor_council_tab.gd`
- MAP_PADDING: `grep -n "MAP_PADDING" price-of-everything-0.1/scripts/hex_map.gd`
- CRLF still true: `file "price-of-everything-0.1/data/recipes_all.csv"` (shows CRLF)
