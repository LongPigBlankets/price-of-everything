# World-map visual gauntlet — inhabited mid-century style

## Preservation record

- Started: 2026-08-11 (Europe/London)
- Source branch: `map-city-plate-variant`
- Source commit: `fa1fbc96c33e2df04601de1d6ac616922ace7729`
- Working branch: `codex/inhabited-midcentury-map`
- Pre-existing untracked files deliberately left untouched:
  - `scripts/frame_budget.gd.uid`
  - `tools/block_dump.gd.uid`
  - `tools/terrace_gap_audit.gd.uid`

## Constraints carried from the design sources

- The new `midcentury` style is draw-only and optional; the game still starts in the existing ink style.
- Road topology, river topology, subtiles, terrain classification, forest occupancy, building footprints,
  simulation values, save data, selection, and click testing are frozen.
- Decorative urban fabric is deterministic, non-interactive, owns no land, and has no economic identity.
- Roads use the full built network geometry for visual parcel response; enclosure-tagged edges are not
  treated as gameplay-building frontage.
- All variation is seeded through `RoadHash`; no per-building or per-tree nodes may be introduced.
- Legacy classic, ink, and plate renderers remain compatibility targets.

## Baseline commands and results

### Deterministic tests

Command: `python3 tools/run_tests.py`

- Result: **2,215 passed, 0 failed**.
- Baseline console is not clean. Repeated scene-instantiation paths report that
  `BuildingVisuals._ensure_farm_underlay()` calls `add_child()` while the parent is busy and then attempts
  `move_child()` on the unattached node. Headless fixture tests also log expected missing `%TerrainLayer`
  lookups, and shutdown reports RID/resource leaks.

### Fixed captures

Command: `Godot --path . res://tools/map_style_shot.tscn --quit-after 4200`

- Captured all 10 framings in classic, ink, and plate: wide, coast, inland, farmclose, plantclose,
  elyclose, mineclose, playerclose, denseclose, and blockclose.
- The harness reported its existing plate-to-classic round-trip successful.
- Classic and ink images are byte-identical in this harness run. Plate images differ as expected.
- Immutable baseline copies live in `reports/map_visual_gauntlet/baseline/`.

Command: `Godot --path . res://tools/mockup_compare_shot.tscn --quit-after 1600`

- Captured Arin port, Arin docks, old Arin, Stoneshore, and Stoneshore docks in ink.
- Copies live beside the fixed map-style baseline captures.

### Road-frontage audit

Command: `Godot --headless --path . res://tools/road_frontage_audit.tscn --quit-after 4000`

| Metric | Baseline |
|---|---:|
| Tiles with roads | 177 |
| Buildings measured | 413 |
| Tiles failing 15u frontage | 79 |
| Buildings over 15u | 177 |
| Off-road by design (farm/extraction) | 137 |
| Saved by service lane | 1 |
| Failing placements via block mode | 165 |
| Worst frontage distance | 146.6u (`tile_10_3`, furnace) |

This audit is supporting evidence only. The visual style will not alter building placement or road topology
to improve the number.

## Baseline visual assessment

The highest-impact weakness is settlement composition. The map reads clearly as geography plus a transport
network, but cities are sparse gameplay-building scatter on open terrain rather than inhabited places.
Road-defined parcels, terraces, courtyards, alleys, open lots, neighbourhood parks, and density falloff are
absent. At wide zoom the white/cream road web is stronger than settlements; at regional zoom there are few
recognisable urban anchors; at close zoom the industrial glyphs have useful silhouettes but no surrounding
ordinary fabric to establish their importance.

Other visible weaknesses:

- forests are compact repeated lobe clusters rather than convincing masses at close zoom;
- large terrain areas are visually empty despite parchment grain;
- plate streets can dominate local geography through brightness and width;
- the `farmclose` framing did not land on visible farm parcels in the baseline run;
- UI occludes substantial areas of the closest framings;
- the map-style harness labels classic and ink separately but produced identical pixel hashes for them.

The last point was a harness setup defect, not a renderer defect: the capture scene initialized both labels
through the same legacy mode. The harness now selects classic, ink, plate, and midcentury explicitly and
captures a masked legacy image before and after every midcentury round-trip.

## Implemented renderer seam

- `MapStyle.set_midcentury(on)` and `MapStyle.is_midcentury()` own the optional switch and emit the existing
  `style_changed` signal. The game default remains the pre-existing style.
- `MapMidcenturyStyle` owns its palette, line weights, shadow values, terrain progression, water, roads,
  farms, parks, decorative fabric, and industrial accent colors. Toggling it does not rewrite legacy state.
- `UrbanFabricVisuals` is a draw-only batched `ArrayMesh` layer. It derives deterministic parcels and masses
  from shared urban classification and built-road geometry, rejects gameplay footprints, road/service-line
  clearances, water/coast, forest discs, parks, and reserved open space, and creates no selectable nodes.
- Gameplay building footprints, occupancy, selection, counts, recipes, capacities, and economic values are
  unchanged. Decorative masses do not enter the placement or economy systems.
- `toggle midcentury` switches immediately. Every completed capture run has restored the frozen legacy map
  region pixel-for-pixel after legacy → midcentury → legacy, with nondeterministic UI masked.

## Post-seam deterministic checks

- Full suite after the accepted V3.02 state and V3.03 visual-only trial: **2,222 passed, 0 failed**.
- The baseline farm-underlay scene-tree error was removed by deferring creation until the parent is ready.
- Expected fixture diagnostics and existing shutdown RID/resource-leak warnings remain.
- Two sandboxed launches failed before project startup because Godot could not rotate its user log. The same
  commands completed normally once the standard Godot user-log location was permitted; these were runner
  failures rather than test or renderer failures.

## Iteration log

| Iteration | Gate / lever | Change | Status | Evidence / next bottleneck |
|---|---|---|---|---|
| V0 baseline | Reproducibility | Tests, 35 baseline captures, frontage audit, direct inspection | Accepted as record | Renderer console errors and sparse settlement fabric are the first blockers. |
| V4.01 | Settlement / shape language | Added deterministic road-aware parcel, park, open-lot, terrace, shadow, and block mesh passes | Accepted | First inhabited fabric; critic average 2.85. Fabric still read as isolated cream cards. |
| V4.02 | Settlement / spacing-density | Increased core density and varied parcel occupancy with deterministic falloff | Accepted | Average 3.08. Denser but still weak street-wall continuity. |
| V4.03 | Settlement / contiguous massing | Replaced card-like lots with stepped masses, U-courtyards, alleys, and irregular voids | Accepted | Average 3.23; settlement 3/5 and massing 4/5. Needed neighbourhood-scale continuity. |
| V4.04 | Settlement / synthetic core roads | Added decorative interior spokes intended to bind urban cores | **Rejected and reverted** | Parcel count fell 490 → 444; pale disconnected spokes competed with real roads and reduced plausibility. |
| V4.05 | Settlement / road-core density | Used denser sampling of actual built-road anchors and centre-first deterministic selection | Accepted | 92 urban tiles, 521 parcels, 456 masses, 37 parks, 34 lots; average 3.46. Settlement and multiscale readability reached 4/5. |
| V4.06 | Settlement / corner enclosure | Added selected high-density junction perimeter masses with narrow alleys and inset paper/green courts | Accepted | 92 tiles, 521 parcels, 484 masses, 39 parks, 34 lots; average held 3.46 but visible enclosure improved. Repeated roof marks became the bottleneck. |
| V4.07 | Settlement / zoom detail | Quieted ordinary roofs: shorter/occasionally omitted terrace seams, mostly blank slabs, rare offset ridges or paired vents | Accepted | Average 3.54; repetitive artifacts reached 4/5. Gameplay-industry roof vocabulary is deliberately untouched. |
| V4.08a | Industry hierarchy / palette-value | Applied the original category colors to whole gameplay-industry masses in midcentury | **Rejected** | Hierarchy improved, but large mustard and orange roofs became saturated color fields at close zoom. |
| V4.08b | Industry hierarchy / palette-value | Keep category identification but halve chroma toward the warm industrial neutral; legacy plate rules remain unchanged | Accepted | Average 3.62; authored materiality reached 4/5 without a palette regression. |
| V4.09a | Settlement / frontage shape | Replaced 38% of eligible regional/core rows with narrow tapered L-shaped masses facing the actual road | **Rejected** | Repeated narrow returns formed a conspicuous hook glyph, trading one procedural artifact for another. |
| V4.09b | Settlement / frontage shape | Used broad frontage returns on only 16% of eligible rows; parcels, clearances, and topology remained unchanged | **Rejected and reverted** | Average fell 3.62 → 3.54; repeated L glyphs remained visible in Arin Old, Arin Port, and Plant Close. |
| V2.01 | Forest / shape language | Replaced midcentury-only circular canopy lobes with deterministic rotated ellipses contained by the same conservative occupancy discs | Accepted | Forest composition rose 2 → 3 and average 3.62 → 3.69. Edge organicity and close tree differentiation improved; weaker wide solidity is the next bottleneck. |
| V2.02 | Forest / layering | Added one quiet low-frequency ellipse under each canopy to restore wide mass | **Rejected and reverted** | Wide solidity improved, but average held at 3.69; the repeated central lozenge flattened close tree character and slightly increased field obstruction. |
| V2.03 | Forest / zoom-dependent layering | Added a three-lobe irregular under-union that fades from wide to zero before close zoom | Accepted | Wide/coast/inland masses became fuller without a repeated core glyph; all six close framings remained pixel-exact to V2.01. Average held at 3.69, with a qualitative gain inside forest 3/5. |
| V2.04 | Forest / zoom-dependent linework | Replaced the broad cluster ring with short warm-ink arcs on a deterministic 19% of lobes, hidden at wide zoom | Accepted | Forest composition reached 4/5 and average rose 3.69 → 3.77. Close crowns gained authored character without wide noise or a repeated parenthesis glyph. |
| V3.01 | Roads / linework hierarchy | Added a sparse warm-ink centre stitch to trunk routes only | **Rejected and reverted** | Regional routes separated, but close views read as modern dashed highway markings; repetitive artifacts fell to 3 and ink/plate consistency to 2, average 3.62. |
| V3.02 | Roads / boundary weight | Increased only the solid trunk casing from bed +2.7u to bed +4.0u; centres and local streets remained unchanged | Accepted | Road continuity/hierarchy reached 4/5 and average rose 3.77 → 3.85. Same-colour trunks now hold through local networks without a highway convention. |
| V3.03 | Roads / junction layering | Covered shared edge endpoints with small road-bed circles after the casing and bed passes | **Rejected and reverted** | Some internal casing caps disappeared, but repeated cream buttons became visible in Player Close, Stoneshore, and Stoneshore Docks. Artifact resistance fell 4 → 3, linework stayed 3, and average fell 3.85 → 3.77. The next road lever is an angle-aware polygonal junction envelope, not a 360-degree patch. |
| V3.04 | Roads / junction shape | Built convex envelopes from incident road-bed shoulders | **Invalid and abandoned before scoring** | Near-collinear endpoint sets produced degenerate polygons and Godot triangulation errors. The legacy round-trip still proved exact, but the errored frames were discarded and the polygon path was removed. |
| V3.05 | Roads / junction linework | Erased only the inward casing-cap seam with a narrow tangent-aligned cross-bed stroke at shared endpoints | **Rejected and reverted** | Subtler than V3.03, but repeated pale diamonds/ticks remained visible in Player Close, Block Close, and Stoneshore. Artifact resistance fell 4 → 3, linework stayed 3, and average fell 3.85 → 3.77. Future junction cleanup must stitch casing paths before drawing and reserve caps for true dead ends. |
| N1.01 | Ports / quay face (addendum §5) | Put the head front on the sampled shore so the head edge and the basin root were one straight line | **Rejected — 0 of 4 ports** | No site on this map offers the 100–135u of straight coast, sea one side and land the other, that a straight quay face needs at 12u lattice resolution. Dead end recorded; do not retry a straight waterline head. |
| N1.02 | Ports / straight arms + real inter-arm water (addendum §5) | Head becomes a block overshooting the quay face 10–34u and clipped back to the rendered band-5 coastline, eroded along an inset ladder until the unchanged NavGrid dry-land gate reads 100%; arms are single straight runs on the two edges of an asymmetric basin trapezoid, attached by marching back along their own axis into the apron | **Accepted (partial on the water half)** | Blind critic: **image_2 (candidate) better**, 2.75 → 3.33 average; reference-family resemblance 2 → 4, multiscale 3 → 4, top-down 3 → 4, hierarchy 2 → 3, accumulated character 2 → 3, repetition 2 → 3; no category regressed. Arm straightness **fully met**: `max_arm_bend_deg` 19.57/21.93/18.66/27.24 → **0.00 at all four**. Inter-arm water **improved but not met**: `interarm_sea_coverage` 85.38% → 95.58% mean, land inside the four Us 4,768 → **2,352u² (−51%)**, so land still remains between the arms at every port. Evidence `/tmp/poe_g3_verify_ports/` (vrun1, vrun2, vstyle, basestyle, vmorph, frontage.log, density_audit.txt); blind pair `/tmp/poe_g3_blind/PORTS/`. **Next bottleneck: the 12u NavGrid lattice, not the coastline** — three of four ports still choose a 10u apron inset under an 8×/unit penalty, and that erosion strip *is* the residual land. Closing the last 4–5% needs either a sub-lattice dry-land instrument or an accepted visible foreshore. Second follow-up: `PortVisuals._rebuild_midcentury_plans()` is not style-gated, costing 4.86s of planner work at every map build in every style (was 0.61s). |

## Rubric scores

Scores are assigned by the independent critic after each candidate capture. No candidate is accepted without
deterministic checks and visible comparison against the previous best.

### Current accepted best: V3.02

| Category | Score | Visible evidence |
|---|---:|---|
| Macro visual hierarchy | 4 | Settlements now form visible anchors without overtaking terrain, coast, and rivers. |
| Geographic plausibility | 4 | Fabric density follows real roads and loosens around rural, water, and steep contexts. |
| Road continuity and hierarchy | 4 | Heavier outer boundaries let blank-centred trunk ribbons remain traceable through same-colour local networks at every scale. |
| River/coast clarity | 4 | Related blue language, banks, mouths, and coastline remain readable through settlements. |
| Forest composition | 4 | Coherent wide unions transition to irregular rotated crowns with sparse close ink notation; a few detached riverside bead chains remain polish-level. |
| Settlement composition | 4 | Road-facing masses, internal greens, alleys, courtyards, and core-to-edge falloff are legible. |
| Building massing and frontage | 4 | Stepped terraces and selected corner enclosures define streets while respecting frozen footprints. |
| Palette coherence | 4 | Warm paper, khaki terrain, grey ordinary fabric, sage greens, and restrained accents remain related. |
| Linework coherence | 3 | Ordinary roofs are calmer; broader road/coast/terrain line-weight issues remain. |
| Materiality and authored character | 4 | Restrained category identity gives real industrial districts purposeful variation. |
| Multiscale readability | 4 | Settlement anchors survive wide zoom and courtyards/alleys emerge progressively at close zoom. |
| Absence of repetitive artifacts | 4 | Full-length roof crosses no longer repeat map-wide; rare small marks avoid a replacement pattern. |
| Consistency with ink/plate direction | 3 | Direction is coherent but not yet as historically accumulated as the references. |
| **Average** | **3.85** | Junction linework and broader ink-direction consistency remain below the 4/5 gate floor. |

Accepted screenshot sets are stored under `reports/map_visual_gauntlet/iterations/`; rejected candidates
may be retained as diagnostic evidence but are never promoted as the current best. The immutable baseline remains in
`reports/map_visual_gauntlet/baseline/`.

## Renderer-seam prototype handoff

The map-wide renderer-seam prototype remains **V3.02**. The road-junction linework target then had three consecutive
non-improving focused attempts: V3.03 introduced circular buttons, V3.04 was invalid because degenerate
convex hulls produced triangulation errors, and V3.05 introduced repeated pale ticks. All three paths were
removed from the renderer; their diagnostic screenshots are preserved where valid.

The independent critic keeps the accepted rubric at **3.85/5**. Road continuity/hierarchy is 4/5, but
linework coherence and consistency with the ink/plate direction remain 3/5. The next viable road lever is
source-level casing-path stitching so connected road segments do not emit internal endpoint caps; no more
overpaint primitives should be attempted.

The latest full suite is **2,222 passed, 0 failed**. The final frontage audit is pixel-style-independent and
exactly matches baseline: 177 road tiles, 413 buildings measured, 79 failing tiles, 177 buildings over 15u,
137 off-road-by-design buildings, one service-lane save, 165 block-mode failures, and the same 146.6u worst
furnace on `tile_10_3`. The fixed capture harness again restored the masked legacy map region pixel-for-pixel.
After traversing all ten camera framings it also revisited the identical midcentury wide framing and reproduced
the masked map pixels exactly, ruling out stale frames and unseeded draw variation. Only the known pre-existing
fixture diagnostics and shutdown RID/resource-leak warnings remain.

This stops only the endpoint-overpaint mechanism. It does not block the overall art direction. The map-wide
result is now classified as a renderer-seam prototype: style isolation, deterministic tooling, legacy
identity, independent palette, and draw-only fabric are preserved foundations rather than an accepted final
spatial grammar.

## Hero slice — Arin Old reference-first figure/ground

Hero framing: `tile_10_16`, Arin City Old Quarter, with its neighboring Arin urban tiles. The capture harness
now also writes a fixed 960×480, 2:1 map-only crop with `UILayer` hidden. The required triptych places the
dense supplied reference at left, the renderer-seam prototype in the middle, and the current hero candidate
at right.

### H1.01 — shared warped parcel lattice

- Replaced road-anchor cards only on the Arin hero tile set with a shared, deterministic warped lattice.
- Neighboring cells share polygon boundaries, producing a continuous paper city envelope rather than
  isolated roadside lots.
- Built road corridors and gameplay footprints are subtracted from decorative masses. Rivers and real roads
  remain later authoritative layers; no gameplay road or occupancy data is created.
- Cell roles produce contiguous solid blocks, three-sided courtyard masses, irregular greens, civic squares,
  alleys, and intentional voids. Gameplay industries remain later landmark overlays.
- Diagnostic composition: 249 cells, **35.8% ordinary built mass**, **14.1% green**, and **50.1% negative
  space**. This is a large figure/ground gain over the prototype, but both built and green shares remain below
  their starting target bands.
- Evidence: `reports/map_visual_gauntlet/hero_arinold/h1_01_triptych.png`.

The critic rejected H1.01. The three largest reference gaps were sparse figure/ground, a coarse repeated
quadrilateral lattice, and checkerboard green/mass roles that dwarfed gameplay buildings. Primary scores
were: inhabited impression 3, reference resemblance 2, continuous figure/ground 2, organic parcels 2,
streets as negative space 2, green integration 3, decorative/gameplay hierarchy 2, industrial color
discipline 4, top-down discipline 4, and accumulated character 2.

### H1.02 — connected fine-grain street-wall clusters

- Reduced the cell grain from 72×54u to 56×42u and deterministically merged adjacent eligible cells into
  bounded two- or three-cell masses. Parks and intentional paper voids break the clusters into courts.
- Diagnostic composition reached the requested starting ranges: 468 cells, **52.1% ordinary built mass**,
  **16.3% green**, and **31.6% negative space**.
- Evidence: `reports/map_visual_gauntlet/hero_arinold/h1_02_triptych.png`.
- Deterministic suite: **2,222 passed, 0 failed**. Two initial sandboxed invocations crashed in Godot's
  rotating user-log setup before project startup; the permitted standard invocation completed normally.

The critic found H1.02 visibly better than H1.01 and the renderer-seam prototype, but rejected it. Its three
largest reference gaps were: decorative masses were still neighborhood-sized slabs rather than fine
perimeter blocks; roads visibly clipped a pre-existing lattice instead of causing parcel boundaries; and
green/mass cadence overwhelmed the real gameplay industries. Primary scores were: inhabited impression 3,
reference resemblance 3, continuous figure/ground 3, organic parcels 2, streets as negative space 3, green
integration 3, decorative/gameplay hierarchy 2, industrial color discipline 4, top-down discipline 4, and
accumulated character 2.

Per the two-failure stopping rule, the warped-lattice mechanism is abandoned. Its abstraction defines cells
independently of the street graph, so no further density or warp tuning can create causal road-bounded
parcels. The next mechanism must derive visual parcel faces from the existing real-road arrangement, then
subdivide those faces and place connected perimeter terraces around protected courts, alleys, and selected
green voids. This remains a visual generator only; road topology and gameplay footprints stay frozen.

### H2.01 — road-bounded parcel faces

- Replaced the abandoned lattice with one merged Arin urban envelope. Nav-grid water margins and existing
  forest occupancy are removed first; merged real built-road corridors are then subtracted to produce 25
  causally road-bounded street faces.
- Large faces are divided into 154 deterministic visual parcels by narrow subordinate alleys whose axes
  follow the current face frontage. Perimeter street walls, protected courts, greens, and gameplay-footprint
  exclusions are generated inside those faces. No road, occupancy, or simulation data is created.
- Diagnostic composition: **26.7% built**, **16.6% green**, **56.7% negative**. Evidence:
  `reports/map_visual_gauntlet/hero_arinold/h2_01_triptych.png`.

The critic accepted H2.01 over H1.02 and the renderer-seam prototype as the new hero-slice best. It is the
first candidate to score 4/5 for inhabited-world impression and streets as negative space: real roads now
visibly cause block boundaries. Industrial color and top-down discipline also scored 4. Reference-family
resemblance, continuous figure/ground, organic parcels, green integration, decorative/gameplay hierarchy,
and accumulated character remained 3. The dominant defect is a repeated thin complete courtyard-ring
grammar around oversized cream or green interiors.

### H2.02 — varied solid, L, U, and courtyard massing

- Replaced the uniform perimeter-ring treatment on built parcels with 44 solid masses, 27 U forms, 22 L
  forms, and 27 retained courtyard rings. Road faces, parcel subdivision, green roles, palette, and gameplay
  exclusions stayed frozen.
- Diagnostic composition: **38.2% built**, **15.0% green**, **46.8% negative**. Evidence:
  `reports/map_visual_gauntlet/hero_arinold/h2_02_triptych.png`.

The critic accepted H2.02 over H2.01. Inhabited impression, continuous figure/ground, streets as negative
space, industrial color discipline, and top-down discipline scored 4. Reference resemblance, organic
parcels, green integration, decorative/gameplay hierarchy, and accumulated character remained 3. The
solid/L/U abstraction is viable, but unbounded forms created several neighborhood-scale blank charcoal
fields that overwhelmed the gameplay industries.

### H2.03 — capped decorative mass grain

- Preserved the accepted solid/L/U/ring vocabulary but split only output masses longer than 84u or larger
  than 7,200u² into at most three pieces along their long axis. Narrow 3.4u visual alleys separate the pieces;
  real road geometry and parcel count remain unchanged.
- Diagnostic composition: **37.2% built**, **15.0% green**, **47.8% negative**. The batched fabric contains
  702 pieces map-wide, up from 581 in H2.02. Evidence:
  `reports/map_visual_gauntlet/hero_arinold/h2_03_triptych.png`.

The critic accepted H2.03 over H2.02 as the current hero best. Inhabited impression, continuous
figure/ground, streets as negative space, industrial discipline, and top-down discipline remain 4. The
finer grain is visibly closer to the reference, but reference resemblance, organic parcels, green
integration, decorative/gameplay hierarchy, and accumulated character remain 3 because equal-width
straight-through cuts still look planned and broad ordinary roofs still flatten the landmark hierarchy.

### H2.04 — high-frequency staggered and T alleys

- Replaced 82% of the straight cap cuts with stepped crossings and added partial T branches to 27% of those.
  Composition stayed effectively fixed at 37.1% built and 15.0% green.
- **Rejected.** Repeated hooks and dead-end T ticks appeared across unrelated blocks, reducing historically
  accumulated character from 3 to 2. Evidence:
  `reports/map_visual_gauntlet/hero_arinold/h2_04_triptych.png`.
- H2.03 remains the accepted best. One quieter second attempt is allowed: no branches and only a minority of
  cuts receive a small jog. If that remains neutral or glyph-like, the stagger mechanism is abandoned.

### H2.05 — low-frequency quiet jogs

- Removed T branches; reduced stepped cuts to 28% with a 2.5–4.5u jog. Composition and the 702-piece batch
  matched H2.03 exactly.
- **Rejected as neutral.** The repeated-glyph regression disappeared, but the remaining jogs were
  triptych-scale indistinguishable from H2.03 and did not improve any primary score. Evidence:
  `reports/map_visual_gauntlet/hero_arinold/h2_05_triptych.png`.
- Per the stopping rule, the stagger mechanism is abandoned and the exact H2.03 straight cap seams are
  restored.

### H2.06 — street-face value families

- Kept the accepted H2.03 geometry, road subtraction, parcel roles, green distribution, and 702-piece
  decorative batch exactly fixed. Only ordinary-building roof values changed.
- Assigned one deterministic warm-grey, charcoal, or khaki family to each road-caused street face, then
  allowed small within-family variation among its masses. This produces coherent neighborhood patches
  instead of a map-wide random roof-value scatter.
- Diagnostic composition remains exactly **37.2% built**, **15.0% green**, and **47.8% negative space**.
  Evidence: `reports/map_visual_gauntlet/hero_arinold/h2_06_triptych.png`.

The critic accepted H2.06 over H2.03. The clustered values visibly add district-scale accretion while keeping
streets and ordinary massing quiet; historically accumulated character rose from 3 to 4. Primary scores are:
inhabited impression 4, reference resemblance 3, continuous figure/ground 4, organic parcels 3, streets as
negative space 4, green integration 3, decorative/gameplay hierarchy 3, industrial color discipline 4,
top-down discipline 4, and accumulated character 4. The remaining hierarchy bottleneck is that real gameplay
industries still sit on the same unarticulated cream ground as decorative voids, so their compound silhouette
does not yet read as a landmark at the hero scale.

### H2.07 — gameplay-industry compound aprons

- Preserved the complete H2.06 urban fabric and added a draw-only, category-tinted compound apron inside
  the unchanged logical footprint of actual furnace, refinery, factory, power, mine, and related gameplay
  industries. The procedural machinery remains overlaid above the apron.
- The apron is inset from the exact placement polygon, uses a restrained low-chroma wash and thin warm-ink
  boundary, and never participates in click testing, occupancy, road avoidance, capacity, or land use.
- Diagnostic composition remains exactly **37.2% built**, **15.0% green**, and **47.8% negative space**;
  the decorative batch remains 702 pieces. Evidence:
  `reports/map_visual_gauntlet/hero_arinold/h2_07_triptych.png`.

The critic accepted H2.07 over H2.06. Decorative-versus-gameplay hierarchy rose from 3 to 4 because the
central machinery groups now read as functional compounds rather than symbols floating in a cream void.
All other scores held: inhabited impression 4, reference resemblance 3, continuous figure/ground 4, organic
parcels 3, streets as negative space 4, green integration 3, industrial discipline 4, top-down discipline 4,
and accumulated character 4. The focused average rose **3.6 → 3.7** with no visible secondary regression.
The largest remaining reference gaps are the still-coarse rectilinear urban grain, broad simple greens, and
the reference's larger rust-red industrial landmark.

### H2.08–H2.09 — rejected promenade-fragmented greens

- H2.08 attempted to split broad greens with narrow paper promenades and raise the probability of green
  internal courts. It reproduced H2.07 pixel-for-pixel because no visible parcel crossed the selected
  thresholds, so it was rejected as neutral.
- H2.09 made the mechanism deterministic at the mass-form level and visibly distributed greens into ring
  and U courts. Green integration reached 4, but repeated dark/cream long-axis divisions resembled miniature
  roads or rails in the waterfront, central, and northern parks. Historically accumulated character fell
  from 4 to 3. Evidence: `reports/map_visual_gauntlet/hero_arinold/h2_09_triptych.png`.
- Per the two-attempt stopping rule, promenade fragmentation is abandoned and removed completely. H2.09's
  beneficial green distribution was isolated as a different abstraction before further scoring.

### H2.10 — distributed civic courts

- Preserved every H2.07 road, parcel, building mass, industrial compound, and broad park outline. Ring-block
  courts and a deterministic minority of U-block courts now receive flat civic-green fills; no internal path
  or new line vocabulary remains.
- Diagnostic composition: **37.2% built**, **19.2% green**, and **43.7% negative space**, with the same 154
  parcels and 702-piece decorative batch. Evidence:
  `reports/map_visual_gauntlet/hero_arinold/h2_10_triptych.png`.

The critic accepted H2.10 over H2.07. Green integration rose from 3 to 4 because the irregular northern ring
court, central U-block court, eastern pocket, and small south-western court distribute civic space through
several kinds of enclosure. Inhabited impression, continuous figure/ground, streets as negative space,
decorative/gameplay hierarchy, industrial discipline, top-down discipline, and accumulated character remain
4. Reference resemblance and organic parcel structure remain 3. The focused average rose **3.7 → 3.8** with
no material regression; broad park shape/materiality remains secondary to the coarse rectilinear parcel grain.

### H2.11 — inherited oblique parcel boundaries

- Kept the merged city envelope, 25 real-road street faces, target parcel area, mass-form vocabulary, mass
  caps, green distribution, industrial compounds, and all gameplay geometry fixed. Most recursive parcel
  cuts now meet their inherited street frontage at a small deterministic oblique angle; a minority remain
  square so the result does not become uniformly skewed.
- The accepted geometry contains 151 hero parcels and 696 batched decorative pieces: **38.3% built**,
  **17.5% green**, and **44.2% negative space**. Evidence and machine-readable metrics:
  `reports/map_visual_gauntlet/hero_arinold/h2_11_triptych.png` and
  `reports/map_visual_gauntlet/hero_arinold/h2_11_metrics.json`.

The critic accepted H2.11 over H2.10. Organic parcel structure and reference-family resemblance both rose
from 3 to 4: adjoining districts now taper and change bearing like layouts accumulated at different times,
while real roads remain wider and more continuous than the subordinate cream alleys. Every primary category
now scores **4/5**: inhabited impression, reference resemblance, continuous figure/ground, organic parcels,
streets as negative space, green integration, decorative/gameplay hierarchy, industrial discipline,
top-down discipline, and historically accumulated character. The focused average is **4.0/5**. Remaining
polish issues are coarser terrace grain than the reference, a physically smaller gameplay-industry landmark,
and broad flat material treatment in a few parks; none breaks the hero-slice gate.

The capture harness now writes `/tmp/poe_hero_arinold_metrics.json` after the fixed map-only hero PNG. During
H2.11, an exact diff exposed that the already-open Godot editor can return control to its launcher before the
delegated capture scene finishes. The stale copy was discarded before critique; accepted evidence uses the
later matching PNG/JSON timestamps and differs from H2.10 at 15.29 dB PSNR. Subsequent capture verification
polls the metrics completion timestamp rather than trusting launcher return.

## H2.11 hero-slice verification

- Repeated normal-GPU hero capture: **byte-for-byte exact**. PNG SHA-256
  `c7325ff4fc3dbbcd7b8a242ecdacc17639a94acbc87b76d4c5b396d55a942f2d`; metrics SHA-256
  `7b8217cb1824ae17543bab330f12075470b56d7f65941e696f12a5db7756f3ff` on both runs.
- Full suite: **2,222 passed, 0 failed**. Expected fixture `%TerrainLayer` diagnostics and shutdown
  RID/resource-leak warnings remain; no new test failure or parser error was introduced.
- Road-frontage audit: exactly the frozen baseline—177 road tiles, 413 buildings measured, 79 failing tiles,
  177 buildings over 15u, 137 off-road-by-design buildings, one service-lane save, 165 block-mode failures,
  and the same 146.6u furnace on `tile_10_3`.
- All-style GPU capture harness completed all fixed framings. The masked legacy-before and
  legacy-after-midcentury regions share SHA-256
  `8135442f22e8a41fb09fabb3d7e8eae712e5aea73282455672e43f91b6631da3`; the first and repeated
  midcentury wide regions share SHA-256
  `ff7e1340344f5aa4325a45ded961cba6a1140b00c193a2c192460aa4f59a4e49`.
- `git diff --check` is clean. No economy, capacity, building count, road/river topology, tile/subtile data,
  occupancy footprint, click-testing, ownership, transport connectivity, or save-schema code changed.

The hero-slice objective is complete and intentionally stops before map-wide rollout. H2.11 proves the
reference-first urban figure/ground abstraction on Arin Old while the rest of the world remains the earlier
renderer-seam prototype.

## Map-wide morphology rollout

The rollout uses one UI-hidden deterministic harness, `tools/settlement_morphology_shot.tscn`, with fixed
camera, zoom, and crop for six map-only views: Arin Old (`tile_10_16`), Fort Silversworth (`tile_6_13`),
Silkstown (`tile_9_8`), Vandel Port Works (`tile_23_16`), Farpoint (`tile_29_17`), and the whole-map bounds.
The baseline set in `reports/map_visual_gauntlet/morphology/baseline/` proved that only Arin carried H2.11;
the other slices still used sparse gameplay-building scatter. The refreshed Arin harness frame has the exact
locked H2.11 PNG hash, so it is also a direct regression oracle.

### P1.01–P1.02 — explicit settlement morphology profiles

- P1.01 grouped adjoining non-hero urban tiles into deterministic connected settlements. Each tile receives
  an explicit metropolitan, town, industrial-fringe, village, or rural profile from its settlement context,
  name/road metadata, and component size. Non-rural envelopes are merged, clipped by water/forest occupancy,
  split by real built-road corridors, and subdivided into the same oblique road-face parcels proven in H2.11.
- Metropolitan/town/fringe parcels use distinct target grain, role ratios, and ordinary mass density. Unnamed
  rural tiles create no envelope. Villages choose only 1–3 central road-face clusters rather than deleting
  random buildings from a city field.
