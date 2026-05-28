class_name RegionRoadPlanner
extends RefCounted

const ROAD_WIDTH := 5.0
const BELTWAY_WIDTH := 5.0
const JUNCTION_RADIUS := 5.0
const CURVE_STEPS := 14
const TILE_CENTER := Vector2(270, 240)
const LOCAL_HEX_CORNERS := [Vector2(270, 0), Vector2(540, 120), Vector2(540, 360), Vector2(270, 480), Vector2(0, 360), Vector2(0, 120)]
const SNAP := 1024.0
const MIN_SECTION_LENGTH := 30.0

class RegionPlan extends RefCounted:
	var edges: Array[Dictionary] = []
	var bridges: Array[Dictionary] = []
	var junctions: Array[Dictionary] = []
	var boundary: PackedVector2Array = PackedVector2Array()
	var inset_loop: PackedVector2Array = PackedVector2Array()

	func signature() -> String:
		var point_count := 0
		var sum_x := 0
		var sum_y := 0
		for edge in edges:
			var path: PackedVector2Array = edge.get("path", PackedVector2Array())
			for point in path:
				point_count += 1
				sum_x += roundi(point.x * 1000.0)
				sum_y += roundi(point.y * 1000.0)
		return "%d:%d:%d" % [point_count, sum_x, sum_y]

class RegionParams extends Resource:
	var beltway_inset_ratio := 0.30
	var spur_length_ratio := 0.50
	var spur_stride := 2
	var trunk_length_ratio := 1.45
	var trunk_stride := 2
	var fractal_depth := 3
	var fractal_split_deg := 25.0
	var fractal_length_decay := 0.62
	var branch_split_chance := 0.66
	var branch_continue_chance := 0.18
	var coastal_bind_iterations := 8
	var coastal_bind_step_ratio := 0.18
	var coastal_clearance_px := 40.0
	var coastal_outline_tension := 0.08
	var island_use_core_shape := true
	var core_connector_arm_count := 4
	var core_connector_drop_count := 1
	var core_connector_dogleg_count := 1
	var core_connector_angle_deg := 45.0
	var core_connector_reach_ratio := 0.70
	var core_connector_dogleg_ratio := 0.28
	var branch_junction_spacing_ratio := 0.40
	var branch_junction_min_spacing := 100.0
	var branch_cross_short_ratio := 0.30
	var branch_cross_long_ratio := 0.67
	var branch_y_arm_ratio := 0.48
	var coastal_t_inset_ratio := 0.22
	var curve_wobble_ratio := 0.12
	var rng_seed := 0
	var density_tier := "medium"

var terrain_layer: HexMap
var _rng := RandomNumberGenerator.new()
var _params := RegionParams.new()
var _hex_size := 270.0


func _init(p_terrain_layer: HexMap) -> void:
	terrain_layer = p_terrain_layer


func plan(tile_coords: Array[Vector2i], params: RegionParams) -> RegionPlan:
	_params = params
	_rng.seed = int(params.rng_seed) if int(params.rng_seed) != 0 else hash_region_signature(tile_coords)
	var result := RegionPlan.new()
	if terrain_layer == null or tile_coords.is_empty():
		return result

	var sorted_tiles := tile_coords.duplicate()
	sorted_tiles.sort_custom(_sort_tile_coord)
	var boundary := _trace_boundary(sorted_tiles)
	if boundary.size() < 3:
		return result
	result.boundary = boundary

	_hex_size = _estimate_hex_size(sorted_tiles[0])
	var centroid := _tiles_centroid(sorted_tiles)
	var external_land := _external_land_neighbors(sorted_tiles)
	var has_sea_neighbor := _region_has_sea_neighbor(sorted_tiles)
	var inset_loop := _coastal_anchor_loop(sorted_tiles, centroid) if has_sea_neighbor else _inset_polygon(boundary, _hex_size * params.beltway_inset_ratio)
	if inset_loop.size() < 3:
		inset_loop = _inset_polygon(boundary, _hex_size * params.beltway_inset_ratio)
	if not has_sea_neighbor:
		inset_loop = _wobble_loop(inset_loop, centroid, _hex_size * 0.035)
	result.inset_loop = inset_loop

	if _params.island_use_core_shape and external_land.is_empty():
		_add_coastal_core_shape(result, sorted_tiles, centroid)
		return result
	else:
		if has_sea_neighbor:
			_add_coastal_edge_roads(result, sorted_tiles)
		else:
			for segment in _polyline_to_cubic_loop(inset_loop, 0.22):
				_add_edge(result, _filtered_path(sample_bezier(segment, CURVE_STEPS)), BELTWAY_WIDTH, "region_beltway")
	if not has_sea_neighbor:
		_add_inner_spurs(result, inset_loop, centroid)
	_add_core_connectors(result, sorted_tiles, inset_loop)
	_add_outer_branches(result, sorted_tiles, inset_loop, centroid)
	return result


