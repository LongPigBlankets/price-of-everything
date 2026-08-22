# Building sprite notes — per-building record

Working notes for improving the sprite set after the demo. One section per building: what it
is meant to read as, what state it is in, what has been checked, and what is known to be
weak. Written 2026-08-21, after the contour/stipple pipeline change.

Pipeline itself is documented in `SKILL.md` ("Pipeline order"); the tools are
`render_sprite.py` → `sprite_export.py` → `stylize_shade.py`, driven by `bake_sprite.py`.

---

## The physical-logic audit

Worth doing on every building before calling it finished, because it catches things that look
fine and are nonsense. The method is just: **name every flow the building implies, then trace
each one end to end and find where it stops.**

For an industrial sprite there are usually three or four:

| flow | trace it from | to |
|---|---|---|
| power | grid / generator | every machine that needs it |
| feed | where material arrives | the vessel that consumes it |
| product | the vessel | where it leaves or is stored |
| waste / fume | the process | filter, stack, or discharge |

Two failure shapes turn up repeatedly:

**An OPEN circuit.** Something arrives and nothing leaves, or vice versa. On the electrolyser,
cables ran battery → transformer and simply stopped: the stacks' rod banks — the building's
signature detail — floated a full unit away, connected to nothing. The fix (an overhead copper
bus with a drop onto each bank) became the composition's best diagonal, so the audit paid for
itself twice.

**A TERMINAL that is not a terminal.** A cable or pipe landing on a part that could not
receive it. `transformer()` models three HV bushings, a conservator drum and radiator fins;
only the bushings are electrical, so a cable touching the drum or the fins is drawn nonsense.
Worse, the electrolyser had the incoming grid line AND both outgoing loads on the same three
bushings. Separating them (grid in on HV, loads out from an LV box on the front face) is one
small box per transformer and makes the machine legible.

Also worth checking: **one emissive per sprite.** An open pool of ember is the brightest thing
in the whole set, and a second glow of equal strength just splits the viewer's attention. Where
a second heat source is genuinely wanted (the EAF's caster strand), it should be the *product*
of the first one, and smaller.

---

## eaf — Electric Arc Furnace  *(new, 2026-08-21)*

Three flat-ended graphite rods standing in an open bath of molten steel, inside a melt shop
whose front bay is an open portal frame. Deliberately the blast furnace's sibling — same
steel-and-heat family, no slab — but sharing none of its silhouette.

**Flows, all closed.** scrap heap → bay → bath; electrodes → bath (via the rail); bath → tap
→ ladle; fume → canopy hood → elbow → bag house → hopper trough → downpipe into the ground;
L3 caster → glowing strand → coil stock.

**The design constant.** The eave is *solved*, not chosen (`_solve_eave()`): it is the maximum
sightline crossing plus margin. Every level shares it, because the shop's height is set by the
electrodes and they do not shrink — the same argument the power plant makes for its flue. L1
was once given a 3.20 eave and `_check_sightlines()` refused to build it.

**To improve after demo**
- The roof is still the largest single mass; the ridge monitor helps but does not solve it.
- L3's caster annex is largely hidden behind the scrap crane.
- The rotary valve under the bag house reads as a stray cube at sprite scale.

## electrolyser — Electrolyser  *(new, 2026-08-21)*

Exposed horizontal cell stacks — fluted barrels on skids with green tie-rods and a bank of
terminal bushings on each end plate. Stack count *is* the level (1/2/3). Every other cylinder
in the set stands up, so a fat barrel lying on its side is a silhouette nothing else uses.

**Flows, all closed.** grid → pylon (3 conductors, one per −Y insulator string) → HV bushings
→ LV box → overhead copper bus → stack rod banks; battery buffers on the LV side; bath taps
LV; stacks → gas risers → shed → header main → swan-necks → tank farm.

**Layout is a ROTATION, not a mirror.** When the yard was flipped, reflecting x → −x would
have put the end plates and rod banks on the barrels' −X ends, which sit on the silhouette at
this camera and vanish. The stacks turn 90° instead.

**To improve after demo**
- L1 is sparse; the middle band is dense at every level.
- Back transformers at L2/L3 are partly hidden behind the front one — the cost of a true
  middle rank.
- The tank swan-necks are legible but busy where four tanks tap one main.

## assembly_plant — Assembly Plant  *(new, 2026-08-22)*

A WIDE hall (2.8 deep) under a gentle segmental GLASS BARREL VAULT — faintly light blue,
curved panes with seams and no frames, rise/half-span 0.51 so it springs at 25° rather than a
half-round's 13° — with the front left out as an open portal frame (the EAF's precedent) so the
production line is visible: a conveyor along X carrying orange cartons, orange six-axis robots
seated beside it and reaching over it. The belt exits through an arched opening in the right
gable onto a LOADING BAY at every level: raised dock, roller door beside the arch, bumpers on
the truck face, carton stacks. From L2 the plan is an L — a tall flat-roofed HEAD BLOCK at the
hall's left end with a second vaulted WING running back from it — and at L3 the loading bay
gains a JIB CRANE at its left-front corner, boom swung out over the dock. Manufacturing family
beside the brick factory; orange is the chroma and it is carried by the robots and the boxes
ONLY, since with the accent tracing the line straight through the building an orange dado on
top of it stops being a signal.

