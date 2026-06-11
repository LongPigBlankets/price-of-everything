extends Node2D

const JOBS_PER_BAND := 30
const CAPSULE_RADIUS := 480.0
const INF := 1.0e30
const ROUTE_WEIGHT := 1.1

const TILE_CENTER := Vector2(270, 240)
const LATTICES := [12.0, 8.0]
const BANDS := [
	{"name": "local", "min": 350.0, "max": 850.0},
	{"name": "regional", "min": 1700.0, "max": 2600.0},
	{"name": "trunk", "min": 5600.0, "max": 7600.0},
]
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

@onready var terrain: HexMap = %TerrainLayer
@onready var river_visuals: Node2D = %RiverVisuals

var _jobs_per_band: int = JOBS_PER_BAND
var _band_filter := {}
var _step_filter: Array[float] = []


func _ready() -> void:
	print("\n==== roads-v2 lattice benchmark ====")
	_apply_args()
	await get_tree().process_frame

	var started := Time.get_ticks_msec()
	var tiles_all := _collect_tiles_all()
	var centers := _collect_centers(tiles_all)
	var rivers := _collect_rivers()
	var lakes := _collect_lakes()
	print("bench_route: generating height field for %d tiles, %d river polylines, %d source lakes" % [
		tiles_all.size(), rivers.size(), lakes.size()
	])
	var field_result: Dictionary = HillField.generate(tiles_all, centers, rivers, lakes, HillBaked.SEED, [], true, true)
	var source: Dictionary = field_result.get("nav_source", {})
	if source.is_empty():
		push_error("bench_route: HillField did not return nav_source")
		get_tree().quit(1)
		return
	var pairs := _make_pairs()
	var summaries: Array[Dictionary] = []
	var build_ms := Time.get_ticks_msec() - started
	print("bench_route: field ready in %.2fs; running %d jobs per band" % [float(build_ms) / 1000.0, _jobs_per_band])

	for lattice in _selected_lattices():
		var step := float(lattice)
		var nav_started := Time.get_ticks_msec()
		var nav := _build_nav(source, step)
		_prepare_route_state(nav)
		print("bench_route: %.0fu navgrid %dx%d (%d passable) built in %.2fs" % [
			step,
			int(nav.gw),
			int(nav.gh),
			int(nav.passable_count),
			float(Time.get_ticks_msec() - nav_started) / 1000.0
		])
		for band in _selected_bands():
			var stats := _run_band(nav, str(band.name), pairs[str(band.name)])
			summaries.append(stats)
			_print_band(stats)

	var summary := {
		"jobs_per_band": _jobs_per_band,
		"capsule_radius": CAPSULE_RADIUS,
		"field_build_ms": build_ms,
		"results": summaries,
		"decision": _decision(summaries),
	}
	print("BENCH_ROUTE_SUMMARY " + JSON.stringify(summary))
	print("bench_route: " + str(summary.decision))
	get_tree().quit(0)


func _apply_args() -> void:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		var text := str(arg)
		if text.begins_with("--jobs="):
			_jobs_per_band = maxi(1, int(text.trim_prefix("--jobs=")))
		elif text.begins_with("--bands=") or text.begins_with("--band="):
			var value := text.split("=", false, 1)[1]
			_band_filter.clear()
			for raw in value.split(",", false):
				_band_filter[str(raw).strip_edges()] = true
		elif text.begins_with("--steps=") or text.begins_with("--step="):
			var value := text.split("=", false, 1)[1]
			_step_filter.clear()
			for raw in value.split(",", false):
				_step_filter.append(float(str(raw).strip_edges()))


func _selected_bands() -> Array:
	if _band_filter.is_empty():
		return BANDS
	var out: Array[Dictionary] = []
	for band in BANDS:
		if _band_filter.has(str(band.name)):
			out.append(band)
	return out


func _selected_lattices() -> Array[float]:
	if _step_filter.is_empty():
		var out: Array[float] = []
		for step in LATTICES:
			out.append(float(step))
		return out
	return _step_filter


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


func _make_pairs() -> Dictionary:
	var land_points: Array[Vector2] = []
	for coord in terrain.tiles:
		var tile: Dictionary = terrain.tiles[coord]
		if _tile_is_route_land(tile):
			land_points.append(terrain.map_to_local(terrain.map_coord_for_tile_coord(coord)))
	var pairs := {}
	for band in _selected_bands():
		pairs[str(band.name)] = []

	var rng := RandomNumberGenerator.new()
	rng.seed = _fnv1a("roads-v2-bench-route-pairs")
	var used := {}
	var guard := 0
	while guard < 250000:
		guard += 1
		var complete := true
		for band in _selected_bands():
			if (pairs[str(band.name)] as Array).size() < _jobs_per_band:
				complete = false
				break
		if complete:
			break
		var ia := rng.randi_range(0, land_points.size() - 1)
		var ib := rng.randi_range(0, land_points.size() - 1)
		if ia == ib:
			continue
		var a := land_points[ia]
		var b := land_points[ib]
		var dist := a.distance_to(b)
		for band in _selected_bands():
			var band_name := str(band.name)
			var bucket: Array = pairs[band_name]
			if bucket.size() >= _jobs_per_band:
				continue
			if dist < float(band.min) or dist > float(band.max):
				continue
			var key := "%s:%d:%d" % [band_name, mini(ia, ib), maxi(ia, ib)]
			if used.has(key):
				continue
			used[key] = true
			bucket.append({"start": a, "goal": b, "distance": dist})
			break
	for band in _selected_bands():
		var band_name := str(band.name)
		if (pairs[band_name] as Array).size() < _jobs_per_band:
			push_warning("bench_route: only found %d %s pairs" % [(pairs[band_name] as Array).size(), band_name])
	return pairs


