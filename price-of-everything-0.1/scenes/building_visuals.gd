extends Node2D

# Polygon building footprints (polygon-buildings plan, phases 1-3). Each
# non-forest, non-road building is a coloured SHAPE (square/rect/L×2/squared-C),
# its AREA = (tile_size_used / build_capacity) × the tile's buildable area, packed
# onto the tile's free LAND cells. Phase 3 makes the layout intelligent:
#   • the buildable mask now also subtracts ROADS (a clearance around built road
#     polylines) and FOREST canopies, not just water;
#   • placement is COST-SCORED, not centre-out: most buildings gravitate to road
#     frontage, break ties toward low ground, and cluster with same-type neighbours;
#   • recycling/extraction INVERT — they seek the far corners, away from everything.
# Footprints are axis-aligned (the "lined-up along the road" look comes from the
# road-distance gravitation + same-type clustering, not per-building rotation).
# Placement stays incremental + stable: a building keeps its spot until demolished.
#
# Ordering note: on a fresh match the seed buildings are emitted BEFORE the road
# network is bootstrapped, so they first lay out with no road data; world_map calls
# relayout() once roads exist to re-gravitate them. On load roads are already
# present at re-emit, so relayout() is idempotent there.

const TileViewData := preload("res://scripts/tile_view_data.gd")

const ROADS_BUILDING_ID := "b_005"
const FOREST_BUILDING_IDS := {"b_015": true, "b_016": true}

# Buildable grid: 27×24 cells of 20u in the tile-local frame. The hex is FLAT-TOP
# (verts (135,0)(405,0)(540,240)(405,480)(135,480)(0,240), centre (270,240)) — the
# geometry roads/forests/navgrid all use; SubtileGrid's hex_polygon is pointy-top
# and inconsistent, so we test the hex ourselves and derive road/forest blocking
# here rather than via TileOccupancy (whose grid is pointy-top and hills-only).
const GRID_COLS := 27
const GRID_ROWS := 24
const CELL := 20.0
const TILE_CENTER := Vector2(270.0, 240.0)
const DESIGN_GAP := 5.0              # gap kept around each footprint
const BUILDABLE_MIN_AREA := 400.0    # never size a footprint below ~1 cell

# Layout cost weights (tile-local units; all guesses to tune in-engine). Cost is
# minimised: cost = W_ROAD*road_dist + W_ELEV*level − W_SAME*same_attract.
const ROAD_CLEAR := 18.0             # cells within this of a road centreline aren't buildable
const ROAD_REACH := 160.0            # clip road geometry to roughly this past the hex
const NO_ROAD_DIST := 100000.0       # road_dist sentinel when the tile has no built road
const W_ROAD := 1.0                  # gravitate to road frontage (road_dist spans ~0..300)
const W_ELEV := 4.0                  # low-ground tie-break (level 0..11 → 0..44)
const W_SAME := 50.0                 # same-type cluster pull (same_attract 0..1)
const SAME_RANGE := 160.0            # same-type attraction radius
const W_AWAY := 1.5                  # edge-seekers: weight on distance-from-buildings vs from-centre

const NPC_OUTLINE_W := 7.0
const CASING := Color(0.12, 0.10, 0.06, 0.85)
const CASING_W := 2.0

## Viewport culling: when no more than this many footprints are on screen (zoomed
## in) draw only the visible ones; above it draw everything once and stay static.
const CULL_CAP := 160
const CULL_MARGIN := 600.0

@onready var terrain_layer: HexMap = %TerrainLayer
@onready var _forest_visuals: Node = get_node_or_null("../ForestVisuals")

# Per-placement: {instance_id, building_id, tile_id, coord, cells: PackedInt32Array,
#                 verts, color, is_npc, bb, cat, center_rel}
var _placements: Array = []
var _placement_index: Dictionary = {}   # instance_id -> index into _placements

# Per-tile caches (built lazily, on first building). The road_dist / level fields
# are static per tile; _tile_occ tracks what footprints have taken.
var _tile_land: Dictionary = {}       # tile_id -> PackedByteArray (1 = buildable land cell)
var _tile_occ: Dictionary = {}        # tile_id -> PackedByteArray (1 = taken by a footprint)
var _tile_roadd: Dictionary = {}      # tile_id -> PackedFloat32Array (dist to nearest road, u)
var _tile_level: Dictionary = {}      # tile_id -> PackedByteArray (NavGrid level + 1, 0..11)
var _tile_landkeys: Dictionary = {}   # tile_id -> PackedInt32Array (buildable cell keys)
var _tile_area: Dictionary = {}       # tile_id -> buildable area (u²)

