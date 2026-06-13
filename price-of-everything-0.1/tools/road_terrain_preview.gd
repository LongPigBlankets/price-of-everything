extends Node2D

const RoadRegionsData := preload("res://scripts/road_regions.gd")

const OUT_PATH := "res://artifacts/road_region_previews/terrain_routes.json"
const STEP := 12.0
const CAPSULE_RADIUS := 820.0
const INF := 1.0e30
const ROUTE_WEIGHT := 1.08
const MAX_EXPANSIONS := 260000
const TILE_CENTER := Vector2(270, 240)
const DIRS := [
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
]
const DIR_LENGTHS := [
	1.0,
	1.41421356237,
	1.0,
	1.41421356237,
	1.0,
	1.41421356237,
	1.0,
	1.41421356237,
]
const HEX_OFFSETS := [
	Vector2(-135, -240),
	Vector2(135, -240),
	Vector2(270, 0),
	Vector2(135, 240),
	Vector2(-135, 240),
	Vector2(-270, 0),
]
const SHOTS := [
	{"identity": "dense_city", "region": "capital_port"},
	{"identity": "dense_city", "region": "stoneshore"},
	{"identity": "sparse_city", "region": "southlake"},
	{"identity": "sparse_city", "region": "klade_estuary"},
	{"identity": "dense_rural", "region": "holyfinger"},
	{"identity": "dense_rural", "region": "green_flats", "suffix": "proxy"},
	{"identity": "sparse_rural", "region": "knot_valley"},
	{"identity": "sparse_rural", "region": "peatsfield"},
	{"identity": "mountain_range", "region": "blue_mountains"},
	{"identity": "mountain_range", "region": "shoulderland"},
]

@onready var terrain: HexMap = %TerrainLayer
@onready var river_visuals: Node2D = %RiverVisuals

var _failures: Array[Dictionary] = []


func _ready() -> void:
	print("\n==== roads-v2 terrain preview ====")
	await get_tree().process_frame
	var started := Time.get_ticks_msec()
	var tiles_all := _collect_tiles_all()
	var centers := _collect_centers(tiles_all)
	var rivers := _collect_rivers()
	var lakes := _collect_lakes()
	print("road_terrain_preview: generating height/nav source")
	var field_result: Dictionary = HillField.generate(tiles_all, centers, rivers, lakes, HillBaked.SEED, [], true, true)
	var source: Dictionary = field_result.get("nav_source", {})
	if source.is_empty():
		push_error("road_terrain_preview: HillField did not return nav_source")
		get_tree().quit(1)
		return
	var nav_started := Time.get_ticks_msec()
	var nav := _build_nav(source, STEP)
	_prepare_route_state(nav)
	print("road_terrain_preview: %.0fu navgrid %dx%d (%d passable) built in %.2fs" % [
		STEP,
		int(nav.gw),
		int(nav.gh),
		int(nav.passable_count),
		float(Time.get_ticks_msec() - nav_started) / 1000.0
	])

	var shots_out: Array[Dictionary] = []
	for shot in SHOTS:
		var region_id := str(shot.region)
		var identity := str(shot.identity)
		var region: Dictionary = RoadRegionsData.get_region(region_id)
		var members := _members_for_region(region)
		var edges := _generate_edges(nav, members, identity, region_id)
		shots_out.append({
			"region": region_id,
			"name": str(region.get("name", region_id)),
			"identity": identity,
			"suffix": str(shot.get("suffix", "")),
			"edges": edges,
		})
		print("road_terrain_preview: %s/%s -> %d terrain edges" % [identity, region_id, edges.size()])

	var doc := {
		"version": 1,
		"source": "12u_terrain_cost_preview",
		"step_u": STEP,
		"capsule_radius_u": CAPSULE_RADIUS,
		"route_weight": ROUTE_WEIGHT,
		"generated_ms": Time.get_ticks_msec() - started,
		"failures": _failures,
		"shots": shots_out,
	}
	_write_json(OUT_PATH, doc)
	print("ROAD_TERRAIN_PREVIEW_JSON " + ProjectSettings.globalize_path(OUT_PATH))
	print("road_terrain_preview: failures=%d elapsed=%.2fs" % [
		_failures.size(),
		float(Time.get_ticks_msec() - started) / 1000.0,
	])
	get_tree().quit(0)