func _tile_is_route_land(tile: Dictionary) -> bool:
	var tile_id := str(tile.get("id", ""))
	if HillField.LAKE_TILES.has(tile_id):
		return false
	var t := str(tile.get("type", ""))
	return t != "" and t != "sea" and t != "deep_sea"


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
	levels.resize(count)
	passable.resize(count)
	var passable_count := 0
	for y in gh:
		var wy := origin.y + float(y) * step
		for x in gw:
			var wx := origin.x + float(x) * step
			var idx := y * gw + x
			var band := _band_at_source(source, wx, wy)
			levels[idx] = clampi(band, 0, 11)
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


func _run_band(nav: Dictionary, band_name: String, pairs: Array) -> Dictionary:
	var samples: Array[Dictionary] = []
	var failures := 0
	for pair in pairs:
		var result := _route(nav, pair.start, pair.goal, true)
		result["straight_distance"] = float(pair.distance)
		if bool(result.ok):
			samples.append(result)
		else:
			failures += 1
	return _summarize(nav, band_name, pairs.size(), failures, samples)


func _route(nav: Dictionary, start_world: Vector2, goal_world: Vector2, bounded: bool) -> Dictionary:
	var gw := int(nav.gw)
	var gh := int(nav.gh)
	var step := float(nav.step)
	var start_cell := _nearest_passable_cell(nav, start_world)
	var goal_cell := _nearest_passable_cell(nav, goal_world)
	if start_cell < 0 or goal_cell < 0:
		return {"ok": false, "reason": "no_passable_endpoint", "ms": 0.0, "expansions": 0}

	var stamp_id := int(nav.stamp_id) + 1
	nav["stamp_id"] = stamp_id
	var scores: PackedFloat32Array = nav.score
	var seen: PackedInt32Array = nav.seen
	var closed: PackedInt32Array = nav.closed
	var levels: PackedByteArray = nav.levels
	var passable: PackedByteArray = nav.passable
	var heap_states: Array[int] = []
	var heap_costs: Array[float] = []
	var started := Time.get_ticks_usec()
	var peak_open := 0
	var expansions := 0
	var start_point := _cell_world(nav, start_cell)
	var goal_point := _cell_world(nav, goal_cell)
	var corridor_min_x := minf(start_point.x, goal_point.x) - CAPSULE_RADIUS
	var corridor_max_x := maxf(start_point.x, goal_point.x) + CAPSULE_RADIUS
	var corridor_min_y := minf(start_point.y, goal_point.y) - CAPSULE_RADIUS
	var corridor_max_y := maxf(start_point.y, goal_point.y) + CAPSULE_RADIUS
	var corridor_seg := goal_point - start_point
	var corridor_len_sq := maxf(corridor_seg.length_squared(), 1.0)

	for dir in 8:
		var state := start_cell * 8 + dir
		scores[state] = 0.0
		seen[state] = stamp_id
		_heap_push(heap_states, heap_costs, state, _heuristic_cell(nav, start_cell, goal_cell) * ROUTE_WEIGHT)

	while not heap_states.is_empty():
		peak_open = maxi(peak_open, heap_states.size())
		var state := _heap_pop(heap_states, heap_costs)
		if closed[state] == stamp_id:
			continue
		closed[state] = stamp_id
		expansions += 1
		var cell := int(state / 8)
		var dir := state % 8
		if cell == goal_cell:
			var elapsed := Time.get_ticks_usec() - started
			return {
				"ok": true,
				"ms": float(elapsed) / 1000.0,
				"expansions": expansions,
				"us_per_expansion": float(elapsed) / maxf(float(expansions), 1.0),
				"peak_open": peak_open,
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
				if npos.distance_squared_to(start_point + corridor_seg * t) > CAPSULE_RADIUS * CAPSULE_RADIUS:
					continue
			var ncell := ny * gw + nx
			if passable[ncell] == 0:
				continue
			var nstate := ncell * 8 + ndir
			if closed[nstate] == stamp_id:
				continue
			var next_level := int(levels[ncell]) - 1
			var move_cost := step * float(DIR_LENGTHS[ndir])
			move_cost *= 1.0 + 0.5 * float(abs(next_level - cur_level))
			move_cost *= 1.0 + 0.03 * float(maxi(next_level, 0))
			move_cost += _turn_penalty(dir, ndir, step)
			var new_g := cur_g + move_cost
			if seen[nstate] != stamp_id or new_g < scores[nstate]:
				seen[nstate] = stamp_id
				scores[nstate] = new_g
				_heap_push(heap_states, heap_costs, nstate, new_g + _heuristic_cell(nav, ncell, goal_cell) * ROUTE_WEIGHT)
	var elapsed_fail := Time.get_ticks_usec() - started
	return {
		"ok": false,
		"reason": "no_route",
		"ms": float(elapsed_fail) / 1000.0,
		"expansions": expansions,
		"peak_open": peak_open,
	}


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
	for radius in range(1, 36):
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


func _turn_penalty(prev_dir: int, next_dir: int, step: float) -> float:
	var delta: int = abs(prev_dir - next_dir)
	delta = mini(delta, 8 - delta)
	match delta:
		0:
			return 0.0
		1:
			return 0.2 * step
		2:
			return 0.9 * step
		_:
			return 3.0 * step


func _summarize(nav: Dictionary, band_name: String, jobs: int, failures: int, samples: Array[Dictionary]) -> Dictionary:
	var ms: Array[float] = []
	var expansions: Array[float] = []
	var us_per: Array[float] = []
	var open_sizes: Array[float] = []
	for sample in samples:
		ms.append(float(sample.ms))
		expansions.append(float(sample.expansions))
		us_per.append(float(sample.us_per_expansion))
		open_sizes.append(float(sample.peak_open))
	ms.sort()
	expansions.sort()
	us_per.sort()
	open_sizes.sort()
	return {
		"step": int(nav.step),
		"band": band_name,
		"bounded": true,
		"jobs": jobs,
		"ok": samples.size(),
		"failures": failures,
		"p50_ms": _percentile(ms, 0.50),
		"p95_ms": _percentile(ms, 0.95),
		"p50_expansions": _percentile(expansions, 0.50),
		"p95_expansions": _percentile(expansions, 0.95),
		"p50_us_per_expansion": _percentile(us_per, 0.50),
		"p95_us_per_expansion": _percentile(us_per, 0.95),
		"p95_peak_open": _percentile(open_sizes, 0.95),
	}


func _percentile(values: Array[float], p: float) -> float:
	if values.is_empty():
		return 0.0
	var idx := clampi(int(ceil(p * float(values.size()))) - 1, 0, values.size() - 1)
	return values[idx]


func _print_band(stats: Dictionary) -> void:
	print("bench_route: %2du %-8s ok=%2d/%2d p50=%7.2fms p95=%7.2fms exp_p50=%8.0f exp_p95=%8.0f us/exp_p50=%5.2f" % [
		int(stats.step),
		str(stats.band),
		int(stats.ok),
		int(stats.jobs),
		float(stats.p50_ms),
		float(stats.p95_ms),
		float(stats.p50_expansions),
		float(stats.p95_expansions),
		float(stats.p50_us_per_expansion),
	])


func _decision(summaries: Array[Dictionary]) -> Dictionary:
	var trunk12 := _find_summary(summaries, 12, "trunk")
	var trunk8 := _find_summary(summaries, 8, "trunk")
	if trunk12.is_empty() or trunk8.is_empty():
		return {"choice": "unknown", "reason": "missing trunk summary"}
	var twelve_pass := int(trunk12.failures) == 0 and float(trunk12.p50_ms) <= 60.0 and float(trunk12.p95_ms) <= 150.0
	var eight_pass := int(trunk8.failures) == 0 and float(trunk8.p95_ms) <= 150.0
	if eight_pass:
		return {"choice": "8u", "reason": "8u trunk P95 is inside the 150 ms adoption gate", "trunk_p95_ms": trunk8.p95_ms}
	if twelve_pass:
		return {"choice": "12u", "reason": "12u passes G1 while 8u misses G2", "trunk_p95_ms": trunk12.p95_ms}
	return {
		"choice": "neither",
		"reason": "12u misses G1; Phase 2 should include stronger bounding/hierarchy",
		"trunk12_p95_ms": trunk12.p95_ms,
		"trunk8_p95_ms": trunk8.p95_ms,
	}


func _find_summary(summaries: Array[Dictionary], step: int, band: String) -> Dictionary:
	for summary in summaries:
		if int(summary.step) == step and str(summary.band) == band:
			return summary
	return {}


func _band_at_source(source: Dictionary, x: float, y: float) -> int:
	var v := _field_at_source(source, x, y)
	var b := 0
	for threshold in HillField.THRESHOLDS:
		if v >= float(threshold):
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


func _fnv1a(text: String) -> int:
	var h := 2166136261
	for i in text.length():
		h = (h ^ text.unicode_at(i)) * 16777619
		h = h & 0xffffffff
	return h