- P1.02 was one village-only refinement: each selected Farpoint cluster gained a compact back row inside the
  same face. Built coverage rose from 2.68% to **5.35%** without adding another cluster or enlarging the
  rural envelope. Evidence: `reports/map_visual_gauntlet/morphology/p1_02_accepted_profiles/`.

Accepted diagnostics:

- Arin Old: unchanged H2.11—25 street faces, 151 parcels, **38.29% built**, **17.52% green**.
- Fort Silversworth component: 50 parcels, **20.77% built**, **7.80% green**.
- Silkstown component: 22 parcels, **14.82% built**, **14.39% green**; its mixed town/works profile is visibly
  denser at the road/bridge centre and looser along the banks.
- Vandel component: 50 parcels, **19.30% built**, **15.95% yard roles** plus ordinary vacant parcels.
- Farpoint: three road faces, two selected paired frontage groups, **5.35% built**, **94.65% negative**.
- Whole renderer: 87 profiled urban tiles, 1,009 parcels, 1,546 decorative mass pieces, 255 parks, and 264
  open-lot roles; still one batched draw layer rather than per-building nodes.

The critic accepted Phase 1. Arin remains the strongest slice (density 5/5; figure/ground, hierarchy,
top-down consistency, and readability 4/5). Fort, Vandel, and the wide view scored 4/5 for settlement
density and road-caused figure/ground. Farpoint scored 5/5 for rural sparsity and 4/5 for intentional vacancy,
ordinary grain, non-repetition, top-down consistency, and readability. Phase-level weaknesses belong to
later scoped phases: stair-stepped river parks (2/5), over-large pale reservation shapes, and quiet but coarse
ordinary roofs.

Phase 1 verification:

- Every one of the six accepted PNGs and the metrics JSON reproduced byte-for-byte on a second normal-GPU
  run. Accepted hashes are stored beside the images; Arin remains
  `c7325ff4fc3dbbcd7b8a242ecdacc17639a94acbc87b76d4c5b396d55a942f2d`.
- Full deterministic suite: **2,222 passed, 0 failed**. The first sandboxed launcher attempt crashed inside
  Godot's rotating user-log setup before tests; the identical unsandboxed command completed cleanly.
- Frontage audit is byte-for-byte equivalent in its measured totals to the frozen baseline: 177 road tiles,
  413 buildings, 79 failing tiles, 177 over 15u, and 137 off-road-by-design.
- Fresh all-style capture: legacy-before and legacy-round-trip PNG SHA-256 both
  `95ba0e42c96d24f4ad2ab8117bece6fa0aa5b1ba1b2a4f3601beca5244bcb775`; first/repeated midcentury both
  `ef7296ad300c605e8b3aca04a4a05c697306e596b838e90948e179ed39bb8302`.
- `git diff --check` passed. No gameplay topology, occupancy, footprint, interaction, count, capacity,
  economy, ownership, connectivity, or save data changed.

### P2.01 — broad industry-yard radii

- Added draw-only industry metadata, a larger decorative-fabric exclusion, connected yard roles, and a
  separate muted-tan yard mesh under real gameplay industries.
- **Rejected.** A 22–31u halo plus radius-based conversion of nearby parcels reduced Fort to 14.85% built,
  Vandel to 17.49%, and Farpoint to 4.13%. Vandel became a tan blanket with distracting polygon seams; the
  mechanism over-reserved whole districts instead of clarifying individual compounds.
- The industry-yard abstraction was retained for one narrower attempt; the broad radius and seam outlines
  were removed.

### P2.02 — compact contextual works yards

- Reduced the draw-only clearance to 13–18u beyond the real logical footprint, removed halo seam outlines,
  and reserved at most the nearest 1–3 fringe parcels per industrial component. Yard and ordinary-vacant
  roles use separate muted khaki/tan fills in the independent mid-century palette; cream is again primarily
  streets and courts.
- The building renderer exposes read-only industry-site draw metadata. The fabric layer uses it only to
  clip decorative masses and paint an underlying works yard; placement legality, click/selection polygons,
  ownership, land use, and the procedural gameplay building remain unchanged.
- Fort recovered to **20.21% built** with **21.08% yard roles** in its mixed town/works component. Vandel is
  **18.73% built**, **19.75% explicit yard roles**, with a 111,086u² connected compound overlay (20.87% of
  its settlement envelope). Farpoint remains visually rural at **4.49% built** after its real gameplay
  industries receive clearance. Evidence: `reports/map_visual_gauntlet/morphology/p2_02_compact_yards/`.

The critic accepted P2.02 over Phase 1. Intentional vacancy, industrial hierarchy, density, road
figure/ground, non-repetition, and mid-century consistency all scored at least 4/5 in Arin and Fort. Vandel
scored 4/5 for vacancy, hierarchy, density, figure/ground, and consistency; its few large detached tan lots
leave artifact absence at 3/5. Farpoint retained 5/5 rural sparsity and 4/5 vacancy/hierarchy/consistency.
At wide zoom the replacement of bright cream reservations with muted tan restores geography priority. The
critic's explicit limit is to **not expand this treatment further**.

Phase 2 verification:

- All six PNGs and metrics JSON reproduced byte-for-byte. Arin remains the locked H2.11 hash.
- Full deterministic suite: **2,222 passed, 0 failed**; frontage audit remains exactly at baseline totals.
- Fresh legacy-before and legacy-round-trip hashes both remain
  `95ba0e42c96d24f4ad2ab8117bece6fa0aa5b1ba1b2a4f3601beca5244bcb775`; first/repeated midcentury both
  `2b7507c1a5afdced6a6e37023de4ca4000f2ddf329c49ef6b4e546f39a834db5`.
- `git diff --check` passed; no gameplay system or schema changed.

### P3.01–P3.02 — rejected sampled-river offset parks

- P3.01 consumed `RiverVisuals.get_river_polylines()`, built a rounded 25u bank corridor from a downsampled
  channel path, subtracted it from nearby park faces, then inset the result. It removed the original coarse
  square staircase, but created an over-wide cream promenade which competed with the real road network and
  ended in acute wedges near the bridge. Evidence:
  `reports/map_visual_gauntlet/morphology/p3_01_smooth_bank_parks/`.
- P3.02 was the second and final attempt with this visual mechanism. It reduced total channel-to-park
  separation to approximately 15–15.8u, extended the sampled endpoints and used a rounded inset. This fixed
  promenade/road ambiguity, endpoint wedges, and retained clean river overlap, but softened the former
  staircase into a conspicuous repeated crenellation of tiny alternating segments along both banks.
  Evidence: `reports/map_visual_gauntlet/morphology/p3_02_compact_bank_parks/`.

The independent critic rejected P3.02 despite its improvement over P3.01. River clarity, road-caused
figure/ground, top-down discipline, and regional/close readability scored 4/5, but river-edge park
organicity scored **3/5** and absence of repeated procedural artifacts **2/5**. No self-intersection, river
overlap, repeated promenade mark, or remaining road ambiguity was visible; the failure was specifically the
continuous serration created by polygon offset-and-clip. Under the two-attempt local stopping rule, this
sampled-offset mechanism was removed in full rather than tuned a third time. Phase 2 remains the accepted
map-wide best for park geometry. River-responsive park boundaries remain a documented unresolved weakness,
not a reason to stop the independent roof-vocabulary phase or the overall rollout.

### P4.01 — accepted contextual roof vocabulary

- Kept the H2.11 roof path byte-identical and routed morphology context only through non-hero decorative
  masses. The new close-zoom vocabulary is **66.1% plain** (764/1,155), **17.1% pitched/ridge** (198),
  **9.4% raised inset/lantern** (109), and **7.3% utility/skylight** (84). Utility marks are weighted toward
  works districts and nearly absent in villages. Raised elements use a second batched top/shadow pair with
  the established shallow south-east shadow direction; no per-building nodes were added.
- Arin Old retains the exact locked H2.11 hash. At wide zoom the detail collapses into the existing settlement
  silhouettes; at regional and close zoom, ridges, quiet inset caps, and occasional utility stripes break
  blank-roof uniformity without competing with tanks, seams, aprons, and colored roofs on gameplay
  industries. Evidence: `reports/map_visual_gauntlet/morphology/p4_01_contextual_roofs/`.

The critic accepted P4.01 over P2.02. Roof/silhouette variety, glyph absence, top-down/mid-century
consistency, gameplay hierarchy, and readability score 4/5 in town, river, fringe, and wide views. Farpoint
scores 4/5 for grain/variety/consistency/hierarchy/readability and 5/5 for non-repetition because its roof
changes remain appropriately scarce. Arin remains unchanged, including its known 3/5 coarse ordinary grain.
Town, river, and fringe ordinary grain also remains 3/5: roof vocabulary improves surface character but is
not claimed as a massing fix.

### P4.02 — rejected rare H/T/cross masses

- The first selection placed nine supported shapes (0.8% of ordinary masses) by profile-wide deterministic
  rarity, but changed none of the fixed close slices. The second and final selection tied at most one shape
  per component to the nearest real gameplay-industry site, producing 15 H/T/cross masses (1.3%) fully
  clipped inside their original decorative parcel footprints.
- **Rejected as neutral.** All five close PNGs remained byte-identical to P4.01 and the critic could not
  identify a reliable compositional or silhouette improvement in the changed wide PNG at original
  resolution. Artifact absence and wide readability remained 4/5, but gameplay-industry hierarchy stayed
  3/5 for this lever because the rare shapes were effectively invisible. Evidence:
  `reports/map_visual_gauntlet/morphology/p4_02_industry_site_masses/`.
- Under the two-attempt local rule, both special-mass selection and construction were removed completely.
  No third rarity or scale tuning was attempted. P4.01 remains the accepted Phase 4 best.

## Accepted rollout verification

- Two fresh normal-GPU runs reproduced every P4.01 PNG and the metrics JSON byte-for-byte. Final SHA-256:
  Arin `c7325ff4fc3dbbcd7b8a242ecdacc17639a94acbc87b76d4c5b396d55a942f2d`, Fort
  `07f89f9da4b1b858133c4d2dcbe65dede6ef928a0590548f65aff41fddaa4483`, Silkstown
  `e72d95d205a4c554cb3e2815c50346eccd855c80cf1e19cac24acd70f3579836`, Vandel
  `cc20cebf0e85cae13693ee8f1e1055935431de26a2c656944fa01bbe3e178a1c`, Farpoint
  `62d21b2dc6c276a9be2f5c6d797bcb5360929354375fd85836674a537d057471`, wide
  `b5d8b7e3b24a4f2cc4e05035996da7c1cafbb13e1e9cda274acfe10f19bab583`, and metrics
  `6625e5d279f13f2e1c9818f0f546e96227840b1f07fae6be675edaaa23de39be`.
- Final component diagnostics: Fort **20.21% built / 21.08% yard roles**; Silkstown **14.51% built /
  14.39% green**; Vandel **18.73% built / 19.75% yard roles / 20.87% industry compound overlay**;
  Farpoint **4.49% built / 95.51% negative**. Arin remains **38.29% built / 17.52% green / 44.19%
  negative**, with 25 real-road faces and 151 parcels.
- Full deterministic suite: **2,222 passed, 0 failed**. Expected isolated `%TerrainLayer` fixture errors,
  GUI-anchor warnings, and shutdown RID/resource leak diagnostics remain unchanged; there is no new parser,
  assertion, or test failure.
- Road-frontage audit is exactly frozen: 177 road tiles, 413 measured buildings, 79 failing tiles, 177 over
  15u, 137 off-road-by-design, one service-lane save, and the same 146.6u `tile_10_3` furnace worst case.
- The all-style GPU harness completed every classic, ink, plate, and mid-century framing. Full-PNG
  legacy-before and legacy-round-trip SHA-256 both equal
  `95ba0e42c96d24f4ad2ab8117bece6fa0aa5b1ba1b2a4f3601beca5244bcb775`; first/repeated mid-century wide
  captures both equal `3920cdd02a7f34a7764c9dcaa1011c69dbf4c297c05aa7ada00b37f88894e5e0`.
  The harness also passed its masked map-region checks and restored the preserved ink state.
- Original-resolution inspection covered the six UI-hidden morphology images plus all wide/coast/inland,
  farm, refinery, electrolyser, mine, dense, and block mid-century framings. `git diff --check` is clean.
  No economy, capacity, count, topology, ownership, connectivity, placement legality, logical footprint,
  occupancy, click/selection, tile/subtile, save-schema, or data-migration code changed.

## Final accepted fixed-slice scorecard

| Slice | Density / sparsity | Intentional vacancy | Industrial hierarchy | Road figure/ground | River-park organicity | Ordinary grain | Roof / silhouette | No repeated glyphs | Top-down / mid-century | Multiscale readability |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Arin Old | 5 | 4 | 4 | 4 | N/A | **3** | **3** | 4 | 4 | 4 |
| Fort Silversworth | 4 | 4 | 4 | 4 | N/A | **3** | 4 | 4 | 4 | 4 |
| Silkstown | 4 | **3** | 4 | 4 | **2** | **3** | 4 | **2** | 4 | **3** |
| Vandel Port Works | 4 | 4 | 4 | 4 | N/A | **3** | 4 | 4 | 4 | 4 |
| Farpoint | 5 | 4 | 4 | 4 | N/A | 4 | 4 | 4 | 4 | 4 |
| Wide | 4 | 4 | **3** | 4 | N/A | 4 | 4 | 4 | 4 | 4 |

The final critic identifies **P4.01 contextual roofs** as the highest accepted scoped phase and confirms it
is better than P2.02 while Arin stays frozen. The complete V4/V5 gauntlet does **not** formally pass: several
applicable scores remain below 4, no fixed slice reaches the requested 4.3 average, and Silkstown retains a
high-severity procedural river-edge defect. The three largest remaining weaknesses are:

1. Silkstown's repeated stair-step river-park edge, the main gate blocker.
2. Coarse ordinary-building slabs in Arin, Fort, Silkstown, and Vandel versus the references' finer terrace
   and frontage grain.
3. Gameplay industries are clear at regional/close scale but mostly disappear into settlement masses at
   world scale, leaving industrial landmark hierarchy at 3/5 in the wide view.

Farpoint is the only complete fixed slice with every applicable category at least 4/5. It demonstrates that
the explicit village abstraction succeeds: one coherent sparse frontage group, 95.51% negative space,
quiet roofs, and no city-like random deletion field.

## Next pass — settlement continuity, density direction, and Silkstown

P4.01 remains the locked accepted baseline. This pass added a seventh deterministic, UI-hidden regional
capture, `/tmp/poe_morph_capital.png`, centred on the connected Capital Port component (`tile_23_8`,
`tile_24_7`, `tile_24_8`, `tile_24_9`, `tile_25_9`). The frame includes multiple internal urban joins,
external land/water edges, built roads crossing former tile borders, and dense/loose districts. The metrics
record now also classifies each participating tile edge as internal, external rural, external hill, external
mountain, water/coast, or authoritative-road occupied. This is read-only visual evidence; it does not change
terrain, roads, placement, or simulation data.

### C1.01–C1.02 — rejected internal-edge connector bands

- C1.01 unioned every participating urban hex before removing exterior edge strips. It removed internal
  moats in Capital but expanded Fort and Vandel into full-frame pale metropolitan plates and exposed long
  parcel cuts through Farpoint countryside. Capital hard-gate scores were 3/2/4/2/3 for internal continuity,
  exterior discipline, road crossing, density continuity, and intentional vacancy.
- C1.02 restored P4.01's profile insets and filled only shared edges with connector bands. Farpoint's
  countryside cuts were removed, but Capital remained a set of western, central, southern, and eastern
  lobes. Fort regressed to 1/5, Vandel 2/5, Silkstown 2/5; Capital scored 3/2/4/3/3.
- The independent critic rejected the second attempt and required the connector mechanism to be retired:
  filling shared edges can move a local seam, but cannot create a coherent settlement-level density field.
  Evidence: `reports/map_visual_gauntlet/continuity/c1_01_union_exterior/` and
  `reports/map_visual_gauntlet/continuity/c1_02_permeable_joins/`.

### D1.01–D1.02 — rejected continuous density thresholds

- D1.01 used one merged component boundary and a smooth score from exterior distance, built-road distance,
  junction centrality, component core direction, and continuous low-frequency variation. Inactive parcels
  emitted no paper, outline, or alley. It proved that internal geometry can be removed without painting pale
  full-tile plates, but parcel-random activation still produced disconnected lobes.
- D1.02 removed the per-tile term and random dropout. A deterministic component threshold created connected
  occupied zones, smaller central grain, and directional thinning. It held Arin and Farpoint byte-identical,
  but binary occupied/unoccupied cliffs remained legible in Capital; Fort became a dense metropolitan slab
  and Silkstown lost its river-focused identity.
- The critic scored Capital 3/2/4/2/3 and the Fort/Silkstown regressions 1/5 each. Under the local two-attempt
  rule, the threshold abstraction was removed in full. Evidence:
  `reports/map_visual_gauntlet/density/d1_01_threshold_noise/` and
  `reports/map_visual_gauntlet/density/d1_02_contiguous_field/`.

### C2.01–C2.02 — rejected road-catchment envelopes

- C2.01 intersected the externally eroded component union with overlapping broad catchments grown from only
  real built-road segments and junctions. This replaced tile plates with visibly road-grown districts, but
  broad town/fringe reach created metropolitan Fort and an overbuilt Silkstown.
- C2.02 narrowed catchments by the contextual morphology profile. The measured bands were plausible in
  isolation—Capital 25.11%, Fort 24.05%, Silkstown 21.50%, Vandel 14.92%, Farpoint 4.49% built—but the image
  fragmented into overlapping road ribbons and residual shards. Capital scored 3/2/4/2/2; Fort, Vandel, and
  Silkstown each regressed to 1/5, while Farpoint remained 5/5.
- The critic rejected and retired catchment geometry as the primary envelope. Road proximity remains a
  valid future weighting input, but not the source of settlement boundaries. Evidence:
  `reports/map_visual_gauntlet/catchment/c2_01_broad_road_catchments/` and
  `reports/map_visual_gauntlet/catchment/c2_02_profile_reach/`.

All three rejected mechanisms were removed after their second attempt. A restoration capture reproduced
every frozen P4.01 image byte-for-byte before the Silkstown work began: Arin
`c7325ff4fc3dbbcd7b8a242ecdacc17639a94acbc87b76d4c5b396d55a942f2d`, Fort
`07f89f9da4b1b858133c4d2dcbe65dede6ef928a0590548f65aff41fddaa4483`, Silkstown
`e72d95d205a4c554cb3e2815c50346eccd855c80cf1e19cac24acd70f3579836`, Vandel
`cc20cebf0e85cae13693ee8f1e1055935431de26a2c656944fa01bbe3e178a1c`, Farpoint
`62d21b2dc6c276a9be2f5c6d797bcb5360929354375fd85836674a537d057471`, and wide
`b5d8b7e3b24a4f2cc4e05035996da7c1cafbb13e1e9cda274acfe10f19bab583`.

### S1.01 — unaccepted Silkstown riverfront-street candidate

A read-only oracle, `tools/silkstown_geometry_dump.tscn`, consumed
`RiverVisuals.get_river_polylines()` and recorded the exact Silkstown channel plus five built-road
approaches. The first candidate derives two smoothed 40u bank-parallel paths from that sampled channel,
restricts all four endpoints to nearby points on those real roads, rejects any path sampled over water,
draws each street as a narrow cream/ink line with no centre marking, and adds its draw-only corridor to the
parcel-face subtraction. It changes no `RoadNetwork` edge, bridge, pathfinding, ownership, placement,
frontage audit, or save record.

This candidate is **not accepted and not scored**. The environment exhausted its approved Godot-execution
quota immediately before the parse/capture run and reports that launches are unavailable until
2026-08-18 16:30. `git diff --check` passes, and static inspection finds no remaining continuity/catchment
code, but no claim is made that S1.01 parses, draws, connects both banks, avoids water, or improves the
Silkstown image. Its executable renderer hooks were removed when capture became unavailable; only the
successful read-only geometry oracle and this documented construction remain. This keeps the active renderer
at the last GPU-verified P4.01 implementation. The deterministic suite, repeated capture,
legacy round-trip, road-frontage audit, and
critic pass are therefore still required before this candidate may be kept.

### Pass status

- Highest accepted result remains **P4.01 contextual roofs**; no new continuity or Silkstown gate passed.
- Arin H2.11 and the P4.01 fixed-slice baseline remain the compatibility targets.
- Three distinct continuity abstractions were tried twice and locally retired; this does not classify the
  overall art direction as blocked.
- Remaining visual work, in order: design a different Silkstown river-edge mechanism and capture/critic it;
  if accepted, run all phase invariants; then reassess settlement continuity with a non-band, non-threshold,
  non-catchment abstraction; only after continuity succeeds, add compact junction-selected tall-building
  micro-cores and far-zoom silhouettes from that same accepted field.

### Resumed deterministic verification — 2026-08-12

The post-quota foundation checks are now complete against the restored P4.01 renderer. S1.01 remains
unaccepted and has no executable renderer hooks; this checkpoint verifies the preserved foundation rather
than claiming a new Silkstown iteration.

- Full deterministic suite: **2,222 passed, 0 failed**. The established isolated GUI-anchor warnings and
  Godot shutdown RID/resource diagnostics remain; there is no parser or assertion failure.
- The all-style GPU harness completed classic, ink, plate, and mid-century captures. Full-PNG
  `legacy_before` and `legacy_roundtrip` SHA-256 are both
  `95ba0e42c96d24f4ad2ab8117bece6fa0aa5b1ba1b2a4f3601beca5244bcb775`. First and repeated
  mid-century wide captures are both
  `3920cdd02a7f34a7764c9dcaa1011c69dbf4c297c05aa7ada00b37f88894e5e0`. The harness also passed its
  masked map-region round-trip check.
- Road-frontage audit remains exactly frozen: **177** road tiles, **413** measured buildings, **79** failing
  tiles, **177** buildings over 15u, **137** off-road-by-design buildings excluded, one service-lane save,
  and the same 146.6u `tile_10_3` furnace worst case.
- Two independent normal-GPU morphology runs produced byte-identical Silkstown PNGs with SHA-256
  `e72d95d205a4c554cb3e2815c50346eccd855c80cf1e19cac24acd70f3579836`; this also exactly matches the
  accepted P4.01 `morphology/p4_01_contextual_roofs/river.png`. The expanded metrics JSON, which now includes
  Capital and edge-class diagnostics, was also byte-identical across both runs at
  `1a43592d0676bfe207eba910df8b98fdc191caee20b52aba67112befd849476e`.
- Original-resolution inspection confirms the capture is stable, not improved: Silkstown's stepped
  river-facing park boundary remains the highest-severity local visual defect. `git diff --check` passes.

This closes the outstanding deterministic-suite, legacy round-trip, frontage-audit, and Silkstown-capture
verification items. Highest accepted result remains **P4.01 contextual roofs**.

## SettlementPlan prototype — 2026-08-12

Work continued on branch `codex/settlement-plan-prototype` from commit
`fa1fbc96c33e2df04601de1d6ac616922ace7729`, preserving the existing dirty worktree without stashing,
discarding, or absorbing unrelated changes. P4.01 remains preserved as comparison/fallback evidence; the
classic, ink, and plate compatibility locks were not altered.

### Diagnostic correction and architecture

`SettlementPlan` now explicitly separates settlement extent, authoritative and decorative street data,
district guides, enclosed faces, role parcels, ordinary masses, industrial reservations, open lots, and
later height/far-zoom consumers. It is draw-only. The Silkstown builder consumes exact river polylines,
built-road segments, and real gameplay-footprint/industry rectangles; it does not write any authoritative
map or simulation record.

The edge diagnostic now records independent properties rather than a mutually exclusive class:
`internal_to_same_settlement`, `crossed_by_authoritative_road`, `external_terrain_type`, and
`water_adjacent`. Capital Port's complete seven-tile component reports 8 real internal edges (16 sides),
with 8 internal edges crossed by authoritative roads. Assertions fail capture if the component or internal
edges disappear. This diagnostic-only change reproduced all six P4.01 fixed-capture hashes byte-for-byte.

The former Silkstown geometry oracle was also found to be mislabeled: hard-coded coordinates `(9, 8)` and
`(9, 9)` resolve to `tile_10_9` and `tile_10_10`, not Silkstown. The corrected oracle resolves IDs
`tile_9_8` and `tile_9_9` through `id_to_coord`; their true coordinates are `(8, 7)` and `(8, 8)`. It records
two river paths, 21 raw built-road records (including redundant network geometry), three gameplay
footprints, and three industry sites. Therefore the earlier claim of exactly five Silkstown approaches is
superseded by the corrected evidence.

### S0 — Silkstown street graph

**S0.01 rejected.** Hypothesis: two authored Catmull paths could connect real approaches while following
opposite inhabited banks. Layer changed: decorative street graph. The first capture had 14 valid faces and
all four endpoints within 0.06u of real roads, but 64 of 408 sampled street points entered the river mask.
The southern street repeatedly changed banks through the meanders. Rejected as a structural route failure;
the next lever was a single continuous east-bank alignment.

**S0.02 rejected.** The east-bank reconstruction reduced the failure to one coarse-water-mask contact at
`(4292.88, 4629.84)`. It was visibly smooth and retained real-road endpoints, but the hard gate is zero wet
points. Evidence is preserved in
`reports/map_visual_gauntlet/settlement_plan/s0_02_east_bank/`. The next lever moved only that inland bend.

**S0.03 accepted.** Evidence:
`reports/map_visual_gauntlet/settlement_plan/s0_03_accepted_street_graph/`. The executable capture gates
report 11 enclosed faces, two decorative streets, zero wet samples, endpoint distances
`[0.0, 0.0531, 0.0, 0.0]`, zero face self-intersections, all three district guides enclosed, and no geometry
errors. The streets use no centre marking, remain visibly narrower/quieter than authoritative roads, and
produce a smooth block/street/embankment/river ordering. PNG SHA-256:
`964a7d0221c99f52d15617a2dfe0cd8a7ef760c1f9490238e2fcd027f71122b5`.

### S1 — Silkstown zoning

**S1.01 rejected.** Hypothesis: each road-enclosed face could receive one contextual role. Layer changed:
zoning. This made a 92k-unit eastern face one industrial yard and a 60k-unit central face one park—two
oversized plates rather than accumulated districts. Role areas were 81,818 built, 59,662 park, 99,355 yard,
and 3,000 open. Evidence:
`reports/map_visual_gauntlet/settlement_plan/s1_01_face_roles_rejected/`. The failure demonstrated that a
street face is not necessarily a land-use parcel; the next structural lever added a parcel layer inside
faces.

**S1.02 accepted.** Thirty deterministic role parcels subdivide the 11 faces independently of building
massing. The accepted starting allocation is 113,019 built-role area (46.4%), 58,153 park (23.9%), 44,278
yard (18.2%), and 27,889 intentional vacancy (11.5%). Parks are road-enclosed, yards are nearest the three
real industries, and vacancy is peripheral. Evidence:
`reports/map_visual_gauntlet/settlement_plan/s1_02_parcel_roles_accepted/`. This accepted the face/parcel
separation; subsequent S2 visual review was allowed to refine the role allocation without changing S0.

### S2 — Silkstown massing

**S2.01 rejected.** Layer changed: plan-to-renderer seam. The first visible plan render produced 37 masses,
27.3% built mass, 23.4% green, 18.2% yard, and 11.4% intentional vacancy. It proved that Silkstown alone
could bypass legacy morphology while all other settlements remained unchanged, but mass concentrated at
outer edges and left the industry/river centre as large green and paper plates. Evidence:
`reports/map_visual_gauntlet/settlement_plan/s2_01_literal_parcel_massing_rejected/`.

**S2.02 rejected as an overall candidate, retained mechanism.** Layer changed: building grain only. Built
parcels subdivided into 3–5k-unit frontage groups with narrow alleys, increasing masses from 37 to 53 and
built coverage from 27.3% to 33.7%. Grain and alleys visibly improved, but unchanged zoning still left an
empty centre. Evidence:
`reports/map_visual_gauntlet/settlement_plan/s2_02_finer_grain_zoning_failed/`. The next lever returned to
zoning rather than retuning mass grain.

**S2.03 rejected as an overall candidate, retained zoning direction.** One focused zoning retune
consolidated park-role area near the river-green guide and converted disconnected central greens to built
frontage. This produced 63 masses, 41.8% built mass, 11.4% green, 18.2% yard, and 11.4% vacancy. Settlement
continuity improved, but several new ordinary masses were monolithic dark slabs that competed with real
industries. The next lever changed form, not density.

**S2.04 rejected as an overall candidate, retained ordinary massing.** Plan-driven built parcels select
only deterministic U, L, and ring forms, never the generic solid form. The result has 77 ordinary masses,
39.3% built coverage, explicit courts, and 15.4% green. It removes the slab defect and more closely matches
the reference family's perimeter/courtyard grammar. Industrial hierarchy remained the sole high-severity
weakness because three real plants were too small at regional scale.

**S2.05 current candidate.** Layer changed: industrial landmark compounds only. Each real gameplay
industry receives a draw-only apron plus one loading/support shed, one tank, and short service/roof marks.
The visual compound adds 17,481 square units and six support masses without changing logical footprints,
selection, occupancy, ownership, capacity, or economy. Ordinary massing remains 39.3% built with 77
perimeter/U/L masses; the complete plan records 83 visible masses. Evidence:
`reports/map_visual_gauntlet/settlement_plan/s2_05_industry_compounds_candidate/`. Close and regional hashes
are `f1ae596f07e03e6b27690db44f6fc9aec666d92a219d4c7ed617e91f6bdb9090` and
`8943b0be021d4427490c917e8ffc983206b5434afdf7a03fe358aa2a2fd7f3a6` respectively. Independent critic
scoring accepted the candidate at **4/5 in every mandatory category**:

- river-park organicity 4/5: smooth S-curve boundary and varied green/open parcels replace stepped banks;
- absence of repeated procedural artifacts 4/5: no serration, repeated edge glyph, self-intersection, or
  river overlap;
- road-caused figure/ground 4/5: connected cream negative space, clear bridge, and route-responsive blocks;
- ordinary grain 4/5: varied L/U masses, courts, angles, and orientation shifts, with some broad southern
  bars remaining as polish;
- industrial hierarchy 4/5: restrained tan aprons, tanks, equipment, and real brown gameplay buildings
  separate the working district from ordinary dark fabric;
- multiscale readability 4/5: equipment, courts, and roof marks resolve close up while river, bridge,
  industries, settlements, and terrain remain clear regionally.

The critic identified three remaining differences from the references: the reference urban grain is more
continuous across both banks; S2.05's cream bank corridor is smoother/more formal; and reference industrial
landmarks use stronger salmon/rust color. These are retained polish limitations, not gate failures.
**Silkstown S2.05 is accepted and materially better than P4.01.** Capital Port continuity may proceed.

### Capital Port SettlementPlan continuity

**C0.01 accepted plan diagnostic.** One draw-only plan consumes all seven recorded component tiles and
defines a single authored outline unrelated to the individual hex silhouettes. Real roads, exact river
polylines, gameplay footprints, and industrial reservations are subtracted before 31 valid faces are
retained. A first capture was rejected by its executable geometry gate because one tiny residual loop at a
dense road junction self-intersected; face construction was corrected to discard only invalid residual
faces. The accepted C0 metrics report all 8 internal edges, 91.15% mean internal-edge-band coverage versus
67.79% on external bands, a 47.89u longest internal empty strip, zero self-intersections, and no validation
errors. Evidence: `reports/map_visual_gauntlet/settlement_plan/capital_c0_01_accepted_plan/`.

**C1.01 accepted visible Capital prototype.** The component-wide faces subdivide into 122 role parcels
assigned from Market Row and Old Quarter cores, Docks/Industrial Zone/Foundry works guides, the harbor-green
guide, and distance to the one true external boundary. Former tile borders are never consulted for zoning
or massing. The result contains 480 masses with area distribution min 119, median 1,058, p75 1,744, and max
4,378 square units. Measured composition is 40.31% built, 14.48% green, 15.21% yard, and 11.03%
intentional vacancy; the largest ordinary parcel is 50,451, largest continuous paper polygon 21,524, and
intentional open-lot area 167,484.

The independent critic accepted C1.01 at **4/5 in every applicable category**:

- internal continuity 4/5: west, north-port, south, and eastern districts connect through roads, bridges,
  frontage, and purposeful green/industrial transitions without a tile-width separator;
- external boundary discipline 4/5: the peninsula and lakeshore loosen into rural/open land;
- authoritative-road crossing 4/5: routes cross district joins continuously and bridges remain legible;
- density continuity/polycentricity 4/5: multiple recognizable centres share one continuous city;
- vacancy/park intention 4/5: greens follow water/roads/districts and tan yards remain tied to facilities;
- no full-frame pale plate or shards 4/5: no settlement sheet, overlap, or residual-sliver field;
- multiscale readability 4/5: lake, rivers, bridges, quarters, green belt, port, and works separate
  immediately while close detail remains discoverable.

All Capital hard gates pass. The 47.9u worst internal gap is visually absorbed by roads, water, parks, or
yards rather than exposing a former hex seam; tile borders cannot be reliably reconstructed; the city is
polycentric; external edges are looser; rural surroundings remain readable; and no pale plate, overlap, or
shard defect remains. The critic rates C1.01 materially better than every rejected C1/D1/C2 predecessor.
Remaining differences from the supplied references are coarser ordinary grain, quieter/distributed industry
instead of a few salmon/rust landmarks, and a more open lake/green/campus composition. Evidence:
`reports/map_visual_gauntlet/settlement_plan/capital_c1_01_candidate/`.

**Visual stopping point reached:** Silkstown and Capital Port both pass their mandatory visual gates. The
required deterministic, repeat-capture, legacy round-trip, frontage-audit, and diff checks follow below.

### SettlementPlan final deterministic verification

The accepted Silkstown S2.05 and Capital C1.01 renderer-seam prototypes completed the required invariant
pass on 2026-08-12:

- Full deterministic suite: **2,222 passed, 0 failed**. The direct sandboxed launch first stopped before
  test discovery because Godot could not rotate its `user://logs` file; the normal approved launch then
  completed successfully. Only the project's established Godot shutdown RID/resource diagnostics remain.
- Two independent normal-GPU fixed morphology runs were byte-identical. Capital SHA-256 was
  `304a2cbfd92add520d4e27148f13365b07555b469eba2fc41d06c00f42d4b4e7`; Silkstown was
  `94d68ea353b2f6572225d70c5249f8d508df7afe7cae57f709c02b4bab8811df`; and the complete metrics JSON was
  `6e38ea2451ad961ca61972443ada2f9742e68eb51aa6a1eff50babb9a39080d9` in both runs.
- The all-style capture harness passed. Repeated mid-century wide captures were full-PNG identical at
  `4f224a464b92490b14c3088631f97e6f5cf1496e47274e170ddfb3415408504c`. The ink capture before enabling
  mid-century and the capture after disabling it were full-PNG identical at
  `95ba0e42c96d24f4ad2ab8117bece6fa0aa5b1ba1b2a4f3601beca5244bcb775`; the harness's explicitly masked
  map-region comparison also passed.
- Road-frontage audit remains frozen: **177** road tiles, **413** measured buildings, **79** failing tiles,
  **177** buildings over 15u, **137** off-road-by-design exclusions, one service-lane save, and the same
  146.6u `tile_10_3` furnace worst case. SettlementPlan does not participate in placement or frontage.
- `git diff --check` passes. No economic rule, capacity, building count, authoritative road/river topology,
  occupancy, visual/logical gameplay footprint, selection, click testing, ownership, or save data changed.

**SettlementPlan stopping point passed.** Silkstown S2.05 and Capital C1.01 both meet every mandatory
visual category at 4/5 and all deterministic invariants are green. Accepted image evidence remains in
`reports/map_visual_gauntlet/settlement_plan/s2_05_industry_compounds_candidate/` and
`reports/map_visual_gauntlet/settlement_plan/capital_c1_01_candidate/`. Remaining polish is deliberately
deferred: finer ordinary Capital grain, stronger but still rare salmon/rust industrial landmarks, less
formal Silkstown bank geometry, and a denser cross-bank urban relationship.

## Water-safe massing and pre-plate land/water palette — 2026-08-12

Starting point: accepted Silkstown S2.05 and Capital C1.01. The fixed pre-change views are preserved in
`reports/map_visual_gauntlet/water_palette/wp0_accepted_start/`. This pass did not redesign settlement
extents, authored streets, density, parks, or industrial compounds except where the shared water exclusion
removed a confirmed intersection.

### W1.01 — accepted shared water exclusion

**Hypothesis:** the apparent cross-bank Capital buildings originate in the plan/massing safety seam, not
river linework. Architectural layer changed: shared draw-only water geometry and final visual validation.

`RiverVisuals.get_water_exclusion_geometry()` now buffers the same sampled river paths and exact rendered
widths used by the visible river. The width includes the 15u channel (25u at mouths), current mid-century
casing, and a 4u building-bank clearance. Godot's joined round polyline offset supplies continuous bends and
closed caps; all path buffers are unioned across branches and tile joins. Selection is based on buffered
intersection with the complete SettlementPlan extent, not membership in an urban tile. Source-lake beans
and the baked inland-lake polygons are included through their visible geometry.

Capital now consumes 11 intersecting river paths, including adjacent non-urban sources, merged into two
continuous exclusion polygons. The mask participates in face and parcel construction and is independently
enforced when ordinary masses, industry supports, raised roof caps, roof marks, and southeast shadows are
emitted. An unsafe proposed mass is rejected whole; it is never retained as two clipped remnants under one
visual identity. Gameplay bridges are untouched and remain rendered by the authoritative transport layer.

The accepted diagnostic is
`reports/map_visual_gauntlet/water_palette/w1_water_safe_accepted/capital_water_diagnostic.png` with metrics
beside it. Distinct face colours show each land-side mass; blue shows the merged exclusion and exact river
path. All hard counters are zero:

- `ordinary_mass_water_overlap_area = 0.0`;
- `industrial_support_water_overlap_area = 0.0`;
- `cross_bank_mass_count = 0`;
- `disconnected_mass_after_water_clip_count = 0`;
- `roof_element_water_overlap_count = 0`;
- `shadow_water_overlap_count = 0`;
- `uncovered_river_join_count = 0`.

Capital retains 31 street faces, 119 role parcels, 356 safe visible masses, 90.10% internal-edge-band
coverage, and the prior 47.89u longest internal empty strip. Original-resolution inspection confirms that
the river now separates complete building identities on either bank, bridge decks remain clear, and the
component still reads as one polycentric settlement. **Accepted: Capital continuity remains 4/5.**
Silkstown's fixed pre-palette image remains byte-identical to S2.05 because its authored faces were already
land-side; the shared check nevertheless reports the same seven zero counters there.

### P1.01 — accepted exact pre-city-plate palette restoration

**Hypothesis:** exact pre-plate ink land/water values will restore figure/ground separation without changing
building, road, forest, contour, or settlement geometry. Architectural layer changed: mid-century palette
only.

`MapMidcenturyStyle` now owns exact read-only copies of `MapStyle._BAND_INK`, `_SEA_INK`, and `_WATER_INK`.
It does not consult the selected legacy style. The current mid-century casing, water lining, contour geometry
and weights, parchment, forest palette, building colours, roads, parcels, parks, yards, and lots remain
unchanged. Planned faces still receive paper/cream or contextual lot fills, so restored green relief cannot
leak into the connected ground between city masses.

Accepted before/after evidence is in `reports/map_visual_gauntlet/water_palette/wp0_accepted_start/` and
`reports/map_visual_gauntlet/water_palette/p1_preplate_palette_accepted/` for wide, Capital, Silkstown,
rural relief, coast, and ordinary town. At original resolution:

- outside-settlement relief returns to a controlled olive/straw/sienna progression while planned urban
  ground remains cream/pale paper;
- dark grey ordinary roofs separate materially better from countryside;
- roads remain the lightest continuous paths;
- sea depth, shelf, lakes, and rivers recover the older blue hierarchy without added saturation elsewhere;
- parks remain darker/more neutral than countryside and retain their parcel boundaries;
- Capital/Silkstown structure, building density, roofs, industrial hierarchy, and road widths do not change;
- the ordinary town remains a bound paper-ground district rather than isolated blocks on green.

**Accepted: palette clarity 4/5, urban-ground continuity 4/5, water contrast 4/5, relief readability 4/5,
road hierarchy 4/5, settlement-structure preservation 4/5.** No compensating density, roof, or road change
was made.

### Final verification

- Two independent normal-GPU runs are byte-identical: Capital
  `61c558a060abf795ee5845d83f8e54141f6a25739791601ace1e4f947849be66`, Silkstown
  `85049d980fb8a2c48112a05736a88f91812e9f660fe9f0b9a7d586863c2e79d7`, wide
  `70f4b7600a5584ca6b4c77d7c10ed1e643e4683c7fa806e90d5595c9231c81f8`, and metrics JSON
  `91ed1159873337eba97f23a904e345ea8610b64bc91263502a294b1d8b737153` in both runs.
- Full deterministic suite: **2,222 passed, 0 failed**. Only established Godot shutdown RID/resource
  diagnostics remain.
- All-style harness passed every classic, ink, plate, and mid-century framing. Frozen wide hashes remain
  classic `c263cf6595b45e480d037c94c91c8c1b8f14f1b2423fd4521b7740b45ca9045a`, ink
  `95ba0e42c96d24f4ad2ab8117bece6fa0aa5b1ba1b2a4f3601beca5244bcb775`, and plate
  `3a98e9399c83d36ea10c370769a334bcbd0c13704c9a3d94410f72877a94ddf6`.
- Legacy ink before and after the mid-century round trip is full-PNG identical at
  `95ba0e42c96d24f4ad2ab8117bece6fa0aa5b1ba1b2a4f3601beca5244bcb775`; the explicitly masked map-region
  assertion also passes. Repeated mid-century wide captures are identical at
  `c44e4c3b4c582ba87d996952bf3f6c77f78c161652797b5392c36392b52e46ad`.
- Road-frontage audit is frozen: 177 road tiles, 413 measured buildings, 79 failing tiles, 177 buildings
  over 15u, 137 off-road-by-design exclusions, one service-lane save, and the same 146.6u `tile_10_3`
  furnace worst case.
- `git diff --check` passes. Authoritative river/road topology, bridges, terrain classification, gameplay
  footprints/occupancy, placement, selection/click testing, building count/capacity, economy, ownership,
  transport connectivity, and save data/schema are unchanged.

**Pass stopping point reached:** water-safe massing and the exact pre-plate land/water palette are accepted.
Remaining visual limitations are unchanged from the SettlementPlan pass: Capital's ordinary grain is still
coarser than the supplied references, industrial landmark colour remains muted, and Silkstown's embankment
street is more formal than the reference family.

## Rotation, relief, accommodation and road-led growth pass — 2026-08-12

Starting point: locked Silkstown S2.05, Capital C1.01, water exclusion W1.01, and palette P1.01. This pass
does not alter settlement extents, water geometry, the accepted palette, authoritative roads or rivers,
gameplay footprints, occupancy, placement, economy, interaction, or save data.

### A1.01 — accepted rotation-aware industrial compounds

Industrial apron planning now offsets each exact oriented gameplay footprint polygon rather than its
axis-aligned bounding rectangle. Loading sheds, tanks, equipment, and service marks use the footprint's
principal tangent/normal basis. Irregular footprints retain their outline instead of becoming oversized
rectangular plates. The visible apron may be clipped by water, roads, unrelated gameplay footprints, or
relief shoulders, but its compound record remains oriented to and contains its own authoritative building.

The fixed three-building capture and metrics live in
`reports/map_visual_gauntlet/relief_growth/a1_01_oriented_industry_compounds/`. All selected rotated targets
emit; apron containment, missing-apron, unrelated-gameplay, road, water, relief, and support/building overlap
counters are zero. Maximum measured principal-axis drift is below 0.0064 degrees. Repeated captures were
byte-identical. **Accepted:** the compounds visibly follow their buildings and no gameplay geometry changed.

### B1.01 — accepted relief-aware decorative massing

`HillVisuals.get_land_relief_geometry()` exposes read-only plateau classifications and narrow protected
shoulders derived from the exact baked contour polygons it renders. Material three-or-more-band areas split
decorative parcels before massing. Ordinary fills, masses, shadows, roofs, marks, and industrial supports
avoid the protected corridor; authoritative roads may still cross it. Existing gameplay footprints are never
moved and are reported separately when they already cross a contour.

Two face-level mechanisms were rejected before acceptance. Broad face subtraction erased districts and
damaged Capital continuity; replacing it with a narrow face-level stroke still reduced internal band
coverage. After two failures the mechanism was abandoned. B1.01 instead preserves the road-caused face graph
and splits parcels/massing by connected plateau. This retains Capital's accepted 90.10% internal-edge-band
coverage and 47.89u longest internal gap.

Evidence lives in `reports/map_visual_gauntlet/relief_growth/b1_01_relief_aware_massing/`: a steep multi-band
tile with continuously visible contours, an occupied higher plateau with a coherent small cluster, and a
usable higher plateau deliberately left open. Across every plan and generic component, contour-crossing
decorative masses, shoulder-overlapping decorative fill, disconnected post-relief masses, and multi-band
decorative buildings are all zero. Capital reports 26 and Silkstown three pre-existing gameplay-footprint
contour conflicts without moving their artwork. Repeated screenshots and metrics were byte-identical.

### Accepted-phase invariant verification

- Full deterministic suite: **2,222 passed, 0 failed**. The first sandboxed launch hit the documented Godot
  log-rotation crash before discovery; the permitted standard run completed. Only established fixture and
  shutdown RID/resource diagnostics remain.
- The all-style harness initially exposed a real capture reproducibility defect: the first wide frame could
  sample HillVisuals' temporary vector fallback while a later identical frame used its completed far-zoom
  texture. A style-generation guard now prevents an obsolete asynchronous relief bake from publishing after
  a style change, and the harness waits on the matching renderer generation before capture.
- After that harness repair, repeated mid-century wide images are byte-identical at
  `6d1a4f9738feb74574795ee59ab6afd88dd4d47f0568490bd3519ecff52119da`.
- Frozen legacy wide hashes remain exact: classic
  `c263cf6595b45e480d037c94c91c8c1b8f14f1b2423fd4521b7740b45ca9045a`, ink
  `95ba0e42c96d24f4ad8117bece6fa0aa5b1ba1b2a4f3601beca5244bcb775`, and plate
  `3a98e9399c83d36ea10c370769a334bcbd0c13704c9a3d94410f72877a94ddf6`.
- Ink before and after mid-century is full-PNG identical at the frozen ink hash; the masked map-region
  assertion passes.
- Road-frontage audit is frozen: 177 road tiles, 413 buildings, 79 failing tiles, 177 over 15u, 137
  off-road-by-design, one service-lane save, and the same 146.6u `tile_10_3` furnace worst case.
- All seven accepted water counters remain zero. Relief failure counters remain zero. `git diff --check`
  passes.

**A1.01 and B1.01 accepted.** The next isolated architectural layer is C: deterministic, style-independent,
draw-only future-building accommodation sites planned before decorative massing.

### C1.01 — accepted future-building accommodation sites

`AccommodationSitePlanner` now creates deterministic, oriented, draw-only site polygons from the same land,
road/access, water, relief, forest, and gameplay-footprint inputs used by the visible building layer. Planning
runs before decorative massing, and accepted sites are excluded from later decorative buildings without entering
gameplay occupancy, selection, placement legality, economy, capacity, or save data. `SettlementPlan` records the
sites, while `BuildingVisuals` continues to own the authoritative gameplay footprint.

Across 86 eligible developed tiles the planner finds **450 valid sites**: 211 small, 189 medium, and 50 large.
Every accepted site has authoritative-road or access-lane reach. Twenty-seven tiles have documented physical
shortfalls rather than manufactured points; their rejected candidate counts identify the actual limiting land,
relief, road/access, water, gameplay, forest, and pairwise exclusions. Thirty-four tiles support at least one
large site. Pairwise, water, contour, existing-gameplay-footprint, and decorative-mass overlap counts are all
zero. Enabling or disabling the mid-century renderer produces the same accommodation signature,
`6379b3d2a9223d792b851d96a75192dbaad2e86a99ddbfaf2925a9ade0661766`.

The non-saving insertion harness tests a releasable park, a releasable yard, and an industrial-growth site.
Each hypothetical footprint removes exactly its one overlapping site, retains the other 449, leaves zero
releasable fragments, zero retained-site overlap, and zero hypothetical/decorative-mass overlap. Surrounding
decorative mass remains 1,060 before and after each local rebuild, and match state is unchanged. One early
headless invocation was rejected because the visual harness requires a rendering device and emitted null-image
texture errors; it was rerun in the normal renderer and is not counted as a mechanism iteration.

Evidence is in `reports/map_visual_gauntlet/relief_growth/c1_01_accommodation_sites/`.
**Accepted:** deterministic/site independence 5/5, authoritative access 5/5, size/use diversity 4/5,
visual integration 4/5, clean hypothetical yield 5/5, gameplay isolation 5/5.

### D1.01 — accepted road-dependent rural growth

Rural settlement now uses a separate route-led generator rather than the city face/parcel generator. It selects
an authoritative trunk first, otherwise the longest through-road continuing beyond the tile, then places
frontage groups, secondary junction concentrations, and a limited back row. It skips roadless tiles. Candidate
phase is shared across adjacent tiles on the same authoritative edge, so the pattern does not restart at each
hex centre.

The accepted world produces **214 rural masses on 53 road-bearing rural tiles**. Of these, 175 are within one
frontage depth of the selected route (**81.78%**), 13 belong to secondary junction groups, and 39 form limited
back rows. Twenty-nine roadless tiles are explicitly skipped. Route `e:1166` provides fixed cross-tile evidence
through `tile_23_14` and `tile_23_15`. Water, relief, forest, gameplay-footprint, and authoritative-road overlap
counts are all zero.

Camera selection was also treated as a visual variable, not a geometry change. The `tile_17_4`/`tile_17_5`
framing was rejected as water/hill dominated; the first `tile_23_14`/`tile_23_15` framing was rejected as too
tight on industry and mountain; `tile_3_17`/`tile_5_17` was rejected because competing routes obscured the
single-route test. The accepted 0.72 regional framing keeps the road ribbon, negative terrain, and cross-tile
continuity visible together.

Evidence is in `reports/map_visual_gauntlet/relief_growth/d1_01_road_dependent_rural/`.
**Accepted:** road dependency 5/5, frontage-first distribution 5/5, cross-tile continuity 4/5,
rural negative space 4/5, junction restraint 4/5, safety 5/5, absence of uniform scatter 4/5,
regional/wide readability 4/5.

### E1.01 — accepted promoted-frontage suburban seam

Two proposed suburban mechanisms reached the local stopping rule and were removed:

1. An offset-band fringe around Fort Silversworth produced no accepted masses in two attempts. The first band
   fragmented against relief; the corrected union still left 15 relief rejections and six outside-land
   rejections. It was an abstract ring, not credible relief-aware urban growth.
2. Independent road-chain branches were tested on authoritative connectors at Fort Silversworth and Blackfarm.
   Fort accepted zero masses because all seven candidates crossed relief shoulders; Blackfarm accepted zero
   because all 18 candidates did. After two failures of the same branching mechanism it was abandoned.

The accepted abstraction promotes already validated D1.01 frontage records at a true works-settlement edge into
`SettlementPlan.suburban_districts`. It does not add or move decorative masses and therefore inherits the exact
water/relief/forest/gameplay/road safety of those records. The pilot `suburban|vandel-tallow-fringe` follows
authoritative route `e:1166` from source tiles `tile_22_16` and `tile_23_16` into `tile_23_14` and
`tile_23_15`. It contains 11 relief-safe frontage masses, seven garden/small-green parcels, two connected 3u
draw-only access lanes without centre marks, and two integrated accommodation records. The route has 74 sampled
points and the district crosses a tile boundary.

Road-connection, floating-street, water, relief, forest, gameplay, decorative, accommodation, and mountain
failure counters are all zero. The district adds no authoritative road, no pathfinding edge, no frontage-audit
input, and no save/ownership record. The accepted capture reads as a deliberately sparse industrial suburb:
the lake, quarry relief, real industries, authoritative route, garden parcels, and low frontage groups establish
an urban-to-rural works edge. It is not presented as a mature detached-house suburb.

Rejected capture choices included a four-mass Peatsfield view that read as a forest hamlet, a five-mass
Blackfarm view dominated by water/agriculture with its urban source clipped, and an initial 0.82 Vandel crop
that hid the regional transition. The accepted 0.62 Vandel/Tallow capture retains the industrial context and
outward negative space.

Evidence is in `reports/map_visual_gauntlet/relief_growth/e1_01_promoted_frontage_suburbs/`.
**Accepted as an architectural seam:** settlement-edge continuity 4/5, distinct sparse-industrial suburban
morphology 4/5, authoritative-road connection/access evidence 4/5, cross-tile continuity 4/5,
relief/water safety 5/5, industrial/rural hierarchy 4/5, multiscale readability 4/5,
absence of repeated ring/cul-de-sac glyphs 4/5.

### Final A–E verification

- Full deterministic suite: **2,225 passed, 0 failed**. The initial sandboxed process exited during Godot log
  rotation before test discovery; the standard permitted rerun completed. Established fixture warnings and
  shutdown RID/resource diagnostics remain, but there are no test or script failures.
- Two independent morphology-harness runs are byte-identical for every fixed output. SHA-256 hashes are Arin
  Old `94c364135e86d0bed149fe7e32df3a8593fdf4e505a5c64aeb75c2ed2dd2e054`, Capital
  `272236e1c185e232f399e3c980b358b8778b9130e7b21dfc160ac6e8c6f7954a`, industrial fringe
  `628007adafcd0cd1ebc1be10e245644956044779378e4d23656c2663b11c20c0`, Silkstown
  `3c5215ecdb424e72f029a1d20f1923283a0760c3c241909897d6400a68c4cf6c`, rural trunk
  `3b61b12f4fa3a1e98422dac7082774dd07d15fd66b46b3374e035e91d171741a`, suburban transition
  `f91c29390bd7eaea7b902fc11cad6bea8267c53eb1cc404f2b337b55ee73205b`, ordinary town
  `3c2b3fce6beb825fa7eadeffc7426a4af2c86c526850f4a2fa3fe6d8bf7a0d8d`, village
  `b3f5d3b1ef4181ad720b84b68522d4137b0352b64266d8b2bc884f955c6eed6e`, and wide
  `7946ad81504ac831b90c3e7b3c52faa2ce33608709ac286839110d1546c3bdf7`. Metrics JSON is also identical at
  `29d17c1ae5d4df0afa621c643719e9bac29b4407a4c98bc32279450bf865d660`.
- The all-style map harness passes. Frozen wide hashes remain classic
  `c263cf6595b45e480d037c94c91c8c1b8f14f1b2423fd4521b7740b45ca9045a`, ink
  `95ba0e42c96d24f4ad8117bece6fa0aa5b1ba1b2a4f3601beca5244bcb775`, and plate
  `3a98e9399c83d36ea10c370769a334bcbd0c13704c9a3d94410f72877a94ddf6`.
- Ink before and after legacy → mid-century → legacy is full-PNG identical at the frozen ink hash; the
  masked map-region assertion passes. The all-style mid-century wide/repeat pair is full-PNG identical at
  `c10e179d53fe6862af51141b251fb693a93308dc6955feb2ceb4edf7b465074c`.
- A1.01 covers 205 compounds. All aprons are present and contain their own gameplay building; containment,
  unrelated-gameplay, road, water, relief, and support/building overlap totals are zero. Maximum principal-axis
  difference is 0.00631 degrees.
- B1.01 fixed probes retain zero contour-crossing masses, shoulder-covering fills, disconnected post-relief
  masses, and multi-band decorative buildings. Capital has seven usable/one occupied higher plateaus and 26
  separately reported pre-existing gameplay conflicts; Silkstown has 11 usable/zero occupied and three
  pre-existing conflicts. The three required relief captures were inspected at original resolution.
- C1.01's real-renderer hypothetical harness passes all three yield cases; accommodation signature is
  style-independent and match state is unchanged.
- Roof vocabulary remains within the accepted contextual bands: 510 plain (66.7%), 151 pitched (19.7%),
  62 raised (8.1%), and 42 utility/sawtooth (5.5%).
- Capital and Silkstown each retain zero for all seven W1.01 checks: ordinary-mass water overlap, industrial
  support water overlap, cross-bank masses, disconnected post-water masses, roof-element water overlap,
  shadow water overlap, and uncovered river joins. Rural and suburban water-overlap counts are also zero.
- Road-frontage audit is frozen: 177 road tiles, 413 buildings, 79 failing tiles, 177 over 15u, 137
  off-road-by-design, one service-lane save, and the same 146.6u `tile_10_3` furnace worst case.
- `git diff --check` passes.

**Highest gate passed: E1.01.** A through E are accepted, while S2.05, C1.01, W1.01, P1.01, and H2.11 remain
the locked compatibility and hero references. Gameplay placement, logical footprints, occupancy, selection and
click testing, building counts/capacity, economy, ownership, authoritative road and river topology, transport
connectivity, tile classifications, and save schema are confirmed untouched.

The largest visible differences from the supplied references remain: the pilot suburb reads as a sparse works
ribbon rather than a mature mixed detached-house district; non-hero regional ordinary-building grain remains
coarser and less historically accumulated than the reference plans; and real industrial landmarks use quieter,
less varied accent colour than the oxide/salmon/mustard vocabulary in the references. Those are future visual
layers, not failures of the accepted deterministic seams.

## F1. Relief-retention and decorative-water correction — 2026-08-12

### Investigation result

The apparent one-step-forward/one-step-back behaviour was a real accepted regression. B1.01 proved that the
few surviving polygons did not cross contour shoulders, but it had no minimum-retention gate. The authored
SettlementPlan path sequentially subtracted every relief shoulder from every parcel and discarded remnants
below 720 square units. Capital retained only 16.6% of its parcel area and 18.2% of its parcels; Silkstown
retained none. The generic path had the same failure mode at a 1,500-square-unit face threshold, followed by a
second component-global rule that demoted small built parcels above the lowest relief band. Internal-edge band
coverage remained high, so the old harness accepted visually empty cities.

The water problem was separate. W1.01 audited ordinary masses, industrial supports, roof elements and shadows
inside the two authored plans, but did not universally audit parcel, park, yard, rural-garden, accommodation or
generic-component fills. Candidate land validation also sampled only polygon corners and centre, allowing a
wide polygon to bridge a curved coast while every probe remained dry.

### F1.01 — retention fallback and final land ownership guard

Relief clipping now records retained parcel/face area and count. If it would retain less than 72% of area or
60% of parcel/face count, that settlement restores its already water-safe pre-relief zoning and defers the
shoulders. The component-global higher-band capacity deletion is no longer applied; a future relief pass must
make that choice per source tile. This is a fail-safe, not the final local contour-massing solution.

All decorative building and shadow candidates now sample complete edges and internal NavGrid cell centres.
Accommodation sites use the same stronger test. Before mesh construction, every parcel, yard, park, block,
shadow and roof polygon passes one final dry-land ownership guard. In the first corrected run the new checks
rejected 169 building candidates and 52 shadows at generation time, then removed 242 parcel fills, 16 park
fills and one yard fill that still touched water. No building, shadow, park, parcel, yard or roof polygon that
touches a water-class cell reaches a rendered mesh.

The morphology harness now fails if Capital falls below 30% built coverage, Silkstown below 25%, pre-rural
urban massing falls below 1,000 blocks, more than one settlement has zero decorative built area, or any
decorative fill survives the final land guard.

### Corrected result and verification

- Capital recovered from 6.7% built coverage / 52 masses to **43.0% / 283 masses**.
- Silkstown recovered from 0% / 0 masses to **41.7% / 87 masses**.
- Pre-rural urban output recovered from 551 to **1,323 blocks**; the completed layer contains 1,800 blocks.
- Only one small settlement reports zero decorative built area, matching the pre-B baseline rather than the
  widespread B1.01 loss.
- Full deterministic suite: **2,225 passed, 0 failed**.
- The morphology harness and all new density/water hard gates pass.
- The relief-specific steep, occupied-higher and empty-higher captures still pass their existing zero-overlap
  gates after the fallback.
- `git diff --check` passes. Established shutdown RID/resource diagnostics remain.

Evidence is in `reports/map_visual_gauntlet/relief_growth/f1_01_retention_water_guard/`. Industrial-building
placement transparency was deliberately left untouched for a separate investigation.

## G1. Settlement-wide organic district field — 2026-08-12

### G1.01 — accepted road-directed district field

The generic city and town path no longer scales, merges or sparsely deletes tile-hex envelopes. Each usable
urban tile contributes an irregular local core whose centre and principal axis come from its real-road context.
Those cores form one settlement field through overlapping organic cells and directional pulls at authoritative
road crossings. A crossing can also pull the field into an eligible rural neighbour, but there are no full-hex
fills, shared-edge connector strips, density thresholds or road-buffer ribbons. Roads remain exclusions and
growth evidence; their topology and ownership are unchanged.

Subdivision and parcel role assignment now consume a continuous growth-intensity field. Road-rich and
core-near sectors generate smaller, more tightly packed ordinary masses. Intensity decays away from the core
and road structure into parks, yards, vacant parcels and retained terrain. A final deterministic core check
adds a small dry, road-safe mass only when exclusions have removed every earlier core candidate. This fallback
changed three physically constrained tiles during development and leaves gameplay occupancy untouched.

Per-tile diagnostics record usable area, core position, core mass count, total mass count, built coverage,
near-road and far-road coverage, near-road built share, mean built-road distance, spill destinations and the
fraction of exterior settlement boundary coincident with a source hex. The capture harness fails on any usable
generic urban tile without a core, on a road-bearing tile whose road-rich sector does not dominate its mass
distribution, or when 30% or more of an exterior boundary substantially reproduces hex edges.

The accepted fixed run covers **74 usable generic urban tiles in 37 connected components** and produces 1,665
decorative blocks. Core, density-direction and hex-boundary failure totals are all **zero**. The weakest
road-bearing near-road mass share is **63.03%**, the median is **100%**, and the maximum detected hex-edge
boundary fraction is **1.22%**. Forty-nine tiles have explicit directional rural spill destinations. Example
diagnostics include Fort Silversworth at 25.68% built / 13 core masses, Vandel at 35.51% / 11, Farpoint at
10.15% / five, and river-edge Stoneshore at 19.80% / 14.

Focused mechanism history:

1. The first field candidate was rejected: two usable tiles had no visible core and the raw near/far coverage
   ratio incorrectly failed 21 tiles when a tiny far-road remnant happened to be densely occupied.
2. Replacing that area-sensitive ratio with near-road share exposed two real direction failures. A roadless
   island was correctly made non-applicable, while Stoneshore's 63.03% near-road majority became the fixed
   lower bound rather than being hidden by its small far-road denominator.
3. Tightening the core definition back to an actual core-zone mass exposed three exclusion-constrained tiles.
   The accepted final dry/road-safe core repair resolves them without reverting to anchor cards or changing
   settlement boundaries.

The accepted town, river, fringe, village, suburban transition, Capital, Arin Old and wide captures were
inspected at original resolution. Fort reads as a connected road-led town with purposeful open terrain;
Vandel retains works yards and landmark industries; Farpoint resolves into a few coherent groups rather than
a diluted city; and the wide image shows settlement anchors without hex-shaped urban plates. Arin Old remains
the locked authored regression slice. The principal remaining visual weakness is coarse ordinary mass grain
in a few non-hero towns, suitable for a later isolated subdivision pass.

Two complete morphology runs are byte-identical for the metrics JSON and every fixed PNG. Accepted evidence is
in `reports/map_visual_gauntlet/district_field/f1_01_organic_district_field/`.

### G1.01 final verification

- Full deterministic suite: **2,225 passed, 0 failed**. The first sandboxed process hit the established Godot
  log-rotation crash before test discovery; the permitted standard run completed. Only established shutdown
  RID/resource diagnostics remain.
- Repeated morphology metrics and every fixed capture are byte-identical. The accepted metrics SHA-256 is
  `72a07e5fa1f959353a2b7b071870aabd25a86c8510fe8ff6f1f6c9efa79f17fa`.
- The all-style map harness passes. Mid-century wide/repeat are full-PNG identical at
  `bb28fc074db2c5ebd6662d773b0481e101288b4f8188dff65c3fbbd02ffdeb9f`.
- Frozen legacy wide hashes remain classic
  `c263cf6595b45e480d037c94c91c8c1b8f14f1b2423fd4521b7740b45ca9045a`, ink
  `95ba0e42c96d24f4ad2ab8117bece6fa0aa5b1ba1b2a4f3601beca5244bcb775`, and plate
  `3a98e9399c83d36ea10c370769a334bcbd0c13704c9a3d94410f72877a94ddf6`.
- Ink before and after legacy → mid-century → legacy is full-PNG identical at the frozen ink hash; the
  harness's masked map-region assertion also passes.
- Road-frontage audit is frozen: 177 road tiles, 413 buildings, 79 failing tiles, 177 over 15u, 137
  off-road-by-design, one service-lane save, and the same 146.6u `tile_10_3` furnace worst case.
- `git diff --check` passes. No gameplay road, river, occupancy, footprint, building-count, economy, capacity,
  selection, click-testing or save-data code was changed by G1.01.

### G1.02 — universal oracle and accepted dense-core checkpoint (density/boundary gates remain open)

G1.01 remains accepted as the settlement-shape mechanism, but its density claims are formally reopened. The
old audit covered only 74 generic tiles, treated one mass as a visible core, measured tessellated road segments,
recorded requested spill rather than surviving geometry, and diluted hex coincidence across a component. G1.02
replaces that evidence with an all-92-tile oracle. This is a checkpoint, not a completed G1.02 gate.

The oracle assigns field, parcel and decorative-building area to every source and destination tile by polygon
intersection rather than centroid. Per tile it records nickname/profile, dry usable land, ranked core candidates,
usable core-zone area, core area/coverage/mass count, total mass area/count, unique authoritative road edges,
road length, junction count/degree, unsaturated influence, normalized rich/intermediate/poor sector coverage,
actual field/parcel/building spill by neighbour, internal-edge crossings, local exterior boundary and hex
coincidence, and water/relief/forest/gameplay/industrial constraints. The harness also writes a deterministic
manifest and dynamically captures the six weakest cores, three worst gradients, three worst internal seams,
and three worst local exterior boundaries.

The accepted Phase 1 mechanism constructs cores from actual road-caused faces. It ranks multiple road/junction
positions, intersects the best surviving face with the dry/available audit union, subdivides it at a 2–3 unit
inset, and creates a compact connected group with the same perimeter-mass vocabulary as the district field.
It is not a marker-building fallback or a return to road-anchor cards. All **92/92 usable urban tiles** now have
a genuine multi-building core: missing-visible-core and dense-core failure counts are both **zero**. Every
applicable village/fringe core has at least four masses and 18% core-zone coverage; every applicable
town/metropolitan core has at least six masses and 25%; constrained small zones require at least three.

The universal spill and seam diagnostics also establish that geometry survives rather than being merely
requested: 55 destination tiles receive actual field/parcel spill, 36 receive decorative-building spill,
actual rural building spill is 250,734.03 square units and hill spill is 20,145.34. Invalid building spill area
is zero, invalid destination count is zero, water overlap remains zero, and all usable internal urban edges have
an organic occupied crossing or a reported physical constraint (**zero internal-seam failures**).

#### Explicitly unaccepted gates

