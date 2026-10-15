# Load time: what is baked, and when to re-bake it

## Owned-first opening and background continent — 15 October 2026

Every new supply-chain board now opens with **Show player owned tiles only**,
ignoring the old saved all-tiles preference. After owned coverage is ready, a
matching cached continent loads in the background. Selecting all tiles early
keeps owned tiles usable while preparation finishes; selecting owned cancels
that pending switch. Coverage selection lasts for the current board only.

The previous **16.023s** all-tiles switch was not rebaking textures. Its 14.274s
board preparation included 4.551s restoring/building the model, 4.264s computing
keys/restoring transport, 0.984s loading scenery and 2.681s assembling the scene.
The rest included visible-detail activation. Worker disk reads alone would not
remove that synchronous work.

The installed supplement now carries the prepared model, content keys, authored
road indexes, mine cuts/rims, building foundations and continent picking shape.
It adds **29,208,588 bytes (27.86 MiB)**; no terrain or sprite artwork was
regenerated. The complete package is **1,841 resources / 1,928,790,772 bytes**.
The existing terrain, scenery and transport keys are unchanged. Independent
package validation checks hashes, source fingerprints, bounds and the supplement.

Fresh rendered Godot 4.6.2 / Forward+ Metal process on Apple M5 Pro, an empty
runtime-cache path and warm OS filesystem caches:

| Measurement | Time |
|---|---:|
| Process start to Begin | 18.864s |
| Owned-board preparation during loading | 2.704s |
| First supply-view opening after Begin | **0.152s** |
| Continent preparation, while owned view remains usable | 6.387s |
| First all-tiles switch after preparation, visible medium detail ready | **3.068s** |
| Return to owned coverage | 0.005s |
| Repeat all-tiles switch | 0.022s |
| Return after ten-second inactive-detail retirement | 0.541s |
| Owned-view frame time during preparation, 95th percentile / maximum | 9.22ms / 57.18ms |

There was one frame above 50ms across 603 sampled frames. Earlier iterations
had 0.5–0.74s stalls from reconstructing indexes, mine geometry and picking
surfaces; the supplement removes those reconstruction stages. **The first
all-tiles switch is still about three seconds, not instant.** Local medium scene
activation and renderer work remain. Game startup is also still around 19s.

The fresh run recorded 35 bundled hits at owned opening and 112 in the continent
builder, with **zero misses and zero runtime bake writes**. It rendered both
coverage modes and checked builder reuse through repeated switches. All 45
resident detail tiles retired after the ten-second grace period; returning
reused the package without writes. The runtime cache directory was not created.
Sixty-six focused assertions pass for background cancellation/input validation,
camera/cursor collision, prefetch and resource-cache retention/prepared reloads.
The existing ObjectDB exit warning remains in rendered captures. Evidence is
under `outputs/supply-chain-3d/background-loading/final/` at repository root.

Only twelve nearby base/medium tile resources are warmed, not every detailed
tile. Strong speculative resource handles are released after the first local
stream completes. Both coverage roots survive toggles; inactive continent detail
has a ten-second grace period before node retirement and normal cache-pressure
rules. Preparation never changes the active world's shared material grading.

The supplement is currently for the **Metal Magnate starting world**, with its
exact live input signature. A changed simulation/layout, a different company or
a visibility change cannot use a stale snapshot. Those worlds retain the normal
explicit all-tiles build path. Pending jobs are cancelled on board invalidation
or exit. Workers only read detached inputs or immutable loaded data; scene-tree
work stays on the main thread. `--no-background-continent` disables speculative
preparation for offline tools and controlled comparisons.

After a production continent bake and `bake_company_start.tscn`, refresh just the
supplement, then validate in a separate process (from the project directory):

```bash
AGENT_GODOT_WINDOW=1 godot --path . --log-file /private/tmp/world-snapshot.log \
  res://tools/supply_chain_3d/bake_world_snapshot.tscn -- \
  --continent-review --no-background-continent --no-telemetry
godot --headless --path . --log-file /private/tmp/world-snapshot-verify.log \
  res://tools/supply_chain_3d/verify_continent_package.tscn -- --no-telemetry
AGENT_GODOT_WINDOW=1 godot --path . --log-file /private/tmp/background-check.log \
  res://tools/supply_chain_3d/check_background_loading.tscn -- \
  --continent-review --verify-retention --no-telemetry \
  --bake-cache-directory=/private/tmp/background-check-unused-cache
```

