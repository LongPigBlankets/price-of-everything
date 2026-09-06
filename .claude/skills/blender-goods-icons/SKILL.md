---
name: blender-goods-icons
description: Load this to create, revise, validate, or ship a GOODS ICON for Carbon and Capital in Blender. Covers the measured poster style, fixed true-isometric camera, shared rectilinear perspective, geometry rules, mipmapped Godot texture imports, the 2D export pass, and the mandatory adversarial-review loop.
---

# Goods icons in Blender — the style rules

Carbon and Capital goods icons: "midcentury industrial poster / WPA catalogue". Every rule below was
either measured on the shipped icons, ruled by the owner (marked OWNER), or paid for with a wasted
render on 2026-09-03 (marked TRAP). Scripts: `goods_icon_kit.py`, `render_icons_headless.py`,
`icon_export.py` in this folder. Reference icons: `g_008_motor.png`, `g_029_aluminium.png`,
`g_056_ice_car.png` under `assets/icons/goods/medium/`.

For complex vehicles, equipment and engines, also read the
[car/jerrycan case study](../blender-goods-build-review-loop/references/car-and-jerrycan.md)
and use the [reproducible complex-goods pipeline](../../../price-of-everything-0.1/tools/goods_icons/complex_goods/README.md).
It preserves the approved sedan/can source and pairs the original goods art with real-world
geometry references. Keep the fixed production camera; side/front diagnostic views may differ.

## 1. What the style IS

1. **An inked poster, not a render.** Form is described by flat tone steps and ink, never by a
   gradient. If a surface shows a smooth ramp, the icon is wrong.
2. **Three flat tones per material**: lit, mid, shadow. Measured on the reference: teal barrel
   ≈ 168 / 132 / 92–112 luma. Steps are ~35 luma apart; closer than that reads as one muddy tone.
3. **One warm accent per icon** (the motor's yellow box, the jerrycan's red). Everything else is
   the desaturated teal/steel/slate family, or white where the good is white.
4. **Halftone is shading, only on the shadow step.** Dots ~6 px at 800, pitch 12–16 px, navy at
   ~40% opacity, constant size. Lit and mid faces stay clean. All-over halftone is rejected (OWNER).
5. **Ink is one navy**, sRGB ≈ (20, 28, 60): outer contour 1.1–1.8% of the long side (motor 15 px,
   aluminium 9 px at ~830), interior lines 0.4–1.5% (6–12 px), thin class ~0.5× for bolt holes and
   rings. Outer : interior ≈ 1.7 : 1. Line ends rounded; every join closed.
6. **Goods shading is gentler than building shading** (OWNER): shaded face ≈ 0.65× the lit face,
   not the sprites' 0.33×.
7. **Subject fills ~92% of a transparent square**, 4% margin each side, 800² delivered, small and
   very-small derived from it.

## 2. Camera and rig

8. True-isometric orthographic camera, rotation (54.736°, 0, 45°), the sprite rig. Frame from
   PROJECTED extents (`frame_collection`), never from the plan: target = centre of the
   projected column/height ranges, ortho_scale = larger range × 1.12.
9. Screen vocabulary: "front" = −Y (lower-left), "back" = +Y, "right" = +X (lower-right),
   "left" = −X. Shafts, rod ends and vehicle noses face −Y.
10. **Standard view transform, never AgX** (TRAP). AgX caps white at 176 and yellow at 180/154/73;
    the icons need 248 and 224/192/64.
11. **Force the light to a SUN** (TRAP: a factory scene's "Light" is a POINT light and every face
    renders identical). Direction (−0.30, −0.62, 0.72): top brightest, front lit, right shaded.
    World white at 0.58, sun 1.6.
12. **Disable the factory "LineSet"** (TRAP: it draws every interior line black over ours).
    Only `ink`, `ink_fine` and (disabled) `contour` may render. Freestyle colour is
    linear-referred: INK (0.006, 0.012, 0.045) → (20, 28, 60).
13. Freestyle `ink` 6.0 px at 1024, `ink_fine` 2.6 px, crease angle 150° (so a 10-sided prism
    inks its facet edges but a 48-segment cylinder does not). The 7 px external contour lineset
    is OFF: the outer line is synthesised in 2D.
14. Never depend on saved .blend state. `setup_icon_rig()` is idempotent and runs at the top of
    every builder; render headless with `--factory-startup`.

## 3. Materials and tone

15. **Every lit material is a toon material** (`toon_mat`): white Diffuse → Shader-to-RGB →
    CONSTANT ColorRamp (0.32 / 0.60 / 1.0 at s < 0.66 / < 0.92) × base colour → Emission.
    No Principled, no roughness, no specular, no gradient.
