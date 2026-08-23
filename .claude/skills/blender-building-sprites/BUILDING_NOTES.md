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

## high_tech_manufactory — High Tech Manufactory  *(new, 2026-08-22; three passes the same day)*

Manufacturing family. Two-toned walls — brick orange below, white above — under a FRONT HALL
whose mono-pitch roof is GLASS on steel rafters and purlins, rising from a low eave to the
flat-roofed steps behind. Through the pitch: a robotic cell of four orange arms converging on
one microchip carrier (green board, silver wafer, dark die), and server racks along the rear
and left walls. The front-right corner is a two-storey glass box on steel pillars with transoms
across the panes, white clean rooms and red laser benches aimed at green circuit boards.
Rooftop air handlers on step 2, electrical units on the L3 extension's roof, a lattice mast
with a dish. Orange — the family chroma — carries the robots, the entrance and the unit
stripes; the red of the lasers is the highlight.

**The glass pitch made the hall hollow.** A roof you can see through has to have something
under it, so the front section is a floor, a thin two-toned end wall (rectangle in brick, a
trapezoid in white above), the rear block's face and the corner partitions — not the solid
prism of the first pass — with five rafters down the slope and two purlins across it under the
glass. Every ray through the pitch lands on one of those; zero see-through in the installed
sprites.

**What can be seen through the pitch is set by the FRONT WALL, not the glass.** An interior
point (y, z) is seen over the 2.0 eave wall iff z + (y − FY0) > EAVE, i.e. y + z > −0.2. So
the cell sits in the back half of the hall (centre y −0.55, radius 0.5) with its elbows at
1.05 — the front pair show from the elbow up, the back pair in full — and the 1.6-tall racks
stand along the rear wall and the left wall. Content in the front half would simply be behind
the wall.

**The roof slopes UP toward the back** (area ∝ cos t + sin t; toward the camera ∝ |cos t − sin t|,
dead flat at 45°). Eave 2.0, 3.05 at the junction, 25.5°. The glass corner's +X pillars and
panes follow the rake; its fascia is a rotbox at the pitch; its interior partition is a prism.

**Engineering audit (owner-requested, third pass) — what was missing and was added:**
- the transformer fed nothing → LV link to the switchgear, and the switchgear now feeds the
  conduits via a drop to the cable tray;
- no goods access on a production building → roller door on step 2's +X face with a dock pad;
  the conduits moved aside for it;
- rooftop units with no penetration → duct drops under every AHU, a roof tray linking the
  electrical units with a drop through the roof;
- no roof access → ladder from step 2's roof to step 3's;
- no drainage → downpipes at the eave's left end and step 2's front-right corner, a ridge
  flashing where the pitch meets the rear block;
- a cantilevered canopy → two posts;
- lasers into nothing → every bench ends on a circuit board.

**The two flat blocks are LEVEL** (owner): one roof deck at 3.05, the rim between them left
out where they abut, no ladder. At L3 the rear block is WIDER than the middle one (to x 3.4
against 2.4) and extends back (to 4.2), and the extra width carries a RAIL LOADING BAY on its
+X face: a siding along Y on sleepers, two goods wagons, a platform at wagon-floor height
(the assembly dock lesson — floor and deck at one level, 0.42), a roller door, and a canopy
over platform and track on posts set outboard of the wagons. The transformer moved beside the
switchgear because its old spot fell inside the widened footprint.

**Framing paid for the rail bay.** Everything at the back-right costs screen width (column =
x + y): the siding's back corner sets the frame, so the L3 extension back is 4.2 rather than
5.0 and the apron's front-left overhang is trimmed. L3 renders 966 px wide with 29 px margins.

**Growth is anchored on the showcase corner** (`SKILL.md` rule 22): L2 adds the third step
(full width, no rail), the upper clean room, a third robot and rack; L3 widens and extends
the third step, adds the rail bay, the mast, three roof electrical units, the fourth robot
and rack.

**To improve after demo**
- The glass tint is the same blue as the assembly vault; a greyer glass would separate them.
- The front pair of robots show only from the elbow up; a lower eave would show more but
  costs the corner's upper floor its headroom.
- The servers read as dark blocks; a blinking-LED column would need a second emissive.

## chem_plant — Chemical Plant  *(new, 2026-08-22; rebuilt to the owner's reference the same day)*

