# Demo build

The demo is the regular game exported through a Demo preset (`macOS Demo`, `Windows Desktop Demo`,
`Linux Demo`). Each is a copy of its regular preset plus the `demo` feature tag and a longer exclude
list. There is no demo branch. Every PR merged to `main` reaches the demo on its next export.

## What the demo leaves out

Two places decide this. Nothing else should.

| Where | What it holds |
| --- | --- |
| `scripts/demo_build.gd` | Runtime allow-lists: the demo starts (`START_IDS`), the terminal commands (`CHEATS`: `cash`, `unlock all`, `help`), the command-line switches (`USER_ARGS`). `DemoBuild.active()` is the gate. |
| `tools/demo_build/excludes.txt` | Files left out of the export. The tool adds every start file outside `START_IDS` and every authored map document except the active one. |

In a demo build:

- `debug CandC` still unlocks the terminal, but only `cash <int>`, `unlock all` and `help` run.
- `unlock demo` and the other unlocks do not exist, so `demo_is_unlocked()` is always false. The New
  Game locks, the recycling chain, the hidden buildings and advisor loyalty stay off.
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

## Exporting

```bash
python3 tools/demo_build/build_demo.py export --zip
```

This syncs, exports all three platforms to `~/Desktop/Carbon and Capital Demo builds/`, and checks each
pack: excluded files absent, demo starts and data present. It then boots a copy of the macOS app twice
(EULA, then main menu) and requires `[STARTUP] build demo` with no engine errors. `--platforms macos,linux`
limits the run. `verify` repeats the checks on an existing export.