The continuous road-density gate is not solved. Of 87 applicable tiles, seven fail the required +5 percentage
point rich-minus-poor margin: Arin Old (`-25.38`), Arin Industrial (`-5.47`), Arin City (`+2.25`), Teganfort
Industrial (`+4.80`), Capital Market Row (`+4.93`), Arin Highgate (`-2.22`) and Arin Millgate (`-3.93`). Direct
inspection agrees with the metric: the worst Arin captures contain large complete masses in road-poor samples
while some junction-rich fragments are parks, reserved gameplay compounds or cream courts. This is not hidden
by near-road mass share or unequal sector area.

The corrected local-boundary oracle measures only a source tile's exterior sides, including settlement geometry
that spills outside the source hex, and applies the requested 20% threshold. It exposes 13 failures rather than
the previous component-diluted pass: seven Arin tiles, Patran Old, three Capital tiles and both Silkstown tiles.
The three worst are Silkstown Docks (81.92%), Arin Highgate (80.01%) and Capital Foundry (78.43%). Their dynamic
captures visibly contain long straight, tile-aligned termination, so this is a real visual defect rather than an
audit-only regression.

Three distinct attempts to make the H2.11 hero obey the normalized gradient were rejected and removed. A
universal low-influence occupation post-pass reduced the counter from seven to one but broke Arin's connected
street walls into paper voids and isolated cards. Two count-preserving contextual role/ordering variants reduced
the counter to four/three but lowered hero built coverage to roughly 34%/33% and made the locked core visibly
sparser. Two depth-weight variants were neutral or worse while lowering hero coverage to roughly 36%. A Tegan
annex, a second reconciliation pass and contiguous annex experiments were neutral or moved the failure into a
neighbour. The renderer source and H2.11 image were restored after every rejection. These experiments show that
post-generation deletion/reordering is the wrong abstraction; a future Phase 2 must make road influence part of
face subdivision and mass construction while preserving connected perimeter fabric.

#### Fixed and dynamic visual review

The weakest-core captures now read as inhabited neighbourhood fragments: multiple connected street-wall masses,
enclosed greens/courts, real cream road corridors and gameplay industries held clear. The wide image retains
distinct settlement anchors, continuous geography and rural negative space. H2.11 remains metrically exact at
151 parcels, 25 street faces, 38.2881% built, 17.5218% green and 44.1901% negative, with 44 solid, 27 U, 21 L
and 26 courtyard-ring masses. Its current locked G1.02 PNG hash is
`1c34666781afd4c6a75afd9c6304eed5786b176f7c731aae90b1295900ad81d5`.

The strongest accepted evidence is preserved in
`reports/map_visual_gauntlet/district_field/g1_02_phase1_exact_realization_working_best/`; the complete final
diagnostic set and manifest are in
`reports/map_visual_gauntlet/district_field/g1_02_final_diagnostic_run1/`. Important fixed hashes are Capital
`57131b37d3ff39ab17d455066c039ba1b7db1a32653e288fc6d18e5a4ad9be81`, Silkstown/river
`8ddb642ba128d10981a8aecfc02f719c4e97b354067edf33421b6f327cbc2d73`, industrial fringe
`08f94b5acc65c3e41db24ccd21a348faa855dcbd14aa35a1c9a1e344daeb1fb3`, town
`4f288c03f803bd9365336bfeed21b899886d7c66056a675981333774ac6f8ffd`, village
`cc813a10e2d5a6e3f6ae513352c6b681b47c157e825ebfe4fa01f2004a9bd17f`, and wide
`08a691ab141ed23bd6bbada24b8b32cc54ceaeee634c65b9c29ccfd44c0665b9`.

#### G1.02 checkpoint verification

- Full deterministic suite: **2,249 passed, 0 failed**. Established Godot shutdown RID/resource warnings
  remain; the test result is green, but the console is therefore not described as clean.
- Two complete morphology runs are byte-identical across all 24 required fixed/dynamic PNG and JSON artifacts.
  The metrics hash is `098bfe1003ba9ed83c58f6f0d0b880257875b73151255e514ff5a9c93f1f262f`.
  Both runs correctly exit non-zero on the unresolved normalized road-gradient gate.
- The all-style harness completes. Frozen wide hashes remain classic
  `c263cf6595b45e480d037c94c91c8c1b8f14f1b2423fd4521b7740b45ca9045a`, ink
  `95ba0e42c96d24f4ad2ab8117bece6fa0aa5b1ba1b2a4f3601beca5244bcb775`, and plate
  `3a98e9399c83d36ea10c370769a334bcbd0c13704c9a3d94410f72877a94ddf6`. The repeated mid-century wide
  pair is full-PNG identical at `9b4f9de1ca6cf2694364e7e12a3b347d30a2fd2d630c85073f32846d0cf66379`,
  and ink before/after legacy → mid-century → legacy is full-PNG identical at the frozen ink hash in addition
  to the masked map-layer assertion. Established harness shutdown leak diagnostics remain.
- Road-frontage audit is frozen: 177 road tiles, 413 buildings, 79 failing tiles, 177 over 15u, 137
  off-road-by-design, one service-lane save, and the same 146.6u `tile_10_3` furnace worst case.
- `git diff --check` passes.

**Checkpoint status:** Phase 0's universal oracle and Phase 1's real dense cores are accepted. Phase 2
road-directed normalized density and Phase 3 local organic exterior boundaries are still open; therefore G1.02
as a whole does not pass. No road/river topology, transport ownership/connectivity, occupancy, logical or visual
gameplay footprint, click testing, selection, building count/capacity, economy, tile classification or save data
was changed. The next valid mechanism should operate on settlement-wide face geometry before parcel roles are
fixed, jointly producing fine road-rich grain and tapered non-hex exterior lobes without deleting H2.11's
connected perimeter masses.

## K1. Bounded implementation and visual gauntlet — 2026-08-13

### Scope and baseline

Work continued on `codex/midcentury-bounded-gauntlet` from the current dirty workspace without staging,
committing, resetting, cleaning or absorbing the owner's unrelated changes. G1.02/H2.11 was the visual and
metric baseline. The G1.02 Pepper capture is preserved beside the final evidence as
`bounded/k1_01_final_candidate/baseline_pepper_g1_02.png`; it visibly contained only a few road-junction slabs
and isolated lot marks. Arin, Capital and Stoneshore interiors were not globally rerolled. Road-junction polish
was not reopened.

This was a bounded partial pass, not a successful whole-map gate. The final independent critic scored the
candidate **3.67/5** and rejected final acceptance because reference resemblance, continuous figure/ground,
historically accumulated character and absence of procedural repetition remained at 3/5. The three largest
reference differences were: the references' finer and darker continuous urban carpet; the candidate's repeated
terrace pairs/open-lot marks/stair-step masses; and the port's bilateral engineering-symbol regularity.

### A. Authoritative gameplay-footprint invalidation — accepted

`BuildingVisuals` now emits a coalesced `footprints_changed(version, affected_tile_ids)` signal only after the
placement cache has mutated. Placement, removal, clear, tile relayout and bulk relayout all record affected
tiles. `UrbanFabricVisuals` listens to that post-mutation seam, defers its rebuild, queries the global set of
exact oriented gameplay footprint polygons (including rural spill destinations), and finishes every geometry
pass with an expanded-footprint sanitizer. A colliding decorative mass is removed whole from block, roof,
outline-equivalent mesh and shadow batches rather than being clipped into a fragment; parks/yards/lots also
yield. Port envelopes use the shared compound plan when it is valid.

The final live-placement run advanced footprint versions 413 → 414 → 415. After two rendered frames:

- dense Arin placement: **0 opaque overlaps**;
- rural-spill placement: **0 opaque overlaps**;
- the fabric metric carried the current post-mutation version for both checks.

The source-level cause was late invalidation plus source-tile-only footprint discovery. The new contract is
draw-only: occupancy, placement legality, click testing and logical building footprints are unchanged.

### B. Unified authoritative Port — rejected after two attempts

One `MidcenturyPortPlan` now supplies separate land, deck, basin, container, crane, apron, solid exclusion,
marine reservation, total-envelope and road-access geometries to both `PortVisuals` and footprint exclusion.
The old independent mid-century shoreline glyph is not drawn, and a valid plan suppresses the generic `b_004`
art, so a valid port has one representation. A rejected plan falls back to the one authoritative gameplay
footprint rather than disappearing or reviving a second glyph. Legacy rendering is unchanged.

Attempt 1 used the best contiguous-water neighbour but one fixed shore offset; it rejected at least one port.
Attempt 2 searched land/sea offsets while requiring at least 98% basin water and 80% landward-base land; it
still produces only **3 of 4** catalog ports. Stoneshore `tile_5_10` cannot fit this symmetric U primitive while
meeting both proof thresholds. The mechanism therefore stops here.

Every accepted local plan has exactly two cranes on different arms, a two-point authoritative-road access,
29–33 container stacks, **100% sampled basin water** and **0 opaque basin overlap**. Nevertheless, the global
port hard gate fails at 3/4, and the critic also rejected the shown plan's identical long piers and rectangular
headhouse as too schematic. No land-colored basin fallback was added.

### C–D. Explicit profiles, whole-body gates and compact-town micro-massing — partially accepted

`data/visual_settlement_profiles.json` explicitly assigns all 92 urban tiles; nickname/component-size inference
is now only a missing-record fallback. The final effective profile counts are 16 metropolitan, 24 town, 2
small-town, 32 industrial-fringe and 18 village. Pepper Valley `tile_5_4` and Klade Estuary `tile_2_4` are
explicit `small_town` settlements; their docks remain explicit industrial fringes.

The renderer now records mass count, p25/median/p75/p90 mass area, largest-one/three shares, repeated-size and
repeated-shape dominance, road-frontage occupancy and occupied body share outside the core. It evaluates these
alongside usable-body built coverage. This audit exposes **20 settlement components** still failing at least one
new whole-body gate, so no map-wide density claim is made.

Two mechanisms were tried:

1. **Rejected:** smaller subdivision targets plus a density floor for `small_town`. Pepper and Klade passed
   numeric averages but still read as sparse, oversized road fragments. Pepper had 35 masses with 961.9 median
   area; Klade had 17 with 1,447.8 median area.
2. **Accepted for compact cores:** a deterministic post-parcel stage replaces selected small-town built parcels
   with one or two coherent frontage rows of 2–6 child masses, preserving 1.5–3u subordinate alley gaps and rare
   pocket greens. It applies only to `small_town`, not Arin, Stoneshore or Capital.

Final compact-core evidence:

| Slice | Masses | Built | Median area | Largest three | Frontage | Outside core | Decision |
|---|---:|---:|---:|---:|---:|---:|---|
| Pepper core | 63 | 20.13% | 355.4 | 7.57% | 100% | 34.39% | accepted |
| Klade core | 32 | 18.19% | 385.6 | 11.90% | 93.31% | 9.05% | visually accepted; body gate misses by 0.95pt |
| Pepper Docks fringe | 6 | 10.83% measured mass coverage | 1,788.9 | 60.43% | 100% | 33.35% | rejected |
| Klade Docks fringe | 11 | 12.88% measured mass coverage | 1,123.3 | 41.30% | 89.30% | 49.37% | accepted |

The core improvement is real, but repeated-shape dominance remains 52.38% at Pepper and 59.38% at Klade
because the new vocabulary is intentionally mostly quiet quadrilateral terraces. The critic accepted both
cores and Klade Docks but rejected Pepper Docks' six oversized masses and repeated staircase river frontage.
That outlier becomes its own later industrial-fringe pass rather than triggering a third town mechanism.

### E–F. Continuity, rural growth, relief and development space — preserved, not declared complete

The accepted regional-field mechanism remains intact: 92/92 usable urban tiles have a genuine dense core,
missing/dense-core failures are zero, internal-seam failures are zero, 55 tiles receive actual spill and no
invalid water destination is introduced. The open G1.02 failures remain **7 road-gradient failures** and **13
local hex-boundary failures**. Arin boundary surgery was deliberately not mixed into this pass.

Rural growth remains route-dependent and visually rural: 184 masses, 83.15% within one frontage depth, 10 at
junctions, 31 in back rows and 28 roadless skips. Water, relief, forest, gameplay and road overlap counters are
all zero. The existing selective suburb remains one cross-tile district with 11 masses and two connected 3u
access streets; its recorded road, water, relief and gameplay failure counters are zero. High-relief and rural
captures were accepted by the critic. Existing redevelopment/accommodation planning remains in place; this pass
does not claim that its map-wide 5–10-site target is newly solved.

### G. Far-zoom settlement silhouettes — accepted bounded attempt

Below zoom 0.28, the detailed urban fabric switches to one batched, quiet grey plate built only from the final
sanitized decorative masses. It uses no tile envelopes, adds no nodes, and cannot introduce new water,
footprint or hex-boundary geometry. The final plate contains 2,043 source masses / 2,288,794 square world units.
The critic accepted the full-map hierarchy: geography and transport remain dominant while major settlement
clusters remain locatable. Some ordinary towns remain low-contrast anchors, but wide readability is 4/5.

### Road-layout fixture

A focused pure-geometry fixture replaces a horizontal authoritative road with a vertical one without changing
terrain or tile metadata. It proves that identical roads reproduce the exact core polygon, the old road produces
horizontal growth, the replacement produces vertical growth, and the core moves more than 40u away from the
removed road. All four assertions pass. The production renderer continues to invalidate on
`RoadWorks.order_settled`; no named-city road coordinates were introduced.

### Independent critic score

| Category | Score |
|---|---:|
| inhabited impression | 4 |
| reference-family resemblance | 3 |
| continuous figure/ground | 3 |
| organic parcel structure | 4 |
| streets as negative space | 4 |
| green-space integration | 4 |
| decorative/gameplay hierarchy | 4 |
| industrial color discipline | 4 |
| top-down discipline | 4 |
| historically accumulated character | 3 |
| multiscale readability | 4 |
| absence of procedural repetition | 3 |

Average: **3.67/5**. Preservation review accepted Arin North and Capital, accepted Stoneshore with a figure/ground
caveat around its central open field, and found no global interior damage. Rural/relief, both player-placement
views and far zoom were accepted. The overall candidate is rejected as final gate-complete.

### Final deterministic and compatibility evidence

- Full deterministic suite exited 0 with all tests passing; the four new road-layout assertions are visible as
  passes in that run.
- Repeated mid-century wide PNGs are full-file identical at
  `1926c97e6384546dc2cf6a0b5d77620ac83bfd293af3202138c6c10a829af9e5`.
- Ink before and after legacy → mid-century → legacy is full-file identical at the frozen hash
  `95ba0e42c96d24f4ad2ab8117bece6fa0aa5b1ba1b2a4f3601beca5244bcb775`; the masked map-layer assertion also
  passes and the selected ink state is restored.
- Road-frontage audit is unchanged: 177 road tiles, 413 gameplay buildings, 79 failing tiles, 177 over 15u,
  137 off-road-by-design, one service-lane save and the same 146.6u `tile_10_3` furnace worst case.
- `git diff --check` passes.
- Established Godot shutdown RID/texture/resource diagnostics remain; therefore the capture console is not
  described as clean.

Final evidence is preserved in `reports/map_visual_gauntlet/bounded/k1_01_final_candidate/`, including fixed
Pepper/Klade, Arin North, Capital, Stoneshore, rural, relief, port, dense-player, spill-player and wide PNGs plus
both metrics JSON files.

### Gameplay and remaining hard failures

No economic rule, production/capacity value, transport connection or ownership, road/river topology, relief
data, tile type, forest occupancy, logical or visual gameplay footprint, occupancy rule, click/selection path or
save schema was changed. All new settlement and port data is draw-only; the only new signal reports an already
mutated visual placement cache.

Hard failures remaining:

1. Pepper Docks: six ordinary masses and 60.43% largest-three dominance.
2. Port: only 3/4 valid plans; the accepted local primitive is also too symmetric.
3. Twenty components fail one or more whole-body gates.
4. Seven normalized road-gradient and 13 local exterior-hex gates remain open from G1.02.
5. Reference resemblance, continuous figure/ground, accumulated character and procedural repetition remain
   below 4/5.

**K1 status:** retain the footprint invalidation seam, explicit profiles, compact Pepper/Klade core mechanism,
road-layout fixture, rural/relief behavior and far-zoom plate. Do not call the whole gauntlet passed. Treat Pepper
Docks, the Stoneshore port siting vocabulary, and the pre-existing density/boundary failures as independent
future passes.

## L1. Port-only coastline-adaptive harbour gauntlet — 2026-08-13

### Scope, cause and bounded loop

This pass stayed on `codex/midcentury-bounded-gauntlet` in the owner's dirty workspace without staging,
committing, resetting, cleaning or absorbing unrelated changes. It changed only the optional mid-century port
plan, rendering/exclusion seam and focused evidence tooling. Settlement density, Arin boundaries, relief,
roads, rivers, rural morphology and the legacy renderers were not reopened.

K1's source-level failure was the fixed rectangle-and-shore-normal abstraction: one partly wet rectangular
head, one rectangular basin and identical parallel arms could not adapt to Stoneshore and made the other three
sites look like the same engineering symbol. L1 replaces it with one deterministic, bounded search over real
local `NavGrid` sea/land coastline samples. The planner evaluates 432 combinations per port (18 coastline
samples, two shore shifts, two angles, three site sizes and two setbacks), fits the dry head independently,
validates a trapezoidal sea basin plus an open-sea run, fits unequal bent arms, subtracts exact river and
gameplay exclusions, and connects the entrance to a real built road.

The first adaptive field candidate was **rejected visually** despite reaching 4/4: its narrow head still read as
a crossbar, the arms remained sparse, and the tiny cargo/crane marks did not establish a working port. The one
permitted materially different refinement was **accepted**: broader trapezoidal heads, independent arm
length/bend/width, one or two offset warehouses, varied cargo groups with working gaps, and larger oriented
gantry/jib cranes. No third mechanism was attempted.

`MidcenturyPortPlan` is now the single plan consumed by `PortVisuals`, generic `b_004` art suppression,
decorative-fabric exclusion, offshore marine reservation, road access, metrics and focused tests. It exposes
land, warehouse, apron, left/right arm, deck, basin, mouth, open-water corridor, containers, cranes, solid
exclusion, marine reservation, compound envelope, access and geographic diagnostics. All four catalog ports
use this plan, so Stoneshore no longer falls back to generic art and each port has one visible mid-century
representation.

### Fixed captures and direct visual review

All normal captures were inspected at original 960 × 540 resolution; the context capture was inspected at
1100 × 650. Diagnostic overlays show sampled coast points in yellow, dry head in yellow, independent arms in
red/purple, basin/corridor in blue/cyan, authoritative river exclusions in red and the road access in
white/purple. They are disabled by default and reachable only through the capture-tool seam.

| Port | Normal | Diagnostic |
|---|---|---|
| Stoneshore Docks | [normal](map_visual_gauntlet/ports/l1_01_coast_adaptive_accepted/poe_port_stoneshore.png) | [overlay](map_visual_gauntlet/ports/l1_01_coast_adaptive_accepted/poe_port_stoneshore_diagnostic.png) |
| Arin Estuary Docks | [normal](map_visual_gauntlet/ports/l1_01_coast_adaptive_accepted/poe_port_arin.png) | [overlay](map_visual_gauntlet/ports/l1_01_coast_adaptive_accepted/poe_port_arin_diagnostic.png) |
| Capital Port | [normal](map_visual_gauntlet/ports/l1_01_coast_adaptive_accepted/poe_port_capital.png) | [overlay](map_visual_gauntlet/ports/l1_01_coast_adaptive_accepted/poe_port_capital_diagnostic.png) |
| Vandel's Skip | [normal](map_visual_gauntlet/ports/l1_01_coast_adaptive_accepted/poe_port_vandel.png) | [overlay](map_visual_gauntlet/ports/l1_01_coast_adaptive_accepted/poe_port_vandel_diagnostic.png) |

The wider [Arin context capture](map_visual_gauntlet/ports/l1_01_coast_adaptive_accepted/poe_port_context.png)
shows that the port remains a landmark within its surrounding figure/ground rather than overwhelming it. The
rejected K1 comparison is preserved as
[the baseline port](map_visual_gauntlet/ports/l1_01_coast_adaptive_accepted/k1_baseline_port.png). The accepted
metrics JSON is [preserved with the images](map_visual_gauntlet/ports/l1_01_coast_adaptive_accepted/poe_port_metrics.json).

The visible improvements are site-specific: Stoneshore turns around its irregular inlet, Arin flanks the
estuary rather than bridging it, Capital opens directly toward its exposed coast, and Vandel fits the shallower
works shoreline. Every basin is actual underlying sea, not a painted water patch. The remaining visual weakness
is the deliberately simple head/apron vocabulary: at close zoom it is still more diagrammatic than the richer
urban fabric. Arin's right arm also has a long land-rooted fraction (29.53% sampled sea-deck coverage); this is
legal and leaves the basin open, but it is the least convincing quay-to-water transition of the four.

### Complete four-port audit

`D.ovlp` is decorative/park overlap, which is zero for every plan under the shared sanitizer. `G.ovlp` is
gameplay overlap. All areas and lengths are world units; coverage values are percentages.

| Port / tile | Valid | Basin area / sea | Open corridor | Mouth | Dry head | L/R arm length | L/R sea-deck | River / opaque basin | Cargo / cranes | Road | G.ovlp / D.ovlp | Plan SHA-256 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Stoneshore `tile_5_10` | yes | 10,602.06 / 100% | yes / 100% | 112.00 | 100% | 120.81 / 128.63 | 87.00% / 89.48% | 0 / 0 | 15 / 2 (L+R) | 135.99, valid | 0 / 0 | `3679035cb5fce345ea464254f7bc0215bba45326dd452b63c4886c3dbdb3114d` |
| Arin `tile_11_17` | yes | 7,839.99 / 100% | yes / 100% | 96.00 | 100% | 121.21 / 102.40 | 100% / 29.53% | 0 / 0 | 14 / 2 (L+R) | 28.42, valid | 0 / 0 | `15f74d8b7e945e57dac88cd152cb80bb4e27c72b16ea7fccd6c4fa847fece831` |
| Capital `tile_24_7` | yes | 7,840.01 / 100% | yes / 100% | 96.00 | 100% | 118.29 / 108.67 | 71.03% / 77.58% | 0 / 0 | 16 / 2 (L+R) | 107.07, valid | 0 / 0 | `47c0d8dfebe864ec2fe8e946b64075bc68b53e6016d17cacbd2486c64b2616ee` |
| Vandel `tile_22_16` | yes | 5,494.02 / 100% | yes / 100% | 80.00 | 100% | 93.08 / 75.36 | 90.80% / 74.12% | 0 / 0 | 11 / 2 (L+R) | 6.41, valid | 0 / 0 | `aa0b424d55e38ae92b852295ddc466aea3c4fd11ce25cac92261bbaa2546daaf` |

Audit result: **4/4 valid**, 100% sea basin and open-water-corridor coverage, 100% dry landward heads,
zero river/channel obstruction, zero opaque basin occupation, zero gameplay overlap, zero decorative/park
overlap, valid real-road access at every site, and exactly two cranes per port with one assigned to each arm.
The collision probe also confirms eight marine reservations (basin plus mouth corridor for four ports), so an
offshore gameplay structure cannot occupy navigable harbour water.

### Critic assessment

The three largest remaining visual differences from a fully authored port reference are: the heads still use a
small family of broad geometric aprons; cargo handling is readable but less dense than a major real port; and
Arin's right quay spends more of its length land-rooted than the other three. None causes fallback art, water
painting, basin blockage, river bridging or loss of the U-shaped silhouette.

| Port-only category | Score | Visible evidence |
|---|---:|---|
| Coastline fit | 4/5 | Four different orientations and head positions follow the sampled local shore rather than a neighbour-tile normal. |
| Recognisable U silhouette | 4/5 | Each dry head terminates in two independent quays around an open underlying-water basin. |
| Basin and mouth clarity | 5/5 | Blue water remains visible between arms and connects through an unobstructed cyan diagnostic corridor. |
| Crane legibility | 4/5 | Two large cross-rail/jib silhouettes remain visible at the fixed regional scale and face their respective arms. |
| Cargo and warehouse variety | 4/5 | Counts vary 11–16; stack length/spacing/colour and warehouse count/offset differ by site. |
| Top-down/cartographic discipline | 5/5 | Dominant roof/deck faces, short southeast shadows and no facade or isometric massing. |
| Settlement integration | 4/5 | Arin context preserves street, water and gameplay-industry hierarchy around the compound. |
| Absence of procedural repetition | 4/5 | Related palette and grammar remain, while arm length, bend, width, head, cargo and roof arrangements vary. |

**L1 port-only decision: accepted.** Every port-specific hard gate is at least 4/5 and every static hard gate
passes. This does not change K1's rejected whole-map score or close any settlement-density/boundary gate.

### Determinism, compatibility and tests

- Two complete normal four-port runs are byte-identical: Stoneshore
  `a2ec20451dfd42be6fbe490a9040784416752aa1e5c22402ffcfc3f22e52d4b6`, Arin
  `a9b80430e50bf2b8a12a42a8f7dd4068e08939226af9c0c326f85b3c984091ee`, Capital
  `4c57c14eec463d130f092a8cf47fcbb6cbf71f4aca7f6d153f7f0b6adfcf6018`, Vandel
  `7e3f601a4b202037bb27ed81aa307e1f6c74b617473c663fb963995be74e3bba`, and context
  `73d143b97829db97467ffca291904bf448516428ccc55c32e558b4617302ee4c`.
- Plan hashes remained identical across the two capture runs, the focused placement/collision probe, the
  all-style round trip and the full test suite. Planner timing is intentionally excluded from deterministic
  comparisons. Corrected diagnostic-overlay hashes are Stoneshore
  `cec702187e1e637cf45c6d87f202c06c3e70b2bfe1a7a2d2cdc9480250a7af48`, Arin
  `435ba89135836b6eb4448a23b4999dfd7f0caa39351e5b944afe673d68a50fe7`, Capital
  `e440e8ee9b4f3c58a176540af9dc2fbeec992f96201acc45fdc634ef6645ff35`, and Vandel
  `2c7f9e0e6700434295ae1f5b96efa5ce82c6aa906a4d5d8040c1d85e3c7e577c`.
- Focused four-port gauntlet: `valid=4/4`, no failures. Focused live-placement probe: footprint version 414,
  four plans, zero opaque decorative overlap, two cranes per plan, sea/open-corridor/river checks passed and
  all eight marine reservations present.
- Full deterministic suite: **2,260 passed, 0 failed**.
- All-style harness: mid-century wide/repeat are full-PNG identical at
  `70c6d3f8c1a09f5a4664c633032f7e628c4c8816f25fdb13f039889bcefffbbf`. Frozen wide hashes remain classic
  `c263cf6595b45e480d037c94c91c8c1b8f14f1b2423fd4521b7740b45ca9045a`, ink
  `95ba0e42c96d24f4ad2ab8117bece6fa0aa5b1ba1b2a4f3601beca5244bcb775`, and plate
  `3a98e9399c83d36ea10c370769a334bcbd0c13704c9a3d94410f72877a94ddf6`.
- Ink before and after legacy → mid-century → legacy is full-PNG identical at the frozen ink hash; the masked
  map-layer assertion also passes.
- `git diff --check` passes. Established Godot shutdown RID/texture/resource warnings remain, so the console is
  not described as clean.

### Files, preservation and player-port eligibility

Port-pass source/tool files are `scripts/midcentury_port_plan.gd`, `scripts/port_visuals.gd`, the narrowly
related query/reservation paths in `scenes/building_visuals.gd`, `tools/midcentury_port_gauntlet.gd/.tscn` and
`tools/midcentury_collision_port_probe.gd/.tscn`, plus this report and the preserved evidence directory.

No port owner, capacity, storage, fee, economy or transport behavior changed. No road, river, coastline, relief
or tile topology changed. Logical gameplay footprints, occupancy, click/selection behavior, building counts,
construction values and save data remain untouched. The only placement consequence is collision safety:
offshore gameplay art cannot be placed in the shared draw-only basin/mouth reservation, and decorative fabric
yields to the shared port envelope.

The requested inland-player-port audit found **no current player-placeable port path**: `MatchState` explicitly
marks `b_004` as existing infrastructure that may be bought but never built, so the construct UI cannot offer an
inland port. The generic `Catalog.is_building_allowed_on_tile_type()` helper has no port-specific coastal rule;
that is a latent requirement only if player-built ports are authorized later. L1 deliberately does not add or
change such a gameplay eligibility rule.

## M1. Per-tile density audit — the measurement instrument — 2026-08-14

### Scope

`docs/map-density-and-port-addendum.md` §6 requires a new deterministic audit that emits, per tile: tile id,
nickname, class, small count, large count, park count, park area, buildable dry area, and pass/fail against the
§2 table, failing the run on any undocumented miss. M1 builds that instrument and measures the current baseline
with it. **No visual mechanism was attempted and no rendered geometry changed** — this pass is measurement only,
so that the four density/park/coastal/port streams are all judged by the same numbers.

### What was built

- `scripts/density_audit.gd` — a `RefCounted` holding the pure, side-effect-free gate logic: class assignment,
  the frozen small/large threshold, what counts as a building and as a green space, and the §2 evaluation.
  Everything a future change is likely to get subtly wrong lives here and is unit-tested without a scene tree.
- `scripts/urban_fabric_visuals.gd` — two read-only seams. Every block and park entry now carries the `kind`
  that produced it (`ordinary`/`core`/`industry_support`; `park`/`green`/`accommodation_park`/`courtyard`), the
  sanitized render arrays are retained, and `density_audit_snapshot()` returns them. `tile_dry_buildable_areas()`
  measures per-tile dry buildable land with the fabric's own exclusion vocabulary. Both are draw-only reads.
- `tools/density_audit.gd` / `.tscn` — the headless audit harness. Writes `/tmp/poe_density_audit.json` and
  `/tmp/poe_density_audit.txt`. Exit 0 = compliant, 2 = ran and the map does not comply, 1 = could not run.
  Runtime is roughly 3.5 minutes headless.
- 27 new asserts in the unit suite pinning classification precedence, the threshold and the §2 rows.

### Decision 1 — the small/large threshold

`DensityAudit.LARGE_MASS_AREA = 1600.0` square units. One absolute value, applied map-wide, frozen.

Derivation: reconstructing the global mass-area histogram from every settlement's 125u size buckets in the
frozen v0 metrics (961 ordinary masses) gives median ~1030, p75 ~1640, p90 ~2500. Measured directly over all
**2,037** rendered masses in this run: p25 = 351, median = 752, p75 = **1532**, p90 = 2417. 1600 is that p75
rounded to a round number, and two independent checks agree with the cut:

- The addendum's own urban row (>= 10 small, >= 3 large) implies a large share of 3/13 = **23%**. At 1600 the
  measured large share is **23.0%** — the cut reproduces the owner's own ratio exactly.
- 1600 sits just above `MORPH_FACE_MIN_AREA` (1500), the smallest area the face subdivider leaves undivided. A
  mass at or above the cut therefore occupies a whole un-subdivided street face and reads as block-scale;
  anything below is a parcel inside a subdivided face.

The constant must NOT be re-derived from a candidate run. A stream that adds hundreds of small masses would
slide a recomputed p75 downwards and silently relabel the same buildings.

### Decision 2 — class assignment

Derived only from authoritative data, never invented and never mutated. Precedence, in order: `sea`/`deep_sea`
are water and are not audited; the 92 tiles in `data/visual_settlement_profiles.json` are **urban** (verified:
the profiled set and the urban-terrain set coincide exactly, zero mismatches either way); terrain class
`mountain` is **mountain**, so the cap wins over the sparse floor even on the 32 mountain tiles that carry a
road; any other land tile with >= 1 BUILT `RoadNetwork` edge is **sparse**; the rest are **remote**.

### Decision 3 — what counts

A building is a decorative mass that SURVIVED both sanitisation guards, of kind `ordinary`, `core` or
`industry_support`, with area >= 120u^2 (21 sub-floor fragments excluded). Gameplay buildings are drawn by
`BuildingVisuals`, are frozen, and are never counted. A green space is a merged connected component of the
rendered park layer of kind `park`, `green` or `accommodation_park`, area >= 200u^2; **inner courtyards are
counted separately and never satisfy the park floor**, or a stream could pass §2 by stamping courtyards.
Polygons are assigned to the tile they share the most area with, not by centroid, per the G1.02 idiom.

### Baseline — the map is 27.8% compliant

| class | tiles | compliant | failing | dominant failures |
|---|---|---|---|---|
| urban | 92 | **19 (20.7%)** | 73 | 57 green below floor, 38 large below floor, 35 small below floor |
| sparse | 204 | **45 (22.1%)** | 159 | 154 small below floor (134 of them at zero), 6 large above cap, 2 small above cap |
| mountain | 45 | **45 (100%)** | 0 | — |
| remote | 54 | **1 (1.9%)** | 53 | 53 small below floor (all at zero) |
| **total** | **395** | **110 (27.8%)** | **285** | all 285 undocumented |

Mountain passes trivially: it is a cap and every mountain tile renders zero decorative masses. The remote class
is the worst in the map — 53 of 54 tiles are empty, because the fabric only grows rural masses on tiles that
carry a BUILT road, and remote is by definition roadless. 73 of 92 urban tiles miss; the largest single defect
is parks (57 tiles under two green spaces, **37 of them with no public green at all**), then large buildings
(38 tiles, **24 with none**), then small buildings (35 tiles). The median urban tile has 11 small, 3 large and
**1** park.

### Every miss is actionable — no tile is physically prevented

`dry_buildable_area` is measured per tile with the fabric's own exclusions. **Zero of the 285 failing tiles is
physically constrained.** The tightest failing urban tile (Patran City Docks) has 146,705u^2 of dry buildable
land against a 38,400u^2 requirement — 3.8x headroom; the tightest failing sparse tile has 38,039u^2 against
7,200u^2. The conclusion is not sensitive to the packing allowance: at 3x, 5x and 8x nothing could plead
constraint, and even at 12x (buildings occupying 8% of a tile) only two tiles could. There are consequently
**zero documented physical shortfalls and 285 silent misses**, which is the addendum's gate failure condition.

### Two findings worth recording

