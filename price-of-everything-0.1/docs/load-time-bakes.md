# Load time: what is baked, and when to re-bake it

## Continuous water and closer rail planting — verified 13 October 2026

The installed package contains the new cross-tile coast/lake geography, flat
lake surfaces, shoreline-aware mesh partitioning, and staggered closer tree
rows. Visibility metadata is version 5 and explicitly includes narrow lake lips
and small islets. The release validator shares the runtime version constant.

The production pipeline and independent validator pass **600 tiles / 1,806
resources / 1,441,338,895 bytes**. All 600 medium and 600 near bakes were
regenerated, with 600 prepared base tiles. The first generation/validation pass
took 1,462.27 s after cold scene preparation; final assembly reused all resources
and passed in 37.23 s. Obsolete resources were pruned only after validation.
The package is 10,944,364 bytes smaller than the preceding vegetation package;
the separate generated water-geography JSON adds 22,985,464 bytes. Texture
resolutions and decoded medium/near texture memory remain unchanged.

Fresh process on Apple M5 Pro, Godot 4.6.2 / Metal Forward+, all tiles enabled:

| Measurement | Time |
|---|---:|
| Begin ready (process elapsed) | 26.72 s |
| Full 3D board preparation during loading | 9.52 s |
| Prepared transport restore | 1.92 s |
| Continent resource load | 0.65 s |
| First supply-chain opening | 2.54 s |
| Combined open/toggle probe | 2.57 s |

The opening uses medium detail. All 100 streamed reads were bundled, with
**zero runtime bake writes** and two startup rail-layout hits / zero misses.
The 120 rendered main-map frames measured 7.16 ms median, 21.55 ms p95 and
41.18 ms maximum. This is a fresh game process with warm OS filesystem caches,
not a cold-disk benchmark. The preceding package measured 24.98 s to Begin
and 2.56 s for first opening; startup is 1.74 s slower in this sample, while
opening is effectively unchanged.

The focused water/tree checks and relief/isolation/bounds regressions pass
48 assertions. Independent geometry verification finds no coastline beyond
the 20u outward / 5u inward envelope, no false shoreline inside lakes, and a
minimum plateau lip of 1.07u. Reports and captures are under
`outputs/supply-chain-3d/water-greenery/` at the repository root.

The final 13-view review uses current production fingerprints and reaches 750
bundled hits with zero runtime writes. Lake and rural railway captures cover
far, medium and near LODs. The population has 9,069 half-size rail-side trees on
157 tiles, with zero canopy-clearance or rail-size violations. The live-game
transport audit finds 48 same-height overlap candidates longer than 10u and
324 elevated runs; these are documented for a separate routing pass.

## Rail vegetation, tree sizes and medium rails — verified 13 October 2026

The installed package includes transport canopy clearance, denser half-size rural
rail belts, and 100%/75%/50% size variation for other trees. Medium/far railway
linework now has its own continuous low-contrast mesh; near retains the steel
heads and sleepers. Scenery carries both meshes and the vegetation spatial index.
Prepared tile detail now fingerprints the tree placement sources, preventing
older tree cards from surviving a vegetation change.

The production baker and independent validator passed **600 tiles / 1,806
resources / 1,452,283,259 bytes**, an increase of 25,901,381 bytes over the house
height package. The existing transport/scenery dependency also changed the map
key, so this refresh replaced all tile references: 600 prepared base tiles,
557 medium and 539 near textures generated, 43 medium and 61 near resources
copied from the revised preview cache. Package preparation and validation took
1,162.15 s, after the separate cold scenery preview. Medium/near decoded terrain
texture sizes are unchanged. Unindexed older package resources were pruned only
after validation.

Fresh process on Apple M5 Pro, Godot 4.6.2 / Metal Forward+, all tiles enabled:

| Measurement | Time |
|---|---:|
| Begin ready (process elapsed) | 24.98 s |
| Full 3D board preparation during loading | 8.69 s |
| Prepared transport restore | 1.64 s |
| Continent resource load | 0.60 s |
| First supply-chain opening | 2.56 s |
| Combined open/toggle probe | 2.59 s |

All 100 streamed reads were bundled, with **zero runtime bake writes** and two
startup rail-layout hits / zero misses. The 120 explicitly rendered main-map
frames measured 6.90 ms median, 19.43 ms p95, 27.21 ms maximum. These measurements
use a fresh game process with warm OS filesystem caches; they are not cold-disk
or saved-game restore benchmarks. Previous house-height Begin/first-open times
were 24.90 s / 2.60 s.