static func hash_region_signature(tile_coords: Array[Vector2i]) -> int:
	var parts: Array[String] = []
	for coord in tile_coords:
		parts.append("%d_%d" % [coord.x, coord.y])
	parts.sort()
	return abs(hash("|".join(parts)))


static func sample_bezier(segment: PackedVector2Array, steps: int = 14) -> PackedVector2Array:
	var out := PackedVector2Array()
	if segment.size() != 4:
		return out
	out.resize(steps + 1)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var u := 1.0 - t
		out[i] = (u * u * u) * segment[0] + (3.0 * u * u * t) * segment[1] + (3.0 * u * t * t) * segment[2] + (t * t * t) * segment[3]
	return out


func _trace_boundary(cells: Array[Vector2i]) -> PackedVector2Array:
	var points: Array[Vector2] = []
	for cell in cells:
		for corner in _hex_corners_world(cell):
			points.append(corner)
	return _convex_hull(points)


func _convex_hull(points: Array[Vector2]) -> PackedVector2Array:
	var unique: Array[Vector2] = []
	var seen := {}
	for point in points:
		var key := "%d:%d" % [roundi(point.x * SNAP), roundi(point.y * SNAP)]
		if seen.has(key):
			continue
		seen[key] = true
		unique.append(point)
	if unique.size() < 3:
		return PackedVector2Array(unique)
	unique.sort_custom(_sort_points_xy)

	var lower: Array[Vector2] = []
	for point in unique:
		while lower.size() >= 2 and _cross(lower[lower.size() - 1] - lower[lower.size() - 2], point - lower[lower.size() - 1]) <= 0.0:
			lower.pop_back()
		lower.append(point)

	var upper: Array[Vector2] = []
	for i in range(unique.size() - 1, -1, -1):
		var point: Vector2 = unique[i]
		while upper.size() >= 2 and _cross(upper[upper.size() - 1] - upper[upper.size() - 2], point - upper[upper.size() - 1]) <= 0.0:
			upper.pop_back()
		upper.append(point)

	lower.pop_back()
	upper.pop_back()
	var hull := PackedVector2Array()
	for point in lower:
		hull.append(point)
	for point in upper:
		hull.append(point)
	return hull


func _sort_points_xy(a: Vector2, b: Vector2) -> bool:
	return a.x < b.x or (is_equal_approx(a.x, b.x) and a.y < b.y)


func _cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


func _inset_polygon(poly: PackedVector2Array, dist: float) -> PackedVector2Array:
	var n := poly.size()
	var out := PackedVector2Array()
	out.resize(n)
	for i in range(n):
		var p_prev: Vector2 = poly[(i + n - 1) % n]
		var p_curr: Vector2 = poly[i]
		var p_next: Vector2 = poly[(i + 1) % n]
		var n_in := (p_curr - p_prev).normalized().rotated(PI / 2.0)
		var n_out := (p_next - p_curr).normalized().rotated(PI / 2.0)
		var bis := n_in + n_out
		if bis.length() < 0.0001:
			bis = n_out
		bis = bis.normalized()
		var cosh_a: float = maxf(bis.dot(n_in), 0.15)
		out[i] = p_curr + bis * (dist / cosh_a)
	return out


