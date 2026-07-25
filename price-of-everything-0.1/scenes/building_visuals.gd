extends Node2D

# Polygon building footprints (polygon-buildings plan, phases 1-3 + phase-2 road snap).
# Each non-forest, non-road building is a coloured SHAPE (square/rect/L×2/squared-C)
# whose AREA is a FIXED amount per tile_size_used point (SIZE_UNIT_AREA) — the same
# building is the same size on every tile, deliberately undersized so a tile never
# fills (Sanborn/Booth look). Placement is now CONTINUOUS, not grid-snapped:
#   • the buildable mask (20u cells) subtracts WATER, ROAD clearance and FOREST canopies;
#   • most buildings pack as a tight ROW along the nearest road frontage — oriented so the
#     long axis runs along the road, snapped flush to the carriageway clearance, and butted
#     up against the previous building with only DESIGN_GAP between them (the 1-2u Sanborn
#     terrace look). Gaps are GEOMETRIC, not weighted — no W_COMPACT.
#   • recycling/extraction INVERT — they seek the far corners, away from everything;
#   • with no road in reach a building abuts its nearest neighbour, else drops to low ground.
# Placement is incremental + stable: a building keeps its spot until demolished.
#
# Ordering note: on a fresh match the seed buildings are emitted BEFORE the road
# network is bootstrapped, so they first lay out with no road data; world_map calls
# relayout() once roads exist to re-snap them to frontage. On load roads are already
# present at re-emit, so relayout() is idempotent there.

const TileViewData := preload("res://scripts/tile_view_data.gd")

# Network infrastructure drawn by its own layer, NOT as a building footprint:
# b_005 roads (RoadNetworkVisuals). b_006 cables regained a footprint
# 2026-07-23 — it draws as the shape-language transformer station.
const NON_FOOTPRINT_IDS := {"b_005": true}
const FOREST_BUILDING_IDS := {"b_015": true, "b_016": true}

# Buildable grid: 27×24 cells of 20u in the tile-local frame, used only for the
# buildable MASK (is this point land?). Placement itself is continuous. The hex is
# FLAT-TOP (verts (135,0)(405,0)(540,240)(405,480)(135,480)(0,240), centre (270,240)).
## Buildable-mask resolution. 5u cells (was 20u): the coarse grid stamped whole
## cells around roads, so a footprint could not legally sit within ~a cell of a
## carriageway no matter what clearance the caller asked for — the reason block
## frontage rows were unbuildable. 16x the cells, so watch world-build time.
const GRID_COLS := 108
const GRID_ROWS := 96
const CELL := 5.0
const TILE_CENTER := Vector2(270.0, 240.0)
const DESIGN_GAP := 1.0              # gap between adjacent footprints / footprint-to-road (tight terrace cling)
const PACK_STEP := 2.0               # scan granularity (u) when walking a frontage for the first free slot
const BUILDABLE_MIN_AREA := 400.0    # never size a footprint below ~1 cell
# Footprint area is a FIXED amount per tile_size_used point, so the same building is the
# same size on every tile — no crowd-dependent shrinking, no overlap. Deliberately
# UNDERSIZED (165 → 100) for the dense Sanborn/Booth look: a size-20 building is ~2000 u²
# ≈ 1% of the ~194k-u² hex, so even a capacity-full tile (~200 pts) draws only ~10%
# footprint. Tune to taste — the ≤50%-of-hex ceiling is the constraint.
const SIZE_UNIT_AREA := 100.0

# Block-subdivision mode: ~BLOCK_PROB% of tiles anchor a "city block" to their straightest
# long road RUN — that road is the block frontage; a grid of lots reaches back from it
# (~15-20% of the tile, free to run up against the tile edge), and only the lots ADJACENT to
# a road get buildings (the deep interior stays an empty courtyard). Buildings claim lots in
# emit order; the rest fall back to the continuous packer. A block only forms where a straight
# road run + room exist, so it self-limits to developed tiles (urban or rural). Works on busy
# tiles (lots of road to anchor to). Deterministic from tile_id; positions are re-derived,
# never persisted. Blocks STAY PUT when a road later settles (only blocked lots fall back).
const BLOCK_PROB := 100              # % of eligible tiles using block mode; lower for variety (block forms only where a road run + room exist)
const BLOCK_MIN_ROAD := 70.0         # need a straight road segment ≥ this (~7u) to anchor a block
const BLOCK_MAX_COLS := 3            # lots along the road (owner: 2x2 or 3x2 blocks only)
const BLOCK_ROWS := 2                # lots deep at first — a block starts 2x2/3x2 and grows a
									 # row at a time (_grow_block_rows) as its lots fill
const BLOCK_MAX_ROWS := 5            # ceiling on growing DEEPER
const BLOCK_MAX_GROWN_COLS := 9      # ceiling on growing ALONG the road (the preferred direction)
const BLOCK_FARM_LIMIT := 2          # this many farms on a tile and its other buildings stop blocking
## Lot pitch (u); axis-aligned so lots pack tight (smaller = denser, more lots).
## THE size lever on developed tiles — they place through the block template,
## which ignores the per-building art lot area. 46 -> 58 puts block buildings
## mid-range of the ART_DRAWN_MIN/MAX band without over-crowding the tile.
const BLOCK_LOT := 44.0
const BLOCK_ROAD_ADJ := 130.0        # a lot is usable within this of a road (~2 frontage rows); deeper interior stays empty
const BLOCK_ROAD_PAD := 7.0          # gap from the road to a block's near edge (tight Sanborn frontage; vs ROAD_CLEAR 18)
const BLOCK_FILL_MIN := 0.85         # smallest building as a fraction of the lot (tight gaps between block buildings)
const BLOCK_FILL_MAX := 0.9          # largest (lots validated at this size)
const BLOCK_MIN_LOTS := 2            # fewer usable lots than this -> skip block mode.
									 # 2, not 3: blocks are now 2x2/3x2 and the frontage row
									 # is unbuildable (mask cells), so a 2-wide block offers 2.
const BLOCK_ASPECT := 0.62           # block building depth as a fraction of its width — LONG side faces the road
const BLOCK_SQUARE_PCT := 25         # % of block buildings kept square (seeded) for variety
# ~CHUNK_PROB% of block tiles (seeded) fill the block with a FEW BIG CHUNKS (3-6) instead of the fine
# lot grid — each building fills its chunk for a dense interior (visual size decoupled from tile_size).
const CHUNK_PROB := 40               # % of block tiles using chunk fill (was the enclosure-seed rate)
const CHUNK_COLS_TARGET := 80.0      # chunk width target along the road → 2-3 columns by run length
const CHUNK_DEPTH := 88.0            # chunk depth (perpendicular) → 1-2 rows deep
const CHUNK_GAP := 4.0               # gap between filled chunks
const BLOCK_DEBUG := false           # set true to log per-tile block decisions to the console ([BLOCKDBG])

const ROAD_CLEAR := 18.0             # no footprint edge may come within this of a road centreline
## The buildable mask is rasterised at this (the tightest frontage any caller
## uses); per-caller distances are enforced in _valid, not by the mask.
const MASK_ROAD_CLEAR := 5.0
## NOTE (audit, 2026-07-23): block-placed buildings sit ~65u from their road and
## cannot currently do better. The block's own frontage row is never buildable:
## _rasterize_seg_clearance stamps whole 20u CELLS around a road, so a footprint
## whose near edge is BLOCK_ROAD_PAD (7u) out still overlaps blocked cells and
## fails _valid — the first usable row is a whole lot back. Tightening the
## road-proximity gate therefore just starves blocks of lots (0-2 usable, below
## BLOCK_MIN_LOTS) rather than pulling them closer.
##
## Service streets were tried and REMOVED (owner): inventing roads to suit
## buildings is backwards, a one-building block got a street to nowhere, and
## unvalidated street geometry drew over the sea. If interior access is ever
## wanted it should grow out of the fronting road along the block's sides, gated
## on the block actually being full.
const ROAD_OVERLAP := 5.0            # relayout: a building is only re-packed if a new road comes THIS close to its footprint (an actual overlap, well inside ROAD_CLEAR) — otherwise it stays put
const RIVER_CLEAR := 16.0            # no footprint edge may come within this of a river arm
const RIVER_ROAD_PAD := 28.0         # reserve a road corridor: buildings keep this off river arms (room for a bank road to the bridge)
const BRIDGE_APPROACH := 50.0        # reserved corridor straight out from each crossing, both banks (~5u "after the bridge")
const ROAD_REACH := 160.0            # clip road geometry to roughly this past the hex
const MIN_BUILD_LEVEL := 0           # NavGrid level below this (the shore fringe, at/under the
									 # waterline) is non-buildable — keeps footprints out of the sea
const W_AWAY := 1.5                  # edge-seekers: weight on distance-from-buildings vs from-centre

const NPC_OUTLINE_W := 2.0                    # farm fields: thin white outline (npc) — buildings use INK
const PLAYER_OUTLINE := Color(0.5, 0.5, 0.5)  # farm fields: 1px medium-grey outline (player)
const PLAYER_OUTLINE_W := 1.0

# ── "Ink & wash" plate look (docs/building-visuals-ink-spec.md, phase I1) ──────
# One dark-sepia ink for EVERY building outline + interior motif; categories
# differentiate by FILL only, inside a muted triad. All variation seeded via
# RoadHash (deterministic across save/load). Farms keep their own field look.
const INK := Color("#3a2c18")
const INK_W := 1.3
const WASH_GREY := Color("#8d8a80")           # extraction / mines
const WASH_RED := Color("#b0483a")            # urban production / default
const WASH_MUSTARD := Color("#c9992e")        # storage / logistics / infrastructure
const WASH_YELLOW := Color("#E3C84A")         # power — matches tile size chart CAT_POWER
const WASH_RUINS := Color("#7a5f43")
# Owner 2026-07-10: restore the pre-ink colour FAMILIES in muted plate shades.
const WASH_NAVY := Color("#5d7285")           # metallurgy (furnaces) — washed steel navy (was #4A7A9B)
const WASH_BLUE := Color("#7ba7bc")           # water — lighter powder blue (was #3A7BD5)
const WASH_PINK := Color("#b57f97")           # refinery — dusty plum-pink (was purple #8E5BC0)
const WASH_ORANGE := Color("#c9803d")         # manufacturing — muted terracotta (was #E08A3C)
const WASH_LIME := Color("#9fae5a")           # electrochemistry (chem plants) — olive lime (was #A6E22E)
const WASH_JITTER := 0.05                     # ±5% per-instance value jitter (seeded)
const NPC_WHITE := Color("#efe9db")           # NPC fill: warm paper white (sits in the parchment)
const SAWTOOTH_PITCH := 12.0                  # factory shed-roof line spacing (u)
const TERRACE_PITCH := 14.0                   # urban party-wall slice spacing (u)
const CHIMNEY_R := 2.2
# Ink & wash phase I2+I4 (spec §2.2/§2.4): compound massing wings + hand-drawn wobble.
const WING_MIN_PARENT_AREA := 140.0           # only halls this big grow wings (u²)
const WING_AREA_MIN := 0.20                   # wing area as a fraction of the parent
const WING_AREA_SPAN := 0.20                  #   … + seeded 0-0.20
const WOBBLE_STEP := 16.0                     # subdivide footprint edges every ~16 u at DRAW time
const WOBBLE_AMP := 1.1                       # perpendicular jitter (u); logic polygon never wobbles
const WOBBLE_MIN_PERIM := 36.0                # tiny shapes stay crisp (jitter reads as noise)
const OFFSHORE_MIN_SEP := 120.0               # sea structures spread at a uniform distance
# Courtyard block-masses (owner rules 2026-07-10): bunches of 5+ adjacent
# same-owner buildings draw as ONE mass; deep masses get an inner courtyard.
# Urban tiles always mass; rural/hill a seeded third; mountains never.
const COURT_MIN_BUNCH := 5
const COURT_ADJ := 10.0            # max footprint gap that still counts as one bunch
const COURT_GROW := 3.5            # inflate-merge-deflate weld margin
const COURT_INSET := 28.0          # courtyard sits this deep inside the mass (needs 2+ rows)
const COURT_MIN_YARD := 400.0      # min courtyard area (u²) — thin L-masses get none
const COURTYARD_FILL := Color("#cfc3a2")   # inner yard ground
const TERRACE_SHADE := 0.05                   # per-strip value overlay so terraces read as houses
const VENT_SIZE := Vector2(4.5, 2.8)          # factory rooftop vent/clerestory rect (u)

# Subcomponents (Sanborn industrial detail): each building gets at most one rect annex + one round
# tank, placed in a SECOND pass after all buildings + roads exist, in spare buildable space beside
# the parent. They AVOID roads (the buildable mask + a clears check) and re-derive when the tile
# changes, so roads never need to avoid THEM. Cosmetic; deterministic from instance_id; never persisted.
# Each building gets at most ONE rectangle annex + ONE round tank, both in the PARENT's colour
# + outline. The annex touches/merges (drawn UNDER the building so the shared edge is hidden);
# the tank sits off with a small gap.
const SUBCOMP_TANK_R := 4.0           # round tank radius (~50 u²)
const SUBCOMP_ANNEX := Vector2(8.0, 5.0)             # annex width, height (~40 u²)
const SUBCOMP_GAP := 2.0              # gap from the parent building (round tank only)
const SUBCOMP_ANNEX_OVERLAP := -2.0   # annex touches/overlaps the parent (merges as an extension)
const MASK_DEBUG := false            # set true to log tiles where the road gate would hide road segs ([MASKDBG])

# Farms (b_014, cat "farm"): irregular polygonal fields that gravitate to the river (or to the
# tile edge if non-farm buildings already crowd the tile), clipped to the hex, hatched dark-green,
# with a brown barn (rect) + silo (circle). Field = light green + 3px dark-green diagonal hatching.
# Field fill + hatch colors live in MapStyle ('toggle ink' swaps them).
const FARM_HATCH_W := 3.0
const FARM_HATCH_SPACING := 12.0                     # gap between hatch lines (u)
const FARM_BARN := Vector2(10.0, 6.0)                # brown barn rect (~size-60 by area, pre-scale)
const FARM_SILO_R := 4.0                             # brown silo circle (pre-scale)
const FARM_BROWN := Color(0.50, 0.33, 0.16)          # barn + silo colour
const FARM_FIELD_SCALE := 3.0          # field rendered 3× linear (≈9× area) — big, clips at hex edge
const FARM_OUTBUILDING_SCALE := 2.1    # barn + silo (3× then 30% smaller), snapped to the plot's road edge
const FARM_MIN_SEP := 70.0             # min farm centre spacing — fields then Voronoi-snap to lanes
const FARM_CROSS_TILE_RADIUS := 440.0  # a neighbour-tile farm within this world radius pulls a new field toward the shared edge
const FARM_FOREST_TOL := 0.7           # farms tolerate forests: excluded only inside 70% of a disc (30% closer)
const FARM_ADJ_MAX := 12.0             # two fields are "adjacent" (share a side, get a lane) within this
const FARM_RING_OFFSET := 6.0          # outer ring sits this far outside the fields (concave hug, not a hull)
const FARM_LANE_COLOR := Color(0.60, 0.54, 0.43)     # thin dirt track between adjacent fields
const FARM_LANE_W := 5.0                             # track width (cosmetic; active RoadNetwork wiring TODO)
const FARM_LANE_REACH := 5.0          # lanes drawn only within this of a field (no cross-tile projection)
const FOREST_RING_NEAR := 32.0        # circumvent a forest (heptagon ring) when it's within this of a field
const FOREST_HEP_MARGIN := 6.0        # heptagon ring sits this far outside the forest disc
const FARM_BRIDGE_COLOR := Color(0.42, 0.36, 0.30)   # deck where a lane crosses a river
const FARM_BRIDGE_W := 6.0
const FARM_BRIDGE_LEN := 20.0
const FARM_ROAD_MERGE_MAX := 120.0    # connect the farm tracks to a real road within this gap (no new road)

## Viewport culling: when no more than this many footprints are on screen (zoomed
## in) draw only the visible ones; above it draw everything once and stay static.
const CULL_CAP := 160
const CULL_MARGIN := 600.0

@onready var terrain_layer: HexMap = %TerrainLayer
@onready var _forest_visuals: Node = get_node_or_null("../ForestVisuals")

# Per-placement: {instance_id, building_id, tile_id, coord, verts, color, is_npc, bb,
#                 cat, center_rel (tile-local, vs TILE_CENTER), half (AABB half-extent)}
var _placements: Array = []
var _placement_index: Dictionary = {}   # instance_id -> index into _placements

# Per-tile caches (built lazily, on first building). All static per tile.
var _tile_land: Dictionary = {}       # tile_id -> PackedByteArray (1 = buildable land cell)
var _tile_landkeys: Dictionary = {}   # tile_id -> PackedInt32Array (buildable cell keys)
var _farm_land: Dictionary = {}       # tile_id -> PackedByteArray: like _tile_land but farms tolerate the
var _farm_landkeys: Dictionary = {}   # outer 30% of forest discs (FARM_FOREST_TOL) — they nestle closer
var _tile_segs: Dictionary = {}       # tile_id -> Array of [a, b] road segments (rel to centre)
var _tile_rivers: Dictionary = {}     # tile_id -> Array of [a, b] river-arm segments (rel to centre)
var _tile_block_mode: Dictionary = {}      # tile_id -> bool (seeded once, urban-only)
var _tile_block_templates: Dictionary = {} # tile_id -> {angle, lots:Array[Vector2], claimed:Array[bool]} ({} = no block)
var _block_streets: Dictionary = {}        # tile_id -> [[world a, world b]] side roads (earned by a 2nd-row build)
var _grew_this_claim := false              # re-entry guard for the grow-and-retry in _claim_slot

# Ancillary tanks/annexes (second pass, re-derived; never persisted). Each: {tile_id, verts (world), color, bb}.
var _subcomponents: Array = []
var _block_masses: Dictionary = {}     # tile_id -> Array[{poly, holes, color, bb, key}]
var _massed_by_tile: Dictionary = {}   # tile_id -> {instance_id: true} — members drawn as ink divisions
var _subcomp_dirty: Dictionary = {}   # tile_id -> true, tiles needing a subcomponent rebuild
var _subcomp_queued := false
# Farm layout (re-derived with subcomponents; never persisted). A field's render shape depends on its
# neighbours (it Voronoi-snaps to the lanes between them), so it is computed per tile, not at placement.
var _farm_render: Dictionary = {}     # instance_id -> {verts (world, cell-clipped), hatch}
var _farm_lanes: Dictionary = {}      # tile_id -> Array of [a, b] lane polylines (world)
var _farm_bridges: Dictionary = {}    # tile_id -> Array of {p (world), dir} where a lane crosses a river
var _farm_promote: Dictionary = {}    # tile_id -> {ring: Array[polyline]} promotion candidate (outer ring)
var _farm_cluster_rings: Dictionary = {}  # tile_id -> Array of closed ring polygons (road snap inside-test)

var _cull := false
var _view := Rect2()
var _warned_no_nav := false

# Bumped on every footprint add/remove so the road realizer's avoidance-disc cache
# (keyed off this) rebuilds — lets roads built later route around buildings.
var footprint_version: int = 0
var _bulk := false                       # begin_bulk()/end_bulk() window (match-start placement)
var _bulk_dirty_tiles: Dictionary = {}   # tile_id -> true; subcomp marks deferred to end_bulk
var farm_lanes_version: int = 0   # bumps when farm tracks change, so the realizer re-caches the corridor

# Tiles whose road settled this frame and whose buildings must re-pack onto the
# new frontage. Coalesced through one deferred flush so a batch of settles (or a
# multi-tile road) triggers a single re-pack pass, not one per settle.
var _resnap_tiles: Dictionary = {}
var _resnap_queued := false

func _ready() -> void:
	add_to_group("building_footprints")
	# When the player's road on a tile actually finishes (RoadWorks settles the
	# edge to STATE_BUILT, ~3 s after the 'roads' infra completes), re-pack that
	# tile so its existing buildings snap to the carriageway. Without this they
	# keep the roadless fallback layout and never visibly align to the new road.
	RoadWorks.order_settled.connect(_on_road_settled)
	# An upgraded building grows annex wings (level-driven compound massing) —
	# re-derive its tile's subcomponents when the new level lands.
	MatchState.building_upgraded.connect(_on_building_upgraded)
	# A bought NPC building swaps to the player's wash (and leaves any NPC
	# block-mass it sat in) the moment ownership changes.
	MatchState.building_owner_changed.connect(_on_building_owner_changed)
	# When RoadWorks promotes a farm tile's outer ring + one path to real roads, stop drawing those
	# brown tracks (the yellow road now represents them).
	if RoadWorks.has_signal("farm_roads_promoted"):
		RoadWorks.farm_roads_promoted.connect(_on_farm_roads_promoted)
	# 'toggle ink' map restyle: farm field/hatch colors come from MapStyle.
	MapStyle.style_changed.connect(queue_redraw)

func _on_farm_roads_promoted(tile_id: String) -> void:
	# Rebuild the tile's layout so the now-promoted ring + trunk are omitted from the brown tracks
	# (the exclusion itself reads RoadWorks.is_farm_promoted, so it's robust to signal ordering on load).
	_mark_subcomp_dirty(tile_id)

## Candidates a road build can promote to real roads: the cluster's outer ring + one through-path.
func farm_promote_candidates(tile_id: String) -> Dictionary:
	return _farm_promote.get(tile_id, {})

## Same, addressed by tile COORD (a settled road knows the coords it crosses, not tile_ids). Returns
## the candidates plus the tile_id, or {} if that coord has no farm.
func farm_promote_candidates_for_coord(coord: Vector2i) -> Dictionary:
	for p in _placements:
		if (p.coord as Vector2i) == coord and str(p.cat) == "farm":
			var c: Dictionary = _farm_promote.get(str(p.tile_id), {})
			if c.is_empty():
				return {}
			var out := c.duplicate()
			out["tile_id"] = str(p.tile_id)
			return out
	return {}

## All farm-track segments on a tile (for the road realizer's follow-the-web cost bias; Stage 2).
func farm_lane_segments(tile_id: String) -> Array:
	return _farm_lanes.get(tile_id, [])

## Every farm-track segment on the map as [a, b] world pairs (multi-point ring polylines are split
## into edges) — the realizer stamps a cheap corridor along these, and the snap builds the web graph.
func all_farm_lane_segments() -> Array:
	var out: Array = []
	for tid in _farm_lanes:
		for poly in (_farm_lanes[tid] as Array):
			var pv: PackedVector2Array = poly
			for i in range(pv.size() - 1):
				out.append([pv[i], pv[i + 1]])
	return out

## Every farm cluster's outer-ring polygon (closed, world) — the road snap uses these to detect where
## a road enters/exits a cluster.
func all_farm_cluster_rings() -> Array:
	var out: Array = []
	for tid in _farm_cluster_rings:
		for ring in (_farm_cluster_rings[tid] as Array):
			out.append(ring)
	return out


func on_building_placed(tile_id: String, building_id: String, _recipe_id: String, instance_id: String, coord: Vector2i) -> void:
	if NON_FOOTPRINT_IDS.has(building_id) or FOREST_BUILDING_IDS.has(building_id):
		return  # roads/cables are networks; forests are drawn by ForestVisuals
	# Re-placement (e.g. a load re-emitting building_placed) must not orphan the old
	# footprint — drop it first so it frees its space and can't ghost.
	if instance_id != "" and _placement_index.has(instance_id):
		remove_instance(instance_id)
	_place_building(instance_id, building_id, tile_id, coord)
	if _bulk:
		_bulk_dirty_tiles[tile_id] = true
		return
	_mark_subcomp_dirty(tile_id)
	queue_redraw()


## Bulk window for the match-start placement pass. Layout is untouched (geometry is
## identical either way); only the per-placement redraw + ancillary rebuild are
## deferred, so ~475 placements cost ONE redraw and one subcomponent rebuild per
## touched tile — redrawing the whole layer per placement was most of the ~60 s
## new-game load.
func begin_bulk() -> void:
	_bulk = true


func end_bulk() -> void:
	_bulk = false
	for tid in _bulk_dirty_tiles:
		_mark_subcomp_dirty(str(tid))
	_bulk_dirty_tiles.clear()
	queue_redraw()

## True once this instance has a drawn footprint — lets the start-building pass skip
## NPC buildings other passes already laid out (ports/ruins/companies).
func has_placement(instance_id: String) -> bool:
	return _placement_index.has(instance_id)

## Lay out one building: size it, pick a shape, and place it (frontage row, else abut a
## neighbour, else low ground). Appends a placement (or nothing if the tile is full).