A separate six-view fresh-process review verified current source fingerprints,
343 bundled reads, zero writes, and matching preview/runtime tree statistics.
There are 22,576 trees, including 17,892 half-size rail-row trees on 158 rural
tiles. No transport canopy-clearance or rail-side sizing violations were found.
The 24 focused vegetation/size/rail-LOD assertions pass; railway kit, transport
cache parity/invalidation and builder-lifetime checks also pass. Existing
nonfatal shutdown warnings remain. Reports, logs and all three zoom captures are
under `outputs/supply-chain-3d/rail-vegetation/` at the repository root.

## Standard 50u house height — verified 13 October 2026

The production package now includes the standard residential height in all
three LODs. A fresh map inspection found all 540 ordinary housing assets at
50u; their footprint-size distribution is unchanged. Scenery frames, continent
sprite transforms and visibility bounds were refreshed. The road/rail transport
key, map key and all 600 base/medium/near tile references are identical to the
preceding farm/half-relief package. No per-tile textures were regenerated.

The production baker and independent validator passed: **600 tiles, 1,806
resources, 1,426,381,878 bytes**. It reused 600 medium and 600 near bakes, with no
base detail preparation required. Package assembly/validation took 40.13 s;
initial cold 3D scenery/continent rebuilding took 335.29 s separately.

Fresh process on Apple M5 Pro, Godot 4.6.2 / Metal Forward+, all tiles enabled:
Begin at **24.90 s**, 3D preparation **8.53 s**, continent resource **0.60 s**,
first supply-chain opening **2.60 s** (combined open/toggle probe **2.62 s**).
All 101 streamed reads were bundled, with **zero runtime bake writes**. Rail
layouts had two cache hits and no misses. These are fresh-process results with
a warm OS filesystem cache, not a cold-disk benchmark.

The separate Stoneshore review checked far/medium/near with current source
fingerprints, 181 bundled reads and zero writes. A rendered house comparison
checks all three asset variants against their live meshes. Focused height/LOD,
far-bake and bounds tests passed 125 assertions. The existing nonfatal ObjectDB
shutdown warning remains. Reports, logs and screenshots are under
`outputs/supply-chain-3d/house-height/` at the repository root.

## Farm clearance and half-height 3D relief — verified 13 October 2026

The installed package now includes the farm/road soil cutouts and 438 intermediate
3D terrain contours. Both the production baker and a separate headless validator
passed: **600 tiles, 1,806 resources, 1,426,382,982 bytes** (84,060,428 bytes more
than the 12 October package). Medium/near decoded terrain texture sizes remain
2,241,286,200 / 8,965,279,800 bytes. The per-tile package phase took 1,186.4 s;
initial cold scene preparation was additional.

Fresh process, Apple M5 Pro / Godot 4.6.2 / Metal Forward+, disposable Metal
Magnate game, all tiles selected at startup:

| Measurement | Time |
|---|---:|
| Begin ready (process elapsed) | 25.17 s |
| Prepared full 3D board | 8.55 s |
| Prepared transport lookup/restore | 1.86 s |
| Continent resource load | 0.57 s |
| First supply-chain opening | 2.48 s |

All 101 landscape/detail reads were bundled, with zero runtime bake writes;
startup rail layouts had two hits and zero misses. The 120 explicitly rendered
post-Begin frames measured 6.90 ms median, 18.09 ms p95, 21.47 ms maximum.
The previous historical Begin measurement was 20.28 s; this run is slower, even
though the baked continent load and first opening remain below a second and
2.5 seconds respectively. These are fresh-process measurements, not a cold OS
filesystem-cache benchmark or a saved-game restore measurement.

A separate five-view visual run checked Stoneshore, the farm crossing and all
three mountain LODs: current fingerprints, 387 bundled reads, zero writes.
All five depot records and the 374u summit match the previous map; 1,069 of 1,681
sampled points around the mountain focus changed height. The shared source hill
and road JSON, shared sampler and depot seeding code are unchanged.

