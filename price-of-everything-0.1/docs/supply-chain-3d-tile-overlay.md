# 3D continent: shipped base plus changed tiles only

## Rule

The game never bakes or lays out the whole continent at runtime. The shipped package is the base world, built for the default start (`data/starts/metal_magnate.json`). A tile is prepared at runtime only when its contents differ from that base, and then only that tile.

A typical game diverges on a handful of tiles per turn: 6–8 tiles on turn 1 of a different start, a few more per turn after that.

## Why the current path is slow

Before this change, any difference from the base world rejected the bundled world snapshot. The board then ran the full continent pipeline: the layout solve for 600 tiles (about 10 minutes), the road and rail solve (about 2.5 minutes), and a bake of every tile, because every bake key hashes the whole map. A 40-building company took 22 minutes before "Show all tiles" could open.

The 3D board rebuilds on every turn, building and infrastructure change (`empire_view.sim_changed`), and each rebuild restarts continent preparation. Ending turns without building keeps the snapshot valid. Any building change does not.

A model dump after adding 36 buildings on 12 tiles showed real geometric change on 18–19 tiles: the 12 built on and a few neighbours. All other differences were map-wide running IDs (`z_back:<tile>:<n>`, road `original` indices) and one shared random sequence, not layout coupling.

## Divergence

A tile diverges when its **identity signature** differs from the base:

- the non-decor standing items (`building`, `site`, `warehouse`, `suppliers`, `port`, pylon): instance id, kind, internal name, level, owner;
- the tile record fields that drive layout: `store`, `level`, `paved`, `polluters`, pylon.

Decor houses, roads and running IDs are outputs, not inputs, and are never compared.

The live signature comes from `Model.build` over the live graph (seconds). The base signature comes from the bundled snapshot model.

## Pipeline when the snapshot does not match

1. Load the bundled snapshot, transport, scenery and continent bakes, exactly as for a match.
2. Compute the divergent set D.
3. Lay out a sub-model covering D, using the same pass chain as the company view, which already lays out any tile subset. Take results only for tiles in D.
4. Merge into the base model. In D tiles: standing items, neighbourhood items, district plots and tile records come from the sub-model. Everywhere else: the base. Goods flows are always live, rerouted on the base roads.
5. Scenery for D, plus its neighbours for shadows that cross hex edges: tree placements, greenery, building and tree shadows, plazas, standing frames, foundations. Everything else comes from the base scenery bake.
6. Tile resources: D tiles leave the progressive manifest, so they never load stale bundled terrain. Their base-chunk and terrain keys include the tile's own standing, shadows and plazas, so they bake at runtime once and then hit the player's cache. Every other tile loads from the package unchanged.
7. Far view: the base continent bake. Decor sprites for D tiles are swapped for D's houses. Buildings are live standing nodes.

## Company view

The company view (not "Show all tiles") uses the same overlay. Each rebuild,
whether from a turn, a building or an infrastructure change, does this:

1. Detection runs over the company tiles and the tiles its routes and pylons cross. A probe `Model.build` takes about 60 ms.
2. Each divergent tile is laid out alone, with the shipped roads of that tile.
   - The result is remembered for the session, keyed by the tile's identity (`TileOverlay._solved_tiles`).
   - A tile that diverged on an earlier turn is not laid out again when another tile changes.
3. `TileOverlay.restrict` cuts the merged world down to the company. It takes roads and rail segments from a per-session index of the shipped world (`TileOverlay.index`), not a scan of the continent.
4. Terrain and road meshes are keyed per tile (`tile_scope_key`): the tile's own roads, rails, nearby depots and stations, and pits. A change on one tile re-bakes that tile and its neighbours, never the whole company.
5. Trees are remembered per tile for the session. Scenery yields a frame between its stages.
6. Road alignment (switchbacks, cuttings, tunnels) is remembered per road chain for the session (`road_alignment_memo.gd`).
   - A chain is keyed by everything its solve reads: its own roads, the heights along it (terrain, mine pits, depots) and, only for its steep stretches, the roads, reserved bends, buildings and company tiles within reach of a reroute.
   - After a bake hit the memo is seeded in idle frames, one slice at a time (about 0.35 s of idle on the Metal Magnate start, frames under 65 ms).
   - A rebuild with new roads first solves the chains the memo lacks, a slice per frame (`presolve_alignment`). `prepare_transport` then only reads the memo, and the result is byte-identical to a full solve (checked by the rebuild profile and by `test_supply_chain_3d_alignment_memo.gd`).
7. Road meshes the cache lacks are baked one tile per frame before infrastructure is assembled (`prebake_roads`).

Goods routes are not part of this cost. Flows are rerouted on the existing roads in milliseconds whatever their destination. A building on a new tile costs road work only because that tile's roads come into view. A route that crosses tiles outside the company brings those tiles into view too, and only their chains are solved.

Measured on the Metal Magnate start (`tools/supply_chain_3d/trials/company_rebuild_profile.tscn`):

| Change | Before | Now | Worst frame |
| --- | --- | --- | --- |
| First open | about 20 s (full re-layout) | 3.3 s, 0 cache misses | |
| Building on an existing company tile | 20 s | 2.1 s | 0.4 s |
| Second building on the same new tile | 20 s | 1.7 s | 0.25 s |
| Building on a tile new to the company | 20 s | 5.0 s | 0.56 s |

For a tile new to the company, 16 of 180 road chains are solved: those on the new tile and on the hill tile next to it, whose bends may now enter it. The rest of the transport step (key, grading, rail) still runs in one frame of about 0.5 s, and each new road mesh takes a frame of about 0.4 s.

The company-start supplement must be baked until it settles. The layout memo the tool writes back can move border roads on the next build. `bake_company_start` reports `settled`; run it again until it is `true`, and then drop auxiliary keys the current start no longer uses (`tools/supply_chain_3d/trials/company_key_probe.tscn` lists the required ones).

## Streaming changed tiles before the far backdrop

A changed tile is not in the progressive manifest, so it streams through the repair path in `world_builder.gd`. When it is wanted before the far backdrop has loaded, it bakes its own medium terrain and shows it at the lowest tier, as packaged tiles do; `install_backdrop()` later swaps in the continent's. The repair path used to call `prepare_continent()` there, which reset `base_ready`, held the board in overview mode, and stopped all local tile streaming for the rest of the session.

The first time, each changed tile and each neighbour whose shadows changed bakes its terrain at about 1–3 s per tile. With 30 buildings on 15 new tiles, 50 tiles bake: about 36 s near the company and 45 s for the medium view. The bakes go to the player's cache; on the next launch the same views stream in 3–9 s.

## Limitations in the first version

- Roads, rails, pipes and cables stay at the base layout on the continent: no new access stubs for new buildings, and no new player lines. The company view still shows them.
- The far ground texture keeps base shadows and plazas for D tiles.

## Verification

- Default start: snapshot match unchanged, zero runtime bakes.
- Heavy scenario, 36 buildings on 12 tiles: D is about 12–19 tiles, no 600-tile solve, a few runtime tile bakes, continent ready in seconds. Captures of changed and unchanged tiles.
- Ending turns with no building: no divergence.
- Unit tests for divergence detection and merge.
