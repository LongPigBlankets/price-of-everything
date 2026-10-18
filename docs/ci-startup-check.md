# Demo startup check

`Demo startup / Linux release startup` runs on pull requests to `main`, pushes to
`main`, tags and manual dispatch. It uses GitHub's Ubuntu runner, Godot 4.6.2 and
the production `Linux` release export preset. Checkout includes Git LFS assets.
Engine downloads and Actions are pinned; the job has read-only repository access.

CI ignores the workbench `artifacts`, `docs`, `reports`, `tests` and `tools`
folders during import; all are already excluded by the release presets. Imported
resources are cached by engine version and asset/configuration content. Godot's
import validation still runs after every restore; the UID and script class caches
are generated fresh. Autoloads use explicit script paths so a cold clone does not
need an existing UID cache just to start the import.

The first cold import compresses thousands of Basis textures and can take tens of
minutes. Later runs can reuse the import cache. Import, export and runtime are
separate steps with bounded timeouts and retained diagnostics.

The single smoke check boots the exported executable twice, using disposable
data next to a copied binary and a separate working directory outside the source
tree. The first launch must show the EULA without accepting it. The second uses
a matching acceptance fixture and must reach the normal main menu. Neither launch
sends telemetry. No auto-accept flag is added to the game.

Each launch runs for 1,200 frames at a maximum of 60 FPS (about 20 seconds after
startup), then exits normally. The runner requires the appropriate readiness
message, exit code zero, a fresh engine log and no engine, script or parser errors
in either stdout/stderr or the engine log. A launch exceeding 120 seconds fails.
There is no error allowlist. Logs and a JSON summary, including the tested
executable's SHA-256, are retained as Actions artifacts for 14 days.

The initial test covers exported resource availability, autoloads, the EULA and
main menu. It does not start a new match, test GPU rendering, or validate Windows,
macOS, store integration or the whole unit suite. Import/export logs are retained;
the strict error gate applies to the two runtime launches. Import/export must
also exit successfully.

There is currently no automated release publication workflow to gate. This job
does not publish binaries or prevent manual store uploads. Before a release,
require a successful check for the exact release commit/tag. A future publication
job should depend on `startup` and publish the same tested artifact; branch
protection can separately require this check before merging.

## Run locally

From the repository root, on Linux with Godot 4.6.2 and its export templates:

```sh
python3 -m unittest discover -s tools/ci -p 'test_*.py' -v
mkdir -p /tmp/cnc-demo-build
godot --headless --path price-of-everything-0.1 --editor --import --quit
godot --headless --path price-of-everything-0.1 --export-release Linux /tmp/cnc-demo-build/carbon-and-capital.x86_64
python3 tools/ci/run_startup_smoke.py --executable /tmp/cnc-demo-build/carbon-and-capital.x86_64 --logs /tmp/cnc-startup-new-run
```

Choose a new logs directory for every run. A release template with an embedded
PCK is required; running the editor against source does not validate the export.
