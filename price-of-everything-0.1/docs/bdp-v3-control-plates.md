# Building Detail v3: control plates, frames, screws and buttons

Building Detail v3 dresses the building detail panel as a physical control panel:

- The four main controls (Inputs, Outputs, Upgrade, Change recipes) sit on a worn steel plate as cream keycaps.
- Sell building and Demolish are guarded buttons under hinged clear covers.
- Each section of the panel sits in a steel frame.
- The panel's backing is dark navy-grey steel inside a brass trim.
- The title is set in raised white letters, like the INPUTS / OUTPUTS lettering on the control plate.
- The building's status is a pilot lamp, lit green, amber or red, beside its name.
- The scrollbar is a steel rail screwed to the backing, with a cream slider riding in its slot.
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
| `tools/bdp_v3_shot.tscn` | Screenshots of the panel in v3 (top, lamp states, scrolled, slider tints, a sheet). |
| `scripts/building_detail_panel_v2.gd` | Switches between v2 and v3 (`UiPrefs.use_bdp_v3`), builds the v3 parts and frames the sections. |
| `tests/unit/test_ui.gd` | `_test_bdp_v3_rules` and `_test_bdp_v3_panel`. |

## The stage: camera, light and scale

All parts share one stage, so they read as one piece of hardware.

- **Camera:** orthographic, straight down. Flat layers then stack in 2D without any perspective mismatch.
- **Coordinates:** layout pixels are the Godot capture pixels. The captures were taken at 1.875 times logical size, so a 280 px key is about 149 logical px wide.
- **Light:** one `SpotLight` above and beyond the frame's top-left corner (420 px left and up, 820 px high, intensity 8400, decay 1.1), plus a weak `HemisphereLight` (0.14) and the room environment at 0.16. The tall panel backing raises the lamp to 1900 px so its far end isn't lost in shadow.
  - The lamp's fall-off grades every part from light top-left to darker bottom-right, and its shadows fall to the bottom-right.
  - Metal takes its brightness mostly from reflections, which a lamp barely grades. So the plates also carry the same grade baked into their colour.
- **House light:** the title's letters, the status lamp, the scrollbar and the seam edge are lit by a directional light instead (`houseLight`, `stage(..., { light: 'house' })`): from the upper left, 49.7° above the panel, strength 4, with no fall-off. It is the knob and gauge renderers' key light, and the angle the raised icons' painted shadows already assume (0.6 × height along each axis). A part lit by it looks the same wherever it sits and at any size, which the scrollbar needs because the game stretches it. Its strength matches the spotlight's at a small key, and its shadow map keeps the spotlight's softness.
- **Export scale:** every layer is rendered at `E = 2 / 1.875` times layout size, which is **2 texture pixels per logical pixel**. Godot draws them at half their pixel size, so all bdp_v3 textures import **with mipmaps**.

## Materials

| Material | How it is made |
| --- | --- |
| Worn steel (plates, frames) | The Sunburst worn-steel texture (`cluster_data.js` → `plateTexture`), brightened, flattened and mostly blended with a blurred copy, so fine scratches recede and relief reads on top (`STEEL_CANVAS`). |
| Navy-grey steel (panel backing) | The same texture heavily blurred, only 20% of the sharp scratches kept, greyscaled and multiplied by `#767D88` (`NAVY_STEEL_CANVAS`). |
| Brass (trim) | The same texture blurred, brightened and multiplied by `#E0B460` (`BRASS_TRIM_CANVAS`). |
| Gunmetal (button bezels) | The raw Sunburst texture on a dark metal material (`MAT.frame`). |
| Cream plastic (keycaps, raised icons) | `#E9DFCA`, the approved keycap reference's cream, roughness 0.62 with a light clear coat. Key tops get faint wear and grime towards their corners (`paintPlastic`). |
| Navy text | `#0B2340`, Barlow Condensed Bold / SemiBold. |

The Sunburst texture was generated once for this work, from a brief asking for a flat, evenly lit, edge-to-edge worn steel surface. The brief and the original image are in Project Rebirth's `.asset-image/factory-buttons/`, which is not tracked in git. The texture itself is kept in `cluster_data.js`.

## Plates

A plate is a rounded rectangle extruded 4 px with a 4.5 px bevel (3.6 px flare, 6 segments). This gives it a rounded, rubbed lip; its face is `PLATE_TOP` = 13 px above the ground. `plateMaterial(w, h, feat)` paints four maps onto the face:

- **Colour:**
  - a window of the steel texture;
  - grime settling into the edges, heaviest along the bottom;
  - the lamp's baked grade;
  - soft grime round every button (`feat.buttons`) and screw (`feat.screws`);
  - the swept shadows of the raised icons (see Buttons);
  - screwdriver-slip arcs round each screw;
  - the rubbed edge: a dark band just inside the lip, then a broken bright line along it, strongest on the top and left where the light catches it;
  - rust flecks along the lip.
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
- **Backing:** radius 7.5, on the brass trim.

