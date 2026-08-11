# Map style — "city plate" variant

A third map style, sitting beside `classic` and the default `ink` & wash look
(`docs/map_ink_wash_restyle_spec.md`). It targets the owner's reference plates —
a vintage printed city plan: extruded block masses and near-white paper streets
— **while staying inside the project's Sanborn / Booth idiom**, and (owner
ruling, decision 8) on the game's own green land rather than the reference's
cream. It reads as the same cartographer drawing a
denser downtown sheet, not as a different game.

Toggle it in the debug terminal:

```
toggle plate
```

`toggle ink` still flips ink ↔ classic, and leaving ink drops the plate with it.

---

## 1. What the reference actually is

Both reference screenshots show a top-down city map rendered like a paper model:

- **Ground is the street.** A warm cream paper; streets are the negative space
  between blocks, not drawn ribbons.
- **Blocks are raised prisms.** Irregular polygons in dark warm grey, each with a
  visible darker side face on its south/south-east edges and a near-black warm
  outline. Lit consistently from the north-west.
- **A second, lighter block family** in cream/tan sits among the dark ones.
- **Parks** are flat muted olive.
- **Water** is a light, comparatively bright sky blue — much lighter than the ink
  style's slate.
- **Brick red is rare** — a handful of landmark accents per screen, which is
  exactly what makes it read as an accent.

The whole palette is cream / tan / grey / olive, with blue water and rare red.
Value contrast between block and street is high; saturation is low everywhere
except the water and the red.

## 2. How that maps onto this game

The game's map is mostly countryside — relief bands, farms, forests, rivers,
coast — with industrial buildings scattered on tiles. There is no dense urban
block fabric to recolour, so the variant translates the reference's *language*
onto the features that exist:

| Reference | This map |
|---|---|
| Packed dark city blocks | Buildings, block masses and their subcomponents, drawn as prisms |
| Cream negative-space streets | Near-white paper road beds bounded by solid ink hairlines |
| Olive parks | Forest canopy — kept ink's green (decision 8), mildly extruded |
| Light sky-blue water | *Partly adopted* — water sits between classic and ink, not the reference sky |
| Cream paper ground | *Not adopted* — the plate shares ink's green land (see decision 8) |
| Rare brick-red landmarks | Farm barns and red-majority courtyard masses only |

**Elevation.** The reference is flat; this map has gameplay relief. Nothing is
done to it — the plate inherits ink's band ramp and its contour hairlines, which
is how period plates drew relief anyway.

## 3. Locked decisions

1. **Ownership is a THREE-way read (owner 2026-08-11):** decorative buildings
   cream `#efe9db`, NPC grey `#8f8d85` with a deeper side face (0.52 darkening
   against the standard 0.32), player buildings coloured. Cream took over the
   paper-white the NPC used to hold. This is also the reference's own block
   fabric — grey masses, cream masses, rare red — arrived at from the game's own
   ownership semantics rather than imposed on them.
2. **One light, one model.** Every solid mass is an opaque prism: wobble the
   polygon, offset the wobbled points toward the SE, draw that silhouette *under*
   the top fill. Only SE-facing edges show a side face. No gradients, no soft
   shadows, no per-layer private shadow values.
3. **One linework ink.** Plate draws every stroke in `#4a4136`, including the
   procedural industrial art (which keeps its own darker `#2f2b26` for ink mode
   behind a plate-gated helper) and the residual local ink constants in
   `building_visuals.gd`.
4. **The micro-shadow is replaced, never doubled.** `building_shadow_color()`
   returns transparent in plate; the prism carries the depth.
5. **Streets are channels, not ribbons.** The bed sits within a couple of value
   points of the lowland ground; solid ink hairline edges carry the read. The
   ink style's dashed casings and trunk centre dash are dropped — dashes are
   survey symbology, and the plate idiom bounds streets with the block-edge line.
6. **Flat things stay flat.** Relief bands, roads, water, farm fields, decks and
   pits take no extrusion. Extruding ground fights the block prisms.
7. **Red stays rare.** One brick red map-wide (`#b0483a`), reserved for farm
   barns and red-majority courtyard masses. Ordinary urban-family buildings draw
   khaki.