1. **Relief shoulders are annuli, and clipping by them erases the plateaus they enclose.** A first version of
   the dry-area probe applied `HillVisuals` shoulders directly and reported **147 tiles with zero buildable
   area**, including tiles that visibly carry buildings. The fabric already guards against this with
   `MORPH_MIN_RELIEF_AREA_RETENTION` (0.72), abandoning relief whenever it retains too little; the probe now
   mirrors that rule exactly and **249 of 395 tiles hit the fallback**. Any stream that reaches for relief
   geometry as an area constraint must apply the same retention rule or it will measure phantom constraints.
2. **`get_land_relief_geometry` must be called per tile, not batched.** It only reports shoulders when the
   extent it is given spans three or more material bands, so one call over all 395 hexes activates relief on
   tiles that individually have none and over-clips them. A batched variant was written, measured against the
   per-tile result, found to differ, and reverted.

### Verification

- Unit suite: **2,287 passed, 0 failed** (v0 baseline 2,260 + the 27 new asserts). Established Godot shutdown
  RID/resource warnings remain.
- Two consecutive density-audit runs are byte-identical in both the JSON and the text artifact.
- Morphology harness: the metrics JSON is **exactly equal to the frozen v0 record** — every settlement, every
  district-field counter (92/0/0/87/7/0/13/55), all seven W1.01 water counters zero on both plans, all four
  relief counters zero, `dry_land_guard.water_overlap_count` zero, 2,135 blocks and 361 parks unchanged. Two
  full morphology runs are byte-identical across all 36 artifacts. The harness exits 1 on the unresolved
  G1.02 gradient gate, as designed.
- Road-frontage audit frozen on all eight counters: 177 road tiles, 413 buildings, 79 failing tiles, 177 over
  15u, 137 off-road-by-design, 1 service-lane save, 165 block-mode failures without streets, 146.6u `tile_10_3`
  furnace worst case.
- All-style harness: within a run, `legacy_before == legacy_roundtrip == ink` and
  `midcentury_wide == midcentury_repeat`, both exactly.
- `git diff --check` clean.

### ⚠ The frozen absolute PNG hashes no longer reproduce on this machine

Every one of the 43 all-style PNGs differs from the v0 archive, **including classic, ink and plate, which no
commit on this branch touches.** Cause: the captures are now **2360x1328** instead of the archived **1920x1080**
— `project.godot` declares `window_width_override=2360`, and the display attached to this machine now honours
it. This was proved not to be a source change: a clean detached worktree at the same base commit
(`2345b9cf`, no M1 changes) was captured and its 43 PNGs are **byte-identical to the M1 branch's 43 PNGs**.

To reproduce that control:

```bash
git worktree add --detach /tmp/poe_control <base-commit>
cp -c -R <owner-checkout>/.godot /tmp/poe_control/price-of-everything-0.1/.godot
cd /tmp/poe_control/price-of-everything-0.1
<godot> --headless --path . --import
<godot> --path . res://tools/map_style_shot.tscn --quit-after 12000   # holding the capture lock
```

Consequence for the four downstream streams: **do not compare against the frozen v0 hashes on this machine.**
Byte-identity must be established against a same-machine, same-session control capture, and the semantic
invariants (legacy round-trip identity, midcentury repeat identity, and the morphology metrics JSON, which IS
still exactly equal to v0) carry the actual guarantee.

### How downstream runs the audit

```bash
cd price-of-everything-0.1
<godot> --headless --path . res://tools/density_audit.tscn --quit-after 40000
#   → /tmp/poe_density_audit.json  (full per-tile record)
#   → /tmp/poe_density_audit.txt   (table + failure list)
#   exit 0 compliant · 2 ran and non-compliant · 1 could not run
```

The frozen baseline output is committed at `docs/map-density-audit-baseline.txt`. Compare against it; do not
regenerate it as a way of moving the goalposts.

## M2. Settlement completion — the per-tile density floors — 2026-08-14

> **Integrator's note (2026-08-14).** This stream originally numbered itself `N1`, colliding with the ports stream's `N1`. It is renumbered **M2** here (its free chronological slot); `N1.01`/`N1.02` inside it became `M2.01`/`M2.02`. No wording otherwise changed. The mechanism is **not** merged — only this postmortem is.


### Scope

Stream: section 2 of `docs/map-density-and-port-addendum.md` — the building-count minimums for
all four tile classes. Branch `gauntlet3/density`, worktree `/tmp/poe_g3_wt/density`, based on
`gauntlet3/density-audit` @ `781bc519`.

### Baseline, regenerated from this worktree

`res://tools/density_audit.tscn` run here reproduces `docs/map-density-audit-baseline.txt`
byte-for-byte (exit 2, 395 audited, 285 failing, 285 undocumented). Per class:

| class | tiles | compliant | failing | failure histogram |
|---|---:|---:|---:|---|
| urban | 92 | 19 | 73 | green_below_floor 57, large_below_floor 38, small_below_floor 35 |
| sparse | 204 | 45 | 159 | small_below_floor 154, large_above_cap 6, small_above_cap 2 |
| mountain | 45 | 45 | 0 | — |
| remote | 54 | 1 | 53 | small_below_floor 53 |

Zero failing tiles are `physically_constrained` in any class: the minimum measured
`dry_buildable_area` is 140,269u² for urban (needs 38,400), 38,039u² for sparse (needs 7,200)
and 141,792u² for remote (needs 2,400). No tile is prevented by land; every miss is a miss of
invitation, not of space.

### Hypothesis, written before coding

The fabric grows only where a generator was invited, and the invitation list is narrower than
the map. Three exclusions account for essentially every miss:

1. rural growth is gated on terrain type `rural`, so the 74 sparse **hill** tiles are never visited;
2. roadless tiles are explicitly skipped (`roadless_skips`), so 53 of 54 **remote** tiles are empty;
3. urban tiles have no count floor at all, so 73 of 92 fall under 10 small / 3 large / 2 parks.

**Mechanism — one new architectural layer, "settlement completion".** A single deterministic
stage runs once, after every existing generator and after the universal district audit, before
sanitisation. It classifies every land tile exactly as `DensityAudit.classify` does, measures the
tile's current counts under the exact `DensityAudit` rules, leaves compliant tiles untouched, and
for a tile below its floor grows through an **anchor ladder**, strongest structure first, stopping
the moment the floor is met:

* **rank 1 — road frontage.** Every BUILT road segment on the tile, sampled at a fine spacing with
  a per-tile hashed start rotation. This is the D1.01 frontage grammar, extended to the terrain
  types D1.01 never visited. Occupancy rejection, not a spacing constant, produces the row.
* **rank 2 — accretion.** A neighbour placed along an existing mass's own long axis at a lane gap,
  so extra count reads as an accumulated cluster rather than scatter.
* **rank 3 — homestead seed** (roadless tiles only). ONE clustered farmstead per tile at a
  deterministically chosen sheltered dry point. One cluster per tile is the opposite of uniform
  scatter, and it is the only legal way to reach the remote floor, which by definition has no road.
* **large masses** (urban only): a block-scale mass placed on the local road axis.
* **parks** (urban only): a green in a clear interstice, using the existing `_add_park` vocabulary.

Every candidate passes the identical safety vocabulary the rural pass already uses, so the seven
W1.01 counters and the relief counters stay zero by construction. Nothing is removed or moved —
deletion and reordering are retired mechanisms and are not used. Caps are never approached from
above: the pass only ever adds, and only up to the floor.

**Prediction:** sparse 45/204 → ≥190, remote 1/54 → ≥50, urban 19/92 → ≥60, mountain 45/45
unchanged. The six sparse `large_above_cap` tiles are urban SPILL from the accepted district field
(`tile_23_9` carries 24 large ordinary masses beside Capital Port) and are out of reach of an
additive mechanism; they are reported, not chased.

### M2.01 — the mechanism, measured (**REJECTED — see M2.02**)

> **Heading corrected at close-out.** The numbers in this section are sound — they were
> reproduced independently before the revert — but the word "accepted" was written before the
> blind pair had been scored, and it is wrong. The mechanism was rejected and has been removed
> completely. Read this section together with M2.02.

The one stage is `UrbanFabricVisuals._complete_density_floors`, called from `_rebuild` after
`_build_universal_district_audit` and before the two sanitisers. Deliberately after the district
audit, so the accepted G1.02 district-field counters keep measuring the field mechanism itself
rather than the floor top-up placed on top of it — those counters are byte-identical to v0.

**Result, regenerated from this worktree** (`res://tools/density_audit.tscn`, exit 2):

| class | tiles | compliant v0 | compliant now | failing now | failure histogram now |
|---|---:|---:|---:|---:|---|
| **urban** | 92 | 19 | **77** | 15 | large_below_floor 11, green_below_floor 8 |
| **sparse** | 204 | 45 | **193** | 11 | large_above_cap 6, small_below_floor 5, small_above_cap 2 |
| **mountain** | 45 | 45 | **45** | 0 | — |
| **remote** | 54 | 1 | **54** | 0 | — |
| **TOTAL** | 395 | 110 (27.8%) | **369 (93.4%)** | 26 | — |

**Undocumented misses: 285 → 6.** All six are the pre-existing sparse CAP violations
(`tile_8_7`, `tile_17_7`, `tile_22_7`, `tile_22_8`, `tile_23_9`, `tile_26_9`), unchanged from v0
in both direction and magnitude. They are urban SPILL from the accepted G1.02 district field —
`tile_23_9` carries 24 large ordinary masses beside Capital Port — and an additive mechanism
cannot reach them. Removing spill masses to satisfy a cap is post-generation deletion, a retired
mechanism, so they are reported rather than chased. Every remaining BELOW-FLOOR miss (20 tiles)
now carries a documented shortfall with its rejected-candidate counts, which is what the addendum
asks for.

The pass added 583+ masses and 81 greens across 277 tiles; 118 already-compliant tiles were left
untouched. Fabric totals moved 2,135 → 2,802 blocks and 361 → 444 parks. 53 remote tiles received
a homestead; 16 accretion masses were needed, i.e. road frontage carried almost all of the growth,
which is the D1.01 character the stream had to preserve.

### Three engine findings this stream had to fix before the mechanism worked

1. **Relief annuli again.** The first candidate run lost **41,872 of ~64,000 candidates to relief
   alone** and moved compliance only 110 → 181. The cause is the shoulder-annulus trap the M1
   stream recorded: `_relief_geometry_for_extents` reports offset RINGS, and clipping a hex by
   them erases the plateaus they enclose. `_build_morph_component` already abandons relief when it
   retains less than `MORPH_MIN_RELIEF_AREA_RETENTION` (0.72), and so does the dry-area probe — but
   `_build_rural_growth` does not, and neither did the first version of this pass. Mirroring the
   rule (189 of 277 grown tiles hit the fallback) took relief rejections to 600 and compliance to
   358. Contour discipline is then kept the way B1.01 actually states it: when relief is abandoned,
   a candidate is rejected if its mass or its shadow spans two land bands
   (`multi_band_decorative_building_count` stays 0).
2. **The sanitisers delete what the pass counted.** `_sanitize_decorative_fills` and
   `_sanitize_gameplay_collisions` run after every generator and remove roughly 98 masses map-wide;
   the gameplay one is MAP-WIDE and expands each footprint by 4.5u, so a footprint on a
   *neighbouring* tile removes a mass a per-tile check accepted. Counting a mass that is later
   deleted converts a satisfied floor into a silent miss. Applying the identical two predicates
   both when measuring existing masses and when accepting candidates took undocumented misses
   21 → 6 and urban compliance 72 → 77.
3. **The size cut has to be enforced, not assumed.** A mass under
   `DensityAudit.MIN_COUNTED_MASS_AREA` is a fragment the audit ignores entirely, and geometry
   jitter in `_stepped_row` can push a nominally 22x15 mass under it. `completion_size_class_ok`
   is now a static, unit-tested predicate with a 40u² margin either side of both frozen cuts.

### M2.01 verification

- Unit suite **2,296 passed, 0 failed** with a real summary line (v0 2,287 in this worktree plus
  exactly the 9 new completion asserts).
- Two consecutive density-audit runs byte-identical in both JSON
  (`658c2f63f6ec0ec8a33ca9004944ef71775e648838065907f5055b3a22a0f438`) and text
  (`625084084b939e6cb6d8e58a61a0b2073be01e53e42f5bb658a3145503680705`).
- Road-frontage audit **byte-identical to the v0 archive log**, all eight counters frozen: 177 road
  tiles, 413 buildings, 79 failing tiles, 177 over 15u, 137 off-road-by-design, 1 service-lane
  save, 165 block-mode failures without streets, 146.6u `tile_10_3` furnace worst case.
- Morphology metrics: every named water and relief gate counter is **zero and unchanged from v0** —
  `water_overlap_count`, `apron_water_overlap_count`, `cross_bank_mass_count`,
  `disconnected_mass_after_water_clip_count`, `roof_element_water_overlap_count`,
  `shadow_water_overlap_count`, `uncovered_river_join_count`,
  `contour_crossing_decorative_mass_count`, `disconnected_mass_after_relief_count`,
  `multi_band_decorative_building_count`.

### M2.01 capture evidence and a capture-lock contamination incident

- **Determinism.** Three consecutive full all-style capture runs at the final commit are
  **byte-identical across all 43 artifacts** (runs B, C, D). Two morphology runs are byte-identical
  across every fixed output, and the morphology metrics JSON is byte-identical between them.
- **Legacy identity.** A same-machine, same-session control was captured from a detached worktree
  at the base commit `781bc519`, per the M1 warning that the archived absolute hashes no longer
  reproduce on this machine (the display forces 2360x1328 instead of the archived 1920x1080). All
  **32 legacy artifacts** — every classic, ink and plate framing plus `wide_legacy_before` and
  `wide_legacy_roundtrip` — are byte-identical between the candidate and that control. Within the
  candidate run, `wide_legacy_before` == `wide_legacy_roundtrip` == `wide_ink`
  (`82cdd1f07ab4e0fe241466b95119e3dfa967fc5793b2622f871c6664e0cbf96e`) and `wide_midcentury` ==
  `wide_midcentury_repeat` (`f678d7cbf795a762f7bbcb1aded188e033678e439d6923296c38346386703ff9`).
  All **10 mid-century framings** differ from the control, which is the intended change.
- **A capture-lock contamination incident worth recording.** A first capture attempt ("pass A")
  produced 43 PNGs whose mid-century framings were *pixel-identical to the base commit* while the
  morphology run from the same code state clearly carried the new masses. Cause: the attempt was
  run in a foreground shell that blocked in the `while ! mkdir "$LOCK"` wait, and the shell's
  10-minute limit killed it **before Godot ever launched**; the `/tmp/poe_mapstyle_*.png` files
  picked up afterwards were another concurrently-running agent's output. The tell was that the
  attempt's own redirected log file did not exist. **Lesson for concurrent streams: a capture is
  only yours if its own log exists and carries its own exit line — never authenticate an output set
  by the presence of files in `/tmp`.** Pass A is discarded; nothing in this report rests on it.

### M2.02 — blind verdict on the completion pass: **REJECTED, mechanism removed**

| field | value |
|---|---|
| **Iteration** | M2.02 (close-out of M2.01) |
| **Stream / lever** | Addendum §2 — per-tile building-count floors across all four tile classes |
| **Layer changed** | one: `UrbanFabricVisuals._complete_density_floors` (settlement completion) |
| **Status** | **REJECTED — reverted. Renderer source byte-identical to `781bc519`.** |
| **Evidence** | blind pair `/tmp/poe_g3_blind/DENSITY/{wide,inland,farmclose,coast,denseclose,playerclose}/image_{1,2}.png` — `image_1` = candidate `61a19b8c`, `image_2` = same-machine control at `781bc519` |
| **Next bottleneck** | the *form vocabulary* of a completion mark, not its placement rule |

#### The verdict, and why a win is still a rejection

The blind critic returned **`image_1_better`** — the candidate won. It is still rejected, and the
reason is the standing acceptance rule of §2 of the gauntlet II prompt:

> *Accept only if a primary failing score rises with no material regression elsewhere.*

The four primary failing categories of the whole-map critique scored, candidate / control:

| primary failing gate | candidate | control | movement |
|---|---:|---:|---|
| reference-family resemblance | 3 | 3 | — |
| continuous figure/ground | 3 | 3 | — |
| historically accumulated character | 3 | 3 | — |
| absence of procedural repetition | **2** | 3 | **FELL** |

**No primary failing gate rose, and one fell.** The rubric averages are a dead tie, **3.50 / 3.50**.
The category that did rise — inhabited impression, 3 → 4 — is a real gain but is not one of the
four gates this gauntlet exists to close, and it was bought by dropping one of them to 2. The
critic's own summary is *"a narrow win, not a good result… neither image is a passing plate"*, and
the tie was broken on reference-family reasoning rather than on any score. Both halves of the
acceptance rule fail, so the candidate is not accepted.

#### The three defects, independently re-measured at close-out

Every claim below was reproduced from the blind PNGs at close-out, not taken on report:

1. **One glyph, ~131 times.** Connected-component extraction of the candidate-minus-control mask
   over the five close framings yields **134 added elements** (critic: 131) with bounding-box
   aspect **p10 1.00 / median 1.10 / p90 1.62** (critic: 1.00 / 1.15 / 1.69). Area varies about
   12×, so scale varies; **form does not**. Not one L, U, courtyard ring, attached terrace or
   farmyard pair in the whole set. Diff footprints match the critic exactly: wide 0.200%, coast
   0.507%, denseclose 0.374%, farmclose 0.592%, inland 0.705%, playerclose 0.838%.
2. **A second, new repeated glyph — the chevron paddock.** Confirmed by direct A/B crop at
   `denseclose (1102,531)`: the candidate carries a dark-green pentagon with a single white
   two-stroke chevron where the control has plain green. At `inland (735,817)` and `(740,880)`
   **two of them sit 63px apart, identical in size, outline and mark, both inside one glance.**
3. **Bare footprints beside a richer authored vocabulary.** The additions carry no plot boundary,
   yard or field, and sit next to the map's own hatched strip-field compounds with embedded
   roofs and mill discs. The average quality of a rural mark falls while the count rises.

#### Root cause of defect 2 — a vocabulary borrowed outside its scale range

`_completion_place_park` reuses `_add_park`, which is correct: reusing the accepted green
vocabulary was the right instinct. But `_add_park` also stamps a two-segment path mark into
`_park_marks`, sized `u = min(length*0.25, 16)`, `v = min(depth*0.20, 8)`, with only ±4.0u of
bend jitter. In a large urban park — the vocabulary's original and only home — that is a small
path inside a big green. At the completion pass's paddock scale (`COMPLETION_PARK_LENGTH`
40–56u, `COMPLETION_PARK_DEPTH` 28–38u) the same two strokes span most of the shape and the
jitter is far too small to differentiate them, so the mark stops being a path and becomes the
glyph. **An accepted mark is only accepted at the scale it was accepted at.** Reusing a
vocabulary element at a materially smaller size is a new mechanism and needs its own scrutiny.

#### What this proves about the abstraction

The completion pass separates cleanly into two halves, and the blind pair scores them opposite ways.

- **The placement half is right and should be carried forward.** The anchor ladder (road frontage
  → accretion → homestead) reached 93.4% compliance with road frontage carrying almost all growth
  and only 16 accretion masses, which preserves D1.01's road-dependency character. The critic
  reached the same conclusion from the pixels — *reported* (not re-verified at close-out) as
  added-element distance-to-nearest-road of median 14px with 90% inside 60px, and summarised as
  *"image_1's placement rule is already 90% right."* The critic also reports a **10% roadless
  tail** (13 of 131 beyond 60px, worst 789px). That tail is partly legitimate — the addendum
  itself gives remote roadless tiles a floor of 1–4 small buildings — but the homestead rung
  clearly places some of them where they read as a lone shed on open moorland, and attempt 2
  should tighten it.
- **The generation half is wrong.** A count floor implemented as *"emit N acceptable masses"*
  optimises for the audit and produces one shape N times. **Counting gates cannot be satisfied by
  a single-form emitter without converting a density defect into a repetition defect** — which is
  a strictly worse trade here, because repetition is one of the four gates and density is not.

This is the third time this project has failed the same way (V4.09a/b hook returns, V2.02 central
lozenge, H2.04–05 tick glyphs) and the first time it has done so while *winning* its blind pair.
The graveyard entry is therefore about the emitter, not about density floors.

#### Attempt budget

This is **attempt 1 of 2** on settlement completion. The mechanism is removed from the renderer
now rather than left live, for two reasons: the standing rule forbids leaving a rejected mechanism
partly in place, and three other streams (parks, coast, ports) are judged against this same
baseline — leaving a fabric that a blind critic scored 2/5 on repetition would contaminate their
comparisons. One attempt remains.

#### Revert verification (all re-run at close-out, not inherited)

- `git diff 781bc519 --stat` → **only `reports/map_visual_gauntlet.md` differs.** The renderer,
  the test runner and the tools tree are byte-identical to the base commit; the probe scene that
  read `density_completion` was removed with the metric it read.