func _place_building(instance_id: String, building_id: String, tile_id: String, coord: Vector2i) -> void:
	_ensure_tile(tile_id, coord)
	var bd := Catalog.get_building(building_id)
	var types: Array = bd.get("building_type", [])
	# Recycling (internal_name ~ "recycl": b_036 recycling_plant + b_022 water_recycling)
	# and extraction (mines) invert placement — they seek the far tile edges.
	var is_edge: bool = types.has("extraction") \
		or str(bd.get("internal_name", "")).to_lower().contains("recycl") \
		or OFF_ROAD_NAMES.has(str(bd.get("internal_name", "")))
	var cat := TileViewData.category_key(bd)
	var size_units := int(bd.get("tile_size_used", 1))
	# Fixed area per size point (see SIZE_UNIT_AREA): consistent on every tile, no
	# crowd-dependent shrink, undersized so the tile never fills.
	var area := maxf(float(size_units) * SIZE_UNIT_AREA, BUILDABLE_MIN_AREA)
	# Shape-language buildings reserve an ART-SIZED lot — placement must
	# separate what is drawn, not the old undersized plates. Lot side scales
	# with tile_size_used between the min and 3x-min classes.
	var iname_lot := str(bd.get("internal_name", ""))
	var has_art := INK_ART_KEY.has(iname_lot)
	if has_art:
		var side := _art_size_for(size_units, str(INK_ART_KEY.get(iname_lot, "")))
		area = maxf(area, side * side)
	# Art buildings keep QUAD footprints: the composition is rect-framed, and
	# an L/C footprint's notch — legally occupied by a neighbour — would sit
	# under the art (the residual start-tile overlap the owner reported).
	var kind: String = BuildingShapes.KINDS[RoadHash.pick("poly|%s|%s|kind" % [tile_id, instance_id], 2 if has_art else BuildingShapes.KINDS.size())]
	var seed_v := RoadHash.pick("poly|%s|%s|var" % [tile_id, instance_id], 9)
	var placed_here := _placed_on_tile(tile_id)

	# Block-subdivision (seeded urban tiles): claim a lot first; the continuous packer is
	# the fallback for every building the grid can't take (full / blocked). Edge-seekers
	# (mines/recycling) skip the central block and keep their far-corner behaviour; farms
	# never block-lot either — they own a polygonal field placed by _search's farm branch.
	var placed := {}
	# Offshore structures (wind farm, oil platform) sit ON WATER — the land
	# mask can't place them at all. Uniform spread, no roads/frontage rules
	# (owner 2026-07-10: sea buildings keep a uniform distance apart).
	var offshore := str(bd.get("internal_name", "")).to_lower().begins_with("offshore")
	if offshore:
		placed = _place_offshore(coord, area, placed_here)
	elif not is_edge and cat != "farm" and _use_block_mode(tile_id, coord):
		var tmpl := _ensure_block_template(tile_id, coord)
		if not tmpl.is_empty():
			placed = _claim_slot(tmpl, size_units, coord, tile_id, placed_here)
	if placed.is_empty() and not offshore:
		# Art buildings front the road tightly (edge ~1u off the carriageway).
		var rc := ART_ROAD_PAD if has_art else ROAD_CLEAR
		var akey := str(INK_ART_KEY.get(iname_lot, ""))
		placed = _search(tile_id, coord, kind, area, seed_v, cat, is_edge, placed_here, rc,
			_sprite_lot_verts(size_units, akey))
		# Dense tiles (Stoneshore Docks runs 100+ buildings): rather than
		# silently vanishing, art buildings retry with smaller lots — the
		# city packs tighter and the art just draws smaller (strokes stay
		# constant-width regardless).
		if placed.is_empty() and has_art:
			# Two steps only: each retry is a full grid search, and at 557
			# buildings a five-step ladder made the world build minutes long.
			# 0.6 still reads; 0.3 is the last resort before going undrawn.
			for shrink in [0.6, 0.3]:
				placed = _search(tile_id, coord, kind, area * float(shrink), seed_v, cat, is_edge, placed_here, rc,
					_sprite_lot_verts(size_units, akey, sqrt(float(shrink))))
				if not placed.is_empty():
					placed["shrink"] = shrink
					break
	if placed.is_empty():
		return  # tile too crowded to fit it — not drawn rather than overlapping

	if has_art:
		_crop_to_sprite(placed, size_units, str(INK_ART_KEY.get(iname_lot, "")))
	var verts: PackedVector2Array = placed.verts
	# Farms carry BOTH looks baked once (clipped to the — possibly hex-cut —
	# field): the classic 45° green hatch and the ink-mode parcel fabric
	# (P3b). The style toggle just picks which set to draw — no re-bake.
	var hatch: Array = _bake_farm_hatch(verts) if cat == "farm" else []
	var parcels: Dictionary = _bake_farm_parcels(verts) if cat == "farm" else {}
	var iname := str(bd.get("internal_name", ""))
	if INK_ART_KEY.has(iname):
		_ink_art_iid[str(instance_id)] = true
	var placement := {
		"instance_id": instance_id,
		"building_id": building_id,
		"tile_id": tile_id,
		"coord": coord,
		"verts": verts,
		"color": TileViewData.category_color(bd),
		"is_npc": not MatchState.is_player_owned(MatchState.get_building(instance_id)),
		"bb": _verts_bb(verts).grow(NPC_OUTLINE_W),
		"cat": cat,
		"iname": iname,
		"size_units": size_units,
		"via": str(placed.get("via", "block" if not offshore else "offshore")),
		"shrink": float(placed.get("shrink", 1.0)),
		"diag": placed.get("diag", {}),
		"center_rel": placed.center_rel,
		"half": placed.half,
		"hatch": hatch,
		"parcels": parcels,
		"offshore": bool(placed.get("offshore", false)),
	}
	if instance_id != "":
		_placement_index[instance_id] = _placements.size()
	_placements.append(placement)
	footprint_version += 1

## True if this (urban) tile uses the slot-grid block mode. Seeded once per tile_id, cached.
func _use_block_mode(tile_id: String, _coord: Vector2i) -> bool:
	# Any tile (seeded). A block only actually FORMS where there's a straight road run + room
	# (_build_block_template returns {} otherwise), so this self-limits to developed/connected
	# tiles regardless of urban/rural. Tune BLOCK_PROB for how many eligible tiles block.
	if not _tile_block_mode.has(tile_id):
		_tile_block_mode[tile_id] = RoadHash.pick("blockmode|%s" % tile_id, 100) < BLOCK_PROB
	if not bool(_tile_block_mode[tile_id]):
		return false
	# Farmland reads as fields with steadings among them, not as a factory
	# grid dropped between the fields (owner). Once a tile carries more than
	# one farm, its non-farm buildings go back to the continuous packer, which
	# tucks them along the roads instead of laying a block. Counted live rather
	# than cached: the first building on a tile usually predates its farms.
	return _tile_farm_count(tile_id) < BLOCK_FARM_LIMIT

## How many farms are already placed on this tile.
func _tile_farm_count(tile_id: String) -> int:
	var n := 0
	for p in _placements:
		if str(p.get("cat", "")) == "farm" and str(p.get("tile_id", "")) == tile_id:
			n += 1
			if n >= BLOCK_FARM_LIMIT:
				return n
	return n

func _ensure_block_template(tile_id: String, coord: Vector2i) -> Dictionary:
	if _tile_block_templates.has(tile_id):
		return _tile_block_templates[tile_id]
	var tmpl := _build_block_template(tile_id, coord)
	# Cache only a REAL block. An empty result (no road yet / no room) is NOT cached, so the
	# next building — or the road-settle re-pack — retries. Otherwise a tile built up BEFORE
	# its road gets a permanent empty template and never blocks even once the road arrives.
	if not tmpl.is_empty():
		_tile_block_templates[tile_id] = tmpl
	return tmpl

## Public: build/cache this tile's block template if a road run + room exist; true when a real grid formed.
## Ensures the tile's land mask first so the template can validate lots. (Used by tests; gameplay builds
## the template lazily via _ensure_tile.)
func ensure_block_template_for(tile_id: String, coord: Vector2i) -> bool:
	_ensure_tile(tile_id, coord)
	return not _ensure_block_template(tile_id, coord).is_empty()

## Public: world centre (footprint bbox centre) of a placed building, or the tile centre when not placed.
func footprint_center_for(instance_id: String, coord: Vector2i) -> Vector2:
	if _placement_index.has(instance_id):
		return _verts_bb(_placements[int(_placement_index[instance_id])].verts).get_center()
	return _tile_center_world_pos(coord)

## Anchor a city block to the straightest long road segment on the tile: that road is the
## block frontage; a grid of lots reaches back from it (free to run up against the tile edge
## — out-of-hex/water cells just drop), and only the lots ADJACENT to a road are kept (the
## deep interior stays an empty courtyard). Axis-aligned (snapped 90°) so lots pack tight.
## Returns {angle, lots, claimed} or {} when there's no anchor road / too few usable lots.
func _build_block_template(tile_id: String, coord: Vector2i) -> Dictionary:
	var land: PackedByteArray = _tile_land.get(tile_id, PackedByteArray())
	if land.is_empty():
		return {}
	var segs: Array = _block_road_segments(coord)   # ungated: any road crossing the tile (validation + adjacency)
	var rivers: Array = _tile_rivers.get(tile_id, [])
	# Road-ENCLOSED pockets get first claim (owner 2026-07-10): when the
	# streets already bound an interior area, the lot grid anchors INSIDE it,
	# so the tile's buildings fill the block the roads drew — without touching
	# the roads (lots keep the same clearance validation as everywhere else).
	var pocket := _enclosed_pocket(tile_id, coord, segs)
	if not pocket.is_empty():
		var ptmpl := _pocket_template(pocket, land, segs, rivers)
		if not ptmpl.is_empty():
			if BLOCK_DEBUG: print("[BLOCKDBG] %s: POCKET block — %d lots inside a road-enclosed area" % [tile_id, (ptmpl.lots as Array).size()])
			return ptmpl
	# anchor on the longest near-STRAIGHT RUN of road (a single polyline segment is tiny).
	var anchor := _longest_straight_road(coord)
	if anchor.is_empty():
		if BLOCK_DEBUG: print("[BLOCKDBG] %s: no straight road run >= %du (segs on tile=%d)" % [tile_id, int(BLOCK_MIN_ROAD), segs.size()])
		return {}   # no straight road run to anchor a block — caller uses the continuous packer
	var ra: Vector2 = anchor[0]
	var rb: Vector2 = anchor[1]
	var best_len := ra.distance_to(rb)
	# Block aligns to the ACTUAL road tilt (not 90-snapped): the lot grid, the buildings' long side, and
	# the enclosure all run along the road. Normalised to [-90,90) (rect period) so the long side is
	# parallel to the road; for a near-square block this reads as a ±45 tilt.
	var angle: float = wrapf((rb - ra).angle(), -PI * 0.5, PI * 0.5)
	var tangent := Vector2.RIGHT.rotated(angle)
	var normal := Vector2(-tangent.y, tangent.x)
	# validate lots at the LARGEST building so any claimer fits.
	var vfull := BLOCK_LOT * BLOCK_FILL_MAX
	var vrect: PackedVector2Array = _rotate(BuildingShapes.make_rect(vfull, vfull).verts, angle)
	var vhalf: Vector2 = _aabb_half(vrect)
	# build on whichever side of the road carries land; frontage row sits flush to clearance.
	# First row hugs the road. The +epsilon matters: landing the near edge exactly
	# on BLOCK_ROAD_PAD put it on the clearance test's boundary, where it failed —
	# so the frontage row was never buildable and the block started a lot back.
	var frontage := BLOCK_ROAD_PAD + 2.0 + BLOCK_LOT * BLOCK_FILL_MAX * 0.5
	var mid := (ra + rb) * 0.5
	if not _valid(mid + normal * frontage, vrect, vhalf, [], land, segs, rivers, BLOCK_ROAD_PAD):
		normal = -normal
	# ~CHUNK_PROB% of block tiles (seeded) fill the block with a few BIG chunks (one building per
	# chunk) for a dense interior. Same template shape + a `cell` field; fine grid if too cramped.
	# (Seed key kept from the retired enclosure system so tile picks stay stable.)
	if RoadHash.pick("enclseed|%s" % tile_id, 100) < CHUNK_PROB:
		var chunk := _chunk_template(best_len, mid, tangent, normal, angle, land, segs, rivers)
		if not chunk.is_empty():
			return chunk
	# 3 along the road when the run allows, else 2 — so a block is 3x2 or 2x2.
	var cols: int = clampi(int(best_len / BLOCK_LOT), 2, BLOCK_MAX_COLS)
	var origin := ra + tangent * (BLOCK_LOT * 0.5) + normal * frontage
	var lots: Array = []
	var rows: Array = []   # row index per lot — a 2nd-row build earns the side roads
	for r in BLOCK_ROWS:
		for c in cols:
			var ctr: Vector2 = origin + tangent * (float(c) * BLOCK_LOT) + normal * (float(r) * BLOCK_LOT)
			if not _valid(ctr, vrect, vhalf, [], land, segs, rivers, BLOCK_ROAD_PAD):
				continue
			if _cell_near_road(ctr, segs):   # only road-facing lots; the interior stays empty
				lots.append(ctr)
				rows.append(r)
	if lots.size() < BLOCK_MIN_LOTS:
		if BLOCK_DEBUG: print("[BLOCKDBG] %s: only %d usable lots (run=%.0fu cols=%d) — need %d" % [tile_id, lots.size(), best_len, cols, BLOCK_MIN_LOTS])
		return {}
	var claimed: Array = []
	for _i in lots.size():
		claimed.append(false)
	if BLOCK_DEBUG: print("[BLOCKDBG] %s: BLOCK formed — %d lots (run=%.0fu cols=%d)" % [tile_id, lots.size(), best_len, cols])
	return {"angle": angle, "lots": lots, "claimed": claimed, "segs": segs, "rows": rows,
		"origin": origin, "tangent": tangent, "normal": normal, "cols": cols, "frontage": frontage}


## A few BIG chunks filling the block box (enclosure-seeded tiles): C cols along the road (2-3 by run length)
## x R rows deep (1-2), 3-6 total. Each cell is sized so its building FILLS it (`_claim_slot` reads `cell`),
## for a dense interior the enclosure ring hugs. Returns {angle, lots, claimed, segs, cell} or {} (too cramped).
func _chunk_template(best_len: float, mid: Vector2, tangent: Vector2, normal: Vector2, angle: float, land: PackedByteArray, segs: Array, rivers: Array) -> Dictionary:
	var w := clampf(best_len, ENCL_MIN_U, ENCL_MAX_U)
	var base: int = clampi(int(round(w / CHUNK_COLS_TARGET)), 2, 3)   # cols by run width → ~70-80u chunks
	# Coarse-to-FINE grids, packed into a TIGHT block. A 2-row block of BIG cells is ideal, but real
	# urban/port tiles have DENSE crossing roads (the Stoneshore hub measured ~200 road segments) that no
	# big cell can clear — and a river or hex edge can cut a row too. So step the grid finer (more, smaller
	# cells), and at each step take the largest all-valid axis-aligned SUB-RECTANGLE (one clean road-free
	# pocket), NOT every scattered valid cell — otherwise the ring spans far-apart cells with gaps between
	# (the "loose, oversized ring" look). Take the COARSEST grid whose pocket fills the block (>=3 cells —
	# biggest cells win); else the densest pocket that fits. Floor of 2 — still a real filled block.
	var combos: Array = [[base, 2], [base, 1], [base + 1, 2], [base + 1, 3], [base + 2, 2], [base + 2, 3]]
	var best_lots: Array = []
	var best_cell := Vector2.ZERO
	for combo in combos:
		var cols: int = combo[0]
		var rows: int = combo[1]
		var celly: float = minf(ENCL_MAX_V, CHUNK_DEPTH * 1.3) if rows == 1 else (ENCL_MAX_V / float(rows))
		var cell := Vector2(w / float(cols), celly)
		var frontage := BLOCK_ROAD_PAD + cell.y * 0.5
		var origin := mid - tangent * (float(cols - 1) * cell.x * 0.5) + normal * frontage
		var crect: PackedVector2Array = _rotate(BuildingShapes.make_rect(cell.x - CHUNK_GAP, cell.y - CHUNK_GAP).verts, angle)
		var ctrs: Array = []    # ctrs[r][c] — cell centre
		var valid: Array = []   # valid[r][c] — road/water/edge-free
		for r in rows:
			var crow: Array = []
			var vrow: Array = []
			for c in cols:
				var ctr: Vector2 = origin + tangent * (float(c) * cell.x) + normal * (float(r) * cell.y)
				crow.append(ctr)
				vrow.append(_chunk_valid(ctr, crect, land, segs, rivers))
			ctrs.append(crow)
			valid.append(vrow)
		var lots: Array = []
		for ij in _largest_valid_rect(valid, cols, rows):
			lots.append(ctrs[(ij as Vector2i).y][(ij as Vector2i).x])
		if lots.size() >= 3:
			best_lots = lots
			best_cell = cell
			break   # coarsest grid whose pocket fills the block — take it (prefers the biggest cells that fit)
		if lots.size() > best_lots.size():
			best_lots = lots
			best_cell = cell
	if best_lots.size() < 2:
		return {}   # genuinely too cramped (water/road/edge) — caller uses the fine grid
	var claimed: Array = []
	for _i in best_lots.size():
		claimed.append(false)
	return {"angle": angle, "lots": best_lots, "claimed": claimed, "segs": segs, "cell": best_cell}

## The largest all-valid axis-aligned sub-rectangle of a rows x cols boolean grid, as Vector2i(col, row) cells.
## Used to pack chunks into ONE clean road-free pocket (a tight block) rather than every scattered free cell.
## Grids are tiny (<=5x3), so the O(n^4) brute force over corner pairs is trivial.
func _largest_valid_rect(valid: Array, cols: int, rows: int) -> Array:
	var best: Array = []
	for r1 in rows:
		for r2 in range(r1, rows):
			for c1 in cols:
				for c2 in range(c1, cols):
					var all_valid := true
					for r in range(r1, r2 + 1):
						for c in range(c1, c2 + 1):
							if not bool(valid[r][c]):
								all_valid = false
								break
						if not all_valid:
							break
					if all_valid and (r2 - r1 + 1) * (c2 - c1 + 1) > best.size():
						var cells: Array = []
						for r in range(r1, r2 + 1):
							for c in range(c1, c2 + 1):
								cells.append(Vector2i(c, r))
						best = cells
	return best

## STATE_BUILT road segments crossing this tile, centre-relative — like _tile_road_segments
## but NOT gated on the per-tile "roads" infra flag (which only 3 of 92 urban tiles have at
## start). A city block anchors to ANY road the player sees crossing the tile (baked spine,
## NPC connects, player roads), so blocks form wherever there's a street, not just on the
## handful of tiles where the "roads" infrastructure was explicitly built.
## The largest road-enclosed interior region of the tile: flood the cell grid
## from the hex rim with road-clearance cells blocking; buildable cells the
## flood never reaches are enclosed by roads on all sides. Returns
## {cells: Array[Vector2 rel], center: Vector2} or {} (none big enough).
func _enclosed_pocket(tile_id: String, _coord: Vector2i, segs: Array) -> Dictionary:
	var land: PackedByteArray = _tile_land.get(tile_id, PackedByteArray())
	if land.is_empty():
		return {}
	var road_block := _rasterize_seg_clearance(segs, ROAD_CLEAR)
	var n := GRID_COLS * GRID_ROWS
	var in_hex := PackedByteArray()
	in_hex.resize(n)
	for row in GRID_ROWS:
		for col in GRID_COLS:
			var rel := Vector2((col + 0.5) * CELL, (row + 0.5) * CELL) - TILE_CENTER
			if absf(rel.x) > 270.0 or absf(rel.y) > 240.0 or 240.0 * absf(rel.x) + 135.0 * absf(rel.y) > 64800.0:
				continue
			in_hex[row * GRID_COLS + col] = 1
	# BFS from every rim cell (an in-hex cell with an out-of-hex neighbour).
	var reached := PackedByteArray()
	reached.resize(n)
	var queue: Array[int] = []
	for row2 in GRID_ROWS:
		for col2 in GRID_COLS:
			var key := row2 * GRID_COLS + col2
			if in_hex[key] == 0 or road_block[key] == 1:
				continue
			var rim := row2 == 0 or row2 == GRID_ROWS - 1 or col2 == 0 or col2 == GRID_COLS - 1
			if not rim:
				for nb in [key - 1, key + 1, key - GRID_COLS, key + GRID_COLS]:
					if in_hex[nb] == 0:
						rim = true
						break
			if rim and reached[key] == 0:
				reached[key] = 1
				queue.append(key)
	var qi := 0
	while qi < queue.size():
		var k := queue[qi]
		qi += 1
		for nb2 in [k - 1, k + 1, k - GRID_COLS, k + GRID_COLS]:
			if nb2 < 0 or nb2 >= n:
				continue
			if absi((nb2 % GRID_COLS) - (k % GRID_COLS)) > 1:
				continue   # row wrap
			if in_hex[nb2] == 0 or road_block[nb2] == 1 or reached[nb2] == 1:
				continue
			reached[nb2] = 1
			queue.append(nb2)
	# Enclosed BUILDABLE cells, grouped into components; take the largest.
	var comp := PackedInt32Array()
	comp.resize(n)
	for ci in n:
		comp[ci] = -1
	var comps: Array = []
	for key3 in n:
		if in_hex[key3] == 0 or road_block[key3] == 1 or reached[key3] == 1 or land[key3] == 0 or comp[key3] != -1:
			continue
		var cells: Array = []
		var q2: Array[int] = [key3]
		comp[key3] = comps.size()
		while not q2.is_empty():
			var k2: int = q2.pop_back()
			cells.append(k2)
			for nb3 in [k2 - 1, k2 + 1, k2 - GRID_COLS, k2 + GRID_COLS]:
				if nb3 < 0 or nb3 >= n or comp[nb3] != -1:
					continue
				if absi((nb3 % GRID_COLS) - (k2 % GRID_COLS)) > 1:
					continue
				if in_hex[nb3] == 0 or road_block[nb3] == 1 or reached[nb3] == 1 or land[nb3] == 0:
					continue
				comp[nb3] = comps.size()
				q2.append(nb3)
		comps.append(cells)
	var best: Array = []
	for c in comps:
		if (c as Array).size() > best.size():
			best = c
	if best.size() < 6:   # under ~2400 u² there is no block to fill
		return {}
	var rels: Array = []
	var centroid := Vector2.ZERO
	for key4 in best:
		var rel4 := Vector2(((int(key4) % GRID_COLS) + 0.5) * CELL, ((int(key4) / GRID_COLS) + 0.5) * CELL) - TILE_CENTER
		rels.append(rel4)
		centroid += rel4
	centroid /= float(rels.size())
	return {"cells": rels, "center": centroid}

## Lot grid over an enclosed pocket, aligned to the street nearest its centre.
func _pocket_template(pocket: Dictionary, land: PackedByteArray, segs: Array, rivers: Array) -> Dictionary:
	var centroid: Vector2 = pocket.center
	var best_d := 1.0e30
	var angle := 0.0
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var d := _pt_seg_dist(centroid, a, b)
		if d < best_d:
			best_d = d
			angle = wrapf((b - a).angle(), -PI * 0.5, PI * 0.5)
	var tangent := Vector2.RIGHT.rotated(angle)
	var normal := Vector2(-tangent.y, tangent.x)
	var tmin := 1.0e30
	var tmax := -1.0e30
	var nmin := 1.0e30
	var nmax := -1.0e30
	for rel in (pocket.cells as Array):
		var t := (rel as Vector2).dot(tangent)
		var nn := (rel as Vector2).dot(normal)
		tmin = minf(tmin, t)
		tmax = maxf(tmax, t)
		nmin = minf(nmin, nn)
		nmax = maxf(nmax, nn)
	var vfull := BLOCK_LOT * BLOCK_FILL_MAX
	var vrect: PackedVector2Array = _rotate(BuildingShapes.make_rect(vfull, vfull).verts, angle)
	var vhalf: Vector2 = _aabb_half(vrect)
	var cols := clampi(int((tmax - tmin) / BLOCK_LOT) + 1, 1, 6)
	var rows := clampi(int((nmax - nmin) / BLOCK_LOT) + 1, 1, 6)
	var lots: Array = []
	for r in rows:
		for c in cols:
			var ctr := tangent * (tmin + (float(c) + 0.5) * BLOCK_LOT) + normal * (nmin + (float(r) + 0.5) * BLOCK_LOT)
			if not _valid(ctr, vrect, vhalf, [], land, segs, rivers, BLOCK_ROAD_PAD):
				continue
			# The lot must genuinely sit in the pocket (not spill past its rim).
			var near_cell := false
			for rel2 in (pocket.cells as Array):
				if ctr.distance_to(rel2) <= CELL * 1.2:
					near_cell = true
					break
			if near_cell:
				lots.append(ctr)
	if lots.size() < BLOCK_MIN_LOTS:
		return {}
	var claimed: Array = []
	for _i in lots.size():
		claimed.append(false)
	return {"angle": angle, "lots": lots, "claimed": claimed, "segs": segs}

func _block_road_segments(coord: Vector2i) -> Array:
	var out: Array = []
	var net := RoadNetwork.instance()
	if net == null:
		return out
	var center := _tile_center_world_pos(coord)
	var limx := 270.0 + ROAD_REACH
	var limy := 240.0 + ROAD_REACH
	for edge_id in net.edges_on_tile(coord):
		var edge: Dictionary = net.edges.get(edge_id, {})
		if str(edge.get("state", "")) != RoadNetwork.STATE_BUILT:
			continue
		var geo: PackedVector2Array = edge.get("geometry", PackedVector2Array())
		for i in range(geo.size() - 1):
			var a := geo[i] - center
			var b := geo[i + 1] - center
			if (absf(a.x) > limx and absf(b.x) > limx) or (absf(a.y) > limy and absf(b.y) > limy):
				continue
			out.append([a, b])
	return out

func _in_tile_hex(p: Vector2, center: Vector2) -> bool:
	var r := p - center
	return absf(r.x) <= 270.0 and absf(r.y) <= 240.0 and 240.0 * absf(r.x) + 135.0 * absf(r.y) <= 64800.0

## The longest near-STRAIGHT run of road touching this tile (centre-relative [a, b]), or []
## when none reaches BLOCK_MIN_ROAD. Road polylines are finely sampled (~12u per segment), so
## a single segment is tiny — a block must anchor to a straight RUN of many segments (the
## "least wiggle, straight for >7u" frontage), not one segment.
func _longest_straight_road(coord: Vector2i) -> Array:
	var net := RoadNetwork.instance()
	if net == null:
		return []
	var center := _tile_center_world_pos(coord)
	var best_a := Vector2.ZERO
	var best_b := Vector2.ZERO
	var best_len := 0.0
	for edge_id in net.edges_on_tile(coord):
		var edge: Dictionary = net.edges.get(edge_id, {})
		if str(edge.get("state", "")) != RoadNetwork.STATE_BUILT:
			continue
		var geo: PackedVector2Array = edge.get("geometry", PackedVector2Array())
		var i := 0
		while i < geo.size() - 1:
			var dir := (geo[i + 1] - geo[i]).normalized()
			var j := i + 1
			while j < geo.size() - 1:
				if dir.dot((geo[j + 1] - geo[j]).normalized()) < 0.97:   # ~14° turn ends the run
					break
				j += 1
			# CLIP the straight run to the part INSIDE this tile (a straight line crosses a
			# convex hex once, so its in-hex points form one contiguous stretch). Without this
			# a road that runs straight across several tiles reports a huge multi-tile run and
			# the grid anchors far outside the tile — every lot then falls out of the hex.
			var lo := -1
			var hi := -1
			for k in range(i, j + 1):
				if _in_tile_hex(geo[k], center):
					if lo < 0:
						lo = k
					hi = k
			if lo >= 0 and hi > lo:
				var l := geo[lo].distance_to(geo[hi])
				if l > best_len:
					best_len = l
					best_a = geo[lo]
					best_b = geo[hi]
			i = maxi(j, i + 1)
	if best_len < BLOCK_MIN_ROAD:
		return []
	return [best_a - center, best_b - center]

