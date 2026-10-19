# Demo build

The demo is the regular game exported through a Demo preset (`macOS Demo`, `Windows Desktop Demo`,
`Linux Demo`). Each is a copy of its regular preset plus the `demo` feature tag and a longer exclude
list. There is no demo branch. Every PR merged to `main` reaches the demo on its next export.

The export runs from a staged copy of the project, never the project itself. `build_demo.py` clones
it, removes every `# demo:strip` region from the scripts, drops scene nodes whose script is excluded,
parse-checks the copy and boots its autoloads, deletes every excluded file and the dead translation
CSVs, and drops Godot's UID and class caches so the export rebuilds them from shipped files only. Then
it exports. A Demo preset exported straight from the
editor packs nothing and says why.

## What the demo leaves out

Four places decide this. Nothing else should.

| Where | What it holds |
| --- | --- |
| `scripts/demo_build.gd` | The allow-lists and gated sets: demo starts (`START_IDS`), terminal commands (`CHEATS`: `cash`, `unlock all`, `help`), command-line switches (`USER_ARGS`), the gated buildings (`HIDDEN_BUILDING_IDS`, `RECYCLING_BUILDING_IDS`), the recycling goods, and the Recycling research branch. `DemoBuild.active()` is the gate. MatchState reads its sets from here. |
| `tools/demo_build/excludes.txt` | Whole files left out of the export. The tool adds every start file outside `START_IDS` and every authored map document except the active one. |
| `# demo:strip` regions in scripts | Code the demo ships without. A region runs from `# demo:strip` to `# demo:end`; an optional `# demo:keep` part holds the demo's replacement, each line written `#| <code>`. Regions do not nest. |
| `addons/demo_export/demo_data_filter.gd` | Rows taken out of the shipped data files: the gated buildings, the waste goods, the recipes made in those buildings or making or consuming a waste good (a waste by-product is cleared instead), the Recycling and Survey research and the always-hidden research nodes, from `Buildings - buildingsMVP.csv`, `Goods - goodsMVP.csv`, `recipes_all.csv`, `research_unlocks.csv` and `research_presentation.json`. The `Demo export` editor plugin applies it to any preset with the `demo` tag. |

In a demo build:

- `debug CandC` still unlocks the terminal, which holds only `cash <int>`, `unlock all` and `help`.
- `unlock demo` and the other unlocks do not exist, so `demo_is_unlocked()` is always false. The New
  Game locks, the recycling chain, the hidden buildings and advisor loyalty stay off.
- The gated buildings, their recipes and the Recycling research are not in the data files. A demo
  run also skips them at load, so Catalog and ResearchState match the shipped files.
- New Game shows no Advanced Settings section, and only Normal difficulty and the 100-turn length exist.
- No waste good is named anywhere in the shipped files.
- Surveying is gone: every tile starts surveyed, so the dialog, the map mode, the overlay, the animation,
  the survey research and the mechanic in MatchState are stripped (its functions answer "surveyed").
- Nothing after turn 100 ships: Carbon Levy phases 2 and 3 and the coal ban (with the prohibition code),
  the campaign policy timeline, the subsidy wind-down and its notice, and the campaign's victory bar
  and tracks. The 200, 300 and 400-turn lengths are gone.
- Only the three demo advisors ship, without the advisor missions.
- The main menu never creates the Map Editor entry. The editor, `tools/` and its documents are not shipped.
- Review and trace switches (`--stoneshore-review`, `--water-review`, `--trace-*`) are ignored.
- Telemetry reports the version as `<version>-demo`.
- The locked start cards still show, drawn from `data/starts/index.json`. Their start files are not shipped.

## Adding or removing a feature

When a demo export fails the forbidden-text scan, the message names the file and the string. Wrap that
code in a `# demo:strip` region, or exclude the file.


- **New work** is in the demo by default. Do nothing.
- **Keep something out**: wrap its code in a `# demo:strip` region, add its files to `excludes.txt`, or
  gate it with `DemoBuild.active()`. Reach an excluded file only by a path string guarded with
  `ResourceLoader.exists`, or from inside a strip region, never by `preload`.
- `python3 tools/demo_build/build_demo.py stage --keep-excluded` makes the stripped copy and checks it in
  about half a minute, leaving `tools/` in it. Run the demo idle probe there for a full 100-turn game:
  `godot --headless --path <stage> res://tools/demo_idle_probe.tscn --quit-after 60000 -- --start=metal_magnate --as-demo`.
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
pack: excluded files absent, demo starts and data present, no gated rows left in the data files, and
no text from `tools/demo_build/forbidden.txt` or the waste goods' names in any packed file. Compiled
scripts are decompressed for that scan. Comments never ship. It then boots a copy of the macOS app twice
(EULA, then main menu) and requires `[STARTUP] build demo`, the demo's building count from the catalog, and no engine errors. `--platforms macos,linux`
limits the run. `verify` repeats the checks on an existing export.
