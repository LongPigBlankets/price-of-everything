# Player colour + gameplay buildings as decorative massing — analysis

Status: **analysis only, nothing implemented.** Written 2026-08-24 against
`demo-itchio-speed` at `0aae4ae`.

The ask, in the owner's words:

> make gameplay building visuals also use similar shapes as the decorative ones (for non
> farm, non solar farm, non wind farm, non mine and non forest ones anyway) … the player
> picking a colour at game start and all their buildings are the same colour. Tile view
> panel also becomes the same colour … pick a few buildings per tile (or create them as
> they get built on sparser tiles) and truncate them for L1 then grow into the full size
> by L3.

That is four separable pieces of work with very different costs. Two are small and can
land this week; one is medium; one is a rework of the renderer's central assumption.

---

## 1. What is actually there today

### 1.1 Gameplay buildings are bespoke art, not generic polygons

This is the single most important correction to the premise. `scenes/building_visuals.gd`
(5,476 lines — combined store *and* renderer) draws each gameplay building from a
**per-type art routine**, selected by internal name:

```gdscript
const INK_ART_KEY := {
    "furnace": "furnace", "eaf": "eaf", "industrial_factory": "industrial_factory",
    ... "mine": "mine", "solar_farm": "solar_farm",
    "onshore_wind_farm": "wind_farm", "offshore_wind_farm": "wind_farm", ...
}
const MIDCENTURY_COMPOUND_ART := { 13 industrial types → true }
```

`scripts/building_shapes.gd` (the five generic kinds — `square, rectangle, l_base,
l_length, c`) is the *older* path, still used for footprint reservation and for types with
no art key. So "make gameplay buildings use decorative shapes" is not adding shapes to
something shapeless — it is **replacing thirteen hand-authored compound routines** with
massing derived the way the fabric derives it.

Excluding farm / solar / wind / mine / forest leaves exactly the `MIDCENTURY_COMPOUND_ART`
set minus mine: **furnace, EAF, industrial factory, consumer factory, assembly plant,
high-tech manufactory, petro refinery, chem plant, poly plant, electrolyser, power plant,
water pump** — twelve types.

### 1.2 The decorative fabric already does the massing the ask wants

`scripts/urban_fabric_visuals.gd` (6,911 lines) derives terraces, courtyard blocks, alleys
and open lots, and — crucially — already slices a mass into strips:

- `_dense_core_terrace_pieces(poly, desired, key)` — cut a block into N terraced lots
- `_dense_core_refined_mass_pieces(...)` — the same for irregular masses
- `_add_industry_support_mass(poly, tangent, ...)` — an industrial lean-to off a spine

