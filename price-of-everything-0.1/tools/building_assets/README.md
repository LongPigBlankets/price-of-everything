# Detailed building assets

This pipeline extends the approved Blender building kit with farms, water pumps,
new-growth forest, old-growth forest, desalination plants, conventional oil wells
and shale oil wells. Every family has three levels. Current revisions are
**v17-shale-colour** for shale oil, **v13-oil-engineering** for approved conventional oil,
and **v10-no-outline** for the other five families (2026-10-10).
One parameterized source produces transparent sprites, editable
Blender scenes and the vertex-painted GLBs used by the supply-chain renderer.

Run from the Godot project directory with Python 3, Pillow, numpy and `blender`
on PATH. Blender always runs in background mode. The original kit and print
passes are read from the repository's `.claude/skills/blender-building-sprites`.
No external master blend or absolute user-specific asset directory is needed.

```sh
python3 tools/building_assets/pipeline.py build --revision v7
python3 tools/building_assets/pipeline.py models --revision v7
python3 tools/building_assets/pipeline.py verify --revision v7
# Inspect proof.png, the 800px exports, 64px thumbnails, and the source scenes.
python3 tools/building_assets/pipeline.py install --revision v7
godot --headless --editor --import --quit --path .
godot --headless --path . res://tools/building_assets/check.tscn
AGENT_GODOT_WINDOW=1 godot --path . res://tools/building_assets/check.tscn -- --capture
```

`--output` selects the revision parent directory. The default is
`outputs/building-assets-2026-10-08` at repository root. `--families farm desal`
limits a build. Existing revision directories are never overwritten. Failed
attempts keep their logs. A new revision snapshots the builder, pipeline, shared
kit, foliage kit, renderer, exporters and print pass before executing them.

Each revision contains:

- `source/`: exact hashed source used to make that revision.
- `<family>_L<n>.blend`: editable geometry with the production camera and materials.
- `<family>_L<n>.png`, `_mask.png`, `.log`: raw colour/mask and Blender evidence.
- `<family>_lvl<n>.png`: final 800×800 transparent sprite, shared scale per family.
- `models/`: colour GLBs and dimensions/ink metadata for the game. Older revisions
  also contain the retired outer-contour GLBs.
- `manifest.json`: source/output hashes, alpha bounds, palette and mask measurements.
- `proof.png`: three levels, 64px thumbnails and an existing industrial-factory control.
- `previous-installed/`: any files replaced during installation.

## Build / render / critique / refine

The requested “dream loop” was not found as a named local skill. This pipeline uses
the repository's `blender-building-sprites` and `blender-goods-build-review-loop`
instructions: write an observable brief, build, render, measure, independently
critique, consolidate changes, and freeze the next revision. Building style takes
precedence over the goods-specific ink and shading constants.

Keep the true-isometric camera, AgX building rig, 2.4/1.05px detail ink,
matte palette and normal-driven print pass. The owner's latest ruling removes
the heavy navy outer contour: sprite export uses `contour=False`, and these seven
model families use `outer_contour=False`. Other asset families retain their style.
The owner permits a broader palette, including black and yellow; colours are
not restricted to grey and terracotta. Keep deliberate equipment colour groups
and the established matte shading and fine ink. No cast shadows or broad underlying ground plates. Retain
functional crop beds, basin floors, equipment foundations and structural feet.
Add readable assemblies before fine details.
Do not apply a goods-icon toon rig to these buildings.

Inspect all levels at full size and 64px. Check physically implied connections
(intake → pump → delivery; membrane ports → manifold → tank/brine), supported
equipment, glass/roof intersections, crown-overlap linework, and shade separation.
The automated gate checks dimensions, alpha margins, nonempty masks with a real
tone range, source/output integrity, and distinct upgrade pixels. These checks do
not replace visual review or establish owner approval.

## Family grammar

