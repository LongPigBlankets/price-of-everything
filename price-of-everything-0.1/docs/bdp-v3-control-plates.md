# Building Detail v3: control plates, frames, screws and buttons

Building Detail v3 dresses the building detail panel as a physical control panel:

- The four main controls (Inputs, Outputs, Upgrade, Change recipes) sit on a worn steel plate as cream keycaps.
- Sell building and Demolish are guarded buttons under hinged clear covers.
- Each section of the panel sits in a steel frame.
- The panel's backing is dark navy-grey steel inside a brass trim.
- The title is set in raised white letters, like the INPUTS / OUTPUTS lettering on the control plate.
- The recipe diagram sits on a cream vitreous enamel sign set into the panel, aged and cracked in the space between its icons.
- The building's status is a pilot lamp, lit green, amber or red, under its name. A Location keycap under Close takes the place of the level and location line.
- The scrollbar is a steel rail screwed to the backing, with a grey rubber grip riding in its slot.
- A lamp at the top-left of the screen lights the whole panel, so it falls away evenly from top-left to bottom-right and follows the content as it scrolls.
- A near-black rubber non-slip edge runs across the seam between the fixed header and the scrolling body, which slides out from under it.

It is behind the debug-terminal cheat `toggle bdp v3`. The cheat is off by default, lasts for the session only, and re-renders the open panel. With it off, the panel is v2 exactly.

Nothing here is drawn by hand in Godot. Every plate, frame, screw and button is modelled and lit in a three.js scene, rendered from straight above into transparent layers, and stacked in the game. This document covers how that scene builds each part, how the layers are exported, and how the game uses them.

## Where things live

| Path | Role |
| --- | --- |
| `tools/button_mockup/cluster.html` | The three.js scene. Opened on its own, it is the design study: the current panel beside the v3 block, with clickable buttons. With `?export` it renders the game layers. |
| `tools/button_mockup/cluster_data.js` | Its data: the Godot captures of the panel, the control rects measured in-game, the icons used (from `assets/icons/...`) and the worn-steel texture, all inlined as data URLs. |
| `tools/button_mockup/export.py` | A small server for the export. It serves the page and writes the posted layers into `assets/ui/bdp_v3/`. |
| `tools/button_mockup/index.html`, `panel_data.js` | The earlier whole-panel button study. It is not used by the game. |
| `assets/ui/bdp_v3/` | The rendered layers and `layout.json`. |
| `scripts/bdp_v3_plate.gd` | Base control: stacks a plate's layers, draws key text, handles key presses. |
| `scripts/bdp_v3_block.gd` | The four-control block and its rules (text lines, upgrade detail, better-recipe count). |
| `scripts/bdp_v3_footer.gd` | Sell building and Demolish, guarded. |
| `scripts/bdp_v3_key.gd` | The small Close and Back keycaps. |
| `scripts/bdp_v3_nine.gd` | Draws a rendered plate as a 9-slice (the panel backing; the frames use its `paint()`). |
| `scripts/bdp_v3_section.gd` | A section inside a steel frame. |
| `scripts/bdp_v3_lamp.gd` | The status lamp: picks the lit colour for a status tone and draws its glow. |
| `scripts/bdp_v3_scroll.gd` | The scrollbar's rail and slider, as `StyleBox`es on a `ScrollContainer`'s bar. |
| `scripts/bdp_v3_seam.gd` | The non-slip edge over the seam between the header and the body. |
| `scripts/bdp_v3_title.gd` | The title in raised letters, set from the letter atlas. |
| `scripts/bdp_v3_enamel.gd` | The recipe diagram's enamel sign, and the shader that keeps its grunge clear of the icons. |
| `scripts/bdp_v3_light.gd` | The lamp over the panel: the overlay's shader and the text's and glows' give-back. |
| `tools/bdp_v3_shot.tscn` | Screenshots of the panel in v3 (top, with and without the lamp, lamp states, scrolled, slider tints, a sheet). |
| `scripts/building_detail_panel_v2.gd` | Switches between v2 and v3 (`UiPrefs.use_bdp_v3`), builds the v3 parts and frames the sections. |
| `tests/unit/test_ui.gd` | `_test_bdp_v3_rules` and `_test_bdp_v3_panel`. |

## The stage: camera, light and scale

All parts share one stage, so they read as one piece of hardware.