Use a new empty cache path for each acceptance run. A full package rebuild/prune
must be followed by the supplement step; the runtime safely ignores an absent
or mismatched supplement. Measurements below are historical baselines.

## Full-continent decoration rollout — verified 15 October 2026

This supersedes the earlier Stoneshore-only bake pause: the user approved the
continent rollout. The installed full package covers **600 tiles, 1,840 resources,
1,899,582,184 bytes (1.77 GiB)**, including the default owned-company start. The
separate five-tile trial is also refreshed (21 resources, 37,114,834 bytes).
Decoration uses the approved 35% reduction across all 92 urban tiles and rural
homes, with region-local infill and clearance against actual NPC meshes. Giant
Stoneshore sea detours are removed and authored 3D roads are clipped at the coast.

Independent production-package validation passes with current fingerprints.
The full package's medium textures decode to 2,241,286,200 bytes; near textures
are 8,965,279,800 bytes if all are resident, with 1,060,484,655 bytes of near
resources on disk. Normal streaming retains only a subset. The 133.33 MiB
combined far resource requires Git LFS when cloning/pulling; it is a native
Godot resource at runtime.

Fresh Godot 4.6.2 / Forward+ process, empty runtime cache path, warm OS filesystem
caches, no task baker/reviewer running (the user's separate Godot process was
left running):

| Measurement | Time |
|---|---:|
| Process start to Begin | 19.045s |
| Owned-board preparation during loading | 3.031s |
| First supply-view opening after Begin | 0.188s |
| Show all tiles with visible detail ready | **16.023s** |
| Full-board preparation within that switch | 14.274s |

The run records **35 bundled hits at first opening, 183 after switching and an
extra close-up, zero misses and zero runtime bake writes**. The cache directory
was not created. All three runtime content keys match the installed manifest.
This is a fresh-process result, not a cold OS-cache benchmark. **The all-tiles
switch still misses the five-second target.** The main remaining costs are
model/memo restoration, key/transport work and scene assembly, rather than
runtime art generation. Do not confuse 0.188s opening with the complete game
startup or the all-tiles switch.

Packaging fixes preserve the persisted transport snapshot before rendering
adds sidewalk annotations, and include exact terrain cut bounds from all three
LODs. The original validation caught one low terrain cut on `tile_10_5`; its
visibility metadata was repaired and independently revalidated without rebaking
art. `repair_package_visibility.tscn` refuses unrelated validation errors.
Auxiliary owned-start resources and both prepared layout variants are bundled.

The final resumed offline assembly took 1,106.064s after preparation; initial cold
preparation took approximately 1,179s. Valid generated-cache resources were reused.
These offline costs are not incurred by the verified normal loading path.
Evidence, current content keys, region notes and the outstanding crossing backlog
are in [the continent review](continent-decoration-review.md) and
`outputs/supply-chain-3d/continent-rollout/validation/` at repository root.

Historical measurements below describe earlier scoped packages, not this package.

## Smaller Stoneshore decoration and closer zoom — verified 15 October 2026

The installed **five-tile trial** uses decorative modules at 65% of their
previous dimensions, including courtyard/back-row homes, commercial buildings
and Docks skyline landmarks. Parks and gameplay building sizes are retained.
The frontage land probe follows the smaller modules, so narrow usable plots
remain part of its coverage calculation. Closest camera span is now 192u,
giving 25% more magnification than the previous 240u limit.

Production assembly prepared five base resources and regenerated five medium
and five near resources, taking **20.188s after offline preparation**. Independent
validation passes with current fingerprints: **21 resources, 40,072,245 bytes
(38.22 MiB)**. Full-continent baking remains paused.

Fresh Godot 4.6.2 / Forward+ Metal process, Apple M5 Pro, empty runtime cache
directory and warm OS filesystem caches:

| Measurement | Time |
|---|---:|
| Process start to Begin | 17.229s |
| Five-tile board preparation during loading | 1.259s |
| Frontage memo restoration stage | 0.187s |
| Transport cache restore | 0.099s |
| Combined five-tile resource load | 0.032s |
| First supply-view opening with visible detail ready | 0.275s |