- Unit suite → **`==== 2287 passed, 0 failed ====`** with a real summary line — exactly the v0
  count for this worktree (the candidate's 2,296 was v0 plus its 9 completion asserts).
- Density audit (`res://tools/density_audit.tscn`, exit 2) → output **byte-identical to the frozen
  `docs/map-density-audit-baseline.txt`**: 395 audited, 285 failing, 285 undocumented. The fabric
  is measurably back at v0, by the same instrument that measured the candidate.
- Road-frontage audit → log **content-identical to the v0 archive** (`/tmp/poe_g2_baseline/v0/frontage_audit.log`;
  the only textual differences are per-run planner millisecond timings and the absolute log path).
  All eight counters frozen: 177 road tiles, 413 buildings, 79 failing tiles, 177 over 15u, 137
  off-road-by-design, 1 service-lane save, 165 block-mode failures without streets, 146.6u
  `tile_10_3` furnace worst case. The four port planner hashes are unchanged.
- All-style capture harness run **twice** at the reverted HEAD, windowed, under the capture lock —
  see the hash block below.
- `git diff --check` clean.

The e2e balance harness was not re-run: the net source diff against the base commit is empty, so
there is no sim surface to regress. That is a statement of what was and was not done, not a claim.

#### Blind-slot authentication (do this, every time)

The slot mapping was verified before the verdict was applied, from the pixels rather than from
either agent's note. The candidate is purely additive, so the slot carrying *more* structures must
be the candidate: over all six framings the changed pixels are markedly **darker in `image_1`**
(mean RGB 100–117, ink masses) than in `image_2` (138–148, open grass). `image_1` = candidate,
independently. It also matches the capture hash the implementer recorded for `wide_midcentury`
(`f678d7cb…`), so note and pixels agree — but the pixels were checked first.

#### Next lever

Not a third density mechanism. **Give the completion mark a form vocabulary, then re-run the same
placement rule** — this is the one change attempt 2 should make:

1. Draw completion masses from the existing accepted mass vocabulary (solid / L / U / courtyard
   ring / attached pair), in the proportions the accepted urban fabric already uses, instead of a
   single rounded rectangle. The vocabulary exists and is accepted; the completion pass simply
   never called it.
2. Give each mass a plot or yard, so a rural addition reads like the map's own strip-field
   compounds rather than a footprint dropped on grass.
3. Cluster 2–4 masses into a hamlet with a shared frontage line instead of spacing single marks
   evenly along a lane — several inland runs currently read as a dashed cartographic line.
4. **Drop the `_add_park` path mark entirely at paddock scale**, or scale the mark and its jitter
   with the shape rather than clamping it.
5. Leave the anchor ladder, the relief-retention fallback and the sanitiser-mirroring predicates
   exactly as M2.01 had them — those are the parts that worked.

The three engine findings recorded in M2.01 survive this rejection and remain actionable for every
other stream, in particular that **`_build_rural_growth` still applies raw relief shoulders with no
retention fallback**, which is very likely why D1.01 recorded so many relief rejections and reached
only 184 masses.

#### M2.02 capture evidence — the revert reproduces V0 exactly

Two all-style harness runs at the reverted HEAD, windowed, serialized under
`/tmp/poe_gauntlet2_capture.lock`, each authenticated by **its own** log file and its own exit
line (per the pass-A lesson recorded in M2.01):

- **Run-to-run determinism:** R1 vs R2 → **identical=43 differing=0**, both exit 0.
- **V0 identity, measured against the blind control itself.** The `image_2` slot of the blind pair
  *is* a same-machine control capture at `781bc519`, so it is the correct V0 reference on this
  display. All six blind framings at the reverted HEAD are **byte-identical to `image_2`** and
  byte-different from `image_1`:

  | framing | reverted HEAD = control `image_2` | candidate `image_1` |
  |---|---|---|
  | wide | `2edb87aeae1e6891…` ✔ | `f678d7cbf795a762…` |
  | inland | `29145c7ef2205927…` ✔ | `0a3186d281ddcbac…` |
  | farmclose | `9f1f247a159be72a…` ✔ | `6c92262aff99aef5…` |
  | coast | `ecdf5b6155285131…` ✔ | `a48f7bc2cd52b4ad…` |
  | denseclose | `98caec96b3e03c9d…` ✔ | `110100f9680604ca…` |
  | playerclose | `ac0ae774531a68f2…` ✔ | `c7be537fea71c139…` |

  This is also the **third independent confirmation of the blind slot mapping** (`image_1` =
  candidate), after the darker-pixel test and the implementer's recorded hash.
- **Legacy identity, within run:** `wide_legacy_before` == `wide_legacy_roundtrip` == `wide_ink` ==
  `82cdd1f07ab4e0fe241466b95119e3dfa967fc5793b2622f871c6664e0cbf96e`; `wide_midcentury` ==
  `wide_midcentury_repeat`. The harness's own two assertions printed in **both** runs: *"midcentury
  seeded map layer pixel exact across repeated wide capture"* and *"midcentury round-trip pixel
  exact in masked map region (back to ink)"*.
- **Morphology harness** run at the reverted HEAD → exit 1 **as designed** (unresolved G1.02
  gradient gate). All ten water and relief counters are **zero and equal to the v0 archive record**:
  `water_overlap_count`, `apron_water_overlap_count`, `cross_bank_mass_count`,
  `disconnected_mass_after_water_clip_count`, `roof_element_water_overlap_count`,
  `shadow_water_overlap_count`, `uncovered_river_join_count`,
  `contour_crossing_decorative_mass_count`, `disconnected_mass_after_relief_count`,
  `multi_band_decorative_building_count`.

#### A trap for the other gauntlet-3 streams: the archived morph PNGs look comparable and are not

The M1 report already warns that the archived **mapstyle** hashes no longer reproduce, because the
display now forces 2360x1328 instead of the archived 1920x1080 — and that is obvious, since the
archived PNGs are visibly a different size. **The archived morph PNGs hide the same problem behind
an identical file size.** All 22 of them are 960x480 in both the archive and today's runs, so they
invite a byte comparison; all 22 differ.

The cause is in the harness: `settlement_morphology_shot.gd` does not downsample, it **centre-crops**
the viewport texture — `crop_origin = (image.width - 960)/2`. A different viewport size therefore
yields a crop of a different world extent at the same output dimensions. Nothing in the file size,
the dimensions or the metrics reveals it.

The delta is provably **not** attributable to this stream: the reverted tree is byte-identical to
`781bc519` (`git diff 781bc519 --stat` lists only this report), so whatever differs from the
`/tmp/poe_g2_baseline/v0` archive differs at the base commit too. Note also that the archive was
taken at `5443818d` ("renderer state identical to `e8cd62ca`"), and `4e863c8d` — *"Fix: per-tile
relief in the dry-area probe; batching over all hexes over-clips"* — landed in
`scripts/urban_fabric_visuals.gd` between that archive and every gauntlet-3 base.

**Rule for the remaining streams: compare against a same-machine, same-session control captured
from your own base commit. Do not byte-compare anything in `/tmp/poe_g2_baseline/v0` — not even the
outputs whose dimensions match.** The counters in that archive remain valid; the pixels do not.

> **Integrator's note (2026-08-14).** The park-halving mechanism is **not** merged; this postmortem is preserved on `gauntlet3/integrated` while the code stays only on `gauntlet3/parks`.

## M3. Park halving in the four largest cities — addendum section 3 — 2026-08-14

### Which four cities — the addendum's guess was right, but only after a tie-break

Connectivity was computed over all 92 authoritative urban tiles (not over the fabric's own component list —
Arin is lifted into the hero path but is still one city). Ranked by tile count, then by the count of tiles
whose AUTHORITATIVE profile in `data/visual_settlement_profiles.json` is `metro`, then by first tile id:

| rank | component key | tiles | metro tiles | name | baseline park area |
|---|---|---|---|---|---|
| 1 | `tile_10_16` | 9 | 9 | Arin City | 214,177 u² |
| 2 | `tile_23_8` | 7 | 3 | Capital Port | 78,613 u² |
| 3 | `tile_18_14` | 5 | 0 | Teganfort | 12,511 u² |
| 4 | `tile_17_8` | 4 | 2 | Patran City | 39,156 u² |

The second sort key is load-bearing: **six components tie at four tiles** (Fort Silversworth, Copperstown,
Port Lightning, Patran, Kingstown, Gold Arm). Exactly one of them — Patran City — carries metro tiles, so the
authoritative profile data resolves the tie without inventing a measure of "largeness". The addendum's
expectation (Arin, Capital Port, Patran, Teganfort) is therefore confirmed on the data, all four.

⚠ A parity trap sits in the way of anyone re-deriving this: **tile ids are coord+1**, so `tile_23_8` is
coord (22, 7) and the odd/even column offset in `HexMap._neighbor_offset_for_hsm` keys on the COORD parity,
not the id parity. Computing adjacency from the id numbers produces a different, wrong component set (it
merges Tomash into Arin and splits Capital Port from its Foundry and Industrial Zone).

### The defect, measured

Green is drawn as a WHOLE-PARCEL fill: a face whose role is `park` becomes one inset green polygon covering
the entire street face. Arin averaged ~7,100 u² per green space. Capital's centre-east tile — `tile_25_9`,
the tile that connects the Old Quarter/Docks half of the city to the Industrial Zone/Foundry half — carried
**seven greens totalling 31,625 u² and ZERO large buildings**. That is the gap the owner reads as the city
being split in two.

### The mechanism — one straight cut per park face, freed half built out

One architectural layer: the park fill step of `UrbanFabricVisuals`, shared by the morph, settlement-plan and
hero-Arin park branches (`_add_park_fill`).

1. A park face whose centroid lies in one of the four components is cut ONCE, straight, by bisection on the
   projected area (`_split_poly_area_fraction`), retaining 46–58% (hash-jittered per face).
2. 62% of faces take a **frontage band** cut (buildings on the long street edge, green retreating into the
   block interior); the rest take an **end cut** (green keeps one end of the block). Two arrangements, so the
   pass does not stamp one repeated glyph.
3. The freed half is built with the EXISTING fine-grained micro-row vocabulary
   (`_morph_add_small_town_micro`, new `allow_pocket = false` so it cannot put green back). Its masses run
   ~300–600 u², well under the audit's 1,600 u² large cut — the addendum's "smaller decorative buildings,
   finer-grained than the current ordinary vocabulary".
4. `AccommodationSitePlanner` sites that sat inside park land now render as **reserved industrial plots**
   (`releasable_yard` / `industrial_growth`) instead of green, but only where the tile still renders three or
   more counted green spaces without them, so the conversion can never take a tile below the ≥2 floor.

Nothing draws a line into a park. That is deliberate: the retired promenade greens (H2.08/H2.09) and the
sampled river offsets (P3.01/P3.02) both failed because they wrote a repeated LINEAR mark into green. Here one
side simply stops being green and becomes building parcels.

### Three guards, each added because a measurement caught a real loss

- **`PARK_HALVING_MIN_FACE_AREA = 2,600 u²`.** A park face loses roughly `perimeter × inset` before it draws,
  so a 1,400 u² face renders only ~590 u² of green; halving that puts both halves under the audit's 200 u²
  counted-green floor. Measured: Teganfort `tile_19_13` went 1 park to 0.
- **Post-render abandon (`MIN_KEPT_GREEN 420`, `MIN_KEPT_PIECE 260`).** The retained half is inset and clipped
  against the footprint exclusions FIRST; if what comes out is not a green space the audit would still count,
  the split is abandoned and the face is drawn whole. 2 of 50 candidate faces abandon.
- **Home-tile ownership preference.** The audit credits a polygon to the tile it shares the most AREA with. A
  retained half leaning over a hex side is credited to the neighbour and the home tile silently loses a green
  space (Capital `tile_24_9`, 2 → 1). The planner now computes the face's owner by the same shared-area rule
  and flips which side keeps the green when — and only when — that restores the owner. A centroid-based
  version of this guard was tried first and was strictly worse (it cost `tile_24_8` its only park); it was
  replaced, not tuned.

### Result — the gate is met at 49.53% retained

| component | tiles | park area before | after | park count before → after | small buildings before → after |
|---|---|---|---|---|---|
| Arin City | 9 | 214,177 | 100,658 | 30 → 31 | 142 → 263 |
| Capital Port | 7 | 78,613 | 43,817 | 11 → 11 | 203 → 298 |
| Teganfort | 5 | 12,511 | 6,187 | 4 → 4 | 75 → 86 |
| Patran City | 4 | 39,156 | 19,963 | 9 → 9 | 54 → 77 |
| **TOTAL** | 25 | **344,457** | **170,625** | **54 → 55** | **474 → 724** |

**49.53% retained** — the addendum asks for half ±10%, i.e. 45–55%. No green space was lost anywhere: the
count went UP by one. Urban `green_below_floor` tiles are unchanged at 57, parkless urban tiles unchanged at
37, `small_below_floor` improved 35 → 33, and compliant urban tiles improved **19 → 21**. Park area in every
OTHER urban component is unchanged to the unit (325,264 u² before and after), which is the scoping proof.

Fabric totals: 2,135 → 2,406 decorative blocks, 361 parks (unchanged), 48 faces split, 2 abandoned, 261
backfill masses, 9 reserved plots.

### One honest regression — the open G1.02 road-gradient gate goes 7 → 8

`district_field.gradient_failure_count` rises from **7 to 8** of 87 applicable tiles. The new failure is
**`tile_19_14` Teganfort Old Quarter**, whose gradient delta falls from 15.38 to 4.57 against a 5.00
requirement: the backfill put buildings into the road-poor part of the tile and flattened the road-rich vs
road-poor coverage difference. `density_direction_failure_count` moves 7 → 8 with it.

This is a real regression on a gate the addendum explicitly does not reopen (§7) and that the morphology
harness already exits 1 on. It is not hidden and it is not repaired here: repairing it needs road geometry
inside the park-split planner, which is a second mechanism. No other district-field counter moves —
`missing_visible_core_count` 0, `dense_core_failure_count` 0, `internal_seam_failure_count` 0,
`hex_boundary_failure_count` 13, `local_hex_failure_count` 13, `actual_spill_tile_count` 55, all unchanged.

### Verification

- **Unit suite: 2,296 passed, 0 failed** (2,287 inherited from M1 plus 9 new asserts pinning the area cut,
  its determinism, the four-city gate, the small-face floor and the shared-area ownership rule).
- **Two byte-identical morphology capture runs**: all 24 artifacts this branch writes, including
  `poe_morph_metrics.json`, hash identical across runs A and B.
- **Two byte-identical density-audit runs** (JSON and text).
- **All seven W1.01 water counters ZERO** on both settlement plans, plus `dry_land_guard.water_overlap_count`
  0, `gameplay_collision_guard.opaque_overlap_count` 0, and every relief overlap/disconnected counter 0.
- **Rural growth and suburban fringe are untouched** — every counter identical to v0 (rural 184 masses,
  83.15% frontage; suburban 11 masses, 1 cross-tile district, 2 access streets, all failure counters 0).
- **Scoping proof, two independent ways**: at the fabric level only `settlement-plan|capital-port`,
  `settlement|tile_17_8`, `settlement|tile_18_14` and `hero_arin` change green or built area — all other 36
  settlements are identical to v0. At the audit level, urban park area outside the four components is
  325,264 u² before and after.
- **Road-frontage audit frozen on all eight counters**: 177 road tiles, 413 buildings, 79 failing tiles, 177
  over 15u, 137 off-road-by-design, 1 service-lane save, 165 block-mode failures without streets, 146.6u
  `tile_10_3` furnace worst case.
- **All-style harness, two full runs 40 minutes apart: all 43 PNGs byte-identical.** Within each run,
  `legacy_before == legacy_roundtrip == ink` exactly (`82cdd1f0…`) and `midcentury_wide ==
  midcentury_repeat` exactly (`8336ce4d…`), and the harness's own in-memory masked round-trip assertion
  passed — that assertion compares viewport images, so it is immune to the `/tmp` filename collisions that
  concurrent streams cause. Legacy wide hashes: classic `749c72fb…`, ink `82cdd1f0…`, plate `d3989f0e…`. Per
  M1's finding these do not match the v0 archive because the window is now 2360x1328 rather than 1920x1080;
  same-machine identity is the available guarantee.
- **Same-machine base-branch control.** `res://tools/map_style_shot.tscn` was captured from a clean checkout
  of the base commit (`/tmp/poe_g3_control`, `781bc519`) in the same session and window. All **32 legacy PNGs
  are byte-identical** to this branch's — classic, ink, plate, `legacy_before` and `legacy_roundtrip`, in
  every framing. Of the 11 midcentury framings, 6 differ (the intended change) and 5 are identical, those
  being the framings that do not look at any of the four cities.
- `git diff --check` clean; the only files this branch changes against `gauntlet3/density-audit` are
  `scripts/urban_fabric_visuals.gd`, `tests/test_runner.gd` and this report.

### Blind comparison staged

`/tmp/poe_g3_blind/PARKS/{A,B,C}` — slot 1 is the v0 baseline and slot 2 the candidate in all three, so the
ordering carries no information. A is the Capital continuity framing (the owner's named defect), B is
Teganfort core, C is the Arin hero slice. A and C are the honest test: A should be clearly better, C should be
no worse, because Arin is the owner's reference for what already works and it loses 53% of its green area
here.

### M3 verdict — REJECTED AND REVERTED

| field | value |
|---|---|
| iteration | **M3** |
| stream / lever | Park halving in the four largest cities — addendum §3 |
| change | One straight cut per park face in Arin / Capital Port / Teganfort / Patran; freed half backfilled with the micro-row vocabulary (261 masses) plus 9 reserved industrial plots |
| status | **Rejected and reverted.** `scripts/urban_fabric_visuals.gd` and `tests/test_runner.gd` restored byte-identical to the branch base `781bc519`; only this report is retained |
| evidence | Blind pair `/tmp/poe_g3_blind/PARKS/{A,B,C}`; candidate captures `/tmp/poe_g3_scratch_parks/morphB/`; baseline `/tmp/poe_g2_baseline/v0/morph/` |
| next bottleneck | The backfill **vocabulary**, not the cut |

**The blind key was re-verified by hash before the verdict was applied.** `image_1.png` in all three subdirs
hashes exactly to the v0 archive (`poe_morph_capital` `cc5225e6…`, `poe_morph_tegan_core` `d1d3cd19…`,
`poe_morph_arinold` `157d146f…`) and `image_2.png` exactly to the candidate run. Slot assignment and the
implementer's note agreed; the artifact is credited to the right image.

The critic **preferred the candidate** — `image_2_better`, average 3.42 vs 3.17 — and it is reverted anyway,
because the preference was bought with two category regressions:

| category | v0 | candidate |
|---|---|---|
| continuous figure/ground | 2 | **4** |
| inhabited impression | 3 | **4** |
| streets as negative space | 3 | **4** |
| green-space integration | 2 | **3** |
| historically accumulated character | 2 | **3** |
| decorative/gameplay hierarchy | 4 | **3** ← regression |
| absence of procedural repetition | 4 | **2** ← regression |

The critic's own summary is the finding: the candidate *"wins, but it wins on a candidate that should NOT pass
a gate."* The gauntlet bar is "scores better **with no material regression**", and reject-neutral already
establishes that a regression is disqualifying regardless of what else improves.

### Why it failed — the cut is sound, the backfill vocabulary is not

The two are separable, and the evidence separates them cleanly.

**The cut worked.** Green-space integration rose 2 → 3, and the single edit the critic rated highest in the
whole set is a halved park: at `C x796–904 / y228–322` the v0 baseline has *"a large flat green rectangle
occupying a whole city block — precisely the 'large cities look SPLIT by oversized parks' complaint"*, and the
candidate slices three street-bounded blocks across it. The owner's §4 defect (Capital reading as split in
two) is answered at `A x560–780 / y300–520`, where an empty pasture wedge inside the urban envelope becomes
walled riverbank frontage. Arin, the owner's reference, was **not** damaged by losing 53% of its green.

**The backfill failed.** Every one of the critic's four repeated-glyph sites is new backfill massing, and the
failure is one shape used everywhere: *"a mid-grey quad, near-constant footprint, near-constant rotation,
near-constant gap, laid one unit deep along a road with open field behind it… beads on a string."* Real
terraces have back plots, varied depth and rear returns; the micro-row builder has none of those, and at 261
new masses its uniformity became the dominant reading of the map.

Worse, enabling the micro builder's pocket path re-exposed **disconnected pale cream service-lane ticks** —
six in `B x165–367 / y315–395` (which also *deleted* a long accreted riverbank parcel boundary and replaced it
with nothing) and two standing in beach sand at `A ~x638 / ~x660`, free-ended at the seaward end. This is the
same pale-tick/button artifact family the project already rejected twice as **V3.03 and V3.05**. It is not a
retry of junction overpaint — a different mechanism reached the same glyph — but the graveyard verdict
*"overpaint is dead as a class"* was about the artifact, and the artifact is back.

I checked the most alarming claim myself rather than accepting it: the stubs that appear to run into the river
do **not** overlap water. A pixel test of framing B finds **zero** cream pixels on baseline-water; the only 11
changed water pixels are 5-unit antialias shifts on dark water. The seven W1.01 counters reading zero was
correct — the defect is visual (ticks reaching the bank with free ends), not a water-safety breach.

### What this proves about the abstraction

1. **Area is the wrong success measure for a density pass.** The gate (§3, half ±10%) was met almost dead
   centre at **49.53% retained**, with the ≥2 green floor held and the park *count* up 54 → 55, and the map
   still got worse in two categories. A numeric gate that says nothing about the grain of what replaces the
   removed area cannot certify a visual change.
2. **Freed area is a demand for vocabulary the project does not have yet.** The addendum's two backfill
   options were "reserved plots" or "smaller decorative buildings". Only 9 plots were reservable under the
   ≥2-green floor, so 261 of the 270 backfills fell to the micro-row builder — a builder designed for small
   rural towns, where a dozen uniform masses are plausible, and asked here to fill a city block.
3. **Precedent is decisive and it is not new.** V3.03 and V3.05 were both rejected and reverted for artifact
   resistance falling **4 → 3**, while each also fixed something real. This candidate falls **4 → 2** and adds
   a hierarchy regression. Accepting it would have overturned the standing that killed those two.

### Preserved for attempt 2 — do not re-derive

Under the two-attempt rule this is **attempt 1** of park halving; one attempt remains, and it must change the
backfill vocabulary, not the cut. The following are measured results and stay valid:

- **The four components are settled** (table above), including the second sort key that resolves the six-way
  tie at four tiles, and the **coord-parity trap** — `tile_23_8` is coord (22, 7); computing hex adjacency
  from id numbers yields a different, wrong component set.
- **The three guards each caught a real, named loss** that the ±10% area number alone would have hidden: the
  2,600 u² minimum face (inset eats small faces below the counted-green floor), the abandon-after-measuring
  rule for halves eaten by gameplay footprints, and the shared-area ownership rule (a half leaning over a hex
  side is credited to the neighbour, silently costing the home tile a park). A centroid-based version of the
  third was strictly worse and was replaced, not tuned.
- **`gradient_failure_count` 7 → 8** (`tile_19_14`) was a genuine consequence of backfilling into the
  road-poor part of a tile, and it disappears with the revert.

### Next lever

Give the backfill a **parcel-aware** vocabulary before cutting any park again: depth variation, rear plots and
corner returns driven by the street face the row sits on, so the freed half reads as blocks rather than beads.
The critic's positive finding points the way — the frontage that "walls" a riverbank scored well; it is the
repetition of one quad, and the pocket service lanes, that lost the run. Until that vocabulary exists, §3's
freed area has nowhere good to go, and the honest sequencing is vocabulary first, halving second.

## M4. Coastal reach and single-tile fill — addendum section 4 — 2026-08-14

**Iteration ID** M4.01 · **Stream** coastal reach and single-tile fill (Stoneshore, Vandel) ·
**Branch** `gauntlet3/coast`, base `gauntlet3/density-audit` (`781bc519`) · **Status ACCEPTED PARTIAL**

### Lever

Water-adjacent hex edges never carry an authoritative road crossing, so the G1.01 directional crossing lobes
can never grow the district field seaward: the extent stops roughly a core radius short of the shoreline and
leaves the unbuilt collar the owner called wrong. The lever adds, **per wet hex bearing**, one more pair of the
*already-accepted* organic influence cell — a reach spur closing the gap to the measured shoreline, and a
shore-parallel frontage cell straddling the water line — plus a **growth-intensity floor** inside the frontage
wedge so the new waterfront subdivides at core grain instead of falling into the sparse tail of the role ballot.

Draw-only. Two files, +260/−1 against the base branch:

- `scripts/urban_fabric_visuals.gd` — the reach block inside `_morph_district_field`, the constants, and
  `_morph_edge_touches_open_water` / `_morph_open_water_distance` / `_morph_coastal_intensity` /
  `_morph_polys_area_in_hex` / `_morph_record_coastal_reach`; one added line in `_morph_field_sample`.
- `tools/settlement_morphology_shot.gd` — four minimum-retention assertions.

Only the **pre-clip** extent moves. The water exclusion, the forbidden sea/mountain hexes, forest, roads,
relief, and the final dry-land and gameplay guards all run afterwards and remain the sole authority on where a
mass may sit. Rivers are deliberately excluded — they keep their existing bank and casing treatment. Cell keys
are `component|tile|coast-spur|edge` / `coast-front|edge`, so the geometry is RoadHash-deterministic; no
`randi()`/`randf()`, no wall clock, no new nodes, all geometry through the existing batched path.

Not a graveyard retry: this extends the **accepted** G1.01 organic influence cell with a new seed direction. It
is not a road-catchment envelope (C2.01–02), not a continuous density threshold (D1.01–02), and not
post-generation deletion or reordering (G1.02).

### Two rejected variants, recorded so they are not retried

1. **Wide frontage cell** (0.80 core radii, 44u depth). Draws more buildings in absolute terms — 1,624 against
   1,556 small masses map-wide — and holds Vandel Port Works visibly denser in a single 1.35-zoom frame, but
   **loses on the addendum's own §2 gate**: 27 compliant urban tiles against 32, with Stoneshore Docks and
   Vandel Port both falling PASS → FAIL, and it degrades the structural counters (new hex-coincident tiles 16
   against 11, road-gradient failures 8 against 6). §2 wins; the narrow cell ships. **Lesson worth keeping:**
   per-tile built coverage in one frame is dominated by the parcel-key re-roll lottery and is not a reliable
   single-frame signal — the audit was right and the eye was wrong.
2. **Road-bounded reach** (bound the reach by how far an authoritative road already leads seaward). This is the
   honest structural objection, since roads are frozen and are the only source of street faces. Measured, it
   starved the owner's named targets — Stoneshore Old Quarter and Stoneshore Docks at exactly **0%** growth —
   while raising dense-core failures 0 → 2. Density has to come from intensity, not from refusing to grow.

### Blind critic — CANDIDATE WON

Three framings, all visibly different at original resolution (102,343 / 383,894 / 12,299 differing pixels), so
neither side could be rejected as neutral. Slot assignment constant, `image_1` = candidate. Verdict
**`image_1_better`**, **3.25 / 5** against **2.58 / 5** on the 12-category whole-map rubric. Candidate gains on
reference-family resemblance, continuous figure/ground, organic parcel structure, streets as negative space,
green-space integration, historically accumulated character, multiscale readability and absence of procedural
repetition; nothing scored lower than v0 in any category.

The critic's own words on the owner's named defect: v0 *"vacates that entire western strip to plain green,
opening exactly the unbuilt collar between city and water that was called wrong"*, while the candidate's
*"fabric runs down to the beach — terraces, a staircase-edged cream lot, blocks touching sand."*

**The critic's one honest counter-finding is Vandel**, and the audit agrees with it — see below.

### Measured result (regenerated from an independent verification run, not the implementer's)

Usable settlement envelope inside the tile hex, core-only → with reach:

| tile | nickname | core-only | with reach | retention |
|---|---|---|---|---|
| `tile_4_9` | Stoneshore | 118,958 | 150,645 | 1.266 |
| `tile_4_10` | Stoneshore Old Quarter | 85,614 | 165,729 | 1.936 |
| `tile_5_10` | Stoneshore Docks | 105,967 | 137,750 | 1.300 |
| `tile_21_17` | Vandel Port Docks | 58,031 | 69,326 | 1.195 |
| `tile_21_18` | Vandel Port Old Quarter | 48,716 | 152,029 | 3.121 |
| `tile_22_16` | Vandel Port | 95,214 | 108,364 | 1.138 |
| `tile_23_16` | Vandel Port Works | 78,988 | 135,328 | 1.713 |
| `tile_23_18` | Vandel Island | 50,007 | 134,351 | 2.687 |
| `tile_24_17` | Vandel Island North | 22,362 | 138,230 | 6.181 |

Coastal-reach gate: 117 bearings, 48 tiles, 26 components, **retention_failure_count 0**, **minimum_retention
1.0**, reach_area_gain 1,991,051 u².

Shared §2 density audit: failing tiles **285 → 271**, urban compliant **19 → 33** of 92, rendered masses
2,037 → 2,213, greens 412 → 456; sparse 45, mountain 45 and remote 1 unchanged. Nineteen tiles moved
FAIL → PASS, including three named targets (Stoneshore Old Quarter, Vandel Port Old Quarter, Vandel Port).

### The load-bearing split — Stoneshore succeeded, Vandel only half did

Component level, measured this run:

| component | envelope | built area | **built_pct** |
|---|---|---|---|
| `settlement\|tile_4_10` Stoneshore | 342,192 → 485,777 | 95,599 → 144,561 | 27.94 → **29.76** |
| `settlement\|tile_21_17` Vandel main | 311,663 → 495,760 | 82,262 → 108,520 | 26.39 → **21.89** |
| `settlement\|tile_23_18` Vandel Island | 72,369 → 272,581 | 2,784 → 5,969 | 3.85 → **2.19** |

**Stoneshore got bigger *and* denser** — the extent grew 42% and the fabric grew 51%, so built share rose. That
is the addendum §4 result, and the critic saw it independently.

**Vandel got bigger and thinner.** The extent grew 59% while the fabric grew only 32%; on Vandel Island the
envelope nearly quadrupled while built share fell to 2.19%. The critic named the same tile as the one place v0
is better — the candidate's Vandel Port Works is *"a chain of four parallel bars on green"* against v0's
contiguous L-plus-bar compound — and the §2 audit confirms it numerically: `tile_23_16` small 21 → 14, large
4 → 2, **gaining** a `large_below_floor` failure; `tile_21_17` small 12 → 8, **gaining** a `small_below_floor`
failure. The owner's clause *"Vandel must read as a port that presses against both the lake and the sea"* is
therefore **only partially delivered**: it presses outward, but the new ground is not yet inhabited.

The intensity floor is what separates the two. Where a coastal bearing lands on an already-dense component
(Stoneshore) it converts new envelope into frontage; where it lands on a thin one (Vandel Island, 3.85% built)
there is not enough fabric for the floor to work on, and the reach just enlarges an empty field.

### Regressions — reported, not softened

None is in the invariant list, but all are measured worsenings of district-field diagnostics.

1. `local_hex_failure_count` / `hex_boundary_failure_count` **13 → 24**. Where the reach pushes fabric to a hex
   edge whose neighbour is a forbidden sea/mountain hex, `_forbidden_settlement_tile_exclusions` clips along
   that hex line and the boundary traces it. Gate B is not reopened by the addendum, but this doubles its
   failure count. The narrow frontage cell already cut it from 16 new tiles to 11; removing it entirely needs a
   standoff wider than the frontage cell's own depth, which reinstates the collar.
2. `dense_core_failure_count` **0 → 1** (`tile_25_6` Gold Arm Old Quarter, 4 core masses / 19% against the town
   floor of 6 / 25%). **Not a coastal defect.** The parcel role ballot is keyed by INDEX
   (`component|parcel|N`), so adding parcels anywhere in a component shifts every downstream key and re-rolls
   the whole component's roles. **Any stream that adds parcels will hit this.** A geometric parcel key fixes it
   structurally but re-rolls the entire map once.
3. `whole_body_gate` failing components **20 → 22** (`settlement|tile_14_17`, `settlement|tile_3_3` newly
   failing; none newly passing). Both named components still clear their floors. This is the honest cost of
   growing the extent while roads stay frozen — new land has no streets, so masses on it cannot have frontage.
4. §2 verdicts: 19 tiles FAIL → PASS against **5** PASS → FAIL (`tile_15_2`, `tile_5_14`, `tile_20_12`,
   `tile_3_14`, `tile_4_15`), and **16** still-failing tiles gained a new failure reason. Net strongly positive
   (285 → 271 failing) but not monotone — the index-keyed re-roll of item 2 is the mechanism.
5. `gradient_failure_count` **7 → 6** and `density_direction_failure_count` **7 → 6** — the standing open G1.02
   gradient gate *improved*.

### Cross-stream contention — the parks stream's baseline has moved

Summed over the §2 audit table, rendered park **area** rose **734,399 → 982,612 u² (+33.8%)** and counted park
count 150 → 182 (fabric-level parks 361 → 415, audit greens 412 → 456), because parks scale with envelope area
and this pass grew the envelope by ~2M u². Addendum §3 asks the parks stream to halve park area in the four
largest cities to ±10%. **That must be measured against the integrated fabric, not against v0**, or the two
changes cancel or overshoot.

### Environment finding — the frozen legacy hashes need an explicit resolution

`map_style_shot` derives the wide zoom from the **live window size**. Without `--resolution 1920x1080` the
frozen legacy hashes do **not** reproduce: a default 2360x1328 run yields classic `749c72fb…`, ink `82cdd1f0…`,
plate `d3989f0e…` and reads as a false legacy regression. This is the same defect M1 diagnosed as a machine
change; the actual fix is the flag. Re-run at 1920x1080 and all three frozen hashes reproduce exactly. The
morphology harness `_wide_shot` has the identical defect, so `poe_morph_wide.png` is **not** framing-stable
across machines and is unusable for blind A/B — use the fixed-zoom slices.

### Independent verification (re-run in full, not inherited)

- Unit suite: **`==== 2287 passed, 0 failed ====`** (real summary line).
- e2e balance sim, `res://tests/e2e_stoneshore.tscn -- 100`: **`==== E2E 748 passed, 0 failed ====`**.
- Two windowed morphology capture runs under the shared lock: `diff -r --brief` clean across all **24**
  artifacts. The harness exits 1 on the unresolved G1.02 gradient gate, as designed.
- All-style harness at `--resolution 1920x1080`: classic `c263cf65…`, ink `95ba0e42…`, plate `3a98e939…` — all
  three reproduce the **frozen** hashes exactly. `legacy_before == legacy_roundtrip == ink`;
  `midcentury_wide == midcentury_repeat` (`6aba3598…`). Of the 43 artifacts, **35 are byte-identical to the v0
  archive and exactly the 8 midcentury ones differ.**
- Road-frontage audit frozen on all eight counters: 177 road tiles, 413 buildings, 79 failing tiles, 177 over
  15u, 137 off-road-by-design, 1 service-lane save, 165 block-mode failures without streets, 146.6u `tile_10_3`
  furnace worst case. Log diff against the v0 archive shows only per-run planner timing and the worktree path.
- Seven W1.01 water counters **ZERO** on both SettlementPlan cities; `dry_land_guard.water_overlap_count` 0.
- Four relief counters **ZERO** on every settlement component and both plans.
- Untouched control proven: Arin hero `built_pct` 38.2880881497716, envelope 1678971.39156318, 151 parcels, 25
  street faces, and Capital / Silkstown `built_pct` 45.6912685084547 / 34.4911877897598 — all **bit-identical**
  to v0.
- `git diff --check` clean; `git status --porcelain` empty.
- **Blind-pair provenance verified by hash**: all three staged candidate images are byte-identical to this
  verification run's own captures, so the critic judged exactly this HEAD.

**Evidence** `/tmp/poe_g3_coast_verify/` (unit, e2e, frontage, density audit, `morphA`/`morphB`, `mapstyle`) ·
blind pair `/tmp/poe_g3_blind/COAST/` · v0 archive `/tmp/poe_g2_baseline/v0`.

### Next bottleneck

**Frozen roads are now the binding constraint on the coast.** The reach can deliver envelope but not streets,
and the fabric only densifies where a component already had enough mass for the intensity floor to bite — which
is why Stoneshore's built share rose and Vandel's fell. Growing extent further without streets will keep
trading built share for area. The next lever is therefore *not* more reach; it is either
(a) **shore-parallel decorative frontage streets** on the new waterfront, so the reached ground has faces to
build against, or (b) a **built-share floor on the reach itself** — refuse to grow a bearing whose component
built share would fall below its pre-reach value, which would have declined Vandel Island outright.

Two prerequisites for anyone who touches this next: the **geometric parcel key** (item 2 above), without which
every parcel-adding change keeps re-rolling unrelated components; and a **hex-edge standoff** that does not
reinstate the collar (item 1).

## N1. Straight port arms and real water between them — 2026-08-14

Addendum section 5, on branch `gauntlet3/ports` (worktree `/tmp/poe_g3_wt/ports`), based on
`gauntlet3/density-audit`. Only the mid-century port plan, its rendering/diagnostic seam and its focused
audit changed. Settlement density, parks, coastal reach, relief, roads, rivers and the legacy renderers were
not reopened.

### The diagnosis — the gate was measuring the wrong region

L1 recorded **100% sampled basin water** and **0 opaque basin overlap** for all four ports, and both numbers
reproduce exactly on this branch: `basin_sea_water_coverage = 1.0000` everywhere. The owner is nevertheless
right. The reason is neither a rendering divergence nor a stale metric — it is that **`basin_polygon` is not
the region a viewer reads as "between the arms."**

L1 built the basin as a trapezoid rooted 10u *seaward* of a sampled shore point and then required it to be
sea. It is water by construction. The arms, however, were rooted on `head_front`, which sits 8–17u *landward*
of that same shore point, and they splayed outward around the basin. The U that the eye sees is therefore
bounded by the arms, is strictly larger than the basin, and its landward strip — the harbour throat — was
never sampled by anything.

The three candidate explanations in the addendum resolve as: **(a) yes, (b) yes, (c) no.**

- **(c) is refuted by measurement.** `tools/port_land_probe.gd` samples every NavGrid cell within 60u of the
  water boundary — 789,496 cells — and compares the NavGrid water class against containment in the baked
  band-5 "land base" polygon whose boundary `hill_visuals` strokes as the coastline. **Agreement 99.470%**,
  and the 0.53% disagreement is a half-cell quantisation band skewed 20:1 toward NavGrid-sea/render-land.
  The audit and the picture are looking at the same world.
- **(a) and (b) are both true and are the same defect seen from two sides.** The apron/head fill stops at
  `head_front`, so the throat is bare terrain; and because the arms start there, they run over that terrain
  before reaching water — L1's own 29.53% sea-deck figure for Arin's right arm was the visible symptom.

Made testable: `MidcenturyPortPlan` now emits `interarm_open_area`, `interarm_sea_area`,
`interarm_sea_coverage` and `max_arm_bend_deg`. The enclosure is the closed ring through both arm centrelines
with every opaque port element subtracted, sampled on a 4u lattice; the diagnostic overlay draws that ring in
green. Measured on the L1 geometry, plan hashes unchanged (`3679035c`, `15f74d8b`, `47c0d8df`, `aa0b424d`):

| Port | basin sea | **enclosure sea** | **land inside the U** | **max arm bend** |
|---|---:|---:|---:|---:|
| Stoneshore `tile_5_10` | 100.00% | 90.36% | 1,072u² | 19.57° |
| Arin `tile_11_17` | 100.00% | 84.94% | 1,296u² | 21.93° |
| Capital `tile_24_7` | 100.00% | 82.92% | 1,536u² | 18.66° |
| Vandel `tile_22_16` | 100.00% | 83.28% | 864u² | 27.24° |

**A gate that passed while the defect was visible is the finding.** L1 proved a property of a polygon it had
constructed to have that property. Nothing checked the geometry the viewer actually sees.

### N1.01 — rejected: straight quay face at the waterline

Attempt 1 collapsed the throat to zero by putting `head_front` on the sampled shore and rooting the basin
there, so the head's straight front edge and the basin's root edge were one shared line. Arms became single
straight segments lying on the basin's two edges.

**0 of 4 ports.** Of 1,944 candidates per port, the basin gate passed 21–39% and then the dry-land head gate
rejected every survivor. A straight quay face requires 100–135u of straight coastline with sea on one side
and land on the other at 12u lattice resolution; no site on this map offers it. Recorded as a dead end: a
straight head front cannot both reach the water and stay dry.

### N1.02 — accepted: coast-clipped apron, straight quays, gated enclosure

The head stops being a rectangle placed near the shore and becomes a block **overshooting the quay face by
10–34u and clipped back to the rendered coastline**, so its seaward edge *is* the shore and the apron covers
every scrap of land in the throat. The clip is then eroded along `HEAD_INSET_LADDER` until the **unchanged**
NavGrid dry-land gate reads 100%; the ladder pays for the 0.53% classification disagreement and no more.

Arms are single straight runs. Each lies on one edge of an **asymmetric** basin trapezoid (independent left
and right flare, 0.80–1.20× the mouth half-width), so the two arms leave the quay face at different angles,
with independent length and width. Each arm then marches backwards **along its own axis** until it bites into
the apron, which attaches it without introducing a vertex. `max_arm_bend_deg` is 0.00 by construction, and
the K1 fixed rectangle-and-shore-normal primitive stays retired — the search is still over real local
coastline samples and every port ends up a different shape.

| Port | enclosure sea | land inside the U | arm bend | L/R arm sea-deck | L/R arm length |
|---|---:|---:|---:|---:|---:|
| Stoneshore | 90.36% → **96.57%** | 1,072 → **416u²** | 19.57° → **0.00°** | 87→86% / 89→88% | 122 / 151 |
| Arin | 84.94% → **95.33%** | 1,296 → **624u²** | 21.93° → **0.00°** | 100→90% / **30→73%** | 187 / 126 |
| Capital | 82.92% → **95.08%** | 1,536 → **672u²** | 18.66° → **0.00°** | 71→92% / 78→88% | 178 / 139 |
| Vandel | 83.28% → **95.34%** | 864 → **640u²** | 27.24° → **0.00°** | 91→87% / 74→68% | 202 / 141 |

Mean enclosure water 85.38% → 95.58%; total visible land inside the four Us 4,768u² → 2,352u² (−51%);
every arm dead straight; Arin's land-rooted right quay more than doubles its sea-deck fraction.

**The residual is honest and understood.** The remaining 3.4–4.9% is a 6–10u strip of foreshore between the
apron and the water: the erosion the NavGrid dry-land gate demands. Drawing the apron out to the coastline
would close it, at the price of putting the drawn geometry outside the instrument that certifies it dry. The
gate was kept; the strip is the cost. `interarm_sea_coverage` is gated at **0.94**, below the measured floor
of 0.9508, with that reasoning written at the gate.

Retained and re-verified: 4/4 valid plans, exactly two cranes per port one per arm, valid authoritative-road
access at every site, 12–19 cargo groups, zero river/channel obstruction, zero gameplay overlap, zero
decorative/park overlap, zero opaque basin overlap, 100% dry landward head, and eight marine reservations.

### Cost

Planner time rose from L1's 88–238ms per port to 804–2,564ms (0.61s → 4.86s for all four), because the
enclosure requirement needs a wider search (864 candidates, up from 432) and the apron clip is polygon work
against the coastline. Road access was moved to the end of the candidate pipeline, where it only runs on
candidates nothing else rejected. An exact branch-and-bound prune on the score was implemented and measured
**useless** (`pruned=0` at every port — the incumbent is found late and the bound is loose); it is left in
because it is free and correct. The remaining lever, not taken here, is to build the plan lazily on the first
switch into mid-century instead of during every map build in every style.

### N1 verification — what was run, and what it returned

- **Unit suite: 2,298 passed / 0 failed**, with a real summary line (v0 baseline 2,287 plus exactly the 11
  new port-geometry asserts). A fresh worktree exits 0 with no summary at all, so the line was checked.
- **Two byte-identical capture runs.** All nine port artifacts (4 normal, 4 diagnostic, 1 context) share
  SHA-256s across two independent runs; plan hashes reproduce across five separate processes (both gauntlet
  runs, the density audit, the morphology harness and the all-style harness):
  `f3242f47` Stoneshore, `4aae1d4d` Arin, `d88be546` Capital, `aa2ff032` Vandel.
- **All-style harness exit 0**, which is the harness asserting, in-memory: legacy→mid-century→legacy is
  full-PNG identical, the masked map-layer round trip is pixel exact, and mid-century wide equals
  mid-century repeat. Run without the capture lock because of concurrent-stream contention, so the PNGs on
  disk may have been overwritten by another stream — the verdicts are this process's own image comparisons
  and are unaffected.
- **Road-frontage audit byte-identical to the v0 archive**, all eight counters: 177 road tiles, 413
  buildings, 79 failing tiles, 177 over 15u, 137 off-road-by-design, 1 service-lane save, 165 block-mode
  failures without streets, 146.6u worst furnace on `tile_10_3`. This is also the evidence that no gameplay
  building moved, despite the marine reservation changing shape.
- **Morphology harness: all seven W1.01 water counters ZERO and all relief counters ZERO** on both plans;
  `dry_land_guard.water_overlap_count` zero; `rural_growth` and `suburban` relief overlap zero. Exit 1, as
  designed, on the unresolved G1.02 road-gradient gate. Against the frozen v0 metrics record, **10 of 26,171
  leaf metrics differ**, and all ten are the port envelope changing shape:
  `gameplay_collision_guard` removes 623 decorative polygons instead of 635, `far_zoom_plate.mass_count`
  2,037 → 2,042, and 8 `tile_22_16` accommodation candidates move between the `extra` and `gameplay`
  rejection reasons. Every settlement-plan, water, relief and district-field counter is unchanged.
- **Density audit: zero verdict changes.** The class compliance table is identical (mountain 45/45, remote
  1/54, sparse 45/204, urban 19/92) and every per-tile PASS/FAIL verdict and reason list is unchanged.
  Four counts moved, all on port tiles and all in the fabric's favour: `tile_24_7` small 13→17 and large
  1→2, `tile_12_17` large 12→13, `tile_22_16` large 5→4. `docs/map-density-audit-baseline.txt` is therefore
  stale by four numbers on three tiles; the compliance conclusion it supports is not.
- `git diff --check` clean; working tree clean.

### N1.02 acceptance — independent verification and the blind result

Re-run in full by the closing agent in the same worktree; nothing below is inherited from the implementing
agent's report.

**Blind chain of custody.** `/tmp/poe_g3_blind/PORTS/*/image_1.png` hashes equal the v0 control captures and
`image_2.png` equal the candidate `run1` captures at all four sites, and the candidate images are SHA-256
identical to this agent's own fresh capture — so the geometry the critic scored is the geometry in the tree.
The critic, rendered blind, chose **image_2, the candidate**, 3.33 vs 2.75, with no category regressing. Its
decisive observation was the deletion of the octagonal hub disc welded into every L1 arm (8 identical
instances, 2 per port) — a UI-looking glyph with no cartographic referent — replaced by a readable slip
between two finger piers at all four sites.

**Legacy proof strengthened.** The implementing agent could not run the all-style harness under the capture
lock and did not run a base-commit control, so its legacy evidence rested on in-process assertions alone. A
control capture at the stream base `781bc519` was taken here under the lock and compared file by file:
**all 10 classic, 10 ink and 10 plate frames are byte-identical to the base commit**, as are
`wide_legacy_before`, `wide_legacy_roundtrip` and the three mid-century framings with no port in view.
Exactly 8 frames differ, every one of them a mid-century framing containing a port. `legacy_before ==
legacy_roundtrip == wide_ink` holds full-PNG, and `midcentury == midcentury_repeat` holds.

**Everything else re-measured green:** unit suite 2,298 / 0 with a real summary line, against 2,287 / 0 at
the base commit — the delta is exactly the 11 new port asserts; two byte-identical port capture runs, all
nine artifacts, `valid=4/4 failures=[]`, plan hashes `f3242f47` / `4aae1d4d` / `d88be546` / `aa2ff032`;
road-frontage audit `diff`-empty against the v0 archive on all eight counters; all 154 water-overlap and 80
relief-overlap leaves zero, with exactly 10 of 26,171 morphology leaves differing and all ten being the
documented decorative-envelope side effect; density audit with zero verdict changes; e2e balance sim 748 / 0;
`git diff --check` clean.

**Why this is accepted PARTIAL.** Addendum §5 has two halves. Arm straightness is fully satisfied — 0.00° at
every port, zero by construction. "The water between the arms must be water" is *improved but not satisfied*:
land remains inside the U at all four ports (416 / 624 / 672 / 640u², 95.08–96.57% sea). The critic
independently saw the residue, noting Arin's right arm "runs ALONG the beach ... sitting roughly half on
sand." The mechanism is accepted because it wins blind, meets half the gate outright and halves the defect on
the other half — not because the owner's complaint is closed. It is not.

## INT-G3. Integration of the gauntlet-3 density pass — 2026-08-14

Branch `gauntlet3/integrated`, cut from `gauntlet3/density-audit` (781bc519) so the shared audit
instrument is always present. **Not merged into `decorative-buildings-and-city-look`** — that is the
owner's call.

### What was merged, and what was not

| stream | branch | verified HEAD | reported | merged? |
|---|---|---|---|---|
| §2 building-count minimums | `gauntlet3/density` | 724ad445 | rejected_reverted | **No** — postmortem only (§M2) |
| §3 park halving | `gauntlet3/parks` | a4ca51a5 | rejected_reverted | **No** — postmortem only (§M3) |
| §4 coastal reach | `gauntlet3/coast` | b7447d0b | accepted_partial | **Yes** |
| §5 port arm geometry | `gauntlet3/ports` | 0b791e72 | accepted_partial | **Yes** |

Every claimed commit exists and every branch's net diff matches its stream report. `density` and
`parks` net-change **only** `reports/map_visual_gauntlet.md` against the audit base — their reverts
are real, with zero source residue. The merged tree's source diff vs 781bc519 is exactly the union
of the two accepted streams, file for file:
`midcentury_port_plan.gd`, `port_visuals.gd`, `test_runner.gd`, `midcentury_port_gauntlet.gd`,
`port_land_probe.gd` (ports) and `urban_fabric_visuals.gd`, `settlement_morphology_shot.gd` (coast).
No source file is touched by both streams, so the only merge conflict was the report.

**Report conflict resolved by keeping every iteration entry**, in addendum order M1 → M2 → M3 → M4 →
N1. The density and ports streams had both numbered themselves `N1`; the density stream is
renumbered **M2** (its free chronological slot, `N1.01/N1.02` → `M2.01/M2.02`), wording otherwise
untouched.

### Headline — addendum §2 compliance on the MERGED result

Regenerated by `res://tools/density_audit.tscn` on this tree (exit 2, undocumented misses remain).

| class | tiles | compliant | % | failing | failure histogram |
|---|---|---|---|---|---|
| urban | 92 | **32** (was 19) | 34.8% | 60 | green_below_floor 46, large_below_floor 34, small_below_floor 32 |
| sparse | 204 | 45 (was 45) | 22.1% | 159 | small_below_floor 153, large_above_cap 7, small_above_cap 3 |
| mountain | 45 | 45 | 100.0% | 0 | — |
| remote | 54 | 1 (was 1) | 1.9% | 53 | small_below_floor 53 |
| **TOTAL** | **395** | **123** (was 110) | **31.1%** (was 27.8%) | **272** (was 285) | 272 undocumented, 0 documented |

Rendered masses 2037 → **2216**, greens 412 → **454**. All of the gain is urban and coastal; sparse,
mountain and remote are **untouched**, because the only stream aimed at them was rejected.

### The one combination effect, isolated and attributed

Coast alone measures urban **33**/92 and 271 failing. Merged measures urban **32**/92 and 272. The
entire difference is a single tile:

```
tile_5_10  Stoneshore Docks  coast-only 14/10/2 PASS  ->  merged 13/9/1 FAIL ["green_below_floor"]
                             park_area 2470 -> 1961
```

The ports stream's new coast-clipped apron at Stoneshore harbour displaces one green, one small and
one large mass on a tile that the coastal reach had just lifted to *exactly* the `>=2` green floor,
so it falls back through it. Ports changed counts on three other tiles (tile_12_17 large 12→13,
tile_22_16 small 12→11, tile_24_7 13/1→17/2) with no verdict change. Net merged is still 13 tiles
better than baseline. **Not a blocking failure** — the §2 gate already fails map-wide at baseline —
but it is an owner-named tile and it is the first item for the next pass.

### Full invariant suite — run on the MERGED result, all green

| invariant | result |
|---|---|
| unit suite | `==== 2298 passed, 0 failed ====` (real summary line; 2287 base + 11 port asserts) |
| e2e balance sim | `==== E2E 748 passed, 0 failed ====` |
| two capture runs, morphology | 23/23 artifacts byte-identical A vs B |
| two capture runs, port gauntlet | 9/9 PNGs byte-identical; `valid=4/4 failures=[]` both runs. Only `planner_msec` (wall-clock diagnostic) differs — every geometric leaf identical |
| classic wide | `c263cf6595b45e480d037c94c91c8c1b8f14f1b2423fd4521b7740b45ca9045a` ✓ exact |
| ink wide | `95ba0e42c96d24f4ad2ab8117bece6fa0aa5b1ba1b2a4f3601beca5244bcb775` ✓ exact |
| plate wide | `3a98e9399c83d36ea10c370769a334bcbd0c13704c9a3d94410f72877a94ddf6` ✓ exact |
| legacy round trip | `legacy_before == legacy_roundtrip == ink`, all `95ba0e42…`; both harness assertions printed |
| mid-century determinism | `wide_midcentury == wide_midcentury_repeat` (`e482704d…`) |
| all-style archive | 34 of 43 byte-identical to v0; the 9 differing are **all** mid-century framings. No legacy style moved |
| road-frontage audit | CONTENT-IDENTICAL to the v0 log. Eight counters frozen: 177 road tiles, 413 buildings, 79 failing tiles, 177 over 15u, 137 off-road-by-design, 1 service-lane save, 165 block-mode failures, 146.6u tile_10_3 furnace. Only the ports planner lines and the worktree path differ |
| seven W1.01 water counters | **ZERO** — and all 154 `water_overlap`-family leaves zero; `dry_land_guard.water_overlap_count` 0 |
| relief counters | all 119 relief overlap/disconnected leaves **ZERO** |
| gameplay collision | `opaque_overlap_count` 0 over 413 footprints |
| `git diff --check` | clean; working tree clean |

Morphology harness exits 1 by design (unresolved G1.02 gradient gate); untouched.

### Addendum §5 on the merged tree — regenerated

All four ports: `max_arm_bend_deg` **0.00** (straight by construction), `basin_sea_water_coverage`
1.0000, `landward_dry_land_coverage` 1.0000, 2 cranes, `road_access_valid` true, zero basin opaque
overlap, zero decorative collisions over 413 sanitized footprints. `interarm_sea_coverage`
96.57 / 95.33 / 95.08 / 95.34% — residual inter-arm land **2,352u²** (416/624/672/640), i.e. the
owner's "land between the arms" is **halved, not closed**. Plan hashes reproduce the ports stream's
exactly (`f3242f47`, `4aae1d4d`, `d88be546`, `aa2ff032`), so the coastal merge did not perturb them.

### Addendum §4 on the merged tree — regenerated

Stoneshore `tile_4_10` envelope 342,192 → **485,777**, built_pct 27.94 → **29.76** (bigger *and*
denser). Vandel main `tile_21_17` envelope +59% but built_pct 26.39 → **21.89**; Vandel Island
`tile_23_18` built_pct 3.85 → **2.19**. Coast's regressions reproduce unchanged on the merged tree:
`hex_boundary`/`local_hex_failure_count` 13 → 24, `dense_core_failure_count` 0 → 1,
`whole_body_gate` failing components 20 → 22; `gradient_failure_count` improved 7 → 6. None is in
the frozen-invariant list.

### Addendum §3 — NOT DELIVERED

The park-halving stream is reverted, so Capital's centre-east green wedge is unchanged. A
before/after crop of the max-zoom-out wide capture over the Capital component is at
`reports/map_visual_gauntlet/integrated_g3/owner_3b_capital_centre_east_BEFORE_top_AFTER_bottom.png`:
the only visible difference in that region is the port quays. 46 urban tiles are still below the
`>=2` green floor — it remains the single largest §2 defect, exactly as at baseline.

### Owner comparison plates

`reports/map_visual_gauntlet/integrated_g3/` (gitignored, durable):
`owner_1_stoneshore_coastal_town.png`, `owner_2_vandel_port.png`, `owner_3_capital_wide_zoom.png`
(+ `_V0_BEFORE`), `owner_3b_capital_centre_east_BEFORE_top_AFTER_bottom.png`,
`owner_4_arin_river_city.png`, plus `extra_*` framings and `density_audit_MERGED.txt`.

### What is still not fixed

1. **Sparse, remote and mountain tiles are exactly at baseline.** 159 sparse and 53 remote tiles
   still miss the floor; 134 of the empty sparse tiles have zero decorative buildings and all 74
   sparse *hill* tiles are untouched by the rural-growth pass by construction. Remote needs a new
   mechanism (rural growth requires a built road; remote is roadless by definition).
2. **Capital is still split by its parks** (§3 undelivered).
3. **Vandel is bigger but thinner** — it gained envelope, not fabric, because roads are frozen and
   new ground has no frontage to build against.
4. **Residual land between the port arms** — 2,352u², bounded by the 12u NavGrid lattice.
5. `tile_5_10` Stoneshore Docks regressed to `green_below_floor` from the ports/coast interaction.

Attempt budget: §2 and §3 have each used **1 of 2** attempts. The next levers are recorded at the
end of §M2, §M3, §M4 and §N1 respectively and are not repeated here.

## N2. Seaward port reposition — only sea between the arms — 2026-08-15

> **OUTCOME: REJECTED AND REVERTED — see N2.02 at the end of this section.** N2.01 met the numeric
> gate (100% at all four ports) and lost the blind comparison to the base tree, 2.67 vs 3.58. The
> source is reverted to `dab04e87`; the N1.02 geometry stands. Everything between here and N2.02 is
> the implementing agent's measurement record, retained because it is accurate and because the
> postmortem depends on it — **not** because the mechanism was accepted.

Addendum **section 5a**, on branch `gauntlet5/port` (worktree `/tmp/poe_g5_wt/port`), based on
`dab04e87` (INT-G3, the merged coast+ports tree). Only the mid-century port plan, its rendering
seam, its focused audit and its unit asserts changed. Settlement density, parks, coastal reach,
relief, roads, rivers and the legacy renderers were not reopened.

N1 delivered straight arms (0.00°) but left **2,352u² of land inside the four Us** (95.08–96.57%
sea) and gated the coverage at 0.94 rather than draw the apron outside the NavGrid instrument that
certifies it dry. The owner ruled: *"close it by moving the port further out if needed. Port is
allowed to sit on up to +10/-10 degrees from perfect orientation on the shore as long as the main
body touches the shore at least 75% on the shore-side and there is only sea between the arms."*

### N2.01 — accepted: measured shore normal, measured seaward push, quay deck

Three changes, all inside the existing bounded coastline search. The K1 fixed
rectangle-and-shore-normal primitive stays retired; every port is still fitted to its own coast.

1. **"Perfect orientation" is measured before the tolerance is applied to it.** A single NavGrid
   cell's 8-neighbour landward gradient on a 12u lattice quantises into roughly 22° buckets, so
   L1/N1's ±22° window was mostly paying for lattice noise. Each coastline sample's normal is now
   the mean seaward direction of every coastal cell within 58u of it, and the search offsets that
   smoothed normal by **±10° only** (`APPROACH_ANGLES_DEG = [-10, -3.4, 3.4, 10]`). Narrowing the
   window *without* the smoothed normal loses Vandel outright.
2. **The quay line is placed past the last land in the throat, measured.** `_land_clearance` marches
   13 transverse rays (spacing below one NavGrid step) seaward from the shore sample until no cell
   in the throat is non-sea, and the quay line goes one full NavGrid step beyond that, plus one of
   three small extras. The basin and both arm roots start there. Measured push: **24 / 18 / 24 / 56u**
   at Stoneshore / Arin / Capital / Vandel. The score subtracts `1.35 × quay_shift`, so the search
   prefers the least push that clears the throat — "further out **if needed**".
3. **A wharf carries the compound from the dry apron out to that line.** It is a marine quay deck in
   the same family as the arm decks (drawn in the same deck colour, under the apron), tapering from
   the full apron width at the land to just enough at the quay line to carry both arm roots, and
   **clipped back around any authoritative river or channel** it would otherwise reach across.

**The NavGrid dry-land gate is untouched.** `_fit_head` still clips to the rendered coastline, still
erodes along `HEAD_INSET_LADDER`, and still requires `_class_coverage(head, WATER_LAND) >= 0.999`.
The diff contains no change to any dry-land threshold. The apron's minimum-area gate was in fact
made *stricter*: it is now judged against the landward reference block rooted on the shore, so
pushing the quay line further out cannot make that gate progressively easier to pass.

The enclosure gate moved **inside** the candidate loop (`_ring_has_uncovered_land`, early-exit on the
first uncovered lattice point) and shares its lattice and water lookup with the reported
`interarm_sea_coverage`, so the gate and the number cannot disagree.

### The four-port audit — `valid=4/4 failures=[]`

| Port / tile | interarm sea | land in the U | arm bend | shore contact | orientation off | quay push | wharf over sea | valid |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Stoneshore `tile_5_10` | **100.00%** | **0u²** | 0.00° | 100.0% | 3.4° | 24.0u | 46.5% | yes |
| Arin `tile_11_17` | **100.00%** | **0u²** | 0.00° | 100.0% | 10.0° | 18.0u | 62.5% | yes |
| Capital `tile_24_7` | **100.00%** | **0u²** | 0.00° | 100.0% | 3.4° | 24.0u | 50.0% | yes |
| Vandel `tile_22_16` | **100.00%** | **0u²** | 0.00° | 100.0% | 10.0° | 56.0u | 64.3% | yes |

Same-session control captured from the base commit reproduces N1 exactly — 96.57 / 95.33 / 95.08 /
95.34% and 416 / 624 / 672 / 640u², total **2,352u² → 0u²**. Retained and re-verified on the
candidate: 100% sea basins, 100% open-water corridors, 100% dry landward aprons, zero river/channel
overlap, zero opaque basin overlap, zero gameplay overlap, zero decorative/park overlap, exactly two
cranes per port one per arm, valid authoritative-road access at all four, 21–25 cargo groups, and
eight marine reservations. Arin's land-rooted right quay, the weakest transition in L1 (29.53% sea
deck) and N1 (73%), now reads **88%**; the other seven arm decks are 100%.