- **Camera:** orthographic, straight down. Flat layers then stack in 2D without any perspective mismatch.
- **Coordinates:** layout pixels are the Godot capture pixels. The captures were taken at 1.875 times logical size, so a 280 px key is about 149 logical px wide.
- **Light:** every part is lit by the house light (`houseLight`), plus a weak `HemisphereLight` (0.14) and the room environment at 0.16. The house light is a directional light from the upper left, 49.7° above the panel, strength 4, with no fall-off. It is the knob and gauge renderers' key light, and the angle the raised icons' painted shadows assume (0.6 × height along each axis).
  - A part lit by it looks the same wherever it sits and at any size, so renders can be stretched and repeated, and the parts all agree.
  - It shades the parts' shape only. How bright each place on the panel is comes from the game's lamp over the panel (see below), so no part carries a light of its own in its colour.
  - `stage(..., { light: 'lamp' })` still gives the old per-part spotlight (above and beyond the frame's top-left corner), but no set uses it. Every part used it until the re-render of 24 September 2026, when each part graded itself from bright at its own top-left to dark at its own bottom-right.
- **Export scale:** every layer is rendered at `E = 2 / 1.875` times layout size, which is **2 texture pixels per logical pixel**. Godot draws them at half their pixel size, so all bdp_v3 textures import **with mipmaps**.

## Materials

| Material | How it is made |
| --- | --- |
| Worn steel (plates, frames) | The Sunburst worn-steel texture (`cluster_data.js` → `plateTexture`), brightened, flattened and mostly blended with a blurred copy, so fine scratches recede and relief reads on top (`STEEL_CANVAS`). |
| Navy-grey steel (panel backing) | The same texture heavily blurred, only 20% of the sharp scratches kept, greyscaled and multiplied by `#767D88` (`NAVY_STEEL_CANVAS`). |
| Brass (trim) | The same texture blurred, brightened and multiplied by `#ECC47A` (`BRASS_TRIM_CANVAS`). |
| Gunmetal (button bezels) | The raw Sunburst texture on a dark metal material (`MAT.frame`). |
| Cream plastic (keycaps, raised icons) | `#E9DFCA`, the approved keycap reference's cream, roughness 0.62 with a light clear coat. Key tops get faint wear and grime towards their corners (`paintPlastic`). |
| Navy text | `#0B2340`, Barlow Condensed Bold / SemiBold. |

Every plate takes the steel texture at the same scale, 1.45 texture pixels per layout pixel (`STEEL_SCALE`), so its scratches are the same size on every part. A plate larger than the texture at that scale repeats it, mirrored (`steelWindow`); the backing and its trim do. Before the re-render a plate took the texture at whatever scale fitted it, so the backing's scratches were 2.3 times the block's.

The Sunburst texture was generated once for this work, from a brief asking for a flat, evenly lit, edge-to-edge worn steel surface. The brief and the original image are in Project Rebirth's `.asset-image/factory-buttons/`, which is not tracked in git. The texture itself is kept in `cluster_data.js`.

## Plates

A plate is a rounded rectangle extruded 4 px with a 4.5 px bevel (3.6 px flare, 6 segments). This gives it a rounded, rubbed lip; its face is `PLATE_TOP` = 13 px above the ground. `plateMaterial(w, h, feat)` paints four maps onto the face:

- **Colour:**
  - a window of the steel texture, at the one scale;
  - grime settling into the edges, heaviest along the bottom;
  - soft grime round every button (`feat.buttons`) and screw (`feat.screws`);
  - the swept shadows of the raised icons (see Buttons);
  - screwdriver-slip arcs round each screw;
  - the rubbed edge: a dark band just inside the lip, then a broken bright line along it, strongest on the top and left where the light catches it;
  - flecks along the lip, 2.45 per 100 px of edge (`FLECKS_PER_100PX`), so a small plate and a large one wear alike: rust on steel, tarnish on the brass (`feat.flecks`);
  - anything `feat.paint(g, w, h)` adds last (the weld's heat tint).
- **Roughness:** from the texture's brightness. Bright scratches are smoother and dark grime is duller.
- **Bump:** a high-pass of the texture, so only the larger scratches catch the light.
- **Options:** `feat.base` swaps the texture (the backing uses the navy-grey steel and the trim uses brass), and `feat.rub` sets the rubbed-edge colour.

Plates that carry keycaps also carry the keycaps' cast shadows. The plate layer is rendered with the keycaps present but not drawn (`colorWrite` off), so they cast into the plate without appearing in it.

## Screws

`screw(r)`:

- the head is a half-sphere of radius `r`, squashed to 0.42 of its height, in dull steel;
- the slot is a thin dark box, 1.75 r long, at a random angle.

Sizes and placement:

- **Plates:** radius 10, 32 px in from each corner (`SCREW_INSET`), clear of the rounded corner and the rubbed lip.
- **Section frames:** radius 6.5, in the middle of the rim.
- **Backing:** none; the brass trim is welded on.
- **Diagnostics' plastic plate:** silver cross-head screws, set by the game along its top and down its sides.

The plate paints grime round each screw and a few bright screwdriver slips. The block's plate runs 24 px further down than its buttons (`PLATE_FOOT`) so its bottom screws clear the lower keys.

## Frames

- **Button bezels:** `mouldedFrame(w, h, r)` is a thin gunmetal ring that follows a button's outline: a 1.6 px gap, a 5 px rim, 6 px high, with a dark floor in the gap. Every keycap and guarded button sits in one, so the metal is moulded to the button's shape.
- **Section frames:** a 26 px steel rim (the plate material on a ring with a rounded hole), a screw in each corner set on the rim's centre line, in from its rounded corner as it would be driven, and the rim's cast shadow, in a 596 × 396 px render with 18 px of shadow room round it.
  - The game draws it as a 9-slice, which keeps the corners and screws at their size and stretches the edges (`bdp_v3_section.gd`).
  - A section's heading and content go inside, 8 px in from the rim.
- **Backing trim:** a 14 px raised brass ring round the navy-grey backing plate (narrow, so it stays clear of the scrollbar), welded to it. There are no screws. A bronze weld bead runs in the join at the trim's foot (`weldBead`), a rounded ridge rippled every 2.6 px as a bead laid in runs is, and heat tint colours both metals beside it: straw, brown, purple and blue fading into the steel, and a darkening into the brass. It is drawn as a 9-slice (`bdp_v3_nine.gd`, 64-texel corners), behind the whole panel.

## Buttons

### Keycaps (the four white buttons, Close, Back)

- **Shape:** `keycap(w, h, r, paint)` is a flat top face on a straight chamfered skirt. The skirt drops 14 px and flares 9 px with one bevel segment, so the chamfer is a single flat slope. The light shades it as a whole: bright on the top and left, shaded on the right and bottom, like the approved keycap reference.
- **Frame:** the key sits in a moulded bezel.
- **Face:** `paint` draws on the top face. In the export the faces are blank, because the game draws the text live.
- **Pressed state:** the cap lowered 5 px.
- **The four main keys:** 280 px wide (`BW`). Inputs and Outputs are 104 px tall. Upgrade and Change recipes are two lines tall; their row grows by 70 px (`EXTRA`).
- **Close, Location and Back:** small square keys, `SMALL_KEY` (76 px, bezel and all) in a 108 px frame for their shadow. The header draws Close and Location each a line of the title tall (`BdpV3Title.line_height()`), Close beside the first line and Location beside the second (`line_pitch()` apart); the header keeps the width it always had for them. Back in the action sheets keeps its old size (`BdpV3Key.DEFAULT_KEY_PX`).

### Raised icons and lettering

`relief(w, h, draw, mat, { height, soften })` raises a white-on-black mask as a real height field:

- a fine grid at 2 vertices per pixel, lifted by a slightly blurred copy of the mask, so every edge gets a sloped flank;
- cut away outside the mask;
- its face grades from light top-left to deeper bottom-right (`FACE_GRADE`), as on the bottom-bar icons.

The icons come from the game's own art:

| Icon | Source | Relief height |
| --- | --- | --- |
| Wheelbarrow | `ui_icons/construction_materials.png` | 10 |
| Output gear | `research/glyph/output.png` | 10 |
| Recipe | `research/glyph/merge.png`, turned 90° as the research panel does | 11 |
| Lorry | `research/glyph/lorry.png` | 6 |
| INPUTS / OUTPUTS, Sell building / Demolish | lettering | 5 |

Each raised part's shadow is baked into the plate by `drawIconShadows`, not taken from the lamp, because the metal is lit mostly by reflection:

- **Swept shadow:** the outline stacked from 0 to 0.6 × height pixels towards the bottom-right, darkest against the shape, then softened. It starts at the icon's foot and joins every edge facing away from the light, so the icon looks fixed to the plate rather than floating. It also falls into cut-outs from their top-left edges.
- **Contact line:** a thin dark line all round seats the relief in the steel.

### The upgrade arrow

The arrow is a chiselled solid, built by hand in `chiselArrow`.

- **Shape:** the base is the game arrow's outline (`research/glyph/arrow_up.png`, with its rounded foot cut flat). The top is the same arrow inset by an even bevel, every edge parallel with mitred corners, joined by a short wall and flat facets. three.js's own extrude bevel offsets corners by a fixed diagonal and skews the tip and shoulders, which is why it isn't used here.
- **Unlit** (the upgrade's research not met): cream, embossed like the other icons.
- **Lit:** light green (`#9CF2B8`), glowing, with no shadow. The glow is a separate additive layer.

### Guarded buttons (Sell building, Demolish)

`guardButton(S, icon, colour)`:

- **Cap:** a frosted plastic cap lit from behind, with a radial glow in the button's colour and the icon as a dark silhouette. Sell is amber `#FFA412` with the game's money glyph; Demolish is red `#E8281E` with a bulldozer glyph drawn in the same style (`BULLDOZER` in `cluster.html`; the game has no bulldozer icon). It sits in a moulded bezel.
- **Cover:** a hinged clear cover: a thin clear lid (8% opacity), a rolled front lip and side cheeks, a steel hinge barrel along the top, a steel latch tab, and a printed glare.
- **Open state:** the cover swings 125° open (`COVER_OPEN`), so a lifted cover stands up over the plate's top edge. The footer's render reaches 64 px above the plate (`HEAD`) to hold it.
- **Labels:** each button's name is raised white lettering on the steel beside it.

## The status lamp

`pilotLamp(colour, lit)` is a panel pilot lamp standing on the backing:

- **Bezel:** a turned steel ring (`LatheGeometry`) rising from a thin flange to a rolled lip, 44 px across (`LAMP_R` 22).
- **Gasket:** a dark ring between the lip and the lens.
- **Lens:** a faceted jewel dome (12 × 4 flat-shaded facets, so each facet catches the light). Lit, it glows from a pale middle to its colour (`lensMaterial`); off, it is dark tinted glass.
- **Colours** (`LAMP`): green `#4FDC86`; amber `#FFA412` and red `#E8281E`, the Sell and Demolish caps' colours.
- **Glow:** a radial layer in the lamp's colour, drawn additively.

Each state renders in a 112 px frame with the lamp in the middle and its shadow on the backing. In the game (`bdp_v3_lamp.gd`) the tone picks the colour: `ok` is green, `warn` amber, `bad` red, and any other tone (NPC-owned, for one) leaves the lamp off. The panel shows the lamp and the status in capitals (Barlow Condensed SemiBold 18, off-white) in place of v2's badge.

## The scrollbar

- **Rail** (`scrollRail`): a steel strip 22 px wide in a 30 × 240 frame, screwed to the backing at both ends, with an 8 px slot down its middle over a dark floor. The steel is brushed along the strip's length (`railMaterial`): each column is one shade, and the rubbed edge is an unbroken line.
- **Slider** (`scrollThumb`): a medium-dark grey rubber grip (`#55595F`, with a soft sheen) 16 px wide on a chamfered edge, in a 30 × 210 frame, standing on the rail, with its shadow on the rail. Diagonal ridges 1.4 px high are moulded across it every 7.5 px between plain rounded ends.

`bdp_v3_scroll.gd` draws each in three pieces: the ends keep their size (30 px of rail, 15 px of slider) and the length between them is filled. The rail's is stretched, which its steel allows, being brushed along its length. The slider's diagonal ridges would change angle if stretched, so its length is filled with whole periods of them, taken from the middle of the grip where every period has ridges on both sides, each squeezed or eased a little so a whole number fits. It draws the pieces itself, because Godot's `StyleBoxTexture` draws one texture pixel per screen pixel and these renders are at two per logical pixel.

`BdpV3Scroll.apply(scroll, on)` puts the rail and slider on a `ScrollContainer`'s vertical bar (`scroll`, `scroll_focus`, `grabber`, `grabber_highlight`, `grabber_pressed`), so scrolling, dragging and paging stay Godot's own. The bar is 16 px wide. The slider stops 12 px short of the rail's ends, clear of the screws. Under the pointer it is drawn 7% brighter, and 7% darker while held.

## The seam edge

`seamStrip()` is a near-black rubber edge like the nosing on a stair tread, run across the panel where the scrolling body meets the fixed header:

- **Strip:** a cross-section extruded along the panel's length: a back edge on the backing, a corrugated tread with three rounded ridges along its length between valleys 3.2 px deep, 6 px apart, and a lip that the last ridge rolls down into, over the body. Each crest catches the light. The rubber is near-black (`#131416`), with a soft sheen on the crests and a fine grit in its surface. It has no screws.
- **Shade:** the strip casts its shadow onto the body, and `paintSeamShade` darkens the body a little way out from under the lip, as if it slid out from beneath it.

It renders in a 900 × 48 frame: the strip from y 6 (its back edge) to 26 (its lip), and the shade below it to the frame's foot. In the game, `bdp_v3_seam.gd` draws it as a horizontal three-slice. The 45 px ends keep their size, and the length between them fits the panel. The render is wider than the panel, so the middle is squeezed a little rather than stretched. The strip reaches out to the backing's trim at both sides and down over the top of the body.

The panel puts the scroll area in a plain `Control` (`BodyWell`) with the edge added after it, so the edge draws over the body without a `z_index` and the action sheets still cover it. With v3 on, the body starts at the edge's lip (`_scroll.offset_top`).

## The recipe diagram

The diagram of the building's recipe sits on a vitreous enamel sign set into the panel (`enamelPlate`):

- **Recess:** the sign is sunk below the backing's surface. The cut is a satin steel chamfer, dark along the top and left where it faces away from the light and lit along the bottom and right, and it throws its shadow onto the enamel. The backing's own surface round the cut isn't drawn (it is in the render only to cast that shadow), so the game's backing meets the cut. The render is 760 × 300 with the cut 3 px in from its edge; the game lines the cut up with the diagram's rect.
- **Enamel:** a thin cream rim (shaded in from the cut, deepest under the top and left), a 7 px navy band (`#0A2140`), a cream gap and a 2 px navy pinstripe (the diagram's old outline), and the diagram's cream field (`#FEEDC3`) under a clear glaze with a soft sheen from the top-left.
- **Chips:** one to three at each corner, showing dark steel under the enamel with rust round them and the enamel's pale broken edge.
- **Grunge** (`recipeGrunge`, its own 900 × 450 layer): uneven yellowing of the glaze, grime blotches, dust specks, hairline crazing, a few scuffs, and two cracks running in from the field's top edge, one near the left and one about half way across where the diagram has no icons. Each crack is a jagged dark line with the enamel's broken edge lit beside it, a branch, and a small flake lost where it starts. Everything is darker or warmer than the cream; a light mark on light enamel reads as a smudge.

In the game, `bdp_v3_enamel.gd` draws the sign as a 9-slice with 44 px corners. Everything between the corners (cut, rim, band, pinstripe, field and sheen) is smooth, so it can stretch; all the wear is in the corners. It lays the grunge over the field through a small shader:

- The grunge is anchored at the field's top-left, at two texture pixels per logical pixel, so it isn't stretched. It repeats if a field is ever larger than the layer.
- It is fully clear within 6 px of every goods icon and the arrow and fades back in over the next 10 px. The panel hands the sign those controls (`watch`), and the sign re-reads where they are each frame while it is visible, passing them to the shader only when they move.
- It thickens towards the band.

In v3 the diagram's flat cream background and inset outline give way to the sign.

The arrow between the inputs and the output is shared with v2. Its head is 35 × 58 px, flares past the body and has smoothed edges (a thin antialiased line traced round the filled triangle). The body has square corners and is 41 px tall, with side padding that makes it 10% narrower than it was round the same number and bolt.

## The title

The title has the effects of the INPUTS / OUTPUTS lettering on the control plate:

- **Letters:** raised in the plate lettering's white (`#F4F2EC`, roughness 0.45, a light clear coat), 5 px high on a flank softened by 0.7 px (`relief`).
- **Shadow:** the same swept shadow and contact line, painted by `drawIconShadows`.
- **Faces:** graded from white at the top-left to `#B8B0A0` at the bottom-right, across the whole title, as the plate's lettering is graded across its word.

The font stays the title's own: Bebas Neue at 32 px (60 layout px). Titles change with the building, so each letter is rendered on its own into an atlas (`titleAtlas`, `title_glyphs` and `title_glyph_shadows`, 1400 × 184). Each letter sits in a cell with 10 px of room round it for its shadow, and every cell has the same baseline. `layout.json` lists each cell as `[x, y, w, h, pen x]`. The page loads the game's copy of the font from `export.py`, so the letters match the game's spacing. `relief(..., { faceGrade: false })` leaves the faces ungraded in the atlas.

In the game, `bdp_v3_title.gd` shapes and wraps the title with Godot's text server in the same font, size and wrapping as the plain label, and places each letter's render on its pen position. It draws every shadow first, then the faces, each shaded for where its middle falls in the block of lines. The atlas covers A–Z, 0–9 and common punctuation, which is every character in the building and recipe names (a test checks this). A title with any other character keeps the plain label.

## Power

v3 leaves out v2's power line ("Draws X MW · ready to draw from the grid"): the diagnostics say the same.

## Economics · per turn

The figures come from `scripts/building_economics.gd` (`per_turn`), which quotes them with the engine's own helpers, the ones the turn's cash moves by, without booking anything: `TransportService.quote_market_buy` for bought inputs (goods at the buy price, inland freight and the port charge), `MarketState.sale_charges` for output sold straight to market, `Production.stock_sale_charges` for output sold from a stockpile, `TransportService.land_cost_after_credit` for output sent to another of the company's tiles, the logistics intermediary's quote where it trades a good, `Power.allocated_draw_cost` for power, and the engine's labour, maintenance, storage-share and carbon-levy helpers. Output that stays in stock is valued as if sold, with what shipping it to market would cost ("Output (if sold)"). Inputs the company makes itself and routes here are valued at what they would sell for and arrive with no transport cost here: freight between its own tiles is the sender's, as the engine charges it. Measured against a single motor factory's real cash over ten turns (`tools/recipe_profitability_case.gd --panel`), net value added came within £0.43 a turn beside the port (+£49.82 against +£49.39 before tax) and £0.02 inland (+£5.18 against +£5.20), where the old Net read +£52.96 and +£35.94.

The section shows three rows, each figure on a mini screen in LED segments (`bdp_v3_led.gd`) after a printed £, as the cost to produce shows its prices. Results are green, or red below zero; costs are red. Every screen in the section shows as many digits as the widest figure, the rest blank (their segments unlit), so the screens are one width and their £ signs line up:

- **Value added in production:** the output's value less inputs, labour and upkeep (maintenance, power, storage and the carbon levy). It opens (a chevron, a click on the row) to show each of them on its own screen: Output (or Output (if sold)), Inputs (left out when they come free), Labour and Upkeep.
- **Transport costs:** bringing the inputs in and taking the output to market. It opens to show each side's cost by how it goes: Inputs · Road, Inputs · Port, Outputs · Rail, and so on, or the logistics intermediary.
- **Net Value Added:** the first less the second, before tax.

Which rows are open is kept while the panel rebuilds. Under them, the revenue and the costs as two bars on one scale (`bdp_v3_value_bar.gd`), each on a mini screen with its name printed beside it, so the gap between their ends is what the building adds. The revenue bar ("Revenue if sold" while the output stays in stock) has a slice for each output in shades of green, the good's own icon over it (the coins for a power plant's power); the cost bar has inputs, labour, upkeep and transport in shades of red, each with its raised icon (`econ_icon_<name>`: the INPUTS wheelbarrow, the engineer, gears, the lorry). A faint dashed mark on the cost bar shows where the revenue ends. Icons that crowd spread apart; a short line joins each icon to its slice. Hovering a slice names it with its £ and its share of the revenue. The money frame leaves a gap after the modifiers and after the economics.

Then a lamp for each side's transport, with that side's icon (the plate's INPUTS and OUTPUTS icons): green while transport costs under 3% of the goods' value on that side, amber under 8%, red above (`BuildingEconomics.transport_tone`). A side that travels free is flagged and its lamp is off: "Inputs free" for a recipe with no inputs (mines, wind and solar, air separation), "Output free to ship" for output with no transport cost (a power plant's, which leaves by cable). A building with neither inputs nor outputs (a battery) shows no Economics section. The loan repayment and stored-goods rows follow, as in v2.

## Section headings

Every section heading (Diagnostics, Cost to produce, Economics · per turn, Inbound shipments, Labour and Wages, and the rest) is lettered as INPUTS and OUTPUTS are on the control plate: IBM Plex Sans Bold at 28 layout px, raised in the plate lettering's white, 5 px high on a flank softened by 0.7 px, with the same swept shadow and contact line, the faces graded from white at the top-left to `#B8B0A0` across the heading. The letters are rendered one per cell into an atlas like the title's (`headingAtlas`, `heading_glyphs` and `heading_glyph_shadows`, 900 × 159, 8 px of room round each letter); `layout.json` lists each cell as `[x, y, w, h, pen x, advance]`, with a space's advance, and `bdp_v3_heading.gd` sets the letters along one line by those advances. The game has no Plex Bold, so the heading is set by the page's measurements rather than by Godot's text server. The atlas holds the title's characters and the middle dot; a heading with any other character keeps the plain label.

## Diagnostics

In v3 the diagnostics section is a moulded dark plastic case (`plasticPlate`, `diag_plastic`, a 9-slice) instead of a steel frame, with silver cross-head screws (`screw_silver`) round its edge, 9 px in: four along the top and four along the bottom, corner to corner, and six down each side, counting the corners (`bdp_v3_section.gd`, `style = "plastic"`, `screw_points`). The heading has a Visual / Text slide switch beside it (`toggleSlot`, `toggleKnob`, `bdp_v3_toggle.gd`): a slot moulded into the case and an off-white ridged thumb that slides across when clicked. It is set to Text and keeps its side while the game runs; the visual view is not built yet, so it changes nothing.

Each check is its own module (`diagModule`, `diag_module`, a 9-slice): a slightly raised black plastic panel a shade lighter than the case, with a rounded glossy edge and its shadow on the case, 8 px apart. A module is led by a lamp like the status lamp, at 72% of its size, lit for the row's tone; a row about a good shows the good's icon beside its lamp. When every check is fine the list folds to one "All green" module with a green lamp, which opens the rest. All the section's text is white with a dark shadow down and to the right, so it stands off the plastic.

A cable runs down the case's left side (`cableRun`, `bdp_v3_cable.gd`): black rubber insulation with a yellow tracer stripe, near-black with one crisp glossy highlight along its top so it reads as round, between a steel cable gland at each end, drawn as a vertical three-slice. Each module takes its feed from it (`cableTap`, `diag_tap`): a moulded junction box clamped over the cable, a short branch of the same cable, and a steel gland where it enters the module's end, at the height of the module's middle. The branch sets the modules' left margin (`BdpV3Cable.TAP_LENGTH` to the right of the cable).

## Cost to produce

The section has its own dark metal plate (`darkPlate`, `dark_plate`, `bdp_v3_section.gd` `style = "dark"`): the backing's steel taken down to a blackened gunmetal, filling the frame's inside with its edges under the rim. The render is one large plain face (900 × 1400) that the game crops from its middle rather than stretching, so its scratches are the size of every other plate's; its steel is blurred from a mirror-padded copy so the mirrored repeat shows no seam. Each output's cost is on a gauge (`scripts/panel_gauge.gd`, 160 px) set into the plate: the card draws the hole cut for it underneath (`gaugeSocket`, `gauge_socket`), a chamfered cut a little wider than the bezel over a dark cavity, so a thin gap shows round the gauge. To the gauge's left is the good's icon, as tall as the gauge's bezel frame and all, set below a thin metal frame (`iconWell`, `icon_well`, a 9-slice drawn over the icon and under any quantity pill): a narrow ring of the keycaps' bezel metal, its shadow on the plate outside, and inside its shadow and a soft shade along the opening, deepest at the top-left, falling onto the icon. The icon's tile takes the opening's corner radius. The row holds only the gauge's bezel and its shadow; the render's empty room round the bezel overhangs its holder.

To the right, the unit cost on a mini screen in LED segments as on a digital clock (`miniScreen`, `mini_screen` and `mini_screen_glass`, `bdp_v3_led.gd`): a gunmetal bezel round a recessed pane of dark glass, the digits' seven segments and point lit in the cost's RAG colour over the unlit segments, faint, with the glass's shadow and glare over them, between a printed £ and a small /unit. The segments carry their own light, so the lamp over the panel doesn't dim them (`BdpV3Light.emissive_material()`). An unknown cost reads --.--. Under it, "Market price £Y". The good's name and the percentage against the market are left out.

## Modifiers

Modifiers is laid out as Inputs is on the control plate: a % sign raised white on the metal (`drawPercent`, `mod_icon` and its swept shadow `mod_icon_shadow`), and beside it the heading in raised letters over an off-white keycap (`key_modifiers` and `_pressed`, rendered blank and drawn as a horizontal three-slice, `bdp_v3_mod_key.gd`) with the output modifier printed on it (or None) and a chevron at its right end. Pressing the key opens a white plastic sheet under it (`whiteSheet`, `sheet_white`, a 9-slice in the keycaps' plastic) with the same rows as v2 printed in navy; the category figures take darker greens, ambers and reds so they read on white (`V3_INK`). The key latches down while the sheet is open, and the sheet stays open across rebuilds. Modifiers and Economics share one steel frame.

## Labour and Wages

In v3 the section is called Labour and Wages. On the frame's steel, a factory door for each kind of worker (`labourDoor`, `labour_door` and `labour_door_lit`, 200 × 300, drawn 150 px tall by `bdp_v3_labour_door.gd`), its name printed over it in off-white capitals (Unskilled, Skilled, Highly skilled): a painted steel door in a dark steel jamb, a small wired-glass window near its top, a lever handle, and a brushed steel kick plate across its foot. The paint is weathered (`weatheredPaint`): mottled, grime run down from the top, dirt gathered at the foot, greasy round the handle, chipped through to primer and rust along the edges and low down (the chips cut into its bump), scuffed by boots, rust run down from the hinges. It hangs on three barrel hinges with a door closer across its head and a pressed panel below the window; the window's bead is screwed at its corners and its glass is grimy; the kick plate is scuffed and dirty; the jamb is as worn, and the threshold is tread plate. The headcount is engraved on the kick plate in navy (Barlow Condensed Bold, with a light edge below and to the right). The window is lit warm from inside when any of that kind of worker are employed and dark when none are.

Below the doors, the labour cost per turn and the number of workers are on drum counters (`bdp_v3_counter.gd`), each labelled beside it.

A drum counter (`counterHousing`, `paintCounterGlass`) is a gunmetal housing with black drums in a window. The game prints the digits on the drums live (Barlow Condensed SemiBold), then lays `counter_glass` over them: the drums' curve shading away top and bottom, the window lip's shadow and a faint glare. Both renders are horizontal three-slices whose middle cell repeats once per drum. The cost has two drums after a printed decimal point. A counter has as many drums as its value needs (at least four for the cost and three for the workers), and when its value changes it rolls to it like an odometer, each drum turning only while the one below it passes from 9 to 0.

## Inbound shipments

The section is a bay on a dark metal plate, as Cost to produce is, with room for six goods, two to a row, and no text: each good is a large icon (96 px), set below a thin metal frame as the cost icons are, with its lamp beside it. Its quantity pill sits inside the icon's corner rather than overhanging it. The goods fill the bottom row first and the rows above after it. The bay's rolling door (`rollingDoor`, `shipment_door`, drawn by `bdp_v3_door.gd`, a roller housing across the top, corrugated slats painted a dark industrial grey, a bottom bar with a rubber seal, and a steel guide channel down each side) comes down over the rows no good needs: two rows with one or two inputs, the top row with three or four (`v3_door_rows`). With every row in use the door is rolled up, the housing with the door's bottom bar tucked under it. So the bay is the same height whatever the recipe, and the door is never behind a good. The guides, housing and bar keep their size, the width between the guides stretches, and whole slats repeat down to the door's height. Below the door the bay is in its shadow for a little way.

Each good's lamp (`v3_stock_tone`) is:

- green with enough in stock to run;
- amber when short with something on its way: an inbound shipment, or the logistics intermediary;
- red when short with nothing coming.

Hovering the icon shows the good's name, what is stored, what a run needs, how it is supplied, and what is inbound (`v3_input_supply`: the logistics intermediary, the tile's own stockpile, a tile-to-tile transfer, or the global market), and clicking it still opens the encyclopedia. The hover is the shared good hover (`good_icon_hover.gd`) with `detail_lines` under the name.

## Action sheets

An action sheet is a worn steel plate (`sheetPlate`, no screws) that slides in from the right over the panel's body, inside the brass trim, in 0.26 s. A sheet rebuilt in place stays put. The sheet still covers the whole panel and takes its clicks; inside it, a clip the trim's size holds a sliding layer with the plate (a 9-slice) and the sheet's content. The plate sits under the lamp over the panel, and the sheet's text takes back its share of the darkening, like the panel's.

## The lamp over the panel

The panel is lit by a lamp at the top-left of the screen (`bdp_v3_light.gd`). The further a point is from it, the darker, falling evenly from full light a quarter of the screen's diagonal away to 0.7 at 90% of it. The panel usually sits a third of the diagonal or so from the lamp, so it takes a gentle, even fall from its top-left to its bottom-right wherever it is. With the panel beside the tile panel on a 1920-wide screen, that is about 0.97 at its top-left to 0.81 at its bottom-right.

- **One overlay:** a single `Control` over the backing and all of the content, under the action sheets, draws the lamp's light as a multiply (`render_mode blend_mul`). Each pixel works it out from its own place on the screen (`SCREEN_UV`), so scrolled content is lit by where it is now and the whole panel changes as it is dragged, with nothing to update on a scroll. The overlay leaves the panel's rounded corners alone, so the map behind them isn't darkened.
- **Text:** the panel's labels share one material that takes back half of the darkening round them (`TEXT_GIVE_BACK`), without lighting them past their own colour. At the panel's bottom, where the steel and the navy cards fall to 0.84, the text only falls to 0.91. The action sheets sit above the overlay, so their text is left alone.
- **Glows:** the arrow's, the footer's and the status lamp's glows take all of it back, since they give off their own light.

It is one draw for the overlay and one shared material for the text, so the panel draws in as few batches as before. `tools/bdp_v3_shot.tscn` saves the panel with the lamp, without its overlay, and with no lamp at all, so its effect can be measured pixel by pixel.

Since the re-render, no part carries a light of its own, so the overlay's even fall is the only one: down the panel's left edge the steel now holds between 84 and 96, where before the re-render it fell from 119 to 22.

## Checking a change against the standard

The approved look is kept as a standard (tag `bdp-v3-standard-2026-09-24-b`; the first standard, before the re-render and the section work, is `bdp-v3-standard-2026-09-24`): `artifacts/bdp_v3_standard/` holds the views `tools/bdp_v3_shot.tscn` captures of it, and `metrics.json` the measurements taken from them. Every visual change is compared with it:

```sh
BDP_SHOT_DIR=/tmp/bdp_now Godot --path . res://tools/bdp_v3_shot.tscn --quit-after 3600 -- --no-telemetry
python3 tools/bdp_v3_compare.py --current /tmp/bdp_now
```

The shot tool runs the game in a SubViewport of 1920 × 1200 logical pixels at two pixels each, so its captures have the same pixels whatever display the window is on, and two captures of the same panel match exactly. The compare tool reports, view by view, how much of the panel changed and by how much, compares the lamp's light over the panel and the steel's brightness down its edges, and writes standard | current | difference images and a contact sheet. `--save` makes a set of captures the new standard, once a change is approved.

## Exporting the layers

Run from the Godot project root:

```sh
python3 tools/button_mockup/export.py
```

Then open `http://127.0.0.1:8771/cluster.html?export` in a browser. It works headless too:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --use-angle=metal --virtual-time-budget=180000 --dump-dom "http://127.0.0.1:8771/cluster.html?export"
```

The tab title becomes "export done". Every layer of a set shares one frame, so the game stacks them without offsets.

To render some sets only, add `&only=` and a comma-separated list of `block`, `footer`, `backing`, `section`, `keys`, `pin`, `lamp`, `scroll`, `seam`, `title`, `enamel`, `cable`, `counter`, `sheet`, `plastic`, `door`, `heading`, `module`, `toggle`, `ldoor`, `modkey`, `sheetw`, `darkplate`, `modicon`, `screen` and `econ`, for example `cluster.html?export&only=lamp,scroll`. The other layers are left as they are, and the page reads the current `layout.json` from the server and updates only those sets' entries. `export.py` takes an optional port (`python3 tools/button_mockup/export.py 8779`); use a port of your own when another export may be running.

| Set | Layers |
| --- | --- |
| Control block (863 × 379) | `block_plate`; `block_icon_input`, `_output`, `_recipe`; `block_kicker_input`, `_output`; `block_lorry_input`, `_output`; `block_arrow`, `block_arrow_lit`; `block_shadow_<part>` for each raised part; `block_glow_arrow` (additive); `block_key_<inputs, outputs, upgrade, recipe>` and `_pressed` |
| Footer (863 × 214: 150 of plate, 64 of headroom above) | `footer_plate`; `footer_glow` (additive); `guard_<sell, demolish>`, `_pressed`, `_cover`, `_cover_open` |
| Small keys (108 × 108, key in the middle 76) | `key_close`, `key_back`, `key_pin` (its own set, `pin`), and `_pressed` |
| Section frame (596 × 396) | `section_frame` |
| Backing (940 × 1640) | `panel_backing` |
| Status lamp (112 × 112, bezel 44 in the middle) | `lamp_<green, amber, red, off>`; `lamp_glow_<green, amber, red>` (additive) |
| Scrollbar | `scroll_rail` (30 × 240), `scroll_thumb` (30 × 210) |
| Seam edge (900 × 48) | `seam_edge` |
| Title letters (1400 × 184) | `title_glyphs`, `title_glyph_shadows` |
| Recipe diagram | `recipe_enamel` (760 × 300), `recipe_grunge` (900 × 450) |
| Diagnostics' cable | `diag_cable` (32 × 240) |
| Drum counter | `counter_housing`, `counter_glass` (186 × 52: two 18 px ends and five 30 px cells) |
| Action sheets | `sheet_plate` (820 × 1600) |
| Diagnostics' plate | `diag_plastic` (600 × 400), `screw_silver` (30 × 30) |
| Inbound shipments' door | `shipment_door` (760 × 310: 16 px guides, a 44 px housing, 12 px slats, a 26 px bottom bar) |
| Section headings (900 × 159) | `heading_glyphs`, `heading_glyph_shadows` |
| Diagnostics' modules and switch | `diag_module` (600 × 120), `diag_tap` (96 × 44: junction at x 13, the module's end at x 78), `toggle_slot` (96 × 44), `toggle_knob` (44 × 44) |
| Labour and Wages' doors | `labour_door`, `labour_door_lit` (200 × 300) |
| Modifiers | `key_modifiers` and `_pressed` (680 × 120: the key 648 × 88 inside, 64 px ends), `sheet_white` (600 × 400), `mod_icon` and `mod_icon_shadow` (110 × 110, the sign 80 in the middle) |
| Mini screen | `mini_screen`, `mini_screen_glass` (200 × 80: 8 px margin, 7 px bezel, 5 px pane radius) |
| Economics icons (72 × 72, the icon 52 in the middle) | `econ_icon_<inputs, labour, upkeep, transport, value, outputs>` and `_shadow`, raised from the game's icons, which `export.py` serves under `/icons/` |
| Dark plate and set-in parts | `dark_plate` (900 × 1400, cropped, not sliced), `gauge_socket` (240 × 240: a 108 px hole, 6 px chamfer), `icon_well` (240 × 240: 12 px margin, 7 px rim, 10 px inner radius) |

`layout.json` lists each set's size and every key's rect and top face, in layout pixels, plus the lamp's bezel, the scrollbar's end, grip and travel sizes, and the seam edge's ends, back edge and lip. The scripts carry these numbers as constants. After changing a layout, copy the new numbers from `layout.json` into `bdp_v3_block.gd`, `bdp_v3_footer.gd`, `bdp_v3_section.gd`, `bdp_v3_lamp.gd`, `bdp_v3_scroll.gd` or `bdp_v3_seam.gd`.

After an export, reimport with `Godot --headless --path . --import`. A new layer's `.import` gets `mipmaps/generate=true`, then import again. The scene uses a seeded random number generator, but the seed advances as parts are built, so adding a part changes the scratches and wear on the parts built after it. Expect every layer to change slightly on each export. Every set is built with a seed of its own (`withSeed`), so they come out the same whichever sets are exported with them. Put a new set after the existing ones and give it its own seed, so the layers already in the game don't change.

## How the game uses them

- **`bdp_v3_plate.gd`** stacks a set in three canvas items, back to front:
  - plate, shadows and raised icons;
  - the glow, additive;
  - the front layers, the keycaps, and each key's navy text drawn live.

  It scales the frame to the control's width, keeps its aspect ratio, and handles hover, press (it draws the pressed render) and release on a key (`key_pressed`). A frame can reach beyond its control (`set_frame(frame, offset, body)`), which is how the footer's lifted covers draw over the section above.
- **`bdp_v3_block.gd`** configures the block from plain values:
  - the route summaries, with a bracketed qualifier or a second line split onto two lines;
  - whether each side is on the logistics intermediary (lorry, "Manage Logistics");
  - "Upgrade to Lv N" / "+X% Output". The arrow is lit when the upgrade can start: not upgrading, not at the top level, research met. Otherwise its tooltip names the missing research.
  - "Change recipes (N)" / "M better for <good>". M counts the recipes that earn more per turn than the current one by `BuildingReadout.economics`; the good's name is cut to 10 characters plus "...".
- **`bdp_v3_footer.gd`:** the first click lifts a cover, the second presses and emits, and an untouched lifted cover drops after 4 s.
- **Panel:** `building_detail_panel_v2.gd` builds these in place of the v2 controls when `UiPrefs.use_bdp_v3` is on. The keys open the same sheets as v2. It then moves each section's heading and content into a `bdp_v3_section` frame (`V3_FRAMED_SECTIONS`; Modifiers and Economics share one). It shows the backing and hides the brass pipe border, and swaps Close and Back for keycaps. `_apply_v3_chrome` swaps the title label for the raised title (`_apply_v3_title`), the level and location line for the Location key under Close (it pans the map to the building, and its tooltip names the place), the status badge for the lamp, shows the lamp's overlay and gives the text its material, puts the rail and slider on the panel's scrollbar (each action sheet's scrollbar gets them too) and shows the seam edge, starting the body at its lip.

## Adding another control

1. **Model it** in `cluster.html` from the existing parts: `keycap`, `mouldedFrame`, `relief` / `iconRelief`, `screw`, `plateMaterial`, `guardButton`. Place it on the stage above.
2. **Check it in the study** (`cluster.html` without `?export`) before exporting.
3. **Export its layers** in `exportLayers()`. Keep one frame per set; render keycaps blank and draw their text in the game; bake icon shadows into the plate, or export them as `shadow_` layers when the icon can change.
4. **Stack them** with a `bdp_v3_plate.gd` subclass, using the rects from `layout.json`, and wire it into the panel behind `UiPrefs.use_bdp_v3`.
5. **Test it** in `tests/unit/test_ui.gd`.