There are 38 passing focused farm/relief assertions plus the disk transport
restore/invalidation check. An attempted broader feature run encountered the
existing smoke assertion expecting 37 catalog buildings (the catalog has 38)
and was stopped in favour of focused regressions; it is not an all-suite pass.
The rendered harnesses still emit the existing nonfatal ObjectDB shutdown warning.
Reports, logs and matched screenshots are in
`outputs/supply-chain-3d/farm-half-relief/` at the repository root.

## Current completion rule and 3D transport package (12 October 2026)

The measurements below this section describe the earlier Windows startup work;
they are not current performance promises. A change is incomplete if it invalidates
a shipped bake without replacing it. See the repository `AGENTS.md`.

Road/rail engineering changes affect the shared 3D map key, so they can invalidate
all 600 terrain tiles, scenery and the continent. The separate start-building
placement bake can still be valid: check its own fingerprint and restoration log.
Do not delete valid caches to fix an unrelated invalidation.

Prepared transport now has its own portable resource. Its lookup runs before
authored bridge grading, switchback/tunnel solving, road grading, urban rail burial
and junction bridge planning. The startup rail layout/depot search also has a disk
cache. The production package includes these records as well as the landscape.
`[TRANSPORT]` reports a cache hit or a cold-stage timing breakdown. Loading finishes
the supply-chain preparation before offering Begin, rather than running synchronous
generation between background coroutine yields after play starts.
Begin now follows actual readiness: the former 20-second cinematic minimum and
60-second override for unfinished work have been removed.

From the Godot project directory, rebuild and install the production package:

```bash
AGENT_GODOT_WINDOW=1 godot --path . --log-file /private/tmp/production-rebake.log \
  tools/supply_chain_3d/bake_continent_package.tscn -- \
  --continent-review --no-telemetry --watchdog-seconds=7200 --prune
godot --headless --path . --log-file /private/tmp/package-validation.log \
  tools/supply_chain_3d/verify_continent_package.tscn -- --no-telemetry
```

This renders textures, so it requires the window-enabled shim. The package is
resumable and reuses matching resources. `--prune` removes unindexed old package
resources only after validation succeeds. The manifest is marked complete only
after every required resource has been written. Do not edit fingerprinted generator
code while baking; that would make the new output stale immediately.

Then use a fresh process to measure the actual full-map startup and first opening:

```bash
LOAD_PROF=1 AGENT_GODOT_WINDOW=1 godot --path . \
  --log-file /private/tmp/supply-startup.log \
  tools/supply_chain_3d/profile_startup.tscn -- \
  --continent-review --combined-open --all-tiles-on-start --no-telemetry \
  --startup-output=/private/tmp/supply-startup
```

Require current fingerprints, bundled landscape/transport hits, no unexpected
runtime bake writes, and record both Begin time and first-open time. The profiler
also samples 120 main-map frames after Begin. Run without `--all-tiles-on-start`
to check company mode followed by the full-map toggle. These harnesses use a
disposable new game; saved-game placement costs require a separate measurement.

The focused headless cache regression is
`tools/railway_assets/transport_cache_check.tscn`. It checks disk restoration,
road/terrain height parity, and invalidation when geometry inputs change.

### Verified result, 12 October 2026

The refreshed package validates 600 tiles and 1,806 resources (1,342,322,554 bytes),
including two startup rail layouts and the prepared transport resource. Both the
baker and a separate headless validator exited successfully.

Measured on Apple M5 Pro, Godot 4.6.2, Metal Forward+, a fresh Metal Magnate game
with all tiles selected at startup:

| Work | Cold generation | Installed package |
|---|---:|---:|
| Road/rail preparation | 32.68 s | 1.84 s |
| Continent stage | 99.68 s | 0.58 s |
| Infrastructure stage | 65.69 s | 0.015 s |
| Full 3D board construction | 346.74 s | 7.52 s |

The loading screen offered Begin at 20.28 s; first supply-chain opening took
2.30 s. All 101 landscape/detail reads came from the bundle, with zero runtime
bake writes. Startup rail planning recorded two hits and zero misses. The 120
explicitly rendered post-Begin map frames measured 6.91 ms median, 18.34 ms p95,
24.95 ms maximum. This is a new-game measurement, not a saved-game restore claim.
Saved-game placement still has the separate path described below.

Detailed reports are in the repository's
`outputs/supply-chain-3d/load-time-2026-10-12/`. The final render probe exited 0;
a nonfatal ObjectDB shutdown warning remains. The earlier diagnostic's rendering
cleanup abort was resolved by draining streaming and stopping idle prefetch before
freeing the test scene.

