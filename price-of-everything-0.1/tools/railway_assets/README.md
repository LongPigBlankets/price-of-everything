# Railway asset kit

`railway.gd` generates the live 3D railway and its transparent sprite atlas from
one source. The atlas maps all 141 keys in `assets/iso/roads/roads.json` to matching
`rail_` keys, plus 12 tunnel variations (four orientations × three levels).
Per-piece `world_span` in `rails.json` records orthographic framing; do not use the
old road atlas's fixed repeat length for these wider railway curves.

- L1: timber sleepers. L2: concrete sleepers. L3: rail fasteners.
  Every route has two parallel tracks, each with two running rails. The whole pair, including both ballast beds, is 9.45 units wide: the authored
  mid/two-lane road carriageway (12.6 × 0.75). Gauge is constant across levels.
- Degree-two bends use tangent cubic curves. Three-arm junctions connect all
  three arm pairs; four-arm junctions connect all six arm pairs. Each movement
  has two tracks, and both straight and turning movements are present.
  Busier input nodes become staggered turnout ladders, not five-way rail fans.
- Shared/overlapping input segments are split and deduplicated. Running-rail
  intersections have flangeway gaps and check rails; turnouts have point blades
  and an actuator. These are game-scale stylisations, not civil-engineering plans.
- Level 6 means navigation band 7 (the game's bands start at level -1).
  Track, sleepers and ballast are omitted at level 6+, including their width.
  One widened low-side portal spans both tracks at each end of an underground
  interval.
- Roads normally pass beneath the railway; at rail junctions the road spans
  the switchwork instead. Deck soffits have 8.03 world units of
  clearance (roughly 5 m; 85% of a two-lane road width) above the sampled road
  height, with a 1-unit deck. Both approaches use smooth 80-unit transitions.
  Earth fill follows the terrain elevation palette and meets the actual ground
  at its outer foot. Rail grade and road-deck sampling are separate. Elevation envelopes are shared
  across piece boundaries so curves and turnouts do not step down at seams.
- Both `rail` transport routes and `rails` infrastructure use this renderer and
  the existing Rails visibility toggle. Tile infrastructure levels select the art.
  Scenery cache fingerprints include the railway source and infrastructure keys
  include levels, so upgrades and kit edits invalidate their previous meshes.

From the Godot project directory:

```sh
godot --headless --log-file /private/tmp/rail-check.log --path . res://tools/railway_assets/check.tscn
AGENT_GODOT_WINDOW=1 godot --log-file /private/tmp/rail-render.log --path . res://tools/railway_assets/render.tscn -- --no-telemetry
godot --headless --editor --import --quit --path .
```

The render writes `assets/iso/rails/rails.png`, `rails.json`, and a labelled
`outputs/railway-assets/review.png` at repository root. No external textures or
Blender session are required. Tests cover mode dispatch/visibility, all-height-6
suppression, both portals, road clearance and ramp continuity, turnout curvature,
flangeways, deduplication, upgrade differences, paired-track spacing, gap-free
  approach joins, all-direction junction connectivity and complete road-variant coverage.

Reference: Network Rail's description of switches and crossings and check rails:
https://www.networkrail.co.uk/stories/three-track-features-youve-never-heard-of/

## Map-wide network

`rail_network.gd` plans the complete land graph before selecting the current view.
Every land neighbour starts connected. In seeded random tile order, a tile still
connected to all of its original neighbours requests one shared edge removal.
Candidates protect urban neighbours first, then prefer the fewest authored
buildings; equal counts drop mountain before hill before rural. Exact ties use a
stable seeded random draw. A removal is rejected if it disconnects its landmass.
Sea tiles never enter the graph. The current map has 395 land tiles and three
landmasses. These presentation lines do not grant transport upgrades or capacity.

Development comes from the actual top-down authored decorative masses and special
building records, grouped by ID; empty slots, trees and harbour aprons do not count.
Junction positions and bowed links seek clearance from those footprints and water.
Company views clip the same global plan to the visible land boundary. Upgraded
infrastructure still selects the corresponding L1–L3 art without changing width.
Spatial indices keep intersection, road-crossing and bridge-envelope work local.

```sh
godot --headless --log-file /private/tmp/rail-network-check.log --path . res://tools/railway_assets/network_check.tscn
AGENT_GODOT_WINDOW=1 godot --log-file /private/tmp/rail-network-capture.log --path . res://tools/railway_assets/network_capture.tscn -- --no-telemetry --continent-review
```

The network check covers deterministic selection, ranking, reciprocal edges,
landmass connectivity, authored building counts, land-only curves and road width.
The capture waits for the full board build and renders overview, urban and hill views.

Every upland colour band now has its own terrain rise, including level 6.
Regression checks sample all nine plateau heights and verify the lower bridge
clearance, shorter approaches, and elevation-coloured earth fill.

## Road grading, urban tunnels and depots

`road_grade.gd` samples a common centre grade, using the lower side of the
carriageway on a cross-slope. The terrain is cut to that grade, with an 8u shoulder
blend. Road bridges span rail junction movements and use the same clearance and
80u transitions as rail bridges. Their approach fill follows the terrain palette.

`rail_urban.gd` identifies roads with at least two junctions within 80u.
On urban tiles, railway within 20u of those roads goes underground, with a 45u
recessed approach to a portal. Covered tracks, ballast and fittings are omitted.
Rural tracks and separate landmasses retain the existing network rules.

`rail_depot.gd` places one yard on suitable nearby rural land for Stoneshore,
Arin, Capital Port, Vandel’s Skip and Port Lightning. Each shed has six individual
tracks (three pairs); the outer pair branches into two dead-end loading sidings
beside it, with a 3u gap between the shed wall and nearest ballast edge.
One yellow gantry crane straddles the siding ends beyond the rear wall.
The native mesh uses six entrances, roof ribs and skylights, vents and an office.
Yards receive a level earth formation and trees are excluded from their footprint.

```sh
godot --headless --log-file /private/tmp/transport-check.log --path . res://tools/railway_assets/transport_check.tscn
AGENT_GODOT_WINDOW=1 godot --log-file /private/tmp/transport-capture.log --path . res://tools/railway_assets/transport_capture.tscn -- --continent-review --no-telemetry
```

The transport check covers road cross-slope, terrain cuts, junction bridge
clearance and priority, urban-only burial, portals, and the six shed-track ends.
The capture renders the actual map and each of the five rural depots.