**The head block is taller than both crowns** (crown + 0.25). Two vaults meeting at a corner
need something for their ends to die into; a flat-roofed block lower than the crowns shows two
cut vault ends poking out above it. `_Arc` holds the geometry for each vault, so the hall and
the wing can have different spans and rises and still share the vault and gable builders.

**The interior is visible by construction.** The view ray runs (+1, −1, +1), so a point at
depth d behind the open front and height z exits the front plane at z + d, and is seen iff
`kerb < z + d < header underside`. Every interior object is placed against that window — the
far-flank robot elbows, the highest thing at the greatest depth, come out at 2.20 against a
header underside of 2.31. An eave of 2.30 with a 0.32 header hid them; the eave is 2.55. Run
the check numerically before rendering: it is nine lines and it replaced a render cycle.

**The vault is one tiled mesh with two material slots** (`SKILL.md` rule 18, the solar trick):
panes and seams abut, so no z-fight and no contour per pane, and the seams are uninked
material boundaries — "seams but no frames" literally. 24 facets round the arc keep every
dihedral above the 120° crease angle, so the shell takes no facet lines and reads as one
smooth surface. The gables are `prism` extrusions of the same arc at R + 0.04, standing just
proud of the glass to hide its cut edge.

**Robots on the FAR flank reach toward the camera.** A near-flank arm reaching away crosses in
front of the cartons it is working on; a far-flank arm reaching toward us is seen against the
belt, behind them. One or two near-flank machines complete the aisle.

**Flows, all closed.** wing (sub-assembly) → head block → (through the shared gable) → belt
→ robots → belt → arched exit in the right gable → external run → loading bay → carton stacks
→ crane/trucks. Power: a switchgear cabinet against the right gable. At L1 there is no wing or
head, so the belt starts inside the hall.

**Framing was the one real bug** — see `SKILL.md` rule 20: the apron's left-front corner sets
the smallest screen column, not the hall, and centring on the plan midpoint clipped L3.

**To improve after demo**
- The apron is the darkest large surface and reads as asphalt; it may want the cream of the
  refinery aprons instead.
- The open front with a pale kerb and mid-steel columns can read as a glazed wall rather than
  an opening. Either reading is acceptable for an assembly hall.
- The wing's interior is never seen; its +X flank carries windows so it is not a blank wall.
- No truck at the dock: the vehicle kit is the film's street-scale system with haze, shadows
  and a `seed` argument, and pulling it into a sprite would break reproducibility.

## solar_farm — Solar Farm  *(new, 2026-08-22)*

Fixed-tilt ground-mounted PV on turf: rows of individually framed modules, each carrying a 5x3
cell grid in dark navy with thin white lines, with inverter cabinets, a pad-mount transformer
and the takeoff pole strung across the front. Shares the wind farm's turf and gravel — the two
renewables are the same kind of place — but nothing else in the set has a large dark plane, so
the silhouette is unmistakable at thumbnail size.

**NO BUILDINGS.** A solar farm's only structures are electrical. This shipped once with a
control room — window, door, pitched roof — and it read as a house in a field, the one thing a
solar farm never has. The inverters were sheds too; what makes them read as switchgear instead
is a FLUSH cap rather than an overhanging lid (an overhang is a roof), a louvred face across
the full width, a heat-sink block on the flank, and cabinet proportions — taller than deep.
Removing the control room also shrank the plate, since the site is sized to its content.

**Two bents per MODULE, at its quarter points.** Three stations spread across a whole row left
most modules spanning nothing, and the array read as pegged down rather than carried.

