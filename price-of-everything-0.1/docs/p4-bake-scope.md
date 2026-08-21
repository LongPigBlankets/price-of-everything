# P4 — Authored-map texture bake: implementation kickoff

*Scoped 2026-08-19 (owner asked to treat the slow game load as its own effort). The full
**design** already exists in [`map-editor-plan.md §7`](map-editor-plan.md); this doc is the
build plan on top of it — the problem it solves, the current state, the phases, and the bar
for "done". It does not re-specify the bake.*

## 1. The problem (measured)

The game boots slowly because the authored map's **roads and decorative fabric render as live
vector geometry every load** — the bake that was meant to replace them was never built.

- `authored_road_visuals.gd:17` states it outright: *"Vector rendering here is P1; P4 swaps in
  the per-tile baked textures."* Roads are drawn point-by-point with per-tile clipping on
  every match start.
- `authored_fabric_visuals.gd` / `urban_fabric_visuals.gd` re-run the full parks / plazas /
  farms / decorative-mass / forest geometry each load (thousands of polygons; the mid-century
  fabric file alone is ~6,900 lines of generator).
- Per-tile mask rasterization in `scenes/building_visuals.gd` (`_ensure_tile`) measured
  **~5.08 s** one-time at match-ready (PR #115 `tools/frame_anatomy_watcher.gd`).
- Decorative fabric + trees measured **~11.6 s** added to match-ready (PR #114), which is why
  they were split out / deferred rather than shipped hot.

None of this is gameplay: the per-tile infra flag/level is the only gameplay surface (2026-08-15
architecture ruling). It is all aesthetic geometry that is **identical every load** — the
textbook case for baking once and blitting.

## 2. Current state — what exists vs. what's missing

**Exists (P1, shipped):** the authored-map document (`data/map_authored/*.json`), the
`authored_map.gd` loader, and live vector renderers (`authored_fabric_visuals.gd`,
`authored_road_visuals.gd`, `authored_fabric_painter.gd`, the mid-century `urban_fabric_visuals.gd`).
The editor draws with the *same* painter code the bake will use (`map_editor_fabric.gd`) — so the
bake and the editor preview cannot disagree by construction.

**Missing (P4):** everything in §7 — the export step, the baked textures, the manifest, the
runtime texture layer, streaming. There is no `assets/authored_map/` output and no
`data/map_authored_bake.json`.

## 3. Build phases

Follow the `hills_baked` / `roads_baked` idiom throughout (cache, `reset_for_tests()`,
`source_hash()` staleness tripwire) — it is the established pattern and §7 is written against it.

- **P4.0 — Export harness.** One `SubViewport` (`transparent_bg`, `UPDATE_ONCE`) + the authored
  painter under `Transform2D(Vector2(s,0),Vector2(0,s),-origin*s)`, `await process_frame` +
  `frame_post_draw` (force-draw loop if occluded), `get_image()` → PNG. Windowed only (headless
  never draws). Bake **one texture per pitch-rect tile** (405×480 u → 540×640 px at
  `BAKE_SCALE=4/3`). Start with the **base** artifact (all always-visible layers) for a single
  settlement; prove pixel-exact reassembly against the live render before going wide.
- **P4.1 — Four artifact kinds.** base · unlock-overlay (a tile's own unlockable streets) ·
  connector patches (cross-tile unlockable strokes, own bounds rect) · sacrificial overlays
  (per-mass sprites the base excludes, drawn until evicted). Emit `data/map_authored_bake.json`
  (bake scale, per-texture world rects, connector tile sets, source md5, hills_hash).
- **P4.2 — Runtime swap.** Replace the vector `_draw` in `authored_fabric_visuals` /
  `authored_road_visuals` with textured `Sprite2D`/`draw_texture_rect` reads keyed off the
  manifest, gated on `AuthoredMap.is_active()`; keep the vector path behind a debug toggle for
  A/B. Roads stay zoom-invariant world geometry (owner ruling) — the bake gives that for free.
- **P4.3 — Incremental + streaming.** An edit rebakes only the tiles/connectors whose rects it
  intersects. At play, load textures for tiles intersecting the camera rect grown one ring,
  LRU-free beyond; rely on the import pipeline's VRAM compression (~4:1) + mipmaps. v1 may load
  eagerly on desktop; streaming lands before the web/itch build. (~350 KB compressed/tile → tens
  of MB resident.)

## 4. Risks / watch-items

- **Seam exactness.** The partition is the pitch rect, not the hex bbox (bboxes overlap by 135 u);
  every rect renders the same global geometry clipped at its edges so a stroke across a seam
  recomposes seamlessly. Verify with a diff against the live render, not by eye.
- **Coordinate discipline.** All tile↔world goes through `%TerrainLayer.map_to_local()` — never
  digit arithmetic on ids (§2). `tile_1_1` centre `(1080,1200)`; world rect `(0,0)–(13905,11760)`.
- **Staleness.** Boot must warn (not silently ship a stale look) when the bake md5 trails the
  document — the `roads_baked` idiom.
- **The bake is derived; JSON is the source of truth.** Never edit baked textures by hand.

## 5. Definition of done

- Match-ready on the authored Stoneshore map drops from the current ~15–20 s toward **a few
  seconds** (the vector-render + mask-raster + decor/trees costs above collapse to texture blits).
- The baked map is **pixel-indistinguishable** from the live render at every play zoom (A/B toggle).
- Editing one settlement re-exports a handful of 540×640 textures, not a region.
- `frame_anatomy_watcher` shows the build frame no longer dominated by fabric/road coroutine time.

## 6. Related

Adjacent to this: the parks-over-decor z-order bug (fixed 2026-08-19 — `urban_fabric_visuals.gd`
now suppresses the procedural fabric when an authored doc is active). PR #115
`tools/frame_anatomy_watcher.gd` is the measurement tool to re-run before/after; the
`map-editor-plan.md` §2/§9 seam and coordinate tables are the authority for the bake math.

---

## 7. As built (2026-08-20)

Shipped as one pass rather than P4.0–P4.3 in sequence. What differs from the plan above, and
why — each deviation is a simplification the data justified, not a corner cut.

**Two layers, not four.** The plan splits the bake into `farmland / forest / fabric / roads`
so live farm fields can tuck under an authored canopy (§6). That split also *changes today's
picture*: the current game draws all authored ground and fabric in ONE node
(`AuthoredFabricVisuals`), forests last. Baking to four layers at their §6 sibling positions
would have moved forests under the fabric as a side effect of an optimisation. So the bake
mirrors what is on screen now — `fabric` (everything that node draws, in its layer-major
order) and `roads` — and the four-way split stays available as a later, deliberate change.

**Static bakes, dynamic stays live** — replaces the plan's unlock-overlay and connector-patch
artifacts. A record is baked only if its visibility cannot change during a match; the rest keep
drawing as vectors over the texture. On this document that is 37 unlockable strokes of 324, so
the reveal rule keeps working with no new artifact kinds, no per-connector bounds rects, and
nothing extra to keep in sync. Worth revisiting only if that live remainder grows enough to
measure. `authored_bake_layout.gd` owns the predicate.

**Eviction repaints the tile at runtime.** The plan bakes each `sacrificial` mass as its own
sprite. That is not sufficient here: `building_visuals._evict_fabric_under` evicts ANY decor or
special under a footprint, not just the marked ones, so a texture would freeze buildings that
should have vanished. Instead the affected tiles are re-rendered in-match through the same
painter, minus the evicted ids (`authored_fabric_visuals._repair_evicted_tiles`) — the plan's
own named fallback, and the only mechanism that is correct for data-driven eviction.

**Disk is not the constraint; VRAM is.** 209 textures total **6.6 MB** on disk, not the ~48 MB a
uniform 540×640 estimate predicts — tiles are mostly transparent and flat art compresses hard.
Resident VRAM would be ~289 MB if all were held at once, so textures stream by camera rect
(`authored_bake.draw_layer` → `trim`) and the loading screen warms only the opening view.

**Zoom.** One texture set serves every play zoom: `BAKE_SCALE = 4/3 px/u` sits ~20% above the
~1.107 px/u maximum, so a tile is never magnified. The generalized far plate (§7) is deliberately
not built — it is the next step when the map is zoomed out far enough for mass detail to turn to
noise.

### The commands

```
# bake (windowed; --doc for any document, --tiles for an incremental re-bake)
<godot> --path . res://tools/map_editor/bake_authored_map.tscn -- --doc=stoneshore-procedural
# then import the new PNGs so the game can load them
<godot> --headless --path . --import
```

### Files

| file | role |
|---|---|
| `scripts/authored_bake_layout.gd` | the partition: pitch rects, cull, static/dynamic split (pure, unit-tested) |
| `scripts/authored_bake_painter.gd` | the painter node, shared by the export tool and the runtime repaint |
| `scripts/authored_bake.gd` | runtime manifest reader, staleness, streaming cache |
| `tools/map_editor/bake_authored_map.gd` | the export tool |
| `data/map_authored_bake.json` | manifest (per-tile world rects, md5, hills hash) |
| `assets/authored_map/<doc>/<layer>/<tile>.png` | the textures |