func _collect_tiles_all() -> Dictionary:
	var tiles_all := {}
	for coord in terrain.tiles:
		tiles_all[coord] = terrain.tiles[coord]
	for cell in terrain.get_used_cells():
		var tc: Vector2i = terrain.tile_coord_for_map_coord(cell)
		if terrain.tiles.has(tc):
			continue
		var ttype: String = terrain._tile_type_for_source(terrain.get_cell_source_id(cell))
		if ttype == "":
			continue
		tiles_all[tc] = {"id": "deco_%d_%d" % [tc.x, tc.y], "type": ttype, "has_river": false}
	return tiles_all


func _collect_centers(tiles_all: Dictionary) -> Dictionary:
	var centers := {}
	for coord in tiles_all:
		centers[coord] = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	return centers


func _collect_rivers() -> Array:
	var rivers: Array = []
	for entry in river_visuals.get_river_polylines():
		rivers.append(entry.points)
	return rivers


func _collect_lakes() -> Array:
	var lakes: Array = []
	for coord in terrain.tiles:
		var tile_data: Dictionary = terrain.tiles[coord]
		if not tile_data.get("has_river", false):
			continue
		var river_type := str(tile_data.get("river_type", ""))
		if river_type == "" or not terrain.river_properties.has(river_type):
			continue
		var rd: Dictionary = terrain.river_properties[river_type]
		if str(rd.get("kind", "single")) != "source":
			continue
		var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		var lake_local := str(rd.get("lake_point", "C0"))
		var lp: Vector2 = SubtileGrid.RIVER_POINTS.get(lake_local, TILE_CENTER)
		var lw := 200.0 if str(rd.get("lake_width", "")) == "" else float(rd.get("lake_width"))
		var lh := 150.0 if str(rd.get("lake_height", "")) == "" else float(rd.get("lake_height"))
		lakes.append([center + lp - TILE_CENTER, lw * 0.5, lh * 0.5])
	return lakes


func _members_for_region(region: Dictionary) -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	for tile_id_value in region.get("tiles", []):
		var tile_id := str(tile_id_value)
		var coord := _coord_from_tile_id(tile_id)
		var tile: Dictionary = terrain.tiles.get(coord, {})
		if tile.is_empty():
			continue
		members.append({
			"id": tile_id,
			"coord": coord,
			"type": str(tile.get("type", "")),
			"center": terrain.map_to_local(terrain.map_coord_for_tile_coord(coord)),
		})
	return members


func _coord_from_tile_id(tile_id: String) -> Vector2i:
	var parts := tile_id.split("_")
	if parts.size() < 3:
		return Vector2i.ZERO
	return Vector2i(int(parts[1]) - 1, int(parts[2]) - 1)


