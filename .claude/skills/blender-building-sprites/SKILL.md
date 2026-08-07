---
name: blender-building-sprites
description: Load this to create or modify 2.5D building sprites for Carbon and Capital in Blender - new building types, level variations (L1/L2/L3), style tweaks, or re-renders. Covers the locked WPA/midcentury style contract (iso camera, Freestyle ink, no cast shadows), the parametric builder pattern, geometry gotchas (z-fighting, cylinders, missing intersection seams), the print-texture pass, and the owner's screen-direction vocabulary.
---

# Blender building sprites — the 2.5D asset pipeline

Building sprites are rendered in Blender and post-processed to match the goods
icons' "midcentury industrial poster / WPA catalogue" style (the owner's term).
Reference icons: `assets/icons/goods/medium/g_008_motor.png`, `g_066_graphite.png`,
`g_056_ice_car.png`. The pilot (industrial goods factory, 3 levels, owner-approved
2026-07-29) defines every convention below.

## Where things live

```
/Users/crisu/Price of Everything/blender-assets/       # OUTSIDE the git repo
├── industrial_goods_factory.blend    # master .blend: the rig + every BLDG_* collection
├── sprite_kit.py                     # ⭐ START HERE — materials, primitives, assemblies
├── kit_sampler.py                    # renders one of every assembly (kit self-test)
├── factory_builder.py                # build_factory(level)   — predates the kit
├── furnace_builder.py                # build_furnace(level)   — predates the kit
├── stylize.py                        # print pass (stipple-as-shading)
└── sprite_export.py                  # square crop + exact-pixel padding
```

Blender 5.2 LTS at `/Applications/Blender.app`; drive it via the **official
Blender MCP** (`mcp__blender__*` tools; see auto-memory `blender-mcp-setup` for
install/config — server needs a GUI Blender running, addon autostarts on :9876).
Verify visually yourself: render via `render_viewport_to_path`, Read the PNG,
and inspect close-ups by cropping with PIL — never ask the owner to check
something you can see.

## The style contract (locked — do not re-derive)

- **Camera**: true isometric orthographic. Rotation `(54.736°, 0, 45°)`, location
  `target + normalize(1,-1,1) * distance`, `ortho_scale` to frame. All buildings
  and all levels share one camera so the set is coherent.
- **Light**: one sun, `use_shadow = False`. **No cast shadows ever** — form reads
  from flat face tones only; cast shadows render as smudgy artifacts in this style.
  Flat-shaded faces (`use_smooth = False` everywhere) give cel shading for free.
- **Ink**: Freestyle, absolute thickness. Two linesets: `ink` (silhouette+border+
  crease+edge marks, color ~`(0.055, 0.065, 0.13)`, 2.4px) and `contour`
  (external contour only, `(0.045, 0.055, 0.11)`, 7px). Heavy outer line is the
  icons' signature.
- **Film**: transparent. Render 1024×1024, EEVEE.
- **Palette** (flat Principled, roughness 1, specular 0 — sheen breaks both the cel
  look and stylize.py's glass test. Canonical copy: `sprite_kit.PALETTE`, addressed by
  ROLE via `K.mat("pipe")` etc.):
  brick `(0.318,0.118,0.082)` = the one warm accent; roof/slate `(0.208,0.262,0.318)`;
  glass `(0.055,0.075,0.140)`; mullion cream `(0.780,0.760,0.700)`; concrete;
  door; darkmetal; ink_black `(0.028,0.032,0.055)`; silver `(0.700,0.720,0.760)`;
  steel_navy; annex_grey; stack_grey; tank_grey; heat_red; plus `ember` (emissive
  fire) and `seam` (unlit navy joint bead).
  **One warm accent per building** — everything else stays desaturated slate.
- **Owner's direction vocabulary** (screen space at this camera):
  "back" = top-right = **+Y** · "right" = lower-right = **+X** ·
  "front" = bottom-left = **−Y** · "left" = upper-left = **−X**.
  E.g. the factory chimney is at the back-right corner (+X,+Y).

## The builder pattern — START FROM THE KIT

A new building is a **parameter file over `sprite_kit.py`**, not fresh geometry.
The kit holds the palette, the render rig, the primitives and — most importantly —
the ASSEMBLIES, each one extracted from approved work *including the fixes it cost*.
Re-deriving a chimney, a stair or a duct merge by hand is the single most expensive
mistake available here: the furnace's two-into-one junction alone took four attempts.

```python
exec(open("/Users/crisu/Price of Everything/blender-assets/sprite_kit.py").read())
exec(open("/Users/crisu/Price of Everything/blender-assets/mine_builder.py").read())
build_mine(2)
```