---

A new game used to take **100 s** to reach the "Begin" button. It now takes about **10.5 s**,
and the worst single frozen frame went from 12.3 s to 1.2 s. Nothing about the map changed: the
same 417 buildings stand in the same places, byte for byte.

This is the operator's page for the three bakes that got it there. If you edit the map and the
game suddenly feels slow again, the answer is on this page.

---

## 1. Where the 100 s went

Measured with `LOAD_PROF=1` and `tools/frame_anatomy_watcher.gd` (Windows, GL Compatibility).

| Chunk | Was | Now |
|---|---:|---:|
| Rendering the world under an opaque loading screen | ~52 % of all wall clock | 0 |
| `HillVisuals` cold draw (one frame) | 8.9 s | 0 |
| Hill far-zoom texture render | ~5 s | 0 (off disk) |
| Start-building placement | 55 s | 8 ms |
| Harbour (`MidcenturyPortPlan`) search, first pass | 3.3 s | 3 ms |
| Harbour search, redundant SECOND pass | 3.3 s | 0 |
| Tile panel + building detail panel | 1.1 s | after "Begin" |
| Goods Graph layout | 0.24 s | first open |

Three findings drove all of it.

**Half the load was drawing a map nobody could see.** The loading screen is opaque, but the
renderer kept submitting the whole plate every frame at 9.5–17k draw calls.

**The expensive half of placement was the visual half.** `MatchState.add_building` for all 417
start buildings measures 4.5 ms; the search for where to put them was 32.5 s, plus the ~22 s of
yielded frames that searching forced.

**The harbour planner ran twice.** `PortVisuals.setup()` plans, and then the single
`footprints_changed` that `end_bulk` emits for the whole match-start placement — ports included
— arrived a moment later and triggered a full replan against the state just planned for. That
was 3.3 s on every load, before this work and unrelated to it. `_planned_footprint_version` now
makes the layer ignore a change notification carrying a version it has already planned against.

---

## 2. The three bakes

### Hill far-zoom texture — `assets/baked/hills_far_zoom.png`

The single texture `HillVisuals` draws whenever enough of the map is on screen.

```bash
godot --path . res://tools/bake_hill_texture.tscn --quit-after 120000
godot --headless --import --path .
```

Must run **windowed** — it renders through a SubViewport, and `--headless` renders nothing. The
`--import` step is not optional: Godot cannot load a PNG under `res://` until it has an
`.import` sidecar, and the runtime says so by name if you forget.

**Re-bake after:** `tools/bake_hills.tscn`, or any change to the relief palette in
`map_style.gd`, or to the painter.

### Start layout — `data/start_layout_bake.bin`

Where every match-start building stands, plus every per-tile working set its placement produced
— block grids with their claimed lots, service lanes, farm tracks, subcomponent geometry, the
decorative masses each building demolished, and the harbour plans.

```bash
godot --path . res://tools/bake_start_layout.tscn --quit-after 240000
```

Also windowed. It runs a real new-game build with the bake forced off (`NO_LAYOUT_BAKE=1`) and
writes what the shipped placement code produced — there is no second implementation to drift.
Takes about 85 s, because it is deliberately paying the old cost once.

**Re-bake after:** a new or edited authored map document, `bake_roads` / `bake_hills`, an edit
to `tile_properties.csv` or `river_properties.csv`, or a change to placement itself (bump
`StartLayoutBaked.BAKE_VERSION` at the same time).

### Authored map textures — `assets/authored_map/` (pre-existing)

```bash
godot --path . res://tools/map_editor/bake_authored_map.tscn --quit-after 600000
godot --headless --import --path .
```

---

## 3. What happens when you forget

Nothing breaks. Every bake refuses itself rather than showing a stale picture:

- **Hill texture** carries the hills source hash, the palette it was rendered in and the framing
  it was rendered for. Any mismatch → the game renders it live, one slow frame, as before.
- **Start layout** carries a content hash over the map document, the road bake, the hill bake and
  the tile CSVs. Mismatch → the whole map is laid out live, 55 s, exactly as it used to be.
- **Start layout, per building.** Adding one entry to `start_buildings.json` does not throw away
  400 good answers: a building the bake does not hold is laid out live *against* the baked world,
  and a placement the bake holds for a building this match never emits is dropped at reconcile.
  So editing the start list costs one building, not the whole map.