## A lot is usable only if it sits within BLOCK_ROAD_ADJ of some road segment (so buildings
## line the streets and the deep interior of the block stays empty).
func _cell_near_road(center: Vector2, segs: Array) -> bool:
	for s in segs:
		if _pt_seg_dist(center, s[0], s[1]) <= BLOCK_ROAD_ADJ:
			return true
	return false

## Claim the next free lot (emit order) for one building. Returns {verts, center_rel, half}
## or {} when the block is full or the lot is now blocked (caller falls back to _search).
func _claim_slot(tmpl: Dictionary, size_units: int, coord: Vector2i, tile_id: String, placed_here: Array) -> Dictionary:
	var lots: Array = tmpl.lots
	var claimed: Array = tmpl.claimed
	var angle: float = tmpl.angle
	var segs: Array = tmpl.get("segs", [])
	var rivers: Array = _tile_rivers.get(tile_id, [])
	var land: PackedByteArray = _tile_land.get(tile_id, PackedByteArray())
	var cell: Vector2 = tmpl.get("cell", Vector2.ZERO)   # chunk tiles: the building FILLS the cell
	var fill: float = BLOCK_LOT * clampf(BLOCK_FILL_MIN + 0.04 * float(size_units), BLOCK_FILL_MIN, BLOCK_FILL_MAX)
	for i in lots.size():
		if bool(claimed[i]):
			continue
		var ctr: Vector2 = lots[i]
		var rv: PackedVector2Array
		if cell != Vector2.ZERO:
			# CHUNK: the building fills its whole cell (long side already along the road via the box).
			rv = _rotate(BuildingShapes.make_rect(cell.x - CHUNK_GAP, cell.y - CHUNK_GAP).verts, angle)
		else:
			# Fine lot: longest side along the road (rect with width along the tangent), or square for a seeded few.
			var aspect: float = 1.0 if RoadHash.pick("blkaspect|%s|%d" % [tile_id, i], 100) < BLOCK_SQUARE_PCT else BLOCK_ASPECT
			rv = _rotate(BuildingShapes.make_rect(fill, fill * aspect).verts, angle)
		var half: Vector2 = _aabb_half(rv)
		# Chunks use the RELAXED validation (the big footprint may overlap a forest/road-clearance edge but
		# must stay in-hex + off road/river centrelines). NO AABB-overlap check — the chunk grid is
		# non-overlapping by construction, and rotated cells' AABBs falsely collide. Fine lots: strict check.
		var ok: bool = _chunk_valid(ctr, rv, land, segs, rivers) if cell != Vector2.ZERO else _valid(ctr, rv, half, placed_here, land, segs, rivers, BLOCK_ROAD_PAD)
		if not ok:
			claimed[i] = true   # blocked (a road moved onto it, or a fallback sits there) — consume it
			continue
		claimed[i] = true
		_grow_block_rows(tmpl, tile_id, coord)   # keep spare lots ahead of demand
		# Occupying a lot behind the frontage row is what earns the block its
		# side roads — they are access to something, not decoration.
		if int((tmpl.get("rows", []) as Array)[i] if i < (tmpl.get("rows", []) as Array).size() else 0) >= 1:
			_ensure_block_side_roads(tmpl, tile_id, coord)
		return _finalize(coord, ctr, rv, half)
	# Every lot is spoken for — but lots are also consumed when they turn out to
	# be blocked, and that path never reaches the growth call above. Grow now and
	# retry once, or a block quietly stops accepting buildings the moment its
	# last lot is invalidated rather than claimed.
	if not _grew_this_claim:
		_grew_this_claim = true
		_grow_block_rows(tmpl, tile_id, coord)
		var out := _claim_slot(tmpl, size_units, coord, tile_id, placed_here)
		_grew_this_claim = false
		return out
	return {}

## Add another row of lots behind the block once the existing ones are (nearly)
## all taken, so a tile that keeps building keeps packing into its block instead
## of scattering the overflow across the tile (owner report, tile_6_12). Rows
## are added one at a time and only where they validate, so the block grows into
## the space it actually has.
func _grow_block_rows(tmpl: Dictionary, tile_id: String, coord: Vector2i) -> void:
	if not tmpl.has("origin"):
		return
	for c in (tmpl.claimed as Array):
		if not bool(c):
			return   # a lot is still free — nothing to grow yet
	var col_min := int(tmpl.get("col_min", 0))
	var col_max := int(tmpl.get("col_max", int(tmpl.get("cols", 2)) - 1))
	var row_max := int(tmpl.get("row_max", BLOCK_ROWS - 1))
	# Grow ALONG THE ROAD first and only go deeper as a last resort: depth runs
	# out within a row or two (hex edge, water, road clearance) while a road run
	# usually has frontage to spare, and a lot on the frontage is worth more
	# than one buried behind the block.
	var rows_span: Array = range(0, row_max + 1)
	if col_max - col_min + 1 < BLOCK_MAX_GROWN_COLS:
		if _append_block_lots(tmpl, tile_id, coord, [col_max + 1], rows_span) > 0:
			tmpl["col_max"] = col_max + 1
			return
		if _append_block_lots(tmpl, tile_id, coord, [col_min - 1], rows_span) > 0:
			tmpl["col_min"] = col_min - 1
			return
	if row_max < BLOCK_MAX_ROWS - 1:
		if _append_block_lots(tmpl, tile_id, coord, range(col_min, col_max + 1), [row_max + 1]) > 0:
			tmpl["row_max"] = row_max + 1

## Append every valid lot at the given (col, row) cells. Returns how many landed.
func _append_block_lots(tmpl: Dictionary, tile_id: String, coord: Vector2i, cols_range, rows_range) -> int:
	var origin: Vector2 = tmpl.origin
	var tangent: Vector2 = tmpl.tangent
	var normal: Vector2 = tmpl.normal
	var angle: float = tmpl.angle
	var land: PackedByteArray = _tile_land.get(tile_id, PackedByteArray())
	var segs: Array = tmpl.get("segs", [])
	var rivers: Array = _tile_rivers.get(tile_id, [])
	var vfull := BLOCK_LOT * BLOCK_FILL_MAX
	var vrect: PackedVector2Array = _rotate(BuildingShapes.make_rect(vfull, vfull).verts, angle)
	var vhalf: Vector2 = _aabb_half(vrect)
	var added := 0
	for c in cols_range:
		for r in rows_range:
			var ctr: Vector2 = origin + tangent * (float(c) * BLOCK_LOT) + normal * (float(r) * BLOCK_LOT)
			if not _valid(ctr, vrect, vhalf, [], land, segs, rivers, BLOCK_ROAD_PAD):
				continue
			if not _footprint_dry(ctr, vrect, coord):
				continue
			(tmpl.lots as Array).append(ctr)
			(tmpl.claimed as Array).append(false)
			(tmpl.rows as Array).append(r)
			added += 1
	return added

## Side roads for a block whose second row has started to fill: they run out of
## the fronting road along the block's two sides, as far back as the occupied
## rows reach. Built once per tile, and each side is dropped if it would cross
## water — unvalidated street geometry drew over the sea last time.
func _ensure_block_side_roads(tmpl: Dictionary, tile_id: String, coord: Vector2i) -> void:
	if _block_streets.has(tile_id) or not tmpl.has("origin"):
		return
	var origin: Vector2 = tmpl.origin
	var tangent: Vector2 = tmpl.tangent
	var normal: Vector2 = tmpl.normal
	var cols: int = int(tmpl.get("cols", 2))
	var frontage: float = float(tmpl.get("frontage", 0.0))
	var depth := float(BLOCK_ROWS - 1) * BLOCK_LOT + BLOCK_LOT * 0.6
	var world_origin := _tile_center_world_pos(coord)
	var nav := NavGrid.instance()
	var out: Array = []
	for side in [-0.6, float(cols - 1) + 0.6]:
		var base: Vector2 = origin + tangent * (side * BLOCK_LOT)
		var a: Vector2 = base - normal * frontage          # at the fronting road
		var b: Vector2 = base + normal * depth             # back past the last row
		var dry := true
		if nav != null and nav.is_ready():
			for t in 6:
				var p: Vector2 = world_origin + a.lerp(b, float(t) / 5.0)
				var c := nav.cell_of(p)
				if nav.water(c.x, c.y) != 0:
					dry = false
					break
		if dry:
			out.append([world_origin + a, world_origin + b])
	if not out.is_empty():
		_block_streets[tile_id] = out
		queue_redraw()

## Re-run every placement (one-shot) now that the road network exists, so seeds laid
## out before bootstrap snap to frontage — and so any seed laid out before NavGrid was
## ready gets re-masked. Replays in _placements (emit) order with the same per-instance
## seeds, so it reproduces the layout for a given emit order. This is the GLOBAL
## startup pass; per-tile re-snap when the player builds a road is relayout_tile().
func relayout() -> void:
	if _placements.is_empty():
		return
	var src: Array = []
	for p in _placements:
		src.append({"iid": p.instance_id, "bid": p.building_id, "tid": p.tile_id, "coord": p.coord})
	_placements.clear()
	_placement_index.clear()
	_clear_tile_caches()
	for s in src:
		_place_building(str(s.iid), str(s.bid), str(s.tid), s.coord as Vector2i)
	for p in _placements:
		_mark_subcomp_dirty(str(p.tile_id))   # re-derive ancillaries once mains are replayed
	queue_redraw()

## True if `segs` (centre-relative road segments) OVERLAP this placement's footprint — the road comes within
## ROAD_OVERLAP of the AABB (it would sit ON the building), so the building must be re-packed off it. A
## building merely NEAR a road (placed at its ROAD_CLEAR=18u frontage) is NOT a hit, so it stays put.
func _placement_hits_road(p: Dictionary, segs: Array) -> bool:
	var cr: Vector2 = p.center_rel
	var reach: float = maxf((p.half as Vector2).x, (p.half as Vector2).y) + ROAD_OVERLAP
	for s in segs:
		if _pt_seg_dist(cr, (s as Array)[0], (s as Array)[1]) < reach:
			return true
	return false

## Re-pack ONE tile's buildings (cheaper + less disruptive than relayout()): used when a road settles on a
## tile that already has buildings. Buildings now STAY PUT unless the new road overlaps them (see the guard
## below) — the road routes around occupied space. Same per-instance seeds → deterministic.
func relayout_tile(tile_id: String) -> void:
	# OCCUPANCY: a settled road routes AROUND buildings (the graduated building cost in RoadRealizer), so a
	# building does NOT need to move just because a road appeared. Only re-pack when the new road actually
	# OVERLAPS a footprint (it would sit ON the road); otherwise keep every building in place and just refresh
	# the tile's caches so the road merges with the mask + farm lanes. (Stops the "buildings shuffle on every
	# road" churn — they only move when a road truly lands on them.)
	if terrain_layer != null:
		var rsegs := _block_road_segments(terrain_layer.id_to_coord(tile_id))
		var conflict := false
		for p in _placements:
			if str(p.tile_id) == tile_id and str(p.cat) != "farm" and _placement_hits_road(p, rsegs):
				conflict = true
				break
		if not conflict:
			_tile_land.erase(tile_id)
			_tile_landkeys.erase(tile_id)
			_farm_land.erase(tile_id)
			_farm_landkeys.erase(tile_id)
			_tile_segs.erase(tile_id)
			_tile_rivers.erase(tile_id)
			_mark_subcomp_dirty(tile_id)   # re-derive farm lanes against the new road; buildings stay put
			queue_redraw()
			return
	var src: Array = []
	var kept: Array = []
	var has_farm := false
	for p in _placements:
		if str(p.tile_id) == tile_id and str(p.cat) != "farm":
			src.append({"iid": p.instance_id, "bid": p.building_id, "tid": p.tile_id, "coord": p.coord})
		else:
			# Farms STAY PUT when a road is placed (don't rearrange) — the road routes through/around the
			# web instead. Other tiles' placements are kept untouched.
			if str(p.tile_id) == tile_id and str(p.cat) == "farm":
				has_farm = true
			kept.append(p)
	if src.is_empty() and not has_farm:
		_farm_lanes.erase(tile_id)   # tile emptied — drop its stale lanes
		_farm_bridges.erase(tile_id)
		return
	if src.is_empty():
		# Only sticky farms here — don't re-place anything (farms keep their spot). Drop the tile caches so
		# _ensure_tile rebuilds them with the new road, then rebuild the farm layout so the road merges.
		_tile_land.erase(tile_id)
		_tile_landkeys.erase(tile_id)
		_farm_land.erase(tile_id)
		_farm_landkeys.erase(tile_id)
		_tile_segs.erase(tile_id)
		_tile_rivers.erase(tile_id)
		_mark_subcomp_dirty(tile_id)
		queue_redraw()
		return
	_placements = kept
	_placement_index.clear()
	for i in _placements.size():
		_placement_index[str(_placements[i].instance_id)] = i
	# Drop just this tile's cached mask/frontage so _ensure_tile rebuilds it with
	# the road that just appeared, then replay the tile's placements in emit order.
	_tile_land.erase(tile_id)
	_tile_landkeys.erase(tile_id)
	_farm_land.erase(tile_id)
	_farm_landkeys.erase(tile_id)
	_tile_segs.erase(tile_id)
	_tile_rivers.erase(tile_id)
	# Block tiles STAY PUT: keep the grid (origin/orientation) but free all its lots so the
	# survivors re-claim them in emit order, re-validated against the rebuilt road mask. A
	# lot the new road now blocks is consumed in _claim_slot and that building falls back.
	# A cached block (only real ones are cached) STAYS PUT: keep its grid, just free the lots
	# so survivors re-claim in emit order. A tile with no cached block rebuilds fresh below —
	# so a tile built up before its road now forms a block once the road has settled.
	if _tile_block_templates.has(tile_id):
		var claimed: Array = (_tile_block_templates[tile_id] as Dictionary).get("claimed", [])
		for i in claimed.size():
			claimed[i] = false
	for s in src:
		_place_building(str(s.iid), str(s.bid), str(s.tid), s.coord as Vector2i)
	_mark_subcomp_dirty(tile_id)   # re-derive ancillaries against the now-settled road
	queue_redraw()

func _on_road_settled(order_id: int) -> void:
	var tile_id := RoadWorks.order_tile(order_id)
	if tile_id == "":
		return
	_resnap_tiles[tile_id] = true
	if not _resnap_queued:
		_resnap_queued = true
		call_deferred("_flush_resnap")

func _flush_resnap() -> void:
	_resnap_queued = false
	var tiles: Array = _resnap_tiles.keys()
	_resnap_tiles.clear()
	for t in tiles:
		relayout_tile(str(t))

## Mark a tile for a subcomponent rebuild (coalesced into one deferred pass), so tanks/annexes
## are re-derived once the tile's buildings + roads have settled for this frame.
func _on_building_owner_changed(instance_id: String) -> void:
	if not _placement_index.has(instance_id):
		return
	var p: Dictionary = _placements[_placement_index[instance_id]]
	p["is_npc"] = not MatchState.is_player_owned(MatchState.get_building(instance_id))
	_mark_subcomp_dirty(str(p.tile_id))
	queue_redraw()

func _on_building_upgraded(instance_id: String, _new_level: int) -> void:
	var tid := str(MatchState.get_building(instance_id).get("tile_id", ""))
	if tid != "":
		_mark_subcomp_dirty(tid)

func _mark_subcomp_dirty(tile_id: String) -> void:
	_subcomp_dirty[tile_id] = true
	if not _subcomp_queued:
		_subcomp_queued = true
		call_deferred("_flush_subcomponents")

func _flush_subcomponents() -> void:
	_subcomp_queued = false
	var tiles: Array = _subcomp_dirty.keys()
	_subcomp_dirty.clear()
	for t in tiles:
		_rebuild_subcomponents(str(t))
	queue_redraw()

## Re-derive one tile's tanks/annexes from scratch: drop its old ones, then for each main
## building (in emit order) place size-budgeted ancillaries in spare buildable cells adjacent to
## it, avoiding buildings/roads/rivers/other ancillaries. Deterministic (seeded per parent iid).
func _rebuild_subcomponents(tile_id: String) -> void:
	farm_lanes_version += 1   # tracks may change; invalidate the realizer's cached corridor
	var kept: Array = []
	for sc in _subcomponents:
		if str(sc.tile_id) != tile_id:
			kept.append(sc)
	_subcomponents = kept
	_farm_lanes.erase(tile_id)   # before the early returns, so an emptied tile drops its stale lanes
	_farm_bridges.erase(tile_id)
	_farm_promote.erase(tile_id)
	_farm_cluster_rings.erase(tile_id)
	_block_masses.erase(tile_id)
	_massed_by_tile.erase(tile_id)
	var blds: Array = []
	for p in _placements:
		if str(p.tile_id) == tile_id:
			blds.append(p)
	if blds.is_empty():
		return
	var coord: Vector2i = blds[0].coord
	_ensure_tile(tile_id, coord)
	var land: PackedByteArray = _tile_land.get(tile_id, PackedByteArray())
	if land.is_empty():
		return
	var rivers: Array = _tile_rivers.get(tile_id, [])
	var segs: Array = _block_road_segments(coord)   # avoid ALL roads on the tile, gated or not
	var center := _tile_center_world_pos(coord)
	# Farm layout first: each field Voronoi-snaps to its cell, with thin lanes between adjacent fields.
	# Must run before the barn/silo pass so they sit on the CLIPPED field.
	var farms: Array = []
	for p in blds:
		_farm_render.erase(str(p.instance_id))   # drop stale render; rebuilt below for farms
		if str(p.cat) == "farm":
			farms.append(p)
	var farm_snap: Array = []   # tracks + roads (world) the farmsteads snap to
	if not farms.is_empty():
		_build_farm_layout(tile_id, coord, center, farms)
		farm_snap = (_farm_lanes.get(tile_id, []) as Array).duplicate()
		for s in segs:   # _block_road_segments → centre-relative; to world
			farm_snap.append([center + (s[0] as Vector2), center + (s[1] as Vector2)])
	_build_block_masses(tile_id, coord, blds)
	var wdiscs := _forest_discs(coord, center)   # precise wing validation (mask-free)
	var dirs := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP,
		Vector2(0.7071, 0.7071), Vector2(-0.7071, 0.7071), Vector2(0.7071, -0.7071), Vector2(-0.7071, -0.7071)]
	# running occupancy: every main footprint, then each ancillary as it lands
	var placed: Array = []
	for p in blds:
		placed.append({"pos": p.center_rel, "half": p.half})
	for bi in blds.size():
		var p: Dictionary = blds[bi]
		var iid := str(p.instance_id)
		var bhalf: Vector2 = p.half
		var bpos: Vector2 = p.center_rel
		var is_npc: bool = p.is_npc
		# occupancy WITHOUT this parent, so an ancillary may touch/overlap its own building while
		# still avoiding every OTHER building + ancillary.
		var others: Array = []
		for k in placed.size():
			if k != bi:
				others.append(placed[k])
		if str(p.cat) == "farm":
			# Brown barn + silo placed ON the field (3×). Uses the cell-clipped render shape if the
			# farm-layout pass produced one, else the placement's own field.
			var rverts: PackedVector2Array = _farm_render[iid].verts if _farm_render.has(iid) else (p.verts as PackedVector2Array)
			_place_farm_outbuildings(tile_id, iid, rverts, is_npc, farm_snap)
			continue
		if bool(p.get("offshore", false)):
			continue   # platforms at sea carry no annexes/wings/tanks
		var lvl := clampi(int(MatchState.get_building(iid).get("level", 1)), 1, 3)
		# Levels ALWAYS show: L2/L3 stack rooftop storey blocks on the parent
		# (wings depend on free ground and are skipped inside block-masses —
		# a storey needs neither). Drawn on top, slightly toward a seeded
		# corner, one per level above 1, stepped smaller.
		if lvl >= 2 and (p.verts as PackedVector2Array).size() >= 3:
			var pv: PackedVector2Array = p.verts
			var pc := _poly_centroid(pv)
			var anchor_i := RoadHash.pick("storey|%s" % iid, pv.size())
			var nudge := (pv[anchor_i] - pc) * 0.16
			for si in range(lvl - 1):
				var f := 0.62 - 0.20 * float(si)
				var sverts := PackedVector2Array()
				for v2 in pv:
					sverts.append(pc + (v2 - pc) * f + nudge * (1.0 + 0.6 * float(si)))
				_subcomponents.append({
					"tile_id": tile_id, "verts": sverts, "color": p.color,
					"kind": "storey", "is_npc": is_npc, "bb": _verts_bb(sverts),
					"cat": str(p.cat), "iid": iid,
				})
		if (_massed_by_tile.get(tile_id, {}) as Dictionary).has(iid):
			continue   # inside a block-mass — the mass is the compound
		var pcolor: Color = p.color
		# Compound massing (ink spec I2): big industrial halls grow 1-2 seeded
		# WINGS — same-wash rects at 20-40% of the parent's area, tucked flush so
		# the pair reads as one compound (wings draw UNDER, like annexes). Draw
		# representation only: placement data, occupancy and discs are untouched.
		var fam := _wash_family(str(p.cat))
		var parent_area := 4.0 * bhalf.x * bhalf.y
		var pverts: PackedVector2Array = p.verts
		# Wing count: big grey/mustard halls start with 1-2 seeded wings; every
		# level above 1 adds one more, ANY family (owner 2026-07-10: buildings
		# visibly expand with annexes when they upgrade to L2/L3).
		var base_wings := 0
		if (fam == "grey" or fam == "navy" or fam == "lime" or fam == "mustard") and parent_area >= WING_MIN_PARENT_AREA:
			base_wings = 1 + RoadHash.pick("wing|%s|n" % iid, 2)
		var wing_total := mini(base_wings + (lvl - 1), 4)
		if wing_total > 0 and pverts.size() >= 3:
			# Axes from the footprint's LONGEST edge, extents by projection —
			# works for quads AND the L/C shapes, which previously never grew
			# wings at all (owner 2026-07-10: an upgraded building must expand
			# even if only a bit). World-axis offsets on rotated halls would
			# corner-touch and draw a bowtie.
			var longest := Vector2.RIGHT
			var best_l := 0.0
			for ei in pverts.size():
				var ev := pverts[(ei + 1) % pverts.size()] - pverts[ei]
				if ev.length() > best_l:
					best_l = ev.length()
					longest = ev
			var ua := longest.normalized()
			var ub := Vector2(-ua.y, ua.x)
			var pang := ua.angle()
			var wc := center + bpos
			var tmin := 1.0e9
			var tmax := -1.0e9
			var nmin := 1.0e9
			var nmax := -1.0e9
			for pv2 in pverts:
				var dt := (pv2 - wc).dot(ua)
				var dn := (pv2 - wc).dot(ub)
				tmin = minf(tmin, dt)
				tmax = maxf(tmax, dt)
				nmin = minf(nmin, dn)
				nmax = maxf(nmax, dn)
			var wdirs: Array = [ua, -ua, ub, -ub]
			var wexts: Array = [tmax, -tmin, nmax, -nmin]
			for wi in wing_total:
				var frac := WING_AREA_MIN + float(RoadHash.pick("wing|%s|%d|a" % [iid, wi], 100)) / 100.0 * WING_AREA_SPAN
				var aspect := 0.5 + float(RoadHash.pick("wing|%s|%d|s" % [iid, wi], 31)) / 100.0
				var ww := sqrt(parent_area * frac / aspect)
				var whh := ww * aspect
				var wshape: Dictionary = BuildingShapes.make_rect(ww, whh)
				var wverts_l := _rotate(wshape.verts, pang)
				var wh := _aabb_half(wverts_l)
				var wrot := RoadHash.pick("wing|%s|%d|rot" % [iid, wi], wdirs.size())
				var wing_done := false
				for j0 in wdirs.size():
					var di := (j0 + wrot) % wdirs.size()
					var wdir: Vector2 = wdirs[di]
					# Wing half-extent along the offset axis (its own w or h).
					var wing_ext: float = ww * 0.5 if di < 2 else whh * 0.5
					var wctr: Vector2 = bpos + wdir * (float(wexts[di]) + SUBCOMP_ANNEX_OVERLAP + wing_ext)
					# Seeded slide along the perpendicular edge so wings sit off-centre
					# (reference compounds are asymmetric), clamped to keep the overlap.
					var perp: Vector2 = wdirs[(di + 2) % 4] if di < 2 else wdirs[di - 2]
					var pext: float = minf(float(wexts[2]), float(wexts[3])) if di < 2 else minf(float(wexts[0]), float(wexts[1]))
					var wing_pext: float = whh * 0.5 if di < 2 else ww * 0.5
					var slide_max: float = maxf(pext - wing_pext, 0.0)
					var slide := (float(RoadHash.pick("wing|%s|%d|sl" % [iid, wi], 100)) / 100.0 - 0.5) * 2.0 * slide_max
					wctr += perp * slide
					if not _wing_valid(wctr, wverts_l, wh, others, segs, rivers, wdiscs, center):
						continue
					var wentry := {"pos": wctr, "half": wh}
					placed.append(wentry)
					others.append(wentry)
					var www := PackedVector2Array()
					for wv in wverts_l:
						www.append(center + wctr + wv)
					_subcomponents.append({
						"tile_id": tile_id, "verts": www, "color": pcolor,
						"kind": "wing", "is_npc": is_npc, "bb": _verts_bb(www),
						"cat": str(p.cat), "iid": iid,
					})
					wing_done = true
					break
				if not wing_done and lvl >= 2:
					# Hemmed in on every side? UPGRADED buildings expand ACROSS
					# the road (owner trigger rule 2026-07-10: no space around
					# + space across + upgraded): the wing lands on the far
					# side of the carriageway, tethered back by a narrow
					# covered corridor drawn over the road (5-10u wide).
					for j1 in wdirs.size():
						if wing_done:
							break
						var di2 := (j1 + wrot) % wdirs.size()
						var wdir2: Vector2 = wdirs[di2]
						var wing_ext2: float = ww * 0.5 if di2 < 2 else whh * 0.5
						for step in [34.0, 42.0, 50.0, 58.0]:
							var wctr2: Vector2 = bpos + wdir2 * (float(wexts[di2]) + step + wing_ext2)
							if not _wing_valid(wctr2, wverts_l, wh, others, segs, rivers, wdiscs, center):
								continue
							var pa: Vector2 = bpos + wdir2 * float(wexts[di2])
							var pb: Vector2 = wctr2 - wdir2 * wing_ext2
							# Only worth it when the corridor genuinely SPANS a
							# road (else the normal flush attempt would have
							# worked); rivers stay uncrossed.
							if not _seg_hits_any(pa, pb, segs) or _seg_hits_any(pa, pb, rivers):
								continue
							var wentry2 := {"pos": wctr2, "half": wh}
							placed.append(wentry2)
							others.append(wentry2)
							var www2 := PackedVector2Array()
							for wv2 in wverts_l:
								www2.append(center + wctr2 + wv2)
							_subcomponents.append({
								"tile_id": tile_id, "verts": www2, "color": pcolor,
								"kind": "wing", "is_npc": is_npc, "bb": _verts_bb(www2),
								"cat": str(p.cat), "iid": iid,
							})
							var cw := (5.0 + float(RoadHash.pick("wing|%s|%d|cw" % [iid, wi], 6))) * 0.5
							var co := Vector2(-wdir2.y, wdir2.x) * cw
							var cverts := PackedVector2Array([
								center + pa - co, center + pb - co,
								center + pb + co, center + pa + co,
							])
							_subcomponents.append({
								"tile_id": tile_id, "verts": cverts, "color": pcolor,
								"kind": "corridor", "is_npc": is_npc, "bb": _verts_bb(cverts),
								"cat": str(p.cat), "iid": iid,
							})
							wing_done = true
							break
		# Tank farm (owner 2026-07-10): chemical works (chem plants lime,
		# petro/poly refineries pink) carry their cylinders OUTSIDE the hall
		# as ONE battery block — 2 side by side, 3 in a triangle, 4 in a grid.
		if fam == "lime" or fam == "pink":
			var tn := 2 + RoadHash.pick("tf|%s|n" % iid, 3)
			var tr := SUBCOMP_TANK_R
			var pitch := tr * 2.0 + 1.5
			var offs: Array = []
			match tn:
				2: offs = [Vector2(-pitch * 0.5, 0), Vector2(pitch * 0.5, 0)]
				3: offs = [Vector2(-pitch * 0.5, pitch * 0.433), Vector2(pitch * 0.5, pitch * 0.433), Vector2(0, -pitch * 0.433)]
				_: offs = [Vector2(-pitch * 0.5, -pitch * 0.5), Vector2(pitch * 0.5, -pitch * 0.5), Vector2(-pitch * 0.5, pitch * 0.5), Vector2(pitch * 0.5, pitch * 0.5)]
			var tbh := Vector2.ZERO
			for o in offs:
				tbh.x = maxf(tbh.x, absf((o as Vector2).x) + tr)
				tbh.y = maxf(tbh.y, absf((o as Vector2).y) + tr)
			var tblock: PackedVector2Array = BuildingShapes.make_rect(tbh.x * 2.0, tbh.y * 2.0).verts
			var trot := RoadHash.pick("tf|%s|rot" % iid, dirs.size())
			for j2 in dirs.size():
				var tdir: Vector2 = dirs[(j2 + trot) % dirs.size()]
				var text: float = absf(tdir.x) * bhalf.x + absf(tdir.y) * bhalf.y
				var tctr: Vector2 = bpos + tdir * (text + SUBCOMP_GAP + maxf(tbh.x, tbh.y))
				if not _valid(tctr, tblock, tbh, placed, land, segs, rivers):
					continue
				var tentry := {"pos": tctr, "half": tbh}
				placed.append(tentry)
				others.append(tentry)
				var tanks: Array = []
				for o2 in offs:
					tanks.append(center + tctr + (o2 as Vector2))
				var tbverts := PackedVector2Array()
				for tbv in tblock:
					tbverts.append(center + tctr + tbv)
				_subcomponents.append({
					"tile_id": tile_id, "verts": tbverts, "color": pcolor,
					"kind": "tankfarm", "is_npc": is_npc, "bb": _verts_bb(tbverts),
					"cat": str(p.cat), "iid": iid, "tanks": tanks, "r": tr,
				})
				break
		# at most ONE annex (touches/merges) + ONE round tank (small gap), both parent colour.
		for kind in ["annex", "tank"]:
			var is_tank: bool = (kind == "tank")
			if is_tank and (fam == "lime" or fam == "pink"):
				continue   # the tank-farm battery IS their tankage
			var shape: Dictionary = BuildingShapes.circle(SUBCOMP_TANK_R) if is_tank else BuildingShapes.make_rect(SUBCOMP_ANNEX.x, SUBCOMP_ANNEX.y)
			var verts: PackedVector2Array = shape.verts
			var sh: Vector2 = shape.half
			var gap := SUBCOMP_GAP if is_tank else SUBCOMP_ANNEX_OVERLAP
			var against: Array = placed if is_tank else others
			var rot := RoadHash.pick("sub|%s|%s|rot" % [iid, kind], dirs.size())
			for j in dirs.size():
				var dir: Vector2 = dirs[(j + rot) % dirs.size()]
				var ext: float = absf(dir.x) * bhalf.x + absf(dir.y) * bhalf.y
				var ctr: Vector2 = bpos + dir * (ext + gap + maxf(sh.x, sh.y))
				if not _valid(ctr, verts, sh, against, land, segs, rivers):
					continue
				var entry := {"pos": ctr, "half": sh}
				placed.append(entry)
				others.append(entry)
				var wverts := PackedVector2Array()
				for v in verts:
					wverts.append(center + ctr + v)
				_subcomponents.append({
					"tile_id": tile_id, "verts": wverts, "color": pcolor,
					"kind": kind, "is_npc": is_npc, "bb": _verts_bb(wverts),
					"cat": str(p.cat), "iid": iid,
				})
				break   # placed this kind; move to the next

