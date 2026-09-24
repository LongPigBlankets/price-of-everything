# DS2: the worn-industrial theme

DS2 is the second design system: panels drawn as physical equipment, meaning worn steel plates, moulded plastic, cream keycaps, LED screens, gauges, drum counters and pilot lamps, lit by one lamp. It was built and approved on one panel, Building Detail v3 (BDP v3, behind the debug cheat `toggle bdp v3`, `UiPrefs.use_bdp_v3`). This document is for the agent that moves another panel to it. It covers the rules of the look, how its parts are made, every component built so far with its API, the patterns that combine them, how to check work, the traps, and the plan for turning the BDP-specific code into a shared DS2 kit.

Read these alongside it:

- `docs/bdp-v3-control-plates.md`: the BDP v3 spec, part by part, with render details, the export command and the layer table.
- `docs/bdp-v3-roadmap.md`: what was decided with the owner, when, and what is still open.
- `CLAUDE.md`: the standing rules. The text-contrast rule applies to DS2 unchanged.

The approved look is kept as a standard: tag `bdp-v3-standard-2026-09-24-d`, its captures in `artifacts/bdp_v3_standard/`. Earlier tags record earlier stages: `-c` before the economics keys and nesting, `-b` before the economics rework, and `bdp-v3-standard-2026-09-24` (no letter) before the re-render.

---

## 1. The rules of the look

These are owner rulings. Each came up more than once; do not re-litigate them.