16. Calibrated bases under that rig: teal (0.34, 0.44, 0.44), teal-dark (0.24, 0.32, 0.32),
    yellow (0.90, 0.62, 0.06), steel (0.40, 0.50, 0.54), silver (0.62, 0.66, 0.70). Re-calibrate
    with a swatch render before adding a colour; do not eyeball a linear value.
17. **Flat white goods are EMISSIVE** (aluminium rods at 0.86): unlit, so they carry no gradient.
    The mask pass still places their shadow-step stipple.
18. Openings, bores, slots and seams are `ic_navy`, unlit, the ink colour: they read as drawn
    holes, not as dark surfaces.
19. The shading mask is a second pass with a material override emitting 0.5 + 0.5·dot(N, L),
    linearised in export ((v/255)^2.2). Stipple where lit < 0.56. Never key the stipple off luma
    (TRAP: that dots every mid-tone body).

## 4. Geometry — how form must be built

20. **Round bodies are faceted prisms when they carry plates or fins** (motor barrel: 10 sides,
    flat-shaded). Pure drums (cowls, flanges, shafts, rods) are 48-segment smooth cylinders and
    take their form from the tone steps.
21. **Faces the owner calls flat are flat** (OWNER): a motor's drive end is a flat plate with a
    proud ring, not a cone or dome. Round-overs belong to the reference only where it draws them.
22. **Bold covers and rings**: a proud rim (r × 1.15, 0.12 deep) plus a drum, never a single
    disc. A step that is under ~0.08 D deep does not read.
23. **Stepped silhouettes**: adjacent drums differ in diameter (motor: cowl 1.15 D > flange
    1.15 D > barrel 1.0 D > cover 0.46 D > shaft 0.2 D). Equal diameters make a sausage.
24. **Proportions in D** (the main body's diameter): motor body length 1.15 D; terminal box
    0.57 D wide × 0.60 D long × 0.32 D tall, front-mounted; shaft 0.5 D long, 0.2 D thick.
    Write every dimension as a ratio of D so an icon can be rescaled without re-judging it.
25. **Plates run INTO their neighbours.** Fins, side plates and pads overshoot 0.03–0.06 into the
    flange, the cowl, the barrel. A plate that stops short shows a sliver of daylight and reads
    as glued on.
26. **Sink every ring 0.04 into the next** (TRAP: coplanar rims z-fight and Freestyle draws the
    circle as dashes).
27. **A pad under an accessory runs the full length of the surface it sits on** (OWNER: the motor
    box pad goes back to the rear face), and its bottom is buried below the curved surface at
    the pad's edges, or a daylight rail appears under it.
28. **Legs are splayed wedges** (OWNER): wide at the base plate, narrow at the body, with a solid
    angled skirt between them (`wedge_y`). A leaning thin plate reads as an X; vertical posts
    read as a bench.
29. **Bolt heads are un-inked navy discs** (`bolt_dot`, face-marked) (TRAP: tiny inked
    cylinders draw as broken C marks). Real bolts get no geometry of their own.
30. **Accessories match their host's accent and seam to it** (OWNER): cable glands are the
    box's yellow with a navy seam ring where they meet the box and a bore at the tip.
31. **Straps and bands are convex-hull paths** (`stack_outline`): a tensioned strap does not dip
    into valleys. Build them with real thickness, face-marked so Freestyle ignores them (TRAP:
    the silhouette flickers segment-by-segment on a near-edge-on strip), and outline them in 2D.
32. **Hex-pack cylindrical goods 4-5-4** (OWNER), ends to the camera, on a wooden pallet with
    bearers and deck boards whose ends show like the rods' discs.
33. Nothing may float: every part touches or overlaps another by ≥ 0.03. `K.validate()` before
    every render.
34. **Polygon budget is not the constraint** (OWNER): 48-segment rounds, 180-sample hulls, real
    thickness everywhere. A headless colour + mask pass is ~10 s per icon.
35. **Never let `hash()` or unseeded `random` reach geometry.** Bake twice, expect identical
    pixels.

## 5. Export (2D pass, `icon_export.py`)

36. Alpha-crop at 1024, then synthesise the outer contour: morphological CLOSE by r, DILATE by r,
    fill the ring with ink. r = 1.3% of the long side for a motor-class icon, 1.1% for a
    simple bundle. Slots narrower than the line get no line.
37. Blend the render's anti-aliased edge toward ink by its missing alpha (TRAP: otherwise a
    bright hairline sits inside the contour).