Eighteen rendered views pass the review assertions, including the 192u closest
view: **19 bundled hits, zero initial cache misses and zero runtime bake writes**.
The runtime cache directory was never created. Placement produces 474 decorative
buildings versus 259 in the preceding PR 204 trial, with 86.88% usable frontage,
10.59% canopy coverage and no building/street overlaps or brownfield intrusions.
The three skyline landmarks, two ponds, port connection and rail/depot crossing
checks pass. All 16 gameplay records retain their asset, size and orientation.
Forty-nine focused assertions pass across trial scaling, frontage, neighbourhood
layout/cache restoration and camera movement. Existing nonfatal certificate,
RoadRegions and exit warnings remain. Evidence:
`outputs/supply-chain-3d/stoneshore-smaller/` at repository root.

## Rail river bridges and Fields junction — verified 15 October 2026

The installed **five-tile** package contains the moved Fields junction, its routed
line to tile_5_10, the river-clear tile_6_9 anchor and the new crossing mix (see
`supply_chain_3d.md`, "Rail river bridges, Fields junction and crossing mix").
Production assembly regenerated two base tiles and all five medium/five near
resources, reusing three base tiles; it took **19.558s** after offline
preparation. Independent validation passes with current fingerprints:
**21 resources, 40,230,218 bytes (38.37 MiB)**. Whole-continent baking remains
paused, so the rail layout outside the trial (version 7: river-clear anchors and
river-aware routes, including Greyroad) is not yet in the continent package.

Fresh Godot 4.6.2 / Forward+ Metal process, Apple M5 Pro, empty runtime cache
directory and warm OS filesystem caches:

| Measurement | Time |
|---|---:|
| Process start to Begin | 16.740s |
| Five-tile board preparation during loading | 1.220s |
| Frontage memo restoration stage | 0.183s |
| Transport cache restore | 0.096s |
| Combined five-tile resource load | 0.031s |
| First supply-view opening after Begin | 0.247s |

Eighteen rendered views record **19 bundled hits, zero misses and zero runtime
bake writes**, and every review assertion passes: 8 side streets, 10.29% canopy
(baseline 10.29%), 81.98% buildable frontage, no building or street overlaps,
depot routes and Docks rail checks unchanged. The review's building-overlap test
now clips polygons: its ray-cast point test reported two pairs of identical
side-by-side modules as overlapping although they stand 2.5u and 4.6u apart.
Evidence is in `outputs/supply-chain-3d/stoneshore-rail-bridges/` at repository root.

## Stoneshore riverside field — verified 14 October 2026

The installed five-tile package contains the west-bank farm's expanded field.
Production assembly reused four unchanged base tiles, updated the affected
base tile, and copied the ten already prepared medium/near resources. Assembly
took **1.850s** after offline preparation. Independent validation passes with
current fingerprints: **21 resources, 39,978,624 bytes (38.13 MiB)**.

Fresh Godot 4.6.2 / Forward+ Metal process, Apple M5 Pro, empty runtime cache
directory and warm OS filesystem caches:

| Measurement | Time |
|---|---:|
| Process start to Begin | 17.654s |
| Five-tile board preparation during loading | 1.171s |
| Frontage/field memo restoration stage | 0.176s |
| Transport cache restore | 0.099s |
| First supply-view opening after Begin | 0.321s |

Eighteen rendered views record **19 bundled hits, zero misses and zero runtime
bake writes**. Shoreline clipping is skipped on a valid field-memo hit. The
field grows from 3,793u² to 6,789u² with zero overlap against the buffered river
and zero intruding tree crowns. The barn pose and source crop-cell sizes remain
unchanged. Thirty-one focused assertions pass for field clipping, repeated crop
geometry, road clearance and layout-cache persistence. Rendered frontage, canopy,
building, depot, port and coastal checks also pass.

Decoded medium/near terrain texture sizes remain 18,677,385 / 74,710,665 bytes;
near resources occupy 20,043,469 bytes on disk. Full-continent baking remains
paused. Evidence is in `outputs/supply-chain-3d/stoneshore-riverside-farm/` at
repository root. Existing nonfatal certificate, RoadRegions and exit warnings
remain.

## Stoneshore depot routes and continuous coast — verified 14 October 2026

