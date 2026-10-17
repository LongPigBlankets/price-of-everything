# First-use stutters and video memory — 17 October 2026

Follows the [stream-ready installation](stream-ready-2026-10-16.md). Same package, same machine (Godot 4.6.2, Forward+/Metal, Apple M5 Pro, 1920×1080 window).

## What caused the stutters

Each slow frame was split into draw time, traced script spans and pipeline compilations (`tools/supply_chain_3d/trials/profile_hitches.tscn`), with native `sample` runs to confirm. Draw time was 1–5 ms in almost every slow frame. The stalls were main-thread script work:

| Stall | Cause |
|---|---|
| 280 ms, first continent open | `HarbourTraffic.create` planned every harbour's ship routes in one frame (about 1,000 shoreline height probes each) |
| 137 ms, first closest zoom | `_update_asset_tier` created every near model in one call (234 mesh pipelines) |
| 30–60 ms, entering a new area | The shared terrain sampler files each tile's shores, steps and hill rises on the first height query near it (8–75 ms per tile). Decorative foundations, cars and harbours paid for it |
| 10–33 ms, during the first open | `_update_cars` walked every car on the continent every frame |
| 20–35 ms, leaving an area | `release_local_tiles` freed whole tile subtrees at once |
| Every frame | `_draw_labels` copied and sorted every continent label |

`ground.gd` and `empire_board_ground.gd` are bake inputs, so the terrain sampler itself was not changed.

## Changes

- Harbours plan routes only for tiles with local detail, one harbour per frame. Routes are planned ahead during idle terrain warming.
- On the continent, near models and medium cards are created within a 6 ms per-frame budget. A deferred model shows its far card until it exists. The colour reveal waits until none are pending. The company view and direct builder use stay unbudgeted.
- Idle terrain warming: one tile per frame, nearest the camera first, only while the camera is still and the last frame took under 20 ms. On the company view it warms the prepared continent outward from the company, before the first open.
- Cars are indexed by tile; only cars on detail tiles are touched.
- Released tiles are hidden and their colliders freed at once; the rest is freed in 3 ms slices.
- Label order is sorted only when the labels or the selection change.
- Foundation edges reuse each step's far sample (identical geometry, half the height queries).

## Results

Fresh process, empty runtime cache, zero bake misses or writes in every run.

Official `profile_streaming_ready` run, opening the continent immediately:

| View | Worst frame before → after | Settled before → after |
|---|---:|---:|
| First open | 307 → 135 ms | first revealed tile 2.78 → 2.46 s |
| Closest first detail | 157 → 34 ms | 396 → 264 ms |
| Medium adjacent pan | 64 → 64 ms | 633 → 683 ms |
| Mountain-region jump | 58 → 58 ms | 1,650 → 1,678 ms |