func _coastal_anchor_loop(cells: Array[Vector2i], centroid: Vector2) -> PackedVector2Array:
	var members := {}
	for cell in cells:
		members[cell] = true

	var points: Array[Vector2] = []
	var seen := {}
	var normal_inset := _hex_size * _params.beltway_inset_ratio
	for cell in cells:
		var corners := _hex_corners_world(cell)
		var cell_center := terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(cell))
		for side in range(6):
			var neighbor := cell + _neighbor_offset_for_side(cell, side)
			if members.has(neighbor):
				continue
			var edge_start: Vector2 = corners[side]
			var edge_end: Vector2 = corners[(side + 1) % 6]
			var midpoint := (edge_start + edge_end) * 0.5
			var inward := (cell_center - midpoint).normalized()
			var inset := _params.coastal_clearance_px if _neighbor_is_sea(neighbor) else normal_inset
			_add_unique_outline_point(points, seen, edge_start + inward * inset)
			_add_unique_outline_point(points, seen, edge_end + inward * inset)

	if points.size() < 3:
		return PackedVector2Array()
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return (a - centroid).angle() < (b - centroid).angle()
	)
	var out := PackedVector2Array()
	for point in points:
		out.append(point)
	return out


func _add_coastal_edge_roads(result: RegionPlan, cells: Array[Vector2i]) -> void:
	var members := {}
	for cell in cells:
		members[cell] = true

	var normal_inset := _hex_size * _params.beltway_inset_ratio
	for cell in cells:
		var corners := _hex_corners_world(cell)
		var cell_center := terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(cell))
		for side in range(6):
			var neighbor := cell + _neighbor_offset_for_side(cell, side)
			if members.has(neighbor):
				continue
			var edge_start: Vector2 = corners[side]
			var edge_end: Vector2 = corners[(side + 1) % 6]
			var midpoint := (edge_start + edge_end) * 0.5
			var inward := (cell_center - midpoint).normalized()
			var inset := _params.coastal_clearance_px if _neighbor_is_sea(neighbor) else normal_inset
			var start := edge_start + inward * inset
			var end := edge_end + inward * inset
			var path := _filtered_path(_clamp_path_to_coastal_clearance(_wobbly_segment(start, end, end - start), cell_center))
			_add_edge(result, path, BELTWAY_WIDTH, "coastal_edge")


func _add_unique_outline_point(points: Array[Vector2], seen: Dictionary, point: Vector2) -> void:
	var key := "%d:%d" % [roundi(point.x * SNAP), roundi(point.y * SNAP)]
	if seen.has(key):
		return
	seen[key] = true
	points.append(point)


func _polyline_to_cubic_loop(points: PackedVector2Array, tension: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var n := points.size()
	if n < 3:
		return out
	for i in range(n):
		var p0: Vector2 = points[(i + n - 1) % n]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[(i + 1) % n]
		var p3: Vector2 = points[(i + 2) % n]
		out.append(PackedVector2Array([p1, p1 + (p2 - p0) * tension, p2 - (p3 - p1) * tension, p2]))
	return out


func _add_inner_spurs(result: RegionPlan, inset_loop: PackedVector2Array, centroid: Vector2) -> void:
	var stride: int = maxi(_params.spur_stride, 1)
	var spur_len := _hex_size * _params.spur_length_ratio
	for i in range(0, inset_loop.size(), stride):
		var anchor: Vector2 = inset_loop[i]
		var raw_dir := centroid - anchor
		if raw_dir.length() < 0.001:
			continue
		var max_len: float = minf(spur_len, raw_dir.length() * 0.72)
		if max_len < MIN_SECTION_LENGTH:
			continue
		var dir := raw_dir.normalized().rotated(deg_to_rad(_rng.randf_range(-8.0, 8.0)))
		var tip := anchor + dir * max_len
		var perp := dir.rotated(PI / 2.0)
		var bend := _rng.randf_range(-0.14, 0.14) * max_len
		var segment := PackedVector2Array([anchor, anchor + dir * max_len * 0.4 + perp * bend, tip - dir * max_len * 0.35 - perp * bend, tip])
		_add_edge(result, _filtered_path(sample_bezier(segment, CURVE_STEPS)), ROAD_WIDTH, "inner_spur")
		result.junctions.append({"point": anchor, "radius": JUNCTION_RADIUS})


func _add_core_connectors(result: RegionPlan, cells: Array[Vector2i], inset_loop: PackedVector2Array) -> void:
	for cell in _central_cells(cells):
		var center := terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(cell))
		_add_core_shape(result, center, inset_loop)