func _generate_edges(nav: Dictionary, members: Array[Dictionary], identity: String, region_id: String) -> Array[Dictionary]:
	if members.size() < 2:
		return []
	var points := _member_points(members)
	var urban := _member_points_of_type(members, "urban")
	var centroid := _centroid(points)
	var edges: Array[Dictionary] = []
	var salt := int(hash(region_id + "|" + identity)) & 0x7fffffff

	if identity == RoadRegionsData.ID_DENSE_CITY:
		var ring := _dense_city_ring(members, centroid)
		if ring.size() >= 3:
			var loop := ring.duplicate()
			loop.append(ring[0])
			_add_edge(edges, nav, loop, "trunk", 8.0, identity, salt + 10)
		var hubs := _limited_nearest_points(urban if urban.size() >= 2 else points, centroid, 4)
		for h in hubs:
			if ring.size() > 0:
				_add_edge(edges, nav, [h, _nearest(h, ring)], "local", 5.0, identity, salt + 20 + hubs.find(h))
		for i in range(hubs.size()):
			for j in range(i + 1, hubs.size()):
				if hubs[i].distance_to(hubs[j]) <= 1050.0:
					_add_edge(edges, nav, [hubs[i], hubs[j]], "local", 5.0, identity, salt + 40 + i * 7 + j)
		for p in points:
			var h: Vector2 = _nearest(p, hubs)
			var dist := p.distance_to(h)
			if dist > 50.0 and dist <= 900.0:
				_add_edge(edges, nav, [h, p], "local", 4.0, identity, salt + 80 + points.find(p))
	elif identity == RoadRegionsData.ID_SPARSE_CITY:
		var hubs := _limited_nearest_points(urban if urban.size() > 0 else points, centroid, 2)
		if hubs.size() == 2:
			_add_edge(edges, nav, [hubs[0], hubs[1]], "local", 5.5, identity, salt + 100)
		for p in points:
			var h: Vector2 = _nearest(p, hubs)
			if p.distance_to(h) > 50.0:
				_add_edge(edges, nav, [h, p], "local", 4.5, identity, salt + 110 + points.find(p))
		if points.size() >= 4:
			var pair := _farthest_pair(points)
			_add_edge(edges, nav, pair, "trunk", 6.5, identity, salt + 140)
	elif identity == RoadRegionsData.ID_DENSE_RURAL:
		var hub := _dense_rural_hub(nav, points, urban, centroid)
		for p in points:
			if p.distance_to(hub) > 50.0:
				_add_edge(edges, nav, [hub, p], "local", 4.5, identity, salt + 200 + points.find(p))
		if points.size() >= 4:
			_add_edge(edges, nav, _farthest_pair(points), "local", 4.0, identity, salt + 240)
	elif identity == RoadRegionsData.ID_MOUNTAIN_RANGE:
		var pair := _farthest_pair(points)
		_add_edge(edges, nav, pair, "trunk", 5.8, identity, salt + 300)
		var spur_targets := _mountain_spur_targets(points, pair)
		for i in range(mini(spur_targets.size(), 2)):
			var target: Vector2 = spur_targets[i]
			var anchor := _project_to_segment(target, pair[0], pair[1])
			if target.distance_to(anchor) > 70.0:
				_add_edge(edges, nav, [anchor, target], "local", 3.8, identity, salt + 320 + i)
	else:
		var pair := _farthest_pair(points)
		_add_edge(edges, nav, pair, "trunk", 5.8, identity, salt + 400)
		var farms := _sparse_rural_spurs(points, pair)
		for i in range(farms.size()):
			var farm: Vector2 = farms[i]
			var anchor := _project_to_segment(farm, pair[0], pair[1])
			if farm.distance_to(anchor) > 50.0:
				_add_edge(edges, nav, [anchor, farm], "local", 3.8, identity, salt + 420 + i)
	return edges


func _add_edge(edges: Array[Dictionary], nav: Dictionary, waypoints: Array, tier: String, width: float, identity: String, salt: int) -> void:
	var routed := _route_waypoints(nav, waypoints, identity, salt)
	if routed.size() < 2:
		return
	routed = _smooth_path(_thin_path(routed, 30.0), 1)
	edges.append({
		"tier": tier,
		"width": width,
		"path": _json_points(routed),
	})


func _route_waypoints(nav: Dictionary, waypoints: Array, identity: String, salt: int) -> Array[Vector2]:
	var full: Array[Vector2] = []
	for i in range(waypoints.size() - 1):
		var a: Vector2 = waypoints[i]
		var b: Vector2 = waypoints[i + 1]
		var result := _route(nav, a, b, identity, salt + i, true)
		if not bool(result.ok):
			result = _route(nav, a, b, identity, salt + i, false)
		if not bool(result.ok):
			_failures.append({
				"identity": identity,
				"reason": str(result.get("reason", "unknown")),
				"start": [a.x, a.y],
				"goal": [b.x, b.y],
			})
			continue
		var segment: Array[Vector2] = result.path
		for p in segment:
			if full.is_empty() or full[full.size() - 1].distance_squared_to(p) > 1.0:
				full.append(p)
	return full