Skeleton for `<building>_builder.py`:
```python
LEVELS = {1: dict(...), 2: dict(...), 3: dict(...)}     # per-level PARAMETERS only

def build_mine(level=2):
    p = LEVELS[level]
    setup_rig()                                  # locked camera/sun/Freestyle, idempotent
    K = Kit(open_collection("BLDG_mine"))        # fresh collection, others auto-hidden
    K.box("hall", ...)                           # massing
    K.window("w0", "+X", (x, y, z), 0.50, 0.72)  # assemblies do the detail
    K.chimney_square("stack", x, y, top, base_top=..., collars=(...))
    print("\n".join(K.validate(ground=0.0, roof=(1.95, x0, x1, y0, y1))))
    return {"level": level, "objects": len(K.col.objects)}
```

**Assemblies available** (all on `Kit`):
| call | gives you |
|---|---|
| `window(name, face, centre, w, h, cols, rows)` | glass + frames + sill + mullion grid |
| `door(...)` / `gate(...)` | ribbed leaf + lintel; `glow=True` for an ember-lit interior |
| `arch_opening(name, centre, normal, hw)` | arched hole, incl. the cylinder-shell rules |
| `stairwell(name, x, y0, y1, z0, z1, flights, steps)` | switchback; returns `top` + `post_x` |
| `walkway(name, x0, x1, y, z, extend_to=…)` | deck + half-height guardrails |
| `chimney_square(...)` / `chimney_round(...)` | the two stack variants |
| `merge_pair(name, a, b, r, tower_top, merge_z, exhaust_top)` | two stacks → one exhaust |
| `pipe_run(name, waypoints, r, ends=(…))` | straights + quarter elbows + end treatment |
| `pipe_end(...)` | `collar` (shell penetration) / `cap` / `flange` |
| `tank(name, cx, cy, r, h, riser=…)` | vessel + lid + seams + riser collar |
| `washer(...)` / `seam(...)` / `seam_bar(...)` | pipe-through-structure hole; joint beads |
| `terraced_pit(...)` / `terraced_pit_poly(...)` | stepped pit; rectangular / outline-driven |
| `poly_bean/poly_rect/poly_offset/point_in_poly` | outline maths for organic massing |
| `spiral_road(polys, tops, j0, w, ground_fn=…)` | haul road spiralling down benches |
| `poly_band(...)` / `seam_band(...)` | ore/coal vein lying ON a pit wall |
| `headframe(...)` / `shaft_cutaway(...)` | winding tower; section drawn on a cut edge |
| `excavator(name, cx, cy, z)` | tracked machine, silhouette-first |
| `cooling_tower(...)` | true hyperboloid shell on a raking colonnade; returns `radius_at(z)` |
| `flue_stack(...)` | banded steel flue — bands are MATERIAL SLOTS on one mesh, not rings |
| `transformer(...)` / `substation_gantry(p0, p1, …)` | yard equipment; gantry takes endpoints |
| `pylon(..., tiers=N)` | L-series lattice pylon; `tiers` are PAIRS (1/2/3 → 2/4/6 arms) |
| `lattice_mast` / `insulator_string` | substation sub-parts, both fine-inked |
| `turbine(...)` | stepped LP casings + generator drum |
| `furnace_stack(..., r_top=, z0=)` | fired heater; TAPER sells its height, `z0` lets it rise out of a roof |
| `flame(...)` | ONE lofted mesh — tilted droplet. Stacked cones ink as separate party hats |
| `dome_cap(...)` | half-ELLIPSOID: rise and radius independent, so a tank cap is not a hemisphere |
| `flat_tank(..., roof_rise=)` / `dome_vessel(..., dome_ratio=)` | storage / process vessels |
| `sphere_tank(...)` | Horton sphere on braced legs |
| `float_tank(...)` | mixing vat: an ANNULUS, so the floating roof recesses inside the rim |
| `ring_rail` / `tank_balcony` / `ladder` | access kit — put them on a face the camera SEES (+X, −Y) |
| `apron_slab(pts, …)` + `slab_outline(items)` | concrete pad; outline is an OCTAGON, see below |
| `tone(mat, f, tag)` / `gloss(ob, …)` | fake-reflection banding by material SLOT (see below) |
| `pump_skid` / `valve_skid` | ground plant; the skid ribs follow its own long axis |
| `roll_stack(..., rod=, z0=)` | rolls of sheet, ends to camera, spool rod proud of both faces |
| `gantry_crane(x0, x1, y, z, …)` | bridge + trolley + hoist + a solid-colour cab |
| `bullet` / `bale_stack` / `conveyor_bridge` / `pipe_rack` | as before |

**`gloss()` — fake reflections, and why it is material SLOTS.** Freestyle linesets do not select
material boundaries, so extra slots on ONE mesh give hard-edged, UN-INKED bands; a separate band
object gets its own 7px contour and reads as a collar. Bands are placed by SCREEN position: for a
face with horizontal normal `(cos t, sin t)`, `u = cos(t − 45°)` is exactly where it sits across
the shell's visible width (−1 left silhouette, 0 camera-facing, +1 right). Tune per material
family — the AgX curve is steepest at the dark end, so a multiplier that reads as shading on steel
turns a dark sphere near-black, and there is NO headroom above `silver` (0.62 and 0.80 land 10
luma apart) so a glint on pipework is invisible. Leave caps at base tone or a hard horizontal seam
crosses the vessel top.

