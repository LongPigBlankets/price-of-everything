# Alumina, glass and windows — analysis and build plans (2026-09-07, nothing built)

Written after surveying the goods-icon tooling as it stands on 7 September. This is a plan for
the next agent, not a record of work. References: `assets/icons/goods/medium/g_030_alumina.png`,
`g_038_glass.png`, `g_039_windows.png`.

## 0. What the tooling looks like now (survey)

Three tracks exist and the next agent must pick deliberately:

| Track | Where | What it gives | Used for |
|---|---|---|---|
| **Kit builders** | `blender-assets/goods_icon_kit.py` (copies in `tools/goods_icons/` and the `blender-goods-icons` skill) | `toon_mat`, `setup_icon_rig`, `render_icon` with mask + object-ID passes (`ID_SEPARATION_COLS` gates the seam pass to rock piles), `nugget` (subsurf boulder, grey-cap depth, crease), `mottle_rock`, `blob` (liquids), `sweep_tube`, `cage_loft` (mirrored sectioned cage), `wedge_y`, `bolt_dot`, `ribbon`/`stack_outline`; `icon_export.py` with `--contour`, `--strength`, `--vib` (vibrance), strap outline, ink-distance protect | motor, aluminium, iron ore, coal, the ore batch, crude oil |
| **Material studies** | `tools/goods_icons/material_studies/` (+ `scenes/*.blend`) | `lathe_cage` (revolved quad cage + subsurf), `tube` (bezier curve with bevel), `label` / `face_text` / `curved_label` (FONT → mesh, wrapped on a cylinder), `glass_window_nodes` (binary front-window transparency that also drives the mask), seven-colour ID exporter | limestone, electrical components, ethylene (installed as alternates) |
| **Complex-goods pipeline** | `tools/goods_icons/complex_goods/pipeline.py` + `diesel_car/` seed | frozen rounds (`init` / `round` / `verify`), `project.json` with reference roles, ≥4 named crop regions, owner rulings, per-good contour and vibrance, camera assertion, pixel-exact repeat verification | diesel car + jerrycan (installed alternate) |

Also in force since the handoff: rules 54–65 (ore recipe, vibrance), 66–71 (one fixed isometric
camera, world axes as the drawing grid, 90° objects stay 90°, parallel-edge review gate,
fail-fast camera check) and 72–73 (Godot import contract, mipmaps in every tier) in
`blender-goods-icons`; `assets/icons/goods/alternate_icons/approved_manifest.json` records
installs; main tiers beat alternates in `scripts/good_icons.gd`.

Two facts that shape these three goods:
- **The sand sacks exist only as a `.blend` checkpoint** (`artifacts/goods_simple_batch/repeat_v15/sand.blend`), not as a code builder. The alumina sack cannot reuse a sack function; it should be authored in code (reproducible, rule 35) and can become the first shared sack helper.
- **Text on goods is solved twice**: ammonia (`NH3` FONT → mesh, subdivided and wrapped on the cylinder) and ethylene (`curved_label`). Alumina's `Al₂O₃` and the windows' nothing; glass has no text.

## 1. The references, measured

| Good | Composition | Palette (sRGB, top shares) | Ink and halftone | Camera fit |
|---|---|---|---|---|
| **Alumina** 1712×1902 | one upright kraft-paper sack, open top with a folded cuff, filled to the brim with white spheres; a white label "Al₂O₃" on the front-left face; vertical crease lines; halftone on the sack's right flank and inside the cuff | kraft 160/120/80 (22%), white 248 (15%), kraft shadow 128/96/64 (12%), kraft highlight 184/152/120 (5%), navy | every sphere outlined; sack edges bold; halftone on sphere shadow sides and the sack's right face | near-square; sack is an orthogonal box with bulged sides |
| **Glass** 1448×1860 | a standing pane behind, a corked green bottle in front-right; the pane shows its thickness on the left edge and two diagonal white highlight streaks; the bottle has neck rings, a liquid level line and a darker lower body | pane cyan 176/216/216 (41% across three near-identical shades), bottle olive 112/144/112 (9%), highlight 208/248/240, navy | halftone across the pane's right half as a screen gradient (not lighting), bottle right side stippled | portrait; pane is an orthogonal thin slab |
| **Windows** 1588×1839 | a double casement: outer frame, left leaf closed, right leaf swung open toward the viewer about its right-hand hinge; 2×3 panes per leaf; handles on both leaves; frame depth faces shown as stippled paper | cream 232/232/224 (33%), glass blue 144/176/200 (10%), navy | thin ink on every frame edge, mullions and pane rebates; halftone on frame depth faces and on the glass | near-square; almost entirely orthogonal, one rotated sub-assembly |