| Family | L1 | L2 | L3 |
| --- | --- | --- | --- |
| Farm | Barn, four crop beds, irrigation and two crates | Same field and yard, plus one silo and water trough | Approved full farm: five beds, twin silos and glasshouse |
| Water pump | Wet well, house and one pump | Previously shown full setup: three pumps, surge vessel and switchgear | Same setup plus elevated water tower, braced legs, service gallery and connected riser |
| New forest | Six saplings, stakes, nursery marker | Nine saplings | Twelve saplings |
| Old forest | Six branching mature trees, fallen log, understory | Nine trees | Twelve trees |
| Desal | Intake screens, membrane rack, freshwater tank | Second membrane rack | Pretreatment filters and recovery unit |
| Oil well | Conventional horsehead pumpjack, wellhead and storage tank | Second tank, horizontal separator and control cabinet | Second pumpjack and connected gathering line |
| Shale oil well (`fracking_oil_well`) | One frac tree, two pump modules, blender, sand hopper and water tank | Second tree, third pump and second water tank | Third tree, fourth pump, tall sand silo and control shelter |

Core geometry stays anchored as capabilities are added. Fixed framing scale keeps
equipment dimensions consistent. Forest seeds and positions are deterministic;
levels increase density without relocating existing trees. Mature woods also use
larger crowns and deeper local green recesses. Buildings and trees sit directly
on the game's terrain, with transparent space between assemblies. Shared export
scale keeps the plant the same physical size across upgrades while the tower
adds a landmark.

## Integration and rollback

The sprite loader discovers `<internal_name>_lvl<n>.png` automatically. The GLB
exporter extends its catalog with these seven families and preserves existing model
families. Installation merges only their model-manifest entries and copies their
sprites/meshes. Existing territory-map farm fields and authored forest terrain
remain their existing specialized renderers; these are building assets for the
sprite consumers and supply-chain board, not a replacement terrain system.

The 3D exporter supports `POE_PROJECT_ROOT`, `POE_SPRITE_KIT`, `POE_DETAIL_SOURCE`
and `POE_MODEL_OUTPUT` so it can execute an exact frozen revision into staging.
The pipeline sets these automatically. It retains the current game's barycentric
detail ink, vertex colour and normal format. The model manifest explicitly sets
`contour: false`; installation backs up and removes retired contour GLBs and import
sidecars for those entries, without altering unrelated models.

## Shale palette update (2026-10-10)

- `v17-shale-colour` applies industrial yellow to pump panels, fluid ends, valve
  bodies, the blender tub and silo ladder; charcoal to mechanical parts and roofs.
  Grey tanks and fittings retain a clear neutral hierarchy. The owner explicitly
  permits colours beyond grey and brown, including black and yellow.
- All 781 source meshes across the three levels are geometrically identical to
  V16; alpha channels also match exactly. The engineering review remains valid.
- Independent colour review passes at full size and 64 px. Other building
  families are unchanged. Evidence: `v17-shale-colour/geometry-check.json` and
  `review-v17-shale-colour.md`.

## Shale oil well validation (2026-10-10)

- `v16-shale` depicts an active fracturing spread using the existing game name
  `fracking_oil_well`. It preserves a complete route at every level: water and
  proppant → blender → low-pressure distribution → reciprocating pumps → separate
  high-pressure collector → valved manifold → frac trees. Counts are stylized.
