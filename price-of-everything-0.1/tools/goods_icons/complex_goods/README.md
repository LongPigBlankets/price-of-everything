# Complex goods icon pipeline

Use this for goods whose recognition depends on multiple curved parts or assemblies:
vehicles, construction equipment, engines and their identifying accessories. It pairs
the existing goods icon with real-world references, then preserves each refinement as
a reproducible Blender candidate. It does not automate visual judgment.

The detailed [car/jerrycan lessons](../../../../.claude/skills/blender-goods-build-review-loop/references/car-and-jerrycan.md)
explain the failures that motivated this workflow. Shared camera, tone, ink and import
rules remain in the [goods style skill](../../../../.claude/skills/blender-goods-icons/SKILL.md).

## Begin with a reference brief

Record the good ID/internal name from **`data/Goods - goodsMVP.csv`**, the runtime
catalogue, rather than the older `data/goods.csv`. Define the subtype, the smallest
display size, the accepted composition and the distinguishing cue. “Car” was insufficient:
this task required a 2004 Passat-like **sedan**, and the red can distinguished diesel.

Save the original goods icon plus useful real front/side/top or assembly views under
`references/`, recording where each came from and what it informs. Inspect a downloaded
3D file before relying on it: identify its actual object/type, orientation and geometry.
Use it as a study unless reuse is intended and its provenance permits it. This pipeline
does not grant rights to redistribute downloaded models or user reference photographs.

Write a small component table before modelling:

| Component | Goods-icon role | Real-world question | Construction and acceptance check |
| --- | --- | --- | --- |
| Host body | silhouette and visible planes | profile and cross sections | loft/cage; matching landmark ratios in side and goods views |
| Glass/lamp/panel | graphic outline and overlap | surface curvature and recess | fitted patch; all layers share one mapping |
| Accessory | subtype cue at 60px | supports, axes and openings | independent subassembly; isolated plus assembled views |
| Seams/ink | shared boundaries and hierarchy | which surfaces actually join | shared endpoint graph; no duplicate perimeter |

Normalise measurements by an appropriate stable length (wheel diameter/axle spacing,
engine block width, track length). Pick only metrics relevant to the current uncertainty;
do not force a motor's flange ratios onto a car or a detailed realism checklist onto an icon.

## Refine in dependency order

1. **Silhouette and assembly:** establish subtype, stance, support and negative space. Use
   plain shaded geometry and side/front diagnostics. Rebuild a wrong host representation
   while preserving accepted components. Do not polish a wrong roofline with lamp details.
2. **Surface relationships:** establish hood/nose curvature, glazing fit, recess directions,
   joint axes and natural occlusion. All graphic layers follow their host surface.
3. **Drawn features:** map the actual icon outlines; distinguish shared panel boundaries
   from pressings, accents and glints. Derive neighbouring endpoints and mirror in 3D.
4. **Ink and materials:** separate crease strokes, explicit ink, cut-face material and
   export contour. Apply the shared palette and selective stipple; check semantic exclusions.
5. **Composition and reduction:** inspect the whole good and each accessory at native 60px,
   then inspect at least four meaningful anatomical crops at 3×. Use a light alpha composite
   to avoid reading hidden RGB/magenta as actual art.

For each owner note, define the visible before/after criterion and protect accepted areas.
Bundle related fixes in one revision. Stop broad refinements once the owner is directing
a local change. If the same structural issue persists, revisit its cause instead of adding
detail or requiring an arbitrary number of renders.

## Executable workspace

`pipeline.py` requires Python with Pillow/numpy and Blender. It accepts an editable job:

```text
project.json          good, render/export entries, reference roles, crop pairs, owner rulings
source/               self-contained builder, kit, driver and exporter
references/           original goods icon and saved real-world references
rounds/<name>/        frozen inputs, brief, render, proof, review, optional repeat verification
```

`diesel_car/` is a working seed, not a universal car-shaped template. Its source intentionally
preserves the accepted helper/driver ordering. It also includes `build_jerrycan_study` for
isolated can renders. Work in a new workspace; do not edit the approved seed for an EV study.

From the repository root:

```sh
python3 price-of-everything-0.1/tools/goods_icons/complex_goods/pipeline.py init \
  price-of-everything-0.1/tools/goods_icons/complex_goods/diesel_car \
  /tmp/diesel-work

python3 price-of-everything-0.1/tools/goods_icons/complex_goods/pipeline.py round \
  /tmp/diesel-work baseline \
  --brief 'Reproduce the approved sedan and can before further work.'

# Edit /tmp/diesel-work/source and project.json as needed, then create a new revision.
python3 price-of-everything-0.1/tools/goods_icons/complex_goods/pipeline.py round \
  /tmp/diesel-work cowl_revision --previous baseline \
  --brief 'Bow the whole windshield base outward; preserve both hood seam endpoints.'

python3 price-of-everything-0.1/tools/goods_icons/complex_goods/pipeline.py verify \
  /tmp/diesel-work/rounds/cowl_revision
```