The failure modes are "slower" and "slower for one tile". They are never "wrong picture".

---

## 4. Proving a bake is right

The layout bake has a byte-for-byte check. Dump both paths and compare:

```bash
NO_LAYOUT_BAKE=1 LAYOUT_DUMP=live.json godot --path . res://tools/load_phase_check.tscn --quit-after 20000
LAYOUT_DUMP=baked.json               godot --path . res://tools/load_phase_check.tscn --quit-after 20000
```

Both files must hold the same placements and subcomponents. At the time of writing that is 417
and 910, md5 `69d99e81f0fb` and `19c1f8ba9dd3`.

`LAYOUT_SHOT=<path>.png` on the same tool saves a picture of the revealed map, which is the
check for anything a dump cannot see (fabric drawing through buildings, a missing harbour).

---

## 5. Measuring the load

```bash
LOAD_PROF=1 godot --path . res://tools/load_phase_check.tscn --quit-after 20000
```

`LOAD_PROF=1` costs one environment-variable read per phase when unset, and nothing per frame.
It prints:

- `LOADPROF <phase>` — wall between marks. **Includes any frame awaited in between**, so a mark
  sitting after a yield is measuring the frame too. This is what made the Goods Graph layout look
  like 1.7 s when it is 0.24 s.
- `LOADPROF-CALL <name>` — one call, in isolation. Trust these.
- `LOADPROF-PLACE` — per-stage placement totals, dumped at `end_bulk`.
- `LOADPROF-DRAW` — any `_draw` over 50 ms.

Add `ANATOMY=1` to account for the *frame* instead of the job (coroutines / nodes / frame_end);
see the header of `tools/frame_anatomy_watcher.gd`, and mind the two traps recorded there.

---

## 6. Where the remaining 10.5 s goes

| | |
|---|---:|
| `main.tscn` load, on a worker thread | 5.2 s |
| Scene instantiation, main thread — **a real stall** | ~1.0 s |
| HUD scaffold (`_build_base`) | 0.7 s |
| Seeds, roads, layout restore, ports | 0.8 s |
| `_warm_authored_bake` (150 baked tile textures, disk) | 0.8 s |
| Reveal: first paint of the world | 1.2 s |
| Reveal: three more warm frames at ~190 ms | 0.6 s |

## 7. What is left, in order

0. **LOADING A SAVE still takes ~90 s.** The bake deliberately does not apply to a loaded save
   — the save carries its own buildings, and `_rebuild_after_load` re-emits every one of them
   through the live placement path, then `relayout()` re-packs the lot. Measured 89.6 s for
   `autosave_3` (562 buildings). Now that a new game is 11 s, this is by far the worst load in
   the game. The shape of a fix is visible — a save whose start buildings still stand on their
   start tiles could claim them from the same bake, with the player's own buildings placed live
   — but `relayout()` would have to stop re-packing what the bake already packed, and that
   needs its own measured pass.
1. **The instantiation frame is ~1.3 s and it is DIFFUSE — do not go hunting for a culprit.**
   Measured with a per-`_ready` timeline in a single run (the numbers move between runs, so one
   run is the only honest way to compare within it):

   | | |
   |---|---:|
   | scene instantiation + `hex_map._ready` | 56 ms |
   | `hill_visuals` (incl. 146 ms loading the baked texture) | ~320 ms |
   | the other nine map layers, ~15 ms each | ~110 ms |
   | overlays + the HUD subtree up to the first big panel | ~460 ms |
   | BuildingDetailPanel / ResearchPanel / TopBar `_ready` | ~110 ms |
   | SearchOverlay + the rest of the HUD | ~265 ms |

   **Moving the big HUD panels out of `main.tscn` was investigated and is NOT worth it.** The four
   largest scripts under UILayer — BuildingDetailPanel (3,308 lines), ResearchPanel, TopBar,
   SearchOverlay — cost about 95 ms of `_ready` between them, not the ~1 s that their size
   suggests. Deferring them means turning `@onready` unique-name scene nodes into lazily-built
   ones across a lot of call sites, to recover a tenth of a second. Script length is not
   `_ready` cost, and this is where that was learned.

   (BuildingDetailPanel is still worth a look for a different reason: it is the v1 panel, kept
   only as the `swap bdp` fallback, and `use_bdp_v2` defaults true — so it is built every load
   and essentially never shown. That is 58 ms and a lot of dead weight in the scene.)