func _build_nav(source: Dictionary, step: float) -> Dictionary:
	var origin: Vector2 = source.origin
	var source_step := float(source.step)
	var source_gw := int(source.gw)
	var source_gh := int(source.gh)
	var width := source_step * float(source_gw - 1)
	var height := source_step * float(source_gh - 1)
	var gw := int(floor(width / step)) + 1
	var gh := int(floor(height / step)) + 1
	var count := gw * gh
	var levels := PackedByteArray()
	var passable := PackedByteArray()
	var field := PackedFloat32Array()
	var coast := PackedFloat32Array()
	levels.resize(count)
	passable.resize(count)
	field.resize(count)
	coast.resize(count)
	var passable_count := 0
	for y in gh:
		var wy := origin.y + float(y) * step
		for x in gw:
			var wx := origin.x + float(x) * step
			var idx := y * gw + x
			var value := _field_at_source(source, wx, wy)
			var band := _band_for_field(value)
			levels[idx] = clampi(band, 0, 11)
			field[idx] = value
			coast[idx] = _coast_at_source(source, wx, wy)
			var water := _water_at_source(source, wx, wy)
			passable[idx] = 0 if water else 1
			if not water:
				passable_count += 1
	return {
		"origin": origin,
		"step": step,
		"gw": gw,
		"gh": gh,
		"levels": levels,
		"passable": passable,
		"field": field,
		"coast": coast,
		"passable_count": passable_count,
	}


func _prepare_route_state(nav: Dictionary) -> void:
	var states := int(nav.gw) * int(nav.gh) * 8
	var score := PackedFloat32Array()
	var seen := PackedInt32Array()
	var closed := PackedInt32Array()
	score.resize(states)
	seen.resize(states)
	closed.resize(states)
	nav["score"] = score
	nav["seen"] = seen
	nav["closed"] = closed
	nav["stamp_id"] = 0


func _route(nav: Dictionary, start_world: Vector2, goal_world: Vector2, identity: String, salt: int, bounded: bool) -> Dictionary:
	var gw := int(nav.gw)
	var gh := int(nav.gh)
	var step := float(nav.step)
	var start_cell := _nearest_passable_cell(nav, start_world)
	var goal_cell := _nearest_passable_cell(nav, goal_world)
	if start_cell < 0 or goal_cell < 0:
		return {"ok": false, "reason": "no_passable_endpoint", "path": []}

	var stamp_id := int(nav.stamp_id) + 1
	nav["stamp_id"] = stamp_id
	var scores: PackedFloat32Array = nav.score
	var seen: PackedInt32Array = nav.seen
	var closed: PackedInt32Array = nav.closed
	var levels: PackedByteArray = nav.levels
	var passable: PackedByteArray = nav.passable
	var parents := {}
	var heap_states: Array[int] = []
	var heap_costs: Array[float] = []
	var expansions := 0
	var start_point := _cell_world(nav, start_cell)
	var goal_point := _cell_world(nav, goal_cell)
	var corridor_radius := maxf(CAPSULE_RADIUS, minf(1320.0, start_point.distance_to(goal_point) * 0.38 + 300.0))
	var corridor_min_x := minf(start_point.x, goal_point.x) - corridor_radius
	var corridor_max_x := maxf(start_point.x, goal_point.x) + corridor_radius
	var corridor_min_y := minf(start_point.y, goal_point.y) - corridor_radius
	var corridor_max_y := maxf(start_point.y, goal_point.y) + corridor_radius
	var corridor_seg := goal_point - start_point
	var corridor_len_sq := maxf(corridor_seg.length_squared(), 1.0)

	for dir in 8:
		var state := start_cell * 8 + dir
		scores[state] = 0.0
		seen[state] = stamp_id
		parents[state] = -1
		_heap_push(heap_states, heap_costs, state, _heuristic_cell(nav, start_cell, goal_cell) * ROUTE_WEIGHT)

	while not heap_states.is_empty():
		var state := _heap_pop(heap_states, heap_costs)
		if closed[state] == stamp_id:
			continue
		closed[state] = stamp_id
		expansions += 1
		if expansions > MAX_EXPANSIONS:
			return {"ok": false, "reason": "expansion_cap", "path": []}
		var cell := int(state / 8)
		var dir := state % 8
		if cell == goal_cell:
			return {
				"ok": true,
				"path": _reconstruct_path(nav, state, parents),
				"expansions": expansions,
			}
		var cx := cell % gw
		var cy := int(cell / gw)
		var cur_level := int(levels[cell]) - 1
		var cur_g := scores[state]
		for ndir in 8:
			var off: Vector2i = DIRS[ndir]
			var nx := cx + off.x
			var ny := cy + off.y
			if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
				continue
			if bounded:
				var npos := Vector2(float(nx) * step + (nav.origin as Vector2).x, float(ny) * step + (nav.origin as Vector2).y)
				if npos.x < corridor_min_x or npos.x > corridor_max_x or npos.y < corridor_min_y or npos.y > corridor_max_y:
					continue
				var t := clampf((npos - start_point).dot(corridor_seg) / corridor_len_sq, 0.0, 1.0)
				if npos.distance_squared_to(start_point + corridor_seg * t) > corridor_radius * corridor_radius:
					continue
			var ncell := ny * gw + nx
			if passable[ncell] == 0:
				continue
			var nstate := ncell * 8 + ndir
			if closed[nstate] == stamp_id:
				continue
			var next_level := int(levels[ncell]) - 1
			var move_cost := _move_cost(nav, cell, ncell, dir, ndir, cur_level, next_level, identity, salt)
			var new_g := cur_g + move_cost
			if seen[nstate] != stamp_id or new_g < scores[nstate]:
				seen[nstate] = stamp_id
				scores[nstate] = new_g
				parents[nstate] = state
				_heap_push(heap_states, heap_costs, nstate, new_g + _heuristic_cell(nav, ncell, goal_cell) * ROUTE_WEIGHT)
	return {"ok": false, "reason": "no_route", "path": []}