The installed **five-tile** package implements both depot roads, the single-pair
bridge and the continuous 48u coastal land/water margin. The production baker
and independent validator pass with current fingerprints: **21 resources,
33,078,100 bytes (31.55 MiB)**. Four base resources and all five medium/five near
resources were updated for the visual change. The final memo-only package pass
reused all terrain/art resources and took 0.755s after offline preparation.
Whole-continent baking remains paused.

Fresh Godot 4.6.2 / Forward+ Metal process, Apple M5 Pro, empty runtime cache
directory and warm OS filesystem caches:

| Measurement | Time |
|---|---:|
| Process start to Begin | 17.323s |
| Five-tile board preparation during loading | 1.092s |
| Frontage/depot memo restoration stage | 0.145s |
| Transport cache restore | 0.090s |
| Combined five-tile resource load | 0.027s |
| First supply-view opening after Begin | 0.308s |

Sixteen final views record **19 bundled hits, zero initial cache misses and zero
runtime bake writes**. The first verification exposed a dropped depot-route memo
in `LayoutQueries.finish()`: route generation was repeated and its insertion
triggered a redundant layout write. The final snapshot now retains it, and two
regression assertions verify memo preservation and zero writes on unchanged data.
The package was regenerated and this timing run used a new empty runtime cache.

Fifty-four focused assertions pass across coast/clearance, crossings, tunnel
heights and route-cache tests. Rendered audits find no building/street overlaps,
271 decorative buildings, 76.37% buildable frontage, three skyline landmarks and
unchanged open working yards. A avoids the rails; B crosses one non-junction
pair on a 21.45u bridge. Transport verification finds at least 8.5325u rail-head
clearance and modified road grades at or below 8%.

The coastal mesh fills the complete 121,383u² preview envelope, including
43,372u² of neighbouring coastal land. Triangle-area error is 0.00015%, with
height/normal sampling shared with the main terrain. Three restored scenery
meshes serve every LOD; no neighbour detail, physics or runtime clipping is added.
Medium/near decoded terrain texture sizes remain 18,677,385 / 74,710,665 bytes.
Near resources occupy 16,613,616 bytes on disk. Evidence, numeric plans, logs and
captures are in `outputs/supply-chain-3d/stoneshore-coastal-routes/` at repository
root. Existing nonfatal certificate/RoadRegions/ObjectDB warnings remain.


## Stoneshore constant sea margin — verified 14 October 2026

The installed five-tile package includes the unified **48u sea-margin offset**,
rounded corners, continuous cutaway texture coordinates and removal of tiny
isolated water pockets. The production baker and independent validator both
pass with current fingerprints: **21 resources, 31,835,105 bytes (30.36 MiB)**.
The final package pass took 20.195s after offline scene preparation, reused all
five byte-identical base resources and regenerated five medium/five near
resources. Whole-continent baking remains paused.

Fresh Godot 4.6.2 / Forward+ Metal process on Apple M5 Pro, empty runtime cache
directory and warm OS filesystem caches:

| Measurement | Time |
|---|---:|
| Process start to Begin | 17.753s |
| Five-tile board preparation during loading | 1.074s |
| Frontage cache restore | 0.123s |
| Transport cache restore | 0.083s |
| Combined five-tile resource load | 0.025s |
| First supply-view opening after Begin | 0.307s |

Fourteen views reach **19 bundled hits, zero initial cache misses and zero
runtime bake writes**. Twenty focused assertions pass, including oblique edge
width, convex/re-entrant joins, water-only clipping, tiny-patch removal and
continuous curved-wall UVs. Final rendered audits retain 258 decorative
buildings, no building/street overlaps, three central skyline buildings and
unchanged open depot tracks. No roads were changed; the two measured depot-road
alternatives are read-only concepts. Regular-map rendering is unchanged.

The sea geometry is restored as three baked scenery meshes. Detailed clipping
and mesh generation remain on cache miss; normal loading only builds the small
preview-envelope description before lookup. Decoded medium/near terrain sizes
remain 18,677,385 / 74,710,665 bytes. The existing nonfatal host certificate and
ObjectDB exit warnings remain. Evidence, route plans and final captures are in
`outputs/supply-chain-3d/stoneshore-sea-margin/` at repository root.


## Stoneshore Docks skyline and sea margin — verified 14 October 2026

