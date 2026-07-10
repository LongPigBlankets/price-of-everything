# Building visuals — "ink & wash" look (spec, NO implementation yet)

Status: **spec only** (designer-approved direction, 2026-07-09). Companion to the
roads-v3 rebake; implementation starts only after the roads rebake lands and this
spec gets a final read.

Reference: the vintage hand-drawn hex-map board image (sepia parchment, inked hexes,
chunky red/mustard/grey building compounds, hatched fields, dashed lanes, rail with
ties). Target: our procedural buildings read like that plate while staying 100%
procedural, deterministic, and inside the existing `building_visuals.gd` `_draw`
architecture — **no sprite assets, no per-building nodes** (architecture rule 1).

---

## 1. What the reference is made of (deconstruction)

Squint at the reference and four separable ingredients emerge, in order of visual
leverage:

1. **Ink pass** — every shape carries a *uniform dark-sepia ink outline* plus interior
   linework: parallel roof ridges on terraced blocks, saw-tooth roofs on factories,
   bay-division lines, tiny rooftop vents/clerestories, chimney dots. This — not
   building size — is the main difference from our current flat-colour-with-pale-outline
   look.
2. **Massing** — buildings are *compounds*, not single boxes: a main hall fused with
   2–3 wings; urban housing is *one large block mass sliced into terraced strips* with
   thin gaps and courtyard holes ("draw larger buildings and slice into grids").
3. **Wash** — muted brick red / mustard / warm grey fills with per-building value
   variation; nothing saturated.
4. **Grunge & wobble** — paper grain across everything (fills sit *in* the parchment,
   not on it) and a slight hand-drawn wobble on edges.

## 2. Technique per ingredient (mapped to the current renderer)

### 2.1 Ink pass (highest leverage, do first)

- One global ink colour for ALL building outlines (e.g. `#3a2c18` @ ~1.2–1.5 px),
  replacing the per-category pale outline. Categories differentiate by FILL only —
  exactly like the reference.
- Interior linework, seeded per instance (`RoadHash.pick("ink|<iid>|<field>")`),
  drawn in the same `_draw` right after the fill polygon:
  - **Factories / heavy industry (grey):** saw-tooth roof lines across the short axis
    (pitch ~10–14 u), 1–2 rooftop vent rects, optional chimney dot at a corner.
  - **Warehouses / logistics (mustard):** 2–4 parallel ridge lines along the long axis
    (extend the existing player-only `ROOF_MARK` ridges to ALL buildings, restyled to
    ink).
  - **Urban/commercial blocks (red):** slice lines every ~12–16 u perpendicular to the
    frontage (terrace party-walls) + a ridge along the row.
  - **Tanks/silos:** ink circle outline + a small centre dot (already circles via
    subcomponents — restyle only).
- Derive line direction from the footprint quad's own edges (the ROOF_MARK code
  already does this correctly under rotation — reuse that derivation).

### 2.2 Massing

- **Compound industrial footprints:** compose 2–4 rects (main hall + seeded wings,
  wing area 20–40% of main) merged via `Geometry2D.merge_polygons` at placement time.
  The merged polygon is the ONE footprint: occupancy, roads-avoid discs, and the LOD
  blob all consume it unchanged. Visual scale may use the chunk-mode precedent
  (visual size decoupled from `tile_size_used`; economy untouched).
- **Urban perimeter blocks:** evolve chunk mode — a block cell renders as ONE mass
  (the cell rect minus a seeded courtyard hole on deep cells), then the ink pass
  slices it into terraces. Buildings in the cell keep their individual identity for
  the sim/panels; the *drawing* is per-cell mass + slice lines, with per-strip fill
  value jitter so strips read as separate houses. Click-mapping stays per-building
  (footprints unchanged in the placement list — only the draw representation merges).
- Explicit NON-goals: no footprint moves, no change to `tile_size_used` economics,
  no change to block/chunk template geometry or lot claiming.

### 2.3 Wash (palette)