func _tile_type(coord: Vector2i) -> String:
	if terrain_layer == null:
		return ""
	return str((terrain_layer.tiles.get(coord, {}) as Dictionary).get("type", ""))

## Courtyard block-masses (ink spec I2 + owner rules 2026-07-10): bunches of
## COURT_MIN_BUNCH+ adjacent same-owner quad buildings draw as ONE merged mass
## (inflate-merge-deflate closes the terrace gaps; L-shapes emerge naturally
## from the union). Masses deep enough get an inner COURTYARD (inset hole).
## Members keep ink outlines + roof motifs as party-wall divisions, so clicks
## and identity stay per-building. Urban tiles always mass; rural/hill a
## seeded third; mountains never; farms and offshore never cluster.
func _build_block_masses(tile_id: String, coord: Vector2i, blds: Array) -> void:
	var ttype := _tile_type(coord)
	var eligible: bool = ttype == "urban" \
		or ((ttype == "rural" or ttype == "grass" or ttype == "hill") and RoadHash.pick("court|%s" % tile_id, 3) == 0)
	if not eligible:
		return
	var cands: Array = []
	for p in blds:
		if str(p.cat) == "farm" or bool(p.get("offshore", false)):
			continue
		if (p.verts as PackedVector2Array).size() != 4:
			continue
		# Shape-language buildings draw their own compound, and a mass member
		# skips its fill and contributes only party-wall ink — which is why a
		# cluster of 5+ factories reverted to plate outlines and then to
		# apparently transparent shapes (owner report, tile_6_12).
		if INK_ART_KEY.has(str(p.get("iname", ""))):
			continue
		cands.append(p)
	if cands.size() < COURT_MIN_BUNCH:
		return
	cands.sort_custom(func(a, b) -> bool: return str(a.instance_id) < str(b.instance_id))
	# Union-find over footprint adjacency (same owner, AABBs within COURT_ADJ).
	var n := cands.size()
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in n:
		parent[i] = i
	for i in n:
		for j in range(i + 1, n):
			var a: Dictionary = cands[i]
			var b: Dictionary = cands[j]
			if bool(a.is_npc) != bool(b.is_npc):
				continue
			if not (a.bb as Rect2).grow(COURT_ADJ * 0.5).intersects((b.bb as Rect2).grow(COURT_ADJ * 0.5)):
				continue
			var ri := _mass_find(parent, i)
			var rj := _mass_find(parent, j)
			if ri != rj:
				parent[ri] = rj
	var groups: Dictionary = {}
	for i2 in n:
		var r := _mass_find(parent, i2)
		var lst: Array = groups.get(r, [])
		lst.append(i2)
		groups[r] = lst
	var roots: Array = groups.keys()
	roots.sort()
	var masses: Array = []
	var member_ids: Dictionary = {}
	var gi := 0
	for root in roots:
		var arr: Array = groups[root]
		if arr.size() < COURT_MIN_BUNCH:
			continue
		# Inflate each footprint, merge pairwise, deflate — one welded mass.
		var acc := _offset_ccw((cands[arr[0]] as Dictionary).verts, COURT_GROW)
		if acc.is_empty():
			continue
		for mi in range(1, arr.size()):
			var nxt := _offset_ccw((cands[arr[mi]] as Dictionary).verts, COURT_GROW)
			if nxt.is_empty():
				continue
			var merged := Geometry2D.merge_polygons(acc, nxt)
			var best := PackedVector2Array()
			var best_a := 0.0
			for part in merged:
				if Geometry2D.is_polygon_clockwise(part):
					continue   # hole — courtyards come from the inset below
				var pa := absf(_poly_area(part))
				if pa > best_a:
					best_a = pa
					best = part
			if best.size() >= 3:
				acc = best
		var mass := _offset_ccw(acc, -COURT_GROW)
		if mass.size() < 3:
			continue
		# Courtyard: the mass inset COURT_INSET deep. Single-row masses vanish
		# under the inset (correct — a yard needs enclosure on all sides).
		var holes: Array = []
		for hole in Geometry2D.offset_polygon(mass, -COURT_INSET):
			if absf(_poly_area(hole)) >= COURT_MIN_YARD:
				holes.append(hole)
		holes.sort_custom(func(x, y) -> bool: return absf(_poly_area(x)) > absf(_poly_area(y)))
		if holes.size() > 2:
			holes = holes.slice(0, 2)
		# Majority family sets the wash (NPC bunches come out paper white).
		var fam_count: Dictionary = {}
		for mi2 in arr:
			var c := str((cands[mi2] as Dictionary).cat)
			fam_count[c] = int(fam_count.get(c, 0)) + 1
		var major := ""
		var major_n := 0
		for c2 in fam_count:
			if int(fam_count[c2]) > major_n:
				major_n = int(fam_count[c2])
				major = str(c2)
		var is_npc := bool((cands[arr[0]] as Dictionary).is_npc)
		masses.append({
			"poly": mass, "holes": holes,
			"color": _wash_for(major, "mass|%s|%d" % [tile_id, gi], is_npc),
			"bb": _verts_bb(mass), "key": "mass|%s|%d" % [tile_id, gi],
		})
		for mi3 in arr:
			member_ids[str((cands[mi3] as Dictionary).instance_id)] = true
		gi += 1
	if not masses.is_empty():
		_block_masses[tile_id] = masses
		_massed_by_tile[tile_id] = member_ids

func _mass_find(parent: PackedInt32Array, i: int) -> int:
	var r := i
	while parent[r] != r:
		r = parent[r]
	return r

func _poly_area(pts: PackedVector2Array) -> float:
	var area := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		area += p.x * q.y - q.x * p.y
	return area * 0.5

## Offset with normalised winding (Clipper shrinks a clockwise polygon on a
## positive delta); returns the largest resulting part.
func _offset_ccw(poly: PackedVector2Array, delta: float) -> PackedVector2Array:
	var src := poly.duplicate()
	if Geometry2D.is_polygon_clockwise(src):
		src.reverse()
	var out := PackedVector2Array()
	var best_a := 0.0
	for part in Geometry2D.offset_polygon(src, delta, Geometry2D.JOIN_MITER):
		var pa := absf(_poly_area(part))
		if pa > best_a:
			best_a = pa
			out = part
	return out

## A farm's outbuildings (brown barn + silo) snap to the plot's ROAD EDGE — the field-boundary point
## nearest any track/road in `snap_segs` — and sit just inside the field there (farmstead by the road).
## The silo abuts the barn, also inside. Kind "farm_barn"/"farm_silo" so _draw paints them over the field.
func _place_farm_outbuildings(tile_id: String, iid: String, field_world: PackedVector2Array, is_npc: bool, snap_segs: Array) -> void:
	if field_world.size() < 3:
		return
	var cen: Vector2 = _poly_centroid(field_world)
	var barn_shape := BuildingShapes.make_rect(FARM_BARN.x * FARM_OUTBUILDING_SCALE, FARM_BARN.y * FARM_OUTBUILDING_SCALE)
	var barn_v: PackedVector2Array = barn_shape.verts
	var barn_h: Vector2 = barn_shape.half
	var br := maxf(barn_h.x, barn_h.y)
	# Anchor: the field-boundary point nearest a track/road (the farmstead faces the road). Centroid if none.
	var anchor := cen
	if not snap_segs.is_empty():
		var best_d := 1.0e9
		var n := field_world.size()
		for k in n:
			var e0: Vector2 = field_world[k]
			var e1: Vector2 = field_world[(k + 1) % n]
			var steps := maxi(1, int(e0.distance_to(e1) / 8.0))
			for s in range(steps + 1):
				var pt: Vector2 = e0.lerp(e1, float(s) / float(steps))
				for seg in snap_segs:
					var d: float = _pt_seg_dist(pt, seg[0], seg[1])
					if d < best_d:
						best_d = d
						anchor = pt
	# Place the barn just INSIDE the field from the anchor (toward the centroid), nudging in until it fits.
	var inward := cen - anchor
	inward = inward.normalized() if inward.length() > 0.001 else Vector2.UP
	var barn_c := cen
	var barn_ok := false
	for f in [1.0, 1.6, 2.2, 3.0]:
		var c: Vector2 = anchor + inward * (br * f)
		if _poly_inside(barn_v, c, field_world):
			barn_c = c
			barn_ok = true
			break
	if not barn_ok:
		if _poly_inside(barn_v, cen, field_world):
			barn_c = cen
		elif not _poly_inside_loose(barn_v, cen, field_world):
			return   # field too thin even for the barn — skip outbuildings
	_append_farm_world_sub(tile_id, barn_v, barn_c, is_npc, "farm_barn")
	# Silo abuts the barn (prefer further inward), kept on the field.
	var silo_shape := BuildingShapes.circle(FARM_SILO_R * FARM_OUTBUILDING_SCALE)
	var silo_v: PackedVector2Array = silo_shape.verts
	var silo_h: Vector2 = silo_shape.half
	var sr := maxf(silo_h.x, silo_h.y)
	var dirs := [inward, Vector2(-inward.y, inward.x), Vector2(inward.y, -inward.x), -inward]
	for dir in dirs:
		var ext: float = absf(dir.x) * barn_h.x + absf(dir.y) * barn_h.y
		var c: Vector2 = barn_c + (dir as Vector2) * (ext + SUBCOMP_GAP * FARM_OUTBUILDING_SCALE + sr)
		if _poly_inside(silo_v, c, field_world):
			_append_farm_world_sub(tile_id, silo_v, c, is_npc, "farm_silo")
			return

## Append a brown farm outbuilding (local verts placed at world centre `c`).
func _append_farm_world_sub(tile_id: String, verts: PackedVector2Array, c: Vector2, is_npc: bool, kind: String) -> void:
	var wverts := PackedVector2Array()
	for v in verts:
		wverts.append(c + v)
	_subcomponents.append({
		"tile_id": tile_id, "verts": wverts, "color": FARM_BROWN,
		"kind": kind, "is_npc": is_npc, "bb": _verts_bb(wverts),
	})

## Build the per-tile farm layout: clip each field to its Voronoi cell (so it "snaps" to the lanes),
## re-bake its hatch, and collect the lanes — Voronoi edges trimmed to within FARM_LANE_REACH of the
## fields, routed AROUND forests (heptagon rings, cut at rivers), crossing rivers only at bridges.
func _build_farm_layout(tile_id: String, coord: Vector2i, center: Vector2, farms: Array) -> void:
	var hex := _hex_world(coord)
	var sites: Array = []                       # one representative world point per farm
	for f in farms:
		sites.append(center + (f.center_rel as Vector2))
	var lanes: Array = []
	var interfield: Array = []   # inter-field lane pieces (the "web") — trunk candidate for promotion
	var ring_pieces: Array = []  # outer-ring pieces — promotion candidate
	var bridges: Array = []
	var fields_w: Array = []                     # clipped (rendered) field polygons, world
	var rivers_w: Array = []                     # river arms in world space
	for r in _tile_rivers.get(tile_id, []):
		rivers_w.append([center + (r[0] as Vector2), center + (r[1] as Vector2)])
	# A river splits the cluster into independent per-bank webs: a field clips its Voronoi cell only
	# against farms on its OWN bank (the segment to them doesn't cross a river), so cells/lanes/rings
	# never span the water (the split-river scenario just uses each bank's farms separately).
	for i in farms.size():
		var render: PackedVector2Array = farms[i].verts
		if farms.size() > 1:
			var cell := hex
			for j in farms.size():
				if i == j or not _same_bank(sites[i], sites[j], rivers_w):
					continue
				cell = _clip_poly_halfplane(cell, sites[i], sites[j])   # keep nearer-to-i side
				if cell.size() < 3:
					break
			if cell.size() >= 3:
				var parts := Geometry2D.intersect_polygons(farms[i].verts, cell)
				render = _largest_ccw(parts, farms[i].verts)
		_farm_render[str(farms[i].instance_id)] = {"verts": render, "hatch": _bake_farm_hatch(render), "parcels": _bake_farm_parcels(render)}
		fields_w.append(render)
	# Group farms into webs by FIELD ADJACENCY (touching = share a side) so distant farms never share a
	# web/ring; one ring per web, computed up front so the inter-field web can EXTEND out to meet it. The
	# ring HUGS the fields (concave union offset outward), not a far-projecting convex hull.
	var comps := _web_components(fields_w, FARM_ADJ_MAX)
	var comp_of: Dictionary = {}
	for ci in comps.size():
		for idx in (comps[ci] as Array):
			comp_of[idx] = ci
	var comp_ring: Array = []
	for ci in comps.size():
		var members: Array = comps[ci]
		comp_ring.append(_union_offset_fields(fields_w, members, FARM_RING_OFFSET) if members.size() >= 2 else PackedVector2Array())
	var heps := _forest_heptagons_near(coord, center, fields_w)   # forests to circumvent
	if farms.size() > 1:
		for i in farms.size():
			for j in range(i + 1, farms.size()):
				# Only adjacent fields (sharing a side, same web) get a lane — no web from distant farms.
				if int(comp_of[i]) != int(comp_of[j]) or not _polys_adjacent(fields_w[i], fields_w[j], FARM_ADJ_MAX):
					continue
				var ring2: PackedVector2Array = comp_ring[int(comp_of[i])]
				if ring2.size() < 3:
					continue
				var seg := _voronoi_edge(sites, i, j, hex)
				if seg.size() < 2:
					continue
				# Clip the Voronoi edge to the (possibly concave) ring: keeps interior junctions AND extends
				# the edge out to MEET the ring, so the web is one connected network (a road can thread it).
				for part in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([seg[0], seg[1]]), ring2):
					var pv: PackedVector2Array = part
					for k in range(pv.size() - 1):
						for pc in _subtract_heptagons([pv[k], pv[k + 1]], heps):
							interfield.append(pc)
	# Forest circumvention: each near-field forest's heptagon ring — but only the arc within
	# FARM_LANE_REACH of a field (a partial heptagon is fine), and cut where a river crosses it.
	for hep in heps:
		var poly: PackedVector2Array = hep.poly
		for k in poly.size():
			var e0: Vector2 = poly[k]
			var e1: Vector2 = poly[(k + 1) % poly.size()]
			for run in _near_field_runs(e0, e1, fields_w, FARM_LANE_REACH):
				var ra: Vector2 = e0.lerp(e1, run[0])
				var rb: Vector2 = e0.lerp(e1, run[1])
				for sub in _seg_keep_away_from_segs(ra, rb, rivers_w, RIVER_CLEAR):
					lanes.append(sub)
	# Outer ring: the per-component ring polygons (computed above), cut at rivers, routed around forests,
	# and clipped just 1u inside the hex (a tiny inset stops two adjacent tiles' rings from overlapping ON
	# the shared edge, but — unlike the old 3u — no longer severs the loop wherever the cluster reaches the
	# tile edge). The full ring polygon still drives the snap's inside-cluster test.
	var inset_hex := _largest_ccw(Geometry2D.offset_polygon(hex, -1.0), hex)
	var cluster_rings: Array = []
	for ci in comp_ring.size():
		var ring: PackedVector2Array = comp_ring[ci]
		if ring.size() < 3:
			continue
		cluster_rings.append(ring)   # snap inside-cluster test uses the FULL ring (unclipped)
		# Detour around forests by CLIPPING each forest heptagon out of the ring polygon (so the drawn
		# outline bends around a forest as one continuous boundary, instead of the old per-edge subtract
		# that deleted the overlapping arc and left a gap). Holes (a forest fully inside the cluster) are
		# dropped — only the outer outline matters here.
		var ring_polys: Array = [ring]
		for hep in heps:
			var nxt: Array = []
			for rpoly in ring_polys:
				var parts := Geometry2D.clip_polygons(rpoly, hep.poly)
				if parts.is_empty():
					nxt.append(rpoly)   # no overlap — keep the ring as-is
					continue
				for part in parts:
					if not Geometry2D.is_polygon_clockwise(part):   # outer ring (CCW); skip CW holes
						nxt.append(part)
			ring_polys = nxt
		for rp in ring_polys:
			var rpv: PackedVector2Array = rp
			if rpv.size() < 3:
				continue
			for k in rpv.size():
				var a0: Vector2 = rpv[k]
				var a1: Vector2 = rpv[(k + 1) % rpv.size()]
				var inhex := _clip_seg_to_convex(a0, a1, inset_hex)   # drop the parts within ~1u of the tile edge
				if inhex.size() < 2:
					continue
				for sub in _seg_keep_away_from_segs(inhex[0], inhex[1], rivers_w, RIVER_CLEAR):
					ring_pieces.append(PackedVector2Array([sub[0], sub[1]]))
	# Merge the farm track network into any real road that reaches the fields — a cosmetic connector
	# lane (NOT a new RoadNetwork edge), from the nearest track/field anchor to the nearest road point.
	var roads_w: Array = []
	for s in _block_road_segments(coord):
		roads_w.append([center + (s[0] as Vector2), center + (s[1] as Vector2)])
	if not roads_w.is_empty() and not fields_w.is_empty():
		var best_fp := Vector2.ZERO        # closest field-edge point
		var best_rp := Vector2.ZERO        # closest point on a real road
		var best_d := 1.0e9
		for rw in roads_w:
			var rl: float = (rw[0] as Vector2).distance_to(rw[1])
			var rs := maxi(1, int(rl / 8.0))
			for si in range(rs + 1):
				var rpt: Vector2 = (rw[0] as Vector2).lerp(rw[1], float(si) / float(rs))
				for fw in fields_w:
					var fp := _closest_point_on_poly(rpt, fw)
					var dd: float = rpt.distance_to(fp)
					if dd < best_d:
						best_d = dd
						best_rp = rpt
						best_fp = fp
		if best_d > 1.0 and best_d < FARM_ROAD_MERGE_MAX and _seg_on_land(best_fp, best_rp):
			for pc in _subtract_heptagons([best_fp, best_rp], heps):
				lanes.append(pc)
	# Promotion candidate: the outer RING only (chained into polylines). The "one path through the web"
	# is provided by the player's actual road, which BORROWS the web exactly when it crosses the cluster
	# (RoadWorks._snap_route_to_web) — so we never promote a trunk that would double up with that road.
	_farm_promote[tile_id] = {"ring": _chain_segments(ring_pieces)}
	_farm_cluster_rings[tile_id] = cluster_rings
	# Draw the inter-field web as brown tracks (always). Once a road PROMOTES this tile, omit the outer
	# RING (it's now a yellow road); the inter-field web stays brown (the road borrows it as needed).
	var promoted: bool = RoadWorks.is_farm_promoted(tile_id) if RoadWorks.has_method("is_farm_promoted") else false
	for pc in interfield:
		lanes.append(pc)
	if not promoted:
		# Chain the outer-ring pieces into continuous polylines so the edges MEET (no broken corners),
		# then drop the runs that already lie within FARM_RING_DEDUP_RADIUS of a real road — INCLUDING a
		# road in a neighbour tile that hugs this cluster but never settled on it (so promotion's dedup
		# never fired). _block_road_segments returns CENTRE-RELATIVE pairs, so neighbour segs re-base via
		# that tile's centre. Same radius as the promotion dedup, so it can't over-merge beyond it.
		var ring_roads_w: Array = roads_w.duplicate()
		if terrain_layer != null and terrain_layer.has_method("neighbor_coords"):
			for ncoord in terrain_layer.neighbor_coords(coord):
				var ncenter := _tile_center_world_pos(ncoord)
				for s in _block_road_segments(ncoord):
					ring_roads_w.append([ncenter + (s[0] as Vector2), ncenter + (s[1] as Vector2)])
		for poly in _chain_segments(ring_pieces):
			for run in _ring_runs_clear_of_roads(poly, ring_roads_w, RoadWorks.FARM_RING_DEDUP_RADIUS):
				lanes.append(run)
	_farm_lanes[tile_id] = lanes
	_farm_bridges[tile_id] = bridges

