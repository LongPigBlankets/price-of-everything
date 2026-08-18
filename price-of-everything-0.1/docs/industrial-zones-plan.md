# Industrial zones — plan

**Status:** P0 authoring BUILT 2026-08-17 — the three kinds are drawable, validated, stored
and visible in the editor. Placement still ignores them; that is the next step (see
[Phases](#phases)).
**Replaces (partly):** authored slots as the primary placement mechanism. Slots stay; see
[What happens to slots](#what-happens-to-slots).

---

## Why

Authored slots pre-commit ground to a building before anyone knows which building will stand
there. The player picks by economics — the ore under the tile, the chain they are building —
not by the mix a designer guessed. A tile over good copper fills with mines while its other
slots sit empty; a town tile gets twelve identical furnaces.

This has now been patched three times in one day, each fix making the mismatch smaller
without removing it:

1. Four size classes, so a slot reserves only what its class needs.
2. **One** size class, so any non-infra building fits any slot.
3. Least-destructive fill order, so the decorative fabric survives until the tile runs out of
   clear ground.

A polygon removes the mismatch instead of shrinking it. A zone has no size, so there is
nothing to mismatch. It also matches the sim, which has always been elastic: a tile holds
`MAX_TILE_LAND` worth of `tile_size_used × SIZE_MULT[level]`, so six mines *or* thirteen
workshops, whichever the player builds.

Second reason, smaller but real: authoring effort. `stoneshore-procedural` carries 69 slots
across 31 tiles, each needing a position **and** an angle. A zone is one polygon per tile, and
the angle is already solved — `_place_frontage` turns a building to face its street.

---

## The insight that makes this cheap

Placement already runs on masks, and a second mask for a different kind of building already
exists.

`_ensure_tile` rasterises the tile into a `PackedByteArray` over a `GRID_COLS × GRID_ROWS`
grid of `CELL` units, marking which cells are buildable land. It builds **two**: `_tile_land`
for regular buildings, and `_farm_land`, which tolerates the outer 30% of a forest disc so
farms nestle closer to woods.

Every placer takes that mask as a parameter:

```gdscript
_place_frontage(tile_id, coord, base_verts, cat, placed_here, land, road_clear)
_place_edge(tile_id, coord, base_verts, placed_here, land, road_clear)
_place_farm(tile_id, coord, base_verts, placed_here, land, toward_river)
```

**A zone is a third mask of exactly the same shape.** Rasterise the polygon onto the same
grid, `AND` it with the land mask, hand the result to the placer that would have run anyway.
Nothing downstream changes — validation, road clearance, river avoidance, overlap tests and
`_crop_to_sprite` all behave identically, because they only ever saw a mask.

That is the whole placement-side implementation. The rest of the work is authoring, priority
and tests.

---

## Schema

A new `zones` list per settlement, beside `decor`, `specials`, `farms`, `forests`, `parks`
and `plazas`:

```json
"zones": [
  { "id": "z:stoneshore:0", "kind": "industrial", "tiles": ["tile_23_8"],
    "outline": [[x, y], ...] }
]
```

- `outline` in world units, same convention as every other authored area.
- `AREA_MAX_VERTICES` (8) applies, same as farms and forests.
- `tiles` is derived on save from which tiles the polygon touches, so a zone may span a tile
  boundary and each tile masks only its own part. (`AuthoredRoadGeometry.touched_tiles` already
  does this job for roads and can be reused.)
- `kind` is one of the three below. Validation rejects anything else, and a legacy-name map is
  **not** needed — this list is new.

### The three kinds

| kind | who may use it | when |
|---|---|---|
| `industrial` | any non-extraction building | first |
| `industrial_reserve` | any non-extraction building | only once `industrial` has no valid cell left |
| `extraction` | mines and wells only | always, and only these |

`extraction` is the one that earns its place immediately. Mines, oil wells and the renewable
farms are `OFF_ROAD_NAMES` today — a hardcoded constant sending them to seek a tile edge. A
zone makes that **authorable**: put the pit where the hillside actually is.

`industrial_reserve` gives a legible overflow rather than a hard stop — the town visibly
spills into its reserve before the tile refuses a building.

---

## Priority and fallback

Ordered attempts inside `_search`, each one just a different mask:

1. `extraction` zone, if the building is a mine or well.
2. `industrial` zone.
3. `industrial_reserve` zone.
4. Unzoned tile land — the current behaviour, and the fallback for every tile nobody has
   zoned. **This is what keeps the change additive:** an unzoned tile behaves exactly as it
   does today.

A building that is refused by every zone is refused by the tile, which is already a supported
outcome (`placed.is_empty()` → not drawn rather than overlapping).

---

## What happens to slots

They stay, and they stop being the bulk mechanism.

`_claim_slot` already runs first when a tile carries authored slots and falls through to
`_search` when it cannot seat the building. Constraining `_search` to zones means a tile can
carry both: a handful of slots where the composition matters — a hero building on a corner,
a plant that must front a particular street — and a zone for everything else.

So today's slot work is not wasted; it becomes the precision tool. Specifically these survive
unchanged and are worth keeping:

- the unified `standard`/`infra`/`area` classes and the derived boxes
- the least-destructive claim order, which **ports directly** to zones as cell scoring: prefer
  cells that overlap no decorative mass, and evict only when the zone runs out of clear ones
- the `evict` hook and the `sacrificial` weighting

---

## Phases

### P0 — authoring ✅ BUILT
Schema + validator for `zones` (one list, kind on the record); all three kinds drawable to
**10** corners against a field's 8; the editor panel section, the three colours, and the
`zone:` prefix that sorts a drawn polygon into the `zones` list. Zones declare the tiles they
cover on commit, so the mask can be built per tile without re-testing every polygon.

Also built: the **Extraction resources** visibility toggle, marking the 98 tiles that carry a
deposit other than water — water is on 104 tiles by itself and would bury what the overlay
exists to find.

### P0b — placement, NOT built
Rasterise a zone to a mask and have `_search` prefer it, falling back to tile land. This is
the half that makes zones do anything; see [The insight](#the-insight-that-makes-this-cheap)
for why it is small. Needs a headless test that a building lands inside the polygon **and
outside it when the zone is removed** — the second half matters, or it passes on a build
where zones do nothing.

### P1 — the three kinds and priority
`industrial_reserve` and `extraction`; the ordered fallback; the extraction gate on mines and
wells. Editor colours and panel entries driven off the kind list, not a hand-written trio —
these names have been renamed twice already in the slot work, and each time the hardcoded
copies failed as a broken editor rather than as an out-of-date check.

### P2 — fabric-aware cell scoring
Port the least-destructive ordering from slots: score cells inside a zone by the decorative
fabric they would displace, with `sacrificial` weighted as it is now, and evict only what a
placement actually covers.

### P3 — authoring quality of life
A per-tile readout in the editor — "fits 6 mines / 10 furnaces / 20 workshops at L1" — which
is the buildability lint already outstanding from the slot work, and is far more useful
against a zone than against a fixed slot count. Bulk-convert existing slots to a zone on a
tile, so `stoneshore-procedural`'s 31 slotted tiles do not need redrawing by hand.

---

## Open questions

**Does a zone bound the building's footprint, or only its centre?** Bounding the footprint
means a building never overhangs its zone, which reads cleanly but wastes the zone's edges and
makes small zones unusable. Bounding the centre is far more permissive and is how the mask
already works. **Recommendation: start with the centre** plus the existing validators, and add
footprint containment only if the art looks wrong. Cheap to change later; expensive to
discover late that every zone must be drawn 40u oversized.

**Should zones respect the terrain land cap?** They should not need to — `max_tile_land` gates
the sim independently, and a zone is presentation. But a zone big enough for twelve buildings
on a mountain tile that only permits four is a misleading thing to draw. The P3 readout is the
answer rather than a rule.

**What happens to a zone the player's roads later cut in half?** Roads are authored on these
tiles, so this is not the procedural problem it would otherwise be — but an unlockable road
appearing mid-game can split a zone. The mask is rebuilt per tile, so it self-corrects; the
question is only whether a building already standing in the severed half should be disturbed.
**Recommendation: no.** Placement is not re-run for standing buildings anywhere else either.

---

## Risks

- **`_ensure_tile` is a hot path.** Rasterising three more masks per tile costs time on world
  build, which has been optimised hard before (60s → 11s). Build zone masks **lazily**, on the
  first placement that needs one, and only for tiles that actually carry a zone.
- **Grid resolution.** `CELL` is 5.0 units, so a zone polygon is quantised to 5u. Fine for
  areas the size of a city block; visible if someone draws a thin sliver. The editor should
  warn below some area rather than silently producing an unusable zone.
- **Determinism.** Mask construction must not use `randi()`/`randf()` (rule #3). Rasterisation
  is pure geometry, so this is a review point rather than a design problem.

---

## Verification

Same standard as the slot work, which caught three real defects this way:

- headless unit tests on the mask itself: a cell inside the polygon is in, outside is out, and
  the `AND` with land never adds a cell land refused
- a placement test per kind: the building lands inside its zone, and lands elsewhere when the
  zone is removed — **the second half matters**, or the test passes on a build where zones do
  nothing
- extraction gate: a furnace is refused an `extraction` zone, a mine is not
- priority: with `industrial` full, the next building lands in `industrial_reserve`
- `tools/map_editor/real_document_check.tscn` extended to assert zones load from the real map
- every document still validates (`validate_documents.tscn`), and the map file hash is
  unchanged across any harness run — a harness has reached real map data twice now
