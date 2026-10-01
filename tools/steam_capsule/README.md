# Steam capsule key art (Blender)

> **What is here.** The scripts, their small data files, and a few final images in
> `renders/review/`. The saved Blender scenes (`*.blend`), the full render history and the
> comparison images named below are kept off GitHub, on the owner's machine; the scripts
> regenerate every image. `KEY_ART.md` explains what was built and why.

The Steam store capsules, built as a diorama in the game's own sprite style: the shared
sprite kit in `~/Price of Everything/blender-assets/` (see the `blender-building-sprites`
skill). That means a true-iso orthographic camera, flat faces, Freestyle ink, no cast
shadows and the stipple print pass.

## Parts

- `earth_plate.py`: the base. Pointy-top hex columns (circumradius R, depth R, which is
  half the vertex-to-vertex height) in one mesh, with no seams on top. The layout is the
  AI concept's slab transferred to hexes (see "Matching the AI concept"): nine land cells
  and a four-cell bay at the back right, open to the east. One shape runs through the whole plate: the map's
  land-to-sea edge (`survey_overlay.gd` `_coastline_curve`, ported: three sine octaves
  tapered to zero at the hex corners, plus an occasional spike).
  - **Coast:** it follows that shape between land and sea cells, with the shared coast
    corners nudged the way the game nudges them. The shoreline is inked.
  - **Strips:** a sand strip and a shelf-water strip run beside the coast, each widening
    and narrowing on its own profile.
  - **Top surface:** a single constrained Delaunay triangulation, so neighbouring areas
    share every edge.
  - **Walls:** banded into strata from the kit's measured earth ramp, its coal and its
    iron ore, with every boundary between bands its own curve of the same shape. The coal
    and ore deposits vary in thickness by it too, thin toward the back of the
    camera-facing walls and pinch out in places.
  - **Sea walls:** a water column over seabed sand, shallow at the shore and deeper
    offshore, with the strata carrying on underneath.
  - **River:** three times as wide as the game draws rivers (`river_visuals.gd`: 15 px,
    25 px at the mouth, on a hex 480 px flat-to-flat), so a bridge can carry the
    composition. It leaves the head of the bay, runs west across the middle of the plate,
    snakes north and exits through the hidden back wall. Its banks wander by the coast
    profile. It is laid over the land in the triangulation, so the river mouth has no
    seam, and ink goes wherever land meets water (the coast and both banks) but not where
    water meets water.
  - **Pits:** holes cut in the top for a building that digs down (the mine), each walled
    straight down to its first bench; the benches below are the building's own.
- `buildings.py`: the game's own buildings, each built by the sprite builder its shipped
  sprite came from (`.claude/skills/blender-building-sprites/`, and `mine_builder.py` from
  `~/Price of Everything/blender-assets/`, the only copy there is), then moved into place.
  - **Levels (owner):** every works at its level 3, the fullest.
  - **Chemical plant (owner):** the game's chemical plant (level 3) in the empty plot by the
    river in the middle of the plate, at 0.48 (its L3 is the biggest sprite, so it matches
    the power plant), with a road off the west road to its door and two pipe bundles that
    run a short way on low supports and turn down into the ground (`blockout.PIPELINES`),
    each starting inside the plant's nearest tank or reaction column, so it comes out of
    its side.
  - **Sizes (owner):**
    - The mine keeps its sprite size; its pit is cut into the plate, so it shows the
      plate's own coal seams.
    - The power plant, factory, high tech manufactory and assembly plant stand at 0.6 (half,
      then a fifth bigger), and battery storage at half.
    - The electric arc furnace, which replaced the blast furnace, stands at 0.45: its melt
      shop is far the biggest.
    - Offices are at 0.28, and houses and blocks at half of what `housing.py` draws, so
      homes stay well below the works.
  - **Layout:** coal at the back, the clean end at the front. EV Assembly is an Assembly
    Plant recipe, so the assembly plant is the EV plant, at the front tip.
  - **Frontage:** houses and offices stand on lots along the roads (`FRONTAGE`: road, how
    far along it, which side). Each is turned so its front, the door side, faces the road,
    set back from the kerb.
  - **Parts, not whole sprites, where a sprite stands on its own ground:**
    - the mine without its block of earth or its shaft section;
    - the solar farm's panel rows (four, the middle two stepped one panel right) without
      the rest of the farm, mirrored on screen about the array's own centre (owner: so they
      face the sun in the key art, which is laid out mirrored with its light from the left;
      `SOLAR_MIRROR`). The array is reflected across the upright plane through the camera's
      line of sight (the rig looks along (-1, 1) in plan), so the camera still sees the
      panels' faces; in the mirrored key art they tilt toward its lower left, toward the
      light, and so catch more of it and read lighter than before (from v32);
    - the wind farm's turbines, on land and on the offshore farm's monopiles in the
      distant sea (three, in the back-right tile: none in the ship's way out of the harbour
      or alone on the east tile), painted white: the kit's "white" is a grey on purpose,
      which read dark against the sea. The land ones keep the full line, blades and all, so
      they stand out against the sea behind them (owner);
    - the electrolyser's battery block, in a row;
    - the EV plant's lot: 25 of the diesel goods icon's sedan (owner), read from the commit
      that shipped it and without its jerry can, in five rows of five on a concrete pad,
      repainted per bay. The icon's boolean cuts are baked once and its 300k faces cut down
      (`EV_FACES`) before it is copied, which took the render from minutes to seconds. The
      pad runs on at the front-left end for a green charging unit, and a short road joins
      it to the spine. A few more of the same car drive the roads (`road_cars`), keeping
      right, each with white headlamps and red tail lamps that the warm looks light, the
      headlamps throwing a short beam on the road;
    - the port's gantry crane, container ship and containers on a pier. They are turned a
      quarter to the left, which keeps the faces the port details toward the camera. The
      crane's trolley is run out over the ship's middle, and its hook swapped for a container
      spreader, a yellow frame the size of a container's top with twistlocks at the corners,
      hovering over the stack below (owner).
  - **Turns:** the sun stands over the sea, off the right of the frame, so +X walls are lit
    and -Y walls shaded. Sprites carry their detail on the -Y front, so the buildings
    whose front is the point turn: the power hall +90, to bring its windows into the light;
    the arc furnace +45, so its bay faces the camera square on (owner); the high tech glass
    hall and the EV plant's open line +20, most of the way back to the sprite's three-quarter
    view, so their fronts face the camera with a side showing too (owner). The factory's long window wall is already its
    +X side, so it stays as built.
  - **Redesigned parts:** the mine's lattice headframe and the power plant's switchyard are
    swapped for bolder versions from `capsule_parts.py`.
  - **Thin line:** every part smaller than 0.69 on screen (35 px at the review size) moves
    to the thin line. Trees keep the full line.
  - **Habits undone:** builders expect one sprite per scene. Each one resets the rig,
    hides other `BLDG_*` collections, unlinks everything from `FINE_INK` and shares
    materials by name (the assembly plant's `crate` is black, the factory's wood). So each
    building gets its own collection, object names and material copies, and its fine-ink
    parts are relinked at the end.