**A slab outline is an OCTAGON, not a rectangle.** `slab_outline()` takes the equipment as
`(x, y, r)` discs and cuts the bounding box with the four DIAGONAL supporting lines. Two of a
rectangle's corners are empty and project furthest along the screen diagonal — measured at ~150px
of sprite width for nothing. Pad the footprint of anything standing near the slab EDGE: the
outline bounds footprints, but a raised object on the rim projects past that rim and reads as
hanging off the slab.

**The AgX curve, MEASURED on this rig (2026-07-31)** — −Y vertical cube faces, centroid-sampled
after ray-casting each face so a reading cannot land on ink or a neighbour:
`0.150→L123  0.238→L134  0.318→L151  0.400→L160  0.480→L171  0.620→L181  0.700→L188  0.800→L191`
(top faces ~7 higher). It is COMPRESSIVE but does **not** saturate at 0.28 — the earth-ramp note
below is specific to pit-wall orientations and must not be generalised. It does flatten past ~0.6.

**The value ceiling applies to every large surface, not just earth.** Anything above base
~0.28 renders within a few luma of everything else, so a big plate of `concrete` (0.56) or
`tank_grey` (0.40) comes out a blank white. The power plant needed three new tones for exactly
this: `shell` (tower concrete), `chalk` (white walls, held low enough that lit and shaded faces
still separate ~L170 vs ~L140), `pad` (switchyard concrete, sitting BETWEEN pale walls and dark
decks) and `deck` (a genuinely dark flat roof — without it a plant built from the existing
greys measured a 26-luma spread, i.e. one flat mid mass).

**Materials by ROLE, not by colour**: `K.mat("ground")`..`K.mat("ground_deep")`
(5-tone earth ramp, `pit_mats()` spreads it), `K.mat("coal_seam")`/`K.mat("coal_upper")`,
`K.mat("ore_seam")`, `K.mat("pipe")`, `K.mat("stair")`,
`K.mat("walkway")`, `K.mat("wall_brick")`, `K.mat("wall_steel")`,
`K.mat("window_glass")`, `K.mat("window_frame")`, `K.mat("vessel")`, `K.mat("hot")`.
Says what the thing IS, so a palette retune lands everywhere at once. Raw palette
names still work.

**`K.validate(ground=…, roof=…)` before you render.** It flags members dipping below
the floor and anything crossing a roof plane *inside* the footprint, and prints the
world bbox. Most of this session's render-and-zoom debugging cycles — the lift through
the roof, the cage under the ground, the bunker into the eave — were findable this way
for free. Render to CONFIRM, not to SEARCH.

`kit_sampler.py` builds one of every assembly in a row (`build_sampler()`), which is
both the kit's self-test and a visual reference.

**factory_builder.py and furnace_builder.py predate the kit** and still carry their own
inlined copies. Their geometry is owner-approved — do NOT refactor them onto the kit
without re-approving the renders. Fix shared shapes in the KIT; new buildings get it.

**Level grammar** (how upgrades read): levels share one footprint story —
upgrades EXTEND, they never relocate. L1 = modest same-bones version (fewer
features, no chimney/annex); L2 = the canonical building (+capability: length,
chimney, loading bay); L3 = adds a NEW LANDMARK element on the only free side
(process annex, pipes) — "more of the same" alone undersells an upgrade. Check
which sides are already occupied before planning growth; the factory grows
lengthwise L1→L2 because L2's ends are taken (loading bay front, chimney back).