func _move_cost(nav: Dictionary, cell: int, ncell: int, prev_dir: int, next_dir: int, cur_level: int, next_level: int, identity: String, salt: int) -> float:
	var step := float(nav.step)
	var delta := next_level - cur_level
	var move_cost := step * float(DIR_LENGTHS[next_dir])
	move_cost *= 1.0 + 0.48 * float(abs(delta))
	if delta > 0:
		move_cost *= 1.0 + 0.18 * float(delta)
	move_cost *= 1.0 + 0.04 * float(maxi(next_level, 0))
	move_cost *= 1.0 + _gradient_crossing_penalty(nav, ncell, next_dir, identity)
	move_cost *= _coast_multiplier(nav, ncell)
	move_cost *= 1.0 + _jitter(nav, ncell, salt) * _jitter_scale(identity)
	move_cost += _turn_penalty(prev_dir, next_dir, step, cur_level, next_level, identity)
	return move_cost


func _gradient_crossing_penalty(nav: Dictionary, cell: int, dir: int, identity: String) -> float:
	var gw := int(nav.gw)
	var gh := int(nav.gh)
	var x := cell % gw
	var y := int(cell / gw)
	if x <= 0 or y <= 0 or x >= gw - 1 or y >= gh - 1:
		return 0.0
	var levels: PackedByteArray = nav.levels
	var gx := float(int(levels[y * gw + x + 1]) - int(levels[y * gw + x - 1]))
	var gy := float(int(levels[(y + 1) * gw + x]) - int(levels[(y - 1) * gw + x]))
	var grad := Vector2(gx, gy)
	var mag := clampf(grad.length() / 4.0, 0.0, 1.0)
	if mag <= 0.01:
		return 0.0
	var move := Vector2(DIRS[dir]).normalized()
	var factor := 1.15 if identity == RoadRegionsData.ID_MOUNTAIN_RANGE else 0.78
	return absf(move.dot(grad.normalized())) * mag * factor


func _coast_multiplier(nav: Dictionary, cell: int) -> float:
	var coast: PackedFloat32Array = nav.coast
	var v := coast[cell]
	if v >= 0.5 and v <= 0.72:
		return 0.92
	return 1.0


func _jitter(nav: Dictionary, cell: int, salt: int) -> float:
	var gw := int(nav.gw)
	var x := cell % gw
	var y := int(cell / gw)
	var h := int(x * 374761393 + y * 668265263 + salt * 1442695041)
	h = (h ^ (h >> 13)) * 1274126177
	h = h & 0x7fffffff
	return (float(h % 10000) / 9999.0) - 0.5


func _jitter_scale(identity: String) -> float:
	match identity:
		RoadRegionsData.ID_DENSE_CITY:
			return 0.018
		RoadRegionsData.ID_SPARSE_CITY:
			return 0.035
		RoadRegionsData.ID_DENSE_RURAL:
			return 0.045
		RoadRegionsData.ID_MOUNTAIN_RANGE:
			return 0.07
		_:
			return 0.06