- `capsule_parts.py`: capsule-only redesigns of two game parts that turn to mush at capsule
  scale (measured at about 45% ink): the mine's headframe, now four bold legs, two belts, a
  brace per panel and two sheave wheels facing the camera; and the power plant's switchyard,
  now two transformers, a gantry and a bold pylon. Fewer, thicker members, on the regular
  line, built in the building's own frame before it is moved. Also the EV lot's charging
  unit, which the game has no model for: the goods icon's green cabinet, with a dark screen
  and a yellow bolt facing the camera.
- `housing.py`: houses, terraces and apartment blocks, new, since the game has none.
  - **Scale:** a home's storey is 0.45 against the halved factory's 0.55.
  - **Houses:** a gable roof over a wall-coloured gable.
  - **Blocks:** a flat roof inside a parapet.
  - **Windows:** painted as glass quads on every wall, with no ink, because a framed window
    at this size is mostly outline.
- `place_trees.py`: picks the tree spots from a layout and writes `trees.json`, which the
  render builds with the game's own tree prop (`props_kit.py`).
  - **Planted first (owner):** an avenue down both sides of the spine road from the docks to
    the EV plant (`AVENUES`, following the road's own line from `blockout.ROADS`, nearer
    the kerb than scattered trees may stand), and a copse between the factory and the high
    tech manufactory (`COPSES`).
  - **Where:** grass only, clear of buildings, roads, rail, water and the plate's edge.
  - **How:** spaced by Poisson-disc sampling and thinned by a smooth field, so they gather
    in copses.
  - **Size:** 0.4 of the prop's.
  - **When:** run it again whenever the layout changes.
- `blockout.py`: the roads, the railway and the bridges.
  - **Roads:** one network (`ROADS`). Every road starts on another's control point, so
    they meet exactly, and the first two start at the pier's root.
    - **One solid:** they are built as the union of every road strip, triangulated
      together and walled only round the outer edge. Separate strips each carry their own
      outline, which crosses every junction.
  - **Railway:** a coal line. A trunk leaves the power plant's coal heap (a buffer stop
    closes it) and crosses the river's west bend on the truss, on a slant to the south-west
    so nothing turns hard off the bridge's west end (owner). Just past the bridge it splits
    (owner), each leg leaving a few degrees off straight on, like a turnout. The west leg
    swings north round the mine's headframe and the south leg runs down between the mine
    and the river, past the mine's coal heap. Both run off the plate's edge, each leaving
    nearly square through its wall. The legs are laid as arcs of 0.3 R or more and
    straights. The trunk starts at the plate's north edge past the power plant (owner), so
    the line runs off the plate at all three ends. A coal train, a diesel engine and two
    loaded hoppers (`capsule_parts.coal_train`), stands on the south leg between the mine
    and the factory, heading out and following the curve (owner). The heaps are the only
    shapes left in `BUILDINGS`: the mine's coal by the south leg, the power plant's, and a
    big heap of copper ore against the mine tile's south-west edge, the wall that faces the
    camera, dark orange with malachite green in patches, with nuggets rolling to the lip and
    falling down the wall (owner; their own collection keeps them out of the layout check).
    In the mine's pit, haul trucks stand on the far benches and floodlight masts on the rim
    (`buildings.pit_works`).
    - **Track:** a stone ballast bed carrying the outline, timber sleepers across it and
      two steel rails on top. The sleepers and rails are painted (no ink), since at a few
      pixels each an outline would be all there is of them.
    - **Level crossings:** the bed and sleepers stop and the rails run on over the road.
      The west road crosses the south leg this way to reach the mine's headframe.
  - **Sunk walls:** road and ballast walls start a little below the plate top. An edge
    lying exactly on it breaks into dashes, because its visibility is a coin toss; sunk,
    it is simply hidden.
  - **Rail bridge:** a Pratt through-truss in red oxide, with inclined end posts, verticals,
    diagonals down toward mid-span, top struts and concrete abutments. It carries the fine
    line. It crosses where the river runs north, on a slant, and stays well turned toward
    the camera.
  - **Road bridges:** two plain decks with low parapets, one over the river's lower stretch
    into the town and one over its north stretch to the arc furnace.