The plate paints grime round each screw and a few bright screwdriver slips. The block's plate runs 24 px further down than its buttons (`PLATE_FOOT`) so its bottom screws clear the lower keys.

## Frames

- **Button bezels:** `mouldedFrame(w, h, r)` is a thin gunmetal ring that follows a button's outline: a 1.6 px gap, a 5 px rim, 6 px high, with a dark floor in the gap. Every keycap and guarded button sits in one, so the metal is moulded to the button's shape.
- **Section frames:** a 22 px steel rim (the plate material on a ring with a rounded hole), a screw in each corner, and the rim's cast shadow, in a 596 × 396 px render with 18 px of shadow room round it.
  - The game draws it as a 9-slice, which keeps the corners and screws at their size and stretches the edges (`bdp_v3_section.gd`).
  - A section's heading and content go inside, 8 px in from the rim.
- **Backing trim:** a 22 px raised brass ring round the navy-grey backing plate, carrying the corner screws. It is also drawn as a 9-slice (`bdp_v3_nine.gd`, 64-texel corners), behind the whole panel.

## Buttons

### Keycaps (the four white buttons, Close, Back)

- **Shape:** `keycap(w, h, r, paint)` is a flat top face on a straight chamfered skirt. The skirt drops 14 px and flares 9 px with one bevel segment, so the chamfer is a single flat slope. The light shades it as a whole: bright on the top and left, shaded on the right and bottom, like the approved keycap reference.
- **Frame:** the key sits in a moulded bezel.
- **Face:** `paint` draws on the top face. In the export the faces are blank, because the game draws the text live.
- **Pressed state:** the cap lowered 5 px.
- **The four main keys:** 280 px wide (`BW`). Inputs and Outputs are 104 px tall. Upgrade and Change recipes are two lines tall; their row grows by 70 px (`EXTRA`).

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
- **Slider** (`scrollThumb`): a cream plastic cap 16 px wide on a chamfered skirt, in a 30 × 210 frame, standing on the rail, with its shadow on the rail. Its top is plain except for a ribbed grip in the middle: grooves shaded on their upper edge and lit on their lower one.

The game stretches both to the scroll area and to the slider's length, so everything between their ends is the same all the way along. `bdp_v3_scroll.gd` draws each as a vertical three-slice. The ends keep their size (30 px of rail, 15 px of slider), and the slider's grip keeps its size in the middle while there is room for it; a slider too short for the grip is drawn plain. It draws the slices itself, because Godot's `StyleBoxTexture` draws one texture pixel per screen pixel and these renders are at two per logical pixel.

`BdpV3Scroll.apply(scroll, on)` puts the rail and slider on a `ScrollContainer`'s vertical bar (`scroll`, `scroll_focus`, `grabber`, `grabber_highlight`, `grabber_pressed`), so scrolling, dragging and paging stay Godot's own. The bar is 16 px wide. The slider stops 12 px short of the rail's ends, clear of the screws. Under the pointer it is drawn 7% brighter, and 7% darker while held.

## The seam edge

`seamStrip()` is a near-black rubber edge like the nosing on a stair tread, run across the panel where the scrolling body meets the fixed header:

- **Strip:** a cross-section extruded along the panel's length: a back edge on the backing, a tread 5 px high with three rounded grooves along its length, and a lip that rolls down to the body. The rubber is near-black (`#131416`), matt with a faint sheen, with a fine grit in its surface. It has no screws.
- **Shade:** the strip casts its shadow onto the body, and `paintSeamShade` darkens the body a little way out from under the lip, as if it slid out from beneath it.

It renders in a 900 × 48 frame: the strip from y 6 (its back edge) to 26 (its lip), and the shade below it to the frame's foot. In the game, `bdp_v3_seam.gd` draws it as a horizontal three-slice. The 45 px ends keep their size, and the length between them fits the panel. The render is wider than the panel, so the middle is squeezed a little rather than stretched. The strip reaches out to the backing's trim at both sides and down over the top of the body.

The panel puts the scroll area in a plain `Control` (`BodyWell`) with the edge added after it, so the edge draws over the body without a `z_index` and the action sheets still cover it. With v3 on, the body starts at the edge's lip (`_scroll.offset_top`).

## The title

The title has the effects of the INPUTS / OUTPUTS lettering on the control plate:

- **Letters:** raised in the plate lettering's white (`#F4F2EC`, roughness 0.45, a light clear coat), 5 px high on a flank softened by 0.7 px (`relief`).
- **Shadow:** the same swept shadow and contact line, painted by `drawIconShadows`.
- **Faces:** graded from white at the top-left to `#B8B0A0` at the bottom-right, across the whole title, as the plate's lettering is graded across its word.