var _cull := false
var _view := Rect2()
var _warned_no_nav := false

func on_building_placed(tile_id: String, building_id: String, _recipe_id: String, instance_id: String, coord: Vector2i) -> void:
	if building_id == ROADS_BUILDING_ID or FOREST_BUILDING_IDS.has(building_id):
		return  # roads aren't buildings; forests are drawn by ForestVisuals
	# Re-placement (e.g. a load re-emitting building_placed) must not orphan the
	# old footprint — drop it first so its cells free and it can't ghost.
	if instance_id != "" and _placement_index.has(instance_id):
		remove_instance(instance_id)
	_place_building(instance_id, building_id, tile_id, coord)
	queue_redraw()

## Lay out one building: size it, pick a shape, and cost-search the tile for the
## best free pocket. Appends a placement (or nothing if the tile is genuinely full).
func _place_building(instance_id: String, building_id: String, tile_id: String, coord: Vector2i) -> void:
	_ensure_tile(tile_id, coord)
	var bd := Catalog.get_building(building_id)
	var types: Array = bd.get("building_type", [])
	# Recycling (internal_name ~ "recycl": b_036 recycling_plant + b_022 water_recycling)
	# and extraction (mines) invert the score — they seek the far tile edges.
	var is_edge: bool = types.has("extraction") or str(bd.get("internal_name", "")).to_lower().contains("recycl")
	var cat := TileViewData.category_key(bd)
	var size_units := int(bd.get("tile_size_used", 1))
	var capacity := maxi(int(terrain_layer.tiles.get(coord, {}).get("build_capacity", 200)), 1)
	var area := maxf(float(size_units) / float(capacity) * float(_tile_area[tile_id]), BUILDABLE_MIN_AREA)
	var kind: String = BuildingShapes.KINDS[RoadHash.pick("poly|%s|%s|kind" % [tile_id, instance_id], BuildingShapes.KINDS.size())]
	var seed_v := RoadHash.pick("poly|%s|%s|var" % [tile_id, instance_id], 9)
	var placed_here := _placed_on_tile(tile_id)

	# Place at the requested area; shrink and retry if the tile is too full.
	var placed := _search(tile_id, coord, kind, area, seed_v, cat, is_edge, placed_here)
	var tries := 0
	while placed.is_empty() and tries < 4:
		area *= 0.6
		placed = _search(tile_id, coord, kind, maxf(area, BUILDABLE_MIN_AREA), seed_v, cat, is_edge, placed_here)
		tries += 1
	if placed.is_empty():
		return  # genuinely no room left on the tile

	var verts: PackedVector2Array = placed.verts
	var placement := {
		"instance_id": instance_id,
		"building_id": building_id,
		"tile_id": tile_id,
		"coord": coord,
		"cells": placed.cells,
		"verts": verts,
		"color": TileViewData.category_color(bd),
		"is_npc": not MatchState.is_player_owned(MatchState.get_building(instance_id)),
		"bb": _verts_bb(verts).grow(NPC_OUTLINE_W),
		"cat": cat,
		"center_rel": placed.center_rel,
	}
	if instance_id != "":
		_placement_index[instance_id] = _placements.size()
	_placements.append(placement)

## Re-run every placement (one-shot) now that the road network exists, so seeds
## laid out before bootstrap gravitate to frontage — and so any seed laid out
## before NavGrid was ready gets its water/elevation re-masked. Replays in
## _placements (emit) order with the same per-instance seeds, so it reproduces the
## layout for a given emit order. Positions are RE-DERIVED from that order, not
## persisted, so they depend on emit order (true save/load position stability is a
## later milestone). NOT called per road change — existing buildings stay put when
## the player builds a new road.
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
	queue_redraw()