func _turn_penalty(prev_dir: int, next_dir: int, step: float, cur_level: int, next_level: int, identity: String) -> float:
	var delta: int = abs(prev_dir - next_dir)
	delta = mini(delta, 8 - delta)
	var base := 0.0
	match delta:
		0:
			base = 0.0
		1:
			base = 0.18 * step
		2:
			base = 0.85 * step
		_:
			base = 3.0 * step
	if delta >= 3 and maxi(cur_level, next_level) >= 2 and abs(next_level - cur_level) >= 2:
		base *= 0.25
	var mult := 1.0
	match identity:
		RoadRegionsData.ID_DENSE_RURAL:
			mult = 1.2
		RoadRegionsData.ID_SPARSE_RURAL:
			mult = 1.3
		RoadRegionsData.ID_MOUNTAIN_RANGE:
			mult = 1.45
		RoadRegionsData.ID_DENSE_CITY:
			mult = 0.92
	return base * mult


func _nearest_passable_cell(nav: Dictionary, world: Vector2) -> int:
	var gw := int(nav.gw)
	var gh := int(nav.gh)
	var origin: Vector2 = nav.origin
	var step := float(nav.step)
	var cx := clampi(int(round((world.x - origin.x) / step)), 0, gw - 1)
	var cy := clampi(int(round((world.y - origin.y) / step)), 0, gh - 1)
	var passable: PackedByteArray = nav.passable
	var first := cy * gw + cx
	if passable[first] != 0:
		return first
	for radius in range(1, 44):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var nx := cx + dx
				var ny := cy + dy
				if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
					continue
				var idx := ny * gw + nx
				if passable[idx] != 0:
					return idx
	return -1


func _cell_world(nav: Dictionary, cell: int) -> Vector2:
	var gw := int(nav.gw)
	var origin: Vector2 = nav.origin
	var step := float(nav.step)
	return origin + Vector2(float(cell % gw) * step, float(int(cell / gw)) * step)


func _heuristic_cell(nav: Dictionary, cell: int, goal: int) -> float:
	var gw := int(nav.gw)
	var dx := float((cell % gw) - (goal % gw))
	var dy := float(int(cell / gw) - int(goal / gw))
	return sqrt(dx * dx + dy * dy) * float(nav.step)


func _reconstruct_path(nav: Dictionary, state: int, parents: Dictionary) -> Array[Vector2]:
	var cells: Array[int] = []
	var cursor := state
	var guard := 0
	while cursor >= 0 and guard < 100000:
		guard += 1
		var cell := int(cursor / 8)
		if cells.is_empty() or cells[cells.size() - 1] != cell:
			cells.append(cell)
		cursor = int(parents.get(cursor, -1))
	cells.reverse()
	var points: Array[Vector2] = []
	for cell in cells:
		points.append(_cell_world(nav, cell))
	return points


func _band_for_field(value: float) -> int:
	var b := 0
	for threshold in HillField.THRESHOLDS:
		if value >= float(threshold):
			b += 1
		else:
			break
	return b


func _field_at_source(source: Dictionary, x: float, y: float) -> float:
	var origin: Vector2 = source.origin
	var step := float(source.step)
	var gw := int(source.gw)
	var gh := int(source.gh)
	var gx := (x - origin.x) / step
	var gy := (y - origin.y) / step
	var ix := int(floor(gx))
	var iy := int(floor(gy))
	if ix < 0 or iy < 0 or ix >= gw - 1 or iy >= gh - 1:
		return 0.0
	var fx := clampf(gx - float(ix), 0.0, 1.0)
	var fy := clampf(gy - float(iy), 0.0, 1.0)
	var field: PackedFloat32Array = source.field
	var v00 := field[iy * gw + ix]
	var v10 := field[iy * gw + ix + 1]
	var v01 := field[(iy + 1) * gw + ix]
	var v11 := field[(iy + 1) * gw + ix + 1]
	var top := v00 + (v10 - v00) * fx
	return top + ((v01 + (v11 - v01) * fx) - top) * fy


func _coast_at_source(source: Dictionary, x: float, y: float) -> float:
	var idx := _nearest_source_index(source, x, y)
	if idx < 0:
		return 0.0
	var coast: PackedFloat32Array = source.coast_land
	return coast[idx]