38. Un-inked regions (straps) get a 2D outline: detect by their neutral dark colour with a tight
    hue tolerance (navy fringe is blue-biased), erode-dilate to drop slivers, ring at 0.45%.
39. Stipple from the mask: one band (lit < 0.56), pitch 1.5% of the long side, dot radius 0.36%,
    ink at 0.42 opacity, never on pixels darker than 80 luma or on the contour.
40. Resize LANCZOS to fit 92% of an 800² canvas, centre, transparent background. Derive
    small/very_small from this file, never from the raw.

## 6. Process

41. **Adversarial review is mandatory before the owner sees an icon.** Spawn a reviewer with the
    reference and candidate paths and this exact question: "why does the reference read as an
    inked poster and the candidate as a 3D render — the five or six STRUCTURAL causes". Require
    same-region side-by-side crops at 3× and measurements: L/D, cowl/D, flange/D, box % of bbox,
    tone-step histogram peaks, line-width p50/p90, halftone by face. Nit-hunting prompts waste
    a round.
42. Fix in ONE consolidated pass per review, re-render, re-review. Two to three rounds is normal.
43. **The owner overrules the reviewer.** Keep a list of owner rulings (4-5-4 pack, raised feet,
    flat face, box size) and reject reviewer findings that contradict them.
44. Verify claims by measuring pixels, not by looking (TRAP: "the ink is black" was true and
    invisible at thumbnail size; "dots on lit faces" was a threshold error found by histogram).
45. Zoom crops at 3× NEAREST of at least four regions before declaring a render done.
46. Never install into `assets/icons/goods/` without the owner's eye on the 800² file.
47. Every new icon is a `build_<good>()` in `goods_icon_kit.py` over `sprite_kit.Kit`; its
    dimensions in D, its accent named, its owner rulings in the docstring.

## 7. Added 2026-09-03 (round six): cages, nuggets, light

48. **Light is overhead-front** (0.06, −0.56, 0.83): top lit, UPPER flank mid, LOWER flank shadow.
    A side-front light (the old −0.30, −0.62, 0.72) turned a barrel's whole flank into one
    screened shadow mass; the reference barrel has three bands.
49. **Sectioned, mirrored control cage** (`cage_loft`): half-profiles along Y, quads between
    them, Mirror across X (clipped, merged), Subdivision Surface on top, crease rings for hard
    edges. Use it for lofted bodies (car shells, domed tanks, castings). Freestyle inks the
    subdivided surface, so the silhouette is the smooth one. Never for anything that must stay
    faceted.
50. **Nuggets are rocks, not dice** (`nugget`): an icosphere (level 2, 320 facets) displaced by
    seeded low-frequency noise, then cut by ~5 planes so the lump is ANGULAR; the first one or
    two cuts, biased to the camera, are the grey fracture faces. Flat-shaded so every facet
    takes its own tone step; crease angle 150 so ink lands on the cleavage rims and silhouette,
    not on every facet. Convex hulls of random points read as d20s (TRAP); level-3 spheres with
    strong noise read as mush with no inked facets (TRAP). Tag fill faces in a face LAYER, not
    by BMFace reference: a later bisect invalidates the handle (TRAP). Bake the centre into the
    vertices: `ob.location` is not in `matrix_world` until the depsgraph runs and the framing
    read every rock at the origin (TRAP).
51. **Halftone protect is by distance to the ink colour**, not by luma: a dark rust shadow
    step sits under 80 luma and still wants its dots (TRAP).
52. **A pad runs UP TO a rear face, not through its rim** (the motor pad cut the cowl ring
    into three arcs); stop it 0.09 short of the ring's front plane.
53. Reviewer suggestions that contradict an owner ruling are dropped without debate: domed
    motor face, no base plate, rectangular rod crib, vertical posts.

## 8. Organic ores + multi-part linework (2026-09-04, iron ore FINISHED at v38)

Iron ore reached "shapes look good" over v13→v38. The winning recipe for an **ore / rock good**
(`build_iron_ore` + `nugget`), every point owner-ruled or paid for with a render:

54. **A rock is a ROUNDED BOULDER, not a faceted crystal** (owner: "reach the look of the goods
    icon"). Build the cut polyhedron (icosphere + gentle noise + planar cuts + limited dissolve),
    then **SMOOTH-shade it and add a Subdivision Surface (levels 2)** so the silhouette and corners
    round. A vertex/edge bevel only nibbles points and leaves a hard polygon — the owner rejected it.
55. **Decouple line sharpness from surface roundness — the key trick.** The cleavage lines come
    from Freestyle `freestyle_edge` MARKS, which draw crisp even where the surface is now smooth.
    So subsurf can round the form freely while the inked facet lines stay sharp and hand-drawn.
    Crease the marked rims (`crease_edge` ~0.7) so each facet stays a flat-ish cel field.
56. **Silver/cleavage coverage = grey-cap DEPTH** (owner: "more surface in silver, esp. flanks").
    The grey cap is a bisect fill; `dist = ext_along(d) * mult`. Smaller `mult` (deeper) = larger
    exposed cleavage face. Per-nugget `grey_depth` varies it (hero 0.84–0.91 = modest, flanks
    0.74–0.83 = big). One BIG cap beats two caps (two caps' bumpy grey/rust boundary re-inks as
    hatching).
57. **3-tone lit cleavage face**: a mid-grey cap (toon base so its LIT step ≈130, the reference's
    dominant grey) + a NARROW highlight bevel tipped toward the sun (`hi_dir = normalize(0.45·capN
    + 0.85·sun)`, grey_hi base LIT ≈176) whose seam with the cap is NOT inked (soft band, ~15% of
    the face). The darker grey comes from the cap's own toon shading + recess halftone — do NOT add
    a shadow bevel (its rim inks as a random dash on the silver).
58. **Keep rust cuts AWAY from the cleavage-cap directions** (`d.dot(cap_dir) < 0.5`, re-roll):
    a rust cut aimed near a grey cap clips a thin rust wedge into the silver, leaving a stray dash.
59. **Fewer, larger faces for a BIG lump** (owner: the hero "has too many flat-ish sides"): the
    hero uses ~6 planar cuts vs the flanks' 7 despite being bigger, so it reads as one boulder.
60. **Separate touching parts with an OBJECT-ID PASS, not Freestyle** (owner: "clearer separation
    between the nuggets using linework"). Interpenetrating meshes have no silhouette between them,
    so Freestyle draws nothing. `render_icon` renders an `_id.png` (each mesh a flat unique
    `ob.color` via an ObjectInfo→Emission `material_override`, Freestyle off); `icon_export.py` inks
    a bold line wherever the ID label changes between two parts. Every rock ends up fully outlined,
    overlaps included — the reference's structure.
61. **Interior lines THINNER than the outlines, and FADED** (owner: "some lines need to fade / only
    show half"). An ALONG_STROKE thickness modifier on `ink_edge` with a hump curve (ends ~0.45,
    mid 1.0) fades line ends; keep the taper GENTLE or short lines wisp to a random-looking tip.
62. **Skip inking SHORT rim edges** (`elen > 0.15–0.18 r` for dihedral rims, `> 0.10–0.12 r` for
    material boundaries): short dihedral stubs near a junction ink as random forks (owner: "these
    lines are a bit random"). Raising the limited-dissolve angle (→25°) merges the small facets so
    fewer lines converge at a junction.
63. **Cracks: don't fake them with mesh edges.** A mesh-edge crack always spans rim-to-rim, so it
    reads as a broken facet stub, not a fracture. Owner rejected them; cracks are OFF. Proper cracks
    would need a deliberate 2D stroke pass on the face interiors (UNBUILT — the next crack attempt
    should go there, not into geometry).
64. **Blender 5.2**: `World.use_nodes` / `Material.use_nodes` print DeprecationWarnings (removal in
    6.0) — harmless, the kit still runs. `bmesh.ops.dissolve_limit(..., delimit={'MATERIAL','SHARP'})`
    and `bmesh.ops.bevel(..., affect='VERTICES')` are the signatures that work.
65. **VIBRANCE is an export lever, global** (owner 2026-09-05: "colours too washed out, punch them
    up"). `icon_export.py --vib 1.45` expands chroma around each pixel's luma (`luma + (rgb-luma)·f`),
    saturating every icon at once without re-tuning each material; the navy ink is left alone. It
    can't colour a NEUTRAL grey (there's no chroma to expand) — a good that reads too grey needs an
    actual coloured base first (crude-oil drum went neutral-grey → saturated blue steel, then vib).
    Toon bases can be picked muted and let `--vib` do the saturation, or picked saturated up front.

## 9. Fixed isometric perspective and orthogonal goods (OWNER, 2026-09-05)

These rules apply to every future goods icon, including organic goods that contain manufactured
parts such as crates, breakers, labels, pallets, meters or containers.

66. **Use one camera for the whole goods set.** The camera is orthographic with Euler rotation
    `(54.7356°, 0°, 45°)`. Do not tune azimuth, elevation, focal length or perspective per icon.
    `setup_icon_rig()` owns the camera; a builder may only change orthographic scale and target via
    projected-extents framing. Re-running a builder from `--factory-startup` must recreate this view.
67. **World axes are the drawing grid.** In the fixed view, world Z projects vertically and world
    X/Y project along the two shared isometric diagonals (approximately ±30° from screen horizontal).
    Every edge intended to be vertical, parallel or perpendicular in the object must use those same
    world or object-local axes. Do not move individual vertices in screen space to improve one icon.
68. **A 90° object remains geometrically 90°.** Cubes, rectangular housings, cartons, ingots,
    pallets and prisms use `K.box` or an equivalent orthogonal mesh. Their adjacent faces meet at
    exact right angles in 3D even though the projected angle is not 90°. Never fake a rectangle as
    an arbitrary screen-facing quadrilateral.
69. **Share orientation across comparable goods.** The default front is −Y and the default right
    side is +X. Rectangular goods should expose the same front/top/right relationship as existing
    goods. If the reference requires a rotated object, rotate the complete assembly about world Z;
    do not rotate lids, labels, switches or stacked boxes independently into conflicting vanishing
    directions. Prefer 90° Z increments for alternate orthogonal orientations.
70. **Parallel edges are a review gate.** At 800 px, compare at least one long X edge, one long Y
    edge and one Z edge against an approved rectangular icon. Corresponding edges must be parallel
    within one pixel over a 100 px run. A cube must show three internally consistent edge families.
    If it does not, fix the geometry or camera rather than the rendered PNG.
71. **Camera validation is fail-fast.** Before rendering, require an ORTHO camera and compare its
    Euler angles to `(54.7356°, 0°, 45°)` within 0.01°. Treat a mismatch as a failed build. Save the
    camera values with render metrics so a visually plausible off-angle asset cannot enter the set.

## 10. Godot texture import contract (OWNER, 2026-09-05)

72. **Every delivered PNG uses the established goods import settings.** The required Godot values
    are `importer="texture"`, `compress/mode=0`, `mipmaps/generate=true`, `mipmaps/limit=-1`,
    `process/fix_alpha_border=true`, `process/premult_alpha=false`, `process/size_limit=0`, and
    `detect_3d/compress_to=1`. Keep the remaining channel-remap, HDR and normal-map values identical
    to an existing icon in the same tier. UIDs and imported-cache paths are expected to differ.
73. **Mipmaps are mandatory in all three tiers and in `alternate_icons`.** Run a Godot editor import
    after adding or replacing PNGs, then inspect every corresponding `.png.import`. Do not infer
    settings from the source image or from a successful `load()` call.
74. **Compare parameter blocks, not whole sidecars.** For each new `.png.import`, compare everything
    after `[params]` with an established goods icon from the same tier. Release only when every block
    matches exactly and `mipmaps/generate=true` is present. Generated `.godot/imported/*.ctex` files
    remain cache files and are not committed.
75. **Runtime validation follows import validation.** Load the medium, small and very-small textures
    in headless Godot and assert their dimensions are 800², 450² and 256². This proves the imported
    resources resolve; the explicit sidecar audit proves mipmaps and filtering inputs match.

## 11. Complex assemblies: lessons from the approved diesel car (2026-09-06)

76. **Reference roles are complementary.** The original icon decides graphic outlines,
    shared boundaries, accessory composition and intended occlusion. Real-object front,
    profile and assembly views decide curvature, subtype and how parts connect. The owner's
    requested subtype wins: the Touareg study did not make the final car an SUV or estate.
77. **Curvature and joins belong to shared geometry.** Fit lens, reflector, amber region and
    border to one host surface; mirror the canonical geometry and let it occlude naturally.
    Derive cap axes from shoulder normals and connected seam endpoints from actual boundaries.
78. **Corner rounding is not whole-edge bow.** Sample the intended curve and measure its
    projected sag/chord. The accepted windscreen's lower edge is about0.115, reference0.111;
    these are this drawing's proportions, not universal vehicle constants.
79. **Solve structure before stroke symptoms.** A false shadow can be an intersecting bar;
    an exposed far lamp can be a wrong nose/carrier; a heavy arch can combine cutter material,
    face marks and alpha contour. Identify the generating geometry/pass before adjusting ink.
80. **Snapshot the complete render contract.** Builder ordering, shared can functions,
    semantic mask tags, exporter and reference inputs all matter. The complex pipeline checks
    fresh color/mask output and identical selected rerenders without promoting visual approval.
81. **Alternate policy is explicit.** Approved alternates live in `alternate_icons`; the
    loader checks every main tier first and uses alternates only when main art is missing.
    Do not replace main art or invent a selection setting from an alternate-install request.