**EVERY MEMBER UNDER THE MODULES IS PLACED FROM `_under()`, never by eye.** The back rail was
once written as `MOUNT_Z + PANEL_RISE - 0.035` — which reads as "just below the back edge" and
is in fact 0.045 ABOVE the sloping face at the rail's own y, because the face has dropped by
then. A bar therefore crossed the top of every module and ate part of the top row of cells,
and it looked like a proportion mistake in the grid rather than a member in the wrong place.
On any tilted plane, compute the surface height AT THE MEMBER'S OWN COORDINATE.

**The two panel axes do not project at the same scale, and everything drawn on the face has to
be corrected for it.** Along the row a = (1,0,0) projects at 80.5 px per unit; up the slope
b = (0, cos t, sin t) projects at 103.8. So a physically square cell comes out 29% taller than
wide and a uniform grid line comes out 20% heavier across the rows than down the columns. The
module is cut to 2.0:1 to cancel it — which is also a realistic landscape panel rather than
the 5:3 it started as — and the two cell-gap widths are set independently. Cells measure
13.4 x 13.5 px. (The first correction used 2:1 dimetric pixel numbers — 80.5 / 103.8 px along
the two panel axes instead of the true-isometric 76.0 / 91.0 — and left the cells 6% wider
than tall; see `SKILL.md` rule 19.)

**The cell grid is ONE mesh with two material slots.** 45 quads that abut rather than overlap:
5 cell columns and 4 line columns, 3 cell rows and 2 line rows. Lines laid *on* a plate would
z-fight and, as separate objects, would earn six contours per panel. See `SKILL.md` rule 18.

**Row pitch is set EQUAL to panel pitch on purpose.** Screen column is x+y, so every panel
sharing (i + k) then lands on exactly the same column and the array reads as a regular grid.
Measured alternatives — the near-misses are the worst of the three outcomes:

| pitch | column shift | |
|---|---|---|
| 1.02 | 0 px | chosen; a regular grid |
| +0.09 | 6 px | near-miss |
| +0.19 | 12 px | near-miss |
| +0.44 | 29 px | clearly offset, but the array goes sparse |

Inter-row occlusion is `rise + (depth - pitch)/2`, which at the final proportions is negative:
the rows do not overlap at all and about 9 px of ground shows between them.

**Tilt is safe at any positive angle**, which is worth knowing because the set has been bitten
by edge-on faces twice. A panel face is edge-on when its two spanning directions project
parallel; spanning X and the slope, that happens only at tan t = -1, i.e. a panel tilted UP
toward the camera at 45 deg. Panels tilt down toward the front, so the whole real 20-35 deg
range is clear. 30 deg is used and sits within 3% of the maximum available screen area.

**The site is sized to the content.** A flat building has no tall object to grow its
silhouette, and with a fixed plate all three levels exported at exactly 870x534 — see
`SKILL.md` rule 17.

**How dark the cells can go is set by the CONTOUR, not the background.** Cells run at luma 40
against a background of 26 but a synthesized contour of 57, so a panel is darker than its own
outline. That only works because the contour bands the sprite's outer boundary alone and the
turf plate always surrounds the array — the two never touch. Any future layout that lets a
module reach the sprite edge would invert the drawing there.

**Flows, all closed.** sun -> modules -> string combiner at each row's left end -> DC tray
(spur, then the Y run, then across) -> inverter (DC in at the back, AC out at the front) ->
AC bus -> transformer -> HV bushings -> takeoff pole -> grid. Two audit catches: the combiners
were left floating 0.26 from the tray after a layout rewrite, an open circuit invisible to the
eye; and nothing at all left the transformer until the pole was added. L1 has no transformer,
so its pole is fed from an AC riser box on the inverter, which is what a small LV-connected
farm actually does.

**To improve after demo**
- The front-left of the plate, between the yard and the track, is the emptiest area.
- The tracker torque tubes only show where they overhang each row's left end.
- L1 has no transformer and no trackers, so it leans hard on the array alone.

## onshore_wind_farm / offshore_wind_farm — the wind farms  *(new, 2026-08-22)*

Two buildings from ONE builder. They share the turbine, the blade loft and the rotor yaw, and
differ only in what the machines stand in and whether there is a yard at all.

**The rotor yaw is the whole design.** A rotor facing the camera dead-on is a true circle, but
its normal projects to zero screen column — so the nacelle mounted along that normal draws as a
vertical bar and the first render read as the tower carrying on past the blades. `ROTOR_YAW`
is 25°, chosen off a measured table (`SKILL.md` rule 13): the nacelle gets a real horizontal
component for under two pixels of roundness. Everything else at the head follows from it — the
hub is pushed upwind by `NAC_OVERHANG` so the tower meets the nacelle two-fifths from its rear,
where a yaw bearing actually is.