Built to the owner's reference image: a stepped two-storey BACK BUILDING with a clerestory
window strip and a roof vent, squat PROCESS TANKS in a grid in front of it with an accent band
round their lower third, tall slender REACTION COLUMNS with inverted-U loop pipes at the right,
pipework tying the three together, all on a slab. Typed `electrochemistry|refinery`, and the
accent is LIME — the game's `CAT_ELECTRO` — by owner instruction: not the electrolyser's
forest green, not the power family's mustard.

**The back building grows with the tanks — and both grow to the LEFT.** Levels add a column
to the tank grid (2 → 4 → 6) and a reaction column (1 → 2 → 3), and the building's width
follows the grid so the plant stays one proportioned unit. This is the owner's explicit
instruction for THIS building and the opposite of the assembly hall's rule; the difference is
that nothing is built against the building's ends, so extending it is physically possible.

**Growth is anchored on the serviced side.** The first version grew to the right, which is
where the five wall pipes and the reaction columns are — so the pipe wall slid along with
every level and the door, fixed at the left, looked stranded. A building cannot extend
through the wall its services are on. Now the last tank column, the reaction columns, the
pipe wall, the door and the window beside it are all placed from the RIGHT and never move;
new tank columns, windows and fan units appear on the left (`TX_LAST`, `DOOR_FROM_R`). The
building also stands 0.4 further back from the tanks than it first did.

**The building itself (owner direction, second pass).** A SINGLE storey painted lime below the
split and white above — two stacked boxes, whose faces share planes but never overlap in z, so
no z-fight, and Freestyle draws the joint as the paint line. Windows sit at door height with
their heads level with the door head (the facade rule from the assembly plant). Every flat
roof has the assembly head block's parapet rim with a coping course, and a row of fan units
runs along the FRONT roof edge behind the parapet, clear of the penthouse footprint. L3 adds
the upper floor — a penthouse with a NAVY clerestory strip (the panes were lime at first;
owner: normal-coloured), its own parapet and the roof vent — and a STANDALONE stack at ground
level off the building's left wall, with a firebox base and a duct into the wall, where it
had first been a chimney on the right of the roof.

**Lime is measured, and the target hue is unreachable.** On the rendered tank bands, against
`CAT_ELECTRO` 166,226,46:

| linear | rendered | saturation | |
|---|---|---|---|
| (0.30, 0.62, 0.045) | 132,163,61 | 0.63 | |
| (0.42, 0.92, 0.03) | 149,180,76 | 0.58 | owner: "too neon" |
| (0.50, 1.10, 0.02) | 157,187,85 | 0.55 | drifting to mud |
| (0.26, 0.52, 0.075) | 125,154,70 | 0.55 | dimmer, same chroma — still neon |
| (0.30, 0.52, 0.12) | 132,155,89 | 0.43 | chosen |

Two findings. AgX compresses saturation: pushing green lifts EVERY channel and the blue floor
rises with it, so the `CAT_ELECTRO` hue is unreachable. And "too neon" is CHROMA, not
brightness: dimming the lime by 16% left its saturation at 0.55 and it read the same; what
calmed it was mixing grey in — raising red and blue relative to green — which took saturation
to 0.43 at almost the same luma. Still clearly lime beside the electrolyser's green (68,116,73
as installed) and the power mustard (123,96,27). A swatch probe was tried first and was
useless — its sample points landed on shaded faces — measure on the real render.

**Grammar from the reference.** Tanks are squat (h/r 1.8) and columns slender (h/r 11); the
contrast is the silhouette. Tank-to-tank links are short horizontal stubs at mid-height and
each row's last tank runs on to its column. Every column carries an inverted-U loop from its
crown back down onto the row header (the loop's end sits on the header's top surface). The
clerestory panes are flat lime, not emissive — one emissive per sprite, and this plant has
none. Five pipes climb the building's visible +X wall and turn in at the top, collected by a
header at the bottom that runs on to the nearest column.

