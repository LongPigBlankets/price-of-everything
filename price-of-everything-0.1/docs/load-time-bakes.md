# Load time: what is baked, and when to re-bake it

A new game used to take **100 s** to reach the "Begin" button. It now takes about **19 s**, and
the worst single frozen frame went from 12.3 s to roughly 2 s. Nothing about the map changed:
the same 417 buildings stand in the same places, byte for byte.

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
| Start-building placement | 55 s | 10 ms |
| Harbour (`MidcenturyPortPlan`) search | 3.3 s | 2 ms |
| Tile panel + building detail panel | 1.1 s | after "Begin" |
| Goods Graph layout | 0.24 s | first open |

Two findings drove all of it. **Half the load was drawing a map nobody could see** — the loading
screen is opaque, but the renderer kept submitting the whole plate every frame at 9.5–17k draw
calls. And **the expensive half of placement was the visual half**: `MatchState.add_building`
for all 417 start buildings measures 4.5 ms; the search for where to put them was 32.5 s, plus
the ~22 s of yielded frames that searching forced.

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

## 6. What is left, in order

1. **Authored-map textures are ~10× oversampled at the opening zoom.** 209 tiles at 540×640 RGBA
   is ~289 MB; the full-map opening view warms about 150 of them (~207 MB) and pays the GPU
   upload on the first frame after the reveal — the 2–6 s "reveal warm", which is spent under the
   plate and so is invisible, but is now the largest single item. Each of those tiles covers
   roughly 60×55 px at that zoom. A quarter-resolution second layer in the same manifest would
   cut it about 16× and look identical.
2. **The loading screen costs 45–85 ms a frame on its own** — the hex lattice is ~1,832 draw
   calls, redrawn every frame. With the world hidden it is now the only thing rendering, so it
   sets the floor for every frame the build yields. A film would replace it with one draw call.
3. **`main.tscn` takes ~6.5 s to load on the worker thread** and ~1.7 s to instantiate on the main
   one. The worker half is covered by the loading screen; the instantiate is a real stall and is
   the one thing that must not land under a playing video.