2. **The full-map view costs ~190 ms a frame at 26.5k draw calls** — about 5 fps. This is the
   opening camera position, so it is the first thing a player sees moving. It is a play-time
   frame-budget problem as much as a load one; the buildings' zoom-out LOD is the lever
   (see `building-visuals-lod`).
3. **The loading screen costs 35–85 ms a frame on its own** — the hex lattice is ~1,832 draw calls,
   redrawn every frame. With the world hidden it is now the only thing rendering, so it sets the
   floor for every frame the build yields. A film would replace it with one draw call.
4. **Authored-map textures are ~10× oversampled at the opening zoom.** 209 tiles at 540×640 RGBA is
   ~289 MB of VRAM if it were all resident. Not a load-time problem any more (the disk read is
   0.8 s and the upload turned out not to be the reveal cost), but a quarter-resolution second
   layer in the same manifest would cut the resident set about 16× and look identical that far out.

## Current Stoneshore visual trial scope

As of 13 October 2026, the user has paused full-continent rebaking until approval.
Use the five-tile `--stoneshore-review` procedure documented in
`supply_chain_3d.md` and install its separate `stoneshore_trial_bakes` package.
The production bake tool guards against accidentally overwriting the continent
package. A successful scoped validation certifies only this trial, not the
outdated full-continent package. Do not regenerate unrelated continent tiles.

Verified trial results: 5 tiles, 21 indexed resources, 22,288,466 bytes (21.26 MiB),
current source fingerprints, and no missing dependencies. Packaging reused the
already-rendered tile resources and took 1.17s. A fresh process using an empty
runtime cache reached the game in approximately 16.97s; the map prepared in
0.862s during loading and opening the prepared supply view took 0.275s. The
review visited region, town, old quarter, harbour, fields, coast, factory and
far views: 19 bundled cache hits and **zero runtime bake writes**. These are
five-tile trial measurements with a warm OS file cache, not full-continent or
cold-disk benchmarks. Evidence is in
`outputs/supply-chain-3d/stoneshore-half-size/validation/` at the repository root.
The 30 civic assertions and 10 new trial assertions passed; all 16 gameplay
structures matched the baseline positions and dimensions.


### Neighbourhood trial verification (13 October 2026)

The five-tile Stoneshore package now includes the Voronoi side streets, revised
residential/commercial placement and wooded pond/grove assets. It validates in
both the baker and a separate headless process: 21 resources, 23,543,906 bytes,
zero package errors, current source fingerprints. This is the scoped trial
package, not a refreshed continent package.

A fresh Godot 4.6.2 / Forward+ Metal process using a new empty runtime cache
prepared the 3D board in 1.042 s during loading; first supply-chain opening,
including visible detail readiness, took 0.275 s. Begin was reached at 17.296 s
from process start. All 19 landscape/detail reads used bundled resources, with
zero runtime writes; transport also restored from its bake. The final layout
has 102 decorative buildings and ten green spaces, with no residential zoning
violations. All 16 player/NPC/pylon records retain their previous positions and
dimensions. Fifty focused Voronoi, zoning and civic assertions passed.

The render harness still reports the existing nonfatal ObjectDB shutdown warning;
headless tests report the existing macOS `ret != noErr` host warning. Neither
produced script errors or failed assertions. Reports and logs are under
`outputs/supply-chain-3d/stoneshore-neighbourhood/validation/` at repository root.


### Semidetached scale verification (14 October 2026)

The revised five-tile package validates in both the baker and an independent
headless process: 21 resources, 23,643,455 bytes, current source fingerprints and
zero package errors. The final review verifies all 43 placed semidetached pairs
at 30u wide / 27.5u tall, and all 16 gameplay/pylon records retain their prior
positions and dimensions. Civic and trial regressions passed 43 assertions.

A fresh rendered process with an empty runtime cache prepared the board in
1.061s during loading, reached Begin at 17.855s from process start, and opened
the supply-chain view with visible detail ready in 0.298s. The review recorded
19 bundled hits and zero runtime writes; the transport lookup also hit its bake.
These are scoped five-tile measurements on the same warm OS cache, not a
whole-continent benchmark. The full-continent bake remains paused. Evidence:
`outputs/supply-chain-3d/stoneshore-semi-scale/validation/`.