func _add_coastal_core_shape(result: RegionPlan, cells: Array[Vector2i], centroid: Vector2) -> void:
	var centers := _central_cells(cells)
	if centers.is_empty():
		_add_core_shape(result, centroid, PackedVector2Array())
		_add_coastal_t(result, centroid, _sea_direction_from_point(centroid))
		return

	for cell in centers:
		var center := terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(cell))
		_add_core_shape(result, center, PackedVector2Array())
		_add_coastal_t(result, center, _sea_direction_from_point(center))


func _add_core_shape(result: RegionPlan, center: Vector2, inset_loop: PackedVector2Array) -> void:
	var arm_count: int = clampi(_params.core_connector_arm_count, 3, 6)
	var drop_count: int = clampi(_params.core_connector_drop_count, 0, maxi(arm_count - 3, 0))
	var dogleg_count: int = clampi(_params.core_connector_dogleg_count, 0, arm_count - drop_count)
	var drop_start: int = int(abs(_params.rng_seed)) % arm_count
	var dogleg_start: int = (drop_start + 2) % arm_count
	var base_angle := deg_to_rad(_params.core_connector_angle_deg)
	var reach := _hex_size * _params.core_connector_reach_ratio
	for i in range(arm_count):
		if _cyclic_distance(i, drop_start, arm_count) < drop_count:
			continue
		var dir := Vector2.RIGHT.rotated(base_angle + TAU * float(i) / float(arm_count))
		var target := center + dir * reach
		if inset_loop.size() >= 3:
			target = _loop_point_in_direction(center, dir, inset_loop, reach)
		target = _clamp_point_to_land(target, center)
		var path := _dogleg_segment(center, target, dir) if _cyclic_distance(i, dogleg_start, arm_count) < dogleg_count else _wobbly_segment(center, target, dir)
		_add_edge(result, _filtered_path(_clamp_path_to_land(path, center)), ROAD_WIDTH, "core_connector")
	result.junctions.append({"point": center, "radius": JUNCTION_RADIUS})


func _add_coastal_t(result: RegionPlan, center: Vector2, dir: Vector2) -> void:
	if dir.is_zero_approx():
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var coast := _land_edge_point(center, dir)
	var t_center := _clamp_point_to_land(coast - dir * _hex_size * _params.coastal_t_inset_ratio, center)
	_add_edge(result, _filtered_path(_clamp_path_to_land(_wobbly_segment(center, t_center, dir), center)), ROAD_WIDTH, "coastal_stem")
	result.junctions.append({"point": t_center, "radius": JUNCTION_RADIUS})

	var side := dir.rotated(PI / 2.0)
	var short_target := _clamp_point_to_land(t_center + side * _hex_size * _params.branch_cross_short_ratio, center)
	var long_target := _clamp_point_to_land(t_center - side * _hex_size * _params.branch_cross_long_ratio, center)
	_add_edge(result, _filtered_path(_clamp_path_to_land(_wobbly_segment(t_center, short_target, side), center)), ROAD_WIDTH, "coastal_t_arm")
	_add_edge(result, _filtered_path(_clamp_path_to_land(_wobbly_segment(t_center, long_target, -side), center)), ROAD_WIDTH, "coastal_t_arm")


func _add_outer_branches(result: RegionPlan, cells: Array[Vector2i], inset_loop: PackedVector2Array, centroid: Vector2) -> void:
	var stride: int = maxi(_params.trunk_stride, 1)
	var anchors := _branch_anchor_indices(inset_loop.size(), stride, _external_land_neighbors(cells).size())
	for i in anchors:
		var anchor: Vector2 = inset_loop[int(i)]
		var out_dir := _outward_normal_at_loop(inset_loop, int(i), centroid)
		if out_dir.length() < 0.001:
			continue
		var trunk_len := _hex_size * _params.trunk_length_ratio * _rng.randf_range(0.85, 1.18)
		if _path_stays_on_land(_filtered_path(sample_bezier(_branch_segment(anchor, out_dir.normalized(), trunk_len), CURVE_STEPS))):
			_grow_branch(result, anchor, out_dir.normalized(), trunk_len, _params.fractal_depth)
			continue
		var inward := centroid - anchor
		var inward_len: float = minf(trunk_len * 0.45, inward.length() * 0.64)
		if inward_len >= MIN_SECTION_LENGTH:
			_grow_inward_branch(result, anchor, inward.normalized(), inward_len, mini(_params.fractal_depth, 3), centroid)


