# Car and jerrycan: lessons from the approved diesel alternate

Read this for vehicles, construction equipment, engines, or accessories with difficult
surface joins. These are lessons from the September 2026 diesel iteration, not a requirement
that every good use a sedan's geometry or exact measurements.

## Where the result lives

The approved asset is the `windscreen_bow_final` revision in
`price-of-everything-0.1/artifacts/goods_icon_diesel/passat_rebuild/`.
It is installed as `g_056_ice_car.png` in alternate medium/small/very_small tiers.
The other approved alternates are electrical components, ethylene, limestone, coal, iron
ore and ammonia. Main icons take priority across **all** tiers; alternates are fallbacks.

The durable, executable seed is
[`tools/goods_icons/complex_goods/diesel_car`](../../../../price-of-everything-0.1/tools/goods_icons/complex_goods/diesel_car/).
It preserves the final car builder, shared can builder, exact kit/exporter dependencies,
original goods art and user-supplied front/profile photographs. The downloaded Touareg
was a geometry study; the accepted scene does not contain third-party geometry.

## What took the rounds, and what finally changed the result

| Failure or owner correction | Useful diagnosis and successful construction |
| --- | --- |
| Boxy/janky car; windshield slab detached; estate shape instead of sedan | The representation was wrong. Rebuild the shell around the requested 2004 Passat-like sedan. Keep the accepted wheel/can components. Trace the supplied profile using axle centres for scale; establish hood, screen rake, roof crown, rear glass and a separate boot deck before adding details. |
| Touareg download seemed a possible shortcut | Use it to understand continuous body/glass surfaces and rounded joins. Its SUV proportions cannot decide the sedan's roof, overhangs or stance. Inspect what a download actually contains; the later supposed jerrycan archive was not present, and a supplied photograph became the useful reference. |
| Can top kept reading as ribs or a slotted solid wedge | Model the negative space: open longitudinal bridges, feet embedded in supporting shoulders, no bottom crossbar through the deck. A narrow dark backing can simplify an opening in the goods view; it must not substitute for the space and support topology. Render the can by itself as well as beside the car. |
| Cap sat on a plate with the wrong angle | Remove the separate pad and derive the neck/cap axis from the actual shoulder tangent. After whole-object nonuniform scaling, measure the resulting world-space slope again. Final shoulder slope was about 22.47 degrees; that number belongs to this can/reference. |
| Handles too high; rear shoulder too low | Judge clearance above the deck, not just grip Z. Keep a nearly level low bridge and raise/round the rear shell into its support. Lowering every handle vertex alone misses the relationship. |
| Can face pressings looked like added pipes | Use shallow recessed branch channels with an inset floor and central stamped field. Deep subtraction can still look like a raised pipe when a broad lit wall dominates. Judge the actual rendered edge, not the Boolean operation's name. |
| Suspected strange shadow at the handle root | It was intersecting geometry; sun shadows were already off. Inspect the mesh and occluder before adjusting light or material. |
| Headlamps looked rectangular, then warped | Trace the goods icon's lens/amber perimeter, reflector layout and end directions. Map every layer through the same curved surface function. Polygon count helps sampling; it cannot fix an incorrect carrier surface. |
| Near lamp improved but far lamp stayed fully exposed | First inspect the host nose's plan and vertical curvature. Upright fascia under the hood lip, rounded wing transition, body-fitted lenses and shallow local-normal recesses produced natural far-side occlusion. Mirrored detached carriers and camera-directed tunnels had forced the wrong visibility. |
| Hood outline was tidy but wrong | The rejected inset closed loop described an extra panel. The original hood boundary shares the grille top and lamp brows, then runs along fender seams to the cowl. The two inner strokes are pressings, not another perimeter. Model this shared boundary graph before drawing lines. |
| Headlamp/grille connectors were uneven | Derive exact endpoints from the rounded grille and actual lamp boundary. Mirror one canonical set of 3D endpoints. Independently approximating both corners created dipping, unequal connectors. Projected lengths need not look equal under the fixed view. |
| Windshield still had a straight bottom | Rounded corners are not a bowed edge. Sample the whole lower boundary as a smooth outward curve and fit it to the body. Retain the cowl endpoints so hood seams stay connected. |
| Aggressive navy around tyres, then unexpected dots | Separate intended tyre tone, wheel-well gap, Freestyle cut-face strokes and the export contour. Mark wheel/cutter faces out of redundant ink; preserve the lower silhouette. Broader lighter sidewalls triggered stipple, so wheel objects received an explicit mask exclusion. |

## Reference roles and feature measurements

Use the goods icon to answer **what must be seen and what lines mean**: composition,
subtype cues, visible portion of a far lamp, lens graphics, shared hood boundary, ink
hierarchy and accessory scale. Use the real object to answer **how it is built**: side
profile, roof/hood curvature, depth, supports, openings, shoulder planes and articulation.
User corrections decide conflicts. Realistic material detail is not an automatic addition.