## Forests (as world heptagons) within FOREST_RING_NEAR of a field — the ones farm lanes must avoid.
func _forest_heptagons_near(coord: Vector2i, center: Vector2, fields_w: Array) -> Array:
	var out: Array = []
	var accepted: Array = []   # accepted {c, r}; drops near-coincident forest instances (the "drawn twice" bug)
	var idx := 0
	for d in _forest_discs(coord, center):
		var wc: Vector2 = center + (d.c as Vector2)
		var r: float = float(d.r)
		var near := false
		for f in fields_w:
			if _dist_point_to_poly(wc, f) <= r + FOREST_RING_NEAR:
				near = true
				break
		if near:
			var dup := false
			for ac in accepted:
				if wc.distance_to(ac.c) < (r + float(ac.r)) * 0.5:   # overlap >half → same forest
					dup = true
					break
			if not dup:
				var rot := TAU * float(RoadHash.pick("farmhep|%d_%d|%d" % [coord.x, coord.y, idx], 7)) / 7.0
				out.append({"poly": _make_heptagon(wc, r + FOREST_HEP_MARGIN, rot)})
				accepted.append({"c": wc, "r": r})
		idx += 1
	return out

## Closest point on segment a–b to p.
func _closest_point_on_seg(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1.0e-6:
		return a
	return a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)

## True only when EVERY interior sample of [a,b] is on land (no sea/lake/river). Used to reject a
## cosmetic farm-merge connector that would otherwise be drawn straight across open water (it has no
## RoadNetwork edge, so it never goes through the router's water mask). Degrades to true if the
## navgrid isn't baked yet, matching the nav_ok fallback used elsewhere in this file.
func _seg_on_land(a: Vector2, b: Vector2) -> bool:
	var nav := NavGrid.instance()
	if nav == null or not nav.is_ready():
		return true
	var n := maxi(1, int(ceil(a.distance_to(b) / (nav.step * 0.5))))   # sample every ~half cell (≤6u)
	for i in range(n + 1):
		var c := nav.cell_of(a.lerp(b, float(i) / float(n)))           # cell_of clamps to grid bounds
		if nav.water(c.x, c.y) != NavGrid.WATER_LAND:
			return false
	return true

## Split a chained ring polyline into the maximal runs of vertices NOT within `radius` of any world
## road segment in `roads_w` (mirrors RoadWorks._undoubled_runs). This stops the cosmetic tan ring
## from drawing parallel to a real road that hugs the cluster — even one in a NEIGHBOUR tile that
## never settled ON this tile (so promotion's dedup never ran). Each kept run is dilated one vertex
## into the covered zone so it still meets the road (no gap).
func _ring_runs_clear_of_roads(poly: PackedVector2Array, roads_w: Array, radius: float) -> Array:
	if roads_w.is_empty():
		return [poly]
	var n := poly.size()
	if n < 2:
		return []
	var r2 := radius * radius
	var include := PackedByteArray()
	include.resize(n)
	include.fill(0)
	for i in n:
		var p: Vector2 = poly[i]
		var covered := false
		for s in roads_w:
			if p.distance_squared_to(_closest_point_on_seg(p, s[0], s[1])) <= r2:
				covered = true
				break
		if not covered:
			include[i] = 1
			if i > 0:
				include[i - 1] = 1
			if i < n - 1:
				include[i + 1] = 1
	var runs: Array = []
	var cur := PackedVector2Array()
	for i in n:
		if include[i] == 1:
			cur.append(poly[i])
		else:
			if cur.size() >= 2:
				runs.append(cur)
			cur = PackedVector2Array()
	if cur.size() >= 2:
		runs.append(cur)
	return runs

## Greedily chain 2-point segments that share endpoints into polylines (fewer, longer road edges).
func _chain_segments(segs: Array) -> Array:
	var pool: Array = []
	for s in segs:
		var ps: PackedVector2Array = s
		if ps.size() == 2 and ps[0].distance_to(ps[1]) > 0.5:
			pool.append(ps)
	var out: Array = []
	var used := {}
	for i in pool.size():
		if used.has(i):
			continue
		used[i] = true
		var chain := PackedVector2Array([pool[i][0], pool[i][1]])
		var extended := true
		while extended:
			extended = false
			for j in pool.size():
				if used.has(j):
					continue
				var a: Vector2 = pool[j][0]
				var b: Vector2 = pool[j][1]
				var tail: Vector2 = chain[chain.size() - 1]
				var head: Vector2 = chain[0]
				if tail.distance_to(a) < 1.0:
					chain.append(b); used[j] = true; extended = true
				elif tail.distance_to(b) < 1.0:
					chain.append(a); used[j] = true; extended = true
				elif head.distance_to(a) < 1.0:
					chain.insert(0, b); used[j] = true; extended = true
				elif head.distance_to(b) < 1.0:
					chain.insert(0, a); used[j] = true; extended = true
		# Close a loop whose two free ends meet (a ring that wasn't cut): the outline then reads as one
		# continuous closed track rather than a polyline with a hairline gap at the start/end vertex.
		if chain.size() > 2 and chain[0].distance_to(chain[chain.size() - 1]) < 1.5:
			chain.append(chain[0])
		out.append(chain)
	return out

## Closest point on a polygon's boundary to p.
func _closest_point_on_poly(p: Vector2, poly: PackedVector2Array) -> Vector2:
	var best := poly[0] if poly.size() > 0 else p
	var bd := 1.0e9
	var n := poly.size()
	for k in n:
		var cp := _closest_point_on_seg(p, poly[k], poly[(k + 1) % n])
		var d: float = p.distance_to(cp)
		if d < bd:
			bd = d
			best = cp
	return best

## Subtract every heptagon from a segment (keep the parts OUTSIDE all of them). Returns [a,b]-pairs.
func _subtract_heptagons(seg: Array, heps: Array) -> Array:
	var pieces: Array = [PackedVector2Array([seg[0], seg[1]])]
	for hep in heps:
		var nxt: Array = []
		for pc in pieces:
			nxt += _seg_outside_convex(pc[0], pc[1], hep.poly)
		pieces = nxt
	var out: Array = []
	for pc in pieces:
		if (pc as PackedVector2Array).size() == 2 and pc[0].distance_to(pc[1]) > 4.0:
			out.append(pc)
	return out

## Two farm sites are on the same river bank if the straight segment between them crosses no river arm.
func _same_bank(a: Vector2, b: Vector2, rivers_w: Array) -> bool:
	for rw in rivers_w:
		if Geometry2D.segment_intersects_segment(a, b, rw[0], rw[1]) != null:
			return false
	return true

## Partition farm sites into connected groups by the same-bank relation (BFS) — one group per bank.
func _bank_components(sites: Array, rivers_w: Array) -> Array:
	var n := sites.size()
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var groups: Array = []
	for i in n:
		if comp[i] != -1:
			continue
		var gi := groups.size()
		comp[i] = gi
		var members: Array = [i]
		var stack: Array = [i]
		while not stack.is_empty():
			var u: int = stack.pop_back()
			for v in n:
				if comp[v] == -1 and _same_bank(sites[u], sites[v], rivers_w):
					comp[v] = gi
					stack.append(v)
					members.append(v)
		groups.append(members)
	return groups

## Two fields are adjacent (share a side) when any of their edges come within `maxd` of each other.
func _polys_adjacent(a: PackedVector2Array, b: PackedVector2Array, maxd: float) -> bool:
	var na := a.size()
	var nb := b.size()
	if na < 2 or nb < 2:
		return false
	for i in na:
		for j in nb:
			if _seg_seg_dist(a[i], a[(i + 1) % na], b[j], b[(j + 1) % nb]) < maxd:
				return true
	return false

## Connected components of farms by FIELD adjacency (touching within `maxd`) — one web per group. A river
## separates fields spatially, so this also keeps banks apart without a separate same-bank test.
func _web_components(fields_w: Array, maxd: float) -> Array:
	var n := fields_w.size()
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var groups: Array = []
	for i in n:
		if comp[i] != -1:
			continue
		var gi := groups.size()
		comp[i] = gi
		var members: Array = [i]
		var stack: Array = [i]
		while not stack.is_empty():
			var u: int = stack.pop_back()
			for v in n:
				if comp[v] == -1 and _polys_adjacent(fields_w[u], fields_w[v], maxd):
					comp[v] = gi
					stack.append(v)
					members.append(v)
		groups.append(members)
	return groups

## A web's outer ring that HUGS its fields: offset each field outward by `d` and union them, so the
## outline follows concavities (vs a convex hull that bridges far across a C-shaped cluster).
func _union_offset_fields(fields_w: Array, indices: Array, d: float) -> PackedVector2Array:
	var polys: Array = []
	for idx in indices:
		for o in Geometry2D.offset_polygon(fields_w[idx], d, Geometry2D.JOIN_MITER):
			if (o as PackedVector2Array).size() >= 3 and not Geometry2D.is_polygon_clockwise(o):
				polys.append(o)
	polys = _union_polys(polys)
	var best := PackedVector2Array()
	var ba := -1.0
	for p in polys:
		var pa: float = BuildingShapes.polygon_area(p)
		if pa > ba:
			ba = pa
			best = p
	if best.size() < 3:
		# Fallback (rare union failure): a convex hull offset, so a web always has a ring.
		var pts := PackedVector2Array()
		for idx in indices:
			for v in (fields_w[idx] as PackedVector2Array):
				pts.append(v)
		if pts.size() >= 3:
			best = _offset_poly_out(Geometry2D.convex_hull(pts), d + 2.0)
	return best

## Boolean-union a list of (CCW outer) polygons into as few as possible — merges any pair whose union is
## a single outer ring, repeating until stable. Holes (CW) are dropped.
func _union_polys(polys: Array) -> Array:
	var acc: Array = polys.duplicate()
	var changed := true
	var guard := 0
	while changed and guard < 300:
		guard += 1
		changed = false
		for i in acc.size():
			var done := false
			for j in range(i + 1, acc.size()):
				var merged := Geometry2D.merge_polygons(acc[i], acc[j])
				var ccw: Array = []
				for p in merged:
					if not Geometry2D.is_polygon_clockwise(p):
						ccw.append(p)
				if ccw.size() == 1:   # the two combined into one outer ring
					acc[i] = ccw[0]
					acc.remove_at(j)
					changed = true
					done = true
					break
			if done:
				break
	return acc