func _branch_anchor_indices(loop_size: int, stride: int, max_count: int) -> Array[int]:
	var result: Array[int] = []
	if loop_size <= 0 or max_count <= 0:
		return result

	var candidates: Array[int] = []
	var phase := stride / 2
	for i in range(phase, loop_size, stride):
		candidates.append(i)
	if candidates.size() <= max_count:
		return candidates

	var step := float(candidates.size()) / float(max_count)
	for i in range(max_count):
		var index := mini(floori(float(i) * step), candidates.size() - 1)
		result.append(candidates[index])
	return result


func _external_land_neighbors(cells: Array[Vector2i]) -> Array[Vector2i]:
	var members := {}
	for cell in cells:
		members[cell] = true

	var neighbors: Array[Vector2i] = []
	var seen := {}
	for cell in cells:
		for offset in _neighbor_offsets_for_coord(cell):
			var neighbor := cell + offset
			if members.has(neighbor) or seen.has(neighbor):
				continue
			seen[neighbor] = true
			if not terrain_layer.tiles.has(neighbor):
				continue
			var tile: Dictionary = terrain_layer.tiles[neighbor]
			var tile_type := str(tile.get("type", "")).strip_edges()
			if tile_type == "" or tile_type == "sea" or tile_type == "deep_sea":
				continue
			neighbors.append(neighbor)
	return neighbors


func _region_has_sea_neighbor(cells: Array[Vector2i]) -> bool:
	var members := {}
	for cell in cells:
		members[cell] = true
	for cell in cells:
		for side in range(6):
			var neighbor := cell + _neighbor_offset_for_side(cell, side)
			if members.has(neighbor):
				continue
			if _neighbor_is_sea(neighbor):
				return true
	return false


func _neighbor_is_sea(coord: Vector2i) -> bool:
	if not terrain_layer.tiles.has(coord):
		return true
	var tile: Dictionary = terrain_layer.tiles[coord]
	var tile_type := str(tile.get("type", "")).strip_edges()
	return tile_type == "" or tile_type == "sea" or tile_type == "deep_sea"


func _grow_branch(result: RegionPlan, start: Vector2, dir: Vector2, length: float, depth: int) -> void:
	if depth <= 0 or length < _hex_size * 0.2:
		return
	var end_dir := dir.rotated(deg_to_rad(_rng.randf_range(-10.0, 10.0)))
	var end_point := start + end_dir * length
	var segment := _branch_segment(start, dir, length, end_dir)
	var path := _filtered_path(sample_bezier(segment, CURVE_STEPS))
	if not _path_stays_on_land(path):
		return
	_add_edge(result, path, ROAD_WIDTH, "outer_branch")
	_add_branch_junctions(result, start, end_dir, length, depth)


func _add_branch_junctions(result: RegionPlan, start: Vector2, dir: Vector2, length: float, depth: int) -> void:
	var spacing: float = maxf(_hex_size * _params.branch_junction_spacing_ratio, _params.branch_junction_min_spacing)
	var max_junctions := mini(maxi(depth - 1, 0), floori(length / spacing))
	for i in range(max_junctions):
		var distance := spacing * float(i + 1)
		if distance > length - MIN_SECTION_LENGTH:
			break
		var point := start + dir.normalized() * distance
		if not _point_is_on_land(point):
			continue
		if i % 2 == 0:
			_add_y_junction(result, point, dir)
		else:
			_add_cross_junction(result, point, dir)