**`BLADE_R0` is absolute, not a fraction of R.** With the blades slimmed and lengthened, R now
runs 1.07 to 1.75 across the set; a root at `0.16 * R` left the three roots stopping short of
the hub drum on the big machines and the rotor read as three planks near a box.

**The blade planform has a SHOULDER.** A monotonic root-to-tip taper gives a tapered plank, not
a turbine blade. Real chord is narrow at the root, peaks at about r/R = 0.22 and only then
tapers; the first version peaked at r/R = 0, exactly where a real blade is narrowest. Measured
against a real large-machine distribution (fraction of max chord):

| r/R | 0.05 | 0.22 | 0.35 | 0.50 | 0.75 | 1.00 |
|---|---|---|---|---|---|---|
| real | 0.55 | 1.00 | 0.82 | 0.62 | 0.42 | 0.20 |
| was | 0.92 | 0.77 | 0.67 | 0.57 | 0.41 | 0.27 |
| now | 0.65 | 1.00 | 0.81 | 0.65 | 0.41 | 0.20 |

Two things go with it: the LEADING EDGE is pinned at a constant offset so all the taper falls
on the trailing edge (sweeping the section centre instead curves both edges and it goes back to
looking like a bent plank), and each section is twisted about the span axis by 14 deg at the
root washing out to zero at the tip.

**The hub must not outgrow the nacelle.** Once the nacelle became a lofted body with an
ELLIPTICAL section it lost the box corners that used to reach past the drum, and a 0.185 hub
simply ate a nacelle with a 0.13 semi-axis. On a real machine the spinner is about nacelle
width, which is what `HUB_R` is set to now. The nacelle's rear 45% closes on a `sqrt(1 - x*x)`
profile — the vertical tangent at the end is what reads as ROUNDED rather than merely narrowed.

**Offshore carries no yard at all.** It went through a jacket-legged substation platform first
— the equipment obviously cannot stand on open water, and the audit caught that — but the deck
had to be squeezed clear of every turbine footprint, competed with the rotors, and made the
offshore sprite a near-copy of the onshore one. Dropping it is better on every count, and the
real export cable runs to shore off-frame so nothing is left dangling. The cost is that
offshore has nothing but turbines to signal level with, so **the sea plate is the same
rectangle at every level** — if it grew with the machines the shared-scale export would
normalise the growth straight back out and all three levels would return the same size.
Level is carried by count (2/4/6) and by `OFFSHORE_HUB` (0.86/0.96/1.08).

**Two colour findings.** `ground4`, the pale gravel that worked against an earth top, measures
luma 66 against turf at 103 — on green it stopped reading as stone and turned the service
tracks into dark ditches; `gravel` is set near luma 130, clear of the turf below and the towers
(158) above. And `K.ladder` defaults to `mat("accent")`, which resolves to **purple** — the
refinery chroma — so every monopile wore a lilac bar until the material was passed explicitly.

**Flows.** Onshore: wind → rotor → nacelle → tower → transformers → mast/gantry → grid, with
the batteries on the LV side and the tracks reaching every hardstanding. Offshore: the export
cable leaves the frame, deliberately.

**Placement traps found here.** `substation_gantry` takes ENDPOINTS and puts a `lattice_mast`
on each one, so a 1.60 span centred at x = 3.35 planted its right leg at 4.15 — past the site
edge at 3.95, with the mast half-width on top of that — and the leg hung off the composition.
Check the extremity against the bounds, never the centre. The met mast that used to stand at
(-2.45, -0.55) is gone: it sat right beside turbine 2 and read as clutter rather than as
instrumentation.

**Turbine spacing is a SCREEN COLUMN problem.** Columns are -3.40 / -1.60 / -0.70 / 0.55 /
2.70 / 4.50, tightest pair 0.90 apart (59 px). Turbines 4 and 5 are L3-only, so they can be
moved without touching L1 or L2. The binding 3D check is not the column but the rotor reach
along Y: the rotor plane spans u = (0.342, 0.940, 0), so a rotor reaches +/- 0.94 R in Y, and
the tall back machine against turbine 2 below it comes to 2.59 against 2.80 of separation.

**To improve after demo**
- Onshore L1 is two machines on a large green plate; the `turf_lo` sward split helps but the
  ground is still the biggest single surface.
- The service tracks pass near the hardstandings without spurs onto them.
- Offshore L1 vs L2 is a 12% height step — the count does most of that level's work.
- At L3 the battery bank and the gantry sit close enough that a turbine tower crosses them.

## industrial_factory — Industrial Goods Factory

