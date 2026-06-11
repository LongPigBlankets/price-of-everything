extends RefCounted
class_name RoadPlanner

const ROAD_TEMPLATES_PATH := "res://data/road_templates.json"

const ROAD_WIDTH := 5.0
const ARTERIAL_WIDTH := 5.0
const ROAD_GRID_WIDTH := 5.0
const CURVE_STEPS := 16
const TILE_CENTER := Vector2(270, 240)
const SUBTILE_SIZE := 20.0
const GRID_SIZE := Vector2(60, 40)
const GRID_CELLS := Vector2i(3, 2)
const ROAD_EDGE_OFFSET := 20.0
const MIN_RIVER_ANCHOR_DISTANCE := 36.0
const MIN_RIVER_PARALLEL_DISTANCE := 30.0
const MAX_RIVER_CROSSINGS_PER_TILE := 2
const BRIDGE_LENGTH := 30.0
const BRIDGE_WIDTH := 5.0
const ROAD_RIVER_HUG_DISTANCE := 42.0
const RIVER_EXIT_STOP_DISTANCE := 40.0
const RIVER_ROAD_END_TRIM := 60.0
const EXISTING_BRIDGE_MAX_DISTANCE_MULTIPLIER := 2.25
const SAME_BANK_DETOUR_ATTEMPTS := 4
const JUNCTION_RADIUS := 5.0
const GRAPH_NODE_MERGE_DISTANCE := 12.0
const GRAPH_EDGE_SNAP_DISTANCE := 90.0
const OPTIONAL_HSM_CONNECT_DISTANCE := 180.0
const REQUIRED_HSM_CONNECT_DISTANCE := 600.0
const REDUNDANT_HSM_CONNECT_DISTANCE := 45.0
const SHORT_SPUR_PRUNE_LENGTH := 35.0
const DUPLICATE_EDGE_DISTANCE := 14.0
const SPARSE_MAX_EXITS := 3
const DENSE_MAX_EXITS := 4
const DENSE_LOOP_MIN_INSET := 20.0
const DENSE_LOOP_MAX_INSET := 120.0
const DENSE_LOOP_BASE_INSET := 55.0
const DENSE_LOOP_WAVE_LIMIT := 22.0
const DENSE_GRID_X_OFFSETS: Array[float] = [-160.0, 0.0, 160.0]
const DENSE_GRID_Y_OFFSETS: Array[float] = [-120.0, 0.0, 120.0]
const DENSE_GRID_CONNECTOR_BEND := 0.04
const DENSE_GRID_CONNECTOR_MAX_BEND := 10.0
const DENSE_GRID_RIVER_STUB_TRIM := 22.0
const FORCED_HSM_TOUCH_DISTANCE := 18.0
const CITY_BOUNDARY_SAMPLE_SPACING := 34.0
const CITY_BOUNDARY_DEFAULT_INSET := 60.0
const CITY_BOUNDARY_WOBBLE_LIMIT := 18.0
const CITY_LOOP_RAY_COUNT := 84
const CITY_EROSION_GRID_STEP := 12.0
const CITY_CONTOUR_MIN_INSET := 24.0
const CITY_CONTOUR_SMOOTH_PASSES := 3
const CITY_CIRCLE_SEARCH_STEP := 10.0
const CITY_CIRCLE_MIN_RADIUS := 16.0
const CITY_CIRCLE_SEGMENTS := 144
const CITY_CIRCLE_RAY_STEPS := 48
const CITY_CIRCLE_RAY_REFINE_STEPS := 10
const CITY_SHAPE_VARIANT_COUNT := 5
const CITY_SHAPE_VARIANTS := [
	{"radius_scale": 1.00, "wobble_scale": 0.30, "center_lerp": 0.00},
	{"radius_scale": 0.94, "wobble_scale": 0.55, "center_lerp": 0.12},
	{"radius_scale": 0.88, "wobble_scale": 0.85, "center_lerp": 0.24},
	{"radius_scale": 0.82, "wobble_scale": 0.45, "center_lerp": -0.10},
	{"radius_scale": 0.76, "wobble_scale": 0.70, "center_lerp": 0.36},
]
const POINT_TENSIONS: Array[float] = [0.34, 0.22, 0.39, 0.27, 0.46]

const HSM_POINTS := {
	"HSM1": Vector2(270, 0),
	"HSM2": Vector2(472.5, 120),
	"HSM3": Vector2(472.5, 360),
	"HSM4": Vector2(270, 480),
	"HSM5": Vector2(67.5, 360),
	"HSM6": Vector2(67.5, 120),
}

const HSM_ORDER := ["HSM1", "HSM2", "HSM3", "HSM4", "HSM5", "HSM6"]
const OPPOSITE_HSM := {
	"HSM1": "HSM4",
	"HSM2": "HSM5",
	"HSM3": "HSM6",
	"HSM4": "HSM1",
	"HSM5": "HSM2",
	"HSM6": "HSM3",
}

var terrain_layer
var _shared_anchor_cache: Dictionary = {}
var _road_templates: Dictionary = {}
var _city_plan_cache: Dictionary = {}
static var city_shape_variant_override := -1
static var _city_valid_point_cache: Dictionary = {}

static func cycle_city_shape_variant(default_variant: int = 0) -> int:
	city_shape_variant_override = (current_city_shape_variant(default_variant) + 1) % CITY_SHAPE_VARIANT_COUNT
	return city_shape_variant_override

static func current_city_shape_variant(default_variant: int = 0) -> int:
	if city_shape_variant_override >= 0:
		return city_shape_variant_override
	return clampi(default_variant, 0, CITY_SHAPE_VARIANT_COUNT - 1)

func _init(p_terrain_layer) -> void:
	terrain_layer = p_terrain_layer
	_road_templates = _load_road_templates()

func build_tile_plan(tile_coord: Vector2i) -> Dictionary:
	var plan: Dictionary = {"edges": [], "bridges": [], "junctions": []}
	if terrain_layer == null or not terrain_layer.tiles.has(tile_coord):
		return plan
	var tile_data: Dictionary = terrain_layer.tiles[tile_coord]
	if not _tile_has_roads(tile_data):
		return plan

	var road_hsms: Array[String] = _road_hsms_for_tile(tile_coord)
	var city_id: String = _tile_city_id(tile_data)
	if city_id != "":
		return _build_city_plan(city_id)

	var river_path: PackedVector2Array = _river_path_for_tile(tile_coord)
	var road_type: String = _road_type_for_tile(tile_data, road_hsms)
	var is_dense: bool = _road_is_dense(tile_data, road_hsms)
	var visible_hsms: Array[String] = _select_visible_road_hsms(road_hsms, DENSE_MAX_EXITS if is_dense else SPARSE_MAX_EXITS)
	if not river_path.is_empty() and visible_hsms.size() >= 1 and not _road_type_is_river_safe(road_type):
		var river_plan: Dictionary = {}
		if is_dense and visible_hsms.size() >= 2:
			river_plan = _build_dense_grid_river_plan(tile_coord, visible_hsms, river_path)
		else:
			river_plan = _build_river_road_plan(tile_coord, visible_hsms, river_path)
		_validate_required_hsms_connected(river_plan, tile_coord, visible_hsms, river_path)
		if is_dense:
			_force_hsm_connectivity(river_plan, tile_coord, visible_hsms, river_path)
		_add_hsm_edge_stubs(river_plan, tile_coord, visible_hsms)
		_sanitize_plan_crossings(river_plan, river_path)
		return river_plan
	if is_dense and visible_hsms.size() >= 1:
		var dense_plan: Dictionary = _build_dense_grid_plan(tile_coord, visible_hsms)
		_force_hsm_connectivity(dense_plan, tile_coord, visible_hsms, river_path)
		_add_hsm_edge_stubs(dense_plan, tile_coord, visible_hsms)
		return dense_plan
	if visible_hsms.size() >= 1:
		var simple_plan: Dictionary = _build_simple_road_plan(tile_coord, visible_hsms)
		_add_hsm_edge_stubs(simple_plan, tile_coord, visible_hsms)
		return simple_plan
	if road_type != "":
		var template_plan: Dictionary = _build_template_plan(tile_coord, road_type, visible_hsms, river_path)
		if not template_plan.is_empty():
			return template_plan

	var graph: Dictionary = _new_graph(river_path)
	var hsm_nodes: Dictionary = _add_hsm_nodes(graph, tile_coord, visible_hsms)
	if visible_hsms.size() == 0:
		_add_local_grid_to_graph(graph, tile_coord, visible_hsms)
	elif visible_hsms.size() == 1:
		_add_local_grid_to_graph(graph, tile_coord, visible_hsms)
	else:
		_add_primary_spine(graph, tile_coord, visible_hsms, hsm_nodes)
		_add_river_parallel_road_if_needed(graph, river_path)
		_connect_remaining_hsms_to_graph(graph, visible_hsms, hsm_nodes)
	_prune_short_dead_ends(graph)
	_prune_duplicate_edges(graph)
	plan = _export_graph_to_plan(graph)
	_sanitize_plan_crossings(plan, river_path)
	return plan

func road_segments_for_tile_local(tile_coord: Vector2i) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var center: Vector2 = _tile_world_center(tile_coord)
	var plan: Dictionary = build_tile_plan(tile_coord)
	var edges: Array = plan.get("edges", [])
	for edge in edges:
		var path: PackedVector2Array = edge["path"]
		var width: float = float(edge.get("width", ROAD_WIDTH))
		for i in range(path.size() - 1):
			segments.append({
				"start": path[i] - center + TILE_CENTER,
				"end": path[i + 1] - center + TILE_CENTER,
				"width": width,
			})
	return segments

func _tile_city_id(tile_data: Dictionary) -> String:
	return str(tile_data.get("city_id", "")).strip_edges()

func _city_data(city_id: String) -> Dictionary:
	if terrain_layer == null:
		return {}
	var registry: Dictionary = terrain_layer.cities
	if not registry.has(city_id):
		return {}
	var city_data: Dictionary = registry[city_id]
	return city_data