The gate is at **1.0** with no threshold left to tune, and it fails the run on land *or* on a body
that has floated off the shore (`shore_contact_coverage < 0.75`) *or* on an orientation past ±10°.

### Two things to be honest about

**The shore-contact gate cannot bind as the plan is currently built.** It measures the right thing —
48 rays landward across exactly the body's shore-side edge width, counting a ray when the body
stands on dry land along it — but the apron is already required to be 100% dry land across that full
width, so the answer is 1.00 at every port by construction. It is a guard against a future change,
not an active constraint, and it is reported as 100% because it is 100%, not because it was tuned.

**`interarm_sea_coverage` counts port-covered lattice points as not open** — that semantic is
inherited unchanged from N1, where it was introduced. So "zero land inside the U" means *zero bare
land visible inside the U*: the foreshore strip the NavGrid erosion leaves is now under the port's
own quay deck rather than exposed. The wharf is 46.5–64.3% over sea; the rest of it is the 16u
landward bite that overlaps the dry apron, plus that foreshore. This is what "move the port out" is
made of — a quay wall standing out over the foreshore into the water — and it is the reading under
which the arms leave from water and the basin is water from the quay line outward. A reader who
wanted "the whole U is over deep water" should know the metric does not assert that.

### The Stoneshore green — checked, NOT freed

INT-G3 recorded that the ports stream's apron displaced a green at `tile_5_10` that the coastal
stream had just lifted to exactly the `>=2` floor, flipping the tile to `green_below_floor`. Moving
the port seaward **does not free it**:

```
tile_5_10  base dab04e87  13 / 9 / 1  park_area 1961  FAIL ["green_below_floor"]
tile_5_10  candidate      13 / 11 / 1  park_area 1961  FAIL ["green_below_floor"]
```

Park count and park area are *identical*, not merely still-failing: the same single green survives
at the same area on both trees. The green is therefore not sensitive to where the quay line sits,
and the seaward move is not the lever that would recover it. (It could not be: the apron's dry depth
is now measured from the shoreline rather than from the quay line, so the landward footprint grew by
the push rather than shrinking — and even so the greens did not move.) Reducing that landward depth
is the untried lever; it was not taken, because the four hard gates are green and §2 fails map-wide
at baseline anyway, so it is not worth risking a 4/4 run.

### N2 verification — what was run, and what it returned

- **Unit suite: 2,306 passed / 0 failed**, with a real `==== N passed, M failed ====` summary line.
  Base is 2,298; the delta is exactly the 8 new port asserts. All 19 port-geometry asserts pass.
- **Port gauntlet `valid=4/4 failures=[]`, `hard_gate_passes: true`**, headless and windowed.
- **Two byte-identical windowed capture runs**: all nine artifacts (4 normal, 4 diagnostic, 1
  context) SHA-256 identical, and the two metrics JSONs identical field-for-field once `planner_msec`
  is excluded.
- **Determinism across five processes** — headless gauntlet, density audit, two windowed gauntlets
  and the morphology harness — identical plan hashes `4e71ef49` Stoneshore, `150be3dc` Arin,
  `09f87238` Capital, `19c034e1` Vandel.
- **Density audit: zero verdict changes.** Class compliance identical (mountain 45/45, remote 1/54,
  sparse 45/204, urban 32/92; 395 audited, 272 failing). Five of 395 rows differ, every one a port
  tile: `tile_5_10` large 9→11, `tile_11_17` small 10→11, `tile_12_17` large 13→12, `tile_22_16`
  small 11→12 and park_area 12,637→18,970, `tile_24_7` small 17→16. Rendered masses/greens
  2,216/454 → 2,218/455.
- **Road-frontage audit byte-identical** to the durable base record on every counter and every
  worst-offender line: 177 road tiles, 413 buildings, 79 failing tiles, 177 over 15u, 137
  off-road-by-design, 1 service-lane save, 165 block-mode failures without streets, 146.6u worst
  furnace on `tile_10_3`. No gameplay building moved.
- **All-style harness exit 0 on both trees**, and compared frame by frame against a same-session
  base-commit control: **35 of 43 frames byte-identical**, including all 10 classic, all 10 ink and
  all 10 plate frames, `wide_legacy_before`, `wide_legacy_roundtrip`, and the three mid-century
  framings with no port in view. The 8 that differ are all mid-century framings containing a port.
  In-process: `legacy_before == legacy_roundtrip == wide_ink` and `midcentury == midcentury_repeat`,
  full-PNG.
- **Morphology harness: 154 water-overlap leaves, 150 `water_overlap_count` leaves and 41
  relief-overlap leaves all ZERO.** Exit 1, as designed, on the unresolved G1.02 dense-core gate.
- `git diff --check` clean.
- **Blind pair staged** at `/tmp/poe_g5_blind/PORT/{stoneshore,arin,capital,vandel}/`, one framing
  per subdirectory, same slot assignment throughout.

### N2.02 — REJECTED: the gate was met and the map got worse

Closed by the reviewing agent in the same worktree. Nothing below is inherited from the implementing
agent's report; the blind key was re-derived from the artifacts before it was trusted.

**Blind chain of custody, re-derived by hash.** The blind pair is 960x540, and so are the harness
captures, so the slots resolve by SHA-256 with no resampling. In all four subdirectories
`image_2.png` is byte-identical to the base-commit control capture (`base_ports/`), whose plan
hashes are exactly N1's recorded `f3242f47` / `4aae1d4d` / `d88be546` / `aa2ff032` — so image 2 is
provably the accepted N1.02 geometry. `image_1.png` is byte-identical to the final candidate capture
(plan hashes `4e71ef49` / `150be3dc` / `09f87238` / `19c034e1`, `valid=4/4 failures=[]`), and that
capture is itself byte-identical to an independent later re-run of the same tree — so image 1 is
provably the candidate, and the geometry the critic scored is the geometry that was in the tree.
The implementer's note and the orchestrator's slot assignment agree with the hashes. *(Three earlier
`cand_ports_r1..r3` snapshots in the scratchpad are intermediate development states, not the
candidate: they report `valid=3` with `tile_22_16 has no valid plan`. They are not evidence for or
against N2.01 and were not used.)*

**The verdict.** The critic, rendered blind, chose **image_2 — the base tree** — averaging
**3.58/5 against the candidate's 2.67/5** across the twelve whole-map categories. The candidate was
below the 4/5 floor in eleven of twelve; it did not win a single category, and it tied only on
top-down discipline (4/4). Its worst losses were reference-family resemblance (2 vs 4),
decorative/gameplay hierarchy (2 vs 4) and absence of procedural repetition (2 vs 4).

**Why it lost — the metric was satisfied by paving, not by clearing.** `interarm_sea_coverage`
counts a lattice point covered by the port's own drawing as "not open". The implementing agent
recorded this honestly as a caveat; the blind result says it is fatal, not cosmetic. Pushing the
compound seaward and carrying a wharf out over the foreshore drives the number to 100% by putting
the port's own deck on top of the land inside the U. Nothing was cleared. The critic, with no
access to the numbers, described the result at every site as a "quay-tan polygon" in the bay with
the shoreline "visibly running BEHIND it", called it reclaimed land rather than a structure on a
shore, and at Arin saw a green terrain seam showing through beneath the slab. **A 100% score and a
basin full of port are the same picture.** The gate as written cannot tell them apart.

Three further defects, all consequences of the same move:

1. **The silhouette collapsed to one stamp.** Fitting the compound to a measured, 58u-smoothed
   shore normal instead of the raw coastline made all four ports converge on the same fat pentagon
   with two stubby legs, carrying an identical grid of red/yellow/white cargo pips (Arin repeats a
   five-pip ladder verbatim). The base tree's four harbours are genuinely different — a splayed
   pair at Vandel, a near-right-angle at Capital, a V at Stoneshore, one long arm plus a short one
   at Arin — because each is fitted to its own raw coast. Smoothing the normal is what bought the
   ±10° window; it also bought the repetition. That trade was not visible in any number.
2. **The port outgrew its town** at Capital, Vandel and Stoneshore — the seaward push plus the
   wharf makes the compound read louder and larger than the settlement it serves.
3. **The coastline stopped being continuous.** The apron's lower edge became the waterline, and at
   Capital the polygon threw two spurious pointed triangular flaps across the beach.

**The shore-contact half of the gate never bound.** Recorded here so it is not mistaken for
evidence: the 75% shore-contact test returns exactly 1.00 at every port by construction, because
the apron is independently required to be 100% dry land across that same edge. It measures the
right thing and can only ever answer yes as the plan is currently built. It constrains a future
change, not this one.

**The revert, verified.** `midcentury_port_plan.gd`, `port_visuals.gd`, `test_runner.gd` and
`midcentury_port_gauntlet.gd` were restored to `dab04e87`; `git diff dab04e87` over `scripts/`,
`tests/` and `tools/` is empty. Re-measured on the reverted tree:

- **Unit suite `==== 2298 passed, 0 failed ====`** with a real summary line — exactly the base
  count, so all 8 of N2.01's added port asserts are gone with the mechanism.
- **Port gauntlet `valid=4/4 failures=[]`, `hard_gate_passes` true**, plan hashes back to
  `f3242f47` / `4aae1d4d` / `d88be546` / `aa2ff032` and `interarm_sea_coverage` back to
  96.57 / 95.33 / 95.08 / 95.34%.
- **All nine windowed artifacts byte-identical** to the same-session base control — four port
  framings, four diagnostics and the context frame. `poe_port_metrics.json` differs only in
  `planner_msec`. The tree is pixel-for-pixel the accepted N1.02 map.
- `git diff --check` clean. Only the report is committed.

**What the blind pass says about the tree we kept.** The critic, scoring the base tree without
knowing it was the incumbent, still put five categories below the 4/5 floor and flagged two defects
in it that are now the standing state and are worth logging: at Stoneshore an L-shaped band of dark
decorative blocks between the town and the shore is missing, leaving bare green with hollow
unfilled parcel outlines and a road that drops to a hairline — it reads as an unfinished plate; and
at Vandel and Capital the red port buildings are truncated into wedges by the harbour polygon edge,
shadows sliced with them. The first is the same `tile_5_10` fabric weakness that INT-G3 classified
as non-blocking and that N2.01 separately proved is **not** sensitive to where the quay line sits
(park count and park area were byte-identical before and after a 24u seaward push).

**Cost.** One WIP mechanism (390 lines in the plan script), one verification pass, one blind
comparison, one revert. Addendum §5a is **not delivered**; §5's arm-straightness half remains
satisfied at 0.00° and its "only sea between the arms" half remains open at 2,352u².

### Next lever

**Fix the instrument before attempting the geometry again.** `interarm_sea_coverage` must be
re-defined to score the *underlying terrain* inside the U, treating a point as open only if the
terrain beneath it is sea, so that drawing the port over the defect scores zero credit. As written,
the metric rewards exactly the move that lost the blind pass, and any future attempt optimising
against it will rediscover the same pentagon.

With a terrain-truth metric in place, the promising attack is **selection, not translation**: keep
the N1.02 compound on the shore, at its raw per-port coast angle — which is what the critic likes
about the base tree, and what the smoothed normal destroyed — and search the coastline for a
*sample whose throat is already clear*, scoring candidates on how much sea their U would enclose,
instead of pushing a fixed sample out until the land is under the deck. That preserves the four
distinct silhouettes and the continuous coastline, and it fails honestly at a site where no such
stretch exists rather than paving one. Explicitly rejected as levers: pushing the compound seaward
(this pass), and relaxing the NavGrid dry-land gate (untouched here, and it is what keeps the apron
buildable).

## I1. Instrument repair — articulation, and park vs hole — 2026-08-15

| field | value |
|---|---|
| **Iteration** | I1 (gauntlet 6, measurement only) |
| **Branch / base** | `gauntlet6/instruments` from `gauntlet5/port` (`bc0fb129`) |
| **Layer changed** | none. `git diff bc0fb129 --stat` is four files, all instrument code |
| **Status** | **BOTH INSTRUMENTS LANDED. Rendered output proven byte-identical to a same-session control.** |
| **Evidence** | 24/24 morphology artifacts identical; 600/600 audited tiles identical on every legacy field; unit suite 2298 → 2325 passed, 0 failed |

This stream changed **no geometry**. It exists because three separate instruments in
this project have now certified a defect a human could plainly see, and the pass
immediately before it added a fourth: **built area is the wrong proxy for perceived
density.** The V5 vocabulary candidate raised coverage 2.1% map-wide while the plate
lost roughly half its parcels in places, and the density audit called that an
improvement. Both instruments below were written to the standing rule — *before
optimising any metric, ask what a candidate that MAXIMISES it while LOOKING WORSE
would look like* — and each is shipped with the answer.

### Instrument 1 — articulation / visible piece count

**Invocation** (headless, ~3.5 min, unchanged from the existing audit):

```
<godot> --headless --path . res://tools/density_audit.tscn --quit-after 4000
#   → /tmp/poe_density_audit.json   full per-tile record
#   → /tmp/poe_density_audit.txt    table, ARTICULATION block, WORST SILHOUETTES
```

**Definition.** Two drawn masses are **visually fused** when their outlines, each
dilated by `DensityAudit.FUSION_DILATION`, overlap — i.e. when the bare ground
between them is narrower than `2 × 1.9u = 3.8u`. A **visible piece** is a connected
component of the masses under that relation, and its **silhouette** is the union of
those dilated outlines. The count of visible pieces, not of polygons, is what the eye
reads.

**Why this catches the blob, where a polygon count does not.** The V5 implementing
agent measured the Vandel blob as *"several adjacent masses rather than one polygon"*
whose outlines abut *"with only their outlines between them and read as one
silhouette"*. A naive polygon counter reports that blob as N healthy masses. Dilating
before clustering asks the question the eye asks — *is there ink-free ground between
these two, wide enough to see?* — and answers no, so the blob is one piece.

**The dilation is not tuned.** It is exactly half `UrbanFabricVisuals.HERO_ALLEY_HALF_WIDTH`
(1.9u), the constant that makes every alley the fabric itself accepts as a visible gap
3.8u wide. Anything narrower than an accepted alley is not a gap the plate shows. The
constant is FROZEN for the same reason `LARGE_MASS_AREA` is: a candidate that fuses its
fabric must not be able to redefine "fused". A unit test pins the derivation, and a
second pins the boundary — a gap of exactly 3.8u does **not** fuse.

**JSON fields.** Per tile (`tiles[]`) and per settlement component (`components[]`):

```
visible_piece_count          how many separate masses the eye can count
piece_mass_count             drawn masses charged to this tile / component
masses_per_visible_piece     1.000 = perfectly articulated; rises as fabric fuses
fused_piece_count            pieces holding >= 2 masses
fused_mass_share_pct         % of drawn masses that hide inside a shared silhouette
largest_piece_mass_count     the worst single silhouette here
mean_visible_piece_area      \  "denser in ink, sparser in city" is these two
median_visible_piece_area    /  rising while the piece count falls
silhouette_perimeter_ratio   sum(dilated outline perimeters) / union perimeter;
                             1.000 = no shared boundary. An INDEPENDENT fusion
                             signal that does not use the piece count at all.
```

Map-wide the same block sits at `articulation.map`, with `articulation.largest_pieces`
naming the fifteen worst silhouettes by tile.

**How it would have caught its motivating defect.** V5 reported `masses 2037 → 2044`
and built area `+2.1%`, and the critic simultaneously found a fringe hamlet fused into
*"ONE continuous charcoal amoeba"* and a river quarter *"one enormous unarticulated
olive polygon"*. Under this instrument, fusing three masses into one silhouette drops
`visible_piece_count` by 2 and cannot be netted back by adding four companions
elsewhere — `masses_per_visible_piece` rises, `median_visible_piece_area` rises, and
`silhouette_perimeter_ratio` rises, all three in the same direction, while built area
also rises. The disagreement between the two families of number is the alarm. A unit
test reproduces exactly that fixture: **same mass count, more built area, fewer visible
pieces, larger median piece.**

**The adversarial question.** A candidate that maximises `visible_piece_count` while
looking worse is confetti — a thousand tiny well-separated crumbs. That is why the
median and mean piece area ship *beside* the count and not behind it, and why the
existing `small_below_floor` / `large_below_floor` gates and `LARGE_MASS_AREA` remain
untouched: piece count alone is not a gate, it is one of four numbers that have to move
together.

### Instrument 2 — deliberate court vs undrawn hole

**Same invocation.** The `PARKS vs HOLES` block of `/tmp/poe_density_audit.txt`.

**Definition — two independent tests, both required.** A green is a **deliberate park**
only if:

1. **ROLE.** The plan assigned this ground a park/green role, recorded at the moment the
   role was decided (`role` stamped on the render entry by
   `urban_fabric_visuals.gd`) — not inferred afterwards from its colour. Where two greens
   merge into one outline, the park role must own at least half the merged area, so a
   residual pocket cannot launder itself by touching a real park.
2. **ENCLOSURE.** At least `PARK_ENCLOSURE_MIN` (75%) of the green's own outline sits on
   ink. A court drawn as a court puts its ring into the block-edge layer; a residual
   pocket left where a mass under-filled or was rejected is bounded by whatever happened
   to survive.

A green failing **either** test is an **UNDRAWN HOLE**, is reported separately with its
area and reason, and **does not count toward the ≥ 2 parks-per-urban-tile floor** of
`docs/map-density-and-port-addendum.md` §2. `DensityAudit.evaluate()` is now fed
`deliberate_park_count`.

A third hole shape carries no green at all: a parcel the plan assigned a **built** role
whose mass never reached the render arrays. Those are `bare_parcel`s — an inked but
empty plot, the critic's *"hollow unfilled parcel outlines"*.

**JSON fields.** Per tile:

```
deliberate_park_count / deliberate_park_area    what the section-2 floor is judged on
park_hole_count / park_hole_area                greens that are not parks
park_hole_reasons                               {no_role | unenclosed | no_role_and_unenclosed}
bare_parcel_count / bare_parcel_area            built-role plots with nothing drawn
bare_parcels[]                                  each with role, area, covered_fraction
park_count / park_area                          unchanged, kept for continuity
```