### Sidewalk and footprint verification (14 October 2026)

The scoped production pipeline regenerated and installed the five Stoneshore
base/medium/near resources, shared scenery and continent presentation. Validation
in the baker and an independent headless process passed: 21 indexed resources,
25,286,917 bytes (24.12 MiB), current fingerprints, no missing dependencies.
Existing model meshes and sprite atlases were reused. Full-continent baking is
still paused.

A fresh Godot 4.6.2 / Forward+ process with an empty runtime cache prepared the
board in 1.102s during loading, reached Begin at 17.926s from process start and
opened the prepared supply view with visible detail ready in 0.302s. The review
visited all ten scoped views, recording 19 bundled hits, a transport cache hit
and zero runtime bake writes. These are five-tile, warm OS-cache measurements.

All 16 gameplay structures match prior positions and dimensions. The geometric
review reports 133 exact decorative footprints, zero building overlaps and zero
street/sidewalk intrusions, with all ten green spaces and zoning checks retained.
38 focused civic, silhouette and sidewalk assertions passed. The broader road
suite reports 51 passes and four failures in the unchanged road_index endpoint
clustering / near-miss audit checks; those transport issues are outside this
visual change. Existing nonfatal host/exit warnings remain as documented above.
Evidence and the complete test logs are under
`outputs/supply-chain-3d/stoneshore-sidewalks/validation/` at repository root.


### Street-front infill verification (14 October 2026)

The five-tile production pipeline regenerated and installed the current
Stoneshore trial: 21 indexed resources, 28,574,474 bytes (27.25 MiB), current
source fingerprints and no package errors. Both the baker and an independent
headless process validate it. Existing GLBs and far/medium atlases are reused.
Full-continent rebaking remains paused.

A fresh Godot 4.6.2 / Forward+ Metal process with an empty runtime cache reached
Begin at 17.165s. Board preparation took 1.040s during loading; opening the
prepared supply view with detail ready took 0.289s. Across ten review views the
process recorded 19 bundled hits, a transport cache hit, zero cache misses on
initial board preparation and zero runtime bake writes. These are scoped trial
measurements with a warm OS filesystem cache, not cold-disk/continent timings.

58 focused civic, frontage, quarter-turn, caching and Stoneshore assertions
passed. Rendered verification confirms 245 decorative buildings, ten green
spaces, no decorative road-access stems and no building/street overlaps. All
16 gameplay records retain their prior positions and dimensions. Coverage is
78.20% of estimated buildable frontage (42.88% counting every road edge);
the metric and exclusions are documented in supply_chain_3d.md. Detailed JSON,
logs and snapshots are under `outputs/supply-chain-3d/stoneshore-frontage/`.

The broader road regression suite still reports the same four endpoint-clustering /
near-miss audit failures in unchanged road_index code, with 51 assertions passing.
No new road regression failure was observed; its complete log is included.

### Rail datum and slope shading verification (14 October 2026)

The production five-tile Stoneshore package was regenerated and installed after
the rail-profile change: 21 indexed resources, 29,459,268 bytes (28.09 MiB), current
fingerprints. Baker and independent headless validation both pass. All five base,
medium and near tile resources were refreshed; existing building meshes and
sprite atlases were reused. Whole-continent rebaking remains paused.

A fresh Godot 4.6.2 / Forward+ Metal process with an empty runtime cache reached
Begin at 17.296s. Board preparation took 1.056s during loading, and opening the
prepared supply view with visible detail ready took 0.273s. Ten review views
recorded 19 bundled hits, a transport cache hit and zero runtime bake writes.
These are scoped Stoneshore measurements with a warm OS filesystem cache.

Nine new rail-elevation assertions and 26 rail-vegetation/LOD assertions pass.
The transport geometry and disk-cache restoration harnesses pass, including
surface/grade parity and source invalidation. The rendered audit has zero hidden
open cuts and zero tunnel grade; all portal crowns fit under natural ground.
All 245 decorative buildings, 78.20% estimated buildable frontage, ten green
spaces and zero building/street overlaps remain. The previously documented four
road-index endpoint/audit failures are outside this change and remain unresolved.

Evidence: `outputs/supply-chain-3d/stoneshore-rail-profile/` (before/after transport
audit, final ten views, validation logs and compact verification JSON). Only the
scoped package is current; the earlier full-continent bake is not a release of
these visual changes.