Two level sets exist. FACTORY: bays 4/5/5, L1 no chimney+gate, L2 +chimney+loading
bay, L3 +back-right process annex. FURNACE (`furnace_builder.LEVELS`, flags
merge/lift/annex/scaffold/tanks): L1 = bare plant — two SEPARATE capped chimneys,
no hoist, no scaffold cage, ONE process tank; L2 = still separate chimneys, gains
the scaffold cage, the second (front-left) tank, and a VERTICAL hoist shaft on a large
ridged storage bunker standing behind the chimneys (bunker width matches the L3 annex's
1.55, so both levels' side structures read as one kit of parts). An inclined trussed
gantry was tried first and abandoned: every variant fought the camera — pure +Y is
geometrically "behind" but projects to almost no screen width and hides entirely, a
back-right diagonal stays visible but its foot swings so far out that L2 overtakes L3
in the shared-scale export, and the inclined deck needs a bespoke trapezium prism (flat
foot, vertical top cut) because an oriented box caps both ends perpendicular to the run;
L3 = the pair MERGES into one exhaust and the gantry is REPLACED by a two-floor
charging house at the back-right — dark grey, FLAT roof level with the hall, half
the hall's depth, wide ember-lit doorway on the front, a four-flight TRUE switchback stair
(flights alternate SIDE as well as direction, so consecutive runs sit beside each
other — alternating direction alone stacks them in one column and reads wrong), and
a guardrailed roof walkway running to the furnace cage. Narrowing the treads to 0.30
and using 6 shallower steps per flight makes the two parallel runs no wider overall
than the single stacked run was.
A level may swap a feature out rather than only adding: L3 trades the exposed
hoist for a proper charging house, which still reads as an upgrade.
Merge geometry (L3), after three failed attempts — build the duct PATH explicitly
in three parts and sweep it: (1) a short VERTICAL lead-in coaxial with the tower,
(2) a constant-radius fillet turning exactly 45 deg, (3) a straight 45-deg run into
the stack's foot, which is a downward-flaring OVAL breeches piece (`oval_cone`)
that swallows both arrivals: elliptical, widening ONLY along the axis joining the
two chimneys and staying stack-narrow across it, closing to a circle at the top to
meet the round stack. A circular flare balloons on the two empty sides; a
flat-bottomed drum meets the ducts as a visible step. Start the flare just ABOVE
where the ducts converge so its open bottom rim hides behind them — any lower and
that rim reads as a dark line floating in the gap between the tubes. Make the
swept sleeve a hair fatter than the tower (+0.012) so the coaxial overlap cannot
z-fight. What does NOT work, and why:
 * a Hermite whose START tangent points at the target leaves the shell at ~39 deg
   immediately, opening a V-notch on the outside of the bend;
 * patching that notch with an extra cylinder along the bisector bulges past the
   silhouette;
 * a MITRED joint reaches `tan(67.5)*r` (~2.4r) below the kink on the outer side,
   so unless the sleeve extends at least that far the vertical section inverts and
   leaves an open hole exactly there. Curvature, not cuts.
(NURBS/curve-with-bevel is the same tube `sweep()` already builds — it would not
have fixed any of these, because every one was a fault in the PATH.)

## Geometry rules (each one cost a debugging round)

1. **No coplanar faces.** Two faces in the same plane z-fight into smears.
   Sink intersecting volumes ≥0.03 into each other; applied details sit proud by
   `EPS = 0.015`.
2. **Square > round by default.** Low-seg flat cylinders show faceted gradients
   under cel shading; square columns shade flat and take ink cleanly. The
   factory chimney is square for this reason. When a round form is wanted
   deliberately (the furnace towers), follow rule 6 instead.
3. **Freestyle cannot ink face intersections** (T-junctions between separate
   meshes have no edge). Where volumes interpenetrate visibly, add explicit
   seam geometry: thin beads (~0.032 sq) with the `ink_seam` material (black
   base + Emission `(0.012,0.016,0.045)` strength 1 → constant navy, matches
   linework unlit). Pattern: vertical bead at wall junctions, horizontal bead
   where a tower exits a roof slope, a square "flashing" collar where a tower
   pierces a flat roof.
4. **Windows** are assemblies: proud glass plane + 4 frame strips + sill +
   mullion grid (2 panes wide × 3 tall is the standard opening; wide windows use
   6×3). Match these proportions on new buildings.
5. **Screen axes at this camera**: screen-horizontal ∝ world **x+y** (screen
   px ≈ Δ(x+y)/√2 · 93 at ortho 11/1024); offsets along x−y are DEPTH and make
   objects stack behind each other. To place twin elements side by side on
   screen, separate them along equal +x/+y (the furnace pair is the exemplar) —
   a (Δx, −Δy) offset reads as one blob. Rotation sign trap: rotating a
   Y-long box about X by **−angle** builds a ramp DOWNHILL toward +Y; use
   +angle for uphill (the skip lift shipped downhill once).
6. **Round assemblies** (owner-approved for the furnace): 32 seg, and shade the
   SIDES smooth while leaving n-gon caps flat (`new_obj(..., smooth=True)` sets
   `use_smooth` only on quads) — the rim keeps a hard ink edge, the wall reads
   round. `dircyl(p0, p1, r)` builds arbitrary-direction cylinders.
   Junction rules, both learned the hard way:
   * angled members converging on a point read as odd acute intersections —
     prefer **right angles**: vertical stubs → one horizontal crossbar duct →
     vertical stack;
   * every cylinder-meets-cylinder junction still needs cover. A **collector
     drum TALLER than the crossing duct is thick** swallows it (a drum shorter
     than the duct diameter leaves tangent slivers = ink scribble), and a
     **sphere elbow** covers each 90° corner — same language as the pipework.
7. **Openings/decals on a CYLINDER must face the camera, not a world axis.** At this
   isometric the −Y face of a cylinder lies on its silhouette edge, so an opening
   put there grazes the outline and half-vanishes. Place it along the view
   normal `(0.707, −0.707, 0)` (`rotbox(..., 'Z', −135)` for the flat part,
   `dircyl` along that normal for the round part). Set the front face on the
   shell's TANGENT plane: further out and its own side walls show (reads as a
   box stuck on), further in and the curve clips it away. Keep half-width small
   enough that the sagitta stays ≲0.03 or the flat face overhangs the silhouette.
8. **Anything spanning ground → roof must clear the roof plane.** A straight
   incline from ground level in front of a building to a point above its roof
   WILL cut the roof inside the footprint unless it is already above roof
   height at the wall. Solve for it: at `y = wall`, require `z > roof_top`,
   then extend back to ground for the start point (the skip lift punched
   through the roof at y≈−1.37 before this).
