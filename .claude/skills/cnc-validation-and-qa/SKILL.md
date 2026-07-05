---
name: cnc-validation-and-qa
description: Load this before declaring ANY change done in price-of-everything, when adding tests, when a test fails, or when you need to verify UI visually. Defines what counts as evidence here - the unit suite, the e2e balance harness (NOT run by the unit runner - it has rotted silently before), and windowed screenshot verification - with exact commands, the shot-tool authoring pattern, and how to add tests safely.
---

# Validation and QA — what counts as evidence

House discipline: **paste the actual verification output. "It should pass" is not done.**
A change is done when the relevant legs below are green and shown.

## The three legs (exact commands, run from the Godot project root)

```bash
cd "/Users/crisu/Price of Everything/price-of-everything/price-of-everything-0.1"
```

### Leg 1 — unit suite (every change)
```bash
python3 tools/run_tests.py
```
- Custom zero-dependency harness (not GUT/gdUnit4): runs
  `res://tests/test_runner.tscn` headless; exit 0 = all pass, 1 = any fail.
- Count as of 2026-07-05: **1165 passed, 0 failed**. The count grows; a *drop* in the
  pass count without a matching test edit is a red flag.
- Auto-locates the Godot binary (falls back to `$GODOT_BIN`); known-good local binary:
  `/Users/crisu/Desktop/Godot.app/Contents/MacOS/Godot` (4.6.2).
- Trailing "RIDs leaked / ObjectDB instances leaked" warnings at exit are normal for
  the headless UI tests — the PASS/FAIL count is the verdict.

### Leg 2 — e2e balance harness (any sim/economy/content change)
```bash
"$GODOT_BIN" --headless --path . res://tests/e2e_stoneshore.tscn -- 100
```
- **NOT part of run_tests.py — you must run it explicitly.** It once rotted to 86
  failing assertions before anyone noticed (fixed in commit `674e4dc`). That story is
  why this leg exists as a separate habit.
- Current expected result (2026-07-05): **598 passed, 4 failed** — the 4 are *standing
  balance gaps*, not harness bugs:
  1. "coal runway is recently post-tax profitable before expansion"
  2. "last 10 turns are post-tax profitable"
  3. "cumulative post-tax profit is positive"
  4. "optimized motor chain increases cash after buildout"
  They are the measured form of the solved-economy/profitability problem
  (see `cnc-balance-campaign`). **Never "fix" them by weakening assertions.** Your
  change is suspect if it *changes* the failure set in either direction without an
  explanation you can defend.
- It prints a metrics JSON line (`[E2E] latest metrics: {...}`) — cash curves, slow
  turns with per-phase profiler breakdowns, load/ready ms. Quote it in balance notes.
- Scenario config: `tests/scenarios/open_field_1.json`; perf baseline:
  `tests/snapshots/e2e_benchmark_baseline.json`.

### Leg 3 — windowed screenshot (any UI change)
Screenshots need a window — **do not use `--headless`**:
```bash
"$GODOT_BIN" --path . res://tools/market_shot.tscn --quit-after 900
```
Shot-tool inventory (as of 2026-07-05, all under `tools/`):

| Tool | Shows |
|---|---|
| `farm_shot` | farm visuals (writes res://farm_shot.png) |
| `real_tile_shot`, `enclosure_shot` | tile/enclosure rendering |
| `ledger_shot` | building ledger with seeded RAG variety (/tmp/poe_ledger.png) |
| `people_shot` | People panel labour indicator |
| `market_shot` | market tab incl. price-impact columns + bracketed base prices |
| `council_shot` | advisors roster + picker + labour spectrums |
| `ui_improvements_shot` | port dockhouse glyph + money-panel Sales tab |
| `surplus_toggle_shot` | Sell-all-Surplus toggle + its confirm dialog |
| `pipe_warning_shot` | fluid pipeline warning row/badge in the building panel |

**Authoring a new shot tool** (the proven skeleton):
```gdscript
extends Node   # tools/my_shot.gd  + a 5-line .tscn wrapping it
func _ready() -> void:
    var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
    add_child(game)
    await _settle(140)                       # map build + intro settle FIRST
    # seed state via the sim API (MatchState.add_building / Stockpile.add / cheats)
    var cam := get_viewport().get_camera_2d()
    cam.edge_pan_enabled = false             # corner-idling mouse would fight tweens
    # open panel / pan camera, then:
    get_viewport().get_texture().get_image().save_png("/tmp/poe_my_shot.png")
    get_tree().quit(0)
func _settle(n: int) -> void:
    for _i in n: await get_tree().process_frame
```
Traps already hit: panning before frame ~140 gets overridden by the post-load camera
configure; edge-pan cancels tweens; panels may need `position` set to be on-screen.

## Adding a unit test

1. Open `tests/test_runner.gd`; write `func _test_my_thing() -> void:` using the
   `_check(condition, "message")` helper; register it in the call list near the top
   (search the existing `_test_...()` invocations).
2. **Restore global state you touch.** The suite shares autoload state across tests.
   Example of record: the price-impact test snapshots `MarketState.prices`, runs
   `tick_turn()` several times, then restores the snapshot and re-emits
   `prices_updated` (see `_test_price_impact_thresholds`).
3. Tests may drive phases directly via `TurnManager.phase_started.emit(...)` — that is
   a supported contract (sim hooks stay connected to the signal).
4. Good ids vs names: `"coal"` is an *internal name*; ids are `g_0xx`. Resolve via
   `Catalog.get_good_by_internal_name("coal").get("id")` — an id/name mixup produced a
   6-check false failure cascade once.
5. Regression tests are named for their story, e.g.
   `_test_construction_reorder_ignores_foreign_inbound`.

## What the suite does NOT catch (know the blind spots)

- **Data integrity**: the catalog's promotion gate silently drops invalid recipes;
  research conditions can be dead; nothing asserts CSV cross-references. Spot-check via
  `cnc-content-pipeline`'s checklist. (This blind spot shipped 95 dead research nodes.)
- **Balance**: the suite passes while the economy is broken — that's what Leg 2's
  metrics and `cnc-balance-campaign` are for.
- The repo-root Python validator (`python -m price_of_everything`) validates a **stale,
  separate dataset** and currently exits 1 with 16 issues — its failures are NOT about
  the live game data. Don't chase them.

## Definition of done by change class

| Change | Required evidence |
|---|---|
| Pure UI | Leg 1 + Leg 3 screenshot |
| Sim/code fix | Leg 1 + Leg 2 (failure set unchanged) |
| Content add | Leg 1 + Leg 2 + content checklist (`cnc-content-pipeline`) |
| Balance change | All of the above + before/after metrics + `cnc-balance-change-control` note |

## When NOT to use this skill
- Deciding whether a change *needs* gating → `cnc-balance-change-control`
- Designing balance experiments/sweeps → `cnc-balance-campaign`
- A test fails and you're triaging why → `cnc-debugging-playbook`

## Provenance and maintenance
Compiled 2026-07-05; counts and the 4 standing e2e failures re-verified that day.
- Re-check counts: run Leg 1 and Leg 2 above.
- Re-check shot inventory: `ls price-of-everything-0.1/tools/*_shot.tscn`
- Re-check the standing-failure list: Leg 2 output, grep `FAIL`.