`docs/building-visuals-ink-spec.md` §2.2 already specifies this as the intended direction
for gameplay buildings ("buildings are *compounds*, not single boxes … one large block mass
sliced into terraced strips"). It is spec-only and unimplemented. **This analysis is that
spec's implementation plan for the twelve industrial types.**

### 1.3 Colour is already a one-function hook, and ownership is already three-way

```gdscript
# scripts/map_style.gd
func block_top(fam: String) -> Color:
    if is_midcentury():
        return MapMidcenturyStyle.gameplay_block_top(fam)
    return plate_block_top(fam)
```

`fam` comes from `building_visuals._wash_family(category)` — one family per building
category (`extraction → grey`, `power → yellow`, `metallurgy → navy`, …). And the palette
comment already anticipates the ask:

> Three-way ownership read (owner 2026-08-11), which is also the reference's own block
> fabric: DECOR is cream, NPC is grey, **the player is coloured**.

So the map side of "all the player's buildings are one colour" is a change to *one*
function, plus a source for the colour.

### 1.4 …but the tile view panel has its own, separate colour table

`scripts/tile_view_data.gd` has a second category→colour mapping (`CAT_INFRA`, `CAT_MINES`,
`CAT_METALLURGY`, …) that knows nothing about `MapStyle`. Two tables, one concept. Any
player-colour work has to point both at the same source or the panel and the map will
disagree — which is exactly the bug class this repo keeps extracting shared helpers to kill
(`hex_stamp.gd`, `keyed_building_icon.gd`, `empire_graph.populate`).

### 1.5 Levels already grow buildings — in the opposite direction to the ask

```gdscript
## Lot side scales with tile_size_used from the smallest class to 3x for the
## biggest (owner's 10:30 ratio); levels never rescale the art — the L3 frame
## is the lot and upgrades annex into it.
```

Today the lot is reserved at **full L3 size from the moment a building is placed**, and an
upgrade fills that reserved frame with annexes (`SUBCOMP_ANNEX`, `WING_MIN_PARENT_AREA`,
`MatchState.building_upgraded` → re-derive subcomponents). The ask — "truncate for L1, grow
into full size by L3" — is the same *visual* outcome by a different mechanism, and the
current one was a deliberate choice: reserving the L3 frame up front is what stops an
upgrade needing to re-pack the tile and shove its neighbours around.

**This is the decision the whole L1→L3 piece hangs on** (see §4.1).

### 1.6 The known gap that bites: footprints are not persisted

`docs/polygon-buildings-spec.md` A1:

> **positions are NOT persisted.** `relayout()` re-derives every footprint from building
> **emit order**, so position stability across save/load is *not* guaranteed today.

Any scheme that says "pick a few buildings per tile and grow *those*" needs a stable
per-building visual identity across save/load. Today it does not exist. This is spec item
B7 and it is a prerequisite, not a detail.

---

## 2. The four pieces

| # | Piece | Size | Depends on |
|---|---|---|---|
| A | Player colour: pick it, store it, apply it (map + tile view) | **Small** | — |
| B | Decorative-style massing for the twelve industrial types | **Large** | — |
| C | Per-tile building selection ("a few buildings per tile") | **Medium** | B |
| D | L1 truncated → L3 full | **Medium** | B, C, and a decision on §1.5 |

A is independently shippable and worth doing first — it is visible, cheap, and does not
touch the renderer.

---

## 3. Piece by piece

### A. Player colour (small)

**Pick.** `scripts/new_game_panel.gd` already owns the start and length selectors; a row of
swatches belongs there. Use a fixed palette rather than a free colour wheel: the map's
colours are printed washes at ~0.55 saturation sitting in parchment, and a player-chosen
pure hue would not sit in that paper. Six to eight pre-tuned tones drawn from
`GAMEPLAY_BLOCK_TOPS` (navy, red, lime, blue, mustard, pink) keeps every option in-style by
construction. NPC grey and decor cream must not be selectable.

**Store.** `MatchState` beside `ruleset` / `scenario_name`, exported in `export_state()` and
read in `import_state()`. It is match state, not a user setting — two saves may differ.

**Apply.**
1. `MapStyle.block_top(fam)`: when the caller is a player-owned building and its type is not
   one of the five exempt families, return the player tone instead of the category tone.
   The cleanest shape is a new `MapStyle.owner_block_top(fam, owner)` so the NPC/decor reads
   stay where they are and the exemption list lives in one place.
2. `tile_view_data._category_color(bd)`: same rule. Better — **delete the second table** and
   have it call the MapStyle accessor, so the panel cannot drift from the map again.
3. `_wash_family()` keeps its category mapping for NPC buildings and for the exempt types.

**Traps.**
- Category colour is currently doing real work: it is how a player reads "that cluster is
  metallurgy" at a glance on a busy tile. Flattening twelve categories to one tone removes
  that signal from the map entirely. The compound art (§1.1) still differentiates by shape,
  which is the reference's own logic ("categories differentiate by FILL only" is the *ink*
  spec's rule and this inverts it). Worth confirming the owner wants that trade.
- `industrial_apron(family)` derives the yard wash from the same family, so aprons follow
  the player tone for free — check that a strong player colour does not make the yard louder
  than the building.
- Contrast against terrain: a lime player on a rural tile, a blue player on water. The
  palette should be pre-checked against the six terrain types rather than trusted.

**Estimate:** a day, including the swatch row and the save round-trip test.

### B. Decorative-style massing for twelve types (large)

The work is to derive an industrial compound the way `urban_fabric_visuals` derives a
terrace block, rather than drawing it from a per-type routine:

1. **A spine from the frontage.** The layout already finds road frontage
   (`BLOCK_MIN_ROAD`, `PACK_STEP`, the block packer). Reuse the same frontage run as the
   compound's long axis — which also finally fixes the documented "footprints are
   axis-aligned only, buildings don't align to roads" gap (spec A3).
2. **Slice into bays.** `_dense_core_terrace_pieces` already cuts a polygon into N pieces
   along its long axis. An industrial hall is the same operation with fewer, wider bays and
   a saw-tooth roof motif instead of terraced ridges.
3. **Hang the wings.** `_add_industry_support_mass(poly, tangent, ...)` exists and is what
   the decorative side uses for lean-tos. Gameplay wings currently come from
   `WING_MIN_PARENT_AREA` / `SUBCOMP_ANNEX` — retire that path onto this one.
4. **Keep one distinguishing mark per type.** With colour flattened by piece A, shape is
   the only remaining type signal. The chimney/tank/stack that each of the twelve currently
   draws should survive as a *motif on the generic massing*, not as twelve bespoke routines.

**Traps.**
- `building_visuals.gd` is 5,476 lines and is both store and renderer. Anything that touches
  massing touches placement. Budget for the seam, not just the drawing.
- The performance tests are already close to budget (`B4: ≤2% frames over 8ms`, road works).
  Terrace slicing per building per redraw is more polygon work than a cached art routine —
  measure before and after, and cache the sliced geometry the way placements are cached.
- `MIDCENTURY_COMPOUND_ART` and `INK_ART_KEY` are also consulted for the *lot* size
  (`ART_SIDE_MIN/MAX`, `ART_SIZE_OVERRIDE`). Massing changes change reservation, which
  changes packing, which changes how many buildings fit a tile. Re-run the density audit
  (`docs/map-density-audit-baseline.txt` is the baseline) after.

**Estimate:** the bulk of the work. A week for the twelve types with the density audit
re-run, assuming the frontage-spine step goes cleanly; longer if road alignment turns out to
be the hard part it has historically been.

### C. A few buildings per tile (medium)

"Pick a few buildings per tile (or create them as they get built on sparser tiles)."

Read as: a tile shows a **compound of a handful of masses**, not one mass per gameplay
building. Six furnaces on a tile become one works with six bays, not six separate halls.

- The grouping key already exists — the layout clusters same-type buildings via
  `W_SAME` (×50) and `TileViewData.category_key`.
- What is missing is the mapping from *building instance* → *bay within a compound*, kept
  stable as buildings are added and removed. That is §1.6's persistence gap in a harder
  form: not just "where is this building" but "which bay of which compound is it".
- Removal is the awkward case. A demolished building in the middle of a six-bay works
  cannot re-slice the compound without every other bay moving.

**Recommendation:** make the compound the persisted unit — a tile keeps a list of compounds,
each with a bay count and a member list — rather than deriving it from emit order each
relayout. That is spec B7 done properly, and C is a good reason to finally do it.

**Estimate:** two to three days on top of B, most of it in persistence and removal.

### D. L1 truncated → L3 full (medium, and needs a decision first)

Mechanically small once B and C exist: a bay's drawn extent becomes `level / 3` of its
reserved extent, and `MatchState.building_upgraded` (already connected) re-derives.

The decision is §1.5. Two options:

1. **Keep reserving the L3 frame; draw less of it at L1.** The lot is unchanged, so
   upgrading never re-packs the tile and never disturbs neighbours. The cost is that an L1
   building visibly occupies less ground than it has reserved, so a tile can look emptier
   than it is — which is the *opposite* of the complaint that led to the reserved-space work
   on the land bar ("a player looking at a tile with a big gap under the cap line was told
   there was room, and then refused").
2. **Reserve the L1 frame; grow the reservation on upgrade.** Honest ground use, but an
   upgrade can now fail to find room, or must shove neighbours — a re-pack on upgrade, which
   is precisely what the current design was written to avoid.

**Option 1 is the right call** given the land-bar history, provided the drawn-vs-reserved
gap is not readable as free space. Worth prototyping the L1 look on a dense tile before
committing.

**Estimate:** two days after B and C.

---

## 4. Risks and open questions

1. **Losing category colour on the map** (§3.A) — a real loss of information, traded for
   company identity. Confirm the trade.
2. **The L1/L3 reservation question** (§3.D) — needs an owner ruling before D starts.
3. **Perf** — B and C both add per-redraw polygon work to a renderer whose frame budget is
   already the suite's only chronic failure.
4. **Footprint persistence** (§1.6) — a prerequisite for C, currently a known gap.
5. **Scope check:** the exempt five (farm, solar, wind, mine, forest) keep bespoke art, so
   the map will mix two visual languages. Farms already have their own underlay, lanes and
   bridges, so this is the status quo — but with twelve types moving to generic massing the
   remaining bespoke ones will stand out more, not less.

## 5. Suggested order

1. **A — player colour**, standalone and shippable. Do the tile-view table deletion as part
   of it; that debt is cheap to clear now and expensive later.
2. **B7 — persist footprints/compounds**, because C cannot be correct without it.
3. **B — massing**, one type first (furnace is the most common and the best test), density
   audit re-run, then the other eleven.
4. **D — level growth**, after the owner rules on §3.D.

A alone gets most of the "these are *my* buildings" feeling for a fraction of the cost, and
it does not block or complicate B.