9. **A level bar cannot trim a sloping roof.** Any seam/fascia along a sloped
   eave must be a `rotbox` at the roof's own angle — a box at one fixed z pokes
   out through the roof wherever the roof has dropped below it (the L3 annex's
   eave seam did exactly this).
10. **Attachments don't follow moved geometry.** When a wall or mass moves,
   everything positioned relative to it by ABSOLUTE coordinates stays behind
   (widening the furnace hall left the tanks overlapping it, and the sprite no
   wider, because the tanks — which set the crop's left extent — hadn't moved).
   After any massing change, re-check which absolute-positioned neighbours
   were supposed to keep their clearance.
11. Objects created by a builder must all be parented into its collection and be
   idempotently deletable (rebuild = delete collection contents, remake). With
   more than one building in the shared .blend, each builder must also
   `hide_render`/`hide_viewport` every OTHER `BLDG_*` collection first.
12. **Hiding `BLDG_*` does NOT isolate a building — `FINE_INK` leaks.** Any builder that
   uses a fine-ink assembly (`transformer`, `lattice_mast`, `insulator_string`, `pylon`)
   DUAL-LINKS those objects into `FINE_INK`, which has to stay visible for the `ink_fine`
   lineset to draw. An object is hidden only if *every* collection holding it is hidden,
   so those parts keep rendering after their own `BLDG_*` is hidden. The construction
   site's 42-object crane mast rendered into a factory shot this way — a tall lattice
   hanging over L1 from off-frame, with nothing wrong in the factory build at all.
   Collection flags cannot fix it; hide per OBJECT:

   ```python
   mine = {o.name for o in current_collection.objects}
   fine = bpy.data.collections.get("FINE_INK")
   for ob in (fine.objects if fine else []):
       ob.hide_render = ob.hide_viewport = ob.name not in mine
   ```

   Check this whenever a render shows geometry you did not build — the owning collection
   being hidden is not evidence that its objects are.

## Ink weight: FINE detail needs its own lineset

Freestyle thickness is per-LINESET, **not per-object**. A transformer's fins carry the same
2.4px line as an entire building, so a cluster of small equipment dissolves into one navy
smudge at sprite scale. `setup_rig` therefore creates a **`FINE_INK` collection**: the main
`ink` lineset EXCLUDES it, and an `ink_fine` lineset (1.05px) draws it. `Kit._fine_mode`
links anything built while set into that collection — `transformer`, `lattice_mast`,
`insulator_string` and `pylon` all turn it on.

* **Save and restore the flag, never hard-clear it.** Assemblies nest (`pylon` calls
  `insulator_string`); a naive `self._fine_mode = False` on exit silently reverts the caller's
  remaining parts to thick ink.
* The **7px external contour is deliberately left alone** — that is the sprite's outer
  silhouette, and punching a hole in it leaves the equipment with no outline at all.
* Fewer parts is the other half of the fix: drop a fin, drop an insulator disc.

## Composition: OCCLUSION IS PER SCREEN COLUMN

Two things can only overlap if their **`x + y` match**; only then does screen height
(`z - (x - y)/2`, larger = higher) decide which wins. Comparing heights at different columns
is meaningless, and comparing columns alone says nothing about occlusion — this project has
now shipped a wrong version of *both* halves:

* a duct check that compared heights across different columns "proved" a ground-level run was
  buried and pushed it up to the tower throats;
* a later one warned on any shared column and fired on a yard that was merely further right.

The predicate needs both, and the object's **width** matters: a round thing spans
`centre ± r·√2`, and the LEFTMOST column is usually the binding one (a flue whose centre
cleared the roofline still had its left half cropped). Where a value can be *solved* from this
relation — a duct's height, a bridge's clearance — solve it rather than typing a number: the
threshold moves by nearly a whole unit when a hall gains a storey.

## Terrain and pits (all three of these are MEASURED, not taste)

Built for the mine; reuse for any quarry/open-cast/earthwork.

**A pit is subtractive and a sprite has no ground plane**, so a hole cannot be
booleaned — build nested rings of solid earth, each shorter than the last
(`terraced_pit_poly`). The bench tops ARE the ring tops. Rings must overlap
(`grow`) or the shared vertical face z-fights.

1. **THE SIGHTLINE RULE.** The view ray gains 1 unit of height per 1 unit of
   horizontal travel, so a bench on the NEAR side (+X / −Y) only lets you see past
   it if its **tread exceeds its riser**. Backwards, and the pit is a sealed dark
   slot however many levels you cut. Derive near treads from the riser
   (`riser + margin`), never by eye. On an organic outline "near" is per-vertex, so
   the inset is a function of the vertex normal. Leave ≥0.10 of margin: 0.06
   satisfies the rule on paper but leaves nothing for a haul road's berm, which also
   stands on the benches — a ray-cast found ZERO visible samples on the two deepest
   surfaces.