func _add_y_junction(result: RegionPlan, point: Vector2, dir: Vector2) -> void:
	if _rng.randf() > _params.branch_split_chance:
		return
	var half_split := deg_to_rad(minf(_params.fractal_split_deg, 35.0))
	var arm_len := _hex_size * _params.branch_y_arm_ratio
	for sign_value in [-1.0, 1.0]:
		var arm_dir := dir.rotated(half_split * sign_value)
		var target := point + arm_dir * arm_len * _rng.randf_range(0.85, 1.10)
		var path := _filtered_path(_wobbly_segment(point, target, arm_dir))
		if _path_stays_on_land(path):
			_add_edge(result, path, ROAD_WIDTH, "branch_y_arm")
	result.junctions.append({"point": point, "radius": JUNCTION_RADIUS})


func _add_cross_junction(result: RegionPlan, point: Vector2, dir: Vector2) -> void:
	if _rng.randf() > _params.branch_continue_chance + _params.branch_split_chance:
		return
	var side := dir.rotated(PI / 2.0)
	var arms := [
		{"dir": side, "len": _hex_size * _params.branch_cross_short_ratio},
		{"dir": -side, "len": _hex_size * _params.branch_cross_long_ratio},
	]
	for arm in arms:
		var arm_dir: Vector2 = arm["dir"]
		var arm_len: float = arm["len"]
		var target := point + arm_dir * arm_len * _rng.randf_range(0.90, 1.08)
		var path := _filtered_path(_wobbly_segment(point, target, arm_dir))
		if _path_stays_on_land(path):
			_add_edge(result, path, ROAD_WIDTH, "branch_cross_arm")
	result.junctions.append({"point": point, "radius": JUNCTION_RADIUS})


func _grow_inward_branch(result: RegionPlan, start: Vector2, dir: Vector2, length: float, depth: int, centroid: Vector2) -> void:
	if depth <= 0 or length < MIN_SECTION_LENGTH:
		return
	var target_dir := (centroid - start).normalized()
	if target_dir.is_zero_approx():
		target_dir = dir
	var end_dir := target_dir.rotated(deg_to_rad(_rng.randf_range(-8.0, 8.0)))
	var safe_len: float = minf(length, start.distance_to(centroid) * 0.68)
	if safe_len < MIN_SECTION_LENGTH:
		return
	var end_point := start + end_dir * safe_len
	var path := _filtered_path(sample_bezier(_branch_segment(start, target_dir, safe_len, end_dir), CURVE_STEPS))
	if not _path_stays_on_land(path):
		return
	_add_edge(result, path, ROAD_WIDTH, "inner_branch")
	var child_len := safe_len * _params.fractal_length_decay
	if _rng.randf() < 0.70:
		_grow_inward_branch(result, end_point, (centroid - end_point).normalized().rotated(deg_to_rad(-14.0)), child_len, depth - 1, centroid)
	if _rng.randf() < 0.70:
		_grow_inward_branch(result, end_point, (centroid - end_point).normalized().rotated(deg_to_rad(14.0)), child_len, depth - 1, centroid)


func _branch_segment(start: Vector2, dir: Vector2, length: float, end_dir: Vector2 = Vector2.INF) -> PackedVector2Array:
	var final_dir := end_dir if end_dir != Vector2.INF else dir
	var end_point := start + final_dir * length
	return PackedVector2Array([start, start + dir * length * 0.32, end_point - final_dir * length * 0.32, end_point])


func _add_edge(result: RegionPlan, path: PackedVector2Array, width: float, kind: String) -> void:
	if path.size() < 2 or _path_length(path) < MIN_SECTION_LENGTH:
		return
	result.edges.append({"path": path, "width": width, "kind": kind})


func _hex_corners_world(tile_coord: Vector2i) -> PackedVector2Array:
	var center := terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(tile_coord))
	var out := PackedVector2Array()
	for corner in LOCAL_HEX_CORNERS:
		out.append(center + corner - TILE_CENTER)
	return out


func _tiles_centroid(cells: Array[Vector2i]) -> Vector2:
	var sum := Vector2.ZERO
	for cell in cells:
		sum += terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(cell))
	return sum / float(cells.size())


func _central_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var members := {}
	for cell in cells:
		members[cell] = true

	var result: Array[Vector2i] = []
	for cell in cells:
		var surrounded := true
		for offset in _neighbor_offsets_for_coord(cell):
			if not members.has(cell + offset):
				surrounded = false
				break
		if surrounded:
			result.append(cell)
	return result