The font stays the title's own: Bebas Neue at 32 px (60 layout px). Titles change with the building, so each letter is rendered on its own into an atlas (`titleAtlas`, `title_glyphs` and `title_glyph_shadows`, 1400 × 184). Each letter sits in a cell with 10 px of room round it for its shadow, and every cell has the same baseline. `layout.json` lists each cell as `[x, y, w, h, pen x]`. The page loads the game's copy of the font from `export.py`, so the letters match the game's spacing. `relief(..., { faceGrade: false })` leaves the faces ungraded in the atlas.

In the game, `bdp_v3_title.gd` shapes and wraps the title with Godot's text server in the same font, size and wrapping as the plain label, and places each letter's render on its pen position. It draws every shadow first, then the faces, each shaded for where its middle falls in the block of lines. The atlas covers A–Z, 0–9 and common punctuation, which is every character in the building and recipe names (a test checks this). A title with any other character keeps the plain label.

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

To render some sets only, add `&only=` and a comma-separated list of `block`, `footer`, `backing`, `section`, `keys`, `lamp`, `scroll`, `seam` and `title`, for example `cluster.html?export&only=lamp,scroll`. The other layers are left as they are, and the page reads the current `layout.json` from the server and updates only those sets' entries. `export.py` takes an optional port (`python3 tools/button_mockup/export.py 8779`); use a port of your own when another export may be running.

| Set | Layers |
| --- | --- |
| Control block (863 × 379) | `block_plate`; `block_icon_input`, `_output`, `_recipe`; `block_kicker_input`, `_output`; `block_lorry_input`, `_output`; `block_arrow`, `block_arrow_lit`; `block_shadow_<part>` for each raised part; `block_glow_arrow` (additive); `block_key_<inputs, outputs, upgrade, recipe>` and `_pressed` |
| Footer (863 × 214: 150 of plate, 64 of headroom above) | `footer_plate`; `footer_glow` (additive); `guard_<sell, demolish>`, `_pressed`, `_cover`, `_cover_open` |
| Small keys (96 × 96, key in the middle 64) | `key_close`, `key_back`, and `_pressed` |
| Section frame (596 × 396) | `section_frame` |
| Backing (940 × 1640) | `panel_backing` |
| Status lamp (112 × 112, bezel 44 in the middle) | `lamp_<green, amber, red, off>`; `lamp_glow_<green, amber, red>` (additive) |
| Scrollbar | `scroll_rail` (30 × 240), `scroll_thumb` (30 × 210) |
| Seam edge (900 × 48) | `seam_edge` |
| Title letters (1400 × 184) | `title_glyphs`, `title_glyph_shadows` |

`layout.json` lists each set's size and every key's rect and top face, in layout pixels, plus the lamp's bezel, the scrollbar's end, grip and travel sizes, and the seam edge's ends, back edge and lip. The scripts carry these numbers as constants. After changing a layout, copy the new numbers from `layout.json` into `bdp_v3_block.gd`, `bdp_v3_footer.gd`, `bdp_v3_section.gd`, `bdp_v3_lamp.gd`, `bdp_v3_scroll.gd` or `bdp_v3_seam.gd`.

After an export, reimport with `Godot --headless --path . --import`. A new layer's `.import` gets `mipmaps/generate=true`, then import again. The scene uses a seeded random number generator, but the seed advances as parts are built, so adding a part changes the scratches and wear on the parts built after it. Expect every layer to change slightly on each export. The lamp, the scrollbar, the seam edge and the title's letters are built with seeds of their own (`withSeed`), so they come out the same whichever sets are exported with them. Put a new set after the existing ones and give it its own seed, so the layers already in the game don't change.

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
- **Panel:** `building_detail_panel_v2.gd` builds these in place of the v2 controls when `UiPrefs.use_bdp_v3` is on. The keys open the same sheets as v2. It then moves each section's heading and content into a `bdp_v3_section` frame (`V3_FRAMED_SECTIONS`; Modifiers and Economics share one). It shows the backing and hides the brass pipe border, and swaps Close and Back for keycaps. `_apply_v3_chrome` swaps the title label for the raised title (`_apply_v3_title`), the status badge for the lamp, puts the rail and slider on the panel's scrollbar (each action sheet's scrollbar gets them too) and shows the seam edge, starting the body at its lip.

## Adding another control

1. **Model it** in `cluster.html` from the existing parts: `keycap`, `mouldedFrame`, `relief` / `iconRelief`, `screw`, `plateMaterial`, `guardButton`. Place it on the stage above.
2. **Check it in the study** (`cluster.html` without `?export`) before exporting.
3. **Export its layers** in `exportLayers()`. Keep one frame per set; render keycaps blank and draw their text in the game; bake icon shadows into the plate, or export them as `shadow_` layers when the icon can change.
4. **Stack them** with a `bdp_v3_plate.gd` subclass, using the rects from `layout.json`, and wire it into the panel behind `UiPrefs.use_bdp_v3`.
5. **Test it** in `tests/unit/test_ui.gd`.