func _water_at_source(source: Dictionary, x: float, y: float) -> bool:
	var src_idx := _nearest_source_index(source, x, y)
	if src_idx < 0:
		return true
	var types: PackedByteArray = source.types
	var coast: PackedFloat32Array = source.coast_land
	var lake_blur: PackedFloat32Array = source.lake_blur
	var t := int(types[src_idx])
	return (
		t == HillField.T_VOID
		or t == HillField.T_SEA
		or t == HillField.T_LAKE
		or coast[src_idx] < 0.5
		or lake_blur[src_idx] > 0.5
	)


func _nearest_source_index(source: Dictionary, x: float, y: float) -> int:
	var origin: Vector2 = source.origin
	var step := float(source.step)
	var gw := int(source.gw)
	var gh := int(source.gh)
	var ix := int(round((x - origin.x) / step))
	var iy := int(round((y - origin.y) / step))
	if ix < 0 or iy < 0 or ix >= gw or iy >= gh:
		return -1
	return iy * gw + ix


func _member_points(members: Array[Dictionary]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for m in members:
		out.append(m.center)
	return out


func _member_points_of_type(members: Array[Dictionary], tile_type: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for m in members:
		if str(m.type) == tile_type:
			out.append(m.center)
	return out


func _centroid(points: Array[Vector2]) -> Vector2:
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	return sum / maxf(1.0, float(points.size()))


func _nearest(target: Vector2, points: Array) -> Vector2:
	if points.is_empty():
		return target
	var best: Vector2 = points[0]
	var best_d := target.distance_squared_to(best)
	for p in points:
		var pp: Vector2 = p
		var d := target.distance_squared_to(pp)
		if d < best_d:
			best = pp
			best_d = d
	return best


func _limited_nearest_points(points: Array[Vector2], target: Vector2, limit: int) -> Array[Vector2]:
	var sorted := points.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(target) < b.distance_squared_to(target))
	var out: Array[Vector2] = []
	for i in range(mini(limit, sorted.size())):
		out.append(sorted[i])
	return out


func _farthest_pair(points: Array[Vector2]) -> Array[Vector2]:
	var best: Array[Vector2] = [points[0], points[1]]
	var best_d := points[0].distance_squared_to(points[1])
	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			var d := points[i].distance_squared_to(points[j])
			if d > best_d:
				best = [points[i], points[j]]
				best_d = d
	return best


func _dense_city_ring(members: Array[Dictionary], centroid: Vector2) -> Array[Vector2]:
	var hex_points: Array[Vector2] = []
	for m in members:
		var center: Vector2 = m.center
		for off in HEX_OFFSETS:
			hex_points.append(center + off)
	var hull := _convex_hull(hex_points)
	if hull.size() <= 10:
		return _scale_ring(hull, centroid, 0.78)
	var sampled: Array[Vector2] = []
	var stride := maxi(1, int(ceil(float(hull.size()) / 10.0)))
	for i in range(0, hull.size(), stride):
		sampled.append(hull[i])
	return _scale_ring(sampled, centroid, 0.78)


func _scale_ring(points: Array[Vector2], centroid: Vector2, scale: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in points:
		out.append(centroid + (p - centroid) * scale)
	return out


func _convex_hull(points: Array[Vector2]) -> Array[Vector2]:
	var sorted := points.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x < b.x if not is_equal_approx(a.x, b.x) else a.y < b.y
	)
	if sorted.size() <= 1:
		return sorted
	var lower: Array[Vector2] = []
	for p in sorted:
		while lower.size() >= 2 and _cross(lower[lower.size() - 2], lower[lower.size() - 1], p) <= 0.0:
			lower.pop_back()
		lower.append(p)
	var upper: Array[Vector2] = []
	for i in range(sorted.size() - 1, -1, -1):
		var p: Vector2 = sorted[i]
		while upper.size() >= 2 and _cross(upper[upper.size() - 2], upper[upper.size() - 1], p) <= 0.0:
			upper.pop_back()
		upper.append(p)
	lower.pop_back()
	upper.pop_back()
	return lower + upper


func _cross(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


func _dense_rural_hub(nav: Dictionary, points: Array[Vector2], urban: Array[Vector2], centroid: Vector2) -> Vector2:
	if not urban.is_empty():
		return _nearest(centroid, urban)
	var best := points[0]
	var best_score := INF
	for p in points:
		var score := p.distance_to(centroid) * 0.002 + float(_level_at_world(nav, p))
		if score < best_score:
			best = p
			best_score = score
	return best


func _level_at_world(nav: Dictionary, world: Vector2) -> int:
	var cell := _nearest_passable_cell(nav, world)
	if cell < 0:
		return 99
	var levels: PackedByteArray = nav.levels
	return int(levels[cell]) - 1


func _mountain_spur_targets(points: Array[Vector2], pair: Array[Vector2]) -> Array[Vector2]:
	var scored: Array[Dictionary] = []
	for p in points:
		var d := p.distance_to(_project_to_segment(p, pair[0], pair[1]))
		scored.append({"point": p, "d": d})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.d) > float(b.d))
	var out: Array[Vector2] = []
	for item in scored:
		var p: Vector2 = item.point
		if p.distance_to(pair[0]) > 20.0 and p.distance_to(pair[1]) > 20.0:
			out.append(p)
	return out