func _city_member_tiles(city_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var city_data: Dictionary = _city_data(city_id)
	var member_ids: Array = city_data.get("member_tiles", [])
	for tile_id_data in member_ids:
		var tile_id: String = str(tile_id_data)
		if terrain_layer.has_method("id_to_coord"):
			var coord: Vector2i = terrain_layer.id_to_coord(tile_id)
			if coord != Vector2i(-1, -1) and terrain_layer.tiles.has(coord) and not result.has(coord):
				result.append(coord)

	for coord_data in terrain_layer.tiles:
		var coord: Vector2i = coord_data
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		if _tile_city_id(tile_data) == city_id and not result.has(coord):
			result.append(coord)

	result.sort_custom(_sort_tile_coord)
	return result

func _build_city_plan(city_id: String) -> Dictionary:
	if _city_plan_cache.has(city_id):
		var cached_plan: Dictionary = _city_plan_cache[city_id]
		return cached_plan

	var plan: Dictionary = {"edges": [], "bridges": [], "junctions": []}
	var members: Array[Vector2i] = _city_member_tiles(city_id)
	if members.is_empty():
		push_warning("City '%s' has no member tiles." % city_id)
		_city_plan_cache[city_id] = plan
		return plan

	var beltway: PackedVector2Array = _city_beltway_path(city_id, members)
	if beltway.size() >= 2:
		_add_direct_edge(plan, beltway, ROAD_WIDTH, "city_beltway")
		_add_city_boundary_connectors(plan, city_id, members, beltway)
		_add_city_interior_streets(plan, city_id, members, beltway)
	_city_plan_cache[city_id] = plan
	return plan

func _city_beltway_path(city_id: String, members: Array[Vector2i]) -> PackedVector2Array:
	var city_data: Dictionary = _city_data(city_id)
	var hull: PackedVector2Array = _city_convex_hull_corners(members)
	var boundary_edges: Array = _city_boundary_edges(members)
	if hull.size() < 3:
		return PackedVector2Array()
	var inset: float = float(city_data.get("inset", CITY_BOUNDARY_DEFAULT_INSET))
	var wobble_amplitude: float = float(city_data.get("wobble_amplitude", 7.0))
	var default_variant: int = int(city_data.get("shape_variant", 0))
	var variant_index: int = current_city_shape_variant(default_variant)
	return _city_largest_inset_circle_path(hull, members, boundary_edges, inset, wobble_amplitude, _city_seed(city_id, members), variant_index)

func _city_largest_inset_circle_path(
	bounds: PackedVector2Array,
	members: Array[Vector2i],
	boundary_edges: Array,
	inset: float,
	wobble_amplitude: float,
	seed: int,
	variant_index: int
) -> PackedVector2Array:
	var best: Dictionary = _largest_city_circle_candidate(bounds)
	if best.is_empty():
		return PackedVector2Array()
	var center: Vector2 = best["point"]
	var boundary_distance: float = float(best["distance"])
	var variant: Dictionary = CITY_SHAPE_VARIANTS[clampi(variant_index, 0, CITY_SHAPE_VARIANT_COUNT - 1)]
	var eroded_center: Vector2 = _largest_eroded_city_point(members, boundary_edges, inset)
	center = center.lerp(eroded_center, float(variant.get("center_lerp", 0.0)))
	var radius: float = (boundary_distance - inset) * float(variant.get("radius_scale", 1.0))
	if radius < CITY_CIRCLE_MIN_RADIUS:
		return PackedVector2Array()

	var path: PackedVector2Array = PackedVector2Array()
	for i in range(CITY_CIRCLE_SEGMENTS):
		var angle: float = TAU * float(i) / float(CITY_CIRCLE_SEGMENTS)
		var direction := Vector2(cos(angle), sin(angle))
		var wave: float = _city_boundary_wave(float(i) * 23.0 + float(variant_index) * 53.0, seed + variant_index * 97, wobble_amplitude * float(variant.get("wobble_scale", 1.0)))
		var desired_point: Vector2 = center + direction * maxf(CITY_CIRCLE_MIN_RADIUS, radius + wave)
		path.append(_nearest_eroded_city_point(desired_point, members, boundary_edges, inset))
	if path.size() < 3:
		return PackedVector2Array()
	path.append(path[0])
	var dense_path: PackedVector2Array = _densify_closed_path(path, 12.0)
	var smoothed: PackedVector2Array = _smooth_closed_path(dense_path, 1)
	return _project_path_to_eroded_city(smoothed, members, boundary_edges, inset)

func _max_city_ray_radius(
	center: Vector2,
	direction: Vector2,
	max_radius: float,
	members: Array[Vector2i],
	boundary_edges: Array,
	inset: float
) -> float:
	var last_valid := 0.0
	var first_invalid := max_radius
	for step in range(1, CITY_CIRCLE_RAY_STEPS + 1):
		var distance: float = max_radius * float(step) / float(CITY_CIRCLE_RAY_STEPS)
		var point: Vector2 = center + direction * distance
		if _point_inside_eroded_city(point, members, boundary_edges, inset):
			last_valid = distance
			continue
		first_invalid = distance
		break
	for _i in range(CITY_CIRCLE_RAY_REFINE_STEPS):
		var midpoint: float = (last_valid + first_invalid) * 0.5
		var point: Vector2 = center + direction * midpoint
		if _point_inside_eroded_city(point, members, boundary_edges, inset):
			last_valid = midpoint
		else:
			first_invalid = midpoint
	return last_valid

func _largest_eroded_city_point(members: Array[Vector2i], boundary_edges: Array, inset: float) -> Vector2:
	var best_point: Vector2 = _city_center_world(members)
	var best_distance := -1.0
	for point in _eroded_city_points(members, boundary_edges, inset):
		var distance: float = _distance_to_city_boundary(point, boundary_edges)
		if distance > best_distance:
			best_distance = distance
			best_point = point
	return best_point

func _nearest_eroded_city_point(point: Vector2, members: Array[Vector2i], boundary_edges: Array, inset: float) -> Vector2:
	if _point_inside_eroded_city(point, members, boundary_edges, inset):
		return point
	var best_point: Vector2 = _largest_eroded_city_point(members, boundary_edges, inset)
	var best_distance: float = point.distance_squared_to(best_point)
	for candidate in _eroded_city_points(members, boundary_edges, inset):
		var distance: float = point.distance_squared_to(candidate)
		if distance < best_distance:
			best_distance = distance
			best_point = candidate

	var refine_step: float = CITY_CIRCLE_SEARCH_STEP * 0.5
	while refine_step >= 1.5:
		var improved := true
		while improved:
			improved = false
			for offset in [
				Vector2(refine_step, 0.0),
				Vector2(-refine_step, 0.0),
				Vector2(0.0, refine_step),
				Vector2(0.0, -refine_step),
				Vector2(refine_step, refine_step),
				Vector2(refine_step, -refine_step),
				Vector2(-refine_step, refine_step),
				Vector2(-refine_step, -refine_step),
			]:
				var candidate: Vector2 = best_point + offset
				if not _point_inside_eroded_city(candidate, members, boundary_edges, inset):
					continue
				var distance: float = point.distance_squared_to(candidate)
				if distance < best_distance:
					best_distance = distance
					best_point = candidate
					improved = true
		refine_step *= 0.5
	return best_point

func _eroded_city_points(members: Array[Vector2i], boundary_edges: Array, inset: float) -> PackedVector2Array:
	var cache_key: String = _city_points_cache_key(members, inset)
	if _city_valid_point_cache.has(cache_key):
		return _city_valid_point_cache[cache_key]
	var result: PackedVector2Array = PackedVector2Array()
	var rect: Rect2 = _city_member_world_rect(members)
	var y: float = rect.position.y
	while y <= rect.end.y:
		var x: float = rect.position.x
		while x <= rect.end.x:
			var point := Vector2(x, y)
			if _point_inside_eroded_city(point, members, boundary_edges, inset):
				result.append(point)
			x += CITY_CIRCLE_SEARCH_STEP
		y += CITY_CIRCLE_SEARCH_STEP
	_city_valid_point_cache[cache_key] = result
	return result

func _city_points_cache_key(members: Array[Vector2i], inset: float) -> String:
	var parts: Array[String] = []
	for member in members:
		parts.append("%d_%d" % [member.x, member.y])
	parts.sort()
	return "%s:%d" % ["|".join(parts), roundi(inset * 10.0)]

func _project_path_to_eroded_city(
	path: PackedVector2Array,
	members: Array[Vector2i],
	boundary_edges: Array,
	inset: float
) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for point in path:
		var projected: Vector2 = _nearest_eroded_city_point(point, members, boundary_edges, inset)
		if result.size() == 0 or projected.distance_to(result[result.size() - 1]) > 1.0:
			result.append(projected)
	if result.size() > 1:
		result[result.size() - 1] = result[0]
	return result

func _densify_closed_path(path: PackedVector2Array, max_spacing: float) -> PackedVector2Array:
	if path.size() < 2:
		return path
	var result: PackedVector2Array = PackedVector2Array()
	for i in range(path.size() - 1):
		var start: Vector2 = path[i]
		var end: Vector2 = path[i + 1]
		var distance: float = start.distance_to(end)
		var steps: int = maxi(1, int(ceil(distance / max_spacing)))
		for step in range(steps):
			result.append(start.lerp(end, float(step) / float(steps)))
	result.append(result[0])
	return result

func _largest_city_circle_candidate(bounds: PackedVector2Array) -> Dictionary:
	var rect: Rect2 = _polygon_world_rect(bounds)
	var best_point: Vector2 = _polygon_centroid(bounds)
	var best_distance: float = _city_circle_candidate_distance(best_point, bounds)

	var y: float = rect.position.y
	while y <= rect.end.y:
		var x: float = rect.position.x
		while x <= rect.end.x:
			var point := Vector2(x, y)
			var distance: float = _city_circle_candidate_distance(point, bounds)
			if distance > best_distance:
				best_distance = distance
				best_point = point
			x += CITY_CIRCLE_SEARCH_STEP
		y += CITY_CIRCLE_SEARCH_STEP

	var refine_step: float = CITY_CIRCLE_SEARCH_STEP * 0.5
	while refine_step >= 1.5:
		var improved := true
		while improved:
			improved = false
			for offset in [
				Vector2(refine_step, 0.0),
				Vector2(-refine_step, 0.0),
				Vector2(0.0, refine_step),
				Vector2(0.0, -refine_step),
				Vector2(refine_step, refine_step),
				Vector2(refine_step, -refine_step),
				Vector2(-refine_step, refine_step),
				Vector2(-refine_step, -refine_step),
			]:
				var candidate: Vector2 = best_point + offset
				var distance: float = _city_circle_candidate_distance(candidate, bounds)
				if distance > best_distance:
					best_distance = distance
					best_point = candidate
					improved = true
		refine_step *= 0.5

	if best_distance <= 0.0:
		return {}
	return {"point": best_point, "distance": best_distance}

func _city_circle_candidate_distance(point: Vector2, bounds: PackedVector2Array) -> float:
	if not _point_inside_polygon(point, bounds):
		return -1.0
	return _distance_to_polygon_boundary(point, bounds)

func _city_convex_hull_corners(members: Array[Vector2i]) -> PackedVector2Array:
	var points: Array[Vector2] = []
	for tile_coord in members:
		for corner in _hex_corners_world(tile_coord):
			points.append(corner)
	return _convex_hull(points)

func _convex_hull(points: Array[Vector2]) -> PackedVector2Array:
	var unique: Array[Vector2] = []
	var seen: Dictionary = {}
	for point in points:
		var key: String = _point_key(point)
		if seen.has(key):
			continue
		seen[key] = true
		unique.append(point)
	if unique.size() < 3:
		var fallback: PackedVector2Array = PackedVector2Array()
		for point in unique:
			fallback.append(point)
		return fallback
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
	var hull: PackedVector2Array = PackedVector2Array()
	for point in lower:
		hull.append(point)
	for point in upper:
		hull.append(point)
	return hull

func _sort_points_xy(a: Vector2, b: Vector2) -> bool:
	return a.x < b.x or (is_equal_approx(a.x, b.x) and a.y < b.y)

func _polygon_world_rect(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var min_pos: Vector2 = points[0]
	var max_pos: Vector2 = points[0]
	for point in points:
		min_pos.x = minf(min_pos.x, point.x)
		min_pos.y = minf(min_pos.y, point.y)
		max_pos.x = maxf(max_pos.x, point.x)
		max_pos.y = maxf(max_pos.y, point.y)
	return Rect2(min_pos, max_pos - min_pos)

func _polygon_centroid(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for point in points:
		total += point
	return total / float(points.size())

func _distance_to_polygon_boundary(point: Vector2, polygon: PackedVector2Array) -> float:
	var best := 1.0e20
	for i in range(polygon.size()):
		var start: Vector2 = polygon[i]
		var end: Vector2 = polygon[(i + 1) % polygon.size()]
		var closest: Vector2 = _closest_point_on_segment(point, start, end)
		best = minf(best, point.distance_to(closest))
	return best

func _city_member_world_rect(members: Array[Vector2i]) -> Rect2:
	var first_corners: PackedVector2Array = _hex_corners_world(members[0])
	var first: Vector2 = first_corners[0]
	var min_pos := first
	var max_pos := first
	for tile_coord in members:
		for corner in _hex_corners_world(tile_coord):
			min_pos.x = minf(min_pos.x, corner.x)
			min_pos.y = minf(min_pos.y, corner.y)
			max_pos.x = maxf(max_pos.x, corner.x)
			max_pos.y = maxf(max_pos.y, corner.y)
	return Rect2(min_pos, max_pos - min_pos)

func _city_boundary_edges(members: Array[Vector2i]) -> Array:
	var boundary_edges: Dictionary = {}
	for tile_coord in members:
		var corners: PackedVector2Array = _hex_corners_world(tile_coord)
		for i in range(corners.size()):
			var start: Vector2 = corners[i]
			var end: Vector2 = corners[(i + 1) % corners.size()]
			var edge_key: String = _undirected_point_pair_key(start, end)
			if boundary_edges.has(edge_key):
				boundary_edges.erase(edge_key)
				continue
			var start_key: String = _point_key(start)
			var end_key: String = _point_key(end)
			boundary_edges[edge_key] = {
				"start": start,
				"end": end,
				"start_key": start_key,
				"end_key": end_key,
			}
	return boundary_edges.values()

func _city_eroded_loop_path(
	members: Array[Vector2i],
	boundary_edges: Array,
	requested_inset: float,
	wobble_amplitude: float,
	seed: int
) -> PackedVector2Array:
	var inset: float = requested_inset
	var contour_data: Dictionary = {}
	while inset >= CITY_CONTOUR_MIN_INSET:
		contour_data = _city_eroded_contour_data(members, boundary_edges, inset)
		if not contour_data.is_empty():
			break
		inset -= 8.0
	if contour_data.is_empty():
		return _city_boundary_fallback_loop(members, boundary_edges, requested_inset, wobble_amplitude, seed)

	var loop: PackedVector2Array = contour_data["loop"]
	var center: Vector2 = contour_data["center"]
	var wiggled: PackedVector2Array = _wiggle_city_contour(loop, center, members, boundary_edges, inset, wobble_amplitude, seed)
	var smoothed: PackedVector2Array = _smooth_closed_path(wiggled, CITY_CONTOUR_SMOOTH_PASSES)
	return _pull_path_inside_eroded_city(smoothed, center, members, boundary_edges, inset)

func _city_boundary_fallback_loop(
	members: Array[Vector2i],
	boundary_edges: Array,
	requested_inset: float,
	wobble_amplitude: float,
	seed: int
) -> PackedVector2Array:
	var boundary: PackedVector2Array = _city_directed_boundary_loop(boundary_edges)
	if boundary.size() < 3:
		boundary = _city_union_boundary_path(members)
	if boundary.size() < 3:
		return PackedVector2Array()
	var fallback_inset: float = maxf(CITY_CONTOUR_MIN_INSET, requested_inset * 0.72)
	var loop: PackedVector2Array = _city_inset_wiggled_boundary_path(boundary, members, fallback_inset, wobble_amplitude, seed)
	var smoothed: PackedVector2Array = _smooth_closed_path(loop, CITY_CONTOUR_SMOOTH_PASSES)
	return _pull_path_inside_eroded_city(smoothed, _city_center_world(members), members, boundary_edges, fallback_inset)

func _city_eroded_contour_data(members: Array[Vector2i], boundary_edges: Array, inset: float) -> Dictionary:
	var cells: Dictionary = _city_eroded_cells(members, boundary_edges, inset)
	if cells.is_empty():
		return {}
	var component: Dictionary = _largest_city_cell_component(cells, members)
	if component.is_empty():
		return {}
	var loop: PackedVector2Array = _city_component_contour_loop(component)
	if loop.size() < 3:
		return {}
	return {
		"loop": loop,
		"center": _city_cell_component_center(component),
	}

func _city_eroded_cells(members: Array[Vector2i], boundary_edges: Array, inset: float) -> Dictionary:
	var cells: Dictionary = {}
	var rect: Rect2 = _city_member_world_rect(members)
	var origin: Vector2 = rect.position - Vector2(CITY_EROSION_GRID_STEP, CITY_EROSION_GRID_STEP)
	var y: float = origin.y
	var row := 0
	while y <= rect.end.y:
		var x: float = origin.x
		var col := 0
		while x <= rect.end.x:
			var center := Vector2(x + CITY_EROSION_GRID_STEP * 0.5, y + CITY_EROSION_GRID_STEP * 0.5)
			if _point_inside_eroded_city(center, members, boundary_edges, inset):
				var key: String = _cell_key(Vector2i(col, row))
				cells[key] = {
					"coord": Vector2i(col, row),
					"origin": Vector2(x, y),
					"center": center,
				}
			x += CITY_EROSION_GRID_STEP
			col += 1
		y += CITY_EROSION_GRID_STEP
		row += 1
	return cells

func _largest_city_cell_component(cells: Dictionary, members: Array[Vector2i]) -> Dictionary:
	var visited: Dictionary = {}
	var best_covering: Dictionary = {}
	for key_data in cells.keys():
		var key: String = str(key_data)
		if visited.has(key):
			continue
		var component: Dictionary = {}
		var queue: Array[String] = [key]
		visited[key] = true
		while not queue.is_empty():
			var current_key: String = queue.pop_front()
			component[current_key] = cells[current_key]
			var coord: Vector2i = cells[current_key]["coord"]
			for offset in [
				Vector2i(1, 0),
				Vector2i(-1, 0),
				Vector2i(0, 1),
				Vector2i(0, -1),
				Vector2i(1, 1),
				Vector2i(1, -1),
				Vector2i(-1, 1),
				Vector2i(-1, -1),
			]:
				var neighbor_key: String = _cell_key(coord + offset)
				if not cells.has(neighbor_key) or visited.has(neighbor_key):
					continue
				visited[neighbor_key] = true
				queue.append(neighbor_key)
		if _city_cell_component_covers_members(component, members) and component.size() > best_covering.size():
			best_covering = component
	return best_covering if not best_covering.is_empty() else {}

func _city_cell_component_covers_members(component: Dictionary, members: Array[Vector2i]) -> bool:
	var covered: Dictionary = {}
	for cell_data in component.values():
		var cell: Dictionary = cell_data
		var center: Vector2 = cell["center"]
		for member in members:
			if covered.has(member):
				continue
			if _point_inside_polygon(center, _hex_corners_world(member)):
				covered[member] = true
	for member in members:
		if not covered.has(member):
			return false
	return true

func _city_component_contour_loop(component: Dictionary) -> PackedVector2Array:
	var directed_edges: Array = []
	for cell_data in component.values():
		var cell: Dictionary = cell_data
		var coord: Vector2i = cell["coord"]
		var origin: Vector2 = cell["origin"]
		var top_left := origin
		var top_right := origin + Vector2(CITY_EROSION_GRID_STEP, 0.0)
		var bottom_right := origin + Vector2(CITY_EROSION_GRID_STEP, CITY_EROSION_GRID_STEP)
		var bottom_left := origin + Vector2(0.0, CITY_EROSION_GRID_STEP)
		if not component.has(_cell_key(coord + Vector2i(0, -1))):
			directed_edges.append({"start": top_left, "end": top_right})
		if not component.has(_cell_key(coord + Vector2i(1, 0))):
			directed_edges.append({"start": top_right, "end": bottom_right})
		if not component.has(_cell_key(coord + Vector2i(0, 1))):
			directed_edges.append({"start": bottom_right, "end": bottom_left})
		if not component.has(_cell_key(coord + Vector2i(-1, 0))):
			directed_edges.append({"start": bottom_left, "end": top_left})
	return _largest_directed_edge_loop(directed_edges)

func _largest_directed_edge_loop(directed_edges: Array) -> PackedVector2Array:
	var outgoing: Dictionary = {}
	for i in range(directed_edges.size()):
		var edge: Dictionary = directed_edges[i]
		var edge_start: Vector2 = edge["start"]
		var start_key: String = _point_key(edge_start)
		if not outgoing.has(start_key):
			outgoing[start_key] = []
		var indexes: Array = outgoing[start_key]
		indexes.append(i)
		outgoing[start_key] = indexes

	var used: Dictionary = {}
	var best_loop: PackedVector2Array = PackedVector2Array()
	for i in range(directed_edges.size()):
		if used.has(i):
			continue
		var loop: PackedVector2Array = PackedVector2Array()
		var current_index := i
		for _guard in range(directed_edges.size() + 2):
			if used.has(current_index):
				break
			used[current_index] = true
			var edge: Dictionary = directed_edges[current_index]
			var edge_start: Vector2 = edge["start"]
			var edge_end: Vector2 = edge["end"]
			loop.append(edge_start)
			var end_key: String = _point_key(edge_end)
			var next_indexes: Array = outgoing.get(end_key, [])
			if next_indexes.is_empty():
				break
			var next_index := -1
			for candidate_data in next_indexes:
				var candidate: int = int(candidate_data)
				if not used.has(candidate):
					next_index = candidate
					break
			if next_index == -1:
				break
			current_index = next_index
		if loop.size() > best_loop.size():
			best_loop = loop
	if best_loop.size() > 1 and best_loop[best_loop.size() - 1].distance_to(best_loop[0]) > 1.0:
		best_loop.append(best_loop[0])
	return best_loop

func _city_cell_component_center(component: Dictionary) -> Vector2:
	var total := Vector2.ZERO
	for cell_data in component.values():
		var cell: Dictionary = cell_data
		total += cell["center"]
	return total / float(maxi(1, component.size()))

func _wiggle_city_contour(
	loop: PackedVector2Array,
	center: Vector2,
	members: Array[Vector2i],
	boundary_edges: Array,
	inset: float,
	wobble_amplitude: float,
	seed: int
) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	var distance_along := 0.0
	for i in range(loop.size()):
		var point: Vector2 = loop[i]
		var next: Vector2 = loop[(i + 1) % loop.size()]
		var previous: Vector2 = loop[(i - 1 + loop.size()) % loop.size()]
		var tangent: Vector2 = (next - previous).normalized()
		var normal: Vector2 = center - point
		if normal.is_zero_approx():
			normal = Vector2(-tangent.y, tangent.x)
		else:
			normal = normal.normalized()
		var wave: float = _city_boundary_wave(distance_along, seed, wobble_amplitude)
		var candidate: Vector2 = point + normal * (10.0 + maxf(0.0, wave))
		result.append(_pull_point_inside_eroded_city(candidate, center, members, boundary_edges, inset))
		distance_along += point.distance_to(next)
	return result

func _cell_key(coord: Vector2i) -> String:
	return "%d:%d" % [coord.x, coord.y]

func _pull_path_inside_eroded_city(
	path: PackedVector2Array,
	center: Vector2,
	members: Array[Vector2i],
	boundary_edges: Array,
	inset: float
) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for point in path:
		result.append(_pull_point_inside_eroded_city(point, center, members, boundary_edges, inset))
	if result.size() > 1:
		result[result.size() - 1] = result[0]
	return result

func _pull_point_inside_eroded_city(
	point: Vector2,
	center: Vector2,
	members: Array[Vector2i],
	boundary_edges: Array,
	inset: float
) -> Vector2:
	if _point_inside_eroded_city(point, members, boundary_edges, inset):
		return point
	for step in range(1, 16):
		var candidate: Vector2 = point.lerp(center, float(step) / 15.0)
		if _point_inside_eroded_city(candidate, members, boundary_edges, inset):
			return candidate
	return center

func _smooth_closed_path(path: PackedVector2Array, passes: int) -> PackedVector2Array:
	if path.size() < 4 or passes <= 0:
		return path
	var current: PackedVector2Array = path.duplicate()
	if current[current.size() - 1].distance_to(current[0]) <= 1.0:
		current.remove_at(current.size() - 1)
	for _pass in range(passes):
		var next: PackedVector2Array = PackedVector2Array()
		var count: int = current.size()
		for i in range(count):
			var start: Vector2 = current[i]
			var end: Vector2 = current[(i + 1) % count]
			next.append(start.lerp(end, 0.25))
			next.append(start.lerp(end, 0.75))
		current = next
	current.append(current[0])
	return current

func _point_inside_eroded_city(point: Vector2, members: Array[Vector2i], boundary_edges: Array, inset: float) -> bool:
	return _point_inside_city_tiles(point, members) and _distance_to_city_boundary(point, boundary_edges) >= inset

func _distance_to_city_boundary(point: Vector2, boundary_edges: Array) -> float:
	var best := 1.0e20
	for edge_data in boundary_edges:
		var edge: Dictionary = edge_data
		var start: Vector2 = edge["start"]
		var end: Vector2 = edge["end"]
		var closest: Vector2 = _closest_point_on_segment(point, start, end)
		best = minf(best, point.distance_to(closest))
	return best

func _city_union_boundary_path(members: Array[Vector2i]) -> PackedVector2Array:
	var point_lookup: Dictionary = {}
	var edges: Array = _city_boundary_edges(members)
	for edge_data in edges:
		var edge: Dictionary = edge_data
		point_lookup[str(edge["start_key"])] = edge["start"]
		point_lookup[str(edge["end_key"])] = edge["end"]
	return _ordered_boundary_loop(edges, point_lookup)

func _city_directed_boundary_loop(edges: Array) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if edges.is_empty():
		return result

	var outgoing: Dictionary = {}
	for i in range(edges.size()):
		var edge: Dictionary = edges[i]
		var start_key: String = str(edge["start_key"])
		if not outgoing.has(start_key):
			outgoing[start_key] = []
		var indexes: Array = outgoing[start_key]
		indexes.append(i)
		outgoing[start_key] = indexes

	var start_index: int = _city_boundary_start_edge_index(edges)
	var current_index: int = start_index
	var used: Dictionary = {}
	for _guard in range(edges.size() + 2):
		if used.has(current_index):
			break
		used[current_index] = true
		var edge: Dictionary = edges[current_index]
		var start: Vector2 = edge["start"]
		var end: Vector2 = edge["end"]
		result.append(start)
		var next_indexes: Array = outgoing.get(str(edge["end_key"]), [])
		var next_index: int = _city_next_boundary_edge_index(edges, next_indexes, current_index, used)
		if next_index == -1:
			if result.size() == 0 or result[result.size() - 1].distance_to(end) > 1.0:
				result.append(end)
			break
		current_index = next_index
		if current_index == start_index:
			break
	if result.size() > 1 and result[result.size() - 1].distance_to(result[0]) > 1.0:
		result.append(result[0])
	return result

func _city_boundary_start_edge_index(edges: Array) -> int:
	var best_index := 0
	var best_point: Vector2 = edges[0]["start"]
	for i in range(1, edges.size()):
		var edge: Dictionary = edges[i]
		var point: Vector2 = edge["start"]
		if point.y < best_point.y or (is_equal_approx(point.y, best_point.y) and point.x < best_point.x):
			best_index = i
			best_point = point
	return best_index

func _city_next_boundary_edge_index(edges: Array, candidates: Array, current_index: int, used: Dictionary) -> int:
	var current_edge: Dictionary = edges[current_index]
	var current_start: Vector2 = current_edge["start"]
	var current_end: Vector2 = current_edge["end"]
	var current_direction: Vector2 = (current_end - current_start).normalized()
	var best_index := -1
	var best_score := 1.0e20
	for candidate_data in candidates:
		var candidate_index: int = int(candidate_data)
		if used.has(candidate_index):
			continue
		var candidate_edge: Dictionary = edges[candidate_index]
		var candidate_end: Vector2 = candidate_edge["end"]
		var candidate_direction: Vector2 = (candidate_end - current_end).normalized()
		var score: float = absf(current_direction.angle_to(candidate_direction))
		if score < best_score:
			best_score = score
			best_index = candidate_index
	return best_index

func _ordered_boundary_loop(edges: Array, point_lookup: Dictionary) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if edges.is_empty():
		return result

	var adjacency: Dictionary = {}
	for i in range(edges.size()):
		var edge: Dictionary = edges[i]
		_add_boundary_adjacency(adjacency, str(edge["start_key"]), i)
		_add_boundary_adjacency(adjacency, str(edge["end_key"]), i)

	var start_key: String = _boundary_start_key(adjacency, point_lookup)
	if start_key == "":
		return result

	var previous_key := ""
	var current_key := start_key
	for _guard in range(edges.size() + 2):
		result.append(point_lookup[current_key])
		var edge_indexes: Array = adjacency.get(current_key, [])
		if edge_indexes.is_empty():
			break
		var next_key := ""
		for edge_index_data in edge_indexes:
			var edge_index: int = int(edge_index_data)
			var edge: Dictionary = edges[edge_index]
			var candidate_key: String = _other_boundary_edge_key(edge, current_key)
			if candidate_key != previous_key:
				next_key = candidate_key
				break
		if next_key == "":
			break
		previous_key = current_key
		current_key = next_key
		if current_key == start_key:
			break
	return result

func _add_boundary_adjacency(adjacency: Dictionary, point_key: String, edge_index: int) -> void:
	if not adjacency.has(point_key):
		adjacency[point_key] = []
	var edge_indexes: Array = adjacency[point_key]
	edge_indexes.append(edge_index)
	adjacency[point_key] = edge_indexes

func _boundary_start_key(adjacency: Dictionary, point_lookup: Dictionary) -> String:
	var best_key := ""
	var best_point := Vector2.ZERO
	for point_key_data in adjacency.keys():
		var point_key: String = str(point_key_data)
		var point: Vector2 = point_lookup[point_key]
		if best_key == "" or point.y < best_point.y or (is_equal_approx(point.y, best_point.y) and point.x < best_point.x):
			best_key = point_key
			best_point = point
	return best_key

func _other_boundary_edge_key(edge: Dictionary, point_key: String) -> String:
	var start_key: String = str(edge["start_key"])
	var end_key: String = str(edge["end_key"])
	return end_key if point_key == start_key else start_key

func _city_inset_wiggled_boundary_path(
	boundary: PackedVector2Array,
	members: Array[Vector2i],
	inset: float,
	wobble_amplitude: float,
	seed: int
) -> PackedVector2Array:
	var anchors: PackedVector2Array = PackedVector2Array()
	var distance_along := 0.0
	for i in range(boundary.size()):
		var start: Vector2 = boundary[i]
		var end: Vector2 = boundary[(i + 1) % boundary.size()]
		var delta: Vector2 = end - start
		var length: float = delta.length()
		if length < 1.0:
			continue
		var tangent: Vector2 = delta / length
		var normal: Vector2 = Vector2(-tangent.y, tangent.x)
		var steps: int = maxi(1, int(ceil(length / CITY_BOUNDARY_SAMPLE_SPACING)))
		for step in range(steps):
			var t: float = float(step) / float(steps)
			var boundary_point: Vector2 = start.lerp(end, t)
			var inward: Vector2 = _city_inward_normal(boundary_point, normal, inset, members)
			var wave: float = _city_boundary_wave(distance_along + length * t, seed, wobble_amplitude)
			var candidate: Vector2 = boundary_point + inward * (inset + wave)
			if not _point_inside_city_tiles(candidate, members):
				candidate = boundary_point + inward * inset
			anchors.append(_pull_point_inside_city(candidate, members, boundary_point))
		distance_along += length

	if anchors.size() < 3:
		return anchors
	var smoothed: PackedVector2Array = _sample_closed_loop(anchors)
	return _pull_path_inside_city(smoothed, members)

func _city_inward_normal(boundary_point: Vector2, normal: Vector2, inset: float, members: Array[Vector2i]) -> Vector2:
	var plus: Vector2 = boundary_point + normal * inset
	var minus: Vector2 = boundary_point - normal * inset
	var plus_inside: bool = _point_inside_city_tiles(plus, members)
	var minus_inside: bool = _point_inside_city_tiles(minus, members)
	if plus_inside and not minus_inside:
		return normal
	if minus_inside and not plus_inside:
		return -normal
	var toward_center: Vector2 = _city_center_world(members) - boundary_point
	return normal if toward_center.is_zero_approx() else toward_center.normalized()

func _city_boundary_wave(distance_along: float, seed: int, amplitude: float) -> float:
	if amplitude <= 0.0:
		return 0.0
	var seed_value: float = float(seed)
	var value: float = (
		sin(distance_along * 0.026 + seed_value * 0.017)
		+ sin(distance_along * 0.049 + seed_value * 0.031) * 0.6
		+ sin(distance_along * 0.083 + seed_value * 0.007) * 0.35
	)
	return clampf(value * amplitude * 0.45, -CITY_BOUNDARY_WOBBLE_LIMIT, CITY_BOUNDARY_WOBBLE_LIMIT)

func _pull_path_inside_city(path: PackedVector2Array, members: Array[Vector2i]) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for point in path:
		result.append(_pull_point_inside_city(point, members, point))
	if result.size() > 1 and result[result.size() - 1].distance_to(result[0]) <= CITY_BOUNDARY_SAMPLE_SPACING:
		result[result.size() - 1] = result[0]
	return result

func _pull_point_inside_city(point: Vector2, members: Array[Vector2i], fallback: Vector2) -> Vector2:
	if _point_inside_city_tiles(point, members):
		return point
	var center: Vector2 = _city_center_world(members)
	for step in range(1, 13):
		var candidate: Vector2 = point.lerp(center, float(step) / 12.0)
		if _point_inside_city_tiles(candidate, members):
			return candidate
	if _point_inside_city_tiles(fallback, members):
		return fallback
	return center

func _city_center_world(members: Array[Vector2i]) -> Vector2:
	var total := Vector2.ZERO
	for tile_coord in members:
		total += _tile_world_center(tile_coord)
	return total / float(maxi(1, members.size()))

func _point_inside_city_tiles(point: Vector2, members: Array[Vector2i]) -> bool:
	for tile_coord in members:
		if _point_inside_polygon(point, _hex_corners_world(tile_coord)):
			return true
	return false

func _hex_corners_world(tile_coord: Vector2i) -> PackedVector2Array:
	var center: Vector2 = _tile_world_center(tile_coord)
	var local_corners: PackedVector2Array = PackedVector2Array([
		Vector2(270, 0),
		Vector2(540, 120),
		Vector2(540, 360),
		Vector2(270, 480),
		Vector2(0, 360),
		Vector2(0, 120),
	])
	var result: PackedVector2Array = PackedVector2Array()
	for corner in local_corners:
		result.append(center + corner - TILE_CENTER)
	return result

func _point_inside_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	var inside := false
	var previous_index: int = polygon.size() - 1
	for i in range(polygon.size()):
		var current: Vector2 = polygon[i]
		var previous: Vector2 = polygon[previous_index]
		var crosses_y: bool = (current.y > point.y) != (previous.y > point.y)
		if crosses_y:
			var intersection_x: float = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
			if point.x < intersection_x:
				inside = not inside
		previous_index = i
	return inside

func _undirected_point_pair_key(a: Vector2, b: Vector2) -> String:
	var a_key: String = _point_key(a)
	var b_key: String = _point_key(b)
	return "%s|%s" % [a_key, b_key] if a_key < b_key else "%s|%s" % [b_key, a_key]

func _point_key(point: Vector2) -> String:
	return "%d:%d" % [roundi(point.x * 10.0), roundi(point.y * 10.0)]

func _add_city_boundary_connectors(plan: Dictionary, city_id: String, members: Array[Vector2i], beltway: PackedVector2Array) -> void:
	if beltway.size() < 2:
		return
	var member_lookup: Dictionary = {}
	for member in members:
		member_lookup[member] = true

	for tile_coord in members:
		var road_hsms: Array[String] = _road_hsms_for_tile(tile_coord)
		for hsm in road_hsms:
			var neighbor_coord: Vector2i = tile_coord + _neighbor_offset_for_hsm(tile_coord, hsm)
			if member_lookup.has(neighbor_coord):
				continue
			var anchor: Vector2 = _road_anchor_world(tile_coord, hsm)
			var beltway_point: Vector2 = _closest_point_on_path(anchor, beltway)
			_add_direct_edge(plan, _sample_city_connector_path(anchor, beltway_point, members), ROAD_WIDTH, "city_connector")
			var junctions: Array = plan["junctions"]
			junctions.append({"point": beltway_point, "radius": JUNCTION_RADIUS})

func _sample_city_connector_path(start: Vector2, end: Vector2, members: Array[Vector2i]) -> PackedVector2Array:
	var sampled: PackedVector2Array = _sample_connector_path(start, end)
	if sampled.size() <= 2:
		return sampled
	var result: PackedVector2Array = PackedVector2Array()
	result.append(sampled[0])
	for i in range(1, sampled.size() - 1):
		result.append(_pull_point_inside_city(sampled[i], members, sampled[i]))
	result.append(sampled[sampled.size() - 1])
	return result

func _add_city_interior_streets(plan: Dictionary, city_id: String, members: Array[Vector2i], beltway: PackedVector2Array) -> void:
	var city_data: Dictionary = _city_data(city_id)
	var interior_count: int = int(city_data.get("interior_grid_lines", 0))
	if interior_count <= 0 or members.size() < 2 or beltway.size() < 2:
		return

	for i in range(members.size()):
		for j in range(i + 1, members.size()):
			if not _tiles_share_side(members[i], members[j]):
				continue
			var start: Vector2 = _tile_world_center(members[i])
			var end: Vector2 = _tile_world_center(members[j])
			_add_direct_edge(plan, _sample_city_street_inside(start, end, members, _city_seed(city_id, members) + i * 17 + j * 31), ROAD_WIDTH, "city_cross_street")

func _sample_city_street_inside(start: Vector2, end: Vector2, members: Array[Vector2i], seed: int) -> PackedVector2Array:
	var path: PackedVector2Array = PackedVector2Array()
	var delta: Vector2 = end - start
	var normal: Vector2 = Vector2(-delta.y, delta.x).normalized()
	for step in range(9):
		var t: float = float(step) / 8.0
		var point: Vector2 = start.lerp(end, t)
		var wave: float = sin(t * PI) * sin(float(seed) * 0.013 + t * TAU) * 8.0
		path.append(_pull_point_inside_city(point + normal * wave, members, point))
	return path

func _tiles_share_side(a: Vector2i, b: Vector2i) -> bool:
	for hsm in HSM_ORDER:
		if a + _neighbor_offset_for_hsm(a, hsm) == b:
			return true
	return false

func _city_seed(city_id: String, members: Array[Vector2i]) -> int:
	var seed := 0
	for character_index in range(city_id.length()):
		seed += city_id.unicode_at(character_index) * (character_index + 17)
	for tile_coord in members:
		seed += (tile_coord.x + 1) * 73856093 ^ (tile_coord.y + 1) * 19349663
	return abs(seed)

func _sort_tile_coord(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)

func _new_graph(river_path: PackedVector2Array) -> Dictionary:
	return {
		"nodes": [],
		"edges": [],
		"next_node_id": 1,
		"river_path": river_path,
		"bridges": [],
		"main_hsms": [],
	}

func _add_hsm_nodes(graph: Dictionary, tile_coord: Vector2i, road_hsms: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for hsm in road_hsms:
		result[hsm] = _add_node(graph, _road_anchor_world(tile_coord, hsm), "hsm")
	return result

func _build_simple_road_plan(tile_coord: Vector2i, road_hsms: Array[String]) -> Dictionary:
	var plan: Dictionary = {"edges": [], "bridges": [], "junctions": []}
	if road_hsms.is_empty():
		return plan
	if road_hsms.size() == 1:
		var anchor: Vector2 = _road_anchor_world(tile_coord, road_hsms[0])
		var destination: Vector2 = _single_exit_destination(tile_coord, anchor)
		_add_direct_edge(plan, _sample_connector_path(anchor, destination), ROAD_WIDTH, "simple_spur")
		return plan
	if road_hsms.size() == 2:
		var start: Vector2 = _road_anchor_world(tile_coord, road_hsms[0])
		var end: Vector2 = _road_anchor_world(tile_coord, road_hsms[1])
		_add_direct_edge(plan, _sample_simple_pair_path(tile_coord, road_hsms[0], road_hsms[1], start, end), ROAD_WIDTH, "simple_through")
		return plan

	var pair: Array[String] = _most_opposite_hsm_pair(road_hsms)
	var junction: Vector2 = _tile_world_center(tile_coord)
	var spine: PackedVector2Array = _sample_template_path(PackedVector2Array([
		_road_anchor_world(tile_coord, pair[0]),
		junction,
		_road_anchor_world(tile_coord, pair[1]),
	]))
	_add_direct_edge(plan, spine, ROAD_WIDTH, "simple_spine")
	for hsm in road_hsms:
		if pair.has(hsm):
			continue
		var branch: PackedVector2Array = _sample_connector_path(_road_anchor_world(tile_coord, hsm), junction)
		_add_direct_edge(plan, branch, ROAD_WIDTH, "simple_branch")
	var junctions: Array = plan["junctions"]
	junctions.append({"point": junction, "radius": JUNCTION_RADIUS})
	return plan

func _single_exit_destination(tile_coord: Vector2i, anchor: Vector2) -> Vector2:
	var center: Vector2 = _tile_world_center(tile_coord)
	return anchor.lerp(center, 0.55)

func _sample_simple_pair_path(tile_coord: Vector2i, hsm_a: String, hsm_b: String, start: Vector2, end: Vector2) -> PackedVector2Array:
	if _hsms_are_adjacent(hsm_a, hsm_b):
		var junction: Vector2 = _junction_point_for_pair(tile_coord, start, end)
		return _sample_template_path(PackedVector2Array([start, junction, end]))
	return _sample_connector_path(start, end)

func _build_dense_loop_plan(tile_coord: Vector2i, road_hsms: Array[String]) -> Dictionary:
	var plan: Dictionary = {"edges": [], "bridges": [], "junctions": []}
	var loop_path: PackedVector2Array = _dense_loop_path(tile_coord)
	_add_direct_edge(plan, loop_path, ROAD_WIDTH, "dense_loop")
	_add_dense_loop_connectors(plan, tile_coord, road_hsms, loop_path)
	return plan

func _build_dense_grid_plan(tile_coord: Vector2i, road_hsms: Array[String]) -> Dictionary:
	var plan: Dictionary = {"edges": [], "bridges": [], "junctions": []}
	var x_world: Array[float] = _dense_grid_axis(tile_coord, DENSE_GRID_X_OFFSETS, true)
	var y_world: Array[float] = _dense_grid_axis(tile_coord, DENSE_GRID_Y_OFFSETS, false)
	var x_min: float = x_world[0]
	var x_max: float = x_world[x_world.size() - 1]
	var y_min: float = y_world[0]
	var y_max: float = y_world[y_world.size() - 1]

	for y in y_world:
		_add_direct_edge(plan, PackedVector2Array([Vector2(x_min, y), Vector2(x_max, y)]), ROAD_WIDTH, "dense_grid_h")
	for x in x_world:
		_add_direct_edge(plan, PackedVector2Array([Vector2(x, y_min), Vector2(x, y_max)]), ROAD_WIDTH, "dense_grid_v")

	var junctions: Array = plan["junctions"]
	for x in x_world:
		for y in y_world:
			junctions.append({"point": Vector2(x, y), "radius": JUNCTION_RADIUS})

	for hsm in road_hsms:
		var anchor: Vector2 = _road_anchor_world(tile_coord, hsm)
		var grid_point: Vector2 = _grid_attachment_for_hsm(hsm, x_world, y_world)
		_add_direct_edge(plan, _dense_grid_connector_path(anchor, grid_point), ROAD_WIDTH, "dense_grid_connector")

	return plan

func _build_dense_grid_river_plan(tile_coord: Vector2i, road_hsms: Array[String], river_path: PackedVector2Array) -> Dictionary:
	var plan: Dictionary = {"edges": [], "bridges": [], "junctions": []}
	var x_world: Array[float] = _dense_grid_axis(tile_coord, DENSE_GRID_X_OFFSETS, true)
	var y_world: Array[float] = _dense_grid_axis(tile_coord, DENSE_GRID_Y_OFFSETS, false)
	var x_min: float = x_world[0]
	var x_max: float = x_world[x_world.size() - 1]
	var y_min: float = y_world[0]
	var y_max: float = y_world[y_world.size() - 1]

	var side_signs: Array[float] = _road_hsm_side_signs(tile_coord, road_hsms, river_path)
	var bank_paths: Dictionary = {}
	for side_sign in side_signs:
		var bank_path: PackedVector2Array = _riverbank_template_path(river_path, side_sign, RIVER_ROAD_END_TRIM)
		bank_paths[side_sign] = bank_path
		_add_direct_edge(plan, bank_path, ROAD_WIDTH, "river_bank")

	var has_bridge := false
	var bridge_point := Vector2.ZERO
	if side_signs.size() >= 2:
		var grid_center := Vector2((x_min + x_max) * 0.5, (y_min + y_max) * 0.5)
		bridge_point = _closest_point_on_path(grid_center, river_path)
		var bridge_tangent: Vector2 = _bridge_tangent_for_river(river_path, bridge_point)
		var bridges: Array = plan["bridges"]
		bridges.append({"point": bridge_point, "tangent": bridge_tangent})
		has_bridge = true

		var left_bank: PackedVector2Array = bank_paths[side_signs[0]]
		var right_bank: PackedVector2Array = bank_paths[side_signs[1]]
		var left_point: Vector2 = _closest_point_on_path(bridge_point, left_bank)
		var right_point: Vector2 = _closest_point_on_path(bridge_point, right_bank)
		_add_direct_edge(plan, PackedVector2Array([left_point, bridge_point, right_point]), ROAD_WIDTH, "bridge_connector")

	var grid_lines: Array = []
	for y in y_world:
		grid_lines.append({
			"path": PackedVector2Array([Vector2(x_min, y), Vector2(x_max, y)]),
			"kind": "dense_grid_h",
		})
	for x in x_world:
		grid_lines.append({
			"path": PackedVector2Array([Vector2(x, y_min), Vector2(x, y_max)]),
			"kind": "dense_grid_v",
		})

	var bridge_line_index: int = -1
	if has_bridge:
		var best_distance: float = 1.0e20
		for i in range(grid_lines.size()):
			var line_path: PackedVector2Array = grid_lines[i]["path"]
			var candidate: Vector2 = _closest_point_on_segment(bridge_point, line_path[0], line_path[1])
			var distance: float = bridge_point.distance_to(candidate)
			if distance < best_distance:
				best_distance = distance
				bridge_line_index = i

	for i in range(grid_lines.size()):
		var line_path: PackedVector2Array = grid_lines[i]["path"]
		var kind: String = str(grid_lines[i]["kind"])
		_add_grid_line_avoiding_river(plan, line_path, river_path, i == bridge_line_index, bridge_point, kind)

	var junctions: Array = plan["junctions"]
	for x in x_world:
		for y in y_world:
			var point := Vector2(x, y)
			var river_distance: float = point.distance_to(_closest_point_on_path(point, river_path))
			if river_distance >= MIN_RIVER_PARALLEL_DISTANCE:
				junctions.append({"point": point, "radius": JUNCTION_RADIUS})

	for hsm in road_hsms:
		var anchor: Vector2 = _road_anchor_world(tile_coord, hsm)
		var grid_point: Vector2 = _grid_attachment_for_hsm(hsm, x_world, y_world)
		var connector: PackedVector2Array = _dense_grid_connector_path(anchor, grid_point)
		if _path_river_crossings(connector, river_path).is_empty():
			_add_direct_edge(plan, connector, ROAD_WIDTH, "dense_grid_connector")
			continue
		var side_sign: float = _river_side_sign(anchor, river_path)
		if not bank_paths.has(side_sign):
			continue
		var bank_point: Vector2 = _nearest_non_crossing_point_on_path(anchor, bank_paths[side_sign], river_path)
		var bank_connector: PackedVector2Array = _sample_connector_path(anchor, bank_point)
		if _path_river_crossings(bank_connector, river_path).is_empty():
			_add_direct_edge(plan, bank_connector, ROAD_WIDTH, "dense_grid_river_connector")

	return plan

func _dense_grid_axis(tile_coord: Vector2i, offsets: Array[float], use_x: bool) -> Array[float]:
	var center: Vector2 = _tile_world_center(tile_coord)
	var result: Array[float] = []
	for offset in offsets:
		result.append((center.x if use_x else center.y) + offset)
	return result

func _grid_attachment_for_hsm(hsm: String, x_world: Array[float], y_world: Array[float]) -> Vector2:
	var left: float = x_world[0]
	var middle: float = x_world[1]
	var right: float = x_world[x_world.size() - 1]
	var top: float = y_world[0]
	var bottom: float = y_world[y_world.size() - 1]
	match hsm:
		"HSM1":
			return Vector2(middle, top)
		"HSM2":
			return Vector2(right, top)
		"HSM3":
			return Vector2(right, bottom)
		"HSM4":
			return Vector2(middle, bottom)
		"HSM5":
			return Vector2(left, bottom)
		"HSM6":
			return Vector2(left, top)
		_:
			return Vector2(middle, (top + bottom) * 0.5)

func _dense_grid_connector_path(start: Vector2, end: Vector2) -> PackedVector2Array:
	var distance: float = start.distance_to(end)
	if distance < 50.0:
		return PackedVector2Array([start, end])
	var delta: Vector2 = end - start
	var normal: Vector2 = Vector2(-delta.y, delta.x).normalized()
	var bend: float = minf(distance * DENSE_GRID_CONNECTOR_BEND, DENSE_GRID_CONNECTOR_MAX_BEND)
	var control: Vector2 = (start + end) * 0.5 + normal * bend
	var path: PackedVector2Array = PackedVector2Array()
	path.append(start)
	for step in range(1, CURVE_STEPS + 1):
		var t: float = float(step) / float(CURVE_STEPS)
		path.append(_quadratic_bezier(start, control, end, t))
	return path

func _add_grid_line_avoiding_river(
	plan: Dictionary,
	line_path: PackedVector2Array,
	river_path: PackedVector2Array,
	is_bridge_line: bool,
	bridge_point: Vector2,
	kind: String
) -> void:
	if line_path.size() < 2:
		return
	var start: Vector2 = line_path[0]
	var end: Vector2 = line_path[1]
	var crossings: Array[Dictionary] = _path_river_crossings(line_path, river_path)
	if crossings.is_empty():
		_add_direct_edge(plan, line_path, ROAD_WIDTH, kind)
		return

	if is_bridge_line:
		_add_direct_edge(plan, PackedVector2Array([start, bridge_point, end]), ROAD_WIDTH, kind)
		return

	var crossing_point: Vector2 = crossings[0]["point"]
	var direction: Vector2 = (end - start).normalized()
	var stub_a_end: Vector2 = crossing_point - direction * DENSE_GRID_RIVER_STUB_TRIM
	var stub_b_start: Vector2 = crossing_point + direction * DENSE_GRID_RIVER_STUB_TRIM
	if start.distance_to(stub_a_end) > 8.0:
		_add_direct_edge(plan, PackedVector2Array([start, stub_a_end]), ROAD_WIDTH, kind)
	if stub_b_start.distance_to(end) > 8.0:
		_add_direct_edge(plan, PackedVector2Array([stub_b_start, end]), ROAD_WIDTH, kind)

func _build_dense_pattern_plan(tile_coord: Vector2i, road_hsms: Array[String]) -> Dictionary:
	if _loop_topology_allowed(road_hsms):
		return _build_dense_loop_plan(tile_coord, road_hsms)
	if _clustered_exit_pattern(road_hsms):
		return _build_dense_arc_plan(tile_coord, road_hsms)
	return _build_simple_road_plan(tile_coord, road_hsms)

func _build_dense_arc_plan(tile_coord: Vector2i, road_hsms: Array[String]) -> Dictionary:
	var plan: Dictionary = {"edges": [], "bridges": [], "junctions": []}
	var cluster: Array[String] = _largest_adjacent_cluster(road_hsms)
	if cluster.size() < 2:
		return _build_simple_road_plan(tile_coord, road_hsms)

	var arc_points: PackedVector2Array = PackedVector2Array()
	for hsm in cluster:
		arc_points.append(_dense_arc_point(tile_coord, hsm))
	if cluster.size() == 2:
		var midpoint: Vector2 = (arc_points[0] + arc_points[1]) * 0.5
		var center: Vector2 = _tile_world_center(tile_coord)
		arc_points.insert(1, midpoint.lerp(center, 0.22))
	var arc_path: PackedVector2Array = _sample_template_path(arc_points)
	_add_direct_edge(plan, arc_path, ROAD_WIDTH, "dense_arc")

	for hsm in road_hsms:
		var anchor: Vector2 = _road_anchor_world(tile_coord, hsm)
		var arc_point: Vector2 = _closest_point_on_path(anchor, arc_path)
		_add_direct_edge(plan, _sample_connector_path(anchor, arc_point), ROAD_WIDTH, "dense_arc_connector")
	return plan

func _dense_arc_point(tile_coord: Vector2i, hsm: String) -> Vector2:
	var center: Vector2 = _tile_world_center(tile_coord)
	var edge_point: Vector2 = HSM_POINTS[hsm]
	var distance_to_center: float = edge_point.distance_to(TILE_CENTER)
	var inset: float = clampf(DENSE_LOOP_BASE_INSET + 18.0, DENSE_LOOP_MIN_INSET, DENSE_LOOP_MAX_INSET)
	var local: Vector2 = edge_point.lerp(TILE_CENTER, inset / distance_to_center)
	return center + local - TILE_CENTER

func _build_dense_river_loop_plan(tile_coord: Vector2i, road_hsms: Array[String], river_path: PackedVector2Array) -> Dictionary:
	var plan: Dictionary = {"edges": [], "bridges": [], "junctions": []}
	var side_signs: Array[float] = _road_hsm_side_signs(tile_coord, road_hsms, river_path)
	var bank_paths: Dictionary = {}
	for side_sign in side_signs:
		var bank_path: PackedVector2Array = _riverbank_template_path(river_path, side_sign, RIVER_ROAD_END_TRIM)
		bank_paths[side_sign] = bank_path
		_add_direct_edge(plan, bank_path, ROAD_WIDTH, "river_bank")

	if side_signs.size() >= 2:
		var bridge_point: Vector2 = _bridge_point_for_road_hsms(tile_coord, road_hsms, river_path)
		var bridge_tangent: Vector2 = _bridge_tangent_for_river(river_path, bridge_point)
		var bridges: Array = plan["bridges"]
		bridges.append({"point": bridge_point, "tangent": bridge_tangent})
		var left_bank: PackedVector2Array = bank_paths[side_signs[0]]
		var right_bank: PackedVector2Array = bank_paths[side_signs[1]]
		var left_point: Vector2 = _closest_point_on_path(bridge_point, left_bank)
		var right_point: Vector2 = _closest_point_on_path(bridge_point, right_bank)
		_add_direct_edge(plan, PackedVector2Array([left_point, bridge_point, right_point]), ROAD_WIDTH, "bridge_connector")

	var loop_path: PackedVector2Array = _dense_loop_path(tile_coord)
	_add_loop_path_avoiding_river(plan, loop_path, river_path)
	_add_dense_river_connectors(plan, tile_coord, road_hsms, loop_path, bank_paths, river_path)
	return plan

func _add_dense_loop_connectors(plan: Dictionary, tile_coord: Vector2i, road_hsms: Array[String], loop_path: PackedVector2Array) -> void:
	for hsm in road_hsms:
		var anchor: Vector2 = _road_anchor_world(tile_coord, hsm)
		var loop_point: Vector2 = _closest_point_on_path(anchor, loop_path)
		_add_direct_edge(plan, _sample_connector_path(anchor, loop_point), ROAD_WIDTH, "dense_loop_connector")

func _add_dense_river_connectors(
	plan: Dictionary,
	tile_coord: Vector2i,
	road_hsms: Array[String],
	loop_path: PackedVector2Array,
	bank_paths: Dictionary,
	river_path: PackedVector2Array
) -> void:
	for hsm in road_hsms:
		var anchor: Vector2 = _road_anchor_world(tile_coord, hsm)
		var candidate_paths: Array = [loop_path]
		var side_sign: float = _river_side_sign(anchor, river_path)
		if bank_paths.has(side_sign):
			candidate_paths.append(bank_paths[side_sign])
		var connector: PackedVector2Array = _best_non_crossing_connector(anchor, candidate_paths, river_path)
		if not connector.is_empty():
			_add_direct_edge(plan, connector, ROAD_WIDTH, "dense_river_connector")

func _best_non_crossing_connector(source: Vector2, target_paths: Array, river_path: PackedVector2Array) -> PackedVector2Array:
	var best_path: PackedVector2Array = PackedVector2Array()
	var best_distance: float = 1.0e20
	for target_path_data in target_paths:
		var target_path: PackedVector2Array = target_path_data
		var target_point: Vector2 = _nearest_non_crossing_point_on_path(source, target_path, river_path)
		var connector: PackedVector2Array = _sample_connector_path(source, target_point)
		if not _path_river_crossings(connector, river_path).is_empty():
			continue
		var distance: float = source.distance_squared_to(target_point)
		if distance < best_distance:
			best_distance = distance
			best_path = connector
	return best_path

func _dense_loop_path(tile_coord: Vector2i) -> PackedVector2Array:
	var anchors: PackedVector2Array = _dense_loop_anchor_points(tile_coord)
	return _sample_closed_loop(anchors)

func _dense_loop_anchor_points(tile_coord: Vector2i) -> PackedVector2Array:
	var center: Vector2 = _tile_world_center(tile_coord)
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(HSM_ORDER.size()):
		var hsm: String = HSM_ORDER[i]
		var edge_point: Vector2 = HSM_POINTS[hsm]
		var distance_to_center: float = edge_point.distance_to(TILE_CENTER)
		var inset: float = clampf(
			DENSE_LOOP_BASE_INSET + _dense_loop_wave(tile_coord, edge_point.x, i),
			DENSE_LOOP_MIN_INSET,
			DENSE_LOOP_MAX_INSET
		)
		var local: Vector2 = edge_point.lerp(TILE_CENTER, inset / distance_to_center)
		points.append(center + local - TILE_CENTER)
	return points

func _dense_loop_wave(tile_coord: Vector2i, x: float, index: int) -> float:
	var seed: float = float(tile_coord.x * 31 + tile_coord.y * 47)
	var y: float = (
		10.0 * sin(0.023 * (x + seed))
		+ 7.0 * sin(0.041 * (x + seed * 0.7 + float(index) * 29.0))
		+ 5.0 * sin(0.067 * (x + seed * 1.3 + float(index) * 17.0))
	)
	return clampf(y, -DENSE_LOOP_WAVE_LIMIT, DENSE_LOOP_WAVE_LIMIT)

func _sample_closed_loop(anchors: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if anchors.size() < 3:
		return anchors
	var count: int = anchors.size()
	result.append(anchors[0])
	for i in range(count):
		var p0: Vector2 = anchors[(i - 1 + count) % count]
		var p1: Vector2 = anchors[i]
		var p2: Vector2 = anchors[(i + 1) % count]
		var p3: Vector2 = anchors[(i + 2) % count]
		for step in range(1, CURVE_STEPS + 1):
			var t: float = float(step) / float(CURVE_STEPS)
			result.append(_catmull_rom(p0, p1, p2, p3, t))
	if result[result.size() - 1].distance_to(result[0]) > 1.0:
		result.append(result[0])
	return result

func _add_loop_path_avoiding_river(plan: Dictionary, loop_path: PackedVector2Array, river_path: PackedVector2Array) -> void:
	if loop_path.size() < 2:
		return
	var current: PackedVector2Array = PackedVector2Array([loop_path[0]])
	for i in range(loop_path.size() - 1):
		var segment: PackedVector2Array = PackedVector2Array([loop_path[i], loop_path[i + 1]])
		if _path_river_crossings(segment, river_path).is_empty():
			current.append(loop_path[i + 1])
			continue
		if current.size() > 1:
			_add_direct_edge(plan, current, ROAD_WIDTH, "dense_loop")
		current = PackedVector2Array([loop_path[i + 1]])
	if current.size() > 1:
		_add_direct_edge(plan, current, ROAD_WIDTH, "dense_loop")

func _build_river_road_plan(tile_coord: Vector2i, road_hsms: Array[String], river_path: PackedVector2Array) -> Dictionary:
	var plan: Dictionary = {"edges": [], "bridges": [], "junctions": []}
	var side_signs: Array[float] = _road_hsm_side_signs(tile_coord, road_hsms, river_path)
	var bank_paths: Dictionary = {}
	for side_sign in side_signs:
		var bank_path: PackedVector2Array = _riverbank_template_path(river_path, side_sign, RIVER_ROAD_END_TRIM)
		bank_paths[side_sign] = bank_path
		_add_direct_edge(plan, bank_path, ROAD_WIDTH, "river_bank")

	if side_signs.size() >= 2:
		var bridge_point: Vector2 = _bridge_point_for_road_hsms(tile_coord, road_hsms, river_path)
		var bridge_tangent: Vector2 = _bridge_tangent_for_river(river_path, bridge_point)
		var bridges: Array = plan["bridges"]
		bridges.append({"point": bridge_point, "tangent": bridge_tangent})
		var left_bank: PackedVector2Array = bank_paths[side_signs[0]]
		var right_bank: PackedVector2Array = bank_paths[side_signs[1]]
		var left_point: Vector2 = _closest_point_on_path(bridge_point, left_bank)
		var right_point: Vector2 = _closest_point_on_path(bridge_point, right_bank)
		_add_direct_edge(plan, PackedVector2Array([left_point, bridge_point, right_point]), ROAD_WIDTH, "bridge_connector")

	for hsm in road_hsms:
		var anchor: Vector2 = _road_anchor_world(tile_coord, hsm)
		var side_sign: float = _river_side_sign(anchor, river_path)
		if not bank_paths.has(side_sign):
			continue
		var bank_path: PackedVector2Array = bank_paths[side_sign]
		var bank_point: Vector2 = _nearest_non_crossing_point_on_path(anchor, bank_path, river_path)
		var connector: PackedVector2Array = _sample_connector_path(anchor, bank_point)
		if _path_river_crossings(connector, river_path).is_empty():
			_add_direct_edge(plan, connector, ROAD_WIDTH, "river_hsm_connector")

	return plan

func _add_hsm_edge_stubs(plan: Dictionary, tile_coord: Vector2i, road_hsms: Array[String]) -> void:
	for hsm in road_hsms:
		var midpoint: Vector2 = _road_hsm_midpoint_world(tile_coord, hsm)
		var anchor: Vector2 = _road_anchor_world(tile_coord, hsm)
		if midpoint.distance_to(anchor) > 2.0:
			_add_direct_edge(plan, PackedVector2Array([midpoint, anchor]), ROAD_WIDTH, "hsm_edge_stub")

func _road_hsm_midpoint_world(tile_coord: Vector2i, hsm: String) -> Vector2:
	var center: Vector2 = _tile_world_center(tile_coord)
	return center + HSM_POINTS[hsm] - TILE_CENTER

func _nearest_non_crossing_point_on_path(source: Vector2, target_path: PackedVector2Array, river_path: PackedVector2Array) -> Vector2:
	var best_point: Vector2 = _closest_point_on_path(source, target_path)
	var best_distance: float = 1.0e20
	for candidate in target_path:
		var candidate_point: Vector2 = candidate
		var connector: PackedVector2Array = _sample_connector_path(source, candidate_point)
		if not _path_river_crossings(connector, river_path).is_empty():
			continue
		var distance: float = source.distance_squared_to(candidate_point)
		if distance < best_distance:
			best_distance = distance
			best_point = candidate_point
	return best_point

func _bridge_point_for_road_hsms(tile_coord: Vector2i, road_hsms: Array[String], river_path: PackedVector2Array) -> Vector2:
	var average_anchor := Vector2.ZERO
	for hsm in road_hsms:
		average_anchor += _road_anchor_world(tile_coord, hsm)
	average_anchor /= float(road_hsms.size())
	return _closest_point_on_path(average_anchor, river_path)

func _bridge_tangent_for_river(river_path: PackedVector2Array, bridge_point: Vector2) -> Vector2:
	var river_tangent: Vector2 = _path_tangent_near_point(river_path, bridge_point)
	if river_tangent.is_zero_approx():
		return Vector2.RIGHT
	return Vector2(-river_tangent.y, river_tangent.x).normalized()

func _road_hsm_side_signs(tile_coord: Vector2i, road_hsms: Array[String], river_path: PackedVector2Array) -> Array[float]:
	var result: Array[float] = []
	for hsm in road_hsms:
		var sign: float = _river_side_sign(_road_anchor_world(tile_coord, hsm), river_path)
		if not result.has(sign):
			result.append(sign)
	result.sort()
	return result

func _river_side_sign(point: Vector2, river_path: PackedVector2Array) -> float:
	var side_value: float = _river_side_value(point, river_path)
	if is_zero_approx(side_value):
		return 1.0
	return 1.0 if side_value > 0.0 else -1.0

func _validate_required_hsms_connected(plan: Dictionary, tile_coord: Vector2i, road_hsms: Array[String], river_path: PackedVector2Array) -> void:
	var bridges: Array = plan.get("bridges", [])
	for hsm in road_hsms:
		var anchor: Vector2 = _road_anchor_world(tile_coord, hsm)
		if _plan_touches_point(plan, anchor, GRAPH_NODE_MERGE_DISTANCE * 2.0):
			continue
		var snap: Dictionary = _nearest_point_on_plan(plan, anchor)
		if snap.is_empty():
			continue
		var snap_point: Vector2 = snap["point"]
		var path: PackedVector2Array = _sample_connector_path(anchor, snap_point)
		if _path_crossings_are_bound(path, river_path, bridges):
			_add_direct_edge(plan, path, ROAD_WIDTH, "required_hsm_repair")

func _force_hsm_connectivity(plan: Dictionary, tile_coord: Vector2i, road_hsms: Array[String], river_path: PackedVector2Array) -> void:
	var bridges: Array = plan.get("bridges", [])
	for hsm in road_hsms:
		var anchor: Vector2 = _road_anchor_world(tile_coord, hsm)
		if _plan_touches_point(plan, anchor, FORCED_HSM_TOUCH_DISTANCE):
			continue
		var snap: Dictionary = _nearest_point_on_plan(plan, anchor)
		if snap.is_empty():
			continue
		var snap_point: Vector2 = snap["point"]
		var candidate: PackedVector2Array = _sample_connector_path(anchor, snap_point)
		if river_path.is_empty():
			_add_direct_edge(plan, candidate, ROAD_WIDTH, "forced_hsm_connector")
			continue
		if _path_crossings_are_bound(candidate, river_path, bridges):
			_add_direct_edge(plan, candidate, ROAD_WIDTH, "forced_hsm_connector")
			continue
		if not bridges.is_empty():
			var via_bridge: Vector2 = _nearest_existing_bridge_point(bridges, anchor, snap_point)
			var through_path: PackedVector2Array = _sample_path_through_point(anchor, via_bridge, snap_point)
			if _path_crossings_are_bound(through_path, river_path, bridges):
				_add_direct_edge(plan, through_path, ROAD_WIDTH, "forced_hsm_connector")

func _plan_touches_point(plan: Dictionary, point: Vector2, max_distance: float) -> bool:
	var snap: Dictionary = _nearest_point_on_plan(plan, point)
	return not snap.is_empty() and float(snap["distance"]) <= max_distance

func _nearest_point_on_plan(plan: Dictionary, point: Vector2) -> Dictionary:
	var edges: Array = plan.get("edges", [])
	var best: Dictionary = {}
	var best_distance: float = 1.0e20
	for edge_index in range(edges.size()):
		var edge: Dictionary = edges[edge_index]
		var path: PackedVector2Array = edge["path"]
		for i in range(path.size() - 1):
			var candidate: Vector2 = _closest_point_on_segment(point, path[i], path[i + 1])
			var distance: float = point.distance_to(candidate)
			if distance < best_distance:
				best_distance = distance
				best = {"edge_index": edge_index, "point": candidate, "distance": distance}
	return best

func _load_road_templates() -> Dictionary:
	if not FileAccess.file_exists(ROAD_TEMPLATES_PATH):
		push_warning("Road templates JSON not found at %s." % ROAD_TEMPLATES_PATH)
		return {}
	var file := FileAccess.open(ROAD_TEMPLATES_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not open %s." % ROAD_TEMPLATES_PATH)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Road templates JSON did not parse to a dictionary.")
		return {}
	var templates: Dictionary = parsed
	return templates

func _road_type_for_tile(tile_data: Dictionary, road_hsms: Array[String]) -> String:
	var explicit_type: String = str(tile_data.get("road_type", "")).strip_edges()
	if explicit_type != "":
		return explicit_type
	return _inferred_road_type_for_hsms(road_hsms)

func _road_type_is_river_safe(road_type: String) -> bool:
	if road_type == "" or not _road_templates.has(road_type):
		return false
	var template: Dictionary = _road_templates.get(road_type, {})
	return bool(template.get("river_safe", false))

func _road_is_dense(tile_data: Dictionary, road_hsms: Array[String]) -> bool:
	var density: String = str(tile_data.get("road_density", "")).strip_edges().to_lower()
	if density == "dense" or density == "loop" or density == "urban" or density == "industrial":
		return true
	if density == "sparse" or density == "normal":
		return false
	var buildings: Array = tile_data.get("buildings_present", [])
	return road_hsms.size() >= 4 or buildings.size() >= 4

func _select_visible_road_hsms(road_hsms: Array[String], max_exits: int) -> Array[String]:
	var candidates: Array[String] = []
	for hsm in road_hsms:
		if HSM_ORDER.has(hsm) and not candidates.has(hsm):
			candidates.append(hsm)
	candidates.sort_custom(_sort_hsm_clockwise)
	if candidates.size() <= max_exits:
		return candidates
	if max_exits <= 0:
		var empty: Array[String] = []
		return empty
	if max_exits == 1:
		var single: Array[String] = [candidates[0]]
		return single

	return _best_spread_hsm_subset(candidates, max_exits)

func _best_spread_hsm_subset(candidates: Array[String], size: int) -> Array[String]:
	var combinations: Array = []
	var current: Array[String] = []
	_collect_hsm_combinations(candidates, size, 0, current, combinations)
	var best: Array[String] = []
	var best_score: float = -1.0e20
	for combination_data in combinations:
		var combination: Array[String] = []
		for hsm in combination_data:
			combination.append(str(hsm))
		var score: float = _hsm_spread_score(combination)
		if score > best_score:
			best_score = score
			best = combination.duplicate()
	best.sort_custom(_sort_hsm_clockwise)
	return best

func _collect_hsm_combinations(candidates: Array[String], size: int, start: int, current: Array[String], combinations: Array) -> void:
	if current.size() == size:
		combinations.append(current.duplicate())
		return
	for i in range(start, candidates.size()):
		current.append(candidates[i])
		_collect_hsm_combinations(candidates, size, i + 1, current, combinations)
		current.pop_back()

func _hsm_spread_score(road_hsms: Array[String]) -> float:
	var gaps: Array[int] = _clockwise_hsm_gaps(road_hsms)
	if gaps.is_empty():
		return -1.0e20
	var max_gap: int = int(gaps.max())
	var min_gap: int = int(gaps.min())
	var adjacent_gaps := 0
	for gap in gaps:
		if gap == 1:
			adjacent_gaps += 1
	return float((6 - max_gap) * 20 + min_gap * 10 - adjacent_gaps * 3)

func _loop_topology_allowed(road_hsms: Array[String]) -> bool:
	if road_hsms.size() < 3 or road_hsms.size() > DENSE_MAX_EXITS:
		return false
	var gaps: Array[int] = _clockwise_hsm_gaps(road_hsms)
	if gaps.is_empty():
		return false
	var max_gap: int = int(gaps.max())
	var max_cluster: int = _max_adjacent_cluster_size(road_hsms)
	return max_gap <= 2 and max_cluster <= 2

func _clustered_exit_pattern(road_hsms: Array[String]) -> bool:
	if road_hsms.size() < 2:
		return false
	if _loop_topology_allowed(road_hsms):
		return false
	return _max_adjacent_cluster_size(road_hsms) >= 2

func _clockwise_hsm_gaps(road_hsms: Array[String]) -> Array[int]:
	var indexes: Array[int] = _sorted_hsm_indexes(road_hsms)
	var gaps: Array[int] = []
	if indexes.size() < 2:
		return gaps
	for i in range(indexes.size()):
		var current: int = indexes[i]
		var next: int = indexes[(i + 1) % indexes.size()]
		var gap: int = next - current
		if gap <= 0:
			gap += HSM_ORDER.size()
		gaps.append(gap)
	return gaps

func _sorted_hsm_indexes(road_hsms: Array[String]) -> Array[int]:
	var indexes: Array[int] = []
	for hsm in road_hsms:
		var index: int = HSM_ORDER.find(hsm)
		if index >= 0 and not indexes.has(index):
			indexes.append(index)
	indexes.sort()
	return indexes

func _max_adjacent_cluster_size(road_hsms: Array[String]) -> int:
	var indexes: Array[int] = _sorted_hsm_indexes(road_hsms)
	if indexes.is_empty():
		return 0
	var present: Dictionary = {}
	for index in indexes:
		present[index] = true
	var best := 1
	for start in indexes:
		var count := 1
		var cursor: int = (start + 1) % HSM_ORDER.size()
		while present.has(cursor) and cursor != start:
			count += 1
			cursor = (cursor + 1) % HSM_ORDER.size()
		best = maxi(best, count)
	return best

func _largest_adjacent_cluster(road_hsms: Array[String]) -> Array[String]:
	var indexes: Array[int] = _sorted_hsm_indexes(road_hsms)
	var best_indexes: Array[int] = []
	if indexes.is_empty():
		var empty: Array[String] = []
		return empty
	var present: Dictionary = {}
	for index in indexes:
		present[index] = true
	for start in indexes:
		var cluster_indexes: Array[int] = [start]
		var cursor: int = (start + 1) % HSM_ORDER.size()
		while present.has(cursor) and cursor != start:
			cluster_indexes.append(cursor)
			cursor = (cursor + 1) % HSM_ORDER.size()
		if cluster_indexes.size() > best_indexes.size():
			best_indexes = cluster_indexes
	var result: Array[String] = []
	for index in best_indexes:
		result.append(HSM_ORDER[index])
	result.sort_custom(_sort_hsm_clockwise)
	return result

func _inferred_road_type_for_hsms(road_hsms: Array[String]) -> String:
	if road_hsms.size() == 2:
		var pair_type: String = _template_key_for_pair("STRAIGHT", road_hsms[0], road_hsms[1])
		if pair_type != "":
			return pair_type
		pair_type = _template_key_for_pair("BEND", road_hsms[0], road_hsms[1])
		if pair_type != "":
			return pair_type
	if road_hsms.size() >= 3 and _road_templates.has("T_JUNCTION_GENERIC"):
		return "T_JUNCTION_GENERIC"
	return ""

func _template_key_for_pair(prefix: String, a: String, b: String) -> String:
	var a_number: int = _hsm_number(a)
	var b_number: int = _hsm_number(b)
	if a_number == 0 or b_number == 0:
		return ""
	var forward_key: String = "%s_%d_%d" % [prefix, a_number, b_number]
	if _road_templates.has(forward_key):
		return forward_key
	var reverse_key: String = "%s_%d_%d" % [prefix, b_number, a_number]
	if _road_templates.has(reverse_key):
		return reverse_key
	return ""

func _hsm_number(hsm: String) -> int:
	var index: int = HSM_ORDER.find(hsm)
	return 0 if index == -1 else index + 1

func _build_template_plan(tile_coord: Vector2i, road_type: String, road_hsms: Array[String], river_path: PackedVector2Array) -> Dictionary:
	if not _road_templates.has(road_type):
		push_warning("Unknown road_type '%s' on %s." % [road_type, str(tile_coord)])
		return {}
	var template: Dictionary = _road_templates.get(road_type, {})
	var plan: Dictionary = {"edges": [], "bridges": [], "junctions": []}
	var mode: String = str(template.get("mode", "paths"))
	var built := false
	match mode:
		"auto_t_junction":
			built = _build_auto_t_template_plan(plan, tile_coord, road_hsms, river_path)
		"riverbank":
			built = _build_riverbank_template_plan(plan, template, river_path)
		_:
			built = _build_path_template_plan(plan, tile_coord, template, river_path)
	if not built:
		return plan
	_sanitize_plan_crossings(plan, river_path)
	return plan

func _build_path_template_plan(plan: Dictionary, tile_coord: Vector2i, template: Dictionary, river_path: PackedVector2Array) -> bool:
	var template_paths: Array = template.get("paths", [])
	for token_path in template_paths:
		var typed_path: Array = token_path
		_add_template_token_path(plan, tile_coord, typed_path, river_path, "template")
	return not plan.get("edges", []).is_empty()

func _build_auto_t_template_plan(plan: Dictionary, tile_coord: Vector2i, road_hsms: Array[String], river_path: PackedVector2Array) -> bool:
	if road_hsms.size() < 3:
		return false
	var pair: Array[String] = _most_opposite_hsm_pair(road_hsms)
	var junction: Vector2 = _template_junction_world(tile_coord, road_hsms, river_path)
	var spine_points := PackedVector2Array([_template_point_world(tile_coord, pair[0]), junction, _template_point_world(tile_coord, pair[1])])
	_add_template_points_path(plan, spine_points, river_path, "template_spine")
	for branch_hsm in road_hsms:
		if pair.has(branch_hsm):
			continue
		var branch_points := PackedVector2Array([_template_point_world(tile_coord, branch_hsm), junction])
		_add_template_points_path(plan, branch_points, river_path, "template_spur")
	var junctions: Array = plan["junctions"]
	junctions.append({"point": junction, "radius": JUNCTION_RADIUS})
	return not plan.get("edges", []).is_empty()

func _build_riverbank_template_plan(plan: Dictionary, template: Dictionary, river_path: PackedVector2Array) -> bool:
	if river_path.is_empty():
		return false
	var side: String = str(template.get("side", "left"))
	var side_sign := -1.0 if side == "left" else 1.0
	var path: PackedVector2Array = _riverbank_template_path(river_path, side_sign, RIVER_ROAD_END_TRIM)
	_add_direct_edge(plan, path, ROAD_WIDTH, "river_parallel")
	return true

func _riverbank_template_path(river_path: PackedVector2Array, side_sign: float, trim_distance: float = RIVER_EXIT_STOP_DISTANCE) -> PackedVector2Array:
	var trimmed: PackedVector2Array = _trim_path_ends(river_path, trim_distance)
	var result: PackedVector2Array = PackedVector2Array()
	for i in range(trimmed.size()):
		var tangent: Vector2 = _path_tangent_at_index(trimmed, i)
		var normal: Vector2 = Vector2(-tangent.y, tangent.x).normalized() * side_sign
		result.append(trimmed[i] + normal * ROAD_RIVER_HUG_DISTANCE)
	return result

func _add_template_token_path(plan: Dictionary, tile_coord: Vector2i, token_path: Array, river_path: PackedVector2Array, kind: String) -> void:
	var anchors: PackedVector2Array = PackedVector2Array()
	for token in token_path:
		anchors.append(_template_point_world(tile_coord, str(token)))
	_add_template_points_path(plan, anchors, river_path, kind)

func _add_template_points_path(plan: Dictionary, anchors: PackedVector2Array, river_path: PackedVector2Array, kind: String) -> void:
	var path: PackedVector2Array = _sample_template_path(anchors)
	path = _adapt_template_path_for_river(plan, path, river_path)
	if path.is_empty():
		return
	_add_direct_edge(plan, path, ROAD_WIDTH, kind)

func _template_junction_world(tile_coord: Vector2i, road_hsms: Array[String], river_path: PackedVector2Array) -> Vector2:
	var center: Vector2 = _tile_world_center(tile_coord)
	if river_path.is_empty():
		return center
	var average_anchor := Vector2.ZERO
	for hsm in road_hsms:
		average_anchor += _template_point_world(tile_coord, hsm)
	average_anchor /= float(road_hsms.size())
	var preferred_side: float = _river_side_value(average_anchor, river_path)
	var closest_data: Dictionary = _closest_point_and_tangent_on_path(center, river_path)
	var closest: Vector2 = closest_data["point"]
	var tangent: Vector2 = closest_data["tangent"]
	var normal: Vector2 = Vector2(-tangent.y, tangent.x).normalized()
	if preferred_side < 0.0:
		normal = -normal
	var candidate: Vector2 = closest + normal * (MIN_RIVER_PARALLEL_DISTANCE + 36.0)
	return _clamp_point_to_hex_world(tile_coord, candidate)

func _clamp_point_to_hex_world(tile_coord: Vector2i, point: Vector2) -> Vector2:
	var center: Vector2 = _tile_world_center(tile_coord)
	var local: Vector2 = point - center + TILE_CENTER
	local.x = clampf(local.x, 90.0, 450.0)
	local.y = clampf(local.y, 80.0, 400.0)
	return center + local - TILE_CENTER

func _template_point_world(tile_coord: Vector2i, token: String) -> Vector2:
	if HSM_POINTS.has(token):
		return _road_anchor_world(tile_coord, token)
	var center: Vector2 = _tile_world_center(tile_coord)
	return center + _river_point_local(token) - TILE_CENTER

func _sample_template_path(anchors: PackedVector2Array) -> PackedVector2Array:
	if anchors.size() < 2:
		return anchors
	if anchors.size() == 2:
		return PackedVector2Array([anchors[0], anchors[1]])
	var path: PackedVector2Array = PackedVector2Array()
	path.append(anchors[0])
	for i in range(anchors.size() - 1):
		var segment: PackedVector2Array = _sample_soft_path(anchors[i], anchors[i + 1])
		for j in range(1, segment.size()):
			path.append(segment[j])
	return _smooth_route_path(path)

func _adapt_template_path_for_river(plan: Dictionary, path: PackedVector2Array, river_path: PackedVector2Array) -> PackedVector2Array:
	if river_path.is_empty() or path.size() < 2:
		return path
	var bridges: Array = plan.get("bridges", [])
	if _path_crossings_are_bound(path, river_path, bridges):
		return path
	var crossings: Array[Dictionary] = _path_river_crossings(path, river_path)
	if crossings.is_empty():
		return path
	var start: Vector2 = path[0]
	var end: Vector2 = path[path.size() - 1]
	if _path_endpoints_same_river_side(start, end, river_path):
		var detour: PackedVector2Array = _same_bank_detour_path(path, river_path)
		return detour if _path_river_crossings(detour, river_path).is_empty() else PackedVector2Array()
	var bridge_point: Vector2 = Vector2.ZERO
	if bridges.size() < MAX_RIVER_CROSSINGS_PER_TILE:
		var crossing: Dictionary = crossings[0]
		bridge_point = crossing["point"]
		bridges.append({"point": bridge_point, "tangent": crossing["tangent"]})
		plan["bridges"] = bridges
	else:
		bridge_point = _nearest_existing_bridge_point(bridges, start, end)
	return _sample_path_through_point(start, bridge_point, end)

func _add_primary_spine(graph: Dictionary, tile_coord: Vector2i, road_hsms: Array[String], hsm_nodes: Dictionary) -> void:
	if road_hsms.size() == 2:
		graph["main_hsms"] = road_hsms.duplicate()
		_add_graph_routed_edge(graph, int(hsm_nodes[road_hsms[0]]), int(hsm_nodes[road_hsms[1]]), ROAD_WIDTH, "spine")
		return

	var pair: Array[String] = _most_opposite_hsm_pair(road_hsms)
	graph["main_hsms"] = pair.duplicate()
	_add_graph_routed_edge(graph, int(hsm_nodes[pair[0]]), int(hsm_nodes[pair[1]]), ROAD_WIDTH, "spine")

func _add_river_parallel_road_if_needed(graph: Dictionary, river_path: PackedVector2Array) -> void:
	if river_path.is_empty():
		return
	var edges: Array = graph["edges"]
	var needs_river_road: bool = false
	for edge in edges:
		var path: PackedVector2Array = edge["path"]
		if not _path_river_crossings(path, river_path).is_empty():
			needs_river_road = true
			break
	if not needs_river_road and edges.size() < 3:
		return
	var side_start: Vector2 = river_path[0]
	var side_end: Vector2 = river_path[river_path.size() - 1]
	if not edges.is_empty():
		var first_edge_path: PackedVector2Array = edges[0]["path"]
		side_start = first_edge_path[0]
		side_end = first_edge_path[first_edge_path.size() - 1]
	var parallel_path: PackedVector2Array = _parallel_path_for_points(side_start, side_end, river_path)
	var start_id: int = _add_node(graph, parallel_path[0], "river_road_end")
	var end_id: int = _add_node(graph, parallel_path[parallel_path.size() - 1], "river_road_end")
	_add_graph_edge(graph, start_id, end_id, parallel_path, ROAD_WIDTH, "river_parallel")

func _parallel_path_for_points(start: Vector2, end: Vector2, river_path: PackedVector2Array) -> PackedVector2Array:
	var trimmed: PackedVector2Array = _trim_path_end(river_path, RIVER_EXIT_STOP_DISTANCE)
	var side_sign: float = _river_parallel_side(start, end, river_path)
	var result: PackedVector2Array = PackedVector2Array()
	for i in range(trimmed.size()):
		var tangent: Vector2 = _path_tangent_at_index(trimmed, i)
		var normal: Vector2 = Vector2(-tangent.y, tangent.x).normalized() * side_sign
		result.append(trimmed[i] + normal * ROAD_RIVER_HUG_DISTANCE)
	return result

func _connect_remaining_hsms_to_graph(graph: Dictionary, road_hsms: Array[String], hsm_nodes: Dictionary) -> void:
	var main_hsms: Array = graph.get("main_hsms", [])
	for hsm in road_hsms:
		if main_hsms.has(hsm):
			continue
		var node_id: int = int(hsm_nodes[hsm])
		var point: Vector2 = _node_point(graph, node_id)
		if _hsm_connection_is_redundant(graph, point):
			continue
		_connect_optional_point_to_graph(graph, point, "hsm_spur", node_id)

func _add_local_grid_to_graph(graph: Dictionary, tile_coord: Vector2i, road_hsms: Array[String]) -> void:
	var grid_rect: Rect2 = _road_grid_world_rect(tile_coord)
	var left: float = grid_rect.position.x
	var right: float = grid_rect.end.x
	var top: float = grid_rect.position.y
	var bottom: float = grid_rect.end.y
	var mid_y: float = grid_rect.position.y + grid_rect.size.y * 0.5
	var step_x: float = grid_rect.size.x / float(GRID_CELLS.x)
	for i in range(GRID_CELLS.x + 1):
		var x: float = grid_rect.position.x + step_x * i
		var a: int = _add_node(graph, Vector2(x, top), "grid")
		var b: int = _add_node(graph, Vector2(x, bottom), "grid")
		_add_graph_edge(graph, a, b, PackedVector2Array([Vector2(x, top), Vector2(x, bottom)]), ROAD_WIDTH, "local_grid")
	for y in [top, mid_y, bottom]:
		var a: int = _add_node(graph, Vector2(left, y), "grid")
		var b: int = _add_node(graph, Vector2(right, y), "grid")
		_add_graph_edge(graph, a, b, PackedVector2Array([Vector2(left, y), Vector2(right, y)]), ROAD_WIDTH, "local_grid")
	for hsm in road_hsms:
		var anchor_id: int = _add_node(graph, _road_anchor_world(tile_coord, hsm), "hsm")
		_connect_required_point_to_graph(graph, _node_point(graph, anchor_id), "required_hsm_spur", anchor_id)

func _add_node(graph: Dictionary, point: Vector2, kind: String) -> int:
	var nodes: Array = graph["nodes"]
	for node in nodes:
		var existing: Vector2 = node["point"]
		if existing.distance_to(point) <= GRAPH_NODE_MERGE_DISTANCE:
			return int(node["id"])
	var id: int = int(graph["next_node_id"])
	graph["next_node_id"] = id + 1
	nodes.append({"id": id, "point": point, "kind": kind})
	return id

func _add_graph_routed_edge(graph: Dictionary, from_id: int, to_id: int, width: float, kind: String) -> void:
	var start: Vector2 = _node_point(graph, from_id)
	var end: Vector2 = _node_point(graph, to_id)
	var river_path: PackedVector2Array = graph.get("river_path", PackedVector2Array())
	var path: PackedVector2Array = _sample_soft_path(start, end)
	if not river_path.is_empty() and not _path_river_crossings(path, river_path).is_empty():
		if _path_endpoints_same_river_side(start, end, river_path):
			path = _same_bank_detour_path(path, river_path)
		else:
			path = _bind_path_to_graph_bridge(graph, path, river_path)
	_add_graph_edge(graph, from_id, to_id, path, width, kind)

func _bind_path_to_graph_bridge(graph: Dictionary, path: PackedVector2Array, river_path: PackedVector2Array) -> PackedVector2Array:
	var bridges: Array = graph["bridges"]
	var start: Vector2 = path[0]
	var end: Vector2 = path[path.size() - 1]
	var bridge_point: Vector2 = Vector2.ZERO
	if not bridges.is_empty():
		bridge_point = _nearest_existing_bridge_point(bridges, start, end)
	else:
		var crossings: Array[Dictionary] = _path_river_crossings(path, river_path)
		if crossings.is_empty():
			return path
		bridge_point = crossings[0]["point"]
		var bridge_id: int = _add_node(graph, bridge_point, "bridge")
		bridges.append({"point": bridge_point, "tangent": crossings[0]["tangent"], "node_id": bridge_id})
		graph["bridges"] = bridges
	if _path_endpoints_same_river_side(start, end, river_path):
		return _same_bank_detour_path(path, river_path)
	return _sample_path_through_point(start, bridge_point, end)

func _add_graph_edge(graph: Dictionary, from_id: int, to_id: int, path: PackedVector2Array, width: float, kind: String) -> void:
	if path.size() < 2 or from_id == to_id:
		return
	var edges: Array = graph["edges"]
	edges.append({"from": from_id, "to": to_id, "path": path, "width": width, "kind": kind})

func _connect_point_to_graph(graph: Dictionary, point: Vector2, max_distance: float, kind: String, existing_node_id: int = -1) -> bool:
	var snap: Dictionary = _nearest_point_on_graph(graph, point)
	if snap.is_empty() or float(snap["distance"]) > max_distance:
		return false
	var start_id: int = existing_node_id
	if start_id == -1:
		start_id = _add_node(graph, point, "spur_start")
	var snap_id: int = _split_edge_at_point(graph, int(snap["edge_index"]), snap["point"])
	_add_graph_routed_edge(graph, start_id, snap_id, ROAD_WIDTH, kind)
	return true

func _connect_required_point_to_graph(graph: Dictionary, point: Vector2, kind: String, existing_node_id: int) -> void:
	if _connect_point_to_graph(graph, point, REQUIRED_HSM_CONNECT_DISTANCE, kind, existing_node_id):
		return
	var nearest_id: int = _nearest_node_id(graph, point, existing_node_id)
	if nearest_id != -1:
		_add_graph_routed_edge(graph, existing_node_id, nearest_id, ROAD_WIDTH, kind)

func _connect_optional_point_to_graph(graph: Dictionary, point: Vector2, kind: String, existing_node_id: int) -> bool:
	var snap: Dictionary = _nearest_point_on_graph(graph, point)
	if snap.is_empty() or float(snap["distance"]) > OPTIONAL_HSM_CONNECT_DISTANCE:
		return false
	var snap_point: Vector2 = snap["point"]
	var candidate: PackedVector2Array = _sample_soft_path(point, snap_point)
	var river_path: PackedVector2Array = graph.get("river_path", PackedVector2Array())
	if not river_path.is_empty() and not _path_crossings_are_bound(candidate, river_path, graph.get("bridges", [])):
		return false
	if _candidate_duplicates_existing_edge(graph, candidate):
		return false
	var snap_id: int = _split_edge_at_point(graph, int(snap["edge_index"]), snap_point)
	_add_graph_edge(graph, existing_node_id, snap_id, candidate, ROAD_WIDTH, kind)
	return true

func _hsm_connection_is_redundant(graph: Dictionary, point: Vector2) -> bool:
	var snap: Dictionary = _nearest_point_on_graph(graph, point)
	if snap.is_empty():
		return false
	var distance: float = float(snap["distance"])
	return distance <= REDUNDANT_HSM_CONNECT_DISTANCE or distance > OPTIONAL_HSM_CONNECT_DISTANCE

func _candidate_duplicates_existing_edge(graph: Dictionary, candidate: PackedVector2Array) -> bool:
	var edges: Array = graph["edges"]
	for edge in edges:
		var path: PackedVector2Array = edge["path"]
		if _paths_are_near_duplicates(candidate, path):
			return true
	return false

func _nearest_point_on_graph(graph: Dictionary, point: Vector2) -> Dictionary:
	var edges: Array = graph["edges"]
	var best: Dictionary = {}
	var best_distance: float = 1.0e20
	for edge_index in range(edges.size()):
		var edge: Dictionary = edges[edge_index]
		var path: PackedVector2Array = edge["path"]
		for i in range(path.size() - 1):
			var candidate: Vector2 = _closest_point_on_segment(point, path[i], path[i + 1])
			var distance: float = point.distance_to(candidate)
			if distance < best_distance and distance > 1.0:
				best_distance = distance
				best = {"edge_index": edge_index, "point": candidate, "distance": distance}
	return best

func _nearest_node_id(graph: Dictionary, point: Vector2, excluded_id: int = -1) -> int:
	var nodes: Array = graph["nodes"]
	var best_id: int = -1
	var best_distance: float = 1.0e20
	for node in nodes:
		var node_id: int = int(node["id"])
		if node_id == excluded_id:
			continue
		var node_point: Vector2 = node["point"]
		var distance: float = point.distance_to(node_point)
		if distance < best_distance:
			best_distance = distance
			best_id = node_id
	return best_id

func _split_edge_at_point(graph: Dictionary, edge_index: int, point: Vector2) -> int:
	var edges: Array = graph["edges"]
	if edge_index < 0 or edge_index >= edges.size():
		return _add_node(graph, point, "snap")
	var edge: Dictionary = edges[edge_index]
	var snap_id: int = _add_node(graph, point, "snap")
	var from_id: int = int(edge["from"])
	var to_id: int = int(edge["to"])
	if snap_id == from_id or snap_id == to_id:
		return snap_id
	edges.remove_at(edge_index)
	var split_paths: Array = _split_path_at_point(edge["path"], point)
	_add_graph_edge(graph, from_id, snap_id, split_paths[0], float(edge["width"]), str(edge["kind"]))
	_add_graph_edge(graph, snap_id, to_id, split_paths[1], float(edge["width"]), str(edge["kind"]))
	return snap_id

func _split_path_at_point(path: PackedVector2Array, point: Vector2) -> Array:
	var best_index: int = 0
	var best_distance: float = 1.0e20
	for i in range(path.size() - 1):
		var candidate: Vector2 = _closest_point_on_segment(point, path[i], path[i + 1])
		var distance: float = point.distance_to(candidate)
		if distance < best_distance:
			best_distance = distance
			best_index = i
	var first: PackedVector2Array = PackedVector2Array()
	var second: PackedVector2Array = PackedVector2Array()
	for i in range(best_index + 1):
		first.append(path[i])
	if first[first.size() - 1].distance_to(point) > 0.5:
		first.append(point)
	second.append(point)
	for i in range(best_index + 1, path.size()):
		if path[i].distance_to(point) > 0.5:
			second.append(path[i])
	if second.size() == 1:
		second.append(path[path.size() - 1])
	return [first, second]

func _export_graph_to_plan(graph: Dictionary) -> Dictionary:
	var plan: Dictionary = {"edges": [], "bridges": graph.get("bridges", []), "junctions": []}
	var edges: Array = graph["edges"]
	for edge in edges:
		var exported_edges: Array = plan["edges"]
		var path: PackedVector2Array = edge["path"]
		if str(edge["kind"]) != "local_grid":
			path = _smooth_route_path(path)
		exported_edges.append({"path": path, "width": edge["width"], "kind": edge["kind"]})
	var nodes: Array = graph["nodes"]
	for node in nodes:
		var kind: String = str(node["kind"])
		if kind == "junction" or kind == "snap":
			var junctions: Array = plan["junctions"]
			junctions.append({"point": node["point"], "radius": JUNCTION_RADIUS})
	return plan

func _most_opposite_hsm_pair(road_hsms: Array[String]) -> Array[String]:
	var best_pair: Array[String] = [road_hsms[0], road_hsms[1]]
	var best_distance: int = -1
	for i in range(road_hsms.size()):
		for j in range(i + 1, road_hsms.size()):
			var index_a: int = HSM_ORDER.find(road_hsms[i])
			var index_b: int = HSM_ORDER.find(road_hsms[j])
			var distance: int = mini(abs(index_a - index_b), HSM_ORDER.size() - abs(index_a - index_b))
			if distance > best_distance:
				best_distance = distance
				best_pair = [road_hsms[i], road_hsms[j]]
	return best_pair

func _sample_path_through_point(start: Vector2, middle: Vector2, end: Vector2) -> PackedVector2Array:
	var result: PackedVector2Array = _sample_soft_path(start, middle)
	var second: PackedVector2Array = _sample_soft_path(middle, end)
	for i in range(1, second.size()):
		result.append(second[i])
	return result

func _prune_short_dead_ends(graph: Dictionary) -> void:
	var edges: Array = graph["edges"]
	var degrees: Dictionary = _graph_degrees(graph)
	for i in range(edges.size() - 1, -1, -1):
		var edge: Dictionary = edges[i]
		if _edge_is_required_boundary(graph, edge):
			continue
		var kind: String = str(edge["kind"])
		if kind != "spur" and kind != "local_spur" and kind != "bridge_connector" and kind != "hsm_spur":
			continue
		var from_degree: int = int(degrees.get(edge["from"], 0))
		var to_degree: int = int(degrees.get(edge["to"], 0))
		if from_degree > 1 and to_degree > 1:
			continue
		var path: PackedVector2Array = edge["path"]
		if _path_length(path) < SHORT_SPUR_PRUNE_LENGTH:
			edges.remove_at(i)
	graph["edges"] = edges

func _prune_duplicate_edges(graph: Dictionary) -> void:
	var edges: Array = graph["edges"]
	for i in range(edges.size() - 1, -1, -1):
		var edge_a: Dictionary = edges[i]
		if _edge_is_required_boundary(graph, edge_a):
			continue
		var path_a: PackedVector2Array = edge_a["path"]
		for j in range(0, i):
			var edge_b: Dictionary = edges[j]
			if _edge_is_required_boundary(graph, edge_b):
				continue
			var path_b: PackedVector2Array = edge_b["path"]
			if _paths_are_near_duplicates(path_a, path_b):
				edges.remove_at(i)
				break
	graph["edges"] = edges

func _graph_degrees(graph: Dictionary) -> Dictionary:
	var degrees: Dictionary = {}
	var edges: Array = graph["edges"]
	for edge in edges:
		var from_id: int = int(edge["from"])
		var to_id: int = int(edge["to"])
		degrees[from_id] = int(degrees.get(from_id, 0)) + 1
		degrees[to_id] = int(degrees.get(to_id, 0)) + 1
	return degrees

func _edge_touches_hsm(graph: Dictionary, edge: Dictionary) -> bool:
	return _node_kind(graph, int(edge["from"])) == "hsm" or _node_kind(graph, int(edge["to"])) == "hsm"

func _edge_is_required_boundary(graph: Dictionary, edge: Dictionary) -> bool:
	var kind: String = str(edge["kind"])
	return _edge_touches_hsm(graph, edge) and (kind == "spine" or kind == "required_hsm_spur")

func _paths_are_near_duplicates(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() < 2 or b.size() < 2:
		return false
	var a_start_to_b: float = minf(a[0].distance_to(b[0]), a[0].distance_to(b[b.size() - 1]))
	var a_end_to_b: float = minf(a[a.size() - 1].distance_to(b[0]), a[a.size() - 1].distance_to(b[b.size() - 1]))
	if a_start_to_b > DUPLICATE_EDGE_DISTANCE or a_end_to_b > DUPLICATE_EDGE_DISTANCE:
		return false
	var samples_close: int = 0
	for point in a:
		if point.distance_to(_closest_point_on_path(point, b)) <= DUPLICATE_EDGE_DISTANCE:
			samples_close += 1
	return samples_close >= maxi(2, int(a.size() / 2))

func _node_point(graph: Dictionary, node_id: int) -> Vector2:
	var nodes: Array = graph["nodes"]
	for node in nodes:
		if int(node["id"]) == node_id:
			return node["point"]
	return Vector2.ZERO

func _node_kind(graph: Dictionary, node_id: int) -> String:
	var nodes: Array = graph["nodes"]
	for node in nodes:
		if int(node["id"]) == node_id:
			return str(node["kind"])
	return ""

func _build_connected_plan(plan: Dictionary, route_context: Dictionary, tile_coord: Vector2i, road_hsms: Array[String]) -> void:
	road_hsms.sort_custom(_sort_hsm_clockwise)
	var adjacent_pairs: Array[Dictionary] = _adjacent_hsm_pairs(road_hsms)
	if adjacent_pairs.is_empty():
		for i in range(road_hsms.size()):
			var next_index: int = (i + 1) % road_hsms.size()
			_add_routed_edge(
				plan,
				route_context,
				tile_coord,
				_road_anchor_world(tile_coord, road_hsms[i]),
				_road_anchor_world(tile_coord, road_hsms[next_index]),
				ARTERIAL_WIDTH,
				"arterial"
			)
		return

	var pair: Dictionary = adjacent_pairs[0]
	var pair_a: String = str(pair["a"])
	var pair_b: String = str(pair["b"])
	var pair_anchor_a: Vector2 = _road_anchor_world(tile_coord, pair_a)
	var pair_anchor_b: Vector2 = _road_anchor_world(tile_coord, pair_b)
	var junction: Vector2 = _junction_point_for_pair(tile_coord, pair_anchor_a, pair_anchor_b)
	var junctions: Array = plan["junctions"]
	junctions.append({"point": junction, "radius": JUNCTION_RADIUS})

	_add_routed_edge(plan, route_context, tile_coord, pair_anchor_a, junction, ROAD_WIDTH, "feeder")
	_add_routed_edge(plan, route_context, tile_coord, pair_anchor_b, junction, ROAD_WIDTH, "feeder")

	var has_destination: bool = false
	for hsm in road_hsms:
		if hsm == pair_a or hsm == pair_b:
			continue
		has_destination = true
		_add_routed_edge(plan, route_context, tile_coord, junction, _road_anchor_world(tile_coord, hsm), ARTERIAL_WIDTH, "arterial")
	if not has_destination:
		var fallback_destination: Vector2 = _arterial_fallback_destination(tile_coord, pair_a, pair_b, junction)
		_add_routed_edge(plan, route_context, tile_coord, junction, fallback_destination, ARTERIAL_WIDTH, "arterial")

func _build_local_grid_plan(plan: Dictionary, route_context: Dictionary, tile_coord: Vector2i, road_hsms: Array[String]) -> void:
	var grid_rect: Rect2 = _road_grid_world_rect(tile_coord)
	var left: float = grid_rect.position.x
	var right: float = grid_rect.end.x
	var top: float = grid_rect.position.y
	var bottom: float = grid_rect.end.y
	var mid_y: float = grid_rect.position.y + grid_rect.size.y * 0.5
	var step_x: float = grid_rect.size.x / float(GRID_CELLS.x)

	for i in range(GRID_CELLS.x + 1):
		var x: float = grid_rect.position.x + step_x * i
		_add_direct_edge(plan, PackedVector2Array([Vector2(x, top), Vector2(x, bottom)]), ROAD_GRID_WIDTH, "local_grid")
	for y in [top, mid_y, bottom]:
		_add_direct_edge(plan, PackedVector2Array([Vector2(left, y), Vector2(right, y)]), ROAD_GRID_WIDTH, "local_grid")

	var connectors: Array[String] = road_hsms.duplicate()
	if connectors.is_empty():
		connectors.append("HSM1")
	for hsm in connectors:
		var anchor: Vector2 = _road_anchor_world(tile_coord, hsm)
		_add_routed_edge(plan, route_context, tile_coord, anchor, _nearest_grid_point(grid_rect, anchor), ROAD_WIDTH, "local_spur")

func _add_routed_edge(plan: Dictionary, route_context: Dictionary, tile_coord: Vector2i, start: Vector2, end: Vector2, width: float, kind: String) -> void:
	var ideal_path: PackedVector2Array = _sample_soft_path(start, end)
	var river_path: PackedVector2Array = route_context.get("river_path", PackedVector2Array())
	if river_path.is_empty() or _path_river_crossings(ideal_path, river_path).is_empty():
		_add_direct_edge(plan, ideal_path, width, kind)
		return

	var routed_paths: Array[Dictionary] = _route_crossing_edge(route_context, ideal_path, river_path, width, kind)
	for routed in routed_paths:
		_add_direct_edge(plan, routed["path"], float(routed["width"]), str(routed["kind"]))

func _route_crossing_edge(route_context: Dictionary, ideal_path: PackedVector2Array, river_path: PackedVector2Array, width: float, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start: Vector2 = ideal_path[0]
	var end: Vector2 = ideal_path[ideal_path.size() - 1]
	var crossings: Array[Dictionary] = _path_river_crossings(ideal_path, river_path)
	if crossings.is_empty():
		result.append({"path": ideal_path, "width": width, "kind": kind})
		return result

	if _path_endpoints_same_river_side(start, end, river_path):
		result.append({
			"path": _same_bank_detour_path(ideal_path, river_path),
			"width": width,
			"kind": kind,
		})
		return result

	var direct_distance: float = _path_length(ideal_path)
	var bridges: Array = route_context.get("bridges", [])
	if not bridges.is_empty():
		var existing_bridge_point: Vector2 = _nearest_existing_bridge_point(bridges, start, end)
		var existing_paths: Array[Dictionary] = _paths_using_parallel_road(route_context, start, existing_bridge_point, end, river_path, width, kind)
		var existing_distance: float = _paths_total_length(existing_paths)
		if existing_distance <= direct_distance * EXISTING_BRIDGE_MAX_DISTANCE_MULTIPLIER or bridges.size() >= MAX_RIVER_CROSSINGS_PER_TILE:
			_update_bridge_tangent(route_context, existing_bridge_point, _path_tangent_near_point(ideal_path, existing_bridge_point))
			return existing_paths

	if bridges.size() < MAX_RIVER_CROSSINGS_PER_TILE:
		var bridge_point: Vector2 = crossings[0]["point"]
		var bridge_tangent: Vector2 = crossings[0]["tangent"]
		bridges.append({"point": bridge_point, "tangent": bridge_tangent})
		route_context["bridges"] = bridges
		return _paths_using_parallel_road(route_context, start, bridge_point, end, river_path, width, kind)

	result.append({"path": _push_path_away_from_river(ideal_path, river_path), "width": width, "kind": kind})
	return result

func _paths_using_parallel_road(route_context: Dictionary, start: Vector2, bridge: Vector2, end: Vector2, river_path: PackedVector2Array, width: float, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var parallel_path: PackedVector2Array = _parallel_path_for_context(route_context, start, end, river_path)
	var bridge_attach: Vector2 = _closest_point_on_path(bridge, parallel_path)
	var exit_attach: Vector2 = _closest_point_on_path(end, parallel_path)
	var river_exit_attach: Vector2 = parallel_path[parallel_path.size() - 1]
	if end.distance_to(river_exit_attach) < end.distance_to(exit_attach) * EXISTING_BRIDGE_MAX_DISTANCE_MULTIPLIER:
		exit_attach = river_exit_attach

	result.append({"path": _sample_soft_path(start, bridge), "width": width, "kind": kind})
	result.append({"path": _sample_soft_path(bridge, bridge_attach), "width": width, "kind": "bridge_connector"})
	_add_parallel_edge_once(route_context, result, _parallel_subpath(parallel_path, bridge_attach, exit_attach), width)
	var exit_connector: PackedVector2Array = _sample_soft_path(exit_attach, end)
	if not _path_river_crossings(exit_connector, river_path).is_empty():
		exit_connector = _push_path_away_from_river(exit_connector, river_path)
	result.append({"path": exit_connector, "width": width, "kind": kind})
	return result

func _add_parallel_edge_once(route_context: Dictionary, result: Array[Dictionary], parallel_path: PackedVector2Array, width: float) -> void:
	var parallel_edges: Array = route_context.get("parallel_edges", [])
	if not parallel_edges.is_empty():
		return
	parallel_edges.append({"path": parallel_path})
	route_context["parallel_edges"] = parallel_edges
	result.append({"path": parallel_path, "width": width, "kind": "river_parallel"})

func _parallel_path_for_context(route_context: Dictionary, start: Vector2, end: Vector2, river_path: PackedVector2Array) -> PackedVector2Array:
	var parallel_edges: Array = route_context.get("parallel_edges", [])
	if not parallel_edges.is_empty():
		var existing: Dictionary = parallel_edges[0]
		return existing["path"]
	var trimmed: PackedVector2Array = _trim_path_end(river_path, RIVER_EXIT_STOP_DISTANCE)
	var side_sign: float = _river_parallel_side(start, end, river_path)
	var result: PackedVector2Array = PackedVector2Array()
	for i in range(trimmed.size()):
		var tangent: Vector2 = _path_tangent_at_index(trimmed, i)
		var normal: Vector2 = Vector2(-tangent.y, tangent.x).normalized() * side_sign
		result.append(trimmed[i] + normal * ROAD_RIVER_HUG_DISTANCE)
	return result

func _parallel_subpath(path: PackedVector2Array, start_point: Vector2, end_point: Vector2) -> PackedVector2Array:
	if path.size() < 2:
		return path
	var start_index: int = _nearest_path_index(path, start_point)
	var end_index: int = _nearest_path_index(path, end_point)
	var result: PackedVector2Array = PackedVector2Array()
	result.append(start_point)
	if start_index <= end_index:
		for i in range(start_index + 1, end_index + 1):
			result.append(path[i])
	else:
		for i in range(start_index - 1, end_index - 1, -1):
			result.append(path[i])
	if result[result.size() - 1].distance_to(end_point) > 1.0:
		result.append(end_point)
	return result

func _add_direct_edge(plan: Dictionary, path: PackedVector2Array, width: float, kind: String) -> void:
	if path.size() < 2:
		return
	var edges: Array = plan["edges"]
	edges.append({
		"path": path,
		"width": width,
		"kind": kind,
	})

func _sanitize_plan_crossings(plan: Dictionary, river_path: PackedVector2Array) -> void:
	if river_path.is_empty():
		return
	var bridges: Array = plan.get("bridges", [])
	var edges: Array = plan.get("edges", [])
	for i in range(edges.size() - 1, -1, -1):
		var edge: Dictionary = edges[i]
		var kind: String = str(edge.get("kind", ""))
		if kind == "river_parallel" or kind == "river_bank" or kind == "hsm_edge_stub" or kind == "local_grid":
			continue
		var path: PackedVector2Array = edge["path"]
		var candidate_path: PackedVector2Array = path
		if not _path_crossings_are_bound(candidate_path, river_path, bridges):
			if kind == "hsm_spur":
				edges.remove_at(i)
				continue
			candidate_path = _push_path_away_from_river(candidate_path, river_path)
			for _attempt in range(2):
				if _path_crossings_are_bound(candidate_path, river_path, bridges):
					break
				candidate_path = _push_path_away_from_river(candidate_path, river_path)
		var smoothed_path: PackedVector2Array = _smooth_route_path(candidate_path)
		if _path_crossings_are_bound(smoothed_path, river_path, bridges):
			candidate_path = smoothed_path
		edge["path"] = candidate_path
		edges[i] = edge
	plan["edges"] = edges

func _smooth_route_path(path: PackedVector2Array) -> PackedVector2Array:
	if path.size() < 3:
		return path
	var result: PackedVector2Array = PackedVector2Array()
	result.append(path[0])
	for i in range(path.size() - 1):
		var p0: Vector2 = path[maxi(i - 1, 0)]
		var p1: Vector2 = path[i]
		var p2: Vector2 = path[i + 1]
		var p3: Vector2 = path[mini(i + 2, path.size() - 1)]
		for step in range(1, 5):
			var t: float = float(step) / 4.0
			result.append(_catmull_rom(p0, p1, p2, p3, t))
	return result

func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return (
		(p1 * 2.0)
		+ (-p0 + p2) * t
		+ (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
		+ (-p0 + p1 * 3.0 - p2 * 3.0 + p3) * t3
	) * 0.5

func _path_crossings_are_bound(path: PackedVector2Array, river_path: PackedVector2Array, bridges: Array) -> bool:
	var crossings: Array[Dictionary] = _path_river_crossings(path, river_path)
	for crossing in crossings:
		var point: Vector2 = crossing["point"]
		if not _crossing_matches_bridge(point, bridges):
			return false
	return true

func _crossing_matches_bridge(point: Vector2, bridges: Array) -> bool:
	for bridge in bridges:
		var bridge_point: Vector2 = bridge["point"]
		if bridge_point.distance_to(point) <= BRIDGE_LENGTH:
			return true
	return false

func _road_grid_world_rect(tile_coord: Vector2i) -> Rect2:
	var river_data: Dictionary = _river_data_for_tile(tile_coord)
	var tile_id := _tile_id_for_coord(tile_coord)
	for row in range(10, 2, -1):
		for col in range(12, 2, -1):
			if _grid_fits(col, row, river_data, tile_id):
				return _grid_rect_from_subtiles(tile_coord, col, row)
	return _grid_rect_from_subtiles(tile_coord, 13, 12)

func _grid_fits(start_col: int, start_row: int, river_data: Dictionary, tile_id: String = "") -> bool:
	for row in range(start_row, start_row + GRID_CELLS.y):
		for col in range(start_col, start_col + GRID_CELLS.x):
			if not SubtileGrid.is_subtile_buildable(col, row, river_data, [], tile_id):
				return false
	return true

func _tile_id_for_coord(tile_coord: Vector2i) -> String:
	return "tile_%d_%d" % [tile_coord.x + 1, tile_coord.y + 1]

func _grid_rect_from_subtiles(tile_coord: Vector2i, start_col: int, start_row: int) -> Rect2:
	var center: Vector2 = _tile_world_center(tile_coord)
	var local_position: Vector2 = Vector2(float(start_col - 1) * SUBTILE_SIZE, float(start_row - 1) * SUBTILE_SIZE)
	return Rect2(center + local_position - TILE_CENTER, GRID_SIZE)

func _nearest_grid_point(grid_rect: Rect2, anchor: Vector2) -> Vector2:
	return Vector2(
		clampf(anchor.x, grid_rect.position.x, grid_rect.end.x),
		clampf(anchor.y, grid_rect.position.y, grid_rect.end.y)
	)

func _road_anchor_world(tile_coord: Vector2i, hsm: String) -> Vector2:
	var neighbor_coord: Vector2i = tile_coord + _neighbor_offset_for_hsm(tile_coord, hsm)
	var edge_key: String = _edge_key(tile_coord, neighbor_coord)
	if _shared_anchor_cache.has(edge_key):
		return _shared_anchor_cache[edge_key]

	var center: Vector2 = _tile_world_center(tile_coord)
	var midpoint: Vector2 = center + HSM_POINTS[hsm] - TILE_CENTER
	var anchor: Vector2 = midpoint
	var neighbor_hsm: String = str(OPPOSITE_HSM[hsm])
	if _tile_has_river_at_hsm(tile_coord, hsm) or _tile_has_river_at_hsm(neighbor_coord, neighbor_hsm):
		anchor = _offset_anchor_to_buildable_edge(tile_coord, neighbor_coord, midpoint, hsm)

	_shared_anchor_cache[edge_key] = anchor
	return anchor

func _offset_anchor_to_buildable_edge(tile_coord: Vector2i, neighbor_coord: Vector2i, midpoint: Vector2, hsm: String) -> Vector2:
	var tangent: Vector2 = _hsm_side_tangent(hsm)
	var distances: Array[float] = [
		ROAD_EDGE_OFFSET,
		-ROAD_EDGE_OFFSET,
		ROAD_EDGE_OFFSET * 2.0,
		-ROAD_EDGE_OFFSET * 2.0,
		ROAD_EDGE_OFFSET * 3.0,
		-ROAD_EDGE_OFFSET * 3.0,
		ROAD_EDGE_OFFSET * 4.0,
		-ROAD_EDGE_OFFSET * 4.0,
	]
	for distance in distances:
		var candidate: Vector2 = midpoint + tangent * distance
		if (
			_road_anchor_is_buildable(tile_coord, candidate)
			and _road_anchor_is_buildable(neighbor_coord, candidate)
			and _road_anchor_has_river_clearance(tile_coord, candidate)
			and _road_anchor_has_river_clearance(neighbor_coord, candidate)
		):
			return candidate
	for distance in distances:
		var candidate: Vector2 = midpoint + tangent * distance
		if _road_anchor_has_river_clearance(tile_coord, candidate) and _road_anchor_has_river_clearance(neighbor_coord, candidate):
			return candidate
	return midpoint

func _road_anchor_is_buildable(tile_coord: Vector2i, world_point: Vector2) -> bool:
	if not terrain_layer.tiles.has(tile_coord):
		return true
	var local_point: Vector2 = world_point - _tile_world_center(tile_coord) + TILE_CENTER
	var col: int = int(floor(local_point.x / SUBTILE_SIZE)) + 1
	var row: int = int(floor(local_point.y / SUBTILE_SIZE)) + 1
	if col < 1 or col > SubtileGrid.COLUMNS or row < 1 or row > SubtileGrid.ROWS:
		return false
	return SubtileGrid.is_subtile_buildable(col, row, _river_data_for_tile(tile_coord), [], _tile_id_for_coord(tile_coord))

func _road_anchor_has_river_clearance(tile_coord: Vector2i, world_point: Vector2) -> bool:
	var river_path: PackedVector2Array = _river_path_for_tile(tile_coord)
	if river_path.is_empty():
		return true
	var closest: Vector2 = _closest_point_on_path(world_point, river_path)
	return world_point.distance_to(closest) >= MIN_RIVER_ANCHOR_DISTANCE

func _sample_soft_path(start: Vector2, end: Vector2) -> PackedVector2Array:
	var delta: Vector2 = end - start
	var normal: Vector2 = Vector2(-delta.y, delta.x).normalized()
	var control_a: Vector2 = start + delta * 0.35 + normal * delta.length() * 0.08
	var control_b: Vector2 = start + delta * 0.68 - normal * delta.length() * 0.05
	var path: PackedVector2Array = PackedVector2Array()
	path.append(start)
	for step in range(1, CURVE_STEPS + 1):
		var t: float = float(step) / float(CURVE_STEPS)
		path.append(_cubic_bezier(start, control_a, control_b, end, t))
	return path

func _sample_connector_path(start: Vector2, end: Vector2) -> PackedVector2Array:
	var distance: float = start.distance_to(end)
	if distance < 120.0:
		return PackedVector2Array([start, end])

	var delta: Vector2 = end - start
	var midpoint: Vector2 = (start + end) * 0.5
	var normal: Vector2 = Vector2(-delta.y, delta.x).normalized()
	var control: Vector2 = midpoint + normal * minf(distance * 0.06, 18.0)
	var path: PackedVector2Array = PackedVector2Array()
	path.append(start)
	for step in range(1, CURVE_STEPS + 1):
		var t: float = float(step) / float(CURVE_STEPS)
		path.append(_quadratic_bezier(start, control, end, t))
	return path

func _quadratic_bezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var inverse_t: float = 1.0 - t
	return a * inverse_t * inverse_t + b * 2.0 * inverse_t * t + c * t * t

func _push_path_away_from_river(path: PackedVector2Array, river_path: PackedVector2Array) -> PackedVector2Array:
	var pushed: PackedVector2Array = PackedVector2Array()
	for i in range(path.size()):
		if i == 0 or i == path.size() - 1:
			pushed.append(path[i])
		else:
			pushed.append(_push_point_away_from_river(path[i], river_path, MIN_RIVER_PARALLEL_DISTANCE))
	return pushed

func _same_bank_detour_path(path: PackedVector2Array, river_path: PackedVector2Array) -> PackedVector2Array:
	var candidate: PackedVector2Array = path
	for _attempt in range(SAME_BANK_DETOUR_ATTEMPTS):
		if _path_river_crossings(candidate, river_path).is_empty():
			break
		candidate = _push_path_away_from_river(candidate, river_path)
	var smoothed: PackedVector2Array = _smooth_route_path(candidate)
	if _path_river_crossings(smoothed, river_path).is_empty():
		return smoothed
	return candidate

func _path_endpoints_same_river_side(start: Vector2, end: Vector2, river_path: PackedVector2Array) -> bool:
	var start_side: float = _river_side_value(start, river_path)
	var end_side: float = _river_side_value(end, river_path)
	if is_zero_approx(start_side) or is_zero_approx(end_side):
		return false
	return (start_side > 0.0 and end_side > 0.0) or (start_side < 0.0 and end_side < 0.0)

func _river_side_value(point: Vector2, river_path: PackedVector2Array) -> float:
	var closest_data: Dictionary = _closest_point_and_tangent_on_path(point, river_path)
	var closest: Vector2 = closest_data["point"]
	var tangent: Vector2 = closest_data["tangent"]
	return _cross(tangent, point - closest)

func _push_point_away_from_river(point: Vector2, river_path: PackedVector2Array, distance: float) -> Vector2:
	var closest_data: Dictionary = _closest_point_and_tangent_on_path(point, river_path)
	var closest: Vector2 = closest_data["point"]
	var away: Vector2 = point - closest
	if away.is_zero_approx():
		var tangent: Vector2 = closest_data["tangent"]
		away = Vector2(-tangent.y, tangent.x)
	else:
		away = away.normalized()
	if point.distance_to(closest) >= distance:
		return point
	return closest + away * distance

func _river_path_for_tile(tile_coord: Vector2i) -> PackedVector2Array:
	var river_data: Dictionary = _river_data_for_tile(tile_coord)
	if river_data.is_empty():
		return PackedVector2Array()
	return _river_curve_world_path(_tile_world_center(tile_coord), river_data)

func _river_data_for_tile(tile_coord: Vector2i) -> Dictionary:
	if not terrain_layer.tiles.has(tile_coord):
		return {}
	var tile_data: Dictionary = terrain_layer.tiles[tile_coord]
	var river_type: String = str(tile_data.get("river_type", ""))
	if river_type == "" or not terrain_layer.river_properties.has(river_type):
		return {}
	return terrain_layer.river_properties[river_type]

func _river_curve_world_path(tile_center: Vector2, river_data: Dictionary) -> PackedVector2Array:
	var point_ids: Array[String] = [
		str(river_data["entry_hsm"]),
		str(river_data["entry_square_point"]),
		str(river_data["center_point"]),
		str(river_data["exit_square_point"]),
		str(river_data["exit_hsm"]),
	]
	var anchors: PackedVector2Array = PackedVector2Array()
	for id in point_ids:
		anchors.append(tile_center + _river_point_local(id) - TILE_CENTER)
	var tangents: Array[Vector2] = _river_path_tangents(anchors, point_ids)
	var path: PackedVector2Array = PackedVector2Array()
	path.append(anchors[0])
	for i in range(anchors.size() - 1):
		var segment_length: float = anchors[i].distance_to(anchors[i + 1])
		var control_a: Vector2 = anchors[i] + tangents[i] * segment_length * POINT_TENSIONS[i]
		var control_b: Vector2 = anchors[i + 1] - tangents[i + 1] * segment_length * POINT_TENSIONS[i + 1]
		for step in range(1, CURVE_STEPS + 1):
			var t: float = float(step) / float(CURVE_STEPS)
			path.append(_cubic_bezier(anchors[i], control_a, control_b, anchors[i + 1], t))
	return path

func _river_point_local(point_id: String) -> Vector2:
	match point_id:
		"C0":
			return Vector2(270, 240)
		"S1":
			return Vector2(390, 120)
		"S2":
			return Vector2(390, 360)
		"S3":
			return Vector2(150, 360)
		"S4":
			return Vector2(150, 120)
		_:
			var hsm_point: Vector2 = HSM_POINTS.get(point_id, TILE_CENTER)
			return hsm_point

func _river_path_tangents(points: PackedVector2Array, point_ids: Array[String]) -> Array[Vector2]:
	var tangents: Array[Vector2] = []
	for i in range(points.size()):
		if i == 0:
			tangents.append(-_hsm_outward_direction(point_ids[i]))
		elif i == points.size() - 1:
			tangents.append(_hsm_outward_direction(point_ids[i]))
		else:
			var tangent: Vector2 = points[i + 1] - points[i - 1]
			if tangent.is_zero_approx():
				tangent = points[i + 1] - points[i]
			tangents.append(tangent.normalized())
	return tangents

func _hsm_outward_direction(hsm: String) -> Vector2:
	match hsm:
		"HSM1":
			return Vector2(0, -1)
		"HSM2":
			return Vector2(240, -135).normalized()
		"HSM3":
			return Vector2(240, 135).normalized()
		"HSM4":
			return Vector2(0, 1)
		"HSM5":
			return Vector2(-240, 135).normalized()
		"HSM6":
			return Vector2(-240, -135).normalized()
		_:
			return Vector2.ZERO

func _path_river_crossings(road_path: PackedVector2Array, river_path: PackedVector2Array) -> Array[Dictionary]:
	var crossings: Array[Dictionary] = []
	if road_path.size() < 2 or river_path.size() < 2:
		return crossings
	for i in range(road_path.size() - 1):
		for j in range(river_path.size() - 1):
			var crossing: Dictionary = _segment_intersection(road_path[i], road_path[i + 1], river_path[j], river_path[j + 1])
			if crossing.is_empty():
				continue
			var point: Vector2 = crossing["point"]
			if _crossing_is_distinct(crossings, point):
				crossings.append({
					"point": point,
					"tangent": (road_path[i + 1] - road_path[i]).normalized(),
					"order": i,
				})
	crossings.sort_custom(_sort_crossing_order)
	return crossings

func _segment_intersection(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Dictionary:
	var road_delta: Vector2 = b - a
	var river_delta: Vector2 = d - c
	var denominator: float = _cross(road_delta, river_delta)
	if is_zero_approx(denominator):
		return {}
	var difference: Vector2 = c - a
	var road_t: float = _cross(difference, river_delta) / denominator
	var river_t: float = _cross(difference, road_delta) / denominator
	if road_t < 0.0 or road_t > 1.0 or river_t < 0.0 or river_t > 1.0:
		return {}
	return {"point": a + road_delta * road_t}

func _crossing_is_distinct(crossings: Array[Dictionary], point: Vector2) -> bool:
	for crossing in crossings:
		var existing: Vector2 = crossing["point"]
		if existing.distance_to(point) < BRIDGE_LENGTH:
			return false
	return true

func _sort_crossing_order(a: Dictionary, b: Dictionary) -> bool:
	return int(a["order"]) < int(b["order"])

func _update_bridge_tangent(route_context: Dictionary, bridge_point: Vector2, tangent: Vector2) -> void:
	var bridges: Array = route_context.get("bridges", [])
	for i in range(bridges.size()):
		var bridge: Dictionary = bridges[i]
		var point: Vector2 = bridge["point"]
		if point.distance_to(bridge_point) < BRIDGE_LENGTH:
			bridge["tangent"] = tangent
			bridges[i] = bridge
			route_context["bridges"] = bridges
			return

func _nearest_existing_bridge_point(bridges: Array, start: Vector2, end: Vector2) -> Vector2:
	var best_point: Vector2 = (start + end) * 0.5
	var best_distance: float = 1.0e20
	for bridge in bridges:
		var point: Vector2 = bridge["point"]
		var distance: float = start.distance_squared_to(point) + end.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best_point = point
	return best_point

func _path_tangent_near_point(path: PackedVector2Array, point: Vector2) -> Vector2:
	var best_tangent: Vector2 = Vector2.RIGHT
	var best_distance: float = 1.0e20
	for i in range(path.size() - 1):
		var closest: Vector2 = _closest_point_on_segment(point, path[i], path[i + 1])
		var distance: float = closest.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best_tangent = (path[i + 1] - path[i]).normalized()
	return best_tangent

func _closest_point_on_path(point: Vector2, path: PackedVector2Array) -> Vector2:
	var closest_data: Dictionary = _closest_point_and_tangent_on_path(point, path)
	var closest: Vector2 = closest_data["point"]
	return closest

func _closest_point_and_tangent_on_path(point: Vector2, path: PackedVector2Array) -> Dictionary:
	var closest: Vector2 = path[0]
	var closest_tangent: Vector2 = Vector2.RIGHT
	var closest_distance: float = 1.0e20
	for i in range(path.size() - 1):
		var candidate: Vector2 = _closest_point_on_segment(point, path[i], path[i + 1])
		var distance: float = point.distance_squared_to(candidate)
		if distance < closest_distance:
			closest = candidate
			closest_tangent = (path[i + 1] - path[i]).normalized()
			closest_distance = distance
	return {"point": closest, "tangent": closest_tangent}

func _closest_point_on_segment(point: Vector2, start: Vector2, end: Vector2) -> Vector2:
	var segment: Vector2 = end - start
	var length_squared: float = segment.length_squared()
	if is_zero_approx(length_squared):
		return start
	var t: float = clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return start + segment * t

func _parallel_path_side_value(start: Vector2, end: Vector2, river_path: PackedVector2Array) -> float:
	var midpoint: Vector2 = (start + end) * 0.5
	var closest_data: Dictionary = _closest_point_and_tangent_on_path(midpoint, river_path)
	var closest: Vector2 = closest_data["point"]
	var tangent: Vector2 = closest_data["tangent"]
	var cross_value: float = _cross(tangent, midpoint - closest)
	if is_zero_approx(cross_value):
		return 1.0
	return 1.0 if cross_value > 0.0 else -1.0

func _river_parallel_side(start: Vector2, end: Vector2, river_path: PackedVector2Array) -> float:
	return _parallel_path_side_value(start, end, river_path)

func _trim_path_end(path: PackedVector2Array, trim_distance: float) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for point in path:
		result.append(point)
	if result.size() < 2 or trim_distance <= 0.0:
		return result
	var remaining: float = trim_distance
	while result.size() > 1 and remaining > 0.0:
		var last: Vector2 = result[result.size() - 1]
		var previous: Vector2 = result[result.size() - 2]
		var segment_length: float = previous.distance_to(last)
		if segment_length <= remaining:
			result.remove_at(result.size() - 1)
			remaining -= segment_length
		else:
			var direction: Vector2 = (last - previous).normalized()
			result[result.size() - 1] = last - direction * remaining
			remaining = 0.0
	return result

func _trim_path_ends(path: PackedVector2Array, trim_distance: float) -> PackedVector2Array:
	var trimmed_end: PackedVector2Array = _trim_path_end(path, trim_distance)
	var reversed_path: PackedVector2Array = PackedVector2Array()
	for i in range(trimmed_end.size() - 1, -1, -1):
		reversed_path.append(trimmed_end[i])
	var trimmed_start_reversed: PackedVector2Array = _trim_path_end(reversed_path, trim_distance)
	var result: PackedVector2Array = PackedVector2Array()
	for i in range(trimmed_start_reversed.size() - 1, -1, -1):
		result.append(trimmed_start_reversed[i])
	return result

func _path_tangent_at_index(path: PackedVector2Array, index: int) -> Vector2:
	if path.size() < 2:
		return Vector2.RIGHT
	if index <= 0:
		return (path[1] - path[0]).normalized()
	if index >= path.size() - 1:
		return (path[path.size() - 1] - path[path.size() - 2]).normalized()
	return (path[index + 1] - path[index - 1]).normalized()

func _nearest_path_index(path: PackedVector2Array, point: Vector2) -> int:
	var best_index: int = 0
	var best_distance: float = 1.0e20
	for i in range(path.size()):
		var distance: float = point.distance_squared_to(path[i])
		if distance < best_distance:
			best_distance = distance
			best_index = i
	return best_index

func _paths_total_length(paths: Array[Dictionary]) -> float:
	var total: float = 0.0
	for path_data in paths:
		var path: PackedVector2Array = path_data["path"]
		total += _path_length(path)
	return total

func _path_length(path: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	return total

func _tile_has_roads(tile_data: Dictionary) -> bool:
	var infrastructure: Array = tile_data.get("infrastructure_present", [])
	return infrastructure.has("roads")

func _tile_has_river_at_hsm(tile_coord: Vector2i, hsm: String) -> bool:
	if not terrain_layer.tiles.has(tile_coord):
		return false
	var tile_data: Dictionary = terrain_layer.tiles[tile_coord]
	if not tile_data.get("has_river", false):
		return false
	var river_data: Dictionary = _river_data_for_tile(tile_coord)
	if river_data.is_empty():
		return false
	return (
		str(river_data.get("entry_hsm", "")) == hsm
		or str(river_data.get("exit_hsm", "")) == hsm
		or str(river_data.get("exit_hsm_2", "")) == hsm
	)

func _road_hsms_for_tile(tile_coord: Vector2i) -> Array[String]:
	var tile_data: Dictionary = terrain_layer.tiles[tile_coord]
	var explicit: Array = tile_data.get("road_hsms", [])
	if not explicit.is_empty():
		var explicit_result: Array[String] = []
		for hsm in explicit:
			var hsm_name: String = str(hsm)
			if HSM_ORDER.has(hsm_name) and _road_hsm_is_valid_land_connection(tile_coord, hsm_name):
				explicit_result.append(hsm_name)
		return explicit_result

	var result: Array[String] = []
	for hsm in HSM_ORDER:
		var neighbor_coord: Vector2i = tile_coord + _neighbor_offset_for_hsm(tile_coord, hsm)
		if (
			_road_hsm_is_valid_land_connection(tile_coord, hsm)
			and terrain_layer.tiles.has(neighbor_coord)
			and _tile_has_roads(terrain_layer.tiles[neighbor_coord])
		):
			result.append(hsm)
	return result

func _road_hsm_is_valid_land_connection(tile_coord: Vector2i, hsm: String) -> bool:
	if not terrain_layer.tiles.has(tile_coord):
		return false
	var tile_data: Dictionary = terrain_layer.tiles[tile_coord]
	if not _tile_is_land(tile_data):
		return false
	var neighbor_coord: Vector2i = tile_coord + _neighbor_offset_for_hsm(tile_coord, hsm)
	if not terrain_layer.tiles.has(neighbor_coord):
		return false
	var neighbor_data: Dictionary = terrain_layer.tiles[neighbor_coord]
	return _tile_is_land(neighbor_data)

func _tile_is_land(tile_data: Dictionary) -> bool:
	var tile_type: String = str(tile_data.get("type", "")).strip_edges()
	return tile_type != "" and tile_type != "sea" and tile_type != "deep_sea"

func _adjacent_hsm_pairs(road_hsms: Array[String]) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	for i in range(road_hsms.size()):
		for j in range(i + 1, road_hsms.size()):
			if _hsms_are_adjacent(road_hsms[i], road_hsms[j]):
				pairs.append({
					"a": road_hsms[i],
					"b": road_hsms[j],
					"score": _hsm_adjacency_score(road_hsms[i], road_hsms[j]),
				})
	pairs.sort_custom(_sort_adjacent_pair)
	return pairs

func _hsms_are_adjacent(a: String, b: String) -> bool:
	var index_a: int = HSM_ORDER.find(a)
	var index_b: int = HSM_ORDER.find(b)
	if index_a < 0 or index_b < 0:
		return false
	var distance: int = abs(index_a - index_b)
	return distance == 1 or distance == HSM_ORDER.size() - 1

func _hsm_adjacency_score(a: String, b: String) -> int:
	var index_a: int = HSM_ORDER.find(a)
	var index_b: int = HSM_ORDER.find(b)
	return mini(abs(index_a - index_b), HSM_ORDER.size() - abs(index_a - index_b))

func _sort_adjacent_pair(a: Dictionary, b: Dictionary) -> bool:
	return int(a["score"]) < int(b["score"])

func _sort_hsm_clockwise(a: String, b: String) -> bool:
	return HSM_ORDER.find(a) < HSM_ORDER.find(b)

func _junction_point_for_pair(tile_coord: Vector2i, anchor_a: Vector2, anchor_b: Vector2) -> Vector2:
	var center: Vector2 = _tile_world_center(tile_coord)
	var edge_midpoint: Vector2 = (anchor_a + anchor_b) * 0.5
	return edge_midpoint.lerp(center, 0.34)

func _arterial_fallback_destination(tile_coord: Vector2i, pair_a: String, pair_b: String, junction: Vector2) -> Vector2:
	var center: Vector2 = _tile_world_center(tile_coord)
	var local_pair_a: Vector2 = HSM_POINTS[pair_a]
	var local_pair_b: Vector2 = HSM_POINTS[pair_b]
	var average_hsm: Vector2 = (local_pair_a + local_pair_b) * 0.5
	var inward: Vector2 = (TILE_CENTER - average_hsm).normalized()
	var local_destination: Vector2 = TILE_CENTER + inward * 135.0
	return (center + local_destination - TILE_CENTER).lerp(junction, 0.15)

func _neighbor_offset_for_hsm(tile_coord: Vector2i, hsm: String) -> Vector2i:
	var is_odd_column: bool = tile_coord.x % 2 == 1
	match hsm:
		"HSM1":
			return Vector2i(0, -1)
		"HSM2":
			return Vector2i(1, 0) if is_odd_column else Vector2i(1, -1)
		"HSM3":
			return Vector2i(1, 1) if is_odd_column else Vector2i(1, 0)
		"HSM4":
			return Vector2i(0, 1)
		"HSM5":
			return Vector2i(-1, 1) if is_odd_column else Vector2i(-1, 0)
		"HSM6":
			return Vector2i(-1, 0) if is_odd_column else Vector2i(-1, -1)
		_:
			return Vector2i.ZERO

func _hsm_side_tangent(hsm: String) -> Vector2:
	match hsm:
		"HSM1", "HSM4":
			return Vector2.RIGHT
		"HSM2", "HSM5":
			return Vector2(135, 240).normalized()
		"HSM3", "HSM6":
			return Vector2(-135, 240).normalized()
		_:
			return Vector2.RIGHT

func _tile_world_center(tile_coord: Vector2i) -> Vector2:
	return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(tile_coord))

func _edge_key(a: Vector2i, b: Vector2i) -> String:
	var first: Vector2i = a
	var second: Vector2i = b
	if second.x < first.x or (second.x == first.x and second.y < first.y):
		first = b
		second = a
	return "%d_%d:%d_%d" % [first.x, first.y, second.x, second.y]

func _cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x

func _cubic_bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var inverse_t: float = 1.0 - t
	return (
		a * inverse_t * inverse_t * inverse_t
		+ b * 3.0 * inverse_t * inverse_t * t
		+ c * 3.0 * inverse_t * t * t
		+ d * t * t * t
	)