## Build (once) the tile's buildable mask, road-distance + elevation fields, and
## the list of buildable cell keys. Buildable = inside the flat-top hex ∧ not water
## ∧ outside road clearance ∧ outside every forest disc.
func _ensure_tile(tile_id: String, coord: Vector2i) -> void:
	if _tile_land.has(tile_id):
		return
	var n := GRID_COLS * GRID_ROWS
	var land := PackedByteArray(); land.resize(n)
	var occ := PackedByteArray(); occ.resize(n)
	var roadd := PackedFloat32Array(); roadd.resize(n)
	var lvl := PackedByteArray(); lvl.resize(n)
	var center := _tile_center_world_pos(coord)
	var nav := NavGrid.instance()
	var nav_ok := nav != null and nav.is_ready()
	if not nav_ok and not _warned_no_nav:
		# Degenerate (unbaked map): can't exclude water/elevation. We still place so
		# relayout() has something to replay; once a bake exists nav loads (it loads
		# synchronously on instance()) and relayout re-masks this tile correctly.
		_warned_no_nav = true
		push_warning("BuildingVisuals: NavGrid not ready — water/elevation exclusion skipped until relayout.")
	var segs := _tile_road_segments(coord, center)
	var discs := _forest_discs(coord, center)
	var keys := PackedInt32Array()
	var land_count := 0
	for row in GRID_ROWS:
		for col in GRID_COLS:
			var rel := Vector2((col + 0.5) * CELL, (row + 0.5) * CELL) - TILE_CENTER
			if absf(rel.x) > 270.0 or absf(rel.y) > 240.0 or 240.0 * absf(rel.x) + 135.0 * absf(rel.y) > 64800.0:
				continue   # outside the flat-top hex
			var key := row * GRID_COLS + col
			# road distance field (kept even for non-buildable cells — used by cost)
			var rd := NO_ROAD_DIST
			for s in segs:
				rd = minf(rd, _pt_seg_dist(rel, s[0], s[1]))
			roadd[key] = rd
			if nav_ok:
				var c := nav.cell_of(center + rel)
				if nav.water(c.x, c.y) != 0:
					continue   # water (sea/lake/river) — not buildable
				lvl[key] = clampi(nav.level(c.x, c.y) + 1, 0, 11)
			if rd < ROAD_CLEAR:
				continue   # too close to a road carriageway
			var in_forest := false
			for d in discs:
				if rel.distance_to(d.c) < d.r:
					in_forest = true
					break
			if in_forest:
				continue   # under a forest canopy
			land[key] = 1
			land_count += 1
			keys.append(key)
	_tile_land[tile_id] = land
	_tile_occ[tile_id] = occ
	_tile_roadd[tile_id] = roadd
	_tile_level[tile_id] = lvl
	_tile_landkeys[tile_id] = keys
	_tile_area[tile_id] = maxf(float(land_count) * CELL * CELL, BUILDABLE_MIN_AREA)

## Cost-search the tile for the best free pocket the shape's bbox fits in. Returns
## {verts (world), cells (occupied keys), center_rel}; {} if nothing fits.
func _search(tile_id: String, coord: Vector2i, kind: String, area: float, seed_v: int, cat: String, is_edge: bool, placed_here: Array) -> Dictionary:
	if not _tile_land.has(tile_id):
		return {}   # caller must _ensure_tile first; never KeyError-crash on a miss
	var shape := BuildingShapes.make(kind, area, seed_v)
	var half: Vector2 = shape.half
	var chw := int(ceil((half.x + DESIGN_GAP) / CELL))
	var chh := int(ceil((half.y + DESIGN_GAP) / CELL))
	var land: PackedByteArray = _tile_land[tile_id]
	var occ: PackedByteArray = _tile_occ[tile_id]
	var roadd: PackedFloat32Array = _tile_roadd[tile_id]
	var lvl: PackedByteArray = _tile_level[tile_id]
	var best_key := -1
	var best_cost := INF
	for key in (_tile_landkeys[tile_id] as PackedInt32Array):
		var col := key % GRID_COLS
		var row := key / GRID_COLS
		if col < chw or col >= GRID_COLS - chw or row < chh or row >= GRID_ROWS - chh:
			continue
		if not _fits(land, occ, col, row, chw, chh):
			continue
		var rel := Vector2((col + 0.5) * CELL, (row + 0.5) * CELL) - TILE_CENTER
		var cost: float
		if is_edge:
			# Maximise distance from the centre AND from other buildings → far corner.
			cost = -(rel.length() + W_AWAY * _nearest_building_dist(rel, placed_here))
		else:
			cost = W_ROAD * roadd[key] + W_ELEV * float(lvl[key]) - W_SAME * _same_attract(rel, cat, placed_here)
		if cost < best_cost:
			best_cost = cost
			best_key = key
	if best_key < 0:
		return {}
	var bcol := best_key % GRID_COLS
	var brow := best_key / GRID_COLS
	var cells := _mark(occ, bcol, brow, chw, chh)
	var rel_best := Vector2((bcol + 0.5) * CELL, (brow + 0.5) * CELL) - TILE_CENTER
	var world_center := _tile_center_world_pos(coord) + rel_best
	var verts := PackedVector2Array()
	for v in (shape.verts as PackedVector2Array):
		verts.append(world_center + v)
	return {"verts": verts, "cells": cells, "center_rel": rel_best}