- `label_render.py`: writes each label beside its shape, for reviewing a layout.
- `render_earth_plate.py`: builds the buildings first, then states the capsule's rig (every
  builder resets it), the plate and the blockout, and renders them headless. It also writes,
  beside the PNG:
  - `.probe.json`: sample points and label positions;
  - `.layout.json`: every footprint, pit and road end, for `check_layout.py`;
  - `.shade.png`: the shading mask (each face's dot product with the sun, as in
    `render_sprite.py`), which drives the stipple;
  - `.shadow.png`: the sun alone with shadows on white, black where the sun cannot reach;
  - `.water.png`: an unlit mask pass in which only water is white;
  - `.plate.png`: the plate on its own, for the heavy outer line;
  - `.look.json`, and with a warm look `.glow.png`: its light sources alone, and for golden
    `.nw.png` and `.se.png`: the frame again under its north-west and sea-side lights (see
    `lighting.py`).

  **Sun:** over the sea, off the right of the frame (`SUN_AZ` 45, `SUN_EL` 48, energy 2.45,
  world 0.62). The sprite rig lights from beside the camera, so a cube's three faces render
  within 8 luma of each other. This light gives three tones and keeps every map colour at
  its calibrated value. It is high enough that flat tops stay clean in the stipple.

  **No-ink faces:** every lineset leaves out faces marked no-ink (`freestyle_face`): painted
  windows, sleepers and rails.

  `--albedo name=r,g,b` overrides a colour for calibration. `--no-blockout` renders the
  plate alone, and `--no-render` builds and writes `.layout.json` only, for layout work.
  `--look golden` or `--look dusk` renders one of `lighting.py`'s warmer looks.
- `lighting.py`: the looks. `day` is the calibrated light above and changes nothing.
  `golden` (warm sun) is the owner's choice; `dusk` stays as the light golden's north-west
  leans toward. The AI concept's amber comes from these, turned up together:
  - **Warm key, cool fill:** the sun goes amber and the world, which lights the shaded
    side, goes blue.
  - **Mine, works and windows (owner):** lamps on the mine's headframe (its deck corners, a
    red light on top and a floodlight); every building's windows lit alike; the high tech
    hall's big skylight glowing and blooming to draw the eye, and the EV plant's glazed
    vaults lit the other way, from white work lamps low on the floor among the robots,
    seen through clearer glass, with the lamp at its front white too (owner); stronger, broader lamps before the mine, the factory, the arc
    furnace and the chemical plant, which wash their fronts; and light coming up out of the
    pit: the haul trucks' headlamps and beams, the masts' floods, a lamp low in it, and a
    tall warm glow over it that `finish_render.py` screens in over the smoke.
  - **Light sources:** a share of every building's glass lights up warm (whole window
    objects, or single quads of a painted window mesh; only a window box's sides, so no
    roof glows). The arc furnace's melt and the laser glow as always.
  - **Lit from inside (owner):** the high tech hall and the EV plant each get a lamp inside,
    and their doorways and openings glow; the glass hall's panes take a warm tint and
    stay see-through.
  - **Port (owner):** lamp posts down the pier's far edge with pools on the deck,
    floodlight bars under the crane's boom, and red lights on its apex and boom tip.
  - **Roads (owner):** cars' lights in pairs, white on one side of the road and red on the
    other, spaced at random along every stretch on land (`blockout.ROAD_RUNS`).
  - **Pools and bloom:** point lamps at each works' front throw warm light on the ground,
    and every light source blooms.
  - **From the mine to the sea (owner):** as in the AI concept, smoke over the mine and a
    low golden light off the sea, both strong (owner: strong enough to read as one light
    across the map and the nameplate beside it). The light is a real source: a broad warm area lamp high
    over the bay, which falls away inland, so the coast and the sea are lit gold and the
    mine's side gets little. Glints lie on the water, thickest toward it. Over the mine's
    side `finish_render.py` lays a smoke haze, a dark warm grey in billows, thinning to
    nothing past the middle of the plate. (`side_lighting` can still blend in renders of the
    frame under other light, `.nw.png`/`.se.png`; golden no longer uses it.)
  - **Why a glow pass:** AgX takes a bright amber most of the way to white. So the light
    sources are rendered again alone under the Standard view, and `finish_render.py`
    paints them from that pass and blooms them in 2D, since EEVEE has no bloom.
- `earth_plate.py` (sea): the sea cells take the shelf's colour, top and wall (owner), so the
  bay reads as one shallow sea. (lenses): a copper deposit swells in the topsoil of the wall
  below the copper heap and pinches out either side (`LENSES`, owner); the topsoil is split
  round an empty lens band everywhere else, so no other wall changes.
- `smoke.py`: grey smoke from the arc furnace's stacks and the power plant's flue, and
  white steam from its cooling tower (owner). Each plume is a string of the game's goods FX
  puff (`goods_icon_batch3_fx.py`: overlapping spheres, two greys, inked round every
  sphere), each puff overlapping the last, growing as it climbs, bending north-west on a
  sea wind, and breaking up at its end. The factory's chimney has none: its plume would
  drift across the rail bridge. The puffs take the thin line and cast no shadow.