## Expand a polygon outward by `d` with SHARP (mitred) corners so consecutive edges meet at exact
## shared vertices — the source poly if it fails.
func _offset_poly_out(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	if poly.size() < 3:
		return poly
	var parts := Geometry2D.offset_polygon(poly, d, Geometry2D.JOIN_MITER)
	return _largest_ccw(parts, poly)

## Regular heptagon (7-gon) of radius r around centre c, rotated by `rot`.
func _make_heptagon(c: Vector2, r: float, rot: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 7:
		var ang := rot + TAU * float(i) / 7.0
		out.append(c + Vector2(cos(ang), sin(ang)) * r)
	return out

## 0 if p is inside `poly`, else the distance to its nearest edge.
func _dist_point_to_poly(p: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() >= 3 and Geometry2D.is_point_in_polygon(p, poly):
		return 0.0
	var d := 1.0e9
	var n := poly.size()
	for k in n:
		d = minf(d, _pt_seg_dist(p, poly[k], poly[(k + 1) % n]))
	return d

## Parameter ranges [lo,hi] (along a→b) of the contiguous runs within `reach` of any polygon in `polys`.
func _near_field_runs(a: Vector2, b: Vector2, polys: Array, reach: float) -> Array:
	var out: Array = []
	var L := a.distance_to(b)
	if L < 0.001:
		return out
	var steps := maxi(4, int(L / 2.0))
	var run_lo := -1
	for s in range(steps + 1):
		var p := a.lerp(b, float(s) / float(steps))
		var near := false
		for poly in polys:
			if _dist_point_to_poly(p, poly) <= reach:
				near = true
				break
		if near and run_lo < 0:
			run_lo = s
		if (not near or s == steps) and run_lo >= 0:
			var hi := s if near else s - 1
			if hi > run_lo:
				out.append([float(run_lo) / float(steps), float(hi) / float(steps)])
			run_lo = -1
	return out

## The parts of segment a–b that lie OUTSIDE convex polygon `poly` (0, 1 or 2 sub-segments).
func _seg_outside_convex(a: Vector2, b: Vector2, poly: PackedVector2Array) -> Array:
	var inside := _clip_seg_to_convex(a, b, poly)
	if inside.size() < 2 or inside[0].distance_to(inside[1]) < 0.001:
		return [PackedVector2Array([a, b])]   # no overlap (or a point graze at a vertex) → all outside
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1.0e-6:
		return []
	var t0 := clampf((inside[0] - a).dot(ab) / l2, 0.0, 1.0)
	var t1 := clampf((inside[1] - a).dot(ab) / l2, 0.0, 1.0)
	if t0 > t1:
		var tmp := t0
		t0 = t1
		t1 = tmp
	var out: Array = []
	if t0 > 0.02:
		out.append(PackedVector2Array([a, a.lerp(b, t0)]))
	if t1 < 0.98:
		out.append(PackedVector2Array([a.lerp(b, t1), b]))
	return out

## The parts of segment a–b that stay farther than `clear` from every segment in `segs`.
func _seg_keep_away_from_segs(a: Vector2, b: Vector2, segs: Array, clear: float) -> Array:
	if segs.is_empty():
		return [PackedVector2Array([a, b])]
	var L := a.distance_to(b)
	if L < 0.001:
		return []
	var steps := maxi(4, int(L / 2.0))
	var out: Array = []
	var run_lo := -1
	for s in range(steps + 1):
		var p := a.lerp(b, float(s) / float(steps))
		var far := true
		for sg in segs:
			if _pt_seg_dist(p, sg[0], sg[1]) <= clear:
				far = false
				break
		if far and run_lo < 0:
			run_lo = s
		if (not far or s == steps) and run_lo >= 0:
			var hi := s if far else s - 1
			if hi > run_lo:
				out.append(PackedVector2Array([a.lerp(b, float(run_lo) / float(steps)), a.lerp(b, float(hi) / float(steps))]))
			run_lo = -1
	return out

## The tile's flat-top hex as a world polygon.
func _hex_world(coord: Vector2i) -> PackedVector2Array:
	var c := _tile_center_world_pos(coord)
	return PackedVector2Array([
		c + Vector2(-135, -240), c + Vector2(135, -240), c + Vector2(270, 0),
		c + Vector2(135, 240), c + Vector2(-135, 240), c + Vector2(-270, 0)])

## Average of a polygon's vertices (good enough to anchor an outbuilding centrally).
func _poly_centroid(poly: PackedVector2Array) -> Vector2:
	var s := Vector2.ZERO
	for v in poly:
		s += v
	return s / float(maxi(poly.size(), 1))

## True if every vertex of `local_verts` placed at world `c` lies inside polygon `poly`.
func _poly_inside(local_verts: PackedVector2Array, c: Vector2, poly: PackedVector2Array) -> bool:
	for v in local_verts:
		if not Geometry2D.is_point_in_polygon(c + v, poly):
			return false
	return true

## Looser containment: the centre point alone is inside (used as a last resort for thin fields).
func _poly_inside_loose(_local_verts: PackedVector2Array, c: Vector2, poly: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(c, poly)

## Sutherland–Hodgman: clip `poly` to the half-plane of points nearer to `si` than `sj`
## (i.e. on si's side of the perpendicular bisector of si–sj). Returns the clipped polygon.
func _clip_poly_halfplane(poly: PackedVector2Array, si: Vector2, sj: Vector2) -> PackedVector2Array:
	var nrm := sj - si                 # f(x) = nrm·(x - mid); keep f <= 0 (nearer si)
	var mid := (si + sj) * 0.5
	var c := nrm.dot(mid)
	var out := PackedVector2Array()
	var n := poly.size()
	for k in n:
		var a: Vector2 = poly[k]
		var b: Vector2 = poly[(k + 1) % n]
		var fa := nrm.dot(a) - c
		var fb := nrm.dot(b) - c
		if fa <= 0.0:
			out.append(a)
		if (fa <= 0.0) != (fb <= 0.0):
			out.append(a + (b - a) * (fa / (fa - fb)))
	return out

## Largest counter-clockwise (outer, non-hole) ring from intersect_polygons output; `fallback` if none.
func _largest_ccw(parts: Array, fallback: PackedVector2Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_a := -1.0
	for p in parts:
		if Geometry2D.is_polygon_clockwise(p):
			continue
		var pa: float = BuildingShapes.polygon_area(p)
		if pa > best_a:
			best_a = pa
			best = p
	if not best.is_empty():
		return best
	return fallback   # only holes (all-CW) — never return a hole; revert to the CCW fallback

## The Voronoi edge between sites i and j: the bisector segment clipped to the hex and to the
## half-planes "nearer i than every other site k" (on the bisector dist_i == dist_j). [] if none.
func _voronoi_edge(sites: Array, i: int, j: int, hex: PackedVector2Array) -> PackedVector2Array:
	var si: Vector2 = sites[i]
	var sj: Vector2 = sites[j]
	var dir: Vector2 = sj - si
	if dir.length() < 0.001:
		return PackedVector2Array()
	var mid := (si + sj) * 0.5
	var perp := Vector2(-dir.y, dir.x).normalized()
	var seg := _clip_seg_to_convex(mid - perp * 2000.0, mid + perp * 2000.0, hex)
	for k in sites.size():
		if k == i or k == j or seg.size() < 2:
			continue
		seg = _clip_seg_halfplane(seg[0], seg[1], si, sites[k])
	return seg

## Clip segment a–b to a convex polygon (keeps the part inside). [] if fully outside.
func _clip_seg_to_convex(a: Vector2, b: Vector2, poly: PackedVector2Array) -> PackedVector2Array:
	var ctr := _poly_centroid(poly)
	var pa := a
	var pb := b
	var n := poly.size()
	for k in n:
		var e0: Vector2 = poly[k]
		var e1: Vector2 = poly[(k + 1) % n]
		var edge := e1 - e0
		var nrm := Vector2(-edge.y, edge.x)
		if nrm.dot(ctr - e0) < 0.0:
			nrm = -nrm                    # make the normal point inward (toward the centroid)
		var res := _clip_seg_by_line(pa, pb, nrm, e0)
		if res.size() < 2:
			return PackedVector2Array()
		pa = res[0]
		pb = res[1]
	return PackedVector2Array([pa, pb])

## Clip segment a–b to the half-plane of points nearer to si than sk.
func _clip_seg_halfplane(a: Vector2, b: Vector2, si: Vector2, sk: Vector2) -> PackedVector2Array:
	return _clip_seg_by_line(a, b, si - sk, (si + sk) * 0.5)

## Keep the part of segment a–b where nrm·(x − p0) >= 0. [] if fully clipped away.
func _clip_seg_by_line(a: Vector2, b: Vector2, nrm: Vector2, p0: Vector2) -> PackedVector2Array:
	var fa := nrm.dot(a - p0)
	var fb := nrm.dot(b - p0)
	var a_in := fa >= 0.0
	var b_in := fb >= 0.0
	if a_in and b_in:
		return PackedVector2Array([a, b])
	if not a_in and not b_in:
		return PackedVector2Array()
	var ip := a + (b - a) * (fa / (fa - fb))
	return PackedVector2Array([a, ip]) if a_in else PackedVector2Array([ip, b])

## Build (once) the tile's buildable mask, elevation field, buildable cell keys, and the
## road frontage segments. Buildable = inside the flat-top hex ∧ not water ∧ outside road
## clearance ∧ outside every forest disc.
func _ensure_tile(tile_id: String, coord: Vector2i) -> void:
	if _tile_land.has(tile_id):
		return
	var n := GRID_COLS * GRID_ROWS
	var land := PackedByteArray(); land.resize(n)
	var farm_land := PackedByteArray(); farm_land.resize(n)   # farms tolerate the outer 30% of forest discs
	var center := _tile_center_world_pos(coord)
	var nav := NavGrid.instance()
	var nav_ok := nav != null and nav.is_ready()
	if not nav_ok and not _warned_no_nav:
		# Degenerate (unbaked map): can't exclude water/elevation. We still place so
		# relayout() has something to replay; once a bake exists nav loads (synchronously
		# on instance()) and relayout re-masks this tile correctly.
		_warned_no_nav = true
		push_warning("BuildingVisuals: NavGrid not ready — water/elevation exclusion skipped until relayout.")
	# Ungated road source: the buildable mask (and frontage) must avoid EVERY built road
	# crossing the tile, not only tiles whose "roads" infra flag is set — otherwise a tile that
	# has a road (baked spine, NPC connect, or a road built before the mask was first cached)
	# lets buildings land on top of it. _block_road_segments reads RoadNetwork directly.
	var segs := _block_road_segments(coord)
	if MASK_DEBUG:
		var gated := _tile_road_segments(coord, center)
		if segs.size() > gated.size():
			print("[MASKDBG] %s: gate HID %d road segs (using %d; infra_roads=%s)" % [tile_id, segs.size() - gated.size(), segs.size(), str((terrain_layer.tiles.get(coord, {}).get("infrastructure_present", []) as Array).has("roads"))])
	var discs := _forest_discs(coord, center)
	var rivers := _tile_river_segments(coord, center)
	var reserved := _bridge_approach_segments(tile_id, center)   # bridge-approach corridors
	var lake := _tile_lake(coord, center)
	# Road clearance, rasterized: stamp each segment's grown bbox instead of
	# scanning every seg per cell. The roads-v3 start network puts finely-sampled
	# (~12u) polylines on most tiles, so the old 648-cells × all-segs scan was
	# ~150k _pt_seg_dist calls per tile (~25 s of world build across the map).
	# Carve the mask at the TIGHTEST clearance any caller may ask for, not at
	# ROAD_CLEAR. The mask used to forbid everything within 18u of a road, which
	# made the 5.5u art frontage structurally impossible — the audit showed
	# 99.9% of rejected frontage candidates failing here rather than on the
	# road-clearance test. Each caller still enforces its own distance through
	# _valid/_farm_valid/_wing_valid, so nothing gets closer than it should.
	var road_block := _rasterize_seg_clearance(segs, MASK_ROAD_CLEAR)
	# Port quay/pier strip: the dock composition is drawn decoration with no
	# placement footprint — without this carve, buildings legally packed under
	# it and the port (z=60) drew over them (owner report, Stoneshore Docks).
	var port_blocks := _port_block_frames(coord, center)
	var keys := PackedInt32Array()
	var farm_keys := PackedInt32Array()
	for row in GRID_ROWS:
		for col in GRID_COLS:
			var rel := Vector2((col + 0.5) * CELL, (row + 0.5) * CELL) - TILE_CENTER
			if absf(rel.x) > 270.0 or absf(rel.y) > 240.0 or 240.0 * absf(rel.x) + 135.0 * absf(rel.y) > 64800.0:
				continue   # outside the flat-top hex
			var key := row * GRID_COLS + col
			if road_block[key] == 1:
				continue   # too close to a road carriageway
			var in_port := false
			for pb in port_blocks:
				var dd: Vector2 = rel - (pb.o as Vector2)
				var dp := dd.dot(pb.dir as Vector2)
				var pp := dd.dot(Vector2(-(pb.dir as Vector2).y, (pb.dir as Vector2).x))
				if dp > -70.0 and dp < 170.0 and absf(pp) < 150.0:
					in_port = true
					break
			if in_port:
				continue   # under the dock quay/piers
			if nav_ok:
				var c := nav.cell_of(center + rel)
				if nav.water(c.x, c.y) != 0:
					continue   # water (sea/lake/river) — not buildable
				if nav.level(c.x, c.y) < MIN_BUILD_LEVEL:
					continue   # at/below the waterline — no buildings (same rule roads should use)
			# Reserved road corridor: a band along the river (room for a bank road) + a stub
			# straight out from each bridge (clean approach), so the road never has to run
			# over riverside buildings. Buildings keep RIVER_ROAD_PAD off both.
			var in_corridor := false
			for rseg in rivers:
				if _pt_seg_dist(rel, rseg[0], rseg[1]) < RIVER_ROAD_PAD:
					in_corridor = true
					break
			if not in_corridor:
				for rsv in reserved:
					if _pt_seg_dist(rel, rsv[0], rsv[1]) < RIVER_ROAD_PAD:
						in_corridor = true
						break
			if in_corridor:
				continue
			if not lake.is_empty():
				var dl: Vector2 = rel - lake.c
				if (dl.x * dl.x) / (lake.rx * lake.rx) + (dl.y * dl.y) / (lake.ry * lake.ry) <= 1.0:
					continue   # inside a source lake
			# Forest is the last gate: regular buildings stay outside the whole disc; farms tolerate the
			# outer 30% (inside FARM_FOREST_TOL x radius) so they nestle closer to forests.
			var norm := 1.0e9
			for d in discs:
				norm = minf(norm, rel.distance_to(d.c) / maxf(d.r, 1.0))
			if norm >= 1.0:
				land[key] = 1
				keys.append(key)
			if norm >= FARM_FOREST_TOL:
				farm_land[key] = 1
				farm_keys.append(key)
	_tile_land[tile_id] = land
	_tile_landkeys[tile_id] = keys
	_farm_land[tile_id] = farm_land
	_farm_landkeys[tile_id] = farm_keys
	_tile_segs[tile_id] = segs
	_tile_rivers[tile_id] = rivers

## Cells of the tile grid within `pad` of any segment, as a 1-bit mask. Each
## segment only visits its own grown bbox (a few cells for the ~12u-sampled road
## polylines), with the exact point-segment distance test inside — same result
## as the brute-force per-cell scan at a fraction of the cost.
## Oriented block frames for any dock on this tile — mirrors port_visuals'
## glyph math (position 0.30 tile-heights toward the first sea neighbour,
## facing seaward). Entries: {o: rel-space origin, dir: seaward direction}.
func _port_block_frames(coord: Vector2i, center: Vector2) -> Array:
	var out: Array = []
	if terrain_layer == null:
		return out
	var tile_h := 480.0
	for p in Catalog.all_ports():
		var pcoord: Vector2i = terrain_layer.id_to_coord(str(p.get("tile_id", "")))
		if pcoord != coord:
			continue
		var cell: Vector2i = terrain_layer.map_coord_for_tile_coord(coord)
		for ncell in terrain_layer.get_surrounding_cells(cell):
			var ntile: Dictionary = terrain_layer.tiles.get(terrain_layer.tile_coord_for_map_coord(ncell), {})
			if str(ntile.get("type", "")) in ["sea", "deep_sea"]:
				var sea_dir := (terrain_layer.map_to_local(ncell) - terrain_layer.map_to_local(cell)).normalized()
				out.append({"o": sea_dir * tile_h * 0.30, "dir": sea_dir})
				break
	return out

func _rasterize_seg_clearance(segs: Array, pad: float) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(GRID_COLS * GRID_ROWS)
	for s in segs:
		var a: Vector2 = (s[0] as Vector2) + TILE_CENTER
		var b: Vector2 = (s[1] as Vector2) + TILE_CENTER
		var min_col := clampi(int(floorf((minf(a.x, b.x) - pad) / CELL - 0.5)), 0, GRID_COLS - 1)
		var max_col := clampi(int(ceilf((maxf(a.x, b.x) + pad) / CELL - 0.5)), 0, GRID_COLS - 1)
		var min_row := clampi(int(floorf((minf(a.y, b.y) - pad) / CELL - 0.5)), 0, GRID_ROWS - 1)
		var max_row := clampi(int(ceilf((maxf(a.y, b.y) + pad) / CELL - 0.5)), 0, GRID_ROWS - 1)
		for row in range(min_row, max_row + 1):
			for col in range(min_col, max_col + 1):
				var key := row * GRID_COLS + col
				if mask[key] == 1:
					continue
				var rel := Vector2((col + 0.5) * CELL, (row + 0.5) * CELL) - TILE_CENTER
				if _pt_seg_dist(rel, s[0], s[1]) < pad:
					mask[key] = 1
	return mask

## Place one building. Returns {verts (world), center_rel, half}; {} if nothing fits.
func _search(tile_id: String, coord: Vector2i, kind: String, area: float, seed_v: int, cat: String, is_edge: bool, placed_here: Array, road_clear: float = ROAD_CLEAR, override_verts: PackedVector2Array = PackedVector2Array()) -> Dictionary:
	if not _tile_land.has(tile_id):
		return {}   # caller must _ensure_tile first; never KeyError-crash on a miss
	var land: PackedByteArray = _tile_land[tile_id]
	if cat == "farm":
		# Farms are irregular polygonal fields. They gravitate to the river — unless non-farm
		# buildings already occupy the tile, in which case (built after them) they retreat to the
		# tile edge. Either way the field may overhang the hex and is then clipped to it.
		# 3× linear → ×(scale²) area (farm_field radius ∝ √area). Big fields that clip at the hex edge.
		var fverts: PackedVector2Array = BuildingShapes.farm_field(area * FARM_FIELD_SCALE * FARM_FIELD_SCALE, seed_v).verts
		var toward_river := not _has_non_farm_buildings(tile_id)
		var farm_mask: PackedByteArray = _farm_land.get(tile_id, land)   # farms nestle closer to forests
		var placed := _place_farm(tile_id, coord, fverts, placed_here, farm_mask, toward_river)
		if not placed.is_empty():
			placed.verts = _clip_to_hex(placed.verts, coord)
		return placed
	# Shape-language buildings supply their own lot (the sprite's box); everyone
	# else gets the seeded plate shape sized from `area`.
	var base_verts: PackedVector2Array = override_verts if not override_verts.is_empty() else BuildingShapes.make(kind, area, seed_v).verts
	if is_edge:
		return _place_edge(tile_id, coord, base_verts, placed_here, land, road_clear)
	return _place_frontage(tile_id, coord, base_verts, cat, placed_here, land, road_clear)

## Offshore placement: pick the WATER cell that maximises distance to the
## buildings already on the tile (capped so ties break toward the tile centre)
## — platforms and wind farms spread out at a uniform distance, clear of the
## hex rim. No roads, rivers or land rules apply out at sea.
func _place_offshore(coord: Vector2i, area: float, placed_here: Array) -> Dictionary:
	var center := _tile_center_world_pos(coord)
	var nav := NavGrid.instance()
	if nav == null or not nav.is_ready():
		return {}
	var side := sqrt(maxf(area, BUILDABLE_MIN_AREA))
	var verts: PackedVector2Array = BuildingShapes.make_rect(side * 1.25, side * 0.8).verts
	var half := _aabb_half(verts)
	var best := Vector2.INF
	var best_score := -INF
	for row in GRID_ROWS:
		for col in GRID_COLS:
			var rel := Vector2((col + 0.5) * CELL, (row + 0.5) * CELL) - TILE_CENTER
			if absf(rel.x) > 240.0 or absf(rel.y) > 210.0 or 240.0 * absf(rel.x) + 135.0 * absf(rel.y) > 57000.0:
				continue   # inset hex — keep platforms off the tile border
			var c := nav.cell_of(center + rel)
			if nav.water(c.x, c.y) == 0:
				continue   # land — offshore structures sit on water
			if _overlaps(rel, half, placed_here):
				continue
			var score := minf(_nearest_building_dist(rel, placed_here), OFFSHORE_MIN_SEP * 2.0) - rel.length() * 0.05
			if score > best_score:
				best_score = score
				best = rel
	if best == Vector2.INF:
		return {}
	var p := _finalize(coord, best, verts, half)
	p["offshore"] = true
	return p

## Tight row along a road frontage: orient the long axis along the road, snap flush to the
## carriageway clearance, and take the first free slot (which abuts the prior building with
## ~DESIGN_GAP). Falls back to abutting the nearest neighbour, then to the lowest free cell.
func _place_frontage(tile_id: String, coord: Vector2i, base_verts: PackedVector2Array, cat: String, placed_here: Array, land: PackedByteArray, road_clear: float = ROAD_CLEAR) -> Dictionary:
	var segs: Array = _tile_segs.get(tile_id, [])
	var rivers: Array = _tile_rivers.get(tile_id, [])
	# Pre-rotation half: because we rotate the shape's long axis (local x) onto the road
	# tangent, the shape's local y maps exactly onto the road normal — so base_half.y is
	# the building's true depth perpendicular to the road, used to snap its near edge flush.
	var base_half := _aabb_half(base_verts)
	var best := {}
	var best_score := INF
	var diag := {"tried": 0, "land": 0, "overlap": 0, "road": 0, "river": 0, "segs": segs.size()}
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var tangent := b - a
		var seg_len := tangent.length()
		if seg_len < 1.0:
			continue
		tangent /= seg_len
		var normal := Vector2(-tangent.y, tangent.x)
		var rv := _rotate(base_verts, tangent.angle())   # long axis (x) now runs along the road
		var half := _aabb_half(rv)
		# Snap flush: near edge sits DESIGN_GAP past the carriageway clearance. Try both
		# sides of the road; keep whichever side has buildable land.
		for side in [1.0, -1.0]:
			# Use the CALLER's clearance, not the constant — art buildings pass a
			# tight frontage (ART_ROAD_PAD) and were being snapped at ROAD_CLEAR
			# anyway, parking them ~12u further off the carriageway than asked.
			var off: Vector2 = normal * side * (road_clear + base_half.y + DESIGN_GAP)
			var t := 0.0
			while t <= seg_len:
				var center: Vector2 = a + tangent * t + off
				if _valid(center, rv, half, placed_here, land, segs, rivers, road_clear):
					var score := _row_score(center, cat, placed_here)
					if score < best_score:
						best_score = score
						best = {"center": center, "rv": rv, "half": half}
					break   # first free slot on this side of this segment
				elif DIAG:
					diag.tried += 1
					var why := _reject_reason(center, rv, half, placed_here, land, segs, rivers, road_clear)
					diag[why] = int(diag.get(why, 0)) + 1
				t += PACK_STEP
	if not best.is_empty():
		var okr := _finalize(coord, best.center, best.rv, best.half)
		okr["via"] = "frontage"
		return okr

	# Fallback A: no usable frontage — abut the nearest existing building (any type) with
	# DESIGN_GAP, axis-aligned, so a roadless tile still packs into a cluster.
	var half0 := _aabb_half(base_verts)
	var nb := _nearest_placed(placed_here)
	if not nb.is_empty():
		for dir in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			var span: float = (nb.half * dir.abs()).length() + (half0 * dir.abs()).length() + DESIGN_GAP
			var center: Vector2 = nb.pos + dir * span
			if _valid(center, base_verts, half0, placed_here, land, segs, rivers, road_clear):
				var ar := _finalize(coord, center, base_verts, half0)
				ar["via"] = "abut"
				ar["diag"] = diag
				return ar

	# Fallback B: the free cell nearest the tile centre (first building on a roadless tile).
	# Centre-seeking — NOT lowest-elevation — so a roadless cluster forms inland rather than
	# sliding down to the coast / waterline.
	var best_center := Vector2.INF
	var best_d := 1.0e9
	for key in (_tile_landkeys[tile_id] as PackedInt32Array):
		var rel := Vector2(((key % GRID_COLS) + 0.5) * CELL, ((key / GRID_COLS) + 0.5) * CELL) - TILE_CENTER
		if not _valid(rel, base_verts, half0, placed_here, land, segs, rivers, road_clear):
			continue
		var d := rel.length()
		if d < best_d:
			best_d = d
			best_center = rel
	if best_center != Vector2.INF:
		var br := _finalize(coord, best_center, base_verts, half0)
		br["via"] = "any"
		br["diag"] = diag
		return br
	return {}

## First failing gate for a rejected candidate — the frontage search's "why".
## `land` folds hex bounds, water, elevation, forest and the river corridor.
func _reject_reason(center: Vector2, local_verts: PackedVector2Array, half: Vector2, placed_here: Array, land: PackedByteArray, segs: Array, rivers: Array, road_clear: float) -> String:
	if not _footprint_on_land(center, local_verts, land):
		return "land"
	if _overlaps(center, half, placed_here):
		return "overlap"
	if not _footprint_clears(center, local_verts, segs, road_clear):
		return "road"
	if not _footprint_clears(center, local_verts, rivers, RIVER_CLEAR):
		return "river"
	return "?"

## Edge-seeker (recycling/extraction): the free land cell that maximises distance from the
## tile centre and from other buildings, i.e. a far empty corner. Axis-aligned.
func _place_edge(tile_id: String, coord: Vector2i, base_verts: PackedVector2Array, placed_here: Array, land: PackedByteArray, road_clear: float = ROAD_CLEAR) -> Dictionary:
	var segs: Array = _tile_segs.get(tile_id, [])
	var rivers: Array = _tile_rivers.get(tile_id, [])
	var half := _aabb_half(base_verts)
	var best_center := Vector2.INF
	var best_score := -INF
	for key in (_tile_landkeys[tile_id] as PackedInt32Array):
		var rel := Vector2(((key % GRID_COLS) + 0.5) * CELL, ((key / GRID_COLS) + 0.5) * CELL) - TILE_CENTER
		if not _valid(rel, base_verts, half, placed_here, land, segs, rivers, road_clear):
			continue
		if not _footprint_dry(rel, base_verts, coord):
			continue   # the rim is where the water is
		var score := rel.length() + W_AWAY * _nearest_building_dist(rel, placed_here)
		if score > best_score:
			best_score = score
			best_center = rel
	if best_center == Vector2.INF:
		return {}
	var er := _finalize(coord, best_center, base_verts, half)
	er["via"] = "edge"
	return er

## Point-wise water test over a footprint. The buildable mask is a grid and the
## edge-seeker deliberately heads for the tile rim, where a corner can hang over
## the coast between sampled cells — an onshore wind farm ended up on water
## (owner report). Offshore structures are exempt; they belong there.
func _footprint_dry(center: Vector2, local_verts: PackedVector2Array, coord: Vector2i) -> bool:
	var nav := NavGrid.instance()
	if nav == null or not nav.is_ready():
		return true
	var origin := _tile_center_world_pos(coord)
	for v in local_verts:
		var c := nav.cell_of(origin + center + v)
		if nav.water(c.x, c.y) != 0:
			return false
	var cc := nav.cell_of(origin + center)
	return nav.water(cc.x, cc.y) == 0

## True if the tile already carries a non-farm building (forests never enter _placements, so
## any placement with cat != "farm" is a non-farm/non-forest building).
func _has_non_farm_buildings(tile_id: String) -> bool:
	for e in _placed_on_tile(tile_id):
		if str(e.cat) != "farm":
			return true
	return false

## World points of every farm on a hex-NEIGHBOUR tile that lies within FARM_CROSS_TILE_RADIUS of
## this tile's centre — i.e. farms hugging a shared edge from the other side. Computed ONCE per
## _place_farm call (never per cell). Only the 6 adjacent tiles count, so a cluster two tiles over
## never tugs across a gap. Empty unless terrain is ready and a neighbour farm is in range.
func _neighbor_farm_world_pts(tile_id: String, coord: Vector2i) -> PackedVector2Array:
	var out := PackedVector2Array()
	if terrain_layer == null:
		return out
	var nb_coords: Array[Vector2i] = terrain_layer.neighbor_coords(coord)
	var my_center := _tile_center_world_pos(coord)
	for p in _placements:
		if str(p.get("cat", "")) != "farm" or str(p.get("tile_id", "")) == tile_id:
			continue                                   # same-tile farms mate via intra-tile Voronoi, not affinity
		var pc: Vector2i = p.get("coord", coord)
		if not nb_coords.has(pc):
			continue                                   # only a directly-adjacent tile pulls across the shared edge
		var wp: Vector2 = _tile_center_world_pos(pc) + (p.get("center_rel", Vector2.ZERO) as Vector2)
		if my_center.distance_to(wp) <= FARM_CROSS_TILE_RADIUS:
			out.append(wp)
	return out

## Farm field placement: scan buildable cells, keep the one that best matches the field's
## affinity. CROSS-TILE EDGE AFFINITY dominates when a neighbour tile already has farms near a
## shared edge: the score becomes the world distance to the nearest such farm, so the new field
## hugs that edge and the cluster visually continues across the tile boundary. (This intentionally
## overrides river/edge affinity on tiles adjacent to existing farms — continuity wins; _farm_valid
## still enforces RIVER_CLEAR so a field never lands on the water.) With no neighbour farm in range
## it falls back to the original affinity — nearest a river arm (toward_river; centre-dist when the
## tile has no river) or farthest from the tile centre (= toward the edge). Order-dependent and
## best-effort: only the LATER-placed tile of a pair can align (we never re-place existing farms).
## Uses the relaxed _farm_valid so a field may overhang the hex (clipped afterwards) but never lands
## on water/forest/road/another building. Falls back to abutting a neighbour.
func _place_farm(tile_id: String, coord: Vector2i, base_verts: PackedVector2Array, placed_here: Array, land: PackedByteArray, toward_river: bool) -> Dictionary:
	var segs: Array = _tile_segs.get(tile_id, [])
	var rivers: Array = _tile_rivers.get(tile_id, [])
	var half := _aabb_half(base_verts)
	var nbr_pts: PackedVector2Array = _neighbor_farm_world_pts(tile_id, coord)   # precomputed ONCE
	var has_nbr := nbr_pts.size() > 0
	var tile_origin := _tile_center_world_pos(coord)
	var best_center := Vector2.INF
	# Score every candidate cell first (cheap), then validate lazily in best-first
	# order and take the first valid one. Identical outcome to validate-then-min
	# (strict < keeps the earlier grid key on ties), but the expensive footprint
	# validation (10 verts × every road/river segment) runs on a handful of cells
	# instead of all ~500 — placing the 119 start farms cost ~18 s before this.
	var cands: Array = []   # [score, original_order, rel]
	var order := 0
	for key in (_farm_landkeys.get(tile_id, _tile_landkeys.get(tile_id, PackedInt32Array())) as PackedInt32Array):
		var rel := Vector2(((key % GRID_COLS) + 0.5) * CELL, ((key / GRID_COLS) + 0.5) * CELL) - TILE_CENTER
		var score: float
		if has_nbr:
			var world := tile_origin + rel
			var nd := 1.0e9
			for wp in nbr_pts:
				nd = minf(nd, world.distance_to(wp))
			score = nd                                  # minimise distance to nearest neighbour-tile farm
		else:
			score = _dist_to_rivers(rel, rivers) if toward_river else -rel.length()
		cands.append([score, order, rel])
		order += 1
	cands.sort_custom(func(a, b) -> bool:
		return float(a[0]) < float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
	for c in cands:
		best_center = c[2] as Vector2
		if _farm_valid(best_center, base_verts, half, placed_here, land, segs, rivers):
			return _finalize(coord, best_center, base_verts, half)
	var nb := _nearest_placed(placed_here)   # fallback: abut a neighbour
	if not nb.is_empty():
		for dir in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			var span: float = (nb.half * dir.abs()).length() + (half * dir.abs()).length() + DESIGN_GAP
			var center: Vector2 = nb.pos + dir * span
			if _farm_valid(center, base_verts, half, placed_here, land, segs, rivers):
				return _finalize(coord, center, base_verts, half)
	return {}

## Relaxed validity for farm fields: like _valid, but the footprint may extend OUTSIDE the hex
## (those parts get clipped). It must still keep clear of roads, rivers and other buildings, and
## every in-hex part of the footprint must be buildable land (no water/forest/off-elevation).
func _farm_valid(center: Vector2, local_verts: PackedVector2Array, half: Vector2, placed_here: Array, land: PackedByteArray, segs: Array, rivers: Array) -> bool:
	return _farm_footprint_ok(center, local_verts, land) \
		and not _farm_overlaps(center, half, placed_here) \
		and _footprint_clears(center, local_verts, segs, ROAD_CLEAR) \
		and _footprint_clears(center, local_verts, rivers, RIVER_CLEAR)

## Farm overlap rule: a farm keeps the full AABB clear of NON-farm buildings, but only a centre
## spacing (FARM_MIN_SEP) from other FARMS — adjacent fields are meant to overlap pre-clip and then
## Voronoi-snap to the lane between them, so a strict AABB would keep them too far apart to share a lane.
func _farm_overlaps(center: Vector2, half: Vector2, placed_here: Array) -> bool:
	for e in placed_here:
		if str(e.get("cat", "")) == "farm":
			if center.distance_to(e.pos) < FARM_MIN_SEP:
				return true
		elif absf(center.x - e.pos.x) < half.x + e.half.x and absf(center.y - e.pos.y) < half.y + e.half.y:
			return true
	return false

## Centre must be buildable land; every vertex must be buildable land OR outside the hex.
func _farm_footprint_ok(center: Vector2, local_verts: PackedVector2Array, land: PackedByteArray) -> bool:
	if not _land_at(center, land):
		return false
	for v in local_verts:
		var rel := center + v
		if _in_hex_rel(rel) and not _land_at(rel, land):
			return false
	return true

## Flat-top hex test in tile-local (TILE_CENTER-relative) coordinates.
func _in_hex_rel(rel: Vector2) -> bool:
	return absf(rel.x) <= 270.0 and absf(rel.y) <= 240.0 and 240.0 * absf(rel.x) + 135.0 * absf(rel.y) <= 64800.0

## Distance from a tile-rel point to the nearest river arm; centre-distance when the tile has no river.
func _dist_to_rivers(rel: Vector2, rivers: Array) -> float:
	if rivers.is_empty():
		return rel.length()
	var d := 1.0e9
	for rseg in rivers:
		d = minf(d, _pt_seg_dist(rel, rseg[0], rseg[1]))
	return d

## Clip a farm's WORLD verts to the tile's flat-top hex (so a field at the edge cuts off cleanly).
func _clip_to_hex(world_verts: PackedVector2Array, coord: Vector2i) -> PackedVector2Array:
	var c := _tile_center_world_pos(coord)
	var hex := PackedVector2Array([
		c + Vector2(-135, -240), c + Vector2(135, -240), c + Vector2(270, 0),
		c + Vector2(135, 240), c + Vector2(-135, 240), c + Vector2(-270, 0)])
	var parts := Geometry2D.intersect_polygons(world_verts, hex)
	if parts.is_empty():
		return world_verts
	# intersect_polygons returns outer rings CCW and any holes CW — keep the largest OUTER ring so
	# a hole can never be drawn as the field (defensive; a star-shaped field ∩ convex hex has none).
	var best := PackedVector2Array()
	var best_a := -1.0
	for p in parts:
		if Geometry2D.is_polygon_clockwise(p):
			continue
		var pa: float = BuildingShapes.polygon_area(p)
		if pa > best_a:
			best_a = pa
			best = p
	return best if not best.is_empty() else world_verts

## Bake the dark-green diagonal hatch lines for a farm field (clipped to the polygon) ONCE at
## placement — recomputing per-frame across ~119 farms would be far too costly.
func _bake_farm_hatch(verts: PackedVector2Array) -> Array:
	var out: Array = []
	if verts.size() < 3:
		return out
	var bb := _verts_bb(verts)
	var ctr := bb.position + bb.size * 0.5
	var d := Vector2(0.7071, 0.7071)    # 45° hatch direction
	var n := Vector2(-0.7071, 0.7071)   # perpendicular offset axis
	var reach := bb.size.length()
	var ext := reach * 0.5
	var off := -ext
	while off <= ext:
		var mid := ctr + n * off
		var clipped := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([mid - d * reach, mid + d * reach]), verts)
		for seg in clipped:
			out.append(seg)
		off += FARM_HATCH_SPACING
	return out

## [centroid, principal angle]: the polygon's PCA long axis.
func _poly_long_axis(verts: PackedVector2Array) -> Array:
	var ctr := Vector2.ZERO
	for v in verts:
		ctr += v
	ctr /= float(verts.size())
	var sxx := 0.0
	var sxy := 0.0
	var syy := 0.0
	for v in verts:
		var r := v - ctr
		sxx += r.x * r.x
		sxy += r.x * r.y
		syy += r.y * r.y
	return [ctr, 0.5 * atan2(2.0 * sxy, sxx - syy)]

## Ink-mode furrows: hatch lines along a polygon's LONG AXIS (+ang_offset for
## the occasional deliberately-perpendicular parcel) with a small seeded
## angle jitter. Used per-parcel by the P3b fabric; deterministic.
func _bake_farm_furrows(verts: PackedVector2Array, ang_offset: float = 0.0) -> Array:
	var out: Array = []
	if verts.size() < 3:
		return out
	var axis := _poly_long_axis(verts)
	var ctr: Vector2 = axis[0]
	var ang: float = float(axis[1]) + ang_offset
	ang += deg_to_rad(float(RoadHash.pick("furrow|%d|%d" % [roundi(ctr.x), roundi(ctr.y)], 13)) - 6.0)
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	var bb := _verts_bb(verts)
	var reach := bb.size.length()
	var ext := reach * 0.5
	var off := -ext
	while off <= ext:
		var mid := ctr + n * off
		var clipped := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([mid - d * reach, mid + d * reach]), verts)
		for seg in clipped:
			out.append(seg)
		off += FURROW_SPACING
	return out

# ── P3b parcel fabric (ink farms) ──────────────────────────────────────────────
const PARCEL_STRIP_MIN := 30.0   # strip width range across the long axis
const PARCEL_STRIP_MAX := 55.0
const PARCEL_CUT_MIN := 40.0     # cross-cut spacing range along the long axis
const PARCEL_CUT_MAX := 80.0
const PARCEL_SHEAR_DEG := 3.0    # per-cut tilt so cells are trapezoids, not graph paper
const PARCEL_INSET := 2.2        # gap: the base path-tan shows through = the little roads
const PARCEL_MIN_AREA := 250.0   # drop boundary slivers (base shows = path widening)
const FURROW_SPACING := 7.0      # ink furrow pitch (owner: denser than the classic 12u hatch)

# ── Ink building art (procedural shape language — DEFAULT in both styles) ──────
## internal_name -> InkBuildingGen recipe key (aliases collapse variants).
## Owner 2026-07-23: the shape-language art is the default building look in
## BOTH map styles, and its lot is reserved at ART size so the packer
## separates what is actually drawn (plate-sized lots caused overlap).
const INK_ART_KEY := {
	"furnace": "furnace", "eaf": "eaf", "industrial_factory": "industrial_factory",
	"consumer_factory": "consumer_factory", "assembly_plant": "assembly_plant",
	"high_tech_manufactory": "high_tech_manufactory", "petro_refinery": "petro_refinery",
	"chem_plant": "chem_plant", "poly_plant": "poly_plant", "electrolyser": "electrolyser",
	"coal_power": "power_plant", "water_pump": "water_pump", "mine": "mine",
	"solar_farm": "solar_farm",
	"onshore_wind_farm": "wind_farm", "offshore_wind_farm": "wind_farm",
	"pipes": "pipes", "reinf_pipes": "pipes", "cables": "cables",
}
## Lot side scales with tile_size_used from the smallest class to 3x for the
## biggest (owner's 10:30 ratio); levels never rescale the art — the L3 frame
## is the lot and upgrades annex into it.
## Lot sides match the drawn bounds, so a lot reserves exactly what gets drawn
## — no wasted ground (which was crowding buildings off dense tiles).
const ART_SIDE_MIN := 40.0
const ART_SIDE_MAX := 90.0
const ART_ROAD_PAD := 5.5    # art frontage: footprint edge ~1u off the carriageway edge
## Placement diagnostics (tools/road_frontage_audit). Off in play: classifying
## a rejected candidate costs four extra predicate calls, and the frontage
## search rejects a lot of candidates.
static var DIAG := false
## Hard bounds on the DRAWN sprite's long side, in world units (owner ruling
## 2026-07-23). Applied at draw time so it holds no matter which placement path
## sized the lot — block-template lots ignore the art lot area entirely.
## Scaled by tile_size_used, whose real range in the buildings CSV is 1..30
## (1-2 = tiny infra, 10 = the bulk, 30 = mine, the largest).
const ART_DRAWN_MIN := 40.0
const ART_DRAWN_MAX := 90.0
const ART_SIZE_UNITS_MAX := 30.0
## Per-recipe drawn-size overrides. Wind sites sprawl — at the size-10 default
## they read as a cramped cluster rather than machines spread over open ground
## (owner). Visual only: it moves the lot too, so reservation stays honest.
const ART_SIZE_OVERRIDE := {"wind_farm": ART_DRAWN_MAX}
## Blocked space is the DRAWN sprite plus this margin, not the lot the packer
## reserved — a lot is sized for the biggest thing that could stand on it, and
## treating all of it as solid wasted ground and pushed neighbours away.
const ART_BLOCK_MARGIN := 6.0
## Sprawling sites that belong on open ground rather than fronting a street
## (owner): pits and renewable farms. They take the edge-seeker path — the same
## one extraction uses — so they head for an empty corner of the tile, and the
## frontage audit counts them as off-road by design rather than as failures.
const OFF_ROAD_NAMES := {
	"mine": true, "solar_farm": true,
	"onshore_wind_farm": true, "offshore_wind_farm": true,
}
var _ink_art_iid: Dictionary = {}   # instance_id -> true (suppress procedural subcomponents)

## P3b (ink farms): subdivide the DRAWN field into an oriented seeded grid of
## rect/trapezoid parcels clipped at the field boundary; each parcel is inset
## so the path-tan base reads as the small roads between plots. Seeded from
## the field centroid — deterministic and layout-independent. The LOGIC
## footprint polygon is never touched. Returns {parcels: [{p, t, f}],
## barn: quad, silo_c: Vector2, silo_r: float} — the ink outbuildings are
## SNAPPED inside one parcel (flush to a path edge, never overflowing).
func _bake_farm_parcels(verts: PackedVector2Array) -> Dictionary:
	var out: Array = []
	if verts.size() < 3:
		return {"parcels": out}
	var axis := _poly_long_axis(verts)
	var ctr: Vector2 = axis[0]
	var ang := float(axis[1])
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	var seed_base := "fparcel|%d|%d" % [roundi(ctr.x), roundi(ctr.y)]
	var dmin := 1.0e9
	var dmax := -1.0e9
	var nmin := 1.0e9
	var nmax := -1.0e9
	for v in verts:
		var r := v - ctr
		dmin = minf(dmin, r.dot(d))
		dmax = maxf(dmax, r.dot(d))
		nmin = minf(nmin, r.dot(n))
		nmax = maxf(nmax, r.dot(n))
	var ccw := verts.duplicate()
	if Geometry2D.is_polygon_clockwise(ccw):
		ccw.reverse()
	var pi_ct := 0
	var n0 := nmin
	var row := 0
	while n0 < nmax:
		var w := lerpf(PARCEL_STRIP_MIN, PARCEL_STRIP_MAX, float(RoadHash.pick("%s|r%d" % [seed_base, row], 100)) / 100.0)
		var n1 := minf(n0 + w, nmax)
		var d0 := dmin
		var col := 0
		while d0 < dmax:
			var cl := lerpf(PARCEL_CUT_MIN, PARCEL_CUT_MAX, float(RoadHash.pick("%s|r%d|c%d" % [seed_base, row, col], 100)) / 100.0)
			var d1 := minf(d0 + cl, dmax)
			var s0 := tan(deg_to_rad((float(RoadHash.pick("%s|r%d|s%d" % [seed_base, row, col], 100)) / 100.0 * 2.0 - 1.0) * PARCEL_SHEAR_DEG))
			var s1 := tan(deg_to_rad((float(RoadHash.pick("%s|r%d|s%d" % [seed_base, row, col + 1], 100)) / 100.0 * 2.0 - 1.0) * PARCEL_SHEAR_DEG))
			var quad := PackedVector2Array([
				ctr + d * d0 + n * n0,
				ctr + d * d1 + n * n0,
				ctr + d * (d1 + s1 * (n1 - n0)) + n * n1,
				ctr + d * (d0 + s0 * (n1 - n0)) + n * n1,
			])
			for piece in Geometry2D.intersect_polygons(quad, ccw):
				if piece.size() < 3 or absf(_poly_area(piece)) < PARCEL_MIN_AREA:
					continue
				var pcw: PackedVector2Array = piece.duplicate()
				if Geometry2D.is_polygon_clockwise(pcw):
					pcw.reverse()
				for inset in Geometry2D.offset_polygon(pcw, -PARCEL_INSET):
					if inset.size() < 3:
						continue
					# ~60% furrowed along the parcel's own axis, ~10% ploughed
					# perpendicular for rhythm, the rest plain.
					var fseg: Array = []
					var roll := RoadHash.pick("%s|f%d" % [seed_base, pi_ct], 10)
					if roll < 6:
						fseg = _bake_farm_furrows(inset, 0.0)
					elif roll < 7:
						fseg = _bake_farm_furrows(inset, PI * 0.5)
					out.append({"p": inset, "t": RoadHash.pick("%s|t%d" % [seed_base, pi_ct], 4), "f": fseg})
					pi_ct += 1
			d0 = d1
			col += 1
		n0 = n1
		row += 1
	var result := {"parcels": out, "silo_r": FARM_SILO_R * FARM_OUTBUILDING_SCALE}
	result.merge(_snap_farm_outbuildings(out))
	return result

## Find a parcel that fits the barn flush against one of its (path-facing)
## edges, and the silo beside the barn along the same edge — both fully
## inside the parcel so nothing overflows onto the little roads. Largest
## parcels and longest edges first; {} when no parcel can host them.
func _snap_farm_outbuildings(parcels: Array) -> Dictionary:
	var bw := FARM_BARN.x * FARM_OUTBUILDING_SCALE
	var bh := FARM_BARN.y * FARM_OUTBUILDING_SCALE
	var sr := FARM_SILO_R * FARM_OUTBUILDING_SCALE
	var by_area: Array = []
	for i in parcels.size():
		by_area.append([absf(_poly_area(parcels[i].p)), i])
	by_area.sort_custom(func(x, y) -> bool: return float(x[0]) > float(y[0]))
	for entry in by_area.slice(0, 6):
		var poly: PackedVector2Array = parcels[int(entry[1])].p
		var edges: Array = []
		for i in poly.size():
			var ea: Vector2 = poly[i]
			var eb: Vector2 = poly[(i + 1) % poly.size()]
			edges.append([ea.distance_to(eb), ea, eb])
		edges.sort_custom(func(x, y) -> bool: return float(x[0]) > float(y[0]))
		for e in edges.slice(0, 4):
			if float(e[0]) < bw + 6.0:
				continue
			var ea2: Vector2 = e[1]
			var eb2: Vector2 = e[2]
			var dir := (eb2 - ea2).normalized()
			var mid := (ea2 + eb2) * 0.5
			for side in [1.0, -1.0]:
				var n := Vector2(-dir.y, dir.x) * float(side)
				var bc := mid + n * (bh * 0.5 + 2.0)
				var barn := PackedVector2Array([
					bc - dir * (bw * 0.5) - n * (bh * 0.5),
					bc + dir * (bw * 0.5) - n * (bh * 0.5),
					bc + dir * (bw * 0.5) + n * (bh * 0.5),
					bc - dir * (bw * 0.5) + n * (bh * 0.5),
				])
				var ok := true
				for corner in barn:
					if not Geometry2D.is_point_in_polygon(corner, poly):
						ok = false
						break
				if not ok:
					continue
				for sdir in [1.0, -1.0]:
					var sc2 := bc + dir * float(sdir) * (bw * 0.5 + sr + 3.0)
					var fits := true
					for probe in [sc2, sc2 + Vector2(sr + 1.0, 0.0), sc2 - Vector2(sr + 1.0, 0.0), sc2 + Vector2(0.0, sr + 1.0), sc2 - Vector2(0.0, sr + 1.0)]:
						if not Geometry2D.is_point_in_polygon(probe, poly):
							fits = false
							break
					if fits:
						return {"barn": barn, "silo_c": sc2}
				return {"barn": barn}
	return {}

## Lower is better: hug the nearest same-type building (terraced rows of a kind); if none
## of this type is placed yet, prefer a frontage slot nearer the tile centre.
func _row_score(center: Vector2, cat: String, placed_here: Array) -> float:
	var nearest := 1.0e9
	for e in placed_here:
		if e.cat == cat:
			nearest = minf(nearest, center.distance_to(e.pos))
	return center.length() if nearest >= 1.0e9 else nearest

## Distance to the nearest already-placed building on the tile (0 when alone).
func _nearest_building_dist(rel: Vector2, placed_here: Array) -> float:
	var nearest := 1.0e9
	for e in placed_here:
		nearest = minf(nearest, rel.distance_to(e.pos))
	return 0.0 if nearest >= 1.0e9 else nearest

## The nearest placed building to the tile centre (the row/cluster seed for fallback A).
func _nearest_placed(placed_here: Array) -> Dictionary:
	var best := {}
	var best_d := 1.0e9
	for e in placed_here:
		var d: float = e.pos.length()
		if d < best_d:
			best_d = d
			best = e
	return best

func _placed_on_tile(tile_id: String) -> Array:
	var out: Array = []
	for p in _placements:
		if p.tile_id == tile_id:
			out.append({"pos": p.center_rel, "cat": p.cat, "half": p.half})
	return out

## Turn a tile-local centre + local verts into a world placement record.
func _finalize(coord: Vector2i, center_rel: Vector2, local_verts: PackedVector2Array, half: Vector2) -> Dictionary:
	var world_center := _tile_center_world_pos(coord) + center_rel
	var verts := PackedVector2Array()
	for v in local_verts:
		verts.append(world_center + v)
	return {"verts": verts, "center_rel": center_rel, "half": half}

## Rotate local verts by `ang` (radians), keeping them centred on the origin.
func _rotate(verts: PackedVector2Array, ang: float) -> PackedVector2Array:
	var c := cos(ang)
	var s := sin(ang)
	var out := PackedVector2Array()
	for v in verts:
		out.append(Vector2(v.x * c - v.y * s, v.x * s + v.y * c))
	return out

## Half-extent of an axis-aligned bbox enclosing `verts` (which are centred on origin).
func _aabb_half(verts: PackedVector2Array) -> Vector2:
	var mx := 0.0
	var my := 0.0
	for v in verts:
		mx = maxf(mx, absf(v.x))
		my = maxf(my, absf(v.y))
	return Vector2(mx, my)

## AABB-overlap (grown by DESIGN_GAP) of a candidate footprint against everything placed.
func _overlaps(center: Vector2, half: Vector2, placed_here: Array) -> bool:
	var lo := center - half - Vector2(DESIGN_GAP, DESIGN_GAP)
	var hi := center + half + Vector2(DESIGN_GAP, DESIGN_GAP)
	for e in placed_here:
		if hi.x <= e.pos.x - e.half.x or lo.x >= e.pos.x + e.half.x:
			continue
		if hi.y <= e.pos.y - e.half.y or lo.y >= e.pos.y + e.half.y:
			continue
		return true
	return false

## A candidate footprint is valid iff it sits on buildable land, doesn't overlap a placed
## building (with DESIGN_GAP), and no edge of it comes within clearance of any road or river.
func _valid(center: Vector2, local_verts: PackedVector2Array, half: Vector2, placed_here: Array, land: PackedByteArray, segs: Array, rivers: Array, road_clear: float = ROAD_CLEAR) -> bool:
	return _footprint_on_land(center, local_verts, land) \
		and not _overlaps(center, half, placed_here) \
		and _footprint_clears(center, local_verts, segs, road_clear) \
		and _footprint_clears(center, local_verts, rivers, RIVER_CLEAR)

## PRECISE wing validation (owner 2026-07-10: the buildable mask is 20u-cell
## chunky and reserves the 28u river bank corridor — a cosmetic wing only
## needs the real clearances). Checks hex, water, elevation and forest discs
## point-wise, exact 18u road / 16u river distances, and building overlaps.
func _wing_valid(wctr: Vector2, local_verts: PackedVector2Array, half: Vector2, others: Array, segs: Array, rivers: Array, discs: Array, center: Vector2) -> bool:
	if _overlaps(wctr, half, others):
		return false
	var nav := NavGrid.instance()
	var nav_ok := nav != null and nav.is_ready()
	var probes := PackedVector2Array([wctr])
	for v in local_verts:
		probes.append(wctr + v)
	for pr in probes:
		if not _in_hex_rel(pr):
			return false
		if nav_ok:
			var c := nav.cell_of(center + pr)
			if nav.water(c.x, c.y) != 0:
				return false
			if nav.level(c.x, c.y) < MIN_BUILD_LEVEL:
				return false
		for d in discs:
			if pr.distance_to(d.c) < float(d.r):
				return false
	return _footprint_clears(wctr, local_verts, segs, ROAD_CLEAR) \
		and _footprint_clears(wctr, local_verts, rivers, RIVER_CLEAR)

## Relaxed validation for a big CHUNK (it fills its cell): only the CENTRE must be buildable land (the chunk
## may overlap a forest edge or the road-clearance band — the building just draws over it), but it must stay
## IN-HEX (no corner outside the tile) and keep BLOCK_ROAD_PAD / RIVER_CLEAR off road + river centrelines.
func _chunk_valid(center: Vector2, local_verts: PackedVector2Array, land: PackedByteArray, segs: Array, rivers: Array) -> bool:
	if not _land_at(center, land):
		return false
	for v in local_verts:
		var p: Vector2 = center + v
		if absf(p.x) > 270.0 or absf(p.y) > 240.0 or 240.0 * absf(p.x) + 135.0 * absf(p.y) > 64800.0:
			return false   # a corner off-hex would draw outside the tile
	return _footprint_clears(center, local_verts, segs, BLOCK_ROAD_PAD) and _footprint_clears(center, local_verts, rivers, RIVER_CLEAR)

## True if the WHOLE footprint polygon keeps `clearance` clear of every obstacle segment —
## every footprint edge is at least `clearance` from every segment. Catches a footprint whose
## far edge would angle across a curved road/river even though its anchor edge is snapped clear.
func _footprint_clears(center: Vector2, local_verts: PackedVector2Array, segs: Array, clearance: float) -> bool:
	if segs.is_empty():
		return true
	# AABB prefilter: obstacle polylines are finely sampled (~12u segments, hundreds
	# per roaded tile since roads-v3), so skip every segment whose bbox misses the
	# footprint's clearance-grown bbox before paying for exact seg-seg distances.
	var n := local_verts.size()
	var world := PackedVector2Array()
	world.resize(n)
	var lo := Vector2(1.0e9, 1.0e9)
	var hi := Vector2(-1.0e9, -1.0e9)
	for i in n:
		var w := center + local_verts[i]
		world[i] = w
		lo = lo.min(w)
		hi = hi.max(w)
	lo -= Vector2(clearance, clearance)
	hi += Vector2(clearance, clearance)
	for s in segs:
		var sa: Vector2 = s[0]
		var sb: Vector2 = s[1]
		if maxf(sa.x, sb.x) < lo.x or minf(sa.x, sb.x) > hi.x \
			or maxf(sa.y, sb.y) < lo.y or minf(sa.y, sb.y) > hi.y:
			continue
		# A finely sampled road can have a complete short segment INSIDE a large
		# footprint. Edge-to-edge distance alone misses that case (there is no
		# crossing edge), which left start buildings visually under a road. Reject
		# an interior endpoint before checking ordinary crossings / near misses.
		if Geometry2D.is_point_in_polygon(sa, world) or Geometry2D.is_point_in_polygon(sb, world):
			return false
		for i2 in n:
			if _seg_seg_dist(world[i2], world[(i2 + 1) % n], sa, sb) < clearance:
				return false
	return true

## Minimum distance between segments p1p2 and p3p4 (0 if they cross).
func _seg_hits_any(a: Vector2, b: Vector2, segs: Array) -> bool:
	for s in segs:
		if _segs_cross(a, b, s[0], s[1]):
			return true
	return false

func _seg_seg_dist(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> float:
	if _segs_cross(p1, p2, p3, p4):
		return 0.0
	return minf(
		minf(_pt_seg_dist(p1, p3, p4), _pt_seg_dist(p2, p3, p4)),
		minf(_pt_seg_dist(p3, p1, p2), _pt_seg_dist(p4, p1, p2)))

## Proper-intersection test for segments ab and cd (collinear-overlap ignored — fine here).
func _segs_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var d1 := _cross(c, d, a)
	var d2 := _cross(c, d, b)
	var d3 := _cross(a, b, c)
	var d4 := _cross(a, b, d)
	return ((d1 > 0.0) != (d2 > 0.0)) and ((d3 > 0.0) != (d4 > 0.0))

func _cross(o: Vector2, p: Vector2, q: Vector2) -> float:
	return (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x)

## Buildable test: the footprint centre and all its verts fall on buildable land cells.
## (Approximate — samples outline + centre; adequate for the blocky footprints we use.)
func _footprint_on_land(center: Vector2, local_verts: PackedVector2Array, land: PackedByteArray) -> bool:
	if not _land_at(center, land):
		return false
	for v in local_verts:
		if not _land_at(center + v, land):
			return false
	return true

## Is the tile-local point (relative to TILE_CENTER) a buildable land cell?
func _land_at(rel: Vector2, land: PackedByteArray) -> bool:
	var local := rel + TILE_CENTER
	var col := int(local.x / CELL)
	var row := int(local.y / CELL)
	if col < 0 or col >= GRID_COLS or row < 0 or row >= GRID_ROWS:
		return false
	return land[row * GRID_COLS + col] == 1

## World-space road polylines on the tile (built infrastructure only), as segment pairs
## relative to the tile centre and clipped to roughly the hex + ROAD_REACH.
func _tile_road_segments(coord: Vector2i, center: Vector2) -> Array:
	var out: Array = []
	if terrain_layer == null:
		return out
	var td: Dictionary = terrain_layer.tiles.get(coord, {})
	if not (td.get("infrastructure_present", []) as Array).has("roads"):
		return out
	var net := RoadNetwork.instance()
	if net == null:
		return out
	var limx := 270.0 + ROAD_REACH
	var limy := 240.0 + ROAD_REACH
	for edge_id in net.edges_on_tile(coord):
		var edge: Dictionary = net.edges.get(edge_id, {})
		if str(edge.get("state", "")) != RoadNetwork.STATE_BUILT:
			continue
		var geo: PackedVector2Array = edge.get("geometry", PackedVector2Array())
		for i in range(geo.size() - 1):
			var a := geo[i] - center
			var b := geo[i + 1] - center
			if (absf(a.x) > limx and absf(b.x) > limx) or (absf(a.y) > limy and absf(b.y) > limy):
				continue
			out.append([a, b])
	return out

## Forest canopy discs on the tile, centre relative to the tile centre. Delegated to
## ForestVisuals so the avoided disc matches the drawn blob exactly.
func _forest_discs(coord: Vector2i, center: Vector2) -> Array:
	var out: Array = []
	if _forest_visuals == null or not _forest_visuals.has_method("discs_on_tile"):
		return out
	for d in _forest_visuals.discs_on_tile(coord):
		out.append({"c": (d.center as Vector2) - center, "r": float(d.radius)})
	return out

## Bridge-approach corridors (centre-relative segment pairs): from each PREDETERMINED river
## crossing, a stub straight out along the bridge axis on each bank, reserved so the road has
## clean space to reach the crossing instead of being forced over riverside buildings. Empty
## when the tile has no crossing (or crossings aren't built yet).
func _bridge_approach_segments(tile_id: String, center: Vector2) -> Array:
	var out: Array = []
	if not RoadCrossings.is_built():
		return out
	for cx in RoadCrossings.for_tile(tile_id):
		var p: Vector2 = (cx.point as Vector2) - center
		var t: Vector2 = (cx.bridge_tangent as Vector2).normalized()
		if t == Vector2.ZERO:
			continue
		out.append([p, p + t * BRIDGE_APPROACH])
		out.append([p, p - t * BRIDGE_APPROACH])
	return out

## River-arm polylines on the tile as segment pairs, relative to the tile centre. Empty
## when the tile has no river. Buildings keep RIVER_CLEAR off these (mask + clears check).
func _tile_river_segments(coord: Vector2i, center: Vector2) -> Array:
	var out: Array = []
	if terrain_layer == null or not terrain_layer.tiles.has(coord):
		return out
	var td: Dictionary = terrain_layer.tiles[coord]
	for arm in RiverGeometry.arms(td, terrain_layer.river_properties, center):
		var geo: PackedVector2Array = arm
		for i in range(geo.size() - 1):
			out.append([geo[i] - center, geo[i + 1] - center])
	return out

## Source-lake ellipse on the tile (rel to centre), or {} when none.
func _tile_lake(coord: Vector2i, center: Vector2) -> Dictionary:
	if terrain_layer == null or not terrain_layer.tiles.has(coord):
		return {}
	var e: Dictionary = RiverGeometry.lake_ellipse(terrain_layer.tiles[coord], terrain_layer.river_properties, center)
	if e.is_empty():
		return {}
	return {"c": (e.center as Vector2) - center, "rx": float(e.rx), "ry": float(e.ry)}

func _pt_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	var t := 0.0
	if denom > 0.0001:
		t = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _verts_bb(verts: PackedVector2Array) -> Rect2:
	var lo := verts[0]
	var hi := verts[0]
	for v in verts:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	return Rect2(lo, hi - lo)

## Cull to the viewport when zoomed in, else draw all once and stay static.
func _process(_delta: float) -> void:
	if _placements.is_empty():
		return
	var view := _visible_world_rect()
	if view.size.x <= 0.0:
		return
	var visible := 0
	for p in _placements:
		if view.intersects(p.bb):
			visible += 1
	var want_cull := visible <= CULL_CAP
	if want_cull != _cull:
		_cull = want_cull
		_view = view
		queue_redraw()
	elif _cull and view != _view:
		_view = view
		queue_redraw()

func _visible_world_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2()
	var size := vp.get_visible_rect().size
	if size.x <= 0.0:
		return Rect2()
	return (vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, size)).grow(CULL_MARGIN)

func _clear_tile_caches() -> void:
	_tile_land.clear()
	_tile_landkeys.clear()
	_farm_land.clear()
	_farm_landkeys.clear()
	_tile_segs.clear()
	_tile_rivers.clear()
	_tile_block_mode.clear()
	_tile_block_templates.clear()
	_farm_render.clear()   # neighbour-dependent farm render + lanes are rebuilt per tile after a relayout
	_farm_lanes.clear()
	_farm_bridges.clear()
	_farm_promote.clear()
	_farm_cluster_rings.clear()

## World-space AABB (one Rect2 per footprint) of the buildings on a tile. Uses the raw vert
## bbox (NOT the NPC-outline-grown bb) so consumers stay tight to the footprint.
func footprint_rects_on_tile(coord: Vector2i) -> Array:
	var out: Array = []
	for p in _placements:
		if p.coord == coord:
			out.append(_verts_bb(p.verts))
	return out

# Block-box size band (road frame: U = along the road, V = perpendicular) — sizes the
# chunk template's coarse cells (_chunk_template). Named for the retired enclosure ring
# that first used them; the chunk grid still fills the same city-block box.
const ENCL_MIN_U := 150.0          # smallest block along the road
const ENCL_MAX_U := 240.0          # largest block along the road
const ENCL_MAX_V := 180.0          # largest block depth (perpendicular)

## Which bank of the river point `p` sits on: sign of the cross product against the NEAREST river
## segment (+1 / -1), or 0 when there is no river. `p` and `rivers` are both rel-to-tile-centre.
func _river_side(p: Vector2, rivers: Array) -> int:
	var best := 1.0e18
	var side := 0
	for seg in rivers:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var d := _pt_seg_dist(p, a, b)
		if d < best - 0.001:   # strictly nearer (deterministic: the earlier segment wins a near-tie at a bend)
			best = d
			var cr := (b - a).cross(p - a)
			side = 1 if cr > 0.0 else (-1 if cr < 0.0 else 0)
	return side

## Budge an enclosure quad off a river it overlaps: clip it to the half-plane on the anchor's bank,
## the cut line set RIVER_ROAD_PAD off the river (so the ring runs along the bank, not in the water).
## No-op when there is no river, the block is off the river, or the bank is ambiguous. Rel-to-centre.
func _clip_to_river_bank(quad: Array, rivers: Array, anchor: Vector2, aside: int) -> Array:
	if rivers.is_empty() or aside == 0 or quad.size() < 3:
		return quad
	var qc := Vector2.ZERO
	for p in quad:
		qc += p as Vector2
	qc /= float(quad.size())
	var best := 1.0e18
	var ba := Vector2.ZERO
	var bb := Vector2.ZERO
	for seg in rivers:
		var d := _pt_seg_dist(qc, seg[0], seg[1])
		if d < best:
			best = d
			ba = seg[0]
			bb = seg[1]
	# Only clip when the river actually reaches the block (within the box's own reach from its centre).
	var reach := 0.0
	for p in quad:
		reach = maxf(reach, qc.distance_to(p as Vector2))
	if best > reach or (bb - ba).length_squared() < 1.0:
		return quad
	var base := Geometry2D.get_closest_point_to_segment(qc, ba, bb)
	var nrm := Vector2(-(bb - ba).y, (bb - ba).x).normalized()
	if nrm.dot(anchor - base) < 0.0:
		nrm = -nrm   # point toward the anchor's bank (the side we keep)
	# Cut along the bank line (RIVER_ROAD_PAD off the river); keep the anchor's (+nrm) side. Reuse the
	# bisector clip: two mirror points across the line so its perpendicular bisector IS the bank line.
	var lp := base + nrm * RIVER_ROAD_PAD
	var packed := PackedVector2Array()
	for p in quad:
		packed.append(p as Vector2)
	var out: Array = []
	for p in _clip_poly_halfplane(packed, lp + nrm, lp - nrm):
		out.append(p)
	return out

## World-space avoidance discs (one bounding circle per footprint) for the road
## realizer, so roads built after buildings route around them instead of over them.
func footprint_discs() -> Array:
	var out: Array = []
	for p in _placements:
		var center: Vector2 = _tile_center_world_pos(p.coord) + p.center_rel
		out.append({"center": center, "radius": (p.half as Vector2).length()})
	return out

func clear_all() -> void:
	# A loaded save rebuilds visuals (world_map._rebuild_after_load).
	_placements.clear()
	_placement_index.clear()
	_clear_tile_caches()
	_subcomponents.clear()
	_subcomp_dirty.clear()
	_block_masses.clear()
	_massed_by_tile.clear()
	_farm_render.clear()
	_farm_lanes.clear()
	_farm_bridges.clear()
	_farm_promote.clear()
	_farm_cluster_rings.clear()
	footprint_version += 1
	queue_redraw()

func remove_instance(instance_id: String) -> void:
	# A cancelled/demolished building frees its footprint (occupancy is implicit in
	# _placements, so dropping the record is enough).
	if not _placement_index.has(instance_id):
		return
	var idx: int = _placement_index[instance_id]
	var tile_id := str(_placements[idx].tile_id)
	_placements.remove_at(idx)
	_placement_index.erase(instance_id)
	_farm_render.erase(instance_id)   # a demolished farm's cached render shape
	for iid in _placement_index:
		if _placement_index[iid] > idx:
			_placement_index[iid] -= 1
	footprint_version += 1
	# On a block tile, re-pack so the freed lot opens and the survivors keep deterministic
	# lots (matches the post-reload re-derivation; otherwise the cached slot grid leaks).
	if _tile_block_templates.has(tile_id):
		relayout_tile(tile_id)
	else:
		_mark_subcomp_dirty(tile_id)
		queue_redraw()

func _draw() -> void:
	# Annexes + wings draw UNDER buildings so a same-colour extension merges seamlessly.
	for sc in _subcomponents:
		var uk := str(sc.kind)
		if uk == "annex" or uk == "wing" or uk == "corridor":
			_draw_subcomponent(sc)
	# Courtyard block-masses draw under their members: one welded mass + inner
	# yard; the members then contribute ink outlines only (party-wall slices).
	var shadow := MapStyle.building_shadow_color()
	var shadow_off := MapStyle.building_shadow_offset()
	for tid_m in _block_masses:
		for m in (_block_masses[tid_m] as Array):
			if _cull and not _view.intersects(m.bb):
				continue
			var mw := _wobble_poly(str(m.key), m.poly)
			if shadow.a > 0.0:
				draw_colored_polygon(_offset_pts(mw, shadow_off), shadow)
			draw_colored_polygon(mw, m.color)
			var ml := mw.duplicate()
			ml.append(mw[0])
			draw_polyline(ml, INK, INK_W, true)
			for h in (m.holes as Array):
				var hw := _wobble_poly(str(m.key) + "|yard", h)
				draw_colored_polygon(hw, COURTYARD_FILL)
				var hl := hw.duplicate()
				hl.append(hw[0])
				draw_polyline(hl, INK, 1.0, true)
	for placement in _placements:
		if _cull and not _view.intersects(placement.bb):
			continue
		var is_farm: bool = str(placement.cat) == "farm"
		var verts: PackedVector2Array = placement.verts
		var hatch_src: Array = placement.get("hatch", [])
		var parcel_src: Dictionary = placement.get("parcels", {})
		if is_farm:
			# Use the cell-clipped (lane-snapped) shape + its re-baked hatch when the layout pass ran.
			var fid := str(placement.instance_id)
			if _farm_render.has(fid):
				verts = _farm_render[fid].verts
				hatch_src = _farm_render[fid].hatch
				parcel_src = (_farm_render[fid] as Dictionary).get("parcels", {})
		if verts.size() < 3:
			continue
		if is_farm:
			if MapStyle.ink:
				# P3b parcel fabric: the path-tan base shows through the parcel
				# insets as the little farm roads; NO outer outline (the parcel
				# edges carry the boundary — kills the chunky-blob read).
				draw_colored_polygon(verts, MapStyle.farm_path_color())
				for pc in (parcel_src.get("parcels", []) as Array):
					var pp: PackedVector2Array = pc.p
					if pp.size() < 3:
						continue
					draw_colored_polygon(pp, MapStyle.farm_parcel_tint(int(pc.t)))
					var pl := pp.duplicate()
					pl.append(pp[0])
					draw_polyline(pl, MapStyle.farm_parcel_outline(), 0.9, true)
					for seg in (pc.f as Array):
						var fs: PackedVector2Array = seg
						if fs.size() >= 2:
							draw_polyline(fs, MapStyle.farm_hatch(), MapStyle.farm_hatch_width())
				# Parcel-snapped outbuildings (subcomponent barn/silo skip in ink).
				var barn: PackedVector2Array = parcel_src.get("barn", PackedVector2Array())
				if barn.size() == 4:
					draw_colored_polygon(barn, MapStyle.farm_barn_color())
					var bl := barn.duplicate()
					bl.append(barn[0])
					draw_polyline(bl, INK, 1.0, true)
				var silo_c: Vector2 = parcel_src.get("silo_c", Vector2.INF)
				if silo_c.is_finite():
					var sr3 := float(parcel_src.get("silo_r", 8.4))
					draw_circle(silo_c, sr3, MapStyle.farm_silo_color())
					draw_arc(silo_c, sr3, 0.0, TAU, 20, INK, 1.0, true)
					draw_circle(silo_c, 1.2, INK)
			else:
				var fid2 := str(placement.instance_id)
				draw_colored_polygon(verts, MapStyle.farm_field_variant(fid2))
				var loop := verts.duplicate()
				loop.append(verts[0])
				var farm_npc := bool(placement.is_npc)
				draw_polyline(loop, MapStyle.farm_outline_color(farm_npc), MapStyle.farm_outline_width(farm_npc), true)
				for seg in (hatch_src as Array):
					var s: PackedVector2Array = seg
					if s.size() >= 2:
						draw_polyline(s, MapStyle.farm_hatch(), MapStyle.farm_hatch_width())
		else:
			# Ink & wash: wash fill + one sepia ink outline + category-flavoured
			# roof motifs. The DRAWN polygon gets a hand-wobble (ink spec I4);
			# the placement polygon stays clean for occupancy/click logic.
			# Members of a courtyard mass skip their fill — the mass carries it —
			# and their outline thins into a party-wall division.
			var in_mass: bool = (_massed_by_tile.get(str(placement.tile_id), {}) as Dictionary).has(str(placement.instance_id))
			if not in_mass and _draw_ink_art(placement, verts):
				pass   # shape-language art replaces wash/outline/motifs (both styles)
			else:
				var wob := _wobble_poly(str(placement.instance_id), verts)
				if not in_mass:
					if shadow.a > 0.0:
						draw_colored_polygon(_offset_pts(wob, shadow_off), shadow)
					draw_colored_polygon(wob, _wash_for(str(placement.cat), str(placement.instance_id), bool(placement.is_npc)))
				var loop2 := wob.duplicate()
				loop2.append(wob[0])
				draw_polyline(loop2, INK, 1.0 if in_mass else INK_W, true)
				# Quad footprints only — L/C shapes (6/8 verts) keep a clean roof so a
				# motif never spills off the polygon (same guard the old ridges used).
				# Offshore platforms stay plain (a helipad dot instead of shed roofs).
				if bool(placement.get("offshore", false)):
					draw_circle(_poly_centroid(verts), 2.4, INK)
				elif verts.size() == 4:
					_draw_roof_motifs(str(placement.cat), str(placement.instance_id), verts, bool(placement.is_npc))
	# Thin dirt tracks between adjacent farms (kept within FARM_LANE_REACH of the fields, routed around
	# forests). A promoted tile's _farm_lanes already excludes the ring + trunk (now real yellow roads).
	# A filled disc (radius = half the track width) at each segment end JOINS the corners + junctions so
	# the network reads as continuous instead of broken butt-capped segments.
	# Block side roads — only exist once a second-row lot was actually built on.
	for tid_s in _block_streets:
		for s in (_block_streets[tid_s] as Array):
			draw_line(s[0], s[1], MapStyle.road_casing(), 11.0, true)
			draw_line(s[0], s[1], MapStyle.road_local(), 7.0, true)
	# Ink mode draws NO grey lane web (owner ruling 2026-07-23): the mockup's
	# farms are parcel blocks sitting beside the roads, not lane-connected
	# blobs. Classic keeps the dirt tracks + their river bridge decks.
	if not MapStyle.ink:
		var joint_r := FARM_LANE_W * 0.5
		for tid in _farm_lanes:
			for seg in (_farm_lanes[tid] as Array):
				var ls: PackedVector2Array = seg
				if ls.size() >= 2:
					draw_polyline(ls, FARM_LANE_COLOR, FARM_LANE_W)
					for v in ls:
						draw_circle(v, joint_r, FARM_LANE_COLOR)   # fill each corner/junction
		# Bridge decks where a lane crosses a river.
		for tid2 in _farm_bridges:
			for br in (_farm_bridges[tid2] as Array):
				var bp: Vector2 = br.p
				var bd: Vector2 = br.dir
				var bpr := Vector2(-bd.y, bd.x)
				var e0 := bp - bd * (FARM_BRIDGE_LEN * 0.5)
				var e1 := bp + bd * (FARM_BRIDGE_LEN * 0.5)
				draw_line(e0, e1, FARM_BRIDGE_COLOR, FARM_BRIDGE_W)            # deck
				draw_line(e0 - bpr * 5.0, e0 + bpr * 5.0, FARM_BRIDGE_COLOR, 2.0)   # abutment rails
				draw_line(e1 - bpr * 5.0, e1 + bpr * 5.0, FARM_BRIDGE_COLOR, 2.0)
	# Round tanks + farm barns/silos on top (tanks sit off their building; farm outbuildings sit ON the field).
	for sc in _subcomponents:
		var k := str(sc.kind)
		if k == "tank" or k == "tankfarm" or k == "farm_barn" or k == "farm_silo" or k == "storey":
			_draw_subcomponent(sc)

## Draw one ancillary (tank/annex) in the parent's wash + ink; farm outbuildings
## keep their brown barn/silo look (farms are outside the plate restyle).
func _draw_subcomponent(sc: Dictionary) -> void:
	if _cull and not _view.intersects(sc.bb):
		return
	var sv: PackedVector2Array = sc.verts
	var kind := str(sc.kind)
	if MapStyle.ink and (kind == "farm_barn" or kind == "farm_silo"):
		return   # ink farms draw their own parcel-snapped outbuildings (P3b)
	if _ink_art_iid.get(str(sc.get("iid", "")), false):
		return   # the shape-language art carries the whole compound (both styles)
	if kind == "tankfarm":
		var twash := _wash_for(str(sc.get("cat", "default")), str(sc.get("iid", "")), bool(sc.is_npc))
		for tc in (sc.tanks as Array):
			draw_circle(tc as Vector2, float(sc.r), twash)
			draw_arc(tc as Vector2, float(sc.r), 0.0, TAU, 24, INK, INK_W, true)
			draw_circle(tc as Vector2, 1.2, INK)
		return
	if kind == "corridor":
		draw_colored_polygon(sv, _wash_for(str(sc.get("cat", "default")), str(sc.get("iid", "")), bool(sc.is_npc)))
		draw_line(sv[0], sv[1], INK, 1.0)
		draw_line(sv[2], sv[3], INK, 1.0)
		return
	if kind == "annex" or kind == "tank" or kind == "wing" or kind == "storey":
		if kind != "tank" and kind != "storey":
			sv = _wobble_poly("%s|%s" % [str(sc.get("iid", "")), kind], sv)
		var wash := _wash_for(str(sc.get("cat", "default")), str(sc.get("iid", "")), bool(sc.is_npc))
		if kind == "storey":
			wash = Color.from_hsv(wash.h, wash.s, clampf(wash.v * 0.92, 0.0, 1.0))
		draw_colored_polygon(sv, wash)
		var si := sv.duplicate()
		si.append(sv[0])
		draw_polyline(si, INK, 1.0 if kind == "storey" else INK_W, true)
		if kind == "tank":
			draw_circle(_poly_centroid(sv), 1.4, INK)   # reference: tank = ink circle + centre dot
		return
	# Farm barn/silo fall through to here. Ink: brick barn / mustard silo + ink
	# outline; classic keeps the brown + white/grey look.
	var fb_fill: Color = sc.color
	if MapStyle.ink:
		fb_fill = MapStyle.farm_silo_color() if kind == "farm_silo" else MapStyle.farm_barn_color()
	draw_colored_polygon(sv, fb_fill)
	var sl := sv.duplicate()
	sl.append(sv[0])
	if MapStyle.ink:
		draw_polyline(sl, INK, 1.0, true)
	elif bool(sc.is_npc):
		draw_polyline(sl, Color.WHITE, NPC_OUTLINE_W, true)
	else:
		draw_polyline(sl, PLAYER_OUTLINE, PLAYER_OUTLINE_W, true)

# ── Ink & wash helpers (phase I1) ──────────────────────────────────────────────

## Procedural industrial art (ink mode): InkBuildingGen draws the shape-language
## compound centered on the footprint, rotated to its first edge, long side
## scaled to INK_ART_SCALE x the footprint extent. The generator computes facet
## tones from WORLD normals, offsets shadows in world SE and aims highlights
## world NW — so rotation keeps the light source top-left (owner requirement).
## Returns false when no recipe applies — caller falls back to the plate look.
func _draw_ink_art(placement: Dictionary, verts: PackedVector2Array) -> bool:
	var art_key: String = INK_ART_KEY.get(str(placement.get("iname", "")), "")
	if art_key == "" or verts.size() < 3:
		return false
	var lvl := clampi(int((MatchState.get_building(str(placement.instance_id)) as Dictionary).get("level", 1)), 1, 3)
	var dir := (verts[1] - verts[0]).normalized()
	var ctr := _poly_centroid(verts)
	var dmax := 0.0
	var nmax := 0.0
	for v in verts:
		var r := v - ctr
		dmax = maxf(dmax, absf(r.dot(dir)))
		nmax = maxf(nmax, absf(r.dot(Vector2(-dir.y, dir.x))))
	# Drawn size comes from tile_size_used (40u at 1 → 90u at 30/mine), not
	# from whatever the placement path happened to reserve. Capped by the
	# actual footprint so a building shrunk to fit a packed tile draws inside
	# its slot rather than over its neighbours.
	var size_target := _art_size_for(int(placement.get("size_units", 1)), art_key)
	var target := clampf(minf(size_target, maxf(dmax, nmax) * 2.0), ART_DRAWN_MIN, ART_DRAWN_MAX)
	# Colour by the SAME rule as the plate look — category triad, NPC
	# paper-white, seeded jitter — so ownership and category read identically
	# in both styles. _wash_for already encodes ownership, so the generator's
	# own npc dulling is left off.
	var wash := _wash_for(str(placement.cat), str(placement.instance_id), bool(placement.is_npc))
	return InkBuildingGen.draw(self, art_key, lvl, ctr, dir.angle(), target, false, Vector2.INF, wash)

## Replace a shape-language placement's footprint with the sprite's own box
## (+ ART_BLOCK_MARGIN), keeping its centre and road-facing orientation. The
## polygon is what everything downstream treats as solid — overlap tests,
## avoidance discs, the frontage audit — so cropping it here is what lets lots
## pack tightly without the art actually touching.
func _crop_to_sprite(placed: Dictionary, size_units: int, art_key: String) -> void:
	if art_key == "":
		return
	var frame: Vector2 = InkBuildingGen.level_frame(art_key, 3)
	if frame.x <= 0.0 or frame.y <= 0.0:
		return
	var pv: PackedVector2Array = placed.verts
	if pv.size() < 3:
		return
	var ctr := Vector2.ZERO
	for v in pv:
		ctr += v
	ctr /= float(pv.size())
	var dirv := (pv[1] - pv[0]).normalized()
	var mn := Vector2(1e30, 1e30)
	var mx := Vector2(-1e30, -1e30)
	for v in pv:
		mn = mn.min(v)
		mx = mx.max(v)
	var lot_extent := maxf((mx - mn).x, (mx - mn).y)
	var target := clampf(minf(_art_size_for(size_units, art_key), lot_extent), ART_DRAWN_MIN, ART_DRAWN_MAX)
	var s := target / maxf(frame.x, frame.y)
	var hx := frame.x * s * 0.5 + ART_BLOCK_MARGIN
	var hy := frame.y * s * 0.5 + ART_BLOCK_MARGIN
	var local := PackedVector2Array([
		Vector2(-hx, -hy).rotated(dirv.angle()), Vector2(hx, -hy).rotated(dirv.angle()),
		Vector2(hx, hy).rotated(dirv.angle()), Vector2(-hx, hy).rotated(dirv.angle()),
	])
	var world := PackedVector2Array()
	for v in local:
		world.append(ctr + v)
	placed.verts = world
	placed.half = _aabb_half(local)

## The LOT for a shape-language building: its sprite's own box plus
## ART_BLOCK_MARGIN, long side first so _place_frontage (which rotates local x
## onto the road tangent) presents the long face to the street and snaps using
## the sprite's shallow depth. Feeding this into the search — rather than a fat
## square lot that gets cropped afterwards — is what actually pulls buildings
## up to the road.
func _sprite_lot_verts(size_units: int, art_key: String, shrink: float = 1.0) -> PackedVector2Array:
	if art_key == "":
		return PackedVector2Array()
	var frame: Vector2 = InkBuildingGen.level_frame(art_key, 3)
	if frame.x <= 0.0 or frame.y <= 0.0:
		return PackedVector2Array()
	var target := clampf(_art_size_for(size_units, art_key) * shrink, ART_DRAWN_MIN * 0.5, ART_DRAWN_MAX)
	var s := target / maxf(frame.x, frame.y)
	var long_side := maxf(frame.x, frame.y) * s + ART_BLOCK_MARGIN * 2.0
	var short_side := minf(frame.x, frame.y) * s + ART_BLOCK_MARGIN * 2.0
	return BuildingShapes.make_rect(long_side, short_side).verts

## Drawn/lot side for a building of `size_units`, interpolating the drawn-size
## band across the CSV's real 1..30 range.
func _art_size_for(size_units: int, art_key: String = "") -> float:
	if ART_SIZE_OVERRIDE.has(art_key):
		return float(ART_SIZE_OVERRIDE[art_key])
	var t := clampf((float(size_units) - 1.0) / (ART_SIZE_UNITS_MAX - 1.0), 0.0, 1.0)
	return lerpf(ART_DRAWN_MIN, ART_DRAWN_MAX, t)

## Shift a polygon by a fixed offset (SE micro-shadow under building fills).
func _offset_pts(pts: PackedVector2Array, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = pts[i] + off
	return out

## Hand-drawn wobble (ink spec I4), DRAW time only: subdivide each edge every
## ~WOBBLE_STEP and jitter the interior points perpendicular ±WOBBLE_AMP, seeded
## per instance. Corners stay EXACT so adjacent shapes keep their gaps and the
## logic polygon (occupancy, clicks, tests) is never touched.
func _wobble_poly(seed_key: String, verts: PackedVector2Array) -> PackedVector2Array:
	var n := verts.size()
	if n < 3:
		return verts
	var perim := 0.0
	for i in n:
		perim += verts[i].distance_to(verts[(i + 1) % n])
	if perim < WOBBLE_MIN_PERIM:
		return verts
	var out := PackedVector2Array()
	for i in n:
		var a := verts[i]
		var b := verts[(i + 1) % n]
		out.append(a)
		var steps := int(a.distance_to(b) / WOBBLE_STEP)
		if steps < 2:
			continue
		var dv := (b - a) / float(steps)
		var nrm := Vector2(-dv.y, dv.x).normalized()
		for s in range(1, steps):
			var off := (float(RoadHash.pick("wob|%s|%d|%d" % [seed_key, i, s], 100)) / 100.0 - 0.5) * 2.0 * WOBBLE_AMP
			out.append(a + dv * float(s) + nrm * off)
	return out

## Wash family for a building category. The pre-ink scheme's colour families
## survive in muted plate shades (owner 2026-07-10): furnaces keep their blue,
## refineries their purple-turned-pink, manufacturing its orange.
func _wash_family(cat: String) -> String:
	match cat:
		"extraction":
			return "grey"
		"power":
			return "yellow"
		"electrochemistry":
			return "lime"
		"metallurgy":
			return "navy"
		"water":
			return "blue"
		"refinery":
			return "pink"
		"manufacturing":
			return "orange"
		"infrastructure":
			return "mustard"
		"ruins":
			return "ruins"
		_:
			return "red"

## Wash fill: PLAYER buildings carry the muted triad (+seeded ±5% value jitter
## so repeated blocks don't clone); NPC buildings are PAPER WHITE with ink
## outlines (owner ruling 2026-07-10) — ownership reads instantly, like the
## uncoloured lots on a vintage plate. Ruins keep their brown either way
## (decay, not ownership).
func _wash_for(cat: String, iid: String, is_npc: bool) -> Color:
	var fam := _wash_family(cat)
	var jitter := (float(RoadHash.pick("ink|%s|val" % iid, 100)) / 100.0 - 0.5) * 2.0 * WASH_JITTER
	if is_npc and fam != "ruins":
		var wv := NPC_WHITE.v * (1.0 + jitter * 0.6)
		return Color.from_hsv(NPC_WHITE.h, NPC_WHITE.s, clampf(wv, 0.0, 1.0))
	var base: Color
	match fam:
		"grey":    base = WASH_GREY
		"yellow":  base = WASH_YELLOW
		"lime":    base = WASH_LIME
		"navy":    base = WASH_NAVY
		"blue":    base = WASH_BLUE
		"pink":    base = WASH_PINK
		"orange":  base = WASH_ORANGE
		"mustard": base = WASH_MUSTARD
		"ruins":   base = WASH_RUINS
		_:         base = WASH_RED
	var s := base.s * (0.78 if is_npc else 1.06)
	var v := base.v * (1.0 + jitter) * (0.96 if is_npc else 1.0)
	return Color.from_hsv(base.h, clampf(s, 0.0, 1.0), clampf(v, 0.0, 1.0))

## Interior ink linework on a quad roof, derived from the footprint's own edges so
## it stays on the roof at any rotation. Grey industry gets shed saw-tooth lines +
## a chimney dot; red urban blocks get terrace party-walls + a ridge; mustard
## logistics keeps longitudinal ridge lines.
func _draw_roof_motifs(cat: String, iid: String, verts: PackedVector2Array, is_npc: bool) -> void:
	var ax: Vector2 = verts[1] - verts[0]
	var bx: Vector2 = verts[3] - verts[0]
	var lng: Vector2 = ax if ax.length() >= bx.length() else bx
	var shr: Vector2 = bx if lng == ax else ax
	match _wash_family(cat):
		"grey", "navy", "orange", "yellow":
			var n := clampi(int(lng.length() / SAWTOOTH_PITCH), 1, 12)
			for k in range(1, n):
				var base: Vector2 = verts[0] + lng * (float(k) / float(n))
				draw_line(base + shr * 0.12, base + shr * 0.88, INK, 1.0)
			var ci := RoadHash.pick("ink|%s|chimney" % iid, 4)
			var corner: Vector2 = verts[ci]
			var inward := (_poly_centroid(verts) - corner).normalized()
			draw_circle(corner + inward * 5.0, CHIMNEY_R, INK)
			# Rooftop vent/clerestory (ink spec I4): 1-2 small ink rects along the
			# ridge on halls long enough to carry them.
			if lng.length() >= 30.0:
				var vents := 1 + RoadHash.pick("ink|%s|vents" % iid, 2)
				var lu := lng.normalized()
				var su := shr.normalized()
				for vi in vents:
					var t := 0.25 + 0.5 * float(RoadHash.pick("ink|%s|vent|%d" % [iid, vi], 100)) / 100.0
					var vc: Vector2 = verts[0] + lng * t + shr * (0.32 + 0.36 * float(vi))
					var vh := lu * (VENT_SIZE.x * 0.5)
					var vv := su * (VENT_SIZE.y * 0.5)
					var vr := PackedVector2Array([vc - vh - vv, vc + vh - vv, vc + vh + vv, vc - vh + vv, vc - vh - vv])
					draw_polyline(vr, INK, 1.0, true)
		"red":
			var n2 := clampi(int(lng.length() / TERRACE_PITCH), 1, 10)
			# Per-strip value shading first (ink spec I2): alternate terraces get a
			# faint seeded light/dark overlay so the row reads as separate houses.
			for s2 in range(n2):
				var t0 := float(s2) / float(n2)
				var t1 := float(s2 + 1) / float(n2)
				var shade := (float(RoadHash.pick("ink|%s|strip|%d" % [iid, s2], 100)) / 100.0 - 0.5) * 2.0 * TERRACE_SHADE
				if absf(shade) < 0.012:
					continue
				var quad := PackedVector2Array([
					verts[0] + lng * t0, verts[0] + lng * t1,
					verts[0] + lng * t1 + shr, verts[0] + lng * t0 + shr,
				])
				var overlay := Color(1, 1, 1, shade) if shade > 0.0 else Color(0, 0, 0, -shade)
				draw_colored_polygon(quad, overlay)
			for k2 in range(1, n2):
				var base2: Vector2 = verts[0] + lng * (float(k2) / float(n2))
				draw_line(base2 + shr * 0.08, base2 + shr * 0.92, INK, 1.0)
			var mid: Vector2 = verts[0] + shr * 0.5
			draw_line(mid + lng * 0.06, mid + lng * 0.94, INK, 1.0)
			# Player rows carry seeded chimney dots on the ridge (ownership cue
			# beyond saturation, spec open-decision 3 leaning roof-marker).
			if not is_npc and lng.length() >= 24.0:
				for c2 in range(1, n2):
					if RoadHash.pick("ink|%s|rchim|%d" % [iid, c2], 3) == 0:
						draw_circle(verts[0] + lng * ((float(c2) - 0.5) / float(n2)) + shr * 0.5, 1.1, INK)
		"ruins":
			pass   # ruins stay quiet — a broken outline reads better than fresh roof lines
		_:
			var n3 := clampi(int(shr.length() / 14.0), 1, 4)
			for k3 in range(1, n3 + 1):
				var b3: Vector2 = verts[0] + shr * (float(k3) / float(n3 + 1))
				draw_line(b3 + lng * 0.14, b3 + lng * 0.86, INK, 1.0)

func _tile_center_world_pos(coord: Vector2i) -> Vector2:
	if terrain_layer != null:
		return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))
	return Vector2.ZERO