2. **THE VALUE CEILING.** With this rig's AgX transform a vertical face responds
   `0.02→L0  0.05→L34  0.09→L80  0.14→L121  0.20→L147  0.28→L168  0.38→L176` —
   it **saturates above base ~0.28**. A plausible light-earth ramp (0.35→0.10) lands
   its top three tones within 8 luma of each other and the terracing vanishes. Keep
   earth tones inside **0.05–0.30**; that ceiling is also why `concrete` (0.56)
   cannot be a yard-sized apron (it renders as a blank white plate). Coal must sit
   BELOW the navy ink (~L70) or it reads as a fat outline, not as coal.
3. **THE ½ IDENTITY.** Two points share a screen position iff `x + y` matches AND
   `z − (x − y)/2` matches — one unit of depth buys exactly half a unit of height.
   (Same relation as rule 1, seen from the other side.) Use it to place a thing
   drawn on a cut face under a thing standing inboard. Decide deliberately whether
   you want the full match or a PLAN match (`x + y` only): the full match is correct
   for "directly behind", but for a shaft section that must stay underground you
   want the plan match, or the head lifts above ground.

Facets fight all of this: they are flat-shaded and Freestyle will not ink a break
that shallow, so a high-poly outline renders as a smooth gradient that swamps the
ring-to-ring steps (at 18 segments a scan down one wall read 152-129-108-**131**-107,
brighter facets *below* darker ones). **Keep pit outlines ~12 segments.**

Two placement traps on an organic outline: anchor props to the floor **centroid**,
not its bounding box (bbox corners fall outside a bean), and assert containment with
`point_in_poly`; and check the rim clears the block's own faces by more than `grow`,
or ring 1 breaches the cut face by a hair and — its normal differing from the face's
— renders as a 1px bright sliver down the strata.

## Pipeline order (render → export → stylize)

```bash
# 1. render each level from Blender (build_factory(N) + render_viewport_to_path)
# 2. crop/scale to the final square canvas
python3 "…/blender-assets/sprite_export.py" exports/ <name> lvl1.png lvl2.png lvl3.png
# 3. stylize AT FINAL SIZE (in-place is fine)
python3 "…/blender-assets/stylize.py" exports/<name>_lvl2_800.png exports/<name>_lvl2_800.png
```
**Stylize LAST, after the resize.** The halftone is a property of the print, not
of the subject: applied before the resize, each sprite's dot pitch ends up scaled
by its own crop ratio and the set stops matching.

## Print-texture pass (stipple = shading)
Stippling is strictly a SHADING SUBSTITUTE (owner rule): denser stippling =
darker shading. Lit faces stay completely clean; density ramps in three bands
(sparse grid → +dual grid 2× → +half-spacing grid 4×) as face darkness grows;
dot size never changes. WINDOWS STAY UNSTIPPLED (owner rule: "already complex
enough") — glass is detected as blue-dominant + dark (b > 1.45·r AND luma <
0.38; the same test intentionally catches navy doors/darkmetal). This detection
requires `Specular IOR Level = 0` on ALL materials (builder does it) — default
specular adds white sheen that breaks the ratio. Ink lines and highlights are
excluded, alpha preserved, mild contrast punch (1.10). Approved defaults at
1024px: `--spacing 10 --dot-r 1.8 --strength 0.30` — rescale the pixel params
proportionally if render size changes. Do NOT revert to all-over halftone
texture; that was tried and rejected.

## Export: square canvas, EXACT pixel padding

```bash
# level sets: ALWAYS pass --ref = the render with the largest max-dimension
python3 "…/blender-assets/sprite_export.py" blender-assets/exports <name> \
    lvl1.png lvl2.png lvl3.png --pad 6 --ref lvl3.png
```
**`--ref` is mandatory for a level set.** The empire view draws every sprite in a
fixed 400px box, so relative building size can only come from the PNG content:
without a shared scale each level fills its own canvas and an L1 shack renders
the same size as an L3 works. Pick the ref by measuring — the largest
max-dimension, not by eye (L1 was *taller* than L3 while L3 was widest; using a
non-maximal ref would scale another level past the canvas and clip it).
One 800×800 PNG per level (owner decision) — import into Godot with **Generate
Mipmaps: On** and let the engine serve every smaller display size. Finals live
in `blender-assets/exports/`.

**Padding is computed in OUTPUT pixels**: each sprite's alpha bbox is cropped
tight, scaled so its LONG axis is `size - 2*pad`, and centred. 6px means 6px in
the delivered PNG. Two earlier bugs this replaced — both invisible until the
margins were actually measured, so **measure them, don't eyeball**:
 * a *shared* crop box (from the biggest level) left the others slack — L2 once
   shipped with a 97px right margin;
 * padding applied to the 1024px render was then rescaled by the resize, so the
   delivered margin was never the number asked for.
The SHORT axis necessarily has more margin (non-square subject, square canvas —
L3 is 788×670, so 65px top/bottom). That is geometry, not slack; a non-square
canvas is the only way to be tight on all four sides, and Godot accepts one.
With `--ref`, only the reference level hits the 6px margin — the smaller levels
are deliberately inset (L1 lands at 492×507 with 154px margins). That inset IS
the relative-size signal; do not "fix" it by re-cropping them tight.