Set `BLENDER_BIN` or pass `--blender` for another machine. Outputs are not installed.
The workspace contains `.gdignore`, so a workspace placed under the game is not imported
as thousands of intermediate game resources. The source/reference seed is tooling content;
do not add it to a game art export list.

For a different good, prepare `source/` with its own builder and edit `project.json`:

- `schema_version`: 1; `good`: snake_case name passed to the builder.
- `good_id`/`internal_name`: catalogue identity, distinct from an authoring alias.
- `entry`/`exporter`: relative files inside `source/`.
- `reference`: original image inside `references/`; real references list `path` and `role`.
- `contour`/`vibrance`: explicit values calibrated to that good, not silently inherited taste.
- `regions`: at least four names with `[left, top, right, bottom]` crop boxes. Candidate boxes
  are on its 800px master; reference boxes use the original reference's native dimensions.
  Crops retain their own scale at 3×; normalised ratios, not their displayed sizes, compare form.
- `owner_rulings`: accepted constraints and corrections to carry into every review.

The render driver accepts `-- OUTPUT GOOD` and writes `GOOD_raw.png`,
`GOOD_raw_mask.png`, `GOOD.blend`, and `metrics.json` with `camera_degrees`.
It must assert ORTHO, apply the common rig, check ground/intersections as appropriate,
and keep geometry deterministic. The exporter accepts raw/output paths plus `--contour`
and `--vib`. The diesel files demonstrate this contract without external screenshot paths.

Each `round` refuses an existing name, copies the entire source/reference/config snapshot,
records input hashes and the brief, and renders from that snapshot. It checks file production,
fixed camera angles and a **nonuniform mask on opaque subject pixels**, then exports
800/450/400/256/60 PNGs. It builds a reference/previous/candidate sheet, four or more 3×
crop sheets and a before/after pixel-change map. A failed run retains its logs; fix the
working source and use a new round name. A changed pixel count proves change, not correctness.

`verify` checks frozen input hashes, rebuilds from factory startup, and compares decoded
color, mask and every export size pixel-for-pixel. It refuses to overwrite an existing repeat.
Run it on the selected candidate; do not pay for duplicate builds after every small tweak.
The tool creates a pending review note, never an automated visual PASS.

## Review and approval

Give an independent reviewer the original goods icon, relevant real references, previous
candidate, new candidate and the owner's exact request. Ask for the largest structural
differences first. Require each requested change to be MET/PARTLY/NOT with a same-region
comparison and a relevant measurement. Request regressions against accepted parts as well.
Reviewers must open the images; clean topology and successful tests do not establish fidelity.

For a disputed curve, use endpoints, bow/chord and uncertainty. For an occlusion, inspect
rendered visible regions. For an assembly, inspect connected support and actual empty space.
For stray ink, identify the generating pass before changing width. Record any unresolved
limit candidly. The owner's acceptance supersedes earlier tentative reviewer verdicts.

## Apply this to the next complex goods

| Good | Useful reference study | Reuse and first review gate |
| --- | --- | --- |
| Electric car | Existing EV goods icon plus matching real vehicle front/profile | Reuse the approved sedan's wheel/surface-fitting methods where compatible. Establish the EV reference's own body and distinguishing accessory/front treatment; do not merely remove the diesel can or assume the Passat body is right. Compare diesel and EV together at 60px. |
| Construction equipment | First identify the machine in the icon, then side and working-arm/joint views of that type | Model chassis, cab, tracks/wheels and articulated assemblies separately with shared pivot axes. Check silhouette, negative spaces between arm segments and support/contact before hoses and bolts. Test in the final assembly, not only in isolated orthographic views. |
| Engine | Original engine icon plus block/head, manifold and accessory views | Begin with major casting volumes, cylinder-bank arrangement if visible, and mounted accessory axes. Prioritise the large voids and overlapping silhouettes that identify the assembly. Do not turn every photographed cable or fastener into ink. |

These are starting questions, not preselected designs or claims that those goods are built.

## Install only the selected result

Honor existing user authorization; do not ask again when they have approved installation.
Copy the selected 800/450/256 PNGs into the requested main/alternate tiers, preserve exact
same-tier Godot `[params]` blocks, import, then load the real textures and check dimensions
and mipmaps. Update `approved_manifest.json` with source and hashes. Preserve the explicit
fallback policy: all main tiers precede all alternate tiers in `scripts/good_icons.gd`.
The pipeline intentionally stops at a reviewable candidate so earlier experiments cannot
be accidentally shipped by running a render command.

## Verified baseline

The pipeline's fresh diesel master matches the installed alternate pixel-for-pixel. A second
factory-startup build reproduces the color, mask and five export sizes exactly. Before/after
proof generation and guards against overwritten workspaces/rounds, changed or added frozen
inputs, unfrozen references and duplicate crop names were exercised. An independent EV setup
dry run checked the workflow without creating or approving an EV model. Evidence is in
[`artifacts/goods_pipeline_validation`](../../../artifacts/goods_pipeline_validation/).