## Same-type clustering: 0..1, peaking when an already-placed same-category building
## sits right next to this pocket and fading to 0 past SAME_RANGE.
func _same_attract(rel: Vector2, cat: String, placed_here: Array) -> float:
	var nearest := 1.0e9
	for e in placed_here:
		if e.cat != cat:
			continue
		nearest = minf(nearest, rel.distance_to(e.pos))
	if nearest >= SAME_RANGE:
		return 0.0
	return clampf((SAME_RANGE - nearest) / SAME_RANGE, 0.0, 1.0)

## Distance to the nearest already-placed building on the tile (0 when alone, so an
## edge-seeker that's first simply heads for the farthest corner).
func _nearest_building_dist(rel: Vector2, placed_here: Array) -> float:
	if placed_here.is_empty():
		return 0.0
	var nearest := 1.0e9
	for e in placed_here:
		nearest = minf(nearest, rel.distance_to(e.pos))
	return nearest

func _placed_on_tile(tile_id: String) -> Array:
	var out: Array = []
	for p in _placements:
		if p.tile_id == tile_id:
			out.append({"pos": p.center_rel, "cat": p.cat})
	return out

## World-space road polylines on the tile (built infrastructure only), as segment
## pairs relative to the tile centre and clipped to roughly the hex + ROAD_REACH.
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

## Forest canopy discs on the tile, centre relative to the tile centre. Delegated
## to ForestVisuals so the avoided disc matches the drawn blob exactly.
func _forest_discs(coord: Vector2i, center: Vector2) -> Array:
	var out: Array = []
	if _forest_visuals == null or not _forest_visuals.has_method("discs_on_tile"):
		return out
	for d in _forest_visuals.discs_on_tile(coord):
		out.append({"c": (d.center as Vector2) - center, "r": float(d.radius)})
	return out

func _pt_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	var t := 0.0
	if denom > 0.0001:
		t = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _fits(land: PackedByteArray, occ: PackedByteArray, col: int, row: int, chw: int, chh: int) -> bool:
	for r in range(row - chh, row + chh + 1):
		var base := r * GRID_COLS
		for c in range(col - chw, col + chw + 1):
			var key := base + c
			if land[key] == 0 or occ[key] == 1:
				return false
	return true

func _mark(occ: PackedByteArray, col: int, row: int, chw: int, chh: int) -> PackedInt32Array:
	var cells := PackedInt32Array()
	for r in range(row - chh, row + chh + 1):
		var base := r * GRID_COLS
		for c in range(col - chw, col + chw + 1):
			occ[base + c] = 1
			cells.append(base + c)
	return cells

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
	_tile_occ.clear()
	_tile_roadd.clear()
	_tile_level.clear()
	_tile_landkeys.clear()
	_tile_area.clear()

func clear_all() -> void:
	# A loaded save rebuilds visuals (world_map._rebuild_after_load).
	_placements.clear()
	_placement_index.clear()
	_clear_tile_caches()
	queue_redraw()

func remove_instance(instance_id: String) -> void:
	# A cancelled/demolished building frees its footprint cells.
	if not _placement_index.has(instance_id):
		return
	var idx: int = _placement_index[instance_id]
	var p: Dictionary = _placements[idx]
	# Free the footprint's cells. Direct dict access (not .get with a default) so
	# the write lands on the cached array, not a throwaway; guard a missing tile.
	if _tile_occ.has(p.tile_id):
		var occ: PackedByteArray = _tile_occ[p.tile_id]
		for key in (p.cells as PackedInt32Array):
			if key >= 0 and key < occ.size():
				occ[key] = 0
	_placements.remove_at(idx)
	_placement_index.erase(instance_id)
	for iid in _placement_index:
		if _placement_index[iid] > idx:
			_placement_index[iid] -= 1
	queue_redraw()

func _draw() -> void:
	for placement in _placements:
		if _cull and not _view.intersects(placement.bb):
			continue
		var verts: PackedVector2Array = placement.verts
		draw_colored_polygon(verts, placement.color)
		var loop := verts.duplicate()
		loop.append(verts[0])
		if bool(placement.is_npc):
			draw_polyline(loop, Color.WHITE, NPC_OUTLINE_W, true)
		else:
			draw_polyline(loop, CASING, CASING_W, true)

func _tile_center_world_pos(coord: Vector2i) -> Vector2:
	if terrain_layer != null:
		return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))
	return Vector2.ZERO