func _sparse_rural_spurs(points: Array[Vector2], pair: Array[Vector2]) -> Array[Vector2]:
	var scored: Array[Dictionary] = []
	for p in points:
		if p.distance_to(pair[0]) <= 20.0 or p.distance_to(pair[1]) <= 20.0:
			continue
		var d := p.distance_to(_project_to_segment(p, pair[0], pair[1]))
		scored.append({"point": p, "d": d})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.d) > float(b.d))
	var out: Array[Vector2] = []
	for i in range(mini(2, scored.size())):
		out.append(scored[i].point)
	return out


func _project_to_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var den := ab.length_squared()
	if den <= 0.001:
		return a
	var t := clampf((p - a).dot(ab) / den, 0.0, 1.0)
	return a + ab * t


func _thin_path(points: Array[Vector2], min_step: float) -> Array[Vector2]:
	if points.size() <= 2:
		return points
	var out: Array[Vector2] = [points[0]]
	for i in range(1, points.size() - 1):
		var p := points[i]
		if p.distance_to(out[out.size() - 1]) >= min_step:
			out.append(p)
	var last := points[points.size() - 1]
	if last.distance_squared_to(out[out.size() - 1]) > 1.0:
		out.append(last)
	return out


func _smooth_path(points: Array[Vector2], iterations: int) -> Array[Vector2]:
	var current := points
	for _i in iterations:
		if current.size() < 3:
			break
		var next: Array[Vector2] = [current[0]]
		for i in range(current.size() - 1):
			var a := current[i]
			var b := current[i + 1]
			next.append(a.lerp(b, 0.25))
			next.append(a.lerp(b, 0.75))
		next.append(current[current.size() - 1])
		current = next
	return current


func _json_points(points: Array[Vector2]) -> Array:
	var out: Array = []
	for p in points:
		out.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
	return out


func _write_json(path: String, doc: Dictionary) -> void:
	var dir_path := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("road_terrain_preview: could not write %s" % path)
		return
	file.store_string(JSON.stringify(doc, "\t"))
	file.close()


func _heap_push(states: Array[int], costs: Array[float], state: int, cost: float) -> void:
	states.append(state)
	costs.append(cost)
	var i := states.size() - 1
	while i > 0:
		var parent := int((i - 1) / 2)
		if costs[parent] <= cost:
			break
		states[i] = states[parent]
		costs[i] = costs[parent]
		i = parent
	states[i] = state
	costs[i] = cost


func _heap_pop(states: Array[int], costs: Array[float]) -> int:
	var root_state := states[0]
	var last_state: int = states.pop_back()
	var last_cost: float = costs.pop_back()
	if states.is_empty():
		return root_state
	var i := 0
	while true:
		var left := i * 2 + 1
		if left >= states.size():
			break
		var right := left + 1
		var child := left
		if right < states.size() and costs[right] < costs[left]:
			child = right
		if costs[child] >= last_cost:
			break
		states[i] = states[child]
		costs[i] = costs[child]
		i = child
	states[i] = last_state
	costs[i] = last_cost
	return root_state