Map-wide at `parks.totals`, plus `parks.enclosure_distribution`,
`parks.enclosure_negative_control` and `parks.role_share_distribution`.

**How it would have caught its motivating defect.** The V5 critic's verdict was
literally *"You cannot tell a park from a hole."* Its park counter rose 361 → 373 while
green-space integration scored **down**, and it found *"an unfilled green pentagon inked
on only two of its five edges"* where a civic block used to be. That pentagon measures
`enclosure ≈ 0.40` here — it is a HOLE, it is excluded from `deliberate_park_count`, and
the tile's park floor is judged without it, so the count would have moved **down**, not
up. A unit test asserts precisely that verdict at 0.40, and the enclosure measurement is
pinned on hand-laid ink: a fully ringed 40×40 court measures 1.000, the same court with
ink on two sides measures 0.50 and fails.

**The adversarial question, and its answer — the negative control.** A metric satisfied
by *paving* rather than by clearing is exactly how the N2 port pass scored 100% on a
basin full of port. The equivalent failure here is ink being so dense everywhere that
every green measures enclosed and the test is vacuous. That is measured, not assumed:
each green is re-measured **displaced by a fixed (37, 29)u onto neighbouring ground,
against the same ink**.

```
enclosure         n=181  min=1.000  p05=1.000  median=1.000  mean=1.000
NEGATIVE CONTROL  n=181  min=0.000  p05=0.000  median=0.103  mean=0.117  max=0.470
```

Every real green scores 1.000; no displaced green reaches even 0.47, let alone the 0.75
floor. The test discriminates by a wide margin. **The zero-hole baseline below is a
measurement, not a vacuous pass.**

### THE BASELINE — the number the next stage is judged against

Measured on `gauntlet6/instruments` (geometry identical to `gauntlet5/port`), one run,
`/tmp/poe_density_audit.txt`:

```
ARTICULATION (map-wide)
  drawn masses counted        2191
  VISIBLE PIECES              1259
  masses per visible piece    1.740      <-- 43% of drawn masses are not separately visible
  fused pieces (>=2 masses)    453
  masses inside a fused piece 63.2%
  largest single silhouette     64 masses
  mean visible piece area     2025 u^2
  median visible piece area    846 u^2
  silhouette perimeter ratio  1.183
  pieces off every tile          0

  by class          tiles  masses  pieces  m/piece  median piece area
  urban                92    1820    1004    1.813             1155 u^2
  sparse              204     368     254    1.449              357 u^2
  mountain             45       0       0        —                  —
  remote               54       3       1    3.000             2749 u^2

  by component (worst)          tiles masses pieces m/piece med_area perim_ratio
  settlement-plan|silkstown         2     55     15   3.667     1277       1.267
  settlement-plan|capital-port       7    235     86   2.733      499       1.298
  hero|arin-old                      9    271    141   1.922     2705       1.211

  worst silhouettes    tile_23_9  64 masses (ink 103,003 u^2 in a 64,323 u^2 silhouette)
                       tile_23_8  50 masses
                       tile_9_8   29 masses

PARKS vs HOLES (map-wide)
  DELIBERATE parks             181   (982,109 u^2)
  UNDRAWN holes (greens)         0   (0 u^2)
  BARE built-role parcels        7   (22,922 u^2) of 606 judged
  urban tiles with >= 2 parks   46 corrected / 46 uncorrected
```

Three things in that baseline are worth naming now, because they are findings, not
noise.

1. **`tile_23_9` already carries a 64-mass amoeba** — 103,003 u² of ink inside a
   64,323 u² silhouette, meaning the masses there overlap each other heavily. It is a
   *sparse* tile. This is the defect class the V5 critic described, present and
   unmeasured in the accepted tree.
2. **The two settlement plans are the least articulated fabric on the map.** Silkstown
   runs 3.667 masses per visible piece and Capital Port 2.733, against 1.449 for ordinary
   sparse fabric. Whatever the next geometry stage does, these are its targets.
3. **The park correction changes no verdict on this tree.** 0 holes means
   `deliberate_park_count == park_count` on every tile, so `46 corrected / 46 uncorrected`
   urban tiles meet the floor and the compliance table is unmoved. The instrument is
   installed *before* it is needed — which is the point. Any hole the next stage
   introduces now costs it a park instead of earning it one.

The 7 bare parcels are all `face_built` morph street faces with `covered_fraction` of
0.000–0.078 — nothing at all was drawn on them: `tile_9_8` Silkstown ×3, `tile_21_7`
Kingstown Docks, `tile_26_8` Capital Port Industrial Zone, `tile_3_4`, `tile_22_15`.

### PROOF THAT NOTHING VISUAL CHANGED

Two independent proofs, both against a **same-session control captured from the base
commit on this machine** (the archived v0 pixels are dead as a baseline here — TRAP 3).

1. **Windowed capture, byte-identical.** The morphology harness was run windowed under
   the capture lock on `gauntlet6/instruments`, then on `gauntlet5/port` (`bc0fb129`) in
   its own worktree, back to back in one session. `diff -rq` over the two output
   directories is **clean across all 24 artifacts — 22 PNGs and both JSON files**,
   including `poe_morph_metrics.json` itself. That is stronger than the V5 revert proof,
   which had to exclude per-run planner timings. `poe_morph_wide.png` hashes
   `d405fd21…` on both trees; `poe_morph_arinold.png` hashes `9c37546667…` on both.
   The seven W1.01 water counters, the relief counters and the district-field counters
   are carried inside that byte-identical metrics JSON.
2. **Density audit, identical on every legacy field.** The audit was run on both trees.
   Across all **600 tile records** and all 22 pre-existing fields — `small_count`,
   `large_count`, `small_area`, `large_area`, `park_count`, `park_area`,
   `courtyard_count`, `courtyard_area`, `mass_kind_counts`, `hex_area`, `dry_land_area`,
   `open_land_area`, `dry_buildable_area`, `forest_disc_count`,
   `gameplay_footprint_count`, `relief_shoulder_count`, `failures`, `passes`,
   `gate_failure`, `physically_constrained` — there are **zero differences**. `threshold`,
   `classification`, `summary` and the ordered failure list are identical objects. Those
   fields are computed from the rendered polygons, so their identity is a direct
   statement that the geometry did not move.

Also run: **unit suite `==== 2325 passed, 0 failed ====`** with a real summary line
(2298 v0 + 27 new asserts), and `git diff --check` clean. `git diff bc0fb129 --stat` is
four files: `scripts/density_audit.gd`, `scripts/urban_fabric_visuals.gd`,
`tests/test_runner.gd`, `tools/density_audit.gd`. Four incidental
`reports/balance/*.translation` import rebuilds and one stray `.uid` that the `--import`
run picked up were reverted — the same trap the V5 pass recorded.

**Why the fabric edit is draw-neutral by construction, not just by measurement.** The
only changes to `urban_fabric_visuals.gd` are: a `"role"` key added to parcel and park
entry dictionaries; one retained reference to the already-sanitised parcel array; three
new read-only keys on `density_audit_snapshot()`; and one `RoadHash.pick` moved one
statement earlier so the hero parcel record can carry the role its own roll assigned.
`_fill_mesh` reads only `poly` and `color`. Both sanitisers remove whole entries without
rebuilding them, so extra keys survive untouched. `RoadHash.pick` is a pure FNV-1a of its
key, so reading it earlier changes no value anywhere. No constant, no threshold and no
polygon was touched.

### Not run, and why

- **e2e balance harness.** No simulation surface was touched; the four changed files are
  the audit tool, the audit logic, the test runner and a measurement seam.
- **Road-frontage audit and the port gauntlet.** Both are carried by the byte-identity
  above: the frontage audit reads the same planner geometry the density audit proved
  unchanged, and the port plan scripts are untouched. This is a statement of what was and
  was not run, not a claim about what they would return.

### Known limits of these instruments — stated, not hidden

- **The bare-parcel test reaches 606 of 1,829 drawn parcels.** The rest either carry a
  deliberately-vacant or park role, or fall under `MIN_COUNTED_PARCEL_AREA` (600 u²).
  Small per-mass lots below that floor are not judged; by construction those lots are
  appended alongside their mass, so a dropout there is rarer, but it is not impossible
  and this instrument would miss it.
- **Coverage is measured by summed intersection, clamped at 1.0.** Two overlapping
  covering polygons are counted twice. That can only make a parcel look *more* covered,
  so it cannot manufacture a bare parcel — but it can hide one whose only "cover" is a
  double-counted sliver. The 0.10 threshold is far below where that matters.
- **Role tags are declared by the drawing code.** A future mechanism could stamp
  `"street_park"` on a residual pocket and pass test 1. Test 2 (enclosure) is the
  independent check that would still catch it, which is exactly why both are required
  and why the negative control is reported every run.
- **`tile_20_11` remains unexplained.** The SettlementPlan core planner still records
  38.5% core coverage where the audit measures 12.01% on identical geometry with the same
  denominator. Neither instrument here touches that disagreement; it is still open.

---

## gauntlet6 ADVERSARIAL STAGE — branch `gauntlet6/gameit`

Task: break the two gauntlet6 instruments by satisfying them while the map looks worse.
**Both are breakable. One is worse than breakable: its enclosure test is tautological and
has never measured anything.** Every claim below is a run, not an argument — probe at
`tools/instrument_attack.gd`, eleven pins in `tests/test_runner.gd::_test_instrument_adversarial`
(2325 → 2336 passed, 0 failed), two full audit runs on this branch reproducing the claimed
baseline byte-for-byte (1259 pieces / 2191 masses / 1.740 / 846 u² / 1.183 / 181 parks /
0 holes / 7 bare) across separate processes.

### INSTRUMENT 2 IS NOT MEASURING ENCLOSURE — it measures each green against its own ring

Every one of the six park-creation sites in `scripts/urban_fabric_visuals.gd` (lines 4204,
4326, 5419, 5575, 5903, 6044) does `park_entries.append({poly: P, ...})` and then
`_append_ring(_block_edges, P)` — **the same polygon**. `snapshot.ink_segments` is
`_block_edges + _parcel_edges + _roof_edges`. So `enclosure_fraction()` walks a green's
perimeter against an ink set that *contains that green's own outline*, and cannot return
anything but 1.000 regardless of what surrounds it.

A FOREIGN-INK CONTROL was added to the audit (removes exactly the green's own ring, keeps
everything else) and run on the real map:

```
  enclosure           n=181  min=1.000 p05=1.000 median=1.000 mean=1.000
  NEGATIVE CONTROL    n=181  min=0.000 p05=0.000 median=0.103 mean=0.117  max=0.470
  FOREIGN-INK CONTROL n=181  min=0.000 p05=0.000 median=0.000 mean=0.074  max=0.563
                      greens still at or above the 0.75 floor: 0 of 181
```

**Zero of 181 greens on this map are enclosed by ink drawn by anything other than
themselves.** The shipped displacement control does not detect this — it moves the polygon
off its own ring, so it fails for the same tautological reason the test passes; it lands on
*more* foreign ink (median 0.103) than the green's true location does (median 0.000). It is
the L1 failure verbatim: 100% of a polygon constructed to score 100%.

Consequence: `park_hole_count == 0` is a **structural identity**, not a measurement.
`role_share` is likewise 1.000 for all 181 samples because the role is stamped at the same
site. Both tests sit at their ceiling for every sample. The instrument cannot see the
critic's pentagon, because the fabric can never emit a green without its own complete ring.

REQUIRED FIX: measure enclosure against ink the green did not contribute — the block edges
of *neighbouring masses* — or better, the fraction of the perimeter with a drawn mass
within a short band outside it. Keep the foreign-ink control as the acceptance criterion.

### INSTRUMENT 1: the netting claim is false, and shattering scores a perfect report

- **A2 NETTING.** The claim "fusing three masses into one silhouette CANNOT be netted back
  by companions placed elsewhere" is false on *all five* headline numbers simultaneously.
  Control 20 abutting pairs + 20 singletons; candidate collapses ten singletons into one
  ten-mass amoeba and adds 28 ordinary buildings elsewhere: pieces 40→59, m/piece
  1.500→1.492, fused mass 66.7%→56.8%, perimeter ratio 1.2121→1.1775, median piece area
  2400→3200. Built area also rises. Only `largest_piece_mass_count` fires (2→10).
  Map-wide the offset needed is `K > M(g-1)/(M-P)` = **22 crumbs anywhere buy one ten-mass
  amoeba** at the real baseline (M=2191, P=1259).
- **A1/A3 SHATTERING and MINIMUM-ALLEY PAVING.** Cutting every building into four crumbs
  at 4.0u gaps gives pieces 36→144, m/piece 1.000, 0 fused, ratio 1.000 — a *perfect*
  report on the same ink; and a 144-mass plate covering **84.6%** of its own bounding box
  on 3.81u gaps scores identically perfect. The fusion test is a step function at 3.8u:
  drop the same plate to 3.79u and it collapses to 1 piece / 144.000 m per piece. The
  claimed confetti guard (mean/median piece area) is not a gate — **`DensityAudit.evaluate()`
  reads no articulation number at all** — and is defeated outright by crumbs at or above
  the median.
- **A4 THE SHADOW LAYER IS WITHHELD.** `masses` is `block_entries` only; the fabric also
  fills a SHADOW for every block at `BLOCK_SHADOW_OFFSET (2.2, 2.8)`. Re-clustering the
  same masses AS DRAWN (mass ∪ its own shadow, identical 1.9u rule) on the real map:

```
    VISIBLE PIECES            1031  (instrument reports 1259)
    masses per visible piece  2.125  (instrument reports 1.740)
    largest silhouette          74  (instrument reports 64)
```

  **18% of the reported pieces exist only because the instrument is not shown the shadow
  layer.** A candidate that widens its street pitch from 3.7u to 4.0u buys articulation
  credit the plate leaves as 1.2u of paper.
- **A5 `mean/median_visible_piece_area` is not an area.** It is the SUM of member ink
  areas; overlaps count repeatedly. Four coincident masses report a 6400 u² "piece area"
  inside a 1916 u² silhouette. The baseline already shows this: tile_23_9, 103,003 u² of
  ink inside a 64,323 u² silhouette. `silhouette_area` is computed and thrown away
  map-wide.
- **PER-TILE DENOMINATOR DISAGREEMENT (the tile_20_11 shape, live).** Pieces are clustered
  map-wide and charged whole to one tile, while masses are assigned individually.
  **57 of 600 tiles** disagree: tile_23_9 owns 34 masses and is charged 90; **tile_22_8
  owns 21 masses and is charged 0 pieces and 0 piece mass**, so it reads as having no
  articulation problem while its entire fabric sits inside a neighbour's amoeba. Map-wide
  totals reconcile (2191 = 2191); the per-tile columns do not.

### Self-declaration and floor games (both instruments)

`kind` and `role` are strings written by the very code being audited. `kind == "courtyard"`
is `continue`d **before** any verdict — **155 of 454 rendered greens (264,873 u², 27% of the
reported park area) already take that exit.** Relabelling a residual pocket `courtyard`
deletes it from both the park and hole counts; relabelling it `face_park` converts it into a
*deliberate park* (P1 guarantees the enclosure half). A bare parcel is cured by 11% cover of
anything, by a courtyard-kind green stamped over it, by renaming `face_built` → `face_open`,
or by splitting it into 599 u² slivers. Greens under 200 u² and masses under 120 u² are
invisible, so a chain of sub-floor crumbs bridges two masses the instrument still calls two
pieces. `role_share ≥ 0.5` is an *area* bar over a merged outline: one 20,000 u² hero park
that merely grazes nineteen 1,000 u² pockets launders all nineteen into itself, and they
stop being counted at all.

### Determinism

Two separate audit processes on this branch produce byte-identical summaries, and both match
the `gauntlet6/instruments` run exactly. `visible_pieces()` is order-stable under input
reversal. No determinism defect found.

---

## G7. Instrument repair — both instruments rebuilt against the gauntlet6 attacks — 2026-08-15

| field | value |
|---|---|
| **Iteration** | G7 (gauntlet 7, measurement only) |
| **Branch / base** | `gauntlet7/repair` from `gauntlet6/gameit` (`ac825d92`) |
| **Layer changed** | none. `git diff gauntlet6/gameit --stat` is five files, all instrument code |
| **Status** | **ELEVEN OF ELEVEN DOCUMENTED BREAKS ADDRESSED — nine closed outright, two partly closed with the residue named** |
| **Evidence** | 600/600 audited tiles identical on 23 rendered-geometry fields (one intended instrument difference); unit suite 2336 → 2369 passed, 0 failed; both audits re-run end to end |

The gauntlet6 adversarial stage found both instruments breakable and one of them
tautological. This stream repaired them. **Every headline number got worse,
which is the point** — the old ones flattered the map.

### THE HEADLINE: what the repaired instruments say about the same, unchanged map

```
                                       gauntlet6      REPAIRED
  ARTICULATION
    drawn masses counted                    2191          2191
    VISIBLE PIECES                          1259          1032     <-- 18% were never there
    masses per visible piece               1.740         2.123
    fused pieces (>= 2 masses)               453           416
    masses inside a fused piece            63.2%         71.9%
    largest single silhouette             64 mass       74 mass
    median visible piece area              846 u2       1317 u2   <-- was a SUM OF INK
    silhouette perimeter ratio             1.183         2.269
    excess masses (not nettable)               -          1159     <-- new, monotone
    pieces holding >=3 / >=5 / >=10            -   210 / 72 / 20   <-- new, monotone
    fusion fragility (0.5x -> 2.0x)            -         1.255     <-- new, graded
    tiles whose piece count disagrees
      with their own mass count               57             0

  PARKS vs HOLES
    DELIBERATE public parks                  181            69
    INNER COURTS (deliberate, private)         -            34
    UNDRAWN HOLES                              0           334
    urban tiles meeting the >= 2 floor    46 / 46       14 / 65
    EMPTY parcels, any role                    -           291  (1,379,872 u2)
    UNCOVERED parcel area                      -     2,703,475 u2 of 4,637,025

  COMPLIANCE (same section-2 table)
    failing tiles                            272           320
    urban compliant                      32 / 92        2 / 92
    sparse compliant                    45 / 204      27 / 204
    new named failures                         -   fabric_fused 51, fabric_confetti 42
```

`gauntlet6` column re-measured on `gauntlet6/gameit` in this session, not quoted
from the earlier write-up; it reproduces the documented baseline exactly
(1259 / 2191 / 1.740 / 846 / 1.183 / 181 / 0 / 7).

### INSTRUMENT 2 — the tautology, closed

**The break.** `enclosure_fraction()` walked a green's perimeter against an ink
set containing that green's own ring, because every park site in
`urban_fabric_visuals.gd` appends the green and then `_append_ring`s the same
polygon. All 181 samples scored 1.000 by construction; `role_share` scored 1.000
for the same reason; `park_hole_count == 0` was a structural identity. The
shipped negative control landed on *more* foreign ink (median 0.103) than the
real greens did (median 0.000).

**The repair.** `DensityAudit.mass_band_enclosure()` walks the green's outline,
steps OUTWARD along the local normal at three depths, and asks whether a DRAWN
MASS is there. The outward direction is resolved by probing (the normal that
lands outside the polygon), which is correct on concave outlines where a
centroid rule is not. A polygon cannot cover ground outside its own outline, so
a green can never be its own enclosure — pinned as a test.

**The band is a derivation, and the first derivation was wrong.** The first
attempt used one accepted alley (3.8u) and the measurement was dead on arrival:
the fabric insets every mass by `PARCEL_MARGIN` (4.5u) inside its parcel, so a
*legally placed* neighbour cannot reach within 3.8u. The median real green
scored 0.000 against a control at 0.018 — a test that could barely fire. The
band is now `PARCEL_SETBACK + 2 x FUSION_DILATION = 8.3u`: the closest a
neighbouring building is allowed to be, plus the narrowest gap this map calls
visible. Both terms are frozen constants of the drawing, pinned equal to the
fabric's own by unit test.

**THE ACCEPTANCE CRITERION — the two distributions, both reported every run.**
The control had to be rebuilt too. Displacing a green by one fixed vector often
drops it *inside a building*, and an outline inside a building is trivially
surrounded by it, which proves nothing — that is why the gauntlet6 control
scored *higher* than the real greens. The control now walks a fixed
deterministic spiral and takes the first placement that overlaps no drawn mass:
the same shape, on unbuilt ground elsewhere.

```
  band   real_med  real_mean   ctl_med  ctl_mean   pass real / control
   4.2      0.000      0.144     0.000     0.020      35 /   0
   8.3      0.019      0.249     0.000     0.041     103 /   0   <-- the verdict band
  16.6      0.201      0.304     0.000     0.082     119 /   5
  33.2      0.334      0.397     0.092     0.154     145 /  19

  control placed on clear ground 434 of 437, unplaceable 3
  at the 0.50 public floor:  real 103 of 437,  control 0 of 434   (control max 0.493)
```

The real greens stand clear of the control at every band, by 6x in the mean and
by 103-to-0 at the floor. **The instrument discriminates, and it discriminates on
ink the green did not draw.** The gauntlet6 numbers are still printed beside it
so the tautology stays on the record: own-ink enclosure min 1.000 median 1.000,
foreign ink median 0.031.

**And the verdict on this map is bad.** 334 of 437 drawn greens have no bounding
fabric; only 69 are public greens and 34 are inner courts. Urban tiles meeting
the two-park floor fall 46 → 14. That is the critic's *"you cannot tell a park
from a hole"* answered with a number, and the answer is that most of them are
holes.

### INSTRUMENT 2 — self-declaration and floor games

- **`kind == "courtyard"` no longer exists as a code path.** It was `continue`d
  before any verdict and 155 of 454 rendered greens took that exit. Every drawn
  green over the area floor is now judged, and `green_verdict()` takes **one
  argument, a measurement**. There is no parameter a rename could reach. A
  courtyard is now a green the fabric *wraps* (>= 0.90), measured — still
  excluded from the public floor, but counted and reported (34 of them).
- **Merge laundering (P3) is closed.** Each entry is judged on its own outline
  BEFORE anything is merged, and a merged space carries only `public_area` — the
  area of the entries that passed alone. The 20,000 u^2 hero park grazing
  nineteen 1,000 u^2 pockets now yields one park of 20,000 u^2 and nineteen
  holes, not one park and nothing else. Pinned with the tool's own
  `_merge_green_spaces`, including a run with every entry relabelled.
- **Bare parcels.** The coverage field is now DRAWN MASSES ONLY, so stamping a
  green of any kind over an empty plot no longer cures it. Three numbers ship,
  deliberately overlapping: `bare_parcels` (role-gated, 7, unchanged — kept for
  continuity), `empty_parcels` (**every** parcel over the floor whatever it calls
  itself, 291) and `uncovered_parcel_area` (area-weighted over every drawn parcel
  with **no counting floor at all**, 2,703,475 u^2 of 4,637,025). A `face_built`
  → `face_open` rename moves a parcel between the first two and leaves the third
  exactly where it was; splitting a 2,995 u^2 plot into five 599 u^2 slivers
  drops out of both counts and leaves the third unchanged.

### INSTRUMENT 1 — the shadow layer, shown

`density_audit_snapshot()` now hands over `shadows`: the fabric's own sanitised
`shadow_entries` array, not a model reconstructed by offsetting. The audit
clusters them as non-counting **BRIDGE** shapes — they fuse what they touch and
count as no building. Sub-floor masses under `MIN_COUNTED_MASS_AREA` are bridges
for the same reason, which closes the crumb-chain attack (P5): a 108 u^2 crumb
laid between two masses 20u apart now makes them one piece and is itself counted
as nothing.

```
  clustered ink: 2191 counted masses + 25 sub-floor + 2201 shadow fills
  VISIBLE PIECES 1259 -> 1032        (the adversarial estimate was 1031)
  m / piece      1.740 -> 2.123      (the adversarial estimate was 2.125)
  largest        64 -> 74 masses     (the adversarial estimate was 74)
```

### INSTRUMENT 1 — netting, closed by an absolute number

Every gauntlet6 headline was a ratio and every ratio could be paid for
elsewhere: 22 crumbs anywhere bought one ten-mass amoeba.
`excess_mass_count = mass_count - visible_piece_count` cannot be.

* adding a well-separated building adds one mass **and** one piece: **0**
* adding a crumb that fuses to something adds one mass and no piece: **+1**
* fusing g masses into one silhouette: **+(g-1)**

There is no arrangement of new geometry that lowers it. On the A2 fixture it
goes 20 → 29 while all five old numbers improve, and forty well-separated
companions added to the control move it 20 → 20. `pieces_holding_3/5/10_or_more`
and `largest_piece_mass_count` are monotone in the same sense. Map-wide the
number is **1159** — 1,159 of 2,191 drawn masses are not separately visible.

### INSTRUMENT 1 — the step function, graded

The fusion test answered one question at one dilation, so a plate on 3.81u gaps
scored perfectly and the same plate at 3.79u collapsed to one piece.
`fusion_curve()` now clusters the same ink at half an accepted alley, one, and
two, and reports the curve. `fusion_fragility` is the rise in masses-per-piece
across it — a continuous number with no threshold in it.

```
  the paved 3.81u plate      x0.5: 144 pieces   x1.0: 144   x2.0: 1     fragility 143.000
  the same 144 on 20u streets                                            fragility   0.000
  THE REAL MAP              x0.5: 1303 pieces  x1.0: 1032  x2.0: 746    fragility   1.255
```

### INSTRUMENT 1 — the confetti direction, actually gated

`DensityAudit.evaluate()` read **no articulation number at all**. It now reads
three, and names two new failures:

* `fabric_fused` — masses per visible piece >= 2.0 on a tile with >= 5 masses.
  The bar is a statement, not a tuning: *more mass hidden than shown*. **51 tiles.**
* `fabric_confetti` — median visible piece area below `drawn_piece_floor_area()`
  (1196 u^2), derived from three frozen numbers: the v0 median small mass
  (800 u^2) as a square, drawn with its shadow, dilated on each side. A plate
  whose median visible piece is smaller than one baseline small building drawn
  the way the plate draws it is confetti. **42 tiles.**

On the A1 fixture the whole plate reports a median silhouette of 1916 u^2 and no
confetti failure; the shattered plate reports 473 u^2 and fails.

### INSTRUMENT 1 — piece area is an area now

`mean/median_visible_piece_area` is the area of the **union**, outer rings minus
holes. The gauntlet6 number — the sum of member ink areas, which double-counts
every overlap — survives as `mean/median_piece_ink_area`, and their ratio ships
as `ink_to_silhouette_ratio` so the overlap the old field hid is named. Four
coincident masses now report a 1916 u^2 piece with `ink_to_silhouette 3.340`,
where the old field reported "6400 u^2".

### INSTRUMENT 1 — the per-tile denominator (the tile_20_11 shape), closed

Pieces were clustered map-wide and charged **whole** to one tile while masses
were assigned individually. A tile is now charged exactly the pieces ITS OWN
masses fall into, from the same `_owning_tile` assignment that produced its
small/large counts. A piece holding masses from two tiles is counted by both,
flagged as SHARED, and the reconciliation is printed.

```
  tiles whose piece_mass_count disagrees with their own mass count:  57 -> 0

  tile_22_8   base: 21 masses, charged 0 pieces, m/piece 0.000 - "no problem"
              G7:   21 masses,         1 piece,  m/piece 21.000,
                    shared with 1 neighbour, largest shared silhouette 74 masses
  tile_23_9   base: 34 masses, charged 90 piece-masses (a 2.6x overcharge)
              G7:   34 masses, 34 piece-masses, 3 pieces, largest shared 74

  map-wide:   per-tile mass sum 2191 = map 2191
              per-tile piece sum 1098 vs map 1032, difference = 66 tile
              memberships across 56 cross-tile silhouettes  (printed, not silent)
```

The worst silhouette is now named by every tile inside it —
`tile_22_7+tile_22_8+tile_23_8+tile_23_9+tile_24_8, 74 masses, 116,165 u^2 of
ink in a 193,808 u^2 silhouette` — instead of being charged to one owner.

### PROOF THAT NOTHING VISUAL CHANGED

This stream changed no geometry. Two proofs, neither of which needed a windowed
capture (a geometry stream held the capture lock for most of this session).

1. **Diff footprint.** `git diff gauntlet6/gameit --stat` is **five files**:
   `scripts/density_audit.gd`, `scripts/urban_fabric_visuals.gd`,
   `tests/test_runner.gd`, `tools/density_audit.gd`,
   `tools/instrument_attack.gd`. The incidental `reports/balance/*.translation`
   and `*.import` rebuilds the `--import` run picked up were reverted — the same
   trap the V5 and I1 passes recorded.

2. **The fabric edit is draw-neutral by construction.** The entire change to
   `urban_fabric_visuals.gd` is: one new member `_render_shadow_entries`, one
   assignment of the ALREADY-EXISTING `shadow_entries` array reference (the same
   array `_shadow_mesh` is built from — retaining a reference cannot change a
   pixel), one reset to `[]`, and a read-only `shadows` key on
   `density_audit_snapshot()`. No constant, no threshold and no polygon was
   touched.

3. **Density audit, identical on every rendered-geometry field.** Both audits
   were run end to end in this session. Across all **600 tile records** and 23
   fields computed from the rendered polygons — `terrain_type`, `class`,
   `urban_profile`, `built_road_edge_count`, `small_count`, `large_count`,
   `small_area`, `large_area`, `courtyard_count`, `courtyard_area`,
   `mass_kind_counts`, `hex_area`, `dry_land_area`, `open_land_area`,
   `dry_buildable_area`, `water_margin_area`, `forest_disc_count`,
   `gameplay_footprint_count`, `relief_shoulder_count`,
   `relief_retention_fallback`, `bare_parcel_count`, `bare_parcel_area`,
   `bare_parcels` — there is **exactly one difference in 13,800 comparisons**,
   and it is an intended instrument change, not a geometry change:
   `tile_22_15`'s single bare parcel reports `covered_fraction` 0.0778 → 0.0726
   because the coverage field no longer counts greens as cover. Its area is
   byte-identical (9650.10031890869) and it is still bare. `threshold`,
   `classification`, `rendered_masses` (2216), `rendered_greens` (454),
   `uncounted_mass_fragments` (25), `unassigned_masses/greens` (0/0) and
   `judged_built_parcels` (606) are identical objects.

Also run: **unit suite `==== 2369 passed, 0 failed ====`** with a real summary
line (2336 gauntlet6 + 33 net new asserts), and the adversarial probe end to
end.

### THE ATTACKS ARE PINNED, NOT DESCRIBED

`tests/test_runner.gd::_test_instrument_adversarial` keeps **every gauntlet6
construction verbatim** and inverts the assertion to the repaired verdict, so a
candidate that reopens one fails in the unit suite before it reaches a critic.
Each block asserts the fixture still reproduces the attack AND that the repaired
instrument now catches it:

```
  A1 CLOSED   shattering into crumbs FAILS the gate as confetti
  A2 CLOSED   excess_mass_count rises by exactly the nine hidden masses;
              forty companions elsewhere buy exactly nothing
  A3 CLOSED   the paved plate collapses across the graded curve (fragility > 100)
              while the same masses on 20u streets sit at 0.000
  A4 CLOSED   with the shadow layer shown, two masses 4.0u apart are ONE piece
  A5 CLOSED   the reported piece AREA is the silhouette; the overlap is named
  P1 CLOSED   a green alone on blank paper is a HOLE however it rings itself
  P3 CLOSED   a merged space carries only the area of entries that passed alone;
              relabelling every entry changes nothing
  P4 CLOSED   the rename escape no longer clears the label-free count
  P5 CLOSED   a 108 u^2 crumb chain fuses two masses and counts as no building
  PER-TILE    each tile is charged the pieces its own masses fall into; a tile
      CLOSED  inside a neighbour's silhouette is told so, not charged zero
```

`tools/instrument_attack.gd` is now a before/after ledger rather than a list of
open wounds: every construction is re-run and prints the number that closes it.

### WHAT IS *NOT* CLOSED — stated, not hidden

- **The 10% bare-parcel cover band survives.** A single 15x15 shed on a 2,000
  u^2 plot is 11.3% cover and clears both the role-gated and the label-free
  count. The area-weighted `uncovered_parcel_area` absorbs the other 89%, but the
  COUNT does not. A defect that leaves one token building per plot is still
  under-reported by two of the three numbers.
- **Greens under `MIN_COUNTED_GREEN_AREA` (200 u^2) are still not judged.** A
  defect shattered into sub-floor GREENS is invisible to instrument 2. Masses
  below their floor no longer escape (they are bridges now), but greens do. The
  only number that sees that ground is `uncovered_parcel_area`, and only where
  the ground is a drawn parcel.
- **`ink_to_silhouette_ratio` is weaker map-wide than per piece.** With the
  shadow layer and the dilation included, the map-wide ratio is 0.702 and no
  longer flags overlap on its own; the per-piece number still does (the A5
  fixture reports 3.340). A candidate that stacked duplicates across the whole
  map would show up in `largest_pieces[]`, not in the map-wide ratio.
- **A degenerate outline is still its own visible piece.** `dilate_outline()`
  returns an empty array for a sub-triangle polygon and the union-find still
  emits a singleton, so a mass that draws nothing is counted as one visible
  piece. Pre-existing; unchanged here.
- **`fabric_fused` and `fabric_confetti` are near-saturated on this tree** (51
  and 42 tiles). A gate that fires on a large share of the map is a weak
  regression detector even when it is correctly derived. They are honest
  measurements of a fused map, but the next stream should expect them to move
  slowly.
- **`tile_20_11` remains unexplained.** The SettlementPlan core planner still
  records 38.5% core coverage where the audit measures 12.01%. Neither repair
  here touches it — and note the per-tile denominator fix did NOT move that tile
  (9 masses, 7 pieces, both before and after), so the two disagreements are
  separate defects.
- **No windowed pixel comparison was run.** A geometry stream held the capture
  lock. The byte-identity claim in section I1 rested on a windowed capture; this
  section's claim rests on the 600-tile / 23-field identity above plus the
  draw-neutrality argument, which is weaker evidence about pixels and is stated
  as such.