These medium jumps teleport into cold areas, so terrain warming has no still moment to work in. With four seconds on the company view first (the trial's `--owned-dwell=4`), as a player would:

| View | Worst frame |
|---|---:|
| First open | 64–73 ms |
| Closest first detail | 35 ms |
| Medium views and pans | 17–25 ms |
| Continuous panning, medium and closest | 16–24 ms (mean 7 ms) |

Captures match the previous run within the animation noise between two unchanged runs (0–0.3% of pixels).

## Video memory

Godot's `RENDER_TEXTURE_MEM_USED` monitor wraps negative here. These figures use `RenderingDevice.get_memory_usage(MEMORY_TOTAL)`.

| Point | Total |
|---|---:|
| Start-up | 110 MB |
| Game loaded, 3D view not opened | 3,800 MB |
| After the continent's first open | 5,000 MB |
| After touring the map | 5,400–5,800 MB |

So about 3.7 GB is in use before the 3D view opens. A census of textures reachable from the scene tree and script statics accounts for 2.4 GB of it:

| Group | Size | Format |
|---|---:|---|
| 2D map per-tile roads + fabric art (`assets/authored_map/stoneshore-procedural`, about 800 textures in a static cache) | 1.4–1.6 GB | 540×640 RGBA8, uncompressed, mipmapped |
| 3D medium building sprite atlases | 320–520 MB | 2048×640 RGBA8, uncompressed |
| Runtime 2D fabric textures (`authored_fabric_visuals.gd`) | 169 MB | uncompressed |
| 3D terrain tiles (retained cache) | 80–600 MB | compressed |
| Far sprites, hill bake, 2D roads atlas, icons | about 300 MB | mostly uncompressed |

The rest is render targets, buffers and textures not reachable by the census. The 3D board renders into a 4× MSAA SubViewport at physical pixel density, which on a Retina display has four times the pixels of this test window.

### Tile residency policy (built)

- Offscreen 5 s: closest detail is dropped and medium is kept. This also applies to nearby tiles, which are never released.
- Offscreen 10 s: released.
- Tiles with the company's buildings keep closest detail for 20 s and medium detail indefinitely.
- 3D view hidden: the render target shrinks to 2×2 at once. After 10 s hidden, continent tiles are released as offscreen tiles.

Measured: twelve still seconds at closest zoom, 361 MB retained. After twelve seconds back on the 2D map, 63 MB retained (company tiles only) and 376 MB less in total. Full detail returns 495 ms after reopening.

Recently read bake files stay in the operating system's file cache. A returning tile therefore costs decode and upload, not disk reads, so no separate compressed RAM copy was added.

## Texture compression (applied)

The 2D map tile art (`assets/authored_map/stoneshore-procedural/{roads,fabric,roads_near,fabric_near}`) and the 3D far/medium sprite colour and lit atlases (2,138 textures) now import as Basis Universal (`compress/mode=4`, `uastc_level=2`). The 214 depth atlases stay lossless, because their values position impostors in depth.

Lossless, BC7 and Basis were compared in a copy of the project. BC7 and Basis look the same as the source in game. At 4× magnification, road outline edges are slightly softer. Measured against the source, every set is within about 1.5 dB between BC7 and Basis. BC7 grew these imports from 280 MB to 2.5 GB (5 GB on the universal macOS build, which carries both BC7 and ASTC). Basis stores 212 MB, one copy for all platforms, and transcodes to BC7/ASTC at load. Basis transcoding costs a little more CPU than PNG decoding when loaded serially. In game, threaded loading and a quarter of the upload data make it no slower: the continent first open took 3.35 s instead of 3.96 s.

Side-by-sides: `outputs/supply-chain-3d/texture-compression-ab/`.

### Measured after applying (fresh process, Metal Magnate)

| | Before | After |
|---|---:|---:|
| Exported pack, Windows and macOS | 1,670.6 MB | 1,603 MB |
| Zipped Windows pack | 1,612 MB | 1,545 MB |
| GPU memory, 2D game | 3,855 MB | 2,254 MB |
| GPU memory, company 3D view | 4,574 MB | 3,097 MB |
| GPU memory, all tiles, peak | 5,598 MB | 3,972 MB |
| Heavy: 2D game with 40 buildings | 4,328 MB | 2,669 MB |
| Heavy: all tiles open | 5,876 MB | 4,071 MB |
| Heavy: peak (medium zoom over the capital) | 6,535 MB | 4,805 MB |

Heavy = 36 extra player buildings on 12 land tiles around the company (`tools/supply_chain_3d/trials/vram_load_profile.tscn --heavy`). Both heavy runs read the same seeded bake cache. The first heavy run, which generated every tile at runtime, peaked at 8,904 MB: freshly generated textures are held uncompressed.

## Mid-game continent preparation (fixed: changed tiles only)

Fixed by the tile overlay (`docs/supply-chain-3d-tile-overlay.md`). The continent and the company view load the shipped base and lay out only the tiles whose contents differ from it, one tile at a time. With 36 extra buildings on 12 tiles, continent preparation went from 22 minutes to about 70 s. A company rebuild after one building change went from about 20 s to 1.7–2.1 s, or 5.3 s when the building is on a tile new to the company. The original finding follows.


The bundled world snapshot and continent package match only the starting company. With buildings on new tiles, background continent preparation re-solves the whole continent layout (`Model.build`, about 10 minutes) and transport (about 2.5 minutes) on every launch. On the first launch with those buildings it also regenerates all 604 tile resources (22 minutes in total before the continent opened). Later launches read the tile resources back from the player's cache but still repeat the layout solve (about 11 minutes). This is the largest loading cost in a real mid-game.

A related fix: idle prefetch stored empty entries for worlds built at runtime, which raised script errors in `prepare_tile`/`tile_node`. Prefetch now skips tiles without packaged resources.

## Not done

- One draw-time pipeline compile (about 60–130 ms) remains on the first continent open. Showing the paper map once in advance moved three of its shader compiles out of the open, but would flash the paper over the company view.
- Reaching 1 GB overall needs decisions on the 2D map texture cache, sprite compression and the board's MSAA/density. They are listed in the hand-off rather than changed here.