Brick two-storey with a sawtooth north-light roof; square brick chimney back-right; loading
bay front-left. The set's one warm-brick building and the manufacturing family's anchor.
`factory_builder.py` predates the kit and carries its own inlined palette — **do not refactor
it onto the kit without re-approving the renders.**

Re-baked on the new contour/stipple 2026-08-21; geometry reproduced within 2 px.
**Not yet flow-audited.**

## furnace — Furnace (blast)

Steel-clad hall, twin banded round chimneys, scaffold cage, process tanks, ember-lit doors.
L3 merges the two stacks into one exhaust via the oval breeches piece that took four attempts
(see `SKILL.md`). Also predates the kit.

Re-baked 2026-08-21; within 3 px. **Not yet flow-audited** — worth doing, since it and the EAF
are a deliberate pair and the EAF's audit found real errors.

## power_plant — Power plant

Cooling tower, banded flue, turbine hall with the mustard power dado, transformer compound and
pylon in a line so hall → transformers → pylon reads left to right as the power actually flows.
The building that forced four new palette tones (`shell`, `chalk`, `pad`, `deck`) because a
plant built from the existing greys measured a 26-luma spread.

Re-baked 2026-08-21; within 5 px. Highest tone divergence of the set (0.717) — its cooling
tower is the largest curved surface anywhere, so the shading mask redistributed the most dots
there. Worth an eye before demo. **Not yet flow-audited.**

## petro_refinery / poly_plant — the refineries

Purple (`CAT_REFINERY`) as the only chroma, cream octagonal aprons, white flat-roofed masses,
silver pipework. Petro has the flare and the bullets; poly has the floating-roof mixing vats
and the warehouse with rolls of finished mesh. L2/L3 of the petro plant still carry the older
layout and were never reworked to match its L1.

Both re-baked 2026-08-21; within 2 px. **Not yet flow-audited** — the petro plant is the most
likely to have an open flow, given how much pipework it carries.

## port — Port / docks

Quay, water, container ships, bottle-green gantry cranes. **Ships ONE image under all three
level names** — `port_lvl1/2/3` were byte-identical before the re-bake and still are;
`build_docks()` takes no level argument.

Two things to know:
- Its raw render is **1024 px wide in a 1024 frame**, i.e. clipped at both sides in Blender.
  This is pre-existing — the shipped sprite has it too — but the docks scene is genuinely
  wider than the camera frame at `ortho_scale` 11. Fixing it means narrowing the scene, not
  changing the camera, since `ortho_scale` is the shared style contract.
- The old halftone screened the whole harbour, because open water at `#497486` sits at luma
  0.424 and cleared `stylize.py`'s glass test. **The new shading mask fixes this for free**: a
  water plane is a +Z face, the brightest thing in the mask, so it takes no dots at all.

## construction_site — Construction site

Tower crane, scaffold frame, hi-vis containers, diggers. **Ships only an L1**;
`build_construction_site()` takes no level argument. Re-baked 2026-08-21; within 3 px. Its
crane mast is 42 objects of fine-ink lattice and was the original cause of the `FINE_INK`
leak documented in `SKILL.md` rule 12.

**The second storey used to float, fixed 2026-08-22.** `col2` ran z 1.337..2.198 between a
deck1 top of 1.240 and a deck2 underside of 2.230 — 0.097 of clear air under the columns and
0.032 over them. At sprite scale it is 880 px and easy to miss; in the loading film the site
is metres from camera and it read, correctly, as suspended concrete. Caught by the owner
watching the film, not by any check here.

The lesson is the fix: the storey is now DEFINED by its two decks (`FRAME_H * 1.5 + 0.16`
centre, `FRAME_H - 0.06` height) instead of by two independently chosen numbers that happened
to nearly meet. **A structural member's extent should be derived from what it lands on.** Any
gap smaller than a line width survives every silhouette check in this pipeline — IoU sees
0.999 — so nothing but arithmetic on the spans will catch this class of fault.

Re-baked both consumers: the sprite, and `06_bldg_near` in the loading intro plates.

## mine — Mine  *(FROZEN)*

Terraced pit, headframe, office block, excavator. Three genuinely distinct sprites.

**Cannot be re-baked: `mine_builder.py` is not in this checkout.** `SKILL.md` documents it and
`bake_sprite.py` deliberately omits it. It is therefore the only sprite still carrying
Freestyle's view-map contour — barely visible, since a terraced pit is solid mass with no
internal gaps for the old contour to wrongly outline. Left as-is by owner decision
2026-08-21. If the builder resurfaces, add it to `BUILDINGS` and re-bake.