## In-game integration (empire view sprite style)

Sprites live at `assets/icons/buildings/sprites/<internal_name>_lvl<level>.png`
(e.g. `industrial_factory_lvl2.png`), 800×800, `.import` with
`mipmaps/generate=true` (copy a sibling's .import; run
`Godot --headless --path . --import` to bake). Loader:
`scripts/building_sprites.gd` — `texture_for(internal_name, level)`, falls back
to lower levels, returns null for unsprited buildings.

**`swap empire view sprite`** (debug terminal; second use switches back;
live-refreshes an open view via `EmpireView.refresh_graph()`) switches the whole
empire view to the SPRITE STYLE: hex backdrop hidden (flat navy `FlatBg`
remains), each sprited building draws its sprite at a fixed 400px
(`empire_node_panel._SPRITE_PX`) with its metal plate ATTACHED BELOW (plate
keeps title/good-icon/RAG; the in-plate building icon is dropped). Unsprited
buildings keep the full classic card; ports are untouched. Plates are drawn at
**L1 size for every level** in this mode (`plate_sz /= cs` in setup) — the
sprite carries the level's scale, so level-scaling the caption plate too made
the row of captions ragged. Mechanics that make it work — all must stay in sync:
 * the panel Control grows to sprite+plate, so the screen-space separation pass
   (which uses ctrl.size) prevents plate/sprite overlap automatically;
 * edges anchor to the PLATE via node key `plate_dy` (= _SPRITE_PX/2, set in
   `empire_graph.gd`) consumed by `empire_graph_world._plate_screen_of` — so
   arrows emerge from plates exactly as in classic mode;
 * TextureRect GOTCHA: set `expand_mode` BEFORE `size`, else the 800px texture
   is the minimum size and the 400px assignment silently clamps up to 800.
Verify with `tools/sprite_swap_shot.tscn` (windowed) →
/tmp/poe_sprites_{off,on,off2}.png. To add a new building's sprites: drop the
3 PNGs + .imports in that folder with the right internal_name — no code changes.

## Session-state hazard

If Blender restarts between sessions, the open scene may have stale camera /
sun / Freestyle state (one bad batch shipped zoomed-in renders WITH shadows).
`build_factory()` now calls `setup_rig()` first — an idempotent assert of
engine, film, resolution, camera transform+ortho_scale, sun (shadows OFF),
both Freestyle linesets, and world. Keep that pattern in every new builder:
geometry functions must never depend on saved .blend state.

## Verification loop

1. Rebuild via MCP → `render_viewport_to_path` → Read the PNG.
2. Crop-zoom suspicious areas with PIL before concluding anything — several
   "artifacts" were only diagnosable at 4× (a cast shadow, a z-fight, a
   coplanar top face).
3. Run `stylize.py`, then view the final.
4. For level sets, composite a 3-up strip at IDENTICAL camera scale so relative
   size reads, and check the upgrade story left→right.

## Not yet decided / pending

- Export naming + sizes into the game (likely mirroring
  `assets/icons/goods/medium|small/` convention) and BDP integration — the
  in-game consumer of these sprites hasn't been wired yet.
- Brick coursing / hatch textures (graphite-icon style) — deliberately skipped;
  halftone-only was approved.
- Brick coursing beyond halftone — still deliberately skipped.


## Headless rendering — use it for anything long (SOLVED 2026-08-07)

The MCP addon needs a GUI Blender, but **you do not need MCP to render**:

```bash
blender --background industrial_goods_factory.blend --python tools_render_chunk.py -- 0 89
```

Use this for every batch or long run. It matters for a reason that is not
obvious: **the MCP server runs on Blender's main thread**, so while a long
operation is running it cannot answer a single call. A one-hour render loop
started through MCP therefore blocks every status check *and* every attempt to
stop it — the only way out is Esc in the GUI. Headless has none of that: you can
poll its log, and kill it like any process.

Because every builder rebuilds from code (`setup_rig()` / `build_film_scene()`),
headless runs need nothing from saved .blend state.

**Long loops must be interruptible.** Check a sentinel file every few frames:

```python
stop_path = os.path.join(out_dir, "STOP")
if (idx - i0) % 5 == 0 and os.path.exists(stop_path):
    os.remove(stop_path); return {"stopped_at": idx}
```

Clear it on entry as well as exit, or a stale file kills the next run.

## Where the render time actually goes (MEASURED)

Per keyframe of the loading film — three passes at 2400×1350 — **40.3s**:

| pass | time | why |
|---|---|---|
| colour (EEVEE + Freestyle) | 35.7s | |
| geometric mask (EEVEE only) | 2.3s | |
| ground mask (EEVEE only) | 2.3s | |

Same geometry, same engine, same resolution — the only difference is Freestyle.
**~83% of render time is Freestyle**, which is CPU-only and largely
single-threaded in its stroke phase.