## 2. Symbol ranking (recognisability vs the shipped icon's confidence)

**Alumina.** Keep the sack with the formula label. The label does the recognising; nothing else
distinguishes a white powder from salt, lime or sugar. Alternatives: a white heap (reads as sand
or limestone, and the new sand icon is already a heap with sacks); loose white pellets (reads as
bauxite's cousin); a bulk bag. Ranked: labelled sack > labelled bulk bag > pellets > heap. One
constraint the reference did not have: the installed sand icon is a heap plus tied sacks, so
alumina must be a **single upright open sack with white contents and the label**, or the two
goods collide at 64 px.

**Glass.** Keep pane plus bottle. The pane alone reads as a mirror or a tablet, the bottle alone
as a chemical or a drink; together they read as "glass". Alternatives: a stack of panes on an
A-frame stillage (strong for "glass sheets", orthogonal-friendly, but loses the bottle's
household cue); pane plus jar. Ranked: pane + bottle > pane stack on a rack > bottle + jar.
The pane is the hero; the bottle overlaps its lower-right corner.

**Windows.** Keep the casement with one open leaf. Alternatives: a stack of window units (reads
as frames or pallets), a window set in a wall (reads as a building). Ranked: open casement >
stack > wall. The open leaf is the recognising cue and must stay.

## 3. Build plans, in D

### 3a. Windows — orthogonal assembly, rules 66–71 apply directly. Build this first.
D = outer frame width. Reference ratios: height 1.16 D; frame member 0.055 D; frame depth
0.10 D; leaf width 0.44 D; leaf height 0.98 D; pane rebate 0.025 D; 2 columns × 3 rows.
**OWNER (2026-09-07): open the leaf PERPENDICULAR to the frame and lean on the isometric
view.** At 90° the open leaf lies along the other world diagonal, so every edge in the whole
assembly belongs to one of the three axis families and the rule-70 parallel-edge gate applies
to all of it, open leaf included. No rotated sub-assembly, no 55° compromise.

- Everything is `K.box`: outer frame (four members), closed leaf (four members + one vertical
  and two horizontal mullions), six glass panes sunk 0.02 D into the leaf, handles (a box plus
  a short `sweep_tube`). The open leaf is the same leaf built with its long axis along −Y
  instead of X (a 90° Z rotation about the hinge line, rule 69's "90° increments"), standing
  proud of the frame toward the viewer from the right-hand hinge. Its panes then face −X, its
  handle faces the camera's left; the frame's right jamb is partly hidden behind it. The
  review gate (rule 70) applies to the whole assembly.
- The sprite kit's `window()` assembly is for building faces (it adds a sill and sits proud of a
  wall face); do not use it. A dedicated `casement_leaf(K, name, origin, w, h, cols, rows, depth)`
  returning its parts is the helper to write.
- Tones: cream toon base calibrated so the lit face lands at ~232 and the depth faces at the
  reference's ~190; glass a pale blue toon (~176 lit). The frame's depth faces in the reference
  are stippled paper: the mask pass gives them the shadow step naturally on the +X and
  underside faces; the vertical left return of the frame is lit in the reference, so light
  direction stays overhead-front.
- Ink: mullions must be at least 3× the interior ink width or they fill in. At 800 px the
  mullion is ~14 px and interior ink ~4.7 px, so this holds; check at 256 px (very_small),
  where the mullion is 4.5 px and the ink must not render as a solid bar. Consider `ink_fine`
  for pane rebates.
- Halftone on glass: the reference stipples each pane with a fine dot on its lower half. A flat
  vertical pane facing the camera gets one mask value, so the dots would cover the whole pane
  or none. Either accept clean glass (defensible, poster-flat) or add the export feature in §5.
- ID pass: not needed; the open leaf's silhouette separates it from the frame.
- Likely traps: the open leaf's glass panes must stay inside their rebates after rotation
  (rotate the parts, not the finished positions); the handle on the open leaf is rotated with
  it; hinge side edges of the open leaf touch the frame (overlap 0.03, rule 33).
- With the leaf at 90°, check that the open leaf's projected width (0.44 D along the −Y
  diagonal, foreshortened to ~0.38 D of screen width) still reads as a leaf and not a slab: at
  64 px this is ~20 px, enough for the 2×3 grid to survive as texture.
