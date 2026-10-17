# Load time: what is baked, and when to re-bake it

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