One front photograph cannot establish every axis. A profile makes sedan vs estate and
overhang/axle relationships legible; the goods view tests the nose's width, curvature and
occlusion. Keep diagnostic side/front views separate from the fixed production camera.

Measure the feature under dispute. These were useful checks here:

- Profile landmark heights and axle-normalized longitudinal positions.
- Hood/lamp/grille endpoint continuity and whether a line is shared or duplicated.
- Cap plane normal versus shoulder normal, **after assembly transforms**.
- Handle/deck clearance and rear support connection.
- Far-lamp visible shape in rendered pixels; ray-hit counts are not pixel-area percentages.
- Windshield bow divided by the chord between its lower corners. Previous: **0.015**;
  first curved attempt: **0.177**; accepted: **0.115**; original icon: **0.111**.
  Endpoint uncertainty was approximately **0.01** in the ratio. These are projected
  drawing measurements, not a claim of identical physical glass dimensions.

The accepted car still has a narrow smooth dark recess above the wheel and a narrower
far-lamp fragment than the illustration. The owner approved it; do not reopen those
features simply because an old reviewer labelled them imperfect.

## Blender traps worth carrying forward

1. **Stale evaluated meshes:** do not add/apply modifiers while continuing ray casts against
   an older evaluated object. Complete surface queries, then add pending lens cutters; or
   explicitly update the dependency graph and reacquire the evaluated mesh.
2. **Fit the entire feature:** lens, amber region, reflectors, glints and border use the same
   mapping. A fitted lens with a flat graphic or floating border still breaks.
3. **Mirror geometry, not the final image:** build a canonical side, mirror its 3D points,
   and let the body occlude the far side. Preserve world axes and the common icon camera.
4. **Normals decide recess direction:** subtract a shallow volume along the surface normal.
   A clearance tunnel along the camera can expose geometry the reference hides.
5. **Ink has several sources:** Freestyle silhouette/crease/face selection, explicit curves,
   material boundaries and 2D alpha dilation. Diagnose which creates the unwanted stroke.
   Boolean faces may inherit the cutter's material and face marks.
6. **Small borders can become occluders:** a raised rim tube can hide the far lens at the
   oblique view. A thin surface-following ribbon can carry ink with less depth interference.
7. **Semantic mask exclusions:** the accepted local kit uses `pass_index = 73` on wheel
   components, read by the override shader. Record both halves of this contract; copying
   the car without that kit will change its dots. Reserve/check the tag in new assemblies.
8. **Run Blender with a Python failure exit code:** some earlier invocations exited zero
   despite a Python traceback. Also require the expected files and valid metrics.
9. **Freeze all dependencies:** `passat.py` is executed after `goods_icon_kit.py` and overrides
   its older car builder. The latter still owns the accepted can and mask. Preserve source
   ordering, exporter settings and all files, not just the newest builder.
10. **Do not depend on screenshot temp paths:** copy reference inputs to the job's references
    directory. The old profile proof script used a macOS TemporaryItems path; the new seed
    stores that photograph durably.

## Review failures and a better question

Several early reviews said “ready” because lines were clean and the object recognisable.
The owner then rejected the same hood topology or far-lamp visibility. Technical validity
and category recognition did not answer the requested comparison.

For each owner request record: their wording, a concrete acceptance criterion, evidence,
MET/PARTLY/NOT, and any remaining difference. A clean but incorrect inset loop must fail
“hood shares radiator/lamp boundary.” An unoccluded far lamp must fail “outer portion turns
out of sight.” Supersede the mistaken review explicitly instead of accumulating approvals.

Rebuild when the underlying shell/topology cannot express the requested relationships.
For a local curvature correction, keep the accepted shell and adjust the constrained curve.
This preserves progress while avoiding endless parameter tweaks to an unsuitable body.

## Evidence trail

Under `price-of-everything-0.1/artifacts/goods_icon_diesel/`:

- `rebuild_review/review.md`: early body and can structural defects.
- `rebuild/review_v3/review.md`: geometry mistaken for a shadow at the handle root.
- `rebuild/model_study_v2/README.md`: role of the downloaded Touareg study.
- `passat_rebuild/top_curve_v4/README.md`: can slope and earlier curved-lamp mapping.
- `passat_rebuild/body_nose_v4/README.md`: successful host-surface/occlusion change and limits.
- `passat_rebuild/bonnet_v1/`: rejected clean inset loop; `bonnet_reference_v1/`: shared boundary.
- `passat_rebuild/glass_wheels_v1/review.md` and `glass_wheels_v2/review.md`: ink/stipple diagnosis.
- `passat_rebuild/windscreen_bow_final/review.md`, `cowl_measurement.json`, `verification.json`:
  measured final curve and identical repeat renders.

The reusable workflow and executable commands are in
[`complex_goods/README.md`](../../../../price-of-everything-0.1/tools/goods_icons/complex_goods/README.md).