- Rounds: two or three. Review emphasis: C5 (thin mullion ink), C8 (rebates closed), C10 (the
  open leaf still reads at 64 px), the rule-70 parallel-edge check on ALL parts.

### 3b. Alumina — a lofted soft body full of spheres, with a text label. Hardest of the three.
**OWNER (2026-09-07): open sack, label on it, pellets visible.** The sealed-sack shortcut is off.
D = sack width at the cuff. Reference ratios: sack height 1.05 D to the cuff; cuff fold 0.12 D
deep, rolled outward; body bulge 0.06 D per flank; base slightly narrower (0.92 D); label
0.42 D wide × 0.25 D tall, centred at 0.45 D height on the front-left face; sphere radius
0.075 D; fill surface at 0.98 D with the top layer proud.

- Sack body: not `cage_loft` (its sections run along Y and mirror across X, which makes a car,
  not an upright bag). Write `ring_loft(K, name, rings)` where each ring is a closed list of
  (x, y) points at a z, lofted with quads, with a Subdivision Surface and crease rings; a
  rounded-rectangle ring (superellipse, n ≈ 4) at eight or nine heights gives the kraft sack:
  base ring 0.92 D, mid rings bulged to 1.06 D, cuff ring folded outward to 1.12 D then back in
  to 0.98 D for the inner lip. Orthogonal base (rule 68) with the bulge expressed only through
  the rings. The cuff's fold line takes a crease so it inks.
- Creases and folds: the reference's vertical crease lines are ink, not geometry; use
  `freestyle_edge` marks on chosen loft edges (thin `ink_edge` lineset) rather than tubes, and
  keep them to two or three per visible face.
- Spheres: a Fibonacci-lattice cluster (the bauxite builder holds this code inline; lift it into
  a `pellet_cluster(K, name, bounds, r, seed)` helper) of smooth icospheres, level 2, filling
  the sack's inner ring to a slightly domed surface, jittered 15% in radius and position,
  seeded. Each sphere is its own mesh so Freestyle outlines it; the sack's inner lip occludes the
  ones below the rim. Where spheres touch, the ID separation pass draws the seam: add the
  collection to `ID_SEPARATION_COLS` but only for the spheres (the sack itself must not seam
  against the pellets; the pass is per top-level object, so either tag sack faces out of it or
  render the pellets' ID pass from a sub-collection).
- White tones: emissive flat white for aluminium rods was right because the reference rods are
  flat; these spheres are shaded with stippled shadow sides, so use a toon white (lit 248, mid
  ~215, shadow ~185 with dots), like the windows' cream.
- Label: `label()` from the material studies (FONT → mesh on a white patch) aimed along the
  front-left face normal, not toward the camera; the patch is a thin box proud by EPS with a
  navy border ring. Subscript digits: Blender's default font renders "₂" and "₃" (Unicode
  subscripts) if the font has them; the ammonia builder used plain "NH3" with a smaller third
  glyph — replicate that with three text objects (Al, 2, O, 3) at two sizes rather than relying
  on Unicode glyph coverage.
- Halftone: sack right flank and the inside of the cuff carry dots in the reference; the mask
  pass handles both. Spheres: the shadow step on each sphere's lower-right.
- Likely traps: the cuff's inner lip must be a separate ring so it reads as a rolled edge
  (a single ring folded back reads as a flat band); the sack's front face must stay near-planar
  or the label warps (keep the bulge to the flanks); crowding — 60 to 80 visible spheres each
  with a silhouette produces a lot of ink, so the sphere outline must be the thin class and the
  sack's outline the bold one (C5 hierarchy).
- Rounds: four or five. Review emphasis: C5, C9 (silhouette crowd), C10 (does the sack read
  as a sack, not a box), C12 (formula legible at 256 px; at 64 px only the sack and white
  contents survive, which is acceptable).

### 3c. Glass — two objects, one flat, one revolved, plus an export gradient.
D = pane width. Reference ratios: pane 1.0 × 1.32 D, thickness 0.035 D, standing upright on
its long edge with the thickness face on the left; bottle height 0.80 D, body diameter 0.30 D,
shoulder at 0.55 D, neck 0.11 D diameter, cork 0.09 D proud, bottle centred at (0.62 D right,
0.15 D forward) so it overlaps the pane's lower-right corner; liquid line at 0.30 D from the
base.

- Pane: one `K.box`, orthogonal (rule 68), pale cyan toon; the thickness face gets the lit step
  automatically if it faces −X… it does not: the left return faces −X, which the overhead-front
  sun leaves in the mid step, and the reference draws it lighter than the face. Give the return
  its own material (a lighter cyan) rather than fighting the light.