- `finish_render.py`: the print pass the game's sprites use since August: `stylize_shade.py`
  with `bake_sprite.py`'s parameters, driven by the `.shade.png` mask.
  - **Stipple means shade:** dots come from how far a face turns from the sun, not from
    its colour.
  - **Printed at each output's final size:** printed large and then shrunk, the dots turn
    to grain at Steam sizes.
  - **Shadows:** with `--shadows`, ground and roofs in a cast shadow print as a dense
    band of dots, as the loading film printed its shadows. Walls and trees take only their
    own shading, since there shadows are only speckle.
  - **Water:** it goes back to flat map colour.
  - **Heavy line:** it goes round the plate only.
  - **Smoke haze:** with golden, over the mine's side (see `lighting.py`), before the lamps.
  - **Lamps:** with a warm look, the light sources are painted in their own colour from
    `.glow.png`, then given a tight and a wide bloom. A lamp only brightens, and never paints
    over the ink (the glow pass has no lines, so a line in front of a lamp would go). The
    sea's glints are not lamps: they come from the render, where what stands in front hides
    them.
  - **Sides:** `.nw.png` and `.se.png` are blended into the render before the print, along
    the look's ramps.
  - **Why not the kit's line:** Freestyle's `contour` lineset draws it wherever background
    shows, so it climbs every chimney that rises past the plate's edge and fills the gaps
    between stacks. The sprites draw theirs in 2D round the whole silhouette instead
    (`sprite_export.py`, since 21 August).
  - **What it does here:** it follows the plate's own silhouette and stops wherever
    anything stands in front, so buildings keep their ordinary ink against the sky.

  It writes `_print.png`, `_print_on_navy.png` and `_labels.png` at full size, and
  `_main.png` at 0.45 (the plate at about the height of Steam's 1232x706 main capsule).
- `check_layout.py`: rasterises the footprints in plan view, turned like the camera. It
  reports:
  - any building in water or off the plate (the pier may stand over water, and the ship
    and offshore turbines must);
  - any building within 0.1 of a road, or 0.2 of the railway, the river or a bridge, except
    where a road ends at it (the coal heaps may stand by the track they are tipped from);
  - any two buildings within 0.08;
  - any road or railway running into water off a bridge or the pier;
  - roads that are not one network with their bridges and the pier.

  It draws `_plan.png` with the clashes in red and exits 1 if there are any.
- `measure_render.py`: reads each top colour back at its probe points, compares it with
  the in-game target, and prints the next albedos to try as ready-made `--albedo`
  arguments.
- `nameplate.py`: a prototype of the game's nameplate (owner's brief), rendered in Cycles,
  seen straight on so it can be laid flat over the key art, with a transparent background.
  Every plate is navy enamel with a thin raised brass rim and (but for `honeycomb-wide`)
  slotted brass screws, as on the current emblem (`~/Desktop/carbon-capital-emblem-1400x700.png`), lettered in tall,
  blocky capitals (owner: "taller, blockier").
  - **Letters (`--letters`):** `octagon` (the default; owner: the tops and bottoms of letters
    such as C and A octagonal): an alphabet drawn in `nameplate.py` (`oct_glyph`) on
    Impact's tall, heavy, condensed proportions, every curve a 45-degree chamfer, the counters
    chamfered smaller, stems square: the O an octagon, the A's apex a wide chamfered top,
    the C's terminals blunt blocks, the R's leg leaving its bowl halfway along the bowl's
    lower stroke on a diagonal and dropping upright only near its foot (owner: so it does not
    read as an A; `RLEG_UPRIGHT`). It has only the letters the plate spells (A B C D I L N
    O P R T); another word needs its letters added. All three words use it. `impact`:
    Impact, drawn up to 60% taller than its face.
  - **`--plate hexbar` (owner):** CARBON, a hex of coal and CAPITAL in a row. A navy plate on
    each side, lettered in brass, and between them a regular pointy-top hex whose upright
    sides are as tall as the plates (`HEXBAR_S`), so each plate meets one of them edge to
    edge and the three are one piece: a long bar with the hex's points standing above and
    below it, one brass rim round all of it, brass dividers where the plates meet the hex.
    Each plate's outer end is half a regular octagon (owner), its corners cut at 45 degrees.
    CARBON's C is drawn to fit its end: its outer corners follow the cut ones a margin in,
    and its inner corners are cut at 45 degrees too, parallel to them, so its stroke is even
    all round (owner: 0.25 on the stem, 0.24 across the cuts, 0.23 on the bars). CAPITAL
    stops where the cut corners begin, so its L's foot stays level (owner: rather than bend
    up the cut); its letters are a little narrower for it. The rim and the dividers between
    the plates and the hex are one piece of brass, bevelled together: made apart, their
    bevels pinched where they met, into dark holes at the four joints (owner).
    The hex is filled with large lumps of dark coal (`HEX_LUMP`, a little loose), none
    glowing. AND (`--hexbar-and`): `letters` (the default; owner) is raised silver letters
    alone on the coal, no plate under them, half the bar's height and the hex's width
    (`HEXBAR_AND_SCALE`; owner: at the full bar's height they were too big), in its middle; the lumps under them are pressed down
    beneath them and those between them left standing. They are lit by the brass lamp as the
    brass is, or their flat metal faces mirror the dark above them and read grey. `plaque`
    (hex bar v1): a bright silver plaque with its corners cut (`PLAQUE`), AND engraved in it
    and filled with the plates' navy enamel.
    The plates are as long as each other: CARBON's letters `HEXBAR_LETTER_W` wide, CAPITAL's
    a little narrower as it has the I as well; both words level, top and foot, in the
    octagonal letters. All the brass is lit as on the single hex. About 4 to 1; render it
    wide (`--res 3300x1020`).
  - **`--plate single` (owner: a simplified logo; v32's honeycomb kept in reserve):** one
    regular pointy-top hex (`SINGLE_A`), no icons, frames or screws. CARBON in its top half,
    standing on a level line above the middle, its letters' tops rising to the hex's top
    point (the point over the gap between R and B, so each top is one straight slope);
    CAPITAL in its bottom half, hanging from a level line below the middle, its feet dropping
    to the bottom point, the I standing over it. The words are moulded as on the wide
    honeycomb (the letters stretched between their strokes; C, A, R and O squared at the
    top, CAPITAL's C at its foot), so the middle letters stand about two and a half times as
    tall as the outer ones. AND, in the words' capitals, is stamped into the plate in silver
    (`--and stamped`, the default here): the letters pressed `STAMP_DEPTH` into the navy,
    their floors bright satin silver, the cut walls shading them on the side toward the
    light. All the brass is as bright as CAPITAL's C on the honeycomb: the brass-only lamp
    hangs over the whole hex (`BRASS_LAMP_SINGLE`, as bright to a unit of its area as
    `BRASS_LAMP`). Renders portrait, 2200 tall. A flat-top hex was considered: its halves'
    sides slope so steeply that the letters would have to taper to about half their width
    at the top.
  - **`--plate honeycomb-wide` (the default; owner):** the emblem's honeycomb with the words
    across whole rows, so they have room: CARBON across the top row and CAPITAL across the
    bottom one; the middle row holds AND between the two icons, the factory in the left
    hex and the solar panel in the right, each outlined in brass. The frames stand as high
    as the icons, so they cast shadows. The factory is joined to its frame (owner: it meets
    it in three places): grown as large as it fits in the frame's ring (`fit_in`), so it
    reaches into it at the smoke's tip and both ends of the ground. Each keeps its own chamfer,
    as the solar panel and its frame have, and the two are then unioned and baked into one
    mesh of brass (bevelled only after the union, the icon's many short traced edges kept the
    bevel from taking and it looked flat; owner). The only screws are four small silver ones, one
    either side of each icon, on its hex's upright sides just inside the frame (owner;
    `SILVER_SCREW_R`, smaller than the old brass ones). The navy is darker than v11's, so the lit plate is close to the backdrop's navy
    (owner).
  - **Words (`--words`, octagonal letters on `honeycomb-wide`):** `moulded` (the default;
    owner): the words fill their rows' hexes. CARBON stands two letters to a hex on a level
    line, each letter's top one straight slope rising to its hex's point; CAPITAL's seven
    letters hang across the three hexes from a level line, their feet sloping down to each
    point, the I's foot a V on the middle one. Each letter fills the half of a hex between a
    point and the next hex (or the plate's side), so the gaps between letters are all alike
    and each word reads as one: centred as pairs, the letters had to be narrow and left
    wide gaps where the hexes meet ("CA RB ON"). The letters' widths therefore differ a
    little, the ones against the plate's sides the narrowest. A letter is stretched to its
    height between its strokes (`oct_glyph` gives each letter's strokes), which keep their
    thickness. Where a letter meets a hex edge, its chamfered corner is squared so it reaches
    into the hex (owner): the tops of CARBON's C, A, R and O, and the foot of CAPITAL's C by
    the plate's side (`square` in the layout); the other letters are left as drawn. CARBON's heat is measured up each letter's own height, so it slopes with the
    tops. `boxed`: each word in a level box (v15).
  - **Icons (`--icons`):** `game` (the default; owner): the game's own factory and solar
    farm icons (`b_007`, `b_024`), keyed to one colour and traced by `icon_key.py`, raised
    in brass like the lettering, fitted in a square `ICON_BOX` on a side (owner: 10% smaller
    than v17's), the factory's windows and the panel's cells cut through.
    `drawn`: the earlier drawn stand-ins.
  - **`--plate hex`:** one pointy-top hexagon, like a map tile: the factory in its top
    point, CARBON, "and" on a riveted brass tab across a brass rule, CAPITAL, and the solar
    panel in its bottom point.
  - **Top row (`--top`, with the moulded coal CARBON on `honeycomb-wide`):** `coal` (the
    default; owner): the top row's three hexes are a slab of coal with CARBON burning in it,
    sitting on top of the rest (just above the rim, `COAL_Z`); the navy plate and its brass rim
    end at the middle row's top. CARBON's letters are moulded to the hexes top and bottom
    (owner: the bottom fits in better so than flat; a flat foot would have run the slab's
    edge over the icons' frames), each a half-hex wide as on the plate, `COAL_MARGIN` from
    the slab's edges (owner: 30% nearer than on the plate, so the letters have more room),
    their corners squared top and bottom where C, A, R, O and B had chamfers, so they reach
    into the hexes' points. The letters are solid (owner: no cracks in them) and white-hot
    only down the middle of each stroke, through yellow and orange to red toward its edges,
    as the bed's gradient (`HEAT_COLOURS`, run over `LETTER_HALF`; owner: more red), glowing
    as v22's letters of coal did (`LETTER_GLOW`). Round them, coal lumps over a glowing bed
    cover the three hexes, cut along the letters' outlines: the lumps dark and the cracks
    red, fading quickly away from the letters (`EMBER_FADE`) but never quite out
    (`EMBER_FLOOR`) (owner). The slab's edge is crumbled (owner: a little rougher;
    `rough_outline`, `COAL_ROUGH`): in along its top and sides, and spilling a little over
    the rim along its foot, so no gap shows there. The heat is by the
    distance from the letters' edges (`heat_field`: a signed distance field of the letters,
    packed into the scene as a float image the materials read by position). No coal in the
    narrow gaps between letters, nor slivers of it in their notches (no lump centred nearer a
    letter than `GROUND_CLEAR`): the bed glows there.
    With the whole row burning the fire casts less light for its brightness (`CARBON_LIGHT`
    12, not 40), or the dark coal round the letters turns orange. The hidden fire lamps run
    level and low over the slab, where the plate's CARBON stands (owner: v22 lit the plate
    better than lamps following the moulded feet up the slab). AND drops a little
    (`AND_DROP`) to clear the plate's new top edge where it dips between the middle hexes.
    `plate`: the top row part of the navy plate (v21).
  - **Squeezed letters:** moulded top and bottom, a letter is much shorter where the hexes
    meet than by their points. Shorter than drawn, the gaps between its strokes give way first,
    down to `ZONE_MIN` of their size, then its strokes thin; taller, only the gaps stretch.
    A's crossbar stays level in both words (owner; `LEVEL`), at the height it takes in the
    letter's middle.
  - **Hexes (`--hexes`, both honeycombs):** `regular` (the default; owner): every side the
    same length. The plate keeps its width and is about 15% shorter than with the emblem's
    hexes, so the rows sit closer: CARBON stands as low as it can with its outer letters'
    feet clear of the icons' frames, and CAPITAL hangs as high. `tall`: a little taller than
    regular, as the emblem's are (v16). A honeycomb renders 2200 wide and as tall as the
    plate needs.
  - **`--plate honeycomb`:** the emblem's honeycomb (three hexes over four over three):
    CARBON across the two left hexes of
    the top row, the factory alone in the top-right hex, "and" in the middle row, the solar
    panel alone in the bottom-left hex and CAPITAL across the two right hexes of the bottom
    row (owner). Each icon's hex is outlined in brass.
  - **CARBON (`--carbon`):** `brass` (the default; owner): raised brass as CAPITAL is, the
    same moulded letters, lit as CAPITAL is (the brass lamp over the plate's left two thirds
    included); nothing on the plate glows. `whitehot` (v26 to v29; owner, after a player
    found the coal letters hard to read, their top halves most): solid raised letters as deep as
    CAPITAL's, the same shapes, glowing white and yellowing to orange only at their edges
    and down their bevels (`white_hot_mat`, `HOT_*`; owner: a smidge less bright than v26);
    where they meet the plate a little of them has melted, a low rounded skirt round each
    letter's foot and inside its counters (`MELT_W`, `MELT_H`) glowing orange at the letter
    and cooling through red to scorched dark. The skirt's outline is each letter's outline
    pushed out and each counter drawn in (`offset_poly`, its sharp corners cut off square
    rather than mitred out to spikes); Blender's own curve offset closed B's small counters
    up and filled them with the melt, which read as red holes (owner). Its hidden fire
    lamps stand just below the letters' feet (over them they lit hot spots in the counters),
    and the letters cast less light for their brightness (`CARBON_LIGHT` 6), or their
    counters fill with orange. `coals` (owner, after a reference of letters built of glowing
    coal; v15 to v25): each letter broken into angular lumps of coal (a Voronoi cell
    per lump, the letter cut to each, raised, its top poked into facets), no brass outline,
    over a glowing bed that shows in the cracks. White-hot at the letters' feet to red a
    quarter of the way up, then the red dying away to nothing by three quarters (owner);
    the bottom lumps glow from within on the same scale, evenly (the glow's noise runs in
    world space: per lump, it left dark flecks). The fire is a real light (owner: it lights
    and shadows as the sun does): the glowing bed and lumps light the plate, AND, the
    frames and the coal round them, cast shadows, and fill the sun's shadows beside the hot
    lower halves of the letters, while the cooler dark tops still cast theirs. To the
    camera the fire looks as tuned; to every other ray it gives `CARBON_LIGHT` (40) times
    that light, tinted warmer (`FIRE_TINT`: the glow as a whole is orange round its
    white core), since at its seen brightness it lit only a thin rim at the letters' feet.
    (It replaces a hidden strip lamp along the word's foot, v16 and before.) On the navy
    enamel, which reflects almost none of that orange, the fire's light barely filled the
    shadows the sun cast beside the glowing coal. So the lumps in the lower
    `SUN_SHADOWLESS` (60%) of their letters, and the bed, cast no shadow from the sun or the
    fill (shadow linking), as if the fire's light filled them (owner); the dark coal above
    them still does. The fire is also one wide light across the whole word (owner): a row of
    hidden lamps (`FIRE_LAMPS`) a little above the glowing coal, so its light reaches across
    the plate rather than skimming it. It fades the sun's shadows round the letters' upper
    halves, and casts its own: the dark coal's up and away from it, AND's down, the frames'
    into their hexes. They are strong, because the navy shows little of an orange light, so
    they light only what is round the coal and not the coal itself (light linking), or its
    dark tops would glow. No sparks (owner). With `--letters impact` the letters are made angular by cutting
    Impact's curves into straight facets (a font resolution of 1), CAPITAL's too. The other ways, each on a brass
    outline:
    `heat` (owner, after the AI plate): dark, calm graphite coal with a few cracks and a hint of heat at the
    letters' feet, an ember glow along their lower edges that runs a little way up the
    cracks. `forge`: each letter a window into a forge, red-hot at its foot through orange
    and red to dark at its top, sparks flying up. `ember`: blocks of coal set a little
    askew, their larger cracks glowing.
  - **More light on the plate (`--light topleft`; owner: stronger at the top left and reaching
    further along it):** a broad round warm lamp high over the plate's top-left quarter
    (`PLATE_LAMP`), the sun's colour. The navy is too dark and the brass too metal to show
    a low lamp from the side (one off the corner changed the plate by under a tenth), but
    seen from straight above they mirror one overhead: the brass bright gold at the top left
    and deepening across the plate, the rim glowing along its top left. At 600 W and more
    the flat brass under it bleached to cream; 380 W keeps it gold.
  - **The brass as bright as CAPITAL's C over the left two thirds (`--brass-light wide`, the
    default; owner):** the C was that colour because, fully metal and seen from straight
    above, its flat face mirrors the lamp over it, and the round lamp covers only the top
    left. So a flat lamp as bright hangs level over the left two thirds of the plate
    (`BRASS_LAMP`), and every brass face under it mirrors the same gold; the right third
    still deepens, so the light still reads as coming from the left. It lights only the
    brass (light linking: the rim, the frames, the icons and CAPITAL), or the navy under it
    takes a grey sheen, and the round lamp now lights everything but the brass, so the C is
    not lit twice. Measured: CAPITAL's C, P and first A within a few levels of v28's C;
    at 60 W and more the brass paled toward cream. `corner`: v28's one lamp.
  - **Brass:** more gold than up to v25, and a little shinier than v26 (owner: smoother, its
    wear narrower; `BRASS`, `brass_mat`), on everything brass: the rim, the frames, the
    icons and CAPITAL.
  - **AND (`--and`, `honeycomb-wide`):** `coal` (the default; owner): the letters built of
    loose coal (owner: less orderly; `AND_LOOSE`: lumps of mixed sizes, unevenly gapped, each
    turned, nudged and tilted a little) on a black bed drawn in under them so the coal hides
    its edges, in a bright silver dish sunk into the plate. The dish is squarish (owner): a
    long slot, its corners only just taken off (`DISH_CORNER`), as wide as the middle row
    allows, its ends `DISH_TO_FRAME_PX` (17) of the render's pixels from the icons' frames
    (owner: 15 to 20 px), and as tall as the frames' upright sides, so its ends run beside
    them (measured at 2200 wide: 17 px each side; the ends 223 px tall, the frames' sides
    227). AND is fitted inside its floor (`AND_CLEAR`), its proportions kept: 0.75 of v31's
    size, the dish being lower than the octagon was; its floor `DISH_DEPTH` down, its lip just proud of
    the face, its wall sloping in so the side facing the light catches it and the other
    falls in shade, the coal casting its shadows on the floor. The silver is satin and
    not wholly metal (`dish_silver_mat`), so its floor, seen head-on, is lit as the face
    beside it is rather than mirroring the dim sky. `silver`: raised brushed silver (v11 to
    v25).
  - **CAPITAL:** raised brass (owner: it stays brassy gold). CARBON's and CAPITAL's bevel is
    a little wider than the rest of the brass (owner; `LETTER_BEVEL_BRASS`, 0.036 against
    v30's 0.025), taken within the letters' outline so their footprint and spacing stay as
    they were. Under the high sun its chamfers
    are flat (45 degrees), each side one face the light lands on evenly (owner: lit rounded
    rims round dark faces looked odd there); under the low one, rounded. **AND** (`honeycomb-wide`):
    capitals in the words' own face, raised in brushed silver (streaks across, brighter
    toward the light, wide bevels that catch it; owner). **"and"** (the other plates):
    cream enamel italic (Baskerville) on a brass tab.
  - **Light (`--light`):** all from one side: from the right (owner's first brief), a low
    key and a higher fill, so every relief casts its shadow to the left; or from the top
    left (`topleft`, with the key art mirrored so its sea light comes from the left too), a
    sun, so the light lands evenly on the whole plate (owner). `--sun low` (the default; owner:
    back to v11's lighting) sets it about 39 degrees up, with the navy and satin, wholly
    metal brass the plate was tuned in. `--sun high` (v13) sets it about 66 degrees up, so
    it lights the plate's face head-on, with short shadows; there a wholly metal flat brass
    face seen head-on reflects only the dark above it while its bevels catch the sun, so the
    brass is part metal (`BRASS_METAL`), its wear narrow and fine, and the navy and gold
    deeper, to keep their colour. The fire is its own light. Grime gathers where
    the relief meets the face (ambient occlusion in the metals and enamel). The render
    leaves `<out>.light.json`, so `nameplate_finish.py` casts the plate's shadow the same way,
    and `<out>.glow.png`, the frame again with every light off, so only the fire shows: the
    bloom comes from it alone (from the render's bright pixels, it caught the lit brass).
  - **References:** the owner's forge photos were used only as a look to imitate (colour,
    heat gradient, sparks); none of them is in the render. One carries a steel firm's
    watermark and another is a search-results screenshot, so they are not ours to reuse.
  - **Scenes:** `nameplate_hexbar.blend` (hex bar v4: octagonal plate ends, the C drawn to
    fit, half-size silver AND); `nameplate_single.blend` (single hex
    v1, the simplified logo);
    `nameplate_brass.blend` (v32, the honeycomb in reserve: brass CARBON and CAPITAL, loose
    coal AND in the squarish dish); `nameplate_white_hot.blend` (v29: white-hot CARBON, the brass lit like the C over
    two thirds); `nameplate_coal_top.blend` (v25, the coal top row); `nameplate_regular.blend`
    (v21, the navy top row, re-rendered with v25's R and level A crossbars: `--top plate`); `nameplate_moulded.blend`
    (v16, taller hexes, the strip lamp); `nameplate_coals.blend`
    (v15, level words, screws); `nameplate_hex.blend` and
    `nameplate_honeycomb.blend` (v7, heat);
    `nameplate_forge.blend` and `nameplate_ember.blend` (v6); `nameplate.blend` (v5, the
    earlier octagon).
- `compose_capsule.py`: lays the map and the nameplate together under one light, a mock-up
  of the capsule (owner: the light has to read across the map as well as the plate). With
  `--mirror` the map is flipped left to right, so its golden light, which comes off the sea,
  comes from the left, as the nameplate's does with `--light topleft`. The light stands off
  the frame's top-left corner: the navy backdrop is lit warm there and falls to dark at the
  bottom right, the map and the plate each cast a soft shadow down and to the right onto it,
  and the map carries a gentle wash of the same light. The plate stands at `--plate-at`: the
  top-left corner (`tl`, the default; owner: the honeycomb plate goes top left or on the
  left), the middle of the left side (`l`) or the bottom-right corner (`br`). It is made as
  large as it can be there without coming near the map (`--plate-h` fixes its size instead).
  `--map-width` scales the map to that share of the frame's width and sets it in the
  bottom-right corner (owner: the map takes two thirds of the composition, `0.667`).
- `nameplate_finish.py`: lays a nameplate render on the capsule's navy with the soft shadow
  it casts away from its light and a glow round its fire (`_on_navy.png`).
- `icon_key.py`: keys the game's building icons (`assets/icons/buildings/cleaned/`) to a
  single colour, dropping the opaque edge pixels that still carry the navy they were cut
  from, and traces them (marching squares at three times their size, smoothed and thinned)
  into `icons/<name>.json`, holes included, for `nameplate.py` to raise. The keyed icons are
  `icons/<name>_keyed.png`. Run it again if the game's icons change.

## Run

From the repo root (Blender must run in background mode; the agent shim adds it):

```
~/.agent-shims/blender --factory-startup --python-exit-code 1 \
    --python tools/steam_capsule/render_earth_plate.py -- \
    --out tools/steam_capsule/renders/earth_plate_v1.png --res 1536x1024 --no-render --no-trees
python3 tools/steam_capsule/check_layout.py tools/steam_capsule/renders/earth_plate_v1.png
python3 tools/steam_capsule/place_trees.py tools/steam_capsule/renders/earth_plate_v1.png
~/.agent-shims/blender --factory-startup --python-exit-code 1 \
    --python tools/steam_capsule/render_earth_plate.py -- \
    --out tools/steam_capsule/renders/earth_plate_v1.png --res 3072x2048 \
    --save tools/steam_capsule/capsule.blend
python3 tools/steam_capsule/finish_render.py tools/steam_capsule/renders/earth_plate_v1.png --shadows
python3 tools/steam_capsule/measure_render.py tools/steam_capsule/renders/earth_plate_v1.png
```

For a warmer look, render to its own file with `--look golden` (or `dusk`) and print it
the same way.

The nameplate (under a minute on the GPU; `--plate`, `--carbon` and `--light` as above),
and the mock-up with the map (the golden look's `_print.png`):

```
~/.agent-shims/blender --factory-startup --python-exit-code 1 \
    --python tools/steam_capsule/nameplate.py -- \
    --out "$PWD/tools/steam_capsule/renders/nameplate_v1.png" --light topleft \
    --samples 160 --save "$PWD/tools/steam_capsule/nameplate_coals.blend"
python3 tools/steam_capsule/nameplate_finish.py tools/steam_capsule/renders/nameplate_v1.png
python3 tools/steam_capsule/compose_capsule.py tools/steam_capsule/renders/earth_plate_v1_golden_print.png \
    tools/steam_capsule/renders/nameplate_v1.png tools/steam_capsule/renders/mock_v1.png \
    --mirror --map-width 0.667 --plate-at tl
```

Give `--out` and `--save` absolute paths: Blender resolves a relative render path against
its own start folder, not the shell's.

The first pass builds the layout only; the trees are placed from it, then the full render
takes a few seconds. `--no-blockout` renders the plate alone, which is how the top colours
are measured: the buildings stand on the probe points. 3072x2048 is the review size; the
game buildings' detail wants the pixels.

## Colour

All the top colours come from the shipped midcentury map style
(`map_midcentury_style.gd`):

| Area   | Source            | Target    | Renders   |
|--------|-------------------|-----------|-----------|
| Ground | `BAND_COLORS[2]`  | `#9aa465` | `#9aa365` |
| Sand   | `BAND_COLORS[1]`  | `#ddd0a6` | `#dbd0ad` |
| Shelf  | `SEA_COLORS[4]`   | `#6b8fb5` | `#6b8fb5` |
| Sea    | `SEA_COLORS[3]`   | `#4f6f99` | `#4f6f99` |
| River  | `WATER`           | `#5b86b5` | `#5d86b5` |

Kit tones are tuned to the rig's AgX view transform, so a flat colour can't be converted
straight to an albedo. Each one is calibrated by rendering instead. The pale sand sits
at the top of AgX's range: a base colour of 1.0 still renders `#cac7a8`, so its albedo
goes above 1.

The stipple reads shade, not colour, so the deep sea no longer draws dots for being dark.
`finish_render.py` still restores every water surface from the water mask, so water stays
the flat map colour, cast shadows included.

The top colours were calibrated under the sprite rig's light. The capsule's sun over the sea
at 2.45 against a white world at 0.62 moves them by under 1 ΔE (measured), so the table stands.

## Camera

The sprite rig's 45-degree yaw, orthographic, at 30 degrees above the ground
(`--elevation`; true isometric is 35.3). The hex grid turns 12 degrees under the camera
(`PLATE_YAW`), so the buildings keep the sprite rig's view while the plate matches the
concept.

## Matching the AI concept

`renders/compare_ai_v9.png` sets the concept beside the plate.

- **The concept is not one camera.** Its buildings are drawn from about 21 degrees: the
  cooling-tower rim is an ellipse about 0.38 as tall as it is wide, and the EV plant's
  rectangular roof resolves to 20.5. Its slab reads from higher: on screen its top is
  about 0.61 as deep as it is wide, and its walls average about 0.20 of that depth. One
  3D scene can only have one angle. 30 degrees reproduces the slab, which is what reads
  as the view, and puts the buildings a little more top-down than the concept draws them
  (closer to the game's own 35-degree sprites).
- **Shape.** The concept's slab outline, projected back onto the ground at 30 degrees and
  covered by hexes sized so the walls match its average wall height, is best fitted by 13
  cells with the grid turned 12 degrees (85% overlap). That's a compact, chunky slab.
  Its W walls face away from this view and read as steps between the SW walls, which
  gives the concept's stepped front-left side. The nearest corner sits about two thirds
  across. A flat-top turn of 30 degrees fits no better, so the hexes stay pointy-top.
- **Water.** The concept's water falls on four of those cells, from about 2,600 down to
  1,100 water pixels each, before dropping to 440 for the river. It's a bay at the back
  right, not a headland. The bay is open to the east and to the back corner, where the
  concept has its islets, with the harbour shore on the west and a strip of land in
  front. A river cuts in from the west under the rail bridge; the plate doesn't carry it
  yet.

## Rig

Factory startup differs from the master sprite .blend in two ways that matter, and the
render script corrects both. Its `Light` is a point lamp, and `setup_rig()` sets the
energy but not the type, so every face would sit at ambient; it becomes a sun. It also
carries Blender's default Freestyle lineset, which draws pure black over the rig's navy
ink; only the rig's `ink`, `ink_fine` and `contour` linesets are kept. The colour
settings read from the master file are restated too (AgX, look None, exposure 0,
32 TAA samples).
