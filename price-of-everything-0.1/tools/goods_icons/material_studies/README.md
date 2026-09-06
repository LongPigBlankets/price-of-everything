# Approved Blender goods icons

The committed `scenes/` folder contains all five approved editable Blender scenes.
Coal and iron ore are installed in the game's default medium/small/very_small tiers.
All five goods are available in `assets/icons/goods/alternate_icons`, with checksums
in `approved_manifest.json`. Original coal/iron art is retained under
`artifacts/goods_material_studies/original_icons` for reference comparisons.

Historical render directories mentioned below are local iteration records, not part of
the release. Rebuild fresh output using the scripts in this directory. The current
builders reproduce the approved coal and iron ore; `scenes/` captures the other three
approved scenes as well. Experiments and unrelated project changes are not included.

# Limestone, electrical components, ethylene

Editable Blender studies for the goods-icon replacement project. Latest previews and
scenes are in `artifacts/goods_material_studies/palette_refinement/`. The preceding passes
remain in their version folders. PNG alternatives are stored in
`assets/icons/goods/alternate_icons/`, without changing the default runtime selection.
The newest electrical-only pass is in `artifacts/goods_material_studies/switch_reference_refinement/`:
the switch is rebuilt from a close-up of the original, with a recessed upper root, short
folded tip, visible end face and constant 0.145D width. It preserves copper strands, 0.01D
inset borders and 0.009D cable-base seams. Up-facing yellow uses the lit tone; forward-facing
yellow uses 0.86 of its linear intensity. The folder includes the original/refined close-up.

## Reference analysis and symbol choice

The existing goods art describes objects through broad silhouettes, navy outlines, stepped
colour and shadow halftone. Its perspective is illustrative rather than mechanically exact.
Each model therefore uses the shared orthographic rig, with geometry simplified for 64 px
legibility. The 800 px files preserve detail for larger displays.

| Good | Ranked symbols | Chosen representation and construction |
| --- | --- | --- |
| Limestone | 1. Layered cream chunks (existing language); 2. single broken slab; 3. aggregate heap | Seven asymmetric chunks, including two added on the right. Quad cages soften corners; cream, chalk, ochre and buff materials define the strata. Seven-colour object-ID pass separates overlaps. |
| Electrical components | 1. Breaker, lamp and wire (existing language); 2. relay/terminal assortment; 3. circuit board | Yellow enclosure, dark backing rail, recessed bent paddle switch, caged bulb and socket. The bulb cable rises vertically before curving. A separate side gland supplies the lowered analog voltmeter with a third cable; both cable routes remain visible. |
| Ethylene | 1. Formula-labelled flask (existing language); 2. formula-labelled industrial cylinder; 3. molecule diagram | Revolved quad cage, pale glass mouth, cylindrical paper label and wrapped C₂H₄ glyphs. A continuous liquid mesh and its coloured planar cap share one circular boundary. A clear front window exposes the liquid while retaining the pale rear glass and silhouette border. This preserves the existing chemistry symbol; it is not a physical simulation of chemical storage or refraction. |

Latest limestone luminance peaks: approximately 215/185/141, bringing the dominant cream
closer to the reference's 215. The reference electrical icon informed the brighter yellow
enclosure (214 luma), beige bulb and warm grey cables. Liquid top and body peaks are now
approximately 198 and 182 instead of the previous brighter cyan treatment.

## Outputs

Each good has a `.blend` scene with named parts, camera, lighting and editable subdivision
modifiers; colour/mask raw renders; and transparent 800, 450, 256, 128 and 64 px PNGs.
`comparison.png` shows original art, candidates and actual 64 px samples on light/dark fields.
`lineup.png` shows the three new goods alone.
The colour key is removed only for the reference comparison; original assets are untouched.
`metrics.json`, `review.md`, `regions_3x.png` and `verification.json` document checks.

## Rebuild

From the game directory (`price-of-everything-0.1`):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python tools/goods_icons/material_studies/render_studies.py \
  -- artifacts/goods_material_studies/rebuild limestone electrical_components ethylene
python3 tools/goods_icons/material_studies/export_studies.py \
  artifacts/goods_material_studies/rebuild