**Flows, all closed.** tank row → links → column (rows 0 and 1 each have one; the third column
at L3 is fed from the second's header) → loop back to the header; building ↔ nearest column
via the wall header. The building is the terminal (processing and packaging) and the plant's
electrical room.

**The first design was an open steel process structure** — a multi-storey frame with vessels
through annular decks, a cold box and cooling cells — and it was sound, but the owner's
reference is a different building. Its one reusable lesson: an elevated pipe rack across the
front buried the tank farm (tank base at depth 1.08 behind a rack top of 1.55), which is why
nothing here runs above knee height except the column loops.

**To improve after demo**
- The column loops overlap each other on screen at L3; the third column's could swing the
  other way.
- The slab is a large flat plate; the reference steps it, and a front step would help.
- No solids handling for the fertiliser recipes.
- The lime lower half is the single largest accent area in the set; if it shouts beside the
  other buildings on the map, lower SPLIT rather than the colour.

## assembly_plant — Assembly Plant  *(new, 2026-08-22)*

BRICK, like the factory beside it. A WIDE hall (2.8 deep) under a gentle segmental barrel
vault of PARTLY TRANSPARENT pale-blue glass on arched ribs — rise/half-span 0.51 so it springs
at 25° rather than a half-round's 13° — with the front left out as an open portal frame (the
EAF's precedent) so the production line is visible: a conveyor along X carrying brown and
black cartons, orange six-axis robots seated beside it and reaching over it. Orange is the
chroma and it is carried by the ROBOTS ONLY. The belt exits through an arched opening in the
right gable onto a CONTAINER loading bay at every level: the dock is the floor continued
outside, a 20-ft box on a chassis stands end-on to the dock face, and at L3 a rail-mounted
gantry crane in the port's bottle green straddles dock and lane carrying a second box. L2 adds
a tall flat-roofed HEAD BLOCK at the hall's left end; L3 adds a second vaulted WING running
back from it — the plan becomes an L, the wing a bay shorter than the hall so it reads square
in iso (equal plan lengths look long in Y, because the wing runs up the screen) — and the crane.

**The hall is the same length at every level, and it has to be.** The loading bay is built
against the hall's right gable from L1 and the head block takes its left end at L2, so the
hall cannot grow afterwards — an earlier version went 4 → 4 → 5 bays and the owner asked how
a hall with a dock already on its end had extended by a window's width. Levels add PARTS,
never length: only the robot count grows inside (2 → 4 → 5).

**The wing's inner face is the same open portal frame as the hall's front** — columns on the
bay lines, a header at the eave, the floor slab's exposed edge as the kerb — with a second
line inside: a belt along Y running toward the head block, cartons, and its own robots on the
far (−X) flank reaching toward the camera. Same visibility window, with depth measured in
from the +X face: belt at d 0.85, far robots at d 1.40 (elbows 2.52 against 2.81). The first
bay is largely hidden behind the hall's vault, which is why its robots start at bay 1. A
glazed curtain wall was tried first and read as windows, not as the hall's opening.

**The head block is a proper facade.** Three columns on a 0.75 grid and THREE storeys on a
1.15 pitch: ground floor window, DOOR, window with the door taking the middle column and the
window HEADS level with the door head (1.00); two rows of three windows above on the same
columns. The first version had a window sharing the door's column and the upper row 0.13
above the door; the second had only two rows with the upper one floating; the third had the
ground-floor windows hung 0.36 above the door head — a head line across a storey is what
makes a row of openings read as one floor. Flat roof with a
brick parapet rim and cream coping, a mullioned skylight, the rooftop unit pushed to a corner.

**Inner faces are brick.** They are seen through the glass, and a pale lining read as a
missing brick wall through the steep part of the wing's vault — `SKILL.md` rule 21.

**The floor is at dock height, and that is what made the loading bay physical.** The audit
(the electrolyser method: name every flow, trace it, find where it stops) turned up the
chain of faults in the first bay: the floor at grade with a dock 0.5 above it put the forklift
door's sill half a metre above the floor it served — "half suspended" — and left the belt
knee-high inside and lying on the slab outside; the door also overhung the dock's side edge.
A real plant floor sits at truck-bed height and the YARD is the thing that is low. Raising the
floor to 0.42 and continuing it through the wall as the dock fixes every one of those at once,
the exposed slab edge along the open front is the kerb for free, and the belt is the same
height above the floor inside and out. Cost: the eave went to 3.05 to keep the far-flank
robots inside the view window (`FLOOR < z + d < header underside`, elbows at 2.72 vs 2.81).

**Second-pass audit faults, all fixed.** The container's door seams were on the +X end because
the camera sees it — physically the doors must face the dock, so they moved to the hidden end
and the visible side carries the corrugation ribs instead. The chassis ran 0.02 into the dock
face and through the middle bumper. The gantry's front rail stood half off the apron edge. And
the vault's back 0.4 let rays escape over the wall top onto background — see `SKILL.md` rule
21 for the glass in full.

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

**Flows, all closed.** wing line (belt along Y, toward the head) → head block → (through the
shared gable) → hall belt → robots → arched exit in the right gable → palletising stand at the
belt end → pallets
on the dock → forklift door → container (doors to the dock, floor level with it, on a chassis
at yard level) → gantry → lane. Power: a switchgear cabinet on the apron at the hall's
front-right corner. At L1 there is no wing or head, so the belt starts inside the hall.

**Framing was the one real bug** — see `SKILL.md` rule 20: the apron's left-front corner sets
the smallest screen column, not the hall, and centring on the plan midpoint clipped L3.

**To improve after demo**
- The apron is the darkest large surface and reads as asphalt; it may want the cream of the
  refinery aprons instead.
- The gantry's front portal stands in front of the belt exit. It is an open frame and the
  exit shows between its posts, but it is the busiest corner of the sprite.
- The wing's interior is never seen; its +X flank carries windows so it is not a blank wall.
- No truck under the container: the vehicle kit is the film's street-scale system with haze,
  shadows and a `seed` argument, and pulling it into a sprite would break reproducibility. The
  chassis with wheels and axle hangers stands in for it.
- L3's top margin in the 1024 render is 33 px with the 4-bay wing. A 5-bay wing left 13 px;
  any growth needs a flatter WING_RISE or a shorter hall (note 5 in the builder).

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

**THE SECOND STOREY WAS UNSUPPORTED IN BOTH SENSES, fixed 2026-08-22. Two faults, and the
first fix only found one of them.**

*In Z:* `col2` ran 1.337..2.198 between a deck1 top of 1.240 and a deck2 underside of 2.230 —
0.097 of clear air under the columns and 0.032 over them.

*In plan:* every slab was sized to the grid the columns are SET OUT on (`deck1` = fw x fd,
`deck2` = fw*0.52 x fd), so the slabs reached the column CENTRELINES and stopped. The outer
columns were half off their own floor, the four corner ones three quarters off, and `deck2`
covered 26% of the column at its left end. Lengthening the columns made them REACH deck1;
it did not make deck1 wide enough to catch them. Found by the owner looking at the sprite,
after the first fix had already shipped.

The ground slab always had the lip (`fw + 0.30`, i.e. 0.15 past each centreline). The two
decks never got it — which is the whole story: three slabs, one sized from the columns and
two sized from the frame, quietly disagreeing.

**Both are now DERIVED, not chosen.** The storey spans deck-top to deck-underside; all three
slabs span `min(cols) - DECK_LIP .. max(cols) + DECK_LIP`. A number that describes where
something LANDS must be computed from the thing it lands on.

**And it is asserted, because nothing else here can see it.** Alpha IoU reads 0.999 across
both faults — a gap thinner than a line width and a slab edge 0.10 short are invisible to
every silhouette check in this pipeline. `build_construction_site()` now checks every
column's footprint against the slab beneath it and prints `COLUMN AT ... OVERHANGS ...`.
Arithmetic on the extents is the only thing that catches this class.

Consumers re-baked: the L1 sprite, and the loading film's opening (`con_a`, frames 0-75).
The street's other three construction sites (`con_b`/`c`/`d`) still carry the old geometry in
the shipped film — see FILM_RUNBOOK, they cost ~50 h to repair for a fault a couple of pixels
tall at that distance. Any future full film render fixes them for nothing.

## mine — Mine  *(FROZEN)*

Terraced pit, headframe, office block, excavator. Three genuinely distinct sprites.

**Cannot be re-baked: `mine_builder.py` is not in this checkout.** `SKILL.md` documents it and
`bake_sprite.py` deliberately omits it. It is therefore the only sprite still carrying
Freestyle's view-map contour — barely visible, since a terraced pit is solid mass with no
internal gaps for the old contour to wrongly outline. Left as-is by owner decision
2026-08-21. If the builder resurfaces, add it to `BUILDINGS` and re-bake.
