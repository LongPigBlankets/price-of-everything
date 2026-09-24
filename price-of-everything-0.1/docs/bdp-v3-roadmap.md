# Building Detail v3: the rest of the panel, and one standard for wear

This is the plan for bringing the rest of the building detail panel over to v3, and for making the grunge, wear and cuts on every plate and metal surface follow one standard. How the parts built so far are made is in `bdp-v3-control-plates.md`.

## Where v3 stands

**Done:**

- the backing and brass trim
- the raised title, the Close and Location keys, the status lamp
- the seam's non-slip edge
- the recipe diagram's enamel sign and its arrow
- the four-key block
- the steel section frames
- the guarded Sell / Demolish footer
- the scrollbar
- the lamp over the panel
- the section headings in raised lettering, as INPUTS and OUTPUTS
- the diagnostics in a dark plastic case with silver screws, each check a raised module fed off the cable, a Visual / Text switch (Text by default; Visual shows the stage columns of checks)
- inbound shipments in a six-good bay, large icons with stock lamps and supply hovers, the rolling door down over the empty rows
- cost to produce on gauges
- Labour and Wages: a factory door per kind of worker with the headcount on its kick plate, and the cost and workers on drum counters
- Modifiers as a white keycap opening a white plastic sheet
- the action sheets' sliding steel plate (their contents are still v2's)

**Still v2 inside the v3 panel.** The panel file still makes 25 plain `Button`s, and every card inside the frames is a flat design-system card.

