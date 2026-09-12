# Tests

Run from the Godot project root (`price-of-everything-0.1/`):

```bash
python3 tools/run_tests.py                          # whole unit suite
python3 tools/run_tests.py --tags market            # one feature
python3 tools/run_tests.py --tags market,stockpile  # any of these tags
python3 tools/run_tests.py --tags production+stockpile   # tests carrying ALL of these
python3 tools/run_tests.py --test market_buy        # tests whose name contains this
python3 tools/run_tests.py --list                   # files, tests and tags; runs nothing
```

`run_tests.py` launches `res://tests/test_runner.tscn` headless and fails the run on any
`SCRIPT ERROR` line as well as on a failed assertion. Anything after the script name is passed
to the Godot runner unchanged (it lands after `--` on the command line).

The e2e balance harness is **not** part of this suite. Run it separately:

```bash
"$GODOT_BIN" --headless --path . res://tests/e2e_stoneshore.tscn -- 100
```

## Layout

| Path | Role |
|---|---|
| `test_runner.gd` / `.tscn` | Discovery runner. Finds every `unit/test_*.gd`, instantiates it, runs each `func _test_*()` in source order, applies the tag filter, prints the summary, sets the exit code. File order is `RUN_ORDER` in the runner (smoke first, then sim core, then views). |
| `test_base.gd` | Base class every unit file extends. Holds `_check(ok, name)`, the shared preloads, helpers used by more than one file, `_await_turn_settled()` and `_boot_main_scene_once()`. |
| `unit/test_<feature>.gd` | One file per feature: smoke, map, production, stockpile, market, power, transport, construction, research, finance, advisors, decisions, events, special_orders, victory, save_load, tutorial, telemetry, goods_views, ui. |
| `scenarios/`, `snapshots/`, `fixtures/` | Data for the e2e harness and fixture-driven tests. |
| `*_test.tscn`, `*_smoke.tscn`, `ui_probe`, `ui_screenshot` | Standalone scene tests. Not run by the runner; launch them directly. |

## Tags

Each unit file declares its feature and, optionally, per-test tag lists:

```gdscript
extends "res://tests/test_base.gd"
const FEATURE := "stockpile"
const TAGS := {
	"_test_exhausted_input_source_falls_back_to_market": ["power", "production", "stockpile"],
}
```

Rules, in order:

1. A test listed in `TAGS` carries exactly those tags.
2. Otherwise it carries `[FEATURE]`.
3. An **empty** tag list (`FEATURE == ""`, or `TAGS[name] == []`) is a **wildcard**: the test is
   treated as relevant to every feature and runs under any `--tags` filter. `test_smoke.gd` is
   wildcard by design, so parse, boot and instantiate checks run on every filtered run.

A test that exercises several systems belongs in the file of its primary subject and lists the
others in `TAGS`. It then shows up under every tag it names. Nothing is duplicated or moved.

## Adding a test

1. Pick the file for the feature under test. Write `func _test_my_thing() -> void:` using
   `_check(condition, "message")`. No registration is needed; the runner discovers it.
2. If the test drives other systems as its subject (not just as a fixture), add a `TAGS` entry
   listing every feature it covers, including the file's own.
3. **Restore global state you touch.** Autoload state is shared across the whole run. Snapshot
   what you mutate and put it back at the end (the price-impact test is the pattern of record).
4. If you call `TurnManager.commit_turn()`, `await _await_turn_settled()` before restoring state:
   resolution yields a frame per phase, and the runner will otherwise wait for it after your test.
5. If you assert on state the main scene seeds (NPC ports, start buildings), call
   `await _boot_main_scene_once()` when it is missing, so the test also holds in isolation.
6. Tests may drive phases directly via `TurnManager.phase_started.emit(...)`; that is a supported
   contract.
7. Good ids vs names: `"coal"` is an internal name, ids are `g_0xx`. Resolve with
   `Catalog.get_good_by_internal_name("coal").get("id")`.

## Isolation the runner provides

Between tests the runner yields one frame (so `queue_free`'d fixtures actually die, and a stale
node in the `hex_map` group is not found first by the next test) and waits for any in-flight turn
resolution to finish. It also yields one frame before the first test so a test may parent a
fixture to the scene root without hitting "Parent node is busy setting up children".

Two perf tests ("road works: zero frames over 8 ms", "B4: ≤2% frames over 8 ms") sit close to
their budgets and can fail on a loaded machine; a failure in only those two is pass-equivalent.