The current **five-tile** production package contains the three-tower Docks
cluster, mandatory tunnel cover beneath conflicting roads/buildings, and the
water-only margin into adjacent sea tiles. Independent validation passes with
current fingerprints: **21 resources, 31,829,261 bytes (30.35 MiB)**. No
full-continent bake was run. The final package assembly took 19.467s after scene
preparation, regenerated all five medium and five near bakes, prepared three
base resources and retained two with identical payloads. Cold frontage generation remains offline.

Fresh process, empty runtime cache directory, Apple M5 Pro / Godot 4.6.2 Metal
Forward+, warm OS filesystem cache:

| Measurement | Time |
|---|---:|
| Begin ready, process elapsed | 17.342s |
| Five-tile board preparation during loading | 1.092s |
| Frontage restoration | 0.126s |
| Transport lookup/restore | 0.087s |
| Combined five-tile continent resource load | 0.023s |
| First supply-chain opening after Begin | 0.310s |

Fourteen final views record **19 bundled hits, zero initial cache misses and
zero runtime bake writes**. The three sea-margin meshes are loaded with cached
scenery; neither polygon clipping nor neighbouring tile/detail generation runs
on this path. All three skyline buildings survive cache restoration and keep
correct far/medium/near representations. The Docks audit finds no exposed rail
intersections with building footprints or parallel road surfaces. Decorative
building/street and brownfield intrusion audits also pass. Working-yard tracks
retain their original elevation and remain open; final tunnel entrance
transitions are at most 0.38%. Seventy-five focused assertions pass across the
Docks clearance/water, frontage, neighbourhood, crossing/station and tunnel tests.

Decoded medium/near terrain texture sizes remain 18,677,385 / 74,710,665 bytes;
near resources use 16,169,279 bytes on disk. These are scoped preview numbers,
not current full-continent timings. The existing RoadRegions water-tile and
ObjectDB exit warnings remain. Evidence is under
`outputs/supply-chain-3d/stoneshore-docks/` at repository root.


## Stoneshore crossings and station — verified 14 October 2026

The current review package is scoped to **five Stoneshore tiles**. It includes
nine engineered road bridges, the broader depot lead and Old Quarter terminal
station, plus regenerated terrain/detail and scenery. Whole-continent baking
remains paused pending approval.

Production baking and independent validation pass: **21 resources,
29,491,338 bytes (28.13 MiB)**. The final package pass took 19.28s after cold
scene preparation; it regenerated five medium and five near bakes, prepared one
base tile and retained four base resources with identical payloads. Normal
loading uses these installed resources; these generation times are not startup
costs.

Fresh process, Apple M5 Pro / Godot 4.6.2 Metal Forward+, disposable game:

| Measurement | Time |
|---|---:|
| Begin ready, process elapsed | 17.486s |
| Five-tile board preparation during loading | 1.029s |
| Transport cache lookup/restore | 0.073s |
| Continent resource load, five-tile preview | 0.023s |
| First supply-chain opening after Begin | 0.275s |

The ten-view far/medium/near review and separate transport capture each use
**19 bundled hits and zero runtime bake writes**. Source fingerprints are current.
The baker now includes adjacent relief-query memo entries, avoiding a first-open
layout rewrite. These timings use fresh processes with warm OS filesystem caches;
they are not cold-disk measurements and do not describe the stale full-continent
package. The existing nonfatal ObjectDB shutdown warning remains.

Twenty crossing/station checks, nine tunnel checks, the transport geometry test
and disk-cache parity/invalidation test pass. Evidence and verification JSON are
under `outputs/supply-chain-3d/stoneshore-crossings/` at repository root.


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


### Stoneshore block interiors — installed package, 14 October 2026

The five-tile production package includes neighbourhood lanes, courtyard homes,
garden rows, greens and brownfields. The full-continent package remains paused.
Existing building meshes and far/medium/near artwork are reused; only affected
layout, transport, scenery and tile resources were regenerated. The final bake
reused all five byte-identical base tile payloads.

Independent `verify_continent_package.tscn` validation passes with current source
fingerprints: 21 resources, 31,217,193 bytes (29.77 MiB). Medium decoded payload
is 18,677,385 bytes; near decoded payload is 74,710,665 bytes. The near resources
occupy 15,860,308 bytes on disk. Production package assembly took 19.856s after
scene preparation; the cold frontage search took 29.106s. This search is offline
preparation, not normal view opening.

