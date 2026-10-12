# Project instructions

## GUI applications
- Run Godot scripts, tests, imports and exports with `godot --headless`.
- Run Blender with `blender -b` / `--background`.
- Only open a Godot window when explicitly requested or required for rendering. For rendered checks and bakes, use `AGENT_GODOT_WINDOW=1 godot ...` through the shim so focus returns to the user's app.
- Never open a GUI editor merely to run a script. If explicitly opening an app, use `open -g -a <App>`.

## Bakes are part of completing a change
- If a change invalidates a bake, regenerate the affected bake and install it in the project's runtime asset location before declaring the work complete. Do not leave the user to pay the rebuilding cost during game startup or when opening the supply-chain view.
- Check dependencies first: placement, road/rail planning, terrain, scenery, and streamed detail can have separate bakes. Reuse valid resources; do not delete caches or regenerate unrelated assets indiscriminately.
- Use the production bake pipeline in `price-of-everything-0.1/tools/supply_chain_3d/` and the instructions in `price-of-everything-0.1/docs/load-time-bakes.md` and `price-of-everything-0.1/docs/supply_chain_3d.md`. A focused screenshot render does not refresh the production package.
- After baking, validate the package and launch a fresh process against it. Verify current fingerprints, bundled cache hits, absence of unexpected runtime bake writes, and startup/first-open timings. A warm cache in the baking process alone is not sufficient proof.
- Check that expensive preparation runs after a usable cache lookup, rather than being repeated before every lookup. Keep cold generation separate from normal loading.
- Report the measured load times and bake verification with the change. If baking or verification fails, state that explicitly; do not describe the change as ready for normal play.