Consequences worth stating before anyone buys hardware:
- A much faster GPU buys ~10%, not 3×. The GPU portion is already ~2s of 40.
- The real levers are **resolution** (Freestyle's view map scales with it) and
  **object count**.
- Rendering keyframes and interpolating beats rendering every frame: 447
  keyframes ≈ 5h gives 30fps output; rendering 1350 frames costs 15h.

Also: standing the whole street up (19 builders, thousands of objects) costs
**~16 min**, and that is a per-CHUNK cost, not per-frame. Pass `rebuild=False`
when the scene is already built at the right LOD.

## Isolation: HOLDOUT, not camera-invisible

When rendering one layer or one mask, the instinct is
`ob.visible_camera = False` for everything else. That is usually **wrong**,
and it caused two separate bugs:

- Building layers rendered with the street merely invisible exposed the
  buildings' below-grade apron kerbs — normally hidden by the verge — which
  then composited over the street as a dark band under the construction site.
- The ground mask with buildings merely invisible left the ground *behind* each
  building visible in the mask. Those pixels reported "ground", so the stipple
  applied the ground's **cast-shadow** bands while the colour pass showed a
  wall: shadows printed straight across facades.

Use `visible_camera = True` + `is_holdout = True`: it still occludes and cuts
alpha, and keeps casting shadows. Reset `is_holdout` on every pass.

## Absolute vs relative coordinates in kit helpers

Two bugs, one cause. A helper that takes a *centre* must offset by the parent's
position, or everything it builds lands near the world origin:

- `_wheels()` placed wheels at `face*wx*s` instead of `x + face*wx*s`, so every
  vehicle's wheels sat in a heap at the origin. The symptom read as "the cars
  have no wheels" — they existed, they just were not under the vehicle.
- `bpy.data.meshes.new_from_object()` returns **LOCAL-space** geometry. Without
  `me.transform(tmp.matrix_world)` every number plate's lettering baked at the
  origin.

When something is "missing", check whether it is at (0,0,0) before rebuilding it.

## Kit gotchas found the hard way

- **`PALETTE` additions must be at MODULE scope**, before any `Kit()` is
  constructed — `Kit.__init__` builds its material table from PALETTE, so adding
  roles inside a `build_*()` raises `KeyError` on the first `mat()` call.
- **`poly_prism` cannot do concave outlines.** Its cap is an n-gon and the
  triangulation does not respect concavity — a C-shaped quay came out filled
  solid, burying the harbour and both ships. Use several overlapping boxes and
  run the middle one long at both ends so the joints are buried inside the mass
  rather than abutting flush (a flush abutment inks as a crease).
- **`container_stack` and friends build from z=0** and take no z argument. On a
  raised deck they end up half-buried. Wrap rather than changing a shared
  signature: record `col.objects` before and after, translate the difference.
- **Hiding `BLDG_*` is not enough.** `SHOWCASE_*` and `STACK_*` collections left
  render-enabled by the lineup tooling will render into your sprite — the
  mine's terraced pit appeared in the middle of the docks. Hide all three
  prefixes.
- **`Kit.seam` hides a face INTERSECTION.** Do not use it across a gap: on the
  truck it was wider than the trailer and stuck out of both flanks as a dark bar.

## Camera and framing traps

- **`shift_y` is in units of the LARGER image dimension**, not the height. The
  vanishing point is `H/2 + shift_y*max(W,H)` — using `0.625*H` put it 130px
  out, which was invisible in a uniform zoom and fatal to a perspective warp.
- **Far clip must clear the furthest backdrop.** Moving the sky plane to x=210
  put it past the 200 clip, so straight renders came out with a transparent sky.
  Only the film noticed nothing, because it composites its own sky.
- **Aiming a camera**: look direction is `rz + 90°` for this rig. Two shots were
  wasted pointing into a verge, and two more with the lens inside a building —
  check the target is on open ground before rendering.
- **Things beyond ~2× the road half-width only appear at the frame edge.** A sea
  laid behind the south building row was geometrically correct and completely
  invisible; the lever was the building row, not the water.

## Proportion lessons at sprite scale

Each of these read wrong until the RATIO changed, not the detail:

- Tanks at 0.52r × 0.74h are squatter than a coin and read as discs on the
  ground. 0.42 × 1.15 reads as a tank.
- A car with more glass than body is a van. Body-to-glass wants ~60/40.
- Hood and boot panels must be at least as WIDE as the waist. At 0.455 on a 0.48
  waist the waist's top showed as a rim down the whole car and read as a
  pickup-bed side wall.
- Wheels tucked inside the body width vanish behind the flanks. Push them proud.
- Tyres nearly as wide as they are tall read as balls.

## Print-pass exclusions

`stylize.py`'s glass test is `b > r*1.45 AND luma < 0.38`. Open water at
`#497486` is blue-dominant but sits at luma 0.424, so it cleared the cut and the
halftone screened the whole harbour. Use `--skip-hex` for explicit tones rather
than loosening the glass rule — widening it starts skipping legitimate slate and
shadowed brick on every other sprite.
