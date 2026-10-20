# Carbon and Capital

A supply-chain tycoon simulation about the cost of the green transition.

The playable game is the Godot project in **`price-of-everything-0.1/`**.
Use Godot **4.6.2**, with Forward+ for desktop rendering. Windows selects D3D12;
the mobile Compatibility override is not the desktop renderer.

## Repository map

| Path | Purpose |
|---|---|
| `price-of-everything-0.1/` | Active game, runtime data, tests and asset/bake tools |
| `price-of-everything-0.1/docs/content-authoring.md` | Current data-authoring instructions and validation |
| `tools/` | Capsule/trailer/loading artwork and repository maintenance tools |
| `docs/` | Cross-project reviews, licensing and CI notes |
| `archive/` | Retired source/data with provenance; ignored local release archives |
| `outputs/` | Review evidence and generated captures; retain approved results and manifests |
| `price_of_everything/`, root `data/`, root `tests/` | Separate legacy Python prototype, retained for reference |

See the [lifecycle and archive index](docs/project-lifecycle.md) before retiring material.

## Licence

Carbon and Capital is proprietary commercial software. The [repository licence](LICENSE)
allows private personal use and modifications, plus gameplay videos and streams
(including monetized ones). Redistribution of the game, its code or its assets
requires separate permission. Official future demos also ship with the
[Demo EULA](price-of-everything-0.1/data/legal/demo_eula.txt).

Earlier MIT grants and third-party licences remain valid; the
[previous MIT notice](docs/legal/PREVIOUS-MIT-LICENSE.txt) is preserved for earlier material.
There is no public mod distribution policy yet.

## Startup check

The [demo startup workflow](.github/workflows/demo-startup.yml) exports a Linux release
and checks fresh and previously accepted EULA launches for Godot errors. See
[the startup check guide](docs/ci-startup-check.md) for its scope and local commands.

## Editing game data

Follow [content authoring](price-of-everything-0.1/docs/content-authoring.md).
The authoritative goods, buildings and recipes are the tables loaded by
`price-of-everything-0.1/scripts/catalog.gd`. Edit **`data/recipes_all.csv` within
the Godot project** directly, preserving IDs and existing columns. The former
master/bootstrap and rebalance outputs are [archived](archive/legacy-recipes/README.md).

The root Python CLI reads a different, historical dataset. Its validation result
does not describe the game. Its old commands and tests are documented in
[the prototype guide](docs/legacy-python-prototype.md).

## Game verification

From `price-of-everything-0.1/`:

```sh
godot --headless --path . res://tools/parse_check.tscn
python3 tools/run_tests.py
# Also required for simulation, economy or content changes:
godot --headless --path . res://tests/e2e_stoneshore.tscn -- 100
```

See [test instructions](price-of-everything-0.1/tests/README.md),
[demo exports](price-of-everything-0.1/docs/demo-build.md) and
[load-time bakes](price-of-everything-0.1/docs/load-time-bakes.md).