- Highlight streaks: two thin white parallelograms proud of the pane by EPS, `noink`, angled
  along the pane's diagonal (a `decal_streak` helper: a flat quad in the face plane). Not
  geometry the rules cover yet; note it as an addition.
- Bottle: `lathe_cage` from the material studies with a profile (base, body, shoulder, neck,
  lip), olive toon; cork as a short tapered `K.cone` in a warm tan; neck rings as `seam_ring`
  navy bands; liquid line as a navy `tube` ring at 0.30 D; upper body in a lighter olive
  material so the level reads (the reference is opaque, so no transparency: avoid the BLENDED
  alpha route and its rule-21 traps; `glass_window_nodes` is optional and adds risk for no
  gain here).
- Halftone on the pane: **OWNER (2026-09-07): CLEAN pane, with the lighting streak on it.**
  The reference's screen-gradient dots on the right half are dropped; the pane carries its
  three tones (face, lighter return, white streaks) and no stipple. The pane object needs an
  explicit mask exclusion (the wheel precedent: `pass_index` read by the mask override, or a
  `noink`-style tag) so the flat face never crosses the stipple threshold. The per-object
  gradient-stipple export feature is therefore NOT required for glass; it stays on the list
  only as a future option.
- ID pass: not needed; the bottle is in front and its silhouette closes.
- Likely traps: the pane's top edge is a long straight ink line that must be exactly on the
  isometric diagonal (rule 67) — measure it against the aluminium pallet's edges; the bottle's
  cork must not be coplanar with the lip (rule 26); the bottle silhouette against the pane will
  be the bold contour, so `--contour` needs calibrating on the reference (its outline reads
  slightly lighter than the motor's).
- Rounds: three or four. Review emphasis: C1 on the pane (three tones: face, return,
  highlight), C6 (bottle proportions), C9 (streak decals must not ink), the rule-70 edge check.

## 4. Order and budget

1. **Windows** first: it exercises rules 66–71 on a good that is 95% boxes, and its helper
   (`casement_leaf`) is reusable for building sprites later. Two to three rounds.
2. **Glass** second: a clean pane with streak decals and a lathed bottle. Two to three rounds
   now that the gradient halftone is off the table.
3. **Alumina** last: needs `ring_loft`, `pellet_cluster`, the label with two text sizes, and a
   sub-collection ID pass. Four to five rounds.

## 5. Helpers and features to add (none exist yet)

| Addition | For | Notes |
|---|---|---|
| `casement_leaf(K, name, origin, w, h, cols, rows, depth, glass_mat, frame_mat)` → parts list | windows | returns parts so the open leaf can be rotated as one assembly about its hinge |
| `ring_loft(K, name, rings, mat, levels=2, crease_rings=())` | alumina sack; later drums, jars, bags | closed rings at successive z; superellipse ring generator alongside |
| `pellet_cluster(K, name, bounds, r, seed, jitter)` | alumina; reusable for pellets, gravel, balls | lift from `build_bauxite_ore` |
| `decal_streak(K, name, face_plane, p0, p1, width, mat)` | glass pane highlights; later any glint | thin noink quad in the face plane, proud by EPS |
| Mask exclusion tag for a whole object (pane) | glass; any flat face that must stay clean | reuse the diesel wheel `pass_index` contract |
| (deferred) per-object gradient stipple | screen-gradient halftones | not needed now that the pane is ruled clean |
| Text label with mixed glyph sizes (subscripts) | alumina; later any formula label | three FONT objects, ammonia precedent |
| ID pass on a sub-collection | alumina pellets vs sack | today the gate is per collection name |

## 6. Review criteria additions for these three

Beyond C1–C12: (W1) parallel-edge families on frame and closed leaf within 1 px over 100 px;
(W2) mullions unfilled at 256 px; (G1) pane shows three tones (face, return, streak) and the
streaks carry no ink; (G2) bottle proportions in D within ±10%; (A1) sphere outlines are the
thin class and the sack outline the bold class, measured; (A2) the formula reads at 256 px;
(A3) at 64 px alumina and sand are distinguishable side by side.

## 7. Owner rulings (2026-09-07) — the questions are settled

- **Alumina:** open sack, with the label, pellets visible.
- **Glass:** the pane carries the lighting streak; the pane is CLEAN (no halftone). The
  gradient-stipple export feature is deferred.
- **Windows:** lean on the isometric view; the open leaf is PERPENDICULAR to the frame (90°),
  so every edge sits on a world-axis family and the parallel-edge gate covers the whole icon.