1. **Everything is a physical object.** A surface is a steel plate, a plastic case, a sheet of white plastic, glass or enamel. A control is a keycap, a guarded button, a slide switch or a rubber grip. A number is an LED screen, a gauge or a drum counter. Nothing is a flat design-system card with a border.
2. **One light.** Every render is lit by the same directional "house light" from the top-left, at 49.7° elevation. In the game, one multiply overlay darkens the panel away from a lamp at the screen's top-left, so the panel reads the same wherever it sits and as it scrolls. No part bakes its own light or gradient.
3. **Text is white on anything dark, navy on anything light.** Never grey on navy (`CLAUDE.md`). On dark metal or plastic, labels are `DS.PALETTE.TEXT` (#E8EEF7) with a dark shadow down and to the right, so they stand off the surface (`_v3_emboss`). On cream keycaps and white plastic, print is navy #0b2340, and semantic figures use darker inks (§6).
4. **Headings and big names are raised lettering.** Section headings are raised white letters (IBM Plex Sans Bold) and the panel title is raised Bebas Neue, both rendered as relief. The small switch labels VISUAL and TEXT use the same raised letters.
5. **Numbers that matter sit on displays.** Money goes on an LED screen after a printed £. Every screen in a group shows the same number of digits, blank digits leading, so the screens are one width and the £ signs line up. Results are green, or red below zero. Costs are red and unsigned. Rolling counts use drum counters, and a ratio against a limit uses a gauge.
6. **Status is a lamp.** A pilot lamp is green (ok), amber (warn), red (bad) or off, with a glow. It is used for building status, diagnostics rows, stock and transport.
7. **Goods keep their icon language.** A good is its cream icon tile with a navy quantity pill. Where an icon stands alone on DS2 it is set into a thin metal frame, below the metal edge, with its pill inside the icon's corner, not overhanging.
8. **Wear is consistent.** Scratch size is the same on every plate (`STEEL_SCALE` 1.45 texture px per plate px). Edge flecks are counted per 100 px of edge (`FLECKS_PER_100PX`). Every render set has its own random seed. Grime, chips and scuffs follow where use and weather would put them: edges, feet, round handles, under hinges.
9. **Show only what informs.** Don't show a caret or sheet with nothing to open (Modifiers with none). Don't show a figure that duplicates another section (the power line). Don't show economics for a building with neither inputs nor outputs (a battery).
10. **Figures come from the engine.** A panel figure is quoted by the same helper the turn's cash moves by, never re-derived (§8).
11. **Every visual change is compared with the standard** before it is shown to the owner (§9).

---

## 2. Units and scale

Three units are in play. Mixing them up is the commonest mistake.

| Unit | What it is | Where |
|---|---|---|
| **layout px** | The render's coordinates. The study was laid out over Godot captures at 1.875× logical. | every constant in `cluster.html` and `layout.json` |
| **logical px** | Godot's UI pixels. | Godot controls, `custom_minimum_size`, draw calls |
| **texels** | Pixels of an exported PNG: 2 per logical px (`E = 2 / 1.875` per layout px). | `draw_texture_rect_region` source rects, 9-slice corners |

Conversions:

- logical = layout / 1.875
- texels = logical × 2 = layout × 2 / 1.875

Every DS2 script carries `CAPTURE_SCALE := 1.875` and `TEXELS_PER_PIXEL := 2.0`. A render's size in logical px is its PNG size / 2.

Every exported layer imports with mipmaps (`mipmaps/generate=true`, the folder's default), and every DS2 control sets `texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`. Draw renders at or below 2 texels per px. Scaling a render up blurs it, so re-render it larger instead; the small keys were re-rendered at 76 layout px so they draw a title line tall.

---

## 3. How a part is made: render → export → Godot

### 3.1 The render

All DS2 art is 3D-rendered in one three.js page, `tools/button_mockup/cluster.html`. A set is one function that builds a `THREE.Group`. `stage(bounds, parts)` lights it with `houseLight` plus a faint sky fill, and grabs it with an orthographic camera looking straight down. Shared building blocks:

- **Geometry:**
  - `rrShape(w, h, r)`, a rounded rectangle.
  - `extrude(shape, depth, bevel, size, segments)`, a bevelled slab. Its top face's UVs are in shape pixels.
  - `relief(w, h, draw, material, {height, soften, faceGrade})`, a mask raised as a height field (icons, lettering).
  - `iconRelief(img, …)`, `textRelief(...)`.
  - `screw(r)`, `silverScrew()`, `weldBead(...)`.
- **Materials:**
  - `plateMaterial(w, h, feat)`: worn steel from the Sunburst texture, with rubbed edges, flecks, grime round features, a `feat.paint` hook, and `feat.base` for another steel. Variants are `STEEL_CANVAS` (light), `NAVY_STEEL_CANVAS` (the backing), `DARK_STEEL_CANVAS` (dark gunmetal) and `BRASS_TRIM_CANVAS`.
  - `paintPlastic` (the cream keycap plastic), `KNOB_PLASTIC`, `WHITE_LETTERS`, `MAT.frame` (gunmetal bezel), `MAT.screw`, `MAT.gap`.
  - `weatheredPaint(w, h, base, {wear, grip, hinges})` for painted steel, `treadPlate(w, h)`, and `blackPlasticFace(...)`.
- **2D layers** (drawn onto a canvas in the render's frame, not rendered):
  - `drawIconShadows`: the swept shadow and contact line of raised shapes.
  - `frame2d(W, H, paint)`: a 2D layer in exactly the render's pixel frame.
  - glass overlays, such as `paintCounterGlass`, `paintScreenGlass` and `paintWellShade`.
- **Parts:**
  - the keycap: `keycap(w, h, r, paint)`, a flat top on a chamfered skirt in a moulded bezel, with `pressable`;
  - `pilotLamp`, `guardButton`, `counterHousing`, `miniScreen`, `iconWell`, `gaugeSocket`;
  - `diagModule`, `cableRun`, `cableTap`, `toggleSlot`/`toggleKnob`, `rollingDoor`, `labourDoor`;
  - `sheetPlate`, `whiteSheet`, `plasticPlate`, `darkPlate`, `enamelPlate`.
- **Seeds:** `withSeed(n, fn)` gives each set its own random sequence, so exporting one set never changes another's wear. A new set gets a new seed after the last one used (421, `econ`).

### 3.2 The export

```sh
python3 tools/button_mockup/export.py 8779        # a private port: 8771 may be another agent's server
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --use-angle=metal \
  --virtual-time-budget=180000 --dump-dom "http://127.0.0.1:8779/cluster.html?export&only=<set>,<set>"
```

- **Completion:** the page's title reads `export done` when it has finished.
- **Output:** layers are written into `assets/ui/bdp_v3/`, and each set merges its entry into `layout.json`. Other sets' layers stay byte-identical.
- **Game assets served to the page:** `export.py` serves the game's fonts at `/fonts/<file>.ttf` and its icons at `/icons/<path>.png`, so lettering and raised icons match the game's own.
- **Sets and their seeds:**

| Seed | Sets |
|---|---|
| 501–505 | `block`, `footer`, `backing`, `section`, `keys` |
| 401–411 | `lamp`, `scroll`, `seam`, `title`, `enamel`, `pin`, `cable`, `counter`, `sheet`, `plastic`, `door` |
| 412–421 | `heading`, `module`, `toggle`, `ldoor`, `modkey`, `sheetw`, `darkplate`, `modicon`, `screen`, `econ` |

Then import:

```sh
"$GODOT" --headless --path . --import
```

Check that a new layer's `.import` has `mipmaps/generate=true`.

### 3.3 In Godot

One script per component, `scripts/bdp_v3_<part>.gd`. Each carries the render's layout numbers as constants copied from `layout.json`, such as a 9-slice corner, a cap width or a plate rect. The drawing primitives are:

| Primitive | How | Used by |
|---|---|---|
| **9-slice** | `BdpV3Nine.paint(ci, tex, dest, corner_texels)`: corners keep size, edges and middle stretch. `dest` is grown by the render's shadow room (its margin). | frames, plates, modules, sheets, screens, wells |
| **3-slice, stretch** | a `StyleBox` subclass (`BdpV3Scroll.make(tex, cap, …)`) whose `_draw` slices at 2 texels per px. `StyleBoxTexture` is 1:1 and cannot. | cable, scrollbar rail |
| **3-slice, whole periods** | the same `StyleBox` with `period` and `repeat_from`: the middle repeats whole periods (ridges, slats), never stretches them | scrollbar thumb, seam edge |
| **Horizontal 3-slice by hand** | cap, middle, cap drawn in `_draw` | wide keys, drum counter (middle cell repeated per drum), seam |
| **Crop, not slice** | a large plain render cropped from its middle at 2 texels per px, so scratches keep their size | the dark plate (`BdpV3Section` style `dark`) |
| **Fixed render, fitted** | drawn at its own aspect into the control | lamps, doors, keys, relief icons |
| **Live print over a blank render** | the render has blank faces; the game prints text on them with its fonts | block keys, footer, wide key |

Layering is by sibling order, never `z_index`: a later sibling draws over an earlier one, and `z_index` would poke through sheets and other panels. A background for a container is painted in the container's own `draw` signal (`draw.connect(func(): BdpV3Nine.paint(...))`), which runs before its children, not as a child: a container insets its children by its content margins. An overlay that must extend beyond its control (a door reaching the rim, a tap into a module, a gauge's socket) is drawn by the owning control at negative or outside coordinates. The outcome slide-out uses a clipping child above the footer.

---

## 4. Lighting

| Where | What | API |
|---|---|---|
| Renders | `houseLight`: a directional light from (−3, 5, −3), intensity 4, with soft shadows. The painted swept shadows of raised shapes imply the same angle. | `stage(..., {light: 'house'})`, the default |
| The panel | One overlay over the whole panel multiplies in the lamp: light falls off linearly from `NEAR` 0.25 to `FAR` 0.9 of the screen diagonal from the top-left, down to `DARKEST` 0.7. It is drawn last in the panel (`_shade`), above sheets. | `BdpV3Light.shade_material()` (`bdp_v3_light.gd`) |
| Text | Labels take back half the overlay's shade (`TEXT_GIVE_BACK` 0.5), so text stays readable as the metal darkens. Applied to every Label and RichTextLabel under the panel's margin and sheets. | `BdpV3Light.text_material()`, `_apply_v3_text_light()` |
| Things that give light | LED segments and the value bar's slices take back all of it: the lamp doesn't dim them. | `BdpV3Light.emissive_material()` |
| Glows | Lamp glows and the lit arrow add their light, undimmed. | `BdpV3Light.glow_material()` (blend_add) |

The lamp's light at a point, for tests and tools, is `BdpV3Light.light_at(screen_uv, screen_size)`.

---

## 5. Components

Each entry lists the look, its render set and layers, the Godot script and API, and where BDP v3 uses it. Items marked *(panel helper)* live as methods in `building_detail_panel_v2.gd` today; §10 says where each should move.

### 5.1 Surfaces

| Component | Look | Render → layers | Godot | BDP use |
|---|---|---|---|---|
| **Backing plate** | navy-grey steel, a narrow welded brass trim (14 px), heat tint by the weld | `backing` → `panel_backing` | `BdpV3Nine` full-rect, corner 60 | the panel itself |
| **Section frame** | a narrow worn steel rim (26 px), a screw in each corner on the rim's centre line | `section` → `section_frame` | `BdpV3Section` (`content` VBox; `RIM`, `PADDING`) | every framed section |
| **Dark metal plate** | blackened gunmetal filling a frame's inside, edges under the rim; cropped, not stretched | `darkplate` → `dark_plate` (900 × 1400) | `BdpV3Section.style = "dark"` | Cost to produce, Inbound shipments |
| **Plastic case** | moulded black plastic, a rounded glossy edge; silver screws placed by Godot, 4 top, 4 bottom, 6 a side | `plastic` → `diag_plastic`, `screw_silver` | `BdpV3Section.style = "plastic"`; `screw_points(size)` | Diagnostics |
| **Raised module** | a slightly raised black plastic panel inside a case | `module` → `diag_module` | `_v3_diag_module()` *(panel helper)*: PanelContainer with the module painted in `draw` | each diagnostics row |
| **Steel sheet** | a worn steel plate that slides in from the right over the body | `sheet` → `sheet_plate` | `_v3_sheet_plate(sheet, margin)` *(panel helper)* | action sheets (recipe, routing, upgrade) |
| **White plastic sheet** | the keycaps' cream plastic as a thin moulded plate, navy print | `sheetw` → `sheet_white` | painted in `draw`; inks via `_v3_ink` | the Modifiers sheet |
| **Enamel sign** | vitreous enamel recessed into the panel, cream rim, cracks and yellowing kept off the icons | `enamel` → `recipe_enamel`, `recipe_grunge` | `BdpV3Enamel.watch(controls)`, `hole_rects()` | the recipe diagram |
| **Outcome plate** | a steel sheet sliding up from behind a plate | reuses `sheet_plate` | `_v3_outcome_plate`, `_v3_slide_outcome` *(panel helpers)* | Sell and Demolish outcomes |

### 5.2 Controls

| Component | Look | Render → layers | Godot | BDP use |
|---|---|---|---|---|
| **Control plate with keys** | a steel plate carrying raised icons, raised kicker lettering and wide cream keycaps printed live | `block` → `block_*` | `BdpV3Block` extends `bdp_v3_plate.gd` (`set_frame`, `set_layers`, `set_key(key, rect, face, normal, pressed, lines, caret, enabled, tooltip)`, signal `key_pressed`) | Inputs / Outputs / Upgrade / Change recipes |
| **Wide key** | a worn cream keycap, 3-sliced across; text printed navy, a chevron, latching down while open | `modkey` → `key_modifiers`, `_pressed` | `BdpV3ModKey`: `summary`, `summary_ink`, `openable` (no chevron, no press), `key_scale` (smaller, uniformly), `set_open()`, signal `toggled(open)` | Modifiers; the economics rows that open |
| **Small key** | a square cream keycap with a navy glyph (✕, ‹, map pin), its shadow baked | `keys`, `pin` → `key_close`, `key_back`, `key_pin` (+ `_pressed`), 76 px key in a 108 frame | `BdpV3Key.make(glyph, key_px)`, `control_side(key_px)` | Close and Location (one title line tall), Back on sheets |
| **Guarded button** | a glowing plastic cap under a hinged clear cover: the first click lifts the cover, the second presses; an untouched cover drops after 4 s | `footer` → `footer_*`, `guard_*` | `BdpV3Footer`: `lift`, `drop`, `is_open`, signals `key_pressed(key)`, `cover_changed(key, open)` | Sell building, Demolish |
| **Slide switch** | a slot moulded into the case, an off-white ridged thumb that slides | `toggle` → `toggle_slot`, `toggle_knob` | `BdpV3Toggle`: `right`, `set_right()`, signal `toggled(right)` | Diagnostics' Visual / Text (does nothing yet) |
| **Scrollbar** | a steel rail screwed to the backing, a rubber grip with diagonal ridges | `scroll` → `scroll_rail`, `scroll_thumb` | `BdpV3Scroll.apply(scroll, on)`, `is_applied()` | the panel's and each sheet's scroll |
| **Seam edge** | a dark ribbed rubber nosing where the fixed header meets the scrolling body | `seam` → `seam_edge` | `BdpV3Seam` (`strip_height()`) | under the header |

### 5.3 Indicators and readouts

| Component | Look | Render → layers | Godot | BDP use |
|---|---|---|---|---|
| **Pilot lamp** | a lens in a turned steel bezel, lit green / amber / red or off, with a glow | `lamp` → `lamp_<green, amber, red, off>`, `lamp_glow_*` | `BdpV3Lamp`: `set_tone(tone)` (ok/good → green, warn → amber, bad → red, else off), `lamp_scale`, `colour_for(tone)` | status, diagnostics rows (0.72), stock (0.62), transport lamps |
| **LED screen** | a gunmetal bezel round dark glass; seven-segment digits lit in a colour over faint unlit segments; a lit point has room of its own | `screen` → `mini_screen`, `mini_screen_glass` | `BdpV3Led`: `set_figure(text, colour)` (digits, `-`, spaces; `.` lights the point of the digit before it), `figure()`, `cells_for(text)` | every money figure |
| **£ figure** | a printed £ then an LED screen, padded to a group's digit count | — | `_v3_money_led(figure, colour, digits)` *(panel helper)* | cost prices, economics, the sale price |
| **Drum counter** | a gunmetal housing, black drums; digits printed live and rolling like an odometer | `counter` → `counter_housing`, `counter_glass` | `BdpV3Counter`: `configure(drums, decimals)`, `set_value(v, from)`, `digits_for`, `drums_for` | labour cost and workers |
| **Gauge set in a plate** | the panel gauge (bezel, zones, needle, LED) in a chamfered hole cut in the dark plate | `darkplate` → `gauge_socket`; gauge layers in `assets/ui/gauge/` | `PanelGauge` (`scripts/panel_gauge.gd`) held in a trimmed holder; the card paints the socket under it | cost to produce |
| **Value bars** | revenue and costs as two bars on one scale on mini screens; revenue a green slice per good (the good's icon on a rounded tile above), costs in four reds (raised icons above); icons spread and joined by leader lines; a dashed mark at the revenue's end | `econ` → `econ_icon_*` (+ `_shadow`) | `BdpV3ValueBar`: `set_values(econ)`, `rows_for(econ)`, `row_keys(row)`, `row_label(row)`, `icon_centres(row)` | economics |
| **Transport lamp** | a raised side icon, a lamp by transport's share of that side's goods (green < 3%, amber < 8%, red above), the cost or a "free" flag | reuses the lamp and `econ_icon_inputs`/`_outputs` | `_v3_transport_lamp(...)` *(panel helper)*; `BuildingEconomics.transport_tone` | economics |

### 5.4 Lettering

| Component | Look | Render → layers | Godot | Rules |
|---|---|---|---|---|
| **Raised title** | Bebas Neue 32 px as white relief, graded across the title | `title` → `title_glyphs`, `title_glyph_shadows` (atlas) | `BdpV3Title`: `text`, `can_show()`, `line_height()`, `line_pitch()` | shaped and wrapped by Godot's text server in the same font |
| **Raised heading** | IBM Plex Sans Bold 28 layout px as white relief, as INPUTS / OUTPUTS | `heading` → `heading_glyphs`, `heading_glyph_shadows` (atlas with advances) | `BdpV3Heading`: `text`, `can_show()`, `letter_count()` | laid out by the page's measured advances (the game has no Plex Bold); falls back to the plain label for missing characters |
| **Metal label** | Barlow Condensed SemiBold capitals, off-white | — | `_v3_metal_label(text, align)` *(panel helper)* | small labels on steel |
| **Embossed white** | `DS.PALETTE.TEXT` with a shadow (0, 0, 0, 0.9) offset 1, 1 | — | `_v3_emboss(label)` *(panel helper)* | any label on plastic or a busy surface |
| **Navy print** | Barlow Condensed Bold, navy, fitted to the face | — | `BdpV3Plate._fit`, the keys' `_draw` | on keycaps |

### 5.5 Icons

| Component | Look | Render → layers | Godot |
|---|---|---|---|
| **Raised relief icon** | a game icon's mask raised in cream enamel with a swept shadow, graded top-left to bottom-right | `econ` (`ECON_ICONS`), `modicon`, the block's icons; source PNGs served from `/icons/` | draw shadow then face at the same rect |
| **Icon set in a well** | a thin gunmetal frame over a good's cream tile, its shadow falling onto the icon (the icon lower than the metal), the tile's corners matching the opening | `darkplate` → `icon_well` | `_v3_set_in_well(icon)` *(panel helper)*: over the art, under the pill |
| **Quantity pill inside** | the navy pill kept within the icon's corner | — | `_good_icon_pill(..., pill_inside = true)`, `QTY_PILL_INSET` 5 |
| **Good tile** | a small rounded cream square behind a good icon with a soft shadow | — | `StyleBoxFlat` in `UIHelpers.PILL_PAPER` (value bar) |

### 5.6 Scenes

These are illustrations of the building's workings. They are BDP-specific, but their techniques are general.

| Scene | Look | Render → layers | Godot |
|---|---|---|---|
| **Cable and taps** | black rubber cable with a yellow tracer between glands; a junction box, branch and gland into each module | `cable`, `module` → `diag_cable`, `diag_tap` | `BdpV3Cable`: `centre_x`, `taps` (draws a tap at each module's middle) |
| **Rolling-door bay** | a six-good bay; the door comes down over the rows no good needs; rolled up, the housing and bottom bar | `door` → `shipment_door` | `BdpV3Door` (`reach`, `rolled_up_height()`, `rows()`, `paint()`); `v3_door_rows(goods)` |
| **Factory doors** | weathered painted steel doors: chips, grime, hinges, closer, wired glass (lit warm when staffed), a kick plate with the headcount engraved | `ldoor` → `labour_door`, `labour_door_lit` | `BdpV3LabourDoor` (`count`, `frame_rect()`) |

---

## 6. Palette and type

| Ink | Value | For |
|---|---|---|
| Text on dark | `DS.PALETTE.TEXT` #E8EEF7 | every label on metal, plastic or glass |
| Navy print | #0b2340 | keycaps, white plastic, engraved kick plates |
| OK / WARN / DANGER on dark | `DS.PALETTE` #5BD180 / #E6B85C / #E66060 | LED figures, semantic text on dark |
| OK / WARN / DANGER on white | `V3_INK` #1d6b3a / #7a4a00 / #8f1f19 | semantic figures on white plastic (`_v3_ink(colour)` maps a DS colour to it) |
| Lamp colours | green #4fdc86, amber #ffa412, red #e8281e | pilot lamps, guarded caps |
| Cost reds | #6b1914 inputs, #8e231b labour, #b03026 upkeep, #d64a3a transport | value bars |
| Revenue greens | #3fb265, #2e8f4f, #5fcf85, #23713d | value bars, a good each |
| Drum digits | #efede6 | drum counters |
| Cable tracer | #e9b81a | cable |

| Type | Font | Size |
|---|---|---|
| Panel title (raised) | Bebas Neue | 32 px |
| Section heading (raised) | IBM Plex Sans Bold | 28 layout px (≈15 px) |
| Key print | Barlow Condensed Bold | fitted, ≤ 22 px |
| Metal labels | Barlow Condensed SemiBold, capitals | 13–15 px (18 for £) |
| Body and captions | `DS` "Body" and "Caption" (IBM Plex Sans Medium) | 14 px; 16–17 for emphasis |
| LED digits | drawn segments | cell 12 × 21 px |

---

## 7. Patterns

These are the ways components are combined. Reuse the pattern, not only the part.

1. **Section framing.** A panel builds its body as a flat list: a heading row (meta `v3_section`) followed by its cards. `_v3_frame_sections()` then moves each heading and everything up to the next heading into a `BdpV3Section`. A dictionary (`V3_FRAMED_SECTIONS`) names which headings are framed and which share a frame. Headings mapped to the same name share one frame, as Modifiers and Economics share "money". The frame's `style` is set by name: `plastic` for diagnostics, `dark` for cost and shipments. A row with meta `v3_section_end` (the footer) closes framing.
2. **Headings.** `_make_section(text)` builds the plain label and, in v3, puts a `BdpV3Heading` in front, hiding the label. The label stays in the tree for code that looks it up.
3. **Money column.** Every money figure is `_v3_money_led(figure, colour, digits)`. A group computes `digits` as the most cells any of its figures needs (`BdpV3Led.cells_for("%.2f" % f).size()`), so its screens are one width and the £ signs line up.
4. **Rows that open (accordion).**
   - `_v3_econ_accordion(name, key, title, figure, colour, parts, key_scale)` builds a wide key (`BdpV3ModKey`) with the title, and the figure's screen beside it.
   - Opened, it shows its parts, indented 22 px, each a `_v3_econ_line`, or a nested accordion built the same way on a smaller key (`key_scale` 0.8).
   - The open state is kept in a dictionary across rebuilds (`_v3_econ_open`).
   - With no parts it is a plain row, and a key with nothing to open is `openable = false`.
5. **Sheets.** An action sheet's content goes on a steel plate that slides in from the right (0.26 s), clipped inside the trim. It is under the lamp overlay (the overlay is moved last), and its text is given back light.
6. **Outcome slide-out.** When a guarded cover lifts (`cover_changed`), a plate slides up from behind the footer, 0.22 s, inside a clip strip above the footer. The plates are laid out all along and parked below the strip: a hidden container measures nothing. The lifted cover stands in front.
7. **Set-in icons.** A good icon standing alone on DS2 goes in a well (`_v3_set_in_well`) with its pill inside. On a value bar, a good's icon goes on a small rounded tile.
8. **Lamps for tone.** Map a tone (`ok`/`warn`/`bad`/`info`) to a `BdpV3Lamp` beside the thing it judges. Scale 0.62–0.72 in rows. The rule that sets the tone lives with the data (`v3_stock_tone`, `BuildingEconomics.transport_tone`), not in the drawing.
9. **Bays and fills.** A space sized for the maximum, with the unused part covered by something physical (the rolling door over empty rows), keeps a section's height constant whatever the content.
10. **Connections drawn.** Where parts are fed by something (modules by the cable), draw the feed: a trunk and a tap per part, placed at each part's middle, redrawn when the parts move (`item_rect_changed`).
11. **Width discipline.** No section's minimum width may exceed the body's width (the scroll's width less its bar). A wider child silently widens the ScrollContainer and shoves the rail into the trim. Autowrapping labels need a minimum width, and it must fit. A test asserts `_body.get_combined_minimum_size().x <= scroll width − bar`.

---

## 8. Data: quote with the engine's helpers

A DS2 panel shows the numbers the game actually moves. The economics section (`scripts/building_economics.gd`, `per_turn(building)`) is the model:

- **Rule:** every figure comes from the helper the turn's cash moves by, called as a quote that books nothing.
- **Inline engine code:** where the engine computed something inline, it was extracted into a shared helper that the engine now calls too. No figure is re-derived.

| Helper | What it quotes | Called by |
|---|---|---|
| `TransportService.quote_market_buy(tile, gid, qty, covered)` | goods at the buy price, inland freight, and the port charge on a purchase | engine purchases; economics inputs |
| `MarketState.sale_charges(port, route, items, seller_pays, commit)` | a market sale's freight and port charge | `execute_sale` (commit); economics (quote) |
| `Production.stock_sale_charges(port, route, gid, qty, waived, commit, breakdown)` | a stockpile sale's leg to port (after the freight credit) and port charge | the sell phase; economics |
| `TransportService.land_cost_after_credit(gid, qty, route, commit)` | a transfer between the company's own tiles | production dispatch; economics |
| `Power.grid_import_price()` / `grid_export_price()` / `allocated_draw_cost(tile, amount)` | power's price and a building's share | power settlement, forecast, intermediary, economics |
| `BuildingStatus.effective_output_qty(b, r, this_turn)` / `BuildingReadout.flow(b, r, this_turn)` | this turn's output (startup ramp, intermittency) | intermediary, economics |
| `PolicyState.run_carbon_levy(b, r)` | one run's carbon levy | readout, intermediary, economics |
| `CostSolver.warehousing_share(iid)` | a building's share of its tile's storage fee | readout, economics |
| `BuildingState.space_used(b)` | a building's land | tile totals, the demolish outcome |
| `BuildingPrice.sale_price(b)`, `BuildingWorks.refund_cost(iid)` | sale price, demolition refund | review panel, outcome plates |

The figures were proved against real cash with `tools/recipe_profitability_case.tscn -- r_009 out.json --panel [--site=tile_5_4 --route=roads]`. Net value added came within £0.43 a turn beside the port and £0.02 inland. Port charges are described in `docs/goods-balancing.md` §1.5.

---

## 9. Verifying a change

Run these in order; each catches what the previous one can't.

1. **Parse check:**
   ```sh
   "$GODOT" --headless --path . res://tools/parse_check.tscn --quit-after 600
   ```
   It skips autoloads. After editing an autoload (Power, MarketState, Production, PolicyState, CostSolver), also check the boot log:
   ```sh
   "$GODOT" --headless --path . --quit-after 5 | grep -i "parse error"
   ```
2. **The v3 tests:**
   ```sh
   python3 tools/run_tests.py --test bdp_v3
   ```
   These are `_test_bdp_v3_rules` and `_test_bdp_v3_panel` in `tests/unit/test_ui.gd`. Check the checks count as well as the failures: a test that returns early passes with fewer checks.
3. **The full suite:**
   ```sh
   python3 tools/run_tests.py
   ```
   Grep the log for `SCRIPT ERROR`, because GDScript runtime errors don't fail tests.
4. **Captures:**
   ```sh
   BDP_SHOT_DIR=<dir> "$GODOT" --path . res://tools/bdp_v3_shot.tscn --quit-after 4000 -- --no-telemetry
   ```
   - It renders in a fixed 1920 × 1200 SubViewport at 2×, so captures are identical whatever display it runs on. The `--no-telemetry` user arg keeps the windowed run off the live telemetry sheet.
   - Its views are: top (lit, unshaded, unlit), the lamp in each tone, cost, mid, bottom, the Sell and Demolish outcomes, the thumb states, the sheet sliding and settled, Modifiers open, the economics (closed, open, a power plant, a mine, a chlor-alkali plant) and shipments (3–4 and 5+ inputs).
5. **Compare with the standard:**
   ```sh
   python3 tools/bdp_v3_compare.py --current <dir> --out <cmp dir>
   ```
   - It reports how much of each view changed, the lamp's light in a 3 × 4 grid and the steel's brightness down the edges, and writes standard | current | difference images. Views the change shouldn't touch must read 0.0.
   - To isolate one batch, compare with the previous batch's captures (`--standard <previous dir>`).
6. **Save the standard** only when the owner approves: `--save`, commit `artifacts/bdp_v3_standard/`, then tag `bdp-v3-standard-<date>-<letter>`.

---

## 10. From BDP v3 to a DS2 kit

Everything above was built inside one panel. To use it across panels, move the generic parts into a kit, keeping the approved look pixel-identical: the comparison must read 0.0 after each move.

**Proposed layout:**

| From | To |
|---|---|
| `assets/ui/bdp_v3/` | `assets/ui/ds2/`, with `layout.json` alongside. Keep the BDP-only scenes (doors, bay, cable) in `assets/ui/ds2/bdp/`, or leave them where they are. |
| `scripts/bdp_v3_{nine,section,light,lamp,led,counter,key,mod_key,toggle,scroll,seam,heading,title,plate,value_bar}.gd` | `scripts/ds2/` as `ds2_<part>.gd`, each with `class_name` added once the editor has scanned them. Until then, preload by path: a new `class_name` isn't in the headless cache. |
| panel helpers `_v3_emboss`, `_v3_metal_label`, `_v3_money_led`, `_v3_econ_line`, `_v3_econ_accordion`, `_v3_set_in_well`, `_v3_diag_module`, `_v3_outcome_plate`/`_v3_slide_outcome`, `_v3_sheet_plate`, `_v3_ink`, `_v3_money_gap` | a `DS2` helper script (`scripts/ds2/ds2.gd`), static factories: `DS2.emboss(label)`, `DS2.metal_label(text)`, `DS2.money(figure, colour, digits)`, `DS2.readout_row(title, figure, colour)`, `DS2.accordion(...)`, `DS2.set_in_well(icon)`, `DS2.module()`, `DS2.slide_out(owner, plate)`, `DS2.sheet_plate(...)`, `DS2.ink(colour)`. Open state, like `_v3_econ_open`, stays with the panel that owns it. |
| `_v3_frame_sections` + `V3_FRAMED_SECTIONS` | `DS2.frame_sections(body, map, styles)`: the panel passes its map and each frame's style |
| `_apply_v3_text_light`, `_shade` | `DS2.light_panel(panel_root, margin, sheets)`: one overlay per panel, text given back |
| constants `CAPTURE_SCALE`, `TEXELS_PER_PIXEL`, inks, lamp and slice colours | `DS2` constants, one place |
| `tools/button_mockup/cluster.html` sets | a DS2 kit page (sets for surfaces, controls, indicators, lettering, icons) and per-panel pages for scenes. Keep `withSeed` per set and the `only=` merge. |
| `tools/bdp_v3_shot.gd`, `tools/bdp_v3_compare.py` | generalise: the shot tool takes a panel and a list of views; the compare tool already takes any folder. Give each migrated panel its own standard folder. |

**Keep panel-specific:** the BDP's economics data (`BuildingEconomics`), the doors, the bay and the cable. Keep the block's layout too (its plate is a render of one arrangement of keys). A new panel with its own plate of keys gets its own render set, built from `keycap` and `buildBlock`'s approach.

**Order of extraction:** move one component at a time. Update BDP v3 to use the moved component, run the v3 tests and the comparison (0.0 on every view), and commit. Only then build the next panel on the kit.

---

## 11. Migrating a panel: the steps

1. **Behind a toggle.** Add a `UiPrefs` flag and a `toggle <panel> ds2` cheat (`debug_terminal.gd`). The old look must stay unchanged with the flag off; test that in the panel's test (BDP v3's last checks switch v3 off and assert v2 is back).
2. **Inventory.** List every element of the panel: surfaces, text, numbers, controls, icons, and what each number means. For each, pick a component from §5 or mark it new.
3. **Numbers first.** Before restyling a figure, make sure it's right. Trace it to the engine and quote it with the engine's helper (§8), extracting a shared helper where the engine computes it inline. Prove it against real cash if money is involved.
4. **Shell.** Backing and trim, the raised title, the keys in the header, the seam, the scrollbar, the lamp overlay and text give-back.
5. **Sections.** Frame them with the shared framing (§7.1). Give each a raised heading and choose its surface (steel frame, dark plate, plastic case, white sheet).
6. **Components.** Build each element from the kit. New parts go through the pipeline (§3): a render set with its own seed, the export, a component script, and constants copied from `layout.json`.
7. **Captures and a standard.** Add the panel's views to its shot tool, including edge cases (empty, full, loss, free), and a first standard once approved.
8. **Tests.** Assert behaviour, not looks: what shows when, what opens, the figures and the width discipline.
9. **Docs.** Add the panel's spec (like `bdp-v3-control-plates.md`) and record decisions in its roadmap. Add any new component or pattern to this document.

---

## 12. Traps

Each of these cost time once.

- **A hidden container measures nothing.** `get_combined_minimum_size()` on a hidden PanelContainer or VBox is stale or empty. Keep plates visible and park them out of the clip rather than hiding them.
- **A container insets its children.** A background as a child is inset by the content margins. Paint it in the container's `draw` instead.
- **Rebuilding frees the nodes you held.** After `_rebuild`, earlier references compare equal to `null`, and `if node != null:` silently skips your checks. Look them up again.
- **`set_meta(key, null)` removes the meta.** Use a separate flag.
- **Same-named siblings are renamed after their class** (`@HBoxContainer@N`). Find by meta, not by name.
- **A new `class_name` or an autoload-like global is unknown to a headless run until the editor has scanned it** (`GoodIcons`, `BuildingReadout` in a tool scene). Preload by path.
- **A parse error in a tool scene's script makes the scene idle forever:** it loads without its script and never quits. Check `engine.log` for SCRIPT ERROR. macOS has no `timeout`; use Python's `subprocess.run(timeout=...)`.
- **GDScript runtime errors don't fail a test.** Grep for SCRIPT ERROR, and watch the check count.
- **A `PlaneGeometry` with a plate material renders flat.** `faceTexture` expects UVs in shape pixels. Use `extrude(rrShape(...))`.
- **A canvas blurred with `filter: blur()` fades its edges.** When `steelWindow` repeats it mirrored, the fade shows as a bright seam. Mirror-pad before blurring (`DARK_STEEL_CANVAS`). The backing and the action sheets' steel still carry such a seam, a known issue not yet fixed.
- **Scaling a render up blurs it.** Re-render at the size it draws.
- **Captures can freeze** if the window is hidden or the Mac idles mid-run. Every later view repeats one frame. Check that two views differ, and rerun.
- **The export server on 8771 may be another agent's.** Its posts would write into their checkout. Use your own port.
- **`z_index` pokes through sheets and other panels.** Layer by sibling order.
- **Width creep:** see §7.11.
- **Timing:** tweens need frames. A test waits with `await get_tree().create_timer(t).timeout` before checking a slid position.