```

Blender 5.2 and Python with Pillow/numpy were used. On macOS the graphics runtime may require
running Blender outside a restricted process sandbox. Paths in the comparison exporter use
the system Helvetica font. Rendering itself has no network dependency.

`goods_icon_kit.py` is the authoring file: `build_limestone`,
`build_electrical_components`, and `build_ethylene` return `sprite_kit.Kit` instances.
`base_kit.py` and `sprite_kit.py` are frozen copies of the current project helpers; this study
does not alter the ongoing diesel/jerrycan work. The local exporter fixes seven-colour ID
decoding and preserves alpha when centring the render. Strap detection is disabled for these
three goods so dark cable tones do not acquire spurious interior outlines.

Geometry is authored for the supplied icon camera. The bulb filament is an illustrative
surface detail. The liquid rim follows the actual cap circumference. The glass-front window
is deliberately binary, preserving flat poster colours; the shading-mask pass applies the
same window so the liquid top remains correctly lit and free of shadow dots.
The text is converted to mesh for consistent framing and mask passes; edit the formula in
the builder and rebuild. `.blend` files preserve the rounded body cages and scene materials.
The full poster finish (outer contour and halftone) comes from the export pass, so a direct
Blender render will differ from the finished PNG.

## Iteration record

- v1: initial forms; review identified cable zipper lines, stone crease stubs, short neck,
  excessive outer ink, and missing liquid-surface definition.
- v2: suppressed cable crease ink and generic rock creases; lengthened neck; legible filament.
- v3: stronger bedding marks, restored manufactured seams, formula fitted to its plate.
- final: lighter outer ink, yellow housing side, and authored meniscus curve.
- refined: seven stones with coloured strata, wrapped label, real liquid volume and cap,
  glass-coloured mouth, vertical cable exit, third cable, voltmeter and shaped switch.
- palette_refinement: closer reference colours, bent switch stem, lower voltmeter, side
  gland with straight cable exits, and alternate-icons folder requested by the owner.

These are first representations for visual review, not a claim of exact reference matching.
The existing reference has more hand-drawn asymmetry and optical highlights. The current
flask uses a simpler pale glass border. The smallest thumbnails communicate a good category;
the chemical formula and fine bedding naturally require larger display sizes.

## Coal and iron ore — fracture rebuild

Latest: `artifacts/goods_material_studies/ores_bottom_heavy_v2/`. The owner rejected
v3's simplified forms, excessive grey and rudimentary coal. Those versions remain
historical comparisons, not recommended candidates.

`ore_builders.py` now uses seeded noisy polyhedra, multiple actual plane cuts,
secondary fracture relief and narrowly bevelled edges. It does not call the
limestone or rejected ore ring-cage builder. Broad regions have explicit planar
triangles; fine changes in facet direction are defined by colour, with ink reserved
for stronger turns and grey/rust boundaries. The saved meshes and modifiers are
editable. The rejected cage source is preserved separately for historical rebuilds.

The supplied coal illustration informs irregular fractures, but the palette remains
restrained charcoal and muted blue-grey. The realistic iron photos inform angular
fracture topology only: rust red remains dominant, and approximately 30% visible
grey is the acceptance target from the shipped good icon. Coal's pile has a broader
hero, asymmetric flanks and three small broken fragments. Iron retains three large
chunks with multiple smaller fracture faces and selective pale highlights.

Both rank the shipped symbol first: coal chunks over sacks/carts; rust-and-grey
ore over pellets/magnets/mining equipment. The approved limestone, ethylene and
electrical assets in `alternate_icons` are separate from these review candidates.

Rebuild using `render_studies.py -- OUTPUT coal iron_ore`, then
`export_ores.py OUTPUT`. Each output contains editable `.blend` scenes, raw
colour/mask/object-ID passes, transparent 800/450/256/128/64px PNGs, comparison and
preview sheets. `*_geometry.json` reports control/evaluated face counts; review
and verification files record measured coverage, visual checks and repeatability.

Final measured visible iron grey:30.4% (shipped reference29.4%; rejected v3:61.4%).
Coal blue-grey:24.0% (reference22.3%). Control mesh totals:coal805 faces,
iron485 faces; evaluated with edge bevels:coal2944 and iron1598 faces.
All ten transparent exports reproduce pixel-identically in a clean Blender run.
The resulting finish remains more geometrically regular than the drawn references.

## Bottom-heavy revision

Owner request: widen lower bodies, reduce top weighting, simplify little coal to
five–seven faces, and give broad faces more fracture relief. The pre-cut rock volume
now tapers from1.55 at its bottom to0.60 at its crown. A plane trims the pointed bottom
into a broad support, excluded from subsequent surface relief. Actual bases are placed
on the ground. Secondary ridges now project0.14–0.22 radii, making adjacent face angles
more distinct. Coal chips are plain triangular, quadrilateral and pentagonal prisms
with exactly5,6,7 mesh faces respectively, without bevel or subdivision modifiers.
Iron cuts are slightly shallower to preserve the established roughly30% grey target.
Previous fracture versions remain historical candidates; approved game assets unchanged.

Verified lower-quarter cross-section areas are1.84–3.10 times upper-quarter areas;
each main mesh has one horizontal bottom face. Final visible iron grey31.8%, coal
blue-grey23.2%. All ten PNGs remain reproducible from a clean render.

## Approved coal installation and hematite material experiment

Coal from `ores_bottom_heavy_v2` is approved and installed in both default and
alternate medium/small/very_small tiers. Original game coal is backed up in
`artifacts/goods_material_studies/original_icons`, and comparisons continue using it.
The alternate manifest records approved hashes and default installation status.

Latest iron experiment: `artifacts/goods_material_studies/hematite_streaks_v4`.
Only the large rear rock changes. Its geometry and bottom weighting remain identical;
the smaller rocks retain their old grey patches as visual controls. The material uses
rotated object-relative generated coordinates, followed by an anisotropic stretch;
thresholded noise creates metallic ribbons and a separate coarse field breaks their
continuity. Rust, metal grey and sparse pale highlights then receive the same toon
lighting as the original material. This is a surface material, not layered limestone
geometry. Pattern parameters remain editable in the .blend node tree and builder.

The attached hematite photograph informs broken metallic directions, not photographic
surface noise or gloss. This experiment intentionally presents one-rock comparison
before extending the material across the pile. At tiny sizes only larger streaks survive.

## Facet-edge hematite refinement

Latest iron: `artifacts/goods_material_studies/hematite_edge_seams`. The owner liked
the right-hand hero streaks and asked for less simplistic left streaks that follow
facet edges. The original streak material remains assigned to the right-hand polygons.
Left polygons use a separate shader that measures actual 3D distance to selected long
fracture edges, varying seam widths with fine noise and interrupting them with a coarse
mask. Sparse pale cores provide ridge glints. This uses fourteen selected edges, not a
wireframe around every triangle. No geometry, other rocks, or installed coal assets change.
The saved scene preserves editable edge-seam nodes; rebuild to update selected edge
coordinates after changing the control mesh geometry.

## Crown streak and foreground ink

Latest iron: `artifacts/goods_material_studies/hematite_crown_refinement_v2`.
One short tapered silver streak now lies on a top-facing central crown facet.
The foreground nugget uses its own internal-edge line set:1.7px rather than3.8px,
with an8% tip/85% centre taper. The other ink passes exclude this nugget so they do
not redraw thick internal diagonals. Its outer contour and overlap separation
remain supplied by the normal PNG alpha/object-ID exporter. Other streak material
and all control meshes remain unchanged. The saved .blend preserves these line sets.

## Restored crown patch

Latest iron: `artifacts/goods_material_studies/hematite_restored_crown`. Restores
the irregular crown patch from the earlier `hematite_streaks_v4` material on the
topmost facets, replacing the recent isolated diamond-like streak. The edge-following
left seams and thin foreground linework remain. The rendered lower half is unchanged.

## Wider left seams and reduced ink

Latest iron: `artifacts/goods_material_studies/hematite_wider_left_seams`.
The left seam distance threshold and pale-core width are exactly1.5 times the
previous values. Noise and gap placement remain the same. Marked interior edges
on the left below the restored crown are suppressed, allowing metallic seams
to define more of those boundaries. The right-hand material, crown restoration
and foreground fine lines remain. PNG dimensions and unaffected regions are
checked in verification.json.

## Iron ore approved and installed

The `hematite_wider_left_seams` render is approved as the runtime iron ore icon.
Its exact PNGs are installed in all three default tiers and alternate tiers.