- Category → fill mapping (muted triad, tune in-engine):
  - heavy industry / power: warm grey `#8d8a80` band
  - residential / commercial / urban production: brick red `#b0483a` band
  - storage / logistics / light industry: mustard `#c9992e` band
  - farms: keep current field greens/browns (already reference-like)
- Per-instance value jitter ±5% (seeded) so repeated blocks don't clone.
- NPC vs player: keep the current ownership distinction but express it inside the
  triad (e.g. player = slightly saturated + roof ridges; NPC = duller), NOT with a
  different hue family.

### 2.4 Grunge & wobble

- **Per-fill grain:** `draw_colored_polygon(..., texture=paper_noise)` with
  world-space UVs (one small seamless texture shared by every fill; zero per-instance
  cost). Also applicable later to hill bands.
- **Map-wide parchment:** ONE world-anchored tiled paper texture over the whole world
  (above terrain/roads/buildings, below UI/labels), `CanvasItemMaterial` multiply
  blend, low opacity. This unifies buildings + roads + the muted relief palette into
  the plate look. NOTE: multiply darkens/warms everything → schedule a small
  brightness retune of `hill_visuals.BAND_COLORS` right after it lands.
- **Wobble:** at DRAW time only — subdivide footprint edges every ~20 u, jitter
  perpendicular ±1.2 u, seeded. **The logic polygon is never wobbled** (occupancy,
  roads-avoid, tests, click hit-tests all keep clean geometry).

## 3. Guardrails (contract)

1. All jitter/variation seeded via `RoadHash` — deterministic across save/load
   (architecture rule 3). No `randi()`.
2. Draw-representation changes NEVER alter placement data: `_placements`, footprint
   discs, `footprint_version` semantics, occupancy, and the `footprint_discs ==
   placed_n` test invariant are untouched.
3. Perf: interior linework ≈ 4× primitives per building — fine under the 160 cull
   cap and change-only redraws. If a profile ever complains, the escape hatch is the
   `hill_visuals` cached-`ArrayMesh` pattern, not fewer details.
4. The parchment overlay is one node; it must NOT blend over UI (sits under the
   UILayer CanvasLayer) and must be world-anchored (no screen-space swimming).
5. LOD: the zoom-out grey-blob mode (polygon-buildings B6) draws blobs UNDER the
   parchment too; ink detail is vector-LOD only (skip interior lines when the
   texture LOD is active — same crossover the hills use).

## 4. Phasing (each step ships visibly on its own)

| Phase | Content | Est. size |
|---|---|---|
| I1 | Ink outlines + interior roof motifs for all buildings + palette triad + value jitter | ~100–150 LOC in building_visuals |
| I2 | Massing: compound industrial footprints + urban block mass w/ terrace slicing | ~150–250 LOC |
| I3 | Grunge: per-fill grain texture + parchment multiply overlay + band-palette retune | ~60 LOC + 1 small texture |
| I4 | Wobble + polish (chimneys, tank ink, vent rects) | ~60 LOC |

Verification per phase: windowed shot tools (Stoneshore closeup + relief wide shot),
before/after pair, plus the unit suite (`footprint_discs` invariant, block template
tests) — see `cnc-validation-and-qa`.

## 5. Out of scope here (tracked elsewhere)

- **Field linework** (plot boundaries + hatched strips on open rural green — big part
  of the reference's richness): terrain-layer feature; natural seed is the farm
  Voronoi kit. Separate spec when picked up.
- **Road/rail ink restyle** (dashed casings, rail ties): folds into the roads-v3
  atlas styling so it happens once, not twice.
- Tree/forest restyle: current canopy blobs are close enough; revisit after I3.
- Hex-border double-ink + map frame: cheap, but decide after the parchment lands.

## 6. Open decisions for the designer

1. Palette triad hexes above are first guesses — approve/adjust after an I1
   screenshot pass.
2. Urban terrace slicing: strips per cell (proposed: seeded 3–6) and whether
   courtyard holes appear on all deep cells or ~50%.
3. Does the player/NPC distinction stay colour-based at all, or move entirely to
   the roof-ridge marker?
4. Parchment opacity (proposed start: multiply @ 12–18%).