- Reference topology: [SLB missile](https://glossary.slb.com/en/terms/m/missile),
  [zipper manifold](https://glossary.slb.com/terms/z/zipper_manifold), and
  [Cameron frac trees](https://www.slb.com/products-and-services/innovating-in-oil-and-gas/completions/stimulation/frac-and-flowback-equipment/frac-trees-and-zipper-manifolds).
- Independent review found and resolved unsupported power-end pedestals, a gap
  under branch valves, an auger clipping the blender rim and an additive-tote
  overlap. The final hopper/tub, separate pressure lanes, supports and ports were
  checked against source geometry as well as full-size and 64 px renders.
- `audit_shale.py` checks frozen scenes for cross-assembly surface intersections,
  explicitly allowed nozzle/tee joins, 30 equipment mounting relationships and
  24 coaxial pipe connections across the three levels. It also checks the hollow
  blender/auger clearance and actual contact at the conveyor support. V16 passes.
  Run it in background Blender with `-- <absolute-revision-directory>`.
- Godot verifies all 21 sprites and 21 meshes with zero failures and no outer
  contour shells. Installed hashes match; 36 other-family files and 74 other
  catalog entries are unchanged. `v16-shale/godot-proof.png` records the gallery.
- Audit evidence is `v16-shale/engineering-check.json`; independent review and
  thumbnails are in `review-v16-shale`. The audit checks the depicted exterior,
  not treatment capacity or pressure-vessel internals.

## Pumpjack engineering audit (2026-10-10)

- `v13-oil-engineering` corrects the three conventional oil-well levels against
  the LUFKIN CU-93 conventional-unit manual. The prior visual review did not
  establish mechanical fidelity; the engineering audit found real collisions.
- Horsehead curvature now shares the beam pivot, with a solved crank/pitman/beam
  linkage, wrapped and anchored bridle, carrier bar, rod clamp and bored bearings.
  Motor/reducer pedestals bear on the foundation; the belt guard has clearance
  and mounting brackets. Counterweights, ladder, control cabinet and the wellhead
  outlet no longer cross unrelated components.
- `audit_pumpjack.py` rebuilds and checks 360 crank poses at one-degree intervals.
  V13 has zero unexpected BVH surface intersections and maximum linkage closure
  error below 7e-16 m. Intended fabricated joints, housed shafts, belt contacts
  and cable contact with the horsehead are explicit exemptions. This is a sampled
  exterior-geometry audit, not a structural/load or hidden-gear simulation.
- Analytic minimum clearances: counterweights above skids 130 mm, beside skids
  50 mm, adjacent pumpjacks 72 mm. The carrier clears the stuffing box throughout
  the stroke. Independent calculations also verify constant cable length.
- Reproduce: `blender --background --python-exit-code 1 --python
  tools/building_assets/audit_pumpjack.py -- /private/tmp/pumpjack-audit.json`.
  Evidence and side/front/exposed-drive views are in
  `outputs/building-assets-2026-10-08/engineering-oil-audit` at repository root.
  Other families remain at v10; no shared site plates or thick outer contours
  are reintroduced.
- The installed three sprites and three meshes match the selected revision.
  Godot loads all 18 sprites and meshes with zero failures; the final gallery is
  `v13-oil-engineering/godot-proof.png`. The capture now rescales the full Retina
  framebuffer instead of cropping out the top and bottom rows.

## Heavy-outline removal validation (2026-10-10)

- v10-no-outline removes the synthesized PNG border and 3D silhouette shells from
  all 18 variants. Fine structural lines, colours, geometry and plate-free layouts
  remain intact.
- All 36 raw colour/mask images are pixel-identical to v9-no-plates. Every model's
  dimensions, triangle count and detail-ink metadata match; only `contour` changes
  to false. Twelve colour GLBs are byte-identical; the tree meshes may reorder
  identical sphere faces during serialization.
- Evidence: `v10-no-outline/raw-render-comparison.json`, `mesh-comparison.json`.
- Independent review found no blockers: outer rims and contour tails are gone,
  with fine joins, transparency and all 18 small-scale identities retained.
  Before/after edge comparisons are in `review-v10-no-outline`.
- Godot verified 18 exact-level sprites and meshes with zero contour shells and
  zero failures. `v10-no-outline/godot-proof.png` shows the live comparison.
  Installed hashes match; the 18 retired shells and import sidecars have rollback
  backups, and all 56 unrelated catalog entries are unchanged.

## Ground-plate removal validation (2026-10-10)

- v9-no-plates updates all 18 sprites and model/contour pairs. Shared concrete,
  farm and forest plates are gone, along with the forest clearing strip.
  Crop beds, basin floors, pump skids, equipment foundations and tower feet remain.
- The saved-scene comparison verifies 42 removed ground objects across all 18
  levels, with no added or changed retained geometry. Sphere face ordering is
  canonicalized without changing topology or winding. Evidence:
  `v9-no-plates/plate-removal-check.json`.
- All 18 exact-level sprite, mesh and contour resources pass the Godot contract;
  the live comparison is `v9-no-plates/godot-proof.png`. All installed hashes and
  mipmaps match, and 56 unrelated catalog entries are unchanged.
- Independent review found no blockers in transparency, exposed supports or
  64px readability. Checkerboard and enlarged comparisons are in
  `review-v9-no-plates`; 2,660 retained source objects are unchanged.
- `v9-no-plates/overview.png` shows the six L3 assets; `proof.png` includes every
  level. The historical farm L2/L3 pixel-identity checks below apply to v8 only;
  v9 re-renders their unchanged geometry with the ground plate removed.

## Farm correction and oil-well validation (2026-10-10)

- v8-oil adds three conventional oil-well levels and updates farm L1. Farm L2
  and L3 PNGs are byte-identical to v7-levels; the water pump is unchanged.
- Saved-scene comparison confirms all 152 shared L1/L2 farm objects have identical
  world vertices, polygons and materials. L2 adds only silo and trough objects.
- Independent visual review found no structural blockers; pumpjack mechanisms
  and upgrade tank/jack counts read at 64px. Evidence: `review-v8-oil`.
  Small contour spikes in narrow gaps remain consistent with the factory control.
- All 18 sprites, 18 meshes and contours loaded in Godot with zero check failures;
  the real rendered comparison is `v8-oil/godot-proof.png`.
- Installed hashes and mipmaps match; 68 unrelated model-catalog entries remain
  unchanged. Evidence: `v8-oil/installed-check.json` and `farm-geometry-check.json`.
- The editor import reported three existing translation UID duplicate warnings;
  the focused asset run was clean. The broader suites below were not rerun for
  this geometry-only revision.

## Earlier level revision validation (2026-10-10)

- v7-levels replaces only the farm and water-pump families (six sprites and six
  model/contour pairs). Other families retain v6.
- Farm L3 is byte-identical to the liked v6 export. Pump L2's raw render has
  exactly the same pixels as the previously shown pump L3; final framing uses
  the new family's shared scale, including the taller/wider L3 tower.
- Independent review found no blockers: three-level silhouettes read at 64px,
  tower feet/braces/gallery meet cleanly, and no clipping was observed.
- Godot import and the live sprite/mesh contract capture passed for all 15 levels,
  with zero failures. Evidence: `v7-levels/godot-proof.png` and `godot-check.log`.
- All 15 installed sprite hashes and the unchanged model families were checked.
  Partial-family installation now retains per-family revision provenance.

## Initial set validation (2026-10-08)

- v6: 15 unique 800px sprites, 15 colour meshes and 15 contour meshes installed.
- Independent visual review of v3 → v5, with the final v6 crop-ink correction
  inspected separately. Evidence is in `review-v3` and `review-v5` beside the revisions.
- Asset contract scene: every exact level, texture size, mesh surface, contour and
  required shader attribute loaded; zero failures. Real windowed capture inspected
  at `godot-sprite-mesh-proof.png` in the output directory.
- Independently rebaked farm L1/L2/L3: all final PNG SHA-256 values match v6 exactly
  (`determinism.json`). Installed sprites/meshes match their recorded hashes, and
  every sprite has mipmaps. All pre-existing model-manifest entries were preserved.
- Full unit suite: **6,304 passed, 0 failed** (`unit-tests.log`).
- 100-turn Stoneshore end-to-end: **723 passed, 0 failed** (`e2e-tests.log`).
- The broader harness logs include terrain/node and teardown diagnostics despite
  passing assertions; the isolated asset contract/render checks passed without them.
- Remaining visual limitation: desal L1/L2 share a similar outer silhouette; the
  second membrane rack is the distinguishing upgrade. L3 adds tall filter vessels.

To roll back an overwritten family, restore its `previous-installed` files and
the previous manifest, then import headlessly. For a newly added family, remove
only that family's added PNGs/GLBs/import sidecars and manifest entries. Do not
restore an entire manifest over unrelated later work.
