# Demo build

The demo is the regular game exported through a Demo preset (`macOS Demo`, `Windows Desktop Demo`,
`Linux Demo`). Each is a copy of its regular preset plus the `demo` feature tag and a longer exclude
list. There is no demo branch. Every PR merged to `main` reaches the demo on its next export.

## What the demo leaves out

Three places decide this. Nothing else should.

| Where | What it holds |
| --- | --- |
| `scripts/demo_build.gd` | The allow-lists and gated sets: demo starts (`START_IDS`), terminal commands (`CHEATS`: `cash`, `unlock all`, `help`), command-line switches (`USER_ARGS`), the gated buildings (`HIDDEN_BUILDING_IDS`, `RECYCLING_BUILDING_IDS`), the recycling goods, and the Recycling research branch. `DemoBuild.active()` is the gate. MatchState reads its sets from here. |
| `tools/demo_build/excludes.txt` | Whole files left out of the export. The tool adds every start file outside `START_IDS` and every authored map document except the active one. |
| `addons/demo_export/demo_data_filter.gd` | Rows taken out of the shipped data files: the gated buildings, their recipes, recipes that make or consume a recycling good, the Recycling research branch and the always-hidden research nodes, from `Buildings - buildingsMVP.csv`, `recipes_all.csv`, `research_unlocks.csv` and `research_presentation.json`. Goods rows stay, because the market prices every good. The `Demo export` editor plugin applies it to any preset with the `demo` tag. |

In a demo build:

- `debug CandC` still unlocks the terminal, but only `cash <int>`, `unlock all` and `help` run.
- `unlock demo` and the other unlocks do not exist, so `demo_is_unlocked()` is always false. The New
  Game locks, the recycling chain, the hidden buildings and advisor loyalty stay off.
- The gated buildings, their recipes and the Recycling research are not in the data files. A demo
  run also skips them at load, so Catalog and ResearchState match the shipped files.
- New Game shows no Advanced Settings section. The default difficulty and speed still apply.
- The main menu never creates the Map Editor entry. The editor, `tools/` and its documents are not shipped.
- Review and trace switches (`--stoneshore-review`, `--water-review`, `--trace-*`) are ignored.
- Telemetry reports the version as `<version>-demo`.
- The locked start cards still show, drawn from `data/starts/index.json`. Their start files are not shipped.

## Adding or removing a feature

- **New work** is in the demo by default. Do nothing.
- **Keep something out**: gate it with `DemoBuild.active()` or add its files to `excludes.txt`. Reach an
  excluded file only by a path string guarded with `ResourceLoader.exists`, never `preload`.
- **Bring something in**: delete its lines from `excludes.txt` or its gate in `scripts/demo_build.gd`.

After changing a regular preset, the version, or `excludes.txt`, run:

```bash
python3 tools/demo_build/build_demo.py sync
```

`tests/unit/test_demo_build.gd` (`--tags demo_build`) and the CI `check` step fail when the Demo presets
are stale, or when shipped code preloads a file the demo leaves out.

To play or test the demo from the editor, add `--as-demo` after `--` (the editor's main run arguments, or
`python3 tools/run_tests.py --as-demo`). The switch works only where the `editor` feature exists, so an
exported build ignores it. A suite run with it loads the catalog without the gated rows. Compare its
failures with a normal run: only tests that use recycling or the hidden buildings should differ.

## Exporting

```bash
python3 tools/demo_build/build_demo.py export --zip
```

This syncs, exports all three platforms to `~/Desktop/Carbon and Capital Demo builds/`, and checks each
pack: excluded files absent, demo starts and data present, no gated rows left in the data files. It then boots a copy of the macOS app twice
(EULA, then main menu) and requires `[STARTUP] build demo`, the demo's building count from the catalog, and no engine errors. `--platforms macos,linux`
limits the run. `verify` repeats the checks on an existing export.