| Where | Element |
| --- | --- |
| Main panel | Diagnostics (coloured squares, row text, the fold button when all is well) |
| | Cost to produce (per output, against its market price) |
| | Modifiers (the accordion's chevron header) |
| | Economics (rows with icons in bordered boxes, the Net row) |
| | Power line |
| | Inbound shipments (cream goods cards with qty pills) |
| | Labour (four tiles) |
| | Section headings (flat cream text) |
| Action sheets | Input sources, output destination (route option cards, "Route details" toggles, destination lists, Go To buttons) |
| | Upgrade (capacity, materials, per turn, Pay / Start / market buttons) |
| | Change recipe (recipe cards) |
| | Sell, Demolish, logistics |
| | Battery source and order |
| Other panel states | NPC-owned (the Owned By card and Buy) |
| | Construction site (materials checklist, countdown, Cancel) |
| | Port rate card; storage card |
| | Infrastructure card and breakdown |
| | Demolition under way (the footer falls back to v2's cancel row) |
| | Upgrading and retooling (only the block's text changes) |

## Principles

- **Build components, not screens.** Most of what is left is made of a few repeated things: a window for readouts, a small lamp, a keycap, a tag for goods, raised lettering. Build each once, then place it everywhere.
- **Nothing is drawn by hand in Godot.** Surfaces, edges, glyphs and wear are rendered in `cluster.html`. Godot stacks, slices and repeats them, and draws only live text and numbers.
- **Readouts stay readable.** Numbers and prose stay live text in the design system's off-white, on dark display windows. The contrast rule in `CLAUDE.md` holds, and the lamp over the panel gives text back half its darkening.
- **Every new part is lit by the house light, on its own seed**, and exported alone (`?export&only=`), so the parts already in the game don't change.
- **v2 stays exactly as it is** until v3 replaces it. Every step sits behind `UiPrefs.use_bdp_v3` and has a test that switching v3 off restores v2.

## Phase 0: the groundwork (before any new part)

1. **Wear kit.** The standard for wear in the second half of this document, built into `cluster.html` as shared functions and material presets.
2. **Re-render the older parts.** Done on 24 September 2026, with the owner's approval. The block, footer, section frames, backing, and the Close / Back / Location keys:
   - moved to the house light;
   - dropped their baked per-part lamp and grade (the overlay supplies the fall-off);
   - take the steel at one scratch scale, with rust flecks by edge length;
   - have their own seeds.

   The backing's brass lost its screws and is welded on. The rest of the wear kit is still to build.
3. **Read layout.json at runtime.** Today most scripts carry the render's numbers as constants copied by hand. Only the title reads `layout.json`. Move the other v3 scripts to a shared reader, so a re-export can't leave a script out of date.
4. **Coverage test.** A test walks the v3 panel for a factory, an NPC building, a construction site, a battery, a port and an infrastructure piece. It counts the plain `Button`s and flat design-system cards left in each. The count only goes down; it is how this plan's progress is tracked.

## Phase 1: the components

Each is a render set in `cluster.html` and a script in `scripts/`. Everything after this phase is assembled from them.

| Component | What it is | Built from | Used by |
| --- | --- | --- | --- |
| **Display window** | A recessed pane of dark glass in a satin steel cut, with a faint glare along its top. Live text sits on it. A 9-slice. | The enamel sign's recess and cut, the kit's glass | Diagnostics, Cost, Economics, Power, Shipments, Labour, every sheet's lists |
| **Indicator lamp** | The status lamp at row size (about 14 px), green / amber / red / off, with its glow. | `pilotLamp` at a smaller bezel | Diagnostics rows, construction checklist, the recipe sheet's current recipe |
| **Keycap, any width** | The block's keycap as a 3-slice, so one render serves every button width, with live text. | `keycap`, `mouldedFrame` | Go To, Pay, Start, Buy, Cancel, battery, route details |
| **Option key** | A square keycap with a raised icon, for choosing among options; the chosen one stays down with its lamp lit. | `keycap`, `iconRelief`, the lamp | Route options in the input / output sheets |
| **Goods tag** | A small enamel tag for a good's icon and quantity, the sign's enamel at tag size. | `enamelPlate` | Shipments, upgrade materials, construction materials, the recipe sheet |
| **Raised lettering** | The title's letter atlas, in the section-heading font and the sheet-title font. | `titleAtlas` at other sizes and fonts | Section headings, sheet titles, the Owned By plaque |
| **Toggle switch** | A bat-handle toggle on a small plate, up or down. | New | Modifiers accordion, the diagnostics fold |
| **Drum counter** | Built: `bdp_v3_counter.gd`. An odometer window; the drums and window are rendered, the digits are live and roll. | `counterHousing` | Labour cost and workers |
| **Gauge** | Built into cost to produce: the existing `panel_gauge`. Its export already looks straight down with the house light's direction; only its light strengths differ from the panel's (key 3.2, fill 0.34, environment 0.32), which the wear kit should bring in line. | `tools/gauge_render` | Cost to produce |

## Phase 2: the main panel

In order of what a player sees most:

1. **Section headings:** done, in raised lettering. **Diagnostics:** modules in a plastic case; the visual view behind the Visual / Text switch is built: five stage columns, inputs on the left, icons over lamps, and a readout at the foot that names the hovered check and keeps in sight.
2. **Economics:** done, value added in production, transport and net value added on LED screens, the value bar and the transport lamps. The power line is left out.
3. **Cost to produce:** done, a gauge per output.
4. **Inbound shipments:** done, a six-good bay with the rolling door over the empty rows.
5. **Labour and Wages:** done, a factory door per kind of worker and the cost and workers on drum counters.
6. **Modifiers:** done, a white keycap and a white plastic sheet.

## Phase 3: the action sheets

A sheet is now a worn steel plate that slides in over the panel's body inside the trim, under the lamp. It keeps its Back key and scrolls on the rail; next it gets a raised title, and its contents move to the components:

- **Input sources / output destination:** the route choices become option keys (the chosen one latched, its lamp lit). "Route details" becomes a small keycap, and the lists become display windows with Go To keycaps.
- **Upgrade:** capacity and per-turn figures in display windows, materials as goods tags, and Pay / Start as keycaps. A step that spends money gets the guarded button.
- **Change recipe:** each recipe is a small enamel sign; the current one carries a lit lamp.
- **Sell / Demolish:** the confirmation steps behind the guarded buttons, in the same plate language.
- **Battery source and order, logistics:** keycaps and display windows.

## Phase 4: the other panel states

- **NPC-owned:** the recipe sign as now, "Owned by …" on an engraved brass plaque in raised lettering, and Buy as a wide keycap.
- **Construction site:** the materials checklist in a display window with indicator lamps, the countdown on drum counters, and Cancel under a guarded cover.
- **Demolition under way:** a v3 footer state with the countdown and a guarded cancel.
- **Port, storage, infrastructure, battery:** each card becomes a display window (the port's rate card may suit a small enamel sign). Their buttons become keycaps.
- **Upgrading and retooling:** the block's keys already carry the text. Add a progress lamp or a small drum.

## Effort and order

Each step is one branch-sized change with its own renders, script, tests and screenshots:

| Phase | Size | Notes |
| --- | --- | --- |
| 0 Groundwork | M | The re-render needs the owner's approval of the new look |
| 1 Components | L | Nine components; the display window and keycap unlock most of the rest |
| 2 Main panel | M | Mostly assembly |
| 3 Sheets | L | The most controls, and the most behaviour to keep |
| 4 Other states | M | Many small cases |

Each step closes with: the tests, the parse check, the coverage count, the screenshot tool (with the unlit capture to check the lighting), and a GPU timing of the panel against the step before.

## One standard for wear

### What differs today

- **Scratch size.** A plate samples the worn-steel texture at `min(texture / plate size, 1.45)` texture pixels per layout pixel, so the size of its scratches depends on the size of the plate. The backing samples it at 0.63, so its scratches are 2.3 times larger than the block's. The section frames and the backing are then stretched as 9-slices, which drags their scratches out along the long edges.
- **Wear density.** Rust flecks are a fixed count per plate (60), whatever its size, so a small plate is rusty and a large one looks clean. The grime along each edge has a fixed strength, whatever the plate.
- **Edges.** Plates have a dark band inside the lip and a broken bright rubbed line. The rail has an unbroken line (so it can stretch). The seam edge and the enamel have neither.
- **Cuts.** Holes and recesses are made four ways: the keycaps' moulded bezel (a dark gap floor), the rail's slot (a dark floor under a bevel), the enamel's recess (a satin chamfer, a cast shadow and painted shade), and the section frame (a raised ring, not a cut at all). Depth, chamfer, floor colour and shading all differ.
- **Sources.** Scratches come from the Sunburst texture on the plates, bezels, backing and brass, from procedural noise on the screws, the lamp's bezel and the rubber's grit, and from procedural brushing on the rail.
- **Where dirt goes.** Plates bake grime round their buttons and icons. The enamel clears its grunge round its icons at runtime. Nothing else follows a rule.
- **Light in the colour.** Plates carry the lamp's grade in their colour, which now doubles the overlay.
- **Seeds.** The older sets share one seed that advances as parts are built, so adding a part changes the ones after it.

### The standard

A single wear kit in `cluster.html` that every part uses, with no one-off numbers.

1. **One scratch scale.** Every surface cut from the worn-steel texture samples it at the same density: 1.45 texture pixels per layout pixel, the block's. It is sampled in the part's own coordinates, with the texture mirrored and repeated past its edge, so a large plate repeats the steel rather than magnifying it. Parts the game stretches are rendered with their long edges tileable, and `bdp_v3_nine.gd` gains a tile mode for them. Only surfaces with a grain along their length (the rail, the seam's rubber) may stretch.
2. **Material presets.** One table, one entry per surface. Each entry names its texture recipe, colour, roughness, bump and reflection strength:

   | Preset | Where |
   | --- | --- |
   | worn steel | plates, frames |
   | navy steel | backing |
   | brass | trim, plaques |
   | gunmetal | bezels |
   | satin steel | every cut's wall |
   | brushed steel | the rail |
   | rubber | seam edge, slider, with its colour as a parameter |
   | enamel | signs, tags |
   | cream plastic | keys |
   | dark glass | display windows |

   Parts name a preset; they never set material numbers themselves.
3. **Wear by area.** One set of wear passes, each with a density per unit of edge or area and one shared set of strengths:
   - edges: dark band and rubbed line, broken where the part won't stretch
   - rust (flecks per 100 px of lip)
   - grime round features (one radius and strength, for screws, keys and raised icons)
   - chips (per corner, for enamel and paint)
   - scratches and specks (per area)
   - aging (yellowing for enamel and plastic)

   A small plate and a large one wear alike.
4. **One way to cut.** `cut(shape, depth)` makes every hole, slot, recess and bezel gap. The wall is the satin preset lit by the house light, it casts its shadow onto the floor, and the floor is shaded in from the edge, deepest under the top and left. There are three depths: a hairline gap (1.6 px, key bezels), a slot (4 px, the rail) and a recess (6 px, the enamel and the display windows). The keycap bezel, the rail slot and the enamel recess are rebuilt with it.
5. **Where dirt goes, one rule.** Grime gathers along the inside edges of cuts, at the foot of anything raised, and in corners. A rubbed bright edge appears only on raised lips facing the light. The enamel's runtime grunge already works this way (it gathers towards the rim and clears round printed content), and the display windows use the same shader.
6. **No light in the colour.** No surface bakes the lamp's grade (`plateMaterial` loses it). Shape light comes from the house light; position light from the overlay.
7. **A seed per set**, for every set, old and new (`withSeed`).
8. **A swatch sheet.** A page in the study renders every preset side by side at the same scale, then a crop of every part at game size, so a mismatch shows at a glance. A check measures each preset's scratch density and luminance spread at game size, and fails if two surfaces of the same preset differ by more than a set amount.

### Rolling it out

1. Build the kit and the swatch sheet. Tune the presets on swatches first, not on parts.
2. Rebuild the three cuts (key bezels, rail slot, enamel recess) with `cut`, and check they match.
3. Re-render the older parts with the kit (Phase 0, step 2) and put them to the owner as one before / after set.
4. From then on, new parts only through the kit. A part that needs something new adds it to the kit.

## Decisions for the owner

Decided on 24 September 2026:

- The older parts are re-rendered (done).
- Cost to produce: a gauge per output (done).
- Diagnostics keep their layout for now, on the steel, with a black cable with a yellow stripe down beside the lights (done).
- Labour: drum counters for the labour cost and the number of workers only, and clear labels on the metal (done).
- The action sheets become slide-in steel plates (done: the plate and the slide; their contents are still v2's).
- Every change is compared against the standard (`artifacts/bdp_v3_standard/`, `tools/bdp_v3_compare.py`).

Decided later on 24 September 2026:

- Inbound shipments show no text: large icons fill the bay, which has room for six goods. The door comes down over the empty rows only (two with one or two inputs, one with three or four), never behind a good.
- Labour becomes Labour and Wages, taller, with three factory doors: a small window at the top of each and a metal plate at the bottom with that kind of worker's headcount.
- Section headings are lettered like INPUTS and OUTPUTS.
- The diagnostics case has four screws along the top and the bottom and six down each side; each check is a raised module with the cable feeding into it. "Always shown" becomes a Visual / Text switch, set to Text; it does nothing until the visual view is built.
- Cost gauges 25% larger (160 px), their figures moved right, centred in the room beside the gauge.
- Modifiers become a white keycap with a % sign, opening a white plastic sheet with navy text.
- Cost to produce gets its own dark metal plate with the gauges set into it, and each gauge the good's icon to its left, set below a thin metal frame. Inbound shipments get the same plate and frames, their quantity pills inside the icons.
- Modifiers follow the Inputs row: the % sign raised white on the metal, the text on a raised white keycap that opens the sheet.
- Cost rows: the icon as tall as the gauge, no good name, no percentage; the unit cost on a mini screen in LED segments with a smaller /unit, and "Market price £Y" under it.
- Close and Location are each a line of the title tall.
- The power line is left out; the diagnostics say the same.
- Economics: value added in production and transport costs open to show their parts, each on its own screen; a printed £ before every screen, all one width; revenue (if sold) and costs as two bars; more room for the icons; more space after the modifiers and after the economics.
- Modifiers with none active read None and open nothing; with some, they start open. Transport costs open to Inputs and Outputs, and each to its goods' freight and port charges.
- The revenue bar slices by good, each good's icon on a small rounded tile. Lifting Sell's or Demolish's cover slides up what pressing it would do: the building becomes NPC and what it sells for; the land it frees and its refund as good icons with quantities.
- Labour and Wages' doors are weathered: grime, chips to primer and rust, scuffs, hinges, a door closer, a pressed panel.
- Economics · per turn is rebuilt on accurate figures (`building_economics.gd`, reusing the engine's quoting helpers): Value added in production, Transport costs (by how each side goes, the intermediary's fee where it trades), Net Value Added; a bar of where each £ goes, costs in shades of red and the net value added in green, icons over the slices; a lamp with its icon for each side's transport; "Inputs free" and "Output free to ship" flags; no section for a building with neither inputs nor outputs.

Still open:

- The diagnostics' visual view: built and wired. Five stage columns, one 56 px icon wide and five rows tall, a readout that keeps in sight, and 18 checks from `BuildingReadout`: Inputs (source, stock cover, upstream health, deposit left), Inbound (route and mode, warehouse room, transit time, freight cost), Power (supply, intermittency, cable capacity), Plant (carbon levy, works) and Outputs (reach as the cheapest suitable infrastructure, transit time, freight cost, port congestion, sales as unsold stock or glut), each Outputs check, Inputs' Source and Inbound's Route and mode over every good with a lamp per tone. The switch's side is kept in UiPrefs while the game runs; the words were reviewed for brevity and plain punctuation. Thresholds set by the owner: glut 5% / 10% under base, unsold 3 / 6 turns' output, cable and warehouse 90%, port within 10% of its cap.
- How dark the lamp over the panel falls. Since the re-render the lower panel is much lighter than in the standard, whose backing fell nearly to black; the overlay's darkest (0.7 now) sets it.

## Next: the DS2 kit

The look is written up as a design system in `docs/ds2-theme.md`. Its §10 plans moving the generic parts (surfaces, keys, lamps, LED screens, counters, lettering, wells, accordion rows, slide-outs, the lamp overlay and section framing) out of `building_detail_panel_v2.gd` and the `bdp_v3_*` scripts into a `scripts/ds2/` kit, one component at a time, each move checked at 0.0 against the standard before the next. Its §11 is the step-by-step for moving another panel to the look.