8. **The plate does NOT re-grade the land.** Two cuts tried: first the
   reference's cream, then a pale sage holding the same lightness. Both were
   rejected by the owner (2026-08-11: *"I preferred the old green colour for the
   landmass"*). The plate shares ink's green ramp, its canopy green and its farm
   tints. **This is the defining decision of the variant**: the plate is not a
   re-grade of the ground, it is a re-treatment of what stands on it.
   The cascade is worth understanding, because several values are ink's *because*
   of this. On a mid-value green ground the figure/ground relationship inverts
   back to ink's, so buildings and canopy must read light-on-dark rather than
   dark-on-light. Specifically: the canopy returns to bottle green (an olive
   canopy sat within a hair of the green ground and the woods vanished), and the
   dark NPC block that suited cream was dropped — NPC is now grey, with cream
   reserved for decor (decision 1).
9. **Streets are the lightest thing on the map.** One near-white warm paper
   (`#f4efdd`) for both tiers. On the green land that reads as a bright street
   web — which is the Booth idiom, and is what carries the plate character now
   that the ground is not doing it. Trunk and local share the bed; width and edge
   alpha carry the hierarchy. Dashed casings are dropped.

### What actually distinguishes plate from ink, after decision 8

The land, canopy, farms and ownership cue are now shared with ink. The variant is:

1. **Extruded blocks** — every solid mass is a prism (the largest difference).
2. **Paper streets** — near-white beds, solid ink edges, no dashes.
3. **Water returned toward pre-ink** — `#3f7cc4`, between classic's saturation
   and ink's slate. The first two cuts (ink slate, then a pale plate sky) both
   went too far from the original; the sea's land-base band tracks band[1].
4. **Quieter, patchy paper** — see the parchment section.

### Decorative buildings — court apartment blocks

One per tile, on every land tile — including tiles nobody has built on, which is
the point: the map should read as inhabited before the player touches it.
(Supersedes the 2026-08-08 ruling's per-terrain counts of rural 1-4 / hill 2-3 /
mountain 0-2 / urban 4-10, and answers its open question about how a building
that is "neither NPC nor player" should read.)

**The form is a court** — the Berlin/Vienna *Hof*: a seeded rectangle with SOME
corners chamfered (never none, or it is just a box), wrapped around an inner
courtyard of `DECOR_WING` = 8.5u thickness that is **even on every side**. The
courtyard is inset from the *placed* polygon rather than the local one, so the
wing stays even whatever rotation the frontage search picked. A yard that comes
out under 40u² is dropped and the block draws solid.

**Rooflines say apartments**: a ridge down the centre of every wing, with party
walls every `DECOR_BAY` = 9u across it. Chamfer faces shorter than 6u carry no
roof — at that length the linework just reads as noise.

**Sized to an L1 factory.** Outer side 34–46u seeded, against `ART_DRAWN_MIN` =
40u, so a court sits in the same register as the industry around it rather than
as scenery. If the full size will not fit, one 0.78× attempt follows before the
tile is left without one.

They go through the **same frontage search** as a real building, so they snap to
a road when the tile has one, and they draw with the same wobble, prism and
outline. Only the fill differs.

What keeps them safe is that they live in their own dictionary, not in
`_placements`: occupancy, footprint discs, the road layer's terminus
suppression, and every placement statistic are blind to them. Real buildings
never collide against decor either — instead a tile's decor is re-placed
whenever its buildings change, so **the decor is what moves out of the way**. A
tile where nothing fits (mountain, water, a full tile) simply has none.

Placement is paced at `DECOR_FLUSH_PER_FRAME` tiles per frame from `_process`,
because the whole map marks itself dirty at once when the match-start seeding
window closes and 286 frontage searches in one frame is exactly the stall the
load path has been tuned to avoid. Measured cost: match ready 18.99s → 19.30s.

## 4. The seam

`scripts/map_style.gd` gains `plate: bool` beside `ink: bool`:

```gdscript
func set_plate(on: bool) -> void   # plate implies ink
func set_ink(on: bool) -> void     # leaving ink clears plate
func is_plate() -> bool            # the one public predicate: ink and plate
```

Getters branch through a named `Style` enum and a `_c3(classic, ink, plate)`
helper, so a getter the plate doesn't change is not edited at all and simply
inherits the ink value. `plate` defaults false, is set only by the cheat, and is
never serialized — so **classic and ink are byte-identical by construction**.

Shared extrusion API (every layer that extrudes uses these, nothing hand-picks):

```gdscript
enum Extrude { NONE, MILD, FULL }
func extrude_offset(tier) -> Vector2   # FULL (3,4), MILD (1.5,2), else ZERO
func extrude_side(fill, tier) -> Color # fill.darkened(0.32 / 0.20), opaque
func extrude_outline() -> Color        # the plate ink, FULL masses only
func extrude_outline_width() -> float  # 1.5
```

`extrude_offset()` returning `Vector2.ZERO` outside plate is what makes every
extrusion site self-skip — there is no `if plate` in the draw code.

**Tiers.** FULL: buildings, block masses, subcomponents, generated industrial
art prims, farm barns and silos. MILD: forest canopy, bridge decks. NONE: roads,
water, relief bands, decks, pits, pipes and cables, hatch linework.

## 5. Palette

| Role | Value |
|---|---|
| Linework ink | `#4a4136` |
| Land ramp, canopy, farm tints | **shared with ink** — unchanged |
| Water | `#3f7cc4`; sea depth ramp `#13387f` → `#3f7cc4`, land base tracks band[1] |
| Road bed (both tiers) | `#f4efdd` — the map's near-white |
| Street edge local / trunk | ink @ 0.68 / 0.85, ~1.5u per side |
| Decorative building | `#efe9db` cream |
| NPC block | `#8f8d85` grey, side face darkened 0.52 instead of 0.32 |
| Player blocks | navy `#58697a`, power `#be9c3c`, refinery `#9e6b79`, electrochem `#8c9757`, manufacturing `#b3743f`, extraction `#9e9382`, logistics `#c1922c`, water `#77a0b4`, urban `#c2b08a` |
| Brick accent | `#b0483a` |
| Ruins | `#7a5f43` |
| Farm tracks | `#ddd3ae` — paper, held well back so a lane never out-reads a road |
| Parchment grain | quieter and patchy — see below |

### Parchment grain

Ink's paper is heavy, even tooth: the noise maps linearly from a `(0.82,0.77,0.67)`
floor to white, so **every** pixel carries some grain. The plate is a printed
sheet rather than a hand-washed one, so its paper is quieter and, more
importantly, **uneven**. Three changes, all plate-only:

- **Gentler floor** — `(0.90,0.88,0.83)`, roughly 10% darkening at its deepest
  against ink's ~33% in the blue channel.
- **Shaped ramp** — four stops at `0.0 / 0.38 / 0.70 / 1.0`, with the middle two
  parked on clean paper. The sheet is therefore *untouched* across most of its
  area, and tone only surfaces where the noise runs to its extremes. This is the
  lever that makes it patchy rather than uniform, and it costs nothing: same one
  texture, same single multiply, just more gradient stops.
- **Coarser scale** — frequency `0.035 → 0.014`, octaves `4 → 3`, tile
  `256 → 512 px`. Broad soft blotches instead of fine speckle, and the tiling
  repeat doubles so it is harder to spot.

Measured on a flat patch of open ground: pixels carrying no grain went from
**40% to 69%**, and mean high-frequency residual fell 6.79 → 5.69. Note that
*total* stddev rises slightly — that is the point, not a regression: the broad
blotches are deliberate, and it is the fine speckle that was removed.

**To go quieter still,** widen the clean band (`0.38 → 0.75`) or lift
`_PARCHMENT_PLATE_DEEP` toward `0.95`. To bring the tooth back, narrow the clean
band toward the ink two-stop ramp.

## 6. Files touched

- `scripts/map_style.gd` — the seam, the extrusion API, every plate value.
- `scripts/debug_terminal.gd` — the `toggle plate` cheat.
- `scenes/building_visuals.gd` — the prism recipe, plate block tops, roof-motif
  contrast, subcomponent and farm-outbuilding prisms, local-ink routing.
- `scripts/ink_building_gen.gd` — plate-gated ink helper; the existing silhouette
  pass doubles as the extrusion pass (decks excepted).
- `scripts/forest_visuals.gd` — canopy colours via the seam; per-lobe MILD
  extrusion discs; a `style_changed` rebuild hook.
- `scripts/road_network_visuals.gd` — solid casings when undashed; MILD bridge
  deck prism.
- `scripts/hill_visuals.gd`, `scripts/port_visuals.gd` — ink routing, port wash.
- `scripts/parchment_overlay.gd` — ramp shape and grain scale read from the seam
  (they were hardcoded), so the style flip re-scales the noise as well as
  re-tinting it.

**No sim, save, layout, bake or gameplay contact.** Road layout, footprints and
`flagged_tiles` are untouched; this is draw-only.

## 7. Verification

- `python3 tools/run_tests.py` — includes `_test_map_style_plate`, which pins the
  classic and ink values of every getter the variant touches and the seam
  semantics (plate implies ink; leaving ink clears plate).
- `<godot> --path . res://tools/map_style_shot.tscn --quit-after 4200` — captures
  ten framings in all three styles and asserts the toggle round-trip.
- Byte-identity was confirmed empirically: baseline (pre-variant) classic and ink
  renders were diffed against the variant build across all seven shared framings.
  Twelve of fourteen were pixel-identical; the two that differed did so only
  inside a lower-left HUD toast rectangle that also differs between two runs of
  identical code. The map layers themselves are unchanged.

### Harness note

`await RenderingServer.frame_post_draw` never fires when the window is occluded,
which hung the harness and, before that, silently produced stale captures — seven
framings hashed identical. It is now `RenderingServer.force_draw()`, which renders
and swaps synchronously and does not depend on window state.