func _loop_point_in_direction(center: Vector2, dir: Vector2, loop: PackedVector2Array, fallback_distance: float) -> Vector2:
	var best := center + dir * fallback_distance
	var best_score := -INF
	for point in loop:
		var delta := point - center
		if delta.length() < 0.001:
			continue
		var score := delta.normalized().dot(dir.normalized()) * 1000.0 - absf(delta.length() - fallback_distance) * 0.01
		if score > best_score:
			best_score = score
			best = point
	return best


func _clamp_path_to_coastal_clearance(path: PackedVector2Array, fallback: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in path:
		out.append(_clamp_point_to_coastal_clearance(point, fallback))
	return out


func _clamp_point_to_coastal_clearance(point: Vector2, fallback: Vector2) -> Vector2:
	if _point_has_coastal_clearance(point):
		return point
	var candidate := point
	for _i in range(maxi(_params.coastal_bind_iterations, 1) * 2):
		candidate = candidate.lerp(fallback, clampf(_params.coastal_bind_step_ratio, 0.01, 0.9))
		if _point_has_coastal_clearance(candidate):
			return candidate
	return _clamp_point_to_land(fallback, point)


func _clamp_path_to_land(path: PackedVector2Array, fallback: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in path:
		out.append(_clamp_point_to_land(point, fallback))
	return out


func _clamp_point_to_land(point: Vector2, fallback: Vector2) -> Vector2:
	if _point_is_on_land(point):
		return point
	var candidate := point
	for _i in range(maxi(_params.coastal_bind_iterations, 1)):
		candidate = candidate.lerp(fallback, clampf(_params.coastal_bind_step_ratio, 0.01, 0.9))
		if _point_is_on_land(candidate):
			return candidate
	return fallback


func _point_has_coastal_clearance(point: Vector2) -> bool:
	if not _point_is_on_land(point):
		return false
	var clearance: float = maxf(_params.coastal_clearance_px, 0.0)
	if clearance <= 0.0:
		return true
	for i in range(12):
		var sample := point + Vector2.RIGHT.rotated(TAU * float(i) / 12.0) * clearance
		if not _point_is_on_land(sample):
			return false
	return true


func _land_edge_point(start: Vector2, dir: Vector2) -> Vector2:
	var current := start
	var step := maxf(_hex_size * 0.04, 10.0)
	for i in range(1, 40):
		var candidate := start + dir.normalized() * step * float(i)
		if not _point_is_on_land(candidate):
			return current
		current = candidate
	return current


func _sea_direction_from_point(point: Vector2) -> Vector2:
	var best_dir := Vector2.RIGHT
	var best_distance := INF
	for i in range(12):
		var dir := Vector2.RIGHT.rotated(TAU * float(i) / 12.0)
		var edge := _land_edge_point(point, dir)
		var distance := point.distance_to(edge)
		if distance < best_distance:
			best_distance = distance
			best_dir = dir
	return best_dir.normalized()


func _wobbly_segment(start: Vector2, target: Vector2, dir: Vector2) -> PackedVector2Array:
	var length := start.distance_to(target)
	if length < MIN_SECTION_LENGTH:
		return PackedVector2Array([start, target])
	var final_dir := (target - start).normalized()
	if final_dir.is_zero_approx():
		final_dir = dir.normalized()
	var perp := final_dir.rotated(PI / 2.0)
	var bend := length * _params.curve_wobble_ratio * _rng.randf_range(-1.0, 1.0)
	var segment := PackedVector2Array([
		start,
		start + final_dir * length * 0.34 + perp * bend,
		target - final_dir * length * 0.34 - perp * bend,
		target,
	])
	return sample_bezier(segment, CURVE_STEPS)


func _dogleg_segment(start: Vector2, target: Vector2, dir: Vector2) -> PackedVector2Array:
	var length := start.distance_to(target)
	if length < MIN_SECTION_LENGTH:
		return PackedVector2Array([start, target])
	var final_dir := (target - start).normalized()
	if final_dir.is_zero_approx():
		final_dir = dir.normalized()
	var side := final_dir.rotated(PI / 2.0)
	var sign_value := -1.0 if _rng.randf() < 0.5 else 1.0
	var waypoint := (start + target) * 0.5 + side * sign_value * length * _params.core_connector_dogleg_ratio
	waypoint = _clamp_point_to_land(waypoint, (start + target) * 0.5)

	var first := _wobbly_segment(start, waypoint, waypoint - start)
	var second := _wobbly_segment(waypoint, target, target - waypoint)
	var out := PackedVector2Array()
	for point in first:
		out.append(point)
	for i in range(1, second.size()):
		out.append(second[i])
	return out


func _cyclic_distance(a: int, b: int, count: int) -> int:
	if count <= 0:
		return 0
	var delta: int = absi(a - b)
	return mini(delta, count - delta)


func _wobble_loop(loop: PackedVector2Array, centroid: Vector2, amplitude: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(loop.size()):
		var point: Vector2 = loop[i]
		var radial := point - centroid
		if radial.length() < 0.001:
			out.append(point)
			continue
		var wave := sin(float(i) * 1.73 + float(_params.rng_seed % 997) * 0.017)
		var jitter := _rng.randf_range(-0.35, 0.35)
		var offset_dir := radial.normalized()
		var offset := amplitude * (wave * 0.65 + jitter)
		var candidate := point + offset_dir * offset
		if not _point_is_on_land(candidate):
			candidate = point - offset_dir * absf(offset)
		if not _point_is_on_land(candidate):
			candidate = point
		out.append(candidate)
	return out


func _outward_normal_at_loop(loop: PackedVector2Array, index: int, centroid: Vector2) -> Vector2:
	var count := loop.size()
	var previous: Vector2 = loop[(index - 1 + count) % count]
	var next: Vector2 = loop[(index + 1) % count]
	var tangent := (next - previous).normalized()
	var radial := (loop[index] - centroid).normalized()
	if tangent.is_zero_approx() or radial.is_zero_approx():
		return radial
	var normal := Vector2(-tangent.y, tangent.x).normalized()
	if normal.dot(radial) < 0.0:
		normal = -normal
	return normal


func _path_stays_on_land(path: PackedVector2Array) -> bool:
	for point in path:
		if not _point_is_on_land(point):
			return false
	return true


func _point_is_on_land(point: Vector2) -> bool:
	var map_coord := terrain_layer.local_to_map(point)
	var tile_coord := terrain_layer.tile_coord_for_map_coord(map_coord)
	if not terrain_layer.tiles.has(tile_coord):
		return false
	var tile: Dictionary = terrain_layer.tiles[tile_coord]
	var tile_type := str(tile.get("type", "")).strip_edges()
	return tile_type != "" and tile_type != "sea" and tile_type != "deep_sea"


func _filtered_path(path: PackedVector2Array) -> PackedVector2Array:
	if path.size() <= 2:
		return path
	var filtered := PackedVector2Array([path[0]])
	var last := path[0]
	for i in range(1, path.size() - 1):
		if last.distance_to(path[i]) >= MIN_SECTION_LENGTH:
			filtered.append(path[i])
			last = path[i]
	if filtered[filtered.size() - 1].distance_to(path[path.size() - 1]) >= MIN_SECTION_LENGTH:
		filtered.append(path[path.size() - 1])
	elif filtered.size() == 1:
		filtered.append(path[path.size() - 1])
	else:
		filtered[filtered.size() - 1] = path[path.size() - 1]
	return filtered


func _path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	return total


func _estimate_hex_size(sample_cell: Vector2i) -> float:
	var corners := _hex_corners_world(sample_cell)
	return corners[0].distance_to(corners[1]) * 0.5


func _neighbor_offsets_for_coord(coord: Vector2i) -> Array[Vector2i]:
	var is_odd_column := coord.x % 2 == 1
	if is_odd_column:
		return [
			Vector2i(0, -1),
			Vector2i(1, 0),
			Vector2i(1, 1),
			Vector2i(0, 1),
			Vector2i(-1, 1),
			Vector2i(-1, 0),
		]
	return [
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
		Vector2i(-1, -1),
	]


func _neighbor_offset_for_side(coord: Vector2i, side: int) -> Vector2i:
	var offsets := _neighbor_offsets_for_coord(coord)
	return offsets[wrapi(side, 0, offsets.size())]


func _sort_tile_coord(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)