Fresh-process `compare_stoneshore.tscn` measurements, using a new empty runtime
cache directory and warm OS filesystem caches:

| Measurement | Result |
| --- | ---: |
| Process start to Begin | 17.394s |
| Five-tile board preparation | 1.080743s |
| Frontage cache restore | 124.204ms |
| Transport lookup and restore | 81.979ms |
| Shared five-tile continent resource | 23.577ms |
| First supply-view opening after Begin | 293ms |
| Final bundled cache hits | 19 |
| Runtime bake writes | 0 |

The first independent run exposed an ordering bug: cached courtyard additions
were grouped after frontage infill, changing downstream transport/scenery keys.
The cache now retains the actual standing emission order. A courtyard-bearing
unit fixture checks complete model equality after restore. The installed package
was regenerated after the fix; the fresh timings above are from that final
package, not from the baking process.

Twelve rendered views cover the regional/far view, town, Old Quarter, harbour,
rural tiles, ponds, factory, courtyard and brownfield. The final layout has 254
decorative buildings (previously 229), 76.49% estimated buildable original/district
frontage, no building/street overlaps and no parcel intrusions. Seven brownfields
reserve 14,560 square units. Nine new thin lane paths, four courtyard groups,
fourteen added greens and sixteen footpaths serve the additional inner rows.

Validation includes fourteen neighbourhood/cache/clearance/mesh assertions,
nineteen frontage/civic assertions and twenty crossing/station assertions. The
installed transport data still has nine bridge groups and three covered-rail
crossings, minimum rail-head clearance 8.5325u and maximum modified approach
grade 8.000001% (floating-point tolerance). No new lane crosses the rail reserve.
Existing unrelated road-index endpoint failures and the previously documented
steep exposed rail segment are outside this pass.

Reports and logs: `outputs/supply-chain-3d/stoneshore-interiors/final/` and
`outputs/supply-chain-3d/stoneshore-interiors/validation/` at repository root.
The nonfatal system-CA warning in headless Godot and ObjectDB exit warning in
rendered harnesses remain unchanged.


### Stoneshore streets, plazas, trees and port — 14 October 2026

The production five-tile package is regenerated and installed. Independent
validation passes with current fingerprints: 21 resources, 40,062,209 bytes
(38.21 MiB). Existing meshes and sprite atlases are reused. The port asset
only gains road-entry/width metadata; its mesh is unchanged. Layout, transport,
scenery, five base tile resources and ten medium/near textures reflect the new
streets, concrete and trees. Medium and near decoded texture payloads remain
18,677,385 / 74,710,665 bytes; the near resources occupy 20,113,414 bytes on disk.
Package assembly reused the draft's ten prepared detail resources and took
2.345s after preparation. Whole-continent baking remains paused.

Fresh Godot 4.6.2 Forward+ / Metal process, empty runtime cache, warm OS cache:

| Measurement | Result |
| --- | ---: |
| Process start to Begin | 25.832s |
| Five-tile board preparation during loading | 1.342s |
| Frontage/route cache restore | 198.785ms |
| Transport lookup and restore | 116.946ms |
| First supply-view opening after Begin | 378ms |
| Final bundled hits | 19 |
| Runtime bake misses / writes | 0 / 0 |

The measured Begin time includes the game's main-map startup and asset warmup;
it is not the supply-view opening time. The offline frontage/plaza/tree search
took approximately 65s in the final cold draft. Prepared layout, port pose,
transport and scenery all load from the installed package in normal play.

Sixty-eight focused assertions pass (curves, plaza classification, canopy union,
port grading, route-cache retention, frontage, neighbourhoods and crossings).
The final rendered audit passes the 75% frontage target, independent 2u canopy
check, beach limit, actual junction/building clearance, port road alignment and
height, wet berths, coastal envelope coverage, depot routes and working-yard
checks. No regular-map files were changed. Evidence and logs are in
`outputs/supply-chain-3d/stoneshore-streets-greenery/`.

The independent installed-transport pass records seven bridges, twelve grouped
crossings, minimum rail-head clearance 8.5325u, modified approach grades at or
below 8%, level buried rail and no open cuts over fully hidden track. Its fresh
process also reports 19 bundled hits and zero writes. The previously documented
steep exposed rail near (2853,4915) and four unrelated road-index endpoint
failures remain outside this work.
